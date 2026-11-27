/// Générateur du prompt IA d'implémentation de la couche Domain d'un
/// [ValueObjectSpec] (`scalar` ou `composite`) en Architecture Hexagonale
/// ([buildValueObjectImplementationPrompt]).
library;

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/business_object_spec.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../../models/value_object_spec.dart';
import '../../spec_storage_slug.dart';
import 'prompt_evolution_sections.dart';
import 'prompt_generator_models.dart';
import 'prompt_json_schema_builder.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Implémentation Value Object » de la couche Domain.
BuildHexaPromptSpec buildValueObjectImplementationPrompt({
  required FunctionalDomain domain,
  required BuildDesignItem item,
  required ValueObjectSpec valueObject,
  required ValueObjectScope scope,
  List<ResolvedValueObject> availableValueObjects =
      const <ResolvedValueObject>[],
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
  PromptEvolutionDecision evolutionDecision =
      const PromptEvolutionDecision.none(),
}) {
  final summary = valueObject.isComposite
      ? 'Value Object composite immuable `${valueObject.technicalName}`, égalité structurelle, validation des champs et règles inter-champs.'
      : 'Value Object scalaire immuable `${valueObject.technicalName}` (`${valueObject.primitiveType.dslKeyword}`), normalisation, validation des contraintes et égalité par valeur.';
  final title =
      '${valueObject.technicalName} — Implémentation Value Object (${scope.label})';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      BuildDesignItemKind.valueObject,
      BuildTechStackSection.domain,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      valueObject.technicalName,
      BuildHexaPromptRole.implementation,
    ),
    title: title,
    version: valueObject.version,
    domainCode: domain.domainCode,
    description: valueObject.description.trim().isNotEmpty
        ? '${valueObject.description.trim()} — $summary'
        : summary,
    tags: <String>[
      'hexagonal-architecture',
      if (techStack != null) techStack.code,
      domain.domainCode,
      'value-object',
      valueObject.kind.name,
      if (scope == ValueObjectScope.shared) 'shared-kernel',
      'domain-layer',
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.domain.slug,
      'layer': 'domain',
      'role': 'implementation',
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
    glossary: glossary,
    modelPreferences: modelPreferences,
    evolutionDecision: evolutionDecision,
  );

  return BuildHexaPromptSpec(
    id: '${item.kind.name}:${item.id}:${BuildTechStackSection.domain.name}:${BuildHexaPromptRole.implementation.name}',
    item: item,
    section: BuildTechStackSection.domain,
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

String _formatBody({
  required FunctionalDomain domain,
  required ValueObjectSpec valueObject,
  required ValueObjectScope scope,
  required List<ResolvedValueObject> availableValueObjects,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
  required PromptEvolutionDecision evolutionDecision,
}) {
  final childVos = _resolveChildValueObjects(valueObject, availableValueObjects);
  final buf = StringBuffer()
    ..writeln(
      '# Implémentation Hexagonale (Value Object `${valueObject.technicalName}`)',
    )
    ..writeln()
    ..writeln('## 1. Mission & Règles DDD / Architecture Hexagonale')
    ..writeln(
      'Tu interviens comme architecte et développeur senior DDD / Architecture Hexagonale.',
    )
    ..writeln(
      'Implémente le Value Object **`${valueObject.technicalName}`** (**${valueObject.name}**, forme `${valueObject.kind.label}` · portée `${scope.label}` · version `${valueObject.version}`) dans le domaine **`${domain.domainCode}`** (**${domain.name}**).',
    )
    ..writeln()
    ..writeln(
      '- **Isolation pure de la couche `domain/`** : aucune dépendance vers un framework HTTP, ORM, base de données ou librairie d’infrastructure.',
    )
    ..writeln(
      '- **Immuabilité totale & Constructeur privé** : tous les champs sont immuables (`final` / `readonly`), aucune mutation en place ; instanciation exclusivement via une fabrique validée (`create(...)` / `fromPrimitive(...)`).',
    )
    ..writeln(
      '- **Égalité structurelle par valeur (`equals` / `hashCode`)** : deux instances de `${valueObject.technicalName}` portant les mêmes valeurs normalisées sont strictement égales (aucune identité propre).',
    )
    ..writeln(
      '- **Erreurs métier explicites** : rejette toute entrée invalide par une erreur ou un résultat typé du domaine (jamais d’exception technique générique).',
    )
    ..writeln();

  PromptMarkdownSections.writeDomainContextSection(
    buf,
    domain,
    glossary,
    modelPreferences,
  );

  PromptEvolutionSections.writeValueObjectEvolutionSection(
    buf,
    decision: evolutionDecision,
    currentVo: valueObject,
    role: BuildHexaPromptRole.implementation,
  );

  buf
    ..writeln(
      '## 3. Spécification Détaillée de `${valueObject.technicalName}`',
    )
    ..writeln('- **Nom technique** : `${valueObject.technicalName}`')
    ..writeln('- **Libellé métier** : ${valueObject.name}')
    ..writeln('- **Catégorie** : ${valueObject.category}')
    ..writeln(
      '- **Portée** : `${scope.label}` (${scope == ValueObjectScope.shared ? 'partagé dans le Shared Kernel transverse et réutilisable entre domaines' : 'propre au Bounded Context `${domain.domainCode}`'})',
    )
    ..writeln('- **Forme structurelle** : `${valueObject.kind.label}`');
  if (valueObject.description.trim().isNotEmpty) {
    buf.writeln('- **Description métier** : ${valueObject.description.trim()}');
  }
  buf.writeln();

  buf.writeln('### 3.1 Normalisation & Invariants de Validation');
  if (valueObject.normalizationRules.isNotEmpty) {
    buf.writeln(
      '- **Pipeline de normalisation (appliqué avant validation)** : `${valueObject.normalizationRules.join('` → `')}`.',
    );
  } else {
    buf.writeln(
      '- **Normalisation** : aucune transformation implicite déclarée (conserver la valeur canonique telle quelle).',
    );
  }

  if (valueObject.isScalar) {
    buf.writeln(
      '- **Type primitif encapsulé** : `${valueObject.primitiveType.dslKeyword}` (${valueObject.primitiveType.label}).',
    );
    final scSummary = valueObject.schemaConstraints.formatSummary();
    if (scSummary.isNotEmpty) {
      buf.writeln('- **Contraintes JSON Schema** : $scSummary.');
    }
    if (valueObject.enumValues.isNotEmpty) {
      buf.writeln(
        '- **Valeurs autorisées (`enum`)** : `${valueObject.enumValues.join('`, `')}`.',
      );
    }
  } else {
    buf.writeln('- **Champs immuables du composite** :');
    for (final field in valueObject.fields) {
      final typeLabel = field.type == BusinessAttributeType.valueObject
          ? 'ValueObject `${field.valueObjectId}`'
          : '`${field.type.dslKeyword}`';
      final sc = field.schemaConstraints.formatSummary();
      buf.writeln(
        '  - `${field.name}` ($typeLabel · ${field.required ? 'obligatoire' : 'optionnel'}${field.nullable ? ', nullable' : ''})'
        '${sc.isEmpty ? '' : ' [$sc]'}'
        '${field.description.trim().isEmpty ? '' : ' — ${field.description.trim()}'}',
      );
    }
    if (valueObject.crossFieldRules.isNotEmpty) {
      buf.writeln('- **Règles métier inter-champs (`crossFieldRules`)** :');
      for (final rule in valueObject.crossFieldRules) {
        buf.writeln('  - $rule');
      }
    }
  }
  if (valueObject.constraints.trim().isNotEmpty) {
    buf.writeln(
      '- **Invariants complémentaires** : ${valueObject.constraints.trim()}',
    );
  }
  buf.writeln();

  buf.writeln(
    '### 3.2 JSON Schema Draft 2020-12 (${valueObject.technicalName})',
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

  if (childVos.isNotEmpty) {
    PromptMarkdownSections.writeReferencedValueObjectsSection(
      buf,
      childVos,
      heading: '### 3.3 Value Objects Enfants Référencés',
    );
  }

  if (valueObject.examples.isNotEmpty) {
    buf
      ..writeln('### 3.4 Exemples Valides & Contre-Exemples Métier')
      ..writeln('| Cas | Valeur d’entrée | Résultat attendu | Raison / Règle |')
      ..writeln('| --- | --- | --- | --- |');
    for (final ex in valueObject.validExamples) {
      buf.writeln(
        '| Valide | `${_escapeTableCell(ex.value)}` | Instance `${valueObject.technicalName}` créée | ${_escapeTableCell(ex.reason.isEmpty ? 'Cas nominal valide' : ex.reason)} |',
      );
    }
    for (final ex in valueObject.invalidExamples) {
      buf.writeln(
        '| Invalide | `${_escapeTableCell(ex.value)}` | Rejet métier explicite | ${_escapeTableCell(ex.reason.isEmpty ? 'Violation d’invariant' : ex.reason)} |',
      );
    }
    buf.writeln();
  }

  buf
    ..writeln('## 4. Livrables Attendus')
    ..writeln(
      '1. Inspecte les conventions existantes du dépôt cible pour les Value Objects (${scope == ValueObjectScope.shared ? 'module Shared Kernel ou dossier partagé' : 'dossier `domain/` du module `${domain.domainCode}`'}).',
    )
    ..writeln(
      '2. Implémente `${valueObject.technicalName}` avec son constructeur privé, sa fabrique validée `create(...)`, son déballage primitif/sérialisable explicite, son égalité structurelle (`equals` / `hashCode`) et ses erreurs métier dédiées.',
    )
    ..writeln(
      '3. Vérifie la compilation et l’analyse statique sans aucune dépendance externe interdite.',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.domain,
    role: BuildHexaPromptRole.implementation,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}

List<ResolvedValueObject> _resolveChildValueObjects(
  ValueObjectSpec root,
  List<ResolvedValueObject> pool,
) {
  if (!root.isComposite || pool.isEmpty) return const <ResolvedValueObject>[];
  final byId = <String, ResolvedValueObject>{
    for (final r in pool) r.spec.id: r,
  };
  final byTech = <String, ResolvedValueObject>{
    for (final r in pool) r.spec.technicalName.toLowerCase(): r,
  };
  final out = <ResolvedValueObject>[];
  final visited = <String>{root.id};

  void visit(ValueObjectSpec current) {
    for (final ref in current.referencedValueObjectIds) {
      final resolved = byId[ref] ?? byTech[ref.toLowerCase()];
      if (resolved != null && visited.add(resolved.spec.id)) {
        out.add(resolved);
        if (resolved.spec.isComposite) {
          visit(resolved.spec);
        }
      }
    }
  }

  visit(root);
  return List<ResolvedValueObject>.unmodifiable(out);
}

String _escapeTableCell(String raw) =>
    raw.replaceAll('|', r'\|').replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
