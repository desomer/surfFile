import 'dart:math' as math;
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../models/automatic_state.dart';

import '../../../models/super_value_config.dart';
import '../../../models/super_text_field_config.dart';
import '../../components/super_text_field.dart';
import '../../../models/json_text_binding.dart';
import '../../../services/json_list_scope.dart';
import '../../../services/json_repository_scope.dart';
import '../../../services/json_repository_store.dart';
import '../../../services/surface_state_binding.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../dialogs/editor_dialog.dart';
import '../repositories/repository_binding_fields.dart';
import '../styles/style_editor_panel.dart';
import '../states/editor_state_controls.dart';
import 'super_text_field_settings.dart';

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
}) async {
  final width = ValueNotifier(StyleEditorPanel.preferredDense ? 680.0 : 1080.0);
  final textStyle = DefaultTextStyle.of(context).style;
  final repositories = JsonRepositoryScope.maybeOf(context);
  final listScope = JsonListScope.maybeOf(context);
  try {
    return await showEditorDialog<SuperValueConfig>(
      context: context,
      target: context,
      preferredWidth: width,
      builder: (_) => _ValueStateEditor(
        ownerContext: context,
        activeState: activeState,
        stateError: stateError,
        isHovered: isHovered,
        isSelected: isSelected,
        allowContentHover: allowContentHover,
        activeAutomatic: activeAutomatic,
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

class _ValueStateEditor extends StatefulWidget {
  const _ValueStateEditor({
    required this.ownerContext,
    required this.config,
    required this.availableFontFamilies,
    required this.textStyle,
    required this.onWidthChanged,
    required this.repositories,
    required this.listScope,
    required this.allowBinding,
    required this.onPreviewChanged,
    required this.activeState,
    required this.stateError,
    required this.isHovered,
    required this.isSelected,
    required this.allowContentHover,
    required this.activeAutomatic,
  });
  final BuildContext ownerContext;
  final SuperValueConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding, isHovered, isSelected;
  final bool allowContentHover;
  final Set<AutomaticState> activeAutomatic;
  final ValueChanged<SuperValueConfig>? onPreviewChanged;
  final String? activeState, stateError;
  @override
  State<_ValueStateEditor> createState() => _ValueStateEditorState();
}

class _ValueStateEditorState extends State<_ValueStateEditor> {
  late SuperValueConfig _root = widget.config;
  String? _state;
  String? _error;
  GlobalKey<_SuperValueEditorState> _leafKey = GlobalKey();
  SurfaceStateBinding? _reader;

  void _stateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _syncReader() {
    final binding = _root.states?.binding;
    if (binding == null) {
      _reader?.removeListener(_stateChanged);
      _reader?.dispose();
      _reader = null;
    } else if (_reader == null) {
      _reader = SurfaceStateBinding(
        store: widget.repositories,
        binding: binding,
        scope: widget.listScope,
        placeholder: widget.listScope?.placeholder ?? false,
      )..addListener(_stateChanged);
    } else {
      _reader!.reconfigure(
        store: widget.repositories,
        binding: binding,
        scope: widget.listScope,
        placeholder: widget.listScope?.placeholder ?? false,
      );
    }
  }

  @override
  void dispose() {
    _reader?.removeListener(_stateChanged);
    _reader?.dispose();
    super.dispose();
  }

  SuperValueConfig get _leaf {
    final states = _root.states;
    final automatic = AutomaticState.fromKey(_state);
    if (automatic != null &&
        automatic != AutomaticState.hover &&
        automatic != AutomaticState.selected) {
      return states?.automatic[automatic]?.config ??
          _root.copyWith(clearStates: true);
    }
    if (_state == hoverSurfaceStateKey) {
      return states?.hover?.config ?? _root.copyWith(clearStates: true);
    }
    if (_state == selectedSurfaceStateKey) {
      return states?.selected?.config ?? _root.copyWith(clearStates: true);
    }
    return states?.named[_state] ?? _root.copyWith(clearStates: true);
  }

  SuperValueConfig _withLeaf(SuperValueConfig leaf) {
    leaf = leaf.copyWith(clearStates: true);
    final states = _root.states ?? ValueConfigStates();
    if (_state == null) return leaf.copyWith(states: _root.states);
    final automatic = AutomaticState.fromKey(_state);
    if (automatic != null &&
        automatic != AutomaticState.hover &&
        automatic != AutomaticState.selected) {
      final previous =
          states.automatic[automatic] ??
          ValueConfigOverride(config: _root.copyWith(clearStates: true));
      return _root.copyWith(
        states: states.copyWith(
          automatic: {...states.automatic, automatic: previous.edited(leaf)},
        ),
      );
    }
    final previous = _state == hoverSurfaceStateKey
        ? states.hover
        : states.selected;
    final overlay =
        (previous ??
                ValueConfigOverride(config: _root.copyWith(clearStates: true)))
            .edited(leaf);
    return _root.copyWith(
      states: _state == hoverSurfaceStateKey
          ? states.copyWith(hover: overlay)
          : _state == selectedSurfaceStateKey
          ? states.copyWith(selected: overlay)
          : states.copyWith(
              named: {...states.named, _state!: leaf},
              namedProperties: {
                ...states.namedProperties,
                _state!: ValueConfigOverride(
                  config: states.named[_state]!,
                  properties: states.namedProperties[_state]!,
                ).edited(leaf).properties,
              },
            ),
    );
  }

  void _validate(SuperValueConfig root) {
    root.validate();
    if (!widget.allowBinding) {
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
  }

  bool _capture() {
    if (_leafKey.currentState == null) return true;
    final leaf = _leafKey.currentState?.capture();
    if (leaf == null) return false;
    try {
      final root = _withLeaf(leaf);
      _validate(root);
      _root = root;
      _error = null;
      return true;
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on ArgumentError {
      setState(() => _error = 'Combinaison de propriétés invalide.');
    }
    return false;
  }

  void _preview(SuperValueConfig root) {
    final states = root.states;
    final config = _state == null
        ? root.copyWith(clearStates: true)
        : states?.resolve(
                root,
                name: AutomaticState.fromKey(_state) != null
                    ? _reader?.stateName ?? widget.activeState
                    : _state,
                isHovered: _state == hoverSurfaceStateKey || widget.isHovered,
                isSelected:
                    _state == selectedSurfaceStateKey || widget.isSelected,
                activeStates: {
                  ...widget.activeAutomatic,
                  ?AutomaticState.fromKey(_state),
                },
              ) ??
              root.copyWith(clearStates: true);
    widget.onPreviewChanged?.call(config);
  }

  void _changeStates(
    ValueConfigStates Function(ValueConfigStates states) update,
  ) {
    if (!_capture()) return;
    try {
      final root = _root.copyWith(
        states: update(_root.states ?? ValueConfigStates()),
      );
      _validate(root);
      setState(() {
        _root = root;
        _error = null;
      });
      _preview(root);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on ArgumentError {
      setState(() => _error = 'Combinaison de propriétés invalide.');
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncReader();
    final states = _root.states ?? ValueConfigStates();
    final automatic = AutomaticState.fromKey(_state);
    final overlay = states.named.containsKey(_state)
        ? ValueConfigOverride(
            config: states.named[_state]!,
            properties: states.namedProperties[_state]!,
          )
        : automatic != null &&
              automatic != AutomaticState.hover &&
              automatic != AutomaticState.selected
        ? states.automatic[automatic]
        : _state == hoverSurfaceStateKey
        ? states.hover
        : states.selected;
    return _SuperValueEditor(
      key: _leafKey,
      config: _leaf,
      availableFontFamilies: widget.availableFontFamilies,
      textStyle: widget.textStyle,
      onWidthChanged: widget.onWidthChanged,
      repositories: widget.repositories,
      listScope: widget.listScope,
      allowBinding: widget.allowBinding,
      onPreviewChanged: (leaf) {
        try {
          final root = _withLeaf(leaf);
          _validate(root);
          if (_root != root) {
            setState(() {
              _root = root;
              _error = null;
            });
          }
          _preview(root);
        } on FormatException catch (e) {
          if (_error != e.message) setState(() => _error = e.message);
        } on ArgumentError {
          const message = 'Combinaison de propriétés invalide.';
          if (_error != message) setState(() => _error = message);
        }
      },
      onSave: (leaf) {
        final root = _withLeaf(leaf);
        _validate(root);
        return root;
      },
      header: EditorStateControls<ValueStateProperty>(
        keyPrefix: 'value-state',
        names: states.named.keys,
        order: states.order
            .where(
              (key) =>
                  (key != ValueConfigStates.hoverKey || states.hover != null) &&
                  (key != ValueConfigStates.selectedKey ||
                      states.selected != null),
            )
            .toList(),
        permanentInteractionStates: false,
        binding: states.binding,
        state: _state,
        allowSelected: widget.listScope != null,
        ownerContext: widget.ownerContext,
        activeState: _reader?.stateName ?? widget.activeState,
        error: _error ?? _reader?.error ?? widget.stateError,
        onSelect: (value) {
          if (value == _state || !_capture()) return;
          setState(() {
            _state = value;
            _leafKey = GlobalKey();
          });
          _preview(_root);
        },
        availableStates: {
          AutomaticState.hover,
          if (widget.listScope != null) AutomaticState.selected,
          if (widget.allowContentHover) AutomaticState.contentHover,
          if (_leaf.mode == SuperValueMode.input) ...{
            AutomaticState.focused,
            AutomaticState.disabled,
            AutomaticState.readOnly,
          },
        },
        onAddAutomatic: (value) {
          _changeStates((s) {
            final override = ValueConfigOverride(
              config: _leaf.copyWith(clearStates: true),
            );
            final order = [
              ...s.order.where((key) => key != value.key),
              value.key,
            ];
            if (value == AutomaticState.hover) {
              return s.copyWith(hover: override, order: order);
            }
            if (value == AutomaticState.selected) {
              return s.copyWith(selected: override, order: order);
            }
            return s.copyWith(
              automatic: {...s.automatic, value: override},
              order: order,
            );
          });
          if ((value == AutomaticState.hover && _root.states?.hover != null) ||
              (value == AutomaticState.selected &&
                  _root.states?.selected != null) ||
              _root.states?.automatic.containsKey(value) == true) {
            setState(() {
              _state = value.key;
              _leafKey = GlobalKey();
            });
            _preview(_root);
          }
        },
        onDeleteAutomatic: (value) {
          if (!_capture()) return;
          setState(() {
            _root = _root.copyWith(
              states: _root.states!.copyWith(
                clearHover: value == AutomaticState.hover,
                clearSelected: value == AutomaticState.selected,
                automatic: {..._root.states!.automatic}..remove(value),
              ),
            );
            _state = null;
            _leafKey = GlobalKey();
          });
          _preview(_root);
        },
        validateName: (name) {
          try {
            ValueConfigStates(named: {name: const SuperValueConfig()});
            return null;
          } on FormatException catch (e) {
            return e.message;
          }
        },
        onAdd: (name) => _changeStates(
          (s) => s.copyWith(
            named: {...s.named, name: _root.copyWith(clearStates: true)},
            order: [name, ...s.order],
          ),
        ),
        onRename: (previous, name) {
          _changeStates(
            (s) => s.copyWith(
              named: {...s.named}
                ..remove(previous)
                ..[name] = s.named[previous]!,
              namedProperties: {...s.namedProperties}
                ..remove(previous)
                ..[name] = s.namedProperties[previous]!,
              order: [
                for (final key in s.order)
                  if (key == previous) name else key,
              ],
            ),
          );
          if (_root.states?.named.containsKey(name) == true) {
            setState(() {
              _state = name;
              _leafKey = GlobalKey();
            });
          }
        },
        onDelete: (name) =>
            _changeStates((s) => s.copyWith(named: {...s.named}..remove(name))),
        onReorder: (order) => _changeStates((s) => s.copyWith(order: order)),
        onBindingChanged: (binding) => _changeStates(
          (s) => s.copyWith(binding: binding, clearBinding: binding == null),
        ),
        properties: {
          for (final property in ValueStateProperty.values)
            property: property.label,
        },
        overrides: overlay?.properties ?? {},
        onOverride: (property, enabled) => _changeStates((s) {
          final current = s.named.containsKey(_state)
              ? ValueConfigOverride(
                  config: s.named[_state]!,
                  properties: s.namedProperties[_state]!,
                )
              : automatic != null &&
                    automatic != AutomaticState.hover &&
                    automatic != AutomaticState.selected
              ? s.automatic[automatic]
              : _state == hoverSurfaceStateKey
              ? s.hover
              : s.selected;
          final properties = {...?current?.properties};
          if (enabled) {
            properties.add(property);
          } else {
            properties.remove(property);
          }
          final value = ValueConfigOverride(
            config: current?.config ?? _root.copyWith(clearStates: true),
            properties: properties,
          );
          return s.named.containsKey(_state)
              ? s.copyWith(
                  namedProperties: {...s.namedProperties, _state!: properties},
                )
              : automatic != null &&
                    automatic != AutomaticState.hover &&
                    automatic != AutomaticState.selected
              ? s.copyWith(automatic: {...s.automatic, automatic: value})
              : _state == hoverSurfaceStateKey
              ? s.copyWith(hover: value)
              : s.copyWith(selected: value);
        }),
      ),
    );
  }
}

class _SuperValueEditor extends StatefulWidget {
  const _SuperValueEditor({
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

  @override
  State<_SuperValueEditor> createState() => _SuperValueEditorState();
}

class _SuperValueEditorState extends State<_SuperValueEditor> {
  final _form = GlobalKey<FormState>();
  final _fieldSettings = GlobalKey<SuperTextFieldSettingsState>();
  late SuperTextFieldConfig _fieldConfig;
  String? _fieldError;
  late SuperValueConfig _draft;
  late final Map<String, TextEditingController> _fields;
  late bool _dense = StyleEditorPanel.preferredDense;
  final _previewText = TextEditingController();
  List<JsonRepositoryEntry> _repositories = [];
  String? _repositoryId;
  bool _inheritRepository = false;
  String? _repositoryError;
  bool _loadingRepositories = false;
  bool _validating = false;
  SuperValueConfig? _lastPreview;
  String? _liveError;

  bool get _hasFieldSettings =>
      _draft.mode == SuperValueMode.input && !_draft.kind.isBoolean;

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

  SuperValueConfig _configuration(
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
        key: ValueKey('super-value-setting-$key'),
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

  Future<void> _editPropertyBinding(
    SuperValueProperty property,
    String label,
  ) async {
    final result = await showRepositoryBindingDialog(
      context: context,
      title: 'Lier $label',
      keyPrefix: 'super-value-property-${property.name}',
      pathHint: 'client.${property.name}',
      binding: _draft.propertyBindings[property],
      store: widget.repositories,
      listScope: widget.listScope,
      helper: 'Lecture seule : la valeur du repository remplace ce paramètre.',
    );
    if (result == null || !mounted) return;
    final bindings = Map<SuperValueProperty, JsonTextBinding>.of(
      _draft.propertyBindings,
    );
    if (result.binding == null) {
      bindings.remove(property);
    } else {
      bindings[property] = result.binding!;
    }
    setState(() => _draft = _draft.copyWith(propertyBindings: bindings));
  }

  Widget _withBinding(
    SuperValueProperty property,
    String label,
    Widget child,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: child),
      IconButton(
        key: ValueKey('super-value-bind-${property.name}'),
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
      key: const ValueKey('super-value-settings'),
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
              label: 'Configurer la valeur',
              dense: _dense,
              onDenseChanged: (value) => setState(() {
                _dense = value;
                widget.onWidthChanged(value ? 680 : 1080);
              }),
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
                    DropdownButtonFormField<SuperValueKind>(
                      isExpanded: true,
                      key: const ValueKey('super-value-setting-kind'),
                      initialValue: _draft.kind,
                      decoration: const InputDecoration(
                        labelText: 'Type de valeur',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SuperValueKind.text,
                          child: Text('Texte'),
                        ),
                        DropdownMenuItem(
                          value: SuperValueKind.checkbox,
                          child: Text('Case à cocher (Checkbox)'),
                        ),
                        DropdownMenuItem(
                          value: SuperValueKind.switchControl,
                          child: Text('Interrupteur (Switch)'),
                        ),
                      ],
                      onChanged: (kind) {
                        if (kind != null) {
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
                        }
                      },
                    ),
                    DropdownButtonFormField<SuperValueMode>(
                      isExpanded: true,
                      key: const ValueKey('super-value-setting-mode'),
                      initialValue: _draft.mode,
                      decoration: const InputDecoration(labelText: 'Mode'),
                      items: const [
                        DropdownMenuItem(
                          value: SuperValueMode.display,
                          child: Text('Affichage'),
                        ),
                        DropdownMenuItem(
                          value: SuperValueMode.input,
                          child: Text('Saisie'),
                        ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) {
                          setState(() => _draft = _draft.copyWith(mode: mode));
                        }
                      },
                    ),
                    if (_draft.kind.isBoolean && !_bound)
                      SwitchListTile(
                        key: const ValueKey('super-value-setting-initialBool'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Valeur initiale'),
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
                      : 'obscureText · maxLines',
                  child: _group([
                    if (!_draft.kind.isBoolean) ...[
                      SwitchListTile(
                        key: const ValueKey('super-value-setting-obscureText'),
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
                        if (_draft.mode == SuperValueMode.input)
                          _field('minLines', 'Lignes minimales', numeric: true),
                        _field('maxLines', 'Lignes maximales', numeric: true),
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
                  child: _group([
                    if (unavailable)
                      Text(
                        'Police indisponible : ${_draft.fontFamily}. Choisissez une police disponible.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    _withBinding(
                      SuperValueProperty.fontFamily,
                      'la police',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey(
                          'super-value-setting-fontFamily-${_draft.fontFamily}',
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
                      SuperValueProperty.fontSize,
                      'la taille de police',
                      _field(
                        'fontSize',
                        'Taille de police (vide = thème)',
                        numeric: true,
                      ),
                    ),
                    _withBinding(
                      SuperValueProperty.fontWeight,
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
                      SuperValueProperty.italic,
                      'le style italique',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: const ValueKey('super-value-setting-italic'),
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
                        _fields['color']!.text = color
                            .toARGB32()
                            .toRadixString(16)
                            .padLeft(8, '0');
                      }),
                      key: const ValueKey('super-value-color-picker'),
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
                if (_hasFieldSettings) ...fieldSections,
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_liveError != null)
          Text(
            _liveError!,
            key: const ValueKey('super-value-live-error'),
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
                  if (_hasFieldSettings &&
                      _fieldSettings.currentState?.validate() == false) {
                    return;
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
                          final attr = await widget.repositories!.readAttribute(
                            resolved,
                          );
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
                  SuperValueConfig result;
                  try {
                    final leaf = _configuration(field, binding);
                    result = widget.onSave?.call(leaf) ?? leaf;
                  } on FormatException catch (e) {
                    setState(() => _liveError = e.message);
                    return;
                  } on ArgumentError {
                    setState(
                      () => _liveError = 'Combinaison de propriétés invalide.',
                    );
                    return;
                  }
                  if (!context.mounted) return;
                  Navigator.of(context).pop(result);
                },
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}
