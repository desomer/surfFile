import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/widgets/super_container.dart';
import '../../../services/favorites.dart';
import 'package:super_container_layout/theme/explorer_colors.dart';

class ExplorerBreadcrumbs extends StatelessWidget {
  const ExplorerBreadcrumbs({
    required this.path,
    required this.onNavigate,
    super.key,
  });

  final String path;
  final ValueChanged<String> onNavigate;

  /// Hauteur du contenu de la barre : 3 + 40 + 3.
  static const _barHeight = 46.0;

  String _joinPath(String parent, String child) =>
      '$parent${parent.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$child';

  @override
  Widget build(BuildContext context) {
    final style = AppearanceScope.of(context).pathBarStyle;
    final colors = Theme.of(context).colorScheme;
    final foreground = style.foreground ?? colors.onSurfaceVariant;
    final normalizedPath = path.replaceAll('\\', '/');
    final parts = normalizedPath
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    final isWindows = Platform.isWindows;
    var accumulated = isWindows ? '' : Platform.pathSeparator;
    final crumbs = <({String label, String path})>[];

    for (final part in parts) {
      accumulated = accumulated.isEmpty
          ? '$part${Platform.pathSeparator}'
          : _joinPath(accumulated, part);
      crumbs.add((label: part, path: accumulated));
    }

    return SizedBox(
      height:
          _barHeight +
          style.contentPadding.vertical +
          style.outerMargin.vertical,
      child: SuperContainer(
        key: const ValueKey('path-bar-surface'),
        slot: AppearanceSlot.pathBar,
        horizontalBorder: true,
        fallbackColor: explorerColor(
          context,
          Colors.white,
          Theme.of(context).colorScheme.surfaceContainerLow,
        ),
        borderColor: explorerColor(
          context,
          const Color(0xFFEAECF2),
          Theme.of(context).colorScheme.outlineVariant,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 3, 12, 3),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Tooltip(
                        message: path,
                        child: Icon(
                          Icons.computer_rounded,
                          size: 20,
                          color: foreground,
                        ),
                      ),
                      for (final (index, crumb) in crumbs.indexed) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: foreground.withValues(alpha: .55),
                          ),
                        ),
                        InkWell(
                          onTap: index == crumbs.length - 1
                              ? null
                              : () => onNavigate(crumb.path),
                          borderRadius: BorderRadius.circular(9),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: index == crumbs.length - 1
                                  ? (style.foreground ?? colors.primary)
                                        .withValues(alpha: .10)
                                  : null,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (index == crumbs.length - 1) ...[
                                  Icon(
                                    Icons.folder_open_rounded,
                                    size: 16,
                                    color: style.foreground ?? colors.primary,
                                  ),
                                  const SizedBox(width: 7),
                                ],
                                Text(
                                  crumb.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        style.foreground ??
                                        explorerColor(
                                          context,
                                          index == crumbs.length - 1
                                              ? const Color(0xFF394154)
                                              : const Color(0xFF7D8494),
                                          index == crumbs.length - 1
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                        ),
                                    fontWeight: index == crumbs.length - 1
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              FavoriteStar(path: path, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

/// Étoile qui ajoute ou retire le dossier des favoris (Ctrl+D).
class FavoriteStar extends StatelessWidget {
  const FavoriteStar({required this.path, this.color, super.key});

  final String path;
  final Color? color;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    valueListenable: Favorites.instance,
    builder: (context, _, _) {
      final favorite = Favorites.instance.contains(path);
      return IconButton(
        key: const ValueKey('favorite-star'),
        tooltip: favorite
            ? 'Retirer des favoris (Ctrl+D)'
            : 'Ajouter aux favoris (Ctrl+D)',
        isSelected: favorite,
        onPressed: () => Favorites.instance.toggle(path),
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(
            favorite ? Icons.star_rounded : Icons.star_outline_rounded,
            key: ValueKey(favorite),
            size: 22,
            color: favorite ? const Color(0xFFFFB300) : color,
          ),
        ),
      );
    },
  );
}
