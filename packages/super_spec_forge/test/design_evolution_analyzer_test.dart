import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('SemVerBump & métadonnées d’évolution', () {
    test(
      'ordonne none < patch < minor < major et calcule applyTo selon SemVer',
      () {
        expect(SemVerBump.none.hasChange, isFalse);
        expect(SemVerBump.patch.hasChange, isTrue);
        expect(SemVerBump.minor.hasChange, isTrue);
        expect(SemVerBump.major.hasChange, isTrue);

        expect(SemVerBump.none.label, 'Aucun');
        expect(SemVerBump.patch.label, 'Patch');
        expect(SemVerBump.minor.label, 'Mineur');
        expect(SemVerBump.major.label, 'Majeur (Breaking)');

        expect(SemVerBump.none < SemVerBump.patch, isTrue);
        expect(SemVerBump.patch < SemVerBump.minor, isTrue);
        expect(SemVerBump.minor < SemVerBump.major, isTrue);
        expect(SemVerBump.patch.max(SemVerBump.minor), SemVerBump.minor);
        expect(SemVerBump.major.max(SemVerBump.patch), SemVerBump.major);

        expect(SemVerBump.none.applyTo('0.0.1'), '0.0.1');
        expect(SemVerBump.patch.applyTo('0.0.1'), '0.0.2');
        expect(SemVerBump.minor.applyTo('0.0.1'), '0.1.0');
        expect(SemVerBump.major.applyTo('0.2.3'), '1.0.0');
        expect(SemVerBump.major.applyTo('1.2.3'), '2.0.0');
        expect(() => SemVerBump.minor.applyTo('v1.0'), throwsFormatException);

        expect(DesignEvolutionAnalyzer.compareSemVer('1.0.0', '1.0.0'), 0);
        expect(
          DesignEvolutionAnalyzer.compareSemVer('0.10.0', '0.2.9'),
          greaterThan(0),
        );
        expect(
          DesignEvolutionAnalyzer.compareSemVer('1.0.0', '2.0.0'),
          lessThan(0),
        );
      },
    );

    test(
      'expose les libellés français attendus sur ArtifactEvolutionState',
      () {
        expect(ArtifactEvolutionState.noBaseline.label, 'Sans jalon');
        expect(ArtifactEvolutionState.unchanged.label, 'Conforme');
        expect(ArtifactEvolutionState.added.label, 'Nouveau');
        expect(ArtifactEvolutionState.modified.label, 'Δ Modifié');
        expect(ArtifactEvolutionState.impacted.label, '⇄ Impacté');
        expect(ArtifactEvolutionState.removed.label, 'Supprimé');
      },
    );
  });

  group('DesignEvolutionAnalyzer.diffValueObject', () {
    test('qualifie durcissement scalaire en majeur, ajout enum en mineur et doc en patch', () {
      final baseScalar = ValueObjectSpec(
        id: 'vo_amount',
        technicalName: 'OrderAmount',
        name: 'Montant commande',
        description: 'Montant hors taxes.',
        kind: ValueObjectKind.scalar,
        primitiveType: BusinessAttributeType.number,
        schemaConstraints: JsonSchemaConstraints(minimum: 0, maximum: 10000),
      );

      // Durcissement minimum 0 -> 100 = major.
      final tightened = baseScalar.copyWith(
        schemaConstraints: JsonSchemaConstraints(minimum: 100, maximum: 10000),
      );
      final tightenDiff = DesignEvolutionAnalyzer.diffValueObject(
        baseScalar,
        tightened,
      );
      expect(DesignEvolutionAnalyzer.maxBumpOf(tightenDiff), SemVerBump.major);
      expect(
        tightenDiff.any((c) => c.summary.contains('durcissement')),
        isTrue,
      );

      // Assouplissement maximum 10000 -> 50000 = minor.
      final relaxed = baseScalar.copyWith(
        schemaConstraints: JsonSchemaConstraints(minimum: 0, maximum: 50000),
      );
      final relaxDiff = DesignEvolutionAnalyzer.diffValueObject(
        baseScalar,
        relaxed,
      );
      expect(DesignEvolutionAnalyzer.maxBumpOf(relaxDiff), SemVerBump.minor);

      // Énumération : ajout = minor, suppression = major.
      final baseEnum = ValueObjectSpec(
        id: 'vo_channel',
        technicalName: 'SalesChannel',
        name: 'Canal de vente',
        kind: ValueObjectKind.scalar,
        primitiveType: BusinessAttributeType.enumeration,
        enumValues: const <String>['WEB', 'STORE'],
      );
      final addedEnum = baseEnum.copyWith(
        enumValues: const <String>['WEB', 'STORE', 'MOBILE'],
      );
      expect(
        DesignEvolutionAnalyzer.maxBumpOf(
          DesignEvolutionAnalyzer.diffValueObject(baseEnum, addedEnum),
        ),
        SemVerBump.minor,
      );

      final removedEnum = baseEnum.copyWith(enumValues: const <String>['WEB']);
      expect(
        DesignEvolutionAnalyzer.maxBumpOf(
          DesignEvolutionAnalyzer.diffValueObject(baseEnum, removedEnum),
        ),
        SemVerBump.major,
      );

      // Documentation / exemples uniquement = patch ; version/states ignorés.
      final docOnly = baseScalar.copyWith(
        description: 'Montant HT arrondi au centime.',
        version: '1.0.1',
        states: const <ContractStage, ContractStatus>{
          ContractStage.design: ContractStatus.done,
        },
      );
      final docDiff = DesignEvolutionAnalyzer.diffValueObject(
        baseScalar,
        docOnly,
      );
      expect(DesignEvolutionAnalyzer.maxBumpOf(docDiff), SemVerBump.patch);
      expect(
        DesignEvolutionAnalyzer.diffValueObject(
          baseScalar,
          baseScalar.copyWith(
            version: '2.0.0',
            states: const <ContractStage, ContractStatus>{
              ContractStage.code: ContractStatus.done,
            },
          ),
        ),
        isEmpty,
      );
    });

    test('qualifie les évolutions d’un Value Object composite', () {
      final baseComposite = ValueObjectPresets.standardPresets.firstWhere(
        (v) => v.technicalName == 'Money',
      );

      // Ajout d'un champ optionnel = minor.
      final withOptionalField = baseComposite.copyWith(
        fields: <BusinessAttribute>[
          ...baseComposite.fields,
          BusinessAttribute(
            id: 'vo_money_scale',
            name: 'displayScale',
            type: BusinessAttributeType.integer,
            required: false,
          ),
        ],
      );
      expect(
        DesignEvolutionAnalyzer.maxBumpOf(
          DesignEvolutionAnalyzer.diffValueObject(
            baseComposite,
            withOptionalField,
          ),
        ),
        SemVerBump.minor,
      );

      // Ajout d'une règle inter-champs = major.
      final withNewCrossRule = baseComposite.copyWith(
        crossFieldRules: <String>[
          ...baseComposite.crossFieldRules,
          'amountMinorUnits <= 100000000',
        ],
      );
      expect(
        DesignEvolutionAnalyzer.maxBumpOf(
          DesignEvolutionAnalyzer.diffValueObject(
            baseComposite,
            withNewCrossRule,
          ),
        ),
        SemVerBump.major,
      );
    });
  });

  group('DesignEvolutionAnalyzer.diffModel & diffUseCase & diffSaga', () {
    test('détecte renommage/retypage DSL via entryId stable, attributs et couche Domain', () {
      final baseArtifact = SnapshotModelArtifact(
        entryId: 'node_order',
        name: 'Order',
        dslType: 'model',
        groupName: 'models',
        title: 'Commande',
        version: '1.0.0',
        objectSpec: BusinessObjectSpec(
          id: 'node_order',
          name: 'Commande',
          technicalName: 'Order',
          attributes: <BusinessAttribute>[
            BusinessAttribute(
              id: 'a_id',
              name: 'orderId',
              type: BusinessAttributeType.uuid,
              required: true,
            ),
          ],
          lifecycleStates: const <LifecycleState>[
            LifecycleState(name: 'DRAFT', isInitial: true),
            LifecycleState(name: 'CONFIRMED'),
          ],
        ),
        domainLayerSpec: HexagonalDomainLayerSpec(
          stateChanges: <DomainStateChangeSpec>[
            DomainStateChangeSpec(id: 'cmd_cancel', name: 'cancelOrder'),
          ],
        ),
      );

      // Ajout d'un attribut optionnel et d'une query Domain = minor.
      final minorEvolution = baseArtifact.copyWith(
        objectSpec: baseArtifact.objectSpec.copyWith(
          attributes: <BusinessAttribute>[
            ...baseArtifact.objectSpec.attributes,
            BusinessAttribute(
              id: 'a_points',
              name: 'loyaltyPoints',
              type: BusinessAttributeType.integer,
              required: false,
            ),
          ],
        ),
        domainLayerSpec: baseArtifact.domainLayerSpec.copyWith(
          queries: <DomainQuerySpec>[
            DomainQuerySpec(id: 'qry_total', name: 'isEligibleForDiscount'),
          ],
        ),
      );
      final minorDiff = DesignEvolutionAnalyzer.diffModel(
        previous: baseArtifact,
        current: minorEvolution,
      );
      expect(DesignEvolutionAnalyzer.maxBumpOf(minorDiff), SemVerBump.minor);

      // Renommage DSL, suppression de méthode Domain et ajout d'invariant = major.
      final majorEvolution = baseArtifact.copyWith(
        name: 'CustomerOrder',
        dslType: 'component',
        domainLayerSpec: HexagonalDomainLayerSpec(
          invariants: <DomainInvariantSpec>[
            DomainInvariantSpec(
              id: 'inv_1',
              code: 'INV-01',
              title: 'Total positif',
              expression: 'total >= 0',
            ),
          ],
          stateChanges: const <DomainStateChangeSpec>[],
        ),
      );
      final majorDiff = DesignEvolutionAnalyzer.diffModel(
        previous: baseArtifact,
        current: majorEvolution,
      );
      expect(DesignEvolutionAnalyzer.maxBumpOf(majorDiff), SemVerBump.major);
      expect(
        majorDiff.any(
          (c) => c.summary.contains("Nom DSL 'Order' → 'CustomerOrder'"),
        ),
        isTrue,
      );
      expect(
        majorDiff.any((c) => c.summary.contains("cancelOrder' supprimée")),
        isTrue,
      );

      // Surcharge directe diffModelSpecs.
      final specsDiff = DesignEvolutionAnalyzer.diffModelSpecs(
        previousObject: baseArtifact.objectSpec,
        currentObject: baseArtifact.objectSpec.copyWith(
          description: 'Commande B2B enrichie.',
        ),
        previousDomainLayer: baseArtifact.domainLayerSpec,
        currentDomainLayer: baseArtifact.domainLayerSpec,
      );
      expect(DesignEvolutionAnalyzer.maxBumpOf(specsDiff), SemVerBump.patch);
    });

    test('qualifie les évolutions de Use Case et de Saga', () {
      final baseUc = ApplicationUseCaseSpec(
        id: 'uc_1',
        code: 'UC-001',
        name: 'PlaceOrder',
        title: 'Passer commande',
        version: '1.0.0',
        cqrsType: UseCaseCqrsType.command,
        targetAggregate: 'Order',
        inboundPort: 'PlaceOrderUseCase',
        outboundPorts: const <String>['OrderRepository', 'EventBus'],
        triggerInputs: const <UseCaseFieldSpec>[
          UseCaseFieldSpec(name: 'customerId', type: 'uuid', required: true),
        ],
        outputs: const <UseCaseFieldSpec>[
          UseCaseFieldSpec(name: 'orderId', type: 'uuid', required: true),
        ],
      );

      // Entrée optionnelle + événement émis = minor.
      final ucMinor = baseUc.copyWith(
        triggerInputs: <UseCaseFieldSpec>[
          ...baseUc.triggerInputs,
          const UseCaseFieldSpec(
            name: 'couponCode',
            type: 'string',
            required: false,
          ),
        ],
        emittedEvents: const <String>['OrderPlaced'],
      );
      expect(
        DesignEvolutionAnalyzer.maxBumpOf(
          DesignEvolutionAnalyzer.diffUseCase(baseUc, ucMinor),
        ),
        SemVerBump.minor,
      );

      // Retrait d'un port sortant ou entrée obligatoire ajoutée = major.
      final ucMajor = baseUc.copyWith(
        outboundPorts: const <String>['OrderRepository'],
      );
      expect(
        DesignEvolutionAnalyzer.maxBumpOf(
          DesignEvolutionAnalyzer.diffUseCase(baseUc, ucMajor),
        ),
        SemVerBump.major,
      );

      final baseSaga = OrchestrationSagaSpec(
        id: 'saga_1',
        code: 'SAGA-001',
        name: 'OrderSaga',
        title: 'Orchestration commande',
        version: '1.0.0',
        boundedContexts: const <String>['Ventes'],
        triggerEventOrCommand: 'OrderPlaced',
        correlationKey: 'orderId',
        compensationMatrix: const <SagaCompensationRow>[
          SagaCompensationRow(
            id: 'step_1',
            step: '1. Réserver stock',
            nominalAction: 'ReserveStock',
            compensationAction: 'ReleaseStock',
          ),
        ],
      );

      // Nouvelle étape + participant étendu = minor.
      final sagaMinor = baseSaga.copyWith(
        boundedContexts: const <String>['Ventes', 'Logistique'],
        compensationMatrix: <SagaCompensationRow>[
          ...baseSaga.compensationMatrix,
          const SagaCompensationRow(
            id: 'step_2',
            step: '2. Débiter paiement',
            nominalAction: 'CapturePayment',
            compensationAction: 'RefundPayment',
          ),
        ],
      );
      expect(
        DesignEvolutionAnalyzer.maxBumpOf(
          DesignEvolutionAnalyzer.diffSaga(baseSaga, sagaMinor),
        ),
        SemVerBump.minor,
      );

      // Modification de l'action de compensation = major.
      final sagaMajor = baseSaga.copyWith(
        compensationMatrix: <SagaCompensationRow>[
          baseSaga.compensationMatrix.first.copyWith(
            compensationAction: 'CancelReservationWithPenalty',
          ),
        ],
      );
      expect(
        DesignEvolutionAnalyzer.maxBumpOf(
          DesignEvolutionAnalyzer.diffSaga(baseSaga, sagaMajor),
        ),
        SemVerBump.major,
      );

      // Mermaid mis à jour uniquement = patch.
      final sagaPatch = baseSaga.copyWith(
        mermaidDiagram: 'sequenceDiagram\n  Ventes->>Logistique: ReserveStock',
      );
      expect(
        DesignEvolutionAnalyzer.maxBumpOf(
          DesignEvolutionAnalyzer.diffSaga(baseSaga, sagaPatch),
        ),
        SemVerBump.patch,
      );
    });
  });

  group('DesignEvolutionAnalyzer.analyzeDomain (graphe d’impact transitif)', () {
    test('propage Shared VO -> Composite VO -> Modèle -> Modèle référent -> UseCase -> Saga et détecte les suppressions', () {
      final sharedMoney = ValueObjectPresets.standardPresets
          .firstWhere((v) => v.technicalName == 'Money')
          .copyWith(id: 'vo_shared_money', version: '1.0.0');
      final domainPriceTag = ValueObjectSpec(
        id: 'vo_price_tag',
        technicalName: 'PriceTag',
        name: 'Étiquette tarifaire',
        version: '1.0.0',
        kind: ValueObjectKind.composite,
        fields: <BusinessAttribute>[
          BusinessAttribute(
            id: 'f_unit_price',
            name: 'unitPrice',
            type: BusinessAttributeType.valueObject,
            valueObjectId: sharedMoney.id,
            required: true,
          ),
        ],
      );
      final removedVo = ValueObjectSpec(
        id: 'vo_legacy_tax',
        technicalName: 'LegacyTaxCode',
        name: 'Ancien code taxe',
        version: '1.0.0',
      );

      var contracts = DomainContracts.parse(
        'models:\n'
        '  Product: model\n'
        '  OrderLine: model\n'
        '  ObsoleteCoupon: model\n',
      );
      final nodes = contracts.groups.first.children;
      final productNode = nodes.firstWhere((n) => n.name == 'Product');
      final orderLineNode = nodes.firstWhere((n) => n.name == 'OrderLine');
      final couponNode = nodes.firstWhere((n) => n.name == 'ObsoleteCoupon');

      contracts = contracts
          .edit(
            productNode,
            'model',
            ContractDetails(title: 'Produit', version: '1.0.0'),
          )
          .edit(
            orderLineNode,
            'model',
            ContractDetails(title: 'Ligne de commande', version: '1.0.0'),
          )
          .edit(
            couponNode,
            'model',
            ContractDetails(title: 'Coupon obsolète', version: '1.0.0'),
          )
          .withModel(
            productNode.id,
            object: BusinessObjectSpec(
              id: productNode.id,
              name: 'Produit',
              technicalName: 'Product',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'p_price',
                  name: 'priceTag',
                  type: BusinessAttributeType.valueObject,
                  valueObjectId: domainPriceTag.id,
                  required: true,
                ),
              ],
            ),
          )
          .withModel(
            orderLineNode.id,
            object: BusinessObjectSpec(
              id: orderLineNode.id,
              name: 'Ligne de commande',
              technicalName: 'OrderLine',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'ol_product',
                  name: 'product',
                  type: BusinessAttributeType.reference,
                  referenceObjectId: productNode.id,
                  required: true,
                ),
              ],
            ),
          );

      final updatePriceUc = ApplicationUseCaseSpec(
        id: 'uc_update_price',
        code: 'UC-001',
        name: 'UpdateProductPrice',
        title: 'Mettre à jour le prix produit',
        version: '0.0.1',
        targetAggregate: 'Product',
      );
      final orderSaga = OrchestrationSagaSpec(
        id: 'saga_order',
        code: 'SAGA-001',
        name: 'OrderRepricingSaga',
        title: 'Recalcul tarifaire des commandes',
        version: '0.0.1',
        compensationMatrix: const <SagaCompensationRow>[
          SagaCompensationRow(
            id: 'row_1',
            step: '1. Appliquer nouveau tarif via UC-001',
            nominalAction: 'UpdateProductPrice',
            compensationAction: 'RestorePreviousPrice',
          ),
        ],
      );

      final iter1Domain = FunctionalDomain(
        id: 'dom_catalog',
        domainCode: 'catalog',
        name: 'Catalogue',
        contracts: contracts,
        valueObjects: <ValueObjectSpec>[domainPriceTag, removedVo],
        useCaseOrchestration: UseCaseOrchestrationSpec(
          useCases: <ApplicationUseCaseSpec>[updatePriceUc],
          sagas: <OrchestrationSagaSpec>[orderSaga],
        ),
      );
      final iter1Catalog = DomainCatalog(
        domains: <FunctionalDomain>[iter1Domain],
        sharedValueObjects: <ValueObjectSpec>[sharedMoney],
      );

      // Sans baseline : tous les items sont en état `noBaseline`.
      final noBaselineReport = DesignEvolutionAnalyzer.analyzeDomain(
        domain: iter1Domain,
        catalog: iter1Catalog,
      );
      expect(noBaselineReport.hasBaseline, isFalse);
      expect(
        noBaselineReport.models[productNode.id]?.state,
        ArtifactEvolutionState.noBaseline,
      );

      // Capture du jalon Itération 1.
      final snap1 = DomainIterationSnapshot.capture(
        id: 'snap_1',
        iterationNumber: 1,
        label: 'Itération 1',
        createdAt: DateTime.utc(2026, 11, 27, 10),
        domain: iter1Domain,
        catalog: iter1Catalog,
      );

      // Itération 2 :
      // - Money dans le Shared Kernel subit un durcissement majeur (minimum 0 -> 100) ;
      // - LegacyTaxCode et ObsoleteCoupon sont supprimés ;
      // - Un nouveau modèle PromotionBanner est ajouté.
      final sharedMoneyV2 = sharedMoney.copyWith(
        fields: <BusinessAttribute>[
          sharedMoney.fields.first.copyWith(
            schemaConstraints: JsonSchemaConstraints(minimum: 100),
          ),
          sharedMoney.fields.last,
        ],
      );
      final contractsV2 = contracts
          .patch(
            'models:\n'
            '  Product: model\n'
            '  OrderLine: model\n',
          )
          .patch(
            'models:\n'
            '  Product: model\n'
            '  OrderLine: model\n'
            '  PromotionBanner: model\n',
          );
      final promoNode = contractsV2.groups.first.children.firstWhere(
        (n) => n.name == 'PromotionBanner',
      );

      final iter2Domain = iter1Domain.copyWith(
        contracts: contractsV2,
        valueObjects: <ValueObjectSpec>[domainPriceTag],
        iterationSnapshots: <DomainIterationSnapshot>[snap1],
        activeBaselineSnapshotId: snap1.id,
      );
      final iter2Catalog = iter1Catalog.copyWith(
        domains: <FunctionalDomain>[iter2Domain],
        sharedValueObjects: <ValueObjectSpec>[sharedMoneyV2],
      );

      final report = DesignEvolutionAnalyzer.analyzeDomain(
        domain: iter2Domain,
        catalog: iter2Catalog,
      );

      expect(report.hasBaseline, isTrue);
      expect(report.addedCount, 1); // PromotionBanner
      expect(report.modifiedCount, 1); // Money
      expect(
        report.impactedCount,
        5,
      ); // PriceTag, Product, OrderLine, UpdateProductPrice, OrderRepricingSaga
      expect(report.removedCount, 2); // LegacyTaxCode, ObsoleteCoupon
      expect(report.totalActionableCount, 7);

      final moneyReport = report.valueObjects[sharedMoney.id]!;
      expect(moneyReport.state, ArtifactEvolutionState.modified);
      expect(moneyReport.valueObjectScope, ValueObjectScope.shared);
      expect(moneyReport.directBump, SemVerBump.major);
      expect(moneyReport.effectiveBump, SemVerBump.major);
      expect(moneyReport.recommendedVersion, '2.0.0');
      expect(moneyReport.needsVersionBump, isTrue);

      final priceTagReport = report.valueObjects[domainPriceTag.id]!;
      expect(priceTagReport.state, ArtifactEvolutionState.impacted);
      expect(priceTagReport.effectiveBump, SemVerBump.major);
      expect(priceTagReport.recommendedVersion, '2.0.0');
      expect(
        priceTagReport.impactedBy,
        contains('Value Object Money (v1.0.0 → v2.0.0 · Majeur)'),
      );

      final productReport = report.models[productNode.id]!;
      expect(productReport.state, ArtifactEvolutionState.impacted);
      expect(productReport.effectiveBump, SemVerBump.major);
      expect(productReport.recommendedVersion, '2.0.0');
      expect(
        productReport.impactedBy,
        contains('Value Object PriceTag (v1.0.0 → v2.0.0 · Majeur)'),
      );

      final orderLineReport = report.models[orderLineNode.id]!;
      expect(orderLineReport.state, ArtifactEvolutionState.impacted);
      expect(
        orderLineReport.impactedBy,
        contains('Modèle Product (v1.0.0 → v2.0.0 · Majeur)'),
      );

      final ucReport = report.useCases[updatePriceUc.id]!;
      expect(ucReport.state, ArtifactEvolutionState.impacted);
      expect(ucReport.effectiveBump, SemVerBump.major);
      expect(ucReport.recommendedVersion, '1.0.0');
      expect(
        ucReport.impactedBy,
        contains('Modèle Product (v1.0.0 → v2.0.0 · Majeur)'),
      );

      final sagaReport = report.sagas[orderSaga.id]!;
      expect(sagaReport.state, ArtifactEvolutionState.impacted);
      expect(sagaReport.effectiveBump, SemVerBump.major);
      expect(sagaReport.recommendedVersion, '1.0.0');
      expect(
        sagaReport.impactedBy,
        contains('Use Case UpdateProductPrice (v0.0.1 → v1.0.0 · Majeur)'),
      );

      expect(report.models[promoNode.id]?.state, ArtifactEvolutionState.added);
      expect(
        report.reportFor(DesignArtifactKind.valueObject, removedVo.id)?.state,
        ArtifactEvolutionState.removed,
      );
      expect(
        report.reportFor(DesignArtifactKind.model, couponNode.id)?.state,
        ArtifactEvolutionState.removed,
      );
    });

    test('gère l’impact d’un VO supprimé, les ports Repository, la fusion directBump+upstream et l’absence d’écho circulaire', () {
      final taxVo = ValueObjectSpec(
        id: 'vo_tax',
        technicalName: 'VatRate',
        name: 'Taux de TVA',
        version: '1.0.0',
      );
      var contracts = DomainContracts.parse(
        'models:\n'
        '  Order: model\n'
        '  Customer: model\n',
      );
      final orderNode = contracts.groups.first.children.firstWhere(
        (n) => n.name == 'Order',
      );
      final customerNode = contracts.groups.first.children.firstWhere(
        (n) => n.name == 'Customer',
      );

      contracts = contracts
          .edit(
            orderNode,
            'model',
            ContractDetails(title: 'Commande', version: '1.0.0'),
          )
          .edit(
            customerNode,
            'model',
            ContractDetails(title: 'Client', version: '1.0.0'),
          )
          .withModel(
            orderNode.id,
            object: BusinessObjectSpec(
              id: orderNode.id,
              name: 'Commande',
              technicalName: 'Order',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'a_vat',
                  name: 'vatRate',
                  type: BusinessAttributeType.valueObject,
                  valueObjectId: 'VatRate',
                ),
                BusinessAttribute(
                  id: 'a_cust',
                  name: 'customer',
                  type: BusinessAttributeType.reference,
                  referenceObjectId: customerNode.id,
                ),
              ],
            ),
          )
          .withDomainLayer(
            orderNode.id,
            layer: HexagonalDomainLayerSpec(
              persistencePolicy: DomainPersistencePolicySpec(
                repositoryPortName: 'CustomOrderPort',
              ),
            ),
          )
          .withModel(
            customerNode.id,
            object: BusinessObjectSpec(
              id: customerNode.id,
              name: 'Client',
              technicalName: 'Customer',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'a_last_order',
                  name: 'lastOrder',
                  type: BusinessAttributeType.reference,
                  referenceObjectId: orderNode.id,
                ),
              ],
            ),
          );

      final auditUc = ApplicationUseCaseSpec(
        id: 'uc_audit',
        code: 'UC-099',
        name: 'AuditOrders',
        title: 'Auditer les commandes',
        version: '1.0.0',
        cqrsType: UseCaseCqrsType.query,
        outboundPorts: const <String>['CustomOrderPort'],
      );

      final baseDomain = FunctionalDomain(
        id: 'dom_sales',
        domainCode: 'sales',
        name: 'Ventes',
        contracts: contracts,
        valueObjects: <ValueObjectSpec>[taxVo],
        useCaseOrchestration: UseCaseOrchestrationSpec(
          useCases: <ApplicationUseCaseSpec>[auditUc],
        ),
      );
      final snap = DomainIterationSnapshot.capture(
        id: 'snap_1',
        iterationNumber: 1,
        label: 'Baseline',
        createdAt: DateTime.utc(2026, 11, 27),
        domain: baseDomain,
      );

      // En itération 2 : VatRate est supprimé, et Order subit aussi un changement patch (titre).
      final contractsV2 = contracts.edit(
        orderNode,
        'model',
        ContractDetails(title: 'Commande client B2B', version: '1.0.0'),
      );
      final iter2Domain = baseDomain.copyWith(
        contracts: contractsV2,
        valueObjects: const <ValueObjectSpec>[],
        iterationSnapshots: <DomainIterationSnapshot>[snap],
        activeBaselineSnapshotId: snap.id,
      );

      final evo = DesignEvolutionAnalyzer.analyzeDomain(domain: iter2Domain);
      final orderRep = evo.models[orderNode.id]!;
      final customerRep = evo.models[customerNode.id]!;
      final ucRep = evo.useCases[auditUc.id]!;

      // Order est `modified` (directBump: patch) + impacté par VatRate supprimé (effectiveBump: major),
      // sans écho circulaire depuis Customer.
      expect(orderRep.state, ArtifactEvolutionState.modified);
      expect(orderRep.directBump, SemVerBump.patch);
      expect(orderRep.effectiveBump, SemVerBump.major);
      expect(orderRep.recommendedVersion, '2.0.0');
      expect(
        orderRep.impactedBy,
        equals(<String>['Value Object VatRate (Supprimé · Majeur)']),
      );

      // Customer est impacté par Order, sans re-boucler vers Order.
      expect(customerRep.state, ArtifactEvolutionState.impacted);
      expect(customerRep.effectiveBump, SemVerBump.major);
      expect(
        customerRep.impactedBy,
        equals(<String>['Modèle Order (v1.0.0 → v2.0.0 · Majeur)']),
      );

      // AuditOrders est impacté via son port sortant CustomOrderPort.
      expect(ucRep.state, ArtifactEvolutionState.impacted);
      expect(ucRep.effectiveBump, SemVerBump.major);
      expect(ucRep.recommendedVersion, '2.0.0');
    });
  });

  group('SpecForgeController (snapshots, statuts VO & SemVer bump 1-clic)', () {
    test('gère le cycle complet des snapshots, statuts de ValueObject et bumps de version avec persistance DomainCatalogStore', () async {
      final scratchDir = Directory(
        '.dart_tool${Platform.pathSeparator}test_design_evolution_${DateTime.now().microsecondsSinceEpoch}',
      );
      await scratchDir.create(recursive: true);
      addTearDown(() async {
        if (await scratchDir.exists()) {
          await scratchDir.delete(recursive: true);
        }
      });

      final projectStore = SpecProjectStore(scratchDir);
      final domainCatalogStore = DomainCatalogStore(scratchDir);
      final controller = SpecForgeController(
        store: projectStore,
        domainCatalogStore: domainCatalogStore,
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      final domain = await controller.createFunctionalDomain(
        domainCode: 'sales',
        name: 'Ventes',
      );

      final sharedEmail = ValueObjectPresets.standardPresets
          .firstWhere((v) => v.technicalName == 'EmailAddress')
          .copyWith(id: 'vo_shared_email', version: '1.0.0');
      final domainDiscount = ValueObjectSpec(
        id: 'vo_discount',
        technicalName: 'DiscountRate',
        name: 'Taux de remise',
        version: '1.0.0',
        kind: ValueObjectKind.scalar,
        primitiveType: BusinessAttributeType.number,
        schemaConstraints: JsonSchemaConstraints(minimum: 0, maximum: 50),
      );
      await controller.upsertValueObject(
        sharedEmail,
        scope: ValueObjectScope.shared,
      );
      await controller.upsertValueObject(
        domainDiscount,
        scope: ValueObjectScope.domain,
        domainId: domain.id,
      );

      // Cycle des indicateurs d'avancement d'un Value Object (shared et domain).
      await controller.updateValueObjectStageStatus(
        voId: sharedEmail.id,
        scope: ValueObjectScope.shared,
        stage: ContractStage.design,
      );
      expect(
        controller.domainCatalog.sharedValueObjects.single.statusOf(
          ContractStage.design,
        ),
        ContractStatus.inProgress,
      );
      await controller.updateValueObjectStageStatus(
        voId: sharedEmail.id,
        scope: ValueObjectScope.shared,
        stage: ContractStage.design,
      );
      expect(
        controller.domainCatalog.sharedValueObjects.single.statusOf(
          ContractStage.design,
        ),
        ContractStatus.done,
      );
      await controller.updateValueObjectStageStatus(
        voId: domainDiscount.id,
        scope: ValueObjectScope.domain,
        domainId: domain.id,
        stage: ContractStage.validation,
        status: ContractStatus.done,
      );

      var contracts = DomainContracts.parse('models:\n  Quote: model\n');
      final quoteNode = contracts.groups.first.children.single;
      contracts = contracts
          .edit(
            quoteNode,
            'model',
            ContractDetails(
              title: 'Devis commercial',
              version: '1.0.0',
              states: const <ContractStage, ContractStatus>{
                ContractStage.design: ContractStatus.done,
              },
            ),
          )
          .withModel(
            quoteNode.id,
            object: BusinessObjectSpec(
              id: quoteNode.id,
              name: 'Devis commercial',
              technicalName: 'Quote',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'q_discount',
                  name: 'discount',
                  type: BusinessAttributeType.valueObject,
                  valueObjectId: domainDiscount.id,
                ),
              ],
            ),
          );
      await controller.updateDomainContracts(domain.id, contracts);

      final approveUc = ApplicationUseCaseSpec(
        id: 'uc_approve_quote',
        code: 'UC-010',
        name: 'ApproveQuote',
        title: 'Valider le devis',
        version: '1.0.0',
        targetAggregate: 'Quote',
        states: const <ContractStage, ContractStatus>{
          ContractStage.design: ContractStatus.done,
        },
      );
      final quoteSaga = OrchestrationSagaSpec(
        id: 'saga_quote',
        code: 'SAGA-010',
        name: 'QuoteApprovalSaga',
        title: 'Approbation devis',
        version: '1.0.0',
        triggerEventOrCommand: 'ApproveQuote',
        states: const <ContractStage, ContractStatus>{
          ContractStage.validation: ContractStatus.inProgress,
        },
      );
      await controller.updateUseCaseOrchestration(
        domain.id,
        UseCaseOrchestrationSpec(
          useCases: <ApplicationUseCaseSpec>[approveUc],
          sagas: <OrchestrationSagaSpec>[quoteSaga],
        ),
      );

      // Création de deux snapshots d'itération.
      final snap1 = await controller.createDomainIterationSnapshot(
        domain.id,
        label: 'Itération 1 — Cadrage Devis',
        notes: 'Premier jalon stable',
      );
      expect(snap1.iterationNumber, 1);

      // Évolution mineure sur DiscountRate (assouplissement max 50 -> 80).
      await controller.upsertValueObject(
        domainDiscount.copyWith(
          schemaConstraints: JsonSchemaConstraints(minimum: 0, maximum: 80),
          states: const <ContractStage, ContractStatus>{
            ContractStage.validation: ContractStatus.done,
          },
        ),
        scope: ValueObjectScope.domain,
        domainId: domain.id,
      );

      final snap2 = await controller.createDomainIterationSnapshot(
        domain.id,
        label: 'Itération 2 — Remises étendues',
        activateAsBaseline: false,
      );
      expect(snap2.iterationNumber, 2);

      // Baseline active = snap1 -> DiscountRate est modified (minor), Quote/UC/Saga sont impacted (minor).
      var evo = controller.analyzeDomainEvolution(domain.id);
      expect(evo.baseline?.id, snap1.id);
      expect(evo.valueObjects[domainDiscount.id]?.recommendedVersion, '1.1.0');
      expect(evo.valueObjects[domainDiscount.id]?.needsVersionBump, isTrue);
      expect(evo.models[quoteNode.id]?.recommendedVersion, '1.1.0');
      expect(evo.useCases[approveUc.id]?.recommendedVersion, '1.1.0');
      expect(evo.sagas[quoteSaga.id]?.recommendedVersion, '1.1.0');

      // Application du bump SemVer 1-clic sur les 4 types d'artefacts sans toucher aux states !
      await controller.applyDesignArtifactVersionBump(
        domainId: domain.id,
        kind: DesignArtifactKind.valueObject,
        artifactId: domainDiscount.id,
        newVersion: '1.1.0',
        valueObjectScope: ValueObjectScope.domain,
      );
      await controller.applyDesignArtifactVersionBump(
        domainId: domain.id,
        kind: DesignArtifactKind.model,
        artifactId: quoteNode.id,
        newVersion: '1.1.0',
      );
      await controller.applyDesignArtifactVersionBump(
        domainId: domain.id,
        kind: DesignArtifactKind.useCase,
        artifactId: approveUc.id,
        newVersion: '1.1.0',
      );
      await controller.applyDesignArtifactVersionBump(
        domainId: domain.id,
        kind: DesignArtifactKind.saga,
        artifactId: quoteSaga.id,
        newVersion: '1.1.0',
      );

      evo = controller.analyzeDomainEvolution(domain.id);
      expect(evo.valueObjects[domainDiscount.id]?.needsVersionBump, isFalse);
      expect(evo.models[quoteNode.id]?.needsVersionBump, isFalse);
      expect(evo.useCases[approveUc.id]?.needsVersionBump, isFalse);
      expect(evo.sagas[quoteSaga.id]?.needsVersionBump, isFalse);

      // Vérifie que les states de tous les artefacts ont été intégralement préservés.
      final updatedDomain = controller.domainCatalog.domains.single;
      expect(
        updatedDomain.valueObjects.single.statusOf(ContractStage.validation),
        ContractStatus.done,
      );
      expect(
        updatedDomain.contracts!.details[quoteNode.id]!.states[ContractStage
            .design],
        ContractStatus.done,
      );
      expect(
        updatedDomain.useCaseOrchestration!.useCases.single.states[ContractStage
            .design],
        ContractStatus.done,
      );
      expect(
        updatedDomain.useCaseOrchestration!.sagas.single.states[ContractStage
            .validation],
        ContractStatus.inProgress,
      );

      // Bascule de baseline active vers snap2, puis suppression de snap2 -> repli auto sur snap1.
      await controller.setActiveBaselineSnapshot(domain.id, snap2.id);
      expect(
        controller.domainCatalog.domains.single.activeBaselineSnapshotId,
        snap2.id,
      );
      await controller.deleteDomainIterationSnapshot(domain.id, snap2.id);
      expect(
        controller.domainCatalog.domains.single.activeBaselineSnapshotId,
        snap1.id,
      );

      // Suppression du dernier snapshot -> baseline active redevient null.
      await controller.deleteDomainIterationSnapshot(domain.id, snap1.id);
      expect(
        controller.domainCatalog.domains.single.activeBaselineSnapshotId,
        isNull,
      );

      // Rechargement complet depuis DomainCatalogStore (vérifie le journal d'audit append-only).
      final reloaded = await domainCatalogStore.load();
      expect(reloaded.domains.single.id, domain.id);
      expect(reloaded.auditLog.length, greaterThanOrEqualTo(7));
    });
  });
}
