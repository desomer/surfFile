import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/main.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_usecase_store'));

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
      super(Directory('memory_usecase_store'));

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
  _MemoryCompanyGlossaryStore() : super(Directory('memory_usecase_store'));

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
  _MemoryModelDictionaryStore() : super(Directory('memory_usecase_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _FakeUseCaseAiService implements SpecAiService {
  String? lastPrompt;
  String? lastSystemInstruction;

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
  }) async* {
    lastPrompt = prompt;
    lastSystemInstruction = systemInstructionOverride;
    final payload = jsonEncode({
      'message':
          'Cartographie, Use Case CQRS et Saga générés à partir du projet.',
      'askUser': null,
      'specPatch': {
        'cartography': [
          {
            'boundedContext': 'Facturation',
            'description': 'Émission et validation des factures',
            'useCaseCodes': ['UC-001'],
            'sagaCodes': ['SAGA-001'],
          },
        ],
        'useCases': [
          {
            'code': 'UC-001',
            'name': 'UpdateInvoiceAmount',
            'title': 'Mettre à jour le montant d’une facture',
            'boundedContext': 'Facturation',
            'cqrsType': 'command',
            'targetAggregate': 'Facture',
            'businessGoal': 'Permettre la mise à jour d’une facture brouillon.',
            'triggerInputs': [
              {
                'name': 'invoiceId',
                'type': 'uuid',
                'required': true,
                'constraints': 'UUID',
                'description': 'Identifiant de la facture',
              },
              {
                'name': 'newAmount',
                'type': 'number',
                'required': true,
                'constraints': '> 0',
              },
              {
                'name': 'auditMeta',
                'type': 'object',
                'children': [
                  {'name': 'reason', 'type': 'string', 'nullable': true},
                ],
              },
            ],
            'businessRules': ['Le montant doit être strictement positif.'],
            'inboundPort': 'UpdateInvoiceAmountUseCase',
            'outboundPorts': ['InvoiceRepository'],
            'emittedEvents': ['InvoiceAmountUpdated'],
            'detailedProcess': [
              'Charger via InvoiceRepository.findById',
              'Sauvegarder la facture',
            ],
            'outputs': [
              {'name': 'invoiceId', 'type': 'uuid', 'required': true},
            ],
            'possibleErrors': ['InvoiceNotFound', 'InvalidAmount'],
            'scenarios': [
              {
                'name': 'Scénario nominal : Mise à jour réussie',
                'isNominal': true,
                'given': ['une facture existe'],
                'when': ['le montant est mis à jour'],
                'then': ['la facture est sauvegardée'],
              },
            ],
            'acceptanceCriteria': ['Le nouveau montant positif est persisté.'],
            'nonGoals': ['L’envoi comptable externe.'],
            'linkedSpecRefs': ['EXF-001'],
          },
        ],
        'sagas': [
          {
            'code': 'SAGA-001',
            'name': 'InvoiceSettlementSaga',
            'title': 'Orchestration de règlement facture',
            'boundedContexts': ['Facturation', 'Paiement'],
            'coordinationMode': 'orchestration',
            'triggerEventOrCommand': 'SettleInvoiceCommand',
            'correlationKey': 'invoiceId',
            'failureRecoveryStrategy': 'Retry 3x puis DLQ',
            'mermaidDiagram':
                'sequenceDiagram\n  Facturation->>Paiement: charge()',
            'compensationMatrix': [
              {
                'step': '1. Réservation crédit',
                'nominalAction': 'reserveCredit()',
                'compensationAction': 'releaseCredit()',
                'rollbackTrigger': 'PaymentFailed',
                'criticality': 'critical',
                'idempotent': true,
                'retryable': true,
                'timeout': '10s',
              },
            ],
          },
        ],
      },
    });
    yield GeminiStreamEvent(
      deltaText: payload,
      accumulatedText: payload,
      isDone: true,
      usedContextCache: false,
    );
  }
}

void main() {
  testWidgets(
    'Design › Cas d’usage & orchestration : état vide sans domaine, redirection Gestion des domaines et retour AppBar',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        domainCatalogStore: _MemoryDomainCatalogStore(),
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        aiService: _FakeUseCaseAiService(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Design'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('design-link-usecase_orchestration')),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Design › Cas d’usage & orchestration'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('design-domain-crumb')),
          matching: find.text('Aucun domaine'),
        ),
        findsOneWidget,
      );
      expect(find.text('Ajoutez un domaine pour commencer.'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('usecase-manage-domains-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('domain-management-view')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-design-view')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Design › Cas d’usage & orchestration : fil d’Ariane, chat à gauche, génération depuis le projet actif, 3 onglets et CRUD manuel',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.utc(2026, 6, 1);
      final projectStore = _MemorySpecProjectStore()
        ..activeProject = SpecForgeProject(
          id: 'proj_billing',
          name: 'Suite Facturation',
          initialIdea: 'Gestion des factures',
          createdAt: now,
          updatedAt: now,
          cahierDesCharges: SpecCahierDesCharges(
            useCases: [
              UseCaseSpec(
                id: 'UC-SPEC-01',
                title: 'Ajuster le montant d’une facture brouillon',
                actorId: 'Comptable',
              ),
            ],
            functionalRequirements: [
              FunctionalRequirement(
                id: 'req_1',
                code: 'EXF-001',
                title: 'Modification des montants',
              ),
            ],
          ),
        );

      final catalog = DomainCatalog(
        domains: [
          FunctionalDomain(
            id: 'dom_crm',
            domainCode: 'crm',
            name: 'CRM',
            contracts: DomainContracts.parse('models:\n  Client: model\n'),
          ),
          FunctionalDomain(
            id: 'dom_billing',
            domainCode: 'billing',
            name: 'Facturation',
            description: 'Émission et suivi des factures',
            contracts: DomainContracts.parse(
              'models:\n  Facture: model\ndto:\n  FactureDto: xresponsedto\n',
            ),
          ),
        ],
        microservices: const [
          Microservice(
            id: 'svc_billing',
            domainId: 'dom_billing',
            serviceCode: 'billing-api',
            name: 'Billing API',
          ),
        ],
      );

      final fakeAi = _FakeUseCaseAiService();
      final controller = SpecForgeController(
        store: projectStore,
        domainCatalogStore: _MemoryDomainCatalogStore(catalog),
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        aiService: fakeAi,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: true),
      );
      await tester.pumpAndSettle();

      // Sélectionne le second domaine via Gestion des domaines pour définir le domaine en cours.
      await tester.tap(find.text('Design'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('design-link-domain_management')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('domain-item-dom_billing')));
      await tester.pumpAndSettle();
      expect(controller.activeDesignDomainId, 'dom_billing');

      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();

      // Ouvre Cas d'usage & orchestration : démarre sur "Facturation" avec chat à gauche.
      await tester.tap(
        find.byKey(const ValueKey('design-link-usecase_orchestration')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('usecase-orchestration-view')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usecase-orchestration-chat-pane')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('design-domain-crumb')),
          matching: find.text('Facturation'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('usecase-source-project-chip')),
          matching: find.textContaining('Suite Facturation'),
        ),
        findsOneWidget,
      );

      // Repli puis réouverture du chat gauche.
      await tester.tap(
        find.byKey(const ValueKey('usecase-orchestration-chat-collapse')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('usecase-orchestration-chat-collapsed')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('usecase-orchestration-chat-expand')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('usecase-orchestration-chat-pane')),
        findsOneWidget,
      );

      // Compléter depuis le projet en cours via le bouton dédié.
      await tester.tap(
        find.byKey(const ValueKey('usecase-generate-from-project-btn')),
      );
      await tester.pumpAndSettle();

      expect(fakeAi.lastSystemInstruction, contains('CQRS'));
      expect(
        fakeAi.lastPrompt,
        contains('Ajuster le montant d’une facture brouillon'),
      );
      expect(fakeAi.lastPrompt, contains('EXF-001'));

      // Onglet 1 : Cartographie
      expect(find.text('Émission et validation des factures'), findsOneWidget);

      // Onglet 2 : Use Cases (10 sections + Given/When/Then)
      await tester.tap(find.byKey(const ValueKey('usecase-tab-useCases')));
      await tester.pumpAndSettle();
      expect(find.text('UpdateInvoiceAmount'), findsOneWidget);
      expect(find.text('Command'), findsOneWidget);
      expect(
        find.textContaining('UpdateInvoiceAmountUseCase'),
        findsOneWidget,
      );
      expect(find.textContaining('Given une facture existe'), findsOneWidget);

      final uc = controller.useCaseOrchestrationOf('dom_billing').useCases.first;
      final scn = uc.scenarios.first;

      // Indicateurs d'avancement des 4 phases sur le Use Case (1-clic pour cycler)
      for (final stage in ContractStage.values) {
        expect(
          find.byKey(ValueKey('usecase-phase-${uc.id}-${stage.name}')),
          findsOneWidget,
        );
      }
      await tester.tap(
        find.byKey(ValueKey('usecase-phase-${uc.id}-design')),
      );
      await tester.pumpAndSettle();
      expect(
        controller
            .useCaseOrchestrationOf('dom_billing')
            .useCases
            .first
            .states[ContractStage.design],
        ContractStatus.inProgress,
      );
      await tester.tap(
        find.byKey(ValueKey('usecase-phase-${uc.id}-design')),
      );
      await tester.pumpAndSettle();
      expect(
        controller
            .useCaseOrchestrationOf('dom_billing')
            .useCases
            .first
            .states[ContractStage.design],
        ContractStatus.done,
      );

      // Rendu arbre Objet métier sur les Inputs & Outputs (SuperTreeView + icônes + *)
      final inputsTree = find.byKey(ValueKey('usecase-inputs-tree-${uc.id}'));
      final outputsTree = find.byKey(
        ValueKey('usecase-outputs-tree-${uc.id}'),
      );
      expect(inputsTree, findsOneWidget);
      expect(outputsTree, findsOneWidget);
      expect(
        find.descendant(of: inputsTree, matching: find.byType(SuperTreeView)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: inputsTree, matching: find.text('Attributs (4)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: inputsTree, matching: find.text('auditMeta')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: inputsTree, matching: find.text('reason')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: inputsTree,
          matching: find.text('number! [> 0]'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: outputsTree, matching: find.text('Attributs (1)')),
        findsOneWidget,
      );

      // Clic sur un nœud d'input affiche son détail inline
      await tester.tap(
        find.descendant(of: inputsTree, matching: find.text('invoiceId')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: inputsTree,
          matching: find.text('Identifiant de la facture'),
        ),
        findsOneWidget,
      );

      // Replier / déplier un scénario individuel
      await tester.ensureVisible(
        find.byKey(ValueKey('usecase-scenario-toggle-${scn.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('usecase-scenario-toggle-${scn.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Given une facture existe'), findsNothing);
      await tester.tap(
        find.byKey(ValueKey('usecase-scenario-toggle-${scn.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Given une facture existe'), findsOneWidget);

      // Replier / déplier une section interne du Use Case
      await tester.ensureVisible(
        find.byKey(ValueKey('usecase-section-${uc.id}-ports')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('usecase-section-${uc.id}-ports')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('UpdateInvoiceAmountUseCase'), findsNothing);
      await tester.tap(
        find.byKey(ValueKey('usecase-section-${uc.id}-ports')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('UpdateInvoiceAmountUseCase'),
        findsOneWidget,
      );

      // Replier / déplier la carte Use Case complète
      await tester.ensureVisible(
        find.byKey(ValueKey('usecase-toggle-${uc.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('usecase-toggle-${uc.id}')));
      await tester.pumpAndSettle();
      expect(find.text('1. Objectif métier'), findsNothing);
      expect(find.text('UpdateInvoiceAmount'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('usecase-toggle-${uc.id}')));
      await tester.pumpAndSettle();
      expect(find.text('1. Objectif métier'), findsOneWidget);

      // Tout replier / Tout déplier sur l'onglet Use Cases
      await tester.tap(find.byKey(const ValueKey('usecase-collapse-all-btn')));
      await tester.pumpAndSettle();
      expect(find.text('1. Objectif métier'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('usecase-expand-all-btn')));
      await tester.pumpAndSettle();
      expect(find.text('1. Objectif métier'), findsOneWidget);

      // Ajout manuel d'un Use Case Query
      await tester.tap(find.byKey(const ValueKey('usecase-add-usecase-btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('usecase-form-name')),
        'GetInvoiceById',
      );
      await tester.enterText(
        find.byKey(const ValueKey('usecase-form-goal')),
        'Consulter le détail d’une facture.',
      );
      await tester.tap(find.byKey(const ValueKey('usecase-form-save-btn')));
      await tester.pumpAndSettle();
      expect(
        controller.useCaseOrchestrationOf('dom_billing').useCases,
        hasLength(2),
      );
      expect(
        controller.useCaseOrchestrationOf('dom_billing').useCases.last.name,
        'GetInvoiceById',
      );

      // Onglet 3 : Sagas & Compensations (Mermaid + matrice 8 colonnes)
      await tester.tap(find.byKey(const ValueKey('usecase-tab-sagas')));
      await tester.pumpAndSettle();
      expect(find.text('InvoiceSettlementSaga'), findsOneWidget);
      expect(
        find.textContaining('sequenceDiagram'),
        findsOneWidget,
      );
      expect(find.text('1. Réservation crédit'), findsOneWidget);
      expect(find.text('releaseCredit()'), findsOneWidget);
      expect(find.text('Critique'), findsOneWidget);

      final saga = controller.useCaseOrchestrationOf('dom_billing').sagas.first;
      final sagaTable = find.byKey(
        ValueKey('usecase-saga-supertable-${saga.id}'),
      );
      expect(sagaTable, findsOneWidget);
      expect(
        find.descendant(of: sagaTable, matching: find.byType(SuperTable)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sagaTable,
          matching: find.text('Action de Compensation (Rollback)'),
        ),
        findsOneWidget,
      );

      // Édition d'une ligne de compensation directement depuis la SuperTable
      final compRow = saga.compensationMatrix.first;
      final editRowBtn = find.byKey(ValueKey('saga-comp-edit-${compRow.id}'));
      await tester.ensureVisible(editRowBtn);
      await tester.pumpAndSettle();
      await tester.tap(editRowBtn);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('usecase-comp-field-step')),
        '1. Réservation crédit client',
      );
      await tester.tap(find.byKey(const ValueKey('usecase-comp-save-btn')));
      await tester.pumpAndSettle();
      expect(
        controller
            .useCaseOrchestrationOf('dom_billing')
            .sagas
            .first
            .compensationMatrix
            .first
            .step,
        '1. Réservation crédit client',
      );

      // Indicateurs d'avancement des 4 phases sur la Saga
      for (final stage in ContractStage.values) {
        expect(
          find.byKey(ValueKey('usecase-saga-phase-${saga.id}-${stage.name}')),
          findsOneWidget,
        );
      }
      await tester.ensureVisible(
        find.byKey(ValueKey('usecase-saga-phase-${saga.id}-validation')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('usecase-saga-phase-${saga.id}-validation')),
      );
      await tester.pumpAndSettle();
      expect(
        controller
            .useCaseOrchestrationOf('dom_billing')
            .sagas
            .first
            .states[ContractStage.validation],
        ContractStatus.inProgress,
      );

      // Replier / déplier les sections Mermaid et Matrice des compensations
      await tester.tap(
        find.byKey(ValueKey('usecase-saga-section-${saga.id}-mermaid')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('sequenceDiagram'), findsNothing);
      await tester.tap(
        find.byKey(ValueKey('usecase-saga-section-${saga.id}-matrix')),
      );
      await tester.pumpAndSettle();
      expect(find.text('releaseCredit()'), findsNothing);

      // Tout déplier rétablit les sections internes de la Saga
      await tester.tap(
        find.byKey(const ValueKey('usecase-sagas-expand-all-btn')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('sequenceDiagram'), findsOneWidget);
      expect(find.text('releaseCredit()'), findsOneWidget);

      // Replier / déplier la carte Saga complète
      await tester.tap(find.byKey(ValueKey('usecase-saga-toggle-${saga.id}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('sequenceDiagram'), findsNothing);
      expect(find.text('InvoiceSettlementSaga'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('usecase-saga-toggle-${saga.id}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('sequenceDiagram'), findsOneWidget);

      // Change de domaine depuis le fil d'Ariane vers "CRM".
      await tester.tap(find.byKey(const ValueKey('design-domain-crumb')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('design-domain-option-dom_crm')),
      );
      await tester.pumpAndSettle();

      expect(controller.activeDesignDomainId, 'dom_crm');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('design-domain-crumb')),
          matching: find.text('CRM'),
        ),
        findsOneWidget,
      );

      // Retour au menu Design puis ouverture de Modèles & Contrats : "CRM" est conservé.
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('design-link-models_contracts')),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('design-domain-crumb')),
          matching: find.text('CRM'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Design › Cas d’usage & orchestration : bouton Aperçu Mermaid de la Saga ouvre le visualisateur avec le diagramme',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final catalog = DomainCatalog(
        domains: [
          FunctionalDomain(
            id: 'dom_billing',
            domainCode: 'billing',
            name: 'Facturation',
            useCaseOrchestration: UseCaseOrchestrationSpec(
              sagas: [
                OrchestrationSagaSpec(
                  id: 'saga_1',
                  code: 'SAGA-001',
                  name: 'InvoiceSettlementSaga',
                  title: 'Règlement facture',
                  mermaidDiagram:
                      'sequenceDiagram\n  Facturation->>Paiement: charge()',
                ),
              ],
            ),
          ),
        ],
      );

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        domainCatalogStore: _MemoryDomainCatalogStore(catalog),
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        aiService: _FakeUseCaseAiService(),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      File? renderedFile;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UseCaseOrchestrationView(
              controller: controller,
              onBack: () {},
              onManageDomains: () {},
              markdownViewerSurfaceBuilder: (context, htmlFile, _) {
                renderedFile = htmlFile;
                return const SizedBox(
                  key: ValueKey('fake-mermaid-preview-surface'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('usecase-tab-sagas')));
      await tester.pumpAndSettle();

      final previewBtn = find.byKey(
        const ValueKey('usecase-saga-mermaid-preview-saga_1'),
      );
      expect(previewBtn, findsOneWidget);
      await tester.tap(previewBtn);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
        if (find
            .byKey(const ValueKey('fake-mermaid-preview-surface'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('fake-mermaid-preview-surface')),
        findsOneWidget,
      );
      expect(renderedFile, isNotNull);
      final renderedHtml = await tester.runAsync(
        () => renderedFile!.readAsString(),
      );
      expect(renderedHtml, contains('InvoiceSettlementSaga'));
      expect(renderedHtml, contains('sequenceDiagram'));
      expect(renderedHtml, contains('ssf-mermaid-card'));
      expect(renderedHtml, contains('ssf-mermaid-lightbox'));
      expect(renderedHtml, contains('ssf-mermaid-expand-btn'));
      expect(renderedHtml, contains('openMermaidFullscreen'));

      // Vérifie le mode presque plein écran (1400-20 x 900-20) et son bouton bascule
      final containerFinder = find.byKey(
        const ValueKey('spec-md-viewer-container'),
      );
      expect(containerFinder, findsOneWidget);
      expect(tester.getSize(containerFinder), const Size(1380, 880));

      await tester.tap(
        find.byKey(const ValueKey('spec-md-viewer-toggle-fullscreen')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(containerFinder),
        Size(1400 * 0.92, 900 * 0.92),
      );

      await tester.tap(
        find.byKey(const ValueKey('spec-md-viewer-toggle-fullscreen')),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(containerFinder), const Size(1380, 880));
    },
  );
}
