import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Sélection par cadre (clic gauche + glisser) au-dessus d'une vue défilante,
/// avec défilement automatique quand le pointeur approche du bord haut ou bas.
///
/// Ctrl au début du glisser inverse la sélection existante sous le cadre ;
/// un simple clic dans le vide vide la sélection.
class DragSelectRegion extends StatefulWidget {
  const DragSelectRegion({
    required this.builder,
    required this.hitTest,
    required this.selectedIndexes,
    required this.onChanged,
    this.reveal,
    this.revealToken,
    this.onViewport,
    super.key,
  });

  /// Construit la vue défilante, qui doit utiliser [controller].
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  /// Indices des éléments qui croisent [rect], exprimé dans le repère du
  /// contenu défilant (origine en haut du contenu, pas de la zone visible).
  final Iterable<int> Function(Rect rect, Size viewport) hitTest;

  final Set<int> Function() selectedIndexes;
  final ValueChanged<Set<int>> onChanged;

  /// Zone (repère du contenu) à rendre visible quand [revealToken] change.
  final Rect? Function(Size viewport)? reveal;
  final Object? revealToken;

  /// Taille de la zone visible, à chaque mise en page.
  final ValueChanged<Size>? onViewport;

  @override
  State<DragSelectRegion> createState() => DragSelectRegionState();
}

@visibleForTesting
class DragSelectRegionState extends State<DragSelectRegion>
    with SingleTickerProviderStateMixin {
  static const dragThreshold = 6.0;
  static const edge = 48.0;
  static const _speed = 900.0;
  static const _scrollbarWidth = 14.0;

  final _controller = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  int? _pointer;
  Offset _down = Offset.zero;
  double _downOffset = 0;
  Offset _current = Offset.zero;
  bool _dragging = false;
  bool _additive = false;
  Set<int> _base = const {};
  Set<int> _last = const {};
  Duration? _lastTick;
  Size _size = Size.zero;

  bool get dragging => _dragging;

  double get _offset => _controller.hasClients ? _controller.offset : 0;

  Rect get _contentRect => Rect.fromPoints(
    Offset(_down.dx, _down.dy + _downOffset),
    Offset(_current.dx, _current.dy + _offset),
  );

  @override
  void didUpdateWidget(DragSelectRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revealToken != oldWidget.revealToken && !_dragging) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal() {
    final rect = widget.reveal?.call(_size);
    if (!mounted || rect == null || !_controller.hasClients) return;
    final position = _controller.position;
    const margin = 12.0;
    final double target;
    if (rect.top - margin < position.pixels) {
      target = rect.top - margin;
    } else if (rect.bottom + margin > position.pixels + _size.height) {
      target = rect.bottom + margin - _size.height;
    } else {
      return;
    }
    _controller.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent event) {
    if (_pointer != null ||
        event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryButton ||
        event.localPosition.dx > _size.width - _scrollbarWidth) {
      return;
    }
    _pointer = event.pointer;
    _down = _current = event.localPosition;
    _downOffset = _offset;
    _dragging = false;
    _additive = HardwareKeyboard.instance.isControlPressed;
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _current = event.localPosition;
    if (!_dragging) {
      if ((_current - _down).distance < dragThreshold) return;
      _dragging = true;
      _base = _additive ? widget.selectedIndexes() : const {};
      _last = widget.selectedIndexes();
      _lastTick = null;
      _ticker.start();
    }
    _update();
  }

  void _onUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (!_dragging &&
        event is PointerUpEvent &&
        !_additive &&
        !HardwareKeyboard.instance.isShiftPressed) {
      final point = Offset(_down.dx, _down.dy + _offset);
      if (widget.hitTest(Rect.fromPoints(point, point), _size).isEmpty &&
          widget.selectedIndexes().isNotEmpty) {
        widget.onChanged(const {});
      }
    }
    _pointer = null;
    _ticker.stop();
    if (_dragging) setState(() => _dragging = false);
  }

  void _update() {
    final hits = widget.hitTest(_contentRect, _size).toSet();
    final next = _additive
        ? _base.union(hits).difference(_base.intersection(hits))
        : hits;
    if (!setEquals(next, _last)) {
      _last = next;
      widget.onChanged(next);
    }
    setState(() {});
  }

  void _tick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null || !_dragging || !_controller.hasClients) return;
    final seconds = (elapsed - previous).inMicroseconds / 1e6;
    final y = _current.dy;
    final factor = y < edge
        ? -((edge - y) / edge).clamp(0.0, 3.0)
        : y > _size.height - edge
        ? ((y - _size.height + edge) / edge).clamp(0.0, 3.0)
        : 0.0;
    if (factor == 0) return;
    final position = _controller.position;
    final target = (position.pixels + factor * _speed * seconds).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    _controller.jumpTo(target);
    _update();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_size != constraints.biggest) {
          _size = constraints.biggest;
          final onViewport = widget.onViewport;
          if (onViewport != null) {
            final size = _size;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) onViewport(size);
            });
          }
        }
        final colors = Theme.of(context).colorScheme;
        return Listener(
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.builder(context, _controller),
              if (_dragging)
                IgnorePointer(
                  child: ClipRect(
                    child: CustomPaint(
                      key: const ValueKey('drag-select-marquee'),
                      painter: _MarqueePainter(
                        rect: _contentRect.shift(Offset(0, -_offset)),
                        color: colors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MarqueePainter extends CustomPainter {
  const _MarqueePainter({required this.rect, required this.color});

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    canvas.drawRRect(shape, Paint()..color = color.withValues(alpha: .14));
    canvas.drawRRect(
      shape,
      Paint()
        ..color = color.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_MarqueePainter old) =>
      old.rect != rect || old.color != color;
}
