import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/main.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_promote_store'));

  final Map<String, SpecForgeProject> _projects = {};
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
  Future<List<SpecProjectSummary>> listProjects() async => [
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
      super(Directory('memory_promote_store'));

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
  _MemoryCompanyGlossaryStore() : super(Directory('memory_promote_store'));

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
  _MemoryModelDictionaryStore() : super(Directory('memory_promote_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemoryRateCardStore extends EnterpriseRateCardStore {
  _MemoryRateCardStore() : super(Directory('memory_promote_store'));

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

SpecForgeProject _sampleReviewProject() {
  final now = DateTime.utc(2026, 6, 1);
  return SpecForgeProject(
    id: 'proj_promote',
    name: 'Suite ERP',
    initialIdea: 'Gestion clients et factures',
    createdAt: now,
    updatedAt: now,
    currentStage: SpecForgeStage.reviewExport,
    businessObjects: [
      BusinessObjectSpec(
        id: 'obj_client',
        name: 'Client',
        technicalName: 'Client',
        description: 'Fiche client référentiel',
        aggregateRoot: true,
        attributes: [
          BusinessAttribute(
            id: 'attr_client_id',
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
            unique: true,
          ),
          BusinessAttribute(
            id: 'attr_client_nom',
            name: 'nom',
            type: BusinessAttributeType.string,
            required: true,
          ),
        ],
      ),
      BusinessObjectSpec(
        id: 'obj_facture',
        name: 'Facture',
        technicalName: 'Facture',
        description: 'Facture émise au client',
        aggregateRoot: true,
        attributes: [
          BusinessAttribute(
            id: 'attr_fac_id',
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
            unique: true,
          ),
          BusinessAttribute(
            id: 'attr_fac_client',
            name: 'clientId',
            type: BusinessAttributeType.reference,
            referenceObjectId: 'obj_client',
            required: true,
          ),
        ],
      ),
      BusinessObjectSpec(
        id: 'obj_brouillon',
        name: 'Note interne',
        technicalName: 'NoteInterne',
        aggregateRoot: false,
      ),
    ],
  );
}

void main() {
  testWidgets(
    'Fin de spec : promotion par objet vers des domaines distincts (dont création inline) et ouverture dans Design',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final projectStore = _MemorySpecProjectStore()
        ..seed(_sampleReviewProject());
      final domainStore = _MemoryDomainCatalogStore(
        DomainCatalog(
          domains: const [
            FunctionalDomain(id: 'dom_crm', domainCode: 'crm', name: 'CRM'),
          ],
        ),
      );
      final controller = SpecForgeController(
        store: projectStore,
        domainCatalogStore: domainStore,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        enterpriseRateCardStore: _MemoryRateCardStore(),
        aiService: _NoopSpecAiService(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: true),
      );
      await tester.pumpAndSettle();

      // Ouvre le wizard Spec (positionné sur la dernière étape reviewExport)
      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      final promoteBtn = find.byKey(
        const ValueKey('spec-review-promote-to-design-btn'),
      );
      expect(promoteBtn, findsOneWidget);
      await tester.tap(promoteBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('promote-business-objects-dialog')),
        findsOneWidget,
      );

      // Création d'un second domaine "Facturation" directement depuis la modale
      await tester.tap(
        find.byKey(const ValueKey('promote-dialog-new-domain-btn')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('promote-new-domain-name-field')),
        'Facturation',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('promote-new-domain-save-btn')),
      );
      await tester.pumpAndSettle();

      expect(controller.domainCatalog.domains, hasLength(2));

      // Affecte Client -> CRM
      await tester.tap(find.byKey(const ValueKey('promote-domain-obj_client')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CRM').last);
      await tester.pumpAndSettle();

      // Affecte Facture -> Facturation et change son type DSL en xresponsedto
      await tester.tap(
        find.byKey(const ValueKey('promote-domain-obj_facture')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Facturation').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('promote-type-obj_facture')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('xresponsedto').last);
      await tester.pumpAndSettle();

      // Indication de référence hors domaine sur Facture (Client est dans CRM)
      expect(
        find.textContaining('référence(s) hors domaine convertie(s)'),
        findsOneWidget,
      );

      // NoteInterne n'est pas sélectionnée : seuls 2 objets seront promus
      expect(find.text('Promouvoir (2)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('promote-dialog-submit-btn')));
      await tester.pumpAndSettle();

      // Vérifie le catalogue mis à jour
      final crm = controller.domainCatalog.domains.firstWhere(
        (d) => d.domainCode == 'crm',
      );
      final billing = controller.domainCatalog.domains.firstWhere(
        (d) => d.domainCode == 'facturation',
      );
      expect(
        SpecDesignPromoter.findExistingEntry(crm.contracts, 'Client'),
        isNotNull,
      );
      expect(
        SpecDesignPromoter.findExistingEntry(crm.contracts, 'NoteInterne'),
        isNull,
      );
      final factureEntry = SpecDesignPromoter.findExistingEntry(
        billing.contracts,
        'Facture',
      );
      expect(factureEntry, isNotNull);
      expect(factureEntry!.type, 'xresponsedto');

      // Clic sur l'action du SnackBar "Ouvrir dans Design"
      await tester.tap(find.text('Ouvrir dans Design'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('contracts-list-crumb')),
        findsOneWidget,
      );
      expect(find.text('Modèles et contrats'), findsOneWidget);
    },
  );

  testWidgets(
    'Fin de spec : détection de conflit par objet et choix Fusionner vs Ignorer',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var preContracts = DomainContracts.parse(
        'models:\n  Client: model\n  Facture: model\ncomponents:\n',
      );
      final prevClient = SpecDesignPromoter.findExistingEntry(
        preContracts,
        'Client',
      )!;
      final prevFacture = SpecDesignPromoter.findExistingEntry(
        preContracts,
        'Facture',
      )!;
      preContracts = preContracts
          .withModel(
            prevClient.id,
            object: BusinessObjectSpec(
              id: prevClient.id,
              name: 'Client ancien',
              technicalName: 'Client',
              description: 'Ancienne description client',
            ),
          )
          .withModel(
            prevFacture.id,
            object: BusinessObjectSpec(
              id: prevFacture.id,
              name: 'Facture figée',
              technicalName: 'Facture',
              description: 'Description à préserver',
            ),
          );

      final projectStore = _MemorySpecProjectStore()
        ..seed(_sampleReviewProject());
      final domainStore = _MemoryDomainCatalogStore(
        DomainCatalog(
          domains: [
            FunctionalDomain(
              id: 'dom_crm',
              domainCode: 'crm',
              name: 'CRM',
              contracts: preContracts,
            ),
          ],
        ),
      );
      final controller = SpecForgeController(
        store: projectStore,
        domainCatalogStore: domainStore,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        enterpriseRateCardStore: _MemoryRateCardStore(),
        aiService: _NoopSpecAiService(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-review-promote-to-design-btn')),
      );
      await tester.pumpAndSettle();

      // Coche Client et Facture (le domaine CRM existant est déjà pré-identifié)
      await tester.tap(find.byKey(const ValueKey('promote-check-obj_client')));
      await tester.tap(find.byKey(const ValueKey('promote-check-obj_facture')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Déjà présent dans « CRM »'),
        findsNWidgets(2),
      );

      // Sur Facture, bascule le choix de conflit sur "Ignorer"
      final factureConflict = find.byKey(
        const ValueKey('promote-conflict-obj_facture'),
      );
      await tester.tap(
        find.descendant(of: factureConflict, matching: find.text('Ignorer')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('promote-dialog-submit-btn')));
      await tester.pumpAndSettle();

      final updatedContracts =
          controller.domainCatalog.domains.single.contracts!;
      // Client a été mis à jour
      expect(
        updatedContracts
            .objectFor(updatedContracts.entryById(prevClient.id)!)
            .description,
        'Fiche client référentiel',
      );
      // Facture a été ignorée
      expect(
        updatedContracts
            .objectFor(updatedContracts.entryById(prevFacture.id)!)
            .description,
        'Description à préserver',
      );
    },
  );

  testWidgets(
    'Promotion 3-voies : préserve le Value Object Design, affiche l’aperçu du merge et fusionne l’attribut d’Itération 2',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.utc(2026, 6, 15);
      final emailVo = ValueObjectPresets.standardPresets.firstWhere(
        (v) => v.technicalName == 'EmailAddress',
      );

      final iter1Project = SpecForgeProject(
        id: 'proj_merge_3way',
        name: 'Portail Clients',
        initialIdea: 'Référentiel client B2B',
        createdAt: now,
        updatedAt: now,
        currentStage: SpecForgeStage.reviewExport,
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_client',
            name: 'Client',
            technicalName: 'Client',
            description: 'Client B2B v1',
            aggregateRoot: true,
            attributes: [
              BusinessAttribute(
                id: 'attr_id',
                name: 'id',
                type: BusinessAttributeType.uuid,
                required: true,
                unique: true,
              ),
              BusinessAttribute(
                id: 'attr_email',
                name: 'email',
                type: BusinessAttributeType.email,
                required: true,
              ),
            ],
          ),
        ],
      );

      final projectStore = _MemorySpecProjectStore()..seed(iter1Project);
      final domainStore = _MemoryDomainCatalogStore(
        DomainCatalog(
          domains: const [
            FunctionalDomain(id: 'dom_crm', domainCode: 'crm', name: 'CRM'),
          ],
          sharedValueObjects: [emailVo],
        ),
      );
      final controller = SpecForgeController(
        store: projectStore,
        domainCatalogStore: domainStore,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        enterpriseRateCardStore: _MemoryRateCardStore(),
        aiService: _NoopSpecAiService(),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: true);

      // 1. Promotion Itération 1 : Client -> CRM
      await controller.promoteBusinessObjectsToDesign(const [
        ObjectPromotionChoice(
          objectId: 'obj_client',
          domainId: 'dom_crm',
          contractType: 'model',
        ),
      ]);

      final crmAfterIter1 = controller.domainCatalog.domains.single;
      final clientEntry = SpecDesignPromoter.findExistingEntry(
        crmAfterIter1.contracts,
        'Client',
      )!;

      // 2. Spécialisation côté Design : rattachement de `email` au ValueObject `EmailAddress`
      await controller.promoteAttributeToValueObject(
        domainId: 'dom_crm',
        entryId: clientEntry.id,
        attributePath: const ['attr_email'],
        valueObject: emailVo,
        scope: ValueObjectScope.shared,
        createIfMissing: false,
      );

      // 3. Évolution Spec en Itération 2 : ajout d'un attribut optionnel `telephone`
      final iter2Client = iter1Project.businessObjects.single.copyWith(
        attributes: [
          ...iter1Project.businessObjects.single.attributes,
          BusinessAttribute(
            id: 'attr_phone',
            name: 'telephone',
            type: BusinessAttributeType.string,
            description: 'Téléphone standard',
          ),
        ],
      );
      await controller.updateProject(
        controller.project!.copyWith(businessObjects: [iter2Client]),
      );

      // 4. Ouverture de PromoteBusinessObjectsDialog en Itération 2
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: FilledButton(
                  key: const ValueKey('open-promote-dialog-btn'),
                  onPressed: () => PromoteBusinessObjectsDialog.show(
                    ctx,
                    controller: controller,
                  ),
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-promote-dialog-btn')));
      await tester.pumpAndSettle();

      // Le domaine CRM est pré-détecté et les badges de diff / VO préservé s'affichent
      expect(
        find.byKey(const ValueKey('promote-status-obj_client')),
        findsOneWidget,
      );
      expect(find.text('Δ +1 / ~0 / -0'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('promote-vo-preserved-obj_client')),
        findsOneWidget,
      );
      expect(find.text('1 VO préservé(s)'), findsOneWidget);

      // 5. Ouverture et inspection de la modale « Aperçu du merge »
      await tester.tap(
        find.byKey(const ValueKey('promote-preview-obj_client')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('promote-merge-preview-dialog')),
        findsOneWidget,
      );
      expect(find.text('v0.0.1 → v0.1.0'), findsOneWidget);
      expect(find.text('Ajouté depuis la Spec'), findsOneWidget);
      expect(find.text('Value Object Design conservé'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('merge-preview-close-btn')));
      await tester.pumpAndSettle();

      // 6. Coche Client (stratégie par défaut = Fusionner (conserver Design)) + auto-bump SemVer
      await tester.tap(find.byKey(const ValueKey('promote-check-obj_client')));
      await tester.pumpAndSettle();
      expect(find.text('Fusionner (conserver Design)'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('promote-dialog-auto-bump-toggle')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('promote-dialog-submit-btn')));
      await tester.pumpAndSettle();

      // 7. Vérification : le contrat Design possède à la fois le VO préservé ET le nouvel attribut Spec !
      final finalContracts = controller.domainCatalog.domains.single.contracts!;
      final finalEntry = finalContracts.entryById(clientEntry.id)!;
      final mergedDesignObj = finalContracts.objectFor(finalEntry);
      final mergedDetails = finalContracts.details[finalEntry.id]!;

      expect(mergedDetails.version, '0.1.0');
      expect(mergedDesignObj.attributes, hasLength(3));

      final emailAttr = mergedDesignObj.attributes.firstWhere(
        (a) => a.name == 'email',
      );
      expect(emailAttr.type, BusinessAttributeType.valueObject);
      expect(emailAttr.valueObjectId, emailVo.id);

      final phoneAttr = mergedDesignObj.attributes.firstWhere(
        (a) => a.name == 'telephone',
      );
      expect(phoneAttr.type, BusinessAttributeType.string);
      expect(phoneAttr.description, 'Téléphone standard');
    },
  );

  testWidgets(
    'Vues Design : bannière de dérive amont Spec ↔ Design, jalon d’itération et badges d’évolution sur Contrats & Use Cases',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1480, 940));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.utc(2026, 7, 1);
      final initialProject = SpecForgeProject(
        id: 'proj_drift_ui',
        name: 'Facturation Suite',
        initialIdea: 'Facturation récurrente',
        createdAt: now,
        updatedAt: now,
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_invoice',
            name: 'Facture',
            technicalName: 'Facture',
            description: 'Facture client',
            aggregateRoot: true,
            attributes: [
              BusinessAttribute(
                id: 'attr_id',
                name: 'id',
                type: BusinessAttributeType.uuid,
                required: true,
                unique: true,
              ),
            ],
          ),
        ],
        businessRules: [
          BusinessRuleSpec(
            id: 'rule_1',
            code: 'RG-001',
            title: 'Montant positif',
            description: 'Le montant Facture est > 0',
            targetObjectIds: const ['obj_invoice'],
          ),
        ],
      );

      final projectStore = _MemorySpecProjectStore()..seed(initialProject);
      final domainStore = _MemoryDomainCatalogStore(
        DomainCatalog(
          domains: [
            FunctionalDomain(
              id: 'dom_bill',
              domainCode: 'billing',
              name: 'Facturation',
              useCaseOrchestration: UseCaseOrchestrationSpec(
                useCases: [
                  ApplicationUseCaseSpec(
                    id: 'uc_issue',
                    code: 'UC-001',
                    name: 'IssueInvoice',
                    title: 'Émettre une facture',
                    version: '1.0.0',
                    linkedSpecRefs: const ['RG-001', 'EXF-999'],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      final controller = SpecForgeController(
        store: projectStore,
        domainCatalogStore: domainStore,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        enterpriseRateCardStore: _MemoryRateCardStore(),
        aiService: _NoopSpecAiService(),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: true);

      // Promeut Facture vers Facturation puis capture un jalon d'itération
      await controller.promoteBusinessObjectsToDesign(const [
        ObjectPromotionChoice(
          objectId: 'obj_invoice',
          domainId: 'dom_bill',
          contractType: 'model',
        ),
      ]);
      await controller.createDomainIterationSnapshot(
        'dom_bill',
        label: 'Itération 1',
      );

      // Modifie la Spec en amont ET modifie le modèle en Design pour déclencher les deux signaux
      await controller.updateProject(
        controller.project!.copyWith(
          businessObjects: [
            initialProject.businessObjects.single.copyWith(
              attributes: [
                ...initialProject.businessObjects.single.attributes,
                BusinessAttribute(
                  id: 'attr_devise',
                  name: 'devise',
                  type: BusinessAttributeType.string,
                ),
              ],
            ),
          ],
        ),
      );
      final billContracts = controller.domainCatalog.domains.single.contracts!;
      final invoiceEntry = billContracts.groups.first.children.single;
      await controller.updateDomainModelObject(
        'dom_bill',
        billContracts
            .objectFor(invoiceEntry)
            .copyWith(description: 'Facture client enrichie en Design'),
      );

      // 1. ModelsContractsView : SnapshotBar + bannière de dérive Spec + fiche contrat
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelsContractsView(
              controller: controller,
              initialDomainId: 'dom_bill',
              onBack: () {},
              onManageDomains: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DomainIterationSnapshotBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('models-spec-drift-banner-dom_bill')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('models-spec-drift-details-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('models-spec-drift-dialog')),
        findsOneWidget,
      );
      expect(find.text('EXF-999'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('models-spec-drift-dialog-close-btn')),
      );
      await tester.pumpAndSettle();

      // Ouvre la fiche Facture (niveau 1) : badge d'origine Spec + EvolutionDriftBadge + SemVerBumpActionChip
      await tester.tap(
        find.byKey(ValueKey('open-${invoiceEntry.path}')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('contract-spec-origin-badge-${invoiceEntry.id}')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Origine Spec : Facturation Suite'),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('contract-evolution-badge-${invoiceEntry.id}')),
        findsOneWidget,
      );
      final bumpChip = find.byKey(
        ValueKey('contract-semver-bump-${invoiceEntry.id}'),
      );
      expect(bumpChip, findsOneWidget);
      await tester.tap(bumpChip);
      await tester.pumpAndSettle();
      expect(find.text('Version : 0.0.2'), findsOneWidget);

      // 2. UseCaseOrchestrationView : SnapshotBar + badge Δ Spec sur UC-001
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UseCaseOrchestrationView(
              controller: controller,
              initialDomainId: 'dom_bill',
              onBack: () {},
              onManageDomains: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DomainIterationSnapshotBar), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('usecase-tab-useCases')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('usecase-spec-drift-uc_issue')),
        findsOneWidget,
      );
      expect(find.text('Δ Spec (1)'), findsOneWidget);

      // Modifie le Use Case pour vérifier EvolutionDriftBadge + SemVerBumpActionChip
      final currentOrch =
          controller.domainCatalog.domains.single.useCaseOrchestration!;
      await controller.updateUseCaseOrchestration(
        'dom_bill',
        currentOrch.copyWith(
          useCases: [
            currentOrch.useCases.single.copyWith(
              businessGoal: 'Émettre et comptabiliser une facture client.',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('usecase-evolution-badge-uc_issue')),
        findsOneWidget,
      );
      final ucBump = find.byKey(const ValueKey('usecase-semver-bump-uc_issue'));
      expect(ucBump, findsOneWidget);
      await tester.tap(ucBump);
      await tester.pumpAndSettle();
      expect(
        controller.domainCatalog.domains.single.useCaseOrchestration!.useCases
            .single
            .version,
        isNot(equals('1.0.0')),
      );
      expect(
        DesignEvolutionAnalyzer.compareSemVer(
          controller.domainCatalog.domains.single.useCaseOrchestration!.useCases
              .single
              .version,
          '1.0.0',
        ),
        greaterThan(0),
      );
    },
  );
}
