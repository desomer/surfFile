import 'package:material_ui/material_ui.dart';

import '../../super_app.dart';
import '../../theme/appearance.dart';
import '../../theme/container_fill.dart';
import '../../theme/container_style.dart';

/// Resolves the fallback [ContainerStyle] for an item/row in collection components.
ContainerStyle resolveRowStyleFallback(
  BuildContext context, {
  required SuperApp? app,
  required String componentId,
  required String rowId,
  required ContainerStyle fallback,
}) {
  if (app == null) return fallback;
  final appearanceStyles = AppearanceScope.controllerOf(context)?.value.styles;
  return app.registry?.containerStyleById[rowId]?.value ??
      app.registry?.containerStyleById[componentId]?.value ??
      appearanceStyles?[rowId] ??
      appearanceStyles?[componentId] ??
      fallback;
}

/// Resolves the [ValueNotifier] controlling the item/row [ContainerStyle].
ValueNotifier<ContainerStyle> resolveRowStyleController(
  BuildContext context, {
  required SuperApp? app,
  required String componentId,
  required String rowId,
  required ContainerStyle fallback,
  required ValueNotifier<ContainerStyle> localStyle,
}) {
  final resolvedFallback = resolveRowStyleFallback(
    context,
    app: app,
    componentId: componentId,
    rowId: rowId,
    fallback: fallback,
  );
  return app?.registry?.styleController(rowId, fallback: resolvedFallback) ??
      localStyle;
}

/// Resolves both the state-resolved style (preserving outer margin) and the
/// margin-free effective indicator style for hover/selection row overlays.
({ContainerStyle resolved, ContainerStyle effective}) resolveRowIndicatorStyle(
  BuildContext context,
  ContainerStyle currentRowStyle, {
  required bool isHover,
  double? fallbackRadius,
  bool fallbackSelectedBorder = false,
}) {
  if (isHover) {
    final accent = AppearanceScope.of(context).accent;
    final hoverBase = currentRowStyle.hoverBase(accent);
    final defaultColor = (hoverBase ?? Theme.of(context).colorScheme.onSurface)
        .withValues(alpha: 0.08);
    final hasCustomHover = currentRowStyle.states?.hover?.isEmpty == false;
    final resolved = hasCustomHover
        ? currentRowStyle.states!.resolve(currentRowStyle, isHovered: true)
        : currentRowStyle.copyWith(clearStates: true);
    final hasFill = resolved.fill.type != FillType.solid || resolved.hasImage;
    final effective = resolved.copyWith(
      clearStates: true,
      margin: 0,
      marginInsets: null,
      hoverEffect: false,
      radius: fallbackRadius != null && resolved.radius <= 0
          ? fallbackRadius
          : resolved.radius,
      color: hasCustomHover
          ? (resolved.color ?? (hasFill ? null : defaultColor))
          : defaultColor,
    );
    return (resolved: resolved, effective: effective);
  }

  final primary = Theme.of(context).colorScheme.primary;
  final defaultColor = primary.withValues(alpha: 0.14);
  final hasCustomSelected = currentRowStyle.states?.hasSelected == true;
  final resolved = hasCustomSelected
      ? currentRowStyle.states!.resolve(currentRowStyle, isSelected: true)
      : currentRowStyle.copyWith(clearStates: true);
  final hasFill = resolved.fill.type != FillType.solid || resolved.hasImage;
  final effective = resolved.copyWith(
    clearStates: true,
    margin: 0,
    marginInsets: null,
    hoverEffect: false,
    radius: fallbackRadius != null && resolved.radius <= 0
        ? fallbackRadius
        : resolved.radius,
    color: hasCustomSelected
        ? (resolved.color ?? (hasFill ? null : defaultColor))
        : defaultColor,
    borderWidth: fallbackSelectedBorder && !hasCustomSelected
        ? 1
        : resolved.borderWidth,
    borderColor: fallbackSelectedBorder && !hasCustomSelected
        ? primary.withValues(alpha: 0.6)
        : resolved.borderColor,
  );
  return (resolved: resolved, effective: effective);
}
