import 'package:material_ui/material_ui.dart';
import '../theme/explorer_colors.dart';

class ExplorerViewToggle extends StatelessWidget {
  const ExplorerViewToggle({
    required this.gridView,
    required this.onChanged,
    super.key,
  });

  final bool gridView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: explorerColor(context, const Color(0xFFEDEFF4),
            Theme.of(context).colorScheme.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _ViewButton(
            icon: Icons.view_list_rounded,
            selected: !gridView,
            onTap: () => onChanged(false),
          ),
          _ViewButton(
            icon: Icons.grid_view_rounded,
            selected: gridView,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: selected ? 'Vue sélectionnée' : 'Changer la vue',
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 19,
        color: explorerColor(context,
            selected ? const Color(0xFF5268D9) : const Color(0xFF8D94A4),
            selected ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? explorerColor(context, Colors.white,
                Theme.of(context).colorScheme.surfaceContainerLow)
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    );
  }
}
