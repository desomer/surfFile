/// Générateurs des prompts IA autonomes (sans rattachement) pour la partie
/// **Playground** d'un domaine ([buildDomainPlaygroundImplementationPrompt],
/// [buildDomainPlaygroundUnitTestPrompt]).
library;

import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../spec_storage_slug.dart';
import 'prompt_generator_models.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Playground — Implémentation » au niveau du domaine.
BuildHexaPromptSpec buildDomainPlaygroundImplementationPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  const summary =
      'Bac à sable local d’expérimentation, scripts de démonstration, jeux d’essais et outils manuels pour manipuler le domaine.';
  final title = '${domain.name} — Playground (Implémentation)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.playground,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-playground',
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
      'playground',
      'sandbox',
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.playground.slug,
      'layer': 'playground',
      'role': 'implementation',
      'artifactType': 'playground',
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
    id: 'standalone:${BuildTechStackSection.playground.name}:${BuildHexaPromptRole.implementation.name}',
    section: BuildTechStackSection.playground,
    role: BuildHexaPromptRole.implementation,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

/// Construit le prompt « Playground — Test unitaire » au niveau du domaine.
BuildHexaPromptSpec buildDomainPlaygroundUnitTestPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
}) {
  const summary =
      'Tests de non-régression et de fumée (smoke tests) des scripts, scénarios et utilitaires du Playground du domaine.';
  final title = '${domain.name} — Playground (Test unitaire)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.playground,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-playground',
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
      'playground',
      'sandbox',
      'unit-test',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.playground.slug,
      'layer': 'playground',
      'role': 'unit-test',
      'artifactType': 'playground',
      'artifactName': domain.domainCode,
    },
    dates: dates,
  );

  final body = _formatUnitTestBody(domain: domain, techStack: techStack);

  return BuildHexaPromptSpec(
    id: 'standalone:${BuildTechStackSection.playground.name}:${BuildHexaPromptRole.unitTest.name}',
    section: BuildTechStackSection.playground,
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
    ..writeln('# Playground & Bac à sable — Domaine `${domain.domainCode}`')
    ..writeln()
    ..writeln('## 1. Mission & Périmètre Playground')
    ..writeln(
      'Mets en place un espace **Playground** autonome et isolé pour le domaine **`${domain.domainCode}`** (**${domain.name}**) afin de démontrer, explorer et tester manuellement les cas d’usage et scénarios clés sans polluer le code de production.',
    )
    ..writeln(
      '- Garde le Playground strictement séparé de la couche `core/${domain.domainCode}/` et de la configuration de production.',
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
      '1. Crée les scripts, scénarios de démonstration ou utilitaires locaux du Playground permettant d’exercer rapidement les flux principaux du domaine.',
    )
    ..writeln(
      '2. Documente clairement la commande d’exécution locale et les données de test utilisées afin que l’espace reste immédiatement reproductible.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.playground,
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
    ..writeln('# Tests du Playground — `${domain.domainCode}`')
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Écris et exécute les **tests unitaires et tests de fumée** garantissant que les scénarios, helpers et jeux de données du **Playground** du domaine **`${domain.domainCode}`** restent synchronisés avec les contrats du domaine.',
    )
    ..writeln()
    ..writeln('## 2. Vérifications Obligatoires')
    ..writeln(
      '- Chaque scénario ou helper du Playground s’exécute de manière déterministe et reproductible en isolation.',
    )
    ..writeln(
      '- Aucune dépendance de production ne repose sur les fichiers du Playground.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.playground,
    role: BuildHexaPromptRole.unitTest,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
