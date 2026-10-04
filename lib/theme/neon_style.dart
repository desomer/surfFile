import 'package:material_ui/material_ui.dart';

@immutable
class NeonStyle {
  static const maxIntensity = 3.0;

  const NeonStyle({this.enabled = false, this.color, this.intensity = .6});

  final bool enabled;
  final Color? color;
  final double intensity;

  NeonStyle copyWith({
    bool? enabled,
    Color? color,
    bool resetColor = false,
    double? intensity,
  }) => NeonStyle(
    enabled: enabled ?? this.enabled,
    color: resetColor ? null : color ?? this.color,
    intensity: intensity ?? this.intensity,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'color': color?.toARGB32(),
    'intensity': intensity,
  };

  static NeonStyle fromJson(Object? value) {
    if (value == null) return const NeonStyle();
    if (value is! Map) {
      throw const FormatException('Style néon invalide.');
    }
    final enabled = value['enabled'];
    final color = value['color'];
    final intensity = value['intensity'];
    if (enabled is! bool ||
        (color != null && (color is! int || color < 0 || color > 0xFFFFFFFF)) ||
        intensity is! num ||
        !intensity.isFinite ||
        intensity < 0 ||
        intensity > maxIntensity) {
      throw const FormatException('Paramètres néon invalides.');
    }
    return NeonStyle(
      enabled: enabled,
      color: color == null ? null : Color(color as int),
      intensity: intensity.toDouble(),
    );
  }
}
