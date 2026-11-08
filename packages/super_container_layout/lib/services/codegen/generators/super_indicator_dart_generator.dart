/// Générateur de code Dart dédié au composant [SuperIndicator] (`SuperIndicatorConfig`).
library;

import '../../../models/super_indicator_config.dart';
import '../dart_code_generator.dart';

/// Classe de génération de code Dart dédiée à [SuperIndicator] (`SuperIndicatorConfig`).
class SuperIndicatorDartGenerator extends ComponentDartGenerator {
  const SuperIndicatorDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperIndicatorConfig>(id) ??
        const SuperIndicatorConfig();
    final behaviors = context.appearance.behaviorsFor(id);
    final isDynamic = context.isDynamicInstanceId(id);
    final canWidgetBeConst =
        !isDynamic &&
        behaviors.isEmpty &&
        config.states == null &&
        context.canContainerStyleBeConst(config.style);

    final args = <String, String>{
      'id': context.formatInstanceId(id),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (config != const SuperIndicatorConfig())
        'config': formatConfig(
          context,
          config,
          indent: indent + 2,
          includeConst:
              !canWidgetBeConst &&
              config.states == null &&
              context.canContainerStyleBeConst(config.style),
        ),
    };

    final prefix = canWidgetBeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperIndicator',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperIndicatorConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperIndicatorConfig config, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = SuperIndicatorConfig();
    final canBeConst =
        includeConst &&
        config.states == null &&
        context.canContainerStyleBeConst(config.style);
    final args = <String, String>{
      if (config.icon != d.icon) 'icon': context.formatString(config.icon),
      if (config.iconPosition != d.iconPosition)
        'iconPosition':
            'SuperIndicatorIconPosition.${config.iconPosition.name}',
      if (config.iconSize != null)
        'iconSize': context.formatNum(config.iconSize!),
      if (config.iconSpacing != d.iconSpacing)
        'iconSpacing': context.formatNum(config.iconSpacing),
      if (config.label != d.label) 'label': context.formatString(config.label),
      if (config.tooltip != d.tooltip)
        'tooltip': context.formatString(config.tooltip),
      if (config.enabled != d.enabled) 'enabled': '${config.enabled}',
      if (config.fontFamily != null)
        'fontFamily': context.formatString(config.fontFamily!),
      if (config.fontSize != null)
        'fontSize': context.formatNum(config.fontSize!),
      if (config.fontWeight != null)
        'fontWeight': context.formatFontWeight(config.fontWeight!),
      if (config.italic != null) 'italic': '${config.italic}',
      if (config.color != null)
        'color': context.formatColor(config.color!, includeConst: !canBeConst),
      if (config.iconColor != null)
        'iconColor': context.formatColor(
          config.iconColor!,
          includeConst: !canBeConst,
        ),
      if (config.backgroundColor != null)
        'backgroundColor': context.formatColor(
          config.backgroundColor!,
          includeConst: !canBeConst,
        ),
      if (config.borderColor != null)
        'borderColor': context.formatColor(
          config.borderColor!,
          includeConst: !canBeConst,
        ),
      if (config.radius != null) 'radius': context.formatNum(config.radius!),
      if (config.borderWidth != null)
        'borderWidth': context.formatNum(config.borderWidth!),
      if (config.elevation != null)
        'elevation': context.formatNum(config.elevation!),
      if (config.horizontalPadding != null)
        'horizontalPadding': context.formatNum(config.horizontalPadding!),
      if (config.verticalPadding != null)
        'verticalPadding': context.formatNum(config.verticalPadding!),
      if (config.textAlign != d.textAlign)
        'textAlign': context.formatTextAlign(config.textAlign),
      if (config.letterSpacing != null)
        'letterSpacing': context.formatNum(config.letterSpacing!),
      if (config.style != d.style)
        'style': context.formatContainerStyle(
          config.style,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (config.propertyBindings.isNotEmpty)
        'propertyBindings': context.formatPropertyBindings(
          'SuperIndicatorProperty',
          config.propertyBindings,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (config.states != null)
        'states': _formatIndicatorStates(
          context,
          config.states!,
          indent: indent + 2,
        ),
    };
    final prefix = canBeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperIndicatorConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: args.length > 1,
    );
  }

  static String _formatIndicatorOverride(
    DartCodegenContext context,
    IndicatorConfigOverride override, {
    int indent = 0,
  }) {
    return context.formatCall(
      'IndicatorConfigOverride',
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
            override.properties.map((p) => 'IndicatorStateProperty.${p.name}'),
            indent: indent + 2,
            isConst: true,
          ),
      },
      indent: indent,
      forceMultiline: true,
    );
  }

  static String _formatIndicatorStates(
    DartCodegenContext context,
    IndicatorConfigStates states, {
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
                  entry.value.map((p) => 'IndicatorStateProperty.${p.name}'),
                  indent: indent + 4,
                ),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (states.hover != null)
        'hover': _formatIndicatorOverride(
          context,
          states.hover!,
          indent: indent + 2,
        ),
      if (states.selected != null)
        'selected': _formatIndicatorOverride(
          context,
          states.selected!,
          indent: indent + 2,
        ),
      if (states.automatic.isNotEmpty)
        'automatic': context.formatMap({
          for (final entry in states.automatic.entries)
            'AutomaticState.${entry.key.name}': _formatIndicatorOverride(
              context,
              entry.value,
              indent: indent + 4,
            ),
        }, indent: indent + 2),
    };
    return context.formatCall(
      'IndicatorConfigStates',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}
