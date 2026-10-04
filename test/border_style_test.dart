import 'dart:convert';
import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:super_container_layout/services/appearance_store.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/appearance_settings.dart';
import 'package:super_container_layout/widgets/container_style_editor.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';

void main() {
  const color = Color(0x8000FFFF);
  test('border preferences persist, reset and reject invalid data', () {
    const style = ContainerStyle(borderColor: color, borderWidth: 3);
    const appearance = Appearance(
      cardStyle: ContainerStyle(borderColor: color, borderWidth: 2),
      backgroundStyle: ContainerStyle(borderColor: color, borderWidth: 4),
      sidebarStyle: style,
      pathBarStyle: style,
      selectedCardStyle: style,
      selectedFolderStyle: style,
    );
    final saved = AppearanceStore.decode(AppearanceStore.encode(appearance));
    expect(saved.cardStyle.borderColor, color);
    expect(saved.backgroundStyle.borderColor, color);
    expect(saved.backgroundStyle.borderWidth, 4);
    for (final panel in [
      saved.sidebarStyle,
      saved.pathBarStyle,
      saved.selectedCardStyle!,
      saved.selectedFolderStyle!,
    ]) {
      expect(panel.borderColor, color);
      expect(panel.borderWidth, 3);
    }
    expect(style.copyWith(resetBorderColor: true).borderColor, isNull);
    final reset = saved.copyWith(
      cardStyle: saved.cardStyle.copyWith(resetBorderColor: true),
      backgroundStyle: saved.backgroundStyle.copyWith(resetBorderColor: true),
    );
    expect(reset.cardStyle.borderColor, isNull);
    expect(reset.backgroundStyle.borderColor, isNull);
    final oldStyle = style.toJson()..remove('borderColor');
    expect(ContainerStyle.fromJson(oldStyle).borderColor, isNull);
    for (final invalid in [-1, 0x100000000, 'cyan']) {
      expect(
        () =>
            ContainerStyle.fromJson(style.toJson()..['borderColor'] = invalid),
        throwsFormatException,
      );
      for (final key in ['cardStyle', 'backgroundStyle']) {
        expect(
          () => AppearanceStore.decode(
            jsonEncode({
              'version': 2,
              'mode': 'light',
              key: style.toJson()..['borderColor'] = invalid,
            }),
          ),
          throwsFormatException,
        );
      }
    }
    for (final invalid in [-1, 5, 'wide']) {
      expect(
        () => AppearanceStore.decode(
          jsonEncode({
            'version': 2,
            'mode': 'light',
            'backgroundStyle': style.toJson()..['borderWidth'] = invalid,
          }),
        ),
        throwsFormatException,
      );
    }
  });

  for (final section in [
    'Style des cartes',
    'Style des cartes sélectionnées',
    'Style de la sélection du panneau gauche',
    'Style du panneau de gauche',
    'Style de la barre du chemin',
    'Fond de l’application',
  ]) {
    testWidgets('border editor updates preview and saved style: $section', (
      tester,
    ) async {
      final controller = ValueNotifier(const Appearance());
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(const Size(1100, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppearanceScope(
          controller: controller,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => AppearanceSettings.show(context),
                  child: const Text('Réglages'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Réglages'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(section));
      await tester.pumpAndSettle();
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
      final editor = tester.widget<ContainerStyleEditor>(
        find.byType(ContainerStyleEditor),
      );
      editor.onBorderWidthChanged!(3);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Couleur de la bordure'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Couleur de la bordure'));
      await tester.pumpAndSettle();
      final picker = tester.widget<ColorPicker>(find.byType(ColorPicker));
      expect(picker.enableOpacity, isTrue);
      picker.onColorChanged(color);
      await tester.pumpAndSettle();
      BoxDecoration preview() =>
          tester
                  .widget<Container>(find.byKey(ValueKey('preview-$section')))
                  .decoration!
              as BoxDecoration;
      expect(preview().border!.top.color, color);
      expect(preview().border!.top.width, 3);
      final saved = AppearanceStore.decode(
        AppearanceStore.encode(controller.value),
      );
      final borderColor = switch (section) {
        'Style des cartes' => saved.cardStyle.borderColor,
        'Style des cartes sélectionnées' =>
          saved.selectedCardStyle!.borderColor,
        'Style de la sélection du panneau gauche' =>
          saved.selectedFolderStyle!.borderColor,
        'Style du panneau de gauche' => saved.sidebarStyle.borderColor,
        'Style de la barre du chemin' => saved.pathBarStyle.borderColor,
        _ => saved.backgroundStyle.borderColor,
      };
      expect(borderColor, color);
      tester
          .widget<ContainerStyleEditor>(find.byType(ContainerStyleEditor))
          .onBorderWidthChanged!(0);
      await tester.pumpAndSettle();
      expect(preview().border!.top.style, BorderStyle.none);
      final automatic = find.byKey(ValueKey('automatic-border-$section'));
      await tester.ensureVisible(automatic);
      await tester.pumpAndSettle();
      await tester.tap(automatic);
      await tester.pumpAndSettle();
      expect(preview().border!.top.color, isNot(color));
      expect(tester.takeException(), isNull);
    });
  }

  for (final grid in [false, true]) {
    testWidgets('unselected card border renders in grid=$grid', (tester) async {
      final controller = ValueNotifier(
        const Appearance(
          cardStyle: ContainerStyle(borderColor: color, borderWidth: 3),
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        AppearanceScope(
          controller: controller,
          child: MaterialApp(
            home: Scaffold(
              body: ExplorerEntriesView(
                entries: [
                  ExplorerEntry(
                    entity: File('file.txt'),
                    name: 'file.txt',
                    isDirectory: false,
                    modified: DateTime(2026),
                    size: 1,
                  ),
                ],
                gridView: grid,
                selectedPath: null,
                onSelected: (_) {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      BorderSide border() {
        if (grid) {
          final material = tester.widget<Material>(
            find
                .ancestor(
                  of: find.text('file.txt'),
                  matching: find.byType(Material),
                )
                .first,
          );
          return (material.shape! as RoundedRectangleBorder).side;
        }
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: find.byKey(const ValueKey('row-surface-file.txt')),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        return decoration.border!.top;
      }

      expect(border().color, color);
      expect(border().width, 3);
      controller.value = controller.value.copyWith(
        cardStyle: controller.value.cardStyle.copyWith(borderWidth: 0),
      );
      await tester.pump();
      expect(border().style, BorderStyle.none);
      expect(tester.takeException(), isNull);
    });
  }
}
