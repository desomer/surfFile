/// Unités, dimensions, contraintes de taille et helpers de dimensionnement des slots.
library;

import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show EdgeInsets;

import 'json_syntax.dart' show JsonDimension;

/// Unité de mesure d'une dimension de slot (pixels ou pourcentage).
enum SlotSizeUnit { pixels, percent }

/// Référentiel utilisé pour calculer une dimension de slot exprimée en pourcentage.
enum SlotPercentBasis { zone, layout }

/// Dimension typée d'un slot combinant une valeur numérique, une [SlotSizeUnit] et une [SlotPercentBasis].
class SlotDimension {
  const SlotDimension(this.value, this.unit);

  final double value;
  final SlotSizeUnit unit;

  double resolve(double available) =>
      unit == SlotSizeUnit.percent ? available * value / 100 : value;

  static String formatNumber(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  String format() =>
      '${formatNumber(value)} ${unit == SlotSizeUnit.pixels ? 'px' : '%'}';

  Map<String, Object> toJson() => {
    'value': value,
    'unit': unit == SlotSizeUnit.pixels ? 'px' : 'percent',
  };

  static SlotDimension fromJson(Object? value) => JsonDimension.parse(value);

  @override
  bool operator ==(Object other) =>
      other is SlotDimension && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);
}

/// Contraintes de taille, d'ajustement (`fitContent`) et de marges intérieures/extérieures d'un slot.
class SlotSizeConstraints {
  static const maxPadding = 200.0;

  static const Set<String> jsonKeys = {
    'minWidth',
    'minHeight',
    'maxWidth',
    'maxHeight',
    'preferredWidth',
    'preferredHeight',
    'padding',
    'paddingInsets',
    'percentBasis',
    'fitContent',
    'flex',
  };

  /// Retourne `true` si [value] est directement un objet de contraintes de slot
  /// (ex. `{"preferredWidth": "110px", "preferredHeight": "40px"}`) au lieu
  /// d'une `Map<slotId, SlotSizeConstraints>`.
  static bool isDirectConstraintsMap(Object? value) {
    if (value is! Map || value.isEmpty) return false;
    return value.keys.every((key) => key is String && jsonKeys.contains(key)) &&
        value.values.any(
          (entry) =>
              entry is! Map ||
              entry.containsKey('value') ||
              entry.containsKey('unit'),
        );
  }

  /// Lit une `Map<slotId, SlotSizeConstraints>` en tolérant aussi un objet
  /// [SlotSizeConstraints] direct si l'IA l'a placé sans clé de slot.
  static Map<String, SlotSizeConstraints> parseMap(
    Object? raw, {
    Iterable<String> placedIds = const [],
    Map<String, SlotSizeConstraints> fallback = const {},
  }) {
    if (raw == null) return fallback;
    if (raw is! Map) {
      throw const FormatException('Contraintes de taille invalides.');
    }
    if (isDirectConstraintsMap(raw)) {
      final direct = SlotSizeConstraints.fromJson(raw);
      final uniquePlaced = placedIds.toSet();
      if (uniquePlaced.length == 1) {
        return {...fallback, uniquePlaced.single: direct};
      }
      return fallback;
    }
    final result = <String, SlotSizeConstraints>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || key.trim().isEmpty) {
        throw const FormatException('Identifiant de slot invalide.');
      }
      if (entry.value != null) {
        result[key] = SlotSizeConstraints.fromJson(entry.value);
      }
    }
    return result;
  }

  const SlotSizeConstraints({
    this.minWidth,
    this.minHeight,
    this.maxWidth,
    this.maxHeight,
    this.preferredWidth,
    this.preferredHeight,
    this.padding = 0,
    this.paddingInsets,
    this.percentBasis = SlotPercentBasis.zone,
    this.fitContent,
  }) : assert(padding >= 0 && padding < double.infinity);

  final SlotDimension? minWidth;
  final SlotDimension? minHeight;
  final SlotDimension? maxWidth;
  final SlotDimension? maxHeight;
  final SlotDimension? preferredWidth;
  final SlotDimension? preferredHeight;
  final double padding;
  final EdgeInsets? paddingInsets;
  final SlotPercentBasis percentBasis;

  /// `true` pour prendre la taille du contenu (`flex: 0`), `false` pour
  /// remplir l'espace disponible (`flex: 1`), `null` pour suivre la zone.
  final bool? fitContent;

  EdgeInsets get contentPadding => paddingInsets ?? EdgeInsets.all(padding);
  bool get hasPadding => padding != 0 || paddingInsets != null;

  bool get hasSizeConstraints =>
      minWidth != null ||
      minHeight != null ||
      maxWidth != null ||
      maxHeight != null ||
      preferredWidth != null ||
      preferredHeight != null;

  Map<String, Object?> toJson() => {
    'percentBasis': percentBasis.name,
    if (fitContent != null) 'fitContent': fitContent,
    if (padding != 0) 'padding': padding,
    if (paddingInsets != null)
      'paddingInsets': [
        paddingInsets!.top,
        paddingInsets!.right,
        paddingInsets!.bottom,
        paddingInsets!.left,
      ],
    for (final (key, dimension) in [
      ('minWidth', minWidth),
      ('minHeight', minHeight),
      ('maxWidth', maxWidth),
      ('maxHeight', maxHeight),
      ('preferredWidth', preferredWidth),
      ('preferredHeight', preferredHeight),
    ])
      if (dimension != null) key: dimension.toJson(),
  };

  static SlotSizeConstraints fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Contraintes de taille invalides.');
    }
    SlotDimension? dimension(String key) =>
        value.containsKey(key) ? SlotDimension.fromJson(value[key]) : null;
    final basis = switch (value['percentBasis']) {
      null || 'zone' => SlotPercentBasis.zone,
      'layout' => SlotPercentBasis.layout,
      _ => throw const FormatException('Base de pourcentage invalide.'),
    };
    final padding = value['padding'] ?? 0;
    if (padding is! num || !padding.isFinite || padding < 0) {
      throw const FormatException('Marge de slot invalide.');
    }
    final rawPaddingInsets = value['paddingInsets'];
    final paddingInsets = rawPaddingInsets == null
        ? null
        : readSlotPaddingInsets(rawPaddingInsets);
    final bool? fitContent = switch ((value['fitContent'], value['flex'])) {
      (final bool fit, _) => fit,
      (null, 0) => true,
      (null, 1) => false,
      (null, null) => null,
      _ => throw const FormatException(
        'Mode flex/fitContent de slot invalide.',
      ),
    };
    return SlotSizeConstraints(
      minWidth: dimension('minWidth'),
      minHeight: dimension('minHeight'),
      maxWidth: dimension('maxWidth'),
      maxHeight: dimension('maxHeight'),
      preferredWidth: dimension('preferredWidth'),
      preferredHeight: dimension('preferredHeight'),
      padding: padding.toDouble(),
      paddingInsets: paddingInsets,
      percentBasis: basis,
      fitContent: fitContent,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SlotSizeConstraints &&
      other.minWidth == minWidth &&
      other.minHeight == minHeight &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight &&
      other.preferredWidth == preferredWidth &&
      other.preferredHeight == preferredHeight &&
      other.padding == padding &&
      other.paddingInsets == paddingInsets &&
      other.percentBasis == percentBasis &&
      other.fitContent == fitContent;

  @override
  int get hashCode => Object.hash(
    minWidth,
    minHeight,
    maxWidth,
    maxHeight,
    preferredWidth,
    preferredHeight,
    padding,
    paddingInsets,
    percentBasis,
    fitContent,
  );
}

/// Indique si les contraintes ou la taille préférée d'un slot imposent une largeur fixe.
bool hasFixedSlotWidth({
  SlotSizeConstraints? constraints,
  Size? preferredSize,
}) {
  final useLegacy = constraints == null || !constraints.hasSizeConstraints;
  return constraints?.preferredWidth != null ||
      (constraints?.minWidth != null &&
          constraints?.maxWidth != null &&
          constraints!.minWidth == constraints.maxWidth) ||
      (useLegacy && preferredSize != null && preferredSize.width.isFinite);
}

/// Indique si les contraintes ou la taille préférée d'un slot imposent une hauteur fixe.
bool hasFixedSlotHeight({
  SlotSizeConstraints? constraints,
  Size? preferredSize,
}) {
  final useLegacy = constraints == null || !constraints.hasSizeConstraints;
  return constraints?.preferredHeight != null ||
      (constraints?.minHeight != null &&
          constraints?.maxHeight != null &&
          constraints!.minHeight == constraints.maxHeight) ||
      (useLegacy && preferredSize != null && preferredSize.height.isFinite);
}

/// Lit les quatre marges d'un slot ou d'une zone dans l'ordre haut, droite, bas, gauche.
EdgeInsets readSlotPaddingInsets(Object? value) {
  if (value is! List || value.length != 4) {
    throw const FormatException('Marge de slot invalide.');
  }
  final sides = <double>[];
  for (final side in value) {
    if (side is! num || !side.isFinite || side < 0) {
      throw const FormatException('Marge de slot invalide.');
    }
    sides.add(side.toDouble());
  }
  return EdgeInsets.fromLTRB(sides[3], sides[0], sides[1], sides[2]);
}
