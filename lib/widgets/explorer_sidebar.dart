import 'package:material_ui/material_ui.dart';

import '../models/explorer_location.dart';
import '../theme/appearance.dart';
import '../theme/explorer_colors.dart';
import '../theme/container_style.dart';
import '../theme/neon_style.dart';
import 'styled_surface.dart';

class ExplorerSidebar extends StatelessWidget {
  const ExplorerSidebar({
    required this.locations,
    required this.currentPath,
    required this.onLocationSelected,
    super.key,
  });

  final List<ExplorerLocation> locations;
  final String currentPath;
  final ValueChanged<String> onLocationSelected;

  @override
  Widget build(BuildContext context) {
    final style = AppearanceScope.of(context).sidebarStyle;
    return StyledSurface(
      key: const ValueKey('sidebar-surface'),
      style: style,
      fallbackColor: explorerColor(context, const Color(0xFFF1F3F8),
          Theme.of(context).colorScheme.surfaceContainerLow),
      borderColor: Theme.of(context).colorScheme.outlineVariant,
      child: Container(
        width: 236,
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
                      color: explorerColor(context, const Color(0xFF5268D9),
                          Theme.of(context).colorScheme.primary),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.folder_open_rounded,
                      color: explorerColor(context, Colors.white,
                          Theme.of(context).colorScheme.onPrimary),
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
                          color: style.foreground),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                'ESPACE PERSONNEL',
                style: TextStyle(
                  color: style.foreground ??
                      explorerColor(context, const Color(0xFF9298A8),
                          Theme.of(context).colorScheme.onSurfaceVariant),
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
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: explorerColor(
                    context,
                    Colors.white.withValues(alpha: .75),
                    Theme.of(context).colorScheme.surfaceContainer),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: explorerColor(context, const Color(0xFFE7E9F0),
                      Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tips_and_updates_outlined,
                    size: 18,
                    color: explorerColor(context, const Color(0xFF68728B),
                        Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Vos fichiers, à portée de main.',
                      style: TextStyle(
                          fontSize: 12,
                          color: explorerColor(context, const Color(0xFF68728B),
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  ),
                ],
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
            shadowOpacity: appearance.shadowOpacity,
            neon: const NeonStyle());
    final foreground =
        selected ? style.foreground : appearance.sidebarStyle.foreground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: StyledSurface(
        style: style,
        borderColor: Theme.of(context).colorScheme.primary,
        fallbackColor: selected
            ? explorerColor(context, const Color(0xFFE2E7FC),
                Theme.of(context).colorScheme.primaryContainer)
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
                  color: foreground ??
                      explorerColor(
                          context,
                          selected
                              ? const Color(0xFF5268D9)
                              : const Color(0xFF70788B),
                          selected
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 11),
                Text(
                  location.label,
                  style: TextStyle(
                    color: foreground ??
                        explorerColor(
                            context,
                            selected
                                ? const Color(0xFF354AAE)
                                : const Color(0xFF3F4656),
                            selected
                                ? Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                : Theme.of(context).colorScheme.onSurface),
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
