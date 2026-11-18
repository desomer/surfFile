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

/// Équivalent Box à profondeur constante de `MouseRegion` + `Listener` +
/// `GestureDetector` (clic primaire / secondaire) (`BoxPointerRegion`).
///
/// Lorsque [enabled] vaut `false`, son [RenderObject] agit comme un pur
/// `RenderProxyBox` pass-through sans suivi souris ni interception pointeur.
class BoxPointerRegion extends SingleChildRenderObjectWidget {
  /// Crée une région de pointeur Box à profondeur d'arbre constante.
  const BoxPointerRegion({
    this.enabled = true,
    this.opaque = false,
    this.onEnter,
    this.onHover,
    this.onExit,
    this.cursor = MouseCursor.defer,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this.onTap,
    this.onSecondaryTapUp,
    required super.child,
    super.key,
  });

  /// Active l'interception des événements pointeur et le suivi souris.
  final bool enabled;

  /// Indique si toute la boîte capte les tests de collision même sur ses zones vides.
  final bool opaque;

  /// Callback d'entrée du pointeur souris.
  final PointerEnterEventListener? onEnter;

  /// Callback de déplacement en survol du pointeur souris.
  final PointerHoverEventListener? onHover;

  /// Callback de sortie du pointeur souris.
  final PointerExitEventListener? onExit;

  /// Curseur souris affiché au survol lorsque [enabled] vaut `true`.
  final MouseCursor cursor;

  /// Callback d'appui pointeur bas niveau.
  final PointerDownEventListener? onPointerDown;

  /// Callback de déplacement pointeur bas niveau.
  final PointerMoveEventListener? onPointerMove;

  /// Callback de relâchement pointeur bas niveau.
  final PointerUpEventListener? onPointerUp;

  /// Callback d'annulation pointeur bas niveau.
  final PointerCancelEventListener? onPointerCancel;

  /// Callback d'appui simple primaire participant à la `GestureArena`.
  final GestureTapCallback? onTap;

  /// Callback de clic secondaire participant à la `GestureArena`.
  final GestureTapUpCallback? onSecondaryTapUp;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBoxPointerRegion(
        enabled,
        opaque,
        onEnter,
        onHover,
        onExit,
        cursor,
        onPointerDown,
        onPointerMove,
        onPointerUp,
        onPointerCancel,
        onTap,
        onSecondaryTapUp,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderBoxPointerRegion)
      ..enabled = enabled
      ..opaque = opaque
      ..onEnter = onEnter
      ..onHover = onHover
      ..onExit = onExit
      ..cursor = cursor
      ..onPointerDown = onPointerDown
      ..onPointerMove = onPointerMove
      ..onPointerUp = onPointerUp
      ..onPointerCancel = onPointerCancel
      ..onTap = onTap
      ..onSecondaryTapUp = onSecondaryTapUp;
  }
}

class _RenderBoxPointerRegion extends RenderProxyBox
    implements MouseTrackerAnnotation {
  _RenderBoxPointerRegion(
    this._enabled,
    this._opaque,
    this._onEnter,
    this._onHover,
    this._onExit,
    this._cursor,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this._onTap,
    this._onSecondaryTapUp,
  );

  bool _enabled;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _syncTapRecognizer();
    markNeedsPaint();
  }

  bool _opaque;
  bool get opaque => _opaque;
  set opaque(bool value) {
    if (_opaque == value) return;
    _opaque = value;
  }

  bool get _needsMouseTracking =>
      _enabled &&
      (_onEnter != null ||
          _onHover != null ||
          _onExit != null ||
          _cursor != MouseCursor.defer);

  PointerEnterEventListener? _onEnter;
  @override
  PointerEnterEventListener? get onEnter => _enabled ? _onEnter : null;
  set onEnter(PointerEnterEventListener? value) {
    if (_onEnter == value) return;
    final before = _needsMouseTracking;
    _onEnter = value;
    if (_needsMouseTracking != before) markNeedsPaint();
  }

  PointerHoverEventListener? _onHover;
  PointerHoverEventListener? get onHover => _enabled ? _onHover : null;
  set onHover(PointerHoverEventListener? value) {
    if (_onHover == value) return;
    final before = _needsMouseTracking;
    _onHover = value;
    if (_needsMouseTracking != before) markNeedsPaint();
  }

  PointerExitEventListener? _onExit;
  @override
  PointerExitEventListener? get onExit => _enabled ? _onExit : null;
  set onExit(PointerExitEventListener? value) {
    if (_onExit == value) return;
    final before = _needsMouseTracking;
    _onExit = value;
    if (_needsMouseTracking != before) markNeedsPaint();
  }

  MouseCursor _cursor;
  @override
  MouseCursor get cursor => _enabled ? _cursor : MouseCursor.defer;
  set cursor(MouseCursor value) {
    if (_cursor == value) return;
    _cursor = value;
    if (_enabled) markNeedsPaint();
  }

  PointerDownEventListener? onPointerDown;
  PointerMoveEventListener? onPointerMove;
  PointerUpEventListener? onPointerUp;
  PointerCancelEventListener? onPointerCancel;

  GestureTapCallback? _onTap;
  GestureTapCallback? get onTap => _onTap;
  set onTap(GestureTapCallback? value) {
    if (_onTap == value) return;
    _onTap = value;
    _syncTapRecognizer();
  }

  GestureTapUpCallback? _onSecondaryTapUp;
  GestureTapUpCallback? get onSecondaryTapUp => _onSecondaryTapUp;
  set onSecondaryTapUp(GestureTapUpCallback? value) {
    if (_onSecondaryTapUp == value) return;
    _onSecondaryTapUp = value;
    _syncTapRecognizer();
  }

  TapGestureRecognizer? _tapRecognizer;

  void _syncTapRecognizer() {
    final active = _enabled && (_onTap != null || _onSecondaryTapUp != null);
    if (!active) {
      _tapRecognizer?.dispose();
      _tapRecognizer = null;
      return;
    }
    final recognizer = _tapRecognizer;
    if (recognizer != null) {
      recognizer
        ..onTap = _onTap
        ..onSecondaryTapUp = _onSecondaryTapUp;
    }
  }

  @override
  void detach() {
    _tapRecognizer?.dispose();
    _tapRecognizer = null;
    super.detach();
  }

  @override
  bool get validForMouseTracker => attached && _needsMouseTracking;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (!_enabled) {
      return hitTestChildren(result, position: position);
    }
    final hitTarget = hitTestChildren(result, position: position) || _opaque;
    result.add(BoxHitTestEntry(this, position));
    return hitTarget;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (!_enabled) return;
    if (event is PointerHoverEvent) {
      _onHover?.call(event);
      return;
    }
    if (event is PointerDownEvent) {
      onPointerDown?.call(event);
      if (_onTap != null || _onSecondaryTapUp != null) {
        final recognizer = _tapRecognizer ??= TapGestureRecognizer(
          debugOwner: this,
        );
        recognizer
          ..onTap = _onTap
          ..onSecondaryTapUp = _onSecondaryTapUp
          ..addPointer(event);
      }
      return;
    }
    if (event is PointerMoveEvent) {
      onPointerMove?.call(event);
      return;
    }
    if (event is PointerUpEvent) {
      onPointerUp?.call(event);
      return;
    }
    if (event is PointerCancelEvent) {
      onPointerCancel?.call(event);
      return;
    }
  }
}

/// Équivalent Sliver de `MouseRegion` + `Listener` + `CustomPaint(foregroundPainter)`.
class SliverPointerRegion extends SingleChildRenderObjectWidget {
  const SliverPointerRegion({
    this.enabled = true,
    this.onEnter,
    this.onHover,
    this.onExit,
    this.cursor = MouseCursor.defer,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this.foregroundPainter,
    this.painterListenable,
    required super.child,
    super.key,
  });

  final bool enabled;
  final PointerEnterEventListener? onEnter;
  final PointerHoverEventListener? onHover;
  final PointerExitEventListener? onExit;
  final MouseCursor cursor;
  final PointerDownEventListener? onPointerDown;
  final PointerMoveEventListener? onPointerMove;
  final PointerUpEventListener? onPointerUp;
  final PointerCancelEventListener? onPointerCancel;
  final CustomPainter? foregroundPainter;
  final ValueListenable<CustomPainter?>? painterListenable;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSliverPointerRegion(
        enabled,
        onEnter,
        onHover,
        onExit,
        cursor,
        onPointerDown,
        onPointerMove,
        onPointerUp,
        onPointerCancel,
        foregroundPainter,
        painterListenable,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderSliverPointerRegion)
      ..enabled = enabled
      ..onEnter = onEnter
      ..onHover = onHover
      ..onExit = onExit
      ..cursor = cursor
      ..onPointerDown = onPointerDown
      ..onPointerMove = onPointerMove
      ..onPointerUp = onPointerUp
      ..onPointerCancel = onPointerCancel
      ..foregroundPainter = foregroundPainter
      ..painterListenable = painterListenable;
  }
}

class _RenderSliverPointerRegion extends RenderProxySliver
    implements MouseTrackerAnnotation {
  _RenderSliverPointerRegion(
    this._enabled,
    this._onEnter,
    this._onHover,
    this._onExit,
    this._cursor,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this._foregroundPainter,
    this._painterListenable,
  );

  bool _enabled;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    markNeedsPaint();
  }

  bool get _needsMouseTracking =>
      _enabled &&
      (_onEnter != null ||
          _onHover != null ||
          _onExit != null ||
          _cursor != MouseCursor.defer);

  PointerEnterEventListener? _onEnter;
  @override
  PointerEnterEventListener? get onEnter => _enabled ? _onEnter : null;
  set onEnter(PointerEnterEventListener? value) {
    if (_onEnter == value) return;
    final before = _needsMouseTracking;
    _onEnter = value;
    if (_needsMouseTracking != before) markNeedsPaint();
  }

  PointerHoverEventListener? _onHover;
  PointerHoverEventListener? get onHover => _enabled ? _onHover : null;
  set onHover(PointerHoverEventListener? value) {
    if (_onHover == value) return;
    final before = _needsMouseTracking;
    _onHover = value;
    if (_needsMouseTracking != before) markNeedsPaint();
  }

  PointerExitEventListener? _onExit;
  @override
  PointerExitEventListener? get onExit => _enabled ? _onExit : null;
  set onExit(PointerExitEventListener? value) {
    if (_onExit == value) return;
    final before = _needsMouseTracking;
    _onExit = value;
    if (_needsMouseTracking != before) markNeedsPaint();
  }

  MouseCursor _cursor;
  @override
  MouseCursor get cursor => _enabled ? _cursor : MouseCursor.defer;
  set cursor(MouseCursor value) {
    if (_cursor == value) return;
    _cursor = value;
    if (_enabled) markNeedsPaint();
  }

  PointerDownEventListener? onPointerDown;
  PointerMoveEventListener? onPointerMove;
  PointerUpEventListener? onPointerUp;
  PointerCancelEventListener? onPointerCancel;

  CustomPainter? _foregroundPainter;
  CustomPainter? get foregroundPainter => _foregroundPainter;
  set foregroundPainter(CustomPainter? value) {
    if (identical(_foregroundPainter, value)) return;
    _foregroundPainter = value;
    _syncActivePainter();
  }

  ValueListenable<CustomPainter?>? _painterListenable;
  ValueListenable<CustomPainter?>? get painterListenable => _painterListenable;
  set painterListenable(ValueListenable<CustomPainter?>? value) {
    if (identical(_painterListenable, value)) return;
    if (attached) {
      _painterListenable?.removeListener(_syncActivePainter);
      value?.addListener(_syncActivePainter);
    }
    _painterListenable = value;
    _syncActivePainter();
  }

  CustomPainter? _subscribedPainter;

  void _syncActivePainter() {
    final next = _painterListenable?.value ?? _foregroundPainter;
    if (identical(next, _subscribedPainter)) return;
    final oldPainter = _subscribedPainter;
    _subscribedPainter = next;
    if (attached) {
      oldPainter?.removeListener(markNeedsPaint);
      next?.addListener(markNeedsPaint);
    }
    if (next == null ||
        oldPainter == null ||
        next.runtimeType != oldPainter.runtimeType ||
        next.shouldRepaint(oldPainter)) {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _painterListenable?.addListener(_syncActivePainter);
    final next = _painterListenable?.value ?? _foregroundPainter;
    _subscribedPainter = next;
    next?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _painterListenable?.removeListener(_syncActivePainter);
    _subscribedPainter?.removeListener(markNeedsPaint);
    _subscribedPainter = null;
    super.detach();
  }

  @override
  bool get validForMouseTracker => attached && _needsMouseTracking;

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
    if (_enabled && hitChild) {
      result.add(
        SliverHitTestEntry(
          this,
          mainAxisPosition: mainAxisPosition,
          crossAxisPosition: crossAxisPosition,
        ),
      );
      return true;
    }
    return hitChild;
  }

  @override
  void handleEvent(PointerEvent event, SliverHitTestEntry entry) {
    if (!_enabled) return;
    if (event is PointerHoverEvent) return _onHover?.call(event);
    if (event is PointerDownEvent) return onPointerDown?.call(event);
    if (event is PointerMoveEvent) return onPointerMove?.call(event);
    if (event is PointerUpEvent) return onPointerUp?.call(event);
    if (event is PointerCancelEvent) return onPointerCancel?.call(event);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final painter = _subscribedPainter;
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
