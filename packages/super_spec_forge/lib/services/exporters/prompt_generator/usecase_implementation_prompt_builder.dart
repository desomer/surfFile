/// Générateur du prompt IA d'implémentation de la couche Application d'un Use Case
/// CQRS en Architecture Hexagonale ([buildUseCaseImplementationPrompt]).
library;

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../../models/usecase_orchestration_spec.dart';
import '../../spec_storage_slug.dart';
import 'prompt_generator_models.dart';
import 'prompt_json_schema_builder.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Implémentation Couche Application » d'un Use Case CQRS.
BuildHexaPromptSpec buildUseCaseImplementationPrompt({
  required FunctionalDomain domain,
  required BuildDesignItem item,
  required ApplicationUseCaseSpec useCase,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  final title =
      '${useCase.code} · ${useCase.name} — Implémentation Couche Application';
  final summary =
      'Port entrant, commandes/requêtes `${useCase.cqrsType.label}`, orchestration des ports sortants et publication d’événements.';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      BuildDesignItemKind.useCase,
      BuildTechStackSection.useCaseSaga,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      useCase.name,
      BuildHexaPromptRole.implementation,
    ),
    title: title,
    version: useCase.version,
    domainCode: domain.domainCode,
    description: useCase.businessGoal.trim().isNotEmpty
        ? '${useCase.businessGoal.trim()} — $summary'
        : summary,
    tags: <String>[
      'hexagonal-architecture',
      if (techStack != null) techStack.code,
      domain.domainCode,
      'usecase',
      'cqrs',
      useCase.cqrsType.name,
      'application-layer',
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.useCaseSaga.slug,
      'layer': 'application',
      'role': 'implementation',
      'artifactType': 'usecase',
      'artifactName': useCase.name,
      'useCaseCode': useCase.code,
      'cqrs': useCase.cqrsType.name,
    },
    dates: dates,
  );

  final body = _formatBody(
    domain: domain,
    useCase: useCase,
    techStack: techStack,
    glossary: glossary,
    modelPreferences: modelPreferences,
  );

  return BuildHexaPromptSpec(
    id: '${item.kind.name}:${item.id}:${BuildTechStackSection.useCaseSaga.name}:${BuildHexaPromptRole.implementation.name}',
    item: item,
    section: BuildTechStackSection.useCaseSaga,
    role: BuildHexaPromptRole.implementation,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

String _formatBody({
  required FunctionalDomain domain,
  required ApplicationUseCaseSpec useCase,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  final inbound = useCase.inboundPort.trim().isNotEmpty
      ? useCase.inboundPort.trim()
      : '${useCase.name}UseCase';
  final buf = StringBuffer()
    ..writeln(
      '# Implémentation Use Case `${useCase.code}` · `${useCase.name}` (${useCase.cqrsType.label})',
    )
    ..writeln()
    ..writeln(
      '## 1. Mission & Règles d’Architecture Hexagonale (Couche Application)',
    )
    ..writeln(
      'Implémente dans la couche `application/` le cas d’usage **`${useCase.name}`** (${useCase.title.isEmpty ? useCase.code : '« ${useCase.title} »'} · type CQRS **`${useCase.cqrsType.label}`**) du domaine **`${domain.domainCode}`** (**${domain.name}**).',
    )
    ..writeln(
      '- **Orchestration pure** : la couche `application/` coordonne les objets de `domain/` et les interfaces des ports sortants, sans logique SQL/HTTP/framework directe.',
    )
    ..writeln(
      '- **Contrat d’entrée/sortie explicite** : définis le port entrant `$inbound` ainsi que les structures immuables d’Input (Command/Query) et d’Output.',
    )
    ..writeln();

  PromptMarkdownSections.writeDomainContextSection(
    buf,
    domain,
    glossary,
    modelPreferences,
  );

  buf
    ..writeln('## 3. Spécification Détaillée du Use Case `${useCase.code}`')
    ..writeln('- **Code & Nom** : `${useCase.code}` — `${useCase.name}`')
    ..writeln('- **Qualification CQRS** : `${useCase.cqrsType.label}`')
    ..writeln('- **Port entrant (Driving Port)** : `$inbound`');
  if (useCase.boundedContext.isNotEmpty) {
    buf.writeln('- **Bounded Context** : ${useCase.boundedContext}');
  }
  if (useCase.targetAggregate.isNotEmpty) {
    buf.writeln(
      '- **Agrégat / Read Model cible** : `${useCase.targetAggregate}`',
    );
  }
  if (useCase.businessGoal.isNotEmpty) {
    buf.writeln('- **Objectif métier** : ${useCase.businessGoal}');
  }
  if (useCase.concurrencyAndIdempotency.isNotEmpty) {
    buf.writeln(
      '- **Concurrence & Idempotence** : ${useCase.concurrencyAndIdempotency}',
    );
  }
  buf.writeln();

  if (useCase.triggerInputs.isNotEmpty) {
    buf.writeln('### 3.1 Déclencheur / Input (JSON Schema)');
    PromptJsonSchemaBuilder.writeJsonSchemaBlock(
      buf,
      PromptJsonSchemaBuilder.buildUseCaseFieldsSchema(
        title: '${useCase.name}Input',
        fields: useCase.triggerInputs,
      ),
    );
    buf.writeln();
  }

  if (useCase.outputs.isNotEmpty) {
    buf.writeln('### 3.2 Sortie / Output (JSON Schema)');
    PromptJsonSchemaBuilder.writeJsonSchemaBlock(
      buf,
      PromptJsonSchemaBuilder.buildUseCaseFieldsSchema(
        title: '${useCase.name}Output',
        fields: useCase.outputs,
      ),
    );
    buf.writeln();
  }

  if (useCase.outboundPorts.isNotEmpty || useCase.emittedEvents.isNotEmpty) {
    buf.writeln('### 3.3 Ports Sortants Utilisés & Événements Publiés');
    for (final port in useCase.outboundPorts) {
      buf.writeln('- Port sortant (`Driven Port`) : `$port`');
    }
    for (final evt in useCase.emittedEvents) {
      buf.writeln('- Événement publié : `$evt`');
    }
    buf.writeln();
  }

  if (useCase.businessRules.isNotEmpty) {
    buf.writeln('### 3.4 Règles Métier Applicables');
    for (final rule in useCase.businessRules) {
      buf.writeln('- $rule');
    }
    buf.writeln();
  }

  if (useCase.detailedProcess.isNotEmpty) {
    buf.writeln('### 3.5 Processus Détaillé Étape par Étape');
    for (var i = 0; i < useCase.detailedProcess.length; i++) {
      buf.writeln('${i + 1}. ${useCase.detailedProcess[i]}');
    }
    buf.writeln();
  }

  if (useCase.possibleErrors.isNotEmpty) {
    buf.writeln(
      '### 3.6 Erreurs Métier Possibles\n- ${useCase.possibleErrors.map((e) => '`$e`').join(', ')}\n',
    );
  }

  if (useCase.nonGoals.isNotEmpty) {
    buf.writeln('### 3.7 Non-Objectifs (Hors Périmètre)');
    for (final ng in useCase.nonGoals) {
      buf.writeln('- $ng');
    }
    buf.writeln();
  }

  buf
    ..writeln('## 4. Livrables Attendus')
    ..writeln(
      '1. Crée le port entrant `$inbound`, ses objets Input/Output immuables et le service d’application `${useCase.name}Handler` / `${useCase.name}Service` injecté par constructeur.',
    )
    ..writeln(
      '2. Déclare ou complète les interfaces des ports sortants manquants dans `domain/ports/outbound/` ou `application/ports/outbound/`.',
    )
    ..writeln('3. Vérifie la compilation et l’analyse statique du projet.');

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.useCaseSaga,
    role: BuildHexaPromptRole.implementation,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
