/// Rendu visuel d'un [SuperIndicator] partagé entre le widget d'exécution et l'aperçu de l'éditeur.
library;

import 'package:material_ui/material_ui.dart';

import '../../models/super_indicator_config.dart';
import '../../theme/container_fill.dart';
import '../../theme/style_extras.dart';
import '../surfaces/styled_surface.dart';

/// Construit le rendu visuel d'un [SuperIndicator] (partagé entre le widget
/// runtime et l'aperçu de l'éditeur).
Widget buildSuperIndicatorVisual({
  required BuildContext context,
  required SuperIndicatorConfig config,
  required TextStyle textStyle,
  Key? surfaceKey,
  Key? labelKey,
  Key? iconKey,
}) {
  final scheme = Theme.of(context).colorScheme;
  final align = switch (config.textAlign) {
    TextAlign.start || TextAlign.left => MainAxisAlignment.start,
    TextAlign.end || TextAlign.right => MainAxisAlignment.end,
    _ => MainAxisAlignment.center,
  };
  final hasIcon = config.icon.trim().isNotEmpty;
  final hasLabel = config.label.trim().isNotEmpty;
  final iconData = hasIcon ? SuperIndicatorIcons.resolve(config.icon) : null;
  final effectiveIconColor = config.iconColor ?? config.color ?? scheme.primary;
  final effectiveIconSize = config.iconSize ?? 24.0;

  final iconWidget = hasIcon
      ? Icon(
          iconData,
          key: iconKey,
          size: effectiveIconSize,
          color: effectiveIconColor,
        )
      : SizedBox(
          key: iconKey,
          width: effectiveIconSize,
          height: effectiveIconSize,
        );

  final fg = config.color ?? scheme.onSurface;
  final textWidget = hasLabel
      ? Text(
          config.label,
          key: labelKey,
          style: textStyle.copyWith(color: fg),
          textAlign: config.textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )
      : null;

  final Widget innerContent = !hasLabel
      ? iconWidget
      : Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: align,
          children: !hasIcon
              ? [Flexible(child: textWidget!)]
              : config.iconPosition == SuperIndicatorIconPosition.leading
              ? [
                  iconWidget,
                  SizedBox(width: config.iconSpacing),
                  Flexible(child: textWidget!),
                ]
              : [
                  Flexible(child: textWidget!),
                  SizedBox(width: config.iconSpacing),
                  iconWidget,
                ],
        );

  final hasCustomSurface =
      config.backgroundColor != null ||
      config.borderColor != null ||
      config.radius != null ||
      config.borderWidth != null ||
      config.elevation != null ||
      config.style.color != null ||
      config.style.borderColor != null ||
      config.style.borderWidth > 0 ||
      config.style.borderWidths != null ||
      config.style.elevation > 0 ||
      config.style.fill.type != FillType.solid ||
      config.style.hasImage ||
      config.style.neon != null ||
      config.style.shadow != null ||
      config.style.hasInnerShadow ||
      config.style.effectiveBackdropBlur > 0 ||
      config.style.pattern != SurfacePattern.none ||
      config.style.hoverEffect ||
      (config.style.transform != null && !config.style.transform!.isIdentity);

  final pad =
      config.horizontalPadding != null || config.verticalPadding != null
      ? EdgeInsets.symmetric(
          horizontal: config.horizontalPadding ?? (hasLabel ? 10 : 6),
          vertical: config.verticalPadding ?? 6,
        )
      : config.style.padding > 0 || config.style.paddingInsets != null
      ? config.style.contentPadding
      : hasCustomSurface
      ? EdgeInsets.symmetric(horizontal: hasLabel ? 10 : 6, vertical: 6)
      : EdgeInsets.zero;

  Widget indicator;
  if (hasCustomSurface) {
    final surfaceStyle = config.style.copyWith(
      color: config.backgroundColor ?? config.style.color,
      borderColor: config.borderColor ?? config.style.borderColor,
      radius: config.radius ?? config.style.radius,
      borderWidth: config.borderWidth ?? config.style.borderWidth,
      elevation: config.elevation ?? config.style.elevation,
    );
    indicator = Padding(
      padding: surfaceStyle.outerMargin,
      child: StyledSurface(
        key: surfaceKey,
        style: surfaceStyle,
        fallbackColor:
            config.backgroundColor ??
            surfaceStyle.color ??
            Colors.transparent,
        borderColor: config.borderColor ?? scheme.outline,
        child: Padding(
          padding: pad,
          child: IconTheme.merge(
            data: IconThemeData(
              color: effectiveIconColor,
              size: effectiveIconSize,
            ),
            child: DefaultTextStyle.merge(
              style: textStyle.copyWith(color: fg),
              child: innerContent,
            ),
          ),
        ),
      ),
    );
  } else {
    indicator = Padding(
      key: surfaceKey,
      padding: config.style.outerMargin + pad,
      child: IconTheme.merge(
        data: IconThemeData(color: effectiveIconColor, size: effectiveIconSize),
        child: DefaultTextStyle.merge(
          style: textStyle.copyWith(color: fg),
          child: innerContent,
        ),
      ),
    );
  }

  if (!config.enabled) {
    indicator = Opacity(opacity: 0.45, child: indicator);
  }
  if (config.tooltip.trim().isNotEmpty) {
    indicator = Tooltip(message: config.tooltip, child: indicator);
  }
  return indicator;
}
