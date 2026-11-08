/// Wrapper d'édition universel ([EditorSlot]) autour d'un slot de composant.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragStartBehavior, kPrimaryButton, kSecondaryMouseButton, kTouchSlop;
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:material_ui/material_ui.dart';

import '../../../theme/appearance.dart';
import '../../../theme/appearance_slot.dart';
import '../../../theme/container_style.dart';
import '../../../models/component_behavior.dart';
import '../../../models/component_config.dart';
import '../../../models/native_component_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../models/super_table_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../services/codegen/dart_code_generator.dart';
import '../../../services/pages/editor_page_graph.dart';
import '../../../services/appearance/appearance_store.dart';
import '../../../models/super_renderer_config.dart';
import '../../../super_app.dart';
import '../../appearance/appearance_transfer_dialog.dart';
import '../../components/behavior_event_listener.dart';
import '../../components/component_tooltip.dart';
import '../../components/super_component.dart';
import '../../components/super_layout/layout_selection.dart';
import '../../components/super_layout/slot_implementation.dart';
import '../../components/super_layout/super_layout.dart';
import '../../components/super_layout/zone_axis_button.dart';
import '../../components/super_list_view.dart';
import '../../components/super_tab.dart';
import '../../components/super_table.dart';
import '../../components/super_tree_view.dart';
import '../addition/contextual_add.dart';
import '../addition/insertion_plan.dart';
import '../ai/vibe_chat_dialog.dart';
import '../behaviors/component_behavior_editor.dart';
import 'editable_surface.dart';
import 'editor_context_menu.dart';
import 'editor_selection_region.dart';
import 'provided_slot_scope.dart';
import '../dialogs/component_export_config_dialog.dart';
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

part 'editor_slot_export.dart';
part 'editor_slot_targets.dart';
part 'editor_slot_menu.dart';
part 'editor_context_menu_dialog.dart';

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
  static const IconData scrollIndicatorIcon = Icons.swap_vert_circle_outlined;
  static const IconData fixedHeightIndicatorIcon = Icons.height;
  static const IconData fixedWidthIndicatorIcon = Icons.height;

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
    this.scrollable = false,
    this.fixedHeight = false,
    this.fixedWidth = false,
    this.identity,
    this.outlineRadius = 0,
    this.onRemoveChild,
    this.wrapChildrenActions = const [],
    this.eventData,
    this.behaviors,
    this.eventComponentType = 'component',
    this.exportConfig,
    super.key,
  });

  final Widget? child;

  /// Configuration courante du composant pour « Exporter le contenu... »
  /// lorsqu'elle n'est ni persistee ni geree par un controleur du registre
  /// (composant declare en code).
  final ComponentConfig Function()? exportConfig;

  /// Comportements explicites ; `null` utilise ceux de l'apparence.
  final List<ComponentBehavior>? behaviors;

  /// Instantane runtime fourni par l'instance, jamais par un registre partage.
  final Map<String, Object?> Function()? eventData;

  /// Type du composant utilise dans l'enveloppe des evenements.
  final String eventComponentType;
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
  final bool scrollable;
  final bool fixedHeight;
  final bool fixedWidth;

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

/// État interne de [EditorSlot] coordonnant le glisser-déposer, le menu contextuel et le redimensionnement.
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

  /// Scope descriptor targeting this component or container zone for AI edits.
  VibeChatScope get aiScope => _buildAiScope();

  /// Calcule l'export contextuel de ce slot (composant ou zone et descendants).
  ///
  /// Lève une [FormatException] si la cible n'est pas exportable.
  EditorFragmentExport buildContentExport() => _buildContentExportImpl();

  /// Génère le code Dart correspondant au contenu de ce slot.
  String buildDartContentExport([
    EditorFragmentExport? export,
    bool decomposeComponents = false,
  ]) => _buildDartContentExportImpl(export, decomposeComponents);

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
            !LayoutSelection.isStrictParentOfSelected(parent.context))) {
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
          LayoutSelection.isStrictParentOfSelected(deepest.context);
      _canvasHoveredParent.value = isParent ? deepest : null;
    }
    final parentTarget = _canvasHoveredParent.value;
    if (parentTarget != null &&
        parentTarget.mounted &&
        parentTarget._active &&
        parentTarget.canEdit &&
        LayoutSelection.isStrictParentOfSelected(parentTarget.context)) {
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
  List<EditorSlotState> get editableChain => _computeEditableChain();

  /// Resolves the editable [EditorSlotState] rooted at or enclosing [targetContext].
  static EditorSlotState? resolveFromContext(
    BuildContext? targetContext, {
    String? preferredId,
  }) => _resolveEditorSlotFromContext(targetContext, preferredId: preferredId);

  /// Opens the context menu for the editable target rooted at [targetContext]
  /// without changing the current selection path.
  static Future<void> openMenuFromContext(
    BuildContext? targetContext,
    Offset globalPosition,
  ) => _openEditorMenuFromContext(targetContext, globalPosition);

  /// Opens this slot's menu at a global pointer position.
  Future<void> openMenu(
    Offset globalPosition, {
    List<EditorSlotAction>? actions,
    BuildContext? targetContext,
    bool selectTarget = true,
  }) => _openSlotMenu(
    globalPosition,
    actions: actions,
    targetContext: targetContext,
    selectTarget: selectTarget,
  );

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

  /// Keeps the child's element when the edit wrappers are added or removed.
  final GlobalKey _childKey = GlobalKey();

  static final Listenable _paintListenable = Listenable.merge([
    _hoveredTarget,
    EditorOverlayVisibility.openDialogs,
    EditorSelectionRegion.hoverTarget,
    _highlightedTarget,
    _canvasHoveredParent,
    LayoutSelection.highlightedSlotId,
    LayoutSelection.focus,
    LayoutSelection.path,
  ]);

  @override
  Widget build(BuildContext context) {
    final editMode = StyleEditScope.controllerOf(context);
    final isSliver = SliverSlotScope.isSliver(context);
    final inEditMode = editMode?.value ?? false;
    final appearance = AppearanceScope.controllerOf(context)?.value;
    final behaviors =
        widget.behaviors ??
        appearance?.behaviorsFor(effectiveComponentId) ??
        const [];
    final clickBehaviors = behaviors
        .where(
          (b) =>
              b.enabled &&
              b.trigger == BehaviorTrigger.click &&
              b.action is! EmitEventAction,
        )
        .toList();
    final eventBehaviors = inEditMode
        ? <ComponentBehavior>[]
        : behaviors
              .where((b) => b.enabled && b.action is EmitEventAction)
              .toList();
    final hasClickBehaviors = !inEditMode && clickBehaviors.isNotEmpty;
    final interactive = canEdit || hasClickBehaviors;
    final runtimeChild = ComponentTooltip(
      componentId: effectiveComponentId,
      behaviors: widget.behaviors,
      sliver: isSliver,
      child: BehaviorEventListener(
        componentId: effectiveComponentId,
        componentType: widget.eventComponentType,
        behaviors: eventBehaviors,
        readData: widget.eventData,
        sliver: isSliver,
        child:
            widget.child ??
            (isSliver
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : const SizedBox.expand()),
      ),
    );

    if (isSliver) {
      final Widget child = KeyedSubtree(key: _childKey, child: runtimeChild);
      if (!interactive) {
        if (_hovered.contains(this)) _removeHoveredSafely();
        return child;
      }
      if (canEdit && editMode != null) {
        _cachedDepth = _depth;
      } else if (_hovered.contains(this)) {
        _removeHoveredSafely();
      }
      final accentColor = AppearanceScope.of(context).accent
          .withValues(alpha: .85);
      return ListenableBuilder(
        listenable: _paintListenable,
        builder: (context, child) {
          final target = _hoveredTarget.value;
          final isEmphasizedHighlight =
              identical(_menuHoveredTarget, this) ||
              identical(_canvasHoveredParent.value, this);
          final hasExternalHighlight =
              _highlightedTarget.value != null ||
              LayoutSelection.highlightedSlotId.value != null;
          final isSelectedLeaf =
              canEdit &&
              editMode != null &&
              EditorOverlayVisibility.openDialogs.value == 0 &&
              !hasExternalHighlight &&
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
                ? (event) => _setHovered(false, pointerPosition: event.position)
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
                    zoomScale:
                        context
                            .dependOnInheritedWidgetOfExactType<
                              EditorZoomScope
                            >()
                            ?.scale ??
                        1.0,
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
      );
    }

    Widget content = KeyedSubtree(key: _childKey, child: runtimeChild);
    if (!interactive) {
      if (_hovered.contains(this)) _removeHoveredSafely();
      return content;
    }
    final trackHover = canEdit && editMode != null;
    if (trackHover) {
      _cachedDepth = _depth;
      final accentColor = AppearanceScope.of(context).accent
          .withValues(alpha: .85);
      content = ListenableBuilder(
        listenable: _paintListenable,
        builder: (context, child) {
          final target = _hoveredTarget.value;
          final isEmphasizedHighlight =
              identical(_menuHoveredTarget, this) ||
              identical(_canvasHoveredParent.value, this);
          final hasExternalHighlight =
              _highlightedTarget.value != null ||
              LayoutSelection.highlightedSlotId.value != null;
          final isSelectedLeaf =
              EditorOverlayVisibility.openDialogs.value == 0 &&
              !hasExternalHighlight &&
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
                    zoomScale:
                        context
                            .dependOnInheritedWidgetOfExactType<
                              EditorZoomScope
                            >()
                            ?.scale ??
                        1.0,
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
        child: RepaintBoundary(child: content),
      );
    } else if (_hovered.contains(this)) {
      _removeHoveredSafely();
    }

    return MouseRegion(
      cursor: hasClickBehaviors ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: trackHover
          ? (event) => _setHovered(true, pointerPosition: event.position)
          : null,
      onHover: trackHover
          ? (event) => _setHovered(true, pointerPosition: event.position)
          : null,
      onExit: trackHover
          ? (event) => _setHovered(false, pointerPosition: event.position)
          : null,
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
  }
}
