part of 'super_layout.dart';

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
    label: key,
    tags: component.tags,
    menuIcon: component.menuIcon,
    builder: (_) => component.getWidget(XuiBuildCtx(id: id)),
  );

  String _registrySlotId(String key, Set<String> slotIds) {
    var id = 'registry:${Uri.encodeComponent(key)}';
    while (slotIds.contains(id)) {
      id = 'registry:$id';
    }
    return id;
  }

  /// Settings of the add wizard for a slot returned by [_availableSlots].
  ComponentAddConfigurator<Object>? _addConfiguratorOf(
    BuildContext context,
    String slotId,
  ) {
    final registry = SuperApp.maybeOf(context)?.registry;
    if (registry == null) return null;
    final ids = {for (final slot in widget.slots) slot.id};
    if (ids.contains(slotId)) return null;
    for (final entry in registry.registry.entries) {
      if (_registrySlotId(entry.key, ids) == slotId) {
        return entry.value.addConfigurator;
      }
    }
    for (final entry in registry.components.entries) {
      if ((entry.value.slotId ?? _registrySlotId(entry.key, ids)) == slotId) {
        return entry.value.addConfigurator;
      }
    }
    return null;
  }

  /// Placement tags of a registry slot returned by [_availableSlots].
  Set<String> _placementTagsOf(BuildContext context, String slotId) {
    final registry = SuperApp.maybeOf(context)?.registry;
    if (registry == null) return const {};
    final ids = {for (final slot in widget.slots) slot.id};
    if (ids.contains(slotId)) return const {};
    for (final entry in registry.registry.entries) {
      if (_registrySlotId(entry.key, ids) == slotId) {
        return entry.value.placementTags;
      }
    }
    for (final entry in registry.components.entries) {
      if ((entry.value.slotId ?? _registrySlotId(entry.key, ids)) == slotId) {
        return entry.value.placementTags;
      }
    }
    return const {};
  }

  /// Display label in the add wizard for a slot returned by [_availableSlots].
  String _addLabelOf(BuildContext context, SlotImplementation slot) {
    final registry = SuperApp.maybeOf(context)?.registry;
    if (registry == null) return slot.label;
    final ids = {for (final item in widget.slots) item.id};
    if (ids.contains(slot.id)) return slot.label;
    for (final entry in registry.registry.entries) {
      if (_registrySlotId(entry.key, ids) == slot.id) {
        return entry.value.label ?? slot.label;
      }
    }
    return slot.label;
  }

  /// Preview builder in the add wizard for a slot returned by [_availableSlots].
  WidgetBuilder? _previewBuilderOf(BuildContext context, String slotId) {
    final registry = SuperApp.maybeOf(context)?.registry;
    if (registry == null) return null;
    final ids = {for (final slot in widget.slots) slot.id};
    if (ids.contains(slotId)) return null;
    for (final entry in registry.registry.entries) {
      if (_registrySlotId(entry.key, ids) == slotId) {
        return entry.value.previewBuilder;
      }
    }
    for (final entry in registry.components.entries) {
      if ((entry.value.slotId ?? _registrySlotId(entry.key, ids)) == slotId) {
        return entry.value.previewBuilder;
      }
    }
    return null;
  }

  /// Resout uniquement le slot demande, sans construire les autres slots.
  /// Retourne aussi les slots masques ; un identifiant inconnu renvoie null.
  SlotImplementation? _searchSlot(
    String id, {
    SuperLayoutConfig? configuration,
  }) {
    final type = (configuration ?? config).slotTypeOf(id);
    final registry = SuperApp.maybeOf(context)?.registry;
    final ids = <String>{};
    SlotImplementation? supplied;
    for (final slot in widget.slots) {
      ids.add(slot.id);
      if (slot.id == type) supplied = slot;
    }
    supplied ??=
        ProvidedSlotScope.find(context, id) ??
        ProvidedSlotScope.find(context, type);
    if (supplied != null && supplied.id != id) {
      final source = supplied;
      supplied = BuilderSlot(
        id: id,
        label: source.label,
        sizing: source.sizing,
        preferredSize: source.preferredSize,
        visible: source.visible,
        showLabel: source.showLabel,
        labelAlignment: source.labelAlignment,
        tags: source.tags,
        menuIcon: source.menuIcon,
        builder: (_) => source,
      );
    }
    if (registry == null) return supplied;

    for (final entry in registry.registry.entries) {
      if (_registrySlotId(entry.key, ids) == type ||
          'factory:${entry.key}' == type) {
        return _createRegistrySlot(entry.key, entry.value, id);
      }
    }
    if (supplied != null) return supplied;

    RegisteredComponent? component;
    for (final entry in registry.components.entries) {
      final candidate = entry.value;
      if (ids.contains(candidate.slotId)) continue;
      if ((candidate.slotId == type ||
              _registrySlotId(entry.key, ids) == type ||
              'component:${candidate.slotId ?? entry.key}' == type) &&
          (candidate.isAvailable?.call(context) ?? true)) {
        component = candidate;
      }
    }
    return component?.createSlot(id);
  }

  List<EditorSlotWrapAction> _wrapActionsForSlot(SlotImplementation slot) {
    final zone = _displayZoneOf(_config.value, slot.id);
    return slotWrapActions(
      registry: SuperApp.maybeOf(context)?.registry,
      acceptsTags: (tags) =>
          zone != null && (widget.zoneTagFilters[zone]?.accepts(tags) ?? true),
      onWrap: (wrapper) async {
        if (!mounted || !_config.value.placedSlotIds.contains(slot.id)) return;
        final registry = SuperApp.maybeOf(context)!.registry!;
        final current = _config.value;
        wrapSlotInstance(
          context,
          registry: registry,
          wrapper: wrapper,
          id: slot.id,
          type: current.slotTypeOf(slot.id),
          label: slot.label,
          occupiedIds: {
            ...current.placedSlotIds,
            ...widget.slots.map((s) => s.id),
          },
          replace: (id, type) {
            var next = current.withSlotReplaced(slot.id, id, type);
            if (!current.slotPreferredSizes.containsKey(slot.id) &&
                !current.slotSizeConstraints.containsKey(slot.id) &&
                slot.preferredSize != null) {
              next = next.withSlotPreferredSize(id, slot.preferredSize);
            }
            _update(next);
            _selectedSlot.value = id;
          },
        );
      },
    );
  }

  List<EditorSlotWrapAction> _wrapActionsForZone(SuperLayoutZone zone) {
    final current = _config.value;
    final contentZone = current.contentZone(zone);
    final slots = _slotsOf(current, contentZone);
    return zoneChildrenWrapActions(
      registry: SuperApp.maybeOf(context)?.registry,
      hasChildren: slots.isNotEmpty,
      acceptsTags: (tags) => widget.zoneTagFilters[zone]?.accepts(tags) ?? true,
      onWrapInCard: () async {
        if (!mounted) return;
        final config = _config.value;
        final content = config.contentZone(zone);
        final children = _slotsOf(config, content);
        if (children.isEmpty) return;
        final registry = SuperApp.maybeOf(context)?.registry;
        if (registry == null) return;
        final childIds = [for (final slot in children) slot.id];
        final movedSet = childIds.toSet();
        wrapZoneChildrenInCard(
          context,
          registry: registry,
          childIds: childIds,
          slotTypes: {for (final id in childIds) id: config.slotTypeOf(id)},
          slotLabels: {
            for (final slot in children)
              slot.id: config.slotLabels[slot.id] ?? slot.label,
          },
          slotPreferredSizes: {
            for (final slot in children)
              if (config.slotPreferredSizes.containsKey(slot.id))
                slot.id: config.slotPreferredSizes[slot.id]
              else if (!config.slotSizeConstraints.containsKey(slot.id) &&
                  slot.preferredSize != null)
                slot.id: slot.preferredSize,
          },
          slotSizeConstraints: {
            for (final id in childIds)
              id: ?config.slotSizeConstraints[id],
          },
          axis: config.axisOf(zone),
          flow: config.flowOf(zone),
          occupiedIds: {
            ...config.placedSlotIds,
            ...widget.slots.map((s) => s.id),
          },
          replaceChildren: (cardId, cardType) {
            final stillReferenced = <String>{
              for (final entry in config.placements.entries)
                if (entry.key != content) ...entry.value,
            };
            final removedOnly = movedSet.difference(stillReferenced);
            final next = config
                .copyWith(
                  placements: {
                    ...config.placements,
                    content: [cardId],
                  },
                  slotTypes: {
                    for (final entry in config.slotTypes.entries)
                      if (!removedOnly.contains(entry.key))
                        entry.key: entry.value,
                    cardId: cardType,
                  },
                  slotLabels: {
                    for (final entry in config.slotLabels.entries)
                      if (!removedOnly.contains(entry.key))
                        entry.key: entry.value,
                  },
                  slotPreferredSizes: {
                    for (final entry in config.slotPreferredSizes.entries)
                      if (!removedOnly.contains(entry.key))
                        entry.key: entry.value,
                  },
                  slotSizeConstraints: {
                    for (final entry in config.slotSizeConstraints.entries)
                      if (!removedOnly.contains(entry.key))
                        entry.key: entry.value,
                  },
                )
                .withAxis(zone, Axis.vertical)
                .withZoneFlow(zone, const ZoneFlowConfig());
            _update(next);
            _selectedSlot.value = cardId;
          },
        );
      },
    );
  }

  /// Contextual addition around [slot]: in its zone stack, after switching a
  /// single-slot zone's axis, or by wrapping it in a new `Layout`.
  EditorSlotInsertion? _insertionForSlot(SlotImplementation slot) {
    final config = _config.value;
    final zone = _displayZoneOf(config, slot.id);
    final registry = SuperApp.maybeOf(context)?.registry;
    if (zone == null || registry == null) return null;
    final grid = config.positioning == SuperLayoutPositioning.grid;
    final filter = widget.zoneTagFilters[zone];
    final layout = registry.registry[EditorSlotWrapper.layout.factory];
    return EditorSlotInsertion(
      label: slot.label,
      host: InsertionHost(
        axis: config.axisOf(zone),
        stacked: !grid,
        axisMutable:
            !grid &&
            config
                .placementsOf(config.contentZone(zone))
                .every((id) => id == slot.id),
        canWrap: layout != null && (filter?.accepts(layout.tags) ?? true),
      ),
      acceptsTags: (tags) => filter?.accepts(tags) ?? true,
      zoneTags: filter?.include ?? const {},
      targetContext: () => _slotFocusKeys[slot.id]?.currentContext,
      insert: (plan, component) async => _insertAround(slot, plan, component),
    );
  }

  ComponentAddPlacementPreview _zonePreview(
    SuperLayoutZone zone, {
    String? beforeId,
    String? label,
  }) {
    final grid = _config.value.positioning == SuperLayoutPositioning.grid;
    final zoneLabel = grid ? 'Grille' : widget.zoneLabel(zone);
    return ComponentAddPlacementPreview.inZone(
      zoneContext: () => _zoneFocusKeys[zone]?.currentContext,
      containerContext: () => mounted ? context : null,
      axis: () => _config.value.positioning == SuperLayoutPositioning.grid
          ? null
          : _config.value.axisOf(zone),
      inactiveEdge: switch (zone) {
        SuperLayoutZone.north ||
        SuperLayoutZone.nw ||
        SuperLayoutZone.ne => InsertDirection.up,
        SuperLayoutZone.south ||
        SuperLayoutZone.sw ||
        SuperLayoutZone.se => InsertDirection.down,
        SuperLayoutZone.west => InsertDirection.left,
        SuperLayoutZone.east => InsertDirection.right,
        SuperLayoutZone.center => null,
      },
      beforeContext: beforeId == null
          ? null
          : () => _slotFocusKeys[beforeId]?.currentContext,
      lastSiblingContext: () {
        final current = _config.value;
        final slots = _slotsOf(current, current.contentZone(zone));
        return slots.isEmpty
            ? null
            : _slotFocusKeys[slots.last.id]?.currentContext;
      },
      label: label ?? zoneLabel,
      icon: beforeId == null ? Icons.add_box_outlined : Icons.vertical_align_top,
    );
  }

  void _insertAround(
    SlotImplementation slot,
    InsertionPlan plan,
    InsertedComponent component,
  ) {
    final current = _config.value;
    final registry = SuperApp.maybeOf(context)?.registry;
    if (!mounted ||
        registry == null ||
        !current.placedSlotIds.contains(slot.id)) {
      return;
    }
    final occupied = {
      ...current.placedSlotIds,
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
            if (!current.slotPreferredSizes.containsKey(slot.id) &&
                !current.slotSizeConstraints.containsKey(slot.id) &&
                slot.preferredSize != null) {
              next = next.withSlotPreferredSize(id, slot.preferredSize);
            }
            _update(next);
            _selectedSlot.value = id;
          },
        );
      case DirectInsertion(:final axis):
        final zone = _displayZoneOf(current, slot.id)!;
        final content = current.contentZone(zone);
        final id = uniqueInstanceId(
          context,
          registry: registry,
          occupiedIds: occupied,
        );
        var next = axis == null ? current : current.withAxis(zone, axis);
        next = next.withSlotMoved(
          id,
          content,
          beforeId: plan.newFirst ? slot.id : null,
          afterId: plan.newFirst ? null : slot.id,
          type: component.type,
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
        _commitAddition(next, id, zone, component, before: current);
    }
  }

  /// Applies the settings, sizing and label of an added instance [id] already
  /// placed in [next], as a single history step.
  void _commitAddition(
    SuperLayoutConfig next,
    String id,
    SuperLayoutZone zone,
    InsertedComponent component, {
    required SuperLayoutConfig before,
  }) {
    final content = before.contentZone(zone);
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      component.configure(id);
      if (_searchSlot(id, configuration: next) case final added?) {
        next = widget.onSlotAdded(
          SlotAddition(
            slotId: id,
            component: added,
            zone: zone,
            contentZone: content,
            existingSlots: List.unmodifiable(_slotsOf(before, content)),
            config: next,
          ),
        );
      }
      if (component.size case final size?) {
        next = next.copyWith(
          slotPreferredSizes: {...next.slotPreferredSizes}..remove(id),
          slotSizeConstraints: {...next.slotSizeConstraints, id: size},
        );
      }
      if (component.label case final label?) {
        next = next.withSlotLabel(id, label);
      }
      _update(next);
    } finally {
      history?.commitTransaction();
    }
  }

  /// Zones offered by the contextual add wizard: the selected one first, then
  /// the other visible zones, then the hidden sides, enabled by the addition.
  List<EditorAddZone> _addZones() {
    final config = _config.value;
    final grid = config.positioning == SuperLayoutPositioning.grid;
    final action = _actionZone;
    final visible = config.visibleZones;
    final zones = grid
        ? const [SuperLayoutZone.center]
        : [
            action,
            for (final zone in SuperLayoutZone.values)
              if (zone != action && visible.contains(zone)) zone,
            for (final zone in SuperLayoutZone.values)
              if (zone.isSide && !visible.contains(zone)) zone,
          ];
    return [
      for (final zone in zones)
        EditorAddZone(
          id: zone.name,
          label: grid ? 'Grille' : widget.zoneLabel(zone),
          hint: grid || visible.contains(zone)
              ? null
              : 'Active la zone ${widget.zoneLabel(zone)}',
          accepts: (tags) => widget.zoneTagFilters[zone]?.accepts(tags) ?? true,
          zoneTags: widget.zoneTagFilters[zone]?.include ?? const {},
          preview: _zonePreview(zone),
          insert: (component) async => _insertInZone(zone, component),
        ),
    ];
  }

  void _insertInZone(SuperLayoutZone zone, InsertedComponent component) {
    if (!mounted) return;
    final current = _config.value;
    if (current.positioning == SuperLayoutPositioning.grid) {
      zone = SuperLayoutZone.center;
    }
    final id = uniqueInstanceId(
      context,
      registry: SuperApp.maybeOf(context)?.registry,
      occupiedIds: {...current.placedSlotIds, ...widget.slots.map((s) => s.id)},
    );
    final shown = zone.isSide && !current.hasSide(zone)
        ? current.withSide(zone, true)
        : current;
    _commitAddition(
      shown.withSlotMoved(id, shown.contentZone(zone), type: component.type),
      id,
      zone,
      component,
      before: current,
    );
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
    final fitScope = SlotContentFitScope.maybeOf(context);
    final shrinkWidth = widget.shrinkWrap || (fitScope?.fitWidth ?? false);
    final shrinkHeight = widget.shrinkWrap || (fitScope?.fitHeight ?? false);
    if (slots.isEmpty) {
      final flow = config.flowOf(zone);
      final axis = config.axisOf(zone);
      final hasFlow = config.zoneFlows.containsKey(content) ||
          config.zoneFlows.containsKey(zone);
      final stretchCross =
          hasFlow && flow.crossAxisAlignment == CrossAxisAlignment.stretch;
      final stretchWidth = stretchCross && axis == Axis.vertical;
      final stretchHeight = stretchCross && axis == Axis.horizontal;
      if (shrinkWidth || shrinkHeight) {
        return SizedBox(
          width: (shrinkWidth && !stretchWidth) ? 16 : double.infinity,
          height: (shrinkHeight && !stretchHeight) ? 16 : double.infinity,
        );
      }
      return _ZonePlaceholder(
        zone: zone,
        label: widget.zoneLabel(zone),
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
    final canEditSlots =
        widget.editable &&
        (StyleEditScope.controllerOf(context)?.value ?? false);
    return SlotStack(
      slots: slots,
      focusKeys: _slotFocusKeys,
      axis: axis,
      flow: config.flowOf(zone),
      preferredSizes: config.slotPreferredSizes,
      sizeConstraints: config.slotSizeConstraints,
      layoutSize: layoutSize,
      selectedSlotId: _selected.value == zone ? _selectedSlot.value : null,
      onResizeSlot: editMode && widget.editable ? _applySlotDimensions : null,
      onSelectSlot: editMode ? (slot) => _selectSlot(zone, slot) : null,
      onSelectContent: canEditSlots
          ? (slot) {
              _selectedSlot.value = slot.id;
              _selected.value = zone;
              _LayoutEditSelection.activate(this);
            }
          : null,
      onEditPreferredSize: canEditSlots ? _editSlotPreferredSize : null,
      dimensionDelegateForSlot: canEditSlots ? _buildSlotSizeDelegate : null,
      wrapActionsForSlot: canEditSlots ? _wrapActionsForSlot : null,
      insertionForSlot: canEditSlots ? _insertionForSlot : null,
      onRemoveSlot: canEditSlots
          ? (slot) async {
              if (mounted) _removeSlot(slot.id);
            }
          : null,
      showLabels: editMode,
      emphasis: _emphasisFor(zone),
      zoneLabel: widget.zoneLabel(zone),
      mover: editMode && widget.editable
          ? SlotMover(
              owner: this,
              canMove: (id) => _canMoveSlot(id, zone),
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
      expand:
          !(axis == Axis.vertical
              ? (shrinkHeight || autoHeight)
              : (shrinkWidth || autoWidth)),
      stretch:
          !(axis == Axis.vertical
              ? (shrinkWidth || autoWidth)
              : (shrinkHeight || autoHeight)),
    );
  }
}
