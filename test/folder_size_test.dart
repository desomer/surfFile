import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/services/folder_size_service.dart';
import 'package:surf_file/widgets/folder_size_cell.dart';
import 'package:surf_file/widgets/folder_size_indicator.dart';

void main() {
  late Directory root;

  setUp(() {
    FolderSizeService.reset();
    root = Directory.systemTemp.createTempSync('folder_size_');
    File('${root.path}/a.bin').writeAsBytesSync(List.filled(100, 0));
    Directory('${root.path}/sub/deep').createSync(recursive: true);
    File('${root.path}/sub/b.bin').writeAsBytesSync(List.filled(50, 0));
    File('${root.path}/sub/deep/c.bin').writeAsBytesSync(List.filled(25, 0));
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('folderSizeSync sums files recursively', () {
    expect(FolderSizeService.folderSizeSync(root.path), 175);
  });

  test('size sort orders folders by computed size numerically', () async {
    final dirs = [
      for (final name in ['big', 'small', 'unknown'])
        Directory('${root.path}/s_$name')..createSync(),
    ];
    File('${dirs[0].path}/f').writeAsBytesSync(List.filled(1000, 0));
    File('${dirs[1].path}/f').writeAsBytesSync(List.filled(90, 0));
    await FolderSizeService.compute(dirs[0].path);
    await FolderSizeService.compute(dirs[1].path);
    final entries = [
      for (final d in dirs)
        ExplorerEntry(
          entity: d,
          name: d.path.split(RegExp(r'[\\/]')).last,
          isDirectory: true,
          modified: DateTime(2020),
          size: 0,
        ),
    ];
    sortExplorerEntries(entries, ExplorerSort.size, ascending: true);
    expect(entries.map((e) => e.name), ['s_unknown', 's_small', 's_big']);
    sortExplorerEntries(entries, ExplorerSort.size, ascending: false);
    expect(entries.map((e) => e.name), ['s_big', 's_small', 's_unknown']);
  });

  testWidgets('shows the chosen size indicator, relative to the biggest', (
    tester,
  ) async {
    final a = Directory('${root.path}/ia')..createSync();
    final b = Directory('${root.path}/ib')..createSync();
    File('${a.path}/f').writeAsBytesSync(List.filled(100, 0));
    File('${b.path}/f').writeAsBytesSync(List.filled(25, 0));
    await tester.runAsync(() async {
      await FolderSizeService.compute(a.path);
      await FolderSizeService.compute(b.path);
    });
    expect(FolderSizeIndicator.ratio(b.path, [a.path, b.path]), .25);
    addTearDown(() => FolderSizeIndicator.mode.value = FolderSizeDisplay.bar);

    Future<void> show(FolderSizeDisplay display) async {
      FolderSizeIndicator.mode.value = display;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const FolderSizeDisplayButton(),
                FolderSizeCell(
                  path: b.path,
                  style: const TextStyle(),
                  siblingFolders: () => [a.path, b.path],
                ),
                SizedBox(
                  height: 30,
                  child: FolderSizeRowBackground(
                    path: b.path,
                    siblings: () => [a.path, b.path],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    await show(FolderSizeDisplay.bar);
    expect(find.byKey(const ValueKey('folder-size-bar')), findsOneWidget);
    await show(FolderSizeDisplay.dot);
    expect(find.byKey(const ValueKey('folder-size-dot')), findsOneWidget);
    await show(FolderSizeDisplay.pie);
    expect(find.byKey(const ValueKey('folder-size-pie')), findsOneWidget);
    await show(FolderSizeDisplay.background);
    expect(
      find.byKey(const ValueKey('folder-size-background')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('folder-size-bar')), findsNothing);
    await show(FolderSizeDisplay.none);
    expect(find.byKey(const ValueKey('folder-size-background')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('folder-size-display-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('folder-size-display-pie')));
    await tester.pumpAndSettle();
    expect(FolderSizeIndicator.mode.value, FolderSizeDisplay.pie);
    expect(find.byKey(const ValueKey('folder-size-pie')), findsOneWidget);
  });

  testWidgets('hovering the progress shows a cross that cancels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FolderSizeCell(path: root.path, style: const TextStyle()),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('folder-size-compute')));
    await tester.pump();
    expect(find.byKey(const ValueKey('folder-size-cancel')), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('folder-size-progress'))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('folder-size-cancel')));
    await tester.pump();
    final state = FolderSizeService.of(root.path).value;
    expect(state.computing, isFalse);
    expect(state.bytes, isNull);
    expect(find.byKey(const ValueKey('folder-size-compute')), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    expect(FolderSizeService.of(root.path).value.bytes, isNull);
  });

  testWidgets('tapping the calculator computes the size in an isolate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FolderSizeCell(path: root.path, style: const TextStyle()),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('folder-size-compute')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-size-compute')));
    await tester.pump();
    expect(find.byKey(const ValueKey('folder-size-progress')), findsOneWidget);
    for (
      var i = 0;
      i < 100 && FolderSizeService.of(root.path).value.computing;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(FolderSizeService.of(root.path).value.bytes, 175);
    expect(find.byKey(const ValueKey('folder-size-compute')), findsNothing);
    expect(find.text('175 o'), findsOneWidget);
  });

  testWidgets('offers to compute the other folders once done', (tester) async {
    final other = Directory('${root.path}/other')..createSync();
    File('${other.path}/d.bin').writeAsBytesSync(List.filled(10, 0));
    final sub = '${root.path}/sub';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FolderSizeCell(
            path: sub,
            style: const TextStyle(),
            siblingFolders: () => [sub, other.path],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('folder-size-compute')));
    await tester.pump();
    final dialog = find.byKey(const ValueKey('folder-size-others-dialog'));
    for (var i = 0; i < 100 && dialog.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(dialog, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-size-others-confirm')));
    await tester.pump();
    for (
      var i = 0;
      i < 100 && FolderSizeService.of(other.path).value.bytes == null;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(FolderSizeService.of(other.path).value.bytes, 10);
  });
}
