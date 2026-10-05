import 'dart:convert';
import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/models/explorer_location.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/theme/surffile_appearance_slots.dart';
import 'package:super_container_layout/theme/container_fill.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/neon_style.dart';
import 'package:surf_file/widgets/dialogs/appearance_settings.dart';
import 'package:super_container_layout/widgets/container_style_editor.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_sidebar.dart';
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
      final appearance = Appearance(
        styles: {
          'selectedCard': custom,
          'selectedFolder': custom,
          'card': ContainerStyle(neon: NeonStyle(enabled: true)),
        },
      );
      await AppearanceStore().save(appearance);
      final saved = await AppearanceStore().load();
      expect(saved.styles['selectedCard']!.toJson(), custom.toJson());
      expect(saved.styles['selectedFolder']!.toJson(), custom.toJson());
      expect((saved.style('card').neon ?? const NeonStyle()).enabled, isTrue);
      final changed = appearance
          .withStyle('selectedCard', custom.copyWith(elevation: 11))
          .withStyle('selectedFolder', custom.copyWith(elevation: 12));
      expect(SurfFileAppearanceSlots.selectedCard.read(changed).elevation, 11);
      expect(SurfFileAppearanceSlots.selectedFolder.read(changed).elevation, 12);
      expect(changed.styles['selectedCard']!.fill.type, FillType.linear);
      final reset = changed
          .withStyle('selectedCard', null)
          .withStyle('selectedFolder', null);
      expect(reset.styles['selectedCard'], isNull);
      expect(reset.styles['selectedFolder'], isNull);
      expect((reset.style('card').neon ?? const NeonStyle()).enabled, isTrue);
      await AppearanceStore().save(Appearance());
      expect((await AppearanceStore().load()).styles['selectedCard'], isNull);
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
        Appearance(
          styles: {
            'selectedCard': custom,
            'card': ContainerStyle(neon: NeonStyle(enabled: true)),
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
      controller.value = controller.value.withStyle(
        'selectedCard',
        custom.copyWith(
          fill: const ContainerFill(),
          color: const Color(0x80112233),
        ),
      );
      await tester.pump();
      expect(material('second.txt', true).color, const Color(0x80112233));
      controller.value = controller.value.withStyle('selectedCard', null);
      await tester.pump();
      expect(material('second.txt', true).elevation, 0);
      controller.value = controller.value.withStyle(
        'selectedCard',
        custom.copyWith(neon: const NeonStyle()),
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
      expect((controller.value.style('card').neon ?? const NeonStyle()).enabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sidebar selected style follows navigation, including neon', (
    tester,
  ) async {
    final controller = ValueNotifier(
      Appearance(
        styles: {
        'selectedFolder': ContainerStyle(
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
        },
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
    controller.value = controller.value.withStyle('selectedFolder', null);
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
        Appearance(
          styles: {
            'card': ContainerStyle(elevation: 5),
            'selectedFolder': ContainerStyle(elevation: 7),
          },
        ),
      );
      final initial = controller.value;
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
      await tester.ensureVisible(find.text(cards
          ? 'Style des cartes sélectionnées'
          : 'Style de la sélection du panneau gauche'));
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
          ? SurfFileAppearanceSlots.selectedCard.read(controller.value)
          : SurfFileAppearanceSlots.selectedFolder.read(controller.value);
      expect(current().elevation, cards ? 5 : 7);
      final controls = tester.widget<ContainerStyleEditor>(find.byType(ContainerStyleEditor));
      controls.onRadiusChanged!(36);
      controls.onBorderWidthChanged!(4);
      controls.onElevationChanged!(16);
      controls.onShadowOpacityChanged!(.6);
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
      expect(controller.value.styles['selectedCard'], isNull);
      expect(controller.value.styles['selectedFolder']?.toJson(), cards ? initial.styles['selectedFolder']?.toJson() : null);
      expect(current().elevation, cards ? 5 : 0);
      expect(controller.value.style('card').toJson(), initial.style('card').toJson());
      expect(tester.takeException(), isNull);
    });
  }
}
