import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/widgets/press_feedback.dart';
import 'dart:io';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';

void main() {
  testWidgets('press selects immediately, compresses and restores on release',
      (tester) async {
    var selections = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: PressFeedback(
        onMouseDown: () => selections++,
        child: const SizedBox(width: 200, height: 60, child: Text('Entry')),
      ),
    )));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Entry')),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    expect(selections, 1);
    await tester.pump();
    expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .995);
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(selections, 1);

    final cancelled = await tester.startGesture(
      tester.getCenter(find.text('Entry')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    final secondary = await tester.startGesture(
      tester.getCenter(find.text('Entry')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(selections, 2);
    await secondary.up();
  });

  for (final cancel in [false, true]) {
    testWidgets('gesture can end after pressed widget is disposed: $cancel',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PressFeedback(
          onMouseDown: () {},
          child: const SizedBox(width: 200, height: 60, child: Text('Entry')),
        ),
      ));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Entry')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final grid in [false, true]) {
    testWidgets('selection rebuild keeps the pressed card alive: $grid',
        (tester) async {
      String? selected;
      final entry = ExplorerEntry(
        entity: Directory('folder'),
        name: 'folder',
        isDirectory: true,
        modified: DateTime(2026),
        size: 0,
      );
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
                  body: ExplorerEntriesView(
                    entries: [entry],
                    gridView: grid,
                    selectedPath: selected,
                    onSelected: (path) => setState(() => selected = path),
                    onOpen: (_) {},
                    onOpenWithBounds: (_, __, ___) {},
                  ),
                )),
      ));
      final feedback = find.byType(PressFeedback);
      final before = tester.state(feedback);
      final gesture = await tester.startGesture(
          tester.getCenter(find.text('folder')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(selected, 'folder');
      expect(tester.state(feedback), same(before));
      expect(
          tester
              .widget<AnimatedScale>(find.descendant(
                  of: feedback, matching: find.byType(AnimatedScale)))
              .scale,
          .995);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<AnimatedScale>(find.descendant(
                  of: feedback, matching: find.byType(AnimatedScale)))
              .scale,
          1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('reduced motion preserves immediate selection without scaling',
      (tester) async {
    var selected = false;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: PressFeedback(
        onMouseDown: () => selected = true,
        child: const SizedBox(width: 200, height: 60, child: Text('Entry')),
      ),
    )));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Entry')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(selected, isTrue);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
  });
}
