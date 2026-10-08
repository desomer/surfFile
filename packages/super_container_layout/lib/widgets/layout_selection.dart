import 'package:flutter/foundation.dart';

/// Chemin des zones sélectionnées (parent > ... > enfant) dans les dispositions
/// imbriquées, affiché par la bannière du mode édition.
///
/// Chaque disposition visible déclare son chemin ; le plus profond l'emporte.
class LayoutSelection {
  const LayoutSelection._();

  /// Noms des zones sélectionnées, de la plus englobante à la plus profonde.
  static final path = ValueNotifier<List<String>>(const []);

  static final _reported = <Object, List<String>>{};
  static final _clears = <Object, VoidCallback>{};
  static final _targets =
      <
        Object,
        ({List<String> path, ValueChanged<String?> select, Object? parent})
      >{};

  static void register(
    Object owner,
    List<String> path,
    ValueChanged<String?> select, {
    Object? parent,
  }) {
    _targets[owner] = (
      path: List.unmodifiable(path),
      select: select,
      parent: parent,
    );
  }

  static void unregister(Object owner) => _targets.remove(owner);

  /// Active la disposition du segment, et sa zone si le segment en est une.
  static void select(List<String> prefix) {
    Object? active;
    var depth = -1;
    for (final entry in _reported.entries) {
      if (entry.value.length >= depth) {
        active = entry.key;
        depth = entry.value.length;
      }
    }
    // Les libelles peuvent etre identiques : preferer les ancetres de la
    // disposition active aux autres instances portant le meme nom.
    while (active != null) {
      final target = _targets[active];
      if (target == null) break;
      final length = target.path.length;
      if ((prefix.length == length || prefix.length == length + 1) &&
          listEquals(prefix.take(length).toList(), target.path)) {
        target.select(prefix.length == length ? null : prefix.last);
        return;
      }
      active = target.parent;
    }
    for (final target in _targets.values.toList().reversed) {
      final length = target.path.length;
      if ((prefix.length == length || prefix.length == length + 1) &&
          listEquals(prefix.take(length).toList(), target.path)) {
        target.select(prefix.length == length ? null : prefix.last);
        return;
      }
    }
  }

  /// Désélectionne les dispositions dont le chemin prolonge [prefix] : le
  /// niveau désigné devient le plus profond. Les autres sont inchangées.
  static void cut(List<String> prefix) {
    for (final MapEntry(:key, :value) in [..._reported.entries]) {
      if (value.length > prefix.length &&
          listEquals(value.sublist(0, prefix.length), prefix)) {
        _clears[key]?.call();
      }
    }
  }

  /// La disposition [owner] déclare son chemin ; vide, elle se retire. [clear]
  /// désélectionne ses zones.
  static void report(Object owner, List<String> value, {VoidCallback? clear}) {
    final previous = _reported[owner];
    if (value.isEmpty) {
      _clears.remove(owner);
      if (_reported.remove(owner) == null) return;
    } else {
      if (clear != null) _clears[owner] = clear;
      if (listEquals(previous, value)) return;
      // Réinsérée en dernier : à profondeur égale, la plus récente l'emporte.
      _reported.remove(owner);
      _reported[owner] = value;
    }
    var best = const <String>[];
    for (final candidate in _reported.values) {
      if (candidate.length >= best.length) best = candidate;
    }
    if (!listEquals(path.value, best)) path.value = best;
  }
}
