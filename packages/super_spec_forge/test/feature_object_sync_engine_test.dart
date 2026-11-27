import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_fsync_store'));

  final Map<String, SpecForgeProject> projects = <String, SpecForgeProject>{};
  String? _lastActiveId;

  void seed(SpecForgeProject project) {
    projects[project.id] = project;
    _lastActiveId = project.id;
  }

  @override
  Future<void> saveProject(SpecForgeProject project) async {
    project.validate();
    projects[project.id] = project;
    _lastActiveId = project.id;
  }

  @override
  Future<SpecForgeProject?> loadProject(String projectId) async =>
      projects[projectId];

  @override
  Future<void> deleteProject(String projectId) async {
    projects.remove(projectId);
    if (_lastActiveId == projectId) _lastActiveId = null;
  }

  @override
  Future<List<SpecProjectSummary>> listProjects() async => <SpecProjectSummary>[
    for (final p in projects.values)
      SpecProjectSummary(
        id: p.id,
        name: p.name,
        initialIdea: p.initialIdea,
        currentStage: p.currentStage,
        updatedAt: p.updatedAt,
        objectCount: p.businessObjects.length,
        ruleCount: p.businessRules.length,
      ),
  ];

  @override
  Future<String?> getLastActiveProjectId() async => _lastActiveId;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {
    _lastActiveId = projectId;
  }
}

class _MemoryDomainCatalogStore extends DomainCatalogStore {
  _MemoryDomainCatalogStore([DomainCatalog? initial])
    : _catalog = initial ?? DomainCatalog.empty,
      super(Directory('memory_fsync_store'));

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
  _MemoryCompanyGlossaryStore() : super(Directory('memory_fsync_store'));

  @override
  Future<CompanyGlossary> loadGlossary() async => CompanyGlossary.empty;

  @override
  Future<void> saveGlossary(CompanyGlossary glossary) async {}

  @override
  Future<List<SpecChatMessage>> loadChatMessages() async =>
      const <SpecChatMessage>[];

  @override
  Future<void> saveChatMessages(List<SpecChatMessage> messages) async {}
}

class _MemoryModelDictionaryStore extends ModelDictionaryStore {
  _MemoryModelDictionaryStore() : super(Directory('memory_fsync_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemoryRateCardStore extends EnterpriseRateCardStore {
  _MemoryRateCardStore() : super(Directory('memory_fsync_store'));

  @override
  Future<EnterpriseRateCard> load() async => EnterpriseRateCard.defaults;

  @override
  Future<void> save(EnterpriseRateCard card) async {}
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

void main() {
  final t0 = DateTime.utc(2026, 11, 27, 9, 0);
  final t1 = DateTime.utc(2026, 11, 27, 11, 0);
  final t2 = DateTime.utc(2026, 11, 27, 14, 0);

  BusinessObjectSpec buildAgence() => BusinessObjectSpec(
    id: 'obj_agence',
    name: 'Agence',
    technicalName: 'Agence',
    description: 'Agence de location.',
    attributes: <BusinessAttribute>[
      BusinessAttribute(
        id: 'attr_ag_id',
        name: 'id',
        type: BusinessAttributeType.uuid,
        required: true,
        unique: true,
      ),
      BusinessAttribute(
        id: 'attr_ag_code',
        name: 'codeAgence',
        type: BusinessAttributeType.string,
        required: true,
      ),
    ],
  );

  BusinessObjectSpec buildFournisseur() => BusinessObjectSpec(
    id: 'obj_fournisseur',
    name: 'Fournisseur leasing',
    technicalName: 'FournisseurLeasing',
    description: 'Partenaire financier du parc.',
    attributes: <BusinessAttribute>[
      BusinessAttribute(
        id: 'attr_four_id',
        name: 'id',
        type: BusinessAttributeType.integer,
        required: true,
        unique: true,
      ),
      BusinessAttribute(
        id: 'attr_four_nom',
        name: 'raisonSociale',
        type: BusinessAttributeType.string,
        required: true,
      ),
    ],
  );

  BusinessObjectSpec buildVehiculeV1() => BusinessObjectSpec(
    id: 'obj_vehicule',
    name: 'Véhicule',
    technicalName: 'Vehicule',
    description: 'Véhicule du parc automobile.',
    attributes: <BusinessAttribute>[
      BusinessAttribute(
        id: 'attr_veh_id',
        name: 'id',
        type: BusinessAttributeType.uuid,
        required: true,
        unique: true,
      ),
      BusinessAttribute(
        id: 'attr_veh_immat',
        name: 'immatriculation',
        type: BusinessAttributeType.string,
        required: true,
        unique: true,
      ),
      BusinessAttribute(
        id: 'attr_veh_agence',
        name: 'agenceRattachement',
        type: BusinessAttributeType.reference,
        referenceObjectId: 'obj_agence',
        required: true,
      ),
    ],
    relations: const <BusinessRelation>[
      BusinessRelation(
        id: 'rel_veh_fournisseur',
        name: 'fournisseur',
        targetObjectId: 'obj_fournisseur',
        cardinality: BusinessRelationCardinality.oneToOne,
        required: true,
        description: 'Bailleur propriétaire',
      ),
    ],
  );

  SpecForgeProject buildTwoFeatureProject({
    required List<BusinessObjectSpec> feat1Objects,
    List<BusinessRuleSpec> feat1Rules = const <BusinessRuleSpec>[],
    List<BusinessObjectSpec> feat2Objects = const <BusinessObjectSpec>[],
    Map<String, FeatureObjectSyncBaseline> feat2Baselines =
        const <String, FeatureObjectSyncBaseline>{},
    List<BusinessRuleSpec> feat2Rules = const <BusinessRuleSpec>[],
    UxForgeSpec? feat2Ux,
    QaForgeSpec? feat2Qa,
    String activeFeatureId = 'feat_02',
  }) {
    final feat1 = SpecFeatureSpec(
      id: 'feat_01',
      code: 'FEAT-01',
      name: 'Gestion du parc',
      status: SpecPortfolioStatus.validated,
      businessObjects: feat1Objects,
      businessRules: feat1Rules,
    );
    final feat2 = SpecFeatureSpec(
      id: 'feat_02',
      code: 'FEAT-02',
      name: 'Retour de location',
      status: SpecPortfolioStatus.inProgress,
      businessObjects: feat2Objects,
      objectSyncBaselines: feat2Baselines,
      businessRules: feat2Rules,
      uxSpec: feat2Ux,
      qaSpec: feat2Qa,
    );
    return SpecForgeProject(
      id: 'proj_fleet',
      name: 'Mobilité Flotte',
      initialIdea: 'Gestion de flotte et location courte durée',
      createdAt: t0,
      updatedAt: t0,
      initiatives: <SpecInitiative>[
        SpecInitiative(
          id: 'init_01',
          code: 'INIT-01',
          name: 'Opérations Flotte',
          features: <SpecFeatureSpec>[feat1, feat2],
        ),
      ],
      activeFeatureId: activeFeatureId,
    );
  }

  group('FeatureObjectSyncEngine — Feature → Feature', () {
    test('import initial préserve id/technicalName canoniques, recâble les références intra-feature, convertit les références externes en ID scalaire et enregistre la baseline', () {
      final project = buildTwoFeatureProject(
        feat1Objects: <BusinessObjectSpec>[
          buildAgence(),
          buildFournisseur(),
          buildVehiculeV1(),
        ],
      );

      final candidates = FeatureObjectSyncEngine.listCandidatesFromFeature(
        project: project,
        sourceFeatureId: 'feat_01',
      );
      expect(candidates, hasLength(3));
      expect(
        candidates.first.sourceFeatureStatus,
        SpecPortfolioStatus.validated,
      );

      // On importe Vehicule + Agence, mais PAS FournisseurLeasing.
      final choices = <FeatureObjectSyncChoice>[
        const FeatureObjectSyncChoice(
          sourceObjectKey: 'obj_agence',
          sourceKind: ObjectSyncSourceKind.feature,
          sourceFeatureId: 'feat_01',
        ),
        const FeatureObjectSyncChoice(
          sourceObjectKey: 'obj_vehicule',
          sourceKind: ObjectSyncSourceKind.feature,
          sourceFeatureId: 'feat_01',
        ),
      ];

      final previews = FeatureObjectSyncEngine.previewSync(
        project: project,
        choices: choices,
      );
      expect(previews, hasLength(2));
      final vehPreview = previews.firstWhere(
        (p) => p.projectedSourceObject.technicalName == 'Vehicule',
      );
      expect(vehPreview.isNewInTarget, isTrue);
      expect(vehPreview.unresolvedExternalRefCount, 1);

      final result = FeatureObjectSyncEngine.executeSync(
        project: project,
        choices: choices,
        now: t1,
      );

      expect(result.hasChanges, isTrue);
      expect(result.importedObjectIds, <String>['obj_agence', 'obj_vehicule']);
      expect(result.mergedObjectIds, isEmpty);
      expect(result.overwrittenObjectIds, isEmpty);
      expect(result.skippedObjectNames, isEmpty);

      // FEAT-01 est strictement intacte.
      expect(
        result.updatedProject.featureById('feat_01'),
        equals(project.featureById('feat_01')),
      );

      final feat2 = result.updatedProject.featureById('feat_02')!;
      expect(feat2.businessObjects, hasLength(2));

      final syncedVehicule = feat2.businessObjects.firstWhere(
        (o) => o.id == 'obj_vehicule',
      );
      expect(syncedVehicule.technicalName, 'Vehicule');
      // La relation vers FournisseurLeasing non importé a été retirée de relations
      // et convertie en attribut scalaire entier (clé primaire int de FournisseurLeasing).
      expect(syncedVehicule.relations, isEmpty);

      final agenceAttr = syncedVehicule.attributes.firstWhere(
        (a) => a.name == 'agenceRattachement',
      );
      expect(agenceAttr.type, BusinessAttributeType.reference);
      expect(agenceAttr.referenceObjectId, 'obj_agence');

      final fournisseurAttr = syncedVehicule.attributes.firstWhere(
        (a) => a.name == 'fournisseur',
      );
      expect(fournisseurAttr.type, BusinessAttributeType.integer);
      expect(fournisseurAttr.referenceObjectId, isEmpty);
      expect(fournisseurAttr.required, isTrue);
      expect(
        fournisseurAttr.description,
        contains('Référence externe vers Fournisseur leasing'),
      );
      expect(fournisseurAttr.description, contains('FEAT-01'));

      final baseline = feat2.syncBaselineFor('obj_vehicule');
      expect(baseline, isNotNull);
      expect(baseline!.sourceKind, ObjectSyncSourceKind.feature);
      expect(baseline.sourceFeatureId, 'feat_01');
      expect(baseline.sourceFeatureCode, 'FEAT-01');
      expect(baseline.syncedAt, t1);
      expect(baseline.baseObject, equals(syncedVehicule));
    });

    test('re-synchronisation 3-voies (smartMerge) conserve les ajouts locaux Lot 2 tout en intégrant les ajouts amont de FEAT-01 sans modifier FEAT-01', () {
      final initialProject = buildTwoFeatureProject(
        feat1Objects: <BusinessObjectSpec>[
          buildAgence(),
          buildFournisseur(),
          buildVehiculeV1(),
        ],
      );
      final syncChoices = <FeatureObjectSyncChoice>[
        const FeatureObjectSyncChoice(
          sourceObjectKey: 'obj_agence',
          sourceKind: ObjectSyncSourceKind.feature,
          sourceFeatureId: 'feat_01',
        ),
        const FeatureObjectSyncChoice(
          sourceObjectKey: 'obj_vehicule',
          sourceKind: ObjectSyncSourceKind.feature,
          sourceFeatureId: 'feat_01',
        ),
      ];

      // 1. Import initial FEAT-01 v1 -> FEAT-02.
      final afterInitial = FeatureObjectSyncEngine.executeSync(
        project: initialProject,
        choices: syncChoices,
        now: t1,
      ).updatedProject;

      // 2. FEAT-02 ajoute localement kilometrageRetour (Lot 2).
      final feat2BeforeResync = afterInitial.featureById('feat_02')!;
      final localVehicule = feat2BeforeResync.businessObjects
          .firstWhere((o) => o.id == 'obj_vehicule')
          .copyWith(
            attributes: <BusinessAttribute>[
              ...feat2BeforeResync.businessObjects
                  .firstWhere((o) => o.id == 'obj_vehicule')
                  .attributes,
              BusinessAttribute(
                id: 'attr_local_km_retour',
                name: 'kilometrageRetour',
                type: BusinessAttributeType.integer,
                required: true,
                description: 'Relevé compteur au retour Lot 2',
              ),
            ],
          );
      var divergedProject = afterInitial.updateFeature(
        feat2BeforeResync.copyWith(
          businessObjects: <BusinessObjectSpec>[
            feat2BeforeResync.businessObjects.firstWhere(
              (o) => o.id == 'obj_agence',
            ),
            localVehicule,
          ],
        ),
      );

      // 3. FEAT-01 évolue en v2 en ajoutant dateProchainControle.
      final feat1BeforeResync = divergedProject.featureById('feat_01')!;
      final vehiculeV2 = buildVehiculeV1().copyWith(
        description: 'Véhicule du parc automobile suivi au contrôle technique.',
        attributes: <BusinessAttribute>[
          ...buildVehiculeV1().attributes,
          BusinessAttribute(
            id: 'attr_veh_ct',
            name: 'dateProchainControle',
            type: BusinessAttributeType.date,
            required: false,
            description: 'Échéance réglementaire CT',
          ),
        ],
      );
      final feat1V2 = feat1BeforeResync.copyWith(
        businessObjects: <BusinessObjectSpec>[
          buildAgence(),
          buildFournisseur(),
          vehiculeV2,
        ],
      );
      divergedProject = divergedProject.updateFeature(feat1V2);

      // 4. Aperçu puis exécution de la re-synchronisation 3-voies FEAT-01 -> FEAT-02.
      final resyncChoices = <FeatureObjectSyncChoice>[
        const FeatureObjectSyncChoice(
          sourceObjectKey: 'obj_vehicule',
          sourceKind: ObjectSyncSourceKind.feature,
          sourceFeatureId: 'feat_01',
          resolution: FeatureObjectSyncResolution.smartMerge,
        ),
      ];

      final previews = FeatureObjectSyncEngine.previewSync(
        project: divergedProject,
        choices: resyncChoices,
      );
      expect(previews.single.isNewInTarget, isFalse);
      expect(previews.single.isIdentical, isFalse);
      expect(previews.single.mergeResult, isNotNull);
      expect(previews.single.mergeResult!.addedCount, 1);
      expect(previews.single.mergeResult!.preservedDesignOnlyCount, 1);

      final resyncResult = FeatureObjectSyncEngine.executeSync(
        project: divergedProject,
        choices: resyncChoices,
        now: t2,
      );

      expect(resyncResult.hasChanges, isTrue);
      expect(resyncResult.importedObjectIds, isEmpty);
      expect(resyncResult.mergedObjectIds, <String>['obj_vehicule']);

      // FEAT-01 n'a subi aucune mutation (ne contient pas kilometrageRetour).
      final feat1After = resyncResult.updatedProject.featureById('feat_01')!;
      expect(feat1After, equals(feat1V2));
      expect(
        feat1After.businessObjects
            .firstWhere((o) => o.id == 'obj_vehicule')
            .attributes
            .any((a) => a.name == 'kilometrageRetour'),
        isFalse,
      );

      // FEAT-02 conserve kilometrageRetour ET reçoit dateProchainControle + nouvelle description.
      final feat2After = resyncResult.updatedProject.featureById('feat_02')!;
      final mergedVehicule = feat2After.businessObjects.firstWhere(
        (o) => o.id == 'obj_vehicule',
      );
      final attrNames = mergedVehicule.attributes.map((a) => a.name).toList();
      expect(
        attrNames,
        containsAll(<String>[
          'id',
          'immatriculation',
          'agenceRattachement',
          'fournisseur',
          'dateProchainControle',
          'kilometrageRetour',
        ]),
      );
      expect(
        mergedVehicule.description,
        'Véhicule du parc automobile suivi au contrôle technique.',
      );
      expect(feat2After.syncBaselineFor('obj_vehicule')!.syncedAt, t2);
      expect(
        feat2After
            .syncBaselineFor('obj_vehicule')!
            .baseObject
            .attributes
            .any((a) => a.name == 'dateProchainControle'),
        isTrue,
      );

      // Une re-synchronisation immédiate sans nouvel écart est idempotente.
      final secondRunPreview = FeatureObjectSyncEngine.previewSync(
        project: resyncResult.updatedProject,
        choices: resyncChoices,
      );
      expect(secondRunPreview.single.isIdentical, isTrue);
      final secondRunResult = FeatureObjectSyncEngine.executeSync(
        project: resyncResult.updatedProject,
        choices: resyncChoices,
        now: t2.add(const Duration(minutes: 5)),
      );
      expect(secondRunResult.hasChanges, isFalse);
      expect(
        secondRunResult.updatedProject,
        equals(resyncResult.updatedProject),
      );
    });
  });

  group('FeatureObjectSyncEngine — Design → Spec & alertes d’impact local', () {
    test('projette les Value Objects scalaires et composites, préserve specOrigin.specObjectId en aller-retour et détecte les impacts RG / UX / QA', () {
      final emailVo = ValueObjectSpec(
        id: 'vo_email',
        technicalName: 'EmailAddress',
        name: 'Adresse email',
        kind: ValueObjectKind.scalar,
        primitiveType: BusinessAttributeType.email,
        schemaConstraints: JsonSchemaConstraints(
          maxLength: 254,
          pattern: r'^[^@]+@[^@]+\.[^@]+$',
        ),
      );
      final moneyVo = ValueObjectSpec(
        id: 'vo_money',
        technicalName: 'Money',
        name: 'Montant monétaire',
        kind: ValueObjectKind.composite,
        fields: <BusinessAttribute>[
          BusinessAttribute(
            id: 'f_amount',
            name: 'amountMinorUnits',
            type: BusinessAttributeType.integer,
            required: true,
          ),
          BusinessAttribute(
            id: 'f_currency',
            name: 'currency',
            type: BusinessAttributeType.string,
            required: true,
          ),
        ],
      );

      // 1. Part d'un projet où FEAT-01 promeut ContratLocation vers Design.
      final contratSpecV1 = BusinessObjectSpec(
        id: 'obj_contrat_canonique',
        name: 'Contrat de location',
        technicalName: 'ContratLocation',
        description: 'Contrat signé avec le locataire.',
        attributes: <BusinessAttribute>[
          BusinessAttribute(
            id: 'attr_ctr_id',
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
            unique: true,
          ),
          BusinessAttribute(
            id: 'attr_ctr_email',
            name: 'emailConducteur',
            type: BusinessAttributeType.string,
            required: true,
            description: 'Contact conducteur',
          ),
        ],
      );

      final initialProject = buildTwoFeatureProject(
        feat1Objects: <BusinessObjectSpec>[contratSpecV1],
        activeFeatureId: 'feat_01',
      );
      final baseCatalog = DomainCatalog(
        sharedValueObjects: <ValueObjectSpec>[emailVo, moneyVo],
        domains: const <FunctionalDomain>[
          FunctionalDomain(
            id: 'dom_booking',
            domainCode: 'booking',
            name: 'Réservation',
          ),
        ],
      );

      final promoted = SpecDesignPromoter.promote(
        project: initialProject,
        catalog: baseCatalog,
        now: t0,
        choices: const <ObjectPromotionChoice>[
          ObjectPromotionChoice(
            objectId: 'obj_contrat_canonique',
            domainId: 'dom_booking',
            contractType: 'model',
          ),
        ],
      );

      // 2. Côté Design, l'architecte enrichit ContratLocation avec EmailAddress, Money,
      // un VO inconnu (repli string) et un DTO non retenu par défaut.
      var bookingDomain = promoted.updatedCatalog.domains.single;
      var contracts = bookingDomain.contracts!;
      contracts = contracts.patch(
        contracts.source.replaceFirst(
          'dto:\n',
          'dto:\n  CreateContratDto: createxdto\n',
        ),
      );
      final contratEntry = SpecDesignPromoter.findExistingEntry(
        contracts,
        'ContratLocation',
      )!;
      final enrichedDesignObj = contracts
          .objectFor(contratEntry)
          .copyWith(
            attributes: <BusinessAttribute>[
              BusinessAttribute(
                id: 'attr_ctr_id',
                name: 'id',
                type: BusinessAttributeType.uuid,
                required: true,
                unique: true,
              ),
              BusinessAttribute(
                id: 'attr_ctr_email',
                name: 'emailConducteur',
                type: BusinessAttributeType.valueObject,
                valueObjectId: 'vo_email',
                required: true,
                description: 'Contact conducteur',
              ),
              BusinessAttribute(
                id: 'attr_ctr_tarif',
                name: 'tarifJournalier',
                type: BusinessAttributeType.valueObject,
                valueObjectId: 'Money',
                required: true,
                description: 'Prix par jour',
              ),
              BusinessAttribute(
                id: 'attr_ctr_code_externe',
                name: 'codePartenaire',
                type: BusinessAttributeType.valueObject,
                valueObjectId: 'UnknownPartnerVo',
                required: false,
              ),
            ],
          );
      contracts = contracts.withModel(
        contratEntry.id,
        object: enrichedDesignObj,
      );
      bookingDomain = bookingDomain.copyWith(contracts: contracts);
      final enrichedCatalog = promoted.updatedCatalog.copyWith(
        domains: <FunctionalDomain>[bookingDomain],
      );

      // Vérification du filtrage par défaut (exclut CreateContratDto) et de la projection VO.
      final entityCandidates =
          FeatureObjectSyncEngine.listCandidatesFromDesignDomain(
            domain: bookingDomain,
            catalog: enrichedCatalog,
            project: initialProject,
          );
      expect(entityCandidates, hasLength(1));
      final allCandidates =
          FeatureObjectSyncEngine.listCandidatesFromDesignDomain(
            domain: bookingDomain,
            catalog: enrichedCatalog,
            project: initialProject,
            includeDtosAndMessages: true,
          );
      expect(allCandidates, hasLength(2));
      final candidate = entityCandidates.single;
      expect(candidate.contractType, 'model');
      // ID Spec canonique préservé en aller-retour Spec -> Design -> Spec !
      expect(candidate.rawObject.id, 'obj_contrat_canonique');

      final projectedEmail = candidate.rawObject.attributes.firstWhere(
        (a) => a.name == 'emailConducteur',
      );
      expect(projectedEmail.type, BusinessAttributeType.email);
      expect(projectedEmail.valueObjectId, isEmpty);
      expect(projectedEmail.schemaConstraints.maxLength, 254);
      expect(
        projectedEmail.description,
        'Contact conducteur (VO: EmailAddress)',
      );

      final projectedMoney = candidate.rawObject.attributes.firstWhere(
        (a) => a.name == 'tarifJournalier',
      );
      expect(projectedMoney.type, BusinessAttributeType.object);
      expect(projectedMoney.valueObjectId, isEmpty);
      expect(projectedMoney.description, 'Prix par jour (VO composite: Money)');
      expect(projectedMoney.children, hasLength(2));
      expect(projectedMoney.children.map((c) => c.id), <String>[
        'attr_ctr_tarif_f_amount',
        'attr_ctr_tarif_f_currency',
      ]);
      expect(projectedMoney.children.map((c) => c.name), <String>[
        'amountMinorUnits',
        'currency',
      ]);

      final projectedUnknownVo = candidate.rawObject.attributes.firstWhere(
        (a) => a.name == 'codePartenaire',
      );
      expect(projectedUnknownVo.type, BusinessAttributeType.string);
      expect(projectedUnknownVo.valueObjectId, isEmpty);

      // 3. Dans FEAT-02, ContratLocation possède un attribut local remisePourcent
      // utilisé dans une règle RG, un écran UX et une fixture/suite QA.
      final localContratFeat2 = BusinessObjectSpec(
        id: 'obj_contrat_canonique',
        name: 'Contrat de location',
        technicalName: 'ContratLocation',
        attributes: <BusinessAttribute>[
          BusinessAttribute(
            id: 'attr_ctr_id',
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
            unique: true,
          ),
          BusinessAttribute(
            id: 'attr_ctr_remise',
            name: 'remisePourcent',
            type: BusinessAttributeType.number,
            required: false,
          ),
        ],
      );
      final projectForFeat2 = buildTwoFeatureProject(
        feat1Objects: <BusinessObjectSpec>[contratSpecV1],
        feat2Objects: <BusinessObjectSpec>[localContratFeat2],
        feat2Rules: <BusinessRuleSpec>[
          BusinessRuleSpec(
            id: 'rule_remise',
            code: 'RG-201',
            title: 'Plafond de remise commerciale',
            targetObjectIds: const <String>['obj_contrat_canonique'],
            targetAttributes: const <String>['ContratLocation.remisePourcent'],
            condition: 'remisePourcent > 30',
            effect: 'Rejeter la validation',
          ),
        ],
        feat2Ux: UxForgeSpec(
          screens: <UxScreenSpec>[
            UxScreenSpec(
              id: 'scr_retour',
              code: 'SCR-01',
              name: 'Clôture du contrat',
              primaryObjectId: 'obj_contrat_canonique',
              zones: <UxScreenZoneSpec>[
                UxScreenZoneSpec(
                  zone: UxLayoutZoneName.center,
                  slots: <UxZoneWidgetSlot>[
                    UxZoneWidgetSlot(
                      id: 'slot_form',
                      title: 'Ajustement tarifaire',
                      kind: UxWidgetKind.formSection,
                      attributeNames: const <String>['remisePourcent'],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        feat2Qa: QaForgeSpec(
          fixtures: <QaFixtureSpec>[
            QaFixtureSpec(
              id: 'fix_contrat_1',
              code: 'FIX-01',
              name: 'Contrat avec remise',
              businessObjectId: 'obj_contrat_canonique',
              payload: const <String, Object?>{'remisePourcent': 15},
            ),
          ],
          tddSuites: <TddTestSuiteSpec>[
            TddTestSuiteSpec(
              id: 'tdd_remise',
              code: 'TDD-01',
              name: 'Validation remise contrat',
              targetObjectId: 'obj_contrat_canonique',
              cases: <TddTestCaseSpec>[
                TddTestCaseSpec(
                  id: 'tc_1',
                  code: 'TC-01',
                  title: 'Refuse remisePourcent > 30',
                  act: 'validerContrat(remisePourcent: 35)',
                  outcomeKind: TddExpectedOutcomeKind.rejectsWithError,
                  expectedErrorMessage: 'Plafond dépassé',
                ),
              ],
            ),
          ],
        ),
        activeFeatureId: 'feat_02',
      );

      // En mode overwriteFromSource, remisePourcent disparaît -> alertes RG + UX + QA !
      final overwritePreviews = FeatureObjectSyncEngine.previewSync(
        project: projectForFeat2,
        catalog: enrichedCatalog,
        choices: <FeatureObjectSyncChoice>[
          candidate.toChoice(
            resolution: FeatureObjectSyncResolution.overwriteFromSource,
          ),
        ],
      );
      final warnings = overwritePreviews.single.localImpactedArtifactWarnings;
      expect(warnings.any((w) => w.contains('RG-201')), isTrue);
      expect(warnings.any((w) => w.contains('SCR-01')), isTrue);
      expect(warnings.any((w) => w.contains('FIX-01')), isTrue);
      expect(warnings.any((w) => w.contains('TDD-01')), isTrue);

      // En mode smartMerge, remisePourcent (ajout local absent de la baseline) est préservé -> 0 alerte !
      final mergePreviews = FeatureObjectSyncEngine.previewSync(
        project: projectForFeat2,
        catalog: enrichedCatalog,
        choices: <FeatureObjectSyncChoice>[
          candidate.toChoice(
            resolution: FeatureObjectSyncResolution.smartMerge,
          ),
        ],
      );
      expect(mergePreviews.single.localImpactedArtifactWarnings, isEmpty);

      final syncResult = FeatureObjectSyncEngine.executeSync(
        project: projectForFeat2,
        catalog: enrichedCatalog,
        choices: <FeatureObjectSyncChoice>[
          candidate.toChoice(
            resolution: FeatureObjectSyncResolution.smartMerge,
          ),
        ],
        now: t2,
      );
      expect(syncResult.mergedObjectIds, <String>['obj_contrat_canonique']);
      final syncedContrat = syncResult.updatedProject.businessObjects.single;
      expect(syncedContrat.id, 'obj_contrat_canonique');
      expect(
        syncedContrat.attributes.map((a) => a.name),
        containsAll(<String>[
          'id',
          'emailConducteur',
          'tarifJournalier',
          'codePartenaire',
          'remisePourcent',
        ]),
      );
      final designBaseline = syncResult.updatedProject.activeFeature
          .syncBaselineFor('obj_contrat_canonique')!;
      expect(designBaseline.sourceKind, ObjectSyncSourceKind.designDomain);
      expect(designBaseline.sourceDomainId, 'dom_booking');
      expect(designBaseline.sourceEntryId, contratEntry.id);

      // En mode skipExisting, aucune modification n'est appliquée et le nom est tracé dans skippedObjectNames.
      final skipResult = FeatureObjectSyncEngine.executeSync(
        project: projectForFeat2,
        catalog: enrichedCatalog,
        choices: <FeatureObjectSyncChoice>[
          candidate.toChoice(
            resolution: FeatureObjectSyncResolution.skipExisting,
          ),
        ],
        now: t2,
      );
      expect(skipResult.hasChanges, isFalse);
      expect(skipResult.skippedObjectNames, <String>['Contrat de location']);
      expect(skipResult.updatedProject, equals(projectForFeat2));
    });
  });

  group(
    'SpecDesignPromoter.contributingFeatures & SpecForgeController Undo/Redo',
    () {
      test('cumule contributingFeatures (FEAT-01 puis FEAT-02) lors de promotions séquentielles vers Design', () {
        final vehV1 = buildVehiculeV1().copyWith(
          relations: const <BusinessRelation>[],
          attributes: <BusinessAttribute>[
            BusinessAttribute(
              id: 'attr_veh_id',
              name: 'id',
              type: BusinessAttributeType.uuid,
              required: true,
              unique: true,
            ),
            BusinessAttribute(
              id: 'attr_veh_immat',
              name: 'immatriculation',
              type: BusinessAttributeType.string,
              required: true,
            ),
          ],
        );
        final vehV2 = vehV1.copyWith(
          attributes: <BusinessAttribute>[
            ...vehV1.attributes,
            BusinessAttribute(
              id: 'attr_veh_km',
              name: 'kilometrageRetour',
              type: BusinessAttributeType.integer,
            ),
          ],
        );

        final project = buildTwoFeatureProject(
          feat1Objects: <BusinessObjectSpec>[vehV1],
          feat1Rules: <BusinessRuleSpec>[
            BusinessRuleSpec(
              id: 'r1',
              code: 'RG-001',
              title: 'Format immatriculation SIV',
              targetObjectIds: const <String>['obj_vehicule'],
            ),
          ],
          feat2Objects: <BusinessObjectSpec>[vehV2],
          feat2Rules: <BusinessRuleSpec>[
            BusinessRuleSpec(
              id: 'r2',
              code: 'RG-002',
              title: 'Kilométrage retour cohérent',
              targetObjectIds: const <String>['obj_vehicule'],
            ),
          ],
          activeFeatureId: 'feat_01',
        );

        final initialCatalog = DomainCatalog(
          domains: const <FunctionalDomain>[
            FunctionalDomain(
              id: 'dom_fleet',
              domainCode: 'fleet',
              name: 'Parc Automobile',
            ),
          ],
        );

        // 1. Promotion depuis FEAT-01.
        final promo1 = SpecDesignPromoter.promote(
          project: project,
          catalog: initialCatalog,
          now: t1,
          choices: const <ObjectPromotionChoice>[
            ObjectPromotionChoice(
              objectId: 'obj_vehicule',
              domainId: 'dom_fleet',
              contractType: 'model',
            ),
          ],
        );
        final contractsAfter1 = promo1.updatedCatalog.domains.single.contracts!;
        final entry1 = SpecDesignPromoter.findExistingEntry(
          contractsAfter1,
          'Vehicule',
        )!;
        final origin1 = contractsAfter1.details[entry1.id]!.specOrigin!;
        expect(origin1.contributingFeatures, hasLength(1));
        expect(origin1.contributingFeatures.single.featureCode, 'FEAT-01');
        expect(
          origin1.contributingFeatures.single.featureName,
          'Gestion du parc',
        );
        expect(origin1.featuresSummaryLabel, 'FEAT-01');

        // 2. Promotion depuis FEAT-02 vers le même domaine Design.
        final projectOnFeat2 = project.selectFeature('feat_02');
        final promo2 = SpecDesignPromoter.promote(
          project: projectOnFeat2,
          catalog: promo1.updatedCatalog,
          now: t2,
          choices: const <ObjectPromotionChoice>[
            ObjectPromotionChoice(
              objectId: 'obj_vehicule',
              domainId: 'dom_fleet',
              contractType: 'model',
              conflictResolution: PromotionConflictResolution.smartMerge,
            ),
          ],
        );
        final contractsAfter2 = promo2.updatedCatalog.domains.single.contracts!;
        final origin2 = contractsAfter2.details[entry1.id]!.specOrigin!;
        expect(origin2.contributingFeatures, hasLength(2));
        expect(
          origin2.contributingFeatures.map((c) => c.featureCode).toList(),
          <String>['FEAT-01', 'FEAT-02'],
        );
        expect(
          origin2.contributingFeatures.map((c) => c.featureName).toList(),
          <String>['Gestion du parc', 'Retour de location'],
        );
        expect(origin2.featuresSummaryLabel, 'FEAT-01, FEAT-02');
        expect(
          origin2.ruleFingerprints.keys,
          containsAll(<String>['RG-001', 'RG-002']),
        );
      });

      test('SpecForgeController.syncBusinessObjectsIntoActiveFeature persiste la Feature active et supporte undo() / redo()', () async {
        final seededProject = buildTwoFeatureProject(
          feat1Objects: <BusinessObjectSpec>[buildAgence()],
          feat2Objects: const <BusinessObjectSpec>[],
          activeFeatureId: 'feat_02',
        );
        final projectStore = _MemorySpecProjectStore()..seed(seededProject);
        final controller = SpecForgeController(
          store: projectStore,
          domainCatalogStore: _MemoryDomainCatalogStore(),
          glossaryStore: _MemoryCompanyGlossaryStore(),
          modelDictionaryStore: _MemoryModelDictionaryStore(),
          enterpriseRateCardStore: _MemoryRateCardStore(),
          aiService: _NoopSpecAiService(),
        );
        addTearDown(controller.dispose);

        await controller.initialize();
        expect(controller.project!.activeFeature.id, 'feat_02');
        expect(controller.project!.businessObjects, isEmpty);
        expect(controller.canUndo, isFalse);

        final choices = <FeatureObjectSyncChoice>[
          const FeatureObjectSyncChoice(
            sourceObjectKey: 'obj_agence',
            sourceKind: ObjectSyncSourceKind.feature,
            sourceFeatureId: 'feat_01',
          ),
        ];

        final previews = controller.previewBusinessObjectSyncIntoActiveFeature(
          choices,
        );
        expect(previews, hasLength(1));
        expect(previews.single.isNewInTarget, isTrue);

        final syncRes = await controller.syncBusinessObjectsIntoActiveFeature(
          choices,
        );
        expect(syncRes.hasChanges, isTrue);
        expect(syncRes.importedObjectIds, <String>['obj_agence']);
        expect(controller.project!.businessObjects, hasLength(1));
        expect(
          controller.project!.activeFeature.syncBaselineFor('obj_agence'),
          isNotNull,
        );
        expect(
          projectStore.projects[seededProject.id]!.businessObjects,
          hasLength(1),
        );
        expect(controller.canUndo, isTrue);

        // Annulation Undo.
        await controller.undo();
        expect(controller.project!.businessObjects, isEmpty);
        expect(
          controller.project!.activeFeature.syncBaselineFor('obj_agence'),
          isNull,
        );
        expect(
          projectStore.projects[seededProject.id]!.businessObjects,
          isEmpty,
        );
        expect(controller.canRedo, isTrue);

        // Rétablissement Redo.
        await controller.redo();
        expect(controller.project!.businessObjects, hasLength(1));
        expect(
          controller.project!.activeFeature.syncBaselineFor('obj_agence'),
          isNotNull,
        );
        expect(
          projectStore.projects[seededProject.id]!.businessObjects,
          hasLength(1),
        );
      });
    },
  );
}
