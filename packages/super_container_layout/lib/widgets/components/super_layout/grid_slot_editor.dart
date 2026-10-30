part of 'super_layout.dart';

class _GridSlotDimensionDelegate extends EditorDimensionDelegate {
  _GridSlotDimensionDelegate({
    required this.owner,
    required this.slot,
  }) : initial = owner._config.value,
       grid = owner._config.value.effectiveGrid,
       showConstraints = ValueNotifier(false),
       sizeDelegate = owner._buildSlotSizeDelegate(
         slot,
         initialOverride: owner._config.value,
       ) {
    final p = grid.items[slot.id]!;
    fields = {
      'x': TextEditingController(text: '${p.x}'),
      'y': TextEditingController(text: '${p.y}'),
      'width': TextEditingController(text: '${p.width}'),
      'height': TextEditingController(text: '${p.height}'),
    };
  }

  final SuperLayoutState owner;
  final SlotImplementation slot;
  final SuperLayoutConfig initial;
  final GridLayoutConfig grid;
  final ValueNotifier<bool> showConstraints;
  final SlotSizeDimensionDelegate sizeDelegate;
  final GlobalKey<FormState> gridForm = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  bool _gridDirty = false;

  static const labels = {
    'x': 'Colonne (depuis 0)',
    'y': 'Ligne (depuis 0)',
    'width': 'Largeur (cellules)',
    'height': 'Hauteur (cellules)',
  };

  @override
  String get title => showConstraints.value
      ? sizeDelegate.title
      : 'Grille : ${sizeDelegate.label.value}';

  @override
  ValueListenable<String>? get labelListenable => sizeDelegate.label;

  @override
  String? get editableLabel => sizeDelegate.editableLabel;

  @override
  ValueChanged<String>? get onLabelChanged => sizeDelegate.onLabelChanged;

  @override
  double get contentWidth => showConstraints.value ? 560 : 320;

  @override
  void syncLabel(String value) => sizeDelegate.syncLabel(value);

  String? _validateGridField(String key, String? text) {
    final value = int.tryParse(text ?? '');
    final minimum = key == 'x' || key == 'y' ? 0 : 1;
    if (value == null || value < minimum || value > 10000) {
      return 'Entier entre $minimum et 10000 requis.';
    }
    final x = int.tryParse(fields['x']!.text);
    final width = int.tryParse(fields['width']!.text);
    if ((key == 'x' || key == 'width') &&
        x != null &&
        width != null &&
        x + width > grid.columns) {
      return 'La grille contient ${grid.columns} colonnes.';
    }
    return null;
  }

  bool _isGridValid() => fields.entries.every(
    (entry) => _validateGridField(entry.key, entry.value.text) == null,
  );

  void previewGrid() {
    if (!(gridForm.currentState?.validate() ?? _isGridValid())) return;
    _gridDirty = true;
    final position = GridSlotPosition(
      x: int.parse(fields['x']!.text),
      y: int.parse(fields['y']!.text),
      width: int.parse(fields['width']!.text),
      height: int.parse(fields['height']!.text),
    );
    owner._update(
      owner._config.value.copyWith(
        grid: grid.withItem(slot.id, position, compact: false),
      ),
    );
  }

  @override
  bool validate() {
    if (showConstraints.value) {
      return sizeDelegate.validate();
    }
    final formValid = gridForm.currentState?.validate() ?? true;
    return formValid && _isGridValid() && sizeDelegate.validate();
  }

  @override
  void apply() {
    if (!owner.mounted) return;
    if (_gridDirty || !showConstraints.value) {
      if (_isGridValid()) {
        previewGrid();
        owner._update(
          owner._config.value.copyWith(
            grid: owner._config.value.effectiveGrid.arrange(activeId: slot.id),
          ),
        );
      }
    }
    if (showConstraints.value) {
      sizeDelegate.apply(force: true);
    } else {
      sizeDelegate.apply();
    }
  }

  @override
  void restore() {
    if (owner.mounted) {
      owner._update(initial);
    }
  }

  @override
  List<Widget> buildExtraActions(
    BuildContext context, {
    required VoidCallback onResetAndClose,
  }) => showConstraints.value
      ? sizeDelegate.buildExtraActions(context, onResetAndClose: onResetAndClose)
      : const [];

  @override
  Widget buildContent(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: showConstraints,
    builder: (context, constraintsView, _) {
      if (constraintsView) {
        return sizeDelegate.buildContent(context);
      }
      return Form(
        key: gridForm,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: const ValueKey('grid-slot-size-constraints'),
              onPressed: () {
                if (!(gridForm.currentState?.validate() ?? _isGridValid())) {
                  return;
                }
                previewGrid();
                showConstraints.value = true;
              },
              child: const Text('Tailles min / préférée / max (px ou %)'),
            ),
            for (final entry in fields.entries)
              TextFormField(
                key: ValueKey('grid-slot-${entry.key}'),
                controller: entry.value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: labels[entry.key]),
                validator: (text) => _validateGridField(entry.key, text),
                onChanged: (_) => previewGrid(),
              ),
          ],
        ),
      );
    },
  );

  @override
  void dispose() {
    sizeDelegate.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in fields.values) {
        controller.dispose();
      }
      showConstraints.dispose();
    });
  }
}

extension _GridSlotEditor on SuperLayoutState {
  _GridSlotDimensionDelegate _buildGridSlotDelegate(SlotImplementation slot) =>
      _GridSlotDimensionDelegate(owner: this, slot: slot);

  Future<void> _editGridSlot(SlotImplementation slot) async {
    final targetContext = _slotFocusKeys[slot.id]?.currentContext;
    final childEditor = EditorWizardNavigation.findDirectChildEditorSlot(
      targetContext,
    );
    final delegate = _buildGridSlotDelegate(slot);
    if (childEditor != null && childEditor.mounted) {
      await EditorWizardNavigation.openWithTab(
        EditorWizardTab.dimensions,
        childEditor.openEditor,
        delegate: delegate,
      );
      return;
    }

    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    var confirmed = false;
    try {
      confirmed =
          await showEditorDialog<bool>(
            context: context,
            target: targetContext ?? context,
            builder: (dialogContext) => ValueListenableBuilder<bool>(
              valueListenable: delegate.showConstraints,
              builder: (context, _, _) => EditorTabbedAlertDialog(
                initialTab: EditorWizardTab.dimensions,
                propertiesEnabled: false,
                propertiesTitle: const SizedBox.shrink(),
                propertiesContentBuilder: (_) => const SizedBox.shrink(),
                dimensionDelegate: delegate,
                onApply: () async => true,
                onCancel: () => Navigator.of(dialogContext).pop(false),
              ),
            ),
          ) ==
          true;
    } finally {
      if (!confirmed && mounted) {
        delegate.restore();
        history?.cancelTransaction();
      } else {
        if (confirmed && mounted) {
          delegate.apply();
        }
        history?.commitTransaction();
      }
      delegate.dispose();
    }
  }
}
