import 'package:material_ui/material_ui.dart';

import '../theme/explorer_colors.dart';

/// Action de la barre : désactivée quand [onPressed] est `null`.
class ExplorerBarAction {
  const ExplorerBarAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.shortcut,
    this.destructive = false,
    this.separatorBefore = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Raccourci clavier affiché dans l'infobulle et le menu.
  final String? shortcut;
  final bool destructive;

  /// Filet de séparation avant cette action.
  final bool separatorBefore;

  String get tooltip => shortcut == null ? label : '$label ($shortcut)';
}

/// Boutons d'action sur les éléments (nouveau dossier, couper, copier,
/// coller, renommer, supprimer…). En mode [compact], ils sont regroupés dans
/// un menu.
class ExplorerActionBar extends StatelessWidget {
  const ExplorerActionBar({
    required this.actions,
    this.compact = false,
    super.key,
  });

  final List<ExplorerBarAction> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) return _menu(context);
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in actions) ...[
          if (action.separatorBefore)
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: colors.outlineVariant,
            ),
          _ActionButton(action: action),
        ],
      ],
    );
  }

  Widget _menu(BuildContext context) => PopupMenuButton<ExplorerBarAction>(
    key: const ValueKey('actions-menu'),
    tooltip: 'Actions',
    icon: const Icon(Icons.more_horiz_rounded, size: 19),
    padding: EdgeInsets.zero,
    onSelected: (action) => action.onPressed?.call(),
    itemBuilder: (context) => [
      for (final action in actions)
        PopupMenuItem(
          key: ValueKey('menu-${action.id}'),
          value: action,
          enabled: action.onPressed != null,
          child: Row(
            children: [
              Icon(action.icon, size: 18),
              const SizedBox(width: 12),
              Expanded(child: Text(action.label)),
              if (action.shortcut != null)
                Text(
                  action.shortcut!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final ExplorerBarAction action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = action.onPressed != null;
    final base = action.destructive
        ? colors.error
        : explorerColor(context, const Color(0xFF6F7689), colors.onSurface);
    return Tooltip(
      message: action.tooltip,
      child: InkWell(
        key: ValueKey('action-${action.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: action.onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            action.icon,
            size: 18,
            color: base.withValues(alpha: enabled ? 1 : .35),
          ),
        ),
      ),
    );
  }
}
