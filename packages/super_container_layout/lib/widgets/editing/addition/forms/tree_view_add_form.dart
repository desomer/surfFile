import 'package:material_ui/material_ui.dart';

import '../../../../models/super_tree_view_config.dart';
import '../../components/super_tree_view_editor.dart';

double? _parse(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

class TreeViewAddForm extends StatefulWidget {
  const TreeViewAddForm({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final SuperTreeViewConfig draft;
  final ValueChanged<SuperTreeViewConfig> onChanged;

  @override
  State<TreeViewAddForm> createState() => _TreeViewAddFormState();
}

class _TreeViewAddFormState extends State<TreeViewAddForm> {
  int _revision = 0;

  Future<void> _more() async {
    final result = await showSuperTreeViewEditor(
      context: context,
      config: widget.draft,
    );
    if (result == null || !mounted) return;
    setState(() => _revision++);
    widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return KeyedSubtree(
      key: ValueKey(_revision),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          TextFormField(
            key: const ValueKey('add-tree-children-key'),
            initialValue: draft.childrenKey,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Clé des nœuds enfants',
              hintText: 'children',
            ),
            onChanged: (value) => widget.onChanged(
              draft.copyWith(childrenKey: value.trim()),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('add-tree-header-size'),
                  initialValue: '${draft.headerSize}',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Largeur Header (px)',
                  ),
                  onChanged: (value) => widget.onChanged(
                    draft.copyWith(headerSize: _parse(value) ?? -1),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('add-tree-row-height'),
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
            ],
          ),
          SwitchListTile(
            key: const ValueKey('add-tree-initially-expanded'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Déplier les nœuds par défaut'),
            value: draft.initiallyExpanded,
            onChanged: (value) =>
                widget.onChanged(draft.copyWith(initiallyExpanded: value)),
          ),
          SwitchListTile(
            key: const ValueKey('add-tree-show-connectors'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Afficher les traits de connexion'),
            value: draft.showConnectors,
            onChanged: (value) =>
                widget.onChanged(draft.copyWith(showConnectors: value)),
          ),
          SwitchListTile(
            key: const ValueKey('add-tree-animate-selection-hover'),
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
              key: const ValueKey('add-tree-more'),
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
