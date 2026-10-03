import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

class PressFeedback extends StatefulWidget {
  const PressFeedback({
    required this.onMouseDown,
    required this.child,
    super.key,
  });

  final VoidCallback onMouseDown;
  final Widget child;

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  int? _pointer;

  void _release(PointerEvent event) {
    // Flutter can deliver the end of a captured gesture after removal.
    if (mounted && event.pointer == _pointer) {
      setState(() => _pointer = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (event) {
        if (!mounted ||
            event.buttons != kPrimaryMouseButton ||
            _pointer != null) {
          return;
        }
        setState(() => _pointer = event.pointer);
        if (event.kind == PointerDeviceKind.mouse) widget.onMouseDown();
      },
      onPointerUp: _release,
      onPointerCancel: _release,
      child: AnimatedScale(
        scale: _pointer != null && !reducedMotion ? .995 : 1,
        duration: reducedMotion
            ? Duration.zero
            : Duration(milliseconds: _pointer != null ? 80 : 160),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
