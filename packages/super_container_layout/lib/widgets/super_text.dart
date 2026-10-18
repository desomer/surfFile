import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:material_ui/material_ui.dart';

import '../models/super_text_config.dart';
import '../models/json_text_binding.dart';
import '../services/json_repository_scope.dart';
import '../services/json_repository_store.dart';
import '../services/json_text_controller_binding.dart';
import '../super_app.dart';
import 'editing/editor_history.dart';
import 'editing/super_text_editor.dart';
import 'super_text_field.dart';
import 'surfaces/super_container.dart';

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
  int _bindingGeneration = 0;
  String? _bindingError;

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

  void _observeBinding(SuperTextConfig config, JsonRepositoryStore? store) {
    final external = widget.controller != null || widget.value != null;
    if (_requestedBinding == config.binding &&
        _requestedStore == store &&
        _requestedExternal == external) {
      return;
    }
    _requestedBinding = config.binding;
    _requestedStore = store;
    _requestedExternal = external;
    final generation = ++_bindingGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _bindingGeneration) return;
      _binding?.removeListener(_bindingChanged);
      _binding?.dispose();
      _binding = null;
      _bindingError = null;
      if (config.binding != null) {
        if (external) {
          _bindingError =
              'La liaison nécessite le contrôleur interne de SuperText.';
        } else if (store == null) {
          _bindingError = 'Service de repositories indisponible.';
        } else {
          _binding = JsonTextControllerBinding(
            store: store,
            binding: config.binding!,
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
    _binding?.removeListener(_bindingChanged);
    _binding?.dispose();
    _resetGeneration++;
    _internal.dispose();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final repositories = JsonRepositoryScope.maybeOf(context);
    final configuration =
        registry?.textController(widget.id, fallback: widget.config) ?? _local;
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    final canConfigure = StyleEditScope.controllerOf(context)?.value ?? true;

    return ValueListenableBuilder<SuperTextConfig>(
      valueListenable: configuration,
      builder: (context, config, _) {
        _observeBinding(config, repositories);
        _observeConfig(config);
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
            final result = await showSuperTextEditor(
              context: context,
              config: configuration.value,
              availableFontFamilies: widget.availableFontFamilies,
              allowBinding: widget.controller == null && widget.value == null,
            );
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
            valueListenable: _text,
            builder: (context, value, _) {
              final text = widget.value ?? value.text;
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
                        controller: _text,
                        style: style,
                        enabled:
                            config.enabled &&
                            !(config.binding != null &&
                                _binding?.loading == true),
                        bindingError: _bindingError ?? _binding?.error,
                        onChanged: (text) {
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
