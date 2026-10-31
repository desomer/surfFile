/// Portée `InheritedNotifier` ([JsonRepositoryScope]) exposant le [JsonRepositoryStore] à l'arbre de widgets.
///
/// Permet à tous les composants liés ([SuperValue], [SuperListView], [SuperTable],
/// [SuperTreeView], [SuperChart]) d'accéder aux repositories JSON actifs.
library;

import 'package:material_ui/material_ui.dart';

import 'json_repository_store.dart';

/// Portée `InheritedNotifier` fournissant le [JsonRepositoryStore] aux composants descendants.
class JsonRepositoryScope extends InheritedWidget {
  const JsonRepositoryScope({
    required this.store,
    required super.child,
    super.key,
  });

  final JsonRepositoryStore store;

  static JsonRepositoryStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<JsonRepositoryScope>()?.store;

  @override
  bool updateShouldNotify(JsonRepositoryScope oldWidget) =>
      store != oldWidget.store;
}
