/// Générateur de code Dart dédié au composant [SuperTab] (`SuperTabConfig`).
library;

import '../../../models/super_tab_config.dart';
import '../dart_code_generator.dart';

/// Classe de génération de code Dart dédiée à [SuperTab] (`SuperTabConfig`).
class SuperTabDartGenerator extends ComponentDartGenerator {
  const SuperTabDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperTabConfig>(id) ?? SuperTabConfig();
    final behaviors = context.appearance.behaviorsFor(id);

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
      'id': context.formatString(id),
      if (label != null && label != 'Onglets')
        'label': context.formatString(label),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (config != SuperTabConfig())
        'config': formatConfig(context, config, indent: indent + 2),
      if (slotEntries.isNotEmpty)
        'slots': context.formatList(
          slotEntries,
          indent: indent + 2,
          forceMultiline: true,
        ),
    };

    return context.formatCall(
      'SuperTab',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperTabConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperTabConfig config, {
    int indent = 0,
  }) {
    final d = SuperTabConfig();
    final args = <String, String>{
      if (config.mode != d.mode) 'mode': 'SuperTabMode.${config.mode.name}',
      if (config.tabBarPosition != d.tabBarPosition)
        'tabBarPosition': 'SuperTabBarPosition.${config.tabBarPosition.name}',
      if (config.isScrollable != d.isScrollable)
        'isScrollable': '${config.isScrollable}',
      if (config.initialIndex != d.initialIndex)
        'initialIndex': '${config.initialIndex}',
      if (config.binding != null)
        'binding': context.formatBinding(
          config.binding!,
          indent: indent + 2,
          includeConst: true,
        ),
      if (config.allowAdd != d.allowAdd) 'allowAdd': '${config.allowAdd}',
      if (config.allowRemove != d.allowRemove)
        'allowRemove': '${config.allowRemove}',
      if (config.emptyText != d.emptyText)
        'emptyText': context.formatString(config.emptyText),
      if (config.tabBarStyle != d.tabBarStyle)
        'tabBarStyle': context.formatContainerStyle(
          config.tabBarStyle,
          indent: indent + 2,
          includeConst: context.canContainerStyleBeConst(config.tabBarStyle),
        ),
      if (config.indicatorKind != d.indicatorKind)
        'indicatorKind': 'SuperTabIndicatorKind.${config.indicatorKind.name}',
      if (config.indicatorSize != d.indicatorSize)
        'indicatorSize': 'TabBarIndicatorSize.${config.indicatorSize.name}',
      if (config.indicatorColor != null)
        'indicatorColor': context.formatColor(
          config.indicatorColor!,
          includeConst: true,
        ),
      if (config.indicatorWeight != d.indicatorWeight)
        'indicatorWeight': context.formatNum(config.indicatorWeight),
      if (config.indicatorRadius != d.indicatorRadius)
        'indicatorRadius': context.formatNum(config.indicatorRadius),
      if (config.indicatorHorizontalPadding != d.indicatorHorizontalPadding)
        'indicatorHorizontalPadding': context.formatNum(
          config.indicatorHorizontalPadding,
        ),
      if (config.indicatorVerticalPadding != d.indicatorVerticalPadding)
        'indicatorVerticalPadding': context.formatNum(
          config.indicatorVerticalPadding,
        ),
      if (config.labelColor != null)
        'labelColor': context.formatColor(
          config.labelColor!,
          includeConst: true,
        ),
      if (config.unselectedLabelColor != null)
        'unselectedLabelColor': context.formatColor(
          config.unselectedLabelColor!,
          includeConst: true,
        ),
      if (config.overlayColor != null)
        'overlayColor': context.formatColor(
          config.overlayColor!,
          includeConst: true,
        ),
      if (config.labelHorizontalPadding != null)
        'labelHorizontalPadding': context.formatNum(
          config.labelHorizontalPadding!,
        ),
      if (config.dividerColor != null)
        'dividerColor': context.formatColor(
          config.dividerColor!,
          includeConst: true,
        ),
      if (config.dividerHeight != null)
        'dividerHeight': context.formatNum(config.dividerHeight!),
      if (config.tabAlignment != null)
        'tabAlignment': 'TabAlignment.${config.tabAlignment!.name}',
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
              context.formatString(entry.key): context.formatList([
                for (final id in entry.value) context.formatString(id),
              ], indent: indent + 4),
          },
          indent: indent + 2,
          isConst: true,
        ),
    };
    return context.formatCall(
      'SuperTabConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}
