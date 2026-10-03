import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';
import 'package:surf_file/widgets/folder_hero_flight.dart';

void main() {
  for (final expand in [false, true]) {
    testWidgets('Hero flight interpolates bounds and completes: $expand',
        (tester) async {
      var completed = false;
      const source = Rect.fromLTWH(100, 200, 48, 48);
      const destination = Rect.fromLTWH(20, 30, 300, 200);
      await tester.pumpWidget(MaterialApp(
        home: FolderHeroFlight(
          source: source,
          destination: destination,
          duration: const Duration(milliseconds: 400),
          expand: expand,
          color: Colors.blue,
          onComplete: () => completed = true,
        ),
      ));
      Positioned flight() => tester.widget<Positioned>(find.byType(Positioned));
      expect(flight().left, source.left);
      expect(flight().width, source.width);
      await tester.pump(const Duration(milliseconds: 200));
      final progress = Curves.easeInOutCubic.transform(.5);
      expect(flight().left,
          closeTo(Rect.lerp(source, destination, progress)!.left, .001));
      expect(flight().width,
          closeTo(Rect.lerp(source, destination, progress)!.width, .001));
      expect(completed, isFalse);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 1));
      expect(flight().left, destination.left);
      expect(flight().width, destination.width);
      expect(completed, isTrue);
      expect(
          tester
              .widget<IgnorePointer>(find
                  .descendant(
                      of: find.byType(FolderHeroFlight),
                      matching: find.byType(IgnorePointer))
                  .first)
              .ignoring,
          isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final grid in [false, true]) {
    testWidgets('opening folder supplies card and icon geometry: $grid',
        (tester) async {
      Rect? card;
      Rect? icon;
      final entry = ExplorerEntry(
          entity: Directory('folder'),
          name: 'folder',
          isDirectory: true,
          modified: DateTime(2026),
          size: 0);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: ExplorerEntriesView(
          entries: [entry],
          gridView: grid,
          selectedPath: null,
          onSelected: (_) {},
          onOpen: (_) => fail('Missing bounds'),
          onOpenWithBounds: (opened, cardRect, iconRect) {
            expect(opened, entry);
            card = cardRect;
            icon = iconRect;
          },
        ),
      )));
      await tester.tap(find.text('folder'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('folder'));
      await tester.pumpAndSettle();
      expect(card, isNotNull);
      expect(icon, isNotNull);
      expect(card!.width, greaterThan(icon!.width));
      expect(card!.contains(icon!.center), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
