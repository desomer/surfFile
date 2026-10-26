import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../theme/appearance.dart';
import '../overlay/editor_overlay.dart';

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
    _hoverTarget.value = index < 0 || isPassThrough
        ? _zone(chain)
        : chain[(index + 1).clamp(0, chain.length - 1)];
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
  Widget build(BuildContext context) => MouseRegion(
    opaque: false,
    onEnter: (_) {
      if (widget.enabled) _hovered.add(this);
      _refreshHover();
    },
    onHover: (_) {
      if (widget.enabled) _hovered.add(this);
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
        child: widget.child,
      ),
    ),
  );
}

class EditorSelectionOutline extends CustomPainter {
  const EditorSelectionOutline({
    required this.color,
    this.dashed = true,
    this.radius = 0,
  });

  final Color color;
  final bool dashed;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.75);
    if (rect.isEmpty) return;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular((radius - .75).clamp(0, rect.shortestSide / 2)),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 11) {
        canvas.drawPath(metric.extractPath(offset, offset + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(EditorSelectionOutline oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dashed != dashed ||
      oldDelegate.radius != radius;
}
