/// Classes de génération de code Dart dédiées aux composants d'extension (`SuperCode` et `SuperChart`).
///
/// Chaque classe étend [ComponentDartGenerator] et sérialise son widget et sa
/// configuration typée ([SuperCodeConfig], [SuperChartConfig]) en omettant les
/// valeurs par défaut.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/super_chart_config.dart';
import '../../models/super_code_config.dart';

/// Classe de génération de code Dart dédiée à `SuperCode` (`SuperCodeConfig`).
class SuperCodeDartGenerator extends ComponentDartGenerator {
  const SuperCodeDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperCodeConfig>(id) ??
        const SuperCodeConfig();
    final behaviors = context.appearance.behaviorsFor(id);
    final canWidgetBeConst = behaviors.isEmpty;

    final args = <String, String>{
      'id': context.formatString(id),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (config != const SuperCodeConfig())
        'config': formatConfig(
          context,
          config,
          indent: indent + 2,
          includeConst: !canWidgetBeConst,
        ),
    };

    final prefix = canWidgetBeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperCode',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperCodeConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperCodeConfig config, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = SuperCodeConfig();
    final args = <String, String>{
      if (config.mode != d.mode) 'mode': 'SuperCodeMode.${config.mode.name}',
      if (config.binding != null)
        'binding': context.formatBinding(
          config.binding!,
          indent: indent + 2,
        ),
      if (config.errorBinding != null)
        'errorBinding': context.formatBinding(
          config.errorBinding!,
          indent: indent + 2,
        ),
      if (config.readOnly != d.readOnly) 'readOnly': '${config.readOnly}',
    };
    final prefix = includeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperCodeConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: args.length > 1,
    );
  }
}

/// Classe de génération de code Dart dédiée à `SuperChart` (`SuperChartConfig`).
class SuperChartDartGenerator extends ComponentDartGenerator {
  const SuperChartDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperChartConfig>(id) ??
        const SuperChartConfig();
    final behaviors = context.appearance.behaviorsFor(id);
    final canWidgetBeConst = behaviors.isEmpty;

    final args = <String, String>{
      'id': context.formatString(id),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (config != const SuperChartConfig())
        'config': formatConfig(
          context,
          config,
          indent: indent + 2,
          includeConst: !canWidgetBeConst,
        ),
    };

    final prefix = canWidgetBeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperChart',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperChartConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperChartConfig config, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = SuperChartConfig();
    final args = <String, String>{
      if (config.binding != null)
        'binding': context.formatBinding(
          config.binding!,
          indent: indent + 2,
        ),
      if (config.kind != d.kind) 'kind': 'SuperChartKind.${config.kind.name}',
      if (config.labelPath != d.labelPath)
        'labelPath': context.formatString(config.labelPath),
      if (!listEquals(config.series, d.series))
        'series': context.formatList(
          [
            for (final s in config.series)
              _formatSeries(context, s, indent: indent + 4),
          ],
          indent: indent + 2,
          forceMultiline: true,
        ),
      if (config.showGrid != d.showGrid) 'showGrid': '${config.showGrid}',
      if (config.showLegend != d.showLegend)
        'showLegend': '${config.showLegend}',
      if (config.enableTooltips != d.enableTooltips)
        'enableTooltips': '${config.enableTooltips}',
      if (config.enableSelection != d.enableSelection)
        'enableSelection': '${config.enableSelection}',
      if (config.showAxisLabels != d.showAxisLabels)
        'showAxisLabels': '${config.showAxisLabels}',
      if (config.showAxisTitles != d.showAxisTitles)
        'showAxisTitles': '${config.showAxisTitles}',
      if (config.xAxisTitle != d.xAxisTitle)
        'xAxisTitle': context.formatString(config.xAxisTitle),
      if (config.yAxisTitle != d.yAxisTitle)
        'yAxisTitle': context.formatString(config.yAxisTitle),
      if (config.minY != null) 'minY': context.formatNum(config.minY!),
      if (config.maxY != null) 'maxY': context.formatNum(config.maxY!),
      if (config.barStacked != d.barStacked)
        'barStacked': '${config.barStacked}',
      if (config.pieCenterSpaceRadius != d.pieCenterSpaceRadius)
        'pieCenterSpaceRadius': context.formatNum(config.pieCenterSpaceRadius),
      if (config.pieSectionsSpace != d.pieSectionsSpace)
        'pieSectionsSpace': context.formatNum(config.pieSectionsSpace),
      if (config.showDemoWhenUnbound != d.showDemoWhenUnbound)
        'showDemoWhenUnbound': '${config.showDemoWhenUnbound}',
      if (config.emptyText != d.emptyText)
        'emptyText': context.formatString(config.emptyText),
    };
    final prefix = includeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperChartConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: args.length > 1,
    );
  }

  static String _formatSeries(
    DartCodegenContext context,
    SuperChartSeries series, {
    int indent = 0,
  }) {
    const d = SuperChartSeries();
    final args = <String, String>{
      if (series.id != d.id) 'id': context.formatString(series.id),
      if (series.label != d.label) 'label': context.formatString(series.label),
      if (series.valuePath != d.valuePath)
        'valuePath': context.formatString(series.valuePath),
      if (series.secondaryValuePath != d.secondaryValuePath)
        'secondaryValuePath': context.formatString(series.secondaryValuePath),
      if (series.color != null) 'color': context.formatColor(series.color!),
      if (series.strokeWidth != d.strokeWidth)
        'strokeWidth': context.formatNum(series.strokeWidth),
      if (series.radius != d.radius) 'radius': context.formatNum(series.radius),
      if (series.isCurved != d.isCurved) 'isCurved': '${series.isCurved}',
      if (series.belowBarArea != d.belowBarArea)
        'belowBarArea': '${series.belowBarArea}',
      if (series.showDots != d.showDots) 'showDots': '${series.showDots}',
    };
    return context.formatCall(
      'SuperChartSeries',
      const [],
      args,
      indent: indent,
    );
  }
}
