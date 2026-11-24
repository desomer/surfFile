/// Générateur du prompt IA de tests unitaires d'une Saga et de ses rollbacks
/// ([buildSagaUnitTestPrompt]).
library;

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../../models/domain_catalog.dart';
import '../../../models/usecase_orchestration_spec.dart';
import '../../spec_storage_slug.dart';
import 'prompt_generator_models.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Tests unitaires Saga & Rollbacks ».
BuildHexaPromptSpec buildSagaUnitTestPrompt({
  required FunctionalDomain domain,
  required BuildDesignItem item,
  required OrchestrationSagaSpec saga,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
}) {
  final title =
      '${saga.code} · ${saga.name} — Tests unitaires Saga & Rollbacks';
  const summary =
      'Tests unitaires du flux nominal, des rollbacks ordonnés par étape, des timeouts/retries et de l’idempotence.';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      BuildDesignItemKind.saga,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      saga.name,
      BuildHexaPromptRole.unitTest,
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
      'unit-test',
      'tdd',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'layer': 'application',
      'role': 'unit-test',
      'artifactType': 'saga',
      'artifactName': saga.name,
      'sagaCode': saga.code,
      'coordination': saga.coordinationMode.name,
    },
    dates: dates,
  );

  final body = _formatBody(domain: domain, saga: saga, techStack: techStack);

  return BuildHexaPromptSpec(
    id: '${item.kind.name}:${item.id}:${BuildHexaPromptRole.unitTest.name}',
    item: item,
    role: BuildHexaPromptRole.unitTest,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

String _formatBody({
  required FunctionalDomain domain,
  required OrchestrationSagaSpec saga,
  BuildTechStackProfile? techStack,
}) {
  final buf = StringBuffer()
    ..writeln(
      '# Tests Unitaires Saga `${saga.code}` · `${saga.name}`',
    )
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Écris la suite complète de **tests unitaires** de la Saga **`${saga.name}`** (domaine `${domain.domainCode}`) avec des doublures en mémoire des ports de commandes, d’événements et d’état de Saga.',
    )
    ..writeln()
    ..writeln('## 2. Scénarios de Test Obligatoires')
    ..writeln(
      '1. **Chemin nominal complet** : déclenchement par `${saga.triggerEventOrCommand.isEmpty ? 'l’événement initial' : saga.triggerEventOrCommand}`, exécution séquentielle de toutes les étapes et marquage de la Saga comme terminée.',
    );

  if (saga.compensationMatrix.isNotEmpty) {
    buf.writeln(
      '2. **Scénarios de compensation (Rollback en ordre inverse)** :',
    );
    for (final row in saga.compensationMatrix) {
      buf.writeln(
        '   - Échec / `${row.rollbackTrigger.isEmpty ? 'timeout' : row.rollbackTrigger}` sur **${row.step}** → vérifie le déclenchement de `${row.compensationAction.isEmpty ? 'la compensation attendue' : row.compensationAction}` (timeout `${row.timeout}`, retry=${row.retryable}).',
      );
    }
  } else {
    buf.writeln(
      '2. **Scénarios de compensation** : vérifie qu’un échec à l’étape `k` déclenche les compensations des étapes `k-1 .. 1` dans l’ordre inverse.',
    );
  }

  buf
    ..writeln(
      '3. **Idempotence & Rejeu** : vérifie que la réception en doublon d’un événement portant la même clé `${saga.correlationKey.isEmpty ? 'correlationId' : saga.correlationKey}` ne ré-exécute pas les effets déjà acquittés.',
    )
    ..writeln(
      '4. **Épuisement des retries & reprise critique / DLQ** : vérifie le comportement défini (${saga.failureRecoveryStrategy.isEmpty ? 'mise en quarantaine / alerte DLQ' : saga.failureRecoveryStrategy}) lorsqu’une compensation critique échoue.',
    )
    ..writeln()
    ..writeln('## 3. Exécution')
    ..writeln(
      'Lance la suite de tests et assure-toi que tous les cas nominaux, de rollback et d’idempotence passent à **100 %**.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    role: BuildHexaPromptRole.unitTest,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
