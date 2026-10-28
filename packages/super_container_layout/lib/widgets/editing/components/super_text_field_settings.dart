import 'package:material_ui/material_ui.dart';

import '../../../models/super_text_field_config.dart';
import '../icons/material_icon_picker.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../styles/style_editor_panel.dart';

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

class SuperTextFieldSettingsState extends State<SuperTextFieldSettings> {
  late final Map<String, Object?> _values = widget.value.toJson();
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
    ])
      key: TextEditingController(text: _values[key]?.toString() ?? ''),
  };
  String? _error;

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
      } else if (entry.key == 'maxLength') {
        final number = text.trim().isEmpty ? null : int.tryParse(text.trim());
        if (text.trim().isNotEmpty && number == null) {
          throw const FormatException('Longueur maximale entière requise.');
        }
        values[entry.key] = number;
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

  Widget _choice<T extends Enum>(
    String key,
    String label,
    List<T> values, {
    Map<String, String> labels = const {},
    bool nullable = false,
  }) => DropdownButtonFormField<String>(
    key: ValueKey('text-field-setting-$key-${_values[key]}'),
    initialValue: _values[key] as String? ?? '',
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

  Widget _text(String key, String label, {bool numeric = false}) =>
      TextFormField(
        key: ValueKey('text-field-setting-$key'),
        controller: _fields[key],
        decoration: InputDecoration(labelText: label),
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        onChanged: (_) => _update(key, _fields[key]!.text),
      );

  Widget _switch(String key, String label) => SwitchListTile(
    key: ValueKey('text-field-setting-$key'),
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: _values[key] == true,
    onChanged: (value) => _update(key, value),
  );

  Widget _color(String key, String label) {
    final color = _values[key] as int?;
    return Column(
      children: [
        styleColorTile(
          label,
          color == null ? Theme.of(context).colorScheme.primary : Color(color),
          (color) => _update(key, color.toARGB32()),
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

  Widget _group(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        children[i],
      ],
    ],
  );

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
        DropdownButtonFormField<String>(
          key: ValueKey('text-field-setting-dense-${_values['dense']}'),
          isExpanded: true,
          initialValue: _values['dense']?.toString() ?? '',
          decoration: const InputDecoration(labelText: 'Densité'),
          items: const [
            DropdownMenuItem(value: '', child: Text('Par défaut')),
            DropdownMenuItem(value: 'true', child: Text('Dense')),
            DropdownMenuItem(value: 'false', child: Text('Confortable')),
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
      title: 'Limites et filtres',
      icon: Icons.filter_alt_outlined,
      tag: 'maxLength · inputFormatters',
      child: _group([
        _text(
          'maxLength',
          'Longueur maximale (vide = illimitée)',
          numeric: true,
        ),
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
          'Les filtres et limites ne modifient pas les valeurs chargées depuis le code ou un repository.',
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
