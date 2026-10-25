import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;

import 'package:material_ui/material_ui.dart';

import '../../models/super_value_config.dart';
import '../../models/automatic_state.dart';
import '../../services/states/content_hover_scope.dart';
import '../../models/json_text_binding.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/repositories/json_text_controller_binding.dart';
import '../../services/states/surface_state_binding.dart';
import '../../super_app.dart';
import '../editing/history/editor_history.dart';
import '../editing/components/super_value_editor.dart';
import 'super_text_field.dart';
import '../editing/slots/editor_slot.dart';
import '../super_layout/slot_implementation.dart';

Object _parseBoundProperty(SuperValueProperty property, Object? value) {
  switch (property) {
    case SuperValueProperty.label:
    case SuperValueProperty.placeholder:
    case SuperValueProperty.fontFamily:
      if (value is! String ||
          (property == SuperValueProperty.fontFamily && value.trim().isEmpty)) {
        throw FormatException(
          'La valeur liée à ${property.name} doit être un texte valide.',
        );
      }
      return value;
    case SuperValueProperty.color:
      if (value is int && value >= 0 && value <= 0xFFFFFFFF) {
        return Color(value);
      }
      if (value is String) {
        final hex = value.trim().replaceFirst(RegExp(r'^#'), '');
        if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
          return Color(0xFF000000 | int.parse(hex, radix: 16));
        }
        if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) {
          return Color(int.parse(hex, radix: 16));
        }
      }
      throw const FormatException(
        'La couleur liée doit être un entier ARGB ou un hexadécimal RGB/ARGB.',
      );
    case SuperValueProperty.fontSize:
      final number = value is num
          ? value.toDouble()
          : value is String
          ? double.tryParse(value.trim().replaceAll(',', '.'))
          : null;
      if (number == null || !number.isFinite || number <= 0) {
        throw const FormatException(
          'La taille de police liée doit être un nombre positif.',
        );
      }
      return number;
    case SuperValueProperty.fontWeight:
      final weight = switch (value) {
        int weightValue =>
          FontWeight.values
              .where((weight) => weight.value == weightValue)
              .firstOrNull,
        String text => switch (text.trim().toLowerCase()) {
          'normal' => FontWeight.w400,
          'bold' => FontWeight.w700,
          final value when RegExp(r'^(?:w)?[1-9]00$').hasMatch(value) =>
            FontWeight.values
                .where(
                  (weight) =>
                      weight.value == int.parse(value.replaceFirst('w', '')),
                )
                .firstOrNull,
          _ => null,
        },
        _ => null,
      };
      if (weight == null) {
        throw const FormatException(
          'La graisse liée doit être normal, bold ou une valeur 100–900.',
        );
      }
      return weight;
    case SuperValueProperty.italic:
      if (value is bool) return value;
      if (value is String) {
        return switch (value.trim().toLowerCase()) {
          'true' || 'italic' => true,
          'false' || 'normal' => false,
          _ => throw const FormatException(
            'Le style italique lié doit être true/false ou italic/normal.',
          ),
        };
      }
      throw const FormatException(
        'Le style italique lié doit être un booléen ou un texte.',
      );
    case SuperValueProperty.textAlign:
      if (value is String) {
        final align = TextAlign.values
            .where((candidate) => candidate.name == value.trim().toLowerCase())
            .firstOrNull;
        if (align != null) return align;
      }
      throw const FormatException(
        'L’alignement lié doit être start, end, left, right, center ou justify.',
      );
  }
}

/// Display or edit a value (text, checkbox or switch); runtime input persists
/// only with a repository binding.
class SuperValue extends StatefulWidget {
  const SuperValue({
    required this.id,
    this.config = const SuperValueConfig(),
    this.controller,
    this.value,
    this.boolValue,
    this.onChanged,
    this.onBoolChanged,
    this.onConfigChanged,
    this.availableFontFamilies = const [],
    super.key,
  }) : assert(
         controller == null || (value == null && boolValue == null),
         'Use either controller or value, not both.',
       ),
       assert(
         value == null || boolValue == null,
         'Use either value or boolValue, not both.',
       );

  final String id;
  final SuperValueConfig config;
  final TextEditingController? controller;
  final String? value;
  final bool? boolValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<bool>? onBoolChanged;
  final ValueChanged<SuperValueConfig>? onConfigChanged;
  final List<String> availableFontFamilies;

  @override
  State<SuperValue> createState() => _SuperValueState();
}

class _SuperValueState extends State<SuperValue> {
  final _surface = GlobalKey<EditorSlotState>();
  late final TextEditingController _internal;
  late final ValueNotifier<SuperValueConfig> _local;
  SuperValueConfig? _previousConfig;
  int _resetGeneration = 0;
  JsonTextControllerBinding? _binding;
  JsonTextBinding? _requestedBinding;
  JsonRepositoryStore? _requestedStore;
  bool? _requestedExternal;
  bool? _requestedAsBool;
  String? _requestedResolveError;
  bool _requestedPlaceholder = false;
  int _bindingGeneration = 0;
  String? _bindingError;
  Map<SuperValueProperty, Object> _boundPropertyValues = const {};
  Map<SuperValueProperty, String> _propertyBindingErrors = const {};
  List<JsonArrayBinding> _propertySelections = const [];
  Map<SuperValueProperty, JsonTextBinding> _activePropertyBindings = const {};
  Map<SuperValueProperty, JsonTextBinding>? _requestedPropertyBindings;
  JsonRepositoryStore? _requestedPropertyStore;
  String? _requestedPropertyRepositoryId;
  List<int> _requestedPropertyIndices = const [];
  bool _requestedPropertyPlaceholder = false;
  bool _refreshPropertyBindings = true;
  int _propertyBindingGeneration = 0;

  /// A `[?]` resolved by a selection has no selected row: empty and read-only.
  bool _unselected = false;

  /// Selections the binding path depends on.
  List<JsonArrayBinding> _selections = const [];
  SuperValueConfig? _editorConfig;
  TextEditingController? _editorText;
  SurfaceStateBinding? _stateReader;
  bool _hovered = false;
  List<String>? _activeStates;
  String? _stateError;
  SuperValueConfig? _effectiveConfig;
  bool _hadStates = false;
  final _focusNode = FocusNode();
  Set<AutomaticState> _automaticActive = {};
  Future<void>? _pendingBindingFlush;

  static String _initialTextFor(SuperValueConfig config) =>
      config.kind.isBoolean
      ? (config.initialBool ? 'true' : 'false')
      : (config.obscureText ? '' : config.initialText);

  void _stateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  SuperValueConfig _resolveStates(
    SuperValueConfig saved,
    JsonListScope? scope,
    JsonRepositoryStore? store,
    bool contentHovered,
  ) {
    final binding = saved.states?.binding;
    if (binding == null) {
      _stateReader?.removeListener(_stateChanged);
      _stateReader?.dispose();
      _stateReader = null;
    } else if (_stateReader == null) {
      _stateReader = SurfaceStateBinding(
        store: store,
        binding: binding,
        scope: scope,
        placeholder: scope?.placeholder ?? false,
      )..addListener(_stateChanged);
    } else {
      _stateReader!.reconfigure(
        store: store,
        binding: binding,
        scope: scope,
        placeholder: scope?.placeholder ?? false,
      );
    }
    _stateError = _stateReader?.error;
    try {
      final source =
          saved.states?.resolve(saved, name: _stateReader?.stateName) ??
          saved.copyWith(clearStates: true);
      final input = source.mode == SuperValueMode.input;
      _automaticActive = {
        if (contentHovered) AutomaticState.contentHover,
        if (input && _focusNode.hasFocus) AutomaticState.focused,
        if (input && !source.enabled) AutomaticState.disabled,
        if (input && source.readOnly) AutomaticState.readOnly,
      };
      final config =
          saved.states?.resolve(
            saved,
            name: _stateReader?.stateName,
            isHovered: _hovered,
            isSelected: scope?.selected ?? false,
            activeStates: _automaticActive,
          ) ??
          saved;
      config.validate();
      return config;
    } on FormatException catch (error) {
      _stateError = error.message;
    } on ArgumentError {
      _stateError = 'Combinaison d’états de la valeur invalide.';
    }
    return saved.copyWith(clearStates: true);
  }

  TextEditingController get _text => widget.controller ?? _internal;

  String? get _controlledText =>
      widget.boolValue != null ? '${widget.boolValue}' : widget.value;

  @override
  void initState() {
    super.initState();
    widget.config.copyWith(clearStates: true).validate();
    _internal = TextEditingController(
      text: _controlledText ?? _initialTextFor(widget.config),
    );
    _local = ValueNotifier(widget.config);
    _focusNode.addListener(_stateChanged);
  }

  @override
  void didUpdateWidget(SuperValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null &&
        (widget.value != null || widget.boolValue != null)) {
      throw ArgumentError('Use either controller or value, not both.');
    }
    if (widget.value != null && widget.boolValue != null) {
      throw ArgumentError('Use either value or boolValue, not both.');
    }
    widget.config.copyWith(clearStates: true).validate();
    if (oldWidget.config != widget.config) _local.value = widget.config;
    if (oldWidget.id != widget.id) {
      _previousConfig = null;
      _resetGeneration++;
      _requestedExternal = null;
      _requestedAsBool = null;
      _activeStates = null;
      _effectiveConfig = null;
    }
    final controlled = _controlledText;
    if (widget.controller == null) {
      if (controlled != null && controlled != _internal.text) {
        _setText(_internal, controlled);
      } else if (oldWidget.controller != null && controlled == null) {
        _setText(_internal, oldWidget.controller!.text);
      }
    }
  }

  void _setText(TextEditingController controller, String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _observeConfig(SuperValueConfig config) {
    config.validate();
    final previous = _previousConfig;
    _previousConfig = config;
    if (config.binding != null) {
      _resetGeneration++;
      return;
    }
    if (previous == null) {
      if (widget.controller == null && _controlledText == null) {
        _setText(_internal, _initialTextFor(config));
      }
      return;
    }
    if (previous.mode == config.mode &&
        previous.kind == config.kind &&
        previous.initialText == config.initialText &&
        previous.initialBool == config.initialBool &&
        previous.binding == null &&
        (!config.obscureText || previous.obscureText)) {
      return;
    }
    final generation = ++_resetGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _resetGeneration) return;
      final text = _initialTextFor(config);
      if (_controlledText == null) _setText(_text, text);
      widget.onChanged?.call(text);
      if (config.kind.isBoolean) {
        widget.onBoolChanged?.call(config.initialBool);
      }
    });
  }

  /// Concrete binding of this row: inherited repository and `[?]` indices.
  ///
  /// `placeholder` is set for a template row and for a `[?]` without selected
  /// row; both show an empty text.
  ({
    JsonTextBinding? binding,
    String? error,
    bool placeholder,
    List<JsonArrayBinding> selections,
  })
  _resolve(
    SuperValueConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final binding = config.binding;
    if (binding == null || (scope?.placeholder ?? false)) {
      return (
        binding: null,
        error: null,
        placeholder: binding != null,
        selections: const [],
      );
    }
    try {
      final resolved = JsonListScope.resolveSelected(binding, scope, store);
      return (
        binding: resolved.binding,
        error: null,
        placeholder: resolved.binding == null,
        selections: resolved.arrays,
      );
    } on FormatException catch (error) {
      return (
        binding: null,
        error: error.message,
        placeholder: false,
        selections: const [],
      );
    }
  }

  void _listenSelections(List<JsonArrayBinding> selections) {
    if (listEquals(_selections, selections)) return;
    for (final selection in _selections) {
      selection.removeListener(_selectionChanged);
    }
    _selections = selections;
    for (final selection in selections) {
      selection.addListener(_selectionChanged);
    }
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  void _observeBinding(
    SuperValueConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store, {
    bool resetText = false,
    bool stateful = false,
  }) {
    final external = widget.controller != null || _controlledText != null;
    final asBool = config.kind.isBoolean;
    final resolved = _resolve(config, scope, store);
    _listenSelections(resolved.selections);
    if (!resetText &&
        _requestedBinding == resolved.binding &&
        _requestedResolveError == resolved.error &&
        _requestedPlaceholder == resolved.placeholder &&
        _requestedStore == store &&
        _requestedExternal == external &&
        _requestedAsBool == asBool) {
      return;
    }
    _requestedBinding = resolved.binding;
    _requestedResolveError = resolved.error;
    _requestedPlaceholder = resolved.placeholder;
    _requestedStore = store;
    _requestedExternal = external;
    _requestedAsBool = asBool;
    final generation = ++_bindingGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _bindingGeneration) return;
      final oldBinding = _binding;
      if (resetText &&
          !external &&
          resolved.error == null &&
          !resolved.placeholder &&
          oldBinding != null &&
          oldBinding.binding == resolved.binding &&
          oldBinding.asBool == asBool &&
          identical(oldBinding.store, store)) {
        await oldBinding.flush();
        if (!mounted || generation != _bindingGeneration) return;
        await oldBinding.reload(showLoading: false);
        return;
      }
      oldBinding?.removeListener(_bindingChanged);
      if (oldBinding != null) {
        _pendingBindingFlush = oldBinding.flush();
      }
      oldBinding?.dispose();
      _binding = null;
      final flushed = _pendingBindingFlush;
      if (flushed != null) await flushed;
      if (!mounted || generation != _bindingGeneration) return;
      _bindingError = resolved.error;
      _unselected = resolved.placeholder && !(scope?.placeholder ?? false);
      if (resetText && !external && resolved.binding == null) {
        _setText(_internal, _initialTextFor(config));
      }
      if (resolved.placeholder && !external) {
        _setText(_internal, asBool ? 'false' : '');
      }
      if (resolved.binding != null) {
        if (external) {
          _bindingError =
              'La liaison nécessite le contrôleur interne de Value.';
        } else if (store == null) {
          _bindingError = 'Service de repositories indisponible.';
        } else {
          _binding = JsonTextControllerBinding(
            store: store,
            binding: resolved.binding!,
            controller: _internal,
            asBool: asBool,
            onChanged: stateful
                ? null
                : (text) {
                    widget.onChanged?.call(text);
                    if (asBool) widget.onBoolChanged?.call(text == 'true');
                  },
          )..addListener(_bindingChanged);
        }
      }
      setState(() {});
    });
  }

  void _bindingChanged() {
    if (mounted) setState(() {});
  }

  void _listenPropertySelections(List<JsonArrayBinding> selections) {
    if (listEquals(_propertySelections, selections)) return;
    for (final selection in _propertySelections) {
      selection.removeListener(_propertySelectionChanged);
    }
    _propertySelections = selections;
    for (final selection in selections) {
      selection.addListener(_propertySelectionChanged);
    }
  }

  void _propertySelectionChanged() {
    _refreshPropertyBindings = true;
    if (mounted) setState(() {});
  }

  void _propertyStoreChanged() {
    final store = _requestedPropertyStore;
    if (!mounted || store == null || _activePropertyBindings.isEmpty) return;
    final generation = ++_propertyBindingGeneration;
    unawaited(
      _loadPropertyBindings(_activePropertyBindings, store, generation),
    );
  }

  void _observePropertyBindings(
    SuperValueConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final bindings = config.propertyBindings;
    final sameBindingContext =
        mapEquals(_requestedPropertyBindings, bindings) &&
        identical(_requestedPropertyStore, store) &&
        _requestedPropertyRepositoryId == scope?.repositoryId &&
        listEquals(_requestedPropertyIndices, scope?.indices ?? const []) &&
        _requestedPropertyPlaceholder == (scope?.placeholder ?? false);
    if (!_refreshPropertyBindings && sameBindingContext) {
      return;
    }
    _refreshPropertyBindings = false;
    _requestedPropertyBindings = Map.of(bindings);
    if (!identical(_requestedPropertyStore, store)) {
      _requestedPropertyStore?.removeListener(_propertyStoreChanged);
      store?.addListener(_propertyStoreChanged);
      _requestedPropertyStore = store;
    }
    _requestedPropertyRepositoryId = scope?.repositoryId;
    _requestedPropertyIndices = List.of(scope?.indices ?? const []);
    _requestedPropertyPlaceholder = scope?.placeholder ?? false;
    final generation = ++_propertyBindingGeneration;
    _propertyBindingErrors = const {};
    if (bindings.isEmpty || (scope?.placeholder ?? false)) {
      _boundPropertyValues = const {};
      _activePropertyBindings = const {};
      _listenPropertySelections(const []);
      return;
    }

    final selections = <JsonArrayBinding>[];
    final resolved = <SuperValueProperty, JsonTextBinding>{};
    final errors = <SuperValueProperty, String>{};
    for (final entry in bindings.entries) {
      try {
        final result = JsonListScope.resolveSelected(entry.value, scope, store);
        selections.addAll(result.arrays);
        if (result.binding != null) resolved[entry.key] = result.binding!;
      } on FormatException catch (error) {
        errors[entry.key] = error.message;
      }
    }
    _listenPropertySelections(selections.toSet().toList());
    _activePropertyBindings = Map.of(resolved);
    _propertyBindingErrors = errors;
    if (resolved.isEmpty) {
      _boundPropertyValues = const {};
      return;
    }
    if (!sameBindingContext) _boundPropertyValues = const {};
    if (store == null) {
      _boundPropertyValues = const {};
      _propertyBindingErrors = {
        ..._propertyBindingErrors,
        for (final property in resolved.keys)
          property: 'Service de repositories indisponible.',
      };
      return;
    }
    unawaited(_loadPropertyBindings(resolved, store, generation));
  }

  Future<void> _loadPropertyBindings(
    Map<SuperValueProperty, JsonTextBinding> bindings,
    JsonRepositoryStore store,
    int generation,
  ) async {
    final values = <SuperValueProperty, Object>{};
    final errors = Map<SuperValueProperty, String>.of(_propertyBindingErrors);
    for (final entry in bindings.entries) {
      try {
        final result = await store.readAttribute(entry.value);
        final value = _parseBoundProperty(entry.key, result.value);
        if (entry.key == SuperValueProperty.fontFamily &&
            widget.availableFontFamilies.isNotEmpty &&
            !widget.availableFontFamilies.contains(value)) {
          throw FormatException(
            'La police liée « $value » n’est pas disponible.',
          );
        }
        values[entry.key] = value;
        errors.remove(entry.key);
      } on FormatException catch (error) {
        errors[entry.key] = error.message;
      } on FileSystemException {
        errors[entry.key] = 'Impossible de lire le repository lié.';
      }
      if (!mounted || generation != _propertyBindingGeneration) return;
    }
    setState(() {
      _boundPropertyValues = values;
      _propertyBindingErrors = errors;
    });
  }

  SuperValueConfig _withBoundProperties(SuperValueConfig config) {
    var result = config;
    for (final entry in _boundPropertyValues.entries) {
      result = switch (entry.key) {
        SuperValueProperty.label => result.copyWith(
          label: entry.value as String,
        ),
        SuperValueProperty.placeholder => result.copyWith(
          placeholder: entry.value as String,
        ),
        SuperValueProperty.fontFamily => result.copyWith(
          fontFamily: entry.value as String,
        ),
        SuperValueProperty.color => result.copyWith(
          color: entry.value as Color,
        ),
        SuperValueProperty.fontSize => result.copyWith(
          fontSize: entry.value as double,
        ),
        SuperValueProperty.fontWeight => result.copyWith(
          fontWeight: entry.value as FontWeight,
        ),
        SuperValueProperty.italic => result.copyWith(
          italic: entry.value as bool,
        ),
        SuperValueProperty.textAlign => result.copyWith(
          textAlign: entry.value as TextAlign,
        ),
      };
    }
    return result;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_stateChanged);
    _focusNode.dispose();
    _stateReader?.removeListener(_stateChanged);
    _stateReader?.dispose();
    _bindingGeneration++;
    _listenSelections(const []);
    _propertyBindingGeneration++;
    _listenPropertySelections(const []);
    _requestedPropertyStore?.removeListener(_propertyStoreChanged);
    _requestedPropertyStore = null;
    _binding?.removeListener(_bindingChanged);
    _binding?.dispose();
    _resetGeneration++;
    _internal.dispose();
    _editorText?.dispose();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final repositories = JsonRepositoryScope.maybeOf(context);
    final listScope = JsonListScope.maybeOf(context);
    final configuration =
        registry?.valueController(widget.id, fallback: widget.config) ?? _local;
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    final canConfigure = StyleEditScope.controllerOf(context)?.value ?? true;

    return MouseRegion(
      opaque: false,
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: ValueListenableBuilder<SuperValueConfig>(
        valueListenable: configuration,
        builder: (context, savedConfig, _) {
          final effective = _resolveStates(
            savedConfig,
            listScope,
            repositories,
            ContentHoverScope.maybeOf(context)?.hovered == true,
          );
          final states = savedConfig.states;
          final active = states == null
              ? <String>[]
              : [
                  for (final key in states.order)
                    if (key == ValueConfigStates.hoverKey
                        ? _hovered && states.hover != null
                        : key == ValueConfigStates.selectedKey
                        ? listScope?.selected == true && states.selected != null
                        : AutomaticState.fromKey(key) != null
                        ? _automaticActive.any((value) => value.key == key)
                        : key == _stateReader?.stateName)
                      key,
                ];
          final transition =
              states != null && !listEquals(_activeStates, active);
          final removedStates = states == null && _hadStates;
          final contentChanged =
              states != null &&
              _effectiveConfig != null &&
              (_effectiveConfig!.initialText != effective.initialText ||
                  _effectiveConfig!.initialBool != effective.initialBool ||
                  _effectiveConfig!.kind != effective.kind ||
                  _effectiveConfig!.mode != effective.mode ||
                  _effectiveConfig!.obscureText != effective.obscureText);
          _effectiveConfig = effective;
          _hadStates = states != null;
          _activeStates = active;
          _observeBinding(
            effective,
            listScope,
            repositories,
            resetText: transition || contentChanged || removedStates,
            stateful: states != null || removedStates,
          );
          if (removedStates) {
            _previousConfig = effective;
          } else if (states == null) {
            _observeConfig(effective);
          }
          _observePropertyBindings(effective, listScope, repositories);
          final config = _editorConfig ?? _withBoundProperties(effective);
          final controller = _editorText ?? _text;
          final missingFont =
              config.fontFamily != null &&
              !widget.availableFontFamilies.contains(config.fontFamily);
          final base = DefaultTextStyle.of(context).style;
          final style = base.copyWith(
            fontFamily: missingFont ? null : config.fontFamily,
            fontSize: config.fontSize,
            fontWeight: config.fontWeight,
            fontStyle: config.italic == null
                ? null
                : config.italic!
                ? FontStyle.italic
                : FontStyle.normal,
            color: config.color,
            height: config.lineHeight,
            letterSpacing: config.letterSpacing,
          );
          return EditorSlot(
            key: _surface,
            id: widget.id,
            label: 'Valeur',
            menuType: 'Value',
            onEdit: () async {
              if (_editorText != null) return;
              final initial = configuration.value;
              final originalText = _text.text;
              _editorText = TextEditingController.fromValue(_text.value);
              SuperValueConfig? result;
              try {
                result = await showSuperValueEditor(
                  context: context,
                  config: initial,
                  availableFontFamilies: widget.availableFontFamilies,
                  allowBinding:
                      widget.controller == null && _controlledText == null,
                  activeState: _stateReader?.stateName,
                  stateError: _stateError,
                  isHovered: _hovered,
                  isSelected: listScope?.selected ?? false,
                  allowContentHover: ContentHoverScope.maybeOf(context) != null,
                  activeAutomatic: _automaticActive,
                  onPreviewChanged: (draft) {
                    if (!mounted || _editorText == null) return;
                    final text =
                        draft.binding == null &&
                            draft.obscureText &&
                            !initial.obscureText
                        ? ''
                        : draft.binding == null &&
                              (draft.kind != initial.kind ||
                                  draft.initialText != initial.initialText ||
                                  draft.initialBool != initial.initialBool ||
                                  draft.mode != initial.mode)
                        ? _initialTextFor(draft)
                        : originalText;
                    if (_editorText!.text != text) _setText(_editorText!, text);
                    setState(() => _editorConfig = draft);
                  },
                );
              } finally {
                final previewText = _editorText;
                if (mounted) {
                  setState(() {
                    _editorConfig = null;
                    _editorText = null;
                  });
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => previewText?.dispose(),
                  );
                }
              }
              if (result == null ||
                  !context.mounted ||
                  result == configuration.value) {
                return;
              }
              final history = EditorHistoryScope.controllerOf(context);
              history?.beginTransaction();
              try {
                configuration.value = result;
              } finally {
                history?.commitTransaction();
              }
              widget.onConfigChanged?.call(result);
            },
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final text = _editorText == null
                    ? _controlledText ?? value.text
                    : value.text;
                final Widget content;
                if (config.kind.isBoolean) {
                  final boolCurrent = text.trim().toLowerCase() == 'true';
                  final interactive =
                      config.mode == SuperValueMode.input &&
                      config.enabled &&
                      !config.readOnly &&
                      !_unselected &&
                      !(config.binding != null && _binding?.loading == true);
                  void toggleBool(bool next) {
                    if (!interactive || _editorText != null) return;
                    final nextText = next ? 'true' : 'false';
                    _setText(controller, nextText);
                    unawaited(_binding?.flush());
                    widget.onChanged?.call(nextText);
                    widget.onBoolChanged?.call(next);
                    if (_controlledText != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted &&
                            widget.controller == null &&
                            _controlledText != null &&
                            _internal.text != _controlledText) {
                          _setText(_internal, _controlledText!);
                        }
                      });
                    }
                  }

                  final control = config.kind == SuperValueKind.checkbox
                      ? Checkbox(
                          key: ValueKey('super-value-checkbox-${widget.id}'),
                          focusNode: _focusNode,
                          value: boolCurrent,
                          activeColor: config.color,
                          onChanged: interactive
                              ? (next) => toggleBool(next ?? false)
                              : null,
                        )
                      : Switch(
                          key: ValueKey('super-value-switch-${widget.id}'),
                          focusNode: _focusNode,
                          value: boolCurrent,
                          activeThumbColor: config.color,
                          onChanged: interactive ? toggleBool : null,
                        );
                  final align = switch (config.textAlign) {
                    TextAlign.center => MainAxisAlignment.center,
                    TextAlign.end || TextAlign.right => MainAxisAlignment.end,
                    _ => MainAxisAlignment.start,
                  };
                  content = Listener(
                    onPointerDown: (event) {
                      if (canConfigure &&
                          event.buttons == kSecondaryMouseButton) {
                        _surface.currentState?.openMenu(event.position);
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: align,
                      children: [
                        control,
                        if (config.label.isNotEmpty)
                          Flexible(
                            child: GestureDetector(
                              onTap: interactive
                                  ? () => toggleBool(!boolCurrent)
                                  : null,
                              child: Text(
                                config.label,
                                key: ValueKey('super-value-label-${widget.id}'),
                                style: style,
                                textAlign: config.textAlign,
                                maxLines: config.maxLines,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                } else {
                  final display = Text(
                    text.isEmpty
                        ? config.placeholder
                        : config.obscureText
                        ? List.filled(text.runes.length, '\u2022').join()
                        : text,
                    key: ValueKey('super-value-display-${widget.id}'),
                    style: style,
                    textAlign: config.textAlign,
                    maxLines: config.maxLines,
                    overflow: TextOverflow.ellipsis,
                  );
                  content = config.mode == SuperValueMode.input
                      ? Listener(
                          onPointerDown: (event) {
                            // TextField consumes secondary taps before EditorSlot.
                            if (canConfigure &&
                                event.buttons == kSecondaryMouseButton) {
                              _surface.currentState?.openMenu(event.position);
                            }
                          },
                          child: SuperTextField(
                            key: ValueKey('super-value-field-${widget.id}'),
                            inputKey: ValueKey(
                              'super-value-input-${widget.id}',
                            ),
                            config: config,
                            focusNode: _focusNode,
                            controller: controller,
                            style: style,
                            enabled:
                                config.enabled &&
                                !(config.binding != null &&
                                    _binding?.loading == true),
                            readOnly: _unselected ? true : null,
                            enableContextMenu: !canConfigure,
                            bindingError: _bindingError ?? _binding?.error,
                            onChanged: (text) {
                              if (_editorText != null) return;
                              widget.onChanged?.call(text);
                              if (_controlledText != null) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted &&
                                      widget.controller == null &&
                                      _controlledText != null &&
                                      _internal.text != _controlledText) {
                                    _setText(_internal, _controlledText!);
                                  }
                                });
                              }
                            },
                          ),
                        )
                      : config.label.isEmpty
                      ? display
                      : InputDecorator(
                          decoration: InputDecoration(
                            labelText: config.label.isEmpty
                                ? null
                                : config.label,
                            enabled: config.enabled,
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          isEmpty: false,
                          child: display,
                        );
                }

                final fit = SlotContentFitScope.maybeOf(context);
                final fitWidth = fit?.fitWidth ?? false;
                final fitHeight = fit?.fitHeight ?? false;
                return LayoutBuilder(
                  builder: (context, constraints) => SizedBox(
                    width: constraints.hasBoundedWidth ? null : 240,
                    height: !fitHeight && constraints.hasBoundedHeight
                        ? constraints.maxHeight
                        : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: fitWidth
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.stretch,
                      children: [
                        Flexible(child: content),
                        if ((config.mode == SuperValueMode.display ||
                                config.kind.isBoolean) &&
                            (_bindingError != null || _binding?.error != null))
                          Text(
                            _bindingError ?? _binding!.error!,
                            key: ValueKey(
                              'super-value-binding-error-${widget.id}',
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        for (final entry in _propertyBindingErrors.entries)
                          Text(
                            'Liaison ${entry.key.name} : ${entry.value}',
                            key: ValueKey(
                              'super-value-property-binding-error-'
                              '${entry.key.name}-${widget.id}',
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (_binding?.error != null)
                          TextButton(
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Recharger la liaison ?'),
                                  content: const Text(
                                    'La saisie non enregistrée sera abandonnée.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Annuler'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Recharger'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && mounted) {
                                await _binding?.discardAndReload();
                              }
                            },
                            child: const Text('Recharger la liaison'),
                          ),
                        if (_stateError != null)
                          Text(
                            _stateError!,
                            key: ValueKey(
                              'super-value-state-error-${widget.id}',
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (missingFont && editing)
                          Text(
                            'Police indisponible : ${config.fontFamily}. Choisissez une police disponible.',
                            key: ValueKey(
                              'super-value-font-warning-${widget.id}',
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
