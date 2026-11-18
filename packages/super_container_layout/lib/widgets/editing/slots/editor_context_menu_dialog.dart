/// Route popup, hôte flottant épinglé, carte déplaçable et délégué de positionnement du menu contextuel de [EditorSlot].
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
  bool initiallyDragged = false,
  bool instantOpen = false,
  Rect? bannerLocal,
  Rect? Function()? avoidRectResolver,
  ValueChanged<Route<T>>? onRouteCreated,
  ValueChanged<Offset>? onPinRequested,
}) async {
  final navigator = Navigator.of(context);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final zoomController = EditorZoomScope.controllerOf(context);
  final route = _EditorContextMenuRoute<T>(
    themes: themes,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    initialPosition: initialPosition,
    initiallyDragged: initiallyDragged,
    instantOpen: instantOpen,
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
    onPinRequested: onPinRequested,
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
    required this.initiallyDragged,
    required this.instantOpen,
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
    required this.onPinRequested,
    required this.items,
  });

  final CapturedThemes themes;
  @override
  final String barrierLabel;
  final Offset initialPosition;
  final bool initiallyDragged;
  final bool instantOpen;
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
  final ValueChanged<Offset>? onPinRequested;
  final List<PopupMenuEntry<T>> items;
  bool _instantClose = false;

  void markInstantClose() {
    _instantClose = true;
    controller?.reverseDuration = Duration.zero;
  }

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      instantOpen ? Duration.zero : const Duration(milliseconds: 120);

  @override
  Duration get reverseTransitionDuration =>
      _instantClose ? Duration.zero : transitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    if (_instantClose) return const SizedBox.shrink();
    return themes.wrap(
      _EditorContextMenuDialog<T>(
        animation: animation,
        initialPosition: initialPosition,
        initiallyDragged: initiallyDragged,
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
        onPinRequested: onPinRequested == null
            ? null
            : (resolvedPosition) {
                markInstantClose();
                onPinRequested!(resolvedPosition);
              },
        items: items,
      ),
    );
  }
}

class _EditorContextMenuCard extends StatelessWidget {
  const _EditorContextMenuCard({
    required this.color,
    required this.surfaceTintColor,
    required this.shadowColor,
    required this.elevation,
    required this.shape,
    required this.menuPadding,
    required this.clipBehavior,
    required this.pinned,
    required this.onDragDelta,
    required this.onTogglePin,
    required this.onClose,
    required this.items,
    this.onDragStart,
    this.onPointerSignal,
  });

  final Color color;
  final Color surfaceTintColor;
  final Color shadowColor;
  final double elevation;
  final ShapeBorder shape;
  final EdgeInsetsGeometry menuPadding;
  final Clip clipBehavior;
  final bool pinned;
  final VoidCallback? onDragStart;
  final ValueChanged<Offset> onDragDelta;
  final VoidCallback? onTogglePin;
  final VoidCallback onClose;
  final List<Widget> items;
  final ValueChanged<PointerSignalEvent>? onPointerSignal;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      onExit: (_) => EditorSlotState.clearHighlightedTarget(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: onPointerSignal,
        child: Material(
          key: const ValueKey('editor-context-menu-dialog'),
          color: color,
          surfaceTintColor: surfaceTintColor,
          shadowColor: shadowColor,
          elevation: elevation,
          shape: shape,
          clipBehavior: clipBehavior,
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
                    onPanStart: (_) => onDragStart?.call(),
                    onPanUpdate: (details) => onDragDelta(details.delta),
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
                            if (onTogglePin != null) ...[
                              IconButton(
                                key: const ValueKey('editor-context-menu-pin'),
                                tooltip: pinned
                                    ? 'Désépingler le menu'
                                    : 'Épingler le menu',
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 24,
                                  height: 24,
                                ),
                                style: pinned
                                    ? IconButton.styleFrom(
                                        backgroundColor: colors.primary
                                            .withValues(alpha: .14),
                                        foregroundColor: colors.primary,
                                      )
                                    : null,
                                color: pinned
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                                icon: Icon(
                                  pinned
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                ),
                                onPressed: onTogglePin,
                              ),
                              const SizedBox(width: 2),
                            ],
                            IconButton(
                              key: const ValueKey('editor-context-menu-close'),
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
                              onPressed: onClose,
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
                    scopesRoute: !pinned,
                    namesRoute: !pinned,
                    explicitChildNodes: true,
                    role: SemanticsRole.menu,
                    child: SingleChildScrollView(
                      padding: menuPadding,
                      child: ListBody(
                        children: [
                          for (final item in items)
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
    );
  }
}

class _EditorContextMenuDialog<T> extends StatefulWidget {
  const _EditorContextMenuDialog({
    required this.animation,
    required this.initialPosition,
    required this.initiallyDragged,
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
    required this.onPinRequested,
    required this.items,
  });

  final Animation<double> animation;
  final Offset initialPosition;
  final bool initiallyDragged;
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
  final ValueChanged<Offset>? onPinRequested;
  final List<PopupMenuEntry<T>> items;

  @override
  State<_EditorContextMenuDialog<T>> createState() =>
      _EditorContextMenuDialogState<T>();
}

class _EditorContextMenuDialogState<T>
    extends State<_EditorContextMenuDialog<T>> {
  final _viewportKey = GlobalKey();
  late Offset _position = widget.initialPosition;
  late bool _dragged = widget.initiallyDragged;
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
        zoom.dialog.value != null) {
      return;
    }
    final options = zoom.options.value;
    if (!options.zoomOnRightClick && !options.zoomOnHover) {
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
      child: _EditorContextMenuCard(
        color: widget.color,
        surfaceTintColor: widget.surfaceTintColor,
        shadowColor: widget.shadowColor,
        elevation: widget.elevation,
        shape: widget.shape,
        menuPadding: widget.menuPadding,
        clipBehavior: widget.clipBehavior,
        pinned: false,
        onPointerSignal: (event) => zoom?.handlePointerSignal(event),
        onDragStart: () => _position = _layout.resolvedPosition,
        onDragDelta: (delta) => setState(() {
          _dragged = true;
          _position += delta;
          _layout = _ContextMenuDialogLayout(
            position: _position,
            dragged: _dragged,
            bannerLocal: widget.bannerLocal,
            avoidRect: null,
            menuConstraints: widget.constraints,
          );
        }),
        onTogglePin: widget.onPinRequested == null
            ? null
            : () {
                final resolvedPos = _layout.resolvedPosition;
                widget.onPinRequested!(resolvedPos);
                Navigator.of(context).pop();
              },
        onClose: () => Navigator.of(context).pop(),
        items: widget.items,
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

  void _updateAvailableViewport(Size size, Size childSize) {
    const gap = 12.0;
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
    var maxTotalArea = 0.0;
    for (final viewport in candidateViewports) {
      if (viewport.width < 80 || viewport.height < 80) continue;
      final area = viewport.width * viewport.height;
      if (area > maxTotalArea) maxTotalArea = area;
    }
    if (maxTotalArea <= 0) {
      availableViewport = null;
      return;
    }
    final target = avoidRect;
    final minUsableWidth = math.min(220.0, size.width * 0.25);
    final minUsableHeight = math.min(180.0, size.height * 0.25);
    Rect? bestOverlapViewport;
    var bestOverlapArea = 0.0;
    var bestOverlapTotalArea = -1.0;
    Rect? largestViewport;
    var largestArea = -1.0;
    for (final viewport in candidateViewports) {
      if (viewport.width < 80 || viewport.height < 80) continue;
      final totalArea = viewport.width * viewport.height;
      if (totalArea > largestArea) {
        largestArea = totalArea;
        largestViewport = viewport;
      }
      if (target != null &&
          viewport.width >= minUsableWidth &&
          viewport.height >= minUsableHeight &&
          totalArea >= maxTotalArea * 0.45) {
        final overlap = viewport.intersect(target);
        final overlapArea = overlap.isEmpty
            ? 0.0
            : overlap.width * overlap.height;
        if (overlapArea > bestOverlapArea ||
            (overlapArea > 0 &&
                overlapArea == bestOverlapArea &&
                totalArea > bestOverlapTotalArea)) {
          bestOverlapArea = overlapArea;
          bestOverlapTotalArea = totalArea;
          bestOverlapViewport = viewport;
        }
      }
    }
    availableViewport = bestOverlapViewport ?? largestViewport;
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
      _updateAvailableViewport(size, childSize);
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
    _updateAvailableViewport(size, childSize);
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

class _PinnedContextMenuHost {
  _PinnedContextMenuHost(this.overlay);

  static final Expando<_PinnedContextMenuHost> _hosts =
      Expando<_PinnedContextMenuHost>();
  static final Set<_PinnedContextMenuHost> _activeHosts =
      <_PinnedContextMenuHost>{};

  static _PinnedContextMenuHost of(OverlayState overlay) =>
      _hosts[overlay] ??= _PinnedContextMenuHost(overlay);

  static _PinnedContextMenuHost? maybeOf(OverlayState overlay) =>
      _hosts[overlay];

  static bool get hasActivePinnedMenu =>
      _activeHosts.any((host) => host.isPinned);

  static void closeAll() {
    for (final host in _activeHosts.toList()) {
      host.close();
    }
  }

  final OverlayState overlay;
  OverlayEntry? _entry;
  EditorSlotState? _target;
  List<EditorSlotAction>? _actions;
  BuildContext? _targetContext;
  List<EditorSlotState> _fallbackChain = const [];
  List<PopupMenuEntry<Object>> _cachedItems = const [];
  Offset _position = Offset.zero;
  late _ContextMenuDialogLayout _layout = _ContextMenuDialogLayout(
    position: Offset.zero,
    dragged: true,
    bannerLocal: null,
    avoidRect: null,
    menuConstraints: const BoxConstraints(minWidth: 420, maxWidth: 620),
  );
  BoxConstraints _constraints = const BoxConstraints(
    minWidth: 420,
    maxWidth: 620,
  );
  CapturedThemes? _themes;
  BuildContext? _lastTrackedFocusContext;
  List<String> _lastTrackedPath = const [];
  bool _listeningGlobals = false;
  bool _rebuildScheduled = false;
  bool _refreshScheduled = false;
  bool _pendingSelectionSync = false;
  ValueNotifier<bool>? _editModeNotifier;
  ValueNotifier<Appearance>? _appearanceNotifier;

  bool get isPinned => _entry != null;

  void pin({
    required EditorSlotState target,
    required Offset position,
    required BoxConstraints constraints,
    required CapturedThemes themes,
    List<EditorSlotAction>? actions,
    BuildContext? targetContext,
  }) {
    if (!overlay.mounted) return;
    _position = position;
    _constraints = constraints;
    _themes = themes;
    _layout = _ContextMenuDialogLayout(
      position: _position,
      dragged: true,
      bannerLocal: null,
      avoidRect: null,
      menuConstraints: _constraints,
    );
    _pendingSelectionSync = false;
    _lastTrackedFocusContext = LayoutSelection.focus.value?.context;
    _lastTrackedPath = List<String>.of(LayoutSelection.path.value);
    _attachGlobalListeners();
    _setTargetInternal(
      target: target,
      actions: actions,
      targetContext: targetContext,
    );
    _rebuildCachedItemsFromCurrentTarget();
    if (_cachedItems.isEmpty) {
      close();
      return;
    }
    if (_entry == null) {
      _activeHosts.add(this);
      _entry = OverlayEntry(maintainState: true, builder: _buildOverlay);
      overlay.insert(_entry!);
    } else {
      _markNeedsBuild();
    }
  }

  void updateTarget({
    required EditorSlotState target,
    List<EditorSlotAction>? actions,
    BuildContext? targetContext,
  }) {
    if (!isPinned || !overlay.mounted) return;
    _pendingSelectionSync = false;
    _lastTrackedFocusContext = LayoutSelection.focus.value?.context;
    _lastTrackedPath = List<String>.of(LayoutSelection.path.value);
    if (target.mounted) {
      _themes = InheritedTheme.capture(
        from: target.context,
        to: overlay.context,
      );
    }
    _setTargetInternal(
      target: target,
      actions: actions,
      targetContext: targetContext,
    );
    _rebuildCachedItemsFromCurrentTarget();
    _markNeedsBuild();
  }

  void unpin() {
    final resolvedPosition = _layout.resolvedPosition;
    final target = _ensureValidTargetOrFallback();
    final actions = _actions;
    final targetContext = _targetContext;
    final constraints = _constraints;
    close();
    if (target != null && target.mounted && target.canEdit) {
      unawaited(
        target._openUnpinnedFromPin(
          position: resolvedPosition,
          constraints: constraints,
          actions: actions,
          targetContext: targetContext,
        ),
      );
    }
  }

  void close() {
    EditorSlotState.clearHighlightedTarget();
    _detachAllListeners();
    _activeHosts.remove(this);
    _target = null;
    _actions = null;
    _targetContext = null;
    _fallbackChain = const [];
    _cachedItems = const [];
    _themes = null;
    _lastTrackedFocusContext = null;
    _lastTrackedPath = const [];
    _pendingSelectionSync = false;
    final oldEntry = _entry;
    _entry = null;
    oldEntry?.remove();
    oldEntry?.dispose();
  }

  void _attachGlobalListeners() {
    if (_listeningGlobals) return;
    _listeningGlobals = true;
    LayoutSelection.focus.addListener(_onSelectionChanged);
    LayoutSelection.path.addListener(_onSelectionChanged);
    EditorOverlayVisibility.openDialogs.addListener(_onOpenDialogsChanged);
  }

  void _detachAllListeners() {
    if (_listeningGlobals) {
      _listeningGlobals = false;
      LayoutSelection.focus.removeListener(_onSelectionChanged);
      LayoutSelection.path.removeListener(_onSelectionChanged);
      EditorOverlayVisibility.openDialogs.removeListener(_onOpenDialogsChanged);
    }
    _editModeNotifier?.removeListener(_onEditModeChanged);
    _editModeNotifier = null;
    _appearanceNotifier?.removeListener(_onAppearanceChanged);
    _appearanceNotifier = null;
  }

  void _bindContextNotifiers(BuildContext slotContext) {
    final nextEditMode = StyleEditScope.maybeReadOf(slotContext);
    if (!identical(nextEditMode, _editModeNotifier)) {
      _editModeNotifier?.removeListener(_onEditModeChanged);
      _editModeNotifier = nextEditMode;
      nextEditMode?.addListener(_onEditModeChanged);
    }
    final nextAppearance = AppearanceScope.controllerOf(slotContext);
    if (!identical(nextAppearance, _appearanceNotifier)) {
      _appearanceNotifier?.removeListener(_onAppearanceChanged);
      _appearanceNotifier = nextAppearance;
      nextAppearance?.addListener(_onAppearanceChanged);
    }
  }

  void _setTargetInternal({
    required EditorSlotState target,
    required List<EditorSlotAction>? actions,
    required BuildContext? targetContext,
  }) {
    _target = target;
    _actions = actions;
    _targetContext = targetContext;
    if (target.mounted) {
      _fallbackChain = target.editableChain;
      _bindContextNotifiers(target.context);
    }
  }

  void _rebuildCachedItemsFromCurrentTarget() {
    final target = _target;
    if (target == null || !target.mounted || !target.canEdit) {
      _cachedItems = const [];
      return;
    }
    _cachedItems = target._buildSlotMenuItems(
      hostContext: target.context,
      onSelect: _handleActionSelected,
      interceptItemTap: true,
      actions: _actions,
    );
  }

  void _scheduleItemsRefresh() {
    if (!isPinned || !overlay.mounted) return;
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!isPinned || !overlay.mounted) return;
      if (_pendingSelectionSync) {
        _pendingSelectionSync = false;
        _applySelectionSync();
      } else {
        final valid = _ensureValidTargetOrFallback();
        if (valid == null) {
          close();
          return;
        }
      }
      _rebuildCachedItemsFromCurrentTarget();
      if (_cachedItems.isEmpty) {
        close();
        return;
      }
      _entry?.markNeedsBuild();
      WidgetsBinding.instance.ensureVisualUpdate();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _applySelectionSync() {
    final focusCtx = LayoutSelection.focus.value?.context;
    if (focusCtx != null && focusCtx.mounted) {
      final resolved = EditorSlotState.resolveFromContext(
        focusCtx,
        preferredId: LayoutSelection.activeLeafId,
      );
      if (resolved != null && resolved.mounted && resolved.canEdit) {
        if (overlay.mounted) {
          _themes = InheritedTheme.capture(
            from: resolved.context,
            to: overlay.context,
          );
        }
        _setTargetInternal(
          target: resolved,
          actions: null,
          targetContext: null,
        );
        return;
      }
    }
    _ensureValidTargetOrFallback();
  }

  void _onEditModeChanged() {
    if (!isPinned) return;
    if (!(_editModeNotifier?.value ?? true)) {
      close();
    }
  }

  void _onAppearanceChanged() {
    if (!isPinned) return;
    _scheduleItemsRefresh();
  }

  void _onOpenDialogsChanged() {
    if (!isPinned) return;
    if (EditorOverlayVisibility.openDialogs.value > 0) {
      EditorSlotState.clearHighlightedTarget();
      _markNeedsBuild();
    } else {
      _markNeedsBuild();
      _scheduleItemsRefresh();
    }
  }

  void _onSelectionChanged() {
    if (!isPinned) return;
    final focusCtx = LayoutSelection.focus.value?.context;
    final currentPath = LayoutSelection.path.value;
    if (identical(focusCtx, _lastTrackedFocusContext) &&
        listEquals(currentPath, _lastTrackedPath)) {
      return;
    }
    _lastTrackedFocusContext = focusCtx;
    _lastTrackedPath = List<String>.of(currentPath);
    _pendingSelectionSync = true;
    _scheduleItemsRefresh();
  }

  EditorSlotState? _ensureValidTargetOrFallback() {
    final current = _target;
    if (current != null && current.mounted && current.canEdit) {
      _fallbackChain = current.editableChain;
      return current;
    }
    final focusCtx = LayoutSelection.focus.value?.context;
    if (focusCtx != null && focusCtx.mounted) {
      final resolved = EditorSlotState.resolveFromContext(
        focusCtx,
        preferredId: LayoutSelection.activeLeafId,
      );
      if (resolved != null && resolved.mounted && resolved.canEdit) {
        if (overlay.mounted) {
          _themes = InheritedTheme.capture(
            from: resolved.context,
            to: overlay.context,
          );
        }
        _setTargetInternal(
          target: resolved,
          actions: null,
          targetContext: null,
        );
        return resolved;
      }
    }
    for (final ancestor in _fallbackChain) {
      if (ancestor.mounted && ancestor.canEdit) {
        if (overlay.mounted) {
          _themes = InheritedTheme.capture(
            from: ancestor.context,
            to: overlay.context,
          );
        }
        _setTargetInternal(
          target: ancestor,
          actions: null,
          targetContext: null,
        );
        return ancestor;
      }
    }
    _target = null;
    return null;
  }

  void _markNeedsBuild() {
    if (!isPinned || !overlay.mounted) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_rebuildScheduled) return;
      _rebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (isPinned && overlay.mounted) {
          _entry?.markNeedsBuild();
        }
      });
      return;
    }
    _entry?.markNeedsBuild();
  }

  void _handleActionSelected(Object selection) {
    EditorSlotState.clearHighlightedTarget();
    unawaited(() async {
      await _executeSlotMenuSelection(selection);
      if (!isPinned) return;
      _scheduleItemsRefresh();
    }());
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    if (!isPinned || !overlay.mounted || _cachedItems.isEmpty) {
      return const SizedBox.shrink();
    }
    final hiddenByDialog = EditorOverlayVisibility.openDialogs.value > 0;
    Widget content = Builder(
      builder: (themedContext) {
        final colors = Theme.of(themedContext).colorScheme;
        _layout = _ContextMenuDialogLayout(
          position: _position,
          dragged: true,
          bannerLocal: null,
          avoidRect: null,
          menuConstraints: _constraints,
        );
        final card = _EditorContextMenuCard(
          color: colors.surfaceContainerHigh.withAlpha(240),
          surfaceTintColor: Colors.transparent,
          shadowColor: colors.shadow.withValues(alpha: .18),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: .55),
            ),
          ),
          menuPadding: const EdgeInsets.symmetric(vertical: 4),
          clipBehavior: Clip.antiAlias,
          pinned: true,
          onDragStart: () => _position = _layout.resolvedPosition,
          onDragDelta: (delta) {
            _position += delta;
            _markNeedsBuild();
          },
          onTogglePin: unpin,
          onClose: close,
          items: _cachedItems,
        );
        return Visibility(
          visible: !hiddenByDialog,
          maintainState: true,
          child: CustomSingleChildLayout(delegate: _layout, child: card),
        );
      },
    );
    if (_themes case final captured?) {
      content = captured.wrap(content);
    }
    return content;
  }
}
