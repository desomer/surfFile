import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/theme/disk_gauge_style.dart';


/// Jauge d'occupation d'un disque : anneau, compteur ou barre, avec dégradé,
/// halo néon (pulsant en alerte) et remplissage animé.
class DiskGauge extends StatefulWidget {
  const DiskGauge({
    required this.value,
    required this.style,
    required this.fillColor,
    required this.alertColor,
    required this.trackColor,
    required this.foreground,
    this.revision = 0,
    super.key,
  });

  /// Occupation de 0 à 1 ; `null` si indisponible.
  final double? value;
  final DiskGaugeStyle style;
  final Color fillColor;
  final Color alertColor;
  final Color trackColor;
  final Color foreground;

  /// Change à chaque actualisation pour rejouer le remplissage.
  final int revision;

  bool get alert => value != null && value! >= style.alertThreshold;

  @override
  State<DiskGauge> createState() => _DiskGaugeState();
}

class _DiskGaugeState extends State<DiskGauge> with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(vsync: this);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  double _from = 0;
  bool _started = false;

  double get _target => widget.value ?? 0;

  double get _current {
    final t = Curves.easeOutCubic.transform(_fill.value);
    return _from + (_target - _from) * t;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _play(from: 0);
    }
    _syncPulse();
  }

  @override
  void didUpdateWidget(DiskGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _play(from: 0);
    } else if (oldWidget.value != widget.value) {
      _play(from: _currentFor(oldWidget));
    } else if (oldWidget.style.animate != widget.style.animate ||
        oldWidget.style.animationMs != widget.style.animationMs) {
      _play(from: 0);
    }
    _syncPulse();
  }

  double _currentFor(DiskGauge old) {
    final t = Curves.easeOutCubic.transform(_fill.value);
    return _from + ((old.value ?? 0) - _from) * t;
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _play({required double from}) {
    final ms = widget.style.animationMs.round();
    if (!widget.style.animate || ms == 0 || _reduceMotion) {
      _from = _target;
      _fill.value = 1;
      return;
    }
    _from = from;
    _fill.duration = Duration(milliseconds: ms);
    _fill.forward(from: 0);
  }

  void _syncPulse() {
    final pulse =
        widget.alert &&
        widget.style.alertPulse &&
        widget.style.trackNeon.enabled &&
        !_reduceMotion;
    if (pulse && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!pulse && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final alert = widget.alert;
    final color = alert ? widget.alertColor : widget.fillColor;
    final neonColor = alert
        ? widget.alertColor
        : style.trackNeon.color ?? color;
    final percentage = widget.value == null
        ? '—'
        : '${(widget.value! * 100).round()} %';
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_fill, _pulse]),
        builder: (context, _) {
          final pulse = _pulse.isAnimating
              ? .45 + .55 * Curves.easeInOut.transform(_pulse.value)
              : 1.0;
          final glow = style.trackNeon.enabled
              ? style.trackNeon.intensity * pulse
              : 0.0;
          final label = Text(
            percentage,
            key: const ValueKey('disk-gauge-percent'),
            style: TextStyle(
              color: widget.foreground,
              fontSize: style.percentSize,
              fontWeight: style.fontWeight,
              shadows: style.labelNeon
                  ? [
                      for (final blur in const [4.0, 10.0])
                        Shadow(
                          color: neonColor.withValues(
                            alpha: (.5 + .3 * pulse).clamp(0, 1),
                          ),
                          blurRadius:
                              blur *
                              (style.trackNeon.enabled
                                  ? style.trackNeon.intensity.clamp(.4, 3)
                                  : 1),
                        ),
                    ]
                  : null,
            ),
          );
          final painter = DiskGaugePainter(
            value: _current,
            style: style,
            fillColor: color,
            gradient: alert ? const [] : style.gradient,
            trackColor: widget.trackColor,
            neonColor: neonColor,
            glow: glow,
          );
          return switch (style.shape) {
            DiskGaugeShape.ring => SizedBox.square(
              dimension: style.size,
              child: CustomPaint(
                painter: painter,
                child: Center(child: label),
              ),
            ),
            DiskGaugeShape.meter => SizedBox(
              width: style.size,
              height: style.size * .82,
              child: CustomPaint(
                painter: painter,
                child: Align(alignment: const Alignment(0, .35), child: label),
              ),
            ),
            DiskGaugeShape.bar => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerRight, child: label),
                const SizedBox(height: 4),
                SizedBox(
                  height: style.thickness + 8,
                  child: CustomPaint(painter: painter),
                ),
              ],
            ),
          };
        },
      ),
    );
  }
}

class DiskGaugePainter extends CustomPainter {
  const DiskGaugePainter({
    required this.value,
    required this.style,
    required this.fillColor,
    required this.gradient,
    required this.trackColor,
    required this.neonColor,
    required this.glow,
  });

  final double value;
  final DiskGaugeStyle style;
  final Color fillColor;
  final List<Color> gradient;
  final Color trackColor;
  final Color neonColor;

  /// Intensité du halo (0 : aucun), pulsation comprise.
  final double glow;

  static const _meterSweep = 240 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final thickness = style.thickness;
    final cap = style.roundCaps ? StrokeCap.round : StrokeCap.butt;
    final fraction = value.clamp(0.0, 1.0);
    Paint stroke(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = cap;

    if (style.shape == DiskGaugeShape.bar) {
      final y = size.height / 2;
      final inset = style.roundCaps ? thickness / 2 : 0.0;
      final start = Offset(inset, y);
      final end = Offset(size.width - inset, y);
      canvas.drawLine(start, end, stroke(trackColor));
      if (fraction <= 0) return;
      final tip = Offset.lerp(start, end, fraction)!;
      final shader = gradient.length >= 2
          ? LinearGradient(colors: gradient)
                .createShader(start & Size(end.dx - start.dx, 1))
          : null;
      _drawGlow(canvas, (paint) => canvas.drawLine(start, tip, paint), shader);
      canvas.drawLine(start, tip, stroke(fillColor)..shader = shader);
      return;
    }

    final meter = style.shape == DiskGaugeShape.meter;
    final diameter = math.min(
      size.width,
      meter ? size.height / .82 : size.height,
    );
    final radius = (diameter - thickness) / 2;
    final center = Offset(
      size.width / 2,
      meter ? diameter / 2 : size.height / 2,
    );
    final total = meter ? _meterSweep : 2 * math.pi;
    final startAngle = meter
        ? math.pi / 2 + (2 * math.pi - _meterSweep) / 2
        : style.start.degrees * math.pi / 180;
    final direction = meter || style.clockwise ? 1.0 : -1.0;

    // Repère tourné vers le départ (et retourné en sens antihoraire) : les arcs
    // et le dégradé partent tous de l'angle 0.
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(startAngle);
    if (direction < 0) canvas.scale(1, -1);
    final rect = Rect.fromCircle(center: Offset.zero, radius: radius);
    canvas.drawArc(rect, 0, total, false, stroke(trackColor));
    if (fraction > 0) {
      final sweep = total * fraction;
      final shader = gradient.length >= 2
          ? SweepGradient(endAngle: total, colors: gradient).createShader(rect)
          : null;
      _drawGlow(
        canvas,
        (paint) => canvas.drawArc(rect, 0, sweep, false, paint),
        shader,
      );
      canvas.drawArc(rect, 0, sweep, false, stroke(fillColor)..shader = shader);
    }
    canvas.restore();
  }

  void _drawGlow(Canvas canvas, void Function(Paint) draw, Shader? shader) {
    if (glow <= 0) return;
    for (final (width, blur, alpha) in const [
      (2.6, 9.0, .55),
      (1.4, 3.5, .8),
    ]) {
      draw(
        Paint()
          ..color = neonColor.withValues(alpha: (alpha * glow).clamp(0, 1))
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.thickness * width
          ..strokeCap = style.roundCaps ? StrokeCap.round : StrokeCap.butt
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            blur * glow.clamp(.3, 2),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(DiskGaugePainter old) =>
      old.value != value ||
      old.style != style ||
      old.fillColor != fillColor ||
      old.trackColor != trackColor ||
      old.neonColor != neonColor ||
      old.glow != glow ||
      !listEquals(old.gradient, gradient);
}
