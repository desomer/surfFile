import 'package:material_ui/material_ui.dart';
import 'appearance.dart';

Color explorerColor(BuildContext context, Color light, Color dark) {
  final appearance = AppearanceScope.of(context);
  final theme = Theme.of(context);
  if (appearance.accent != const Color(0xFF5268D9)) {
    if (light == const Color(0xFF5268D9) ||
        light == const Color(0xFF354AAE)) {
      return theme.colorScheme.primary;
    }
    if (light == const Color(0xFFE2E7FC)) {
      return theme.colorScheme.primaryContainer;
    }
    if (light == Colors.white && dark == theme.colorScheme.onPrimary) {
      return theme.colorScheme.onPrimary;
    }
  }
  return theme.brightness == Brightness.dark ? dark : light;
}
