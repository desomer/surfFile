part of '../super_layout.dart';

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
            SwitchListTile(
              key: ValueKey('super-layout-auto-${side.name}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Taille automatique'),
              value: config.isAuto(side),
              onChanged: (v) => onChanged(config.withAuto(side, v)),
            ),
          if (config.hasSide(side) && !config.isAuto(side))
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
        const Divider(),
        const Text('Axe d’affichage des zones'),
        for (final zone in SuperLayoutZone.values)
          Row(
            children: [
              Expanded(child: Text(zone.label)),
              DropdownButton<Axis>(
                key: ValueKey('super-layout-axis-${zone.name}'),
                value: config.axisOf(zone),
                onChanged: config.visibleZones.contains(zone)
                    ? (axis) {
                        if (axis != null) {
                          onChanged(config.withAxis(zone, axis));
                        }
                      }
                    : null,
                items: const [
                  DropdownMenuItem(value: Axis.horizontal, child: Text('Row')),
                  DropdownMenuItem(value: Axis.vertical, child: Text('Column')),
                ],
              ),
            ],
          ),
        TextButton(
          onPressed: () => onChanged(
            const SuperLayoutConfig().copyWith(
              placements: config.placements,
              slotTypes: config.slotTypes,
            ),
          ),
          child: const Text('Réinitialiser'),
        ),
      ],
    );
  }
}
