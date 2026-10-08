part of '../super_layout.dart';

/// Indique si les étiquettes d'édition des dispositions situées dessous sont
/// visibles ; la disposition racine les montre toujours.
class _LabelScope extends InheritedWidget {
  const _LabelScope({
    required this.visible,
    required this.path,
    required super.child,
  });

  final bool visible;

  /// Zones sélectionnées au-dessus de ces dispositions, de la plus englobante
  /// à la plus proche.
  final List<String> path;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LabelScope>()?.visible ??
      true;

  static List<String> pathOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LabelScope>()?.path ??
      const [];

  @override
  bool updateShouldNotify(_LabelScope oldWidget) =>
      visible != oldWidget.visible || !listEquals(path, oldWidget.path);
}
