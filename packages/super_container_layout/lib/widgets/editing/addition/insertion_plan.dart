import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart' show SlotSizeConstraints;

/// Side of the target where the new component appears.
enum InsertDirection {
  right('À droite', 'à droite', Icons.arrow_forward),
  left('À gauche', 'à gauche', Icons.arrow_back),
  up('Au-dessus', 'vers le haut', Icons.arrow_upward),
  down('En dessous', 'vers le bas', Icons.arrow_downward);

  const InsertDirection(this.label, this.pushLabel, this.icon);

  final String label;
  final String pushLabel;
  final IconData icon;

  Axis get axis =>
      this == right || this == left ? Axis.horizontal : Axis.vertical;

  /// Whether the direction follows the reading order of its axis.
  bool get forward => this == right || this == down;

  IconData get pushIcon => switch (this) {
    right => Icons.keyboard_double_arrow_right,
    left => Icons.keyboard_double_arrow_left,
    up => Icons.keyboard_double_arrow_up,
    down => Icons.keyboard_double_arrow_down,
  };
}

enum InsertMode {
  /// The new component goes next to the target, which keeps its size.
  beside,

  /// The new component takes the target's place and size; the target is
  /// shifted in the direction.
  push,
}

/// How the container of a target stacks its children.
class InsertionHost {
  const InsertionHost({
    required this.axis,
    this.stacked = true,
    this.single = false,
    this.axisMutable = false,
    this.canWrap = true,
  });

  /// Axis along which siblings are stacked.
  final Axis axis;

  /// False for hosts without a stacking order, such as a grid.
  final bool stacked;

  /// The host holds a single component.
  final bool single;

  /// The stack only holds the target and its axis may be switched.
  final bool axisMutable;

  /// The host accepts a `Layout` wrapper in place of the target.
  final bool canWrap;
}

/// The resolved way to add a component next to a target.
sealed class InsertionPlan {
  const InsertionPlan(this.direction, this.mode);

  final InsertDirection direction;
  final InsertMode mode;

  /// Whether the new component precedes the target along the axis.
  bool get newFirst =>
      mode == InsertMode.beside ? !direction.forward : direction.forward;

  /// Human description of the structural change.
  String get hint;
}

/// The new component joins the target's own stack.
class DirectInsertion extends InsertionPlan {
  const DirectInsertion(super.direction, super.mode, {this.axis});

  /// New axis of the stack, when it must be switched first.
  final Axis? axis;

  @override
  String get hint => switch (axis) {
    Axis.horizontal => 'La zone passe en ligne',
    Axis.vertical => 'La zone passe en colonne',
    null => 'Dans la même zone',
  };
}

/// The target is wrapped in a new `Layout` holding it and the new component in
/// its center zone, stacked along [axis].
class WrapInsertion extends InsertionPlan {
  const WrapInsertion(super.direction, super.mode);

  Axis get axis => direction.axis;

  @override
  String get hint => axis == Axis.horizontal
      ? 'Englobe dans un Layout en ligne'
      : 'Englobe dans un Layout en colonne';
}

/// Chooses how to add a component in [direction] of a target held by [host];
/// null when impossible.
InsertionPlan? planInsertion(
  InsertionHost host,
  InsertDirection direction,
  InsertMode mode,
) {
  if (host.stacked && !host.single) {
    if (direction.axis == host.axis) return DirectInsertion(direction, mode);
    if (host.axisMutable) {
      return DirectInsertion(direction, mode, axis: direction.axis);
    }
  }
  return host.canWrap ? WrapInsertion(direction, mode) : null;
}

/// Component chosen in the contextual add wizard.
class InsertedComponent {
  const InsertedComponent({
    required this.type,
    required this.configure,
    this.label,
    this.size,
  });

  /// Placement type, such as `factory:<key>` or `component:<id>`.
  final String type;

  /// Instance label; null keeps the component label.
  final String? label;

  /// Explicit size; null keeps the host's default sizing.
  final SlotSizeConstraints? size;

  /// Writes the component settings under its new instance ID.
  final void Function(String instanceId) configure;
}

/// A level of the contextual add wizard, from the clicked element outwards.
sealed class ContextualAddLevel {
  const ContextualAddLevel();
}

/// Lets a host add a component around one of its children.
class EditorSlotInsertion extends ContextualAddLevel {
  const EditorSlotInsertion({
    required this.label,
    required this.host,
    required this.acceptsTags,
    required this.insert,
    this.zoneTags = const {},
  });

  /// Name of the target, shown as a level of the wizard.
  final String label;
  final InsertionHost host;

  /// Whether the host accepts a component with these tags as a direct child.
  final bool Function(Set<String> tags) acceptsTags;

  /// Tags the host zone is dedicated to (its filter's `include`).
  final Set<String> zoneTags;
  final Future<void> Function(InsertionPlan plan, InsertedComponent component)
  insert;
}

/// A zone or region of an existing container able to receive a component.
class EditorAddZone {
  const EditorAddZone({
    required this.id,
    required this.label,
    required this.insert,
    this.accepts,
    this.hint,
    this.zoneTags = const {},
  });

  final String id;
  final String label;

  /// Whether the zone accepts a component with these tags.
  final bool Function(Set<String> tags)? accepts;

  /// Tags the zone is dedicated to (its filter's `include`).
  final Set<String> zoneTags;

  /// Consequence of the addition; defaults to an addition at the end.
  final String? hint;
  final Future<void> Function(InsertedComponent component) insert;

  bool accept(Set<String> tags) => accepts?.call(tags) ?? true;
}

/// The zones of one container, offered as a level of the wizard.
class EditorAddZoneGroup extends ContextualAddLevel {
  const EditorAddZoneGroup({required this.label, required this.zones});

  /// Name of the container.
  final String label;
  final List<EditorAddZone> zones;
}

/// Publishes the zones of a container (`SuperLayout`, native component) to
/// the contextual add wizard of the elements it contains.
class EditorAddZones extends InheritedWidget {
  const EditorAddZones({
    required this.label,
    required this.zones,
    required super.child,
    this.enabled = true,
    super.key,
  });

  final String label;

  /// Evaluated when the menu opens, the zone under the pointer first.
  final List<EditorAddZone> Function() zones;
  final bool enabled;

  EditorAddZoneGroup? group() {
    if (!enabled) return null;
    final list = zones();
    return list.isEmpty ? null : EditorAddZoneGroup(label: label, zones: list);
  }

  @override
  bool updateShouldNotify(EditorAddZones oldWidget) =>
      label != oldWidget.label ||
      zones != oldWidget.zones ||
      enabled != oldWidget.enabled;
}
