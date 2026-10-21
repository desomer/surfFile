import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../dialogs/editor_dialog.dart';
import '../repositories/repository_binding_fields.dart';

const selectedSurfaceStateKey = '\u0000selected';
const hoverSurfaceStateKey = '\u0000hover';

class EditorStateControls<P extends Enum> extends StatelessWidget {
  const EditorStateControls({
    required this.names,
    required this.order,
    required this.binding,
    required this.state,
    required this.allowSelected,
    required this.onSelect,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onReorder,
    required this.onBindingChanged,
    required this.validateName,
    required this.ownerContext,
    this.activeState,
    this.error,
    this.properties = const {},
    this.overrides = const {},
    this.onOverride,
    this.keyPrefix = 'surface-state',
    super.key,
  });

  final Iterable<String> names;
  final List<String> order;
  final JsonTextBinding? binding;
  final String? state, activeState, error;
  final bool allowSelected;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onAdd, onDelete;
  final void Function(String previous, String name) onRename;
  final ValueChanged<List<String>> onReorder;
  final ValueChanged<JsonTextBinding?> onBindingChanged;
  final String? Function(String name) validateName;
  final BuildContext ownerContext;
  final Map<P, String> properties;
  final Set<P> overrides;
  final void Function(P property, bool enabled)? onOverride;
  final String keyPrefix;

  Future<void> _name(BuildContext context, {String? previous}) async {
    final text = TextEditingController(text: previous ?? '');
    final form = GlobalKey<FormState>();
    try {
      final name = await showEditorDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(previous == null ? 'Ajouter un état' : 'Renommer l’état'),
          content: Form(
            key: form,
            child: TextFormField(
              key: ValueKey('$keyPrefix-name'),
              controller: text,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom exact dans le JSON',
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                return validateName(name) ??
                    (name != previous && names.contains(name)
                        ? 'Ce nom existe déjà.'
                        : null);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, text.text.trim());
                }
              },
              child: const Text('Appliquer'),
            ),
          ],
        ),
      );
      if (name == null || !context.mounted) return;
      if (previous == null) {
        onAdd(name);
      } else {
        onRename(previous, name);
      }
      onSelect(name);
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final namedState = names.contains(state);
    final current =
        state == hoverSurfaceStateKey ||
            (state == selectedSurfaceStateKey && allowSelected) ||
            namedState
        ? state
        : null;
    String label(String key) => key == hoverSurfaceStateKey
        ? 'Hover'
        : key == selectedSurfaceStateKey
        ? 'Sélectionné'
        : key;
    Widget choice(String? key) => ChoiceChip(
      key: ValueKey('$keyPrefix-choice-${key ?? ''}'),
      label: Text(
        key == null ? 'Par défaut' : label(key),
        overflow: TextOverflow.ellipsis,
      ),
      selected: current == key,
      onSelected: (_) => onSelect(key),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          key: ValueKey('$keyPrefix-selector'),
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            choice(null),
            for (final key in order)
              if (key != selectedSurfaceStateKey || allowSelected)
                DragTarget<({Object owner, String key})>(
                  onWillAcceptWithDetails: (details) =>
                      identical(details.data.owner, ownerContext) &&
                      details.data.key != key &&
                      order.contains(details.data.key),
                  onAcceptWithDetails: (details) {
                    final next = [...order];
                    final target = next.indexOf(key);
                    next.remove(details.data.key);
                    next.insert(target, details.data.key);
                    onReorder(next);
                  },
                  builder: (context, candidates, rejected) =>
                      Draggable<({Object owner, String key})>(
                        data: (owner: ownerContext, key: key),
                        feedback: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(24),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(label(key)),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: .35,
                          child: choice(key),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: candidates.isEmpty
                                ? null
                                : Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: choice(key),
                        ),
                      ),
                ),
            IconButton(
              key: ValueKey('$keyPrefix-add'),
              tooltip: 'Ajouter un état',
              icon: const Icon(Icons.add),
              onPressed: () => _name(context),
            ),
            if (namedState) ...[
              IconButton(
                tooltip: 'Renommer l’état',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _name(context, previous: state),
              ),
              IconButton(
                key: ValueKey('$keyPrefix-delete'),
                tooltip: 'Supprimer l’état',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  onSelect(null);
                  onDelete(state!);
                },
              ),
            ],
            IconButton(
              key: ValueKey('$keyPrefix-binding'),
              tooltip: 'Attribut JSON de l’état',
              icon: const Icon(Icons.link),
              onPressed: () async {
                final result = await showRepositoryBindingDialog(
                  context: ownerContext,
                  title: 'Liaison de l’état',
                  keyPrefix: '$keyPrefix-binding',
                  pathHint: 'clients[?].statut',
                  binding: binding,
                  helper: 'Une valeur texte doit correspondre exactement au nom d’un état.',
                );
                if (result != null && context.mounted) {
                  onBindingChanged(result.binding);
                }
              },
            ),
          ],
        ),
        Text(
          'Aperçu local • État réel : ${activeState ?? 'Par défaut'}',
          key: ValueKey('$keyPrefix-active'),
        ),
        const Text('Glissez les états : le suivant est prioritaire.'),
        if (error != null)
          Text(
            error!,
            key: ValueKey('$keyPrefix-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (state == selectedSurfaceStateKey || state == hoverSurfaceStateKey)
          Wrap(
            spacing: 6,
            children: [
              for (final entry in properties.entries)
                FilterChip(
                  key: ValueKey('$keyPrefix-override-${entry.key.name}'),
                  label: Text(entry.value),
                  selected: overrides.contains(entry.key),
                  onSelected: onOverride == null
                      ? null
                      : (enabled) => onOverride!(entry.key, enabled),
                ),
            ],
          ),
      ],
    );
  }
}
