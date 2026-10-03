import 'package:material_ui/material_ui.dart';

import '../models/shell_menu_item.dart';
import '../services/windows_context_menu.dart';

class ExplorerContextMenu {
  static const _back = ShellMenuItem(id: -1, label: 'Retour');
  static const _native =
      ShellMenuItem(id: -2, label: 'Afficher le menu Windows');

  static Future<ShellMenuItem?> show({
    required BuildContext context,
    required Offset position,
    required WindowsContextMenu menu,
  }) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(position);
    final anchor = RelativeRect.fromRect(
      Rect.fromLTWH(local.dx, local.dy, 0, 0),
      Offset.zero & overlay.size,
    );
    final stack = <List<ShellMenuItem>>[menu.items];

    while (true) {
      if (!context.mounted) return null;
      final selected = await showMenu<ShellMenuItem>(
        context: context,
        position: anchor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Theme.of(context).colorScheme.surface,
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
        items: [
          if (stack.length > 1)
            const PopupMenuItem(value: _back, child: Text('‹ Retour')),
          for (final item in stack.last)
            if (item.separator)
              const PopupMenuDivider()
            else if (!item.nativeOnly && item.label.isNotEmpty)
              PopupMenuItem(
                value: item,
                enabled: item.enabled,
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: item.checked
                          ? const Icon(Icons.check_rounded, size: 17)
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontWeight: item.isDefault
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (item.submenu != null)
                      const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _native,
            child: Row(
              children: [
                Icon(Icons.open_in_new_rounded, size: 17),
                SizedBox(width: 7),
                Expanded(child: Text('Afficher le menu Windows')),
              ],
            ),
          ),
        ],
      );
      if (selected == null || !context.mounted) return null;
      if (selected == _back) {
        stack.removeLast();
      } else if (selected == _native) {
        return menu.showNative();
      } else if (selected.submenu != null) {
        stack.add(await menu.submenu(selected.submenu!));
      } else {
        return selected;
      }
    }
  }
}
