/// Défilement des zones de layout et mesure de leur viewport pour les slots.
library;

import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart';
import '../../../theme/theme_color.dart';

/// Mesure interne du viewport disponible autour d'un layout défilant.
abstract interface class ScrollViewportMetrics implements RenderObject {
  /// Taille du viewport après retrait de son padding.
  Size get viewportSize;
}

/// Conteneur défilant d'une zone avec barre de défilement configurable.
class ZoneScrollableViewport extends StatefulWidget {
  /// Crée un viewport pour une zone de layout.
  const ZoneScrollableViewport({
    required this.axis,
    required this.showScrollbar,
    this.scrollbarStyle = const ScrollbarStyleConfig(),
    this.padding = EdgeInsets.zero,
    required this.child,
    super.key,
  });

  /// Axe de défilement de la zone.
  final Axis axis;

  /// Indique si la barre de défilement est visible.
  final bool showScrollbar;

  /// Style appliqué à la barre de défilement.
  final ScrollbarStyleConfig scrollbarStyle;

  /// Padding intérieur de la zone.
  final EdgeInsets padding;

  /// Contenu défilant.
  final Widget child;

  @override
  State<ZoneScrollableViewport> createState() => _ZoneScrollableViewportState();
}

class _ZoneScrollableViewportState extends State<ZoneScrollableViewport> {
  final ScrollController _controller = ScrollController();

  void _handlePointerSignal(PointerSignalEvent event) {
    if (widget.axis != Axis.horizontal ||
        event is! PointerScrollEvent ||
        event.scrollDelta.dx != 0 ||
        event.scrollDelta.dy == 0 ||
        !_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    if (position.maxScrollExtent <= position.minScrollExtent) return;
    final target = (position.pixels + event.scrollDelta.dy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolved,
    ) {
      if (!mounted || !_controller.hasClients) return;
      _controller.position.pointerScroll(
        (resolved as PointerScrollEvent).scrollDelta.dy,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget scrollView = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: widget.axis,
        padding: widget.padding == EdgeInsets.zero ? null : widget.padding,
        child: widget.child,
      ),
    );
    if (widget.showScrollbar) {
      final style = widget.scrollbarStyle;
      final colors = Theme.of(context).colorScheme;
      scrollView = RawScrollbar(
        controller: _controller,
        thumbVisibility: style.thumbVisibility,
        trackVisibility: style.trackVisibility,
        interactive: style.interactive,
        thickness: style.thickness,
        radius: Radius.circular(style.radius),
        mainAxisMargin: style.mainAxisMargin,
        crossAxisMargin: style.crossAxisMargin,
        thumbColor:
            style.thumbColor.resolveTheme(context) ??
            colors.onSurfaceVariant.withValues(alpha: 0.45),
        trackColor:
            style.trackColor.resolveTheme(context) ??
            colors.surfaceContainerHighest.withValues(alpha: 0.35),
        trackBorderColor:
            style.trackBorderColor.resolveTheme(context) ??
            (style.trackVisibility
                ? colors.outlineVariant.withValues(alpha: 0.5)
                : const Color(0x00000000)),
        scrollbarOrientation: style.side.resolveOrientation(widget.axis),
        child: scrollView,
      );
    }
    if (widget.axis == Axis.horizontal) {
      scrollView = Listener(
        onPointerSignal: _handlePointerSignal,
        child: scrollView,
      );
    }
    return ScrollViewportHost(padding: widget.padding, child: scrollView);
  }
}

/// Portée de rendu indiquant qu'un conteneur parent gère le défilement.
class ScrollViewportHost extends SingleChildRenderObjectWidget {
  /// Crée une portée de viewport avec un padding optionnel.
  const ScrollViewportHost({
    this.padding = EdgeInsets.zero,
    required super.child,
    super.key,
  });

  /// Padding déduit de la taille utile du viewport.
  final EdgeInsets padding;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollViewportHost(padding);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderScrollViewportHost).padding = padding;
}

class _RenderScrollViewportHost extends RenderProxyBox
    implements ScrollViewportMetrics {
  _RenderScrollViewportHost(this._padding);

  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  @override
  Size viewportSize = Size.zero;

  @override
  void performLayout() {
    viewportSize = constraints.deflate(_padding).biggest;
    super.performLayout();
  }
}
