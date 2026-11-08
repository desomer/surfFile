/// Générateur de code Dart dédié au composant [SuperTreeView] (`SuperTreeViewConfig`).
library;

import '../../../models/super_layout_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../theme/container_style.dart';
import '../dart_code_generator.dart';
import 'super_layout_dart_generator.dart';

/// Classe de génération de code Dart dédiée à [SuperTreeView] (`SuperTreeViewConfig`).
class SuperTreeViewDartGenerator extends ComponentDartGenerator {
  const SuperTreeViewDartGenerator();

  static const _layoutGen = SuperLayoutDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperTreeViewConfig>(id) ??
        SuperTreeViewConfig();
    final behaviors = context.appearance.behaviorsFor(id);
    final rowId = config.itemId ?? id;
    final templateStyle =
        context.appearance.styles[rowId] ??
        context.appearance.styles[id] ??
        const ContainerStyle();

    final headerSlots = config.slotsOf(SuperTreeViewConfig.headerZone);
    final dataSlots = config.slotsOf(SuperTreeViewConfig.dataZone);

    // Détecte le cas idiomatique de main.dart : `header: SuperLayout(...)` et `data: SuperLayout(...)`
    // lorsque la zone header a un unique slot 'header' (ou un SuperLayout) et data a 'data'.
    final inlineHeaderId =
        headerSlots.length == 1 &&
            headerSlots.single == 'header' &&
            context.appearance.components['header'] is SuperLayoutConfig
        ? 'header'
        : null;
    final inlineDataId =
        dataSlots.length == 1 &&
            dataSlots.single == 'data' &&
            context.appearance.components['data'] is SuperLayoutConfig
        ? 'data'
        : null;

    final remainingIds = <String>[
      for (final slotId in headerSlots)
        if (slotId != inlineHeaderId) slotId,
      for (final slotId in dataSlots)
        if (slotId != inlineDataId) slotId,
    ];

    final slotEntries = <String>[
      for (final slotId in remainingIds)
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
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (inlineHeaderId != null)
        'header': _layoutGen.generateLayoutWidget(
          context,
          id: inlineHeaderId,
          label: config.slotLabels[inlineHeaderId] ?? 'Node header',
          omitId: true,
          indent: indent + 2,
        ),
      if (inlineDataId != null)
        'data': _layoutGen.generateLayoutWidget(
          context,
          id: inlineDataId,
          label: config.slotLabels[inlineDataId] ?? 'Node data',
          omitId: true,
          indent: indent + 2,
        ),
      if (slotEntries.isNotEmpty)
        'slots': context.formatList(
          slotEntries,
          indent: indent + 2,
          forceMultiline: true,
        ),
      if (templateStyle != const ContainerStyle())
        'templateStyle': context.formatContainerStyle(
          templateStyle,
          indent: indent + 2,
          includeConst: context.canContainerStyleBeConst(templateStyle),
        ),
      if (config != SuperTreeViewConfig())
        'config': formatConfig(context, config, indent: indent + 2),
    };

    return context.formatCall(
      'SuperTreeView',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperTreeViewConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperTreeViewConfig config, {
    int indent = 0,
  }) {
    final d = SuperTreeViewConfig();
    final args = <String, String>{
      if (config.binding != null)
        'binding': context.formatBinding(
          config.binding!,
          indent: indent + 2,
          includeConst: true,
        ),
      if (config.childrenKey != d.childrenKey)
        'childrenKey': context.formatString(config.childrenKey),
      if (config.headerSize != d.headerSize)
        'headerSize': context.formatNum(config.headerSize),
      if (config.rowHeight != d.rowHeight)
        'rowHeight': context.formatNum(config.rowHeight),
      if (config.indent != d.indent) 'indent': context.formatNum(config.indent),
      if (config.initiallyExpanded != d.initiallyExpanded)
        'initiallyExpanded': '${config.initiallyExpanded}',
      if (config.showConnectors != d.showConnectors)
        'showConnectors': '${config.showConnectors}',
      if (config.showCheckboxes != d.showCheckboxes)
        'showCheckboxes': '${config.showCheckboxes}',
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
              _formatTreeZoneKey(context, entry.key): context.formatList([
                for (final id in entry.value) context.formatString(id),
              ], indent: indent + 4),
          },
          indent: indent + 2,
          isConst: true,
        ),
    };
    return context.formatCall(
      'SuperTreeViewConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  static String _formatTreeZoneKey(DartCodegenContext context, String zone) =>
      switch (zone) {
        SuperTreeViewConfig.headerZone => 'SuperTreeViewConfig.headerZone',
        SuperTreeViewConfig.dataZone => 'SuperTreeViewConfig.dataZone',
        _ => context.formatString(zone),
      };
}
