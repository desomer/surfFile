import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../models/super_layout_config.dart';
import 'super_container.dart';

/// Disposition en neuf zones (Nord, Sud, Est, Ouest, coins et Centre) dont la
/// structure s'édite par clic droit, comme un [SuperContainer].
///
/// Les zones à afficher sont fournies dans [zones] ; une zone sans widget
/// montre un repère portant son nom. Le widget occupe tout l'espace disponible.
class SuperLayout extends StatefulWidget {
  const SuperLayout({
    required this.zones,
    this.config = const SuperLayoutConfig(),
    this.onChanged,
    this.label = 'Super layout',
    this.editable = true,
    this.centerHeight,
    super.key,
  });

  final Map<SuperLayoutZone, Widget> zones;
  final SuperLayoutConfig config;
  final ValueChanged<SuperLayoutConfig>? onChanged;
  final String label;
  final bool editable;

  /// Hauteur de la ligne centrale. Si elle est fournie, le widget prend la
  /// hauteur du centre plus celle des zones Nord et Sud affichées, ce qui
  /// permet de l'utiliser dans une hauteur non bornée (ex. une [Column]).
  final double? centerHeight;

  @override
  State<SuperLayout> createState() => SuperLayoutState();
}

class SuperLayoutState extends State<SuperLayout> {
  late final ValueNotifier<SuperLayoutConfig> _config = ValueNotifier(
    widget.config,
  );

  SuperLayoutConfig get config => _config.value;

  /// Vrai quand un nom de zone glissé survole le centre.
  final _overCenter = ValueNotifier(false);

  @override
  void didUpdateWidget(SuperLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) _config.value = widget.config;
  }

  @override
  void dispose() {
    _config.dispose();
    _overCenter.dispose();
    super.dispose();
  }

  void _update(SuperLayoutConfig value) {
    if (value == _config.value) return;
    _config.value = value;
    widget.onChanged?.call(value);
  }

  Future<void> _openEditor() async {
    final initial = _config.value;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (context) => AlertDialog(
        title: Text(widget.label),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: _config,
              builder: (context, _) =>
                  SuperLayoutEditor(config: _config.value, onChanged: _update),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
    if (confirmed != true && mounted) _update(initial);
  }

  @override
  Widget build(BuildContext context) => SuperContainer(
    decorate: false,
    label: widget.label,
    editable: widget.editable,
    onEdit: _openEditor,
    child: ListenableBuilder(
      listenable: _config,
      builder: (context, _) {
        final config = _config.value;
        final editing = StyleEditScope.controllerOf(context)?.value ?? false;
        final layout = LayoutBuilder(
          builder: (context, constraints) {
            final rects = config.resolve(constraints.biggest);
            return Stack(
              fit: StackFit.expand,
              children: [
                for (final MapEntry(key: zone, value: rect) in rects.entries)
                  Positioned.fromRect(
                    key: ValueKey('super-layout-${zone.name}'),
                    rect: rect,
                    child:
                        widget.zones[config.contentZone(zone)] ??
                        _ZonePlaceholder(zone: zone),
                  ),
                // Noms des zones utilisées, au-dessus de leur centre.
                if (editing) ...[
                  Positioned.fromRect(
                    key: const ValueKey('super-layout-center-target'),
                    rect: rects[SuperLayoutZone.center]!,
                    child: _CenterSwapTarget(
                      overCenter: _overCenter,
                      canSwap: (zone) =>
                          widget.editable &&
                          rects.containsKey(zone) &&
                          config.canSwap(zone),
                      onSwap: (zone) => _update(config.withSwap(zone)),
                    ),
                  ),
                  for (final MapEntry(key: zone, value: rect) in rects.entries)
                    if (widget.zones.containsKey(config.contentZone(zone)))
                      Positioned.fromRect(
                        key: ValueKey('super-layout-name-${zone.name}'),
                        rect: rect,
                        child: _ZoneNameBadge(
                          zone: zone,
                          overCenter: _overCenter,
                          swapTarget: widget.editable && config.canSwap(zone)
                              ? zone.opposite
                              : null,
                          moves: !rects.containsKey(zone.opposite),
                          onSwap: () => _update(config.withSwap(zone)),
                        ),
                      ),
                ],
              ],
            );
          },
        );
        final centerHeight = widget.centerHeight;
        if (centerHeight == null) return layout;
        return SizedBox(
          height:
              centerHeight +
              (config.north ? config.northSize : 0) +
              (config.south ? config.southSize : 0),
          child: layout,
        );
      },
    ),
  );
}

/// Pastille du nom d'une zone, centrée sur celle-ci pendant le mode édition.
/// Un clic sur une zone ayant une opposée ([swapTarget]) révèle un bouton qui
/// échange leurs contenus, ou déplace la zone si l'opposée n'existe pas
/// ([moves]).
class _ZoneNameBadge extends StatefulWidget {
  const _ZoneNameBadge({
    required this.zone,
    required this.onSwap,
    required this.overCenter,
    this.swapTarget,
    this.moves = false,
  });

  final SuperLayoutZone zone;
  final SuperLayoutZone? swapTarget;
  final bool moves;
  final VoidCallback onSwap;
  final ValueListenable<bool> overCenter;

  @override
  State<_ZoneNameBadge> createState() => _ZoneNameBadgeState();
}

class _ZoneNameBadgeState extends State<_ZoneNameBadge> {
  bool _open = false;

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
      style: TextStyle(fontSize: 11, color: colors.onPrimary),
    );
    final badge = Material(
      color: colors.primary.withValues(alpha: .85),
      borderRadius: BorderRadius.circular(12),
      child: target == null
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: label,
            )
          : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _open = !_open),
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
                        color: colors.onPrimary,
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
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        // Glisser le nom vers le centre déclenche l'échange.
        child: target == null
            ? IgnorePointer(child: badge)
            : Draggable<SuperLayoutZone>(
                data: widget.zone,
                feedback: Material(
                  color: colors.primary,
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
                        style: TextStyle(fontSize: 11, color: colors.onPrimary),
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(opacity: .35, child: badge),
                child: badge,
              ),
      ),
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
  });

  final ValueNotifier<bool> overCenter;
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
            ? const SizedBox.expand()
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
        child: Text(
          zone.label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Formulaire d'édition d'un [SuperLayoutConfig] : aperçu, présence des côtés,
/// fusion des coins et tailles.
class SuperLayoutEditor extends StatelessWidget {
  const SuperLayoutEditor({
    required this.config,
    required this.onChanged,
    super.key,
  });

  final SuperLayoutConfig config;
  final ValueChanged<SuperLayoutConfig> onChanged;

  static const _sides = [
    SuperLayoutZone.north,
    SuperLayoutZone.south,
    SuperLayoutZone.west,
    SuperLayoutZone.east,
  ];
  static const _corners = [
    SuperLayoutZone.nw,
    SuperLayoutZone.ne,
    SuperLayoutZone.sw,
    SuperLayoutZone.se,
  ];

  static double _size(SuperLayoutConfig config, SuperLayoutZone side) =>
      switch (side) {
        SuperLayoutZone.north => config.northSize,
        SuperLayoutZone.south => config.southSize,
        SuperLayoutZone.west => config.westSize,
        _ => config.eastSize,
      };

  SuperLayoutConfig _withSize(SuperLayoutZone side, double value) =>
      switch (side) {
        SuperLayoutZone.north => config.copyWith(northSize: value),
        SuperLayoutZone.south => config.copyWith(southSize: value),
        SuperLayoutZone.west => config.copyWith(westSize: value),
        _ => config.copyWith(eastSize: value),
      };

  /// Voisins d'un coin : (zone de sa ligne, zone de sa colonne).
  static (SuperLayoutZone, SuperLayoutZone) _neighbors(
    SuperLayoutZone corner,
  ) => switch (corner) {
    SuperLayoutZone.nw => (SuperLayoutZone.north, SuperLayoutZone.west),
    SuperLayoutZone.ne => (SuperLayoutZone.north, SuperLayoutZone.east),
    SuperLayoutZone.sw => (SuperLayoutZone.south, SuperLayoutZone.west),
    _ => (SuperLayoutZone.south, SuperLayoutZone.east),
  };

  static String _mergeLabel(SuperLayoutZone corner, CornerMerge merge) {
    final (row, column) = _neighbors(corner);
    return switch (merge) {
      CornerMerge.none => 'Case propre',
      CornerMerge.row => 'Fusionné avec ${row.label}',
      CornerMerge.column => 'Fusionné avec ${column.label}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = config.copyWith(
      northSize: 36,
      southSize: 36,
      westSize: 70,
      eastSize: 70,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('super-layout-preview'),
          height: 170,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                for (final MapEntry(key: zone, value: rect)
                    in preview.resolve(constraints.biggest).entries)
                  Positioned.fromRect(
                    key: ValueKey('super-layout-preview-${zone.name}'),
                    rect: rect.deflate(1),
                    child: ColoredBox(
                      color: colors.primaryContainer,
                      child: Center(
                        child: Text(
                          zone.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final side in _sides) ...[
          SwitchListTile(
            key: ValueKey('super-layout-side-${side.name}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(side.label),
            value: config.hasSide(side),
            onChanged: (v) => onChanged(config.withSide(side, v)),
          ),
          if (config.hasSide(side))
            Slider(
              key: ValueKey('super-layout-size-${side.name}'),
              min: SuperLayoutConfig.minSize,
              max: SuperLayoutConfig.maxSize,
              value: _size(
                config,
                side,
              ).clamp(SuperLayoutConfig.minSize, SuperLayoutConfig.maxSize),
              label: '${_size(config, side).round()}',
              onChanged: (v) => onChanged(_withSize(side, v)),
            ),
        ],
        const Divider(),
        for (final corner in _corners)
          Row(
            children: [
              Expanded(child: Text(corner.label)),
              DropdownButton<CornerMerge>(
                key: ValueKey('super-layout-corner-${corner.name}'),
                value: config.mergeOf(corner),
                onChanged: config.cornerExists(corner)
                    ? (v) => onChanged(config.withCorner(corner, v!))
                    : null,
                items: [
                  for (final merge in CornerMerge.values)
                    DropdownMenuItem(
                      value: merge,
                      child: Text(_mergeLabel(corner, merge)),
                    ),
                ],
              ),
            ],
          ),
        TextButton(
          onPressed: () => onChanged(const SuperLayoutConfig()),
          child: const Text('Réinitialiser'),
        ),
      ],
    );
  }
}
