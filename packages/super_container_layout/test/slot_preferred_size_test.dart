import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  const base = SuperLayoutConfig(
    north: false,
    south: false,
    west: false,
    east: false,
    placements: {
      SuperLayoutZone.center: ['first', 'second'],
    },
  );

  BuilderSlot slot(String id, {Size? preferredSize, bool styled = false}) =>
      BuilderSlot(
        id: id,
        label: id,
        preferredSize: preferredSize,
        builder: (_) => styled
            ? SuperContainer(
                label: 'Style du slot',
                child: SizedBox.expand(key: ValueKey('content-$id')),
              )
            : SizedBox.expand(key: ValueKey('content-$id')),
      );

  Future<void> pump(
    WidgetTester tester, {
    SuperLayoutConfig config = base,
    ValueNotifier<bool>? editMode,
    ValueChanged<SuperLayoutConfig>? onChanged,
    bool editable = true,
    List<SlotImplementation>? slots,
  }) => tester.pumpWidget(
    MaterialApp(
      home: StyleEditScope(
        controller: editMode ?? ValueNotifier(false),
        child: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: SuperLayout(
              config: config,
              onChanged: onChanged,
              editable: editable,
              slots: slots ?? [slot('first'), slot('second')],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('content-first')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taille préférée : first'));
    await tester.pumpAndSettle();
  }

  test('preferred sizes survive copies, moves, swaps and JSON', () {
    final config = base.withSlotPreferredSize('first', const Size(240, 90));
    final restored = SuperLayoutConfig.fromJson(config.toJson());
    expect(restored, config);
    expect(restored.hashCode, config.hashCode);
    expect(restored.copyWith(), config);
    expect(
      restored
          .withSlotMoved('first', SuperLayoutZone.north)
          .withSwap(SuperLayoutZone.north)
          .slotPreferredSizes['first'],
      const Size(240, 90),
    );
    final automatic = config.withSlotPreferredSize('first', null);
    expect(automatic.slotPreferredSizes, {'first': null});
    expect(SuperLayoutConfig.fromJson(automatic.toJson()), automatic);
    expect(automatic, isNot(base.withSlotPreferredSize('second', null)));
    expect(SuperLayoutConfig.fromJson({}), const SuperLayoutConfig());
    expect(SuperLayoutConfig.fromJson({}, fallback: config), config);
    for (final size in [
      Size.zero,
      const Size(-1, 2),
      const Size(double.infinity, 1),
    ]) {
      expect(
        () => base.withSlotPreferredSize('first', size),
        throwsArgumentError,
      );
    }
    for (final sizes in [
      [],
      {
        'first': {'width': -1, 'height': 10},
      },
      {
        'first': {'width': 10},
      },
      {
        'first': {'width': double.nan, 'height': 10},
      },
      {
        '': {'width': 1, 'height': 1},
      },
    ]) {
      expect(
        () => SuperLayoutConfig.fromJson({'slotPreferredSizes': sizes}),
        throwsFormatException,
      );
    }
  });

  test('appearance snapshots sizes and registry forwards defaults', () {
    final sizes = {'first': const Size(120, 50)};
    final appearance = Appearance(
      layouts: {'layout': base.copyWith(slotPreferredSizes: sizes)},
    );
    sizes.clear();
    expect(
      appearance.layout('layout').slotPreferredSizes['first'],
      const Size(120, 50),
    );
    expect(
      () => appearance.layout('layout').slotPreferredSizes.clear(),
      throwsUnsupportedError,
    );
    final component = RegisteredComponent(
      label: 'first',
      preferredSize: const Size(120, 50),
      builder: (_) => const SizedBox(),
    );
    expect(component.createSlot('instance').preferredSize, const Size(120, 50));
  });

  testWidgets('preferred dimensions leave remaining height to fill slots', (
    tester,
  ) async {
    await pump(
      tester,
      config: base.withSlotPreferredSize('first', const Size(240, 90)),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(240, 90),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-second'))),
      const Size(600, 310),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('oversized preferences are bounded and shared proportionally', (
    tester,
  ) async {
    await pump(
      tester,
      config: base
          .withSlotPreferredSize('first', const Size(1000, 600))
          .withSlotPreferredSize('second', const Size(1000, 200)),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(600, 300),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-second'))),
      const Size(600, 100),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('default sizes are overridden per instance', (tester) async {
    await pump(
      tester,
      slots: [
        slot('first', preferredSize: const Size(120, 50)),
        slot('second'),
      ],
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(120, 50),
    );
    await pump(
      tester,
      config: base.withSlotPreferredSize('first', const Size(200, 70)),
      slots: [
        slot('first', preferredSize: const Size(120, 50)),
        slot('second'),
      ],
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(200, 70),
    );
  });

  testWidgets('preferred height respects space used by intrinsic siblings', (
    tester,
  ) async {
    await pump(
      tester,
      config: base.withSlotPreferredSize('first', const Size(240, 600)),
      slots: [
        slot('first'),
        BuilderSlot(
          id: 'second',
          label: 'second',
          sizing: SlotSizing.intrinsic,
          builder: (_) =>
              const SizedBox(key: ValueKey('content-second'), height: 50),
        ),
      ],
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(240, 350),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-second'))),
      const Size(600, 50),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic sides use preferred dimensions', (tester) async {
    for (final zone in [SuperLayoutZone.north, SuperLayoutZone.west]) {
      await pump(
        tester,
        config: base.copyWith(
          north: zone == SuperLayoutZone.north,
          west: zone == SuperLayoutZone.west,
          autoSides: {zone},
          placements: {
            zone: ['first'],
            SuperLayoutZone.center: ['second'],
          },
          slotPreferredSizes: {'first': const Size(150, 60)},
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('content-first'))),
        const Size(150, 60),
      );
      final content = tester.getRect(
        find.byKey(const ValueKey('content-second')),
      );
      expect(
        zone == SuperLayoutZone.north ? content.top : content.left,
        zone == SuperLayoutZone.north ? 60 : 150,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('automatic override ignores a declared preferred size', (
    tester,
  ) async {
    await pump(
      tester,
      config: base.withSlotPreferredSize('first', null),
      slots: [
        slot('first', preferredSize: const Size(120, 50)),
        slot('second'),
      ],
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(600, 200),
    );
  });

  testWidgets('changing sizing preserves child state', (tester) async {
    var created = 0;
    final slots = [
      BuilderSlot(
        id: 'first',
        label: 'first',
        builder: (_) => _StateProbe(onCreated: () => created++),
      ),
      slot('second'),
    ];
    await pump(tester, slots: slots);
    expect(created, 1);
    await pump(
      tester,
      slots: slots,
      config: base.withSlotPreferredSize('first', const Size(150, 60)),
    );
    expect(created, 1);
    await pump(tester, slots: slots);
    expect(created, 1);
  });

  testWidgets(
    'right click keeps styles and edits, validates, cancels and resets sizes',
    (tester) async {
      final editMode = ValueNotifier(true);
      addTearDown(editMode.dispose);
      SuperLayoutConfig? changed;
      await pump(
        tester,
        editMode: editMode,
        slots: [slot('first', styled: true), slot('second')],
        onChanged: (value) => changed = value,
      );
      await tester.tap(
        find.byKey(const ValueKey('content-first')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Style du slot'), findsOneWidget);
      expect(find.text('Super layout'), findsOneWidget);
      await tester.tap(find.text('Taille préférée : first'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-width')),
        '-1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-height')),
        '90',
      );
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Saisissez une dimension positive en pixels.'),
        findsOneWidget,
      );
      expect(changed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-width')),
        '240,5',
      );
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(changed!.slotPreferredSizes['first'], const Size(240.5, 90));
      expect(
        tester.getSize(find.byKey(const ValueKey('content-first'))),
        const Size(240.5, 90),
      );
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-width')),
        '300',
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(changed!.slotPreferredSizes['first'], const Size(240.5, 90));
      await openEditor(tester);
      await tester.tap(find.text('Taille automatique'));
      await tester.pumpAndSettle();
      expect(changed!.slotPreferredSizes, {'first': null});
      expect(
        tester.getSize(find.byKey(const ValueKey('content-first'))),
        const Size(600, 200),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'size editing is disabled outside edit mode or on readonly layouts',
    (tester) async {
      final editMode = ValueNotifier(false);
      addTearDown(editMode.dispose);
      await pump(tester, editMode: editMode);
      await tester.tap(
        find.byKey(const ValueKey('content-first')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Taille préférée : first'), findsNothing);
      editMode.value = true;
      await pump(tester, editMode: editMode, editable: false);
      await tester.tap(
        find.byKey(const ValueKey('content-first')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Taille préférée : first'), findsNothing);
    },
  );
}

class _StateProbe extends StatefulWidget {
  const _StateProbe({required this.onCreated});
  final VoidCallback onCreated;

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  void initState() {
    super.initState();
    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
