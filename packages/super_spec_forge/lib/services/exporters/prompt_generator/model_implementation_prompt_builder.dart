/// Générateur du prompt IA d'implémentation de la couche Domain d'un modèle
/// en Architecture Hexagonale ([buildModelImplementationPrompt]).
library;

import '../../../models/build_design_item.dart';
import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/company_glossary.dart';
import '../../spec_storage_slug.dart';
import 'model_prompt_context.dart';
import 'prompt_generator_models.dart';
import 'prompt_json_schema_builder.dart';
import 'prompt_markdown_sections.dart';
import 'prompt_yaml_header_builder.dart';

/// Construit le prompt « Implémentation Couche Domain » d'un modèle/contrat.
BuildHexaPromptSpec buildModelImplementationPrompt({
  required ModelPromptContext ctx,
  required PromptMetadataDates dates,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  final domain = ctx.domain;
  final item = ctx.item;
  final objectSpec = ctx.objectSpec;
  final dslType = ctx.dslType;
  final summary =
      'Modèle immuable/encapsulé `${objectSpec.technicalName}`, invariants, fabriques, mutations d’état, calculs purs et événements du domaine.';
  final title = '${item.name} — Implémentation Couche Domain';

  final header = PromptYamlHeaderBuilder.buildFencedYamlHeader(
    kind: PromptYamlHeaderBuilder.kindFor(
      BuildDesignItemKind.model,
      BuildTechStackSection.domain,
      BuildHexaPromptRole.implementation,
    ),
    name: PromptYamlHeaderBuilder.buildPromptSlug(
      objectSpec.technicalName,
      BuildHexaPromptRole.implementation,
    ),
    title: title,
    version: ctx.detail.version,
    domainCode: domain.domainCode,
    description: objectSpec.description.trim().isNotEmpty
        ? '${objectSpec.description.trim()} — $summary'
        : summary,
    tags: <String>[
      'hexagonal-architecture',
      if (techStack != null) techStack.code,
      domain.domainCode,
      dslType,
      'domain-layer',
      'implementation',
    ],
    generation: <String, String>{
      'architecture': 'hexagonal',
      if (techStack != null) 'stack': techStack.code,
      'section': BuildTechStackSection.domain.slug,
      'layer': 'domain',
      'role': 'implementation',
      'artifactType': dslType,
      'artifactName': objectSpec.technicalName,
    },
    dates: dates,
  );

  final body = _formatBody(
    ctx: ctx,
    techStack: techStack,
    glossary: glossary,
    modelPreferences: modelPreferences,
  );

  return BuildHexaPromptSpec(
    id: '${item.kind.name}:${item.id}:${BuildTechStackSection.domain.name}:${BuildHexaPromptRole.implementation.name}',
    item: item,
    section: BuildTechStackSection.domain,
    role: BuildHexaPromptRole.implementation,
    title: title,
    summary: summary,
    promptMarkdown: SpecStorageIo.normalizeLf('$header\n\n$body'),
  );
}

String _formatBody({
  required ModelPromptContext ctx,
  BuildTechStackProfile? techStack,
  CompanyGlossary? glossary,
  BusinessObjectModelPreferences? modelPreferences,
}) {
  final domain = ctx.domain;
  final objectSpec = ctx.objectSpec;
  final dslType = ctx.dslType;
  final groupName = ctx.groupName;

  final buf = StringBuffer()
    ..writeln(
      '# Implémentation Hexagonale (Modèle `${objectSpec.technicalName}`)',
    )
    ..writeln()
    ..writeln('## 1. Mission & Règles d’Architecture Hexagonale')
    ..writeln(
      'Tu interviens comme architecte et développeur senior DDD / Architecture Hexagonale.',
    )
    ..writeln(
      'Implémente l’élément **`${objectSpec.technicalName}`** (**${objectSpec.name}**, type DSL `$dslType` · version `${ctx.detail.version}`) appartenant au domaine fonctionnel **`${domain.domainCode}`** (**${domain.name}**).',
    )
    ..writeln()
    ..writeln(
      '- **Isolation stricte du domaine** : aucune dépendance vers un framework web, ORM, client HTTP, base de données ou annotation d’infrastructure dans la couche `domain/`.',
    )
    ..writeln(
      '- **Encapsulation & Immuabilité** : protège les collections internes, valide systématiquement tous les invariants à l’instanciation et lors de chaque transition d’état.',
    )
    ..writeln(
      '- **Erreurs métier explicites** : lève des exceptions ou résultats typés du domaine (jamais d’exceptions techniques génériques).',
    )
    ..writeln();

  PromptMarkdownSections.writeDomainContextSection(
    buf,
    domain,
    glossary,
    modelPreferences,
  );

  buf
    ..writeln(
      '## 3. Spécification Structurelle de `${objectSpec.technicalName}`',
    )
    ..writeln('- **Nom technique** : `${objectSpec.technicalName}`')
    ..writeln('- **Libellé métier** : ${objectSpec.name}')
    ..writeln(
      '- **Classification DSL** : `$dslType`${groupName.isEmpty ? '' : ' (rubrique `$groupName`)'}',
    )
    ..writeln(
      '- **Rôle DDD** : ${objectSpec.aggregateRoot ? 'Agrégat racine (Aggregate Root)' : 'Entité / Value Object / Contrat'}',
    );
  if (objectSpec.description.trim().isNotEmpty) {
    buf.writeln(
      '- **Description métier** : ${objectSpec.description.trim()}',
    );
  }
  buf.writeln();

  if (objectSpec.attributes.isNotEmpty || objectSpec.relations.isNotEmpty) {
    buf.writeln('### 3.1 JSON Schema (${objectSpec.technicalName})');
    PromptJsonSchemaBuilder.writeJsonSchemaBlock(
      buf,
      PromptJsonSchemaBuilder.buildModelSchema(ctx),
    );
    buf.writeln();
  } else {
    buf
      ..writeln(
        '### 3.1 JSON Schema (${objectSpec.technicalName})\n_Aucun attribut détaillé saisi : déduis ou conserve la structure minimale cohérente avec le codebase existant._',
      )
      ..writeln();
  }

  if (objectSpec.lifecycleStates.isNotEmpty ||
      objectSpec.lifecycleTransitions.isNotEmpty) {
    buf.writeln('### 3.2 Cycle de Vie & Transitions Autorisées');
    if (objectSpec.lifecycleStates.isNotEmpty) {
      for (final st in objectSpec.lifecycleStates) {
        final flags = <String>[
          if (st.isInitial) 'initial',
          if (st.isTerminal) 'terminal',
        ];
        buf.writeln(
          '- État `${st.name}` (${st.effectiveLabel}${flags.isEmpty ? '' : ' · ${flags.join(', ')}'})',
        );
      }
    }
    if (objectSpec.lifecycleTransitions.isNotEmpty) {
      for (final tr in objectSpec.lifecycleTransitions) {
        buf.writeln(
          '- Transition `${tr.fromState}` → `${tr.toState}`'
          '${tr.trigger.trim().isEmpty ? '' : ' sur `${tr.trigger.trim()}`'}'
          '${tr.guardSummary.trim().isEmpty ? '' : ' (garde : ${tr.guardSummary.trim()})'}',
        );
      }
    }
    buf.writeln();
  }

  PromptMarkdownSections.writeReferencedValueObjectsSection(
    buf,
    ctx.referencedValueObjects,
  );

  PromptMarkdownSections.writeDomainLayerBehaviorsSection(
    buf,
    objectSpec,
    ctx.layerSpec,
  );

  buf
    ..writeln('## 5. Livrables Attendus')
    ..writeln(
      '1. Inspecte d’abord l’arborescence et les conventions existantes du dépôt cible (langage, structure des dossiers `domain/`, conventions de nommage et types partagés).',
    )
    ..writeln(
      '2. Crée ou mets à jour le modèle `${objectSpec.technicalName}`, ses Value Objects, ses événements du domaine et ses exceptions métier dans la couche `domain/`.',
    )
    ..writeln(
      '3. Vérifie la compilation et l’analyse statique sans introduire aucune dépendance vers `infrastructure/` ou `presentation/`.',
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
