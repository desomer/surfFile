/// Fenêtre d'édition d'un composant conditionnel [SuperConditional].
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/super_conditional_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../repositories/repository_binding_fields.dart';
import 'shared/editor_segmented_field.dart';

/// Ouvre la fenêtre des propriétés d'un composant [SuperConditional].
Future<SuperConditionalConfig?> showSuperConditionalEditor({
  required BuildContext context,
  required SuperConditionalConfig config,
}) {
  final repositories = JsonRepositoryScope.maybeOf(context);
  final scope = JsonListScope.maybeOf(context);
  return runWithDimensionDelegate<SuperConditionalConfig>(
    context: context,
    runner: (initialTab, dimensionDelegate) =>
        showEditorDialog<SuperConditionalConfig>(
          context: context,
          target: context,
          builder: (_) => _SuperConditionalEditorDialog(
            initialTab: initialTab,
            dimensionDelegate: dimensionDelegate,
            config: config,
            repositories: repositories,
            scope: scope,
          ),
        ),
  );
}

class _SuperConditionalEditorDialog extends StatefulWidget {
  const _SuperConditionalEditorDialog({
    required this.initialTab,
    required this.dimensionDelegate,
    required this.config,
    required this.repositories,
    required this.scope,
  });

  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;
  final SuperConditionalConfig config;
  final JsonRepositoryStore? repositories;
  final JsonListScope? scope;

  @override
  State<_SuperConditionalEditorDialog> createState() =>
      _SuperConditionalEditorDialogState();
}

class _SuperConditionalEditorDialogState
    extends State<_SuperConditionalEditorDialog> {
  late SuperConditionalConfig _draft = widget.config;
  late final TextEditingController _newCaseController = TextEditingController();
  late final TextEditingController _initialCaseController =
      TextEditingController(text: widget.config.initialCase);
  late final TextEditingController _emptyTextController = TextEditingController(
    text: widget.config.emptyText,
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _newCaseController.dispose();
    _initialCaseController.dispose();
    _emptyTextController.dispose();
    super.dispose();
  }

  void _addCase() {
    final value = _newCaseController.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Saisissez une valeur de cas non vide.');
      return;
    }
    if (_draft.cases.contains(value)) {
      setState(() => _error = 'Le cas "$value" existe déjà.');
      return;
    }
    setState(() {
      _error = null;
      _draft = _draft.withCaseAdded(value);
      _newCaseController.clear();
    });
  }

  void _removeCase(String caseValue) {
    setState(() {
      _error = null;
      _draft = _draft.withoutCase(caseValue);
      if (_initialCaseController.text.trim() == caseValue) {
        _initialCaseController.clear();
      }
    });
  }

  Future<bool> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pendingNewCase = _newCaseController.text.trim();
      var nextDraft = _draft;
      if (pendingNewCase.isNotEmpty &&
          !nextDraft.cases.contains(pendingNewCase)) {
        nextDraft = nextDraft.withCaseAdded(pendingNewCase);
      }
      final config = nextDraft.copyWith(
        initialCase: _initialCaseController.text.trim(),
        emptyText: _emptyTextController.text,
      )..validate();
      final binding = config.binding;
      if (binding != null && binding.path.trim().isEmpty) {
        throw const FormatException('Chemin de liaison requis.');
      }
      if (mounted) Navigator.of(context).pop(config);
      return true;
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return EditorTabbedAlertDialog(
      dialogKey: const ValueKey('super-conditional-settings'),
      initialTab: widget.initialTab,
      dimensionDelegate: widget.dimensionDelegate,
      propertiesTitle: const Text('Configurer le composant conditionnel'),
      propertiesWidth: 460,
      busy: _busy,
      onApply: _apply,
      onCancel: () => Navigator.of(context).pop(),
      propertiesContentBuilder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text('Cas conditionnels (branches)', style: theme.textTheme.titleSmall),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('super-conditional-new-case-input'),
                  controller: _newCaseController,
                  decoration: const InputDecoration(
                    labelText: 'Ajouter une valeur de cas',
                    hintText: 'ex: string, number, true...',
                    isDense: true,
                  ),
                  onFieldSubmitted: (_) => _addCase(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const ValueKey('super-conditional-add-case-button'),
                onPressed: _addCase,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          if (_draft.cases.isEmpty)
            Text(
              'Aucun cas défini. Ajoutez au moins une valeur de cas ci-dessus.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in _draft.cases)
                  InputChip(
                    key: ValueKey('super-conditional-case-chip-$c'),
                    label: Text(c),
                    selected: _initialCaseController.text.trim() == c,
                    tooltip: 'Cliquer pour définir comme cas initial',
                    onSelected: (selected) {
                      setState(() {
                        _initialCaseController.text = selected ? c : '';
                        _draft = _draft.copyWith(
                          initialCase: _initialCaseController.text,
                        );
                      });
                    },
                    onDeleted: () => _removeCase(c),
                  ),
              ],
            ),
          EditorSwitchTile(
            tileKey: const ValueKey('super-conditional-has-default'),
            title: 'Branche par défaut (« default »)',
            subtitle:
                'Affiche la zone par défaut si la valeur ne correspond à aucun cas',
            value: _draft.hasDefaultCase,
            onChanged: (value) =>
                setState(() => _draft = _draft.copyWith(hasDefaultCase: value)),
          ),
          EditorSwitchTile(
            tileKey: const ValueKey('super-conditional-maintain-state'),
            title: 'Maintenir l’état des branches inactives',
            subtitle: 'Conserve en mémoire les widgets des cas masqués',
            value: _draft.maintainState,
            onChanged: (value) =>
                setState(() => _draft = _draft.copyWith(maintainState: value)),
          ),
          TextFormField(
            key: const ValueKey('super-conditional-initial-case'),
            controller: _initialCaseController,
            decoration: const InputDecoration(
              labelText: 'Cas initial (optionnel)',
              hintText: 'Valeur du cas par défaut avant résolution',
            ),
          ),
          TextFormField(
            key: const ValueKey('super-conditional-empty-text'),
            controller: _emptyTextController,
            decoration: const InputDecoration(
              labelText: 'Message si aucune branche ne correspond',
            ),
          ),
          const Divider(),
          Text(
            'Liaison du repository déterminant le cas actif',
            style: theme.textTheme.titleSmall,
          ),
          RepositoryBindingFields(
            keyPrefix: 'super-conditional-binding',
            binding: _draft.binding,
            store: widget.repositories,
            listScope: widget.scope,
            pathHint: 'nodes[?].type ou ui.mode',
            onChanged: (binding) => setState(
              () => _draft = _draft.copyWith(
                binding: binding,
                clearBinding: binding == null,
              ),
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              key: const ValueKey('super-conditional-editor-error'),
              style: TextStyle(color: colors.error),
            ),
        ],
      ),
    );
  }
}
