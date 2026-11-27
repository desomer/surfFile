import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  final epoch = DateTime.utc(2026, 3, 1);

  final emailVo = ResolvedValueObject(
    spec: ValueObjectPresets.standardPresets.firstWhere(
      (v) => v.technicalName == 'EmailAddress',
    ),
    scope: ValueObjectScope.shared,
  );
  final ibanVo = ResolvedValueObject(
    spec: ValueObjectPresets.standardPresets.firstWhere(
      (v) => v.technicalName == 'Iban',
    ),
    scope: ValueObjectScope.shared,
  );
  final postalAddressVo = ResolvedValueObject(
    spec: ValueObjectPresets.standardPresets.firstWhere(
      (v) => v.technicalName == 'PostalAddress',
    ),
    scope: ValueObjectScope.shared,
  );

  group('SpecDesignMergeEngine', () {
    test('fusion 2-voies legacy (baseSpec == null) préserve tous les attributs Design absents de la Spec et les enrichissements techniques', () {
      final currentDesign = BusinessObjectSpec(
        id: 'entry_supplier',
        name: 'Fournisseur',
        technicalName: 'Fournisseur',
        description: 'Ancienne description',
        attributes: [
          BusinessAttribute(
            id: 'd_id',
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
            unique: true,
          ),
          BusinessAttribute(
            id: 'd_iban',
            name: 'ibanPaiement',
            type: BusinessAttributeType.valueObject,
            valueObjectId: ibanVo.spec.id,
            required: false,
            schemaConstraints: JsonSchemaConstraints(
              extraKeywords: const {
                'x-database-index': true,
                'x-searchable': false,
                'x-mask': 'AA00 #### ####',
              },
            ),
          ),
          BusinessAttribute(
            id: 'd_version',
            name: 'version',
            type: BusinessAttributeType.integer,
            required: true,
            description: 'Verrou optimiste technique',
          ),
          BusinessAttribute(
            id: 'd_deleted_at',
            name: 'deletedAt',
            type: BusinessAttributeType.datetime,
            nullable: true,
          ),
        ],
      );

      final nextSpecResolved = BusinessObjectSpec(
        id: 'entry_supplier',
        name: 'Fournisseur agréé',
        technicalName: 'Fournisseur',
        description: 'Fournisseur référencé aux achats',
        attributes: [
          BusinessAttribute(
            id: 's_id',
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
            unique: true,
          ),
          BusinessAttribute(
            id: 's_iban',
            name: 'ibanPaiement',
            type: BusinessAttributeType.string,
            required: true,
            description: 'IBAN vérifié pour virements SEPA',
          ),
          BusinessAttribute(
            id: 's_delai',
            name: 'delaiLivraisonJours',
            type: BusinessAttributeType.integer,
            required: false,
          ),
        ],
      );

      final result = SpecDesignMergeEngine.merge(
        baseSpec: null,
        nextSpecResolved: nextSpecResolved,
        currentDesign: currentDesign,
        availableValueObjects: [ibanVo],
      );

      expect(result.hasChanges, isTrue);
      expect(result.addedCount, 1);
      expect(result.removedCount, 0);
      expect(result.preservedDesignOnlyCount, 2);
      expect(result.preservedValueObjectCount, 1);
      expect(result.preservedDesignCount, 3);
      expect(result.conflictCount, 0);
      expect(result.preservedValueObjectIds, [ibanVo.spec.id]);

      final byName = {
        for (final a in result.mergedObject.attributes) a.name: a,
      };
      expect(
        byName.keys,
        containsAll([
          'id',
          'ibanPaiement',
          'delaiLivraisonJours',
          'version',
          'deletedAt',
        ]),
      );

      final ibanAttr = byName['ibanPaiement']!;
      expect(ibanAttr.id, 'd_iban');
      expect(ibanAttr.type, BusinessAttributeType.valueObject);
      expect(ibanAttr.valueObjectId, ibanVo.spec.id);
      expect(ibanAttr.required, isTrue);
      expect(ibanAttr.description, 'IBAN vérifié pour virements SEPA');
      expect(ibanAttr.schemaConstraints.xDatabaseIndex, isTrue);
      expect(ibanAttr.schemaConstraints.xSearchable, isFalse);
      expect(ibanAttr.schemaConstraints.xMask, 'AA00 #### ####');
    });

    test('protège contre la perte silencieuse (conflictKeptDesign + warning) si un attribut supprimé en Spec a été spécialisé en Design', () {
      final baseSpec = BusinessObjectSpec(
        id: 'obj_order',
        name: 'Commande',
        technicalName: 'Commande',
        attributes: [
          BusinessAttribute(
            id: 'a_id',
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
          ),
          BusinessAttribute(
            id: 'a_plain_note',
            name: 'noteTemporaire',
            type: BusinessAttributeType.string,
          ),
          BusinessAttribute(
            id: 'a_adr',
            name: 'adresseFacturation',
            type: BusinessAttributeType.object,
            children: [
              BusinessAttribute(
                id: 'a_adr_rue',
                name: 'rue',
                type: BusinessAttributeType.string,
              ),
            ],
          ),
          BusinessAttribute(
            id: 'a_code_interne',
            name: 'codeInterne',
            type: BusinessAttributeType.string,
          ),
        ],
      );

      // Côté Design :
      // - noteTemporaire n'a reçu aucune spécialisation
      // - adresseFacturation a été promue en Value Object PostalAddress
      // - codeInterne a reçu un index de base de données x-database-index: true
      final currentDesign = BusinessObjectSpec(
        id: 'entry_order',
        name: 'Commande',
        technicalName: 'Commande',
        attributes: [
          baseSpec.attributes[0],
          baseSpec.attributes[1],
          BusinessAttribute(
            id: 'a_adr',
            name: 'adresseFacturation',
            type: BusinessAttributeType.valueObject,
            valueObjectId: postalAddressVo.spec.id,
            required: true,
          ),
          baseSpec.attributes[3].copyWith(
            schemaConstraints: JsonSchemaConstraints(
              maxLength: 32,
              extraKeywords: const {'x-database-index': true},
            ),
          ),
        ],
      );

      // En Spec v2 : noteTemporaire, adresseFacturation et codeInterne ont tous été retirés !
      final nextSpec = baseSpec.copyWith(attributes: [baseSpec.attributes[0]]);

      final result = SpecDesignMergeEngine.merge(
        baseSpec: baseSpec,
        nextSpecResolved: nextSpec.copyWith(id: 'entry_order'),
        nextSpec: nextSpec,
        currentDesign: currentDesign,
        availableValueObjects: [postalAddressVo],
      );

      // noteTemporaire (non spécialisé) est bien supprimé ; les 2 attributs spécialisés sont conservés avec conflit !
      expect(result.removedCount, 1);
      expect(result.conflictCount, 2);
      expect(result.warnings, hasLength(2));
      expect(result.preservedValueObjectIds, [postalAddressVo.spec.id]);

      final mergedNames = result.mergedObject.attributes
          .map((a) => a.name)
          .toList();
      expect(mergedNames, isNot(contains('noteTemporaire')));
      expect(mergedNames, containsAll(['adresseFacturation', 'codeInterne']));
    });

    test('signale un conflit tout en conservant le Value Object si la Spec change le type de manière incompatible', () {
      final baseSpec = BusinessObjectSpec(
        id: 'obj_contact',
        name: 'Contact',
        technicalName: 'Contact',
        attributes: [
          BusinessAttribute(
            id: 'a_email',
            name: 'canalContact',
            type: BusinessAttributeType.string,
          ),
        ],
      );
      final currentDesign = BusinessObjectSpec(
        id: 'entry_contact',
        name: 'Contact',
        technicalName: 'Contact',
        attributes: [
          BusinessAttribute(
            id: 'a_email',
            name: 'canalContact',
            type: BusinessAttributeType.valueObject,
            valueObjectId: emailVo.spec.id,
          ),
        ],
      );
      // La Spec bascule canalContact en booléen (incompatible avec EmailAddress)
      final nextSpec = baseSpec.copyWith(
        attributes: [
          BusinessAttribute(
            id: 'a_email',
            name: 'canalContact',
            type: BusinessAttributeType.boolean,
          ),
        ],
      );

      final result = SpecDesignMergeEngine.merge(
        baseSpec: baseSpec,
        nextSpecResolved: nextSpec.copyWith(id: 'entry_contact'),
        nextSpec: nextSpec,
        currentDesign: currentDesign,
        availableValueObjects: [emailVo],
      );

      expect(result.conflictCount, 1);
      expect(result.warnings, hasLength(1));
      expect(
        result.mergedObject.attributes.single.type,
        BusinessAttributeType.valueObject,
      );
      expect(
        result.mergedObject.attributes.single.valueObjectId,
        emailVo.spec.id,
      );
    });

    test('fusionne récursivement les sous-objets et préserve les états/transitions de cycle de vie propres au Design', () {
      final baseSpec = BusinessObjectSpec(
        id: 'obj_dossier',
        name: 'Dossier',
        technicalName: 'Dossier',
        attributes: [
          BusinessAttribute(
            id: 'a_meta',
            name: 'metadonnees',
            type: BusinessAttributeType.object,
            children: [
              BusinessAttribute(
                id: 'c_mail',
                name: 'referentEmail',
                type: BusinessAttributeType.string,
              ),
            ],
          ),
        ],
        lifecycleStates: const [
          LifecycleState(name: 'ouvert', label: 'Ouvert', isInitial: true),
          LifecycleState(name: 'clos', label: 'Clos', isTerminal: true),
        ],
        lifecycleTransitions: const [
          LifecycleTransition(
            id: 'tr_1',
            fromState: 'ouvert',
            toState: 'clos',
            trigger: 'cloturer',
          ),
        ],
      );

      final currentDesign = BusinessObjectSpec(
        id: 'entry_dossier',
        name: 'Dossier',
        technicalName: 'Dossier',
        attributes: [
          BusinessAttribute(
            id: 'a_meta',
            name: 'metadonnees',
            type: BusinessAttributeType.object,
            children: [
              BusinessAttribute(
                id: 'c_mail',
                name: 'referentEmail',
                type: BusinessAttributeType.valueObject,
                valueObjectId: emailVo.spec.id,
              ),
              BusinessAttribute(
                id: 'c_hash',
                name: 'checksum',
                type: BusinessAttributeType.string,
              ),
            ],
          ),
        ],
        lifecycleStates: const [
          LifecycleState(name: 'ouvert', label: 'Ouvert', isInitial: true),
          LifecycleState(name: 'clos', label: 'Clos', isTerminal: true),
          LifecycleState(
            name: 'purge_technique',
            label: 'Purge technique',
            isTerminal: true,
          ),
        ],
        lifecycleTransitions: const [
          LifecycleTransition(
            id: 'tr_1',
            fromState: 'ouvert',
            toState: 'clos',
            trigger: 'cloturer',
          ),
          LifecycleTransition(
            id: 'tr_design_purge',
            fromState: 'clos',
            toState: 'purge_technique',
            trigger: 'purger',
          ),
        ],
      );

      final nextSpec = baseSpec.copyWith(
        attributes: [
          BusinessAttribute(
            id: 'a_meta',
            name: 'metadonnees',
            type: BusinessAttributeType.object,
            children: [
              BusinessAttribute(
                id: 'c_mail',
                name: 'referentEmail',
                type: BusinessAttributeType.email,
                required: true,
              ),
              BusinessAttribute(
                id: 'c_origine',
                name: 'canalOrigine',
                type: BusinessAttributeType.string,
              ),
            ],
          ),
        ],
        lifecycleStates: const [
          LifecycleState(name: 'ouvert', label: 'Ouvert', isInitial: true),
          LifecycleState(name: 'suspendu', label: 'Suspendu'),
          LifecycleState(name: 'clos', label: 'Clos', isTerminal: true),
        ],
        lifecycleTransitions: const [
          LifecycleTransition(
            id: 'tr_1',
            fromState: 'ouvert',
            toState: 'clos',
            trigger: 'cloturer',
          ),
          LifecycleTransition(
            id: 'tr_2',
            fromState: 'ouvert',
            toState: 'suspendu',
            trigger: 'suspendre',
          ),
        ],
      );

      final result = SpecDesignMergeEngine.merge(
        baseSpec: baseSpec,
        nextSpecResolved: nextSpec.copyWith(id: 'entry_dossier'),
        nextSpec: nextSpec,
        currentDesign: currentDesign,
        availableValueObjects: [emailVo],
      );

      final children = result.mergedObject.attributes.single.children;
      final byChildName = {for (final c in children) c.name: c};
      expect(
        byChildName.keys,
        containsAll(['referentEmail', 'canalOrigine', 'checksum']),
      );
      expect(
        byChildName['referentEmail']!.type,
        BusinessAttributeType.valueObject,
      );
      expect(byChildName['referentEmail']!.required, isTrue);
      expect(
        result.decisions.map((d) => d.attributePath),
        containsAll([
          'metadonnees.referentEmail',
          'metadonnees.canalOrigine',
          'metadonnees.checksum',
        ]),
      );

      expect(
        result.mergedObject.lifecycleStates.map((s) => s.name),
        containsAll(['ouvert', 'suspendu', 'clos', 'purge_technique']),
      );
      expect(
        result.mergedObject.lifecycleTransitions.map((t) => t.id),
        containsAll(['tr_1', 'tr_2', 'tr_design_purge']),
      );
    });
  });

  group('SpecDesignDriftAnalyzer', () {
    test('détecte les contrats synchronisés, modifiés, supprimés en Spec, les objets non promus et les dérives RG/EXF/UC', () {
      final commandeV1 = BusinessObjectSpec(
        id: 'obj_cmd',
        name: 'Commande',
        technicalName: 'Commande',
        attributes: [
          BusinessAttribute(
            id: 'a_id',
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
          ),
          BusinessAttribute(
            id: 'a_total',
            name: 'totalHt',
            type: BusinessAttributeType.number,
            required: true,
          ),
        ],
      );
      final brouillonPanier = BusinessObjectSpec(
        id: 'obj_panier',
        name: 'Panier temporaire',
        technicalName: 'PanierTemporaire',
        attributes: [
          BusinessAttribute(
            id: 'p_id',
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
          ),
        ],
      );
      final rgTotal = BusinessRuleSpec(
        id: 'r_1',
        code: 'RG-001',
        title: 'Total positif',
        targetObjectIds: const ['obj_cmd'],
        condition: 'totalHt > 0',
        effect: 'Valider la commande',
      );
      final rgRemise = BusinessRuleSpec(
        id: 'r_2',
        code: 'RG-002',
        title: 'Plafond remise',
        targetObjectIds: const ['obj_cmd'],
        condition: 'remise <= 20',
        effect: 'Autoriser remise standard',
      );
      final exfCreate = FunctionalRequirement(
        id: 'req_1',
        code: 'EXF-001',
        title: 'Création de commande',
        priority: RequirementPriority.must,
      );
      final ucPasserCmd = UseCaseSpec(
        id: 'uc_1',
        title: 'Passer une commande ferme',
      );

      final projectV1 = SpecForgeProject(
        id: 'proj_oms',
        name: 'OMS',
        initialIdea: 'Gestion des commandes',
        createdAt: epoch,
        updatedAt: epoch,
        businessObjects: [commandeV1, brouillonPanier],
        businessRules: [rgTotal, rgRemise],
        cahierDesCharges: SpecCahierDesCharges(
          functionalRequirements: [exfCreate],
          useCases: [ucPasserCmd],
        ),
      );

      // Promotion initiale de Commande et PanierTemporaire + ajout d'un DTO pur Design
      var baseContracts = DomainContracts.parse(
        'models:\ncomponents:\ndto:\n  CreateCommandeDto: createxdto\nmessage:\n',
      );
      final promo = SpecDesignPromoter.promote(
        project: projectV1,
        catalog: DomainCatalog(
          domains: [
            FunctionalDomain(
              id: 'dom_oms',
              domainCode: 'oms',
              name: 'Commandes',
              contracts: baseContracts,
              useCaseOrchestration: UseCaseOrchestrationSpec(
                useCases: [
                  ApplicationUseCaseSpec(
                    id: 'app_uc_1',
                    code: 'UC-APP-01',
                    name: 'PlaceOrder',
                    title: 'Enregistrer une commande',
                    linkedSpecRefs: const [
                      'EXF-001',
                      'EXF-999',
                      'RG-001',
                      'RG-002',
                      'UC-001',
                      'UC-099',
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        now: epoch,
        choices: const [
          ObjectPromotionChoice(
            objectId: 'obj_cmd',
            domainId: 'dom_oms',
            contractType: 'model',
          ),
          ObjectPromotionChoice(
            objectId: 'obj_panier',
            domainId: 'dom_oms',
            contractType: 'component',
          ),
        ],
      );

      final omsAfterV1 = promo.updatedCatalog.domains.single;

      // Juste après promotion : Commande et PanierTemporaire sont inSync, CreateCommandeDto est designOnly,
      // seules EXF-999 et UC-099 (inexistantes) remontent sur le Use Case applicatif.
      final reportV1 = SpecDesignDriftAnalyzer.analyzeDomain(
        project: projectV1,
        domain: omsAfterV1,
        catalog: promo.updatedCatalog,
      );
      expect(reportV1.driftedContractsCount, 0);
      expect(reportV1.unpromotedSpecObjects, isEmpty);
      final dtoDrift = reportV1.contractDrifts.firstWhere(
        (c) => c.entryName == 'CreateCommandeDto',
      );
      expect(dtoDrift.status, ContractSpecDriftStatus.designOnly);
      expect(
        reportV1
            .driftsForUseCase('app_uc_1')
            .map((d) => '${d.refCode}:${d.status.name}'),
        containsAll(['EXF-999:missingInSpec', 'UC-099:missingInSpec']),
      );

      // Évolution Spec v2 :
      // - Commande gagne l'attribut dateLivraisonSouhaitee
      // - PanierTemporaire est supprimé de la Spec
      // - LivraisonColis est créé dans la Spec mais pas encore promu
      // - RG-001 est modifiée (condition changée), RG-002 est supprimée, RG-003 est ajoutée sur Commande
      // - EXF-001 passe en Won't
      final commandeV2 = commandeV1.copyWith(
        attributes: [
          ...commandeV1.attributes,
          BusinessAttribute(
            id: 'a_date_liv',
            name: 'dateLivraisonSouhaitee',
            type: BusinessAttributeType.date,
          ),
        ],
      );
      final livraisonNew = BusinessObjectSpec(
        id: 'obj_livraison',
        name: 'Livraison colis',
        technicalName: 'LivraisonColis',
      );
      final rgTotalModified = rgTotal.copyWith(condition: 'totalHt >= 10');
      final rgNew = BusinessRuleSpec(
        id: 'r_3',
        code: 'RG-003',
        title: 'Devise obligatoire',
        targetObjectIds: const ['obj_cmd'],
        condition: 'devise != ""',
      );

      final projectV2 = projectV1.copyWith(
        businessObjects: [commandeV2, livraisonNew],
        businessRules: [rgTotalModified, rgNew],
        cahierDesCharges: projectV1.cahierDesCharges.copyWith(
          functionalRequirements: [
            exfCreate.copyWith(priority: RequirementPriority.wont),
          ],
        ),
      );

      final reportV2 = SpecDesignDriftAnalyzer.analyzeDomain(
        project: projectV2,
        domain: omsAfterV1,
        catalog: promo.updatedCatalog,
      );

      expect(reportV2.hasAnyDrift, isTrue);
      expect(reportV2.modifiedInSpecCount, 1);
      expect(reportV2.missingInSpecCount, 1);
      expect(reportV2.unpromotedSpecObjects.map((o) => o.technicalName), [
        'LivraisonColis',
      ]);

      final cmdDrift = reportV2.driftForSpecObject('obj_cmd')!;
      expect(cmdDrift.status, ContractSpecDriftStatus.specModified);
      expect(cmdDrift.addedAttributeNames, ['dateLivraisonSouhaitee']);
      expect(cmdDrift.previewMergeResult?.addedCount, 1);
      expect(
        cmdDrift.ruleDrifts.map((r) => '${r.refCode}:${r.status.name}'),
        containsAll([
          'RG-001:modifiedInSpec',
          'RG-002:missingInSpec',
          'RG-003:addedInSpec',
        ]),
      );

      final panierDrift = reportV2.driftForSpecObject('obj_panier')!;
      expect(panierDrift.status, ContractSpecDriftStatus.missingInSpec);

      final ucDrifts = reportV2.driftsForUseCase('app_uc_1');
      expect(
        ucDrifts.map((d) => '${d.refCode}:${d.status.name}'),
        containsAll([
          'EXF-001:modifiedInSpec',
          'EXF-999:missingInSpec',
          'RG-001:modifiedInSpec',
          'RG-002:missingInSpec',
          'UC-099:missingInSpec',
        ]),
      );
      // UC-001 existe toujours dans le cahier des charges -> pas de dérive sur UC-001
      expect(ucDrifts.any((d) => d.refCode == 'UC-001'), isFalse);
    });
  });
}
