/// Générateurs des prompts IA autonomes (sans rattachement) pour la partie
/// **Dev Tools** d'un domaine ([buildDomainDevToolsImplementationPrompt],
/// [buildDomainDevToolsUnitTestPrompt]).
library;

import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../spec_storage_slug.dart';
import 'prompt_generator_models.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Dev Tools — Implémentation » au niveau du domaine.
BuildHexaPromptSpec buildDomainDevToolsImplementationPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  const summary =
      'Outillage de développement : configuration compilateur strict, linter, frontières architecturales, runner de tests, scripts et CI.';
  final title = '${domain.name} — Dev Tools (Implémentation)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.devTools,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-dev-tools',
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
      'dev-tools',
      'tooling',
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.devTools.slug,
      'layer': 'tooling',
      'role': 'implementation',
      'artifactType': 'dev-tools',
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
    id: 'standalone:${BuildTechStackSection.devTools.name}:${BuildHexaPromptRole.implementation.name}',
    section: BuildTechStackSection.devTools,
    role: BuildHexaPromptRole.implementation,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

/// Construit le prompt « Dev Tools — Test unitaire » au niveau du domaine.
BuildHexaPromptSpec buildDomainDevToolsUnitTestPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
}) {
  const summary =
      'Tests de conformité outillage & architecture : isolation stricte du domaine, lint, typage strict et configuration des tests.';
  final title = '${domain.name} — Dev Tools (Test unitaire)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.devTools,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-dev-tools',
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
      'dev-tools',
      'tooling',
      'unit-test',
      'architecture-tests',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.devTools.slug,
      'layer': 'tooling',
      'role': 'unit-test',
      'artifactType': 'dev-tools',
      'artifactName': domain.domainCode,
    },
    dates: dates,
  );

  final body = _formatUnitTestBody(domain: domain, techStack: techStack);

  return BuildHexaPromptSpec(
    id: 'standalone:${BuildTechStackSection.devTools.name}:${BuildHexaPromptRole.unitTest.name}',
    section: BuildTechStackSection.devTools,
    role: BuildHexaPromptRole.unitTest,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

String _formatImplementationBody({
  required FunctionalDomain domain,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  final buf = StringBuffer()
    ..writeln(
      '# Dev Tools & Qualité Continue — Domaine `${domain.domainCode}`',
    )
    ..writeln()
    ..writeln('## 1. Mission & Périmètre Dev Tools')
    ..writeln(
      'Configure et vérifie l’**outillage de développement** du projet hébergeant le domaine **`${domain.domainCode}`** (**${domain.name}**) : options strictes de compilation/typage, règles de lint bloquant toute fuite d’infrastructure dans la couche métier, runner de tests, formatage et scripts d’automatisation.',
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
      '1. Configure les fichiers d’outillage (compilateur strict, linter avec règles d’isolation hexagonale, runner de tests unitaires et d’intégration).',
    )
    ..writeln(
      '2. Définis les scripts reproductibles de vérification (`typecheck`, `lint`, `test`, `build`) et le pipeline CI associé.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.devTools,
    role: BuildHexaPromptRole.implementation,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}

String _formatUnitTestBody({
  required FunctionalDomain domain,
  BuildTechStackProfile? techStack,
}) {
  final buf = StringBuffer()
    ..writeln(
      '# Tests d’Architecture & Outillage (Dev Tools) — `${domain.domainCode}`',
    )
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Écris et exécute les **tests automatisés de conformité architecturale et d’outillage** pour le domaine **`${domain.domainCode}`** afin de garantir dans la durée le respect de l’Architecture Hexagonale.',
    )
    ..writeln()
    ..writeln('## 2. Vérifications Obligatoires')
    ..writeln(
      '- Absence d’imports de framework, ORM/ODM ou transport réseau dans le cœur métier (`core/${domain.domainCode}/`).',
    )
    ..writeln(
      '- Respect des conventions de nommage, présence des en-têtes documentaires attendus et exécution sans erreur des commandes `typecheck`, `lint` et tests unitaires.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.devTools,
    role: BuildHexaPromptRole.unitTest,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
