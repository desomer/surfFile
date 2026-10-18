import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../super_layout/layout_selection.dart';
import 'editor_zoom.dart';
import 'editor_overlay.dart';

/// Opens an editor beside its target when the page supports selection zoom.
Future<T?> showEditorDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  BuildContext? target,
  ValueListenable<double>? preferredWidth,
  bool barrierDismissible = true,
  Color? barrierColor,
}) async {
  EditorOverlayVisibility.openDialogs.value++;
  try {
    return await _showEditorDialog<T>(
      context: context,
      builder: builder,
      target: target,
      preferredWidth: preferredWidth,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
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
  final focus =
      target ??
      inherited?.dialog.value?.target ??
      LayoutSelection.focus.value?.context;
  final controller =
      inherited ??
      (focus != null && focus.mounted
          ? EditorZoomScope.controllerOf(focus)
          : null);
  if (controller == null || !controller.enabled) {
    return await showDialog<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
    );
  }
  final previous = controller.dialog.value;
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
        ],
      );
    },
  );
}
