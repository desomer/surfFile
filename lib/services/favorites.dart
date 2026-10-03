import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dossiers favoris, partagés par tous les volets et persistés.
class Favorites extends ValueNotifier<List<String>> {
  Favorites._() : super(const []) {
    unawaited(_load());
  }

  static const key = 'favorites.v1';
  static final instance = Favorites._();

  static String _normalize(String path) => path.toLowerCase();

  bool contains(String path) =>
      value.any((p) => _normalize(p) == _normalize(path));

  void toggle(String path) => contains(path) ? remove(path) : add(path);

  void add(String path) {
    if (contains(path)) return;
    value = [...value, path];
    unawaited(_save());
  }

  void remove(String path) {
    value = [
      for (final p in value)
        if (_normalize(p) != _normalize(path)) p,
    ];
    unawaited(_save());
  }

  void move(int from, int to) {
    final list = [...value];
    final item = list.removeAt(from);
    list.insert(to.clamp(0, list.length), item);
    value = list;
    unawaited(_save());
  }

  Future<void> _load() async {
    try {
      final stored = (await SharedPreferences.getInstance()).getString(key);
      if (stored == null) return;
      final json = jsonDecode(stored);
      if (json is! List) return;
      final loaded = [
        for (final p in json)
          if (p is String) p,
      ];
      // Les ajouts faits pendant le chargement sont conservés.
      value = [
        ...loaded,
        for (final p in value)
          if (!loaded.any((l) => _normalize(l) == _normalize(p))) p,
      ];
    } on Exception catch (error) {
      debugPrint('Error loading favorites: $error');
    }
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        key,
        jsonEncode(value),
      );
    } on Exception catch (error) {
      debugPrint('Error saving favorites: $error');
    }
  }
}
