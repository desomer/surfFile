/// Page de liens de l'onglet Spec du `NavigationRail` ([SpecLinksView]).
library;

import 'package:material_ui/material_ui.dart';

import '../models/spec_forge_project.dart';
import 'design_links_view.dart';

/// Vue principale de l'onglet Spec présentant des cartes-liens vers
/// l'écran Projets ([IdeaLauncherView]), le Wizard de spécification et
/// le Glossaire d'entreprise.
class SpecLinksView extends StatelessWidget {
  /// Crée la page de liens Spec.
  const SpecLinksView({
    this.activeProject,
    this.recentProjectsCount = 0,
    this.companyGlossaryTermsCount = 0,
    this.onLinkTap,
    super.key,
  });

  /// Projet actuellement ouvert en mémoire, le cas échéant.
  final SpecForgeProject? activeProject;

  /// Libellés partagés par les cartes et le titre de la page ouverte.
  static const projectsLabel = 'Projets';
  static const glossaryLabel = 'Glossaire d’entreprise';

  /// Nombre de projets récents enregistrés.
  final int recentProjectsCount;

  /// Nombre de termes présents dans le glossaire d'entreprise.
  final int companyGlossaryTermsCount;

  /// Callback déclenché lors du clic sur une carte.
  final ValueChanged<DesignLinkItem>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final project = activeProject;
    final sections = <DesignLinkSection>[
      DesignLinkSection(
        id: 'enterprise',
        title: 'Entreprise',
        items: <DesignLinkItem>[
          DesignLinkItem(
            id: 'company_glossary',
            label: glossaryLabel,
            icon: Icons.language_rounded,
            subtitle: companyGlossaryTermsCount > 0
                ? '$companyGlossaryTermsCount terme(s)'
                : 'Référentiel partagé',
            tooltip:
                'Gérer le glossaire terminologique d’entreprise partagé entre tous les projets',
          ),
        ],
      ),
      DesignLinkSection(
        id: 'spec_workspace',
        title: 'Spécification & Projets',
        items: <DesignLinkItem>[
          DesignLinkItem(
            id: 'projects',
            label: projectsLabel,
            icon: Icons.folder_open_rounded,
            subtitle: recentProjectsCount > 0
                ? '$recentProjectsCount projet(s) récent(s)'
                : 'Nouvelle idée ou ouverture',
            tooltip:
                'Démarrer une nouvelle forge depuis une idée ou reprendre un projet récent',
          ),
          DesignLinkItem(
            id: 'wizard',
            label: 'Wizard de spécification',
            icon: Icons.auto_awesome_rounded,
            subtitle: project != null
                ? project.name
                : 'Aucun projet actif',
            tooltip: project != null
                ? 'Ouvrir le wizard du projet « ${project.name} »'
                : 'Ouvrez ou créez d’abord un projet dans Projets',
          ),
        ],
      ),
    ];

    return DesignLinksView(
      sections: sections,
      keyPrefix: 'spec',
      onLinkTap: onLinkTap,
    );
  }
}
