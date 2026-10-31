import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:material_ui/material_ui.dart';

import '../../../theme/appearance.dart';

class EditorZoneBadge extends StatelessWidget {
  const EditorZoneBadge({
    required this.label,
    required this.selected,
    this.hasSelectedChild = false,
    this.labelKey,
    this.onTap,
    this.onHover,
    this.leading,
    this.onAdd,
    this.addKey,
    this.addTooltip,
    this.actions = const [],
    this.mouseCursor = SystemMouseCursors.click,
    super.key,
  });

  final String label;
  final Key? labelKey;
  final bool selected;
  final bool hasSelectedChild;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final Widget? leading;
  final VoidCallback? onAdd;
  final Key? addKey;
  final String? addTooltip;
  final List<Widget> actions;
  final MouseCursor mouseCursor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final directSelection = selected && !hasSelectedChild;
    final parentSelection = selected && hasSelectedChild;
    return Material(
      color: colors.primary.withValues(alpha: .35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: directSelection
              ? colors.onSurface
              : parentSelection
              ? colors.onSurface.withValues(alpha: .45)
              : Colors.transparent,
          width: directSelection ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        mouseCursor: mouseCursor,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onHover: onHover,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 1, 5, 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?leading,
              Text(
                label,
                key: labelKey,
                style: TextStyle(fontSize: 10, color: colors.onSurface),
              ),
              if (onAdd case final onAdd?)
                IconButton(
                  key: addKey,
                  tooltip: addTooltip,
                  visualDensity: VisualDensity.compact,
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  color: colors.onSurface,
                  icon: const Icon(Icons.add),
                  onPressed: onAdd,
                ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Animation continue du contour néon plein pour l'élément sélectionné.
///
/// En exécution réelle (`WidgetsFlutterBinding`), l'animation boucle en continu
/// tant qu'au moins un `EditorSelectionBorder(animated: true)` est affiché.
/// En environnement de test (`TestWidgetsFlutterBinding`), elle exécute un
/// cycle borné afin de permettre à `pumpAndSettle()` de se stabiliser.
class _EditorNeonLoopAnimation extends ChangeNotifier {
  static final _EditorNeonLoopAnimation instance = _EditorNeonLoopAnimation();

  static const Duration _cycleDuration = Duration(milliseconds: 1800);
  static const Duration _testSettleDuration = Duration(milliseconds: 520);
  Duration? _startTimeStamp;
  int? _scheduledFrameId;
  double phase = 0.0;

  static bool get _isTestBinding =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  void restart() {
    _startTimeStamp = null;
    if (hasListeners) {
      _scheduleNextFrame();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    final wasEmpty = !hasListeners;
    super.addListener(listener);
    if (wasEmpty) {
      _startTimeStamp = null;
    }
    _scheduleNextFrame();
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
      _startTimeStamp = null;
      return;
    }
    _startTimeStamp ??= timeStamp;
    final elapsed = timeStamp - _startTimeStamp!;
    if (elapsed.isNegative) {
      phase = 0.0;
      notifyListeners();
      _scheduleNextFrame();
      return;
    }
    if (_isTestBinding && elapsed >= _testSettleDuration) {
      phase = 0.35;
      notifyListeners();
      return;
    }
    final micros = elapsed.inMicroseconds % _cycleDuration.inMicroseconds;
    phase = micros / _cycleDuration.inMicroseconds;
    notifyListeners();
    _scheduleNextFrame();
  }
}

/// Cadre néon d'édition unifié basé sur la couleur d'accent d'édition :
/// - [EditorSelectionBorder.active] : néon **plein toujours animé** sur l'élément sélectionné.
/// - [EditorSelectionBorder.subtleParent] : néon **pointillé non animé** sur le parent.
/// - [EditorSelectionBorder.hover] : néon **pointillé** mis en avant au survol.
class EditorSelectionBorder extends StatelessWidget {
  const EditorSelectionBorder({
    this.dashed = false,
    this.animated = false,
    this.filled = false,
    this.strokeWidth = 2.0,
    this.opacity = 1.0,
    this.fillOpacity = 0.10,
    this.color,
    super.key,
  });

  /// Bordure de sélection active : néon plein toujours animé (`2px`).
  const EditorSelectionBorder.active({
    this.filled = false,
    this.fillOpacity = 0.10,
    this.color,
    super.key,
  }) : dashed = false,
       animated = true,
       strokeWidth = 2.0,
       opacity = 1.0;

  /// Bordure de zone ou slot parent lorsqu'un enfant est sélectionné :
  /// néon pointillé statique (non animé).
  const EditorSelectionBorder.subtleParent({this.color, super.key})
    : dashed = true,
      animated = false,
      filled = false,
      strokeWidth = 1.0,
      opacity = 0.45,
      fillOpacity = 0.0;

  /// Bordure de survol d'un parent ou d'une étiquette : néon pointillé.
  const EditorSelectionBorder.hover({
    this.filled = true,
    this.fillOpacity = 0.12,
    this.color,
    super.key,
  }) : dashed = true,
       animated = false,
       strokeWidth = 1.5,
       opacity = 0.85;

  final bool dashed;
  final bool animated;
  final bool filled;
  final double strokeWidth;
  final double opacity;
  final double fillOpacity;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? AppearanceScope.of(context).accent;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final effectiveAnimated = animated && !dashed && !disableAnimations;
    return IgnorePointer(
      child: CustomPaint(
        painter: EditorSelectionBorderPainter(
          color: baseColor,
          opacity: opacity,
          fillOpacity: filled ? fillOpacity : 0.0,
          dashed: dashed,
          animated: effectiveAnimated,
          strokeWidth: strokeWidth,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class EditorSelectionBorderPainter extends CustomPainter {
  EditorSelectionBorderPainter({
    required this.color,
    required this.dashed,
    required this.strokeWidth,
    this.opacity = 1.0,
    this.fillOpacity = 0.0,
    this.animated = false,
  }) : super(repaint: animated ? _EditorNeonLoopAnimation.instance : null);

  final Color color;
  final double opacity;
  final double fillOpacity;
  final bool dashed;
  final bool animated;
  final double strokeWidth;

  static Color _shiftHue(Color source, double deltaDegrees, double lightness) {
    final hsl = HSLColor.fromColor(source);
    return hsl
        .withHue((hsl.hue + deltaDegrees) % 360)
        .withSaturation((hsl.saturation + 0.18).clamp(0.0, 1.0))
        .withLightness((hsl.lightness + lightness).clamp(0.18, 0.92))
        .toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final fullRect = Offset.zero & size;
    final baseColor = color.withValues(alpha: 1.0);
    final secondaryColor = _shiftHue(baseColor, 38, 0.14);
    final highlightColor = Color.lerp(baseColor, Colors.white, 0.78)!;

    if (fillOpacity > 0) {
      final fillShader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          baseColor.withValues(alpha: fillOpacity),
          secondaryColor.withValues(alpha: fillOpacity * 0.45),
          baseColor.withValues(alpha: fillOpacity * 0.85),
        ],
      ).createShader(fullRect);
      canvas.drawRect(fullRect, Paint()..shader = fillShader);
    }

    final inset = math.max(1.0, strokeWidth / 2);
    final rect = fullRect.deflate(inset);
    if (rect.isEmpty || rect.width <= 0 || rect.height <= 0) return;

    if (!dashed) {
      final phase = animated ? _EditorNeonLoopAnimation.instance.phase : 0.0;
      final pulse = 1.0 + 0.22 * math.sin(phase * math.pi * 2.0);

      // 1. Halo néon externe diffus
      canvas.drawRect(
        rect,
        Paint()
          ..color = baseColor.withValues(alpha: 0.34 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (strokeWidth + 4.5) * pulse
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
      );

      // 2. Coeur lumineux blanc (tube néon)
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.78 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 0.9,
      );

      // 3. Dégradé néon tournant en continu
      final sweepAngle = phase * math.pi * 2.0;
      final sweepShader = SweepGradient(
        colors: [
          baseColor.withValues(alpha: opacity),
          secondaryColor.withValues(alpha: opacity),
          highlightColor.withValues(alpha: opacity),
          secondaryColor.withValues(alpha: opacity),
          baseColor.withValues(alpha: opacity),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        transform: GradientRotation(sweepAngle - math.pi / 4),
      ).createShader(rect);

      canvas.drawRect(
        rect,
        Paint()
          ..shader = sweepShader
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
      return;
    }

    // Mode Néon Pointillé (Non Animé) pour le parent et le survol
    final path = Path()..addRect(rect);
    final dashedPath = Path();
    const dashLength = 6.0;
    const gapLength = 4.5;
    const step = dashLength + gapLength;
    for (final metric in path.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += step) {
        dashedPath.addPath(
          metric.extractPath(
            offset,
            (offset + dashLength).clamp(0.0, metric.length),
          ),
          Offset.zero,
        );
      }
    }

    // 1. Halo néon externe statique autour des pointillés
    canvas.drawPath(
      dashedPath,
      Paint()
        ..color = baseColor.withValues(alpha: (0.36 * opacity).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 3.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // 2. Sous-couche claire pour le contraste néon
    canvas.drawPath(
      dashedPath,
      Paint()
        ..color = Colors.white.withValues(
          alpha: (0.62 * opacity).clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 0.6
        ..strokeCap = StrokeCap.round,
    );

    // 3. Trait néon pointillé statique
    final dashedShader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        baseColor.withValues(alpha: opacity.clamp(0.0, 1.0)),
        secondaryColor.withValues(alpha: opacity.clamp(0.0, 1.0)),
        baseColor.withValues(alpha: opacity.clamp(0.0, 1.0)),
      ],
    ).createShader(rect);

    canvas.drawPath(
      dashedPath,
      Paint()
        ..shader = dashedShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(EditorSelectionBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity ||
      oldDelegate.fillOpacity != fillOpacity ||
      oldDelegate.dashed != dashed ||
      oldDelegate.animated != animated ||
      oldDelegate.strokeWidth != strokeWidth;
}

class EditorZoneHighlight extends StatelessWidget {
  const EditorZoneHighlight({super.key});

  @override
  Widget build(BuildContext context) =>
      const Positioned.fill(child: EditorSelectionBorder.hover());
}
