/// Route popup, boîte de dialogue déplaçable et délégué de positionnement du menu contextuel de [EditorSlot].
part of 'editor_slot.dart';

Future<T?> _showEditorContextMenuDialog<T>({
  required BuildContext context,
  required Offset initialPosition,
  required BoxConstraints constraints,
  required Color color,
  required Color surfaceTintColor,
  required Color shadowColor,
  required double elevation,
  required ShapeBorder shape,
  required EdgeInsetsGeometry menuPadding,
  required Clip clipBehavior,
  required List<PopupMenuEntry<T>> items,
  Rect? bannerLocal,
  Rect? Function()? avoidRectResolver,
  ValueChanged<Route<T>>? onRouteCreated,
}) async {
  final navigator = Navigator.of(context);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final zoomController = EditorZoomScope.controllerOf(context);
  final route = _EditorContextMenuRoute<T>(
    themes: themes,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    initialPosition: initialPosition,
    bannerLocal: bannerLocal,
    avoidRectResolver: avoidRectResolver,
    constraints: constraints,
    color: color,
    surfaceTintColor: surfaceTintColor,
    shadowColor: shadowColor,
    elevation: elevation,
    shape: shape,
    menuPadding: menuPadding,
    clipBehavior: clipBehavior,
    zoomController: zoomController,
    items: items,
  );
  onRouteCreated?.call(route);
  final hasZoom =
      zoomController != null &&
      !zoomController.disposed &&
      zoomController.enabled;
  if (hasZoom) {
    zoomController.openContextMenus.value++;
  }
  try {
    return await navigator.push<T>(route);
  } finally {
    if (hasZoom && !zoomController.disposed) {
      zoomController.openContextMenus.value--;
      if (zoomController.openContextMenus.value == 0) {
        zoomController.contextMenuAvailable.value = null;
      }
    }
  }
}

class _EditorContextMenuRoute<T> extends PopupRoute<T> {
  _EditorContextMenuRoute({
    required this.themes,
    required this.barrierLabel,
    required this.initialPosition,
    required this.bannerLocal,
    required this.avoidRectResolver,
    required this.constraints,
    required this.color,
    required this.surfaceTintColor,
    required this.shadowColor,
    required this.elevation,
    required this.shape,
    required this.menuPadding,
    required this.clipBehavior,
    required this.zoomController,
    required this.items,
  });

  final CapturedThemes themes;
  @override
  final String barrierLabel;
  final Offset initialPosition;
  final Rect? bannerLocal;
  final Rect? Function()? avoidRectResolver;
  final BoxConstraints constraints;
  final Color color;
  final Color surfaceTintColor;
  final Color shadowColor;
  final double elevation;
  final ShapeBorder shape;
  final EdgeInsetsGeometry menuPadding;
  final Clip clipBehavior;
  final EditorZoomController? zoomController;
  final List<PopupMenuEntry<T>> items;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    _EditorContextMenuDialog<T>(
      animation: animation,
      initialPosition: initialPosition,
      bannerLocal: bannerLocal,
      avoidRectResolver: avoidRectResolver,
      constraints: constraints,
      color: color,
      surfaceTintColor: surfaceTintColor,
      shadowColor: shadowColor,
      elevation: elevation,
      shape: shape,
      menuPadding: menuPadding,
      clipBehavior: clipBehavior,
      zoomController: zoomController,
      items: items,
    ),
  );
}

class _EditorContextMenuDialog<T> extends StatefulWidget {
  const _EditorContextMenuDialog({
    required this.animation,
    required this.initialPosition,
    required this.bannerLocal,
    required this.avoidRectResolver,
    required this.constraints,
    required this.color,
    required this.surfaceTintColor,
    required this.shadowColor,
    required this.elevation,
    required this.shape,
    required this.menuPadding,
    required this.clipBehavior,
    required this.zoomController,
    required this.items,
  });

  final Animation<double> animation;
  final Offset initialPosition;
  final Rect? bannerLocal;
  final Rect? Function()? avoidRectResolver;
  final BoxConstraints constraints;
  final Color color;
  final Color surfaceTintColor;
  final Color shadowColor;
  final double elevation;
  final ShapeBorder shape;
  final EdgeInsetsGeometry menuPadding;
  final Clip clipBehavior;
  final EditorZoomController? zoomController;
  final List<PopupMenuEntry<T>> items;

  @override
  State<_EditorContextMenuDialog<T>> createState() =>
      _EditorContextMenuDialogState<T>();
}

class _EditorContextMenuDialogState<T>
    extends State<_EditorContextMenuDialog<T>> {
  final _viewportKey = GlobalKey();
  late Offset _position = widget.initialPosition;
  bool _dragged = false;
  late final Rect? _initialAvoidRect = widget.avoidRectResolver?.call();
  late _ContextMenuDialogLayout _layout = _ContextMenuDialogLayout(
    position: _position,
    dragged: _dragged,
    bannerLocal: widget.bannerLocal,
    avoidRect: _initialAvoidRect,
    menuConstraints: widget.constraints,
  );
  ZoomToolbarLayout _zoomToolbarLayout = ZoomToolbarLayout(null);

  void _syncZoomAvailable() {
    final zoom = widget.zoomController;
    if (zoom == null ||
        zoom.disposed ||
        !zoom.enabled ||
        zoom.dialog.value != null ||
        widget.avoidRectResolver == null) {
      return;
    }
    final options = zoom.options.value;
    if (!options.zoomOnRightClick) {
      if (zoom.contextMenuAvailable.value != null) {
        zoom.contextMenuAvailable.value = null;
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          zoom.disposed ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final box = _viewportKey.currentContext?.findRenderObject();
      final available = _layout.availableViewport;
      if (box is! RenderBox || !box.hasSize || available == null) {
        if (zoom.contextMenuAvailable.value != null) {
          zoom.contextMenuAvailable.value = null;
        }
        return;
      }
      final screen = Rect.fromPoints(
        box.localToGlobal(available.topLeft),
        box.localToGlobal(available.bottomRight),
      );
      if (zoom.contextMenuAvailable.value != screen) {
        zoom.contextMenuAvailable.value = screen;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final zoom = widget.zoomController;
    final showZoomToolbar =
        zoom != null &&
        !zoom.disposed &&
        zoom.enabled &&
        zoom.dialog.value == null;
    if (!_dragged) {
      _layout = _ContextMenuDialogLayout(
        position: _position,
        dragged: _dragged,
        bannerLocal: widget.bannerLocal,
        avoidRect: _initialAvoidRect ?? widget.avoidRectResolver?.call(),
        menuConstraints: widget.constraints,
      );
    }
    _syncZoomAvailable();
    final dialogCard = FadeTransition(
      opacity: CurvedAnimation(parent: widget.animation, curve: Curves.easeOut),
      child: MouseRegion(
        onExit: (_) => EditorSlotState.clearHighlightedTarget(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) => zoom?.handlePointerSignal(event),
          child: Material(
            key: const ValueKey('editor-context-menu-dialog'),
            color: widget.color,
            surfaceTintColor: widget.surfaceTintColor,
            shadowColor: widget.shadowColor,
            elevation: widget.elevation,
            shape: widget.shape,
            clipBehavior: widget.clipBehavior,
            child: IntrinsicWidth(
              stepWidth: 56.0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      key: const ValueKey('editor-context-menu-drag'),
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onPanUpdate: (details) => setState(() {
                        _dragged = true;
                        _position = _layout.resolvedPosition + details.delta;
                        _layout = _ContextMenuDialogLayout(
                          position: _position,
                          dragged: _dragged,
                          bannerLocal: widget.bannerLocal,
                          avoidRect: null,
                          menuConstraints: widget.constraints,
                        );
                      }),
                      child: ColoredBox(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: .45,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.drag_indicator,
                                size: 16,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Center(
                                  child: Container(
                                    width: 32,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: colors.onSurfaceVariant.withValues(
                                        alpha: .35,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                key: const ValueKey(
                                  'editor-context-menu-close',
                                ),
                                tooltip: 'Fermer',
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 24,
                                  height: 24,
                                ),
                                color: colors.onSurfaceVariant,
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 1,
                    child: ColoredBox(
                      color: colors.outlineVariant.withValues(alpha: .4),
                    ),
                  ),
                  Flexible(
                    child: Semantics(
                      scopesRoute: true,
                      namesRoute: true,
                      explicitChildNodes: true,
                      role: SemanticsRole.menu,
                      child: SingleChildScrollView(
                        padding: widget.menuPadding,
                        child: ListBody(
                          children: [
                            for (final item in widget.items)
                              Builder(builder: (_) => item),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Stack(
      key: _viewportKey,
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if ((event.buttons & kSecondaryMouseButton) != 0) {
                zoom?.handlePointerDown(event);
              }
            },
            onPointerMove: (event) {
              if ((event.buttons & kSecondaryMouseButton) != 0) {
                zoom?.handlePointerMove(event);
              }
            },
            onPointerUp: (event) => zoom?.handlePointerUp(event),
            onPointerCancel: (event) => zoom?.handlePointerCancel(event),
            onPointerSignal: (event) => zoom?.handlePointerSignal(event),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        if (showZoomToolbar)
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _zoomToolbarLayout = ZoomToolbarLayout(
                zoom.toolbarPosition,
              ),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal: zoom.handlePointerSignal,
                child: Material(
                  key: const ValueKey('editor-zoom-toolbar'),
                  type: MaterialType.card,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  child: ValueListenableBuilder<double>(
                    valueListenable: zoom.scale,
                    builder: (context, currentScale, _) =>
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: EditorZoomToolbarContent(
                            scale: currentScale,
                            onScaleChanged: zoom.setScale,
                            onDrag: (details) => setState(() {
                              final nextPos =
                                  _zoomToolbarLayout.resolvedPosition +
                                  details.delta;
                              zoom.toolbarPosition = nextPos;
                              _zoomToolbarLayout = ZoomToolbarLayout(nextPos);
                            }),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: CustomSingleChildLayout(delegate: _layout, child: dialogCard),
        ),
      ],
    );
  }
}

class _ContextMenuDialogLayout extends SingleChildLayoutDelegate {
  _ContextMenuDialogLayout({
    required this.position,
    required this.dragged,
    required this.bannerLocal,
    required this.avoidRect,
    required this.menuConstraints,
  }) : resolvedPosition = position;

  final Offset position;
  final bool dragged;
  final Rect? bannerLocal;
  final Rect? avoidRect;
  final BoxConstraints menuConstraints;
  Offset resolvedPosition;
  Rect? availableViewport;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = math.min(menuConstraints.maxWidth, constraints.maxWidth);
    final minWidth = math.min(menuConstraints.minWidth, maxWidth);
    final maxHeight = dragged
        ? math.max(120.0, constraints.maxHeight - 16.0)
        : math.min(
            menuConstraints.maxHeight,
            math.max(120.0, constraints.maxHeight - 16.0),
          );
    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    if (dragged) {
      final maxX = math.max(0.0, size.width - childSize.width);
      final maxY = math.max(0.0, size.height - childSize.height);
      resolvedPosition = Offset(
        position.dx.clamp(0.0, maxX),
        position.dy.clamp(0.0, maxY),
      );
      return resolvedPosition;
    }
    const margin = 8.0;
    const gap = 12.0;
    final maxX = math.max(margin, size.width - childSize.width - margin);
    var minY = margin;
    var maxY = math.max(margin, size.height - childSize.height - margin);
    var desiredX = position.dx;
    var desiredY = position.dy;
    if (avoidRect == null && bannerLocal != null) {
      final banner = bannerLocal!;
      final spaceAbove = banner.top;
      final spaceBelow = size.height - banner.bottom;
      if (spaceBelow >= spaceAbove || spaceBelow >= 220) {
        minY = banner.bottom + 6;
        maxY = math.max(minY, size.height - childSize.height - margin);
        desiredY = math.max(position.dy, minY);
      } else {
        final maxBottom = banner.top - 6;
        maxY = math.max(margin, maxBottom - childSize.height);
        desiredY = math.min(position.dy, maxBottom) - childSize.height;
      }
    } else if (avoidRect case final rawTarget?) {
      if (bannerLocal case final banner? when banner.top < 120) {
        minY = math.max(minY, banner.bottom + 6);
        maxY = math.max(minY, size.height - childSize.height - margin);
      }
      final screenRect = Offset.zero & size;
      final target = rawTarget.intersect(screenRect);
      if (!target.isEmpty &&
          (target.width < size.width * .92 ||
              target.height < size.height * .92)) {
        final alignedY = target.top.clamp(minY, maxY);
        final alignedX = target.left.clamp(margin, maxX);
        final horizontalCandidates = <Offset>[
          if (target.right + gap + childSize.width <= size.width - margin)
            Offset(target.right + gap, alignedY),
          if (target.left - gap - childSize.width >= margin)
            Offset(target.left - gap - childSize.width, alignedY),
        ];
        final verticalCandidates = <Offset>[
          if (target.bottom + gap + childSize.height <= size.height - margin)
            Offset(alignedX, target.bottom + gap),
          if (target.top - gap - childSize.height >= minY)
            Offset(alignedX, target.top - gap - childSize.height),
        ];
        final candidates = horizontalCandidates.isNotEmpty
            ? horizontalCandidates
            : verticalCandidates;
        if (candidates.isNotEmpty) {
          Offset? best;
          var bestDist = double.infinity;
          for (final candidate in candidates) {
            final dist = (candidate - position).distanceSquared;
            if (dist < bestDist) {
              bestDist = dist;
              best = candidate;
            }
          }
          desiredX = best!.dx;
          desiredY = best.dy;
        } else {
          final spaceRight = size.width - margin - target.right;
          final spaceLeft = target.left - margin;
          desiredX = spaceRight >= spaceLeft ? maxX : margin;
          desiredY = alignedY;
        }
      }
    }
    final dx = desiredX.clamp(margin, maxX);
    final dy = desiredY.clamp(minY, maxY);
    resolvedPosition = Offset(dx, dy);
    if (avoidRect case final target?) {
      final dialogRect = resolvedPosition & childSize;
      final candidateViewports = <Rect>[
        Rect.fromLTWH(0, 0, math.max(0.0, dialogRect.left - gap), size.height),
        Rect.fromLTWH(
          math.min(size.width, dialogRect.right + gap),
          0,
          math.max(0.0, size.width - dialogRect.right - gap),
          size.height,
        ),
        Rect.fromLTWH(0, 0, size.width, math.max(0.0, dialogRect.top - gap)),
        Rect.fromLTWH(
          0,
          math.min(size.height, dialogRect.bottom + gap),
          size.width,
          math.max(0.0, size.height - dialogRect.bottom - gap),
        ),
      ];
      Rect? bestViewport;
      var bestOverlapArea = -1.0;
      var bestTotalArea = -1.0;
      for (final viewport in candidateViewports) {
        if (viewport.width < 80 || viewport.height < 80) continue;
        final overlap = viewport.intersect(target);
        final overlapArea = overlap.isEmpty
            ? 0.0
            : overlap.width * overlap.height;
        final totalArea = viewport.width * viewport.height;
        if (overlapArea > bestOverlapArea ||
            (overlapArea == bestOverlapArea && totalArea > bestTotalArea)) {
          bestOverlapArea = overlapArea;
          bestTotalArea = totalArea;
          bestViewport = viewport;
        }
      }
      availableViewport = bestViewport;
    }
    return resolvedPosition;
  }

  @override
  bool shouldRelayout(_ContextMenuDialogLayout oldDelegate) =>
      position != oldDelegate.position ||
      dragged != oldDelegate.dragged ||
      bannerLocal != oldDelegate.bannerLocal ||
      avoidRect != oldDelegate.avoidRect ||
      menuConstraints != oldDelegate.menuConstraints;
}
