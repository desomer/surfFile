import 'package:material_ui/material_ui.dart';

import '../../../models/shell_menu_item.dart';
import '../../../services/windows_context_menu.dart';
import '../../interaction/mouse_back_navigation.dart';

class ExplorerContextMenu {
  static const _back = ShellMenuItem(id: -1, label: 'Retour');
  static const _forward = ShellMenuItem(id: -3, label: 'Suivant');
  static const _native = ShellMenuItem(
    id: -2,
    label: 'Afficher le menu Windows',
  );

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
    final forward = <List<ShellMenuItem>>[];

    while (true) {
      if (!context.mounted) return null;
      final colors = Theme.of(context).colorScheme;
      var navigating = false;
      void navigate(BuildContext menuContext, ShellMenuItem direction) {
        if (navigating) return;
        navigating = true;
        Navigator.of(menuContext).pop(direction);
      }

      PopupMenuItem<ShellMenuItem> menuItem(
        ShellMenuItem item, {
        IconData? icon,
        String? label,
      }) {
        final foreground = item.enabled
            ? colors.onSurface
            : colors.onSurface.withValues(alpha: .38);
        return _MouseNavigationMenuItem(
          onBack: (menuContext) => navigate(menuContext, _back),
          onForward: forward.isEmpty
              ? null
              : (menuContext) => navigate(menuContext, _forward),
          value: item,
          enabled: item.enabled,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              color: states.contains(WidgetState.disabled)
                  ? colors.onSurface.withValues(alpha: .38)
                  : colors.onSurface,
              fontWeight: item.isDefault ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child:
                    item.checked || icon != null || _iconFor(item.verb) != null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          item.checked
                              ? Icons.check_rounded
                              : icon ?? _iconFor(item.verb),
                          size: 16,
                          color: item.enabled && item.isDefault
                              ? colors.primary
                              : foreground,
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  label ?? item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.submenu != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.chevron_right_rounded, size: 16, color: foreground),
              ],
            ],
          ),
        );
      }

      final selected = await showMenu<ShellMenuItem>(
        context: context,
        position: anchor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
        ),
        color: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: .2),
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
        items: [
          if (stack.length > 1)
            menuItem(_back, icon: Icons.arrow_back_rounded, label: '‹ Retour'),
          for (final item in stack.last)
            if (item.separator)
              const PopupMenuDivider(height: 8)
            else if (!item.nativeOnly && item.label.isNotEmpty)
              menuItem(item),
          const PopupMenuDivider(height: 8),
          menuItem(_native, icon: Icons.open_in_new_rounded),
        ],
      );
      if (selected == null || !context.mounted) return null;
      if (selected == _back) {
        if (stack.length == 1) return null;
        forward.add(stack.removeLast());
      } else if (selected == _forward) {
        if (forward.isNotEmpty) stack.add(forward.removeLast());
      } else if (selected == _native) {
        return menu.showNative();
      } else if (selected.submenu != null) {
        final items = await menu.submenu(selected.submenu!);
        forward.clear();
        stack.add(items);
      } else {
        return selected;
      }
    }
  }

  static IconData? _iconFor(String verb) => switch (verb.toLowerCase()) {
    'open' => Icons.open_in_new_rounded,
    'cut' => Icons.content_cut_rounded,
    'copy' => Icons.content_copy_rounded,
    'paste' => Icons.content_paste_rounded,
    'delete' => Icons.delete_outline_rounded,
    'rename' => Icons.drive_file_rename_outline_rounded,
    'properties' => Icons.info_outline_rounded,
    _ => null,
  };
}

class _MouseNavigationMenuItem extends PopupMenuItem<ShellMenuItem> {
  const _MouseNavigationMenuItem({
    required this.onBack,
    required this.onForward,
    required super.value,
    required super.enabled,
    required super.height,
    required super.padding,
    required super.labelTextStyle,
    required super.child,
  });

  final ValueChanged<BuildContext> onBack;
  final ValueChanged<BuildContext>? onForward;

  @override
  PopupMenuItemState<ShellMenuItem, _MouseNavigationMenuItem> createState() =>
      _MouseNavigationMenuItemState();
}

class _MouseNavigationMenuItemState
    extends PopupMenuItemState<ShellMenuItem, _MouseNavigationMenuItem> {
  @override
  Widget build(BuildContext context) => MouseBackNavigation(
    enabled: true,
    onBack: () => widget.onBack(context),
    forwardEnabled: widget.onForward != null,
    onForward: () => widget.onForward?.call(context),
    child: super.build(context),
  );
}
