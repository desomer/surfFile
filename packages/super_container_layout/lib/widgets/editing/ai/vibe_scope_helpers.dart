/// Résout les composants, styles, comportements et usages autorisés dans un
/// scope Vibe.
library;

import 'dart:convert';

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
        if (bid is String &&
            !nonTargetedParents.contains(bid) &&
            (allowedSubtreeIds.contains(bid) || rawTargetIds.contains(bid))) {
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
        if (subtreeIds.contains(entry.key) || rawTargetIds.contains(entry.key))
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
}
