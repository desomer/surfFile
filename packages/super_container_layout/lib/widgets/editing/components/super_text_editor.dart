import 'dart:math' as math;
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../models/super_text_config.dart';
import '../../../models/super_text_field_config.dart';
import '../../components/super_text_field.dart';
import '../../../models/json_text_binding.dart';
import '../../../services/json_list_scope.dart';
import '../../../services/json_repository_scope.dart';
import '../../../services/json_repository_store.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../dialogs/editor_dialog.dart';
import '../repositories/repository_binding_fields.dart';
import '../styles/style_editor_panel.dart';
import 'super_text_field_settings.dart';

Future<SuperTextConfig?> showSuperTextEditor({
  required BuildContext context,
  required SuperTextConfig config,
  required List<String> availableFontFamilies,
  bool allowBinding = true,
  ValueChanged<SuperTextConfig>? onPreviewChanged,
}) async {
  final width = ValueNotifier(StyleEditorPanel.preferredDense ? 680.0 : 1080.0);
  final textStyle = DefaultTextStyle.of(context).style;
  final repositories = JsonRepositoryScope.maybeOf(context);
  final listScope = JsonListScope.maybeOf(context);
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
        repositories: repositories,
        listScope: listScope,
        allowBinding: allowBinding,
        onPreviewChanged: onPreviewChanged,
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
    required this.repositories,
    required this.listScope,
    required this.allowBinding,
    required this.onPreviewChanged,
  });
  final SuperTextConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding;
  final ValueChanged<SuperTextConfig>? onPreviewChanged;

  @override
  State<_SuperTextEditor> createState() => _SuperTextEditorState();
}

class _SuperTextEditorState extends State<_SuperTextEditor> {
  final _form = GlobalKey<FormState>();
  final _fieldSettings = GlobalKey<SuperTextFieldSettingsState>();
  late SuperTextFieldConfig _fieldConfig;
  String? _fieldError;
  late SuperTextConfig _draft;
  late final Map<String, TextEditingController> _fields;
  late bool _dense = StyleEditorPanel.preferredDense;
  final _previewText = TextEditingController();
  List<JsonRepositoryEntry> _repositories = [];
  String? _repositoryId;
  bool _inheritRepository = false;
  String? _repositoryError;
  bool _loadingRepositories = false;
  bool _validating = false;
  SuperTextConfig? _lastPreview;
  String? _liveError;

  SuperTextConfig _configuration(
    SuperTextFieldConfig field,
    JsonTextBinding? binding,
  ) {
    double? number(String key) {
      final text = _fields[key]!.text.trim();
      if (text.isEmpty) return null;
      final value = double.tryParse(text.replaceAll(',', '.'));
      if (value == null) {
        throw const FormatException('Valeur numérique invalide.');
      }
      return value;
    }

    final min = _draft.mode == SuperTextMode.display
        ? _draft.minLines
        : int.tryParse(_fields['minLines']!.text);
    final max = int.tryParse(_fields['maxLines']!.text);
    if (!_draft.obscureText && (min == null || max == null)) {
      throw const FormatException('Nombre de lignes invalide.');
    }
    final color = _fields['color']!.text.trim();
    if (color.isNotEmpty && !RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(color)) {
      throw const FormatException('Couleur AARRGGBB à 8 chiffres requise.');
    }
    if (_draft.fontFamily != null &&
        !widget.availableFontFamilies.contains(_draft.fontFamily)) {
      throw const FormatException('Choisissez une police disponible.');
    }
    final result = _draft.copyWith(
      field: field,
      binding: binding,
      clearBinding: binding == null,
      initialText: _draft.obscureText ? '' : _fields['initialText']!.text,
      label: _fields['label']!.text,
      placeholder: _fields['placeholder']!.text,
      minLines: _draft.obscureText
          ? 1
          : _draft.mode == SuperTextMode.display && max != null
          ? math.min(min!, max)
          : min,
      maxLines: _draft.obscureText ? 1 : max,
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
    return result;
  }

  void _schedulePreview() {
    if (widget.onPreviewChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      try {
        final binding = _binding;
        final config = _configuration(
          _draft.mode == SuperTextMode.input
              ? _fieldSettings.currentState?.value() ?? _fieldConfig
              : _fieldConfig,
          binding,
        );
        if (_liveError != null) setState(() => _liveError = null);
        if (_lastPreview != config) {
          _lastPreview = config;
          widget.onPreviewChanged!(config);
        }
      } on FormatException catch (error) {
        if (_liveError != error.message) {
          setState(() => _liveError = error.message);
        }
      } on ArgumentError {
        const message =
            'Réglages du texte invalides : vérifiez les lignes et les dimensions.';
        if (_liveError != message) setState(() => _liveError = message);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _draft = widget.config;
    _fieldConfig = _draft.field;
    _repositoryId = _draft.binding?.repositoryId;
    _inheritRepository =
        _draft.binding != null && _draft.binding!.repositoryId == null;
    _fields = {
      'initialText': TextEditingController(text: _draft.initialText),
      'repositoryPath': TextEditingController(text: _draft.binding?.path ?? ''),
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
    if (widget.repositories != null) _loadRepositories();
  }

  Future<void> _loadRepositories() async {
    setState(() {
      _loadingRepositories = true;
      _repositoryError = null;
    });
    try {
      final entries = await widget.repositories!.catalog();
      if (mounted) setState(() => _repositories = entries);
    } on FormatException catch (error) {
      if (mounted) setState(() => _repositoryError = error.message);
    } on FileSystemException {
      if (mounted) {
        setState(
          () => _repositoryError = 'Impossible de charger les repositories.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingRepositories = false);
    }
  }

  bool get _bound => _repositoryId != null || _inheritRepository;

  JsonTextBinding? get _binding => _bound
      ? JsonTextBinding(
          repositoryId: _repositoryId,
          path: _fields['repositoryPath']!.text,
        )
      : null;

  int get _listDepth => widget.listScope?.indices.length ?? 0;

  Widget _repositorySettings() {
    final available = widget.allowBinding && widget.repositories != null;
    final inheritable = widget.listScope != null || _inheritRepository;
    final missing =
        _repositoryId != null &&
        !_repositories.any((entry) => entry.id == _repositoryId);
    return _group([
      if (!widget.allowBinding)
        const Text('La liaison nécessite le contrôleur interne de SuperText.'),
      if (widget.repositories == null)
        const Text('Service de repositories indisponible.'),
      DropdownButtonFormField<String>(
        key: ValueKey('super-text-repository-$_repositoryId'),
        initialValue: _inheritRepository
            ? inheritedRepositoryValue
            : _repositoryId ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Repository'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Sans liaison')),
          if (inheritable)
            const DropdownMenuItem(
              value: inheritedRepositoryValue,
              child: Text('Hérité de la liste englobante'),
            ),
          for (final entry in _repositories)
            DropdownMenuItem(
              value: entry.id,
              child: Text(
                '${entry.name} (${entry.id})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (missing)
            DropdownMenuItem(
              value: _repositoryId,
              child: const Text('Repository indisponible'),
            ),
        ],
        onChanged: _loadingRepositories || _validating
            ? null
            : (value) {
                if (!available && value != '') return;
                setState(() {
                  _inheritRepository = value == inheritedRepositoryValue;
                  _repositoryId = value == '' || _inheritRepository
                      ? null
                      : value;
                  _repositoryError = null;
                });
              },
      ),
      TextFormField(
        key: const ValueKey('super-text-repository-path'),
        controller: _fields['repositoryPath'],
        enabled: available && _bound && !_validating,
        decoration: InputDecoration(
          labelText: 'Chemin d’attribut',
          hintText: _listDepth == 0
              ? 'client.nom ou clients[0].nom'
              : 'clients[?].nom',
          helperText: _listDepth == 0
              ? '[?] = ligne sélectionnée du tableau'
              : 'Chaque [?] reçoit l’indice d’une liste englobante '
                    '($_listDepth disponible(s)), puis la ligne sélectionnée.',
        ),
        validator: (value) {
          if (!_bound) return null;
          try {
            JsonAttributePath(value ?? '');
            return null;
          } on FormatException catch (error) {
            return error.message;
          }
        },
      ),
      const Text(
        'Liaison bidirectionnelle. Les attributs absents deviennent des chaînes '
        'à la saisie ; les indices de tableau doivent déjà exister. '
        'Les modifications sont enregistrées automatiquement dans le JSON.',
      ),
      if (_draft.obscureText && _bound)
        const Text(
          'Attention : le mot de passe sera enregistré en clair sur disque.',
          key: ValueKey('super-text-repository-plaintext-warning'),
        ),
      if (_loadingRepositories) const Text('Chargement des repositories…'),
      if (_validating) const LinearProgressIndicator(),
      if (_repositoryError != null)
        Text(
          _repositoryError!,
          key: const ValueKey('super-text-repository-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      TextButton.icon(
        onPressed: available && !_loadingRepositories && !_validating
            ? _loadRepositories
            : null,
        icon: const Icon(Icons.refresh),
        label: const Text('Recharger les repositories'),
      ),
    ]);
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
            if (key == 'maxLines' &&
                _draft.mode == SuperTextMode.input &&
                min != null &&
                number < min) {
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

  Future<void> _editPropertyBinding(
    SuperTextProperty property,
    String label,
  ) async {
    final result = await showRepositoryBindingDialog(
      context: context,
      title: 'Lier $label',
      keyPrefix: 'super-text-property-${property.name}',
      pathHint: 'client.${property.name}',
      binding: _draft.propertyBindings[property],
      store: widget.repositories,
      listScope: widget.listScope,
      helper: 'Lecture seule : la valeur du repository remplace ce paramètre.',
    );
    if (result == null || !mounted) return;
    final bindings = Map<SuperTextProperty, JsonTextBinding>.of(
      _draft.propertyBindings,
    );
    if (result.binding == null) {
      bindings.remove(property);
    } else {
      bindings[property] = result.binding!;
    }
    setState(() => _draft = _draft.copyWith(propertyBindings: bindings));
  }

  Widget _withBinding(SuperTextProperty property, String label, Widget child) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: child),
          IconButton(
            key: ValueKey('super-text-bind-${property.name}'),
            tooltip: _draft.propertyBindings.containsKey(property)
                ? 'Modifier la liaison de $label'
                : 'Lier $label à un repository',
            visualDensity: VisualDensity.compact,
            onPressed: !widget.allowBinding || widget.repositories == null
                ? null
                : () => _editPropertyBinding(property, label),
            icon: Icon(
              _draft.propertyBindings.containsKey(property)
                  ? Icons.link
                  : Icons.add_link,
              size: 18,
            ),
          ),
        ],
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
    final previewConfig = _draft.copyWith(
      field: _fieldConfig,
      initialText: _draft.obscureText ? '' : text,
      label: label,
      placeholder: placeholder,
      minLines: _draft.obscureText ? 1 : min,
      maxLines: _draft.obscureText ? 1 : max,
    );
    String? previewError;
    try {
      _fieldConfig.validateFor(
        obscureText: previewConfig.obscureText,
        maxLines: previewConfig.maxLines,
      );
    } on FormatException catch (error) {
      previewError = error.message;
    }
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
                  ? previewError != null
                        ? Text(
                            previewError,
                            style: TextStyle(color: scheme.error),
                          )
                        : SuperTextField(
                            config: previewConfig,
                            controller: _previewText,
                            readOnly: true,
                            style: style,
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
    _schedulePreview();
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
          onChanged: () => setState(() {}),
          child: SuperTextFieldSettings(
            key: _fieldSettings,
            value: _draft.field,
            onChanged: (value) => setState(() {
              _fieldConfig = value;
              _fieldError = null;
            }),
            builder: (fieldSections) => StyleEditorPanel(
              label: 'Configurer le texte',
              dense: _dense,
              onDenseChanged: (value) => setState(() {
                _dense = value;
                widget.onWidthChanged(value ? 680 : 1080);
              }),
              preview: _preview(unavailable),
              sections: [
                StyleEditorSection(
                  id: 'text-repository',
                  title: 'Repository',
                  icon: Icons.storage_outlined,
                  tag: 'repository · path',
                  child: _repositorySettings(),
                ),
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
                    if (!_draft.obscureText && !_bound)
                      _field('initialText', 'Texte initial'),
                    _withBinding(
                      SuperTextProperty.label,
                      'le label',
                      _field('label', 'Label'),
                    ),
                    _withBinding(
                      SuperTextProperty.placeholder,
                      'le placeholder',
                      _field('placeholder', 'Placeholder'),
                    ),
                    const Text(
                      'Sans liaison, changer le mode ou le texte initial '
                      'réinitialise la valeur dans l’application. '
                      'Avec une liaison, le repository fournit la valeur.',
                    ),
                  ]),
                ),
                StyleEditorSection(
                  id: 'text-behavior',
                  title: 'Comportement',
                  icon: Icons.tune,
                  tag: _draft.mode == SuperTextMode.input
                      ? 'enabled · readOnly'
                      : 'obscureText · maxLines',
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
                      if (_draft.mode == SuperTextMode.input)
                        _field('minLines', 'Lignes minimales', numeric: true),
                      _field('maxLines', 'Lignes maximales', numeric: true),
                    ],
                    if (_draft.mode == SuperTextMode.input)
                      SwitchListTile(
                        key: const ValueKey('super-text-setting-enabled'),
                        title: const Text('Activé'),
                        value: _draft.enabled,
                        onChanged: (value) => setState(
                          () => _draft = _draft.copyWith(enabled: value),
                        ),
                      ),
                    if (_draft.mode == SuperTextMode.input)
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
                    _withBinding(
                      SuperTextProperty.fontFamily,
                      'la police',
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
                    ),
                    _withBinding(
                      SuperTextProperty.fontSize,
                      'la taille de police',
                      _field(
                        'fontSize',
                        'Taille de police (vide = thème)',
                        numeric: true,
                      ),
                    ),
                    _withBinding(
                      SuperTextProperty.fontWeight,
                      'la graisse',
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
                    ),
                    _withBinding(
                      SuperTextProperty.italic,
                      'le style italique',
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
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('Normal'),
                          ),
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
                              int.parse(
                                _fields['color']!.text.trim(),
                                radix: 16,
                              ),
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
                    _withBinding(
                      SuperTextProperty.color,
                      'la couleur',
                      _field('color', 'Couleur AARRGGBB (vide = parent)'),
                    ),
                    TextButton(
                      key: const ValueKey('super-text-inherit-color'),
                      onPressed: () =>
                          setState(() => _fields['color']!.clear()),
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
                    _withBinding(
                      SuperTextProperty.textAlign,
                      'l’alignement',
                      DropdownButtonFormField<TextAlign>(
                        isExpanded: true,
                        initialValue: _draft.textAlign,
                        decoration: const InputDecoration(
                          labelText: 'Alignement',
                        ),
                        items: [
                          for (final align in TextAlign.values)
                            DropdownMenuItem(
                              value: align,
                              child: Text(align.name),
                            ),
                        ],
                        onChanged: (align) {
                          if (align != null) {
                            setState(
                              () => _draft = _draft.copyWith(textAlign: align),
                            );
                          }
                        },
                      ),
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
                if (_draft.mode == SuperTextMode.input) ...fieldSections,
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_liveError != null)
          Text(
            _liveError!,
            key: const ValueKey('super-text-live-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_fieldError != null)
          Text(
            _fieldError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextButton(
          onPressed: _validating ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _validating
              ? null
              : () async {
                  if (!_form.currentState!.validate()) return;
                  if (_draft.mode == SuperTextMode.input &&
                      _fieldSettings.currentState?.validate() == false) {
                    return;
                  }
                  final field = _draft.mode == SuperTextMode.input
                      ? _fieldSettings.currentState?.value() ?? _fieldConfig
                      : _fieldConfig;
                  try {
                    field.validateFor(
                      obscureText: _draft.obscureText,
                      maxLines: _draft.obscureText
                          ? 1
                          : int.parse(_fields['maxLines']!.text),
                    );
                  } on FormatException catch (error) {
                    setState(() => _fieldError = error.message);
                    return;
                  }
                  final binding = _binding;
                  if (binding != null) {
                    if (!widget.allowBinding || widget.repositories == null) {
                      setState(
                        () => _repositoryError = 'La liaison nécessite le service et un contrôleur interne.',
                      );
                      return;
                    }
                    setState(() {
                      _validating = true;
                      _repositoryError = null;
                    });
                    try {
                      final scope = widget.listScope;
                      // A template row has no element to read yet.
                      if (!(scope?.placeholder ?? false)) {
                        final resolved = JsonListScope.resolveSelected(
                          binding,
                          scope,
                          widget.repositories,
                        ).binding;
                        // Without selected row, only the path is checked.
                        if (resolved != null) {
                          await widget.repositories!.readAttribute(resolved);
                        }
                      }
                    } on FormatException catch (error) {
                      if (mounted) {
                        setState(() => _repositoryError = error.message);
                      }
                      return;
                    } on FileSystemException {
                      if (mounted) {
                        setState(
                          () => _repositoryError =
                              'Impossible de lire le repository.',
                        );
                      }
                      return;
                    } finally {
                      if (mounted) setState(() => _validating = false);
                    }
                    if (!mounted) return;
                  }
                  final result = _configuration(field, binding);
                  if (!context.mounted) return;
                  Navigator.of(context).pop(result);
                },
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}
