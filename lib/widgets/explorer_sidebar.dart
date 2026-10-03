import 'package:material_ui/material_ui.dart';

import '../models/explorer_location.dart';
import '../theme/appearance.dart';
import '../theme/explorer_colors.dart';
import '../theme/container_style.dart';
import '../theme/neon_style.dart';
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

  static const double width = 236;

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
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Text(
                                'ESPACE PERSONNEL',
                                style: TextStyle(
                                  color:
                                      style.foreground ??
                                      explorerColor(
                                        context,
                                        const Color(0xFF9298A8),
                                        Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final location in locations)
                              _LocationItem(
                                location: location,
                                selected: location.path == currentPath,
                                onTap: () => onLocationSelected(location.path),
                              ),
                          ],
                        ),
                        DiskSpacePanel(onNavigate: onLocationSelected),
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

class _LocationItem extends StatelessWidget {
  const _LocationItem({
    required this.location,
    required this.selected,
    required this.onTap,
  });

  final ExplorerLocation location;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    final style = selected
        ? appearance.effectiveSelectedFolderStyle
        : ContainerStyle(
            radius: 9,
            shadowOpacity: appearance.cardStyle.shadowOpacity,
            neon: const NeonStyle(),
          );
    final foreground = selected
        ? style.foreground
        : appearance.sidebarStyle.foreground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: SuperContainer(
        slot: selected ? AppearanceSlot.selectedFolder : null,
        editable: selected,
        style: style,
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
          onTap: onTap,
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
                Text(
                  location.label,
                  style: TextStyle(
                    color:
                        foreground ??
                        explorerColor(
                          context,
                          selected
                              ? const Color(0xFF354AAE)
                              : const Color(0xFF3F4656),
                          selected
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
