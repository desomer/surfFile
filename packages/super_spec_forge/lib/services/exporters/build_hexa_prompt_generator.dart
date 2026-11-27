/// Orchestrateur de génération de prompts IA en Architecture Hexagonale
/// ([BuildHexaPromptGenerator]), déléguant chaque type de prompt au module
/// dédié sous `prompt_generator/`.
library;

import '../../models/build_design_item.dart';
import '../../models/build_tech_stack_profile.dart';
import '../../models/business_object_model_preferences.dart';
import '../../models/company_glossary.dart';
import '../../models/domain_catalog.dart';
import '../../models/usecase_orchestration_spec.dart';
import '../spec_storage_slug.dart';
import 'prompt_generator/domain_boilerplate_prompt_builders.dart';
import 'prompt_generator/domain_check_integration_prompt_builders.dart';
import 'prompt_generator/domain_dev_tools_prompt_builders.dart';
import 'prompt_generator/domain_inbound_prompt_builders.dart';
import 'prompt_generator/domain_outbound_prompt_builders.dart';
import 'prompt_generator/model_implementation_prompt_builder.dart';
import 'prompt_generator/model_persistence_prompt_builder.dart';
import 'prompt_generator/model_persistence_unit_test_prompt_builder.dart';
import 'prompt_generator/model_prompt_context.dart';
import 'prompt_generator/model_unit_test_prompt_builder.dart';
import 'prompt_generator/prompt_generator_models.dart';
import 'prompt_generator/prompt_yaml_header_builder.dart';
import 'prompt_generator/saga_implementation_prompt_builder.dart';
import 'prompt_generator/saga_unit_test_prompt_builder.dart';
import 'prompt_generator/usecase_implementation_prompt_builder.dart';
import 'prompt_generator/usecase_unit_test_prompt_builder.dart';

export 'prompt_generator/prompt_generator_models.dart';

/// Assemble les prompts Markdown pour implémenter les modèles, cas d'usage,
/// sagas et adaptateurs Outbound / Inbound selon une **Architecture Hexagonale**
/// stricte (Ports & Adapters, DDD, CQRS & TDD).
abstract final class BuildHexaPromptGenerator {
  /// Rôles de prompts applicables à chaque section (`Implémentation`, `Test unitaire`).
  static const List<BuildHexaPromptRole> standardRoles = <BuildHexaPromptRole>[
    BuildHexaPromptRole.implementation,
    BuildHexaPromptRole.unitTest,
  ];

  /// Retourne l'identifiant canonique `kind` en `kebab-case` pour un couple
  /// catégorie d'élément (ou `null` pour Outbound/Inbound autonomes), section
  /// architecturale et rôle de prompt.
  static String kindFor(
    BuildDesignItemKind? itemKind,
    BuildTechStackSection section,
    BuildHexaPromptRole role,
  ) => PromptYamlHeaderBuilder.kindFor(itemKind, section, role);

  /// Extrait le contenu YAML brut de l'en-tête ```` ```yaml ... ``` ```` situé
  /// au début de [promptMarkdown], ou `null` s'il est absent.
  static String? extractYamlHeader(String promptMarkdown) =>
      PromptYamlHeaderBuilder.extractYamlHeader(promptMarkdown);

  /// Génère les groupes de prompts pour chaque élément de [selectedItems] dans [domain],
  /// suivis en fin de liste par les groupes autonomes **Outbound** et **Inbound**
  /// (lorsque [includeDomainAdapters] vaut `true`).
  static List<BuildItemPromptGroup> generateGroups({
    required FunctionalDomain domain,
    required List<BuildDesignItem> selectedItems,
    DomainCatalog? catalog,
    BuildTechStackProfile? techStack,
    CompanyGlossary? glossary,
    BusinessObjectModelPreferences? modelPreferences,
    DateTime? referenceDate,
    bool includeDomainAdapters = true,
  }) {
    final dates = PromptYamlHeaderBuilder.resolveMetadataDates(
      domain: domain,
      catalog: catalog,
      referenceDate: referenceDate,
    );
    final effectiveStack = techStack ?? catalog?.techStackForDomain(domain);
    final groups = <BuildItemPromptGroup>[];
    for (final item in selectedItems) {
      final prompts = switch (item.kind) {
        BuildDesignItemKind.model => _buildModelPrompts(
          domain: domain,
          item: item,
          catalog: catalog,
          dates: dates,
          techStack: effectiveStack,
          glossary: glossary,
          modelPreferences: modelPreferences,
        ),
        BuildDesignItemKind.useCase => _buildUseCasePrompts(
          domain: domain,
          item: item,
          dates: dates,
          techStack: effectiveStack,
          glossary: glossary,
          modelPreferences: modelPreferences,
        ),
        BuildDesignItemKind.saga => _buildSagaPrompts(
          domain: domain,
          item: item,
          dates: dates,
          techStack: effectiveStack,
          glossary: glossary,
        ),
      };
      if (prompts.isNotEmpty) {
        groups.add(BuildItemPromptGroup(item: item, prompts: prompts));
      }
    }
    if (includeDomainAdapters) {
      groups.add(
        BuildItemPromptGroup.standalone(
          section: BuildTechStackSection.outbound,
          subtitle: 'Adaptateurs sortants hors persistance (messaging, logger, clients)',
          domainCode: domain.domainCode,
          prompts: <BuildHexaPromptSpec>[
            buildDomainOutboundImplementationPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
              glossary: glossary,
              modelPreferences: modelPreferences,
            ),
            buildDomainOutboundUnitTestPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
            ),
          ],
        ),
      );
      groups.add(
        BuildItemPromptGroup.standalone(
          section: BuildTechStackSection.inbound,
          subtitle: 'Points d’entrée entrants (contrôleurs, DTOs, consumers, guards)',
          domainCode: domain.domainCode,
          prompts: <BuildHexaPromptSpec>[
            buildDomainInboundImplementationPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
              glossary: glossary,
              modelPreferences: modelPreferences,
            ),
            buildDomainInboundUnitTestPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
            ),
          ],
        ),
      );
      groups.add(
        BuildItemPromptGroup.standalone(
          section: BuildTechStackSection.boilerplate,
          kindLabel: 'Socle & Outillage',
          subtitle: 'Bootstrap applicatif, configuration, logger et helpers partagés',
          domainCode: domain.domainCode,
          prompts: <BuildHexaPromptSpec>[
            buildDomainBoilerplateImplementationPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
              glossary: glossary,
              modelPreferences: modelPreferences,
            ),
            buildDomainBoilerplateUnitTestPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
            ),
          ],
        ),
      );
      groups.add(
        BuildItemPromptGroup.standalone(
          section: BuildTechStackSection.devTools,
          kindLabel: 'Socle & Outillage',
          subtitle: 'Compilateur strict, linter, frontières hexagonales, runner et CI',
          domainCode: domain.domainCode,
          prompts: <BuildHexaPromptSpec>[
            buildDomainDevToolsImplementationPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
              glossary: glossary,
              modelPreferences: modelPreferences,
            ),
            buildDomainDevToolsUnitTestPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
            ),
          ],
        ),
      );
      groups.add(
        BuildItemPromptGroup.standalone(
          section: BuildTechStackSection.checkIntegration,
          kindLabel: 'Validation',
          subtitle: 'Câblage DI complet, harnesses et vérification d’intégration globale',
          domainCode: domain.domainCode,
          prompts: <BuildHexaPromptSpec>[
            buildDomainCheckIntegrationImplementationPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
              glossary: glossary,
              modelPreferences: modelPreferences,
            ),
            buildDomainCheckIntegrationUnitTestPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
            ),
          ],
        ),
      );
    }
    return groups;
  }

  /// Concatène une sélection de [prompts] en un document Markdown unique prêt
  /// à être exécuté.
  static String combinePromptsMarkdown({
    required FunctionalDomain domain,
    required Iterable<BuildHexaPromptSpec> prompts,
  }) {
    final list = prompts.toList(growable: false);
    if (list.isEmpty) return '';
    if (list.length == 1) return list.single.promptMarkdown;

    final buf = StringBuffer()
      ..writeln(
        '# Plan d’implémentation — Architecture Hexagonale (${domain.name})',
      )
      ..writeln()
      ..writeln(
        'Exécute séquentiellement les **${list.length} prompts** ci-dessous pour le domaine **`${domain.domainCode}`** (**${domain.name}**), en respectant strictement l’isolation des couches **Domain → Application → Infrastructure (Ports & Adapters)** et la validation des tests à chaque étape.',
      )
      ..writeln();

    for (var i = 0; i < list.length; i++) {
      final prompt = list[i];
      buf
        ..writeln('---')
        ..writeln()
        ..writeln(
          '<!-- Étape ${i + 1}/${list.length} : ${prompt.targetLabel} · ${prompt.section.label} — ${prompt.role.label} -->',
        )
        ..writeln(prompt.promptMarkdown.trimRight())
        ..writeln();
    }
    return SpecStorageIo.normalizeLf(buf.toString());
  }

  static List<BuildHexaPromptSpec> _buildModelPrompts({
    required FunctionalDomain domain,
    required BuildDesignItem item,
    DomainCatalog? catalog,
    required PromptMetadataDates dates,
    BuildTechStackProfile? techStack,
    CompanyGlossary? glossary,
    BusinessObjectModelPreferences? modelPreferences,
  }) {
    final ctx = ModelPromptContext.resolve(
      domain: domain,
      item: item,
      catalog: catalog,
      modelPreferences: modelPreferences,
    );
    return <BuildHexaPromptSpec>[
      buildModelImplementationPrompt(
        ctx: ctx,
        dates: dates,
        techStack: techStack,
        glossary: glossary,
        modelPreferences: modelPreferences,
      ),
      buildModelUnitTestPrompt(
        ctx: ctx,
        dates: dates,
        techStack: techStack,
      ),
      buildModelPersistencePrompt(
        ctx: ctx,
        dates: dates,
        techStack: techStack,
        modelPreferences: modelPreferences,
      ),
      buildModelPersistenceUnitTestPrompt(
        ctx: ctx,
        dates: dates,
        techStack: techStack,
      ),
    ];
  }

  static List<BuildHexaPromptSpec> _buildUseCasePrompts({
    required FunctionalDomain domain,
    required BuildDesignItem item,
    required PromptMetadataDates dates,
    BuildTechStackProfile? techStack,
    CompanyGlossary? glossary,
    BusinessObjectModelPreferences? modelPreferences,
  }) {
    final existing = domain.useCaseOrchestration?.useCases
        .where((uc) => uc.id == item.id)
        .firstOrNull;
    final useCase =
        existing ??
        ApplicationUseCaseSpec(
          id: item.id,
          code: item.primaryBadge.isNotEmpty ? item.primaryBadge : 'UC-001',
          name: item.name,
          title: item.subtitle,
          version: item.version,
          boundedContext: item.groupName,
        );

    return <BuildHexaPromptSpec>[
      buildUseCaseImplementationPrompt(
        domain: domain,
        item: item,
        useCase: useCase,
        dates: dates,
        techStack: techStack,
        glossary: glossary,
        modelPreferences: modelPreferences,
      ),
      buildUseCaseUnitTestPrompt(
        domain: domain,
        item: item,
        useCase: useCase,
        dates: dates,
        techStack: techStack,
      ),
    ];
  }

  static List<BuildHexaPromptSpec> _buildSagaPrompts({
    required FunctionalDomain domain,
    required BuildDesignItem item,
    required PromptMetadataDates dates,
    BuildTechStackProfile? techStack,
    CompanyGlossary? glossary,
  }) {
    final existing = domain.useCaseOrchestration?.sagas
        .where((s) => s.id == item.id)
        .firstOrNull;
    final saga =
        existing ??
        OrchestrationSagaSpec(
          id: item.id,
          code: item.primaryBadge.isNotEmpty ? item.primaryBadge : 'SAGA-001',
          name: item.name,
          title: item.subtitle,
          version: item.version,
        );

    return <BuildHexaPromptSpec>[
      buildSagaImplementationPrompt(
        domain: domain,
        item: item,
        saga: saga,
        dates: dates,
        techStack: techStack,
        glossary: glossary,
      ),
      buildSagaUnitTestPrompt(
        domain: domain,
        item: item,
        saga: saga,
        dates: dates,
        techStack: techStack,
      ),
    ];
  }
}
