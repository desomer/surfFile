/// Générateur de code Dart dédié au composant [SuperSeparator] (`SuperSeparatorConfig`).
library;

import '../../../models/super_separator_config.dart';
import '../dart_code_generator.dart';

/// Classe de génération de code Dart dédiée à [SuperSeparator] (`SuperSeparatorConfig`).
class SuperSeparatorDartGenerator extends ComponentDartGenerator {
  const SuperSeparatorDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperSeparatorConfig>(id) ??
        const SuperSeparatorConfig();
    final behaviors = context.appearance.behaviorsFor(id);
    final isDynamic = context.isDynamicInstanceId(id);
    final canWidgetBeConst =
        !isDynamic && behaviors.isEmpty && config.states == null;

    final args = <String, String>{
      'id': context.formatInstanceId(id),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (config != const SuperSeparatorConfig())
        'config': formatConfig(
          context,
          config,
          indent: indent + 2,
          includeConst: !canWidgetBeConst && config.states == null,
        ),
    };

    final prefix = canWidgetBeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperSeparator',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperSeparatorConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperSeparatorConfig config, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = SuperSeparatorConfig();
    final canBeConst = includeConst && config.states == null;
    final args = <String, String>{
      if (config.kind != d.kind)
        'kind': 'SuperSeparatorKind.${config.kind.name}',
      if (config.axis != d.axis) 'axis': context.formatAxis(config.axis),
      if (config.extent != d.extent) 'extent': context.formatNum(config.extent),
      if (config.thickness != d.thickness)
        'thickness': context.formatNum(config.thickness),
      if (config.indent != d.indent) 'indent': context.formatNum(config.indent),
      if (config.endIndent != d.endIndent)
        'endIndent': context.formatNum(config.endIndent),
      if (config.lineStyle != d.lineStyle)
        'lineStyle': 'SuperSeparatorLineStyle.${config.lineStyle.name}',
      if (config.lineColor != null)
        'lineColor': context.formatColor(
          config.lineColor!,
          includeConst: !canBeConst,
        ),
      if (config.label != d.label) 'label': context.formatString(config.label),
      if (config.labelPosition != d.labelPosition)
        'labelPosition':
            'SuperSeparatorLabelPosition.${config.labelPosition.name}',
      if (config.labelSpacing != d.labelSpacing)
        'labelSpacing': context.formatNum(config.labelSpacing),
      if (config.fontFamily != null)
        'fontFamily': context.formatString(config.fontFamily!),
      if (config.fontSize != null)
        'fontSize': context.formatNum(config.fontSize!),
      if (config.fontWeight != null)
        'fontWeight': context.formatFontWeight(config.fontWeight!),
      if (config.italic != null) 'italic': '${config.italic}',
      if (config.color != null)
        'color': context.formatColor(config.color!, includeConst: !canBeConst),
      if (config.letterSpacing != null)
        'letterSpacing': context.formatNum(config.letterSpacing!),
      if (config.propertyBindings.isNotEmpty)
        'propertyBindings': context.formatPropertyBindings(
          'SuperSeparatorProperty',
          config.propertyBindings,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (config.states != null)
        'states': _formatSeparatorStates(
          context,
          config.states!,
          indent: indent + 2,
        ),
    };
    final prefix = canBeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperSeparatorConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: args.length > 1,
    );
  }

  static String _formatSeparatorOverride(
    DartCodegenContext context,
    SeparatorConfigOverride override, {
    int indent = 0,
  }) {
    return context.formatCall(
      'SeparatorConfigOverride',
      const [],
      {
        'config': formatConfig(
          context,
          override.config,
          indent: indent + 2,
          includeConst: true,
        ),
        if (override.properties.isNotEmpty)
          'properties': context.formatSet(
            override.properties.map((p) => 'SeparatorStateProperty.${p.name}'),
            indent: indent + 2,
            isConst: true,
          ),
      },
      indent: indent,
      forceMultiline: true,
    );
  }

  static String _formatSeparatorStates(
    DartCodegenContext context,
    SeparatorConfigStates states, {
    int indent = 0,
  }) {
    final args = <String, String>{
      if (states.binding != null)
        'binding': context.formatBinding(
          states.binding!,
          indent: indent + 2,
          includeConst: true,
        ),
      if (states.named.isNotEmpty)
        'named': context.formatMap(
          {
            for (final entry in states.named.entries)
              context.formatString(entry.key): formatConfig(
                context,
                entry.value,
                indent: indent + 4,
              ),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (states.namedProperties.values.any((s) => s.isNotEmpty))
        'namedProperties': context.formatMap(
          {
            for (final entry in states.namedProperties.entries)
              if (entry.value.isNotEmpty)
                context.formatString(entry.key): context.formatSet(
                  entry.value.map((p) => 'SeparatorStateProperty.${p.name}'),
                  indent: indent + 4,
                ),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (states.hover != null)
        'hover': _formatSeparatorOverride(
          context,
          states.hover!,
          indent: indent + 2,
        ),
      if (states.selected != null)
        'selected': _formatSeparatorOverride(
          context,
          states.selected!,
          indent: indent + 2,
        ),
      if (states.automatic.isNotEmpty)
        'automatic': context.formatMap({
          for (final entry in states.automatic.entries)
            'AutomaticState.${entry.key.name}': _formatSeparatorOverride(
              context,
              entry.value,
              indent: indent + 4,
            ),
        }, indent: indent + 2),
    };
    return context.formatCall(
      'SeparatorConfigStates',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}
