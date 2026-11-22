/// Résout les composants, styles, comportements et usages autorisés dans un
/// scope Vibe.
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart' show Axis;

import '../../../models/a4_page_config.dart';
import '../../../models/component_config.dart';
import '../../../models/json_numbers.dart';
import '../../../models/native_component_config.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/super_conditional_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../models/super_table_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/inspection/vibe_app_inspector.dart'
    show VibeVisibleTabState, VibeVisibleViewportSnapshot;
import '../../../theme/appearance.dart';
import '../slots/editor_context_menu.dart';

/// Fonctions pures de collecte, de filtrage et d'export des scopes Vibe.
abstract final class VibeScopeHelpers {
  /// Retourne les composants directement parents du ou des composants ciblés.
  static Set<String> parentIdsOfScope(Appearance current, VibeChatScope scope) {
    final targetIds = scope.canonicalComponentIds;
    final parents = <String>{};
    for (final target in scope.allTargets) {
      final targetId = target.canonicalComponentId;
      for (final entry in current.components.entries) {
        if (entry.key == targetId || targetIds.contains(entry.key)) continue;
        if (childrenOfComponent(entry.value).contains(targetId)) {
          parents.add(entry.key);
        }
      }
      if (target.canonicalParentComponentId case final explicitParent?) {
        if (!targetIds.contains(explicitParent)) {
          parents.add(explicitParent);
        }
      }
    }
    return parents;
  }

  /// Filtre un patch Vibe pour limiter ses modifications au sous-arbre ciblé.
  static Map<String, dynamic> filterPatchToScope(
    Appearance current,
    Map<String, dynamic> patch,
    VibeChatScope scope,
  ) {
    final payload = patch['data'] is Map<String, dynamic>
        ? patch['data'] as Map<String, dynamic>
        : patch;
    final targetIds = scope.canonicalComponentIds;
    final rawTargetIds = <String>{
      for (final target in scope.allTargets) target.componentId,
      ...targetIds,
    };
    final parents = parentIdsOfScope(current, scope);
    final topRootIds = parents.isNotEmpty
        ? <String>{...parents, ...targetIds}
        : targetIds;
    final nonTargetedParents = scope.isMultiTarget
        ? parents.difference(targetIds)
        : const <String>{};

    final existingSubtree = existingSubtreeIds(current, scope);
    final outsideExistingIds = <String>{
      for (final id in current.components.keys)
        if (!existingSubtree.contains(id) && !targetIds.contains(id)) id,
    };

    final allowedSubtreeIds = <String>{...existingSubtree};
    final rawComponents = payload['components'];
    final placedByOutsideIds = <String>{};

    if (rawComponents is Map) {
      for (final entry in rawComponents.entries) {
        final cid = entry.key;
        final cval = entry.value;
        if (cid is! String || cval is! Map) continue;
        if (outsideExistingIds.contains(cid)) {
          placedByOutsideIds.addAll(_placedIdsInPatchMap(cval));
        }
      }

      final queue = <String>[...allowedSubtreeIds];
      while (queue.isNotEmpty) {
        final id = queue.removeLast();
        if (!nonTargetedParents.contains(id)) {
          for (final childId in childrenOfComponent(current.components[id])) {
            if (!outsideExistingIds.contains(childId) &&
                allowedSubtreeIds.add(childId)) {
              queue.add(childId);
            }
          }
        }
        if (rawComponents[id] is Map) {
          for (final childId in _placedIdsInPatchMap(
            rawComponents[id] as Map,
          )) {
            if (!outsideExistingIds.contains(childId) &&
                allowedSubtreeIds.add(childId)) {
              queue.add(childId);
            }
          }
        }
      }
    }

    final filteredComponents = <String, Object?>{};
    if (rawComponents is Map) {
      for (final entry in rawComponents.entries) {
        final cid = entry.key;
        final cval = entry.value;
        if (cid is! String) continue;
        if (allowedSubtreeIds.contains(cid)) {
          if (topRootIds.contains(cid) && cval == null) continue;
          filteredComponents[cid] = cval;
        } else if (!current.components.containsKey(cid) &&
            !outsideExistingIds.contains(cid) &&
            !placedByOutsideIds.contains(cid)) {
          filteredComponents[cid] = cval;
        }
      }
    }

    bool isStyleAllowed(String styleId) {
      if (nonTargetedParents.contains(styleId)) return false;
      if (allowedSubtreeIds.contains(styleId)) return true;
      if (styleId.endsWith(':item')) {
        final base = styleId.substring(0, styleId.length - 5);
        if (nonTargetedParents.contains(base)) return false;
        if (allowedSubtreeIds.contains(base)) return true;
        if (rawTargetIds.contains(base)) return true;
      }
      return rawTargetIds.contains(styleId);
    }

    final filteredStyles = <String, Object?>{};
    if (payload['styles'] case final Map rawStyles) {
      for (final entry in rawStyles.entries) {
        if (entry.key is String && isStyleAllowed(entry.key as String)) {
          filteredStyles[entry.key as String] = entry.value;
        }
      }
    }

    final filteredBehaviors = <String, Object?>{};
    if (payload['behaviors'] case final Map rawBehaviors) {
      for (final entry in rawBehaviors.entries) {
        final bid = entry.key;
        if (bid is String && isStyleAllowed(bid)) {
          filteredBehaviors[bid] = entry.value;
        }
      }
    }

    final filteredUsages = <String, Object?>{};
    if (payload['usages'] case final Map rawUsages) {
      for (final entry in rawUsages.entries) {
        final uid = entry.key;
        if (uid is String &&
            !nonTargetedParents.contains(uid) &&
            (allowedSubtreeIds.contains(uid) || rawTargetIds.contains(uid))) {
          filteredUsages[uid] = entry.value;
        }
      }
    }

    return <String, dynamic>{
      if (filteredComponents.isNotEmpty) 'components': filteredComponents,
      if (filteredStyles.isNotEmpty) 'styles': filteredStyles,
      if (filteredBehaviors.isNotEmpty) 'behaviors': filteredBehaviors,
      if (filteredUsages.isNotEmpty) 'usages': filteredUsages,
    };
  }

  /// Exporte un snapshot compact d'un scope et de son sous-arbre.
  static String exportScopedAi(
    Appearance appearance,
    VibeChatScope scope, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final targetIds = scope.canonicalComponentIds;
    final rawTargetIds = <String>{
      for (final target in scope.allTargets) target.componentId,
      ...targetIds,
    };
    final parentIds = parentIdsOfScope(appearance, scope);
    final subtreeIds = <String>{
      ...targetIds,
      ...parentIds,
      ...existingSubtreeIds(appearance, scope),
    };
    final compactJson = codec.toCompactJson(appearance);
    final allComponents =
        compactJson['components'] as Map<String, Object?>? ?? const {};
    final allStyles =
        compactJson['styles'] as Map<String, Object?>? ?? const {};
    final allBehaviors =
        compactJson['behaviors'] as Map<String, Object?>? ?? const {};
    final allUsages =
        compactJson['usages'] as Map<String, Object?>? ?? const {};

    final scopedComponents = <String, Object?>{
      for (final id in subtreeIds)
        if (allComponents.containsKey(id)) id: allComponents[id],
    };
    final scopedStyles = <String, Object?>{
      for (final entry in allStyles.entries)
        if (subtreeIds.contains(entry.key) ||
            rawTargetIds.contains(entry.key) ||
            (entry.key.endsWith(':item') &&
                (subtreeIds.contains(
                      entry.key.substring(0, entry.key.length - 5),
                    ) ||
                    rawTargetIds.contains(
                      entry.key.substring(0, entry.key.length - 5),
                    ))))
          entry.key: entry.value,
    };
    final scopedBehaviors = <String, Object?>{
      for (final entry in allBehaviors.entries)
        if (subtreeIds.contains(entry.key) ||
            rawTargetIds.contains(entry.key) ||
            (entry.key.endsWith(':item') &&
                (subtreeIds.contains(
                      entry.key.substring(0, entry.key.length - 5),
                    ) ||
                    rawTargetIds.contains(
                      entry.key.substring(0, entry.key.length - 5),
                    ))))
          entry.key: entry.value,
    };
    final scopedUsages = <String, Object?>{
      for (final entry in allUsages.entries)
        if (subtreeIds.contains(entry.key) || rawTargetIds.contains(entry.key))
          entry.key: entry.value,
    };

    final Map<String, Object?> scopeMetadata;
    if (!scope.isMultiTarget) {
      final targetId = scope.canonicalComponentId;
      final rawTargetId = scope.componentId;
      scopeMetadata = {
        'componentId': targetId,
        if (rawTargetId != targetId) 'surfaceId': rawTargetId,
        'zoneId': ?scope.zoneId,
        if (parentIds.isNotEmpty)
          'parentComponentId': parentIds.length == 1
              ? parentIds.first
              : parentIds.toList(),
        'label': scope.displayLabel,
      };
    } else {
      scopeMetadata = {
        'multiTarget': true,
        'targets': [
          for (final target in scope.allTargets)
            {
              'componentId': target.canonicalComponentId,
              if (target.componentId != target.canonicalComponentId)
                'surfaceId': target.componentId,
              'zoneId': ?target.zoneId,
              if (target.canonicalParentComponentId != null)
                'parentComponentId': target.canonicalParentComponentId,
              'label': target.displayLabel,
            },
        ],
        if (parentIds.isNotEmpty) 'parentComponentIds': parentIds.toList(),
        'label': scope.displayLabel,
      };
    }

    return jsonEncode(
      JsonNumbers.normalizeMap({
        'scope': scopeMetadata,
        'components': scopedComponents,
        'styles': scopedStyles,
        if (scopedBehaviors.isNotEmpty) 'behaviors': scopedBehaviors,
        if (scopedUsages.isNotEmpty) 'usages': scopedUsages,
      }),
    );
  }

  /// Composants directement placés dans [component], éventuellement une région.
  static Iterable<String> childrenOfComponent(
    ComponentConfig? component, {
    String? onlyZoneId,
  }) {
    if (component == null) return const [];
    if (onlyZoneId != null && onlyZoneId.isNotEmpty) {
      return switch (component) {
        final SuperLayoutConfig layout => () {
          final zone = SuperLayoutZone.values
              .where((z) => z.name == onlyZoneId)
              .firstOrNull;
          return zone == null
              ? const <String>[]
              : layout.placementsOf(layout.contentZone(zone));
        }(),
        final SuperListViewConfig list => () {
          final zone = SuperLayoutZone.values
              .where((z) => z.name == onlyZoneId)
              .firstOrNull;
          return zone == null
              ? const <String>[]
              : list.template.placementsOf(list.template.contentZone(zone));
        }(),
        final SuperTabConfig tab => tab.slotsOf(onlyZoneId),
        final SuperConditionalConfig cond => cond.slotsOf(onlyZoneId),
        final SuperTreeViewConfig tree => tree.slotsOf(onlyZoneId),
        final SuperTableConfig table => table.slotsOf(onlyZoneId),
        final NativeComponentConfig native => native.slotsOf(onlyZoneId),
        final ScaffoldPageConfig scaffold => scaffold.native.slotsOf(
          onlyZoneId,
        ),
        final A4PageConfig a4 => a4.childSlots.keys,
        _ => const <String>[],
      };
    }
    return switch (component) {
      final SuperLayoutConfig layout => layout.placedSlotIds,
      final SuperListViewConfig list => list.template.placedSlotIds,
      final SuperTabConfig tab => tab.placedSlotIds,
      final SuperConditionalConfig cond => cond.placedSlotIds,
      final SuperTreeViewConfig tree => tree.placedSlotIds,
      final SuperTableConfig table => table.placedSlotIds,
      final NativeComponentConfig native => native.placements.values.expand(
        (ids) => ids,
      ),
      final ScaffoldPageConfig scaffold =>
        scaffold.native.placements.values.expand((ids) => ids),
      final A4PageConfig a4 => a4.childSlots.keys,
      _ => const <String>[],
    };
  }

  /// Identifiants racines pris en compte pour une modification restreinte.
  static Set<String> scopeRootIds(Appearance current, VibeChatScope scope) =>
      <String>{
        ...parentIdsOfScope(current, scope),
        ...scope.canonicalComponentIds,
      };

  /// Retourne les identifiants déjà présents dans le sous-arbre ciblé.
  static Set<String> existingSubtreeIds(
    Appearance current,
    VibeChatScope scope,
  ) {
    if (!scope.isMultiTarget) {
      final visited = <String>{};
      final pending = <String>[...scopeRootIds(current, scope)];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!visited.add(id)) continue;
        pending.addAll(childrenOfComponent(current.components[id]));
      }
      return visited;
    }

    final parents = parentIdsOfScope(current, scope);
    final visited = <String>{...parents};
    final pending = <String>[];
    for (final target in scope.allTargets) {
      final id = target.canonicalComponentId;
      if (target.zoneId != null && target.zoneId!.isNotEmpty) {
        visited.add(id);
        pending.addAll(
          childrenOfComponent(
            current.components[id],
            onlyZoneId: target.zoneId,
          ),
        );
      } else {
        pending.add(id);
      }
    }
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!visited.add(id)) continue;
      pending.addAll(childrenOfComponent(current.components[id]));
    }
    return visited;
  }

  static Iterable<String> _placedIdsInPatchMap(
    Map<Object?, Object?> map, {
    String? onlyZoneId,
  }) sync* {
    Iterable<String> fromPlacementsMap(Object? placements) sync* {
      if (placements is! Map) return;
      for (final entry in placements.entries) {
        if (onlyZoneId != null && entry.key != onlyZoneId) continue;
        final list = entry.value;
        if (list is List) {
          for (final item in list) {
            if (item is String && item.trim().isNotEmpty) {
              yield item.trim();
            } else if (item is Map && item['id'] is String) {
              final id = (item['id'] as String).trim();
              if (id.isNotEmpty) yield id;
            }
          }
        }
      }
    }

    yield* fromPlacementsMap(
      map.containsKey('placements') ? map['placements'] : map['zones'],
    );
    if (map['template'] is Map) {
      final template = map['template'] as Map;
      yield* fromPlacementsMap(
        template.containsKey('placements')
            ? template['placements']
            : template['zones'],
      );
    }
    if (map['row'] is Map) {
      final row = map['row'] as Map;
      yield* fromPlacementsMap(
        row.containsKey('placements') ? row['placements'] : row['zones'],
      );
    }
    if (map['sheets'] is List) {
      for (final sheet in map['sheets'] as List) {
        if (sheet is Map && sheet['rootSlotId'] is String) {
          final id = (sheet['rootSlotId'] as String).trim();
          if (id.isNotEmpty) yield id;
        }
      }
    }
    for (final slotKey in const ['headerSlotId', 'footerSlotId']) {
      if (map[slotKey] is String) {
        final id = (map[slotKey] as String).trim();
        if (id.isNotEmpty) yield id;
      }
    }
    if (onlyZoneId == null || onlyZoneId == 'tabs') {
      if (map['tabs'] is List) {
        for (final item in map['tabs'] as List) {
          if (item is String && item.trim().isNotEmpty) yield item.trim();
          if (item is Map && item['id'] is String) {
            final id = (item['id'] as String).trim();
            if (id.isNotEmpty) yield id;
          }
        }
      }
    }
    if (onlyZoneId == null || onlyZoneId == 'content') {
      if (map['content'] is List) {
        for (final item in map['content'] as List) {
          if (item is String && item.trim().isNotEmpty) yield item.trim();
          if (item is Map && item['id'] is String) {
            final id = (item['id'] as String).trim();
            if (id.isNotEmpty) yield id;
          }
        }
      }
    }
    if (map['contents'] is Map) {
      for (final entry in (map['contents'] as Map).entries) {
        final regionKey = 'content:${entry.key}';
        if (onlyZoneId != null &&
            onlyZoneId != regionKey &&
            onlyZoneId != entry.key) {
          continue;
        }
        if (entry.value is List) {
          for (final item in entry.value as List) {
            if (item is String && item.trim().isNotEmpty) yield item.trim();
            if (item is Map && item['id'] is String) {
              final id = (item['id'] as String).trim();
              if (id.isNotEmpty) yield id;
            }
          }
        }
      }
    }
  }

  static String? _slotItemId(Object? item) {
    if (item is String && item.trim().isNotEmpty) return item.trim();
    if (item is Map && item['id'] is String) {
      final id = (item['id'] as String).trim();
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  static List<Object?> _preserveProtectedSlotsInList(
    List<String> existingSlots,
    List<Object?> nextRawSlots,
    Set<String> protectedIds, {
    required Map<String, String> existingSlotTypes,
  }) {
    Object? normalizeItem(Object? raw) {
      if (raw is String && raw.trim().isNotEmpty) {
        final id = raw.trim();
        final knownType = existingSlotTypes[id];
        if (knownType != null && knownType != id) {
          return <String, Object?>{'id': id, 'type': knownType};
        }
        return id;
      }
      if (raw is Map && raw['id'] is String && raw['type'] == null) {
        final id = (raw['id'] as String).trim();
        final knownType = existingSlotTypes[id];
        if (knownType != null && knownType != id) {
          return <String, Object?>{...raw, 'type': knownType};
        }
      }
      return raw;
    }

    if (existingSlots.isEmpty) {
      return [for (final item in nextRawSlots) normalizeItem(item)];
    }
    final nextIds = <String>{for (final raw in nextRawSlots) ?_slotItemId(raw)};
    final missingProtected = <String>[
      for (final s in existingSlots)
        if (protectedIds.contains(s) && !nextIds.contains(s)) s,
    ];
    if (missingProtected.isEmpty) {
      return [for (final item in nextRawSlots) normalizeItem(item)];
    }

    final sharedSurviving = <String>[
      for (final s in existingSlots)
        if (nextIds.contains(s)) s,
    ];
    if (sharedSurviving.isEmpty) {
      return <Object?>[
        for (final s in missingProtected) normalizeItem(s),
        for (final raw in nextRawSlots) normalizeItem(raw),
      ];
    }

    final beforeAnchor = <String, List<String>>{};
    final afterAll = <String>[];
    var anchorIdx = 0;
    for (final s in existingSlots) {
      if (anchorIdx < sharedSurviving.length &&
          s == sharedSurviving[anchorIdx]) {
        anchorIdx++;
        continue;
      }
      if (!protectedIds.contains(s) || nextIds.contains(s)) continue;
      if (anchorIdx < sharedSurviving.length) {
        beforeAnchor
            .putIfAbsent(sharedSurviving[anchorIdx], () => <String>[])
            .add(s);
      } else {
        afterAll.add(s);
      }
    }

    final merged = <Object?>[];
    for (final raw in nextRawSlots) {
      final id = _slotItemId(raw);
      if (id != null) {
        final preceding = beforeAnchor.remove(id);
        if (preceding != null) {
          for (final p in preceding) {
            merged.add(normalizeItem(p));
          }
        }
      }
      merged.add(normalizeItem(raw));
    }
    for (final s in afterAll) {
      merged.add(normalizeItem(s));
    }
    return merged;
  }

  static void _preserveContainerSlotMetadata(
    Map<String, Object?> copy,
    ComponentConfig existingComp,
    Set<String> protectedIds,
  ) {
    final (
      Map<String, String> oldTypes,
      Map<String, String> oldLabels,
      Map<String, SlotSizeConstraints> oldConstraints,
    ) = switch (existingComp) {
      final SuperLayoutConfig c => (
        c.slotTypes,
        c.slotLabels,
        c.slotSizeConstraints,
      ),
      final SuperTabConfig c => (
        c.slotTypes,
        c.slotLabels,
        c.slotSizeConstraints,
      ),
      final NativeComponentConfig c => (
        c.slotTypes,
        c.slotLabels,
        c.slotSizeConstraints,
      ),
      final ScaffoldPageConfig c => (
        c.native.slotTypes,
        c.native.slotLabels,
        c.native.slotSizeConstraints,
      ),
      _ => (
        const <String, String>{},
        const <String, String>{},
        const <String, SlotSizeConstraints>{},
      ),
    };

    if (oldTypes.isNotEmpty && existingComp is! SuperLayoutConfig) {
      final nextTypes = <String, Object?>{
        ...oldTypes,
        if (copy['slotTypes'] case final Map m)
          for (final e in m.entries)
            if (e.key is String && !protectedIds.contains(e.key))
              e.key as String: e.value,
      };
      copy['slotTypes'] = nextTypes;
    }
    if (oldLabels.isNotEmpty) {
      final nextLabels = <String, Object?>{
        ...oldLabels,
        if (copy['slotLabels'] case final Map m)
          for (final e in m.entries)
            if (e.key is String && !protectedIds.contains(e.key))
              e.key as String: e.value,
      };
      copy['slotLabels'] = nextLabels;
    }
    if (oldConstraints.isNotEmpty) {
      final nextConstraints = <String, Object?>{
        for (final e in oldConstraints.entries) e.key: e.value.toJson(),
        if (copy['slotSizeConstraints'] case final Map m)
          for (final e in m.entries)
            if (e.key is String && !protectedIds.contains(e.key))
              e.key as String: e.value,
      };
      copy['slotSizeConstraints'] = nextConstraints;
    }
    if (existingComp is SuperLayoutConfig && !copy.containsKey('zoneFlows')) {
      if (existingComp.zoneFlows.isNotEmpty) {
        copy['zoneFlows'] = <String, Object?>{
          for (final e in existingComp.zoneFlows.entries)
            e.key.name: e.value.toJson(),
        };
      }
    }
    if (existingComp is SuperLayoutConfig && !copy.containsKey('zoneAxes')) {
      if (existingComp.zoneAxes.isNotEmpty) {
        copy['zoneAxes'] = <String, Object?>{
          for (final e in existingComp.zoneAxes.entries)
            e.key.name: e.value == Axis.horizontal ? 'row' : 'column',
        };
      }
    }
  }

  /// Protège les onglets inactifs, les composants hors du scroll courant et `pageCatalog`
  /// lorsqu'un patch Vibe est généré en mode « Uniquement visible ».
  static Map<String, dynamic> filterPatchToVisibleViewport(
    Appearance current,
    Map<String, dynamic> patch,
    VibeVisibleViewportSnapshot snapshot,
  ) {
    final isWrapped = patch['data'] is Map<String, dynamic>;
    final payload = isWrapped
        ? Map<String, dynamic>.of(patch['data'] as Map<String, dynamic>)
        : Map<String, dynamic>.of(patch);
    payload.remove('pageCatalog');

    if (!snapshot.hasMeasuredViewport) {
      return isWrapped ? <String, dynamic>{...patch, 'data': payload} : payload;
    }

    final protectedIds = snapshot.protectedOffscreenComponentIds;
    final tabById = <String, VibeVisibleTabState>{
      for (final t in snapshot.activeTabs) t.tabComponentId: t,
    };

    bool isProtectedStyleOrBehavior(String key) {
      if (protectedIds.contains(key)) return true;
      if (key.endsWith(':item')) {
        final base = key.substring(0, key.length - 5);
        if (protectedIds.contains(base)) return true;
      }
      return false;
    }

    if (payload['components'] case final Map rawComponents) {
      final nextComponents = <String, Object?>{};
      for (final entry in rawComponents.entries) {
        final cid = entry.key;
        final cval = entry.value;
        if (cid is! String) continue;
        if (protectedIds.contains(cid)) continue;
        if (snapshot.ancestorComponentIds.contains(cid) && cval == null) {
          continue;
        }

        if (cval is Map) {
          final rawCopy = Map<String, Object?>.from(cval);
          final existingComp = current.components[cid];
          final activeTabState = tabById[cid];
          if (activeTabState != null && existingComp is SuperTabConfig) {
            rawCopy.remove('initialIndex');
            if (rawCopy.keys.every((k) => k == 'type')) {
              continue;
            }
          }
          final copy = existingComp != null
              ? <String, Object?>{...existingComp.toJson(), ...rawCopy}
              : rawCopy;
          if (activeTabState != null && existingComp is SuperTabConfig) {
            copy['initialIndex'] = existingComp.initialIndex;
          }

          final placementsKey = copy.containsKey('placements')
              ? 'placements'
              : (copy.containsKey('zones') ? 'zones' : null);
          if (placementsKey != null && copy[placementsKey] is Map) {
            final rawPl = Map<String, Object?>.from(copy[placementsKey] as Map);
            if (activeTabState != null && existingComp is SuperTabConfig) {
              rawPl[SuperTabConfig.tabsZone] = List<String>.of(
                existingComp.tabSlotIds,
              );
              for (final inactiveZone in activeTabState.inactiveZones) {
                rawPl[inactiveZone] = List<String>.of(
                  existingComp.slotsOf(inactiveZone),
                );
              }
            }
            if (existingComp != null) {
              for (final zEntry in rawPl.entries.toList()) {
                if (activeTabState != null &&
                    (zEntry.key == SuperTabConfig.tabsZone ||
                        activeTabState.inactiveZones.contains(zEntry.key))) {
                  continue;
                }
                if (zEntry.value is List) {
                  final oldZoneSlots = childrenOfComponent(
                    existingComp,
                    onlyZoneId: zEntry.key,
                  ).toList(growable: false);
                  final existingSlotTypes = switch (existingComp) {
                    final SuperLayoutConfig c => c.slotTypes,
                    final SuperTabConfig c => c.slotTypes,
                    final NativeComponentConfig c => c.slotTypes,
                    final ScaffoldPageConfig c => c.native.slotTypes,
                    _ => const <String, String>{},
                  };
                  rawPl[zEntry.key] = _preserveProtectedSlotsInList(
                    oldZoneSlots,
                    zEntry.value as List<Object?>,
                    protectedIds,
                    existingSlotTypes: existingSlotTypes,
                  );
                }
              }
              _preserveContainerSlotMetadata(copy, existingComp, protectedIds);
            }
            copy[placementsKey] = rawPl;
          }
          nextComponents[cid] = copy;
        } else {
          nextComponents[cid] = cval;
        }
      }
      if (nextComponents.isEmpty) {
        payload.remove('components');
      } else {
        payload['components'] = nextComponents;
      }
    }

    for (final section in const <String>['styles', 'behaviors', 'usages']) {
      if (payload[section] case final Map rawMap) {
        final filtered = <String, Object?>{
          for (final entry in rawMap.entries)
            if (entry.key is String &&
                !isProtectedStyleOrBehavior(entry.key as String))
              entry.key as String: entry.value,
        };
        if (filtered.isEmpty) {
          payload.remove(section);
        } else {
          payload[section] = filtered;
        }
      }
    }

    return isWrapped ? <String, dynamic>{...patch, 'data': payload} : payload;
  }
}
