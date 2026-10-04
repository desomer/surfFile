import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

class MouseBackNavigation extends StatelessWidget {
  const MouseBackNavigation({
    required this.enabled,
    required this.onBack,
    required this.child,
    this.forwardEnabled = false,
    this.onForward,
    super.key,
  });

  final bool enabled;
  final VoidCallback onBack;
  final Widget child;
  final bool forwardEnabled;
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if (event.kind != PointerDeviceKind.mouse ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (enabled && event.buttons == kBackMouseButton) {
        onBack();
      } else if (forwardEnabled && event.buttons == kForwardMouseButton) {
        onForward?.call();
      }
    },
    child: child,
  );
}
