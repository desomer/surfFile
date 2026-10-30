import 'package:material_ui/material_ui.dart';

import '../models/json_syntax.dart';
import '../models/json_text_binding.dart';

import 'container_fill.dart';
import 'design_system.dart';
import 'interaction_effect.dart';
import 'neon_style.dart';
import 'style_extras.dart';

import '../models/automatic_state.dart';

part 'surface_style_states.dart';

const Object _keep = Object();

enum ContainerStyleProperty { imageUrl }

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
    this.propertyBindings = const {},
    this.states,
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
  final Map<ContainerStyleProperty, JsonTextBinding> propertyBindings;
  final SurfaceStyleStates? states;

  static const maxBlur = 40.0;

  JsonTextBinding? get imageBinding =>
      propertyBindings[ContainerStyleProperty.imageUrl] ?? fill.imageBinding;

  bool get hasImage => fill.hasImage || imageBinding != null;

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
    states: states,
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
    propertyBindings: propertyBindings,
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
    bool resetHoverColor = false,
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
    Map<ContainerStyleProperty, JsonTextBinding>? propertyBindings,
    SurfaceStyleStates? states,
    bool clearStates = false,
  }) => ContainerStyle(
    states: clearStates ? null : states ?? this.states,
    propertyBindings: propertyBindings ?? this.propertyBindings,
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
    hoverColor: resetHoverColor ? null : hoverColor ?? this.hoverColor,
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
    if (propertyBindings.isNotEmpty)
      'propertyBindings': {
        for (final entry in propertyBindings.entries)
          entry.key.name: entry.value.toJson(),
      },
    if (states != null) 'states': states!.toJson(),
  };

  Map<String, Object?> toCompactJson() {
    const d = ContainerStyle();
    return {
      if (color != null) 'color': JsonColor.toHex(color!),
      if (fill != d.fill) 'fill': fill.toCompactJson(),
      if (radius != d.radius) 'radius': radius,
      if (borderWidth != d.borderWidth) 'borderWidth': borderWidth,
      if (borderColor != null) 'borderColor': JsonColor.toHex(borderColor!),
      if (elevation != d.elevation) 'elevation': elevation,
      if (shadowOpacity != d.shadowOpacity) 'shadowOpacity': shadowOpacity,
      if (neon != null && neon != const NeonStyle())
        'neon': neon!.toCompactJson(),
      if (padding != d.padding) 'padding': padding,
      if (margin != d.margin) 'margin': margin,
      if (designSystem != d.designSystem) 'designSystem': designSystem.name,
      if (interactionEffect != d.interactionEffect)
        'interactionEffect': interactionEffect.name,
      if (hoverEffect != d.hoverEffect) 'hoverEffect': hoverEffect,
      if (hoverTint != d.hoverTint) 'hoverTint': hoverTint.name,
      if (hoverColor != null) 'hoverColor': JsonColor.toHex(hoverColor!),
      if (radii != null) 'radii': radii!.toJson(),
      if (borderWidths != null) 'borderWidths': borderWidths!.toJson(),
      if (borderLine != BorderLine.solid) 'borderLine': borderLine.name,
      if (shadow != null) 'shadow': shadow!.toCompactJson(),
      if (innerShadow != null) 'innerShadow': innerShadow!.toCompactJson(),
      if (opacity != 1) 'opacity': opacity,
      if (paddingInsets != null) 'paddingInsets': paddingInsets!.toJson(),
      if (marginInsets != null) 'marginInsets': marginInsets!.toJson(),
      if (backdropBlur != null) 'backdropBlur': backdropBlur,
      if (pattern != SurfacePattern.none) 'pattern': pattern.name,
      if (patternOpacity != .1) 'patternOpacity': patternOpacity,
      if (transform != null) 'transform': transform!.toJson(),
      if (propertyBindings.isNotEmpty)
        'propertyBindings': {
          for (final entry in propertyBindings.entries)
            entry.key.name: entry.value.toCompactJson(),
        },
      if (states != null) 'states': states!.toCompactJson(),
    };
  }

  /// Applique un patch JSON partiel sur ce style en conservant toutes les
  /// propriétés non mentionnées dans [patch].
  ContainerStyle patchFromJson(Map<Object?, Object?> patch) {
    final merged = <String, Object?>{
      ...toJson(),
      for (final entry in patch.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    if (patch['fill'] is Map) {
      merged['fill'] = ContainerFill.fromJson(
        patch['fill'],
        fallback: fill,
      ).toJson();
    }
    if (patch['propertyBindings'] is Map) {
      final currentBindings = <String, Object?>{
        for (final entry in propertyBindings.entries)
          entry.key.name: entry.value.toJson(),
      };
      for (final entry in (patch['propertyBindings'] as Map).entries) {
        if (entry.key is String) {
          if (entry.value == null) {
            currentBindings.remove(entry.key);
          } else {
            currentBindings[entry.key as String] = entry.value;
          }
        }
      }
      merged['propertyBindings'] = currentBindings;
    }
    return ContainerStyle.fromJson(
      merged,
      fallback: patch['fill'] is Map || patch.containsKey('propertyBindings')
          ? copyWith(
              fill: patch['fill'] is Map ? const ContainerFill() : fill,
              propertyBindings: patch.containsKey('propertyBindings')
                  ? const {}
                  : propertyBindings,
            )
          : this,
    );
  }

  static ContainerStyle fromJson(
    Object? value, {
    ContainerStyle fallback = const ContainerStyle(),
  }) {
    if (value == null) return fallback;
    if (value is! Map) {
      throw const FormatException('Style de conteneur invalide.');
    }
    final Color? parsedColor;
    try {
      parsedColor = value.containsKey('color')
          ? JsonColor.parseNullable(value['color'], 'color')
          : fallback.color;
    } on FormatException {
      throw const FormatException('Couleur de conteneur invalide.');
    }
    final Color? parsedBorderColor;
    try {
      parsedBorderColor = value.containsKey('borderColor')
          ? JsonColor.parseNullable(value['borderColor'], 'borderColor')
          : fallback.borderColor;
    } on FormatException {
      throw const FormatException('Couleur de bordure invalide.');
    }
    double number(String key, double min, double max, [double? fallbackVal]) {
      final number = value[key] ?? fallbackVal;
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
    final Color? parsedHoverColor;
    try {
      parsedHoverColor = value.containsKey('hoverColor')
          ? JsonColor.parseNullable(value['hoverColor'], 'hoverColor')
          : fallback.hoverColor;
    } on FormatException {
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
    final rawPropertyBindings = value['propertyBindings'];
    if (rawPropertyBindings != null && rawPropertyBindings is! Map) {
      throw const FormatException(
        'Liaisons de propriétés de conteneur invalides.',
      );
    }
    final Map<ContainerStyleProperty, JsonTextBinding> propertyBindings;
    if (!value.containsKey('propertyBindings')) {
      propertyBindings = fallback.propertyBindings;
    } else {
      propertyBindings = <ContainerStyleProperty, JsonTextBinding>{};
      for (final entry in (rawPropertyBindings as Map? ?? {}).entries) {
        if (entry.key is! String) {
          throw const FormatException(
            'Liaison de propriété de conteneur invalide.',
          );
        }
        final property = ContainerStyleProperty.values
            .where((candidate) => candidate.name == entry.key)
            .firstOrNull;
        if (property == null ||
            (entry.value != null &&
                entry.value is! Map &&
                entry.value is! String)) {
          throw const FormatException(
            'Liaison de propriété de conteneur invalide.',
          );
        }
        if (entry.value != null) {
          propertyBindings[property] = JsonTextBinding.fromJson(entry.value);
        }
      }
    }
    return ContainerStyle(
      states: value['states'] == null
          ? fallback.states
          : SurfaceStyleStates.fromJson(value['states']),
      propertyBindings: Map.unmodifiable(propertyBindings),
      color: parsedColor,
      fill: value['fill'] == null
          ? fallback.fill
          : ContainerFill.fromJson(value['fill'], fallback: fallback.fill),
      radius: number('radius', 0, 36, fallback.radius),
      borderWidth: number('borderWidth', 0, 4, fallback.borderWidth),
      borderColor: parsedBorderColor,
      elevation: number('elevation', 0, 16, fallback.elevation),
      shadowOpacity: number('shadowOpacity', 0, 1, fallback.shadowOpacity),
      neon: value['neon'] == null
          ? fallback.neon
          : NeonStyle.fromJson(value['neon']),
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
      hoverColor: parsedHoverColor,
      radii: value['radii'] == null
          ? fallback.radii
          : Quad.fromJson(value['radii'], 0, 36, 'radii'),
      borderWidths: value['borderWidths'] == null
          ? fallback.borderWidths
          : Quad.fromJson(value['borderWidths'], 0, 4, 'borderWidths'),
      borderLine: borderLine == null
          ? fallback.borderLine
          : BorderLine.values.byName(borderLine as String),
      shadow: value['shadow'] == null
          ? fallback.shadow
          : ShadowSpec.fromJson(value['shadow'], 'shadow'),
      innerShadow: value['innerShadow'] == null
          ? fallback.innerShadow
          : ShadowSpec.fromJson(value['innerShadow'], 'innerShadow'),
      opacity: number('opacity', 0, 1, fallback.opacity),
      paddingInsets: value['paddingInsets'] == null
          ? fallback.paddingInsets
          : Quad.fromJson(
              value['paddingInsets'],
              0,
              maxSpacing,
              'paddingInsets',
            ),
      marginInsets: value['marginInsets'] == null
          ? fallback.marginInsets
          : Quad.fromJson(value['marginInsets'], 0, maxSpacing, 'marginInsets'),
      backdropBlur: value['backdropBlur'] == null
          ? fallback.backdropBlur
          : number('backdropBlur', 0, maxBlur),
      pattern: pattern == null
          ? fallback.pattern
          : SurfacePattern.values.byName(pattern as String),
      patternOpacity: number('patternOpacity', 0, 1, fallback.patternOpacity),
      transform: value['transform'] == null
          ? fallback.transform
          : TransformSpec.fromJson(value['transform']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContainerStyle && _sameStyleValue(toJson(), other.toJson()));

  @override
  int get hashCode => _styleValueHash(toJson());
}

String _formatStyleNumber(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

String _formatStyleQuad(double uniform, Quad? quad) {
  if (quad != null && !quad.uniform) {
    return '${_formatStyleNumber(quad.top)}/${_formatStyleNumber(quad.right)}/'
        '${_formatStyleNumber(quad.bottom)}/${_formatStyleNumber(quad.left)} px';
  }
  final v = quad?.top ?? uniform;
  return '${_formatStyleNumber(v)} px';
}

/// Résumé des propriétés d'un [ContainerStyle] pour l'info-bulle du menu contextuel.
String formatContainerStyleTooltip({
  required String title,
  required ContainerStyle style,
}) {
  final baseFillLabel = switch (style.fill.type) {
    FillType.solid =>
      style.color != null ? JsonColor.toHex(style.color!) : 'Auto',
    FillType.linear =>
      'Dégradé linéaire (${JsonColor.toHex(style.fill.start)} → ${JsonColor.toHex(style.fill.end)})',
    FillType.radial =>
      'Dégradé radial (${JsonColor.toHex(style.fill.start)} → ${JsonColor.toHex(style.fill.end)})',
    FillType.sweep =>
      'Dégradé conique (${JsonColor.toHex(style.fill.start)} → ${JsonColor.toHex(style.fill.end)})',
  };
  final imageTarget = style.fill.imageUrl.trim().isNotEmpty
      ? style.fill.imageUrl.trim()
      : '${style.imageBinding?.toCompactJson() ?? ''}';
  final fillLabel = style.hasImage
      ? '$baseFillLabel · Image ($imageTarget)'
      : baseFillLabel;
  final radiusLabel = _formatStyleQuad(style.radius, style.radii);
  final borderExtent = _formatStyleQuad(style.borderWidth, style.borderWidths);
  final borderDetails = <String>[
    borderExtent,
    if (style.borderColor != null) JsonColor.toHex(style.borderColor!),
    if (style.borderLine != BorderLine.solid) style.borderLine.label,
  ].join(' ');
  final extras = <String>[
    if (style.opacity != 1) 'Opacité : ${(style.opacity * 100).round()} %',
    if (style.neon?.enabled == true) 'Néon : Activé',
    if (style.hoverEffect) 'Survol : Activé',
    if (style.backdropBlur != null && style.backdropBlur! > 0)
      'Flou : ${_formatStyleNumber(style.backdropBlur!)} px',
    if (style.pattern != SurfacePattern.none) 'Motif : ${style.pattern.label}',
    if (style.states != null) 'États : Configurés',
  ];
  return [
    title,
    'Design : ${style.designSystem.label} · Fond : $fillLabel',
    'Rayon : $radiusLabel · Bordure : $borderDetails · Élévation : ${_formatStyleNumber(style.elevation)}',
    'Padding : ${_formatStyleQuad(style.padding, style.paddingInsets)} · '
        'Marge : ${_formatStyleQuad(style.margin, style.marginInsets)}',
    if (extras.isNotEmpty) extras.join(' · '),
  ].join('\n');
}
