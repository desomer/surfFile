/// Observation des clics d'evenement sans concurrence avec les gestes natifs.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/component_behavior.dart';
import '../../services/events/super_event_bus.dart';
import '../editing/slots/editor_selection_region.dart';

/// Observe les pointeurs sans absorber focus, selection, bascule ou defilement.
class BehaviorEventListener extends StatefulWidget {
  const BehaviorEventListener({
    required this.componentId,
    required this.componentType,
    required this.behaviors,
    required this.child,
    this.readData,
    this.sliver = false,
    super.key,
  });

  final String componentId;
  final String componentType;
  final List<ComponentBehavior> behaviors;
  final Map<String, Object?> Function()? readData;
  final bool sliver;
  final Widget child;

  @override
  State<BehaviorEventListener> createState() => _BehaviorEventListenerState();
}

class _BehaviorEventListenerState extends State<BehaviorEventListener> {
  static final _targets = Expando<Set<String>>();
  PointerDownEvent? _down;
  Map<String, Object?>? _before;
  PointerDownEvent? _firstDown;
  Duration? _firstUp;
  Map<String, Object?>? _firstBefore;
  int _generation = 0;

  Map<String, Object?> _read() =>
      immutableEventJson(widget.readData?.call() ?? const {});

  void _cancel() {
    _generation++;
    _down = null;
    _before = null;
    _firstDown = null;
    _firstUp = null;
    _firstBefore = null;
  }

  @override
  void didUpdateWidget(BehaviorEventListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.componentId != oldWidget.componentId ||
        widget.behaviors.isEmpty) {
      _cancel();
    }
  }

  void _onDown(PointerDownEvent event) {
    if (widget.behaviors.isEmpty) return;
    if (_down != null || event.buttons != kPrimaryButton) {
      _cancel();
      return;
    }
    PointerEvent original = event;
    while (original.original != null) {
      original = original.original!;
    }
    final targets = _targets[original] ??= <String>{};
    // Equivalent nested slots represent the same technical component.
    if (!targets.add(widget.componentId)) return;
    _down = event;
    _before = _read();
  }

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down != null &&
        down.pointer == event.pointer &&
        (event.position - down.position).distance > kTouchSlop) {
      _cancel();
    }
  }

  void _onUp(PointerUpEvent event) {
    final down = _down;
    final before = _before;
    if (down == null || before == null || down.pointer != event.pointer) return;
    if ((event.position - down.position).distance > kTouchSlop ||
        event.timeStamp - down.timeStamp > kLongPressTimeout) {
      _cancel();
      return;
    }
    _down = null;
    _before = null;
    final firstDown = _firstDown;
    final firstUp = _firstUp;
    final firstBefore = _firstBefore;
    final interval = firstUp == null ? null : down.timeStamp - firstUp;
    final isDouble =
        firstDown != null &&
        firstBefore != null &&
        interval != null &&
        interval >= kDoubleTapMinTime &&
        interval <= kDoubleTapTimeout &&
        firstDown.kind == down.kind &&
        firstDown.device == down.device &&
        (firstDown.position - down.position).distance <= kDoubleTapSlop;
    if (isDouble) {
      _firstDown = null;
      _firstUp = null;
      _firstBefore = null;
    } else {
      _firstDown = down;
      _firstUp = event.timeStamp;
      _firstBefore = before;
    }
    final generation = _generation;
    final componentId = widget.componentId;
    final componentType = widget.componentType;
    final behaviors = List<ComponentBehavior>.of(widget.behaviors);
    // Pointer listeners run before the child's tap callbacks.
    scheduleMicrotask(() async {
      if (!mounted || generation != _generation) return;
      final after = _read();
      for (final trigger in [
        BehaviorTrigger.click,
        if (isDouble) BehaviorTrigger.doubleClick,
      ]) {
        final previous = trigger == BehaviorTrigger.doubleClick
            ? firstBefore!
            : before;
        final data = BehaviorExecutionData(
          componentId: componentId,
          componentType: componentType,
          trigger: trigger,
          data: {
            ...after,
            if (previous.containsKey('value'))
              'previousValue': previous['value'],
          },
        );
        for (final behavior in behaviors) {
          if (!mounted || generation != _generation) return;
          if (behavior.enabled && behavior.trigger == trigger) {
            await behavior.execute(context, data: data);
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.sliver
      ? SliverPointerRegion(
          cursor: widget.behaviors.isEmpty
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: (_) => _cancel(),
          child: widget.child,
        )
      : MouseRegion(
          cursor: widget.behaviors.isEmpty
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: (_) => _cancel(),
            child: widget.child,
          ),
        );
}
