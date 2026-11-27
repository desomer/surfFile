/// Modèles immuables des prompts IA en Architecture Hexagonale
/// ([BuildPromptGenerationMode], [BuildHexaPromptRole], [BuildHexaPromptSpec],
/// [BuildItemPromptGroup]).
library;

import 'package:flutter/foundation.dart';

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../design_evolution_analyzer.dart';

/// Mode de génération des prompts vis-à-vis du jalon d'itération actif du domaine.
enum BuildPromptGenerationMode {
  /// Création pour les nouveaux éléments, Delta `vN → vN+1` pour les éléments modifiés ou impactés.
  autoByBaseline(
    label: 'Auto (selon jalon)',
    subtitle:
        'Création pour les nouveaux éléments, Delta vN → vN+1 pour les éléments modifiés ou impactés',
  ),

  /// Inclut systématiquement le changelog d'évolution et les consignes de migration depuis le jalon.
  evolutionDelta(
    label: 'Delta vN → vN+1',
    subtitle:
        'Inclut systématiquement le changelog d’évolution et les consignes de migration depuis le jalon',
  ),

  /// Spécification complète autonome sans historique d'itération.
  fullFromScratch(
    label: 'Complet (from scratch)',
    subtitle: 'Spécification complète autonome sans historique d’itération',
  );

  const BuildPromptGenerationMode({
    required this.label,
    required this.subtitle,
  });

  /// Libellé court affiché dans les sélecteurs de mode.
  final String label;

  /// Description synthétique du comportement de génération.
  final String subtitle;
}

/// Sous-rôle d'un prompt de génération de code en Architecture Hexagonale.
enum BuildHexaPromptRole {
  /// Implémentation de la couche ou de l'adaptateur ciblé.
  implementation(
    label: 'Implémentation',
    subtitle: 'Code de production en Architecture Hexagonale',
  ),

  /// Suite de tests unitaires TDD associée.
  unitTest(
    label: 'Test unitaire',
    subtitle: 'Tests unitaires TDD rapides et déterministes',
  );

  const BuildHexaPromptRole({required this.label, required this.subtitle});

  /// Libellé court affiché sur le badge du prompt.
  final String label;

  /// Description synthétique du périmètre couvert par le prompt.
  final String subtitle;

  /// Convertit vers le sous-rôle correspondant de [BuildTechStackProfile].
  BuildTechStackSubRole get toStackSubRole => switch (this) {
    BuildHexaPromptRole.implementation => BuildTechStackSubRole.implementation,
    BuildHexaPromptRole.unitTest => BuildTechStackSubRole.unitTest,
  };
}

/// Prompt individuel prêt à être copié et exécuté.
@immutable
class BuildHexaPromptSpec {
  /// Crée une fiche de prompt IA en Architecture Hexagonale.
  const BuildHexaPromptSpec({
    required this.id,
    required this.section,
    required this.role,
    required this.title,
    required this.summary,
    required this.promptMarkdown,
    this.item,
    this.isEvolutionDelta = false,
    this.baselineLabel,
    this.baselineVersion,
    this.changeBump = SemVerBump.none,
  });

  /// Identifiant unique stable (`<kind>:<itemId>:<section>:<role>` ou `standalone:<section>:<role>`).
  final String id;

  /// Élément de design auquel se rattache ce prompt (`null` pour Outbound / Inbound autonomes).
  final BuildDesignItem? item;

  /// Partie architecturale ciblée (`domain`, `useCaseSaga`, `outbound`, `inbound`, `persistence`).
  final BuildTechStackSection section;

  /// Sous-rôle architectural du prompt (`implementation`, `unitTest`).
  final BuildHexaPromptRole role;

  /// Titre lisible du prompt.
  final String title;

  /// Résumé court du livrable attendu.
  final String summary;

  /// Contenu complet du prompt au format Markdown.
  final String promptMarkdown;

  /// Indique si ce prompt contient un bloc d'évolution et de migration inter-itérations.
  final bool isEvolutionDelta;

  /// Libellé du jalon d'itération utilisé comme référence lorsque [isEvolutionDelta] vaut `true`.
  final String? baselineLabel;

  /// Version sémantique précédente dans le jalon lorsque [isEvolutionDelta] vaut `true`.
  final String? baselineVersion;

  /// Niveau d'incrément SemVer associé au delta lorsque [isEvolutionDelta] vaut `true`.
  final SemVerBump changeBump;

  /// Libellé synthétique de la cible (nom de l'item ou nom de la section autonome).
  String get targetLabel => item?.name ?? section.label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildHexaPromptSpec &&
          other.id == id &&
          other.item == item &&
          other.section == section &&
          other.role == role &&
          other.title == title &&
          other.summary == summary &&
          other.promptMarkdown == promptMarkdown &&
          other.isEvolutionDelta == isEvolutionDelta &&
          other.baselineLabel == baselineLabel &&
          other.baselineVersion == baselineVersion &&
          other.changeBump == changeBump;

  @override
  int get hashCode => Object.hash(
    id,
    item,
    section,
    role,
    title,
    summary,
    promptMarkdown,
    isEvolutionDelta,
    baselineLabel,
    baselineVersion,
    changeBump,
  );
}

/// Groupe de prompts IA rattachés à un [BuildDesignItem] sélectionné ou à une
/// section autonome de niveau domaine (`Outbound`, `Inbound`).
@immutable
class BuildItemPromptGroup {
  /// Crée un groupe de prompts pour un élément de design [item].
  BuildItemPromptGroup({
    required BuildDesignItem this.item,
    required List<BuildHexaPromptSpec> prompts,
  }) : standaloneSection = null,
       groupId = '${item.kind.name}:${item.id}',
       groupTitle = item.name,
       groupSubtitle = item.subtitle,
       kindLabel = item.kind.shortLabel,
       primaryBadge = item.primaryBadge,
       prompts = List<BuildHexaPromptSpec>.unmodifiable(prompts);

  /// Crée un groupe autonome sans rattachement à un item (ex. `Outbound`,
  /// `Inbound`, `Boilerplate`, `Dev Tools`, `Check Integration`, `Playground`).
  BuildItemPromptGroup.standalone({
    required BuildTechStackSection section,
    required String subtitle,
    required String domainCode,
    required List<BuildHexaPromptSpec> prompts,
    this.kindLabel = 'Ports & Adaptateurs',
  }) : item = null,
       standaloneSection = section,
       groupId = 'standalone:${section.name}',
       groupTitle = section.label,
       groupSubtitle = subtitle,
       primaryBadge = domainCode,
       prompts = List<BuildHexaPromptSpec>.unmodifiable(prompts);

  /// Élément de design sélectionné (`Modèle`, `Use Case` ou `Saga`), ou `null`
  /// pour un groupe autonome sans rattachement.
  final BuildDesignItem? item;

  /// Section autonome lorsque [item] est `null` (`outbound` ou `inbound`).
  final BuildTechStackSection? standaloneSection;

  /// Identifiant stable du groupe dans l'interface.
  final String groupId;

  /// Titre principal du groupe.
  final String groupTitle;

  /// Sous-titre descriptif optionnel.
  final String groupSubtitle;

  /// Badge de catégorie du groupe (`Modèle`, `Use Case`, `Saga`, `Ports & Adaptateurs`).
  final String kindLabel;

  /// Badge secondaire (type DSL, code `UC-xxx`, ou `domainCode`).
  final String primaryBadge;

  /// Liste ordonnée des prompts IA du groupe.
  final List<BuildHexaPromptSpec> prompts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildItemPromptGroup &&
          other.item == item &&
          other.standaloneSection == standaloneSection &&
          other.groupId == groupId &&
          other.groupTitle == groupTitle &&
          other.groupSubtitle == groupSubtitle &&
          other.kindLabel == kindLabel &&
          other.primaryBadge == primaryBadge &&
          listEquals(other.prompts, prompts);

  @override
  int get hashCode => Object.hash(
    item,
    standaloneSection,
    groupId,
    groupTitle,
    groupSubtitle,
    kindLabel,
    primaryBadge,
    Object.hashAll(prompts),
  );
}
