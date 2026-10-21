import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_text_config.dart';
import '../../../theme/container_style.dart';
import '../../super_layout/super_layout.dart';
import 'component_add_wizard.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../components/super_list_view_editor.dart';
import '../components/super_text_editor.dart';

export '../repositories/repository_binding_fields.dart'
    show RepositoryBindingFields;

/// Add wizard settings of a `SuperText`, written to `Registry.textController`.
ComponentAddConfigurator<SuperTextConfig> superTextAddConfigurator(
  List<String> availableFontFamilies,
) => ComponentAddConfigurator<SuperTextConfig>(
  initial: (_) => const SuperTextConfig(),
  builder: (context, draft, onChanged) => _SuperTextAddForm(
    draft: draft,
    onChanged: onChanged,
    availableFontFamilies: availableFontFamilies,
  ),
  validate: (draft) {
    if (draft.binding?.path.trim().isEmpty ?? false) {
      return 'Chemin de liaison requis.';
    }
    try {
      draft.validate();
      return null;
    } on FormatException catch (error) {
      return error.message;
    } on Object {
      return 'Configuration du texte invalide.';
    }
  },
  summary: (draft) => [
    ('Mode', draft.mode == SuperTextMode.input ? 'Saisie' : 'Affichage'),
    if (draft.initialText.isNotEmpty) ('Texte initial', draft.initialText),
    if (draft.label.isNotEmpty) ('Libellé du champ', draft.label),
    if (draft.placeholder.isNotEmpty) ('Texte indicatif', draft.placeholder),
    if (draft.fontSize != null) ('Taille du texte', '${draft.fontSize}'),
    ('Alignement', _alignLabel(draft.textAlign)),
    ('Liaison', _bindingLabel(draft.binding)),
  ],
  apply: (registry, id, draft) => registry.textController(id).value = draft,
  readBinding: (draft) => draft.binding,
  writeBinding: (draft, binding) =>
      draft.copyWith(binding: binding, clearBinding: binding == null),
  bindingKeyPrefix: 'add-text',
  bindingPathHint: 'client.nom ou clients[?].nom',
  bindingHelp: 'Le repository fournit la valeur (liaison bidirectionnelle).',
);

/// Add wizard settings of a `SuperListView`, written to `Registry.listController`.
final listViewAddConfigurator = ComponentAddConfigurator<SuperListViewConfig>(
  initial: (_) => const SuperListViewConfig(),
  builder: (context, draft, onChanged) =>
      _ListViewAddForm(draft: draft, onChanged: onChanged),
  validate: (draft) {
    if (draft.binding?.path.trim().isEmpty ?? false) {
      return 'Chemin de liaison requis.';
    }
    try {
      draft.validate();
      return null;
    } on FormatException catch (error) {
      return error.message;
    } on Object {
      return 'Configuration de la liste invalide.';
    }
  },
  summary: (draft) => [
    ('Orientation', draft.axis == Axis.vertical ? 'Verticale' : 'Horizontale'),
    ('Taille des lignes', '${draft.itemExtent}'),
    ('Espacement', '${draft.spacing}'),
    (
      'Ajout / suppression',
      '${_yes(draft.allowAdd)} / ${_yes(draft.allowRemove)}',
    ),
    ('Liste vide', draft.emptyText),
    ('Liaison', _bindingLabel(draft.binding)),
  ],
  apply: (registry, id, draft) => registry.listController(id).value = draft,
  readBinding: (draft) => draft.binding,
  writeBinding: (draft, binding) =>
      draft.copyWith(binding: binding, clearBinding: binding == null),
  bindingKeyPrefix: 'add-list',
  bindingPathHint: 'clients ou clients[?].commandes',
  bindingHelp: 'Chaque élément du tableau devient une ligne de la liste.',
);

/// Add wizard settings of a nested `SuperLayout`.
final layoutAddConfigurator = ComponentAddConfigurator<SuperLayoutConfig>(
  initial: (_) => const SuperLayoutConfig(),
  builder: (context, draft, onChanged) =>
      SuperLayoutEditor(config: draft, onChanged: onChanged),
  summary: (draft) {
    final sides = [
      for (final zone in [
        SuperLayoutZone.north,
        SuperLayoutZone.south,
        SuperLayoutZone.west,
        SuperLayoutZone.east,
      ])
        if (draft.hasSide(zone)) zone.label,
    ];
    return [
      (
        'Disposition',
        draft.positioning == SuperLayoutPositioning.grid ? 'Grille' : 'Zones',
      ),
      ('Côtés', sides.isEmpty ? 'Centre seul' : sides.join(', ')),
    ];
  },
  apply: (registry, id, draft) => registry.layoutController(id).value = draft,
);

/// Add wizard settings of a `NewContainer` style.
final containerAddConfigurator = ComponentAddConfigurator<ContainerStyle>(
  initial: (_) => const ContainerStyle(),
  builder: (context, draft, onChanged) =>
      _ContainerAddForm(draft: draft, onChanged: onChanged),
  summary: (draft) => [
    (
      'Couleur',
      draft.color == null
          ? 'Par défaut'
          : '#${draft.color!.toARGB32().toRadixString(16).padLeft(8, '0')}',
    ),
    ('Rayon', draft.radius.toStringAsFixed(0)),
    ('Bordure', draft.borderWidth.toStringAsFixed(0)),
    ('Marge intérieure', draft.padding.toStringAsFixed(0)),
    ('Marge extérieure', draft.margin.toStringAsFixed(0)),
    ('Élévation', draft.elevation.toStringAsFixed(0)),
  ],
  apply: (registry, id, draft) => registry.styleController(id).value = draft,
);

String _yes(bool value) => value ? 'oui' : 'non';

String _bindingLabel(JsonTextBinding? binding) => binding == null
    ? 'Aucune'
    : '${binding.repositoryId ?? 'Repository hérité'} · ${binding.path}';

String _alignLabel(TextAlign align) => switch (align) {
  TextAlign.center => 'Centré',
  TextAlign.end || TextAlign.right => 'Fin',
  TextAlign.justify => 'Justifié',
  _ => 'Début',
};

double? _parse(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

class _SuperTextAddForm extends StatefulWidget {
  const _SuperTextAddForm({
    required this.draft,
    required this.onChanged,
    required this.availableFontFamilies,
  });

  final SuperTextConfig draft;
  final ValueChanged<SuperTextConfig> onChanged;
  final List<String> availableFontFamilies;

  @override
  State<_SuperTextAddForm> createState() => _SuperTextAddFormState();
}

class _SuperTextAddFormState extends State<_SuperTextAddForm> {
  /// Recreates the text fields after the full editor changed the draft.
  int _revision = 0;

  Future<void> _more() async {
    final result = await showSuperTextEditor(
      context: context,
      config: widget.draft,
      availableFontFamilies: widget.availableFontFamilies,
    );
    if (result == null || !mounted) return;
    setState(() => _revision++);
    widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final input = draft.mode == SuperTextMode.input;
    return KeyedSubtree(
      key: ValueKey(_revision),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<SuperTextMode>(
            key: const ValueKey('add-text-mode'),
            segments: const [
              ButtonSegment(
                value: SuperTextMode.display,
                label: Text('Affichage'),
              ),
              ButtonSegment(value: SuperTextMode.input, label: Text('Saisie')),
            ],
            selected: {draft.mode},
            onSelectionChanged: (value) =>
                widget.onChanged(draft.copyWith(mode: value.single)),
          ),
          if (!draft.obscureText)
            TextFormField(
              key: const ValueKey('add-text-initial'),
              initialValue: draft.initialText,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Texte initial',
              ),
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(initialText: value)),
            ),
          if (input) ...[
            TextFormField(
              key: const ValueKey('add-text-label'),
              initialValue: draft.label,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Libellé du champ',
              ),
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(label: value)),
            ),
            TextFormField(
              key: const ValueKey('add-text-placeholder'),
              initialValue: draft.placeholder,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Texte indicatif',
              ),
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(placeholder: value)),
            ),
          ],
          TextFormField(
            key: const ValueKey('add-text-font-size'),
            initialValue: draft.fontSize?.toString() ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Taille du texte (vide : héritée)',
            ),
            onChanged: (value) {
              final size = _parse(value);
              widget.onChanged(
                value.trim().isEmpty
                    ? draft.copyWith(inheritFontSize: true)
                    : draft.copyWith(fontSize: size ?? -1),
              );
            },
          ),
          const SizedBox(height: 8),
          SegmentedButton<TextAlign>(
            key: const ValueKey('add-text-align'),
            segments: const [
              ButtonSegment(
                value: TextAlign.start,
                icon: Icon(Icons.format_align_left),
              ),
              ButtonSegment(
                value: TextAlign.center,
                icon: Icon(Icons.format_align_center),
              ),
              ButtonSegment(
                value: TextAlign.end,
                icon: Icon(Icons.format_align_right),
              ),
            ],
            selected: {
              switch (draft.textAlign) {
                TextAlign.center => TextAlign.center,
                TextAlign.end || TextAlign.right => TextAlign.end,
                _ => TextAlign.start,
              },
            },
            onSelectionChanged: (value) =>
                widget.onChanged(draft.copyWith(textAlign: value.single)),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('add-text-more'),
              onPressed: _more,
              icon: const Icon(Icons.tune),
              label: const Text('Plus d’options…'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListViewAddForm extends StatefulWidget {
  const _ListViewAddForm({required this.draft, required this.onChanged});

  final SuperListViewConfig draft;
  final ValueChanged<SuperListViewConfig> onChanged;

  @override
  State<_ListViewAddForm> createState() => _ListViewAddFormState();
}

class _ListViewAddFormState extends State<_ListViewAddForm> {
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
    final draft = widget.draft;
    return KeyedSubtree(
      key: ValueKey(_revision),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<Axis>(
            key: const ValueKey('add-list-axis'),
            segments: const [
              ButtonSegment(value: Axis.vertical, label: Text('Verticale')),
              ButtonSegment(value: Axis.horizontal, label: Text('Horizontale')),
            ],
            selected: {draft.axis},
            onSelectionChanged: (value) =>
                widget.onChanged(draft.copyWith(axis: value.single)),
          ),
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
                    labelText: 'Taille des lignes',
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
          ),
          SwitchListTile(
            key: const ValueKey('add-list-allow-add'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Bouton Ajouter'),
            value: draft.allowAdd,
            onChanged: (value) =>
                widget.onChanged(draft.copyWith(allowAdd: value)),
          ),
          SwitchListTile(
            key: const ValueKey('add-list-allow-remove'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Bouton Supprimer'),
            value: draft.allowRemove,
            onChanged: (value) =>
                widget.onChanged(draft.copyWith(allowRemove: value)),
          ),
          TextFormField(
            key: const ValueKey('add-list-empty'),
            initialValue: draft.emptyText,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Message de liste vide',
            ),
            onChanged: (value) =>
                widget.onChanged(draft.copyWith(emptyText: value)),
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
    );
  }
}

class _ContainerAddForm extends StatelessWidget {
  const _ContainerAddForm({required this.draft, required this.onChanged});

  final ContainerStyle draft;
  final ValueChanged<ContainerStyle> onChanged;

  Widget _slider(
    String key,
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
  ) => Row(
    children: [
      SizedBox(width: 130, child: Text(label)),
      Expanded(
        child: Slider(
          key: ValueKey('add-container-$key'),
          value: value.clamp(0, max).toDouble(),
          max: max,
          divisions: max.round(),
          label: value.toStringAsFixed(0),
          onChanged: onChanged,
        ),
      ),
      SizedBox(width: 32, child: Text(value.toStringAsFixed(0))),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      styleColorTile(
        'Couleur de fond',
        draft.color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        (color) => onChanged(draft.copyWith(color: color)),
        key: const ValueKey('add-container-color'),
        dense: true,
      ),
      _slider(
        'radius',
        'Rayon',
        draft.radius,
        48,
        (value) => onChanged(draft.copyWith(radius: value)),
      ),
      _slider(
        'border',
        'Bordure',
        draft.borderWidth,
        8,
        (value) => onChanged(draft.copyWith(borderWidth: value)),
      ),
      _slider(
        'padding',
        'Marge intérieure',
        draft.padding,
        ContainerStyle.maxSpacing,
        (value) => onChanged(draft.copyWith(padding: value)),
      ),
      _slider(
        'margin',
        'Marge extérieure',
        draft.margin,
        ContainerStyle.maxSpacing,
        (value) => onChanged(draft.copyWith(margin: value)),
      ),
      _slider(
        'elevation',
        'Élévation',
        draft.elevation,
        24,
        (value) => onChanged(draft.copyWith(elevation: value)),
      ),
    ],
  );
}
