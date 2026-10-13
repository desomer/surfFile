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
    confirmed = await showEditorDialog<bool>(
      context: context,
      target: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
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
      )),
    ) == true;
    } finally {
    if (!confirmed && mounted) _update(initial);
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
    if (_config.value.positioning == SuperLayoutPositioning.grid) {
      zone = SuperLayoutZone.center;
    }
    final slots = _availableSlots(context, includeRegistry: true);
    final id = await showEditorDialog<String>(
      context: context,
      target: _zoneFocusKeys[zone]?.currentContext ?? context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: EditorDialogHeader(
            label: _config.value.positioning == SuperLayoutPositioning.grid
                ? 'Ajouter un slot dans la grille'
                : 'Ajouter un slot dans ${widget.zoneLabel(zone)}',
          ),
          children: [
            if (!slots.any((slot) => slot.visible))
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text('Aucun slot visible disponible.'),
              ),
            for (final slot in slots)
              if (slot.visible)
                SimpleDialogOption(
                  key: ValueKey('super-layout-add-slot-${slot.id}'),
                  onPressed: () => Navigator.of(dialogContext).pop(slot.id),
                  child: Text(slot.label),
                ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );
    if (id == null || !mounted) return;
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
    _update(
      widget.onSlotAdded(
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
            type: supplied ? null : id,
          ),
        ),
      ),
    );
  }
}
