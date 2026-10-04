import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/interaction_effect.dart';

/// Applique un [InteractionEffect] à la surface construite par [builder].
///
/// [builder] reçoit la surélévation à ajouter à celle de la surface (effet
/// [InteractionEffect.elevation]) : positive au survol, `-infinity` à l'appui
/// (le consommateur borne l'élévation à 0) où une ombre intérieure donne
/// l'impression d'enfoncement. Les effets autres que l'onde désactivent
/// celle des InkWell descendants.
class InteractionEffectBox extends StatefulWidget {
  const InteractionEffectBox({
    required this.effect,
    required this.radius,
    required this.builder,
    this.hover = false,
    this.hoverColor,
    this.ownsHover = false,
    this.borderRadius,
    super.key,
  });

  final InteractionEffect effect;

  /// Voile au survol, en plus de [effect].
  final bool hover;

  /// Couleur du voile au survol ; `null` pour le gris Material.
  final Color? hoverColor;

  /// Supprime le survol natif des InkWell descendants (lignes, cartes) même
  /// sans [hover] : le survol n'existe alors que s'il est activé.
  final bool ownsHover;
  final double radius;

  /// Coins de la surface quand ils diffèrent ; sinon [radius].
  final BorderRadius? borderRadius;
  final Widget Function(BuildContext context, double elevationBoost) builder;

  @override
  State<InteractionEffectBox> createState() => _InteractionEffectBoxState();
}

class _InteractionEffectBoxState extends State<InteractionEffectBox> {
  bool _hovered = false;
  bool _pressed = false;
  int? _pointer;

  void _set({bool? hovered, bool? pressed}) {
    if (!mounted) return;
    setState(() {
      _hovered = hovered ?? _hovered;
      _pressed = pressed ?? _pressed;
    });
  }

  void _release(PointerEvent event) {
    if (event.pointer == _pointer) {
      _pointer = null;
      _set(pressed: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effect = widget.effect;
    final hover = widget.hover;
    final ripple = effect == InteractionEffect.ripple;
    if (ripple && !hover) {
      if (!widget.ownsHover) return widget.builder(context, 0);
      return Theme(
        data: Theme.of(context).copyWith(hoverColor: Colors.transparent),
        child: widget.builder(context, 0),
      );
    }
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced ? Duration.zero : InteractionEffect.duration;
    final elevation = effect == InteractionEffect.elevation;
    final sunk = elevation && _pressed;
    final boost = sunk
        ? double.negativeInfinity
        : elevation && _hovered
        ? InteractionEffect.hoverLift
        : 0.0;
    final pressedVeil = effect == InteractionEffect.pressed && _pressed;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final tint = pressedVeil ? null : widget.hoverColor;
    final base = tint ?? onSurface;
    final alpha = pressedVeil
        ? InteractionEffect.pressedOverlay
        : hover && _hovered && !_pressed
        ? (tint == null
              ? InteractionEffect.hoverOverlay
              : InteractionEffect.hoverTintedOverlay)
        : 0.0;
    final corners = widget.borderRadius ?? BorderRadius.circular(widget.radius);
    final showOverlay = hover || effect == InteractionEffect.pressed;
    Widget content = Theme(
      data: Theme.of(context).copyWith(
        splashFactory: ripple ? null : NoSplash.splashFactory,
        splashColor: ripple ? null : Colors.transparent,
        // Le voile du survol est dessiné ici, pas par les InkWell.
        hoverColor: Colors.transparent,
        highlightColor: ripple ? null : Colors.transparent,
      ),
      child: widget.builder(context, boost),
    );
    if (showOverlay) {
      content = Stack(
        fit: StackFit.passthrough,
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: duration,
                decoration: BoxDecoration(
                  color: base.withValues(alpha: base.a * alpha),
                  borderRadius: corners,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (elevation) {
      content = TweenAnimationBuilder<double>(
        tween: Tween(end: sunk ? 1 : 0),
        duration: duration,
        curve: Curves.easeOutCubic,
        child: content,
        builder: (context, t, child) => Transform.translate(
          offset: InteractionEffect.sinkOffset * (reduced ? 0 : t),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: InsetShadowPainter(
                      borderRadius: corners,
                      intensity: t,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (effect == InteractionEffect.pressed) {
      content = AnimatedScale(
        scale: _pressed && !reduced ? InteractionEffect.pressedScale : 1,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: content,
      );
    }
    return MouseRegion(
      onEnter: (_) => _set(hovered: true),
      onExit: (_) => _set(hovered: false),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons != kPrimaryButton) return;
          _pointer = event.pointer;
          _set(pressed: true);
        },
        onPointerUp: _release,
        onPointerCancel: _release,
        child: content,
      ),
    );
  }
}

/// Ombre intérieure : sombre en haut à gauche, claire en bas à droite.
class InsetShadowPainter extends CustomPainter {
  const InsetShadowPainter({
    required this.borderRadius,
    required this.intensity,
  });

  final BorderRadius borderRadius;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0 || size.isEmpty) return;
    final rrect = borderRadius.toRRect(Offset.zero & size);
    const d = InteractionEffect.insetOffset;
    const blur = InteractionEffect.insetBlur;
    canvas.save();
    canvas.clipRRect(rrect);
    void edge(Offset offset, Color color) {
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rrect.outerRect.inflate(d + blur * 3))
        ..addRRect(rrect.shift(offset));
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, blur),
      );
    }

    edge(
      const Offset(d, d),
      Colors.black.withValues(
        alpha: InteractionEffect.insetShadowOpacity * intensity,
      ),
    );
    edge(
      const Offset(-d, -d),
      Colors.white.withValues(
        alpha: InteractionEffect.insetLightOpacity * intensity,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(InsetShadowPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.intensity != intensity;
}
