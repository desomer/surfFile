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
        '0123456789abcdef0123456789abcdef',
        'nodes',
        [
          {'id': 'test-node', 'name': 'Test node', 'type': 'string'},
        ],
      );
      await tester.pumpAndSettle();
      final name = tester.widget<SuperValue>(
        find.byWidgetPredicate(
          (widget) => widget is SuperValue && widget.id == 'tree-node-name',
        ),
      );
      expect(name.behaviours, hasLength(1));
      expect(
        AppearanceScope.of(tester.element(find.byWidget(name)))
            .behaviorsFor('tree-node-name'),
        isEmpty,
      );
      await tester.tap(find.text('Test node'));
      await tester.pump();

      expect(events, hasLength(1));
      expect(events.single.componentId, 'tree-node-name');
      expect(events.single.trigger, 'click');
      expect(events.single.data['value'], 'Test node');
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
