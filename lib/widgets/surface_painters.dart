import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../theme/style_extras.dart';

/// Bordure à côtés d'épaisseurs différentes et/ou au trait tireté ou
/// pointillé, que BoxDecoration ne sait pas dessiner avec des coins arrondis.
class StyleBorderPainter extends CustomPainter {
  const StyleBorderPainter({
    required this.widths,
    required this.color,
    required this.radii,
    this.line = BorderLine.solid,
  });

  final Quad widths;
  final Color color;
  final BorderRadius radii;
  final BorderLine line;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final outer = radii.toRRect(Offset.zero & size);
    final center = size.center(Offset.zero);
    // Chaque côté est dessiné dans le triangle qui le relie au centre, ce qui
    // sépare proprement les angles entre deux épaisseurs.
    final wedges = [
      [Offset.zero, Offset(size.width, 0)],
      [Offset(size.width, 0), Offset(size.width, size.height)],
      [Offset(size.width, size.height), Offset(0, size.height)],
      [Offset(0, size.height), Offset.zero],
    ];
    for (var i = 0; i < 4; i++) {
      final width = widths[i];
      if (width <= 0) continue;
      canvas.save();
      canvas.clipPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(wedges[i][0].dx, wedges[i][0].dy)
          ..lineTo(wedges[i][1].dx, wedges[i][1].dy)
          ..close(),
      );
      final path = Path()..addRRect(outer.deflate(width / 2));
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width;
      switch (line) {
        case BorderLine.solid:
          canvas.drawPath(path, paint);
        case BorderLine.dashed:
          _dash(
            canvas,
            path,
            paint,
            math.max(width * 3, 5),
            math.max(width * 2, 4),
          );
        case BorderLine.dotted:
          paint.strokeCap = StrokeCap.round;
          _dash(canvas, path, paint, .01, width * 2);
      }
      canvas.restore();
    }
  }

  void _dash(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(StyleBorderPainter old) =>
      old.widths != widths ||
      old.color != color ||
      old.radii != radii ||
      old.line != line;
}

/// Motif et ombre intérieure dessinés au-dessus du fond.
class SurfaceOverlayPainter extends CustomPainter {
  const SurfaceOverlayPainter({
    required this.radii,
    required this.pattern,
    required this.patternOpacity,
    required this.ink,
    this.innerShadow,
  });

  final BorderRadius radii;
  final SurfacePattern pattern;
  final double patternOpacity;

  /// Couleur du motif (sombre sur un fond clair, claire sur un fond sombre).
  final Color ink;
  final ShadowSpec? innerShadow;

  static const _step = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = radii.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipRRect(rrect);
    _paintPattern(canvas, size);
    final shadow = innerShadow;
    if (shadow != null && shadow.enabled) {
      final hole = rrect
          .shift(Offset(shadow.dx, shadow.dy))
          .deflate(shadow.spread);
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(
            (Offset.zero & size).inflate(
              shadow.blur * 3 + shadow.dx.abs() + shadow.dy.abs() + 8,
            ),
          )
          ..addRRect(hole),
        Paint()
          ..color = shadow.shadowColor
          ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, shadow.blur / 2),
      );
    }
    canvas.restore();
  }

  void _paintPattern(Canvas canvas, Size size) {
    if (pattern == SurfacePattern.none || patternOpacity <= 0) return;
    final paint = Paint()
      ..color = ink.withValues(alpha: ink.a * patternOpacity)
      ..strokeWidth = 1;
    switch (pattern) {
      case SurfacePattern.none:
        break;
      case SurfacePattern.lines:
        final span = size.width + size.height;
        for (var d = 0.0; d < span; d += _step) {
          canvas.drawLine(
            Offset(d, 0),
            Offset(d - size.height, size.height),
            paint,
          );
        }
      case SurfacePattern.dots:
        paint.strokeCap = StrokeCap.round;
        paint.strokeWidth = 2;
        final points = <Offset>[];
        for (var y = _step / 2; y < size.height; y += _step * 1.5) {
          for (var x = _step / 2; x < size.width; x += _step * 1.5) {
            points.add(Offset(x, y));
          }
        }
        canvas.drawPoints(ui.PointMode.points, points, paint);
      case SurfacePattern.grain:
        final random = math.Random(7);
        final count = math.min(4000, (size.width * size.height / 10).round());
        final points = [
          for (var i = 0; i < count; i++)
            Offset(
              random.nextDouble() * size.width,
              random.nextDouble() * size.height,
            ),
        ];
        canvas.drawPoints(ui.PointMode.points, points, paint);
    }
  }

  @override
  bool shouldRepaint(SurfaceOverlayPainter old) =>
      old.radii != radii ||
      old.pattern != pattern ||
      old.patternOpacity != patternOpacity ||
      old.ink != ink ||
      old.innerShadow != innerShadow;
}
