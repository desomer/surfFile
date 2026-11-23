import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemProjectStore extends SpecProjectStore {
  _MemProjectStore() : super(Directory('memory_em_store'));

  final Map<String, SpecForgeProject> _projects = {};
  String? _lastActive;

  void seed(SpecForgeProject p) {
    _projects[p.id] = p;
    _lastActive = p.id;
  }

  @override
  Future<void> saveProject(SpecForgeProject project) async {
    project.validate();
    _projects[project.id] = project;
    _lastActive = project.id;
  }

  @override
  Future<SpecForgeProject?> loadProject(String projectId) async =>
      _projects[projectId];

  @override
  Future<void> deleteProject(String projectId) async {
    _projects.remove(projectId);
    if (_lastActive == projectId) _lastActive = null;
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
        exampleMapCount: p.exampleMappings.length,
      ),
  ];

  @override
  Future<String?> getLastActiveProjectId() async => _lastActive;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {
    _lastActive = projectId;
  }
}

class _MemGlossaryStore extends CompanyGlossaryStore {
  _MemGlossaryStore() : super(Directory('memory_em_store'));

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
  _MemDictStore() : super(Directory('memory_em_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemDomainStore extends DomainCatalogStore {
  _MemDomainStore() : super(Directory('memory_em_store'));

  @override
  Future<DomainCatalog> load() async => DomainCatalog.empty;

  @override
  Future<void> save(DomainCatalog catalog) async {}
}

class _FakeExampleMapperAi implements SpecAiService {
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
        '{"message":"J’ai affiné CommandeClient grâce à 2 exemples concrets.","askUser":null,"specPatch":{"exampleMappings":[{"id":"em_ai_cmd","code":"EM-001","title":"Validation commande","targetObjectId":"obj_cmd","rules":[{"id":"emr_ai_1","title":"Seuil remise 500 EUR","category":"calculation","targetObjectIds":["obj_cmd"],"targetAttributes":["CommandeClient.montantHt","CommandeClient.tauxRemise"],"examples":[{"id":"ex_ai_1","title":"Commande 500 EUR -> 10%","kind":"boundary","given":"Commande brouillon de 500 EUR","when":"Validation","then":"tauxRemise vaut 10","inputValues":{"montantHt":500},"expectedOutcome":{"tauxRemise":10},"discoveredAttributes":["tauxRemise"]}]}],"questions":[]}],"businessObjects":[{"id":"obj_cmd","name":"Commande client","technicalName":"CommandeClient","attributes":[{"id":"attr_ht","name":"montantHt","type":"number","required":true,"schemaConstraints":{"minimum":0,"examples":[120,500]}},{"id":"attr_remise","name":"tauxRemise","type":"number","required":false,"schemaConstraints":{"minimum":0,"maximum":100,"examples":[0,10]}}]}]},"stageSummary":"1 tableau EM-001 et tauxRemise ajouté","stageReadyToAdvance":true}';
    yield const GeminiStreamEvent(
      deltaText: json,
      accumulatedText: json,
      isDone: true,
      usedContextCache: false,
    );
  }
}

SpecForgeProject _buildSampleProject({
  List<ExampleMapStory> exampleMappings = const <ExampleMapStory>[],
  SpecForgeStage currentStage = SpecForgeStage.exampleMapping,
}) {
  final now = DateTime.utc(2026, 11, 23, 18);
  return SpecForgeProject(
    id: 'proj_em_test',
    name: 'Commandes B2B',
    initialIdea: 'Gestion des commandes clients B2B avec remises et statuts',
    createdAt: now,
    updatedAt: now,
    currentStage: currentStage,
    cahierDesCharges: SpecCahierDesCharges(
      functionalRequirements: [
        FunctionalRequirement(
          id: 'req_1',
          code: 'EXF-001',
          title: 'Calcul des remises sur CommandeClient',
        ),
      ],
      useCases: [
        UseCaseSpec(
          id: 'uc_valider',
          title: 'Valider une CommandeClient',
          preconditions: const ['La commande est en brouillon'],
          mainFlow: const ['Le gestionnaire valide la commande'],
          postconditions: const ['Le statut passe à validee'],
        ),
      ],
    ),
    businessObjects: [
      BusinessObjectSpec(
        id: 'obj_cmd',
        name: 'Commande client',
        technicalName: 'CommandeClient',
        description: 'Commande B2B',
        attributes: [
          BusinessAttribute(
            id: 'attr_ht',
            name: 'montantHt',
            type: BusinessAttributeType.number,
            required: true,
            schemaConstraints: JsonSchemaConstraints(minimum: 0),
          ),
          BusinessAttribute(
            id: 'attr_statut',
            name: 'statut',
            type: BusinessAttributeType.enumeration,
            required: true,
            enumValues: const ['brouillon', 'validee', 'annulee'],
          ),
        ],
        lifecycleStates: const [
          LifecycleState(
            name: 'brouillon',
            label: 'Brouillon',
            isInitial: true,
          ),
          LifecycleState(name: 'validee', label: 'Validée'),
          LifecycleState(name: 'annulee', label: 'Annulée', isTerminal: true),
        ],
        lifecycleTransitions: const [
          LifecycleTransition(
            id: 'tr_1',
            fromState: 'brouillon',
            toState: 'validee',
            trigger: 'Valider la commande',
            guardSummary: 'montantHt > 0',
          ),
        ],
      ),
    ],
    exampleMappings: exampleMappings,
  );
}

void main() {
  group('Modèles, Patch & Persistance Example Mapping', () {
    test('SpecForgeStage compte 7 étapes avec exampleMapping en étape 5', () {
      expect(SpecForgeStage.values.length, 7);
      expect(SpecForgeStage.exampleMapping.stepNumber, 5);
      expect(
        SpecForgeStage.businessObjects.next,
        SpecForgeStage.exampleMapping,
      );
      expect(SpecForgeStage.exampleMapping.next, SpecForgeStage.businessRules);
      expect(SpecForgeStage.businessRules.stepNumber, 6);
      expect(SpecForgeStage.reviewExport.stepNumber, 7);
      expect(
        SpecForgeStage.fromJson('example_mapping'),
        SpecForgeStage.exampleMapping,
      );
    });

    test('ExampleMapStory round-trip JSON, égalité et SpecPatchApplier', () {
      final base = _buildSampleProject();
      final applied = SpecPatchApplier.apply(base, {
        'exampleMappings': [
          {
            'id': 'em_1',
            'code': 'EM-001',
            'title': 'Remise sur commande',
            'targetObjectId': 'obj_cmd',
            'useCaseId': 'uc_valider',
            'requirementIds': ['EXF-001'],
            'rules': [
              {
                'id': 'emr_1',
                'title': 'Remise 10 % dès 500 EUR',
                'category': 'calculation',
                'targetObjectIds': ['obj_cmd'],
                'targetAttributes': ['CommandeClient.montantHt'],
                'examples': [
                  {
                    'id': 'ex_1',
                    'title': 'Au seuil 500 EUR',
                    'kind': 'boundary',
                    'given': 'Commande 500 EUR',
                    'when': 'Validation',
                    'then': 'Remise 10%',
                    'inputValues': {'montantHt': 500},
                    'expectedOutcome': {'remise': 50},
                    'discoveredAttributes': ['remise'],
                  },
                ],
              },
            ],
            'questions': [
              {
                'id': 'emq_1',
                'question': 'Cumulable avec code promo ?',
                'impact': 'Ajoute champ cumulable',
                'resolved': false,
              },
            ],
          },
        ],
      });

      expect(applied.project.exampleMappings, hasLength(1));
      final roundTrip = SpecForgeProject.fromJson(applied.project.toJson());
      expect(roundTrip.exampleMappings, applied.project.exampleMappings);
      expect(roundTrip, applied.project);

      final removed = SpecPatchApplier.apply(applied.project, {
        'removeExampleMapIds': ['em_1'],
      });
      expect(removed.project.exampleMappings, isEmpty);
    });

    test('SpecPatchApplier.applyPartial isole une story invalide et garde les valides', () {
      final base = _buildSampleProject();
      final partial = SpecPatchApplier.applyPartial(base, {
        'exampleMappings': [
          {
            'id': 'em_valid',
            'code': 'EM-001',
            'title': 'Story valide',
            'targetObjectId': 'obj_cmd',
          },
          'invalide',
        ],
      });
      expect(partial.project.exampleMappings, hasLength(1));
      expect(partial.rejectedEntries, hasLength(1));
    });

    test('SpecProjectStore persiste dans spec/example_maps/ et recharge les anciens projets sans erreur', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_em_store_');
      try {
        final store = SpecProjectStore(tempDir);
        final sep = Platform.pathSeparator;
        final story = ExampleMapStory(
          id: 'em_1',
          code: 'EM-001',
          title: 'Validation Commande',
          targetObjectId: 'obj_cmd',
          rules: [
            ExampleMapRule(
              id: 'emr_1',
              title: 'Montant positif',
              examples: [
                ExampleMapExample(
                  id: 'ex_1',
                  title: 'Nominal 100 EUR',
                  inputValues: const {'montantHt': 100},
                ),
              ],
            ),
          ],
        );
        final project = _buildSampleProject(exampleMappings: [story]);
        await store.saveProject(project);

        final emDir = Directory(
          '${tempDir.path}${sep}projects${sep}commandes-b2b${sep}spec${sep}example_maps',
        );
        expect(await emDir.exists(), isTrue);
        expect(await File('${emDir.path}${sep}_order.json').exists(), isTrue);

        final reloaded = await store.loadProject(project.id);
        expect(reloaded, isNotNull);
        expect(reloaded!.exampleMappings, [story]);

        final summaries = await store.listProjects();
        expect(summaries.single.exampleMapCount, 1);

        // Simule un projet v3 antérieur sans dossier example_maps/
        await emDir.delete(recursive: true);
        final legacyReloaded = await SpecProjectStore(tempDir)
            .loadProject(project.id);
        expect(legacyReloaded, isNotNull);
        expect(legacyReloaded!.exampleMappings, isEmpty);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });

  group('Opérations, Cohérence, Exports & Passerelle QA', () {
    test('ExampleMappingOperations initialise, promeut une règle bleue et injecte des exemples', () {
      final base = _buildSampleProject();
      final seeded = ExampleMappingOperations.seedStoriesFromObjectsAndUseCases(
        base,
      );
      expect(seeded, hasLength(1));
      expect(seeded.first.code, 'EM-001');
      expect(seeded.first.targetObjectId, 'obj_cmd');
      expect(seeded.first.useCaseId, 'uc_valider');
      expect(seeded.first.rules, isNotEmpty);

      final withStory = base.copyWith(
        exampleMappings: [
          seeded.first.copyWith(
            rules: [
              ExampleMapRule(
                id: 'emr_remise',
                title: 'Remise palier 500 EUR',
                category: BusinessRuleCategory.calculation,
                targetObjectIds: const ['obj_cmd'],
                targetAttributes: const ['CommandeClient.montantHt'],
                examples: [
                  ExampleMapExample(
                    id: 'ex_500',
                    title: 'Seuil 500 EUR',
                    kind: ExampleMapExampleKind.boundary,
                    given: 'Commande 500 EUR',
                    when: 'Validation',
                    then: 'Remise 10%',
                    inputValues: const {'montantHt': 500, 'statut': 'validee'},
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final promoted = ExampleMappingOperations.promoteRuleToBusinessRule(
        withStory,
        storyId: seeded.first.id,
        ruleId: 'emr_remise',
      );
      expect(promoted.createdNew, isTrue);
      expect(promoted.rule.code, 'RG-001');
      expect(
        promoted.project.exampleMappings.single.rules.single.linkedRuleId,
        promoted.rule.id,
      );

      final enriched = ExampleMappingOperations.enrichObjectExamplesFromStory(
        promoted.project,
        storyId: seeded.first.id,
      );
      expect(enriched.injectedValuesCount, 2);
      final cmdObj = enriched.project.findBusinessObject('obj_cmd')!;
      final montantAttr = cmdObj.attributes.firstWhere(
        (a) => a.name == 'montantHt',
      );
      expect(montantAttr.schemaConstraints.examples, contains(500));

      // Prévisualisation & injection sélective (modes append et replace + clés non rattachées)
      final previewBase = promoted.project.copyWith(
        businessObjects: [
          cmdObj.copyWith(
            attributes: [
              for (final attr in cmdObj.attributes)
                if (attr.name == 'montantHt')
                  attr.copyWith(
                    schemaConstraints: attr.schemaConstraints.copyWith(
                      examples: const [120],
                    ),
                  )
                else
                  attr,
            ],
          ),
        ],
        exampleMappings: [
          promoted.project.exampleMappings.single.copyWith(
            rules: [
              ...promoted.project.exampleMappings.single.rules,
              ExampleMapRule(
                id: 'emr_extra',
                title: 'Remise',
                examples: [
                  ExampleMapExample(
                    id: 'ex_extra',
                    title: 'Seuil 1000',
                    inputValues: const {'montantHt': 120},
                    expectedOutcome: const {'tauxRemise': 15},
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final preview = ExampleMappingOperations.buildExampleInjectionPreview(
        previewBase,
        storyId: seeded.first.id,
      );
      final montantComp = preview.attributeComparisons.firstWhere(
        (c) => c.attributePath == 'montantHt',
      );
      expect(montantComp.existingExamples, const [120]);
      expect(
        montantComp.candidates
            .firstWhere((c) => c.value == 120)
            .alreadyPresent,
        isTrue,
      );
      expect(
        montantComp.candidates
            .firstWhere((c) => c.value == 500)
            .alreadyPresent,
        isFalse,
      );
      expect(preview.unmatchedCandidates.keys, contains('tauxRemise'));

      final appended = ExampleMappingOperations.applyExampleInjectionSelection(
        previewBase,
        storyId: seeded.first.id,
        selectedByAttributePath: const {
          'montantHt': [500],
        },
        mode: ExampleInjectionMode.append,
      );
      expect(
        appended.project
            .findBusinessObject('obj_cmd')!
            .attributes
            .firstWhere((a) => a.name == 'montantHt')
            .schemaConstraints
            .examples,
        const [120, 500],
      );

      final replaced = ExampleMappingOperations.applyExampleInjectionSelection(
        appended.project,
        storyId: seeded.first.id,
        selectedByAttributePath: const {
          'montantHt': [500],
        },
        mode: ExampleInjectionMode.replace,
      );
      expect(
        replaced.project
            .findBusinessObject('obj_cmd')!
            .attributes
            .firstWhere((a) => a.name == 'montantHt')
            .schemaConstraints
            .examples,
        const [500],
      );
    });

    test('SpecCoherenceAnalyzer, SpecMarkdownExporter et QaAutoSeeder exploitent exampleMappings', () async {
      final story = ExampleMapStory(
        id: 'em_cmd',
        code: 'EM-001',
        title: 'Remises et statuts CommandeClient',
        targetObjectId: 'obj_cmd',
        rules: [
          ExampleMapRule(
            id: 'emr_1',
            title: 'Seuil remise',
            category: BusinessRuleCategory.calculation,
            targetObjectIds: const ['obj_cmd'],
            examples: [
              ExampleMapExample(
                id: 'ex_1',
                title: 'Sous seuil 100 EUR',
                kind: ExampleMapExampleKind.boundary,
                given: 'Commande 100 EUR',
                when: 'Calcul',
                then: 'Remise 0%',
                inputValues: const {'montantHt': 100},
                expectedOutcome: const {'tauxRemise': 0},
              ),
              ExampleMapExample(
                id: 'ex_2',
                title: 'Au seuil 500 EUR',
                kind: ExampleMapExampleKind.boundary,
                given: 'Commande 500 EUR',
                when: 'Calcul',
                then: 'Remise 10%',
                inputValues: const {'montantHt': 500},
                expectedOutcome: const {'tauxRemise': 10},
              ),
            ],
          ),
          ExampleMapRule(id: 'emr_empty', title: 'Règle sans exemple'),
        ],
        questions: const [
          ExampleMapQuestion(
            id: 'emq_1',
            question: 'Quel plafond de remise ?',
            resolved: false,
          ),
        ],
      );

      final project = _buildSampleProject(exampleMappings: [story]);

      // Cohérence : détecte COH-EM-001 (question ouverte) et COH-EM-003 (règle sans exemple)
      final issues = SpecCoherenceAnalyzer.analyze(project);
      expect(issues.any((i) => i.code == 'COH-EM-001'), isTrue);
      expect(issues.any((i) => i.code == 'COH-EM-003'), isTrue);

      // Export Markdown : section 5 Example Mapping
      final md = SpecMarkdownExporter.export(project);
      expect(
        md,
        contains(
          '## 5. Example Mapping (Stories, Règles, Exemples & Questions)',
        ),
      );
      expect(md, contains('EM-001'));
      expect(md, contains('Seuil remise'));
      expect(md, contains('Quel plafond de remise ?'));

      // Passerelle QA : fixtures + Scenario Outline Gherkin depuis cartes vertes
      final fixtures = QaAutoSeeder.seedFixturesFromSchema(project);
      expect(fixtures.any((f) => f.payload['montantHt'] == 500), isTrue);
      final features = QaAutoSeeder.seedFeaturesFromSpecAndUx(project);
      final emFeature = features.firstWhere((f) => f.id == 'feat_em_em_001');
      expect(emFeature.scenarios.single.isOutline, isTrue);
      expect(emFeature.scenarios.single.examples.rows, hasLength(2));

      // Outil IA get_example_mapping & focus_stage_or_object
      String? focusedStoryId;
      SpecForgeStage? navigated;
      final registry = SpecForgeToolRegistry.build(
        readProject: () => project,
        onNavigateStage: (s) async => navigated = s,
        onFocusExampleStory: (id) => focusedStoryId = id,
      );
      final toolRes = await registry.execute(
        VibeToolCall(
          id: 't1',
          name: 'get_example_mapping',
          arguments: const {'onlyOpenQuestions': true},
        ),
      );
      expect(toolRes.isError, isFalse);
      expect(toolRes.data['storyCount'], 1);
      expect(toolRes.data['openQuestionCount'], 1);

      final focusRes = await registry.execute(
        VibeToolCall(
          id: 't2',
          name: 'focus_stage_or_object',
          arguments: const {
            'stage': 'exampleMapping',
            'exampleStoryId': 'EM-001',
          },
        ),
      );
      expect(focusRes.isError, isFalse);
      expect(navigated, SpecForgeStage.exampleMapping);
      expect(focusedStoryId, 'em_cmd');
    });
  });

  group('Atelier UI & Stepper Example Mapping', () {
    testWidgets(
      'Stepper 7 étapes, ExampleMappingEditorView 1-clic et affinage IA fonctionnent sans erreur',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final store = _MemProjectStore()..seed(_buildSampleProject());
        final fakeAi = _FakeExampleMapperAi();
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
        expect(find.text('Example Map'), findsOneWidget);
        expect(find.text('Example Mapper'), findsOneWidget);

        // Rendu complet de ExampleMappingEditorView + StageAiChatPane
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
                      child: ExampleMappingEditorView(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initialisation 1-clic depuis Objets & UC
        await tester.tap(find.byKey(const ValueKey('spec-em-seed-btn')));
        await tester.pumpAndSettle();
        expect(controller.project!.exampleMappings, hasLength(1));
        final seededStoryId = controller.project!.exampleMappings.single.id;
        expect(
          find.descendant(
            of: find.byKey(ValueKey('spec-em-story-chip-$seededStoryId')),
            matching: find.text('EM-001'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ValueKey('spec-em-yellow-card-$seededStoryId')),
            matching: find.text('EM-001'),
          ),
          findsOneWidget,
        );

        // 2. Promotion d'une règle bleue vers RG-001
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        final firstRuleId =
            controller.project!.exampleMappings.single.rules.first.id;
        final promoteBtn = find.byKey(
          ValueKey('spec-em-promote-rule-$firstRuleId'),
        );
        await tester.ensureVisible(promoteBtn);
        await tester.pumpAndSettle();
        await tester.tap(promoteBtn);
        await tester.pumpAndSettle();
        expect(controller.project!.businessRules, hasLength(1));
        expect(controller.project!.businessRules.single.code, 'RG-001');

        // 3. Appel IA Example Mapper qui ajoute EM-001 + affine CommandeClient (tauxRemise)
        await tester.tap(find.byKey(const ValueKey('spec-stage-start-ai')));
        await tester.pumpAndSettle();

        expect(fakeAi.calledStages, [SpecForgeStage.exampleMapping]);
        final cmd = controller.project!.findBusinessObject('obj_cmd')!;
        expect(cmd.attributes.any((a) => a.name == 'tauxRemise'), isTrue);
        expect(
          controller.project!.exampleMappings.any((s) => s.id == 'em_ai_cmd'),
          isTrue,
        );

        // 4. Sélection d'une story depuis la liste latérale gauche
        await tester.tap(
          find.byKey(const ValueKey('spec-em-story-chip-em_ai_cmd')),
        );
        await tester.pumpAndSettle();
        expect(controller.focusedExampleStoryId, 'em_ai_cmd');
        expect(
          find.byKey(const ValueKey('spec-em-yellow-card-em_ai_cmd')),
          findsOneWidget,
        );

        // 5. Ouverture de la popup de comparaison/choix sur "Injecter exemples"
        final enrichBtn = find.byKey(
          const ValueKey('spec-em-enrich-object-btn'),
        );
        await tester.ensureVisible(enrichBtn);
        await tester.pumpAndSettle();
        await tester.tap(enrichBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('spec-em-inject-dialog')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('spec-em-inject-attr-montantHt')),
          findsOneWidget,
        );

        // En mode Remplacer, sélection de 500 sur montantHt et validation
        await tester.tap(find.text('Remplacer'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('spec-em-inject-select-all-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('spec-em-inject-confirm-btn')));
        await tester.pumpAndSettle();

        final updatedMontant = controller.project!
            .findBusinessObject('obj_cmd')!
            .attributes
            .firstWhere((a) => a.name == 'montantHt');
        expect(updatedMontant.schemaConstraints.examples, const [500]);
      },
    );
  });
}
