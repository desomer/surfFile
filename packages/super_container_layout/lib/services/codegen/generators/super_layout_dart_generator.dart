/// Générateur de code Dart dédié au composant [SuperLayout] (`SuperLayoutConfig`).
library;

import 'package:flutter/foundation.dart' show setEquals;

import '../../../models/super_layout_config.dart';
import '../dart_code_generator.dart';

/// Classe de génération de code Dart dédiée à [SuperLayout] (`SuperLayoutConfig`).
class SuperLayoutDartGenerator extends ComponentDartGenerator {
  const SuperLayoutDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    return generateLayoutWidget(
      context,
      id: id,
      label: label,
      omitId: false,
      indent: indent,
    );
  }

  /// Génère une expression `SuperLayout(...)` avec possibilité d'omettre `id`
  /// lorsqu'il s'agit d'un layout inline (ex: `header` ou `data` d'un `SuperTreeView`).
  String generateLayoutWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    bool omitId = false,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperLayoutConfig>(id) ??
        const SuperLayoutConfig();
    final behaviors = context.appearance.behaviorsFor(id);
    final effectiveLabel = config.label ?? label ?? 'Layout';

    final placedIds = <String>[
      for (final zoneIds in config.placements.values) ...zoneIds,
    ];
    final slotEntries = <String>[
      for (final slotId in placedIds)
        context.generateBuilderSlot(
          slotId,
          slotType: config.slotTypes[slotId],
          label: config.slotLabels[slotId],
          preferredSize: config.slotPreferredSizes[slotId],
          indent: indent + 4,
        ),
    ];

    final args = <String, String>{
      if (!omitId) 'id': context.formatString(id),
      'label': context.formatString(effectiveLabel),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (config != const SuperLayoutConfig())
        'config': formatConfig(
          context,
          config,
          indent: indent + 2,
          includeConst: true,
        ),
      if (slotEntries.isNotEmpty)
        'slots': context.formatList(
          slotEntries,
          indent: indent + 2,
          forceMultiline: true,
        ),
    };

    return context.formatCall(
      'SuperLayout',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperLayoutConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperLayoutConfig config, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = SuperLayoutConfig();
    // Filter out internal slotTypes/slotLabels when slots are generated directly as BuilderSlots,
    // keeping all layout, sizing, flow, and placement configuration.
    final args = <String, String>{
      if (config.positioning != d.positioning)
        'positioning': 'SuperLayoutPositioning.${config.positioning.name}',
      if (config.north != d.north) 'north': '${config.north}',
      if (config.south != d.south) 'south': '${config.south}',
      if (config.west != d.west) 'west': '${config.west}',
      if (config.east != d.east) 'east': '${config.east}',
      if (config.nw != d.nw) 'nw': 'CornerMerge.${config.nw.name}',
      if (config.ne != d.ne) 'ne': 'CornerMerge.${config.ne.name}',
      if (config.sw != d.sw) 'sw': 'CornerMerge.${config.sw.name}',
      if (config.se != d.se) 'se': 'CornerMerge.${config.se.name}',
      if (config.north && config.northSize != d.northSize)
        'northSize': context.formatNum(config.northSize),
      if (config.south && config.southSize != d.southSize)
        'southSize': context.formatNum(config.southSize),
      if (config.west && config.westSize != d.westSize)
        'westSize': context.formatNum(config.westSize),
      if (config.east && config.eastSize != d.eastSize)
        'eastSize': context.formatNum(config.eastSize),
      if (config.resizeSides != d.resizeSides)
        'resizeSides': '${config.resizeSides}',
      if (config.sideResizing.isNotEmpty)
        'sideResizing': context.formatMap(
          {
            for (final entry in config.sideResizing.entries)
              'SuperLayoutZone.${entry.key.name}': '${entry.value}',
          },
          indent: indent + 2,
          forceMultiline: config.sideResizing.length > 1,
        ),
      if (config.collapsedSides.isNotEmpty)
        'collapsedSides': context.formatMap(
          {
            for (final entry in config.collapsedSides.entries)
              'SuperLayoutZone.${entry.key.name}': context.formatNum(
                entry.value,
              ),
          },
          indent: indent + 2,
          forceMultiline: config.collapsedSides.length > 1,
        ),
      if (config.swaps.isNotEmpty)
        'swaps': context.formatSet(
          config.swaps.map((z) => 'SuperLayoutZone.${z.name}'),
          indent: indent + 2,
        ),
      if (!setEquals(config.autoSides, d.autoSides))
        'autoSides': context.formatSet(
          config.autoSides.map((z) => 'SuperLayoutZone.${z.name}'),
          indent: indent + 2,
        ),
      if (config.zoneAxes.isNotEmpty)
        'zoneAxes': context.formatMap(
          {
            for (final entry in config.zoneAxes.entries)
              'SuperLayoutZone.${entry.key.name}': context.formatAxis(
                entry.value,
              ),
          },
          indent: indent + 2,
          forceMultiline: config.zoneAxes.length > 1,
        ),
      if (config.zoneFlows.entries.any((e) => !e.value.isDefault))
        'zoneFlows': context.formatMap({
          for (final entry in config.zoneFlows.entries)
            if (!entry.value.isDefault)
              'SuperLayoutZone.${entry.key.name}': context.formatZoneFlowConfig(
                entry.value,
                indent: indent + 4,
              ),
        }, indent: indent + 2),
      if (config.slotSizeConstraints.isNotEmpty)
        'slotSizeConstraints': context.formatMap({
          for (final entry in config.slotSizeConstraints.entries)
            context.formatString(entry.key): context.formatSlotSizeConstraints(
              entry.value,
              indent: indent + 4,
            ),
        }, indent: indent + 2),
      if (config.placements.entries.any((e) => e.value.isNotEmpty))
        'placements': context.formatMap({
          for (final entry in config.placements.entries)
            if (entry.value.isNotEmpty)
              'SuperLayoutZone.${entry.key.name}': context.formatList([
                for (final s in entry.value) context.formatString(s),
              ], indent: indent + 4),
        }, indent: indent + 2),
      if (config.grid != null)
        'grid': context.formatGridLayoutConfig(
          config.grid!,
          indent: indent + 2,
        ),
    };
    final prefix = includeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperLayoutConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}
