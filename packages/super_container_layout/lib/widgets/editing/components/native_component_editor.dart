/// Éditeur générique des propriétés et régions d'un composant Material natif ([NativeComponentEditor]).
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/models/component_config.dart';

import '../../../models/component_behavior.dart';
import '../../../models/native_component_config.dart';
import '../../../models/native_property_descriptor.dart';
import '../../../models/registry.dart';
import '../../../models/super_layout_config.dart';
import '../../components/component_tooltip.dart';
import '../../components/super_layout/layout_selection.dart';
import '../../components/super_layout/slot_implementation.dart';
import '../../components/super_layout/super_layout.dart'
    show ZoneFlowSettingsEditor;
import '../../components/super_layout/zone_axis_button.dart';
import '../addition/component_add_wizard.dart';
import '../addition/insertion_plan.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../history/editor_history.dart';
import '../overlay/editor_overlay.dart';
import '../overlay/editor_zone_badge.dart';
import '../slots/editor_selection_region.dart';
import '../slots/editor_slot.dart';
import '../slots/provided_slot_scope.dart';
import '../slots/slot_removal.dart';
import '../slots/slot_size_editor.dart';
import '../slots/slot_wrapping.dart';
import 'native_editor/native_property_control.dart';
import 'native_editor/native_region_slot.dart';

export 'native_editor/native_property_control.dart';
export 'native_editor/native_region_slot.dart';

part 'native_editor/native_editor_addition.dart';
part 'native_editor/native_editor_dialogs.dart';
part 'native_editor/native_editor_interactions.dart';
part 'native_editor/native_editor_regions.dart';
part 'native_editor/native_editor_selection.dart';
part 'native_editor/native_editor_slots.dart';

/// Shared selection, menus, switches and slot catalog for native adapters.
class NativeComponentEditor extends StatefulWidget {
  /// Crée un [NativeComponentEditor].
  const NativeComponentEditor({
    this.id,
    this.behaviours,
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
    this.exportConfig,
    super.key,
  });

  final String? id;
  final String label;
  final NativeComponentConfig config;

  /// Configuration personnalisée à retourner lors de l'export (ex. `SuperTabConfig`, `SuperTreeViewConfig`, `SuperTableConfig`).
  final ComponentConfig Function()? exportConfig;

  /// Comportements explicites de la surface complete du composant.
  final List<ComponentBehavior>? behaviours;
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

/// État interne de [NativeComponentEditor] gérant l'édition des propriétés et régions natives.
class NativeComponentEditorState extends State<NativeComponentEditor> {
  final _keys = <String, GlobalKey>{};
  final _regionContentKeys = <String, GlobalKey>{};
  final _slotKeys = <String, GlobalKey>{};
  ValueNotifier<bool>? _editMode;
  String? _selected;
  String? _selectedSlot;
  bool _active = false;
  final _hoveredRegionScopes = ValueNotifier<Set<Object>>({});
  List<String> _path = const [];
  Size _layoutSize = Size.zero;
  late final ValueNotifier<NativeComponentConfig> _config =
      _NativeConfigNotifier(widget.config);

  void _setEditorState(VoidCallback fn) => setState(fn);

  /// Indique si le mode édition visuelle est actif.
  bool get editing => _editMode?.value ?? false;

  /// Chemin courant du composant dans l'arbre de sélection.
  List<String> get componentPath => _path;

  /// Indique si le [slotId] de la [region] est actuellement sélectionné.
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
      final resolved = EditorSlotState.resolveFromContext(slotCtx)
          ?.effectiveComponentId;
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

  /// Retourne la définition [NativeRegion] correspondant à [id].
  NativeRegion definition(String id) =>
      widget.regions.firstWhere((region) => region.id == id);

  /// Retourne l'axe effectif de la région [id].
  Axis axisOf(String id) =>
      widget.config.regionAxisOf(id) ?? definition(id).axis;

  /// Retourne la configuration de flux [ZoneFlowConfig] de la région [id].
  ZoneFlowConfig flowOf(String id) => widget.config.regionFlowOf(id);

  /// Retourne la taille fixe éventuelle de la région [id].
  double? sizeOf(String id) => widget.config.regionSizeOf(id);

  /// Indique si la région [id] est activée et disponible.
  bool enabled(String id) =>
      (widget.isRegionAvailable?.call(widget.config, id) ?? true) &&
      (definition(id).required || widget.config.isEnabled(id));

  /// Indique si la région [id] est visible à l'écran.
  bool visible(String id) =>
      enabled(id) && (editing || slotsFor(id).isNotEmpty);

  @override
  void initState() {
    super.initState();
    _config.value = widget.config;
  }

  @override
  void didUpdateWidget(NativeComponentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _config.value = widget.config;
    }
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
    _registerLayoutSelection(scope);
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

  @override
  Widget build(BuildContext context) {
    _validate(widget.config);
    Widget wrapSurface(BuildContext context) {
      final child = widget.builder(context, this);
      if (!widget.editSurface && widget.behaviours == null) {
        return ComponentTooltip(
          componentId: _effectiveComponentId ?? widget.keyPrefix,
          child: child,
        );
      }
      if (!widget.editSurface) {
        return EditorSlot(
          id: _effectiveComponentId,
          exportConfig: widget.exportConfig ?? () => _config.value,
          behaviors: widget.behaviours,
          editable: false,
          child: child,
        );
      }
      return EditorSelectionRegion(
        enabled: editing,
        isZone: true,
        fallback: true,
        selected: _active && _selected == null,
        onSelect: () => select(null),
        child: EditorSlot(
          id: _effectiveComponentId,
          exportConfig: widget.exportConfig ?? () => _config.value,
          behaviors: widget.behaviours,
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
          // Selection paths only affect edit overlays.
          listenable: editing
              ? LayoutSelection.path
              : const AlwaysStoppedAnimation<double>(0),
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

class _NativeConfigNotifier extends ValueNotifier<NativeComponentConfig> {
  _NativeConfigNotifier(super._value) : _current = _value;

  NativeComponentConfig _current;
  bool _postFrameScheduled = false;
  bool _disposed = false;

  @override
  NativeComponentConfig get value => _current;

  @override
  set value(NativeComponentConfig newValue) {
    if (_current == newValue) return;
    _current = newValue;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_postFrameScheduled) {
        _postFrameScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _postFrameScheduled = false;
          if (!_disposed && hasListeners) {
            notifyListeners();
          }
        });
      }
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
