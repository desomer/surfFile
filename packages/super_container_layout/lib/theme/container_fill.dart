/// Modèle de remplissage de surface ([ContainerFill]) : couleur unie, dégradé et image de fond.
///
/// Supporte les dégradés `linear`, `radial` et `sweep` ([FillType]) ainsi que
/// les images/SVG (URL, Data URI, Base64) avec ajustement `BoxFit` et opacité.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../models/json_syntax.dart';
import '../models/json_text_binding.dart';
import 'theme_color.dart';

/// Type de remplissage d'une surface (`solid`, `linear`, `radial` ou `sweep`).
enum FillType { solid, linear, radial, sweep }

/// Spécification immuable du remplissage de fond (dégradé et/ou image) d'un [ContainerStyle].
@immutable
class ContainerFill {
  const ContainerFill({
    this.type = FillType.solid,
    this.start = const Color(0xFF5268D9),
    this.end = const Color(0xFFB794F4),
    this.angle = 45,
    this.radius = .8,
    this.imageUrl = '',
    this.imageBinding,
    this.imageFit = BoxFit.cover,
    this.imageOpacity = 1,
  });

  final FillType type;
  final Color start;
  final Color end;
  final double angle;
  final double radius;
  final String imageUrl;
  final JsonTextBinding? imageBinding;
  final BoxFit imageFit;
  final double imageOpacity;

  bool get hasImage => imageUrl.trim().isNotEmpty || imageBinding != null;

  ContainerFill copyWith({
    FillType? type,
    Color? start,
    bool resetStart = false,
    Color? end,
    bool resetEnd = false,
    double? angle,
    double? radius,
    String? imageUrl,
    JsonTextBinding? imageBinding,
    bool clearImageBinding = false,
    BoxFit? imageFit,
    double? imageOpacity,
  }) => ContainerFill(
    type: type ?? this.type,
    start: resetStart ? const Color(0xFF5268D9) : start ?? this.start,
    end: resetEnd ? const Color(0xFFB794F4) : end ?? this.end,
    angle: angle ?? this.angle,
    radius: radius ?? this.radius,
    imageUrl: imageUrl ?? this.imageUrl,
    imageBinding: clearImageBinding ? null : imageBinding ?? this.imageBinding,
    imageFit: imageFit ?? this.imageFit,
    imageOpacity: imageOpacity ?? this.imageOpacity,
  );

  Gradient? gradient({double opacity = 1, ColorScheme? colorScheme}) {
    final start = colorScheme == null
        ? this.start
        : resolveThemeColor(this.start, colorScheme);
    final end = colorScheme == null
        ? this.end
        : resolveThemeColor(this.end, colorScheme);
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
    'start': JsonColor.toJson(start),
    'end': JsonColor.toJson(end),
    'angle': angle,
    'radius': radius,
    if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
    if (imageBinding != null) 'imageBinding': imageBinding!.toJson(),
    if (imageFit != BoxFit.cover) 'imageFit': imageFit.name,
    if (imageOpacity != 1) 'imageOpacity': imageOpacity,
  };

  Map<String, Object> toCompactJson() => {
    'type': type.name,
    'start': JsonColor.toHex(start),
    'end': JsonColor.toHex(end),
    if (angle != 45) 'angle': angle,
    if (radius != .8) 'radius': radius,
    if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
    if (imageBinding != null) 'imageBinding': imageBinding!.toCompactJson(),
    if (imageFit != BoxFit.cover) 'imageFit': imageFit.name,
    if (imageOpacity != 1) 'imageOpacity': imageOpacity,
  };

  static ContainerFill fromJson(
    Object? value, {
    ContainerFill fallback = const ContainerFill(),
  }) {
    if (value == null) return fallback;
    if (value is! Map) throw const FormatException('Style de fond invalide.');
    final type = switch (value['type'] ?? fallback.type.name) {
      'solid' => FillType.solid,
      'linear' => FillType.linear,
      'radial' => FillType.radial,
      'sweep' => FillType.sweep,
      _ => throw const FormatException('Type de dégradé invalide.'),
    };
    Color color(String key, Color defaultColor) {
      if (!value.containsKey(key) || value[key] == null) return defaultColor;
      try {
        return JsonColor.parse(value[key], key);
      } on FormatException {
        throw FormatException('Couleur de dégradé invalide : $key.');
      }
    }

    double number(String key, double min, double max, double defaultVal) {
      final number = value[key] ?? defaultVal;
      if (number is! num || !number.isFinite || number < min || number > max) {
        throw FormatException('Paramètre de dégradé invalide : $key.');
      }
      return number.toDouble();
    }

    final rawImageUrl = value['imageUrl'] ?? fallback.imageUrl;
    if (rawImageUrl is! String) {
      throw const FormatException('URL d’image de fond invalide.');
    }
    final imageBinding = value.containsKey('imageBinding')
        ? (value['imageBinding'] == null
              ? null
              : JsonTextBinding.fromJson(value['imageBinding']))
        : fallback.imageBinding;
    final rawImageFit = value['imageFit'] ?? fallback.imageFit.name;
    final imageFit = rawImageFit is String
        ? BoxFit.values.where((fit) => fit.name == rawImageFit).firstOrNull
        : null;
    if (imageFit == null) {
      throw const FormatException('Mode d’ajustement d’image invalide.');
    }

    return ContainerFill(
      type: type,
      start: color('start', fallback.start),
      end: color('end', fallback.end),
      angle: number('angle', 0, 360, fallback.angle),
      radius: number('radius', .1, double.infinity, fallback.radius),
      imageUrl: rawImageUrl,
      imageBinding: imageBinding,
      imageFit: imageFit,
      imageOpacity: number('imageOpacity', 0, 1, fallback.imageOpacity),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContainerFill &&
          other.type == type &&
          JsonColor.toJson(other.start) == JsonColor.toJson(start) &&
          JsonColor.toJson(other.end) == JsonColor.toJson(end) &&
          other.angle == angle &&
          other.radius == radius &&
          other.imageUrl == imageUrl &&
          other.imageBinding == imageBinding &&
          other.imageFit == imageFit &&
          other.imageOpacity == imageOpacity);

  @override
  int get hashCode => Object.hash(
    type,
    JsonColor.toJson(start),
    JsonColor.toJson(end),
    angle,
    radius,
    imageUrl,
    imageBinding,
    imageFit,
    imageOpacity,
  );
}
