/// Générateurs des prompts IA autonomes (sans rattachement) pour la partie
/// **Check Integration** d'un domaine
/// ([buildDomainCheckIntegrationImplementationPrompt],
/// [buildDomainCheckIntegrationUnitTestPrompt]).
library;

import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../spec_storage_slug.dart';
import 'prompt_generator_models.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Check Integration — Implémentation » au niveau du domaine.
BuildHexaPromptSpec buildDomainCheckIntegrationImplementationPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  const summary =
      'Vérification du câblage DI complet (Inbound → Application → Domain → Outbound / Persistance) et préparation des tests d’intégration.';
  final title = '${domain.name} — Check Integration (Implémentation)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.checkIntegration,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-check-integration',
      BuildHexaPromptRole.implementation,
    ),
    title: title,
    version: '1.0.0',
    domainCode: domain.domainCode,
    description: summary,
    tags: <String>[
      'hexagonal-architecture',
      if (techStack != null) techStack.code,
      domain.domainCode,
      'check-integration',
      'integration',
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.checkIntegration.slug,
      'layer': 'integration',
      'role': 'implementation',
      'artifactType': 'integration-check',
      'artifactName': domain.domainCode,
    },
    dates: dates,
  );

  final body = _formatImplementationBody(
    domain: domain,
    techStack: techStack,
    glossary: glossary,
    modelPreferences: modelPreferences,
  );

  return BuildHexaPromptSpec(
    id: 'standalone:${BuildTechStackSection.checkIntegration.name}:${BuildHexaPromptRole.implementation.name}',
    section: BuildTechStackSection.checkIntegration,
    role: BuildHexaPromptRole.implementation,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

/// Construit le prompt « Check Integration — Test unitaire » au niveau du domaine.
BuildHexaPromptSpec buildDomainCheckIntegrationUnitTestPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
}) {
  const summary =
      'Validation bout-en-bout du build, du typage, des contrats et de la suite complète de tests d’intégration du domaine.';
  final title = '${domain.name} — Check Integration (Test unitaire)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.checkIntegration,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-check-integration',
      BuildHexaPromptRole.unitTest,
    ),
    title: title,
    version: '1.0.0',
    domainCode: domain.domainCode,
    description: summary,
    tags: <String>[
      'hexagonal-architecture',
      if (techStack != null) techStack.code,
      domain.domainCode,
      'check-integration',
      'integration',
      'unit-test',
      'e2e',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.checkIntegration.slug,
      'layer': 'integration',
      'role': 'unit-test',
      'artifactType': 'integration-check',
      'artifactName': domain.domainCode,
    },
    dates: dates,
  );

  final body = _formatUnitTestBody(domain: domain, techStack: techStack);

  return BuildHexaPromptSpec(
    id: 'standalone:${BuildTechStackSection.checkIntegration.name}:${BuildHexaPromptRole.unitTest.name}',
    section: BuildTechStackSection.checkIntegration,
    role: BuildHexaPromptRole.unitTest,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

({int modelsCount, int useCasesCount, int sagasCount}) _domainStats(
  FunctionalDomain domain,
) {
  final contracts = domain.contracts;
  final modelsCount = contracts == null
      ? 0
      : contracts.groups.fold<int>(0, (sum, g) => sum + g.children.length);
  final orchestration = domain.useCaseOrchestration;
  return (
    modelsCount: modelsCount,
    useCasesCount: orchestration?.useCases.length ?? 0,
    sagasCount: orchestration?.sagas.length ?? 0,
  );
}

String _formatImplementationBody({
  required FunctionalDomain domain,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  final stats = _domainStats(domain);
  final buf = StringBuffer()
    ..writeln(
      '# Check Integration & Câblage — Domaine `${domain.domainCode}`',
    )
    ..writeln()
    ..writeln('## 1. Mission & Périmètre Check Integration')
    ..writeln(
      'Audite et finalise l’**intégration complète** de toutes les briques du domaine **`${domain.domainCode}`** (**${domain.name}**) : ${stats.modelsCount} modèle(s)/contrat(s), ${stats.useCasesCount} cas d’usage et ${stats.sagasCount} saga(s).',
    )
    ..writeln(
      '- Vérifie la cohérence des signatures entre **Inbound → Application (Commands/Queries/Sagas) → Domain → Outbound / Persistance**.',
    )
    ..writeln(
      '- Valide tous les bindings d’injection de dépendances (tokens de ports, modules, exports inter-modules) et prépare les harnais/fixtures d’intégration.',
    )
    ..writeln();

  PromptMarkdownSections.writeDomainContextSection(
    buf,
    domain,
    glossary,
    modelPreferences,
  );

  buf
    ..writeln('## 3. Livrables Attendus')
    ..writeln(
      '1. Vérifie et complète le câblage du module du domaine ainsi que son enregistrement dans le module racine.',
    )
    ..writeln(
      '2. Mets en place les utilitaires/harnais d’intégration permettant de tester la chaîne complète avec base/transports isolés.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.checkIntegration,
    role: BuildHexaPromptRole.implementation,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}

String _formatUnitTestBody({
  required FunctionalDomain domain,
  BuildTechStackProfile? techStack,
}) {
  final stats = _domainStats(domain);
  final buf = StringBuffer()
    ..writeln(
      '# Check Integration (Suite de Vérification) — `${domain.domainCode}`',
    )
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Exécute et complète les **tests d’intégration et la validation globale** du domaine **`${domain.domainCode}`** (${stats.modelsCount} modèle(s)/contrat(s), ${stats.useCasesCount} cas d’usage, ${stats.sagasCount} saga(s)).',
    )
    ..writeln()
    ..writeln('## 2. Points de Contrôle Obligatoires')
    ..writeln(
      '- Démarrage du conteneur / module applicatif sans erreur de dépendance manquante ni référence circulaire.',
    )
    ..writeln(
      '- Parcours nominal et cas d’erreur traversant la chaîne complète (entrée Inbound → Use Case → Domain → Persistance / Outbound).',
    )
    ..writeln(
      '- Compilation, analyse statique, lint et **100 % des tests au vert**.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.checkIntegration,
    role: BuildHexaPromptRole.unitTest,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
