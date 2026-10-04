import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/models/treemap_layout.dart';
import 'package:surf_file/services/folder_size_service.dart';
import 'package:surf_file/widgets/explorer_heatmap_view.dart';
import 'package:surf_file/widgets/explorer_view_toggle.dart';

void main() {
  group('squarifyTreemap', () {
    test('areas are proportional to weights and fill the bounds', () {
      const bounds = Rect.fromLTWH(0, 0, 400, 300);
      final weights = [60.0, 30.0, 6.0, 3.0, 1.0];
      final rects = squarifyTreemap(weights, bounds);
      expect(rects, hasLength(weights.length));
      final total = weights.reduce((a, b) => a + b);
      var area = 0.0;
      for (var i = 0; i < rects.length; i++) {
        final rectArea = rects[i].width * rects[i].height;
        expect(
          rectArea,
          closeTo(bounds.width * bounds.height * weights[i] / total, 1e-6),
        );
        expect(bounds.inflate(1e-6).contains(rects[i].topLeft), isTrue);
        expect(bounds.inflate(1e-6).contains(rects[i].bottomRight), isTrue);
        area += rectArea;
      }
      expect(area, closeTo(bounds.width * bounds.height, 1e-6));
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          final overlap = rects[i].intersect(rects[j]);
          expect(overlap.width <= 1e-6 || overlap.height <= 1e-6, isTrue);
        }
      }
    });

    test('handles empty input and empty bounds', () {
      expect(
        squarifyTreemap(const [], const Rect.fromLTWH(0, 0, 10, 10)),
        isEmpty,
      );
      expect(squarifyTreemap([1], Rect.zero), [Rect.zero]);
    });
  });

  group('ExplorerHeatmapView', () {
    late Directory root;

    setUp(() {
      FolderSizeService.reset();
      root = Directory.systemTemp.createTempSync('heatmap_');
    });

    tearDown(() => root.deleteSync(recursive: true));

    ExplorerEntry entryOf(FileSystemEntity entity, int size) => ExplorerEntry(
      entity: entity,
      name: entity.path.split(RegExp(r'[\\/]')).last,
      isDirectory: entity is Directory,
      modified: DateTime(2020),
      size: size,
    );

    testWidgets('computes sub-folder sizes and draws one tile per item', (
      tester,
    ) async {
      final file = File('${root.path}/big.bin')
        ..writeAsBytesSync(List.filled(4000, 0));
      final dir = Directory('${root.path}/sub')..createSync();
      File('${dir.path}/a').writeAsBytesSync(List.filled(1000, 0));
      File('${dir.path}/b').writeAsBytesSync(List.filled(500, 0));
      final empty = Directory('${root.path}/empty')..createSync();
      final entries = [entryOf(dir, 0), entryOf(empty, 0), entryOf(file, 4000)];
      final opened = <String>[];
      await tester.binding.setSurfaceSize(const Size(600, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExplorerHeatmapView(
              entries: entries,
              selectedPaths: {file.path},
              onOpen: (entry) => opened.add(entry.name),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (
          var i = 0;
          i < 100 && FolderSizeService.bytesOf(dir.path) == null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump();
      expect(FolderSizeService.bytesOf(dir.path), 1500);
      expect(find.byKey(ValueKey(file.path)), findsOneWidget);
      expect(find.byKey(ValueKey(dir.path)), findsOneWidget);
      // Dossier vide : aucune surface.
      expect(find.byKey(ValueKey(empty.path)), findsNothing);
      expect(find.text('Total : 5 Ko'), findsOneWidget);

      final fileTile = tester.getSize(find.byKey(ValueKey(file.path)));
      final dirTile = tester.getSize(find.byKey(ValueKey(dir.path)));
      expect(
        fileTile.width * fileTile.height,
        greaterThan(dirTile.width * dirTile.height * 2),
      );

      await tester.tap(find.byKey(ValueKey(dir.path)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(ValueKey(dir.path)));
      await tester.pump(const Duration(seconds: 1));
      expect(opened, ['sub']);
    });
  });

  testWidgets('view toggle exposes the heatmap button', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ExplorerViewToggle(
          gridView: false,
          onChanged: (_) => calls.add('grid'),
          onColumnViewChanged: (value) => calls.add('columns:$value'),
          heatmapView: false,
          onHeatmapViewChanged: (value) => calls.add('heatmap:$value'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('view-heatmap')));
    expect(calls, ['heatmap:true', 'columns:false']);
    calls.clear();
    await tester.tap(find.byKey(const ValueKey('view-list')));
    expect(calls, ['grid', 'columns:false', 'heatmap:false']);
  });
}
