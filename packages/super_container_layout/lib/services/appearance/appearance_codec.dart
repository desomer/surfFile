/// Contrat de sérialisation, validation et migration ([AppearanceCodec]) d'un modèle [Appearance].
///
/// Permet également de composer des préférences applicatives indépendantes
/// (`additionalPreferences`) au sein du même document de sauvegarde.
library;

import 'dart:convert';

import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/component_behavior.dart';
import 'package:super_container_layout/models/component_usage.dart';
import 'package:super_container_layout/models/component_config.dart';
import 'package:super_container_layout/models/automatic_state.dart';
import 'package:super_container_layout/models/editor_page_config.dart';
import 'package:super_container_layout/models/json_syntax.dart';
import 'package:super_container_layout/models/native_component_config.dart';
import 'package:super_container_layout/models/scaffold_page_config.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_list_view_config.dart';
import 'package:super_container_layout/models/super_conditional_config.dart';
import 'package:super_container_layout/models/super_tab_config.dart';
import 'package:super_container_layout/models/super_table_config.dart';
import 'package:super_container_layout/models/super_tree_view_config.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';

import '../../models/json_numbers.dart';

/// Entrée individuelle d'un patch d'apparence ou de repository rejetée lors d'une application partielle.
@immutable
class PatchRejectedEntry {
  /// Construit une entrée rejetée.
  const PatchRejectedEntry({
    required this.section,
    required this.key,
    required this.message,
    this.rawValue,
  });

  /// Section concernée (`'root'`, `'styles'`, `'components'`, `'behaviors'`, `'usages'`, `'pageCatalog'`, `'repositories'`).
  final String section;

  /// Clé ou identifiant de l'entrée rejetée.
  final String key;

  /// Cause détaillée du rejet.
  final String message;

  /// Valeur brute JSON associée à l'entrée rejetée, si disponible.
  final Object? rawValue;
}

/// Résultat immuable d'une mise à jour partielle tolérante ([AppearanceCodec.patchFromJsonPartial]).
@immutable
class PartialPatchResult {
  /// Construit le résultat d'une application partielle.
  const PartialPatchResult({
    required this.appearance,
    required this.appliedPatch,
    required this.rejectedEntries,
  });

  /// Apparence résultante intégrant uniquement les entrées valides du patch.
  final Appearance appearance;

  /// Sous-ensemble des clés et entrées du patch qui ont été acceptées et appliquées.
  final Map<String, dynamic> appliedPatch;

  /// Entrées invalides ignorées durant l'application partielle.
  final List<PatchRejectedEntry> rejectedEntries;

  /// Indique si au moins une entrée valide a été retenue dans [appliedPatch].
  bool get hasAppliedEntries => appliedPatch.isNotEmpty;

  /// Indique si au moins une entrée a été rejetée.
  bool get hasRejections => rejectedEntries.isNotEmpty;
}

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

  /// Encode le document complet, y compris les champs hotes, a deux decimales.
  String encode(Appearance appearance) =>
      jsonEncode(JsonNumbers.normalizeMap(toJson(appearance)));
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
    'bindingDebounceMs': a.bindingDebounceMs,
    'bindingSaveOnBlurOnly': a.bindingSaveOnBlurOnly,
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
    'usages': {
      for (final entry in a.usages.entries) entry.key: entry.value.toJson(),
    },
    'pageCatalog': a.pageCatalog.toJson(),
  };

  /// Sérialise une représentation compacte de [a] en omettant les valeurs par défaut.
  Map<String, Object?> toCompactJson(Appearance a) {
    final compactStyles = <String, Object?>{
      for (final entry in a.styles.entries)
        if (entry.value != const ContainerStyle())
          entry.key: entry.value.toCompactJson(),
    };
    return {
      'version': schemaVersion,
      'mode': a.mode.name,
      'accent': JsonColor.toHex(a.accent),
      if (a.backgroundOpacity != 1.0) 'backgroundOpacity': a.backgroundOpacity,
      if (a.windowOpacity != 1.0) 'windowOpacity': a.windowOpacity,
      if (a.windowEffect != WindowEffect.transparent)
        'windowEffect': a.windowEffect.name,
      if (a.bindingDebounceMs != Appearance.defaultBindingDebounceMs)
        'bindingDebounceMs': a.bindingDebounceMs,
      if (a.bindingSaveOnBlurOnly)
        'bindingSaveOnBlurOnly': a.bindingSaveOnBlurOnly,
      if (compactStyles.isNotEmpty) 'styles': compactStyles,
      if (a.components.isNotEmpty)
        'components': {
          for (final entry in a.components.entries)
            entry.key: entry.value.toTypedCompactJson(),
        },
      if (a.behaviors.values.any((list) => list.isNotEmpty))
        'behaviors': {
          for (final entry in a.behaviors.entries)
            if (entry.value.isNotEmpty)
              entry.key: [for (final b in entry.value) b.toCompactJson()],
        },
      if (a.usages.isNotEmpty)
        'usages': {
          for (final entry in a.usages.entries)
            entry.key: entry.value.toCompactJson(),
        },
      if (a.pageCatalog.pages.isNotEmpty) 'pageCatalog': a.pageCatalog.toJson(),
    };
  }

  /// Sérialise un instantané de transfert sans modifier la sauvegarde complète.
  ///
  /// Les clés racines restent présentes pour préserver le remplacement des
  /// groupes lors de l'import, même lorsque leur valeur est celle par défaut.
  Map<String, Object?> toTransferJson(Appearance appearance) {
    final document = toJson(appearance);

    Map<String, Object?> compactOrFull(
      Map<String, Object?> full,
      Map<String, Object?> Function(Map<String, Object?>) compact,
      Object? Function(Map<String, Object?>) decode,
      String description,
    ) {
      try {
        final candidate = compact(full);
        if (ComponentStateHelpers.sameJsonValue(
          decode(full),
          decode(candidate),
        )) {
          return candidate;
        }
        debugPrint(
          '[AppearanceCodec] Transfert complet conservé pour $description : '
          'la sérialisation compacte modifierait sa configuration.',
        );
      } on FormatException catch (error) {
        debugPrint(
          '[AppearanceCodec] Transfert complet conservé pour $description : '
          '${error.message}',
        );
      }
      return full;
    }

    final styles = document['styles'];
    if (styles is Map) {
      document['styles'] = {
        for (final entry in styles.entries)
          entry.key: compactOrFull(
            Map<String, Object?>.from(entry.value as Map),
            (json) => ContainerStyle.fromJson(json).toCompactJson(),
            (json) => ContainerStyle.fromJson(json).toJson(),
            'le style "${entry.key}"',
          ),
      };
    }
    final components = document['components'];
    if (components is Map) {
      document['components'] = {
        for (final entry in components.entries)
          entry.key: compactOrFull(
            Map<String, Object?>.from(entry.value as Map),
            (json) => ComponentConfig.fromJson(json).toTypedCompactJson(),
            (json) => ComponentConfig.fromJson(json).toTypedJson(),
            'le composant "${entry.key}"',
          ),
      };
    }
    final behaviors = document['behaviors'];
    if (behaviors is Map) {
      document['behaviors'] = {
        for (final entry in behaviors.entries)
          entry.key: [
            for (final value in entry.value as List)
              compactOrFull(
                Map<String, Object?>.from(value as Map),
                (json) => ComponentBehavior.fromJson(json).toCompactJson(),
                (json) => ComponentBehavior.fromJson(json).toJson(),
                'un comportement de "${entry.key}"',
              ),
          ],
      };
    }
    return document;
  }

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
      'bindingDebounceMs',
      'bindingSaveOnBlurOnly',
      'styles',
      'components',
      'behaviors',
      'usages',
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

    int integer(String key, int fallback, int min, int max) {
      final value = json[key] ?? fallback;
      if (value is! num ||
          !value.isFinite ||
          value != value.roundToDouble() ||
          value < min ||
          value > max) {
        throw FormatException('Invalid "$key".');
      }
      return value.round();
    }

    bool boolean(String key, bool fallback) {
      final value = json[key] ?? fallback;
      if (value is! bool) {
        throw FormatException('Invalid "$key".');
      }
      return value;
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
      parsedAccent = JsonColor.parseLiteral(rawAccent, 'accent');
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
      bindingDebounceMs: integer(
        'bindingDebounceMs',
        Appearance.defaultBindingDebounceMs,
        Appearance.minBindingDebounceMs,
        Appearance.maxBindingDebounceMs,
      ),
      bindingSaveOnBlurOnly: boolean('bindingSaveOnBlurOnly', false),
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
      usages: {
        for (final entry in entries('usages').entries)
          entry.key: ComponentUsage.fromJson(entry.value),
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
        } else if (comp is SuperConditionalConfig &&
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
  /// - Entries in `usages` replace the usage of their ID; `null` deletes it.
  ///   Usages of deleted components are dropped.
  Appearance patchFromJson(
    Appearance current,
    Map<String, dynamic> patch, {
    bool logErrors = true,
  }) {
    final known = {
      'version',
      'mode',
      'accent',
      'backgroundOpacity',
      'windowOpacity',
      'windowEffect',
      'bindingDebounceMs',
      'bindingSaveOnBlurOnly',
      'styles',
      'components',
      'behaviors',
      'usages',
      'pageCatalog',
      'vibe',
      'merge',
      ...additionalKeys,
    };
    final unknownKeys = patch.keys
        .where((key) => !known.contains(key))
        .toList();
    if (unknownKeys.isNotEmpty) {
      if (logErrors) {
        debugPrint(
          '[AppearanceCodec] Clés de patch inconnues : $unknownKeys '
          '(attendues : ${known.toList()}).',
        );
      }
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
        accent = JsonColor.parseLiteral(patch['accent'], 'accent');
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

    int integer(String key, int fallback, int min, int max) {
      final value = patch[key] ?? fallback;
      if (value is! num ||
          !value.isFinite ||
          value != value.roundToDouble() ||
          value < min ||
          value > max) {
        throw FormatException('Invalid "$key".');
      }
      return value.round();
    }

    bool boolean(String key, bool fallback) {
      final value = patch[key] ?? fallback;
      if (value is! bool) {
        throw FormatException('Invalid "$key".');
      }
      return value;
    }

    final bindingDebounceMs = integer(
      'bindingDebounceMs',
      current.bindingDebounceMs,
      Appearance.minBindingDebounceMs,
      Appearance.maxBindingDebounceMs,
    );
    final bindingSaveOnBlurOnly = boolean(
      'bindingSaveOnBlurOnly',
      current.bindingSaveOnBlurOnly,
    );

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
            if (logErrors) {
              debugPrint(
                '[AppearanceCodec] Échec du décodage du style "$id" '
                '(FormatException) : ${error.message} | JSON: ${jsonEncode(entry.value)}',
              );
            }
            throw FormatException(
              'Style "$id" : ${error.message}',
              error.source,
              error.offset,
            );
          } catch (error) {
            if (logErrors) {
              debugPrint(
                '[AppearanceCodec] Échec du décodage du style "$id" '
                '(${error.runtimeType}) : $error | JSON: ${jsonEncode(entry.value)}',
              );
            }
            rethrow;
          }
        } else {
          if (logErrors) {
            debugPrint(
              '[AppearanceCodec] Style "$id" invalide (type: ${entry.value.runtimeType}).',
            );
          }
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
            if (logErrors) {
              debugPrint(
                '[AppearanceCodec] Échec du décodage du composant "$id" '
                '(type: $resolvedType, FormatException) : ${error.message} | '
                'JSON: ${jsonEncode(entry.value)}',
              );
            }
            throw FormatException(
              'Composant "$id" (type: $resolvedType) : ${error.message}',
              error.source,
              error.offset,
            );
          } catch (error) {
            if (logErrors) {
              debugPrint(
                '[AppearanceCodec] Échec du décodage du composant "$id" '
                '(type: $resolvedType, ${error.runtimeType}) : $error | '
                'JSON: ${jsonEncode(entry.value)}',
              );
            }
            rethrow;
          }
        } else {
          if (logErrors) {
            debugPrint(
              '[AppearanceCodec] Composant "$id" invalide (type: ${entry.value.runtimeType}).',
            );
          }
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
          } else if (comp is SuperConditionalConfig &&
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

    final behaviors = Map<String, List<ComponentBehavior>>.of(current.behaviors)
      ..removeWhere(
        (id, _) =>
            removedIds.contains(id) ||
            (id.endsWith(':item') &&
                removedIds.contains(id.substring(0, id.length - 5))),
      );
    if (patch.containsKey('behaviors') && patch['behaviors'] != null) {
      final rawBehaviors = patch['behaviors'];
      if (rawBehaviors is! Map) {
        throw const FormatException('Invalid "behaviors" map.');
      }
      for (final entry in rawBehaviors.entries) {
        final id = entry.key;
        if (id is! String || id.trim().isEmpty) {
          throw const FormatException('Invalid "behaviors" map.');
        }
        final value = entry.value;
        if (value == null) {
          behaviors.remove(id);
        } else if (value is List) {
          final parsed = <ComponentBehavior>[];
          for (final item in value) {
            if (item is! Map) {
              throw FormatException(
                'Comportement "$id" : chaque entrée doit être un objet JSON.',
              );
            }
            try {
              parsed.add(
                ComponentBehavior.fromJson(Map<String, dynamic>.from(item)),
              );
            } on FormatException catch (error) {
              throw FormatException(
                'Comportement "$id" : ${error.message}',
                error.source,
                error.offset,
              );
            }
          }
          if (parsed.isEmpty) {
            behaviors.remove(id);
          } else {
            behaviors[id] = List<ComponentBehavior>.unmodifiable(parsed);
          }
        } else {
          throw const FormatException('Invalid "behaviors" map.');
        }
      }
    }

    final usages = Map<String, ComponentUsage>.of(current.usages)
      ..removeWhere((id, _) => removedIds.contains(id));
    if (patch.containsKey('usages') && patch['usages'] != null) {
      final rawUsages = patch['usages'];
      if (rawUsages is! Map) {
        throw const FormatException('Invalid "usages" map.');
      }
      for (final entry in rawUsages.entries) {
        final id = entry.key;
        if (id is! String || id.trim().isEmpty) {
          throw const FormatException('Invalid "usages" map.');
        }
        if (entry.value == null) {
          usages.remove(id);
        } else {
          try {
            usages[id] = ComponentUsage.fromJson(entry.value);
          } on FormatException catch (error) {
            throw FormatException(
              'Usage "$id" : ${error.message}',
              error.source,
              error.offset,
            );
          }
        }
      }
    }

    return current.copyWith(
      mode: mode,
      accent: accent,
      backgroundOpacity: backgroundOpacity,
      windowOpacity: windowOpacity,
      windowEffect: windowEffect,
      bindingDebounceMs: bindingDebounceMs,
      bindingSaveOnBlurOnly: bindingSaveOnBlurOnly,
      styles: styles,
      components: components,
      behaviors: behaviors,
      usages: usages,
      pageCatalog: pageCatalog,
    );
  }

  /// Applique de manière tolérante chaque entrée valide de [patch] sur [current]
  /// tout en isolant les entrées en erreur dans [PartialPatchResult.rejectedEntries].
  PartialPatchResult patchFromJsonPartial(
    Appearance current,
    Map<String, dynamic> patch,
  ) {
    final known = {
      'version',
      'mode',
      'accent',
      'backgroundOpacity',
      'windowOpacity',
      'windowEffect',
      'bindingDebounceMs',
      'bindingSaveOnBlurOnly',
      'styles',
      'components',
      'behaviors',
      'usages',
      'pageCatalog',
      'vibe',
      'merge',
      ...additionalKeys,
    };
    final rejected = <PatchRejectedEntry>[];
    final applied = <String, dynamic>{};

    for (final key in patch.keys) {
      if (!known.contains(key)) {
        rejected.add(
          PatchRejectedEntry(
            section: 'root',
            key: key,
            message: 'Unknown appearance preference: $key.',
            rawValue: patch[key],
          ),
        );
      }
    }

    var mode = current.mode;
    if (patch.containsKey('mode') && patch['mode'] != 'vibe') {
      final candidate = ThemeMode.values
          .where((v) => v.name == patch['mode'])
          .firstOrNull;
      if (candidate == null) {
        rejected.add(
          PatchRejectedEntry(
            section: 'root',
            key: 'mode',
            message: 'Valeur invalide pour "mode".',
            rawValue: patch['mode'],
          ),
        );
      } else {
        mode = candidate;
        applied['mode'] = patch['mode'];
      }
    }

    var accent = current.accent;
    if (patch.containsKey('accent') && patch['accent'] != null) {
      try {
        accent = JsonColor.parseLiteral(patch['accent'], 'accent');
        applied['accent'] = patch['accent'];
      } on FormatException catch (error) {
        rejected.add(
          PatchRejectedEntry(
            section: 'root',
            key: 'accent',
            message: error.message,
            rawValue: patch['accent'],
          ),
        );
      }
    }

    double boundedScalar(String key, double fallback, double min, double max) {
      if (!patch.containsKey(key) || patch[key] == null) return fallback;
      final value = patch[key];
      if (value is! num || !value.isFinite || value < min || value > max) {
        rejected.add(
          PatchRejectedEntry(
            section: 'root',
            key: key,
            message: 'Invalid "$key".',
            rawValue: value,
          ),
        );
        return fallback;
      }
      applied[key] = value;
      return value.toDouble();
    }

    final backgroundOpacity = boundedScalar(
      'backgroundOpacity',
      current.backgroundOpacity,
      0,
      1,
    );
    final windowOpacity = boundedScalar(
      'windowOpacity',
      current.windowOpacity,
      .2,
      1,
    );

    var windowEffect = current.windowEffect;
    if (patch.containsKey('windowEffect') && patch['windowEffect'] != null) {
      final candidate = WindowEffect.values
          .where((v) => v.name == patch['windowEffect'])
          .firstOrNull;
      if (candidate == null) {
        rejected.add(
          PatchRejectedEntry(
            section: 'root',
            key: 'windowEffect',
            message: 'Valeur invalide pour "windowEffect".',
            rawValue: patch['windowEffect'],
          ),
        );
      } else {
        windowEffect = candidate;
        applied['windowEffect'] = patch['windowEffect'];
      }
    }

    int boundedInt(String key, int fallback, int min, int max) {
      if (!patch.containsKey(key) || patch[key] == null) return fallback;
      final value = patch[key];
      if (value is! num ||
          !value.isFinite ||
          value != value.roundToDouble() ||
          value < min ||
          value > max) {
        rejected.add(
          PatchRejectedEntry(
            section: 'root',
            key: key,
            message: 'Invalid "$key".',
            rawValue: value,
          ),
        );
        return fallback;
      }
      applied[key] = value.round();
      return value.round();
    }

    bool booleanValue(String key, bool fallback) {
      if (!patch.containsKey(key) || patch[key] == null) return fallback;
      final value = patch[key];
      if (value is! bool) {
        rejected.add(
          PatchRejectedEntry(
            section: 'root',
            key: key,
            message: 'Invalid "$key".',
            rawValue: value,
          ),
        );
        return fallback;
      }
      applied[key] = value;
      return value;
    }

    final bindingDebounceMs = boundedInt(
      'bindingDebounceMs',
      current.bindingDebounceMs,
      Appearance.minBindingDebounceMs,
      Appearance.maxBindingDebounceMs,
    );
    final bindingSaveOnBlurOnly = booleanValue(
      'bindingSaveOnBlurOnly',
      current.bindingSaveOnBlurOnly,
    );

    final styles = Map<String, ContainerStyle>.of(current.styles);
    if (patch.containsKey('styles') && patch['styles'] != null) {
      final rawStyles = patch['styles'];
      if (rawStyles is! Map) {
        rejected.add(
          PatchRejectedEntry(
            section: 'styles',
            key: 'styles',
            message: 'Invalid "styles" map.',
            rawValue: rawStyles,
          ),
        );
      } else {
        final appliedStyles = <String, Object?>{};
        for (final entry in rawStyles.entries) {
          final id = entry.key;
          if (id is! String || id.trim().isEmpty) continue;
          if (entry.value == null) {
            styles.remove(id);
            appliedStyles[id] = null;
          } else if (entry.value is Map) {
            final existing = styles[id];
            try {
              styles[id] = existing != null
                  ? existing.patchFromJson(entry.value as Map)
                  : ContainerStyle.fromJson(entry.value);
              appliedStyles[id] = entry.value;
            } on FormatException catch (error) {
              rejected.add(
                PatchRejectedEntry(
                  section: 'styles',
                  key: id,
                  message: 'Style "$id" : ${error.message}',
                  rawValue: entry.value,
                ),
              );
            } catch (error) {
              rejected.add(
                PatchRejectedEntry(
                  section: 'styles',
                  key: id,
                  message: 'Style "$id" : $error',
                  rawValue: entry.value,
                ),
              );
            }
          } else {
            rejected.add(
              PatchRejectedEntry(
                section: 'styles',
                key: id,
                message: 'Style "$id" : objet JSON attendu.',
                rawValue: entry.value,
              ),
            );
          }
        }
        if (appliedStyles.isNotEmpty) {
          applied['styles'] = appliedStyles;
        }
      }
    }

    final components = Map<String, ComponentConfig>.of(current.components);
    final removedIds = <String>{};
    final selfConstraints = <String, SlotSizeConstraints>{};
    if (patch.containsKey('components') && patch['components'] != null) {
      final rawComponents = patch['components'];
      if (rawComponents is! Map) {
        rejected.add(
          PatchRejectedEntry(
            section: 'components',
            key: 'components',
            message: 'Invalid "components" map.',
            rawValue: rawComponents,
          ),
        );
      } else {
        final appliedComponents = <String, Object?>{};
        for (final entry in rawComponents.entries) {
          final id = entry.key;
          if (id is! String || id.trim().isEmpty) continue;
          if (entry.value == null) {
            components.remove(id);
            styles.remove(id);
            removedIds.add(id);
            appliedComponents[id] = null;
          } else if (entry.value is Map) {
            final rawMap = entry.value as Map;
            final rawType = rawMap['type'] ?? rawMap['componentType'];
            final existing = components[id];
            final resolvedType =
                rawType ?? existing?.componentType ?? 'inconnu';
            final entryConstraints = <String, SlotSizeConstraints>{};
            try {
              final map = _extractSelfSlotSizeConstraints(
                id,
                rawMap,
                entryConstraints,
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
              selfConstraints.addAll(entryConstraints);
              appliedComponents[id] = entry.value;
            } on FormatException catch (error) {
              rejected.add(
                PatchRejectedEntry(
                  section: 'components',
                  key: id,
                  message:
                      'Composant "$id" (type: $resolvedType) : ${error.message}',
                  rawValue: entry.value,
                ),
              );
            } catch (error) {
              rejected.add(
                PatchRejectedEntry(
                  section: 'components',
                  key: id,
                  message: 'Composant "$id" (type: $resolvedType) : $error',
                  rawValue: entry.value,
                ),
              );
            }
          } else {
            rejected.add(
              PatchRejectedEntry(
                section: 'components',
                key: id,
                message: 'Composant "$id" : objet JSON attendu.',
                rawValue: entry.value,
              ),
            );
          }
        }
        if (appliedComponents.isNotEmpty) {
          applied['components'] = appliedComponents;
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
          } else if (comp is SuperConditionalConfig &&
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
      try {
        pageCatalog = EditorPageCatalog.fromJson(patch['pageCatalog']);
        applied['pageCatalog'] = patch['pageCatalog'];
      } on FormatException catch (error) {
        rejected.add(
          PatchRejectedEntry(
            section: 'pageCatalog',
            key: 'pageCatalog',
            message: error.message,
            rawValue: patch['pageCatalog'],
          ),
        );
      }
    }

    final behaviors = Map<String, List<ComponentBehavior>>.of(current.behaviors)
      ..removeWhere(
        (id, _) =>
            removedIds.contains(id) ||
            (id.endsWith(':item') &&
                removedIds.contains(id.substring(0, id.length - 5))),
      );
    if (patch.containsKey('behaviors') && patch['behaviors'] != null) {
      final rawBehaviors = patch['behaviors'];
      if (rawBehaviors is! Map) {
        rejected.add(
          PatchRejectedEntry(
            section: 'behaviors',
            key: 'behaviors',
            message: 'Invalid "behaviors" map.',
            rawValue: rawBehaviors,
          ),
        );
      } else {
        final appliedBehaviors = <String, Object?>{};
        for (final entry in rawBehaviors.entries) {
          final id = entry.key;
          if (id is! String || id.trim().isEmpty) continue;
          final value = entry.value;
          if (value == null) {
            behaviors.remove(id);
            appliedBehaviors[id] = null;
          } else if (value is List) {
            try {
              final parsed = <ComponentBehavior>[];
              for (final item in value) {
                if (item is! Map) {
                  throw FormatException(
                    'Comportement "$id" : chaque entrée doit être un objet JSON.',
                  );
                }
                parsed.add(
                  ComponentBehavior.fromJson(Map<String, dynamic>.from(item)),
                );
              }
              if (parsed.isEmpty) {
                behaviors.remove(id);
              } else {
                behaviors[id] = List<ComponentBehavior>.unmodifiable(parsed);
              }
              appliedBehaviors[id] = value;
            } on FormatException catch (error) {
              rejected.add(
                PatchRejectedEntry(
                  section: 'behaviors',
                  key: id,
                  message: error.message.startsWith('Comportement ')
                      ? error.message
                      : 'Comportement "$id" : ${error.message}',
                  rawValue: value,
                ),
              );
            }
          } else {
            rejected.add(
              PatchRejectedEntry(
                section: 'behaviors',
                key: id,
                message: 'Comportement "$id" : liste JSON attendue.',
                rawValue: value,
              ),
            );
          }
        }
        if (appliedBehaviors.isNotEmpty) {
          applied['behaviors'] = appliedBehaviors;
        }
      }
    }

    final usages = Map<String, ComponentUsage>.of(current.usages)
      ..removeWhere((id, _) => removedIds.contains(id));
    if (patch.containsKey('usages') && patch['usages'] != null) {
      final rawUsages = patch['usages'];
      if (rawUsages is! Map) {
        rejected.add(
          PatchRejectedEntry(
            section: 'usages',
            key: 'usages',
            message: 'Invalid "usages" map.',
            rawValue: rawUsages,
          ),
        );
      } else {
        final appliedUsages = <String, Object?>{};
        for (final entry in rawUsages.entries) {
          final id = entry.key;
          if (id is! String || id.trim().isEmpty) continue;
          if (entry.value == null) {
            usages.remove(id);
            appliedUsages[id] = null;
          } else {
            try {
              usages[id] = ComponentUsage.fromJson(entry.value);
              appliedUsages[id] = entry.value;
            } on FormatException catch (error) {
              rejected.add(
                PatchRejectedEntry(
                  section: 'usages',
                  key: id,
                  message: 'Usage "$id" : ${error.message}',
                  rawValue: entry.value,
                ),
              );
            }
          }
        }
        if (appliedUsages.isNotEmpty) {
          applied['usages'] = appliedUsages;
        }
      }
    }

    final nextAppearance = current.copyWith(
      mode: mode,
      accent: accent,
      backgroundOpacity: backgroundOpacity,
      windowOpacity: windowOpacity,
      windowEffect: windowEffect,
      bindingDebounceMs: bindingDebounceMs,
      bindingSaveOnBlurOnly: bindingSaveOnBlurOnly,
      styles: styles,
      components: components,
      behaviors: behaviors,
      usages: usages,
      pageCatalog: pageCatalog,
    );
    return PartialPatchResult(
      appearance: nextAppearance,
      appliedPatch: applied,
      rejectedEntries: List<PatchRejectedEntry>.unmodifiable(rejected),
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
