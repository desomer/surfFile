import 'dart:math' as math;

import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart' show SlotSizeUnit;
import '../../../models/native_component_config.dart';
import '../../../models/native_property_descriptor.dart';
import '../../../models/registry.dart';
import '../../../super_app.dart';
import '../../../theme/appearance.dart';
import '../../editing/components/native_component_editor.dart';
import '../super_layout/slot_implementation.dart';
import '../../editing/slots/editor_slot.dart';

/// AppBar regions map to Flutter properties, never to a SuperLayout.
class SuperAppBar extends StatefulWidget
    implements NativePreferredSizeWidget, SliverCapableWidget {
  static const List<NativePropertyDescriptor> propertyDescriptors =
      superAppBarPropertyDescriptors;

  static const List<NativePropertyDescriptor> sliverPropertyDescriptors =
      superSliverAppBarPropertyDescriptors;

  const SuperAppBar({
    this.id = 'root-appBar',
    this.label = 'ApplicationBar',
    this.title,
    this.leading,
    this.action,
    this.actions = const [],
    this.bottom,
    this.flexibleSpace,
    this.automaticallyImplyLeading = true,
    this.automaticallyImplyActions = true,
    this.toolbarHeight = kToolbarHeight,
    this.pinned = false,
    this.floating = false,
    this.snap = false,
    this.stretch = false,
    this.stretchTriggerOffset = 100.0,
    this.forceElevated = false,
    this.useDefaultSemanticsOrder = true,
    this.expandedHeight,
    this.collapsedHeight,
    this.actionsPadding,
    this.slots = const [],
    this.nativeConfig,
    this.onNativeSlotAdded,
    super.key,
  });

  final String id;
  final String label;
  final Widget? title;
  final Widget? leading;

  /// Compatibility shorthand for the first entry in [actions].
  final Widget? action;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final Widget? flexibleSpace;
  final bool automaticallyImplyLeading;
  final bool automaticallyImplyActions;
  final double toolbarHeight;
  final bool pinned;
  final bool floating;
  final bool snap;
  final bool stretch;
  final double stretchTriggerOffset;
  final bool forceElevated;
  final bool useDefaultSemanticsOrder;
  final double? expandedHeight;
  final double? collapsedHeight;
  final double? actionsPadding;
  final List<SlotImplementation> slots;
  final NativeComponentConfig? nativeConfig;
  final NativeSlotAddedCallback? onNativeSlotAdded;

  NativeComponentConfig get _initialConfig =>
      nativeConfig ??
      NativeComponentConfig(
        properties: {
          if (pinned) 'pinned': true,
          if (floating) 'floating': true,
          if (snap) 'snap': true,
          if (stretch) 'stretch': true,
          if (stretchTriggerOffset != 100.0)
            'stretchTriggerOffset': stretchTriggerOffset,
          if (forceElevated) 'forceElevated': true,
          if (!useDefaultSemanticsOrder) 'useDefaultSemanticsOrder': false,
          'expandedHeight': ?expandedHeight,
          'collapsedHeight': ?collapsedHeight,
          'actionsPadding': ?actionsPadding,
        },
        placements: {
          if (leading != null) 'leading': ['leading'],
          if (title != null) 'title': ['title'],
          if (action != null || actions.isNotEmpty)
            'actions': [
              if (action != null) 'action',
              for (var i = 0; i < actions.length; i++) 'action:$i',
            ],
          if (bottom != null) 'bottom': ['bottom'],
          if (flexibleSpace != null) 'flexibleSpace': ['flexibleSpace'],
        },
      );

  double _toolbarHeight(NativeComponentConfig config) {
    if (config.doubleProperty('toolbarHeight') case final height?) {
      return height;
    }
    final regionHeights = [
      for (final id in const ['leading', 'title', 'actions'])
        if (config.isEnabled(id)) ?config.regionSizeOf(id),
    ];
    if (regionHeights.isNotEmpty) {
      return regionHeights.reduce(math.max);
    }
    return toolbarHeight;
  }

  @override
  Size get preferredSize => Size.fromHeight(
    _toolbarHeight(_initialConfig) + _bottomHeight(_initialConfig),
  );

  double _bottomHeight(
    NativeComponentConfig config, {
    bool editing = false,
    Registry? registry,
  }) {
    final ids = config.slotsOf('bottom');
    if (!config.isEnabled('bottom') || (ids.isEmpty && !editing)) return 0;
    if (ids.length > 1) {
      throw StateError('AppBar.bottom accepts a single slot.');
    }
    if (config.regionSizeOf('bottom') case final regionSize?) {
      return regionSize;
    }
    if (ids.isEmpty) return kToolbarHeight;
    final id = ids.single;
    final constraints = config.slotSizeConstraints[id];
    if (constraints?.preferredHeight case final preferredHeight?
        when preferredHeight.unit == SlotSizeUnit.pixels &&
            preferredHeight.value.isFinite) {
      return preferredHeight.value;
    }
    final type = config.slotTypeOf(id);
    final supplied = slots
        .where((slot) => slot.id == id || slot.id == type)
        .firstOrNull;
    final component = registry?.components.entries
        .where(
          (entry) => type == 'component:${entry.value.slotId ?? entry.key}',
        )
        .firstOrNull
        ?.value;
    final preferred =
        config.slotPreferredSizes[id] ??
        (type == 'bottom'
            ? bottom?.preferredSize
            : supplied?.preferredSize ??
                  component?.createSlot(id).preferredSize);
    final height = preferred?.height;
    return height != null && height.isFinite ? height : kToolbarHeight;
  }

  ValueNotifier<NativeComponentConfig>? _controller(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    return registry?.nativeComponentController(id, fallback: _initialConfig);
  }

  @override
  Listenable? sizeListenable(BuildContext context) => _controller(context);

  @override
  Size preferredSizeIn(BuildContext context) {
    final config =
        _controller(context)?.value ??
        AppearanceScope.of(context)
            .nativeComponent(id, fallback: _initialConfig);
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    return Size.fromHeight(
      _toolbarHeight(config) +
          _bottomHeight(
            config,
            editing: editing,
            registry: SuperApp.maybeOf(context)?.registry,
          ),
    );
  }

  @override
  State<SuperAppBar> createState() => _SuperAppBarState();
}

class _SuperAppBarState extends State<SuperAppBar> {
  late final _localConfig = ValueNotifier(widget._initialConfig);

  bool _usesDefaultNavigation(NativeComponentConfig config) =>
      config.useDefaultNavigation ??
      (widget.automaticallyImplyLeading &&
          config.regions['leading'] != false &&
          config.slotsOf('leading').isEmpty);

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

  Clip? _clipBehavior(NativeComponentConfig config) =>
      switch (config.stringProperty('clipBehavior')) {
        'none' => Clip.none,
        'hardEdge' => Clip.hardEdge,
        'antiAlias' => Clip.antiAlias,
        'antiAliasWithSaveLayer' => Clip.antiAliasWithSaveLayer,
        _ => null,
      };

  SystemUiOverlayStyle? _systemOverlayStyle(NativeComponentConfig config) =>
      switch (config.stringProperty('systemOverlayStyle')) {
        'light' => SystemUiOverlayStyle.light,
        'dark' => SystemUiOverlayStyle.dark,
        _ => null,
      };

  List<NativeRegion> _regions(
    NativeComponentConfig config,
    double effectiveToolbarHeight,
  ) {
    final centerTitle = config.boolProperty('centerTitle') ?? false;
    return [
      NativeRegion(
        'leading',
        'Navigation',
        single: true,
        editableFlow: true,
        emptySize: Size(
          config.doubleProperty('leadingWidth') ?? 56,
          effectiveToolbarHeight,
        ),
      ),
      NativeRegion(
        'title',
        'Titre',
        axis: Axis.horizontal,
        expand: !centerTitle,
        stretch: false,
        editableFlow: true,
        emptySize: Size(double.infinity, effectiveToolbarHeight),
      ),
      NativeRegion(
        'actions',
        'Actions',
        axis: Axis.horizontal,
        expand: false,
        stretch: false,
        editableFlow: true,
        emptySize: Size(96, effectiveToolbarHeight),
      ),
      const NativeRegion('bottom', 'Bas', single: true, editableFlow: true),
      const NativeRegion(
        'flexibleSpace',
        'Espace flexible',
        single: true,
        editableFlow: true,
      ),
    ];
  }

  List<SlotImplementation> _slots(NativeComponentConfig config) {
    final centerTitle = config.boolProperty('centerTitle') ?? false;
    return [
      if (widget.leading case final child?)
        BuilderSlot(id: 'leading', label: 'leading', builder: (_) => child),
      if (widget.title case final child?)
        BuilderSlot(
          id: 'title',
          label: 'title',
          sizing: centerTitle ? SlotSizing.intrinsic : SlotSizing.fill,
          builder: (_) => centerTitle
              ? child
              : Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: child,
                ),
        ),
      if (widget.action case final child?)
        BuilderSlot(
          id: 'action',
          label: 'action',
          sizing: SlotSizing.intrinsic,
          builder: (_) => child,
        ),
      for (final (index, child) in widget.actions.indexed)
        BuilderSlot(
          id: 'action:$index',
          label: 'action ${index + 1}',
          sizing: SlotSizing.intrinsic,
          builder: (_) => child,
        ),
      if (widget.bottom case final child?)
        BuilderSlot(
          id: 'bottom',
          label: 'bottom',
          preferredSize: child.preferredSize,
          builder: (_) => child,
        ),
      if (widget.flexibleSpace case final child?)
        BuilderSlot(
          id: 'flexibleSpace',
          label: 'flexibleSpace',
          builder: (_) => child,
        ),
      ...widget.slots,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final controller = widget._controller(context) ?? _localConfig;
    final isSliver = SliverSlotScope.isSliver(context);
    final sliverPreferredSize = isSliver
        ? SliverSlotScope.preferredSizeOf(context)
        : null;
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    return ValueListenableBuilder<NativeComponentConfig>(
      valueListenable: controller,
      builder: (context, config, _) {
        final baseToolbarHeight = widget._toolbarHeight(config);
        final bottomHeight = widget._bottomHeight(
          config,
          editing: editing,
          registry: registry,
        );
        double resolveToolbarHeight(double? allocatedHeight) {
          if (allocatedHeight == null || !allocatedHeight.isFinite) {
            return baseToolbarHeight;
          }
          final resolved = allocatedHeight - bottomHeight;
          return resolved > 0 ? resolved : baseToolbarHeight;
        }

        Widget buildEditor(double effectiveToolbarHeight) =>
            NativeComponentEditor(
              label: widget.label,
              menuType: 'AppBar',
              keyPrefix: 'super-app-bar',
              settingsTitle: 'Configurer la barre',
              editSurface: true,
              config: config,
              onChanged: (value) => controller.value = value,
              regions: _regions(config, effectiveToolbarHeight),
              slots: _slots(config),
              registry: registry,
              propertyDescriptors: isSliver
                  ? const [
                      ...SuperAppBar.sliverPropertyDescriptors,
                      ...SuperAppBar.propertyDescriptors,
                    ]
                  : SuperAppBar.propertyDescriptors,
              isPropertyAvailable: (_, descriptor) =>
                  !isSliver ||
                  (descriptor.id != 'toolbarOpacity' &&
                      descriptor.id != 'bottomOpacity'),
              isRegionAvailable: (config, region) =>
                  region != 'leading' || !_usesDefaultNavigation(config),
              settingsControls: (config, onChanged) => [
                SwitchListTile(
                  key: const ValueKey('super-app-bar-default-navigation'),
                  title: const Text('Bouton de navigation par défaut'),
                  subtitle: const Text(
                    'Menu du drawer ou bouton Retour natif. Remplace la zone Navigation.',
                  ),
                  value: _usesDefaultNavigation(config),
                  onChanged: (value) =>
                      onChanged(config.withDefaultNavigation(value)),
                ),
              ],
              onSlotAdded: _added,
              builder: (context, editor) {
                final actions = editor.slotsFor('actions');
                Widget toolbarRegion(
                  String id, {
                  SlotImplementation? item,
                  bool showBadge = true,
                }) => SliverSlotScope(
                  enabled: false,
                  child: SizedBox(
                    height: effectiveToolbarHeight,
                    child: editor.region(id, item: item, showBadge: showBadge),
                  ),
                );
          final leadingWidget =
              !_usesDefaultNavigation(config) && editor.visible('leading')
              ? toolbarRegion('leading')
              : null;
          final titleWidget = editor.visible('title')
              ? toolbarRegion('title')
              : null;
          final actionsWidgets = !editor.visible('actions')
              ? (config.regions['actions'] == false ? const <Widget>[] : null)
              : <Widget>[
                  if (actions.isEmpty)
                    SizedBox(width: 96, child: toolbarRegion('actions'))
                  else if (!config.regionFlowOf('actions').isDefault ||
                      config.regionAxisOf('actions') != null)
                    toolbarRegion('actions')
                  else
                    for (final (index, slot) in actions.indexed)
                      toolbarRegion(
                        'actions',
                        item: slot,
                        showBadge: index == 0,
                      ),
                ];
          final bottomWidget = editor.visible('bottom')
              ? PreferredSize(
                  preferredSize: Size.fromHeight(bottomHeight),
                  child: SliverSlotScope(
                    enabled: false,
                    child: SizedBox(
                      height: bottomHeight,
                      child: editor.region('bottom'),
                    ),
                  ),
                )
              : null;
          final flexibleSpaceWidget = editor.visible('flexibleSpace')
              ? SliverSlotScope(
                  enabled: false,
                  child: editor.region('flexibleSpace'),
                )
              : null;

          if (isSliver) {
            final effectiveFloating =
                config.boolProperty('floating') ?? widget.floating;
            final effectivePinned =
                config.boolProperty('pinned') ?? widget.pinned;
            final effectiveSnap =
                (config.boolProperty('snap') ?? widget.snap) &&
                effectiveFloating;
            final effectiveStretch =
                config.boolProperty('stretch') ?? widget.stretch;
            final effectiveStretchTriggerOffset = math.max(
              1.0,
              config.doubleProperty('stretchTriggerOffset') ??
                  widget.stretchTriggerOffset,
            );
            final effectiveForceElevated =
                config.boolProperty('forceElevated') ?? widget.forceElevated;
            final effectiveUseDefaultSemanticsOrder =
                config.boolProperty('useDefaultSemanticsOrder') ??
                widget.useDefaultSemanticsOrder;
            final rawActionsPadding =
                config.doubleProperty('actionsPadding') ??
                widget.actionsPadding;
            final effectiveActionsPadding = rawActionsPadding != null
                ? EdgeInsets.symmetric(horizontal: rawActionsPadding)
                : null;
            final rawCollapsed =
                config.doubleProperty('collapsedHeight') ??
                widget.collapsedHeight;
            final effectiveCollapsed = rawCollapsed != null
                ? math.max(rawCollapsed, effectiveToolbarHeight)
                : null;
            final effectiveExpanded =
                config.doubleProperty('expandedHeight') ??
                widget.expandedHeight;
            return SliverAppBar(
              toolbarHeight: effectiveToolbarHeight,
              leadingWidth: config.doubleProperty('leadingWidth'),
              titleSpacing: config.doubleProperty('titleSpacing') ?? 0,
              centerTitle: config.boolProperty('centerTitle'),
              backgroundColor: config.colorProperty('backgroundColor'),
              foregroundColor: config.colorProperty('foregroundColor'),
              surfaceTintColor: config.colorProperty('surfaceTintColor'),
              shadowColor: config.colorProperty('shadowColor'),
              elevation: config.doubleProperty('elevation'),
              scrolledUnderElevation: config.doubleProperty(
                'scrolledUnderElevation',
              ),
              forceElevated: effectiveForceElevated,
              forceMaterialTransparency:
                  config.boolProperty('forceMaterialTransparency') ?? false,
              shape: config.shapeBorderProperty('shape'),
              primary: config.boolProperty('primary') ?? true,
              excludeHeaderSemantics:
                  config.boolProperty('excludeHeaderSemantics') ?? false,
              useDefaultSemanticsOrder: effectiveUseDefaultSemanticsOrder,
              clipBehavior: _clipBehavior(config),
              systemOverlayStyle: _systemOverlayStyle(config),
              automaticallyImplyLeading: _usesDefaultNavigation(config),
              automaticallyImplyActions: widget.automaticallyImplyActions,
              actionsPadding: effectiveActionsPadding,
              pinned: effectivePinned,
              floating: effectiveFloating,
              snap: effectiveSnap,
              stretch: effectiveStretch,
              stretchTriggerOffset: effectiveStretchTriggerOffset,
              expandedHeight: effectiveExpanded,
              collapsedHeight: effectiveCollapsed,
              leading: leadingWidget,
              title: titleWidget,
              actions: actionsWidgets,
              bottom: bottomWidget,
              flexibleSpace: flexibleSpaceWidget,
            );
          }

          return AppBar(
            toolbarHeight: effectiveToolbarHeight,
            leadingWidth: config.doubleProperty('leadingWidth'),
            titleSpacing: config.doubleProperty('titleSpacing') ?? 0,
            centerTitle: config.boolProperty('centerTitle'),
            backgroundColor: config.colorProperty('backgroundColor'),
            foregroundColor: config.colorProperty('foregroundColor'),
            surfaceTintColor: config.colorProperty('surfaceTintColor'),
            shadowColor: config.colorProperty('shadowColor'),
            elevation: config.doubleProperty('elevation'),
            scrolledUnderElevation: config.doubleProperty(
              'scrolledUnderElevation',
            ),
            forceMaterialTransparency:
                config.boolProperty('forceMaterialTransparency') ?? false,
            shape: config.shapeBorderProperty('shape'),
            toolbarOpacity: config.doubleProperty('toolbarOpacity') ?? 1.0,
            bottomOpacity: config.doubleProperty('bottomOpacity') ?? 1.0,
            primary: config.boolProperty('primary') ?? true,
            excludeHeaderSemantics:
                config.boolProperty('excludeHeaderSemantics') ?? false,
            clipBehavior: _clipBehavior(config),
            systemOverlayStyle: _systemOverlayStyle(config),
            automaticallyImplyLeading: _usesDefaultNavigation(config),
            automaticallyImplyActions:
                widget.automaticallyImplyActions &&
                config.regions['actions'] != false,
            leading: leadingWidget,
            title: titleWidget,
            actions: actionsWidgets,
            bottom: bottomWidget,
            flexibleSpace: flexibleSpaceWidget,
          );
        },
      );
        if (isSliver) {
          return buildEditor(resolveToolbarHeight(sliverPreferredSize?.height));
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final targetHeight = constraints.hasTightHeight
                ? constraints.maxHeight
                : (baseToolbarHeight + bottomHeight).clamp(
                    constraints.minHeight,
                    constraints.maxHeight,
                  );
            return buildEditor(resolveToolbarHeight(targetHeight));
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _localConfig.dispose();
    super.dispose();
  }
}
