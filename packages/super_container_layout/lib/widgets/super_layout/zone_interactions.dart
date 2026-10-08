part of '../super_layout.dart';

/// Pastille du nom d'une zone, centrée sur celle-ci pendant le mode édition.
/// Un clic sur une zone ayant une opposée ([swapTarget]) révèle un bouton qui
/// échange leurs contenus, ou déplace la zone si l'opposée n'existe pas
/// ([moves]).
class _ZoneNameBadge extends StatefulWidget {
  const _ZoneNameBadge({
    required this.zone,
    required this.onSwap,
    required this.overCenter,
    required this.onCenterHint,
    required this.emphasis,
    required this.selected,
    required this.onSelect,
    this.swapTarget,
    this.moves = false,
  });

  final SuperLayoutZone zone;
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
    final label = Text(
      widget.zone.label,
      style: TextStyle(fontSize: 11, color: colors.onSurface),
    );
    final badge = Material(
      color: colors.primary.withValues(alpha: .35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.selected ? colors.onSurface : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: target == null
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: label,
            )
          : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() => _open = !_open);
                widget.onSelect();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 1, 4, 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    label,
                    if (_open)
                      IconButton(
                        key: ValueKey('super-layout-swap-${widget.zone.name}'),
                        tooltip: widget.moves
                            ? 'Déplacer vers ${target.label}'
                            : 'Échanger avec ${target.label}',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        color: colors.onSurface,
                        icon: Icon(_icon),
                        onPressed: () {
                          setState(() => _open = false);
                          widget.onSwap();
                        },
                      )
                    else
                      const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_hover || _dragging)
          Positioned.fill(
            key: ValueKey('super-layout-zone-highlight-${widget.zone.name}'),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .12),
                  border: Border.all(color: colors.primary, width: 2),
                ),
              ),
            ),
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
              child: MouseRegion(
                hitTestBehavior: HitTestBehavior.translucent,
                onEnter: (_) => _setHover(true),
                onExit: (_) => _setHover(false),
                // Glisser le nom vers le centre déclenche l'échange.
                child: target == null
                    ? GestureDetector(onTap: widget.onSelect, child: badge)
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
                                over ? target.label : widget.zone.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: .35, child: badge),
                        child: badge,
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
      builder: (context, candidates, _) => IgnorePointer(
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
    );
  }
}

/// Cible de dépôt d'une zone entière pour les slots de son propriétaire.
class _SlotZoneTarget extends StatelessWidget {
  const _SlotZoneTarget({
    required this.owner,
    required this.zoneLabel,
    required this.ids,
    required this.onMove,
  });

  final Object owner;
  final String zoneLabel;

  /// Slots visibles de la zone, dans l'ordre.
  final List<String> ids;
  final ValueChanged<String> onMove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DragTarget<SlotDragData>(
      onWillAcceptWithDetails: (details) {
        final accepts = identical(details.data.owner, owner);
        if (accepts) {
          details.data.hint.value = SlotDropHint.at(
            zoneLabel: zoneLabel,
            ids: ids,
            movedId: details.data.id,
          );
        }
        return accepts;
      },
      onLeave: (data) => data?.hint.value = null,
      onAcceptWithDetails: (details) => onMove(details.data.id),
      builder: (context, candidates, _) => IgnorePointer(
        child: candidates.isEmpty
            ? const SizedBox.expand()
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.tertiary.withValues(alpha: .15),
                  border: Border.all(color: colors.tertiary, width: 2),
                ),
              ),
      ),
    );
  }
}

class _ZonePlaceholder extends StatelessWidget {
  const _ZonePlaceholder({required this.zone});

  final SuperLayoutZone zone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Center(
        // child: Text(
        //   zone.label,
        //   overflow: TextOverflow.ellipsis,
        //   style: TextStyle(color: colors.onSurfaceVariant),
        // ),
      ),
    );
  }
}
