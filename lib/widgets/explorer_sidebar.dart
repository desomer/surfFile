import 'package:material_ui/material_ui.dart';

import '../models/explorer_location.dart';
import '../services/favorites.dart';
import '../theme/appearance.dart';
import '../theme/explorer_colors.dart';
import '../theme/appearance_slot.dart';
import 'super_container.dart';
import 'disk_space_panel.dart';

class ExplorerSidebar extends StatelessWidget {
  const ExplorerSidebar({
    required this.locations,
    required this.currentPath,
    required this.onLocationSelected,
    super.key,
  });

  static const double width = Appearance.defaultSidebarWidth;

  /// Onglet affiché (0 : espace perso, 1 : favoris), commun aux deux volets.
  static final tab = ValueNotifier(0);

  final List<ExplorerLocation> locations;
  final String currentPath;
  final ValueChanged<String> onLocationSelected;

  @override
  Widget build(BuildContext context) {
    final style = AppearanceScope.of(context).sidebarStyle;
    return SuperContainer(
      key: const ValueKey('sidebar-surface'),
      slot: AppearanceSlot.sidebar,
      fallbackColor: explorerColor(
        context,
        const Color(0xFFF1F3F8),
        Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      borderColor: Theme.of(context).colorScheme.outlineVariant,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(14, 18, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 8, 24),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: explorerColor(
                        context,
                        const Color(0xFF5268D9),
                        Theme.of(context).colorScheme.primary,
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.folder_open_rounded,
                      color: explorerColor(
                        context,
                        Colors.white,
                        Theme.of(context).colorScheme.onPrimary,
                      ),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'SurfFile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: style.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SidebarTabs(foreground: style.foreground),
                            const SizedBox(height: 10),
                            ValueListenableBuilder<int>(
                              valueListenable: tab,
                              builder: (context, index, _) => AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: index == 0
                                    ? Column(
                                        key: const ValueKey('sidebar-personal'),
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (final location in locations)
                                            _LocationItem(
                                              location: location,
                                              selected:
                                                  location.path == currentPath,
                                              onTap: () => onLocationSelected(
                                                location.path,
                                              ),
                                            ),
                                        ],
                                      )
                                    : _FavoritesList(
                                        key: const ValueKey(
                                          'sidebar-favorites',
                                        ),
                                        currentPath: currentPath,
                                        onSelected: onLocationSelected,
                                        foreground: style.foreground,
                                      ),
                              ),
                            ),
                          ],
                        ),
                        DiskSpacePanel(
                          currentPath: currentPath,
                          onNavigate: onLocationSelected,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarTabs extends StatelessWidget {
  const _SidebarTabs({this.foreground});

  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = foreground ?? colors.onSurfaceVariant;
    return ValueListenableBuilder<int>(
      valueListenable: ExplorerSidebar.tab,
      builder: (context, current, _) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: muted.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            for (final (index, label, icon) in const [
              (0, 'Espace perso', Icons.person_outline_rounded),
              (1, 'Favoris', Icons.star_rounded),
            ])
              Expanded(
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: Favorites.instance,
                  builder: (context, favorites, _) {
                    final selected = index == current;
                    final color = selected ? colors.primary : muted;
                    return Material(
                      key: ValueKey('sidebar-tab-$index'),
                      color: selected ? colors.surface : Colors.transparent,
                      elevation: selected ? 1 : 0,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => ExplorerSidebar.tab.value = index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icon,
                                size: 15,
                                color: index == 1 && selected
                                    ? const Color(0xFFFFB300)
                                    : color,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  index == 1 && favorites.isNotEmpty
                                      ? '$label (${favorites.length})'
                                      : label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 12,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesList extends StatelessWidget {
  const _FavoritesList({
    required this.currentPath,
    required this.onSelected,
    this.foreground,
    super.key,
  });

  final String currentPath;
  final ValueChanged<String> onSelected;
  final Color? foreground;

  static String _label(String path) {
    final parts = path
        .split(RegExp(r'[\\/]'))
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? path : parts.last;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    valueListenable: Favorites.instance,
    builder: (context, favorites, _) {
      if (favorites.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            'Aucun favori.\nCliquez sur l’étoile ☆ de la barre du chemin '
            'ou appuyez sur Ctrl+D.',
            style: TextStyle(
              color:
                  foreground ?? Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        );
      }
      return ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: Favorites.instance.move,
        children: [
          for (final (index, path) in favorites.indexed)
            ReorderableDragStartListener(
              key: ValueKey('favorite-$path'),
              index: index,
              child: _LocationItem(
                location: ExplorerLocation(
                  _label(path),
                  path,
                  Icons.folder_special_rounded,
                ),
                tooltip: path,
                selected: path.toLowerCase() == currentPath.toLowerCase(),
                onTap: () => onSelected(path),
                onRemove: () => Favorites.instance.remove(path),
              ),
            ),
        ],
      );
    },
  );
}

class _LocationItem extends StatefulWidget {
  const _LocationItem({
    required this.location,
    required this.selected,
    required this.onTap,
    this.tooltip,
    this.onRemove,
  });

  final ExplorerLocation location;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  /// Affiche au survol un bouton pour retirer l'élément (favoris).
  final VoidCallback? onRemove;

  @override
  State<_LocationItem> createState() => _LocationItemState();
}

class _LocationItemState extends State<_LocationItem> {
  bool _hovered = false;

  ExplorerLocation get location => widget.location;
  bool get selected => widget.selected;

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    final style = selected
        ? appearance.effectiveSelectedFolderStyle
        : appearance.effectiveFolderStyle;
    final foreground = selected
        ? style.foreground
        : style.foreground ?? appearance.sidebarStyle.foreground;
    final item = Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: SuperContainer(
        slot: selected ? AppearanceSlot.selectedFolder : AppearanceSlot.folder,
        borderColor: Theme.of(context).colorScheme.primary,
        fallbackColor: selected
            ? explorerColor(
                context,
                const Color(0xFFE2E7FC),
                Theme.of(context).colorScheme.primaryContainer,
              )
            : Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(style.radius),
          onTap: widget.onTap,
          onHover: (hovered) => setState(() => _hovered = hovered),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 11),
                Icon(
                  location.icon,
                  size: 19,
                  color:
                      foreground ??
                      explorerColor(
                        context,
                        selected
                            ? const Color(0xFF5268D9)
                            : const Color(0xFF70788B),
                        selected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    location.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          foreground ??
                          explorerColor(
                            context,
                            selected
                                ? const Color(0xFF354AAE)
                                : const Color(0xFF3F4656),
                            selected
                                ? Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.onRemove != null && _hovered)
                  IconButton(
                    tooltip: 'Retirer des favoris',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: widget.onRemove,
                    icon: Icon(
                      Icons.close_rounded,
                      color:
                          foreground ??
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? item
        : Tooltip(
            message: widget.tooltip,
            waitDuration: const Duration(milliseconds: 600),
            child: item,
          );
  }
}
