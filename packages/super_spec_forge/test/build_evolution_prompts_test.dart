import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';
import 'package:yaml/yaml.dart';

({
  DomainCatalog catalogV1,
  FunctionalDomain domainV1,
  DomainIterationSnapshot snapshotV1,
  DomainCatalog catalogV2,
  FunctionalDomain domainV2,
  String productNodeId,
  String oldPromoNodeId,
})
_buildCatalogFixture() {
  final currencyVo = ValueObjectSpec(
    id: 'vo_shared_currency',
    technicalName: 'CurrencyCode',
    name: 'Code devise ISO',
    category: 'Finance',
    version: '1.0.0',
    kind: ValueObjectKind.scalar,
    primitiveType: BusinessAttributeType.enumeration,
    enumValues: const <String>['EUR', 'USD'],
    normalizationRules: const <String>['trim', 'uppercase'],
    examples: const <ValueObjectExample>[
      ValueObjectExample(
        id: 'ex_cur_ok',
        value: 'EUR',
        isValid: true,
        reason: 'Code devise valide',
      ),
      ValueObjectExample(
        id: 'ex_cur_ko',
        value: 'GBP',
        isValid: false,
        reason: 'Devise hors périmètre autorisé',
      ),
    ],
    states: const <ContractStage, ContractStatus>{
      ContractStage.design: ContractStatus.done,
      ContractStage.code: ContractStatus.done,
    },
  );

  final moneyVoV1 = ValueObjectSpec(
    id: 'vo_shared_money',
    technicalName: 'Money',
    name: 'Montant monétaire',
    description: 'Montant exprimé en centimes avec devise.',
    category: 'Finance',
    version: '1.0.0',
    kind: ValueObjectKind.composite,
    fields: <BusinessAttribute>[
      BusinessAttribute(
        id: 'f_amount',
        name: 'amountMinorUnits',
        type: BusinessAttributeType.integer,
        required: true,
        schemaConstraints: JsonSchemaConstraints(minimum: 0),
      ),
      BusinessAttribute(
        id: 'f_currency',
        name: 'currency',
        type: BusinessAttributeType.valueObject,
        valueObjectId: currencyVo.id,
        required: true,
      ),
    ],
    crossFieldRules: const <String>['amountMinorUnits >= 0'],
    examples: const <ValueObjectExample>[
      ValueObjectExample(
        id: 'ex_m_ok',
        value: '{"amountMinorUnits": 1990, "currency": "EUR"}',
        isValid: true,
        reason: '19,90 EUR nominal',
      ),
      ValueObjectExample(
        id: 'ex_m_ko',
        value: '{"amountMinorUnits": -10, "currency": "EUR"}',
        isValid: false,
        reason: 'Montant négatif interdit',
      ),
    ],
    states: const <ContractStage, ContractStatus>{
      ContractStage.design: ContractStatus.done,
      ContractStage.validation: ContractStatus.done,
      ContractStage.code: ContractStatus.done,
      ContractStage.delivery: ContractStatus.done,
    },
  );

  final skuVo = ValueObjectSpec(
    id: 'vo_dom_sku',
    technicalName: 'SkuCode',
    name: 'Référence article SKU',
    description: 'Identifiant SKU normalisé sans espace.',
    category: 'Identité',
    version: '1.0.0',
    kind: ValueObjectKind.scalar,
    primitiveType: BusinessAttributeType.string,
    schemaConstraints: JsonSchemaConstraints(
      minLength: 4,
      maxLength: 24,
      pattern: r'^[A-Z0-9-]+$',
    ),
    normalizationRules: const <String>['trim', 'uppercase'],
    constraints: 'Alphanumérique majuscule et tirets uniquement.',
    examples: const <ValueObjectExample>[
      ValueObjectExample(
        id: 'ex_sku_ok',
        value: 'PROD-2026-A',
        isValid: true,
        reason: 'SKU canonique',
      ),
      ValueObjectExample(
        id: 'ex_sku_ko',
        value: 'ab',
        isValid: false,
        reason: 'Longueur inférieure à 4 caractères',
      ),
    ],
    states: const <ContractStage, ContractStatus>{
      ContractStage.design: ContractStatus.done,
      ContractStage.code: ContractStatus.done,
    },
  );

  var contractsV1 = DomainContracts.parse(
    'models:\n'
    '  Product: model\n'
    '  OldPromo: model\n'
    'dto:\n'
    '  CreateProductDto: createxdto\n',
  );
  final productNode = contractsV1.groups[0].children[0];
  final oldPromoNode = contractsV1.groups[0].children[1];

  contractsV1 = contractsV1.edit(
    productNode,
    productNode.type,
    ContractDetails(
      title: 'Produit catalogue',
      version: '1.0.0',
      states: const <ContractStage, ContractStatus>{
        ContractStage.design: ContractStatus.done,
        ContractStage.validation: ContractStatus.done,
        ContractStage.code: ContractStatus.done,
        ContractStage.delivery: ContractStatus.done,
      },
    ),
  );
  contractsV1 = contractsV1.edit(
    oldPromoNode,
    oldPromoNode.type,
    ContractDetails(
      title: 'Ancienne promotion',
      version: '1.0.0',
      states: const <ContractStage, ContractStatus>{
        ContractStage.design: ContractStatus.done,
      },
    ),
  );
  contractsV1 = contractsV1.withModel(
    productNode.id,
    object: BusinessObjectSpec(
      id: productNode.id,
      name: 'Produit catalogue',
      technicalName: 'Product',
      aggregateRoot: true,
      attributes: <BusinessAttribute>[
        BusinessAttribute(
          id: 'attr_sku',
          name: 'sku',
          type: BusinessAttributeType.valueObject,
          valueObjectId: skuVo.id,
          required: true,
        ),
        BusinessAttribute(
          id: 'attr_price',
          name: 'unitPrice',
          type: BusinessAttributeType.valueObject,
          valueObjectId: moneyVoV1.id,
          required: true,
        ),
      ],
    ),
  );
  contractsV1 = contractsV1.withDomainLayer(
    productNode.id,
    layer: HexagonalDomainLayerSpec(
      stateChanges: <DomainStateChangeSpec>[
        DomainStateChangeSpec(
          id: 'sc_reprice',
          name: 'changePrice',
          title: 'Changer le prix unitaire',
          methodSignature: 'changePrice(Money newPrice)',
          emittedEvents: const <String>['ProductPriceChanged'],
        ),
      ],
      persistencePolicy: DomainPersistencePolicySpec(
        repositoryPortName: 'ProductRepository',
        concurrencyStrategy: DomainConcurrencyStrategy.optimisticVersion,
      ),
    ),
  );
  contractsV1 = contractsV1.withModel(
    oldPromoNode.id,
    object: BusinessObjectSpec(
      id: oldPromoNode.id,
      name: 'Ancienne promotion',
      technicalName: 'OldPromo',
      attributes: <BusinessAttribute>[
        BusinessAttribute(
          id: 'attr_code',
          name: 'promoCode',
          type: BusinessAttributeType.string,
          required: true,
        ),
      ],
    ),
  );

  final publishUc = ApplicationUseCaseSpec(
    id: 'uc_publish_product',
    code: 'UC-010',
    name: 'PublishProduct',
    title: 'Publier un produit au catalogue',
    version: '1.0.0',
    boundedContext: 'Catalogue',
    cqrsType: UseCaseCqrsType.command,
    inboundPort: 'PublishProductUseCase',
    targetAggregate: 'Product',
    outboundPorts: const <String>['ProductRepository', 'CatalogEventPublisher'],
    emittedEvents: const <String>['ProductPublished'],
    triggerInputs: const <UseCaseFieldSpec>[
      UseCaseFieldSpec(name: 'productId', type: 'uuid', required: true),
    ],
    states: const <ContractStage, ContractStatus>{
      ContractStage.design: ContractStatus.done,
      ContractStage.code: ContractStatus.done,
    },
  );

  final syncSaga = OrchestrationSagaSpec(
    id: 'saga_catalog_sync',
    code: 'SAGA-010',
    name: 'CatalogSyncSaga',
    title: 'Synchronisation catalogue multi-canaux',
    version: '1.0.0',
    boundedContexts: const <String>['Catalogue', 'IndexRecherche'],
    coordinationMode: SagaCoordinationMode.orchestration,
    triggerEventOrCommand: 'ProductPublished',
    correlationKey: 'productId',
    compensationMatrix: const <SagaCompensationRow>[
      SagaCompensationRow(
        id: 'step_1',
        step: '1. Indexer produit',
        nominalAction: 'PublishProduct',
        compensationAction: 'UnindexProduct',
      ),
    ],
    states: const <ContractStage, ContractStatus>{
      ContractStage.design: ContractStatus.done,
      ContractStage.code: ContractStatus.inProgress,
    },
  );

  final domainV1 = FunctionalDomain(
    id: 'dom_catalog',
    domainCode: 'catalog',
    name: 'Catalogue Produits',
    techStackId: BuildTechStackProfile.defaultTsNestJsId,
    valueObjects: <ValueObjectSpec>[skuVo],
    contracts: contractsV1,
    useCaseOrchestration: UseCaseOrchestrationSpec(
      useCases: <ApplicationUseCaseSpec>[publishUc],
      sagas: <OrchestrationSagaSpec>[syncSaga],
    ),
  );

  final catalogV1 = DomainCatalog(
    domains: <FunctionalDomain>[domainV1],
    sharedValueObjects: <ValueObjectSpec>[currencyVo, moneyVoV1],
    updatedAt: DateTime.utc(2026, 11, 20),
  );

  final snapshotV1 = DomainIterationSnapshot.capture(
    id: 'snap_it_1',
    iterationNumber: 1,
    label: 'Itération 1 — MVP',
    notes: 'Baseline initiale du catalogue produits',
    createdAt: DateTime.utc(2026, 11, 20),
    domain: domainV1,
    catalog: catalogV1,
  );

  // --- Évolution vers l'Itération 2 ---
  // 1) Shared Kernel Money évolue (ajout d'un champ obligatoire roundingMode -> breaking / major).
  final moneyVoV2 = moneyVoV1.copyWith(
    version: '2.0.0',
    fields: <BusinessAttribute>[
      ...moneyVoV1.fields,
      BusinessAttribute(
        id: 'f_rounding',
        name: 'roundingMode',
        type: BusinessAttributeType.enumeration,
        enumValues: const <String>['HALF_UP', 'HALF_EVEN'],
        required: true,
      ),
    ],
  );

  // 2) OldPromo est supprimé ; Product gagne un attribut discountTag + nouvelle méthode Domain.
  var contractsV2 = contractsV1.patch(
    'models:\n'
    '  Product: model\n'
    'dto:\n'
    '  CreateProductDto: createxdto\n',
  );
  final productNodeV2 = contractsV2.entryById(productNode.id)!;
  contractsV2 = contractsV2.edit(
    productNodeV2,
    productNodeV2.type,
    contractsV1.details[productNode.id]!.copyWith(version: '1.1.0'),
  );
  contractsV2 = contractsV2.withModel(
    productNode.id,
    object: contractsV1
        .objectFor(productNode)
        .copyWith(
          attributes: <BusinessAttribute>[
            ...contractsV1.objectFor(productNode).attributes,
            BusinessAttribute(
              id: 'attr_discount_tag',
              name: 'discountTag',
              type: BusinessAttributeType.string,
              required: false,
              nullable: true,
            ),
          ],
        ),
  );
  contractsV2 = contractsV2.withDomainLayer(
    productNode.id,
    layer: HexagonalDomainLayerSpec(
      stateChanges: <DomainStateChangeSpec>[
        DomainStateChangeSpec(
          id: 'sc_reprice',
          name: 'changePrice',
          title: 'Appliquer un nouveau tarif avec remise optionnelle',
          methodSignature: 'changePrice(Money newPrice, String? discountTag)',
          emittedEvents: const <String>['ProductPriceChanged'],
        ),
      ],
      persistencePolicy: DomainPersistencePolicySpec(
        repositoryPortName: 'ProductRepository',
        concurrencyStrategy: DomainConcurrencyStrategy.optimisticVersion,
      ),
    ),
  );

  // 3) Nouveau Use Case CreateDiscount ajouté en Itération 2 ; PublishProduct reste inchangé mais impacté.
  final createDiscountUc = ApplicationUseCaseSpec(
    id: 'uc_create_discount',
    code: 'UC-020',
    name: 'CreateDiscount',
    title: 'Créer une remise produit',
    version: '1.0.0',
    boundedContext: 'Catalogue',
    cqrsType: UseCaseCqrsType.command,
    inboundPort: 'CreateDiscountUseCase',
    outboundPorts: const <String>['ProductRepository'],
    triggerInputs: const <UseCaseFieldSpec>[
      UseCaseFieldSpec(name: 'productId', type: 'uuid', required: true),
      UseCaseFieldSpec(name: 'discountTag', type: 'string', required: true),
    ],
    states: const <ContractStage, ContractStatus>{
      ContractStage.design: ContractStatus.inProgress,
    },
  );

  final domainV2 = domainV1.copyWith(
    contracts: contractsV2,
    useCaseOrchestration: UseCaseOrchestrationSpec(
      useCases: <ApplicationUseCaseSpec>[publishUc, createDiscountUc],
      sagas: <OrchestrationSagaSpec>[syncSaga],
    ),
    iterationSnapshots: <DomainIterationSnapshot>[snapshotV1],
    activeBaselineSnapshotId: snapshotV1.id,
  );

  final catalogV2 = DomainCatalog(
    domains: <FunctionalDomain>[domainV2],
    sharedValueObjects: <ValueObjectSpec>[currencyVo, moneyVoV2],
    updatedAt: DateTime.utc(2026, 11, 27),
  );

  return (
    catalogV1: catalogV1,
    domainV1: domainV1,
    snapshotV1: snapshotV1,
    catalogV2: catalogV2,
    domainV2: domainV2,
    productNodeId: productNode.id,
    oldPromoNodeId: oldPromoNode.id,
  );
}

void main() {
  group('BuildDomainDesignItems — Value Objects & politique non-intrusive badge_only', () {
    test('projette les Value Objects (Domaine + Shared Kernel), attache les rapports d’évolution et préserve strictement les états (badge_only)', () {
      final fx = _buildCatalogFixture();
      final projection = BuildDomainDesignItems.fromDomain(
        fx.domainV2,
        catalog: fx.catalogV2,
      );

      expect(projection.hasBaseline, isTrue);
      expect(projection.baselineSnapshot?.id, 'snap_it_1');

      // 1 VO domaine (SkuCode) + 2 VOs Shared Kernel (CurrencyCode, Money) = 3 VOs.
      expect(projection.valueObjects, hasLength(3));
      final skuItem = projection.valueObjects.firstWhere(
        (i) => i.name == 'SkuCode',
      );
      expect(skuItem.valueObjectScope, ValueObjectScope.domain);
      expect(skuItem.evolutionState, ArtifactEvolutionState.unchanged);
      expect(skuItem.isEvolved, isFalse);

      final moneyItem = projection.valueObjects.firstWhere(
        (i) => i.name == 'Money',
      );
      expect(moneyItem.valueObjectScope, ValueObjectScope.shared);
      expect(moneyItem.primaryBadge, 'composite');
      expect(moneyItem.secondaryBadge, contains('Shared Kernel'));
      expect(moneyItem.evolutionState, ArtifactEvolutionState.modified);
      expect(moneyItem.effectiveBump, SemVerBump.major);
      expect(moneyItem.baselineVersion, '1.0.0');
      expect(moneyItem.isEvolved, isTrue);

      // POLITIQUE BADGE_ONLY : malgré un changement majeur, les 4 indicateurs restent à done !
      for (final stage in ContractStage.values) {
        expect(moneyItem.statusOf(stage), ContractStatus.done);
      }

      final productItem = projection.models.firstWhere(
        (i) => i.id == fx.productNodeId,
      );
      expect(productItem.evolutionState, ArtifactEvolutionState.modified);
      expect(productItem.isEvolved, isTrue);
      for (final stage in ContractStage.values) {
        expect(productItem.statusOf(stage), ContractStatus.done);
      }

      final publishUcItem = projection.useCases.firstWhere(
        (i) => i.id == 'uc_publish_product',
      );
      expect(publishUcItem.evolutionState, ArtifactEvolutionState.impacted);
      expect(publishUcItem.isEvolved, isTrue);
      expect(publishUcItem.statusOf(ContractStage.code), ContractStatus.done);

      final createDiscountItem = projection.useCases.firstWhere(
        (i) => i.id == 'uc_create_discount',
      );
      expect(createDiscountItem.evolutionState, ArtifactEvolutionState.added);
      expect(createDiscountItem.baselineVersion, isNull);

      final sagaItem = projection.sagas.single;
      expect(sagaItem.evolutionState, ArtifactEvolutionState.impacted);
      expect(sagaItem.statusOf(ContractStage.code), ContractStatus.inProgress);

      // Artefact supprimé (OldPromo) exposé dans removedArtifacts.
      expect(projection.removedArtifacts, hasLength(1));
      expect(projection.removedArtifacts.single.id, fx.oldPromoNodeId);
      expect(projection.removedArtifacts.single.name, 'OldPromo');
      expect(
        projection.removedArtifacts.single.state,
        ArtifactEvolutionState.removed,
      );

      // Filtrage par état d'évolution et actionableOnly.
      expect(
        projection.filteredItemsOf(
          BuildDesignItemKind.valueObject,
          evolutionFilter: ArtifactEvolutionState.modified,
        ),
        equals(<BuildDesignItem>[moneyItem]),
      );
      expect(
        projection.filteredItemsOf(
          BuildDesignItemKind.useCase,
          evolutionFilter: ArtifactEvolutionState.added,
        ),
        equals(<BuildDesignItem>[createDiscountItem]),
      );
      expect(
        projection.filteredItemsOf(
          BuildDesignItemKind.valueObject,
          actionableOnly: true,
        ),
        equals(<BuildDesignItem>[moneyItem]),
      );
    });
  });

  group(
    'BuildHexaPromptGenerator — Prompts Value Objects (Scalaire & Composite)',
    () {
      test('génère les prompts Implémentation et Test unitaire conformes pour les Value Objects scalaires et composites', () {
        final fx = _buildCatalogFixture();
        final projection = BuildDomainDesignItems.fromDomain(
          fx.domainV1,
          catalog: fx.catalogV1,
        );
        final skuItem = projection.valueObjects.firstWhere(
          (i) => i.name == 'SkuCode',
        );
        final moneyItem = projection.valueObjects.firstWhere(
          (i) => i.name == 'Money',
        );

        final groups = BuildHexaPromptGenerator.generateGroups(
          domain: fx.domainV1,
          selectedItems: <BuildDesignItem>[skuItem, moneyItem],
          catalog: fx.catalogV1,
          includeDomainAdapters: false,
          referenceDate: DateTime.utc(2026, 11, 20),
        );

        expect(groups, hasLength(2));
        expect(groups[0].item, skuItem);
        expect(groups[0].prompts, hasLength(2));
        expect(groups[1].item, moneyItem);
        expect(groups[1].prompts, hasLength(2));

        // Vérification du VO scalaire (SkuCode)
        final skuImpl = groups[0].prompts[0];
        final skuTest = groups[0].prompts[1];
        final skuImplYaml = loadYaml(
          BuildHexaPromptGenerator.extractYamlHeader(skuImpl.promptMarkdown)!,
        ) as YamlMap;
        expect(skuImplYaml['kind'], 'value-object-implementation');
        expect(skuImplYaml['generation']['artifactType'], 'value-object');
        expect(skuImplYaml['generation']['valueObjectKind'], 'scalar');
        expect(skuImplYaml['generation']['valueObjectScope'], 'domain');
        expect(skuImplYaml['generation']['mode'], isNull);

        expect(
          skuImpl.promptMarkdown,
          allOf(
            contains('`trim` → `uppercase`'),
            contains('PROD-2026-A'),
            contains('Longueur inférieure à 4 caractères'),
            contains('## Extension Stack Technique & Structure des Dossiers'),
          ),
        );

        final skuTestYaml = loadYaml(
          BuildHexaPromptGenerator.extractYamlHeader(skuTest.promptMarkdown)!,
        ) as YamlMap;
        expect(skuTestYaml['kind'], 'value-object-unit-test');
        expect(
          skuTest.promptMarkdown,
          allOf(
            contains('PROD-2026-A'),
            contains('Longueur inférieure à 4 caractères'),
            contains('Égalité Structurelle, `hashCode` & Immuabilité'),
          ),
        );

        // Vérification du VO composite Shared Kernel (Money + enfant CurrencyCode)
        final moneyImpl = groups[1].prompts[0];
        final moneyImplYaml = loadYaml(
          BuildHexaPromptGenerator.extractYamlHeader(moneyImpl.promptMarkdown)!,
        ) as YamlMap;
        expect(moneyImplYaml['kind'], 'value-object-implementation');
        expect(moneyImplYaml['generation']['valueObjectKind'], 'composite');
        expect(moneyImplYaml['generation']['valueObjectScope'], 'shared');
        expect(moneyImplYaml['tags'], contains('shared-kernel'));

        final jsonMatch = RegExp(r'```json\n([\s\S]*?)\n```')
            .firstMatch(moneyImpl.promptMarkdown);
        expect(jsonMatch, isNotNull);
        final moneySchema =
            jsonDecode(jsonMatch!.group(1)!) as Map<String, Object?>;
        expect(moneySchema['title'], 'Money');
        expect(moneySchema['type'], 'object');
        expect(moneySchema['x-value-object'], 'Money');
        expect(moneySchema['x-value-object-scope'], 'shared');
        expect(
          moneyImpl.promptMarkdown,
          allOf(
            contains('amountMinorUnits'),
            contains('CurrencyCode'),
            contains('Montant négatif interdit'),
          ),
        );
      });
    },
  );

  group('BuildHexaPromptGenerator — Modes d’évolution inter-itérations', () {
    test('autoByBaseline génère le delta vN → vN+1 pour les éléments modifiés/impactés, un prompt de création pur pour les nouveaux et signale les suppressions dans les adaptateurs', () {
      final fx = _buildCatalogFixture();
      final projection = BuildDomainDesignItems.fromDomain(
        fx.domainV2,
        catalog: fx.catalogV2,
      );
      final skuItem = projection.valueObjects.firstWhere(
        (i) => i.name == 'SkuCode',
      );
      final moneyItem = projection.valueObjects.firstWhere(
        (i) => i.name == 'Money',
      );
      final productItem = projection.models.firstWhere(
        (i) => i.id == fx.productNodeId,
      );
      final publishUcItem = projection.useCases.firstWhere(
        (i) => i.id == 'uc_publish_product',
      );
      final createDiscountItem = projection.useCases.firstWhere(
        (i) => i.id == 'uc_create_discount',
      );

      final groups = BuildHexaPromptGenerator.generateGroups(
        domain: fx.domainV2,
        selectedItems: <BuildDesignItem>[
          skuItem,
          moneyItem,
          productItem,
          publishUcItem,
          createDiscountItem,
        ],
        catalog: fx.catalogV2,
        mode: BuildPromptGenerationMode.autoByBaseline,
      );

      // 1. SkuCode (unchanged) -> PAS de delta en mode autoByBaseline
      final skuGroup = groups.firstWhere((g) => g.item?.id == skuItem.id);
      for (final p in skuGroup.prompts) {
        expect(p.isEvolutionDelta, isFalse);
        expect(
          p.promptMarkdown,
          isNot(contains('## Évolution Inter-Itérations')),
        );
        final yaml = loadYaml(
          BuildHexaPromptGenerator.extractYamlHeader(p.promptMarkdown)!,
        ) as YamlMap;
        expect(yaml['generation']['mode'], isNull);
      }

      // 2. Money VO (modified major v1.0.0 -> v2.0.0) -> Delta actif
      final moneyGroup = groups.firstWhere((g) => g.item?.id == moneyItem.id);
      for (final p in moneyGroup.prompts) {
        expect(p.isEvolutionDelta, isTrue);
        expect(p.baselineLabel, 'Itération 1 — MVP');
        expect(p.baselineVersion, '1.0.0');
        expect(p.changeBump, SemVerBump.major);
        expect(
          p.promptMarkdown,
          allOf(
            contains(
              '## Évolution Inter-Itérations (Itération 1 — MVP : v1.0.0 → v2.0.0) & Consignes de Migration',
            ),
            contains('roundingMode'),
          ),
        );
        final yaml = loadYaml(
          BuildHexaPromptGenerator.extractYamlHeader(p.promptMarkdown)!,
        ) as YamlMap;
        expect(yaml['generation']['mode'], 'evolution-delta');
        expect(yaml['generation']['baselineIteration'], 'Itération 1 — MVP');
        expect(yaml['generation']['previousVersion'], '1.0.0');
        expect(yaml['generation']['changeImpact'], 'major');
      }

      // 3. Product Model (modified + impacted by Money) -> Delta Domain + Migration Persistance
      final productGroup = groups.firstWhere(
        (g) => g.item?.id == productItem.id,
      );
      expect(productGroup.prompts, hasLength(4));
      final prodDomainImpl = productGroup.prompts[0];
      final prodPersistenceImpl = productGroup.prompts[2];
      final prodPersistenceTest = productGroup.prompts[3];

      expect(prodDomainImpl.isEvolutionDelta, isTrue);
      expect(
        prodDomainImpl.promptMarkdown,
        allOf(
          contains(
            '## Évolution Inter-Itérations (Itération 1 — MVP : v1.0.0 → v1.1.0) & Consignes de Migration',
          ),
          contains('discountTag'),
          contains('changePrice(Money newPrice, String? discountTag)'),
          contains('Money'),
        ),
      );
      expect(
        prodPersistenceImpl.promptMarkdown,
        allOf(
          contains('ALTER TABLE'),
          contains('backfill'),
          contains('NOT NULL'),
        ),
      );
      expect(
        prodPersistenceTest.promptMarkdown,
        allOf(
          contains('Non-régression des tests existants'),
          contains('Tests de migration du Mapper'),
        ),
      );

      // 4. PublishProduct UseCase (impacted transitivement) -> Delta avec causes amont
      final publishGroup = groups.firstWhere(
        (g) => g.item?.id == publishUcItem.id,
      );
      expect(publishGroup.prompts.first.isEvolutionDelta, isTrue);
      expect(
        publishGroup.prompts.first.promptMarkdown,
        allOf(contains('Impact transitif'), contains('impactedBy')),
      );

      // 5. CreateDiscount UseCase (added en Itération 2) -> Création pure sans faux delta !
      final createDiscountGroup = groups.firstWhere(
        (g) => g.item?.id == createDiscountItem.id,
      );
      for (final p in createDiscountGroup.prompts) {
        expect(p.isEvolutionDelta, isFalse);
        expect(
          p.promptMarkdown,
          isNot(contains('## Évolution Inter-Itérations')),
        );
        final yaml = loadYaml(
          BuildHexaPromptGenerator.extractYamlHeader(p.promptMarkdown)!,
        ) as YamlMap;
        expect(yaml['generation']['mode'], isNull);
      }

      // 6. Adaptateurs autonomes (Outbound, Inbound, Check Integration) -> incluent OldPromo dans removedArtifacts
      for (final section in const <BuildTechStackSection>[
        BuildTechStackSection.outbound,
        BuildTechStackSection.inbound,
        BuildTechStackSection.checkIntegration,
      ]) {
        final standaloneGroup = groups.firstWhere(
          (g) => g.standaloneSection == section,
        );
        final implPrompt = standaloneGroup.prompts.first;
        expect(implPrompt.isEvolutionDelta, isTrue);
        expect(
          implPrompt.promptMarkdown,
          allOf(
            contains('## Évolution Inter-Itérations'),
            contains('OldPromo'),
            contains('removedArtifacts'),
          ),
        );
        final yaml = loadYaml(
          BuildHexaPromptGenerator.extractYamlHeader(
            implPrompt.promptMarkdown,
          )!,
        ) as YamlMap;
        expect(yaml['generation']['mode'], 'evolution-delta');
        expect(yaml['generation']['baselineIteration'], 'Itération 1 — MVP');
      }
    });

    test('evolutionDelta force la section d’évolution sur tous les éléments et fullFromScratch désactive totalement l’historique d’itération', () {
      final fx = _buildCatalogFixture();
      final projection = BuildDomainDesignItems.fromDomain(
        fx.domainV2,
        catalog: fx.catalogV2,
      );
      final skuItem = projection.valueObjects.firstWhere(
        (i) => i.name == 'SkuCode',
      );
      final moneyItem = projection.valueObjects.firstWhere(
        (i) => i.name == 'Money',
      );
      final createDiscountItem = projection.useCases.firstWhere(
        (i) => i.id == 'uc_create_discount',
      );

      // Mode evolutionDelta : même SkuCode (conforme) et CreateDiscount (nouveau) reçoivent le contexte du jalon.
      final deltaGroups = BuildHexaPromptGenerator.generateGroups(
        domain: fx.domainV2,
        selectedItems: <BuildDesignItem>[
          skuItem,
          moneyItem,
          createDiscountItem,
        ],
        catalog: fx.catalogV2,
        mode: BuildPromptGenerationMode.evolutionDelta,
        includeDomainAdapters: false,
      );
      for (final group in deltaGroups) {
        for (final prompt in group.prompts) {
          expect(prompt.isEvolutionDelta, isTrue);
          expect(
            prompt.promptMarkdown,
            contains('## Évolution Inter-Itérations'),
          );
        }
      }
      expect(
        deltaGroups[0].prompts.first.promptMarkdown,
        contains('Conforme au jalon'),
      );
      expect(
        deltaGroups[2].prompts.first.promptMarkdown,
        contains('nouvel artefact → v1.0.0'),
      );

      // Mode fullFromScratch : aucun delta ni métadonnée evolution-delta, même avec un jalon actif.
      final scratchGroups = BuildHexaPromptGenerator.generateGroups(
        domain: fx.domainV2,
        selectedItems: <BuildDesignItem>[
          skuItem,
          moneyItem,
          createDiscountItem,
        ],
        catalog: fx.catalogV2,
        mode: BuildPromptGenerationMode.fullFromScratch,
        includeDomainAdapters: true,
      );
      for (final group in scratchGroups) {
        for (final prompt in group.prompts) {
          expect(prompt.isEvolutionDelta, isFalse);
          expect(
            prompt.promptMarkdown,
            isNot(contains('## Évolution Inter-Itérations')),
          );
          final yaml = loadYaml(
            BuildHexaPromptGenerator.extractYamlHeader(prompt.promptMarkdown)!,
          ) as YamlMap;
          expect(yaml['generation']['mode'], isNull);
        }
      }
    });
  });
}
