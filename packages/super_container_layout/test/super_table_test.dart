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
    directory = await Directory.systemTemp.createTemp('super-table-');
    store = JsonRepositoryStore(directory);
    await store.create('CRM');
    repository = await store.idOf('CRM');
    await store.save(
      'CRM',
      jsonEncode({
        'clients': [
          {'nom': 'Alice', 'ville': 'Paris', 'role': 'Admin'},
          {'nom': 'Bob', 'ville': 'Lyon', 'role': 'User'},
        ],
      }),
      expectedText: await store.read('CRM'),
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
        body: Center(child: SizedBox(width: 800, height: 600, child: child)),
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
                child: SizedBox(width: 800, height: 600, child: child),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      app = SuperApp(
        router: router,
        title: 'Table Test',
        registry: registry,
        repositoryStore: store,
      );
    }
    await real(
      tester,
      () => tester.pumpWidget(JsonRepositoryScope(store: store, child: app)),
    );
  }

  test('SuperTableConfig serializes and deserializes through catalog', () {
    final config = SuperTableConfig(
      binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
      columns: const [
        SuperTableColumnConfig(id: 'col_0', title: 'Nom', width: 180),
        SuperTableColumnConfig(id: 'col_1', title: 'Ville', width: 160),
      ],
      colFreezeLeftCount: 1,
      showHeaderRow: true,
      showBottomRow: true,
      headerRowHeight: 44,
      rowHeight: 38,
      bottomRowHeight: 36,
      allowAdd: true,
      allowRemove: true,
      emptyText: 'Vide',
      placements: const {
        'cell:col_0': ['c0'],
        'cell:col_1': ['c1'],
      },
      slotTypes: const {'c0': 'registry:Value', 'c1': 'registry:Value'},
    );

    final encoded = config.toTypedJson();
    final decoded = ComponentConfig.fromJson(encoded);
    expect(decoded, equals(config));
    expect(config.toCompactJson()['colFreezeLeftCount'], 1);
  });

  testWidgets(
    'SuperTable renders frozen columns, headers, bottom row, IterableContent, and bound cells',
    (tester) async {
      final registry = Registry()..bootstrap();
      await mount(
        tester,
        SuperTable(
          id: 'clients-table',
          config: SuperTableConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
            columns: const [
              SuperTableColumnConfig(id: 'col_0', title: 'Nom', width: 180),
              SuperTableColumnConfig(id: 'col_1', title: 'Ville', width: 180),
            ],
            colFreezeLeftCount: 1,
            showHeaderRow: true,
            showBottomRow: true,
            placements: const {
              'cell:col_0': ['cell:col_0'],
              'cell:col_1': ['cell:col_1'],
              'bottom:col_0': ['bottom:col_0'],
            },
          ),
          cells: const {
            'col_0': SuperValue(
              id: 'val-nom',
              config: SuperValueConfig(
                mode: SuperValueMode.display,
                binding: JsonTextBinding(path: 'nom'),
              ),
            ),
            'col_1': SuperValue(
              id: 'val-ville',
              config: SuperValueConfig(
                mode: SuperValueMode.display,
                binding: JsonTextBinding(path: 'clients[?].ville'),
              ),
            ),
          },
          bottoms: const {'col_0': Text('Total: 2 clients')},
        ),
        registry: registry,
      );

      expect(find.text('Nom'), findsOneWidget);
      expect(find.text('Ville'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Paris'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Lyon'), findsOneWidget);
      expect(find.text('Total: 2 clients'), findsOneWidget);
      expect(find.byType(IterableContent), findsWidgets);
      expect(find.byType(CwTableRow), findsWidgets);
    },
  );

  testWidgets(
    'Selecting a row in SuperTable updates external master/detail SuperValue',
    (tester) async {
      int? selectedRowIndex;
      await mount(
        tester,
        Column(
          children: [
            Expanded(
              child: SuperTable(
                id: 'clients-table',
                onRowSelected: (idx) => selectedRowIndex = idx,
                config: SuperTableConfig(
                  binding: JsonTextBinding(
                    repositoryId: repository,
                    path: 'clients',
                  ),
                  columns: const [
                    SuperTableColumnConfig(
                      id: 'col_0',
                      title: 'Nom',
                      width: 200,
                    ),
                    SuperTableColumnConfig(
                      id: 'col_1',
                      title: 'Ville',
                      width: 200,
                    ),
                  ],
                  placements: const {
                    'cell:col_0': ['cell:col_0'],
                    'cell:col_1': ['cell:col_1'],
                  },
                ),
                cells: const {
                  'col_0': SuperValue(
                    id: 'val-nom',
                    config: SuperValueConfig(
                      mode: SuperValueMode.display,
                      binding: JsonTextBinding(path: 'nom'),
                    ),
                  ),
                  'col_1': SuperValue(
                    id: 'val-ville',
                    config: SuperValueConfig(
                      mode: SuperValueMode.display,
                      binding: JsonTextBinding(path: 'ville'),
                    ),
                  ),
                },
              ),
            ),
            SuperValue(
              id: 'selected-detail',
              config: SuperValueConfig(
                mode: SuperValueMode.display,
                binding: JsonTextBinding(
                  repositoryId: repository,
                  path: 'clients[?].ville',
                ),
              ),
            ),
          ],
        ),
      );

      await real(tester, () => tester.tap(find.text('Bob')));
      expect(selectedRowIndex, 1);
      expect(find.text('Lyon'), findsNWidgets(2));
    },
  );

  testWidgets(
    'Editing a SuperValue inside a SuperTable row writes back to repository JSON',
    (tester) async {
      await mount(
        tester,
        SuperTable(
          id: 'clients-table',
          config: SuperTableConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
            columns: const [
              SuperTableColumnConfig(id: 'col_0', title: 'Nom', width: 200),
              SuperTableColumnConfig(id: 'col_1', title: 'Ville', width: 200),
            ],
            placements: const {
              'cell:col_0': ['cell:col_0'],
              'cell:col_1': ['cell:col_1'],
            },
          ),
          cells: const {
            'col_0': SuperValue(
              id: 'val-nom',
              config: SuperValueConfig(
                mode: SuperValueMode.display,
                binding: JsonTextBinding(path: 'nom'),
              ),
            ),
            'col_1': SuperValue(
              id: 'val-ville-input',
              config: SuperValueConfig(
                mode: SuperValueMode.input,
                binding: JsonTextBinding(path: 'ville'),
              ),
            ),
          },
        ),
      );

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));
      await real(tester, () async {
        await tester.enterText(textFields.at(1), 'Marseille');
        await store.flushBindings();
      }, save: true);

      final saved = jsonDecode(
        (await tester.runAsync(() => store.read('CRM')))!,
      ) as Map<String, dynamic>;
      final clients = saved['clients'] as List<dynamic>;
      expect((clients[1] as Map<String, dynamic>)['ville'], 'Marseille');
    },
  );

  test('EditorPageGraph duplicates SuperTable and its column slots', () {
    final registry = Registry()..bootstrap();
    final source = Appearance(
      components: {
        'page-1': NativeComponentConfig(
          placements: const {
            'body': ['table-1'],
          },
          slotTypes: const {'table-1': 'registry:Table'},
        ),
        'table-1': SuperTableConfig(
          binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
          columns: const [
            SuperTableColumnConfig(id: 'col_0', title: 'Nom', width: 180),
          ],
          placements: const {
            'cell:col_0': ['c-val'],
          },
          slotTypes: const {'c-val': 'registry:Value'},
        ),
        'c-val': const SuperValueConfig(binding: JsonTextBinding(path: 'nom')),
      },
    );

    final duplicated = EditorPageGraph.duplicate(
      appearance: source,
      registry: registry,
      sourcePageId: 'page-1',
      targetPageId: 'page-2',
    );

    final copiedPage = duplicated.nativeComponent('page-2');
    final copiedTableId = copiedPage.slotsOf('body').single;
    expect(copiedTableId, isNot('table-1'));
    final copiedTable = duplicated.tableComponent(copiedTableId);
    expect(copiedTable.binding, source.tableComponent('table-1').binding);
    final copiedCellSlot = copiedTable.slotsOf('cell:col_0').single;
    expect(copiedCellSlot, isNot('c-val'));
    expect(duplicated.valueComponent(copiedCellSlot).binding?.path, 'nom');
  });

  testWidgets('SuperTable supports adding a row to repository', (tester) async {
    await mount(
      tester,
      SuperTable(
        id: 'clients-table',
        config: SuperTableConfig(
          binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
          allowAdd: true,
          columns: const [
            SuperTableColumnConfig(id: 'col_0', title: 'Nom', width: 200),
          ],
          placements: const {
            'cell:col_0': ['cell:col_0'],
          },
        ),
        cells: const {
          'col_0': SuperValue(
            id: 'val-nom',
            config: SuperValueConfig(
              mode: SuperValueMode.display,
              binding: JsonTextBinding(path: 'nom'),
            ),
          ),
        },
      ),
    );

    final addButton = find.byKey(
      const ValueKey('super-table-add-clients-table'),
    );
    expect(addButton, findsOneWidget);
    await real(tester, () => tester.tap(addButton), save: true);

    final items = await tester.runAsync(
      () => store.readArray(repository, 'clients'),
    );
    expect(items?.length, 3);
  });
}
