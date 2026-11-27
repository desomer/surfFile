/// Page de liens de l'onglet Spec du `NavigationRail` ([SpecLinksView]).
library;

import 'package:material_ui/material_ui.dart';

import '../models/spec_forge_project.dart';
import '../services/cost_calculator.dart';
import 'design_links_view.dart';

/// Vue principale de l'onglet Spec présentant des cartes-liens vers
/// l'écran Projets ([IdeaLauncherView]), les Wizards de spécification et
/// les référentiels d'entreprise.
class SpecLinksView extends StatelessWidget {
  /// Crée la page de liens Spec.
  const SpecLinksView({
    this.activeProject,
    this.recentProjectsCount = 0,
    this.companyGlossaryTermsCount = 0,
    this.enterpriseRateCardProfilesCount = 0,
    this.onLinkTap,
    super.key,
  });

  /// Projet actuellement ouvert en mémoire, le cas échéant.
  final SpecForgeProject? activeProject;

  /// Libellés partagés par les cartes et le titre de la page ouverte.
  static const projectsLabel = 'Projets';
  static const initiativesLabel = 'Initiatives & Features';
  static const projectLexiconLabel = 'Lexique du projet';
  static const glossaryLabel = 'Glossaire d’entreprise';
  static const modelingDictionaryLabel = 'Dictionnaire technique & Modèle';
  static const enterpriseRatesLabel = 'Grille TJM & Abaques IT';
  static const uxWizardLabel = 'Wizard UX & Parcours';
  static const qaWizardLabel = 'Wizard BDD / Gherkin & TDD';
  static const costWizardLabel = 'Estimation de coût IT';

  /// Citation affichée en tête de la page Spec.
  static const quoteText =
      '« Ce n’est pas le code qui est compliqué. C’est ce qu’on croit savoir sur le métier qui l’est. »';

  /// Auteur de la citation affichée en tête de la page Spec.
  static const quoteAuthor = 'Alberto Brandolini';

  /// Nombre de projets récents enregistrés.
  final int recentProjectsCount;

  /// Nombre de termes présents dans le glossaire d'entreprise.
  final int companyGlossaryTermsCount;

  /// Nombre de profils présents dans la grille tarifaire TJM d'entreprise.
  final int enterpriseRateCardProfilesCount;

  /// Callback déclenché lors du clic sur une carte.
  final ValueChanged<DesignLinkItem>? onLinkTap;

  static String _buildCostSubtitle(SpecForgeProject? project) {
    if (project == null) {
      return 'PERT (j/h), Build/Run, TCO & gain IA';
    }
    final costSpec = project.costSpec;
    if (costSpec.wbsItems.isEmpty && costSpec.runItems.isEmpty) {
      return 'À chiffrer · ${costSpec.currency.code}';
    }
    final summary = CostCalculator.compute(costSpec);
    final buildDays = CostCalculator.formatDays(
      summary.fullLot.effectiveTotalDays,
    );
    final buildCost = CostCalculator.formatAmount(
      summary.fullLot.effectiveTotalCost,
      summary.currency,
      compact: true,
    );
    if (summary.monthlyRunYear1 > 0) {
      final runMonthly = CostCalculator.formatAmount(
        summary.monthlyRunYear1,
        summary.currency,
        compact: true,
      );
      return '$buildDays · Build $buildCost · Run $runMonthly/mois';
    }
    return '$buildDays · Build $buildCost';
  }

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
            tooltip: 'Gérer le glossaire terminologique d’entreprise partagé entre tous les projets',
          ),
          DesignLinkItem(
            id: 'modeling_dictionary',
            label: modelingDictionaryLabel,
            icon: Icons.rule_folder_outlined,
            tooltip: 'Règles techniques (Id, Ref, Code, Number, dates, booléens) et préférences globales de modélisation',
          ),
          DesignLinkItem(
            id: 'enterprise_rates',
            label: enterpriseRatesLabel,
            icon: Icons.payments_outlined,
            subtitle: enterpriseRateCardProfilesCount > 0
                ? '$enterpriseRateCardProfilesCount profil(s) TJM'
                : 'Profils TJM & abaques PERT',
            tooltip: 'Configurer la grille TJM d’entreprise, les abaques T-shirt (j/h) et les ratios FinOps partagés',
          ),
        ],
      ),
      DesignLinkSection(
        id: 'spec_workspace',
        title: 'Projets & Spécification',
        items: <DesignLinkItem>[
          DesignLinkItem(
            id: 'projects',
            label: projectsLabel,
            icon: Icons.folder_open_rounded,
            subtitle: recentProjectsCount > 0
                ? '$recentProjectsCount projet(s) récent(s)'
                : 'Nouvelle idée ou ouverture',
            tooltip: 'Démarrer une nouvelle forge depuis une idée ou reprendre un projet récent',
          ),
          DesignLinkItem(
            id: 'initiatives',
            label: initiativesLabel,
            icon: Icons.account_tree_rounded,
            subtitle: project != null
                ? '${project.initiatives.length} initiative(s) · ${project.totalFeatureCount} feature(s)'
                : 'Découpage produit par projet',
            tooltip: project != null
                ? 'Gérer les initiatives et features du projet « ${project.name} » et lancer ses Wizards'
                : 'Ouvrez ou créez d’abord un projet dans Projets',
          ),
          DesignLinkItem(
            id: 'project_lexicon',
            label: projectLexiconLabel,
            icon: Icons.menu_book_rounded,
            subtitle: project == null
                ? 'Référentiel partagé du projet'
                : '${project.lexicon.terms.length} terme(s) · Partagé inter-features',
            tooltip: project != null
                ? 'Gérer le lexique métier partagé du projet « ${project.name} » (référentiel transverse hors stepper)'
                : 'Ouvrez ou créez d’abord un projet dans Projets',
          ),
          DesignLinkItem(
            id: 'wizard',
            label: 'Wizard de spécification',
            icon: Icons.auto_awesome_rounded,
            subtitle: project == null
                ? 'Aucun projet actif'
                : (project.hasSingleDefaultFeature
                      ? project.name
                      : '${project.name} › ${project.activeFeature.displayLabel}'),
            tooltip: project != null
                ? 'Ouvrir le wizard de la feature « ${project.activeFeature.name} » (${project.name})'
                : 'Ouvrez ou créez d’abord un projet dans Projets',
          ),
          DesignLinkItem(
            id: 'ux_wizard',
            label: uxWizardLabel,
            icon: Icons.design_services_rounded,
            subtitle: project == null
                ? 'Parcours, navigation & écrans'
                : '${project.uxSpec.journeys.length} parcours · ${project.uxSpec.screens.length} écran(s)',
            tooltip: project != null
                ? 'Concevoir les parcours, la navigation et les écrans UX du projet « ${project.name} »'
                : 'Ouvrez ou créez d’abord un projet dans Projets',
          ),
          DesignLinkItem(
            id: 'qa_wizard',
            label: qaWizardLabel,
            icon: Icons.science_rounded,
            subtitle: project == null
                ? 'Jeux d’essais, .feature & TDD'
                : '${project.qaSpec.features.length} feature(s) · ${project.qaSpec.totalTddCaseCount} cas TDD',
            tooltip: project != null
                ? 'Forger les jeux d’essais, les scénarios Gherkin et les suites TDD du projet « ${project.name} »'
                : 'Ouvrez ou créez d’abord un projet dans Projets',
          ),
          DesignLinkItem(
            id: 'cost_wizard',
            label: costWizardLabel,
            icon: Icons.calculate_rounded,
            subtitle: _buildCostSubtitle(project),
            tooltip: project != null
                ? 'Chiffrer les charges PERT (j/h), les coûts Build/Run, l’impact IA et le TCO du projet « ${project.name} »'
                : 'Ouvrez ou créez d’abord un projet dans Projets',
          ),
        ],
      ),
    ];

    return DesignLinksView(
      sections: sections,
      keyPrefix: 'spec',
      header: const DesignQuoteBanner(
        key: ValueKey('spec-quote-banner'),
        quoteText: SpecLinksView.quoteText,
        quoteAuthor: SpecLinksView.quoteAuthor,
      ),
      onLinkTap: onLinkTap,
    );
  }
}
