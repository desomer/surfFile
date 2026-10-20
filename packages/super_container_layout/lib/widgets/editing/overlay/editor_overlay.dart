import 'package:material_ui/material_ui.dart';

import 'editor_zoom.dart';
import '../slots/editor_slot.dart';

/// Hides editing controls without changing content geometry or selection.
class EditorOverlayVisibility extends StatelessWidget {
  const EditorOverlayVisibility({required this.child, super.key});

  static final ValueNotifier<int> openDialogs = ValueNotifier(0);
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: openDialogs,
    builder: (context, count, child) => Visibility(
      visible: count == 0,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: child!,
    ),
    child: child,
  );
}

/// Keeps editor controls at screen scale while following their content bounds.
class EditorOverlay extends StatefulWidget {
  const EditorOverlay({required this.child, this.clipKey, super.key});

  final Widget child;

  /// Clips portaled controls to a scroll viewport, without scaling them.
  final GlobalKey? clipKey;

  @override
  State<EditorOverlay> createState() => _EditorOverlayState();
}

class _EditorOverlayState extends State<EditorOverlay> {
  final _controller = OverlayPortalController();
  bool _enabled = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = EditorZoomScope.contains(context);
    if (_initialized && enabled == _enabled) return;
    _initialized = true;
    _enabled = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_enabled && !_controller.isShowing) {
        _controller.show();
      } else if (!_enabled && _controller.isShowing) {
        _controller.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return EditorOverlayVisibility(child: widget.child);
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _controller,
      overlayChildBuilder: (context, info) {
        final rect = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        final controls = Listener(
          onPointerSignal: (event) =>
              EditorZoomScope.controllerOf(this.context)
                  ?.handlePointerSignal(event),
          child: GestureDetector(
            excludeFromSemantics: true,
            onSecondaryTapUp:
                (StyleEditScope.controllerOf(this.context)?.value ?? false)
                ? (details) => this.context
                      .findAncestorStateOfType<EditorSlotState>()
                      ?.openMenu(
                        details.globalPosition,
                        actions: EditorSlotAction.of(this.context),
                      )
                : null,
            child: EditorOverlayVisibility(child: widget.child),
          ),
        );
        final viewport = widget.clipKey?.currentContext?.findRenderObject();
        final overlay = Overlay.of(this.context).context.findRenderObject();
        if (viewport is RenderBox && viewport.hasSize && overlay is RenderBox) {
          final clip = MatrixUtils.transformRect(
            viewport.getTransformTo(overlay),
            Offset.zero & viewport.size,
          );
          final visible = rect.intersect(clip);
          if (visible.isEmpty) return const SizedBox.shrink();
          return Positioned.fromRect(
            rect: visible,
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    left: rect.left - visible.left,
                    top: rect.top - visible.top,
                    width: rect.width,
                    height: rect.height,
                    child: controls,
                  ),
                ],
              ),
            ),
          );
        }
        return Positioned.fromRect(rect: rect, child: controls);
      },
      child: const SizedBox.expand(),
    );
  }
}
