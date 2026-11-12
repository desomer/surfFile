/// Générateur de code Dart dédié au composant [SuperConditional] (`SuperConditionalConfig`).
library;

import '../../../models/super_conditional_config.dart';
import '../dart_code_generator.dart';

/// Classe de génération de code Dart dédiée à [SuperConditional] (`SuperConditionalConfig`).
class SuperConditionalDartGenerator extends ComponentDartGenerator {
  const SuperConditionalDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperConditionalConfig>(id) ??
        SuperConditionalConfig();
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
      'id': context.formatInstanceId(id),
      if (label != null && label != 'Conditionnel')
        'label': context.formatString(label),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (config != SuperConditionalConfig())
        'config': formatConfig(context, config, indent: indent + 2),
      if (slotEntries.isNotEmpty)
        'slots': context.formatList(
          slotEntries,
          indent: indent + 2,
          forceMultiline: true,
        ),
    };

    return context.formatCall(
      'SuperConditional',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperConditionalConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperConditionalConfig config, {
    int indent = 0,
  }) {
    final d = SuperConditionalConfig();
    final args = <String, String>{
      if (config.binding != null)
        'binding': context.formatBinding(
          config.binding!,
          indent: indent + 2,
          includeConst: true,
        ),
      if (config.cases.isNotEmpty)
        'cases': context.formatList(
          [for (final c in config.cases) context.formatString(c)],
          indent: indent + 2,
          isConst: true,
        ),
      if (config.hasDefaultCase != d.hasDefaultCase)
        'hasDefaultCase': '${config.hasDefaultCase}',
      if (config.initialCase != d.initialCase)
        'initialCase': context.formatString(config.initialCase),
      if (config.maintainState != d.maintainState)
        'maintainState': '${config.maintainState}',
      if (config.emptyText != d.emptyText)
        'emptyText': context.formatString(config.emptyText),
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
      'SuperConditionalConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}
