import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/main.dart' as demo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> pumpPage(
    WidgetTester tester,
    SuperPage page, {
    Registry? registry,
    AppearanceStore? store,
  }) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => page)],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(router: router, registry: registry, appearanceStore: store),
    );
    await tester.pumpAndSettle();
  }

  Finder layout(String label) => find.byWidgetPredicate(
    (widget) => widget is SuperLayout && widget.label == label,
  );

  Finder zone(Finder owner, SuperLayoutZone zone) => find.descendant(
    of: owner,
    matching: find.byKey(ValueKey('super-layout-${zone.name}')),
  );

  testWidgets('demo tooltips preserve semantics while editing', (tester) async {
    await tester.pumpWidget(const demo.TestApp());
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    try {
      await tester.tap(find.byKey(const ValueKey('style-edit-mode')));
      await tester.pumpAndSettle();
      for (final key in ['appearance-settings', 'style-edit-mode']) {
        await mouse.moveTo(tester.getCenter(find.byKey(ValueKey(key))));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
      }
      await mouse.moveTo(tester.getCenter(
        find.byKey(const ValueKey('style-edit-banner-transfer')),
      ));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Importer / exporter le style et la disposition'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-edit-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('style-edit-mode')));
      await tester.pumpAndSettle();
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('appearance-settings'))),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Paramètres d’apparence'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
    }
  });

  testWidgets('empty bars take no space outside edit mode', (tester) async {
    final registry = Registry();
    await pumpPage(
      tester,
      const SuperPage(child: SizedBox.expand(key: ValueKey('body-content'))),
      registry: registry,
    );
    final page = layout('Super page');
    expect(tester.getSize(zone(page, SuperLayoutZone.north)).height, 0);
    expect(tester.getSize(zone(page, SuperLayoutZone.south)).height, 0);
    expect(
      tester.getSize(find.byKey(const ValueKey('body-content'))),
      const Size(800, 600),
    );
    expect(find.byType(SuperAppBar), findsNothing);
    expect(registry.registry.containsKey('SuperAppBar'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provided page and app bar slots have their intended geometry', (
    tester,
  ) async {
    await pumpPage(
      tester,
      SuperPage(
        id: 'provided',
        appBar: SuperAppBar(
          id: 'provided-bar',
          title: const Text('Page title'),
          action: IconButton(
            key: const ValueKey('page-action'),
            onPressed: () {},
            icon: const Icon(Icons.settings),
          ),
        ),
        bottomBar: const SizedBox(height: 32, child: Text('Bottom content')),
        child: const SizedBox.expand(key: ValueKey('page-body')),
      ),
      registry: Registry(),
    );
    final page = layout('Super page');
    expect(
      tester.getSize(zone(page, SuperLayoutZone.north)).height,
      kToolbarHeight,
    );
    expect(tester.getSize(zone(page, SuperLayoutZone.south)).height, 32);
    expect(
      tester.getSize(find.byKey(const ValueKey('page-body'))).height,
      600 - kToolbarHeight - 32,
    );
    expect(find.text('Page title'), findsOneWidget);
    expect(find.text('Bottom content'), findsOneWidget);
    final action = tester.getRect(find.byKey(const ValueKey('page-action')));
    final title = tester.getRect(find.text('Page title'));
    expect(action.left, greaterThan(title.right));
    expect(action.right, closeTo(800, 1));
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provided drawer opens from the app bar menu', (tester) async {
    await pumpPage(
      tester,
      SuperPage(
        appBar: AppBar(title: const Text('Page title')),
        drawer: const Drawer(child: Text('Navigation drawer')),
        child: const SizedBox.expand(),
      ),
      registry: Registry(),
    );

    expect(find.text('Navigation drawer'), findsNothing);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('Navigation drawer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor adds a registered app bar and edits title and action', (
    tester,
  ) async {
    final registry = Registry();
    registry.registerComponent(
      'test-title',
      const RegisteredComponent(label: 'Test title', builder: _title),
    );
    registry.registerComponent(
      'test-action',
      const RegisteredComponent(
        label: 'Test action',
        sizing: SlotSizing.intrinsic,
        builder: _action,
      ),
    );
    await pumpPage(tester, const SuperPage(), registry: registry);
    final context = tester.element(find.byType(SuperPage));
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('style-edit-banner-drag')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    final page = layout('Super page');
    await tester.tap(zone(page, SuperLayoutZone.north));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: page,
        matching: find.byKey(const ValueKey('super-layout-add-north')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un slot dans appBar'), findsOneWidget);
    await tester.tap(find.text('SuperAppBar'));
    await tester.pumpAndSettle();
    expect(find.byType(SuperAppBar), findsOneWidget);
    final bar = tester.widget<SuperAppBar>(find.byType(SuperAppBar));
    expect(
      registry.layoutController('root').value.slotTypeOf(bar.id),
      'registry:SuperAppBar',
    );
    final barLayout = layout('Super app bar');
    await tester.tapAt(
      tester.getTopLeft(zone(barLayout, SuperLayoutZone.center)) +
          const Offset(100, 48),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: barLayout,
        matching: find.byKey(const ValueKey('super-layout-add-center')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un slot dans title'), findsOneWidget);
    await tester.tap(find.text('Test title'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: barLayout,
        matching: find.byKey(const ValueKey('super-layout-name-center')),
      ),
    );
    await tester.pumpAndSettle();
    expect(LayoutSelection.path.value, contains('title'));
    expect(LayoutSelection.path.value, contains('appBar'));

    await tester.tap(
      find.descendant(
        of: barLayout,
        matching: find.byKey(const ValueKey('super-layout-add-east')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un slot dans action'), findsOneWidget);
    await tester.tap(find.text('Test action'));
    await tester.pumpAndSettle();
    expect(find.text('Registered title'), findsOneWidget);
    expect(find.byKey(const ValueKey('registered-action')), findsOneWidget);
    final history = EditorHistoryScope.controllerOf(context)!;
    history.undo();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('registered-action')), findsNothing);
    history.redo();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('registered-action')), findsOneWidget);
    StyleEditScope.controllerOf(context)!.value = false;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('page and bar layouts persist independently and reset', (
    tester,
  ) async {
    final registry = Registry();
    registry.registerComponent(
      'test-title',
      const RegisteredComponent(label: 'Test title', builder: _title),
    );
    registry.registerComponent(
      'test-action',
      const RegisteredComponent(
        label: 'Test action',
        sizing: SlotSizing.intrinsic,
        builder: _action,
      ),
    );
    final store = AppearanceStore();
    const page = SuperPage(id: 'persisted-page', child: Text('Original body'));
    await pumpPage(tester, page, registry: registry, store: store);
    final pageController = registry.layoutController('persisted-page');
    pageController.value = pageController.value
        .withSlotMoved(
          'first-bar',
          SuperLayoutZone.north,
          type: 'registry:SuperAppBar',
        )
        .withSlotMoved(
          'second-bar',
          SuperLayoutZone.south,
          type: 'registry:SuperAppBar',
        )
        .withSlotMoved(
          'footer',
          SuperLayoutZone.south,
          type: 'registry:test-title',
        )
        .withSlotMoved(
          'body-extra',
          SuperLayoutZone.center,
          type: 'registry:test-title',
        );
    await tester.pumpAndSettle();
    final first = registry.layoutController('first-bar');
    final second = registry.layoutController('second-bar');
    first.value = first.value.withSlotMoved(
      'first-title',
      SuperLayoutZone.center,
      type: 'registry:test-title',
    );
    second.value = second.value.withSlotMoved(
      'second-action',
      SuperLayoutZone.east,
      type: 'registry:test-action',
    );
    await tester.pumpAndSettle();
    expect(find.text('Registered title'), findsNWidgets(3));
    expect(find.byKey(const ValueKey('registered-action')), findsOneWidget);
    expect(second.value.placementsOf(SuperLayoutZone.center), isEmpty);
    final appearance = AppearanceScope.controllerOf(
      tester.element(find.byType(SuperPage)),
    )!;
    await (appearance as PersistentAppearanceController).saved;
    final saved = await store.load();
    expect(saved.layout('persisted-page'), pageController.value);
    expect(saved.layout('first-bar'), first.value);
    expect(saved.layout('second-bar'), second.value);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final restarted = Registry();
    restarted.registerComponent(
      'test-title',
      const RegisteredComponent(label: 'Test title', builder: _title),
    );
    restarted.registerComponent(
      'test-action',
      const RegisteredComponent(
        label: 'Test action',
        sizing: SlotSizing.intrinsic,
        builder: _action,
      ),
    );
    await pumpPage(tester, page, registry: restarted, store: store);
    expect(find.byType(SuperAppBar), findsNWidgets(2));
    expect(find.text('Registered title'), findsNWidgets(3));
    expect(find.byKey(const ValueKey('registered-action')), findsOneWidget);
    final restored = AppearanceScope.controllerOf(
      tester.element(find.byType(SuperPage)),
    )!;
    restored.value = restored.value.resetLayouts();
    await tester.pumpAndSettle();
    expect(find.byType(SuperAppBar), findsNothing);
    expect(find.text('Original body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'adding slots after accessibility is enabled preserves semantics',
    (tester) async {
      final registry = Registry();
      registry.registerComponent(
        'test-title',
        const RegisteredComponent(label: 'Test title', builder: _title),
      );
      await pumpPage(tester, const SuperPage(), registry: registry);
      final context = tester.element(find.byType(SuperPage));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpAndSettle();
        final controller = registry.layoutController('root');
        controller.value = controller.value.withSlotMoved(
          'bar',
          SuperLayoutZone.north,
          type: 'registry:SuperAppBar',
        );
        await tester.pumpAndSettle();
        final bar = registry.layoutController('bar');
        bar.value = bar.value.withSlotMoved(
          'title',
          SuperLayoutZone.center,
          type: 'registry:test-title',
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Registered title'), findsOneWidget);
        final titleNode = tester.getSemantics(find.text('Registered title'));
        controller.value = controller.value.withSlotMoved(
          'footer',
          SuperLayoutZone.south,
          type: 'registry:test-title',
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Registered title'), findsNWidgets(2));
        final barTitle = find.descendant(
          of: find.byType(SuperAppBar),
          matching: find.text('Registered title'),
        );
        expect(tester.getSemantics(barTitle).id, titleNode.id);
        controller.value = controller.value.withoutSlot('footer');
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Registered title'), findsOneWidget);
        expect(tester.getSemantics(barTitle).id, titleNode.id);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    semanticsEnabled: false,
  );
}

Widget _title(BuildContext context) => const Text('Registered title');

Widget _action(BuildContext context) => IconButton(
  key: const ValueKey('registered-action'),
  onPressed: () {},
  icon: const Icon(Icons.refresh),
);
