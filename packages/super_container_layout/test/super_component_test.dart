import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

class _CallbackAction extends BehaviorAction {
  const _CallbackAction(this.callback);

  final VoidCallback callback;
  @override
  String get type => 'test';
  @override
  String get label => 'Test';
  @override
  String get description => 'Test';
  @override
  IconData get icon => Icons.touch_app;
  @override
  Map<String, Object?> toJson() => {'type': type};
  @override
  Future<void> execute(BuildContext context) async => callback();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  Future<void> mount(
    WidgetTester tester,
    Widget child,
    SuperEventBus bus,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              Scaffold(body: SizedBox(width: 600, height: 400, child: child)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(
        router: router,
        registry: Registry()..bootstrap(),
        eventBus: bus,
      ),
    );
    await tester.pumpAndSettle();
  }

  final factories = <String, Widget Function(List<ComponentBehavior>)>{
    'value': (behaviours) => SuperValue(
      id: 'subject',
      behaviours: behaviours,
      config: const SuperValueConfig(initialText: 'Value'),
    ),
    'action': (behaviours) => SuperAction(
      id: 'subject',
      behaviours: behaviours,
      config: const SuperActionConfig(label: 'Action'),
    ),
    'layout': (behaviours) =>
        SuperLayout(id: 'subject', behaviours: behaviours),
    'registered layout': (behaviours) => RegisteredSuperLayout(
      id: 'subject',
      label: 'Layout',
      config: const SuperLayoutConfig(),
      behaviours: behaviours,
    ),
    'iterable': (behaviours) => IterableContent(
      id: 'subject',
      behaviours: behaviours,
      child: const Text('Row'),
    ),
    'list': (behaviours) =>
        SuperListView(id: 'subject', behaviours: behaviours),
    'tab': (behaviours) => SuperTab(
      id: 'subject',
      behaviours: behaviours,
      tab: const SuperAction(
        id: 'tab',
        config: SuperActionConfig(label: 'Tab'),
      ),
    ),
    'table': (behaviours) => SuperTable(id: 'subject', behaviours: behaviours),
    'tree': (behaviours) =>
        SuperTreeView(id: 'subject', behaviours: behaviours),
    'app bar': (behaviours) => SuperAppBar(
      id: 'subject',
      behaviours: behaviours,
      title: const Text('Title'),
    ),
    'bottom app bar': (behaviours) => SuperBottomAppBar(
      id: 'subject',
      behaviours: behaviours,
      center: const Text('Bottom'),
    ),
    'bottom navigation': (behaviours) => SuperBottomNavigationBar(
      id: 'subject',
      behaviours: behaviours,
      destinations: const [
        SuperAction(
          id: 'one',
          config: SuperActionConfig(label: 'One', icon: 'home'),
        ),
        SuperAction(
          id: 'two',
          config: SuperActionConfig(label: 'Two', icon: 'settings'),
        ),
      ],
    ),
    'navigation rail': (behaviours) => SuperNavigationRail(
      id: 'subject',
      behaviours: behaviours,
      destinations: const [
        SuperAction(
          id: 'one',
          config: SuperActionConfig(label: 'One', icon: 'home'),
        ),
        SuperAction(
          id: 'two',
          config: SuperActionConfig(label: 'Two', icon: 'settings'),
        ),
      ],
    ),
    'expansible': (behaviours) => SuperExpansible(
      id: 'subject',
      behaviours: behaviours,
      header: const Text('Header'),
      body: const Text('Body'),
    ),
    'menu': (behaviours) => SuperMenuAnchor(
      id: 'subject',
      behaviours: behaviours,
      header: const Text('Menu'),
    ),
    'page': (behaviours) => SuperPage(
      id: 'subject',
      behaviours: behaviours,
      child: const Text('Page'),
    ),
  };

  for (final entry in factories.entries) {
    testWidgets('${entry.key} exposes and executes code behaviours', (
      tester,
    ) async {
      final behaviours = [
        ComponentBehavior(
          id: 'code-click',
          trigger: BehaviorTrigger.click,
          action: EmitEventAction(eventId: 'clicked'),
        ),
      ];
      final component = entry.value(behaviours);
      expect(component, isA<SuperComponent<ComponentConfig?>>());
      final contract = component as SuperComponent<ComponentConfig?>;
      expect(contract.id, 'subject');
      expect(contract.behaviours, same(behaviours));
      final bus = SuperEventBus();
      final events = <SuperComponentEvent>[];
      final subscription = bus.on('clicked').listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await bus.close();
      });
      await mount(tester, component, bus);

      final target = find.byWidgetPredicate(
        (widget) =>
            widget is EditorSlot &&
            widget.id == 'subject' &&
            identical(widget.behaviors, behaviours),
      );
      expect(target, findsOneWidget);
      expect(
        AppearanceScope.of(tester.element(target)).behaviorsFor('subject'),
        isEmpty,
      );
      await tester.tap(target);
      await tester.pump();
      expect(events, hasLength(1));
      expect(events.single.componentId, 'subject');
      expect(events.single.trigger, 'click');
    });
  }

  test('configuration types and nullable initial configs are preserved', () {
    const value = SuperValue(id: 'value');
    const tab = SuperTab();
    const native = SuperAppBar();
    const page = SuperPage();
    expect(value, isA<SuperStatefulComponent<SuperValueConfig>>());
    expect(value.config, const SuperValueConfig());
    expect(tab.config, isNull);
    expect(native.config, native.nativeConfig);
    expect(page, isA<SuperStatelessComponent<ScaffoldPageConfig?>>());
    expect(page.config, page.pageConfig);
    expect(value.behaviours, isNull);
  });

  testWidgets(
    'action code behaviours retain onPressed without double execution',
    (tester) async {
      var pressed = 0;
      var executed = 0;
      final bus = SuperEventBus();
      addTearDown(bus.close);
      await mount(
        tester,
        SuperAction(
          id: 'subject',
          config: const SuperActionConfig(label: 'Run'),
          onPressed: () => pressed++,
          behaviours: [
            ComponentBehavior(
              id: 'callback',
              trigger: BehaviorTrigger.click,
              action: _CallbackAction(() => executed++),
            ),
          ],
        ),
        bus,
      );
      await tester.tap(find.text('Run'));
      await tester.pump();
      expect(pressed, 1);
      expect(executed, 1);
    },
  );
}
