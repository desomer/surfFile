import 'package:material_ui/material_ui.dart';

import '../theme/explorer_colors.dart';
import '../theme/appearance.dart';
import 'appearance_settings.dart';
import 'super_container.dart';

class ExplorerToolbar extends StatelessWidget {
  const ExplorerToolbar({
    required this.canGoBack,
    required this.canGoUp,
    required this.onBack,
    required this.onUp,
    required this.onRefresh,
    required this.onSearchChanged,
    required this.onCreateFolder,
    this.canGoForward = false,
    this.onForward,
    this.split = false,
    this.onToggleSplit,
    super.key,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback? onForward;
  final bool canGoUp;
  final VoidCallback onBack;
  final VoidCallback onUp;
  final VoidCallback onRefresh;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCreateFolder;
  final bool split;
  final VoidCallback? onToggleSplit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final navigation = Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NavigationButton(
              tooltip: 'Retour',
              onPressed: canGoBack ? onBack : null,
              icon: Icons.arrow_back_rounded,
            ),
            _NavigationButton(
              tooltip: 'Suivant',
              onPressed: canGoForward ? onForward : null,
              icon: Icons.arrow_forward_rounded,
            ),
            _NavigationButton(
              tooltip: 'Dossier parent',
              onPressed: canGoUp ? onUp : null,
              icon: Icons.arrow_upward_rounded,
            ),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: colors.outlineVariant,
            ),
            _NavigationButton(
              tooltip: 'Actualiser',
              onPressed: onRefresh,
              icon: Icons.refresh_rounded,
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final actions = [
            if (compact)
              IconButton.filled(
                tooltip: 'Nouveau dossier',
                onPressed: onCreateFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  maximumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            else
              FilledButton.icon(
                onPressed: onCreateFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                label: const Text('Nouveau dossier'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            if (onToggleSplit != null) ...[
              const SizedBox(width: 8),
              _NavigationButton(
                key: const ValueKey('split-view'),
                tooltip: split ? 'Fermer la vue partagée' : 'Vue partagée',
                icon: Icons.vertical_split_outlined,
                selected: split,
                onPressed: onToggleSplit,
              ),
            ],
            if (AppearanceScope.controllerOf(context) != null) ...[
              const SizedBox(width: 8),
              _NavigationButton(
                tooltip: 'Paramètres d’apparence',
                icon: Icons.settings_outlined,
                onPressed: () => AppearanceSettings.show(context),
              ),
              if (StyleEditScope.controllerOf(context) case final editMode?)
                _NavigationButton(
                  key: const ValueKey('style-edit-mode'),
                  tooltip: editMode.value
                      ? 'Quitter l’édition du style'
                      : 'Éditer le style (clic droit sur une zone)',
                  icon: Icons.brush_outlined,
                  selected: editMode.value,
                  onPressed: () => editMode.value = !editMode.value,
                ),
            ],
          ];
          final search = _SearchBox(onChanged: onSearchChanged);
          return compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [navigation, const Spacer(), ...actions]),
                    const SizedBox(height: 8),
                    search,
                  ],
                )
              : Row(
                  children: [
                    navigation,
                    const SizedBox(width: 16),
                    Expanded(child: search),
                    const SizedBox(width: 16),
                    ...actions,
                  ],
                );
        },
      ),
    );
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    isSelected: selected,
    icon: Icon(icon, size: 20),
    style: IconButton.styleFrom(
      minimumSize: const Size(36, 36),
      maximumSize: const Size(36, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      foregroundColor: selected
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : Theme.of(context).colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Rechercher dans ce dossier',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: explorerColor(
            context,
            Colors.white,
            colors.surfaceContainerLow,
          ),
          hintStyle: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          prefixIconColor: colors.onSurfaceVariant,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.primary, width: 2),
          ),
        ),
      ),
    );
  }
}
