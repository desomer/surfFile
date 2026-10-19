import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:material_ui/material_ui.dart';

import '../../models/super_text_config.dart';
import '../../models/json_text_binding.dart';
import '../../services/json_list_scope.dart';
import '../../services/json_repository_binding.dart';
import '../../services/json_repository_scope.dart';
import '../../services/json_repository_store.dart';
import '../../services/json_text_controller_binding.dart';
import '../../super_app.dart';
import '../editing/editor_history.dart';
import '../editing/super_text_editor.dart';
import 'super_text_field.dart';
import '../surfaces/super_container.dart';

/// Display or edit text; runtime input persists only with a repository binding.
class SuperText extends StatefulWidget {
  const SuperText({
    required this.id,
    this.config = const SuperTextConfig(),
    this.controller,
    this.value,
    this.onChanged,
    this.onConfigChanged,
    this.availableFontFamilies = const [],
    super.key,
  }) : assert(
         controller == null || value == null,
         'Use either controller or value, not both.',
       );

  final String id;
  final SuperTextConfig config;
  final TextEditingController? controller;
  final String? value;
  final ValueChanged<String>? onChanged;
  final ValueChanged<SuperTextConfig>? onConfigChanged;
  final List<String> availableFontFamilies;

  @override
  State<SuperText> createState() => _SuperTextState();
}

class _SuperTextState extends State<SuperText> {
  final _surface = GlobalKey<SuperContainerState>();
  late final TextEditingController _internal;
  late final ValueNotifier<SuperTextConfig> _local;
  SuperTextConfig? _previousConfig;
  int _resetGeneration = 0;
  JsonTextControllerBinding? _binding;
  JsonTextBinding? _requestedBinding;
  JsonRepositoryStore? _requestedStore;
  bool? _requestedExternal;
  String? _requestedResolveError;
  bool _requestedPlaceholder = false;
  int _bindingGeneration = 0;
  String? _bindingError;

  /// A `[?]` resolved by a selection has no selected row: empty and read-only.
  bool _unselected = false;

  /// Selections the binding path depends on.
  List<JsonArrayBinding> _selections = const [];
  SuperTextConfig? _editorConfig;
  TextEditingController? _editorText;

  TextEditingController get _text => widget.controller ?? _internal;

  @override
  void initState() {
    super.initState();
    widget.config.validate();
    _internal = TextEditingController(
      text: widget.value ?? widget.config.initialText,
    );
    _local = ValueNotifier(widget.config);
  }

  @override
  void didUpdateWidget(SuperText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && widget.value != null) {
      throw ArgumentError('Use either controller or value, not both.');
    }
    widget.config.validate();
    if (oldWidget.config != widget.config) _local.value = widget.config;
    if (oldWidget.id != widget.id) {
      _previousConfig = null;
      _resetGeneration++;
      _requestedExternal = null;
    }
    if (widget.controller == null) {
      if (widget.value != null && widget.value != _internal.text) {
        _setText(_internal, widget.value!);
      } else if (oldWidget.controller != null && widget.value == null) {
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

  void _observeConfig(SuperTextConfig config) {
    config.validate();
    final previous = _previousConfig;
    _previousConfig = config;
    if (config.binding != null) {
      _resetGeneration++;
      return;
    }
    if (previous == null) {
      if (widget.controller == null && widget.value == null) {
        _setText(_internal, config.initialText);
      }
      return;
    }
    if (previous.mode == config.mode &&
        previous.initialText == config.initialText &&
        previous.binding == null &&
        (!config.obscureText || previous.obscureText)) {
      return;
    }
    final generation = ++_resetGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _resetGeneration) return;
      final text = config.obscureText ? '' : config.initialText;
      if (widget.value == null) _setText(_text, text);
      widget.onChanged?.call(text);
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
    SuperTextConfig config,
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
    SuperTextConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final external = widget.controller != null || widget.value != null;
    final resolved = _resolve(config, scope, store);
    _listenSelections(resolved.selections);
    if (_requestedBinding == resolved.binding &&
        _requestedResolveError == resolved.error &&
        _requestedPlaceholder == resolved.placeholder &&
        _requestedStore == store &&
        _requestedExternal == external) {
      return;
    }
    _requestedBinding = resolved.binding;
    _requestedResolveError = resolved.error;
    _requestedPlaceholder = resolved.placeholder;
    _requestedStore = store;
    _requestedExternal = external;
    final generation = ++_bindingGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _bindingGeneration) return;
      _binding?.removeListener(_bindingChanged);
      _binding?.dispose();
      _binding = null;
      _bindingError = resolved.error;
      _unselected = resolved.placeholder && !(scope?.placeholder ?? false);
      if (resolved.placeholder && !external) _setText(_internal, '');
      if (resolved.binding != null) {
        if (external) {
          _bindingError =
              'La liaison nécessite le contrôleur interne de SuperText.';
        } else if (store == null) {
          _bindingError = 'Service de repositories indisponible.';
        } else {
          _binding = JsonTextControllerBinding(
            store: store,
            binding: resolved.binding!,
            controller: _internal,
            onChanged: (text) => widget.onChanged?.call(text),
          )..addListener(_bindingChanged);
        }
      }
      setState(() {});
    });
  }

  void _bindingChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bindingGeneration++;
    _listenSelections(const []);
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
        registry?.textController(widget.id, fallback: widget.config) ?? _local;
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    final canConfigure = StyleEditScope.controllerOf(context)?.value ?? true;

    return ValueListenableBuilder<SuperTextConfig>(
      valueListenable: configuration,
      builder: (context, savedConfig, _) {
        _observeBinding(savedConfig, listScope, repositories);
        _observeConfig(savedConfig);
        final config = _editorConfig ?? savedConfig;
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
        return SuperContainer(
          key: _surface,
          label: 'Texte',
          decorate: false,
          onEdit: () async {
            if (_editorText != null) return;
            final initial = configuration.value;
            final originalText = _text.text;
            _editorText = TextEditingController.fromValue(_text.value);
            SuperTextConfig? result;
            try {
              result = await showSuperTextEditor(
                context: context,
                config: initial,
                availableFontFamilies: widget.availableFontFamilies,
                allowBinding: widget.controller == null && widget.value == null,
                onPreviewChanged: (draft) {
                  if (!mounted || _editorText == null) return;
                  final text =
                      draft.binding == null &&
                          draft.obscureText &&
                          !initial.obscureText
                      ? ''
                      : draft.binding == null &&
                            (draft.initialText != initial.initialText ||
                                draft.mode != initial.mode)
                      ? draft.initialText
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
                  ? widget.value ?? value.text
                  : value.text;
              final display = Text(
                text.isEmpty
                    ? config.placeholder
                    : config.obscureText
                    ? List.filled(text.runes.length, '\u2022').join()
                    : text,
                key: ValueKey('super-text-display-${widget.id}'),
                style: style,
                textAlign: config.textAlign,
                maxLines: config.maxLines,
                overflow: TextOverflow.ellipsis,
              );
              final content = config.mode == SuperTextMode.input
                  ? Listener(
                      onPointerDown: (event) {
                        // TextField consumes secondary taps before SuperContainer.
                        if (canConfigure &&
                            event.buttons == kSecondaryMouseButton) {
                          _surface.currentState?.openMenu(event.position);
                        }
                      },
                      child: SuperTextField(
                        key: ValueKey('super-text-field-${widget.id}'),
                        inputKey: ValueKey('super-text-input-${widget.id}'),
                        config: config,
                        controller: controller,
                        style: style,
                        enabled:
                            config.enabled &&
                            !(config.binding != null &&
                                _binding?.loading == true),
                        readOnly: _unselected ? true : null,
                        bindingError: _bindingError ?? _binding?.error,
                        onChanged: (text) {
                          if (_editorText != null) return;
                          widget.onChanged?.call(text);
                          if (widget.value != null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted &&
                                  widget.controller == null &&
                                  widget.value != null &&
                                  _internal.text != widget.value) {
                                _setText(_internal, widget.value!);
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
                        labelText: config.label.isEmpty ? null : config.label,
                        enabled: config.enabled,
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      isEmpty: false,
                      child: display,
                    );

              return LayoutBuilder(
                builder: (context, constraints) => SizedBox(
                  width: constraints.hasBoundedWidth ? null : 240,
                  height: constraints.hasBoundedHeight
                      ? constraints.maxHeight
                      : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(child: content),
                      if (config.mode == SuperTextMode.display &&
                          (_bindingError != null || _binding?.error != null))
                        Text(
                          _bindingError ?? _binding!.error!,
                          key: ValueKey(
                            'super-text-binding-error-${widget.id}',
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      // if (_binding != null &&
                      //     (_binding!.loading || _binding!.saving))
                      //   Text(
                      //     _binding!.loading ? 'Chargement…' : 'Enregistrement…',
                      //   ),
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
                      if (missingFont && editing)
                        Text(
                          'Police indisponible : ${config.fontFamily}. Choisissez une police disponible.',
                          key: ValueKey('super-text-font-warning-${widget.id}'),
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
    );
  }
}
