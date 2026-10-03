import 'dart:convert';
import 'dart:io';

import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/super_layout_config.dart';
import '../theme/appearance.dart';
import '../theme/container_style.dart';
import '../theme/disk_gauge_style.dart';
import '../theme/folder_transition.dart';

class AppearanceStore {
  static const key = 'appearance.v1';
  static const version = 2;

  Future<Appearance> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.get(key);
    if (stored == null) return const Appearance();
    if (stored is! String) {
      throw const FormatException('Le paramétrage enregistré est invalide.');
    }
    if (isOutdated(stored)) {
      await preferences.remove(key);
      return const Appearance();
    }
    return decode(stored);
  }

  Future<void> save(Appearance appearance) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(key, encode(appearance))) {
      throw StateError('L’enregistrement des paramètres a échoué.');
    }
  }

  /// Older formats are discarded rather than migrated.
  static bool isOutdated(String stored) {
    try {
      final json = jsonDecode(stored);
      return json is Map && json['version'] is int && json['version'] < version;
    } on FormatException {
      return false;
    }
  }

  static String encode(Appearance a) => jsonEncode({
    'version': version,
    'mode': a.mode.name,
    'accent': a.accent.toARGB32(),
    'backgroundOpacity': a.backgroundOpacity,
    'windowOpacity': a.windowOpacity,
    'windowEffect': a.windowEffect.name,
    'cardStyle': a.cardStyle.toJson(),
    'backgroundStyle': a.backgroundStyle.toJson(),
    'sidebarStyle': a.sidebarStyle.toJson(),
    'pathBarStyle': a.pathBarStyle.toJson(),
    'pathBarLayout': a.pathBarLayout.toJson(),
    'explorerLayout': a.explorerLayout.toJson(),
    'explorerViewModeBarStyle': a.explorerViewModeBarStyle.toJson(),
    'diskPanelStyle': a.diskPanelStyle.toJson(),
    'diskTileStyle': a.diskTileStyle.toJson(),
    'diskGaugeStyle': a.diskGaugeStyle.toJson(),
    'selectedDiskTileStyle': a.selectedDiskTileStyle?.toJson(),
    'selectedCardStyle': a.selectedCardStyle?.toJson(),
    'selectedFolderStyle': a.selectedFolderStyle?.toJson(),
    'folderStyle': a.folderStyle?.toJson(),
    'cardHeight': a.cardHeight,
    'cardWidth': a.cardWidth,
    'rowHeight': a.rowHeight,
    'spacing': a.spacing,
    'fontSize': a.fontSize,
    'iconSize': a.iconSize,
    'folderTransition': a.folderTransition.name,
    'folderTransitionDuration': a.folderTransitionDuration,
    'scrollFadeEnabled': a.scrollFadeEnabled,
    'scrollFadeExtent': a.scrollFadeExtent,
  });

  static Appearance decode(String stored) {
    final json = jsonDecode(stored);
    if (json is! Map<String, dynamic> || json['version'] != version) {
      throw const FormatException(
        'Version du paramétrage non prise en charge.',
      );
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
    final effectName = json['windowEffect'] ?? WindowEffect.transparent.name;
    final windowEffect = WindowEffect.values
        .where((e) => e.name == effectName)
        .firstOrNull;
    if (windowEffect == null) {
      throw const FormatException('Effet de fenêtre invalide.');
    }
    final fadeEnabled = json['scrollFadeEnabled'] ?? true;
    if (fadeEnabled is! bool) {
      throw const FormatException('Activation du fondu invalide.');
    }
    return Appearance(
      mode: mode,
      accent: color('accent') ?? const Color(0xFF5268D9),
      backgroundOpacity: number('backgroundOpacity', 1, 0, 1),
      windowOpacity: number('windowOpacity', 1, .2, 1),
      windowEffect: windowEffect,
      cardStyle: ContainerStyle.fromJson(
        json['cardStyle'],
        fallback: Appearance.defaultCardStyle,
      ),
      backgroundStyle: ContainerStyle.fromJson(json['backgroundStyle']),
      sidebarStyle: ContainerStyle.fromJson(json['sidebarStyle']),
      pathBarStyle: ContainerStyle.fromJson(
        json['pathBarStyle'],
        fallback: const ContainerStyle(borderWidth: 1),
      ),
      pathBarLayout: SuperLayoutConfig.fromJson(
        json['pathBarLayout'],
        fallback: Appearance.defaultPathBarLayout,
      ),
      explorerLayout: SuperLayoutConfig.fromJson(
        json['explorerLayout'],
        fallback: Appearance.defaultExplorerLayout,
      ),
      explorerViewModeBarStyle: ContainerStyle.fromJson(
        json['explorerViewModeBarStyle'],
      ),
      diskPanelStyle: ContainerStyle.fromJson(json['diskPanelStyle']),
      diskTileStyle: ContainerStyle.fromJson(
        json['diskTileStyle'],
        fallback: Appearance.defaultDiskTileStyle,
      ),
      diskGaugeStyle: DiskGaugeStyle.fromJson(json['diskGaugeStyle']),
      selectedDiskTileStyle: json['selectedDiskTileStyle'] == null
          ? null
          : ContainerStyle.fromJson(json['selectedDiskTileStyle']),
      selectedCardStyle: json['selectedCardStyle'] == null
          ? null
          : ContainerStyle.fromJson(json['selectedCardStyle']),
      folderStyle: json['folderStyle'] == null
          ? null
          : ContainerStyle.fromJson(json['folderStyle']),
      selectedFolderStyle: json['selectedFolderStyle'] == null
          ? null
          : ContainerStyle.fromJson(json['selectedFolderStyle']),
      cardHeight: number('cardHeight', 142, 142, 300),
      cardWidth: number('cardWidth', 180, 180, 360),
      rowHeight: number(
        'rowHeight',
        48,
        Appearance.minRowHeight,
        Appearance.maxRowHeight,
      ),
      spacing: number(
        'spacing',
        12,
        Appearance.minSpacing,
        Appearance.maxSpacing,
      ),
      fontSize: number('fontSize', 12, 10, 16),
      iconSize: number('iconSize', 49, 24, 64),
      folderTransition: transition,
      folderTransitionDuration: number(
        'folderTransitionDuration',
        220,
        Appearance.minTransitionDuration,
        Appearance.maxTransitionDuration,
      ),
      scrollFadeEnabled: fadeEnabled,
      scrollFadeExtent: number(
        'scrollFadeExtent',
        28,
        Appearance.minScrollFadeExtent,
        Appearance.maxScrollFadeExtent,
      ),
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
