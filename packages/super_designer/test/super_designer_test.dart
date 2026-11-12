import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_designer/super_designer.dart';

void main() {
  final channels = [
    const MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  test(
    'createSuperDesignerRegistry registers both core engine and extensions',
    () {
      final registry = createSuperDesignerRegistry();

      // Composants du moteur super_container_layout
      expect(registry.registry.containsKey('Layout'), isTrue);
      expect(registry.registry.containsKey('Card'), isTrue);
      expect(registry.registry.containsKey('Value'), isTrue);
      expect(registry.registry.containsKey('Action'), isTrue);
      expect(registry.registry.containsKey('ListView'), isTrue);
      expect(registry.registry.containsKey('Tab'), isTrue);
      expect(registry.registry.containsKey('TreeView'), isTrue);
      expect(registry.registry.containsKey('Table'), isTrue);

      // Composants d'extension super_container_extensions
      expect(registry.registry.containsKey('Chart'), isTrue);
      expect(ComponentConfigCatalog.of('chart'), isNotNull);
    },
  );

  testWidgets(
    'SuperDesignerApp mounts SuperPage, FloatingAppearanceToolbar and registered extensions',
    (tester) async {
      await tester.pumpWidget(const SuperDesignerApp());
      await tester.pumpAndSettle();

      expect(find.byType(SuperPage), findsOneWidget);
      expect(find.byType(FloatingAppearanceToolbar), findsOneWidget);

      final superApp = tester.widget<SuperApp>(find.byType(SuperApp));
      expect(superApp.registry, isNotNull);
      expect(superApp.registry!.registry.containsKey('Layout'), isTrue);
      expect(superApp.registry!.registry.containsKey('Chart'), isTrue);
      expect(superApp.appearanceStore, isNull);
      expect(superApp.eventBus, isNotNull);

      final events = <SuperComponentEvent>[];
      final subscription = superApp.eventBus!
          .on('node.click')
          .listen(events.add);
      addTearDown(subscription.cancel);
      superApp
          .getLayoutConfigById('mainLayout')
          .value = const SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['explorer'],
        },
        slotTypes: {'explorer': 'registry:A'},
      );
      await superApp.repositoryStore!.replaceArray(
        'pan_model_repository',
        'nodes',
        [
          {
            'id': 'test-node',
            'name': 'Test node',
            'type': 'string',
            'typeIcon': 'value',
          },
          {
            'id': 'container-node',
            'name': 'Container node',
            'type': 'object',
            'typeIcon': 'container',
          },
        ],
      );
      await tester.pumpAndSettle();
      final indicatorIcons = tester
          .widgetList<Icon>(
            find.byKey(const ValueKey('super-indicator-icon-tree-node-icon')),
          )
          .map((icon) => icon.icon)
          .toList();
      expect(indicatorIcons, [
        Icons.description_outlined,
        Icons.folder_outlined,
      ]);
      final name = tester.widget<SuperValue>(
        find
            .byWidgetPredicate(
              (widget) => widget is SuperValue && widget.id == 'tree-node-name',
            )
            .first,
      );
      expect(name.behaviours, hasLength(1));
      expect(
        AppearanceScope.of(tester.element(find.byWidget(name)))
            .behaviorsFor('tree-node-name'),
        isEmpty,
      );
      const sizeBinding = JsonTextBinding(
        repositoryId: 'pan_model_repository',
        path: 'estSize',
      );
      final tree = find.byType(SuperTreeView);
      final initialTreeWidth = tester.getSize(tree).width;
      expect(
        (await superApp.repositoryStore!.readAttribute(sizeBinding)).value,
        300,
      );
      await tester.tap(find.text('Test node'));
      await tester.pumpAndSettle();

      expect(events, hasLength(1));
      expect(events.single.componentId, 'tree-node-name');
      expect(events.single.trigger, 'click');
      expect(events.single.data['value'], 'Test node');
      expect(
        (await superApp.repositoryStore!.readAttribute(sizeBinding)).value,
        0,
      );
      expect(tester.getSize(tree).width, closeTo(initialTreeWidth + 300, 1));

      await tester.tap(find.text('Test node'));
      await tester.pumpAndSettle();
      expect(events, hasLength(2));
      expect(
        (await superApp.repositoryStore!.readAttribute(sizeBinding)).value,
        300,
      );
      expect(tester.getSize(tree).width, closeTo(initialTreeWidth, 1));
    },
  );

  testWidgets(
    'main layout AI scope accepts and renders a patch targeting mainLayout',
    (tester) async {
      await tester.pumpWidget(const SuperDesignerApp());
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SuperPage));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      final center = tester
          .stateList<EditorSlotState>(find.byType(EditorSlot))
          .singleWhere(
            (slot) =>
                slot.widget.zoneId == 'center' &&
                slot.widget.menuSubtitle?.call() == 'Main Layout',
          );
      final scope = center.aiScope;
      expect(scope.canonicalComponentId, 'mainLayout');
      expect(scope.zoneId, 'center');

      final controller = AppearanceScope.controllerOf(context)!;
      final patch = VibeChatDialog.filterPatchToScope(controller.value, {
        'components': {
          'mainLayout': {
            'type': 'layout',
            'placements': {
              'center': [
                {'id': 'scope-title', 'type': 'registry:Value'},
              ],
            },
          },
          'scope-title': {'type': 'value', 'text': 'Scoped form title'},
        },
      }, scope);
      expect(
        (patch['components'] as Map).keys,
        containsAll(['mainLayout', 'scope-title']),
      );
      controller.value = AppearanceTransfer.applyVibe(
        controller.value,
        jsonEncode(patch),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scoped form title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'every edit target exports its own subtree, renderable by SuperRenderer',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SuperDesignerApp());
      await tester.pumpAndSettle();
      final superApp = tester.widget<SuperApp>(find.byType(SuperApp));
      superApp
          .getLayoutConfigById('mainLayout')
          .value = const SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['explorer'],
        },
        slotTypes: {'explorer': 'registry:A'},
      );
      await tester.pumpAndSettle();
      StyleEditScope.controllerOf(tester.element(find.byType(SuperPage)))!
              .value =
          true;
      await tester.pumpAndSettle();

      final exports = <String, EditorFragmentExport>{};
      for (final slot in tester.stateList<EditorSlotState>(
        find.byType(EditorSlot),
      )) {
        if (!slot.canEdit || slot.widget.identity is AppearanceSlot) continue;
        final key = '${slot.effectiveComponentId}|${slot.widget.zoneId}';
        exports.putIfAbsent(key, slot.buildContentExport);
      }
      // Corps du SuperPage (pseudo-slot `scaffold:body`) et layouts declares
      // en code, auparavant introuvables.
      expect(
        exports.keys,
        containsAll([
          'root|body',
          'scaffold:body|null',
          'explorer|null',
          'header|null',
        ]),
      );
      final body = exports['scaffold:body|null']!;
      expect(body.appearance.components.keys, isNot(contains('scaffold:body')));
      expect(body.appearance.components['body'], isA<SuperLayoutConfig>());
      expect(body.omitted, ['global-node-properties']);
      final header = exports['header|null']!.appearance;
      expect(
        header.components.keys,
        unorderedEquals([
          'header',
          'tree-node-icon',
          'tree-node-name',
          'tree-node-separator',
          'tree-node-type',
          '__export_root',
        ]),
      );
      for (final export in exports.values) {
        AppearanceTransfer.import(
          Appearance(),
          AppearanceTransfer.export(export.appearance, {
            ...TransferGroup.values,
          }),
          {...TransferGroup.values},
        );
      }

      final source = AppearanceTransfer.export(
        exports['explorer|null']!.appearance,
        {...TransferGroup.values},
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(body: SuperRenderer(source: source)),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        SuperApp(
          key: UniqueKey(),
          router: router,
          registry: createSuperDesignerRegistry(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SuperTreeView), findsOneWidget);
      expect(find.byType(SuperCode), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final name in ['Code', 'Chart']) {
    testWidgets('$name shares the component contract and code behaviours', (
      tester,
    ) async {
      final behaviours = [
        ComponentBehavior(
          id: 'click',
          trigger: BehaviorTrigger.click,
          action: EmitEventAction(eventId: 'extension.click'),
        ),
      ];
      final Widget component = name == 'Code'
          ? SuperCode(id: 'extension', behaviours: behaviours)
          : SuperChart(id: 'extension', behaviours: behaviours);
      expect(component, isA<SuperComponent<ComponentConfig>>());
      final events = <SuperComponentEvent>[];
      final bus = SuperEventBus();
      final subscription = bus.on('extension.click').listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await bus.close();
      });
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: SizedBox(width: 600, height: 400, child: component),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        SuperApp(
          router: router,
          registry: createSuperDesignerRegistry(),
          eventBus: bus,
        ),
      );
      await tester.pumpAndSettle();
      final target = find.byWidgetPredicate(
        (widget) =>
            widget is EditorSlot &&
            widget.id == 'extension' &&
            identical(widget.behaviors, behaviours),
      );
      expect(target, findsOneWidget);
      await tester.tap(target);
      await tester.pump();
      expect(events, hasLength(1));
      expect(events.single.componentId, 'extension');
    });
  }
}
