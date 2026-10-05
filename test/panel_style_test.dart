import 'dart:convert';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surf_file/models/explorer_location.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:super_container_layout/theme/container_fill.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:surf_file/widgets/dialogs/appearance_settings.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_breadcrumbs.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_sidebar.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_view_mode_bar.dart';
import 'package:super_container_layout/widgets/super_container.dart';
import 'package:super_container_layout/widgets/container_style_editor.dart';

void _ignoreGridChange(bool _) {}

void main() {
  const custom = ContainerStyle(
    color: Color(0x80112233),
    fill: ContainerFill(
      type: FillType.linear,
      start: Color(0x40223344),
      end: Color(0x80556677),
    ),
    radius: 18,
    borderWidth: 3,
    borderColor: Color(0x8000FFFF),
    elevation: 8,
    shadowOpacity: .4,
  );

  test('panel styles persist, validate, and default missing styles', () {
    final saved = AppearanceStore.decode(
      AppearanceStore.encode(
        Appearance(
          styles: {
            'sidebar': custom,
            'pathBar': custom,
            'explorerViewModeBar': custom,
          },
        ),
      ),
    );
    expect(saved.style('sidebar').toJson(), custom.toJson());
    expect(saved.style('pathBar').toJson(), custom.toJson());
    expect(saved.style('explorerViewModeBar').toJson(), custom.toJson());
    final json = jsonDecode(
      AppearanceStore.encode(Appearance()),
    ) as Map<String, dynamic>;
    json.remove('sidebarStyle');
    json.remove('pathBarStyle');
    json.remove('explorerViewModeBarStyle');
    final decoded = AppearanceStore.decode(jsonEncode(json));
    expect(decoded.style('sidebar').toJson(), const ContainerStyle().toJson());
    expect(decoded.style('pathBar').borderWidth, 1);
    expect(
      decoded.style('explorerViewModeBar').toJson(),
      const ContainerStyle().toJson(),
    );
    for (final field in [
      'sidebarStyle',
      'pathBarStyle',
      'explorerViewModeBarStyle',
    ]) {
      for (final invalid in [
        custom.toJson()..['radius'] = 37,
        custom.toJson()..['elevation'] = -1,
        custom.toJson()..['borderWidth'] = 5,
        custom.toJson()..['shadowOpacity'] = .7,
        custom.toJson()..['color'] = -1,
        custom.toJson()..['fill'] = {'type': 'invalid'},
      ]) {
        expect(
          () => AppearanceStore.decode(jsonEncode({...json, field: invalid})),
          throwsFormatException,
        );
      }
    }
  });

  test('panel styles are saved and restored from local preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppearanceStore();
    await store.save(
      Appearance(
        styles: {
          'sidebar': custom,
          'pathBar': custom,
          'explorerViewModeBar': custom,
        },
      ),
    );
    final restored = await store.load();
    expect(restored.style('sidebar').toJson(), custom.toJson());
    expect(restored.style('pathBar').toJson(), custom.toJson());
    expect(restored.style('explorerViewModeBar').toJson(), custom.toJson());
    await store.save(Appearance());
    final reset = await store.load();
    expect(reset.style('sidebar').toJson(), const ContainerStyle().toJson());
    expect(
      reset.style('pathBar').toJson(),
      const ContainerStyle(borderWidth: 1).toJson(),
    );
    expect(
      reset.style('explorerViewModeBar').toJson(),
      const ContainerStyle().toJson(),
    );
  });

  testWidgets('surfaces render styles live and retain navigation', (
    tester,
  ) async {
    final controller = ValueNotifier(
      Appearance(
        styles: {
          'sidebar': custom,
          'pathBar': custom,
          'explorerViewModeBar': custom,
          'selectedFolder': ContainerStyle(elevation: 9),
        },
      ),
    );
    addTearDown(controller.dispose);
    String? location;
    String? path;
    await tester.pumpWidget(
      AppearanceScope(
        controller: controller,
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ExplorerSidebar(
                  locations: const [
                    ExplorerLocation('Documents', 'docs', Icons.folder),
                    ExplorerLocation('Images', 'images', Icons.image),
                  ],
                  currentPath: 'docs',
                  onLocationSelected: (value) => location = value,
                ),
                Expanded(
                  child: Column(
                    children: [
                      ExplorerBreadcrumbs(
                        path: 'C:\\Users\\Documents',
                        onNavigate: (value) => path = value,
                      ),
                      ExplorerViewModeBar(
                        title: 'Fichiers',
                        itemCount: 2,
                        gridView: false,
                        onGridViewChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (final key in [
      'sidebar-surface',
      'path-bar-surface',
      'explorer-view-mode-bar-surface',
    ]) {
      final surface = find.byKey(ValueKey(key));
      final material = tester.widget<Material>(
        find.descendant(of: surface, matching: find.byType(Material)).first,
      );
      expect(material.elevation, 8);
      expect(material.color, Colors.transparent);
      expect(material.shadowColor, Colors.black.withValues(alpha: .4));
      final ink = tester.widget<Ink>(
        find.descendant(of: surface, matching: find.byType(Ink)).first,
      );
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.gradient!.colors, [custom.fill.start, custom.fill.end]);
      expect(decoration.borderRadius, BorderRadius.circular(18));
      expect(decoration.border!.top.width, 3);
      expect(decoration.border!.top.color, custom.borderColor);
    }
    expect(
      tester.widget<Text>(find.text('Images')).style!.color,
      custom.foreground,
    );
    expect(
      tester.widget<Text>(find.text('Users')).style!.color,
      custom.foreground,
    );
    expect(
      tester.widget<Text>(find.text('Fichiers')).style!.color,
      custom.foreground,
    );
    final selected = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Documents').first,
            matching: find.byType(Material),
          )
          .first,
    );
    expect(selected.elevation, 9);
    await tester.tap(find.text('Images'));
    expect(location, 'images');
    await tester.tap(find.text('Users'));
    expect(path, 'C:\\Users');
    controller.value = Appearance(
      styles: {
        'sidebar': ContainerStyle(color: Color(0x40112233)),
        'pathBar': ContainerStyle(color: Color(0x40112233)),
        'explorerViewModeBar': ContainerStyle(color: Color(0x40112233)),
      },
    );
    await tester.pump();
    for (final key in [
      'sidebar-surface',
      'path-bar-surface',
      'explorer-view-mode-bar-surface',
    ]) {
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, const Color(0x40112233));
      expect(material.elevation, 0);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('view mode bar opens its style editor in edit mode', (
    tester,
  ) async {
    final appearance = ValueNotifier(Appearance());
    final editMode = ValueNotifier(true);
    addTearDown(appearance.dispose);
    addTearDown(editMode.dispose);
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: StyleEditScope(
          controller: editMode,
          child: const MaterialApp(
            home: Scaffold(
              body: ExplorerViewModeBar(
                title: 'Fichiers',
                itemCount: 2,
                gridView: false,
                onGridViewChanged: _ignoreGridChange,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('explorer-view-mode-bar-surface')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Style de la barre des modes d’affichage'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  for (final sidebar in [true, false]) {
    testWidgets(
      'panel popup edits, restores automatic color and resets: $sidebar',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1100, 950));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = ValueNotifier(Appearance());
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
            sidebar
                ? 'Style du panneau de gauche'
                : 'Style de la barre du chemin',
          ),
        );
        await tester.pumpAndSettle();
        final controls = tester.widget<ContainerStyleEditor>(find.byType(ContainerStyleEditor));
        controls.onRadiusChanged!(36);
        controls.onBorderWidthChanged!(4);
        controls.onElevationChanged!(16);
        controls.onShadowOpacityChanged!(.6);
        await tester.pumpAndSettle();
        ContainerStyle current() => sidebar
            ? controller.value.style('sidebar')
            : controller.value.style('pathBar');
        expect(current().radius, 36);
        expect(current().borderWidth, 4);
        expect(current().elevation, 16);
        expect(current().shadowOpacity, .6);
        await tester.tap(find.text('Couleur unie').last);
        await tester.pumpAndSettle();
        tester
            .widget<ColorPicker>(find.byType(ColorPicker))
            .onColorChanged(const Color(0x40112233));
        await tester.pumpAndSettle();
        expect(current().color, const Color(0x40112233));
        await tester.ensureVisible(find.text('Couleur unie automatique'));
        await tester.tap(find.text('Couleur unie automatique'));
        await tester.pumpAndSettle();
        expect(current().color, isNull);
        await tester.ensureVisible(
          find.byType(DropdownButtonFormField<FillType>),
        );
        await tester.tap(find.byType(DropdownButtonFormField<FillType>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Radial').last);
        await tester.pumpAndSettle();
        expect(current().fill.type, FillType.radial);
        await tester.ensureVisible(find.text('Réinitialiser ce style'));
        await tester.tap(find.text('Réinitialiser ce style'));
        await tester.pumpAndSettle();
        expect(
          current().toJson(),
          (sidebar
                  ? const ContainerStyle()
                  : const ContainerStyle(borderWidth: 1))
              .toJson(),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
