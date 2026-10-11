import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis;

class LayoutAxisAction {
  const LayoutAxisAction({
    required this.zoneLabel,
    required this.axis,
    required this.onToggle,
  });

  final String zoneLabel;
  final Axis axis;
  final VoidCallback onToggle;
}

/// Chemin des zones sélectionnées (parent > ... > enfant) dans les dispositions
/// imbriquées, affiché par la bannière du mode édition.
///
/// Chaque disposition visible déclare son chemin ; le plus profond l'emporte.
class LayoutSelection {
  const LayoutSelection._();

  /// Noms des zones sélectionnées, de la plus englobante à la plus profonde.
  static final path = ValueNotifier<List<String>>(const []);
  static final axisAction = ValueNotifier<LayoutAxisAction?>(null);

  static final _reported = <Object, List<String>>{};
  static final _axisActions = <Object, LayoutAxisAction>{};
  static final _clears = <Object, VoidCallback>{};
  static final _targets =
      <
        Object,
        ({List<String> path, ValueChanged<String?> select, Object? parent})
      >{};
  static final _slotSelectors = <Object, ValueChanged<String>>{};
  static final _deselects = <Object, VoidCallback>{};

  static void register(
    Object owner,
    List<String> path,
    ValueChanged<String?> select, {
    Object? parent,
    ValueChanged<String>? selectSlot,
    VoidCallback? onDeselect,
  }) {
    if (onDeselect == null) {
      _deselects.remove(owner);
    } else {
      _deselects[owner] = onDeselect;
    }
    if (selectSlot == null) {
      _slotSelectors.remove(owner);
    } else {
      _slotSelectors[owner] = selectSlot;
    }
    _targets[owner] = (
      path: List.unmodifiable(path),
      select: select,
      parent: parent,
    );
  }

  static void unregister(Object owner) {
    _targets.remove(owner);
    _slotSelectors.remove(owner);
    _deselects.remove(owner);
  }

  /// Bascule le segment courant, ou selectionne un segment parent.
  static void toggle(List<String> prefix) {
    if (!listEquals(prefix, path.value)) {
      select(prefix);
      return;
    }
    Object? active;
    for (final entry in _reported.entries) {
      if (listEquals(entry.value, prefix)) active = entry.key;
    }
    final target = _targets[active];
    if (target == null) return;
    if (prefix.length > target.path.length) {
      select(prefix.sublist(0, prefix.length - 1));
    } else {
      _deselects[active]?.call();
    }
  }

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
      if (prefix.length == length + 2 &&
          _slotSelectors.containsKey(active) &&
          listEquals(prefix.take(length).toList(), target.path)) {
        target.select(prefix[length]);
        _slotSelectors[active]!(prefix.last);
        return;
      }
      if ((prefix.length == length || prefix.length == length + 1) &&
          listEquals(prefix.take(length).toList(), target.path)) {
        target.select(prefix.length == length ? null : prefix.last);
        return;
      }
      active = target.parent;
    }
    for (final entry in _targets.entries.toList().reversed) {
      final target = entry.value;
      final length = target.path.length;
      if (prefix.length == length + 2 &&
          _slotSelectors.containsKey(entry.key) &&
          listEquals(prefix.take(length).toList(), target.path)) {
        target.select(prefix[length]);
        _slotSelectors[entry.key]!(prefix.last);
        return;
      }
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
  static void report(
    Object owner,
    List<String> value, {
    VoidCallback? clear,
    LayoutAxisAction? axis,
  }) {
    final previous = _reported[owner];
    if (value.isEmpty) {
      _clears.remove(owner);
      _axisActions.remove(owner);
      if (_reported.remove(owner) == null) return;
    } else {
      if (clear != null) _clears[owner] = clear;
      if (axis == null) {
        _axisActions.remove(owner);
      } else {
        _axisActions[owner] = axis;
      }
      // Réinsérée en dernier : à profondeur égale, la plus récente l'emporte.
      if (!listEquals(previous, value)) _reported.remove(owner);
      _reported[owner] = value;
    }
    var best = const <String>[];
    Object? bestOwner;
    for (final entry in _reported.entries) {
      if (entry.value.length >= best.length) {
        best = entry.value;
        bestOwner = entry.key;
      }
    }
    if (!listEquals(path.value, best)) path.value = best;
    axisAction.value = _axisActions[bestOwner];
  }
}
