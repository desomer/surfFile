import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
      animateSelectionAndHover: false,
      emptyText: 'Vide',
      placements: const {
        'cell:col_0': ['c0'],
        'cell:col_1': ['c1'],
      },
      slotTypes: const {'c0': 'registry:Value', 'c1': 'registry:Value'},
      zoneStyles: const {
        'header:col_0': ContainerStyle(color: Colors.indigo, radius: 6),
        'bottom:col_1': ContainerStyle(color: Colors.teal, borderWidth: 1),
      },
    );

    final encoded = config.toTypedJson();
    final decoded = ComponentConfig.fromJson(encoded);
    expect(decoded, equals(config));
    expect(config.toCompactJson()['colFreezeLeftCount'], 1);
    expect(config.toCompactJson()['animateSelectionAndHover'], isFalse);
    expect(
      (config.toCompactJson()['zoneStyles'] as Map)['header:col_0'],
      isNotNull,
    );
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

  testWidgets(
    'SuperTable animates selection and hover backgrounds vertically with IterableContent states and frozen columns',
    (tester) async {
      final registry = Registry()..bootstrap();
      const rowStyle = ContainerStyle(radius: 8);
      final styledStates = SurfaceStyleStates(
        selected: SelectedSurfaceStyle(
          style: const ContainerStyle(color: Colors.teal, radius: 12),
          properties: const {
            SurfaceStyleProperty.background,
            SurfaceStyleProperty.corners,
          },
        ),
        hover: SelectedSurfaceStyle(
          style: const ContainerStyle(color: Colors.amber, radius: 10),
          properties: const {
            SurfaceStyleProperty.background,
            SurfaceStyleProperty.corners,
          },
        ),
      );

      await mount(
        tester,
        SuperTable(
          id: 'clients-table',
          templateStyle: rowStyle.copyWith(states: styledStates),
          config: SuperTableConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
            colFreezeLeftCount: 1,
            rowHeight: 40,
            columns: const [
              SuperTableColumnConfig(id: 'col_0', title: 'Nom', width: 180),
              SuperTableColumnConfig(id: 'col_1', title: 'Ville', width: 180),
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
        registry: registry,
      );

      final selIndicatorRight = find.byKey(
        const ValueKey('super-table-selection-indicator-clients-table'),
      );
      final selIndicatorLeft = find.byKey(
        const ValueKey('super-table-selection-indicator-left-clients-table'),
      );
      final hoverIndicatorRight = find.byKey(
        const ValueKey('super-table-hover-indicator-clients-table'),
      );
      final selOpacityRight = find.byKey(
        const ValueKey('table-view-selection-opacity'),
      );
      final hoverOpacityRight = find.byKey(
        const ValueKey('table-view-hover-opacity'),
      );

      expect(tester.widget<AnimatedOpacity>(selOpacityRight).opacity, 0.0);
      expect(tester.widget<AnimatedOpacity>(hoverOpacityRight).opacity, 0.0);

      // 1. Tap first row ("Alice", index 0)
      await tester.tap(find.text('Alice'));
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(selOpacityRight).opacity, 1.0);
      expect(
        tester
            .widget<SuperContainer>(selIndicatorRight)
            .style
            .color
            ?.toARGB32(),
        Colors.teal.toARGB32(),
      );
      expect(
        tester.widget<SuperContainer>(selIndicatorLeft).style.color?.toARGB32(),
        Colors.teal.toARGB32(),
      );
      final initialSelTop = tester.getTopLeft(selIndicatorRight).dy;
      expect(
        tester.getTopLeft(selIndicatorLeft).dy,
        closeTo(initialSelTop, 0.5),
      );

      // 2. Tap second row ("Bob", index 1 -> top offset +40)
      await tester.tap(find.text('Bob'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final midSelTop = tester.getTopLeft(selIndicatorRight).dy;
      expect(midSelTop, greaterThan(initialSelTop + 5));
      expect(midSelTop, lessThan(initialSelTop + 40 - 3));
      expect(tester.getTopLeft(selIndicatorLeft).dy, closeTo(midSelTop, 0.5));

      await tester.pumpAndSettle();
      final finalSelTop = tester.getTopLeft(selIndicatorRight).dy;
      expect(finalSelTop - initialSelTop, closeTo(40.0, 0.5));
      expect(tester.getTopLeft(selIndicatorLeft).dy, closeTo(finalSelTop, 0.5));

      // 3. Hover first row ("Alice"), then move to second row ("Bob")
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      await gesture.moveTo(tester.getCenter(find.text('Alice')));
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(hoverOpacityRight).opacity, 1.0);
      expect(
        tester
            .widget<SuperContainer>(hoverIndicatorRight)
            .style
            .color
            ?.toARGB32(),
        Colors.amber.toARGB32(),
      );
      final initialHoverTop = tester.getTopLeft(hoverIndicatorRight).dy;
      expect(initialHoverTop, closeTo(initialSelTop, 0.5));

      await gesture.moveTo(tester.getCenter(find.text('Bob')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final midHoverTop = tester.getTopLeft(hoverIndicatorRight).dy;
      expect(midHoverTop, greaterThan(initialHoverTop + 5));
      expect(midHoverTop, lessThan(initialHoverTop + 40.0 - 3));

      await tester.pumpAndSettle();
      final finalHoverTop = tester.getTopLeft(hoverIndicatorRight).dy;
      expect(finalHoverTop - initialHoverTop, closeTo(40.0, 0.5));

      // 4. Move pointer outside table: hover fades out in place
      await gesture.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(hoverOpacityRight).opacity, 0.0);
      expect(
        tester.getTopLeft(hoverIndicatorRight).dy,
        closeTo(finalHoverTop, 0.5),
      );
    },
  );

  testWidgets(
    'SuperTable header and bottom cells have no default background/border and support per-cell ContainerStyle',
    (tester) async {
      final registry = Registry()..bootstrap();
      SuperTableConfig? lastConfig;

      await mount(
        tester,
        SuperTable(
          id: 'clients-table',
          onConfigChanged: (cfg) => lastConfig = cfg,
          config: SuperTableConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
            colFreezeLeftCount: 1,
            showHeaderRow: true,
            showBottomRow: true,
            columns: const [
              SuperTableColumnConfig(id: 'col_0', title: 'Nom', width: 180),
              SuperTableColumnConfig(id: 'col_1', title: 'Ville', width: 180),
            ],
            zoneStyles: const {
              'header:col_1': ContainerStyle(color: Colors.deepPurple, radius: 6),
              'bottom:col_0': ContainerStyle(color: Colors.orange, borderWidth: 2),
            },
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
                binding: JsonTextBinding(path: 'ville'),
              ),
            ),
          },
          bottoms: const {'col_0': Text('Total: 2 clients')},
        ),
        registry: registry,
      );

      final headerCol0 = tester.widget<EditableSurface>(
        find.byKey(const ValueKey('super-table-header-cell-clients-table-col_0')),
      );
      expect(headerCol0.style, const ContainerStyle());
      expect(headerCol0.fallbackColor, Colors.transparent);
      expect(headerCol0.borderColor, Colors.transparent);

      final bottomCol1 = tester.widget<EditableSurface>(
        find.byKey(const ValueKey('super-table-bottom-cell-clients-table-col_1')),
      );
      expect(bottomCol1.style, const ContainerStyle());
      expect(bottomCol1.fallbackColor, Colors.transparent);
      expect(bottomCol1.borderColor, Colors.transparent);

      final headerCol1 = tester.widget<EditableSurface>(
        find.byKey(const ValueKey('super-table-header-cell-clients-table-col_1')),
      );
      expect(
        headerCol1.style,
        const ContainerStyle(color: Colors.deepPurple, radius: 6),
      );

      final bottomCol0 = tester.widget<EditableSurface>(
        find.byKey(const ValueKey('super-table-bottom-cell-clients-table-col_0')),
      );
      expect(
        bottomCol0.style,
        const ContainerStyle(color: Colors.orange, borderWidth: 2),
      );

      // Update header cell style via EditableSurface callback
      headerCol0.onStyleChanged?.call(
        const ContainerStyle(color: Colors.cyan, borderWidth: 1),
      );
      await tester.pump();

      expect(
        lastConfig?.zoneStyleOf('header:col_0'),
        const ContainerStyle(color: Colors.cyan, borderWidth: 1),
      );
      final updatedHeaderCol0 = tester.widget<EditableSurface>(
        find.byKey(const ValueKey('super-table-header-cell-clients-table-col_0')),
      );
      expect(
        updatedHeaderCol0.style,
        const ContainerStyle(color: Colors.cyan, borderWidth: 1),
      );
    },
  );

  test('SuperTableColumnConfig serializes and validates fillPercent', () {
    const fixedCol = SuperTableColumnConfig(
      id: 'col_0',
      title: 'Fixe',
      width: 140,
    );
    expect(fixedCol.isFill, isFalse);
    expect(fixedCol.toCompactJson().containsKey('fillPercent'), isFalse);

    const fillCol = SuperTableColumnConfig(
      id: 'col_1',
      title: 'Reste',
      width: 120,
      fillPercent: 75,
    );
    expect(fillCol.isFill, isTrue);
    expect(fillCol.toCompactJson()['fillPercent'], 75);
    expect(
      SuperTableColumnConfig.fromJson(fillCol.toCompactJson()),
      equals(fillCol),
    );

    expect(
      () => const SuperTableColumnConfig(
        id: 'col_bad',
        fillPercent: -5,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const SuperTableColumnConfig(
        id: 'col_bad',
        fillPercent: 120,
      ).validate(),
      throwsFormatException,
    );
  });

  testWidgets(
    'SuperTable columns with fillPercent fill remaining horizontal space, respect min width, and support drag/double-click reset',
    (tester) async {
      final registry = Registry()..bootstrap();
      final controller = ValueNotifier<SuperTableConfig>(
        SuperTableConfig(
          binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
          colFreezeLeftCount: 1,
          showHeaderRow: true,
          columns: const [
            SuperTableColumnConfig(id: 'col_0', title: 'Nom', width: 200),
            SuperTableColumnConfig(
              id: 'col_1',
              title: 'Ville',
              width: 120,
              fillPercent: 30,
            ),
            SuperTableColumnConfig(
              id: 'col_2',
              title: 'Rôle',
              width: 120,
              fillPercent: 70,
            ),
          ],
          placements: const {
            'cell:col_0': ['cell:col_0'],
            'cell:col_1': ['cell:col_1'],
            'cell:col_2': ['cell:col_2'],
          },
        ),
      );
      addTearDown(controller.dispose);

      await mount(
        tester,
        ValueListenableBuilder<SuperTableConfig>(
          valueListenable: controller,
          builder: (_, cfg, _) => SuperTable(
            id: 'fill-table',
            config: cfg,
            cells: const {
              'col_0': Text('Cell 0'),
              'col_1': Text('Cell 1'),
              'col_2': Text('Cell 2'),
            },
          ),
        ),
        registry: registry,
      );

      // Total available width is 800 px.
      // col_0 is fixed at 200 px -> remaining space is 600 px.
      // col_1 (30%) = 180 px, col_2 (70%) = 420 px.
      final header0 = find.byKey(
        const ValueKey('super-table-header-cell-fill-table-col_0'),
      );
      final header1 = find.byKey(
        const ValueKey('super-table-header-cell-fill-table-col_1'),
      );
      final header2 = find.byKey(
        const ValueKey('super-table-header-cell-fill-table-col_2'),
      );

      expect(tester.getSize(header0).width, closeTo(200.0, 0.5));
      expect(tester.getSize(header1).width, closeTo(180.0, 0.5));
      expect(tester.getSize(header2).width, closeTo(420.0, 0.5));

      // Drag resize handle on col_1 -> col_1 becomes fixed at 230 px (70 px drag - 20 px touch slop = +50 px),
      // remaining space is 800 - 200 - 230 = 370 px, so col_2 (70%) becomes 370 * 0.70 = 259 px.
      final resize1 = find.byKey(const ValueKey('cw-table-header-resize-1'));
      await tester.drag(resize1, const Offset(70, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(header1).width, closeTo(230.0, 0.5));
      expect(tester.getSize(header2).width, closeTo(259.0, 0.5));

      // Double-tap resize handle on col_1 to reset manual override -> returns to 180 px / 420 px.
      await tester.tap(resize1);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(resize1);
      await tester.pumpAndSettle();
      expect(tester.getSize(header1).width, closeTo(180.0, 0.5));
      expect(tester.getSize(header2).width, closeTo(420.0, 0.5));

      // Verify minWidth is respected when remaining space is smaller than minWidth.
      registry.tableController('fill-table').value = SuperTableConfig(
        binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
        showHeaderRow: true,
        columns: const [
          SuperTableColumnConfig(id: 'col_0', title: 'Nom', width: 650),
          SuperTableColumnConfig(
            id: 'col_1',
            title: 'Ville',
            width: 240,
            fillPercent: 100,
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(header0).width, closeTo(650.0, 0.5));
      expect(tester.getSize(header1).width, closeTo(240.0, 0.5));
    },
  );

  testWidgets(
    'SuperTableEditor edits column fillPercent and updates width label to Largeur min (px)',
    (tester) async {
      SuperTableConfig? result;
      await mount(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showSuperTableEditor(
                context: context,
                config: SuperTableConfig(
                  columns: const [
                    SuperTableColumnConfig(
                      id: 'col_0',
                      title: 'Nom',
                      width: 150,
                    ),
                    SuperTableColumnConfig(
                      id: 'col_1',
                      title: 'Description',
                      width: 120,
                    ),
                  ],
                ),
              );
            },
            child: const Text('Open Editor'),
          ),
        ),
      );

      await tester.tap(find.text('Open Editor'));
      await tester.pumpAndSettle();

      expect(find.text('Largeur (px)'), findsNWidgets(2));
      expect(find.text('Largeur min (px)'), findsNothing);

      final fillCol1 = find.byKey(const ValueKey('super-table-col-fill-col_1'));
      await tester.enterText(fillCol1, '100');
      await tester.pump();

      expect(find.text('Largeur (px)'), findsOneWidget);
      expect(find.text('Largeur min (px)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('super-table-apply')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.columns[0].fillPercent, 0);
      expect(result!.columns[1].fillPercent, 100);
      expect(result!.columns[1].width, 120);
    },
  );

  testWidgets(
    'Card containing a SuperValue inside a SuperTable column cell fills the full row height',
    (tester) async {
      final registry = Registry()..bootstrap();
      registry.nativeComponentController(
        'cell-card',
        fallback: NativeComponentConfig(
          placements: const {
            'child': ['cell-val'],
          },
          slotTypes: const {'cell-val': 'factory:Value'},
        ),
      );
      registry.valueController(
        'cell-val',
        fallback: const SuperValueConfig(
          mode: SuperValueMode.display,
          binding: JsonTextBinding(path: 'nom'),
        ),
      );
      registry.tableController(
        'card-table',
        fallback: SuperTableConfig(
          binding: JsonTextBinding(repositoryId: repository, path: 'clients'),
          rowHeight: 64,
          columns: const [
            SuperTableColumnConfig(id: 'col_0', title: 'Nom', width: 220),
          ],
          placements: {
            SuperTableConfig.cellZoneFor('col_0'): const ['cell-card'],
          },
          slotTypes: const {'cell-card': 'factory:Card'},
        ),
      );

      await mount(
        tester,
        const SuperTable(id: 'card-table'),
        registry: registry,
      );

      expect(find.text('Alice'), findsOneWidget);
      final cardFinder = find.ancestor(
        of: find.text('Alice'),
        matching: find.byWidgetPredicate(
          (w) => w is EditableSurface && w.id == 'cell-card',
        ),
      );
      expect(cardFinder, findsOneWidget);
      final cardSize = tester.getSize(cardFinder);
      expect(cardSize.width, closeTo(220.0, 0.5));
      expect(cardSize.height, closeTo(64.0, 0.5));
    },
  );
}
