import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';

void main() {
  for (final mode in FileDragMode.values) {
    for (final grid in [false, true]) {
      for (final where in ['name', 'beside']) {
        testWidgets('double click opens an unselected item '
            '($mode, grid: $grid, $where)', (tester) async {
          final preferences = ValueNotifier(
            SurfFilePreferences(fileDragMode: mode),
          );
          final entries = [
            for (final name in ['a', 'b'])
              ExplorerEntry(
                entity: Directory('C:\\dbl\\$name'),
                name: name,
                isDirectory: true,
                modified: DateTime(2026),
                size: 1,
              ),
          ];
          var selection = <String>{};
          String? collapseTo;
          final opened = <String>[];
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SurfFilePreferencesScope(
                  controller: preferences,
                  child: StatefulBuilder(
                    builder: (context, setState) => ExplorerEntriesView(
                      entries: entries,
                      gridView: grid,
                      selectedPath: null,
                      selectedPaths: selection,
                      onSelectionChanged: (paths) =>
                          setState(() => selection = paths.toSet()),
                      onSelected: (path) => setState(() {
                        collapseTo = null;
                        if (selection.contains(path)) {
                          collapseTo = path;
                        } else {
                          selection = {path};
                        }
                      }),
                      onTapped: (path) {
                        final collapse =
                            collapseTo == path || !selection.contains(path);
                        collapseTo = null;
                        if (!collapse) return;
                        setState(() => selection = {path});
                      },
                      onOpen: (entry) => opened.add(entry.name),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final rect = tester.getRect(find.text('b'));
          final point = where == 'name'
              ? rect.center
              : grid
              ? rect.topCenter - const Offset(0, 20)
              : rect.centerRight + const Offset(60, 0);
          // Les horodatages des événements font foi, pas l'heure à laquelle
          // ils sont traités.
          Future<void> click(Duration at) async {
            final gesture = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await gesture.down(point, timeStamp: at);
            await tester.pump(const Duration(milliseconds: 30));
            await gesture.up(timeStamp: at + const Duration(milliseconds: 30));
            await tester.pump(const Duration(milliseconds: 60));
          }

          await click(Duration.zero);
          await click(const Duration(milliseconds: 450));
          await tester.pump(const Duration(seconds: 1));
          expect(opened, ['b']);

          // Trop espacés : deux clics simples.
          await click(const Duration(seconds: 5));
          await click(const Duration(milliseconds: 5700));
          await tester.pump(const Duration(seconds: 1));
          expect(opened, ['b']);
        });
      }
    }
  }
}
