import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemProjectStore extends SpecProjectStore {
  _MemProjectStore() : super(Directory('memory_es_store'));

  final Map<String, SpecForgeProject> _projects = {};
  String? _lastId;

  void seed(SpecForgeProject project) {
    _projects[project.id] = project;
    _lastId = project.id;
  }

  @override
  Future<void> saveProject(SpecForgeProject project) async {
    project.validate();
    _projects[project.id] = project;
    _lastId = project.id;
  }

  @override
  Future<SpecForgeProject?> loadProject(String projectId) async =>
      _projects[projectId];

  @override
  Future<void> deleteProject(String projectId) async {
    _projects.remove(projectId);
    if (_lastId == projectId) _lastId = null;
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
  Future<String?> getLastActiveProjectId() async => _lastId;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {
    _lastId = projectId;
  }
}

class _MemGlossaryStore extends CompanyGlossaryStore {
  _MemGlossaryStore() : super(Directory('memory_es_store'));

  @override
  Future<CompanyGlossary> loadGlossary() async => CompanyGlossary.empty;

  @override
  Future<void> saveGlossary(CompanyGlossary glossary) async {}

  @override
  Future<List<SpecChatMessage>> loadChatMessages() async => const [];

  @override
  Future<void> saveChatMessages(List<SpecChatMessage> messages) async {}
}

class _MemDictStore extends ModelDictionaryStore {
  _MemDictStore() : super(Directory('memory_es_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemDomainStore extends DomainCatalogStore {
  _MemDomainStore() : super(Directory('memory_es_store'));

  @override
  Future<DomainCatalog> load() async => DomainCatalog.empty;

  @override
  Future<void> save(DomainCatalog catalog) async {}
}

class _FakeEventStormingAi implements SpecAiService {
  final List<SpecForgeStage> calledStages = [];
  final List<String> receivedPrompts = [];

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
    calledStages.add(stage);
    receivedPrompts.add(prompt);
    const json =
        '{"message":"Flux Event Storming ES-AI structuré avec 1 événement pivot et 1 politique.","askUser":null,"specPatch":{"eventStorming":{"boundedContexts":[{"id":"bc_ventes","code":"BC-001","name":"Ventes"}],"flows":[{"id":"es_ai_cmd","code":"ES-099","title":"Validation commande B2B","boundedContextIds":["bc_ventes"],"requirementIds":["EXF-001"],"nodes":[{"id":"n_act","kind":"actor","title":"Acheteur","sequenceOrder":1,"boundedContextId":"bc_ventes"},{"id":"n_cmd","kind":"command","title":"ValiderCommande","sequenceOrder":2,"boundedContextId":"bc_ventes","payloadFields":["commandeId","montantHt"]},{"id":"n_agg","kind":"aggregate","title":"CommandeClient","sequenceOrder":3,"boundedContextId":"bc_ventes"},{"id":"n_evt","kind":"domainEvent","title":"CommandeValidee","sequenceOrder":4,"boundedContextId":"bc_ventes","isPivotal":true,"payloadFields":["commandeId","valideeLe"]},{"id":"n_pol","kind":"policy","title":"Quand CommandeValidee -> NotifierLogistique","sequenceOrder":5,"boundedContextId":"bc_ventes"}],"links":[{"id":"l_1","fromNodeId":"n_act","toNodeId":"n_cmd","kind":"triggers"},{"id":"l_2","fromNodeId":"n_cmd","toNodeId":"n_agg","kind":"handles"},{"id":"l_3","fromNodeId":"n_agg","toNodeId":"n_evt","kind":"emits"},{"id":"l_4","fromNodeId":"n_evt","toNodeId":"n_pol","kind":"reactsTo"}]}]}},"stageSummary":"1 flux ES-099 modélisé","stageReadyToAdvance":true}';
    yield const GeminiStreamEvent(
      deltaText: json,
      accumulatedText: json,
      isDone: true,
      usedContextCache: false,
    );
  }
}

SpecForgeProject _buildSampleProject({
  EventStormingSpec? eventStorming,
  SpecForgeStage currentStage = SpecForgeStage.eventStorming,
}) {
  final now = DateTime.utc(2026, 11, 23, 21);
  return SpecForgeProject(
    id: 'proj_es_test',
    name: 'Commandes B2B',
    initialIdea: 'Plateforme de gestion de commandes B2B avec validation et expédition',
    createdAt: now,
    updatedAt: now,
    currentStage: currentStage,
    vision: SpecVision(
      personas: [
        SpecPersona(
          id: 'p_acheteur',
          name: 'Acheteur',
          role: 'Passe et valide les commandes',
        ),
      ],
    ),
    cahierDesCharges: SpecCahierDesCharges(
      modules: const [
        SpecModule(
          id: 'mod_ventes',
          name: 'Ventes',
          description: 'Gestion des commandes clients',
        ),
      ],
      functionalRequirements: [
        FunctionalRequirement(
          id: 'req_1',
          code: 'EXF-001',
          title: 'Validation d’une commande client',
          moduleId: 'mod_ventes',
          actorIds: const ['p_acheteur'],
        ),
      ],
      useCases: [
        UseCaseSpec(
          id: 'uc_valider_cmd',
          title: 'Valider une Commande',
          actorId: 'p_acheteur',
          mainFlow: const ['Sélectionner brouillon', 'Valider montant'],
          alternativeFlows: const ['Plafond dépassé -> alerte'],
          postconditions: const ['CommandeValidee'],
        ),
      ],
    ),
    eventStorming: eventStorming,
  );
}

void main() {
  group('Modèles, Patch & Persistance Event Storming', () {
    test('SpecForgeStage compte 8 étapes avec eventStorming en étape 4', () {
      expect(SpecForgeStage.values.length, 8);
      expect(SpecForgeStage.eventStorming.stepNumber, 4);
      expect(
        SpecForgeStage.specifications.next,
        SpecForgeStage.eventStorming,
      );
      expect(
        SpecForgeStage.eventStorming.previous,
        SpecForgeStage.specifications,
      );
      expect(
        SpecForgeStage.eventStorming.next,
        SpecForgeStage.businessObjects,
      );
      expect(SpecForgeStage.businessObjects.stepNumber, 5);
      expect(SpecForgeStage.exampleMapping.stepNumber, 6);
      expect(SpecForgeStage.businessRules.stepNumber, 7);
      expect(SpecForgeStage.reviewExport.stepNumber, 8);
      expect(
        SpecForgeStage.fromJson('event_storming'),
        SpecForgeStage.eventStorming,
      );
      expect(
        SpecForgeStage.fromJson('eventStorming'),
        SpecForgeStage.eventStorming,
      );
    });

    test('EventStormingSpec round-trip JSON, alias LLM et rétrocompatibilité', () {
      expect(EventStormNodeKind.fromJson('event'), EventStormNodeKind.domainEvent);
      expect(EventStormNodeKind.fromJson('reactor'), EventStormNodeKind.policy);
      expect(
        EventStormNodeKind.fromJson('read_model'),
        EventStormNodeKind.readModel,
      );
      expect(EventStormNodeKind.fromJson('question'), EventStormNodeKind.hotspot);

      final base = _buildSampleProject();
      final applied = SpecPatchApplier.apply(base, {
        'eventStorming': {
          'boundedContexts': [
            {
              'id': 'bc_sales',
              'code': 'BC-001',
              'name': 'Ventes',
              'description': 'Cycle commercial',
            },
          ],
          'flows': [
            {
              'id': 'es_1',
              'code': 'ES-001',
              'title': 'Validation commande',
              'boundedContextIds': ['bc_sales'],
              'requirementIds': ['EXF-001'],
              'nodes': [
                {
                  'id': 'n_act',
                  'kind': 'actor',
                  'title': 'Acheteur',
                  'sequenceOrder': 1,
                  'boundedContextId': 'bc_sales',
                },
                {
                  'id': 'n_rmd',
                  'kind': 'read_model',
                  'title': 'Panier courant',
                  'sequenceOrder': 2,
                  'boundedContextId': 'bc_sales',
                },
                {
                  'id': 'n_cmd',
                  'kind': 'command',
                  'title': 'ValiderCommande',
                  'sequenceOrder': 3,
                  'boundedContextId': 'bc_sales',
                  'payloadFields': ['commandeId', 'montantHt'],
                },
                {
                  'id': 'n_agg',
                  'kind': 'aggregate',
                  'title': 'CommandeClient',
                  'sequenceOrder': 4,
                  'boundedContextId': 'bc_sales',
                },
                {
                  'id': 'n_evt',
                  'kind': 'event',
                  'title': 'CommandeValidee',
                  'sequenceOrder': 5,
                  'boundedContextId': 'bc_sales',
                  'pivotal': true,
                  'payloadFields': ['commandeId', 'valideeLe'],
                },
                {
                  'id': 'n_pol',
                  'kind': 'policy',
                  'title': 'Quand CommandeValidee -> Facturer',
                  'sequenceOrder': 6,
                  'boundedContextId': 'bc_sales',
                },
                {
                  'id': 'n_hot',
                  'kind': 'hotspot',
                  'title': 'Délai d’expiration ?',
                  'sequenceOrder': 7,
                  'boundedContextId': 'bc_sales',
                },
              ],
              'links': [
                {
                  'id': 'l_1',
                  'fromNodeId': 'n_act',
                  'toNodeId': 'n_cmd',
                  'kind': 'triggers',
                },
                {
                  'id': 'l_2',
                  'fromNodeId': 'n_cmd',
                  'toNodeId': 'n_agg',
                  'kind': 'handles',
                },
                {
                  'id': 'l_3',
                  'fromNodeId': 'n_agg',
                  'toNodeId': 'n_evt',
                  'kind': 'emits',
                },
              ],
            },
          ],
        },
      });

      expect(applied.project.eventStorming.boundedContexts, hasLength(1));
      expect(applied.project.eventStorming.flows, hasLength(1));
      expect(applied.project.eventStorming.totalEventCount, 1);
      expect(applied.project.eventStorming.openHotspotCount, 1);

      final roundTrip = SpecForgeProject.fromJson(applied.project.toJson());
      expect(roundTrip.eventStorming, applied.project.eventStorming);

      // Rétrocompatibilité sans clé eventStorming
      final legacyJson = Map<String, Object?>.from(applied.project.toJson())
        ..remove('eventStorming');
      final legacyLoaded = SpecForgeProject.fromJson(legacyJson);
      expect(legacyLoaded.eventStorming.hasContent, isFalse);

      // Suppression ciblée
      final removed = SpecPatchApplier.apply(applied.project, {
        'removeFlowIds': ['es_1'],
        'removeBoundedContextIds': ['bc_sales'],
      });
      expect(removed.project.eventStorming.hasContent, isFalse);
    });

    test('SpecPatchApplier.applyPartial conserve les flux valides malgré une entrée invalide', () {
      final base = _buildSampleProject();
      final partial = SpecPatchApplier.applyPartial(base, {
        'eventStorming': {
          'flows': [
            {
              'id': 'es_ok',
              'code': 'ES-001',
              'title': 'Flux valide',
              'nodes': [
                {'id': 'n1', 'kind': 'domainEvent', 'title': 'CommandeCreee'},
              ],
            },
            'entree_invalide',
          ],
        },
      });
      expect(partial.project.eventStorming.flows, hasLength(1));
      expect(partial.rejectedEntries, hasLength(1));
    });
  });

  group('Opérations, Cohérence, Exports & Outils Event Storming', () {
    test('EventStormingOperations amorce depuis CDC, synthétise Objets métiers et promeut Politique en RG', () {
      final base = _buildSampleProject();

      // 1. Amorçage depuis le Cahier des charges
      final seeded = EventStormingOperations.seedFromCahierDesCharges(base);
      expect(seeded.addedContextsCount, 1);
      expect(seeded.addedFlowsCount, 1);
      final flow = seeded.updated.flows.single;
      expect(flow.code, 'ES-001');
      expect(flow.nodes.any((n) => n.kind == EventStormNodeKind.aggregate), isTrue);
      expect(flow.nodes.any((n) => n.kind == EventStormNodeKind.domainEvent), isTrue);

      // 2. Synthèse d'objets métiers + cycle de vie depuis les agrégats/événements
      final withEs = base.copyWith(eventStorming: seeded.updated);
      final synthesized =
          EventStormingOperations.synthesizeBusinessObjectsFromEventStorming(
            withEs,
          );
      expect(synthesized.createdObjectsCount, 1);
      final createdObj = synthesized.project.businessObjects.single;
      expect(createdObj.aggregateRoot, isTrue);
      expect(createdObj.lifecycleStates, isNotEmpty);
      expect(createdObj.lifecycleTransitions, isNotEmpty);

      // 3. Promotion d'une politique lilas en règle RG-001
      final policyNode = EventStormNode(
        id: 'n_pol',
        kind: EventStormNodeKind.policy,
        title: 'Quand CommandeValidee -> RéserverStock',
        sequenceOrder: 6,
      );
      final flowWithPolicy = synthesized.project.eventStorming.flows.single
          .copyWith(
            nodes: [
              ...synthesized.project.eventStorming.flows.single.nodes,
              policyNode,
            ],
          );
      final withPolicy = synthesized.project.copyWith(
        eventStorming: synthesized.project.eventStorming.copyWith(
          flows: [flowWithPolicy],
        ),
      );
      final promoted = EventStormingOperations.promotePolicyToBusinessRule(
        withPolicy,
        flowId: flowWithPolicy.id,
        nodeId: 'n_pol',
      );
      expect(promoted.createdNew, isTrue);
      expect(promoted.rule.code, 'RG-001');
      expect(promoted.rule.category, BusinessRuleCategory.trigger);
      expect(
        promoted.project.eventStorming.flows.single.nodes
            .firstWhere((n) => n.id == 'n_pol')
            .linkedRuleId,
        'RG-001',
      );
    });

    test('SpecCoherenceAnalyzer, SpecMarkdownExporter (Mermaid) et get_event_storming fonctionnent', () async {
      final project = _buildSampleProject(
        eventStorming: EventStormingSpec(
          boundedContexts: const [
            EventStormBoundedContext(
              id: 'bc_1',
              code: 'BC-001',
              name: 'Ventes',
            ),
          ],
          flows: [
            EventStormBoard(
              id: 'es_1',
              code: 'ES-001',
              title: 'Cycle commande',
              boundedContextIds: const ['bc_1'],
              nodes: [
                EventStormNode(
                  id: 'n1',
                  kind: EventStormNodeKind.actor,
                  title: 'Acheteur',
                  sequenceOrder: 1,
                  boundedContextId: 'bc_1',
                ),
                EventStormNode(
                  id: 'n2',
                  kind: EventStormNodeKind.command,
                  title: 'ValiderCommande',
                  sequenceOrder: 2,
                  boundedContextId: 'bc_1',
                ),
                EventStormNode(
                  id: 'n3',
                  kind: EventStormNodeKind.domainEvent,
                  title: 'CommandeValidee',
                  sequenceOrder: 3,
                  boundedContextId: 'bc_1',
                  isPivotal: true,
                ),
                EventStormNode(
                  id: 'n4',
                  kind: EventStormNodeKind.hotspot,
                  title: 'Délai annulation ?',
                  sequenceOrder: 4,
                  boundedContextId: 'bc_1',
                ),
              ],
              links: const [
                EventStormLink(
                  id: 'l1',
                  fromNodeId: 'n1',
                  toNodeId: 'n2',
                  kind: EventStormLinkKind.triggers,
                ),
                EventStormLink(
                  id: 'l2',
                  fromNodeId: 'n2',
                  toNodeId: 'n3',
                  kind: EventStormLinkKind.emits,
                ),
              ],
            ),
          ],
        ),
      );

      final issues = SpecCoherenceAnalyzer.analyze(project);
      expect(issues.any((i) => i.code == 'COH-ES-002'), isTrue);

      final md = SpecMarkdownExporter.export(project);
      expect(
        md,
        contains(
          '## 4. Event Storming (Flux, Événements, Commandes, Politiques & Contextes)',
        ),
      );
      expect(md, contains('flowchart LR'));
      expect(md, contains('classDef domainEvent'));
      expect(md, contains('subgraph bc_1'));
      expect(md, contains('CommandeValidee ★'));

      SpecForgeStage? navigated;
      String? focusedFlow;
      final registry = SpecForgeToolRegistry.build(
        readProject: () => project,
        onNavigateStage: (s) async => navigated = s,
        onFocusEventStormFlow: (id) => focusedFlow = id,
      );
      final res = await registry.execute(
        VibeToolCall(
          id: 'tc_es',
          name: 'get_event_storming',
          arguments: const {'onlyOpenHotspots': true},
        ),
      );
      expect(res.isError, isFalse);
      expect(res.data['flowCount'], 1);
      expect(res.data['openHotspotCount'], 1);

      final focusRes = await registry.execute(
        VibeToolCall(
          id: 'tc_focus_es',
          name: 'focus_stage_or_object',
          arguments: const {
            'stage': 'eventStorming',
            'eventStormFlowId': 'ES-001',
          },
        ),
      );
      expect(focusRes.isError, isFalse);
      expect(navigated, SpecForgeStage.eventStorming);
      expect(focusedFlow, 'es_1');
    });
  });

  group('Atelier UI & Stepper Event Storming', () {
    testWidgets(
      'Stepper 8 étapes, EventStormingEditorView 1-clic et tour IA fonctionnent sans erreur',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1480, 920));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final store = _MemProjectStore()..seed(_buildSampleProject());
        final fakeAi = _FakeEventStormingAi();
        final controller = SpecForgeController(
          store: store,
          glossaryStore: _MemGlossaryStore(),
          modelDictionaryStore: _MemDictStore(),
          domainCatalogStore: _MemDomainStore(),
          aiService: fakeAi,
          initialQuestioningLevel: VibeQuestioningLevel.none,
        );
        await controller.initialize();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SpecWizardStepper(
                project: controller.project!,
                onSelectStage: controller.goToStage,
              ),
            ),
          ),
        );
        expect(find.text('Event Storming'), findsOneWidget);
        expect(find.text('Event Storming Facilitator'), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Row(
                  children: [
                    SizedBox(
                      width: 460,
                      child: StageAiChatPane(controller: controller),
                    ),
                    Expanded(
                      child: EventStormingEditorView(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Amorçage 1-clic depuis le Cahier des charges
        await tester.tap(find.byKey(const ValueKey('spec-es-seed-btn')));
        await tester.pumpAndSettle();
        expect(controller.project!.eventStorming.flows, hasLength(1));

        // 2. Génération 1-clic des Objets métiers depuis l'Event Storming
        await tester.tap(
          find.byKey(const ValueKey('spec-es-generate-objects-btn')),
        );
        await tester.pumpAndSettle();
        expect(controller.project!.businessObjects, isNotEmpty);

        // 3. Appel IA Event Storming Facilitator (ajoute ES-099 avec politique)
        await tester.tap(find.byKey(const ValueKey('spec-stage-start-ai')));
        await tester.pumpAndSettle();
        expect(fakeAi.calledStages, [SpecForgeStage.eventStorming]);
        expect(
          controller.project!.eventStorming.flows.any(
            (f) => f.id == 'es_ai_cmd',
          ),
          isTrue,
        );

        // 4. Sélection du flux ES-099 et promotion de la politique en RG-001
        await tester.tap(
          find.byKey(const ValueKey('spec-es-flow-tile-es_ai_cmd')),
        );
        await tester.pumpAndSettle();
        final promoteBtn = find.byKey(
          const ValueKey('spec-es-promote-policy-n_pol'),
        );
        await tester.ensureVisible(promoteBtn);
        await tester.pumpAndSettle();
        await tester.tap(promoteBtn);
        await tester.pumpAndSettle();
        expect(controller.project!.businessRules, hasLength(1));
        expect(controller.project!.businessRules.single.code, 'RG-001');
      },
    );
  });
}
