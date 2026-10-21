import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../theme/appearance.dart';
import '../../super_layout/layout_selection.dart';
import '../../super_layout/zone_axis_button.dart';
import 'editor_context_menu.dart';
import 'editor_selection_region.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../overlay/editor_overlay.dart';

export 'editor_context_menu.dart'
    show EditorContextMenuEntry, EditorSlotAction, EditorSlotWrapAction;

/// Enables/disables editor gestures below this scope.
///
/// Without a scope, editable slots remain active, matching the historical
/// behavior of standalone editable surfaces.
class StyleEditScope extends InheritedNotifier<ValueNotifier<bool>> {
  const StyleEditScope({
    required ValueNotifier<bool> controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ValueNotifier<bool>? controllerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StyleEditScope>()?.notifier;
}

const double _defaultIndent = 8.0;

EditorComponentLabel? editorComponentLabelOf(BuildContext context) {
  final inherited = context
      .getElementForInheritedWidgetOfExactType<EditorComponentLabel>()
      ?.widget;
  if (inherited is! EditorComponentLabel) return null;

  var direct = true;
  context.visitAncestorElements((ancestor) {
    if (identical(ancestor.widget, inherited)) return false;
    if (ancestor is StatefulElement && ancestor.state is EditorSlotState) {
      direct = false;
      return false;
    }
    return true;
  });
  return direct ? EditorComponentLabel.of(context) : null;
}

/// An editor interaction target that can wrap any widget.
class EditorSlot extends StatefulWidget {
  const EditorSlot({
    this.child,
    this.label,
    this.menuTitle,
    this.menuType,
    this.onLabelChanged,
    this.editable = true,
    this.onEdit,
    this.onAdd,
    this.axisAction,
    this.menuSubtitle,
    this.onContextMenu,
    this.menuIcon,
    this.identity,
    this.outlineRadius = 0,
    this.onRemoveChild,
    super.key,
  });

  final Widget? child;
  final String? label;
  final String? menuTitle;
  final String? menuType;
  final ValueChanged<String>? onLabelChanged;
  final bool editable;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onAdd;
  final LayoutAxisAction Function()? axisAction;
  final String? Function()? menuSubtitle;
  final ValueChanged<Offset>? onContextMenu;
  final IconData? menuIcon;

  /// Optional semantic identity used to deduplicate equivalent nested slots.
  final Object? identity;

  /// Radius for the generic edit outline, independent of any surface style.
  final double outlineRadius;

  /// Fallback child-removal affordance when the child has no editable target.
  final Future<void> Function()? onRemoveChild;

  @override
  EditorSlotState createState() => EditorSlotState();
}

class EditorSlotState extends State<EditorSlot> {
  String? _localLabel;

  EditorComponentLabel? get _instance => editorComponentLabelOf(context);

  bool get _canRename => _instance != null || widget.onLabelChanged != null;

  String get label {
    final instance = _instance;
    return (instance?.overridden ?? false)
        ? instance!.label
        : _localLabel ?? widget.label ?? 'Editable component';
  }

  bool get canEdit {
    final editMode = StyleEditScope.controllerOf(context);
    return widget.editable && (editMode?.value ?? true);
  }

  /// The directly associated component instance label, if this is its
  /// outermost editor target.
  EditorComponentLabel? get componentLabel => _instance;

  void _renameLabel(String value) {
    final instance = _instance;
    if (instance != null) {
      instance.onChanged(value);
    } else {
      setState(() => _localLabel = value);
      widget.onLabelChanged?.call(value);
    }
  }

  /// Restores a label after cancelling the editor without changing its owner.
  void restoreLabel(String value) => _renameLabel(value);

  Future<void> _promptRename() async {
    final text = TextEditingController(text: label);
    final form = GlobalKey<FormState>();
    try {
      final value = await showEditorDialog<String>(
        context: context,
        target: context,
        builder: (dialogContext) {
          void save() {
            if (form.currentState!.validate()) {
              Navigator.of(dialogContext).pop(text.text.trim());
            }
          }

          return AlertDialog(
            title: const Text('Renommer le composant'),
            content: Form(
              key: form,
              child: TextFormField(
                key: const ValueKey('style-menu-rename-input'),
                controller: text,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Le nom ne peut pas être vide.'
                    : null,
                onFieldSubmitted: (_) => save(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                key: const ValueKey('style-menu-rename-save'),
                onPressed: save,
                child: const Text('Renommer'),
              ),
            ],
          );
        },
      );
      if (value != null && value != label && mounted) _renameLabel(value);
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
    }
  }

  static final Set<EditorSlotState> _hovered = {};
  static final ValueNotifier<EditorSlotState?> _hoveredTarget = ValueNotifier(
    null,
  );
  static bool _hoveredTargetUpdateScheduled = false;
  static EditorSlotState? _menuHoveredTarget;

  int _cachedDepth = 0;

  int get _depth {
    var depth = 0;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is EditorSlotState) {
        depth++;
      }
      return true;
    });
    return depth;
  }

  void _setHovered(bool hovered) {
    if (hovered) {
      _hovered.add(this);
    } else {
      _hovered.remove(this);
    }
    _refreshHoveredTarget();
  }

  void _removeHoveredSafely() {
    final wasHovered = _hovered.remove(this);
    final wasMenuTarget = identical(_menuHoveredTarget, this);
    if (wasMenuTarget) _menuHoveredTarget = null;
    if ((!wasHovered && !wasMenuTarget) || _hoveredTargetUpdateScheduled) {
      return;
    }
    _hoveredTargetUpdateScheduled = true;
    scheduleMicrotask(() {
      _hoveredTargetUpdateScheduled = false;
      _refreshHoveredTarget();
    });
  }

  static void _refreshHoveredTarget() {
    final menuTarget = _menuHoveredTarget;
    if (menuTarget != null && menuTarget.mounted && menuTarget.canEdit) {
      _hoveredTarget.value = menuTarget;
      return;
    }
    EditorSlotState? deepest;
    var maxDepth = -1;
    for (final state in _hovered) {
      if (!state.mounted) continue;
      final depth = state._cachedDepth;
      if (depth > maxDepth) {
        maxDepth = depth;
        deepest = state;
      }
    }
    _hoveredTarget.value = deepest;
  }

  Widget _menuIconBadge(
    IconData icon, {
    required Color background,
    required Color foreground,
  }) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 19, color: foreground),
  );

  ButtonStyle _menuIconButtonStyle(
    BuildContext context, {
    bool destructive = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return IconButton.styleFrom(
      foregroundColor: destructive ? colors.error : colors.onSurfaceVariant,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      minimumSize: const Size.square(36),
    );
  }

  Widget _menuHover(EditorSlotState target, Widget child) => MouseRegion(
    onEnter: (_) {
      if (!(StyleEditScope.controllerOf(target.context)?.value ?? false)) {
        return;
      }
      _menuHoveredTarget = target;
      _refreshHoveredTarget();
    },
    onExit: (_) {
      if (identical(_menuHoveredTarget, target)) {
        _menuHoveredTarget = null;
        _refreshHoveredTarget();
      }
    },
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      ),
    ),
  );

  bool get _hasNestedEditableTarget {
    var found = false;
    void visit(Element element) {
      if (found) return;
      if (element is StatefulElement &&
          element.state is EditorSlotState &&
          (element.state as EditorSlotState).canEdit) {
        found = true;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  @override
  void dispose() {
    _removeHoveredSafely();
    super.dispose();
  }

  /// This slot and its editable ancestors, from deepest to outermost.
  List<EditorSlotState> get editableChain {
    final chain = <EditorSlotState>[];
    final identities = <Object>{};
    EditorSlotState? state = this;
    while (state != null) {
      final identity = state.widget.identity;
      if (state.canEdit && (identity == null || identities.add(identity))) {
        chain.add(state);
      }
      state = state.context.findAncestorStateOfType<EditorSlotState>();
    }
    return chain;
  }

  Map<EditorSlotState, List<EditorSlotAction>> _inlineActionsByState(
    List<EditorSlotState> chain,
    List<EditorSlotAction> provided,
  ) {
    final result = <EditorSlotState, List<EditorSlotAction>>{};
    if (chain.isEmpty) return result;
    final ancestors = <EditorSlotAction>{};
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditorSlotAction && widget.inline) ancestors.add(widget);
      return true;
    });
    final below = [
      for (final action in provided)
        if (action.inline && !ancestors.contains(action)) action,
    ];
    if (below.isNotEmpty) result[chain.first] = below;
    EditorSlotState? current = chain.contains(this) ? this : null;
    final claimed = <EditorSlotState>{if (below.isNotEmpty) chain.first};
    context.visitAncestorElements((element) {
      final inherited = element.widget;
      if (element is StatefulElement) {
        final state = element.state;
        if (state is EditorSlotState && chain.contains(state)) {
          current = state;
        }
      } else if (inherited is EditorSlotAction &&
          inherited.enabled &&
          inherited.inline) {
        final owner = current ?? chain.first;
        if (claimed.add(owner)) (result[owner] ??= []).add(inherited);
      }
      return true;
    });
    return result;
  }

  /// Opens this slot's menu at a global pointer position.
  Future<void> openMenu(
    Offset globalPosition, {
    List<EditorSlotAction>? actions,
  }) async {
    final chain = editableChain;
    for (final state in chain.reversed) {
      if (StyleEditScope.controllerOf(state.context)?.value ?? false) {
        state.widget.onContextMenu?.call(globalPosition);
      }
    }
    final extraActions = actions ?? EditorSlotAction.of(context);
    final inlineActions = _inlineActionsByState(chain, extraActions);
    final entries = <(int, Object)>[
      if (chain.contains(this)) (chain.indexOf(this), this),
    ];
    context.visitAncestorElements((element) {
      final inherited = element.widget;
      if (inherited is EditorContextMenuEntry && inherited.enabled) {
        entries.add((entries.length, inherited));
      } else if (element is StatefulElement) {
        final state = element.state;
        if (state is EditorSlotState && chain.contains(state)) {
          entries.add((entries.length, state));
        }
      }
      return true;
    });
    if (entries.isEmpty && extraActions.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final colors = Theme.of(context).colorScheme;
    final hasMenuActions = extraActions.any((action) => !action.inline);
    Object? selected;
    try {
      selected = await showMenu<Object>(
        context: context,
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 420),
        color: colors.surfaceContainerHigh.withAlpha(240),
        surfaceTintColor: Colors.transparent,
        shadowColor: colors.shadow.withValues(alpha: .18),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          overlay.size.width - position.dx,
          overlay.size.height - position.dy,
        ),
        items: [
          for (final (actionIndex, action)
              in extraActions.where((action) => !action.inline).indexed) ...[
            if (actionIndex > 0) const PopupMenuDivider(height: 12),
            PopupMenuItem<Future<void> Function()>(
              height: 40,
              value: action.onEdit,
              padding: EdgeInsets.zero,
              child: _menuHover(
                this,
                Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    _menuIconBadge(
                      Icons.tune_rounded,
                      background: colors.tertiaryContainer,
                      foreground: colors.onTertiaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        action.label,
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (action.onRemove case final remove?)
                      IconButton(
                        key: ValueKey('style-menu-remove-${action.label}'),
                        tooltip: 'Supprimer le slot',
                        icon: const Icon(Icons.delete_outline),
                        style: _menuIconButtonStyle(context, destructive: true),
                        onPressed: () => Navigator.of(context).pop(remove),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (hasMenuActions && entries.isNotEmpty)
            const PopupMenuDivider(height: 12),
          for (final (entryIndex, (index, entry)) in entries.indexed) ...[
            if (entryIndex > 0) const PopupMenuDivider(height: 12),
            if (entry is EditorContextMenuEntry)
              PopupMenuItem<Future<void> Function()>(
                height: 40,
                key: ValueKey('style-menu-entry-${entry.label}'),
                value: entry.onSelected,
                padding: EdgeInsets.zero,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16 + _defaultIndent * index,
                      0,
                      16,
                      0,
                    ),
                    child: Row(
                      children: [
                        _menuIconBadge(
                          Icons.subdirectory_arrow_left,
                          background: colors.secondaryContainer,
                          foreground: colors.onSecondaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.label,
                            style: Theme.of(context).textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (entry case final EditorSlotState state)
              PopupMenuItem<EditorSlotState>(
                height: 40,
                key: ValueKey('style-menu-${state.label}'),
                enabled: state.widget.onEdit != null,
                value: state,
                padding: EdgeInsets.zero,
                child: _menuHover(
                  state,
                  Padding(
                    padding: EdgeInsets.only(left: _defaultIndent * index),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        _menuIconBadge(
                          state.widget.menuIcon ??
                              state.componentLabel?.menuIcon ??
                              (index == 0
                                  ? Icons.brush_outlined
                                  : Icons.subdirectory_arrow_left),
                          background: colors.primaryContainer,
                          foreground: colors.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state.widget.menuTitle ?? state.label,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              if ((state.widget.menuSubtitle?.call() ??
                                      ((StyleEditScope.controllerOf(
                                                    state.context,
                                                  )?.value ??
                                                  false) &&
                                              state.widget.axisAction != null
                                          ? state.widget.axisAction!().zoneLabel
                                          : state.widget.menuType ??
                                                (state.widget.menuTitle == null
                                                    ? null
                                                    : state.label)))
                                  case final subtitle?
                                  when subtitle !=
                                      (state.widget.menuTitle ?? state.label))
                                Text(
                                  subtitle,
                                  key:
                                      state.widget.menuSubtitle != null ||
                                          (state.widget.menuType == null &&
                                              state.widget.menuTitle == null)
                                      ? ValueKey(
                                          'style-menu-zone-${state.label}',
                                        )
                                      : null,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              if (state.widget.menuSubtitle == null &&
                                  state.widget.menuType != null &&
                                  state.widget.menuTitle != null)
                                Text(
                                  state.label,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                            ],
                          ),
                        ),
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state.widget.axisAction != null)
                          ZoneAxisButton(
                            key: ValueKey('style-menu-axis-${state.label}'),
                            action: LayoutAxisAction(
                              zoneLabel: state.widget.axisAction!().zoneLabel,
                              axis: state.widget.axisAction!().axis,
                              onToggle: () =>
                                  Navigator.of(context)
                                      .pop<Future<void> Function()>(() async {
                                        if (state.mounted) {
                                          state.widget.axisAction!().onToggle();
                                        }
                                      }),
                            ),
                          ),
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state._canRename)
                          IconButton(
                            key: ValueKey('style-menu-rename-${state.label}'),
                            tooltip: 'Renommer',
                            icon: const Icon(Icons.drive_file_rename_outline),
                            style: _menuIconButtonStyle(context),
                            onPressed: () =>
                                Navigator.of(context)
                                    .pop<Future<void> Function()>(() async {
                                      if (state.mounted) {
                                        await state._promptRename();
                                      }
                                    }),
                          ),
                        for (final action
                            in inlineActions[state] ??
                                const <EditorSlotAction>[]) ...[
                          if (action.showEdit)
                            IconButton(
                              key: ValueKey('style-menu-size-${action.label}'),
                              tooltip: action.label,
                              icon: const Icon(Icons.straighten),
                              style: _menuIconButtonStyle(context),
                              onPressed: () =>
                                  Navigator.of(context).pop(action.onEdit),
                            ),
                          if (action.onRemove case final remove?)
                            IconButton(
                              key: ValueKey(
                                'style-menu-remove-${action.label}',
                              ),
                              tooltip: 'Supprimer le slot',
                              icon: const Icon(Icons.delete_outline),
                              style: _menuIconButtonStyle(
                                context,
                                destructive: true,
                              ),
                              onPressed: () =>
                                  Navigator.of(context).pop(remove),
                            ),
                        ],
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state.widget.onRemoveChild != null &&
                            !state._hasNestedEditableTarget)
                          IconButton(
                            key: ValueKey(
                              'style-menu-remove-child-${state.label}',
                            ),
                            tooltip: 'Supprimer le composant enfant',
                            icon: const Icon(Icons.delete_outline),
                            style: _menuIconButtonStyle(
                              context,
                              destructive: true,
                            ),
                            onPressed: () => Navigator.of(context)
                                .pop<Future<void> Function()>(
                                  state.widget.onRemoveChild,
                                ),
                          ),
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state.widget.onAdd != null)
                          IconButton(
                            key: ValueKey('style-menu-add-${state.label}'),
                            tooltip: 'Ajouter un slot',
                            icon: const Icon(Icons.add),
                            style: _menuIconButtonStyle(context),
                            onPressed: () =>
                                Navigator.of(context).pop(state.widget.onAdd),
                          ),
                        if ([
                              for (final action
                                  in inlineActions[state] ??
                                      const <EditorSlotAction>[])
                                ...action.wrapActions,
                            ]
                            case final wrapActions when wrapActions.isNotEmpty)
                          MenuAnchor(
                            consumeOutsideTap: true,
                            menuChildren: [
                              SubmenuButton(
                                leadingIcon: const Icon(Icons.wrap_text),
                                menuChildren: [
                                  for (final action in wrapActions)
                                    MenuItemButton(
                                      leadingIcon: Icon(action.icon),
                                      onPressed: () => Navigator.of(context)
                                          .pop<Future<void> Function()>(
                                            action.onSelected,
                                          ),
                                      child: Text(action.label),
                                    ),
                                ],
                                child: const Text('Envelopper dans…'),
                              ),
                            ],
                            builder: (context, controller, child) => IconButton(
                              key: ValueKey('style-menu-more-${state.label}'),
                              tooltip: 'Autres options',
                              icon: const Icon(Icons.more_vert),
                              style: _menuIconButtonStyle(context),
                              onPressed: () => controller.isOpen
                                  ? controller.close()
                                  : controller.open(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      );
    } finally {
      _menuHoveredTarget = null;
      _refreshHoveredTarget();
    }
    if (!mounted) return;
    if (selected is EditorSlotState && selected.mounted) {
      await selected.openEditor();
    } else if (selected is Future<void> Function()) {
      await selected();
    }
  }

  /// Opens this slot's specialized editor, when supplied.
  Future<void> openEditor() async {
    final callback = widget.onEdit;
    if (callback != null) await callback();
  }

  @override
  Widget build(BuildContext context) {
    final editMode = StyleEditScope.controllerOf(context);
    Widget content = widget.child ?? const SizedBox.expand();
    if (canEdit && editMode != null) {
      _cachedDepth = _depth;
      final painter = EditorSelectionOutline(
        color: AppearanceScope.of(context).accent.withValues(alpha: .8),
        radius: widget.outlineRadius,
      );
      content = MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: ValueListenableBuilder<EditorSlotState?>(
          valueListenable: _hoveredTarget,
          builder: (context, target, child) => ListenableBuilder(
            listenable: Listenable.merge([
              EditorOverlayVisibility.openDialogs,
              EditorSelectionRegion.hoverTarget,
            ]),
            builder: (context, child) => CustomPaint(
              foregroundPainter:
                  EditorOverlayVisibility.openDialogs.value == 0 &&
                      identical(target, this) &&
                      (EditorSelectionRegion.hoverTarget.value == null ||
                          _menuHoveredTarget != null)
                  ? painter
                  : null,
              child: child,
            ),
            child: child,
          ),
          child: content,
        ),
      );
    } else if (_hovered.contains(this)) {
      _removeHoveredSafely();
    }
    content = GestureDetector(
      excludeFromSemantics: true,
      onSecondaryTapUp: canEdit
          ? (details) => openMenu(details.globalPosition)
          : null,
      child: content,
    );
    return content;
  }
}
