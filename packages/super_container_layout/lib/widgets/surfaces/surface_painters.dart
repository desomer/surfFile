import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../theme/style_extras.dart';

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
    if (size.isEmpty || widths.max <= 0) return;
    final outer = radii.toRRect(Offset.zero & size).scaleRadii();
    final inner = _innerRRect(outer, size);
    final borderRing = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outer)
      ..addRRect(inner);
    if (line == BorderLine.solid) {
      canvas.drawPath(borderRing, Paint()..color = color);
      return;
    }
    canvas.save();
    canvas.clipPath(borderRing);
    for (var i = 0; i < 4; i++) {
      final width = widths[i];
      if (width <= 0) continue;
      final path = _sidePath(outer, size, i, width);
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
    }
    canvas.restore();
  }

  RRect _innerRRect(RRect outer, Size size) {
    final left = widths.left.clamp(0.0, size.width);
    final top = widths.top.clamp(0.0, size.height);
    final right = widths.right.clamp(0.0, size.width - left);
    final bottom = widths.bottom.clamp(0.0, size.height - top);
    Radius shrink(Radius r, double dx, double dy) =>
        Radius.elliptical(math.max(0.0, r.x - dx), math.max(0.0, r.y - dy));
    return RRect.fromRectAndCorners(
      Rect.fromLTRB(left, top, size.width - right, size.height - bottom),
      topLeft: shrink(outer.tlRadius, left, top),
      topRight: shrink(outer.trRadius, right, top),
      bottomRight: shrink(outer.brRadius, right, bottom),
      bottomLeft: shrink(outer.blRadius, left, bottom),
    );
  }

  Path _sidePath(RRect outer, Size size, int side, double width) {
    final r = outer.deflate(width / 2).scaleRadii();
    final prevWidth = widths[(side + 3) % 4];
    final nextWidth = widths[(side + 1) % 4];
    final path = Path();
    void startCorner(Rect arc, double baseAngle, Offset sharpPoint) {
      if (!arc.isEmpty) {
        final start = prevWidth > 0 ? baseAngle + 0.25 * math.pi : baseAngle;
        final sweep = (prevWidth > 0 ? 0.25 : 0.5) * math.pi;
        path.arcTo(arc, start, sweep, true);
      } else {
        path.moveTo(sharpPoint.dx, sharpPoint.dy);
      }
    }

    void endCorner(Rect arc, double baseAngle, Offset sharpPoint) {
      if (!arc.isEmpty) {
        final sweep = (nextWidth > 0 ? 0.25 : 0.5) * math.pi;
        path.arcTo(arc, baseAngle, sweep, false);
      } else {
        path.lineTo(sharpPoint.dx, sharpPoint.dy);
      }
    }

    final tl = Rect.fromLTWH(r.left, r.top, r.tlRadiusX * 2, r.tlRadiusY * 2);
    final tr = Rect.fromLTWH(
      r.right - r.trRadiusX * 2,
      r.top,
      r.trRadiusX * 2,
      r.trRadiusY * 2,
    );
    final br = Rect.fromLTWH(
      r.right - r.brRadiusX * 2,
      r.bottom - r.brRadiusY * 2,
      r.brRadiusX * 2,
      r.brRadiusY * 2,
    );
    final bl = Rect.fromLTWH(
      r.left,
      r.bottom - r.blRadiusY * 2,
      r.blRadiusX * 2,
      r.blRadiusY * 2,
    );
    switch (side) {
      case 0: // Haut
        startCorner(tl, math.pi, Offset(prevWidth > 0 ? r.left : 0, r.top));
        endCorner(
          tr,
          1.5 * math.pi,
          Offset(nextWidth > 0 ? r.right : size.width, r.top),
        );
      case 1: // Droite
        startCorner(
          tr,
          1.5 * math.pi,
          Offset(r.right, prevWidth > 0 ? r.top : 0),
        );
        endCorner(
          br,
          0,
          Offset(r.right, nextWidth > 0 ? r.bottom : size.height),
        );
      case 2: // Bas
        startCorner(
          br,
          0,
          Offset(prevWidth > 0 ? r.right : size.width, r.bottom),
        );
        endCorner(
          bl,
          0.5 * math.pi,
          Offset(nextWidth > 0 ? r.left : 0, r.bottom),
        );
      case 3: // Gauche
        startCorner(
          bl,
          0.5 * math.pi,
          Offset(r.left, prevWidth > 0 ? r.bottom : size.height),
        );
        endCorner(tl, math.pi, Offset(r.left, nextWidth > 0 ? r.top : 0));
    }
    return path;
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
        canvas.drawPoints(ui.PointMode.points, _dotsFor(size), paint);
      case SurfacePattern.grain:
        canvas.drawPoints(ui.PointMode.points, _grainFor(size), paint);
    }
  }

  static Size? _cachedDotsSize;
  static List<Offset>? _cachedDotsPoints;

  static List<Offset> _dotsFor(Size size) {
    if (_cachedDotsSize == size && _cachedDotsPoints != null) {
      return _cachedDotsPoints!;
    }
    final points = <Offset>[];
    for (var y = _step / 2; y < size.height; y += _step * 1.5) {
      for (var x = _step / 2; x < size.width; x += _step * 1.5) {
        points.add(Offset(x, y));
      }
    }
    _cachedDotsSize = size;
    _cachedDotsPoints = points;
    return points;
  }

  static final List<(double, double)> _unitGrain = () {
    final random = math.Random(7);
    return List<(double, double)>.generate(
      4000,
      (_) => (random.nextDouble(), random.nextDouble()),
      growable: false,
    );
  }();
  static Size? _cachedGrainSize;
  static List<Offset>? _cachedGrainPoints;

  static List<Offset> _grainFor(Size size) {
    if (_cachedGrainSize == size && _cachedGrainPoints != null) {
      return _cachedGrainPoints!;
    }
    final count = math.min(4000, (size.width * size.height / 10).round());
    final points = List<Offset>.generate(count, (i) {
      final (ux, uy) = _unitGrain[i];
      return Offset(ux * size.width, uy * size.height);
    }, growable: false);
    _cachedGrainSize = size;
    _cachedGrainPoints = points;
    return points;
  }

  @override
  bool shouldRepaint(SurfaceOverlayPainter old) =>
      old.radii != radii ||
      old.pattern != pattern ||
      old.patternOpacity != patternOpacity ||
      old.ink != ink ||
      old.innerShadow != innerShadow;
}
