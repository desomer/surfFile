import 'package:material_ui/material_ui.dart';

import '../../../theme/container_style.dart';
import '../dialogs/editor_dialog.dart';
import '../repositories/repository_binding_fields.dart';

const selectedSurfaceStateKey = '\u0000selected';
const hoverSurfaceStateKey = '\u0000hover';

class SurfaceStateControls extends StatelessWidget {
  const SurfaceStateControls({
    required this.style,
    required this.state,
    required this.allowSelected,
    required this.onSelect,
    required this.onChanged,
    required this.ownerContext,
    this.activeState,
    this.error,
    super.key,
  });

  final ContainerStyle style;
  final String? state;
  final String? activeState;
  final String? error;
  final bool allowSelected;
  final ValueChanged<String?> onSelect;
  final ValueChanged<SurfaceStyleStates> onChanged;
  final BuildContext ownerContext;

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
              key: const ValueKey('surface-state-name'),
              controller: text,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom exact dans le JSON',
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                try {
                  SurfaceStyleStates(named: {name: const ContainerStyle()});
                } on FormatException catch (e) {
                  return e.message;
                }
                return name != previous &&
                        (style.states?.named.containsKey(name) ?? false)
                    ? 'Ce nom existe déjà.'
                    : null;
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
      if (name == null) return;
      final states = style.states ?? SurfaceStyleStates();
      final named = {...states.named};
      final value = previous == null
          ? style.copyWith(clearStates: true)
          : named.remove(previous)!;
      named[name] = value;
      final order = [
        for (final key in states.order)
          if (key == previous) name else key,
      ];
      if (previous == null) order.insert(0, name);
      onChanged(states.copyWith(named: named, order: order));
      onSelect(name);
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final states = style.states ?? SurfaceStyleStates();
    final namedState = states.named.containsKey(state);
    final overlay = state == hoverSurfaceStateKey
        ? states.hover
        : states.selected;
    final current =
        state == hoverSurfaceStateKey ||
            (state == selectedSurfaceStateKey && allowSelected) ||
            namedState
        ? state
        : null;
    Widget choice(String? key, String label) => ChoiceChip(
      key: ValueKey('surface-state-choice-${key ?? ''}'),
      label: Text(label, overflow: TextOverflow.ellipsis),
      selected: current == key,
      onSelected: (_) => onSelect(key),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          key: const ValueKey('surface-state-selector'),
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            choice(null, 'Par défaut'),
            for (final key in states.order)
              if (key != selectedSurfaceStateKey || allowSelected)
                DragTarget<String>(
                  onWillAcceptWithDetails: (details) =>
                      details.data != key &&
                      states.order.contains(details.data),
                  onAcceptWithDetails: (details) {
                    final order = [...states.order];
                    final target = order.indexOf(key);
                    order.remove(details.data);
                    order.insert(target, details.data);
                    onChanged(states.copyWith(order: order));
                  },
                  builder: (context, candidates, rejected) => Draggable<String>(
                    data: key,
                    feedback: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          key == hoverSurfaceStateKey
                              ? 'Hover'
                              : key == selectedSurfaceStateKey
                              ? 'Sélectionné'
                              : key,
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: .35,
                      child: choice(
                        key,
                        key == hoverSurfaceStateKey
                            ? 'Hover'
                            : key == selectedSurfaceStateKey
                            ? 'Sélectionné'
                            : key,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: candidates.isEmpty
                            ? null
                            : Border.all(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: choice(
                        key,
                        key == hoverSurfaceStateKey
                            ? 'Hover'
                            : key == selectedSurfaceStateKey
                            ? 'Sélectionné'
                            : key,
                      ),
                    ),
                  ),
                ),
            IconButton(
              key: const ValueKey('surface-state-add'),
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
                key: const ValueKey('surface-state-delete'),
                tooltip: 'Supprimer l’état',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  onSelect(null);
                  onChanged(
                    states.copyWith(named: {...states.named}..remove(state)),
                  );
                },
              ),
            ],
            IconButton(
              key: const ValueKey('surface-state-binding'),
              tooltip: 'Attribut JSON de l’état',
              icon: const Icon(Icons.link),
              onPressed: () async {
                final result = await showRepositoryBindingDialog(
                  context: ownerContext,
                  title: 'État de la surface',
                  keyPrefix: 'surface-state-binding',
                  pathHint: 'clients[?].statut',
                  binding: states.binding,
                  helper: 'Une valeur texte doit correspondre exactement au nom d’un état.',
                );
                if (result != null) {
                  onChanged(
                    states.copyWith(
                      binding: result.binding,
                      clearBinding: result.binding == null,
                    ),
                  );
                }
              },
            ),
          ],
        ),
        Text(
          'Aperçu local • État réel : ${activeState ?? 'Par défaut'}',
          key: const ValueKey('surface-state-active'),
        ),
        const Text('Glissez les états : le suivant est prioritaire.'),
        if (error != null)
          Text(
            error!,
            key: const ValueKey('surface-state-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (state == selectedSurfaceStateKey || state == hoverSurfaceStateKey)
          Wrap(
            spacing: 6,
            children: [
              for (final property in SurfaceStyleProperty.values)
                FilterChip(
                  key: ValueKey('surface-state-override-${property.name}'),
                  label: Text(property.label),
                  selected: overlay?.properties.contains(property) ?? false,
                  onSelected: (enabled) {
                    final properties = {...?overlay?.properties};
                    if (enabled) {
                      properties.add(property);
                    } else {
                      properties.remove(property);
                    }
                    final value = SelectedSurfaceStyle(
                      style:
                          overlay?.style ?? style.copyWith(clearStates: true),
                      properties: properties,
                    );
                    onChanged(
                      state == hoverSurfaceStateKey
                          ? states.copyWith(hover: value)
                          : states.copyWith(selected: value),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}
