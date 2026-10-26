part of 'super_layout.dart';

extension _GridSlotEditor on SuperLayoutState {
  Future<void> _editGridSlot(SlotImplementation slot) async {
    final initial = _config.value;
    final grid = initial.effectiveGrid;
    final p = grid.items[slot.id]!;
    var label = initial.slotLabels[slot.id] ?? slot.label;
    final fields = {
      'x': TextEditingController(text: '${p.x}'),
      'y': TextEditingController(text: '${p.y}'),
      'width': TextEditingController(text: '${p.width}'),
      'height': TextEditingController(text: '${p.height}'),
    };
    final labels = {
      'x': 'Colonne (depuis 0)', 'y': 'Ligne (depuis 0)',
      'width': 'Largeur (cellules)', 'height': 'Hauteur (cellules)',
    };
    final form = GlobalKey<FormState>();
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    var confirmed = false;
    var editDimensions = false;
    try {
      confirmed = await showEditorDialog<bool>(
        context: context,
        target: _slotFocusKeys[slot.id]?.currentContext ?? context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) {
          void preview() {
            if (!form.currentState!.validate()) return;
            final position = GridSlotPosition(
              x: int.parse(fields['x']!.text), y: int.parse(fields['y']!.text),
              width: int.parse(fields['width']!.text),
              height: int.parse(fields['height']!.text),
            );
            _update(_config.value.copyWith(
              grid: grid.withItem(slot.id, position, compact: false),
            ));
          }
          return AlertDialog(
            title: EditorDialogHeader(
              label: 'Grille : $label', editableLabel: label,
              onLabelChanged: (value) => setDialog(() {
                label = value;
                _update(_config.value.withSlotLabel(slot.id, value));
              }),
            ),
            content: SizedBox(width: 320, child: SingleChildScrollView(
              child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    key: const ValueKey('grid-slot-size-constraints'),
                    onPressed: () {
                      if (!form.currentState!.validate()) return;
                      preview();
                      editDimensions = true;
                      Navigator.of(dialogContext).pop(true);
                    },
                    child: const Text('Tailles min / préférée / max (px ou %)'),
                  ),
                  for (final entry in fields.entries)
                    TextFormField(
                      key: ValueKey('grid-slot-${entry.key}'),
                      controller: entry.value,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: labels[entry.key]),
                      validator: (text) {
                        final value = int.tryParse(text ?? '');
                        final minimum = entry.key == 'x' || entry.key == 'y' ? 0 : 1;
                        if (value == null || value < minimum || value > 10000) {
                          return 'Entier entre $minimum et 10000 requis.';
                        }
                        final x = int.tryParse(fields['x']!.text);
                        final width = int.tryParse(fields['width']!.text);
                        if ((entry.key == 'x' || entry.key == 'width') &&
                            x != null && width != null && x + width > grid.columns) {
                          return 'La grille contient ${grid.columns} colonnes.';
                        }
                        return null;
                      },
                      onChanged: (_) => preview(),
                    ),
                ],
              )),
            )),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Annuler')),
              FilledButton(onPressed: () {
                if (!form.currentState!.validate()) return;
                preview();
                _update(_config.value.copyWith(
                  grid: _config.value.effectiveGrid.arrange(activeId: slot.id),
                ));
                Navigator.of(dialogContext).pop(true);
              }, child: const Text('Appliquer')),
            ],
          );
        }),
      ) == true;
    } finally {
      if (!confirmed && mounted) {
        _update(initial);
        history?.cancelTransaction();
      } else {
        history?.commitTransaction();
      }
      // Route transitions can still build the text fields after pop.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final controller in fields.values) {
          controller.dispose();
        }
      });
    }
    if (editDimensions && mounted) await _editSlotPreferredSize(slot);
  }
}
