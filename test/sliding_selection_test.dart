import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';

void main() {
  final entries = [
    for (var i = 0; i < 50; i++)
      ExplorerEntry(
        entity: File('file$i.txt'),
        name: 'file$i.txt',
        isDirectory: false,
        modified: DateTime(2026),
        size: i,
      ),
  ];
  const highlightKey = ValueKey('sliding-selection');
  double top(WidgetTester tester) =>
      tester.widget<Positioned>(find.byKey(highlightKey)).top!;

  Future<void> show(
    WidgetTester tester,
    String? selected, {
    List<ExplorerEntry>? visible,
    bool reduceMotion = false,
    Appearance appearance = const Appearance(),
  }) {
    final controller = ValueNotifier(appearance);
    addTearDown(controller.dispose);
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: AppearanceScope(
            controller: controller,
            child: Scaffold(
              body: ExplorerEntriesView(
                entries: visible ?? entries,
                gridView: false,
                selectedPath: selected,
                onSelected: (_) {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('highlight travels for 250 ms without moving text', (
    tester,
  ) async {
    await show(tester, 'file0.txt');
    expect(top(tester), 2);
    final textPosition = tester.getTopLeft(find.text('file3.txt'));
    await show(tester, 'file3.txt');
    expect(top(tester), 2);
    await tester.pump(const Duration(milliseconds: 125));
    expect(
      top(tester),
      closeTo(2 + 150 * Curves.easeInOutCubic.transform(.5), .01),
    );
    expect(tester.getTopLeft(find.text('file3.txt')), textPosition);
    await tester.pump(const Duration(milliseconds: 125));
    expect(top(tester), 152);
    expect(tester.getTopLeft(find.text('file3.txt')), textPosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid selections retarget from the current position', (
    tester,
  ) async {
    await show(tester, 'file0.txt');
    await show(tester, 'file4.txt');
    await tester.pump(const Duration(milliseconds: 125));
    final current = top(tester);
    await show(tester, 'file1.txt');
    expect(top(tester), closeTo(current, .01));
    await tester.pump(const Duration(milliseconds: 250));
    expect(top(tester), 52);
  });

  testWidgets('scrolling tracks the content and supports offscreen selection', (
    tester,
  ) async {
    await show(tester, 'file0.txt');
    await show(tester, 'file30.txt');
    await tester.pumpAndSettle();
    expect(top(tester), 1502);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(1400);
    await tester.pump();
    expect(top(tester), 102);
    expect(find.text('file30.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter, clear and reduced motion never slide to stale indices', (
    tester,
  ) async {
    await show(tester, null);
    expect(find.byKey(highlightKey), findsNothing);
    await show(tester, 'file3.txt');
    expect(top(tester), 152);
    await show(tester, 'file3.txt', visible: [entries[3], entries[0]]);
    expect(top(tester), 2);
    await show(
      tester,
      'file0.txt',
      visible: [entries[3], entries[0]],
      reduceMotion: true,
    );
    expect(top(tester), 52);
    await show(tester, null, visible: [entries[3], entries[0]]);
    expect(find.byKey(highlightKey), findsNothing);
    await show(
      tester,
      'file0.txt',
      appearance: const Appearance(
        rowHeight: 80,
        spacing: 24,
        selectedCardStyle: ContainerStyle(elevation: 9, radius: 22),
      ),
    );
    expect(top(tester), 2);
    final surface = tester.widget<Material>(
      find.descendant(
        of: find.byKey(highlightKey),
        matching: find.byType(Material),
      ),
    );
    expect(surface.elevation, 9);
    expect(surface.borderRadius, BorderRadius.circular(22));
    expect(tester.getSize(find.byKey(highlightKey)).height, 80);
    expect(tester.takeException(), isNull);
  });
}
