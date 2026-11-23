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

      expect(find.text('Liste des modèles et contrats'), findsOneWidget);
    },
  );

  testWidgets(
    'Fin de spec : détection de conflit par objet et choix Mettre à jour vs Ignorer',
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
}
