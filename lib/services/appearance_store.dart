import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/services/appearance/appearance_codec.dart'
    as shell;
import 'package:super_container_layout/services/appearance/appearance_store.dart'
    as shell;
import 'package:super_container_layout/theme/appearance.dart' as base;
import '../theme/surffile_appearance.dart';
import '../theme/disk_gauge_style.dart';
import '../theme/folder_transition.dart';

class SurfFileAppearanceStore extends shell.AppearanceStore {
  SurfFileAppearanceStore({
    super.key = 'appearance.v1',
    SurfFileAppearanceCodec? codec,
  }) : super(codec: codec ?? SurfFileAppearanceCodec());
  static const version = 3;
  ValueNotifier<SurfFilePreferences> get preferences =>
      (codec as SurfFileAppearanceCodec).preferences;
  static String encode(
    Appearance value, {
    SurfFilePreferences preferences = const SurfFilePreferences(),
  }) => SurfFileAppearanceCodec(
    preferences: ValueNotifier(preferences),
  ).encode(value);
  static Appearance decode(String text) =>
      SurfFileAppearanceCodec().decode(text);
  @override
  Future<Appearance> load() async {
    final value = await super.load();
    if (value is DefaultAppearance) return value;
    throw StateError('SurfFile requires DefaultAppearance.');
  }
}

typedef AppearanceStore = SurfFileAppearanceStore;

class PersistentAppearanceController extends ValueNotifier<Appearance> {
  PersistentAppearanceController(
    AppearanceStore store,
    void Function(Object) onSaveError,
  ) : _delegate = shell.PersistentAppearanceController(store, onSaveError),
      super(defaultSurfFileAppearance());
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
  void removeListener(VoidCallback listener) =>
      _delegate.removeListener(listener);
  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }
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
    if (appearance is! DefaultAppearance) {
      throw StateError('SurfFile requires DefaultAppearance.');
    }
    return appearance.copyWith(
      styles: {
        ...SurfFileAppearanceDefaults.defaultStyles,
        ...appearance.styles,
      },
      layouts: {
        ...SurfFileAppearanceDefaults.defaultLayouts,
        ...appearance.layouts,
      },
    );
  }

  @override
  DefaultAppearance decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid appearance document.');
    }
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

  static const businessKeys = {
    'diskGaugeStyle',
    'cardHeight',
    'cardWidth',
    'rowHeight',
    'spacing',
    'fontSize',
    'iconSize',
    'folderTransition',
    'folderTransitionDuration',
    'fileDragMode',
    'scrollFadeEnabled',
    'scrollFadeExtent',
  };

  @override
  Map<String, Object?> toJson(base.Appearance a) {
    final prepared = prepare(a);
    final p = preferences.value;
    return {
      ...super.toJson(prepared),
      'application': {
        'diskGaugeStyle': p.diskGaugeStyle.toJson(),
        'cardHeight': prepared.cardHeight,
        'cardWidth': prepared.cardWidth,
        'rowHeight': prepared.rowHeight,
        'spacing': prepared.spacing,
        'fontSize': prepared.fontSize,
        'iconSize': prepared.iconSize,
        'folderTransition': p.folderTransition.name,
        'folderTransitionDuration': p.folderTransitionDuration,
        'fileDragMode': p.fileDragMode.name,
        'scrollFadeEnabled': prepared.scrollFadeEnabled,
        'scrollFadeExtent': prepared.scrollFadeExtent,
      },
    };
  }

  @override
  DefaultAppearance fromJson(Map<String, dynamic> json) =>
      decodeDocument(json).appearance;

  ({DefaultAppearance appearance, SurfFilePreferences preferences})
  decodeDocument(Map<String, dynamic> json) {
    final generic = super.fromJson(json);
    final payload = json['application'];
    if (payload is! Map<String, dynamic>) {
      throw const FormatException(
        'Préférences SurfFile absentes ou invalides.',
      );
    }
    if (payload.keys.any((key) => !businessKeys.contains(key))) {
      throw const FormatException('Préférence SurfFile inconnue.');
    }
    double number(String key, double fallback, double min, double max) {
      final value = payload[key] ?? fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('Valeur invalide pour "$key".');
      }
      return value.toDouble();
    }

    final transition = switch (payload['folderTransition']) {
      null || 'none' => FolderTransition.none,
      'fade' => FolderTransition.fade,
      'slide' => FolderTransition.slide,
      'fullSlide' => FolderTransition.fullSlide,
      'heroExpand' => FolderTransition.heroExpand,
      'heroIcon' => FolderTransition.heroIcon,
      'zoom' => FolderTransition.zoom,
      _ => throw const FormatException('Animation de dossier invalide.'),
    };
    final dragName =
        payload['fileDragMode'] ?? SurfFileAppearanceDefaults.fileDragMode.name;
    final fileDragMode = FileDragMode.values
        .where((value) => value.name == dragName)
        .firstOrNull;
    if (fileDragMode == null) {
      throw const FormatException('Mode de glisser-déposer invalide.');
    }
    final fadeEnabled = payload['scrollFadeEnabled'] ?? true;
    if (fadeEnabled is! bool) {
      throw const FormatException('Activation du fondu invalide.');
    }
    final parsedPreferences = SurfFilePreferences(
      diskGaugeStyle: DiskGaugeStyle.fromJson(payload['diskGaugeStyle']),
      folderTransition: transition,
      folderTransitionDuration: number(
        'folderTransitionDuration',
        SurfFileAppearanceDefaults.folderTransitionDuration,
        SurfFileAppearanceDefaults.minTransitionDuration,
        SurfFileAppearanceDefaults.maxTransitionDuration,
      ),
      fileDragMode: fileDragMode,
    );
    final appearance = DefaultAppearance(
      mode: generic.mode,
      accent: generic.accent,
      backgroundOpacity: generic.backgroundOpacity,
      windowOpacity: generic.windowOpacity,
      windowEffect: generic.windowEffect,
      styles: generic.styles,
      layouts: generic.layouts,
      components: generic.components,
      pageCatalog: generic.pageCatalog,
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
    );
    return (
      preferences: parsedPreferences,
      appearance: prepare(appearance),
    );
  }

  @override
  Object? mergeTransferValue(
    String key,
    Object? current,
    Object? imported,
    int sourceVersion,
  ) {
    if (key == 'application') {
      if (current is! Map || imported is! Map) {
        throw const FormatException('Préférences SurfFile invalides.');
      }
      return {...current, ...imported};
    }
    return imported;
  }
}
