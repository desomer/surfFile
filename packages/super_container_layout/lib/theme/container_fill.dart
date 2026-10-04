import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

enum FillType { solid, linear, radial, sweep }

@immutable
class ContainerFill {
  const ContainerFill({
    this.type = FillType.solid,
    this.start = const Color(0xFF5268D9),
    this.end = const Color(0xFFB794F4),
    this.angle = 45,
    this.radius = .8,
  });

  final FillType type;
  final Color start;
  final Color end;
  final double angle;
  final double radius;

  ContainerFill copyWith({
    FillType? type,
    Color? start,
    Color? end,
    double? angle,
    double? radius,
  }) => ContainerFill(
    type: type ?? this.type,
    start: start ?? this.start,
    end: end ?? this.end,
    angle: angle ?? this.angle,
    radius: radius ?? this.radius,
  );

  Gradient? gradient({double opacity = 1}) {
    final colors = [
      start.withValues(alpha: start.a * opacity),
      end.withValues(alpha: end.a * opacity),
    ];
    final radians = angle * math.pi / 180;
    return switch (type) {
      FillType.solid => null,
      FillType.linear => LinearGradient(
        begin: Alignment(-math.cos(radians), -math.sin(radians)),
        end: Alignment(math.cos(radians), math.sin(radians)),
        colors: colors,
      ),
      FillType.radial => RadialGradient(colors: colors, radius: radius),
      FillType.sweep => SweepGradient(
        colors: colors,
        transform: GradientRotation(radians),
      ),
    };
  }

  Map<String, Object> toJson() => {
    'type': type.name,
    'start': start.toARGB32(),
    'end': end.toARGB32(),
    'angle': angle,
    'radius': radius,
  };

  static ContainerFill fromJson(Object? value) {
    if (value == null) return const ContainerFill();
    if (value is! Map) throw const FormatException('Style de fond invalide.');
    final type = switch (value['type']) {
      'solid' => FillType.solid,
      'linear' => FillType.linear,
      'radial' => FillType.radial,
      'sweep' => FillType.sweep,
      _ => throw const FormatException('Type de dégradé invalide.'),
    };
    Color color(String key) {
      final color = value[key];
      if (color is! int || color < 0 || color > 0xFFFFFFFF) {
        throw FormatException('Couleur de dégradé invalide : $key.');
      }
      return Color(color);
    }

    double number(String key, double min, double max) {
      final number = value[key];
      if (number is! num || !number.isFinite || number < min || number > max) {
        throw FormatException('Paramètre de dégradé invalide : $key.');
      }
      return number.toDouble();
    }

    return ContainerFill(
      type: type,
      start: color('start'),
      end: color('end'),
      angle: number('angle', 0, 360),
      radius: number('radius', .1, 2),
    );
  }
}
