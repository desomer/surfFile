import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

class PressFeedback extends StatefulWidget {
  const PressFeedback({
    required this.onMouseDown,
    this.onPress,
    required this.child,
    super.key,
  });

  final VoidCallback onMouseDown;

  /// Appui principal, quel que soit le type de pointeur.
  final ValueChanged<PointerDownEvent>? onPress;
  final Widget child;

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  int? _pointer;

  void _release(PointerEvent event) {
    if (event.pointer == _pointer) _pointer = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (event.buttons != kPrimaryMouseButton || _pointer != null) return;
      _pointer = event.pointer;
      widget.onPress?.call(event);
      if (event.kind == PointerDeviceKind.mouse) widget.onMouseDown();
    },
    onPointerUp: _release,
    onPointerCancel: _release,
    child: widget.child,
  );
}
