/// Fenêtre d'édition complète d'un composant [SuperSeparator].
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/automatic_state.dart';
import '../../../models/json_text_binding.dart';
import '../../../models/super_separator_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../services/states/surface_state_binding.dart';
import '../../components/super_separator.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../repositories/repository_binding_fields.dart';
import '../states/editor_state_controls.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../styles/style_editor_panel.dart';

/// Ouvre la boîte de dialogue d'édition d'un [SuperSeparatorConfig] avec gestion
/// complète des états standards (`hover`, `selected`, `contentHover`),
/// des états métier personnalisés (`named`) et des liaisons JSON.
Future<SuperSeparatorConfig?> showSuperSeparatorEditor({
  required BuildContext context,
  required SuperSeparatorConfig config,
  required List<String> availableFontFamilies,
  bool allowBinding = true,
  ValueChanged<SuperSeparatorConfig>? onPreviewChanged,
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
    return await runWithDimensionDelegate<SuperSeparatorConfig>(
      context: context,
      runner: (initialTab, dimensionDelegate) =>
          showEditorDialog<SuperSeparatorConfig>(
            context: context,
            target: context,
            preferredWidth: width,
            builder: (_) => _SeparatorStateEditor(
              ownerContext: context,
              initialTab: initialTab,
              dimensionDelegate: dimensionDelegate,
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
          ),
    );
  } finally {
    width.dispose();
  }
}

class _SeparatorStateEditor extends StatefulWidget {
  const _SeparatorStateEditor({
    required this.ownerContext,
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
    required this.activeState,
    required this.stateError,
    required this.isHovered,
    required this.isSelected,
    required this.allowContentHover,
    required this.activeAutomatic,
  });

  final BuildContext ownerContext;
  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;
  final SuperSeparatorConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding, isHovered, isSelected;
  final bool allowContentHover;
  final Set<AutomaticState> activeAutomatic;
  final ValueChanged<SuperSeparatorConfig>? onPreviewChanged;
  final String? activeState, stateError;

  @override
  State<_SeparatorStateEditor> createState() => _SeparatorStateEditorState();
}

class _SeparatorStateEditorState extends State<_SeparatorStateEditor> {
  late SuperSeparatorConfig _root = widget.config;
  String? _state;
  String? _error;
  GlobalKey<_SuperSeparatorEditorState> _leafKey = GlobalKey();
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

  SuperSeparatorConfig get _leaf {
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

  SuperSeparatorConfig _withLeaf(SuperSeparatorConfig leaf) {
    leaf = leaf.copyWith(clearStates: true);
    final states = _root.states ?? SeparatorConfigStates();
    if (_state == null) return leaf.copyWith(states: _root.states);
    final automatic = AutomaticState.fromKey(_state);
    if (automatic != null &&
        automatic != AutomaticState.hover &&
        automatic != AutomaticState.selected) {
      final previous =
          states.automatic[automatic] ??
          SeparatorConfigOverride(config: _root.copyWith(clearStates: true));
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
                SeparatorConfigOverride(
                  config: _root.copyWith(clearStates: true),
                ))
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
                _state!: SeparatorConfigOverride(
                  config: states.named[_state]!,
                  properties: states.namedProperties[_state]!,
                ).edited(leaf).properties,
              },
            ),
    );
  }

  void _validate(SuperSeparatorConfig root) {
    root.validate();
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

  void _preview(SuperSeparatorConfig root) {
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
    SeparatorConfigStates Function(SeparatorConfigStates states) update,
  ) {
    if (!_capture()) return;
    try {
      final root = _root.copyWith(
        states: update(_root.states ?? SeparatorConfigStates()),
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
    final states = _root.states ?? SeparatorConfigStates();
    final automatic = AutomaticState.fromKey(_state);
    final overlay = states.named.containsKey(_state)
        ? SeparatorConfigOverride(
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
    final allowSelected = widget.listScope != null || states.selected != null;
    return _SuperSeparatorEditor(
      key: _leafKey,
      initialTab: widget.initialTab,
      dimensionDelegate: widget.dimensionDelegate,
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
      header: EditorStateControls<SeparatorStateProperty>(
        keyPrefix: 'super-separator-state',
        names: states.named.keys,
        order: states.order
            .where(
              (key) =>
                  (key != SeparatorConfigStates.hoverKey ||
                      states.hover != null) &&
                  (key != SeparatorConfigStates.selectedKey ||
                      states.selected != null),
            )
            .toList(),
        permanentInteractionStates: false,
        binding: states.binding,
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
        availableStates: {
          AutomaticState.hover,
          if (allowSelected) AutomaticState.selected,
          if (widget.allowContentHover ||
              states.automatic.containsKey(AutomaticState.contentHover))
            AutomaticState.contentHover,
        },
        onAddAutomatic: (value) {
          _changeStates((s) {
            final override = SeparatorConfigOverride(
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
            SeparatorConfigStates(named: {name: const SuperSeparatorConfig()});
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
          for (final property in SeparatorStateProperty.values)
            property: property.label,
        },
        overrides: overlay?.properties ?? {},
        onOverride: (property, enabled) => _changeStates((s) {
          final current = s.named.containsKey(_state)
              ? SeparatorConfigOverride(
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
          final value = SeparatorConfigOverride(
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

class _SuperSeparatorEditor extends StatefulWidget {
  const _SuperSeparatorEditor({
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
  final SuperSeparatorConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding;
  final ValueChanged<SuperSeparatorConfig>? onPreviewChanged;
  final Widget? header;
  final SuperSeparatorConfig Function(SuperSeparatorConfig config)? onSave;

  @override
  State<_SuperSeparatorEditor> createState() => _SuperSeparatorEditorState();
}

class _SuperSeparatorEditorState extends State<_SuperSeparatorEditor> {
  final _form = GlobalKey<FormState>();
  late EditorWizardTab _tab = EditorWizardNavigation.resolveInitialTab(
    widget.initialTab,
    widget.dimensionDelegate,
  );
  late SuperSeparatorConfig _draft;
  late final Map<String, TextEditingController> _fields;
  late bool _dense = StyleEditorPanel.preferredDense;
  SuperSeparatorConfig? _lastPreview;
  String? _liveError;

  static String _hex(Color? color) => color == null
      ? ''
      : color.toARGB32().toRadixString(16).padLeft(8, '0');

  @override
  void initState() {
    super.initState();
    _draft = widget.config;
    _fields = {
      'label': TextEditingController(text: _draft.label),
      'extent': TextEditingController(text: _draft.extent.toString()),
      'thickness': TextEditingController(text: _draft.thickness.toString()),
      'indent': TextEditingController(text: _draft.indent.toString()),
      'endIndent': TextEditingController(text: _draft.endIndent.toString()),
      'labelSpacing': TextEditingController(
        text: _draft.labelSpacing.toString(),
      ),
      'fontSize': TextEditingController(
        text: _draft.fontSize?.toString() ?? '',
      ),
      'letterSpacing': TextEditingController(
        text: _draft.letterSpacing?.toString() ?? '',
      ),
      'lineColor': TextEditingController(text: _hex(_draft.lineColor)),
      'color': TextEditingController(text: _hex(_draft.color)),
    };
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  SuperSeparatorConfig? capture() {
    if (!_form.currentState!.validate()) return null;
    try {
      return _configuration();
    } on FormatException catch (e) {
      setState(() => _liveError = e.message);
    } on ArgumentError {
      setState(() => _liveError = 'Réglages du séparateur invalides.');
    }
    return null;
  }

  SuperSeparatorConfig _configuration() {
    double? number(
      String key, {
      bool allowZero = false,
      bool allowNegative = false,
    }) {
      final text = _fields[key]!.text.trim();
      if (text.isEmpty) return null;
      final value = double.tryParse(text.replaceAll(',', '.'));
      if (value == null ||
          !value.isFinite ||
          (!allowNegative && (allowZero ? value < 0 : value <= 0))) {
        throw const FormatException('Valeur numérique invalide.');
      }
      return value;
    }

    Color? colorField(String key) {
      final text = _fields[key]!.text.trim();
      if (text.isEmpty) return null;
      if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(text)) {
        throw const FormatException('Couleur AARRGGBB à 8 chiffres requise.');
      }
      return Color(int.parse(text, radix: 16));
    }

    if (_draft.fontFamily != null &&
        !widget.availableFontFamilies.contains(_draft.fontFamily)) {
      throw const FormatException('Choisissez une police disponible.');
    }

    final extent = number('extent', allowZero: true) ?? 16;
    final thickness = number('thickness') ?? 1;
    final indent = number('indent', allowZero: true) ?? 0;
    final endIndent = number('endIndent', allowZero: true) ?? 0;
    final labelSpacing = number('labelSpacing', allowZero: true) ?? 8;
    final fontSize = number('fontSize');
    final letterSpacing = number(
      'letterSpacing',
      allowZero: true,
      allowNegative: true,
    );
    final lineColor = colorField('lineColor');
    final color = colorField('color');

    final result = _draft.copyWith(
      label: _fields['label']!.text,
      extent: extent,
      thickness: thickness,
      indent: indent,
      endIndent: endIndent,
      labelSpacing: labelSpacing,
      fontSize: fontSize,
      inheritFontSize: fontSize == null,
      letterSpacing: letterSpacing,
      inheritLetterSpacing: letterSpacing == null,
      lineColor: lineColor,
      inheritLineColor: lineColor == null,
      color: color,
      inheritColor: color == null,
    );
    result.validate();
    return result;
  }

  void _schedulePreview() {
    if (widget.onPreviewChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      try {
        final config = _configuration();
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
        const message = 'Réglages du séparateur invalides.';
        if (_liveError != message) setState(() => _liveError = message);
      }
    });
  }

  Widget _field(
    String key,
    String label, {
    bool numeric = false,
    bool allowZero = false,
    bool allowNegative = false,
    bool colorHex = false,
  }) => TextFormField(
    key: ValueKey('super-separator-setting-$key'),
    controller: _fields[key],
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    decoration: InputDecoration(labelText: label),
    validator: (raw) {
      final value = raw?.trim() ?? '';
      if (numeric && value.isNotEmpty) {
        final number = double.tryParse(value.replaceAll(',', '.'));
        if (number == null ||
            !number.isFinite ||
            (!allowNegative && (allowZero ? number < 0 : number <= 0))) {
          return 'Valeur numérique valide requise.';
        }
      } else if (colorHex &&
          value.isNotEmpty &&
          !RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(value)) {
        return 'Couleur AARRGGBB à 8 chiffres hexadécimaux requise.';
      }
      return null;
    },
  );

  Future<void> _editPropertyBinding(
    SuperSeparatorProperty property,
    String label,
  ) async {
    final result = await showRepositoryBindingDialog(
      context: context,
      title: 'Lier $label',
      keyPrefix: 'super-separator-property-${property.name}',
      pathHint: 'client.${property.name}',
      binding: _draft.propertyBindings[property],
      store: widget.repositories,
      listScope: widget.listScope,
      helper: 'Lecture seule : la valeur du repository remplace ce paramètre.',
    );
    if (result == null || !mounted) return;
    final bindings = Map<SuperSeparatorProperty, JsonTextBinding>.of(
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
    SuperSeparatorProperty property,
    String label,
    Widget child,
  ) {
    final binding = _draft.propertyBindings[property];
    final canBind = widget.allowBinding && widget.repositories != null;
    return RepositoryBoundPropertyTile(
      buttonKey: ValueKey('super-separator-bind-${property.name}'),
      keyPrefix: 'super-separator-bind-${property.name}',
      binding: binding,
      tooltip: binding != null
          ? 'Modifier la liaison de $label'
          : 'Lier $label à un repository',
      onPressed: !canBind ? null : () => _editPropertyBinding(property, label),
      onClear: !canBind || binding == null
          ? null
          : () {
              final bindings = Map<SuperSeparatorProperty, JsonTextBinding>.of(
                _draft.propertyBindings,
              )..remove(property);
              setState(
                () => _draft = _draft.copyWith(propertyBindings: bindings),
              );
            },
      child: child,
    );
  }

  Widget _colorSetting({
    required String fieldKey,
    required String label,
    required Color fallbackColor,
    required SuperSeparatorProperty property,
  }) {
    final raw = _fields[fieldKey]!.text.trim();
    final current = RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(raw)
        ? Color(int.parse(raw, radix: 16))
        : fallbackColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        styleColorTile(
          label,
          current,
          (color) => setState(() {
            _fields[fieldKey]!.text = color
                .toARGB32()
                .toRadixString(16)
                .padLeft(8, '0');
          }),
          key: ValueKey('super-separator-color-picker-$fieldKey'),
          onClear: () => setState(() => _fields[fieldKey]!.clear()),
        ),
        _withBinding(
          property,
          label.toLowerCase(),
          _field(fieldKey, '$label AARRGGBB (vide = thème)', colorHex: true),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: ValueKey('super-separator-inherit-$fieldKey'),
            onPressed: raw.isEmpty
                ? null
                : () => setState(() => _fields[fieldKey]!.clear()),
            child: const Text('Utiliser la couleur du thème'),
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

  Widget _preview(bool unavailable) {
    SuperSeparatorConfig previewConfig;
    try {
      previewConfig = _configuration();
    } on Object {
      previewConfig = _draft.copyWith(label: _fields['label']!.text);
    }
    final style = widget.textStyle.copyWith(
      fontFamily: unavailable ? null : previewConfig.fontFamily,
      fontSize: previewConfig.fontSize,
      fontWeight: previewConfig.fontWeight,
      fontStyle: previewConfig.italic == null
          ? null
          : previewConfig.italic!
          ? FontStyle.italic
          : FontStyle.normal,
      color: previewConfig.color,
      letterSpacing: previewConfig.letterSpacing,
    );
    final scheme = Theme.of(context).colorScheme;
    final isHorizontal = previewConfig.axis == Axis.horizontal;
    return Card(
      key: const ValueKey('super-separator-preview'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Aperçu', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              height: isHorizontal ? 100 : 120,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Center(
                child: SizedBox(
                  width: isHorizontal ? double.infinity : null,
                  height: isHorizontal ? null : double.infinity,
                  child: buildSuperSeparatorVisual(
                    context: context,
                    config: previewConfig,
                    textStyle: style,
                  ),
                ),
              ),
            ),
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
    final scheme = Theme.of(context).colorScheme;
    final delegate = widget.dimensionDelegate;
    final onDimensions = _tab == EditorWizardTab.dimensions && delegate != null;
    void handleApply() {
      if (delegate != null && !delegate.validate()) {
        if (_tab != EditorWizardTab.dimensions) {
          setState(() => _tab = EditorWizardTab.dimensions);
        }
        return;
      }
      if (_form.currentState != null && !_form.currentState!.validate()) {
        if (_tab != EditorWizardTab.properties) {
          setState(() => _tab = EditorWizardTab.properties);
        }
        return;
      }
      SuperSeparatorConfig result;
      try {
        final leaf = _configuration();
        result = widget.onSave?.call(leaf) ?? leaf;
      } on FormatException catch (e) {
        setState(() {
          _liveError = e.message;
          _tab = EditorWizardTab.properties;
        });
        return;
      } on ArgumentError {
        setState(() {
          _liveError = 'Combinaison de propriétés invalide.';
          _tab = EditorWizardTab.properties;
        });
        return;
      }
      Navigator.of(context).pop(result);
    }

    return AlertDialog(
      key: const ValueKey('super-separator-settings'),
      insetPadding: const EdgeInsets.all(24),
      constraints: BoxConstraints(maxWidth: width + 48),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EditorWizardTabBar(
              selectedTab: _tab,
              propertiesEnabled: true,
              dimensionsEnabled: delegate != null,
              onTabSelected: (next) {
                if (next != _tab) setState(() => _tab = next);
              },
            ),
            const SizedBox(height: 12),
            if (onDimensions)
              Expanded(child: EditorDimensionTabView(delegate: delegate))
            else
              Expanded(
                child: Form(
                  key: _form,
                  onChanged: () => setState(() {}),
                  child: StyleEditorPanel(
                    label: delegate?.editableLabel ?? 'Configurer le séparateur',
                    onLabelChanged: delegate?.onLabelChanged,
                    dense: _dense,
                    onDenseChanged: (value) => setState(() {
                      _dense = value;
                      widget.onWidthChanged(value ? 680 : 1080);
                    }),
                    preview: _preview(unavailable),
                    sections: [
                      if (widget.header != null)
                        StyleEditorSection(
                          id: 'separator-states',
                          title: 'États',
                          icon: Icons.layers_outlined,
                          child: widget.header!,
                        ),
                      StyleEditorSection(
                        id: 'separator-content',
                        title: 'Type, orientation et dimensions',
                        icon: Icons.horizontal_rule,
                        tag: 'kind · axis · extent · indent',
                        child: _group([
                          const Text(
                            'Type de composant',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SegmentedButton<SuperSeparatorKind>(
                            key: const ValueKey('super-separator-setting-kind'),
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: SuperSeparatorKind.divider,
                                tooltip: 'Trait de séparation (Divider)',
                                icon: Icon(Icons.horizontal_rule, size: 16),
                                label: Text(
                                  'Divider (trait)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ButtonSegment(
                                value: SuperSeparatorKind.spacer,
                                tooltip: 'Espace vide (Spacer)',
                                icon: Icon(Icons.space_bar, size: 16),
                                label: Text(
                                  'Spacer (espace)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            selected: {_draft.kind},
                            onSelectionChanged: (selected) {
                              if (selected.isNotEmpty) {
                                setState(
                                  () => _draft = _draft.copyWith(
                                    kind: selected.first,
                                  ),
                                );
                              }
                            },
                          ),
                          const Text(
                            'Orientation',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SegmentedButton<Axis>(
                            key: const ValueKey('super-separator-setting-axis'),
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: Axis.horizontal,
                                tooltip: 'Horizontal',
                                icon: Icon(Icons.swap_horiz, size: 16),
                                label: Text(
                                  'Horizontal',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ButtonSegment(
                                value: Axis.vertical,
                                tooltip: 'Vertical',
                                icon: Icon(Icons.swap_vert, size: 16),
                                label: Text(
                                  'Vertical',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            selected: {_draft.axis},
                            onSelectionChanged: (selected) {
                              if (selected.isNotEmpty) {
                                setState(
                                  () => _draft = _draft.copyWith(
                                    axis: selected.first,
                                  ),
                                );
                              }
                            },
                          ),
                          _withBinding(
                            SuperSeparatorProperty.extent,
                            'la taille / l’espace',
                            _field(
                              'extent',
                              _draft.axis == Axis.horizontal
                                  ? 'Hauteur / espace total (px)'
                                  : 'Largeur / espace total (px)',
                              numeric: true,
                              allowZero: true,
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: _withBinding(
                                  SuperSeparatorProperty.indent,
                                  'le retrait de début',
                                  _field(
                                    'indent',
                                    'Retrait début (indent px)',
                                    numeric: true,
                                    allowZero: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _withBinding(
                                  SuperSeparatorProperty.endIndent,
                                  'le retrait de fin',
                                  _field(
                                    'endIndent',
                                    'Retrait fin (endIndent px)',
                                    numeric: true,
                                    allowZero: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ]),
                      ),
                      if (_draft.kind.isDivider)
                        StyleEditorSection(
                          id: 'separator-line',
                          title: 'Style et couleur du trait',
                          icon: Icons.line_style,
                          tag: 'lineStyle · thickness · lineColor',
                          child: _group([
                            const Text(
                              'Style du trait',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SegmentedButton<SuperSeparatorLineStyle>(
                              key: const ValueKey(
                                'super-separator-setting-lineStyle',
                              ),
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: SuperSeparatorLineStyle.solid,
                                  tooltip: 'Continu',
                                  icon: Icon(Icons.horizontal_rule, size: 16),
                                  label: Text(
                                    'Continu',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                ButtonSegment(
                                  value: SuperSeparatorLineStyle.dashed,
                                  tooltip: 'Tireté',
                                  icon: Icon(Icons.power_input, size: 16),
                                  label: Text(
                                    'Tireté',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                ButtonSegment(
                                  value: SuperSeparatorLineStyle.dotted,
                                  tooltip: 'Pointillé',
                                  icon: Icon(Icons.more_horiz, size: 16),
                                  label: Text(
                                    'Pointillé',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              selected: {_draft.lineStyle},
                              onSelectionChanged: (selected) {
                                if (selected.isNotEmpty) {
                                  setState(
                                    () => _draft = _draft.copyWith(
                                      lineStyle: selected.first,
                                    ),
                                  );
                                }
                              },
                            ),
                            _withBinding(
                              SuperSeparatorProperty.thickness,
                              'l’épaisseur du trait',
                              _field(
                                'thickness',
                                'Épaisseur du trait (px)',
                                numeric: true,
                              ),
                            ),
                            _colorSetting(
                              fieldKey: 'lineColor',
                              label: 'Couleur du trait',
                              fallbackColor: scheme.outlineVariant,
                              property: SuperSeparatorProperty.lineColor,
                            ),
                          ]),
                        ),
                      StyleEditorSection(
                        id: 'separator-label-typography',
                        title: 'Libellé et typographie',
                        icon: Icons.text_fields,
                        tag: 'label · labelPosition · TextStyle',
                        child: _group([
                          _withBinding(
                            SuperSeparatorProperty.label,
                            'le libellé',
                            _field(
                              'label',
                              'Libellé optionnel (vide = sans texte)',
                            ),
                          ),
                          const Text(
                            'Position du libellé',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SegmentedButton<SuperSeparatorLabelPosition>(
                            key: const ValueKey(
                              'super-separator-setting-labelPosition',
                            ),
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: SuperSeparatorLabelPosition.start,
                                tooltip: 'Début',
                                icon: Icon(Icons.align_horizontal_left, size: 16),
                                label: Text(
                                  'Début',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ButtonSegment(
                                value: SuperSeparatorLabelPosition.center,
                                tooltip: 'Centre',
                                icon: Icon(
                                  Icons.align_horizontal_center,
                                  size: 16,
                                ),
                                label: Text(
                                  'Centre',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ButtonSegment(
                                value: SuperSeparatorLabelPosition.end,
                                tooltip: 'Fin',
                                icon: Icon(
                                  Icons.align_horizontal_right,
                                  size: 16,
                                ),
                                label: Text(
                                  'Fin',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            selected: {_draft.labelPosition},
                            onSelectionChanged: (selected) {
                              if (selected.isNotEmpty) {
                                setState(
                                  () => _draft = _draft.copyWith(
                                    labelPosition: selected.first,
                                  ),
                                );
                              }
                            },
                          ),
                          _field(
                            'labelSpacing',
                            'Espacement trait / libellé (px)',
                            numeric: true,
                            allowZero: true,
                          ),
                          if (unavailable)
                            Text(
                              'Police indisponible : ${_draft.fontFamily}. Choisissez une police disponible.',
                              style: TextStyle(color: scheme.error),
                            ),
                          _withBinding(
                            SuperSeparatorProperty.fontFamily,
                            'la police',
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              key: ValueKey(
                                'super-separator-setting-fontFamily-${_draft.fontFamily}',
                              ),
                              initialValue: unavailable
                                  ? null
                                  : _draft.fontFamily,
                              hint: const Text('Police du thème'),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('Police du thème'),
                                ),
                                for (final font in fonts)
                                  DropdownMenuItem(
                                    value: font,
                                    child: Text(font),
                                  ),
                              ],
                              onChanged: (font) => setState(
                                () => _draft = _draft.copyWith(
                                  fontFamily: font,
                                  inheritFontFamily:
                                      font == null || font.isEmpty,
                                ),
                              ),
                              validator: (_) => unavailable
                                  ? 'Choisissez une police disponible.'
                                  : null,
                            ),
                          ),
                          _withBinding(
                            SuperSeparatorProperty.fontSize,
                            'la taille de police',
                            _field(
                              'fontSize',
                              'Taille de police (vide = thème)',
                              numeric: true,
                            ),
                          ),
                          _withBinding(
                            SuperSeparatorProperty.fontWeight,
                            'la graisse',
                            DropdownButtonFormField<FontWeight>(
                              isExpanded: true,
                              initialValue: _draft.fontWeight,
                              decoration: const InputDecoration(
                                labelText: 'Graisse',
                              ),
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
                            SuperSeparatorProperty.italic,
                            'le style italique',
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 4,
                              children: [
                                const Text(
                                  'Style de police',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SegmentedButton<String>(
                                  key: const ValueKey(
                                    'super-separator-setting-italic',
                                  ),
                                  showSelectedIcon: false,
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  segments: const [
                                    ButtonSegment(
                                      value: 'inherit',
                                      tooltip: 'Style du parent',
                                      icon: Icon(
                                        Icons.hdr_auto_outlined,
                                        size: 16,
                                      ),
                                      label: Text(
                                        'Style du parent',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'normal',
                                      tooltip: 'Normal',
                                      icon: Icon(Icons.text_format, size: 16),
                                      label: Text(
                                        'Normal',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'italic',
                                      tooltip: 'Italique',
                                      icon: Icon(Icons.format_italic, size: 16),
                                      label: Text(
                                        'Italique',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  selected: {
                                    _draft.italic == null
                                        ? 'inherit'
                                        : _draft.italic!
                                        ? 'italic'
                                        : 'normal',
                                  },
                                  onSelectionChanged: (selected) {
                                    if (selected.isEmpty) return;
                                    final value = selected.first;
                                    setState(
                                      () => _draft = _draft.copyWith(
                                        italic: value == 'italic',
                                        inheritItalic: value == 'inherit',
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          _colorSetting(
                            fieldKey: 'color',
                            label: 'Couleur du libellé',
                            fallbackColor:
                                widget.textStyle.color ??
                                scheme.onSurfaceVariant,
                            property: SuperSeparatorProperty.color,
                          ),
                          _field(
                            'letterSpacing',
                            'Espacement des lettres (px)',
                            numeric: true,
                            allowZero: true,
                            allowNegative: true,
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (onDimensions)
          ...delegate.buildExtraActions(context, onResetAndClose: handleApply),
        if (_liveError != null)
          Text(
            _liveError!,
            key: const ValueKey('super-separator-live-error'),
            style: TextStyle(color: scheme.error),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: handleApply, child: const Text('Appliquer')),
      ],
    );
  }
}
