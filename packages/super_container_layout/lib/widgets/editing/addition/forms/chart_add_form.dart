import 'package:material_ui/material_ui.dart';

import '../../../../models/super_chart_config.dart';
import '../../components/super_chart_editor.dart';
import 'add_form_common.dart';

class ChartAddForm extends StatefulWidget {
  const ChartAddForm({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final SuperChartConfig draft;
  final ValueChanged<SuperChartConfig> onChanged;

  @override
  State<ChartAddForm> createState() => _ChartAddFormState();
}

class _ChartAddFormState extends State<ChartAddForm>
    with DraftAddFormStateMixin {
  Future<void> _more() => openAdvancedDraftEditor(
    () => showSuperChartEditor(context: context, config: widget.draft),
    widget.onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final primarySeries = draft.series.first;

    Widget sectionCard({required String title, required Widget child}) =>
        AddFormSectionCard(title: title, child: child);

    return buildRevisionSubtree(
      SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            sectionCard(
              title: 'Type de graphique',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  const Text(
                    'Représentation (fl_chart)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  SegmentedButton<SuperChartKind>(
                    key: const ValueKey('add-chart-kind'),
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
                    selected: {draft.kind},
                    onSelectionChanged: (selected) {
                      if (selected.isNotEmpty) {
                        widget.onChanged(draft.copyWith(kind: selected.first));
                      }
                    },
                  ),
                ],
              ),
            ),
            sectionCard(
              title: 'Extraction des données',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  TextFormField(
                    key: const ValueKey('add-chart-label-path'),
                    initialValue: draft.labelPath,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Chemin du libellé / axe X',
                      hintText: 'ex: mois, nom',
                    ),
                    onChanged: (value) =>
                        widget.onChanged(draft.copyWith(labelPath: value.trim())),
                  ),
                  Row(
                    spacing: 10,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('add-chart-series-label'),
                          initialValue: primarySeries.label,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Nom de la 1re série',
                          ),
                          onChanged: (value) {
                            final next = [...draft.series];
                            next[0] = primarySeries.copyWith(
                              label: value.trim().isEmpty
                                  ? 'Série 1'
                                  : value.trim(),
                            );
                            widget.onChanged(draft.copyWith(series: next));
                          },
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('add-chart-series-path'),
                          initialValue: primarySeries.valuePath,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Chemin valeur Y',
                            hintText: 'ex: montant',
                          ),
                          onChanged: (value) {
                            final next = [...draft.series];
                            next[0] = primarySeries.copyWith(
                              valuePath: value.trim(),
                            );
                            widget.onChanged(draft.copyWith(series: next));
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            sectionCard(
              title: 'Affichage & Interaction',
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilterChip(
                    key: const ValueKey('add-chart-show-legend'),
                    label: const Text('Légende'),
                    selected: draft.showLegend,
                    onSelected: (v) =>
                        widget.onChanged(draft.copyWith(showLegend: v)),
                  ),
                  FilterChip(
                    key: const ValueKey('add-chart-show-grid'),
                    label: const Text('Grille'),
                    selected: draft.showGrid,
                    onSelected: (v) =>
                        widget.onChanged(draft.copyWith(showGrid: v)),
                  ),
                  FilterChip(
                    key: const ValueKey('add-chart-enable-tooltips'),
                    label: const Text('Infobulles'),
                    selected: draft.enableTooltips,
                    onSelected: (v) =>
                        widget.onChanged(draft.copyWith(enableTooltips: v)),
                  ),
                  FilterChip(
                    key: const ValueKey('add-chart-enable-selection'),
                    label: const Text('Sélection synchronisée'),
                    selected: draft.enableSelection,
                    onSelected: (v) =>
                        widget.onChanged(draft.copyWith(enableSelection: v)),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: const ValueKey('add-chart-more'),
                onPressed: _more,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Configuration avancée (séries, axes…)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
