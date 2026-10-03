import 'package:material_ui/material_ui.dart';

import 'container_fill.dart';
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
  });

  final Color? color;
  final ContainerFill fill;
  final double radius;
  final double borderWidth;
  final Color? borderColor;
  final double elevation;
  final double shadowOpacity;
  final NeonStyle? neon;

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
  }) =>
      ContainerStyle(
        color: resetColor ? null : color ?? this.color,
        fill: fill ?? this.fill,
        radius: radius ?? this.radius,
        borderWidth: borderWidth ?? this.borderWidth,
        borderColor: resetBorderColor ? null : borderColor ?? this.borderColor,
        elevation: elevation ?? this.elevation,
        shadowOpacity: shadowOpacity ?? this.shadowOpacity,
        neon: neon ?? this.neon,
      );

  Color? get foreground => fill.type != FillType.solid
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
      };

  static ContainerStyle fromJson(Object? value,
      {ContainerStyle fallback = const ContainerStyle()}) {
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
    double number(String key, double min, double max) {
      final number = value[key];
      if (number is! num || !number.isFinite || number < min || number > max) {
        throw FormatException('Paramètre de conteneur invalide : $key.');
      }
      return number.toDouble();
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
    );
  }
}
