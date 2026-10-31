import 'package:material_ui/material_ui.dart';

import '../models/json_syntax.dart';

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

  Map<String, Object?> toCompactJson() => {
    'enabled': enabled,
    if (color != null) 'color': JsonColor.toHex(color!),
    if (intensity != .6) 'intensity': intensity,
  };

  static NeonStyle fromJson(Object? value) {
    if (value == null) return const NeonStyle();
    if (value is bool) return NeonStyle(enabled: value);
    if (value is! Map) {
      throw const FormatException('Style néon invalide.');
    }
    final enabled = value.containsKey('enabled') ? value['enabled'] : true;
    final rawColor = value['color'];
    final intensity = value.containsKey('intensity') ? value['intensity'] : .6;
    if (enabled is! bool ||
        intensity is! num ||
        !intensity.isFinite ||
        intensity < 0 ||
        intensity > maxIntensity) {
      throw const FormatException('Paramètres néon invalides.');
    }
    final Color? parsedColor;
    try {
      parsedColor = JsonColor.parseNullable(rawColor, 'neon.color');
    } on FormatException {
      throw const FormatException('Paramètres néon invalides.');
    }
    return NeonStyle(
      enabled: enabled,
      color: parsedColor,
      intensity: intensity.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NeonStyle &&
          other.enabled == enabled &&
          other.color?.toARGB32() == color?.toARGB32() &&
          other.intensity == intensity);

  @override
  int get hashCode => Object.hash(enabled, color?.toARGB32(), intensity);
}
