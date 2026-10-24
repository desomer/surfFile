import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_value_config.dart';
import '../../../models/super_action_config.dart';
import '../../../theme/container_style.dart';
import '../../super_layout/super_layout.dart';
import 'component_add_wizard.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../components/super_list_view_editor.dart';
import '../components/super_value_editor.dart';
import '../components/super_action_editor.dart';

export '../repositories/repository_binding_fields.dart'
    show RepositoryBindingFields;

/// Add wizard settings of a `SuperValue`, written to `Registry.valueController`.
ComponentAddConfigurator<SuperValueConfig> superValueAddConfigurator(
  List<String> availableFontFamilies,
) => ComponentAddConfigurator<SuperValueConfig>(
  initial: (_) => const SuperValueConfig(),
  builder: (context, draft, onChanged) => _SuperValueAddForm(
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
      return 'Configuration de la valeur invalide.';
    }
  },
  summary: (draft) => [
    if (draft.kind != SuperValueKind.text)
      (
        'Type',
        draft.kind == SuperValueKind.checkbox ? 'Checkbox' : 'Switch',
      ),
    ('Mode', draft.mode == SuperValueMode.input ? 'Saisie' : 'Affichage'),
    if (!draft.kind.isBoolean && draft.initialText.isNotEmpty)
      ('Texte initial', draft.initialText),
    if (draft.kind.isBoolean) ('Valeur initiale', _yes(draft.initialBool)),
    if (draft.label.isNotEmpty) ('Libellé du champ', draft.label),
    if (!draft.kind.isBoolean && draft.placeholder.isNotEmpty)
      ('Texte indicatif', draft.placeholder),
    if (draft.fontSize != null) ('Taille du texte', '${draft.fontSize}'),
    ('Alignement', _alignLabel(draft.textAlign)),
    ('Liaison', _bindingLabel(draft.binding)),
  ],
  apply: (registry, id, draft) => registry.valueController(id).value = draft,
  readBinding: (draft) => draft.binding,
  writeBinding: (draft, binding) =>
      draft.copyWith(binding: binding, clearBinding: binding == null),
  bindingKeyPrefix: 'add-value',
  bindingPathHint: 'client.nom ou clients[?].nom',
  bindingHelp: 'Le repository fournit la valeur (liaison bidirectionnelle).',
);

/// Add wizard settings of a `SuperAction`, written to `Registry.actionController`.
ComponentAddConfigurator<SuperActionConfig> superActionAddConfigurator(
  List<String> availableFontFamilies,
) => ComponentAddConfigurator<SuperActionConfig>(
  initial: (_) => const SuperActionConfig(),
  builder: (context, draft, onChanged) => _SuperActionAddForm(
    draft: draft,
    onChanged: onChanged,
    availableFontFamilies: availableFontFamilies,
  ),
  validate: (draft) {
    try {
      draft.validate();
      return null;
    } on FormatException catch (error) {
      return error.message;
    } on Object {
      return 'Configuration de l’action invalide.';
    }
  },
  summary: (draft) => [
    (
      'Type',
      switch (draft.kind) {
        SuperActionKind.text => 'Texte',
        SuperActionKind.icon => 'Icône',
        SuperActionKind.textAndIcon => 'Texte et icône',
      },
    ),
    ('Variante', draft.variant.name),
    if (draft.kind.hasText && draft.label.isNotEmpty) ('Libellé', draft.label),
    if (draft.kind.hasIcon) ('Icône', SuperActionIcons.labelOf(draft.icon)),
    if (draft.fontSize != null) ('Taille du texte', '${draft.fontSize}'),
    if (draft.iconSize != null) ('Taille de l’icône', '${draft.iconSize}'),
    ('Alignement', _alignLabel(draft.textAlign)),
  ],
  apply: (registry, id, draft) => registry.actionController(id).value = draft,
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

class _SuperValueAddForm extends StatefulWidget {
  const _SuperValueAddForm({
    required this.draft,
    required this.onChanged,
    required this.availableFontFamilies,
  });

  final SuperValueConfig draft;
  final ValueChanged<SuperValueConfig> onChanged;
  final List<String> availableFontFamilies;

  @override
  State<_SuperValueAddForm> createState() => _SuperValueAddFormState();
}

class _SuperValueAddFormState extends State<_SuperValueAddForm> {
  /// Recreates the text fields after the full editor changed the draft.
  int _revision = 0;

  Future<void> _more() async {
    final result = await showSuperValueEditor(
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
    final input = draft.mode == SuperValueMode.input;
    return KeyedSubtree(
      key: ValueKey(_revision),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<SuperValueKind>(
            key: const ValueKey('add-value-kind'),
            segments: const [
              ButtonSegment(value: SuperValueKind.text, label: Text('Texte')),
              ButtonSegment(
                value: SuperValueKind.checkbox,
                label: Text('Checkbox'),
              ),
              ButtonSegment(
                value: SuperValueKind.switchControl,
                label: Text('Switch'),
              ),
            ],
            selected: {draft.kind},
            onSelectionChanged: (value) {
              final kind = value.single;
              widget.onChanged(
                draft.copyWith(
                  kind: kind,
                  obscureText: kind.isBoolean ? false : draft.obscureText,
                  minLines: kind.isBoolean ? 1 : draft.minLines,
                  maxLines: kind.isBoolean ? 1 : draft.maxLines,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          SegmentedButton<SuperValueMode>(
            key: const ValueKey('add-value-mode'),
            segments: const [
              ButtonSegment(
                value: SuperValueMode.display,
                label: Text('Affichage'),
              ),
              ButtonSegment(value: SuperValueMode.input, label: Text('Saisie')),
            ],
            selected: {draft.mode},
            onSelectionChanged: (value) =>
                widget.onChanged(draft.copyWith(mode: value.single)),
          ),
          if (draft.kind.isBoolean)
            SwitchListTile(
              key: const ValueKey('add-value-initial-bool'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Valeur initiale'),
              value: draft.initialBool,
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(initialBool: value)),
            )
          else if (!draft.obscureText)
            TextFormField(
              key: const ValueKey('add-value-initial'),
              initialValue: draft.initialText,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Texte initial',
              ),
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(initialText: value)),
            ),
          if (input || draft.kind.isBoolean) ...[
            TextFormField(
              key: const ValueKey('add-value-label'),
              initialValue: draft.label,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Libellé du champ',
              ),
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(label: value)),
            ),
            if (!draft.kind.isBoolean)
              TextFormField(
                key: const ValueKey('add-value-placeholder'),
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
            key: const ValueKey('add-value-font-size'),
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
            key: const ValueKey('add-value-align'),
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
              key: const ValueKey('add-value-more'),
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

class _SuperActionAddForm extends StatefulWidget {
  const _SuperActionAddForm({
    required this.draft,
    required this.onChanged,
    required this.availableFontFamilies,
  });

  final SuperActionConfig draft;
  final ValueChanged<SuperActionConfig> onChanged;
  final List<String> availableFontFamilies;

  @override
  State<_SuperActionAddForm> createState() => _SuperActionAddFormState();
}

class _SuperActionAddFormState extends State<_SuperActionAddForm> {
  int _revision = 0;

  Future<void> _more() async {
    final result = await showSuperActionEditor(
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
    return KeyedSubtree(
      key: ValueKey(_revision),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<SuperActionKind>(
            key: const ValueKey('add-action-kind'),
            segments: const [
              ButtonSegment(value: SuperActionKind.text, label: Text('Texte')),
              ButtonSegment(value: SuperActionKind.icon, label: Text('Icône')),
              ButtonSegment(
                value: SuperActionKind.textAndIcon,
                label: Text('Texte + Icône'),
              ),
            ],
            selected: {draft.kind},
            onSelectionChanged: (value) =>
                widget.onChanged(draft.copyWith(kind: value.single)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<SuperActionVariant>(
            key: const ValueKey('add-action-variant'),
            isExpanded: true,
            initialValue: draft.variant,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Style / variante du bouton',
            ),
            items: const [
              DropdownMenuItem(
                value: SuperActionVariant.filled,
                child: Text('Filled (plein)'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.tonal,
                child: Text('Tonal (secondaire)'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.elevated,
                child: Text('Elevated (élevé)'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.outlined,
                child: Text('Outlined (contour)'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.text,
                child: Text('Text (sans fond)'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.icon,
                child: Text('Icon Button'),
              ),
              DropdownMenuItem(
                value: SuperActionVariant.surface,
                child: Text('Surface personnalisée'),
              ),
            ],
            onChanged: (variant) {
              if (variant != null) {
                widget.onChanged(draft.copyWith(variant: variant));
              }
            },
          ),
          if (draft.kind.hasText)
            TextFormField(
              key: const ValueKey('add-action-label'),
              initialValue: draft.label,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Libellé du bouton',
              ),
              onChanged: (value) =>
                  widget.onChanged(draft.copyWith(label: value)),
            ),
          if (draft.kind.hasIcon)
            DropdownButtonFormField<String>(
              key: const ValueKey('add-action-icon'),
              isExpanded: true,
              initialValue: SuperActionIcons.isKnown(draft.icon)
                  ? draft.icon
                  : 'touch_app',
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Icône',
              ),
              items: [
                for (final entry in SuperActionIcons.catalog.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(entry.value.icon, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            entry.value.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (icon) {
                if (icon != null) {
                  widget.onChanged(draft.copyWith(icon: icon));
                }
              },
            ),
          TextFormField(
            key: const ValueKey('add-action-font-size'),
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
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('add-action-more'),
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
