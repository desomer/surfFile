/// Générateurs des prompts IA autonomes (sans rattachement) pour la partie
/// **Inbound** d'un domaine ([buildDomainInboundImplementationPrompt],
/// [buildDomainInboundUnitTestPrompt]).
library;

import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../spec_storage_slug.dart';
import 'prompt_generator_models.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Inbound — Implémentation » au niveau du domaine.
BuildHexaPromptSpec buildDomainInboundImplementationPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  const summary =
      'Points d’entrée entrants (contrôleurs HTTP/REST, DTOs d’entrée/sortie, consumers, guards) orchestrant les Use Cases du domaine.';
  final title = '${domain.name} — Inbound (Implémentation)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.inbound,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-inbound',
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
      'inbound',
      'infrastructure-layer',
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.inbound.slug,
      'layer': 'infrastructure',
      'role': 'implementation',
      'artifactType': 'inbound-entrypoints',
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
    id: 'standalone:${BuildTechStackSection.inbound.name}:${BuildHexaPromptRole.implementation.name}',
    section: BuildTechStackSection.inbound,
    role: BuildHexaPromptRole.implementation,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

/// Construit le prompt « Inbound — Test unitaire » au niveau du domaine.
BuildHexaPromptSpec buildDomainInboundUnitTestPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
}) {
  const summary =
      'Tests unitaires des contrôleurs, validation des DTOs entrants, guards et mapping des erreurs vers les réponses HTTP/CLI.';
  final title = '${domain.name} — Inbound (Test unitaire)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.inbound,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-inbound',
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
      'inbound',
      'infrastructure-layer',
      'unit-test',
      'tdd',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.inbound.slug,
      'layer': 'infrastructure',
      'role': 'unit-test',
      'artifactType': 'inbound-entrypoints',
      'artifactName': domain.domainCode,
    },
    dates: dates,
  );

  final body = _formatUnitTestBody(domain: domain, techStack: techStack);

  return BuildHexaPromptSpec(
    id: 'standalone:${BuildTechStackSection.inbound.name}:${BuildHexaPromptRole.unitTest.name}',
    section: BuildTechStackSection.inbound,
    role: BuildHexaPromptRole.unitTest,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

({List<String> useCaseEntries, List<String> dtoContracts}) _collectInboundContext(
  FunctionalDomain domain,
) {
  final useCases = <String>[];
  final dtos = <String>[];

  final orchestration = domain.useCaseOrchestration;
  if (orchestration != null) {
    for (final uc in orchestration.useCases) {
      final inbound = uc.inboundPort.trim().isNotEmpty
          ? uc.inboundPort.trim()
          : '${uc.name}UseCase';
      useCases.add(
        '`${uc.code}` · `${uc.name}` (${uc.cqrsType.label}) → port entrant `$inbound`',
      );
    }
  }

  final contracts = domain.contracts;
  if (contracts != null) {
    const dtoTypes = <String>{
      'createxdto',
      'updatexdto',
      'xresponsedto',
      'xlistitemdto',
      'xquerydto',
    };
    for (final group in contracts.groups) {
      for (final node in group.children) {
        if (dtoTypes.contains(node.type)) {
          dtos.add('${node.name} (`${node.type}`)');
        }
      }
    }
  }

  return (useCaseEntries: useCases, dtoContracts: dtos);
}

String _formatImplementationBody({
  required FunctionalDomain domain,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  final ctx = _collectInboundContext(domain);
  final buf = StringBuffer()
    ..writeln(
      '# Points d’Entrée Inbound — Domaine `${domain.domainCode}`',
    )
    ..writeln()
    ..writeln('## 1. Mission & Périmètre Inbound')
    ..writeln(
      'Implémente les **adaptateurs entrants (`Driving Adapters`)** du domaine **`${domain.domainCode}`** (**${domain.name}**) : contrôleurs REST/HTTP, DTOs de validation aux bordures, consumers d’événements et guards.',
    )
    ..writeln(
      '- Délègue systématiquement l’exécution aux ports entrants (`Driving Ports`) des Use Cases sans jamais contenir de logique métier.',
    )
    ..writeln(
      '- Convertis les erreurs métier retournées par les Use Cases en codes de statut et réponses HTTP explicites.',
    )
    ..writeln();

  PromptMarkdownSections.writeDomainContextSection(
    buf,
    domain,
    glossary,
    modelPreferences,
  );

  buf.writeln('## 3. Use Cases & Contrats DTO Exposés');
  if (ctx.useCaseEntries.isEmpty && ctx.dtoContracts.isEmpty) {
    buf.writeln(
      '- Structure les contrôleurs, DTOs et mappers d’entrée/sortie cohérents avec les conventions du domaine.',
    );
  } else {
    for (final uc in ctx.useCaseEntries) {
      buf.writeln('- $uc');
    }
    for (final dto in ctx.dtoContracts) {
      buf.writeln('- Contrat DTO : $dto');
    }
  }
  buf
    ..writeln()
    ..writeln('## 4. Livrables Attendus')
    ..writeln(
      '1. Crée les DTOs d’entrée/réponse avec validation de schéma/format aux bordures.',
    )
    ..writeln(
      '2. Implémente les contrôleurs/consumers en appelant exclusivement les ports entrants des Use Cases.',
    )
    ..writeln(
      '3. Déclare les contrôleurs et handlers dans le module du domaine.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.inbound,
    role: BuildHexaPromptRole.implementation,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}

String _formatUnitTestBody({
  required FunctionalDomain domain,
  BuildTechStackProfile? techStack,
}) {
  final ctx = _collectInboundContext(domain);
  final buf = StringBuffer()
    ..writeln(
      '# Tests Unitaires Inbound — Domaine `${domain.domainCode}`',
    )
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Écris la suite de **tests unitaires** des adaptateurs entrants (contrôleurs, validation DTO, guards, consumers) du domaine **`${domain.domainCode}`** en remplaçant les Use Cases par des doublures en mémoire.',
    )
    ..writeln()
    ..writeln('## 2. Scénarios de Test Obligatoires')
    ..writeln(
      '- Validation des DTOs entrants (champs requis, formats, bornes) et rejet des payloads invalides.',
    )
    ..writeln(
      '- Mapping exact requête entrante → Command/Query du Use Case et Command/Query Output → réponse HTTP/DTO.',
    )
    ..writeln(
      '- Traduction de chaque erreur métier retournée par les Use Cases vers le statut HTTP attendu.',
    );

  if (ctx.useCaseEntries.isNotEmpty) {
    buf.writeln('- Points d’entrée à couvrir :');
    for (final uc in ctx.useCaseEntries) {
      buf.writeln('  - $uc');
    }
  }
  buf
    ..writeln()
    ..writeln('## 3. Exécution')
    ..writeln(
      'Lance la suite de tests unitaires Inbound et assure **100 % de réussite**.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.inbound,
    role: BuildHexaPromptRole.unitTest,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
