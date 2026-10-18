import 'package:material_ui/material_ui.dart';

import 'json_repository_store.dart';

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
