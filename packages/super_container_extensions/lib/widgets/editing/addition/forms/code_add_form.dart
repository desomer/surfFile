/// Formulaire des proprietes de SuperCode, partage entre ajout et edition.
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_code_config.dart';

/// Choix du langage et de la lecture seule.
class CodeAddForm extends StatelessWidget {
  const CodeAddForm({required this.draft, required this.onChanged, super.key});

  /// Configuration en cours.
  final SuperCodeConfig draft;

  /// Transmet les modifications au wizard.
  final ValueChanged<SuperCodeConfig> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<SuperCodeMode>(
        key: const ValueKey('super-code-mode'),
        segments: [
          for (final mode in SuperCodeMode.values)
            ButtonSegment(value: mode, label: Text(mode.label)),
        ],
        selected: {draft.mode},
        onSelectionChanged: (selected) =>
            onChanged(draft.copyWith(mode: selected.single)),
      ),
      SwitchListTile(
        title: const Text('Lecture seule'),
        value: draft.readOnly,
        onChanged: (value) => onChanged(draft.copyWith(readOnly: value)),
      ),
    ],
  );
}
