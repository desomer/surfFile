import 'package:material_ui/material_ui.dart';

import '../../../../models/native_component_config.dart';
import '../../../../models/native_property_descriptor.dart';

class ExpansibleAddForm extends StatelessWidget {
  const ExpansibleAddForm({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final NativeComponentConfig draft;
  final ValueChanged<NativeComponentConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final toggleIcon = draft.toggleIcon ?? 'none';
    final toggleIconPosition = draft.toggleIconPosition ?? 'trailing';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('add-expansible-initially-expanded'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Ouvert par défaut'),
          value: draft.initiallyExpanded ?? false,
          onChanged: (value) => onChanged(draft.withInitiallyExpanded(value)),
        ),
        SwitchListTile(
          key: const ValueKey('add-expansible-header-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Basculer au clic sur l’en-tête'),
          value: draft.headerClickToggles ?? true,
          onChanged: (value) => onChanged(draft.withHeaderClickToggles(value)),
        ),
        SwitchListTile(
          key: const ValueKey('add-expansible-maintain-state'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Maintenir l’état fermé'),
          value: draft.maintainState ?? true,
          onChanged: (value) => onChanged(draft.withMaintainState(value)),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('add-expansible-toggle-icon'),
          isExpanded: true,
          initialValue: toggleIcon,
          decoration: const InputDecoration(
            labelText: 'Icône ouvert / fermé',
            isDense: true,
          ),
          items: [
            for (final option in toggleIconPropertyDescriptor.options)
              DropdownMenuItem<String>(
                value: option.value,
                child: Text(option.label),
              ),
          ],
          onChanged: (value) => onChanged(draft.withToggleIcon(value)),
        ),
        if (toggleIcon != 'none') ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const ValueKey('add-expansible-toggle-icon-position'),
            isExpanded: true,
            initialValue: toggleIconPosition,
            decoration: const InputDecoration(
              labelText: 'Position de l’icône',
              isDense: true,
            ),
            items: [
              for (final option in toggleIconPositionPropertyDescriptor.options)
                DropdownMenuItem<String>(
                  value: option.value,
                  child: Text(option.label),
                ),
            ],
            onChanged: (value) =>
                onChanged(draft.withToggleIconPosition(value)),
          ),
        ],
      ],
    );
  }
}
