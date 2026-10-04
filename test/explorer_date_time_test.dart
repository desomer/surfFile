import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';

void main() {
  group('formatExplorerDateTime', () {
    test('adds the local time to the date, padded', () {
      expect(
        formatExplorerDateTime(DateTime(2026, 3, 5, 9, 7)),
        '05/03/2026 09:07',
      );
      expect(
        formatExplorerDateTime(DateTime(2022, 10, 31, 23, 59)),
        '31/10/2022 23:59',
      );
      expect(formatExplorerDateTime(DateTime(2026, 1, 2)), '02/01/2026 00:00');
    });

    test('converts UTC instants to local time', () {
      final utc = DateTime.utc(2026, 6, 15, 12, 30);
      final local = utc.toLocal();
      expect(
        formatExplorerDateTime(utc),
        '${formatExplorerDate(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}',
      );
    });
  });

  testWidgets('the modified column shows date and time in the list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entry = ExplorerEntry(
      entity: File('note.txt'),
      name: 'note.txt',
      isDirectory: false,
      modified: DateTime(2026, 3, 5, 9, 7),
      size: 12,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExplorerEntriesView(
            entries: [entry],
            gridView: false,
            selectedPath: null,
            onSelected: (_) {},
            onOpen: (_) {},
            onOpenWithBounds: (_, _, _) {},
          ),
        ),
      ),
    );
    expect(find.text('05/03/2026 09:07'), findsOneWidget);
    expect(find.text('05/03/2026'), findsNothing);
  });
}
