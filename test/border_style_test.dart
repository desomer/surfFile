import 'dart:convert';
import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:surf_file/widgets/dialogs/appearance_settings.dart';
import 'package:super_container_layout/widgets/container_style_editor.dart';
import 'package:super_container_layout/widgets/styled_surface.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';

void main() {
  const color = Color(0x8000FFFF);
  test('border preferences persist, reset and reject invalid data', () {
    const style = ContainerStyle(borderColor: color, borderWidth: 3);
    final appearance = Appearance(
      styles: {
        'card': ContainerStyle(borderColor: color, borderWidth: 2),
        'background': ContainerStyle(borderColor: color, borderWidth: 4),
        'sidebar': style,
        'pathBar': style,
        'selectedCard': style,
        'selectedFolder': style,
      },
    );
    final saved = AppearanceStore.decode(AppearanceStore.encode(appearance));
    expect(saved.style('card').borderColor, color);
    expect(saved.style('background').borderColor, color);
    expect(saved.style('background').borderWidth, 4);
    for (final panel in [
      saved.style('sidebar'),
      saved.style('pathBar'),
      saved.styles['selectedCard']!,
      saved.styles['selectedFolder']!,
    ]) {
      expect(panel.borderColor, color);
      expect(panel.borderWidth, 3);
    }
    expect(style.copyWith(resetBorderColor: true).borderColor, isNull);
    final reset = saved
        .withStyle('card', saved.style('card').copyWith(resetBorderColor: true))
        .withStyle(
          'background',
          saved.style('background').copyWith(resetBorderColor: true),
        );
    expect(reset.style('card').borderColor, isNull);
    expect(reset.style('background').borderColor, isNull);
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
      final controller = ValueNotifier(Appearance());
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
      ContainerStyle preview() => tester.widget<StyledSurface>(
        find.descendant(of: find.byKey(ValueKey('preview-$section')),
          matching: find.byType(StyledSurface)),
      ).style;
      expect(preview().borderColor, color);
      expect(preview().borderWidth, 3);
      final saved = AppearanceStore.decode(
        AppearanceStore.encode(controller.value),
      );
      final borderColor = switch (section) {
        'Style des cartes' => saved.style('card').borderColor,
        'Style des cartes sélectionnées' =>
          saved.styles['selectedCard']!.borderColor,
        'Style de la sélection du panneau gauche' =>
          saved.styles['selectedFolder']!.borderColor,
        'Style du panneau de gauche' => saved.style('sidebar').borderColor,
        'Style de la barre du chemin' => saved.style('pathBar').borderColor,
        _ => saved.style('background').borderColor,
      };
      expect(borderColor, color);
      tester
          .widget<ContainerStyleEditor>(find.byType(ContainerStyleEditor))
          .onBorderWidthChanged!(0);
      await tester.pumpAndSettle();
      expect(preview().borderWidth, 0);
      final automatic = find.byKey(ValueKey('automatic-border-$section'));
      await tester.ensureVisible(automatic);
      await tester.pumpAndSettle();
      await tester.tap(automatic);
      await tester.pumpAndSettle();
      expect(preview().borderColor, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final grid in [false, true]) {
    testWidgets('unselected card border renders in grid=$grid', (tester) async {
      final controller = ValueNotifier(
        Appearance(
          styles: {
            'card': ContainerStyle(borderColor: color, borderWidth: 3),
          },
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
      controller.value = controller.value.withStyle(
        'card',
        controller.value.style('card').copyWith(borderWidth: 0),
      );
      await tester.pump();
      expect(border().style, BorderStyle.none);
      expect(tester.takeException(), isNull);
    });
  }
}
