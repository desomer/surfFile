import 'package:material_ui/material_ui.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/theme/explorer_colors.dart';
import 'package:surf_file/widgets/dialogs/appearance_settings.dart';
import 'package:super_container_layout/widgets/appearance/appearance_toolbar.dart';

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
            SuperToolbarIconButton(
              tooltip: 'Retour',
              onPressed: canGoBack ? onBack : null,
              icon: Icons.arrow_back_rounded,
            ),
            SuperToolbarIconButton(
              tooltip: 'Suivant',
              onPressed: canGoForward ? onForward : null,
              icon: Icons.arrow_forward_rounded,
            ),
            SuperToolbarIconButton(
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
            SuperToolbarIconButton(
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
              SuperToolbarIconButton(
                key: const ValueKey('split-view'),
                tooltip: split ? 'Fermer la vue partagée' : 'Vue partagée',
                icon: Icons.vertical_split_outlined,
                selected: split,
                onPressed: onToggleSplit,
              ),
            ],
            if (AppearanceScope.controllerOf(context) != null) ...[
              const SizedBox(width: 8),
              SuperToolbarIconButton(
                tooltip: 'Paramètres d’apparence',
                icon: Icons.settings_outlined,
                onPressed: () => AppearanceSettings.show(context),
              ),
              const StyleEditModeButton(),
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
