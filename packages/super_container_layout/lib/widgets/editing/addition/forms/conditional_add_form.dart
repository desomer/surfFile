/// Formulaire de configuration initiale ([ConditionalAddForm]) lors de l'ajout d'un [SuperConditional].
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_conditional_config.dart';
import '../../components/shared/editor_segmented_field.dart';

/// Formulaire de paramétrage initial d'un [SuperConditional] dans l'assistant d'ajout.
class ConditionalAddForm extends StatefulWidget {
  const ConditionalAddForm({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final SuperConditionalConfig draft;
  final ValueChanged<SuperConditionalConfig> onChanged;

  @override
  State<ConditionalAddForm> createState() => _ConditionalAddFormState();
}

class _ConditionalAddFormState extends State<ConditionalAddForm> {
  final TextEditingController _caseInput = TextEditingController();

  @override
  void dispose() {
    _caseInput.dispose();
    super.dispose();
  }

  void _addCase() {
    final value = _caseInput.text.trim();
    if (value.isEmpty || widget.draft.cases.contains(value)) return;
    _caseInput.clear();
    widget.onChanged(widget.draft.withCaseAdded(value));
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('add-conditional-case-input'),
                controller: _caseInput,
                decoration: const InputDecoration(
                  labelText: 'Ajouter un cas nommé',
                  hintText: 'ex: string, number, true...',
                  isDense: true,
                ),
                onFieldSubmitted: (_) => _addCase(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              key: const ValueKey('add-conditional-add-case'),
              onPressed: _addCase,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        if (draft.cases.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in draft.cases)
                InputChip(
                  key: ValueKey('add-conditional-case-$c'),
                  label: Text(c),
                  onDeleted: () => widget.onChanged(draft.withoutCase(c)),
                ),
            ],
          ),
        EditorSwitchTile(
          tileKey: const ValueKey('add-conditional-has-default'),
          title: 'Branche par défaut (« default »)',
          value: draft.hasDefaultCase,
          onChanged: (value) =>
              widget.onChanged(draft.copyWith(hasDefaultCase: value)),
        ),
        EditorSwitchTile(
          tileKey: const ValueKey('add-conditional-maintain-state'),
          title: 'Maintenir l’état des branches inactives',
          value: draft.maintainState,
          onChanged: (value) =>
              widget.onChanged(draft.copyWith(maintainState: value)),
        ),
      ],
    );
  }
}
