import 'package:material_ui/material_ui.dart';

import '../theme/container_style.dart';
import '../theme/appearance.dart';
import 'neon_surface.dart';

class StyledSurface extends StatelessWidget {
  const StyledSurface({
    required this.style,
    required this.fallbackColor,
    required this.borderColor,
    required this.child,
    this.horizontalBorder = false,
    super.key,
  });

  final ContainerStyle style;
  final Color fallbackColor;
  final Color borderColor;
  final Widget child;
  final bool horizontalBorder;

  @override
  Widget build(BuildContext context) {
    final gradient = style.fill.gradient();
    final side = BorderSide(
      color: style.borderColor ?? borderColor,
      width: style.borderWidth,
      style: style.borderWidth == 0 ? BorderStyle.none : BorderStyle.solid,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(style.radius),
    );
    final material = Material(
      color: gradient == null ? style.color ?? fallbackColor : Colors.transparent,
      elevation: style.elevation,
      shadowColor: Colors.black.withValues(alpha: style.shadowOpacity),
      surfaceTintColor: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(style.radius),
          border: horizontalBorder && style.radius == 0
              ? Border.symmetric(horizontal: side)
              : Border.fromBorderSide(side),
        ),
        child: child,
      ),
    );
    final neon = style.neon;
    return neon == null
        ? material
        : NeonSurface(
            style: neon,
            accent: AppearanceScope.of(context).accent,
            radius: style.radius,
            child: material,
          );
  }
}
