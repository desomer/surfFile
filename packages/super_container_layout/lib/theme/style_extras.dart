import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Quatre valeurs : haut, droite, bas, gauche pour des côtés ; haut-gauche,
/// haut-droite, bas-droite, bas-gauche pour des coins.
@immutable
class Quad {
  const Quad(this.top, this.right, this.bottom, this.left);

  const Quad.all(double value)
    : top = value,
      right = value,
      bottom = value,
      left = value;

  final double top;
  final double right;
  final double bottom;
  final double left;

  bool get uniform => top == right && right == bottom && bottom == left;

  double get max => math.max(math.max(top, right), math.max(bottom, left));

  List<double> get values => [top, right, bottom, left];

  double operator [](int index) => values[index];

  Quad withAt(int index, double value) => Quad(
    index == 0 ? value : top,
    index == 1 ? value : right,
    index == 2 ? value : bottom,
    index == 3 ? value : left,
  );

  EdgeInsets get insets => EdgeInsets.fromLTRB(left, top, right, bottom);

  BorderRadius get radii => BorderRadius.only(
    topLeft: Radius.circular(top),
    topRight: Radius.circular(right),
    bottomRight: Radius.circular(bottom),
    bottomLeft: Radius.circular(left),
  );

  List<double> toJson() => values;

  static Quad fromJson(Object? value, double min, double max, String name) {
    if (value is! List || value.length != 4) {
      throw FormatException('Paramètre de conteneur invalide : $name.');
    }
    final numbers = [
      for (final item in value)
        if (item is num && item.isFinite && item >= min && item <= max)
          item.toDouble()
        else
          throw FormatException('Paramètre de conteneur invalide : $name.'),
    ];
    return Quad(numbers[0], numbers[1], numbers[2], numbers[3]);
  }

  @override
  bool operator ==(Object other) =>
      other is Quad &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}

/// Type de trait d'une bordure.
enum BorderLine {
  solid('Plein'),
  dashed('Tireté'),
  dotted('Pointillé');

  const BorderLine(this.label);

  final String label;
}

/// Motif dessiné par-dessus le fond.
enum SurfacePattern {
  none('Aucun'),
  grain('Grain'),
  lines('Lignes'),
  dots('Points');

  const SurfacePattern(this.label);

  final String label;
}

/// Ombre réglable en détail, portée ou intérieure.
@immutable
class ShadowSpec {
  const ShadowSpec({
    this.enabled = true,
    this.color = const Color(0xFF000000),
    this.opacity = .1,
    this.blur = 16,
    this.spread = 0,
    this.dx = 0,
    this.dy = 8,
  });

  /// Ombre équivalente à une élévation Material.
  factory ShadowSpec.fromElevation(double elevation, double opacity) =>
      ShadowSpec(
        opacity: opacity,
        blur: (elevation * 2).clamp(0, maxBlur).toDouble(),
        dy: elevation / 2,
      );

  static const maxBlur = 48.0;
  static const maxSpread = 32.0;
  static const maxOffset = 32.0;

  final bool enabled;
  final Color color;
  final double opacity;
  final double blur;
  final double spread;
  final double dx;
  final double dy;

  Color get shadowColor => color.withValues(alpha: color.a * opacity);

  BoxShadow toBoxShadow() => BoxShadow(
    color: shadowColor,
    blurRadius: blur,
    spreadRadius: spread,
    offset: Offset(dx, dy),
  );

  ShadowSpec copyWith({
    bool? enabled,
    Color? color,
    double? opacity,
    double? blur,
    double? spread,
    double? dx,
    double? dy,
  }) => ShadowSpec(
    enabled: enabled ?? this.enabled,
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    blur: blur ?? this.blur,
    spread: spread ?? this.spread,
    dx: dx ?? this.dx,
    dy: dy ?? this.dy,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'color': color.toARGB32(),
    'opacity': opacity,
    'blur': blur,
    'spread': spread,
    'dx': dx,
    'dy': dy,
  };

  static ShadowSpec fromJson(Object? value, String name) {
    if (value is! Map) {
      throw FormatException('Paramètre de conteneur invalide : $name.');
    }
    double number(String key, double min, double max, double fallback) {
      final number = value[key] ?? fallback;
      if (number is! num || !number.isFinite || number < min || number > max) {
        throw FormatException('Paramètre de conteneur invalide : $name.$key.');
      }
      return number.toDouble();
    }

    final color = value['color'];
    if (color != null && (color is! int || color < 0 || color > 0xFFFFFFFF)) {
      throw FormatException('Paramètre de conteneur invalide : $name.color.');
    }
    final enabled = value['enabled'];
    if (enabled != null && enabled is! bool) {
      throw FormatException('Paramètre de conteneur invalide : $name.enabled.');
    }
    const d = ShadowSpec();
    return ShadowSpec(
      enabled: enabled as bool? ?? true,
      color: color == null ? d.color : Color(color as int),
      opacity: number('opacity', 0, 1, d.opacity),
      blur: number('blur', 0, maxBlur, d.blur),
      spread: number('spread', -maxSpread, maxSpread, d.spread),
      dx: number('dx', -maxOffset, maxOffset, d.dx),
      dy: number('dy', -maxOffset, maxOffset, d.dy),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShadowSpec &&
      other.enabled == enabled &&
      other.color == color &&
      other.opacity == opacity &&
      other.blur == blur &&
      other.spread == spread &&
      other.dx == dx &&
      other.dy == dy;

  @override
  int get hashCode =>
      Object.hash(enabled, color, opacity, blur, spread, dx, dy);
}

/// Transformation appliquée à la surface (rotation en degrés).
@immutable
class TransformSpec {
  const TransformSpec({
    this.dx = 0,
    this.dy = 0,
    this.rotation = 0,
    this.scale = 1,
  });

  static const maxOffset = 48.0;
  static const minScale = .5;
  static const maxScale = 1.5;

  final double dx;
  final double dy;
  final double rotation;
  final double scale;

  bool get isIdentity => dx == 0 && dy == 0 && rotation == 0 && scale == 1;

  Matrix4 get matrix => Matrix4.identity()
    ..translateByDouble(dx, dy, 0, 1)
    ..rotateZ(rotation * math.pi / 180)
    ..scaleByDouble(scale, scale, 1, 1);

  TransformSpec copyWith({
    double? dx,
    double? dy,
    double? rotation,
    double? scale,
  }) => TransformSpec(
    dx: dx ?? this.dx,
    dy: dy ?? this.dy,
    rotation: rotation ?? this.rotation,
    scale: scale ?? this.scale,
  );

  Map<String, Object?> toJson() => {
    'dx': dx,
    'dy': dy,
    'rotation': rotation,
    'scale': scale,
  };

  static TransformSpec fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'Paramètre de conteneur invalide : transform.',
      );
    }
    double number(String key, double min, double max, double fallback) {
      final number = value[key] ?? fallback;
      if (number is! num || !number.isFinite || number < min || number > max) {
        throw FormatException(
          'Paramètre de conteneur invalide : transform.$key.',
        );
      }
      return number.toDouble();
    }

    return TransformSpec(
      dx: number('dx', -maxOffset, maxOffset, 0),
      dy: number('dy', -maxOffset, maxOffset, 0),
      rotation: number('rotation', -180, 180, 0),
      scale: number('scale', minScale, maxScale, 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TransformSpec &&
      other.dx == dx &&
      other.dy == dy &&
      other.rotation == rotation &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(dx, dy, rotation, scale);
}
