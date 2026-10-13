import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'editor_zoom.dart';

const editorResizeDirections = [
  ('nw', Alignment.topLeft), ('ne', Alignment.topRight),
  ('sw', Alignment.bottomLeft), ('se', Alignment.bottomRight),
  ('n', Alignment.topCenter), ('s', Alignment.bottomCenter),
  ('w', Alignment.centerLeft), ('e', Alignment.centerRight),
];

/// Screen-sized grip shared by zone and grid slot editors.
class EditorResizeHandle extends StatefulWidget {
  const EditorResizeHandle({
    required this.direction, required this.label,
    required this.onStart, required this.onUpdate, required this.onEnd,
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
    final colors = Theme.of(context).colorScheme;
    final d = widget.direction;
    return SizedBox(
      width: 32, height: 32,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: d.x == 0 ? SystemMouseCursors.resizeUpDown
            : d.y == 0 ? SystemMouseCursors.resizeLeftRight
            : d.x == d.y ? SystemMouseCursors.resizeUpLeftDownRight
            : SystemMouseCursors.resizeUpRightDownLeft,
        child: Listener(
          onPointerSignal: (event) =>
              EditorZoomScope.controllerOf(context)?.handlePointerSignal(event),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: widget.onStart, onPanUpdate: widget.onUpdate,
            onPanEnd: (_) => widget.onEnd(), onPanCancel: widget.onEnd,
            child: Tooltip(
              message: d.x == 0 ? 'Modifier la hauteur de ${widget.label}'
                  : d.y == 0 ? 'Modifier la largeur de ${widget.label}'
                  : 'Redimensionner ${widget.label}',
              child: Center(
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: _hover ? colors.tertiary : colors.surface,
                    border: Border.all(color: colors.tertiary, width: 2),
                    shape: BoxShape.circle,
                  ),
                  child: Transform.rotate(
                    angle: d.x != 0 && d.y != 0
                        ? (d.x == d.y ? math.pi / 4 : -math.pi / 4) : 0,
                    child: Icon(d.x == 0 ? Icons.height : Icons.swap_horiz,
                      size: 16, color: _hover ? colors.onTertiary : colors.tertiary),
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
