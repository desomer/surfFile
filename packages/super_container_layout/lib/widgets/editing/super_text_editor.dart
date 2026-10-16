import 'package:material_ui/material_ui.dart';

import '../../models/super_text_config.dart';
import 'editor_dialog.dart';

Future<SuperTextConfig?> showSuperTextEditor({
  required BuildContext context,
  required SuperTextConfig config,
  required List<String> availableFontFamilies,
}) => showEditorDialog<SuperTextConfig>(
  context: context,
  builder: (_) => _SuperTextEditor(
    config: config,
    availableFontFamilies: availableFontFamilies,
  ),
);

class _SuperTextEditor extends StatefulWidget {
  const _SuperTextEditor({
    required this.config,
    required this.availableFontFamilies,
  });
  final SuperTextConfig config;
  final List<String> availableFontFamilies;

  @override
  State<_SuperTextEditor> createState() => _SuperTextEditorState();
}

class _SuperTextEditorState extends State<_SuperTextEditor> {
  final _form = GlobalKey<FormState>();
  late SuperTextConfig _draft;
  late final Map<String, TextEditingController> _fields;

  @override
  void initState() {
    super.initState();
    _draft = widget.config;
    _fields = {
      'initialText': TextEditingController(text: _draft.initialText),
      'label': TextEditingController(text: _draft.label),
      'placeholder': TextEditingController(text: _draft.placeholder),
      'minLines': TextEditingController(text: '${_draft.minLines}'),
      'maxLines': TextEditingController(text: '${_draft.maxLines}'),
      'fontSize': TextEditingController(
        text: _draft.fontSize?.toString() ?? '',
      ),
      'lineHeight': TextEditingController(
        text: _draft.lineHeight?.toString() ?? '',
      ),
      'letterSpacing': TextEditingController(
        text: _draft.letterSpacing?.toString() ?? '',
      ),
      'color': TextEditingController(
        text: _draft.color?.toARGB32().toRadixString(16).padLeft(8, '0') ?? '',
      ),
    };
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String label, {bool numeric = false}) =>
      TextFormField(
        key: ValueKey('super-text-setting-$key'),
        controller: _fields[key],
        maxLines: key == 'initialText' ? 3 : 1,
        decoration: InputDecoration(labelText: label),
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        validator: (text) {
          final value = (text ?? '').trim();
          if (key == 'minLines' || key == 'maxLines') {
            final number = int.tryParse(value);
            if (number == null || number < 1) return 'Entier positif requis.';
            final min = int.tryParse(_fields['minLines']!.text);
            if (key == 'maxLines' && min != null && number < min) {
              return 'Le maximum doit être supérieur ou égal au minimum.';
            }
          } else if (numeric && value.isNotEmpty) {
            final number = double.tryParse(value.replaceAll(',', '.'));
            if (number == null ||
                !number.isFinite ||
                (key != 'letterSpacing' && number <= 0)) {
              return 'Valeur numérique valide requise.';
            }
          } else if (key == 'color' &&
              value.isNotEmpty &&
              !RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(value)) {
            return 'Couleur AARRGGBB à 8 chiffres hexadécimaux requise.';
          }
          return null;
        },
      );

  @override
  Widget build(BuildContext context) {
    final fonts = widget.availableFontFamilies.toSet().toList();
    final unavailable =
        _draft.fontFamily != null && !fonts.contains(_draft.fontFamily);
    return AlertDialog(
      key: const ValueKey('super-text-settings'),
      title: const Text('Configurer le texte'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<SuperTextMode>(
                  key: const ValueKey('super-text-setting-mode'),
                  initialValue: _draft.mode,
                  decoration: const InputDecoration(labelText: 'Mode'),
                  items: const [
                    DropdownMenuItem(
                      value: SuperTextMode.display,
                      child: Text('Affichage'),
                    ),
                    DropdownMenuItem(
                      value: SuperTextMode.input,
                      child: Text('Saisie'),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) {
                      setState(() => _draft = _draft.copyWith(mode: mode));
                    }
                  },
                ),
                SwitchListTile(
                  key: const ValueKey('super-text-setting-obscureText'),
                  title: const Text('Mot de passe'),
                  value: _draft.obscureText,
                  onChanged: (value) => setState(() {
                    _draft = _draft.copyWith(obscureText: value);
                    if (value) {
                      _fields['initialText']!.clear();
                      _fields['minLines']!.text = '1';
                      _fields['maxLines']!.text = '1';
                    }
                  }),
                ),
                if (_draft.obscureText)
                  const Text(
                    'Texte masqué dans les deux modes. Une seule ligne, sans texte initial sauvegardé.',
                  )
                else ...[
                  _field('initialText', 'Texte initial'),
                  _field('minLines', 'Lignes minimales', numeric: true),
                  _field('maxLines', 'Lignes maximales', numeric: true),
                ],
                _field('label', 'Label'),
                _field('placeholder', 'Placeholder'),
                SwitchListTile(
                  key: const ValueKey('super-text-setting-enabled'),
                  title: const Text('Activé'),
                  value: _draft.enabled,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(enabled: value)),
                ),
                SwitchListTile(
                  key: const ValueKey('super-text-setting-readOnly'),
                  title: const Text('Lecture seule'),
                  value: _draft.readOnly,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(readOnly: value)),
                ),
                if (unavailable)
                  Text(
                    'Police indisponible : ${_draft.fontFamily}. Choisissez une police disponible.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'super-text-setting-fontFamily-${_draft.fontFamily}',
                  ),
                  initialValue: unavailable ? null : _draft.fontFamily,
                  hint: const Text('Police du thème'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Police du thème'),
                    ),
                    for (final font in fonts)
                      DropdownMenuItem(value: font, child: Text(font)),
                  ],
                  onChanged: (font) => setState(
                    () => _draft = _draft.copyWith(
                      fontFamily: font,
                      inheritFontFamily: font == null || font.isEmpty,
                    ),
                  ),
                  validator: (_) =>
                      unavailable ? 'Choisissez une police disponible.' : null,
                ),
                _field(
                  'fontSize',
                  'Taille de police (vide = thème)',
                  numeric: true,
                ),
                DropdownButtonFormField<FontWeight>(
                  initialValue: _draft.fontWeight,
                  decoration: const InputDecoration(labelText: 'Graisse'),
                  hint: const Text('Graisse du thème'),
                  items: [
                    const DropdownMenuItem<FontWeight>(
                      value: null,
                      child: Text('Graisse du thème'),
                    ),
                    for (final weight in FontWeight.values)
                      DropdownMenuItem(
                        value: weight,
                        child: Text('${weight.value}'),
                      ),
                  ],
                  onChanged: (weight) => setState(
                    () => _draft = _draft.copyWith(
                      fontWeight: weight,
                      inheritFontWeight: weight == null,
                    ),
                  ),
                ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('super-text-setting-italic'),
                  initialValue: _draft.italic == null
                      ? 'inherit'
                      : _draft.italic!
                      ? 'italic'
                      : 'normal',
                  decoration: const InputDecoration(
                    labelText: 'Style de police',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'inherit',
                      child: Text('Style du parent'),
                    ),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'italic', child: Text('Italique')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(
                      () => _draft = _draft.copyWith(
                        italic: value == 'italic',
                        inheritItalic: value == 'inherit',
                      ),
                    );
                  },
                ),
                _field('color', 'Couleur AARRGGBB (vide = thème)'),
                DropdownButtonFormField<TextAlign>(
                  initialValue: _draft.textAlign,
                  decoration: const InputDecoration(labelText: 'Alignement'),
                  items: [
                    for (final align in TextAlign.values)
                      DropdownMenuItem(value: align, child: Text(align.name)),
                  ],
                  onChanged: (align) {
                    if (align != null) {
                      setState(
                        () => _draft = _draft.copyWith(textAlign: align),
                      );
                    }
                  },
                ),
                _field(
                  'lineHeight',
                  'Interligne (multiplicateur)',
                  numeric: true,
                ),
                _field(
                  'letterSpacing',
                  'Espacement des lettres (px)',
                  numeric: true,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            double? number(String key) => _fields[key]!.text.trim().isEmpty
                ? null
                : double.parse(_fields[key]!.text.replaceAll(',', '.'));
            final color = _fields['color']!.text.trim();
            final result = _draft.copyWith(
              initialText: _draft.obscureText
                  ? ''
                  : _fields['initialText']!.text,
              label: _fields['label']!.text,
              placeholder: _fields['placeholder']!.text,
              minLines: _draft.obscureText
                  ? 1
                  : int.parse(_fields['minLines']!.text),
              maxLines: _draft.obscureText
                  ? 1
                  : int.parse(_fields['maxLines']!.text),
              fontSize: number('fontSize'),
              inheritFontSize: number('fontSize') == null,
              lineHeight: number('lineHeight'),
              inheritLineHeight: number('lineHeight') == null,
              letterSpacing: number('letterSpacing'),
              inheritLetterSpacing: number('letterSpacing') == null,
              color: color.isEmpty ? null : Color(int.parse(color, radix: 16)),
              inheritColor: color.isEmpty,
            );
            result.validate();
            Navigator.of(context).pop(result);
          },
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}
