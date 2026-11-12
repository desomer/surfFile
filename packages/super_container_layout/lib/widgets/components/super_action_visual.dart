/// Rendu visuel et adaptation en destination de navigation pour [SuperAction].
///
/// Contient [buildSuperActionVisual], [buildSuperActionTabVisual],
/// [SuperActionNavigationScope] et [executeSuperActionClick], partagés entre
/// le composant d'exécution [SuperAction], les barres de navigation natives,
/// [SuperTab] et l'aperçu de l'éditeur.
library;

import 'package:material_ui/material_ui.dart';

import '../../theme/theme_color.dart';

import '../../models/component_behavior.dart';
import '../../models/super_action_config.dart';
import '../../theme/appearance.dart';
import '../../theme/container_fill.dart';
import '../../theme/style_extras.dart';
import '../surfaces/styled_surface.dart';

/// Construit le rendu visuel d'un [SuperAction] (partagé entre le widget
/// runtime et l'aperçu de l'éditeur).
Widget buildSuperActionVisual({
  required BuildContext context,
  required SuperActionConfig config,
  required TextStyle textStyle,
  required VoidCallback? onPressed,
  FocusNode? focusNode,
  Key? buttonKey,
  Key? labelKey,
  Key? iconKey,
  bool inTab = false,
}) {
  final variant = config.effectiveVariant(inTab: inTab);
  final scheme = Theme.of(context).colorScheme;
  textStyle = textStyle.copyWith(color: textStyle.color.resolveTheme(context));
  final effectiveOnPressed = config.enabled ? (onPressed ?? () {}) : null;
  final align = switch (config.textAlign) {
    TextAlign.start || TextAlign.left => MainAxisAlignment.start,
    TextAlign.end || TextAlign.right => MainAxisAlignment.end,
    _ => MainAxisAlignment.center,
  };
  final hasIcon = config.kind.hasIcon && config.icon.trim().isNotEmpty;
  final iconData = hasIcon ? SuperActionIcons.resolve(config.icon) : null;
  final effectiveIconColor =
      config.iconColor.resolveTheme(context) ??
      config.color.resolveTheme(context);
  final iconWidget = hasIcon
      ? Icon(
          iconData,
          key: iconKey,
          size: config.iconSize,
          color: effectiveIconColor,
        )
      : SizedBox(
          key: iconKey,
          width: config.iconSize ?? 20,
          height: config.iconSize ?? 20,
        );
  final textWidget = Text(
    config.label,
    key: labelKey,
    style: textStyle,
    textAlign: config.textAlign,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  final Widget innerContent = switch (config.kind) {
    SuperActionKind.icon => iconWidget,
    SuperActionKind.text => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: align,
      children: [Flexible(child: textWidget)],
    ),
    SuperActionKind.textAndIcon => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: align,
      children: !hasIcon
          ? [Flexible(child: textWidget)]
          : config.iconPosition == SuperActionIconPosition.leading
          ? [
              iconWidget,
              SizedBox(width: config.iconSpacing),
              Flexible(child: textWidget),
            ]
          : [
              Flexible(child: textWidget),
              SizedBox(width: config.iconSpacing),
              iconWidget,
            ],
    ),
  };

  final hasCustomSurface =
      variant == SuperActionVariant.surface ||
      config.style.fill.type != FillType.solid ||
      config.style.hasImage ||
      config.style.neon != null ||
      config.style.shadow != null ||
      config.style.hasInnerShadow ||
      config.style.effectiveBackdropBlur > 0 ||
      config.style.pattern != SurfacePattern.none ||
      config.style.hoverEffect ||
      (config.style.transform != null && !config.style.transform!.isIdentity);

  Widget button;
  if (hasCustomSurface) {
    final surfaceStyle = config.style.copyWith(
      color:
          config.backgroundColor.resolveTheme(context) ??
          config.style.color.resolveTheme(context),
      borderColor:
          config.borderColor.resolveTheme(context) ??
          config.style.borderColor.resolveTheme(context),
      radius: config.radius ?? config.style.radius,
      borderWidth: config.borderWidth ?? config.style.borderWidth,
      elevation: config.elevation ?? config.style.elevation,
    );
    final defaultBg = switch (variant) {
      SuperActionVariant.filled || SuperActionVariant.surface => scheme.primary,
      SuperActionVariant.tonal => scheme.secondaryContainer,
      SuperActionVariant.elevated => scheme.surfaceContainerLow,
      SuperActionVariant.outlined ||
      SuperActionVariant.text ||
      SuperActionVariant.icon => Colors.transparent,
    };
    final defaultFg = switch (variant) {
      SuperActionVariant.filled ||
      SuperActionVariant.surface => scheme.onPrimary,
      SuperActionVariant.tonal => scheme.onSecondaryContainer,
      SuperActionVariant.elevated ||
      SuperActionVariant.outlined ||
      SuperActionVariant.text => scheme.primary,
      SuperActionVariant.icon => scheme.onSurfaceVariant,
    };
    final pad =
        config.horizontalPadding != null || config.verticalPadding != null
        ? EdgeInsets.symmetric(
            horizontal:
                config.horizontalPadding ??
                (config.kind == SuperActionKind.icon ? 10 : 16),
            vertical: config.verticalPadding ?? 10,
          )
        : surfaceStyle.padding > 0 || surfaceStyle.paddingInsets != null
        ? surfaceStyle.contentPadding
        : EdgeInsets.symmetric(
            horizontal: config.kind == SuperActionKind.icon ? 10 : 16,
            vertical: 10,
          );
    final fg = config.color.resolveTheme(context) ?? defaultFg;
    button = Padding(
      padding: surfaceStyle.outerMargin,
      child: StyledSurface(
        key: buttonKey,
        style: surfaceStyle,
        fallbackColor: defaultBg,
        borderColor: config.borderColor.resolveTheme(context) ?? scheme.outline,
        child: InkWell(
          focusNode: focusNode,
          borderRadius: surfaceStyle.borderRadius,
          onTap: effectiveOnPressed,
          child: Padding(
            padding: pad,
            child: IconTheme.merge(
              data: IconThemeData(
                color: effectiveIconColor ?? fg,
                size: config.iconSize ?? 20,
              ),
              child: DefaultTextStyle.merge(
                style: textStyle.copyWith(color: fg),
                child: innerContent,
              ),
            ),
          ),
        ),
      ),
    );
    if (!config.enabled) {
      button = Opacity(opacity: 0.45, child: button);
    }
  } else {
    final bg =
        config.backgroundColor.resolveTheme(context) ??
        config.style.color.resolveTheme(context);
    final fg = config.color.resolveTheme(context);
    final bColor =
        config.borderColor.resolveTheme(context) ??
        config.style.borderColor.resolveTheme(context);
    final bWidth =
        config.borderWidth ??
        (config.style.borderWidth > 0 ? config.style.borderWidth : null);
    final rad =
        config.radius ?? (config.style.radius > 0 ? config.style.radius : null);
    final elev =
        config.elevation ??
        (config.style.elevation > 0 ? config.style.elevation : null);
    final pad =
        config.horizontalPadding != null || config.verticalPadding != null
        ? EdgeInsets.symmetric(
            horizontal:
                config.horizontalPadding ??
                (config.kind == SuperActionKind.icon ? 10 : 16),
            vertical: config.verticalPadding ?? 10,
          )
        : (config.style.padding > 0 || config.style.paddingInsets != null)
        ? config.style.contentPadding
        : null;
    final shape = rad != null || config.style.radii != null
        ? RoundedRectangleBorder(
            borderRadius: rad != null
                ? BorderRadius.circular(rad)
                : config.style.borderRadius,
          )
        : null;
    final side = bColor != null || bWidth != null
        ? BorderSide(color: bColor ?? scheme.outline, width: bWidth ?? 1)
        : null;

    final buttonStyle = ButtonStyle(
      backgroundColor: bg != null ? WidgetStatePropertyAll(bg) : null,
      foregroundColor: fg != null ? WidgetStatePropertyAll(fg) : null,
      iconColor: (effectiveIconColor != null)
          ? WidgetStatePropertyAll(effectiveIconColor)
          : null,
      iconSize: config.iconSize != null
          ? WidgetStatePropertyAll(config.iconSize)
          : null,
      textStyle: WidgetStatePropertyAll(textStyle),
      elevation: elev != null ? WidgetStatePropertyAll(elev) : null,
      padding: pad != null ? WidgetStatePropertyAll(pad) : null,
      shape: shape != null ? WidgetStatePropertyAll(shape) : null,
      side: side != null ? WidgetStatePropertyAll(side) : null,
    );

    button = switch (variant) {
      SuperActionVariant.filled => FilledButton(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
      SuperActionVariant.tonal => FilledButton.tonal(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
      SuperActionVariant.elevated => ElevatedButton(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
      SuperActionVariant.outlined => OutlinedButton(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
      SuperActionVariant.text => TextButton(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
      SuperActionVariant.icon =>
        config.kind == SuperActionKind.icon
            ? IconButton(
                key: buttonKey,
                focusNode: focusNode,
                style: buttonStyle,
                iconSize: config.iconSize,
                color: effectiveIconColor,
                onPressed: effectiveOnPressed,
                icon: iconWidget,
              )
            : TextButton(
                key: buttonKey,
                focusNode: focusNode,
                style: buttonStyle,
                onPressed: effectiveOnPressed,
                child: innerContent,
              ),
      SuperActionVariant.surface => FilledButton(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
    };
  }

  if (config.tooltip.trim().isNotEmpty) {
    button = Tooltip(message: config.tooltip, child: button);
  }
  return button;
}

/// Construit le rendu visuel d'un [SuperAction] lorsqu'il est affiché comme
/// onglet dans un [SuperTab] (`SuperActionNavigationPart.tab`).
Widget buildSuperActionTabVisual({
  required BuildContext context,
  required String componentId,
  required SuperActionConfig config,
  required TextStyle textStyle,
}) {
  final variant = config.effectiveVariant(inTab: true);
  final scheme = Theme.of(context).colorScheme;
  final defaultBg = switch (variant) {
    SuperActionVariant.filled || SuperActionVariant.surface => scheme.primary,
    SuperActionVariant.tonal => scheme.secondaryContainer,
    SuperActionVariant.elevated => scheme.surfaceContainerLow,
    SuperActionVariant.outlined ||
    SuperActionVariant.text ||
    SuperActionVariant.icon => Colors.transparent,
  };
  final defaultFg = switch (variant) {
    SuperActionVariant.filled || SuperActionVariant.surface => scheme.onPrimary,
    SuperActionVariant.tonal => scheme.onSecondaryContainer,
    SuperActionVariant.elevated ||
    SuperActionVariant.outlined ||
    SuperActionVariant.text => scheme.primary,
    SuperActionVariant.icon => scheme.onSurfaceVariant,
  };
  final fg =
      config.color.resolveTheme(context) ??
      ((variant == SuperActionVariant.filled ||
              variant == SuperActionVariant.surface)
          ? defaultFg
          : null);
  final effectiveIconColor =
      config.iconColor.resolveTheme(context) ??
      fg ??
      config.color.resolveTheme(context);

  final surfaceStyle = config.style.copyWith(
    color:
        config.backgroundColor.resolveTheme(context) ??
        config.style.color.resolveTheme(context),
    borderColor:
        config.borderColor.resolveTheme(context) ??
        config.style.borderColor.resolveTheme(context),
    radius: config.radius ?? config.style.radius,
    borderWidth: config.borderWidth ?? config.style.borderWidth,
    elevation:
        config.elevation ??
        (variant == SuperActionVariant.elevated && config.style.elevation == 0
            ? 1.0
            : config.style.elevation),
  );

  final hasIcon = config.kind.hasIcon && config.icon.trim().isNotEmpty;
  final iconWidget = hasIcon
      ? Icon(
          SuperActionIcons.resolve(config.icon),
          key: ValueKey('super-action-icon-$componentId'),
          size: config.iconSize ?? 18,
          color: effectiveIconColor,
        )
      : SizedBox(
          key: ValueKey('super-action-icon-$componentId'),
          width: config.iconSize ?? 18,
          height: config.iconSize ?? 18,
        );
  final textWidget = Text(
    config.label,
    key: ValueKey('super-action-label-$componentId'),
    style: fg != null ? textStyle.copyWith(color: fg) : textStyle,
    textAlign: config.textAlign,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
  Widget tabVisual = switch (config.kind) {
    SuperActionKind.icon => iconWidget,
    SuperActionKind.text => textWidget,
    SuperActionKind.textAndIcon =>
      !hasIcon
          ? textWidget
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: config.iconPosition == SuperActionIconPosition.leading
                  ? [
                      iconWidget,
                      SizedBox(width: config.iconSpacing),
                      Flexible(child: textWidget),
                    ]
                  : [
                      Flexible(child: textWidget),
                      SizedBox(width: config.iconSpacing),
                      iconWidget,
                    ],
            ),
  };
  if (!config.enabled) {
    tabVisual = Opacity(opacity: 0.45, child: tabVisual);
  }
  if (config.tooltip.trim().isNotEmpty) {
    tabVisual = Tooltip(message: config.tooltip, child: tabVisual);
  }

  final pad = config.horizontalPadding != null || config.verticalPadding != null
      ? EdgeInsets.symmetric(
          horizontal:
              config.horizontalPadding ??
              (config.kind == SuperActionKind.icon ? 8 : 12),
          vertical: config.verticalPadding ?? 4,
        )
      : (surfaceStyle.padding > 0 || surfaceStyle.paddingInsets != null)
      ? surfaceStyle.contentPadding
      : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);

  final effectiveBorderColor =
      config.borderColor.resolveTheme(context) ??
      (variant == SuperActionVariant.outlined
          ? scheme.outline
          : Colors.transparent);

  final hasSurface =
      (variant != SuperActionVariant.text &&
          variant != SuperActionVariant.icon) ||
      config.backgroundColor.resolveTheme(context) != null ||
      config.borderColor.resolveTheme(context) != null ||
      (config.borderWidth != null && config.borderWidth! > 0) ||
      (config.radius != null && config.radius! > 0) ||
      (config.elevation != null && config.elevation! > 0) ||
      surfaceStyle.color != null ||
      surfaceStyle.fill.type != FillType.solid ||
      surfaceStyle.elevation > 0 ||
      surfaceStyle.borderWidth > 0 ||
      surfaceStyle.radius > 0 ||
      surfaceStyle.radii != null ||
      surfaceStyle.hasImage ||
      surfaceStyle.shadow != null ||
      surfaceStyle.hasInnerShadow ||
      surfaceStyle.neon != null ||
      surfaceStyle.pattern != SurfacePattern.none;

  Widget styledTab = hasSurface
      ? StyledSurface(
          key: ValueKey('super-action-surface-$componentId'),
          style: surfaceStyle,
          fallbackColor: defaultBg,
          borderColor: effectiveBorderColor,
          child: Padding(
            padding: pad,
            child: Center(widthFactor: 1, child: tabVisual),
          ),
        )
      : Padding(
          padding: pad,
          child: Center(widthFactor: 1, child: tabVisual),
        );

  if (surfaceStyle.outerMargin != EdgeInsets.zero) {
    styledTab = Padding(padding: surfaceStyle.outerMargin, child: styledTab);
  }
  return styledTab;
}

/// Part of a native navigation destination or tab rendered by a [SuperAction].
enum SuperActionNavigationPart { icon, label, tab }

/// Scope instructing a descendant [SuperAction] to render as the icon or label
/// of a native navigation destination (`NavigationRailDestination` or
/// `BottomNavigationBarItem`) while preserving its editor interactions.
class SuperActionNavigationScope extends InheritedWidget {
  const SuperActionNavigationScope({
    required this.part,
    this.selected = false,
    required super.child,
    super.key,
  });

  final SuperActionNavigationPart part;
  final bool selected;

  static SuperActionNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperActionNavigationScope>();

  @override
  bool updateShouldNotify(SuperActionNavigationScope oldWidget) =>
      part != oldWidget.part || selected != oldWidget.selected;
}

/// Executes [onPressed] and enabled click actions for [id].
/// Event actions are observed separately by the slot without consuming gestures.
void executeSuperActionClick(
  BuildContext context,
  String id, {
  VoidCallback? onPressed,
  List<ComponentBehavior>? behaviours,
}) {
  onPressed?.call();
  final appearance =
      AppearanceScope.controllerOf(context)?.value ??
      AppearanceScope.of(context);
  final behaviors = behaviours ?? appearance.behaviorsFor(id);
  for (final behavior in behaviors) {
    if (behavior.enabled &&
        behavior.trigger == BehaviorTrigger.click &&
        behavior.action is! EmitEventAction) {
      behavior.execute(context);
    }
  }
}
