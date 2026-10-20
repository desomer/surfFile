import 'package:flutter/widgets.dart';

/// Extra menu action contributed by an editor owner to an `EditorSlot`.
class EditorSlotAction extends InheritedWidget {
  const EditorSlotAction({
    required this.label,
    required this.onEdit,
    required this.enabled,
    this.onRemove,
    this.inline = false,
    this.showEdit = true,
    required super.child,
    super.key,
  });

  final String label;
  final Future<void> Function() onEdit;
  final bool enabled;
  final Future<void> Function()? onRemove;
  final bool inline;
  final bool showEdit;

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
      enabled != oldWidget.enabled ||
      onEdit != oldWidget.onEdit ||
      onRemove != oldWidget.onRemove ||
      inline != oldWidget.inline ||
      showEdit != oldWidget.showEdit;
}

/// Inserts a command at its ancestor position among editor menu entries.
class EditorContextMenuEntry extends InheritedWidget {
  const EditorContextMenuEntry({
    required this.label,
    required this.onSelected,
    required this.enabled,
    required super.child,
    super.key,
  });

  final String label;
  final Future<void> Function() onSelected;
  final bool enabled;

  @override
  bool updateShouldNotify(EditorContextMenuEntry oldWidget) =>
      label != oldWidget.label ||
      onSelected != oldWidget.onSelected ||
      enabled != oldWidget.enabled;
}
