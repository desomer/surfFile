import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/widgets/hover_preview.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hover_preview_');
    for (var i = 0; i < 10; i++) {
      File('${root.path}/f$i.txt').writeAsStringSync('x');
    }
  });

  tearDown(() {
    HoverPreview.dismiss();
    root.deleteSync(recursive: true);
  });

  ExplorerEntry entry(String path, {bool directory = false}) => ExplorerEntry(
    entity: directory ? Directory(path) : File(path),
    name: path.split(Platform.pathSeparator).last,
    isDirectory: directory,
    modified: DateTime(2026),
    size: 0,
  );

  Future<TestGesture> pump(WidgetTester tester, ExplorerEntry e) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HoverPreview(
              entry: e,
              child: const SizedBox(width: 200, height: 30),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    return mouse;
  }

  final preview = find.byKey(const ValueKey('hover-preview'));

  testWidgets('folder preview appears after a long hover and lists items', (
    tester,
  ) async {
    final mouse = await pump(tester, entry(root.path, directory: true));
    await mouse.moveTo(tester.getCenter(find.byType(SizedBox).last));
    await tester.pump(HoverPreview.delay ~/ 2);
    expect(preview, findsNothing);
    await tester.pump(HoverPreview.delay);
    expect(preview, findsOneWidget);
    for (var i = 0; i < 20 && find.text('f0.txt').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('f0.txt'), findsOneWidget);
    expect(find.text('f9.txt'), findsNothing);
    expect(find.text('+ 2 autres'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(preview, findsOneWidget);
    await tester.pump(HoverPreview.exitGrace);
    expect(preview, findsNothing);
  });

  testWidgets('an open preview follows the hovered row without delay', (
    tester,
  ) async {
    Directory('${root.path}/sub').createSync();
    final rows = [
      entry(root.path, directory: true),
      entry('${root.path}/f0.txt'),
      entry('${root.path}/sub', directory: true),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final row in rows)
                HoverPreview(
                  key: ValueKey(row.entity.path),
                  entry: row,
                  child: const SizedBox(width: 200, height: 30),
                ),
            ],
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    addTearDown(mouse.removePointer);
    Offset rowAt(int i) =>
        tester.getCenter(find.byKey(ValueKey(rows[i].entity.path)));
    String? shownPath() {
      final card = find.byKey(const ValueKey('hover-preview'));
      if (card.evaluate().isEmpty) return null;
      final key = tester
          .widget(
            find
                .ancestor(
                  of: card,
                  matching: find.byWidgetPredicate(
                    (w) => w.key is ValueKey<String>,
                  ),
                )
                .first,
          )
          .key;
      return (key! as ValueKey<String>).value;
    }

    await mouse.moveTo(rowAt(0));
    await tester.pump(HoverPreview.delay * 2);
    expect(shownPath(), rows[0].entity.path);
    // Ligne sans aperçu : la carte se masque, le mode reste actif.
    await mouse.moveTo(rowAt(1));
    await tester.pump(HoverPreview.exitGrace * 2);
    expect(shownPath(), isNull);
    await mouse.moveTo(rowAt(2));
    await tester.pump();
    expect(shownPath(), rows[2].entity.path);
  });

  testWidgets('a click hides the preview; other files have none', (
    tester,
  ) async {
    final mouse = await pump(tester, entry(root.path, directory: true));
    final center = tester.getCenter(find.byType(SizedBox).last);
    await mouse.moveTo(center);
    await tester.pump(HoverPreview.delay * 2);
    expect(preview, findsOneWidget);
    await mouse.down(center);
    await tester.pump();
    expect(preview, findsNothing);
    await mouse.up();

    expect(HoverPreview.supports(entry('${root.path}/a.PNG')), isTrue);
    expect(HoverPreview.supports(entry('${root.path}/f0.txt')), isFalse);
  });
}
