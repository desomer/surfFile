import 'dart:async';
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
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => DynamicFontManager.shared.loadCachedFonts());
      await tester.pump();
      await tester.pumpWidget(const SuperDesignerApp());
      await tester.pumpAndSettle();

      expect(find.byType(SuperPage), findsOneWidget);
      expect(find.byType(FloatingAppearanceToolbar), findsOneWidget);

      final superApp = tester.widget<SuperApp>(find.byType(SuperApp));
      expect(superApp.registry, isNotNull);
      expect(superApp.registry!.registry.containsKey('Layout'), isTrue);
      expect(superApp.registry!.registry.containsKey('Chart'), isTrue);
      expect(superApp.registry!.registry.containsKey('Code'), isTrue);
      expect(superApp.appearanceStore, isNull);
      expect(superApp.eventBus, isNotNull);

      final events = <SuperComponentEvent>[];
      final subscription = superApp.eventBus!
          .on('designer.click')
          .listen(events.add);
      addTearDown(subscription.cancel);

      final context = tester.element(find.byType(SuperPage));
      final appearance = AppearanceScope.controllerOf(context)!;
      appearance.value = appearance.value.copyWith(
        components: {
          ...appearance.value.components,
          'mainLayout': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['clickable-label'],
            },
            slotTypes: {'clickable-label': 'registry:Value'},
          ),
          'clickable-label': const SuperValueConfig(initialText: 'Cliquer ici'),
        },
        behaviors: {
          ...appearance.value.behaviors,
          'clickable-label': [
            ComponentBehavior(
              id: 'emit-click',
              trigger: BehaviorTrigger.click,
              action: EmitEventAction(eventId: 'designer.click'),
            ),
          ],
        },
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cliquer ici'));
      await tester.pumpAndSettle();

      expect(events, hasLength(1));
      expect(events.single.componentId, 'clickable-label');
      expect(events.single.trigger, 'click');
      expect(events.single.data['value'], 'Cliquer ici');
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

      final rootCtx = tester.element(find.byType(SuperPage));
      final appearance = AppearanceScope.controllerOf(rootCtx)!;
      appearance.value = appearance.value.copyWith(
        components: {
          ...appearance.value.components,
          'mainLayout': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['explorer'],
            },
            slotTypes: {'explorer': 'registry:Layout'},
          ),
          'explorer': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['attribut-tree', 'code-preview'],
            },
            slotTypes: {
              'attribut-tree': 'registry:TreeView',
              'code-preview': 'registry:Code',
            },
          ),
          'attribut-tree': SuperTreeViewConfig(
            placements: const {
              'header': ['tree-label'],
              'data': ['tree-data'],
            },
            slotTypes: const {
              'tree-label': 'registry:Value',
              'tree-data': 'registry:Value',
            },
          ),
          'tree-label': const SuperValueConfig(initialText: 'Nœud'),
          'tree-data': const SuperValueConfig(initialText: 'Détail'),
          'code-preview': const SuperCodeConfig(),
        },
      );
      await tester.pumpAndSettle();
      StyleEditScope.controllerOf(rootCtx)!.value = true;
      await tester.pumpAndSettle();

      final exports = <String, EditorFragmentExport>{};
      for (final slot in tester.stateList<EditorSlotState>(
        find.byType(EditorSlot),
      )) {
        if (!slot.canEdit || slot.widget.identity is AppearanceSlot) continue;
        final key = '${slot.effectiveComponentId}|${slot.widget.zoneId}';
        exports.putIfAbsent(key, slot.buildContentExport);
      }
      // The design surface and code-declared layouts both expose their slots.
      expect(
        exports.keys,
        containsAll([
          'root|body',
          'mainLayout|null',
          'explorer|null',
          'attribut-tree|header',
        ]),
      );
      final body = exports['mainLayout|null']!;
      expect(
        body.appearance.components['mainLayout'],
        isA<SuperLayoutConfig>(),
      );
      expect(body.omitted, isEmpty);
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

  testWidgets(
    'non-coded pages display FloatingAppearanceToolbar, keep its position, and include background EditableSurface',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SuperDesignerApp());
      await tester.pumpAndSettle();

      final toolbarFinder = find.byKey(const ValueKey('appearance-toolbar'));
      expect(toolbarFinder, findsOneWidget);

      final initialToolbarTopLeft = tester.getTopLeft(toolbarFinder);
      await tester.drag(
        find.byKey(const ValueKey('appearance-toolbar-drag')),
        const Offset(-120, -80),
      );
      await tester.pumpAndSettle();
      final movedToolbarTopLeft = tester.getTopLeft(toolbarFinder);
      expect(movedToolbarTopLeft.dx, lessThan(initialToolbarTopLeft.dx));
      expect(movedToolbarTopLeft.dy, lessThan(initialToolbarTopLeft.dy));

      final pageContext = tester.element(find.byType(SuperPage));
      final appearance = AppearanceScope.controllerOf(pageContext)!;
      appearance.value = appearance.value.copyWith(
        pageCatalog: EditorPageCatalog(
          pages: [
            EditorPageConfig(
              id: 'extra-page',
              name: 'Extra Page',
              path: '/extra',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final superApp = tester.widget<SuperApp>(find.byType(SuperApp));
      superApp.router.go('/extra');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('editor-page-extra-page')),
        findsOneWidget,
      );
      expect(find.byType(FloatingAppearanceToolbar), findsOneWidget);
      expect(tester.getTopLeft(toolbarFinder), movedToolbarTopLeft);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableSurface &&
              widget.slot?.name == 'demo-background',
        ),
        findsOneWidget,
      );
    },
  );

  test('createSuperDesignerLogZoneSpecification horodate les logs console et conserve le message brut dans debugEntries', () {
    clearDebugEntries();
    addTearDown(clearDebugEntries);

    final printed = <String>[];
    final fixedTime = DateTime(2026, 11, 22, 22, 3, 2, 273);

    runZoned(
      () {
        runZoned(
          () {
            Zone.current.print('[Vibe IA] Test horodatage');
          },
          zoneSpecification: createSuperDesignerLogZoneSpecification(
            clock: () => fixedTime,
          ),
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );

    expect(printed, ['[22:03:02.273] [Vibe IA] Test horodatage']);
    expect(debugEntries, hasLength(1));
    expect(debugEntries.single.message, '[Vibe IA] Test horodatage');
    expect(
      VibeDebugCapture.isVibeInternalMessage(debugEntries.single.message),
      isTrue,
    );
  });

  testWidgets(
    'SuperDesignerApp opens sideSheet over root page, preserves FloatingAppearanceToolbar, edits inside sideSheet and closes cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.runAsync(() => DynamicFontManager.shared.loadCachedFonts());
      await tester.pump();

      await tester.pumpWidget(const SuperDesignerApp());
      await tester.pumpAndSettle();

      final superApp = tester.widget<SuperApp>(find.byType(SuperApp));
      final rootCtx = tester.element(find.byType(SuperPage));
      final appearance = AppearanceScope.controllerOf(rootCtx)!;

      appearance.value = appearance.value.copyWith(
        pageCatalog: EditorPageCatalog(
          pages: [
            EditorPageConfig(
              id: 'designer-side',
              name: 'Panneau Latéral',
              path: '/panneau',
              pageType: EditorPageType.sideSheet,
              modalWidth: 400,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      superApp.pageRouting!.openLocation('/panneau');
      await tester.pumpAndSettle();

      final sideContainer = find.byKey(
        const ValueKey('editor-side-sheet-page-container'),
      );
      expect(sideContainer, findsOneWidget);
      expect(tester.getSize(sideContainer).width, 400);
      expect(
        find.byKey(const ValueKey('editor-page-designer-side')),
        findsOneWidget,
      );
      expect(
        find.byType(FloatingAppearanceToolbar, skipOffstage: false),
        findsOneWidget,
      );

      final sheetCtx = tester.element(
        find.byKey(const ValueKey('editor-page-designer-side')),
      );
      StyleEditScope.controllerOf(sheetCtx)!.value = true;
      await tester.pumpAndSettle();

      LayoutSelection.select(['Panneau Latéral']);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('scaffold-page-add-body')));
      await tester.pumpAndSettle();
      final addCard = find.byKey(
        const ValueKey('scaffold-page-add-slot-factory:Card'),
      );
      await tester.ensureVisible(addCard);
      await tester.pumpAndSettle();
      await tester.tap(addCard);
      await tester.pumpAndSettle();

      expect(
        appearance.value.nativeComponent('designer-side').slotsOf('body'),
        hasLength(1),
      );

      StyleEditScope.controllerOf(sheetCtx)!.value = false;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-modal-page-close')));
      await tester.pumpAndSettle();

      expect(sideContainer, findsNothing);
      expect(find.byType(FloatingAppearanceToolbar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SuperDesignerApp toggles edit mode and StyleEditBanner with F12',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const SuperDesignerApp());
      await tester.runAsync(() => DynamicFontManager.shared.loadCachedFonts());
      await tester.pumpAndSettle();

      final editMode = StyleEditScope.controllerOf(
        tester.element(find.byType(SuperPage)),
      )!;
      expect(editMode.value, isFalse);
      expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.pumpAndSettle();
      expect(editMode.value, isTrue);
      expect(find.byKey(const ValueKey('style-edit-banner')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.pumpAndSettle();
      expect(editMode.value, isFalse);
      expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SuperDesignerApp does not duplicate background EditableSurface, toolbar or root Scaffold when rootShellId is active',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.runAsync(() => DynamicFontManager.shared.loadCachedFonts());
      await tester.pump();

      await tester.pumpWidget(const SuperDesignerApp());
      await tester.pumpAndSettle();

      final rootCtx = tester.element(find.byType(SuperPage));
      final appearance = AppearanceScope.controllerOf(rootCtx)!;

      appearance.value = appearance.value.copyWith(
        pageCatalog: EditorPageCatalog(
          shells: [EditorShellConfig(id: 'app-shell', name: 'Shell')],
          rootShellId: 'app-shell',
          pages: [
            EditorPageConfig(
              id: 'orders',
              name: 'Commandes',
              path: '/orders',
              shellId: 'app-shell',
            ),
          ],
        ),
        components: {
          ...appearance.value.components,
          'app-shell': ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.appBar: const ['shell-bar'],
              ScaffoldPageRegion.body: const ['scaffold:outlet'],
            },
            slotTypes: const {'shell-bar': 'registry:ApplicationBar'},
          ),
          'shell-bar': NativeComponentConfig(
            placements: const {
              'title': ['shell-title'],
            },
            slotTypes: const {'shell-title': 'registry:Value'},
          ),
          'shell-title': const SuperValueConfig(initialText: 'Designer Shell'),
        },
      );
      await tester.pumpAndSettle();

      expect(find.text('Designer Shell'), findsOneWidget);
      expect(find.byType(FloatingAppearanceToolbar), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableSurface &&
              widget.slot?.name == 'demo-background',
        ),
        findsOneWidget,
      );
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
