import 'dart:convert';
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/services/appearance_store.dart' as shell;
import 'package:super_container_layout/theme/appearance.dart' as base;
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/container_fill.dart';
import 'package:super_container_layout/theme/neon_style.dart';
import '../theme/surffile_appearance.dart';
import '../theme/disk_gauge_style.dart';
import '../theme/folder_transition.dart';

class SurfFileAppearanceStore extends shell.AppearanceStore {
  SurfFileAppearanceStore({super.key = 'appearance.v1', SurfFileAppearanceCodec? codec})
      : super(codec: codec ?? SurfFileAppearanceCodec());
  static const version = 3;
  ValueNotifier<SurfFilePreferences> get preferences => (codec as SurfFileAppearanceCodec).preferences;
  static String encode(Appearance value, {SurfFilePreferences preferences = const SurfFilePreferences()}) =>
      SurfFileAppearanceCodec(preferences: ValueNotifier(preferences)).encode(value);
  static Appearance decode(String text) => SurfFileAppearanceCodec().decode(text);
  @override
  Future<Appearance> load() async {
    final value = await super.load();
    if (value is DefaultAppearance) return value;
    throw StateError('SurfFile requires DefaultAppearance.');
  }
}

typedef AppearanceStore = SurfFileAppearanceStore;

class PersistentAppearanceController extends ValueNotifier<Appearance> {
  PersistentAppearanceController(AppearanceStore store, void Function(Object) onSaveError)
      : _delegate = shell.PersistentAppearanceController(store, onSaveError), super(defaultSurfFileAppearance());
  final shell.PersistentAppearanceController _delegate;
  @override
  Appearance get value {
    final value = _delegate.value;
    if (value is DefaultAppearance) return value;
    throw StateError('SurfFile requires DefaultAppearance.');
  }
  @override
  set value(Appearance value) => _delegate.value = value;
  Future<void> get saved => _delegate.saved;
  Future<void> restore() => _delegate.restore();
  ValueNotifier<SurfFilePreferences> get preferences =>
      (_delegate.store.codec as SurfFileAppearanceCodec).preferences;
  void reset() => _delegate.reset();
  @override
  void addListener(VoidCallback listener) => _delegate.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => _delegate.removeListener(listener);
  @override
  void dispose() { _delegate.dispose(); super.dispose(); }
}

class LegacyAppearanceCodec {
  static String encode(Appearance a, {SurfFilePreferences preferences = const SurfFilePreferences()}) => jsonEncode({
    'version': 2,
    'mode': a.mode.name,
    'accent': a.accent.toARGB32(),
    'backgroundOpacity': a.backgroundOpacity,
    'windowOpacity': a.windowOpacity,
    'windowEffect': a.windowEffect.name,
    for (final entry in SurfFileAppearanceCodec.styleIds.entries)
      entry.key: a.styles[entry.value]?.toJson(),
    for (final entry in SurfFileAppearanceCodec.layoutIds.entries)
      entry.key: a.layout(entry.value).toJson(),
    'diskGaugeStyle': preferences.diskGaugeStyle.toJson(),
    'cardHeight': a.cardHeight,
    'cardWidth': a.cardWidth,
    'rowHeight': a.rowHeight,
    'spacing': a.spacing,
    'fontSize': a.fontSize,
    'iconSize': a.iconSize,
    'folderTransition': preferences.folderTransition.name,
    'folderTransitionDuration': preferences.folderTransitionDuration,
    'scrollFadeEnabled': a.scrollFadeEnabled,
    'scrollFadeExtent': a.scrollFadeExtent,
  });

  static ({DefaultAppearance appearance, SurfFilePreferences preferences}) decodeDocument(String stored) {
    final json = jsonDecode(stored);
    if (json is! Map<String, dynamic> || json['version'] != 2) {
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
    final preferences = SurfFilePreferences(
      diskGaugeStyle: DiskGaugeStyle.fromJson(json['diskGaugeStyle']),
      folderTransition: transition,
      folderTransitionDuration: number(
        'folderTransitionDuration', SurfFileAppearanceDefaults.folderTransitionDuration,
        SurfFileAppearanceDefaults.minTransitionDuration,
        SurfFileAppearanceDefaults.maxTransitionDuration,
      ),
    );
    return (preferences: preferences, appearance: DefaultAppearance(
      mode: mode,
      accent: color('accent') ?? const Color(0xFF5268D9),
      backgroundOpacity: number('backgroundOpacity', 1, 0, 1),
      windowOpacity: number('windowOpacity', 1, .2, 1),
      windowEffect: windowEffect,
      styles: {
        for (final entry in SurfFileAppearanceCodec.styleIds.entries)
          if (json[entry.key] != null ||
              !SurfFileAppearanceCodec.optionalStyles.contains(entry.key))
            entry.value: ContainerStyle.fromJson(
              json[entry.key],
              fallback:
                  SurfFileAppearanceDefaults.defaultStyles[entry.value] ??
                  const ContainerStyle(),
            ),
      },
      layouts: {
        for (final entry in SurfFileAppearanceCodec.layoutIds.entries)
          entry.value: SuperLayoutConfig.fromJson(
            json[entry.key],
            fallback: SurfFileAppearanceDefaults.defaultLayouts[entry.value]!,
          ),
      },
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
      scrollFadeEnabled: fadeEnabled,
      scrollFadeExtent: number(
        'scrollFadeExtent',
        28,
        Appearance.minScrollFadeExtent,
        Appearance.maxScrollFadeExtent,
      ),
    ));
  }
  static DefaultAppearance decode(String stored) => decodeDocument(stored).appearance;
}

class SurfFileAppearanceCodec extends shell.AppearanceCodec {
  SurfFileAppearanceCodec({ValueNotifier<SurfFilePreferences>? preferences})
      : preferences = preferences ?? ValueNotifier(const SurfFilePreferences());
  final ValueNotifier<SurfFilePreferences> preferences;
  @override
  Listenable get additionalPreferences => preferences;
  @override
  void resetAdditional() => preferences.value = const SurfFilePreferences();
  @override
  DefaultAppearance prepare(base.Appearance appearance) {
    if (appearance is! DefaultAppearance) throw StateError('SurfFile requires DefaultAppearance.');
    return appearance.copyWith(
      styles: {...SurfFileAppearanceDefaults.defaultStyles, ...appearance.styles},
      layouts: {...SurfFileAppearanceDefaults.defaultLayouts, ...appearance.layouts},
    );
  }
  @override
  DefaultAppearance decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) throw const FormatException('Invalid appearance document.');
    return fromJson(json);
  }
  @override
  void restoreAdditional(String document) => preferences.value = decodeDocument(
    Map<String, dynamic>.from(jsonDecode(document) as Map),
  ).preferences;
  @override
  String get format => 'surf_file.appearance';
  @override
  int get schemaVersion => 3;
  @override
  Set<String> get additionalKeys => const {'application'};
  @override
  Appearance get defaults => defaultSurfFileAppearance();

  static const styleIds = {
    'cardStyle': 'card', 'backgroundStyle': 'background',
    'sidebarStyle': 'sidebar', 'pathBarStyle': 'pathBar',
    'explorerViewModeBarStyle': 'explorerViewModeBar',
    'diskPanelStyle': 'diskPanel', 'diskTileStyle': 'diskTile',
    'selectedDiskTileStyle': 'selectedDiskTile',
    'selectedCardStyle': 'selectedCard', 'selectedFolderStyle': 'selectedFolder',
    'folderStyle': 'folder',
  };
  static const layoutIds = {
    'explorerLayout': 'explorer', 'explorerMainLayout': 'explorerMain',
    'explorerSidebarLayout': 'explorerSidebar',
  };
  static const shellKeys = {'version', 'mode', 'accent', 'backgroundOpacity', 'windowOpacity', 'windowEffect'};
  static const businessKeys = {
    'diskGaugeStyle', 'cardHeight', 'cardWidth', 'rowHeight', 'spacing',
    'fontSize', 'iconSize', 'folderTransition', 'folderTransitionDuration',
    'scrollFadeEnabled', 'scrollFadeExtent',
  };
  static const optionalStyles = {'selectedDiskTileStyle', 'selectedCardStyle', 'selectedFolderStyle', 'folderStyle'};

  static Map<String, Object?> upgradeVersionOne(Map<String, dynamic> source) {
    const oldKeys = {
      'cardColor', 'backgroundColor', 'cardFill', 'backgroundFill',
      'cardNeon', 'selectedFolderNeon', 'backgroundNeon', 'radius', 'elevation',
      'selectedCardElevation', 'selectedFolderElevation', 'shadowOpacity',
      'borderWidth', 'cardBorderColor', 'backgroundBorderColor', 'backgroundBorderWidth',
    };
    final known = {...shellKeys, ...styleIds.keys, ...layoutIds.keys, ...businessKeys, ...oldKeys};
    if (source.keys.any((key) => !known.contains(key))) {
      throw const FormatException('Préférence version 1 inconnue.');
    }
    final card = ContainerStyle.fromJson({
      ...const ContainerStyle().toJson(),
      'color': source['cardColor'],
      'fill': ContainerFill.fromJson(source['cardFill']).toJson(),
      'neon': NeonStyle.fromJson(source['cardNeon']).toJson(),
      'radius': source['radius'] ?? 13,
      'borderWidth': source['borderWidth'] ?? 1,
      'borderColor': source['cardBorderColor'],
      'elevation': source['elevation'] ?? 0,
      'shadowOpacity': source['shadowOpacity'] ?? .2,
      'padding': 12,
    });
    final background = ContainerStyle.fromJson({
      ...const ContainerStyle().toJson(),
      'color': source['backgroundColor'],
      'fill': ContainerFill.fromJson(source['backgroundFill']).toJson(),
      'neon': NeonStyle.fromJson(source['backgroundNeon']).toJson(),
      'borderWidth': source['backgroundBorderWidth'] ?? 0,
      'borderColor': source['backgroundBorderColor'],
    });
    ContainerStyle? selectedCard;
    if (source['selectedCardStyle'] != null) {
      selectedCard = ContainerStyle.fromJson(source['selectedCardStyle']);
    } else if (source['selectedCardElevation'] != null) {
      selectedCard = ContainerStyle.fromJson({
        ...const ContainerStyle().toJson(),
        'radius': card.radius, 'borderWidth': card.borderWidth,
        'elevation': source['selectedCardElevation'],
        'shadowOpacity': card.shadowOpacity,
      });
    }
    final folderNeon = NeonStyle.fromJson(source['selectedFolderNeon']);
    ContainerStyle? selectedFolder;
    if (source['selectedFolderStyle'] != null) {
      selectedFolder = ContainerStyle.fromJson(source['selectedFolderStyle']);
      selectedFolder = selectedFolder.copyWith(neon: selectedFolder.neon ?? folderNeon);
    } else {
      final folder = ContainerStyle.fromJson({
        ...const ContainerStyle().toJson(),
        'radius': 9, 'elevation': source['selectedFolderElevation'] ?? 0,
        'shadowOpacity': card.shadowOpacity, 'neon': folderNeon.toJson(),
      });
      if (folder.elevation != 0 || folderNeon.enabled || folderNeon.color != null ||
          folderNeon.intensity != const NeonStyle().intensity) {
        selectedFolder = folder;
      }
    }
    return {
      for (final entry in source.entries) if (!oldKeys.contains(entry.key)) entry.key: entry.value,
      'version': 2,
      'cardStyle': card.toJson(),
      'backgroundStyle': background.toJson(),
      'selectedCardStyle': selectedCard?.toJson(),
      'selectedFolderStyle': selectedFolder?.toJson(),
    };
  }

  @override
  Map<String, Object?> toJson(base.Appearance value) {
    final a = prepare(value);
    final p = preferences.value;
    return {...super.toJson(a), 'application': {
      'diskGaugeStyle': p.diskGaugeStyle.toJson(),
      'cardHeight': a.cardHeight, 'cardWidth': a.cardWidth,
      'rowHeight': a.rowHeight, 'spacing': a.spacing,
      'fontSize': a.fontSize, 'iconSize': a.iconSize,
      'folderTransition': p.folderTransition.name,
      'folderTransitionDuration': p.folderTransitionDuration,
      'scrollFadeEnabled': a.scrollFadeEnabled,
      'scrollFadeExtent': a.scrollFadeExtent,
    }};
  }

  @override
  DefaultAppearance fromJson(Map<String, dynamic> json) => decodeDocument(json).appearance;

  ({DefaultAppearance appearance, SurfFilePreferences preferences}) decodeDocument(Map<String, dynamic> json) {
    if (json['version'] == 1) {
      final document = LegacyAppearanceCodec.decodeDocument(jsonEncode(upgradeVersionOne(json)));
      return (appearance: prepare(document.appearance), preferences: document.preferences);
    }
    if (json['version'] == 2) {
      final known = {...shellKeys, ...styleIds.keys, ...layoutIds.keys, ...businessKeys};
      if (json.keys.any((key) => !known.contains(key))) throw const FormatException('Préférence historique inconnue.');
      final document = LegacyAppearanceCodec.decodeDocument(jsonEncode(json));
      return (appearance: prepare(document.appearance), preferences: document.preferences);
    }
    final generic = super.fromJson(json);
    final payload = json['application'];
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Préférences SurfFile absentes ou invalides.');
    }
    if (payload.keys.any((key) => !businessKeys.contains(key))) {
      throw const FormatException('Préférence SurfFile inconnue.');
    }
    final legacy = <String, Object?>{
      ...payload,
      'version': 2,
      'mode': generic.mode.name,
      'accent': generic.accent.toARGB32(),
      'backgroundOpacity': generic.backgroundOpacity,
      'windowOpacity': generic.windowOpacity,
      'windowEffect': generic.windowEffect.name,
      for (final entry in styleIds.entries) entry.key: generic.styles[entry.value]?.toJson(),
      for (final entry in layoutIds.entries) entry.key: generic.layouts[entry.value]?.toJson(),
    };
    final document = LegacyAppearanceCodec.decodeDocument(jsonEncode(legacy));
    return (preferences: document.preferences, appearance: prepare(document.appearance.copyWith(
      styles: generic.styles,
      layouts: generic.layouts,
    )));
  }

  @override
  bool needsMigration(String text) {
    final json = jsonDecode(text);
    return json is Map && (json['version'] == 1 || json['version'] == 2);
  }

  @override
  Map<String, Object?> normalizeTransfer(Map<String, dynamic> data, int version) {
    if (version == schemaVersion) return super.normalizeTransfer(data, version);
    if (version == 1) {
      if (!data.containsKey('mode')) throw const FormatException('Document version 1 incomplet.');
      final upgraded = upgradeVersionOne(data)..remove('version');
      return normalizeTransfer(Map<String, dynamic>.from(upgraded), 2);
    }
    if (version != 2) {
      throw const FormatException('Version d’export non prise en charge.');
    }
    if (data.keys.any((key) => !shellKeys.contains(key) && !styleIds.containsKey(key) && !layoutIds.containsKey(key) && !businessKeys.contains(key))) {
      throw const FormatException('Préférence historique inconnue.');
    }
    return {
      for (final key in shellKeys)
        if (key != 'version' && data.containsKey(key)) key: data[key],
      if (styleIds.keys.any(data.containsKey))
        'styles': {
          for (final entry in styleIds.entries)
            if (data.containsKey(entry.key))
              entry.value: data[entry.key] ?? (optionalStyles.contains(entry.key) ? null : defaults.style(entry.value).toJson()),
        },
      if (layoutIds.keys.any(data.containsKey))
        'layouts': {
          for (final entry in layoutIds.entries)
            if (data.containsKey(entry.key)) entry.value: data[entry.key],
        },
      if (data.keys.any((key) => !shellKeys.contains(key) && !styleIds.containsKey(key) && !layoutIds.containsKey(key)))
        'application': {
          for (final entry in data.entries)
            if (!shellKeys.contains(entry.key) && !styleIds.containsKey(entry.key) && !layoutIds.containsKey(entry.key))
              entry.key: entry.value,
        },
    };
  }

  @override
  Object? mergeTransferValue(String key, Object? current, Object? imported, int sourceVersion) {
    if (key == 'application') {
      if (current is! Map || imported is! Map) throw const FormatException('Préférences SurfFile invalides.');
      return {...current, ...imported};
    }
    if ((sourceVersion == 1 || sourceVersion == 2) && (key == 'styles' || key == 'layouts')) {
      if (current is! Map || imported is! Map) throw FormatException('Groupe "$key" invalide.');
      final merged = {...current, ...imported};
      merged.removeWhere((_, value) => value == null);
      return merged;
    }
    return imported;
  }
}
