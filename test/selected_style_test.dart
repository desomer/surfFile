import 'dart:convert';
import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/models/explorer_location.dart';
import 'package:super_container_layout/services/appearance_store.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_fill.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/neon_style.dart';
import 'package:super_container_layout/widgets/appearance_settings.dart';
import 'package:super_container_layout/widgets/container_style_editor.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer_sidebar.dart';
import 'package:super_container_layout/widgets/neon_surface.dart';

void main() {
  const custom = ContainerStyle(
    color: Color(0x80102030),
    fill: ContainerFill(
      type: FillType.linear,
      start: Color(0xFF102030),
      end: Color(0xFF304050),
    ),
    radius: 24,
    borderWidth: 3,
    borderColor: Color(0x8000FFFF),
    elevation: 8,
    shadowOpacity: .4,
  );

  test(
    'selection styles persist, validate and reset to current defaults',
    () async {
      SharedPreferences.setMockInitialValues({});
      const appearance = Appearance(
        selectedCardStyle: custom,
        selectedFolderStyle: custom,
        cardStyle: ContainerStyle(neon: NeonStyle(enabled: true)),
      );
      await AppearanceStore().save(appearance);
      final saved = await AppearanceStore().load();
      expect(saved.selectedCardStyle!.toJson(), custom.toJson());
      expect(saved.selectedFolderStyle!.toJson(), custom.toJson());
      expect(saved.cardNeon.enabled, isTrue);
      final changed = appearance.copyWith(
        selectedCardStyle: custom.copyWith(elevation: 11),
        selectedFolderStyle: custom.copyWith(elevation: 12),
      );
      expect(changed.cardElevation(selected: true), 11);
      expect(changed.effectiveSelectedFolderStyle.elevation, 12);
      expect(changed.selectedCardStyle!.fill.type, FillType.linear);
      final reset = changed.copyWith(
        resetSelectedCardStyle: true,
        resetSelectedFolderStyle: true,
      );
      expect(reset.selectedCardStyle, isNull);
      expect(reset.selectedFolderStyle, isNull);
      expect(reset.cardNeon.enabled, isTrue);
      await AppearanceStore().save(const Appearance());
      expect((await AppearanceStore().load()).selectedCardStyle, isNull);
      for (final field in ['selectedCardStyle', 'selectedFolderStyle']) {
        for (final invalid in [
          'bad',
          custom.toJson()..['radius'] = 37,
          custom.toJson()..['borderWidth'] = 5,
          custom.toJson()..['elevation'] = -1,
          custom.toJson()..['shadowOpacity'] = .7,
          custom.toJson()..['color'] = -1,
          custom.toJson()..['fill'] = {'type': 'bad'},
        ]) {
          expect(
            () => AppearanceStore.decode(
              jsonEncode({'version': 2, 'mode': 'light', field: invalid}),
            ),
            throwsFormatException,
          );
        }
      }
    },
  );

  for (final grid in [false, true]) {
    testWidgets('custom card selection renders and follows selection: $grid', (
      tester,
    ) async {
      final controller = ValueNotifier(
        const Appearance(
          selectedCardStyle: custom,
          cardStyle: ContainerStyle(neon: NeonStyle(enabled: true)),
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
      String? clicked;
      Future<void> show(String selected) => tester.pumpWidget(
        AppearanceScope(
          controller: controller,
          child: MaterialApp(
            home: Scaffold(
              body: ExplorerEntriesView(
                entries: entries,
                gridView: grid,
                selectedPath: selected,
                onSelected: (path) => clicked = path,
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      Finder surface(String name, bool selected) => grid
          ? find.ancestor(
              of: find.text(name),
              matching: find.byType(NeonSurface),
            )
          : find.byKey(
              ValueKey(selected ? 'sliding-selection' : 'row-surface-$name'),
            );
      Material material(String name, bool selected) => tester.widget<Material>(
        find
            .descendant(
              of: surface(name, selected),
              matching: find.byType(Material),
            )
            .first,
      );
      void checkSelected(String name) {
        final selected = surface(name, true);
        expect(material(name, true).color, Colors.transparent);
        expect(material(name, true).elevation, 8);
        expect(
          material(name, true).shadowColor,
          Colors.black.withValues(alpha: .4),
        );
        final decoration = grid
            ? tester
                      .widget<Ink>(
                        find.descendant(
                          of: selected,
                          matching: find.byType(Ink),
                        ),
                      )
                      .decoration!
                  as BoxDecoration
            : tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: selected,
                              matching: find.byType(DecoratedBox),
                            )
                            .last,
                      )
                      .decoration
                  as BoxDecoration;
        expect(decoration.gradient!.colors, [
          custom.fill.start,
          custom.fill.end,
        ]);
        expect(decoration.borderRadius, BorderRadius.circular(24));
        expect(
          tester
              .widget<NeonSurface>(
                grid
                    ? selected
                    : find.descendant(
                        of: selected,
                        matching: find.byType(NeonSurface),
                      ),
              )
              .radius,
          24,
        );
        expect(
          tester.widget<Text>(find.text(name)).style!.color,
          custom.foreground,
        );
        if (grid) {
          final shape = material(name, true).shape! as RoundedRectangleBorder;
          expect(shape.side.width, 3);
          expect(shape.side.color, custom.borderColor);
        } else {
          expect(decoration.border!.top.width, 3);
          expect(decoration.border!.top.color, custom.borderColor);
        }
      }

      await show('first.txt');
      checkSelected('first.txt');
      expect(material('second.txt', false).elevation, 0);
      await tester.tap(find.text('second.txt'), kind: PointerDeviceKind.mouse);
      expect(clicked, 'second.txt');
      await show('second.txt');
      await tester.pumpAndSettle();
      checkSelected('second.txt');
      expect(material('first.txt', false).elevation, 0);
      controller.value = controller.value.copyWith(
        selectedCardStyle: custom.copyWith(
          fill: const ContainerFill(),
          color: const Color(0x80112233),
        ),
      );
      await tester.pump();
      expect(material('second.txt', true).color, const Color(0x80112233));
      controller.value = controller.value.copyWith(
        resetSelectedCardStyle: true,
      );
      await tester.pump();
      expect(material('second.txt', true).elevation, 0);
      controller.value = controller.value.copyWith(
        selectedCardStyle: custom.copyWith(neon: const NeonStyle()),
      );
      await tester.pump();
      final selectedSurface = surface('second.txt', true);
      final selectedNeon = tester.widget<NeonSurface>(
        grid
            ? selectedSurface
            : find.descendant(
                of: selectedSurface,
                matching: find.byType(NeonSurface),
              ),
      );
      expect(selectedNeon.style.enabled, isFalse);
      expect(controller.value.cardNeon.enabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sidebar selected style follows navigation, including neon', (
    tester,
  ) async {
    final controller = ValueNotifier(
      const Appearance(
        selectedFolderStyle: ContainerStyle(
          color: Color(0x80102030),
          fill: ContainerFill(
            type: FillType.linear,
            start: Color(0xFF102030),
            end: Color(0xFF304050),
          ),
          radius: 24,
          borderWidth: 3,
          borderColor: Color(0x8000FFFF),
          elevation: 8,
          shadowOpacity: .4,
          neon: NeonStyle(enabled: true),
        ),
      ),
    );
    addTearDown(controller.dispose);
    String? clicked;
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
              onLocationSelected: (path) => clicked = path,
            ),
          ),
        ),
      ),
    );
    Finder surface(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(NeonSurface));
    void check(String name) {
      final neon = tester.widget<NeonSurface>(surface(name));
      expect(neon.radius, 24);
      expect(neon.style.enabled, isTrue);
      final material = tester.widget<Material>(
        find.descendant(of: surface(name), matching: find.byType(Material)),
      );
      expect(material.color, Colors.transparent);
      expect(material.elevation, 8);
      expect(material.shadowColor, Colors.black.withValues(alpha: .4));
      final ink = tester.widget<Ink>(
        find.descendant(of: surface(name), matching: find.byType(Ink)),
      );
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.gradient!.colors, [custom.fill.start, custom.fill.end]);
      expect(decoration.border!.top.width, 3);
      expect(
        tester.widget<Text>(find.text(name)).style!.color,
        custom.foreground,
      );
      final icon = tester.widget<Icon>(
        find.descendant(of: surface(name), matching: find.byType(Icon)),
      );
      expect(icon.color, custom.foreground);
    }

    await show('docs');
    check('Documents');
    expect(tester.widget<NeonSurface>(surface('Images')).radius, 9);
    await tester.tap(find.text('Images'));
    expect(clicked, 'images');
    await show('images');
    check('Images');
    expect(
      tester.widget<NeonSurface>(surface('Documents')).style.enabled,
      isFalse,
    );
    controller.value = controller.value.copyWith(
      resetSelectedFolderStyle: true,
    );
    await tester.pump();
    expect(tester.widget<NeonSurface>(surface('Images')).radius, 9);
    expect(tester.takeException(), isNull);
  });

  for (final cards in [true, false]) {
    testWidgets('selection popup edits and resets only its style: $cards', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1100, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ValueNotifier(
        const Appearance(
          cardStyle: ContainerStyle(elevation: 5),
          selectedFolderStyle: ContainerStyle(elevation: 7),
        ),
      );
      addTearDown(controller.dispose);
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
      await tester.tap(
        find.text(
          cards
              ? 'Style des cartes sélectionnées'
              : 'Style de la sélection du panneau gauche',
        ),
      );
      await tester.pumpAndSettle();
      ContainerStyle current() => cards
          ? controller.value.effectiveSelectedCardStyle
          : controller.value.effectiveSelectedFolderStyle;
      expect(current().elevation, cards ? 5 : 7);
      for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
        slider.onChanged!(slider.max);
      }
      await tester.pumpAndSettle();
      expect(current().radius, 36);
      expect(current().borderWidth, 4);
      expect(current().elevation, 16);
      expect(current().shadowOpacity, .6);
      await tester.tap(find.text('Couleur unie').last);
      await tester.pumpAndSettle();
      tester
          .widget<ColorPicker>(find.byType(ColorPicker))
          .onColorChanged(const Color(0x80112233));
      await tester.pumpAndSettle();
      expect(current().color, const Color(0x80112233));
      final editor = tester.widget<ContainerStyleEditor>(
        find.byType(ContainerStyleEditor),
      );
      editor.onChanged(custom.fill);
      await tester.pumpAndSettle();
      expect(current().fill.type, FillType.linear);
      editor.onChanged(const ContainerFill());
      await tester.pumpAndSettle();
      final automatic = find.text('Couleur unie automatique');
      await tester.ensureVisible(automatic);
      await tester.pumpAndSettle();
      await tester.tap(automatic);
      await tester.pumpAndSettle();
      expect(current().color, isNull);
      final reset = find.text('Réinitialiser ce style');
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(controller.value.selectedCardStyle, isNull);
      expect(controller.value.selectedFolderStyle, isNull);
      expect(current().elevation, cards ? 5 : 0);
      expect(controller.value.cardStyle.radius, 13);
      expect(tester.takeException(), isNull);
    });
  }
}
