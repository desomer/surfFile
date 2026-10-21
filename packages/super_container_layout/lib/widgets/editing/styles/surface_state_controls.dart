import 'package:material_ui/material_ui.dart';

import '../../../theme/container_style.dart';
import '../states/editor_state_controls.dart';

export '../states/editor_state_controls.dart'
    show selectedSurfaceStateKey, hoverSurfaceStateKey;

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
  final String? state, activeState, error;
  final bool allowSelected;
  final ValueChanged<String?> onSelect;
  final ValueChanged<SurfaceStyleStates> onChanged;
  final BuildContext ownerContext;

  @override
  Widget build(BuildContext context) {
    final states = style.states ?? SurfaceStyleStates();
    final overlay = state == hoverSurfaceStateKey
        ? states.hover
        : states.selected;
    return EditorStateControls<SurfaceStyleProperty>(
      names: states.named.keys,
      order: states.order,
      binding: states.binding,
      state: state,
      allowSelected: allowSelected,
      ownerContext: ownerContext,
      activeState: activeState,
      error: error,
      onSelect: onSelect,
      validateName: (name) {
        try {
          SurfaceStyleStates(named: {name: const ContainerStyle()});
          return null;
        } on FormatException catch (e) {
          return e.message;
        }
      },
      onAdd: (name) => onChanged(
        states.copyWith(
          named: {...states.named, name: style.copyWith(clearStates: true)},
          order: [name, ...states.order],
        ),
      ),
      onRename: (previous, name) => onChanged(
        states.copyWith(
          named: {...states.named}
            ..remove(previous)
            ..[name] = states.named[previous]!,
          order: [
            for (final key in states.order)
              if (key == previous) name else key,
          ],
        ),
      ),
      onDelete: (name) =>
          onChanged(states.copyWith(named: {...states.named}..remove(name))),
      onReorder: (order) => onChanged(states.copyWith(order: order)),
      onBindingChanged: (binding) => onChanged(
        states.copyWith(binding: binding, clearBinding: binding == null),
      ),
      properties: {
        for (final property in SurfaceStyleProperty.values)
          property: property.label,
      },
      overrides: overlay?.properties ?? {},
      onOverride: (property, enabled) {
        final properties = {...?overlay?.properties};
        if (enabled) {
          properties.add(property);
        } else {
          properties.remove(property);
        }
        final value = SelectedSurfaceStyle(
          style: overlay?.style ?? style.copyWith(clearStates: true),
          properties: properties,
        );
        onChanged(
          state == hoverSurfaceStateKey
              ? states.copyWith(hover: value)
              : states.copyWith(selected: value),
        );
      },
    );
  }
}
