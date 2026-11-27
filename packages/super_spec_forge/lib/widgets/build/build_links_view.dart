/// Page de liens de l'onglet Build du `NavigationRail` ([BuildLinksView]).
library;

import 'package:material_ui/material_ui.dart';

import '../design_links_view.dart';

/// Vue principale de l'onglet Build présentant des cartes-liens vers
/// la gestion des stacks techniques et la génération des prompts agentiques.
class BuildLinksView extends StatelessWidget {
  /// Crée la page d'actions Build.
  const BuildLinksView({
    this.techStacksCount = 0,
    this.domainsCount = 0,
    this.onLinkTap,
    super.key,
  });

  /// Libellés partagés par les cartes et la barre d'application.
  static const techStacksLabel = 'Stacks techniques';
  static const agenticPromptsLabel = 'Prompts agentiques';

  /// Citation affichée en tête de la page Build.
  static const quoteText =
      '« Rendez d’abord les changements faciles, puis faites les changements faciles. »';

  /// Auteur de la citation affichée en tête de la page Build.
  static const quoteAuthor = 'Kent Beck';

  /// Nombre de profils de stacks techniques configurés dans le catalogue.
  final int techStacksCount;

  /// Nombre de domaines fonctionnels définis dans le catalogue.
  final int domainsCount;

  /// Callback déclenchée lors du clic sur une carte.
  final ValueChanged<DesignLinkItem>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final sections = <DesignLinkSection>[
      DesignLinkSection(
        id: 'build_workspace',
        title: 'Atelier Build',
        items: <DesignLinkItem>[
          DesignLinkItem(
            id: 'tech_stacks',
            label: techStacksLabel,
            icon: Icons.layers_rounded,
            subtitle: techStacksCount > 0
                ? '$techStacksCount profil(s) · Arborescences & règles'
                : 'Stacks, dossiers & règles Markdown',
            tooltip:
                'Configurer les profils de stacks techniques, les arborescences cibles, les règles Markdown et la Documentation IA',
          ),
          DesignLinkItem(
            id: 'agentic_prompts',
            label: agenticPromptsLabel,
            icon: Icons.terminal_rounded,
            subtitle: domainsCount > 0
                ? '$domainsCount domaine(s) · Architecture Hexagonale'
                : 'Suivi & prompts hexagonaux',
            tooltip:
                'Suivre l’avancement des items de design et générer les prompts IA en Architecture Hexagonale',
          ),
        ],
      ),
    ];

    return DesignLinksView(
      sections: sections,
      keyPrefix: 'build',
      header: const DesignQuoteBanner(
        key: ValueKey('build-quote-banner'),
        quoteText: BuildLinksView.quoteText,
        quoteAuthor: BuildLinksView.quoteAuthor,
      ),
      onLinkTap: onLinkTap,
    );
  }
}
