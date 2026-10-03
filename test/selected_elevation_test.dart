import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/models/explorer_location.dart';
import 'package:surf_file/theme/appearance.dart';
import 'package:surf_file/theme/container_style.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer_sidebar.dart';

void main() {
  test('selected cards follow general elevation until customized', () {
    const appearance = Appearance(cardStyle: ContainerStyle(elevation: 6));
    expect(appearance.cardElevation(selected: true), 6);
    final custom = appearance
        .copyWith(
          selectedCardStyle: const ContainerStyle(elevation: 12),
          selectedFolderStyle: const ContainerStyle(elevation: 8),
        )
        .copyWith(cardStyle: const ContainerStyle(elevation: 3));
    expect(custom.cardElevation(selected: true), 12);
    expect(custom.cardElevation(selected: false), 3);
    expect(custom.effectiveSelectedFolderStyle.elevation, 8);
    expect(const Appearance().effectiveSelectedFolderStyle.elevation, 0);
  });

  for (final grid in [false, true]) {
    testWidgets('selected elevation is independent in grid=$grid', (
      tester,
    ) async {
      final controller = ValueNotifier(
        const Appearance(
          cardStyle: ContainerStyle(elevation: 2),
          selectedCardStyle: ContainerStyle(elevation: 10),
        ),
      );
      addTearDown(controller.dispose);
      final entries = [
        for (final name in ['first.txt', 'second.txt'])
          ExplorerEntry(
            entity: File(name),
            name: name,
            isDirectory: false,
            modified: DateTime(2026),
            size: 1,
          ),
      ];
      Future<void> show(String selected) => tester.pumpWidget(
        AppearanceScope(
          controller: controller,
          child: MaterialApp(
            home: Scaffold(
              body: ExplorerEntriesView(
                entries: entries,
                gridView: grid,
                selectedPath: selected,
                onSelected: (_) {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      double elevation(String name) {
        if (grid) {
          return tester
              .widget<Material>(
                find
                    .ancestor(
                      of: find.text(name),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .elevation;
        }
        final selected =
            tester
                .widget<ExplorerEntriesView>(find.byType(ExplorerEntriesView))
                .selectedPath ==
            name;
        return tester
            .widget<Material>(
              find.descendant(
                of: find.byKey(
                  ValueKey(
                    selected ? 'sliding-selection' : 'row-surface-$name',
                  ),
                ),
                matching: find.byType(Material),
              ),
            )
            .elevation;
      }

      await show('first.txt');
      expect(elevation('first.txt'), 10);
      expect(elevation('second.txt'), 2);
      await show('second.txt');
      expect(elevation('first.txt'), 2);
      expect(elevation('second.txt'), 10);
      controller.value = const Appearance();
      await tester.pump();
      expect(elevation('second.txt'), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('only selected sidebar folder has elevation', (tester) async {
    final controller = ValueNotifier(
      const Appearance(
        cardStyle: ContainerStyle(shadowOpacity: .4),
        selectedFolderStyle: ContainerStyle(elevation: 9),
      ),
    );
    addTearDown(controller.dispose);
    Future<void> show(String path) => tester.pumpWidget(
      AppearanceScope(
        controller: controller,
        child: MaterialApp(
          home: Scaffold(
            body: ExplorerSidebar(
              locations: const [
                ExplorerLocation('Documents', 'docs', Icons.folder),
                ExplorerLocation('Images', 'images', Icons.image),
              ],
              currentPath: path,
              onLocationSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    Material item(String name) => tester.widget<Material>(
      find.ancestor(of: find.text(name), matching: find.byType(Material)).first,
    );
    await show('docs');
    expect(item('Documents').elevation, 9);
    expect(item('Documents').shadowColor, Colors.black.withValues(alpha: .4));
    expect(item('Images').elevation, 0);
    await show('images');
    expect(item('Documents').elevation, 0);
    expect(item('Images').elevation, 9);
    controller.value = const Appearance();
    await tester.pump();
    expect(item('Images').elevation, 0);
    expect(tester.takeException(), isNull);
  });
}
