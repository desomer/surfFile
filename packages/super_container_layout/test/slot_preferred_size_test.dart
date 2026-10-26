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
            ? EditableSurface(
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
    await tester.tap(
      find.byKey(
        const ValueKey('style-menu-size-Taille et marge préférées : first'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder slider(String key) => find.byWidgetPredicate(
    (widget) => widget is Slider && widget.key == ValueKey(key),
  );

  testWidgets('corner handles belong only to the selected editable slot', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, editMode: mode);
    Finder handle(String id, String corner) =>
        find.byKey(ValueKey('slot-resize-$id-$corner'));
    expect(handle('first', 'se'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    for (final corner in ['nw', 'ne', 'sw', 'se', 'n', 's', 'e', 'w']) {
      expect(handle('first', corner), findsOneWidget);
      expect(handle('second', corner), findsNothing);
      expect(tester.getSize(handle('first', corner)), const Size(32, 32));
    }
    await tester.tap(find.byKey(const ValueKey('slot-label-select-second')));
    await tester.pumpAndSettle();
    expect(handle('first', 'se'), findsNothing);
    expect(handle('second', 'se'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slot-label-select-second')));
    await tester.pumpAndSettle();
    expect(handle('second', 'se'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    mode.value = false;
    await tester.pumpAndSettle();
    expect(handle('first', 'se'), findsNothing);
    mode.value = true;
    await pump(tester, editMode: mode, editable: false);
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    expect(handle('first', 'se'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slot padding is saved and applied around its content', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    SuperLayoutConfig? changed;
    await pump(
      tester,
      editMode: mode,
      config: base.copyWith(
        slotPreferredSizes: const {'first': Size(300, 200)},
        slotSizeConstraints: const {'first': SlotSizeConstraints(padding: 12)},
      ),
      onChanged: (value) => changed = value,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(276, 176),
    );

    await openEditor(tester);
    expect(find.byKey(const ValueKey('slot-padding-card')), findsOneWidget);
    tester.widget<Slider>(slider('slot-padding')).onChanged!(24);
    await tester.pump();
    expect(changed!.slotSizeConstraints['first']!.padding, 24);
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(
      SlotSizeConstraints.fromJson(
        changed!.slotSizeConstraints['first']!.toJson(),
      ),
      changed!.slotSizeConstraints['first'],
    );
    expect(SuperLayoutConfig.fromJson(changed!.toJson()), changed);
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(252, 152),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('slot padding can be configured independently by side', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    SuperLayoutConfig? changed;
    await pump(
      tester,
      editMode: mode,
      config: base.copyWith(
        slotPreferredSizes: const {'first': Size(300, 200)},
      ),
      onChanged: (value) => changed = value,
    );
    await openEditor(tester);
    final independent = find
        .byKey(const ValueKey('slot-padding-independent'))
        .first;
    await tester.ensureVisible(independent);
    await tester.tap(independent);
    await tester.pumpAndSettle();
    final top = slider('slot-padding-side-0');
    await tester.ensureVisible(top);
    tester.widget<Slider>(top).onChanged!(32);
    await tester.pump();
    expect(
      changed!.slotSizeConstraints['first']!.paddingInsets,
      const EdgeInsets.only(top: 32),
    );
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(SuperLayoutConfig.fromJson(changed!.toJson()), changed);
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(300, 168),
    );
    expect(tester.takeException(), isNull);
  });

  for (final (side, delta, expected) in [
    ('e', const Offset(40, 30), const Size(280, 120)),
    ('w', const Offset(-40, 30), const Size(280, 120)),
    ('n', const Offset(40, -30), const Size(240, 150)),
    ('s', const Offset(40, 30), const Size(240, 150)),
  ]) {
    testWidgets('$side arrow adjusts only its dimension and shows live size', (
      tester,
    ) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      SuperLayoutConfig? changed;
      await pump(
        tester,
        editMode: mode,
        config: base.copyWith(
          slotPreferredSizes: {'first': const Size(240, 120)},
        ),
        onChanged: (value) => changed = value,
      );
      await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
      await tester.pumpAndSettle();
      final handle = find.byKey(ValueKey('slot-resize-first-$side'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(delta / 2);
      await tester.pump();
      await gesture.moveBy(delta / 2);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('slot-resize-size-first')),
        findsOneWidget,
      );
      expect(
        find.text('${expected.width.round()} × ${expected.height.round()} px'),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changed!.slotPreferredSizes['first'], expected);
      expect(
        find.byKey(const ValueKey('slot-resize-size-first')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final (corner, delta) in [
    ('nw', const Offset(-40, -30)),
    ('ne', const Offset(40, -30)),
    ('sw', const Offset(-40, 30)),
    ('se', const Offset(40, 30)),
  ]) {
    testWidgets('$corner handle resizes from displayed size and persists', (
      tester,
    ) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      SuperLayoutConfig? changed;
      await pump(
        tester,
        editMode: mode,
        slots: [
          slot('first', preferredSize: const Size(240, 120)),
          slot('second'),
        ],
        onChanged: (value) => changed = value,
      );
      await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(ValueKey('slot-resize-first-$corner')),
        delta,
      );
      await tester.pumpAndSettle();
      expect(changed!.slotPreferredSizes['first'], const Size(280, 150));
      expect(
        tester.getSize(find.byKey(const ValueKey('content-first'))),
        const Size(280, 150),
      );
      final restored = SuperLayoutConfig.fromJson(changed!.toJson());
      await pump(tester, config: restored, editMode: mode);
      expect(
        tester.getSize(find.byKey(const ValueKey('content-first'))),
        const Size(280, 150),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('corner handle tooltips can appear and resize while hovered', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(
      tester,
      editMode: mode,
      slots: [
        slot('first', preferredSize: const Size(240, 120)),
        slot('second'),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    for (final corner in ['nw', 'ne', 'sw', 'se']) {
      final handle = find.byKey(ValueKey('slot-resize-first-$corner'));
      await mouse.moveTo(tester.getCenter(handle));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Redimensionner first'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await mouse.moveTo(const Offset(700, 500));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }
    final handle = find.byKey(const ValueKey('slot-resize-first-se'));
    await mouse.moveTo(tester.getCenter(handle));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.drag(handle, const Offset(40, 30));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(280, 150),
    );
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('corner overlays follow a translated and scaled layout', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    final translation = ValueNotifier(Offset.zero);
    addTearDown(mode.dispose);
    addTearDown(translation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: Scaffold(
            body: Center(
              child: ValueListenableBuilder<Offset>(
                valueListenable: translation,
                builder: (context, offset, child) =>
                    Transform.translate(offset: offset, child: child),
                child: Transform.scale(
                  scale: .75,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 600,
                    height: 400,
                    child: SuperLayout(
                      config: base,
                      slots: [
                        slot('first', preferredSize: const Size(240, 120)),
                        slot('second'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(
      tester.getTopLeft(find.byType(SuperLayout)) + const Offset(100, 50),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    final content = find.byKey(const ValueKey('content-first'));
    final handle = find.byKey(const ValueKey('slot-resize-first-se'));
    expect(tester.getBottomRight(handle), tester.getBottomRight(content));
    final before = tester.getBottomRight(handle);
    translation.value = const Offset(40, 30);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(handle), before + const Offset(40, 30));
    expect(tester.getBottomRight(handle), tester.getBottomRight(content));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(handle));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Redimensionner first'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(handle, const Offset(30, 22.5));
    await tester.pumpAndSettle();
    expect(tester.getSize(content), const Size(280, 150));
    expect(tester.getBottomRight(handle), tester.getBottomRight(content));
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('corner resizing preserves percentage units and sibling minima', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    final config = base.copyWith(
      slotSizeConstraints: {
        'first': const SlotSizeConstraints(
          minWidth: SlotDimension(20, SlotSizeUnit.percent),
          maxWidth: SlotDimension(75, SlotSizeUnit.percent),
          minHeight: SlotDimension(50, SlotSizeUnit.pixels),
          preferredWidth: SlotDimension(50, SlotSizeUnit.percent),
          preferredHeight: SlotDimension(25, SlotSizeUnit.percent),
          percentBasis: SlotPercentBasis.layout,
        ),
        'second': const SlotSizeConstraints(
          minHeight: SlotDimension(100, SlotSizeUnit.pixels),
        ),
      },
    );
    SuperLayoutConfig? changed;
    await pump(
      tester,
      config: config,
      editMode: mode,
      onChanged: (value) => changed = value,
    );
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('slot-resize-first-se')),
      const Offset(500, 500),
    );
    await tester.pumpAndSettle();
    final dimensions = changed!.slotSizeConstraints['first']!;
    expect(
      dimensions.preferredWidth,
      const SlotDimension(75, SlotSizeUnit.percent),
    );
    expect(
      dimensions.preferredHeight,
      const SlotDimension(75, SlotSizeUnit.percent),
    );
    expect(dimensions.minWidth, config.slotSizeConstraints['first']!.minWidth);
    expect(dimensions.maxWidth, config.slotSizeConstraints['first']!.maxWidth);
    expect(dimensions.percentBasis, SlotPercentBasis.layout);
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(450, 300),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-second'))).height,
      100,
    );
    await tester.drag(
      find.byKey(const ValueKey('slot-resize-first-se')),
      const Offset(-600, -600),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(120, 50),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal corner resizing allows fill siblings to shrink', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(
      tester,
      config: base
          .withAxis(SuperLayoutZone.center, Axis.horizontal)
          .copyWith(
            slotSizeConstraints: {
              'second': const SlotSizeConstraints(
                minWidth: SlotDimension(100, SlotSizeUnit.pixels),
              ),
            },
          ),
      editMode: mode,
    );
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('slot-resize-first-se')),
      const Offset(400, -80),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(500, 320),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-second'))).width,
      100,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('corner resizing starts from the clamped displayed size', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    SuperLayoutConfig? changed;
    await pump(
      tester,
      editMode: mode,
      slots: [
        slot('first', preferredSize: const Size(1000, 1000)),
        slot('second'),
      ],
      onChanged: (value) => changed = value,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(600, 400),
    );
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('slot-resize-first-se')),
      const Offset(-50, -50),
    );
    await tester.pumpAndSettle();
    expect(changed!.slotPreferredSizes['first'], const Size(550, 350));
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(550, 350),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('corner resizing resolves percentages against the zone', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    SuperLayoutConfig? changed;
    await pump(
      tester,
      config: base.copyWith(
        north: true,
        slotSizeConstraints: {
          'first': const SlotSizeConstraints(
            preferredWidth: SlotDimension(50, SlotSizeUnit.percent),
            preferredHeight: SlotDimension(50, SlotSizeUnit.percent),
          ),
        },
      ),
      editMode: mode,
      onChanged: (value) => changed = value,
    );
    final initial = tester.getSize(find.byKey(const ValueKey('content-first')));
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('slot-resize-first-se')),
      Offset(initial.width * .2, initial.height * .2),
    );
    await tester.pumpAndSettle();
    final dimensions = changed!.slotSizeConstraints['first']!;
    expect(dimensions.percentBasis, SlotPercentBasis.zone);
    expect(dimensions.preferredWidth!.unit, SlotSizeUnit.percent);
    expect(dimensions.preferredHeight!.unit, SlotSizeUnit.percent);
    expect(dimensions.preferredWidth!.value, closeTo(60, .001));
    expect(dimensions.preferredHeight!.value, closeTo(60, .001));
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))).height,
      closeTo(initial.height * 1.2, .001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a continuous corner drag is a single undoable change', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier<Appearance>(
      Appearance(layouts: {'resize': base}),
    );
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: mode,
    );
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    addTearDown(history.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorHistoryScope(
          controller: history,
          child: StyleEditScope(
            controller: mode,
            child: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: ValueListenableBuilder<Appearance>(
                  valueListenable: appearance,
                  builder: (context, value, _) => SuperLayout(
                    config: value.layouts['resize']!,
                    onChanged: (config) => appearance.value = appearance.value
                        .withLayout('resize', config),
                    slots: [slot('first'), slot('second')],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('slot-resize-first-se'))),
    );
    await gesture.moveBy(const Offset(-40, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(-20, 30));
    await tester.pump();
    expect(history.canUndo, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    final changed = appearance.value.layouts['resize'];
    expect(changed!.slotPreferredSizes['first'], const Size(540, 260));
    history.undo();
    await tester.pumpAndSettle();
    expect(appearance.value.layouts['resize'], base);
    expect(history.canUndo, isFalse);
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(600, 200),
    );
    history.redo();
    await tester.pumpAndSettle();
    expect(appearance.value.layouts['resize'], changed);
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(540, 260),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('incompatible slot bounds report blocked corner resizing', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    var updates = 0;
    await pump(
      tester,
      config: base.copyWith(
        slotSizeConstraints: {
          'first': const SlotSizeConstraints(
            minHeight: SlotDimension(200, SlotSizeUnit.pixels),
            maxHeight: SlotDimension(100, SlotSizeUnit.pixels),
          ),
        },
      ),
      editMode: mode,
      onChanged: (_) => updates++,
    );
    await tester.tap(find.byKey(const ValueKey('slot-label-select-first')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('slot-resize-first-se')),
      const Offset(-40, -40),
    );
    await tester.pump();
    expect(updates, 0);
    expect(
      find.textContaining('Redimensionnement de first impossible'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'size sliders preview immediately and cancel restores saved sizes',
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
      await openEditor(tester);
      expect(find.byType(Slider), findsNWidgets(3));
      final slider = find.byKey(const ValueKey('slot-slider-preferred-height'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.drag(slider, const Offset(0, -30));
      await tester.pump();
      final preferred = changed!.slotSizeConstraints['first']!.preferredHeight!;
      expect(preferred.unit, SlotSizeUnit.pixels);
      expect(preferred.value, greaterThan(0));
      expect(
        tester.getSize(find.byKey(const ValueKey('content-first'))).height,
        preferred.value.clamp(0, 400),
      );
      final field = tester.widget<TextFormField>(
        find.byKey(const ValueKey('slot-preferred-height')),
      );
      expect(double.parse(field.controller!.text), preferred.value);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(changed, base);
      expect(
        tester.getSize(find.byKey(const ValueKey('content-first'))).height,
        200,
      );
    },
  );

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
          padding: 16,
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
    expect(
      () => SlotSizeConstraints.fromJson({'padding': 201}),
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('slot-unit-preferred-width')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slot-unit-preferred-width')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('%').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('slot-unit-preferred-height')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slot-unit-preferred-height')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('%').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('slot-percent-basis')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slot-percent-basis')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toute la place du layout').last);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(240, 100),
    );
    final percentSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('slot-slider-preferred-width')),
    );
    expect(percentSlider.max, 100);
    expect(percentSlider.value, 40);
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
    expect(find.text('Taille et marge préférées : first'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('style-menu-size-Taille et marge préférées : first'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('style-menu-Style du slot')),
      findsOneWidget,
    );
    for (final action in ['size', 'remove']) {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('style-menu-Style du slot')),
          matching: find.byKey(
            ValueKey('style-menu-$action-Taille et marge préférées : first'),
          ),
        ),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.byKey(
        const ValueKey('style-menu-remove-Taille et marge préférées : first'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('content-first')), findsNothing);
    expect(find.byKey(const ValueKey('content-second')), findsOneWidget);
    expect(find.text('Taille et marge préférées : first'), findsNothing);
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
    await tester.tap(find.byKey(const ValueKey('style-menu-add-Centre')));
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
    Future<void> openZoneEditor() async {
      await tester.tap(
        find.byKey(const ValueKey('content-first')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('style-menu-zone-flow-Centre')),
      );
      await tester.pumpAndSettle();
    }

    Future<void> chooseRow() async {
      final selector = find.byKey(
        const ValueKey('zone-flow-dialog-center-axis'),
      );
      await tester.ensureVisible(selector);
      await tester.tap(find.text('Ligne (Row)'));
      await tester.pumpAndSettle();
    }

    await openZoneEditor();
    await chooseRow();
    expect(changed!.axisOf(SuperLayoutZone.center), Axis.horizontal);
    expect(
      tester.getSize(find.byKey(const ValueKey('content-first'))),
      const Size(300, 400),
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(changed!.axisOf(SuperLayoutZone.center), Axis.vertical);
    await openZoneEditor();
    await chooseRow();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(changed!.axisOf(SuperLayoutZone.center), Axis.horizontal);
    await openZoneEditor();
    await tester.ensureVisible(find.text('Réinitialiser'));
    await tester.tap(find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    expect(changed!.axisOf(SuperLayoutZone.center), Axis.vertical);
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
      await tester.tap(
        find.byKey(
          const ValueKey('style-menu-size-Taille et marge préférées : first'),
        ),
      );
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
        find.text('Saisissez une dimension positive en pixels ou en %.'),
        findsOneWidget,
      );
      expect(changed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-width')),
        '240,5',
      );
      await tester.pump();
      expect(changed!.slotPreferredSizes['first'], const Size(240.5, 90));
      expect(
        tester.getSize(find.byKey(const ValueKey('content-first'))),
        const Size(240.5, 90),
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
      await tester.tap(find.text('Taille et marge par défaut'));
      await tester.pumpAndSettle();
      expect(changed!.slotPreferredSizes, {'first': null});
      expect(
        tester.getSize(find.byKey(const ValueKey('content-first'))),
        const Size(600, 200),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('size editor clears each constraint and cancel restores all', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    final initial = base.copyWith(
      slotSizeConstraints: {
        'first': const SlotSizeConstraints(
          minWidth: SlotDimension(10, SlotSizeUnit.pixels),
          minHeight: SlotDimension(10, SlotSizeUnit.pixels),
          preferredWidth: SlotDimension(300, SlotSizeUnit.pixels),
          preferredHeight: SlotDimension(100, SlotSizeUnit.pixels),
          maxWidth: SlotDimension(500, SlotSizeUnit.pixels),
          maxHeight: SlotDimension(300, SlotSizeUnit.pixels),
          percentBasis: SlotPercentBasis.zone,
        ),
      },
    );
    SuperLayoutConfig? changed;
    await pump(
      tester,
      config: initial,
      editMode: mode,
      onChanged: (value) => changed = value,
    );
    await openEditor(tester);
    expect(
      tester
          .widget<DropdownButton<SlotPercentBasis>>(
            find.byKey(const ValueKey('slot-percent-basis')),
          )
          .value,
      SlotPercentBasis.zone,
    );
    for (final key in [
      'min-width',
      'min-height',
      'preferred-width',
      'preferred-height',
      'max-width',
      'max-height',
    ]) {
      final clear = find.byKey(ValueKey('slot-clear-$key'));
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(ValueKey('slot-$key')))
            .controller!
            .text,
        isEmpty,
      );
    }
    expect(changed!.slotSizeConstraints, isEmpty);
    expect(changed!.slotPreferredSizes['first'], isNull);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(changed, initial);
    expect(tester.takeException(), isNull);
  });

  testWidgets('size editor preview matches proportions and sliders retarget', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, editMode: mode);
    await openEditor(tester);
    expect(
      tester
          .widget<DropdownButton<SlotPercentBasis>>(
            find.byKey(const ValueKey('slot-percent-basis')),
          )
          .value,
      SlotPercentBasis.layout,
    );
    final layoutPreview = find.byKey(const ValueKey('slot-preview-layout'));
    final slotPreview = find.byKey(const ValueKey('slot-preview-slot'));
    final layoutSize = tester.getSize(layoutPreview);
    expect(layoutSize.width / layoutSize.height, closeTo(1.5, .001));
    expect(tester.getSize(slotPreview).height / layoutSize.height, .5);
    await tester.enterText(
      find.byKey(const ValueKey('slot-preferred-width')),
      '300',
    );
    await tester.enterText(
      find.byKey(const ValueKey('slot-preferred-height')),
      '100',
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(slotPreview).width / layoutSize.width, .5);
    expect(tester.getSize(slotPreview).height / layoutSize.height, .25);
    expect(find.text('Effective : 300.0 × 100.0 px'), findsOneWidget);
    final vertical = tester.widget<RotatedBox>(
      find.ancestor(
        of: find.byKey(const ValueKey('slot-slider-preferred-height')),
        matching: find.byType(RotatedBox),
      ),
    );
    expect(vertical.quarterTurns, 3);
    for (final group in ['min', 'max']) {
      final chip = find.byKey(ValueKey('slot-slider-group-$group'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('slot-slider-$group-width')), findsOneWidget);
      expect(find.byKey(ValueKey('slot-slider-$group-height')), findsOneWidget);
    }
    await tester.enterText(
      find.byKey(const ValueKey('slot-max-width')),
      '2000',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('slot-slider-max-width')))
          .max,
      2000,
    );
    expect(find.byKey(const ValueKey('slot-preview-max')), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('size editor rejects conflicting bounds before applying', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    SuperLayoutConfig? changed;
    await pump(tester, editMode: mode, onChanged: (value) => changed = value);
    await openEditor(tester);
    await tester.enterText(find.byKey(const ValueKey('slot-max-width')), '100');
    await tester.pumpAndSettle();
    final valid = changed;
    await tester.enterText(find.byKey(const ValueKey('slot-min-width')), '200');
    await tester.pumpAndSettle();
    expect(
      find.text('La largeur minimale dépasse la largeur maximale.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(changed, valid);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(changed, base);
    expect(tester.takeException(), isNull);
  });

  for (final basis in SlotPercentBasis.values) {
    testWidgets('size editor preserves saved ${basis.name} basis with pixels', (
      tester,
    ) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      SuperLayoutConfig? changed;
      await pump(
        tester,
        editMode: mode,
        config: base.copyWith(
          slotSizeConstraints: {
            'first': SlotSizeConstraints(
              preferredWidth: const SlotDimension(300, SlotSizeUnit.pixels),
              preferredHeight: const SlotDimension(100, SlotSizeUnit.pixels),
              percentBasis: basis,
            ),
          },
        ),
        onChanged: (value) => changed = value,
      );
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-width')),
        '320',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(changed!.slotSizeConstraints['first']!.percentBasis, basis);
      await openEditor(tester);
      expect(
        tester
            .widget<DropdownButton<SlotPercentBasis>>(
              find.byKey(const ValueKey('slot-percent-basis')),
            )
            .value,
        basis,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('size editor remains usable on a narrow screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, editMode: mode);
    await openEditor(tester);
    expect(find.byKey(const ValueKey('slot-preview-slot')), findsOneWidget);
    final clear = find.byKey(const ValueKey('slot-clear-max-height'));
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('slot-max-height')),
      '200',
    );
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slot editor changes apply as one undoable transaction', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier<Appearance>(
      Appearance(layouts: {'editor': base}),
    );
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: mode,
    );
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    addTearDown(history.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorHistoryScope(
          controller: history,
          child: StyleEditScope(
            controller: mode,
            child: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: ValueListenableBuilder<Appearance>(
                  valueListenable: appearance,
                  builder: (context, value, _) => SuperLayout(
                    config: value.layouts['editor']!,
                    onChanged: (config) => appearance.value = appearance.value
                        .withLayout('editor', config),
                    slots: [slot('first'), slot('second')],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await openEditor(tester);
    final slider = find.byKey(const ValueKey('slot-slider-preferred-width'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(history.canUndo, isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('slot-preferred-height')),
      '120',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    final saved = appearance.value.layouts['editor'];
    expect(saved, isNot(base));
    expect(history.canUndo, isTrue);
    history.undo();
    await tester.pumpAndSettle();
    expect(appearance.value.layouts['editor'], base);
    expect(history.canUndo, isFalse);
    history.redo();
    await tester.pumpAndSettle();
    expect(appearance.value.layouts['editor'], saved);
    expect(tester.takeException(), isNull);
  });

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
      expect(find.text('Taille et marge préférées : first'), findsNothing);
      expect(
        find.byKey(
          const ValueKey('style-menu-size-Taille et marge préférées : first'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('style-menu-remove-Taille et marge préférées : first'),
        ),
        findsNothing,
      );
      editMode.value = true;
      await pump(tester, editMode: editMode, editable: false);
      await tester.tap(
        find.byKey(const ValueKey('content-first')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Taille et marge préférées : first'), findsNothing);
      expect(
        find.byKey(
          const ValueKey('style-menu-size-Taille et marge préférées : first'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('style-menu-remove-Taille et marge préférées : first'),
        ),
        findsNothing,
      );
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
