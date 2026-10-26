import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis, Rect;
import 'package:flutter/widgets.dart' show BuildContext, InheritedWidget, PointerDownEvent, PointerEvent;

/// Selection ancestry shared by native page regions and nested layouts.
class LayoutSelectionScope extends InheritedWidget {
  const LayoutSelectionScope({
    required this.path,
    required this.owner,
    this.isSlotScope = false,
    required super.child,
    super.key,
  });

  final List<String> path;
  final Object owner;
  final bool isSlotScope;

  static LayoutSelectionScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayoutSelectionScope>();

  @override
  bool updateShouldNotify(LayoutSelectionScope oldWidget) =>
      !listEquals(path, oldWidget.path) ||
      owner != oldWidget.owner ||
      isSlotScope != oldWidget.isSlotScope;
}

class LayoutFocus {
  const LayoutFocus(this.context);

  final BuildContext context;
}

class LayoutAxisAction {
  const LayoutAxisAction({
    required this.zoneLabel,
    required this.axis,
    required this.onToggle,
    this.onEditFlow,
  });

  final String zoneLabel;
  final Axis axis;
  final VoidCallback onToggle;
  final Future<void> Function()? onEditFlow;
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
  static final focus = ValueNotifier<LayoutFocus?>(null);
  static PointerEvent? _pointer;

  /// The deepest selection listener claims each pointer event first.
  static bool claimPointer(PointerDownEvent event) {
    final original = event.original ?? event;
    if (identical(original, _pointer)) return false;
    _pointer = original;
    return true;
  }
  /// Free screen area while an editor dialog is docked.
  static final editorViewport = ValueNotifier<Rect?>(null);

  static final _reported = <Object, List<String>>{};
  static final _axisActions = <Object, LayoutAxisAction>{};
  static final _focusTargets = <Object, LayoutFocus>{};
  static final _clears = <Object, VoidCallback>{};
  static final _targets =
      <
        Object,
        ({
          List<String> path,
          ValueChanged<String?> select,
          Object? parent,
          bool delegateToParent,
        })
      >{};
  static final _slotSelectors = <Object, ValueChanged<String>>{};
  static final _deselects = <Object, VoidCallback>{};
  static Object? _activeOwner;
  static List<String> _leafSuffix = const [];

  /// The container currently owning the deepest reported selection path.
  static Object? get activeOwner => _activeOwner;

  /// Whether [owner] currently has a non-empty reported path.
  static bool isReported(Object owner) => _reported.containsKey(owner);

  static bool _isAncestor(Object candidate, Object ofOwner) {
    var parent = _targets[ofOwner]?.parent;
    while (parent != null) {
      if (identical(parent, candidate)) return true;
      parent = _targets[parent]?.parent;
    }
    return false;
  }

  static void _removeReported(Object owner) {
    _clears.remove(owner);
    _axisActions.remove(owner);
    _focusTargets.remove(owner);
    _reported.remove(owner);
  }

  static void _syncReported() {
    var best = const <String>[];
    Object? bestOwner;
    for (final entry in _reported.entries) {
      if (entry.value.length >= best.length) {
        best = entry.value;
        bestOwner = entry.key;
      }
    }
    _activeOwner = bestOwner;
    final fullPath = best.isEmpty || _leafSuffix.isEmpty
        ? best
        : List<String>.unmodifiable([...best, ..._leafSuffix]);
    if (!listEquals(path.value, fullPath)) path.value = fullPath;
    axisAction.value = _axisActions[bestOwner];
    focus.value = _focusTargets[bestOwner];
  }

  /// Appends deeper leaf `EditorSlot` labels below the active container's slot.
  static void setLeafSuffix(List<String> labels) {
    if (listEquals(_leafSuffix, labels)) return;
    _leafSuffix = labels.isEmpty ? const [] : List.unmodifiable(labels);
    _syncReported();
  }

  static void register(
    Object owner,
    List<String> path,
    ValueChanged<String?> select, {
    Object? parent,
    ValueChanged<String>? selectSlot,
    VoidCallback? onDeselect,
    bool delegateToParent = false,
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
      delegateToParent: delegateToParent,
    );
  }

  static void unregister(Object owner) {
    _targets.remove(owner);
    _slotSelectors.remove(owner);
    _deselects.remove(owner);
  }

  /// Clears descendants by identity, including inactive layouts with saved
  /// zone or slot selections.
  static void deselectDescendants(Object owner) {
    _leafSuffix = const [];
    var removedReported = false;
    for (final entry in _targets.entries.toList()) {
      if (_isAncestor(owner, entry.key)) {
        if (_reported.containsKey(entry.key)) {
          _removeReported(entry.key);
          removedReported = true;
        }
        _deselects[entry.key]?.call();
      }
    }
    if (removedReported) _syncReported();
  }

  /// Activates [owner], clearing its descendants as well as any previously
  /// active non-ancestor containers and removing stale ancestor reports.
  static void activate(Object owner) {
    _leafSuffix = const [];
    var changed = false;
    for (final entry in _targets.entries.toList()) {
      final other = entry.key;
      if (identical(other, owner)) continue;
      if (_isAncestor(owner, other)) {
        if (_reported.containsKey(other)) {
          _removeReported(other);
          changed = true;
        }
        _deselects[other]?.call();
      } else if (!_isAncestor(other, owner)) {
        if (_reported.containsKey(other)) {
          _removeReported(other);
          changed = true;
          _deselects[other]?.call();
        }
      } else if (_reported.containsKey(other)) {
        _removeReported(other);
        changed = true;
      }
    }
    if (changed) _syncReported();
  }

  static bool _canParentHandlePrefix(Object? parent, List<String> prefix) {
    if (parent == null) return false;
    final target = _targets[parent];
    if (target == null) return false;
    final length = target.path.length;
    if (!listEquals(prefix.take(length).toList(), target.path)) return false;
    if (prefix.length == length + 2 && _slotSelectors.containsKey(parent)) {
      return true;
    }
    if (prefix.length == length || prefix.length == length + 1) {
      return true;
    }
    return false;
  }

  /// Bascule le segment courant, ou selectionne un segment parent.
  static void toggle(List<String> prefix) {
    if (!listEquals(prefix, path.value)) {
      select(prefix);
      return;
    }
    if (_leafSuffix.isNotEmpty && prefix.length > 1) {
      _leafSuffix = _leafSuffix.sublist(0, _leafSuffix.length - 1);
      _syncReported();
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
    } else if (target.delegateToParent &&
        target.parent != null &&
        prefix.length > 1) {
      select(prefix.sublist(0, prefix.length - 1));
    } else {
      _deselects[active]?.call();
    }
  }

  /// Active la disposition du segment, et sa zone si le segment en est une.
  static void select(List<String> prefix) {
    _leafSuffix = const [];
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
          !(prefix.length == length &&
              target.delegateToParent &&
              _canParentHandlePrefix(target.parent, prefix)) &&
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
          !(prefix.length == length &&
              target.delegateToParent &&
              _canParentHandlePrefix(target.parent, prefix)) &&
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
    BuildContext? focusContext,
  }) {
    final previous = _reported[owner];
    if (value.isEmpty) {
      _clears.remove(owner);
      _axisActions.remove(owner);
      _focusTargets.remove(owner);
      if (_reported.remove(owner) == null) return;
      if (identical(_activeOwner, owner)) _leafSuffix = const [];
    } else {
      if (!listEquals(previous, value)) _leafSuffix = const [];
      if (clear != null) _clears[owner] = clear;
      if (focusContext == null) {
        _focusTargets.remove(owner);
      } else {
        _focusTargets[owner] = LayoutFocus(focusContext);
      }
      if (axis == null) {
        _axisActions.remove(owner);
      } else {
        _axisActions[owner] = axis;
      }
      // Réinsérée en dernier : à profondeur égale, la plus récente l'emporte.
      if (!listEquals(previous, value)) _reported.remove(owner);
      _reported[owner] = value;
    }
    _syncReported();
  }
}
