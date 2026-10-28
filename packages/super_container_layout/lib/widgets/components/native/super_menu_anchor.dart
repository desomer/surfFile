import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
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

/// Adapter around Flutter's native [MenuAnchor] widget with editable `header`
/// (anchor trigger) and `body` (popup content) regions and optional two-way
/// boolean JSON repository binding for its open/closed state.
class SuperMenuAnchor extends StatefulWidget {
  static const List<NativePropertyDescriptor> propertyDescriptors =
      superMenuAnchorPropertyDescriptors;

  const SuperMenuAnchor({
    this.id = 'root-menu-anchor',
    this.label = 'Menu',
    this.header,
    this.headers = const [],
    this.body,
    this.bodies = const [],
    this.controller,
    this.initiallyExpanded = false,
    this.headerClickToggles = true,
    this.consumeOutsideTap = false,
    this.toggleIcon,
    this.toggleIconPosition = 'trailing',
    this.alignmentOffset,
    this.style,
    this.clipBehavior = Clip.hardEdge,
    this.onExpansionChanged,
    this.onOpen,
    this.onClose,
    this.slots = const [],
    this.nativeConfig,
    this.onNativeSlotAdded,
    super.key,
  });

  final String id;
  final String label;

  /// Shorthand for a single header (anchor) widget or the first entry in [headers].
  final Widget? header;
  final List<Widget> headers;

  /// Shorthand for a single body (menu content) widget or the first entry in [bodies].
  final Widget? body;
  final List<Widget> bodies;

  /// Optional external [MenuController]. When omitted, an internal
  /// controller is managed and synchronized with [NativeComponentConfig.binding].
  final MenuController? controller;

  /// Default open state when unbound.
  final bool initiallyExpanded;

  /// Whether tapping the header region toggles the menu state at runtime.
  final bool headerClickToggles;

  /// Whether a tap outside that closes the menu is consumed by the tap region.
  final bool consumeOutsideTap;

  /// Optional preset toggle icon style (`'none'`, `'chevron'`, `'arrow'`, `'plusMinus'`, `'triangle'`).
  final String? toggleIcon;

  /// Position of the toggle icon inside the header (`'trailing'` or `'leading'`).
  final String toggleIconPosition;

  /// Optional offset of the menu relative to its anchor.
  final Offset? alignmentOffset;

  /// Optional style passed to Flutter's [MenuAnchor].
  final MenuStyle? style;

  /// Clip behavior passed to Flutter's [MenuAnchor].
  final Clip clipBehavior;

  /// Called whenever the open/closed state changes.
  final ValueChanged<bool>? onExpansionChanged;

  /// Called when the menu opens.
  final VoidCallback? onOpen;

  /// Called when the menu closes.
  final VoidCallback? onClose;

  final List<SlotImplementation> slots;
  final NativeComponentConfig? nativeConfig;
  final NativeSlotAddedCallback? onNativeSlotAdded;

  NativeComponentConfig get _initialConfig =>
      nativeConfig ??
      NativeComponentConfig(
        properties: {
          if (initiallyExpanded) 'initiallyExpanded': true,
          if (!headerClickToggles) 'headerClickToggles': false,
          if (consumeOutsideTap) 'consumeOutsideTap': true,
          if (toggleIcon != null && toggleIcon!.trim() != 'none')
            'toggleIcon': toggleIcon!,
          if (toggleIconPosition.trim() != 'trailing')
            'toggleIconPosition': toggleIconPosition,
          if (alignmentOffset != null && alignmentOffset!.dx != 0)
            'alignmentOffsetX': alignmentOffset!.dx,
          if (alignmentOffset != null && alignmentOffset!.dy != 0)
            'alignmentOffsetY': alignmentOffset!.dy,
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
  State<SuperMenuAnchor> createState() => _SuperMenuAnchorState();
}

class _SuperMenuAnchorState extends State<SuperMenuAnchor> {
  late final _localConfig = ValueNotifier(widget._initialConfig);
  late final MenuController _internalController = MenuController();
  late final TextEditingController _internalText = TextEditingController(
    text: widget.initiallyExpanded ? 'true' : 'false',
  );
  final PageStorageBucket _isolatedPageStorage = PageStorageBucket();
  final GlobalKey _anchorKey = GlobalKey();

  NativeComponentConfig? _previousConfig;
  bool _initialExpansionSynced = false;
  bool _syncingFromBinding = false;
  bool _changingProgrammatically = false;
  bool _isEditing = false;
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

  MenuController get _effectiveController =>
      widget.controller ?? _internalController;

  @override
  void initState() {
    super.initState();
    _lastKnownExpanded = widget.initiallyExpanded;
    if (widget.controller == null && widget.initiallyExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _setExpanded(true, fromBinding: false);
      });
    }
  }

  @override
  void didUpdateWidget(SuperMenuAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _lastKnownExpanded = _effectiveController.isOpen;
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

  void _setExpanded(
    bool expanded, {
    required bool fromBinding,
    bool notifyCallback = true,
  }) {
    void apply() {
      if (!mounted) return;
      if (_effectiveController.isOpen == expanded &&
          _lastKnownExpanded == expanded) {
        return;
      }
      final previousSync = _syncingFromBinding;
      final previousProgrammatic = _changingProgrammatically;
      _syncingFromBinding = fromBinding;
      _changingProgrammatically = true;
      try {
        if (expanded) {
          _effectiveController.open();
        } else {
          _effectiveController.close();
        }
        if (_lastKnownExpanded != expanded) {
          _handleMenuStateChanged(expanded, notifyCallback: notifyCallback);
        }
      } finally {
        _syncingFromBinding = previousSync;
        _changingProgrammatically = previousProgrammatic;
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  void _toggleMenu() {
    _setExpanded(!_lastKnownExpanded, fromBinding: false);
  }

  void _handleMenuOpened() {
    _handleMenuStateChanged(true);
  }

  void _handleMenuClosed() {
    if (_isEditing && !_changingProgrammatically && _lastKnownExpanded) {
      // In edit mode, clicking on portaled EditorOverlay controls or dialogs
      // triggers MenuAnchor's outside TapRegion. Keep the menu open until
      // explicitly toggled via the header action button or configuration.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isEditing || !_lastKnownExpanded) return;
        final previousProgrammatic = _changingProgrammatically;
        _changingProgrammatically = true;
        try {
          if (!_effectiveController.isOpen) {
            _effectiveController.open();
          }
        } finally {
          _changingProgrammatically = previousProgrammatic;
        }
      });
      return;
    }
    _handleMenuStateChanged(false);
  }

  void _handleMenuStateChanged(bool expanded, {bool notifyCallback = true}) {
    final changed = expanded != _lastKnownExpanded;
    _lastKnownExpanded = expanded;
    if (!_syncingFromBinding) {
      _setText(expanded ? 'true' : 'false');
      unawaited(_binding?.flush());
    }
    if (changed && notifyCallback) {
      if (expanded) {
        widget.onOpen?.call();
      } else {
        widget.onClose?.call();
      }
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
        _lastKnownExpanded = desiredInitial;
        _setText(desiredInitial ? 'true' : 'false');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _setExpanded(
            desiredInitial,
            fromBinding: true,
            notifyCallback: false,
          );
        });
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
      if (_lastKnownExpanded != desired) {
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
      emptySize: Size(240, 120),
    ),
  ];

  String _bindingSummary(JsonTextBinding? binding) => binding == null
      ? 'Aucune liaison'
      : '${binding.repositoryId ?? 'Repository hérité'} · ${binding.path}';

  double _resolveMenuWidth() {
    final renderObject = _anchorKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        renderObject.size.width.isFinite &&
        renderObject.size.width > 0) {
      return math.max(renderObject.size.width, 200.0);
    }
    return 240.0;
  }

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
        final effectiveHeaderToggle =
            config.headerClickToggles ?? widget.headerClickToggles;
        final effectiveConsumeOutsideTap =
            config.consumeOutsideTap ?? widget.consumeOutsideTap;
        final effectiveToggleIcon = config.toggleIcon ?? widget.toggleIcon;
        final effectiveToggleIconPosition =
            config.toggleIconPosition ?? widget.toggleIconPosition;
        final effectiveAlignmentOffset =
            config.alignmentOffset ?? widget.alignmentOffset;
        final activeError = _bindingError ?? _binding?.error;

        return NativeComponentEditor(
          label: widget.label,
          menuType: 'Menu',
          menuIcon: Icons.menu_open_outlined,
          keyPrefix: 'super-menu-anchor',
          settingsTitle: 'Configurer le menu',
          editSurface: true,
          config: config,
          onChanged: (value) => controller.value = value,
          registry: registry,
          slots: _slots,
          onSlotAdded: _added,
          regions: _regions,
          propertyDescriptors: SuperMenuAnchor.propertyDescriptors,
          regionActions: (region) {
            if (region != 'header') return const [];
            final expanded = _lastKnownExpanded;
            return [
              IconButton(
                key: ValueKey('super-menu-anchor-toggle-${widget.id}'),
                icon: Icon(
                  expanded ? Icons.unfold_less : Icons.unfold_more,
                  size: 16,
                ),
                tooltip: expanded ? 'Replier le contenu' : 'Déplier le contenu',
                visualDensity: VisualDensity.compact,
                onPressed: _toggleMenu,
              ),
            ];
          },
          settingsControls: (current, update) => [
            ListTile(
              key: const ValueKey('super-menu-anchor-binding'),
              leading: const Icon(Icons.link),
              title: const Text('Liaison état ouvert / fermé'),
              subtitle: Text(_bindingSummary(current.binding)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final result = await showRepositoryBindingDialog(
                  context: context,
                  title: 'Lier l’état ouvert / fermé',
                  keyPrefix: 'super-menu-anchor-binding',
                  pathHint: 'ui.menuOuvert ou clients[?].menuOuvert',
                  helper:
                      'Attribut booléen JSON synchronisé avec l’ouverture du menu.',
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
            _isEditing = editor.editing;
            final canToggleOnHeaderTap =
                !editor.editing && effectiveHeaderToggle && !_unselected;
            final fixedHeaderSize = editor.sizeOf('header');
            final headerFlow = editor.flowOf('header');
            final toggleIconData = resolveNativeToggleIcon(
              effectiveToggleIcon,
              expanded: _lastKnownExpanded,
            );
            Widget headerContent = SlotContentFitScope(
              fitWidth: false,
              fitHeight: fixedHeaderSize == null || !headerFlow.expandSlots,
              child: editor.region('header'),
            );
            if (toggleIconData != null) {
              final isLeading = effectiveToggleIconPosition == 'leading';
              final regionChild = headerContent;
              final iconWidget = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  toggleIconData,
                  key: ValueKey(
                    'super-menu-anchor-header-toggle-icon-${widget.id}',
                  ),
                  size: 20,
                ),
              );
              headerContent = LayoutBuilder(
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
            Widget headerWidget = KeyedSubtree(
              key: _anchorKey,
              child: headerContent,
            );
            if (canToggleOnHeaderTap) {
              headerWidget = MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: ValueKey('super-menu-anchor-header-tap-${widget.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleMenu,
                  child: headerWidget,
                ),
              );
            }

            final fixedBodySize = editor.sizeOf('body');
            final bodyFlow = editor.flowOf('body');
            final menuWidth = _resolveMenuWidth();

            Widget menuWidget = PageStorage(
              bucket: _isolatedPageStorage,
              child: MenuAnchor(
                controller: _effectiveController,
                consumeOutsideTap: effectiveConsumeOutsideTap,
                alignmentOffset: effectiveAlignmentOffset,
                style: widget.style,
                clipBehavior: widget.clipBehavior,
                onOpen: _handleMenuOpened,
                onClose: _handleMenuClosed,
                menuChildren: [
                  _MenuContentIntrinsicShield(
                    fallbackWidth: menuWidth,
                    fallbackHeight: fixedBodySize ?? 120.0,
                    child: SlotContentFitScope(
                      fitWidth: false,
                      fitHeight: fixedBodySize == null || !bodyFlow.expandSlots,
                      child: editor.region('body'),
                    ),
                  ),
                ],
                child: headerWidget,
              ),
            );

            if (activeError != null) {
              menuWidget = Tooltip(message: activeError, child: menuWidget);
            }
            return menuWidget;
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
    _internalText.dispose();
    _localConfig.dispose();
    super.dispose();
  }
}

/// Shields [MenuAnchor]'s internal [IntrinsicWidth] from querying intrinsic
/// dimensions on descendant [LayoutBuilder] widgets inside `editor.region('body')`,
/// while providing bounded width constraints during layout.
class _MenuContentIntrinsicShield extends SingleChildRenderObjectWidget {
  const _MenuContentIntrinsicShield({
    required this.fallbackWidth,
    required this.fallbackHeight,
    required super.child,
  });

  final double fallbackWidth;
  final double fallbackHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMenuContentIntrinsicShield(
        fallbackWidth: fallbackWidth,
        fallbackHeight: fallbackHeight,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMenuContentIntrinsicShield renderObject,
  ) {
    renderObject
      ..fallbackWidth = fallbackWidth
      ..fallbackHeight = fallbackHeight;
  }
}

class _RenderMenuContentIntrinsicShield extends RenderProxyBox {
  _RenderMenuContentIntrinsicShield({
    required double fallbackWidth,
    required double fallbackHeight,
  }) {
    _fallbackWidth = fallbackWidth;
    _fallbackHeight = fallbackHeight;
  }

  late double _fallbackWidth;
  double get fallbackWidth => _fallbackWidth;
  set fallbackWidth(double value) {
    if (_fallbackWidth == value) return;
    _fallbackWidth = value;
    markNeedsLayout();
  }

  late double _fallbackHeight;
  double get fallbackHeight => _fallbackHeight;
  set fallbackHeight(double value) {
    if (_fallbackHeight == value) return;
    _fallbackHeight = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) => _fallbackWidth;

  @override
  double computeMaxIntrinsicWidth(double height) => _fallbackWidth;

  @override
  double computeMinIntrinsicHeight(double width) => _fallbackHeight;

  @override
  double computeMaxIntrinsicHeight(double width) => _fallbackHeight;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size(_fallbackWidth, _fallbackHeight));

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(_fallbackWidth, 0));
      return;
    }
    final effectiveWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.constrainWidth(_fallbackWidth);
    final childConstraints = BoxConstraints(
      minWidth: math.min(constraints.minWidth, effectiveWidth),
      maxWidth: effectiveWidth,
      minHeight: constraints.minHeight,
      maxHeight: constraints.maxHeight,
    );
    child.layout(childConstraints, parentUsesSize: true);
    size = constraints.constrain(child.size);
  }
}
