import 'package:material_ui/material_ui.dart';

import '../theme/explorer_colors.dart';
import '../theme/appearance.dart';
import 'appearance_settings.dart';

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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 26, 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Retour',
            onPressed: canGoBack ? onBack : null,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          IconButton(
            tooltip: 'Suivant',
            onPressed: canGoForward ? onForward : null,
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
          IconButton(
            tooltip: 'Dossier parent',
            onPressed: canGoUp ? onUp : null,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(child: _SearchBox(onChanged: onSearchChanged)),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onCreateFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('Nouveau dossier'),
            style: FilledButton.styleFrom(
              backgroundColor: explorerColor(context, const Color(0xFF5268D9),
                  Theme.of(context).colorScheme.primary),
              foregroundColor: explorerColor(context, Colors.white,
                  Theme.of(context).colorScheme.onPrimary),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            ),
          ),
          if (AppearanceScope.controllerOf(context) != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Paramètres d’apparence',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => AppearanceSettings.show(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Rechercher dans ce dossier',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: explorerColor(context, Colors.white,
              Theme.of(context).colorScheme.surfaceContainerLow),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(
              color: explorerColor(context, const Color(0xFFE5E8F0),
                  Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(
              color: explorerColor(context, const Color(0xFFE5E8F0),
                  Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
        ),
      ),
    );
  }
}
