import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../ai/call_gemini.dart';
import '../../../ai/vibe_chat_attachment.dart';
import '../../../models/component_config.dart';
import '../../../models/native_component_config.dart';
import '../../../models/registry.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/appearance_store.dart';
import '../../../services/appearance/appearance_transfer.dart';
import '../../../super_app.dart';
import '../../../theme/appearance.dart';
import '../dialogs/editor_dialog.dart';
import '../slots/editor_context_menu.dart';

export '../../../ai/vibe_chat_attachment.dart';
export '../slots/editor_context_menu.dart' show VibeChatScope;

class VibeChatDialog extends StatefulWidget {
  const VibeChatDialog({
    required this.controller,
    required this.codec,
    required this.onClose,
    required this.onDrag,
    required this.generate,
    this.scope,
    this.onScopeChanged,
    this.pickAttachments,
    this.pasteAttachments,
    this.validateAppearance,
    this.registry,
    super.key,
  });

  final ValueNotifier<Appearance> controller;
  final AppearanceCodec codec;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDrag;
  final Future<String> Function(String prompt) generate;
  final VibeChatScope? scope;
  final ValueChanged<VibeChatScope?>? onScopeChanged;
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final void Function(Appearance appearance)? validateAppearance;
  final Registry? registry;

  /// Opens the Vibe AI chat targeted at [scope]: reuses the active
  /// `StyleEditBanner` panel when mounted, or falls back to an editor dialog.
  static Future<void> showScoped(
    BuildContext context,
    VibeChatScope scope,
  ) async {
    if (VibeChatScope.onOpenRequested case final handler?
        when handler(scope)) {
      return;
    }
    final appearance = AppearanceScope.controllerOf(context);
    if (appearance == null) return;
    final codec = AppearanceServicesScope.codecOf(context);
    final registry = SuperApp.maybeOf(context)?.registry;
    await showEditorDialog<void>(
      context: context,
      target: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SizedBox(
          width: 440,
          height: 600,
          child: VibeChatDialog(
            controller: appearance,
            codec: codec,
            registry: registry,
            scope: scope,
            onClose: () => Navigator.of(dialogContext).pop(),
            onDrag: (_) {},
            generate: callGemini,
          ),
        ),
      ),
    );
  }

  /// Returns the direct child slot IDs placed inside [component], optionally
  /// restricted to [onlyZoneId].
  static Iterable<String> _childrenOfComponent(
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
        final NativeComponentConfig native => native.slotsOf(onlyZoneId),
        final ScaffoldPageConfig scaffold =>
          scaffold.native.slotsOf(onlyZoneId),
        _ => const <String>[],
      };
    }
    return switch (component) {
      final SuperLayoutConfig layout => layout.placedSlotIds,
      final SuperListViewConfig list => list.template.placedSlotIds,
      final SuperTabConfig tab => tab.placedSlotIds,
      final NativeComponentConfig native =>
        native.placements.values.expand((ids) => ids),
      final ScaffoldPageConfig scaffold =>
        scaffold.native.placements.values.expand((ids) => ids),
      _ => const <String>[],
    };
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
      final t = map['template'] as Map;
      yield* fromPlacementsMap(
        t.containsKey('placements') ? t['placements'] : t['zones'],
      );
    }
    if (map['row'] is Map) {
      final r = map['row'] as Map;
      yield* fromPlacementsMap(
        r.containsKey('placements') ? r['placements'] : r['zones'],
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

  /// Collects all existing component IDs in [current] belonging to [scope]'s
  /// modifiable subtree (including [scope.canonicalComponentId] when
  /// `zoneId == null`, or only the descendants of `zoneId` when `zoneId != null`).
  static Set<String> _existingSubtreeIds(
    Appearance current,
    VibeChatScope scope,
  ) {
    final targetId = scope.canonicalComponentId;
    final zoneId = scope.zoneId;
    final visited = <String>{};
    final pending = <String>[
      if (zoneId == null || zoneId.isEmpty)
        targetId
      else
        ..._childrenOfComponent(
          current.components[targetId],
          onlyZoneId: zoneId,
        ),
    ];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!visited.add(id)) continue;
      pending.addAll(_childrenOfComponent(current.components[id]));
    }
    return visited;
  }

  static Map<String, Object?> _stringObjectMap(Object? raw) => raw is Map
      ? <String, Object?>{
          for (final entry in raw.entries)
            if (entry.key is String) entry.key as String: entry.value,
        }
      : <String, Object?>{};

  static Map<String, Object?>? _filterLayoutMapToZone(
    SuperLayoutConfig baseLayout,
    Map<Object?, Object?> rawMap,
    String zoneId,
    Set<String> existingZoneSlots,
    Set<String> allowedSlotIds,
  ) {
    final baseJson = Map<String, Object?>.of(baseLayout.toJson());
    var changed = false;
    const sides = {'north', 'south', 'west', 'east'};
    if (sides.contains(zoneId)) {
      if (rawMap.containsKey(zoneId)) {
        baseJson[zoneId] = rawMap[zoneId];
        changed = true;
      }
      final sizeKey = '${zoneId}Size';
      if (rawMap.containsKey(sizeKey)) {
        baseJson[sizeKey] = rawMap[sizeKey];
        changed = true;
      }
      if (rawMap['autoSides'] is List) {
        final rawAuto = (rawMap['autoSides'] as List)
            .whereType<String>()
            .toSet();
        final mergedAuto = {for (final z in baseLayout.autoSides) z.name};
        if (rawAuto.contains(zoneId)) {
          mergedAuto.add(zoneId);
        } else {
          mergedAuto.remove(zoneId);
        }
        baseJson['autoSides'] = mergedAuto.toList();
        changed = true;
      }
      if (rawMap['sideResizing'] is Map &&
          (rawMap['sideResizing'] as Map).containsKey(zoneId)) {
        final map = _stringObjectMap(baseJson['sideResizing']);
        map[zoneId] = (rawMap['sideResizing'] as Map)[zoneId];
        baseJson['sideResizing'] = map;
        changed = true;
      }
      if (rawMap['collapsedSides'] is Map &&
          (rawMap['collapsedSides'] as Map).containsKey(zoneId)) {
        final map = _stringObjectMap(baseJson['collapsedSides']);
        map[zoneId] = (rawMap['collapsedSides'] as Map)[zoneId];
        baseJson['collapsedSides'] = map;
        changed = true;
      }
    }

    final rawPlacements = rawMap.containsKey('placements')
        ? rawMap['placements']
        : rawMap['zones'];
    if (rawPlacements is Map && rawPlacements.containsKey(zoneId)) {
      final mergedPlacements = _stringObjectMap(baseJson['placements']);
      mergedPlacements[zoneId] = rawPlacements[zoneId];
      baseJson['placements'] = mergedPlacements;
      if (sides.contains(zoneId) &&
          !rawMap.containsKey(zoneId) &&
          rawPlacements[zoneId] is List &&
          (rawPlacements[zoneId] as List).isNotEmpty) {
        baseJson[zoneId] = true;
      }
      changed = true;
    }

    if (rawMap['zoneAxes'] is Map &&
        (rawMap['zoneAxes'] as Map).containsKey(zoneId)) {
      final mergedAxes = _stringObjectMap(baseJson['zoneAxes']);
      mergedAxes[zoneId] = (rawMap['zoneAxes'] as Map)[zoneId];
      baseJson['zoneAxes'] = mergedAxes;
      changed = true;
    }

    if (rawMap['zoneFlows'] is Map &&
        (rawMap['zoneFlows'] as Map).containsKey(zoneId)) {
      final mergedFlows = _stringObjectMap(baseJson['zoneFlows']);
      mergedFlows[zoneId] = (rawMap['zoneFlows'] as Map)[zoneId];
      baseJson['zoneFlows'] = mergedFlows;
      changed = true;
    }

    for (final mapKey in const [
      'slotSizeConstraints',
      'slotPreferredSizes',
      'slotLabels',
    ]) {
      if (rawMap[mapKey] is Map) {
        final incoming = rawMap[mapKey] as Map;
        final merged = <String, Object?>{
          for (final entry
              in (baseJson[mapKey] as Map? ?? const {}).entries)
            if (entry.key is String &&
                !existingZoneSlots.contains(entry.key as String))
              entry.key as String: entry.value,
        };
        var slotMapChanged = false;
        for (final entry in incoming.entries) {
          if (entry.key is String &&
              allowedSlotIds.contains(entry.key as String)) {
            merged[entry.key as String] = entry.value;
            slotMapChanged = true;
          }
        }
        if (slotMapChanged) {
          baseJson[mapKey] = merged;
          changed = true;
        }
      }
    }

    if (!changed) return null;
    return {'type': 'layout', ...baseJson};
  }

  static Map<String, Object?>? _filterNativeMapToZone(
    NativeComponentConfig baseNative,
    Map<Object?, Object?> rawMap,
    String zoneId,
    Set<String> existingZoneSlots,
    Set<String> allowedSlotIds, {
    required String componentType,
  }) {
    final baseJson = Map<String, Object?>.of(baseNative.toJson());
    var changed = false;

    if (rawMap['regions'] is Map &&
        (rawMap['regions'] as Map).containsKey(zoneId)) {
      final mergedRegions = _stringObjectMap(baseJson['regions']);
      mergedRegions[zoneId] = (rawMap['regions'] as Map)[zoneId];
      baseJson['regions'] = mergedRegions;
      changed = true;
    }

    if (rawMap['placements'] is Map &&
        (rawMap['placements'] as Map).containsKey(zoneId)) {
      final mergedPlacements = _stringObjectMap(baseJson['placements']);
      mergedPlacements[zoneId] = (rawMap['placements'] as Map)[zoneId];
      baseJson['placements'] = mergedPlacements;
      if ((rawMap['regions'] is! Map ||
              !(rawMap['regions'] as Map).containsKey(zoneId)) &&
          (rawMap['placements'] as Map)[zoneId] is List &&
          ((rawMap['placements'] as Map)[zoneId] as List).isNotEmpty) {
        final mergedRegions = _stringObjectMap(baseJson['regions']);
        mergedRegions[zoneId] = true;
        baseJson['regions'] = mergedRegions;
      }
      changed = true;
    }

    for (final mapKey in const ['regionAxes', 'regionFlows', 'regionSizes']) {
      if (rawMap[mapKey] is Map &&
          (rawMap[mapKey] as Map).containsKey(zoneId)) {
        final merged = _stringObjectMap(baseJson[mapKey]);
        merged[zoneId] = (rawMap[mapKey] as Map)[zoneId];
        baseJson[mapKey] = merged;
        changed = true;
      }
    }

    for (final mapKey in const [
      'slotSizeConstraints',
      'slotPreferredSizes',
      'slotLabels',
    ]) {
      if (rawMap[mapKey] is Map) {
        final incoming = rawMap[mapKey] as Map;
        final merged = <String, Object?>{
          for (final entry
              in (baseJson[mapKey] as Map? ?? const {}).entries)
            if (entry.key is String &&
                !existingZoneSlots.contains(entry.key as String))
              entry.key as String: entry.value,
        };
        var slotMapChanged = false;
        for (final entry in incoming.entries) {
          if (entry.key is String &&
              allowedSlotIds.contains(entry.key as String)) {
            merged[entry.key as String] = entry.value;
            slotMapChanged = true;
          }
        }
        if (slotMapChanged) {
          baseJson[mapKey] = merged;
          changed = true;
        }
      }
    }

    if (!changed) return null;
    return {'type': componentType, ...baseJson};
  }

  static Map<String, Object?>? _filterTabMapToZone(
    SuperTabConfig baseTab,
    Map<Object?, Object?> rawMap,
    String zoneId,
    Set<String> existingZoneSlots,
    Set<String> allowedSlotIds,
  ) {
    final baseJson = Map<String, Object?>.of(baseTab.toJson());
    var changed = false;

    final mergedPlacements = _stringObjectMap(baseJson['placements']);
    if (rawMap['placements'] is Map &&
        (rawMap['placements'] as Map).containsKey(zoneId)) {
      mergedPlacements[zoneId] = (rawMap['placements'] as Map)[zoneId];
      baseJson['placements'] = mergedPlacements;
      changed = true;
    } else if (zoneId == 'tabs' && rawMap['tabs'] is List) {
      mergedPlacements['tabs'] = rawMap['tabs'];
      baseJson['placements'] = mergedPlacements;
      changed = true;
    } else if (zoneId == 'content' && rawMap['content'] is List) {
      mergedPlacements['content'] = rawMap['content'];
      baseJson['placements'] = mergedPlacements;
      changed = true;
    } else if (zoneId.startsWith('content:') && rawMap['contents'] is Map) {
      final contents = rawMap['contents'] as Map;
      final tabId = zoneId.substring('content:'.length);
      final targetList = contents[tabId] ?? contents[zoneId];
      if (targetList is List) {
        mergedPlacements[zoneId] = targetList;
        baseJson['placements'] = mergedPlacements;
        changed = true;
      }
    }

    for (final mapKey in const ['zoneAxes', 'zoneFlows']) {
      if (rawMap[mapKey] is Map &&
          (rawMap[mapKey] as Map).containsKey(zoneId)) {
        final merged = _stringObjectMap(baseJson[mapKey]);
        merged[zoneId] = (rawMap[mapKey] as Map)[zoneId];
        baseJson[mapKey] = merged;
        changed = true;
      }
    }

    for (final mapKey in const [
      'slotSizeConstraints',
      'slotPreferredSizes',
      'slotLabels',
    ]) {
      if (rawMap[mapKey] is Map) {
        final incoming = rawMap[mapKey] as Map;
        final merged = <String, Object?>{
          for (final entry
              in (baseJson[mapKey] as Map? ?? const {}).entries)
            if (entry.key is String &&
                !existingZoneSlots.contains(entry.key as String))
              entry.key as String: entry.value,
        };
        var slotMapChanged = false;
        for (final entry in incoming.entries) {
          if (entry.key is String &&
              allowedSlotIds.contains(entry.key as String)) {
            merged[entry.key as String] = entry.value;
            slotMapChanged = true;
          }
        }
        if (slotMapChanged) {
          baseJson[mapKey] = merged;
          changed = true;
        }
      }
    }

    if (!changed) return null;
    return {'type': 'tab', ...baseJson};
  }

  static Map<String, Object?>? _filterContainerPatchToZone(
    ComponentConfig? existing,
    Map<Object?, Object?> rawMap,
    String zoneId,
    Set<String> existingZoneSlots,
    Set<String> allowedSlotIds,
  ) {
    if (existing is SuperLayoutConfig) {
      return _filterLayoutMapToZone(
        existing,
        rawMap,
        zoneId,
        existingZoneSlots,
        allowedSlotIds,
      );
    }
    if (existing is SuperListViewConfig) {
      final rawTemplate = rawMap['template'] is Map
          ? rawMap['template'] as Map
          : rawMap['row'] is Map
          ? rawMap['row'] as Map
          : rawMap;
      final filteredTemplate = _filterLayoutMapToZone(
        existing.template,
        rawTemplate,
        zoneId,
        existingZoneSlots,
        allowedSlotIds,
      );
      if (filteredTemplate == null) return null;
      final copy = Map<String, Object?>.of(filteredTemplate)..remove('type');
      return {'type': 'list', 'template': copy};
    }
    if (existing is ScaffoldPageConfig) {
      return _filterNativeMapToZone(
        existing.native,
        rawMap,
        zoneId,
        existingZoneSlots,
        allowedSlotIds,
        componentType: 'page',
      );
    }
    if (existing is NativeComponentConfig) {
      return _filterNativeMapToZone(
        existing,
        rawMap,
        zoneId,
        existingZoneSlots,
        allowedSlotIds,
        componentType: 'native',
      );
    }
    if (existing is SuperTabConfig) {
      return _filterTabMapToZone(
        existing,
        rawMap,
        zoneId,
        existingZoneSlots,
        allowedSlotIds,
      );
    }
    final rawType = rawMap['type'] ?? rawMap['componentType'];
    if (rawType == 'native' || rawType == 'page') {
      return _filterNativeMapToZone(
        NativeComponentConfig(),
        rawMap,
        zoneId,
        existingZoneSlots,
        allowedSlotIds,
        componentType: rawType as String,
      );
    }
    if (rawType == 'tab') {
      return _filterTabMapToZone(
        SuperTabConfig(),
        rawMap,
        zoneId,
        existingZoneSlots,
        allowedSlotIds,
      );
    }
    return _filterLayoutMapToZone(
      const SuperLayoutConfig(),
      rawMap,
      zoneId,
      existingZoneSlots,
      allowedSlotIds,
    );
  }

  /// Filters an incoming GenUI [patch] so that only changes belonging to
  /// [scope] (either the target component and its subtree, or a specific zone
  /// of the target container and its subtree) are kept.
  ///
  /// Out-of-scope edits (other zones, parent/sibling components, global theme
  /// properties, `pageCatalog`) are stripped automatically.
  static Map<String, dynamic> filterPatchToScope(
    Appearance current,
    Map<String, dynamic> patch,
    VibeChatScope scope,
  ) {
    final payload = patch['data'] is Map<String, dynamic>
        ? patch['data'] as Map<String, dynamic>
        : patch;
    final targetId = scope.canonicalComponentId;
    final rawTargetId = scope.componentId;
    final zoneId =
        scope.zoneId != null && scope.zoneId!.isNotEmpty ? scope.zoneId : null;

    final existingSubtree = _existingSubtreeIds(current, scope);
    final outsideExistingIds = <String>{
      for (final id in current.components.keys)
        if (!existingSubtree.contains(id) && id != targetId) id,
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
        } else if (zoneId != null && cid == targetId) {
          final allInTarget = _placedIdsInPatchMap(cval).toSet();
          final inAllowedZone = _placedIdsInPatchMap(
            cval,
            onlyZoneId: zoneId,
          ).toSet();
          placedByOutsideIds.addAll(allInTarget.difference(inAllowedZone));
        }
      }

      final queue = <String>[];
      if (zoneId != null && rawComponents[targetId] is Map) {
        for (final childId in _placedIdsInPatchMap(
          rawComponents[targetId] as Map,
          onlyZoneId: zoneId,
        )) {
          if (!outsideExistingIds.contains(childId) &&
              childId != targetId &&
              allowedSubtreeIds.add(childId)) {
            queue.add(childId);
          }
        }
      }
      queue.addAll(allowedSubtreeIds);

      while (queue.isNotEmpty) {
        final id = queue.removeLast();
        for (final childId in _childrenOfComponent(current.components[id])) {
          if (!outsideExistingIds.contains(childId) &&
              allowedSubtreeIds.add(childId)) {
            queue.add(childId);
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
        if (zoneId != null && cid == targetId) {
          if (cval is Map) {
            final zonePatch = _filterContainerPatchToZone(
              current.components[targetId],
              cval,
              zoneId,
              existingSubtree,
              allowedSubtreeIds,
            );
            if (zonePatch != null) {
              filteredComponents[targetId] = zonePatch;
            }
          }
        } else if (allowedSubtreeIds.contains(cid)) {
          if (cid == targetId && cval == null) continue;
          filteredComponents[cid] = cval;
        } else if (!current.components.containsKey(cid) &&
            !outsideExistingIds.contains(cid) &&
            !placedByOutsideIds.contains(cid)) {
          // Detached newly created component: keep so validation can report it.
          filteredComponents[cid] = cval;
        }
      }
    }

    bool isStyleAllowed(String styleId) {
      if (allowedSubtreeIds.contains(styleId)) return true;
      if (styleId.endsWith(':item')) {
        final base = styleId.substring(0, styleId.length - 5);
        if (allowedSubtreeIds.contains(base)) return true;
      }
      if (zoneId == null &&
          (styleId == rawTargetId ||
              styleId == targetId ||
              styleId == '$targetId:item')) {
        return true;
      }
      return false;
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
            (allowedSubtreeIds.contains(bid) ||
                (zoneId == null && bid == rawTargetId))) {
          filteredBehaviors[bid] = entry.value;
        }
      }
    }

    return <String, dynamic>{
      if (filteredComponents.isNotEmpty) 'components': filteredComponents,
      if (filteredStyles.isNotEmpty) 'styles': filteredStyles,
      if (filteredBehaviors.isNotEmpty) 'behaviors': filteredBehaviors,
    };
  }

  /// Exports a focused JSON snapshot of [scope]'s subtree from [appearance]
  /// for inclusion in the AI prompt.
  static String exportScopedAi(
    Appearance appearance,
    VibeChatScope scope, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final targetId = scope.canonicalComponentId;
    final rawTargetId = scope.componentId;
    final subtreeIds = <String>{
      targetId,
      ..._existingSubtreeIds(appearance, scope),
    };
    final fullJson = codec.toJson(appearance);
    final allComponents =
        fullJson['components'] as Map<String, Object?>? ?? const {};
    final allStyles = fullJson['styles'] as Map<String, Object?>? ?? const {};

    final scopedComponents = <String, Object?>{
      for (final id in subtreeIds)
        if (allComponents.containsKey(id)) id: allComponents[id],
    };
    final scopedStyles = <String, Object?>{
      for (final entry in allStyles.entries)
        if (subtreeIds.contains(entry.key) ||
            entry.key == rawTargetId ||
            (entry.key.endsWith(':item') &&
                subtreeIds.contains(
                  entry.key.substring(0, entry.key.length - 5),
                )))
          entry.key: entry.value,
    };

    return const JsonEncoder.withIndent('  ').convert({
      'scope': {
        'componentId': targetId,
        if (rawTargetId != targetId) 'surfaceId': rawTargetId,
        'zoneId': ?scope.zoneId,
        'label': scope.displayLabel,
      },
      'components': scopedComponents,
      'styles': scopedStyles,
    });
  }

  @override
  State<VibeChatDialog> createState() => _VibeChatDialogState();
}

class _VibeChatDialogState extends State<VibeChatDialog> {
  static const _guideAssets = [
    'SCREEN_JSON_AI_GUIDE.md',
    'packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md',
  ];

  final _input = TextEditingController();
  final _pendingAttachments = <VibeChatAttachment>[];
  final _messages = <_ChatMessage>[
    const _ChatMessage(
      text: 'Décris l’écran à créer ou les changements souhaités.',
      isUser: false,
    ),
  ];
  bool _sending = false;
  String? _lastFailedResponse;
  String? _attachmentError;
  late VibeChatScope? _scope = widget.scope;

  Appearance get _currentAppearance =>
      widget.registry?.appearanceSnapshot(widget.controller.value) ??
      widget.controller.value;

  @override
  void didUpdateWidget(VibeChatDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _scope = widget.scope;
    }
  }

  void _clearScope() {
    setState(() => _scope = null);
    widget.onScopeChanged?.call(null);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _attachFromPicker() async {
    if (_sending) return;
    setState(() => _attachmentError = null);
    try {
      final picker = widget.pickAttachments ?? VibeChatAttachment.pickFiles;
      final picked = await picker();
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _pendingAttachments.addAll(picked);
        _attachmentError = null;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _attachmentError = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError = 'Lecture impossible : ${error.message}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError =
              'Impossible d’importer le fichier : ${_describeErrorCause(error)}',
        );
      }
    }
  }

  Future<void> _attachFromClipboard() async {
    if (_sending) return;
    setState(() => _attachmentError = null);
    try {
      final paster = widget.pasteAttachments ?? VibeChatAttachment.fromClipboard;
      final pasted = await paster();
      if (!mounted) return;
      if (pasted.isEmpty) {
        setState(
          () => _attachmentError =
              'Aucun fichier ou texte trouvé dans le presse-papiers.',
        );
        return;
      }
      setState(() {
        _pendingAttachments.addAll(pasted);
        _attachmentError = null;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _attachmentError = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError = 'Lecture impossible : ${error.message}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError =
              'Impossible de coller depuis le presse-papiers : '
              '${_describeErrorCause(error)}',
        );
      }
    }
  }

  void _removePendingAttachment(int index) {
    if (_sending || index < 0 || index >= _pendingAttachments.length) return;
    setState(() {
      _pendingAttachments.removeAt(index);
      _attachmentError = null;
    });
  }

  String _describeErrorCause(Object error) {
    if (error is FormatException) {
      final offset = error.offset;
      final source = error.source;
      if (offset != null && source is String && source.isNotEmpty) {
        final start = (offset - 40).clamp(0, source.length);
        final end = (offset + 40).clamp(0, source.length);
        final snippet = source.substring(start, end).replaceAll('\n', ' ');
        return '${error.message} (offset $offset, près de "$snippet")';
      }
      return error.message;
    }
    if (error is ArgumentError) {
      final name = error.name;
      final message = error.message?.toString() ?? error.toString();
      return name != null && name.isNotEmpty ? '$name : $message' : message;
    }
    if (error is StateError) {
      return error.message;
    }
    if (error is FlutterError) {
      return error.message;
    }
    return '$error';
  }

  Future<void> _send() async {
    final request = _input.text.trim();
    final attachments = List<VibeChatAttachment>.unmodifiable(
      _pendingAttachments,
    );
    if ((request.isEmpty && attachments.isEmpty) || _sending) return;
    _input.clear();
    _lastFailedResponse = null;
    setState(() {
      _sending = true;
      _pendingAttachments.clear();
      _attachmentError = null;
      _messages.add(
        _ChatMessage(
          text: request,
          isUser: true,
          attachments: attachments,
        ),
      );
    });

    debugPrint(
      '[Vibe IA] Nouvelle demande utilisateur : "$request" '
      '(pièces jointes: ${attachments.map((a) => a.name).toList()})',
    );
    try {
      final guide = await _loadGuide(context);
      final prompt = _buildPrompt(guide);
      final allAttachments = <VibeChatAttachment>[
        for (final message in _messages)
          if (message.isUser) ...message.attachments,
      ];
      final generated = await _generateAndApply(
        prompt,
        attachments: allAttachments,
      );
      if (generated.appearance case final appearance?) {
        widget.controller.value = appearance;
        debugPrint(
          '[Vibe IA] Apparence mise à jour avec succès '
          '(composants: ${appearance.components.length}, '
          'styles: ${appearance.styles.length}, '
          'pages: ${appearance.pageCatalog.pages.length}).',
        );
      } else {
        debugPrint(
          '[Vibe IA] Réponse textuelle affichée sans modification d’apparence.',
        );
      }
      final summary = generated.result['message'];
      _appendMessage(
        summary is String && summary.trim().isNotEmpty
            ? summary.trim()
            : 'Modifications appliquées.',
      );
    } on FormatException catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (FormatException): $cause\n'
        'Source: ${error.source ?? "n/a"} (offset: ${error.offset ?? "n/a"})\n'
        '$stackTrace',
      );
      _appendMessage(
        'Réponse Vibe invalide : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on ArgumentError catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (ArgumentError): $cause\n$stackTrace',
      );
      _appendMessage(
        'Modification refusée : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on StateError catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (StateError): $cause\n$stackTrace',
      );
      _appendMessage(
        'Modification impossible : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on FlutterError catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint('AI screen guide could not be loaded: $cause\n$stackTrace');
      _appendMessage(
        'Guide de génération indisponible : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on Exception catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (${error.runtimeType}): $cause\n'
        '$stackTrace',
      );
      _appendMessage(
        'Génération impossible (${error.runtimeType}) : $cause',
        failedResponse: _lastFailedResponse,
      );
    } catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed with unexpected error '
        '(${error.runtimeType}): $cause\n$stackTrace',
      );
      _appendMessage(
        'Génération impossible (${error.runtimeType}) : $cause',
        failedResponse: _lastFailedResponse,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _logLong(String title, String content) {
    debugPrint('$title (${content.length} caractères) :');
    const chunkSize = 800;
    if (content.length <= chunkSize) {
      debugPrint(content);
      return;
    }
    for (var start = 0; start < content.length; start += chunkSize) {
      final end = (start + chunkSize < content.length)
          ? start + chunkSize
          : content.length;
      debugPrint(content.substring(start, end));
    }
  }

  Future<String> _invokeGenerate(
    String prompt,
    List<VibeChatAttachment> attachments,
  ) {
    final generator = widget.generate;
    if (generator is Future<String> Function(
      String, {
      List<VibeChatAttachment> attachments,
    })) {
      return generator(prompt, attachments: attachments);
    }
    return generator(prompt);
  }

  Future<({Appearance? appearance, Map<String, dynamic> result})>
  _generateAndApply(
    String prompt, {
    List<VibeChatAttachment> attachments = const [],
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      debugPrint(
        '[Vibe IA] Tentative ${attempt + 1}/2 — envoi du prompt '
        '(${prompt.length} caractères, '
        'fichiers joints: ${attachments.length})...',
      );
      final String response;
      try {
        response = await _invokeGenerate(prompt, attachments);
      } catch (error, stackTrace) {
        debugPrint(
          '[Vibe IA] Échec de widget.generate à la tentative ${attempt + 1} '
          '(${error.runtimeType}) : $error\n$stackTrace',
        );
        rethrow;
      }
      _lastFailedResponse = response;
      _logLong(
        '[Vibe IA] Réponse brute (tentative ${attempt + 1})',
        response,
      );
      try {
        final json = _extractJson(response);
        final Object? result;
        try {
          result = jsonDecode(json);
        } on FormatException catch (error) {
          debugPrint(
            '[Vibe IA] Échec de jsonDecode (tentative ${attempt + 1}) : '
            '${error.message} (offset: ${error.offset})',
          );
          rethrow;
        }
        if (result is! Map<String, dynamic>) {
          debugPrint(
            '[Vibe IA] Le JSON décodé n’est pas un Map<String, dynamic> '
            '(type reçu: ${result.runtimeType}).',
          );
          throw const FormatException('La réponse doit être un objet JSON.');
        }
        final patch = _extractPatch(result);
        if (patch == null) {
          final message = result['message'];
          if (message is! String || message.trim().isEmpty) {
            debugPrint(
              '[Vibe IA] Réponse sans patch ni message valide. '
              'Clés reçues: ${result.keys.toList()}',
            );
            throw const FormatException(
              'La réponse ne contient ni message ni modification.',
            );
          }
          _lastFailedResponse = null;
          return (appearance: null, result: result);
        }
        final current = _currentAppearance;
        final activeScope = _scope;
        final effectivePatch = activeScope == null
            ? patch
            : VibeChatDialog.filterPatchToScope(current, patch, activeScope);
        if (activeScope != null && !_hasPatchChanges(effectivePatch)) {
          throw FormatException(
            'Modifications hors du scope autorisé (${activeScope.displayLabel}, '
            'id: "${activeScope.canonicalComponentId}"'
            '${activeScope.zoneId != null ? ', zone: "${activeScope.zoneId}"' : ''}). '
            'Modifie uniquement ce scope.',
          );
        }
        final formattedPatch = const JsonEncoder.withIndent('  ').convert(
          effectivePatch,
        );
        _logLong('[Vibe IA] Patch à appliquer', formattedPatch);
        final Appearance appearance;
        try {
          appearance = AppearanceTransfer.applyVibe(
            current,
            jsonEncode(effectivePatch),
            codec: widget.codec,
          );
        } catch (error, stackTrace) {
          debugPrint(
            '[Vibe IA] Échec lors de AppearanceTransfer.applyVibe '
            '(tentative ${attempt + 1}, ${error.runtimeType}) : $error\n'
            '$stackTrace',
          );
          rethrow;
        }
        try {
          widget.validateAppearance?.call(appearance);
        } catch (error, stackTrace) {
          debugPrint(
            '[Vibe IA] Échec lors de validateAppearance '
            '(tentative ${attempt + 1}, ${error.runtimeType}) : $error\n'
            '$stackTrace',
          );
          rethrow;
        }
        _validatePatchedComponents(current, appearance, effectivePatch);
        _lastFailedResponse = null;
        return (appearance: appearance, result: result);
      } catch (error) {
        final isValidationError =
            error is FormatException ||
            error is ArgumentError ||
            error is StateError;
        if (attempt != 0 || !isValidationError) {
          debugPrint(
            '[Vibe IA] Tentative ${attempt + 1} échouée sans relance '
            '(${error.runtimeType}) : ${_describeErrorCause(error)}',
          );
          rethrow;
        }
        final cause = _describeErrorCause(error);
        debugPrint(
          '[Vibe IA] Tentative ${attempt + 1} rejetée ($cause). '
          'Relance avec prompt de correction...',
        );
        prompt =
            '''
$prompt

CORRECTION REQUISE :
La réponse précédente a été refusée.
Cause de l'erreur (${error.runtimeType}) :
$cause
Corrige la réponse en respectant strictement le schéma JSON du guide et en rattachant tous les nouveaux composants à un conteneur existant de l'état actuel ou à une page déclarée dans pageCatalog.
Réutilise les identifiants existants ; les identifiants du guide sont uniquement des exemples.
Si tu crées une page, son chemin doit commencer par un seul "/", être différent de "/" et ne contenir ni espace, ni "?", ni "#"; ne termine pas le chemin par "/".
Tu peux aussi éviter de créer une page si la demande ne le nécessite pas.
Réponse précédente invalide :
$response
''';
      }
    }
    throw StateError('La génération Vibe n’a pas produit de réponse valide.');
  }

  Map<String, dynamic>? _extractPatch(Map<String, dynamic> result) {
    if (result.containsKey('vibe') && result['vibe'] is! bool) {
      final vibe = result['vibe'];
      if (vibe == null) return null;
      if (vibe is! Map<String, dynamic>) {
        throw const FormatException(
          'Le champ "vibe" doit être un objet JSON ou null.',
        );
      }
      return _hasPatchChanges(vibe) ? vibe : null;
    }
    final candidate = Map<String, dynamic>.of(result)..remove('message');
    return _hasPatchChanges(candidate) ? candidate : null;
  }

  bool _hasPatchChanges(Map<String, dynamic> patch) {
    final payload = patch['data'] is Map<String, dynamic>
        ? patch['data'] as Map<String, dynamic>
        : patch;
    const metaKeys = {'version', 'vibe', 'merge', 'format', 'groups'};
    for (final entry in payload.entries) {
      if (metaKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value == null) continue;
      if (value is Map && value.isEmpty) continue;
      return true;
    }
    return false;
  }

  void _validatePatchedComponents(
    Appearance current,
    Appearance next,
    Map<String, dynamic> patch,
  ) {
    final activeScope = _scope;
    final reachable = <String>{};
    if (activeScope != null) {
      final targetId = activeScope.canonicalComponentId;
      final zoneId = activeScope.zoneId;
      reachable.add(targetId);
      final pending = <String>[
        if (zoneId != null && zoneId.isNotEmpty)
          ...VibeChatDialog._childrenOfComponent(
            next.components[targetId],
            onlyZoneId: zoneId,
          )
        else
          ...VibeChatDialog._childrenOfComponent(next.components[targetId]),
      ];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!reachable.add(id)) continue;
        pending.addAll(
          VibeChatDialog._childrenOfComponent(next.components[id]),
        );
      }
    } else {
      final pending = [
        ...?widget.registry?.instantiatedComponentIds,
        if (widget.registry == null) ...current.components.keys,
        for (final page in next.pageCatalog.pages) page.id,
      ];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!reachable.add(id)) continue;
        final component = next.components[id];
        final children = switch (component) {
          final SuperLayoutConfig layout => layout.placedSlotIds,
          final SuperListViewConfig list => list.template.placedSlotIds,
          final SuperTabConfig tab => tab.placedSlotIds,
          final NativeComponentConfig native =>
            native.placements.values.expand((ids) => ids),
          final ScaffoldPageConfig scaffold =>
            scaffold.native.placements.values.expand((ids) => ids),
          _ => const <String>[],
        };
        pending.addAll(children);
      }
    }
    final payload = patch['data'] is Map ? patch['data'] as Map : patch;
    final patchedComponents = payload['components'];
    final affected = patchedComponents is Map
        ? patchedComponents.keys.whereType<String>()
        : next.components.keys.where(
            (id) => !current.components.containsKey(id),
          );
    final detached = affected
        .where(
          (id) => next.components.containsKey(id) && !reachable.contains(id),
        )
        .toList();
    if (detached.isNotEmpty) {
      debugPrint(
        '[Vibe IA] Composants détachés détectés : $detached '
        '(composants accessibles depuis l’écran : ${reachable.toList()}).',
      );
      throw FormatException(
        'Composants non rattachés à l’écran : ${detached.join(', ')}. '
        'Modifie les placements d’un conteneur existant ou déclare une page.',
      );
    }
  }

  Future<String> _loadGuide(BuildContext context) async {
    final bundle = DefaultAssetBundle.of(context);
    FlutterError? lastError;
    for (final asset in _guideAssets) {
      try {
        final guide = await bundle.loadString(asset);
        if (guide.trim().isNotEmpty) return guide;
        lastError = FlutterError('Asset "$asset" is empty.');
      } on FlutterError catch (error) {
        lastError = error;
      }
    }
    throw FlutterError(
      'Unable to load the Vibe screen guide from '
      '${_guideAssets.map((asset) => '"$asset"').join(' or ')}.'
      '${lastError == null ? '' : ' $lastError'}',
    );
  }

  String _buildPrompt(String guide) {
    final conversation = _messages
        .map((message) => message.toConversationEntry())
        .join('\n');
    final appearance = _currentAppearance;
    final current = AppearanceTransfer.exportAi(
      appearance,
      codec: widget.codec,
    );
    final instantiated = widget.registry?.instantiatedComponentIds;
    final activeScope = _scope;
    final scopeInstructions = activeScope == null
        ? ''
        : '''

RESTRICTION STRICTE DE SCOPE :
L'utilisateur a ouvert l'assistant IA sur un scope restreint : "${activeScope.displayLabel}" (composant id: "${activeScope.canonicalComponentId}"${activeScope.zoneId != null ? ', zone/région: "${activeScope.zoneId}"' : ''}).
- Tu dois UNIQUEMENT modifier ce scope ("${activeScope.canonicalComponentId}"${activeScope.zoneId != null ? ' dans sa zone "${activeScope.zoneId}"' : ''}) et ses sous-composants.
- Ne modifie AUCUN composant parent, frère ou externe à ce scope.
- Ne modifie PAS les paramètres globaux de thème (mode, accent, background) ni pageCatalog.
${activeScope.zoneId != null ? '- Dans le conteneur "${activeScope.canonicalComponentId}", modifie exclusivement la zone/région "${activeScope.zoneId}" (ses placements, son activation, son flux/axe/taille) et les composants placés dans "${activeScope.zoneId}". Ne touche à aucune autre zone de "${activeScope.canonicalComponentId}".' : '- Tout nouveau composant créé doit être rattaché dans les placements de "${activeScope.canonicalComponentId}" ou de l’un de ses sous-composants.'}

ÉTAT DU SCOPE CIBLÉ (JSON) :
${VibeChatDialog.exportScopedAi(appearance, activeScope, codec: widget.codec)}
''';
    return '''
Tu es l’assistant de création d’écrans de super_container_layout. Réponds en français.
Utilise exclusivement le guide ci-dessous et l’état actuel de l’application.
Renvoie uniquement un objet JSON :
- Si l'utilisateur demande de créer ou modifier l'écran, renvoie {"message":"résumé bref en français","vibe":{...}}. Le champ "vibe" doit contenir un patch JSON plat (modèle GenUI : "components", "styles", "pageCatalog") accepté par AppearanceTransfer.applyVibe.
- Si l'utilisateur pose une question ou demande une information sans demander de modification de l'écran, renvoie {"message":"réponse claire en français","vibe":null} (ou omets le champ "vibe") sans modifier l'écran.
Réutilise les identifiants des conteneurs de l'état actuel, y compris ceux dont la configuration est encore celle par défaut. Les identifiants du guide (comme "contA") sont des exemples, pas des racines d'écran implicites.
Tout nouveau composant doit être rattaché par les placements à un conteneur existant ou à une page déclarée dans pageCatalog. Créer un layout isolé ne l'affiche pas.
${instantiated == null ? '' : 'Les composants instanciés sont : ${jsonEncode(instantiated.toList())}. Rattache les modifications à ces composants ou aux pages déclarées ; une configuration sauvegardée mais isolée ne suffit pas.'}
Si une opération crée une page, son chemin doit commencer par un seul "/", être différent de "/" et ne contenir ni espace, ni "?", ni "#"; ne termine pas le chemin par "/".
Si la conversation mentionne une erreur sur une réponse précédente, identifie la cause indiquée et corrige-la sans reproduire la même erreur.
Ne renvoie aucun Markdown ni texte hors du JSON. Si une information manque, fais une hypothèse raisonnable et indique-la dans "message".$scopeInstructions

GUIDE DE MODÉLISATION :
$guide

ÉTAT ACTUEL (JSON) :
$current

CONVERSATION :
$conversation
''';
  }

  String _extractJson(String response) {
    var value = response.trim();
    if (value.startsWith('```')) {
      final newline = value.indexOf('\n');
      if (newline < 0) {
        throw const FormatException('Aucun objet JSON détecté.');
      }
      value = value.substring(newline + 1).trim();
      if (value.endsWith('```')) {
        value = value.substring(0, value.length - 3).trim();
      }
    }
    return value;
  }

  void _appendMessage(String text, {String? failedResponse}) {
    if (!mounted) return;
    setState(
      () => _messages.add(
        _ChatMessage(
          text: text,
          isUser: false,
          failedResponse: failedResponse,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('vibe-chat-dialog'),
      color: scheme.surface,
      elevation: 18,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          GestureDetector(
            key: const ValueKey('vibe-chat-drag'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => widget.onDrag(details.delta),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              color: scheme.primary,
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Vibe — création d’écran',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.drag_indicator, color: scheme.onPrimary, size: 18),
                  IconButton(
                    key: const ValueKey('vibe-chat-close'),
                    tooltip: 'Fermer le chat',
                    onPressed: widget.onClose,
                    icon: Icon(Icons.close, color: scheme.onPrimary, size: 20),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'Votre demande et la configuration de l’écran sont envoyées à Gemini.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_scope case final activeScope?)
            Container(
              key: const ValueKey('vibe-chat-scope-banner'),
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_center_focus_outlined,
                    size: 16,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scope : ${activeScope.displayLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('vibe-chat-clear-scope'),
                    tooltip: 'Retirer la restriction de scope',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    color: scheme.onSecondaryContainer,
                    onPressed: _sending ? null : _clearScope,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              reverse: true,
              padding: const EdgeInsets.all(12),
              children: [
                if (_sending)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                for (final message in _messages.reversed)
                  _MessageBubble(message: message),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_attachmentError != null)
            Container(
              key: const ValueKey('vibe-chat-attachment-error'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: scheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _attachmentError!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    color: scheme.onErrorContainer,
                    onPressed: () => setState(() => _attachmentError = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          if (_pendingAttachments.isNotEmpty)
            Container(
              key: const ValueKey('vibe-chat-pending-attachments'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (index, attachment)
                        in _pendingAttachments.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _PendingAttachmentChip(
                          index: index,
                          attachment: attachment,
                          onRemove: _sending
                              ? null
                              : () => _removePendingAttachment(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const ValueKey('vibe-chat-attach'),
                  tooltip: 'Joindre un fichier (image ou texte)',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _attachFromPicker,
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  key: const ValueKey('vibe-chat-paste-attachment'),
                  tooltip: 'Coller un fichier ou texte du presse-papiers',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _attachFromClipboard,
                  icon: const Icon(Icons.content_paste),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    key: const ValueKey('vibe-chat-input'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Décris l’écran souhaité…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey('vibe-chat-send'),
                  tooltip: 'Générer et appliquer',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.failedResponse,
    this.attachments = const [],
  });

  final String text;
  final bool isUser;
  final String? failedResponse;
  final List<VibeChatAttachment> attachments;

  String toConversationEntry() {
    if (isUser) {
      final effectiveText = text.isEmpty && attachments.isNotEmpty
          ? 'Analyse les fichiers joints et applique les modifications correspondantes.'
          : text;
      if (attachments.isEmpty) {
        return 'Utilisateur : $effectiveText';
      }
      final buffer = StringBuffer('Utilisateur : $effectiveText');
      for (final attachment in attachments) {
        if (attachment.isImage) {
          buffer.write(
            '\n[Fichier image joint : "${attachment.name}" (${attachment.mimeType})]',
          );
        } else if (attachment.isText) {
          buffer.write(
            '\n[Fichier texte joint : "${attachment.name}" (${attachment.mimeType})]\n'
            '${attachment.textContent}',
          );
        }
      }
      return buffer.toString();
    }
    final rejected = failedResponse?.trim();
    if (rejected == null || rejected.isEmpty) {
      return 'Assistant : $text';
    }
    return 'Assistant (ERREUR À CORRIGER) : $text\n'
        'Réponse précédente invalide :\n$rejected';
  }
}

class _PendingAttachmentChip extends StatelessWidget {
  const _PendingAttachmentChip({
    required this.index,
    required this.attachment,
    required this.onRemove,
  });

  final int index;
  final VibeChatAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey('vibe-chat-pending-attachment-$index'),
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment.isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  attachment.bytes,
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.image_outlined,
                    size: 20,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              )
            else
              Icon(
                Icons.description_outlined,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              key: ValueKey('vibe-chat-remove-attachment-$index'),
              tooltip: 'Retirer ${attachment.name}',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              onPressed: onRemove,
              icon: Icon(
                Icons.close,
                size: 15,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = message.isUser
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: message.isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.attachments.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final attachment in message.attachments)
                    if (attachment.isImage)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 220,
                                maxHeight: 120,
                              ),
                              child: Image.memory(
                                attachment.bytes,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  padding: const EdgeInsets.all(8),
                                  color: scheme.surface.withValues(alpha: 0.4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.image_outlined,
                                        size: 16,
                                        color: foreground,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          attachment.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: foreground,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            attachment.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: foreground.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 15,
                              color: foreground,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                attachment.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: foreground,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
              if (message.text.isNotEmpty) const SizedBox(height: 6),
            ],
            if (message.text.isNotEmpty) SelectableText(message.text),
          ],
        ),
      ),
    );
  }
}
