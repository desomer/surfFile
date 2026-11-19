import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
    'static tab header supports onTooltip without changing selection',
    (tester) async {
      await mount(
        const SuperPage(
          child: SuperTab(
            tab: SuperAction(
              id: 'tab-tooltip',
              config: SuperActionConfig(
                label: 'Tooltip tab',
                tooltip: 'Native tab',
              ),
              behaviours: [
                ComponentBehavior(
                  id: 'tab-hover',
                  trigger: BehaviorTrigger.hover,
                  action: TooltipAction(message: 'Tab behavior'),
                ),
              ],
            ),
          ),
        ),
        tester,
        Registry()..bootstrap(),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Tooltip tab')));
      await tester.pumpAndSettle();
      expect(find.text('Tab behavior'), findsOneWidget);
      expect(find.text('Native tab'), findsNothing);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(find.text('Tab behavior'), findsNothing);
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

      final tooltipAppearance = ValueNotifier(
        Appearance(
          behaviors: {
            'tpl-action': [
              const ComponentBehavior(
                id: 'tab-description',
                trigger: BehaviorTrigger.hover,
                action: TooltipAction(
                  binding: JsonTextBinding(path: 'categories[?].detail'),
                ),
              ),
            ],
          },
        ),
      );
      addTearDown(tooltipAppearance.dispose);
      await mount(
        AppearanceScope(
          controller: tooltipAppearance,
          child: const SuperPage(child: SuperTab(id: 'dyn-tabs')),
        ),
        tester,
        registry,
      );
      await real(tester, () async {});

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('Fruits'), findsOneWidget);
      expect(find.text('Légumes'), findsOneWidget);
      expect(find.text('Pommes et poires'), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Fruits')));
      await tester.pumpAndSettle();
      expect(find.text('Pommes et poires'), findsNWidgets(2));
      await mouse.moveTo(tester.getCenter(find.text('Légumes')));
      await tester.pumpAndSettle();
      expect(find.text('Carottes et poireaux'), findsOneWidget);
      expect(find.text('Pommes et poires'), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(find.text('Carottes et poireaux'), findsNothing);

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

  testWidgets(
    'SuperAction inside SuperTab respects margin, elevation, padding and surface styles',
    (tester) async {
      final registry = Registry()..bootstrap();
      registry.tabController(
        'styled-action-tabs',
        fallback: SuperTabConfig(
          placements: const {
            'tabs': ['tab-act-1', 'tab-act-2'],
            'content:tab-act-1': ['content-1'],
            'content:tab-act-2': ['content-2'],
          },
        ),
      );
      registry.actionController(
        'tab-act-1',
        fallback: const SuperActionConfig(
          label: 'Onglet Style 1',
          elevation: 4.0,
          horizontalPadding: 16,
          verticalPadding: 8,
          style: ContainerStyle(
            margin: 6,
            radius: 10,
            color: Color(0xFF1E293B),
            elevation: 4.0,
          ),
        ),
      );
      registry.actionController(
        'tab-act-2',
        fallback: const SuperActionConfig(label: 'Onglet Style 2'),
      );

      await mount(
        SuperPage(
          child: SuperTab(
            id: 'styled-action-tabs',
            config: SuperTabConfig(
              placements: const {
                'tabs': ['tab-act-1', 'tab-act-2'],
                'content:tab-act-1': ['content-1'],
                'content:tab-act-2': ['content-2'],
              },
            ),
            tabs: const [
              SuperAction(
                id: 'tab-act-1',
                config: SuperActionConfig(
                  label: 'Onglet Style 1',
                  elevation: 4.0,
                  horizontalPadding: 16,
                  verticalPadding: 8,
                  style: ContainerStyle(
                    margin: 6,
                    radius: 10,
                    color: Color(0xFF1E293B),
                    elevation: 4.0,
                  ),
                ),
              ),
              SuperAction(
                id: 'tab-act-2',
                config: SuperActionConfig(label: 'Onglet Style 2'),
              ),
            ],
            slots: [
              BuilderSlot(
                id: 'content-1',
                label: 'C1',
                builder: (_) => const Text('Contenu 1'),
              ),
              BuilderSlot(
                id: 'content-2',
                label: 'C2',
                builder: (_) => const Text('Contenu 2'),
              ),
            ],
          ),
        ),
        tester,
        registry,
      );

      final surfaceFinder = find.byKey(
        const ValueKey('super-action-surface-tab-act-1'),
      );
      expect(surfaceFinder, findsOneWidget);

      final styledSurface = tester.widget<StyledSurface>(surfaceFinder);
      expect(styledSurface.style.elevation, 4.0);
      expect(styledSurface.style.radius, 10.0);
      expect(styledSurface.style.color, const Color(0xFF1E293B));

      // Vérifier la marge extérieure (outerMargin de 6 px)
      final paddingWidgets = tester.widgetList<Padding>(
        find.ancestor(of: surfaceFinder, matching: find.byType(Padding)),
      );
      expect(
        paddingWidgets.any((p) => p.padding == const EdgeInsets.all(6.0)),
        isTrue,
      );

      // Vérifier le padding intérieur (16 horiz, 8 vert)
      final innerPadding = tester.widget<Padding>(
        find.descendant(
          of: surfaceFinder,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Padding &&
                w.padding ==
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      );
      expect(innerPadding, isNotNull);

      // Le clic sur l'onglet change bien de vue
      expect(find.text('Contenu 1'), findsOneWidget);
      await tester.tap(find.text('Onglet Style 2'));
      await tester.pumpAndSettle();
      expect(find.text('Contenu 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SuperActionConfig variant is null by default and resolves to text in tabs and filled elsewhere',
    (tester) async {
      const config = SuperActionConfig();
      expect(config.variant, isNull);
      expect(config.effectiveVariant(inTab: false), SuperActionVariant.filled);
      expect(config.effectiveVariant(inTab: true), SuperActionVariant.text);

      const explicit = SuperActionConfig(variant: SuperActionVariant.outlined);
      expect(explicit.variant, SuperActionVariant.outlined);
      expect(
        explicit.effectiveVariant(inTab: true),
        SuperActionVariant.outlined,
      );
      expect(
        explicit.effectiveVariant(inTab: false),
        SuperActionVariant.outlined,
      );

      final configurator = superActionAddConfigurator(const []);

      // Hors zone onglets : SuperActionAddForm initialise le dropdown à filled
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final draft =
                    configurator.initialDraft(context) as SuperActionConfig;
                return SuperActionAddForm(
                  draft: draft,
                  onChanged: (_) {},
                  availableFontFamilies: const [],
                );
              },
            ),
          ),
        ),
      );
      final dropdownOutside = tester
          .widget<DropdownButtonFormField<SuperActionVariant>>(
            find.byKey(const ValueKey('add-action-variant')),
          );
      expect(dropdownOutside.initialValue, SuperActionVariant.filled);

      // Dans la zone onglets via ComponentAddTargetScope : dropdown initialisé à text
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ComponentAddTargetScope(
              targetId: SuperTabConfig.tabsZone,
              targetLabel: 'Onglets',
              child: Builder(
                builder: (context) {
                  final draft =
                      configurator.initialDraft(context) as SuperActionConfig;
                  return SuperActionAddForm(
                    draft: draft,
                    onChanged: (_) {},
                    availableFontFamilies: const [],
                  );
                },
              ),
            ),
          ),
        ),
      );
      final dropdownInside = tester
          .widget<DropdownButtonFormField<SuperActionVariant>>(
            find.byKey(const ValueKey('add-action-variant')),
          );
      expect(dropdownInside.initialValue, SuperActionVariant.text);
    },
  );

  testWidgets(
    'updating SuperTabConfig while a region flow ListenableBuilder dialog is open does not throw markNeedsBuild during build',
    (tester) async {
      final registry = Registry()..bootstrap();
      final tabController = registry.tabController(
        'flow-tabs',
        fallback: SuperTabConfig(
          placements: const {
            'tabs': ['tab-a'],
            'content:tab-a': ['slot-a'],
          },
        ),
      );

      await mount(
        SuperPage(
          child: SuperTab(
            id: 'flow-tabs',
            config: tabController.value,
            tabs: const [
              SuperAction(
                id: 'tab-a',
                config: SuperActionConfig(label: 'Onglet A'),
              ),
            ],
            slots: [
              BuilderSlot(
                id: 'slot-a',
                label: 'Contenu A',
                builder: (_) => const Text('Vue A'),
              ),
            ],
          ),
        ),
        tester,
        registry,
      );

      final editorState = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperTab),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      final dialogFuture = editorState.configure(
        regionId: 'content:tab-a',
        initialTab: EditorWizardTab.dimensions,
      );
      await tester.pumpAndSettle();

      // Mutate SuperTabConfig while the dimensions tab ListenableBuilder is mounted in the dialog route
      tabController.value = tabController.value.copyWith(
        zoneFlows: const {'content:tab-a': ZoneFlowConfig(spacing: 12)},
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      await dialogFuture;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sliding between tabs keeps visited tab subtrees alive and does not re-evaluate cached calculated attributes',
    (tester) async {
      var tabACalcRuns = 0;
      var tabABuilds = 0;
      final repo =
          RepositoryImpl(
            id: 'tab_calc_repo',
            json: {
              'ui': {'tab': 0},
              'amount': 42,
            },
          )..addCalculatedAttribute('doubled', (ctx) {
            tabACalcRuns++;
            return (ctx.sync.getInt('amount') ?? 0) * 2;
          });
      repositoryStore.registerRepository(repo);

      final registry = Registry()..bootstrap();
      registry.valueController(
        'calc-val-a',
        fallback: const SuperValueConfig(
          binding: JsonTextBinding(
            repositoryId: 'tab_calc_repo',
            path: '@doubled',
          ),
        ),
      );
      registry.valueController(
        'plain-val-b',
        fallback: const SuperValueConfig(initialText: 'Contenu B'),
      );

      await mount(
        SuperPage(
          child: SuperTab(
            id: 'keepalive-tabs',
            config: SuperTabConfig(
              binding: const JsonTextBinding(
                repositoryId: 'tab_calc_repo',
                path: 'ui.tab',
              ),
              placements: const {
                'tabs': ['tab-a', 'tab-b'],
                'content:tab-a': ['slot-a'],
                'content:tab-b': ['slot-b'],
              },
            ),
            tabs: const [
              SuperAction(
                id: 'tab-a',
                config: SuperActionConfig(label: 'Onglet Calc'),
              ),
              SuperAction(
                id: 'tab-b',
                config: SuperActionConfig(label: 'Onglet Autre'),
              ),
            ],
            slots: [
              BuilderSlot(
                id: 'slot-a',
                label: 'Slot A',
                builder: (_) {
                  tabABuilds++;
                  return const SuperValue(
                    id: 'calc-val-a',
                    config: SuperValueConfig(
                      binding: JsonTextBinding(
                        repositoryId: 'tab_calc_repo',
                        path: '@doubled',
                      ),
                    ),
                  );
                },
              ),
              BuilderSlot(
                id: 'slot-b',
                label: 'Slot B',
                builder: (_) => const SuperValue(
                  id: 'plain-val-b',
                  config: SuperValueConfig(initialText: 'Contenu B'),
                ),
              ),
            ],
          ),
        ),
        tester,
        registry,
      );

      expect(find.text('84'), findsOneWidget);
      expect(tabACalcRuns, 1);
      final buildsAfterInitial = tabABuilds;

      // Slide to Tab B (also writes ui.tab = 1 in tab_calc_repo)
      await real(
        tester,
        () => tester.tap(find.text('Onglet Autre')),
        save: true,
      );
      expect(find.text('Contenu B'), findsOneWidget);
      expect(tabACalcRuns, 1);

      // Slide back to Tab A: Tab A was kept alive (not rebuilt from scratch)
      // and @doubled is still served from cache without recalculation.
      await real(
        tester,
        () => tester.tap(find.text('Onglet Calc')),
        save: true,
      );
      expect(find.text('84'), findsOneWidget);
      expect(tabACalcRuns, 1);
      expect(tabABuilds, buildsAfterInitial);
    },
  );

  testWidgets(
    'switching tabs in edit mode hides EditorOverlay and resize portals of kept-alive inactive tabs without NaN layout or hit-test errors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final registry = Registry()..bootstrap();
      registry.valueController(
        'val-dash',
        fallback: const SuperValueConfig(initialText: 'Vue Dashboard'),
      );
      registry.valueController(
        'val-settings',
        fallback: const SuperValueConfig(initialText: 'Vue Paramètres'),
      );

      await mount(
        SuperPage(
          child: Padding(
            padding: const EdgeInsets.only(top: 64),
            child: SuperTab(
              id: 'edit-keepalive-tabs',
              config: SuperTabConfig(
                placements: const {
                  'tabs': ['tab-dash', 'tab-settings'],
                  'content:tab-dash': ['val-dash'],
                  'content:tab-settings': ['val-settings'],
                },
                slotTypes: const {
                  'tab-dash': 'registry:Action',
                  'tab-settings': 'registry:Action',
                  'val-dash': 'registry:Value',
                  'val-settings': 'registry:Value',
                },
              ),
              tabs: const [
                SuperAction(
                  id: 'tab-dash',
                  config: SuperActionConfig(label: 'Dashboard'),
                ),
                SuperAction(
                  id: 'tab-settings',
                  config: SuperActionConfig(label: 'Paramètres'),
                ),
              ],
            ),
          ),
        ),
        tester,
        registry,
      );

      final tabContext = tester.element(find.byType(SuperTab));
      StyleEditScope.controllerOf(tabContext)!.value = true;
      await tester.pumpAndSettle();

      // Select the slot in tab-dash so both region EditorOverlay badges and
      // LabeledSlot resize OverlayPortals are active on tab-dash.
      await tester.tap(find.text('Vue Dashboard'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('super-tab-badge-content-content:tab-dash')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // Switch to Paramètres: tab-dash is kept alive in _keepAliveBucket with
      // a Matrix4.zero() paint transform.
      await tester.tap(find.text('Paramètres'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Vue Paramètres'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('super-tab-badge-content-content:tab-dash')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('super-tab-badge-content-content:tab-settings'),
        ),
        findsOneWidget,
      );

      // Hovering across the canvas must not hit-test any unlaid-out render box.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(200, 200));
      await tester.pump();
      await mouse.moveTo(const Offset(640, 450));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // VibeAppInspector geometry on the kept-alive inactive tab component
      // must report isOffscreen without throwing NaN rounding errors.
      final inspector = VibeAppInspector(
        readAppearance: () => AppearanceScope.controllerOf(tabContext)!.value,
        registry: registry,
        repositoryStore: repositoryStore,
      );
      final geometry = await tester.runAsync(
        () => inspector.getComponentGeometry({'id': 'val-dash'}),
      );
      expect(geometry, isNotNull);
      final components = geometry!['components']! as Map<String, Object?>;
      final valDashEntry = components['val-dash']! as Map<String, Object?>;
      final occurrences = valDashEntry['occurrences'] as List<Object?>;
      expect(occurrences, isNotEmpty);
      final firstOccurrence = occurrences.first! as Map<String, Object?>;
      expect(firstOccurrence.containsKey('bounds'), isFalse);
      final diagnostics =
          firstOccurrence['diagnostics']! as Map<String, Object?>;
      expect(diagnostics['isOffscreen'], isTrue);

      // Switch back to Dashboard: tab-dash overlays reappear cleanly.
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('super-tab-badge-content-content:tab-dash')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SuperTab dynamic mode with cached repository items mounts without build-time setState and preserves SuperValue focus after save',
    (tester) async {
      repositoryStore.registerRepository(
        RepositoryImpl(
          id: 'dyn_focus_repo',
          json: {
            'items': [
              {'name': 'Premier'},
              {'name': 'Second'},
            ],
          },
        ),
      );

      final registry = Registry()..bootstrap();
      await mount(
        SuperPage(
          child: SuperTab(
            id: 'dyn-focus-tabs',
            config: SuperTabConfig(
              mode: SuperTabMode.dynamic,
              binding: const JsonTextBinding(
                repositoryId: 'dyn_focus_repo',
                path: 'items',
              ),
              placements: const {
                'tabs': ['dyn-tab'],
                'content': ['dyn-val'],
              },
            ),
            slots: [
              BuilderSlot(
                id: 'dyn-tab',
                label: 'Onglet',
                builder: (_) => const SuperAction(
                  id: 'dyn-tab',
                  config: SuperActionConfig(
                    propertyBindings: {
                      SuperActionProperty.label: JsonTextBinding(
                        path: 'items[?].name',
                      ),
                    },
                  ),
                ),
              ),
              BuilderSlot(
                id: 'dyn-val',
                label: 'Valeur',
                builder: (_) => const SuperValue(
                  id: 'dyn-val',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    binding: JsonTextBinding(path: 'items[?].name'),
                  ),
                ),
              ),
            ],
          ),
        ),
        tester,
        registry,
      );
      expect(tester.takeException(), isNull);

      final input = find.byKey(const ValueKey('super-value-input-dyn-val'));
      final focusBefore = tester.widget<TextField>(input).focusNode!;
      await tester.tap(input);
      await tester.pumpAndSettle();
      expect(focusBefore.hasFocus, isTrue);

      await real(
        tester,
        () => tester.enterText(input, 'Premier modifié'),
        save: true,
      );

      final focusAfter = tester.widget<TextField>(input).focusNode!;
      expect(identical(focusBefore, focusAfter), isTrue);
      expect(focusAfter.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
