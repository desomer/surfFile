import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../super_layout/layout_selection.dart';
import '../surfaces/super_container.dart';

/// Animates the page around the selected layout, zone or slot.
class EditorZoom extends StatefulWidget {
  const EditorZoom({required this.child, super.key});

  final Widget child;

  @override
  State<EditorZoom> createState() => _EditorZoomState();
}

class _EditorZoomState extends State<EditorZoom>
    with SingleTickerProviderStateMixin {
  final _content = GlobalKey();
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addListener(_animate);
  ValueNotifier<bool>? _editMode;
  Size _viewport = Size.zero;
  ({double scale, Offset offset}) _from = (scale: 1, offset: Offset.zero);
  ({double scale, Offset offset}) _to = (scale: 1, offset: Offset.zero);
  ({double scale, Offset offset}) _current = (scale: 1, offset: Offset.zero);
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    LayoutSelection.focus.addListener(_schedule);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = StyleEditScope.controllerOf(context);
    if (!identical(mode, _editMode)) {
      _editMode?.removeListener(_schedule);
      _editMode = mode;
      mode?.addListener(_schedule);
    }
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _frameSelection();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _frameSelection() {
    var destination = (scale: 1.0, offset: Offset.zero);
    final focus = LayoutSelection.focus.value?.context;
    final contentContext = _content.currentContext;
    if ((_editMode?.value ?? false) &&
        focus != null &&
        focus.mounted &&
        contentContext != null) {
      var belongsToPage = identical(focus, contentContext);
      focus.visitAncestorElements((element) {
        if (identical(element, contentContext)) belongsToPage = true;
        return !belongsToPage;
      });
      final target = focus.findRenderObject();
      final content = contentContext.findRenderObject();
      if (belongsToPage &&
          target is RenderBox &&
          content is RenderBox &&
          target.attached &&
          target.hasSize &&
          content.hasSize) {
        final rect = MatrixUtils.transformRect(
          target.getTransformTo(content),
          Offset.zero & target.size,
        );
        if (!rect.isEmpty && rect.isFinite && !_viewport.isEmpty) {
          final scale = math.min(
            _viewport.width * .7 / rect.width,
            _viewport.height * .7 / rect.height,
          ).clamp(1.0, 3.0);
          destination = (
            scale: scale,
            offset: _viewport.center(Offset.zero) - rect.center * scale,
          );
        }
      }
    }
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (destination == _to &&
        !(disableAnimations && _animation.isAnimating)) return;
    _from = _current;
    _to = destination;
    if (disableAnimations) {
      _animation.stop();
      setState(() => _current = _to);
    } else {
      _animation.forward(from: 0);
    }
  }

  void _animate() {
    final progress = Curves.easeInOutCubic.transform(_animation.value);
    setState(() {
      _current = (
        scale: _from.scale + (_to.scale - _from.scale) * progress,
        offset: Offset.lerp(_from.offset, _to.offset, progress)!,
      );
    });
  }

  @override
  void dispose() {
    LayoutSelection.focus.removeListener(_schedule);
    _editMode?.removeListener(_schedule);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EditorZoomScope(
    scale: _current.scale,
    offset: _current.offset,
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (_viewport != constraints.biggest) {
          _viewport = constraints.biggest;
          _schedule();
        }
        return ClipRect(
          child: Transform(
            key: const ValueKey('editor-zoom-transform'),
            alignment: Alignment.topLeft,
            transform: Matrix4.identity()
              ..translateByDouble(_current.offset.dx, _current.offset.dy, 0, 1)
              ..scaleByDouble(_current.scale, _current.scale, 1, 1),
            child: SizedBox.expand(key: _content, child: widget.child),
          ),
        );
      },
    ),
  );
}

class EditorZoomScope extends InheritedWidget {
  const EditorZoomScope({
    required this.scale,
    required this.offset,
    required super.child,
    super.key,
  });

  final double scale;
  final Offset offset;

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EditorZoomScope>() != null;

  @override
  bool updateShouldNotify(EditorZoomScope oldWidget) =>
      scale != oldWidget.scale || offset != oldWidget.offset;
}
