/// Orchestrateur de génération de prompts IA en Architecture Hexagonale
/// ([BuildHexaPromptGenerator]), déléguant chaque type de prompt au module
/// dédié sous `prompt_generator/`.
library;

import '../../models/build_design_item.dart';
import '../../models/build_tech_stack_profile.dart';
import '../../models/business_object_model_preferences.dart';
import '../../models/business_object_spec.dart';
import '../../models/company_glossary.dart';
import '../../models/domain_catalog.dart';
import '../../models/domain_iteration_snapshot.dart';
import '../../models/usecase_orchestration_spec.dart';
import '../../models/value_object_spec.dart';
import '../design_evolution_analyzer.dart';
import '../spec_storage_slug.dart';
import 'prompt_generator/domain_boilerplate_prompt_builders.dart';
import 'prompt_generator/domain_check_integration_prompt_builders.dart';
import 'prompt_generator/domain_dev_tools_prompt_builders.dart';
import 'prompt_generator/domain_inbound_prompt_builders.dart';
import 'prompt_generator/domain_outbound_prompt_builders.dart';
import 'prompt_generator/domain_playground_prompt_builders.dart';
import 'prompt_generator/model_implementation_prompt_builder.dart';
import 'prompt_generator/model_persistence_prompt_builder.dart';
import 'prompt_generator/model_persistence_unit_test_prompt_builder.dart';
import 'prompt_generator/model_prompt_context.dart';
import 'prompt_generator/model_unit_test_prompt_builder.dart';
import 'prompt_generator/prompt_evolution_sections.dart';
import 'prompt_generator/prompt_generator_models.dart';
import 'prompt_generator/prompt_yaml_header_builder.dart';
import 'prompt_generator/saga_implementation_prompt_builder.dart';
import 'prompt_generator/saga_unit_test_prompt_builder.dart';
import 'prompt_generator/usecase_implementation_prompt_builder.dart';
import 'prompt_generator/usecase_unit_test_prompt_builder.dart';
import 'prompt_generator/value_object_implementation_prompt_builder.dart';
import 'prompt_generator/value_object_unit_test_prompt_builder.dart';

export 'prompt_generator/prompt_evolution_sections.dart';
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
    BuildPromptGenerationMode mode = BuildPromptGenerationMode.autoByBaseline,
    DomainIterationSnapshot? baselineOverride,
    DomainEvolutionReport? evolutionReport,
  }) {
    final dates = PromptYamlHeaderBuilder.resolveMetadataDates(
      domain: domain,
      catalog: catalog,
      referenceDate: referenceDate,
    );
    final effectiveCatalog = _synchronizeDomainInCatalog(domain, catalog);
    final effectiveStack =
        techStack ?? effectiveCatalog?.techStackForDomain(domain);
    final effectiveBaseline =
        baselineOverride ??
        evolutionReport?.baseline ??
        domain.activeBaselineSnapshot;
    final effectiveEvolution =
        (mode == BuildPromptGenerationMode.fullFromScratch ||
            effectiveBaseline == null)
        ? null
        : (evolutionReport ??
              DesignEvolutionAnalyzer.analyzeDomain(
                domain: domain,
                catalog: effectiveCatalog,
                baselineOverride: baselineOverride,
              ));

    final groups = <BuildItemPromptGroup>[];
    for (final item in selectedItems) {
      final prompts = switch (item.kind) {
        BuildDesignItemKind.valueObject => _buildValueObjectPrompts(
          domain: domain,
          item: item,
          catalog: effectiveCatalog,
          dates: dates,
          techStack: effectiveStack,
          glossary: glossary,
          modelPreferences: modelPreferences,
          mode: mode,
          evolutionReport: effectiveEvolution,
        ),
        BuildDesignItemKind.model => _buildModelPrompts(
          domain: domain,
          item: item,
          catalog: effectiveCatalog,
          dates: dates,
          techStack: effectiveStack,
          glossary: glossary,
          modelPreferences: modelPreferences,
          mode: mode,
          evolutionReport: effectiveEvolution,
        ),
        BuildDesignItemKind.useCase => _buildUseCasePrompts(
          domain: domain,
          item: item,
          dates: dates,
          techStack: effectiveStack,
          glossary: glossary,
          modelPreferences: modelPreferences,
          mode: mode,
          evolutionReport: effectiveEvolution,
        ),
        BuildDesignItemKind.saga => _buildSagaPrompts(
          domain: domain,
          item: item,
          dates: dates,
          techStack: effectiveStack,
          glossary: glossary,
          mode: mode,
          evolutionReport: effectiveEvolution,
        ),
      };
      if (prompts.isNotEmpty) {
        groups.add(BuildItemPromptGroup(item: item, prompts: prompts));
      }
    }
    if (includeDomainAdapters) {
      final adapterDecision =
          PromptEvolutionSections.resolveDomainAdapterDecision(
            mode: mode,
            evolutionReport: effectiveEvolution,
          );
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
              evolutionDecision: adapterDecision,
            ),
            buildDomainOutboundUnitTestPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
              evolutionDecision: adapterDecision,
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
              evolutionDecision: adapterDecision,
            ),
            buildDomainInboundUnitTestPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
              evolutionDecision: adapterDecision,
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
              evolutionDecision: adapterDecision,
            ),
            buildDomainCheckIntegrationUnitTestPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
              evolutionDecision: adapterDecision,
            ),
          ],
        ),
      );
      groups.add(
        BuildItemPromptGroup.standalone(
          section: BuildTechStackSection.playground,
          kindLabel: 'Bac à sable',
          subtitle:
              'Bac à sable local d’expérimentation, scripts de démo et essais manuels',
          domainCode: domain.domainCode,
          prompts: <BuildHexaPromptSpec>[
            buildDomainPlaygroundImplementationPrompt(
              domain: domain,
              dates: dates,
              techStack: effectiveStack,
              glossary: glossary,
              modelPreferences: modelPreferences,
            ),
            buildDomainPlaygroundUnitTestPrompt(
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

  static DomainCatalog? _synchronizeDomainInCatalog(
    FunctionalDomain domain,
    DomainCatalog? catalog,
  ) {
    if (catalog == null) return null;
    if (catalog.domains.any((d) => d.id == domain.id && identical(d, domain))) {
      return catalog;
    }
    return catalog.copyWith(
      domains: <FunctionalDomain>[
        for (final existing in catalog.domains)
          if (existing.id != domain.id) existing,
        domain,
      ],
    );
  }

  static List<ResolvedValueObject> _resolveVisibleValueObjects(
    FunctionalDomain domain,
    DomainCatalog? catalog,
  ) {
    final resolved = <ResolvedValueObject>[];
    final seenTechNames = <String>{};
    for (final vo in domain.valueObjects) {
      seenTechNames.add(vo.technicalName.toLowerCase());
      resolved.add(
        ResolvedValueObject(
          spec: vo,
          scope: ValueObjectScope.domain,
          domainId: domain.id,
        ),
      );
    }
    if (catalog != null) {
      for (final vo in catalog.sharedValueObjects) {
        if (seenTechNames.add(vo.technicalName.toLowerCase())) {
          resolved.add(
            ResolvedValueObject(spec: vo, scope: ValueObjectScope.shared),
          );
        }
      }
    }
    return List<ResolvedValueObject>.unmodifiable(resolved);
  }

  static List<BuildHexaPromptSpec> _buildValueObjectPrompts({
    required FunctionalDomain domain,
    required BuildDesignItem item,
    DomainCatalog? catalog,
    required PromptMetadataDates dates,
    BuildTechStackProfile? techStack,
    CompanyGlossary? glossary,
    BusinessObjectModelPreferences? modelPreferences,
    required BuildPromptGenerationMode mode,
    DomainEvolutionReport? evolutionReport,
  }) {
    final availableVos = _resolveVisibleValueObjects(domain, catalog);
    final resolved =
        availableVos.where((r) => r.spec.id == item.id).firstOrNull ??
        availableVos
            .where(
              (r) =>
                  r.spec.technicalName.toLowerCase() == item.name.toLowerCase(),
            )
            .firstOrNull;
    final effectiveScope =
        resolved?.scope ?? item.valueObjectScope ?? ValueObjectScope.domain;
    final effectiveVo =
        resolved?.spec ??
        ValueObjectSpec(
          id: item.id,
          technicalName: BusinessAttribute.isValidDslIdentifier(item.name)
              ? item.name
              : BusinessAttribute.toPascalCaseDslIdentifier(item.name),
          name: item.subtitle.isNotEmpty ? item.subtitle : item.name,
          version: ValueObjectSpec.versionPattern.hasMatch(item.version)
              ? item.version
              : '1.0.0',
        );
    final decision = PromptEvolutionSections.resolveArtifactDecision(
      mode: mode,
      item: item,
      currentVersion: effectiveVo.version,
      evolutionReport: evolutionReport,
    );

    return <BuildHexaPromptSpec>[
      buildValueObjectImplementationPrompt(
        domain: domain,
        item: item,
        valueObject: effectiveVo,
        scope: effectiveScope,
        availableValueObjects: availableVos,
        dates: dates,
        techStack: techStack,
        glossary: glossary,
        modelPreferences: modelPreferences,
        evolutionDecision: decision,
      ),
      buildValueObjectUnitTestPrompt(
        domain: domain,
        item: item,
        valueObject: effectiveVo,
        scope: effectiveScope,
        availableValueObjects: availableVos,
        dates: dates,
        techStack: techStack,
        modelPreferences: modelPreferences,
        evolutionDecision: decision,
      ),
    ];
  }

  static List<BuildHexaPromptSpec> _buildModelPrompts({
    required FunctionalDomain domain,
    required BuildDesignItem item,
    DomainCatalog? catalog,
    required PromptMetadataDates dates,
    BuildTechStackProfile? techStack,
    CompanyGlossary? glossary,
    BusinessObjectModelPreferences? modelPreferences,
    required BuildPromptGenerationMode mode,
    DomainEvolutionReport? evolutionReport,
  }) {
    final ctx = ModelPromptContext.resolve(
      domain: domain,
      item: item,
      catalog: catalog,
      modelPreferences: modelPreferences,
    );
    final decision = PromptEvolutionSections.resolveArtifactDecision(
      mode: mode,
      item: item,
      currentVersion: ctx.detail.version,
      evolutionReport: evolutionReport,
    );
    return <BuildHexaPromptSpec>[
      buildModelImplementationPrompt(
        ctx: ctx,
        dates: dates,
        techStack: techStack,
        glossary: glossary,
        modelPreferences: modelPreferences,
        evolutionDecision: decision,
      ),
      buildModelUnitTestPrompt(
        ctx: ctx,
        dates: dates,
        techStack: techStack,
        evolutionDecision: decision,
      ),
      buildModelPersistencePrompt(
        ctx: ctx,
        dates: dates,
        techStack: techStack,
        modelPreferences: modelPreferences,
        evolutionDecision: decision,
      ),
      buildModelPersistenceUnitTestPrompt(
        ctx: ctx,
        dates: dates,
        techStack: techStack,
        evolutionDecision: decision,
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
    required BuildPromptGenerationMode mode,
    DomainEvolutionReport? evolutionReport,
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
    final decision = PromptEvolutionSections.resolveArtifactDecision(
      mode: mode,
      item: item,
      currentVersion: useCase.version,
      evolutionReport: evolutionReport,
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
        evolutionDecision: decision,
      ),
      buildUseCaseUnitTestPrompt(
        domain: domain,
        item: item,
        useCase: useCase,
        dates: dates,
        techStack: techStack,
        evolutionDecision: decision,
      ),
    ];
  }

  static List<BuildHexaPromptSpec> _buildSagaPrompts({
    required FunctionalDomain domain,
    required BuildDesignItem item,
    required PromptMetadataDates dates,
    BuildTechStackProfile? techStack,
    CompanyGlossary? glossary,
    required BuildPromptGenerationMode mode,
    DomainEvolutionReport? evolutionReport,
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
    final decision = PromptEvolutionSections.resolveArtifactDecision(
      mode: mode,
      item: item,
      currentVersion: saga.version,
      evolutionReport: evolutionReport,
    );

    return <BuildHexaPromptSpec>[
      buildSagaImplementationPrompt(
        domain: domain,
        item: item,
        saga: saga,
        dates: dates,
        techStack: techStack,
        glossary: glossary,
        evolutionDecision: decision,
      ),
      buildSagaUnitTestPrompt(
        domain: domain,
        item: item,
        saga: saga,
        dates: dates,
        techStack: techStack,
        evolutionDecision: decision,
      ),
    ];
  }
}
