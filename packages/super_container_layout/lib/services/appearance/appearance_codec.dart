import 'dart:convert';
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/editor_page_config.dart';
import 'package:super_container_layout/models/json_syntax.dart';
import 'package:super_container_layout/models/native_component_config.dart';
import 'package:super_container_layout/models/scaffold_page_config.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_list_view_config.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/models/super_action_config.dart';
import 'package:super_container_layout/services/appearance/screen_tree_codec.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';

/// Override this codec to retain application-owned preferences and migrations.
class AppearanceCodec {
  const AppearanceCodec();
  String get format => 'super_container_layout.appearance';
  int get schemaVersion => 1;
  Set<String> get additionalKeys => const {};
  Appearance get defaults => Appearance();
  Listenable? get additionalPreferences => null;
  Appearance prepare(Appearance appearance) => appearance;
  void restoreAdditional(String document) {}
  void resetAdditional() {}
  bool needsMigration(String text) => false;
  String encode(Appearance appearance) => jsonEncode(toJson(appearance));
  Appearance decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid appearance document.');
    }
    return fromJson(json);
  }

  Map<String, Object?> toJson(Appearance a) => {
    'version': schemaVersion,
    'mode': a.mode.name,
    'accent': a.accent.toARGB32(),
    'backgroundOpacity': a.backgroundOpacity,
    'windowOpacity': a.windowOpacity,
    'windowEffect': a.windowEffect.name,
    'styles': {
      for (final entry in a.styles.entries) entry.key: entry.value.toJson(),
    },
    'layouts': {
      for (final entry in a.layouts.entries) entry.key: entry.value.toJson(),
    },
    'scaffoldPages': {
      for (final entry in a.scaffoldPages.entries)
        entry.key: entry.value.toJson(),
    },
    'nativeComponents': {
      for (final entry in a.nativeComponents.entries)
        entry.key: entry.value.toJson(),
    },
    'valueComponents': {
      for (final entry in a.valueComponents.entries)
        entry.key: entry.value.toJson(),
    },
    'actionComponents': {
      for (final entry in a.actionComponents.entries)
        entry.key: entry.value.toJson(),
    },
    'listComponents': {
      for (final entry in a.listComponents.entries)
        entry.key: entry.value.toJson(),
    },
    'pageCatalog': a.pageCatalog.toJson(),
  };
  Appearance fromJson(Map<String, dynamic> json) {
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported appearance version.');
    }
    final known = {
      'version',
      'mode',
      'accent',
      'backgroundOpacity',
      'windowOpacity',
      'windowEffect',
      'styles',
      'layouts',
      'scaffoldPages',
      'nativeComponents',
      'valueComponents',
      'actionComponents',
      'listComponents',
      'pageCatalog',
      'screens',
      'ops',
      'vibe',
      'merge',
      ...additionalKeys,
    };
    if (json.keys.any((key) => !known.contains(key))) {
      throw const FormatException('Unknown appearance preference.');
    }
    if (ScreenTreeCodec.isAiDocument(json)) {
      final expanded = ScreenTreeCodec.expandToCanonicalJson(json);
      json = {
        ...expanded,
        for (final key in additionalKeys)
          if (json.containsKey(key)) key: json[key],
      };
    }
    double number(String key, double fallback, double min, double max) {
      final value = json[key] ?? fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('Invalid "$key".');
      }
      return value.toDouble();
    }

    final mode = ThemeMode.values
        .where((v) => v.name == (json['mode'] ?? 'light'))
        .firstOrNull;
    final effect = WindowEffect.values
        .where((v) => v.name == (json['windowEffect'] ?? 'transparent'))
        .firstOrNull;
    final rawAccent = json['accent'] ?? 0xFF5268D9;
    final Color parsedAccent;
    try {
      parsedAccent = JsonColor.parse(rawAccent, 'accent');
    } on FormatException {
      throw const FormatException('Invalid theme or window preferences.');
    }
    if (mode == null || effect == null) {
      throw const FormatException('Invalid theme or window preferences.');
    }
    Map<String, dynamic> entries(String key, {bool optional = true}) {
      final value = json[key];
      if (value == null && optional) return {};
      if (value is! Map<String, dynamic> ||
          value.keys.any((id) => id.trim().isEmpty) ||
          value.values.any((v) => v is! Map<String, dynamic>)) {
        throw FormatException('Invalid "$key" map.');
      }
      return value;
    }

    return Appearance(
      mode: mode,
      accent: parsedAccent,
      windowEffect: effect,
      backgroundOpacity: number('backgroundOpacity', 1, 0, 1),
      windowOpacity: number('windowOpacity', 1, .2, 1),
      styles: {
        for (final entry in entries('styles').entries)
          entry.key: ContainerStyle.fromJson(entry.value),
      },
      layouts: {
        for (final entry in entries('layouts').entries)
          entry.key: SuperLayoutConfig.fromJson(entry.value),
      },
      scaffoldPages: {
        for (final entry in entries('scaffoldPages', optional: true).entries)
          entry.key: ScaffoldPageConfig.fromJson(entry.value),
      },
      nativeComponents: {
        for (final entry in entries('nativeComponents', optional: true).entries)
          entry.key: NativeComponentConfig.fromJson(entry.value),
      },
      valueComponents: {
        for (final entry in entries('valueComponents', optional: true).entries)
          entry.key: SuperValueConfig.fromJson(entry.value),
      },
      actionComponents: {
        for (final entry in entries('actionComponents', optional: true).entries)
          entry.key: SuperActionConfig.fromJson(entry.value),
      },
      listComponents: {
        for (final entry in entries('listComponents', optional: true).entries)
          entry.key: SuperListViewConfig.fromJson(entry.value),
      },
      pageCatalog: json.containsKey('pageCatalog')
          ? EditorPageCatalog.fromJson(json['pageCatalog'])
          : const EditorPageCatalog.empty(),
    );
  }

  Map<String, Object?> normalizeTransfer(
    Map<String, dynamic> data,
    int version,
  ) {
    if (version != schemaVersion) {
      throw const FormatException('Unsupported export version.');
    }
    final known = {
      ...toJson(defaults).keys,
      'screens',
      'ops',
      'vibe',
      'merge',
    }..remove('version');
    if (data.keys.any((key) => !known.contains(key))) {
      throw const FormatException('Unknown export preference.');
    }
    return Map<String, Object?>.from(data);
  }

  Object? mergeTransferValue(
    String key,
    Object? current,
    Object? imported,
    int sourceVersion,
  ) => imported;
}
