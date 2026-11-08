/// Fenêtre d'édition complète d'un composant [SuperValue].
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/automatic_state.dart';
import '../../../models/json_text_binding.dart';
import '../../../models/super_text_field_config.dart';
import '../../../models/super_value_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../components/super_text_field.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../repositories/repository_binding_fields.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../styles/style_editor_panel.dart';
import 'shared/component_state_editor_host.dart';
import 'shared/component_typography_controls.dart';
import 'shared/editor_color_fields.dart';
import 'shared/editor_segmented_field.dart';
import 'super_text_field_settings.dart';

final _valueStateAdapter =
    ComponentStateAdapter<
      SuperValueConfig,
      ValueConfigStates,
      ValueConfigOverride,
      ValueStateProperty
    >(
      stateKeyPrefix: 'value-state',
      emptyStates: ValueConfigStates.new,
      getStates: (root) => root.states,
      withStates: (root, states) =>
          root.copyWith(states: states, clearStates: states == null),
      clearStates: (config) => config.copyWith(clearStates: true),
      getNamed: (s) => s.named,
      getNamedProperties: (s) => s.namedProperties,
      getHover: (s) => s.hover,
      getSelected: (s) => s.selected,
      getAutomatic: (s) => s.automatic,
      getOrder: (s) => s.order,
      getBinding: (s) => s.binding,
      copyStates: (
        s, {
        named,
        namedProperties,
        hover,
        clearHover = false,
        selected,
        clearSelected = false,
        automatic,
        order,
        binding,
        clearBinding = false,
      }) => s.copyWith(
        named: named,
        namedProperties: namedProperties,
        hover: hover,
        clearHover: clearHover,
        selected: selected,
        clearSelected: clearSelected,
        automatic: automatic,
        order: order,
        binding: binding,
        clearBinding: clearBinding,
      ),
      createOverride: (config, [properties]) => ValueConfigOverride(
        config: config,
        properties: properties ?? const {},
      ),
      getOverrideConfig: (override) => override.config,
      getOverrideProperties: (override) => override.properties,
      editOverride: (previous, nextLeaf) => previous.edited(nextLeaf),
      resolvePreview: (
        states,
        root, {
        name,
        required isHovered,
        required isSelected,
        required activeStates,
      }) => states.resolve(
        root,
        name: name,
        isHovered: isHovered,
        isSelected: isSelected,
        activeStates: activeStates,
      ),
      validateName: (name) {
        try {
          ValueConfigStates(named: {name: const SuperValueConfig()});
          return null;
        } on FormatException catch (e) {
          return e.message;
        }
      },
      propertyLabels: {
        for (final property in ValueStateProperty.values)
          property: property.label,
      },
      validateRoot: (root, allowBinding) {
        root.validate();
        if (!allowBinding) {
          final leaves = [
            root,
            ...?root.states?.named.values,
            if (root.states?.hover case final value?) value.config,
            if (root.states?.selected case final value?) value.config,
            ...?root.states?.automatic.values.map((value) => value.config),
          ];
          if (leaves.any((leaf) => leaf.binding != null)) {
            throw const FormatException(
              'La liaison nécessite le contrôleur interne de Value.',
            );
          }
        }
      },
      availableStatesBuilder: ({
        required leaf,
        required states,
        required allowSelected,
        required allowContentHover,
      }) => {
        AutomaticState.hover,
        if (allowSelected) AutomaticState.selected,
        if (allowContentHover) AutomaticState.contentHover,
        if (leaf.mode == SuperValueMode.input) ...{
          AutomaticState.focused,
          AutomaticState.disabled,
          AutomaticState.readOnly,
        },
      },
    );

/// Ouvre la boîte de dialogue d'édition complète d'un composant `SuperValue`.
///
/// Retourne la nouvelle configuration [SuperValueConfig] validée lorsque
/// l'utilisateur clique sur « Appliquer », ou `null` en cas d'annulation.
Future<SuperValueConfig?> showSuperValueEditor({
  required BuildContext context,
  required SuperValueConfig config,
  required List<String> availableFontFamilies,
  bool allowBinding = true,
  ValueChanged<SuperValueConfig>? onPreviewChanged,
  String? activeState,
  String? stateError,
  bool isHovered = false,
  bool isSelected = false,
  bool allowContentHover = false,
  Set<AutomaticState> activeAutomatic = const {},
}) => showStatefulComponentEditorDialog(
  context: context,
  config: config,
  adapter: _valueStateAdapter,
  allowBinding: allowBinding,
  onPreviewChanged: onPreviewChanged,
  activeState: activeState,
  stateError: stateError,
  isHovered: isHovered,
  isSelected: isSelected,
  allowContentHover: allowContentHover,
  activeAutomatic: activeAutomatic,
  leafBuilder: ({
    required key,
    required initialTab,
    required dimensionDelegate,
    required config,
    required onWidthChanged,
    required repositories,
    required listScope,
    required textStyle,
    required onPreviewChanged,
    required onSave,
    required header,
  }) => _SuperValueEditor(
    key: key,
    initialTab: initialTab,
    dimensionDelegate: dimensionDelegate,
    config: config,
    availableFontFamilies: availableFontFamilies,
    textStyle: textStyle,
    onWidthChanged: onWidthChanged,
    repositories: repositories,
    listScope: listScope,
    allowBinding: allowBinding,
    onPreviewChanged: onPreviewChanged,
    onSave: onSave,
    header: header,
  ),
);

/// Formulaire d'édition d'une configuration unitaire [SuperValueConfig]
/// (état de base ou surcharge d'un état spécifique).
class _SuperValueEditor extends StatefulWidget {
  /// Crée le formulaire d'édition pour une feuille [config] de `SuperValue`.
  const _SuperValueEditor({
    required this.initialTab,
    required this.dimensionDelegate,
    required this.config,
    required this.availableFontFamilies,
    required this.textStyle,
    required this.onWidthChanged,
    required this.repositories,
    required this.listScope,
    required this.allowBinding,
    required this.onPreviewChanged,
    this.header,
    this.onSave,
    super.key,
  });
  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;
  final SuperValueConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding;
  final ValueChanged<SuperValueConfig>? onPreviewChanged;
  final Widget? header;
  final SuperValueConfig Function(SuperValueConfig config)? onSave;

  /// Crée l'état mutable du formulaire [_SuperValueEditor].
  @override
  State<_SuperValueEditor> createState() => _SuperValueEditorState();
}

/// État du formulaire [_SuperValueEditor] gérant les contrôleurs de saisie,
/// la sélection du repository, les liaisons de propriétés individuelles,
/// l'aperçu temps réel et la validation finale.
class _SuperValueEditorState extends State<_SuperValueEditor>
    implements ComponentLeafCapable<SuperValueConfig> {
  final _form = GlobalKey<FormState>();
  final _fieldSettings = GlobalKey<SuperTextFieldSettingsState>();
  late SuperTextFieldConfig _fieldConfig;
  String? _fieldError;
  late SuperValueConfig _draft;
  late final Map<String, TextEditingController> _fields;
  final _previewText = TextEditingController();
  List<JsonRepositoryEntry> _repositories = [];
  String? _repositoryId;
  bool _inheritRepository = false;
  String? _repositoryError;
  bool _loadingRepositories = false;
  bool _validating = false;
  SuperValueConfig? _lastPreview;
  String? _liveError;

  /// Indique si les sections de réglages propres au `SuperTextField` doivent
  /// être affichées (uniquement en mode saisie `input` pour une valeur textuelle
  /// non booléenne).
  bool get _hasFieldSettings =>
      _draft.mode == SuperValueMode.input && !_draft.kind.isBoolean;

  @override
  SuperValueConfig? capture() {
    if (!_form.currentState!.validate() ||
        (_hasFieldSettings &&
            _fieldSettings.currentState?.validate() == false)) {
      return null;
    }
    try {
      return _configuration(
        _hasFieldSettings
            ? _fieldSettings.currentState?.value() ?? _fieldConfig
            : _fieldConfig,
        _binding,
      );
    } on FormatException catch (e) {
      setState(() => _liveError = e.message);
    } on ArgumentError {
      setState(() => _liveError = 'Réglages de la valeur invalides.');
    }
    return null;
  }

  /// Assemble et valide une instance de [SuperValueConfig] à partir du brouillon
  /// [_draft], des contrôleurs de texte [_fields], de la configuration de champ
  /// [field] et de la liaison repository [binding].
  ///
  /// Lève une [FormatException] si une valeur numérique, un nombre de lignes,
  /// un code couleur hexadécimal ou une famille de police est invalide.
  SuperValueConfig _configuration(
    SuperTextFieldConfig field,
    JsonTextBinding? binding,
  ) {
    /// Convertit le texte du champ [key] en `double`, ou retourne `null` s'il
    /// est vide. Lève une [FormatException] si le format numérique est invalide.
    double? number(String key) {
      final text = _fields[key]!.text.trim();
      if (text.isEmpty) return null;
      final value = double.tryParse(text.replaceAll(',', '.'));
      if (value == null) {
        throw const FormatException('Valeur numérique invalide.');
      }
      return value;
    }

    final min = _draft.mode == SuperValueMode.display || _draft.kind.isBoolean
        ? _draft.minLines
        : int.tryParse(_fields['minLines']!.text);
    final max = _draft.kind.isBoolean
        ? _draft.maxLines
        : int.tryParse(_fields['maxLines']!.text);
    if (!_draft.obscureText &&
        !_draft.kind.isBoolean &&
        (min == null || max == null)) {
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
      minLines: _draft.obscureText || _draft.kind.isBoolean
          ? 1
          : _draft.mode == SuperValueMode.display && max != null
          ? math.min(min!, max)
          : min,
      maxLines: _draft.obscureText || _draft.kind.isBoolean ? 1 : max,
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

  /// Planifie après le rendu de la frame courante la construction de la
  /// configuration d'aperçu et appelle [widget.onPreviewChanged] si la
  /// configuration a changé depuis le dernier aperçu ([_lastPreview]).
  ///
  /// Capture et affiche dans [_liveError] les éventuelles erreurs de format ou
  /// d'arguments saisies en cours de route.
  void _schedulePreview() {
    if (widget.onPreviewChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      try {
        final binding = _binding;
        final config = _configuration(
          _hasFieldSettings
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
            'Réglages de la valeur invalides : vérifiez les lignes et les dimensions.';
        if (_liveError != message) setState(() => _liveError = message);
      }
    });
  }

  /// Initialise le brouillon [_draft], l'état de la liaison repository, tous
  /// les [TextEditingController] des champs du formulaire ([_fields]), puis
  /// lance le chargement de la liste des repositories disponibles.
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

  /// Charge de manière asynchrone le catalogue des repositories JSON depuis
  /// [widget.repositories] afin de peupler la liste déroulante de liaison.
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

  /// Indique si le composant est actuellement lié à un repository (explicite
  /// via [_repositoryId] ou hérité d'une liste englobante via [_inheritRepository]).
  bool get _bound => _repositoryId != null || _inheritRepository;

  /// Construit l'objet [JsonTextBinding] correspondant à la sélection actuelle
  /// du repository et du chemin d'attribut, ou `null` si aucune liaison n'est active.
  JsonTextBinding? get _binding => _bound
      ? JsonTextBinding(
          repositoryId: _repositoryId,
          path: _fields['repositoryPath']!.text,
        )
      : null;

  /// Retourne le nombre de listes englobantes actives autour de ce composant
  /// (déterminant le nombre de jokers `[?]` résolus par contexte de ligne).
  int get _listDepth => widget.listScope?.indices.length ?? 0;

  /// Construit les contrôles de la section « Repository » permettant de choisir
  /// le repository JSON cible, de saisir le chemin d'attribut et de recharger
  /// la liste des repositories.
  Widget _repositorySettings() {
    final available = widget.allowBinding && widget.repositories != null;
    final inheritable = widget.listScope != null || _inheritRepository;
    final missing =
        _repositoryId != null &&
        !_repositories.any((entry) => entry.id == _repositoryId);
    return _group([
      if (!widget.allowBinding)
        const Text('La liaison nécessite le contrôleur interne de Value.'),
      if (widget.repositories == null)
        const Text('Service de repositories indisponible.'),
      DropdownButtonFormField<String>(
        key: ValueKey('super-value-repository-$_repositoryId'),
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
        key: const ValueKey('super-value-repository-path'),
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
        '(ou booléens) à la saisie ; les indices de tableau doivent déjà exister. '
        'Les modifications sont enregistrées automatiquement dans le JSON.',
      ),
      if (_draft.obscureText && _bound)
        const Text(
          'Attention : le mot de passe sera enregistré en clair sur disque.',
          key: ValueKey('super-value-repository-plaintext-warning'),
        ),
      if (_loadingRepositories) const Text('Chargement des repositories…'),
      if (_validating) const LinearProgressIndicator(),
      if (_repositoryError != null)
        Text(
          _repositoryError!,
          key: const ValueKey('super-value-repository-error'),
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

  /// Libère le contrôleur de texte d'aperçu ([_previewText]) ainsi que tous les
  /// contrôleurs de champs du formulaire ([_fields]).
  @override
  void dispose() {
    _previewText.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  /// Construit un [TextFormField] standardisé relié au contrôleur `_fields[key]`
  /// avec validation intégrée (entiers positifs pour `minLines`/`maxLines`,
  /// nombres flottants pour les champs `numeric`, et format hexadécimal 8
  /// caractères pour `color`).
  ///
  /// Ajuste aussi automatiquement `maxLines` lorsque l'utilisateur saisit
  /// plusieurs lignes dans `initialText`.
  Widget _field(String key, String label, {bool numeric = false}) =>
      TextFormField(
        key: ValueKey('super-value-setting-$key'),
        controller: _fields[key],
        minLines: key == 'initialText' ? 1 : null,
        maxLines: key == 'initialText' ? 3 : 1,
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (value) {
          if (key == 'initialText' &&
              !_draft.obscureText &&
              !_draft.kind.isBoolean) {
            final lines = '\n'.allMatches(value).length + 1;
            final currentMax = int.tryParse(_fields['maxLines']!.text) ?? 1;
            if (lines > currentMax) {
              _fields['maxLines']!.text = '$lines';
            }
          }
          setState(() {});
        },
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : key == 'initialText'
            ? TextInputType.multiline
            : TextInputType.text,
        validator: (text) {
          final value = (text ?? '').trim();
          if (key == 'minLines' || key == 'maxLines') {
            final number = int.tryParse(value);
            if (number == null || number < 1) return 'Entier positif requis.';
            final min = int.tryParse(_fields['minLines']!.text);
            if (key == 'maxLines' &&
                _draft.mode == SuperValueMode.input &&
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

  EditablePropertyBindingScope<SuperValueProperty> get _bindingScope =>
      EditablePropertyBindingScope<SuperValueProperty>(
        context: context,
        componentPrefix: 'super-value',
        allowBinding: widget.allowBinding,
        repositories: widget.repositories,
        listScope: widget.listScope,
        bindings: _draft.propertyBindings,
        onBindingsChanged: (bindings) =>
            setState(() => _draft = _draft.copyWith(propertyBindings: bindings)),
      );

  Widget _withBinding(
    SuperValueProperty property,
    String label,
    Widget child,
  ) => _bindingScope.wrap(property, label, child);

  Widget _group(List<Widget> children) => buildEditorFieldGroup(children);

  /// Construit la carte d'aperçu en direct du `SuperValue` (en mode `Text`,
  /// `SuperTextField`, `Checkbox` ou `Switch`) reflétant les réglages actuels
  /// du formulaire sans impacter la donnée réelle de l'application.
  Widget _preview(bool unavailable) {
    /// Lit et valide localement une valeur numérique du champ [key] pour
    /// l'appliquer au style de l'aperçu sans lever d'exception.
    double? number(String key, {bool positive = true}) {
      final value = double.tryParse(_fields[key]!.text.replaceAll(',', '.'));
      return value != null && value.isFinite && (!positive || value > 0)
          ? value
          : null;
    }

    final color = _fields['color']!.text.trim();
    final parsedColor = RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(color)
        ? Color(int.parse(color, radix: 16))
        : null;
    final style = widget.textStyle.copyWith(
      fontFamily: unavailable ? null : _draft.fontFamily,
      fontSize: number('fontSize'),
      fontWeight: _draft.fontWeight,
      fontStyle: _draft.italic == null
          ? null
          : _draft.italic!
          ? FontStyle.italic
          : FontStyle.normal,
      color: parsedColor,
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
      minLines: _draft.obscureText || _draft.kind.isBoolean ? 1 : min,
      maxLines: _draft.obscureText || _draft.kind.isBoolean ? 1 : max,
    );
    String? previewError;
    if (!_draft.kind.isBoolean) {
      try {
        _fieldConfig.validateFor(
          obscureText: previewConfig.obscureText,
          maxLines: previewConfig.maxLines,
        );
      } on FormatException catch (error) {
        previewError = error.message;
      }
    }
    final Widget previewBody;
    if (_draft.kind.isBoolean) {
      final align = switch (_draft.textAlign) {
        TextAlign.center => MainAxisAlignment.center,
        TextAlign.end || TextAlign.right => MainAxisAlignment.end,
        _ => MainAxisAlignment.start,
      };
      final control = _draft.kind == SuperValueKind.checkbox
          ? Checkbox(
              value: _draft.initialBool,
              activeColor: parsedColor,
              onChanged:
                  _draft.mode == SuperValueMode.input &&
                      _draft.enabled &&
                      !_draft.readOnly
                  ? (_) {}
                  : null,
            )
          : Switch(
              value: _draft.initialBool,
              activeThumbColor: parsedColor,
              onChanged:
                  _draft.mode == SuperValueMode.input &&
                      _draft.enabled &&
                      !_draft.readOnly
                  ? (_) {}
                  : null,
            );
      previewBody = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: align,
        children: [
          control,
          if (label.isNotEmpty)
            Flexible(
              child: Text(
                label,
                style: style,
                textAlign: _draft.textAlign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      );
    } else if (_draft.mode == SuperValueMode.input) {
      previewBody = previewError != null
          ? Text(previewError, style: TextStyle(color: scheme.error))
          : SuperTextField(
              config: previewConfig,
              controller: _previewText,
              readOnly: true,
              style: style,
            );
    } else if (label.isEmpty) {
      previewBody = display;
    } else {
      previewBody = InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: _draft.enabled,
          border: InputBorder.none,
          isDense: true,
        ),
        child: display,
      );
    }
    return Card(
      key: const ValueKey('super-value-preview'),
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
              child: previewBody,
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

  Future<bool> _handleApply() async {
    if (_form.currentState != null && !_form.currentState!.validate()) {
      return false;
    }
    if (_hasFieldSettings && _fieldSettings.currentState?.validate() == false) {
      return false;
    }
    final field = _hasFieldSettings
        ? _fieldSettings.currentState?.value() ?? _fieldConfig
        : _fieldConfig;
    try {
      field.validateFor(
        obscureText: _draft.obscureText,
        maxLines: _draft.obscureText || _draft.kind.isBoolean
            ? 1
            : int.parse(_fields['maxLines']!.text),
      );
    } on FormatException catch (error) {
      setState(() => _fieldError = error.message);
      return false;
    }
    final binding = _binding;
    if (binding != null) {
      if (!widget.allowBinding || widget.repositories == null) {
        setState(() {
          _repositoryError =
              'La liaison nécessite le service et un contrôleur interne.';
        });
        return false;
      }
      setState(() {
        _validating = true;
        _repositoryError = null;
      });
      try {
        final scope = widget.listScope;
        if (!(scope?.placeholder ?? false)) {
          final resolved = JsonListScope.resolveSelected(
            binding,
            scope,
            widget.repositories,
          ).binding;
          if (resolved != null) {
            final attr = await widget.repositories!.readAttribute(resolved);
            if (_draft.kind.isBoolean &&
                attr.value != null &&
                attr.value is! bool) {
              throw const FormatException(
                'L’attribut lié doit être un booléen.',
              );
            }
          }
        }
      } on FormatException catch (error) {
        if (mounted) {
          setState(() => _repositoryError = error.message);
        }
        return false;
      } on FileSystemException {
        if (mounted) {
          setState(
            () => _repositoryError = 'Impossible de lire le repository.',
          );
        }
        return false;
      } finally {
        if (mounted) setState(() => _validating = false);
      }
      if (!mounted) return false;
    }
    SuperValueConfig result;
    try {
      final leaf = _configuration(field, binding);
      result = widget.onSave?.call(leaf) ?? leaf;
    } on FormatException catch (e) {
      setState(() => _liveError = e.message);
      return false;
    } on ArgumentError {
      setState(() => _liveError = 'Combinaison de propriétés invalide.');
      return false;
    }
    if (!context.mounted) return false;
    Navigator.of(context).pop(result);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    _schedulePreview();
    final fonts = widget.availableFontFamilies.toSet().toList();
    final unavailable =
        _draft.fontFamily != null && !fonts.contains(_draft.fontFamily);
    final delegate = widget.dimensionDelegate;

    return EditorStyleWizardDialog(
      dialogKey: const ValueKey('super-value-settings'),
      initialTab: widget.initialTab,
      dimensionDelegate: delegate,
      onWidthChanged: widget.onWidthChanged,
      liveError: _liveError,
      liveErrorKey: const ValueKey('super-value-live-error'),
      secondaryError: _fieldError,
      busy: _validating,
      onApply: _handleApply,
      propertiesBuilder: (context, dense, onDenseChanged) => Form(
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
            label: delegate?.editableLabel ?? 'Configurer la valeur',
            onLabelChanged: delegate?.onLabelChanged,
            dense: dense,
            onDenseChanged: onDenseChanged,
            preview: _preview(unavailable),
            sections: [
                if (widget.header != null)
                  StyleEditorSection(
                    id: 'value-states',
                    title: 'États',
                    icon: Icons.layers_outlined,
                    child: widget.header!,
                  ),
                StyleEditorSection(
                  id: 'value-repository',
                  title: 'Repository',
                  icon: Icons.storage_outlined,
                  tag: 'repository · path',
                  child: _repositorySettings(),
                ),
                StyleEditorSection(
                  id: 'value-content',
                  title: 'Contenu',
                  icon: Icons.text_fields,
                  tag: 'kind · mode · initialText',
                  child: _group([
                    EditorSegmentedField.valueKind(
                      buttonKey: const ValueKey('super-value-setting-kind'),
                      value: _draft.kind,
                      onChanged: (kind) {
                        setState(() {
                          _draft = _draft.copyWith(
                            kind: kind,
                            obscureText: kind.isBoolean
                                ? false
                                : _draft.obscureText,
                          );
                          if (kind.isBoolean) {
                            _fields['minLines']!.text = '1';
                            _fields['maxLines']!.text = '1';
                          }
                        });
                      },
                    ),
                    EditorSegmentedField.valueMode(
                      buttonKey: const ValueKey('super-value-setting-mode'),
                      value: _draft.mode,
                      onChanged: (mode) => setState(
                        () => _draft = _draft.copyWith(
                          mode: mode,
                          obscureText: mode == SuperValueMode.display
                              ? false
                              : _draft.obscureText,
                        ),
                      ),
                    ),
                    if (_draft.kind.isBoolean && !_bound)
                      EditorSwitchTile(
                        tileKey: const ValueKey(
                          'super-value-setting-initialBool',
                        ),
                        title: 'Valeur initiale',
                        value: _draft.initialBool,
                        onChanged: (value) => setState(
                          () => _draft = _draft.copyWith(initialBool: value),
                        ),
                      )
                    else if (!_draft.kind.isBoolean &&
                        !_draft.obscureText &&
                        !_bound)
                      _field('initialText', 'Texte initial'),
                    _withBinding(
                      SuperValueProperty.label,
                      'le label',
                      _field('label', 'Label'),
                    ),
                    if (!_draft.kind.isBoolean)
                      _withBinding(
                        SuperValueProperty.placeholder,
                        'le placeholder',
                        _field('placeholder', 'Placeholder'),
                      ),
                    const Text(
                      'Sans liaison, changer le mode ou la valeur initiale '
                      'réinitialise la valeur dans l’application. '
                      'Avec une liaison, le repository fournit la valeur.',
                    ),
                  ]),
                ),
                StyleEditorSection(
                  id: 'value-behavior',
                  title: 'Comportement',
                  icon: Icons.tune,
                  tag: _draft.mode == SuperValueMode.input
                      ? 'enabled · readOnly'
                      : 'maxLines',
                  child: _group([
                    if (!_draft.kind.isBoolean) ...[
                      if (_draft.mode == SuperValueMode.input)
                        SwitchListTile(
                          key: const ValueKey(
                            'super-value-setting-obscureText',
                          ),
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
                          'Texte masqué. Une seule ligne, sans texte initial sauvegardé.',
                        )
                      else ...[
                        if (_draft.mode == SuperValueMode.input)
                          _field(
                            'minLines',
                            'Nb lignes minimales',
                            numeric: true,
                          ),
                        _field(
                          'maxLines',
                          'Nb lignes maximales',
                          numeric: true,
                        ),
                      ],
                    ],
                    if (_draft.mode == SuperValueMode.input)
                      SwitchListTile(
                        key: const ValueKey('super-value-setting-enabled'),
                        title: const Text('Activé'),
                        value: _draft.enabled,
                        onChanged: (value) => setState(
                          () => _draft = _draft.copyWith(enabled: value),
                        ),
                      ),
                    if (_draft.mode == SuperValueMode.input)
                      SwitchListTile(
                        key: const ValueKey('super-value-setting-readOnly'),
                        title: const Text('Lecture seule'),
                        value: _draft.readOnly,
                        onChanged: (value) => setState(
                          () => _draft = _draft.copyWith(readOnly: value),
                        ),
                      ),
                  ]),
                ),
                StyleEditorSection(
                  id: 'value-typography',
                  title: 'Typographie',
                  icon: Icons.font_download_outlined,
                  tag: 'TextStyle',
                  child: _group(
                    buildComponentTypographyFields(
                      context: context,
                      settingPrefix: 'super-value-setting',
                      bindingScope: _bindingScope,
                      availableFontFamilies: fonts,
                      fontFamily: _draft.fontFamily,
                      onFontFamilyChanged: (font) => setState(
                        () => _draft = _draft.copyWith(
                          fontFamily: font,
                          inheritFontFamily: font == null || font.isEmpty,
                        ),
                      ),
                      fontFamilyProperty: SuperValueProperty.fontFamily,
                      fontSizeField: _field(
                        'fontSize',
                        'Taille de police (vide = thème)',
                        numeric: true,
                      ),
                      fontSizeProperty: SuperValueProperty.fontSize,
                      fontWeight: _draft.fontWeight,
                      onFontWeightChanged: (weight) => setState(
                        () => _draft = _draft.copyWith(
                          fontWeight: weight,
                          inheritFontWeight: weight == null,
                        ),
                      ),
                      fontWeightProperty: SuperValueProperty.fontWeight,
                      italic: _draft.italic,
                      onItalicChanged: ({required italic, required inherit}) =>
                          setState(
                            () => _draft = _draft.copyWith(
                              italic: italic,
                              inheritItalic: inherit,
                            ),
                          ),
                      italicProperty: SuperValueProperty.italic,
                    ),
                  ),
                ),
                StyleEditorSection(
                  id: 'value-color',
                  title: 'Couleur',
                  icon: Icons.palette_outlined,
                  tag: 'color',
                  child: _group([
                    styleColorTile(
                      'Couleur de la valeur',
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
                        _fields['color']!.text = formatEditorColorHex(color);
                      }),
                      key: const ValueKey('super-value-color-picker'),
                      onClear: () => setState(() => _fields['color']!.clear()),
                    ),
                    _withBinding(
                      SuperValueProperty.color,
                      'la couleur',
                      _field('color', 'Couleur AARRGGBB (vide = parent)'),
                    ),
                    TextButton(
                      key: const ValueKey('super-value-inherit-color'),
                      onPressed: () =>
                          setState(() => _fields['color']!.clear()),
                      child: const Text('Utiliser la couleur du parent'),
                    ),
                  ]),
                ),
                StyleEditorSection(
                  id: 'value-spacing',
                  title: 'Alignement et espacement',
                  icon: Icons.format_align_left,
                  tag: 'textAlign · height',
                  child: _group([
                    _withBinding(
                      SuperValueProperty.textAlign,
                      'l’alignement',
                      ComponentTextAlignSegmentField(
                        settingPrefix: 'super-value-setting',
                        textAlign: _draft.textAlign,
                        onChanged: (align) => setState(
                          () => _draft = _draft.copyWith(textAlign: align),
                        ),
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
                if (_hasFieldSettings) ...fieldSections,
              ],
            ),
          ),
        ),
      );
  }
}
