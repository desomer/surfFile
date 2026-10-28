import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/native_component_config.dart';
import '../../../models/native_property_descriptor.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_binding.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../services/repositories/json_text_controller_binding.dart';
import '../../../super_app.dart';
import '../../editing/components/native_component_editor.dart';
import '../../editing/repositories/repository_binding_fields.dart';
import '../super_layout/slot_implementation.dart';

/// Adapter around Flutter's native [Expansible] widget with editable `header`
/// and `body` regions and optional two-way boolean JSON repository binding
/// for its open/closed state.
class SuperExpansible extends StatefulWidget {
  static const List<NativePropertyDescriptor> propertyDescriptors =
      superExpansiblePropertyDescriptors;

  const SuperExpansible({
    this.id = 'root-expansible',
    this.label = 'Expansible',
    this.header,
    this.headers = const [],
    this.body,
    this.bodies = const [],
    this.controller,
    this.initiallyExpanded = false,
    this.maintainState = true,
    this.headerClickToggles = true,
    this.toggleIcon,
    this.toggleIconPosition = 'trailing',
    this.animationStyle,
    this.expansibleBuilder,
    this.onExpansionChanged,
    this.slots = const [],
    this.nativeConfig,
    this.onNativeSlotAdded,
    super.key,
  });

  final String id;
  final String label;

  /// Shorthand for a single header widget or the first entry in [headers].
  final Widget? header;
  final List<Widget> headers;

  /// Shorthand for a single body widget or the first entry in [bodies].
  final Widget? body;
  final List<Widget> bodies;

  /// Optional external [ExpansibleController]. When omitted, an internal
  /// controller is managed and synchronized with [NativeComponentConfig.binding].
  final ExpansibleController? controller;

  /// Default expansion state when unbound.
  final bool initiallyExpanded;

  /// Whether the body widget subtree is kept alive in the tree when collapsed.
  final bool maintainState;

  /// Whether tapping the header region toggles the expansion state at runtime.
  final bool headerClickToggles;

  /// Optional preset toggle icon style (`'none'`, `'chevron'`, `'arrow'`, `'plusMinus'`, `'triangle'`).
  final String? toggleIcon;

  /// Position of the toggle icon inside the header (`'trailing'` or `'leading'`).
  final String toggleIconPosition;

  /// Optional animation style passed to Flutter's [Expansible].
  final AnimationStyle? animationStyle;

  /// Optional custom layout builder passed to Flutter's [Expansible].
  final ExpansibleBuilder? expansibleBuilder;

  /// Called whenever the expansion state changes.
  final ValueChanged<bool>? onExpansionChanged;

  final List<SlotImplementation> slots;
  final NativeComponentConfig? nativeConfig;
  final NativeSlotAddedCallback? onNativeSlotAdded;

  NativeComponentConfig get _initialConfig =>
      nativeConfig ??
      NativeComponentConfig(
        properties: {
          if (initiallyExpanded) 'initiallyExpanded': true,
          if (!maintainState) 'maintainState': false,
          if (!headerClickToggles) 'headerClickToggles': false,
          if (toggleIcon != null && toggleIcon!.trim() != 'none')
            'toggleIcon': toggleIcon!,
          if (toggleIconPosition.trim() != 'trailing')
            'toggleIconPosition': toggleIconPosition,
        },
        regions: const {'header': true, 'body': true},
        placements: {
          if (header != null || headers.isNotEmpty)
            'header': [
              if (header != null) 'header',
              for (var i = 0; i < headers.length; i++) 'header:$i',
            ],
          if (body != null || bodies.isNotEmpty)
            'body': [
              if (body != null) 'body',
              for (var i = 0; i < bodies.length; i++) 'body:$i',
            ],
        },
      );

  @override
  State<SuperExpansible> createState() => _SuperExpansibleState();
}

class _SuperExpansibleState extends State<SuperExpansible> {
  late final _localConfig = ValueNotifier(widget._initialConfig);
  late final ExpansibleController _internalExpansible = ExpansibleController();
  late final TextEditingController _internalText = TextEditingController(
    text: widget.initiallyExpanded ? 'true' : 'false',
  );
  final PageStorageBucket _isolatedPageStorage = PageStorageBucket();

  NativeComponentConfig? _previousConfig;
  bool _initialExpansionSynced = false;
  bool _syncingFromBinding = false;
  late bool _lastKnownExpanded;

  JsonTextControllerBinding? _binding;
  JsonTextBinding? _requestedBinding;
  JsonRepositoryStore? _requestedStore;
  String? _requestedResolveError;
  bool _requestedPlaceholder = false;
  int _bindingGeneration = 0;
  String? _bindingError;
  bool _unselected = false;
  List<JsonArrayBinding> _selections = const [];
  Future<void>? _pendingBindingFlush;

  ExpansibleController get _effectiveController =>
      widget.controller ?? _internalExpansible;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null && widget.initiallyExpanded) {
      _internalExpansible.expand();
    }
    _lastKnownExpanded = _effectiveController.isExpanded;
    _effectiveController.addListener(_handleExpansibleChanged);
  }

  @override
  void didUpdateWidget(SuperExpansible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleExpansibleChanged);
      if (oldWidget.controller == null) {
        _internalExpansible.removeListener(_handleExpansibleChanged);
      }
      _lastKnownExpanded = _effectiveController.isExpanded;
      _effectiveController.addListener(_handleExpansibleChanged);
    }
    if (oldWidget.id != widget.id) {
      _previousConfig = null;
      _initialExpansionSynced = false;
      _requestedBinding = null;
      _requestedStore = null;
      _requestedResolveError = null;
      _requestedPlaceholder = false;
    }
  }

  void _setText(String text) {
    if (_internalText.text == text) return;
    _internalText.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _setExpanded(bool expanded, {required bool fromBinding}) {
    if (_effectiveController.isExpanded == expanded) return;
    final previousSync = _syncingFromBinding;
    _syncingFromBinding = fromBinding;
    try {
      if (expanded) {
        _effectiveController.expand();
      } else {
        _effectiveController.collapse();
      }
    } finally {
      _syncingFromBinding = previousSync;
    }
  }

  void _handleExpansibleChanged() {
    final expanded = _effectiveController.isExpanded;
    final changed = expanded != _lastKnownExpanded;
    _lastKnownExpanded = expanded;
    if (!_syncingFromBinding) {
      _setText(expanded ? 'true' : 'false');
      unawaited(_binding?.flush());
    }
    if (changed) {
      widget.onExpansionChanged?.call(expanded);
    }
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

  void _observeConfig(NativeComponentConfig config) {
    config.validate();
    final previous = _previousConfig;
    _previousConfig = config;
    final desiredInitial = config.initiallyExpanded ?? widget.initiallyExpanded;

    if (!_initialExpansionSynced) {
      _initialExpansionSynced = true;
      if (widget.controller == null && config.binding == null) {
        _internalExpansible.removeListener(_handleExpansibleChanged);
        try {
          if (desiredInitial) {
            _internalExpansible.expand();
          } else {
            _internalExpansible.collapse();
          }
          _lastKnownExpanded = _internalExpansible.isExpanded;
          _setText(desiredInitial ? 'true' : 'false');
        } finally {
          _internalExpansible.addListener(_handleExpansibleChanged);
        }
      }
      return;
    }

    if (config.binding != null || widget.controller != null) return;
    final previousInitial =
        previous?.initiallyExpanded ?? widget.initiallyExpanded;
    if (previousInitial != desiredInitial || previous?.binding != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _setExpanded(desiredInitial, fromBinding: false);
      });
    }
  }

  ({
    JsonTextBinding? binding,
    String? error,
    bool placeholder,
    List<JsonArrayBinding> selections,
  })
  _resolveBinding(
    NativeComponentConfig config,
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
    NativeComponentConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final resolved = _resolveBinding(config, scope, store);
    _listenSelections(resolved.selections);
    if (_requestedBinding == resolved.binding &&
        _requestedResolveError == resolved.error &&
        _requestedPlaceholder == resolved.placeholder &&
        _requestedStore == store) {
      return;
    }
    _requestedBinding = resolved.binding;
    _requestedResolveError = resolved.error;
    _requestedPlaceholder = resolved.placeholder;
    _requestedStore = store;
    final generation = ++_bindingGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _bindingGeneration) return;
      final oldBinding = _binding;
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
      if (resolved.placeholder) {
        _setText('false');
        _setExpanded(false, fromBinding: true);
      }
      if (resolved.binding != null) {
        if (store == null) {
          _bindingError = 'Service de repositories indisponible.';
        } else {
          _binding = JsonTextControllerBinding(
            store: store,
            binding: resolved.binding!,
            controller: _internalText,
            asBool: true,
            onChanged: (text) {
              if (!mounted) return;
              _setExpanded(text == 'true', fromBinding: true);
            },
          )..addListener(_bindingChanged);
        }
      }
      if (mounted) setState(() {});
    });
  }

  void _bindingChanged() {
    if (!mounted) return;
    final binding = _binding;
    if (binding != null && !binding.loading && binding.error == null) {
      final desired = _internalText.text == 'true';
      if (_effectiveController.isExpanded != desired) {
        _setExpanded(desired, fromBinding: true);
      }
    }
    setState(() {});
  }

  List<SlotImplementation> get _slots => [
    if (widget.header case final child?)
      BuilderSlot(id: 'header', label: 'header', builder: (_) => child),
    for (final (index, child) in widget.headers.indexed)
      BuilderSlot(
        id: 'header:$index',
        label: 'header ${index + 1}',
        builder: (_) => child,
      ),
    if (widget.body case final child?)
      BuilderSlot(id: 'body', label: 'body', builder: (_) => child),
    for (final (index, child) in widget.bodies.indexed)
      BuilderSlot(
        id: 'body:$index',
        label: 'body ${index + 1}',
        builder: (_) => child,
      ),
    ...widget.slots,
  ];

  NativeComponentConfig _added(
    NativeComponentConfig config,
    String region,
    String id,
    SlotImplementation slot,
    List<SlotImplementation> siblings,
  ) {
    return widget.onNativeSlotAdded?.call(config, region, id, slot, siblings) ??
        config;
  }

  static const List<NativeRegion> _regions = [
    NativeRegion(
      'header',
      'En-tête',
      required: true,
      axis: Axis.horizontal,
      expand: true,
      stretch: false,
      editableFlow: true,
      emptySize: Size(double.infinity, 48),
    ),
    NativeRegion(
      'body',
      'Contenu',
      required: true,
      axis: Axis.vertical,
      expand: false,
      stretch: true,
      editableFlow: true,
      emptySize: Size(double.infinity, 120),
    ),
  ];

  String _bindingSummary(JsonTextBinding? binding) => binding == null
      ? 'Aucune liaison'
      : '${binding.repositoryId ?? 'Repository hérité'} · ${binding.path}';

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final controller =
        registry?.nativeComponentController(
          widget.id,
          fallback: widget._initialConfig,
        ) ??
        _localConfig;
    final listScope = JsonListScope.maybeOf(context);
    final repositoryStore = JsonRepositoryScope.maybeOf(context);

    return ValueListenableBuilder<NativeComponentConfig>(
      valueListenable: controller,
      builder: (context, config, _) {
        _observeConfig(config);
        _observeBinding(config, listScope, repositoryStore);
        final effectiveMaintainState =
            config.maintainState ?? widget.maintainState;
        final effectiveHeaderToggle =
            config.headerClickToggles ?? widget.headerClickToggles;
        final effectiveToggleIcon = config.toggleIcon ?? widget.toggleIcon;
        final effectiveToggleIconPosition =
            config.toggleIconPosition ?? widget.toggleIconPosition;
        final activeError = _bindingError ?? _binding?.error;

        return NativeComponentEditor(
          id: widget.id,
          label: widget.label,
          menuType: 'Expansible',
          menuIcon: Icons.unfold_more_outlined,
          keyPrefix: 'super-expansible',
          settingsTitle: 'Configurer l’expansible',
          editSurface: true,
          config: config,
          onChanged: (value) => controller.value = value,
          registry: registry,
          slots: _slots,
          onSlotAdded: _added,
          regions: _regions,
          propertyDescriptors: SuperExpansible.propertyDescriptors,
          regionActions: (region) {
            if (region != 'header') return const [];
            final expanded = _effectiveController.isExpanded;
            return [
              IconButton(
                key: ValueKey('super-expansible-toggle-${widget.id}'),
                icon: Icon(
                  expanded ? Icons.unfold_less : Icons.unfold_more,
                  size: 16,
                ),
                tooltip: expanded ? 'Replier le contenu' : 'Déplier le contenu',
                visualDensity: VisualDensity.compact,
                onPressed: _effectiveController.toggle,
              ),
            ];
          },
          settingsControls: (current, update) => [
            ListTile(
              key: const ValueKey('super-expansible-binding'),
              leading: const Icon(Icons.link),
              title: const Text('Liaison état ouvert / fermé'),
              subtitle: Text(_bindingSummary(current.binding)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final result = await showRepositoryBindingDialog(
                  context: context,
                  title: 'Lier l’état ouvert / fermé',
                  keyPrefix: 'super-expansible-binding',
                  pathHint: 'ui.ouvert ou clients[?].ouvert',
                  helper:
                      'Attribut booléen JSON synchronisé avec l’ouverture de l’expansible.',
                  binding: current.binding,
                  store: repositoryStore,
                  listScope: listScope,
                );
                if (result != null) {
                  update(current.withBinding(result.binding));
                }
              },
            ),
          ],
          builder: (context, editor) {
            final canToggleOnHeaderTap =
                !editor.editing && effectiveHeaderToggle && !_unselected;
            Widget exp = PageStorage(
              bucket: _isolatedPageStorage,
              child: Expansible(
                controller: _effectiveController,
                maintainState: effectiveMaintainState || editor.editing,
                animationStyle: widget.animationStyle,
                expansibleBuilder:
                    widget.expansibleBuilder ??
                    (context, header, body, animation) => LayoutBuilder(
                      builder: (context, constraints) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          if (constraints.hasBoundedHeight)
                            Flexible(
                              fit: FlexFit.loose,
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: body,
                              ),
                            )
                          else
                            body,
                        ],
                      ),
                    ),
                headerBuilder: (context, animation) {
                  final fixedHeaderSize = editor.sizeOf('header');
                  final headerFlow = editor.flowOf('header');
                  final toggleIconData = resolveNativeToggleIcon(
                    effectiveToggleIcon,
                    expanded: _effectiveController.isExpanded,
                  );
                  Widget headerWidget = SlotContentFitScope(
                    fitWidth: false,
                    fitHeight:
                        fixedHeaderSize == null || !headerFlow.expandSlots,
                    child: editor.region('header'),
                  );
                  if (toggleIconData != null) {
                    final isLeading = effectiveToggleIconPosition == 'leading';
                    final regionChild = headerWidget;
                    final iconWidget = Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        toggleIconData,
                        key: ValueKey(
                          'super-expansible-header-toggle-icon-${widget.id}',
                        ),
                        size: 20,
                      ),
                    );
                    headerWidget = LayoutBuilder(
                      builder: (context, constraints) => Row(
                        mainAxisSize: constraints.hasBoundedWidth
                            ? MainAxisSize.max
                            : MainAxisSize.min,
                        children: [
                          if (isLeading) iconWidget,
                          if (constraints.hasBoundedWidth)
                            Expanded(child: regionChild)
                          else
                            Flexible(fit: FlexFit.loose, child: regionChild),
                          if (!isLeading) iconWidget,
                        ],
                      ),
                    );
                  }
                  if (canToggleOnHeaderTap) {
                    headerWidget = MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        key: ValueKey(
                          'super-expansible-header-tap-${widget.id}',
                        ),
                        behavior: HitTestBehavior.opaque,
                        onTap: _effectiveController.toggle,
                        child: headerWidget,
                      ),
                    );
                  }
                  return headerWidget;
                },
                bodyBuilder: (context, animation) {
                  final fixedBodySize = editor.sizeOf('body');
                  final bodyFlow = editor.flowOf('body');
                  return SlotContentFitScope(
                    fitWidth: false,
                    fitHeight: fixedBodySize == null || !bodyFlow.expandSlots,
                    child: editor.region('body'),
                  );
                },
              ),
            );

            if (activeError != null) {
              exp = Tooltip(message: activeError, child: exp);
            }
            return exp;
          },
        );
      },
    );
  }

  @override
  void dispose() {
    for (final selection in _selections) {
      selection.removeListener(_selectionChanged);
    }
    _binding?.removeListener(_bindingChanged);
    _binding?.dispose();
    _effectiveController.removeListener(_handleExpansibleChanged);
    _internalExpansible.dispose();
    _internalText.dispose();
    _localConfig.dispose();
    super.dispose();
  }
}
