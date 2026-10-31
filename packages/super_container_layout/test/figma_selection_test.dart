import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  const config = SuperLayoutConfig(
    north: false,
    south: false,
    west: false,
    east: false,
    placements: {
      SuperLayoutZone.center: ['content'],
    },
  );

  Widget layout(String name, Widget child) => SuperLayout(
    name: name,
    config: config,
    showZoneNames: false,
    slots: [
      BuilderSlot(id: 'content', label: '$name child', builder: (_) => child),
    ],
  );

  Future<void> doubleClick(WidgetTester tester, Offset point) async {
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
  }

  Future<ValueNotifier<bool>> pump(WidgetTester tester, Widget child) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return mode;
  }

  List<EditorSelectionOutline> outlines(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.foregroundPainter)
      .whereType<EditorSelectionOutline>()
      .toList();

  testWidgets(
    'single click selects zone; only a double click selects its child',
    (tester) async {
      var presses = 0;
      final mode = await pump(
        tester,
        layout(
          'Root',
          Center(
            child: FilledButton(
              onPressed: () => presses++,
              child: const Text('Action'),
            ),
          ),
        ),
      );
      const point = Offset(600, 400);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Root', 'Centre']);
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Root', 'Centre']);
      await tester.pump(const Duration(seconds: 1));
      await doubleClick(tester, point);
      expect(LayoutSelection.path.value, ['Root', 'Centre', 'Root child']);

      mode.value = false;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();
      expect(presses, 1);
      expect(LayoutSelection.path.value, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('grid clicks select the canvas before its direct child', (
    tester,
  ) async {
    await pump(
      tester,
      SuperLayout(
        name: 'Grid',
        config: config.copyWith(
          positioning: SuperLayoutPositioning.grid,
          grid: const GridLayoutConfig(
            columns: 4,
            rowHeight: 80,
            compact: false,
            items: {'content': GridSlotPosition(width: 4, height: 4)},
          ),
        ),
        slots: [
          BuilderSlot(
            id: 'content',
            label: 'Grid child',
            builder: (_) => const SizedBox.expand(),
          ),
        ],
      ),
    );
    const point = Offset(600, 200);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(LayoutSelection.path.value, ['Grid']);
    await tester.pump(const Duration(seconds: 1));
    await doubleClick(tester, point);
    expect(LayoutSelection.path.value, ['Grid', 'Grid child']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'nested double clicks skip zones when double-clicking on a direct child and select the zone only when empty',
    (tester) async {
      await pump(
        tester,
        layout(
          'Root',
          layout(
            'Nested',
            SuperLayout(
              name: 'Grandchild',
              config: const SuperLayoutConfig(
                north: false,
                south: false,
                west: false,
                east: false,
              ),
              showZoneNames: false,
            ),
          ),
        ),
      );
      final history = <List<String>>[];
      void record() => history.add(List.of(LayoutSelection.path.value));
      LayoutSelection.path.addListener(record);
      addTearDown(() => LayoutSelection.path.removeListener(record));
      const point = Offset(600, 400);
      await doubleClick(tester, point);
      expect(LayoutSelection.path.value, ['Root', 'Centre', 'Root child']);
      await doubleClick(tester, point);
      expect(LayoutSelection.path.value, [
        'Root',
        'Centre',
        'Nested',
        'Centre',
        'Nested child',
      ]);
      await doubleClick(tester, point);
      expect(LayoutSelection.path.value, [
        'Root',
        'Centre',
        'Nested',
        'Centre',
        'Grandchild',
        'Centre',
      ]);
      expect(history, [
        ['Root', 'Centre'],
        ['Root', 'Centre', 'Root child'],
        ['Root', 'Centre', 'Nested', 'Centre', 'Nested child'],
        ['Root', 'Centre', 'Nested', 'Centre', 'Grandchild', 'Centre'],
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hover uses a solid zone outline then a dashed direct child', (
    tester,
  ) async {
    final mode = await pump(
      tester,
      layout('Root', layout('Nested', const SizedBox.expand())),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(790, 590));
    await mouse.moveTo(const Offset(600, 400));
    await tester.pumpAndSettle();
    expect(outlines(tester), hasLength(1));
    expect(outlines(tester).single.dashed, isFalse);
    await tester.tapAt(const Offset(600, 400));
    await tester.pumpAndSettle();
    expect(outlines(tester), hasLength(1));
    expect(outlines(tester).single.dashed, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await doubleClick(tester, const Offset(600, 400));
    expect(outlines(tester), hasLength(1));
    expect(outlines(tester).single.dashed, isFalse);
    mode.value = false;
    await tester.pumpAndSettle();
    expect(outlines(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag and cancelled pointers do not select a zone', (
    tester,
  ) async {
    await pump(tester, layout('Root', const SizedBox.expand()));
    await tester.dragFrom(const Offset(600, 400), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(LayoutSelection.path.value, isEmpty);
    final gesture = await tester.startGesture(const Offset(600, 400));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(LayoutSelection.path.value, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
