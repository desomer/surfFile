import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('contract_stage helpers', () {
    test('sérialise et désérialise les états en mode souple et strict', () {
      const states = <ContractStage, ContractStatus>{
        ContractStage.design: ContractStatus.done,
        ContractStage.validation: ContractStatus.inProgress,
      };
      final json = contractStatesToJson(states);
      expect(json, <String, String>{
        'design': 'done',
        'validation': 'inProgress',
      });

      expect(parseContractStatesJson(json, strict: true), equals(states));
      expect(parseContractStatesJson(null), isEmpty);
      expect(
        parseContractStatesJson(<String, Object?>{
          'design': 'done',
          'unknownStage': 'done',
          'code': 'unknownStatus',
        }),
        equals(const <ContractStage, ContractStatus>{
          ContractStage.design: ContractStatus.done,
        }),
      );
      expect(
        () => parseContractStatesJson(<String, Object?>{
          'unknownStage': 'done',
        }, strict: true),
        throwsFormatException,
      );
      expect(
        () => parseContractStatesJson('not-a-map', strict: true),
        throwsFormatException,
      );
      expect(nextContractStatus(null), ContractStatus.inProgress);
      expect(
        nextContractStatus(ContractStatus.inProgress),
        ContractStatus.done,
      );
      expect(nextContractStatus(ContractStatus.done), ContractStatus.pending);
    });
  });

  group('ValueObjectSpec.states', () {
    test(
      'aller-retour JSON et rétrocompatibilité lorsque states est absent',
      () {
        final preset = ValueObjectPresets.standardPresets.firstWhere(
          (v) => v.technicalName == 'EmailAddress',
        );
        expect(preset.states, isEmpty);
        expect(preset.statusOf(ContractStage.design), ContractStatus.pending);
        expect(preset.toJson().containsKey('states'), isFalse);

        // Legacy JSON sans clé 'states'.
        final fromLegacy = ValueObjectSpec.fromJson(preset.toJson());
        expect(fromLegacy, equals(preset));
        expect(fromLegacy.states, isEmpty);

        // Avec états renseignés.
        final withStates = preset.copyWith(
          states: const <ContractStage, ContractStatus>{
            ContractStage.design: ContractStatus.done,
            ContractStage.code: ContractStatus.inProgress,
          },
        );
        expect(withStates.statusOf(ContractStage.design), ContractStatus.done);
        expect(
          withStates.statusOf(ContractStage.code),
          ContractStatus.inProgress,
        );
        expect(
          withStates.statusOf(ContractStage.delivery),
          ContractStatus.pending,
        );
        expect(withStates, isNot(equals(preset)));

        final serialized = withStates.toJson();
        expect(serialized['states'], <String, String>{
          'design': 'done',
          'code': 'inProgress',
        });

        final restored = ValueObjectSpec.fromJson(serialized);
        expect(restored, equals(withStates));
        expect(restored.hashCode, equals(withStates.hashCode));
      },
    );
  });

  group('SpecOriginBaseline & ContractDetails.specOrigin', () {
    BusinessObjectSpec buildSampleObject() => BusinessObjectSpec(
      id: 'obj_invoice',
      name: 'Facture client',
      technicalName: 'CustomerInvoice',
      description: 'Facture émise au client.',
      attributes: <BusinessAttribute>[
        BusinessAttribute(
          id: 'attr_total',
          name: 'totalAmount',
          type: BusinessAttributeType.number,
          required: true,
        ),
      ],
    );

    test('calcule une empreinte déterministe sensible aux changements RG', () {
      final ruleA = BusinessRuleSpec(
        id: 'r1',
        code: 'RG-001',
        title: 'Montant strictement positif',
        category: BusinessRuleCategory.validation,
        priority: BusinessRulePriority.critical,
        trigger: 'À l’émission de la facture',
        condition: 'totalAmount <= 0',
        effect: 'Rejeter l’émission',
        targetObjectIds: const <String>['obj_b', 'obj_a'],
        targetAttributes: const <String>['CustomerInvoice.totalAmount'],
      );
      final ruleSameReordered = ruleA.copyWith(
        id: 'r_other_internal_id',
        targetObjectIds: const <String>['obj_a', 'obj_b'],
      );
      final ruleModified = ruleA.copyWith(condition: 'totalAmount < 0');

      final fpA = SpecOriginBaseline.computeRuleFingerprint(ruleA);
      final fpSame = SpecOriginBaseline.computeRuleFingerprint(
        ruleSameReordered,
      );
      final fpModified = SpecOriginBaseline.computeRuleFingerprint(
        ruleModified,
      );

      expect(fpA, isNotEmpty);
      expect(fpA, equals(fpSame));
      expect(fpModified, isNot(equals(fpA)));
    });

    test('aller-retour JSON et rétrocompatibilité de ContractDetails', () {
      // Legacy ContractDetails JSON sans specOrigin.
      final legacyJson = <String, Object?>{
        'title': 'Facture',
        'version': '1.2.0',
        'states': <String, String>{'design': 'done'},
      };
      final legacyDetails = ContractDetails.fromJson(legacyJson);
      expect(legacyDetails.specOrigin, isNull);
      expect(legacyDetails.toJson().containsKey('specOrigin'), isFalse);

      final localDate = DateTime(2026, 11, 27, 19, 30, 0);
      final origin = SpecOriginBaseline(
        projectId: 'proj_erp',
        projectName: 'ERP Facturation',
        featureId: 'feat_invoicing',
        featureCode: 'FEAT-01',
        specObjectId: 'obj_invoice',
        promotedAt: localDate,
        baseSpecObject: buildSampleObject(),
        ruleFingerprints: const <String, String>{
          'RG-001': 'RG-001 | validation | critical | active',
        },
      );
      expect(origin.promotedAt.isUtc, isTrue);
      origin.validate();

      final detailsWithOrigin = legacyDetails.copyWith(specOrigin: origin);
      final json = detailsWithOrigin.toJson();
      expect(json.containsKey('specOrigin'), isTrue);

      final restored = ContractDetails.fromJson(json);
      expect(restored, equals(detailsWithOrigin));
      expect(restored.hashCode, equals(detailsWithOrigin.hashCode));
      expect(restored.specOrigin, equals(origin));

      final cleared = restored.copyWith(clearSpecOrigin: true);
      expect(cleared.specOrigin, isNull);
      expect(cleared, equals(legacyDetails));

      expect(
        () => origin.copyWith(projectId: '  ').validate(),
        throwsFormatException,
      );
      expect(
        () => origin.copyWith(specObjectId: '').validate(),
        throwsFormatException,
      );
    });
  });

  group('DomainIterationSnapshot & FunctionalDomain', () {
    test('capture un domaine riche (Shared Kernel + Domaine VOs, Contrats, Couche Domain, UseCases, Sagas) et persiste via DomainCatalog', () {
      final sharedEmail = ValueObjectPresets.standardPresets.firstWhere(
        (v) => v.technicalName == 'EmailAddress',
      );
      final sharedMoney = ValueObjectPresets.standardPresets.firstWhere(
        (v) => v.technicalName == 'Money',
      );
      final domainMoney = sharedMoney.copyWith(
        id: 'vo_billing_money',
        name: 'Montant facturable',
        version: '1.1.0',
        states: const <ContractStage, ContractStatus>{
          ContractStage.design: ContractStatus.done,
        },
      );
      final domainInvoiceNumber = ValueObjectSpec(
        id: 'vo_invoice_number',
        technicalName: 'InvoiceNumber',
        name: 'Numéro de facture',
        states: const <ContractStage, ContractStatus>{
          ContractStage.design: ContractStatus.inProgress,
        },
      );

      var contracts = DomainContracts.parse(
        'models:\n'
        '  CustomerInvoice: model\n'
        'dto:\n'
        '  IssueInvoiceDto: createxdto\n',
      );
      final invoiceNode = contracts.groups
          .expand((g) => g.children)
          .firstWhere((n) => n.name == 'CustomerInvoice');
      final dtoNode = contracts.groups
          .expand((g) => g.children)
          .firstWhere((n) => n.name == 'IssueInvoiceDto');

      final invoiceOrigin = SpecOriginBaseline(
        projectId: 'proj_1',
        projectName: 'Facturation 2026',
        specObjectId: 'spec_obj_invoice',
        promotedAt: DateTime.utc(2026, 11, 20, 10, 0),
        baseSpecObject: BusinessObjectSpec(
          id: 'spec_obj_invoice',
          name: 'Facture',
          technicalName: 'CustomerInvoice',
        ),
      );

      contracts = contracts
          .edit(
            invoiceNode,
            'model',
            ContractDetails(
              title: 'Facture client',
              version: '1.0.0',
              states: const <ContractStage, ContractStatus>{
                ContractStage.design: ContractStatus.done,
              },
              specOrigin: invoiceOrigin,
            ),
          )
          .withModel(
            invoiceNode.id,
            object: BusinessObjectSpec(
              id: invoiceNode.id,
              name: 'Facture client',
              technicalName: 'CustomerInvoice',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'a_num',
                  name: 'invoiceNumber',
                  type: BusinessAttributeType.valueObject,
                  valueObjectId: domainInvoiceNumber.id,
                  required: true,
                ),
              ],
            ),
          )
          .withDomainLayer(
            invoiceNode.id,
            layer: HexagonalDomainLayerSpec(
              invariants: <DomainInvariantSpec>[
                DomainInvariantSpec(
                  id: 'inv_1',
                  code: 'INV-01',
                  title: 'Numéro obligatoire',
                  expression: 'invoiceNumber.isNotEmpty',
                ),
              ],
            ),
          );

      final useCase = ApplicationUseCaseSpec(
        id: 'uc_issue_invoice',
        code: 'UC-001',
        name: 'IssueCustomerInvoice',
        title: 'Émettre une facture client',
        version: '1.0.0',
        boundedContext: 'Facturation',
        targetAggregate: 'CustomerInvoice',
        states: const <ContractStage, ContractStatus>{
          ContractStage.design: ContractStatus.done,
        },
      );
      final saga = OrchestrationSagaSpec(
        id: 'saga_billing',
        code: 'SAGA-001',
        name: 'InvoiceSettlementSaga',
        title: 'Règlement de facture',
        version: '1.0.0',
        boundedContexts: const <String>['Facturation', 'Paiement'],
        states: const <ContractStage, ContractStatus>{
          ContractStage.design: ContractStatus.inProgress,
        },
      );

      final stackId = BuildTechStackProfile.defaults.first.id;
      final domain = FunctionalDomain(
        id: 'dom_billing',
        domainCode: 'billing',
        name: 'Facturation',
        techStackId: stackId,
        contracts: contracts,
        valueObjects: <ValueObjectSpec>[domainMoney, domainInvoiceNumber],
        useCaseOrchestration: UseCaseOrchestrationSpec(
          useCases: <ApplicationUseCaseSpec>[useCase],
          sagas: <OrchestrationSagaSpec>[saga],
        ),
      );
      final initialCatalog = DomainCatalog(
        domains: <FunctionalDomain>[domain],
        sharedValueObjects: <ValueObjectSpec>[sharedEmail, sharedMoney],
      );
      initialCatalog.validate();

      final snapTime = DateTime.utc(2026, 11, 27, 18, 0);
      final snapshot = DomainIterationSnapshot.capture(
        id: 'snap_iter_1',
        iterationNumber: 1,
        label: 'Itération 1 — MVP',
        notes: 'Périmètre initial figé pour livraison MVP.',
        createdAt: snapTime,
        domain: domain,
        catalog: initialCatalog,
      );

      expect(snapshot.techStackId, stackId);
      expect(snapshot.models.length, 2);
      expect(snapshot.models[invoiceNode.id]?.title, 'Facture client');
      expect(snapshot.models[invoiceNode.id]?.version, '1.0.0');
      expect(snapshot.models[invoiceNode.id]?.groupName, 'models');
      expect(snapshot.models[invoiceNode.id]?.dslType, 'model');
      expect(
        snapshot.models[invoiceNode.id]?.domainLayerSpec.invariants.length,
        1,
      );
      expect(snapshot.models[dtoNode.id]?.groupName, 'dto');
      expect(snapshot.models[dtoNode.id]?.dslType, 'createxdto');

      // domainMoney écrase sharedMoney (homonyme Money), sharedEmail reste visible en scope shared.
      expect(snapshot.valueObjects.length, 3);
      expect(
        snapshot.valueObjects[domainMoney.id]?.scope,
        ValueObjectScope.domain,
      );
      expect(
        snapshot.valueObjects[domainInvoiceNumber.id]?.scope,
        ValueObjectScope.domain,
      );
      expect(
        snapshot.valueObjects[sharedEmail.id]?.scope,
        ValueObjectScope.shared,
      );
      expect(snapshot.valueObjects.containsKey(sharedMoney.id), isFalse);

      expect(snapshot.useCases[useCase.id], equals(useCase));
      expect(snapshot.sagas[saga.id], equals(saga));

      final domainWithBaseline = domain.copyWith(
        iterationSnapshots: <DomainIterationSnapshot>[snapshot],
        activeBaselineSnapshotId: snapshot.id,
      );
      expect(domainWithBaseline.activeBaselineSnapshot, equals(snapshot));

      final catalogWithBaseline = initialCatalog.copyWith(
        domains: <FunctionalDomain>[domainWithBaseline],
      );
      catalogWithBaseline.validate();

      final restoredCatalog = DomainCatalog.fromJson(
        catalogWithBaseline.toJson(),
      );
      final restoredDomain = restoredCatalog.domains.single;
      expect(restoredDomain.iterationSnapshots.single, equals(snapshot));
      expect(
        restoredDomain.iterationSnapshots.single.hashCode,
        equals(snapshot.hashCode),
      );
      expect(restoredDomain.activeBaselineSnapshotId, snapshot.id);
      expect(restoredDomain.activeBaselineSnapshot, equals(snapshot));

      final restoredOrigin =
          restoredDomain.contracts!.details[invoiceNode.id]!.specOrigin;
      expect(restoredOrigin, equals(invoiceOrigin));

      final deactivated = restoredDomain.copyWith(
        clearActiveBaselineSnapshotId: true,
      );
      expect(deactivated.activeBaselineSnapshotId, isNull);
      expect(deactivated.activeBaselineSnapshot, isNull);
      deactivated.validate();
    });

    test('rétrocompatibilité FunctionalDomain sans snapshots et validation des erreurs', () {
      final legacyDomain = FunctionalDomain.fromJson(const <String, Object?>{
        'id': 'dom_legacy',
        'domainCode': 'legacy-domain',
        'name': 'Domaine Legacy',
      });
      expect(legacyDomain.iterationSnapshots, isEmpty);
      expect(legacyDomain.activeBaselineSnapshotId, isNull);
      expect(legacyDomain.activeBaselineSnapshot, isNull);
      expect(legacyDomain.toJson().containsKey('iterationSnapshots'), isFalse);
      expect(
        legacyDomain.toJson().containsKey('activeBaselineSnapshotId'),
        isFalse,
      );

      final snap1 = DomainIterationSnapshot(
        id: 'snap_1',
        iterationNumber: 1,
        label: 'Itération 1',
        createdAt: DateTime.utc(2026, 11, 27),
      );
      final snapDup = snap1.copyWith(iterationNumber: 2, label: 'Itération 2');

      // ID de snapshot dupliqué.
      expect(
        () => legacyDomain
            .copyWith(
              iterationSnapshots: <DomainIterationSnapshot>[snap1, snapDup],
            )
            .validate(),
        throwsFormatException,
      );

      // activeBaselineSnapshotId introuvable.
      expect(
        () => legacyDomain
            .copyWith(
              iterationSnapshots: <DomainIterationSnapshot>[snap1],
              activeBaselineSnapshotId: 'snap_missing',
            )
            .validate(),
        throwsFormatException,
      );

      // iterationNumber < 1 ou label vide.
      expect(
        () => snap1.copyWith(iterationNumber: 0).validate(),
        throwsFormatException,
      );
      expect(
        () => snap1.copyWith(label: '   ').validate(),
        throwsFormatException,
      );
    });
  });
}
