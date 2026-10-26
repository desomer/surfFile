import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/automatic_state.dart';
import '../../../models/json_text_binding.dart';
import '../../../models/super_action_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../services/states/surface_state_binding.dart';
import '../../../theme/container_style.dart';
import '../../../theme/design_system.dart';
import '../../../theme/interaction_effect.dart';
import '../../../theme/neon_style.dart';
import '../../components/super_action.dart';
import '../dialogs/editor_dialog.dart';
import '../icons/material_icon_picker.dart';
import '../repositories/repository_binding_fields.dart';
import '../states/editor_state_controls.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../styles/style_editor_panel.dart';

Future<SuperActionConfig?> showSuperActionEditor({
  required BuildContext context,
  required SuperActionConfig config,
  required List<String> availableFontFamilies,
  bool allowBinding = true,
  ValueChanged<SuperActionConfig>? onPreviewChanged,
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
    return await showEditorDialog<SuperActionConfig>(
      context: context,
      target: context,
      preferredWidth: width,
      builder: (_) => _ActionStateEditor(
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

class _ActionStateEditor extends StatefulWidget {
  const _ActionStateEditor({
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
  final SuperActionConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding, isHovered, isSelected;
  final bool allowContentHover;
  final Set<AutomaticState> activeAutomatic;
  final ValueChanged<SuperActionConfig>? onPreviewChanged;
  final String? activeState, stateError;

  @override
  State<_ActionStateEditor> createState() => _ActionStateEditorState();
}

class _ActionStateEditorState extends State<_ActionStateEditor> {
  late SuperActionConfig _root = widget.config;
  String? _state;
  String? _error;
  GlobalKey<_SuperActionEditorState> _leafKey = GlobalKey();
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

  SuperActionConfig get _leaf {
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

  SuperActionConfig _withLeaf(SuperActionConfig leaf) {
    leaf = leaf.copyWith(clearStates: true);
    final states = _root.states ?? ActionConfigStates();
    if (_state == null) return leaf.copyWith(states: _root.states);
    final automatic = AutomaticState.fromKey(_state);
    if (automatic != null &&
        automatic != AutomaticState.hover &&
        automatic != AutomaticState.selected) {
      final previous =
          states.automatic[automatic] ??
          ActionConfigOverride(config: _root.copyWith(clearStates: true));
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
                ActionConfigOverride(config: _root.copyWith(clearStates: true)))
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
                _state!: ActionConfigOverride(
                  config: states.named[_state]!,
                  properties: states.namedProperties[_state]!,
                ).edited(leaf).properties,
              },
            ),
    );
  }

  void _validate(SuperActionConfig root) {
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

  void _preview(SuperActionConfig root) {
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
    ActionConfigStates Function(ActionConfigStates states) update,
  ) {
    if (!_capture()) return;
    try {
      final root = _root.copyWith(
        states: update(_root.states ?? ActionConfigStates()),
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
    final states = _root.states ?? ActionConfigStates();
    final automatic = AutomaticState.fromKey(_state);
    final overlay = states.named.containsKey(_state)
        ? ActionConfigOverride(
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
    return _SuperActionEditor(
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
      header: EditorStateControls<ActionStateProperty>(
        keyPrefix: 'action-state',
        names: states.named.keys,
        order: states.order
            .where(
              (key) =>
                  (key != ActionConfigStates.hoverKey ||
                      states.hover != null) &&
                  (key != ActionConfigStates.selectedKey ||
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
          AutomaticState.focused,
          AutomaticState.disabled,
        },
        onAddAutomatic: (value) {
          _changeStates((s) {
            final override = ActionConfigOverride(
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
            ActionConfigStates(named: {name: const SuperActionConfig()});
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
          for (final property in ActionStateProperty.values)
            property: property.label,
        },
        overrides: overlay?.properties ?? {},
        onOverride: (property, enabled) => _changeStates((s) {
          final current = s.named.containsKey(_state)
              ? ActionConfigOverride(
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
          final value = ActionConfigOverride(
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

class _SuperActionEditor extends StatefulWidget {
  const _SuperActionEditor({
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

  final SuperActionConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding;
  final ValueChanged<SuperActionConfig>? onPreviewChanged;
  final Widget? header;
  final SuperActionConfig Function(SuperActionConfig config)? onSave;

  @override
  State<_SuperActionEditor> createState() => _SuperActionEditorState();
}

class _SuperActionEditorState extends State<_SuperActionEditor> {
  final _form = GlobalKey<FormState>();
  late SuperActionConfig _draft;
  late final Map<String, TextEditingController> _fields;
  late bool _dense = StyleEditorPanel.preferredDense;
  SuperActionConfig? _lastPreview;
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
      'tooltip': TextEditingController(text: _draft.tooltip),
      'fontSize': TextEditingController(
        text: _draft.fontSize?.toString() ?? '',
      ),
      'iconSize': TextEditingController(
        text: _draft.iconSize?.toString() ?? '',
      ),
      'iconSpacing': TextEditingController(
        text: _draft.iconSpacing.toString(),
      ),
      'letterSpacing': TextEditingController(
        text: _draft.letterSpacing?.toString() ?? '',
      ),
      'color': TextEditingController(text: _hex(_draft.color)),
      'iconColor': TextEditingController(text: _hex(_draft.iconColor)),
      'backgroundColor': TextEditingController(
        text: _hex(_draft.backgroundColor),
      ),
      'borderColor': TextEditingController(text: _hex(_draft.borderColor)),
      'radius': TextEditingController(text: _draft.radius?.toString() ?? ''),
      'borderWidth': TextEditingController(
        text: _draft.borderWidth?.toString() ?? '',
      ),
      'elevation': TextEditingController(
        text: _draft.elevation?.toString() ?? '',
      ),
      'horizontalPadding': TextEditingController(
        text: _draft.horizontalPadding?.toString() ?? '',
      ),
      'verticalPadding': TextEditingController(
        text: _draft.verticalPadding?.toString() ?? '',
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

  SuperActionConfig? capture() {
    if (!_form.currentState!.validate()) return null;
    try {
      return _configuration();
    } on FormatException catch (e) {
      setState(() => _liveError = e.message);
    } on ArgumentError {
      setState(() => _liveError = 'Réglages de l’action invalides.');
    }
    return null;
  }

  SuperActionConfig _configuration() {
    double? number(String key, {bool allowZero = false, bool allowNegative = false}) {
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

    final fontSize = number('fontSize');
    final iconSize = number('iconSize');
    final iconSpacing = number('iconSpacing', allowZero: true) ?? 8;
    final letterSpacing = number(
      'letterSpacing',
      allowZero: true,
      allowNegative: true,
    );
    final radius = number('radius', allowZero: true);
    final borderWidth = number('borderWidth', allowZero: true);
    final elevation = number('elevation', allowZero: true);
    final horizontalPadding = number('horizontalPadding', allowZero: true);
    final verticalPadding = number('verticalPadding', allowZero: true);
    final color = colorField('color');
    final iconColor = colorField('iconColor');
    final backgroundColor = colorField('backgroundColor');
    final borderColor = colorField('borderColor');

    final result = _draft.copyWith(
      label: _fields['label']!.text,
      tooltip: _fields['tooltip']!.text,
      fontSize: fontSize,
      inheritFontSize: fontSize == null,
      iconSize: iconSize,
      inheritIconSize: iconSize == null,
      iconSpacing: iconSpacing,
      letterSpacing: letterSpacing,
      inheritLetterSpacing: letterSpacing == null,
      color: color,
      inheritColor: color == null,
      iconColor: iconColor,
      inheritIconColor: iconColor == null,
      backgroundColor: backgroundColor,
      inheritBackgroundColor: backgroundColor == null,
      borderColor: borderColor,
      inheritBorderColor: borderColor == null,
      radius: radius,
      inheritRadius: radius == null,
      borderWidth: borderWidth,
      inheritBorderWidth: borderWidth == null,
      elevation: elevation,
      inheritElevation: elevation == null,
      horizontalPadding: horizontalPadding,
      inheritHorizontalPadding: horizontalPadding == null,
      verticalPadding: verticalPadding,
      inheritVerticalPadding: verticalPadding == null,
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
        const message = 'Réglages de l’action invalides.';
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
    key: ValueKey('super-action-setting-$key'),
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
    SuperActionProperty property,
    String label,
  ) async {
    final result = await showRepositoryBindingDialog(
      context: context,
      title: 'Lier $label',
      keyPrefix: 'super-action-property-${property.name}',
      pathHint: 'client.${property.name}',
      binding: _draft.propertyBindings[property],
      store: widget.repositories,
      listScope: widget.listScope,
      helper: 'Lecture seule : la valeur du repository remplace ce paramètre.',
    );
    if (result == null || !mounted) return;
    final bindings = Map<SuperActionProperty, JsonTextBinding>.of(
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
    SuperActionProperty property,
    String label,
    Widget child,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: child),
      IconButton(
        key: ValueKey('super-action-bind-${property.name}'),
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

  Widget _colorSetting({
    required String fieldKey,
    required String label,
    required Color fallbackColor,
    required SuperActionProperty property,
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
          key: ValueKey('super-action-color-picker-$fieldKey'),
        ),
        _withBinding(
          property,
          label.toLowerCase(),
          _field(fieldKey, '$label AARRGGBB (vide = thème)', colorHex: true),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: ValueKey('super-action-inherit-$fieldKey'),
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
    SuperActionConfig previewConfig;
    try {
      previewConfig = _configuration();
    } on Object {
      previewConfig = _draft.copyWith(
        label: _fields['label']!.text,
        tooltip: _fields['tooltip']!.text,
      );
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
    return Card(
      key: const ValueKey('super-action-preview'),
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
              child: Center(
                child: buildSuperActionVisual(
                  context: context,
                  config: previewConfig,
                  textStyle: style,
                  onPressed: () {},
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

    return AlertDialog(
      key: const ValueKey('super-action-settings'),
      insetPadding: const EdgeInsets.all(24),
      constraints: BoxConstraints(maxWidth: width + 48),
      content: SizedBox(
        width: width,
        height: height,
        child: Form(
          key: _form,
          onChanged: () => setState(() {}),
          child: StyleEditorPanel(
            label: 'Configurer l’action',
            dense: _dense,
            onDenseChanged: (value) => setState(() {
              _dense = value;
              widget.onWidthChanged(value ? 680 : 1080);
            }),
            preview: _preview(unavailable),
            sections: [
              if (widget.header != null)
                StyleEditorSection(
                  id: 'action-states',
                  title: 'États',
                  icon: Icons.layers_outlined,
                  child: widget.header!,
                ),
              StyleEditorSection(
                id: 'action-content',
                title: 'Contenu et type de bouton',
                icon: Icons.smart_button_outlined,
                tag: 'kind · variant · label · icon',
                child: _group([
                  DropdownButtonFormField<SuperActionKind>(
                    isExpanded: true,
                    key: const ValueKey('super-action-setting-kind'),
                    initialValue: _draft.kind,
                    decoration: const InputDecoration(
                      labelText: 'Type de bouton',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: SuperActionKind.text,
                        child: Text('Texte'),
                      ),
                      DropdownMenuItem(
                        value: SuperActionKind.icon,
                        child: Text('Icône'),
                      ),
                      DropdownMenuItem(
                        value: SuperActionKind.textAndIcon,
                        child: Text('Texte et icône'),
                      ),
                    ],
                    onChanged: (kind) {
                      if (kind != null) {
                        setState(() => _draft = _draft.copyWith(kind: kind));
                      }
                    },
                  ),
                  DropdownButtonFormField<SuperActionVariant>(
                    isExpanded: true,
                    key: const ValueKey('super-action-setting-variant'),
                    initialValue: _draft.variant,
                    decoration: const InputDecoration(
                      labelText: 'Style / variante du bouton',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: SuperActionVariant.filled,
                        child: Text('Filled (plein)'),
                      ),
                      DropdownMenuItem(
                        value: SuperActionVariant.tonal,
                        child: Text('Tonal (secondaire)'),
                      ),
                      DropdownMenuItem(
                        value: SuperActionVariant.elevated,
                        child: Text('Elevated (élevé)'),
                      ),
                      DropdownMenuItem(
                        value: SuperActionVariant.outlined,
                        child: Text('Outlined (contour)'),
                      ),
                      DropdownMenuItem(
                        value: SuperActionVariant.text,
                        child: Text('Text (sans fond)'),
                      ),
                      DropdownMenuItem(
                        value: SuperActionVariant.icon,
                        child: Text('Icon Button'),
                      ),
                      DropdownMenuItem(
                        value: SuperActionVariant.surface,
                        child: Text('Surface personnalisée (ContainerStyle)'),
                      ),
                    ],
                    onChanged: (variant) {
                      if (variant != null) {
                        setState(
                          () => _draft = _draft.copyWith(variant: variant),
                        );
                      }
                    },
                  ),
                  if (_draft.kind.hasText)
                    _withBinding(
                      SuperActionProperty.label,
                      'le libellé',
                      _field('label', 'Libellé du bouton'),
                    ),
                  if (_draft.kind.hasIcon)
                    _withBinding(
                      SuperActionProperty.icon,
                      'l’icône',
                      MaterialIconPickerField(
                        key: const ValueKey('super-action-setting-icon'),
                        label: 'Icône',
                        value: SuperActionIcons.isKnown(_draft.icon)
                            ? _draft.icon
                            : 'touch_app',
                        onChanged: (icon) {
                          if (icon != null) {
                            setState(
                              () => _draft = _draft.copyWith(icon: icon),
                            );
                          }
                        },
                      ),
                    ),
                  if (_draft.kind == SuperActionKind.textAndIcon)
                    DropdownButtonFormField<SuperActionIconPosition>(
                      isExpanded: true,
                      key: const ValueKey('super-action-setting-iconPosition'),
                      initialValue: _draft.iconPosition,
                      decoration: const InputDecoration(
                        labelText: 'Position de l’icône',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SuperActionIconPosition.leading,
                          child: Text('Début (avant le texte)'),
                        ),
                        DropdownMenuItem(
                          value: SuperActionIconPosition.trailing,
                          child: Text('Fin (après le texte)'),
                        ),
                      ],
                      onChanged: (position) {
                        if (position != null) {
                          setState(
                            () => _draft = _draft.copyWith(
                              iconPosition: position,
                            ),
                          );
                        }
                      },
                    ),
                  _withBinding(
                    SuperActionProperty.tooltip,
                    'l’infobulle',
                    _field('tooltip', 'Infobulle (tooltip)'),
                  ),
                ]),
              ),
              StyleEditorSection(
                id: 'action-behavior',
                title: 'Comportement',
                icon: Icons.tune,
                tag: 'enabled',
                child: _group([
                  _withBinding(
                    SuperActionProperty.enabled,
                    'l’activation',
                    SwitchListTile(
                      key: const ValueKey('super-action-setting-enabled'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activé'),
                      value: _draft.enabled,
                      onChanged: (value) => setState(
                        () => _draft = _draft.copyWith(enabled: value),
                      ),
                    ),
                  ),
                ]),
              ),
              StyleEditorSection(
                id: 'action-typography',
                title: 'Typographie et icône',
                icon: Icons.font_download_outlined,
                tag: 'TextStyle · Icon',
                child: _group([
                  if (unavailable)
                    Text(
                      'Police indisponible : ${_draft.fontFamily}. Choisissez une police disponible.',
                      style: TextStyle(color: scheme.error),
                    ),
                  _withBinding(
                    SuperActionProperty.fontFamily,
                    'la police',
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey(
                        'super-action-setting-fontFamily-${_draft.fontFamily}',
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
                    SuperActionProperty.fontSize,
                    'la taille de police',
                    _field(
                      'fontSize',
                      'Taille de police (vide = thème)',
                      numeric: true,
                    ),
                  ),
                  _withBinding(
                    SuperActionProperty.iconSize,
                    'la taille de l’icône',
                    _field(
                      'iconSize',
                      'Taille de l’icône (vide = thème)',
                      numeric: true,
                    ),
                  ),
                  if (_draft.kind == SuperActionKind.textAndIcon)
                    _field(
                      'iconSpacing',
                      'Espacement icône / texte (px)',
                      numeric: true,
                      allowZero: true,
                    ),
                  _withBinding(
                    SuperActionProperty.fontWeight,
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
                    SuperActionProperty.italic,
                    'le style italique',
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: const ValueKey('super-action-setting-italic'),
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
                  _withBinding(
                    SuperActionProperty.textAlign,
                    'l’alignement',
                    DropdownButtonFormField<TextAlign>(
                      isExpanded: true,
                      key: const ValueKey('super-action-setting-textAlign'),
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
                    'letterSpacing',
                    'Espacement des lettres (px)',
                    numeric: true,
                    allowZero: true,
                    allowNegative: true,
                  ),
                ]),
              ),
              StyleEditorSection(
                id: 'action-colors-shape',
                title: 'Couleurs et forme du bouton',
                icon: Icons.palette_outlined,
                tag: 'color · background · border · radius',
                child: _group([
                  _colorSetting(
                    fieldKey: 'color',
                    label: 'Couleur du texte / contenu',
                    fallbackColor:
                        widget.textStyle.color ?? scheme.onPrimary,
                    property: SuperActionProperty.color,
                  ),
                  if (_draft.kind.hasIcon)
                    _colorSetting(
                      fieldKey: 'iconColor',
                      label: 'Couleur de l’icône',
                      fallbackColor:
                          _draft.color ?? scheme.onPrimary,
                      property: SuperActionProperty.iconColor,
                    ),
                  _colorSetting(
                    fieldKey: 'backgroundColor',
                    label: 'Couleur de fond',
                    fallbackColor: scheme.primary,
                    property: SuperActionProperty.backgroundColor,
                  ),
                  _colorSetting(
                    fieldKey: 'borderColor',
                    label: 'Couleur de bordure',
                    fallbackColor: scheme.outline,
                    property: SuperActionProperty.borderColor,
                  ),
                  _withBinding(
                    SuperActionProperty.radius,
                    'le rayon',
                    _field(
                      'radius',
                      'Rayon des coins (vide = thème)',
                      numeric: true,
                      allowZero: true,
                    ),
                  ),
                  _withBinding(
                    SuperActionProperty.borderWidth,
                    'l’épaisseur de bordure',
                    _field(
                      'borderWidth',
                      'Épaisseur de bordure (vide = thème)',
                      numeric: true,
                      allowZero: true,
                    ),
                  ),
                  _withBinding(
                    SuperActionProperty.elevation,
                    'l’élévation',
                    _field(
                      'elevation',
                      'Élévation (vide = thème)',
                      numeric: true,
                      allowZero: true,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          'horizontalPadding',
                          'Marge interne H (px)',
                          numeric: true,
                          allowZero: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          'verticalPadding',
                          'Marge interne V (px)',
                          numeric: true,
                          allowZero: true,
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
              StyleEditorSection(
                id: 'action-surface',
                title: 'Effets et surface avancés',
                icon: Icons.auto_fix_high_outlined,
                tag: 'ContainerStyle',
                child: _group([
                  DropdownButtonFormField<DesignSystem>(
                    isExpanded: true,
                    key: const ValueKey('super-action-setting-designSystem'),
                    initialValue: _draft.style.designSystem,
                    decoration: const InputDecoration(
                      labelText: 'Système de design (Surface)',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: DesignSystem.material,
                        child: Text('Material'),
                      ),
                      DropdownMenuItem(
                        value: DesignSystem.liquidGlass,
                        child: Text('Liquid Glass'),
                      ),
                      DropdownMenuItem(
                        value: DesignSystem.neumorphism,
                        child: Text('Neumorphism'),
                      ),
                    ],
                    onChanged: (ds) {
                      if (ds != null) {
                        setState(
                          () => _draft = _draft.copyWith(
                            style: _draft.style.copyWith(designSystem: ds),
                          ),
                        );
                      }
                    },
                  ),
                  DropdownButtonFormField<InteractionEffect>(
                    isExpanded: true,
                    key: const ValueKey(
                      'super-action-setting-interactionEffect',
                    ),
                    initialValue: _draft.style.interactionEffect,
                    decoration: const InputDecoration(
                      labelText: 'Effet d’interaction (Surface)',
                    ),
                    items: [
                      for (final effect in InteractionEffect.values)
                        DropdownMenuItem(
                          value: effect,
                          child: Text(effect.label),
                        ),
                    ],
                    onChanged: (effect) {
                      if (effect != null) {
                        setState(
                          () => _draft = _draft.copyWith(
                            style: _draft.style.copyWith(
                              interactionEffect: effect,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  SwitchListTile(
                    key: const ValueKey('super-action-setting-hoverEffect'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Voile au survol (Surface)'),
                    value: _draft.style.hoverEffect,
                    onChanged: (value) => setState(
                      () => _draft = _draft.copyWith(
                        style: _draft.style.copyWith(hoverEffect: value),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    key: const ValueKey('super-action-setting-neon'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Effet néon'),
                    value: _draft.style.neon?.enabled ?? false,
                    onChanged: (enabled) => setState(
                      () => _draft = _draft.copyWith(
                        style: _draft.style.copyWith(
                          neon: (_draft.style.neon ?? const NeonStyle())
                              .copyWith(enabled: enabled),
                        ),
                      ),
                    ),
                  ),
                  if (_draft.style != const ContainerStyle())
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey('super-action-reset-surface'),
                        onPressed: () => setState(
                          () => _draft = _draft.copyWith(
                            style: const ContainerStyle(),
                          ),
                        ),
                        child: const Text('Réinitialiser la surface avancée'),
                      ),
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_liveError != null)
          Text(
            _liveError!,
            key: const ValueKey('super-action-live-error'),
            style: TextStyle(color: scheme.error),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            SuperActionConfig result;
            try {
              final leaf = _configuration();
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
            Navigator.of(context).pop(result);
          },
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}
