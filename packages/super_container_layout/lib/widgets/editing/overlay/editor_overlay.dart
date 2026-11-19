/// Superposition visuelle du mode édition pour un [SuperLayout].
library;

import 'package:flutter/rendering.dart'
    show RenderOffstage, RenderSliverOffstage;
import 'package:material_ui/material_ui.dart';

import 'editor_zoom.dart';
import '../slots/editor_slot.dart';

/// Indique si [renderObject] se trouve dans un sous-arbre masqué par un
/// [RenderOffstage] ou un [RenderSliverOffstage] actif avant d'atteindre [stopAt].
bool isRenderObjectOffstage(
  RenderObject? renderObject, {
  RenderObject? stopAt,
}) {
  if (renderObject == null || !renderObject.attached) return true;
  for (
    RenderObject? node = renderObject;
    node != null && !identical(node, stopAt);
    node = node.parent
  ) {
    if ((node is RenderOffstage && node.offstage) ||
        (node is RenderSliverOffstage && node.offstage)) {
      return true;
    }
  }
  return false;
}

/// Indique si [sourceContext] se trouve dans un sous-arbre masqué par un
/// [Offstage] ou un [SliverOffstage] actif avant d'atteindre [stopAt].
bool isEditorOverlaySourceOffstage(
  BuildContext sourceContext, {
  RenderObject? stopAt,
}) =>
    !sourceContext.mounted ||
    isRenderObjectOffstage(sourceContext.findRenderObject(), stopAt: stopAt);

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
    return ExcludeSemantics(
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _controller,
        overlayChildBuilder: (context, info) {
          if (info.childPaintTransform.isZero() || !info.childSize.isFinite) {
            return const SizedBox.shrink();
          }
          final overlay = Overlay.of(this.context).context.findRenderObject();
          if (isEditorOverlaySourceOffstage(this.context, stopAt: overlay)) {
            return const SizedBox.shrink();
          }
          final rect = MatrixUtils.transformRect(
            info.childPaintTransform,
            Offset.zero & info.childSize,
          );
          if (!rect.isFinite) return const SizedBox.shrink();
          final zoomController = EditorZoomScope.controllerOf(this.context);
          final controlsBody = ExcludeSemantics(
            child: Listener(
              onPointerDown: (event) =>
                  zoomController?.handlePointerDown(event),
              onPointerMove: (event) =>
                  zoomController?.handlePointerMove(event),
              onPointerUp: (event) => zoomController?.handlePointerUp(event),
              onPointerCancel: (event) =>
                  zoomController?.handlePointerCancel(event),
              onPointerSignal: (event) =>
                  zoomController?.handlePointerSignal(event),
              child: GestureDetector(
                excludeFromSemantics: true,
                onSecondaryTapUp:
                    (StyleEditScope.controllerOf(this.context)?.value ?? false)
                    ? (details) => this.context
                          .findAncestorStateOfType<EditorSlotState>()
                          ?.openMenu(
                            details.globalPosition,
                            actions: EditorSlotAction.of(this.context),
                            targetContext: this.context,
                          )
                    : null,
                child: EditorOverlayVisibility(child: widget.child),
              ),
            ),
          );
          final controls = zoomController == null
              ? controlsBody
              : ValueListenableBuilder<bool>(
                  valueListenable: zoomController.lassoIntercepting,
                  child: controlsBody,
                  builder: (context, intercepting, child) =>
                      IgnorePointer(ignoring: intercepting, child: child),
                );
          final viewport = widget.clipKey?.currentContext?.findRenderObject();
          if (viewport is RenderBox &&
              viewport.hasSize &&
              overlay is RenderBox) {
            final viewportTransform = viewport.getTransformTo(overlay);
            if (viewportTransform.isZero()) return const SizedBox.shrink();
            final clip = MatrixUtils.transformRect(
              viewportTransform,
              Offset.zero & viewport.size,
            );
            if (!clip.isFinite) return const SizedBox.shrink();
            final visible = rect.intersect(clip);
            if (visible.isEmpty || !visible.isFinite) {
              return const SizedBox.shrink();
            }
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
      ),
    );
  }
}
