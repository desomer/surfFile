/// Hôte générique d'édition multi-états ([ComponentStateEditorHost]) partagé
/// par les éditeurs de composants (`SuperAction`, `SuperValue`,
/// `SuperIndicator`, `SuperSeparator`).
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/automatic_state.dart';
import '../../../../models/json_text_binding.dart';
import '../../../../services/repositories/json_list_scope.dart';
import '../../../../services/repositories/json_repository_scope.dart';
import '../../../../services/repositories/json_repository_store.dart';
import '../../../../services/states/surface_state_binding.dart';
import '../../dialogs/editor_dialog.dart';
import '../../dialogs/editor_tabbed_wizard.dart';
import '../../states/editor_state_controls.dart';
import '../../styles/style_editor_panel.dart';
import 'editor_color_fields.dart';

/// Contrat implémenté par l'`State` d'un éditeur feuille pour permettre à
/// [ComponentStateEditorHost] de capturer la saisie courante avant un
/// changement d'état.
abstract interface class ComponentLeafCapable<TConfig extends Object> {
  /// Valide et retourne la configuration unitaire courante, ou `null` si la
  /// saisie contient une erreur.
  TConfig? capture();
}

/// Mixin mutualisant la gestion du formulaire (`FormState`), des contrôleurs de
/// champs (`fields`), de la capture (`capture`), de l'aperçu temps réel
/// (`schedulePreview`) et de la validation finale (`handleApply`) pour les
/// éditeurs feuilles (`SuperAction`, `SuperIndicator`, `SuperSeparator`).
mixin ComponentLeafFormMixin<
  TWidget extends StatefulWidget,
  TConfig extends Object
>
    on State<TWidget>
    implements ComponentLeafCapable<TConfig> {
  /// Clé du formulaire principal de l'onglet « Propriétés ».
  final formKey = GlobalKey<FormState>();

  /// Contrôleurs de saisie indexés par nom de champ.
  late final Map<String, TextEditingController> fields;

  TConfig? _lastPreview;

  /// Message d'erreur de validation affiché en temps réel dans la barre d'actions.
  String? liveError;

  /// Préfixe de clé des champs de réglage (ex: `'super-action-setting'`).
  String get settingKeyPrefix;

  /// Message d'erreur générique affiché lorsqu'un `ArgumentError` survient.
  String get invalidConfigMessage;

  /// Callback d'aperçu temps réel fourni par le widget parent.
  ValueChanged<TConfig>? get onPreviewChangedCallback;

  /// Callback de transformation/sauvegarde de la feuille fourni par l'hôte d'état.
  TConfig Function(TConfig leaf)? get onSaveCallback;

  /// Assemble et valide l'instance `TConfig` courante à partir de [fields] et
  /// du brouillon de l'éditeur.
  TConfig buildConfiguration();

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Lit un nombre décimal optionnel depuis `fields[key]`.
  double? numberField(
    String key, {
    bool allowZero = false,
    bool allowNegative = false,
  }) => parseEditorNumberField(
    fields[key]!.text,
    allowZero: allowZero,
    allowNegative: allowNegative,
  );

  /// Lit une couleur hexadécimale `AARRGGBB` optionnelle depuis `fields[key]`.
  Color? colorField(String key) => parseEditorColorHex(fields[key]!.text);

  /// Construit un [TextFormField] standard relié à `fields[key]`.
  Widget buildSettingField(
    String key,
    String label, {
    bool numeric = false,
    bool allowZero = false,
    bool allowNegative = false,
    bool colorHex = false,
  }) => buildEditorSettingTextField(
    fieldKey: ValueKey('$settingKeyPrefix-$key'),
    controller: fields[key]!,
    label: label,
    numeric: numeric,
    allowZero: allowZero,
    allowNegative: allowNegative,
    colorHex: colorHex,
  );

  @override
  TConfig? capture() {
    if (!formKey.currentState!.validate()) return null;
    try {
      return buildConfiguration();
    } on FormatException catch (e) {
      setState(() => liveError = e.message);
    } on ArgumentError {
      setState(() => liveError = invalidConfigMessage);
    }
    return null;
  }

  /// Planifie la mise à jour de l'aperçu après le rendu de la frame courante.
  void schedulePreview() {
    final callback = onPreviewChangedCallback;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      try {
        final config = buildConfiguration();
        if (liveError != null) setState(() => liveError = null);
        if (_lastPreview != config) {
          _lastPreview = config;
          callback(config);
        }
      } on FormatException catch (error) {
        if (liveError != error.message) {
          setState(() => liveError = error.message);
        }
      } on ArgumentError {
        final message = invalidConfigMessage;
        if (liveError != message) setState(() => liveError = message);
      }
    });
  }

  /// Valide le formulaire, construit la configuration finale et ferme le dialogue.
  bool handleApply() {
    if (formKey.currentState != null && !formKey.currentState!.validate()) {
      return false;
    }
    TConfig result;
    try {
      final leaf = buildConfiguration();
      result = onSaveCallback?.call(leaf) ?? leaf;
    } on FormatException catch (e) {
      setState(() => liveError = e.message);
      return false;
    } on ArgumentError {
      setState(
        () => liveError = 'Combinaison de propriétés invalide.',
      );
      return false;
    }
    Navigator.of(context).pop(result);
    return true;
  }
}

/// Adaptateur typé décrivant les opérations de lecture/écriture des états
/// (`TStates`) et surcharges (`TOverride`) d'une configuration `TConfig`.
@immutable
class ComponentStateAdapter<
  TConfig extends Object,
  TStates extends Object,
  TOverride extends Object,
  TProperty extends Enum
> {
  /// Crée un [ComponentStateAdapter].
  const ComponentStateAdapter({
    required this.stateKeyPrefix,
    required this.emptyStates,
    required this.getStates,
    required this.withStates,
    required this.clearStates,
    required this.getNamed,
    required this.getNamedProperties,
    required this.getHover,
    required this.getSelected,
    required this.getAutomatic,
    required this.getOrder,
    required this.getBinding,
    required this.copyStates,
    required this.createOverride,
    required this.getOverrideConfig,
    required this.getOverrideProperties,
    required this.editOverride,
    required this.resolvePreview,
    required this.validateName,
    required this.propertyLabels,
    this.validateRoot,
    this.availableStatesBuilder,
    this.allowSelectedWhenAlreadyConfigured = false,
  });

  /// Préfixe de clé transmis à [EditorStateControls].
  final String stateKeyPrefix;

  /// Fabrique une instance vide de `TStates`.
  final TStates Function() emptyStates;

  /// Extrait `states` depuis `root`.
  final TStates? Function(TConfig root) getStates;

  /// Retourne une copie de `root` avec `states` mis à jour.
  final TConfig Function(TConfig root, TStates? states) withStates;

  /// Retourne une copie de `config` sans ses sous-états (`clearStates: true`).
  final TConfig Function(TConfig config) clearStates;

  /// Accesseurs sur `TStates`.
  final Map<String, TConfig> Function(TStates states) getNamed;
  final Map<String, Set<TProperty>> Function(TStates states) getNamedProperties;
  final TOverride? Function(TStates states) getHover;
  final TOverride? Function(TStates states) getSelected;
  final Map<AutomaticState, TOverride> Function(TStates states) getAutomatic;
  final List<String> Function(TStates states) getOrder;
  final JsonTextBinding? Function(TStates states) getBinding;

  /// Copie immuable de `TStates`.
  final TStates Function(
    TStates states, {
    Map<String, TConfig>? named,
    Map<String, Set<TProperty>>? namedProperties,
    TOverride? hover,
    bool clearHover,
    TOverride? selected,
    bool clearSelected,
    Map<AutomaticState, TOverride>? automatic,
    List<String>? order,
    JsonTextBinding? binding,
    bool clearBinding,
  })
  copyStates;

  /// Fabrique et manipule une surcharge `TOverride`.
  final TOverride Function(TConfig config, [Set<TProperty>? properties])
  createOverride;
  final TConfig Function(TOverride override) getOverrideConfig;
  final Set<TProperty> Function(TOverride override) getOverrideProperties;
  final TOverride Function(TOverride previous, TConfig nextLeaf) editOverride;

  /// Résout la configuration effective pour l'aperçu d'un état.
  final TConfig Function(
    TStates states,
    TConfig root, {
    String? name,
    required bool isHovered,
    required bool isSelected,
    required Set<AutomaticState> activeStates,
  })
  resolvePreview;

  /// Valide un nom d'état personnalisé (retourne le message d'erreur ou `null`).
  final String? Function(String name) validateName;

  /// Libellés de toutes les propriétés surchargeables `TProperty`.
  final Map<TProperty, String> propertyLabels;

  /// Validation additionnelle optionnelle sur la configuration racine.
  final void Function(TConfig root, bool allowBinding)? validateRoot;

  /// Calcule l'ensemble des états automatiques proposables dans le sélecteur.
  final Set<AutomaticState> Function({
    required TConfig leaf,
    required TStates states,
    required bool allowSelected,
    required bool allowContentHover,
  })?
  availableStatesBuilder;

  /// Si `true`, autorise l'état `selected` même hors `JsonListScope` dès lors
  /// qu'une surcharge `selected` existe déjà sur la configuration.
  final bool allowSelectedWhenAlreadyConfigured;
}

/// Signature du builder construisant l'éditeur feuille d'un état unitaire.
typedef ComponentLeafEditorBuilder<TConfig extends Object> =
    Widget Function({
      required Key key,
      required EditorWizardTab initialTab,
      required EditorDimensionDelegate? dimensionDelegate,
      required TConfig config,
      required ValueChanged<double> onWidthChanged,
      required JsonRepositoryStore? repositories,
      required JsonListScope? listScope,
      required TextStyle textStyle,
      required ValueChanged<TConfig> onPreviewChanged,
      required TConfig Function(TConfig leaf) onSave,
      required Widget header,
    });

/// Ouvre une boîte de dialogue modale redimensionnable hébergeant un
/// [ComponentStateEditorHost].
Future<TConfig?>
showStatefulComponentEditorDialog<
  TConfig extends Object,
  TStates extends Object,
  TOverride extends Object,
  TProperty extends Enum
>({
  required BuildContext context,
  required TConfig config,
  required ComponentStateAdapter<TConfig, TStates, TOverride, TProperty>
  adapter,
  required ComponentLeafEditorBuilder<TConfig> leafBuilder,
  bool allowBinding = true,
  ValueChanged<TConfig>? onPreviewChanged,
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
    return await runWithDimensionDelegate<TConfig>(
      context: context,
      runner: (initialTab, dimensionDelegate) => showEditorDialog<TConfig>(
        context: context,
        target: context,
        preferredWidth: width,
        builder: (_) =>
            ComponentStateEditorHost<TConfig, TStates, TOverride, TProperty>(
              ownerContext: context,
              initialTab: initialTab,
              dimensionDelegate: dimensionDelegate,
              config: config,
              adapter: adapter,
              leafBuilder: leafBuilder,
              textStyle: textStyle,
              onWidthChanged: (value) => width.value = value,
              repositories: repositories,
              listScope: listScope,
              allowBinding: allowBinding,
              onPreviewChanged: onPreviewChanged,
              activeState: activeState,
              stateError: stateError,
              isHovered: isHovered,
              isSelected: isSelected,
              allowContentHover: allowContentHover,
              activeAutomatic: activeAutomatic,
            ),
      ),
    );
  } finally {
    width.dispose();
  }
}

/// Widget conteneur orchestrant l'édition multi-états d'un composant
/// (`SuperAction`, `SuperValue`, `SuperIndicator`, `SuperSeparator`).
class ComponentStateEditorHost<
  TConfig extends Object,
  TStates extends Object,
  TOverride extends Object,
  TProperty extends Enum
>
    extends StatefulWidget {
  /// Crée un [ComponentStateEditorHost].
  const ComponentStateEditorHost({
    required this.ownerContext,
    required this.initialTab,
    required this.dimensionDelegate,
    required this.config,
    required this.adapter,
    required this.leafBuilder,
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
    super.key,
  });

  final BuildContext ownerContext;
  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;
  final TConfig config;
  final ComponentStateAdapter<TConfig, TStates, TOverride, TProperty> adapter;
  final ComponentLeafEditorBuilder<TConfig> leafBuilder;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding;
  final bool isHovered;
  final bool isSelected;
  final bool allowContentHover;
  final Set<AutomaticState> activeAutomatic;
  final ValueChanged<TConfig>? onPreviewChanged;
  final String? activeState;
  final String? stateError;

  @override
  State<ComponentStateEditorHost<TConfig, TStates, TOverride, TProperty>>
  createState() =>
      _ComponentStateEditorHostState<TConfig, TStates, TOverride, TProperty>();
}

class _ComponentStateEditorHostState<
  TConfig extends Object,
  TStates extends Object,
  TOverride extends Object,
  TProperty extends Enum
>
    extends
        State<
          ComponentStateEditorHost<TConfig, TStates, TOverride, TProperty>
        > {
  late TConfig _root = widget.config;
  String? _state;
  String? _error;
  GlobalKey _leafKey = GlobalKey();
  SurfaceStateBinding? _reader;

  ComponentStateAdapter<TConfig, TStates, TOverride, TProperty> get _adapter =>
      widget.adapter;

  void _stateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _syncReader() {
    final currentStates = _adapter.getStates(_root);
    final binding = currentStates == null
        ? null
        : _adapter.getBinding(currentStates);
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

  TConfig get _leaf {
    final states = _adapter.getStates(_root);
    final base = _adapter.clearStates(_root);
    if (states == null) return base;
    final automatic = AutomaticState.fromKey(_state);
    if (automatic != null &&
        automatic != AutomaticState.hover &&
        automatic != AutomaticState.selected) {
      final override = _adapter.getAutomatic(states)[automatic];
      return override == null ? base : _adapter.getOverrideConfig(override);
    }
    if (_state == hoverSurfaceStateKey) {
      final hover = _adapter.getHover(states);
      return hover == null ? base : _adapter.getOverrideConfig(hover);
    }
    if (_state == selectedSurfaceStateKey) {
      final selected = _adapter.getSelected(states);
      return selected == null ? base : _adapter.getOverrideConfig(selected);
    }
    return _adapter.getNamed(states)[_state] ?? base;
  }

  TConfig _withLeaf(TConfig leaf) {
    leaf = _adapter.clearStates(leaf);
    final states = _adapter.getStates(_root) ?? _adapter.emptyStates();
    if (_state == null) {
      return _adapter.withStates(leaf, _adapter.getStates(_root));
    }
    final base = _adapter.clearStates(_root);
    final automatic = AutomaticState.fromKey(_state);
    if (automatic != null &&
        automatic != AutomaticState.hover &&
        automatic != AutomaticState.selected) {
      final currentAuto = _adapter.getAutomatic(states);
      final previous =
          currentAuto[automatic] ?? _adapter.createOverride(base);
      return _adapter.withStates(
        _root,
        _adapter.copyStates(
          states,
          automatic: {
            ...currentAuto,
            automatic: _adapter.editOverride(previous, leaf),
          },
        ),
      );
    }
    final previous = _state == hoverSurfaceStateKey
        ? _adapter.getHover(states)
        : _adapter.getSelected(states);
    final overlay = _adapter.editOverride(
      previous ?? _adapter.createOverride(base),
      leaf,
    );
    if (_state == hoverSurfaceStateKey) {
      return _adapter.withStates(
        _root,
        _adapter.copyStates(states, hover: overlay),
      );
    }
    if (_state == selectedSurfaceStateKey) {
      return _adapter.withStates(
        _root,
        _adapter.copyStates(states, selected: overlay),
      );
    }
    final named = _adapter.getNamed(states);
    final namedProps = _adapter.getNamedProperties(states);
    final editedNamedOverride = _adapter.editOverride(
      _adapter.createOverride(named[_state]!, namedProps[_state]!),
      leaf,
    );
    return _adapter.withStates(
      _root,
      _adapter.copyStates(
        states,
        named: {...named, _state!: leaf},
        namedProperties: {
          ...namedProps,
          _state!: _adapter.getOverrideProperties(editedNamedOverride),
        },
      ),
    );
  }

  void _validate(TConfig root) {
    _adapter.validateRoot?.call(root, widget.allowBinding);
  }

  bool _capture() {
    final state = _leafKey.currentState;
    if (state == null) return true;
    final capable = state as ComponentLeafCapable<TConfig>;
    final leaf = capable.capture();
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

  void _preview(TConfig root) {
    final states = _adapter.getStates(root);
    final base = _adapter.clearStates(root);
    final config = _state == null || states == null
        ? base
        : _adapter.resolvePreview(
            states,
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
          );
    widget.onPreviewChanged?.call(config);
  }

  void _changeStates(TStates Function(TStates states) update) {
    if (!_capture()) return;
    try {
      final root = _adapter.withStates(
        _root,
        update(_adapter.getStates(_root) ?? _adapter.emptyStates()),
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
    final states = _adapter.getStates(_root) ?? _adapter.emptyStates();
    final named = _adapter.getNamed(states);
    final namedProps = _adapter.getNamedProperties(states);
    final autoMap = _adapter.getAutomatic(states);
    final hover = _adapter.getHover(states);
    final selected = _adapter.getSelected(states);
    final automatic = AutomaticState.fromKey(_state);
    final TOverride? overlay = named.containsKey(_state)
        ? _adapter.createOverride(named[_state]!, namedProps[_state]!)
        : automatic != null &&
              automatic != AutomaticState.hover &&
              automatic != AutomaticState.selected
        ? autoMap[automatic]
        : _state == hoverSurfaceStateKey
        ? hover
        : selected;
    final allowSelected =
        widget.listScope != null ||
        (_adapter.allowSelectedWhenAlreadyConfigured && selected != null);
    final leaf = _leaf;
    final availableStates =
        _adapter.availableStatesBuilder?.call(
          leaf: leaf,
          states: states,
          allowSelected: allowSelected,
          allowContentHover: widget.allowContentHover,
        ) ??
        {
          AutomaticState.hover,
          if (allowSelected) AutomaticState.selected,
          if (widget.allowContentHover) AutomaticState.contentHover,
          AutomaticState.focused,
          AutomaticState.disabled,
        };

    return widget.leafBuilder(
      key: _leafKey,
      initialTab: widget.initialTab,
      dimensionDelegate: widget.dimensionDelegate,
      config: leaf,
      onWidthChanged: widget.onWidthChanged,
      repositories: widget.repositories,
      listScope: widget.listScope,
      textStyle: widget.textStyle,
      onPreviewChanged: (nextLeaf) {
        try {
          final root = _withLeaf(nextLeaf);
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
      onSave: (nextLeaf) {
        final root = _withLeaf(nextLeaf);
        _validate(root);
        return root;
      },
      header: EditorStateControls<TProperty>(
        keyPrefix: _adapter.stateKeyPrefix,
        names: named.keys,
        order: _adapter
            .getOrder(states)
            .where(
              (key) =>
                  (key != hoverSurfaceStateKey || hover != null) &&
                  (key != selectedSurfaceStateKey || selected != null),
            )
            .toList(),
        permanentInteractionStates: false,
        binding: _adapter.getBinding(states),
        state: _state,
        allowSelected: allowSelected,
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
        availableStates: availableStates,
        onAddAutomatic: (value) {
          _changeStates((s) {
            final override = _adapter.createOverride(
              _adapter.clearStates(_leaf),
            );
            final order = [
              ..._adapter.getOrder(s).where((key) => key != value.key),
              value.key,
            ];
            if (value == AutomaticState.hover) {
              return _adapter.copyStates(s, hover: override, order: order);
            }
            if (value == AutomaticState.selected) {
              return _adapter.copyStates(s, selected: override, order: order);
            }
            return _adapter.copyStates(
              s,
              automatic: {..._adapter.getAutomatic(s), value: override},
              order: order,
            );
          });
          final updatedStates = _adapter.getStates(_root);
          if (updatedStates != null &&
              ((value == AutomaticState.hover &&
                      _adapter.getHover(updatedStates) != null) ||
                  (value == AutomaticState.selected &&
                      _adapter.getSelected(updatedStates) != null) ||
                  _adapter.getAutomatic(updatedStates).containsKey(value))) {
            setState(() {
              _state = value.key;
              _leafKey = GlobalKey();
            });
            _preview(_root);
          }
        },
        onDeleteAutomatic: (value) {
          if (!_capture()) return;
          final currentStates = _adapter.getStates(_root)!;
          setState(() {
            _root = _adapter.withStates(
              _root,
              _adapter.copyStates(
                currentStates,
                clearHover: value == AutomaticState.hover,
                clearSelected: value == AutomaticState.selected,
                automatic: {..._adapter.getAutomatic(currentStates)}
                  ..remove(value),
              ),
            );
            _state = null;
            _leafKey = GlobalKey();
          });
          _preview(_root);
        },
        validateName: _adapter.validateName,
        onAdd: (name) => _changeStates(
          (s) => _adapter.copyStates(
            s,
            named: {..._adapter.getNamed(s), name: _adapter.clearStates(_root)},
            order: [name, ..._adapter.getOrder(s)],
          ),
        ),
        onRename: (previous, name) {
          _changeStates((s) {
            final curNamed = _adapter.getNamed(s);
            final curProps = _adapter.getNamedProperties(s);
            return _adapter.copyStates(
              s,
              named: {...curNamed}
                ..remove(previous)
                ..[name] = curNamed[previous]!,
              namedProperties: {...curProps}
                ..remove(previous)
                ..[name] = curProps[previous]!,
              order: [
                for (final key in _adapter.getOrder(s))
                  if (key == previous) name else key,
              ],
            );
          });
          final updatedStates = _adapter.getStates(_root);
          if (updatedStates != null &&
              _adapter.getNamed(updatedStates).containsKey(name)) {
            setState(() {
              _state = name;
              _leafKey = GlobalKey();
            });
          }
        },
        onDelete: (name) => _changeStates(
          (s) => _adapter.copyStates(
            s,
            named: {..._adapter.getNamed(s)}..remove(name),
          ),
        ),
        onReorder: (order) =>
            _changeStates((s) => _adapter.copyStates(s, order: order)),
        onBindingChanged: (binding) => _changeStates(
          (s) => _adapter.copyStates(
            s,
            binding: binding,
            clearBinding: binding == null,
          ),
        ),
        properties: _adapter.propertyLabels,
        overrides: overlay == null
            ? <TProperty>{}
            : _adapter.getOverrideProperties(overlay),
        onOverride: (property, enabled) => _changeStates((s) {
          final sNamed = _adapter.getNamed(s);
          final sNamedProps = _adapter.getNamedProperties(s);
          final sAuto = _adapter.getAutomatic(s);
          final current = sNamed.containsKey(_state)
              ? _adapter.createOverride(sNamed[_state]!, sNamedProps[_state]!)
              : automatic != null &&
                    automatic != AutomaticState.hover &&
                    automatic != AutomaticState.selected
              ? sAuto[automatic]
              : _state == hoverSurfaceStateKey
              ? _adapter.getHover(s)
              : _adapter.getSelected(s);
          final properties = {
            if (current != null) ..._adapter.getOverrideProperties(current),
          };
          if (enabled) {
            properties.add(property);
          } else {
            properties.remove(property);
          }
          final value = _adapter.createOverride(
            current == null
                ? _adapter.clearStates(_root)
                : _adapter.getOverrideConfig(current),
            properties,
          );
          if (sNamed.containsKey(_state)) {
            return _adapter.copyStates(
              s,
              namedProperties: {...sNamedProps, _state!: properties},
            );
          }
          if (automatic != null &&
              automatic != AutomaticState.hover &&
              automatic != AutomaticState.selected) {
            return _adapter.copyStates(
              s,
              automatic: {...sAuto, automatic: value},
            );
          }
          if (_state == hoverSurfaceStateKey) {
            return _adapter.copyStates(s, hover: value);
          }
          return _adapter.copyStates(s, selected: value);
        }),
      ),
    );
  }
}
