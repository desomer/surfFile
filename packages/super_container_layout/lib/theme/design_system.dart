import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'container_fill.dart';
import 'container_style.dart';
import 'neon_style.dart';

/// Système de design appliqué à un conteneur : sélectionner l'un d'eux règle
/// les paramètres du style (via [apply]) et fixe le rendu de la surface
/// (ombres jumelles du neumorphisme, flou du verre liquide).
enum DesignSystem {
  material('Material', 'Surface plane, ombre portée légère'),
  neumorphism('Neumorphism', 'Relief doux, ombres claire et sombre'),
  liquidGlass('Liquid Glass', 'Verre translucide et flou d’arrière-plan');

  const DesignSystem(this.label, this.description);

  final String label;
  final String description;

  /// Flou (écart type) appliqué à l'arrière-plan du verre liquide.
  static const glassBlur = 20.0;

  /// [style] avec les paramètres de ce système ; le padding et la margin sont
  /// conservés.
  ContainerStyle apply(ContainerStyle style) => switch (this) {
    DesignSystem.material => ContainerStyle(
      designSystem: this,
      radius: 12,
      elevation: 1,
      shadowOpacity: .2,
      padding: style.padding,
      margin: style.margin,
      paddingInsets: style.paddingInsets,
      marginInsets: style.marginInsets,
      transform: style.transform,
      interactionEffect: style.interactionEffect,
      hoverEffect: style.hoverEffect,
      hoverTint: style.hoverTint,
      hoverColor: style.hoverColor,
    ),
    DesignSystem.neumorphism => ContainerStyle(
      designSystem: this,
      radius: 20,
      elevation: 6,
      shadowOpacity: .45,
      padding: style.padding,
      margin: style.margin,
      paddingInsets: style.paddingInsets,
      marginInsets: style.marginInsets,
      transform: style.transform,
      interactionEffect: style.interactionEffect,
      hoverEffect: style.hoverEffect,
      hoverTint: style.hoverTint,
      hoverColor: style.hoverColor,
    ),
    DesignSystem.liquidGlass => ContainerStyle(
      designSystem: this,
      fill: const ContainerFill(
        type: FillType.linear,
        start: Color(0x59FFFFFF),
        end: Color(0x14FFFFFF),
        angle: 135,
      ),
      radius: 24,
      borderWidth: 1,
      borderColor: const Color(0x80FFFFFF),
      elevation: 4,
      shadowOpacity: .15,
      neon: const NeonStyle(),
      padding: style.padding,
      margin: style.margin,
      paddingInsets: style.paddingInsets,
      marginInsets: style.marginInsets,
      transform: style.transform,
      interactionEffect: style.interactionEffect,
      hoverEffect: style.hoverEffect,
      hoverTint: style.hoverTint,
      hoverColor: style.hoverColor,
    ),
  };

  /// Ombres jumelles sur le fond [base] : l'élévation donne la distance et
  /// [strength] (0 à .6, l'opacité de l'ombre) leur intensité.
  static List<BoxShadow> neumorphicShadows(
    Color base,
    double distance,
    double strength,
  ) {
    if (distance == 0 || strength == 0) return const [];
    final amount = (strength / .6).clamp(0.0, 1.0);
    final light = Color.lerp(base, Colors.white, .75)!;
    final dark = Color.lerp(base, Colors.black, .35)!;
    final blur = distance * 2;
    return [
      BoxShadow(
        color: dark.withValues(alpha: math.min(1, .9 * amount)),
        offset: Offset(distance, distance),
        blurRadius: blur,
      ),
      BoxShadow(
        color: light.withValues(alpha: math.min(1, amount * 1.2)),
        offset: Offset(-distance, -distance),
        blurRadius: blur,
      ),
    ];
  }
}
