import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart'
    show
        MouseTrackerAnnotation,
        PointerEnterEventListener,
        PointerExitEventListener,
        PointerHoverEventListener;
import 'package:material_ui/material_ui.dart';

import '../../../theme/appearance.dart';
import '../overlay/editor_overlay.dart';

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
    covariant _RenderSliverPointerRegion renderObject,
  ) {
    renderObject
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

/// A selectable zone or direct child in the editor's visual hierarchy.
class EditorSelectionRegion extends StatefulWidget {
  const EditorSelectionRegion({
    required this.enabled,
    required this.onSelect,
    required this.child,
    this.isZone = false,
    this.fallback = false,
    this.selected = false,
    super.key,
  });

  final bool enabled;
  final bool isZone;

  /// Empty native surfaces remain selectable without enclosing their regions.
  final bool fallback;
  final bool selected;
  final VoidCallback onSelect;
  final Widget child;

  static ValueListenable<Object?> get hoverTarget =>
      _EditorSelectionRegionState._hoverTarget;

  static PointerEvent? _ignored;

  /// Labels retain their explicit selection and drag actions.
  static void ignorePointer(PointerDownEvent event) {
    _ignored = event.original ?? event;
  }

  @override
  State<EditorSelectionRegion> createState() => _EditorSelectionRegionState();
}

class _EditorSelectionRegionState extends State<EditorSelectionRegion> {
  static final _hovered = <_EditorSelectionRegionState>{};
  static final _hoverTarget = ValueNotifier<_EditorSelectionRegionState?>(null);
  static _EditorSelectionRegionState? _selected;
  static _EditorSelectionRegionState? _lastBase;
  static PointerEvent? _claimed;
  static Timer? _doubleTapTimer;
  static Timer? _minimumTapTimer;
  static Offset? _lastPosition;
  static _EditorSelectionRegionState? _lastLeaf;

  PointerDownEvent? _down;
  bool _moved = false;

  List<_EditorSelectionRegionState> get _ancestry {
    final chain = <_EditorSelectionRegionState>[this];
    context.visitAncestorElements((element) {
      if (element is StatefulElement &&
          element.state is _EditorSelectionRegionState) {
        final state = element.state as _EditorSelectionRegionState;
        if (state.widget.enabled && !state.widget.fallback) chain.add(state);
      }
      return true;
    });
    return chain.reversed.toList();
  }

  static _EditorSelectionRegionState? _resolveCurrent(
    List<_EditorSelectionRegionState> chain,
  ) {
    final current = _selected;
    if (current != null &&
        current.mounted &&
        current.widget.enabled &&
        current.widget.selected) {
      return current;
    }
    for (final state in chain.reversed) {
      if (state.mounted && state.widget.enabled && state.widget.selected) {
        return _selected = state;
      }
    }
    if (current != null && current.mounted && current.widget.enabled) {
      return current;
    }
    return null;
  }

  static _EditorSelectionRegionState _skipPassThroughZones(
    List<_EditorSelectionRegionState> chain,
    int index,
  ) {
    var i = index.clamp(0, chain.length - 1);
    while (i + 1 < chain.length &&
        chain[i].widget.isZone &&
        chain[i + 1].widget.isZone) {
      i++;
    }
    return chain[i];
  }

  static _EditorSelectionRegionState _zone(
    List<_EditorSelectionRegionState> chain,
  ) {
    final current = _resolveCurrent(chain);
    final index = current == null ? -1 : chain.indexOf(current);
    if (index >= 0) {
      for (var i = index; i >= 0; i--) {
        if (chain[i].widget.isZone) {
          return _skipPassThroughZones(chain, i);
        }
      }
    }
    if (current != null && current.mounted) {
      final ancestry = current._ancestry;
      var commonIndex = -1;
      for (var i = chain.length - 1; i >= 0; i--) {
        if (ancestry.contains(chain[i])) {
          commonIndex = i;
          break;
        }
      }
      if (commonIndex >= 0) {
        if (commonIndex + 1 < chain.length &&
            chain[commonIndex + 1].widget.isZone) {
          return _skipPassThroughZones(chain, commonIndex + 1);
        }
        for (var i = commonIndex; i >= 0; i--) {
          if (chain[i].widget.isZone) {
            return _skipPassThroughZones(chain, i);
          }
        }
      }
    }
    final firstZone = chain.indexWhere((state) => state.widget.isZone);
    return _skipPassThroughZones(chain, firstZone < 0 ? 0 : firstZone);
  }

  static void _refreshHover() {
    _EditorSelectionRegionState? leaf;
    var depth = -1;
    for (final state in _hovered) {
      if (!state.mounted || !state.widget.enabled) continue;
      final length = state._ancestry.length;
      if (length > depth) {
        leaf = state;
        depth = length;
      }
    }
    if (leaf == null) {
      _hoverTarget.value = null;
      return;
    }
    final chain = leaf._ancestry;
    final current = _resolveCurrent(chain);
    final index = current == null ? -1 : chain.indexOf(current);
    final isPassThrough =
        index >= 0 &&
        chain[index].widget.isZone &&
        index + 1 < chain.length &&
        chain[index + 1].widget.isZone;
    final nextTarget = index < 0 || isPassThrough
        ? _zone(chain)
        : chain[(index + 1).clamp(0, chain.length - 1)];
    final previous = _hoverTarget.value;
    _hoverTarget.value = nextTarget;
    if (!identical(previous, nextTarget)) {
      EditorSelectionOutline.triggerAnimation();
    }
  }

  void _pointerDown(PointerDownEvent event) {
    if (!widget.enabled || event.buttons != kPrimaryButton) return;
    final original = event.original ?? event;
    if (identical(original, _claimed) ||
        identical(original, EditorSelectionRegion._ignored)) {
      return;
    }
    _claimed = original;
    _down = event;
    _moved = false;
  }

  void _pointerUp(PointerUpEvent event) {
    final down = _down;
    _down = null;
    if (down == null ||
        down.pointer != event.pointer ||
        _moved ||
        identical(down.original ?? down, EditorSelectionRegion._ignored) ||
        (event.position - down.position).distance > kTouchSlop ||
        !widget.enabled) {
      return;
    }
    final chain = _ancestry;
    final current = _resolveCurrent(chain);
    final currentIndex = current == null ? -1 : chain.indexOf(current);
    final isPassThrough =
        currentIndex >= 0 &&
        chain[currentIndex].widget.isZone &&
        currentIndex + 1 < chain.length &&
        chain[currentIndex + 1].widget.isZone;
    final doubleClick =
        identical(_lastLeaf, this) &&
        (_doubleTapTimer?.isActive ?? false) &&
        !(_minimumTapTimer?.isActive ?? false) &&
        (event.position - _lastPosition!).distance <= kDoubleTapSlop;
    final _EditorSelectionRegionState target;
    if (doubleClick) {
      final base = _lastBase ?? current;
      final baseIndex = base == null ? -1 : chain.indexOf(base);
      final fromIndex = baseIndex >= 0
          ? baseIndex
          : (currentIndex >= 0 ? currentIndex : chain.indexOf(_zone(chain)));
      target = chain[(fromIndex + 1).clamp(0, chain.length - 1)];
    } else if (currentIndex >= 0 && !isPassThrough) {
      // Clicking inside the already-selected region/slot keeps it selected
      // instead of resetting back to the parent zone on the first click.
      target = current!;
    } else {
      target = _zone(chain);
    }
    _lastBase = target;
    _doubleTapTimer?.cancel();
    _minimumTapTimer?.cancel();
    if (!doubleClick) {
      _doubleTapTimer = Timer(kDoubleTapTimeout, () {});
      _minimumTapTimer = Timer(kDoubleTapMinTime, () {});
    }
    _lastPosition = event.position;
    _lastLeaf = this;
    final changed = !identical(target, current) || !target.widget.selected;
    _selected = target;
    if (changed) {
      target.widget.onSelect();
    }
    _refreshHover();
  }

  @override
  void initState() {
    super.initState();
    if (widget.enabled && widget.selected) _selected = this;
  }

  @override
  void didUpdateWidget(EditorSelectionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _clear();
      scheduleMicrotask(_refreshHover);
    } else if (widget.enabled && widget.selected != oldWidget.selected) {
      if (widget.selected) {
        final current = _selected;
        if (current == null ||
            !current.mounted ||
            !current.widget.enabled ||
            !current.widget.selected ||
            !current._ancestry.contains(this)) {
          _selected = this;
        }
      } else if (identical(_selected, this)) {
        _selected = _ancestry
            .where(
              (s) =>
                  !identical(s, this) &&
                  s.mounted &&
                  s.widget.enabled &&
                  s.widget.selected,
            )
            .lastOrNull;
      }
      scheduleMicrotask(_refreshHover);
    }
  }

  void _clear() {
    _hovered.remove(this);
    if (identical(_selected, this)) _selected = null;
    if (identical(_lastBase, this)) _lastBase = null;
    if (identical(_lastLeaf, this)) {
      _lastLeaf = null;
      _doubleTapTimer?.cancel();
      _minimumTapTimer?.cancel();
    }
    _down = null;
  }

  @override
  void dispose() {
    _clear();
    scheduleMicrotask(_refreshHover);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSliver = SliverSlotScope.isSliver(context);
    if (isSliver) {
      return ListenableBuilder(
        listenable: Listenable.merge([
          _hoverTarget,
          EditorOverlayVisibility.openDialogs,
        ]),
        builder: (context, child) => SliverPointerRegion(
          onEnter: (_) {
            if (widget.enabled) _hovered.add(this);
            _refreshHover();
          },
          onHover: (_) {
            if (!widget.enabled || _hovered.contains(this)) return;
            _hovered.add(this);
            _refreshHover();
          },
          onExit: (_) {
            _hovered.remove(this);
            _refreshHover();
          },
          onPointerDown: _pointerDown,
          onPointerMove: (event) {
            final down = _down;
            if (down != null &&
                event.pointer == down.pointer &&
                (event.position - down.position).distance > kTouchSlop) {
              _moved = true;
            }
          },
          onPointerUp: _pointerUp,
          onPointerCancel: (_) => _down = null,
          foregroundPainter:
              widget.enabled &&
                  identical(_hoverTarget.value, this) &&
                  EditorOverlayVisibility.openDialogs.value == 0
              ? EditorSelectionOutline(
                  color: AppearanceScope.of(context).accent,
                  dashed: !widget.isZone,
                )
              : null,
          child: child,
        ),
        child: widget.child,
      );
    }
    return MouseRegion(
      opaque: false,
      onEnter: (_) {
        if (widget.enabled) _hovered.add(this);
        _refreshHover();
      },
      onHover: (_) {
        if (!widget.enabled || _hovered.contains(this)) return;
        _hovered.add(this);
        _refreshHover();
      },
      onExit: (_) {
        _hovered.remove(this);
        _refreshHover();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _pointerDown,
        onPointerMove: (event) {
          final down = _down;
          if (down != null &&
              event.pointer == down.pointer &&
              (event.position - down.position).distance > kTouchSlop) {
            _moved = true;
          }
        },
        onPointerUp: _pointerUp,
        onPointerCancel: (_) => _down = null,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            _hoverTarget,
            EditorOverlayVisibility.openDialogs,
          ]),
          builder: (context, child) => CustomPaint(
            foregroundPainter:
                widget.enabled &&
                    identical(_hoverTarget.value, this) &&
                    EditorOverlayVisibility.openDialogs.value == 0
                ? EditorSelectionOutline(
                    color: AppearanceScope.of(context).accent,
                    dashed: !widget.isZone,
                  )
                : null,
            child: child,
          ),
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}

class _EditorOutlineAnimation extends ChangeNotifier {
  static final _EditorOutlineAnimation instance = _EditorOutlineAnimation();

  static const Duration _duration = Duration(milliseconds: 520);
  Duration? _startTimeStamp;
  int? _scheduledFrameId;
  double progress = 1.0;

  void trigger() {
    progress = 0.0;
    _startTimeStamp = null;
    notifyListeners();
    if (hasListeners) {
      _scheduleNextFrame();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (progress < 1.0) {
      _scheduleNextFrame();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _cancelScheduledFrame();
    }
  }

  void _cancelScheduledFrame() {
    if (_scheduledFrameId case final id?) {
      _scheduledFrameId = null;
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
    progress = 1.0;
    _startTimeStamp = null;
  }

  void _scheduleNextFrame() {
    if (_scheduledFrameId != null || !hasListeners) return;
    _scheduledFrameId = SchedulerBinding.instance.scheduleFrameCallback(
      _onFrame,
    );
  }

  void _onFrame(Duration timeStamp) {
    _scheduledFrameId = null;
    if (!hasListeners) {
      progress = 1.0;
      _startTimeStamp = null;
      return;
    }
    _startTimeStamp ??= timeStamp;
    final elapsed = timeStamp - _startTimeStamp!;
    if (elapsed >= _duration || elapsed.isNegative) {
      progress = 1.0;
      _startTimeStamp = null;
      notifyListeners();
      return;
    }
    progress = (elapsed.inMicroseconds / _duration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    notifyListeners();
    _scheduleNextFrame();
  }
}

class EditorSelectionOutline extends CustomPainter {
  EditorSelectionOutline({
    required this.color,
    this.dashed = true,
    this.radius = 0,
    this.emphasized = false,
    this.label,
  }) : super(repaint: _EditorOutlineAnimation.instance);

  final Color color;
  final bool dashed;
  final double radius;
  final bool emphasized;
  final String? label;

  /// Relance l'animation d'entrée (verrouillage des coins + balayage lumineux).
  static void triggerAnimation() {
    _EditorOutlineAnimation.instance.trigger();
  }

  static Color _shiftHue(Color source, double deltaDegrees, double lightness) {
    final hsl = HSLColor.fromColor(source);
    return hsl
        .withHue((hsl.hue + deltaDegrees) % 360)
        .withSaturation((hsl.saturation + 0.15).clamp(0.0, 1.0))
        .withLightness((hsl.lightness + lightness).clamp(0.15, 0.92))
        .toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rawProgress = _EditorOutlineAnimation.instance.progress;
    final lockCurve = Curves.easeOutBack.transform(rawProgress);
    final fadeCurve = Curves.easeOutCubic.transform(rawProgress);

    final baseInset = emphasized ? 1.5 : 1.0;
    // Slight initial expansion that locks onto the target bounds
    final dynamicInset =
        baseInset - (1.0 - lockCurve) * (emphasized ? 4.5 : 2.5);
    final rect = (Offset.zero & size).deflate(dynamicInset);
    if (rect.isEmpty || rect.width <= 2 || rect.height <= 2) return;

    final maxCorner = math.max(0.0, math.min(16.0, rect.shortestSide / 2));
    final cornerRadius = (radius - baseInset).clamp(0.0, maxCorner).toDouble();
    final r = Radius.circular(cornerRadius);
    final rrect = RRect.fromRectAndRadius(rect, r);
    final path = Path()..addRRect(rrect);

    final baseColor = color.withValues(alpha: 1.0);
    final secondaryColor = _shiftHue(baseColor, 38, 0.14);
    final highlightColor = Color.lerp(baseColor, Colors.white, 0.72)!;
    final strokeWidth = emphasized ? 2.6 : 2.0;

    // 1. Subtle inner spotlight tint when emphasized
    if (emphasized) {
      final fillShader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          baseColor.withValues(alpha: 0.11 * fadeCurve),
          secondaryColor.withValues(alpha: 0.04 * fadeCurve),
          baseColor.withValues(alpha: 0.09 * fadeCurve),
        ],
      ).createShader(rect);
      canvas.drawRRect(rrect, Paint()..shader = fillShader);
    }

    // 2. Outer luminous glow halo
    final pulseFactor = 1.0 + 0.25 * math.sin(rawProgress * math.pi);
    final glowPaint = Paint()
      ..color = baseColor.withValues(
        alpha: (emphasized ? 0.26 : 0.14) * fadeCurve,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = (emphasized ? 7.5 : 4.5) * pulseFactor;
    canvas.drawRRect(rrect, glowPaint);

    // 3. High-contrast white underlay stroke
    final contrastPaint = Paint()
      ..color = Colors.white.withValues(
        alpha: (emphasized ? 0.90 : 0.65) * fadeCurve,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1.2;
    canvas.drawRRect(rrect, contrastPaint);

    // 4. Animated SweepGradient border
    final sweepAngle = rawProgress * math.pi * 2.0;
    final sweepShader = SweepGradient(
      colors: [
        baseColor,
        secondaryColor,
        highlightColor,
        secondaryColor,
        baseColor,
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(sweepAngle - math.pi / 4),
    ).createShader(rect);

    final borderPaint = Paint()
      ..shader = sweepShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (!dashed || emphasized) {
      canvas.drawPath(path, borderPaint);
    } else {
      final dashedPath = Path();
      final dashPhase = (1.0 - rawProgress) * 14.0;
      for (final metric in path.computeMetrics()) {
        for (var offset = dashPhase; offset < metric.length; offset += 12) {
          dashedPath.addPath(
            metric.extractPath(
              offset,
              (offset + 7.5).clamp(0.0, metric.length),
            ),
            Offset.zero,
          );
        }
      }
      canvas.drawPath(dashedPath, borderPaint);
    }

    // 5. Dynamic 4-corner Lock-On brackets
    if (rect.width >= 24 && rect.height >= 24) {
      final bracketLen = math
          .min(emphasized ? 14.0 : 10.0, rect.shortestSide * 0.28)
          .clamp(6.0, 18.0)
          .toDouble();
      final bracketSpread = (1.0 - lockCurve) * (emphasized ? 7.0 : 4.0);
      final bRect = rect.inflate(bracketSpread);
      final maxBr = math.max(0.0, math.min(bracketLen - 2, 10.0));
      final br = cornerRadius.clamp(0.0, maxBr).toDouble();
      final bracketPath = _buildCornerBracketsPath(bRect, bracketLen, br);

      canvas.drawPath(
        bracketPath,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.92 * fadeCurve)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (emphasized ? 4.2 : 3.2)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        bracketPath,
        Paint()
          ..color = emphasized ? secondaryColor : baseColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = (emphasized ? 2.8 : 2.0)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 6. Modern gradient pill badge at top-left when emphasized
    final badgeText = label?.trim();
    if (emphasized &&
        badgeText != null &&
        badgeText.isNotEmpty &&
        rect.width >= 44 &&
        rect.height >= 22) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: badgeText,
          style: TextStyle(
            color: Colors.white.withValues(alpha: fadeCurve),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.25,
            height: 1.1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: (rect.width - 24).clamp(24.0, 240.0));

      const hPad = 8.0;
      const vPad = 4.0;
      const dotSize = 5.5;
      const dotGap = 5.0;
      final badgeWidth = textPainter.width + hPad * 2 + dotSize + dotGap;
      final badgeHeight = textPainter.height + vPad * 2;
      final slideOffset = (1.0 - fadeCurve) * -6.0;
      final badgeLeft = rect.left + 6.0;
      final badgeTop = rect.top + 6.0 + slideOffset;
      final badgeRect = Rect.fromLTWH(
        badgeLeft,
        badgeTop,
        badgeWidth,
        badgeHeight,
      );
      final badgeRRect = RRect.fromRectAndRadius(
        badgeRect,
        Radius.circular(badgeHeight / 2),
      );

      // Soft drop shadow
      canvas.drawRRect(
        badgeRRect.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28 * fadeCurve)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );

      // Pill gradient background
      final pillShader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          baseColor.withValues(alpha: 0.96 * fadeCurve),
          secondaryColor.withValues(alpha: 0.96 * fadeCurve),
        ],
      ).createShader(badgeRect);
      canvas.drawRRect(badgeRRect, Paint()..shader = pillShader);

      // Crisp specular border
      canvas.drawRRect(
        badgeRRect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.88 * fadeCurve)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );

      // Glowing indicator dot
      final dotCenter = Offset(
        badgeLeft + hPad + dotSize / 2,
        badgeTop + badgeHeight / 2,
      );
      canvas.drawCircle(
        dotCenter,
        dotSize / 2,
        Paint()..color = Colors.white.withValues(alpha: 0.95 * fadeCurve),
      );

      textPainter.paint(
        canvas,
        Offset(badgeLeft + hPad + dotSize + dotGap, badgeTop + vPad),
      );
      textPainter.dispose();
    }
  }

  static Path _buildCornerBracketsPath(Rect rect, double len, double r) {
    final path = Path();
    // Top-left
    path.moveTo(rect.left, rect.top + len);
    path.lineTo(rect.left, rect.top + r);
    if (r > 0) {
      path.quadraticBezierTo(rect.left, rect.top, rect.left + r, rect.top);
    }
    path.lineTo(rect.left + len, rect.top);

    // Top-right
    path.moveTo(rect.right - len, rect.top);
    path.lineTo(rect.right - r, rect.top);
    if (r > 0) {
      path.quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + r);
    }
    path.lineTo(rect.right, rect.top + len);

    // Bottom-right
    path.moveTo(rect.right, rect.bottom - len);
    path.lineTo(rect.right, rect.bottom - r);
    if (r > 0) {
      path.quadraticBezierTo(
        rect.right,
        rect.bottom,
        rect.right - r,
        rect.bottom,
      );
    }
    path.lineTo(rect.right - len, rect.bottom);

    // Bottom-left
    path.moveTo(rect.left + len, rect.bottom);
    path.lineTo(rect.left + r, rect.bottom);
    if (r > 0) {
      path.quadraticBezierTo(
        rect.left,
        rect.bottom,
        rect.left,
        rect.bottom - r,
      );
    }
    path.lineTo(rect.left, rect.bottom - len);
    return path;
  }

  @override
  bool shouldRepaint(EditorSelectionOutline oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dashed != dashed ||
      oldDelegate.radius != radius ||
      oldDelegate.emphasized != emphasized ||
      oldDelegate.label != label;
}
