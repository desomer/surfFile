import 'dart:convert';

import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/component_behavior.dart';
import 'package:super_container_layout/models/component_config.dart';
import 'package:super_container_layout/models/editor_page_config.dart';
import 'package:super_container_layout/models/json_syntax.dart';
import 'package:super_container_layout/models/native_component_config.dart';
import 'package:super_container_layout/models/scaffold_page_config.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_list_view_config.dart';
import 'package:super_container_layout/models/super_tab_config.dart';
import 'package:super_container_layout/models/super_table_config.dart';
import 'package:super_container_layout/models/super_tree_view_config.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';

/// Unified GenUI-style codec for flat, polymorphic `Appearance` persistence
/// and incremental surface updates (`patchFromJson`).
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
    'components': {
      for (final entry in a.components.entries)
        entry.key: entry.value.toTypedJson(),
    },
    'behaviors': {
      for (final entry in a.behaviors.entries)
        entry.key: [for (final b in entry.value) b.toJson()],
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
      'components',
      'behaviors',
      'pageCatalog',
      ...additionalKeys,
    };
    if (json.keys.any((key) => !known.contains(key))) {
      throw const FormatException('Unknown appearance preference.');
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

    final selfConstraints = <String, SlotSizeConstraints>{};
    final decodedComponents = <String, ComponentConfig>{
      for (final entry in entries('components', optional: true).entries)
        entry.key: ComponentConfig.fromJson(
          _extractSelfSlotSizeConstraints(
            entry.key,
            entry.value,
            selfConstraints,
          ),
        ),
    };
    _applySelfSlotSizeConstraints(decodedComponents, selfConstraints);

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
      components: decodedComponents,
      behaviors: {
        if (json['behaviors'] case final Map<String, dynamic> bMap)
          for (final entry in bMap.entries)
            if (entry.value is List)
              entry.key: [
                for (final item in entry.value as List)
                  if (item is Map<String, dynamic>)
                    ComponentBehavior.fromJson(item),
              ],
      },
      pageCatalog: json.containsKey('pageCatalog')
          ? EditorPageCatalog.fromJson(json['pageCatalog'])
          : const EditorPageCatalog.empty(),
    );
  }

  /// Extracts a direct `SlotSizeConstraints` object placed on component [id]
  /// (e.g. `{"preferredWidth": "110px", "preferredHeight": "40px"}`) so it can
  /// be attached to the parent container that places [id].
  static Map<Object?, Object?> _extractSelfSlotSizeConstraints(
    String id,
    Map<Object?, Object?> map,
    Map<String, SlotSizeConstraints> outSelfConstraints,
  ) {
    final rawConstraints = map['slotSizeConstraints'];
    if (SlotSizeConstraints.isDirectConstraintsMap(rawConstraints)) {
      outSelfConstraints[id] = SlotSizeConstraints.fromJson(rawConstraints);
      return <Object?, Object?>{
        for (final entry in map.entries)
          if (entry.key != 'slotSizeConstraints') entry.key: entry.value,
      };
    }
    return map;
  }

  /// Attaches extracted self-constraints to any parent container placing the slot.
  static void _applySelfSlotSizeConstraints(
    Map<String, ComponentConfig> components,
    Map<String, SlotSizeConstraints> selfConstraints,
  ) {
    if (selfConstraints.isEmpty) return;
    for (final entry in components.entries.toList()) {
      var comp = entry.value;
      for (final MapEntry(key: slotId, value: constraints)
          in selfConstraints.entries) {
        if (comp is SuperLayoutConfig && comp.placedSlotIds.contains(slotId)) {
          comp = comp.copyWith(
            slotSizeConstraints: {
              ...comp.slotSizeConstraints,
              slotId: constraints,
            },
          );
        } else if (comp is NativeComponentConfig &&
            comp.placements.values.any((ids) => ids.contains(slotId))) {
          comp = comp.withSlotSizeConstraints(slotId, constraints);
        } else if (comp is ScaffoldPageConfig &&
            comp.native.placements.values.any((ids) => ids.contains(slotId))) {
          comp = ScaffoldPageConfig.fromNative(
            comp.native.withSlotSizeConstraints(slotId, constraints),
          );
        } else if (comp is SuperListViewConfig &&
            comp.template.placedSlotIds.contains(slotId)) {
          comp = comp.copyWith(
            template: comp.template.copyWith(
              slotSizeConstraints: {
                ...comp.template.slotSizeConstraints,
                slotId: constraints,
              },
            ),
          );
        } else if (comp is SuperTabConfig &&
            comp.placedSlotIds.contains(slotId)) {
          comp = comp.withSlotSizeConstraints(slotId, constraints);
        } else if (comp is SuperTreeViewConfig &&
            comp.placedSlotIds.contains(slotId)) {
          comp = comp.withSlotSizeConstraints(slotId, constraints);
        } else if (comp is SuperTableConfig &&
            comp.placedSlotIds.contains(slotId)) {
          comp = comp.withSlotSizeConstraints(slotId, constraints);
        }
      }
      components[entry.key] = comp;
    }
  }

  /// Applies an incremental GenUI-style surface update ([patch]) onto [current].
  ///
  /// - Existing entries in `styles` and `components` are patched in place via
  ///   `patchFromJson`.
  /// - New entries in `components` are decoded via [ComponentConfigCatalog].
  /// - Setting an entry to `null` in `styles` or `components` deletes it (and
  ///   unplaces deleted component IDs from parent containers).
  Appearance patchFromJson(Appearance current, Map<String, dynamic> patch) {
    final known = {
      'version',
      'mode',
      'accent',
      'backgroundOpacity',
      'windowOpacity',
      'windowEffect',
      'styles',
      'components',
      'behaviors',
      'pageCatalog',
      'vibe',
      'merge',
      ...additionalKeys,
    };
    final unknownKeys = patch.keys
        .where((key) => !known.contains(key))
        .toList();
    if (unknownKeys.isNotEmpty) {
      debugPrint(
        '[AppearanceCodec] Clés de patch inconnues : $unknownKeys '
        '(attendues : ${known.toList()}).',
      );
      throw FormatException(
        'Unknown appearance preference: ${unknownKeys.join(', ')}.',
      );
    }

    var mode = current.mode;
    if (patch.containsKey('mode') && patch['mode'] != 'vibe') {
      mode =
          ThemeMode.values.where((v) => v.name == patch['mode']).firstOrNull ??
          (throw const FormatException('Invalid theme or window preferences.'));
    }

    var accent = current.accent;
    if (patch.containsKey('accent') && patch['accent'] != null) {
      try {
        accent = JsonColor.parse(patch['accent'], 'accent');
      } on FormatException {
        throw const FormatException('Invalid theme or window preferences.');
      }
    }

    double number(String key, double fallback, double min, double max) {
      final value = patch[key] ?? fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('Invalid "$key".');
      }
      return value.toDouble();
    }

    final backgroundOpacity = number(
      'backgroundOpacity',
      current.backgroundOpacity,
      0,
      1,
    );
    final windowOpacity = number('windowOpacity', current.windowOpacity, .2, 1);

    var windowEffect = current.windowEffect;
    if (patch.containsKey('windowEffect') && patch['windowEffect'] != null) {
      windowEffect =
          WindowEffect.values
              .where((v) => v.name == patch['windowEffect'])
              .firstOrNull ??
          (throw const FormatException('Invalid theme or window preferences.'));
    }

    final styles = Map<String, ContainerStyle>.of(current.styles);
    if (patch.containsKey('styles') && patch['styles'] != null) {
      final rawStyles = patch['styles'];
      if (rawStyles is! Map) {
        throw const FormatException('Invalid "styles" map.');
      }
      for (final entry in rawStyles.entries) {
        final id = entry.key;
        if (id is! String || id.trim().isEmpty) {
          throw const FormatException('Invalid "styles" map.');
        }
        if (entry.value == null) {
          styles.remove(id);
        } else if (entry.value is Map) {
          final existing = styles[id];
          try {
            styles[id] = existing != null
                ? existing.patchFromJson(entry.value as Map)
                : ContainerStyle.fromJson(entry.value);
          } on FormatException catch (error) {
            debugPrint(
              '[AppearanceCodec] Échec du décodage du style "$id" '
              '(FormatException) : ${error.message} | JSON: ${jsonEncode(entry.value)}',
            );
            throw FormatException(
              'Style "$id" : ${error.message}',
              error.source,
              error.offset,
            );
          } catch (error) {
            debugPrint(
              '[AppearanceCodec] Échec du décodage du style "$id" '
              '(${error.runtimeType}) : $error | JSON: ${jsonEncode(entry.value)}',
            );
            rethrow;
          }
        } else {
          debugPrint(
            '[AppearanceCodec] Style "$id" invalide (type: ${entry.value.runtimeType}).',
          );
          throw const FormatException('Invalid "styles" map.');
        }
      }
    }

    final components = Map<String, ComponentConfig>.of(current.components);
    final removedIds = <String>{};
    final selfConstraints = <String, SlotSizeConstraints>{};
    if (patch.containsKey('components') && patch['components'] != null) {
      final rawComponents = patch['components'];
      if (rawComponents is! Map) {
        throw const FormatException('Invalid "components" map.');
      }
      for (final entry in rawComponents.entries) {
        final id = entry.key;
        if (id is! String || id.trim().isEmpty) {
          throw const FormatException('Invalid "components" map.');
        }
        if (entry.value == null) {
          components.remove(id);
          styles.remove(id);
          removedIds.add(id);
        } else if (entry.value is Map) {
          final rawMap = entry.value as Map;
          final rawType = rawMap['type'] ?? rawMap['componentType'];
          final existing = components[id];
          final resolvedType = rawType ?? existing?.componentType ?? 'inconnu';
          try {
            final map = _extractSelfSlotSizeConstraints(
              id,
              rawMap,
              selfConstraints,
            );
            if (existing != null &&
                (rawType == null || existing.componentType == rawType)) {
              final payload = <String, Object?>{
                for (final e in map.entries)
                  if (e.key is String &&
                      e.key != 'type' &&
                      e.key != 'componentType')
                    e.key as String: e.value,
              };
              components[id] = existing.patchFromJson(payload);
            } else {
              components[id] = ComponentConfig.fromJson(map);
            }
          } on FormatException catch (error) {
            debugPrint(
              '[AppearanceCodec] Échec du décodage du composant "$id" '
              '(type: $resolvedType, FormatException) : ${error.message} | '
              'JSON: ${jsonEncode(entry.value)}',
            );
            throw FormatException(
              'Composant "$id" (type: $resolvedType) : ${error.message}',
              error.source,
              error.offset,
            );
          } catch (error) {
            debugPrint(
              '[AppearanceCodec] Échec du décodage du composant "$id" '
              '(type: $resolvedType, ${error.runtimeType}) : $error | '
              'JSON: ${jsonEncode(entry.value)}',
            );
            rethrow;
          }
        } else {
          debugPrint(
            '[AppearanceCodec] Composant "$id" invalide (type: ${entry.value.runtimeType}).',
          );
          throw const FormatException('Invalid "components" map.');
        }
      }
    }

    _applySelfSlotSizeConstraints(components, selfConstraints);

    if (removedIds.isNotEmpty) {
      for (final entry in components.entries.toList()) {
        var comp = entry.value;
        for (final removedId in removedIds) {
          if (comp is SuperLayoutConfig &&
              comp.placedSlotIds.contains(removedId)) {
            comp = comp.withoutSlot(removedId);
          } else if (comp is NativeComponentConfig &&
              comp.placements.values.any((ids) => ids.contains(removedId))) {
            comp = comp.withoutSlot(removedId);
          } else if (comp is ScaffoldPageConfig &&
              comp.native.placements.values.any(
                (ids) => ids.contains(removedId),
              )) {
            comp = comp.withoutSlot(removedId);
          } else if (comp is SuperListViewConfig &&
              comp.template.placedSlotIds.contains(removedId)) {
            comp = comp.copyWith(
              template: comp.template.withoutSlot(removedId),
            );
          } else if (comp is SuperTabConfig &&
              comp.placedSlotIds.contains(removedId)) {
            comp = comp.withoutSlot(removedId);
          } else if (comp is SuperTreeViewConfig &&
              comp.placedSlotIds.contains(removedId)) {
            comp = comp.withoutSlot(removedId);
          } else if (comp is SuperTableConfig &&
              comp.placedSlotIds.contains(removedId)) {
            comp = comp.withoutSlot(removedId);
          }
        }
        components[entry.key] = comp;
      }
    }

    var pageCatalog = current.pageCatalog;
    if (patch.containsKey('pageCatalog') && patch['pageCatalog'] != null) {
      pageCatalog = EditorPageCatalog.fromJson(patch['pageCatalog']);
    }

    return current.copyWith(
      mode: mode,
      accent: accent,
      backgroundOpacity: backgroundOpacity,
      windowOpacity: windowOpacity,
      windowEffect: windowEffect,
      styles: styles,
      components: components,
      pageCatalog: pageCatalog,
    );
  }

  Map<String, Object?> normalizeTransfer(
    Map<String, dynamic> data,
    int version,
  ) {
    if (version != schemaVersion) {
      throw const FormatException('Unsupported export version.');
    }
    final known = {...toJson(defaults).keys, 'vibe', 'merge'}
      ..remove('version');
    final unknownKeys = data.keys.where((key) => !known.contains(key)).toList();
    if (unknownKeys.isNotEmpty) {
      debugPrint(
        '[AppearanceCodec] Clés d’export/transfert inconnues : $unknownKeys '
        '(attendues : ${known.toList()}).',
      );
      throw FormatException(
        'Unknown export preference: ${unknownKeys.join(', ')}.',
      );
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
