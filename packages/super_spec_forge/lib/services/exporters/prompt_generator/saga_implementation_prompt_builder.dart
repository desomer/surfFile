/// Générateur du prompt IA d'implémentation d'une Saga (orchestration ou
/// chorégraphie) en Architecture Hexagonale ([buildSagaImplementationPrompt]).
library;

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../../models/usecase_orchestration_spec.dart';
import '../../spec_storage_slug.dart';
import 'prompt_generator_models.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Implémentation Saga » en Architecture Hexagonale.
BuildHexaPromptSpec buildSagaImplementationPrompt({
  required FunctionalDomain domain,
  required BuildDesignItem item,
  required OrchestrationSagaSpec saga,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
}) {
  final title =
      '${saga.code} · ${saga.name} — Implémentation Saga (${saga.coordinationMode.label})';
  final summary =
      'Coordinateur/handlers de Saga, corrélation `${saga.correlationKey.isEmpty ? 'correlationId' : saga.correlationKey}`, compensations et reprise sur échec.';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      BuildDesignItemKind.saga,
      BuildTechStackSection.useCaseSaga,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      saga.name,
      BuildHexaPromptRole.implementation,
    ),
    title: title,
    version: saga.version,
    domainCode: domain.domainCode,
    description: summary,
    tags: <String>[
      'hexagonal-architecture',
      if (techStack != null) techStack.code,
      domain.domainCode,
      'saga',
      saga.coordinationMode.name,
      'application-layer',
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.useCaseSaga.slug,
      'layer': 'application',
      'role': 'implementation',
      'artifactType': 'saga',
      'artifactName': saga.name,
      'sagaCode': saga.code,
      'coordination': saga.coordinationMode.name,
    },
    dates: dates,
  );

  final body = _formatBody(
    domain: domain,
    saga: saga,
    techStack: techStack,
    glossary: glossary,
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
  required OrchestrationSagaSpec saga,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
}) {
  final buf = StringBuffer()
    ..writeln(
      '# Implémentation Saga `${saga.code}` · `${saga.name}` (${saga.coordinationMode.label})',
    )
    ..writeln()
    ..writeln('## 1. Mission & Architecture Hexagonale')
    ..writeln(
      'Implémente dans la couche `application/` la Saga **`${saga.name}`** (${saga.title.isEmpty ? saga.code : '« ${saga.title} »'}) du domaine **`${domain.domainCode}`** (**${domain.name}**) selon le mode **`${saga.coordinationMode.label}`**.',
    )
    ..writeln(
      '- Toute interaction externe (commandes distantes, publication d’événements, persistance d’état de Saga, planification de timeouts) passe exclusivement par des **ports sortants typés**.',
    )
    ..writeln(
      '- Garantis l’**idempotence** de chaque étape et de chaque compensation via la clé de corrélation.',
    )
    ..writeln();

  PromptMarkdownSections.writeDomainContextSection(buf, domain, glossary, null);

  buf
    ..writeln('## 3. Paramètres de Coordination de la Saga')
    ..writeln('- **Code & Nom** : `${saga.code}` — `${saga.name}`')
    ..writeln('- **Mode de coordination** : `${saga.coordinationMode.label}`');
  if (saga.boundedContexts.isNotEmpty) {
    buf.writeln(
      '- **Bounded Contexts coordonnés** : ${saga.boundedContexts.join(', ')}',
    );
  }
  if (saga.triggerEventOrCommand.isNotEmpty) {
    buf.writeln('- **Déclencheur initial** : `${saga.triggerEventOrCommand}`');
  }
  if (saga.correlationKey.isNotEmpty) {
    buf.writeln(
      '- **Clé de corrélation / idempotence** : `${saga.correlationKey}`',
    );
  }
  if (saga.failureRecoveryStrategy.isNotEmpty) {
    buf.writeln(
      '- **Stratégie de reprise / DLQ** : ${saga.failureRecoveryStrategy}',
    );
  }
  buf.writeln();

  if (saga.mermaidDiagram.isNotEmpty) {
    buf
      ..writeln('### 3.1 Diagramme de Flux Mermaid')
      ..writeln('```mermaid')
      ..writeln(saga.mermaidDiagram)
      ..writeln('```')
      ..writeln();
  }

  if (saga.compensationMatrix.isNotEmpty) {
    buf.writeln('### 3.2 Matrice des Étapes & Compensations (Rollback)');
    for (final row in saga.compensationMatrix) {
      buf.writeln(
        '- **${row.step}** `[Criticité : ${row.criticality.label} · Timeout : ${row.timeout} · Idempotent : ${row.idempotent ? 'oui' : 'non'} · Retry : ${row.retryable ? 'oui' : 'non'}]`\n'
        '  - Action nominale : ${row.nominalAction.isEmpty ? 'N/A' : row.nominalAction}\n'
        '  - Compensation (Rollback) : ${row.compensationAction.isEmpty ? 'Aucune' : row.compensationAction}\n'
        '  - Déclencheur du Rollback : ${row.rollbackTrigger.isEmpty ? 'Échec étape suivante / timeout' : row.rollbackTrigger}',
      );
    }
    buf.writeln();
  }

  buf
    ..writeln('## 4. Livrables Attendus')
    ..writeln(
      '1. Modélise l’état de progression de la Saga, son port de persistance d’état et ses ports d’envoi de commandes / événements.',
    )
    ..writeln(
      '2. Implémente le flux nominal ainsi que l’exécution ordonnée en sens inverse des actions de compensation en cas d’échec ou de timeout, plus l’escalade DLQ lorsque la compensation échoue.',
    )
    ..writeln('3. Vérifie la compilation et l’analyse statique.');

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.useCaseSaga,
    role: BuildHexaPromptRole.implementation,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
