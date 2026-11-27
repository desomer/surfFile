/// Générateur du prompt IA de tests unitaires TDD d'un [ValueObjectSpec]
/// (`scalar` ou `composite`) de la couche Domain
/// ([buildValueObjectUnitTestPrompt]).
library;

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/domain_catalog.dart';
import '../../../models/value_object_spec.dart';
import '../../spec_storage_slug.dart';
import 'prompt_evolution_sections.dart';
import 'prompt_generator_models.dart';
import 'prompt_json_schema_builder.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Tests unitaires Value Object » de la couche Domain.
BuildHexaPromptSpec buildValueObjectUnitTestPrompt({
  required FunctionalDomain domain,
  required BuildDesignItem item,
  required ValueObjectSpec valueObject,
  required ValueObjectScope scope,
  List<ResolvedValueObject> availableValueObjects =
      const <ResolvedValueObject>[],
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  BusinessObjectModelPreferences? modelPreferences,
  PromptEvolutionDecision evolutionDecision =
      const PromptEvolutionDecision.none(),
}) {
  final summary =
      'Suite TDD unitaire déterministe couvrant exemples valides/invalides, bornes JSON Schema, normalisation, égalité par valeur et immuabilité de `${valueObject.technicalName}`.';
  final title =
      '${valueObject.technicalName} — Tests unitaires Value Object (${scope.label})';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      BuildDesignItemKind.valueObject,
      BuildTechStackSection.domain,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      valueObject.technicalName,
      BuildHexaPromptRole.unitTest,
    ),
    title: title,
    version: valueObject.version,
    domainCode: domain.domainCode,
    description: summary,
    tags: <String>[
      'hexagonal-architecture',
      if (techStack != null) techStack.code,
      domain.domainCode,
      'value-object',
      valueObject.kind.name,
      if (scope == ValueObjectScope.shared) 'shared-kernel',
      'domain-layer',
      'unit-test',
      'tdd',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.domain.slug,
      'layer': 'domain',
      'role': 'unit-test',
      'artifactType': 'value-object',
      'artifactName': valueObject.technicalName,
      'valueObjectKind': valueObject.kind.name,
      'valueObjectScope': scope.name,
    },
    dates: dates,
    isEvolutionDelta: evolutionDecision.isEvolutionDelta,
    baselineIteration: evolutionDecision.baselineLabel,
    previousVersion: evolutionDecision.baselineVersion,
    changeImpact: evolutionDecision.changeBump,
  );

  final body = _formatBody(
    domain: domain,
    valueObject: valueObject,
    scope: scope,
    availableValueObjects: availableValueObjects,
    techStack: techStack,
    modelPreferences: modelPreferences,
    evolutionDecision: evolutionDecision,
  );

  return BuildHexaPromptSpec(
    id: '${item.kind.name}:${item.id}:${BuildTechStackSection.domain.name}:${BuildHexaPromptRole.unitTest.name}',
    item: item,
    section: BuildTechStackSection.domain,
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

String _formatBody({
  required FunctionalDomain domain,
  required ValueObjectSpec valueObject,
  required ValueObjectScope scope,
  required List<ResolvedValueObject> availableValueObjects,
  BuildTechStackProfile? techStack,
  BusinessObjectModelPreferences? modelPreferences,
  required PromptEvolutionDecision evolutionDecision,
}) {
  final buf = StringBuffer()
    ..writeln(
      '# Tests Unitaires TDD (Value Object `${valueObject.technicalName}`)',
    )
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Écris la suite complète de **tests unitaires purs et déterministes** pour le Value Object **`${valueObject.technicalName}`** (**${valueObject.name}**, forme `${valueObject.kind.label}` · portée `${scope.label}` · domaine `${domain.domainCode}`).',
    )
    ..writeln(
      '- Aucun accès I/O (base de données, réseau, système de fichiers ni horloge globale non contrôlée).',
    )
    ..writeln(
      '- Structure chaque cas selon **Arrange / Act / Assert** avec des intitulés explicites orientés règles métier.',
    )
    ..writeln();

  PromptEvolutionSections.writeValueObjectEvolutionSection(
    buf,
    decision: evolutionDecision,
    currentVo: valueObject,
    role: BuildHexaPromptRole.unitTest,
  );

  buf.writeln('## 2. Matrice des Cas de Tests Obligatoires');

  buf.writeln('### 2.1 Exemples Valides & Cas Nominaux');
  if (valueObject.validExamples.isNotEmpty) {
    for (final ex in valueObject.validExamples) {
      buf.writeln(
        '- ✅ Entrée `${ex.value}` → création réussie de `${valueObject.technicalName}`'
        '${ex.reason.trim().isEmpty ? '' : ' (${ex.reason.trim()})'}.',
      );
    }
  } else {
    buf.writeln(
      '- ✅ Création nominale valide de `${valueObject.technicalName}` et lecture cohérente de sa valeur / de ses champs.',
    );
  }
  buf.writeln();

  buf.writeln('### 2.2 Contre-Exemples Invalides & Valeurs aux Limites');
  if (valueObject.invalidExamples.isNotEmpty) {
    for (final ex in valueObject.invalidExamples) {
      buf.writeln(
        '- ❌ Entrée `${ex.value}` → rejet métier attendu'
        '${ex.reason.trim().isEmpty ? '' : ' (motif : ${ex.reason.trim()})'}.',
      );
    }
  }
  if (valueObject.isScalar) {
    final scSummary = valueObject.schemaConstraints.formatSummary();
    if (scSummary.isNotEmpty) {
      buf.writeln(
        '- ❌ Tester systématiquement les bornes exactes et hors-bornes des contraintes JSON Schema ($scSummary).',
      );
    }
    if (valueObject.enumValues.isNotEmpty) {
      buf.writeln(
        '- ❌ Rejeter toute valeur absente de `[${valueObject.enumValues.join(', ')}]`.',
      );
    }
  } else {
    buf.writeln(
      '- ❌ Tester chaque champ obligatoire manquant/invalide parmi `${valueObject.fields.map((f) => f.name).join('`, `')}`.',
    );
    for (final rule in valueObject.crossFieldRules) {
      buf.writeln('- ❌ Vérifier la violation de la règle inter-champs : $rule.');
    }
  }
  if (valueObject.constraints.trim().isNotEmpty) {
    buf.writeln(
      '- ❌ Vérifier les cas d’invalidation de : ${valueObject.constraints.trim()}.',
    );
  }
  buf.writeln();

  buf.writeln('### 2.3 Normalisation & Idempotence');
  if (valueObject.normalizationRules.isNotEmpty) {
    buf.writeln(
      '- 🧹 Vérifier l’application ordonnée de `${valueObject.normalizationRules.join('` → `')}` avant validation.',
    );
    buf.writeln(
      '- 🔁 Vérifier l’idempotence : recréer `${valueObject.technicalName}` à partir de sa valeur déjà normalisée produit une instance strictement égale.',
    );
  } else {
    buf.writeln(
      '- 🔁 Vérifier la préservation exacte de la valeur d’entrée sans altération silencieuse.',
    );
  }
  buf.writeln();

  buf
    ..writeln('### 2.4 Égalité Structurelle, `hashCode` & Immuabilité')
    ..writeln(
      '- Deux instances distinctes construites à partir de valeurs équivalentes (y compris avant/après normalisation) sont égales (`equals` == `true`) et partagent le même `hashCode`.',
    )
    ..writeln(
      '- Deux instances différant sur la valeur scalaire ou sur au moins un champ composite ne sont pas égales.',
    )
    ..writeln(
      '- Vérifier qu’aucune propriété interne de `${valueObject.technicalName}` ne peut être mutée après instanciation.',
    )
    ..writeln();

  buf.writeln(
    '### 2.5 JSON Schema de Référence (${valueObject.technicalName})',
  );
  PromptJsonSchemaBuilder.writeJsonSchemaBlock(
    buf,
    PromptJsonSchemaBuilder.buildValueObjectSchema(
      valueObject: valueObject,
      scope: scope,
      availableValueObjects: availableValueObjects,
      modelPreferences: modelPreferences,
    ),
  );
  buf.writeln();

  buf
    ..writeln('## 3. Exécution & Critères de Succès')
    ..writeln(
      '1. Crée le fichier de tests unitaires au bon emplacement dans le dossier de tests de la couche `domain/`.',
    )
    ..writeln(
      '2. Exécute la suite de tests et corrige toute anomalie jusqu’à obtenir **100 % des tests au vert**.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.domain,
    role: BuildHexaPromptRole.unitTest,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
