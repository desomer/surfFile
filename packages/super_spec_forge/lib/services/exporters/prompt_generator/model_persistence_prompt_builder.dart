/// Générateur du prompt IA de persistance hexagonale (port sortant Repository,
/// entité d'infrastructure, mapper et adaptateur) d'un modèle ([buildModelPersistencePrompt]).
library;

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../spec_storage_slug.dart';
import 'model_prompt_context.dart';
import 'prompt_evolution_sections.dart';
import 'prompt_generator_models.dart';
import 'prompt_json_schema_builder.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Persistance (Port & Adaptateur) » d'un modèle/contrat.
BuildHexaPromptSpec buildModelPersistencePrompt({
  required ModelPromptContext ctx,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  BusinessObjectModelPreferences? modelPreferences,
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
      'Port sortant Repository, entité/schéma de persistance dédié, mapper Domain ↔ Infra et adaptateur.';
  final title = '${item.name} — Persistance (Implémentation)';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      BuildDesignItemKind.model,
      BuildTechStackSection.persistence,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      objectSpec.technicalName,
      BuildHexaPromptRole.implementation,
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
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.persistence.slug,
      'layer': 'infrastructure',
      'role': 'implementation',
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
    ctx: ctx,
    techStack: techStack,
    modelPreferences: modelPreferences,
    evolutionDecision: evolutionDecision,
  );

  return BuildHexaPromptSpec(
    id: '${item.kind.name}:${item.id}:${BuildTechStackSection.persistence.name}:${BuildHexaPromptRole.implementation.name}',
    item: item,
    section: BuildTechStackSection.persistence,
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
  required ModelPromptContext ctx,
  BuildTechStackProfile? techStack,
  BusinessObjectModelPreferences? modelPreferences,
  required PromptEvolutionDecision evolutionDecision,
}) {
  final domain = ctx.domain;
  final objectSpec = ctx.objectSpec;
  final policy = ctx.layerSpec.persistencePolicy;
  final portName = ctx.portName;

  final buf = StringBuffer()
    ..writeln(
      '# Persistance Hexagonale (`$portName` & Adaptateur Infra)',
    )
    ..writeln()
    ..writeln('## 1. Objectif Architectural (Driven Port & Driven Adapter)')
    ..writeln(
      'Implémente la persistance complète de **`${objectSpec.technicalName}`** (**${objectSpec.name}**, domaine `${domain.domainCode}`) en séparant strictement :',
    )
    ..writeln(
      '1. **Le Port Sortant (`Driven Port`)** `$portName` dans `domain/ports/outbound/` (manipulant uniquement les types métier du domaine).',
    )
    ..writeln(
      '2. **Le Modèle / Schéma de Persistance & le Mapper bidirectionnel** (`${objectSpec.technicalName}Entity` / Row ↔ `${objectSpec.technicalName}`) dans `infrastructure/persistence/`.',
    )
    ..writeln(
      '3. **L’Adaptateur d’Infrastructure (`Driven Adapter`)** implémentant `$portName` avec la technologie de persistance du projet, accompagné de ses tests de contrat/persistance.',
    )
    ..writeln();

  if (modelPreferences != null) {
    buf
      ..writeln('## 2. Conventions Techniques du Modèle')
      ..writeln(modelPreferences.toPromptDirective())
      ..writeln();
  }

  PromptEvolutionSections.writeModelEvolutionSection(
    buf,
    decision: evolutionDecision,
    ctx: ctx,
    section: BuildTechStackSection.persistence,
    role: BuildHexaPromptRole.implementation,
  );

  buf
    ..writeln('## 3. Politique de Persistance & Contrat du Port `$portName`')
    ..writeln('- **Port sortant** : `$portName`')
    ..writeln(
      '- **Frontière transactionnelle d’agrégat** : ${policy.aggregateBoundary.trim().isNotEmpty ? policy.aggregateBoundary.trim() : objectSpec.technicalName}',
    )
    ..writeln(
      '- **Contrôle de concurrence** : ${policy.concurrencyStrategy.label}',
    )
    ..writeln(
      '- **Politique de suppression** : ${policy.deletionStrategy.label}',
    );
  if (policy.consistencyNotes.trim().isNotEmpty) {
    buf.writeln(
      '- **Notes de cohérence** : ${policy.consistencyNotes.trim()}',
    );
  }
  if (policy.rules.isNotEmpty) {
    buf.writeln('- **Règles transverses de persistance** :');
    for (final r in policy.rules) {
      buf.writeln('  - $r');
    }
  }
  buf.writeln();

  if (policy.portMethods.isNotEmpty) {
    buf.writeln('### 3.1 Méthodes du Port & Contraintes Index / Unicité');
    for (final m in policy.portMethods) {
      if (m.hasMethod) {
        buf.writeln(
          '- `[${m.category.label}]` **${m.effectiveTitle}** : `${m.effectiveAssociatedMethods.join('`, `')}`',
        );
      } else {
        buf.writeln('- `[${m.category.label}]` **${m.effectiveTitle}**');
      }
      for (final rule in m.effectiveRules) {
        buf.writeln('  - Règle : $rule');
      }
    }
    buf.writeln();
  } else {
    buf
      ..writeln('### 3.1 Méthodes Minimales Attendues sur `$portName`')
      ..writeln(
        '- Opérations de sauvegarde atomique, lecture par identifiant, vérification d’existence/unicité et recherche selon les besoins du domaine.',
      )
      ..writeln();
  }

  if (objectSpec.attributes.isNotEmpty || objectSpec.relations.isNotEmpty) {
    buf.writeln(
      '### 3.2 JSON Schema de Persistance (${objectSpec.technicalName})',
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
  );

  buf
    ..writeln('## 4. Livrables & Vérification')
    ..writeln(
      '1. Crée l’interface `$portName` côté `domain/` sans aucune fuite d’infrastructure.',
    )
    ..writeln(
      '2. Implémente le schéma/migration éventuel, l’entité infra, le mapper fidèle (incluant sous-objets, enums et stratégie `${policy.concurrencyStrategy.name}` / `${policy.deletionStrategy.name}`) et l’adaptateur concret côté `infrastructure/`.',
    )
    ..writeln(
      '3. Ajoute et exécute les tests du mapper et les tests de contrat du repository (persistance aller-retour, unicité, concurrence et suppression).',
    );

  PromptMarkdownSections.writeTechStackExtensionSection(
    buf,
    domain: domain,
    section: BuildTechStackSection.persistence,
    role: BuildHexaPromptRole.implementation,
    techStack: techStack,
  );

  return SpecStorageIo.normalizeLf(buf.toString());
}
