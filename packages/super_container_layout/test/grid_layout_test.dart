import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/editor_zoom.dart';

void main() {
  const zones = SuperLayoutConfig(
    north: false,
    south: false,
    west: false,
    east: false,
    placements: {
      SuperLayoutZone.center: ['a', 'b'],
      SuperLayoutZone.north: ['hidden'],
    },
    slotTypes: {'hidden': 'HiddenType'},
    slotLabels: {'a': 'Custom A'},
    slotPreferredSizes: {'a': Size(200, 100)},
  );

  void expectNoOverlap(GridLayoutConfig grid) {
    for (final a in grid.items.entries) {
      for (final b in grid.items.entries) {
        if (a.key != b.key) {
          expect(a.value.bounds.overlaps(b.value.bounds), isFalse);
        }
      }
    }
  }

  test(
    'mode conversion includes hidden zones, restores both layouts and JSON',
    () {
      final config = zones.withPositioning(SuperLayoutPositioning.grid);
      expect(config.grid!.items.keys.toSet(), {'a', 'b', 'hidden'});
      expect(config.placements, zones.placements);
      expectNoOverlap(config.grid!);
      final moved = config.copyWith(
        grid: config.grid!.withItem(
          'a',
          const GridSlotPosition(x: 8, y: 3, width: 4, height: 2),
        ),
      );
      final returned = moved.withPositioning(SuperLayoutPositioning.zones);
      expect(returned.placements, zones.placements);
      expect(returned.slotPreferredSizes, zones.slotPreferredSizes);
      expect(
        returned.withPositioning(SuperLayoutPositioning.grid).grid,
        moved.grid,
      );
      final restored = SuperLayoutConfig.fromJson(moved.toJson());
      expect(restored, moved);
      expect(restored.hashCode, moved.hashCode);
      expect(
        SuperLayoutConfig.fromJson({'placements': {}}).positioning,
        SuperLayoutPositioning.zones,
      );
      final snapshot = Appearance(layouts: {'grid': moved});
      expect(
        () => snapshot.layouts['grid']!.grid!.items.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'collisions cascade, compact vertically and stay within changed columns',
    () {
      const grid = GridLayoutConfig(
        compact: false,
        items: {
          'a': GridSlotPosition(x: 0, y: 0),
          'b': GridSlotPosition(x: 0, y: 3),
          'c': GridSlotPosition(x: 0, y: 6),
        },
      );
      final moved = grid.withItem('a', const GridSlotPosition(y: 3, height: 4));
      expect(moved.items['a']!.y, 3);
      expect(moved.items['b']!.y, 7);
      expect(moved.items['c']!.y, 10);
      expectNoOverlap(moved);
      final compact = moved.copyWith(compact: true).arrange();
      expect(compact.items['a']!.y, 0);
      expectNoOverlap(compact);
      final narrow = moved.withColumns(2);
      expect(narrow.items.values.every((p) => p.x + p.width <= 2), isTrue);
      expectNoOverlap(narrow);
    },
  );

  test('adding and removing keeps both modes synchronized', () {
    var config = zones.withPositioning(SuperLayoutPositioning.grid);
    config = config.withSlotMoved('new', SuperLayoutZone.center, type: 'Type');
    expect(config.grid!.items.containsKey('new'), isTrue);
    expect(config.placementsOf(SuperLayoutZone.center), contains('new'));
    config = config
        .withPositioning(SuperLayoutPositioning.zones)
        .withSlotMoved('other', SuperLayoutZone.west);
    expect(config.grid!.items.containsKey('other'), isTrue);
    config = config.withoutSlot('a');
    expect(config.grid!.items.containsKey('a'), isFalse);
    expect(config.placedSlotIds, isNot(contains('a')));
    expect(config.slotLabels.containsKey('a'), isFalse);
    expectNoOverlap(config.grid!);
  });

  test(
    'invalid persisted grids reject unsupported modes, bounds and overlaps',
    () {
      for (final json in [
        {'positioning': 'unknown'},
        {'grid': const GridLayoutConfig(columns: 0).toJson()},
        {'grid': const GridLayoutConfig(rowHeight: -1).toJson()},
        {
          'grid': const GridLayoutConfig(
            items: {'a': GridSlotPosition(width: 13)},
          ).toJson(),
        },
        {
          'grid': const GridLayoutConfig(
            items: {'a': GridSlotPosition(), 'b': GridSlotPosition()},
          ).toJson(),
        },
      ]) {
        expect(() => SuperLayoutConfig.fromJson(json), throwsFormatException);
      }
    },
  );

  test('repeated moves keep every item bounded and collision-free', () {
    final random = math.Random(42);
    var grid = const GridLayoutConfig().synchronize(
      List.generate(20, (index) => 'slot-$index'),
    );
    for (var move = 0; move < 100; move++) {
      final width = 1 + random.nextInt(6);
      final id = 'slot-${random.nextInt(20)}';
      final p = GridSlotPosition(
        x: random.nextInt(13 - width),
        y: random.nextInt(20),
        width: width,
        height: 1 + random.nextInt(6),
      );
      grid = grid.withItem(id, p, compact: false);
      expect(grid.items[id], p);
      expectNoOverlap(grid);
      expect(grid.items.length, 20);
      grid = grid.arrange();
      expectNoOverlap(grid);
      expect(GridLayoutConfig.fromJson(grid.toJson()), grid);
    }
  });

  Future<
    (ValueNotifier<bool>, ValueNotifier<Appearance>, EditorHistoryController)
  >
  pumpGrid(WidgetTester tester, {bool zoom = false}) async {
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier(
      Appearance(
        layouts: {
          'grid': zones
              .copyWith(slotTypes: {})
              .withPositioning(SuperLayoutPositioning.grid),
        },
      ),
    );
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: mode,
    );
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    addTearDown(history.dispose);
    Widget page = ValueListenableBuilder<Appearance>(
      valueListenable: appearance,
      builder: (context, value, _) => SuperLayout(
        label: 'Grid layout',
        config: value.layouts['grid']!,
        onChanged: (config) =>
            appearance.value = appearance.value.withLayout('grid', config),
        slots: [
          for (final id in ['a', 'b', 'hidden', 'available'])
            BuilderSlot(
              id: id,
              label: id,
              builder: (_) => ColoredBox(
                key: ValueKey('grid-content-$id'),
                color: Colors.blue,
                child: TextField(key: ValueKey('input-$id')),
              ),
            ),
        ],
      ),
    );
    if (zoom) page = EditorZoom(child: page);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: EditorHistoryScope(
            controller: history,
            child: Scaffold(
              body: SizedBox(width: 720, height: 500, child: page),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(690, 450));
    await tester.pumpAndSettle();
    return (mode, appearance, history);
  }

  testWidgets('grid labels share hover colors without changing size', (
    tester,
  ) async {
    await pumpGrid(tester);
    final labels = find.byType(ComponentDragLabel);
    expect(labels, findsNWidgets(3));
    final bounds = [for (var i = 0; i < 3; i++) tester.getRect(labels.at(i))];
    Color? background(int index) => tester
        .widget<Material>(
          find
              .descendant(of: labels.at(index), matching: find.byType(Material))
              .first,
        )
        .color;
    final original = [for (var i = 0; i < 3; i++) background(i)];
    final highlight = Theme.of(tester.element(labels.first))
        .colorScheme
        .tertiary;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(790, 590));
    for (final index in [0, 1]) {
      await mouse.moveTo(bounds[index].center);
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        expect(background(i), highlight);
        expect(tester.getRect(labels.at(i)), bounds[i]);
      }
    }
    await mouse.moveTo(const Offset(790, 590));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      expect(background(i), original[i]);
    }
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'grid renders hidden zones, moves by cells and undoes one gesture',
    (tester) async {
      final (_, appearance, history) = await pumpGrid(tester);
      expect(find.byKey(const ValueKey('grid-content-hidden')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('input-a')), 'kept');
      await tester.tap(find.byKey(const ValueKey('grid-slot-label-a')));
      await tester.pumpAndSettle();
      history.clear();
      final before = appearance.value;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('grid-slot-label-a'))),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('grid-slot-size-a')), findsOneWidget);
      expect(history.canUndo, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      final changed = appearance.value;
      expect(changed.layouts['grid']!.grid!.items['a']!.x, 2);
      expectNoOverlap(changed.layouts['grid']!.grid!);
      expect(find.text('kept'), findsOneWidget);
      history.undo();
      await tester.pumpAndSettle();
      expect(appearance.value, before);
      expect(history.canUndo, isFalse);
      history.redo();
      await tester.pumpAndSettle();
      expect(appearance.value, changed);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'grid resize snaps, keeps other dimension and preserves child state',
    (tester) async {
      final (mode, appearance, history) = await pumpGrid(tester);
      await tester.enterText(find.byKey(const ValueKey('input-a')), 'state');
      await tester.tap(find.byKey(const ValueKey('grid-slot-label-a')));
      await tester.pumpAndSettle();
      history.clear();
      final before = appearance.value;
      await tester.drag(
        find.byKey(const ValueKey('slot-resize-a-e')),
        const Offset(120, 45),
      );
      await tester.pumpAndSettle();
      final grid = appearance.value.layouts['grid']!.grid!;
      expect(grid.items['a']!.width, 6);
      expect(grid.items['a']!.height, 3);
      expectNoOverlap(grid);
      expect(find.text('state'), findsOneWidget);
      history.undo();
      await tester.pumpAndSettle();
      expect(appearance.value, before);
      mode.value = false;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slot-resize-a-e')), findsNothing);
      expect(find.byKey(const ValueKey('grid-slot-label-a')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'grid exposes shared size constraints alongside cell position',
    (tester) async {
      final (_, appearance, history) = await pumpGrid(tester);
      final state = tester.state<SuperLayoutState>(find.byType(SuperLayout));
      final action = ContainerMenuAction.of(
        tester.element(find.byKey(const ValueKey('grid-content-a'))),
      ).first;
      action.onEdit();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('grid-slot-width')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('grid-slot-size-constraints')));
      await tester.pumpAndSettle();
      final position = state.config.effectiveGrid.items['a'];
      final before = state.config;
      for (final dimension in [
        'min-width', 'min-height', 'preferred-width',
        'preferred-height', 'max-width', 'max-height',
      ]) {
        expect(find.byKey(ValueKey('slot-$dimension')), findsOneWidget);
      }
      await tester.enterText(
        find.byKey(const ValueKey('slot-min-width')), '80',
      );
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-width')), '120',
      );
      await tester.enterText(
        find.byKey(const ValueKey('slot-max-width')), '160',
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('grid-content-a'))).width,
          closeTo(120, 1));
      expect(state.config.effectiveGrid.items['a'], position);
      expect(find.byKey(const ValueKey('slot-preview-zone')), findsOneWidget);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      final saved = state.config.slotSizeConstraints['a']!;
      expect(saved.minWidth, const SlotDimension(80, SlotSizeUnit.pixels));
      expect(saved.maxWidth, const SlotDimension(160, SlotSizeUnit.pixels));
      expect(SuperLayoutConfig.fromJson(state.config.toJson()), state.config);
      history.undo();
      await tester.pumpAndSettle();
      expect(appearance.value.layouts['grid'], before);
      history.redo();
      await tester.pumpAndSettle();
      expect(state.config.slotSizeConstraints['a'], saved);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'grid size editor validates cells, renames and cancels atomically',
    (tester) async {
      final (_, appearance, history) = await pumpGrid(tester);
      final before = appearance.value;
      final state = tester.state<SuperLayoutState>(find.byType(SuperLayout));
      final action = ContainerMenuAction.of(
        tester.element(find.byKey(const ValueKey('grid-content-a'))),
      ).first;
      action.onEdit();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('grid-slot-width')),
        '13',
      );
      await tester.pump();
      expect(find.text('La grille contient 12 colonnes.'), findsWidgets);
      expect(appearance.value.layouts, before.layouts);
      await tester.enterText(
        find.byKey(const ValueKey('grid-slot-width')),
        '6',
      );
      await tester.pumpAndSettle();
      expect(state.config.grid!.items['a']!.width, 6);
      await tester.tap(find.byKey(const ValueKey('editor-label-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('editor-label-input')),
        'Renamed',
      );
      await tester.tap(find.byKey(const ValueKey('editor-label-save')));
      await tester.pumpAndSettle();
      expect(state.config.slotLabels['a'], 'Renamed');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(appearance.value.layouts, before.layouts);
      expect(history.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'layout editor switches type live, cancels and applies with undo',
    (tester) async {
      final (_, appearance, history) = await pumpGrid(tester);
      final before = appearance.value;
      final container = find.byWidgetPredicate(
        (widget) => widget is SuperContainer && widget.label == 'Grid layout',
      );
      Future<void> open() async {
        tester.state<SuperContainerState>(container).openEditor();
        await tester.pumpAndSettle();
      }

      await open();
      await tester.tap(find.text('Zones'));
      await tester.pumpAndSettle();
      expect(
        appearance.value.layouts['grid']!.positioning,
        SuperLayoutPositioning.zones,
      );
      expect(find.byKey(const ValueKey('grid-setting-columns')), findsNothing);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(appearance.value.layouts, before.layouts);
      expect(history.canUndo, isFalse);
      await open();
      await tester.tap(find.text('Zones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      history.undo();
      await tester.pumpAndSettle();
      expect(appearance.value.layouts, before.layouts);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('grid selection zoom keeps handles at screen size', (
    tester,
  ) async {
    await pumpGrid(tester, zoom: true);
    await tester.tap(find.byKey(const ValueKey('grid-slot-label-a')));
    await tester.pumpAndSettle();
    final handle = find.byKey(const ValueKey('slot-resize-a-e'));
    final box = tester.renderObject<RenderBox>(handle);
    final screen = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    expect(screen.size, const Size(32, 32));
    expect(LayoutSelection.path.value.last, 'Custom A');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'zoomed grid resize freezes framing and uses logical cell steps',
    (tester) async {
      final (_, appearance, _) = await pumpGrid(tester, zoom: true);
      await tester.tap(find.byKey(const ValueKey('grid-slot-label-a')));
      await tester.pumpAndSettle();
      final content = find.byKey(const ValueKey('grid-content-a'));
      final box = tester.renderObject<RenderBox>(content);
      final screen = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
      final scale = screen.width / box.size.width;
      final transform = find.byKey(const ValueKey('editor-zoom-transform'));
      final beforeTransform = tester
          .widget<Transform>(transform)
          .transform
          .clone();
      final step = (720 + 8) / 12 * scale;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('slot-resize-a-e'))),
      );
      await gesture.moveBy(Offset(step, 0));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.widget<Transform>(transform).transform, beforeTransform);
      await gesture.moveBy(Offset(step, 0));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.widget<Transform>(transform).transform, beforeTransform);
      expect(appearance.value.layouts['grid']!.grid!.items['a']!.width, 6);
      await gesture.up();
      await tester.pumpAndSettle();
      expectNoOverlap(appearance.value.layouts['grid']!.grid!);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'grid menu uses cells, hides zone axes and adds/removes in both modes',
    (tester) async {
      final (_, appearance, history) = await pumpGrid(tester);
      await tester.tap(
        find.byKey(const ValueKey('grid-slot-label-a')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('style-menu-axis-Grid layout')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('style-menu-size-Position et taille : Custom A'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const ValueKey('style-menu-remove-Position et taille : Custom A'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        appearance.value.layouts['grid']!.grid!.items.containsKey('a'),
        isFalse,
      );
      expect(
        appearance.value.layouts['grid']!.placedSlotIds,
        isNot(contains('a')),
      );
      history.undo();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('grid-content-a')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('grid-add-slot')));
      await tester.pumpAndSettle();
      expect(find.text('Ajouter un slot dans la grille'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('super-layout-add-slot-available')),
      );
      await tester.pumpAndSettle();
      final config = appearance.value.layouts['grid']!;
      expect(config.grid!.items.containsKey('available'), isTrue);
      expect(
        config.placementsOf(SuperLayoutZone.center),
        contains('available'),
      );
      expectNoOverlap(config.grid!);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scrolling grid clips its unscaled overlays to the viewport', (
    tester,
  ) async {
    final (_, appearance, _) = await pumpGrid(tester, zoom: true);
    final config = appearance.value.layouts['grid']!;
    appearance.value = appearance.value.withLayout(
      'grid',
      config.copyWith(
        grid: config.effectiveGrid
            .withColumns(4)
            .withItem(
              'a',
              const GridSlotPosition(width: 4, height: 12),
              compact: false,
            ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('grid-slot-label-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('grid-slot-label-b')), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('super-layout-grid-scroll')),
      const Offset(0, -650),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('grid-slot-label-a')).hitTestable(),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('grid-slot-label-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('grid-add-slot')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'grid size apply creates one history entry and preserves zone sizes',
    (tester) async {
      final (_, appearance, history) = await pumpGrid(tester);
      final before = appearance.value;
      ContainerMenuAction.of(
        tester.element(find.byKey(const ValueKey('grid-content-a'))),
      ).first.onEdit();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('grid-slot-width')),
        '5',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('grid-slot-height')),
        '4',
      );
      await tester.pump();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(appearance.value.layouts['grid']!.grid!.items['a']!.width, 5);
      expect(
        appearance.value.layouts['grid']!.slotPreferredSizes,
        before.layouts['grid']!.slotPreferredSizes,
      );
      history.undo();
      await tester.pumpAndSettle();
      expect(appearance.value.layouts, before.layouts);
      expect(history.canUndo, isFalse);
      history.redo();
      await tester.pumpAndSettle();
      expect(appearance.value.layouts['grid']!.grid!.items['a']!.height, 4);
      expect(tester.takeException(), isNull);
    },
  );
}
