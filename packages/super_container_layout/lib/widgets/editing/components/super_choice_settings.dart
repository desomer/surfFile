/// Panneau de configuration d'un composant de choix [SuperChoice] ([SuperChoiceConfig]).
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/super_choice_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../icons/material_icon_picker.dart';
import '../repositories/repository_binding_fields.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../styles/style_editor_panel.dart';
import 'shared/editor_color_fields.dart';
import 'shared/editor_segmented_field.dart';

/// Panneau de réglages dédié à [SuperChoiceConfig] dans l'éditeur de [SuperValue].
class SuperChoiceSettings extends StatefulWidget {
  const SuperChoiceSettings({
    required this.value,
    required this.onChanged,
    required this.builder,
    this.repositories = const [],
    this.listScope,
    this.allowBinding = true,
    super.key,
  });

  final SuperChoiceConfig value;
  final ValueChanged<SuperChoiceConfig> onChanged;
  final Widget Function(List<StyleEditorSection> sections) builder;
  final List<JsonRepositoryEntry> repositories;
  final JsonListScope? listScope;
  final bool allowBinding;

  @override
  State<SuperChoiceSettings> createState() => SuperChoiceSettingsState();
}

/// État interne du panneau de paramétrage d'un [SuperChoice].
class SuperChoiceSettingsState extends State<SuperChoiceSettings> {
  late SuperChoiceConfig _draft = widget.value;
  late String? _optionsRepoId = widget.value.optionsBinding?.repositoryId;
  late bool _inheritOptionsRepo =
      widget.value.optionsBinding != null &&
      widget.value.optionsBinding!.repositoryId == null;
  late final Map<String, TextEditingController> _fields = {
    'optionsPath': TextEditingController(
      text: widget.value.optionsBinding?.path ?? '',
    ),
    'optionValueKey': TextEditingController(text: widget.value.optionValueKey),
    'optionLabelKey': TextEditingController(text: widget.value.optionLabelKey),
    'optionIconKey': TextEditingController(text: widget.value.optionIconKey),
    'spacing': TextEditingController(text: '${widget.value.spacing}'),
    'radius': TextEditingController(
      text: widget.value.radius?.toString() ?? '',
    ),
    'borderWidth': TextEditingController(
      text: widget.value.borderWidth?.toString() ?? '',
    ),
    'searchHint': TextEditingController(text: widget.value.searchHint),
    'helperText': TextEditingController(text: widget.value.helperText),
    'errorText': TextEditingController(text: widget.value.errorText),
  };
  final List<({TextEditingController value, TextEditingController label, String? icon})>
  _optionControllers = [];

  @override
  void initState() {
    super.initState();
    _syncOptionControllers(widget.value.options);
  }

  void _syncOptionControllers(List<SuperChoiceOption> options) {
    for (final item in _optionControllers) {
      item.value.dispose();
      item.label.dispose();
    }
    _optionControllers
      ..clear()
      ..addAll([
        for (final opt in options)
          (
            value: TextEditingController(text: opt.value),
            label: TextEditingController(text: opt.label),
            icon: opt.icon,
          ),
      ]);
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final item in _optionControllers) {
      item.value.dispose();
      item.label.dispose();
    }
    super.dispose();
  }

  bool get _hasOptionsBinding => _optionsRepoId != null || _inheritOptionsRepo;

  double? _parseOptionalDouble(String key) {
    final text = _fields[key]!.text.trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      throw const FormatException('Dimension de choix invalide.');
    }
    return parsed;
  }

  /// Construit et valide l'instance de [SuperChoiceConfig] courante.
  SuperChoiceConfig value() {
    final spacingText = _fields['spacing']!.text.trim();
    final spacing = spacingText.isEmpty
        ? 8.0
        : double.tryParse(spacingText.replaceAll(',', '.'));
    if (spacing == null || !spacing.isFinite || spacing < 0) {
      throw const FormatException('Espacement de choix invalide.');
    }
    final radius = _parseOptionalDouble('radius');
    final borderWidth = _parseOptionalDouble('borderWidth');

    JsonTextBinding? optionsBinding;
    if (_hasOptionsBinding) {
      final path = _fields['optionsPath']!.text.trim();
      if (path.isEmpty) {
        throw const FormatException(
          'Chemin du tableau d’options requis pour le repository lié.',
        );
      }
      optionsBinding = JsonTextBinding(
        repositoryId: _inheritOptionsRepo ? null : _optionsRepoId,
        path: path,
      )..validate();
    }

    final options = <SuperChoiceOption>[
      for (final item in _optionControllers)
        SuperChoiceOption(
          value: item.value.text.trim(),
          label: item.label.text,
          icon: item.icon,
        ),
    ];

    final result = _draft.copyWith(
      options: options,
      optionsBinding: optionsBinding,
      clearOptionsBinding: optionsBinding == null,
      optionValueKey: _fields['optionValueKey']!.text.trim(),
      optionLabelKey: _fields['optionLabelKey']!.text.trim(),
      optionIconKey: _fields['optionIconKey']!.text.trim(),
      spacing: spacing,
      radius: radius,
      inheritRadius: radius == null,
      borderWidth: borderWidth,
      inheritBorderWidth: borderWidth == null,
      searchHint: _fields['searchHint']!.text,
      helperText: _fields['helperText']!.text,
      errorText: _fields['errorText']!.text,
    );
    result.validate();
    return result;
  }

  /// Valide la saisie courante.
  bool validate() {
    try {
      value();
      return true;
    } on FormatException {
      return false;
    }
  }

  void _emitChange() {
    try {
      final next = value();
      _draft = next;
      widget.onChanged(next);
    } on FormatException {
      setState(() {});
    }
  }

  void _addOption() {
    final index = _optionControllers.length + 1;
    var candidate = 'option_$index';
    final existing = _optionControllers.map((e) => e.value.text.trim()).toSet();
    var suffix = index;
    while (existing.contains(candidate)) {
      suffix++;
      candidate = 'option_$suffix';
    }
    setState(() {
      _optionControllers.add((
        value: TextEditingController(text: candidate),
        label: TextEditingController(text: 'Option $suffix'),
        icon: null,
      ));
    });
    _emitChange();
  }

  void _removeOption(int index) {
    setState(() {
      final removed = _optionControllers.removeAt(index);
      removed.value.dispose();
      removed.label.dispose();
    });
    _emitChange();
  }

  void _moveOption(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _optionControllers.length) return;
    setState(() {
      final item = _optionControllers.removeAt(index);
      _optionControllers.insert(target, item);
    });
    _emitChange();
  }

  void _updateOptionIcon(int index, String? icon) {
    setState(() {
      final current = _optionControllers[index];
      _optionControllers[index] = (
        value: current.value,
        label: current.label,
        icon: icon,
      );
    });
    _emitChange();
  }

  Widget _group(List<Widget> children) => buildEditorFieldGroup(children);

  Widget _text(String key, String label, {bool numeric = false}) =>
      TextFormField(
        key: ValueKey('choice-setting-$key'),
        controller: _fields[key],
        decoration: InputDecoration(labelText: label, isDense: true),
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        onChanged: (_) => _emitChange(),
      );

  Widget _colorTile({
    required String keyName,
    required String label,
    required Color? color,
    required ValueChanged<Color?> onColorChanged,
  }) => Column(
    children: [
      styleColorTile(
        label,
        color ?? Theme.of(context).colorScheme.primary,
        (next) {
          onColorChanged(next);
          _emitChange();
        },
        dense: true,
        key: ValueKey('choice-setting-$keyName'),
        onClear: () {
          onColorChanged(null);
          _emitChange();
        },
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: color == null
              ? null
              : () {
                  onColorChanged(null);
                  _emitChange();
                },
          child: const Text('Couleur du thème'),
        ),
      ),
    ],
  );

  Widget _buildOptionsListEditor() {
    final canAddSegmented =
        _draft.variant != ChoiceVariant.segmented ||
        _optionControllers.length < 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_draft.variant == ChoiceVariant.segmented)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'SegmentedButton requiert entre 2 et 5 options.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        for (var i = 0; i < _optionControllers.length; i++)
          Card(
            key: ValueKey('choice-option-card-$i'),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('choice-option-value-$i'),
                          controller: _optionControllers[i].value,
                          decoration: const InputDecoration(
                            labelText: 'Valeur',
                            isDense: true,
                          ),
                          onChanged: (_) => _emitChange(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('choice-option-label-$i'),
                          controller: _optionControllers[i].label,
                          decoration: const InputDecoration(
                            labelText: 'Libellé (optionnel)',
                            isDense: true,
                          ),
                          onChanged: (_) => _emitChange(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Monter',
                        icon: const Icon(Icons.arrow_upward, size: 18),
                        onPressed: i > 0 ? () => _moveOption(i, -1) : null,
                      ),
                      IconButton(
                        tooltip: 'Descendre',
                        icon: const Icon(Icons.arrow_downward, size: 18),
                        onPressed: i < _optionControllers.length - 1
                            ? () => _moveOption(i, 1)
                            : null,
                      ),
                      IconButton(
                        key: ValueKey('choice-option-delete-$i'),
                        tooltip: 'Supprimer l’option',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _removeOption(i),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  MaterialIconPickerField(
                    key: ValueKey(
                      'choice-option-icon-$i-${_optionControllers[i].icon}',
                    ),
                    label: 'Icône (optionnelle)',
                    value: _optionControllers[i].icon,
                    nullable: true,
                    onChanged: (icon) => _updateOptionIcon(i, icon),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('choice-option-add'),
            onPressed: canAddSegmented ? _addOption : null,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter une option'),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsRepositoryEditor() {
    final inheritable = widget.listScope != null || _inheritOptionsRepo;
    final missing =
        _optionsRepoId != null &&
        !widget.repositories.any((e) => e.id == _optionsRepoId);
    return _group([
      DropdownButtonFormField<String>(
        key: ValueKey('choice-options-repository-$_optionsRepoId'),
        initialValue: _inheritOptionsRepo
            ? inheritedRepositoryValue
            : _optionsRepoId ?? '',
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Source des options (Repository)',
          isDense: true,
        ),
        items: [
          const DropdownMenuItem(
            value: '',
            child: Text('Liste statique (options ci-dessous)'),
          ),
          if (inheritable)
            const DropdownMenuItem(
              value: inheritedRepositoryValue,
              child: Text('Hérité de la liste englobante'),
            ),
          for (final entry in widget.repositories)
            DropdownMenuItem(
              value: entry.id,
              child: Text(
                '${entry.name} (${entry.id})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (missing)
            DropdownMenuItem(
              value: _optionsRepoId,
              child: const Text('Repository indisponible'),
            ),
        ],
        onChanged: !widget.allowBinding
            ? null
            : (selected) {
                setState(() {
                  _inheritOptionsRepo = selected == inheritedRepositoryValue;
                  _optionsRepoId = selected == '' || _inheritOptionsRepo
                      ? null
                      : selected;
                });
                _emitChange();
              },
      ),
      if (_hasOptionsBinding) ...[
        _text('optionsPath', 'Chemin du tableau d’options (ex: categories)'),
        _text(
          'optionValueKey',
          'Clé de valeur dans l’objet (vide = auto / value / id)',
        ),
        _text(
          'optionLabelKey',
          'Clé de libellé dans l’objet (vide = auto / label / name)',
        ),
        _text(
          'optionIconKey',
          'Clé d’icône dans l’objet (vide = auto / icon)',
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => widget.builder([
    StyleEditorSection(
      id: 'choice-options',
      title: 'Composant de choix et options',
      icon: Icons.checklist_outlined,
      tag: '${_draft.variant.shortLabel} · ${_optionControllers.length} opt.',
      child: _group([
        DropdownButtonFormField<ChoiceVariant>(
          key: ValueKey('choice-setting-variant-${_draft.variant.name}'),
          initialValue: _draft.variant,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Type de composant de choix',
            isDense: true,
          ),
          items: [
            for (final variant in ChoiceVariant.values)
              DropdownMenuItem(
                value: variant,
                child: Text(
                  variant.displayLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (next) {
            if (next == null) return;
            setState(() {
              _draft = _draft.copyWith(variant: next);
              if (next == ChoiceVariant.segmented &&
                  _optionControllers.length == 1) {
                _optionControllers.add((
                  value: TextEditingController(text: 'option_2'),
                  label: TextEditingController(text: 'Option 2'),
                  icon: null,
                ));
              }
            });
            _emitChange();
          },
        ),
        _buildOptionsRepositoryEditor(),
        _buildOptionsListEditor(),
      ]),
    ),
    StyleEditorSection(
      id: 'choice-behavior',
      title: 'Disposition et comportement du choix',
      icon: Icons.tune,
      tag: 'direction · allowEmpty',
      child: _group([
        if (_draft.variant.isSingle)
          EditorSwitchTile(
            tileKey: const ValueKey('choice-setting-allowEmpty'),
            title: 'Autoriser l’absence de sélection',
            value: _draft.allowEmpty,
            onChanged: (val) {
              setState(() => _draft = _draft.copyWith(allowEmpty: val));
              _emitChange();
            },
          ),
        if (_draft.variant == ChoiceVariant.segmented ||
            _draft.variant == ChoiceVariant.filterChip)
          EditorSwitchTile(
            tileKey: const ValueKey('choice-setting-showCheckmark'),
            title: 'Afficher la coche de sélection',
            value: _draft.showCheckmark,
            onChanged: (val) {
              setState(() => _draft = _draft.copyWith(showCheckmark: val));
              _emitChange();
            },
          ),
        if (_draft.variant == ChoiceVariant.radio ||
            _draft.variant == ChoiceVariant.checkboxList ||
            _draft.variant == ChoiceVariant.filterChip)
          EditorSegmentedField.axis(
            buttonKey: ValueKey('choice-setting-direction-${_draft.direction}'),
            value: _draft.direction,
            onChanged: (axis) {
              setState(() => _draft = _draft.copyWith(direction: axis));
              _emitChange();
            },
          ),
        _text('spacing', 'Espacement entre les options (px)', numeric: true),
        EditorSegmentedField<String>(
          buttonKey: ValueKey('choice-setting-dense-${_draft.dense}'),
          label: 'Densité',
          spacing: 8,
          value: _draft.dense?.toString() ?? '',
          options: const [
            EditorSegmentOption(
              value: '',
              label: 'Auto',
              icon: Icons.hdr_auto_outlined,
              iconSize: 14,
              flexibleIcon: true,
            ),
            EditorSegmentOption(
              value: 'true',
              label: 'Dense',
              icon: Icons.density_small,
              iconSize: 14,
              flexibleIcon: true,
            ),
            EditorSegmentOption(
              value: 'false',
              label: 'Confortable',
              icon: Icons.density_medium,
              iconSize: 14,
              flexibleIcon: true,
            ),
          ],
          onChanged: (val) {
            setState(() {
              _draft = val.isEmpty
                  ? _draft.copyWith(inheritDense: true)
                  : _draft.copyWith(dense: val == 'true');
            });
            _emitChange();
          },
        ),
        if (_draft.variant == ChoiceVariant.searchAnchor)
          _text('searchHint', 'Texte indicatif de recherche'),
        _text('helperText', 'Texte d’aide'),
        _text('errorText', 'Message d’erreur manuel'),
      ]),
    ),
    StyleEditorSection(
      id: 'choice-style',
      title: 'Style et couleurs du choix',
      icon: Icons.palette_outlined,
      tag: 'fillColor · selectedColor · border',
      child: _group([
        _text('radius', 'Arrondi (vide = thème)', numeric: true),
        _text(
          'borderWidth',
          'Épaisseur de bordure (vide = thème)',
          numeric: true,
        ),
        _colorTile(
          keyName: 'fillColor',
          label: 'Couleur de fond',
          color: _draft.fillColor,
          onColorChanged: (c) => setState(
            () => _draft = _draft.copyWith(
              fillColor: c,
              inheritFillColor: c == null,
            ),
          ),
        ),
        _colorTile(
          keyName: 'selectedColor',
          label: 'Couleur de sélection',
          color: _draft.selectedColor,
          onColorChanged: (c) => setState(
            () => _draft = _draft.copyWith(
              selectedColor: c,
              inheritSelectedColor: c == null,
            ),
          ),
        ),
        _colorTile(
          keyName: 'borderColor',
          label: 'Couleur de bordure',
          color: _draft.borderColor,
          onColorChanged: (c) => setState(
            () => _draft = _draft.copyWith(
              borderColor: c,
              inheritBorderColor: c == null,
            ),
          ),
        ),
      ]),
    ),
  ]);
}
