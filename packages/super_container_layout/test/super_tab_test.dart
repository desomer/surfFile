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

  test('SuperTabConfig round-trips through JSON and ComponentConfigCatalog', () {
    final config = SuperTabConfig(
      mode: SuperTabMode.static,
      tabBarPosition: SuperTabBarPosition.bottom,
      isScrollable: true,
      initialIndex: 1,
      binding: JsonTextBinding(repositoryId: repositoryId, path: 'ui.tab'),
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
  });

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
                config: SuperActionConfig(
                  label: 'Verrouillé',
                  enabled: false,
                ),
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
      final appearance = AppearanceScope.controllerOf(
        tester.element(find.byType(SuperTab)),
      )!.value.withComponent(
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
      registry.valueController('tpl-value', fallback: SuperValueConfig(
        mode: SuperValueMode.display,
        binding: JsonTextBinding(
          repositoryId: repositoryId,
          path: 'categories[?].detail',
        ),
      ));
      registry.actionController('tpl-action', fallback: SuperActionConfig(
        label: 'Catégorie',
        propertyBindings: {
          SuperActionProperty.label: JsonTextBinding(
            repositoryId: repositoryId,
            path: 'categories[?].nom',
          ),
        },
      ));

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
}
