part of 'super_layout.dart';

extension _SuperLayoutDialogs on SuperLayoutState {
  Future<void> _openEditor() async {
    final initial = _config.value;
    final initialInstance = EditorComponentLabel.of(context);
    var label = _displayLabel;
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    var confirmed = false;
    try {
      confirmed =
          await showEditorDialog<bool>(
            context: context,
            target: context,
            barrierDismissible: true,
            barrierColor: Colors.transparent,
            builder: (context) => StatefulBuilder(
              builder: (context, setDialog) => AlertDialog(
                title: EditorDialogHeader(
                  label: label,
                  onLabelChanged: (value) => setDialog(() {
                    label = value;
                    _rename(value);
                  }),
                ),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: ListenableBuilder(
                      listenable: _config,
                      builder: (context, _) => SuperLayoutEditor(
                        config: _config.value,
                        onChanged: _update,
                        zoneLabels: widget.zoneLabels,
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Annuler'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Appliquer'),
                  ),
                ],
              ),
            ),
          ) ==
          true;
    } finally {
      if (!confirmed && mounted) _update(initial, validateTags: false);
      if (!confirmed && mounted && initialInstance != null) {
        initialInstance.onRestore();
      }
      if (confirmed) {
        history?.commitTransaction();
      } else {
        history?.cancelTransaction();
      }
    }
  }

  Future<void> _addSlot(SuperLayoutZone zone) async {
    final grid = _config.value.positioning == SuperLayoutPositioning.grid;
    if (grid) zone = SuperLayoutZone.center;
    final slots = _availableSlots(context, includeRegistry: true)
        .where(
          (slot) => widget.zoneTagFilters[zone]?.accepts(slot.tags) ?? true,
        )
        .toList();
    final initial = _config.value;
    final zones = grid
        ? const [SuperLayoutZone.center]
        : [
            for (final option in SuperLayoutZone.values)
              if (option == zone || initial.visibleZones.contains(option))
                option,
          ];
    final request = await showComponentAddWizard(
      context: context,
      target: _zoneFocusKeys[zone]?.currentContext ?? context,
      title: grid
          ? 'Ajouter un slot dans la grille'
          : 'Ajouter un slot dans ${widget.zoneLabel(zone)}',
      keyPrefix: 'super-layout',
      emptyMessage: 'Aucun slot visible disponible.',
      initialTargetId: zone.name,
      candidates: [
        for (final slot in slots)
          if (slot.visible)
            ComponentAddCandidate(
              id: slot.id,
              label: slot.label,
              tags: slot.tags,
              configurator: _addConfiguratorOf(context, slot.id),
            ),
      ],
      targets: [
        for (final option in zones)
          ComponentAddTarget(
            id: option.name,
            label: grid ? 'Grille' : widget.zoneLabel(option),
            siblings: [
              for (final slot in _slotsOf(initial, initial.contentZone(option)))
                (slot.id, initial.slotLabels[slot.id] ?? slot.label),
            ],
            accepts: (tags) =>
                widget.zoneTagFilters[option]?.accepts(tags) ?? true,
          ),
      ],
    );
    if (request == null || !mounted) return;
    zone = SuperLayoutZone.values.byName(request.targetId);
    final id = request.component.id;
    final config = _config.value;
    final supplied = widget.slots.any((slot) => slot.id == id);
    var instanceId = id;
    if (!supplied) {
      final used = {
        ...widget.slots.map((slot) => slot.id),
        ...config.placements.values.expand((ids) => ids),
      };
      do {
        instanceId = shortid.generate();
      } while (used.contains(instanceId));
    }

    final contentZone = config.contentZone(zone);
    final component = slots.firstWhere((slot) => slot.id == id);
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      request.applyConfiguration(
        SuperApp.maybeOf(context)?.registry,
        instanceId,
      );
      var next = widget.onSlotAdded(
        SlotAddition(
          slotId: instanceId,
          component: component,
          zone: zone,
          contentZone: contentZone,
          existingSlots: List.unmodifiable(
            _slotsOf(
              config,
              contentZone,
            ).where((slot) => slot.id != instanceId),
          ),
          config: config.withSlotMoved(
            instanceId,
            contentZone,
            beforeId: request.beforeId,
            type: supplied ? null : id,
          ),
        ),
      );
      if (request.size case final size?) {
        next = next.copyWith(
          slotPreferredSizes: {...next.slotPreferredSizes}..remove(instanceId),
          slotSizeConstraints: {...next.slotSizeConstraints, instanceId: size},
        );
      }
      if (request.label case final label?) {
        next = next.withSlotLabel(instanceId, label);
      }
      _update(next);
    } finally {
      history?.commitTransaction();
    }
  }
}
