import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/explorer_colors.dart';

class ExplorerViewToggle extends StatelessWidget {
  const ExplorerViewToggle({
    required this.gridView,
    required this.onChanged,
    this.columnView = false,
    this.onColumnViewChanged,
    this.heatmapView = false,
    this.onHeatmapViewChanged,
    super.key,
  });

  final bool gridView;
  final ValueChanged<bool> onChanged;

  /// Navigation en colonnes ; le bouton n'apparaît que si
  /// [onColumnViewChanged] est fourni.
  final bool columnView;
  final ValueChanged<bool>? onColumnViewChanged;

  /// Carte thermique des tailles ; le bouton n'apparaît que si
  /// [onHeatmapViewChanged] est fourni.
  final bool heatmapView;
  final ValueChanged<bool>? onHeatmapViewChanged;

  @override
  Widget build(BuildContext context) {
    final onColumnViewChanged = this.onColumnViewChanged;
    final onHeatmapViewChanged = this.onHeatmapViewChanged;
    return Container(
      decoration: BoxDecoration(
        color: explorerColor(
          context,
          const Color(0xFFEDEFF4),
          Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _ViewButton(
            key: const ValueKey('view-list'),
            icon: Icons.view_list_rounded,
            selected: !gridView && !columnView && !heatmapView,
            onTap: () {
              onChanged(false);
              onColumnViewChanged?.call(false);
              onHeatmapViewChanged?.call(false);
            },
          ),
          _ViewButton(
            key: const ValueKey('view-grid'),
            icon: Icons.grid_view_rounded,
            selected: gridView && !columnView && !heatmapView,
            onTap: () {
              onChanged(true);
              onColumnViewChanged?.call(false);
              onHeatmapViewChanged?.call(false);
            },
          ),
          if (onColumnViewChanged != null)
            _ViewButton(
              key: const ValueKey('view-columns'),
              icon: Icons.view_column_rounded,
              selected: columnView,
              onTap: () {
                onColumnViewChanged(true);
                onHeatmapViewChanged?.call(false);
              },
            ),
          if (onHeatmapViewChanged != null)
            _ViewButton(
              key: const ValueKey('view-heatmap'),
              icon: Icons.dashboard_rounded,
              selected: heatmapView,
              onTap: () {
                onHeatmapViewChanged(true);
                onColumnViewChanged?.call(false);
              },
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
    super.key,
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
        color: explorerColor(
          context,
          selected ? const Color(0xFF5268D9) : const Color(0xFF8D94A4),
          selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? explorerColor(
                context,
                Colors.white,
                Theme.of(context).colorScheme.surfaceContainerLow,
              )
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    );
  }
}
