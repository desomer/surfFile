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

  @override
  void didUpdateWidget(SuperLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) _config.value = widget.config;
  }

  @override
  void dispose() {
    _config.dispose();
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
        final layout = LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              for (final MapEntry(key: zone, value: rect)
                  in config.resolve(constraints.biggest).entries)
                Positioned.fromRect(
                  key: ValueKey('super-layout-${zone.name}'),
                  rect: rect,
                  child: widget.zones[zone] ?? _ZonePlaceholder(zone: zone),
                ),
            ],
          ),
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
