part of 'super_layout.dart';

/// Pastille du nom d'une zone, centrée sur celle-ci pendant le mode édition.
/// Un clic sur une zone ayant une opposée ([swapTarget]) révèle un bouton qui
/// échange leurs contenus, ou déplace la zone si l'opposée n'existe pas
/// ([moves]).
class _ZoneNameBadge extends StatefulWidget {
  const _ZoneNameBadge({
    required this.zone,
    required this.label,
    required this.zoneLabel,
    required this.onSwap,
    required this.overCenter,
    required this.onCenterHint,
    required this.emphasis,
    required this.selected,
    required this.onSelect,
    this.swapTarget,
    this.moves = false,
    this.axisAction,
    this.onAdd,
  });

  final SuperLayoutZone zone;
  final String label;
  final String Function(SuperLayoutZone) zoneLabel;
  final SuperLayoutZone? swapTarget;
  final bool moves;
  final VoidCallback onSwap;
  final ValueListenable<bool> overCenter;

  /// Signale que ce nom est survolé ou glissé : le centre doit être surligné.
  final ValueChanged<bool> onCenterHint;
  final LabelEmphasis emphasis;

  /// La zone est sélectionnée ; un clic sur son nom la (dé)sélectionne.
  final bool selected;
  final VoidCallback onSelect;
  final LayoutAxisAction? axisAction;
  final VoidCallback? onAdd;

  @override
  State<_ZoneNameBadge> createState() => _ZoneNameBadgeState();
}

class _ZoneNameBadgeState extends State<_ZoneNameBadge> {
  bool _open = false;

  /// Le nom est survolé ou glissé : la zone qu'il désigne est surlignée.
  bool _hover = false;
  bool _dragging = false;

  void _setHover(bool value) {
    if (mounted && value != _hover) {
      setState(() => _hover = value);
      _report();
    }
  }

  void _setDragging(bool value) {
    if (mounted && value != _dragging) {
      setState(() => _dragging = value);
      _report();
    }
  }

  void _report() {
    final active = _hover || _dragging;
    widget.emphasis.report(widget.zone, active);
    // Le centre n'a pas de centre associé : il se surligne lui-même.
    if (widget.zone != SuperLayoutZone.center) widget.onCenterHint(active);
  }

  @override
  void dispose() {
    if (_hover || _dragging) {
      // Le parent ne doit pas être notifié pendant le démontage.
      final zone = widget.zone;
      final emphasis = widget.emphasis;
      final centerHint = widget.onCenterHint;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        emphasis.report(zone, false);
        if (zone != SuperLayoutZone.center) centerHint(false);
      });
    }
    super.dispose();
  }

  IconData get _icon => switch (widget.zone) {
    SuperLayoutZone.north || SuperLayoutZone.south => Icons.swap_vert,
    SuperLayoutZone.west || SuperLayoutZone.east => Icons.swap_horiz,
    _ => Icons.swap_calls,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final target = widget.swapTarget;
    final badge = EditorZoneBadge(
      label: widget.label,
      selected: widget.selected,
      mouseCursor: target == null
          ? SystemMouseCursors.click
          : editorDragCursor(dragging: _dragging),
      onTap: () {
        setState(() => _open = !_open);
        widget.onSelect();
      },
      leading: target == null
          ? null
          : Icon(
              Icons.drag_indicator,
              key: ValueKey('super-layout-zone-drag-${widget.zone.name}'),
              size: 12,
              color: colors.onSurface,
            ),
      onAdd: widget.onAdd,
      addKey: ValueKey('super-layout-add-${widget.zone.name}'),
      addTooltip: 'Ajouter un slot dans ${widget.label}',
      actions: [
        if (widget.axisAction case final action?)
          ZoneAxisButton(
            key: ValueKey('super-layout-toggle-axis-${widget.zone.name}'),
            action: action,
            compact: true,
            color: colors.onSurface,
          ),
        if (_open && target != null)
          IconButton(
            key: ValueKey('super-layout-swap-${widget.zone.name}'),
            tooltip: widget.moves
                ? 'Déplacer vers ${widget.zoneLabel(target)}'
                : 'Échanger avec ${widget.zoneLabel(target)}',
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            color: colors.onSurface,
            icon: Icon(_icon),
            onPressed: () {
              setState(() => _open = false);
              widget.onSwap();
            },
          )
        else
          const SizedBox(width: 2),
      ],
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_hover || _dragging)
          EditorZoneHighlight(
            key: ValueKey('super-layout-zone-highlight-${widget.zone.name}'),
          ),
        if (widget.selected)
          Positioned.fill(
            key: ValueKey('super-layout-zone-selected-${widget.zone.name}'),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.primary, width: 3),
                ),
              ),
            ),
          ),
        Center(
          key: const ValueKey('super-layout-zone-badge'),
          child: EmphasizedLabel(
            emphasis: widget.emphasis,
            allScopes: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: EditorSelectionRegion.ignorePointer,
                child: MouseRegion(
                  cursor: target == null
                      ? SystemMouseCursors.click
                      : editorDragCursor(dragging: _dragging),
                  hitTestBehavior: HitTestBehavior.translucent,
                  onEnter: (_) => _setHover(true),
                  onExit: (_) => _setHover(false),
                  // Glisser le nom vers le centre déclenche l'échange.
                  child: target == null
                      ? badge
                      : Draggable<SuperLayoutZone>(
                          onDragStarted: () => _setDragging(true),
                          onDragEnd: (_) => _setDragging(false),
                          data: widget.zone,
                          feedback: Material(
                            color: colors.primary.withValues(alpha: .35),
                            elevation: 4,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              // Pendant le survol du centre, le nom devient la zone future.
                              child: ValueListenableBuilder<bool>(
                                valueListenable: widget.overCenter,
                                builder: (context, over, _) => Text(
                                  over
                                      ? widget.zoneLabel(target)
                                      : widget.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: .35,
                            child: badge,
                          ),
                          child: badge,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cible de dépôt sur le centre : illuminée pendant qu'un nom de zone la
/// survole, elle échange alors cette zone avec son opposée au relâchement.
class _CenterSwapTarget extends StatelessWidget {
  const _CenterSwapTarget({
    required this.canSwap,
    required this.onSwap,
    required this.overCenter,
    required this.hint,
  });

  final ValueNotifier<bool> overCenter;

  /// Le nom d'une autre zone est survolé : le centre est mis en évidence.
  final ValueListenable<bool> hint;
  final bool Function(SuperLayoutZone zone) canSwap;
  final ValueChanged<SuperLayoutZone> onSwap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DragTarget<SuperLayoutZone>(
      onWillAcceptWithDetails: (details) {
        final accept = canSwap(details.data);
        overCenter.value = accept;
        return accept;
      },
      onLeave: (_) => overCenter.value = false,
      onAcceptWithDetails: (details) {
        overCenter.value = false;
        onSwap(details.data);
      },
      builder: (context, candidates, _) => EditorOverlay(
        child: IgnorePointer(
          child: candidates.isEmpty
              ? ValueListenableBuilder<bool>(
                  valueListenable: hint,
                  builder: (context, hinted, _) => hinted
                      ? DecoratedBox(
                          key: const ValueKey('super-layout-center-hint'),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .08),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: .7),
                              width: 1.5,
                            ),
                          ),
                          child: const SizedBox.expand(),
                        )
                      : const SizedBox.expand(),
                )
              : DecoratedBox(
                  key: const ValueKey('super-layout-center-drop'),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .2),
                    border: Border.all(color: colors.primary, width: 2),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ZonePlaceholder extends StatelessWidget {
  const _ZonePlaceholder({
    required this.zone,
    required this.label,
    this.showLabel = true,
  });

  final SuperLayoutZone zone;
  final String label;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final editMode = StyleEditScope.controllerOf(context)?.value ?? false;
    return EditorOverlayVisibility(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: editMode ? Border.all(color: colors.outlineVariant) : null,
        ),
        // child: Center(
        //   child: showLabel && editMode
        //       ? Text(
        //           label,
        //           overflow: TextOverflow.ellipsis,
        //           style: TextStyle(color: colors.onSurfaceVariant),
        //         )
        //       : null,
        // ),
      ),
    );
  }
}
