import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../../models/native_component_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/component_tag_filter.dart';
import '../../../models/registry.dart';
import '../dialogs/editor_dialog.dart';
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
    this.menuIcon,
    this.menuType,
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
  final IconData? menuIcon;
  final String? menuType;
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
  final _hoveredRegionScopes = ValueNotifier<Set<Object>>({});
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
      _hoveredRegionScopes.value = {};
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
            label: entry.value,
            tags: _tagsForType(entry.key),
            placementTags: _placementTagsForType(entry.key),
            configurator: _addConfiguratorOf(entry.key),
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
      insert: (plan, component) async =>
          _insertAround(region, slot, plan, component),
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
          next = NativeComponentConfig(
            useDefaultNavigation: next.useDefaultNavigation,
            placements: next.placements,
            slotTypes: next.slotTypes,
            regions: next.regions,
            slotPreferredSizes: preferred,
            slotSizeConstraints: constraints,
            slotLabels: next.slotLabels,
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
            slotLabels: current.slotLabels,
          ),
        );
      },
    );
  }

  bool _showOverlay() {
    final path = LayoutSelection.path.value;
    return editing &&
        _active &&
        path.length >= _path.length &&
        path.length <= _path.length + 1 &&
        List.generate(
          _path.length,
          (index) => path[index] == _path[index],
        ).every((value) => value);
  }

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

  /// Decorates a native property without changing the adapter's composition.
  Widget region(
    String id, {
    Widget? child,
    SlotImplementation? item,
    bool showBadge = true,
  }) {
    final spec = definition(id);
    final slots = item == null ? slotsFor(id) : [item];
    final overlay = _showOverlay();
    final selected = _selected == id;
    final emphasis = LabelEmphasis(
      scopes: _hoveredRegionScopes,
      scope: id,
      onHover: (_, _, value) => _setRegionHovered(id, value),
    );
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
          onSelectContent: editing ? (slot) => _selectSlot(id, slot) : null,
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
              ? (slot) async => removeSlotInstance(
                  context,
                  id: slot.id,
                  type: _config.value.slotTypeOf(slot.id),
                  containerKind: EditorConfigKind.nativeComponent,
                  unplace: () => _update(_config.value.withoutSlot(slot.id)),
                )
              : null,
          onEditPreferredSize: editing ? _editSize : null,
          wrapActionsForSlot: editing
              ? (slot) => wrapActionsForSlot(id, slot)
              : null,
          insertionForSlot: editing
              ? (slot) => insertionForSlot(id, slot)
              : null,
        );
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
            label: spec.label,
            menuTitle: widget.label,
            menuSubtitle: () => spec.label,
            menuIcon: widget.menuIcon,
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
                                actions:
                                    widget.regionActions?.call(id) ?? const [],
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
    return ProvidedSlotScope(
      slots: widget.slots,
      child: EditorAddZones(
        label: widget.label,
        enabled: editing,
        zones: _addZones,
        child: ListenableBuilder(
          listenable: LayoutSelection.path,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              _layoutSize = Size(
                constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
                constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
              );
              final child = widget.builder(context, this);
              if (!widget.editSurface) return child;
              return EditorSelectionRegion(
                enabled: editing,
                isZone: true,
                fallback: true,
                selected: _active && _selected == null,
                onSelect: () => select(null),
                child: EditorSlot(
                  label: widget.settingsTitle,
                  menuTitle: widget.label,
                  menuType: widget.menuType,
                  menuIcon: widget.menuIcon,
                  editable: true,
                  onEdit: configure,
                  onContextMenu: (_) => select(null),
                  child: child,
                ),
              );
            },
          ),
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
