/// Configuration visuelle ([ScrollbarStyleConfig]) des barres de défilement d'une zone.
///
/// Contrôle l'épaisseur, le rayon, les marges, la visibilité de la piste/curseur
/// et les couleurs appliquées par [ZoneScrollableViewport].
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show Axis, Color, ScrollbarOrientation;

import 'json_syntax.dart';

/// Position / côté d'affichage de la barre de défilement d'une zone.
enum ScrollbarSide {
  auto('Automatique'),
  start('Début (Gauche / Haut)'),
  end('Fin (Droite / Bas)');

  const ScrollbarSide(this.label);

  final String label;

  String labelForAxis(Axis axis) => switch ((this, axis)) {
    (ScrollbarSide.auto, _) => 'Automatique',
    (ScrollbarSide.start, Axis.vertical) => 'Gauche',
    (ScrollbarSide.end, Axis.vertical) => 'Droite',
    (ScrollbarSide.start, Axis.horizontal) => 'Haut',
    (ScrollbarSide.end, Axis.horizontal) => 'Bas',
  };

  ScrollbarOrientation? resolveOrientation(Axis axis) => switch ((this, axis)) {
    (ScrollbarSide.auto, _) => null,
    (ScrollbarSide.start, Axis.vertical) => ScrollbarOrientation.left,
    (ScrollbarSide.end, Axis.vertical) => ScrollbarOrientation.right,
    (ScrollbarSide.start, Axis.horizontal) => ScrollbarOrientation.top,
    (ScrollbarSide.end, Axis.horizontal) => ScrollbarOrientation.bottom,
  };

  static ScrollbarSide fromJson(Object? value) => switch (value) {
    null || 'auto' => ScrollbarSide.auto,
    'start' || 'left' || 'top' => ScrollbarSide.start,
    'end' || 'right' || 'bottom' => ScrollbarSide.end,
    _ => throw FormatException(
      'Position de barre de défilement invalide : $value.',
    ),
  };
}

/// Configuration immuable et sérialisable en JSON du style d'une `ScrollBar` de zone.
@immutable
class ScrollbarStyleConfig {
  static const double minThickness = 2.0;
  static const double maxThickness = 24.0;
  static const double defaultThickness = 8.0;

  static const double maxRadius = 24.0;
  static const double defaultRadius = 4.0;

  static const double maxMainAxisMargin = 48.0;
  static const double maxCrossAxisMargin = 24.0;

  const ScrollbarStyleConfig({
    this.thumbVisibility = true,
    this.trackVisibility = false,
    this.interactive = true,
    this.thickness = defaultThickness,
    this.radius = defaultRadius,
    this.mainAxisMargin = 0,
    this.crossAxisMargin = 0,
    this.thumbColor,
    this.trackColor,
    this.trackBorderColor,
    this.side = ScrollbarSide.auto,
  }) : assert(thickness >= minThickness && thickness < double.infinity),
       assert(radius >= 0 && radius < double.infinity),
       assert(mainAxisMargin >= 0 && mainAxisMargin < double.infinity),
       assert(crossAxisMargin >= 0 && crossAxisMargin < double.infinity);

  /// Si `true` (défaut), le curseur reste visible en permanence dès que le
  /// contenu déborde. Si `false`, il n'apparaît que pendant le défilement.
  final bool thumbVisibility;

  /// Affiche ou masque la piste (`track`) derrière le curseur.
  final bool trackVisibility;

  /// Autorise le glisser du curseur à la souris ou au doigt.
  final bool interactive;

  /// Épaisseur en pixels (minimum `2`, slider `2`..`24`, sans plafond de saisie).
  final double thickness;

  /// Rayon en pixels (minimum `0`, slider `0`..`24`, sans plafond de saisie).
  final double radius;

  /// Marge aux extrémités (minimum `0`, slider `0`..`48`, sans plafond de saisie).
  final double mainAxisMargin;

  /// Marge latérale (minimum `0`, slider `0`..`24`, sans plafond de saisie).
  final double crossAxisMargin;

  /// Couleur personnalisée du curseur (`null` utilise la couleur du thème).
  final Color? thumbColor;

  /// Couleur personnalisée de la piste (`null` utilise la couleur du thème).
  final Color? trackColor;

  /// Couleur personnalisée de la bordure de piste (`null` utilise celle du thème).
  final Color? trackBorderColor;

  /// Côté de la zone où s'affiche la barre (`auto`, `start`, `end`).
  final ScrollbarSide side;

  bool get isDefault =>
      thumbVisibility &&
      !trackVisibility &&
      interactive &&
      thickness == defaultThickness &&
      radius == defaultRadius &&
      mainAxisMargin == 0 &&
      crossAxisMargin == 0 &&
      thumbColor == null &&
      trackColor == null &&
      trackBorderColor == null &&
      side == ScrollbarSide.auto;

  static String _formatNumber(double value) =>
      value == value.roundToDouble()
          ? '${value.round()}'
          : value.toStringAsFixed(1);

  /// Résumé lisible pour l'aperçu dans l'éditeur de flux de zone et les info-bulles.
  String get summary {
    final parts = <String>[
      '${_formatNumber(thickness)} px',
      'rayon ${_formatNumber(radius)} px',
      thumbVisibility ? 'toujours visible' : 'au défilement',
      if (trackVisibility) 'piste visible',
      if (!interactive) 'non interactive',
      if (side != ScrollbarSide.auto) side.label,
      if (thumbColor != null) JsonColor.toHex(thumbColor!),
    ];
    return parts.join(' • ');
  }

  ScrollbarStyleConfig copyWith({
    bool? thumbVisibility,
    bool? trackVisibility,
    bool? interactive,
    double? thickness,
    double? radius,
    double? mainAxisMargin,
    double? crossAxisMargin,
    Color? thumbColor,
    bool clearThumbColor = false,
    Color? trackColor,
    bool clearTrackColor = false,
    Color? trackBorderColor,
    bool clearTrackBorderColor = false,
    ScrollbarSide? side,
  }) => ScrollbarStyleConfig(
    thumbVisibility: thumbVisibility ?? this.thumbVisibility,
    trackVisibility: trackVisibility ?? this.trackVisibility,
    interactive: interactive ?? this.interactive,
    thickness: (thickness ?? this.thickness).clamp(minThickness, double.infinity),
    radius: (radius ?? this.radius).clamp(0, double.infinity),
    mainAxisMargin: (mainAxisMargin ?? this.mainAxisMargin).clamp(
      0,
      double.infinity,
    ),
    crossAxisMargin: (crossAxisMargin ?? this.crossAxisMargin).clamp(
      0,
      double.infinity,
    ),
    thumbColor: clearThumbColor ? null : (thumbColor ?? this.thumbColor),
    trackColor: clearTrackColor ? null : (trackColor ?? this.trackColor),
    trackBorderColor: clearTrackBorderColor
        ? null
        : (trackBorderColor ?? this.trackBorderColor),
    side: side ?? this.side,
  );

  Map<String, Object?> toJson() => {
    if (!thumbVisibility) 'thumbVisibility': thumbVisibility,
    if (trackVisibility) 'trackVisibility': trackVisibility,
    if (!interactive) 'interactive': interactive,
    if (thickness != defaultThickness) 'thickness': thickness,
    if (radius != defaultRadius) 'radius': radius,
    if (mainAxisMargin != 0) 'mainAxisMargin': mainAxisMargin,
    if (crossAxisMargin != 0) 'crossAxisMargin': crossAxisMargin,
    if (thumbColor != null) 'thumbColor': JsonColor.toHex(thumbColor!),
    if (trackColor != null) 'trackColor': JsonColor.toHex(trackColor!),
    if (trackBorderColor != null)
      'trackBorderColor': JsonColor.toHex(trackBorderColor!),
    if (side != ScrollbarSide.auto) 'side': side.name,
  };

  factory ScrollbarStyleConfig.fromJson(Object? value) {
    if (value == null) return const ScrollbarStyleConfig();
    if (value is ScrollbarStyleConfig) return value;
    if (value is! Map) {
      throw const FormatException(
        'Style de barre de défilement invalide.',
      );
    }

    bool readBool(String key, bool fallback) {
      final raw = value[key];
      if (raw == null) return fallback;
      if (raw is! bool) {
        throw FormatException('Valeur invalide pour "scrollbarStyle.$key".');
      }
      return raw;
    }

    double readNumber(
      String key,
      double min,
      double max,
      double fallback,
    ) {
      final raw = value[key];
      if (raw == null) return fallback;
      if (raw is! num || !raw.isFinite || raw < min || raw > max) {
        throw FormatException('Valeur invalide pour "scrollbarStyle.$key".');
      }
      return raw.toDouble();
    }

    return ScrollbarStyleConfig(
      thumbVisibility: readBool('thumbVisibility', true),
      trackVisibility: readBool('trackVisibility', false),
      interactive: readBool('interactive', true),
      thickness: readNumber(
        'thickness',
        minThickness,
        double.infinity,
        defaultThickness,
      ),
      radius: readNumber('radius', 0, double.infinity, defaultRadius),
      mainAxisMargin: readNumber('mainAxisMargin', 0, double.infinity, 0),
      crossAxisMargin: readNumber('crossAxisMargin', 0, double.infinity, 0),
      thumbColor: JsonColor.parseNullable(
        value['thumbColor'],
        'scrollbarStyle.thumbColor',
      ),
      trackColor: JsonColor.parseNullable(
        value['trackColor'],
        'scrollbarStyle.trackColor',
      ),
      trackBorderColor: JsonColor.parseNullable(
        value['trackBorderColor'],
        'scrollbarStyle.trackBorderColor',
      ),
      side: ScrollbarSide.fromJson(value['side'] ?? value['orientation']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScrollbarStyleConfig &&
      other.thumbVisibility == thumbVisibility &&
      other.trackVisibility == trackVisibility &&
      other.interactive == interactive &&
      other.thickness == thickness &&
      other.radius == radius &&
      other.mainAxisMargin == mainAxisMargin &&
      other.crossAxisMargin == crossAxisMargin &&
      other.thumbColor == thumbColor &&
      other.trackColor == trackColor &&
      other.trackBorderColor == trackBorderColor &&
      other.side == side;

  @override
  int get hashCode => Object.hash(
    thumbVisibility,
    trackVisibility,
    interactive,
    thickness,
    radius,
    mainAxisMargin,
    crossAxisMargin,
    thumbColor,
    trackColor,
    trackBorderColor,
    side,
  );
}
