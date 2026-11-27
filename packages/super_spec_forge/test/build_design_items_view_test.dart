import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/main.dart';
import 'package:super_spec_forge/super_spec_forge.dart';
import 'package:yaml/yaml.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_build_items_store'));

  SpecForgeProject? activeProject;

  @override
  Future<void> saveProject(SpecForgeProject project) async {
    activeProject = project;
  }

  @override
  Future<SpecForgeProject?> loadProject(String projectId) async =>
      activeProject?.id == projectId ? activeProject : null;

  @override
  Future<void> deleteProject(String projectId) async {
    if (activeProject?.id == projectId) activeProject = null;
  }

  @override
  Future<List<SpecProjectSummary>> listProjects() async => const [];

  @override
  Future<String?> getLastActiveProjectId() async => activeProject?.id;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {}
}

class _MemoryDomainCatalogStore extends DomainCatalogStore {
  _MemoryDomainCatalogStore([DomainCatalog? initial])
    : _catalog = initial ?? DomainCatalog.empty,
      super(Directory('memory_build_items_store'));

  DomainCatalog _catalog;

  @override
  Future<DomainCatalog> load() async => _catalog;

  @override
  Future<void> save(DomainCatalog catalog) async {
    catalog.validate();
    _catalog = catalog;
  }
}

class _MemoryCompanyGlossaryStore extends CompanyGlossaryStore {
  _MemoryCompanyGlossaryStore() : super(Directory('memory_build_items_store'));

  @override
  Future<CompanyGlossary> loadGlossary() async => CompanyGlossary.empty;

  @override
  Future<void> saveGlossary(CompanyGlossary glossary) async {}

  @override
  Future<List<SpecChatMessage>> loadChatMessages() async => const [];

  @override
  Future<void> saveChatMessages(List<SpecChatMessage> messages) async {}
}

class _MemoryModelDictionaryStore extends ModelDictionaryStore {
  _MemoryModelDictionaryStore() : super(Directory('memory_build_items_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemoryEnterpriseRateCardStore extends EnterpriseRateCardStore {
  _MemoryEnterpriseRateCardStore()
    : super(Directory('memory_build_items_store'));

  @override
  Future<EnterpriseRateCard> load() async => EnterpriseRateCard.defaults;

  @override
  Future<void> save(EnterpriseRateCard rateCard) async {}
}

class _NoopSpecAiService implements SpecAiService {
  @override
  Future<void> warmUp(
    SpecForgeStage stage, {
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
  }) async {}

  @override
  Stream<GeminiStreamEvent> streamTurn({
    required SpecForgeStage stage,
    required String prompt,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
    List<Map<String, Object?>>? conversationContents,
    bool enforceJsonResponse = true,
    String? systemInstructionOverride,
    String? staticGuideOverride,
  }) => const Stream<GeminiStreamEvent>.empty();
}

FunctionalDomain _buildBillingDomain() {
  var contracts = DomainContracts.parse(
    'models:\n'
    '  Invoice: model\n'
    'components:\n'
    '  MoneyAmount: component\n'
    'dto:\n'
    '  CreateInvoiceRequest: createxdto\n'
    'message:\n'
    '  InvoiceIssuedEvent: eventxpayloaddto\n',
  );
  final invoiceNode = contracts.groups[0].children.single;
  final moneyNode = contracts.groups[1].children.single;
  contracts = contracts.edit(
    invoiceNode,
    invoiceNode.type,
    ContractDetails(
      title: 'Facture client',
      version: '1.2.0',
      states: const <ContractStage, ContractStatus>{
        ContractStage.design: ContractStatus.done,
        ContractStage.validation: ContractStatus.inProgress,
      },
    ),
  );
  contracts = contracts.withModel(
    moneyNode.id,
    object: BusinessObjectSpec(
      id: moneyNode.id,
      name: 'Montant monétaire',
      technicalName: 'MoneyAmount',
      attributes: <BusinessAttribute>[
        BusinessAttribute(
          id: 'attr_currency',
          name: 'currency',
          type: BusinessAttributeType.enumeration,
          enumValues: const <String>['EUR', 'USD'],
          required: true,
        ),
        BusinessAttribute(
          id: 'attr_val',
          name: 'value',
          type: BusinessAttributeType.number,
          required: true,
        ),
      ],
    ),
  );
  contracts = contracts.withModel(
    invoiceNode.id,
    object: BusinessObjectSpec(
      id: invoiceNode.id,
      name: 'Facture client',
      technicalName: 'Invoice',
      aggregateRoot: true,
      attributes: <BusinessAttribute>[
        BusinessAttribute(
          id: 'attr_amount',
          name: 'totalAmount',
          type: BusinessAttributeType.number,
          required: true,
          constraints: '> 0',
          schemaConstraints: JsonSchemaConstraints(exclusiveMinimum: 0),
        ),
        BusinessAttribute(
          id: 'attr_money_ref',
          name: 'amountDetail',
          type: BusinessAttributeType.reference,
          referenceObjectId: moneyNode.id,
          required: true,
        ),
      ],
    ),
  );
  contracts = contracts.withDomainLayer(
    invoiceNode.id,
    layer: HexagonalDomainLayerSpec(
      invariants: <DomainInvariantSpec>[
        DomainInvariantSpec(
          id: 'inv_1',
          code: 'INV-001',
          title: 'Montant strictement positif',
          expression: 'totalAmount > 0',
          violationError: 'InvalidInvoiceAmountError',
        ),
      ],
      persistencePolicy: DomainPersistencePolicySpec(
        repositoryPortName: 'InvoiceRepository',
        concurrencyStrategy: DomainConcurrencyStrategy.optimisticVersion,
        deletionStrategy: DomainDeletionStrategy.softDelete,
      ),
    ),
  );

  final orchestration = UseCaseOrchestrationSpec(
    useCases: <ApplicationUseCaseSpec>[
      ApplicationUseCaseSpec(
        id: 'uc_issue_invoice',
        code: 'UC-001',
        name: 'IssueInvoice',
        title: 'Émettre une facture',
        version: '2.1.0',
        boundedContext: 'Facturation',
        cqrsType: UseCaseCqrsType.command,
        inboundPort: 'IssueInvoiceUseCase',
        outboundPorts: const <String>['InvoiceRepository'],
        triggerInputs: const <UseCaseFieldSpec>[
          UseCaseFieldSpec(name: 'invoiceId', type: 'uuid', required: true),
          UseCaseFieldSpec(
            name: 'amount',
            type: 'number',
            constraints: '> 0',
            required: true,
          ),
          UseCaseFieldSpec(
            name: 'lines',
            type: 'object',
            isArray: true,
            required: true,
            children: <UseCaseFieldSpec>[
              UseCaseFieldSpec(name: 'sku', type: 'string', required: true),
              UseCaseFieldSpec(name: 'qty', type: 'integer', required: true),
            ],
          ),
          UseCaseFieldSpec(
            name: 'note',
            type: 'string',
            nullable: true,
            required: false,
          ),
        ],
        outputs: const <UseCaseFieldSpec>[
          UseCaseFieldSpec(
            name: 'invoiceNumber',
            type: 'string',
            required: true,
          ),
          UseCaseFieldSpec(
            name: 'status',
            type: 'enumeration',
            enumValues: <String>['ISSUED', 'PENDING'],
            required: true,
          ),
        ],
        scenarios: <UseCaseScenarioSpec>[
          UseCaseScenarioSpec(
            id: 'scn_1',
            name: 'Émission nominale',
            given: const <String>['Un client actif'],
            when: const <String>['IssueInvoice est exécuté'],
            then: const <String>['La facture est créée et publiée'],
          ),
        ],
        states: const <ContractStage, ContractStatus>{
          ContractStage.design: ContractStatus.done,
          ContractStage.code: ContractStatus.inProgress,
        },
      ),
    ],
    sagas: <OrchestrationSagaSpec>[
      OrchestrationSagaSpec(
        id: 'saga_invoice_settlement',
        code: 'SAGA-001',
        name: 'InvoiceSettlementSaga',
        title: 'Règlement facture',
        version: '0.4.2',
        boundedContexts: const <String>['Facturation', 'Paiement'],
        coordinationMode: SagaCoordinationMode.orchestration,
        correlationKey: 'invoiceId',
        mermaidDiagram: 'sequenceDiagram\n  Facturation->>Paiement: charge()',
        compensationMatrix: const <SagaCompensationRow>[
          SagaCompensationRow(
            id: 'comp_1',
            step: '1. Réservation crédit',
            nominalAction: 'reserveCredit()',
            compensationAction: 'releaseCredit()',
            rollbackTrigger: 'PaymentRejected',
          ),
        ],
        states: const <ContractStage, ContractStatus>{
          ContractStage.design: ContractStatus.inProgress,
        },
      ),
    ],
  );

  return FunctionalDomain(
    id: 'dom_billing',
    domainCode: 'billing',
    name: 'Facturation',
    contracts: contracts,
    useCaseOrchestration: orchestration,
  );
}

FunctionalDomain _buildLogisticsDomain() {
  final contracts = DomainContracts.parse(
    'models:\n'
    '  Shipment: model\n'
    'components:\n'
    'dto:\n'
    'message:\n',
  );
  return FunctionalDomain(
    id: 'dom_logistics',
    domainCode: 'logistics',
    name: 'Logistique',
    contracts: contracts,
  );
}

SpecForgeController _createController([DomainCatalog? catalog]) =>
    SpecForgeController(
      store: _MemorySpecProjectStore(),
      domainCatalogStore: _MemoryDomainCatalogStore(catalog),
      glossaryStore: _MemoryCompanyGlossaryStore(),
      modelDictionaryStore: _MemoryModelDictionaryStore(),
      enterpriseRateCardStore: _MemoryEnterpriseRateCardStore(),
      aiService: _NoopSpecAiService(),
    );

void main() {
  group('BuildDomainDesignItems — projection et filtres', () {
    test('extrait toutes les entrées de DomainContracts, les Use Cases et les Sagas avec leurs états', () {
      final domain = _buildBillingDomain();
      final projection = BuildDomainDesignItems.fromDomain(domain);

      expect(projection.domainId, 'dom_billing');
      expect(projection.models, hasLength(4));
      expect(
        projection.models.map((m) => '${m.name}:${m.primaryBadge}'),
        containsAll(<String>[
          'Invoice:model',
          'MoneyAmount:component',
          'CreateInvoiceRequest:createxdto',
          'InvoiceIssuedEvent:eventxpayloaddto',
        ]),
      );

      final invoice = projection.models.firstWhere((m) => m.name == 'Invoice');
      expect(invoice.subtitle, 'Facture client');
      expect(invoice.secondaryBadge, 'v1.2.0');
      expect(invoice.statusOf(ContractStage.design), ContractStatus.done);
      expect(
        invoice.statusOf(ContractStage.validation),
        ContractStatus.inProgress,
      );
      expect(invoice.statusOf(ContractStage.code), ContractStatus.pending);

      expect(projection.useCases, hasLength(1));
      expect(projection.useCases.single.name, 'IssueInvoice');
      expect(projection.useCases.single.version, '2.1.0');
      expect(projection.useCases.single.primaryBadge, 'UC-001');
      expect(projection.useCases.single.secondaryBadge, 'Command · v2.1.0');
      expect(
        projection.useCases.single.statusOf(ContractStage.code),
        ContractStatus.inProgress,
      );

      expect(projection.sagas, hasLength(1));
      expect(projection.sagas.single.name, 'InvoiceSettlementSaga');
      expect(projection.sagas.single.version, '0.4.2');
      expect(projection.sagas.single.primaryBadge, 'SAGA-001');
      expect(projection.sagas.single.secondaryBadge, 'Orchestration · v0.4.2');
      expect(
        projection.sagas.single.statusOf(ContractStage.design),
        ContractStatus.inProgress,
      );
    });

    test('filtre par texte, catégorie, étape et statut d’avancement', () {
      final projection = BuildDomainDesignItems.fromDomain(
        _buildBillingDomain(),
      );

      expect(
        projection.filterItems(
          BuildDesignItemKind.model,
          query: 'facture client',
        ),
        hasLength(1),
      );
      expect(
        projection.filterItems(
          BuildDesignItemKind.model,
          kindFilter: BuildDesignItemKind.saga,
        ),
        isEmpty,
      );
      expect(
        projection.filterItems(
          BuildDesignItemKind.useCase,
          stageFilter: ContractStage.code,
          statusFilter: ContractStatus.inProgress,
        ),
        hasLength(1),
      );
      expect(
        projection.filterItems(
          BuildDesignItemKind.model,
          stageFilter: ContractStage.code,
        ),
        isEmpty,
      );
      expect(
        projection.filterItems(
          BuildDesignItemKind.model,
          statusFilter: ContractStatus.done,
        ),
        hasLength(1),
      );
    });

    test(
      'BuildHexaPromptGenerator génère 4 prompts pour un Modèle, 2 pour Use Case / Saga et 2x6 autonomes Outbound / Inbound / Boilerplate / Dev Tools / Check Integration / Playground',
      () {
      final domain = _buildBillingDomain();
      final projection = BuildDomainDesignItems.fromDomain(domain);
      final invoiceItem = projection.models.firstWhere(
        (m) => m.name == 'Invoice',
      );
      final useCaseItem = projection.useCases.single;
      final sagaItem = projection.sagas.single;

      final catalog = DomainCatalog(
        domains: <FunctionalDomain>[domain],
        auditLog: <AuditLogEntry>[
          AuditLogEntry(
            id: 'aud_1',
            recordedAt: DateTime.utc(2026, 3, 10),
            actorUsername: 'architect',
            domainId: domain.id,
            actionType: DomainAuditAction.create,
            details: 'Création Facturation',
          ),
        ],
        updatedAt: DateTime.utc(2026, 11, 24),
      );

      final groups = BuildHexaPromptGenerator.generateGroups(
        domain: domain,
        selectedItems: <BuildDesignItem>[invoiceItem, useCaseItem, sagaItem],
        catalog: catalog,
      );

      expect(groups, hasLength(9));
      expect(groups[3].standaloneSection, BuildTechStackSection.outbound);
      expect(groups[3].item, isNull);
      expect(groups[4].standaloneSection, BuildTechStackSection.inbound);
      expect(groups[4].item, isNull);
      expect(groups[5].standaloneSection, BuildTechStackSection.boilerplate);
      expect(groups[5].item, isNull);
      expect(groups[6].standaloneSection, BuildTechStackSection.devTools);
      expect(groups[6].item, isNull);
      expect(groups[7].standaloneSection, BuildTechStackSection.checkIntegration);
      expect(groups[7].item, isNull);
      expect(groups[8].standaloneSection, BuildTechStackSection.playground);
      expect(groups[8].item, isNull);

      // Vérifie la validité YAML et le schéma d'en-tête sur les 20 variantes de prompts.
      final allGenerated = groups.expand((g) => g.prompts).toList();
      expect(allGenerated, hasLength(20));
      expect(
        allGenerated.map((p) {
          final rawYaml = BuildHexaPromptGenerator.extractYamlHeader(
            p.promptMarkdown,
          );
          expect(rawYaml, isNotNull);
          expect(p.promptMarkdown.startsWith('```yaml\nkind: '), isTrue);
          final parsed = loadYaml(rawYaml!) as YamlMap;
          expect(parsed['domain'], 'billing');
          expect(parsed['owner'], 'billing-team');
          expect(parsed['status'], 'approved');
          expect((parsed['description'] as String).trim(), isNotEmpty);
          expect((parsed['tags'] as YamlList), isNotEmpty);
          expect(parsed['security']['classification'], 'internal');
          expect(parsed['ai']['searchable'], isTrue);
          expect(parsed['ai']['embeddable'], isTrue);
          expect(parsed['generation']['architecture'], 'hexagonal');
          expect(parsed['generation']['targetAgent'], isNull);
          expect(parsed['metadata']['created'], '2026-03-10');
          expect(parsed['metadata']['updated'], '2026-11-24');
          return '${parsed['kind']}@${parsed['version']}';
        }),
        equals(const <String>[
          'model-implementation@1.2.0',
          'model-unit-test@1.2.0',
          'model-persistence-implementation@1.2.0',
          'model-persistence-unit-test@1.2.0',
          'usecase-implementation@2.1.0',
          'usecase-unit-test@2.1.0',
          'saga-implementation@0.4.2',
          'saga-unit-test@0.4.2',
          'outbound-implementation@1.0.0',
          'outbound-unit-test@1.0.0',
          'inbound-implementation@1.0.0',
          'inbound-unit-test@1.0.0',
          'boilerplate-implementation@1.0.0',
          'boilerplate-unit-test@1.0.0',
          'dev-tools-implementation@1.0.0',
          'dev-tools-unit-test@1.0.0',
          'check-integration-implementation@1.0.0',
          'check-integration-unit-test@1.0.0',
          'playground-implementation@1.0.0',
          'playground-unit-test@1.0.0',
        ]),
      );

      final persistenceYaml = loadYaml(
        BuildHexaPromptGenerator.extractYamlHeader(
          groups[0].prompts[2].promptMarkdown,
        )!,
      ) as YamlMap;
      expect(persistenceYaml['name'], 'invoice-persistence-implementation');
      expect(persistenceYaml['generation']['layer'], 'infrastructure');
      expect(
        persistenceYaml['generation']['repositoryPort'],
        'InvoiceRepository',
      );

      List<Map<String, Object?>> extractJsonBlocks(String markdown) {
        final matches = RegExp(r'```json\n([\s\S]*?)\n```')
            .allMatches(markdown);
        return [
          for (final m in matches)
            (jsonDecode(m.group(1)!) as Map<String, Object?>),
        ];
      }

      // Modèle : Domain (Impl + TU) + Persistance (Impl + TU) intègrent tous le JSON Schema
      // Draft 2020-12 avec résolution des références (MoneyAmount), sans puces texte.
      expect(
        groups[0].prompts.map((p) => (p.section, p.role)),
        equals(const <(BuildTechStackSection, BuildHexaPromptRole)>[
          (BuildTechStackSection.domain, BuildHexaPromptRole.implementation),
          (BuildTechStackSection.domain, BuildHexaPromptRole.unitTest),
          (
            BuildTechStackSection.persistence,
            BuildHexaPromptRole.implementation,
          ),
          (BuildTechStackSection.persistence, BuildHexaPromptRole.unitTest),
        ]),
      );
      for (final modelPrompt in groups[0].prompts) {
        expect(
          modelPrompt.promptMarkdown,
          isNot(contains('- `totalAmount` :')),
        );
        final blocks = extractJsonBlocks(modelPrompt.promptMarkdown);
        expect(blocks, hasLength(1));
        final schema = blocks.single;
        expect(
          schema[r'$schema'],
          'https://json-schema.org/draft/2020-12/schema',
        );
        expect(schema['title'], 'Invoice');
        expect(schema['type'], 'object');
        expect(
          schema['required'],
          containsAll(<String>['totalAmount', 'amountDetail']),
        );
        final props = schema['properties'] as Map<String, Object?>;
        final totalAmount = props['totalAmount'] as Map<String, Object?>;
        expect(totalAmount['type'], 'number');
        expect(totalAmount['exclusiveMinimum'], 0);
        final amountDetail = props['amountDetail'] as Map<String, Object?>;
        expect(amountDetail['x-reference'], 'MoneyAmount');
        final resolvedProps =
            amountDetail['properties'] as Map<String, Object?>;
        expect(
          (resolvedProps['currency'] as Map<String, Object?>)['enum'],
          equals(const <String>['EUR', 'USD']),
        );
      }
      expect(
        groups[0].prompts[0].promptMarkdown,
        allOf(contains('Architecture Hexagonale'), contains('INV-001')),
      );
      expect(
        groups[0].prompts[1].promptMarkdown,
        contains('InvalidInvoiceAmountError'),
      );
      expect(
        groups[0].prompts[2].promptMarkdown,
        allOf(
          contains('InvoiceRepository'),
          contains('Verrouillage optimiste'),
          contains('Suppression logique'),
        ),
      );
      expect(
        groups[0].prompts[3].promptMarkdown,
        allOf(contains('Tests Unitaires Persistance'), contains('InvoiceRepository')),
      );

      // Use Case : Implémentation contient les JSON Schemas stricts Input & Output + Tests unitaires.
      expect(
        groups[1].prompts.map((p) => p.role),
        equals(const <BuildHexaPromptRole>[
          BuildHexaPromptRole.implementation,
          BuildHexaPromptRole.unitTest,
        ]),
      );
      final ucImplMd = groups[1].prompts[0].promptMarkdown;
      expect(
        ucImplMd,
        allOf(
          contains('IssueInvoiceUseCase'),
          contains('InvoiceRepository'),
          isNot(contains('- `invoiceId` :')),
          isNot(contains('- `invoiceNumber` :')),
        ),
      );
      final ucSchemas = extractJsonBlocks(ucImplMd);
      expect(ucSchemas, hasLength(2));

      final inputSchema = ucSchemas[0];
      expect(
        inputSchema[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema',
      );
      expect(inputSchema['title'], 'IssueInvoiceInput');
      expect(inputSchema['additionalProperties'], isFalse);
      expect(
        inputSchema['required'],
        equals(const <String>['invoiceId', 'amount', 'lines']),
      );
      final inProps = inputSchema['properties'] as Map<String, Object?>;
      expect((inProps['invoiceId'] as Map<String, Object?>)['format'], 'uuid');
      expect(
        (inProps['amount'] as Map<String, Object?>)['exclusiveMinimum'],
        0,
      );
      expect(
        (inProps['note'] as Map<String, Object?>)['type'],
        equals(const <String>['string', 'null']),
      );
      final linesSchema = inProps['lines'] as Map<String, Object?>;
      expect(linesSchema['type'], 'array');
      final lineItems = linesSchema['items'] as Map<String, Object?>;
      expect(lineItems['additionalProperties'], isFalse);
      expect(lineItems['required'], equals(const <String>['sku', 'qty']));

      final outputSchema = ucSchemas[1];
      expect(outputSchema['title'], 'IssueInvoiceOutput');
      expect(outputSchema['additionalProperties'], isFalse);
      expect(
        outputSchema['required'],
        equals(const <String>['invoiceNumber', 'status']),
      );
      final outProps = outputSchema['properties'] as Map<String, Object?>;
      expect(
        (outProps['status'] as Map<String, Object?>)['enum'],
        equals(const <String>['ISSUED', 'PENDING']),
      );

      expect(
        groups[1].prompts[1].promptMarkdown,
        contains('Émission nominale'),
      );

      // Saga : Implémentation + Tests unitaires (sans persistance).
      expect(
        groups[2].prompts.map((p) => p.role),
        equals(const <BuildHexaPromptRole>[
          BuildHexaPromptRole.implementation,
          BuildHexaPromptRole.unitTest,
        ]),
      );
      expect(
        groups[2].prompts[0].promptMarkdown,
        allOf(contains('sequenceDiagram'), contains('releaseCredit()')),
      );
      expect(groups[2].prompts[1].promptMarkdown, contains('PaymentRejected'));

      // Outbound & Inbound (autonomes en fin de liste).
      expect(
        groups[3].prompts.map((p) => (p.section, p.role)),
        equals(const <(BuildTechStackSection, BuildHexaPromptRole)>[
          (BuildTechStackSection.outbound, BuildHexaPromptRole.implementation),
          (BuildTechStackSection.outbound, BuildHexaPromptRole.unitTest),
        ]),
      );
      expect(
        groups[3].prompts[0].promptMarkdown,
        contains('InvoiceIssuedEvent'),
      );
      expect(
        groups[4].prompts.map((p) => (p.section, p.role)),
        equals(const <(BuildTechStackSection, BuildHexaPromptRole)>[
          (BuildTechStackSection.inbound, BuildHexaPromptRole.implementation),
          (BuildTechStackSection.inbound, BuildHexaPromptRole.unitTest),
        ]),
      );
      expect(
        groups[4].prompts[0].promptMarkdown,
        allOf(contains('IssueInvoiceUseCase'), contains('CreateInvoiceRequest')),
      );
      expect(
        groups[5].prompts.map((p) => (p.section, p.role)),
        equals(const <(BuildTechStackSection, BuildHexaPromptRole)>[
          (BuildTechStackSection.boilerplate, BuildHexaPromptRole.implementation),
          (BuildTechStackSection.boilerplate, BuildHexaPromptRole.unitTest),
        ]),
      );
      expect(
        groups[6].prompts.map((p) => (p.section, p.role)),
        equals(const <(BuildTechStackSection, BuildHexaPromptRole)>[
          (BuildTechStackSection.devTools, BuildHexaPromptRole.implementation),
          (BuildTechStackSection.devTools, BuildHexaPromptRole.unitTest),
        ]),
      );
      expect(
        groups[7].prompts.map((p) => (p.section, p.role)),
        equals(const <(BuildTechStackSection, BuildHexaPromptRole)>[
          (
            BuildTechStackSection.checkIntegration,
            BuildHexaPromptRole.implementation,
          ),
          (
            BuildTechStackSection.checkIntegration,
            BuildHexaPromptRole.unitTest,
          ),
        ]),
      );
      expect(
        groups[7].prompts[0].promptMarkdown,
        contains('4 modèle(s)/contrat(s), 1 cas d’usage et 1 saga(s)'),
      );
      expect(
        groups[8].prompts.map((p) => (p.section, p.role)),
        equals(const <(BuildTechStackSection, BuildHexaPromptRole)>[
          (BuildTechStackSection.playground, BuildHexaPromptRole.implementation),
          (BuildTechStackSection.playground, BuildHexaPromptRole.unitTest),
        ]),
      );
      expect(
        groups[8].prompts[0].promptMarkdown,
        contains('Playground'),
      );

      final combined = BuildHexaPromptGenerator.combinePromptsMarkdown(
        domain: domain,
        prompts: groups.expand((g) => g.prompts),
      );
      expect(combined, contains('20 prompts'));
      expect(combined, contains('Étape 1/20'));
      expect(combined, contains('Étape 20/20'));
    });
  });

  testWidgets(
    'Build : état vide sans domaine et redirection vers Gestion des domaines',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = _createController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-build-menu-view')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('build-link-agentic_prompts')));
      await tester.pumpAndSettle();

      expect(find.text('Ajoutez un domaine pour commencer.'), findsOneWidget);
      final manageBtn = find.byKey(const ValueKey('build-manage-domains-btn'));
      expect(manageBtn, findsOneWidget);

      await tester.tap(manageBtn);
      await tester.pumpAndSettle();

      expect(find.text('Design › Gestion des domaines'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('domain-manage-tech-stacks-btn')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Build : sélection par domaine, sections repliables, filtres et cycle persisté des 4 indicateurs',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final billing = _buildBillingDomain();
      final logistics = _buildLogisticsDomain();
      final controller = _createController(
        DomainCatalog(domains: <FunctionalDomain>[billing, logistics]),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('build-link-agentic_prompts')));
      await tester.pumpAndSettle();

      // Vérifie l'affichage des 3 sections du premier domaine (Facturation).
      expect(find.text('Modèles & Contrats (4)'), findsOneWidget);
      expect(find.text('Cas d’usage (1)'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('build-section-header-saga')),
          matching: find.text('Sagas (1)'),
        ),
        findsOneWidget,
      );
      expect(find.text('Invoice'), findsOneWidget);
      expect(find.text('CreateInvoiceRequest'), findsOneWidget);
      expect(find.text('IssueInvoice'), findsOneWidget);
      expect(find.text('InvoiceSettlementSaga'), findsOneWidget);

      // Repli puis dépli de la section Modèles & Contrats.
      await tester.tap(
        find.byKey(const ValueKey('build-section-header-model')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Invoice'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('build-section-header-model')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Invoice'), findsOneWidget);

      // Le bouton « Sélection des Prompts IA » est désactivé tant qu'aucun item n'est coché.
      final nextPromptsBtn = find.byKey(
        const ValueKey('build-next-prompts-btn'),
      );
      expect(nextPromptsBtn, findsOneWidget);
      expect(tester.widget<FilledButton>(nextPromptsBtn).onPressed, isNull);

      // Cycle direct d'un indicateur sur un Modèle (Code : pending -> inProgress -> done)
      // sans basculer la sélection multiple de la carte parente.
      final invoiceNodeId = billing.contracts!.groups[0].children.single.id;
      final invoiceCodePhase = find.byKey(
        ValueKey('build-item-phase-model-$invoiceNodeId-code'),
      );
      await tester.tap(invoiceCodePhase);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(nextPromptsBtn).onPressed, isNull);

      var savedBilling = controller.domainCatalog.domains.firstWhere(
        (d) => d.id == 'dom_billing',
      );
      expect(
        savedBilling.contracts!.details[invoiceNodeId]!.states[ContractStage
            .code],
        ContractStatus.inProgress,
      );
      expect(savedBilling.contracts!.source, billing.contracts!.source);

      await tester.tap(invoiceCodePhase);
      await tester.pumpAndSettle();
      savedBilling = controller.domainCatalog.domains.firstWhere(
        (d) => d.id == 'dom_billing',
      );
      expect(
        savedBilling.contracts!.details[invoiceNodeId]!.states[ContractStage
            .code],
        ContractStatus.done,
      );

      // Cycle direct d'un indicateur sur un Use Case et sur une Saga.
      await tester.tap(
        find.byKey(
          const ValueKey('build-item-phase-useCase-uc_issue_invoice-delivery'),
        ),
      );
      await tester.pumpAndSettle();
      final sagaValidationPhase = find.byKey(
        const ValueKey(
          'build-item-phase-saga-saga_invoice_settlement-validation',
        ),
      );
      await tester.ensureVisible(sagaValidationPhase);
      await tester.pumpAndSettle();
      await tester.tap(sagaValidationPhase);
      await tester.pumpAndSettle();

      savedBilling = controller.domainCatalog.domains.firstWhere(
        (d) => d.id == 'dom_billing',
      );
      expect(
        savedBilling.useCaseOrchestration!.useCases.single.states[ContractStage
            .delivery],
        ContractStatus.inProgress,
      );
      expect(
        savedBilling.useCaseOrchestration!.sagas.single.states[ContractStage
            .validation],
        ContractStatus.inProgress,
      );

      // Recherche texte et réinitialisation des filtres.
      await tester.enterText(
        find.byKey(const ValueKey('build-search-field')),
        'Settlement',
      );
      await tester.pumpAndSettle();
      expect(find.text('InvoiceSettlementSaga'), findsOneWidget);
      expect(find.text('Invoice'), findsNothing);
      expect(find.text('IssueInvoice'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('build-filter-reset-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Invoice'), findsOneWidget);

      // Sélection multiple : 1 Modèle + 1 Use Case + 1 Saga -> active « Sélection des Prompts IA (3) ».
      String? lastClipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>;
            lastClipboardText = args['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final invoiceCard = find.byKey(ValueKey('build-item-model-$invoiceNodeId'));
      await tester.ensureVisible(invoiceCard);
      await tester.pumpAndSettle();
      await tester.tap(invoiceCard);
      await tester.pumpAndSettle();
      final useCaseCard = find.byKey(
        const ValueKey('build-item-useCase-uc_issue_invoice'),
      );
      await tester.ensureVisible(useCaseCard);
      await tester.pumpAndSettle();
      await tester.tap(useCaseCard);
      await tester.pumpAndSettle();
      final sagaCard = find.byKey(
        const ValueKey('build-item-saga-saga_invoice_settlement'),
      );
      await tester.ensureVisible(sagaCard);
      await tester.pumpAndSettle();
      await tester.tap(sagaCard);
      await tester.pumpAndSettle();

      expect(find.text('Sélection des Prompts IA (3)'), findsOneWidget);

      // Ouvre la nouvelle page « Sélection des Prompts IA » avec fil d'Ariane et bouton retour AppBar.
      await tester.tap(nextPromptsBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('build-prompts-selection-page')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('build-prompts-crumb')), findsOneWidget);
      expect(
        find.text(
          'Build › ${BuildLinksView.agenticPromptsLabel} › Sélection des Prompts IA',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
        findsOneWidget,
      );

      // Regroupement par élément sélectionné : 4 prompts pour Invoice, 2 pour IssueInvoice,
      // 2 pour Saga (cochés par défaut = 8) + 2x6 groupes autonomes décochés par défaut = 20 prompts.
      expect(find.text('8 / 20 prompt(s) · 9 groupe(s)'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            'build-prompt-card-model:$invoiceNodeId:domain:implementation',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey('build-prompt-card-model:$invoiceNodeId:domain:unitTest'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey(
            'build-prompt-card-model:$invoiceNodeId:persistence:implementation',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey(
            'build-prompt-card-model:$invoiceNodeId:persistence:unitTest',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'build-prompt-card-useCase:uc_issue_invoice:persistence:implementation',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey(
            'build-prompt-card-saga:saga_invoice_settlement:persistence:implementation',
          ),
        ),
        findsNothing,
      );

      // Décoche 1 prompt puis copie les 7 prompts sélectionnés.
      await tester.tap(
        find.byKey(
          ValueKey('build-prompt-check-model:$invoiceNodeId:domain:unitTest'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('7 / 20 prompt(s) · 9 groupe(s)'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('build-copy-selected-prompts-btn')),
      );
      await tester.pumpAndSettle();
      expect(find.text('7 prompt(s) copié(s)'), findsOneWidget);
      expect(lastClipboardText, isNotNull);
      expect(lastClipboardText, contains('7 prompts'));
      expect(lastClipboardText, contains('InvoiceRepository'));

      // Vérifie que les groupes autonomes Outbound, Inbound, Boilerplate, Dev Tools,
      // Check Integration et Playground sont présents en bas de la liste et désactivés par défaut.
      final promptsScrollable = find.descendant(
        of: find.byKey(const ValueKey('build-prompts-selection-page')),
        matching: find.byType(Scrollable),
      );
      for (final sectionName in const <String>[
        'outbound',
        'inbound',
        'boilerplate',
        'devTools',
        'checkIntegration',
        'playground',
      ]) {
        final groupKey = ValueKey('build-prompt-group-standalone-$sectionName');
        await tester.scrollUntilVisible(
          find.byKey(groupKey),
          400,
          scrollable: promptsScrollable,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(groupKey), findsOneWidget);

        for (final roleName in const <String>['implementation', 'unitTest']) {
          final checkFinder = find.byKey(
            ValueKey('build-prompt-check-standalone:$sectionName:$roleName'),
          );
          await tester.scrollUntilVisible(
            checkFinder,
            200,
            scrollable: promptsScrollable,
          );
          await tester.pumpAndSettle();
          expect(tester.widget<Checkbox>(checkFinder).value, isFalse);
        }
      }

      // Retour au niveau 0 via le segment parent du fil d'Ariane -> conserve la sélection (3).
      await tester.tap(find.byKey(const ValueKey('build-items-crumb')));
      await tester.pumpAndSettle();
      expect(find.text('Sélection des Prompts IA (3)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
        findsOneWidget,
      );

      // Changement de domaine via le fil d'Ariane -> synchronise activeDesignDomainId.
      await tester.tap(find.byKey(const ValueKey('build-domain-crumb')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('design-domain-option-dom_logistics')),
      );
      await tester.pumpAndSettle();

      expect(controller.activeDesignDomainId, 'dom_logistics');
      expect(find.text('Shipment'), findsOneWidget);
      expect(find.text('Invoice'), findsNothing);
    },
  );

  test('BuildHexaPromptGenerator injecte la stack technique du domaine dans le YAML et en fin de chaque prompt', () {
    final billing = _buildBillingDomain().copyWith(
      techStackId: BuildTechStackProfile.defaultTsNestJsId,
    );
    final catalog = DomainCatalog(domains: <FunctionalDomain>[billing]);
    final projection = BuildDomainDesignItems.fromDomain(billing);
    final invoiceItem = projection.models.firstWhere(
      (m) => m.name == 'Invoice',
    );
    final useCaseItem = projection.useCases.single;
    final sagaItem = projection.sagas.single;

    final groups = BuildHexaPromptGenerator.generateGroups(
      domain: billing,
      selectedItems: <BuildDesignItem>[invoiceItem, useCaseItem, sagaItem],
      catalog: catalog,
    );

    final allPrompts = groups.expand((g) => g.prompts).toList();
    expect(allPrompts, hasLength(20));

    for (final prompt in allPrompts) {
      final rawYaml = BuildHexaPromptGenerator.extractYamlHeader(
        prompt.promptMarkdown,
      );
      final parsed = loadYaml(rawYaml!) as YamlMap;
      expect(parsed['generation']['stack'], 'ts-nestjs');
      expect(parsed['tags'], contains('ts-nestjs'));

      expect(
        prompt.promptMarkdown,
        contains(
          '## Extension Stack Technique & Structure des Dossiers (TypeScript / NestJS)',
        ),
      );
      expect(prompt.promptMarkdown, contains('### Stack technique'));
      expect(
        prompt.promptMarkdown,
        contains('### Structure des dossiers cible'),
      );
      expect(prompt.promptMarkdown, contains('billing'));
      expect(prompt.promptMarkdown, isNot(contains('{{domain}}')));
      expect(prompt.promptMarkdown, isNot(contains('{{module}}')));
      final hasPresetExtension = BuildTechStackProfile.tsNestJsPreset
          .extensionFor(
            prompt.section,
            prompt.role == BuildHexaPromptRole.implementation
                ? BuildTechStackSubRole.implementation
                : BuildTechStackSubRole.unitTest,
          )
          .isNotEmpty;
      if (hasPresetExtension) {
        expect(
          prompt.promptMarkdown,
          contains(
            '### Consignes spécifiques — ${prompt.section.label} (${prompt.role.label})',
          ),
        );
      } else {
        expect(
          prompt.promptMarkdown,
          isNot(
            contains(
              '### Consignes spécifiques — ${prompt.section.label} (${prompt.role.label})',
            ),
          ),
        );
      }

      // La section Documentation IA doit être présente tout à la fin de chaque prompt.
      final extIdx = prompt.promptMarkdown.indexOf(
        '## Extension Stack Technique & Structure des Dossiers',
      );
      final docIdx = prompt.promptMarkdown.indexOf('## Documentation IA');
      expect(docIdx, greaterThan(extIdx));
      expect(
        prompt.promptMarkdown,
        allOf(
          contains('## Mise à jour obligatoire de la documentation IA du projet'),
          contains('du module `billing`'),
        ),
      );

      switch ((prompt.section, prompt.role)) {
        case (BuildTechStackSection.domain, BuildHexaPromptRole.implementation):
          expect(
            prompt.promptMarkdown,
            contains('src/\n└── core/                # Domaine pur (DDD)\n    └── billing/'),
          );
          expect(
            prompt.promptMarkdown,
            allOf(
              contains('# Contraintes techniques :'),
              contains('# MODE STRICT - CONTRAINTES BLOQUANTES'),
              contains('src/core/billing/'),
              contains('Neverthrow'),
            ),
          );
        case (BuildTechStackSection.domain, BuildHexaPromptRole.unitTest):
          expect(
            prompt.promptMarkdown,
            contains('identique au domaine principal'),
          );
          expect(
            prompt.promptMarkdown,
            allOf(
              contains('CONTRAINTES TESTS OBLIGATOIRES'),
              contains('npm: test:domain'),
              contains('domain/models/**/*.spec.ts'),
              contains('@ai-modification-guide'),
            ),
          );
        case (BuildTechStackSection.useCaseSaga, BuildHexaPromptRole.implementation):
          expect(
            prompt.promptMarkdown,
            contains('src/\n└── core/\n    └── billing/\n        ├── ports/\n'),
          );
          expect(
            prompt.promptMarkdown,
            allOf(
              contains('src/core/billing/application/'),
              contains('UnitOfWorkPort.runInTransaction()'),
              contains('ApplicationEventPublisherPort.publish()'),
              contains('CommandDispatcherPort.dispatch()'),
              contains('application/commands/'),
              contains('@collaborators'),
            ),
          );
        case (BuildTechStackSection.useCaseSaga, BuildHexaPromptRole.unitTest):
          expect(
            prompt.promptMarkdown,
            contains('src/\n└── core/\n    └── billing/\n        └── application/'),
          );
          expect(
            prompt.promptMarkdown,
            allOf(
              contains('CONTRAINTES TESTS OBLIGATOIRES'),
              contains('src/core/billing/application/**/*.spec.ts'),
              contains('npm: test:usecase'),
              contains('@coverage'),
              contains('compensationMatrix'),
            ),
          );
        case (BuildTechStackSection.outbound, BuildHexaPromptRole.implementation):
          expect(
            prompt.promptMarkdown,
            allOf(
              contains('└── outbound/'),
              contains('external-api/'),
              contains('avro/'),
              contains('storage/'),
              contains('Anti-Corruption Layer'),
              contains('core/billing/ports/'),
              contains('AdapterImpl'),
            ),
          );
        case (BuildTechStackSection.outbound, BuildHexaPromptRole.unitTest):
          expect(
            prompt.promptMarkdown,
            contains('identique au domaine principal'),
          );
        case (BuildTechStackSection.inbound, BuildHexaPromptRole.implementation):
          expect(
            prompt.promptMarkdown,
            allOf(
              contains('└── inbound/'),
              contains('dto-in/'),
              contains('dto-out/'),
              contains('route_style: restful'),
              contains('RESTful API Design Guidelines'),
              contains('DTO → Command → Handler → Domain → Response'),
            ),
          );
        case (BuildTechStackSection.inbound, BuildHexaPromptRole.unitTest):
          expect(prompt.promptMarkdown, contains('└── inbound/'));
        case (BuildTechStackSection.persistence, BuildHexaPromptRole.implementation):
          expect(
            prompt.promptMarkdown,
            contains('src/\n└── infrastructure/\n    └── billing/'),
          );
          expect(
            prompt.promptMarkdown,
            allOf(
              contains('billing.module.ts'),
              contains('SCHÉMA MONGOOSE & INDEXATION'),
              contains('core/billing/ports/repositories'),
              contains('src/infrastructure/billing/outbound/persistence/repositories/'),
              contains('error.code === 11000'),
              contains('@collaborators'),
            ),
          );
        case (BuildTechStackSection.persistence, BuildHexaPromptRole.unitTest):
          expect(
            prompt.promptMarkdown,
            contains('identique au domaine principal'),
          );
        case (BuildTechStackSection.boilerplate, BuildHexaPromptRole.implementation):
          expect(prompt.promptMarkdown, contains('├── main.ts'));
          expect(
            prompt.promptMarkdown,
            allOf(
              contains('Fastify comme adapter HTTP'),
              contains('nestjs-pino'),
              contains('x-correlation-id'),
              contains('emitDecoratorMetadata'),
              contains(r'MONGODB_DB_NAME=$currentApp'),
            ),
          );
        case (BuildTechStackSection.boilerplate, BuildHexaPromptRole.unitTest):
          expect(prompt.promptMarkdown, contains('└── shared/'));
        case (BuildTechStackSection.devTools, BuildHexaPromptRole.implementation):
          expect(
            prompt.promptMarkdown,
            allOf(
              contains('eslint.config.mjs'),
              contains('`typecheck`, `lint`'),
              contains('docker/mongo'),
              contains('docker/pubsub'),
              contains('pubsub-emulator-ui'),
            ),
          );
        case (BuildTechStackSection.devTools, BuildHexaPromptRole.unitTest):
          expect(prompt.promptMarkdown, contains('└── architecture/'));
        case (
          BuildTechStackSection.checkIntegration,
          BuildHexaPromptRole.implementation,
        ):
          expect(
            prompt.promptMarkdown,
            allOf(
              contains('└── integration/'),
              contains('billing.module.ts'),
              contains('MongooseModule.forRoot'),
              contains('SchemaFactory.createForClass'),
              contains('LoggerModule'),
              contains('emitDecoratorMetadata'),
              contains('*.probe.ts'),
            ),
          );
        case (
          BuildTechStackSection.checkIntegration,
          BuildHexaPromptRole.unitTest,
        ):
          expect(prompt.promptMarkdown, contains('└── e2e/'));
          expect(prompt.promptMarkdown, contains('batterie de vérification complète'));
        case (
          BuildTechStackSection.playground,
          BuildHexaPromptRole.implementation,
        ):
          expect(
            prompt.promptMarkdown,
            contains(
              'src/\n'
              '└── infrastructure/\n'
              '    └── billing/\n'
              '        └── playground/',
            ),
          );
        case (BuildTechStackSection.playground, BuildHexaPromptRole.unitTest):
          expect(prompt.promptMarkdown, contains('test/billing/playground/'));
      }
    }

    // Lorsque des consignes Playground personnalisées sont configurées, elles sont injectées.
    final customPlaygroundStack = BuildTechStackProfile.tsNestJsPreset.copyWith(
      playgroundImplementationExtension:
          '- Générer un script `playground/billing/demo.ts` exécutable via `tsx`.',
    );
    final customPlaygroundGroups = BuildHexaPromptGenerator.generateGroups(
      domain: billing,
      selectedItems: const <BuildDesignItem>[],
      techStack: customPlaygroundStack,
    );
    final playgroundImplPrompt = customPlaygroundGroups
        .firstWhere((g) => g.standaloneSection == BuildTechStackSection.playground)
        .prompts
        .first;
    expect(
      playgroundImplPrompt.promptMarkdown,
      allOf(
        contains('### Consignes spécifiques — Playground (Implémentation)'),
        contains('playground/billing/demo.ts'),
      ),
    );

    // Sans stack affectée au domaine, aucune section d'extension, aucune Documentation IA ni generation.stack.
    final withoutStack = _buildBillingDomain();
    final noStackGroups = BuildHexaPromptGenerator.generateGroups(
      domain: withoutStack,
      selectedItems: <BuildDesignItem>[invoiceItem],
      catalog: DomainCatalog(domains: <FunctionalDomain>[withoutStack]),
    );
    expect(noStackGroups, hasLength(7));
    final noStackPrompt = noStackGroups.first.prompts.first;
    final noStackYaml = loadYaml(
      BuildHexaPromptGenerator.extractYamlHeader(noStackPrompt.promptMarkdown)!,
    ) as YamlMap;
    expect(noStackYaml['generation']['stack'], isNull);
    expect(
      noStackPrompt.promptMarkdown,
      isNot(contains('## Extension Stack Technique & Structure des Dossiers')),
    );
    expect(
      noStackPrompt.promptMarkdown,
      isNot(contains('## Documentation IA')),
    );
  });

  testWidgets(
    'Build : création d’une stack personnalisée, affectation au domaine et injection dans les prompts',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final billing = _buildBillingDomain();
      final controller = _createController(
        DomainCatalog(domains: <FunctionalDomain>[billing]),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      String? lastClipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>;
            lastClipboardText = args['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();

      // Ouvre la page dédiée « Gestion des Stack technique » depuis le menu Build.
      expect(
        find.byKey(const ValueKey('spec-forge-build-menu-view')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('build-link-tech_stacks')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('build-tech-stacks-view')),
        findsOneWidget,
      );
      expect(
        find.text('Build › ${BuildLinksView.techStacksLabel}'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('tech-stack-add-btn')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('tech-stack-code-field')),
        'java-spring',
      );
      await tester.enterText(
        find.byKey(const ValueKey('tech-stack-name-field')),
        'Java 21 / Spring Boot',
      );
      await tester.enterText(
        find.byKey(const ValueKey('tech-stack-technical-field')),
        '- Java 21 · Spring Boot 3 · JPA · JUnit 5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('tech-stack-ai-documentation-field')),
        '- Mettre à jour `docs/architecture.md` pour `{{domain}}`.',
      );

      // Onglet Domain (renommé depuis Implémentation) -> sous-onglet Implémentation.
      expect(
        find.byKey(const ValueKey('tech-stack-tab-domain')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-tab-useCaseSaga')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-tab-outbound')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-tab-inbound')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-tab-persistence')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-tab-boilerplate')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-tab-devTools')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-tab-checkIntegration')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-tab-playground')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('tech-stack-tab-useCaseSaga')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const ValueKey(
            'tech-stack-folders-useCaseSaga-implementation-field',
          ),
        ),
        'src/main/java/com/acme/{{domain}}/application/',
      );
      await tester.enterText(
        find.byKey(
          const ValueKey('tech-stack-ext-useCaseSaga-implementation-field'),
        ),
        '- Utilise des records Java pour les Commands/Queries.',
      );

      // Sous-onglet Test unitaire sous UseCase / Saga.
      await tester.tap(
        find.byKey(
          const ValueKey('tech-stack-subtab-useCaseSaga-unitTest'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const ValueKey('tech-stack-folders-useCaseSaga-unitTest-field'),
        ),
        'src/test/java/com/acme/{{domain}}/application/',
      );
      await tester.enterText(
        find.byKey(
          const ValueKey('tech-stack-ext-useCaseSaga-unitTest-field'),
        ),
        '- Utilise JUnit 5 avec fakes en mémoire.',
      );

      await tester.tap(find.byKey(const ValueKey('tech-stack-save-btn')));
      await tester.pumpAndSettle();
      expect(
        controller.domainCatalog.techStacks.any((s) => s.code == 'java-spring'),
        isTrue,
      );

      // Revient au menu Build via l'AppBar puis ouvre « Génération des prompts agentiques ».
      await tester.tap(find.byKey(const ValueKey('spec-forge-appbar-back-btn')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-build-menu-view')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('build-link-agentic_prompts')));
      await tester.pumpAndSettle();

      // Sélectionne la nouvelle stack pour le domaine Facturation.
      await tester.tap(
        find.byKey(const ValueKey('build-domain-stack-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Java 21 / Spring Boot').last);
      await tester.pumpAndSettle();

      final savedDomain = controller.domainCatalog.domains.single;
      expect(
        controller.domainCatalog.techStackForDomain(savedDomain)?.code,
        'java-spring',
      );

      // Sélectionne le Use Case et passe à « Sélection des Prompts IA ».
      await tester.tap(
        find.byKey(const ValueKey('build-item-useCase-uc_issue_invoice')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('build-next-prompts-btn')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('build-copy-selected-prompts-btn')),
      );
      await tester.pumpAndSettle();

      expect(lastClipboardText, isNotNull);
      expect(lastClipboardText, contains('stack: java-spring'));
      expect(
        lastClipboardText,
        contains(
          '## Extension Stack Technique & Structure des Dossiers (Java 21 / Spring Boot)',
        ),
      );
      expect(
        lastClipboardText,
        contains('src/main/java/com/acme/billing/application/'),
      );
      expect(
        lastClipboardText,
        contains('src/test/java/com/acme/billing/application/'),
      );
      expect(
        lastClipboardText,
        contains('Utilise des records Java pour les Commands/Queries.'),
      );
      expect(
        lastClipboardText,
        contains('Utilise JUnit 5 avec fakes en mémoire.'),
      );
      expect(
        lastClipboardText,
        contains('## Documentation IA'),
      );
      expect(
        lastClipboardText,
        contains('Mettre à jour `docs/architecture.md` pour `billing`.'),
      );
    },
  );

  testWidgets(
    'Build : bannière 1-clic sur domaine sans stack et affectation par défaut à la création',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final billing = _buildBillingDomain();
      final controller = _createController(
        DomainCatalog(domains: <FunctionalDomain>[billing]),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      // Un nouveau domaine créé via le contrôleur reçoit automatiquement la stack par défaut.
      final created = await controller.createFunctionalDomain(
        domainCode: 'orders',
        name: 'Commandes',
      );
      expect(created.techStackId, BuildTechStackProfile.defaultTsNestJsId);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('build-link-agentic_prompts')));
      await tester.pumpAndSettle();

      // Sélectionne un item de Facturation (encore sans stack) puis ouvre Prompts IA.
      await tester.tap(
        find.byKey(const ValueKey('build-item-useCase-uc_issue_invoice')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('build-next-prompts-btn')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('build-prompts-no-stack-banner')),
        findsOneWidget,
      );

      // Un clic applique la stack par défaut et injecte immédiatement la section en fin de prompt.
      await tester.tap(
        find.byKey(const ValueKey('build-prompts-apply-default-stack-btn')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('build-prompts-no-stack-banner')),
        findsNothing,
      );
      final updatedBilling = controller.domainCatalog.domains.firstWhere(
        (d) => d.id == 'dom_billing',
      );
      expect(
        updatedBilling.techStackId,
        BuildTechStackProfile.defaultTsNestJsId,
      );

      // Ouvre le prompt d'implémentation pour vérifier la section injectée en fin de prompt.
      await tester.tap(
        find.byKey(
          const ValueKey(
            'build-prompt-expand-useCase:uc_issue_invoice:useCaseSaga:implementation',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('## Extension Stack Technique & Structure des Dossiers'),
        findsOneWidget,
      );
      expect(
        find.textContaining('## Documentation IA'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Build : éditeur de stack technique bascule entre aperçu Markdown des règles et édition',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final billing = _buildBillingDomain().copyWith(
        techStackId: BuildTechStackProfile.defaultTsNestJsId,
      );
      final controller = _createController(
        DomainCatalog(domains: <FunctionalDomain>[billing]),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('build-link-tech_stacks')));
      await tester.pumpAndSettle();

      // À l'ouverture d'une stack existante, l'aperçu Markdown est actif par défaut.
      expect(
        find.byKey(const ValueKey('tech-stack-mode-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-technical-preview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-ai-documentation-preview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tech-stack-technical-field')),
        findsNothing,
      );

      // Passe sur l'onglet Domain pour vérifier l'aperçu Markdown des consignes.
      await tester.tap(find.byKey(const ValueKey('tech-stack-tab-domain')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('tech-stack-ext-domain-implementation-preview'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('tech-stack-ext-domain-implementation-field'),
        ),
        findsNothing,
      );

      // Bascule en mode Édition et modifie les consignes Markdown.
      await tester.tap(find.text('Édition'));
      await tester.pumpAndSettle();
      final domainExtField = find.byKey(
        const ValueKey('tech-stack-ext-domain-implementation-field'),
      );
      expect(domainExtField, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('tech-stack-ext-domain-implementation-preview'),
        ),
        findsNothing,
      );

      await tester.enterText(
        domainExtField,
        '## Règle customisée\n- Toujours valider via `create()`.',
      );
      await tester.pumpAndSettle();

      // Rebascule en mode Aperçu : le Markdown rendu reflète la modification en direct.
      await tester.tap(find.text('Aperçu'));
      await tester.pumpAndSettle();
      final previewFinder = find.byKey(
        const ValueKey('tech-stack-ext-domain-implementation-preview'),
      );
      expect(previewFinder, findsOneWidget);
      expect(
        find.descendant(
          of: previewFinder,
          matching: find.textContaining('Règle customisée', findRichText: true),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Build : bouton apps de l’AppBar depuis Sélection des Prompts IA ramène directement au menu Build',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final billing = _buildBillingDomain();
      final controller = _createController(
        DomainCatalog(domains: <FunctionalDomain>[billing]),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-appbar-menu-btn')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('build-link-agentic_prompts')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('build-item-useCase-uc_issue_invoice')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('build-next-prompts-btn')));
      await tester.pumpAndSettle();

      final backFinder = find.byKey(const ValueKey('spec-forge-appbar-back-btn'));
      final menuFinder = find.byKey(const ValueKey('spec-forge-appbar-menu-btn'));
      expect(backFinder, findsOneWidget);
      expect(menuFinder, findsOneWidget);
      expect(
        tester.getTopRight(backFinder).dx,
        lessThanOrEqualTo(tester.getTopLeft(menuFinder).dx),
      );

      await tester.tap(menuFinder);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-build-menu-view')),
        findsOneWidget,
      );
      expect(backFinder, findsNothing);
      expect(menuFinder, findsNothing);
    },
  );

  testWidgets(
    'Build : éditeur de stack technique affiche des boutons de navigation sur écran étroit pour atteindre les onglets masqués',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1050, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final billing = _buildBillingDomain();
      final controller = _createController(
        DomainCatalog(domains: <FunctionalDomain>[billing]),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BuildTechStacksView(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      final leftBtn = find.byKey(
        const ValueKey('tech-stack-tabs-scroll-left-btn'),
      );
      final rightBtn = find.byKey(
        const ValueKey('tech-stack-tabs-scroll-right-btn'),
      );
      final menuBtn = find.byKey(const ValueKey('tech-stack-tabs-menu-btn'));

      expect(leftBtn, findsOneWidget);
      expect(rightBtn, findsOneWidget);
      expect(menuBtn, findsOneWidget);
      expect(tester.widget<IconButton>(leftBtn).onPressed, isNull);
      expect(tester.widget<IconButton>(rightBtn).onPressed, isNotNull);

      // Le bouton droit fait défiler les onglets vers la droite et active le bouton gauche.
      await tester.tap(rightBtn);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(leftBtn).onPressed, isNotNull);

      // Le menu complet permet de sauter directement sur l'onglet Playground.
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();
      final playgroundIndex = BuildTechStackSection.values.length;
      await tester.tap(
        find.byKey(ValueKey('tech-stack-tabs-menu-item-$playgroundIndex')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('tech-stack-folders-playground-implementation-field'),
        ),
        findsOneWidget,
      );

      // Sur écran large où tous les onglets tiennent, les boutons d'overflow sont masqués.
      await tester.binding.setSurfaceSize(const Size(2400, 900));
      await tester.pumpAndSettle();
      expect(leftBtn, findsNothing);
      expect(rightBtn, findsNothing);
      expect(menuBtn, findsNothing);
    },
  );
}
