/// Générateur de code Dart dédié au composant [SuperTable] (`SuperTableConfig`).
library;

import 'package:flutter/foundation.dart' show listEquals;

import '../../../models/super_table_config.dart';
import '../../../theme/container_style.dart';
import '../dart_code_generator.dart';

/// Classe de génération de code Dart dédiée à [SuperTable] (`SuperTableConfig`).
class SuperTableDartGenerator extends ComponentDartGenerator {
  const SuperTableDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperTableConfig>(id) ??
        SuperTableConfig();
    final behaviors = context.appearance.behaviorsFor(id);
    final rowId = config.itemId ?? id;
    final templateStyle =
        context.appearance.styles[rowId] ??
        context.appearance.styles[id] ??
        const ContainerStyle();

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
      'id': context.formatInstanceId(id),
      if (config.itemId != null) 'itemId': context.formatString(config.itemId!),
      if (label != null && label != 'Table')
        'label': context.formatString(label),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (templateStyle != const ContainerStyle())
        'templateStyle': context.formatContainerStyle(
          templateStyle,
          indent: indent + 2,
          includeConst: context.canContainerStyleBeConst(templateStyle),
        ),
      if (config != SuperTableConfig())
        'config': formatConfig(context, config, indent: indent + 2),
      if (slotEntries.isNotEmpty)
        'slots': context.formatList(
          slotEntries,
          indent: indent + 2,
          forceMultiline: true,
        ),
    };

    return context.formatCall(
      'SuperTable',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperTableConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperTableConfig config, {
    int indent = 0,
  }) {
    final d = SuperTableConfig();
    final args = <String, String>{
      if (config.binding != null)
        'binding': context.formatBinding(
          config.binding!,
          indent: indent + 2,
          includeConst: true,
        ),
      if (!listEquals(config.columns, SuperTableConfig.defaultColumns))
        'columns': context.formatList(
          [
            for (final col in config.columns)
              _formatColumnConfig(context, col, indent: indent + 4),
          ],
          indent: indent + 2,
          isConst: true,
          forceMultiline: true,
        ),
      if (config.colFreezeLeftCount != d.colFreezeLeftCount)
        'colFreezeLeftCount': '${config.colFreezeLeftCount}',
      if (config.showHeaderRow != d.showHeaderRow)
        'showHeaderRow': '${config.showHeaderRow}',
      if (config.showBottomRow != d.showBottomRow)
        'showBottomRow': '${config.showBottomRow}',
      if (config.headerRowHeight != d.headerRowHeight)
        'headerRowHeight': context.formatNum(config.headerRowHeight),
      if (config.rowHeight != d.rowHeight)
        'rowHeight': context.formatNum(config.rowHeight),
      if (config.bottomRowHeight != d.bottomRowHeight)
        'bottomRowHeight': context.formatNum(config.bottomRowHeight),
      if (config.allowAdd != d.allowAdd) 'allowAdd': '${config.allowAdd}',
      if (config.allowRemove != d.allowRemove)
        'allowRemove': '${config.allowRemove}',
      if (config.animateSelectionAndHover != d.animateSelectionAndHover)
        'animateSelectionAndHover': '${config.animateSelectionAndHover}',
      if (config.emptyText != d.emptyText)
        'emptyText': context.formatString(config.emptyText),
      if (config.itemId != null) 'itemId': context.formatString(config.itemId!),
      if (config.zoneAxes.isNotEmpty)
        'zoneAxes': context.formatMap(
          {
            for (final entry in config.zoneAxes.entries)
              context.formatString(entry.key): context.formatAxis(entry.value),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (config.zoneFlows.isNotEmpty)
        'zoneFlows': context.formatMap(
          {
            for (final entry in config.zoneFlows.entries)
              context.formatString(entry.key): context.formatZoneFlowConfig(
                entry.value,
                indent: indent + 4,
              ),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (config.zoneStyles.isNotEmpty)
        'zoneStyles': context.formatMap({
          for (final entry in config.zoneStyles.entries)
            context.formatString(entry.key): context.formatContainerStyle(
              entry.value,
              indent: indent + 4,
              includeConst: context.canContainerStyleBeConst(entry.value),
            ),
        }, indent: indent + 2),
      if (config.slotSizeConstraints.isNotEmpty)
        'slotSizeConstraints': context.formatMap(
          {
            for (final entry in config.slotSizeConstraints.entries)
              context.formatString(entry.key): context
                  .formatSlotSizeConstraints(entry.value, indent: indent + 4),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (config.placements.isNotEmpty)
        'placements': context.formatMap(
          {
            for (final entry in config.placements.entries)
              context.formatString(entry.key): context.formatList([
                for (final id in entry.value) context.formatString(id),
              ], indent: indent + 4),
          },
          indent: indent + 2,
          isConst: true,
        ),
    };
    return context.formatCall(
      'SuperTableConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  static String _formatColumnConfig(
    DartCodegenContext context,
    SuperTableColumnConfig col, {
    int indent = 0,
  }) {
    return context.formatCall('SuperTableColumnConfig', const [], {
      'id': context.formatString(col.id),
      if (col.title.isNotEmpty) 'title': context.formatString(col.title),
      if (col.width != SuperTableColumnConfig.defaultWidth)
        'width': context.formatNum(col.width),
      if (col.fillPercent != SuperTableColumnConfig.defaultFillPercent)
        'fillPercent': context.formatNum(col.fillPercent),
    }, indent: indent);
  }
}
