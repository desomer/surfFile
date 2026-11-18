/// Édition, sélection, glissement et redimensionnement visuel d'un slot.
library;

import 'dart:async' show scheduleMicrotask;

import 'package:flutter/gestures.dart'
    show PointerDownEvent, kPrimaryButton, kTouchSlop;
import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart';
import '../../editing/history/editor_history.dart';
import '../../editing/overlay/editor_overlay.dart';
import '../../editing/overlay/editor_resize_handle.dart';
import '../../editing/overlay/editor_zone_badge.dart';
import '../../editing/overlay/editor_zoom.dart';
import '../../editing/slots/editor_selection_region.dart';
import '../../editing/slots/editor_slot.dart';
import 'layout_selection.dart';
import 'slot_core.dart';
import 'slot_drag.dart';
import 'slot_render_layout.dart';

/// Un slot, son étiquette d'édition et sa cible de dépôt. Le slot reste le
/// premier enfant du `Stack` : son état survit au mode édition.
class LabeledSlot extends StatefulWidget {
  /// Crée un slot avec ses interactions d'édition visuelle.
  const LabeledSlot({
    required this.slot,
    required this.axis,
    required this.showLabel,
    required this.caption,
    required this.mover,
    required this.emphasis,
    required this.zoneLabel,
    required this.ids,
    required this.onSelect,
    required this.onTapContent,
    required this.onSelectContent,
    required this.selected,
    required this.onResize,
    required this.sizeConstraints,
    required this.padding,
    super.key,
  });

  final SlotImplementation slot;
  final Axis axis;
  final bool showLabel;
  final String caption;
  final SlotMover? mover;
  final LabelEmphasis? emphasis;
  final String? zoneLabel;
  final VoidCallback? onSelect;
  final ValueChanged<PointerDownEvent>? onTapContent;
  final VoidCallback? onSelectContent;
  final bool selected;
  final ValueChanged<SlotSizeConstraints>? onResize;
  final SlotSizeConstraints? sizeConstraints;
  final EdgeInsets padding;

  /// Slots visibles de la zone, dans l'ordre.
  final List<String> ids;

  @override
  State<LabeledSlot> createState() => _LabeledSlotState();
}

class _LabeledSlotState extends State<LabeledSlot> {
  int? _tapPointer;
  Offset? _tapStart;
  VoidCallback? _tapAction;
  final _labelKey = GlobalKey();

  /// Vrai quand le glisser survole la seconde moitie sur l'axe du slot.
  bool _after = false;

  /// L'étiquette ou une poignée du slot est survolée, ou l'étiquette est
  /// glissée : le slot qu'elle désigne est surligné.
  bool _hover = false;
  bool _labelHover = false;

  /// Les poignées recouvrent l'étiquette dans les coins : leur survol prolonge
  /// celui de l'étiquette, sinon poignées et surlignage clignotent.
  final _hoveredHandles = <String>{};
  bool _dragging = false;

  /// Cible annoncée par l'étiquette pendant qu'elle est glissée.
  final _hint = ValueNotifier<SlotDropHint?>(null);
  final _resizeOverlay = OverlayPortalController();
  SlotResizeGeometry? _resizeLayout;
  Offset? _resizeStart;
  Size _resizeSize = Size.zero;
  SlotSizeConstraints? _resizeConstraints;
  Size? _resizeLegacySize;
  EditorHistoryController? _resizeHistory;
  bool _resizeBlocked = false;
  bool _active = true;
  bool _cachedHasSelectedDescendant = false;
  bool _focusDirty = true;

  static final Listenable _focusListenable = Listenable.merge([
    LayoutSelection.path,
    LayoutSelection.focus,
  ]);

  static final Listenable _hoverListenable = Listenable.merge([
    EditorSlotState.highlightedTarget,
    EditorSlotState.canvasHoveredParent,
    EditorSelectionRegion.hoverTarget,
    LayoutSelection.highlightedSlotId,
  ]);

  bool _isDirectSlotOfThis(BuildContext targetContext) {
    if (!mounted || !_active || !targetContext.mounted) return false;
    var foundSelf = false;
    var hasIntermediateSlot = false;
    try {
      targetContext.visitAncestorElements((element) {
        if (identical(element, context)) {
          foundSelf = true;
          return false;
        }
        if (element is StatefulElement) {
          if (element.state is _LabeledSlotState) {
            return false;
          }
          if (element.state is EditorSlotState) {
            hasIntermediateSlot = true;
            return false;
          }
        }
        return true;
      });
    } catch (_) {
      return false;
    }
    return foundSelf && !hasIntermediateSlot;
  }

  bool _computeHasSelectedDescendant() {
    if (!_active || !mounted) return false;
    final focusCtx = LayoutSelection.focus.value?.context;
    if (focusCtx == null || !focusCtx.mounted || identical(focusCtx, context)) {
      return false;
    }
    var foundSelf = false;
    var hasIntermediateSlot = false;
    try {
      focusCtx.visitAncestorElements((element) {
        if (identical(element, context)) {
          foundSelf = true;
          return false;
        }
        if (element is StatefulElement) {
          if (element.state is _LabeledSlotState ||
              element.state is EditorSlotState) {
            hasIntermediateSlot = true;
          }
        }
        return true;
      });
    } catch (_) {
      return false;
    }
    return foundSelf && hasIntermediateSlot;
  }

  bool get _hasSelectedDescendant {
    if (_focusDirty) {
      _cachedHasSelectedDescendant = _computeHasSelectedDescendant();
      _focusDirty = false;
    }
    return _cachedHasSelectedDescendant;
  }

  bool get _hasExternalHighlight =>
      EditorSlotState.highlightedTarget.value != null ||
      LayoutSelection.highlightedSlotId.value != null;

  bool get _isActivelySelected =>
      widget.showLabel && widget.selected && !_hasSelectedDescendant;

  bool get _isParentOfSelected => _hasSelectedDescendant;

  bool get _isHighlightedTarget {
    if (!_active) return false;
    final hasExternal = _hasExternalHighlight;
    final hasDescendant = _hasSelectedDescendant;
    final activelySelected = widget.showLabel && widget.selected && !hasDescendant;
    if (activelySelected && !hasExternal) {
      return false;
    }
    final highlightedId = LayoutSelection.highlightedSlotId.value;
    if (highlightedId != null) {
      return highlightedId == widget.slot.id;
    }
    final highlighted =
        EditorSlotState.highlightedTarget.value ??
        EditorSlotState.canvasHoveredParent.value;
    if (highlighted != null &&
        highlighted.mounted &&
        _isDirectSlotOfThis(highlighted.context)) {
      return true;
    }
    if (hasDescendant) {
      final hoverCtx = EditorSelectionRegion.hoverTargetContext;
      if (hoverCtx != null && _isDirectSlotOfThis(hoverCtx)) {
        return true;
      }
    }
    return false;
  }

  bool get _isHoveredForResize => _hover || _isHighlightedTarget;

  bool get _showResizeHandles =>
      _active &&
      widget.onResize != null &&
      (_resizeStart != null ||
          (_isActivelySelected && !_hasExternalHighlight) ||
          _isHoveredForResize);

  (bool, bool, bool, bool, bool) get _selectionVisualState {
    final hasExternal = _hasExternalHighlight;
    final hasDescendant = _hasSelectedDescendant;
    final activelySelected =
        widget.showLabel && widget.selected && !hasDescendant;
    final highlightedTarget = _isHighlightedTarget;
    final showHandles =
        _active &&
        widget.onResize != null &&
        (_resizeStart != null ||
            (activelySelected && !hasExternal) ||
            _hover ||
            highlightedTarget);
    return (
      hasExternal,
      highlightedTarget,
      hasDescendant,
      activelySelected,
      showHandles,
    );
  }

  (bool, bool, bool, bool, bool)? _lastSelectionVisualState;
  bool _selectionCheckScheduled = false;

  void _onFocusChanged() {
    _focusDirty = true;
    _onSelectionOrHoverChanged();
  }

  void _onSelectionOrHoverChanged() {
    if (!mounted || !_active || _selectionCheckScheduled) return;
    _selectionCheckScheduled = true;
    scheduleMicrotask(() {
      _selectionCheckScheduled = false;
      if (!mounted || !_active) return;
      final next = _selectionVisualState;
      _syncResizeOverlay(shouldShowOverride: next.$5);
      if (next != _lastSelectionVisualState) {
        setState(() {});
      }
    });
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    _focusDirty = true;
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  void _syncResizeOverlay({bool? shouldShowOverride}) {
    final shouldShow = shouldShowOverride ?? _showResizeHandles;
    if (shouldShow == _resizeOverlay.isShowing &&
        (shouldShow || _resizeStart == null)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_showResizeHandles) {
        if (!_resizeOverlay.isShowing) _resizeOverlay.show();
      } else {
        final wasShowing = _resizeOverlay.isShowing;
        if (wasShowing) _resizeOverlay.hide();
        _finishResize();
        if (_hoveredHandles.isNotEmpty) {
          _hoveredHandles.clear();
          _updateHover();
        }
        if (wasShowing && mounted) setState(() {});
      }
    });
  }

  bool _listening = false;

  void _listen(bool value) {
    if (value == _listening) return;
    _listening = value;
    if (value) {
      _focusDirty = true;
      _focusListenable.addListener(_onFocusChanged);
      _hoverListenable.addListener(_onSelectionOrHoverChanged);
    } else {
      _focusListenable.removeListener(_onFocusChanged);
      _hoverListenable.removeListener(_onSelectionOrHoverChanged);
    }
  }

  @override
  void initState() {
    super.initState();
    _syncResizeOverlay();
  }

  @override
  void didUpdateWidget(LabeledSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _focusDirty = true;
    _syncResizeOverlay();
  }

  void _beginResize(DragStartDetails details) {
    final layout = context
        .findAncestorRenderObjectOfType<SlotResizeGeometry>()!;
    final box = context.findRenderObject()! as RenderBox;
    _resizeLayout = layout;
    _resizeStart = layout.globalToLocal(details.globalPosition);
    _resizeSize = box.size;
    _resizeConstraints = widget.sizeConstraints;
    _resizeLegacySize = layout.preferredSizeAt(
      widget.ids.indexOf(widget.slot.id),
    );
    _resizeBlocked = false;
    _resizeHistory = EditorHistoryScope.controllerOf(context);
    _resizeHistory?.beginTransaction();
    setState(() {});
  }

  void _resize(DragUpdateDetails details, Alignment corner) {
    final layout = _resizeLayout;
    final start = _resizeStart;
    if (layout == null || start == null || !layout.attached) return;
    final bounds = layout.resizeBounds(widget.ids.indexOf(widget.slot.id));
    final saved = _resizeConstraints;
    final legacySize = _resizeLegacySize;
    final basis = saved?.percentBasis == SlotPercentBasis.layout
        ? layout.layoutSize
        : layout.resizeBasis;
    final minWidth = saved?.minWidth?.resolve(basis.width) ?? 0;
    final minHeight = saved?.minHeight?.resolve(basis.height) ?? 0;
    final maxWidth = saved?.maxWidth?.resolve(basis.width) ?? bounds.max.width;
    final maxHeight =
        saved?.maxHeight?.resolve(basis.height) ?? bounds.max.height;
    final lowerWidth = bounds.min.width > 1 ? bounds.min.width : 1.0;
    final lowerHeight = bounds.min.height > 1 ? bounds.min.height : 1.0;
    if (bounds.max.width < lowerWidth ||
        bounds.max.height < lowerHeight ||
        minWidth > bounds.max.width ||
        minHeight > bounds.max.height ||
        maxWidth < minWidth ||
        maxHeight < minHeight) {
      if (!_resizeBlocked) {
        _resizeBlocked = true;
        final message =
            'Redimensionnement de ${widget.slot.label} impossible : '
            'les bornes min/max sont incompatibles avec l’espace disponible.';
        debugPrint(message);
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    final delta = layout.globalToLocal(details.globalPosition) - start;
    final width = (_resizeSize.width + delta.dx * corner.x).clamp(
      lowerWidth,
      bounds.max.width,
    );
    final height = (_resizeSize.height + delta.dy * corner.y).clamp(
      lowerHeight,
      bounds.max.height,
    );
    SlotDimension dimension(
      double value,
      SlotDimension? original,
      double base,
    ) => original?.unit == SlotSizeUnit.percent && base > 0 && base.isFinite
        ? SlotDimension(value * 100 / base, SlotSizeUnit.percent)
        : SlotDimension(value, SlotSizeUnit.pixels);
    widget.onResize?.call(
      SlotSizeConstraints(
        minWidth: saved?.minWidth,
        minHeight: saved?.minHeight,
        maxWidth: saved?.maxWidth,
        maxHeight: saved?.maxHeight,
        preferredWidth: corner.x == 0
            ? saved?.preferredWidth ??
                  (saved == null && legacySize != null
                      ? SlotDimension(legacySize.width, SlotSizeUnit.pixels)
                      : null)
            : dimension(width, saved?.preferredWidth, basis.width),
        preferredHeight: corner.y == 0
            ? saved?.preferredHeight ??
                  (saved == null && legacySize != null
                      ? SlotDimension(legacySize.height, SlotSizeUnit.pixels)
                      : null)
            : dimension(height, saved?.preferredHeight, basis.height),
        padding: saved?.padding ?? 0,
        paddingInsets: saved?.paddingInsets,
        percentBasis: saved?.percentBasis ?? SlotPercentBasis.zone,
        fitContent: saved?.fitContent,
      ),
    );
  }

  void _finishResize() {
    final wasResizing = _resizeStart != null;
    _resizeLayout = null;
    _resizeStart = null;
    _resizeHistory?.commitTransaction();
    _resizeHistory = null;
    if (wasResizing && mounted) {
      setState(() {});
      // Les poignées maintenues pendant le redimensionnement peuvent se masquer.
      _syncResizeOverlay();
    }
  }

  Widget _resizeHandle(String name, Alignment corner, ColorScheme colors) =>
      EditorResizeHandle(
        key: ValueKey('slot-resize-${widget.slot.id}-$name'),
        direction: corner,
        label: widget.slot.label,
        onStart: _beginResize,
        onUpdate: (details) => _resize(details, corner),
        onEnd: _finishResize,
        onHoverChanged: (hovered) {
          hovered ? _hoveredHandles.add(name) : _hoveredHandles.remove(name);
          _updateHover();
        },
      );

  void _setLabelHover(bool value) {
    _labelHover = value;
    _updateHover();
  }

  void _updateHover() {
    final value = _labelHover || _hoveredHandles.isNotEmpty;
    if (mounted && value != _hover) {
      setState(() => _hover = value);
      _syncResizeOverlay();
      if (_isParentOfSelected) {
        final slotState = EditorSlotState.resolveFromContext(context);
        if (slotState != null && _isDirectSlotOfThis(slotState.context)) {
          EditorSlotState.setCanvasHoveredParent(value ? slotState : null);
        }
      }
      _reportEmphasis();
    }
  }

  void _setDragging(bool value) {
    if (!value) _hint.value = null;
    if (mounted && value != _dragging) {
      setState(() => _dragging = value);
      _reportEmphasis();
    }
  }

  void _reportEmphasis() =>
      widget.emphasis?.report(widget.slot.id, _hover || _dragging);

  @override
  void dispose() {
    _listen(false);
    _finishResize();
    final emphasis = widget.emphasis;
    if (emphasis != null && (_hover || _dragging)) {
      // Le parent ne doit pas être notifié pendant le démontage.
      final id = widget.slot.id;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => emphasis.report(id, false),
      );
    }
    super.dispose();
  }

  /// Rang du slot glissé s'il était lâché avant ou après ce slot.
  SlotDropHint? _hintFor(SlotDragData data) => data.id == widget.slot.id
      ? null
      : SlotDropHint.at(
          zoneLabel: widget.zoneLabel,
          ids: widget.ids,
          movedId: data.id,
          beforeId: _after ? null : widget.slot.id,
          afterId: _after ? widget.slot.id : null,
        );
  bool _accepts(SlotDragData data) =>
      widget.mover != null &&
      identical(data.owner, widget.mover!.owner) &&
      (widget.mover!.canMove?.call(data.id) ?? true);

  void _track(Offset pointer) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(pointer);
    final after = widget.axis == Axis.horizontal
        ? local.dx > box.size.width / 2
        : local.dy > box.size.height / 2;
    if (after != _after) setState(() => _after = after);
  }

  Widget _chip(
    ColorScheme colors, {
    double opacity = 0.5,
    bool dragged = false,
  }) {
    final emphasis = widget.emphasis;
    Widget label(bool highlighted) => ComponentDragLabel(
      key: ValueKey('slot-label-${widget.slot.id}'),
      opacity: opacity,
      highlighted: highlighted,
      draggable: widget.mover != null,
      dragging: _dragging || dragged,
      child: dragged
          ? ValueListenableBuilder<SlotDropHint?>(
              valueListenable: _hint,
              builder: (context, hint, _) => Text(
                hint == null
                    ? widget.caption
                    : '${widget.slot.label} → ${hint.caption}',
              ),
            )
          : Text(widget.caption),
    );
    if (emphasis == null) return label(_hover || _dragging);
    return ValueListenableBuilder<Set<Object>>(
      valueListenable: emphasis.scopes,
      builder: (context, scopes, _) =>
          label(_hover || _dragging || scopes.contains(emphasis.scope)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final mover = widget.mover;
    final canEditSize =
        (StyleEditScope.controllerOf(context)?.value ?? true) &&
        EditorSlotAction.of(context).isNotEmpty;
    final hasTapContent = widget.onTapContent != null;
    final inert =
        !canEditSize &&
        !widget.showLabel &&
        mover == null &&
        widget.onResize == null &&
        !hasTapContent &&
        widget.onSelectContent == null &&
        !_hover &&
        !_dragging &&
        _resizeStart == null;
    _listen(!inert);

    final baseChild = BoxPointerRegion(
      enabled: canEditSize || hasTapContent,
      opaque: false,
      onSecondaryTapUp: canEditSize
          ? (details) =>
                context.findAncestorStateOfType<EditorSlotState>()?.openMenu(
                  details.globalPosition,
                  actions: EditorSlotAction.of(context),
                  targetContext: context,
                )
          : null,
      onPointerDown: hasTapContent
          ? (event) {
              // Portal labels can hit-test alongside the content below.
              final label = _labelKey.currentContext?.findRenderObject();
              final onLabel =
                  label is RenderBox &&
                  label.hasSize &&
                  (Offset.zero & label.size).contains(
                    label.globalToLocal(event.position),
                  );
              if (event.buttons != kPrimaryButton ||
                  onLabel ||
                  _tapPointer != null) {
                _tapAction = null;
                return;
              }
              _tapPointer = event.pointer;
              _tapStart = event.position;
              final callback = widget.onTapContent;
              _tapAction = callback == null ? null : () => callback(event);
            }
          : null,
      onPointerMove: hasTapContent
          ? (event) {
              if (event.pointer == _tapPointer &&
                  (event.position - _tapStart!).distance > kTouchSlop) {
                _tapAction = null;
              }
            }
          : null,
      onPointerCancel: hasTapContent
          ? (event) {
              if (event.pointer == _tapPointer) {
                _tapPointer = null;
                _tapStart = null;
                _tapAction = null;
              }
            }
          : null,
      onPointerUp: hasTapContent
          ? (event) {
              if (event.pointer != _tapPointer) return;
              final action =
                  (event.position - _tapStart!).distance <= kTouchSlop
                  ? _tapAction
                  : null;
              _tapPointer = null;
              _tapStart = null;
              _tapAction = null;
              action?.call();
            }
          : null,
      child: EditorSelectionRegion(
        enabled: !inert && widget.onSelectContent != null,
        selected: !inert && widget.showLabel && widget.selected,
        onSelect: () => widget.onSelectContent?.call(),
        child: Padding(padding: widget.padding, child: slot),
      ),
    );

    if (inert) {
      return SlotDropTargetStack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [baseChild],
      );
    }

    final colors = Theme.of(context).colorScheme;
    _lastSelectionVisualState = _selectionVisualState;
    final mountResizePortal =
        _showResizeHandles || _resizeOverlay.isShowing || _resizeStart != null;
    final hasDropTarget = mover != null;
    return SlotDropTargetStack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      hasDropTarget: hasDropTarget,
      children: [
        baseChild,
        if (mountResizePortal)
              Positioned.fill(
                child: IgnorePointer(
                  child: OverlayPortal.overlayChildLayoutBuilder(
                    controller: _resizeOverlay,
                    overlayChildBuilder: (context, info) {
                      final handles = Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final (name, corner) in editorResizeDirections)
                            Positioned.fill(
                              child: Align(
                                alignment: corner,
                                child: _resizeHandle(name, corner, colors),
                              ),
                            ),
                          if (_resizeStart != null)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 34),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: colors.tertiaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          '${info.childSize.width.round()} × ${info.childSize.height.round()} px',
                                          key: ValueKey(
                                            'slot-resize-size-${slot.id}',
                                          ),
                                          style: TextStyle(
                                            color: colors.onTertiaryContainer,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                      if (EditorZoomScope.contains(context)) {
                        return Positioned.fromRect(
                          rect: MatrixUtils.transformRect(
                            info.childPaintTransform,
                            Offset.zero & info.childSize,
                          ),
                          child: handles,
                        );
                      }
                      return Positioned(
                        left: 0,
                        top: 0,
                        child: Transform(
                          transform: info.childPaintTransform,
                          child: SizedBox.fromSize(
                            size: info.childSize,
                            child: handles,
                          ),
                        ),
                      );
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            if (_hover ||
                _dragging ||
                (!_hasExternalHighlight &&
                    (_isHighlightedTarget ||
                        _isParentOfSelected ||
                        _isActivelySelected)))
              Positioned.fill(
                key: ValueKey('slot-highlight-${slot.id}'),
                child: EditorOverlayVisibility(
                  child: _dragging
                      ? const EditorSelectionBorder.active(
                          filled: true,
                          hideOnTargetHighlight: false,
                        )
                      : (!_hasExternalHighlight && _isActivelySelected)
                      ? const EditorSelectionBorder.active(filled: true)
                      : (_hover || _isHighlightedTarget)
                      ? const EditorSelectionBorder.hover()
                      : const EditorSelectionBorder.subtleParent(),
                ),
              ),
            if (widget.showLabel && slot.showLabel)
              Positioned.fill(
                key: ValueKey('slot-label-position-${slot.id}'),
                child: EditorOverlay(
                  child: Align(
                    alignment: slot.labelAlignment,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: MouseRegion(
                        key: _labelKey,
                        cursor: mover == null
                            ? SystemMouseCursors.click
                            : editorDragCursor(dragging: _dragging),
                        hitTestBehavior: HitTestBehavior.translucent,
                        onEnter: (_) => _setLabelHover(true),
                        onExit: (_) => _setLabelHover(false),
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: widget.onSelect == null
                              ? null
                              : EditorSelectionRegion.ignorePointer,
                          child: GestureDetector(
                            key: ValueKey('slot-label-select-${slot.id}'),
                            onTap: widget.onSelect,
                            behavior: HitTestBehavior.translucent,
                            child: mover == null
                                ? IgnorePointer(child: _chip(colors))
                                : DragTarget<SlotDragData>(
                                    onWillAcceptWithDetails: (details) {
                                      final accepts =
                                          details.data.id != slot.id &&
                                          _accepts(details.data);
                                      if (accepts) {
                                        _track(details.offset);
                                        details.data.hint.value = _hintFor(
                                          details.data,
                                        );
                                      }
                                      return accepts;
                                    },
                                    onMove: (details) {
                                      if (!_accepts(details.data) ||
                                          details.data.id == slot.id) {
                                        return;
                                      }
                                      _track(details.offset);
                                      details.data.hint.value = _hintFor(
                                        details.data,
                                      );
                                    },
                                    onLeave: (data) => data?.hint.value = null,
                                    onAcceptWithDetails: (details) {
                                      if (details.data.id == slot.id ||
                                          !_accepts(details.data)) {
                                        return;
                                      }
                                      mover.onMove(
                                        details.data.id,
                                        beforeId: _after ? null : slot.id,
                                        afterId: _after ? slot.id : null,
                                      );
                                    },
                                    builder: (context, candidates, _) =>
                                        Draggable<SlotDragData>(
                                          data: SlotDragData(
                                            id: slot.id,
                                            owner: mover.owner,
                                            hint: _hint,
                                          ),
                                          dragAnchorStrategy:
                                              pointerDragAnchorStrategy,
                                          hitTestBehavior:
                                              HitTestBehavior.translucent,
                                          onDragStarted: () =>
                                              _setDragging(true),
                                          onDragEnd: (_) => _setDragging(false),
                                          feedback: _chip(
                                            colors,
                                            opacity: 1,
                                            dragged: true,
                                          ),
                                          childWhenDragging: Opacity(
                                            opacity: .35,
                                            child: _chip(colors),
                                          ),
                                          // Le contenu sous l'étiquette reste atteignable (clic
                                          // droit du style) : seul le Draggable écoute le glisser.
                                          child: IgnorePointer(
                                            child: _chip(colors),
                                          ),
                                        ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (hasDropTarget)
              Positioned.fill(
                child: DragTarget<SlotDragData>(
                  // Déposer un slot sur lui-même est accepté sans effet : la zone qui le
                  // contient ne doit pas le ranger en dernier.
                  onWillAcceptWithDetails: (details) {
                    final accepts = _accepts(details.data);
                    if (accepts) {
                      _track(details.offset);
                      details.data.hint.value = _hintFor(details.data);
                    }
                    return accepts;
                  },
                  onMove: (details) {
                    if (!_accepts(details.data)) return;
                    _track(details.offset);
                    details.data.hint.value = _hintFor(details.data);
                  },
                  onLeave: (data) => data?.hint.value = null,
                  onAcceptWithDetails: (details) {
                    if (details.data.id == slot.id) return;
                    mover.onMove(
                      details.data.id,
                      beforeId: _after ? null : slot.id,
                      afterId: _after ? slot.id : null,
                    );
                  },
                  builder: (context, candidates, _) =>
                      candidates.any(
                        (data) => data != null && data.id != slot.id,
                      )
                      ? EditorOverlayVisibility(
                          child: Align(
                            alignment: widget.axis == Axis.horizontal
                                ? (_after
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft)
                                : (_after
                                      ? Alignment.bottomCenter
                                      : Alignment.topCenter),
                            child: SizedBox(
                              key: ValueKey('slot-drop-position-${slot.id}'),
                              width: widget.axis == Axis.horizontal
                                  ? 3
                                  : double.infinity,
                              height: widget.axis == Axis.vertical
                                  ? 3
                                  : double.infinity,
                              child: IgnorePointer(
                                child: ColoredBox(
                                  key: ValueKey('slot-drop-${slot.id}'),
                                  color: colors.tertiary,
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
          ],
    );
  }
}
