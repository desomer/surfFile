import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/models/explorer_location.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/theme/surffile_appearance_slots.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_sidebar.dart';

void main() {
  test('selected cards follow general elevation until customized', () {
    final appearance = Appearance(
      styles: const {'card': ContainerStyle(elevation: 6)},
    );
    expect(SurfFileAppearanceSlots.selectedCard.read(appearance).elevation, 6);
    final custom = appearance
        .withStyle('selectedCard', const ContainerStyle(elevation: 12))
        .withStyle('selectedFolder', const ContainerStyle(elevation: 8))
        .withStyle('card', const ContainerStyle(elevation: 3));
    expect(SurfFileAppearanceSlots.selectedCard.read(custom).elevation, 12);
    expect(custom.style('card').elevation, 3);
    expect(SurfFileAppearanceSlots.selectedFolder.read(custom).elevation, 8);
    expect(SurfFileAppearanceSlots.selectedFolder.read(Appearance()).elevation, 0);
  });

  for (final grid in [false, true]) {
    testWidgets('selected elevation is independent in grid=$grid', (
      tester,
    ) async {
      final controller = ValueNotifier(
        Appearance(
          styles: {
            'card': ContainerStyle(elevation: 2),
            'selectedCard': ContainerStyle(elevation: 10),
          },
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
      controller.value = defaultSurfFileAppearance();
      await tester.pump();
      expect(elevation('second.txt'), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('only selected sidebar folder has elevation', (tester) async {
    final controller = ValueNotifier(
      Appearance(
        styles: {
          'card': ContainerStyle(shadowOpacity: .4),
          'selectedFolder': ContainerStyle(elevation: 9),
        },
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
    expect(item('Documents').shadowColor, Colors.black.withValues(alpha: controller.value.style('selectedFolder').shadowOpacity));
    expect(item('Images').elevation, 0);
    await show('images');
    expect(item('Documents').elevation, 0);
    expect(item('Images').elevation, 9);
    controller.value = defaultSurfFileAppearance();
    await tester.pump();
    expect(item('Images').elevation, 0);
    expect(tester.takeException(), isNull);
  });
}
