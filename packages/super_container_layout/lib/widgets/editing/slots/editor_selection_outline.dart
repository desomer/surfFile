/// Animation et peintre du cadre de sélection et de survol en mode édition ([EditorSelectionOutline]).
part of 'editor_selection_region.dart';

class _EditorOutlineAnimation extends ChangeNotifier {
  static final _EditorOutlineAnimation instance = _EditorOutlineAnimation();

  static const Duration _duration = Duration(milliseconds: 520);
  Duration? _startTimeStamp;
  int? _scheduledFrameId;
  double progress = 1.0;

  void trigger() {
    progress = 0.0;
    _startTimeStamp = null;
    notifyListeners();
    if (hasListeners) {
      _scheduleNextFrame();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (progress < 1.0) {
      _scheduleNextFrame();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _cancelScheduledFrame();
    }
  }

  void _cancelScheduledFrame() {
    if (_scheduledFrameId case final id?) {
      _scheduledFrameId = null;
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
    progress = 1.0;
    _startTimeStamp = null;
  }

  void _scheduleNextFrame() {
    if (_scheduledFrameId != null || !hasListeners) return;
    _scheduledFrameId = SchedulerBinding.instance.scheduleFrameCallback(
      _onFrame,
    );
  }

  void _onFrame(Duration timeStamp) {
    _scheduledFrameId = null;
    if (!hasListeners) {
      progress = 1.0;
      _startTimeStamp = null;
      return;
    }
    _startTimeStamp ??= timeStamp;
    final elapsed = timeStamp - _startTimeStamp!;
    if (elapsed >= _duration || elapsed.isNegative) {
      progress = 1.0;
      _startTimeStamp = null;
      notifyListeners();
      return;
    }
    progress = (elapsed.inMicroseconds / _duration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    notifyListeners();
    _scheduleNextFrame();
  }
}

/// Cadre visuel entourant la zone ou le composant sélectionné/survolé dans [EditorSelectionRegion].
class EditorSelectionOutline extends CustomPainter {
  EditorSelectionOutline({
    required this.color,
    this.dashed = true,
    this.radius = 0,
    this.emphasized = false,
    this.label,
    this.zoomScale = 1.0,
  }) : super(repaint: _EditorOutlineAnimation.instance);

  final Color color;
  final bool dashed;
  final double radius;
  final bool emphasized;
  final String? label;

  /// Facteur de zoom courant (`EditorZoomScope`) afin que le badge de survol
  /// conserve une taille écran constante (1:1) sans être zoomé.
  final double zoomScale;

  /// Relance l'animation d'entrée (verrouillage des coins + balayage lumineux).
  static void triggerAnimation() {
    _EditorOutlineAnimation.instance.trigger();
  }

  static Color _shiftHue(Color source, double deltaDegrees, double lightness) {
    final hsl = HSLColor.fromColor(source);
    return hsl
        .withHue((hsl.hue + deltaDegrees) % 360)
        .withSaturation((hsl.saturation + 0.15).clamp(0.0, 1.0))
        .withLightness((hsl.lightness + lightness).clamp(0.15, 0.92))
        .toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rawProgress = _EditorOutlineAnimation.instance.progress;
    final lockCurve = Curves.easeOutBack.transform(rawProgress);
    final fadeCurve = Curves.easeOutCubic.transform(rawProgress);

    final baseInset = emphasized ? 1.5 : 1.0;
    // Slight initial expansion that locks onto the target bounds
    final dynamicInset =
        baseInset - (1.0 - lockCurve) * (emphasized ? 4.5 : 2.5);
    final rect = (Offset.zero & size).deflate(dynamicInset);
    if (rect.isEmpty || rect.width <= 2 || rect.height <= 2) return;

    final maxCorner = math.max(0.0, math.min(16.0, rect.shortestSide / 2));
    final cornerRadius = (radius - baseInset).clamp(0.0, maxCorner).toDouble();
    final r = Radius.circular(cornerRadius);
    final rrect = RRect.fromRectAndRadius(rect, r);
    final path = Path()..addRRect(rrect);

    final baseColor = color.withValues(alpha: 1.0);
    final secondaryColor = _shiftHue(baseColor, 38, 0.14);
    final highlightColor = Color.lerp(baseColor, Colors.white, 0.72)!;
    final strokeWidth = emphasized ? 2.6 : 2.0;

    // 1. Subtle inner spotlight tint when emphasized
    if (emphasized) {
      final fillShader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          baseColor.withValues(alpha: 0.11 * fadeCurve),
          secondaryColor.withValues(alpha: 0.04 * fadeCurve),
          baseColor.withValues(alpha: 0.09 * fadeCurve),
        ],
      ).createShader(rect);
      canvas.drawRRect(rrect, Paint()..shader = fillShader);
    }

    // 2. Outer luminous glow halo
    final pulseFactor = 1.0 + 0.25 * math.sin(rawProgress * math.pi);
    final glowPaint = Paint()
      ..color = baseColor.withValues(
        alpha: (emphasized ? 0.26 : 0.14) * fadeCurve,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = (emphasized ? 7.5 : 4.5) * pulseFactor;
    canvas.drawRRect(rrect, glowPaint);

    // 3. High-contrast white underlay stroke + 4. Animated SweepGradient border
    final contrastPaint = Paint()
      ..color = Colors.white.withValues(
        alpha: (emphasized ? 0.90 : 0.65) * fadeCurve,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1.2
      ..strokeCap = StrokeCap.round;

    final sweepAngle = rawProgress * math.pi * 2.0;
    final sweepShader = SweepGradient(
      colors: [
        baseColor,
        secondaryColor,
        highlightColor,
        secondaryColor,
        baseColor,
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(sweepAngle - math.pi / 4),
    ).createShader(rect);

    final borderPaint = Paint()
      ..shader = sweepShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (!dashed) {
      canvas.drawRRect(rrect, contrastPaint);
      canvas.drawPath(path, borderPaint);
    } else {
      final dashedPath = Path();
      final dashPhase = (1.0 - rawProgress) * 14.0;
      for (final metric in path.computeMetrics()) {
        for (var offset = dashPhase; offset < metric.length; offset += 12) {
          dashedPath.addPath(
            metric.extractPath(
              offset,
              (offset + 7.5).clamp(0.0, metric.length),
            ),
            Offset.zero,
          );
        }
      }
      canvas.drawPath(dashedPath, contrastPaint);
      canvas.drawPath(dashedPath, borderPaint);
    }

    // 5. Dynamic 4-corner Lock-On brackets
    if (rect.width >= 24 && rect.height >= 24) {
      final bracketLen = math
          .min(emphasized ? 14.0 : 10.0, rect.shortestSide * 0.28)
          .clamp(6.0, 18.0)
          .toDouble();
      final bracketSpread = (1.0 - lockCurve) * (emphasized ? 7.0 : 4.0);
      final bRect = rect.inflate(bracketSpread);
      final maxBr = math.max(0.0, math.min(bracketLen - 2, 10.0));
      final br = cornerRadius.clamp(0.0, maxBr).toDouble();
      final bracketPath = _buildCornerBracketsPath(bRect, bracketLen, br);

      canvas.drawPath(
        bracketPath,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.92 * fadeCurve)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (emphasized ? 4.2 : 3.2)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        bracketPath,
        Paint()
          ..color = emphasized ? secondaryColor : baseColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = (emphasized ? 2.8 : 2.0)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 6. Modern gradient pill badge at top-left when emphasized (kept at constant 1:1 screen size)
    final badgeText = label?.trim();
    final effectiveZoom = zoomScale > 0 && zoomScale.isFinite ? zoomScale : 1.0;
    final invZoom = 1.0 / effectiveZoom;
    final screenWidth = rect.width * effectiveZoom;
    final screenHeight = rect.height * effectiveZoom;
    if (emphasized &&
        badgeText != null &&
        badgeText.isNotEmpty &&
        screenWidth >= 44 &&
        screenHeight >= 22) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: badgeText,
          style: TextStyle(
            color: Colors.white.withValues(alpha: fadeCurve),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.25,
            height: 1.1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: (screenWidth - 24).clamp(24.0, 240.0));

      const hPad = 8.0;
      const vPad = 4.0;
      const dotSize = 5.5;
      const dotGap = 5.0;
      final badgeWidth = textPainter.width + hPad * 2 + dotSize + dotGap;
      final badgeHeight = textPainter.height + vPad * 2;
      final slideOffset = (1.0 - fadeCurve) * -6.0;
      const badgeLeft = 6.0;
      final badgeTop = 6.0 + slideOffset;
      final badgeRect = Rect.fromLTWH(
        badgeLeft,
        badgeTop,
        badgeWidth,
        badgeHeight,
      );
      final badgeRRect = RRect.fromRectAndRadius(
        badgeRect,
        Radius.circular(badgeHeight / 2),
      );

      canvas.save();
      canvas.translate(rect.left, rect.top);
      canvas.scale(invZoom, invZoom);

      // Soft drop shadow
      canvas.drawRRect(
        badgeRRect.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28 * fadeCurve)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );

      // Pill gradient background
      final pillShader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          baseColor.withValues(alpha: 0.96 * fadeCurve),
          secondaryColor.withValues(alpha: 0.96 * fadeCurve),
        ],
      ).createShader(badgeRect);
      canvas.drawRRect(badgeRRect, Paint()..shader = pillShader);

      // Crisp specular border
      canvas.drawRRect(
        badgeRRect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.88 * fadeCurve)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );

      // Glowing indicator dot
      final dotCenter = Offset(
        badgeLeft + hPad + dotSize / 2,
        badgeTop + badgeHeight / 2,
      );
      canvas.drawCircle(
        dotCenter,
        dotSize / 2,
        Paint()..color = Colors.white.withValues(alpha: 0.95 * fadeCurve),
      );

      textPainter.paint(
        canvas,
        Offset(badgeLeft + hPad + dotSize + dotGap, badgeTop + vPad),
      );
      textPainter.dispose();
      canvas.restore();
    }
  }

  static Path _buildCornerBracketsPath(Rect rect, double len, double r) {
    final path = Path();
    // Top-left
    path.moveTo(rect.left, rect.top + len);
    path.lineTo(rect.left, rect.top + r);
    if (r > 0) {
      path.quadraticBezierTo(rect.left, rect.top, rect.left + r, rect.top);
    }
    path.lineTo(rect.left + len, rect.top);

    // Top-right
    path.moveTo(rect.right - len, rect.top);
    path.lineTo(rect.right - r, rect.top);
    if (r > 0) {
      path.quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + r);
    }
    path.lineTo(rect.right, rect.top + len);

    // Bottom-right
    path.moveTo(rect.right, rect.bottom - len);
    path.lineTo(rect.right, rect.bottom - r);
    if (r > 0) {
      path.quadraticBezierTo(
        rect.right,
        rect.bottom,
        rect.right - r,
        rect.bottom,
      );
    }
    path.lineTo(rect.right - len, rect.bottom);

    // Bottom-left
    path.moveTo(rect.left + len, rect.bottom);
    path.lineTo(rect.left + r, rect.bottom);
    if (r > 0) {
      path.quadraticBezierTo(
        rect.left,
        rect.bottom,
        rect.left,
        rect.bottom - r,
      );
    }
    path.lineTo(rect.left, rect.bottom - len);
    return path;
  }

  @override
  bool shouldRepaint(EditorSelectionOutline oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dashed != dashed ||
      oldDelegate.radius != radius ||
      oldDelegate.emphasized != emphasized ||
      oldDelegate.label != label ||
      oldDelegate.zoomScale != zoomScale;
}

/// Peintre permanent en mode édition affichant un badge compact en haut à droite
/// et un liseré subtil pour identifier visuellement un composant composé / enregistré.
class EditorComposedComponentBadgePainter extends CustomPainter {
  const EditorComposedComponentBadgePainter({
    required this.componentName,
    this.composable = true,
    this.radius = 0,
    this.zoomScale = 1.0,
    this.innerPainter,
  });

  /// Nom du composant enregistré (ex: `'panString'`).
  final String componentName;

  /// Vrai s'il s'agit d'un composant décomposable (`RegisteredComponent.composable`), faux s'il est forcé/atomique.
  final bool composable;

  /// Rayon de courbure de la surface.
  final double radius;

  /// Facteur de zoom courant (`EditorZoomScope`) pour garder le badge à l'échelle 1:1.
  final double zoomScale;

  /// Peintre d'outline de sélection/survol éventuel à combiner.
  final CustomPainter? innerPainter;

  static const Color composedPrimary = Color(0xFF7C3AED);
  static const Color composedSecondary = Color(0xFF6366F1);
  static const Color forcedPrimary = Color(0xFF0D9488);
  static const Color forcedSecondary = Color(0xFF0284C7);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.0);
    if (!rect.isEmpty && rect.width > 4 && rect.height > 4) {
      final primary = composable ? composedPrimary : forcedPrimary;
      final secondary = composable ? composedSecondary : forcedSecondary;
      final maxCorner = math.max(0.0, math.min(16.0, rect.shortestSide / 2));
      final cornerRadius = (radius - 1.0).clamp(0.0, maxCorner).toDouble();
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));

      // Fin liseré pointillé si aucun peintre de survol actif n'est présent
      if (innerPainter == null) {
        final path = Path()..addRRect(rrect);
        final dashedPath = Path();
        for (final metric in path.computeMetrics()) {
          for (var offset = 0.0; offset < metric.length; offset += 10) {
            dashedPath.addPath(
              metric.extractPath(
                offset,
                (offset + 5.0).clamp(0.0, metric.length),
              ),
              Offset.zero,
            );
          }
        }
        canvas.drawPath(
          dashedPath,
          Paint()
            ..color = primary.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }

      innerPainter?.paint(canvas, size);

      // Badge permanent en haut à droite (maintenu à l'échelle écran 1:1)
      final effectiveZoom =
          zoomScale > 0 && zoomScale.isFinite ? zoomScale : 1.0;
      final invZoom = 1.0 / effectiveZoom;
      final screenWidth = rect.width * effectiveZoom;
      final screenHeight = rect.height * effectiveZoom;
      final text = componentName.trim();
      if (text.isNotEmpty && screenWidth >= 48 && screenHeight >= 20) {
        final prefix = composable ? '🧩 ' : '📦 ';
        final textPainter = TextPainter(
          text: TextSpan(
            text: '$prefix$text',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              height: 1.1,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: (screenWidth - 20).clamp(24.0, 200.0));

        const hPad = 7.0;
        const vPad = 3.0;
        final badgeWidth = textPainter.width + hPad * 2;
        final badgeHeight = textPainter.height + vPad * 2;
        final badgeLeft = screenWidth - badgeWidth - 6.0;
        const badgeTop = 5.0;
        final badgeRect = Rect.fromLTWH(
          badgeLeft,
          badgeTop,
          badgeWidth,
          badgeHeight,
        );
        final badgeRRect = RRect.fromRectAndRadius(
          badgeRect,
          Radius.circular(badgeHeight / 2),
        );

        canvas.save();
        canvas.translate(rect.left, rect.top);
        canvas.scale(invZoom, invZoom);

        canvas.drawRRect(
          badgeRRect.shift(const Offset(0, 1.0)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.24)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
        );

        final pillShader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: 0.92),
            secondary.withValues(alpha: 0.92),
          ],
        ).createShader(badgeRect);
        canvas.drawRRect(badgeRRect, Paint()..shader = pillShader);

        canvas.drawRRect(
          badgeRRect,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.80)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );

        textPainter.paint(canvas, Offset(badgeLeft + hPad, badgeTop + vPad));
        textPainter.dispose();
        canvas.restore();
      }
    } else {
      innerPainter?.paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(EditorComposedComponentBadgePainter oldDelegate) =>
      oldDelegate.componentName != componentName ||
      oldDelegate.composable != composable ||
      oldDelegate.radius != radius ||
      oldDelegate.zoomScale != zoomScale ||
      oldDelegate.innerPainter != innerPainter;
}
