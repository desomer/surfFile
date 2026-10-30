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
        const Text(
          'Icône ouvert / fermé',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          key: const ValueKey('add-menu-anchor-toggle-icon'),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: [
            for (final option in toggleIconPropertyDescriptor.options)
              ButtonSegment<String>(
                value: option.value,
                tooltip: option.label,
                icon: Flexible(
                  flex: 0,
                  child: Icon(
                    switch (option.value) {
                      'none' => Icons.block,
                      'chevron' => Icons.expand_more,
                      'arrow' => Icons.arrow_downward,
                      'plusMinus' => Icons.add,
                      'triangle' => Icons.arrow_drop_down,
                      _ => Icons.tune,
                    },
                    size: 14,
                  ),
                ),
                label: Text(option.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          selected: {toggleIcon},
          onSelectionChanged: (selected) {
            if (selected.isNotEmpty) {
              onChanged(draft.withToggleIcon(selected.first));
            }
          },
        ),
        if (toggleIcon != 'none') ...[
          const SizedBox(height: 8),
          const Text(
            'Position de l’icône',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            key: const ValueKey('add-menu-anchor-toggle-icon-position'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              for (final option in toggleIconPositionPropertyDescriptor.options)
                ButtonSegment<String>(
                  value: option.value,
                  tooltip: option.label,
                  icon: Icon(
                    option.value == 'leading'
                        ? Icons.first_page
                        : Icons.last_page,
                    size: 16,
                  ),
                  label: Text(option.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            selected: {toggleIconPosition},
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) {
                onChanged(draft.withToggleIconPosition(selected.first));
              }
            },
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
