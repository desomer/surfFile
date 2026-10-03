import 'package:material_ui/material_ui.dart';

import '../theme/appearance.dart';
import '../theme/appearance_slot.dart';
import '../theme/explorer_colors.dart';
import '../theme/folder_transition.dart';
import 'super_container.dart';
import 'explorer_view_toggle.dart';

/// En-tête du dossier courant : icône, nom, nombre d'éléments et bascule
/// liste / grille.
class ExplorerViewModeBar extends StatelessWidget {
  const ExplorerViewModeBar({
    required this.title,
    required this.itemCount,
    required this.gridView,
    required this.onGridViewChanged,
    this.pending = false,
    this.titleIconKey,
    this.filterCount = 0,
    this.filterOpen = false,
    this.onToggleFilter,
    super.key,
  });

  final String title;
  final int itemCount;

  /// Liste en cours de chargement : le compteur affiche « … ».
  final bool pending;
  final bool gridView;
  final ValueChanged<bool> onGridViewChanged;

  /// Clé de l'icône dossier, cible de la transition « heroIcon ».
  final Key? titleIconKey;

  /// Critères de filtre actifs (badge sur l'icône).
  final int filterCount;
  final bool filterOpen;
  final VoidCallback? onToggleFilter;

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    final style = appearance.explorerViewModeBarStyle;
    return SuperContainer(
      key: const ValueKey('explorer-view-mode-bar-surface'),
      slot: AppearanceSlot.explorerViewModeBar,
      fallbackColor: explorerColor(
        context,
        Colors.white,
        Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      borderColor: Theme.of(context).colorScheme.outlineVariant,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 10, 30, 6),
        child: Row(
          children: [
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
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  color: style.foreground,
                ),
              ),
            ),
            if (onToggleFilter != null) ...[
              _filterButton(context),
              const SizedBox(width: 12),
            ],
            Text(
              pending ? '…' : '$itemCount élément${itemCount == 1 ? '' : 's'}',
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
            ),
          ],
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
