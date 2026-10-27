part of 'super_layout.dart';

/// Formulaire d'édition d'un [SuperLayoutConfig] : aperçu, présence des côtés,
/// fusion des coins et tailles.
class SuperLayoutEditor extends StatefulWidget {
  const SuperLayoutEditor({
    required this.config,
    required this.onChanged,
    this.zoneLabels = const {},
    super.key,
  });

  final SuperLayoutConfig config;
  final ValueChanged<SuperLayoutConfig> onChanged;
  final Map<SuperLayoutZone, String> zoneLabels;

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

  /// Voisins d'un coin : (zone de sa ligne, zone de sa colonne).
  static (SuperLayoutZone, SuperLayoutZone) _neighbors(
    SuperLayoutZone corner,
  ) => switch (corner) {
    SuperLayoutZone.nw => (SuperLayoutZone.north, SuperLayoutZone.west),
    SuperLayoutZone.ne => (SuperLayoutZone.north, SuperLayoutZone.east),
    SuperLayoutZone.sw => (SuperLayoutZone.south, SuperLayoutZone.west),
    _ => (SuperLayoutZone.south, SuperLayoutZone.east),
  };

  @override
  State<SuperLayoutEditor> createState() => _SuperLayoutEditorState();
}

class _SuperLayoutEditorState extends State<SuperLayoutEditor> {
  SuperLayoutConfig get config => widget.config;
  ValueChanged<SuperLayoutConfig> get onChanged => widget.onChanged;

  String _zoneLabel(SuperLayoutZone zone) =>
      widget.zoneLabels[zone] ?? zone.label;

  String _mergeLabel(SuperLayoutZone corner, CornerMerge merge) {
    final (row, column) = SuperLayoutEditor._neighbors(corner);
    return switch (merge) {
      CornerMerge.none => 'Case propre',
      CornerMerge.row => 'Fusionné avec ${_zoneLabel(row)}',
      CornerMerge.column => 'Fusionné avec ${_zoneLabel(column)}',
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
    final activeCorners = [
      for (final corner in SuperLayoutEditor._corners)
        if (config.cornerExists(corner)) corner,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<SuperLayoutPositioning>(
          key: const ValueKey('super-layout-positioning'),
          segments: const [
            ButtonSegment(
              value: SuperLayoutPositioning.zones,
              label: Text('Zones'),
              icon: Icon(Icons.view_quilt_outlined),
            ),
            ButtonSegment(
              value: SuperLayoutPositioning.grid,
              label: Text('Grille'),
              icon: Icon(Icons.grid_view),
            ),
          ],
          selected: {config.positioning},
          onSelectionChanged: (modes) =>
              onChanged(config.withPositioning(modes.single)),
        ),
        const SizedBox(height: 12),
        if (config.positioning == SuperLayoutPositioning.grid)
          ..._gridSettings()
        else ...[
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
                            _zoneLabel(zone),
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
          for (final pair in const [
            (SuperLayoutZone.north, SuperLayoutZone.south),
            (SuperLayoutZone.west, SuperLayoutZone.east),
          ])
            Row(
              children: [
                for (final side in [pair.$1, pair.$2])
                  Expanded(
                    child: SwitchListTile(
                      key: ValueKey('super-layout-side-${side.name}'),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(_zoneLabel(side)),
                      value: config.hasSide(side),
                      onChanged: (v) => onChanged(config.withSide(side, v)),
                    ),
                  ),
              ],
            ),
          SwitchListTile(
            key: const ValueKey('super-layout-resize-sides'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Redimensionner tous les côtés par glisser'),
            subtitle: const Text(
              'Bord intérieur de 5 px, même hors du mode édition. '
              'Le glisser désactive la taille automatique du côté.',
            ),
            value: SuperLayoutEditor._sides.every(config.canResize),
            onChanged: (value) => onChanged(
              config.copyWith(resizeSides: value, sideResizing: {}),
            ),
          ),
          if (activeCorners.isNotEmpty) ...[
            const Divider(),
            for (final corner in activeCorners)
              Row(
                children: [
                  Expanded(child: Text(_zoneLabel(corner))),
                  DropdownButton<CornerMerge>(
                    key: ValueKey('super-layout-corner-${corner.name}'),
                    value: config.mergeOf(corner),
                    onChanged: (v) => onChanged(config.withCorner(corner, v!)),
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
          ],
        ],
        TextButton(
          onPressed: () => onChanged(
            config.positioning == SuperLayoutPositioning.grid
                ? config.copyWith(
                    grid: GridLayoutConfig(items: config.effectiveGrid.items)
                        .withColumns(12),
                  )
                : const SuperLayoutConfig().copyWith(
                    placements: config.placements,
                    slotTypes: config.slotTypes,
                    slotLabels: config.slotLabels,
                    label: config.label,
                    positioning: config.positioning,
                    grid: config.grid,
                  ),
          ),
          child: const Text('Réinitialiser'),
        ),
      ],
    );
  }

  List<Widget> _gridSettings() {
    final grid = config.effectiveGrid;
    Widget slider(
      String name,
      String label,
      double value,
      double min,
      double max,
      ValueChanged<double> change,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label : ${value.round()}'),
        EditorHistorySlider(
          key: ValueKey('grid-setting-$name'),
          value: value,
          min: min,
          max: max,
          onChanged: change,
        ),
      ],
    );
    return [
      const Text(
        'Les composants se placent sur des cellules, sans chevauchement.',
      ),
      slider(
        'columns',
        'Colonnes',
        grid.columns.toDouble(),
        1,
        48,
        (v) => onChanged(config.copyWith(grid: grid.withColumns(v.round()))),
      ),
      slider(
        'row-height',
        'Hauteur des lignes (px)',
        grid.rowHeight,
        16,
        400,
        (v) => onChanged(
          config.copyWith(grid: grid.copyWith(rowHeight: v.roundToDouble())),
        ),
      ),
      slider(
        'gap',
        'Espacement (px)',
        grid.gap,
        0,
        64,
        (v) => onChanged(
          config.copyWith(grid: grid.copyWith(gap: v.roundToDouble())),
        ),
      ),
      SwitchListTile(
        key: const ValueKey('grid-setting-compact'),
        title: const Text('Compactage vertical'),
        value: grid.compact,
        onChanged: (v) => onChanged(
          config.copyWith(grid: grid.copyWith(compact: v).arrange()),
        ),
      ),
      const Text(
        'Glisser le label pour déplacer un composant. '
        'Les flèches redimensionnent en cellules. Les tailles px/% du mode Zones sont conservées.',
      ),
    ];
  }
}

/// Éditeur des paramètres d'une zone (taille pour un côté, direction, scroll,
/// alignements, espacement entre éléments et marge intérieure).
class ZoneFlowSettingsEditor extends StatelessWidget {
  const ZoneFlowSettingsEditor({
    required this.keyPrefix,
    required this.axis,
    required this.flow,
    required this.onAxisChanged,
    required this.onFlowChanged,
    this.showAxis = true,
    this.isSide = false,
    this.sizeAxis,
    this.autoSize = true,
    this.size = 100,
    this.canResize = false,
    this.onAutoSizeChanged,
    this.onSizeChanged,
    this.onResizeChanged,
    super.key,
  });

  final String keyPrefix;
  final Axis axis;
  final ZoneFlowConfig flow;
  final ValueChanged<Axis> onAxisChanged;
  final ValueChanged<ZoneFlowConfig> onFlowChanged;
  final bool showAxis;
  final bool isSide;
  final Axis? sizeAxis;
  final bool autoSize;
  final double size;
  final bool canResize;
  final ValueChanged<bool>? onAutoSizeChanged;
  final ValueChanged<double>? onSizeChanged;
  final ValueChanged<bool>? onResizeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final autoOnFlowAxis = isSide && autoSize && sizeAxis == axis;
    final autoSizeTitle = switch (sizeAxis) {
      Axis.vertical => 'Taille automatique (hauteur)',
      Axis.horizontal => 'Taille automatique (largeur)',
      null => 'Taille automatique',
    };
    final autoSizeSubtitle = switch (sizeAxis) {
      Axis.vertical => 'La hauteur de la zone s’adapte à son contenu.',
      Axis.horizontal => 'La largeur de la zone s’adapte à son contenu.',
      null => 'S’adapte à la taille naturelle de son contenu.',
    };
    final expandTitle = axis == Axis.horizontal
        ? 'Étirer les éléments sur la ligne (flex : 1)'
        : 'Étirer les éléments sur la colonne (flex : 1)';
    final expandSubtitle = autoOnFlowAxis
        ? 'Désactivé : la zone s’adapte déjà à la taille des éléments sur cet axe.'
        : axis == Axis.horizontal
        ? 'Les éléments se partagent toute la largeur de la ligne (décochez pour garder leur largeur naturelle).'
        : 'Les éléments se partagent toute la hauteur de la colonne (décochez pour garder leur hauteur naturelle).';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isSide)
          _FlowSectionCard(
            title: 'Taille de la zone',
            icon: Icons.straighten,
            subtitle: 'Dimensions et redimensionnement de ce côté',
            children: [
              SwitchListTile(
                key: ValueKey('$keyPrefix-auto-size'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  autoSizeTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  autoSizeSubtitle,
                  style: const TextStyle(fontSize: 11),
                ),
                value: autoSize,
                onChanged: onAutoSizeChanged,
              ),
              if (!autoSize)
                if (onSizeChanged case final changeSize?) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Taille fixe',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                      decoration: BoxDecoration(
                          color: colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${size.round()} px',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  EditorHistorySlider(
                    key: ValueKey('$keyPrefix-size'),
                    min: SuperLayoutConfig.minSize,
                    max: SuperLayoutConfig.maxSize,
                    value: size.clamp(
                      SuperLayoutConfig.minSize,
                      SuperLayoutConfig.maxSize,
                    ),
                    label: '${size.round()}',
                    onChanged: changeSize,
                  ),
                ],
              if (onResizeChanged != null) ...[
                Divider(
                  height: 12,
                  color: colors.outlineVariant.withValues(alpha: 0.4),
                ),
                SwitchListTile(
                  key: ValueKey('$keyPrefix-resizable'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Redimensionner par glisser',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text(
                    'Poignée sur le bord intérieur de la zone.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: canResize,
                  onChanged: onResizeChanged,
                ),
              ],
            ],
          ),
        if (showAxis)
          _FlowSectionCard(
            title: 'Direction du flux',
            icon: Icons.alt_route_rounded,
            subtitle: 'Orientation des éléments dans cette zone',
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<Axis>(
                  key: ValueKey('$keyPrefix-axis'),
                  segments: const [
                    ButtonSegment(
                      value: Axis.horizontal,
                      label: Text('Ligne (Row)'),
                      icon: Icon(Icons.view_week_outlined),
                    ),
                    ButtonSegment(
                      value: Axis.vertical,
                      label: Text('Colonne (Column)'),
                      icon: Icon(Icons.view_agenda_outlined),
                    ),
                  ],
                  selected: {axis},
                  onSelectionChanged: (selected) {
                    if (selected.isNotEmpty) {
                      onAxisChanged(selected.first);
                    }
                  },
                ),
              ),
            ],
          ),
        _FlowSectionCard(
          title: 'Comportement du contenu',
          icon: Icons.tune_rounded,
          subtitle: 'Dimensionnement des éléments et défilement',
          children: [
            SwitchListTile(
              key: ValueKey('$keyPrefix-fit-content'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.open_in_full_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              title: Text(
                expandTitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                expandSubtitle,
                style: const TextStyle(fontSize: 11),
              ),
              value: !autoOnFlowAxis && flow.expandSlots,
              onChanged: autoOnFlowAxis
                  ? null
                  : (expand) =>
                        onFlowChanged(flow.copyWith(expandSlots: expand)),
            ),
            Divider(
              height: 12,
              color: colors.outlineVariant.withValues(alpha: 0.4),
            ),
            SwitchListTile(
              key: ValueKey('$keyPrefix-scrollable'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.swap_vert_circle_outlined,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              title: const Text(
                'Défilement automatique (scroll)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Empile les éléments sans les compresser et active le scroll si besoin.',
                style: TextStyle(fontSize: 11),
              ),
              value: flow.scrollable,
              onChanged: (value) =>
                  onFlowChanged(flow.copyWith(scrollable: value)),
            ),
          ],
        ),
        _FlowSectionCard(
          title: 'Alignement & Distribution',
          icon: Icons.format_align_center_rounded,
          subtitle: 'Positionnement sur les axes principal et transversal',
          children: [
            Text(
              'Alignement principal (${axis == Axis.horizontal ? "Horizontal" : "Vertical"})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            getSegmentedMainAlign(),
            const SizedBox(height: 14),
            Text(
              'Alignement transversal (${axis == Axis.horizontal ? "Vertical" : "Horizontal"})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            getSegmentedCrossAlign(),
          ],
        ),
        _FlowSectionCard(
          title: 'Espacement & Marges',
          icon: Icons.space_dashboard_outlined,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Espacement entre éléments',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${flow.spacing.round()} px',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            EditorHistorySlider(
              key: ValueKey('$keyPrefix-spacing'),
              min: 0,
              max: ZoneFlowConfig.maxSpacing,
              value: flow.spacing.clamp(0, ZoneFlowConfig.maxSpacing),
              label: '${flow.spacing.round()}',
              onChanged: (next) =>
                  onFlowChanged(flow.copyWith(spacing: next.roundToDouble())),
            ),
            Divider(
              height: 10,
              color: colors.outlineVariant.withValues(alpha: 0.4),
            ),
            IndependentSpacingEditor(
              label: 'Marge intérieure',
              value: flow.padding,
              sides: flow.paddingInsets,
              max: ZoneFlowConfig.maxPadding,
              keyPrefix: '$keyPrefix-padding',
              onChanged: (padding, sides) => onFlowChanged(
                flow.copyWith(
                  padding: padding.roundToDouble(),
                  paddingInsets: sides == null
                      ? null
                      : EdgeInsets.fromLTRB(
                          sides.left.roundToDouble(),
                          sides.top.roundToDouble(),
                          sides.right.roundToDouble(),
                          sides.bottom.roundToDouble(),
                        ),
                  clearPaddingInsets: sides == null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  SizedBox getSegmentedCrossAlign() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<CrossAxisAlignment>(
        key: ValueKey('$keyPrefix-cross-alignment'),
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
        ),
        segments: const [
          ButtonSegment(
            value: CrossAxisAlignment.start,
            label: Text('Début', style: TextStyle(fontSize: 12)),
            tooltip: 'Début (Start)',
          ),
          ButtonSegment(
            value: CrossAxisAlignment.center,
            label: Text('Centre', style: TextStyle(fontSize: 12)),
            tooltip: 'Centre (Center)',
          ),
          ButtonSegment(
            value: CrossAxisAlignment.end,
            label: Text('Fin', style: TextStyle(fontSize: 12)),
            tooltip: 'Fin (End)',
          ),
          ButtonSegment(
            value: CrossAxisAlignment.stretch,
            label: Text('Étirer', style: TextStyle(fontSize: 12)),
            tooltip: 'Étirer (Stretch)',
          ),
        ],
        selected: {flow.crossAxisAlignment},
        onSelectionChanged: (selected) {
          if (selected.isNotEmpty) {
            onFlowChanged(flow.copyWith(crossAxisAlignment: selected.first));
          }
        },
      ),
    );
  }

  Container getSegmentedMainAlign() {
    return Container(
      key: ValueKey('$keyPrefix-main-alignment'),
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<MainAxisAlignment>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            segments: const [
              ButtonSegment(
                value: MainAxisAlignment.start,
                label: Text('Début', style: TextStyle(fontSize: 11)),
                tooltip: 'Début (Start)',
              ),
              ButtonSegment(
                value: MainAxisAlignment.center,
                label: Text('Centre', style: TextStyle(fontSize: 11)),
                tooltip: 'Centre (Center)',
              ),
              ButtonSegment(
                value: MainAxisAlignment.end,
                label: Text('Fin', style: TextStyle(fontSize: 11)),
                tooltip: 'Fin (End)',
              ),
            ],
            selected: {
              if (const [
                MainAxisAlignment.start,
                MainAxisAlignment.center,
                MainAxisAlignment.end,
              ].contains(flow.mainAxisAlignment))
                flow.mainAxisAlignment,
            },
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) {
                onFlowChanged(flow.copyWith(mainAxisAlignment: selected.first));
              }
            },
          ),
          const SizedBox(height: 6),
          SegmentedButton<MainAxisAlignment>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            segments: const [
              ButtonSegment(
                value: MainAxisAlignment.spaceBetween,
                label: Text('Espace entre', style: TextStyle(fontSize: 11)),
                tooltip: 'Espace entre (Space Between)',
              ),
              ButtonSegment(
                value: MainAxisAlignment.spaceAround,
                label: Text('Espace autour', style: TextStyle(fontSize: 11)),
                tooltip: 'Espace autour (Space Around)',
              ),
              ButtonSegment(
                value: MainAxisAlignment.spaceEvenly,
                label: Text('Espace uniforme', style: TextStyle(fontSize: 11)),
                tooltip: 'Espace uniforme (Space Evenly)',
              ),
            ],
            selected: {
              if (const [
                MainAxisAlignment.spaceBetween,
                MainAxisAlignment.spaceAround,
                MainAxisAlignment.spaceEvenly,
              ].contains(flow.mainAxisAlignment))
                flow.mainAxisAlignment,
            },
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) {
                onFlowChanged(flow.copyWith(mainAxisAlignment: selected.first));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _FlowSectionCard extends StatelessWidget {
  const _FlowSectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLowest,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}
