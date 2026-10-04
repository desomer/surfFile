import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/super_layout_config.dart';
import 'package:surf_file/widgets/slot_implementation.dart';
import 'package:surf_file/widgets/super_container.dart';
import 'package:surf_file/widgets/super_layout.dart';

/// Un slot par zone, pour tester le placement sans écrire les ids à la main.
Widget zonedLayout({
  required Map<SuperLayoutZone, Widget> zones,
  SuperLayoutConfig config = const SuperLayoutConfig(),
  ValueChanged<SuperLayoutConfig>? onChanged,
}) => SuperLayout(
  config: config.copyWith(
    placements: {
      for (final zone in zones.keys) zone: [zone.name],
    },
  ),
  onChanged: onChanged,
  slots: [
    for (final MapEntry(:key, :value) in zones.entries)
      BuilderSlot(id: key.name, label: 'slot ', builder: (_) => value),
  ],
);

void main() {
  const size = Size(600, 400);
  const z = SuperLayoutZone.values;

  group('SuperLayoutConfig.resolve', () {
    test('full grid has nine distinct cells', () {
      final rects = const SuperLayoutConfig().resolve(size);
      expect(rects.keys.toSet(), z.toSet());
      expect(
        rects[SuperLayoutZone.center],
        const Rect.fromLTRB(120, 80, 480, 320),
      );
      expect(rects[SuperLayoutZone.nw], const Rect.fromLTRB(0, 0, 120, 80));
      expect(
        rects[SuperLayoutZone.se],
        const Rect.fromLTRB(480, 320, 600, 400),
      );
    });

    test('missing sides drop their cells and corners', () {
      final rects = const SuperLayoutConfig(
        north: false,
        west: false,
      ).resolve(size);
      expect(rects.keys.toSet(), {
        SuperLayoutZone.center,
        SuperLayoutZone.south,
        SuperLayoutZone.east,
        SuperLayoutZone.se,
      });
      expect(
        rects[SuperLayoutZone.center],
        const Rect.fromLTRB(0, 0, 480, 320),
      );
    });

    test('corner merges into the row side', () {
      final rects = const SuperLayoutConfig(sw: CornerMerge.row).resolve(size);
      expect(rects.containsKey(SuperLayoutZone.sw), isFalse);
      expect(
        rects[SuperLayoutZone.south],
        const Rect.fromLTRB(0, 320, 480, 400),
      );
      expect(rects[SuperLayoutZone.west], const Rect.fromLTRB(0, 80, 120, 320));
    });

    test('corner merges into the column side', () {
      final rects = const SuperLayoutConfig(sw: CornerMerge.column)
          .resolve(size);
      expect(rects.containsKey(SuperLayoutZone.sw), isFalse);
      expect(rects[SuperLayoutZone.west], const Rect.fromLTRB(0, 80, 120, 400));
      expect(
        rects[SuperLayoutZone.south],
        const Rect.fromLTRB(120, 320, 480, 400),
      );
    });

    test('all corners merged span full sides without overlap', () {
      final rects = const SuperLayoutConfig(
        nw: CornerMerge.row,
        ne: CornerMerge.row,
        sw: CornerMerge.column,
        se: CornerMerge.column,
      ).resolve(size);
      expect(rects[SuperLayoutZone.north], const Rect.fromLTRB(0, 0, 600, 80));
      expect(rects[SuperLayoutZone.west], const Rect.fromLTRB(0, 80, 120, 400));
      expect(
        rects[SuperLayoutZone.east],
        const Rect.fromLTRB(480, 80, 600, 400),
      );
      expect(
        rects[SuperLayoutZone.south],
        const Rect.fromLTRB(120, 320, 480, 400),
      );
      final list = rects.values.toList();
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          expect(list[i].intersect(list[j]).isEmpty, isTrue);
        }
      }
    });

    test('oversized sides shrink to fit', () {
      final rects = const SuperLayoutConfig(
        westSize: 600,
        eastSize: 600,
      ).resolve(size);
      expect(rects[SuperLayoutZone.west]!.width, 300);
      expect(rects[SuperLayoutZone.center]!.width, 0);
    });
  });

  Future<List<SuperLayoutConfig>> pump(
    WidgetTester tester, {
    SuperLayoutConfig config = const SuperLayoutConfig(),
  }) async {
    final changes = <SuperLayoutConfig>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: zonedLayout(
              config: config,
              onChanged: changes.add,
              zones: const {SuperLayoutZone.center: Text('Contenu')},
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  Future<void> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.tap(find.text('Contenu'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuItem<SuperContainerState>).first);
    await tester.pumpAndSettle();
  }

  testWidgets('renders zones with placeholders for the missing ones', (
    tester,
  ) async {
    await pump(tester, config: const SuperLayoutConfig(east: false));
    expect(find.text('Contenu'), findsOneWidget);
    expect(find.text('Nord'), findsOneWidget);
    expect(find.text('Est'), findsNothing);
    expect(find.text('Sud-Est'), findsNothing);
  });

  testWidgets('editor toggles sides and merges corners live', (tester) async {
    final changes = await pump(tester);
    await openEditor(tester);
    expect(find.byType(SuperLayoutEditor), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('super-layout-side-north')));
    await tester.pumpAndSettle();
    expect(changes.last.north, isFalse);
    expect(find.byKey(const ValueKey('super-layout-nw')), findsNothing);
    expect(
      find.byKey(const ValueKey('super-layout-preview-north')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('super-layout-side-north')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-layout-corner-sw')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fusionné avec Ouest').last);
    await tester.pumpAndSettle();
    expect(changes.last.sw, CornerMerge.column);
    expect(find.byKey(const ValueKey('super-layout-sw')), findsNothing);
  });

  testWidgets('cancel restores the previous layout', (tester) async {
    final changes = await pump(tester);
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('super-layout-side-east')));
    await tester.pumpAndSettle();
    expect(changes.last.east, isFalse);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(
      changes.last,
      const SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['center'],
        },
      ),
    );
    expect(find.byKey(const ValueKey('super-layout-east')), findsOneWidget);
  });

  testWidgets('edit mode names the used zones above their centre', (
    tester,
  ) async {
    final editMode = ValueNotifier(false);
    addTearDown(editMode.dispose);
    await tester.pumpWidget(
      StyleEditScope(
        controller: editMode,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: zonedLayout(
                zones: const {
                  SuperLayoutZone.west: SizedBox.expand(),
                  SuperLayoutZone.center: Text('Contenu'),
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('super-layout-name-west')), findsNothing);

    editMode.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Ouest'), findsOneWidget);
    expect(find.text('Centre'), findsOneWidget);
    expect(find.byKey(const ValueKey('super-layout-name-north')), findsNothing);
    final zoneCentre = tester.getCenter(
      find.byKey(const ValueKey('super-layout-west')),
    );
    expect(tester.getCenter(find.text('Ouest')), zoneCentre);

    editMode.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Ouest'), findsNothing);
  });

  testWidgets('clicking a zone name swaps it with its opposite', (
    tester,
  ) async {
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    final changes = <SuperLayoutConfig>[];
    await tester.pumpWidget(
      StyleEditScope(
        controller: editMode,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: zonedLayout(
                onChanged: changes.add,
                zones: const {
                  SuperLayoutZone.west: Text('Panneau'),
                  SuperLayoutZone.center: Text('Contenu'),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    const swap = ValueKey('super-layout-swap-west');
    expect(find.byKey(swap), findsNothing);

    await tester.tap(find.text('Centre'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.swap_calls), findsNothing);
    expect(find.byIcon(Icons.swap_horiz), findsNothing);

    final west = tester.getCenter(find.text('Panneau'));
    await tester.tap(find.text('Ouest'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(swap));
    await tester.pumpAndSettle();

    expect(changes.last.swaps, {SuperLayoutZone.west});
    expect(tester.getCenter(find.text('Panneau')).dx, greaterThan(west.dx));
    expect(find.byKey(swap), findsNothing);
  });

  test('swaps are symmetric and round-trip through json', () {
    final config = const SuperLayoutConfig()
        .withSwap(SuperLayoutZone.east)
        .withSwap(SuperLayoutZone.sw);
    expect(config.contentZone(SuperLayoutZone.west), SuperLayoutZone.east);
    expect(config.contentZone(SuperLayoutZone.east), SuperLayoutZone.west);
    expect(config.contentZone(SuperLayoutZone.ne), SuperLayoutZone.sw);
    expect(config.contentZone(SuperLayoutZone.center), SuperLayoutZone.center);
    expect(SuperLayoutConfig.fromJson(config.toJson()), config);
    expect(
      config.withSwap(SuperLayoutZone.west).withSwap(SuperLayoutZone.ne),
      const SuperLayoutConfig(),
    );
  });

  test('swapping two sides also swaps their sizes and corner merges', () {
    const config = SuperLayoutConfig(
      westSize: 200,
      eastSize: 90,
      nw: CornerMerge.column,
    );
    final swapped = config.withSwap(SuperLayoutZone.west);
    expect(swapped.westSize, 90);
    expect(swapped.eastSize, 200);
    expect(swapped.ne, CornerMerge.column);
    expect(swapped.nw, CornerMerge.none);
    expect(swapped.withSwap(SuperLayoutZone.east), config);
  });

  test('swapping with a missing side moves it with its size and corners', () {
    const config = SuperLayoutConfig(
      east: false,
      westSize: 200,
      nw: CornerMerge.row,
    );
    final moved = config.withSwap(SuperLayoutZone.west);
    expect(moved.west, isFalse);
    expect(moved.east, isTrue);
    expect(moved.eastSize, 200);
    expect(moved.ne, CornerMerge.row);
    expect(moved.nw, CornerMerge.none);
    expect(moved.contentZone(SuperLayoutZone.east), SuperLayoutZone.west);
    expect(moved.withSwap(SuperLayoutZone.east), config);
    expect(config.canSwap(SuperLayoutZone.center), isFalse);
    expect(
      const SuperLayoutConfig(south: false).canSwap(SuperLayoutZone.nw),
      isFalse,
    );
  });

  testWidgets('a zone without opposite moves to the other side', (
    tester,
  ) async {
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    final changes = <SuperLayoutConfig>[];
    await tester.pumpWidget(
      StyleEditScope(
        controller: editMode,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: zonedLayout(
                config: const SuperLayoutConfig(east: false),
                onChanged: changes.add,
                zones: const {
                  SuperLayoutZone.west: Text('Panneau'),
                  SuperLayoutZone.center: Text('Contenu'),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getCenter(find.text('Panneau'));
    await tester.tap(find.text('Ouest'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-layout-swap-west')));
    await tester.pumpAndSettle();

    expect(changes.last.east, isTrue);
    expect(changes.last.west, isFalse);
    expect(tester.getCenter(find.text('Panneau')).dx, greaterThan(before.dx));
    expect(find.text('Est'), findsOneWidget);
  });

  testWidgets('dragging a zone name onto the centre swaps it', (tester) async {
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    final changes = <SuperLayoutConfig>[];
    await tester.pumpWidget(
      StyleEditScope(
        controller: editMode,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: zonedLayout(
                onChanged: changes.add,
                zones: const {
                  SuperLayoutZone.west: Text('Panneau'),
                  SuperLayoutZone.center: Text('Contenu'),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getCenter(find.text('Panneau'));

    // Lâché hors du centre : rien ne change.
    await tester.drag(find.text('Ouest'), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Ouest')),
    );
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveTo(tester.getCenter(find.text('Contenu')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('super-layout-center-drop')),
      findsOneWidget,
    );
    // Le nom glissé annonce la zone future (le repère de la zone Est existe déjà).
    expect(find.text('Est'), findsNWidgets(2));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(changes.last.swaps, {SuperLayoutZone.west});
    expect(tester.getCenter(find.text('Panneau')).dx, greaterThan(before.dx));
    expect(
      find.byKey(const ValueKey('super-layout-center-drop')),
      findsNothing,
    );
  });
}
