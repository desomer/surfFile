import 'package:material_ui/material_ui.dart';

import '../../../../models/native_component_config.dart';
import '../../../../models/native_property_descriptor.dart';

class MenuAnchorAddForm extends StatelessWidget {
  const MenuAnchorAddForm({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final NativeComponentConfig draft;
  final ValueChanged<NativeComponentConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final offsetX = draft.alignmentOffsetX ?? 0.0;
    final offsetY = draft.alignmentOffsetY ?? 0.0;
    final toggleIcon = draft.toggleIcon ?? 'none';
    final toggleIconPosition = draft.toggleIconPosition ?? 'trailing';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('add-menu-anchor-initially-expanded'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Ouvert par défaut'),
          value: draft.initiallyExpanded ?? false,
          onChanged: (value) => onChanged(draft.withInitiallyExpanded(value)),
        ),
        SwitchListTile(
          key: const ValueKey('add-menu-anchor-header-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Basculer au clic sur l’en-tête'),
          value: draft.headerClickToggles ?? true,
          onChanged: (value) => onChanged(draft.withHeaderClickToggles(value)),
        ),
        SwitchListTile(
          key: const ValueKey('add-menu-anchor-consume-outside-tap'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Consommer le clic extérieur'),
          value: draft.consumeOutsideTap ?? false,
          onChanged: (value) => onChanged(draft.withConsumeOutsideTap(value)),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('add-menu-anchor-toggle-icon'),
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
            key: const ValueKey('add-menu-anchor-toggle-icon-position'),
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
        const SizedBox(height: 8),
        Text(
          'Décalage horizontal X (${offsetX.toStringAsFixed(0)} px)',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          key: const ValueKey('add-menu-anchor-offset-x'),
          value: offsetX.clamp(-200.0, 200.0),
          min: -200,
          max: 200,
          divisions: 80,
          label: '${offsetX.toStringAsFixed(0)} px',
          onChanged: (value) =>
              onChanged(draft.withAlignmentOffsetX(value == 0 ? null : value)),
        ),
        Text(
          'Décalage vertical Y (${offsetY.toStringAsFixed(0)} px)',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          key: const ValueKey('add-menu-anchor-offset-y'),
          value: offsetY.clamp(-200.0, 200.0),
          min: -200,
          max: 200,
          divisions: 80,
          label: '${offsetY.toStringAsFixed(0)} px',
          onChanged: (value) =>
              onChanged(draft.withAlignmentOffsetY(value == 0 ? null : value)),
        ),
      ],
    );
  }
}
