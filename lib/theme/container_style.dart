import 'package:material_ui/material_ui.dart';

import 'container_fill.dart';
import 'design_system.dart';
import 'interaction_effect.dart';
import 'neon_style.dart';
import 'style_extras.dart';

const Object _keep = Object();

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
    this.radii,
    this.borderWidths,
    this.borderLine = BorderLine.solid,
    this.shadow,
    this.innerShadow,
    this.opacity = 1,
    this.paddingInsets,
    this.marginInsets,
    this.backdropBlur,
    this.pattern = SurfacePattern.none,
    this.patternOpacity = .1,
    this.transform,
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

  /// Rayon par coin (haut-gauche, haut-droite, bas-droite, bas-gauche) ;
  /// `null` pour le [radius] uniforme.
  final Quad? radii;

  /// Épaisseur par côté (haut, droite, bas, gauche) ; `null` pour la
  /// [borderWidth] uniforme.
  final Quad? borderWidths;
  final BorderLine borderLine;

  /// Ombre portée détaillée ; `null` pour celle de [elevation].
  final ShadowSpec? shadow;

  /// Ombre intérieure, en creux ; `null` ou désactivée pour aucune.
  final ShadowSpec? innerShadow;

  /// Opacité de toute la surface, contenu compris.
  final double opacity;

  /// Padding et margin par côté ; `null` pour les valeurs uniformes.
  final Quad? paddingInsets;
  final Quad? marginInsets;

  /// Flou de l'arrière-plan ; `null` pour celui du design system.
  final double? backdropBlur;
  final SurfacePattern pattern;
  final double patternOpacity;
  final TransformSpec? transform;

  static const maxBlur = 40.0;

  BorderRadius get borderRadius =>
      radii?.radii ?? BorderRadius.circular(radius);

  /// Plus grand rayon, pour les effets qui n'acceptent qu'un rayon uniforme.
  double get maxRadius => radii?.max ?? radius;

  Quad get sideWidths => borderWidths ?? Quad.all(borderWidth);

  /// Bordure uniforme et pleine : dessinée par une BoxDecoration.
  bool get plainBorder => sideWidths.uniform && borderLine == BorderLine.solid;

  EdgeInsets get contentPadding =>
      paddingInsets?.insets ?? EdgeInsets.all(padding);

  EdgeInsets get outerMargin => marginInsets?.insets ?? EdgeInsets.all(margin);

  /// Ombre intérieure visible.
  bool get hasInnerShadow => innerShadow?.enabled ?? false;

  double get effectiveBackdropBlur =>
      backdropBlur ??
      (designSystem == DesignSystem.liquidGlass ? DesignSystem.glassBlur : 0);

  /// Reprend de [other] les réglages de forme et d'aspect ajoutés au style de
  /// base (coins, côtés, ombres, motif, transformation…).
  ContainerStyle withLookOf(ContainerStyle other) => ContainerStyle(
    color: color,
    fill: fill,
    radius: radius,
    borderWidth: borderWidth,
    borderColor: borderColor,
    elevation: elevation,
    shadowOpacity: shadowOpacity,
    neon: neon,
    padding: padding,
    margin: margin,
    designSystem: designSystem,
    interactionEffect: interactionEffect,
    hoverEffect: hoverEffect,
    hoverTint: hoverTint,
    hoverColor: hoverColor,
    radii: other.radii,
    borderWidths: other.borderWidths,
    borderLine: other.borderLine,
    shadow: other.shadow,
    innerShadow: other.innerShadow,
    opacity: other.opacity,
    paddingInsets: other.paddingInsets,
    marginInsets: other.marginInsets,
    backdropBlur: other.backdropBlur,
    pattern: other.pattern,
    patternOpacity: other.patternOpacity,
    transform: other.transform,
  );

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
    Object? radii = _keep,
    Object? borderWidths = _keep,
    BorderLine? borderLine,
    Object? shadow = _keep,
    Object? innerShadow = _keep,
    double? opacity,
    Object? paddingInsets = _keep,
    Object? marginInsets = _keep,
    Object? backdropBlur = _keep,
    SurfacePattern? pattern,
    double? patternOpacity,
    Object? transform = _keep,
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
    radii: identical(radii, _keep) ? this.radii : radii as Quad?,
    borderWidths: identical(borderWidths, _keep)
        ? this.borderWidths
        : borderWidths as Quad?,
    borderLine: borderLine ?? this.borderLine,
    shadow: identical(shadow, _keep) ? this.shadow : shadow as ShadowSpec?,
    innerShadow: identical(innerShadow, _keep)
        ? this.innerShadow
        : innerShadow as ShadowSpec?,
    opacity: opacity ?? this.opacity,
    paddingInsets: identical(paddingInsets, _keep)
        ? this.paddingInsets
        : paddingInsets as Quad?,
    marginInsets: identical(marginInsets, _keep)
        ? this.marginInsets
        : marginInsets as Quad?,
    backdropBlur: identical(backdropBlur, _keep)
        ? this.backdropBlur
        : (backdropBlur as num?)?.toDouble(),
    pattern: pattern ?? this.pattern,
    patternOpacity: patternOpacity ?? this.patternOpacity,
    transform: identical(transform, _keep)
        ? this.transform
        : transform as TransformSpec?,
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
    if (radii != null) 'radii': radii!.toJson(),
    if (borderWidths != null) 'borderWidths': borderWidths!.toJson(),
    if (borderLine != BorderLine.solid) 'borderLine': borderLine.name,
    if (shadow != null) 'shadow': shadow!.toJson(),
    if (innerShadow != null) 'innerShadow': innerShadow!.toJson(),
    if (opacity != 1) 'opacity': opacity,
    if (paddingInsets != null) 'paddingInsets': paddingInsets!.toJson(),
    if (marginInsets != null) 'marginInsets': marginInsets!.toJson(),
    if (backdropBlur != null) 'backdropBlur': backdropBlur,
    if (pattern != SurfacePattern.none) 'pattern': pattern.name,
    if (patternOpacity != .1) 'patternOpacity': patternOpacity,
    if (transform != null) 'transform': transform!.toJson(),
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
    final borderLine = value['borderLine'];
    if (borderLine != null &&
        !BorderLine.values.any((line) => line.name == borderLine)) {
      throw const FormatException('Type de bordure invalide.');
    }
    final pattern = value['pattern'];
    if (pattern != null &&
        !SurfacePattern.values.any((kind) => kind.name == pattern)) {
      throw const FormatException('Motif de conteneur invalide.');
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
      radii: value['radii'] == null
          ? null
          : Quad.fromJson(value['radii'], 0, 36, 'radii'),
      borderWidths: value['borderWidths'] == null
          ? null
          : Quad.fromJson(value['borderWidths'], 0, 4, 'borderWidths'),
      borderLine: borderLine == null
          ? BorderLine.solid
          : BorderLine.values.byName(borderLine as String),
      shadow: value['shadow'] == null
          ? null
          : ShadowSpec.fromJson(value['shadow'], 'shadow'),
      innerShadow: value['innerShadow'] == null
          ? null
          : ShadowSpec.fromJson(value['innerShadow'], 'innerShadow'),
      opacity: number('opacity', 0, 1, 1),
      paddingInsets: value['paddingInsets'] == null
          ? null
          : Quad.fromJson(
              value['paddingInsets'],
              0,
              maxSpacing,
              'paddingInsets',
            ),
      marginInsets: value['marginInsets'] == null
          ? null
          : Quad.fromJson(value['marginInsets'], 0, maxSpacing, 'marginInsets'),
      backdropBlur: value['backdropBlur'] == null
          ? null
          : number('backdropBlur', 0, maxBlur),
      pattern: pattern == null
          ? SurfacePattern.none
          : SurfacePattern.values.byName(pattern as String),
      patternOpacity: number('patternOpacity', 0, 1, .1),
      transform: value['transform'] == null
          ? null
          : TransformSpec.fromJson(value['transform']),
    );
  }
}
