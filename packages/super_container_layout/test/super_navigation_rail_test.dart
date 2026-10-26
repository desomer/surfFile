import 'dart:async';

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
    'SuperNavigationRail renders native NavigationRail with SuperAction destinations',
    (tester) async {
      final registry = Registry()..bootstrap();
      var selectedIndex = -1;
      var settingsClicked = false;

      await mount(
        SuperPage(
          child: Row(
            children: [
              SuperNavigationRail(
                id: 'my-rail',
                onDestinationSelected: (index) => selectedIndex = index,
                destinations: [
                  const SuperAction(
                    id: 'nav-home',
                    config: SuperActionConfig(label: 'Home', icon: 'home'),
                  ),
                  SuperAction(
                    id: 'nav-settings',
                    onPressed: () => settingsClicked = true,
                    config: const SuperActionConfig(
                      label: 'Settings',
                      icon: 'settings',
                    ),
                  ),
                ],
              ),
              const Expanded(child: Center(child: Text('Content'))),
            ],
          ),
        ),
        tester,
        registry,
      );

      expect(find.byType(SuperNavigationRail), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(selectedIndex, 1);
      expect(settingsClicked, isTrue);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        1,
      );

      // Update action config via registry controller and verify destination updates
      registry.actionController('nav-home').value = const SuperActionConfig(
        label: 'Accueil',
        icon: 'star',
      );
      await tester.pumpAndSettle();
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsOneWidget);

      // Enable edit mode, move banner out of the way, select destinations region, and drag first item below second
      StyleEditScope.controllerOf(
        tester.element(find.byType(SuperNavigationRail)),
      )!.value = true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      final editor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperNavigationRail),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      editor.select('destinations');
      await tester.pumpAndSettle();

      final controller = registry.nativeComponentController('my-rail');
      expect(controller.value.slotsOf('destinations'), [
        'nav-home',
        'nav-settings',
      ]);

      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('slot-label-nav-home'))),
      );
      await drag.moveBy(const Offset(0, 25));
      await tester.pump();
      final secondRect = tester.getRect(
        find.byKey(const ValueKey('slot-nav-settings')),
      );
      await drag.moveTo(Offset(secondRect.center.dx, secondRect.bottom - 2));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(controller.value.slotsOf('destinations'), [
        'nav-settings',
        'nav-home',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SuperNavigationRail falls back when empty, mounts NavigationRail from 1 item without overflow in edit mode, and filters by action tag',
    (tester) async {
      final registry = Registry()..bootstrap();

      await mount(
        Scaffold(
          body: Row(
            children: [
              const SuperNavigationRail(id: 'fallback-rail'),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
        tester,
        registry,
      );

      // When empty, native NavigationRail is not mounted yet
      expect(find.byType(NavigationRail), findsNothing);

      final editor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperNavigationRail),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      final spec = editor.definition('destinations');
      expect(spec.tagFilter.accepts(const {'action'}), isTrue);
      expect(spec.tagFilter.accepts(const {'container'}), isFalse);
      expect(spec.tagFilter.accepts(const {'text'}), isFalse);

      // Enable edit mode and select destinations region
      StyleEditScope.controllerOf(
        tester.element(find.byType(SuperNavigationRail)),
      )!.value = true;
      editor.select('destinations');
      await tester.pumpAndSettle();

      // Add a single SuperAction via the controller -> mounts native NavigationRail without overflow
      final controller = registry.nativeComponentController('fallback-rail');
      controller.value = controller.value.withSlotAdded(
        'first-action',
        'destinations',
        type: 'factory:Action',
      );
      registry.actionController('first-action').value = const SuperActionConfig(
        label: 'Unique',
        icon: 'home',
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Unique'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Add wizard in SuperNavigationRail and SuperBottomNavigationBar only offers Action',
    (tester) async {
      final registry = Registry()..bootstrap();

      await mount(
        const SuperPage(
          bottomNavigationBar: SuperBottomNavigationBar(id: 'wizard-bottom'),
          child: Row(
            children: [
              SuperNavigationRail(id: 'wizard-rail'),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
        tester,
        registry,
      );

      final pageContext = tester.element(find.byType(SuperPage));
      StyleEditScope.controllerOf(pageContext)!.value = true;
      await tester.pumpAndSettle();

      // Open add wizard on SuperNavigationRail
      final railEditor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperNavigationRail),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      unawaited(railEditor.add('destinations'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('super-navigation-rail-add-card-factory:Action'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('super-navigation-rail-add-card-factory:Card'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('super-navigation-rail-add-card-factory:Value'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('super-navigation-rail-add-card-factory:Layout'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('super-navigation-rail-add-cancel')),
      );
      await tester.pumpAndSettle();

      // Open add wizard on SuperBottomNavigationBar
      final bottomEditor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperBottomNavigationBar),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      unawaited(bottomEditor.add('destinations'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('super-bottom-navigation-bar-add-card-factory:Action'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('super-bottom-navigation-bar-add-card-factory:Card'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('super-bottom-navigation-bar-add-card-factory:Value'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('super-bottom-navigation-bar-add-cancel')),
      );
      await tester.pumpAndSettle();
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
              destinations: [
                SuperAction(
                  id: 'd1',
                  config: SuperActionConfig(label: 'One', icon: 'home'),
                ),
                SuperAction(
                  id: 'd2',
                  config: SuperActionConfig(label: 'Two', icon: 'star'),
                ),
              ],
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
      destinations: [
        SuperAction(
          id: 'e1',
          config: SuperActionConfig(label: 'One', icon: 'home'),
        ),
        SuperAction(
          id: 'e2',
          config: SuperActionConfig(label: 'Two', icon: 'star'),
        ),
      ],
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
    'SuperBottomNavigationBar renders native BottomNavigationBar with SuperAction items',
    (tester) async {
      final registry = Registry()..bootstrap();
      var tappedIndex = -1;
      var profileClicked = false;

      await mount(
        SuperPage(
          bottomNavigationBar: SuperBottomNavigationBar(
            id: 'my-bottom-nav',
            onTap: (index) => tappedIndex = index,
            destinations: [
              const SuperAction(
                id: 'tab-home',
                config: SuperActionConfig(label: 'Home', icon: 'home'),
              ),
              SuperAction(
                id: 'tab-profile',
                onPressed: () => profileClicked = true,
                config: const SuperActionConfig(
                  label: 'Profile',
                  icon: 'person',
                ),
              ),
            ],
          ),
        ),
        tester,
        registry,
      );

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(tappedIndex, 1);
      expect(profileClicked, isTrue);
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        1,
      );

      // Enable edit mode, move zoom toolbar out of the way, and reorder items via drag-and-drop
      StyleEditScope.controllerOf(
        tester.element(find.byType(SuperBottomNavigationBar)),
      )!.value = true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('editor-zoom-toolbar-drag')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      final editor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperBottomNavigationBar),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      editor.select('destinations');
      await tester.pumpAndSettle();

      final controller = registry.nativeComponentController('my-bottom-nav');
      expect(controller.value.slotsOf('destinations'), [
        'tab-home',
        'tab-profile',
      ]);

      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('slot-label-tab-home'))),
      );
      await drag.moveBy(const Offset(25, 0));
      await tester.pump();
      final secondRect = tester.getRect(
        find.byKey(const ValueKey('slot-tab-profile')),
      );
      await drag.moveTo(Offset(secondRect.right - 2, secondRect.center.dy));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(controller.value.slotsOf('destinations'), [
        'tab-profile',
        'tab-home',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

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
                destinations: [
                  SuperAction(
                    id: 'p1',
                    config: SuperActionConfig(label: 'Inbox', icon: 'home'),
                  ),
                  SuperAction(
                    id: 'p2',
                    config: SuperActionConfig(label: 'Sent', icon: 'send'),
                  ),
                ],
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
      controller.value = controller.value.withRegionEnabled(
        'destinations',
        false,
      );
      await tester.pumpAndSettle();

      final appearance = AppearanceScope.of(
        tester.element(find.byType(SuperNavigationRail)),
      );
      final json = AppearanceStore.encode(appearance);
      final decoded = AppearanceStore.decode(json);

      final restoredConfig = decoded.nativeComponent('persisted-rail');
      expect(restoredConfig.isEnabled('destinations'), isFalse);
    },
  );

  test('Registry bootstrap includes NavigationRail, BottomNavigationBar and BottomAppBar', () {
    final registry = Registry()..bootstrap();
    expect(registry.registry.containsKey('NavigationRail'), isTrue);
    expect(registry.registry.containsKey('BottomNavigationBar'), isTrue);
    expect(registry.registry.containsKey('BottomAppBar'), isTrue);

    final railBuilder = registry.registry['NavigationRail']!;
    expect(railBuilder.menuIcon, Icons.view_sidebar_outlined);
    expect(railBuilder.tags, contains('navigationRail'));
    expect(railBuilder.placementTags, isEmpty);
    expect(
      railBuilder.getWidget(XuiBuildCtx(id: 'dynamic-rail')),
      isA<SuperNavigationRail>(),
    );

    final bottomNavBuilder = registry.registry['BottomNavigationBar']!;
    expect(bottomNavBuilder.tags, contains('bottomNavigationBar'));
    expect(bottomNavBuilder.placementTags, contains('bottomNavigationBar'));
    expect(
      bottomNavBuilder.getWidget(XuiBuildCtx(id: 'dynamic-bottom-nav')),
      isA<SuperBottomNavigationBar>(),
    );

    final bottomAppBarBuilder = registry.registry['BottomAppBar']!;
    expect(bottomAppBarBuilder.tags, contains('bottomNavigationBar'));
    expect(bottomAppBarBuilder.placementTags, contains('bottomNavigationBar'));
    expect(
      bottomAppBarBuilder.getWidget(XuiBuildCtx(id: 'dynamic-bottom-app-bar')),
      isA<SuperBottomAppBar>(),
    );
  });

  test(
    'JsonComponentType normalizes NavigationRail, BottomAppBar and aliases',
    () {
      expect(
        JsonComponentType.normalize('NavigationRail'),
        'registry:NavigationRail',
      );
      expect(JsonComponentType.normalize('Rail'), 'registry:NavigationRail');
      expect(
        JsonComponentType.normalize('BottomNavigationBar'),
        'registry:BottomNavigationBar',
      );
      expect(
        JsonComponentType.normalize('BottomAppBar'),
        'registry:BottomAppBar',
      );
      expect(JsonComponentType.normalize('BottomBar'), 'registry:BottomAppBar');
    },
  );
}
