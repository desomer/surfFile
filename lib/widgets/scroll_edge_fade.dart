import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/appearance.dart';

class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({required this.child, super.key});

  final Widget child;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  double _top = 0;
  double _bottom = 0;
  double _pendingTop = 0;
  double _pendingBottom = 0;
  bool _scheduled = false;
  // Permet de retirer le ShaderMask (une couche hors écran à chaque image)
  // quand aucun bord n'est estompé, sans perdre l'état du défilement.
  final _contentKey = GlobalKey();

  void _update(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return;
    _pendingTop = math.max(0, metrics.extentBefore);
    _pendingBottom = math.max(0, metrics.extentAfter);
    if (_scheduled || (_pendingTop == _top && _pendingBottom == _bottom)) {
      return;
    }
    _scheduled = true;
    // Metrics notifications can arrive during layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || (_pendingTop == _top && _pendingBottom == _bottom)) {
        return;
      }
      setState(() {
        _top = _pendingTop;
        _bottom = _pendingBottom;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    final extent = appearance.scrollFadeEnabled
        ? appearance.scrollFadeExtent
        : 0.0;
    final content = KeyedSubtree(key: _contentKey, child: widget.child);
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _update(notification.metrics, notification.depth);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _update(notification.metrics, notification.depth);
          return false;
        },
        child: _top == 0 && _bottom == 0 || extent == 0
            ? content
            : ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) {
                  final top = bounds.height == 0
                      ? 0.0
                      : math.min(math.min(_top, extent) / bounds.height, .5);
                  final bottom = bounds.height == 0
                      ? 0.0
                      : math.min(math.min(_bottom, extent) / bounds.height, .5);
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      top == 0 ? Colors.white : Colors.transparent,
                      Colors.white,
                      Colors.white,
                      bottom == 0 ? Colors.white : Colors.transparent,
                    ],
                    stops: [0, top, 1 - bottom, 1],
                  ).createShader(bounds);
                },
                child: content,
              ),
      ),
    );
  }
}
