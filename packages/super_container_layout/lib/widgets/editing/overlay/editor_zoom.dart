/// Contrôleur et barre d'outils de zoom/panoramique du canevas en mode édition ([EditorZoomController]).
library;

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
  double? _manualScale;
  Offset? _manualOffset;
  Offset? _anchorViewportPoint;
  Offset? _anchorContentPoint;
  bool _framingHeld = false;
  ZoomToolbarLayout _toolbarLayout = ZoomToolbarLayout(null);

  bool _isSecondaryDown = false;
  Offset? _secondaryDownPosition;
  Offset? _lastSecondaryPosition;
  bool _isSecondaryPanning = false;
  bool _isSecondaryZooming = false;
  BuildContext? _lastFocusContext;
  bool _focusFromRightClick = false;
  ({double scale, Offset offset})? _preRightClickTransform;
  ({double scale, Offset offset})? _preDialogTransform;
  EditorZoomOptions _lastOptions = const EditorZoomOptions();

  void _onFocusChanged() {
    final nextFocus = LayoutSelection.focus.value?.context;
    if (_controller.isSelectingFromRightClick ||
        _controller.openContextMenus.value > 0) {
      _focusFromRightClick = true;
    } else if (!identical(nextFocus, _lastFocusContext)) {
      _focusFromRightClick = false;
      if (_zoomDialog == null) {
        _preRightClickTransform = null;
      }
    }
    _lastFocusContext = nextFocus;
    _schedule();
  }

  void _onOptionsChanged() {
    final next = _controller.options.value;
    if (next == _lastOptions) return;
    final previous = _lastOptions;
    _lastOptions = next;
    if (next.maxScale != previous.maxScale ||
        next.minDialogScale != previous.minDialogScale ||
        next.targetScreenAreaFraction != previous.targetScreenAreaFraction ||
        next.zoomOnSelection != previous.zoomOnSelection ||
        next.zoomOnRightClick != previous.zoomOnRightClick ||
        next.zoomOnHover != previous.zoomOnHover ||
        next.zoomOnEditorDialog != previous.zoomOnEditorDialog ||
        next.resetZoomOnDialogExit != previous.resetZoomOnDialogExit ||
        next.skipLargeElementsOnRightClick !=
            previous.skipLargeElementsOnRightClick ||
        next.skipLargeElementsOnDialog != previous.skipLargeElementsOnDialog ||
        next.largeElementViewportThreshold !=
            previous.largeElementViewportThreshold) {
      _zoomTarget = null;
    }
    _schedule();
  }

  void _onHighlightChanged() {
    _hoverZoomTimer?.cancel();
    final next = EditorSlotState.highlightedTarget.value;
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
    _controller._resetZoomHandler = _resetZoom;
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
    LayoutSelection.focus.addListener(_onFocusChanged);
    EditorSlotState.highlightedTarget.addListener(_onHighlightChanged);
    _controller.dialog.addListener(_schedule);
    _controller.contextMenuAvailable.addListener(_schedule);
    _controller.options.addListener(_onOptionsChanged);
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

  void _resetZoom() {
    if (!(_editMode?.value ?? false) || _framingHeld) return;
    _manualScale = 1.0;
    _manualOffset = Offset.zero;
    _controller.scale.value = 1.0;
    _animation.stop();
    const next = (scale: 1.0, offset: Offset.zero);
    _controller.transform.value = next;
    setState(() {
      _current = _from = _to = next;
    });
  }

  void _frameSelection() {
    var destination = (scale: 1.0, offset: Offset.zero);
    _controller.enabled = _editMode?.value ?? false;
    if (_framingHeld && _controller.enabled) return;
    _controller.contentContext = _content.currentContext;
    final options = _controller.options.value;
    final desiredDuration = Duration(
      milliseconds: options.animationDurationMs.clamp(50, 600),
    );
    if (_animation.duration != desiredDuration) {
      _animation.duration = desiredDuration;
    }
    final dialog = _controller.dialog.value;
    final hasContextMenu =
        _controller.openContextMenus.value > 0 ||
        _controller.contextMenuAvailable.value != null;
    final isRightClickContext = hasContextMenu || _focusFromRightClick;
    final highlighted = _debouncedHighlight;
    final rawHoverCtx = highlighted != null && highlighted.mounted
        ? highlighted.context
        : null;
    BuildContext? activeHoverCtx = options.zoomOnHover ? rawHoverCtx : null;
    if (activeHoverCtx != null && !_viewport.isEmpty) {
      final hoverRect = _controller.targetBounds(activeHoverCtx);
      if ((hasContextMenu && !options.zoomOnRightClick) ||
          (isRightClickContext &&
              options.skipLargeElementsOnRightClick &&
              hoverRect != null &&
              options.isElementTooLarge(hoverRect, _viewport))) {
        activeHoverCtx = null;
      }
    }
    final focus =
        activeHoverCtx ??
        (options.zoomOnEditorDialog ? dialog?.target : null) ??
        LayoutSelection.focus.value?.context ??
        (dialog != null && options.zoomOnEditorDialog
            ? _content.currentContext
            : null);
    final viewport = _viewportKey.currentContext?.findRenderObject();
    var rect = _controller.targetBounds(focus);
    final isTooLargeForRightClick =
        isRightClickContext &&
        options.skipLargeElementsOnRightClick &&
        rect != null &&
        options.isElementTooLarge(rect, _viewport);
    final isTooLargeForDialog =
        dialog != null &&
        EditorInsertionPreview.active.value == null &&
        options.skipLargeElementsOnDialog &&
        rect != null &&
        options.isElementTooLarge(rect, _viewport);
    final shouldKeepCurrentView =
        _controller.enabled &&
        ((dialog != null &&
                (!options.zoomOnEditorDialog || isTooLargeForDialog)) ||
            (dialog == null &&
                activeHoverCtx == null &&
                isRightClickContext &&
                (!options.zoomOnRightClick || isTooLargeForRightClick)) ||
            (dialog == null &&
                activeHoverCtx == null &&
                !isRightClickContext &&
                focus != null &&
                !options.zoomOnSelection));
    final enteringEditorDialog = _zoomDialog == null && dialog != null;
    final exitingEditorDialog = _zoomDialog != null && dialog == null;
    if (enteringEditorDialog) {
      _preDialogTransform = _preRightClickTransform ?? _to;
      _preRightClickTransform = null;
    }
    if (!_controller.enabled ||
        !identical(focus, _zoomTarget) ||
        !identical(dialog, _zoomDialog)) {
      if (!_controller.enabled) {
        _manualScale = null;
        _manualOffset = null;
        _focusFromRightClick = false;
        _preRightClickTransform = null;
        _preDialogTransform = null;
      } else if (exitingEditorDialog &&
          options.resetZoomOnDialogExit &&
          _preDialogTransform != null) {
        _manualScale = _preDialogTransform!.scale;
        _manualOffset = _preDialogTransform!.offset;
        _preDialogTransform = null;
      } else if (shouldKeepCurrentView) {
        _manualScale ??= _current.scale;
        _manualOffset ??= _current.offset;
      } else {
        _manualScale = null;
        _manualOffset = null;
      }
      if (exitingEditorDialog) {
        _preDialogTransform = null;
      }
      _zoomTarget = focus;
      _zoomDialog = dialog;
      final doubleClickPos = LayoutSelection.doubleClickGlobalPosition;
      LayoutSelection.doubleClickGlobalPosition = null;
      if (_controller.enabled &&
          !shouldKeepCurrentView &&
          doubleClickPos != null &&
          activeHoverCtx == null &&
          dialog == null &&
          viewport is RenderBox &&
          viewport.hasSize &&
          _current.scale > 0) {
        final localPointer = viewport.globalToLocal(doubleClickPos);
        final rawContentPt = (localPointer - _current.offset) / _current.scale;
        _anchorViewportPoint = localPointer;
        _anchorContentPoint = rect == null
            ? rawContentPt
            : Offset(
                rawContentPt.dx.clamp(rect.left, rect.right),
                rawContentPt.dy.clamp(rect.top, rect.bottom),
              );
      } else {
        _anchorViewportPoint = null;
        _anchorContentPoint = null;
      }
    }
    if (_controller.enabled && !_viewport.isEmpty) {
      if (shouldKeepCurrentView) {
        destination = (
          scale: _manualScale ?? _current.scale,
          offset: _manualOffset ?? _current.offset,
        );
      } else {
        var available = Offset.zero & _viewport;
        final Rect? reservedScreen;
        if (dialog != null) {
          reservedScreen = options.zoomOnEditorDialog ? dialog.available : null;
        } else if (options.zoomOnRightClick && !isTooLargeForRightClick) {
          reservedScreen = _controller.contextMenuAvailable.value;
        } else {
          reservedScreen = null;
        }
        if (reservedScreen case final screen? when viewport is RenderBox) {
          available = Rect.fromPoints(
            viewport.globalToLocal(screen.topLeft),
            viewport.globalToLocal(screen.bottomRight),
          ).intersect(available);
        }
        if (available.isEmpty) return;
        final effectiveMaxScale = options.maxScale.clamp(
          EditorZoom.minScale,
          EditorZoom.maxScale,
        );
        if (dialog != null &&
            options.zoomOnEditorDialog &&
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
                    .clamp(0.0, effectiveMaxScale);
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
          final hasEditorDialog = dialog != null && options.zoomOnEditorDialog;
          final autoZoomDisabled =
              !hasEditorDialog &&
              _manualScale == null &&
              widget.maxAutoZoomExtent <= 0;
          if (!autoZoomDisabled) {
            final double rawScale;
            if (hasEditorDialog) {
              final zoomInFit = math.min(
                available.width * .7 / rect.width,
                available.height * .7 / rect.height,
              );
              if (zoomInFit >= EditorZoom.minScale) {
                rawScale = zoomInFit;
              } else {
                final padX = math.min(24.0, available.width * .06);
                final padY = math.min(24.0, available.height * .06);
                final tightFit = math.min(
                  math.max(1.0, available.width - padX) / rect.width,
                  math.max(1.0, available.height - padY) / rect.height,
                );
                rawScale = math.min(EditorZoom.minScale, tightFit);
              }
            } else {
              final targetArea =
                  available.width *
                  available.height *
                  options.targetScreenAreaFraction.clamp(0.10, 0.90);
              final selectionArea = rect.width * rect.height;
              final areaScale = math.sqrt(targetArea / selectionArea);
              final fitScale = math.min(
                available.width * .9 / rect.width,
                available.height * .9 / rect.height,
              );
              rawScale = math.min(areaScale, fitScale);
            }
            final minAllowedScale = hasEditorDialog
                ? options.minDialogScale.clamp(0.30, EditorZoom.minScale)
                : EditorZoom.minScale;
            final baseScale = rawScale.clamp(
              minAllowedScale,
              effectiveMaxScale,
            );
            const handleMargin = 28.0;
            final fitWithHandles = math.min(
              math.max(1.0, available.width - handleMargin * 2) / rect.width,
              math.max(1.0, available.height - handleMargin * 2) / rect.height,
            );
            final scale = isHoverFraming
                ? math
                      .min(baseScale, fitWithHandles)
                      .clamp(0.5, effectiveMaxScale)
                : baseScale;
            if (hasEditorDialog ||
                scale > EditorZoom.minScale ||
                isOutOfView ||
                isHoverFraming) {
              final Offset targetOffset;
              if (scale <= EditorZoom.minScale &&
                  !hasEditorDialog &&
                  !isOutOfView &&
                  !isHoverFraming) {
                targetOffset = Offset.zero;
              } else if (!hasEditorDialog &&
                  !isHoverFraming &&
                  _anchorViewportPoint != null &&
                  _anchorContentPoint != null) {
                final desiredOffset =
                    _anchorViewportPoint! - _anchorContentPoint! * scale;
                final margin = math.min(
                  16.0,
                  math.min(available.width, available.height) * 0.05,
                );
                final safe = available.deflate(margin);
                final scaledWidth = rect.width * scale;
                final scaledHeight = rect.height * scale;
                final double dx;
                if (scaledWidth <= safe.width) {
                  final minDx = safe.left - rect.left * scale;
                  final maxDx = safe.right - rect.right * scale;
                  dx = desiredOffset.dx.clamp(
                    math.min(minDx, maxDx),
                    math.max(minDx, maxDx),
                  );
                } else {
                  final minDx = available.right - rect.right * scale;
                  final maxDx = available.left - rect.left * scale;
                  dx = desiredOffset.dx.clamp(
                    math.min(minDx, maxDx),
                    math.max(minDx, maxDx),
                  );
                }
                final double dy;
                if (scaledHeight <= safe.height) {
                  final minDy = safe.top - rect.top * scale;
                  final maxDy = safe.bottom - rect.bottom * scale;
                  dy = desiredOffset.dy.clamp(
                    math.min(minDy, maxDy),
                    math.max(minDy, maxDy),
                  );
                } else {
                  final minDy = available.bottom - rect.bottom * scale;
                  final maxDy = available.top - rect.top * scale;
                  dy = desiredOffset.dy.clamp(
                    math.min(minDy, maxDy),
                    math.max(minDy, maxDy),
                  );
                }
                targetOffset = Offset(dx, dy);
              } else if (hasEditorDialog) {
                final scaledWidth = rect.width * scale;
                final scaledHeight = rect.height * scale;
                final double dx;
                if (scaledWidth <= available.width) {
                  dx = available.center.dx - rect.center.dx * scale;
                } else if (available.left <= 0) {
                  dx = available.left - rect.left * scale;
                } else {
                  dx = available.right - rect.right * scale;
                }
                final double dy;
                if (scaledHeight <= available.height) {
                  dy = available.center.dy - rect.center.dy * scale;
                } else if (available.top <= 0) {
                  dy = available.top - rect.top * scale;
                } else {
                  dy = available.bottom - rect.bottom * scale;
                }
                targetOffset = Offset(dx, dy);
              } else {
                targetOffset = available.center - rect.center * scale;
              }
              destination = (scale: scale, offset: targetOffset);
            }
          }
        }
      }
    }
    final disableAnimations =
        !options.animateTransitions ||
        options.animationDurationMs <= 0 ||
        MediaQuery.disableAnimationsOf(context);
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
      if (_zoomDialog == null && _controller.openContextMenus.value == 0) {
        _preRightClickTransform = _to;
      }
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
        _preRightClickTransform = null;
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
      _preRightClickTransform = null;
      _controller.suppressContextMenu = true;
      EditorZoom.suppressContextMenu = true;
    } else if (_zoomDialog == null && _controller.openContextMenus.value == 0) {
      _preRightClickTransform = null;
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
    if (dialog == null && _controller.openContextMenus.value == 0) {
      _preRightClickTransform = null;
    }
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
    _controller._resetZoomHandler = null;
    LayoutSelection.focus.removeListener(_onFocusChanged);
    EditorSlotState.highlightedTarget.removeListener(_onHighlightChanged);
    _controller.dialog.removeListener(_schedule);
    _controller.contextMenuAvailable.removeListener(_schedule);
    _controller.options.removeListener(_onOptionsChanged);
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

/// Contenu des boutons de contrôle du zoom affiché dans la barre d'édition.
class EditorZoomToolbarContent extends StatelessWidget {
  const EditorZoomToolbarContent({
    required this.scale,
    required this.onScaleChanged,
    required this.onDrag,
    this.onOpenOptions,
    super.key,
  });

  final double scale;
  final ValueChanged<double> onScaleChanged;
  final GestureDragUpdateCallback onDrag;

  /// Action personnalisée d'ouverture des options de zoom.
  /// Par défaut, ouvre [showEditorZoomOptionsDialog] pour le contrôleur courant.
  final VoidCallback? onOpenOptions;

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
    final hasOverlay = Overlay.maybeOf(context) != null;
    if (hasOverlay) {
      handle = Tooltip(message: 'Déplacer la barre de zoom', child: handle);
    }
    Widget optionsButton = SizedBox(
      width: 32,
      height: 36,
      child: IconButton(
        key: const ValueKey('editor-zoom-options-button'),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        icon: const Icon(Icons.tune),
        onPressed:
            onOpenOptions ??
            () {
              final controller = EditorZoomScope.controllerOf(context);
              if (controller != null) {
                showEditorZoomOptionsDialog(context, controller: controller);
              }
            },
      ),
    );
    if (hasOverlay) {
      optionsButton = Tooltip(message: 'Options du zoom', child: optionsButton);
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
          padding: const EdgeInsets.only(right: 4),
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
        Padding(padding: const EdgeInsets.only(right: 4), child: optionsButton),
      ],
    );
  }
}

/// Disposition adaptative de la barre d'outils de zoom en mode édition.
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

/// Portée `InheritedNotifier` fournissant l'[EditorZoomController] aux widgets enfants.
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

/// Contrôleur gérant le facteur d'échelle (zoom) et le décalage (panoramique) du canevas d'édition.
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

  /// Options de comportement du zoom automatique en mode édition.
  final options = ValueNotifier<EditorZoomOptions>(const EditorZoomOptions());

  Offset? toolbarPosition;
  final transform = ValueNotifier<({double scale, Offset offset})>((
    scale: 1.0,
    offset: Offset.zero,
  ));
  void Function(double)? sliderScaleHandler;
  VoidCallback? _resetZoomHandler;
  int _rightClickSelectionDepth = 0;

  /// Indique qu'une sélection est en cours de déclenchement depuis un clic droit.
  bool get isSelectingFromRightClick => _rightClickSelectionDepth > 0;

  /// Marque le début d'une sélection déclenchée par l'ouverture du menu clic droit.
  void beginRightClickSelection() => _rightClickSelectionDepth++;

  /// Marque la fin d'une sélection déclenchée par l'ouverture du menu clic droit.
  void endRightClickSelection() {
    if (_rightClickSelectionDepth > 0) _rightClickSelectionDepth--;
  }

  void setScale(double value) => sliderScaleHandler?.call(value);

  /// Réinitialise immédiatement le zoom à 100% (`1.0`) et le décalage à `Offset.zero`.
  void resetZoom() =>
      (_resetZoomHandler ?? () => sliderScaleHandler?.call(1.0))();

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
    _resetZoomHandler = null;
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
    options.dispose();
    dialog.dispose();
    transform.dispose();
  }
}

/// Options immuables configurant le comportement du zoom et du cadrage automatique
/// en mode édition.
@immutable
class EditorZoomOptions {
  /// Crée une configuration d'options de zoom pour le mode édition.
  const EditorZoomOptions({
    this.skipLargeElementsOnRightClick = true,
    this.skipLargeElementsOnDialog = true,
    this.largeElementViewportThreshold = defaultLargeElementThreshold,
    this.zoomOnRightClick = true,
    this.zoomOnHover = true,
    this.zoomOnSelection = true,
    this.zoomOnEditorDialog = true,
    this.resetZoomOnDialogExit = true,
    this.minDialogScale = defaultMinDialogScale,
    this.maxScale = EditorZoom.maxScale,
    this.targetScreenAreaFraction = EditorZoom.targetScreenAreaFraction,
    this.animateTransitions = true,
    this.animationDurationMs = defaultAnimationDurationMs,
  });

  /// Seuil par défaut (`0.70`, soit 70% de l'écran) au-delà duquel un élément
  /// est considéré comme trop grand pour le zoom au clic droit ou l'ouverture des propriétés.
  static const double defaultLargeElementThreshold = 0.70;

  /// Échelle minimale par défaut (`0.50`, soit 50%) lors du dézoom à côté d'une
  /// boîte de dialogue de propriétés.
  static const double defaultMinDialogScale = 0.50;

  /// Durée par défaut de l'animation de transition du zoom (en millisecondes).
  static const int defaultAnimationDurationMs = 300;

  /// Conserve la vue actuelle sans zoomer ni déplacer le canevas lors d'un clic
  /// droit sur un élément dépassant [largeElementViewportThreshold].
  final bool skipLargeElementsOnRightClick;

  /// Conserve la vue actuelle sans dézoomer lors de l'ouverture d'une boîte de
  /// dialogue de propriétés sur un élément dépassant [largeElementViewportThreshold].
  final bool skipLargeElementsOnDialog;

  /// Proportion maximale (entre `0.30` et `1.0`) du canevas au-delà de laquelle
  /// un élément est considéré comme trop grand.
  final double largeElementViewportThreshold;

  /// Active le zoom et le recadrage automatique lors de l'ouverture du menu
  /// contextuel au clic droit.
  final bool zoomOnRightClick;

  /// Active le zoom/cadrage automatique lors du survol des entrées du menu
  /// contextuel ou de l'arbre de sélection.
  final bool zoomOnHover;

  /// Active le zoom automatique lors de la sélection d'un composant ou d'une
  /// zone sur le canevas.
  final bool zoomOnSelection;

  /// Active le recadrage automatique à côté des boîtes de dialogue d'édition.
  final bool zoomOnEditorDialog;

  /// Retourne automatiquement au zoom et à la position d'avant l'ouverture
  /// de la fenêtre de saisie des propriétés lors de sa fermeture.
  final bool resetZoomOnDialogExit;

  /// Facteur de dézoom minimal autorisé lorsqu'une boîte de dialogue d'édition
  /// est ouverte (entre `0.30` et `1.0`).
  final double minDialogScale;

  /// Facteur de zoom automatique maximal (entre `1.5` et `4.0`).
  final double maxScale;

  /// Fraction cible de la surface d'écran occupée par l'élément zoomé
  /// (entre `0.15` et `0.75`).
  final double targetScreenAreaFraction;

  /// Active les animations fluides lors des transitions de zoom et de cadrage.
  final bool animateTransitions;

  /// Durée de l'animation de zoom en millisecondes (entre `50` et `600`).
  final int animationDurationMs;

  /// Indique si [targetRect] dépasse le seuil [largeElementViewportThreshold]
  /// par rapport à la taille [viewportSize] du canevas.
  bool isElementTooLarge(Rect targetRect, Size viewportSize) {
    if (viewportSize.isEmpty || targetRect.isEmpty || !targetRect.isFinite) {
      return false;
    }
    final threshold = largeElementViewportThreshold.clamp(0.10, 1.0);
    final widthRatio = (targetRect.width / viewportSize.width).clamp(0.0, 1.0);
    final heightRatio = (targetRect.height / viewportSize.height).clamp(
      0.0,
      1.0,
    );
    final areaRatio = widthRatio * heightRatio;
    return (widthRatio >= threshold && heightRatio >= threshold) ||
        areaRatio >= threshold;
  }

  /// Retourne une copie de ces options avec les champs spécifiés mis à jour.
  EditorZoomOptions copyWith({
    bool? skipLargeElementsOnRightClick,
    bool? skipLargeElementsOnDialog,
    double? largeElementViewportThreshold,
    bool? zoomOnRightClick,
    bool? zoomOnHover,
    bool? zoomOnSelection,
    bool? zoomOnEditorDialog,
    bool? resetZoomOnDialogExit,
    double? minDialogScale,
    double? maxScale,
    double? targetScreenAreaFraction,
    bool? animateTransitions,
    int? animationDurationMs,
  }) => EditorZoomOptions(
    skipLargeElementsOnRightClick:
        skipLargeElementsOnRightClick ?? this.skipLargeElementsOnRightClick,
    skipLargeElementsOnDialog:
        skipLargeElementsOnDialog ?? this.skipLargeElementsOnDialog,
    largeElementViewportThreshold:
        largeElementViewportThreshold ?? this.largeElementViewportThreshold,
    zoomOnRightClick: zoomOnRightClick ?? this.zoomOnRightClick,
    zoomOnHover: zoomOnHover ?? this.zoomOnHover,
    zoomOnSelection: zoomOnSelection ?? this.zoomOnSelection,
    zoomOnEditorDialog: zoomOnEditorDialog ?? this.zoomOnEditorDialog,
    resetZoomOnDialogExit: resetZoomOnDialogExit ?? this.resetZoomOnDialogExit,
    minDialogScale: minDialogScale ?? this.minDialogScale,
    maxScale: maxScale ?? this.maxScale,
    targetScreenAreaFraction:
        targetScreenAreaFraction ?? this.targetScreenAreaFraction,
    animateTransitions: animateTransitions ?? this.animateTransitions,
    animationDurationMs: animationDurationMs ?? this.animationDurationMs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorZoomOptions &&
          other.skipLargeElementsOnRightClick ==
              skipLargeElementsOnRightClick &&
          other.skipLargeElementsOnDialog == skipLargeElementsOnDialog &&
          other.largeElementViewportThreshold ==
              largeElementViewportThreshold &&
          other.zoomOnRightClick == zoomOnRightClick &&
          other.zoomOnHover == zoomOnHover &&
          other.zoomOnSelection == zoomOnSelection &&
          other.zoomOnEditorDialog == zoomOnEditorDialog &&
          other.resetZoomOnDialogExit == resetZoomOnDialogExit &&
          other.minDialogScale == minDialogScale &&
          other.maxScale == maxScale &&
          other.targetScreenAreaFraction == targetScreenAreaFraction &&
          other.animateTransitions == animateTransitions &&
          other.animationDurationMs == animationDurationMs;

  @override
  int get hashCode => Object.hash(
    skipLargeElementsOnRightClick,
    skipLargeElementsOnDialog,
    largeElementViewportThreshold,
    zoomOnRightClick,
    zoomOnHover,
    zoomOnSelection,
    zoomOnEditorDialog,
    resetZoomOnDialogExit,
    minDialogScale,
    maxScale,
    targetScreenAreaFraction,
    animateTransitions,
    animationDurationMs,
  );
}

/// Ouvre la boîte de dialogue de configuration des options du zoom en mode édition.
Future<void> showEditorZoomOptionsDialog(
  BuildContext context, {
  EditorZoomController? controller,
}) async {
  final resolved = controller ?? EditorZoomScope.controllerOf(context);
  if (resolved == null || resolved.disposed) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => EditorZoomOptionsDialog(controller: resolved),
  );
}

/// Boîte de dialogue permettant de configurer toutes les options de zoom et de
/// cadrage automatique du mode édition ([EditorZoomOptions]).
class EditorZoomOptionsDialog extends StatelessWidget {
  /// Crée la boîte de dialogue d'options de zoom liée à [controller].
  const EditorZoomOptionsDialog({required this.controller, super.key});

  /// Contrôleur de zoom dont les options sont modifiées en direct.
  final EditorZoomController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      key: const ValueKey('editor-zoom-options-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: ValueListenableBuilder<EditorZoomOptions>(
          valueListenable: controller.options,
          builder: (context, options, _) {
            void update(EditorZoomOptions next) {
              controller.options.value = next;
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Icon(Icons.zoom_in_map, color: colors.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Options du zoom en mode édition',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: controller.scale,
                        builder: (context, currentScale, _) =>
                            FilledButton.tonalIcon(
                              key: const ValueKey('zoom-option-reset-100'),
                              onPressed: controller.resetZoom,
                              icon: const Icon(
                                Icons.center_focus_strong,
                                size: 16,
                              ),
                              label: Text(
                                '100% (${(currentScale * 100).round()}%)',
                              ),
                            ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        key: const ValueKey('zoom-option-close'),
                        tooltip: 'Fermer',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader(
                          icon: Icons.aspect_ratio,
                          title: 'Grands éléments & Clic droit',
                          color: colors.primary,
                        ),
                        SwitchListTile(
                          key: const ValueKey(
                            'zoom-option-skip-large-right-click',
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Ne pas zoomer sur les grands éléments au clic droit',
                          ),
                          subtitle: const Text(
                            'Garde la vue actuelle sans zoomer, dézoomer ni décaler '
                            'l’écran lorsque l’élément occupe une grande partie de l’écran.',
                          ),
                          value: options.skipLargeElementsOnRightClick,
                          onChanged: (value) => update(
                            options.copyWith(
                              skipLargeElementsOnRightClick: value,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-skip-large-dialog'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Ne pas dézoomer les grands éléments à l’ouverture des propriétés',
                          ),
                          subtitle: const Text(
                            'Évite de réduire toute la page lorsqu’une fenêtre de propriétés '
                            'est ouverte sur un élément couvrant l’écran.',
                          ),
                          value: options.skipLargeElementsOnDialog,
                          onChanged: (value) => update(
                            options.copyWith(skipLargeElementsOnDialog: value),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Seuil de taille maximale de l’élément',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(options.largeElementViewportThreshold * 100).round()}% de l’écran',
                                    key: const ValueKey(
                                      'zoom-option-large-threshold-label',
                                    ),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                key: const ValueKey(
                                  'zoom-option-large-threshold-slider',
                                ),
                                min: 0.30,
                                max: 1.00,
                                divisions: 14,
                                value: options.largeElementViewportThreshold
                                    .clamp(0.30, 1.00),
                                onChanged:
                                    options.skipLargeElementsOnRightClick ||
                                        options.skipLargeElementsOnDialog
                                    ? (value) => update(
                                        options.copyWith(
                                          largeElementViewportThreshold: value,
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 16),
                        _SectionHeader(
                          icon: Icons.touch_app_outlined,
                          title: 'Déclencheurs du zoom automatique',
                          color: colors.primary,
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-right-click'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text('Zoom automatique au clic droit'),
                          subtitle: const Text(
                            'Recadre et zoome sur le composant ciblé à côté du menu contextuel.',
                          ),
                          value: options.zoomOnRightClick,
                          onChanged: (value) =>
                              update(options.copyWith(zoomOnRightClick: value)),
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-hover'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Zoom automatique au survol du menu / arbre',
                          ),
                          subtitle: const Text(
                            'Recadre la vue lors du survol des entrées du menu contextuel ou de la hiérarchie.',
                          ),
                          value: options.zoomOnHover,
                          onChanged: (value) =>
                              update(options.copyWith(zoomOnHover: value)),
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-selection'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Zoom automatique lors de la sélection',
                          ),
                          subtitle: const Text(
                            'Zoome sur la zone ou le composant sélectionné par clic ou double-clic sur le canevas.',
                          ),
                          value: options.zoomOnSelection,
                          onChanged: (value) =>
                              update(options.copyWith(zoomOnSelection: value)),
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-editor-dialog'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Recadrage avec les fenêtres d’édition',
                          ),
                          subtitle: const Text(
                            'Centre le composant édité dans l’espace libre à côté des fenêtres de propriétés.',
                          ),
                          value: options.zoomOnEditorDialog,
                          onChanged: (value) => update(
                            options.copyWith(zoomOnEditorDialog: value),
                          ),
                        ),
                        SwitchListTile(
                          key: const ValueKey(
                            'zoom-option-reset-on-dialog-exit',
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Retour au zoom et à la position initiale après la saisie des propriétés',
                          ),
                          subtitle: const Text(
                            'Rétablit le zoom et la position d’avant l’ouverture à la fermeture d’une fenêtre de propriétés.',
                          ),
                          value: options.resetZoomOnDialogExit,
                          onChanged: (value) => update(
                            options.copyWith(resetZoomOnDialogExit: value),
                          ),
                        ),
                        const Divider(height: 16),
                        _SectionHeader(
                          icon: Icons.tune,
                          title: 'Échelle et animation',
                          color: colors.primary,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Niveau de zoom automatique maximum',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(options.maxScale * 100).round()}%',
                                    key: const ValueKey(
                                      'zoom-option-max-scale-label',
                                    ),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                key: const ValueKey(
                                  'zoom-option-max-scale-slider',
                                ),
                                min: 1.5,
                                max: EditorZoom.maxScale,
                                divisions: 25,
                                value: options.maxScale.clamp(
                                  1.5,
                                  EditorZoom.maxScale,
                                ),
                                onChanged: (value) =>
                                    update(options.copyWith(maxScale: value)),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Échelle minimale de dézoom (fenêtres d’édition)',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(options.minDialogScale * 100).round()}%',
                                    key: const ValueKey(
                                      'zoom-option-min-dialog-scale-label',
                                    ),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                key: const ValueKey(
                                  'zoom-option-min-dialog-scale-slider',
                                ),
                                min: 0.30,
                                max: 1.00,
                                divisions: 14,
                                value: options.minDialogScale.clamp(0.30, 1.00),
                                onChanged: (value) => update(
                                  options.copyWith(minDialogScale: value),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Surface cible de l’élément à l’écran',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(options.targetScreenAreaFraction * 100).round()}%',
                                    key: const ValueKey(
                                      'zoom-option-target-area-label',
                                    ),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                key: const ValueKey(
                                  'zoom-option-target-area-slider',
                                ),
                                min: 0.15,
                                max: 0.75,
                                divisions: 12,
                                value: options.targetScreenAreaFraction.clamp(
                                  0.15,
                                  0.75,
                                ),
                                onChanged: (value) => update(
                                  options.copyWith(
                                    targetScreenAreaFraction: value,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-animate'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text('Animer les transitions de zoom'),
                          subtitle: Text(
                            options.animateTransitions
                                ? 'Durée : ${options.animationDurationMs} ms'
                                : 'Transitions instantanées',
                          ),
                          value: options.animateTransitions,
                          onChanged: (value) => update(
                            options.copyWith(animateTransitions: value),
                          ),
                        ),
                        if (options.animateTransitions)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                            child: Slider(
                              key: const ValueKey(
                                'zoom-option-animation-duration-slider',
                              ),
                              min: 50,
                              max: 600,
                              divisions: 11,
                              value: options.animationDurationMs
                                  .toDouble()
                                  .clamp(50, 600),
                              onChanged: (value) => update(
                                options.copyWith(
                                  animationDurationMs: value.round(),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('zoom-option-restore-defaults'),
                        onPressed: options == const EditorZoomOptions()
                            ? null
                            : () => update(const EditorZoomOptions()),
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Valeurs par défaut'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Terminé'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// Notifieur suivant l'ouverture et le focus des boîtes de dialogue d'édition flottantes.
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

/// Portée identifiant la boîte de dialogue d'édition active pour isoler ses événements de pointeur.
class EditorDialogFocus {
  EditorDialogFocus({required this.target});
  BuildContext? target;
  Rect? available;
}
