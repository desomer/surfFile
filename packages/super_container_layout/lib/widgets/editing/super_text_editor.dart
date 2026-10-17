import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../models/super_text_config.dart';
import 'container_style_editor.dart' show styleColorTile;
import 'editor_dialog.dart';
import 'style_editor_panel.dart';

Future<SuperTextConfig?> showSuperTextEditor({
  required BuildContext context,
  required SuperTextConfig config,
  required List<String> availableFontFamilies,
}) async {
  final width = ValueNotifier(StyleEditorPanel.preferredDense ? 680.0 : 1080.0);
  final textStyle = DefaultTextStyle.of(context).style;
  try {
    return await showEditorDialog<SuperTextConfig>(
      context: context,
      target: context,
      preferredWidth: width,
      builder: (_) => _SuperTextEditor(
        config: config,
        availableFontFamilies: availableFontFamilies,
        textStyle: textStyle,
        onWidthChanged: (value) => width.value = value,
      ),
    );
  } finally {
    width.dispose();
  }
}

class _SuperTextEditor extends StatefulWidget {
  const _SuperTextEditor({
    required this.config,
    required this.availableFontFamilies,
    required this.textStyle,
    required this.onWidthChanged,
  });
  final SuperTextConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;

  @override
  State<_SuperTextEditor> createState() => _SuperTextEditorState();
}

class _SuperTextEditorState extends State<_SuperTextEditor> {
  final _form = GlobalKey<FormState>();
  late SuperTextConfig _draft;
  late final Map<String, TextEditingController> _fields;
  late bool _dense = StyleEditorPanel.preferredDense;
  final _previewText = TextEditingController();

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
    _previewText.dispose();
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
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (_) => setState(() {}),
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

  Widget _group(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        children[i],
      ],
    ],
  );

  Widget _preview(bool unavailable) {
    double? number(String key, {bool positive = true}) {
      final value = double.tryParse(_fields[key]!.text.replaceAll(',', '.'));
      return value != null && value.isFinite && (!positive || value > 0)
          ? value
          : null;
    }

    final color = _fields['color']!.text.trim();
    final style = widget.textStyle.copyWith(
      fontFamily: unavailable ? null : _draft.fontFamily,
      fontSize: number('fontSize'),
      fontWeight: _draft.fontWeight,
      fontStyle: _draft.italic == null
          ? null
          : _draft.italic!
          ? FontStyle.italic
          : FontStyle.normal,
      color: RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(color)
          ? Color(int.parse(color, radix: 16))
          : null,
      height: number('lineHeight'),
      letterSpacing: number('letterSpacing', positive: false),
    );
    final text = _draft.obscureText ? '' : _fields['initialText']!.text;
    if (_previewText.text != text) _previewText.text = text;
    final min = math.max(1, int.tryParse(_fields['minLines']!.text) ?? 1);
    final max = math.max(min, int.tryParse(_fields['maxLines']!.text) ?? min);
    final label = _fields['label']!.text;
    final placeholder = _fields['placeholder']!.text;
    final display = Text(
      text.isEmpty ? placeholder : text,
      style: style,
      textAlign: _draft.textAlign,
      maxLines: _draft.obscureText ? 1 : max,
      overflow: TextOverflow.ellipsis,
    );
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('super-text-preview'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Aperçu', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 100),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: _draft.mode == SuperTextMode.input
                  ? TextField(
                      controller: _previewText,
                      readOnly: true,
                      enabled: _draft.enabled,
                      style: style,
                      textAlign: _draft.textAlign,
                      obscureText: _draft.obscureText,
                      minLines: _draft.obscureText ? 1 : min,
                      maxLines: _draft.obscureText ? 1 : max,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: label.isEmpty ? null : label,
                        hintText: placeholder.isEmpty ? null : placeholder,
                      ),
                    )
                  : label.isEmpty
                  ? display
                  : InputDecorator(
                      decoration: InputDecoration(
                        labelText: label,
                        enabled: _draft.enabled,
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      child: display,
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              'Brouillon uniquement. La saisie de l’application n’est pas utilisée.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_draft.obscureText)
              const Text('Mot de passe : aucun texte initial sauvegardé.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fonts = widget.availableFontFamilies.toSet().toList();
    final unavailable =
        _draft.fontFamily != null && !fonts.contains(_draft.fontFamily);
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(
      _dense ? 680.0 : 1080.0,
      math.max(0.0, screen.width - 96),
    );
    final height = math.min(680.0, math.max(0.0, screen.height - 180));
    return AlertDialog(
      key: const ValueKey('super-text-settings'),
      insetPadding: const EdgeInsets.all(24),
      constraints: BoxConstraints(maxWidth: width + 48),
      content: SizedBox(
        width: width,
        height: height,
        child: Form(
          key: _form,
          child: StyleEditorPanel(
            label: 'Configurer le texte',
            dense: _dense,
            onDenseChanged: (value) => setState(() {
              _dense = value;
              widget.onWidthChanged(value ? 680 : 1080);
            }),
            preview: _preview(unavailable),
            sections: [
              StyleEditorSection(
                id: 'text-content',
                title: 'Contenu',
                icon: Icons.text_fields,
                tag: 'mode · initialText',
                child: _group([
                  DropdownButtonFormField<SuperTextMode>(
                    isExpanded: true,
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
                  if (!_draft.obscureText)
                    _field('initialText', 'Texte initial'),
                  _field('label', 'Label'),
                  _field('placeholder', 'Placeholder'),
                  const Text(
                    'Changer le mode ou le texte initial réinitialise la valeur dans l’application.',
                  ),
                ]),
              ),
              StyleEditorSection(
                id: 'text-behavior',
                title: 'Comportement',
                icon: Icons.tune,
                tag: 'enabled · readOnly',
                child: _group([
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
                    _field('minLines', 'Lignes minimales', numeric: true),
                    _field('maxLines', 'Lignes maximales', numeric: true),
                  ],
                  SwitchListTile(
                    key: const ValueKey('super-text-setting-enabled'),
                    title: const Text('Activé'),
                    value: _draft.enabled,
                    onChanged: (value) => setState(
                      () => _draft = _draft.copyWith(enabled: value),
                    ),
                  ),
                  SwitchListTile(
                    key: const ValueKey('super-text-setting-readOnly'),
                    title: const Text('Lecture seule'),
                    value: _draft.readOnly,
                    onChanged: (value) => setState(
                      () => _draft = _draft.copyWith(readOnly: value),
                    ),
                  ),
                ]),
              ),
              StyleEditorSection(
                id: 'text-typography',
                title: 'Typographie',
                icon: Icons.font_download_outlined,
                tag: 'TextStyle',
                child: _group([
                  if (unavailable)
                    Text(
                      'Police indisponible : ${_draft.fontFamily}. Choisissez une police disponible.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
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
                    validator: (_) => unavailable
                        ? 'Choisissez une police disponible.'
                        : null,
                  ),
                  _field(
                    'fontSize',
                    'Taille de police (vide = thème)',
                    numeric: true,
                  ),
                  DropdownButtonFormField<FontWeight>(
                    isExpanded: true,
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
                    isExpanded: true,
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
                      DropdownMenuItem(
                        value: 'italic',
                        child: Text('Italique'),
                      ),
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
                ]),
              ),
              StyleEditorSection(
                id: 'text-color',
                title: 'Couleur',
                icon: Icons.palette_outlined,
                tag: 'color',
                child: _group([
                  styleColorTile(
                    'Couleur du texte',
                    RegExp(r'^[0-9a-fA-F]{8}$')
                            .hasMatch(_fields['color']!.text.trim())
                        ? Color(
                            int.parse(_fields['color']!.text.trim(), radix: 16),
                          )
                        : widget.textStyle.color ??
                              Theme.of(context).colorScheme.onSurface,
                    (color) => setState(() {
                      _fields['color']!.text = color
                          .toARGB32()
                          .toRadixString(16)
                          .padLeft(8, '0');
                    }),
                    key: const ValueKey('super-text-color-picker'),
                  ),
                  _field('color', 'Couleur AARRGGBB (vide = parent)'),
                  TextButton(
                    key: const ValueKey('super-text-inherit-color'),
                    onPressed: () => setState(() => _fields['color']!.clear()),
                    child: const Text('Utiliser la couleur du parent'),
                  ),
                ]),
              ),
              StyleEditorSection(
                id: 'text-spacing',
                title: 'Alignement et espacement',
                icon: Icons.format_align_left,
                tag: 'textAlign · height',
                child: _group([
                  DropdownButtonFormField<TextAlign>(
                    isExpanded: true,
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
                ]),
              ),
            ],
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
