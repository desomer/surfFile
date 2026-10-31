/// Portée de propagation du survol de conteneur ([ContentHoverScope]).
///
/// Permet à un conteneur englobant (comme [IterableContent] sur une ligne de liste)
/// d'activer l'état automatique [AutomaticState.contentHover] sur ses enfants.
library;

import 'package:material_ui/material_ui.dart';

/// The nearest IterableContent owns the hover of its whole row.
class ContentHoverScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ContentHoverScope({
    required ValueNotifier<bool> hovered,
    required super.child,
    super.key,
  }) : super(notifier: hovered);

  static ContentHoverScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentHoverScope>();

  bool get hovered => notifier!.value;
}
