import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../../models/json_syntax.dart';
import '../../../models/native_component_config.dart';
import '../../../models/native_property_descriptor.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/component_tag_filter.dart';
import '../../../models/registry.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import 'native_shape_editor.dart';
import '../addition/component_add_wizard.dart';
import '../addition/insertion_plan.dart';
import '../history/editor_history.dart';
import '../slots/slot_removal.dart';
import '../slots/slot_wrapping.dart';
import '../slots/provided_slot_scope.dart';
import '../overlay/editor_overlay.dart';
import '../overlay/editor_zone_badge.dart';
import '../slots/slot_size_editor.dart';
import '../../components/super_layout/layout_selection.dart';
import '../../components/super_layout/slot_implementation.dart';
import '../../components/super_layout/super_layout.dart'
    show ZoneFlowSettingsEditor;
import '../../components/super_layout/zone_axis_button.dart';
import '../slots/editor_slot.dart';
import '../slots/editor_selection_region.dart';

/// Lets a native parent track a child's edited preferred height.
abstract interface class NativePreferredSizeWidget
    implements PreferredSizeWidget {
  Listenable? sizeListenable(BuildContext context);
  Size preferredSizeIn(BuildContext context);
}

/// Retains a native widget's reactive size through slot composition.
class NativeWidgetSlot extends SlotImplementation
    implements NativePreferredSizeWidget {
  const NativeWidgetSlot({
    required super.id,
    required super.label,
    required this.child,
    super.sizing = SlotSizing.intrinsic,
    super.tags,
    super.menuIcon,
    super.key,
  });

  final NativePreferredSizeWidget child;
  @override
  bool get isSliverSlot => super.isSliverSlot || isSliverWidget(child);
  @override
  bool canRenderAsSliver(BuildContext context) => isSliverSlot;
  @override
  Size get preferredSize => child.preferredSize;
  @override
  Size preferredSizeIn(BuildContext context) => child.preferredSizeIn(context);
  @override
  Listenable? sizeListenable(BuildContext context) =>
      child.sizeListenable(context);
  @override
  Widget buildSlot(BuildContext context) => child;
}

/// [InstanceSlot] keeping the preferred size contract of a native slot.
class _NativeInstanceSlot extends InstanceSlot
    implements NativePreferredSizeWidget {
  _NativeInstanceSlot(
    super.component, {
    required super.label,
    required super.onRename,
    required super.onRestore,
    required super.overridden,
  });

  NativePreferredSizeWidget get _native =>
      component as NativePreferredSizeWidget;
  @override
  Size get preferredSize => _native.preferredSize;
  @override
  Size preferredSizeIn(BuildContext context) =>
      _native.preferredSizeIn(context);
  @override
  Listenable? sizeListenable(BuildContext context) =>
      _native.sizeListenable(context);
}

typedef NativeSlotAddedCallback = NativeComponentConfig Function(
  NativeComponentConfig config,
  String region,
  String id,
  SlotImplementation slot,
  List<SlotImplementation> siblings,
);

/// A native property's editing contract, independent of persisted placements.
class NativeRegion {
  const NativeRegion(
    this.id,
    this.label, {
    this.required = false,
    this.single = false,
    this.axis = Axis.vertical,
    this.expand = true,
    this.stretch = true,
    this.editableFlow = false,
    this.emptySize = const Size(double.infinity, kToolbarHeight),
    this.fillSize,
    this.tagFilter = const ComponentTagFilter(),
    this.menuDestination = EditorMenuDestination.configuration,
  });

  final String id;
  final String label;
  final bool required;
  final bool single;
  final Axis axis;
  final bool expand;
  final bool stretch;
  final bool editableFlow;
  final Size emptySize;
  final Size? fillSize;
  final ComponentTagFilter tagFilter;
  final EditorMenuDestination menuDestination;
}

/// Shared selection, menus, switches and slot catalog for native adapters.
class NativeComponentEditor extends StatefulWidget {
  const NativeComponentEditor({
    this.id,
    required this.label,
    required this.config,
    required this.onChanged,
    required this.regions,
    required this.slots,
    required this.builder,
    required this.keyPrefix,
    required this.settingsTitle,
    this.registry,
    this.onConfigured,
    this.onConfigure,
    this.onEditRegion,
    this.onRegionSelected,
    this.regionActions,
    this.onSlotAdded,
    this.onSlotRemoved,
    this.editSurface = false,
    this.showRegionInPath = true,
    this.resolveSlotLabel,
    this.isSlotSelectable,
    this.slotContextFor,
    this.menuIcon,
    this.menuType,
    this.menuTooltip,
    this.regionTooltip,
    this.settingsControls,
    this.propertyDescriptors = const [],
    this.isRegionAvailable,
    this.isPropertyAvailable,
    super.key,
  });

  final String? id;
  final String label;
  final NativeComponentConfig config;
  final ValueChanged<NativeComponentConfig> onChanged;
  final List<NativeRegion> regions;
  final List<SlotImplementation> slots;
  final Widget Function(BuildContext, NativeComponentEditorState) builder;
  final String keyPrefix;
  final String settingsTitle;
  final Registry? registry;
  final ValueChanged<Set<String>>? onConfigured;
  final Future<void> Function()? onConfigure;
  final Future<void> Function(String region)? onEditRegion;
  final ValueChanged<String?>? onRegionSelected;
  final List<Widget> Function(String region)? regionActions;
  final NativeSlotAddedCallback? onSlotAdded;
  final Future<void> Function(String region, SlotImplementation slot)?
  onSlotRemoved;
  final bool editSurface;
  final bool showRegionInPath;
  final String? Function(SlotImplementation slot)? resolveSlotLabel;
  final bool Function(SlotImplementation slot)? isSlotSelectable;
  final BuildContext? Function(SlotImplementation slot)? slotContextFor;
  final IconData? menuIcon;
  final String? menuType;
  final String? Function(NativeComponentConfig config)? menuTooltip;
  final String? Function(NativeComponentConfig config, String region)?
  regionTooltip;
  final List<Widget> Function(
    NativeComponentConfig config,
    ValueChanged<NativeComponentConfig> onChanged,
  )?
  settingsControls;
  final List<NativePropertyDescriptor> propertyDescriptors;
  final bool Function(NativeComponentConfig config, String region)?
  isRegionAvailable;
  final bool Function(
    NativeComponentConfig config,
    NativePropertyDescriptor descriptor,
  )?
  isPropertyAvailable;

  @override
  State<NativeComponentEditor> createState() => NativeComponentEditorState();
}

class NativeComponentEditorState extends State<NativeComponentEditor> {
  final _keys = <String, GlobalKey>{};
  final _slotKeys = <String, GlobalKey>{};
  ValueNotifier<bool>? _editMode;
  String? _selected;
  String? _selectedSlot;
  bool _active = false;
  final _hoveredRegionScopes = ValueNotifier<Set<Object>>({});
  List<String> _path = const [];
  Size _layoutSize = Size.zero;
  final _config = ValueNotifier<NativeComponentConfig>(NativeComponentConfig());

  bool get editing => _editMode?.value ?? false;
  List<String> get componentPath => _path;
  bool isSlotSelected(String region, String slotId) =>
      _active && _selected == region && _selectedSlot == slotId;

  String get _componentLabel {
    final instance = editorComponentLabelOf(context);
    return (instance?.overridden ?? false) ? instance!.label : widget.label;
  }

  String? get _effectiveComponentId {
    if (widget.id != null && widget.id!.isNotEmpty) return widget.id!;
    final fromLabel = editorComponentLabelOf(context)?.id;
    if (fromLabel != null && fromLabel.isNotEmpty) return fromLabel;
    final registry = widget.registry;
    if (registry != null) {
      final current = _config.value;
      for (final entry in registry.nativeComponentConfigById.entries) {
        if (identical(entry.value.value, current) ||
            entry.value.value == current) {
          return entry.key;
        }
      }
      if (registry.nativeComponentConfigById.length == 1) {
        return registry.nativeComponentConfigById.keys.single;
      }
    }
    return null;
  }

  String _resolvedSlotLabel(SlotImplementation slot) =>
      widget.resolveSlotLabel?.call(slot) ?? slot.label;

  String _resolvedSlotId(SlotImplementation slot, BuildContext? slotCtx) {
    if (slot.id == '__provided-child') {
      final resolved = EditorSlotState.resolveFromContext(
        slotCtx,
      )?.effectiveComponentId;
      if (resolved != null && resolved.isNotEmpty) return resolved;
    }
    return slot.id;
  }

  bool _canSelectSlot(SlotImplementation slot) =>
      !slot.id.startsWith('scaffold:') &&
      (widget.isSlotSelectable?.call(slot) ?? true);

  BuildContext? _regionContext(String? id) => id == null
      ? null
      : (_keys[id]?.currentContext ?? _keys['$id:sliver']?.currentContext);

  BuildContext? _slotContext(String slotId, [String? region]) =>
      _slotKeys[slotId]?.currentContext ??
      _slotKeys['$slotId:sliver']?.currentContext ??
      (region == null ? null : _keys['$region:$slotId']?.currentContext);

  NativeRegion definition(String id) =>
      widget.regions.firstWhere((region) => region.id == id);
  Axis axisOf(String id) =>
      widget.config.regionAxisOf(id) ?? definition(id).axis;
  ZoneFlowConfig flowOf(String id) => widget.config.regionFlowOf(id);
  double? sizeOf(String id) => widget.config.regionSizeOf(id);
  bool enabled(String id) =>
      (widget.isRegionAvailable?.call(widget.config, id) ?? true) &&
      (definition(id).required || widget.config.isEnabled(id));
  bool visible(String id) =>
      enabled(id) && (editing || slotsFor(id).isNotEmpty);

  Size? preferredSizeFor(SlotImplementation slot) {
    final base = widget.config.slotPreferredSizes.containsKey(slot.id)
        ? widget.config.slotPreferredSizes[slot.id]
        : switch (slot) {
            NativePreferredSizeWidget native => native.preferredSizeIn(context),
            _ => slot.preferredSize,
          };
    final configured = widget.config.slotSizeConstraints[slot.id];
    if (configured == null || !configured.hasSizeConstraints) {
      return base;
    }
    final media = MediaQuery.maybeSizeOf(context) ?? Size.zero;
    final basisWidth = _layoutSize.width > 0 ? _layoutSize.width : media.width;
    final basisHeight = _layoutSize.height > 0
        ? _layoutSize.height
        : media.height;
    double? resolveDimension(
      SlotDimension? preferred,
      SlotDimension? min,
      SlotDimension? max,
      double basis,
      double? fallback,
    ) {
      var value = preferred?.resolve(basis) ?? fallback;
      final minVal = min?.resolve(basis);
      final maxVal = max?.resolve(basis);
      if (value != null && value.isFinite) {
        if (minVal != null) value = math.max(value, minVal);
        if (maxVal != null) value = math.min(value, maxVal);
        return value;
      }
      if (minVal != null) {
        return maxVal != null ? math.min(minVal, maxVal) : minVal;
      }
      return value;
    }

    final width = resolveDimension(
      configured.preferredWidth,
      configured.minWidth,
      configured.maxWidth,
      basisWidth,
      base?.width,
    );
    final height = resolveDimension(
      configured.preferredHeight,
      configured.minHeight,
      configured.maxHeight,
      basisHeight,
      base?.height,
    );
    if (width == null && height == null) return base;
    return Size(width ?? double.infinity, height ?? double.infinity);
  }

  @override
  void initState() {
    super.initState();
    _config.value = widget.config;
  }

  @override
  void didUpdateWidget(NativeComponentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _config.value = widget.config;
    if (_selectedSlot != null &&
        (_selected == null ||
            !widget.config.slotsOf(_selected!).contains(_selectedSlot))) {
      _selectedSlot = null;
    }
    if (_selected != null && !enabled(_selected!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selected != null && !enabled(_selected!)) _clear();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = LayoutSelectionScope.of(context);
    final label = _componentLabel;
    _path = !widget.showRegionInPath && (scope?.isSlotScope ?? false)
        ? scope!.path
        : [...?scope?.path, label];
    final mode = StyleEditScope.controllerOf(context);
    final modeChanged = mode != _editMode;
    if (modeChanged) {
      _editMode?.removeListener(_editingChanged);
      _editMode = mode;
      _editMode?.addListener(_editingChanged);
    }
    LayoutSelection.register(
      this,
      _path,
      (targetLabel) {
        if (!widget.showRegionInPath) {
          if (targetLabel == null) {
            select(null);
            return;
          }
          final region = widget.regions.first.id;
          final slots = slotsFor(region);
          final slot = slots
              .where((s) => _resolvedSlotLabel(s) == targetLabel)
              .firstOrNull;
          if (slot != null) {
            selectSlot(region, slot);
          } else {
            select(null);
          }
          return;
        }
        select(
          widget.regions
              .where((region) => region.label == targetLabel)
              .firstOrNull
              ?.id,
        );
      },
      id: _effectiveComponentId,
      parent: scope?.owner,
      delegateToParent: !widget.showRegionInPath && scope != null,
      selectedSlotId: () => _selectedSlot,
      selectSlot: widget.showRegionInPath
          ? (slotLabel) {
              final region = _selected;
              if (!mounted || region == null) return;
              final slots = slotsFor(region);
              final slot =
                  slots
                      .where(
                        (s) =>
                            s.id == _selectedSlot &&
                            _resolvedSlotLabel(s) == slotLabel,
                      )
                      .firstOrNull ??
                  slots
                      .where((s) => _resolvedSlotLabel(s) == slotLabel)
                      .firstOrNull;
              if (slot != null) selectSlot(region, slot);
            }
          : null,
      onDeselect: _clear,
      onContextMenu: (position) => EditorSlotState.openMenuFromContext(
        !widget.editSurface && widget.showRegionInPath
            ? (_regionContext(_selected) ?? _regionContext('body') ?? context)
            : context,
        position,
      ),
      targetContext: () => !widget.editSurface && widget.showRegionInPath
          ? (_regionContext(_selected) ?? _regionContext('body') ?? context)
          : context,
      treeBuilder: () {
        if (!widget.showRegionInPath) {
          final regionId = widget.regions.first.id;
          final currentSlots = slotsFor(regionId);
          return [
            for (final slot in currentSlots)
              if (_canSelectSlot(slot))
                () {
                  final sLabel = _resolvedSlotLabel(slot);
                  final slotPath = [..._path, sLabel];
                  void selectThisSlot() => selectSlot(regionId, slot);
                  final slotCtx =
                      widget.slotContextFor?.call(slot) ??
                      _slotContext(slot.id, regionId) ??
                      _regionContext(regionId);
                  return LayoutSelectionNode(
                    id: _resolvedSlotId(slot, slotCtx),
                    label: sLabel,
                    path: slotPath,
                    icon: slot.menuIcon,
                    onSelect: selectThisSlot,
                    onContextMenu: (position) =>
                        EditorSlotState.openMenuFromContext(slotCtx, position),
                    targetContext: () =>
                        widget.slotContextFor?.call(slot) ??
                        _slotContext(slot.id, regionId) ??
                        _regionContext(regionId),
                    children: LayoutSelection.childrenFromContext(
                      slotCtx,
                      slotPath,
                      selectThisSlot,
                      ignoreOwner: this,
                    ),
                  );
                }(),
          ];
        }
        return [
          for (final region in widget.regions)
            if (visible(region.id))
              () {
                final regionPath = [..._path, region.label];
                final currentSlots = slotsFor(region.id);
                final slotNodes = <LayoutSelectionNode>[];
                for (final slot in currentSlots) {
                  final slotCtx =
                      widget.slotContextFor?.call(slot) ??
                      _slotContext(slot.id, region.id);
                  if (_canSelectSlot(slot)) {
                    final sLabel = _resolvedSlotLabel(slot);
                    final slotPath = [...regionPath, sLabel];
                    void selectThisSlot() => selectSlot(region.id, slot);
                    slotNodes.add(
                      LayoutSelectionNode(
                        id: _resolvedSlotId(slot, slotCtx),
                        label: sLabel,
                        path: slotPath,
                        icon: slot.menuIcon,
                        onSelect: selectThisSlot,
                        onContextMenu: (position) =>
                            EditorSlotState.openMenuFromContext(
                              slotCtx,
                              position,
                            ),
                        targetContext: () =>
                            widget.slotContextFor?.call(slot) ??
                            _slotContext(slot.id, region.id),
                        children: LayoutSelection.childrenFromContext(
                          slotCtx,
                          slotPath,
                          selectThisSlot,
                          ignoreOwner: this,
                        ),
                      ),
                    );
                  } else {
                    slotNodes.addAll(
                      LayoutSelection.childrenFromContext(
                        slotCtx ?? _regionContext(region.id),
                        regionPath,
                        () => select(region.id),
                        ignoreOwner: this,
                      ),
                    );
                  }
                }
                return LayoutSelectionNode(
                  id: 'region:${region.id}',
                  label: region.label,
                  path: regionPath,
                  icon: EditorSlot.zoneMenuIcon,
                  onSelect: () => select(region.id),
                  onContextMenu: (position) =>
                      EditorSlotState.openMenuFromContext(
                        _regionContext(region.id),
                        position,
                      ),
                  targetContext: () => _regionContext(region.id),
                  children: slotNodes,
                );
              }(),
        ];
      },
    );
    if (modeChanged &&
        editing &&
        widget.showRegionInPath &&
        scope == null &&
        !_active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            editing &&
            !_active &&
            LayoutSelection.path.value.isEmpty) {
          select(null);
        }
      });
    }
  }

  void _editingChanged() {
    if (editing &&
        widget.showRegionInPath &&
        LayoutSelectionScope.of(context) == null) {
      select(null);
    } else {
      _clear();
    }
  }

  void _clear() {
    if (!mounted) return;
    setState(() {
      _active = false;
      _selected = null;
      _selectedSlot = null;
      _hoveredRegionScopes.value = {};
    });
    LayoutSelection.report(this, const []);
  }

  void select(String? id, [BuildContext? target]) {
    if (!mounted) return;
    LayoutSelection.activate(this);
    setState(() {
      _active = true;
      _selected = id;
      _selectedSlot = null;
    });
    widget.onRegionSelected?.call(id);
    LayoutSelection.report(
      this,
      [
        ..._path,
        if (id != null && widget.showRegionInPath) definition(id).label,
      ],
      axis: id != null && definition(id).editableFlow
          ? _axisActionFor(id)
          : null,
      clear: _clear,
      focusContext: target ?? _regionContext(id) ?? context,
    );
  }

  LayoutAxisAction _axisActionFor(String id) {
    final spec = definition(id);
    final currentAxis = axisOf(id);
    final fixedSize = sizeOf(id);
    final defaultSize = spec.emptySize.height.isFinite
        ? spec.emptySize.height
        : 100.0;
    final hasNaturalHeight = currentAxis == Axis.vertical
        ? !spec.expand
        : !spec.stretch;
    return LayoutAxisAction(
      zoneLabel: spec.label,
      axis: currentAxis,
      onToggle: () {
        select(id);
        _update(
          _config.value.withRegionAxis(
            id,
            currentAxis == Axis.horizontal ? Axis.vertical : Axis.horizontal,
            defaultAxis: spec.axis,
          ),
        );
      },
      onEditFlow: () => _openRegionFlowEditor(id),
      flowTooltip: formatZoneFlowTooltip(
        zoneLabel: spec.label,
        axis: currentAxis,
        flow: flowOf(id),
        isSide: true,
        sizeAxis: hasNaturalHeight ? Axis.vertical : null,
        autoSize: fixedSize == null,
        size: fixedSize ?? defaultSize,
      ),
    );
  }

  String _componentTooltip() {
    final config = _config.value;
    if (widget.menuTooltip?.call(config) case final custom?) return custom;
    return formatNativeComponentTooltip(
      title: _componentLabel,
      config: config,
      regions: [
        for (final region in widget.regions)
          if (widget.isRegionAvailable?.call(config, region.id) ?? true)
            (
              label: region.label,
              count: slotsFor(region.id).length,
              enabled: enabled(region.id),
            ),
      ],
      propertyDescriptors: [
        for (final descriptor in widget.propertyDescriptors)
          if (widget.isPropertyAvailable?.call(config, descriptor) ?? true)
            descriptor,
      ],
    );
  }

  String _regionTooltip(String id) {
    final config = _config.value;
    if (widget.regionTooltip?.call(config, id) case final custom?) {
      return custom;
    }
    final spec = definition(id);
    final zoneSummary = spec.editableFlow
        ? _axisActionFor(id).flowTooltip!
        : [
            'Zone ${spec.label} ($_componentLabel)',
            [
              'Direction : ${axisOf(id) == Axis.horizontal ? 'Ligne (Row)' : 'Colonne (Column)'}',
              if (spec.single) 'Élément unique',
            ].join(' · '),
            'Éléments : ${slotsFor(id).length}',
          ].join('\n');
    if (!widget.editSurface && widget.onEditRegion == null) {
      final parentLines = _componentTooltip().split('\n').skip(1);
      if (parentLines.isNotEmpty) {
        return [zoneSummary, ...parentLines].join('\n');
      }
    }
    return zoneSummary;
  }

  EditorDimensionDelegate _buildRegionFlowDelegate(
    String id, {
    NativeComponentConfig? initialOverride,
  }) {
    final spec = definition(id);
    final initial = initialOverride ?? _config.value;
    return _NativeRegionFlowDimensionDelegate(
      title: 'Flux de la zone : ${spec.label}',
      onRestore: () {
        if (mounted) _update(initial);
      },
      onReset: () {
        _update(
          _config.value
              .withRegionAxis(id, spec.axis, defaultAxis: spec.axis)
              .withRegionFlow(id, const ZoneFlowConfig())
              .withRegionSize(id, null),
        );
      },
      builder: (context) => ListenableBuilder(
        listenable: _config,
        builder: (context, _) {
          final current = _config.value;
          final defaultSize = spec.emptySize.height.isFinite
              ? spec.emptySize.height
              : 100.0;
          final fixedSize = current.regionSizeOf(id);
          final effectiveAxis = current.regionAxisOf(id) ?? spec.axis;
          final hasNaturalHeight = effectiveAxis == Axis.vertical
              ? !spec.expand
              : !spec.stretch;
          return ZoneFlowSettingsEditor(
            keyPrefix: '${widget.keyPrefix}-flow-dialog-$id',
            axis: effectiveAxis,
            flow: current.regionFlowOf(id),
            isSide: true,
            sizeAxis: hasNaturalHeight ? Axis.vertical : null,
            autoSize: fixedSize == null,
            size: fixedSize ?? defaultSize,
            onAutoSizeChanged: (auto) => _update(
              current.withRegionSize(
                id,
                auto ? null : (fixedSize ?? defaultSize),
              ),
            ),
            onSizeChanged: (value) =>
                _update(current.withRegionSize(id, value)),
            onAxisChanged: (axis) => _update(
              current.withRegionAxis(id, axis, defaultAxis: spec.axis),
            ),
            onFlowChanged: (flow) => _update(current.withRegionFlow(id, flow)),
          );
        },
      ),
    );
  }

  Future<void> _openRegionFlowEditor(String id) async {
    if (widget.onEditRegion != null) {
      await EditorWizardNavigation.openWithTab(
        EditorWizardTab.dimensions,
        () => widget.onEditRegion!(id),
        delegate: _buildRegionFlowDelegate(id),
      );
      return;
    }
    await configure(regionId: id, initialTab: EditorWizardTab.dimensions);
  }

  void selectSlot(
    String region,
    SlotImplementation slot, [
    BuildContext? target,
  ]) {
    if (!mounted) return;
    if (!_canSelectSlot(slot)) {
      if (widget.showRegionInPath) select(region, target);
      return;
    }
    LayoutSelection.activate(this);
    setState(() {
      _active = true;
      _selected = region;
      _selectedSlot = slot.id;
    });
    widget.onRegionSelected?.call(region);
    final customSlotCtx = widget.slotContextFor?.call(slot);
    final resolvedCustomCtx = customSlotCtx == null
        ? null
        : (EditorSlotState.resolveFromContext(customSlotCtx)?.context ??
              customSlotCtx);
    LayoutSelection.report(
      this,
      [
        ..._path,
        if (widget.showRegionInPath) definition(region).label,
        _resolvedSlotLabel(slot),
      ],
      clear: _clear,
      focusContext:
          target ??
          resolvedCustomCtx ??
          _slotContext(slot.id, region) ??
          _regionContext(region) ??
          context,
    );
  }

  void _toggleSlot(String region, SlotImplementation slot) {
    if (_active && _selected == region && _selectedSlot == slot.id) {
      select(region);
    } else {
      selectSlot(region, slot);
    }
  }

  void _selectSlot(String region, SlotImplementation slot) {
    selectSlot(region, slot);
  }

  void _update(NativeComponentConfig config) {
    if (identical(config, _config.value)) return;
    _validate(config);
    for (final region in widget.regions) {
      for (final id in config.slotsOf(region.id)) {
        final type = config.slotTypeOf(id);
        final unchanged =
            _config.value.slotsOf(region.id).contains(id) &&
            _config.value.slotTypeOf(id) == type;
        if (!unchanged &&
            !region.tagFilter.accepts(_tagsForType(type, id: id))) {
          _reportTagRejection(region.id);
          return;
        }
      }
    }
    _config.value = config;
    widget.onChanged(config);
  }

  void _reportTagRejection(String region) {
    final message =
        'Composant incompatible avec la zone ${definition(region).label}.';
    debugPrint(message);
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _validate(NativeComponentConfig config) {
    final ids = widget.regions.map((region) => region.id).toSet();
    if (config.placements.keys.any((id) => !ids.contains(id)) ||
        config.regions.keys.any((id) => !ids.contains(id)) ||
        config.regionAxes.keys.any((id) => !ids.contains(id)) ||
        config.regionFlows.keys.any((id) => !ids.contains(id)) ||
        config.regionSizes.keys.any((id) => !ids.contains(id))) {
      throw StateError('Unknown region in ${widget.label}.');
    }
    for (final region in widget.regions) {
      if ((region.required && config.regions[region.id] == false) ||
          (region.single && config.slotsOf(region.id).length > 1)) {
        throw StateError('Invalid native region ${widget.label}.${region.id}.');
      }
    }
  }

  Future<void> configure({
    String? regionId,
    EditorWizardTab? initialTab,
  }) async {
    final targetRegion = regionId;
    if (targetRegion == null) {
      select(null);
    }
    final requestedTab = EditorWizardNavigation.consumeInitialTab(initialTab);
    final initial = _config.value;
    final regionDelegate =
        targetRegion != null && definition(targetRegion).editableFlow
        ? _buildRegionFlowDelegate(targetRegion, initialOverride: initial)
        : null;
    if (widget.onConfigure != null) {
      await EditorWizardNavigation.openWithTab(
        requestedTab,
        widget.onConfigure!,
        delegate: regionDelegate,
      );
      return;
    }
    final delegate =
        regionDelegate ??
        EditorWizardNavigation.resolveDimensionDelegate(context);
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    final activated = <String>{};
    var confirmed = false;
    try {
      confirmed =
          await showEditorDialog<bool>(
            context: context,
            target:
                (targetRegion != null ? _regionContext(targetRegion) : null) ??
                context,
            barrierDismissible: true,
            barrierColor: targetRegion != null ? Colors.transparent : null,
            builder: (dialogContext) => EditorTabbedAlertDialog(
              dialogKey: ValueKey('${widget.keyPrefix}-settings'),
              applyButtonKey: ValueKey('${widget.keyPrefix}-settings-apply'),
              cancelButtonKey: ValueKey('${widget.keyPrefix}-settings-cancel'),
              initialTab: requestedTab,
              propertiesTitle: Text(widget.settingsTitle),
              propertiesWidth: widget.propertyDescriptors.isEmpty ? 360 : 420,
              dimensionDelegate: delegate,
              propertiesContentBuilder: (context) =>
                  ValueListenableBuilder<NativeComponentConfig>(
                    valueListenable: _config,
                    builder: (context, config, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...?widget.settingsControls?.call(config, _update),
                        for (final region in widget.regions)
                          if (!region.required &&
                              (widget.isRegionAvailable?.call(
                                    config,
                                    region.id,
                                  ) ??
                                  true))
                            SwitchListTile(
                              key: ValueKey(
                                '${widget.keyPrefix}-switch-${region.id}',
                              ),
                              title: Text(region.label),
                              value: config.isEnabled(region.id),
                              onChanged: (value) {
                                _update(
                                  _config.value.withRegionEnabled(
                                    region.id,
                                    value,
                                  ),
                                );
                                if (value) activated.add(region.id);
                              },
                            ),
                        if (widget.propertyDescriptors.isNotEmpty) ...[
                          const Divider(),
                          for (final descriptor in widget.propertyDescriptors)
                            if (widget.isPropertyAvailable?.call(
                                  config,
                                  descriptor,
                                ) ??
                                true)
                              _buildPropertyControl(
                                context,
                                config,
                                descriptor,
                              ),
                        ],
                      ],
                    ),
                  ),
              propertiesExtraActions: [
                TextButton(
                  key: ValueKey('${widget.keyPrefix}-settings-reset'),
                  onPressed: () {
                    activated.clear();
                    _update(_config.value.withSettingsReset());
                  },
                  child: const Text('Réinitialiser'),
                ),
              ],
              onApply: () async {
                delegate?.apply();
                Navigator.of(dialogContext).pop(true);
                return true;
              },
              onCancel: () => Navigator.of(dialogContext).pop(false),
            ),
          ) ==
          true;
    } finally {
      if (!confirmed && mounted) {
        delegate?.restore();
        _update(initial);
      }
      if (confirmed) {
        history?.commitTransaction();
      } else {
        history?.cancelTransaction();
      }
      delegate?.dispose();
    }
    if (confirmed && mounted) {
      widget.onConfigured?.call(activated.where(enabled).toSet());
    }
  }

  Widget _buildPropertyControl(
    BuildContext context,
    NativeComponentConfig config,
    NativePropertyDescriptor descriptor,
  ) {
    final propKey = ValueKey('${widget.keyPrefix}-prop-${descriptor.id}');
    final resetKey = ValueKey(
      '${widget.keyPrefix}-prop-reset-${descriptor.id}',
    );
    final hasCustomValue = config.property(descriptor.id) != null;

    Widget? resetButton() => descriptor.nullable && hasCustomValue
        ? IconButton(
            key: resetKey,
            tooltip: 'Par défaut (Thème)',
            icon: const Icon(Icons.restart_alt, size: 18),
            onPressed: () =>
                _update(_config.value.withProperty(descriptor.id, null)),
          )
        : null;

    return switch (descriptor.editorType) {
      NativePropertyEditorType.bool => SwitchListTile(
        key: propKey,
        title: Text(descriptor.label),
        subtitle: descriptor.subtitle != null
            ? Text(descriptor.subtitle!)
            : null,
        secondary: resetButton(),
        value:
            config.boolProperty(descriptor.id) ??
            (descriptor.defaultValue is bool
                ? descriptor.defaultValue as bool
                : false),
        onChanged: (value) =>
            _update(_config.value.withProperty(descriptor.id, value)),
      ),
      NativePropertyEditorType.color => Row(
        children: [
          Expanded(
            child: styleColorTile(
              descriptor.label,
              config.colorProperty(descriptor.id) ??
                  (descriptor.defaultValue != null
                      ? JsonColor.parse(descriptor.defaultValue, descriptor.id)
                      : Theme.of(context).colorScheme.primary),
              (color) =>
                  _update(_config.value.withProperty(descriptor.id, color)),
              key: propKey,
              dense: true,
              onClear: descriptor.nullable
                  ? () =>
                        _update(_config.value.withProperty(descriptor.id, null))
                  : null,
            ),
          ),
          ?resetButton(),
        ],
      ),
      NativePropertyEditorType.number => () {
        final min = descriptor.min ?? 0.0;
        final max = descriptor.max ?? 100.0;
        final current = config.doubleProperty(descriptor.id);
        final fallback = (descriptor.defaultValue as num?)?.toDouble() ?? min;
        final effective = (current ?? fallback).clamp(min, max);
        final formatted = current == null
            ? 'Auto'
            : (current == current.roundToDouble()
                  ? current.toInt().toString()
                  : current.toStringAsFixed(2));
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${descriptor.label} ($formatted)',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  ?resetButton(),
                ],
              ),
              if (descriptor.subtitle != null)
                Text(
                  descriptor.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Slider(
                key: propKey,
                value: effective,
                min: min,
                max: max,
                divisions: descriptor.divisions,
                onChanged: (value) =>
                    _update(_config.value.withProperty(descriptor.id, value)),
              ),
            ],
          ),
        );
      }(),
      NativePropertyEditorType.select => () {
        final effectiveValue =
            config.stringProperty(descriptor.id) ??
            (!descriptor.nullable && descriptor.defaultValue is String
                ? descriptor.defaultValue as String
                : null);
        final totalOptions =
            descriptor.options.length + (descriptor.nullable ? 1 : 0);
        IconData optionIcon(String? val) => switch (val) {
          null => Icons.hdr_auto_outlined,
          'none' => Icons.block,
          'hardEdge' => Icons.crop_sharp,
          'antiAlias' => Icons.blur_linear,
          'antiAliasWithSaveLayer' => Icons.layers_outlined,
          'light' => Icons.light_mode_outlined,
          'dark' => Icons.dark_mode_outlined,
          'fixed' => Icons.push_pin_outlined,
          'shifting' => Icons.swap_horiz,
          'spread' => Icons.space_bar,
          'centered' => Icons.format_align_center,
          'linear' => Icons.view_headline,
          'click' => Icons.touch_app_outlined,
          'basic' => Icons.mouse_outlined,
          'defer' => Icons.subdirectory_arrow_right,
          'chevron' => Icons.expand_more,
          'arrow' => Icons.arrow_downward,
          'plusMinus' => Icons.add,
          'triangle' => Icons.arrow_drop_down,
          'trailing' => Icons.last_page,
          'leading' => Icons.first_page,
          'standard' => Icons.crop_16_9,
          'singleChildScrollView' => Icons.swap_vert,
          'customScrollView' => Icons.view_day_outlined,
          'vertical' => Icons.swap_vert,
          'horizontal' => Icons.swap_horiz,
          _ => Icons.tune,
        };
        if (totalOptions <= 5) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                Text(
                  descriptor.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (descriptor.subtitle != null)
                  Text(
                    descriptor.subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                SegmentedButton<String?>(
                  key: propKey,
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    if (descriptor.nullable)
                      ButtonSegment<String?>(
                        value: null,
                        tooltip: 'Par défaut (Thème)',
                        icon: Flexible(
                          flex: 0,
                          child: Icon(optionIcon(null), size: 14),
                        ),
                        label: const Text(
                          'Par défaut (Thème)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    for (final option in descriptor.options)
                      ButtonSegment<String?>(
                        value: option.value,
                        tooltip: option.label,
                        icon: Flexible(
                          flex: 0,
                          child: Icon(optionIcon(option.value), size: 14),
                        ),
                        label: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  selected: {effectiveValue},
                  onSelectionChanged: (selected) {
                    final value = selected.first;
                    _update(
                      _config.value.withProperty(
                        descriptor.id,
                        !descriptor.nullable && value == descriptor.defaultValue
                            ? null
                            : value,
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: DropdownButtonFormField<String?>(
            key: propKey,
            isExpanded: true,
            initialValue: effectiveValue,
            decoration: InputDecoration(
              labelText: descriptor.label,
              helperText: descriptor.subtitle,
              isDense: true,
            ),
            items: [
              if (descriptor.nullable)
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Par défaut (Thème)'),
                ),
              for (final option in descriptor.options)
                DropdownMenuItem<String?>(
                  value: option.value,
                  child: Text(option.label),
                ),
            ],
            onChanged: (value) => _update(
              _config.value.withProperty(
                descriptor.id,
                !descriptor.nullable && value == descriptor.defaultValue
                    ? null
                    : value,
              ),
            ),
          ),
        );
      }(),
      NativePropertyEditorType.shape => () {
        final currentShape = config.shapeProperty(descriptor.id);
        return ListTile(
          key: propKey,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: const Icon(Icons.rounded_corner, size: 20),
          title: Text(descriptor.label),
          subtitle: Text(
            currentShape?.summary ??
                (descriptor.subtitle ?? 'Par défaut (Thème)'),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [?resetButton(), const Icon(Icons.tune, size: 18)],
          ),
          onTap: () => showNativeShapeEditor(
            context: context,
            title: descriptor.label,
            initialValue: currentShape,
            keyPrefix: '${widget.keyPrefix}-shape-${descriptor.id}',
            onChanged: (nextShape) =>
                _update(_config.value.withProperty(descriptor.id, nextShape)),
          ),
        );
      }(),
    };
  }

  Map<String, SlotImplementation> _provided() {
    final result = <String, SlotImplementation>{};
    for (final slot in widget.slots) {
      if (result.containsKey(slot.id)) {
        throw StateError('Duplicate native slot ID: ${slot.id}');
      }
      result[slot.id] = slot;
    }
    return result;
  }

  String _componentType(String key, RegisteredComponent component) =>
      'component:${component.slotId ?? key}';

  Set<String> _tagsForType(String type, {String? id}) {
    final provided = _provided();
    final supplied =
        provided[id] ??
        provided[type] ??
        (id == null ? null : ProvidedSlotScope.find(context, id)) ??
        ProvidedSlotScope.find(context, type);
    if (supplied != null) return supplied.tags;
    final registry = widget.registry;
    if (registry == null) return const {};
    for (final entry in registry.components.entries) {
      if (type == _componentType(entry.key, entry.value) ||
          type == entry.value.slotId ||
          type == 'registry:${Uri.encodeComponent(entry.key)}') {
        return entry.value.tags;
      }
    }
    final key = type.startsWith('factory:')
        ? type.substring('factory:'.length)
        : type.startsWith('registry:')
        ? Uri.decodeComponent(type.substring('registry:'.length))
        : null;
    return registry.registry[key]?.tags ?? const {};
  }

  List<SlotImplementation> slotsFor(String region) {
    final provided = _provided();
    final result = <SlotImplementation>[];
    for (final id in widget.config.slotsOf(region)) {
      final type = widget.config.slotTypeOf(id);
      SlotImplementation? slot =
          provided[id] ??
          provided[type] ??
          ProvidedSlotScope.find(context, id) ??
          ProvidedSlotScope.find(context, type);
      final registry = widget.registry;
      if (slot == null && registry != null) {
        for (final entry in registry.components.entries) {
          if (type == _componentType(entry.key, entry.value) ||
              type == entry.value.slotId ||
              type == 'registry:${Uri.encodeComponent(entry.key)}') {
            if (!(entry.value.isAvailable?.call(context) ?? true)) {
              slot = BuilderSlot(
                id: id,
                label: entry.value.label,
                tags: entry.value.tags,
                menuIcon: entry.value.menuIcon,
                visible: false,
                builder: (_) => const SizedBox.shrink(),
              );
              break;
            }
            slot = entry.value.createSlot(id);
            break;
          }
        }
        if (slot == null &&
            (type.startsWith('factory:') || type.startsWith('registry:'))) {
          final factoryKey = type.startsWith('factory:')
              ? type.substring('factory:'.length)
              : Uri.decodeComponent(type.substring('registry:'.length));
          final factory = registry.registry[factoryKey];
          if (factory != null) {
            final child = factory.getWidget(XuiBuildCtx(id: id));
            slot = child is NativePreferredSizeWidget
                ? NativeWidgetSlot(
                    id: id,
                    label: factoryKey,
                    tags: factory.tags,
                    menuIcon: factory.menuIcon,
                    child: child,
                  )
                : BuilderSlot(
                    id: id,
                    label: factoryKey,
                    tags: factory.tags,
                    menuIcon: factory.menuIcon,
                    builder: (_) => child,
                  );
          }
        }
      }
      if (slot == null) {
        throw StateError(
          'Unresolved native slot "$id" (type "$type") in ${widget.label}.',
        );
      }
      if (slot.visible) {
        final source = slot;
        final SlotImplementation resolved;
        if (source.id == id) {
          resolved = source;
        } else if (source case NativePreferredSizeWidget native) {
          resolved = NativeWidgetSlot(
            id: id,
            label: source.label,
            tags: source.tags,
            menuIcon: source.menuIcon,
            child: native,
          );
        } else {
          resolved = BuilderSlot(
            id: id,
            label: source.label,
            sizing: source.sizing,
            preferredSize: source.preferredSize,
            showLabel: source.showLabel,
            labelAlignment: source.labelAlignment,
            tags: source.tags,
            menuIcon: source.menuIcon,
            builder: (_) => source,
          );
        }
        result.add(_named(resolved));
      }
    }
    return result;
  }

  /// Exposes the instance name of [slot] to its content, renamed through
  /// [NativeComponentConfig.slotLabels].
  SlotImplementation _named(SlotImplementation slot) {
    final id = slot.id;
    final previous = widget.config.slotLabels[id];
    void rename(String label) => _update(
      _config.value.withSlotLabel(id, label == slot.label ? null : label),
    );
    void restore() => _update(_config.value.withSlotLabel(id, previous));
    return slot is NativePreferredSizeWidget
        ? _NativeInstanceSlot(
            slot,
            label: previous ?? slot.label,
            onRename: rename,
            onRestore: restore,
            overridden: previous != null,
          )
        : InstanceSlot(
            slot,
            label: previous ?? slot.label,
            onRename: rename,
            onRestore: restore,
            overridden: previous != null,
          );
  }

  Future<void> add(String region) async {
    if (!(widget.isRegionAvailable?.call(widget.config, region) ?? true)) {
      final message = 'Zone ${definition(region).label} indisponible.';
      debugPrint(message);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final provided = _provided();
    final registry = widget.registry;
    final candidates =
        <String, String>{
          for (final slot in provided.values)
            if (slot.visible) slot.id: slot.label,
          if (registry != null) ...{
            for (final entry in registry.components.entries)
              if (entry.value.isAvailable?.call(context) ?? true)
                _componentType(entry.key, entry.value): entry.value.label,
            for (final entry in registry.registry.entries)
              'factory:${entry.key}': entry.key,
          },
        }..removeWhere(
          (type, _) =>
              !definition(region).tagFilter.accepts(_tagsForType(type)),
        );
    final selected = await showComponentAddWizard(
      context: context,
      title: 'Ajouter dans ${definition(region).label}',
      keyPrefix: widget.keyPrefix,
      emptyMessage: 'Aucun slot disponible.',
      initialTargetId: region,
      candidates: [
        for (final entry in candidates.entries)
          ComponentAddCandidate(
            id: entry.key,
            label: _addLabelForType(entry.key, entry.value),
            tags: _tagsForType(entry.key),
            placementTags: _placementTagsForType(entry.key),
            configurator: _addConfiguratorOf(entry.key),
            previewBuilder: _previewBuilderOf(entry.key),
          ),
      ],
      targets: [
        for (final option in widget.regions)
          if (option.id == region || enabled(option.id))
            ComponentAddTarget(
              id: option.id,
              label: option.label,
              replaces: option.single,
              siblings: [
                for (final slot in slotsFor(option.id)) (slot.id, slot.label),
              ],
              accepts: option.tagFilter.accepts,
              zoneTags: option.tagFilter.include,
              preview: _regionPreview(option.id),
              previewFor: (beforeId) {
                if (beforeId == null) return _regionPreview(option.id);
                final siblingLabel = slotsFor(option.id)
                    .where((s) => s.id == beforeId)
                    .firstOrNull
                    ?.label;
                return _regionPreview(
                  option.id,
                  beforeId: beforeId,
                  label: siblingLabel == null ? null : 'Avant $siblingLabel',
                );
              },
            ),
      ],
    );
    if (selected == null || !mounted) return;
    region = selected.targetId;
    final type = selected.component.id;
    if (!definition(region).tagFilter.accepts(_tagsForType(type))) {
      _reportTagRejection(region);
      return;
    }
    final isProvided = provided.containsKey(type);
    var id = type;
    final used = {
      ...provided.keys,
      ..._config.value.placements.values.expand((ids) => ids),
    };
    if (!isProvided) {
      do {
        id = shortid.generate();
      } while (used.contains(id));
    }
    var next = _config.value.withSlotAdded(
      id,
      region,
      type: isProvided ? null : type,
      replace: definition(region).single,
    );
    if (selected.beforeId case final beforeId?
        when next.slotsOf(region).contains(beforeId)) {
      next = next.withSlotMoved(id, region, beforeId: beforeId);
    }
    final slot = _createSlot(type, id, label: candidates[type]!);
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      selected.applyConfiguration(registry, id);
      next =
          widget.onSlotAdded?.call(next, region, id, slot, slotsFor(region)) ??
          next;
      if (selected.size case final size?) {
        next = next.withSlotSizeConstraints(id, size);
      }
      if (selected.label case final label?) {
        next = next.withSlotLabel(id, label);
      }
      _update(next);
    } finally {
      history?.commitTransaction();
    }
  }

  SlotImplementation _createSlot(
    String type,
    String id, {
    required String label,
  }) {
    final registry = widget.registry;
    return _provided()[type] ??
        registry?.components.entries
            .where((entry) => _componentType(entry.key, entry.value) == type)
            .firstOrNull
            ?.value
            .createSlot(id) ??
        BuilderSlot(
          id: id,
          label: label,
          tags: _tagsForType(type),
          menuIcon:
              registry?.registry[type.substring('factory:'.length)]?.menuIcon,
          builder: (_) => registry!.getWidget(
            type.substring('factory:'.length),
            XuiBuildCtx(id: id),
          ),
        );
  }

  /// Contextual addition around [slot] of [region]: in the region stack when
  /// the direction follows its axis, otherwise by wrapping it in a `Layout`.
  EditorSlotInsertion? insertionForSlot(
    String region,
    SlotImplementation slot,
  ) {
    final registry = widget.registry;
    if (registry == null) return null;
    final spec = definition(region);
    final layout = registry.registry[EditorSlotWrapper.layout.factory];
    return EditorSlotInsertion(
      label: slot.label,
      host: InsertionHost(
        axis: spec.axis,
        single: spec.single,
        canWrap: layout != null && spec.tagFilter.accepts(layout.tags),
      ),
      acceptsTags: spec.tagFilter.accepts,
      zoneTags: spec.tagFilter.include,
      targetContext: () =>
          widget.slotContextFor?.call(slot) ?? _slotContext(slot.id, region),
      insert: (plan, component) async =>
          _insertAround(region, slot, plan, component),
    );
  }

  static InsertDirection? _inactiveEdgeForRegion(String region) =>
      switch (region) {
        'appBar' ||
        'header' ||
        'top' ||
        'flexibleSpace' ||
        'title' => InsertDirection.up,
        'bottomNavigationBar' ||
        'bottomAppBar' ||
        'bottomSheet' ||
        'footer' ||
        'bottom' ||
        'persistentFooterButtons' => InsertDirection.down,
        'drawer' ||
        'navigationRail' ||
        'leading' ||
        'start' => InsertDirection.left,
        'endDrawer' ||
        'actions' ||
        'trailing' ||
        'end' ||
        'floatingActionButton' => InsertDirection.right,
        _ => null,
      };

  ComponentAddPlacementPreview _regionPreview(
    String regionId, {
    String? beforeId,
    String? label,
  }) {
    final spec = definition(regionId);
    return ComponentAddPlacementPreview.inZone(
      zoneContext: () => _regionContext(regionId),
      containerContext: () => mounted ? context : null,
      axis: () => axisOf(regionId),
      replaces: spec.single,
      inactiveEdge: _inactiveEdgeForRegion(regionId),
      beforeContext: beforeId == null
          ? null
          : () => _slotContext(beforeId, regionId),
      lastSiblingContext: () {
        final slots = slotsFor(regionId);
        if (slots.isEmpty) return null;
        final last = slots.last;
        return widget.slotContextFor?.call(last) ??
            _slotContext(last.id, regionId);
      },
      label: label ?? spec.label,
      icon: beforeId == null
          ? Icons.add_box_outlined
          : Icons.vertical_align_top,
    );
  }

  void _insertAround(
    String region,
    SlotImplementation slot,
    InsertionPlan plan,
    InsertedComponent component,
  ) {
    final current = _config.value;
    final registry = widget.registry;
    if (!mounted ||
        registry == null ||
        !current.slotsOf(region).contains(slot.id)) {
      return;
    }
    final occupied = {
      for (final ids in current.placements.values) ...ids,
      ...widget.slots.map((s) => s.id),
    };
    switch (plan) {
      case WrapInsertion():
        wrapSlotInstance(
          context,
          registry: registry,
          wrapper: EditorSlotWrapper.layout,
          id: slot.id,
          type: current.slotTypeOf(slot.id),
          label: slot.label,
          occupiedIds: occupied,
          sibling: WrapSibling(
            type: component.type,
            axis: plan.axis,
            before: plan.newFirst,
            label: component.label,
            size: component.size,
            configure: component.configure,
          ),
          replace: (id, type) {
            var next = current.withSlotReplaced(slot.id, id, type);
            final preferred = preferredSizeFor(slot);
            if (!current.slotPreferredSizes.containsKey(slot.id) &&
                !current.slotSizeConstraints.containsKey(slot.id) &&
                preferred != null) {
              next = next.withSlotSize(id, preferred);
            }
            _update(next);
            _selectedSlot = id;
          },
        );
      case DirectInsertion():
        final id = uniqueInstanceId(
          context,
          registry: registry,
          occupiedIds: occupied,
        );
        var next = current
            .withSlotAdded(id, region, type: component.type)
            .withSlotMoved(
              id,
              region,
              beforeId: plan.newFirst ? slot.id : null,
              afterId: plan.newFirst ? null : slot.id,
            );
        if (plan.mode == InsertMode.push) {
          // The new component takes the target's size; the target reverts to
          // its default sizing.
          final preferred = {...next.slotPreferredSizes};
          final constraints = {...next.slotSizeConstraints};
          if (preferred.containsKey(slot.id)) {
            preferred[id] = preferred.remove(slot.id);
          }
          if (constraints.remove(slot.id) case final saved?) {
            constraints[id] = saved;
          }
          next = next.copyWith(
            slotPreferredSizes: preferred,
            slotSizeConstraints: constraints,
          );
        }
        _commitAddition(next, region, id, component);
    }
  }

  /// Applies the settings, sizing and label of an added instance [id] already
  /// placed in [next], as a single history step.
  void _commitAddition(
    NativeComponentConfig next,
    String region,
    String id,
    InsertedComponent component,
  ) {
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      component.configure(id);
      final added = _createSlot(
        component.type,
        id,
        label:
            component.label ??
            (component.type.startsWith('factory:')
                ? component.type.substring('factory:'.length)
                : component.type),
      );
      next =
          widget.onSlotAdded?.call(next, region, id, added, slotsFor(region)) ??
          next;
      if (component.size case final size?) {
        next = next.withSlotSizeConstraints(id, size);
      }
      if (component.label case final label?) {
        next = next.withSlotLabel(id, label);
      }
      _update(next);
    } finally {
      history?.commitTransaction();
    }
  }

  /// Regions offered by the contextual add wizard: the selected one first,
  /// then the other enabled regions, then the disabled but available ones,
  /// enabled by the addition. An occupied single region is skipped: wrapping
  /// covers that case.
  List<EditorAddZone> _addZones() {
    if (widget.registry == null) return const [];
    final selected = _selected;
    bool available(NativeRegion region) =>
        (widget.isRegionAvailable?.call(widget.config, region.id) ?? true) &&
        !(region.single && _config.value.slotsOf(region.id).isNotEmpty);
    return [
      for (final region in [
        ?widget.regions
            .where((region) => region.id == selected && enabled(region.id))
            .firstOrNull,
        for (final region in widget.regions)
          if (region.id != selected && enabled(region.id)) region,
        for (final region in widget.regions)
          if (!enabled(region.id)) region,
      ])
        if (available(region))
          EditorAddZone(
            id: region.id,
            label: region.label,
            hint: enabled(region.id) ? null : 'Active la zone ${region.label}',
            accepts: region.tagFilter.accepts,
            zoneTags: region.tagFilter.include,
            preview: _regionPreview(region.id),
            insert: (component) async => _insertInRegion(region.id, component),
          ),
    ];
  }

  void _insertInRegion(String region, InsertedComponent component) {
    if (!mounted ||
        !(widget.isRegionAvailable?.call(widget.config, region) ?? true)) {
      return;
    }
    final current = _config.value;
    final id = uniqueInstanceId(
      context,
      registry: widget.registry,
      occupiedIds: {
        for (final ids in current.placements.values) ...ids,
        ...widget.slots.map((s) => s.id),
      },
    );
    _commitAddition(
      current.withSlotAdded(
        id,
        region,
        type: component.type,
        replace: definition(region).single,
      ),
      region,
      id,
      component,
    );
  }

  /// Placement tags of a registry type (`factory:` or `component:`).
  Set<String> _placementTagsForType(String type) {
    final registry = widget.registry;
    if (registry == null) return const {};
    if (type.startsWith('factory:')) {
      return registry
              .registry[type.substring('factory:'.length)]
              ?.placementTags ??
          const {};
    }
    for (final entry in registry.components.entries) {
      if (_componentType(entry.key, entry.value) == type) {
        return entry.value.placementTags;
      }
    }
    return const {};
  }

  ComponentAddConfigurator<Object>? _addConfiguratorOf(String type) {
    final registry = widget.registry;
    if (registry == null) return null;
    if (type.startsWith('factory:')) {
      return registry
          .registry[type.substring('factory:'.length)]
          ?.addConfigurator;
    }
    for (final entry in registry.components.entries) {
      if (_componentType(entry.key, entry.value) == type) {
        return entry.value.addConfigurator;
      }
    }
    return null;
  }

  String _addLabelForType(String type, String defaultLabel) {
    final registry = widget.registry;
    if (registry == null) return defaultLabel;
    if (type.startsWith('factory:')) {
      return registry.registry[type.substring('factory:'.length)]?.label ??
          defaultLabel;
    }
    return defaultLabel;
  }

  WidgetBuilder? _previewBuilderOf(String type) {
    final registry = widget.registry;
    if (registry == null) return null;
    if (type.startsWith('factory:')) {
      return registry
          .registry[type.substring('factory:'.length)]
          ?.previewBuilder;
    }
    for (final entry in registry.components.entries) {
      if (_componentType(entry.key, entry.value) == type) {
        return entry.value.previewBuilder;
      }
    }
    return null;
  }

  SlotSizeDimensionDelegate _buildSlotSizeDelegate(SlotImplementation slot) {
    final initial = _config.value;
    return SlotSizeDimensionDelegate(
      context: context,
      slot: slot,
      saved: initial.slotSizeConstraints[slot.id],
      legacy: preferredSizeFor(slot),
      initialLabel: initial.slotLabels[slot.id] ?? slot.label,
      changes: _config,
      onLabelChanged: (label) => _update(
        _config.value.withSlotLabel(
          slot.id,
          label == slot.label ? null : label,
        ),
      ),
      measure: () {
        final layout = context.findRenderObject();
        final slotBox = _slotContext(slot.id)?.findRenderObject();
        final region = initial.placements.entries
            .where((entry) => entry.value.contains(slot.id))
            .firstOrNull
            ?.key;
        final zoneBox = _regionContext(region)?.findRenderObject();
        if (layout is! RenderBox ||
            !layout.hasSize ||
            slotBox is! RenderBox ||
            !slotBox.hasSize ||
            zoneBox is! RenderBox ||
            !zoneBox.hasSize) {
          return null;
        }
        Rect bounds(RenderBox box) => MatrixUtils.transformRect(
          box.getTransformTo(layout),
          Offset.zero & box.size,
        );
        return (
          layout: layout.size,
          zone: bounds(zoneBox),
          slot: bounds(slotBox),
        );
      },
      onApply: (dimensions, useLegacyPixels) {
        if (useLegacyPixels &&
            dimensions.minWidth == null &&
            dimensions.minHeight == null &&
            dimensions.maxWidth == null &&
            dimensions.maxHeight == null &&
            !dimensions.hasPadding &&
            dimensions.preferredWidth?.unit == SlotSizeUnit.pixels &&
            dimensions.preferredHeight?.unit == SlotSizeUnit.pixels) {
          _update(
            _config.value.withSlotSize(
              slot.id,
              Size(
                dimensions.preferredWidth!.value,
                dimensions.preferredHeight!.value,
              ),
            ),
          );
        } else {
          _update(_config.value.withSlotSizeConstraints(slot.id, dimensions));
        }
      },
      onRestore: () {
        final current = _config.value;
        _update(
          current.copyWith(
            slotLabels: {...current.slotLabels}
              ..remove(slot.id)
              ..addAll({
                if (initial.slotLabels.containsKey(slot.id))
                  slot.id: initial.slotLabels[slot.id]!,
              }),
            slotPreferredSizes: {...current.slotPreferredSizes}
              ..remove(slot.id)
              ..addAll({
                if (initial.slotPreferredSizes.containsKey(slot.id))
                  slot.id: initial.slotPreferredSizes[slot.id],
              }),
            slotSizeConstraints: {...current.slotSizeConstraints}
              ..remove(slot.id)
              ..addAll({slot.id: ?initial.slotSizeConstraints[slot.id]}),
          ),
        );
      },
    );
  }

  Future<void> _editSize(SlotImplementation slot) async {
    final initial = _config.value;
    await showSlotSizeEditor(
      context: context,
      slot: slot,
      saved: initial.slotSizeConstraints[slot.id],
      legacy: preferredSizeFor(slot),
      changes: _config,
      target: _slotContext(slot.id),
      measure: () {
        final layout = context.findRenderObject();
        final slotBox = _slotContext(slot.id)?.findRenderObject();
        final region = initial.placements.entries
            .where((entry) => entry.value.contains(slot.id))
            .firstOrNull
            ?.key;
        final zoneBox = _regionContext(region)?.findRenderObject();
        if (layout is! RenderBox ||
            !layout.hasSize ||
            slotBox is! RenderBox ||
            !slotBox.hasSize ||
            zoneBox is! RenderBox ||
            !zoneBox.hasSize) {
          return null;
        }
        Rect bounds(RenderBox box) => MatrixUtils.transformRect(
          box.getTransformTo(layout),
          Offset.zero & box.size,
        );
        return (
          layout: layout.size,
          zone: bounds(zoneBox),
          slot: bounds(slotBox),
        );
      },
      onApply: (dimensions, useLegacyPixels) {
        if (useLegacyPixels &&
            dimensions.minWidth == null &&
            dimensions.minHeight == null &&
            dimensions.maxWidth == null &&
            dimensions.maxHeight == null &&
            !dimensions.hasPadding &&
            dimensions.preferredWidth?.unit == SlotSizeUnit.pixels &&
            dimensions.preferredHeight?.unit == SlotSizeUnit.pixels) {
          _update(
            _config.value.withSlotSize(
              slot.id,
              Size(
                dimensions.preferredWidth!.value,
                dimensions.preferredHeight!.value,
              ),
            ),
          );
        } else {
          _update(_config.value.withSlotSizeConstraints(slot.id, dimensions));
        }
      },
      onRestore: () {
        final current = _config.value;
        _update(
          current.copyWith(
            slotPreferredSizes: {...current.slotPreferredSizes}
              ..remove(slot.id)
              ..addAll({
                if (initial.slotPreferredSizes.containsKey(slot.id))
                  slot.id: initial.slotPreferredSizes[slot.id],
              }),
            slotSizeConstraints: {...current.slotSizeConstraints}
              ..remove(slot.id)
              ..addAll({slot.id: ?initial.slotSizeConstraints[slot.id]}),
          ),
        );
      },
    );
  }

  bool _showOverlay() =>
      editing && _active && identical(LayoutSelection.activeOwner, this);

  void _setRegionHovered(String id, bool hovered) {
    if (!mounted) return;
    final scopes = {..._hoveredRegionScopes.value};
    final changed = hovered ? scopes.add(id) : scopes.remove(id);
    if (!changed) return;
    setState(() => _hoveredRegionScopes.value = scopes);
  }

  bool _canMoveSlot(String slotId, String region) {
    if (!editing || !enabled(region)) return false;
    final config = _config.value;
    if (!config.placements.values.any((ids) => ids.contains(slotId))) {
      return false;
    }
    final current = config.slotsOf(region);
    if (definition(region).single && current.any((id) => id != slotId)) {
      return false;
    }
    return current.contains(slotId) ||
        definition(region).tagFilter
            .accepts(_tagsForType(config.slotTypeOf(slotId), id: slotId));
  }

  void _moveSlot(
    String slotId,
    String region, {
    String? beforeId,
    String? afterId,
  }) {
    if (!_canMoveSlot(slotId, region)) {
      final message =
          'Déplacement impossible vers ${definition(region).label} : '
          'zone indisponible, occupée ou composant incompatible.';
      debugPrint(message);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final next = _config.value.withSlotMoved(
      slotId,
      region,
      beforeId: beforeId,
      afterId: afterId,
    );
    if (identical(next, _config.value)) return;
    _update(next);
    if (mounted && identical(_config.value, next)) select(region);
  }

  /// Wrapper choices accepted by the receiving native property.
  List<EditorSlotWrapAction> wrapActionsForSlot(
    String region,
    SlotImplementation slot,
  ) => slotWrapActions(
    registry: widget.registry,
    acceptsTags: definition(region).tagFilter.accepts,
    onWrap: (wrapper) async {
      if (!mounted || !_config.value.slotsOf(region).contains(slot.id)) return;
      final current = _config.value;
      wrapSlotInstance(
        context,
        registry: widget.registry!,
        wrapper: wrapper,
        id: slot.id,
        type: current.slotTypeOf(slot.id),
        label: slot.label,
        occupiedIds: {
          for (final ids in current.placements.values) ...ids,
          ...widget.slots.map((s) => s.id),
        },
        replace: (id, type) {
          var next = current.withSlotReplaced(slot.id, id, type);
          final preferred = preferredSizeFor(slot);
          if (!current.slotPreferredSizes.containsKey(slot.id) &&
              !current.slotSizeConstraints.containsKey(slot.id) &&
              preferred != null) {
            next = next.withSlotSize(id, preferred);
          }
          _update(next);
          _selectedSlot = id;
        },
      );
    },
  );

  List<EditorSlotWrapAction> wrapActionsForRegion(String region) {
    final children = slotsFor(region);
    return zoneChildrenWrapActions(
      registry: widget.registry,
      hasChildren: children.isNotEmpty,
      acceptsTags: definition(region).tagFilter.accepts,
      onWrapInCard: () async {
        if (!mounted) return;
        final current = _config.value;
        final slots = slotsFor(region);
        if (slots.isEmpty || widget.registry == null) return;
        final childIds = [for (final slot in slots) slot.id];
        final movedSet = childIds.toSet();
        wrapZoneChildrenInCard(
          context,
          registry: widget.registry!,
          childIds: childIds,
          slotTypes: {for (final id in childIds) id: current.slotTypeOf(id)},
          slotLabels: {
            for (final slot in slots)
              slot.id: current.slotLabels[slot.id] ?? slot.label,
          },
          slotPreferredSizes: {
            for (final slot in slots)
              if (current.slotPreferredSizes.containsKey(slot.id))
                slot.id: current.slotPreferredSizes[slot.id]
              else if (!current.slotSizeConstraints.containsKey(slot.id) &&
                  preferredSizeFor(slot) != null)
                slot.id: preferredSizeFor(slot),
          },
          slotSizeConstraints: {
            for (final id in childIds) id: ?current.slotSizeConstraints[id],
          },
          axis: axisOf(region),
          flow: flowOf(region),
          occupiedIds: {
            for (final ids in current.placements.values) ...ids,
            ...widget.slots.map((s) => s.id),
          },
          replaceChildren: (cardId, cardType) {
            final stillReferenced = <String>{
              for (final entry in current.placements.entries)
                if (entry.key != region) ...entry.value,
            };
            final removedOnly = movedSet.difference(stillReferenced);
            final next = current.copyWith(
              placements: {
                ...current.placements,
                region: [cardId],
              },
              slotTypes: {
                for (final entry in current.slotTypes.entries)
                  if (!removedOnly.contains(entry.key)) entry.key: entry.value,
                cardId: cardType,
              },
              slotPreferredSizes: {
                for (final entry in current.slotPreferredSizes.entries)
                  if (!removedOnly.contains(entry.key)) entry.key: entry.value,
              },
              slotSizeConstraints: {
                for (final entry in current.slotSizeConstraints.entries)
                  if (!removedOnly.contains(entry.key)) entry.key: entry.value,
              },
              slotLabels: {
                for (final entry in current.slotLabels.entries)
                  if (!removedOnly.contains(entry.key)) entry.key: entry.value,
              },
            );
            _update(next);
            _selectedSlot = cardId;
          },
        );
      },
    );
  }

  /// Wraps a single [slot] of region [id] with its slot editing actions,
  /// selection, and drag-and-drop reordering without duplicating the region's
  /// outer [EditorSlot] or zone badge.
  Widget slotItem(String id, SlotImplementation slot) {
    final spec = definition(id);
    final overlay = _showOverlay();
    final selected = _selected == id;
    final emphasis = LabelEmphasis(
      scopes: _hoveredRegionScopes,
      scope: id,
      onHover: (_, _, value) => _setRegionHovered(id, value),
    );
    return SlotStack(
      slots: [slot],
      focusKeys: _slotKeys,
      regionSlotIds: [for (final item in slotsFor(id)) item.id],
      axis: spec.axis,
      expand: false,
      stretch: spec.stretch,
      emphasis: emphasis,
      preferredSizes: {
        if (slot case NativePreferredSizeWidget native)
          slot.id: native.preferredSizeIn(context),
        ...widget.config.slotPreferredSizes,
      },
      sizeConstraints: widget.config.slotSizeConstraints,
      layoutSize: _layoutSize,
      showLabels: overlay,
      zoneLabel: spec.label,
      selectedSlotId: selected ? _selectedSlot : null,
      onSelectSlot: editing && widget.editSurface
          ? (slot) => _toggleSlot(id, slot)
          : null,
      onSelectContent: editing ? (slot) => _selectSlot(id, slot) : null,
      canSelectSlot: _canSelectSlot,
      onResizeSlot: editing && widget.editSurface
          ? (slot, dimensions) => _update(
              _config.value.withSlotSizeConstraints(slot.id, dimensions),
            )
          : null,
      mover: editing
          ? SlotMover(
              owner: this,
              canMove: (slotId) => _canMoveSlot(slotId, id),
              onMove: (slotId, {beforeId, afterId}) =>
                  _moveSlot(slotId, id, beforeId: beforeId, afterId: afterId),
            )
          : null,
      onRemoveSlot: editing
          ? (slot) async {
              if (widget.onSlotRemoved != null) {
                await widget.onSlotRemoved!(id, slot);
                return;
              }
              removeSlotInstance(
                context,
                id: slot.id,
                type: _config.value.slotTypeOf(slot.id),
                containerKind: EditorConfigKind.nativeComponent,
                unplace: () => _update(_config.value.withoutSlot(slot.id)),
              );
            }
          : null,
      onEditPreferredSize: editing ? _editSize : null,
      dimensionDelegateForSlot: editing ? _buildSlotSizeDelegate : null,
      wrapActionsForSlot: editing
          ? (slot) => wrapActionsForSlot(id, slot)
          : null,
      insertionForSlot: editing ? (slot) => insertionForSlot(id, slot) : null,
    );
  }

  /// Renders a single [slot] of region [id] as a Sliver:
  /// - If [slot] can render natively as a Sliver (`SuperAppBar`, `SuperListView`,
  ///   or a Flutter `Sliver*` widget), it is built inside a [SliverSlotScope]
  ///   with its slot editing actions and selection.
  /// - Otherwise, it is wrapped in a [SliverToBoxAdapter] containing [slotItem].
  Widget sliverSlotItem(
    String id,
    SlotImplementation slot, {
    required Axis scrollDirection,
  }) {
    if (slot.canRenderAsSliver(context)) {
      final selectable = _canSelectSlot(slot);
      final actionLabel = 'Taille et marge préférées : ${slot.label}';
      final constraints = widget.config.slotSizeConstraints[slot.id];
      final preferredSize = preferredSizeFor(slot);
      final padding = constraints?.contentPadding ?? EdgeInsets.zero;
      Widget sliver = SliverSlotScope(
        enabled: true,
        scrollDirection: scrollDirection,
        preferredSize: preferredSize,
        child: EditorSlotAction(
          key: ValueKey('slot-item-${slot.id}'),
          label: actionLabel,
          tooltip: formatSlotSizeTooltip(
            title: actionLabel,
            constraints: constraints,
            preferredSize: preferredSize,
          ),
          inline: true,
          enabled: editing,
          showEdit: editing,
          onSelect: editing && selectable ? () => _selectSlot(id, slot) : null,
          onEdit: () async => _editSize(slot),
          dimensionDelegateBuilder: editing
              ? () => _buildSlotSizeDelegate(slot)
              : null,
          onRemove: editing
              ? () async {
                  if (widget.onSlotRemoved != null) {
                    await widget.onSlotRemoved!(id, slot);
                    return;
                  }
                  removeSlotInstance(
                    context,
                    id: slot.id,
                    type: _config.value.slotTypeOf(slot.id),
                    containerKind: EditorConfigKind.nativeComponent,
                    unplace: () => _update(_config.value.withoutSlot(slot.id)),
                  );
                }
              : null,
          wrapActions: editing
              ? wrapActionsForSlot(id, slot)
              : const <EditorSlotWrapAction>[],
          insertion: editing ? insertionForSlot(id, slot) : null,
          child: KeyedSubtree(
            key: _slotKeys.putIfAbsent('${slot.id}:sliver', GlobalKey.new),
            child: EditorSelectionRegion(
              enabled: editing && selectable,
              selected: _selected == id && _selectedSlot == slot.id,
              onSelect: () => _selectSlot(id, slot),
              child: slot,
            ),
          ),
        ),
      );
      if (padding != EdgeInsets.zero) {
        sliver = SliverPadding(padding: padding, sliver: sliver);
      }
      return sliver;
    }
    return SliverToBoxAdapter(
      child: SlotContentFitScope(
        fitWidth: scrollDirection == Axis.horizontal,
        fitHeight: scrollDirection == Axis.vertical,
        child: slotItem(id, slot),
      ),
    );
  }

  /// Renders region [id] as a Sliver (for use inside a `CustomScrollView`).
  Widget sliverRegion(
    String id, {
    required Axis scrollDirection,
    bool fillWhenEmpty = false,
  }) {
    final spec = definition(id);
    final slots = slotsFor(id);
    if (slots.isEmpty && !fillWhenEmpty) {
      if (!editing) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }
      final fallbackHeight =
          sizeOf(id) ??
          (spec.emptySize.height.isFinite
              ? spec.emptySize.height
              : kToolbarHeight);
      return SliverToBoxAdapter(
        child: SizedBox(height: fallbackHeight, child: region(id)),
      );
    }
    final selected = _selected == id;
    final regionFlow = flowOf(id);
    final spacing = regionFlow.spacing;
    final padding = regionFlow.contentPadding;
    final slivers = <Widget>[];
    for (final (index, slot) in slots.indexed) {
      if (index > 0 && spacing > 0) {
        slivers.add(
          SliverToBoxAdapter(
            child: SizedBox(
              width: scrollDirection == Axis.horizontal ? spacing : null,
              height: scrollDirection == Axis.vertical ? spacing : null,
            ),
          ),
        );
      }
      slivers.add(sliverSlotItem(id, slot, scrollDirection: scrollDirection));
    }
    Widget content = slivers.isEmpty
        ? const SliverFillRemaining(
            hasScrollBody: false,
            child: SizedBox.expand(),
          )
        : slivers.length == 1
        ? slivers.single
        : SliverMainAxisGroup(slivers: slivers);
    if (padding != EdgeInsets.zero) {
      content = SliverPadding(padding: padding, sliver: content);
    }
    return SliverSlotScope(
      enabled: true,
      scrollDirection: scrollDirection,
      child: LayoutSelectionScope(
        owner: this,
        path: [..._path, spec.label],
        child: Builder(
          key: _keys.putIfAbsent('$id:sliver', GlobalKey.new),
          builder: (regionContext) => EditorSelectionRegion(
            enabled: editing,
            isZone: true,
            selected: selected && _selectedSlot == null,
            onSelect: () => select(id, regionContext),
            child: EditorSlot(
              id: _effectiveComponentId,
              zoneId: id,
              label: spec.label,
              menuTitle: 'zone ${spec.label}',
              menuSubtitle: () => _componentLabel,
              menuTooltip: () => _regionTooltip(id),
              menuIcon: EditorSlot.zoneMenuIcon,
              menuDestination: spec.menuDestination,
              editable: true,
              axisAction: spec.editableFlow ? () => _axisActionFor(id) : null,
              onEdit: widget.onEditRegion != null
                  ? () => EditorWizardNavigation.openWithTab(
                      EditorWizardTab.properties,
                      () => widget.onEditRegion!(id),
                      delegate: spec.editableFlow
                          ? _buildRegionFlowDelegate(id)
                          : null,
                    )
                  : () => configure(
                      regionId: id,
                      initialTab: EditorWizardTab.properties,
                    ),
              onAdd: () => add(id),
              wrapChildrenActions: wrapActionsForRegion(id),
              onContextMenu: (_) => select(id, regionContext),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps a box [child] (such as a `CustomScrollView`) with the drop target,
  /// selection border, hover highlight, and zone badge of region [id].
  Widget regionOverlay(
    String id, {
    required Widget child,
    bool showBadge = true,
  }) {
    final spec = definition(id);
    final regionAxis = axisOf(id);
    final slots = slotsFor(id);
    final overlay = _showOverlay();
    final selected = _selected == id;
    final emphasis = LabelEmphasis(
      scopes: _hoveredRegionScopes,
      scope: id,
      onHover: (_, _, value) => _setRegionHovered(id, value),
    );
    final colors = Theme.of(context).colorScheme;
    return SlotZoneTarget(
      key: ValueKey('${widget.keyPrefix}-slot-drop-$id'),
      owner: this,
      zoneLabel: spec.label,
      ids: _config.value.slotsOf(id),
      canMove: (slotId) => _canMoveSlot(slotId, id),
      onMove: (slotId) => _moveSlot(slotId, id),
      alignment: regionAxis == Axis.horizontal && !spec.stretch
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.topStart,
      child: Stack(
        alignment: regionAxis == Axis.horizontal && !spec.stretch
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.topStart,
        children: [
          child,
          Positioned.fill(
            child: EditorOverlayVisibility(
              child: !overlay
                  ? const SizedBox.shrink()
                  : selected
                  ? (_selectedSlot != null
                        ? EditorSelectionBorder.subtleParent(
                            key: ValueKey('${widget.keyPrefix}-selected-$id'),
                          )
                        : EditorSelectionBorder.active(
                            key: ValueKey('${widget.keyPrefix}-selected-$id'),
                          ))
                  : IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: colors.outlineVariant,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (overlay && showBadge)
            ValueListenableBuilder<Set<Object>>(
              valueListenable: _hoveredRegionScopes,
              builder: (context, hoveredRegions, _) =>
                  hoveredRegions.contains(id)
                  ? EditorZoneHighlight(
                      key: ValueKey('${widget.keyPrefix}-zone-highlight-$id'),
                    )
                  : const SizedBox.shrink(),
            ),
          if (overlay && showBadge)
            Positioned.fill(
              key: ValueKey('${widget.keyPrefix}-badge-$id'),
              child: EditorOverlay(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: EmphasizedLabel(
                      emphasis: emphasis,
                      allScopes: true,
                      child: EditorZoneBadge(
                        key: ValueKey('${widget.keyPrefix}-badge-content-$id'),
                        label: spec.label,
                        labelKey: ValueKey('${widget.keyPrefix}-select-$id'),
                        selected: selected,
                        hasSelectedChild: selected && _selectedSlot != null,
                        onHover: (hovered) => emphasis.report(id, hovered),
                        onTap: () => select(
                          selected ? null : id,
                          _keys['$id:sliver']?.currentContext ??
                              _keys[id]?.currentContext,
                        ),
                        onAdd: slots.isEmpty
                            ? () {
                                select(
                                  id,
                                  _keys['$id:sliver']?.currentContext ??
                                      _keys[id]?.currentContext,
                                );
                                add(id);
                              }
                            : null,
                        addKey: ValueKey('${widget.keyPrefix}-add-$id'),
                        addTooltip: 'Ajouter dans ${spec.label}',
                        actions: [
                          if (spec.editableFlow && selected) ...[
                            ZoneAxisButton(
                              key: ValueKey(
                                '${widget.keyPrefix}-toggle-axis-$id',
                              ),
                              action: _axisActionFor(id),
                              compact: true,
                              color: colors.onSurface,
                            ),
                            IconButton(
                              key: ValueKey('${widget.keyPrefix}-flow-$id'),
                              tooltip:
                                  '${spec.label} : Taille et paramètres de flux',
                              visualDensity: VisualDensity.compact,
                              iconSize: 14,
                              padding: const EdgeInsets.all(2),
                              constraints: const BoxConstraints(),
                              color: colors.onSurface,
                              onPressed: () => _openRegionFlowEditor(id),
                              icon: const Icon(Icons.straighten),
                            ),
                          ],
                          ...?widget.regionActions?.call(id),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Decorates a native property without changing the adapter's composition.
  Widget region(
    String id, {
    Widget? child,
    SlotImplementation? item,
    bool showBadge = true,
    bool? expand,
    bool? stretch,
  }) {
    final spec = definition(id);
    final regionAxis = axisOf(id);
    final regionFlow = flowOf(id);
    final fixedSize = sizeOf(id);
    final effectiveExpand = expand ?? spec.expand;
    final effectiveStretch = stretch ?? spec.stretch;
    final slots = item == null ? slotsFor(id) : [item];
    final overlay = _showOverlay();
    final selected = _selected == id;
    final emphasis = LabelEmphasis(
      scopes: _hoveredRegionScopes,
      scope: id,
      onHover: (_, _, value) => _setRegionHovered(id, value),
    );
    final colors = Theme.of(context).colorScheme;
    Widget content =
        child ??
        SlotStack(
          slots: slots,
          focusKeys: _slotKeys,
          axis: regionAxis,
          flow: regionFlow,
          expand: fixedSize != null && regionAxis == Axis.vertical
              ? true
              : effectiveExpand,
          stretch: fixedSize != null && regionAxis == Axis.horizontal
              ? true
              : effectiveStretch,
          preferredSizes: {
            for (final slot in slots)
              if (slot case NativePreferredSizeWidget native)
                slot.id: native.preferredSizeIn(context),
            ...widget.config.slotPreferredSizes,
            if (spec.fillSize != null)
              for (final slot in slots)
                if (slot.sizing == SlotSizing.fill &&
                    slot.tags.intersection(const {
                      'action',
                      'button',
                      'text',
                    }).isEmpty &&
                    slot.preferredSize == null &&
                    !widget.config.slotPreferredSizes.containsKey(slot.id))
                  slot.id: spec.fillSize,
          },
          sizeConstraints: widget.config.slotSizeConstraints,
          layoutSize: _layoutSize,
          showLabels: overlay,
          zoneLabel: spec.label,
          selectedSlotId: selected ? _selectedSlot : null,
          onSelectSlot: editing && widget.editSurface
              ? (slot) => _toggleSlot(id, slot)
              : null,
          onSelectContent: editing ? (slot) => _selectSlot(id, slot) : null,
          canSelectSlot: _canSelectSlot,
          onResizeSlot: editing && widget.editSurface
              ? (slot, dimensions) => _update(
                  _config.value.withSlotSizeConstraints(slot.id, dimensions),
                )
              : null,
          mover: editing
              ? SlotMover(
                  owner: this,
                  canMove: (slotId) => _canMoveSlot(slotId, id),
                  onMove: (slotId, {beforeId, afterId}) => _moveSlot(
                    slotId,
                    id,
                    beforeId: beforeId,
                    afterId: afterId,
                  ),
                )
              : null,
          onRemoveSlot: editing
              ? (slot) async {
                  if (widget.onSlotRemoved != null) {
                    await widget.onSlotRemoved!(id, slot);
                    return;
                  }
                  removeSlotInstance(
                    context,
                    id: slot.id,
                    type: _config.value.slotTypeOf(slot.id),
                    containerKind: EditorConfigKind.nativeComponent,
                    unplace: () => _update(_config.value.withoutSlot(slot.id)),
                  );
                }
              : null,
          onEditPreferredSize: editing ? _editSize : null,
          dimensionDelegateForSlot: editing ? _buildSlotSizeDelegate : null,
          wrapActionsForSlot: editing
              ? (slot) => wrapActionsForSlot(id, slot)
              : null,
          insertionForSlot: editing
              ? (slot) => insertionForSlot(id, slot)
              : null,
        );
    if (fixedSize != null) {
      content = SizedBox(height: fixedSize, child: content);
    }
    return LayoutSelectionScope(
      owner: this,
      path: [..._path, spec.label],
      child: Builder(
        key: _keys.putIfAbsent(
          item == null ? id : '$id:${item.id}',
          GlobalKey.new,
        ),
        builder: (regionContext) => EditorSelectionRegion(
          enabled: editing,
          isZone: true,
          selected: selected && _selectedSlot == null,
          onSelect: () => select(id, regionContext),
          child: EditorSlot(
            id: _effectiveComponentId,
            zoneId: id,
            label: spec.label,
            menuTitle: 'zone ${spec.label}',
            menuSubtitle: () => _componentLabel,
            menuTooltip: () => _regionTooltip(id),
            menuIcon: EditorSlot.zoneMenuIcon,
            menuDestination: spec.menuDestination,
            editable: true,
            axisAction: spec.editableFlow ? () => _axisActionFor(id) : null,
            onEdit: widget.onEditRegion != null
                ? () => EditorWizardNavigation.openWithTab(
                    EditorWizardTab.properties,
                    () => widget.onEditRegion!(id),
                    delegate: spec.editableFlow
                        ? _buildRegionFlowDelegate(id)
                        : null,
                  )
                : () => configure(
                    regionId: id,
                    initialTab: EditorWizardTab.properties,
                  ),
            onAdd: () => add(id),
            wrapChildrenActions: wrapActionsForRegion(id),
            onContextMenu: (_) => select(id, regionContext),
            child: SlotZoneTarget(
              key: ValueKey(
                '${widget.keyPrefix}-slot-drop-$id${item == null ? '' : ':${item.id}'}',
              ),
              owner: this,
              zoneLabel: spec.label,
              ids: _config.value.slotsOf(id),
              canMove: (slotId) => _canMoveSlot(slotId, id),
              onMove: (slotId) => _moveSlot(slotId, id),
              alignment: regionAxis == Axis.horizontal && !effectiveStretch
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.topStart,
              child: Stack(
                alignment: regionAxis == Axis.horizontal && !effectiveStretch
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.topStart,
                children: [
                  if (slots.isEmpty && editing)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final fillWidth =
                            (regionAxis == Axis.horizontal
                                ? effectiveExpand
                                : effectiveStretch) &&
                            constraints.hasBoundedWidth;
                        final fillHeight =
                            fixedSize == null &&
                            (regionAxis == Axis.vertical
                                ? effectiveExpand
                                : effectiveStretch) &&
                            constraints.hasBoundedHeight;
                        return SizedBox(
                          width: fillWidth
                              ? double.infinity
                              : (spec.emptySize.width.isFinite
                                    ? spec.emptySize.width
                                    : (constraints.hasBoundedWidth
                                          ? double.infinity
                                          : 120)),
                          height:
                              fixedSize ??
                              (fillHeight
                                  ? double.infinity
                                  : (spec.emptySize.height.isFinite
                                        ? spec.emptySize.height
                                        : kToolbarHeight)),
                        );
                      },
                    )
                  else
                    content,
                  Positioned.fill(
                    child: EditorOverlayVisibility(
                      child: !overlay
                          ? const SizedBox.shrink()
                          : selected
                          ? (_selectedSlot != null
                                ? EditorSelectionBorder.subtleParent(
                                    key: ValueKey(
                                      '${widget.keyPrefix}-selected-$id',
                                    ),
                                  )
                                : EditorSelectionBorder.active(
                                    key: ValueKey(
                                      '${widget.keyPrefix}-selected-$id',
                                    ),
                                  ))
                          : IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (overlay && showBadge)
                    ValueListenableBuilder<Set<Object>>(
                      valueListenable: _hoveredRegionScopes,
                      builder: (context, hoveredRegions, _) =>
                          hoveredRegions.contains(id)
                          ? EditorZoneHighlight(
                              key: ValueKey(
                                '${widget.keyPrefix}-zone-highlight-$id',
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  if (overlay && showBadge)
                    Positioned.fill(
                      key: ValueKey('${widget.keyPrefix}-badge-$id'),
                      child: EditorOverlay(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: EmphasizedLabel(
                              emphasis: emphasis,
                              allScopes: true,
                              child: EditorZoneBadge(
                                key: ValueKey(
                                  '${widget.keyPrefix}-badge-content-$id',
                                ),
                                label: spec.label,
                                labelKey: ValueKey(
                                  '${widget.keyPrefix}-select-$id',
                                ),
                                selected: selected,
                                hasSelectedChild:
                                    selected && _selectedSlot != null,
                                onHover: (hovered) =>
                                    emphasis.report(id, hovered),
                                onTap: () =>
                                    select(selected ? null : id, regionContext),
                                onAdd: slots.isEmpty
                                    ? () {
                                        select(id, regionContext);
                                        add(id);
                                      }
                                    : null,
                                addKey: ValueKey('${widget.keyPrefix}-add-$id'),
                                addTooltip: 'Ajouter dans ${spec.label}',
                                actions: [
                                  if (spec.editableFlow && selected) ...[
                                    ZoneAxisButton(
                                      key: ValueKey(
                                        '${widget.keyPrefix}-toggle-axis-$id',
                                      ),
                                      action: _axisActionFor(id),
                                      compact: true,
                                      color: colors.onSurface,
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        '${widget.keyPrefix}-flow-$id',
                                      ),
                                      tooltip:
                                          '${spec.label} : Taille et paramètres de flux',
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 14,
                                      padding: const EdgeInsets.all(2),
                                      constraints: const BoxConstraints(),
                                      color: colors.onSurface,
                                      onPressed: () =>
                                          _openRegionFlowEditor(id),
                                      icon: const Icon(Icons.straighten),
                                    ),
                                  ],
                                  ...?widget.regionActions?.call(id),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _validate(widget.config);
    Widget wrapSurface(BuildContext context) {
      final child = widget.builder(context, this);
      if (!widget.editSurface) return child;
      return EditorSelectionRegion(
        enabled: editing,
        isZone: true,
        fallback: true,
        selected: _active && _selected == null,
        onSelect: () => select(null),
        child: EditorSlot(
          id: _effectiveComponentId,
          label: widget.settingsTitle,
          menuTitle: widget.label,
          menuType: widget.menuType,
          menuTooltip: _componentTooltip,
          menuIcon: widget.menuIcon,
          editable: true,
          onEdit: configure,
          onContextMenu: (_) => select(null),
          child: child,
        ),
      );
    }

    return ProvidedSlotScope(
      slots: widget.slots,
      child: EditorAddZones(
        label: widget.label,
        enabled: editing,
        zones: _addZones,
        child: ListenableBuilder(
          listenable: LayoutSelection.path,
          builder: (context, _) {
            if (SliverSlotScope.isSliver(context)) {
              return SliverLayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = constraints.axis == Axis.horizontal;
                  final width = horizontal
                      ? constraints.viewportMainAxisExtent
                      : constraints.crossAxisExtent;
                  final height = horizontal
                      ? constraints.crossAxisExtent
                      : constraints.viewportMainAxisExtent;
                  _layoutSize = Size(
                    width.isFinite ? width : 0,
                    height.isFinite ? height : 0,
                  );
                  return wrapSurface(context);
                },
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                _layoutSize = Size(
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
                  constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
                );
                return wrapSurface(context);
              },
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _editMode?.removeListener(_editingChanged);
    LayoutSelection.unregister(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => LayoutSelection.report(this, const []),
    );
    _config.dispose();
    _hoveredRegionScopes.dispose();
    super.dispose();
  }
}

class _NativeRegionFlowDimensionDelegate extends EditorDimensionDelegate {
  _NativeRegionFlowDimensionDelegate({
    required this.title,
    required this.onRestore,
    required this.onReset,
    required this.builder,
  });

  @override
  final String title;
  final VoidCallback onRestore;
  final VoidCallback onReset;
  final WidgetBuilder builder;

  @override
  double get contentWidth => 400;

  @override
  void restore() => onRestore();

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  List<Widget> buildExtraActions(
    BuildContext context, {
    required VoidCallback onResetAndClose,
  }) => [TextButton(onPressed: onReset, child: const Text('Réinitialiser'))];
}
