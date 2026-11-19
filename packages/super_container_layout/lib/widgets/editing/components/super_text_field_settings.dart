/// Panneau de configuration d'un champ texte [SuperTextField] ([SuperTextFieldConfig]).
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/super_text_field_config.dart';
import '../../../models/json_syntax.dart';
import '../icons/material_icon_picker.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../styles/style_editor_panel.dart';
import 'shared/editor_color_fields.dart';
import 'shared/editor_segmented_field.dart';

/// Keeps incomplete numeric/regex drafts out of the live preview.
class SuperTextFieldSettings extends StatefulWidget {
  const SuperTextFieldSettings({
    required this.value,
    required this.onChanged,
    required this.builder,
    super.key,
  });
  final SuperTextFieldConfig value;
  final ValueChanged<SuperTextFieldConfig> onChanged;
  final Widget Function(List<StyleEditorSection> sections) builder;

  @override
  State<SuperTextFieldSettings> createState() => SuperTextFieldSettingsState();
}

/// État interne du dialogue de paramétrage d'un [SuperTextField].
class SuperTextFieldSettingsState extends State<SuperTextFieldSettings> {
  late Map<String, Object?> _values = widget.value.toJson();
  late final Map<String, TextEditingController> _fields = {
    for (final key in [
      'radius',
      'borderWidth',
      'horizontalPadding',
      'verticalPadding',
      'maxLength',
      'prefixText',
      'suffixText',
      'helperText',
      'errorText',
      'pattern',
      'mask',
      'dateFormat',
      'decimalDigits',
      'minLength',
      'validationPattern',
      'minimum',
      'maximum',
      'exclusiveMinimum',
      'exclusiveMaximum',
      'multipleOf',
      'enumValues',
      'constValue',
      'validationMessage',
    ])
      key: TextEditingController(
        text: key == 'enumValues'
            ? ((_values[key] as List?)?.join(', ') ?? '')
            : (_values[key]?.toString() ?? ''),
      ),
  };
  String? _error;

  /// Synchronise les contrôleurs depuis une modification externe (ex. mode
  /// affichage dans [SuperValueEditor]) hors phase de construction.
  void syncValue(SuperTextFieldConfig nextValue) {
    final next = nextValue.toJson();
    _values = next;
    for (final entry in _fields.entries) {
      final formatted = entry.key == 'enumValues'
          ? ((next[entry.key] as List?)?.join(', ') ?? '')
          : (next[entry.key]?.toString() ?? '');
      if (entry.value.text != formatted) {
        entry.value.text = formatted;
      }
    }
  }

  SuperTextFieldConfig value() {
    final values = {..._values};
    for (final entry in _fields.entries) {
      final text = entry.value.text;
      if ([
        'radius',
        'borderWidth',
        'horizontalPadding',
        'verticalPadding',
      ].contains(entry.key)) {
        final number = text.trim().isEmpty
            ? null
            : double.tryParse(text.replaceAll(',', '.'));
        if (text.trim().isNotEmpty && number == null) {
          throw const FormatException('Dimension numérique requise.');
        }
        values[entry.key] = number;
      } else if ([
        'minimum',
        'maximum',
        'exclusiveMinimum',
        'exclusiveMaximum',
        'multipleOf',
      ].contains(entry.key)) {
        final number = text.trim().isEmpty
            ? null
            : double.tryParse(text.trim().replaceAll(',', '.'));
        if (text.trim().isNotEmpty && number == null) {
          throw const FormatException('Valeur numérique requise.');
        }
        values[entry.key] = number;
      } else if (entry.key == 'maxLength') {
        final number = text.trim().isEmpty ? null : int.tryParse(text.trim());
        if (text.trim().isNotEmpty && number == null) {
          throw const FormatException('Longueur maximale entière requise.');
        }
        values[entry.key] = number;
      } else if (entry.key == 'minLength') {
        final number = text.trim().isEmpty ? null : int.tryParse(text.trim());
        if (text.trim().isNotEmpty && number == null) {
          throw const FormatException('Longueur minimale entière requise.');
        }
        values[entry.key] = number;
      } else if (entry.key == 'decimalDigits') {
        final number = text.trim().isEmpty ? null : int.tryParse(text.trim());
        if (text.trim().isNotEmpty && number == null) {
          throw const FormatException('Nombre de décimales entier requis.');
        }
        values[entry.key] = number;
      } else if (entry.key == 'enumValues') {
        values[entry.key] = [
          for (final part in text.split(','))
            if (part.trim().isNotEmpty) part.trim(),
        ];
      } else if (entry.key == 'constValue') {
        values[entry.key] = text.isEmpty ? null : text;
      } else {
        values[entry.key] = text;
      }
    }
    return SuperTextFieldConfig.fromJson(values);
  }

  bool validate() {
    try {
      value();
      setState(() => _error = null);
      return true;
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return false;
    }
  }

  void _update(String key, Object? value) {
    _values[key] = value;
    try {
      final config = this.value();
      setState(() => _error = null);
      widget.onChanged(config);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  static IconData _choiceIcon(String key, String value) =>
      switch ((key, value)) {
        (_, '') => Icons.hdr_auto_outlined,
        ('variant', 'theme') => Icons.hdr_auto_outlined,
        ('variant', 'filled') => Icons.format_color_fill,
        ('variant', 'outlined') => Icons.crop_16_9,
        ('variant', 'underline') => Icons.border_bottom,
        ('variant', 'borderless') => Icons.border_clear,
        ('suffix', 'decoration') => Icons.image_outlined,
        ('suffix', 'clear') => Icons.clear,
        ('suffix', 'visibility') => Icons.visibility_outlined,
        ('filter', 'none') => Icons.filter_none,
        ('filter', 'digits') => Icons.pin_outlined,
        ('filter', 'decimal') => Icons.numbers,
        ('filter', 'letters') => Icons.sort_by_alpha,
        ('filter', 'pattern') => Icons.code,
        ('valueType', 'string') => Icons.text_fields,
        ('valueType', 'integer') => Icons.pin_outlined,
        ('valueType', 'number') => Icons.numbers,
        ('capitalization', 'none') => Icons.text_rotation_none,
        ('capitalization', 'words') => Icons.title,
        ('capitalization', 'sentences') => Icons.short_text,
        ('capitalization', 'characters') => Icons.text_fields,
        ('verticalAlign', 'automatic') => Icons.hdr_auto_outlined,
        ('verticalAlign', 'top') => Icons.vertical_align_top,
        ('verticalAlign', 'center') => Icons.vertical_align_center,
        ('verticalAlign', 'bottom') => Icons.vertical_align_bottom,
        ('floatingLabel', 'auto') => Icons.motion_photos_auto_outlined,
        ('floatingLabel', 'always') => Icons.label_outlined,
        ('floatingLabel', 'never') => Icons.label_off_outlined,
        _ => Icons.tune,
      };

  Widget _choice<T extends Enum>(
    String key,
    String label,
    List<T> values, {
    Map<String, String> labels = const {},
    bool nullable = false,
  }) {
    final totalOptions = values.length + (nullable ? 1 : 0);
    final current = _values[key] as String? ?? '';
    if (totalOptions <= 5) {
      return EditorSegmentedField<String>(
        buttonKey: ValueKey('text-field-setting-$key-${_values[key]}'),
        label: label,
        value: current,
        options: [
          if (nullable)
            EditorSegmentOption<String>(
              value: '',
              label: 'Thème / aucune',
              icon: _choiceIcon(key, ''),
              iconSize: 14,
              flexibleIcon: true,
            ),
          for (final value in values)
            EditorSegmentOption<String>(
              value: value.name,
              label: labels[value.name] ?? value.name,
              icon: _choiceIcon(key, value.name),
              iconSize: 14,
              flexibleIcon: true,
            ),
        ],
        onChanged: (next) => _update(key, next == '' ? null : next),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('text-field-setting-$key-${_values[key]}'),
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (nullable)
          const DropdownMenuItem(value: '', child: Text('Thème / aucune')),
        for (final value in values)
          DropdownMenuItem(
            value: value.name,
            child: Text(labels[value.name] ?? value.name),
          ),
      ],
      onChanged: (value) => _update(key, value == '' ? null : value),
    );
  }

  Widget _text(String key, String label, {bool numeric = false}) =>
      TextFormField(
        key: ValueKey('text-field-setting-$key'),
        controller: _fields[key],
        decoration: InputDecoration(labelText: label),
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        onChanged: (_) => _update(key, _fields[key]!.text),
      );

  Widget _switch(String key, String label) => EditorSwitchTile(
    tileKey: ValueKey('text-field-setting-$key'),
    title: label,
    value: _values[key] == true,
    onChanged: (value) => _update(key, value),
  );

  Widget _color(String key, String label) {
    final color = JsonColor.parseNullable(_values[key], key);
    return Column(
      children: [
        styleColorTile(
          label,
          color,
          (color) => _update(key, JsonColor.toJson(color)),
          dense: true,
          key: ValueKey('text-field-setting-$key'),
          onClear: () => _update(key, null),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: color == null ? null : () => _update(key, null),
            child: const Text('Couleur du thème'),
          ),
        ),
      ],
    );
  }

  Widget _group(List<Widget> children) => buildEditorFieldGroup(children);

  @override
  Widget build(BuildContext context) => widget.builder([
    StyleEditorSection(
      id: 'text-field-style',
      title: 'Style du champ',
      icon: Icons.input,
      tag: 'border · padding',
      child: _group([
        const Text('Ces options concernent uniquement le mode Saisie.'),
        _choice(
          'variant',
          'Style du champ',
          TextFieldVariant.values,
          labels: const {
            'theme': 'Thème',
            'filled': 'Filled',
            'outlined': 'Outlined',
            'underline': 'Underline',
            'borderless': 'Sans bordure',
          },
        ),
        _text('radius', 'Arrondi (vide = thème)', numeric: true),
        _text(
          'borderWidth',
          'Épaisseur de bordure (vide = thème)',
          numeric: true,
        ),
        _text(
          'horizontalPadding',
          'Marge interne horizontale (vide = thème)',
          numeric: true,
        ),
        _text(
          'verticalPadding',
          'Marge interne verticale (vide = thème)',
          numeric: true,
        ),
        EditorSegmentedField<String>(
          buttonKey: ValueKey('text-field-setting-dense-${_values['dense']}'),
          label: 'Densité',
          spacing: 12,
          value: _values['dense']?.toString() ?? '',
          options: const [
            EditorSegmentOption(
              value: '',
              label: 'Par défaut',
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
          onChanged: (value) =>
              _update('dense', value == '' ? null : value == 'true'),
        ),
      ]),
    ),
    StyleEditorSection(
      id: 'text-field-colors',
      title: 'Couleurs du champ',
      icon: Icons.palette_outlined,
      tag: 'fillColor · borderColor',
      child: _group([
        for (final entry in {
          'fillColor': 'Fond normal',
          'focusFillColor': 'Fond au focus',
          'disabledFillColor': 'Fond désactivé',
          'errorFillColor': 'Fond en erreur',
          'borderColor': 'Bordure normale',
          'focusBorderColor': 'Bordure au focus',
          'disabledBorderColor': 'Bordure désactivée',
          'errorBorderColor': 'Bordure en erreur (avec ou sans focus)',
        }.entries)
          _color(entry.key, entry.value),
      ]),
    ),
    StyleEditorSection(
      id: 'text-field-ornaments',
      title: 'Préfixes et suffixes',
      icon: Icons.insert_emoticon_outlined,
      tag: 'prefix · suffix',
      child: _group([
        _text('prefixText', 'Texte de préfixe'),
        MaterialIconPickerField(
          key: ValueKey(
            'text-field-setting-prefixIcon-${_values['prefixIcon']}',
          ),
          label: 'Icône de préfixe',
          value: _values['prefixIcon'] as String?,
          nullable: true,
          allowedIds: [for (final icon in TextFieldIcon.values) icon.name],
          onChanged: (value) => _update('prefixIcon', value),
        ),
        _text('suffixText', 'Texte de suffixe'),
        _choice(
          'suffix',
          'Fonction du suffixe',
          TextFieldSuffix.values,
          labels: const {
            'decoration': 'Icône décorative',
            'clear': 'Effacer',
            'visibility': 'Afficher / masquer le mot de passe',
          },
        ),
        if (_values['suffix'] == 'decoration')
          MaterialIconPickerField(
            key: ValueKey(
              'text-field-setting-suffixIcon-${_values['suffixIcon']}',
            ),
            label: 'Icône de suffixe',
            value: _values['suffixIcon'] as String?,
            nullable: true,
            allowedIds: [for (final icon in TextFieldIcon.values) icon.name],
            onChanged: (value) => _update('suffixIcon', value),
          ),
        if (_values['suffix'] == 'visibility')
          const Text(
            'Action disponible uniquement pour un champ Mot de passe.',
          ),
      ]),
    ),
    StyleEditorSection(
      id: 'text-field-messages',
      title: 'Messages et compteur',
      icon: Icons.info_outline,
      tag: 'helperText · errorText · counter',
      child: _group([
        _text('helperText', 'Texte d’aide'),
        _text('errorText', 'Message d’erreur manuel'),
        _switch('showCounter', 'Afficher le compteur de caractères'),
      ]),
    ),
    StyleEditorSection(
      id: 'text-field-filters',
      title: 'Masques, limites et contraintes',
      icon: Icons.filter_alt_outlined,
      tag: 'mask · JSON Schema',
      child: _group([
        _text('mask', 'Masque à motifs (ex. ##/##/####, UU-###-UU)'),
        if ((_values['mask'] as String? ?? '').isNotEmpty ||
            _fields['mask']!.text.isNotEmpty)
          _switch(
            'maskIncludeLiterals',
            'Inclure les littéraux du masque dans la valeur enregistrée',
          ),
        const Text(
          'Jetons : # chiffre · A lettre · U majuscule · L minuscule · * alphanumérique · \\ échappement.',
        ),
        _text('dateFormat', 'Format de date affiché (ex. dd/MM/yyyy)'),
        _text(
          'decimalDigits',
          'Décimales affichées (0..10, vide = brut)',
          numeric: true,
        ),
        EditorSegmentedField<String>(
          buttonKey: ValueKey(
            'text-field-setting-decimalSeparator-${_values['decimalSeparator']}',
          ),
          label: 'Séparateur décimal',
          value: (_values['decimalSeparator'] as String?) ?? '.',
          options: const [
            EditorSegmentOption(value: '.', label: 'Point (.)'),
            EditorSegmentOption(value: ',', label: 'Virgule (,)'),
          ],
          onChanged: (value) => _update('decimalSeparator', value),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(
            'text-field-setting-thousandsSeparator-${_values['thousandsSeparator']}',
          ),
          initialValue: (_values['thousandsSeparator'] as String?) ?? '',
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Séparateur des milliers',
          ),
          items: const [
            DropdownMenuItem(value: '', child: Text('Aucun')),
            DropdownMenuItem(value: ' ', child: Text('Espace ( )')),
            DropdownMenuItem(value: ',', child: Text('Virgule (,)')),
            DropdownMenuItem(value: '.', child: Text('Point (.)')),
          ],
          onChanged: (value) => _update('thousandsSeparator', value ?? ''),
        ),
        const Divider(),
        _choice(
          'valueType',
          'Type JSON Schema',
          TextFieldValueType.values,
          labels: {
            for (final t in TextFieldValueType.values) t.name: t.displayLabel,
          },
        ),
        _switch('required', 'Champ obligatoire (required)'),
        _text(
          'minLength',
          'Longueur minimale (minLength)',
          numeric: true,
        ),
        _text(
          'maxLength',
          'Longueur maximale (vide = illimitée)',
          numeric: true,
        ),
        _text('validationPattern', 'Regex de validation complète (pattern)'),
        DropdownButtonFormField<String>(
          key: ValueKey('text-field-setting-format-${_values['format']}'),
          initialValue: (_values['format'] as String?) ?? 'none',
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Format JSON Schema (format)',
          ),
          items: [
            for (final format in TextFieldFormat.values)
              DropdownMenuItem(
                value: format.name,
                child: Text(format.displayLabel),
              ),
          ],
          onChanged: (value) => _update('format', value ?? 'none'),
        ),
        if (_values['valueType'] != 'string' ||
            _fields['minimum']!.text.isNotEmpty ||
            _fields['maximum']!.text.isNotEmpty ||
            _fields['exclusiveMinimum']!.text.isNotEmpty ||
            _fields['exclusiveMaximum']!.text.isNotEmpty ||
            _fields['multipleOf']!.text.isNotEmpty) ...[
          _text('minimum', 'Minimum inclusif (minimum)', numeric: true),
          _text('maximum', 'Maximum inclusif (maximum)', numeric: true),
          _text(
            'exclusiveMinimum',
            'Minimum strict (exclusiveMinimum)',
            numeric: true,
          ),
          _text(
            'exclusiveMaximum',
            'Maximum strict (exclusiveMaximum)',
            numeric: true,
          ),
          _text('multipleOf', 'Multiple de (multipleOf)', numeric: true),
        ],
        _text('enumValues', 'Valeurs autorisées (enum, séparées par virgules)'),
        _text('constValue', 'Valeur exacte imposée (const)'),
        _text('validationMessage', 'Message d’erreur de validation'),
        const Divider(),
        _choice(
          'filter',
          'Filtre de saisie',
          TextFieldFilter.values,
          labels: const {
            'none': 'Aucun',
            'digits': 'Chiffres uniquement',
            'decimal': 'Nombre décimal signé',
            'letters': 'Lettres, espaces, apostrophes et traits d’union',
            'pattern': 'Expression régulière',
          },
        ),
        if (_values['filter'] == 'pattern') ...[
          _text('pattern', 'Caractères autorisés (regex)'),
          const Text(
            'Exemple : [A-Za-z0-9_]. Les caractères non autorisés sont retirés. '
            'Ne pas utiliser une validation de texte entier avec ^ et \$.',
          ),
        ],
        const Text(
          'Les filtres de frappe ne modifient pas les valeurs déjà chargées ; '
          'la validation bloque la sauvegarde repository tant que la saisie est invalide.',
        ),
      ]),
    ),
    StyleEditorSection(
      id: 'text-field-keyboard',
      title: 'Clavier et saisie',
      icon: Icons.keyboard_outlined,
      tag: 'keyboard · textInputAction',
      child: _group([
        _choice(
          'keyboard',
          'Clavier',
          TextFieldKeyboard.values,
          labels: const {
            'automatic': 'Automatique',
            'text': 'Texte',
            'multiline': 'Multiligne',
            'email': 'E-mail',
            'phone': 'Téléphone',
            'url': 'URL',
            'number': 'Nombre',
            'decimal': 'Décimal',
            'signedDecimal': 'Décimal signé',
          },
        ),
        _choice(
          'action',
          'Action Entrée',
          TextFieldAction.values,
          labels: const {
            'automatic': 'Automatique',
            'done': 'Terminer',
            'next': 'Suivant',
            'previous': 'Précédent',
            'search': 'Rechercher',
            'send': 'Envoyer',
            'go': 'Accéder',
            'newline': 'Nouvelle ligne',
          },
        ),
        _choice(
          'capitalization',
          'Capitalisation',
          TextCapitalization.values,
          labels: const {
            'none': 'Aucune',
            'words': 'Mots',
            'sentences': 'Phrases',
            'characters': 'Caractères',
          },
        ),
        _choice(
          'verticalAlign',
          'Alignement vertical',
          TextFieldVerticalAlign.values,
          labels: const {
            'automatic': 'Automatique',
            'top': 'Haut',
            'center': 'Centre',
            'bottom': 'Bas',
          },
        ),
        _choice(
          'floatingLabel',
          'Label flottant',
          FloatingLabelBehavior.values,
          nullable: true,
          labels: const {
            'auto': 'Automatique',
            'always': 'Toujours',
            'never': 'Jamais',
          },
        ),
        _switch('autocorrect', 'Autocorrection'),
        _switch('suggestions', 'Suggestions'),
        const Text(
          'Autocorrection et suggestions restent désactivées pour les mots de passe.',
        ),
        if (_error != null)
          Text(
            _error!,
            key: const ValueKey('text-field-settings-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ]),
    ),
  ]);
}
