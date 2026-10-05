import 'package:material_ui/material_ui.dart';

import 'package:super_container_layout/theme/neon_style.dart';

/// Forme de la jauge d'occupation d'un disque.
enum DiskGaugeShape {
  ring('Anneau'),
  meter('Compteur'),
  bar('Barre');

  const DiskGaugeShape(this.label);
  final String label;
}

/// Point de départ de l'anneau.
enum DiskGaugeStart {
  top('Haut', -90),
  right('Droite', 0),
  bottom('Bas', 90),
  left('Gauche', 180);

  const DiskGaugeStart(this.label, this.degrees);
  final String label;
  final double degrees;
}

/// Apparence des jauges du panneau des disques.
@immutable
class DiskGaugeStyle {
  static const minSize = 40.0;
  static const maxSize = 96.0;
  static const minThickness = 2.0;
  static const maxThickness = 14.0;
  static const maxAnimation = 2000.0;

  const DiskGaugeStyle({
    this.shape = DiskGaugeShape.ring,
    this.size = 62,
    this.thickness = 5,
    this.roundCaps = false,
    this.trackColor,
    this.fillColor,
    this.gradient = const [],
    this.alertColor,
    this.alertThreshold = .9,
    this.start = DiskGaugeStart.top,
    this.clockwise = true,
    this.trackNeon = const NeonStyle(),
    this.alertPulse = false,
    this.labelNeon = false,
    this.animate = true,
    this.animationMs = 700,
    this.percentSize = 12,
    this.percentWeight = 7,
    this.nameSize = 13,
    this.captionSize = 10,
    this.columns = 2,
  });

  final DiskGaugeShape shape;

  /// Diamètre de l'anneau ou du compteur.
  final double size;
  final double thickness;
  final bool roundCaps;

  /// `null` : couleur du texte, très atténuée.
  final Color? trackColor;

  /// `null` : couleur d'accent.
  final Color? fillColor;

  /// Deux ou trois couleurs réparties le long de la piste ; vide : uni.
  final List<Color> gradient;

  /// `null` : couleur d'erreur du thème.
  final Color? alertColor;
  final double alertThreshold;
  final DiskGaugeStart start;
  final bool clockwise;

  /// Halo sur la partie remplie ; couleur `null` : celle du remplissage.
  final NeonStyle trackNeon;

  /// Le halo pulse quand le seuil d'alerte est dépassé.
  final bool alertPulse;

  /// Halo sur le pourcentage.
  final bool labelNeon;
  final bool animate;
  final double animationMs;
  final double percentSize;

  /// 1 à 9 (`FontWeight.values`, w100 à w900).
  final int percentWeight;
  final double nameSize;
  final double captionSize;
  final int columns;

  FontWeight get fontWeight =>
      FontWeight.values[(percentWeight - 1).clamp(0, 8)];

  /// Préréglages proposés dans l'éditeur.
  static const presets = <String, DiskGaugeStyle>{
    'Classique': DiskGaugeStyle(),
    'Néon cyber': DiskGaugeStyle(
      thickness: 6,
      roundCaps: true,
      trackColor: Color(0x2600E5FF),
      fillColor: Color(0xFF00E5FF),
      gradient: [Color(0xFF00E5FF), Color(0xFFFF00E5)],
      alertColor: Color(0xFFFF1744),
      trackNeon: NeonStyle(enabled: true, intensity: 1.2),
      alertPulse: true,
      labelNeon: true,
      percentWeight: 8,
    ),
    'Minimal': DiskGaugeStyle(
      size: 52,
      thickness: 2,
      roundCaps: true,
      percentWeight: 4,
      percentSize: 11,
      nameSize: 12,
    ),
    'Tableau de bord': DiskGaugeStyle(
      shape: DiskGaugeShape.meter,
      size: 76,
      thickness: 9,
      roundCaps: true,
      gradient: [Color(0xFF43A047), Color(0xFFFFB300), Color(0xFFE53935)],
      alertPulse: true,
      percentSize: 15,
      percentWeight: 8,
    ),
  };

  DiskGaugeStyle copyWith({
    DiskGaugeShape? shape,
    double? size,
    double? thickness,
    bool? roundCaps,
    Color? trackColor,
    bool resetTrackColor = false,
    Color? fillColor,
    bool resetFillColor = false,
    List<Color>? gradient,
    Color? alertColor,
    bool resetAlertColor = false,
    double? alertThreshold,
    DiskGaugeStart? start,
    bool? clockwise,
    NeonStyle? trackNeon,
    bool? alertPulse,
    bool? labelNeon,
    bool? animate,
    double? animationMs,
    double? percentSize,
    int? percentWeight,
    double? nameSize,
    double? captionSize,
    int? columns,
  }) => DiskGaugeStyle(
    shape: shape ?? this.shape,
    size: size ?? this.size,
    thickness: thickness ?? this.thickness,
    roundCaps: roundCaps ?? this.roundCaps,
    trackColor: resetTrackColor ? null : trackColor ?? this.trackColor,
    fillColor: resetFillColor ? null : fillColor ?? this.fillColor,
    gradient: gradient ?? this.gradient,
    alertColor: resetAlertColor ? null : alertColor ?? this.alertColor,
    alertThreshold: alertThreshold ?? this.alertThreshold,
    start: start ?? this.start,
    clockwise: clockwise ?? this.clockwise,
    trackNeon: trackNeon ?? this.trackNeon,
    alertPulse: alertPulse ?? this.alertPulse,
    labelNeon: labelNeon ?? this.labelNeon,
    animate: animate ?? this.animate,
    animationMs: animationMs ?? this.animationMs,
    percentSize: percentSize ?? this.percentSize,
    percentWeight: percentWeight ?? this.percentWeight,
    nameSize: nameSize ?? this.nameSize,
    captionSize: captionSize ?? this.captionSize,
    columns: columns ?? this.columns,
  );

  Map<String, Object?> toJson() => {
    'shape': shape.name,
    'size': size,
    'thickness': thickness,
    'roundCaps': roundCaps,
    'trackColor': trackColor?.toARGB32(),
    'fillColor': fillColor?.toARGB32(),
    'gradient': [for (final color in gradient) color.toARGB32()],
    'alertColor': alertColor?.toARGB32(),
    'alertThreshold': alertThreshold,
    'start': start.name,
    'clockwise': clockwise,
    'trackNeon': trackNeon.toJson(),
    'alertPulse': alertPulse,
    'labelNeon': labelNeon,
    'animate': animate,
    'animationMs': animationMs,
    'percentSize': percentSize,
    'percentWeight': percentWeight,
    'nameSize': nameSize,
    'captionSize': captionSize,
    'columns': columns,
  };

  static DiskGaugeStyle fromJson(Object? value) {
    if (value == null) return const DiskGaugeStyle();
    if (value is! Map) {
      throw const FormatException('Style des jauges invalide.');
    }
    const d = DiskGaugeStyle();
    T read<T>(String key, T fallback) {
      final v = value[key];
      if (v == null) return fallback;
      if (v is! T) throw FormatException('Valeur invalide pour "$key".');
      return v;
    }

    double number(String key, double fallback, double min, double max) {
      final v = read<num>(key, fallback);
      if (!v.isFinite || v < min || v > max) {
        throw FormatException('Valeur invalide pour "$key".');
      }
      return v.toDouble();
    }

    int integer(String key, int fallback, int min, int max) {
      final v = read<int>(key, fallback);
      if (v < min || v > max) {
        throw FormatException('Valeur invalide pour "$key".');
      }
      return v;
    }

    Color toColor(Object? v, String key) {
      if (v is! int || v < 0 || v > 0xFFFFFFFF) {
        throw FormatException('Couleur invalide pour "$key".');
      }
      return Color(v);
    }

    Color? color(String key) {
      final v = value[key];
      return v == null ? null : toColor(v, key);
    }

    E choice<E extends Enum>(String key, List<E> values, E fallback) {
      final name = read<String>(key, fallback.name);
      return values.where((e) => e.name == name).firstOrNull ??
          (throw FormatException('Valeur invalide pour "$key".'));
    }

    final gradient = read<List<Object?>>('gradient', const []);
    if (gradient.length > 3) {
      throw const FormatException('Dégradé invalide.');
    }
    return DiskGaugeStyle(
      shape: choice('shape', DiskGaugeShape.values, d.shape),
      size: number('size', d.size, minSize, maxSize),
      thickness: number('thickness', d.thickness, minThickness, maxThickness),
      roundCaps: read('roundCaps', d.roundCaps),
      trackColor: color('trackColor'),
      fillColor: color('fillColor'),
      gradient: [for (final c in gradient) toColor(c, 'gradient')],
      alertColor: color('alertColor'),
      alertThreshold: number('alertThreshold', d.alertThreshold, .5, 1),
      start: choice('start', DiskGaugeStart.values, d.start),
      clockwise: read('clockwise', d.clockwise),
      trackNeon: NeonStyle.fromJson(value['trackNeon']),
      alertPulse: read('alertPulse', d.alertPulse),
      labelNeon: read('labelNeon', d.labelNeon),
      animate: read('animate', d.animate),
      animationMs: number('animationMs', d.animationMs, 0, maxAnimation),
      percentSize: number('percentSize', d.percentSize, 8, 24),
      percentWeight: integer('percentWeight', d.percentWeight, 1, 9),
      nameSize: number('nameSize', d.nameSize, 9, 20),
      captionSize: number('captionSize', d.captionSize, 8, 16),
      columns: integer('columns', d.columns, 1, 3),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiskGaugeStyle && _encoded == other._encoded;

  String get _encoded => toJson().toString();

  @override
  int get hashCode => _encoded.hashCode;
}
