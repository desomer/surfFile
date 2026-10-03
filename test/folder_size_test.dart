import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/services/folder_size_service.dart';
import 'package:surf_file/widgets/folder_size_cell.dart';

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
}
