import 'package:material_ui/material_ui.dart';

import '../../../../models/super_table_config.dart';
import '../../components/super_table_editor.dart';
import 'add_form_common.dart';

double? _parse(String text) => parseAddFormDouble(text);

class TableAddForm extends StatefulWidget {
  const TableAddForm({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final SuperTableConfig draft;
  final ValueChanged<SuperTableConfig> onChanged;

  @override
  State<TableAddForm> createState() => _TableAddFormState();
}

class _TableAddFormState extends State<TableAddForm>
    with DraftAddFormStateMixin {
  Future<void> _more() => openAdvancedDraftEditor(
    () => showSuperTableEditor(context: context, config: widget.draft),
    widget.onChanged,
  );

  void _updateColumnCount(int count) {
    final clamped = count.clamp(1, 20);
    final current = widget.draft.columns;
    if (clamped == current.length) return;
    final next = <SuperTableColumnConfig>[
      for (var i = 0; i < clamped; i++)
        if (i < current.length)
          current[i]
        else
          SuperTableColumnConfig(
            id: 'col_$i',
            title: 'Colonne ${i + 1}',
          ),
    ];
    final freeze = widget.draft.colFreezeLeftCount.clamp(0, next.length);
    widget.onChanged(
      widget.draft.copyWith(
        columns: next,
        colFreezeLeftCount: freeze,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return buildRevisionSubtree(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('add-table-column-count'),
                  initialValue: '${draft.columns.length}',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Nombre de colonnes',
                  ),
                  onChanged: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed != null && parsed >= 1) {
                      _updateColumnCount(parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('add-table-freeze-left'),
                  initialValue: '${draft.colFreezeLeftCount}',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Colonnes figées à gauche',
                  ),
                  onChanged: (value) => widget.onChanged(
                    draft.copyWith(
                      colFreezeLeftCount: int.tryParse(value.trim()) ?? -1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('add-table-row-height'),
                  initialValue: '${draft.rowHeight}',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Hauteur ligne (px)',
                  ),
                  onChanged: (value) => widget.onChanged(
                    draft.copyWith(rowHeight: _parse(value) ?? -1),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('add-table-header-height'),
                  initialValue: '${draft.headerRowHeight}',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Hauteur en-tête (px)',
                  ),
                  onChanged: (value) => widget.onChanged(
                    draft.copyWith(headerRowHeight: _parse(value) ?? -1),
                  ),
                ),
              ),
            ],
          ),
          SwitchListTile(
            key: const ValueKey('add-table-show-header'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Afficher la ligne d’en-tête'),
            value: draft.showHeaderRow,
            onChanged: (value) =>
                widget.onChanged(draft.copyWith(showHeaderRow: value)),
          ),
          SwitchListTile(
            key: const ValueKey('add-table-show-bottom'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Afficher la ligne de pied figée'),
            value: draft.showBottomRow,
            onChanged: (value) =>
                widget.onChanged(draft.copyWith(showBottomRow: value)),
          ),
          SwitchListTile(
            key: const ValueKey('add-table-animate-selection-hover'),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Animer le déplacement de la sélection et du survol',
            ),
            value: draft.animateSelectionAndHover,
            onChanged: (value) => widget.onChanged(
              draft.copyWith(animateSelectionAndHover: value),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('add-table-more'),
              onPressed: _more,
              icon: const Icon(Icons.tune),
              label: const Text('Tous les réglages…'),
            ),
          ),
        ],
      ),
    );
  }
}
