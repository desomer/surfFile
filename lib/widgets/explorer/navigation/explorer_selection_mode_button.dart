import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/explorer_colors.dart';
import '../../../models/selection_mode.dart';

/// Menu de choix du mode de sélection, placé à côté du bouton de filtre.
class ExplorerSelectionModeButton extends StatelessWidget {
  const ExplorerSelectionModeButton({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  final SelectionMode mode;
  final ValueChanged<SelectionMode> onChanged;

  static IconData icon(SelectionMode mode) => switch (mode) {
    SelectionMode.standard => Icons.mouse_outlined,
    SelectionMode.checkbox => Icons.check_box_outlined,
    SelectionMode.rowClick => Icons.touch_app_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final highlighted = mode != SelectionMode.standard;
    return PopupMenuButton<SelectionMode>(
      key: const ValueKey('selection-mode-toggle'),
      tooltip: 'Mode de sélection : ${mode.label}',
      initialValue: mode,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      borderRadius: BorderRadius.circular(8),
      itemBuilder: (context) => [
        for (final value in SelectionMode.values)
          CheckedPopupMenuItem<SelectionMode>(
            key: ValueKey('selection-mode-${value.name}'),
            value: value,
            checked: value == mode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value.label),
                Text(
                  value.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: highlighted
              ? colors.primary.withValues(alpha: .12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon(mode),
          size: 17,
          color: highlighted
              ? colors.primary
              : explorerColor(
                  context,
                  const Color(0xFF9298A8),
                  colors.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}
