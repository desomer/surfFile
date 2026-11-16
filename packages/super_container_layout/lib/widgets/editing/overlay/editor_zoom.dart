/// Contrôleur et barre d'outils de zoom/panoramique du canevas en mode édition ([EditorZoomController]).
library;

export 'editor_zoom_controls.dart';
export 'editor_zoom_options.dart' show EditorZoomOptions;

import 'dart:async';
import 'dart:math' as math;

import 'editor_zoom_controls.dart';
import 'editor_zoom_options.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderSliver;
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
  static const minScale = EditorZoomOptions.defaultMinScale;
  static const maxScale = EditorZoomOptions.defaultMaxScale;
  static const targetScreenAreaFraction =
      EditorZoomOptions.defaultTargetScreenAreaFraction;

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
    duration: const Duration(
      milliseconds: EditorZoomOptions.defaultAnimationDurationMs,
    ),
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
  BuildContext? _lastHoverTarget;
  bool _wasKeepingCurrentView = false;
  bool _wasContextMenuOpen = false;
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
    _controller.openContextMenus.addListener(_schedule);
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
    if (!_wasContextMenuOpen && hasContextMenu && _zoomDialog == null) {
      _preRightClickTransform ??= _to;
    }
    _wasContextMenuOpen = hasContextMenu;
    final isRightClickContext = hasContextMenu || _focusFromRightClick;
    final highlighted = _debouncedHighlight;
    final rawHoverCtx = highlighted != null && highlighted.mounted
        ? highlighted.context
        : null;
    final BuildContext? activeHoverCtx = options.zoomOnHover
        ? rawHoverCtx
        : null;
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
        activeHoverCtx == null &&
        isRightClickContext &&
        options.skipLargeElementsOnRightClick &&
        rect != null &&
        options.isElementTooLarge(rect, _viewport);
    final isTooLargeForDialog =
        activeHoverCtx == null &&
        dialog != null &&
        EditorInsertionPreview.active.value == null &&
        options.skipLargeElementsOnDialog &&
        rect != null &&
        options.isElementTooLarge(rect, _viewport);
    final shouldKeepCurrentView =
        _controller.enabled &&
        activeHoverCtx == null &&
        ((dialog != null &&
                (!options.zoomOnEditorDialog || isTooLargeForDialog)) ||
            (dialog == null &&
                isRightClickContext &&
                (!options.zoomOnRightClick || isTooLargeForRightClick)) ||
            (dialog == null &&
                !isRightClickContext &&
                focus != null &&
                !options.zoomOnSelection));
    final enteringEditorDialog = _zoomDialog == null && dialog != null;
    final exitingEditorDialog = _zoomDialog != null && dialog == null;
    if (enteringEditorDialog) {
      _preDialogTransform = _preRightClickTransform ?? _to;
      _preRightClickTransform = null;
    }
    final hoverTargetChanged = !identical(activeHoverCtx, _lastHoverTarget);
    final keepCurrentViewChanged =
        shouldKeepCurrentView != _wasKeepingCurrentView;
    if (!_controller.enabled ||
        !identical(focus, _zoomTarget) ||
        !identical(dialog, _zoomDialog) ||
        hoverTargetChanged ||
        keepCurrentViewChanged) {
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
      } else if (activeHoverCtx != null) {
        _manualScale = null;
        _manualOffset = null;
      } else if (shouldKeepCurrentView) {
        if (_lastHoverTarget != null && _preRightClickTransform != null) {
          _manualScale = _preRightClickTransform!.scale;
          _manualOffset = _preRightClickTransform!.offset;
        } else {
          _manualScale ??= _current.scale;
          _manualOffset ??= _current.offset;
        }
      } else {
        _manualScale = null;
        _manualOffset = null;
      }
      if (exitingEditorDialog) {
        _preDialogTransform = null;
      }
      _zoomTarget = focus;
      _zoomDialog = dialog;
      _lastHoverTarget = activeHoverCtx;
      _wasKeepingCurrentView = shouldKeepCurrentView;
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
        } else if ((options.zoomOnRightClick && !isTooLargeForRightClick) ||
            activeHoverCtx != null) {
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
              rawScale = math.min(
                available.width * .7 / rect.width,
                available.height * .7 / rect.height,
              );
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
            final handleMargin = math.min(
              28.0,
              math.min(available.width, available.height) * 0.08,
            );
            final fitWithHandles = math.min(
              math.max(1.0, available.width - handleMargin * 2) / rect.width,
              math.max(1.0, available.height - handleMargin * 2) / rect.height,
            );
            final scale = isHoverFraming
                ? math
                      .min(baseScale, fitWithHandles)
                      .clamp(0.15, effectiveMaxScale)
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
        if (_controller.openContextMenus.value > 0) {
          _preRightClickTransform = next;
        }
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
      if (_controller.openContextMenus.value > 0) {
        _preRightClickTransform = (
          scale: _manualScale!,
          offset: _manualOffset!,
        );
      }
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
    if (_controller.openContextMenus.value > 0) {
      _preRightClickTransform = (scale: nextScale, offset: nextOffset);
    } else if (dialog == null) {
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
    _controller.openContextMenus.removeListener(_schedule);
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
    final content = contentContext!.findRenderObject();
    if (content is! RenderBox || !content.attached || !content.hasSize) {
      return null;
    }
    var belongs = identical(targetContext, contentContext);
    targetContext.visitAncestorElements((element) {
      if (identical(element, contentContext)) belongs = true;
      return !belongs;
    });
    if (!belongs) {
      var wrapsContent = false;
      contentContext!.visitAncestorElements((element) {
        if (identical(element, targetContext)) wrapsContent = true;
        return !wrapsContent;
      });
      return wrapsContent ? Offset.zero & content.size : null;
    }
    final target = targetContext.findRenderObject();
    if (target == null || !target.attached) {
      return null;
    }
    if (target is RenderBox) {
      if (!target.hasSize) return null;
      return MatrixUtils.transformRect(
        target.getTransformTo(content),
        Offset.zero & target.size,
      );
    }
    if (target is RenderSliver) {
      final geom = target.geometry;
      if (geom == null || geom.paintExtent <= 0) return null;
      final size = target.constraints.axis == Axis.vertical
          ? Size(target.constraints.crossAxisExtent, geom.paintExtent)
          : Size(geom.paintExtent, target.constraints.crossAxisExtent);
      if (size.isEmpty || !size.isFinite) return null;
      return MatrixUtils.transformRect(
        target.getTransformTo(content),
        Offset.zero & size,
      );
    }
    return null;
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
