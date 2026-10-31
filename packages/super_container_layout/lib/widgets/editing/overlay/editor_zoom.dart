import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../components/super_layout/layout_selection.dart';
import '../addition/insertion_plan.dart';
import '../slots/editor_slot.dart';
import 'editor_overlay.dart';

/// Animates the page around the selected layout, zone or slot.
class EditorZoom extends StatefulWidget {
  const EditorZoom({
    required this.child,
    this.maxAutoZoomExtent = defaultMaxAutoZoomExtent,
    super.key,
  });

  static const defaultMaxAutoZoomExtent = 200.0;
  static const minScale = 1.0;
  static const maxScale = 4.0;
  static const targetScreenAreaFraction = 1.0 / 3.0;

  /// Empêche l'ouverture du menu contextuel après un drag ou un zoom au clic droit.
  static bool suppressContextMenu = false;

  final Widget child;

  /// Une sélection dont la largeur ou la hauteur atteint cette taille (en px)
  /// n'est pas zoomée automatiquement.
  final double maxAutoZoomExtent;

  @override
  State<EditorZoom> createState() => _EditorZoomState();
}

class _EditorZoomState extends State<EditorZoom>
    with SingleTickerProviderStateMixin {
  final _content = GlobalKey();
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addListener(_animate);
  ValueNotifier<bool>? _editMode;
  Size _viewport = Size.zero;
  ({double scale, Offset offset}) _from = (scale: 1, offset: Offset.zero);
  ({double scale, Offset offset}) _to = (scale: 1, offset: Offset.zero);
  ({double scale, Offset offset}) _current = (scale: 1, offset: Offset.zero);
  bool _scheduled = false;
  final _controller = EditorZoomController();
  final _viewportKey = GlobalKey();
  BuildContext? _zoomTarget;
  EditorDialogFocus? _zoomDialog;
  EditorSlotState? _debouncedHighlight;
  Timer? _hoverZoomTimer;
  static const _hoverZoomDelay = Duration(milliseconds: 160);
  double? _manualScale;
  Offset? _manualOffset;
  bool _framingHeld = false;
  ZoomToolbarLayout _toolbarLayout = ZoomToolbarLayout(null);

  bool _isSecondaryDown = false;
  Offset? _secondaryDownPosition;
  Offset? _lastSecondaryPosition;
  bool _isSecondaryPanning = false;
  bool _isSecondaryZooming = false;

  void _onHighlightChanged() {
    _hoverZoomTimer?.cancel();
    final next =
        EditorSlotState.highlightedTarget.value ??
        EditorSlotState.canvasHoveredParent.value;
    if (identical(next, _debouncedHighlight)) return;
    _debouncedHighlight = next;
    _schedule();
  }

  @override
  void initState() {
    super.initState();
    _controller._contentKey = _content;
    EditorZoomController._mounted.add(_controller);
    _controller._pointerDownHandler = _onPointerDown;
    _controller._pointerMoveHandler = _onPointerMove;
    _controller._pointerUpHandler = _onPointerUp;
    _controller._pointerCancelHandler = _onPointerCancel;
    _controller._pointerSignalHandler = _onPointerSignal;
    _controller.sliderScaleHandler = _setSliderScale;
    _controller.scale.value = _current.scale;
    _controller._interactionHandler = (held) {
      _framingHeld = held;
      if (held) {
        _animation.stop();
        _from = _to = _current;
      } else {
        _schedule();
      }
    };
    LayoutSelection.focus.addListener(_schedule);
    EditorSlotState.highlightedTarget.addListener(_onHighlightChanged);
    EditorSlotState.canvasHoveredParent.addListener(_onHighlightChanged);
    _controller.hoveredParentContext.addListener(_schedule);
    _controller.dialog.addListener(_schedule);
    _controller.contextMenuAvailable.addListener(_schedule);
    EditorInsertionPreview.active.addListener(_schedule);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = StyleEditScope.controllerOf(context);
    if (!identical(mode, _editMode)) {
      _editMode?.removeListener(_schedule);
      _editMode = mode;
      mode?.addListener(_schedule);
    }
    _controller.enabled = mode?.value ?? false;
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _frameSelection();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _frameSelection() {
    var destination = (scale: 1.0, offset: Offset.zero);
    _controller.enabled = _editMode?.value ?? false;
    if (_framingHeld && _controller.enabled) return;
    _controller.contentContext = _content.currentContext;
    final dialog = _controller.dialog.value;
    final highlighted = _debouncedHighlight;
    final highlightedCtx = highlighted != null && highlighted.mounted
        ? highlighted.context
        : null;
    final parentHover = _controller.hoveredParentContext.value;
    final parentHoverCtx = parentHover != null && parentHover.mounted
        ? parentHover
        : null;
    final activeHoverCtx = highlightedCtx ?? parentHoverCtx;
    final focus =
        activeHoverCtx ??
        dialog?.target ??
        LayoutSelection.focus.value?.context ??
        (dialog != null ? _content.currentContext : null);
    if (!_controller.enabled ||
        !identical(focus, _zoomTarget) ||
        !identical(dialog, _zoomDialog)) {
      _manualScale = null;
      _manualOffset = null;
      _zoomTarget = focus;
      _zoomDialog = dialog;
    }
    var rect = _controller.targetBounds(focus);
    if (_controller.enabled && !_viewport.isEmpty) {
      var available = Offset.zero & _viewport;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      final reservedScreen =
          dialog?.available ?? _controller.contextMenuAvailable.value;
      if (reservedScreen case final screen? when viewport is RenderBox) {
        available = Rect.fromPoints(
          viewport.globalToLocal(screen.topLeft),
          viewport.globalToLocal(screen.bottomRight),
        ).intersect(available);
      }
      if (available.isEmpty) return;
      if (dialog != null &&
          EditorInsertionPreview.active.value != null &&
          _content.currentContext?.findRenderObject() != null) {
        final content = _content.currentContext!.findRenderObject()!;
        if (content is RenderBox && content.attached && content.hasSize) {
          final previewBounds = EditorInsertionPreview.active.value!
              .resolve(content)
              ?.framingRect;
          if (previewBounds != null &&
              !previewBounds.isEmpty &&
              previewBounds.isFinite) {
            if (rect == null || rect.isEmpty || !rect.isFinite) {
              rect = previewBounds;
            } else {
              final baseScale = math
                  .min(
                    available.width * .7 / rect.width,
                    available.height * .7 / rect.height,
                  )
                  .clamp(0.0, EditorZoom.maxScale);
              final baseOffset = available.center - rect.center * baseScale;
              final projected = Rect.fromLTWH(
                baseOffset.dx + previewBounds.left * baseScale,
                baseOffset.dy + previewBounds.top * baseScale,
                previewBounds.width * baseScale,
                previewBounds.height * baseScale,
              );
              final margin = math.min(
                8.0,
                math.min(available.width, available.height) * .05,
              );
              final safeArea = available.deflate(margin);
              final fitsInView =
                  safeArea.contains(projected.topLeft) &&
                  safeArea.contains(projected.bottomRight);
              if (!fitsInView) {
                rect = rect.expandToInclude(previewBounds);
              }
            }
          }
        }
      }
      if (_manualScale case final manualScale?) {
        destination = (
          scale: manualScale,
          offset:
              _manualOffset ??
              (rect != null
                  ? available.center - rect.center * manualScale
                  : available.center),
        );
      } else if (_manualOffset case final manualOffset?) {
        destination = (scale: _to.scale, offset: manualOffset);
      } else if (rect != null && !rect.isEmpty && rect.isFinite) {
        final viewportBounds = Offset.zero & _viewport;
        final isOutOfView =
            rect.left < viewportBounds.left ||
            rect.top < viewportBounds.top ||
            rect.right > viewportBounds.right ||
            rect.bottom > viewportBounds.bottom;
        final isHoverFraming = activeHoverCtx != null;
        final hasEditorDialog = dialog != null;
        final autoZoomDisabled =
            !hasEditorDialog &&
            _manualScale == null &&
            widget.maxAutoZoomExtent <= 0;
        if (!autoZoomDisabled) {
          final double rawScale;
          if (hasEditorDialog) {
            rawScale = math.min(
              available.width * .7 / rect.width,
              available.height * .7 / rect.height,
            );
          } else {
            final targetArea =
                available.width *
                available.height *
                EditorZoom.targetScreenAreaFraction;
            final selectionArea = rect.width * rect.height;
            final areaScale = math.sqrt(targetArea / selectionArea);
            final fitScale = math.min(
              available.width * .9 / rect.width,
              available.height * .9 / rect.height,
            );
            rawScale = math.min(areaScale, fitScale);
          }
          final baseScale = rawScale.clamp(
            hasEditorDialog ? 0.0 : EditorZoom.minScale,
            EditorZoom.maxScale,
          );
          const handleMargin = 28.0;
          final fitWithHandles = math.min(
            math.max(1.0, available.width - handleMargin * 2) / rect.width,
            math.max(1.0, available.height - handleMargin * 2) / rect.height,
          );
          final scale = isHoverFraming
              ? math
                    .min(baseScale, fitWithHandles)
                    .clamp(0.5, EditorZoom.maxScale)
              : baseScale;
          if (hasEditorDialog ||
              scale > EditorZoom.minScale ||
              isOutOfView ||
              isHoverFraming) {
            destination = (
              scale: scale,
              offset:
                  scale <= EditorZoom.minScale &&
                      !hasEditorDialog &&
                      !isOutOfView &&
                      !isHoverFraming
                  ? Offset.zero
                  : available.center - rect.center * scale,
            );
          }
        }
      }
    }
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (destination == _to && !(disableAnimations && _animation.isAnimating)) {
      return;
    }
    _from = _current;
    _to = destination;
    if (disableAnimations) {
      _animation.stop();
      _controller.scale.value = _to.scale;
      _controller.transform.value = _to;
      setState(() => _current = _to);
    } else {
      _animation.forward(from: 0);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!(_editMode?.value ?? false)) return;
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      _isSecondaryDown = true;
      _secondaryDownPosition = event.position;
      _lastSecondaryPosition = event.position;
      _isSecondaryPanning = false;
      _isSecondaryZooming = false;
      _controller.suppressContextMenu = false;
      EditorZoom.suppressContextMenu = false;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!(_editMode?.value ?? false) || !_isSecondaryDown || _framingHeld) {
      return;
    }
    // Si l'utilisateur utilise la molette avec le bouton droit, on ne déclenche
    // aucun pan parasite lors des mouvements involontaires de la souris.
    if (_isSecondaryZooming) return;

    if ((event.buttons & kSecondaryMouseButton) != 0) {
      final totalDelta =
          (event.position - (_secondaryDownPosition ?? event.position))
              .distance;
      if (totalDelta > kTouchSlop || _isSecondaryPanning) {
        _isSecondaryPanning = true;
        _controller.suppressContextMenu = true;
        EditorZoom.suppressContextMenu = true;

        final delta =
            event.position - (_lastSecondaryPosition ?? event.position);
        _lastSecondaryPosition = event.position;

        final newOffset = (_manualOffset ?? _to.offset) + delta;
        _manualOffset = newOffset;
        _manualScale ??= _to.scale;
        _animation.stop();
        final next = (scale: _current.scale, offset: newOffset);
        _controller.transform.value = next;
        setState(() {
          _current = _from = _to = next;
        });
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isSecondaryDown) {
      _isSecondaryDown = false;
      _lastSecondaryPosition = null;
      _secondaryDownPosition = null;
      if (_isSecondaryPanning || _isSecondaryZooming) {
        _controller.suppressContextMenu = true;
        EditorZoom.suppressContextMenu = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _controller.suppressContextMenu = false;
          EditorZoom.suppressContextMenu = false;
        });
      }
      _isSecondaryPanning = false;
      _isSecondaryZooming = false;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_isSecondaryDown) {
      _isSecondaryDown = false;
      _lastSecondaryPosition = null;
      _secondaryDownPosition = null;
      if (_isSecondaryPanning || _isSecondaryZooming) {
        _controller.suppressContextMenu = true;
        EditorZoom.suppressContextMenu = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _controller.suppressContextMenu = false;
          EditorZoom.suppressContextMenu = false;
        });
      }
      _isSecondaryPanning = false;
      _isSecondaryZooming = false;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        !event.scrollDelta.dy.isFinite ||
        !(_editMode?.value ?? false) ||
        _framingHeld) {
      return;
    }
    final isSecondaryPressed =
        (event.buttons & kSecondaryMouseButton) != 0 || _isSecondaryDown;
    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
    if (!isCtrlPressed && !isSecondaryPressed) {
      return;
    }
    if (isSecondaryPressed) {
      _isSecondaryZooming = true;
      _controller.suppressContextMenu = true;
      EditorZoom.suppressContextMenu = true;
    }
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize || _viewport.isEmpty) {
      return;
    }
    final localPointer = viewport.globalToLocal(event.position);
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted) return;
      _frameSelection();
      final base = _to;
      final nextScale =
          (base.scale *
                  math.exp(
                    -event.scrollDelta.dy.clamp(-1200.0, 1200.0) * .0025,
                  ))
              .clamp(EditorZoom.minScale, EditorZoom.maxScale);
      _manualScale = nextScale;
      _manualOffset =
          event.scrollDelta.dy > 0 &&
              nextScale <= EditorZoom.minScale &&
              _controller.dialog.value == null
          ? Offset.zero
          : localPointer -
                (localPointer - base.offset) * (nextScale / base.scale);
      _frameSelection();
    });
  }

  void _setSliderScale(double value) {
    if (!(_editMode?.value ?? false) || _viewport.isEmpty || _framingHeld) {
      return;
    }
    final nextScale = value.clamp(EditorZoom.minScale, EditorZoom.maxScale);
    final dialog = _controller.dialog.value;
    var available = Offset.zero & _viewport;
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (dialog?.available case final screen? when viewport is RenderBox) {
      available = Rect.fromPoints(
        viewport.globalToLocal(screen.topLeft),
        viewport.globalToLocal(screen.bottomRight),
      ).intersect(available);
    }
    if (available.isEmpty) return;
    _controller.contentContext = _content.currentContext;
    final base = _current;
    final focus = dialog?.target ?? LayoutSelection.focus.value?.context;
    final rect = _controller.targetBounds(focus);
    final Offset pivot;
    if (base.scale <= EditorZoom.minScale &&
        base.offset == Offset.zero &&
        rect != null &&
        !rect.isEmpty &&
        rect.isFinite &&
        (rect.width < _viewport.width || rect.height < _viewport.height)) {
      pivot = rect.center;
    } else {
      pivot = available.center;
    }
    final nextOffset = nextScale <= EditorZoom.minScale && dialog == null
        ? Offset.zero
        : pivot - (pivot - base.offset) * (nextScale / base.scale);
    _manualScale = nextScale;
    _manualOffset = nextOffset;
    _controller.scale.value = nextScale;
    _animation.stop();
    final next = (scale: nextScale, offset: nextOffset);
    _controller.transform.value = next;
    setState(() {
      _current = _from = _to = next;
    });
  }

  void _animate() {
    final progress = Curves.easeInOutCubic.transform(_animation.value);
    final scale = _from.scale + (_to.scale - _from.scale) * progress;
    final offset = Offset.lerp(_from.offset, _to.offset, progress)!;
    _controller.scale.value = scale;
    final next = (scale: scale, offset: offset);
    _controller.transform.value = next;
    setState(() {
      _current = next;
    });
  }

  @override
  void dispose() {
    _hoverZoomTimer?.cancel();
    _controller.sliderScaleHandler = null;
    LayoutSelection.focus.removeListener(_schedule);
    EditorSlotState.highlightedTarget.removeListener(_onHighlightChanged);
    EditorSlotState.canvasHoveredParent.removeListener(_onHighlightChanged);
    _controller.hoveredParentContext.removeListener(_schedule);
    _controller.dialog.removeListener(_schedule);
    _controller.contextMenuAvailable.removeListener(_schedule);
    EditorInsertionPreview.active.removeListener(_schedule);
    _controller.dispose();
    _editMode?.removeListener(_schedule);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EditorZoomScope(
    scale: _current.scale,
    offset: _current.offset,
    controller: _controller,
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (_viewport != constraints.biggest) {
          _viewport = constraints.biggest;
          _schedule();
        }
        final editing = _editMode?.value ?? false;
        return Stack(
          fit: StackFit.expand,
          children: [
            MouseRegion(
              opaque: false,
              onHover: (event) =>
                  EditorSlotState.recordViewportPointerHover(event.position),
              onExit: (_) => EditorSlotState.clearCanvasHoveredParent(),
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                onPointerSignal: _onPointerSignal,
                behavior: HitTestBehavior.translucent,
                child: ClipRect(
                  key: _viewportKey,
                  child: Transform(
                    key: const ValueKey('editor-zoom-transform'),
                    alignment: Alignment.topLeft,
                    transform: Matrix4.identity()
                      ..translateByDouble(
                        _current.offset.dx,
                        _current.offset.dy,
                        0,
                        1,
                      )
                      ..scaleByDouble(_current.scale, _current.scale, 1, 1),
                    child: SizedBox.expand(key: _content, child: widget.child),
                  ),
                ),
              ),
            ),
            if (editing)
              ListenableBuilder(
                listenable: Listenable.merge([
                  EditorOverlayVisibility.openDialogs,
                  _controller.openContextMenus,
                ]),
                builder: (context, _) =>
                    EditorOverlayVisibility.openDialogs.value > 0 ||
                        _controller.openContextMenus.value > 0
                    ? const SizedBox.shrink()
                    : Positioned.fill(
                        child: CustomSingleChildLayout(
                          delegate: _toolbarLayout = ZoomToolbarLayout(
                            _controller.toolbarPosition,
                          ),
                          child: Material(
                            key: const ValueKey('editor-zoom-toolbar'),
                            type: MaterialType.card,
                            elevation: 8,
                            borderRadius: BorderRadius.circular(8),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: EditorZoomToolbarContent(
                                scale: _current.scale,
                                onScaleChanged: _setSliderScale,
                                onDrag: (details) => setState(() {
                                  final nextPosition =
                                      _toolbarLayout.resolvedPosition +
                                      details.delta;
                                  _controller.toolbarPosition = nextPosition;
                                  _toolbarLayout = ZoomToolbarLayout(
                                    nextPosition,
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
          ],
        );
      },
    ),
  );
}

class EditorZoomToolbarContent extends StatelessWidget {
  const EditorZoomToolbarContent({
    required this.scale,
    required this.onScaleChanged,
    required this.onDrag,
    super.key,
  });

  final double scale;
  final ValueChanged<double> onScaleChanged;
  final GestureDragUpdateCallback onDrag;

  @override
  Widget build(BuildContext context) {
    Widget handle = GestureDetector(
      key: const ValueKey('editor-zoom-toolbar-drag'),
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onDrag,
      child: const SizedBox(
        width: 36,
        height: 36,
        child: Icon(Icons.drag_indicator, size: 20),
      ),
    );
    handle = MouseRegion(cursor: SystemMouseCursors.move, child: handle);
    if (Overlay.maybeOf(context) != null) {
      handle = Tooltip(message: 'Déplacer la barre de zoom', child: handle);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        handle,
        const Icon(Icons.zoom_in, size: 18),
        SizedBox(
          width: 120,
          height: 36,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              key: const ValueKey('editor-zoom-slider'),
              min: EditorZoom.minScale,
              max: EditorZoom.maxScale,
              value: scale.clamp(EditorZoom.minScale, EditorZoom.maxScale),
              onChanged: onScaleChanged,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: SizedBox(
            width: 38,
            child: Text(
              '${(scale * 100).round()}%',
              key: const ValueKey('editor-zoom-percentage'),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class ZoomToolbarLayout extends SingleChildLayoutDelegate {
  ZoomToolbarLayout(this.position, {this.available})
    : resolvedPosition = position ?? Offset.zero;

  final Offset? position;
  final Rect? available;
  Offset resolvedPosition;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = available ?? (Offset.zero & size);
    final desired =
        position ??
        Offset(
          bounds.right - childSize.width - 16,
          bounds.bottom - childSize.height - 12,
        );
    final minX = bounds.left;
    final maxX = (bounds.right - childSize.width).clamp(minX, double.infinity);
    final minY = bounds.top;
    final maxY = (bounds.bottom - childSize.height).clamp(
      minY,
      double.infinity,
    );
    resolvedPosition = Offset(
      desired.dx.clamp(minX, maxX),
      desired.dy.clamp(minY, maxY),
    );
    return resolvedPosition;
  }

  @override
  bool shouldRelayout(ZoomToolbarLayout oldDelegate) =>
      position != oldDelegate.position || available != oldDelegate.available;
}

class EditorZoomScope extends InheritedWidget {
  const EditorZoomScope({
    required this.scale,
    required this.offset,
    required super.child,
    this.controller,
    super.key,
  });

  final double scale;
  final Offset offset;
  final EditorZoomController? controller;

  static EditorZoomController? controllerOf(BuildContext context) {
    final inherited = context
        .getInheritedWidgetOfExactType<EditorZoomScope>()
        ?.controller;
    if (inherited != null) return inherited;
    EditorZoomController? descendant;
    void visit(Element element) {
      if (descendant != null) return;
      if (element.widget case EditorZoomScope(:final controller?)) {
        descendant = controller;
        return;
      }
      element.visitChildElements(visit);
    }

    if (context is Element) visit(context);
    return descendant ?? EditorZoomController._active;
  }

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EditorZoomScope>() != null;

  @override
  bool updateShouldNotify(EditorZoomScope oldWidget) =>
      scale != oldWidget.scale ||
      offset != oldWidget.offset ||
      controller != oldWidget.controller;
}

class EditorZoomController {
  static final List<EditorZoomController> _mounted = [];
  static EditorZoomController? get _active {
    for (var i = _mounted.length - 1; i >= 0; i--) {
      final candidate = _mounted[i];
      if (!candidate.disposed && (candidate.contentContext?.mounted ?? false)) {
        return candidate;
      }
    }
    return null;
  }

  void Function(PointerSignalEvent)? _pointerSignalHandler;
  void Function(PointerDownEvent)? _pointerDownHandler;
  void Function(PointerMoveEvent)? _pointerMoveHandler;
  void Function(PointerUpEvent)? _pointerUpHandler;
  void Function(PointerCancelEvent)? _pointerCancelHandler;
  void Function(bool)? _interactionHandler;
  int _interactions = 0;

  /// Holds the viewport steady while dragging in content coordinates.
  void beginInteraction() {
    if (_interactions++ == 0) _interactionHandler?.call(true);
  }

  void endInteraction() {
    if (_interactions == 0) return;
    if (--_interactions == 0) _interactionHandler?.call(false);
  }

  void handlePointerSignal(PointerSignalEvent event) =>
      _pointerSignalHandler?.call(event);

  void handlePointerDown(PointerDownEvent event) =>
      _pointerDownHandler?.call(event);

  void handlePointerMove(PointerMoveEvent event) =>
      _pointerMoveHandler?.call(event);

  void handlePointerUp(PointerUpEvent event) => _pointerUpHandler?.call(event);

  void handlePointerCancel(PointerCancelEvent event) =>
      _pointerCancelHandler?.call(event);

  final scale = ValueNotifier<double>(1.0);
  final openContextMenus = ValueNotifier<int>(0);
  final contextMenuAvailable = ValueNotifier<Rect?>(null);
  final hoveredParentContext = ValueNotifier<BuildContext?>(null);
  Offset? toolbarPosition;
  final transform = ValueNotifier<({double scale, Offset offset})>((
    scale: 1.0,
    offset: Offset.zero,
  ));
  void Function(double)? sliderScaleHandler;
  void setScale(double value) => sliderScaleHandler?.call(value);

  bool suppressContextMenu = false;
  bool enabled = false;
  bool disposed = false;
  final dialog = EditorDialogNotifier();
  GlobalKey? _contentKey;
  BuildContext? _contentContext;
  BuildContext? get contentContext =>
      _contentContext ?? _contentKey?.currentContext;
  set contentContext(BuildContext? value) => _contentContext = value;

  Rect? targetBounds(BuildContext? targetContext) {
    if (targetContext == null ||
        !targetContext.mounted ||
        contentContext == null ||
        !contentContext!.mounted) {
      return null;
    }
    var belongs = identical(targetContext, contentContext);
    targetContext.visitAncestorElements((element) {
      if (identical(element, contentContext)) belongs = true;
      return !belongs;
    });
    final target = targetContext.findRenderObject();
    final content = contentContext!.findRenderObject();
    if (!belongs ||
        target is! RenderBox ||
        content is! RenderBox ||
        !target.attached ||
        !content.attached ||
        !target.hasSize ||
        !content.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      target.getTransformTo(content),
      Offset.zero & target.size,
    );
  }

  void dispose() {
    _mounted.remove(this);
    disposed = true;
    _pointerSignalHandler = null;
    _interactionHandler = null;
    final available = dialog.value?.available;
    if (available != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (LayoutSelection.editorViewport.value == available) {
          LayoutSelection.editorViewport.value = null;
        }
      });
    }
    openContextMenus.dispose();
    contextMenuAvailable.dispose();
    hoveredParentContext.dispose();
    dialog.dispose();
    transform.dispose();
  }
}

class EditorDialogNotifier extends ValueNotifier<EditorDialogFocus?> {
  EditorDialogNotifier() : super(null);

  void frame(EditorDialogFocus request, Rect available) {
    if (request.available == available && identical(value, request)) return;
    request.available = available;
    if (identical(value, request)) {
      notifyListeners();
    } else {
      value = request;
    }
  }

  void retarget(BuildContext? target) {
    final current = value;
    if (current == null || identical(current.target, target)) return;
    current.target = target;
    notifyListeners();
  }

  void geometryChanged() => notifyListeners();
}

class EditorDialogFocus {
  EditorDialogFocus({required this.target});
  BuildContext? target;
  Rect? available;
}
