import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

Widget _content(BuildContext context) => const SizedBox.expand();

const _slots = [
  BuilderSlot(
    id: 'allowed',
    label: 'Allowed',
    tags: {'allowed'},
    builder: _content,
  ),
  BuilderSlot(
    id: 'new',
    label: 'New',
    tags: {'allowed', 'other'},
    builder: _content,
  ),
  BuilderSlot(id: 'bad', label: 'Bad', builder: _content),
  BuilderSlot(
    id: 'blocked',
    label: 'Blocked',
    tags: {'allowed', 'blocked'},
    builder: _content,
  ),
];

const _config = SuperLayoutConfig(
  north: true,
  south: true,
  west: false,
  east: false,
  northSize: 80,
  southSize: 80,
  autoSides: {},
  placements: {
    SuperLayoutZone.north: ['allowed'],
    SuperLayoutZone.center: ['bad'],
  },
);

void main() {
  Future<List<SuperLayoutConfig>> pumpLayout(
    WidgetTester tester, {
    SuperLayoutConfig config = _config,
    Map<SuperLayoutZone, ComponentTagFilter> filters = const {
      SuperLayoutZone.north: ComponentTagFilter(
        include: {'allowed'},
        exclude: {'blocked'},
      ),
    },
    SlotAddedCallback onSlotAdded = SuperLayout.defaultSlotAddition,
  }) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    final changes = <SuperLayoutConfig>[];
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: Scaffold(
            body: SuperLayout(
              label: 'Test layout',
              slots: _slots,
              config: config,
              zoneTagFilters: filters,
              onSlotAdded: onSlotAdded,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(600, 300));
    await tester.pumpAndSettle();
    return changes;
  }

  SlotStack stackOf(WidgetTester tester, String id) => tester
      .widgetList<SlotStack>(find.byType(SlotStack))
      .where((stack) => stack.slots.any((slot) => slot.id == id))
      .single;

  SlotDragData dragData(WidgetTester tester, String id) {
    final hint = ValueNotifier<SlotDropHint?>(null);
    addTearDown(hint.dispose);
    return SlotDragData(
      id: id,
      owner: tester.state<SuperLayoutState>(find.byType(SuperLayout)),
      hint: hint,
    );
  }

  testWidgets('layout catalog filters by receiving zone', (tester) async {
    final changes = await pumpLayout(tester);
    await tester.tap(find.byKey(const ValueKey('super-layout-add-north')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('super-layout-add-slot-new')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('super-layout-add-slot-bad')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('super-layout-add-slot-blocked')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('super-layout-add-slot-new')));
    await tester.pumpAndSettle();
    expect(changes.single.placementsOf(SuperLayoutZone.north), [
      'allowed',
      'new',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slot and free-zone drop targets reject incompatible entries', (
    tester,
  ) async {
    final changes = await pumpLayout(tester);
    final mover = stackOf(tester, 'allowed').mover!;
    expect(mover.canMove!('bad'), isFalse);
    expect(mover.canMove!('new'), isTrue);
    final target = tester.widget<DragTarget<SlotDragData>>(
      find.descendant(
        of: find.byKey(const ValueKey('super-layout-slot-drop-north')),
        matching: find.byType(DragTarget<SlotDragData>),
      ),
    );
    final details = DragTargetDetails(
      data: dragData(tester, 'bad'),
      offset: Offset.zero,
    );
    expect(target.onWillAcceptWithDetails!(details), isFalse);
    expect(details.data.hint.value, isNull);
    final slotTargets = tester.widgetList<DragTarget<SlotDragData>>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is SlotStack &&
              widget.slots.any((slot) => slot.id == 'allowed'),
        ),
        matching: find.byType(DragTarget<SlotDragData>),
      ),
    );
    expect(slotTargets, isNotEmpty);
    expect(slotTargets.first.onWillAcceptWithDetails!(details), isFalse);
    mover.onMove('bad');
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(
      find.text('Composant incompatible avec la zone Nord.'),
      findsOneWidget,
    );
    mover.onMove('new', beforeId: 'allowed');
    await tester.pumpAndSettle();
    expect(changes.single.placementsOf(SuperLayoutZone.north), [
      'new',
      'allowed',
    ]);
  });

  testWidgets('legacy entries can reorder, resize, leave and be removed', (
    tester,
  ) async {
    final changes = await pumpLayout(
      tester,
      config: _config.copyWith(
        placements: {
          SuperLayoutZone.north: ['bad', 'allowed'],
        },
      ),
    );
    expect(find.byKey(const ValueKey('slot-bad')), findsOneWidget);
    final mover = stackOf(tester, 'bad').mover!;
    expect(mover.canMove!('bad'), isTrue);
    mover.onMove('bad', afterId: 'allowed');
    await tester.pumpAndSettle();
    expect(changes.last.placementsOf(SuperLayoutZone.north), [
      'allowed',
      'bad',
    ]);
    final stack = stackOf(tester, 'bad');
    stack.onResizeSlot!(
      stack.slots.firstWhere((slot) => slot.id == 'bad'),
      const SlotSizeConstraints(
        preferredHeight: SlotDimension(35, SlotSizeUnit.pixels),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      changes.last.slotSizeConstraints['bad']!.preferredHeight,
      const SlotDimension(35, SlotSizeUnit.pixels),
    );
    final center = tester.widget<DragTarget<SlotDragData>>(
      find.descendant(
        of: find.byKey(const ValueKey('super-layout-slot-drop-center')),
        matching: find.byType(DragTarget<SlotDragData>),
      ),
    );
    center.onAcceptWithDetails!(
      DragTargetDetails(data: dragData(tester, 'bad'), offset: Offset.zero),
    );
    await tester.pumpAndSettle();
    expect(changes.last.placementsOf(SuperLayoutZone.center), ['bad']);
    expect(stackOf(tester, 'allowed').mover!.canMove!('bad'), isFalse);
    await stackOf(tester, 'bad').onRemoveSlot!(
      stackOf(tester, 'bad').slots.firstWhere((slot) => slot.id == 'bad'),
    );
    await tester.pumpAndSettle();
    expect(changes.last.placedSlotIds, isNot(contains('bad')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('swaps cannot introduce incompatible placements in either side', (
    tester,
  ) async {
    final changes = await pumpLayout(
      tester,
      config: _config.copyWith(
        placements: {
          SuperLayoutZone.north: ['allowed'],
          SuperLayoutZone.south: ['bad'],
        },
      ),
    );
    final swap = tester.widget<DragTarget<SuperLayoutZone>>(
      find.byType(DragTarget<SuperLayoutZone>),
    );
    expect(
      swap.onWillAcceptWithDetails!(
        DragTargetDetails(data: SuperLayoutZone.north, offset: Offset.zero),
      ),
      isFalse,
    );
    expect(changes, isEmpty);
  });

  testWidgets('swapped content is filtered at its displayed destination', (
    tester,
  ) async {
    final swapped = _config.withSwap(SuperLayoutZone.north);
    final changes = await pumpLayout(tester, config: swapped);
    await tester.tap(find.byKey(const ValueKey('super-layout-add-north')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('super-layout-add-slot-bad')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('super-layout-add-slot-new')));
    await tester.pumpAndSettle();
    expect(changes.last.placementsOf(SuperLayoutZone.south), ['new']);
  });

  testWidgets('addition callbacks cannot bypass tag validation', (
    tester,
  ) async {
    final changes = await pumpLayout(
      tester,
      onSlotAdded: (addition) => addition.config.withSlotMoved(
        addition.slotId,
        addition.contentZone,
        type: 'bad',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('super-layout-add-north')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-layout-add-slot-new')));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(
      find.text('Composant incompatible avec la zone Nord.'),
      findsOneWidget,
    );
  });

  testWidgets('grid uses the center filter for new additions', (tester) async {
    final changes = await pumpLayout(
      tester,
      config: _config.withPositioning(SuperLayoutPositioning.grid),
      filters: const {
        SuperLayoutZone.center: ComponentTagFilter(include: {'allowed'}),
      },
    );
    await tester.tapAt(const Offset(500, 300), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-menu-add-Test layout')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('super-layout-add-slot-bad')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('super-layout-add-slot-new')));
    await tester.pumpAndSettle();
    expect(changes.last.placementsOf(SuperLayoutZone.center), ['bad', 'new']);
    expect(tester.takeException(), isNull);
  });
}
