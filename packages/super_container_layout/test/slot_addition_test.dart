import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

Widget _content(BuildContext context) => const SizedBox.expand();

const _first = BuilderSlot(id: 'first', label: 'First', builder: _content);
const _second = BuilderSlot(id: 'second', label: 'Second', builder: _content);

void main() {
  for (final zone in [
    SuperLayoutZone.north,
    SuperLayoutZone.south,
    SuperLayoutZone.west,
    SuperLayoutZone.east,
  ]) {
    test('default addition sizes ${zone.name} on its side axis', () {
      final config = const SuperLayoutConfig().withSlotMoved('second', zone);
      final result = SuperLayout.defaultSlotAddition(
        SlotAddition(
          slotId: 'second',
          component: _second,
          zone: zone,
          contentZone: zone,
          config: config,
          existingSlots: const [],
        ),
      );
      final constraints = result.slotSizeConstraints['second']!;
      final width =
          zone == SuperLayoutZone.west || zone == SuperLayoutZone.east;
      expect(
        width ? constraints.preferredWidth : constraints.preferredHeight,
        const SlotDimension(20, SlotSizeUnit.percent),
      );
      expect(constraints.percentBasis, SlotPercentBasis.layout);
      expect(
        width ? constraints.preferredHeight : constraints.preferredWidth,
        isNull,
      );
      expect(SuperLayoutConfig.fromJson(result.toJson()), result);
    });
  }

  test('first sibling preference wins and preserves bounds and other axis', () {
    final config = const SuperLayoutConfig(
      placements: {
        SuperLayoutZone.east: ['first', 'second'],
      },
      slotSizeConstraints: {
        'first': SlotSizeConstraints(
          preferredWidth: SlotDimension(275, SlotSizeUnit.pixels),
        ),
        'second': SlotSizeConstraints(
          minWidth: SlotDimension(100, SlotSizeUnit.pixels),
          maxWidth: SlotDimension(400, SlotSizeUnit.pixels),
          preferredHeight: SlotDimension(80, SlotSizeUnit.pixels),
        ),
      },
    );
    final result = SuperLayout.defaultSlotAddition(
      SlotAddition(
        slotId: 'second',
        component: _second,
        zone: SuperLayoutZone.east,
        contentZone: SuperLayoutZone.east,
        config: config,
        existingSlots: const [_first],
      ),
    );
    expect(
      result.slotSizeConstraints['second'],
      const SlotSizeConstraints(
        minWidth: SlotDimension(100, SlotSizeUnit.pixels),
        maxWidth: SlotDimension(400, SlotSizeUnit.pixels),
        preferredWidth: SlotDimension(275, SlotSizeUnit.pixels),
        preferredHeight: SlotDimension(80, SlotSizeUnit.pixels),
      ),
    );
  });

  test('legacy and declared sibling sizes are reused', () {
    for (final legacy in [true, false]) {
      final first = BuilderSlot(
        id: 'first',
        label: 'First',
        builder: _content,
        preferredSize: legacy ? null : const Size(130, 250),
      );
      final config = SuperLayoutConfig(
        slotPreferredSizes: {if (legacy) 'first': const Size(130, 250)},
      ).withSlotMoved('second', SuperLayoutZone.north);
      final result = SuperLayout.defaultSlotAddition(
        SlotAddition(
          slotId: 'second',
          component: _second,
          zone: SuperLayoutZone.north,
          contentZone: SuperLayoutZone.north,
          config: config,
          existingSlots: [first],
        ),
      );
      expect(
        result.slotSizeConstraints['second']?.preferredHeight,
        const SlotDimension(250, SlotSizeUnit.pixels),
      );
    }
  });

  test('percent preferences keep their source basis', () {
    const config = SuperLayoutConfig(
      slotSizeConstraints: {
        'first': SlotSizeConstraints(
          preferredWidth: SlotDimension(30, SlotSizeUnit.percent),
          percentBasis: SlotPercentBasis.layout,
        ),
      },
    );
    final result = SuperLayout.defaultSlotAddition(
      const SlotAddition(
        slotId: 'second',
        component: _second,
        zone: SuperLayoutZone.east,
        contentZone: SuperLayoutZone.east,
        config: config,
        existingSlots: [_first],
      ),
    );
    expect(
      result.slotSizeConstraints['second'],
      const SlotSizeConstraints(
        preferredWidth: SlotDimension(30, SlotSizeUnit.percent),
        percentBasis: SlotPercentBasis.layout,
      ),
    );
  });

  test('center and corners do not receive an automatic preferred size', () {
    for (final zone in [SuperLayoutZone.center, SuperLayoutZone.nw]) {
      const config = SuperLayoutConfig();
      expect(
        SuperLayout.defaultSlotAddition(
          SlotAddition(
            slotId: 'second',
            component: _second,
            zone: zone,
            contentZone: zone,
            config: config,
            existingSlots: const [],
          ),
        ),
        same(config),
      );
    }
  });

  test('fallback uses whole-layout basis when sibling bases are incompatible', () {
    const config = SuperLayoutConfig(
      slotSizeConstraints: {
        'first': SlotSizeConstraints(
          preferredWidth: SlotDimension(30, SlotSizeUnit.percent),
          percentBasis: SlotPercentBasis.layout,
        ),
        'second': SlotSizeConstraints(
          minHeight: SlotDimension(10, SlotSizeUnit.percent),
        ),
      },
    );
    final result = SuperLayout.defaultSlotAddition(
      const SlotAddition(
        slotId: 'second',
        component: _second,
        zone: SuperLayoutZone.east,
        contentZone: SuperLayoutZone.east,
        config: config,
        existingSlots: [_first],
      ),
    );
    expect(
      result.slotSizeConstraints['second'],
      const SlotSizeConstraints(
        preferredWidth: SlotDimension(20, SlotSizeUnit.percent),
        minHeight: SlotDimension(10, SlotSizeUnit.percent),
        percentBasis: SlotPercentBasis.layout,
      ),
    );
  });

  Future<void> pumpLayout(
    WidgetTester tester,
    ValueNotifier<bool> mode, {
    required ValueChanged<SuperLayoutConfig> onChanged,
    SlotAddedCallback onSlotAdded = SuperLayout.defaultSlotAddition,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: Scaffold(
            body: SuperLayout(
              onChanged: onChanged,
              onSlotAdded: onSlotAdded,
              slots: const [_first, _second],
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
  }

  Future<void> add(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(const ValueKey('super-layout-add-east')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('super-layout-add-slot-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('cancelled additions do not call the callback or change config', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    var calls = 0;
    final changes = <SuperLayoutConfig>[];
    await pumpLayout(
      tester,
      mode,
      onChanged: changes.add,
      onSlotAdded: (addition) {
        calls++;
        return addition.config;
      },
    );
    await tester.tap(find.byKey(const ValueKey('super-layout-add-east')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(changes, isEmpty);
  });

  testWidgets('editor additions commit preferred size with placement once', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    final changes = <SuperLayoutConfig>[];
    await pumpLayout(tester, mode, onChanged: changes.add);
    await add(tester, 'first');
    expect(changes, hasLength(1));
    expect(changes.single.placementsOf(SuperLayoutZone.east), ['first']);
    expect(
      changes.single.slotSizeConstraints['first']?.preferredWidth,
      const SlotDimension(20, SlotSizeUnit.percent),
    );
    expect(changes.single.slotSizeConstraints['first']?.percentBasis,
        SlotPercentBasis.layout);
    expect(tester.getSize(find.byKey(const ValueKey('slot-first'))).width, 160);
  });

  testWidgets(
    'callback sees added instance and siblings and can override sizing',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      final calls = <SlotAddition>[];
      final changes = <SuperLayoutConfig>[];
      await pumpLayout(
        tester,
        mode,
        onChanged: changes.add,
        onSlotAdded: (addition) {
          calls.add(addition);
          return addition.config.copyWith(
            slotSizeConstraints: {
              ...addition.config.slotSizeConstraints,
              addition.slotId: const SlotSizeConstraints(
                preferredWidth: SlotDimension(260, SlotSizeUnit.pixels),
              ),
            },
          );
        },
      );
      await add(tester, 'first');
      LayoutSelection.select(['Super layout', SuperLayoutZone.east.label]);
      await tester.pumpAndSettle();
      // The occupied zone exposes its add action in the context menu.
      await tester.tapAt(const Offset(790, 500), buttons: 2);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('style-menu-add-Super layout')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('super-layout-add-slot-second')),
      );
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
      expect(calls.last.slotId, 'second');
      expect(calls.last.zone, SuperLayoutZone.east);
      expect(calls.last.contentZone, SuperLayoutZone.east);
      expect(calls.last.existingSlots.map((slot) => slot.id), ['first']);
      expect(calls.last.config.placementsOf(SuperLayoutZone.east), [
        'first',
        'second',
      ]);
      expect(changes, hasLength(2));
      expect(
        changes.last.slotSizeConstraints['second']?.preferredWidth,
        const SlotDimension(260, SlotSizeUnit.pixels),
      );
    },
  );
}
