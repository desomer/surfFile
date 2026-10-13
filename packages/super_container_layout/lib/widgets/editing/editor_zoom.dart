import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../super_layout/layout_selection.dart';
import '../surfaces/super_container.dart';

/// Animates the page around the selected layout, zone or slot.
class EditorZoom extends StatefulWidget {
  const EditorZoom({required this.child, super.key});

  final Widget child;

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
  double? _manualScale;
  bool _framingHeld = false;

  @override
  void initState() {
    super.initState();
    _controller._pointerSignalHandler = _onPointerSignal;
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
    _controller.dialog.addListener(_schedule);
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
    final dialog = _controller.dialog.value;
    final focus = dialog?.target ?? LayoutSelection.focus.value?.context;
    if (!_controller.enabled || !identical(focus, _zoomTarget)) {
      _manualScale = null;
      _zoomTarget = focus;
    }
    _controller.contentContext = _content.currentContext;
    final rect = _controller.targetBounds(focus);
    if (_controller.enabled && rect != null) {
      if (!rect.isEmpty && rect.isFinite && !_viewport.isEmpty) {
        var available = Offset.zero & _viewport;
        final viewport = _viewportKey.currentContext?.findRenderObject();
        if (dialog?.available case final screen? when viewport is RenderBox) {
          available = Rect.fromPoints(
            viewport.globalToLocal(screen.topLeft),
            viewport.globalToLocal(screen.bottomRight),
          ).intersect(available);
        }
        if (available.isEmpty) return;
        final automaticScale = math
            .min(
              available.width * .7 / rect.width,
              available.height * .7 / rect.height,
            )
            .clamp(dialog == null ? 1.0 : 0.0, 3.0);
        final scale = _manualScale ?? automaticScale;
        destination = (
          scale: scale,
          offset: _manualScale == null
              ? available.center - rect.center * scale
              : (available.center - rect.center * 3) * ((scale - 1) / 2),
        );
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
      setState(() => _current = _to);
    } else {
      _animation.forward(from: 0);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        !event.scrollDelta.dy.isFinite ||
        !(_editMode?.value ?? false) || _framingHeld) {
      return;
    }
    final focus =
        _controller.dialog.value?.target ??
        LayoutSelection.focus.value?.context;
    final rect = _controller.targetBounds(focus);
    if (rect == null || rect.isEmpty || !rect.isFinite) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted) return;
      _frameSelection();
      _manualScale =
          (_to.scale *
                  math.exp(-event.scrollDelta.dy.clamp(-1200.0, 1200.0) * .0025))
              .clamp(1.0, 3.0);
      _frameSelection();
    });
  }

  void _animate() {
    final progress = Curves.easeInOutCubic.transform(_animation.value);
    setState(() {
      _current = (
        scale: _from.scale + (_to.scale - _from.scale) * progress,
        offset: Offset.lerp(_from.offset, _to.offset, progress)!,
      );
    });
  }

  @override
  void dispose() {
    LayoutSelection.focus.removeListener(_schedule);
    _controller.dialog.removeListener(_schedule);
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
        return Listener(
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
        );
      },
    ),
  );
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

  static EditorZoomController? controllerOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EditorZoomScope>()?.controller;

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EditorZoomScope>() != null;

  @override
  bool updateShouldNotify(EditorZoomScope oldWidget) =>
      scale != oldWidget.scale ||
      offset != oldWidget.offset ||
      controller != oldWidget.controller;
}

class EditorZoomController {
  void Function(PointerSignalEvent)? _pointerSignalHandler;
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

  bool enabled = false;
  bool disposed = false;
  final dialog = EditorDialogNotifier();
  BuildContext? contentContext;

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
    dialog.dispose();
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

  void geometryChanged() => notifyListeners();
}

class EditorDialogFocus {
  EditorDialogFocus({required this.target});
  final BuildContext? target;
  Rect? available;
}
