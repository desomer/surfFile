import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_import_sync_ui_store'));

  final Map<String, SpecForgeProject> _projects = <String, SpecForgeProject>{};
  String? _lastActiveId;

  void seed(SpecForgeProject project) {
    _projects[project.id] = project;
    _lastActiveId = project.id;
  }

  @override
  Future<void> saveProject(SpecForgeProject project) async {
    project.validate();
    _projects[project.id] = project;
    _lastActiveId = project.id;
  }

  @override
  Future<SpecForgeProject?> loadProject(String projectId) async =>
      _projects[projectId];

  @override
  Future<void> deleteProject(String projectId) async {
    _projects.remove(projectId);
    if (_lastActiveId == projectId) _lastActiveId = null;
  }

  @override
  Future<List<SpecProjectSummary>> listProjects() async => <SpecProjectSummary>[
    for (final p in _projects.values)
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
      super(Directory('memory_import_sync_ui_store'));

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
  _MemoryCompanyGlossaryStore()
    : super(Directory('memory_import_sync_ui_store'));

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
  _MemoryModelDictionaryStore()
    : super(Directory('memory_import_sync_ui_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemoryRateCardStore extends EnterpriseRateCardStore {
  _MemoryRateCardStore() : super(Directory('memory_import_sync_ui_store'));

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

BusinessObjectSpec _buildVehicule() => BusinessObjectSpec(
  id: 'obj_vehicule',
  name: 'Véhicule',
  technicalName: 'Vehicule',
  description: 'Véhicule du parc automobile.',
  aggregateRoot: true,
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
  ],
);

BusinessRuleSpec _buildRg001() => BusinessRuleSpec(
  id: 'rule_immat',
  code: 'RG-001',
  title: 'Format immatriculation SIV obligatoire',
  category: BusinessRuleCategory.validation,
  priority: BusinessRulePriority.critical,
  targetObjectIds: const <String>['obj_vehicule'],
  targetAttributes: const <String>['Vehicule.immatriculation'],
  condition: 'Vehicule.immatriculation respecte le format AA-123-BB',
  effect: 'Autorise la mise en circulation du véhicule',
);

SpecForgeProject _buildFleetProject({
  required List<BusinessObjectSpec> feat1Objects,
  List<BusinessRuleSpec> feat1Rules = const <BusinessRuleSpec>[],
  List<BusinessObjectSpec> feat2Objects = const <BusinessObjectSpec>[],
  Map<String, FeatureObjectSyncBaseline> feat2Baselines =
      const <String, FeatureObjectSyncBaseline>{},
  List<BusinessRuleSpec> feat2Rules = const <BusinessRuleSpec>[],
}) {
  final now = DateTime.utc(2026, 11, 27, 10, 0);
  return SpecForgeProject(
    id: 'proj_fleet_ui',
    name: 'Parc Auto Pro',
    initialIdea: 'Gestion de flotte multi-lots',
    createdAt: now,
    updatedAt: now,
    initiatives: <SpecInitiative>[
      SpecInitiative(
        id: 'init_01',
        code: 'INIT-01',
        name: 'Socle Flotte',
        features: <SpecFeatureSpec>[
          SpecFeatureSpec(
            id: 'feat_01',
            code: 'FEAT-01',
            name: 'Référentiel Parc',
            status: SpecPortfolioStatus.validated,
            currentStage: SpecForgeStage.businessObjects,
            businessObjects: feat1Objects,
            businessRules: feat1Rules,
          ),
          SpecFeatureSpec(
            id: 'feat_02',
            code: 'FEAT-02',
            name: 'Télématique Lot 2',
            status: SpecPortfolioStatus.inProgress,
            currentStage: SpecForgeStage.businessObjects,
            businessObjects: feat2Objects,
            objectSyncBaselines: feat2Baselines,
            businessRules: feat2Rules,
          ),
        ],
      ),
    ],
    activeFeatureId: 'feat_02',
  );
}

Future<SpecForgeController> _initController({
  required SpecForgeProject project,
  DomainCatalog? catalog,
}) async {
  final projectStore = _MemorySpecProjectStore()..seed(project);
  final domainStore = _MemoryDomainCatalogStore(catalog);
  final controller = SpecForgeController(
    store: projectStore,
    domainCatalogStore: domainStore,
    glossaryStore: _MemoryCompanyGlossaryStore(),
    modelDictionaryStore: _MemoryModelDictionaryStore(),
    enterpriseRateCardStore: _MemoryRateCardStore(),
    aiService: _NoopSpecAiService(),
  );
  await controller.initialize(restoreLastProject: true);
  return controller;
}

void main() {
  testWidgets(
    'Test 1 : import inter-features depuis FEAT-01 (Validée) vers FEAT-02 conserve l’ID canonique et affiche le badge Partagé · FEAT-01',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = await _initController(
        project: _buildFleetProject(
          feat1Objects: <BusinessObjectSpec>[_buildVehicule()],
          feat1Rules: <BusinessRuleSpec>[_buildRg001()],
        ),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessObjectsEditorView(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // FEAT-02 est vide : le bouton d'état vide et le bouton d'en-tête sont tous deux présents.
      expect(
        find.byKey(const ValueKey('spec-objects-empty-import-sync-btn')),
        findsOneWidget,
      );
      final importBtn = find.byKey(
        const ValueKey('spec-objects-import-sync-btn'),
      );
      expect(importBtn, findsOneWidget);

      await tester.tap(importBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-sync-business-objects-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('FEAT-01 · Référentiel Parc'), findsWidgets);
      expect(find.text('Validée'), findsWidgets);
      expect(find.text('Nouveau dans FEAT-02'), findsOneWidget);

      // Coche Vehicule et valide l'import.
      await tester.tap(
        find.byKey(const ValueKey('import-sync-check-obj_vehicule')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synchroniser (1)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-sync-submit-btn')));
      await tester.pumpAndSettle();

      // SnackBar de confirmation et mise à jour de FEAT-02 avec l'ID canonique obj_vehicule.
      expect(find.text('1 objet(s) importé(s).'), findsOneWidget);
      final feat2Objects = controller.project!.activeFeature.businessObjects;
      expect(feat2Objects, hasLength(1));
      expect(feat2Objects.single.id, 'obj_vehicule');
      expect(feat2Objects.single.technicalName, 'Vehicule');

      // Le badge de partage inter-features apparaît sans alerte de rupture.
      final sharedBadge = find.byKey(
        const ValueKey('spec-object-shared-badge-obj_vehicule'),
      );
      expect(sharedBadge, findsOneWidget);
      expect(find.text('Partagé · FEAT-01'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-objects-cross-feature-warning-banner')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Test 2 : gouvernance additive_warn_on_validated (extension additive sans alerte, rupture sur RG-001 signalée et re-synchronisable en 3-voies)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final vehiculeV1 = _buildVehicule();
      final initialSynced = FeatureObjectSyncEngine.executeSync(
        project: _buildFleetProject(
          feat1Objects: <BusinessObjectSpec>[vehiculeV1],
          feat1Rules: <BusinessRuleSpec>[_buildRg001()],
        ),
        choices: const <FeatureObjectSyncChoice>[
          FeatureObjectSyncChoice(
            sourceObjectKey: 'obj_vehicule',
            sourceKind: ObjectSyncSourceKind.feature,
            sourceFeatureId: 'feat_01',
          ),
        ],
      ).updatedProject;

      final controller = await _initController(project: initialSynced);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessObjectsEditorView(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Ajout d'un attribut optionnel Lot 2 `gpsId` dans FEAT-02 -> extension additive autorisée sans bannière d'alerte !
      final vehiculeWithGps = vehiculeV1.copyWith(
        attributes: <BusinessAttribute>[
          ...vehiculeV1.attributes,
          BusinessAttribute(
            id: 'attr_veh_gps',
            name: 'gpsId',
            type: BusinessAttributeType.string,
            required: false,
            description: 'Identifiant boîtier télématique Lot 2',
          ),
        ],
      );
      await controller.updateProject(
        controller.project!.copyWith(
          businessObjects: <BusinessObjectSpec>[vehiculeWithGps],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-objects-cross-feature-warning-banner')),
        findsNothing,
      );
      expect(find.text('Partagé · FEAT-01'), findsOneWidget);

      // 2. Modification cassante dans FEAT-02 : retypage incompatible de `immatriculation` référencé par RG-001 de FEAT-01.
      final vehiculeBreaking = vehiculeWithGps.copyWith(
        attributes: <BusinessAttribute>[
          vehiculeV1.attributes.first,
          BusinessAttribute(
            id: 'attr_veh_immat',
            name: 'immatriculation',
            type: BusinessAttributeType.boolean,
            required: true,
          ),
          vehiculeWithGps.attributes.last,
        ],
      );
      await controller.updateProject(
        controller.project!.copyWith(
          businessObjects: <BusinessObjectSpec>[vehiculeBreaking],
          businessRules: <BusinessRuleSpec>[
            BusinessRuleSpec(
              id: 'rule_gps_local',
              code: 'RG-020',
              title: 'Format identifiant boîtier GPS',
              targetObjectIds: const <String>['obj_vehicule'],
              targetAttributes: const <String>['Vehicule.gpsId'],
              condition: 'Si Vehicule.gpsId est renseigné',
              effect: 'Vérifier préfixe GPS-',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // La bannière d'alerte Validée et le badge d'impact sur l'objet apparaissent.
      expect(
        find.byKey(const ValueKey('spec-objects-cross-feature-warning-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-object-shared-badge-obj_vehicule')),
        findsOneWidget,
      );
      expect(find.text('⚠ Impact FEAT-01'), findsOneWidget);

      // Ouvre la modale de détails des impacts et vérifie que RG-001 est listé.
      await tester.tap(
        find.byKey(
          const ValueKey('spec-objects-cross-feature-warning-details-btn'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('cross-feature-impact-details-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('RG-001'), findsWidgets);
      expect(
        find.text('Format immatriculation SIV obligatoire'),
        findsOneWidget,
      );

      // Clic 1-clic « Synchroniser depuis FEAT-01… » -> ouvre ImportSyncBusinessObjectsDialog pré-ciblé.
      await tester.tap(
        find.byKey(const ValueKey('cross-impact-sync-obj_vehicule-feat_01')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-sync-business-objects-dialog')),
        findsOneWidget,
      );
      expect(find.text('Synchroniser (1)'), findsOneWidget);

      // Vérifie l'ouverture de l'aperçu du merge avant réalignement.
      await tester.tap(
        find.byKey(const ValueKey('import-sync-preview-obj_vehicule')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('import-sync-merge-preview-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('import-sync-preview-close-btn')),
      );
      await tester.pumpAndSettle();

      // Bascule sur « Remplacer par la source » -> signale l'impact local sur RG-020 (gpsId retiré) puis réaligne FEAT-02 sur FEAT-01.
      await tester.tap(
        find.byKey(const ValueKey('import-sync-resolution-obj_vehicule')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remplacer par la source').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-sync-impact-pill-obj_vehicule')),
        findsOneWidget,
      );
      expect(find.text('⚠ 1 impact(s) local(aux) RG/UX/QA'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-sync-submit-btn')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-objects-cross-feature-warning-banner')),
        findsNothing,
      );
      expect(find.text('Partagé · FEAT-01'), findsOneWidget);
    },
  );

  testWidgets(
    'Test 3 : import depuis un Domaine Design convertit un ValueObjectSpec composite Money en sous-objet typé Spec',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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

      var contracts = DomainContracts.parse(
        'models:\n  FactureLocation: model\n\ncomponents:\n\ndto:\n  CreateFactureDto: createxdto\n\nmessage:\n',
      );
      final factureEntry = contracts.groups
          .expand((g) => g.children)
          .firstWhere((e) => e.name == 'FactureLocation');
      contracts = contracts.withModel(
        factureEntry.id,
        object: BusinessObjectSpec(
          id: factureEntry.id,
          name: 'Facture location',
          technicalName: 'FactureLocation',
          description: 'Facture issue du domaine Facturation.',
          aggregateRoot: true,
          attributes: <BusinessAttribute>[
            BusinessAttribute(
              id: 'attr_fac_id',
              name: 'id',
              type: BusinessAttributeType.uuid,
              required: true,
              unique: true,
            ),
            BusinessAttribute(
              id: 'attr_fac_total',
              name: 'montantTotal',
              type: BusinessAttributeType.valueObject,
              valueObjectId: 'vo_money',
              required: true,
              description: 'Total TTC facturé',
            ),
          ],
        ),
      );

      final catalog = DomainCatalog(
        sharedValueObjects: <ValueObjectSpec>[moneyVo],
        domains: <FunctionalDomain>[
          FunctionalDomain(
            id: 'dom_billing',
            domainCode: 'facturation',
            name: 'Facturation',
            contracts: contracts,
          ),
        ],
      );

      final controller = await _initController(
        project: _buildFleetProject(
          feat1Objects: <BusinessObjectSpec>[_buildVehicule()],
        ),
        catalog: catalog,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessObjectsEditorView(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('spec-objects-import-sync-btn')),
      );
      await tester.pumpAndSettle();

      // Bascule sur le mode « Depuis un Domaine Design ».
      await tester.tap(find.byKey(const ValueKey('import-sync-mode-design')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('import-sync-row-${factureEntry.id}')),
        findsOneWidget,
      );
      expect(find.text('FactureLocation'), findsWidgets);
      // Le DTO est masqué tant que l'option « Inclure DTOs & Messages » est décochée.
      expect(find.text('CreateFactureDto'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('import-sync-include-dtos-checkbox')),
      );
      await tester.pumpAndSettle();
      expect(find.text('CreateFactureDto'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey('import-sync-include-dtos-checkbox')),
      );
      await tester.pumpAndSettle();
      expect(find.text('CreateFactureDto'), findsNothing);

      await tester.tap(
        find.byKey(ValueKey('import-sync-check-${factureEntry.id}')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-sync-submit-btn')));
      await tester.pumpAndSettle();

      final imported = controller.project!.activeFeature.businessObjects.single;
      expect(imported.technicalName, 'FactureLocation');

      final montantAttr = imported.attributes.firstWhere(
        (a) => a.name == 'montantTotal',
      );
      expect(montantAttr.type, BusinessAttributeType.object);
      expect(montantAttr.valueObjectId, isEmpty);
      expect(montantAttr.children.map((c) => c.name).toList(), <String>[
        'amountMinorUnits',
        'currency',
      ]);
      expect(
        montantAttr.children
            .firstWhere((c) => c.name == 'amountMinorUnits')
            .type,
        BusinessAttributeType.integer,
      );

      // Le badge Sync · Design · Facturation est affiché sur la carte de l'objet importé.
      expect(
        find.byKey(ValueKey('spec-object-design-sync-badge-${imported.id}')),
        findsOneWidget,
      );
      expect(find.text('Sync · Design · Facturation'), findsOneWidget);
    },
  );
}
