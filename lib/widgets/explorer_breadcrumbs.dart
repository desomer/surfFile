import 'dart:io';

import 'package:material_ui/material_ui.dart';
import '../theme/explorer_colors.dart';
import '../theme/appearance.dart';
import 'styled_surface.dart';

class ExplorerBreadcrumbs extends StatelessWidget {
  const ExplorerBreadcrumbs({
    required this.path,
    required this.onNavigate,
    super.key,
  });

  final String path;
  final ValueChanged<String> onNavigate;

  String _joinPath(String parent, String child) =>
      '$parent${parent.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$child';

  @override
  Widget build(BuildContext context) {
    final style = AppearanceScope.of(context).pathBarStyle;
    final normalizedPath = path.replaceAll('\\', '/');
    final parts =
        normalizedPath.split('/').where((part) => part.isNotEmpty).toList();
    final isWindows = Platform.isWindows;
    var accumulated = isWindows ? '' : Platform.pathSeparator;
    final crumbs = <({String label, String path})>[];

    for (final part in parts) {
      accumulated = accumulated.isEmpty
          ? '$part${Platform.pathSeparator}'
          : _joinPath(accumulated, part);
      crumbs.add((label: part, path: accumulated));
    }

    return StyledSurface(
      key: const ValueKey('path-bar-surface'),
      style: style,
      horizontalBorder: true,
      fallbackColor: explorerColor(context, Colors.white,
          Theme.of(context).colorScheme.surfaceContainerLow),
      borderColor: explorerColor(context, const Color(0xFFEAECF2),
          Theme.of(context).colorScheme.outlineVariant),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Icon(Icons.computer_rounded,
                  size: 16,
                  color: style.foreground ?? Colors.blueGrey.shade400),
              for (final (index, crumb) in crumbs.indexed) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: style.foreground ?? const Color(0xFFAAB0BF),
                  ),
                ),
                InkWell(
                  onTap: index == crumbs.length - 1
                      ? null
                      : () => onNavigate(crumb.path),
                  borderRadius: BorderRadius.circular(5),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    child: Text(
                      crumb.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: style.foreground ??
                            explorerColor(
                                context,
                                index == crumbs.length - 1
                                    ? const Color(0xFF394154)
                                    : const Color(0xFF7D8494),
                                index == crumbs.length - 1
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                        fontWeight: index == crumbs.length - 1
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
