/// Composant d'affichage ou de saisie de valeur ([SuperValue] : texte, case à cocher, interrupteur).
///
/// Se lie bidirectionnellement aux repositories JSON via [JsonTextBinding] et [JsonListScope],
/// et applique les surcharges d'états ([ValueConfigStates]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:material_ui/material_ui.dart';

import '../../theme/theme_color.dart';

import '../../models/automatic_state.dart';
import '../../models/component_behavior.dart';
import '../../models/json_text_binding.dart';
import '../../models/super_choice_config.dart';
import '../../models/super_text_field_config.dart';
import '../../models/super_value_config.dart';
import '../../services/behaviors/behavior_dispatcher.dart';
import '../../services/diagnostics/debug_entry.dart';
import '../../services/inspection/vibe_debug_capture.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/repositories/json_schema_field_resolver.dart';
import '../../services/repositories/json_text_controller_binding.dart';
import '../../services/states/content_hover_scope.dart';
import '../../super_app.dart';
import '../appearance/appearance_scope.dart';
import '../editing/components/super_value_editor.dart';
import '../editing/dialogs/super_value_json_extract_dialog.dart';
import '../editing/slots/editor_slot.dart';
import 'component_common.dart';
import 'component_property_bindings.dart';
import 'component_state_behavior.dart';
import 'super_choice.dart';
import 'super_component.dart';
import 'super_layout/slot_implementation.dart';
import 'super_text_field.dart';

Object _parseBoundProperty(SuperValueProperty property, Object? value) =>
    switch (property) {
      SuperValueProperty.label ||
      SuperValueProperty.placeholder ||
      SuperValueProperty.prefix ||
      SuperValueProperty.suffix ||
      SuperValueProperty.fontFamily => BoundPropertyParsers.parseString(
        property.name,
        value,
        nonEmptyTrimmed: property == SuperValueProperty.fontFamily,
      ),
      SuperValueProperty.color => BoundPropertyParsers.parseColor(value),
      SuperValueProperty.fontSize => BoundPropertyParsers.parsePositiveDouble(
        value,
        errorMessage: 'La taille de police liée doit être un nombre positif.',
      ),
      SuperValueProperty.fontWeight => BoundPropertyParsers.parseFontWeight(
        value,
      ),
      SuperValueProperty.italic => BoundPropertyParsers.parseItalic(value),
      SuperValueProperty.textAlign => BoundPropertyParsers.parseTextAlign(
        value,
      ),
    };

/// Display or edit a value (text, checkbox or switch); runtime input persists
/// only with a repository binding.
class SuperValue extends SuperStatefulComponent<SuperValueConfig> {
  const SuperValue({
    required this.id,
    this.config = const SuperValueConfig(),
    this.controller,
    this.value,
    this.boolValue,
    this.onChanged,
    this.onBoolChanged,
    this.onConfigChanged,
    super.behaviours,
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

  @override
  final String id;
  @override
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

class _SuperValueState extends State<SuperValue>
    with
        ComponentStateResolutionMixin<SuperValue>,
        ComponentPropertyBindingsMixin<SuperValue, SuperValueProperty>
    implements JsonExtractableState {
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
  bool? _requestedAsStringList;
  String? _requestedResolveError;
  bool _requestedPlaceholder = false;
  int _bindingGeneration = 0;
  String? _bindingError;

  /// A `[?]` resolved by a selection has no selected row: empty and disabled/read-only.
  bool _unselected = false;

  /// Selections the binding path depends on.
  List<JsonArrayBinding> _selections = const [];
  SuperValueConfig? _editorConfig;
  TextEditingController? _editorText;
  List<String>? _activeStates;
  SuperValueConfig? _effectiveConfig;
  bool _hadStates = false;
  final _focusNode = FocusNode();
  bool _hadFocus = false;
  bool _touched = false;
  JsonRepositoryStore? _schemaStore;
  final Set<String> _schemaLoadRequested = {};
  Map<String, Object?>? _lastObservedSchema;
  Duration _requestedDebounceDuration =
      JsonTextControllerBinding.defaultDebounceDuration;
  bool _requestedSaveOnBlurOnly = false;
  Future<void>? _pendingBindingFlush;
  TextEditingController? _observedController;
  String _lastControllerText = '';
  String _previousControllerText = '';

  void _syncObservedController() {
    final current = _text;
    if (identical(_observedController, current)) return;
    _observedController?.removeListener(_handleControllerTextChanged);
    _observedController = current;
    _lastControllerText = current.text;
    _previousControllerText = current.text;
    current.addListener(_handleControllerTextChanged);
  }

  void _handleControllerTextChanged() {
    final currentText = _observedController?.text ?? '';
    if (currentText == _lastControllerText) return;
    _previousControllerText = _lastControllerText;
    _lastControllerText = currentText;
  }

  Object _decodeRuntimeValue(String rawText, SuperValueConfig config) {
    if (config.kind.isBoolean) {
      return rawText.trim().toLowerCase() == 'true';
    }
    if (config.kind.isChoice && config.choice.variant.isMultiple) {
      return SuperChoiceConfig.parseSelectedValues(rawText);
    }
    if (config.kind.isText) {
      return config.field.toStorageText(rawText);
    }
    return rawText;
  }

  Object _readCurrentRuntimeValue([SuperValueConfig? overrideConfig]) {
    final current = overrideConfig ?? _currentEffectiveConfig;
    final rawText = _editorText != null
        ? _editorText!.text
        : (_controlledText ?? _text.text);
    return _decodeRuntimeValue(rawText, current);
  }

  bool _readCurrentIsValid() {
    if (_bindingError != null || _binding?.error != null) return false;
    final current = _currentEffectiveConfig;
    if (current.kind.isText && current.mode == SuperValueMode.input) {
      if (current.field.errorText.trim().isNotEmpty) return false;
      final displayText = _editorText != null
          ? _editorText!.text
          : (_controlledText ?? _text.text);
      final storageText = current.field.toStorageText(displayText);
      return current.field.validateValue(
            storageText,
            displayValue: displayText,
            obscureText: current.obscureText,
          ) ==
          null;
    }
    if (current.kind.isChoice &&
        current.mode == SuperValueMode.input &&
        current.choice.errorText.trim().isNotEmpty) {
      return false;
    }
    return true;
  }

  void _dispatchValueEvent(
    BehaviorEvent event, {
    required Map<String, Object?> data,
    BuildContext? targetContext,
  }) {
    if (_editorText != null) return;
    final ctx = targetContext ?? _surface.currentContext ?? context;
    if (!ctx.mounted) return;
    unawaited(
      BehaviorDispatcher.dispatch(
        ctx,
        componentId: widget.id,
        componentType: 'value',
        event: event,
        data: data,
        behaviors: widget.behaviours,
      ),
    );
  }

  void _syncSchemaStoreListener(
    JsonRepositoryStore? store,
    SuperValueConfig config,
    JsonListScope? scope,
  ) {
    if (!identical(_schemaStore, store)) {
      _schemaStore?.removeListener(_handleSchemaStoreChanged);
      _schemaStore = store;
      _schemaLoadRequested.clear();
      _lastObservedSchema = null;
      _schemaStore?.addListener(_handleSchemaStoreChanged);
    }
    final repoId = config.binding?.repositoryId ?? scope?.repositoryId;
    if (store != null &&
        repoId != null &&
        repoId.isNotEmpty &&
        config.kind.isText &&
        config.field.useRepositorySchema) {
      _lastObservedSchema = store.jsonSchemaOf(repoId);
      if (_lastObservedSchema == null &&
          !store.isMemoryOnlyRepository(repoId) &&
          _schemaLoadRequested.add(repoId)) {
        unawaited(
          store.ensureSchemasLoaded().then((_) {
            if (mounted && store.jsonSchemaOf(repoId) != null) {
              setState(() {});
            }
          }),
        );
      }
    } else {
      _lastObservedSchema = null;
    }
  }

  void _handleSchemaStoreChanged() {
    if (!mounted) return;
    final store = _schemaStore;
    if (store == null) return;
    final scope = JsonListScope.maybeOf(context);
    final saved =
        (SuperApp.maybeOf(context)?.registry?.valueController(
                  widget.id,
                  fallback: widget.config,
                ) ??
                _local)
            .value;
    final repoId = saved.binding?.repositoryId ?? scope?.repositoryId;
    final nextSchema = repoId == null ? null : store.jsonSchemaOf(repoId);
    if (!identical(nextSchema, _lastObservedSchema)) {
      _lastObservedSchema = nextSchema;
      setState(() {});
    }
  }

  SuperValueConfig _applySchemaConstraints(
    SuperValueConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    if (!config.kind.isText || !config.field.useRepositorySchema) {
      return config;
    }
    final binding = config.binding;
    if (binding == null || store == null) return config;
    final repoId = binding.repositoryId ?? scope?.repositoryId;
    if (repoId == null || repoId.isEmpty) return config;
    final schema = store.jsonSchemaOf(repoId);
    if (schema == null) return config;
    final profile = JsonSchemaFieldResolver.resolve(schema, binding.path);
    if (profile == null) return config;
    return config.copyWith(
      field: config.field.applySchemaProfile(
        profile,
        allowMaskAndFormat: !config.obscureText && config.maxLines == 1,
      ),
    );
  }

  static String _initialTextFor(
    SuperValueConfig config, {
    bool focused = false,
  }) => config.kind.isBoolean
      ? (config.initialBool ? 'true' : 'false')
      : (config.obscureText
            ? ''
            : config.kind.isText && config.field.hasMaskOrFormat
            ? config.field.toDisplayText(config.initialText, focused: focused)
            : config.initialText);

  static String _displayControlledText(
    SuperValueConfig config,
    String text, {
    bool focused = false,
  }) => config.kind.isText && !config.obscureText && config.field.hasMaskOrFormat
      ? config.field.toDisplayText(text, focused: focused)
      : text;

  static List<String> _nonInvalidStateKeys(List<String>? keys) => keys == null
      ? const []
      : [
          for (final key in keys)
            if (key != AutomaticState.invalid.key) key,
        ];

  @override
  List<String> get availableComponentFontFamilies => mounted
      ? resolveAvailableComponentFontFamilies(
          context,
          widget.availableFontFamilies,
          listen: false,
        )
      : widget.availableFontFamilies;

  @override
  Object parseBoundProperty(SuperValueProperty property, Object? value) =>
      _parseBoundProperty(property, value);

  SuperValueConfig _resolveStates(
    SuperValueConfig saved,
    JsonListScope? scope,
    JsonRepositoryStore? store,
    bool contentHovered, {
    bool behaviorDisabled = false,
    bool behaviorReadOnly = false,
    String? behaviorNamedState,
    bool unselected = false,
  }) {
    syncSurfaceStateReader(saved.states?.binding, scope, store);
    final effectiveStateName = behaviorNamedState ?? stateReader?.stateName;
    try {
      final rawSource =
          saved.states?.resolve(saved, name: effectiveStateName) ??
          saved.copyWith(clearStates: true);
      final source = _applySchemaConstraints(rawSource, scope, store);
      final input = source.mode == SuperValueMode.input;
      final effectiveDisabled =
          behaviorDisabled || (input && (unselected || !source.enabled));
      final effectiveReadOnly =
          behaviorReadOnly || (input && source.readOnly);
      final currentDisplay = _editorText != null
          ? _editorText!.text
          : (_controlledText ?? _text.text);
      final currentStorage = input && source.kind.isText
          ? source.field.toStorageText(currentDisplay)
          : currentDisplay;
      final isInvalid =
          _touched &&
          input &&
          source.kind.isText &&
          source.field.validateValue(
                currentStorage,
                displayValue: currentDisplay,
                obscureText: source.obscureText,
              ) !=
              null;
      automaticActiveStates = {
        if (contentHovered) AutomaticState.contentHover,
        if (input && _focusNode.hasFocus) AutomaticState.focused,
        if (effectiveDisabled) AutomaticState.disabled,
        if (effectiveReadOnly) AutomaticState.readOnly,
        if (isInvalid) AutomaticState.invalid,
      };
      var config =
          saved.states?.resolve(
            saved,
            name: effectiveStateName,
            isHovered: isComponentHovered,
            isSelected: scope?.selected ?? false,
            activeStates: automaticActiveStates,
          ) ??
          saved;
      config = _applySchemaConstraints(config, scope, store);
      if ((behaviorDisabled ||
              (unselected && config.mode == SuperValueMode.input)) &&
          config.enabled) {
        config = config.copyWith(enabled: false);
      }
      if (behaviorReadOnly && !config.readOnly) {
        config = config.copyWith(readOnly: true);
      }
      config.validate();
      return config;
    } on FormatException catch (error) {
      stateError = error.message;
    } on ArgumentError {
      stateError = 'Combinaison d’états de la valeur invalide.';
    }
    var fallback = _applySchemaConstraints(
      saved.copyWith(clearStates: true),
      scope,
      store,
    );
    if ((behaviorDisabled ||
            (unselected && fallback.mode == SuperValueMode.input)) &&
        fallback.enabled) {
      fallback = fallback.copyWith(enabled: false);
    }
    if (behaviorReadOnly && !fallback.readOnly) {
      fallback = fallback.copyWith(readOnly: true);
    }
    return fallback;
  }

  TextEditingController get _text => widget.controller ?? _internal;

  String? get _controlledText =>
      widget.boolValue != null ? '${widget.boolValue}' : widget.value;

  @override
  void initState() {
    super.initState();
    widget.config.copyWith(clearStates: true).validate();
    final initial = _controlledText != null
        ? _displayControlledText(widget.config, _controlledText!)
        : _initialTextFor(widget.config);
    _internal = TextEditingController(text: initial);
    _syncObservedController();
    _local = ValueNotifier(widget.config);
    _focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    final hasFocus = _focusNode.hasFocus;
    final focusChanged = hasFocus != _hadFocus;
    final current = _currentEffectiveConfig;
    if (_hadFocus && !hasFocus) {
      _touched = true;
    }
    if (current.mode == SuperValueMode.input &&
        current.kind.isText &&
        !current.obscureText &&
        widget.controller == null &&
        _editorText == null &&
        current.field.mask.isEmpty &&
        (current.field.hasNumericFormatting ||
            (current.field.dateFormat.isNotEmpty && !hasFocus))) {
      final storage = current.field.toStorageText(_internal.text);
      final formatted = current.field.toDisplayText(storage, focused: hasFocus);
      if (formatted != _internal.text &&
          (!hasFocus || current.field.hasNumericFormatting)) {
        final nextValue = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
        if (_binding != null) {
          _binding!.syncFormattedText(nextValue);
        } else {
          _internal.value = nextValue;
        }
      }
    }
    if (_hadFocus && !hasFocus) {
      final binding = _binding;
      if (binding != null && binding.hasPendingWrite) {
        unawaited(binding.flush());
      }
    }
    _hadFocus = hasFocus;
    if (focusChanged && mounted && _editorText == null) {
      _dispatchValueEvent(
        hasFocus ? BehaviorEvent.onFocus : BehaviorEvent.onBlur,
        data: {
          'value': _readCurrentRuntimeValue(current),
          'hasFocus': hasFocus,
        },
      );
    }
    onComponentStateChanged();
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
    _syncObservedController();
    if (oldWidget.config != widget.config) _local.value = widget.config;
    if (oldWidget.id != widget.id) {
      _previousConfig = null;
      _resetGeneration++;
      _requestedExternal = null;
      _requestedAsBool = null;
      _requestedAsStringList = null;
      _activeStates = null;
      _effectiveConfig = null;
      _touched = false;
      _lastControllerText = _text.text;
      _previousControllerText = _text.text;
    }
    final controlled = _controlledText;
    if (widget.controller == null) {
      if (controlled != null) {
        final display = _displayControlledText(
          _currentEffectiveConfig,
          controlled,
          focused: _focusNode.hasFocus,
        );
        if (display != _internal.text) {
          _setText(_internal, display);
        }
      } else if (oldWidget.controller != null) {
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
        _setText(
          _internal,
          _initialTextFor(config, focused: _focusNode.hasFocus),
        );
      }
      return;
    }
    if (previous.mode == config.mode &&
        previous.kind == config.kind &&
        previous.initialText == config.initialText &&
        previous.initialBool == config.initialBool &&
        previous.binding == null &&
        (!config.obscureText || previous.obscureText)) {
      if (widget.controller == null &&
          _controlledText == null &&
          previous.field != config.field) {
        final storage = previous.field.toStorageText(_internal.text);
        final nextDisplay = _displayControlledText(
          config,
          storage,
          focused: _focusNode.hasFocus,
        );
        if (nextDisplay != _internal.text) {
          _setText(_internal, nextDisplay);
        }
      }
      return;
    }
    _touched = false;
    final generation = ++_resetGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _resetGeneration) return;
      final display = _initialTextFor(config, focused: _focusNode.hasFocus);
      final raw = config.kind.isText && !config.obscureText
          ? config.field.toStorageText(display)
          : display;
      if (_controlledText == null) _setText(_text, display);
      widget.onChanged?.call(raw);
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

  ({
    String Function(String displayText)? toStorageText,
    String Function(String storageText)? toDisplayText,
    String? Function(String storageText, String displayText)? validateText,
  })
  _bindingTransformsFor(SuperValueConfig config) {
    if (!config.kind.isText || config.obscureText) {
      return (toStorageText: null, toDisplayText: null, validateText: null);
    }
    final field = config.field;
    final hasTransform =
        field.hasMaskOrFormat || field.valueType != TextFieldValueType.string;
    final toStorage = hasTransform ? field.toStorageText : null;
    final toDisplay = field.hasMaskOrFormat
        ? (String s) => field.toDisplayText(
            s,
            focused: config.mode == SuperValueMode.input && _focusNode.hasFocus,
          )
        : null;
    final validate = config.mode == SuperValueMode.input && field.hasConstraints
        ? (String storage, String display) => field.validateValue(
            storage,
            displayValue: display,
            obscureText: config.obscureText,
          )
        : null;
    return (
      toStorageText: toStorage,
      toDisplayText: toDisplay,
      validateText: validate,
    );
  }

  void _observeBinding(
    SuperValueConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store, {
    bool resetText = false,
    bool stateful = false,
    Duration debounceDuration =
        JsonTextControllerBinding.defaultDebounceDuration,
    bool saveOnBlurOnly = false,
  }) {
    _requestedDebounceDuration = debounceDuration;
    _requestedSaveOnBlurOnly = saveOnBlurOnly;
    _binding?.configureTiming(
      debounceDuration: debounceDuration,
      saveOnBlurOnly: saveOnBlurOnly,
    );
    final transforms = _bindingTransformsFor(config);
    _binding?.configureTransform(
      toStorageText: transforms.toStorageText,
      toDisplayText: transforms.toDisplayText,
      validateText: transforms.validateText,
    );
    final external = widget.controller != null || _controlledText != null;
    final asBool = config.kind.isBoolean;
    final asStringList =
        config.kind.isChoice && config.choice.variant.isMultiple;
    final resolved = _resolve(config, scope, store);
    _listenSelections(resolved.selections);
    if (!resetText &&
        _requestedBinding == resolved.binding &&
        _requestedResolveError == resolved.error &&
        _requestedPlaceholder == resolved.placeholder &&
        _requestedStore == store &&
        _requestedExternal == external &&
        _requestedAsBool == asBool &&
        _requestedAsStringList == asStringList) {
      return;
    }
    if (_requestedBinding != resolved.binding || resetText) {
      _touched = false;
    }
    _requestedBinding = resolved.binding;
    _requestedResolveError = resolved.error;
    _requestedPlaceholder = resolved.placeholder;
    _requestedStore = store;
    _requestedExternal = external;
    _requestedAsBool = asBool;
    _requestedAsStringList = asStringList;
    final generation = ++_bindingGeneration;
    final existingBinding = _binding;
    final sameBindingReset =
        resetText &&
        !external &&
        resolved.error == null &&
        !resolved.placeholder &&
        existingBinding != null &&
        existingBinding.binding == resolved.binding &&
        existingBinding.asBool == asBool &&
        existingBinding.asStringList == asStringList &&
        identical(existingBinding.store, store);

    if (!sameBindingReset) {
      if (existingBinding != null) {
        existingBinding.removeListener(_bindingChanged);
        if (existingBinding.hasPendingWrite) {
          _pendingBindingFlush = existingBinding.flush();
        }
        existingBinding.dispose();
        _binding = null;
      }
      _bindingError = external && resolved.binding != null
          ? 'La liaison nécessite le contrôleur interne de Value.'
          : store == null && resolved.binding != null
          ? 'Service de repositories indisponible.'
          : resolved.error;
      _unselected = resolved.placeholder && !(scope?.placeholder ?? false);
      if (!external) {
        if (resolved.placeholder) {
          final fallback = asBool ? 'false' : '';
          if (_internal.text != fallback) _setText(_internal, fallback);
        } else if (resetText && resolved.binding == null) {
          final fallback = _initialTextFor(
            config,
            focused: _focusNode.hasFocus,
          );
          if (_internal.text != fallback) _setText(_internal, fallback);
        } else if (resolved.error == null &&
            resolved.binding != null &&
            store != null) {
          final cached = store.peekAttribute(
            resolved.binding!,
            allowStringList: asStringList,
          );
          if (cached != null &&
              (!asBool || cached.value == null || cached.value is bool) &&
              (!asStringList ||
                  cached.value == null ||
                  cached.value is String ||
                  cached.value is List)) {
            final resolvedText = asBool
                ? (cached.value == true ? 'true' : 'false')
                : (transforms.toDisplayText?.call(cached.text) ?? cached.text);
            if (_internal.text != resolvedText) {
              _setText(_internal, resolvedText);
            }
          } else if (existingBinding != null &&
              existingBinding.binding != resolved.binding) {
            final fallback = asBool ? 'false' : '';
            if (_internal.text != fallback) _setText(_internal, fallback);
          }
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _bindingGeneration) return;
      if (sameBindingReset) {
        final active = _binding;
        if (active == null) return;
        await active.flush();
        if (!mounted || generation != _bindingGeneration) return;
        await active.reload(showLoading: false);
        return;
      }
      final flushed = _pendingBindingFlush;
      if (flushed != null) {
        await flushed;
        if (identical(_pendingBindingFlush, flushed)) {
          _pendingBindingFlush = null;
        }
      }
      if (!mounted || generation != _bindingGeneration) return;
      final previousError = _bindingError;
      final previousUnselected = _unselected;
      final previousText = _internal.text;
      _bindingError = resolved.error;
      _unselected = resolved.placeholder && !(scope?.placeholder ?? false);
      if (resetText && !external && resolved.binding == null) {
        _setText(
          _internal,
          _initialTextFor(config, focused: _focusNode.hasFocus),
        );
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
            componentId: widget.id,
            asBool: asBool,
            asStringList: asStringList,
            debounceDuration: _requestedDebounceDuration,
            saveOnBlurOnly: _requestedSaveOnBlurOnly,
            toStorageText: transforms.toStorageText,
            toDisplayText: transforms.toDisplayText,
            validateText: transforms.validateText,
            onChanged: stateful
                ? null
                : (text) {
                    widget.onChanged?.call(text);
                    if (asBool) widget.onBoolChanged?.call(text == 'true');
                  },
          )..addListener(_bindingChanged);
        }
      }
      if (mounted &&
          (_bindingError != previousError ||
              _unselected != previousUnselected ||
              _internal.text != previousText ||
              (_binding?.loading ?? false) ||
              _binding?.error != null)) {
        setState(() {});
      }
    });
  }

  void _bindingChanged() {
    if (mounted) setState(() {});
  }

  SuperValueConfig _withBoundProperties(SuperValueConfig config) {
    var result = config;
    for (final entry in boundPropertyValues.entries) {
      result = switch (entry.key) {
        SuperValueProperty.label => result.copyWith(
          label: entry.value as String,
        ),
        SuperValueProperty.placeholder => result.copyWith(
          placeholder: entry.value as String,
        ),
        SuperValueProperty.prefix => result.copyWith(
          prefix: entry.value as String,
        ),
        SuperValueProperty.suffix => result.copyWith(
          suffix: entry.value as String,
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
    VibeDebugCapture.clearComponentDiagnostics(widget.id);
    _observedController?.removeListener(_handleControllerTextChanged);
    _observedController = null;
    _schemaStore?.removeListener(_handleSchemaStoreChanged);
    _schemaStore = null;
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    disposeComponentStateReader();
    _bindingGeneration++;
    _listenSelections(const []);
    disposePropertyBindings();
    _binding?.removeListener(_bindingChanged);
    _binding?.dispose();
    _resetGeneration++;
    _internal.dispose();
    _editorText?.dispose();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComponentStateBehavior(
    componentId: widget.id,
    behaviors: widget.behaviours,
    styleHandling: BehaviorStyleHandling.textOnly,
    child: Builder(builder: _buildValueContent),
  );

  static String? _templatePreviewText(
    String? slotLabel,
    SuperValueConfig config,
    JsonListScope? listScope,
    bool editing, {
    required bool unselected,
  }) {
    if (!editing || config.binding == null) return null;
    if (!(listScope?.placeholder ?? false) && !unselected) return null;
    final trimmedSlot = slotLabel?.trim();
    if (trimmedSlot != null &&
        trimmedSlot.isNotEmpty &&
        trimmedSlot != 'Valeur' &&
        trimmedSlot != 'Value') {
      return trimmedSlot;
    }
    if (config.label.trim().isNotEmpty) return config.label.trim();
    final rawPath = config.binding!.path.trim();
    if (rawPath.isEmpty) return null;
    final lastSegment = rawPath.split('.').last.replaceAll('[?]', '').trim();
    return lastSegment.isEmpty ? rawPath : '{$lastSegment}';
  }

  Widget _buildValueContent(BuildContext context) {
    final slotLabel = editorComponentLabelOf(context)?.label;
    final registry = SuperApp.maybeOf(context)?.registry;
    final repositories = JsonRepositoryScope.maybeOf(context);
    final listScope = JsonListScope.maybeOf(context);
    final configuration =
        registry?.valueController(widget.id, fallback: widget.config) ?? _local;
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    final canConfigure = StyleEditScope.controllerOf(context)?.value ?? true;
    final behaviorDisabled =
        !editing && ComponentBehaviorStateScope.isDisabled(context);
    final behaviorReadOnly =
        !editing && ComponentBehaviorStateScope.isReadOnly(context);
    final behaviorStyle = editing
        ? null
        : ComponentBehaviorStateScope.styleOverrideFor(context, widget.id);

    return wrapWithComponentHoverRegion(
      ValueListenableBuilder<SuperValueConfig>(
        valueListenable: configuration,
        builder: (context, savedConfig, _) {
          _syncSchemaStoreListener(repositories, savedConfig, listScope);
          final initialResolution = _resolve(
            savedConfig,
            listScope,
            repositories,
          );
          final isUnselected =
              initialResolution.placeholder &&
              !(listScope?.placeholder ?? false);
          final effective = _resolveStates(
            savedConfig,
            listScope,
            repositories,
            ContentHoverScope.maybeOf(context)?.hovered == true,
            behaviorDisabled: behaviorDisabled,
            behaviorReadOnly: behaviorReadOnly,
            behaviorNamedState: behaviorStyle?.namedState,
            unselected: isUnselected,
          );
          final effectiveStateName =
              behaviorStyle?.namedState ?? stateReader?.stateName;
          final states = savedConfig.states;
          final active = states == null
              ? <String>[]
              : [
                  for (final key in states.order)
                    if (key == ValueConfigStates.hoverKey
                        ? isComponentHovered && states.hover != null
                        : key == ValueConfigStates.selectedKey
                        ? listScope?.selected == true && states.selected != null
                        : AutomaticState.fromKey(key) != null
                        ? automaticActiveStates.any((value) => value.key == key)
                        : key == effectiveStateName)
                      key,
                ];
          final transition =
              states != null &&
              !listEquals(
                _nonInvalidStateKeys(_activeStates),
                _nonInvalidStateKeys(active),
              );
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
          final appearance = AppearanceScope.of(context);
          final debounceMs =
              effective.bindingDebounceMs ?? appearance.bindingDebounceMs;
          final saveOnBlurOnly =
              effective.bindingSaveOnBlurOnly ??
              appearance.bindingSaveOnBlurOnly;
          _observeBinding(
            effective,
            listScope,
            repositories,
            resetText: transition || contentChanged || removedStates,
            stateful: states != null || removedStates,
            debounceDuration: Duration(milliseconds: debounceMs),
            saveOnBlurOnly: saveOnBlurOnly,
          );
          if (removedStates) {
            _previousConfig = effective;
          } else if (states == null) {
            _observeConfig(effective);
          }
          observePropertyBindings(
            effective.propertyBindings,
            listScope,
            repositories,
          );
          var boundConfig = _withBoundProperties(effective);
          if (behaviorStyle != null && behaviorStyle.hasForegroundProperties) {
            boundConfig = boundConfig.copyWith(
              color: behaviorStyle.foregroundColor ?? boundConfig.color,
              fontSize: behaviorStyle.fontSize ?? boundConfig.fontSize,
              fontWeight: behaviorStyle.fontWeight ?? boundConfig.fontWeight,
            );
          }
          final config = _editorConfig ?? boundConfig;
          final controller = _editorText ?? _text;
          final availableFonts = resolveAvailableComponentFontFamilies(
            context,
            widget.availableFontFamilies,
          );
          final missingFont = isComponentFontMissing(
            config.fontFamily,
            availableFonts,
          );
          if (missingFont) {
            scheduleMissingComponentFontLoad(
              context,
              config.fontFamily,
              availableFonts,
            );
          }
          final style = buildComponentTextStyle(
            context,
            fontFamily: config.fontFamily,
            missingFont: missingFont,
            fontSize: config.fontSize,
            fontWeight: config.fontWeight,
            italic: config.italic,
            color: config.color.resolveTheme(context),
            lineHeight: config.lineHeight,
            letterSpacing: config.letterSpacing,
          );
          return EditorSlot(
            key: _surface,
            id: widget.id,
            exportConfig: () => configuration.value,
            eventComponentType: 'value',
            behaviors: widget.behaviours,
            readValue: _readCurrentRuntimeValue,
            readIsValid: _readCurrentIsValid,
            eventData: () => {'value': _readCurrentRuntimeValue()},
            label: 'Valeur',
            menuType: 'Value',
            menuTooltip: () => formatSuperValueTooltip(
              title: _surface.currentState?.titleLabel ?? 'Valeur',
              config: config,
            ),
            onEdit: () async {
              if (_editorText != null) return;
              final originalText = _text.text;
              _editorText = TextEditingController.fromValue(_text.value);
              await runComponentEditorTransaction<SuperValueConfig>(
                context: context,
                configuration: configuration,
                onConfigChanged: widget.onConfigChanged,
                onFinally: () {
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
                },
                showEditor: (initial) => showSuperValueEditor(
                  context: context,
                  config: initial,
                  availableFontFamilies: widget.availableFontFamilies,
                  allowBinding:
                      widget.controller == null && _controlledText == null,
                  activeState: stateReader?.stateName,
                  stateError: stateError,
                  isHovered: isComponentHovered,
                  isSelected: listScope?.selected ?? false,
                  allowContentHover: ContentHoverScope.maybeOf(context) != null,
                  activeAutomatic: automaticActiveStates,
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
                ),
              );
            },
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final text = _editorText == null
                    ? _controlledText ?? value.text
                    : value.text;
                final bindingReadOnly =
                    JsonTextBinding.isCalculatedPath(
                      config.binding?.path ?? '',
                    ) ||
                    (_binding?.isReadOnly ?? false);
                final Widget content;
                if (config.kind.isBoolean) {
                  final boolCurrent = text.trim().toLowerCase() == 'true';
                  final interactive =
                      config.mode == SuperValueMode.input &&
                      config.enabled &&
                      !config.readOnly &&
                      !bindingReadOnly &&
                      !_unselected &&
                      !(config.binding != null && _binding?.loading == true);
                  void toggleBool(bool next) {
                    if (!interactive || _editorText != null) return;
                    final previousValue = boolCurrent;
                    final nextText = next ? 'true' : 'false';
                    _setText(controller, nextText);
                    unawaited(_binding?.flush());
                    widget.onChanged?.call(nextText);
                    widget.onBoolChanged?.call(next);
                    if (next != previousValue) {
                      _dispatchValueEvent(
                        BehaviorEvent.onChanged,
                        data: {'value': next, 'previousValue': previousValue},
                        targetContext: context,
                      );
                    }
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
                          activeColor: config.color.resolveTheme(context),
                          onChanged: interactive
                              ? (next) => toggleBool(next ?? false)
                              : null,
                        )
                      : Switch(
                          key: ValueKey('super-value-switch-${widget.id}'),
                          focusNode: _focusNode,
                          value: boolCurrent,
                          activeThumbColor: config.color.resolveTheme(context),
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
                } else if (config.kind.isChoice) {
                  final choiceEnabled =
                      config.enabled &&
                      !_unselected &&
                      !(config.binding != null && _binding?.loading == true);
                  content = Listener(
                    onPointerDown: (event) {
                      if (canConfigure &&
                          event.buttons == kSecondaryMouseButton) {
                        _surface.currentState?.openMenu(event.position);
                      }
                    },
                    child: wrapWithOutsideSuperValueAffixes(
                      prefix: config.prefix,
                      suffix: config.suffix,
                      valueStyle: style,
                      enabled: choiceEnabled,
                      prefixKey: ValueKey('super-value-prefix-${widget.id}'),
                      suffixKey: ValueKey('super-value-suffix-${widget.id}'),
                      child: SuperChoice(
                        key: ValueKey('super-value-choice-${widget.id}'),
                        inputKey: ValueKey('super-value-input-${widget.id}'),
                        config: config,
                        focusNode: _focusNode,
                        controller: controller,
                        style: style,
                        enabled: choiceEnabled,
                        readOnly: _unselected || bindingReadOnly ? true : null,
                        bindingError: _bindingError ?? _binding?.error,
                        onChanged: (nextText) {
                          if (_editorText != null) return;
                          final previousRaw = _lastControllerText == nextText
                              ? _previousControllerText
                              : _lastControllerText;
                          final nextValue = _decodeRuntimeValue(
                            nextText,
                            config,
                          );
                          final previousValue = _decodeRuntimeValue(
                            previousRaw,
                            config,
                          );
                          unawaited(_binding?.flush());
                          widget.onChanged?.call(nextText);
                          final eventData = <String, Object?>{
                            'value': nextValue,
                            'previousValue': previousValue,
                          };
                          _dispatchValueEvent(
                            BehaviorEvent.onChanged,
                            data: eventData,
                            targetContext: context,
                          );
                          _dispatchValueEvent(
                            BehaviorEvent.onSelected,
                            data: eventData,
                            targetContext: context,
                          );
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
                        },
                      ),
                    ),
                  );
                } else {
                  final previewText = text.isEmpty && config.placeholder.isEmpty
                      ? _templatePreviewText(
                          slotLabel,
                          config,
                          listScope,
                          editing,
                          unselected: _unselected,
                        )
                      : null;
                  final effectiveColor =
                      style.color ?? Theme.of(context).colorScheme.onSurface;
                  final displayText =
                      config.mode == SuperValueMode.display &&
                          !config.obscureText &&
                          text.isNotEmpty
                      ? config.field.toDisplayText(text)
                      : text;
                  final display = buildSuperValueDisplayWithAffixes(
                    config: config,
                    valueStyle: style,
                    prefixKey: ValueKey('super-value-prefix-${widget.id}'),
                    suffixKey: ValueKey('super-value-suffix-${widget.id}'),
                    display: Text(
                      displayText.isEmpty
                          ? (config.placeholder.isNotEmpty
                                ? config.placeholder
                                : (previewText ?? ''))
                          : config.obscureText
                          ? List.filled(
                              displayText.runes.length,
                              '\u2022',
                            ).join()
                          : displayText,
                      key: ValueKey('super-value-display-${widget.id}'),
                      style: previewText != null
                          ? style.copyWith(
                              color: effectiveColor.withValues(
                                alpha: effectiveColor.a * 0.55,
                              ),
                              fontStyle: FontStyle.italic,
                            )
                          : style,
                      textAlign: config.textAlign,
                      maxLines: config.maxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                  final storageText = config.field.toStorageText(text);
                  final validationError =
                      _touched &&
                          _editorText == null &&
                          config.mode == SuperValueMode.input
                      ? config.field.validateValue(
                          storageText,
                          displayValue: text,
                          obscureText: config.obscureText,
                        )
                      : null;
                  VibeDebugCapture.syncComponentDiagnostic(
                    componentId: widget.id,
                    sourceKey: 'super-value.validationError',
                    active: validationError != null,
                    category: DebugErrorCategory.userInput,
                    severity: DebugSeverity.warning,
                    message: validationError,
                    source: 'SuperTextField.validation',
                    visibleInUi: true,
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
                            prefixKey: ValueKey(
                              'super-value-prefix-${widget.id}',
                            ),
                            suffixKey: ValueKey(
                              'super-value-suffix-${widget.id}',
                            ),
                            errorIndicatorKey: ValueKey(
                              'super-value-error-indicator-${widget.id}',
                            ),
                            config: config,
                            focusNode: _focusNode,
                            controller: controller,
                            style: style,
                            enabled:
                                config.enabled &&
                                !_unselected &&
                                !(config.binding != null &&
                                    _binding?.loading == true),
                            readOnly: _unselected || bindingReadOnly
                                ? true
                                : null,
                            enableContextMenu: !canConfigure,
                            bindingError: _bindingError ?? _binding?.error,
                            validationError: validationError,
                            onChanged: (nextText) {
                              if (_editorText != null) return;
                              final previousRaw =
                                  _lastControllerText == nextText
                                  ? _previousControllerText
                                  : _lastControllerText;
                              final nextStorage = config.field.toStorageText(
                                nextText,
                              );
                              final previousStorage = config.field
                                  .toStorageText(previousRaw);
                              if (!_touched) {
                                setState(() => _touched = true);
                              } else if (savedConfig.states?.automatic
                                      .containsKey(AutomaticState.invalid) ==
                                  true) {
                                setState(() {});
                              }
                              widget.onChanged?.call(nextStorage);
                              _dispatchValueEvent(
                                BehaviorEvent.onChanged,
                                data: {
                                  'value': nextStorage,
                                  'previousValue': previousStorage,
                                },
                                targetContext: context,
                              );
                              if (_controlledText != null) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted &&
                                      widget.controller == null &&
                                      _controlledText != null) {
                                    final expectedDisplay =
                                        _displayControlledText(
                                          _currentEffectiveConfig,
                                          _controlledText!,
                                          focused: _focusNode.hasFocus,
                                        );
                                    if (_internal.text != expectedDisplay) {
                                      _setText(_internal, expectedDisplay);
                                    }
                                  }
                                });
                              }
                            },
                            onSubmitted: (submittedText) {
                              if (_editorText != null) return;
                              final currentStorage = config.field.toStorageText(
                                submittedText,
                              );
                              _dispatchValueEvent(
                                BehaviorEvent.onSubmitted,
                                data: {'value': currentStorage},
                                targetContext: context,
                              );
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
                final needsFallbackWidth =
                    !config.kind.isBoolean &&
                    (config.mode == SuperValueMode.input ||
                        config.label.isNotEmpty);
                final activeBindingError = _bindingError ?? _binding?.error;
                syncComponentPropertyDiagnostics(
                  componentPrefix: 'super-value',
                  componentId: widget.id,
                  stateError: stateError,
                  propertyBindingErrors: propertyBindingErrors,
                  missingFontFamily: missingFont ? config.fontFamily : null,
                  showMissingFontError: missingFont && editing,
                );
                VibeDebugCapture.syncComponentDiagnostic(
                  componentId: widget.id,
                  sourceKey: 'super-value.bindingError',
                  active: activeBindingError != null,
                  category: DebugErrorCategory.binding,
                  severity: DebugSeverity.error,
                  message: activeBindingError,
                  source: 'SuperValue.binding',
                  visibleInUi: true,
                );
                if (config.kind.isBoolean ||
                    config.kind.isChoice ||
                    config.mode != SuperValueMode.input) {
                  VibeDebugCapture.syncComponentDiagnostic(
                    componentId: widget.id,
                    sourceKey: 'super-value.validationError',
                    active: false,
                    category: DebugErrorCategory.userInput,
                    severity: DebugSeverity.warning,
                    message: null,
                    source: 'SuperTextField.validation',
                  );
                }
                final showBindingError =
                    !config.kind.isChoice &&
                    (config.mode == SuperValueMode.display ||
                        config.kind.isBoolean) &&
                    activeBindingError != null;
                return LayoutBuilder(
                  builder: (context, constraints) => SizedBox(
                    width: !constraints.hasBoundedWidth
                        ? 240
                        : fitWidth &&
                              needsFallbackWidth &&
                              !constraints.hasTightWidth
                        ? 240.0.clamp(
                            constraints.minWidth,
                            constraints.maxWidth,
                          )
                        : null,
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
                        if (showBindingError ||
                            _binding?.error != null ||
                            propertyBindingErrors.isNotEmpty ||
                            stateError != null ||
                            (missingFont && editing))
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showBindingError)
                                    Text(
                                      _bindingError ?? _binding!.error!,
                                      key: ValueKey(
                                        'super-value-binding-error-${widget.id}',
                                      ),
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                    ),
                                  for (final entry in propertyBindingErrors.entries)
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
                                  if (stateError != null)
                                    Text(
                                      stateError!,
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

  SuperValueConfig get _currentEffectiveConfig {
    final registry = SuperApp.maybeOf(context)?.registry;
    final saved =
        (registry?.valueController(widget.id, fallback: widget.config) ??
                _local)
            .value;
    return _withBoundProperties(_effectiveConfig ?? saved);
  }

  String get extractedKey => resolveExtractableComponentKey(
    surface: _surface.currentState,
    fallbackId: widget.id,
    configLabel: _currentEffectiveConfig.label,
    ignoredLabels: const {'Value', 'Valeur'},
    preferConfigLabelFirst: true,
  );

  Object get extractedValue {
    final config = _currentEffectiveConfig;
    final text = _controlledText ?? _text.text;
    if (config.kind.isBoolean) {
      return text.trim().toLowerCase() == 'true';
    }
    if (config.kind.isChoice && config.choice.variant.isMultiple) {
      return SuperChoiceConfig.parseSelectedValues(text);
    }
    return text;
  }

  @override
  String get extractableId => widget.id;

  @override
  ExtractableComponentKind get extractableKind =>
      ExtractableComponentKind.superValue;

  @override
  EditorSlotState? get extractableSurface => _surface.currentState;

  @override
  BuildContext get extractableContext => context;

  @override
  bool get isExtractableMounted => mounted;

  @override
  String get preferredExtractableKey => extractedKey;

  @override
  ExtractableComponentTarget buildExtractableTarget(String assignedBaseKey) {
    final config = _currentEffectiveConfig;
    final options = <ExtractablePropertyOption>[
      ExtractablePropertyOption(
        id: 'value',
        label: 'Valeur',
        value: extractedValue,
        defaultSelected: true,
      ),
      if (config.label.trim().isNotEmpty)
        ExtractablePropertyOption(
          id: SuperValueProperty.label.name,
          label: 'Libellé',
          value: config.label,
        ),
      if (config.placeholder.trim().isNotEmpty)
        ExtractablePropertyOption(
          id: SuperValueProperty.placeholder.name,
          label: 'Placeholder',
          value: config.placeholder,
        ),
      if (config.prefix.trim().isNotEmpty)
        ExtractablePropertyOption(
          id: SuperValueProperty.prefix.name,
          label: 'Préfixe',
          value: config.prefix,
        ),
      if (config.suffix.trim().isNotEmpty)
        ExtractablePropertyOption(
          id: SuperValueProperty.suffix.name,
          label: 'Suffixe',
          value: config.suffix,
        ),
      ...buildTypographyExtractableOptions(
        fontFamily: config.fontFamily,
        color: config.color,
        fontSize: config.fontSize,
        fontWeight: config.fontWeight,
        italic: config.italic,
        textAlign: config.textAlign,
        defaultTextAlign: const SuperValueConfig().textAlign,
        hasTextAlignBinding: config.propertyBindings.containsKey(
          SuperValueProperty.textAlign,
        ),
      ),
    ];

    return ExtractableComponentTarget(
      id: widget.id,
      kind: ExtractableComponentKind.superValue,
      displayName: extractedKey,
      baseJsonKey: assignedBaseKey,
      properties: options,
      applyBindings: (bindings) {
        if (!mounted || bindings.isEmpty) return;
        final registry = SuperApp.maybeOf(context)?.registry;
        final controller =
            registry?.valueController(widget.id, fallback: widget.config) ??
            _local;
        final current = controller.value;
        final valueBinding = bindings['value'];
        final updatedProps = <SuperValueProperty, JsonTextBinding>{
          ...current.propertyBindings,
          for (final prop in SuperValueProperty.values)
            prop: ?bindings[prop.name],
        };
        final next = current.copyWith(
          binding: valueBinding ?? current.binding,
          propertyBindings: updatedProps,
        );
        if (next == current) return;
        controller.value = next;
        widget.onConfigChanged?.call(next);
      },
    );
  }
}

/// Extracts a `{ key: currentValue }` map for the [SuperValue] owned by [slot]
/// or all [SuperValue] components mounted inside [slot]'s subtree.
Map<String, Object?> extractSuperValuesFromSlot(EditorSlotState slot) {
  if (!slot.mounted) return const {};
  final statesById = <String, _SuperValueState>{};
  final direct = slot.context.findAncestorStateOfType<_SuperValueState>();
  if (direct != null &&
      direct.mounted &&
      identical(direct._surface.currentState, slot)) {
    statesById[direct.widget.id] = direct;
  } else {
    void visit(Element element) {
      if (element is StatefulElement) {
        final state = element.state;
        if (state is _SuperValueState && state.mounted) {
          final existing = statesById[state.widget.id];
          final scope = JsonListScope.maybeOf(state.context);
          final isPlaceholder = scope?.placeholder ?? false;
          final isSelected = scope?.selected ?? false;
          if (existing == null) {
            statesById[state.widget.id] = state;
          } else {
            final existingScope = JsonListScope.maybeOf(existing.context);
            final existingPlaceholder = existingScope?.placeholder ?? false;
            final existingSelected = existingScope?.selected ?? false;
            if ((existingPlaceholder && !isPlaceholder) ||
                (!existingSelected && isSelected && !isPlaceholder)) {
              statesById[state.widget.id] = state;
            }
          }
          return;
        }
      }
      element.visitChildren(visit);
    }

    slot.context.visitChildElements(visit);
  }
  if (statesById.isEmpty) return const {};
  final result = <String, Object?>{};
  for (final state in statesById.values) {
    final baseKey = state.extractedKey;
    var key = baseKey;
    var suffix = 2;
    while (result.containsKey(key)) {
      key = '${baseKey}_$suffix';
      suffix++;
    }
    result[key] = state.extractedValue;
  }
  return result;
}
