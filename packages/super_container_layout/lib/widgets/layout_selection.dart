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
