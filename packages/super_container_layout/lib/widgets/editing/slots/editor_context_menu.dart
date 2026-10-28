import 'package:flutter/widgets.dart';

import '../addition/insertion_plan.dart';

enum EditorMenuDestination { style, configuration }

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
    this.destination = EditorMenuDestination.configuration,
    required super.child,
    super.key,
  });

  final String label;
  final Future<void> Function() onSelected;
  final bool enabled;
  final EditorMenuDestination destination;

  @override
  bool updateShouldNotify(EditorContextMenuEntry oldWidget) =>
      label != oldWidget.label ||
      onSelected != oldWidget.onSelected ||
      enabled != oldWidget.enabled ||
      destination != oldWidget.destination;
}
