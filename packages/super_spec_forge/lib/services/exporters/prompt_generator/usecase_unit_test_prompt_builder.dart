/// Générateur du prompt IA de tests unitaires de la couche Application d'un
/// Use Case CQRS ([buildUseCaseUnitTestPrompt]).
library;

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../../models/domain_catalog.dart';
import '../../../models/usecase_orchestration_spec.dart';
import '../../spec_storage_slug.dart';
import 'prompt_generator_models.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Tests unitaires Couche Application » d'un Use Case CQRS.
BuildHexaPromptSpec buildUseCaseUnitTestPrompt({
  required FunctionalDomain domain,
  required BuildDesignItem item,
  required ApplicationUseCaseSpec useCase,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
}) {
  final title =
      '${useCase.code} · ${useCase.name} — Tests unitaires Couche Application';
  const summary =
      'Suite TDD avec doublures en mémoire des ports sortants validant les scénarios Given/When/Then et critères d’acceptation.';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      BuildDesignItemKind.useCase,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      useCase.name,
      BuildHexaPromptRole.unitTest,
    ),
    title: title,
    version: useCase.version,
    domainCode: domain.domainCode,
    description: summary,
    tags: <String>[
      'hexagonal-architecture',
      if (techStack != null) techStack.code,
      domain.domainCode,
      'usecase',
      'cqrs',
      useCase.cqrsType.name,
      'application-layer',
      'unit-test',
      'tdd',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'layer': 'application',
      'role': 'unit-test',
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
  );

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
  required ApplicationUseCaseSpec useCase,
  BuildTechStackProfile? techStack,
}) {
  final buf = StringBuffer()
    ..writeln(
      '# Tests Unitaires Use Case `${useCase.code}` · `${useCase.name}`',
    )
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Écris la suite complète de **tests unitaires de la couche `application/`** pour **`${useCase.name}`** (domaine `${domain.domainCode}`), en isolant tous les ports sortants par des **fakes en mémoire ou doublures de test** (aucune infrastructure réelle).',
    )
    ..writeln();

  if (useCase.outboundPorts.isNotEmpty) {
    buf
      ..writeln('## 2. Doublures de Ports Sortants à Isoler')
      ..writeln(useCase.outboundPorts.map((p) => '- `$p`').join('\n'))
      ..writeln();
  }

  buf.writeln('## 3. Scénarios Comportementaux (`Given / When / Then`)');
  if (useCase.scenarios.isEmpty) {
    buf.writeln(
      '- Couvre le scénario nominal complet ainsi que chaque cas d’erreur métier (${useCase.possibleErrors.isEmpty ? 'validation des entrées, entité introuvable, refus d’invariant' : useCase.possibleErrors.join(', ')}).',
    );
  } else {
    for (final scn in useCase.scenarios) {
      buf.writeln(
        '### ${scn.isNominal ? '[Nominal]' : '[Erreur]'} ${scn.name}',
      );
      for (final g in scn.given) {
        buf.writeln('- **Given** $g');
      }
      for (final w in scn.when) {
        buf.writeln('- **When** $w');
      }
      for (final t in scn.then) {
        buf.writeln('- **Then** $t');
      }
      buf.writeln();
    }
  }

  if (useCase.acceptanceCriteria.isNotEmpty) {
    buf.writeln('## 4. Critères d’Acceptation à Vérifier par Assertions');
    for (final ac in useCase.acceptanceCriteria) {
      buf.writeln('- $ac');
    }
    buf.writeln();
  }

  buf
    ..writeln('## 5. Exécution')
    ..writeln(
      'Vérifie les mutations persistées dans les fakes, la publication exacte des événements (${useCase.emittedEvents.isEmpty ? 'si applicable' : useCase.emittedEvents.map((e) => '`$e`').join(', ')}) et l’absence d’effets de bord en cas d’erreur, puis exécute les tests jusqu’à **100 % de réussite**.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    role: BuildHexaPromptRole.unitTest,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
