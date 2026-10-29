import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late String repository;

  setUp(() async {
    StyleEditorPanel.preferredDense = false;
    directory = await Directory.systemTemp.createTemp('super-tree-view-');
    store = JsonRepositoryStore(directory);
    await store.create('Catalog');
    repository = await store.idOf('Catalog');
    await store.save(
      'Catalog',
      jsonEncode({
        'nodes': [
          {
            'key': 'Parent 1',
            'data': 'Data P1',
            'children': [
              {'key': 'Child 1.1', 'data': 'Data C1.1', 'children': []},
              {'key': 'Child 1.2', 'data': 'Data C1.2', 'children': []},
            ],
          },
          {'key': 'Parent 2', 'data': 'Data P2', 'children': []},
        ],
      }),
      expectedText: await store.read('Catalog'),
    );
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
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
    WidgetTester tester,
    Widget child, {
    Registry? registry,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget app = MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 700, height: 800, child: child)),
      ),
    );
    if (registry != null) {
      SharedPreferences.setMockInitialValues({});
      for (final channel in [
        const MethodChannel('com.alexmercerind/flutter_acrylic'),
        WindowTransparency.channel,
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
      }
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Center(
                child: SizedBox(width: 700, height: 800, child: child),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      app = SuperApp(
        router: router,
        title: 'TreeView Test',
        registry: registry,
        repositoryStore: store,
      );
    }
    await real(
      tester,
      () => tester.pumpWidget(JsonRepositoryScope(store: store, child: app)),
    );
  }

  test('SuperTreeViewConfig serializes and deserializes through catalog', () {
    final config = SuperTreeViewConfig(
      binding: JsonTextBinding(repositoryId: repository, path: 'nodes'),
      childrenKey: 'items',
      headerSize: 260,
      rowHeight: 36,
      indent: 24,
      initiallyExpanded: false,
      showConnectors: false,
      showCheckboxes: true,
      emptyText: 'Vide',
      placements: const {
        SuperTreeViewConfig.headerZone: ['h1'],
        SuperTreeViewConfig.dataZone: ['d1'],
      },
      slotTypes: const {'h1': 'registry:Value', 'd1': 'registry:Value'},
    );

    final encoded = config.toTypedJson();
    final decoded = ComponentConfig.fromJson(encoded);
    expect(decoded, equals(config));
  });

  testWidgets(
    'SuperTreeView renders Header and Data zones bound to repository nodes',
    (tester) async {
      final registry = Registry()..bootstrap();
      await mount(
        tester,
        SuperTreeView(
          id: 'catalog-tree',
          config: SuperTreeViewConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'nodes'),
            childrenKey: 'children',
            headerSize: 220,
            rowHeight: 36,
            placements: const {
              SuperTreeViewConfig.headerZone: ['header'],
              SuperTreeViewConfig.dataZone: ['data'],
            },
          ),
          header: const SuperValue(
            id: 'node-header',
            config: SuperValueConfig(
              mode: SuperValueMode.display,
              binding: JsonTextBinding(path: 'key'),
            ),
          ),
          data: const SuperValue(
            id: 'node-data',
            config: SuperValueConfig(
              mode: SuperValueMode.display,
              binding: JsonTextBinding(path: 'nodes[?].data'),
            ),
          ),
        ),
        registry: registry,
      );

      expect(find.text('Parent 1'), findsOneWidget);
      expect(find.text('Data P1'), findsOneWidget);
      expect(find.text('Child 1.1'), findsOneWidget);
      expect(find.text('Data C1.1'), findsOneWidget);
      expect(find.text('Child 1.2'), findsOneWidget);
      expect(find.text('Data C1.2'), findsOneWidget);
      expect(find.text('Parent 2'), findsOneWidget);
      expect(find.text('Data P2'), findsOneWidget);
    },
  );

  testWidgets(
    'Selecting a nested node in SuperTreeView updates external master/detail SuperValue',
    (tester) async {
      String? selectedPath;
      await mount(
        tester,
        Column(
          children: [
            Expanded(
              child: SuperTreeView(
                id: 'catalog-tree',
                onNodeSelected: (path) => selectedPath = path,
                config: SuperTreeViewConfig(
                  binding: JsonTextBinding(
                    repositoryId: repository,
                    path: 'nodes',
                  ),
                  placements: const {
                    SuperTreeViewConfig.headerZone: ['header'],
                    SuperTreeViewConfig.dataZone: ['data'],
                  },
                ),
                header: const SuperValue(
                  id: 'node-header',
                  config: SuperValueConfig(
                    mode: SuperValueMode.display,
                    binding: JsonTextBinding(path: 'key'),
                  ),
                ),
                data: const SuperValue(
                  id: 'node-data',
                  config: SuperValueConfig(
                    mode: SuperValueMode.display,
                    binding: JsonTextBinding(path: 'data'),
                  ),
                ),
              ),
            ),
            SuperValue(
              id: 'selected-detail',
              config: SuperValueConfig(
                mode: SuperValueMode.display,
                binding: JsonTextBinding(
                  repositoryId: repository,
                  path: 'nodes[?].data',
                ),
              ),
            ),
          ],
        ),
      );

      await real(tester, () => tester.tap(find.text('Child 1.2')));
      expect(selectedPath, 'nodes[0].children[1]');
      expect(find.text('Data C1.2'), findsNWidgets(2));
    },
  );

  testWidgets(
    'Editing a SuperValue inside a nested tree node writes back to repository JSON',
    (tester) async {
      await mount(
        tester,
        SuperTreeView(
          id: 'catalog-tree',
          config: SuperTreeViewConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'nodes'),
            placements: const {
              SuperTreeViewConfig.headerZone: ['header'],
              SuperTreeViewConfig.dataZone: ['data'],
            },
          ),
          header: const SuperValue(
            id: 'node-header',
            config: SuperValueConfig(
              mode: SuperValueMode.display,
              binding: JsonTextBinding(path: 'key'),
            ),
          ),
          data: const SuperValue(
            id: 'node-data-input',
            config: SuperValueConfig(
              mode: SuperValueMode.input,
              binding: JsonTextBinding(path: 'data'),
            ),
          ),
        ),
      );

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(4));
      // Index 2 is Child 1.2 (nodes[0].children[1])
      await real(tester, () async {
        await tester.enterText(textFields.at(2), 'Updated C1.2');
        await store.flushBindings();
      }, save: true);

      final saved = jsonDecode(
        (await tester.runAsync(() => store.read('Catalog')))!,
      ) as Map<String, dynamic>;
      final nodes = saved['nodes'] as List<dynamic>;
      final children =
          (nodes[0] as Map<String, dynamic>)['children'] as List<dynamic>;
      expect((children[1] as Map<String, dynamic>)['data'], 'Updated C1.2');
    },
  );

  test(
    'EditorPageGraph duplicates SuperTreeView and its Header/Data slots',
    () {
      final registry = Registry()..bootstrap();
      final source = Appearance(
        components: {
          'page-1': NativeComponentConfig(
            placements: const {
              'body': ['tree-1'],
            },
            slotTypes: const {'tree-1': 'registry:TreeView'},
          ),
          'tree-1': SuperTreeViewConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'nodes'),
            placements: const {
              SuperTreeViewConfig.headerZone: ['h-val'],
              SuperTreeViewConfig.dataZone: ['d-val'],
            },
            slotTypes: const {
              'h-val': 'registry:Value',
              'd-val': 'registry:Value',
            },
          ),
          'h-val': const SuperValueConfig(
            binding: JsonTextBinding(path: 'key'),
          ),
          'd-val': const SuperValueConfig(
            binding: JsonTextBinding(path: 'data'),
          ),
        },
      );

      final duplicated = EditorPageGraph.duplicate(
        appearance: source,
        registry: registry,
        sourcePageId: 'page-1',
        targetPageId: 'page-2',
      );

      final copiedPage = duplicated.nativeComponent('page-2');
      final copiedTreeId = copiedPage.slotsOf('body').single;
      expect(copiedTreeId, isNot('tree-1'));
      final copiedTree = duplicated.treeViewComponent(copiedTreeId);
      expect(copiedTree.binding, source.treeViewComponent('tree-1').binding);
      final copiedHeaderSlot = copiedTree
          .slotsOf(SuperTreeViewConfig.headerZone)
          .single;
      final copiedDataSlot = copiedTree
          .slotsOf(SuperTreeViewConfig.dataZone)
          .single;
      expect(copiedHeaderSlot, isNot('h-val'));
      expect(copiedDataSlot, isNot('d-val'));
      expect(duplicated.valueComponent(copiedHeaderSlot).binding?.path, 'key');
      expect(duplicated.valueComponent(copiedDataSlot).binding?.path, 'data');
    },
  );

  testWidgets(
    'Clicking rows in SuperTreeView does not recreate or flicker bound SuperValues',
    (tester) async {
      await mount(
        tester,
        SuperTreeView(
          id: 'catalog-tree',
          config: SuperTreeViewConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'nodes'),
            placements: const {
              SuperTreeViewConfig.headerZone: ['header'],
              SuperTreeViewConfig.dataZone: ['data'],
            },
          ),
          header: const SuperValue(
            id: 'node-header',
            config: SuperValueConfig(
              mode: SuperValueMode.display,
              binding: JsonTextBinding(path: 'key'),
            ),
          ),
          data: const SuperValue(
            id: 'node-data',
            config: SuperValueConfig(
              mode: SuperValueMode.display,
              binding: JsonTextBinding(path: 'data'),
            ),
          ),
        ),
      );

      final beforeElements = tester
          .elementList(find.byType(SuperValue))
          .toList();
      expect(beforeElements.length, 8);

      // Tap a row and pump only a single frame (without waiting for async I/O):
      // all SuperValue texts must remain immediately present without flickering.
      await tester.tap(find.text('Child 1.1'));
      await tester.pump();

      expect(find.text('Parent 1'), findsOneWidget);
      expect(find.text('Data P1'), findsOneWidget);
      expect(find.text('Child 1.1'), findsOneWidget);
      expect(find.text('Data C1.1'), findsOneWidget);
      expect(find.text('Child 1.2'), findsOneWidget);
      expect(find.text('Data C1.2'), findsOneWidget);
      expect(find.text('Parent 2'), findsOneWidget);
      expect(find.text('Data P2'), findsOneWidget);

      final afterElements = tester
          .elementList(find.byType(SuperValue))
          .toList();
      expect(afterElements, equals(beforeElements));
    },
  );

  testWidgets(
    'Collapsing and expanding a parent node does not flicker parent or sibling SuperValues',
    (tester) async {
      await mount(
        tester,
        SuperTreeView(
          id: 'catalog-tree',
          config: SuperTreeViewConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'nodes'),
            placements: const {
              SuperTreeViewConfig.headerZone: ['header'],
              SuperTreeViewConfig.dataZone: ['data'],
            },
          ),
          header: const SuperValue(
            id: 'node-header',
            config: SuperValueConfig(
              mode: SuperValueMode.display,
              binding: JsonTextBinding(path: 'key'),
            ),
          ),
          data: const SuperValue(
            id: 'node-data',
            config: SuperValueConfig(
              mode: SuperValueMode.display,
              binding: JsonTextBinding(path: 'data'),
            ),
          ),
        ),
      );

      final initialElements = tester
          .elementList(find.byType(SuperValue))
          .toList();
      expect(initialElements.length, 8);

      // Tap collapse arrow on Parent 1
      await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
      // Frame 1 (start of collapse animation)
      await tester.pump();
      expect(find.text('Parent 1'), findsOneWidget);
      expect(find.text('Data P1'), findsOneWidget);
      expect(find.text('Child 1.1'), findsOneWidget);
      expect(find.text('Data C1.1'), findsOneWidget);
      expect(find.text('Parent 2'), findsOneWidget);
      expect(find.text('Data P2'), findsOneWidget);

      // Mid-animation (100ms)
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Parent 1'), findsOneWidget);
      expect(find.text('Data P1'), findsOneWidget);
      expect(find.text('Child 1.1'), findsOneWidget);
      expect(find.text('Data C1.1'), findsOneWidget);
      expect(find.text('Parent 2'), findsOneWidget);
      expect(find.text('Data P2'), findsOneWidget);

      // End of collapse (after 200ms Future.delayed)
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.text('Parent 1'), findsOneWidget);
      expect(find.text('Data P1'), findsOneWidget);
      expect(find.text('Parent 2'), findsOneWidget);
      expect(find.text('Data P2'), findsOneWidget);

      final collapsedElements = tester
          .elementList(find.byType(SuperValue))
          .toList();
      expect(collapsedElements, equals(initialElements));

      // Now expand Parent 1 again
      await tester.tap(find.byIcon(Icons.arrow_right_sharp).first);
      // Frame 1 of re-expansion: even Child 1.1 and Child 1.2 are immediately
      // present without flickering!
      await tester.pump();
      expect(find.text('Parent 1'), findsOneWidget);
      expect(find.text('Data P1'), findsOneWidget);
      expect(find.text('Child 1.1'), findsOneWidget);
      expect(find.text('Data C1.1'), findsOneWidget);
      expect(find.text('Child 1.2'), findsOneWidget);
      expect(find.text('Data C1.2'), findsOneWidget);
      expect(find.text('Parent 2'), findsOneWidget);
      expect(find.text('Data P2'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Parent 1'), findsOneWidget);
      expect(find.text('Data P1'), findsOneWidget);
      expect(find.text('Child 1.1'), findsOneWidget);
      expect(find.text('Data C1.1'), findsOneWidget);

      await tester.pumpAndSettle();
      final reexpandedElements = tester
          .elementList(find.byType(SuperValue))
          .toList();
      expect(reexpandedElements, equals(initialElements));
    },
  );
}
