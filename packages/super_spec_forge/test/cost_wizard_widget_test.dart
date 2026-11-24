import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/main.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemoryModelDictionaryStore extends ModelDictionaryStore {
  _MemoryModelDictionaryStore() : super(Directory('memory_cost_store'));

  BusinessObjectModelPreferences _prefs =
      BusinessObjectModelPreferences.defaults;

  @override
  Future<BusinessObjectModelPreferences> load() async => _prefs;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {
    preferences.validate();
    _prefs = preferences;
  }
}

class _MemoryCompanyGlossaryStore extends CompanyGlossaryStore {
  _MemoryCompanyGlossaryStore() : super(Directory('memory_cost_store'));

  CompanyGlossary _glossary = CompanyGlossary.empty;
  List<SpecChatMessage> _chat = const <SpecChatMessage>[];

  @override
  Future<CompanyGlossary> loadGlossary() async => _glossary;

  @override
  Future<void> saveGlossary(CompanyGlossary glossary) async {
    glossary.validate();
    _glossary = glossary;
  }

  @override
  Future<List<SpecChatMessage>> loadChatMessages() async => _chat;

  @override
  Future<void> saveChatMessages(List<SpecChatMessage> messages) async {
    _chat = List<SpecChatMessage>.unmodifiable(messages);
  }
}

class _MemoryDomainCatalogStore extends DomainCatalogStore {
  _MemoryDomainCatalogStore() : super(Directory('memory_cost_store'));

  DomainCatalog _catalog = DomainCatalog.empty;

  @override
  Future<DomainCatalog> load() async => _catalog;

  @override
  Future<void> save(DomainCatalog catalog) async {
    catalog.validate();
    _catalog = catalog;
  }
}

class _MemoryEnterpriseRateCardStore extends EnterpriseRateCardStore {
  _MemoryEnterpriseRateCardStore() : super(Directory('memory_cost_store'));

  EnterpriseRateCard _card = EnterpriseRateCard.defaults;

  @override
  Future<EnterpriseRateCard> load() async => _card;

  @override
  Future<void> save(EnterpriseRateCard card) async {
    card.validate();
    _card = card;
  }
}

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_cost_store'));

  final Map<String, SpecForgeProject> _projects = {};
  String? _lastActiveId;

  void seedProject(SpecForgeProject project) {
    project.validate();
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
        wbsItemCount: p.costSpec.wbsItems.length,
        runItemCount: p.costSpec.runItems.length,
        currentCostStage: p.costSpec.currentStage,
      ),
  ];

  @override
  Future<String?> getLastActiveProjectId() async => _lastActiveId;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {
    _lastActiveId = projectId;
  }
}

class _FakeCostAiService implements SpecAiService {
  final List<Map<String, Object?>> _queued = [];
  int callCount = 0;

  void enqueue(Map<String, Object?> payload) => _queued.add(payload);

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
    callCount++;
    final payload = _queued.isNotEmpty
        ? _queued.removeAt(0)
        : const <String, Object?>{
            'message': 'Chiffrage FinOps mis à jour.',
            'askUser': null,
            'costPatch': null,
            'specPatch': null,
            'stageReadyToAdvance': false,
          };
    final encoded = jsonEncode(payload);
    yield GeminiStreamEvent(
      deltaText: encoded,
      accumulatedText: encoded,
      isDone: true,
      usedContextCache: false,
    );
  }
}

SpecForgeProject _sampleProject() {
  return SpecForgeProject.fromIdea(
    idea: 'Plateforme B2B de gestion des flottes automobiles',
    name: 'FleetPulse',
    id: 'proj_fleetpulse',
  ).copyWith(
    cahierDesCharges: SpecCahierDesCharges(
      modules: const [SpecModule(id: 'mod_fleet', name: 'Gestion de flotte')],
      functionalRequirements: [
        FunctionalRequirement(
          id: 'ef_1',
          code: 'EF-001',
          title: 'Suivre le kilométrage des véhicules',
          moduleId: 'mod_fleet',
          priority: RequirementPriority.must,
        ),
        FunctionalRequirement(
          id: 'ef_2',
          code: 'EF-002',
          title: 'Alertes d’entretien préventif',
          moduleId: 'mod_fleet',
          priority: RequirementPriority.should,
        ),
      ],
    ),
    qaSpec: QaForgeSpec(currentStage: QaForgeStage.qaReviewExport),
  );
}

void main() {
  group('SpecLinksView & Wizard Estimation de coût IT', () {
    testWidgets(
      'affiche la carte Estimation de coût IT après le Wizard BDD, ouvre la Grille TJM d’entreprise et déroule les 4 étapes du Wizard Coûts',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final store = _MemorySpecProjectStore()..seedProject(_sampleProject());
        final ai = _FakeCostAiService()
          ..enqueue(<String, Object?>{
            'message': 'J’ai ajouté un lot sécurité SSO.',
            'askUser': null,
            'costPatch': <String, Object?>{
              'wbsItems': <Map<String, Object?>>[
                {
                  'id': 'wbs_ai_sso',
                  'code': 'WBS-050',
                  'title': 'Authentification SSO OIDC',
                  'discipline': 'devSecOps',
                  'priority': 'must',
                  'days': 5.0,
                },
              ],
            },
            'specPatch': null,
            'stageSummary': 'WBS enrichi.',
            'stageReadyToAdvance': true,
          });

        final controller = SpecForgeController(
          store: store,
          glossaryStore: _MemoryCompanyGlossaryStore(),
          modelDictionaryStore: _MemoryModelDictionaryStore(),
          domainCatalogStore: _MemoryDomainCatalogStore(),
          enterpriseRateCardStore: _MemoryEnterpriseRateCardStore(),
          aiService: ai,
          initialQuestioningLevel: VibeQuestioningLevel.none,
        );
        await controller.initialize();

        await tester.pumpWidget(SuperSpecForgeApp(controller: controller));
        await tester.pumpAndSettle();

        // Vérifie la présence dans le menu Spec et l'ordre après le Wizard BDD
        final qaCard = find.byKey(const ValueKey('spec-link-qa_wizard'));
        final costCard = find.byKey(
          const ValueKey('spec-link-cost_wizard'),
        );
        final rateCard = find.byKey(
          const ValueKey('spec-link-enterprise_rates'),
        );
        expect(qaCard, findsOneWidget);
        expect(costCard, findsOneWidget);
        expect(rateCard, findsOneWidget);

        final qaPos = tester.getTopLeft(qaCard);
        final costPos = tester.getTopLeft(costCard);
        expect(
          costPos.dy > qaPos.dy ||
              (costPos.dy == qaPos.dy && costPos.dx > qaPos.dx),
          isTrue,
        );

        // Ouvre la Grille TJM d'entreprise et applique au projet
        await tester.tap(rateCard);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('enterprise-rate-card-view')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
        );
        await tester.pumpAndSettle();

        // Ouvre le Wizard BDD (étape 4) et bascule vers l'Estimation de coût IT
        await tester.tap(qaCard);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('qa-continue-to-cost-wizard-btn')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('qa-continue-to-cost-wizard-btn')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('spec-forge-cost-wizard-view')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('cost-wizard-stepper')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('cost-assumptions-editor-view')),
          findsOneWidget,
        );

        // Étape 2 : Build WBS + pré-chiffrage automatique depuis la Spec
        await tester.tap(
          find.byKey(ValueKey('cost-step-${CostForgeStage.buildWbs.name}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cost-wbs-editor-view')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('cost-seed-wbs-btn')));
        await tester.pumpAndSettle();
        expect(controller.project!.costSpec.wbsItems.length, greaterThanOrEqualTo(2));

        // Envoi d'un prompt FinOps via le contrôleur et vérification du patch IA
        await controller.sendCostUserMessage('Ajoute le lot SSO');
        await tester.pumpAndSettle();
        expect(ai.callCount, 1);
        expect(
          controller.project!.costSpec.findWbsItem('WBS-050'),
          isNotNull,
        );

        // Étape 3 : Run OPEX
        await tester.tap(
          find.byKey(ValueKey('cost-step-${CostForgeStage.runOpex.name}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cost-run-editor-view')),
          findsOneWidget,
        );

        // Étape 4 : Synthèse TCO, Risques & Export
        await tester.tap(
          find.byKey(
            ValueKey('cost-step-${CostForgeStage.tcoReviewExport.name}'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cost-tco-review-export-view')),
          findsOneWidget,
        );
        expect(find.textContaining('TCO 3 ans'), findsOneWidget);
      },
    );
  });
}
