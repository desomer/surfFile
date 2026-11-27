/// Générateur du prompt IA de tests unitaires de la couche Persistance
/// (mapper bidirectionnel, schéma et repository) d'un modèle
/// ([buildModelPersistenceUnitTestPrompt]).
library;

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../spec_storage_slug.dart';
import 'model_prompt_context.dart';
import 'prompt_evolution_sections.dart';
import 'prompt_generator_models.dart';
import 'prompt_json_schema_builder.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Persistance (Test unitaire) » d'un modèle/contrat.
BuildHexaPromptSpec buildModelPersistenceUnitTestPrompt({
  required ModelPromptContext ctx,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  PromptEvolutionDecision evolutionDecision =
      const PromptEvolutionDecision.none(),
}) {
  final domain = ctx.domain;
  final item = ctx.item;
  final objectSpec = ctx.objectSpec;
  final policy = ctx.layerSpec.persistencePolicy;
  final dslType = ctx.dslType;
  final portName = ctx.portName;

  const summary =
      'Tests unitaires du mapper Domain ↔ Persistence, du verrouillage optimiste, de la suppression et de la traduction des erreurs BDD.';
  final title = '${item.name} — Persistance (Test unitaire)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      BuildDesignItemKind.model,
      BuildTechStackSection.persistence,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      objectSpec.technicalName,
      BuildHexaPromptRole.unitTest,
      section: BuildTechStackSection.persistence,
    ),
    title: title,
    version: ctx.detail.version,
    domainCode: domain.domainCode,
    description: summary,
    tags: <String>[
      'hexagonal-architecture',
      if (techStack != null) techStack.code,
      domain.domainCode,
      dslType,
      'infrastructure-layer',
      'persistence',
      'repository',
      'unit-test',
      'tdd',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.persistence.slug,
      'layer': 'infrastructure',
      'role': 'unit-test',
      'artifactType': dslType,
      'artifactName': objectSpec.technicalName,
      'repositoryPort': portName,
      'concurrency': policy.concurrencyStrategy.name,
      'deletion': policy.deletionStrategy.name,
    },
    dates: dates,
    isEvolutionDelta: evolutionDecision.isEvolutionDelta,
    baselineIteration: evolutionDecision.baselineLabel,
    previousVersion: evolutionDecision.baselineVersion,
    changeImpact: evolutionDecision.changeBump,
  );

  final body = _formatBody(
    ctx,
    techStack: techStack,
    evolutionDecision: evolutionDecision,
  );

  return BuildHexaPromptSpec(
    id: '${item.kind.name}:${item.id}:${BuildTechStackSection.persistence.name}:${BuildHexaPromptRole.unitTest.name}',
    item: item,
    section: BuildTechStackSection.persistence,
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

String _formatBody(
  ModelPromptContext ctx, {
  BuildTechStackProfile? techStack,
  required PromptEvolutionDecision evolutionDecision,
}) {
  final domain = ctx.domain;
  final objectSpec = ctx.objectSpec;
  final policy = ctx.layerSpec.persistencePolicy;
  final portName = ctx.portName;

  final buf = StringBuffer()
    ..writeln(
      '# Tests Unitaires Persistance (`$portName` & Mapper)',
    )
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Écris la suite de **tests unitaires** de la persistance pour **`${objectSpec.technicalName}`** (**${objectSpec.name}**, domaine `${domain.domainCode}`) en isolant la base de données réelle via des doublures/stubs du client ou modèle de persistance.',
    )
    ..writeln();

  PromptEvolutionSections.writeModelEvolutionSection(
    buf,
    decision: evolutionDecision,
    ctx: ctx,
    section: BuildTechStackSection.persistence,
    role: BuildHexaPromptRole.unitTest,
  );

  buf
    ..writeln('## 2. Scénarios de Test Obligatoires')
    ..writeln(
      '1. **Mapper bidirectionnel (`toPersistence` / `toDomain`)** : vérifie l’aller-retour fidèle de tous les attributs, Value Objects, sous-objets, enums et dates via `reconstitute()`.',
    )
    ..writeln(
      '2. **Concurrence & Suppression** : valide la stratégie `${policy.concurrencyStrategy.label}` (conflit de version → erreur métier dédiée) et la politique `${policy.deletionStrategy.label}`.',
    )
    ..writeln(
      '3. **Traduction des erreurs techniques & unicité** : vérifie la conversion des violations d’unicité/contrainte, conflits d’écriture et timeouts en erreurs métier typées.',
    );

  if (policy.portMethods.isNotEmpty) {
    buf.writeln('4. **Méthodes du port `$portName`** :');
    for (final m in policy.portMethods) {
      buf.writeln(
        '   - `[${m.category.label}]` **${m.effectiveTitle}**'
        '${m.hasMethod ? ' (`${m.effectiveAssociatedMethods.join('`, `')}`)' : ''}',
      );
    }
  }
  buf.writeln();

  if (objectSpec.attributes.isNotEmpty || objectSpec.relations.isNotEmpty) {
    buf.writeln(
      '### 2.1 JSON Schema de Référence (${objectSpec.technicalName})',
    );
    PromptJsonSchemaBuilder.writeJsonSchemaBlock(
      buf,
      PromptJsonSchemaBuilder.buildModelSchema(ctx),
    );
    buf.writeln();
  }

  PromptMarkdownSections.writePersistenceValueObjectsMappingSection(
    buf,
    ctx.referencedValueObjects,
    heading: '### 2.2 Cas de Mapping Value Objects à Tester',
  );

  buf
    ..writeln('## 3. Exécution')
    ..writeln(
      'Exécute les tests unitaires de persistance et assure **100 % de réussite** sans dépendre d’une base de données active.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.persistence,
    role: BuildHexaPromptRole.unitTest,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
