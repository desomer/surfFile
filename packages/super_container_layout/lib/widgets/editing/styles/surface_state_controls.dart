import 'package:material_ui/material_ui.dart';

import '../../../theme/container_style.dart';
import '../../../models/automatic_state.dart';
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
    this.allowContentHover = false,
    super.key,
  });

  final ContainerStyle style;
  final String? state, activeState, error;
  final bool allowSelected;
  final bool allowContentHover;
  final ValueChanged<String?> onSelect;
  final ValueChanged<SurfaceStyleStates> onChanged;
  final BuildContext ownerContext;

  @override
  Widget build(BuildContext context) {
    final states = style.states ?? SurfaceStyleStates();
    final automatic = AutomaticState.fromKey(state);
    final overlay = states.named.containsKey(state)
        ? SelectedSurfaceStyle(
            style: states.named[state]!,
            properties: states.namedProperties[state]!,
          )
        : automatic == AutomaticState.contentHover
        ? states.automatic[automatic]
        : state == hoverSurfaceStateKey
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
      availableStates: {
        AutomaticState.hover,
        if (allowSelected) AutomaticState.selected,
        if (allowContentHover) AutomaticState.contentHover,
      },
      onAddAutomatic: (value) {
        onChanged(
          states.copyWith(
            automatic: {
              ...states.automatic,
              value: SelectedSurfaceStyle(
                style: style.copyWith(clearStates: true),
              ),
            },
            order: [...states.order, value.key],
          ),
        );
        onSelect(value.key);
      },
      onDeleteAutomatic: (value) {
        onSelect(null);
        onChanged(
          states.copyWith(automatic: {...states.automatic}..remove(value)),
        );
      },
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
          namedProperties: {...states.namedProperties}
            ..remove(previous)
            ..[name] = states.namedProperties[previous]!,
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
          states.named.containsKey(state)
              ? states.copyWith(
                  namedProperties: {
                    ...states.namedProperties,
                    state!: properties,
                  },
                )
              : automatic == AutomaticState.contentHover
              ? states.copyWith(
                  automatic: {...states.automatic, automatic!: value},
                )
              : state == hoverSurfaceStateKey
              ? states.copyWith(hover: value)
              : states.copyWith(selected: value),
        );
      },
    );
  }
}
