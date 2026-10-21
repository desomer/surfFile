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

  static _EditorSelectionRegionState _zone(
    List<_EditorSelectionRegionState> chain,
  ) {
    final index = _selected == null ? -1 : chain.indexOf(_selected!);
    if (index >= 0) {
      for (var i = index; i >= 0; i--) {
        if (chain[i].widget.isZone) return chain[i];
      }
    }
    final previous = _selected;
    if (previous != null && previous.mounted) {
      for (final state in previous._ancestry.reversed) {
        if (state.widget.isZone && chain.contains(state)) return state;
      }
    }
    return chain.firstWhere(
      (state) => state.widget.isZone,
      orElse: () => chain.first,
    );
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
    final index = _selected == null ? -1 : chain.indexOf(_selected!);
    _hoverTarget.value = index < 0
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
    final doubleClick =
        identical(_lastLeaf, this) &&
        (_doubleTapTimer?.isActive ?? false) &&
        !(_minimumTapTimer?.isActive ?? false) &&
        (event.position - _lastPosition!).distance <= kDoubleTapSlop;
    final base = doubleClick ? _lastBase : _selected;
    var target = _zone(chain);
    if (doubleClick) {
      final index = base == null ? -1 : chain.indexOf(base);
      final zoneIndex = chain.indexOf(target);
      target =
          chain[((index < 0 ? zoneIndex : index) + 1).clamp(
            0,
            chain.length - 1,
          )];
    }
    _lastBase = _selected;
    _doubleTapTimer?.cancel();
    _minimumTapTimer?.cancel();
    if (!doubleClick) {
      _doubleTapTimer = Timer(kDoubleTapTimeout, () {});
      _minimumTapTimer = Timer(kDoubleTapMinTime, () {});
    }
    _lastPosition = event.position;
    _lastLeaf = this;
    _selected = target;
    target.widget.onSelect();
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
        _selected = this;
      } else if (identical(_selected, this)) {
        _selected = null;
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
