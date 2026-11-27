import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _TempSpecProjectStore extends SpecProjectStore {
  _TempSpecProjectStore(super.rootDirectory);

  @override
  Future<List<SpecProjectSummary>> listProjects() async => const [];

  @override
  Future<String?> getLastActiveProjectId() async => null;
}

class _MemoryDomainCatalogStore extends DomainCatalogStore {
  _MemoryDomainCatalogStore(super.rootDirectory, [DomainCatalog? initial])
    : catalog = initial ?? DomainCatalog.empty;

  DomainCatalog catalog;

  @override
  Future<DomainCatalog> load() async => catalog;

  @override
  Future<void> save(DomainCatalog next) async {
    next.validate();
    catalog = next;
  }
}

({
  FunctionalDomain domain,
  DomainCatalog catalog,
  String invoiceEntryId,
  String customerEntryId,
})
_buildRichFixture() {
  final sharedEmail = ValueObjectPresets.standardPresets.firstWhere(
    (vo) => vo.technicalName == 'EmailAddress',
  );
  final sharedCurrency = ValueObjectPresets.standardPresets.firstWhere(
    (vo) => vo.technicalName == 'CurrencyCode',
  );

  final domainInvoiceNumber = ValueObjectSpec(
    id: 'vo_invoice_number',
    technicalName: 'InvoiceNumber',
    name: 'Numéro de facture',
    description: 'Identifiant séquentiel légal de facture.',
    category: 'Finance',
    version: '1.1.0',
    kind: ValueObjectKind.scalar,
    primitiveType: BusinessAttributeType.string,
    schemaConstraints: JsonSchemaConstraints(
      minLength: 8,
      maxLength: 20,
      pattern: r'^FAC-\d{4}-\d+$',
    ),
    normalizationRules: const <String>['trim', 'uppercase'],
    examples: const <ValueObjectExample>[
      ValueObjectExample(id: 'ex_inv_ok', value: 'FAC-2026-0001'),
    ],
  );

  final domainMoney = ValueObjectSpec(
    id: 'vo_money',
    technicalName: 'Money',
    name: 'Montant monétaire',
    description: 'Montant décimal positif associé à une devise ISO 4217.',
    category: 'Finance',
    version: '1.0.0',
    kind: ValueObjectKind.composite,
    fields: <BusinessAttribute>[
      BusinessAttribute(
        id: 'f_amount',
        name: 'amount',
        type: BusinessAttributeType.number,
        required: true,
        schemaConstraints: JsonSchemaConstraints(minimum: 0),
      ),
      BusinessAttribute(
        id: 'f_currency',
        name: 'currency',
        type: BusinessAttributeType.valueObject,
        valueObjectId: sharedCurrency.id,
        required: true,
      ),
    ],
    crossFieldRules: const <String>['amount >= 0'],
  );

  var contracts = DomainContracts.parse(
    'models:\n'
    '  Invoice: model\n'
    'components:\n'
    '  CustomerSummary: component\n',
  );
  final invoiceNode = contracts.groups[0].children.single;
  final customerNode = contracts.groups[1].children.single;

  contracts = contracts.edit(
    invoiceNode,
    'model',
    ContractDetails(
      title: 'Facture client',
      version: '1.2.0',
      states: const <ContractStage, ContractStatus>{
        ContractStage.design: ContractStatus.done,
        ContractStage.validation: ContractStatus.inProgress,
      },
    ),
  );
  contracts = contracts.edit(
    customerNode,
    'component',
    ContractDetails(
      title: 'Résumé client',
      version: '1.0.0',
      states: const <ContractStage, ContractStatus>{
        ContractStage.design: ContractStatus.done,
      },
    ),
  );

  final customerSpec = BusinessObjectSpec(
    id: customerNode.id,
    name: 'Résumé client',
    technicalName: 'CustomerSummary',
    description: 'Projection synthétique du client facturé.',
    attributes: <BusinessAttribute>[
      BusinessAttribute(
        id: 'attr_cust_id',
        name: 'customerId',
        type: BusinessAttributeType.uuid,
        required: true,
      ),
      BusinessAttribute(
        id: 'attr_cust_email',
        name: 'billingEmail',
        type: BusinessAttributeType.valueObject,
        valueObjectId: sharedEmail.id,
        required: true,
      ),
    ],
  );

  final invoiceSpec = BusinessObjectSpec(
    id: invoiceNode.id,
    name: 'Facture client',
    technicalName: 'Invoice',
    description: 'Agrégat racine de facturation client.',
    attributes: <BusinessAttribute>[
      BusinessAttribute(
        id: 'attr_inv_id',
        name: 'id',
        type: BusinessAttributeType.uuid,
        required: true,
      ),
      BusinessAttribute(
        id: 'attr_inv_num',
        name: 'invoiceNumber',
        type: BusinessAttributeType.valueObject,
        valueObjectId: domainInvoiceNumber.id,
        required: true,
      ),
      BusinessAttribute(
        id: 'attr_inv_total',
        name: 'totalAmount',
        type: BusinessAttributeType.valueObject,
        valueObjectId: domainMoney.id,
        required: true,
      ),
      BusinessAttribute(
        id: 'attr_inv_customer',
        name: 'customer',
        type: BusinessAttributeType.reference,
        referenceObjectId: customerNode.id,
        required: true,
      ),
      BusinessAttribute(
        id: 'attr_inv_status',
        name: 'status',
        type: BusinessAttributeType.enumeration,
        enumValues: const <String>['DRAFT', 'ISSUED', 'PAID'],
        required: true,
      ),
    ],
  );

  final fullDomainLayer = HexagonalDomainLayerSpec(
    invariants: <DomainInvariantSpec>[
      DomainInvariantSpec(
        id: 'inv_total_pos',
        code: 'INV-001',
        title: 'Total positif ou nul',
        expression: 'totalAmount.amount >= 0',
        relatedAttributes: const <String>['totalAmount'],
        violationError: 'NegativeInvoiceAmountError',
      ),
    ],
    stateChanges: <DomainStateChangeSpec>[
      DomainStateChangeSpec(
        id: 'sc_issue',
        name: 'issueInvoice',
        title: 'Émettre la facture',
        parameters: const <String>['issuedAt: datetime'],
        preconditions: const <String>['status == DRAFT'],
        mutations: const <String>['status = ISSUED'],
        fromStates: const <String>['DRAFT'],
        toState: 'ISSUED',
        emittedEvents: const <String>['InvoiceIssued'],
      ),
    ],
    queries: <DomainQuerySpec>[
      DomainQuerySpec(
        id: 'qry_payable',
        name: 'isPayable',
        title: 'Indique si la facture est payable',
        returnType: 'bool',
        formula: 'status == ISSUED',
      ),
    ],
    policyServices: <DomainPolicyServiceSpec>[
      DomainPolicyServiceSpec(
        id: 'pol_vat',
        name: 'VatCalculationPolicy',
        title: 'Politique de calcul de TVA',
        operation: 'computeVat(invoice) -> Money',
        collaborators: const <String>['CustomerSummary'],
        rules: const <String>['TVA standard 20%'],
      ),
    ],
    factories: <DomainFactorySpec>[
      DomainFactorySpec(
        id: 'fac_draft',
        name: 'createDraft',
        title: 'Créer un brouillon de facture',
        parameters: const <String>[
          'customer: CustomerSummary',
          'totalAmount: Money',
        ],
        initialState: 'DRAFT',
        enforcedInvariants: const <String>['INV-001'],
      ),
    ],
    domainEvents: <DomainEventSpec>[
      DomainEventSpec(
        id: 'evt_issued',
        name: 'InvoiceIssued',
        title: 'Facture émise',
        trigger: 'issueInvoice',
        payloadFields: const <String>['id', 'invoiceNumber', 'totalAmount'],
      ),
    ],
    persistencePolicy: DomainPersistencePolicySpec(
      repositoryPortName: 'InvoiceRepository',
      aggregateBoundary: 'Invoice',
      concurrencyStrategy: DomainConcurrencyStrategy.optimisticVersion,
      deletionStrategy: DomainDeletionStrategy.immutableArchive,
      rules: const <String>['Unicité stricte sur invoiceNumber'],
      portMethods: <DomainRepositoryMethodSpec>[
        DomainRepositoryMethodSpec(
          id: 'rep_save',
          name: 'save',
          signature: '(invoice: Invoice) -> void',
          category: PersistenceBehaviorCategory.crud,
        ),
      ],
    ),
  );

  contracts = contracts
      .withModel(customerNode.id, object: customerSpec)
      .withModel(invoiceNode.id, object: invoiceSpec)
      .withDomainLayer(invoiceNode.id, layer: fullDomainLayer);

  final orchestration = UseCaseOrchestrationSpec(
    cartography: <BoundedContextUseCaseMap>[
      BoundedContextUseCaseMap(
        id: 'bc_billing',
        boundedContext: 'Facturation',
        description: 'Émission et consultation des factures.',
        useCaseCodes: const <String>['UC-001', 'UC-002'],
        sagaCodes: const <String>['SAGA-001'],
      ),
    ],
    useCases: <ApplicationUseCaseSpec>[
      ApplicationUseCaseSpec(
        id: 'uc_issue_invoice',
        code: 'UC-001',
        name: 'IssueCustomerInvoice',
        title: 'Émettre une facture client',
        version: '1.0.0',
        boundedContext: 'Facturation',
        cqrsType: UseCaseCqrsType.command,
        targetAggregate: 'Invoice',
        businessGoal: 'Valide et émet légalement une facture brouillon.',
        triggerInputs: const <UseCaseFieldSpec>[
          UseCaseFieldSpec(
            name: 'invoiceId',
            type: 'uuid',
            required: true,
            description: 'Identifiant de la facture.',
          ),
          UseCaseFieldSpec(
            name: 'forceNotify',
            type: 'boolean',
            required: false,
          ),
        ],
        outputs: const <UseCaseFieldSpec>[
          UseCaseFieldSpec(
            name: 'invoiceNumber',
            type: 'string',
            required: true,
          ),
        ],
        outboundPorts: const <String>['InvoiceRepository', 'EventBusPort'],
        emittedEvents: const <String>['InvoiceIssued'],
      ),
      ApplicationUseCaseSpec(
        id: 'uc_get_invoice',
        code: 'UC-002',
        name: 'GetInvoiceDetails',
        title: 'Consulter une facture',
        version: '1.0.0',
        boundedContext: 'Facturation',
        cqrsType: UseCaseCqrsType.query,
        targetAggregate: 'Invoice',
        businessGoal: 'Retourne le détail complet d’une facture.',
        triggerInputs: const <UseCaseFieldSpec>[
          UseCaseFieldSpec(name: 'invoiceId', type: 'uuid', required: true),
        ],
        outputs: const <UseCaseFieldSpec>[
          UseCaseFieldSpec(
            name: 'status',
            type: 'enum',
            enumValues: <String>['DRAFT', 'ISSUED', 'PAID'],
            required: true,
          ),
          UseCaseFieldSpec(
            name: 'totalAmount',
            type: 'number',
            constraints: '>= 0',
            required: true,
          ),
        ],
      ),
    ],
    sagas: <OrchestrationSagaSpec>[
      OrchestrationSagaSpec(
        id: 'saga_billing_settlement',
        code: 'SAGA-001',
        name: 'InvoiceSettlementSaga',
        title: 'Saga d’encaissement de facture',
        version: '1.0.0',
        boundedContexts: const <String>['Facturation', 'Paiement'],
        coordinationMode: SagaCoordinationMode.orchestration,
        triggerEventOrCommand: 'InvoiceIssued',
        correlationKey: 'invoiceId',
        mermaidDiagram: 'sequenceDiagram\n  Facturation->>Paiement: Capture',
        compensationMatrix: const <SagaCompensationRow>[
          SagaCompensationRow(
            id: 'comp_1',
            step: '1. Capture paiement',
            nominalAction: 'CapturePayment',
            compensationAction: 'VoidInvoiceIssuance',
            rollbackTrigger: 'PaymentDeclined',
            criticality: SagaStepCriticality.critical,
          ),
        ],
      ),
    ],
  );

  final billingDomain = FunctionalDomain(
    id: 'dom_billing',
    domainCode: 'billing-domain',
    name: 'Facturation Client',
    description: 'Gestion du cycle de vie des factures et règlements.',
    isActive: true,
    techStackId: BuildTechStackProfile.defaultTsNestJsId,
    contracts: contracts,
    useCaseOrchestration: orchestration,
    valueObjects: <ValueObjectSpec>[domainInvoiceNumber, domainMoney],
  );

  const otherDomain = FunctionalDomain(
    id: 'dom_other',
    domainCode: 'shipping-domain',
    name: 'Expédition',
  );

  final catalog = DomainCatalog(
    domains: <FunctionalDomain>[billingDomain, otherDomain],
    sharedValueObjects: <ValueObjectSpec>[sharedEmail, sharedCurrency],
    environments: const <LogicalEnvironment>[
      LogicalEnvironment(
        id: 'env_billing_prod',
        domainId: 'dom_billing',
        environmentCode: 'prod',
        name: 'Production Facturation',
        description: 'Environnement de production.',
      ),
      LogicalEnvironment(
        id: 'env_other_dev',
        domainId: 'dom_other',
        environmentCode: 'dev',
        name: 'Dev Expédition',
      ),
    ],
    microservices: const <Microservice>[
      Microservice(
        id: 'svc_billing_api',
        domainId: 'dom_billing',
        serviceCode: 'billing-api',
        name: 'Billing API',
        kind: DomainSystemKind.microservice,
        description: 'Service cœur de facturation.',
        techStackId: BuildTechStackProfile.defaultTsNestJsId,
      ),
      Microservice(
        id: 'svc_stripe',
        domainId: 'dom_billing',
        serviceCode: 'stripe-psp',
        name: 'Stripe PSP',
        kind: DomainSystemKind.externalApp,
        vendor: 'Stripe',
      ),
      Microservice(
        id: 'svc_shipping_api',
        domainId: 'dom_other',
        serviceCode: 'shipping-api',
        name: 'Shipping API',
      ),
    ],
    configurationEntries: const <ConfigurationEntry>[
      ConfigurationEntry(
        id: 'cfg_plain_url',
        domainId: 'dom_billing',
        environmentId: 'env_billing_prod',
        microserviceId: 'svc_billing_api',
        configKey: 'PUBLIC_BASE_URL',
        entryType: ConfigurationEntryType.plainVariable,
        plainValue: 'https://billing.acme.example',
        description: 'URL publique du service.',
      ),
      ConfigurationEntry(
        id: 'cfg_secret_stripe',
        domainId: 'dom_billing',
        environmentId: 'env_billing_prod',
        microserviceId: 'svc_stripe',
        configKey: 'STRIPE_API_SECRET',
        entryType: ConfigurationEntryType.secret,
        encryptedValue: 'v1:TOP_SECRET_CIPHERTEXT_DO_NOT_LEAK',
        isInitialized: true,
        description: 'Clé secrète Stripe.',
      ),
      ConfigurationEntry(
        id: 'cfg_secret_uninit',
        domainId: 'dom_billing',
        environmentId: 'env_billing_prod',
        configKey: 'WEBHOOK_SIGNING_SECRET',
        entryType: ConfigurationEntryType.secret,
        isInitialized: false,
        description: 'Secret de signature webhook en attente.',
      ),
      ConfigurationEntry(
        id: 'cfg_other_domain',
        domainId: 'dom_other',
        environmentId: 'env_other_dev',
        configKey: 'SHIPPING_MODE',
        entryType: ConfigurationEntryType.plainVariable,
        plainValue: 'express',
      ),
    ],
  );

  return (
    domain: billingDomain,
    catalog: catalog,
    invoiceEntryId: invoiceNode.id,
    customerEntryId: customerNode.id,
  );
}

void main() {
  group('DomainDesignSpecExporter', () {
    test(
      'defaultFileName distingue l’état courant et un snapshot d’itération',
      () {
        const domain = FunctionalDomain(
          id: 'dom_1',
          domainCode: 'billing-domain',
          name: 'Facturation',
        );
        expect(
          DomainDesignSpecExporter.defaultFileName(domain),
          'billing-domain.domain-design.json',
        );

        final snap = DomainIterationSnapshot(
          id: 'snap_2',
          iterationNumber: 2,
          label: 'Itération 2',
          createdAt: DateTime.utc(2026, 11, 27),
        );
        expect(
          DomainDesignSpecExporter.defaultFileName(domain, snapshot: snap),
          'billing-domain.iter-2.domain-design.json',
        );
      },
    );

    test('exporte l’état courant complet (modèles, 7 onglets Domain Layer, VOs domaine/shared, Use Cases Command/Query, Sagas, systèmes) et supprime strictement encryptedValue', () {
      final fixture = _buildRichFixture();
      final exportedAt = DateTime(2026, 11, 27, 20, 30, 0);

      final prettyJson = DomainDesignSpecExporter.exportToPrettyJson(
        domain: fixture.domain,
        catalog: fixture.catalog,
        modelPreferences: BusinessObjectModelPreferences.defaults.copyWith(
          schemaStrictness: JsonSchemaStrictness.strict,
        ),
        exportedAt: exportedAt,
      );

      // Sécurité critique : aucune trace du ciphertext dans la chaîne JSON produite.
      expect(prettyJson.contains('TOP_SECRET_CIPHERTEXT_DO_NOT_LEAK'), isFalse);
      expect(prettyJson.contains('encryptedValue'), isFalse);

      final decoded = jsonDecode(prettyJson) as Map<String, Object?>;
      expect(decoded['format'], DomainDesignSpecExporter.fileFormat);
      expect(decoded['version'], DomainDesignSpecExporter.specVersion);
      expect(decoded['exportedAt'], exportedAt.toUtc().toIso8601String());
      expect(decoded['sourceKind'], 'current');
      expect(decoded.containsKey('snapshotMeta'), isFalse);

      // Domaine & stack technique résolue.
      final domainJson = decoded['domain'] as Map<String, Object?>;
      expect(domainJson['id'], 'dom_billing');
      expect(domainJson['domainCode'], 'billing-domain');
      expect(domainJson['name'], 'Facturation Client');
      expect(domainJson['isActive'], isTrue);
      expect(
        domainJson['techStackId'],
        BuildTechStackProfile.defaultTsNestJsId,
      );
      final techStackJson = domainJson['techStack'] as Map<String, Object?>;
      expect(techStackJson['id'], BuildTechStackProfile.defaultTsNestJsId);
      expect(techStackJson['code'], 'ts-nestjs');
      expect(techStackJson['name'], 'TypeScript / NestJS');
      expect((techStackJson['description'] as String), isNotEmpty);

      // Environnements et systèmes filtrés sur dom_billing uniquement.
      final envsJson = decoded['environments'] as List<Object?>;
      expect(envsJson, hasLength(1));
      expect(
        (envsJson.single as Map<String, Object?>)['environmentCode'],
        'prod',
      );

      final systemsJson = decoded['systems'] as List<Object?>;
      expect(systemsJson, hasLength(2));
      expect(
        systemsJson.map((s) => (s as Map<String, Object?>)['serviceCode']),
        containsAll(<String>['billing-api', 'stripe-psp']),
      );

      // Configurations filtrées et secrets masqués sans encryptedValue ni plainValue.
      final configsJson = (decoded['configurations'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(configsJson, hasLength(3));

      final plainCfg = configsJson.firstWhere(
        (c) => c['configKey'] == 'PUBLIC_BASE_URL',
      );
      expect(plainCfg['entryType'], 'plainVariable');
      expect(plainCfg['plainValue'], 'https://billing.acme.example');
      expect(plainCfg['microserviceId'], 'svc_billing_api');
      expect(plainCfg['isInitialized'], isTrue);
      expect(plainCfg.containsKey('encryptedValue'), isFalse);

      final secretInitCfg = configsJson.firstWhere(
        (c) => c['configKey'] == 'STRIPE_API_SECRET',
      );
      expect(secretInitCfg['entryType'], 'secret');
      expect(secretInitCfg['microserviceId'], 'svc_stripe');
      expect(secretInitCfg['isInitialized'], isTrue);
      expect(secretInitCfg.containsKey('encryptedValue'), isFalse);
      expect(secretInitCfg.containsKey('plainValue'), isFalse);

      final secretUninitCfg = configsJson.firstWhere(
        (c) => c['configKey'] == 'WEBHOOK_SIGNING_SECRET',
      );
      expect(secretUninitCfg['entryType'], 'secret');
      expect(secretUninitCfg['isInitialized'], isFalse);
      expect(secretUninitCfg.containsKey('microserviceId'), isFalse);
      expect(secretUninitCfg.containsKey('encryptedValue'), isFalse);
      expect(secretUninitCfg.containsKey('plainValue'), isFalse);

      // Value Objects (2 domaine + 2 shared) avec Draft 2020-12 JSON Schema.
      final vosJson = (decoded['valueObjects'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(vosJson, hasLength(4));

      final moneyVo = vosJson.firstWhere(
        (v) => (v['spec'] as Map<String, Object?>)['technicalName'] == 'Money',
      );
      expect(moneyVo['scope'], 'domain');
      final moneySchema = moneyVo['jsonSchema'] as Map<String, Object?>;
      expect(
        moneySchema[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema',
      );
      expect(moneySchema['title'], 'Money');
      expect(moneySchema['type'], 'object');
      expect(moneySchema['x-value-object'], 'Money');
      expect(moneySchema['x-value-object-scope'], 'domain');
      final moneyProps = moneySchema['properties'] as Map<String, Object?>;
      expect(
        (moneyProps['currency'] as Map<String, Object?>)['x-value-object'],
        'CurrencyCode',
      );
      expect(
        (moneyProps['currency']
            as Map<String, Object?>)['x-value-object-scope'],
        'shared',
      );

      final emailVo = vosJson.firstWhere(
        (v) =>
            (v['spec'] as Map<String, Object?>)['technicalName'] ==
            'EmailAddress',
      );
      expect(emailVo['scope'], 'shared');
      final emailSchema = emailVo['jsonSchema'] as Map<String, Object?>;
      expect(
        emailSchema[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema',
      );
      expect(emailSchema['format'], 'email');
      expect(emailSchema['x-value-object-scope'], 'shared');

      // Contrats, JSON Schemas Draft 2020-12 et 7 onglets Domain Layer.
      final contractsJson = decoded['contracts'] as Map<String, Object?>;
      expect(
        (contractsJson['dslSource'] as String),
        contains('Invoice: model'),
      );
      final entriesJson = (contractsJson['entries'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(entriesJson, hasLength(2));

      final invoiceEntry = entriesJson.firstWhere(
        (e) => e['entryId'] == fixture.invoiceEntryId,
      );
      expect(invoiceEntry['name'], 'Invoice');
      expect(invoiceEntry['technicalName'], 'Invoice');
      expect(invoiceEntry['groupName'], 'models');
      expect(invoiceEntry['dslType'], 'model');
      expect(invoiceEntry['title'], 'Facture client');
      expect(invoiceEntry['version'], '1.2.0');
      expect(invoiceEntry['states'], <String, Object?>{
        'design': 'done',
        'validation': 'inProgress',
      });

      final invoiceSchema = invoiceEntry['jsonSchema'] as Map<String, Object?>;
      expect(
        invoiceSchema[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema',
      );
      expect(invoiceSchema['title'], 'Invoice');
      expect(invoiceSchema['additionalProperties'], isFalse);
      final invProps = invoiceSchema['properties'] as Map<String, Object?>;
      expect(
        (invProps['invoiceNumber'] as Map<String, Object?>)['x-value-object'],
        'InvoiceNumber',
      );
      expect(
        (invProps['totalAmount'] as Map<String, Object?>)['x-value-object'],
        'Money',
      );
      expect(
        (invProps['customer'] as Map<String, Object?>)['x-reference'],
        'CustomerSummary',
      );

      final domainLayerJson =
          invoiceEntry['domainLayer'] as Map<String, Object?>;
      expect(domainLayerJson['invariants'], isA<List<Object?>>());
      expect(domainLayerJson['stateChanges'], isA<List<Object?>>());
      expect(domainLayerJson['queries'], isA<List<Object?>>());
      expect(domainLayerJson['policyServices'], isA<List<Object?>>());
      expect(domainLayerJson['factories'], isA<List<Object?>>());
      expect(domainLayerJson['domainEvents'], isA<List<Object?>>());
      expect(domainLayerJson['persistencePolicy'], isA<Map<String, Object?>>());
      expect(
        HexagonalDomainLayerSpec.fromJson(domainLayerJson),
        equals(fixture.domain.contracts!.domainLayers[fixture.invoiceEntryId]),
      );

      // Use Cases (Command & Query avec inputJsonSchema / outputJsonSchema) & Sagas.
      final ucoJson = decoded['useCaseOrchestration'] as Map<String, Object?>;
      expect(ucoJson['cartography'] as List<Object?>, hasLength(1));

      final useCasesJson = (ucoJson['useCases'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(useCasesJson, hasLength(2));

      final cmdUc = useCasesJson.firstWhere(
        (u) => (u['spec'] as Map<String, Object?>)['code'] == 'UC-001',
      );
      expect((cmdUc['spec'] as Map<String, Object?>)['cqrsType'], 'command');
      final cmdInputSchema = cmdUc['inputJsonSchema'] as Map<String, Object?>;
      expect(
        cmdInputSchema[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema',
      );
      expect(cmdInputSchema['title'], 'IssueCustomerInvoiceInput');
      expect(cmdInputSchema['required'], <Object?>['invoiceId']);
      final cmdOutputSchema = cmdUc['outputJsonSchema'] as Map<String, Object?>;
      expect(cmdOutputSchema['title'], 'IssueCustomerInvoiceOutput');
      expect(cmdOutputSchema['required'], <Object?>['invoiceNumber']);

      final qryUc = useCasesJson.firstWhere(
        (u) => (u['spec'] as Map<String, Object?>)['code'] == 'UC-002',
      );
      expect((qryUc['spec'] as Map<String, Object?>)['cqrsType'], 'query');
      final qryOutProps =
          (qryUc['outputJsonSchema'] as Map<String, Object?>)['properties']
              as Map<String, Object?>;
      expect(
        (qryOutProps['totalAmount'] as Map<String, Object?>)['minimum'],
        0,
      );

      final sagasJson = (ucoJson['sagas'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(sagasJson, hasLength(1));
      expect(sagasJson.single['name'], 'InvoiceSettlementSaga');
    });

    test('exporte fidèlement un DomainIterationSnapshot figé même après évolution ultérieure du domaine courant', () {
      final fixture = _buildRichFixture();
      final snapCreatedAt = DateTime.utc(2026, 11, 20, 10, 0, 0);
      final snapshot = DomainIterationSnapshot.capture(
        id: 'snap_iter_1',
        iterationNumber: 1,
        label: 'Itération 1 — Socle MVP',
        notes: 'Jalon initial validé',
        createdAt: snapCreatedAt,
        domain: fixture.domain,
        catalog: fixture.catalog,
      );

      // Évolution ultérieure du domaine courant (ajout d'un modèle, d'un VO, suppression de la Saga, ajout d'un UC).
      final mutatedContracts = fixture.domain.contracts!.patch(
        'models:\n'
        '  Invoice: model\n'
        '  CreditNote: model\n'
        'components:\n'
        '  CustomerSummary: component\n',
      );
      final extraVo = ValueObjectSpec(
        id: 'vo_iban',
        technicalName: 'Iban',
        name: 'IBAN',
        kind: ValueObjectKind.scalar,
        primitiveType: BusinessAttributeType.string,
      );
      final mutatedDomain = fixture.domain.copyWith(
        name: 'Facturation Client v2',
        contracts: mutatedContracts,
        valueObjects: <ValueObjectSpec>[
          ...fixture.domain.valueObjects,
          extraVo,
        ],
        useCaseOrchestration: fixture.domain.useCaseOrchestration!.copyWith(
          sagas: const <OrchestrationSagaSpec>[],
        ),
        iterationSnapshots: <DomainIterationSnapshot>[snapshot],
      );
      final mutatedCatalog = fixture.catalog.copyWith(
        domains: <FunctionalDomain>[
          for (final d in fixture.catalog.domains)
            if (d.id == mutatedDomain.id) mutatedDomain else d,
        ],
      );

      final exported = DomainDesignSpecExporter.exportToJson(
        domain: mutatedDomain,
        catalog: mutatedCatalog,
        snapshot: snapshot,
        exportedAt: DateTime.utc(2026, 11, 27, 21, 0, 0),
      );

      expect(exported['sourceKind'], 'snapshot');
      final snapMeta = exported['snapshotMeta'] as Map<String, Object?>;
      expect(snapMeta['id'], 'snap_iter_1');
      expect(snapMeta['iterationNumber'], 1);
      expect(snapMeta['label'], 'Itération 1 — Socle MVP');
      expect(snapMeta['notes'], 'Jalon initial validé');
      expect(snapMeta['createdAt'], snapCreatedAt.toIso8601String());

      // L'en-tête domaine, environnements, systèmes et configurations masquées proviennent du domaine/catalogue.
      expect(
        (exported['domain'] as Map<String, Object?>)['name'],
        'Facturation Client v2',
      );
      expect(exported['environments'] as List<Object?>, hasLength(1));
      expect(exported['systems'] as List<Object?>, hasLength(2));
      final configs = (exported['configurations'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(configs.every((c) => !c.containsKey('encryptedValue')), isTrue);

      // Les VOs, contrats, Use Cases et Sagas proviennent strictement du snapshot figé !
      final snapVos = (exported['valueObjects'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(snapVos, hasLength(4));
      expect(
        snapVos.any(
          (v) => (v['spec'] as Map<String, Object?>)['technicalName'] == 'Iban',
        ),
        isFalse,
      );

      final snapEntries =
          ((exported['contracts'] as Map<String, Object?>)['entries']
                  as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(snapEntries, hasLength(2));
      expect(snapEntries.any((e) => e['name'] == 'CreditNote'), isFalse);
      final snapInvoice = snapEntries.firstWhere(
        (e) => e['entryId'] == fixture.invoiceEntryId,
      );
      expect(
        (snapInvoice['jsonSchema'] as Map<String, Object?>)[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema',
      );
      expect(
        (snapInvoice['domainLayer'] as Map<String, Object?>)['invariants'],
        isNotEmpty,
      );

      final snapUco = exported['useCaseOrchestration'] as Map<String, Object?>;
      expect(snapUco['useCases'] as List<Object?>, hasLength(2));
      expect(snapUco['sagas'] as List<Object?>, hasLength(1));
    });

    test('exportToFile crée les dossiers parents et écrit le fichier JSON formaté', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'domain_design_spec_export_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final fixture = _buildRichFixture();
      final sep = Platform.pathSeparator;
      final target = File(
        '${tempDir.path}${sep}exports$sep${DomainDesignSpecExporter.defaultFileName(fixture.domain)}',
      );

      final written = await DomainDesignSpecExporter.exportToFile(
        targetFile: target,
        domain: fixture.domain,
        catalog: fixture.catalog,
      );

      expect(await written.exists(), isTrue);
      final content = await written.readAsString();
      expect(content.contains('TOP_SECRET_CIPHERTEXT_DO_NOT_LEAK'), isFalse);
      final parsed = jsonDecode(content) as Map<String, Object?>;
      expect(parsed['format'], DomainDesignSpecExporter.fileFormat);
      expect(parsed['sourceKind'], 'current');
    });
  });

  group('DomainManagementView — action Exporter Spec Design', () {
    testWidgets(
      'permet de choisir état courant ou snapshot, copier dans le presse-papiers et enregistrer dans <workspace>/exports/',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final workspaceDir = await tester.runAsync(
          () => Directory.systemTemp.createTemp('spec_forge_ws_export_'),
        );
        expect(workspaceDir, isNotNull);
        addTearDown(() async {
          if (workspaceDir!.existsSync()) {
            workspaceDir.deleteSync(recursive: true);
          }
        });

        String? copiedClipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                final args = call.arguments as Map<dynamic, dynamic>;
                copiedClipboardText = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final fixture = _buildRichFixture();
        final snap1 = DomainIterationSnapshot.capture(
          id: 'snap_1',
          iterationNumber: 1,
          label: 'MVP Initial',
          createdAt: DateTime.utc(2026, 11, 25),
          domain: fixture.domain,
          catalog: fixture.catalog,
        );
        final domainWithSnap = fixture.domain.copyWith(
          iterationSnapshots: <DomainIterationSnapshot>[snap1],
        );
        final initialCatalog = fixture.catalog.copyWith(
          domains: <FunctionalDomain>[
            for (final d in fixture.catalog.domains)
              if (d.id == domainWithSnap.id) domainWithSnap else d,
          ],
        );

        final catalogStore = _MemoryDomainCatalogStore(
          workspaceDir!,
          initialCatalog,
        );
        final controller = SpecForgeController(
          store: _TempSpecProjectStore(workspaceDir),
          domainCatalogStore: catalogStore,
          glossaryStore: CompanyGlossaryStore(workspaceDir),
          modelDictionaryStore: ModelDictionaryStore(workspaceDir),
          enterpriseRateCardStore: EnterpriseRateCardStore(workspaceDir),
        );
        addTearDown(controller.dispose);
        await controller.updateDomainCatalog(initialCatalog);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: DomainManagementView(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        // Sélectionne le domaine Facturation Client.
        await tester.tap(find.byKey(const ValueKey('domain-item-dom_billing')));
        await tester.pumpAndSettle();

        final exportBtn = find.byKey(
          const ValueKey('domain-export-design-spec-btn'),
        );
        expect(exportBtn, findsOneWidget);

        // 1) Copier le JSON de l'état courant.
        await tester.tap(exportBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('domain-export-design-spec-dialog')),
          findsOneWidget,
        );

        final sep = Platform.pathSeparator;
        final expectedCurrentPath =
            '${workspaceDir.path}${sep}exports${sep}billing-domain.domain-design.json';
        final pathField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('domain-export-file-path-field')),
        );
        expect(pathField.controller?.text, expectedCurrentPath);

        await tester.tap(
          find.byKey(const ValueKey('domain-export-copy-json-btn')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Spécification Design copiée dans le presse-papiers.'),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        expect(copiedClipboardText, isNotNull);
        final copiedMap =
            jsonDecode(copiedClipboardText!) as Map<String, Object?>;
        expect(copiedMap['sourceKind'], 'current');
        expect(
          copiedClipboardText!.contains('TOP_SECRET_CIPHERTEXT_DO_NOT_LEAK'),
          isFalse,
        );

        // 2) Réouvre la boîte de dialogue, sélectionne le snapshot Itération 1 et enregistre sur disque.
        await tester.tap(exportBtn);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('domain-export-source-dropdown')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Itération 1 — MVP Initial').last);
        await tester.pumpAndSettle();

        final expectedSnapPath =
            '${workspaceDir.path}${sep}exports${sep}billing-domain.iter-1.domain-design.json';
        final updatedPathField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('domain-export-file-path-field')),
        );
        expect(updatedPathField.controller?.text, expectedSnapPath);

        await tester.runAsync(() async {
          await tester.tap(
            find.byKey(const ValueKey('domain-export-save-file-btn')),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Spécification Design enregistrée dans'),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        final savedFile = File(expectedSnapPath);
        expect(savedFile.existsSync(), isTrue);
        final savedJson =
            jsonDecode(savedFile.readAsStringSync()) as Map<String, Object?>;
        expect(savedJson['sourceKind'], 'snapshot');
        expect(
          (savedJson['snapshotMeta'] as Map<String, Object?>)['id'],
          'snap_1',
        );
      },
    );
  });
}
