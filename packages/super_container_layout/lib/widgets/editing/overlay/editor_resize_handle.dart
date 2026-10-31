import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../theme/appearance.dart';
import 'editor_zoom.dart';

const editorResizeDirections = [
  ('nw', Alignment.topLeft),
  ('ne', Alignment.topRight),
  ('sw', Alignment.bottomLeft),
  ('se', Alignment.bottomRight),
  ('n', Alignment.topCenter),
  ('s', Alignment.bottomCenter),
  ('w', Alignment.centerLeft),
  ('e', Alignment.centerRight),
];

/// Screen-sized modern neon grip shared by zone and grid slot editors.
class EditorResizeHandle extends StatefulWidget {
  const EditorResizeHandle({
    required this.direction,
    required this.label,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    super.key,
  });
  final Alignment direction;
  final String label;
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final VoidCallback onEnd;

  @override
  State<EditorResizeHandle> createState() => _EditorResizeHandleState();
}

class _EditorResizeHandleState extends State<EditorResizeHandle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppearanceScope.of(context).accent;
    final d = widget.direction;
    return SizedBox(
      width: 32,
      height: 32,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: d.x == 0
            ? SystemMouseCursors.resizeUpDown
            : d.y == 0
            ? SystemMouseCursors.resizeLeftRight
            : d.x == d.y
            ? SystemMouseCursors.resizeUpLeftDownRight
            : SystemMouseCursors.resizeUpRightDownLeft,
        child: Listener(
          onPointerSignal: (event) =>
              EditorZoomScope.controllerOf(context)?.handlePointerSignal(event),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: widget.onStart,
            onPanUpdate: widget.onUpdate,
            onPanEnd: (_) => widget.onEnd(),
            onPanCancel: widget.onEnd,
            child: Tooltip(
              message: d.x == 0
                  ? 'Modifier la hauteur de ${widget.label}'
                  : d.y == 0
                  ? 'Modifier la largeur de ${widget.label}'
                  : 'Redimensionner ${widget.label}',
              child: Align(
                alignment: d,
                child: CustomPaint(
                  painter: _ModernResizeAnchorPainter(
                    direction: d,
                    color: accent,
                    hovered: _hover,
                  ),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _hover ? accent : Colors.white,
                      borderRadius: BorderRadius.circular(2.5),
                      border: Border.all(
                        color: _hover ? Colors.white : accent,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: _hover ? 0.80 : 0.48),
                          blurRadius: _hover ? 8.0 : 4.5,
                          spreadRadius: _hover ? 1.5 : 0.5,
                        ),
                      ],
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
}

class _ModernResizeAnchorPainter extends CustomPainter {
  const _ModernResizeAnchorPainter({
    required this.direction,
    required this.color,
    required this.hovered,
  });

  final Alignment direction;
  final Color color;
  final bool hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final isCorner = direction.x != 0 && direction.y != 0;
    final strokeColor = hovered ? Colors.white : color;

    if (isCorner) {
      // Brackets d'angle modernes autour du point d'ancrage
      final arm = hovered ? 8.5 : 6.5;
      final offset = hovered ? -2.0 : -1.0;
      final cornerX = direction.x < 0 ? offset : size.width - offset;
      final cornerY = direction.y < 0 ? offset : size.height - offset;
      final dirX = direction.x < 0 ? 1.0 : -1.0;
      final dirY = direction.y < 0 ? 1.0 : -1.0;

      final path = Path()
        ..moveTo(cornerX + dirX * arm, cornerY)
        ..lineTo(cornerX, cornerY)
        ..lineTo(cornerX, cornerY + dirY * arm);

      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: hovered ? 0.70 : 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = hovered ? 4.5 : 3.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = hovered ? 2.2 : 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }

    // Barre pilule moderne sur les côtés (N, S, E, W)
    final isHorizontalEdge = direction.x == 0;
    final pillWidth = isHorizontalEdge ? (hovered ? 18.0 : 14.0) : 4.0;
    final pillHeight = isHorizontalEdge ? 4.0 : (hovered ? 18.0 : 14.0);
    final pillRect = Rect.fromCenter(
      center: center,
      width: pillWidth,
      height: pillHeight,
    );
    final pillRRect = RRect.fromRectAndRadius(
      pillRect,
      const Radius.circular(3),
    );

    canvas.drawRRect(
      pillRRect,
      Paint()
        ..color = color.withValues(alpha: hovered ? 0.65 : 0.36)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );
    canvas.drawRRect(
      pillRRect,
      Paint()..color = color.withValues(alpha: hovered ? 0.95 : 0.75),
    );
  }

  @override
  bool shouldRepaint(_ModernResizeAnchorPainter oldDelegate) =>
      oldDelegate.direction != direction ||
      oldDelegate.color != color ||
      oldDelegate.hovered != hovered;
}
