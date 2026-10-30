/// Fenêtre de configuration d'un composant graphique [SuperChart].
///
/// Ouverte via le menu contextuel en mode édition (*Graphique*). Permet de
/// choisir :
/// * le type de graphique (`fl_chart` : Courbe, Barres, Camembert, Nuage de points, Radar) ;
/// * la liaison au tableau JSON d'un repository (`JsonTextBinding`) et le chemin du libellé ;
/// * une ou plusieurs séries de données (libellé, chemin de valeur Y, chemin secondaire X, couleur, style) ;
/// * les axes, la grille, les bornes min/max, la légende, les infobulles et la sélection synchronisée.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../models/json_syntax.dart';
import '../../../models/super_chart_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../repositories/repository_binding_fields.dart';

/// Palette de couleurs proposées pour les séries d'un graphique.
const List<Color> defaultChartSeriesPalette = [
  Color(0xFF3B82F6), // Bleu
  Color(0xFF10B981), // Émeraude
  Color(0xFFF59E0B), // Ambre
  Color(0xFFEF4444), // Rouge
  Color(0xFF8B5CF6), // Violet
  Color(0xFFEC4899), // Rose
  Color(0xFF06B6D4), // Cyan
  Color(0xFFF97316), // Orange
];

/// Formate l'infobulle de menu contextuel d'un [SuperChart].
String formatSuperChartTooltip({
  required String title,
  required SuperChartConfig config,
}) {
  final bindingText = config.binding == null
      ? 'Sans liaison (aperçu)'
      : config.binding!.repositoryId == null
      ? 'Hérité · ${config.binding!.path}'
      : config.binding!.path;
  final seriesNames = config.series
      .map(
        (s) => s.color != null
            ? '${s.label} (${JsonColor.toHex(s.color!)})'
            : s.label,
      )
      .join(', ');
  return '$title\n'
      'Type : ${config.kind.label}\n'
      'Source : $bindingText\n'
      'Séries (${config.series.length}) : $seriesNames';
}

/// Ouvre la boîte de dialogue d'édition pour [config].
Future<SuperChartConfig?> showSuperChartEditor({
  required BuildContext context,
  required SuperChartConfig config,
}) {
  final repositories = JsonRepositoryScope.maybeOf(context);
  final scope = JsonListScope.maybeOf(context);
  return runWithDimensionDelegate<SuperChartConfig>(
    context: context,
    runner: (initialTab, dimensionDelegate) =>
        showEditorDialog<SuperChartConfig>(
          context: context,
          target: context,
          builder: (_) => _SuperChartEditorDialog(
            initialTab: initialTab,
            dimensionDelegate: dimensionDelegate,
            config: config,
            repositories: repositories,
            scope: scope,
          ),
        ),
  );
}

class _SuperChartEditorDialog extends StatefulWidget {
  const _SuperChartEditorDialog({
    required this.initialTab,
    required this.dimensionDelegate,
    required this.config,
    required this.repositories,
    required this.scope,
  });

  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;
  final SuperChartConfig config;
  final JsonRepositoryStore? repositories;
  final JsonListScope? scope;

  @override
  State<_SuperChartEditorDialog> createState() =>
      _SuperChartEditorDialogState();
}

class _SuperChartEditorDialogState extends State<_SuperChartEditorDialog> {
  final _form = GlobalKey<FormState>();
  late SuperChartConfig _draft = widget.config;
  late final TextEditingController _labelPath = TextEditingController(
    text: widget.config.labelPath,
  );
  late final TextEditingController _xAxisTitle = TextEditingController(
    text: widget.config.xAxisTitle,
  );
  late final TextEditingController _yAxisTitle = TextEditingController(
    text: widget.config.yAxisTitle,
  );
  late final TextEditingController _minY = TextEditingController(
    text: _formatNullableNumber(widget.config.minY),
  );
  late final TextEditingController _maxY = TextEditingController(
    text: _formatNullableNumber(widget.config.maxY),
  );
  late final TextEditingController _pieCenterRadius = TextEditingController(
    text: _formatNumber(widget.config.pieCenterSpaceRadius),
  );
  late final TextEditingController _pieSectionsSpace = TextEditingController(
    text: _formatNumber(widget.config.pieSectionsSpace),
  );
  late final TextEditingController _emptyText = TextEditingController(
    text: widget.config.emptyText,
  );

  String? _error;
  bool _busy = false;

  static String _formatNumber(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  static String _formatNullableNumber(double? value) =>
      value == null ? '' : _formatNumber(value);

  @override
  void dispose() {
    _labelPath.dispose();
    _xAxisTitle.dispose();
    _yAxisTitle.dispose();
    _minY.dispose();
    _maxY.dispose();
    _pieCenterRadius.dispose();
    _pieSectionsSpace.dispose();
    _emptyText.dispose();
    super.dispose();
  }

  double? _parseOptionalDouble(String raw, String fieldLabel) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed.replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite) {
      throw FormatException('$fieldLabel invalide.');
    }
    return parsed;
  }

  double _parseRequiredDouble(String raw, String fieldLabel) {
    final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite) {
      throw FormatException('$fieldLabel invalide.');
    }
    return parsed;
  }

  SuperChartConfig _buildConfig() {
    final minY = _parseOptionalDouble(_minY.text, 'Borne minimale Y');
    final maxY = _parseOptionalDouble(_maxY.text, 'Borne maximale Y');
    final pieCenter = _parseRequiredDouble(
      _pieCenterRadius.text,
      'Rayon central du camembert',
    );
    final pieSpace = _parseRequiredDouble(
      _pieSectionsSpace.text,
      'Espacement des sections',
    );
    final result = _draft.copyWith(
      labelPath: _labelPath.text.trim(),
      xAxisTitle: _xAxisTitle.text.trim(),
      yAxisTitle: _yAxisTitle.text.trim(),
      minY: minY,
      clearMinY: minY == null,
      maxY: maxY,
      clearMaxY: maxY == null,
      pieCenterSpaceRadius: pieCenter,
      pieSectionsSpace: pieSpace,
      emptyText: _emptyText.text,
    );
    result.validate();
    return result;
  }

  Future<bool> _apply() async {
    if (!(_form.currentState?.validate() ?? true)) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = _buildConfig();
      final binding = config.binding;
      final scope = widget.scope;
      if (binding != null && !(scope?.placeholder ?? false)) {
        if (binding.path.trim().isEmpty) {
          throw const FormatException('Chemin de liaison requis.');
        }
        final store = widget.repositories;
        if (store == null) {
          throw const FormatException('Service de repositories indisponible.');
        }
        final resolved = JsonListScope.resolveSelected(
          binding,
          scope,
          store,
        ).binding;
        if (resolved != null) {
          await store.readArray(resolved.repositoryId!, resolved.path);
        }
      }
      if (mounted) Navigator.of(context).pop(config);
      return true;
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    } on FileSystemException {
      if (mounted) setState(() => _error = 'Impossible de lire le repository.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addSeries() {
    final existingIds = {for (final s in _draft.series) s.id};
    var index = _draft.series.length + 1;
    while (existingIds.contains('series-$index')) {
      index++;
    }
    final nextSeries = [
      ..._draft.series,
      SuperChartSeries(
        id: 'series-$index',
        label: 'Série $index',
        valuePath: 'value',
        color:
            defaultChartSeriesPalette[(index - 1) %
                defaultChartSeriesPalette.length],
      ),
    ];
    setState(() => _draft = _draft.copyWith(series: nextSeries));
  }

  void _updateSeries(int index, SuperChartSeries updated) {
    final next = [..._draft.series];
    next[index] = updated;
    setState(() => _draft = _draft.copyWith(series: next));
  }

  void _removeSeries(int index) {
    if (_draft.series.length <= 1) return;
    final next = [..._draft.series]..removeAt(index);
    setState(() => _draft = _draft.copyWith(series: next));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kind = _draft.kind;
    final hasCartesianAxes =
        kind == SuperChartKind.line ||
        kind == SuperChartKind.bar ||
        kind == SuperChartKind.scatter;

    return EditorTabbedAlertDialog(
      dialogKey: const ValueKey('super-chart-editor'),
      applyButtonKey: const ValueKey('super-chart-apply'),
      initialTab: widget.initialTab,
      dimensionDelegate: widget.dimensionDelegate,
      propertiesTitle: const EditorDialogHeader(
        label: 'Configurer le graphique',
      ),
      propertiesWidth: 540,
      busy: _busy,
      onApply: _apply,
      onCancel: () => Navigator.of(context).pop(),
      propertiesContentBuilder: (context) => Form(
        key: _form,
        child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                // 1. Type de graphique
                const Text(
                  'Type de graphique (fl_chart)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                SegmentedButton<SuperChartKind>(
                  key: const ValueKey('super-chart-kind'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    for (final item in SuperChartKind.values)
                      ButtonSegment<SuperChartKind>(
                        value: item,
                        tooltip: item.label,
                        icon: Flexible(
                          flex: 0,
                          child: Icon(
                            switch (item) {
                              SuperChartKind.line => Icons.show_chart,
                              SuperChartKind.bar => Icons.bar_chart,
                              SuperChartKind.pie => Icons.pie_chart_outline,
                              SuperChartKind.scatter =>
                                Icons.scatter_plot_outlined,
                              SuperChartKind.radar => Icons.radar,
                            },
                            size: 14,
                          ),
                        ),
                        label: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  selected: {_draft.kind},
                  onSelectionChanged: _busy
                      ? null
                      : (selected) {
                          if (selected.isNotEmpty) {
                            setState(
                              () => _draft = _draft.copyWith(
                                kind: selected.first,
                              ),
                            );
                          }
                        },
                ),

                // 2. Liaison au repository JSON
                RepositoryBindingFields(
                  keyPrefix: 'super-chart-binding',
                  binding: _draft.binding,
                  store: widget.repositories,
                  listScope: widget.scope,
                  pathHint: 'ventes ou clients[?].commandes',
                  helper:
                      'Tableau JSON dont chaque élément fournit un point / une entrée du graphique.',
                  onChanged: (binding) => setState(
                    () => _draft = _draft.copyWith(
                      binding: binding,
                      clearBinding: binding == null,
                    ),
                  ),
                ),

                // 3. Chemin du libellé / Axe X
                TextFormField(
                  key: const ValueKey('super-chart-label-path'),
                  controller: _labelPath,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Chemin du libellé / catégorie (axe X)',
                    hintText: 'mois, nom ou laisser vide pour l’index',
                    helperText:
                        'Clé relative dans chaque élément du tableau pour le titre X ou la tranche.',
                  ),
                ),

                const Divider(height: 8),

                // 4. Séries de données
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Séries de données (${_draft.series.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('super-chart-add-series'),
                      onPressed: _busy ? null : _addSeries,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Ajouter une série'),
                    ),
                  ],
                ),
                for (var i = 0; i < _draft.series.length; i++)
                  _SeriesEditorCard(
                    key: ValueKey('super-chart-series-${_draft.series[i].id}'),
                    index: i,
                    series: _draft.series[i],
                    chartKind: kind,
                    canRemove: _draft.series.length > 1 && !_busy,
                    enabled: !_busy,
                    onChanged: (updated) => _updateSeries(i, updated),
                    onRemove: () => _removeSeries(i),
                  ),

                const Divider(height: 8),

                // 5. Options spécifiques au type
                if (kind == SuperChartKind.bar)
                  SwitchListTile(
                    key: const ValueKey('super-chart-bar-stacked'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Empiler les séries (barres empilées)'),
                    subtitle: const Text(
                      'Cumule les valeurs Y des séries sur une seule barre par entrée.',
                    ),
                    value: _draft.barStacked,
                    onChanged: _busy
                        ? null
                        : (v) => setState(
                            () => _draft = _draft.copyWith(barStacked: v),
                          ),
                  ),

                if (kind == SuperChartKind.pie)
                  Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('super-chart-pie-center-radius'),
                          controller: _pieCenterRadius,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Rayon central (Donut)',
                            helperText: '0 = Camembert plein',
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('super-chart-pie-sections-space'),
                          controller: _pieSectionsSpace,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Espacement des parts',
                            helperText: 'En pixels (0–40)',
                          ),
                        ),
                      ),
                    ],
                  ),

                // 6. Axes, Grille et Bornes
                if (kind != SuperChartKind.pie)
                  SwitchListTile(
                    key: const ValueKey('super-chart-show-grid'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Afficher la grille'),
                    value: _draft.showGrid,
                    onChanged: _busy
                        ? null
                        : (v) => setState(
                            () => _draft = _draft.copyWith(showGrid: v),
                          ),
                  ),

                if (kind != SuperChartKind.pie)
                  SwitchListTile(
                    key: const ValueKey('super-chart-show-axis-labels'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Afficher les graduations et libellés'),
                    value: _draft.showAxisLabels,
                    onChanged: _busy
                        ? null
                        : (v) => setState(
                            () => _draft = _draft.copyWith(showAxisLabels: v),
                          ),
                  ),

                if (hasCartesianAxes) ...[
                  SwitchListTile(
                    key: const ValueKey('super-chart-show-axis-titles'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Afficher les titres des axes X / Y'),
                    value: _draft.showAxisTitles,
                    onChanged: _busy
                        ? null
                        : (v) => setState(
                            () => _draft = _draft.copyWith(showAxisTitles: v),
                          ),
                  ),
                  if (_draft.showAxisTitles)
                    Row(
                      spacing: 12,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('super-chart-x-axis-title'),
                            controller: _xAxisTitle,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Titre axe X',
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('super-chart-y-axis-title'),
                            controller: _yAxisTitle,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Titre axe Y',
                            ),
                          ),
                        ),
                      ],
                    ),
                  Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('super-chart-min-y'),
                          controller: _minY,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Min Y (optionnel)',
                            hintText: 'Auto',
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('super-chart-max-y'),
                          controller: _maxY,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Max Y (optionnel)',
                            hintText: 'Auto',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // 7. Légende, Infobulles & Sélection
                SwitchListTile(
                  key: const ValueKey('super-chart-show-legend'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Afficher la légende'),
                  value: _draft.showLegend,
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () => _draft = _draft.copyWith(showLegend: v),
                        ),
                ),
                SwitchListTile(
                  key: const ValueKey('super-chart-enable-tooltips'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activer les infobulles (tooltips)'),
                  value: _draft.enableTooltips,
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () => _draft = _draft.copyWith(enableTooltips: v),
                        ),
                ),
                SwitchListTile(
                  key: const ValueKey('super-chart-enable-selection'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Synchroniser la sélection avec le repository',
                  ),
                  subtitle: const Text(
                    'Un clic sur le graphique sélectionne la ligne dans JsonArrayBinding (maître / détail).',
                  ),
                  value: _draft.enableSelection,
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () => _draft = _draft.copyWith(enableSelection: v),
                        ),
                ),

                // 8. Aperçu & Texte vide
                SwitchListTile(
                  key: const ValueKey('super-chart-show-demo'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Afficher des données de démonstration sans liaison',
                  ),
                  value: _draft.showDemoWhenUnbound,
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () =>
                              _draft = _draft.copyWith(showDemoWhenUnbound: v),
                        ),
                ),
                TextFormField(
                  key: const ValueKey('super-chart-empty-text'),
                  controller: _emptyText,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Message quand le tableau est vide',
                  ),
                ),

                if (_error != null)
                  Text(
                    _error!,
                    key: const ValueKey('super-chart-error'),
                    style: TextStyle(color: colors.error),
                  ),
              ],
            ),
      ),
    );
  }
}

class _SeriesEditorCard extends StatefulWidget {
  const _SeriesEditorCard({
    required this.index,
    required this.series,
    required this.chartKind,
    required this.canRemove,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final SuperChartSeries series;
  final SuperChartKind chartKind;
  final bool canRemove;
  final bool enabled;
  final ValueChanged<SuperChartSeries> onChanged;
  final VoidCallback onRemove;

  @override
  State<_SeriesEditorCard> createState() => _SeriesEditorCardState();
}

class _SeriesEditorCardState extends State<_SeriesEditorCard> {
  late final TextEditingController _label = TextEditingController(
    text: widget.series.label,
  );
  late final TextEditingController _valuePath = TextEditingController(
    text: widget.series.valuePath,
  );
  late final TextEditingController _secondaryPath = TextEditingController(
    text: widget.series.secondaryValuePath,
  );
  late final TextEditingController _strokeWidth = TextEditingController(
    text: _SuperChartEditorDialogState._formatNumber(widget.series.strokeWidth),
  );
  late final TextEditingController _radius = TextEditingController(
    text: _SuperChartEditorDialogState._formatNumber(widget.series.radius),
  );

  @override
  void didUpdateWidget(covariant _SeriesEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series.label != widget.series.label &&
        _label.text != widget.series.label) {
      _label.text = widget.series.label;
    }
    if (oldWidget.series.valuePath != widget.series.valuePath &&
        _valuePath.text != widget.series.valuePath) {
      _valuePath.text = widget.series.valuePath;
    }
    if (oldWidget.series.secondaryValuePath !=
            widget.series.secondaryValuePath &&
        _secondaryPath.text != widget.series.secondaryValuePath) {
      _secondaryPath.text = widget.series.secondaryValuePath;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _valuePath.dispose();
    _secondaryPath.dispose();
    _strokeWidth.dispose();
    _radius.dispose();
    super.dispose();
  }

  void _emitNumbers() {
    final sw = double.tryParse(_strokeWidth.text.trim().replaceAll(',', '.'));
    final rad = double.tryParse(_radius.text.trim().replaceAll(',', '.'));
    widget.onChanged(
      widget.series.copyWith(
        label: _label.text.trim().isEmpty
            ? 'Série ${widget.index + 1}'
            : _label.text.trim(),
        valuePath: _valuePath.text.trim(),
        secondaryValuePath: _secondaryPath.text.trim(),
        strokeWidth:
            sw != null &&
                sw >= SuperChartSeries.minStrokeWidth &&
                sw <= SuperChartSeries.maxStrokeWidth
            ? sw
            : widget.series.strokeWidth,
        radius:
            rad != null &&
                rad >= SuperChartSeries.minRadius &&
                rad <= SuperChartSeries.maxRadius
            ? rad
            : widget.series.radius,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final series = widget.series;
    final isLine = widget.chartKind == SuperChartKind.line;
    final showSecondary =
        widget.chartKind == SuperChartKind.scatter ||
        widget.chartKind == SuperChartKind.line;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            children: [
              Text(
                'Série #${widget.index + 1}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              if (widget.canRemove)
                IconButton(
                  key: ValueKey('super-chart-series-remove-${ widget.index}'),
                  tooltip: 'Supprimer la série',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
            ],
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('super-chart-series-label-${widget.index}'),
                  controller: _label,
                  enabled: widget.enabled,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Nom de la série',
                  ),
                  onChanged: (_) => _emitNumbers(),
                ),
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('super-chart-series-path-${widget.index}'),
                  controller: _valuePath,
                  enabled: widget.enabled,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Chemin valeur Y',
                    hintText: 'ex: montant (vide = nombre direct)',
                  ),
                  onChanged: (_) => _emitNumbers(),
                ),
              ),
            ],
          ),
          if (showSecondary)
            TextFormField(
              key: ValueKey('super-chart-series-secondary-${widget.index}'),
              controller: _secondaryPath,
              enabled: widget.enabled,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Chemin valeur X numérique (optionnel)',
                hintText: 'ex: x ou age (vide = index 0, 1, 2…)',
              ),
              onChanged: (_) => _emitNumbers(),
            ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('super-chart-series-stroke-${widget.index}'),
                  controller: _strokeWidth,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Épaisseur du trait',
                  ),
                  onChanged: (_) => _emitNumbers(),
                ),
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('super-chart-series-radius-${widget.index}'),
                  controller: _radius,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: widget.chartKind == SuperChartKind.bar
                        ? 'Largeur des barres'
                        : 'Rayon des points',
                  ),
                  onChanged: (_) => _emitNumbers(),
                ),
              ),
            ],
          ),
          // Couleur de la série
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Couleur :', style: Theme.of(context).textTheme.bodySmall),
              ChoiceChip(
                label: const Text('Auto'),
                selected: series.color == null,
                onSelected: widget.enabled
                    ? (_) => widget.onChanged(series.copyWith(clearColor: true))
                    : null,
              ),
              for (final swatch in defaultChartSeriesPalette)
                InkWell(
                  onTap: widget.enabled
                      ? () => widget.onChanged(series.copyWith(color: swatch))
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: series.color == swatch
                            ? colors.onSurface
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (isLine)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  key: ValueKey('super-chart-series-curved-${widget.index}'),
                  label: const Text('Courbe lissée'),
                  selected: series.isCurved,
                  onSelected: widget.enabled
                      ? (v) => widget.onChanged(series.copyWith(isCurved: v))
                      : null,
                ),
                FilterChip(
                  key: ValueKey('super-chart-series-area-${widget.index}'),
                  label: const Text('Aire remplie'),
                  selected: series.belowBarArea,
                  onSelected: widget.enabled
                      ? (v) =>
                            widget.onChanged(series.copyWith(belowBarArea: v))
                      : null,
                ),
                FilterChip(
                  key: ValueKey('super-chart-series-dots-${widget.index}'),
                  label: const Text('Points visibles'),
                  selected: series.showDots,
                  onSelected: widget.enabled
                      ? (v) => widget.onChanged(series.copyWith(showDots: v))
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
