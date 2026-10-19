import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/native_component_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/component_tag_filter.dart';
import '../../models/registry.dart';
import '../editing/editor_dialog.dart';
import '../editing/editor_overlay.dart';
import '../editing/slot_size_editor.dart';
import '../super_layout/layout_selection.dart';
import '../super_layout/slot_implementation.dart';
import '../surfaces/super_container.dart';

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
    super.key,
  });

  final NativePreferredSizeWidget child;
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
    this.emptySize = const Size(double.infinity, kToolbarHeight),
    this.fillSize,
    this.tagFilter = const ComponentTagFilter(),
  });

  final String id;
  final String label;
  final bool required;
  final bool single;
  final Axis axis;
  final bool expand;
  final bool stretch;
  final Size emptySize;
  final Size? fillSize;
  final ComponentTagFilter tagFilter;
}

/// Shared selection, menus, switches and slot catalog for native adapters.
class NativeComponentEditor extends StatefulWidget {
  const NativeComponentEditor({
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
    this.regionActions,
    this.onSlotAdded,
    this.editSurface = false,
    this.settingsControls,
    this.isRegionAvailable,
    super.key,
  });

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
  final List<Widget> Function(String region)? regionActions;
  final NativeSlotAddedCallback? onSlotAdded;
  final bool editSurface;
  final List<Widget> Function(
    NativeComponentConfig config,
    ValueChanged<NativeComponentConfig> onChanged,
  )?
  settingsControls;
  final bool Function(NativeComponentConfig config, String region)?
  isRegionAvailable;

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
  List<String> _path = const [];
  Size _layoutSize = Size.zero;
  final _config = ValueNotifier<NativeComponentConfig>(NativeComponentConfig());

  bool get editing => _editMode?.value ?? false;
  NativeRegion definition(String id) =>
      widget.regions.firstWhere((region) => region.id == id);
  bool enabled(String id) =>
      (widget.isRegionAvailable?.call(widget.config, id) ?? true) &&
      (definition(id).required || widget.config.isEnabled(id));
  bool visible(String id) =>
      enabled(id) && (editing || slotsFor(id).isNotEmpty);

  Size? preferredSizeFor(SlotImplementation slot) {
    if (widget.config.slotPreferredSizes.containsKey(slot.id)) {
      return widget.config.slotPreferredSizes[slot.id];
    }
    return switch (slot) {
      NativePreferredSizeWidget native => native.preferredSizeIn(context),
      _ => slot.preferredSize,
    };
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
    _path = [...?scope?.path, widget.label];
    final mode = StyleEditScope.controllerOf(context);
    if (mode != _editMode) {
      _editMode?.removeListener(_editingChanged);
      _editMode = mode;
      _editMode?.addListener(_editingChanged);
    }
    LayoutSelection.register(
      this,
      _path,
      (label) => select(
        widget.regions.where((region) => region.label == label).firstOrNull?.id,
      ),
      parent: scope?.owner,
      onDeselect: _clear,
    );
  }

  void _editingChanged() {
    if (editing && LayoutSelectionScope.of(context) == null) {
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
    });
    LayoutSelection.report(this, const []);
  }

  void select(String? id, [BuildContext? target]) {
    if (!mounted) return;
    LayoutSelection.deselectDescendants(this);
    setState(() {
      _active = true;
      _selected = id;
      _selectedSlot = null;
    });
    LayoutSelection.report(
      this,
      [..._path, if (id != null) definition(id).label],
      clear: _clear,
      focusContext: target ?? _keys[id]?.currentContext ?? context,
    );
  }

  void _selectSlot(String region, SlotImplementation slot) {
    select(region);
    setState(() => _selectedSlot = slot.id);
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
        config.regions.keys.any((id) => !ids.contains(id))) {
      throw StateError('Unknown region in ${widget.label}.');
    }
    for (final region in widget.regions) {
      if ((region.required && config.regions[region.id] == false) ||
          (region.single && config.slotsOf(region.id).length > 1)) {
        throw StateError('Invalid native region ${widget.label}.${region.id}.');
      }
    }
  }

  Future<void> configure() async {
    final activated = <String>{};
    select(null);
    await showEditorDialog<void>(
      context: context,
      target: context,
      builder: (dialogContext) => AlertDialog(
        key: ValueKey('${widget.keyPrefix}-settings'),
        title: Text(widget.settingsTitle),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: ValueListenableBuilder<NativeComponentConfig>(
              valueListenable: _config,
              builder: (context, config, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...?widget.settingsControls?.call(config, _update),
                  for (final region in widget.regions)
                    if (!region.required &&
                        (widget.isRegionAvailable?.call(config, region.id) ??
                            true))
                      SwitchListTile(
                        key: ValueKey(
                          '${widget.keyPrefix}-switch-${region.id}',
                        ),
                        title: Text(region.label),
                        value: config.isEnabled(region.id),
                        onChanged: (value) {
                          _update(
                            _config.value.withRegionEnabled(region.id, value),
                          );
                          if (value) activated.add(region.id);
                        },
                      ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
    if (mounted) widget.onConfigured?.call(activated.where(enabled).toSet());
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
    final supplied = provided[id] ?? provided[type];
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
      SlotImplementation? slot = provided[id] ?? provided[type];
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
                    child: child,
                  )
                : BuilderSlot(
                    id: id,
                    label: factoryKey,
                    tags: factory.tags,
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
        if (source.id == id) {
          result.add(source);
        } else if (source case NativePreferredSizeWidget native) {
          result.add(
            NativeWidgetSlot(
              id: id,
              label: source.label,
              tags: source.tags,
              child: native,
            ),
          );
        } else {
          result.add(
            BuilderSlot(
              id: id,
              label: source.label,
              sizing: source.sizing,
              preferredSize: source.preferredSize,
              showLabel: source.showLabel,
              labelAlignment: source.labelAlignment,
              tags: source.tags,
              builder: (_) => source,
            ),
          );
        }
      }
    }
    return result;
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
    final selected = await showEditorDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Ajouter dans ${definition(region).label}'),
        children: [
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Text('Aucun slot disponible.'),
            ),
          for (final entry in candidates.entries)
            SimpleDialogOption(
              key: ValueKey('${widget.keyPrefix}-add-slot-${entry.key}'),
              onPressed: () => Navigator.of(dialogContext).pop(entry.key),
              child: Text(entry.value),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    if (!definition(region).tagFilter.accepts(_tagsForType(selected))) {
      _reportTagRejection(region);
      return;
    }
    final isProvided = provided.containsKey(selected);
    var id = selected;
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
      type: isProvided ? null : selected,
      replace: definition(region).single,
    );
    final slot =
        provided[selected] ??
        registry?.components.entries
            .where(
              (entry) => _componentType(entry.key, entry.value) == selected,
            )
            .firstOrNull
            ?.value
            .createSlot(id) ??
        BuilderSlot(
          id: id,
          label: candidates[selected]!,
          tags: _tagsForType(selected),
          builder: (_) => registry!.getWidget(
            selected.substring('factory:'.length),
            XuiBuildCtx(id: id),
          ),
        );
    next =
        widget.onSlotAdded?.call(next, region, id, slot, slotsFor(region)) ??
        next;
    _update(next);
  }

  Future<void> _editSize(SlotImplementation slot) async {
    final initial = _config.value;
    await showSlotSizeEditor(
      context: context,
      slot: slot,
      saved: initial.slotSizeConstraints[slot.id],
      legacy: preferredSizeFor(slot),
      changes: _config,
      target: _slotKeys[slot.id]?.currentContext,
      measure: () {
        final layout = context.findRenderObject();
        final slotBox = _slotKeys[slot.id]?.currentContext?.findRenderObject();
        final region = initial.placements.entries
            .where((entry) => entry.value.contains(slot.id))
            .firstOrNull
            ?.key;
        final zoneBox = (_keys['$region:${slot.id}'] ?? _keys[region])
            ?.currentContext
            ?.findRenderObject();
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
          NativeComponentConfig(
            useDefaultNavigation: current.useDefaultNavigation,
            placements: current.placements,
            slotTypes: current.slotTypes,
            regions: current.regions,
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

  bool _showOverlay(String id) {
    final path = LayoutSelection.path.value;
    return editing &&
        _active &&
        path.length >= _path.length &&
        path.length <= _path.length + 1 &&
        List.generate(
          _path.length,
          (index) => path[index] == _path[index],
        ).every((value) => value) &&
        (_selected == null || _selected == id);
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

  /// Decorates a native property without changing the adapter's composition.
  Widget region(
    String id, {
    Widget? child,
    SlotImplementation? item,
    bool showBadge = true,
  }) {
    final spec = definition(id);
    final slots = item == null ? slotsFor(id) : [item];
    final overlay = _showOverlay(id);
    final selected = _selected == id;
    final colors = Theme.of(context).colorScheme;
    final content =
        child ??
        SlotStack(
          slots: slots,
          focusKeys: _slotKeys,
          axis: spec.axis,
          expand: spec.expand,
          stretch: spec.stretch,
          preferredSizes: {
            for (final slot in slots)
              if (slot case NativePreferredSizeWidget native)
                slot.id: native.preferredSizeIn(context),
            ...widget.config.slotPreferredSizes,
            if (spec.fillSize != null)
              for (final slot in slots)
                if (slot.sizing == SlotSizing.fill &&
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
              ? (slot) => _selectSlot(id, slot)
              : null,
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
              ? (slot) async => _update(_config.value.withoutSlot(slot.id))
              : null,
          onEditPreferredSize: editing ? _editSize : null,
        );
    return LayoutSelectionScope(
      owner: this,
      path: [..._path, spec.label],
      child: Builder(
        key: _keys.putIfAbsent(
          item == null ? id : '$id:${item.id}',
          GlobalKey.new,
        ),
        builder: (regionContext) => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if (editing &&
                event.buttons == kPrimaryButton &&
                LayoutSelection.claimPointer(event)) {
              select(id, regionContext);
            }
          },
          child: SuperContainer(
            label: spec.label,
            menuTitle: widget.label,
            decorate: false,
            editable: true,
            onEdit: configure,
            onAdd: () => add(id),
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
              child: Stack(
                children: [
                  if (slots.isEmpty && editing)
                    SizedBox(
                      width: spec.emptySize.width,
                      height: spec.expand
                          ? double.infinity
                          : spec.emptySize.height,
                    )
                  else
                    content,
                  Positioned.fill(
                    child: EditorOverlayVisibility(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          key: selected && overlay
                              ? ValueKey('${widget.keyPrefix}-selected-$id')
                              : null,
                          decoration: BoxDecoration(
                            border: overlay
                                ? Border.all(
                                    color: selected
                                        ? colors.primary
                                        : colors.outlineVariant,
                                    width: selected ? 3 : 1,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (overlay && showBadge)
                    Positioned.fill(
                      child: EditorOverlayVisibility(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Material(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    key: ValueKey(
                                      '${widget.keyPrefix}-select-$id',
                                    ),
                                    onPressed: () => select(
                                      selected ? null : id,
                                      regionContext,
                                    ),
                                    child: Text(spec.label),
                                  ),
                                  IconButton(
                                    key: ValueKey(
                                      '${widget.keyPrefix}-add-$id',
                                    ),
                                    tooltip: 'Ajouter dans ${spec.label}',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.add),
                                    onPressed: () {
                                      select(id, regionContext);
                                      add(id);
                                    },
                                  ),
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
    return ListenableBuilder(
      listenable: LayoutSelection.path,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          _layoutSize = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
          );
          final child = widget.builder(context, this);
          if (!widget.editSurface) return child;
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (editing &&
                  event.buttons == kPrimaryButton &&
                  LayoutSelection.claimPointer(event)) {
                select(null);
              }
            },
            child: SuperContainer(
              label: widget.settingsTitle,
              menuTitle: widget.label,
              decorate: false,
              editable: true,
              onEdit: configure,
              onContextMenu: (_) => select(null),
              child: child,
            ),
          );
        },
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
    super.dispose();
  }
}
