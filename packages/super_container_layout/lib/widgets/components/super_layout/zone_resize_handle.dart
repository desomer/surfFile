// Poignée interactive de redimensionnement d'une zone cardinale ([ZoneResizeHandle]).
part of 'super_layout.dart';

class _ZoneResizeHandle extends StatefulWidget {
  const _ZoneResizeHandle({
    required this.zone,
    required this.label,
    required this.onResize,
    required this.bounds,
    required this.onCollapse,
    this.restoreSize,
  });

  final SuperLayoutZone zone;
  final String label;
  final ValueChanged<double> onResize;
  final ({double min, double max}) Function(Size) bounds;
  final ValueChanged<double> onCollapse;
  final double? restoreSize;

  @override
  State<_ZoneResizeHandle> createState() => _ZoneResizeHandleState();
}

class _ZoneResizeHandleState extends State<_ZoneResizeHandle> {
  static const double _lineThickness = 2.0;
  static const Duration _doubleClickTimeout = Duration(milliseconds: 300);
  static const double _tapMovementSlop = 4.0;
  static const double _doubleClickSlop = 18.0;

  _RenderZoneLayout? _layout;
  Offset? _start;
  double _extent = 0;
  bool _reportedBlocked = false;
  bool _hovered = false;
  bool _dragging = false;

  int? _activePointer;
  Offset? _pointerDownPos;
  bool _pointerMoved = false;
  Offset? _lastTapPos;
  Timer? _doubleClickTimer;

  bool get _active => _hovered || _dragging;

  bool get _vertical =>
      widget.zone == SuperLayoutZone.north ||
      widget.zone == SuperLayoutZone.south;

  @override
  void dispose() {
    _doubleClickTimer?.cancel();
    super.dispose();
  }

  void _clearPendingDoubleClick() {
    _doubleClickTimer?.cancel();
    _doubleClickTimer = null;
    _lastTapPos = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    _activePointer = event.pointer;
    _pointerDownPos = event.position;
    _pointerMoved = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _pointerDownPos == null) return;
    if ((event.position - _pointerDownPos!).distance > _tapMovementSlop) {
      _pointerMoved = true;
      _clearPendingDoubleClick();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    final downPos = _pointerDownPos;
    final moved = _pointerMoved;
    _activePointer = null;
    _pointerDownPos = null;
    _pointerMoved = false;
    if (moved || downPos == null) return;
    if ((event.position - downPos).distance > _tapMovementSlop) return;

    final previousPos = _lastTapPos;
    if ((_doubleClickTimer?.isActive ?? false) &&
        previousPos != null &&
        (event.position - previousPos).distance <= _doubleClickSlop) {
      _clearPendingDoubleClick();
      _toggleCollapse();
      return;
    }

    _doubleClickTimer?.cancel();
    _lastTapPos = event.position;
    _doubleClickTimer = Timer(_doubleClickTimeout, () {
      _doubleClickTimer = null;
      _lastTapPos = null;
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _pointerDownPos = null;
    _pointerMoved = false;
  }

  void _begin(DragStartDetails details) {
    EditorHistoryScope.controllerOf(context)?.beginTransaction();
    final layout = context.findAncestorRenderObjectOfType<_RenderZoneLayout>()!;
    final rect = layout.rects[widget.zone]!;
    _layout = layout;
    _start = layout.globalToLocal(details.globalPosition);
    _extent = _vertical ? rect.height : rect.width;
    _reportedBlocked = false;
    if (!_dragging) setState(() => _dragging = true);
  }

  void _drag(DragUpdateDetails details) {
    _clearPendingDoubleClick();
    final layout = _layout;
    final start = _start;
    if (layout == null || start == null || !layout.attached) return;
    final position = layout.globalToLocal(details.globalPosition);
    final delta = _vertical ? position.dy - start.dy : position.dx - start.dx;
    final growsForward =
        widget.zone == SuperLayoutZone.north ||
        widget.zone == SuperLayoutZone.west;
    final bounds = _limits(layout);
    final upper = bounds.max;
    if (upper < bounds.min) {
      if (!_reportedBlocked) {
        _reportedBlocked = true;
        _reportBlocked();
      }
      return;
    }
    widget.onResize(
      (_extent + (growsForward ? delta : -delta)).clamp(bounds.min, upper),
    );
  }

  void _finish() {
    _layout = null;
    _start = null;
    if (mounted && _dragging) setState(() => _dragging = false);
    EditorHistoryScope.controllerOf(context)?.commitTransaction();
  }

  void _toggleCollapse() {
    final layout = context.findAncestorRenderObjectOfType<_RenderZoneLayout>()!;
    final restore = widget.restoreSize;
    if (restore == null) {
      final rect = layout.rects[widget.zone]!;
      widget.onCollapse(_vertical ? rect.height : rect.width);
      return;
    }
    final bounds = _limits(layout);
    if (bounds.max < bounds.min) {
      _reportBlocked();
      return;
    }
    widget.onResize(restore.clamp(bounds.min, bounds.max));
  }

  ({double min, double max}) _limits(_RenderZoneLayout layout) {
    final opposite = layout.rects[widget.zone.opposite];
    final remaining =
        (_vertical ? layout.size.height : layout.size.width) -
        (opposite == null
            ? 0
            : _vertical
            ? opposite.height
            : opposite.width) -
        SuperLayoutConfig.minSize;
    final bounds = widget.bounds(layout.size);
    return (
      min: bounds.min,
      max: remaining < bounds.max ? remaining : bounds.max,
    );
  }

  void _reportBlocked() {
    final message =
        'Redimensionnement de ${widget.label} impossible : '
        'les bornes min/max sont incompatibles avec l’espace disponible.';
    debugPrint(message);
    if (Scaffold.maybeOf(context) != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Alignment get _lineAlignment {
    if (widget.restoreSize == null) return Alignment.center;
    return switch (widget.zone) {
      SuperLayoutZone.north => Alignment.topCenter,
      SuperLayoutZone.south => Alignment.bottomCenter,
      SuperLayoutZone.west => Alignment.centerLeft,
      _ => Alignment.centerRight,
    };
  }

  @override
  Widget build(BuildContext context) => EditorOverlay(
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: _vertical
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: GestureDetector(
          key: ValueKey('super-layout-resize-${widget.zone.name}'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onVerticalDragStart: _vertical ? _begin : null,
          onVerticalDragUpdate: _vertical ? _drag : null,
          onVerticalDragEnd: _vertical ? (_) => _finish() : null,
          onHorizontalDragStart: !_vertical ? _begin : null,
          onHorizontalDragUpdate: !_vertical ? _drag : null,
          onHorizontalDragEnd: !_vertical ? (_) => _finish() : null,
          onVerticalDragCancel: _vertical ? _finish : null,
          onHorizontalDragCancel: !_vertical ? _finish : null,
          child: SizedBox.expand(
            child: Align(
              alignment: _lineAlignment,
              child: AnimatedOpacity(
                opacity: _active ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: SizedBox(
                  width: _vertical ? double.infinity : _lineThickness,
                  height: _vertical ? _lineThickness : double.infinity,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
