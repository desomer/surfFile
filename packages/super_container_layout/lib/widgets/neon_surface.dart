import 'package:material_ui/material_ui.dart';

import '../theme/neon_style.dart';

class NeonSurface extends StatelessWidget {
  const NeonSurface({
    required this.style,
    required this.accent,
    required this.radius,
    this.corners,
    required this.child,
    super.key,
  });

  final NeonStyle style;
  final Color accent;
  final double radius;

  /// Coins de la surface quand ils diffèrent ; sinon [radius].
  final BorderRadius? corners;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!style.enabled || style.intensity == 0) return child;
    final color = style.color ?? accent;
    final strength = style.intensity;
    final borderRadius = corners ?? BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: color.withValues(
              alpha: color.a * (strength * .7).clamp(0.0, 1.0),
            ),
            blurRadius: 6 + 12 * strength,
            spreadRadius: 2 * strength,
          ),
        ],
      ),
      child: child,
    );
  }
}
