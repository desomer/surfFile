import 'package:material_ui/material_ui.dart';

import '../theme/style_extras.dart' show Quad;
import 'json_syntax.dart';

/// Type de géométrie Flutter [ShapeBorder] utilisable sur un composant natif.
enum NativeShapeKind {
  rounded('Coins arrondis (Rounded)'),
  continuous('Courbe continue (Squircle)'),
  beveled('Coins biseautés (Beveled)'),
  stadium('Pilule (Stadium)'),
  linear('Trait linéaire (LinearBorder)');

  const NativeShapeKind(this.label);

  final String label;

  bool get supportsCornerRadius =>
      this == NativeShapeKind.rounded ||
      this == NativeShapeKind.continuous ||
      this == NativeShapeKind.beveled;

  static NativeShapeKind fromJson(Object? value) => switch (value) {
    'rounded' || 'roundedRectangle' => NativeShapeKind.rounded,
    'continuous' ||
    'continuousRectangle' ||
    'squircle' => NativeShapeKind.continuous,
    'beveled' || 'beveledRectangle' => NativeShapeKind.beveled,
    'stadium' || 'pill' => NativeShapeKind.stadium,
    'linear' || 'linearBorder' => NativeShapeKind.linear,
    _ => throw FormatException('Type de shape invalide : $value'),
  };
}

/// Configuration immuable et sérialisable en JSON d'un [ShapeBorder] Flutter.
@immutable
class NativeShapeConfig {
  const NativeShapeConfig({
    this.kind = NativeShapeKind.rounded,
    this.radius = 0,
    this.radii,
    this.borderWidth = 0,
    this.borderColor,
    this.top = false,
    this.right = false,
    this.bottom = true,
    this.left = false,
  }) : assert(radius >= 0 && radius <= maxRadius),
       assert(borderWidth >= 0 && borderWidth <= maxBorderWidth);

  static const double maxRadius = 64;
  static const double maxBorderWidth = 16;

  final NativeShapeKind kind;

  /// Rayon uniforme des coins (utilisé si [radii] est `null`).
  final double radius;

  /// Rayons indépendants par coin (`[topLeft, topRight, bottomRight, bottomLeft]`).
  final Quad? radii;

  /// Épaisseur de la bordure (`BorderSide.width`).
  final double borderWidth;

  /// Couleur de la bordure (`BorderSide.color`).
  final Color? borderColor;

  /// Côtés actifs lorsque [kind] vaut [NativeShapeKind.linear].
  final bool top;
  final bool right;
  final bool bottom;
  final bool left;

  BorderRadius get borderRadius =>
      radii?.radii ?? BorderRadius.circular(radius);

  BorderSide _borderSide({double fallbackWidth = 0}) {
    final effectiveWidth = borderWidth > 0 ? borderWidth : fallbackWidth;
    if (effectiveWidth <= 0) return BorderSide.none;
    return BorderSide(
      width: effectiveWidth,
      color: borderColor ?? const Color(0xFF000000),
    );
  }

  /// Construit le [ShapeBorder] Flutter correspondant.
  ShapeBorder toShapeBorder() => switch (kind) {
    NativeShapeKind.rounded => RoundedRectangleBorder(
      borderRadius: borderRadius,
      side: _borderSide(),
    ),
    NativeShapeKind.continuous => ContinuousRectangleBorder(
      borderRadius: borderRadius,
      side: _borderSide(),
    ),
    NativeShapeKind.beveled => BeveledRectangleBorder(
      borderRadius: borderRadius,
      side: _borderSide(),
    ),
    NativeShapeKind.stadium => StadiumBorder(side: _borderSide()),
    NativeShapeKind.linear => LinearBorder(
      side: _borderSide(fallbackWidth: 1),
      top: top ? const LinearBorderEdge() : null,
      bottom: bottom ? const LinearBorderEdge() : null,
      start: left ? const LinearBorderEdge() : null,
      end: right ? const LinearBorderEdge() : null,
    ),
  };

  /// Résumé lisible pour l'aperçu dans la liste des propriétés.
  String get summary {
    final parts = <String>[kind.label];
    if (kind.supportsCornerRadius) {
      if (radii != null) {
        parts.add(
          '[${radii!.top.toInt()}, ${radii!.right.toInt()}, '
          '${radii!.bottom.toInt()}, ${radii!.left.toInt()}] px',
        );
      } else if (radius > 0) {
        parts.add('${radius.toInt()} px');
      }
    }
    if (borderWidth > 0) {
      parts.add('bordure ${borderWidth.toStringAsFixed(1)} px');
    }
    return parts.join(' • ');
  }

  NativeShapeConfig copyWith({
    NativeShapeKind? kind,
    double? radius,
    Quad? radii,
    bool clearRadii = false,
    double? borderWidth,
    Color? borderColor,
    bool clearBorderColor = false,
    bool? top,
    bool? right,
    bool? bottom,
    bool? left,
  }) => NativeShapeConfig(
    kind: kind ?? this.kind,
    radius: (radius ?? this.radius).clamp(0, maxRadius),
    radii: clearRadii ? null : (radii ?? this.radii),
    borderWidth: (borderWidth ?? this.borderWidth).clamp(0, maxBorderWidth),
    borderColor: clearBorderColor ? null : (borderColor ?? this.borderColor),
    top: top ?? this.top,
    right: right ?? this.right,
    bottom: bottom ?? this.bottom,
    left: left ?? this.left,
  );

  Map<String, Object> toJson() => {
    'kind': kind.name,
    if (kind.supportsCornerRadius && radii == null && radius > 0)
      'radius': radius,
    if (kind.supportsCornerRadius && radii != null) 'radii': radii!.toJson(),
    if (borderWidth > 0) 'borderWidth': borderWidth,
    if (borderColor != null) 'borderColor': JsonColor.toHex(borderColor!),
    if (kind == NativeShapeKind.linear) ...{
      'top': top,
      'right': right,
      'bottom': bottom,
      'left': left,
    },
  };

  factory NativeShapeConfig.fromJson(Object? raw) {
    if (raw is NativeShapeConfig) return raw;
    if (raw is num && raw.isFinite) {
      return NativeShapeConfig(radius: raw.toDouble().clamp(0, maxRadius));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return NativeShapeConfig(kind: NativeShapeKind.fromJson(raw.trim()));
    }
    if (raw is List) {
      return NativeShapeConfig(
        radii: Quad.fromJson(raw, 0, maxRadius, 'shape.radii'),
      );
    }
    if (raw is! Map) {
      throw const FormatException('Configuration de shape invalide.');
    }
    final kind = raw['kind'] == null
        ? NativeShapeKind.rounded
        : NativeShapeKind.fromJson(raw['kind']);
    final rawRadius = raw['radius'] ?? 0;
    if (rawRadius is! num || !rawRadius.isFinite) {
      throw const FormatException('Rayon de shape invalide.');
    }
    final radii = raw['radii'] == null
        ? null
        : Quad.fromJson(raw['radii'], 0, maxRadius, 'shape.radii');
    final rawBorderWidth = raw['borderWidth'] ?? 0;
    if (rawBorderWidth is! num || !rawBorderWidth.isFinite) {
      throw const FormatException('Épaisseur de bordure de shape invalide.');
    }
    final borderColor = JsonColor.parseNullable(
      raw['borderColor'],
      'shape.borderColor',
    );
    bool side(String key, bool fallback) {
      final v = raw[key];
      if (v == null) return fallback;
      if (v is! bool) {
        throw FormatException('Côté "$key" de shape invalide.');
      }
      return v;
    }

    return NativeShapeConfig(
      kind: kind,
      radius: rawRadius.toDouble().clamp(0, maxRadius),
      radii: radii,
      borderWidth: rawBorderWidth.toDouble().clamp(0, maxBorderWidth),
      borderColor: borderColor,
      top: side('top', false),
      right: side('right', false),
      bottom: side('bottom', true),
      left: side('left', false),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NativeShapeConfig &&
      other.kind == kind &&
      other.radius == radius &&
      other.radii == radii &&
      other.borderWidth == borderWidth &&
      other.borderColor == borderColor &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(
    kind,
    radius,
    radii,
    borderWidth,
    borderColor,
    top,
    right,
    bottom,
    left,
  );
}
