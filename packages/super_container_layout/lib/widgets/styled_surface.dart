import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../theme/container_style.dart';
import '../theme/design_system.dart';
import '../theme/interaction_effect.dart';
import '../theme/style_extras.dart';
import '../theme/appearance.dart';
import 'interaction_effect_box.dart';
import 'neon_surface.dart';
import 'surface_painters.dart';

class StyledSurface extends StatelessWidget {
  const StyledSurface({
    required this.style,
    required this.fallbackColor,
    required this.borderColor,
    required this.child,
    this.horizontalBorder = false,
    super.key,
  });

  final ContainerStyle style;
  final Color fallbackColor;
  final Color borderColor;
  final Widget child;
  final bool horizontalBorder;

  @override
  Widget build(BuildContext context) => InteractionEffectBox(
    effect: style.interactionEffect,
    hover: style.hoverEffect,
    hoverColor: style.hoverBase(AppearanceScope.of(context).accent),
    radius: style.maxRadius,
    borderRadius: style.borderRadius,
    builder: _surface,
  );

  Widget _surface(BuildContext context, double elevationBoost) {
    final custom = style.shadow;
    final elevation = custom != null
        ? 0.0
        : (style.elevation + elevationBoost).clamp(0.0, double.infinity);
    final gradient = style.fill.gradient();
    final borderSide = BorderSide(
      color: style.borderColor ?? borderColor,
      width: style.borderWidth,
      style: style.borderWidth == 0 ? BorderStyle.none : BorderStyle.solid,
    );
    final radius = style.borderRadius;
    final shape = RoundedRectangleBorder(borderRadius: radius);
    final system = style.designSystem;
    final neumorphic = system == DesignSystem.neumorphism;
    final plain = style.plainBorder;
    final hasOverlay =
        style.pattern != SurfacePattern.none || style.hasInnerShadow;
    final baseColor = style.color ?? fallbackColor;
    Widget content = hasOverlay
        ? Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: SurfaceOverlayPainter(
                      radii: radius,
                      pattern: style.pattern,
                      patternOpacity: style.patternOpacity,
                      ink:
                          style.foreground ??
                          Theme.of(context).colorScheme.onSurface,
                      innerShadow: style.innerShadow,
                    ),
                  ),
                ),
              ),
              child,
            ],
          )
        : child;
    Widget material = Material(
      color: gradient == null ? baseColor : Colors.transparent,
      elevation: neumorphic ? 0 : elevation,
      shadowColor: Colors.black.withValues(alpha: style.shadowOpacity),
      surfaceTintColor: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: radius,
          border: !plain
              ? null
              : horizontalBorder && style.maxRadius == 0
              ? Border.symmetric(horizontal: borderSide)
              : Border.fromBorderSide(borderSide),
        ),
        child: content,
      ),
    );
    if (!plain) {
      material = CustomPaint(
        foregroundPainter: StyleBorderPainter(
          widths: style.sideWidths,
          color: style.borderColor ?? borderColor,
          radii: radius,
          line: style.borderLine,
        ),
        child: material,
      );
    }
    final blur = style.effectiveBackdropBlur;
    if (blur > 0) {
      material = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: material,
        ),
      );
    }
    if (custom != null) {
      material = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: custom.enabled ? [custom.toBoxShadow()] : null,
        ),
        child: material,
      );
    } else if (neumorphic) {
      material = AnimatedContainer(
        duration: InteractionEffect.duration,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: DesignSystem.neumorphicShadows(
            baseColor,
            elevation,
            style.shadowOpacity,
          ),
        ),
        child: material,
      );
    }
    final neon = style.neon;
    Widget result = neon == null
        ? material
        : NeonSurface(
            style: neon,
            accent: AppearanceScope.of(context).accent,
            radius: style.maxRadius,
            corners: radius,
            child: material,
          );
    if (style.opacity < 1) {
      result = Opacity(opacity: style.opacity, child: result);
    }
    final transform = style.transform;
    if (transform != null && !transform.isIdentity) {
      result = Transform(
        transform: transform.matrix,
        alignment: Alignment.center,
        child: result,
      );
    }
    return result;
  }
}
