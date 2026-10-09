import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  const enabled = SuperLayoutConfig(resizeSides: true);
  final layoutKey = GlobalKey<SuperLayoutState>();

  Finder handle(SuperLayoutZone side) =>
      find.byKey(ValueKey('super-layout-resize-${side.name}'));

  Future<void> pump(
    WidgetTester tester, {
    SuperLayoutConfig config = enabled,
    bool editable = true,
    List<SlotImplementation> slots = const [],
    ValueChanged<SuperLayoutConfig>? onChanged,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 600,
          height: 400,
          child: SuperLayout(
            key: layoutKey,
            config: config,
            editable: editable,
            slots: slots,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );

  test('resize option survives JSON, copies and swaps', () {
    final restored = SuperLayoutConfig.fromJson(enabled.toJson());
    expect(restored, enabled);
    expect(restored.hashCode, enabled.hashCode);
    expect(restored.copyWith().resizeSides, isTrue);
    expect(restored.withSwap(SuperLayoutZone.north).resizeSides, isTrue);
    expect(
      SuperLayoutConfig.fromJson({}, fallback: enabled).resizeSides,
      isTrue,
    );
    expect(SuperLayoutConfig.fromJson({}).resizeSides, isFalse);
    expect(enabled, isNot(const SuperLayoutConfig()));
    expect(
      () => SuperLayoutConfig.fromJson({'resizeSides': 'yes'}),
      throwsFormatException,
    );
    for (final value in [0.0, 401.0, double.nan]) {
      expect(
        () => enabled.withSize(SuperLayoutZone.north, value),
        throwsArgumentError,
      );
    }
    expect(
      () => enabled.withSize(SuperLayoutZone.center, 100),
      throwsArgumentError,
    );
  });

  test(
    'per-side activation overrides the legacy setting and survives JSON',
    () {
      final config = enabled
          .withSideResizing(SuperLayoutZone.north, false)
          .withSideResizing(SuperLayoutZone.east, false);
      expect(config.canResize(SuperLayoutZone.north), isFalse);
      expect(config.canResize(SuperLayoutZone.south), isTrue);
      expect(config.canResize(SuperLayoutZone.center), isFalse);
      final restored = SuperLayoutConfig.fromJson(config.toJson());
      expect(restored, config);
      expect(restored.hashCode, config.hashCode);
      expect(restored.copyWith().sideResizing, config.sideResizing);
      expect(SuperLayoutConfig.fromJson({}, fallback: config), config);
      for (final raw in [
        {'center': true},
        {'north': 'yes'},
        [],
      ]) {
        expect(
          () => SuperLayoutConfig.fromJson({'sideResizing': raw}),
          throwsFormatException,
        );
      }
    },
  );

  test('resize bounds combine min/max along the stacking axis', () {
    final config = enabled.copyWith(
      slotSizeConstraints: {
        'first': const SlotSizeConstraints(
          minHeight: SlotDimension(40, SlotSizeUnit.pixels),
          maxHeight: SlotDimension(90, SlotSizeUnit.pixels),
        ),
        'second': const SlotSizeConstraints(
          minHeight: SlotDimension(60, SlotSizeUnit.pixels),
          maxHeight: SlotDimension(110, SlotSizeUnit.pixels),
        ),
      },
    );
    expect(
      config.resizeBounds(SuperLayoutZone.north, ['first', 'second'], 400),
      (min: 100.0, max: 200.0),
    );
    expect(
      config.withAxis(SuperLayoutZone.north, Axis.horizontal).resizeBounds(
        SuperLayoutZone.north,
        ['first', 'second'],
        400,
      ),
      (min: 60.0, max: 90.0),
    );
    expect(
      config.resizeBounds(SuperLayoutZone.north, ['first', 'unbounded'], 400),
      (min: 40.0, max: 400.0),
    );
  });

  test('percentage bounds resolve against candidate zone or whole layout', () {
    final config = enabled.copyWith(
      slotSizeConstraints: {
        'percent': const SlotSizeConstraints(
          minHeight: SlotDimension(50, SlotSizeUnit.percent),
          maxHeight: SlotDimension(50, SlotSizeUnit.percent),
        ),
        'pixels': const SlotSizeConstraints(
          minHeight: SlotDimension(50, SlotSizeUnit.pixels),
          maxHeight: SlotDimension(100, SlotSizeUnit.pixels),
        ),
      },
    );
    expect(
      config.resizeBounds(SuperLayoutZone.north, ['percent', 'pixels'], 400),
      (min: 100.0, max: 200.0),
    );
    expect(
      config
          .copyWith(
            slotSizeConstraints: {
              'percent': const SlotSizeConstraints(
                minHeight: SlotDimension(25, SlotSizeUnit.percent),
                maxHeight: SlotDimension(50, SlotSizeUnit.percent),
                percentBasis: SlotPercentBasis.layout,
              ),
            },
          )
          .resizeBounds(SuperLayoutZone.north, ['percent'], 400),
      (min: 100.0, max: 200.0),
    );
  });

  test('east/west bounds sum widths in Row and intersect widths in Column', () {
    final config = enabled.copyWith(
      slotSizeConstraints: {
        'first': const SlotSizeConstraints(
          minWidth: SlotDimension(70, SlotSizeUnit.pixels),
          maxWidth: SlotDimension(150, SlotSizeUnit.pixels),
        ),
        'second': const SlotSizeConstraints(
          minWidth: SlotDimension(90, SlotSizeUnit.pixels),
          maxWidth: SlotDimension(180, SlotSizeUnit.pixels),
        ),
      },
    );
    expect(
      config.resizeBounds(SuperLayoutZone.east, ['first', 'second'], 600),
      (min: 90.0, max: 150.0),
    );
    expect(
      config.withAxis(SuperLayoutZone.east, Axis.horizontal).resizeBounds(
        SuperLayoutZone.east,
        ['first', 'second'],
        600,
      ),
      (min: 160.0, max: 330.0),
    );
  });

  testWidgets('swapped zones use bounds of the content actually displayed', (
    tester,
  ) async {
    await pump(
      tester,
      config: enabled
          .copyWith(
            placements: {
              SuperLayoutZone.south: ['component'],
            },
            slotSizeConstraints: {
              'component': const SlotSizeConstraints(
                maxHeight: SlotDimension(25, SlotSizeUnit.percent),
                percentBasis: SlotPercentBasis.layout,
              ),
            },
          )
          .withSwap(SuperLayoutZone.north),
      slots: [
        BuilderSlot(
          id: 'component',
          label: 'Component',
          builder: (_) => const SizedBox(),
        ),
      ],
    );
    await tester.drag(handle(SuperLayoutZone.north), const Offset(0, 600));
    await tester.pump();
    expect(layoutKey.currentState!.config.northSize, 100);
  });

  testWidgets('incompatible component limits do not change the zone size', (
    tester,
  ) async {
    await pump(
      tester,
      config: enabled.copyWith(
        placements: {
          SuperLayoutZone.north: ['component'],
        },
        slotSizeConstraints: {
          'component': const SlotSizeConstraints(
            minHeight: SlotDimension(150, SlotSizeUnit.pixels),
            maxHeight: SlotDimension(100, SlotSizeUnit.pixels),
          ),
        },
      ),
      slots: [
        BuilderSlot(
          id: 'component',
          label: 'Component',
          builder: (_) => const SizedBox(),
        ),
      ],
    );
    await tester.drag(handle(SuperLayoutZone.north), const Offset(0, 100));
    await tester.pump();
    expect(layoutKey.currentState!.config.northSize, 80);
    expect(tester.takeException(), isNull);
  });

  testWidgets('individual activation creates only the selected side handle', (
    tester,
  ) async {
    await pump(
      tester,
      config: const SuperLayoutConfig().withSideResizing(
        SuperLayoutZone.south,
        true,
      ),
    );
    expect(handle(SuperLayoutZone.south), findsOneWidget);
    for (final side in [
      SuperLayoutZone.north,
      SuperLayoutZone.west,
      SuperLayoutZone.east,
    ]) {
      expect(handle(side), findsNothing);
    }
  });

  testWidgets(
    'drag respects visible component bounds and ignores hidden slots',
    (tester) async {
      await pump(
        tester,
        config: enabled.copyWith(
          placements: {
            SuperLayoutZone.north: ['first', 'second', 'hidden'],
          },
          slotSizeConstraints: {
            'first': const SlotSizeConstraints(
              minHeight: SlotDimension(40, SlotSizeUnit.pixels),
              maxHeight: SlotDimension(90, SlotSizeUnit.pixels),
            ),
            'second': const SlotSizeConstraints(
              minHeight: SlotDimension(60, SlotSizeUnit.pixels),
              maxHeight: SlotDimension(110, SlotSizeUnit.pixels),
            ),
            'hidden': const SlotSizeConstraints(
              minHeight: SlotDimension(300, SlotSizeUnit.pixels),
            ),
          },
        ),
        slots: [
          for (final id in ['first', 'second', 'hidden'])
            BuilderSlot(
              id: id,
              label: id,
              visible: id != 'hidden',
              builder: (_) => const SizedBox(),
            ),
        ],
      );
      await tester.drag(handle(SuperLayoutZone.north), const Offset(0, 600));
      await tester.pump();
      expect(layoutKey.currentState!.config.northSize, 200);
      await tester.drag(handle(SuperLayoutZone.north), const Offset(0, -600));
      await tester.pump();
      expect(layoutKey.currentState!.config.northSize, 100);
    },
  );

  for (final (side, delta, expected) in [
    (SuperLayoutZone.north, const Offset(0, 40), 120.0),
    (SuperLayoutZone.south, const Offset(0, -40), 120.0),
    (SuperLayoutZone.west, const Offset(40, 0), 160.0),
    (SuperLayoutZone.east, const Offset(-40, 0), 160.0),
  ]) {
    testWidgets('${side.name} resizes outside edit mode through a 5 px edge', (
      tester,
    ) async {
      final changes = <SuperLayoutConfig>[];
      await pump(tester, onChanged: changes.add);
      final size = tester.getSize(handle(side));
      if (side == SuperLayoutZone.north || side == SuperLayoutZone.south) {
        expect(size.height, 5);
        expect(size.width, 360);
      } else {
        expect(size.width, 5);
        expect(size.height, 240);
      }
      await tester.drag(handle(side), delta);
      await tester.pump();
      expect(layoutKey.currentState!.config.sizeOf(side), expected);
      expect(changes.last.sizeOf(side), expected);
      final zone = find.byKey(ValueKey('super-layout-${side.name}'));
      final zoneSize = tester.getSize(zone);
      expect(
        side == SuperLayoutZone.north || side == SuperLayoutZone.south
            ? zoneSize.height
            : zoneSize.width,
        expected,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabled, absent and readonly sides have no handles', (
    tester,
  ) async {
    await pump(tester, config: const SuperLayoutConfig());
    for (final side in SuperLayoutZone.values) {
      expect(handle(side), findsNothing);
    }
    await pump(tester, config: enabled.copyWith(north: false));
    expect(handle(SuperLayoutZone.north), findsNothing);
    expect(handle(SuperLayoutZone.west), findsOneWidget);
    expect(handle(SuperLayoutZone.center), findsNothing);
    expect(handle(SuperLayoutZone.nw), findsNothing);
    await pump(tester, editable: false);
    expect(handle(SuperLayoutZone.west), findsNothing);
  });

  testWidgets('dragging an automatic side starts from its measured size', (
    tester,
  ) async {
    await pump(
      tester,
      config: enabled.copyWith(
        autoSides: {SuperLayoutZone.north},
        placements: {
          SuperLayoutZone.north: ['toolbar'],
        },
      ),
      slots: [
        BuilderSlot(
          id: 'toolbar',
          label: 'Toolbar',
          sizing: SlotSizing.intrinsic,
          builder: (_) => const SizedBox(height: 50),
        ),
      ],
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('super-layout-north'))).height,
      50,
    );
    await tester.drag(handle(SuperLayoutZone.north), const Offset(0, 40));
    await tester.pump();
    expect(layoutKey.currentState!.config.northSize, 90);
    expect(
      layoutKey.currentState!.config.isAuto(SuperLayoutZone.north),
      isFalse,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('super-layout-north'))).height,
      90,
    );
  });

  testWidgets('drag sizes are bounded and preserve space for the center', (
    tester,
  ) async {
    await pump(tester);
    await tester.drag(handle(SuperLayoutZone.north), const Offset(0, 600));
    await tester.pump();
    expect(layoutKey.currentState!.config.northSize, 300);
    expect(
      tester.getSize(find.byKey(const ValueKey('super-layout-center'))).height,
      20,
    );
    await tester.drag(handle(SuperLayoutZone.north), const Offset(0, -600));
    await tester.pump();
    expect(layoutKey.currentState!.config.northSize, 20);
    await tester.drag(handle(SuperLayoutZone.west), const Offset(600, 0));
    await tester.pump();
    expect(layoutKey.currentState!.config.westSize, 400);
    expect(
      SuperLayoutConfig.fromJson(layoutKey.currentState!.config.toJson()),
      layoutKey.currentState!.config,
    );
  });

  testWidgets('continuous dragging stays stable as the edge moves', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(handle(SuperLayoutZone.east)),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(layoutKey.currentState!.config.eastSize, 150);
    await gesture.moveBy(const Offset(-25, 0));
    await tester.pump();
    expect(layoutKey.currentState!.config.eastSize, 175);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(layoutKey.currentState!.config.eastSize, 155);
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('resize overlays do not consume taps in zone content', (
    tester,
  ) async {
    var taps = 0;
    await pump(
      tester,
      config: enabled.copyWith(
        placements: {
          SuperLayoutZone.west: ['button'],
        },
      ),
      slots: [
        BuilderSlot(
          id: 'button',
          label: 'Button',
          builder: (_) => Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Click'),
            ),
          ),
        ),
      ],
    );
    await tester.tap(find.text('Click'));
    expect(taps, 1);
    expect(
      layoutKey.currentState!.config,
      enabled.copyWith(
        placements: {
          SuperLayoutZone.west: ['button'],
        },
      ),
    );
  });

  testWidgets('editor can enable and reset resizing', (tester) async {
    var config = const SuperLayoutConfig();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => SuperLayoutEditor(
                config: config,
                onChanged: (value) => setState(() => config = value),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('super-layout-resize-sides')));
    await tester.pump();
    expect(config.resizeSides, isTrue);
    final northSwitch = find.byKey(
      const ValueKey('super-layout-resize-side-north'),
    );
    await tester.ensureVisible(northSwitch);
    await tester.tap(northSwitch);
    await tester.pump();
    expect(config.canResize(SuperLayoutZone.north), isFalse);
    expect(config.canResize(SuperLayoutZone.south), isTrue);
    await tester.ensureVisible(find.text('Réinitialiser'));
    await tester.tap(find.text('Réinitialiser'));
    await tester.pump();
    expect(config.resizeSides, isFalse);
    expect(config.sideResizing, isEmpty);
  });
}
