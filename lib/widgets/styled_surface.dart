import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../theme/container_style.dart';
import '../theme/design_system.dart';
import '../theme/interaction_effect.dart';
import '../theme/appearance.dart';
import 'interaction_effect_box.dart';
import 'neon_surface.dart';

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
    radius: style.radius,
    builder: _surface,
  );

  Widget _surface(BuildContext context, double elevationBoost) {
    final elevation = (style.elevation + elevationBoost).clamp(
      0.0,
      double.infinity,
    );
    final gradient = style.fill.gradient();
    final side = BorderSide(
      color: style.borderColor ?? borderColor,
      width: style.borderWidth,
      style: style.borderWidth == 0 ? BorderStyle.none : BorderStyle.solid,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(style.radius),
    );
    final system = style.designSystem;
    final neumorphic = system == DesignSystem.neumorphism;
    final radius = BorderRadius.circular(style.radius);
    Widget material = Material(
      color: gradient == null
          ? style.color ?? fallbackColor
          : Colors.transparent,
      elevation: neumorphic ? 0 : elevation,
      shadowColor: Colors.black.withValues(alpha: style.shadowOpacity),
      surfaceTintColor: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(style.radius),
          border: horizontalBorder && style.radius == 0
              ? Border.symmetric(horizontal: side)
              : Border.fromBorderSide(side),
        ),
        child: child,
      ),
    );
    if (system == DesignSystem.liquidGlass) {
      material = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: DesignSystem.glassBlur,
            sigmaY: DesignSystem.glassBlur,
          ),
          child: material,
        ),
      );
    } else if (neumorphic) {
      material = AnimatedContainer(
        duration: InteractionEffect.duration,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: DesignSystem.neumorphicShadows(
            style.color ?? fallbackColor,
            elevation,
            style.shadowOpacity,
          ),
        ),
        child: material,
      );
    }
    final neon = style.neon;
    return neon == null
        ? material
        : NeonSurface(
            style: neon,
            accent: AppearanceScope.of(context).accent,
            radius: style.radius,
            child: material,
          );
  }
}
