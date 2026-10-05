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
import 'package:super_container_layout/theme/neon_style.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/styled_surface.dart';
import 'package:surf_file/widgets/dialogs/appearance_settings.dart';
import 'package:super_container_layout/widgets/container_style_editor.dart';
import 'package:surf_file/widgets/explorer/views/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_sidebar.dart';
import 'package:super_container_layout/widgets/neon_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'neon options persist independently and defaults disable them',
    () async {
      SharedPreferences.setMockInitialValues({});
      final appearance = Appearance(
        styles: {
        'card': Appearance.defaultCardStyle.copyWith(
          neon: const NeonStyle(
            enabled: true,
            color: Color(0x8000FFFF),
          ).copyWith(intensity: .9),
        ),
        'selectedFolder': const ContainerStyle(
          neon: NeonStyle(
            enabled: true,
            color: Color(0xFFFF00FF),
            intensity: .3,
          ),
        ),
        },
      );
      final errors = <Object>[];
      final controller = PersistentAppearanceController(
        AppearanceStore(),
        errors.add,
      );
      controller.value = appearance;
      await controller.saved;
      controller.dispose();
      final restored = PersistentAppearanceController(
        AppearanceStore(),
        errors.add,
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect((restored.value.style('card').neon ?? const NeonStyle()).toJson(), (appearance.style('card').neon ?? const NeonStyle()).toJson());
      expect(
        SurfFileAppearanceSlots.selectedFolder.read(restored.value).neon!.toJson(),
        SurfFileAppearanceSlots.selectedFolder.read(appearance).neon!.toJson(),
      );
      expect(errors, isEmpty);
      restored.value = Appearance();
      await restored.saved;
      final reset = await AppearanceStore().load();
      expect((reset.style('card').neon ?? const NeonStyle()).enabled, isFalse);
      expect(SurfFileAppearanceSlots.selectedFolder.read(reset).neon!.enabled, isFalse);
      expect((appearance.style('card').neon ?? const NeonStyle()).copyWith(resetColor: true).color, isNull);
    },
  );

  test('invalid stored neon parameters are rejected', () {
    for (final key in ['cardStyle', 'selectedFolderStyle']) {
      for (final invalid in [
        'invalid',
        {'enabled': 1, 'color': null, 'intensity': .6},
        {'enabled': true, 'color': 'cyan', 'intensity': .6},
        {'enabled': true, 'color': -1, 'intensity': .6},
        {'enabled': true, 'color': 0x100000000, 'intensity': .6},
        {'enabled': true, 'color': null, 'intensity': -.1},
        {'enabled': true, 'color': null, 'intensity': 3.1},
        {'enabled': true, 'color': null, 'intensity': 'bright'},
      ]) {
        expect(
          () => AppearanceStore.decode(
            jsonEncode({
              'version': 2,
              'mode': 'light',
              key: const ContainerStyle().toJson()..['neon'] = invalid,
            }),
          ),
          throwsFormatException,
        );
      }
    }
  });

  test('neon intensity persists through 300 percent', () {
    for (final intensity in [0.0, 1.0, 2.0, NeonStyle.maxIntensity]) {
      final neon = NeonStyle(enabled: true, intensity: intensity);
      final restored = AppearanceStore.decode(
        AppearanceStore.encode(
          Appearance(
            styles: {
              'card': ContainerStyle(neon: neon),
              'background': ContainerStyle(neon: neon),
              'selectedCard': ContainerStyle(neon: neon),
              'sidebar': ContainerStyle(neon: neon),
            },
          ),
        ),
      );
      expect((restored.style('card').neon ?? const NeonStyle()).intensity, intensity);
      expect(restored.style('background').neon!.intensity, intensity);
      expect(restored.styles['selectedCard']!.neon!.intensity, intensity);
      expect(restored.style('sidebar').neon!.intensity, intensity);
    }
  });

  test(
    'all panel neon settings persist and selections can override inheritance',
    () {
      const glow = NeonStyle(enabled: true, color: Colors.pink, intensity: .8);
      final appearance = Appearance(
        styles: {
          'card': ContainerStyle(neon: glow),
          'background': ContainerStyle(neon: glow),
          'sidebar': ContainerStyle(neon: glow),
          'pathBar': ContainerStyle(neon: glow),
          'selectedCard': ContainerStyle(neon: NeonStyle()),
          'selectedFolder': ContainerStyle(neon: glow),
        },
      );
      final restored = AppearanceStore.decode(
        AppearanceStore.encode(appearance),
      );
      expect(restored.style('background').neon!.toJson(), glow.toJson());
      expect(restored.style('sidebar').neon!.toJson(), glow.toJson());
      expect(restored.style('pathBar').neon!.toJson(), glow.toJson());
      expect(SurfFileAppearanceSlots.selectedCard.read(restored).neon!.enabled, isFalse);
      expect(
        SurfFileAppearanceSlots.selectedFolder.read(restored).neon!.toJson(),
        glow.toJson(),
      );
      expect(
        SurfFileAppearanceSlots.selectedCard
            .read(restored.withStyle('selectedCard', null))
            .neon!
            .enabled,
        isTrue,
      );
      for (final key in [
        'cardStyle',
        'backgroundStyle',
        'sidebarStyle',
        'pathBarStyle',
        'selectedCardStyle',
        'selectedFolderStyle',
      ]) {
        expect(
          () => AppearanceStore.decode(
            jsonEncode({
              'version': 2,
              'mode': 'light',
              key: const ContainerStyle().toJson()
                ..['neon'] = {'enabled': 'bad'},
            }),
          ),
          throwsFormatException,
        );
      }
    },
  );

  testWidgets('shared surface renders panel neon outside its material clip', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: StyledSurface(
            style: ContainerStyle(radius: 18, neon: NeonStyle(enabled: true)),
            fallbackColor: Colors.white,
            borderColor: Colors.blue,
            child: SizedBox(width: 100, height: 60),
          ),
        ),
      ),
    );
    final neon = tester.widget<NeonSurface>(find.byType(NeonSurface));
    expect(neon.style.enabled, isTrue);
    expect(neon.radius, 18);
    expect(neon.child, isA<Material>());
    expect(tester.takeException(), isNull);
  });

  for (final section in [
    'Style des cartes',
    'Style des cartes sélectionnées',
    'Style de la sélection du panneau gauche',
    'Style du panneau de gauche',
    'Style de la barre du chemin',
    'Fond de l’application',
  ]) {
    testWidgets('each container editor exposes independent neon: $section', (
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
      expect(find.widgetWithText(OutlinedButton, 'Effet néon'), findsNothing);
      await tester.ensureVisible(find.text(section));
      await tester.pumpAndSettle();
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
      final toggle = find.byKey(ValueKey('neon-$section'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final editor = tester.widget<ContainerStyleEditor>(
        find.byType(ContainerStyleEditor),
      );
      expect(editor.neon.enabled, isTrue);
      editor.onNeonChanged!(
        editor.neon.copyWith(color: Colors.cyan, intensity: .7),
      );
      await tester.pumpAndSettle();
      final saved = AppearanceStore.decode(
        AppearanceStore.encode(controller.value),
      );
      final styles = [
        (saved.style('card').neon ?? const NeonStyle()),
        SurfFileAppearanceSlots.selectedCard.read(saved).neon!,
        SurfFileAppearanceSlots.selectedFolder.read(saved).neon!,
        saved.style('sidebar').neon ?? const NeonStyle(),
        saved.style('pathBar').neon ?? const NeonStyle(),
        saved.style('background').neon ?? const NeonStyle(),
      ];
      expect(
        styles.where((style) => style.enabled),
        hasLength(section == 'Style des cartes' ? 2 : 1),
      );
      final configured = styles.firstWhere((style) => style.enabled);
      expect(configured.color!.toARGB32(), Colors.cyan.toARGB32());
      expect(configured.intensity, .7);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('halo uses intensity, alpha and accent without changing layout', (
    tester,
  ) async {
    Future<void> show(NeonStyle style, Color accent) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NeonSurface(
            style: style,
            accent: accent,
            radius: 12,
            child: const SizedBox(
              key: ValueKey('content'),
              width: 120,
              height: 60,
            ),
          ),
        ),
      ),
    );
    BoxDecoration halo() =>
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byType(NeonSurface),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;
    await show(const NeonStyle(), Colors.cyan);
    expect(find.byType(Container), findsNothing);
    final size = tester.getSize(find.byKey(const ValueKey('content')));
    await show(const NeonStyle(enabled: true, intensity: .5), Colors.cyan);
    expect(halo().boxShadow!.single.color, Colors.cyan.withValues(alpha: .35));
    expect(halo().boxShadow!.single.blurRadius, 12);
    expect(halo().boxShadow!.single.spreadRadius, 1);
    expect(tester.getSize(find.byKey(const ValueKey('content'))), size);
    await show(const NeonStyle(enabled: true, intensity: .5), Colors.pink);
    expect(halo().boxShadow!.single.color, Colors.pink.withValues(alpha: .35));
    const translucent = Color(0x8000FFFF);
    await show(
      const NeonStyle(enabled: true, color: translucent, intensity: 1),
      Colors.pink,
    );
    expect(
      halo().boxShadow!.single.color,
      translucent.withValues(alpha: translucent.a * .7),
    );
    await show(
      const NeonStyle(enabled: true, color: translucent, intensity: 3),
      Colors.pink,
    );
    expect(halo().boxShadow!.single.color, translucent);
    expect(halo().boxShadow!.single.blurRadius, 42);
    expect(halo().boxShadow!.single.spreadRadius, 6);
    final surface = tester.widget<Container>(
      find.descendant(
        of: find.byType(NeonSurface),
        matching: find.byType(Container),
      ),
    );
    expect(surface.foregroundDecoration, isNull);
    expect(halo().border, isNull);
    expect(tester.getSize(find.byKey(const ValueKey('content'))), size);
    await show(const NeonStyle(enabled: true, intensity: 0), Colors.cyan);
    expect(find.byType(Container), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('neon preserves the configured border without adding another', (
    tester,
  ) async {
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red, width: 3),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NeonSurface(
            style: const NeonStyle(enabled: true, intensity: 3),
            accent: Colors.cyan,
            radius: 12,
            child: Container(
              key: const ValueKey('bordered-content'),
              width: 120,
              height: 60,
              decoration: decoration,
            ),
          ),
        ),
      ),
    );
    final containers = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(NeonSurface),
            matching: find.byType(Container),
          ),
        )
        .toList();
    expect(containers, hasLength(2));
    expect(containers.first.foregroundDecoration, isNull);
    expect((containers.first.decoration! as BoxDecoration).border, isNull);
    expect(containers.last.decoration, decoration);
    expect(
      tester.getSize(find.byKey(const ValueKey('bordered-content'))),
      const Size(120, 60),
    );
    expect(tester.takeException(), isNull);
  });

  for (final grid in [false, true]) {
    testWidgets('neon covers selected and unselected cards in grid=$grid', (
      tester,
    ) async {
      final controller = ValueNotifier(
        Appearance(
          styles: {
            'card': ContainerStyle(
              neon: NeonStyle(enabled: true, color: Colors.cyan),
            ),
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
      Future<void> show(String path) => tester.pumpWidget(
        AppearanceScope(
          controller: controller,
          child: MaterialApp(
            home: Scaffold(
              body: ExplorerEntriesView(
                entries: entries,
                gridView: grid,
                selectedPath: path,
                onSelected: (path) => clicked = path,
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await show('first.txt');
      final surfaces = tester
          .widgetList<NeonSurface>(find.byType(NeonSurface))
          .toList();
      expect(surfaces.length, grid ? 2 : 3);
      expect(surfaces.where((surface) => surface.style.enabled), hasLength(2));
      await tester.tap(find.text('second.txt'), kind: PointerDeviceKind.mouse);
      expect(clicked, 'second.txt');
      await show('second.txt');
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<NeonSurface>(find.byType(NeonSurface))
            .where((surface) => surface.style.enabled),
        hasLength(2),
      );
      controller.value = Appearance();
      await tester.pump();
      expect(
        tester
            .widgetList<NeonSurface>(find.byType(NeonSurface))
            .every((surface) => !surface.style.enabled),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sidebar neon follows only the selected location', (
    tester,
  ) async {
    final controller = ValueNotifier(
      Appearance(
        styles: {
          'selectedFolder': ContainerStyle(neon: NeonStyle(enabled: true)),
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
    NeonSurface item(String name) => tester.widget<NeonSurface>(
      find
          .ancestor(of: find.text(name), matching: find.byType(NeonSurface))
          .first,
    );
    await show('docs');
    expect(item('Documents').style.enabled, isTrue);
    expect(item('Images').style.enabled, isFalse);
    await tester.tap(find.text('Images'));
    expect(clicked, 'images');
    await show('images');
    expect(item('Documents').style.enabled, isFalse);
    expect(item('Images').style.enabled, isTrue);
    controller.value = Appearance();
    await tester.pump();
    expect(item('Images').style.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings edit neon independently and reset both effects', (
    tester,
  ) async {
    final controller = ValueNotifier(Appearance());
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1000, 900));
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
    expect(find.widgetWithText(OutlinedButton, 'Effet néon'), findsNothing);
    await tester.ensureVisible(find.text('Style des cartes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Style des cartes'));
    await tester.pumpAndSettle();
    final cardSwitch = find.byKey(const ValueKey('neon-Style des cartes'));
    await tester.ensureVisible(cardSwitch);
    await tester.pumpAndSettle();
    await tester.tap(cardSwitch);
    await tester.pumpAndSettle();
    expect((controller.value.style('card').neon ?? const NeonStyle()).enabled, isTrue);
    expect(
      SurfFileAppearanceSlots.selectedFolder.read(controller.value).neon!.enabled,
      isFalse,
    );
    await tester.ensureVisible(find.text('Couleur du néon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Couleur du néon'));
    await tester.pumpAndSettle();
    tester
        .widget<ColorPicker>(find.byType(ColorPicker))
        .onColorChanged(Colors.cyan);
    await tester.pumpAndSettle();
    expect((controller.value.style('card').neon ?? const NeonStyle()).color, Colors.cyan);
    await tester.ensureVisible(find.text('Utiliser la couleur d’accent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utiliser la couleur d’accent'));
    await tester.pumpAndSettle();
    expect((controller.value.style('card').neon ?? const NeonStyle()).color, isNull);
    await tester.tap(find.text('Couleur du néon'));
    await tester.pumpAndSettle();
    final intensity = find.byKey(
      const ValueKey('neon-intensity-Style des cartes'),
    );
    expect(tester.widget<Slider>(intensity).max, 3);
    tester.widget<Slider>(intensity).onChanged!(3);
    await tester.pumpAndSettle();
    expect((controller.value.style('card').neon ?? const NeonStyle()).intensity, 3);
    expect(find.text('Intensité : 300 %'), findsOneWidget);
    tester.widget<Slider>(intensity).onChanged!(.8);
    await tester.pumpAndSettle();
    expect((controller.value.style('card').neon ?? const NeonStyle()).intensity, .8);
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text('Style de la sélection du panneau gauche'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Style de la sélection du panneau gauche'));
    await tester.pumpAndSettle();
    final folderSwitch = find.byKey(
      const ValueKey('neon-Style de la sélection du panneau gauche'),
    );
    await tester.ensureVisible(folderSwitch);
    await tester.pumpAndSettle();
    await tester.tap(folderSwitch);
    await tester.pumpAndSettle();
    expect(SurfFileAppearanceSlots.selectedFolder.read(controller.value).neon!.enabled, isTrue);
    final editors = tester.widgetList<NeonStyleEditor>(
      find.byType(NeonStyleEditor),
    );
    expect((controller.value.style('card').neon ?? const NeonStyle()).intensity, .8);
    expect(editors.single.value.intensity, .6);
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    expect((controller.value.style('card').neon ?? const NeonStyle()).enabled, isFalse);
    expect(
      SurfFileAppearanceSlots.selectedFolder.read(controller.value).neon!.enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
