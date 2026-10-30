import 'package:material_ui/material_ui.dart';

import '../../../../models/super_list_view_config.dart';
import '../../components/super_list_view_editor.dart';

double? _parse(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

class ListViewAddForm extends StatefulWidget {
  const ListViewAddForm({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final SuperListViewConfig draft;
  final ValueChanged<SuperListViewConfig> onChanged;

  @override
  State<ListViewAddForm> createState() => _ListViewAddFormState();
}

class _ListViewAddFormState extends State<ListViewAddForm> {
  int _revision = 0;

  Future<void> _more() async {
    final result = await showSuperListViewEditor(
      context: context,
      config: widget.draft,
    );
    if (result == null || !mounted) return;
    setState(() => _revision++);
    widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final draft = widget.draft;

    Card sectionCard({required String title, required Widget child}) => Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child,
          ],
        ),
      ),
    );

    return KeyedSubtree(
      key: ValueKey(_revision),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            sectionCard(
              title: 'Disposition & Dimensions',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  SegmentedButton<String>(
                    key: const ValueKey('add-list-axis'),
                    segments: const [
                      ButtonSegment(
                        value: 'vertical',
                        tooltip: 'Verticale',
                        label: Text('Verticale'),
                        icon: Icon(Icons.view_agenda_outlined),
                      ),
                      ButtonSegment(
                        value: 'horizontal',
                        tooltip: 'Horizontale',
                        label: Text('Horizontale'),
                        icon: Icon(Icons.view_week_outlined),
                      ),
                      ButtonSegment(
                        value: 'wrap',
                        tooltip: 'Wrap',
                        label: Text('Wrap'),
                        icon: Icon(Icons.wrap_text),
                      ),
                    ],
                    selected: {draft.wrap ? 'wrap' : draft.axis.name},
                    onSelectionChanged: (value) {
                      final selected = value.single;
                      if (selected == 'wrap') {
                        widget.onChanged(draft.copyWith(wrap: true));
                      } else {
                        widget.onChanged(
                          draft.copyWith(
                            wrap: false,
                            axis: selected == 'vertical'
                                ? Axis.vertical
                                : Axis.horizontal,
                          ),
                        );
                      }
                    },
                  ),
                  if (!draft.wrap)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('add-list-extent'),
                            initialValue: '${draft.itemExtent}',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Taille des items',
                            ),
                            onChanged: (value) => widget.onChanged(
                              draft.copyWith(itemExtent: _parse(value) ?? -1),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('add-list-spacing'),
                            initialValue: '${draft.spacing}',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Espacement',
                            ),
                            onChanged: (value) => widget.onChanged(
                              draft.copyWith(spacing: _parse(value) ?? -1),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('add-list-item-width'),
                            initialValue: '${draft.itemWidth}',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Largeur des items',
                            ),
                            onChanged: (value) => widget.onChanged(
                              draft.copyWith(itemWidth: _parse(value) ?? -1),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('add-list-extent'),
                            initialValue: '${draft.itemExtent}',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Taille des items',
                            ),
                            onChanged: (value) => widget.onChanged(
                              draft.copyWith(itemExtent: _parse(value) ?? -1),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('add-list-spacing'),
                            initialValue: '${draft.spacing}',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Espacement',
                            ),
                            onChanged: (value) => widget.onChanged(
                              draft.copyWith(spacing: _parse(value) ?? -1),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            sectionCard(
              title: 'Actions interactives',
              child: Column(
                children: [
                  SwitchListTile(
                    key: const ValueKey('add-list-allow-add'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.add_circle_outline),
                    title: const Text('Bouton Ajouter'),
                    subtitle: const Text('Permet d’ajouter des éléments'),
                    value: draft.allowAdd,
                    onChanged: (value) =>
                        widget.onChanged(draft.copyWith(allowAdd: value)),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    key: const ValueKey('add-list-allow-remove'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.delete_outline),
                    title: const Text('Bouton Supprimer'),
                    subtitle: const Text('Permet de retirer des éléments'),
                    value: draft.allowRemove,
                    onChanged: (value) =>
                        widget.onChanged(draft.copyWith(allowRemove: value)),
                  ),
                ],
              ),
            ),
            sectionCard(
              title: 'Contenu & Messages',
              child: TextFormField(
                key: const ValueKey('add-list-empty'),
                initialValue: draft.emptyText,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.inbox_outlined),
                  labelText: 'Message si aucun élément',
                ),
                onChanged: (value) =>
                    widget.onChanged(draft.copyWith(emptyText: value)),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('add-list-more'),
                onPressed: _more,
                icon: const Icon(Icons.tune),
                label: const Text('Plus d’options…'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
