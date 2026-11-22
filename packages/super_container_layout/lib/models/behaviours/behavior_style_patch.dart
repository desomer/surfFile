/// Modèle immuable de surcharge visuelle runtime ([BehaviorStylePatch]) utilisé
/// par les comportements de changement de style (`SetStyleAction`).
///
/// Regroupe les propriétés visuelles ciblées (couleurs `ThemeColor` ou hex,
/// bordure, rayon, opacité, élévation, typographie, remplissage, ombre, néon)
/// ainsi que l'activation éventuelle d'un état métier nommé (`namedState`).
library;

import 'package:material_ui/material_ui.dart';

import '../../theme/container_fill.dart';
import '../../theme/container_style.dart';
import '../../theme/neon_style.dart';
import '../../theme/style_extras.dart';
import '../json_syntax.dart';

const Object _keep = Object();

/// Surcharge visuelle partielle et immuable appliquée en mémoire sur un composant
/// ou une surface par une action `SetStyleAction`.
@immutable
class BehaviorStylePatch {
  /// Crée un patch visuel partiel.
  const BehaviorStylePatch({
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.borderWidth,
    this.radius,
    this.opacity,
    this.elevation,
    this.fontSize,
    this.fontWeight,
    this.namedState,
    this.fill,
    this.shadow,
    this.neon,
  });

  /// Couleur de fond (accepte `ThemeColor` ou `Color` ARGB).
  final Color? backgroundColor;

  /// Couleur de texte / icône (accepte `ThemeColor` ou `Color` ARGB).
  final Color? foregroundColor;

  /// Couleur de bordure (accepte `ThemeColor` ou `Color` ARGB).
  final Color? borderColor;

  /// Épaisseur uniforme de bordure (`>= 0`).
  final double? borderWidth;

  /// Rayon uniforme des coins (`>= 0`).
  final double? radius;

  /// Opacité globale (`0.0` à `1.0`).
  final double? opacity;

  /// Élévation d'ombre portée (`>= 0`).
  final double? elevation;

  /// Taille de police (`> 0`).
  final double? fontSize;

  /// Graisse typographique (`FontWeight.w100`..`w900`).
  final FontWeight? fontWeight;

  /// Nom d'un état métier défini dans `states.named` du composant ou de la surface.
  final String? namedState;

  /// Remplissage avancé (dégradé / image) pour les surfaces.
  final ContainerFill? fill;

  /// Ombre portée détaillée pour les surfaces.
  final ShadowSpec? shadow;

  /// Halo néon pour les surfaces.
  final NeonStyle? neon;

  /// Indique si aucune propriété visuelle ni aucun état nommé n'est défini.
  bool get isEmpty =>
      backgroundColor == null &&
      foregroundColor == null &&
      borderColor == null &&
      borderWidth == null &&
      radius == null &&
      opacity == null &&
      elevation == null &&
      fontSize == null &&
      fontWeight == null &&
      namedState == null &&
      fill == null &&
      shadow == null &&
      neon == null;

  /// Indique si au moins une propriété de surface (fond, bordure, rayon, ombre,
  /// néon, remplissage) est renseignée.
  bool get hasSurfaceProperties =>
      backgroundColor != null ||
      borderColor != null ||
      borderWidth != null ||
      radius != null ||
      elevation != null ||
      fill != null ||
      shadow != null ||
      neon != null;

  /// Indique si au moins une propriété de texte / premier plan est renseignée.
  bool get hasForegroundProperties =>
      foregroundColor != null || fontSize != null || fontWeight != null;

  /// Valide les bornes numériques et les chaînes du patch.
  void validate() {
    if (borderWidth != null && (!borderWidth!.isFinite || borderWidth! < 0)) {
      throw const FormatException(
        'L’épaisseur de bordure du comportement doit être un nombre >= 0.',
      );
    }
    if (radius != null && (!radius!.isFinite || radius! < 0)) {
      throw const FormatException(
        'Le rayon des coins du comportement doit être un nombre >= 0.',
      );
    }
    if (opacity != null &&
        (!opacity!.isFinite || opacity! < 0 || opacity! > 1)) {
      throw const FormatException(
        'L’opacité du comportement doit être comprise entre 0 et 1.',
      );
    }
    if (elevation != null && (!elevation!.isFinite || elevation! < 0)) {
      throw const FormatException(
        'L’élévation du comportement doit être un nombre >= 0.',
      );
    }
    if (fontSize != null && (!fontSize!.isFinite || fontSize! <= 0)) {
      throw const FormatException(
        'La taille de police du comportement doit être strictement positive.',
      );
    }
    if (namedState != null) {
      final trimmed = namedState!.trim();
      if (trimmed.isEmpty || trimmed != namedState) {
        throw const FormatException(
          'Le nom d’état nommé du comportement ne peut pas être vide ni contenir d’espaces superflus.',
        );
      }
    }
  }

  /// Retourne une copie immuable avec possibilité d'effacer explicitement un champ.
  BehaviorStylePatch copyWith({
    Object? backgroundColor = _keep,
    Object? foregroundColor = _keep,
    Object? borderColor = _keep,
    Object? borderWidth = _keep,
    Object? radius = _keep,
    Object? opacity = _keep,
    Object? elevation = _keep,
    Object? fontSize = _keep,
    Object? fontWeight = _keep,
    Object? namedState = _keep,
    Object? fill = _keep,
    Object? shadow = _keep,
    Object? neon = _keep,
  }) => BehaviorStylePatch(
    backgroundColor: identical(backgroundColor, _keep)
        ? this.backgroundColor
        : backgroundColor as Color?,
    foregroundColor: identical(foregroundColor, _keep)
        ? this.foregroundColor
        : foregroundColor as Color?,
    borderColor: identical(borderColor, _keep)
        ? this.borderColor
        : borderColor as Color?,
    borderWidth: identical(borderWidth, _keep)
        ? this.borderWidth
        : borderWidth as double?,
    radius: identical(radius, _keep) ? this.radius : radius as double?,
    opacity: identical(opacity, _keep) ? this.opacity : opacity as double?,
    elevation: identical(elevation, _keep)
        ? this.elevation
        : elevation as double?,
    fontSize: identical(fontSize, _keep) ? this.fontSize : fontSize as double?,
    fontWeight: identical(fontWeight, _keep)
        ? this.fontWeight
        : fontWeight as FontWeight?,
    namedState: identical(namedState, _keep)
        ? this.namedState
        : namedState as String?,
    fill: identical(fill, _keep) ? this.fill : fill as ContainerFill?,
    shadow: identical(shadow, _keep) ? this.shadow : shadow as ShadowSpec?,
    neon: identical(neon, _keep) ? this.neon : neon as NeonStyle?,
  );

  /// Fusionne [other] par-dessus `this` : les propriétés non nulles de [other]
  /// remplacent celles de `this`.
  BehaviorStylePatch merge(BehaviorStylePatch other) => BehaviorStylePatch(
    backgroundColor: other.backgroundColor ?? backgroundColor,
    foregroundColor: other.foregroundColor ?? foregroundColor,
    borderColor: other.borderColor ?? borderColor,
    borderWidth: other.borderWidth ?? borderWidth,
    radius: other.radius ?? radius,
    opacity: other.opacity ?? opacity,
    elevation: other.elevation ?? elevation,
    fontSize: other.fontSize ?? fontSize,
    fontWeight: other.fontWeight ?? fontWeight,
    namedState: other.namedState ?? namedState,
    fill: other.fill ?? fill,
    shadow: other.shadow ?? shadow,
    neon: other.neon ?? neon,
  );

  /// Indique si toutes les propriétés définies dans `this` correspondent déjà
  /// à celles présentes dans [current] (utilisé pour l'opération `toggle`).
  bool isAppliedIn(BehaviorStylePatch? current) {
    if (current == null || isEmpty) return false;
    if (backgroundColor != null && current.backgroundColor != backgroundColor) {
      return false;
    }
    if (foregroundColor != null && current.foregroundColor != foregroundColor) {
      return false;
    }
    if (borderColor != null && current.borderColor != borderColor) {
      return false;
    }
    if (borderWidth != null && current.borderWidth != borderWidth) {
      return false;
    }
    if (radius != null && current.radius != radius) return false;
    if (opacity != null && current.opacity != opacity) return false;
    if (elevation != null && current.elevation != elevation) return false;
    if (fontSize != null && current.fontSize != fontSize) return false;
    if (fontWeight != null && current.fontWeight != fontWeight) return false;
    if (namedState != null && current.namedState != namedState) return false;
    if (fill != null && current.fill != fill) return false;
    if (shadow != null && current.shadow != shadow) return false;
    if (neon != null && current.neon != neon) return false;
    return true;
  }

  /// Retire de `this` uniquement les clés portées par [patch] (utilisé lors du
  /// passage à `off` d'une opération `toggle`).
  BehaviorStylePatch subtract(BehaviorStylePatch patch) => BehaviorStylePatch(
    backgroundColor: patch.backgroundColor != null ? null : backgroundColor,
    foregroundColor: patch.foregroundColor != null ? null : foregroundColor,
    borderColor: patch.borderColor != null ? null : borderColor,
    borderWidth: patch.borderWidth != null ? null : borderWidth,
    radius: patch.radius != null ? null : radius,
    opacity: patch.opacity != null ? null : opacity,
    elevation: patch.elevation != null ? null : elevation,
    fontSize: patch.fontSize != null ? null : fontSize,
    fontWeight: patch.fontWeight != null ? null : fontWeight,
    namedState: patch.namedState != null ? null : namedState,
    fill: patch.fill != null ? null : fill,
    shadow: patch.shadow != null ? null : shadow,
    neon: patch.neon != null ? null : neon,
  );

  /// Applique les propriétés de surface de ce patch sur un [ContainerStyle].
  ContainerStyle applyToContainerStyle(ContainerStyle base) {
    if (isEmpty) return base;
    final clearRadii = radius != null;
    final clearBorderWidths = borderWidth != null;
    return base.copyWith(
      color: backgroundColor ?? base.color,
      fill: fill ?? base.fill,
      borderColor: borderColor ?? base.borderColor,
      borderWidth: borderWidth ?? base.borderWidth,
      borderWidths: clearBorderWidths ? null : base.borderWidths,
      radius: radius ?? base.radius,
      radii: clearRadii ? null : base.radii,
      opacity: opacity ?? base.opacity,
      elevation: elevation ?? base.elevation,
      shadow: shadow ?? base.shadow,
      neon: neon ?? base.neon,
    );
  }

  /// Résumé lisible des propriétés configurées dans ce patch.
  String describe() {
    final parts = <String>[
      if (namedState != null) 'état "$namedState"',
      if (backgroundColor != null) 'fond ${JsonColor.toHex(backgroundColor!)}',
      if (foregroundColor != null)
        'texte ${JsonColor.toHex(foregroundColor!)}',
      if (borderColor != null) 'bordure ${JsonColor.toHex(borderColor!)}',
      if (borderWidth != null) 'épaisseur ${borderWidth!.toStringAsFixed(0)}px',
      if (radius != null) 'rayon ${radius!.toStringAsFixed(0)}px',
      if (opacity != null) 'opacité ${(opacity! * 100).round()}%',
      if (elevation != null) 'élévation ${elevation!.toStringAsFixed(0)}',
      if (fontSize != null) 'police ${fontSize!.toStringAsFixed(0)}px',
      if (fontWeight != null) 'graisse w${fontWeight!.value}',
      if (fill != null) 'remplissage ${fill!.type.name}',
      if (shadow != null) 'ombre',
      if (neon != null) 'néon',
    ];
    return parts.isEmpty ? 'aucune propriété' : parts.join(', ');
  }

  /// Sérialise ce patch au format JSON complet.
  Map<String, Object?> toJson() {
    validate();
    return {
      if (backgroundColor != null)
        'backgroundColor': JsonColor.toJson(backgroundColor!),
      if (foregroundColor != null)
        'foregroundColor': JsonColor.toJson(foregroundColor!),
      if (borderColor != null) 'borderColor': JsonColor.toJson(borderColor!),
      if (borderWidth != null) 'borderWidth': borderWidth,
      if (radius != null) 'radius': radius,
      if (opacity != null) 'opacity': opacity,
      if (elevation != null) 'elevation': elevation,
      if (fontSize != null) 'fontSize': fontSize,
      if (fontWeight != null) 'fontWeight': 'w${fontWeight!.value}',
      if (namedState != null) 'namedState': namedState,
      if (fill != null) 'fill': fill!.toJson(),
      if (shadow != null) 'shadow': shadow!.toJson(),
      if (neon != null) 'neon': neon!.toJson(),
    };
  }

  /// Sérialise ce patch au format JSON compact (`theme:*` / hex).
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      if (backgroundColor != null)
        'backgroundColor': JsonColor.toHex(backgroundColor!),
      if (foregroundColor != null)
        'foregroundColor': JsonColor.toHex(foregroundColor!),
      if (borderColor != null) 'borderColor': JsonColor.toHex(borderColor!),
      if (borderWidth != null) 'borderWidth': borderWidth,
      if (radius != null) 'radius': radius,
      if (opacity != null) 'opacity': opacity,
      if (elevation != null) 'elevation': elevation,
      if (fontSize != null) 'fontSize': fontSize,
      if (fontWeight != null) 'fontWeight': 'w${fontWeight!.value}',
      if (namedState != null) 'namedState': namedState,
      if (fill != null) 'fill': fill!.toCompactJson(),
      if (shadow != null) 'shadow': shadow!.toCompactJson(),
      if (neon != null) 'neon': neon!.toCompactJson(),
    };
  }

  /// Décode et valide un [BehaviorStylePatch] depuis une Map JSON.
  factory BehaviorStylePatch.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'Le style d’un comportement setStyle doit être un objet JSON.',
      );
    }
    double? readDouble(String key) {
      final value = raw[key];
      if (value == null) return null;
      if (value is! num) {
        throw FormatException('Le champ "$key" doit être numérique.');
      }
      return value.toDouble();
    }

    final rawBg = raw.containsKey('backgroundColor')
        ? raw['backgroundColor']
        : raw['color'];
    final rawFg = raw.containsKey('foregroundColor')
        ? raw['foregroundColor']
        : raw['textColor'];
    final rawNamed = raw['namedState'];
    if (rawNamed != null && rawNamed is! String) {
      throw const FormatException(
        'Le champ "namedState" doit être une chaîne de caractères.',
      );
    }

    final patch = BehaviorStylePatch(
      backgroundColor: JsonColor.parseNullable(rawBg, 'backgroundColor'),
      foregroundColor: JsonColor.parseNullable(rawFg, 'foregroundColor'),
      borderColor: JsonColor.parseNullable(raw['borderColor'], 'borderColor'),
      borderWidth: readDouble('borderWidth'),
      radius: readDouble('radius'),
      opacity: readDouble('opacity'),
      elevation: readDouble('elevation'),
      fontSize: readDouble('fontSize'),
      fontWeight: JsonReader.readFontWeight(
        raw,
        null,
        errorMessage: 'Graisse de police invalide dans setStyle.',
      ),
      namedState: rawNamed as String?,
      fill: raw['fill'] == null ? null : ContainerFill.fromJson(raw['fill']),
      shadow: raw['shadow'] == null
          ? null
          : ShadowSpec.fromJson(raw['shadow'], 'shadow'),
      neon: raw['neon'] == null ? null : NeonStyle.fromJson(raw['neon']),
    );
    patch.validate();
    return patch;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BehaviorStylePatch &&
          other.backgroundColor == backgroundColor &&
          other.foregroundColor == foregroundColor &&
          other.borderColor == borderColor &&
          other.borderWidth == borderWidth &&
          other.radius == radius &&
          other.opacity == opacity &&
          other.elevation == elevation &&
          other.fontSize == fontSize &&
          other.fontWeight == fontWeight &&
          other.namedState == namedState &&
          other.fill == fill &&
          other.shadow == shadow &&
          other.neon == neon;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    foregroundColor,
    borderColor,
    borderWidth,
    radius,
    opacity,
    elevation,
    fontSize,
    fontWeight,
    namedState,
    fill,
    shadow,
    neon,
  );
}
