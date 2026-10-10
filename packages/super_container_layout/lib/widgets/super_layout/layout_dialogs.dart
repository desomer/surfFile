part of '../super_layout.dart';

extension _SuperLayoutDialogs on SuperLayoutState {
  Future<void> _openEditor() async {
    final initial = _config.value;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (context) => AlertDialog(
        title: Text(widget.label),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: _config,
              builder: (context, _) =>
                  SuperLayoutEditor(config: _config.value, onChanged: _update),
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
    );
    if (confirmed != true && mounted) _update(initial);
  }

  Future<void> _addSlot(SuperLayoutZone zone) async {
    final id = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final slots = _availableSlots(context, includeRegistry: true);
        return SimpleDialog(
          title: Text('Ajouter un slot dans ${zone.label}'),
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

    _update(
      config.withSlotMoved(
        instanceId,
        config.contentZone(zone),
        type: supplied ? null : id,
      ),
    );
  }
}
