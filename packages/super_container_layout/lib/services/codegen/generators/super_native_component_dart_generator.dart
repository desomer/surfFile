/// Générateur de code Dart dédié aux composants Material natifs.
library;

import '../../../models/native_component_config.dart';
import '../dart_code_generator.dart';

/// Classe de génération de code Dart dédiée aux composants Material natifs
/// (`SuperAppBar`, `SuperBottomNavigationBar`, `SuperBottomAppBar`,
/// `SuperNavigationRail`, `SuperExpansible`, `SuperMenuAnchor`).
class SuperNativeComponentDartGenerator extends ComponentDartGenerator {
  const SuperNativeComponentDartGenerator({
    required this.widgetClassName,
    this.defaultLabel,
  });

  /// Nom de la classe du widget Flutter (ex: `'SuperAppBar'`, `'SuperExpansible'`).
  final String widgetClassName;

  /// Libellé par défaut du widget.
  final String? defaultLabel;

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<NativeComponentConfig>(id) ??
        NativeComponentConfig();
    final behaviors = context.appearance.behaviorsFor(id);

    final placedIds = <String>[
      for (final regionIds in config.placements.values) ...regionIds,
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
      if (label != null && label != defaultLabel && label != id)
        'label': context.formatString(label),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (config != NativeComponentConfig())
        'nativeConfig': formatConfig(context, config, indent: indent + 2),
      if (slotEntries.isNotEmpty)
        'slots': context.formatList(
          slotEntries,
          indent: indent + 2,
          forceMultiline: true,
        ),
    };

    return context.formatCall(
      widgetClassName,
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [NativeComponentConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    NativeComponentConfig config, {
    int indent = 0,
  }) {
    final args = <String, String>{
      if (config.binding != null)
        'binding': context.formatBinding(
          config.binding!,
          indent: indent + 2,
          includeConst: true,
        ),
      if (config.properties.isNotEmpty)
        'properties': context.formatMap(
          {
            for (final entry in config.properties.entries)
              context.formatString(entry.key): context.formatLiteralValue(
                entry.value,
                indent: indent + 4,
              ),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (config.regions.isNotEmpty)
        'regions': context.formatMap(
          {
            for (final entry in config.regions.entries)
              context.formatString(entry.key): '${entry.value}',
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (config.regionAxes.isNotEmpty)
        'regionAxes': context.formatMap(
          {
            for (final entry in config.regionAxes.entries)
              context.formatString(entry.key): context.formatAxis(entry.value),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (config.regionFlows.isNotEmpty)
        'regionFlows': context.formatMap(
          {
            for (final entry in config.regionFlows.entries)
              context.formatString(entry.key): context.formatZoneFlowConfig(
                entry.value,
                indent: indent + 4,
              ),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (config.regionSizes.isNotEmpty)
        'regionSizes': context.formatMap(
          {
            for (final entry in config.regionSizes.entries)
              context.formatString(entry.key): context.formatNum(entry.value),
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
      'NativeComponentConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}
