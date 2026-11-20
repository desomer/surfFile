/// Écran d'accueil permettant de démarrer un projet depuis une idée ou de reprendre un projet existant ([IdeaLauncherView]).
library;

import 'package:material_ui/material_ui.dart';

import '../services/spec_forge_controller.dart';
import '../services/spec_project_store.dart';

/// Vue d'amorçage d'un nouveau cahier des charges à partir d'une idée brute.
class IdeaLauncherView extends StatefulWidget {
  /// Crée l'écran d'accueil connecté au [controller].
  const IdeaLauncherView({required this.controller, super.key});

  /// Contrôleur principal de forge.
  final SpecForgeController controller;

  @override
  State<IdeaLauncherView> createState() => _IdeaLauncherViewState();
}

class _IdeaLauncherViewState extends State<IdeaLauncherView> {
  final _nameController = TextEditingController();
  final _ideaController = TextEditingController();
  bool _submitting = false;

  static const List<({String title, String idea})> _sampleIdeas = [
    (
      title: 'Gestion de flotte automobile',
      idea:
          'Application de suivi d’une flotte de véhicules d’entreprise : réservations par les collaborateurs, suivi kilométrique, alertes d’entretien périodique, gestion des sinistres et refacturation par service.',
    ),
    (
      title: 'Location & maintenance matériels',
      idea:
          'Plateforme B2B de location de matériel de chantier : catalogue, devis, contrats de location, check-in/check-out avec état des lieux, facturation au prorata et maintenance préventive.',
    ),
    (
      title: 'Portail SAV & tickets clients',
      idea:
          'Outil de support client multi-équipes avec portail client, SLA par niveau de contrat, escalade automatique, base de connaissances et suivi des interventions terrain.',
    ),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _ideaController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final idea = _ideaController.text.trim();
    if (idea.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.controller.createProjectFromIdea(
        idea: idea,
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final recents = widget.controller.recentProjects;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: colors.onPrimaryContainer,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SuperSpecForge',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Transformez une idée brute en cahier des charges, objets métiers et règles de gestion via un wizard de 5 agents IA spécialisés.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Nouvelle forge à partir d’une idée',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nom du projet (optionnel)',
                          hintText: 'Ex. Portail de gestion des commandes B2B',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _ideaController,
                        minLines: 4,
                        maxLines: 8,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Décrivez votre idée d’application ou de produit *',
                          hintText:
                              'Décrivez les utilisateurs, le problème à résoudre, les opérations principales… L’assistant IA va ensuite vous poser des questions étape par étape.',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Exemples :',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          for (final sample in _sampleIdeas)
                            ActionChip(
                              avatar: const Icon(Icons.bolt_rounded, size: 16),
                              label: Text(sample.title),
                              onPressed: () {
                                _nameController.text = sample.title;
                                _ideaController.text = sample.idea;
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FilledButton.icon(
                            onPressed:
                                _ideaController.text.trim().isEmpty ||
                                    _submitting
                                ? null
                                : _submit,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward_rounded),
                            label: const Text(
                              'Démarrer le wizard (Étape 1 : Cadrage)',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (recents.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  'Projets récents (${recents.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final summary in recents)
                  _RecentProjectTile(
                    summary: summary,
                    onOpen: () => widget.controller.openProject(summary.id),
                    onDelete: () => widget.controller.deleteProject(summary.id),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentProjectTile extends StatelessWidget {
  const _RecentProjectTile({
    required this.summary,
    required this.onOpen,
    required this.onDelete,
  });

  final SpecProjectSummary summary;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: colors.secondaryContainer,
          child: Icon(
            summary.currentStage.icon,
            color: colors.onSecondaryContainer,
          ),
        ),
        title: Text(
          summary.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Étape ${summary.currentStage.stepNumber}/5 (${summary.currentStage.shortLabel}) · '
          '${summary.objectCount} objet(s) · ${summary.ruleCount} règle(s)\n${summary.initialIdea}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Supprimer ce projet',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: onDelete,
            ),
            const SizedBox(width: 4),
            FilledButton.tonal(
              onPressed: onOpen,
              child: const Text('Reprendre'),
            ),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}
