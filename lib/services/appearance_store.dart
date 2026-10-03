import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/appearance.dart';
import '../theme/container_fill.dart';
import '../theme/container_style.dart';
import '../theme/neon_style.dart';
import '../theme/folder_transition.dart';

class AppearanceStore {
  static const key = 'appearance.v1';

  Future<Appearance> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.get(key);
    if (stored == null) return const Appearance();
    if (stored is! String) {
      throw const FormatException('Le paramétrage enregistré est invalide.');
    }
    return decode(stored);
  }

  Future<void> save(Appearance appearance) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(key, encode(appearance))) {
      throw StateError('L’enregistrement des paramètres a échoué.');
    }
  }

  static String encode(Appearance a) => jsonEncode({
        'version': 1,
        'mode': a.mode.name,
        'accent': a.accent.toARGB32(),
        'cardColor': a.cardColor?.toARGB32(),
        'backgroundColor': a.backgroundColor?.toARGB32(),
        'backgroundOpacity': a.backgroundOpacity,
        'windowOpacity': a.windowOpacity,
        'cardFill': a.cardFill.toJson(),
        'backgroundFill': a.backgroundFill.toJson(),
        'sidebarStyle': a.sidebarStyle.toJson(),
        'pathBarStyle': a.pathBarStyle.toJson(),
        'selectedCardStyle': a.selectedCardStyle?.toJson(),
        'selectedFolderStyle': a.selectedFolderStyle?.toJson(),
        'cardNeon': a.cardNeon.toJson(),
        'selectedFolderNeon': a.selectedFolderNeon.toJson(),
        'backgroundNeon': a.backgroundNeon.toJson(),
        'cardHeight': a.cardHeight,
        'cardWidth': a.cardWidth,
        'rowHeight': a.rowHeight,
        'radius': a.radius,
        'spacing': a.spacing,
        'elevation': a.elevation,
        'selectedCardElevation': a.selectedCardElevation,
        'selectedFolderElevation': a.selectedFolderElevation,
        'shadowOpacity': a.shadowOpacity,
        'borderWidth': a.borderWidth,
        'cardBorderColor': a.cardBorderColor?.toARGB32(),
        'backgroundBorderColor': a.backgroundBorderColor?.toARGB32(),
        'backgroundBorderWidth': a.backgroundBorderWidth,
        'fontSize': a.fontSize,
        'iconSize': a.iconSize,
        'folderTransition': a.folderTransition.name,
        'folderTransitionDuration': a.folderTransitionDuration,
        'scrollFadeEnabled': a.scrollFadeEnabled,
        'scrollFadeExtent': a.scrollFadeExtent,
      });

  static Appearance decode(String stored) {
    final json = jsonDecode(stored);
    if (json is! Map<String, dynamic> || json['version'] != 1) {
      throw const FormatException(
          'Version du paramétrage non prise en charge.');
    }
    double number(String key, double fallback, double min, double max) {
      final value = json[key] ?? fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('Valeur invalide pour "$key".');
      }
      return value.toDouble();
    }

    Color? color(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! int || value < 0 || value > 0xFFFFFFFF) {
        throw FormatException('Couleur invalide pour "$key".');
      }
      return Color(value);
    }

    final mode = switch (json['mode']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => throw const FormatException('Thème enregistré invalide.'),
    };
    final transition = switch (json['folderTransition']) {
      null || 'none' => FolderTransition.none,
      'fade' => FolderTransition.fade,
      'slide' => FolderTransition.slide,
      'fullSlide' => FolderTransition.fullSlide,
      'heroExpand' => FolderTransition.heroExpand,
      'heroIcon' => FolderTransition.heroIcon,
      'zoom' => FolderTransition.zoom,
      _ => throw const FormatException('Animation de dossier invalide.'),
    };
    final fadeEnabled = json['scrollFadeEnabled'] ?? true;
    if (fadeEnabled is! bool) {
      throw const FormatException('Activation du fondu invalide.');
    }
    return Appearance(
      mode: mode,
      accent: color('accent') ?? const Color(0xFF5268D9),
      cardColor: color('cardColor'),
      backgroundColor: color('backgroundColor'),
      backgroundOpacity: number('backgroundOpacity', 1, 0, 1),
      windowOpacity: number('windowOpacity', 1, .2, 1),
      cardFill: ContainerFill.fromJson(json['cardFill']),
      backgroundFill: ContainerFill.fromJson(json['backgroundFill']),
      sidebarStyle: ContainerStyle.fromJson(json['sidebarStyle']),
      pathBarStyle: ContainerStyle.fromJson(json['pathBarStyle'],
          fallback: const ContainerStyle(borderWidth: 1)),
      selectedCardStyle: json['selectedCardStyle'] == null
          ? null
          : ContainerStyle.fromJson(json['selectedCardStyle']),
      selectedFolderStyle: json['selectedFolderStyle'] == null
          ? null
          : ContainerStyle.fromJson(json['selectedFolderStyle']),
      cardNeon: NeonStyle.fromJson(json['cardNeon']),
      selectedFolderNeon: NeonStyle.fromJson(json['selectedFolderNeon']),
      backgroundNeon: NeonStyle.fromJson(json['backgroundNeon']),
      cardHeight: number('cardHeight', 142, 142, 300),
      cardWidth: number('cardWidth', 180, 180, 360),
      rowHeight: number(
          'rowHeight', 48, Appearance.minRowHeight, Appearance.maxRowHeight),
      radius: number('radius', 13, 0, 36),
      spacing:
          number('spacing', 12, Appearance.minSpacing, Appearance.maxSpacing),
      elevation: number('elevation', 0, 0, 16),
      selectedCardElevation: json['selectedCardElevation'] == null
          ? null
          : number('selectedCardElevation', 0, 0, 16),
      selectedFolderElevation: number('selectedFolderElevation', 0, 0, 16),
      shadowOpacity: number('shadowOpacity', .2, 0, .6),
      borderWidth: number('borderWidth', 1, 0, 4),
      cardBorderColor: color('cardBorderColor'),
      backgroundBorderColor: color('backgroundBorderColor'),
      backgroundBorderWidth: number('backgroundBorderWidth', 0, 0, 4),
      fontSize: number('fontSize', 12, 10, 16),
      iconSize: number('iconSize', 49, 24, 64),
      folderTransition: transition,
      folderTransitionDuration: number('folderTransitionDuration', 220,
          Appearance.minTransitionDuration, Appearance.maxTransitionDuration),
      scrollFadeEnabled: fadeEnabled,
      scrollFadeExtent: number('scrollFadeExtent', 28,
          Appearance.minScrollFadeExtent, Appearance.maxScrollFadeExtent),
    );
  }
}

class PersistentAppearanceController extends ValueNotifier<Appearance> {
  PersistentAppearanceController(this.store, this.onSaveError)
      : super(const Appearance());

  final AppearanceStore store;
  final void Function(Object error) onSaveError;
  Future<void> _pending = Future.value();

  Future<void> get saved => _pending;

  Future<void> restore() async {
    super.value = await store.load();
  }

  @override
  set value(Appearance appearance) {
    super.value = appearance;
    // Serialize writes so an older slider value cannot replace a newer one.
    _pending = _pending.then((_) async {
      try {
        await store.save(appearance);
      } on PlatformException catch (error) {
        onSaveError(error);
      } on MissingPluginException catch (error) {
        onSaveError(error);
      } on StateError catch (error) {
        onSaveError(error);
      } on FileSystemException catch (error) {
        onSaveError(error);
      }
    });
  }
}
