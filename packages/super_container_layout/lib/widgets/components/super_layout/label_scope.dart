// Portée de visibilité et d'état de survol des badges/labels en mode édition ([LabelScope]).
//
// Coordonne la mise en évidence des badges d'une même zone ou d'une même grille.
part of 'super_layout.dart';

class _LayoutEditSelection {
  static final selected = ValueNotifier<SuperLayoutState?>(null);

  static void activate(SuperLayoutState layout) {
    LayoutSelection.activate(layout);
    selected.value = layout;
  }
}

/// Transmet le chemin des zones selectionnees aux dispositions imbriquees.
class _LabelScope extends InheritedWidget {
  const _LabelScope({required this.path, required super.child});

  /// Zones sélectionnées au-dessus de ces dispositions, de la plus englobante
  /// à la plus proche.
  final List<String> path;

  static List<String> pathOf(BuildContext context) =>
      LayoutSelectionScope.of(context)?.path ??
      context.dependOnInheritedWidgetOfExactType<_LabelScope>()?.path ??
      const [];

  @override
  bool updateShouldNotify(_LabelScope oldWidget) =>
      !listEquals(path, oldWidget.path);
}
