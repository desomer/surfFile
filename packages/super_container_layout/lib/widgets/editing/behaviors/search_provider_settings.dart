/// Configuration de l'action « Lancer une recherche » ([SearchProviderSettings]).
///
/// Étape du wizard de comportements qui liste les providers du registre
/// (`store.providers`) et ouvre le gestionnaire de providers pour en créer ou
/// en modifier un.
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';

import '../../../services/repositories/json_repository_store.dart';
import '../providers/data_provider_manager.dart';

/// Choix du provider lancé par une action `searchProvider`.
class SearchProviderSettings extends StatefulWidget {
  /// Crée le sélecteur ; [onSelected] reçoit l'identifiant choisi.
  const SearchProviderSettings({
    required this.store,
    required this.selectedId,
    required this.onSelected,
    this.managerContext,
    super.key,
  });

  /// Store dont les providers sont proposés.
  final JsonRepositoryStore? store;

  /// Provider actuellement choisi.
  final String? selectedId;

  /// Appelé avec l'identifiant du provider choisi ou créé.
  final ValueChanged<String> onSelected;

  /// Contexte depuis lequel ouvrir le gestionnaire de providers (il doit voir
  /// le même `JsonRepositoryScope` que [store]) ; défaut : ce widget.
  final BuildContext? managerContext;

  @override
  State<SearchProviderSettings> createState() => _SearchProviderSettingsState();
}

class _SearchProviderSettingsState extends State<SearchProviderSettings> {
  @override
  void initState() {
    super.initState();
    final store = widget.store;
    if (store != null) unawaited(store.providers.ensureLoaded());
  }

  Future<void> _openManager({bool createNew = false}) async {
    final launcher = widget.managerContext;
    final id = await DataProviderManager.show(
      launcher != null && launcher.mounted ? launcher : context,
      initialProviderId: createNew ? null : widget.selectedId,
      createNew: createNew,
    );
    if (id != null && mounted) widget.onSelected(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = widget.store;
    if (store == null) {
      return const Text(
        'Service de repositories indisponible : aucun provider ne peut être '
        'lancé.',
      );
    }
    final registry = store.providers;
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final providers = registry.providers;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Provider à lancer',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'La recherche lit les paramètres dans le repository de filtre '
                'du provider, appelle sa source (API…) puis écrit les lignes '
                'dans son repository de résultats.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (providers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Aucun provider : créez-en un pour continuer.',
                    key: ValueKey('behavior-provider-empty'),
                  ),
                )
              else
                for (final provider in providers)
                  ListTile(
                    key: ValueKey('behavior-provider-${provider.id}'),
                    dense: true,
                    leading: Icon(
                      provider.id == widget.selectedId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(provider.label),
                    subtitle: Text(
                      '${provider.id} · '
                      '${registry.isEditable(provider.id) ? 'éditeur' : 'code'}',
                    ),
                    selected: provider.id == widget.selectedId,
                    onTap: () => widget.onSelected(provider.id),
                  ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('behavior-provider-create'),
                    onPressed: () => _openManager(createNew: true),
                    icon: const Icon(Icons.add),
                    label: const Text('Créer un provider…'),
                  ),
                  if (providers.isNotEmpty)
                    TextButton.icon(
                      key: const ValueKey('behavior-provider-manage'),
                      onPressed: _openManager,
                      icon: const Icon(Icons.tune),
                      label: const Text('Gérer les providers…'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
