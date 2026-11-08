// Assistant d'ajout de composant et insertion contextuelle (autour d'un slot ou dans une région)
// pour [NativeComponentEditorState].
part of '../native_component_editor.dart';

/// Extension gérant l'ajout et l'insertion contextuelle de composants dans [NativeComponentEditorState].
extension NativeComponentEditorAddition on NativeComponentEditorState {
  /// Ouvre l'assistant d'ajout de composant ciblant initialement la [region].
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

  /// Contrat d'ajout contextuel autour de [slot] : directement dans [region]
  /// lorsque la direction suit son axe, sinon en l'enveloppant dans un `Layout`.
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

  /// Applique les paramètres, le dimensionnement et le libellé d'une instance [id]
  /// ajoutée dans [next], au sein d'une transaction d'historique unique.
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

  /// Régions proposées par l'assistant d'ajout contextuel : la région sélectionnée
  /// en premier, puis les autres régions actives, puis les régions désactivées mais
  /// disponibles (activées lors de l'ajout).
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

  /// Tags de placement d'un type du registre (`factory:` ou `component:`).
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
}
