/// Formulaire des proprietes de SuperCode, partage entre ajout et edition.
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_code_config.dart';

/// Choix du langage, de la lecture seule et du style visuel de l'éditeur.
class CodeAddForm extends StatelessWidget {
  const CodeAddForm({required this.draft, required this.onChanged, super.key});

  /// Configuration en cours.
  final SuperCodeConfig draft;

  /// Transmet les modifications au wizard.
  final ValueChanged<SuperCodeConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = draft.style;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
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
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) => onChanged(draft.copyWith(readOnly: value)),
        ),
        DropdownButtonFormField<SuperCodeTheme>(
          key: const ValueKey('super-code-theme'),
          initialValue: style.theme,
          decoration: const InputDecoration(
            labelText: 'Thème de coloration',
            isDense: true,
          ),
          items: [
            for (final theme in SuperCodeTheme.values)
              DropdownMenuItem(
                value: theme,
                child: Row(
                  children: [
                    Icon(
                      theme.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(theme.label),
                  ],
                ),
              ),
          ],
          onChanged: (theme) {
            if (theme != null) {
              onChanged(draft.copyWith(style: style.copyWith(theme: theme)));
            }
          },
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Taille de police : ${style.fontSize.toInt()} px',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            SizedBox(
              width: 180,
              child: Slider(
                key: const ValueKey('super-code-font-size'),
                value: style.fontSize,
                min: 10.0,
                max: 28.0,
                divisions: 18,
                label: '${style.fontSize.toInt()} px',
                onChanged: (value) => onChanged(
                  draft.copyWith(style: style.copyWith(fontSize: value)),
                ),
              ),
            ),
          ],
        ),
        SwitchListTile(
          key: const ValueKey('super-code-line-numbers'),
          title: const Text('Numéros de ligne'),
          value: style.showLineNumbers,
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) => onChanged(
            draft.copyWith(style: style.copyWith(showLineNumbers: value)),
          ),
        ),
        SwitchListTile(
          key: const ValueKey('super-code-folding-handles'),
          title: const Text('Pliage de code'),
          value: style.showFoldingHandles,
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) => onChanged(
            draft.copyWith(style: style.copyWith(showFoldingHandles: value)),
          ),
        ),
        SwitchListTile(
          key: const ValueKey('super-code-transparent-bg'),
          title: const Text('Arrière-plan transparent'),
          subtitle: const Text(
            'Laisse transparaître le style du conteneur parent',
            style: TextStyle(fontSize: 12),
          ),
          value: style.transparentBackground,
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) => onChanged(
            draft.copyWith(style: style.copyWith(transparentBackground: value)),
          ),
        ),
      ],
    );
  }
}
