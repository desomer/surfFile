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
      animateSelectionAndHover: false,
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
    expect(config.toCompactJson()['animateSelectionAndHover'], isFalse);
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

  testWidgets(
    'Newly mounted SuperValue hydrates value and propertyBindings synchronously from cache on first frame',
    (tester) async {
      // Because setUp saved 'Catalog' through store.save, the document is
      // already in store's synchronous cache. Mounting a brand new SuperValue
      // with a single pumpWidget (no runAsync, no extra frames) must render the
      // bound text and bound property immediately on frame 1.
      await tester.pumpWidget(
        JsonRepositoryScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(
              body: SuperValue(
                id: 'instant-cached-value',
                config: SuperValueConfig(
                  mode: SuperValueMode.display,
                  binding: JsonTextBinding(
                    repositoryId: repository,
                    path: 'nodes[0].children[1].data',
                  ),
                  propertyBindings: {
                    SuperValueProperty.label: JsonTextBinding(
                      repositoryId: repository,
                      path: 'nodes[0].children[1].key',
                    ),
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Immediately visible on the very first frame without any async delay:
      expect(find.text('Data C1.2'), findsOneWidget);
      expect(find.text('Child 1.2'), findsOneWidget);
    },
  );

  testWidgets(
    'SuperTreeView rows wrap in IterableContent by default and share row ContainerStyle',
    (tester) async {
      final registry = Registry()..bootstrap();
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
        registry: registry,
      );

      expect(find.byType(IterableContent), findsNWidgets(4));
      final context = tester.element(find.byType(SuperTreeView));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      final appearance = AppearanceScope.controllerOf(context)!;
      final history = EditorHistoryScope.controllerOf(context)!;
      history.clear();
      final before = appearance.value;

      tester
          .widget<IterableContent>(find.byType(IterableContent).first)
          .onStyleChanged!(
        const ContainerStyle(color: Colors.orange, radius: 10),
      );
      await tester.pumpAndSettle();

      expect(appearance.value.styles['catalog-tree']!.radius, 10);
      for (final content in tester.widgetList<IterableContent>(
        find.byType(IterableContent),
      )) {
        expect(content.style.radius, 10);
      }

      await real(tester, () async => history.undo());
      expect(appearance.value, same(before));
      for (final content in tester.widgetList<IterableContent>(
        find.byType(IterableContent),
      )) {
        expect(content.style.radius, 0);
      }

      await real(tester, () async => history.redo());
      for (final content in tester.widgetList<IterableContent>(
        find.byType(IterableContent),
      )) {
        expect(content.style.radius, 10);
      }

      // Enabling neon on the row style renders NeonSurface without hard clipping:
      tester
          .widget<IterableContent>(find.byType(IterableContent).first)
          .onStyleChanged!(
        const ContainerStyle(
          color: Colors.orange,
          radius: 10,
          neon: NeonStyle(enabled: true, intensity: 0.8),
        ),
      );
      await tester.pumpAndSettle();

      final rowClipRects = tester.widgetList<ClipRect>(
        find.descendant(
          of: find.byType(SuperTreeView),
          matching: find.byType(ClipRect),
        ),
      );
      for (final clipRect in rowClipRects) {
        expect(clipRect.clipBehavior, Clip.none);
      }
    },
  );

  testWidgets(
    'SuperTreeView animates selection and hover backgrounds vertically with IterableContent states',
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
        SuperTreeView(
          id: 'catalog-tree',
          templateStyle: rowStyle.copyWith(states: styledStates),
          config: SuperTreeViewConfig(
            binding: JsonTextBinding(repositoryId: repository, path: 'nodes'),
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
              binding: JsonTextBinding(path: 'data'),
            ),
          ),
        ),
        registry: registry,
      );

      final selIndicatorFinder = find.byKey(
        const ValueKey('super-tree-selection-indicator-catalog-tree'),
      );
      final hoverIndicatorFinder = find.byKey(
        const ValueKey('super-tree-hover-indicator-catalog-tree'),
      );
      final selOpacityFinder = find.byKey(
        const ValueKey('tree-view-selection-opacity'),
      );
      final hoverOpacityFinder = find.byKey(
        const ValueKey('tree-view-hover-opacity'),
      );

      // Initially neither selection nor hover indicator is visible.
      expect(tester.widget<AnimatedOpacity>(selOpacityFinder).opacity, 0.0);
      expect(tester.widget<AnimatedOpacity>(hoverOpacityFinder).opacity, 0.0);

      // 1. Tap first row ("Parent 1", index 0 -> top offset 0)
      await tester.tap(find.text('Parent 1'));
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(selOpacityFinder).opacity, 1.0);
      expect(
        tester
            .widget<SuperContainer>(selIndicatorFinder)
            .style
            .color
            ?.toARGB32(),
        Colors.teal.toARGB32(),
      );
      expect(
        tester.widget<SuperContainer>(selIndicatorFinder).style.radius,
        12,
      );
      final initialSelTop = tester.getTopLeft(selIndicatorFinder).dy;

      // 2. Tap fourth row ("Parent 2", index 3 -> top offset 3 * 36 = 108)
      await tester.tap(find.text('Parent 2'));
      await tester.pump();
      // Mid-animation (80ms into 200ms slide): indicator is moving vertically
      await tester.pump(const Duration(milliseconds: 80));
      final midSelTop = tester.getTopLeft(selIndicatorFinder).dy;
      expect(midSelTop, greaterThan(initialSelTop + 10));
      expect(midSelTop, lessThan(initialSelTop + 108 - 5));

      await tester.pumpAndSettle();
      final finalSelTop = tester.getTopLeft(selIndicatorFinder).dy;
      expect(finalSelTop - initialSelTop, closeTo(3 * 36.0, 0.5));

      // 3. Hover first row ("Parent 1"), then move to third row ("Child 1.2")
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      await gesture.moveTo(tester.getCenter(find.text('Parent 1')));
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(hoverOpacityFinder).opacity, 1.0);
      expect(
        tester
            .widget<SuperContainer>(hoverIndicatorFinder)
            .style
            .color
            ?.toARGB32(),
        Colors.amber.toARGB32(),
      );
      final initialHoverTop = tester.getTopLeft(hoverIndicatorFinder).dy;
      expect(initialHoverTop, closeTo(initialSelTop, 0.5));

      await gesture.moveTo(tester.getCenter(find.text('Child 1.2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final midHoverTop = tester.getTopLeft(hoverIndicatorFinder).dy;
      expect(midHoverTop, greaterThan(initialHoverTop + 8));
      expect(midHoverTop, lessThan(initialHoverTop + 2 * 36.0 - 4));

      await tester.pumpAndSettle();
      final finalHoverTop = tester.getTopLeft(hoverIndicatorFinder).dy;
      expect(finalHoverTop - initialHoverTop, closeTo(2 * 36.0, 0.5));

      // 4. Move pointer outside tree: hover fades out in place without jumping
      await gesture.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(hoverOpacityFinder).opacity, 0.0);
      expect(
        tester.getTopLeft(hoverIndicatorFinder).dy,
        closeTo(finalHoverTop, 0.5),
      );
    },
  );

  testWidgets(
    'Card containing a SuperValue inside a SuperTreeView zone fills the full row height',
    (tester) async {
      final registry = Registry()..bootstrap();
      registry.nativeComponentController(
        'tree-card',
        fallback: NativeComponentConfig(
          placements: const {
            'child': ['tree-val'],
          },
          slotTypes: const {'tree-val': 'factory:Value'},
        ),
      );
      registry.valueController(
        'tree-val',
        fallback: const SuperValueConfig(
          mode: SuperValueMode.display,
          binding: JsonTextBinding(path: 'key'),
        ),
      );
      registry.treeViewController(
        'card-tree',
        fallback: SuperTreeViewConfig(
          binding: JsonTextBinding(repositoryId: repository, path: 'nodes'),
          rowHeight: 60,
          placements: const {
            SuperTreeViewConfig.headerZone: ['tree-card'],
          },
          slotTypes: const {'tree-card': 'factory:Card'},
        ),
      );

      await mount(
        tester,
        const SuperTreeView(id: 'card-tree'),
        registry: registry,
      );

      expect(find.text('Parent 1'), findsOneWidget);
      final cardFinder = find.ancestor(
        of: find.text('Parent 1'),
        matching: find.byWidgetPredicate(
          (w) => w is EditableSurface && w.id == 'tree-card',
        ),
      );
      expect(cardFinder, findsOneWidget);
      expect(tester.getSize(cardFinder).height, closeTo(60.0, 0.5));
    },
  );
}
