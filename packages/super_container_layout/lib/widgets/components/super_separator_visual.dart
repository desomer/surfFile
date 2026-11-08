/// Rendu visuel d'un [SuperSeparator] (`divider` / `spacer`, trait plein/tireté/pointillé)
/// partagé entre le widget d'exécution et l'aperçu de l'éditeur.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../models/super_separator_config.dart';

class _SeparatorLinePainter extends CustomPainter {
  const _SeparatorLinePainter({
    required this.axis,
    required this.color,
    required this.thickness,
    required this.lineStyle,
  });

  final Axis axis;
  final Color color;
  final double thickness;
  final SuperSeparatorLineStyle lineStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (thickness <= 0 || color.a == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = lineStyle == SuperSeparatorLineStyle.dotted
          ? StrokeCap.round
          : StrokeCap.butt;

    final isHorizontal = axis == Axis.horizontal;
    final length = isHorizontal ? size.width : size.height;
    if (length <= 0) return;
    final crossCenter = (isHorizontal ? size.height : size.width) / 2;

    Offset pointAt(double mainOffset) => isHorizontal
        ? Offset(mainOffset, crossCenter)
        : Offset(crossCenter, mainOffset);

    if (lineStyle == SuperSeparatorLineStyle.solid) {
      canvas.drawLine(pointAt(0), pointAt(length), paint);
      return;
    }

    final dash = lineStyle == SuperSeparatorLineStyle.dotted
        ? math.max(1.0, thickness)
        : math.max(4.0, thickness * 3);
    final gap = lineStyle == SuperSeparatorLineStyle.dotted
        ? math.max(2.0, thickness * 2)
        : math.max(3.0, thickness * 2);
    var offset = 0.0;
    while (offset < length) {
      final end = math.min(offset + dash, length);
      canvas.drawLine(pointAt(offset), pointAt(end), paint);
      offset += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SeparatorLinePainter oldDelegate) =>
      axis != oldDelegate.axis ||
      color != oldDelegate.color ||
      thickness != oldDelegate.thickness ||
      lineStyle != oldDelegate.lineStyle;
}

class _SeparatorLineSegment extends StatelessWidget {
  const _SeparatorLineSegment({
    required this.axis,
    required this.color,
    required this.thickness,
    required this.lineStyle,
  });

  final Axis axis;
  final Color color;
  final double thickness;
  final SuperSeparatorLineStyle lineStyle;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: axis == Axis.horizontal
        ? Size(double.infinity, thickness)
        : Size(thickness, double.infinity),
    painter: _SeparatorLinePainter(
      axis: axis,
      color: color,
      thickness: thickness,
      lineStyle: lineStyle,
    ),
  );
}

/// Construit le rendu visuel d'un [SuperSeparator] (partagé entre le widget
/// runtime et l'aperçu de l'éditeur).
Widget buildSuperSeparatorVisual({
  required BuildContext context,
  required SuperSeparatorConfig config,
  required TextStyle textStyle,
  Key? separatorKey,
  Key? labelKey,
}) {
  final scheme = Theme.of(context).colorScheme;
  final dividerTheme = DividerTheme.of(context);
  final isHorizontal = config.axis == Axis.horizontal;
  final hasLabel = config.label.trim().isNotEmpty;
  final fg = config.color ?? scheme.onSurfaceVariant;
  final effectiveTextStyle = textStyle.copyWith(color: fg);

  final indentPadding = isHorizontal
      ? EdgeInsets.only(left: config.indent, right: config.endIndent)
      : EdgeInsets.only(top: config.indent, bottom: config.endIndent);

  if (config.kind == SuperSeparatorKind.spacer) {
    final Widget content = hasLabel
        ? Align(
            alignment: switch (config.labelPosition) {
              SuperSeparatorLabelPosition.start =>
                isHorizontal ? Alignment.centerLeft : Alignment.topCenter,
              SuperSeparatorLabelPosition.center => Alignment.center,
              SuperSeparatorLabelPosition.end =>
                isHorizontal ? Alignment.centerRight : Alignment.bottomCenter,
            },
            child: Text(
              config.label,
              key: labelKey,
              style: effectiveTextStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : const SizedBox.shrink();
    return Padding(
      padding: indentPadding,
      child: SizedBox(
        key: separatorKey,
        width: isHorizontal ? null : config.extent,
        height: isHorizontal ? config.extent : null,
        child: content,
      ),
    );
  }

  final effectiveLineColor =
      config.lineColor ?? dividerTheme.color ?? scheme.outlineVariant;
  final crossExtent = math.max(config.extent, config.thickness);

  if (!hasLabel && config.lineStyle == SuperSeparatorLineStyle.solid) {
    return isHorizontal
        ? Divider(
            key: separatorKey,
            height: crossExtent,
            thickness: config.thickness,
            indent: config.indent,
            endIndent: config.endIndent,
            color: effectiveLineColor,
          )
        : VerticalDivider(
            key: separatorKey,
            width: crossExtent,
            thickness: config.thickness,
            indent: config.indent,
            endIndent: config.endIndent,
            color: effectiveLineColor,
          );
  }

  Widget lineSegment() => Expanded(
    child: _SeparatorLineSegment(
      axis: config.axis,
      color: effectiveLineColor,
      thickness: config.thickness,
      lineStyle: config.lineStyle,
    ),
  );

  if (!hasLabel) {
    return Padding(
      key: separatorKey,
      padding: indentPadding,
      child: SizedBox(
        width: isHorizontal ? double.infinity : crossExtent,
        height: isHorizontal ? crossExtent : double.infinity,
        child: Center(
          child: _SeparatorLineSegment(
            axis: config.axis,
            color: effectiveLineColor,
            thickness: config.thickness,
            lineStyle: config.lineStyle,
          ),
        ),
      ),
    );
  }

  final labelWidget = Flexible(
    flex: 0,
    child: Text(
      config.label,
      key: labelKey,
      style: effectiveTextStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
  final gap = SizedBox(
    width: isHorizontal ? config.labelSpacing : 0,
    height: isHorizontal ? 0 : config.labelSpacing,
  );

  final children = switch (config.labelPosition) {
    SuperSeparatorLabelPosition.start => [
      labelWidget,
      if (config.labelSpacing > 0) gap,
      lineSegment(),
    ],
    SuperSeparatorLabelPosition.center => [
      lineSegment(),
      if (config.labelSpacing > 0) gap,
      labelWidget,
      if (config.labelSpacing > 0) gap,
      lineSegment(),
    ],
    SuperSeparatorLabelPosition.end => [
      lineSegment(),
      if (config.labelSpacing > 0) gap,
      labelWidget,
    ],
  };

  return Padding(
    key: separatorKey,
    padding: indentPadding,
    child: ConstrainedBox(
      constraints: isHorizontal
          ? BoxConstraints(minHeight: crossExtent)
          : BoxConstraints(minWidth: crossExtent),
      child: Flex(
        direction: config.axis,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    ),
  );
}
