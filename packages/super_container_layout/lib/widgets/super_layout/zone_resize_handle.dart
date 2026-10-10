part of '../super_layout.dart';

class _ZoneResizeHandle extends StatefulWidget {
  const _ZoneResizeHandle({
    required this.zone,
    required this.onResize,
    required this.bounds,
    required this.onCollapse,
    this.restoreSize,
  });

  final SuperLayoutZone zone;
  final ValueChanged<double> onResize;
  final ({double min, double max}) Function(Size) bounds;
  final ValueChanged<double> onCollapse;
  final double? restoreSize;

  @override
  State<_ZoneResizeHandle> createState() => _ZoneResizeHandleState();
}

class _ZoneResizeHandleState extends State<_ZoneResizeHandle> {
  _RenderZoneLayout? _layout;
  Offset? _start;
  double _extent = 0;
  bool _reportedBlocked = false;
  bool _borderHovered = false;
  bool _controlsHovered = false;

  bool get _hovered => _borderHovered || _controlsHovered;

  bool get _vertical =>
      widget.zone == SuperLayoutZone.north ||
      widget.zone == SuperLayoutZone.south;

  void _begin(DragStartDetails details) {
    final layout = context.findAncestorRenderObjectOfType<_RenderZoneLayout>()!;
    final rect = layout.rects[widget.zone]!;
    _layout = layout;
    _start = layout.globalToLocal(details.globalPosition);
    _extent = _vertical ? rect.height : rect.width;
    _reportedBlocked = false;
  }

  void _drag(DragUpdateDetails details) {
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
  }

  void _collapse() {
    final layout = context.findAncestorRenderObjectOfType<_RenderZoneLayout>()!;
    final rect = layout.rects[widget.zone]!;
    widget.onCollapse(_vertical ? rect.height : rect.width);
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
        'Redimensionnement de ${widget.zone.label} impossible : '
        'les bornes min/max sont incompatibles avec l’espace disponible.';
    debugPrint(message);
    if (Scaffold.maybeOf(context) != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _expand() {
    final layout = context.findAncestorRenderObjectOfType<_RenderZoneLayout>()!;
    final bounds = _limits(layout);
    if (bounds.max < bounds.min) {
      _reportBlocked();
      return;
    }
    widget.onResize(
      (widget.restoreSize ?? bounds.max).clamp(bounds.min, bounds.max),
    );
  }

  Widget _button(String action, IconData icon, VoidCallback? onTap) => SizedBox(
    width: 15,
    height: 15,
    child: Tooltip(
      message: action == 'collapse'
          ? 'Réduire ${widget.zone.label}'
          : widget.restoreSize != null
          ? 'Restaurer ${widget.zone.label}'
          : 'Agrandir ${widget.zone.label} au maximum',
      child: GestureDetector(
        key: ValueKey('super-layout-$action-${widget.zone.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: Icon(
            icon,
            size: 15,
            color: onTap == null
                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .38)
                : _hovered
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    ),
  );

  Widget _draggable(Widget child, {Key? key}) => GestureDetector(
    key: key,
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
    child: child,
  );

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Align(
        alignment: switch (widget.restoreSize != null
            ? widget.zone.opposite
            : widget.zone) {
          SuperLayoutZone.north => Alignment.bottomCenter,
          SuperLayoutZone.south => Alignment.topCenter,
          SuperLayoutZone.west => Alignment.centerRight,
          _ => Alignment.centerLeft,
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _borderHovered = true),
          onExit: (_) => setState(() => _borderHovered = false),
          cursor: _vertical
              ? SystemMouseCursors.resizeUpDown
              : SystemMouseCursors.resizeLeftRight,
          child: _draggable(
            SizedBox(
              width: _vertical ? double.infinity : 5,
              height: _vertical ? 5 : double.infinity,
              key: ValueKey('super-layout-resize-${widget.zone.name}'),
              child: ColoredBox(
                color: _hovered
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant.withAlpha(128),
              ),
            ),
          ),
        ),
      ),
      Center(
        child: Transform.translate(
          offset: getOffsetZoneAction(widget.zone == SuperLayoutZone.north || widget.zone == SuperLayoutZone.west),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: MouseRegion(
              onEnter: (_) => setState(() => _controlsHovered = true),
              onExit: (_) => setState(() => _controlsHovered = false),
              cursor: _vertical
                  ? SystemMouseCursors.resizeUpDown
                  : SystemMouseCursors.resizeLeftRight,
              child: _draggable(
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _hovered
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest
                            .withAlpha(128),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Flex(
                    direction: _vertical ? Axis.horizontal : Axis.vertical,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _button('collapse', switch (widget.zone) {
                        SuperLayoutZone.north => Icons.arrow_drop_up,
                        SuperLayoutZone.south => Icons.arrow_drop_down,
                        SuperLayoutZone.west => Icons.arrow_left,
                        _ => Icons.arrow_right,
                      }, widget.restoreSize == null ? _collapse : null),
                      SizedBox(
                        width: _vertical ? 8 : 0,
                        height: _vertical ? 0 : 8,
                      ),
                      for (var index = 0; index < 3; index++)
                        Padding(
                          padding: _vertical
                              ? const EdgeInsets.symmetric(horizontal: 2)
                              : const EdgeInsets.symmetric(vertical: 2),
                          child: SizedBox(
                            width: 3,
                            height: 3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: _vertical ? 8 : 0,
                        height: _vertical ? 0 : 8,
                      ),
                      _button('expand', switch (widget.zone) {
                        SuperLayoutZone.north => Icons.arrow_drop_down,
                        SuperLayoutZone.south => Icons.arrow_drop_up,
                        SuperLayoutZone.west => Icons.arrow_right,
                        _ => Icons.arrow_left,
                      }, _expand),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
  Offset getOffsetZoneAction(bool isNorW) {
    if (isNorW) {
      return widget.restoreSize != null
          ? Offset(_vertical ? 0 : -10, _vertical ? -10 : 0)
          : Offset(_vertical ? 0 : 10, _vertical ? 10 : 0);
    } else {
      return widget.restoreSize != null
          ? Offset(_vertical ? 0 : 10, _vertical ? 10 : 0)
          : Offset(_vertical ? 0 : -10, _vertical ? -10 : 0);
    }
  }
}
