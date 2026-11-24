/// Générateur du prompt IA de tests unitaires TDD de la couche Domain d'un modèle
/// ([buildModelUnitTestPrompt]).
library;

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../spec_storage_slug.dart';
import 'model_prompt_context.dart';
import 'prompt_generator_models.dart';
import 'prompt_json_schema_builder.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Tests unitaires Couche Domain » d'un modèle/contrat.
BuildHexaPromptSpec buildModelUnitTestPrompt({
  required ModelPromptContext ctx,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
}) {
  final domain = ctx.domain;
  final item = ctx.item;
  final objectSpec = ctx.objectSpec;
  final dslType = ctx.dslType;
  final summary =
      'Suite TDD unitaire couvrant les invariants, contraintes d’attributs, transitions d’état et événements de `${objectSpec.technicalName}`.';
  final title = '${item.name} — Tests unitaires Couche Domain';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      BuildDesignItemKind.model,
      BuildTechStackSection.domain,
      BuildHexaPromptRole.unitTest,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      objectSpec.technicalName,
      BuildHexaPromptRole.unitTest,
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
      'artifactType': dslType,
      'artifactName': objectSpec.technicalName,
    },
    dates: dates,
  );

  final body = _formatBody(ctx, techStack: techStack);

  return BuildHexaPromptSpec(
    id: '${item.kind.name}:${item.id}:${BuildTechStackSection.domain.name}:${BuildHexaPromptRole.unitTest.name}',
    item: item,
    section: BuildTechStackSection.domain,
    role: BuildHexaPromptRole.unitTest,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

String _formatBody(ModelPromptContext ctx, {BuildTechStackProfile? techStack}) {
  final domain = ctx.domain;
  final objectSpec = ctx.objectSpec;
  final layerSpec = ctx.layerSpec;

  final buf = StringBuffer()
    ..writeln(
      '# Tests Unitaires TDD (Modèle `${objectSpec.technicalName}`)',
    )
    ..writeln()
    ..writeln('## 1. Objectif')
    ..writeln(
      'Écris la suite complète de **tests unitaires purs** de la couche `domain/` pour **`${objectSpec.technicalName}`** (**${objectSpec.name}**, domaine `${domain.domainCode}`).',
    )
    ..writeln(
      '- Aucun accès base de données, système de fichiers, horloge système non contrôlée ni réseau.',
    )
    ..writeln(
      '- Structure chaque test selon le pattern **Arrange / Act / Assert** avec des noms explicites orientés règles métier.',
    )
    ..writeln()
    ..writeln('## 2. Matrice des Cas de Tests à Couvrir')
    ..writeln('### 2.1 Instanciation, Fabriques & Contrat JSON Schema')
    ..writeln(
      '- Création nominale valide de `${objectSpec.technicalName}` (et fabriques : ${layerSpec.factories.isEmpty ? 'constructeur / fabrique standard' : layerSpec.factories.map((f) => '`${f.effectiveMethodSignature}`').join(', ')}).',
    );

  if (objectSpec.attributes.isNotEmpty || objectSpec.relations.isNotEmpty) {
    buf.writeln(
      '- Valide chaque propriété, type, format, borne, `enum`, `required` et nullabilité définis par le JSON Schema ci-dessous :',
    );
    PromptJsonSchemaBuilder.writeJsonSchemaBlock(
      buf,
      PromptJsonSchemaBuilder.buildModelSchema(ctx),
    );
  }

  if (layerSpec.invariants.isNotEmpty) {
    buf.writeln('\n### 2.2 Invariants Métier');
    for (final inv in layerSpec.invariants) {
      buf.writeln(
        '- **${inv.code.isEmpty ? inv.title : '${inv.code} — ${inv.title}'}**'
        '${inv.expression.isEmpty ? '' : ' (`${inv.expression}`)'}'
        '${inv.violationError.isEmpty ? '' : ' → erreur attendue `${inv.violationError}`'}.',
      );
    }
  }

  if (layerSpec.stateChanges.isNotEmpty ||
      objectSpec.lifecycleTransitions.isNotEmpty) {
    buf.writeln('\n### 2.3 Mutations d’État & Événements du Domaine');
    for (final sc in layerSpec.stateChanges) {
      buf.writeln(
        '- `${sc.effectiveMethodSignature}` (${sc.effectiveTitle}) : cas nominal'
        '${sc.effectiveStateChangeRule.isEmpty ? '' : ' [${sc.effectiveStateChangeRule}]'}'
        '${sc.emittedEvents.isEmpty ? '' : ', émission de ${sc.emittedEvents.map((e) => '`$e`').join(', ')}'}'
        '${sc.domainErrors.isEmpty ? '' : ', et refus métier (${sc.domainErrors.join(', ')})'}.',
      );
    }
    for (final tr in objectSpec.lifecycleTransitions) {
      buf.writeln(
        '- Transition `${tr.fromState}` → `${tr.toState}` autorisée et rejet depuis un état interdit.',
      );
    }
  }

  if (layerSpec.queries.isNotEmpty || layerSpec.policyServices.isNotEmpty) {
    buf.writeln('\n### 2.4 Calculs Purs (`Query`) & `Policy Services`');
    for (final q in layerSpec.queries) {
      buf.writeln(
        '- `${q.name}(${q.parameters.join(', ')}) -> ${q.returnType}` : cas nominaux et cas aux limites${q.formula.isEmpty ? '' : ' (`${q.formula}`)'}.',
      );
    }
    for (final p in layerSpec.policyServices) {
      buf.writeln(
        '- `${p.effectiveMethodSignature}` (${p.effectiveTitle}) : règles ${p.effectiveRules.isEmpty ? 'métier' : p.effectiveRules.join(' ; ')}.',
      );
    }
  }

  buf
    ..writeln()
    ..writeln('## 3. Exécution & Critères de Succès')
    ..writeln(
      '1. Crée le fichier de test unitaire au bon emplacement dans le dossier de tests de la couche `domain/`.',
    )
    ..writeln(
      '2. Lance la commande de tests du projet et corrige toute régression jusqu’à obtenir **100 % des tests au vert**.',
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
