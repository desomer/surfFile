import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

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

  Future<void> mount(
    Widget child,
    WidgetTester tester,
    Registry registry, {
    AppearanceStore? store,
  }) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => child)],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(
        router: router,
        registry: registry,
        appearanceStore: store ?? AppearanceStore(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'SuperNavigationRail renders leading, destinations and trailing',
    (tester) async {
      final registry = Registry();
      var leadingTapped = false;

      await mount(
        Scaffold(
          body: Row(
            children: [
              SuperNavigationRail(
                id: 'my-rail',
                leading: IconButton(
                  onPressed: () => leadingTapped = true,
                  icon: const Icon(Icons.menu),
                ),
                destinations: const [Text('Home'), Text('Settings')],
                trailing: const Icon(Icons.account_circle),
              ),
              const Expanded(child: Center(child: Text('Content'))),
            ],
          ),
        ),
        tester,
        registry,
      );

      expect(find.byType(SuperNavigationRail), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byIcon(Icons.account_circle), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu));
      expect(leadingTapped, isTrue);

      final railFinder = find.byType(SuperNavigationRail);
      expect(tester.getSize(railFinder).width, 72.0);

      // Disable leading region via controller
      final controller = registry.nativeComponentController('my-rail');
      controller.value = controller.value.withRegionEnabled('leading', false);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.menu), findsNothing);
      expect(find.text('Home'), findsOneWidget);

      // Re-enable leading
      controller.value = controller.value.withRegionEnabled('leading', true);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.menu), findsOneWidget);
    },
  );

  testWidgets('SuperNavigationRail respects extended property and sizing', (
    tester,
  ) async {
    final registry = Registry();

    await mount(
      Scaffold(
        body: Row(
          children: [
            const SuperNavigationRail(
              id: 'compact-rail',
              destination: Text('Dashboard'),
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
      tester,
      registry,
    );

    final compactFinder = find.byType(SuperNavigationRail);
    expect(tester.getSize(compactFinder).width, 72.0);

    const rail = SuperNavigationRail(
      id: 'extended-rail',
      extended: true,
      destination: Text('Dashboard'),
    );
    expect(rail.preferredSize.width, 256.0);

    await mount(
      Scaffold(
        body: Row(
          children: [
            rail,
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
      tester,
      registry,
    );

    final extendedFinder = find.byType(SuperNavigationRail);
    expect(tester.getSize(extendedFinder).width, 256.0);
  });

  testWidgets(
    'SuperNavigationRail configuration survives JSON appearance transfer',
    (tester) async {
      final registry = Registry();
      final store = AppearanceStore();

      await mount(
        const Scaffold(
          body: Row(
            children: [
              SuperNavigationRail(
                id: 'persisted-rail',
                destination: Text('Inbox'),
                trailing: Text('Version 1.0'),
              ),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
        tester,
        registry,
        store: store,
      );

      final controller = registry.nativeComponentController('persisted-rail');
      controller.value = controller.value.withRegionEnabled('trailing', false);
      await tester.pumpAndSettle();

      final appearance = AppearanceScope.of(
        tester.element(find.byType(SuperNavigationRail)),
      );
      final json = AppearanceStore.encode(appearance);
      final decoded = AppearanceStore.decode(json);

      final restoredConfig = decoded.nativeComponent('persisted-rail');
      expect(restoredConfig.isEnabled('trailing'), isFalse);
    },
  );

  test('Registry bootstrap includes NavigationRail dynamic builder', () {
    final registry = Registry()..bootstrap();
    expect(registry.registry.containsKey('NavigationRail'), isTrue);

    final builder = registry.registry['NavigationRail']!;
    expect(builder.menuIcon, Icons.view_sidebar_outlined);
    expect(builder.tags, contains('navigationRail'));
    expect(builder.placementTags, contains('navigationRail'));

    final widget = builder.getWidget(XuiBuildCtx(id: 'dynamic-rail'));
    expect(widget, isA<SuperNavigationRail>());
  });

  test('JsonComponentType normalizes NavigationRail and Rail', () {
    expect(
      JsonComponentType.normalize('NavigationRail'),
      'registry:NavigationRail',
    );
    expect(JsonComponentType.normalize('Rail'), 'registry:NavigationRail');
  });
}
