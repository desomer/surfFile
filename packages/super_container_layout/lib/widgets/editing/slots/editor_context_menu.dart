import 'package:flutter/widgets.dart';

import '../addition/insertion_plan.dart';

enum EditorMenuDestination { style, configuration }

/// Target scope when launching or filtering the Vibe AI assistant from a
/// context menu entry (either a whole component or a specific zone/region of a
/// container).
@immutable
class VibeChatScope {
  const VibeChatScope({
    required this.componentId,
    required this.label,
    this.zoneId,
    this.zoneLabel,
  });

  /// Technical identifier of the target component (e.g. layout, card, list,
  /// native component, value, action).
  final String componentId;

  /// Human-readable label of the target component.
  final String label;

  /// Optional technical zone/region identifier within [componentId] (e.g.
  /// `'center'`, `'west'`, `'body'`, `'appBar'`).
  final String? zoneId;

  /// Optional human-readable label for [zoneId].
  final String? zoneLabel;

  /// Registered callback by the active `StyleEditBanner` to open its floating
  /// `VibeChatDialog` focused on the requested scope.
  static bool Function(VibeChatScope scope)? onOpenRequested;

  /// Canonical component ID in `Appearance.components`.
  String get canonicalComponentId {
    if (componentId.endsWith(':layout')) {
      return componentId.substring(0, componentId.length - ':layout'.length);
    }
    if (componentId.endsWith(':item')) {
      return componentId.substring(0, componentId.length - ':item'.length);
    }
    return componentId;
  }

  /// Concise human-readable description of this scope.
  String get displayLabel {
    final z = zoneLabel?.trim();
    if (z != null && z.isNotEmpty) {
      if (label.toLowerCase().contains(z.toLowerCase())) return label;
      return '$label — zone $z';
    }
    if (zoneId != null && zoneId!.isNotEmpty) {
      return '$label — zone $zoneId';
    }
    return label;
  }

  @override
  bool operator ==(Object other) =>
      other is VibeChatScope &&
      other.componentId == componentId &&
      other.label == label &&
      other.zoneId == zoneId &&
      other.zoneLabel == zoneLabel;

  @override
  int get hashCode => Object.hash(componentId, label, zoneId, zoneLabel);

  @override
  String toString() =>
      'VibeChatScope(componentId: $componentId, zoneId: $zoneId, label: $displayLabel)';
}

class EditorSlotWrapAction {
  const EditorSlotWrapAction({
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onSelected;
}

/// Extra menu action contributed by an editor owner to an `EditorSlot`.
class EditorSlotAction extends InheritedWidget {
  const EditorSlotAction({
    required this.label,
    required this.onEdit,
    required this.enabled,
    this.tooltip,
    this.onRemove,
    this.onSelect,
    this.inline = false,
    this.showEdit = true,
    this.wrapActions = const [],
    this.insertion,
    this.destination = EditorMenuDestination.configuration,
    required super.child,
    super.key,
  });

  final String label;
  final String? tooltip;
  final Future<void> Function() onEdit;
  final bool enabled;
  final Future<void> Function()? onRemove;
  final VoidCallback? onSelect;
  final bool inline;
  final bool showEdit;
  final List<EditorSlotWrapAction> wrapActions;

  /// Adds a component around this child through the contextual wizard.
  final EditorSlotInsertion? insertion;
  final EditorMenuDestination destination;

  static List<EditorSlotAction> of(BuildContext context) {
    final actions = <EditorSlotAction>[];
    var hasInlineAction = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditorSlotAction && widget.enabled) {
        if (!widget.inline || !hasInlineAction) actions.add(widget);
        if (widget.inline) hasInlineAction = true;
      }
      return true;
    });
    return actions;
  }

  @override
  bool updateShouldNotify(EditorSlotAction oldWidget) =>
      label != oldWidget.label ||
      tooltip != oldWidget.tooltip ||
      enabled != oldWidget.enabled ||
      onEdit != oldWidget.onEdit ||
      onRemove != oldWidget.onRemove ||
      onSelect != oldWidget.onSelect ||
      wrapActions != oldWidget.wrapActions ||
      insertion != oldWidget.insertion ||
      inline != oldWidget.inline ||
      showEdit != oldWidget.showEdit ||
      destination != oldWidget.destination;
}

/// Inserts a command at its ancestor position among editor menu entries.
class EditorContextMenuEntry extends InheritedWidget {
  const EditorContextMenuEntry({
    required this.label,
    required this.onSelected,
    required this.enabled,
    this.tooltip,
    this.destination = EditorMenuDestination.configuration,
    required super.child,
    super.key,
  });

  final String label;
  final String? tooltip;
  final Future<void> Function() onSelected;
  final bool enabled;
  final EditorMenuDestination destination;

  @override
  bool updateShouldNotify(EditorContextMenuEntry oldWidget) =>
      label != oldWidget.label ||
      tooltip != oldWidget.tooltip ||
      onSelected != oldWidget.onSelected ||
      enabled != oldWidget.enabled ||
      destination != oldWidget.destination;
}
