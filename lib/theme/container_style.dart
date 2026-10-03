import 'package:material_ui/material_ui.dart';

import 'container_fill.dart';
import 'design_system.dart';
import 'interaction_effect.dart';
import 'neon_style.dart';

@immutable
class ContainerStyle {
  const ContainerStyle({
    this.color,
    this.fill = const ContainerFill(),
    this.radius = 0,
    this.borderWidth = 0,
    this.borderColor,
    this.elevation = 0,
    this.shadowOpacity = .2,
    this.neon,
    this.padding = 0,
    this.margin = 0,
    this.designSystem = DesignSystem.material,
    this.interactionEffect = InteractionEffect.ripple,
    this.hoverEffect = false,
    this.hoverTint = HoverTint.material,
    this.hoverColor,
  });

  static const maxSpacing = 48.0;

  final Color? color;
  final ContainerFill fill;
  final double radius;
  final double borderWidth;
  final Color? borderColor;
  final double elevation;
  final double shadowOpacity;
  final NeonStyle? neon;

  /// Espace intérieur entre la surface et son contenu.
  final double padding;

  /// Espace extérieur autour de la surface.
  final double margin;
  final DesignSystem designSystem;
  final InteractionEffect interactionEffect;

  /// Voile au survol du pointeur, cumulable avec [interactionEffect].
  final bool hoverEffect;
  final HoverTint hoverTint;

  /// Couleur du voile quand [hoverTint] est [HoverTint.custom].
  final Color? hoverColor;

  /// Couleur du voile au survol ; `null` pour le gris Material.
  Color? hoverBase(Color accent) => switch (hoverTint) {
    HoverTint.material => null,
    HoverTint.accent => accent,
    HoverTint.custom => hoverColor ?? accent,
  };

  ContainerStyle copyWith({
    Color? color,
    bool resetColor = false,
    ContainerFill? fill,
    double? radius,
    double? borderWidth,
    Color? borderColor,
    bool resetBorderColor = false,
    double? elevation,
    double? shadowOpacity,
    NeonStyle? neon,
    double? padding,
    double? margin,
    DesignSystem? designSystem,
    InteractionEffect? interactionEffect,
    bool? hoverEffect,
    HoverTint? hoverTint,
    Color? hoverColor,
  }) => ContainerStyle(
    color: resetColor ? null : color ?? this.color,
    fill: fill ?? this.fill,
    radius: radius ?? this.radius,
    borderWidth: borderWidth ?? this.borderWidth,
    borderColor: resetBorderColor ? null : borderColor ?? this.borderColor,
    elevation: elevation ?? this.elevation,
    shadowOpacity: shadowOpacity ?? this.shadowOpacity,
    neon: neon ?? this.neon,
    padding: padding ?? this.padding,
    margin: margin ?? this.margin,
    designSystem: designSystem ?? this.designSystem,
    interactionEffect: interactionEffect ?? this.interactionEffect,
    hoverEffect: hoverEffect ?? this.hoverEffect,
    hoverTint: hoverTint ?? this.hoverTint,
    hoverColor: hoverColor ?? this.hoverColor,
  );

  /// `null` pour le verre liquide : le texte suit le thème, le fond translucide
  /// ne donnant pas de couleur fiable.
  Color? get foreground => designSystem == DesignSystem.liquidGlass
      ? null
      : fill.type != FillType.solid
      ? foregroundFor(Color.lerp(fill.start, fill.end, .5)!)
      : color == null
      ? null
      : foregroundFor(color!);

  static Color foregroundFor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? const Color(0xFFF1F3F8)
      : const Color(0xFF262B38);

  Map<String, Object?> toJson() => {
    'color': color?.toARGB32(),
    'fill': fill.toJson(),
    'radius': radius,
    'borderWidth': borderWidth,
    'borderColor': borderColor?.toARGB32(),
    'elevation': elevation,
    'shadowOpacity': shadowOpacity,
    'neon': neon?.toJson(),
    'padding': padding,
    'margin': margin,
    'designSystem': designSystem.name,
    'interactionEffect': interactionEffect.name,
    'hoverEffect': hoverEffect,
    'hoverTint': hoverTint.name,
    'hoverColor': hoverColor?.toARGB32(),
  };

  static ContainerStyle fromJson(
    Object? value, {
    ContainerStyle fallback = const ContainerStyle(),
  }) {
    if (value == null) return fallback;
    if (value is! Map) {
      throw const FormatException('Style de conteneur invalide.');
    }
    final color = value['color'];
    if (color != null && (color is! int || color < 0 || color > 0xFFFFFFFF)) {
      throw const FormatException('Couleur de conteneur invalide.');
    }
    final borderColor = value['borderColor'];
    if (borderColor != null &&
        (borderColor is! int || borderColor < 0 || borderColor > 0xFFFFFFFF)) {
      throw const FormatException('Couleur de bordure invalide.');
    }
    double number(String key, double min, double max, [double? fallback]) {
      final number = value[key] ?? fallback;
      if (number is! num || !number.isFinite || number < min || number > max) {
        throw FormatException('Paramètre de conteneur invalide : $key.');
      }
      return number.toDouble();
    }

    final designSystem = value['designSystem'];
    if (designSystem != null &&
        !DesignSystem.values.any((system) => system.name == designSystem)) {
      throw const FormatException('Système de design invalide.');
    }
    var interactionEffect = value['interactionEffect'];
    var hoverEffect = value['hoverEffect'];
    // « hover » était autrefois un effet exclusif.
    if (interactionEffect == 'hover') {
      interactionEffect = null;
      hoverEffect = true;
    }
    if (interactionEffect != null &&
        !InteractionEffect.values.any((e) => e.name == interactionEffect)) {
      throw const FormatException('Effet d’interaction invalide.');
    }
    if (hoverEffect != null && hoverEffect is! bool) {
      throw const FormatException('Effet au survol invalide.');
    }
    final hoverTint = value['hoverTint'];
    if (hoverTint != null &&
        !HoverTint.values.any((tint) => tint.name == hoverTint)) {
      throw const FormatException('Teinte du survol invalide.');
    }
    final hoverColor = value['hoverColor'];
    if (hoverColor != null &&
        (hoverColor is! int || hoverColor < 0 || hoverColor > 0xFFFFFFFF)) {
      throw const FormatException('Couleur du survol invalide.');
    }
    return ContainerStyle(
      color: color == null ? null : Color(color as int),
      fill: ContainerFill.fromJson(value['fill']),
      radius: number('radius', 0, 36),
      borderWidth: number('borderWidth', 0, 4),
      borderColor: borderColor == null ? null : Color(borderColor as int),
      elevation: number('elevation', 0, 16),
      shadowOpacity: number('shadowOpacity', 0, .6),
      neon: value['neon'] == null ? null : NeonStyle.fromJson(value['neon']),
      padding: number('padding', 0, maxSpacing, fallback.padding),
      margin: number('margin', 0, maxSpacing, fallback.margin),
      designSystem: designSystem == null
          ? fallback.designSystem
          : DesignSystem.values.byName(designSystem as String),
      interactionEffect: interactionEffect == null
          ? fallback.interactionEffect
          : InteractionEffect.values.byName(interactionEffect as String),
      hoverEffect: hoverEffect as bool? ?? fallback.hoverEffect,
      hoverTint: hoverTint == null
          ? fallback.hoverTint
          : HoverTint.values.byName(hoverTint as String),
      hoverColor: hoverColor == null
          ? fallback.hoverColor
          : Color(hoverColor as int),
    );
  }
}
