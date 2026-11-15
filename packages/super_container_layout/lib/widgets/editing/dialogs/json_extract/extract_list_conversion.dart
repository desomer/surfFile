/// Conversion des blocs récurrents en listes liées sans mutation du dialogue.
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/json_text_binding.dart';
import '../../../../models/registry.dart';
import '../../../../models/super_layout_config.dart';
import '../../../../models/super_list_view_config.dart';
import '../../../../super_app.dart';
import '../../../../theme/container_style.dart';
import '../../slots/slot_wrapping.dart';
import 'extract_contracts.dart';

/// Opérations d'insertion et de remplacement des blocs par une liste.
abstract final class ExtractListConverter {
  static bool convert({
    required BuildContext ownerContext,
    required DetectedRecurringBlockGroup group,
    required RecurringGroupUserConfig userConfig,
    required String repoId,
    required String arrayPath,
    required Map<(String, String), Map<String, String>> groupFieldRelativePaths,
  }) {
    final layoutState = group.layoutState;
    if (!layoutState.mounted) return false;
    final registry = SuperApp.maybeOf(ownerContext)?.registry;
    if (registry == null) return false;

    final currentParentConfig = layoutState.config;
    final zonePlacements = List<String>.of(
      currentParentConfig.placementsOf(group.contentZone),
    );
    final firstNode = group.occurrences.first;
    if (!zonePlacements.contains(firstNode.slotId)) return false;

    // 1. Apply wildcard `[?]` bindings to the first occurrence (the template)
    Map<String, JsonTextBinding>? outerSurfaceBindings;
    for (final field in group.fields) {
      final relPaths = groupFieldRelativePaths[(group.id, field.fieldKey)];
      if (relPaths == null || relPaths.isEmpty) continue;
      final tplTarget = field.templateTarget;
      if (tplTarget == null) continue;
      final bindings = <String, JsonTextBinding>{
        for (final entry in relPaths.entries)
          entry.key: JsonTextBinding(
            // Inherit repository from the enclosing SuperListView
            repositoryId: null,
            path: '$arrayPath[?].${entry.value}',
          ),
      };
      if (userConfig.templateMode == ListViewTemplateMode.unwrapContainer &&
          tplTarget.kind == ExtractableComponentKind.surface &&
          tplTarget.id == firstNode.slotId) {
        outerSurfaceBindings = bindings;
      } else {
        tplTarget.applyBindings(bindings);
      }
    }

    // 2. Allocate unique ID for the new SuperListView
    final occupiedIds = <String>{
      ...currentParentConfig.placedSlotIds,
      ...registry.instantiatedComponentIds,
    };
    final listId = uniqueInstanceId(
      ownerContext,
      registry: registry,
      occupiedIds: occupiedIds,
    );

    // 3. Build row template layout & style
    SuperLayoutConfig templateLayout;
    ContainerStyle templateStyle = const ContainerStyle();
    String? unwrappedOuterId;

    if (userConfig.templateMode == ListViewTemplateMode.unwrapContainer &&
        group.canUnwrapContainer) {
      if (firstNode.normalizedSlotType == 'Card') {
        final cardNative = registry
            .nativeComponentController(firstNode.slotId)
            .value;
        final childSlots = cardNative.slotsOf('child');
        final singleChildId = childSlots.length == 1 ? childSlots.single : null;
        final singleChildType = singleChildId == null
            ? null
            : normalizeExtractableSlotType(
                cardNative.slotTypeOf(singleChildId),
              );
        var cardStyle = registry.styleController(firstNode.slotId).value;
        if (outerSurfaceBindings != null && outerSurfaceBindings.isNotEmpty) {
          cardStyle = cardStyle.copyWith(
            propertyBindings: {
              ...cardStyle.propertyBindings,
              for (final prop in ContainerStyleProperty.values)
                prop: ?outerSurfaceBindings[prop.name],
            },
          );
        }
        templateStyle = cardStyle;
        if (singleChildId != null && singleChildType == 'Layout') {
          templateLayout = registry.layoutController(singleChildId).value;
          unwrappedOuterId = firstNode.slotId;
        } else if (singleChildId != null) {
          templateLayout = SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: [singleChildId],
            },
            slotTypes: {singleChildId: cardNative.slotTypeOf(singleChildId)},
            slotLabels: {singleChildId: ?cardNative.slotLabels[singleChildId]},
          );
          unwrappedOuterId = firstNode.slotId;
        } else {
          templateLayout = const SuperLayoutConfig();
          unwrappedOuterId = firstNode.slotId;
        }
      } else if (firstNode.normalizedSlotType == 'Layout') {
        templateLayout = registry.layoutController(firstNode.slotId).value;
        unwrappedOuterId = firstNode.slotId;
      } else {
        templateLayout = SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: [firstNode.slotId],
          },
          slotTypes: {firstNode.slotId: firstNode.rawSlotType},
          slotLabels: {
            if (firstNode.customLabel != null)
              firstNode.slotId: firstNode.customLabel!,
          },
        );
      }
    } else {
      templateLayout = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: [firstNode.slotId],
        },
        slotTypes: {firstNode.slotId: firstNode.rawSlotType},
        slotLabels: {
          if (firstNode.customLabel != null)
            firstNode.slotId: firstNode.customLabel!,
        },
      );
    }

    final zoneFlow = currentParentConfig.flowOf(group.displayZone);
    final listConfig = SuperListViewConfig(
      binding: JsonTextBinding(
        repositoryId: group.isNestedInList ? null : repoId,
        path: arrayPath,
      ),
      axis: userConfig.axis,
      wrap: userConfig.wrap,
      itemExtent: group.inferredItemExtent,
      itemWidth: group.inferredItemWidth,
      spacing: group.inferredSpacing,
      allowAdd: userConfig.allowAdd,
      allowRemove: userConfig.allowRemove,
      showScrollbar: zoneFlow.showScrollbar,
      scrollbarStyle: zoneFlow.scrollbarStyle,
      template: templateLayout,
    );

    registry.styleController(listId).value = templateStyle;
    registry.layoutController(listId).value = templateLayout;
    registry.listController(listId).value = listConfig;

    // 4. Replace occurrences[0] with listId and remove occurrences[1..N-1]
    // in the parent SuperLayoutConfig
    final duplicateIds = {
      for (final occ in group.occurrences.skip(1)) occ.slotId,
    };
    final allReplacedIds = {firstNode.slotId, ...duplicateIds};

    final updatedZonePlacements = <String>[
      for (final id in zonePlacements)
        if (id == firstNode.slotId)
          listId
        else if (!duplicateIds.contains(id))
          id,
    ];

    final otherZoneReferenced = <String>{
      for (final entry in currentParentConfig.placements.entries)
        if (entry.key != group.contentZone) ...entry.value,
    };
    final removedFromParent = allReplacedIds.difference(otherZoneReferenced);

    // Ensure the new ListView gets flex: 1 (fitContent: false) when the zone
    // does not expand slots by default, so it receives a bounded main-axis viewport.
    final listConstraints =
        !zoneFlow.expandSlots ||
            zoneFlow.mainAxisAlignment != MainAxisAlignment.start
        ? const SlotSizeConstraints(fitContent: false)
        : null;

    final nextParentConfig = currentParentConfig.copyWith(
      placements: {
        ...currentParentConfig.placements,
        group.contentZone: updatedZonePlacements,
      },
      slotTypes: {
        for (final entry in currentParentConfig.slotTypes.entries)
          if (!removedFromParent.contains(entry.key)) entry.key: entry.value,
        listId: 'registry:ListView',
      },
      slotLabels: {
        for (final entry in currentParentConfig.slotLabels.entries)
          if (!removedFromParent.contains(entry.key)) entry.key: entry.value,
        listId: userConfig.arrayKey.trim().isEmpty
            ? group.defaultArrayKey
            : userConfig.arrayKey.trim(),
      },
      slotPreferredSizes: {
        for (final entry in currentParentConfig.slotPreferredSizes.entries)
          if (!removedFromParent.contains(entry.key)) entry.key: entry.value,
      },
      slotSizeConstraints: {
        for (final entry in currentParentConfig.slotSizeConstraints.entries)
          if (!removedFromParent.contains(entry.key)) entry.key: entry.value,
        listId: ?listConstraints,
      },
      grid: currentParentConfig.grid?.copyWith(
        items: {
          for (final entry in currentParentConfig.grid!.items.entries)
            if (entry.key == firstNode.slotId)
              listId: entry.value
            else if (!removedFromParent.contains(entry.key))
              entry.key: entry.value,
        },
      ),
    );

    layoutState.updateConfig(nextParentConfig, validateTags: false);
    if (layoutState.effectiveLayoutId case final parentLayoutId?
        when registry.superLayoutConfigById.containsKey(parentLayoutId)) {
      registry.layoutController(parentLayoutId).value = nextParentConfig;
    }

    // 5. Purge orphaned duplicate instances (and unwrapped shell if any)
    for (final dup in group.occurrences.skip(1)) {
      registry.purgeInstance(
        dup.slotId,
        dup.rawSlotType,
        EditorConfigKind.layout,
      );
    }
    if (unwrappedOuterId != null) {
      registry.purgeInstance(
        unwrappedOuterId,
        firstNode.rawSlotType,
        EditorConfigKind.layout,
      );
    }

    return true;
  }
}
