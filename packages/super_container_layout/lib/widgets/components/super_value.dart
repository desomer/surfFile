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
import '../../models/json_text_binding.dart';
import '../../models/super_choice_config.dart';
import '../../models/super_value_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/repositories/json_text_controller_binding.dart';
import '../../services/states/content_hover_scope.dart';
import '../../super_app.dart';
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

  /// A `[?]` resolved by a selection has no selected row: empty and read-only.
  bool _unselected = false;

  /// Selections the binding path depends on.
  List<JsonArrayBinding> _selections = const [];
  SuperValueConfig? _editorConfig;
  TextEditingController? _editorText;
  List<String>? _activeStates;
  SuperValueConfig? _effectiveConfig;
  bool _hadStates = false;
  final _focusNode = FocusNode();
  Future<void>? _pendingBindingFlush;

  static String _initialTextFor(SuperValueConfig config) =>
      config.kind.isBoolean
      ? (config.initialBool ? 'true' : 'false')
      : (config.obscureText ? '' : config.initialText);

  @override
  List<String> get availableComponentFontFamilies =>
      widget.availableFontFamilies;

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
  }) {
    syncSurfaceStateReader(saved.states?.binding, scope, store);
    try {
      final source =
          saved.states?.resolve(saved, name: stateReader?.stateName) ??
          saved.copyWith(clearStates: true);
      final input = source.mode == SuperValueMode.input;
      final effectiveDisabled =
          behaviorDisabled || (input && !source.enabled);
      final effectiveReadOnly =
          behaviorReadOnly || (input && source.readOnly);
      automaticActiveStates = {
        if (contentHovered) AutomaticState.contentHover,
        if (input && _focusNode.hasFocus) AutomaticState.focused,
        if (effectiveDisabled) AutomaticState.disabled,
        if (effectiveReadOnly) AutomaticState.readOnly,
      };
      var config =
          saved.states?.resolve(
            saved,
            name: stateReader?.stateName,
            isHovered: isComponentHovered,
            isSelected: scope?.selected ?? false,
            activeStates: automaticActiveStates,
          ) ??
          saved;
      if (behaviorDisabled && config.enabled) {
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
    var fallback = saved.copyWith(clearStates: true);
    if (behaviorDisabled && fallback.enabled) {
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
    _internal = TextEditingController(
      text: _controlledText ?? _initialTextFor(widget.config),
    );
    _local = ValueNotifier(widget.config);
    _focusNode.addListener(onComponentStateChanged);
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
      _requestedAsStringList = null;
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
    _requestedBinding = resolved.binding;
    _requestedResolveError = resolved.error;
    _requestedPlaceholder = resolved.placeholder;
    _requestedStore = store;
    _requestedExternal = external;
    _requestedAsBool = asBool;
    _requestedAsStringList = asStringList;
    final generation = ++_bindingGeneration;

    if (!external &&
        resolved.error == null &&
        !resolved.placeholder &&
        resolved.binding != null &&
        store != null &&
        _binding == null &&
        _pendingBindingFlush == null) {
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
            : cached.text;
        if (_internal.text != resolvedText) {
          _setText(_internal, resolvedText);
        }
      }
    }

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
          oldBinding.asStringList == asStringList &&
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
      if (flushed != null) {
        await flushed;
        if (identical(_pendingBindingFlush, flushed)) {
          _pendingBindingFlush = null;
        }
      }
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
            componentId: widget.id,
            asBool: asBool,
            asStringList: asStringList,
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
    _focusNode.removeListener(onComponentStateChanged);
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
    child: Builder(builder: _buildValueContent),
  );

  Widget _buildValueContent(BuildContext context) {
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

    return wrapWithComponentHoverRegion(
      ValueListenableBuilder<SuperValueConfig>(
        valueListenable: configuration,
        builder: (context, savedConfig, _) {
          final effective = _resolveStates(
            savedConfig,
            listScope,
            repositories,
            ContentHoverScope.maybeOf(context)?.hovered == true,
            behaviorDisabled: behaviorDisabled,
            behaviorReadOnly: behaviorReadOnly,
          );
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
                        : key == stateReader?.stateName)
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
          observePropertyBindings(
            effective.propertyBindings,
            listScope,
            repositories,
          );
          final config = _editorConfig ?? _withBoundProperties(effective);
          final controller = _editorText ?? _text;
          final missingFont = isComponentFontMissing(
            config.fontFamily,
            widget.availableFontFamilies,
          );
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
            eventData: () {
              final current = _currentEffectiveConfig;
              return {
                'value': current.kind.isBoolean
                    ? _text.text.trim().toLowerCase() == 'true'
                    : current.kind.isChoice && current.choice.variant.isMultiple
                    ? SuperChoiceConfig.parseSelectedValues(_text.text)
                    : _text.text,
              };
            },
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
                  content = Listener(
                    onPointerDown: (event) {
                      if (canConfigure &&
                          event.buttons == kSecondaryMouseButton) {
                        _surface.currentState?.openMenu(event.position);
                      }
                    },
                    child: SuperChoice(
                      key: ValueKey('super-value-choice-${widget.id}'),
                      inputKey: ValueKey('super-value-input-${widget.id}'),
                      config: config,
                      focusNode: _focusNode,
                      controller: controller,
                      style: style,
                      enabled:
                          config.enabled &&
                          !(config.binding != null && _binding?.loading == true),
                      readOnly: _unselected || bindingReadOnly ? true : null,
                      bindingError: _bindingError ?? _binding?.error,
                      onChanged: (text) {
                        if (_editorText != null) return;
                        unawaited(_binding?.flush());
                        widget.onChanged?.call(text);
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
                            readOnly: _unselected || bindingReadOnly
                                ? true
                                : null,
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
                final needsFallbackWidth =
                    !config.kind.isBoolean &&
                    (config.mode == SuperValueMode.input ||
                        config.label.isNotEmpty);
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
                        if (!config.kind.isChoice &&
                            (config.mode == SuperValueMode.display ||
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
