import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surf_file/app.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/services/personal_folders.dart';
import 'package:surf_file/services/disk_space.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/services/window_transparency.dart';
import 'package:surf_file/theme/appearance.dart';
import 'package:surf_file/theme/neon_style.dart';
import 'package:surf_file/widgets/neon_surface.dart';
import 'package:surf_file/widgets/appearance_settings.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer_toolbar.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.alexmercerind/flutter_acrylic'),
        (_) async => null);
    messenger.setMockMethodCallHandler(
        WindowTransparency.channel, (_) async => null);
    messenger.setMockMethodCallHandler(DiskSpace.channel, (_) async => []);
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.alexmercerind/flutter_acrylic'), null);
    messenger.setMockMethodCallHandler(WindowTransparency.channel, null);
    messenger.setMockMethodCallHandler(DiskSpace.channel, null);
  });
  testWidgets('settings update themes live, follow system and preserve search',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var folderRequests = 0;
    messenger.setMockMethodCallHandler(PersonalFolders.channel, (call) async {
      folderRequests++;
      throw PlatformException(code: 'test_unavailable');
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(PersonalFolders.channel, null));
    await tester.pumpWidget(const SurfFileApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'document');
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Paramètres d’apparence'));
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceSettings), findsOneWidget);
    await tester.tap(find.text('Sombre'));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
    expect(Theme.of(tester.element(find.byType(ExplorerToolbar))).brightness,
        Brightness.dark);
    expect(tester.takeException(), isNull);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.tap(find.text('Système'));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(ExplorerToolbar))).brightness,
        Brightness.light);

    await tester.tap(find.text('Clair'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(ColorPicker), findsNothing);
    await tester.tap(find.text('Dimensions et espacement'));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('Hauteur des cartes'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.tap(slider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    final settingsContext = tester.element(find.byType(AppearanceSettings));
    expect(AppearanceScope.of(settingsContext).cardHeight, greaterThan(142));
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('document'), findsOneWidget);
    expect(folderRequests, 1);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Paramètres d’apparence'));
    await tester.pumpAndSettle();
    expect(
        AppearanceScope.of(tester.element(find.byType(AppearanceSettings)))
            .cardHeight,
        greaterThan(142));
    await tester.tap(find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    final reset =
        AppearanceScope.of(tester.element(find.byType(AppearanceSettings)));
    expect(reset.cardHeight, 142);
    expect(reset.mode, ThemeMode.light);
    expect(reset.cardColor, isNull);
    final controller = AppearanceScope.controllerOf(
        tester.element(find.byType(AppearanceSettings)))!;
    controller.value = controller.value.copyWith(
        backgroundNeon: const NeonStyle(enabled: true, intensity: .8),
        backgroundBorderColor: const Color(0x80112233),
        backgroundBorderWidth: 3);
    await tester.pumpAndSettle();
    final background = tester
        .widget<NeonSurface>(find.byKey(const ValueKey('background-neon')));
    expect(background.style.enabled, isTrue);
    expect(background.style.intensity, .8);
    final border = tester
        .widget<DecoratedBox>(find.byKey(const ValueKey('background-border')));
    expect(border.position, DecorationPosition.foreground);
    expect((border.decoration as BoxDecoration).border!.top.color,
        const Color(0x80112233));
    expect((border.decoration as BoxDecoration).border!.top.width, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('color pickers apply colors and restore automatic backgrounds',
      (tester) async {
    final controller = ValueNotifier(const Appearance());
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppearanceScope(
      controller: controller,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => AppearanceSettings.show(context),
                        child: const Text('Réglages')),
                  ))),
    ));
    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();
    expect(find.byType(ColorPicker), findsNothing);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.text('Style des cartes'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(4));
    await tester.tap(find.text('Couleur unie').last);
    await tester.pumpAndSettle();
    expect(find.byType(ColorPicker), findsOneWidget);
    final picker = tester.widget<ColorPicker>(find.byType(ColorPicker));
    expect(picker.enableOpacity, isTrue);
    expect(picker.showColorCode, isTrue);
    expect(picker.pickersEnabled[ColorPickerType.wheel], isTrue);
    picker.onColorChanged(const Color(0x80102030));
    await tester.pumpAndSettle();
    expect(controller.value.cardColor, const Color(0x80102030));
    expect(Appearance.foreground(controller.value.cardColor!),
        const Color(0xFFF1F3F8));
    final automatic =
        find.byKey(const ValueKey('automatic-Couleur des cartes'));
    await tester.ensureVisible(automatic);
    await tester.pumpAndSettle();
    await tester.tap(automatic);
    await tester.pumpAndSettle();
    expect(controller.value.cardColor, isNull);
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Couleur d’accent'));
    await tester.pumpAndSettle();
    tester
        .widget<ColorPicker>(find.byType(ColorPicker))
        .onColorChanged(const Color(0x8000796B));
    await tester.pumpAndSettle();
    expect(controller.value.accent, const Color(0x8000796B));
    expect(tester.widget<ColorPicker>(find.byType(ColorPicker)).color,
        const Color(0x8000796B));
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fond de l’application'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(2));
    await tester.tap(find.text('Couleur unie').last);
    await tester.pumpAndSettle();
    tester
        .widget<ColorPicker>(find.byType(ColorPicker))
        .onColorChanged(const Color(0x40E2E8F0));
    await tester.pumpAndSettle();
    expect(controller.value.backgroundColor, const Color(0x40E2E8F0));
    tester
        .widget<Slider>(find.byKey(const ValueKey('Opacité du fond')))
        .onChanged!(.5);
    await tester.pumpAndSettle();
    expect(controller.value.backgroundOpacity, .5);
    final automaticBackground =
        find.byKey(const ValueKey('automatic-Arrière-plan'));
    await tester.ensureVisible(automaticBackground);
    await tester.tap(automaticBackground);
    await tester.pumpAndSettle();
    expect(controller.value.backgroundColor, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('popups expose each setting once and retain live changes',
      (tester) async {
    final controller = ValueNotifier(const Appearance());
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppearanceScope(
      controller: controller,
      child: MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                    onPressed: () => AppearanceSettings.show(context),
                    child: const Text('Réglages'),
                  ))),
    ));
    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();
    expect(find.text('Élévation de la sélection'), findsNothing);
    for (final section in {
      'Style des cartes': 4,
      'Style des cartes sélectionnées': 4,
      'Style de la sélection du panneau gauche': 4,
      'Dimensions et espacement': 4,
      'Texte et icônes': 2,
      'Transparence de la fenêtre': 1,
    }.entries) {
      await tester.ensureVisible(find.text(section.key));
      await tester.pumpAndSettle();
      await tester.tap(find.text(section.key));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNWidgets(section.value));
      expect(find.byType(ColorPicker), findsNothing);
      for (final barrier
          in tester.widgetList<ModalBarrier>(find.byType(ModalBarrier))) {
        expect(barrier.color?.a ?? 0, 0);
        expect(barrier.dismissible, isFalse);
      }
      // Change all sliders before rebuilding to catch stale snapshot callbacks.
      for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
        slider.onChanged!(slider.max);
      }
      await tester.pumpAndSettle();
      for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
        expect(slider.value, slider.max);
      }
      await tester.tap(find.text('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
    }
    final saved =
        AppearanceStore.decode(AppearanceStore.encode(controller.value));
    expect(saved.radius, 36);
    expect(saved.borderWidth, 4);
    expect(saved.elevation, 16);
    expect(saved.shadowOpacity, .6);
    expect(saved.spacing, Appearance.maxSpacing);
    expect(saved.rowHeight, Appearance.maxRowHeight);
    expect(saved.fontSize, 16);
    expect(saved.iconSize, 64);
    expect(saved.selectedCardStyle!.elevation, 16);
    expect(saved.selectedFolderStyle!.elevation, 16);
    expect(saved.windowOpacity, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grid and list consume geometry, color and shadow settings',
      (tester) async {
    final controller = ValueNotifier(const Appearance(
      cardHeight: 260,
      cardWidth: 320,
      rowHeight: 88,
      radius: 28,
      spacing: 24,
      elevation: 8,
      shadowOpacity: .4,
      borderWidth: 3,
      cardColor: Color(0xFF102030),
      fontSize: 16,
      iconSize: 64,
    ));
    addTearDown(controller.dispose);
    final entry = ExplorerEntry(
        entity: File('C:\\example.txt'),
        name: 'example.txt',
        isDirectory: false,
        modified: DateTime(2026),
        size: 12);
    Future<void> show(bool grid) => tester.pumpWidget(AppearanceScope(
          controller: controller,
          child: MaterialApp(
              home: Scaffold(
                  body: ExplorerEntriesView(
            entries: [entry],
            gridView: grid,
            selectedPath: null,
            onSelected: (_) {},
            onOpen: (_) {},
          ))),
        ));
    await show(true);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
    expect(delegate.mainAxisExtent, 260);
    expect(delegate.maxCrossAxisExtent, 320);
    expect(delegate.crossAxisSpacing, 24);
    final materialFinder = find
        .ancestor(of: find.text('example.txt'), matching: find.byType(Material))
        .first;
    final material = tester.widget<Material>(materialFinder);
    expect(material.color, const Color(0xFF102030));
    expect(material.elevation, 8);
    expect((material.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(28));
    expect((material.shape! as RoundedRectangleBorder).side.width, 3);
    expect(tester.widget<Text>(find.text('example.txt')).style?.fontSize, 16);
    expect(tester.getSize(materialFinder).height, 260);
    expect(tester.takeException(), isNull);
    await show(false);
    final rowMaterial = find.descendant(
      of: find.byKey(const ValueKey('row-surface-C:\\example.txt')),
      matching: find.byType(Material),
    );
    expect(tester.getSize(rowMaterial).height, 88);
    expect(tester.widget<Material>(rowMaterial).elevation, 8);
    expect(tester.takeException(), isNull);
    controller.value = const Appearance(
        cardHeight: 142, cardWidth: 180, fontSize: 16, iconSize: 64);
    await show(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
