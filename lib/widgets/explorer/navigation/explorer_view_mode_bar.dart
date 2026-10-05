import 'package:material_ui/material_ui.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import '../../../theme/surffile_appearance_slots.dart';
import 'package:surf_file/theme/folder_transition.dart';
import 'package:surf_file/theme/explorer_colors.dart';
import 'package:super_container_layout/widgets/super_container.dart';

import '../../../models/selection_mode.dart';
import 'explorer_action_bar.dart';
import 'explorer_view_toggle.dart';
import 'explorer_selection_mode_button.dart';
import '../../folder_size/folder_size_indicator.dart';

/// En-tête du dossier courant : icône, nom, nombre d'éléments et bascule
/// liste / grille.
class ExplorerViewModeBar extends StatelessWidget {
  const ExplorerViewModeBar({
    required this.title,
    required this.itemCount,
    required this.gridView,
    required this.onGridViewChanged,
    this.columnView = false,
    this.onColumnViewChanged,
    this.heatmapView = false,
    this.onHeatmapViewChanged,
    this.pending = false,
    this.titleIconKey,
    this.filterCount = 0,
    this.filterOpen = false,
    this.onToggleFilter,
    this.selectionMode = SelectionMode.standard,
    this.onSelectionModeChanged,
    this.actions = const [],
    super.key,
  });

  final String title;
  final int itemCount;

  /// Liste en cours de chargement : le compteur affiche « … ».
  final bool pending;
  final bool gridView;
  final ValueChanged<bool> onGridViewChanged;

  /// Navigation en colonnes (à la place de la liste ou de la grille).
  final bool columnView;
  final ValueChanged<bool>? onColumnViewChanged;

  /// Carte thermique des tailles (à la place de la liste ou de la grille).
  final bool heatmapView;
  final ValueChanged<bool>? onHeatmapViewChanged;

  /// Clé de l'icône dossier, cible de la transition « heroIcon ».
  final Key? titleIconKey;

  /// Critères de filtre actifs (badge sur l'icône).
  final int filterCount;
  final bool filterOpen;
  final VoidCallback? onToggleFilter;

  /// Mode de sélection ; le sélecteur n'apparaît que si
  /// [onSelectionModeChanged] est fourni.
  final SelectionMode selectionMode;
  final ValueChanged<SelectionMode>? onSelectionModeChanged;

  /// Boutons d'action sur les éléments, à gauche de la barre.
  final List<ExplorerBarAction> actions;

  /// Largeur en dessous de laquelle les actions passent dans un menu.
  static const compactActionsWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    final style = appearance.style('explorerViewModeBar');
    return SuperContainer(
      key: const ValueKey('explorer-view-mode-bar-surface'),
      slot: SurfFileAppearanceSlots.explorerViewModeBar,
      fallbackColor: explorerColor(
        context,
        Colors.white,
        Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      borderColor: Theme.of(context).colorScheme.outlineVariant,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        //padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (actions.isNotEmpty) ...[
                ExplorerActionBar(
                  actions: actions,
                  compact: constraints.maxWidth < compactActionsWidth,
                ),
                const SizedBox(width: 10),
              ],
              if (appearance.folderTransition == FolderTransition.heroIcon) ...[
                Icon(
                  Icons.folder_rounded,
                  key: titleIconKey,
                  size: 28,
                  color: appearance.accent,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: style.foreground,
                  ),
                ),
              ),
              if (!gridView && !columnView && !heatmapView) ...[
                const FolderSizeDisplayButton(),
                const SizedBox(width: 4),
              ],
              if (onToggleFilter != null) ...[
                _filterButton(context),
                const SizedBox(width: 4),
              ],
              if (onSelectionModeChanged != null) ...[
                ExplorerSelectionModeButton(
                  mode: selectionMode,
                  onChanged: onSelectionModeChanged!,
                ),
                const SizedBox(width: 12),
              ] else if (onToggleFilter != null)
                const SizedBox(width: 8),
              Text(
                pending
                    ? '…'
                    : '$itemCount élément${itemCount == 1 ? '' : 's'}',
                style: TextStyle(
                  color:
                      style.foreground ??
                      explorerColor(
                        context,
                        const Color(0xFF82899A),
                        Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 14),
              ExplorerViewToggle(
                gridView: gridView,
                onChanged: onGridViewChanged,
                columnView: columnView,
                onColumnViewChanged: onColumnViewChanged,
                heatmapView: heatmapView,
                onHeatmapViewChanged: onHeatmapViewChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = filterCount > 0;
    final highlighted = active || filterOpen;
    return Tooltip(
      message: filterOpen
          ? 'Masquer les filtres (Ctrl+Maj+F)'
          : 'Filtres (Ctrl+Maj+F)',
      child: InkWell(
        key: const ValueKey('filter-toggle'),
        borderRadius: BorderRadius.circular(8),
        onTap: onToggleFilter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: highlighted
                ? colors.primary.withValues(alpha: .12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Badge(
            isLabelVisible: active,
            label: Text('$filterCount'),
            offset: const Offset(6, -6),
            child: Icon(
              active ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
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
        ),
      ),
    );
  }
}
