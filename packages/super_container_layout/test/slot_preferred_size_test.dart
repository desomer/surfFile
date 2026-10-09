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
  }) async {
    await tester.pumpWidget(
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
    if (editMode?.value ?? false) {
      await tester.tapAt(
        tester.getTopLeft(find.byType(SuperLayout)) + const Offset(10, 10),
      );
      await tester.pumpAndSettle();
    }
  }

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

  test('slot size constraints serialize pixel and percentage dimensions', () {
    final config = base.copyWith(
      slotSizeConstraints: {
        'first': const SlotSizeConstraints(
          minWidth: SlotDimension(25, SlotSizeUnit.percent),
          minHeight: SlotDimension(80, SlotSizeUnit.pixels),
          maxWidth: SlotDimension(500, SlotSizeUnit.pixels),
          maxHeight: SlotDimension(75, SlotSizeUnit.percent),
          preferredWidth: SlotDimension(240, SlotSizeUnit.pixels),
          preferredHeight: SlotDimension(50, SlotSizeUnit.percent),
          percentBasis: SlotPercentBasis.layout,
        ),
      },
    );
    expect(SuperLayoutConfig.fromJson(config.toJson()), config);
    expect(config.copyWith(), config);
    expect(config.withoutSlot('first').slotSizeConstraints, isEmpty);
    expect(
      () => SuperLayoutConfig.fromJson({
        'slotSizeConstraints': {
          'first': {
            'preferredWidth': {'value': -1, 'unit': 'px'},
          },
        },
      }),
      throwsFormatException,
    );
  });

  testWidgets('slot percentage sizes and limits use the available zone', (
    tester,
  ) async {
    final config = base.copyWith(
      slotSizeConstraints: {
        'first': const SlotSizeConstraints(
          minWidth: SlotDimension(50, SlotSizeUnit.percent),
          minHeight: SlotDimension(120, SlotSizeUnit.pixels),
          maxWidth: SlotDimension(350, SlotSizeUnit.pixels),
          maxHeight: SlotDimension(50, SlotSizeUnit.percent),
          preferredWidth: SlotDimension(40, SlotSizeUnit.percent),
          preferredHeight: SlotDimension(25, SlotSizeUnit.percent),
        ),
      },
    );
    await pump(tester, config: config, slots: [slot('first')]);
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(300, 120),
    );
  });

  testWidgets('slot size editor stores percentage preferences', (tester) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    SuperLayoutConfig? changed;
    await pump(
      tester,
      config: base.copyWith(north: true),
      editMode: mode,
      onChanged: (value) => changed = value,
    );
    await openEditor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('slot-preferred-width')),
      '40',
    );
    await tester.enterText(
      find.byKey(const ValueKey('slot-preferred-height')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('slot-unit-preferred-width')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slot-unit-preferred-height')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slot-percent-basis')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tout le SuperLayout').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(
      changed!.slotSizeConstraints['first'],
      const SlotSizeConstraints(
        preferredWidth: SlotDimension(40, SlotSizeUnit.percent),
        preferredHeight: SlotDimension(25, SlotSizeUnit.percent),
        percentBasis: SlotPercentBasis.layout,
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(240, 100),
    );
  });

  test('removing a slot cleans only its instance configuration', () {
    final config = base
        .copyWith(
          placements: {
            SuperLayoutZone.center: ['first', 'second'],
            SuperLayoutZone.north: ['first'],
          },
          slotTypes: {'first': 'component', 'second': 'component'},
          slotPreferredSizes: {
            'first': const Size(100, 50),
            'second': const Size(200, 70),
          },
        )
        .withAxis(SuperLayoutZone.center, Axis.horizontal);
    final removed = config.withoutSlot('first');
    expect(removed.placements, {
      SuperLayoutZone.center: ['second'],
    });
    expect(removed.slotTypes, {'second': 'component'});
    expect(removed.slotPreferredSizes, {'second': const Size(200, 70)});
    expect(removed.axisOf(SuperLayoutZone.center), Axis.horizontal);
    expect(config.placementsOf(SuperLayoutZone.north), ['first']);
    expect(SuperLayoutConfig.fromJson(removed.toJson()), removed);
    expect(removed.withoutSlot('second').placements, isEmpty);
  });

  testWidgets('preferred size menu removes a slot and allows adding it again', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    final changes = <SuperLayoutConfig>[];
    await pump(
      tester,
      editMode: mode,
      config: base.withSlotPreferredSize('first', const Size(120, 90)),
      slots: [slot('first', styled: true), slot('second')],
      onChanged: changes.add,
    );
    await tester.tap(
      find.byKey(const ValueKey('content-first')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Taille préférée : first'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('style-menu-Style du slot')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('style-menu-remove-Taille préférée : first')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('content-first')), findsNothing);
    expect(find.byKey(const ValueKey('content-second')), findsOneWidget);
    expect(find.text('Taille préférée : first'), findsNothing);
    expect(find.text('Largeur (px)'), findsNothing);
    expect(changes.single.placementsOf(SuperLayoutZone.center), ['second']);
    expect(changes.single.slotPreferredSizes.containsKey('first'), isFalse);
    expect(
      tester.getSize(find.byKey(const ValueKey('content-second'))),
      const Size(600, 400),
    );
    await tester.tap(
      find.byKey(const ValueKey('content-second')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-menu-add-Super layout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-layout-add-slot-first')));
    await tester.pumpAndSettle();
    expect(changes.last.placementsOf(SuperLayoutZone.center), [
      'second',
      'first',
    ]);
    expect(find.byKey(const ValueKey('content-first')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('zone axes round trip, follow swaps and reject invalid JSON', () {
    final config = base
        .withAxis(SuperLayoutZone.center, Axis.horizontal)
        .withAxis(SuperLayoutZone.north, Axis.horizontal);
    final restored = SuperLayoutConfig.fromJson(config.toJson());
    expect(restored, config);
    expect(restored.hashCode, config.hashCode);
    expect(restored.copyWith(), config);
    expect(base.axisOf(SuperLayoutZone.center), Axis.vertical);
    expect(SuperLayoutConfig.fromJson({}).zoneAxes, isEmpty);
    expect(SuperLayoutConfig.fromJson({}, fallback: config), config);
    expect(config.toJson()['zoneAxes'], {'center': 'row', 'north': 'row'});
    expect(config, isNot(base));
    final swapped = config.withSwap(SuperLayoutZone.north);
    expect(swapped.axisOf(SuperLayoutZone.south), Axis.horizontal);
    expect(swapped.axisOf(SuperLayoutZone.north), Axis.vertical);
    final edited = swapped.withAxis(SuperLayoutZone.south, Axis.vertical);
    expect(edited.zoneAxes[SuperLayoutZone.north], Axis.vertical);
    for (final axes in [
      [],
      {'nowhere': 'row'},
      {'center': 'diagonal'},
      {'center': 1},
      {'center': null},
    ]) {
      expect(
        () => SuperLayoutConfig.fromJson({'zoneAxes': axes}),
        throwsFormatException,
      );
    }
  });

  testWidgets('row splits fill slots horizontally', (tester) async {
    await pump(
      tester,
      config: base.withAxis(SuperLayoutZone.center, Axis.horizontal),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('content-first'))),
      const Rect.fromLTWH(0, 0, 300, 400),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('content-second'))),
      const Rect.fromLTWH(300, 0, 300, 400),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('row respects preferred sizes and remaining fill width', (
    tester,
  ) async {
    await pump(
      tester,
      config: base
          .withAxis(SuperLayoutZone.center, Axis.horizontal)
          .withSlotPreferredSize('first', const Size(240, 90)),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('content-first'))),
      const Rect.fromLTWH(0, 0, 240, 90),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('content-second'))),
      const Rect.fromLTWH(240, 0, 360, 400),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('row bounds oversized preferences proportionally', (
    tester,
  ) async {
    await pump(
      tester,
      config: base
          .withAxis(SuperLayoutZone.center, Axis.horizontal)
          .withSlotPreferredSize('first', const Size(600, 1000))
          .withSlotPreferredSize('second', const Size(200, 1000)),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('content-first'))),
      const Rect.fromLTWH(0, 0, 450, 400),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('content-second'))),
      const Rect.fromLTWH(450, 0, 150, 400),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('row reserves width for intrinsic siblings', (tester) async {
    await pump(
      tester,
      config: base
          .withAxis(SuperLayoutZone.center, Axis.horizontal)
          .withSlotPreferredSize('first', const Size(1000, 90)),
      slots: [
        slot('first'),
        BuilderSlot(
          id: 'second',
          label: 'second',
          sizing: SlotSizing.intrinsic,
          builder: (_) =>
              const SizedBox(key: ValueKey('content-second'), width: 50),
        ),
      ],
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(550, 90),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-second'))),
      const Size(50, 400),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('row automatic sides measure the appropriate dimension', (
    tester,
  ) async {
    for (final zone in [SuperLayoutZone.north, SuperLayoutZone.west]) {
      await pump(
        tester,
        config: base.copyWith(
          north: zone == SuperLayoutZone.north,
          west: zone == SuperLayoutZone.west,
          autoSides: {zone},
          zoneAxes: {zone: Axis.horizontal},
          placements: {
            zone: ['first', 'second'],
          },
          slotPreferredSizes: {
            'first': const Size(150, 60),
            'second': const Size(100, 40),
          },
        ),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('content-first'))),
        const Rect.fromLTWH(0, 0, 150, 60),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('content-second'))),
        const Rect.fromLTWH(150, 0, 100, 40),
      );
      expect(
        tester.getSize(find.byKey(ValueKey('super-layout-${zone.name}'))),
        zone == SuperLayoutZone.north
            ? const Size(600, 60)
            : const Size(250, 400),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('row dragging uses left and right halves and a vertical marker', (
    tester,
  ) async {
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    SuperLayoutConfig? changed;
    final config = base.withAxis(SuperLayoutZone.center, Axis.horizontal);
    for (final after in [true, false]) {
      await pump(
        tester,
        config: config,
        editMode: editMode,
        onChanged: (value) => changed = value,
      );
      await tester.pumpAndSettle();
      final source = after ? 'first' : 'second';
      final target = after ? 'second' : 'first';
      final rect = tester.getRect(find.byKey(ValueKey('content-$target')));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('slot-label-$source'))),
      );
      await gesture.moveBy(const Offset(0, 25));
      await gesture.moveTo(
        Offset(after ? rect.right - 20 : rect.left + 20, rect.top + 80),
      );
      await tester.pump();
      final marker = tester.getRect(
        find.byKey(ValueKey('slot-drop-position-$target')),
      );
      expect(marker.width, 3);
      expect(marker.height, rect.height);
      expect(marker.left, after ? rect.right - 3 : rect.left);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changed!.placementsOf(SuperLayoutZone.center), [
        'second',
        'first',
      ]);
      // Reset the widget identity so each direction starts from the same order.
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('zone axis selector updates live, cancels and resets', (
    tester,
  ) async {
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    SuperLayoutConfig? changed;
    await pump(
      tester,
      editMode: editMode,
      onChanged: (value) => changed = value,
    );
    Future<void> openLayoutEditor() async {
      await tester.tap(
        find.byKey(const ValueKey('content-first')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Super layout'));
      await tester.pumpAndSettle();
    }

    Future<void> chooseRow() async {
      final selector = find.byKey(const ValueKey('super-layout-axis-center'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Row').last);
      await tester.pumpAndSettle();
    }

    await openLayoutEditor();
    for (final zone in SuperLayoutZone.values) {
      final dropdown = tester.widget<DropdownButton<Axis>>(
        find.byKey(ValueKey('super-layout-axis-${zone.name}')),
      );
      expect(dropdown.value, Axis.vertical);
      expect(
        dropdown.onChanged,
        zone == SuperLayoutZone.center ? isNotNull : isNull,
      );
    }
    await chooseRow();
    expect(changed!.axisOf(SuperLayoutZone.center), Axis.horizontal);
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(300, 400),
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(changed!.axisOf(SuperLayoutZone.center), Axis.vertical);
    await openLayoutEditor();
    await chooseRow();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(changed!.axisOf(SuperLayoutZone.center), Axis.horizontal);
    await openLayoutEditor();
    await tester.ensureVisible(find.text('Réinitialiser'));
    await tester.tap(find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    expect(changed!.zoneAxes, isEmpty);
    expect(changed!.placements, base.placements);
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
      config: base.withAxis(SuperLayoutZone.center, Axis.horizontal),
    );
    expect(created, 1);
    await pump(
      tester,
      slots: slots,
      config: base
          .withAxis(SuperLayoutZone.center, Axis.horizontal)
          .withSlotPreferredSize('first', const Size(150, 60)),
    );
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
