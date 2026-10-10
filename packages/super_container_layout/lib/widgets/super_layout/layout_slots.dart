part of '../super_layout.dart';

extension _SuperLayoutSlots on SuperLayoutState {
  List<SlotImplementation> _availableSlots(
    BuildContext context, {
    bool? includeRegistry,
  }) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final ids = {for (final slot in widget.slots) slot.id};
    return [
      ...widget.slots,
      if (registry != null)
        for (final entry in registry.components.entries)
          if (entry.value.isAvailable?.call(context) ?? true)
            if (!ids.contains(entry.value.slotId))
              entry.value.createSlot(
                entry.value.slotId ?? _registrySlotId(entry.key, ids),
              ),
      if (includeRegistry == true && registry != null)
        for (final entry in registry.registry.entries)
          _createRegistrySlot(
            entry.key,
            entry.value,
            _registrySlotId(entry.key, ids),
          ),
    ];
  }

  BuilderSlot _createRegistrySlot(
    String key,
    ComponentBuilder component,
    String id,
  ) => BuilderSlot(
    id: id,
    label: 'Registre : $key',
    builder: (_) => component.getWidget(XuiBuildCtx(id: id)),
  );

  String _registrySlotId(String key, Set<String> slotIds) {
    var id = 'registry:${Uri.encodeComponent(key)}';
    while (slotIds.contains(id)) {
      id = 'registry:$id';
    }
    return id;
  }

  /// Resout uniquement le slot demande, sans construire les autres slots.
  /// Retourne aussi les slots masques ; un identifiant inconnu renvoie null.
  SlotImplementation? _searchSlot(String id) {
    final type = config.slotTypeOf(id);
    final registry = SuperApp.maybeOf(context)?.registry;
    final ids = <String>{};
    SlotImplementation? supplied;
    for (final slot in widget.slots) {
      ids.add(slot.id);
      if (slot.id == type) supplied = slot;
    }
    if (registry == null) return supplied;

    for (final entry in registry.registry.entries) {
      if (_registrySlotId(entry.key, ids) == type) {
        return _createRegistrySlot(entry.key, entry.value, id);
      }
    }
    if (supplied != null) return supplied;

    RegisteredComponent? component;
    for (final entry in registry.components.entries) {
      final candidate = entry.value;
      if (ids.contains(candidate.slotId)) continue;
      if ((candidate.slotId ?? _registrySlotId(entry.key, ids)) == type &&
          (candidate.isAvailable?.call(context) ?? true)) {
        component = candidate;
      }
    }
    return component?.createSlot(id);
  }

  /// Slots visibles rangés dans la zone de contenu [content], dans l'ordre de
  /// [SuperLayoutConfig.placements] ; un identifiant inconnu est ignoré.
  List<SlotImplementation> _slotsOf(
    SuperLayoutConfig config,
    SuperLayoutZone content,
  ) {
    final ids = config.placementsOf(content);
    if (ids.isEmpty) return const [];
    return [
      for (final id in ids)
        if (searchSlot(id) case final slot? when slot.visible) slot,
    ];
  }

  bool _hasContent(SuperLayoutConfig config, SuperLayoutZone content) =>
      _slotsOf(config, content).isNotEmpty;

  Widget _contentOf(
    SuperLayoutConfig config,
    SuperLayoutZone zone,
    Set<SuperLayoutZone> autoSides,
    bool editMode,
    Size layoutSize,
  ) {
    final content = config.contentZone(zone);
    final slots = _slotsOf(config, content);
    if (slots.isEmpty) {
      return _ZonePlaceholder(
        zone: zone,
        showLabel: !(editMode && widget.showZoneNames && widget.editable),
      );
    }
    final auto = autoSides.contains(zone);
    final axis = config.axisOf(zone);
    final autoHeight =
        auto &&
        (zone == SuperLayoutZone.north || zone == SuperLayoutZone.south);
    final autoWidth =
        auto && (zone == SuperLayoutZone.west || zone == SuperLayoutZone.east);
    return SlotStack(
      slots: slots,
      axis: axis,
      preferredSizes: config.slotPreferredSizes,
      sizeConstraints: config.slotSizeConstraints,
      layoutSize: layoutSize,
      onEditPreferredSize: editMode && widget.editable
          ? _editSlotPreferredSize
          : null,
      onRemoveSlot: editMode && widget.editable
          ? (slot) async {
              if (mounted) _update(_config.value.withoutSlot(slot.id));
            }
          : null,
      showLabels: editMode,
      emphasis: _emphasisFor(zone),
      zoneLabel: zone.label,
      mover: editMode && widget.editable
          ? SlotMover(
              owner: this,
              onMove: (id, {beforeId, afterId}) => _update(
                _config.value.withSlotMoved(
                  id,
                  content,
                  beforeId: beforeId,
                  afterId: afterId,
                ),
              ),
            )
          : null,
      expand: !(axis == Axis.vertical ? autoHeight : autoWidth),
      stretch: !(axis == Axis.vertical ? autoWidth : autoHeight),
    );
  }
}
