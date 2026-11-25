/// Générateurs des prompts IA autonomes (sans rattachement) pour la partie
/// **Boilerplate** d'un domaine ([buildDomainBoilerplateImplementationPrompt],
/// [buildDomainBoilerplateUnitTestPrompt]).
library;

import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../spec_storage_slug.dart';
import 'prompt_generator_models.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Boilerplate — Implémentation » au niveau du domaine.
BuildHexaPromptSpec buildDomainBoilerplateImplementationPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  const summary =
      'Socle technique initial : bootstrap applicatif, configuration typée, logger métier, helpers partagés et module racine.';
  final title = '${domain.name} — Boilerplate (Implémentation)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.boilerplate,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-boilerplate',
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
      'boilerplate',
      'shared',
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.boilerplate.slug,
      'layer': 'shared',
      'role': 'implementation',
      'artifactType': 'boilerplate',
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
    id: 'standalone:${BuildTechStackSection.boilerplate.name}:${BuildHexaPromptRole.implementation.name}',
    section: BuildTechStackSection.boilerplate,
    role: BuildHexaPromptRole.implementation,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

/// Construit le prompt « Boilerplate — Test unitaire » au niveau du domaine.
BuildHexaPromptSpec buildDomainBoilerplateUnitTestPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
}) {
  const summary =
      'Tests unitaires du socle partagé : validation de configuration, helpers de résultat/erreur et logger.';
  final title = '${domain.name} — Boilerplate (Test unitaire)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.boilerplate,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-boilerplate',
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
      'boilerplate',
      'shared',
      'unit-test',
      'tdd',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.boilerplate.slug,
      'layer': 'shared',
      'role': 'unit-test',
      'artifactType': 'boilerplate',
      'artifactName': domain.domainCode,
    },
    dates: dates,
  );

  final body = _formatUnitTestBody(domain: domain, techStack: techStack);

  return BuildHexaPromptSpec(
    id: 'standalone:${BuildTechStackSection.boilerplate.name}:${BuildHexaPromptRole.unitTest.name}',
    section: BuildTechStackSection.boilerplate,
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
      '# Boilerplate & Socle Partagé — Domaine `${domain.domainCode}`',
    )
    ..writeln()
    ..writeln('## 1. Mission & Périmètre Boilerplate')
    ..writeln(
      'Mets en place ou complète le **socle technique partagé** servant d’ossature au domaine **`${domain.domainCode}`** (**${domain.name}**) : bootstrap applicatif, chargement et validation stricte des variables d’environnement, configuration du logger, gestion transversale des erreurs et santé applicative.',
    )
    ..writeln(
      '- Garde le socle **minimal, modulaire et sans fuite de framework dans la couche métier pure**.',
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
      '1. Initialise la structure de démarrage (`main`, module racine) et l’injection des modules par domaine.',
    )
    ..writeln(
      '2. Implémente la validation de configuration, les briques de journalisation et les helpers partagés réutilisés par les couches applicatives et d’infrastructure.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.boilerplate,
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
      '# Tests Unitaires Boilerplate — Domaine `${domain.domainCode}`',
    )
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Écris la suite de **tests unitaires** du socle technique partagé pour **`${domain.domainCode}`** afin de fiabiliser la configuration au démarrage et les utilitaires transverses.',
    )
    ..writeln()
    ..writeln('## 2. Scénarios de Test Obligatoires')
    ..writeln(
      '- Validation des variables de configuration requises (cas nominal + rejet explicite en cas de valeur manquante ou invalide).',
    )
    ..writeln(
      '- Comportement des helpers partagés (`Result` / erreurs, formatage, logger en mémoire) sans dépendre d’un serveur ou d’une base de données.',
    )
    ..writeln()
    ..writeln('## 3. Exécution')
    ..writeln(
      'Lance les tests unitaires du socle partagé et vérifie **100 % de réussite**.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.boilerplate,
    role: BuildHexaPromptRole.unitTest,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
