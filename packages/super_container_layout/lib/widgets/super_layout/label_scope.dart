part of 'super_layout.dart';

class _LayoutEditSelection {
  static final selected = ValueNotifier<SuperLayoutState?>(null);
  static PointerEvent? _lastEvent;
  static SuperLayoutState? _previous;

  static void activate(SuperLayoutState layout) {
    LayoutSelection.deselectDescendants(layout);
    selected.value = layout;
  }

  static bool wasSelected(SuperLayoutState layout, PointerDownEvent event) =>
      identical(event.original ?? event, _lastEvent)
      ? identical(_previous, layout)
      : identical(selected.value, layout);

  static void select(SuperLayoutState layout, PointerDownEvent event) {
    // Les listeners sont appeles du contenu le plus profond vers ses parents.
    final original = event.original ?? event;
    if (identical(original, _lastEvent)) return;
    _lastEvent = original;
    _previous = selected.value;
    if (!identical(_previous, layout)) {
      layout._selectedSlot.value = null;
      layout._selected.value = null;
    }
    activate(layout);
  }
}

/// Transmet le chemin des zones selectionnees aux dispositions imbriquees.
class _LabelScope extends InheritedWidget {
  const _LabelScope({required this.path, required super.child});

  /// Zones sélectionnées au-dessus de ces dispositions, de la plus englobante
  /// à la plus proche.
  final List<String> path;

  static List<String> pathOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LabelScope>()?.path ??
      const [];

  @override
  bool updateShouldNotify(_LabelScope oldWidget) =>
      !listEquals(path, oldWidget.path);
}
