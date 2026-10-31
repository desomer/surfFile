import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragStartBehavior, kPrimaryButton, kSecondaryMouseButton, kTouchSlop;
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:material_ui/material_ui.dart';

import '../../../theme/appearance.dart';
import '../../../models/component_behavior.dart';
import '../../components/super_layout/layout_selection.dart';
import '../../components/super_layout/zone_axis_button.dart';
import '../addition/contextual_add.dart';
import '../addition/insertion_plan.dart';
import '../ai/vibe_chat_dialog.dart';
import '../behaviors/component_behavior_editor.dart';
import 'editor_context_menu.dart';
import 'editor_selection_region.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../dialogs/super_value_json_extract_dialog.dart';
import '../overlay/editor_overlay.dart';
import '../overlay/editor_zone_badge.dart';
import '../overlay/editor_zoom.dart';

export 'editor_context_menu.dart'
    show
        EditorContextMenuEntry,
        EditorSlotAction,
        EditorSlotWrapAction,
        EditorMenuDestination,
        EditorTooltipColorSwatch,
        VibeChatScope,
        buildEditorTooltipRichMessage;

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
  static const IconData zoneMenuIcon = Icons.view_quilt_outlined;

  const EditorSlot({
    this.id,
    this.zoneId,
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
    this.menuTooltip,
    this.onContextMenu,
    this.menuIcon,
    this.menuDestination = EditorMenuDestination.configuration,
    this.identity,
    this.outlineRadius = 0,
    this.onRemoveChild,
    this.wrapChildrenActions = const [],
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
  final String? Function()? menuTooltip;
  final ValueChanged<Offset>? onContextMenu;
  final IconData? menuIcon;
  final EditorMenuDestination menuDestination;

  /// Optional semantic identity used to deduplicate equivalent nested slots.
  final Object? identity;

  /// Radius for the generic edit outline, independent of any surface style.
  final double outlineRadius;

  /// Fallback child-removal affordance when the child has no editable target.
  final Future<void> Function()? onRemoveChild;

  /// Actions that wrap all children of this zone or container.
  final List<EditorSlotWrapAction> wrapChildrenActions;

  /// Stable technical identity for the component or slot.
  final String? id;

  /// Optional technical zone/region identity when this slot represents a zone
  /// of a container (`id`).
  final String? zoneId;

  @override
  EditorSlotState createState() => EditorSlotState();
}

class EditorSlotState extends State<EditorSlot> {
  String? _localLabel;

  EditorComponentLabel? get _instance => editorComponentLabelOf(context);

  bool get _canRename => _instance != null || widget.onLabelChanged != null;

  String get effectiveComponentId {
    if (widget.id != null && widget.id!.isNotEmpty) return widget.id!;
    final instId = _instance?.id;
    if (instId != null && instId.isNotEmpty) return instId;
    if (widget.identity is String && (widget.identity as String).isNotEmpty) {
      return widget.identity as String;
    }
    final inst = _instance?.label;
    if (inst != null && inst.isNotEmpty) return inst;
    final l = widget.label;
    if (l != null && l.isNotEmpty) return l;
    return 'component';
  }

  String get label {
    final instance = _instance;
    return (instance?.overridden ?? false)
        ? instance!.label
        : _localLabel ?? widget.label ?? 'Editable component';
  }

  String get titleLabel {
    final instance = _instance;
    return (instance?.overridden ?? false)
        ? instance!.label
        : _localLabel ??
              widget.menuTitle ??
              widget.label ??
              'Editable component';
  }

  bool get canEdit {
    final editMode = StyleEditScope.controllerOf(context);
    return widget.editable && (editMode?.value ?? true);
  }

  /// The directly associated component instance label, if this is its
  /// outermost editor target.
  EditorComponentLabel? get componentLabel => _instance;

  String? get _parentComponentIdForAi {
    final selfCanonical = VibeChatScope.canonicalizeId(effectiveComponentId);
    EditorSlotState? ancestor = context
        .findAncestorStateOfType<EditorSlotState>();
    while (ancestor != null) {
      if (ancestor.canEdit) {
        final candidate = VibeChatScope.canonicalizeId(
          ancestor.effectiveComponentId,
        );
        if (candidate.isNotEmpty &&
            candidate != 'component' &&
            candidate != selfCanonical) {
          return candidate;
        }
      }
      ancestor = ancestor.context.findAncestorStateOfType<EditorSlotState>();
    }
    return null;
  }

  /// Scope descriptor targeting this component or container zone for AI edits.
  VibeChatScope get aiScope {
    final zId = widget.zoneId;
    final parentId = _parentComponentIdForAi;
    if (zId != null && zId.isNotEmpty) {
      final parentLabel = widget.menuSubtitle?.call()?.trim();
      return VibeChatScope(
        componentId: effectiveComponentId,
        label: (parentLabel != null && parentLabel.isNotEmpty)
            ? parentLabel
            : titleLabel,
        zoneId: zId,
        zoneLabel: label,
        parentComponentId: parentId,
      );
    }
    return VibeChatScope(
      componentId: effectiveComponentId,
      label: titleLabel,
      parentComponentId: parentId,
    );
  }

  bool get _canEditWithAi =>
      canEdit && AppearanceScope.controllerOf(context) != null;

  Future<void> _openAiWithScope() async {
    if (!mounted) return;
    await VibeChatDialog.showScoped(context, aiScope);
  }

  /// Whether this slot's label has been customized by the user.
  bool get hasCustomLabel =>
      (_instance?.overridden ?? false) || _localLabel != null;

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
    final currentLabel = titleLabel;
    final text = TextEditingController(text: currentLabel);
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
      if (value != null && value != currentLabel && mounted) {
        _renameLabel(value);
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
    }
  }

  static final Set<EditorSlotState> _hovered = {};
  static final ValueNotifier<EditorSlotState?> _hoveredTarget = ValueNotifier(
    null,
  );
  static bool _hoveredTargetUpdateScheduled = false;
  static final ValueNotifier<EditorSlotState?> _highlightedTarget =
      ValueNotifier(null);
  static final ValueNotifier<EditorSlotState?> _canvasHoveredParent =
      ValueNotifier(null);
  static Offset? _settledPointerPosition;
  static bool _pointerMoveActive = false;

  /// Target currently highlighted from a context menu, banner path segment,
  /// chevron tree popup, or target selector dialog.
  static ValueNotifier<EditorSlotState?> get highlightedTarget =>
      _highlightedTarget;

  /// Parent slot currently hovered directly by the mouse pointer on the canvas.
  static ValueNotifier<EditorSlotState?> get canvasHoveredParent =>
      _canvasHoveredParent;

  static EditorSlotState? get _menuHoveredTarget => _highlightedTarget.value;
  static set _menuHoveredTarget(EditorSlotState? value) {
    if (!identical(_highlightedTarget.value, value)) {
      _highlightedTarget.value = value;
    }
  }

  static bool _recordRealPointerMove(Offset position) {
    final settled = _settledPointerPosition;
    final moved = settled == null || (position - settled).distance > 0.01;
    if (moved && !_pointerMoveActive) {
      _pointerMoveActive = true;
      scheduleMicrotask(() {
        _settledPointerPosition = position;
        _pointerMoveActive = false;
      });
    }
    return moved || _pointerMoveActive;
  }

  /// Records a pointer hover position on the canvas viewport so synthetic
   /// enter/exit events during zoom animations can be distinguished from real
  /// pointer movements.
  static void recordViewportPointerHover(Offset position) {
    final moved = _recordRealPointerMove(position);
    if (moved) {
      scheduleMicrotask(_refreshHoveredTarget);
    }
  }

  /// Clears any parent slot hovered on the canvas.
  static void clearCanvasHoveredParent([EditorSlotState? expected]) {
    if (expected != null && !identical(_canvasHoveredParent.value, expected)) {
      return;
    }
    if (_canvasHoveredParent.value == null) return;
    _canvasHoveredParent.value = null;
    _refreshHoveredTarget(allowCanvasParentUpdate: false);
  }

  /// Explicitly sets or clears the parent slot hovered via its canvas badge.
  static void setCanvasHoveredParent(EditorSlotState? target) {
    if (identical(_canvasHoveredParent.value, target)) return;
    _canvasHoveredParent.value = target;
    _refreshHoveredTarget(allowCanvasParentUpdate: false);
  }

  static bool _menuOpen = false;
  static bool _openingMenuThisTurn = false;
  static int _menuGeneration = 0;
  static Route<dynamic>? _activeMenuRoute;
  static VoidCallback? _dismissActiveMenu;
  bool _ownsOpenMenu = false;

  /// Closes the currently open editor context menu, if any.
  static void closeActiveMenu() {
    _dismissActiveMenu?.call();
  }

  PointerDownEvent? _sliverDown;
  int _sliverButtons = 0;
  bool _sliverMoved = false;

  int _cachedDepth = 0;
  bool _active = true;

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

  void _setHovered(bool hovered, {Offset? pointerPosition}) {
    final realMove =
        pointerPosition == null || _recordRealPointerMove(pointerPosition);
    if (hovered) {
      _hovered.add(this);
    } else {
      _hovered.remove(this);
      if (realMove && identical(_canvasHoveredParent.value, this)) {
        _canvasHoveredParent.value = null;
      }
    }
    _refreshHoveredTarget(allowCanvasParentUpdate: realMove);
  }

  void _removeHoveredSafely() {
    final wasHovered = _hovered.remove(this);
    final wasMenuTarget = identical(_menuHoveredTarget, this);
    final wasCanvasParent = identical(_canvasHoveredParent.value, this);
    if ((!wasHovered && !wasMenuTarget && !wasCanvasParent) ||
        _hoveredTargetUpdateScheduled) {
      return;
    }
    _hoveredTargetUpdateScheduled = true;
    scheduleMicrotask(() {
      _hoveredTargetUpdateScheduled = false;
      if (identical(_menuHoveredTarget, this) && (!_active || !mounted)) {
        _menuHoveredTarget = null;
      }
      if (identical(_canvasHoveredParent.value, this) &&
          (!_active || !mounted)) {
        _canvasHoveredParent.value = null;
      }
      _refreshHoveredTarget(allowCanvasParentUpdate: false);
    });
  }

  /// Highlights [target] with the editor selection outline (used when hovering
  /// entries in the context menu or target selector dialogs).
  static void setHighlightedTarget(EditorSlotState? target) {
    if (target != null &&
        (!target.mounted ||
            !(StyleEditScope.controllerOf(target.context)?.value ?? false))) {
      return;
    }
    if (identical(_menuHoveredTarget, target)) return;
    _menuHoveredTarget = target;
    if (target != null) {
      _canvasHoveredParent.value = null;
    }
    _refreshHoveredTarget(allowCanvasParentUpdate: false);
  }

  /// Clears the highlighted target if it matches [expected] (or unconditionally
  /// when [expected] is `null`).
  static void clearHighlightedTarget([EditorSlotState? expected]) {
    if (expected != null && !identical(_menuHoveredTarget, expected)) return;
    if (_menuHoveredTarget == null) return;
    _menuHoveredTarget = null;
    _refreshHoveredTarget(allowCanvasParentUpdate: false);
  }

  static bool _hoverTargetListenerAdded = false;

  static void _ensureHoverTargetListener() {
    if (_hoverTargetListenerAdded) return;
    _hoverTargetListenerAdded = true;
    EditorSelectionRegion.hoverTarget.addListener(_refreshHoveredTarget);
    LayoutSelection.focus.addListener(_onSelectionFocusChanged);
  }

  static void _onSelectionFocusChanged() {
    final parent = _canvasHoveredParent.value;
    if (parent != null &&
        (!parent.mounted ||
            !parent._active ||
            !LayoutSelection.isAncestorOfFocus(parent.context))) {
      _canvasHoveredParent.value = null;
      _refreshHoveredTarget(allowCanvasParentUpdate: false);
    }
  }

  static void _refreshHoveredTarget({bool allowCanvasParentUpdate = true}) {
    _ensureHoverTargetListener();
    final previous = _hoveredTarget.value;
    final menuTarget = _menuHoveredTarget;
    if (menuTarget != null &&
        menuTarget.mounted &&
        menuTarget._active &&
        menuTarget.canEdit) {
      _hoveredTarget.value = menuTarget;
      if (!identical(previous, menuTarget)) {
        EditorSelectionOutline.triggerAnimation();
      }
      return;
    }
    EditorSlotState? deepest;
    var maxDepth = -1;
    for (final state in _hovered) {
      if (!state.mounted || !state._active) continue;
      final depth = state._cachedDepth;
      if (depth > maxDepth) {
        maxDepth = depth;
        deepest = state;
      }
    }
    if (allowCanvasParentUpdate && _pointerMoveActive) {
      final isParent =
          deepest != null &&
          deepest.canEdit &&
          LayoutSelection.isAncestorOfFocus(deepest.context);
      _canvasHoveredParent.value = isParent ? deepest : null;
    }
    final parentTarget = _canvasHoveredParent.value;
    if (parentTarget != null &&
        parentTarget.mounted &&
        parentTarget._active &&
        parentTarget.canEdit &&
        LayoutSelection.isAncestorOfFocus(parentTarget.context)) {
      _hoveredTarget.value = parentTarget;
      if (!identical(previous, parentTarget)) {
        EditorSelectionOutline.triggerAnimation();
      }
      return;
    } else if (parentTarget != null) {
      _canvasHoveredParent.value = null;
    }
    if (EditorSelectionRegion.hoverTarget.value != null) {
      _hoveredTarget.value = null;
      return;
    }
    _hoveredTarget.value = deepest;
    if (deepest != null && !identical(previous, deepest)) {
      EditorSelectionOutline.triggerAnimation();
    }
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

  Widget _menuTitle(
    String label, {
    required EditorMenuDestination? destination,
    TextStyle? style,
    String? tooltip,
    Key? tooltipKey,
  }) {
    final textWidget = Text(
      label,
      style: style ?? Theme.of(context).textTheme.titleSmall,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    final resolvedTooltip = tooltip?.trim();
    final richTooltip = resolvedTooltip != null && resolvedTooltip.isNotEmpty
        ? buildEditorTooltipRichMessage(resolvedTooltip)
        : null;
    return Row(
      children: [
        if (destination != null) ...[
          Tooltip(
            message: destination == EditorMenuDestination.style
                ? 'Ouvre le style'
                : 'Ouvre les paramètres',
            child: Icon(
              destination == EditorMenuDestination.style
                  ? Icons.palette_outlined
                  : Icons.settings_outlined,
              size: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: resolvedTooltip != null && resolvedTooltip.isNotEmpty
              ? Tooltip(
                  key: tooltipKey,
                  message: richTooltip == null ? resolvedTooltip : null,
                  richMessage: richTooltip,
                  ignorePointer: true,
                  child: textWidget,
                )
              : textWidget,
        ),
      ],
    );
  }

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

  Widget _menuHover(
    EditorSlotState target,
    Widget child, {
    double minHeight = 40,
  }) => Builder(
    builder: (menuContext) {
      _activeMenuRoute ??= ModalRoute.of(menuContext);
      return MouseRegion(
        onEnter: (_) {
          if (!target.mounted ||
              !(StyleEditScope.controllerOf(target.context)?.value ?? false)) {
            return;
          }
          _menuHoveredTarget = target;
          _refreshHoveredTarget();
        },
        onExit: (_) {
          if (!_menuOpen && identical(_menuHoveredTarget, target)) {
            _menuHoveredTarget = null;
            _refreshHoveredTarget();
          }
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ),
      );
    },
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
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void deactivate() {
    _active = false;
    _removeHoveredSafely();
    super.deactivate();
  }

  @override
  void dispose() {
    if (_ownsOpenMenu) {
      _ownsOpenMenu = false;
      _menuOpen = false;
      _openingMenuThisTurn = false;
      _activeMenuRoute = null;
      _dismissActiveMenu = null;
    }
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

  /// Contextual addition levels, from the clicked element to its outermost
  /// editable parent: positions around elements and zones of containers.
  /// [provided] holds actions found below this slot.
  List<ContextualAddLevel> _insertionLevels(List<EditorSlotAction>? provided) {
    final seen = Set<Object>.identity();
    final levels = <ContextualAddLevel>[];
    void collect(Widget widget) {
      if (!seen.add(widget)) return;
      if (widget is EditorSlotAction &&
          widget.enabled &&
          widget.insertion != null) {
        levels.add(widget.insertion!);
      } else if (widget is EditorAddZones) {
        if (widget.group() case final group?) levels.add(group);
      }
    }

    provided?.forEach(collect);
    context.visitAncestorElements((element) {
      collect(element.widget);
      return true;
    });
    return levels;
  }

  List<BehaviorTargetElement> _behaviorTargets(List<(int, Object)> entries) {
    final targets = <BehaviorTargetElement>[];
    final titles = <String, int>{};
    String unique(String title) {
      final count = titles[title] = (titles[title] ?? 0) + 1;
      return switch (count) {
        1 => title,
        2 => '$title (parent)',
        _ => '$title (parent ${count - 1})',
      };
    }

    final appearance = AppearanceScope.controllerOf(context)?.value;

    for (final (index, entry) in entries) {
      if (entry is EditorSlotState) {
        final id = entry.effectiveComponentId;
        final existing = appearance?.behaviorsFor(id) ?? const [];
        targets.add(
          BehaviorTargetElement(
            id: id,
            label: unique(entry.label),
            slot: entry,
            icon:
                entry.widget.menuIcon ??
                entry.componentLabel?.menuIcon ??
                (index == 0 ? Icons.widgets_outlined : Icons.folder_outlined),
            depth: index,
            existingBehaviors: existing,
          ),
        );
      }
    }

    if (targets.isEmpty) {
      final id = effectiveComponentId;
      final existing = appearance?.behaviorsFor(id) ?? const [];
      targets.add(
        BehaviorTargetElement(
          id: id,
          label: label,
          slot: this,
          icon:
              widget.menuIcon ??
              componentLabel?.menuIcon ??
              Icons.widgets_outlined,
          depth: 0,
          existingBehaviors: existing,
        ),
      );
    }

    return targets;
  }

  List<DataTargetElement> _dataTargets(List<(int, Object)> entries) {
    final targets = <DataTargetElement>[];
    final titles = <String, int>{};
    String unique(String title) {
      final count = titles[title] = (titles[title] ?? 0) + 1;
      return switch (count) {
        1 => title,
        2 => '$title (parent)',
        _ => '$title (parent ${count - 1})',
      };
    }

    for (final (index, entry) in entries) {
      if (entry is EditorSlotState && entry.mounted) {
        final id = entry.effectiveComponentId;
        targets.add(
          DataTargetElement(
            id: id,
            label: unique(entry.label),
            slot: entry,
            icon:
                entry.widget.menuIcon ??
                entry.componentLabel?.menuIcon ??
                (index == 0 ? Icons.widgets_outlined : Icons.folder_outlined),
            depth: index,
            extractableTargets: collectExtractableTargetsFromSlot(entry),
            recurringGroups: detectRecurringBlockGroups(entry),
            existingBindings: collectExistingBindingsFromSlot(entry),
          ),
        );
      }
    }

    if (targets.isEmpty && mounted) {
      final id = effectiveComponentId;
      targets.add(
        DataTargetElement(
          id: id,
          label: label,
          slot: this,
          icon:
              widget.menuIcon ??
              componentLabel?.menuIcon ??
              Icons.widgets_outlined,
          depth: 0,
          extractableTargets: collectExtractableTargetsFromSlot(this),
          recurringGroups: detectRecurringBlockGroups(this),
          existingBindings: collectExistingBindingsFromSlot(this),
        ),
      );
    }

    return targets;
  }

  /// Resolves the editable [EditorSlotState] rooted at or enclosing [targetContext].
  static EditorSlotState? resolveFromContext(BuildContext? targetContext) {
    if (targetContext is! Element || !targetContext.mounted) return null;
    if (targetContext is StatefulElement &&
        targetContext.state is EditorSlotState) {
      final state = targetContext.state as EditorSlotState;
      if (state.canEdit) return state;
    }
    EditorSlotState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditorSlotState) {
        final state = element.state as EditorSlotState;
        if (state.canEdit) {
          found = state;
          return;
        }
      }
      element.visitChildren(visit);
    }

    targetContext.visitChildElements(visit);
    if (found != null) return found;
    return targetContext.findAncestorStateOfType<EditorSlotState>();
  }

  /// Opens the context menu for the editable target rooted at [targetContext]
  /// without changing the current selection path.
  static Future<void> openMenuFromContext(
    BuildContext? targetContext,
    Offset globalPosition,
  ) async {
    if (targetContext is! Element || !targetContext.mounted) return;
    if (targetContext is StatefulElement &&
        targetContext.state is EditorSlotState) {
      final state = targetContext.state as EditorSlotState;
      if (state.canEdit) {
        await state.openMenu(globalPosition, selectTarget: false);
        return;
      }
    }
    EditorSlotState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditorSlotState) {
        final state = element.state as EditorSlotState;
        if (state.canEdit) {
          found = state;
          return;
        }
      }
      element.visitChildren(visit);
    }

    targetContext.visitChildElements(visit);
    if (found != null) {
      await found!.openMenu(globalPosition, selectTarget: false);
      return;
    }
    await targetContext.findAncestorStateOfType<EditorSlotState>()?.openMenu(
      globalPosition,
      actions: EditorSlotAction.of(targetContext),
      targetContext: targetContext,
      selectTarget: false,
    );
  }

  /// Opens this slot's menu at a global pointer position.
  Future<void> openMenu(
    Offset globalPosition, {
    List<EditorSlotAction>? actions,
    BuildContext? targetContext,
    bool selectTarget = true,
  }) async {
    if (!mounted ||
        !(StyleEditScope.controllerOf(context)?.value ?? true) ||
        EditorZoom.suppressContextMenu ||
        (EditorZoomScope.controllerOf(context)?.suppressContextMenu ?? false)) {
      return;
    }
    final chain = editableChain;
    final origin = targetContext ?? context;
    if (selectTarget) {
      final callbacks = <VoidCallback>[];
      if (origin is Element) {
        void collectElement(Element element) {
          if (element is StatefulElement) {
            final state = element.state;
            if (state is EditorSlotState &&
                chain.contains(state) &&
                (StyleEditScope.controllerOf(state.context)?.value ?? false) &&
                state.widget.onContextMenu != null) {
              final onContextMenu = state.widget.onContextMenu!;
              callbacks.add(() => onContextMenu(globalPosition));
            }
          } else {
            final widget = element.widget;
            if (widget is EditorSlotAction &&
                widget.enabled &&
                widget.onSelect != null &&
                (StyleEditScope.controllerOf(element)?.value ?? false)) {
              callbacks.add(widget.onSelect!);
            }
          }
        }

        collectElement(origin);
        origin.visitAncestorElements((element) {
          collectElement(element);
          return true;
        });
      } else {
        for (final state in chain) {
          if ((StyleEditScope.controllerOf(state.context)?.value ?? false) &&
              state.widget.onContextMenu != null) {
            final onContextMenu = state.widget.onContextMenu!;
            callbacks.add(() => onContextMenu(globalPosition));
          }
        }
      }
      for (final callback in callbacks.reversed) {
        callback();
      }
      if (origin is Element) {
        final slotStates = <EditorSlotState>[];
        var foundSlotBoundary = false;
        void collectLeaf(Element element) {
          if (foundSlotBoundary) return;
          if (element is StatefulElement) {
            final state = element.state;
            if (state is EditorSlotState && chain.contains(state)) {
              if (state.widget.onContextMenu != null) {
                foundSlotBoundary = true;
                return;
              }
              slotStates.add(state);
            }
          } else {
            final widget = element.widget;
            if ((widget is EditorSlotAction &&
                    widget.enabled &&
                    widget.onSelect != null) ||
                widget is LayoutSelectionScope) {
              foundSlotBoundary = true;
            }
          }
        }

        collectLeaf(origin);
        origin.visitAncestorElements((element) {
          collectLeaf(element);
          return !foundSlotBoundary;
        });
        if (slotStates.length > 1) {
          final deepestLeaf = slotStates.first;
          final leaves = [
            for (final state in slotStates.reversed.skip(1)) state.label,
          ];
          LayoutSelection.setLeafSuffix(
            leaves,
            focusContext: deepestLeaf.context,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              LayoutSelection.setLeafSuffix(
                leaves,
                focusContext: deepestLeaf.mounted ? deepestLeaf.context : null,
              );
            }
          });
        }
      }
    }
    final extraActions = [
      for (final action in actions ?? EditorSlotAction.of(context))
        if (action.enabled) action,
    ];
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
    final hasMenuActions = extraActions.any((action) => !action.inline);
    final insertions = _insertionLevels(actions);
    final behaviorTargets = _behaviorTargets(entries);
    final dataTargets = _dataTargets(entries);
    // Inline actions only render inside an editable entry, never on their own.
    if (entries.isEmpty && !hasMenuActions && insertions.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final bannerGlobalRect = LayoutSelection.bannerBounds?.call();
    final bannerLocal = bannerGlobalRect == null
        ? null
        : Rect.fromPoints(
            overlay.globalToLocal(bannerGlobalRect.topLeft),
            overlay.globalToLocal(bannerGlobalRect.bottomRight),
          );
    Rect? resolveAvoidRect() {
      if (!selectTarget) return null;
      final overlayRect = Offset.zero & overlay.size;
      final candidateContexts = <BuildContext>[
        ?targetContext,
        context,
        ?LayoutSelection.focus.value?.context,
      ];
      Rect? fallbackRect;
      for (final candidate in candidateContexts) {
        if (!candidate.mounted) continue;
        final box = candidate.findRenderObject();
        if (box is RenderBox &&
            box.attached &&
            box.hasSize &&
            !box.size.isEmpty) {
          final rect = Rect.fromPoints(
            overlay.globalToLocal(box.localToGlobal(Offset.zero)),
            overlay.globalToLocal(
              box.localToGlobal(box.size.bottomRight(Offset.zero)),
            ),
          ).intersect(overlayRect);
          if (!rect.isEmpty && rect.isFinite) {
            fallbackRect ??= rect;
            if (rect.width < overlay.size.width * .92 ||
                rect.height < overlay.size.height * .92) {
              return rect;
            }
          }
        }
      }
      return fallbackRect;
    }

    var menuConstraints = const BoxConstraints(minWidth: 420, maxWidth: 620);
    if (!selectTarget && bannerLocal != null) {
      final spaceAbove = bannerLocal.top;
      final spaceBelow = overlay.size.height - bannerLocal.bottom;
      if (spaceBelow >= spaceAbove || spaceBelow >= 220) {
        final minTop = bannerLocal.bottom + 6;
        final maxHeight = math.max(120.0, overlay.size.height - minTop - 8);
        menuConstraints = BoxConstraints(
          minWidth: 420,
          maxWidth: 620,
          maxHeight: maxHeight,
        );
      } else {
        final maxBottom = bannerLocal.top - 6;
        final bottomEdge = math.min(position.dy, maxBottom);
        final maxHeight = math.max(120.0, bottomEdge - 8);
        menuConstraints = BoxConstraints(
          minWidth: 420,
          maxWidth: 620,
          maxHeight: maxHeight,
        );
      }
    }
    final colors = Theme.of(context).colorScheme;
    if (_menuOpen) {
      if (_openingMenuThisTurn && selectTarget) return;
      closeActiveMenu();
      if (!mounted) return;
    }
    final navigator = Navigator.of(context);
    final hostRoute = ModalRoute.of(context);
    final generation = ++_menuGeneration;
    _menuOpen = true;
    _openingMenuThisTurn = true;
    _activeMenuRoute = null;
    _ownsOpenMenu = true;
    scheduleMicrotask(() {
      if (_menuGeneration == generation) {
        _openingMenuThisTurn = false;
      }
    });
    _dismissActiveMenu = () {
      if (_menuGeneration != generation) return;
      _menuGeneration++;
      _ownsOpenMenu = false;
      _menuOpen = false;
      _openingMenuThisTurn = false;
      final route = _activeMenuRoute;
      _activeMenuRoute = null;
      _dismissActiveMenu = null;
      _menuHoveredTarget = null;
      _refreshHoveredTarget();
      if (!navigator.mounted) return;
      if (route != null) {
        if (route.isActive) {
          navigator.removeRoute(route);
        }
      } else if (hostRoute != null
          ? !hostRoute.isCurrent
          : navigator.canPop()) {
        navigator.pop();
      }
    };
    Object? selected;
    try {
      selected = await _showEditorContextMenuDialog<Object>(
        context: context,
        initialPosition: position,
        bannerLocal: bannerLocal,
        avoidRectResolver: selectTarget ? resolveAvoidRect : null,
        constraints: menuConstraints,
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
        onRouteCreated: (route) => _activeMenuRoute = route,
        items: [
          if (insertions.isNotEmpty || canEdit) ...[
            PopupMenuItem<Future<void> Function()>(
              height: 28,
              key: const ValueKey('style-menu-insert'),
              value: insertions.isNotEmpty
                  ? () => showContextualAddWizard(
                      context,
                      insertions,
                      target: context,
                    )
                  : () => showComponentBehaviorWizard(
                      context: context,
                      targets: behaviorTargets,
                      target: context,
                    ),
              padding: EdgeInsets.zero,
              child: _menuHover(
                this,
                minHeight: 28,
                Row(
                  children: [
                    if (insertions.isNotEmpty) ...[
                      Expanded(
                        flex: 5,
                        child: Tooltip(
                          message: 'Ajouter un composant',
                          child: InkWell(
                            key: const ValueKey('style-menu-insert-component'),
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => Navigator.of(context)
                                .pop<Future<void> Function()>(
                                  () => showContextualAddWizard(
                                    context,
                                    insertions,
                                    target: context,
                                  ),
                                ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 3,
                                horizontal: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: colors.primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.add,
                                      size: 14,
                                      color: colors.onPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: _menuTitle(
                                      'Composant…',
                                      destination: null,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      flex: 5,
                      child: Tooltip(
                        message: 'Ajouter un comportement',
                        child: InkWell(
                          key: const ValueKey('style-menu-behavior'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () =>
                              Navigator.of(context)
                                  .pop<Future<void> Function()>(
                                    () => showComponentBehaviorWizard(
                                      context: context,
                                      targets: behaviorTargets,
                                      target: context,
                                    ),
                                  ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 3,
                              horizontal: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: colors.tertiary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.bolt,
                                    size: 14,
                                    color: colors.onTertiary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: _menuTitle(
                                    'Comportement…',
                                    destination: null,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 5,
                      child: Tooltip(
                        message: 'Extraire ou gérer les données JSON',
                        child: InkWell(
                          key: const ValueKey('style-menu-data'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => Navigator.of(context)
                              .pop<Future<void> Function()>(
                                () => showComponentDataWizard(
                                  context: context,
                                  targets: dataTargets,
                                  target: context,
                                ),
                              ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 3,
                              horizontal: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: colors.secondary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.data_object,
                                    size: 14,
                                    color: colors.onSecondary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: _menuTitle(
                                    'Donnée…',
                                    destination: null,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasMenuActions || entries.isNotEmpty)
              const PopupMenuDivider(height: 8),
          ],
          for (final (actionIndex, action)
              in extraActions.where((action) => !action.inline).indexed) ...[
            if (actionIndex > 0) const PopupMenuDivider(height: 4),
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
                      child: _menuTitle(
                        action.label,
                        destination: action.destination,
                        tooltip: action.tooltip,
                        tooltipKey: ValueKey(
                          'style-menu-action-tooltip-${action.label}',
                        ),
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
            const PopupMenuDivider(height: 4),
          for (final (entryIndex, (index, entry)) in entries.indexed) ...[
            if (entryIndex > 0) const PopupMenuDivider(height: 4),
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
                          child: _menuTitle(
                            entry.label,
                            destination: entry.destination,
                            tooltip: entry.tooltip,
                            tooltipKey: ValueKey(
                              'style-menu-entry-tooltip-${entry.label}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (entry case final EditorSlotState state when state.mounted)
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
                              _menuTitle(
                                state.titleLabel,
                                destination: state.widget.onEdit == null
                                    ? null
                                    : state.widget.menuDestination,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                tooltip:
                                    state.widget.menuTooltip?.call() ??
                                    state.widget.axisAction?.call().flowTooltip,
                                tooltipKey: ValueKey(
                                  'style-menu-tooltip-${state.label}',
                                ),
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
                                                    : state.widget.label)))
                                  case final subtitle?
                                  when subtitle != state.titleLabel &&
                                      !(state.widget.menuSubtitle == null &&
                                          state.widget.menuType != null &&
                                          state.widget.menuTitle != null &&
                                          subtitle == state.widget.label))
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
                                  state.widget.menuTitle != null &&
                                  state.widget.label != null &&
                                  state.widget.label != state.titleLabel)
                                Text(
                                  state.widget.label!,
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
                            state.widget.axisAction != null) ...[
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
                          if (state.widget.axisAction!().onEditFlow
                              case final editFlow?)
                            IconButton(
                              key: ValueKey(
                                'style-menu-zone-flow-${state.label}',
                              ),
                              tooltip:
                                  state.widget.axisAction!().flowTooltip ??
                                  'Taille et flux de la zone ${state.widget.axisAction!().zoneLabel}',
                              icon: const Icon(Icons.straighten),
                              style: _menuIconButtonStyle(context),
                              onPressed: () => Navigator.of(context)
                                  .pop<Future<void> Function()>(() async {
                                    if (state.mounted) {
                                      await EditorWizardNavigation.openWithTab(
                                        EditorWizardTab.dimensions,
                                        editFlow,
                                      );
                                    }
                                  }),
                            ),
                        ],
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
                              tooltip: action.tooltip ?? action.label,
                              icon: const Icon(Icons.straighten),
                              style: _menuIconButtonStyle(context),
                              onPressed: () => Navigator.of(context)
                                  .pop<Future<void> Function()>(() async {
                                    if (state.mounted &&
                                        state.widget.onEdit != null &&
                                        EditorWizardNavigation.findDirectSlotSizeAction(
                                              state.context,
                                            )?.label ==
                                            action.label) {
                                      await state.openEditor(
                                        initialTab: EditorWizardTab.dimensions,
                                        dimensionDelegate: action
                                            .dimensionDelegateBuilder
                                            ?.call(),
                                      );
                                    } else {
                                      await EditorWizardNavigation.openWithTab(
                                        EditorWizardTab.dimensions,
                                        action.onEdit,
                                        delegate: action
                                            .dimensionDelegateBuilder
                                            ?.call(),
                                      );
                                    }
                                  }),
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
                        if ((
                              [
                                for (final action
                                    in inlineActions[state] ??
                                        const <EditorSlotAction>[])
                                  ...action.wrapActions,
                              ],
                              (StyleEditScope.controllerOf(state.context)
                                          ?.value ??
                                      false)
                                  ? state.widget.wrapChildrenActions
                                  : const <EditorSlotWrapAction>[],
                              state.canEdit
                                  ? collectExtractableTargetsFromSlot(state)
                                  : const <ExtractableComponentTarget>[],
                              state._canEditWithAi,
                            )
                            case (
                              final wrapActions,
                              final wrapChildrenActions,
                              final extractableTargets,
                              final canEditWithAi,
                            )
                            when wrapActions.isNotEmpty ||
                                wrapChildrenActions.isNotEmpty ||
                                extractableTargets.isNotEmpty ||
                                canEditWithAi)
                          MenuAnchor(
                            consumeOutsideTap: true,
                            menuChildren: [
                              if (wrapActions.isNotEmpty)
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
                              if (wrapChildrenActions.isNotEmpty)
                                SubmenuButton(
                                  leadingIcon: const Icon(Icons.wrap_text),
                                  menuChildren: [
                                    for (final action in wrapChildrenActions)
                                      MenuItemButton(
                                        leadingIcon: Icon(action.icon),
                                        onPressed: () => Navigator.of(context)
                                            .pop<Future<void> Function()>(
                                              action.onSelected,
                                            ),
                                        child: Text(action.label),
                                      ),
                                  ],
                                  child: const Text(
                                    'Envelopper les enfants dans…',
                                  ),
                                ),
                              if (extractableTargets.isNotEmpty)
                                MenuItemButton(
                                  key: ValueKey(
                                    'style-menu-extract-super-values-${state.label}',
                                  ),
                                  leadingIcon: const Icon(Icons.data_object),
                                  onPressed: () => Navigator.of(context)
                                      .pop<Future<void> Function()>(() async {
                                        if (!state.mounted) return;
                                        final latest =
                                            collectExtractableTargetsFromSlot(
                                              state,
                                            );
                                        if (latest.isEmpty) return;
                                        await SuperValueJsonExtractDialog.show(
                                          state.context,
                                          targets: latest,
                                          sourceLabel: state.titleLabel,
                                          target: state.context,
                                          rootSlot: state,
                                        );
                                      }),
                                  child: const Text('Extraire & lier en JSON…'),
                                ),
                              if (canEditWithAi)
                                MenuItemButton(
                                  key: ValueKey('style-menu-ai-${state.label}'),
                                  leadingIcon: const Icon(
                                    Icons.auto_awesome_outlined,
                                  ),
                                  onPressed: () => Navigator.of(context)
                                      .pop<Future<void> Function()>(
                                        state._openAiWithScope,
                                      ),
                                  child: const Text('Modifier avec l’IA…'),
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
      if (_menuGeneration == generation) {
        _ownsOpenMenu = false;
        _menuOpen = false;
        _openingMenuThisTurn = false;
        _activeMenuRoute = null;
        _dismissActiveMenu = null;
        _menuHoveredTarget = null;
        _refreshHoveredTarget();
      } else {
        _ownsOpenMenu = false;
      }
    }
    if (!mounted) return;
    if (selected is EditorSlotState && selected.mounted) {
      await selected.openEditor();
    } else if (selected is Future<void> Function()) {
      await selected();
    }
  }

  /// Opens this slot's specialized editor, when supplied.
  Future<void> openEditor({
    EditorWizardTab? initialTab,
    EditorDimensionDelegate? dimensionDelegate,
  }) async {
    final callback = widget.onEdit;
    if (callback != null) {
      await EditorWizardNavigation.openWithTab(
        initialTab,
        callback,
        delegate: dimensionDelegate,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editMode = StyleEditScope.controllerOf(context);
    final isSliver = SliverSlotScope.isSliver(context);
    final inEditMode = editMode?.value ?? false;
    final appearance = AppearanceScope.controllerOf(context)?.value;
    final behaviors =
        appearance?.behaviorsFor(effectiveComponentId) ?? const [];
    final clickBehaviors = behaviors
        .where((b) => b.enabled && b.trigger == BehaviorTrigger.click)
        .toList();
    final hasClickBehaviors = !inEditMode && clickBehaviors.isNotEmpty;

    if (isSliver) {
      final Widget child =
          widget.child ?? const SliverToBoxAdapter(child: SizedBox.shrink());
      if (canEdit && editMode != null) {
        _cachedDepth = _depth;
      } else if (_hovered.contains(this)) {
        _removeHoveredSafely();
      }
      final accentColor = AppearanceScope.of(context).accent
          .withValues(alpha: .85);
      return ValueListenableBuilder<EditorSlotState?>(
        valueListenable: _hoveredTarget,
        builder: (context, target, child) => ListenableBuilder(
          listenable: Listenable.merge([
            EditorOverlayVisibility.openDialogs,
            EditorSelectionRegion.hoverTarget,
            _canvasHoveredParent,
            LayoutSelection.focus,
            LayoutSelection.path,
          ]),
          builder: (context, child) {
            final isEmphasizedHighlight =
                identical(_menuHoveredTarget, this) ||
                identical(_canvasHoveredParent.value, this);
            final isSelectedLeaf =
                canEdit &&
                editMode != null &&
                EditorOverlayVisibility.openDialogs.value == 0 &&
                LayoutSelection.isLeafFocus(this.context);
            final showOutline =
                canEdit &&
                editMode != null &&
                (EditorOverlayVisibility.openDialogs.value == 0 ||
                    isEmphasizedHighlight) &&
                identical(target, this) &&
                (EditorSelectionRegion.hoverTarget.value == null ||
                    isEmphasizedHighlight);
            return SliverPointerRegion(
              cursor: hasClickBehaviors
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              onEnter: canEdit && editMode != null
                  ? (event) => _setHovered(true, pointerPosition: event.position)
                  : null,
              onHover: canEdit && editMode != null
                  ? (event) => _setHovered(true, pointerPosition: event.position)
                  : null,
              onExit: canEdit && editMode != null
                  ? (event) =>
                        _setHovered(false, pointerPosition: event.position)
                  : null,
              onPointerDown: (event) {
                _sliverDown = event;
                _sliverButtons = event.buttons;
                _sliverMoved = false;
              },
              onPointerMove: (event) {
                final down = _sliverDown;
                if (down != null &&
                    down.pointer == event.pointer &&
                    (event.position - down.position).distance > kTouchSlop) {
                  _sliverMoved = true;
                }
              },
              onPointerUp: (event) async {
                final down = _sliverDown;
                final buttons = _sliverButtons;
                final moved = _sliverMoved;
                _sliverDown = null;
                _sliverButtons = 0;
                _sliverMoved = false;
                if (down == null ||
                    down.pointer != event.pointer ||
                    moved ||
                    (event.position - down.position).distance > kTouchSlop) {
                  return;
                }
                if (buttons == kSecondaryMouseButton && canEdit) {
                  await openMenu(event.position);
                } else if (buttons == kPrimaryButton && hasClickBehaviors) {
                  for (final b in clickBehaviors) {
                    await b.execute(context);
                  }
                }
              },
              onPointerCancel: (_) {
                _sliverDown = null;
                _sliverButtons = 0;
                _sliverMoved = false;
              },
              foregroundPainter: showOutline
                  ? EditorSelectionOutline(
                      color: accentColor,
                      radius: widget.outlineRadius,
                      emphasized: isEmphasizedHighlight,
                      label: titleLabel,
                    )
                  : isSelectedLeaf
                  ? EditorSelectionBorderPainter(
                      color: AppearanceScope.of(context).accent,
                      dashed: false,
                      strokeWidth: 2.0,
                      fillOpacity: 0.10,
                      animated:
                          !(MediaQuery.maybeDisableAnimationsOf(context) ??
                              false),
                    )
                  : null,
              child: child,
            );
          },
          child: child,
        ),
        child: child,
      );
    }

    Widget content = widget.child ?? const SizedBox.expand();
    if (canEdit && editMode != null) {
      _cachedDepth = _depth;
      final accentColor = AppearanceScope.of(context).accent
          .withValues(alpha: .85);
      content = MouseRegion(
        onEnter: (event) => _setHovered(true, pointerPosition: event.position),
        onHover: (event) => _setHovered(true, pointerPosition: event.position),
        onExit: (event) => _setHovered(false, pointerPosition: event.position),
        child: ValueListenableBuilder<EditorSlotState?>(
          valueListenable: _hoveredTarget,
          builder: (context, target, child) => ListenableBuilder(
            listenable: Listenable.merge([
              EditorOverlayVisibility.openDialogs,
              EditorSelectionRegion.hoverTarget,
              _canvasHoveredParent,
              LayoutSelection.focus,
              LayoutSelection.path,
            ]),
            builder: (context, child) {
              final isEmphasizedHighlight =
                  identical(_menuHoveredTarget, this) ||
                  identical(_canvasHoveredParent.value, this);
              final isSelectedLeaf =
                  EditorOverlayVisibility.openDialogs.value == 0 &&
                  LayoutSelection.isLeafFocus(this.context);
              final showOutline =
                  (EditorOverlayVisibility.openDialogs.value == 0 ||
                      isEmphasizedHighlight) &&
                  identical(target, this) &&
                  (EditorSelectionRegion.hoverTarget.value == null ||
                      isEmphasizedHighlight);
              return CustomPaint(
                foregroundPainter: showOutline
                    ? EditorSelectionOutline(
                        color: accentColor,
                        radius: widget.outlineRadius,
                        emphasized: isEmphasizedHighlight,
                        label: titleLabel,
                      )
                    : isSelectedLeaf
                    ? EditorSelectionBorderPainter(
                        color: AppearanceScope.of(context).accent,
                        dashed: false,
                        strokeWidth: 2.0,
                        fillOpacity: 0.10,
                        animated:
                            !(MediaQuery.maybeDisableAnimationsOf(context) ??
                                false),
                      )
                    : null,
                child: child,
              );
            },
            child: child,
          ),
          child: RepaintBoundary(child: content),
        ),
      );
    } else if (_hovered.contains(this)) {
      _removeHoveredSafely();
    }

    content = MouseRegion(
      cursor: hasClickBehaviors ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.translucent,
        onTap: hasClickBehaviors
            ? () async {
                for (final b in clickBehaviors) {
                  await b.execute(context);
                }
              }
            : null,
        onSecondaryTapUp: canEdit
            ? (details) => openMenu(details.globalPosition)
            : null,
        child: content,
      ),
    );
    return content;
  }
}

Future<T?> _showEditorContextMenuDialog<T>({
  required BuildContext context,
  required Offset initialPosition,
  required BoxConstraints constraints,
  required Color color,
  required Color surfaceTintColor,
  required Color shadowColor,
  required double elevation,
  required ShapeBorder shape,
  required EdgeInsetsGeometry menuPadding,
  required Clip clipBehavior,
  required List<PopupMenuEntry<T>> items,
  Rect? bannerLocal,
  Rect? Function()? avoidRectResolver,
  ValueChanged<Route<T>>? onRouteCreated,
}) async {
  final navigator = Navigator.of(context);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final zoomController = EditorZoomScope.controllerOf(context);
  final route = _EditorContextMenuRoute<T>(
    themes: themes,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    initialPosition: initialPosition,
    bannerLocal: bannerLocal,
    avoidRectResolver: avoidRectResolver,
    constraints: constraints,
    color: color,
    surfaceTintColor: surfaceTintColor,
    shadowColor: shadowColor,
    elevation: elevation,
    shape: shape,
    menuPadding: menuPadding,
    clipBehavior: clipBehavior,
    zoomController: zoomController,
    items: items,
  );
  onRouteCreated?.call(route);
  final hasZoom =
      zoomController != null &&
      !zoomController.disposed &&
      zoomController.enabled;
  if (hasZoom) {
    zoomController.openContextMenus.value++;
  }
  try {
    return await navigator.push<T>(route);
  } finally {
    if (hasZoom && !zoomController.disposed) {
      zoomController.openContextMenus.value--;
      if (zoomController.openContextMenus.value == 0) {
        zoomController.contextMenuAvailable.value = null;
      }
    }
  }
}

class _EditorContextMenuRoute<T> extends PopupRoute<T> {
  _EditorContextMenuRoute({
    required this.themes,
    required this.barrierLabel,
    required this.initialPosition,
    required this.bannerLocal,
    required this.avoidRectResolver,
    required this.constraints,
    required this.color,
    required this.surfaceTintColor,
    required this.shadowColor,
    required this.elevation,
    required this.shape,
    required this.menuPadding,
    required this.clipBehavior,
    required this.zoomController,
    required this.items,
  });

  final CapturedThemes themes;
  @override
  final String barrierLabel;
  final Offset initialPosition;
  final Rect? bannerLocal;
  final Rect? Function()? avoidRectResolver;
  final BoxConstraints constraints;
  final Color color;
  final Color surfaceTintColor;
  final Color shadowColor;
  final double elevation;
  final ShapeBorder shape;
  final EdgeInsetsGeometry menuPadding;
  final Clip clipBehavior;
  final EditorZoomController? zoomController;
  final List<PopupMenuEntry<T>> items;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    _EditorContextMenuDialog<T>(
      animation: animation,
      initialPosition: initialPosition,
      bannerLocal: bannerLocal,
      avoidRectResolver: avoidRectResolver,
      constraints: constraints,
      color: color,
      surfaceTintColor: surfaceTintColor,
      shadowColor: shadowColor,
      elevation: elevation,
      shape: shape,
      menuPadding: menuPadding,
      clipBehavior: clipBehavior,
      zoomController: zoomController,
      items: items,
    ),
  );
}

class _EditorContextMenuDialog<T> extends StatefulWidget {
  const _EditorContextMenuDialog({
    required this.animation,
    required this.initialPosition,
    required this.bannerLocal,
    required this.avoidRectResolver,
    required this.constraints,
    required this.color,
    required this.surfaceTintColor,
    required this.shadowColor,
    required this.elevation,
    required this.shape,
    required this.menuPadding,
    required this.clipBehavior,
    required this.zoomController,
    required this.items,
  });

  final Animation<double> animation;
  final Offset initialPosition;
  final Rect? bannerLocal;
  final Rect? Function()? avoidRectResolver;
  final BoxConstraints constraints;
  final Color color;
  final Color surfaceTintColor;
  final Color shadowColor;
  final double elevation;
  final ShapeBorder shape;
  final EdgeInsetsGeometry menuPadding;
  final Clip clipBehavior;
  final EditorZoomController? zoomController;
  final List<PopupMenuEntry<T>> items;

  @override
  State<_EditorContextMenuDialog<T>> createState() =>
      _EditorContextMenuDialogState<T>();
}

class _EditorContextMenuDialogState<T>
    extends State<_EditorContextMenuDialog<T>> {
  final _viewportKey = GlobalKey();
  late Offset _position = widget.initialPosition;
  bool _dragged = false;
  late final Rect? _initialAvoidRect = widget.avoidRectResolver?.call();
  late _ContextMenuDialogLayout _layout = _ContextMenuDialogLayout(
    position: _position,
    dragged: _dragged,
    bannerLocal: widget.bannerLocal,
    avoidRect: _initialAvoidRect,
    menuConstraints: widget.constraints,
  );
  ZoomToolbarLayout _zoomToolbarLayout = ZoomToolbarLayout(null);

  void _syncZoomAvailable() {
    final zoom = widget.zoomController;
    if (zoom == null ||
        zoom.disposed ||
        !zoom.enabled ||
        zoom.dialog.value != null ||
        widget.avoidRectResolver == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          zoom.disposed ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final box = _viewportKey.currentContext?.findRenderObject();
      final available = _layout.availableViewport;
      if (box is! RenderBox || !box.hasSize || available == null) return;
      final screen = Rect.fromPoints(
        box.localToGlobal(available.topLeft),
        box.localToGlobal(available.bottomRight),
      );
      if (zoom.contextMenuAvailable.value != screen) {
        zoom.contextMenuAvailable.value = screen;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final zoom = widget.zoomController;
    final showZoomToolbar =
        zoom != null &&
        !zoom.disposed &&
        zoom.enabled &&
        zoom.dialog.value == null;
    if (!_dragged) {
      _layout = _ContextMenuDialogLayout(
        position: _position,
        dragged: _dragged,
        bannerLocal: widget.bannerLocal,
        avoidRect: _initialAvoidRect ?? widget.avoidRectResolver?.call(),
        menuConstraints: widget.constraints,
      );
    }
    _syncZoomAvailable();
    final dialogCard = FadeTransition(
      opacity: CurvedAnimation(parent: widget.animation, curve: Curves.easeOut),
      child: MouseRegion(
        onExit: (_) => EditorSlotState.clearHighlightedTarget(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) => zoom?.handlePointerSignal(event),
          child: Material(
            key: const ValueKey('editor-context-menu-dialog'),
            color: widget.color,
            surfaceTintColor: widget.surfaceTintColor,
            shadowColor: widget.shadowColor,
            elevation: widget.elevation,
            shape: widget.shape,
            clipBehavior: widget.clipBehavior,
            child: IntrinsicWidth(
              stepWidth: 56.0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      key: const ValueKey('editor-context-menu-drag'),
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onPanUpdate: (details) => setState(() {
                        _dragged = true;
                        _position = _layout.resolvedPosition + details.delta;
                        _layout = _ContextMenuDialogLayout(
                          position: _position,
                          dragged: _dragged,
                          bannerLocal: widget.bannerLocal,
                          avoidRect: null,
                          menuConstraints: widget.constraints,
                        );
                      }),
                      child: ColoredBox(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: .45,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.drag_indicator,
                                size: 16,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Center(
                                  child: Container(
                                    width: 32,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: colors.onSurfaceVariant.withValues(
                                        alpha: .35,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                key: const ValueKey(
                                  'editor-context-menu-close',
                                ),
                                tooltip: 'Fermer',
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 24,
                                  height: 24,
                                ),
                                color: colors.onSurfaceVariant,
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 1,
                    child: ColoredBox(
                      color: colors.outlineVariant.withValues(alpha: .4),
                    ),
                  ),
                  Flexible(
                    child: Semantics(
                      scopesRoute: true,
                      namesRoute: true,
                      explicitChildNodes: true,
                      role: SemanticsRole.menu,
                      child: SingleChildScrollView(
                        padding: widget.menuPadding,
                        child: ListBody(
                          children: [
                            for (final item in widget.items)
                              Builder(builder: (_) => item),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Stack(
      key: _viewportKey,
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if ((event.buttons & kSecondaryMouseButton) != 0) {
                zoom?.handlePointerDown(event);
              }
            },
            onPointerMove: (event) {
              if ((event.buttons & kSecondaryMouseButton) != 0) {
                zoom?.handlePointerMove(event);
              }
            },
            onPointerUp: (event) => zoom?.handlePointerUp(event),
            onPointerCancel: (event) => zoom?.handlePointerCancel(event),
            onPointerSignal: (event) => zoom?.handlePointerSignal(event),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        if (showZoomToolbar)
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _zoomToolbarLayout = ZoomToolbarLayout(
                zoom.toolbarPosition,
              ),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal: zoom.handlePointerSignal,
                child: Material(
                  key: const ValueKey('editor-zoom-toolbar'),
                  type: MaterialType.card,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  child: ValueListenableBuilder<double>(
                    valueListenable: zoom.scale,
                    builder: (context, currentScale, _) =>
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: EditorZoomToolbarContent(
                            scale: currentScale,
                            onScaleChanged: zoom.setScale,
                            onDrag: (details) => setState(() {
                              final nextPos =
                                  _zoomToolbarLayout.resolvedPosition +
                                  details.delta;
                              zoom.toolbarPosition = nextPos;
                              _zoomToolbarLayout = ZoomToolbarLayout(nextPos);
                            }),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: CustomSingleChildLayout(delegate: _layout, child: dialogCard),
        ),
      ],
    );
  }
}

class _ContextMenuDialogLayout extends SingleChildLayoutDelegate {
  _ContextMenuDialogLayout({
    required this.position,
    required this.dragged,
    required this.bannerLocal,
    required this.avoidRect,
    required this.menuConstraints,
  }) : resolvedPosition = position;

  final Offset position;
  final bool dragged;
  final Rect? bannerLocal;
  final Rect? avoidRect;
  final BoxConstraints menuConstraints;
  Offset resolvedPosition;
  Rect? availableViewport;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = math.min(menuConstraints.maxWidth, constraints.maxWidth);
    final minWidth = math.min(menuConstraints.minWidth, maxWidth);
    final maxHeight = dragged
        ? math.max(120.0, constraints.maxHeight - 16.0)
        : math.min(
            menuConstraints.maxHeight,
            math.max(120.0, constraints.maxHeight - 16.0),
          );
    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    if (dragged) {
      final maxX = math.max(0.0, size.width - childSize.width);
      final maxY = math.max(0.0, size.height - childSize.height);
      resolvedPosition = Offset(
        position.dx.clamp(0.0, maxX),
        position.dy.clamp(0.0, maxY),
      );
      return resolvedPosition;
    }
    const margin = 8.0;
    const gap = 12.0;
    final maxX = math.max(margin, size.width - childSize.width - margin);
    var minY = margin;
    var maxY = math.max(margin, size.height - childSize.height - margin);
    var desiredX = position.dx;
    var desiredY = position.dy;
    if (avoidRect == null && bannerLocal != null) {
      final banner = bannerLocal!;
      final spaceAbove = banner.top;
      final spaceBelow = size.height - banner.bottom;
      if (spaceBelow >= spaceAbove || spaceBelow >= 220) {
        minY = banner.bottom + 6;
        maxY = math.max(minY, size.height - childSize.height - margin);
        desiredY = math.max(position.dy, minY);
      } else {
        final maxBottom = banner.top - 6;
        maxY = math.max(margin, maxBottom - childSize.height);
        desiredY = math.min(position.dy, maxBottom) - childSize.height;
      }
    } else if (avoidRect case final rawTarget?) {
      if (bannerLocal case final banner? when banner.top < 120) {
        minY = math.max(minY, banner.bottom + 6);
        maxY = math.max(minY, size.height - childSize.height - margin);
      }
      final screenRect = Offset.zero & size;
      final target = rawTarget.intersect(screenRect);
      if (!target.isEmpty &&
          (target.width < size.width * .92 ||
              target.height < size.height * .92)) {
        final alignedY = target.top.clamp(minY, maxY);
        final alignedX = target.left.clamp(margin, maxX);
        final horizontalCandidates = <Offset>[
          if (target.right + gap + childSize.width <= size.width - margin)
            Offset(target.right + gap, alignedY),
          if (target.left - gap - childSize.width >= margin)
            Offset(target.left - gap - childSize.width, alignedY),
        ];
        final verticalCandidates = <Offset>[
          if (target.bottom + gap + childSize.height <= size.height - margin)
            Offset(alignedX, target.bottom + gap),
          if (target.top - gap - childSize.height >= minY)
            Offset(alignedX, target.top - gap - childSize.height),
        ];
        final candidates = horizontalCandidates.isNotEmpty
            ? horizontalCandidates
            : verticalCandidates;
        if (candidates.isNotEmpty) {
          Offset? best;
          var bestDist = double.infinity;
          for (final candidate in candidates) {
            final dist = (candidate - position).distanceSquared;
            if (dist < bestDist) {
              bestDist = dist;
              best = candidate;
            }
          }
          desiredX = best!.dx;
          desiredY = best.dy;
        } else {
          final spaceRight = size.width - margin - target.right;
          final spaceLeft = target.left - margin;
          desiredX = spaceRight >= spaceLeft ? maxX : margin;
          desiredY = alignedY;
        }
      }
    }
    final dx = desiredX.clamp(margin, maxX);
    final dy = desiredY.clamp(minY, maxY);
    resolvedPosition = Offset(dx, dy);
    if (avoidRect case final target?) {
      final dialogRect = resolvedPosition & childSize;
      final candidateViewports = <Rect>[
        Rect.fromLTWH(0, 0, math.max(0.0, dialogRect.left - gap), size.height),
        Rect.fromLTWH(
          math.min(size.width, dialogRect.right + gap),
          0,
          math.max(0.0, size.width - dialogRect.right - gap),
          size.height,
        ),
        Rect.fromLTWH(0, 0, size.width, math.max(0.0, dialogRect.top - gap)),
        Rect.fromLTWH(
          0,
          math.min(size.height, dialogRect.bottom + gap),
          size.width,
          math.max(0.0, size.height - dialogRect.bottom - gap),
        ),
      ];
      Rect? bestViewport;
      var bestOverlapArea = -1.0;
      var bestTotalArea = -1.0;
      for (final viewport in candidateViewports) {
        if (viewport.width < 80 || viewport.height < 80) continue;
        final overlap = viewport.intersect(target);
        final overlapArea = overlap.isEmpty
            ? 0.0
            : overlap.width * overlap.height;
        final totalArea = viewport.width * viewport.height;
        if (overlapArea > bestOverlapArea ||
            (overlapArea == bestOverlapArea && totalArea > bestTotalArea)) {
          bestOverlapArea = overlapArea;
          bestTotalArea = totalArea;
          bestViewport = viewport;
        }
      }
      availableViewport = bestViewport;
    }
    return resolvedPosition;
  }

  @override
  bool shouldRelayout(_ContextMenuDialogLayout oldDelegate) =>
      position != oldDelegate.position ||
      dragged != oldDelegate.dragged ||
      bannerLocal != oldDelegate.bannerLocal ||
      avoidRect != oldDelegate.avoidRect ||
      menuConstraints != oldDelegate.menuConstraints;
}
