/// Portée Sliver ([SliverSlotScope]) et région de détection pointeur/peinture pour les enfants Sliver ([SliverPointerRegion]).
part of 'editor_selection_region.dart';

/// Indique aux composants compatibles Sliver (`SuperAppBar`, `SuperListView`,
/// `EditorSlot`, `EditorSelectionRegion`, `NativeComponentEditor`) qu'ils sont
/// construits directement comme enfant sliver d'un `CustomScrollView`.
class SliverSlotScope extends InheritedWidget {
  const SliverSlotScope({
    this.enabled = true,
    this.scrollDirection = Axis.vertical,
    this.preferredSize,
    required super.child,
    super.key,
  });

  final bool enabled;
  final Axis scrollDirection;
  final Size? preferredSize;

  static bool isSliver(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SliverSlotScope>();
    if (scope == null || !scope.enabled) return false;
    var result = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is SliverSlotScope) {
        result = widget.enabled;
        return false;
      }
      if (widget is SliverPointerRegion ||
          widget is SliverLayoutBuilder ||
          widget is SliverMainAxisGroup ||
          widget is SliverCrossAxisGroup ||
          widget is SliverPadding ||
          widget is SliverSafeArea ||
          widget is SliverOffstage ||
          widget is SliverOpacity) {
        return true;
      }
      if (widget is RenderObjectWidget) {
        result = false;
        return false;
      }
      return true;
    });
    return result;
  }

  static Axis scrollDirectionOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SliverSlotScope>()
          ?.scrollDirection ??
      Axis.vertical;

  static Size? preferredSizeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SliverSlotScope>()
      ?.preferredSize;

  @override
  bool updateShouldNotify(SliverSlotScope oldWidget) =>
      oldWidget.enabled != enabled ||
      oldWidget.scrollDirection != scrollDirection ||
      oldWidget.preferredSize != preferredSize;
}

/// Équivalent Sliver de `MouseRegion` + `Listener` + `CustomPaint(foregroundPainter)`.
class SliverPointerRegion extends SingleChildRenderObjectWidget {
  const SliverPointerRegion({
    this.onEnter,
    this.onHover,
    this.onExit,
    this.cursor = MouseCursor.defer,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this.foregroundPainter,
    required super.child,
    super.key,
  });

  final PointerEnterEventListener? onEnter;
  final PointerHoverEventListener? onHover;
  final PointerExitEventListener? onExit;
  final MouseCursor cursor;
  final PointerDownEventListener? onPointerDown;
  final PointerMoveEventListener? onPointerMove;
  final PointerUpEventListener? onPointerUp;
  final PointerCancelEventListener? onPointerCancel;
  final CustomPainter? foregroundPainter;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSliverPointerRegion(
        onEnter: onEnter,
        onHover: onHover,
        onExit: onExit,
        cursor: cursor,
        onPointerDown: onPointerDown,
        onPointerMove: onPointerMove,
        onPointerUp: onPointerUp,
        onPointerCancel: onPointerCancel,
        foregroundPainter: foregroundPainter,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderSliverPointerRegion)
      ..onEnter = onEnter
      ..onHover = onHover
      ..onExit = onExit
      ..cursor = cursor
      ..onPointerDown = onPointerDown
      ..onPointerMove = onPointerMove
      ..onPointerUp = onPointerUp
      ..onPointerCancel = onPointerCancel
      ..foregroundPainter = foregroundPainter;
  }
}

class _RenderSliverPointerRegion extends RenderProxySliver
    implements MouseTrackerAnnotation {
  _RenderSliverPointerRegion({
    this._onEnter,
    this.onHover,
    this._onExit,
    this._cursor = MouseCursor.defer,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this._foregroundPainter,
  });

  PointerEnterEventListener? _onEnter;
  @override
  PointerEnterEventListener? get onEnter => _onEnter;
  set onEnter(PointerEnterEventListener? value) {
    if (_onEnter == value) return;
    _onEnter = value;
  }

  PointerHoverEventListener? onHover;

  PointerExitEventListener? _onExit;
  @override
  PointerExitEventListener? get onExit => _onExit;
  set onExit(PointerExitEventListener? value) {
    if (_onExit == value) return;
    _onExit = value;
  }

  MouseCursor _cursor;
  @override
  MouseCursor get cursor => _cursor;
  set cursor(MouseCursor value) {
    if (_cursor == value) return;
    _cursor = value;
    markNeedsPaint();
  }

  PointerDownEventListener? onPointerDown;
  PointerMoveEventListener? onPointerMove;
  PointerUpEventListener? onPointerUp;
  PointerCancelEventListener? onPointerCancel;

  CustomPainter? _foregroundPainter;
  CustomPainter? get foregroundPainter => _foregroundPainter;
  set foregroundPainter(CustomPainter? value) {
    if (_foregroundPainter == value) return;
    final oldPainter = _foregroundPainter;
    _foregroundPainter = value;
    if (attached) {
      oldPainter?.removeListener(markNeedsPaint);
      value?.addListener(markNeedsPaint);
    }
    if (value == null ||
        oldPainter == null ||
        value.runtimeType != oldPainter.runtimeType ||
        value.shouldRepaint(oldPainter)) {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _foregroundPainter?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _foregroundPainter?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get validForMouseTracker => attached;

  @override
  bool hitTest(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    final geom = geometry;
    if (geom == null ||
        mainAxisPosition < 0.0 ||
        mainAxisPosition >= geom.hitTestExtent ||
        crossAxisPosition < 0.0 ||
        crossAxisPosition >= constraints.crossAxisExtent) {
      return false;
    }
    final hitChild = hitTestChildren(
      result,
      mainAxisPosition: mainAxisPosition,
      crossAxisPosition: crossAxisPosition,
    );
    if (hitChild) {
      result.add(
        SliverHitTestEntry(
          this,
          mainAxisPosition: mainAxisPosition,
          crossAxisPosition: crossAxisPosition,
        ),
      );
      return true;
    }
    return false;
  }

  @override
  void handleEvent(PointerEvent event, SliverHitTestEntry entry) {
    if (event is PointerHoverEvent) return onHover?.call(event);
    if (event is PointerDownEvent) return onPointerDown?.call(event);
    if (event is PointerMoveEvent) return onPointerMove?.call(event);
    if (event is PointerUpEvent) return onPointerUp?.call(event);
    if (event is PointerCancelEvent) return onPointerCancel?.call(event);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final painter = _foregroundPainter;
    final geom = geometry;
    if (painter != null &&
        geom != null &&
        geom.visible &&
        geom.paintExtent > 0) {
      final size = constraints.axis == Axis.vertical
          ? Size(constraints.crossAxisExtent, geom.paintExtent)
          : Size(geom.paintExtent, constraints.crossAxisExtent);
      context.canvas.save();
      context.canvas.translate(offset.dx, offset.dy);
      painter.paint(context.canvas, size);
      context.canvas.restore();
    }
  }
}
