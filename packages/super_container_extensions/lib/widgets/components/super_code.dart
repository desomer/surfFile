/// Editeur de code colore, synchronise avec une chaine d'un repository JSON.
library;

import 'package:highlight/languages/javascript.dart' as javascript;
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton, kTouchSlop;
import 'package:highlight/languages/yaml.dart' as yaml;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../extensions_registry.dart';
import '../../models/super_code_config.dart';
import '../editing/components/super_code_editor.dart';
import 'internal_widget/code_editor.dart';

/// Composant Code configurable; aucune execution du code saisi.
class SuperCode extends SuperStatefulComponent<SuperCodeConfig>
    implements SliverCapableWidget {
  const SuperCode({
    required this.id,
    this.config = const SuperCodeConfig(),
    this.onConfigChanged,
    super.behaviours,
    super.key,
  });

  /// Identifiant dans Appearance.components.
  @override
  final String id;

  /// Configuration initiale hors registre.
  @override
  final SuperCodeConfig config;

  /// Notification apres application des reglages.
  final ValueChanged<SuperCodeConfig>? onConfigChanged;

  @override
  State<SuperCode> createState() => _SuperCodeState();
}

class _SuperCodeState extends State<SuperCode> {
  final _surface = GlobalKey<EditorSlotState>();
  PointerDownEvent? _secondaryDown;
  bool _secondaryMoved = false;
  late final _local = ValueNotifier(widget.config);
  List<JsonArrayBinding> _arrays = const [];

  @override
  void didUpdateWidget(SuperCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config || oldWidget.id != widget.id) {
      _local.value = widget.config;
    }
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  void _listen(List<JsonArrayBinding> arrays) {
    for (final array in _arrays) {
      array.removeListener(_selectionChanged);
    }
    _arrays = arrays;
    for (final array in arrays) {
      array.addListener(_selectionChanged);
    }
  }

  @override
  void dispose() {
    _listen(const []);
    _local.dispose();
    super.dispose();
  }

  Future<void> _edit(ValueNotifier<SuperCodeConfig> configuration) async {
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    SuperCodeConfig? result;
    try {
      result = await showSuperCodeEditor(
        context: context,
        config: configuration.value,
      );
      if (result != null && mounted && result != configuration.value) {
        configuration.value = result;
        widget.onConfigChanged?.call(result);
      }
    } finally {
      if (result != null) {
        history?.commitTransaction();
      } else {
        history?.cancelTransaction();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final configuration =
        SuperApp.maybeOf(context)?.registry
            ?.codeController(widget.id, fallback: widget.config) ??
        _local;
    final store = JsonRepositoryScope.maybeOf(context);
    final scope = JsonListScope.maybeOf(context);
    final sliver = SliverSlotScope.isSliver(context);
    final canConfigure = StyleEditScope.controllerOf(context)?.value ?? true;
    return ValueListenableBuilder<SuperCodeConfig>(
      valueListenable: configuration,
      builder: (context, config, _) {
        JsonTextBinding? binding;
        JsonTextBinding? errorBinding;
        String? error;
        final arrays = <JsonArrayBinding>[];
        final placeholder = scope?.placeholder ?? false;
        try {
          config.validate();
          if ((config.binding != null || config.errorBinding != null) &&
              !placeholder) {
            if (store == null) {
              throw const FormatException('Repository indisponible.');
            }
            if (config.binding != null) {
              final resolved = JsonListScope.resolveSelected(
                config.binding!,
                scope,
                store,
              );
              binding = resolved.binding;
              arrays.addAll(resolved.arrays);
            }
            if (config.errorBinding != null) {
              final resolved = JsonListScope.resolveSelected(
                config.errorBinding!,
                scope,
                store,
              );
              errorBinding = resolved.binding;
              arrays.addAll(resolved.arrays);
            }
          }
        } on FormatException catch (exception) {
          error = exception.message;
        }
        _listen(arrays);
        final content = _BoundCode(
          key: ValueKey((widget.id, store, binding, errorBinding, placeholder)),
          config: config,
          binding: binding,
          errorBinding: errorBinding,
          store: store,
          error: error,
          componentId: widget.id,
        );
        final body = LayoutBuilder(
          builder: (context, constraints) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (event.buttons == kSecondaryMouseButton) {
                _secondaryDown = event;
                _secondaryMoved = false;
              }
            },
            onPointerMove: (event) {
              final down = _secondaryDown;
              if (down != null &&
                  down.pointer == event.pointer &&
                  (down.position - event.position).distance > kTouchSlop) {
                _secondaryMoved = true;
              }
            },
            onPointerUp: (event) {
              final down = _secondaryDown;
              _secondaryDown = null;
              if (canConfigure &&
                  down != null &&
                  down.pointer == event.pointer &&
                  !_secondaryMoved &&
                  (down.position - event.position).distance <= kTouchSlop) {
                _surface.currentState?.openMenu(event.position);
              }
            },
            onPointerCancel: (_) => _secondaryDown = null,
            child: constraints.hasBoundedHeight
                ? content
                : SizedBox(height: 300, child: content),
          ),
        );
        return EditorSlot(
          behaviors: widget.behaviours,
          key: _surface,
          id: widget.id,
          label: 'Code',
          menuType: 'Code',
          menuIcon: Icons.code,
          menuTooltip: () =>
              'Code ${config.mode.label}\n${config.binding?.path ?? 'Sans liaison'}',
          onEdit: () => _edit(configuration),
          child: sliver
              ? SliverToBoxAdapter(
                  child: SliverSlotScope(
                    enabled: false,
                    child: SizedBox(height: 300, child: body),
                  ),
                )
              : body,
        );
      },
    );
  }
}

class _BoundCode extends StatefulWidget {
  const _BoundCode({
    required this.config,
    required this.binding,
    required this.store,
    required this.error,
    required this.componentId,
    this.errorBinding,
    super.key,
  });

  final SuperCodeConfig config;
  final JsonTextBinding? binding;
  final JsonTextBinding? errorBinding;
  final JsonRepositoryStore? store;
  final String? error;
  final String componentId;

  @override
  State<_BoundCode> createState() => _BoundCodeState();
}

class _BoundCodeState extends State<_BoundCode> {
  final _text = TextEditingController();
  final _error = ValueNotifier('');
  final _errorText = TextEditingController();
  JsonTextControllerBinding? _binding;
  // Read-only: _errorText is never edited, so this binding never writes.
  JsonTextControllerBinding? _errorBinding;

  @override
  void initState() {
    super.initState();
    final binding = widget.binding;
    final errorBinding = widget.errorBinding;
    final store = widget.store;
    if (errorBinding != null && store != null) {
      _errorBinding = JsonTextControllerBinding(
        store: store,
        binding: errorBinding,
        controller: _errorText,
        componentId: widget.componentId,
      )..addListener(_changed);
    }
    if (binding != null && store != null) {
      _binding = JsonTextControllerBinding(
        store: store,
        binding: binding,
        controller: _text,
        componentId: widget.componentId,
        requireString: true,
      )..addListener(_changed);
    }
  }

  void _changed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _binding?.removeListener(_changed);
    _binding?.dispose();
    _errorBinding?.removeListener(_changed);
    _errorBinding?.dispose();
    _errorText.dispose();
    _text.dispose();
    _error.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final binding = _binding;
    _error.value =
        widget.error ??
        binding?.error ??
        _errorBinding?.error ??
        _errorText.text;
    return CodeEditor(
      config: CodeEditorConfig(
        mode: switch (widget.config.mode) {
          SuperCodeMode.yaml => yaml.yaml,
          SuperCodeMode.javascript => javascript.javascript,
        },
        getText: () => _text.text,
        onChange: (String text, CodeEditorConfig config) {
          if (!config.readOnly && _text.text != text) _text.text = text;
        },
        notifError: _error,
        readOnly:
            widget.config.readOnly ||
            binding == null ||
            binding.loading ||
            (binding.error != null && !binding.dirty),
        useLargeTextViewer: false,
        type: 'code',
      ),
    );
  }
}
