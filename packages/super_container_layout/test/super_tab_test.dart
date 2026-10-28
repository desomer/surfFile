import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late JsonRepositoryStore repositoryStore;
  late String repositoryId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    directory = await Directory.systemTemp.createTemp('super-tab-test-');
    repositoryStore = JsonRepositoryStore(directory);
    await repositoryStore.create('TabRepo');
    repositoryId = await repositoryStore.idOf('TabRepo');
  });

  tearDown(() async {
    repositoryStore.dispose();
    await directory.delete(recursive: true);
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> real(
    WidgetTester tester,
    Future<void> Function() action, {
    bool save = false,
  }) async {
    await tester.runAsync(() async {
      await action();
      await tester.pump();
      await Future<void>.delayed(Duration(milliseconds: save ? 500 : 120));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    });
    await tester.pumpAndSettle();
  }

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
    await real(
      tester,
      () => tester.pumpWidget(
        SuperApp(
          router: router,
          registry: registry,
          repositoryStore: repositoryStore,
          appearanceStore: store ?? AppearanceStore(),
        ),
      ),
    );
  }

  test(
    'SuperTabConfig round-trips through JSON and ComponentConfigCatalog',
    () {
      final config = SuperTabConfig(
        mode: SuperTabMode.static,
        tabBarPosition: SuperTabBarPosition.bottom,
        isScrollable: true,
        initialIndex: 1,
        binding: JsonTextBinding(repositoryId: repositoryId, path: 'ui.tab'),
        tabBarStyle: const ContainerStyle(
          color: Color(0xFF1E293B),
          radius: 16,
          borderWidth: 2,
          borderColor: Color(0xFF38BDF8),
          elevation: 6,
          padding: 4,
          margin: 8,
        ),
        indicatorKind: SuperTabIndicatorKind.box,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: const Color(0xFF0EA5E9),
        indicatorWeight: 3,
        indicatorRadius: 12,
        indicatorHorizontalPadding: 6,
        indicatorVerticalPadding: 4,
        labelColor: const Color(0xFFFFFFFF),
        unselectedLabelColor: const Color(0xFF94A3B8),
        overlayColor: const Color(0x3338BDF8),
        labelHorizontalPadding: 20,
        dividerColor: const Color(0xFF334155),
        dividerHeight: 2,
        tabAlignment: TabAlignment.start,
        placements: const {
          'tabs': ['tab-1', 'tab-2'],
          'content:tab-1': ['val-1'],
          'content:tab-2': ['val-2'],
        },
        slotTypes: const {
          'tab-1': 'registry:Action',
          'tab-2': 'registry:Action',
          'val-1': 'registry:Value',
          'val-2': 'registry:Value',
        },
        zoneAxes: const {'content:tab-1': Axis.horizontal},
        slotLabels: const {'tab-1': 'Premier onglet'},
      );

      final typedJson = config.toTypedJson();
      expect(typedJson['type'], 'tab');
      final decoded = ComponentConfig.fromJson(typedJson);
      expect(decoded, isA<SuperTabConfig>());
      expect(decoded, equals(config));

      final compactJson = config.toTypedCompactJson();
      expect(ComponentConfig.fromJson(compactJson), equals(config));

      // Removing a tab slot also removes its content zone and children
      final afterRemove = config.withoutSlot('tab-1');
      expect(afterRemove.tabSlotIds, ['tab-2']);
      expect(afterRemove.slotsOf('content:tab-1'), isEmpty);
      expect(afterRemove.placedSlotIds, {'tab-2', 'val-2'});
      expect(afterRemove.zoneAxes.containsKey('content:tab-1'), isFalse);
    },
  );

  testWidgets(
    'SuperTab static mode renders TabBar with SuperAction tabs and switches TabBarView contents',
    (tester) async {
      final registry = Registry()..bootstrap();
      var selectedIndex = -1;
      var secondTabClicked = false;

      await mount(
        SuperPage(
          child: SuperTab(
            id: 'my-tabs',
            onTabSelected: (index) => selectedIndex = index,
            tabs: [
              const SuperAction(
                id: 'tab-general',
                config: SuperActionConfig(
                  kind: SuperActionKind.textAndIcon,
                  label: 'Général',
                  icon: 'home',
                ),
              ),
              SuperAction(
                id: 'tab-details',
                onPressed: () => secondTabClicked = true,
                config: const SuperActionConfig(
                  kind: SuperActionKind.textAndIcon,
                  label: 'Détails',
                  icon: 'settings',
                ),
              ),
              const SuperAction(
                id: 'tab-disabled',
                config: SuperActionConfig(label: 'Verrouillé', enabled: false),
              ),
            ],
            children: const [
              Center(child: Text('Contenu Général')),
              Center(child: Text('Contenu Détails')),
              Center(child: Text('Contenu Verrouillé')),
            ],
          ),
        ),
        tester,
        registry,
      );

      expect(find.byType(SuperTab), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(TabBarView), findsOneWidget);
      expect(find.text('Général'), findsOneWidget);
      expect(find.text('Détails'), findsOneWidget);
      expect(find.text('Contenu Général'), findsOneWidget);

      // Tap second tab
      await tester.tap(find.text('Détails'));
      await tester.pumpAndSettle();
      expect(selectedIndex, 1);
      expect(secondTabClicked, isTrue);
      expect(find.text('Contenu Détails'), findsOneWidget);

      // Tapping disabled tab keeps current selection
      await tester.tap(find.text('Verrouillé'));
      await tester.pumpAndSettle();
      expect(selectedIndex, 1);
      expect(find.text('Contenu Détails'), findsOneWidget);

      // Updating SuperAction config via Registry updates the TabBar
      registry.actionController('tab-general').value = const SuperActionConfig(
        label: 'Vue principale',
        icon: 'star',
      );
      await tester.pumpAndSettle();
      expect(find.text('Vue principale'), findsOneWidget);

      // Removing a tab slot in edit mode also purges its content children
      final tabController = registry.tabController('my-tabs');
      tabController.value = SuperTabConfig(
        placements: const {
          'tabs': ['tab-a', 'tab-b'],
          'content:tab-a': ['val-a'],
          'content:tab-b': ['val-b'],
        },
        slotTypes: const {
          'tab-a': 'registry:Action',
          'tab-b': 'registry:Action',
          'val-a': 'registry:Value',
          'val-b': 'registry:Value',
        },
      );
      registry.actionController('tab-a').value = const SuperActionConfig(
        label: 'Onglet A',
      );
      registry.actionController('tab-b').value = const SuperActionConfig(
        label: 'Onglet B',
      );
      registry.valueController('val-a').value = const SuperValueConfig(
        initialText: 'Valeur A',
      );
      registry.valueController('val-b').value = const SuperValueConfig(
        initialText: 'Valeur B',
      );
      await tester.pumpAndSettle();

      expect(find.text('Onglet A'), findsOneWidget);
      expect(find.text('Onglet B'), findsOneWidget);
      expect(find.text('Valeur B'), findsOneWidget);
      await tester.tap(find.text('Onglet A'));
      await tester.pumpAndSettle();
      expect(find.text('Valeur A'), findsOneWidget);

      // Test page duplication remaps content:<tabId> regions
      final appearance =
          AppearanceScope.controllerOf(tester.element(find.byType(SuperTab)))!
              .value
              .withComponent(
                'root',
                ScaffoldPageConfig(
                  placements: {
                    ScaffoldPageRegion.body: const ['my-tabs'],
                  },
                  slotTypes: const {'my-tabs': 'registry:Tab'},
                ),
              );
      final duplicated = EditorPageGraph.duplicate(
        appearance: appearance,
        registry: registry,
        sourcePageId: 'root',
        targetPageId: 'page-copy',
      );
      final copiedTabs = duplicated.componentsOfType<SuperTabConfig>();
      expect(copiedTabs.length, 2);
      final copiedTabConfig = copiedTabs.entries
          .firstWhere((e) => e.key != 'my-tabs')
          .value;
      expect(copiedTabConfig.tabSlotIds.length, 2);
      for (final newTabId in copiedTabConfig.tabSlotIds) {
        expect(newTabId, isNot(anyOf('tab-a', 'tab-b')));
        expect(
          copiedTabConfig.slotsOf(SuperTabConfig.contentZoneFor(newTabId)),
          hasLength(1),
        );
      }
    },
  );

  testWidgets(
    'SuperTab dynamic mode generates tabs and contents from JSON repository array with JsonListScope',
    (tester) async {
      final arrayBinding = JsonTextBinding(
        repositoryId: repositoryId,
        path: 'categories',
      );
      await tester.runAsync(() async {
        await repositoryStore.appendArrayItem(
          repositoryId,
          'categories',
          expectedLength: 0,
        );
        await repositoryStore.writeAttribute(
          JsonTextBinding(
            repositoryId: repositoryId,
            path: 'categories[0].nom',
          ),
          'Fruits',
          expectedValue: null,
        );
        await repositoryStore.writeAttribute(
          JsonTextBinding(
            repositoryId: repositoryId,
            path: 'categories[0].detail',
          ),
          'Pommes et poires',
          expectedValue: null,
        );
        await repositoryStore.appendArrayItem(
          repositoryId,
          'categories',
          expectedLength: 1,
        );
        await repositoryStore.writeAttribute(
          JsonTextBinding(
            repositoryId: repositoryId,
            path: 'categories[1].nom',
          ),
          'Légumes',
          expectedValue: '',
        );
        await repositoryStore.writeAttribute(
          JsonTextBinding(
            repositoryId: repositoryId,
            path: 'categories[1].detail',
          ),
          'Carottes et poireaux',
          expectedValue: '',
        );
      });

      final registry = Registry()..bootstrap();
      registry.tabController('dyn-tabs').value = SuperTabConfig(
        mode: SuperTabMode.dynamic,
        binding: arrayBinding,
        allowAdd: true,
        allowRemove: true,
        placements: const {
          'tabs': ['tpl-action'],
          'content': ['tpl-value'],
        },
        slotTypes: const {
          'tpl-action': 'registry:Action',
          'tpl-value': 'registry:Value',
        },
      );
      registry.valueController(
        'tpl-value',
        fallback: SuperValueConfig(
          mode: SuperValueMode.display,
          binding: JsonTextBinding(
            repositoryId: repositoryId,
            path: 'categories[?].detail',
          ),
        ),
      );
      registry.actionController(
        'tpl-action',
        fallback: SuperActionConfig(
          label: 'Catégorie',
          propertyBindings: {
            SuperActionProperty.label: JsonTextBinding(
              repositoryId: repositoryId,
              path: 'categories[?].nom',
            ),
          },
        ),
      );

      await mount(
        const SuperPage(child: SuperTab(id: 'dyn-tabs')),
        tester,
        registry,
      );
      await real(tester, () async {});

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('Fruits'), findsOneWidget);
      expect(find.text('Légumes'), findsOneWidget);
      expect(find.text('Pommes et poires'), findsOneWidget);

      // Select second dynamic tab
      await real(tester, () async {
        await tester.tap(find.text('Légumes'));
      });

      expect(find.text('Carottes et poireaux'), findsOneWidget);
      expect(
        repositoryStore
            .bindingOf(repositoryId)
            .array('categories')
            .indexFor(const []),
        1,
      );

      // Add a third dynamic tab via the + button
      await real(tester, () async {
        await tester.tap(find.byKey(const ValueKey('super-tab-add-dyn-tabs')));
      });

      final updatedItems = await tester.runAsync(
        () => repositoryStore.readArray(repositoryId, 'categories'),
      );
      expect(updatedItems, hasLength(3));

      // Remove the first dynamic tab via its close button
      await real(tester, () async {
        await tester.tap(
          find.byKey(const ValueKey('super-tab-remove-dyn-tabs-0')),
        );
      });
      final afterRemoveItems = await tester.runAsync(
        () => repositoryStore.readArray(repositoryId, 'categories'),
      );
      expect(afterRemoveItems, hasLength(2));
    },
  );

  testWidgets(
    'SuperTab static mode supports two-way active index binding and bottom/scrollable TabBar',
    (tester) async {
      final indexBinding = JsonTextBinding(
        repositoryId: repositoryId,
        path: 'ui.activeTab',
      );
      await tester.runAsync(
        () => repositoryStore.writeAttribute(
          indexBinding,
          '1',
          expectedValue: null,
        ),
      );

      final registry = Registry()..bootstrap();
      await mount(
        SuperPage(
          child: SuperTab(
            id: 'bound-static-tabs',
            config: SuperTabConfig(
              tabBarPosition: SuperTabBarPosition.bottom,
              isScrollable: true,
              binding: indexBinding,
              placements: const {
                'tabs': ['t0', 't1'],
                'content:t0': ['c0'],
                'content:t1': ['c1'],
              },
            ),
            tabs: const [
              SuperAction(
                id: 't0',
                config: SuperActionConfig(label: 'Tab 0'),
              ),
              SuperAction(
                id: 't1',
                config: SuperActionConfig(label: 'Tab 1'),
              ),
            ],
            slots: [
              BuilderSlot(
                id: 'c0',
                label: 'C0',
                builder: (_) => const Text('Vue 0'),
              ),
              BuilderSlot(
                id: 'c1',
                label: 'C1',
                builder: (_) => const Text('Vue 1'),
              ),
            ],
          ),
        ),
        tester,
        registry,
      );

      // Repository initial value is '1' -> Tab 1 is active
      expect(find.text('Vue 1'), findsOneWidget);
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.isScrollable, isTrue);

      // Tap Tab 0 -> writes '0' to repository
      await real(tester, () async {
        await tester.tap(find.text('Tab 0'));
      });
      expect(find.text('Vue 0'), findsOneWidget);
      final stored = await tester.runAsync(
        () => repositoryStore.readAttribute(indexBinding),
      );
      expect(stored?.text, '0');
    },
  );

  testWidgets(
    'SuperTab renders full TabBar styles (StyledSurface, box/underline/none indicator, colors, divider) and opens full style editor from zone Onglets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final registry = Registry()..bootstrap();
      const customStyle = ContainerStyle(
        color: Color(0xFF0F172A),
        radius: 18,
        borderWidth: 2,
        borderColor: Color(0xFF6366F1),
        padding: 6,
      );

      await mount(
        SuperPage(
          child: SuperTab(
            id: 'styled-tabs',
            config: SuperTabConfig(
              tabBarStyle: customStyle,
              indicatorKind: SuperTabIndicatorKind.box,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorColor: const Color(0xFF4F46E5),
              indicatorRadius: 12,
              indicatorHorizontalPadding: 8,
              indicatorVerticalPadding: 4,
              labelColor: const Color(0xFFFFFFFF),
              unselectedLabelColor: const Color(0xFF94A3B8),
              dividerColor: const Color(0xFF334155),
              dividerHeight: 0,
              placements: const {
                'tabs': ['st-1', 'st-2'],
                'content:st-1': ['sc-1'],
                'content:st-2': ['sc-2'],
              },
            ),
            tabs: const [
              SuperAction(
                id: 'st-1',
                config: SuperActionConfig(label: 'Design'),
              ),
              SuperAction(
                id: 'st-2',
                config: SuperActionConfig(label: 'Code'),
              ),
            ],
            slots: [
              BuilderSlot(
                id: 'sc-1',
                label: 'SC1',
                builder: (_) => const Text('Vue Design'),
              ),
              BuilderSlot(
                id: 'sc-2',
                label: 'SC2',
                builder: (_) => const Text('Vue Code'),
              ),
            ],
          ),
        ),
        tester,
        registry,
      );

      final surfaceFinder = find.byKey(
        const ValueKey('super-tab-surface-styled-tabs'),
      );
      expect(surfaceFinder, findsOneWidget);
      final styledSurface = tester.widget<StyledSurface>(surfaceFinder);
      expect(styledSurface.style.color, const Color(0xFF0F172A));
      expect(styledSurface.style.radius, 18);

      final tabBar = tester.widget<TabBar>(
        find.byKey(const ValueKey('super-tab-bar-styled-tabs')),
      );
      expect(tabBar.indicator, isA<BoxDecoration>());
      final boxIndicator = tabBar.indicator! as BoxDecoration;
      expect(boxIndicator.color, const Color(0xFF4F46E5));
      expect(boxIndicator.borderRadius, BorderRadius.circular(12));
      expect(tabBar.labelColor, const Color(0xFFFFFFFF));
      expect(tabBar.unselectedLabelColor, const Color(0xFF94A3B8));
      expect(tabBar.dividerHeight, 0);

      final editorState = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperTab),
          matching: find.byType(NativeComponentEditor),
        ),
      );

      // 1) Component Tab & content zones open the simple properties dialog (showSuperTabEditor)
      expect(
        editorState
            .definition(SuperTabConfig.contentZoneFor('st-1'))
            .menuDestination,
        EditorMenuDestination.configuration,
      );
      final simpleFuture = editorState.configure();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('super-tab-settings')), findsOneWidget);
      expect(find.byType(ContainerStyleEditor), findsNothing);
      await tester.tap(find.byKey(const ValueKey('super-tab-apply')));
      await tester.pumpAndSettle();
      await simpleFuture;

      // 2) Only zone Onglets uses EditorMenuDestination.style and opens the full ContainerStyleEditor panel
      expect(
        editorState.definition(SuperTabConfig.tabsZone).menuDestination,
        EditorMenuDestination.style,
      );

      final styleFuture = editorState.widget.onEditRegion!(
        SuperTabConfig.tabsZone,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('super-tab-bar-style-settings')),
        findsOneWidget,
      );
      expect(find.byType(ContainerStyleEditor), findsOneWidget);
      expect(find.byType(StyleEditorPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey('super-tab-indicator-kind')),
        findsOneWidget,
      );

      // Apply the style editor dialog
      await tester.tap(find.byKey(const ValueKey('super-tab-bar-style-apply')));
      await tester.pumpAndSettle();
      await styleFuture;
    },
  );

  testWidgets(
    'SuperTab lays out and switches tabs inside an unbounded vertical scrollable parent',
    (tester) async {
      final registry = Registry()..bootstrap();
      registry.tabController(
        'scroll-static-tabs',
        fallback: SuperTabConfig(
          placements: const {
            'tabs': ['st-a', 'st-b'],
            'content:st-a': ['val-a'],
            'content:st-b': ['val-b'],
          },
          slotTypes: const {
            'st-a': 'registry:Action',
            'st-b': 'registry:Action',
            'val-a': 'registry:Value',
            'val-b': 'registry:Value',
          },
        ),
      );
      registry.actionController(
        'st-a',
        fallback: const SuperActionConfig(label: 'Joyeuses Fêtes'),
      );
      registry.actionController(
        'st-b',
        fallback: const SuperActionConfig(label: 'Anniversaire'),
      );
      registry.valueController(
        'val-a',
        fallback: const SuperValueConfig(initialText: 'Cartes de fêtes'),
      );
      registry.valueController(
        'val-b',
        fallback: const SuperValueConfig(initialText: 'Cartes anniversaire'),
      );

      await mount(
        SuperPage(
          id: 'scroll-page',
          pageConfig: ScaffoldPageConfig(
            bodyMode: ScaffoldBodyMode.singleChildScrollView,
            placements: {
              ScaffoldPageRegion.body: const [
                'scroll-static-tabs',
                'scroll-empty-tabs',
              ],
            },
            slotTypes: const {
              'scroll-static-tabs': 'factory:Tab',
              'scroll-empty-tabs': 'factory:Tab',
            },
          ),
        ),
        tester,
        registry,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Joyeuses Fêtes'), findsOneWidget);
      expect(find.text('Anniversaire'), findsOneWidget);
      expect(find.text('Cartes de fêtes'), findsOneWidget);
      expect(find.text('Cartes anniversaire'), findsNothing);
      expect(
        find.byKey(const ValueKey('super-tab-empty-scroll-empty-tabs')),
        findsOneWidget,
      );

      await tester.tap(find.text('Anniversaire'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Cartes anniversaire'), findsOneWidget);
      expect(find.text('Cartes de fêtes'), findsNothing);
    },
  );
}
