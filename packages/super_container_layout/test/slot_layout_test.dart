import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/widgets/layout_selection.dart';
import 'package:super_container_layout/widgets/slot_implementation.dart';
import 'package:super_container_layout/widgets/super_container.dart';
import 'package:super_container_layout/widgets/super_layout.dart';

import 'package:super_container_layout/widgets/style_edit_banner.dart';

Widget _box(String id, {double? width, double? height}) =>
    SizedBox(key: ValueKey('box-$id'), width: width, height: height);

BuilderSlot _slot(
  String id, {
  double? width,
  double? height,
  SlotSizing sizing = SlotSizing.intrinsic,
  bool visible = true,
}) => BuilderSlot(
  id: id,
  label: id,
  sizing: sizing,
  visible: visible,
  builder: (_) => _box(id, width: width, height: height),
);

void main() {
  const size = Size(600, 400);

  group('SuperLayoutConfig auto sides and placements', () {
    test('placement types and instance IDs survive JSON and moves', () {
      final config = const SuperLayoutConfig()
          .withSlotMoved(
            'first',
            SuperLayoutZone.center,
            type: 'registry:clock',
          )
          .withSlotMoved(
            'second',
            SuperLayoutZone.center,
            type: 'registry:clock',
          );
      expect(config.toJson()['placements'], {
        'center': [
          {'type': 'registry:clock', 'id': 'first'},
          {'type': 'registry:clock', 'id': 'second'},
        ],
      });
      final restored = SuperLayoutConfig.fromJson(config.toJson());
      expect(restored, config);
      expect(restored.hashCode, config.hashCode);
      final moved = restored.withSlotMoved('first', SuperLayoutZone.east);
      expect(moved.slotTypeOf('first'), 'registry:clock');
      expect(moved.placementsOf(SuperLayoutZone.center), ['second']);
      expect(moved.placementsOf(SuperLayoutZone.east), ['first']);
      expect(config.copyWith(slotTypes: {'first': 'other'}), isNot(config));
    });

    test('legacy string placements remain readable', () {
      final config = SuperLayoutConfig.fromJson({
        'placements': {
          'center': ['registry:clock'],
        },
      });
      expect(config.slotTypeOf('registry:clock'), 'registry:clock');
      expect(config.toJson()['placements'], {
        'center': [
          {'type': 'registry:clock', 'id': 'registry:clock'},
        ],
      });
    });

    test('measured sizes replace fixed sizes of auto sides only', () {
      final rects =
          const SuperLayoutConfig(
            south: false,
            east: false,
            autoSides: {SuperLayoutZone.north},
          ).resolve(
            size,
            measured: {SuperLayoutZone.north: 50, SuperLayoutZone.west: 10},
          );
      expect(
        rects[SuperLayoutZone.north],
        const Rect.fromLTRB(120, 0, 600, 50),
      );
      expect(rects[SuperLayoutZone.west], const Rect.fromLTRB(0, 50, 120, 400));
      expect(
        rects[SuperLayoutZone.center],
        const Rect.fromLTRB(120, 50, 600, 400),
      );
    });

    test('an auto side without measure keeps its fixed size', () {
      final rects = const SuperLayoutConfig(autoSides: {SuperLayoutZone.north})
          .resolve(size);
      expect(rects[SuperLayoutZone.north]!.height, 80);
    });

    test('visibleZones lists the zones whatever the size', () {
      expect(const SuperLayoutConfig(north: false, west: false).visibleZones, {
        SuperLayoutZone.center,
        SuperLayoutZone.south,
        SuperLayoutZone.east,
        SuperLayoutZone.se,
      });
    });

    test('json round trip keeps auto sides and placements', () {
      const config = SuperLayoutConfig(
        autoSides: {SuperLayoutZone.north, SuperLayoutZone.west},
        placements: {
          SuperLayoutZone.north: ['toolbar', 'breadcrumbs'],
          SuperLayoutZone.center: ['content'],
        },
      );
      final restored = SuperLayoutConfig.fromJson(config.toJson());
      expect(restored, config);
      expect(restored.placementsOf(SuperLayoutZone.north), [
        'toolbar',
        'breadcrumbs',
      ]);
      expect(restored.placementsOf(SuperLayoutZone.south), isEmpty);
    });

    test('missing keys fall back to the fallback config', () {
      const fallback = SuperLayoutConfig(
        autoSides: {SuperLayoutZone.south},
        placements: {
          SuperLayoutZone.center: ['content'],
        },
      );
      final restored = SuperLayoutConfig.fromJson({
        'north': false,
      }, fallback: fallback);
      expect(restored.north, isFalse);
      expect(restored.autoSides, {SuperLayoutZone.south});
      expect(restored.placements, fallback.placements);
    });

    test('invalid auto sides and placements are rejected', () {
      for (final json in [
        {
          'autoSides': ['center'],
        },
        {'autoSides': 'north'},
        {
          'placements': {'nowhere': <String>[]},
        },
        {
          'placements': {
            'north': [1],
          },
        },
        {'placements': <String>[]},
        {
          'placements': {
            'center': [
              {'type': 'clock'},
            ],
          },
        },
        {
          'placements': {
            'center': [
              {'type': '', 'id': 'instance'},
            ],
          },
        },
        {
          'placements': {
            'center': [
              {'type': 'clock', 'id': 'instance'},
              {'type': 'other', 'id': 'instance'},
            ],
          },
        },
      ]) {
        expect(
          () => SuperLayoutConfig.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });

    test('equality takes auto sides and placements into account', () {
      const base = SuperLayoutConfig(
        autoSides: {SuperLayoutZone.north},
        placements: {
          SuperLayoutZone.north: ['a', 'b'],
        },
      );
      expect(
        base,
        const SuperLayoutConfig(
          autoSides: {SuperLayoutZone.north},
          placements: {
            SuperLayoutZone.north: ['a', 'b'],
          },
        ),
      );
      expect(base.hashCode, base.copyWith().hashCode);
      expect(base == base.withAuto(SuperLayoutZone.north, false), isFalse);
      expect(
        base == base.withPlacement(SuperLayoutZone.north, ['b', 'a']),
        isFalse,
      );
      expect(base.withPlacement(SuperLayoutZone.north, []).placements, isEmpty);
    });

    test('withAuto rejects zones that are not sides', () {
      expect(
        () => const SuperLayoutConfig().withAuto(SuperLayoutZone.center, true),
        throwsArgumentError,
      );
    });

    test('swapping a side moves its auto flag with its size', () {
      final swapped = const SuperLayoutConfig(
        autoSides: {SuperLayoutZone.north},
      ).withSwap(SuperLayoutZone.north);
      expect(swapped.autoSides, {SuperLayoutZone.south});
    });
  });

  group('SuperLayout with slots', () {
    Future<void> pump(
      WidgetTester tester, {
      required SuperLayoutConfig config,
      required List<SlotImplementation> slots,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: SuperLayout(config: config, slots: slots),
          ),
        ),
      ),
    );

    Rect rectOf(WidgetTester tester, String id) =>
        tester.getRect(find.byKey(ValueKey('box-$id')));

    testWidgets('auto north takes the height of its stacked slots', (
      tester,
    ) async {
      await pump(
        tester,
        config: const SuperLayoutConfig(
          south: false,
          west: false,
          east: false,
          autoSides: {SuperLayoutZone.north},
          placements: {
            SuperLayoutZone.north: ['toolbar', 'crumbs'],
            SuperLayoutZone.center: ['content'],
          },
        ),
        slots: [
          _slot('toolbar', height: 30),
          _slot('crumbs', height: 50),
          _slot('content', sizing: SlotSizing.fill),
        ],
      );
      expect(rectOf(tester, 'toolbar'), const Rect.fromLTWH(0, 0, 600, 30));
      expect(rectOf(tester, 'crumbs'), const Rect.fromLTWH(0, 30, 600, 50));
      expect(rectOf(tester, 'content'), const Rect.fromLTWH(0, 80, 600, 320));
    });

    testWidgets('the north grows when a slot becomes taller', (tester) async {
      SuperLayoutConfig config() => const SuperLayoutConfig(
        south: false,
        west: false,
        east: false,
        autoSides: {SuperLayoutZone.north},
        placements: {
          SuperLayoutZone.north: ['bar'],
          SuperLayoutZone.center: ['content'],
        },
      );
      await pump(
        tester,
        config: config(),
        slots: [_slot('bar', height: 40), _slot('content')],
      );
      expect(rectOf(tester, 'content').top, 40);

      await pump(
        tester,
        config: config(),
        slots: [_slot('bar', height: 90), _slot('content')],
      );
      expect(rectOf(tester, 'content').top, 90);
    });

    testWidgets('auto west takes the width of its slot', (tester) async {
      await pump(
        tester,
        config: const SuperLayoutConfig(
          north: false,
          south: false,
          east: false,
          autoSides: {SuperLayoutZone.west},
          placements: {
            SuperLayoutZone.west: ['side'],
            SuperLayoutZone.center: ['content'],
          },
        ),
        slots: [_slot('side', width: 150), _slot('content')],
      );
      expect(rectOf(tester, 'side').width, 150);
      expect(rectOf(tester, 'content').left, 150);
    });

    testWidgets('auto north and west resolve together', (tester) async {
      await pump(
        tester,
        config: const SuperLayoutConfig(
          south: false,
          east: false,
          autoSides: {SuperLayoutZone.north, SuperLayoutZone.west},
          placements: {
            SuperLayoutZone.north: ['bar'],
            SuperLayoutZone.west: ['side'],
            SuperLayoutZone.center: ['content'],
          },
        ),
        slots: [
          _slot('bar', height: 40),
          _slot('side', width: 100),
          _slot('content', sizing: SlotSizing.fill),
        ],
      );
      expect(rectOf(tester, 'bar'), const Rect.fromLTWH(100, 0, 500, 40));
      expect(rectOf(tester, 'side').left, 0);
      expect(rectOf(tester, 'side').width, 100);
      expect(rectOf(tester, 'content'), const Rect.fromLTWH(100, 40, 500, 360));
    });

    testWidgets('hidden slots and unknown ids take no room', (tester) async {
      await pump(
        tester,
        config: const SuperLayoutConfig(
          south: false,
          west: false,
          east: false,
          autoSides: {SuperLayoutZone.north},
          placements: {
            SuperLayoutZone.north: ['hidden', 'missing', 'bar'],
            SuperLayoutZone.center: ['content'],
          },
        ),
        slots: [
          _slot('hidden', height: 70, visible: false),
          _slot('bar', height: 20),
          _slot('content', sizing: SlotSizing.fill),
        ],
      );
      expect(find.byKey(const ValueKey('box-hidden')), findsNothing);
      expect(rectOf(tester, 'bar'), const Rect.fromLTWH(0, 0, 600, 20));
      expect(rectOf(tester, 'content').top, 20);
    });

    testWidgets('an auto side without content keeps its fixed size', (
      tester,
    ) async {
      await pump(
        tester,
        config: const SuperLayoutConfig(
          south: false,
          west: false,
          east: false,
          autoSides: {SuperLayoutZone.north},
          placements: {
            SuperLayoutZone.center: ['content'],
          },
        ),
        slots: [_slot('content', sizing: SlotSizing.fill)],
      );
      expect(rectOf(tester, 'content').top, 80);
      expect(find.text('Nord'), findsOneWidget);
    });

    testWidgets('fill slots share the zone, intrinsic ones keep their height', (
      tester,
    ) async {
      await pump(
        tester,
        config: const SuperLayoutConfig(
          north: false,
          south: false,
          west: false,
          east: false,
          placements: {
            SuperLayoutZone.center: ['head', 'body'],
          },
        ),
        slots: [
          _slot('head', height: 60),
          _slot('body', sizing: SlotSizing.fill),
        ],
      );
      expect(rectOf(tester, 'head'), const Rect.fromLTWH(0, 0, 600, 60));
      expect(rectOf(tester, 'body'), const Rect.fromLTWH(0, 60, 600, 340));
    });

    testWidgets('swapped zones move their slots with them', (tester) async {
      await pump(
        tester,
        config: const SuperLayoutConfig(
          south: false,
          east: false,
          north: false,
          swaps: {SuperLayoutZone.west},
          placements: {
            SuperLayoutZone.west: ['side'],
          },
        ).copyWith(east: true, west: false, westSize: 120, eastSize: 120),
        slots: [_slot('side', sizing: SlotSizing.fill)],
      );
      expect(rectOf(tester, 'side').right, 600);
    });
  });

  testWidgets('the north of a nested layout can be dragged to the south', (
    tester,
  ) async {
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    final inner = <SuperLayoutConfig>[];
    const innerConfig = SuperLayoutConfig(
      south: false,
      west: false,
      east: false,
      autoSides: {SuperLayoutZone.north},
      placements: {
        SuperLayoutZone.north: ['bar'],
        SuperLayoutZone.center: ['content'],
      },
    );
    await tester.pumpWidget(
      StyleEditScope(
        controller: editMode,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: SuperLayout(
                config: const SuperLayoutConfig(
                  north: false,
                  south: false,
                  east: false,
                  placements: {
                    SuperLayoutZone.west: ['side'],
                    SuperLayoutZone.center: ['main'],
                  },
                ),
                slots: [
                  _slot('side'),
                  BuilderSlot(
                    id: 'main',
                    label: 'main',
                    labelAlignment: Alignment.topRight,
                    builder: (_) => SuperLayout(
                      config: innerConfig,
                      onChanged: inner.add,
                      slots: [
                        _slot('bar', height: 40),
                        _slot('content', sizing: SlotSizing.fill),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const ValueKey('box-content'))) +
          const Offset(20, 20),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('box-bar'))).top, 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Nord')),
    );
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('box-content'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(inner, isNotEmpty);
    expect(inner.last.south, isTrue);
    expect(inner.last.north, isFalse);
    expect(inner.last.isAuto(SuperLayoutZone.south), isTrue);
    expect(tester.getRect(find.byKey(const ValueKey('box-bar'))).bottom, 400);
  });
  group('SuperLayoutConfig.withSlotMoved', () {
    const config = SuperLayoutConfig(
      placements: {
        SuperLayoutZone.north: ['a', 'b', 'c'],
        SuperLayoutZone.center: ['content'],
      },
    );

    test('reorders inside a zone before or after a reference', () {
      expect(
        config
            .withSlotMoved('c', SuperLayoutZone.north, beforeId: 'a')
            .placementsOf(SuperLayoutZone.north),
        ['c', 'a', 'b'],
      );
      expect(
        config
            .withSlotMoved('a', SuperLayoutZone.north, afterId: 'c')
            .placementsOf(SuperLayoutZone.north),
        ['b', 'c', 'a'],
      );
      expect(
        config
            .withSlotMoved('a', SuperLayoutZone.north, afterId: 'a')
            .placementsOf(SuperLayoutZone.north),
        ['b', 'c', 'a'],
      );
    });

    test('moves a slot to another zone and drops empty zones', () {
      final moved = config.withSlotMoved('content', SuperLayoutZone.north);
      expect(moved.placementsOf(SuperLayoutZone.north), [
        'a',
        'b',
        'c',
        'content',
      ]);
      expect(moved.placements.containsKey(SuperLayoutZone.center), isFalse);
      expect(
        config
            .withSlotMoved('b', SuperLayoutZone.south)
            .placementsOf(SuperLayoutZone.south),
        ['b'],
      );
    });

    test('an unknown reference puts the slot last', () {
      expect(
        config
            .withSlotMoved('a', SuperLayoutZone.north, beforeId: 'zzz')
            .placementsOf(SuperLayoutZone.north),
        ['b', 'c', 'a'],
      );
    });
  });

  group('moving slots by their label', () {
    const config = SuperLayoutConfig(
      west: false,
      east: false,
      autoSides: {SuperLayoutZone.north},
      placements: {
        SuperLayoutZone.north: ['a', 'b', 'c'],
        SuperLayoutZone.center: ['content'],
      },
    );

    Future<List<SuperLayoutConfig>> pumpMovable(WidgetTester tester) async {
      final editMode = ValueNotifier(true);
      addTearDown(editMode.dispose);
      final changes = <SuperLayoutConfig>[];
      await tester.pumpWidget(
        StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: SuperLayout(
                  config: config,
                  onChanged: changes.add,
                  slots: [
                    _slot('a', height: 30),
                    _slot('b', height: 30),
                    _slot('c', height: 30),
                    _slot('content', sizing: SlotSizing.fill),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(500, 200));
      await tester.pumpAndSettle();
      return changes;
    }

    Future<void> dragLabel(WidgetTester tester, String id, Offset to) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('slot-label-$id'))),
      );
      await gesture.moveBy(const Offset(0, 25));
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('dropping on the lower half puts the slot after', (
      tester,
    ) async {
      final changes = await pumpMovable(tester);
      await dragLabel(tester, 'a', const Offset(300, 85));
      expect(changes.last.placementsOf(SuperLayoutZone.north), ['b', 'c', 'a']);
      expect(
        tester.getRect(find.byKey(const ValueKey('box-a'))).top,
        greaterThan(tester.getRect(find.byKey(const ValueKey('box-c'))).top),
      );
    });

    testWidgets('dropping on the upper half puts the slot before', (
      tester,
    ) async {
      final changes = await pumpMovable(tester);
      await dragLabel(tester, 'c', const Offset(300, 5));
      expect(changes.last.placementsOf(SuperLayoutZone.north), ['c', 'a', 'b']);
    });

    testWidgets('dropping on itself changes nothing', (tester) async {
      final changes = await pumpMovable(tester);
      await dragLabel(tester, 'b', const Offset(450, 45));
      expect(changes, isEmpty);
    });

    testWidgets('dropping on a free zone moves the slot there', (tester) async {
      final changes = await pumpMovable(tester);
      await dragLabel(tester, 'a', const Offset(300, 370));
      expect(changes.last.placementsOf(SuperLayoutZone.north), ['b', 'c']);
      expect(changes.last.placementsOf(SuperLayoutZone.south), ['a']);
      expect(tester.getRect(find.byKey(const ValueKey('box-a'))).top, 320);
      expect(tester.getRect(find.byKey(const ValueKey('box-b'))).top, 0);
    });

    testWidgets('hovering a slot label highlights that slot', (tester) async {
      await pumpMovable(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(500, 300));
      addTearDown(mouse.removePointer);
      await tester.pump();
      const highlight = ValueKey('slot-highlight-b');
      expect(find.byKey(highlight), findsNothing);

      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('slot-label-b'))),
      );
      await tester.pump();
      expect(find.byKey(highlight), findsOneWidget);
      expect(
        tester.getRect(find.byKey(highlight)),
        tester.getRect(find.byKey(const ValueKey('box-b'))),
      );
      expect(find.byKey(const ValueKey('slot-highlight-a')), findsNothing);

      await mouse.moveTo(const Offset(500, 300));
      await tester.pump();
      expect(find.byKey(highlight), findsNothing);
    });

    testWidgets('the slot stays highlighted while its label is dragged', (
      tester,
    ) async {
      await pumpMovable(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('slot-label-a'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 25));
      await gesture.moveTo(const Offset(450, 200));
      await tester.pump();
      expect(find.byKey(const ValueKey('slot-highlight-a')), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slot-highlight-a')), findsNothing);
    });

    testWidgets('hovering a zone name highlights that zone', (tester) async {
      await pumpMovable(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(500, 300));
      addTearDown(mouse.removePointer);
      await tester.pump();
      const highlight = ValueKey('super-layout-zone-highlight-north');
      expect(find.byKey(highlight), findsNothing);

      await mouse.moveTo(tester.getCenter(find.text('Nord')));
      await tester.pump();
      expect(find.byKey(highlight), findsOneWidget);
      expect(tester.getRect(find.byKey(highlight)).height, 90);
      expect(
        find.byKey(const ValueKey('super-layout-zone-highlight-south')),
        findsNothing,
      );

      await mouse.moveTo(const Offset(500, 300));
      await tester.pump();
      expect(find.byKey(highlight), findsNothing);
    });

    testWidgets('the dragged label announces the target zone and rank', (
      tester,
    ) async {
      await pumpMovable(tester);
      expect(find.text('a · Nord 1/3'), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('slot-label-a'))),
      );
      await gesture.moveBy(const Offset(0, 25));

      await gesture.moveTo(const Offset(450, 85));
      await tester.pump();
      expect(find.text('a → Nord 3/3'), findsOneWidget);

      await gesture.moveTo(const Offset(450, 38));
      await tester.pump();
      expect(find.text('a → Nord 1/3'), findsOneWidget);

      await gesture.moveTo(const Offset(450, 370));
      await tester.pump();
      expect(find.text('a → Sud 1/1'), findsOneWidget);

      await gesture.moveTo(const Offset(450, 300));
      await tester.pump();
      expect(find.text('a → Centre 2/2'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.textContaining('→'), findsNothing);
    });

    testWidgets('hovering another zone name highlights the centre', (
      tester,
    ) async {
      await pumpMovable(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(500, 300));
      addTearDown(mouse.removePointer);
      await tester.pump();
      const hint = ValueKey('super-layout-center-hint');
      expect(find.byKey(hint), findsNothing);

      await mouse.moveTo(tester.getCenter(find.text('Nord')));
      await tester.pump();
      expect(find.byKey(hint), findsOneWidget);
      expect(
        tester.getRect(find.byKey(hint)),
        const Rect.fromLTRB(0, 90, 600, 320),
      );

      await mouse.moveTo(const Offset(500, 300));
      await tester.pump();
      expect(find.byKey(hint), findsNothing);

      // Le centre n'a pas de centre associé : il se surligne lui-même.
      await mouse.moveTo(tester.getCenter(find.text('Centre')));
      await tester.pump();
      expect(find.byKey(hint), findsNothing);
      expect(
        find.byKey(const ValueKey('super-layout-zone-highlight-center')),
        findsOneWidget,
      );
    });

    testWidgets('the centre stays highlighted while a zone name is dragged', (
      tester,
    ) async {
      await pumpMovable(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Nord')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveTo(const Offset(500, 380));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('super-layout-center-hint')),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-layout-center-hint')),
        findsNothing,
      );
    });

    testWidgets('hovering a label enlarges every label of the layout', (
      tester,
    ) async {
      await pumpMovable(tester);
      double width(Finder finder) =>
          (tester.getBottomRight(finder) - tester.getTopLeft(finder)).dx;
      final chipB = find.byKey(const ValueKey('slot-label-b'));
      final zoneName = find.text('Nord');
      final chipBefore = width(chipB);
      final zoneBefore = width(zoneName);
      final topLeft = tester.getTopLeft(chipB);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(500, 300));
      addTearDown(mouse.removePointer);
      await tester.pump();

      // Survol d'une étiquette de slot : les slots et les zones grossissent.
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('slot-label-a'))),
      );
      await tester.pumpAndSettle();
      expect(width(chipB), closeTo(chipBefore * 1.3, .5));
      expect(width(zoneName), closeTo(zoneBefore * 1.3, .5));
      expect(tester.getTopLeft(chipB), topLeft);

      await mouse.moveTo(const Offset(500, 300));
      await tester.pumpAndSettle();
      expect(width(chipB), closeTo(chipBefore, .5));
      expect(width(zoneName), closeTo(zoneBefore, .5));

      // Survol d'un nom de zone : les étiquettes de slot grossissent aussi.
      await mouse.moveTo(tester.getCenter(zoneName));
      await tester.pumpAndSettle();
      expect(width(chipB), closeTo(chipBefore * 1.3, .5));
      expect(width(zoneName), closeTo(zoneBefore * 1.3, .5));

      await mouse.moveTo(const Offset(500, 300));
      await tester.pumpAndSettle();
      expect(width(chipB), closeTo(chipBefore, .5));
    });

    testWidgets('only the slot labels of the hovered zone grow', (
      tester,
    ) async {
      await pumpMovable(tester);
      double width(Finder finder) =>
          (tester.getBottomRight(finder) - tester.getTopLeft(finder)).dx;
      final north = find.byKey(const ValueKey('slot-label-b'));
      final centre = find.byKey(const ValueKey('slot-label-content'));
      final northBefore = width(north);
      final centreBefore = width(centre);
      final northName = find.text('Nord');
      final centreName = find.text('Centre');
      final northNameBefore = width(northName);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(500, 300));
      addTearDown(mouse.removePointer);
      await tester.pump();

      // Une étiquette du Nord : les slots du Nord grossissent, pas ceux du centre.
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('slot-label-a'))),
      );
      await tester.pumpAndSettle();
      expect(width(north), closeTo(northBefore * 1.3, .5));
      expect(width(centre), closeTo(centreBefore, .5));
      expect(width(northName), closeTo(northNameBefore * 1.3, .5));

      // Le nom du centre : les slots du centre grossissent, pas ceux du Nord.
      await mouse.moveTo(const Offset(500, 300));
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(centreName));
      await tester.pumpAndSettle();
      expect(width(centre), closeTo(centreBefore * 1.3, .5));
      expect(width(north), closeTo(northBefore, .5));
      expect(width(northName), closeTo(northNameBefore * 1.3, .5));
    });

    testWidgets('labels stay enlarged while a label is dragged', (
      tester,
    ) async {
      await pumpMovable(tester);
      final chipB = find.byKey(const ValueKey('slot-label-b'));
      final before =
          (tester.getBottomRight(chipB) - tester.getTopLeft(chipB)).dx;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('slot-label-a'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 25));
      await gesture.moveTo(const Offset(450, 300));
      await tester.pumpAndSettle();
      expect(
        (tester.getBottomRight(chipB) - tester.getTopLeft(chipB)).dx,
        closeTo(before * 1.3, .5),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        (tester.getBottomRight(find.byKey(const ValueKey('slot-label-b'))) -
                tester.getTopLeft(find.byKey(const ValueKey('slot-label-b'))))
            .dx,
        closeTo(before, .5),
      );
    });

    testWidgets('a container slot shows its label on the opposite corner', (
      tester,
    ) async {
      final editMode = ValueNotifier(true);
      addTearDown(editMode.dispose);
      await tester.pumpWidget(
        StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: SuperLayout(
                  editable: false,
                  config: const SuperLayoutConfig(
                    north: true,
                    south: false,
                    west: false,
                    east: false,
                    placements: {
                      SuperLayoutZone.center: ['main'],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'main',
                      label: 'Explorateur',
                      labelAlignment: Alignment.topRight,
                      builder: (_) => SuperLayout(
                        editable: false,
                        config: const SuperLayoutConfig(
                          south: false,
                          west: false,
                          east: false,
                          autoSides: {SuperLayoutZone.north},
                          placements: {
                            SuperLayoutZone.north: ['bar'],
                            SuperLayoutZone.center: ['content'],
                          },
                        ),
                        slots: [
                          _slot('bar', height: 40),
                          _slot('content', sizing: SlotSizing.fill),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(590, 10));
      await tester.pumpAndSettle();

      final container = find.byKey(const ValueKey('slot-label-main'));
      expect(find.text('Explorateur · Centre 1/1'), findsOneWidget);
      final rect = Rect.fromPoints(
        tester.getTopLeft(container),
        tester.getBottomRight(container),
      );
      expect(rect.right, 596);
      expect(rect.top, 84);
      // Les étiquettes de la disposition interne restent à gauche, sans
      // recouvrement, et le conteneur est dessiné au-dessus du contenu.
      expect(find.byKey(const ValueKey('slot-label-bar')), findsNothing);
      await tester.tapAt(const Offset(500, 150));
      await tester.pumpAndSettle();
      expect(container, findsNothing);
      final bar = tester.getRect(find.byKey(const ValueKey('slot-label-bar')));
      expect(bar.topLeft, const Offset(4, 84));
      expect(rect.overlaps(bar), isFalse);
      // Le Centre de la disposition qui contient main et celui de la
      // disposition interne affichent chacun leur nom.
      expect(find.text('Centre'), findsOneWidget);
      expect(find.text('Nord'), findsOneWidget);
    });

    testWidgets('clicking nested content selects only its layout overlays', (
      tester,
    ) async {
      final editMode = ValueNotifier(true);
      addTearDown(editMode.dispose);
      await tester.pumpWidget(
        StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: SuperLayout(
                  editable: false,
                  config: const SuperLayoutConfig(
                    north: false,
                    south: false,
                    east: false,
                    placements: {
                      SuperLayoutZone.west: ['side'],
                      SuperLayoutZone.center: ['main'],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'side',
                      label: 'side',
                      builder: (_) => SuperLayout(
                        editable: false,
                        config: const SuperLayoutConfig(
                          north: false,
                          west: false,
                          east: false,
                          placements: {
                            SuperLayoutZone.center: ['places'],
                            SuperLayoutZone.south: ['disks'],
                          },
                        ),
                        slots: [
                          _slot('places', sizing: SlotSizing.fill),
                          _slot('disks', height: 30),
                        ],
                      ),
                    ),
                    BuilderSlot(
                      id: 'main',
                      label: 'main',
                      builder: (_) => SuperLayout(
                        editable: false,
                        config: const SuperLayoutConfig(
                          south: false,
                          west: false,
                          east: false,
                          autoSides: {SuperLayoutZone.north},
                          placements: {
                            SuperLayoutZone.north: ['bar'],
                            SuperLayoutZone.center: ['content'],
                          },
                        ),
                        slots: [
                          _slot('bar', height: 40),
                          _slot('content', sizing: SlotSizing.fill),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mainChild = find.byKey(const ValueKey('slot-label-bar'));
      final sideChild = find.byKey(const ValueKey('slot-label-places'));
      expect(find.byKey(const ValueKey('slot-label-main')), findsNothing);
      expect(find.byKey(const ValueKey('slot-label-side')), findsNothing);
      expect(find.text('Nord'), findsNothing);
      expect(mainChild, findsNothing);
      expect(sideChild, findsNothing);

      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('box-content'))) +
            const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      expect(mainChild, findsOneWidget);
      expect(find.text('Nord'), findsOneWidget);
      expect(sideChild, findsNothing);

      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('box-places'))) +
            const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-layout-zone-selected-center')),
        findsNothing,
      );
      expect(mainChild, findsNothing);
      expect(sideChild, findsOneWidget);

      // Un clic sur le nom selectionne la zone, sans deselectionner le layout.
      await tester.tap(find.text('Centre'));
      await tester.pumpAndSettle();
      expect(sideChild, findsOneWidget);
      expect(
        find.byKey(const ValueKey('super-layout-zone-selected-center')),
        findsOneWidget,
      );
    });

    testWidgets('a root layout always shows its labels', (tester) async {
      await pumpMovable(tester);
      expect(find.byKey(const ValueKey('slot-label-a')), findsOneWidget);
      expect(find.text('Nord'), findsOneWidget);
    });

    testWidgets('the banner shows the path of the selected zones', (
      tester,
    ) async {
      final editMode = ValueNotifier(true);
      addTearDown(editMode.dispose);
      SuperLayout layout({
        required String name,
        required SuperLayoutConfig config,
        required List<SlotImplementation> slots,
      }) => SuperLayout(
        name: name,
        editable: false,
        config: config,
        slots: slots,
      );
      await tester.pumpWidget(
        StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            builder: (context, child) => Stack(
              children: [
                Positioned.fill(child: child!),
                const Positioned.fill(child: StyleEditBanner()),
              ],
            ),
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: layout(
                  name: 'Page',
                  config: const SuperLayoutConfig(
                    north: false,
                    south: false,
                    west: false,
                    east: false,
                    placements: {
                      SuperLayoutZone.center: ['l2'],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'l2',
                      label: 'l2',
                      builder: (_) => layout(
                        name: 'Explorateur',
                        config: const SuperLayoutConfig(
                          north: false,
                          south: false,
                          east: false,
                          westSize: 300,
                          placements: {
                            SuperLayoutZone.west: ['l3'],
                            SuperLayoutZone.center: ['content'],
                          },
                        ),
                        slots: [
                          BuilderSlot(
                            id: 'l3',
                            label: 'l3',
                            builder: (_) => layout(
                              name: 'Panneau',
                              config: const SuperLayoutConfig(
                                north: false,
                                south: false,
                                west: false,
                                placements: {
                                  SuperLayoutZone.east: ['y'],
                                  SuperLayoutZone.center: ['z'],
                                },
                              ),
                              slots: [
                                _slot('y', sizing: SlotSizing.fill),
                                _slot('z', sizing: SlotSizing.fill),
                              ],
                            ),
                          ),
                          _slot('content', sizing: SlotSizing.fill),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pathRow = find.byKey(const ValueKey('style-edit-banner-path'));
      String? path() => pathRow.evaluate().isEmpty
          ? null
          : tester
                .widgetList<Text>(
                  find.descendant(of: pathRow, matching: find.byType(Text)),
                )
                .map((text) => text.data)
                .join(' > ');
      Finder name(String zone) =>
          find.byKey(ValueKey('super-layout-name-$zone'));
      Finder segment(String label) =>
          find.descendant(of: pathRow, matching: find.text(label));
      expect(find.text('Mode édition'), findsOneWidget);
      expect(path(), isNull);

      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('box-y'))) +
            const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      expect(path(), 'Page > Centre > Explorateur > Ouest > Panneau');

      await tester.tap(
        find.descendant(of: name('east'), matching: find.text('Est')),
      );
      await tester.pumpAndSettle();
      expect(path(), 'Page > Centre > Explorateur > Ouest > Panneau > Est');

      // Un clic sur une zone du chemin selectionne sa disposition et sa zone.
      await tester.tap(segment('Est'));
      await tester.pumpAndSettle();
      expect(path(), 'Page > Centre > Explorateur > Ouest > Panneau > Est');
      expect(
        find.byKey(const ValueKey('super-layout-zone-selected-east')),
        findsOneWidget,
      );

      // Selectionner le contenu de l'autre layout change le chemin actif.
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('box-content'))) +
            const Offset(20, 100),
      );
      await tester.pumpAndSettle();
      expect(path(), 'Page > Centre > Explorateur');
      editMode.value = false;
      await tester.pumpAndSettle();
      expect(path(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(LayoutSelection.path.value, isEmpty);
    });

    testWidgets('a slot of a nested layout cannot leave its owner', (
      tester,
    ) async {
      final editMode = ValueNotifier(true);
      addTearDown(editMode.dispose);
      final outer = <SuperLayoutConfig>[];
      final inner = <SuperLayoutConfig>[];
      await tester.pumpWidget(
        StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: SuperLayout(
                  config: const SuperLayoutConfig(
                    north: false,
                    south: false,
                    east: false,
                    placements: {
                      SuperLayoutZone.west: ['side'],
                      SuperLayoutZone.center: ['main'],
                    },
                  ),
                  onChanged: outer.add,
                  slots: [
                    _slot('side'),
                    BuilderSlot(
                      id: 'main',
                      label: 'main',
                      labelAlignment: Alignment.topRight,
                      builder: (_) => SuperLayout(
                        config: const SuperLayoutConfig(
                          south: false,
                          west: false,
                          east: false,
                          autoSides: {SuperLayoutZone.north},
                          placements: {
                            SuperLayoutZone.north: ['bar'],
                            SuperLayoutZone.center: ['content'],
                          },
                        ),
                        onChanged: inner.add,
                        slots: [
                          _slot('bar', height: 40),
                          _slot('content', sizing: SlotSizing.fill),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('box-content'))) +
            const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('slot-label-bar'))),
      );
      await gesture.moveBy(const Offset(0, 25));
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('box-side'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(outer, isEmpty);
      expect(inner, isEmpty);
    });
  });
  group('slot labels in edit mode', () {
    const config = SuperLayoutConfig(
      south: false,
      west: false,
      east: false,
      autoSides: {SuperLayoutZone.north},
      placements: {
        SuperLayoutZone.north: ['bar', 'quiet'],
        SuperLayoutZone.center: ['content'],
      },
    );

    Future<ValueNotifier<bool>> pumpEditable(
      WidgetTester tester,
      List<SlotImplementation> slots,
    ) async {
      final editMode = ValueNotifier(false);
      addTearDown(editMode.dispose);
      await tester.pumpWidget(
        StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: SuperLayout(
                  config: config,
                  slots: slots,
                  showZoneNames: false,
                  editable: false,
                ),
              ),
            ),
          ),
        ),
      );
      return editMode;
    }

    testWidgets('labels show only in edit mode and move nothing', (
      tester,
    ) async {
      final editMode = await pumpEditable(tester, [
        _slot('bar', height: 30),
        _slot('quiet', height: 20),
        _slot('content', sizing: SlotSizing.fill),
      ]);
      final before = tester.getRect(find.byKey(const ValueKey('box-content')));
      expect(find.textContaining('bar'), findsNothing);

      editMode.value = true;
      await tester.pump();
      await tester.tapAt(const Offset(500, 200));
      await tester.pump();
      expect(find.text('bar · Nord 1/2'), findsOneWidget);
      expect(find.text('quiet · Nord 2/2'), findsOneWidget);
      expect(find.text('content · Centre 1/1'), findsOneWidget);
      final label = tester.getRect(
        find.byKey(const ValueKey('slot-label-bar')),
      );
      expect(label.topLeft, const Offset(4, 4));
      expect(tester.getRect(find.byKey(const ValueKey('box-content'))), before);

      editMode.value = false;
      await tester.pump();
      expect(find.textContaining('bar'), findsNothing);
    });

    testWidgets('a slot with showLabel false shows no label', (tester) async {
      final editMode = await pumpEditable(tester, [
        _slot('bar', height: 30),
        const BuilderSlot(
          id: 'quiet',
          label: 'quiet',
          showLabel: false,
          sizing: SlotSizing.intrinsic,
          builder: _quietBox,
        ),
        _slot('content', sizing: SlotSizing.fill),
      ]);
      editMode.value = true;
      await tester.pump();
      await tester.tapAt(const Offset(500, 200));
      await tester.pump();
      expect(find.text('bar · Nord 1/2'), findsOneWidget);
      expect(find.textContaining('quiet'), findsNothing);
    });

    testWidgets('every zone with a slot shows its name, containers included', (
      tester,
    ) async {
      final editMode = ValueNotifier(true);
      addTearDown(editMode.dispose);
      await tester.pumpWidget(
        StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: SuperLayout(
                  config: const SuperLayoutConfig(
                    south: false,
                    west: false,
                    east: false,
                    autoSides: {SuperLayoutZone.north},
                    placements: {
                      SuperLayoutZone.north: ['bar'],
                      SuperLayoutZone.center: ['container'],
                    },
                  ),
                  editable: false,
                  slots: [
                    _slot('bar', height: 30),
                    const BuilderSlot(
                      id: 'container',
                      label: 'container',
                      builder: _quietBox,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tapAt(const Offset(500, 200));
      await tester.pump();
      expect(find.text('Nord'), findsOneWidget);
      expect(find.text('Centre'), findsOneWidget);
      final badge = tester.getCenter(find.text('Nord'));
      expect(badge.dy, 15);
    });

    testWidgets('toggling edit mode keeps the state of the slots', (
      tester,
    ) async {
      var created = 0;
      final editMode = await pumpEditable(tester, [
        BuilderSlot(
          id: 'bar',
          label: 'bar',
          sizing: SlotSizing.intrinsic,
          builder: (_) => _Probe(onCreate: () => created++),
        ),
        _slot('content', sizing: SlotSizing.fill),
      ]);
      expect(created, 1);
      editMode.value = true;
      await tester.pump();
      editMode.value = false;
      await tester.pump();
      expect(created, 1);
    });
  });
}

Widget _quietBox(BuildContext context) => const SizedBox(height: 20);

class _Probe extends StatefulWidget {
  const _Probe({required this.onCreate});

  final VoidCallback onCreate;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 30);
}
