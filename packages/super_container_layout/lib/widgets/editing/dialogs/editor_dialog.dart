import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:material_ui/material_ui.dart';

import '../../components/super_layout/layout_selection.dart';
import '../addition/insertion_plan.dart';
import '../overlay/editor_zoom.dart';
import '../overlay/editor_overlay.dart';

/// Opens an editor beside its target when the page supports selection zoom.
Future<T?> showEditorDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  BuildContext? target,
  ValueListenable<double>? preferredWidth,
  bool barrierDismissible = true,
  Color? barrierColor,
}) async {
  final nested =
      EditorOverlayVisibility.openDialogs.value > 0 ||
      ModalRoute.of(context) is PopupRoute;
  EditorOverlayVisibility.openDialogs.value++;
  try {
    return await _showEditorDialog<T>(
      context: context,
      builder: nested
          ? (context) {
              final theme = Theme.of(context);
              final shape = theme.dialogTheme.shape;
              final border = BorderSide(
                color: theme.colorScheme.outline,
                width: 1.5,
              );
              return Theme(
                data: theme.copyWith(
                  dialogTheme: theme.dialogTheme.copyWith(
                    elevation: 24,
                    shadowColor: Colors.black.withValues(alpha: .5),
                    shape: switch (shape) {
                      OutlinedBorder shape => shape.copyWith(side: border),
                      null => RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: border,
                      ),
                      _ => shape,
                    },
                  ),
                ),
                child: Builder(builder: builder),
              );
            }
          : builder,
      target: target,
      preferredWidth: preferredWidth,
      barrierDismissible: barrierDismissible,
      barrierColor:
          barrierColor ?? (nested ? Colors.black.withValues(alpha: .24) : null),
    );
  } finally {
    EditorOverlayVisibility.openDialogs.value--;
  }
}

Future<T?> _showEditorDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  BuildContext? target,
  ValueListenable<double>? preferredWidth,
  bool barrierDismissible = true,
  Color? barrierColor,
}) async {
  final inherited = EditorZoomScope.controllerOf(context);
  final requestedFocus =
      target ??
      inherited?.dialog.value?.target ??
      LayoutSelection.focus.value?.context ??
      context;
  final controller =
      inherited ??
      (requestedFocus.mounted
          ? EditorZoomScope.controllerOf(requestedFocus)
          : null);
  if (controller == null || !controller.enabled) {
    return await showDialog<T>(
      context: context,
      builder: (context) => Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: EditorInsertionPreviewOverlay()),
          Builder(builder: builder),
        ],
      ),
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
    );
  }
  final previous = controller.dialog.value;
  // A nested editor may pass its dialog context, which is outside the canvas.
  // Keep framing the edited component rather than resetting the whole page.
  final focus =
      [
            target,
            previous?.target,
            context,
            LayoutSelection.focus.value?.context,
            controller.contentContext,
          ]
          .whereType<BuildContext>()
          .where((candidate) => controller.targetBounds(candidate) != null)
          .firstOrNull;
  final request = EditorDialogFocus(target: focus);
  try {
    return await showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? Colors.transparent,
      builder: (context) => EditorZoomScope(
        scale: 1,
        offset: Offset.zero,
        controller: controller,
        child: _EditorDialog(
          builder: builder,
          controller: controller,
          request: request,
          preferredWidth: preferredWidth,
        ),
      ),
    );
  } finally {
    if (!controller.disposed && identical(controller.dialog.value, request)) {
      controller.dialog.value = previous;
      LayoutSelection.editorViewport.value = previous?.available;
    }
  }
}

class _EditorDialog extends StatefulWidget {
  const _EditorDialog({
    required this.builder,
    required this.controller,
    required this.request,
    this.preferredWidth,
  });

  final WidgetBuilder builder;
  final EditorZoomController controller;
  final EditorDialogFocus request;
  final ValueListenable<double>? preferredWidth;

  @override
  State<_EditorDialog> createState() => _EditorDialogState();
}

class _EditorDialogState extends State<_EditorDialog> {
  final _viewport = GlobalKey();
  bool _left = false;
  Rect? _targetBounds;
  Offset? _toolbarPosition;

  @override
  void initState() {
    super.initState();
    widget.preferredWidth?.addListener(_resize);
    _trackGeometry();
  }

  void _trackGeometry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controller.disposed) return;
      if (ModalRoute.of(context)?.isCurrent == true) {
        final bounds = widget.controller.targetBounds(widget.request.target);
        if (_targetBounds != bounds) {
          _targetBounds = bounds;
          widget.controller.dialog.geometryChanged();
        }
      }
      _trackGeometry();
    });
  }

  void _resize() => setState(() {});

  @override
  void dispose() {
    widget.preferredWidth?.removeListener(_resize);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    key: _viewport,
    builder: (context, constraints) {
      final size = constraints.biggest;
      final bottom = size.width < 900;
      final extent = bottom
          ? size.height * .52
          : math.min(widget.preferredWidth?.value ?? 560, size.width * .55);
      final available = bottom
          ? Rect.fromLTWH(0, 0, size.width, size.height - extent)
          : Rect.fromLTWH(
              _left ? extent : 0,
              0,
              size.width - extent,
              size.height,
            );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            widget.controller.disposed ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        final box = _viewport.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        final screen = Rect.fromPoints(
          box.localToGlobal(available.topLeft),
          box.localToGlobal(available.bottomRight),
        );
        widget.controller.dialog.frame(widget.request, screen);
        LayoutSelection.editorViewport.value = screen;
      });
      return Stack(
        children: [
          Positioned.fromRect(
            rect: available,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if ((event.buttons & kSecondaryMouseButton) != 0) {
                  widget.controller.handlePointerDown(event);
                }
              },
              onPointerMove: (event) {
                if ((event.buttons & kSecondaryMouseButton) != 0) {
                  widget.controller.handlePointerMove(event);
                }
              },
              onPointerUp: (event) => widget.controller.handlePointerUp(event),
              onPointerCancel: (event) =>
                  widget.controller.handlePointerCancel(event),
              onPointerSignal: (event) =>
                  widget.controller.handlePointerSignal(event),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final route = ModalRoute.of(context);
                  if (route != null && route.barrierDismissible) {
                    Navigator.of(context).pop();
                  }
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: available,
            child: IgnorePointer(
              child: ClipRect(
                child: EditorInsertionPreviewOverlay(
                  controller: widget.controller,
                ),
              ),
            ),
          ),
          Positioned(
            key: const ValueKey('editor-dialog-panel'),
            left: bottom || _left ? 0 : null,
            right: bottom || !_left ? 0 : null,
            top: bottom ? null : 0,
            bottom: 0,
            width: bottom ? null : extent,
            height: bottom ? extent : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!bottom)
                  Align(
                    alignment: _left
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: IconButton.filledTonal(
                      key: const ValueKey('editor-dialog-side'),
                      tooltip: _left ? 'Placer à droite' : 'Placer à gauche',
                      icon: Icon(
                        _left
                            ? Icons.keyboard_arrow_right
                            : Icons.keyboard_arrow_left,
                      ),
                      onPressed: () => setState(() => _left = !_left),
                    ),
                  ),
                Expanded(child: Builder(builder: widget.builder)),
              ],
            ),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: ZoomToolbarLayout(
                _toolbarPosition,
                available: available,
              ),
              child: Material(
                key: const ValueKey('editor-zoom-toolbar'),
                type: MaterialType.card,
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: ValueListenableBuilder<double>(
                  valueListenable: widget.controller.scale,
                  builder: (context, currentScale, _) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: EditorZoomToolbarContent(
                      scale: currentScale,
                      onScaleChanged: widget.controller.setScale,
                      onDrag: (details) => setState(() {
                        final bounds = available;
                        final currentPos = _toolbarPosition ??
                            Offset(
                              bounds.right - 220 - 16,
                              bounds.bottom - 36 - 12,
                            );
                        _toolbarPosition = currentPos + details.delta;
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Renders the hovered placement preview on top of the canvas.
class EditorInsertionPreviewOverlay extends StatefulWidget {
  const EditorInsertionPreviewOverlay({
    this.controller,
    super.key,
  });

  final EditorZoomController? controller;

  @override
  State<EditorInsertionPreviewOverlay> createState() =>
      _EditorInsertionPreviewOverlayState();
}

class _EditorInsertionPreviewOverlayState
    extends State<EditorInsertionPreviewOverlay> {
  final _boxKey = GlobalKey();
  InsertionPreviewBounds? _lastBounds;
  bool _postFrameScheduled = false;

  void _scheduleCheck(ComponentAddPlacementPreview? preview) {
    if (_postFrameScheduled || preview == null) return;
    _postFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameScheduled = false;
      if (!mounted) return;
      final current = EditorInsertionPreview.active.value;
      if (current == null) return;
      final box = _boxKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        final next = current.resolve(box);
        if (next != _lastBounds) {
          setState(() => _lastBounds = next);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      EditorInsertionPreview.active,
      widget.controller?.transform,
      widget.controller?.dialog,
    ]),
    builder: (context, _) {
      final preview = EditorInsertionPreview.active.value;
      if (preview == null) {
        _lastBounds = null;
        return SizedBox.expand(key: _boxKey);
      }
      InsertionPreviewBounds? bounds;
      final box = _boxKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        bounds = preview.resolve(box);
        _lastBounds = bounds;
      } else {
        bounds = _lastBounds;
      }
      _scheduleCheck(preview);
      if (bounds == null) {
        return SizedBox.expand(key: _boxKey);
      }
      final colors = Theme.of(context).colorScheme;
      final refRect = bounds.referenceRect;
      final insertRect = bounds.insertRect;
      return SizedBox.expand(
        key: _boxKey,
        child: Stack(
          key: const ValueKey('editor-insertion-preview-overlay'),
          fit: StackFit.expand,
          children: [
            if (refRect != null && refRect != insertRect)
              Positioned.fromRect(
                key: const ValueKey('editor-insertion-preview-reference'),
                rect: refRect,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: .55),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            Positioned.fromRect(
              key: const ValueKey('editor-insertion-preview-rect'),
              rect: insertRect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.primary,
                    width: 2.5,
                  ),
                ),
                child: insertRect.width >= 24 &&
                        insertRect.height >= 20 &&
                        (preview.icon != null ||
                            (preview.label != null &&
                                preview.label!.isNotEmpty))
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (preview.icon case final icon?)
                                    Icon(
                                      icon,
                                      size: 14,
                                      color: colors.onPrimary,
                                    ),
                                  if (preview.icon != null &&
                                      preview.label != null &&
                                      preview.label!.isNotEmpty)
                                    const SizedBox(width: 4),
                                  if (preview.label case final label?
                                      when label.isNotEmpty)
                                    Text(
                                      label,
                                      key: const ValueKey(
                                        'editor-insertion-preview-label',
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colors.onPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      );
    },
  );
}

