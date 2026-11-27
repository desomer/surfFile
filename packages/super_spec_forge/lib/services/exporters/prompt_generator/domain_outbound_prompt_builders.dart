/// Générateurs des prompts IA autonomes (sans rattachement) pour la partie
/// **Outbound** d'un domaine ([buildDomainOutboundImplementationPrompt],
/// [buildDomainOutboundUnitTestPrompt]).
library;

import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../spec_storage_slug.dart';
import 'prompt_evolution_sections.dart';
import 'prompt_generator_models.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Outbound — Implémentation » au niveau du domaine.
BuildHexaPromptSpec buildDomainOutboundImplementationPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
  PromptEvolutionDecision evolutionDecision =
      const PromptEvolutionDecision.none(),
}) {
  const summary =
      'Adaptateurs sortants hors persistance (messaging, événements, logger, clients externes) implémentant les ports Outbound du domaine.';
  final title = '${domain.name} — Outbound (Implémentation)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.outbound,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-outbound',
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
      'outbound',
      'infrastructure-layer',
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.outbound.slug,
      'layer': 'infrastructure',
      'role': 'implementation',
      'artifactType': 'outbound-adapters',
      'artifactName': domain.domainCode,
    },
    dates: dates,
    isEvolutionDelta: evolutionDecision.isEvolutionDelta,
    baselineIteration: evolutionDecision.baselineLabel,
    previousVersion: evolutionDecision.baselineVersion,
    changeImpact: evolutionDecision.changeBump,
  );

  final body = _formatImplementationBody(
    domain: domain,
    techStack: techStack,
    glossary: glossary,
    modelPreferences: modelPreferences,
    evolutionDecision: evolutionDecision,
  );

  return BuildHexaPromptSpec(
    id: 'standalone:${BuildTechStackSection.outbound.name}:${BuildHexaPromptRole.implementation.name}',
    section: BuildTechStackSection.outbound,
    role: BuildHexaPromptRole.implementation,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
    isEvolutionDelta: evolutionDecision.isEvolutionDelta,
    baselineLabel: evolutionDecision.baselineLabel,
    baselineVersion: evolutionDecision.baselineVersion,
    changeBump: evolutionDecision.changeBump,
  );
}

/// Construit le prompt « Outbound — Test unitaire » au niveau du domaine.
BuildHexaPromptSpec buildDomainOutboundUnitTestPrompt({
  required FunctionalDomain domain,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  PromptEvolutionDecision evolutionDecision =
      const PromptEvolutionDecision.none(),
}) {
  const summary =
      'Tests unitaires des adaptateurs sortants (messaging, logger, clients externes) avec doublures déterministes.';
  final title = '${domain.name} — Outbound (Test unitaire)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      null,
      BuildTechStackSection.outbound,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      '${domain.domainCode}-outbound',
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
      'outbound',
      'infrastructure-layer',
      'unit-test',
      'tdd',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.outbound.slug,
      'layer': 'infrastructure',
      'role': 'unit-test',
      'artifactType': 'outbound-adapters',
      'artifactName': domain.domainCode,
    },
    dates: dates,
    isEvolutionDelta: evolutionDecision.isEvolutionDelta,
    baselineIteration: evolutionDecision.baselineLabel,
    previousVersion: evolutionDecision.baselineVersion,
    changeImpact: evolutionDecision.changeBump,
  );

  final body = _formatUnitTestBody(
    domain: domain,
    techStack: techStack,
    evolutionDecision: evolutionDecision,
  );

  return BuildHexaPromptSpec(
    id: 'standalone:${BuildTechStackSection.outbound.name}:${BuildHexaPromptRole.unitTest.name}',
    section: BuildTechStackSection.outbound,
    role: BuildHexaPromptRole.unitTest,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
    isEvolutionDelta: evolutionDecision.isEvolutionDelta,
    baselineLabel: evolutionDecision.baselineLabel,
    baselineVersion: evolutionDecision.baselineVersion,
    changeBump: evolutionDecision.changeBump,
  );
}

({
  List<String> nonRepositoryPorts,
  List<String> emittedEvents,
  List<String> messageContracts,
})
_collectOutboundContext(FunctionalDomain domain) {
  final ports = <String>{};
  final events = <String>{};
  final messages = <String>{};

  final orchestration = domain.useCaseOrchestration;
  if (orchestration != null) {
    for (final uc in orchestration.useCases) {
      for (final p in uc.outboundPorts) {
        final trimmed = p.trim();
        if (trimmed.isNotEmpty &&
            !trimmed.toLowerCase().contains('repository')) {
          ports.add(trimmed);
        }
      }
      for (final evt in uc.emittedEvents) {
        if (evt.trim().isNotEmpty) events.add(evt.trim());
      }
    }
  }

  final contracts = domain.contracts;
  if (contracts != null) {
    for (final group in contracts.groups) {
      for (final node in group.children) {
        if (node.type == 'eventxpayloaddto' ||
            node.type == 'eventxenvelopedto') {
          messages.add('${node.name} (`${node.type}`)');
        }
        final layer = contracts.domainLayerFor(node);
        for (final evt in layer.domainEvents) {
          if (evt.name.trim().isNotEmpty) events.add(evt.name.trim());
        }
      }
    }
  }

  return (
    nonRepositoryPorts: ports.toList(growable: false),
    emittedEvents: events.toList(growable: false),
    messageContracts: messages.toList(growable: false),
  );
}

String _formatImplementationBody({
  required FunctionalDomain domain,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
  required PromptEvolutionDecision evolutionDecision,
}) {
  final ctx = _collectOutboundContext(domain);
  final buf = StringBuffer()
    ..writeln(
      '# Adaptateurs Outbound — Domaine `${domain.domainCode}`',
    )
    ..writeln()
    ..writeln('## 1. Mission & Périmètre Outbound')
    ..writeln(
      'Implémente les **adaptateurs sortants (`Driven Adapters`) hors persistance** du domaine **`${domain.domainCode}`** (**${domain.name}**) : publication d’événements / messaging, logger métier et clients externes.',
    )
    ..writeln(
      '- Aucune logique métier dans les adaptateurs : traduction pure des contrats du domaine vers l’infrastructure et remontée d’erreurs typées.',
    )
    ..writeln();

  PromptMarkdownSections.writeDomainContextSection(
    buf,
    domain,
    glossary,
    modelPreferences,
  );

  PromptEvolutionSections.writeDomainAdapterEvolutionSection(
    buf,
    decision: evolutionDecision,
    section: BuildTechStackSection.outbound,
    role: BuildHexaPromptRole.implementation,
  );

  buf.writeln('## 3. Ports Sortants, Événements & Messages Inventoriés');
  if (ctx.nonRepositoryPorts.isEmpty &&
      ctx.emittedEvents.isEmpty &&
      ctx.messageContracts.isEmpty) {
    buf.writeln(
      '- Aucun port sortant externe ou événement explicite déclaré : implémente le port Logger et l’adaptateur de bus d’événements standard du domaine.',
    );
  } else {
    for (final port in ctx.nonRepositoryPorts) {
      buf.writeln('- Port sortant (`Driven Port`) : `$port`');
    }
    for (final evt in ctx.emittedEvents) {
      buf.writeln('- Événement du domaine à publier : `$evt`');
    }
    for (final msg in ctx.messageContracts) {
      buf.writeln('- Contrat message : $msg');
    }
  }
  buf
    ..writeln()
    ..writeln('## 4. Livrables Attendus')
    ..writeln(
      '1. Implémente chaque adaptateur sortant (messaging, logger, clients externes) en respectant strictement les interfaces des ports définies dans le domaine.',
    )
    ..writeln(
      '2. Déclare et exporte les bindings d’injection de dépendances correspondants dans le module du domaine.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.outbound,
    role: BuildHexaPromptRole.implementation,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}

String _formatUnitTestBody({
  required FunctionalDomain domain,
  BuildTechStackProfile? techStack,
  required PromptEvolutionDecision evolutionDecision,
}) {
  final ctx = _collectOutboundContext(domain);
  final buf = StringBuffer()
    ..writeln(
      '# Tests Unitaires Outbound — Domaine `${domain.domainCode}`',
    )
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Écris la suite de **tests unitaires** des adaptateurs sortants hors persistance du domaine **`${domain.domainCode}`** en isolant les SDK/transports externes par des doublures déterministes.',
    )
    ..writeln();

  PromptEvolutionSections.writeDomainAdapterEvolutionSection(
    buf,
    decision: evolutionDecision,
    section: BuildTechStackSection.outbound,
    role: BuildHexaPromptRole.unitTest,
  );

  buf
    ..writeln('## 2. Cas de Test à Couvrir')
    ..writeln(
      '- Mapping des payloads sortants (événements, messages, requêtes HTTP) et préservation des clés de corrélation.',
    )
    ..writeln(
      '- Traduction des erreurs techniques (timeout, indisponibilité, erreur broker/HTTP) en erreurs typées.',
    );

  if (ctx.nonRepositoryPorts.isNotEmpty) {
    buf.writeln('- Adaptateurs ciblés :');
    for (final port in ctx.nonRepositoryPorts) {
      buf.writeln('  - `$port`');
    }
  }
  if (ctx.emittedEvents.isNotEmpty) {
    buf.writeln(
      '- Événements couverts : ${ctx.emittedEvents.map((e) => '`$e`').join(', ')}',
    );
  }
  buf
    ..writeln()
    ..writeln('## 3. Exécution')
    ..writeln(
      'Lance la suite de tests unitaires Outbound et vérifie **100 % de réussite**.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.outbound,
    role: BuildHexaPromptRole.unitTest,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
