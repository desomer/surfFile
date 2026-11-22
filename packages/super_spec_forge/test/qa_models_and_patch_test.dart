import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemoryModelDictionaryStore extends ModelDictionaryStore {
  _MemoryModelDictionaryStore() : super(Directory('memory_store'));

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
  _MemoryCompanyGlossaryStore() : super(Directory('memory_store'));

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
  _MemoryDomainCatalogStore() : super(Directory('memory_store'));

  DomainCatalog _catalog = DomainCatalog.empty;

  @override
  Future<DomainCatalog> load() async => _catalog;

  @override
  Future<void> save(DomainCatalog catalog) async {
    catalog.validate();
    _catalog = catalog;
  }
}

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_store'));

  final Map<String, SpecForgeProject> _projects = {};
  String? _lastActiveId;

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
  Future<List<SpecProjectSummary>> listProjects() async {
    final list = [
      for (final p in _projects.values)
        SpecProjectSummary(
          id: p.id,
          name: p.name,
          initialIdea: p.initialIdea,
          currentStage: p.currentStage,
          updatedAt: p.updatedAt,
          objectCount: p.businessObjects.length,
          ruleCount: p.businessRules.length,
          journeyCount: p.uxSpec.journeys.length,
          screenCount: p.uxSpec.screens.length,
          currentUxStage: p.uxSpec.currentStage,
          featureCount: p.qaSpec.features.length,
          tddCaseCount: p.qaSpec.totalTddCaseCount,
          currentQaStage: p.qaSpec.currentStage,
        ),
    ];
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<String?> getLastActiveProjectId() async => _lastActiveId;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {
    _lastActiveId = projectId;
  }
}

/// Service IA factice émettant des fragments SSE multi-chunks pour simuler un tour QA.
class FakeSpecAiService implements SpecAiService {
  FakeSpecAiService(this._scriptedChunkBatches);

  final List<List<String>> _scriptedChunkBatches;
  final List<String> receivedPrompts = <String>[];
  final List<String?> receivedSystemInstructions = <String?>[];
  int _turnIndex = 0;

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
    receivedPrompts.add(prompt);
    receivedSystemInstructions.add(systemInstructionOverride);
    final chunks = _scriptedChunkBatches[
      _turnIndex < _scriptedChunkBatches.length
          ? _turnIndex
          : _scriptedChunkBatches.length - 1
    ];
    _turnIndex++;

    final accumulated = StringBuffer();
    for (var i = 0; i < chunks.length; i++) {
      final delta = chunks[i];
      accumulated.write(delta);
      yield GeminiStreamEvent(
        deltaText: delta,
        accumulatedText: accumulated.toString(),
        isDone: i == chunks.length - 1,
        usedContextCache: false,
      );
    }
  }
}

SpecForgeProject _buildRichBusinessAndUxProject() {
  final base = SpecForgeProject.fromIdea(
    idea: 'Plateforme B2B de gestion des commandes et contrôles d’encours',
    name: 'OrderFlow QA',
    id: 'proj_orderflow_qa',
  );
  return base.copyWith(
    lexicon: SpecLexicon(
      terms: [
        LexiconTerm(
          id: 'term_cmd',
          term: 'Commande client',
          definition: 'Engagement ferme de livraison de marchandises.',
          synonyms: const ['Ordre client'],
          domain: 'Ventes',
        ),
      ],
      conventions: const ['Montants HT en EUR'],
    ),
    vision: base.vision.copyWith(
      problemStatement: 'Erreurs d’encours et régressions lors des mises en production',
      objectives: const ['Zéro commande validée au-delà du plafond'],
      personas: [
        SpecPersona(
          id: 'persona_adv',
          name: 'Gestionnaire ADV',
          role: 'Contrôle et valide les commandes B2B',
          goals: const ['Valider rapidement sous contrôle encours'],
          painPoints: const ['Calculs manuels sujets aux erreurs'],
        ),
      ],
    ),
    cahierDesCharges: SpecCahierDesCharges(
      modules: const [
        SpecModule(
          id: 'mod_ventes',
          name: 'Administration des ventes',
          description: 'Validation et cycle de vie des commandes',
        ),
      ],
      functionalRequirements: [
        FunctionalRequirement(
          id: 'req_exf_001',
          code: 'EXF-001',
          title: 'Valider une commande client sous plafond',
          moduleId: 'mod_ventes',
          priority: RequirementPriority.must,
          actorIds: const ['persona_adv'],
          acceptanceCriteria: const [
            'Vérifie le plafond d’encours client',
            'Passe le statut à validee',
          ],
        ),
        FunctionalRequirement(
          id: 'req_exf_002',
          code: 'EXF-002',
          title: 'Exporter le récapitulatif des rejets',
          moduleId: 'mod_ventes',
          priority: RequirementPriority.should,
          actorIds: const ['persona_adv'],
          acceptanceCriteria: const ['Génère un relevé horodaté'],
        ),
      ],
      useCases: [
        UseCaseSpec(
          id: 'uc_valider_cmd',
          title: 'Validation commande B2B',
          actorId: 'persona_adv',
          preconditions: const ['Commande au statut brouillon'],
          mainFlow: const [
            'Ouvrir la commande en attente',
            'Contrôler l’encours et valider',
          ],
          alternativeFlows: const [
            'Encours dépassé : blocage avec motif RG-001',
          ],
          postconditions: const ['Statut passé à validee'],
        ),
      ],
      nonFunctionalRequirements: const [
        NonFunctionalRequirement(
          id: 'nfr_001',
          code: 'ENF-001',
          category: NonFunctionalCategory.performance,
          title: 'Validation unitaire < 50 ms',
          targetMetric: 'p95 < 50 ms',
        ),
      ],
    ),
    businessObjects: [
      BusinessObjectSpec(
        id: 'obj_client',
        name: 'Client',
        technicalName: 'Client',
        description: 'Compte client B2B avec plafond d’encours',
        attributes: [
          BusinessAttribute(
            id: 'attr_cli_raison',
            name: 'raisonSociale',
            type: BusinessAttributeType.string,
            required: true,
            schemaConstraints: JsonSchemaConstraints(minLength: 3),
          ),
          BusinessAttribute(
            id: 'attr_cli_plafond',
            name: 'plafondEncours',
            type: BusinessAttributeType.number,
            required: true,
            schemaConstraints: JsonSchemaConstraints(minimum: 0),
          ),
        ],
      ),
      BusinessObjectSpec(
        id: 'obj_commande',
        name: 'Commande',
        technicalName: 'Commande',
        description: 'Commande B2B soumise à validation ADV',
        attributes: [
          BusinessAttribute(
            id: 'attr_cmd_num',
            name: 'numero',
            type: BusinessAttributeType.string,
            required: true,
            unique: true,
            schemaConstraints: JsonSchemaConstraints(
              minLength: 5,
              examples: const ['CMD-2026-001'],
            ),
          ),
          BusinessAttribute(
            id: 'attr_cmd_montant',
            name: 'montantHt',
            type: BusinessAttributeType.number,
            required: true,
            schemaConstraints: JsonSchemaConstraints(
              exclusiveMinimum: 0,
              maximum: 100000,
            ),
          ),
          BusinessAttribute(
            id: 'attr_cmd_statut',
            name: 'statut',
            type: BusinessAttributeType.enumeration,
            required: true,
            enumValues: const ['brouillon', 'validee'],
          ),
          BusinessAttribute(
            id: 'attr_cmd_lignes',
            name: 'lignes',
            type: BusinessAttributeType.object,
            isArray: true,
            estimatedMaxRows: 80,
            children: [
              BusinessAttribute(
                id: 'attr_lig_sku',
                name: 'codeArticle',
                type: BusinessAttributeType.string,
                required: true,
              ),
              BusinessAttribute(
                id: 'attr_lig_qte',
                name: 'quantite',
                type: BusinessAttributeType.integer,
                required: true,
                schemaConstraints: JsonSchemaConstraints(minimum: 1),
              ),
            ],
          ),
        ],
        relations: const [
          BusinessRelation(
            id: 'rel_cmd_client',
            name: 'client',
            targetObjectId: 'obj_client',
            cardinality: BusinessRelationCardinality.oneToOne,
            description: 'Client donneur d’ordre',
            required: true,
          ),
        ],
        lifecycleStates: const [
          LifecycleState(
            name: 'brouillon',
            label: 'Brouillon',
            isInitial: true,
          ),
          LifecycleState(
            name: 'validee',
            label: 'Validée',
            isTerminal: true,
          ),
        ],
        lifecycleTransitions: const [
          LifecycleTransition(
            id: 'tr_cmd_valider',
            fromState: 'brouillon',
            toState: 'validee',
            trigger: 'Validation ADV',
            guardSummary: 'Encours autorisé',
          ),
        ],
      ),
    ],
    businessRules: [
      BusinessRuleSpec(
        id: 'rule_rg_001',
        code: 'RG-001',
        title: 'Plafond encours client',
        category: BusinessRuleCategory.validation,
        priority: BusinessRulePriority.critical,
        targetObjectIds: const ['obj_commande', 'obj_client'],
        targetAttributes: const ['Commande.montantHt', 'Client.plafondEncours'],
        trigger: 'Validation d’une commande brouillon',
        condition: 'encoursActuel + montantHt <= plafondEncours',
        effect: 'Autoriser le passage au statut validee',
        errorMessage: 'Plafond d’encours client dépassé (RG-001).',
      ),
      BusinessRuleSpec(
        id: 'rule_rg_002',
        code: 'RG-002',
        title: 'Quantité de ligne strictement positive',
        category: BusinessRuleCategory.calculation,
        targetObjectIds: const ['obj_commande'],
        targetAttributes: const ['Commande.lignes.quantite'],
        condition: 'quantite >= 1',
        effect: 'Calculer le total HT de la ligne',
        errorMessage: 'La quantité commandée doit être au moins égale à 1.',
      ),
    ],
    uxSpec: UxForgeSpec(
      currentStage: UxForgeStage.screenBlueprints,
      journeys: [
        UxJourneySpec(
          id: 'jrn_valider',
          code: 'JRN-001',
          name: 'Validation commande ADV',
          personaId: 'persona_adv',
          useCaseIds: const ['uc_valider_cmd'],
          requirementIds: const ['EXF-001'],
          trigger: 'Nouvelle commande reçue',
          goal: 'Valider la commande conforme',
          steps: const [
            UxJourneyStep(
              id: 'jst_1',
              order: 1,
              title: 'Contrôle commande',
              actorAction: 'Sélectionne la commande et clique sur Valider',
              systemResponse: 'Passe la commande au statut Validée',
              targetRouteId: 'route_commandes',
            ),
          ],
        ),
      ],
      navigation: UxNavigationSpec(
        homeRouteId: 'route_commandes',
        routes: [
          UxRouteNode(
            id: 'route_commandes',
            path: '/commandes',
            title: 'Commandes',
            moduleId: 'mod_ventes',
          ),
          UxRouteNode(
            id: 'route_audit',
            path: '/audit-rejets',
            title: 'Audit des rejets',
            moduleId: 'mod_ventes',
          ),
        ],
      ),
      screens: [
        UxScreenSpec(
          id: 'scr_commandes',
          code: 'SCR-001',
          name: 'Poste Commandes ADV',
          routeId: 'route_commandes',
          pattern: UxScreenPattern.masterDetail,
          primaryObjectId: 'obj_commande',
          actions: [
            UxScreenAction(
              id: 'act_valider',
              label: 'Valider',
              hierarchy: UxActionHierarchy.primary,
              businessRuleIds: const ['RG-001'],
            ),
          ],
        ),
        UxScreenSpec(
          id: 'scr_audit',
          code: 'SCR-002',
          name: 'Journal des rejets encours',
          routeId: 'route_audit',
          pattern: UxScreenPattern.tableExplorer,
        ),
      ],
    ),
  );
}

void main() {
  group('Modèles QA, normalisation, validation, mots-clés FR/EN et rétrocompatibilité', () {
    test('round-trip JSON complet de QaForgeSpec et de tous les sous-modèles QA', () {
      final fixtureNominal = QaFixtureSpec(
        id: 'fix_cmd_ok',
        code: 'FIX-001',
        name: 'Commande nominale sous plafond',
        kind: QaFixtureKind.nominal,
        businessObjectId: 'obj_commande',
        personaId: 'persona_adv',
        businessRuleIds: const ['RG-001', 'RG-002'],
        description: 'Commande valide avec 2 lignes et encours respecté.',
        payload: <String, Object?>{
          'numero': 'CMD-2026-001',
          'montantHt': 4200.50,
          'statut': 'brouillon',
          'horodatage': DateTime.utc(2026, 11, 22, 9, 15),
          'lignes': <Map<String, Object?>>[
            {'codeArticle': 'SKU-100', 'quantite': 4},
          ],
        },
        expectedValid: true,
      );

      final fixtureInvalid = QaFixtureSpec(
        id: 'fix_cmd_ko_encours',
        code: 'FIX-002',
        name: 'Commande dépassant le plafond client',
        kind: QaFixtureKind.invalid,
        businessObjectId: 'obj_commande',
        personaId: 'persona_adv',
        businessRuleIds: const ['RG-001'],
        description: 'Montant HT supérieur au plafond autorisé.',
        payload: const <String, Object?>{
          'numero': 'CMD-2026-002',
          'montantHt': 25000,
          'statut': 'brouillon',
        },
        expectedValid: false,
        expectedErrorHint: 'Plafond d’encours client dépassé (RG-001).',
      );

      // Vérifie l'immuabilité profonde du payload de fixture
      expect(
        () => fixtureNominal.payload['numero'] = 'MUTATION',
        throwsUnsupportedError,
      );
      expect(
        () => (fixtureNominal.payload['lignes'] as List).add('x'),
        throwsUnsupportedError,
      );
      expect(
        fixtureNominal.payload['horodatage'],
        '2026-11-22T09:15:00.000Z',
      );

      final scenarioNominal = GherkinScenarioSpec(
        id: 'scn_valider_ok',
        code: 'SCN-001',
        title: 'Validation nominale d’une commande sous plafond',
        tags: const ['smoke', '@@rg 001', '@smoke'],
        steps: [
          GherkinStep(
            id: 'st_1',
            keyword: GherkinStepKeyword.given,
            text: 'une commande brouillon conforme issue de FIX-001',
            dataTable: const [
              ['numero', 'montantHt'],
              ['CMD-2026-001', '4200.50'],
            ],
          ),
          GherkinStep(
            id: 'st_2',
            keyword: GherkinStepKeyword.when,
            text: 'le gestionnaire ADV valide la commande sur SCR-001',
          ),
          GherkinStep(
            id: 'st_3',
            keyword: GherkinStepKeyword.then,
            text: 'la commande passe au statut "validee"',
            docString: '{"statut":"validee"}',
          ),
        ],
        requirementIds: const ['EXF-001'],
        useCaseIds: const ['uc_valider_cmd'],
        businessRuleIds: const ['RG-001'],
        journeyIds: const ['JRN-001'],
        screenIds: const ['SCR-001'],
        fixtureIds: const ['FIX-001'],
      );

      final scenarioOutline = GherkinScenarioSpec(
        id: 'scn_outline_encours',
        code: 'SCN-002',
        title: 'Contrôle paramétré du plafond d’encours',
        isOutline: true,
        tags: const ['@outline', '@rg-001'],
        steps: [
          GherkinStep(
            id: 'ost_1',
            keyword: GherkinStepKeyword.given,
            text: 'un client avec plafond <plafond_eur> EUR',
          ),
          GherkinStep(
            id: 'ost_2',
            keyword: GherkinStepKeyword.when,
            text: 'il soumet une commande de lignes :',
            dataTable: const [
              ['article', 'montant'],
              ['<code_sku>', '<montant_cmd>'],
            ],
          ),
          GherkinStep(
            id: 'ost_3',
            keyword: GherkinStepKeyword.then,
            text: 'la décision retournée est "<decision>"',
            docString: '{"motif": "<motif_attendu>"}',
          ),
        ],
        examples: GherkinExamplesTable(
          headers: const [
            'plafond_eur',
            'code_sku',
            'montant_cmd',
            'decision',
            'motif_attendu',
          ],
          rows: const [
            ['10000', 'SKU-1', '4200', 'validee', 'OK'],
            ['10000', 'SKU-2', '15000', 'rejetee', 'RG-001'],
          ],
        ),
        businessRuleIds: const ['RG-001'],
        fixtureIds: const ['FIX-001', 'FIX-002'],
      );

      expect(scenarioNominal.tags, ['@smoke', '@rg-001']);
      expect(
        scenarioOutline.referencedOutlineVariables,
        equals(<String>{
          'plafond_eur',
          'code_sku',
          'montant_cmd',
          'decision',
          'motif_attendu',
        }),
      );
      expect(scenarioOutline.examples.isNotEmpty, isTrue);
      expect(GherkinExamplesTable.empty.isEmpty, isTrue);

      final feature = GherkinFeatureSpec(
        id: 'feat_validation_cmd',
        code: 'FEAT-001',
        title: 'Validation des commandes clients B2B',
        moduleId: 'mod_ventes',
        personaId: 'persona_adv',
        narrative:
            'En tant que Gestionnaire ADV\nJe veux contrôler le plafond d’encours\nAfin d’éviter tout impayé',
        tags: const ['ventes', '@b2b'],
        backgroundSteps: [
          GherkinStep(
            id: 'bg_1',
            keyword: GherkinStepKeyword.given,
            text: 'le référentiel client B2B est initialisé',
          ),
        ],
        scenarios: [scenarioNominal, scenarioOutline],
      );

      final tddSuite = TddTestSuiteSpec(
        id: 'tdd_encours_suite',
        code: 'TDD-001',
        name: 'Validation plafond encours & calcul lignes',
        layer: TddTargetLayer.domainValidation,
        targetObjectId: 'obj_commande',
        moduleId: 'mod_ventes',
        description: 'Progression Red -> Green -> Refactor sur RG-001 et RG-002.',
        cases: [
          TddTestCaseSpec(
            id: 'tc_1',
            code: 'TC-001',
            order: 1,
            title: 'Autorise la validation lorsque encours + montant <= plafond',
            fixtureId: 'FIX-001',
            arrange: 'Charger FIX-001 avec plafond client = 10 000 EUR',
            act: 'commandeValidator.validate(commande, client)',
            outcomeKind: TddExpectedOutcomeKind.mutatesState,
            assertExpected: 'statut == "validee" sans erreur',
            businessRuleIds: const ['RG-001'],
            requirementIds: const ['EXF-001'],
            screenIds: const ['SCR-001'],
          ),
          TddTestCaseSpec(
            id: 'tc_2',
            code: 'TC-002',
            order: 2,
            title: 'Rejette la validation lorsque encours + montant > plafond',
            fixtureId: 'FIX-002',
            arrange: 'Charger FIX-002 avec montantHt = 25 000 EUR > plafond 10 000 EUR',
            act: 'commandeValidator.validate(commande, client)',
            outcomeKind: TddExpectedOutcomeKind.rejectsWithError,
            assertExpected: 'statut reste "brouillon"',
            expectedErrorMessage: 'Plafond d’encours client dépassé (RG-001).',
            businessRuleIds: const ['RG-001'],
            requirementIds: const ['EXF-001'],
          ),
        ],
      );

      const coherenceIssue = QaCoherenceIssue(
        id: 'qa_coh_1',
        severity: CoherenceSeverity.warning,
        stage: QaForgeStage.qaReviewExport,
        code: 'COH-QA-COV-001',
        title: 'Exigence EXF-002 non couverte',
        description: 'Aucun scénario ne couvre l’export des rejets.',
        targetRef: 'EXF-002',
        suggestion: 'Ajouter un scénario Gherkin dédié à EXF-002.',
        source: 'local',
      );

      final qaSpec = QaForgeSpec(
        currentStage: QaForgeStage.tddSuites,
        gherkinLanguage: GherkinKeywordLanguage.en,
        fixtures: [fixtureNominal, fixtureInvalid],
        features: [feature],
        tddSuites: [tddSuite],
        stageStates: {
          QaForgeStage.testFixtures: QaStageState(
            stage: QaForgeStage.testFixtures,
            status: SpecStageStatus.validated,
            stageSummary: '2 fixtures validées.',
            readyToAdvance: true,
            messages: [
              SpecChatMessage(
                id: 'qa_m1',
                isUser: true,
                text: 'Prépare les fixtures d’encours.',
              ),
            ],
          ),
        },
        coherenceIssues: const [coherenceIssue],
      );

      qaSpec.validate();
      expect(qaSpec.hasContent, isTrue);
      expect(qaSpec.totalScenarioCount, 2);
      expect(qaSpec.totalTddCaseCount, 2);

      final roundTripped = QaForgeSpec.fromJson(qaSpec.toJson());
      expect(roundTripped, equals(qaSpec));
      expect(roundTripped.findFixture('FIX-001'), equals(fixtureNominal));
      expect(
        roundTripped.findFixture('Commande dépassant le plafond client'),
        equals(fixtureInvalid),
      );
      expect(roundTripped.findFeature('FEAT-001'), equals(feature));
      expect(
        roundTripped.findFeature('Validation des commandes clients B2B'),
        equals(feature),
      );
      expect(roundTripped.findTddSuite('TDD-001'), equals(tddSuite));
      expect(
        roundTripped.findTddSuite('Validation plafond encours & calcul lignes'),
        equals(tddSuite),
      );

      final moved = roundTripped.moveToStage(
        QaForgeStage.qaReviewExport,
        validateCurrentStage: true,
      );
      expect(moved.currentStage, QaForgeStage.qaReviewExport);
      expect(
        moved.stageStateFor(QaForgeStage.tddSuites).status,
        SpecStageStatus.validated,
      );
      expect(
        moved.stageStateFor(QaForgeStage.qaReviewExport).status,
        SpecStageStatus.inProgress,
      );
      expect(
        moved
            .toCompactContextJson(QaForgeStage.qaReviewExport)
            .containsKey('coherenceIssues'),
        isTrue,
      );
    });

    test('correspondance des mots-clés Gherkin FR/EN et désérialisation tolérante', () {
      const fr = GherkinKeywordLanguage.fr;
      const en = GherkinKeywordLanguage.en;

      expect(fr.gherkinHeader, '# language: fr');
      expect(fr.featureKeyword, 'Fonctionnalité');
      expect(fr.backgroundKeyword, 'Contexte');
      expect(fr.scenarioKeyword, 'Scénario');
      expect(fr.scenarioOutlineKeyword, 'Plan du Scénario');
      expect(fr.examplesKeyword, 'Exemples');
      expect(GherkinStepKeyword.given.keywordFor(fr), 'Étant donné');
      expect(GherkinStepKeyword.when.keywordFor(fr), 'Quand');
      expect(GherkinStepKeyword.then.keywordFor(fr), 'Alors');
      expect(GherkinStepKeyword.and.keywordFor(fr), 'Et');
      expect(GherkinStepKeyword.but.keywordFor(fr), 'Mais');

      expect(en.gherkinHeader, '# language: en');
      expect(en.featureKeyword, 'Feature');
      expect(en.backgroundKeyword, 'Background');
      expect(en.scenarioKeyword, 'Scenario');
      expect(en.scenarioOutlineKeyword, 'Scenario Outline');
      expect(en.examplesKeyword, 'Examples');
      expect(GherkinStepKeyword.given.keywordFor(en), 'Given');
      expect(GherkinStepKeyword.when.keywordFor(en), 'When');
      expect(GherkinStepKeyword.then.keywordFor(en), 'Then');
      expect(GherkinStepKeyword.and.keywordFor(en), 'And');
      expect(GherkinStepKeyword.but.keywordFor(en), 'But');

      // Alias FR / EN sur GherkinKeywordLanguage et GherkinStepKeyword
      expect(GherkinKeywordLanguage.fromJson('en-US'), GherkinKeywordLanguage.en);
      expect(GherkinKeywordLanguage.fromJson('Anglais'), GherkinKeywordLanguage.en);
      expect(GherkinKeywordLanguage.fromJson('français'), GherkinKeywordLanguage.fr);
      expect(GherkinKeywordLanguage.fromJson(null), GherkinKeywordLanguage.fr);

      expect(
        GherkinStepKeyword.fromJson('Étant donné qu’'),
        GherkinStepKeyword.given,
      );
      expect(
        GherkinStepKeyword.fromJson('Sachant que :'),
        GherkinStepKeyword.given,
      );
      expect(GherkinStepKeyword.fromJson('Lorsque'), GherkinStepKeyword.when);
      expect(GherkinStepKeyword.fromJson('Alors :'), GherkinStepKeyword.then);
      expect(GherkinStepKeyword.fromJson('*'), GherkinStepKeyword.and);
      expect(GherkinStepKeyword.fromJson('Mais'), GherkinStepKeyword.but);
      expect(GherkinStepKeyword.fromJson('When'), GherkinStepKeyword.when);
      expect(GherkinStepKeyword.fromJson('Then'), GherkinStepKeyword.then);

      // Alias d'étapes, fixtures et couches/résultats TDD
      expect(QaForgeStage.fromJson(1), QaForgeStage.testFixtures);
      expect(QaForgeStage.fromJson('bdd'), QaForgeStage.gherkinFeatures);
      expect(QaForgeStage.fromJson('tdd'), QaForgeStage.tddSuites);
      expect(
        QaForgeStage.fromJson('qa-review-export'),
        QaForgeStage.qaReviewExport,
      );
      expect(QaForgeStage.testFixtures.previous, isNull);
      expect(QaForgeStage.testFixtures.next, QaForgeStage.gherkinFeatures);
      expect(QaForgeStage.qaReviewExport.next, isNull);

      expect(QaFixtureKind.fromJson('edge-case'), QaFixtureKind.boundary);
      expect(QaFixtureKind.fromJson('negative'), QaFixtureKind.invalid);
      expect(QaFixtureKind.fromJson('rbac'), QaFixtureKind.permission);
      expect(QaFixtureKind.fromJson('workflow'), QaFixtureKind.lifecycle);

      expect(TddTargetLayer.fromJson('formula'), TddTargetLayer.calculationFormula);
      expect(TddTargetLayer.fromJson('lifecycle'), TddTargetLayer.stateMachine);
      expect(TddTargetLayer.fromJson('rbac'), TddTargetLayer.permissionPolicy);
      expect(TddTargetLayer.fromJson('json-schema'), TddTargetLayer.schemaContract);
      expect(TddTargetLayer.fromJson('widget'), TddTargetLayer.uiBehavior);

      expect(
        TddExpectedOutcomeKind.fromJson('throws'),
        TddExpectedOutcomeKind.rejectsWithError,
      );
      expect(
        TddExpectedOutcomeKind.fromJson('forbidden'),
        TddExpectedOutcomeKind.deniesAction,
      );
      expect(
        TddExpectedOutcomeKind.fromJson('permitted'),
        TddExpectedOutcomeKind.allowsAction,
      );

      // Parsing tolérant de payload JSON string et de GherkinExamplesTable à partir de Maps
      final parsedFix = QaFixtureSpec.fromJson({
        'id': 'fix_str_json',
        'title': 'Fixture JSON encodé',
        'targetObjectId': 'obj_commande',
        'data': '{"numero":"CMD-900","actif":true}',
      });
      expect(parsedFix.name, 'Fixture JSON encodé');
      expect(parsedFix.businessObjectId, 'obj_commande');
      expect(parsedFix.payload['numero'], 'CMD-900');

      final parsedScenario = GherkinScenarioSpec.fromJson({
        'id': 'scn_map_rows',
        'title': 'Outline depuis lignes Map',
        'examples': {
          'rows': [
            {'qte': 2, 'total': 20},
            {'qte': 5, 'total': 50},
          ],
        },
      });
      expect(parsedScenario.isOutline, isTrue);
      expect(parsedScenario.examples.headers, ['qte', 'total']);
      expect(parsedScenario.examples.rows, [
        ['2', '20'],
        ['5', '50'],
      ]);
    });

    test('invariants de validation (validate) et déduplication tolérante depuis JSON', () {
      expect(
        QaFixtureSpec(id: '   ', name: 'Valide').validate,
        throwsFormatException,
      );
      expect(
        QaFixtureSpec(id: 'fix_1', name: '   ').validate,
        throwsFormatException,
      );
      expect(
        GherkinStep(id: '', text: 'action').validate,
        throwsFormatException,
      );
      expect(
        GherkinStep(id: 'st_1', text: '   ').validate,
        throwsFormatException,
      );
      expect(
        GherkinExamplesTable(
          headers: const [],
          rows: const [
            ['val1'],
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        GherkinExamplesTable(
          headers: const ['col1', '   '],
          rows: const [],
        ).validate,
        throwsFormatException,
      );
      expect(
        GherkinExamplesTable(
          headers: const ['col1', 'col2'],
          rows: const [
            ['seule_cellule'],
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        GherkinScenarioSpec(
          id: 'scn_1',
          title: 'Scénario',
          steps: [
            GherkinStep(id: 'dup', text: 'Étape 1'),
            GherkinStep(id: 'dup', text: 'Étape 2'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        GherkinFeatureSpec(
          id: 'feat_1',
          title: 'Feature',
          scenarios: [
            GherkinScenarioSpec(id: 'scn_dup', title: 'S1'),
            GherkinScenarioSpec(id: 'scn_dup', title: 'S2'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        TddTestCaseSpec(id: 'tc_1', order: 0, title: 'Ordre invalide').validate,
        throwsFormatException,
      );
      expect(
        TddTestSuiteSpec(
          id: 'tdd_1',
          name: 'Suite',
          cases: [
            TddTestCaseSpec(id: 'tc_dup', title: 'Cas 1'),
            TddTestCaseSpec(id: 'tc_dup', title: 'Cas 2'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        const QaCoherenceIssue(
          id: ' ',
          severity: CoherenceSeverity.error,
          stage: QaForgeStage.testFixtures,
          code: 'QA-1',
          title: 'Titre',
          description: 'Desc',
        ).validate,
        throwsFormatException,
      );
      expect(
        QaForgeSpec(
          fixtures: [
            QaFixtureSpec(id: 'f_dup', name: 'F1'),
            QaFixtureSpec(id: 'f_dup', name: 'F2'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        QaForgeSpec(
          features: [
            GherkinFeatureSpec(id: 'feat_dup', title: 'F1'),
            GherkinFeatureSpec(id: 'feat_dup', title: 'F2'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        QaForgeSpec(
          tddSuites: [
            TddTestSuiteSpec(id: 's_dup', name: 'S1'),
            TddTestSuiteSpec(id: 's_dup', name: 'S2'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        QaForgeSpec(
          coherenceIssues: const [
            QaCoherenceIssue(
              id: 'i_dup',
              severity: CoherenceSeverity.warning,
              stage: QaForgeStage.tddSuites,
              code: 'QA-1',
              title: 'T1',
              description: 'D1',
            ),
            QaCoherenceIssue(
              id: 'i_dup',
              severity: CoherenceSeverity.info,
              stage: QaForgeStage.qaReviewExport,
              code: 'QA-2',
              title: 'T2',
              description: 'D2',
            ),
          ],
        ).validate,
        throwsFormatException,
      );

      // Désérialisation tolérante : déduplique les IDs à chaque niveau
      final deduplicated = QaForgeSpec.fromJson({
        'fixtures': [
          {'id': 'fix_1', 'name': 'A'},
          {'id': 'fix_1', 'name': 'B'},
        ],
        'features': [
          {
            'id': 'feat_1',
            'title': 'Feature A',
            'scenarios': [
              {'id': 'scn_1', 'title': 'S1'},
              {'id': 'scn_1', 'title': 'S2'},
            ],
          },
          {'id': 'feat_1', 'title': 'Feature B'},
        ],
        'tddSuites': [
          {
            'id': 'tdd_1',
            'name': 'Suite A',
            'cases': [
              {'id': 'tc_1', 'title': 'Cas 1'},
              {'id': 'tc_1', 'title': 'Cas 2'},
            ],
          },
          {'id': 'tdd_1', 'name': 'Suite B'},
        ],
        'coherenceIssues': [
          {'id': 'coh_1', 'title': 'Alerte 1'},
          {'id': 'coh_1', 'title': 'Alerte 2'},
        ],
      });

      expect(deduplicated.fixtures.map((f) => f.id).toList(), [
        'fix_1',
        'fix_1_2',
      ]);
      expect(deduplicated.features.map((f) => f.id).toList(), [
        'feat_1',
        'feat_1_2',
      ]);
      expect(
        deduplicated.features.first.scenarios.map((s) => s.id).toList(),
        ['scn_1', 'scn_1_2'],
      );
      expect(deduplicated.tddSuites.map((s) => s.id).toList(), [
        'tdd_1',
        'tdd_1_2',
      ]);
      expect(
        deduplicated.tddSuites.first.cases.map((c) => c.id).toList(),
        ['tc_1', 'tc_1_2'],
      );
      expect(
        deduplicated.tddSuites.first.cases.map((c) => c.order).toList(),
        [1, 2],
      );
      expect(deduplicated.coherenceIssues.map((i) => i.id).toList(), [
        'coh_1',
        'coh_1_2',
      ]);
    });

    test('SpecForgeProject.qaSpec rétrocompatibilité (omis vs renseigné) et QaPromptBuilder', () {
      final withoutQa = SpecForgeProject.fromIdea(
        idea: 'Gestion des retours fournisseurs',
        name: 'ReturnPro',
        id: 'proj_returns',
      );
      expect(withoutQa.qaSpec, equals(QaForgeSpec.empty));
      expect(withoutQa.qaSpec.hasContent, isFalse);

      final jsonWithoutQa = withoutQa.toJson();
      expect(jsonWithoutQa.containsKey('qaSpec'), isFalse);
      expect(
        withoutQa
            .toCompactContextJson(SpecForgeStage.reviewExport)
            .containsKey('qaSummary'),
        isFalse,
      );

      // Chargement d'un JSON historique sans clé qaSpec
      final legacyLoaded = SpecForgeProject.fromJson(jsonWithoutQa);
      expect(legacyLoaded, equals(withoutQa));
      expect(legacyLoaded.qaSpec, equals(QaForgeSpec.empty));

      // Projet avec qaSpec renseigné
      final withQa = _buildRichBusinessAndUxProject().copyWith(
        qaSpec: QaForgeSpec(
          currentStage: QaForgeStage.gherkinFeatures,
          gherkinLanguage: GherkinKeywordLanguage.en,
          fixtures: [
            QaFixtureSpec(
              id: 'fix_1',
              code: 'FIX-001',
              name: 'Commande nominale',
              businessObjectId: 'obj_commande',
            ),
          ],
          features: [
            GherkinFeatureSpec(
              id: 'feat_1',
              code: 'FEAT-001',
              title: 'Order validation',
              scenarios: [
                GherkinScenarioSpec(
                  id: 'scn_1',
                  code: 'SCN-001',
                  title: 'Valid order under credit limit',
                ),
              ],
            ),
          ],
          tddSuites: [
            TddTestSuiteSpec(
              id: 'tdd_1',
              code: 'TDD-001',
              name: 'CreditLimitValidator',
              cases: [
                TddTestCaseSpec(
                  id: 'tc_1',
                  code: 'TC-001',
                  title: 'Allows order within credit limit',
                ),
              ],
            ),
          ],
        ),
      );

      final jsonWithQa = withQa.toJson();
      expect(jsonWithQa.containsKey('qaSpec'), isTrue);
      final compact = withQa.toCompactContextJson(SpecForgeStage.reviewExport);
      expect(compact.containsKey('qaSummary'), isTrue);
      final qaSummary = compact['qaSummary'] as Map<String, Object?>;
      expect(qaSummary['gherkinLanguage'], 'en');
      expect(qaSummary['fixtureCount'], 1);
      expect(qaSummary['featureCount'], 1);
      expect(qaSummary['scenarioCount'], 1);
      expect(qaSummary['tddSuiteCount'], 1);
      expect(qaSummary['tddCaseCount'], 1);
      expect(SpecForgeProject.fromJson(jsonWithQa), equals(withQa));

      final focusBlock = QaPromptBuilder.buildQaFocusScopeBlock(
        project: withQa,
        focusedFixtureId: 'FIX-001',
        focusedFeatureId: 'FEAT-001',
        focusedScenarioId: 'SCN-001',
        focusedTddSuiteId: 'TDD-001',
      );
      expect(focusBlock, contains('FIX-001'));
      expect(focusBlock, contains('FEAT-001'));
      expect(focusBlock, contains('SCN-001'));
      expect(focusBlock, contains('TDD-001'));

      final turnPrompt = QaPromptBuilder.buildTurnPrompt(
        project: withQa,
        stage: QaForgeStage.gherkinFeatures,
        userInput: 'Complète ce scénario avec une table d’exemples',
        questioningLevel: VibeQuestioningLevel.none,
        afterAskUserReply: false,
        focusedScenarioId: 'SCN-001',
      );
      expect(turnPrompt, contains('LANGUE GHERKIN ACTIVE : `en`'));
      expect(turnPrompt, contains('RÉSUMÉ COMPACT DU VOLET UX'));
      expect(turnPrompt, contains('FOCUS COURANT DANS L’ATELIER QA'));
    });
  });

  group('QaPatchApplier.apply, applyPartial, salvageFailedAttempt & contrat additive_safe', () {
    test('ajoute, met à jour par id/code et supprime fixtures, features/scénarios, suites/cas TDD et diagnostics IA', () {
      final initial = _buildRichBusinessAndUxProject().copyWith(
        qaSpec: QaForgeSpec(
          coherenceIssues: const [
            QaCoherenceIssue(
              id: 'local_qa_1',
              severity: CoherenceSeverity.warning,
              stage: QaForgeStage.testFixtures,
              code: 'COH-QA-FIX-001',
              title: 'Diagnostic local à conserver',
              description: 'Issu de QaCoherenceAnalyzer.',
              source: 'local',
            ),
          ],
        ),
      );

      // 1. Création initiale complète via qaPatch
      final step1 = QaPatchApplier.apply(
        initial,
        qaPatch: {
          'gherkinLanguage': 'en',
          'fixtures': [
            {
              'id': 'fix_1',
              'code': 'FIX-001',
              'name': 'Commande nominale',
              'kind': 'nominal',
              'businessObjectId': 'obj_commande',
              'payload': {'numero': 'CMD-2026-001', 'montantHt': 1500},
              'expectedValid': true,
            },
            {
              'id': 'fix_temp',
              'code': 'FIX-002',
              'name': 'Fixture temporaire',
            },
          ],
          'features': [
            {
              'id': 'feat_1',
              'code': 'FEAT-001',
              'title': 'Order approval',
              'backgroundSteps': [
                {'id': 'bg_1', 'keyword': 'given', 'text': 'ADV session is active'},
              ],
              'scenarios': [
                {
                  'id': 'scn_1',
                  'code': 'SCN-001',
                  'title': 'Approve valid order',
                  'steps': [
                    {'id': 's1', 'keyword': 'given', 'text': 'order FIX-001 exists'},
                    {'id': 's2', 'keyword': 'when', 'text': 'ADV clicks approve'},
                    {'id': 's3', 'keyword': 'then', 'text': 'status becomes validee'},
                  ],
                },
                {
                  'id': 'scn_temp',
                  'code': 'SCN-002',
                  'title': 'Temporary scenario',
                },
              ],
            },
            {
              'id': 'feat_temp',
              'code': 'FEAT-002',
              'title': 'Temporary feature',
            },
          ],
          'tddSuites': [
            {
              'id': 'tdd_1',
              'code': 'TDD-001',
              'name': 'OrderCreditLimitValidator',
              'layer': 'domainValidation',
              'targetObjectId': 'obj_commande',
              'cases': [
                {
                  'id': 'tc_1',
                  'code': 'TC-001',
                  'title': 'Approves order below credit limit',
                  'act': 'validator.check(order)',
                  'outcomeKind': 'allowsAction',
                  'assertExpected': 'returns true',
                },
                {
                  'id': 'tc_temp',
                  'code': 'TC-002',
                  'title': 'Temporary case',
                },
              ],
            },
            {
              'id': 'tdd_temp',
              'code': 'TDD-002',
              'name': 'Temporary suite',
            },
          ],
          'coherenceIssues': [
            {
              'id': 'local_qa_1',
              'severity': 'info',
              'stage': 'qaReviewExport',
              'code': 'QA-AI-1',
              'title': 'Recommandation IA dédupliquée',
              'description': 'Suggestion IA.',
            },
          ],
        },
      );

      final qa1 = step1.project.qaSpec;
      expect(qa1.gherkinLanguage, GherkinKeywordLanguage.en);
      expect(qa1.fixtures.length, 2);
      expect(qa1.features.length, 2);
      expect(qa1.totalScenarioCount, 2);
      expect(qa1.tddSuites.length, 2);
      expect(qa1.totalTddCaseCount, 2);
      expect(qa1.coherenceIssues.length, 2);
      expect(qa1.coherenceIssues[0].source, 'local');
      expect(qa1.coherenceIssues[1].id, 'local_qa_1_2');
      expect(qa1.coherenceIssues[1].source, 'ai');

      // 2. Mise à jour incrémentale par code métier + suppressions ciblées
      final step2 = QaPatchApplier.apply(
        step1.project,
        qaPatch: {
          'removeFixtureIds': ['FIX-002'],
          'fixtures': [
            {
              'code': 'FIX-001',
              'description': 'Enrichie avec contexte persona ADV',
              'personaId': 'persona_adv',
            },
          ],
          'removeFeatureIds': ['FEAT-002'],
          'removeScenarioIds': ['SCN-002'],
          'features': [
            {
              'code': 'FEAT-001',
              'narrative': 'As an ADV manager, I validate compliant B2B orders.',
              'scenarios': [
                {
                  'code': 'SCN-001',
                  'fixtureIds': ['FIX-001'],
                },
              ],
            },
          ],
          'removeTddSuiteIds': ['TDD-002'],
          'removeTddCaseIds': ['TC-002'],
          'tddSuites': [
            {
              'code': 'TDD-001',
              'description': 'Suite consolidée Red -> Green -> Refactor',
              'cases': [
                {
                  'code': 'TC-001',
                  'fixtureId': 'FIX-001',
                  'businessRuleIds': ['RG-001'],
                },
              ],
            },
          ],
        },
      );

      final qa2 = step2.project.qaSpec;
      expect(qa2.fixtures.length, 1);
      expect(qa2.fixtures.single.id, 'fix_1');
      expect(qa2.fixtures.single.personaId, 'persona_adv');
      expect(qa2.fixtures.single.payload['numero'], 'CMD-2026-001');

      expect(qa2.features.length, 1);
      final updatedFeat = qa2.features.single;
      expect(updatedFeat.id, 'feat_1');
      expect(updatedFeat.backgroundSteps.single.id, 'bg_1');
      expect(updatedFeat.scenarios.length, 1);
      expect(updatedFeat.scenarios.single.id, 'scn_1');
      expect(updatedFeat.scenarios.single.steps.length, 3);
      expect(updatedFeat.scenarios.single.fixtureIds, ['FIX-001']);

      expect(qa2.tddSuites.length, 1);
      final updatedSuite = qa2.tddSuites.single;
      expect(updatedSuite.id, 'tdd_1');
      expect(updatedSuite.cases.length, 1);
      expect(updatedSuite.cases.single.id, 'tc_1');
      expect(updatedSuite.cases.single.act, 'validator.check(order)');
      expect(updatedSuite.cases.single.fixtureId, 'FIX-001');
      expect(updatedSuite.cases.single.businessRuleIds, ['RG-001']);
    });

    test('contrat additive_safe : ajoute une règle RG-xxx et un attribut depuis QA sans supprimer l’existant', () {
      final baseline = _buildRichBusinessAndUxProject();

      final destructiveAndAdditiveSpecPatch = <String, Object?>{
        // Toutes les clés de suppression doivent être strictement ignorées depuis QA
        'removeBusinessObjectIds': ['obj_client', 'obj_commande'],
        'removeBusinessRuleIds': ['rule_rg_001', 'rule_rg_002'],
        'removeLexiconTermIds': ['term_cmd'],
        'removePersonaIds': ['persona_adv'],
        'removeModuleIds': ['mod_ventes'],
        'removeRequirementIds': ['req_exf_001', 'req_exf_002'],
        'removeUseCaseIds': ['uc_valider_cmd'],
        'removeNfrIds': ['nfr_001'],
        'removeAttributes': [
          {'objectId': 'obj_commande', 'attributeName': 'numero'},
        ],
        'lexicon': {'terms': <Object?>[]},
        'vision': {'personas': <Object?>[]},
        'businessObjects': [
          {
            'id': 'obj_commande',
            'name': 'Commande',
            'technicalName': 'Commande',
            'attributes': [
              {
                'id': 'attr_cmd_plafond_snap',
                'name': 'plafondSnapshotValidation',
                'type': 'number',
                'description':
                    'Plafond d’encours capturé lors de l’assertion d’audit QA',
              },
              {
                'name': 'statut',
                'type': 'enum',
                'enumValues': ['bloquee_encours'],
              },
              {
                'name': 'lignes',
                'type': 'object',
                'isArray': true,
                'children': [
                  {
                    'id': 'attr_lig_tva',
                    'name': 'tauxTvaPct',
                    'type': 'number',
                  },
                ],
              },
            ],
          },
          {
            'id': 'obj_trace_validation',
            'name': 'Trace de validation',
            'technicalName': 'TraceValidation',
            'attributes': [
              {
                'id': 'attr_trace_code',
                'name': 'codeDecision',
                'type': 'string',
                'required': true,
              },
            ],
          },
        ],
        'businessRules': [
          {
            'id': 'rule_rg_003',
            'code': 'RG-003',
            'title': 'Traçabilité du plafond lors du blocage encours',
            'category': 'validation',
            'targetObjectIds': ['obj_commande'],
            'targetAttributes': ['Commande.plafondSnapshotValidation'],
            'condition': 'statut == "bloquee_encours"',
            'effect': 'Enregistrer plafondSnapshotValidation >= 0',
            'errorMessage': 'Le plafond constaté doit être renseigné (RG-003).',
          },
        ],
      };

      final res = QaPatchApplier.apply(
        baseline,
        qaPatch: {
          'fixtures': [
            {
              'id': 'fix_rg_003',
              'code': 'FIX-001',
              'name': 'Commande bloquée avec trace plafond',
              'kind': 'invalid',
              'businessObjectId': 'obj_commande',
              'businessRuleIds': ['RG-003'],
              'expectedValid': false,
              'expectedErrorHint': 'RG-003',
            },
          ],
        },
        specPatch: destructiveAndAdditiveSpecPatch,
      );

      final updated = res.project;

      // Lexique, cadrage, cahier des charges et UX intacts
      expect(updated.lexicon, equals(baseline.lexicon));
      expect(updated.vision, equals(baseline.vision));
      expect(updated.cahierDesCharges, equals(baseline.cahierDesCharges));
      expect(updated.uxSpec, equals(baseline.uxSpec));

      // Aucun objet existant supprimé + TraceValidation ajouté
      expect(updated.businessObjects.map((o) => o.id).toList(), [
        'obj_client',
        'obj_commande',
        'obj_trace_validation',
      ]);

      final commande = updated.findBusinessObject('obj_commande')!;
      expect(commande.attributes.map((a) => a.name).toList(), [
        'numero',
        'montantHt',
        'statut',
        'lignes',
        'plafondSnapshotValidation',
      ]);
      expect(commande.attributes[0].schemaConstraints.minLength, 5);
      expect(commande.attributes[2].enumValues, [
        'brouillon',
        'validee',
        'bloquee_encours',
      ]);
      expect(commande.attributes[3].children.map((c) => c.name).toList(), [
        'codeArticle',
        'quantite',
        'tauxTvaPct',
      ]);
      expect(commande.relations, equals(baseline.businessObjects[1].relations));
      expect(
        commande.lifecycleStates,
        equals(baseline.businessObjects[1].lifecycleStates),
      );
      expect(
        commande.lifecycleTransitions,
        equals(baseline.businessObjects[1].lifecycleTransitions),
      );

      // Règles RG-001 et RG-002 préservées + RG-003 ajoutée
      expect(updated.businessRules.map((r) => r.code).toList(), [
        'RG-001',
        'RG-002',
        'RG-003',
      ]);
      expect(updated.qaSpec.fixtures.single.id, 'fix_rg_003');
    });

    test('QaPatchApplier.applyPartial et salvageFailedAttempt isolent les entrées invalides et récupèrent les flux tronqués', () {
      final baseline = _buildRichBusinessAndUxProject();

      final partial = QaPatchApplier.applyPartial(
        baseline,
        qaPatch: {
          'gherkinLanguage': 999,
          'fixtures': [
            {
              'id': 'fix_ok',
              'code': 'FIX-001',
              'name': 'Fixture valide',
              'businessObjectId': 'obj_commande',
            },
            'fixture_invalide_non_map',
          ],
          'features': [
            {
              'id': 'feat_salvaged',
              'code': 'FEAT-001',
              'title': 'Feature avec un scénario invalide isolé',
              'scenarios': [
                {
                  'id': 'scn_ok',
                  'code': 'SCN-001',
                  'title': 'Scénario valide conservé',
                },
                'scenario_invalide_non_map',
              ],
            },
          ],
          'tddSuites': [
            {
              'id': 'tdd_salvaged',
              'code': 'TDD-001',
              'name': 'Suite avec un cas invalide isolé',
              'cases': [
                {
                  'id': 'tc_ok',
                  'code': 'TC-001',
                  'title': 'Cas TDD valide conservé',
                },
                'cas_tdd_invalide_non_map',
              ],
            },
          ],
          'coherenceIssues': [
            {
              'id': 'qa_coh_ok',
              'severity': 'info',
              'stage': 'qaReviewExport',
              'code': 'QA-01',
              'title': 'Diagnostic valide',
              'description': 'Détail',
            },
            'issue_invalide',
          ],
        },
        specPatch: {
          'removeBusinessObjectIds': ['obj_client'],
          'businessObjects': [
            {
              'id': 'obj_avoir',
              'name': 'Avoir',
              'technicalName': 'Avoir',
              'attributes': [
                {'id': 'a_montant', 'name': 'montant', 'type': 'number'},
              ],
            },
            {
              'id': 'obj_invalide',
              'name': 'Invalide',
              'attributes': [
                {'id': 'a_bad', 'name': '@attributInterdit', 'type': 'string'},
              ],
            },
          ],
          'businessRules': [
            {
              'id': 'r_ok_qa',
              'code': 'RG-004',
              'title': 'Avoir positif',
            },
            'regle_invalide_non_map',
          ],
        },
      );

      expect(partial.hasAppliedChanges, isTrue);
      expect(partial.project.qaSpec.fixtures.single.id, 'fix_ok');
      expect(partial.project.qaSpec.features.single.id, 'feat_salvaged');
      expect(
        partial.project.qaSpec.features.single.scenarios.single.id,
        'scn_ok',
      );
      expect(partial.project.qaSpec.tddSuites.single.id, 'tdd_salvaged');
      expect(
        partial.project.qaSpec.tddSuites.single.cases.single.id,
        'tc_ok',
      );
      expect(partial.project.qaSpec.coherenceIssues.single.id, 'qa_coh_ok');
      expect(partial.project.findBusinessObject('obj_avoir'), isNotNull);
      expect(partial.project.findBusinessObject('obj_client'), isNotNull);
      expect(partial.project.businessRules.any((r) => r.code == 'RG-004'), isTrue);
      expect(partial.rejectedEntries.length, 7);

      const truncatedQaJson =
          '{"message":"Génération QA en cours","qaPatch":{"gherkinLanguage":"en","fixtures":[{"id":"fix_salvaged","code":"FIX-009","name":"Fixture récupérée"},{"id":"fix_tronquee';
      final salvage = QaPatchApplier.salvageFailedAttempt(
        workingProject: baseline,
        rawResponse: truncatedQaJson,
      );
      expect(salvage.hasCheckpoint, isTrue);
      expect(salvage.wasTruncated, isTrue);
      expect(
        salvage.checkpointProject.qaSpec.gherkinLanguage,
        GherkinKeywordLanguage.en,
      );
      expect(
        salvage.checkpointProject.qaSpec.fixtures.single.id,
        'fix_salvaged',
      );
    });
  });

  group('SpecStreamParser & SpecAgentResponse pour qaPatch', () {
    test('détecte hasQaPatch en streaming puis décode qaPatch et specPatch', () {
      final parser = SpecStreamParser();

      var snap = parser.addChunk('{"message":"Structuration BDD/TDD ');
      expect(snap.message, 'Structuration BDD/TDD ');
      expect(snap.isMessageComplete, isFalse);
      expect(snap.hasQaPatch, isFalse);
      expect(snap.hasUxPatch, isFalse);
      expect(snap.hasSpecPatch, isFalse);

      snap = parser.addChunk(
        'terminée.","askUser":null,"qaPatch":{"gherkinLanguage":"en","fixtures":[{"id":"fix_1","code":"FIX-001","name":"Nominal order"}]}',
      );
      expect(snap.message, 'Structuration BDD/TDD terminée.');
      expect(snap.isMessageComplete, isTrue);
      expect(snap.hasQaPatch, isTrue);
      expect(snap.hasSpecPatch, isFalse);

      snap = parser.addChunk(
        ',"specPatch":{"businessRules":[{"id":"r_qa","code":"RG-020","title":"Garde QA"}]},"stageSummary":"1 fixture créée","stageReadyToAdvance":true}',
      );
      expect(snap.hasQaPatch, isTrue);
      expect(snap.hasSpecPatch, isTrue);

      final parsed = SpecAgentResponse.parse('```json\n${parser.rawText}\n```');
      expect(parsed.message, 'Structuration BDD/TDD terminée.');
      expect(parsed.askUser, isNull);
      expect(parsed.qaPatch, isNotNull);
      expect(parsed.qaPatch!['gherkinLanguage'], 'en');
      expect((parsed.qaPatch!['fixtures'] as List).length, 1);
      expect(parsed.specPatch, isNotNull);
      expect((parsed.specPatch!['businessRules'] as List).length, 1);
      expect(parsed.stageSummary, '1 fixture créée');
      expect(parsed.stageReadyToAdvance, isTrue);
    });
  });

  group('SpecForgeController : mutations QA, seeders 1-clic, Undo/Redo unifié et tour IA QA', () {
    test('updateQaSpec, setGherkinLanguage, goToQaStage, seeders 1-clic et Undo/Redo unifié', () async {
      final memoryStore = _MemorySpecProjectStore();
      final seededProject = _buildRichBusinessAndUxProject();
      await memoryStore.saveProject(seededProject);

      final controller = SpecForgeController(
        store: memoryStore,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        domainCatalogStore: _MemoryDomainCatalogStore(),
      );
      addTearDown(controller.dispose);

      await controller.initialize(restoreLastProject: true);
      expect(controller.canUndo, isFalse);
      expect(
        controller.project!.qaSpec.gherkinLanguage,
        GherkinKeywordLanguage.fr,
      );

      // 1. Changement de langue Gherkin
      await controller.setGherkinLanguage(GherkinKeywordLanguage.en);
      expect(
        controller.project!.qaSpec.gherkinLanguage,
        GherkinKeywordLanguage.en,
      );
      expect(controller.canUndo, isTrue);

      // 2. Navigation d'étape QA avec validation de l'étape précédente
      await controller.goToQaStage(
        QaForgeStage.gherkinFeatures,
        validateCurrent: true,
      );
      expect(
        controller.project!.qaSpec.currentStage,
        QaForgeStage.gherkinFeatures,
      );
      expect(
        controller.project!.qaSpec
            .stageStateFor(QaForgeStage.testFixtures)
            .status,
        SpecStageStatus.validated,
      );
      expect(
        controller.project!.qaSpec
            .stageStateFor(QaForgeStage.gherkinFeatures)
            .status,
        SpecStageStatus.inProgress,
      );

      // 3. Seeder 1-clic des fixtures depuis le schéma JSON
      final addedFixtures = await controller.seedQaFixturesFromSchema();
      expect(addedFixtures, 4); // 2 objets métiers * (nominal + invalide/borne)
      expect(controller.project!.qaSpec.fixtures.length, 4);
      // Idempotence si tous les objets métiers sont déjà couverts
      expect(await controller.seedQaFixturesFromSchema(), 0);

      // 4. Seeder 1-clic des features Gherkin depuis Spec + UX
      final addedFeatures = await controller.seedQaFeaturesFromSpecAndUx();
      expect(addedFeatures, greaterThanOrEqualTo(3));
      expect(
        controller.project!.qaSpec.features.length,
        addedFeatures,
      );
      expect(controller.project!.qaSpec.totalScenarioCount, greaterThanOrEqualTo(3));
      expect(await controller.seedQaFeaturesFromSpecAndUx(), 0);

      // 5. Seeder 1-clic des suites TDD depuis les règles RG-xxx actives
      final addedSuites = await controller.seedQaTddSuitesFromRules();
      expect(addedSuites, 2);
      expect(controller.project!.qaSpec.tddSuites.length, 2);
      expect(controller.project!.qaSpec.totalTddCaseCount, 4);
      expect(await controller.seedQaTddSuitesFromRules(), 0);

      // 6. Mise à jour manuelle via updateQaSpec
      final customFixture = QaFixtureSpec(
        id: 'fix_manual_vip',
        code: 'FIX-099',
        name: 'Client VIP plafond étendu',
        kind: QaFixtureKind.permission,
        businessObjectId: 'obj_client',
      );
      await controller.updateQaSpec(
        controller.project!.qaSpec.copyWith(
          fixtures: [...controller.project!.qaSpec.fixtures, customFixture],
        ),
      );
      expect(controller.project!.qaSpec.fixtures.length, 5);

      // 7. Vérification de la pile Undo/Redo unifiée sur toutes les mutations QA
      await controller.undo(); // Annule updateQaSpec (FIX-099)
      expect(controller.project!.qaSpec.fixtures.length, 4);

      await controller.undo(); // Annule seedQaTddSuitesFromRules
      expect(controller.project!.qaSpec.tddSuites, isEmpty);

      await controller.undo(); // Annule seedQaFeaturesFromSpecAndUx
      expect(controller.project!.qaSpec.features, isEmpty);

      await controller.undo(); // Annule seedQaFixturesFromSchema
      expect(controller.project!.qaSpec.fixtures, isEmpty);

      await controller.undo(); // Annule setGherkinLanguage(en)
      expect(
        controller.project!.qaSpec.gherkinLanguage,
        GherkinKeywordLanguage.fr,
      );
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);

      while (controller.canRedo) {
        await controller.redo();
      }
      expect(
        controller.project!.qaSpec.gherkinLanguage,
        GherkinKeywordLanguage.en,
      );
      expect(controller.project!.qaSpec.fixtures.length, 5);
      expect(controller.project!.qaSpec.features.length, addedFeatures);
      expect(controller.project!.qaSpec.totalTddCaseCount, 4);
    });

    test('simule un tour IA QA en streaming avec FakeSpecAiService, qaPatch + specPatch additif et Undo/Redo', () async {
      final responsePayload = <String, Object?>{
        'message':
            'J’ai structuré la suite TDD-001, la feature FEAT-001 et ajouté l’attribut codeControleQa.',
        'askUser': null,
        'qaPatch': {
          'gherkinLanguage': 'en',
          'fixtures': [
            {
              'id': 'fix_cmd_ok',
              'code': 'FIX-001',
              'name': 'Valid B2B order',
              'kind': 'nominal',
              'businessObjectId': 'obj_commande',
              'payload': {'numero': 'CMD-2026-100', 'montantHt': 3200},
              'expectedValid': true,
            },
          ],
          'features': [
            {
              'id': 'feat_approval',
              'code': 'FEAT-001',
              'title': 'B2B Order Credit Approval',
              'scenarios': [
                {
                  'id': 'scn_approval_outline',
                  'code': 'SCN-001',
                  'title': 'Credit check by amount <amount>',
                  'isOutline': true,
                  'steps': [
                    {
                      'id': 's1',
                      'keyword': 'given',
                      'text': 'an order of <amount> EUR',
                    },
                    {
                      'id': 's2',
                      'keyword': 'when',
                      'text': 'credit check runs',
                    },
                    {
                      'id': 's3',
                      'keyword': 'then',
                      'text': 'outcome is <expected>',
                    },
                  ],
                  'examples': {
                    'headers': ['amount', 'expected'],
                    'rows': [
                      ['3200', 'validee'],
                      ['50000', 'rejetee'],
                    ],
                  },
                  'businessRuleIds': ['RG-001', 'RG-020'],
                  'fixtureIds': ['FIX-001'],
                },
              ],
            },
          ],
          'tddSuites': [
            {
              'id': 'tdd_credit_guard',
              'code': 'TDD-001',
              'name': 'OrderCreditGuard',
              'layer': 'domainValidation',
              'targetObjectId': 'obj_commande',
              'cases': [
                {
                  'id': 'tc_guard_1',
                  'code': 'TC-001',
                  'order': 1,
                  'title': 'Stamps codeControleQa when order passes RG-001',
                  'fixtureId': 'FIX-001',
                  'arrange': 'Load FIX-001 with limit 10000',
                  'act': 'guard.approve(order)',
                  'outcomeKind': 'mutatesState',
                  'assertExpected': 'order.codeControleQa is non-empty',
                  'businessRuleIds': ['RG-001', 'RG-020'],
                },
              ],
            },
          ],
        },
        'specPatch': {
          'removeBusinessObjectIds': ['obj_client'],
          'businessObjects': [
            {
              'id': 'obj_commande',
              'name': 'Commande',
              'technicalName': 'Commande',
              'attributes': [
                {
                  'id': 'attr_code_ctrl_qa',
                  'name': 'codeControleQa',
                  'type': 'string',
                },
              ],
            },
          ],
          'businessRules': [
            {
              'id': 'rule_rg_020',
              'code': 'RG-020',
              'title': 'Empreinte de contrôle obligatoire à la validation',
              'category': 'validation',
              'targetObjectIds': ['obj_commande'],
            },
          ],
        },
        'stageSummary': 'Suite TDD-001, FEAT-001 et RG-020 alignés.',
        'stageReadyToAdvance': true,
      };
      final fullJson = jsonEncode(responsePayload);
      final cut1 = fullJson.indexOf('TDD-001') + 7;
      final cut2 = fullJson.indexOf('"specPatch"');

      final fakeAi = FakeSpecAiService([
        [
          fullJson.substring(0, cut1),
          fullJson.substring(cut1, cut2),
          fullJson.substring(cut2),
        ],
      ]);

      final memoryStore = _MemorySpecProjectStore();
      await memoryStore.saveProject(_buildRichBusinessAndUxProject());

      final controller = SpecForgeController(
        store: memoryStore,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        domainCatalogStore: _MemoryDomainCatalogStore(),
        aiService: fakeAi,
        initialQuestioningLevel: VibeQuestioningLevel.none,
      );
      addTearDown(controller.dispose);

      await controller.initialize(restoreLastProject: true);
      await controller.goToQaStage(QaForgeStage.tddSuites);
      controller.focusQaItem(fixtureId: 'FIX-001');
      expect(controller.focusedFixtureId, 'FIX-001');

      final observedStreamingMessages = <String>[];
      final observedStatuses = <String>[];
      var sawSendingQa = false;
      QaForgeStage? observedSendingQaStage;

      controller.addListener(() {
        if (controller.isSendingQa) {
          sawSendingQa = true;
          observedSendingQaStage = controller.sendingQaStage;
        }
        final msg = controller.streamingMessage;
        if (msg != null && msg.isNotEmpty) {
          observedStreamingMessages.add(msg);
        }
        if (controller.streamingStatus.isNotEmpty) {
          observedStatuses.add(controller.streamingStatus);
        }
      });

      await controller.sendQaUserMessage(
        'Conçois la suite TDD et le scénario Gherkin de contrôle d’encours.',
      );

      expect(sawSendingQa, isTrue);
      expect(observedSendingQaStage, QaForgeStage.tddSuites);
      expect(controller.isSendingQa, isFalse);
      expect(
        observedStreamingMessages.first,
        contains('J’ai structuré la suite TDD-001'),
      );
      expect(
        observedStatuses,
        contains('Mise à jour des tests BDD / TDD…'),
      );
      expect(fakeAi.receivedPrompts.length, 1);

      final updated = controller.project!;
      expect(updated.qaSpec.gherkinLanguage, GherkinKeywordLanguage.en);
      expect(updated.qaSpec.fixtures.single.id, 'fix_cmd_ok');
      expect(updated.qaSpec.features.single.id, 'feat_approval');
      expect(updated.qaSpec.tddSuites.single.id, 'tdd_credit_guard');

      // Vérifie le contrat additive_safe sur specPatch : Client préservé, Commande enrichie, RG-020 ajoutée
      expect(updated.findBusinessObject('obj_client'), isNotNull);
      final commande = updated.findBusinessObject('obj_commande')!;
      expect(commande.attributes.map((a) => a.name).toList(), [
        'numero',
        'montantHt',
        'statut',
        'lignes',
        'codeControleQa',
      ]);
      expect(updated.businessRules.map((r) => r.code).toList(), [
        'RG-001',
        'RG-002',
        'RG-020',
      ]);

      final qaStageState = updated.qaSpec.stageStateFor(QaForgeStage.tddSuites);
      expect(qaStageState.messages.length, 2);
      expect(qaStageState.messages.last.isUser, isFalse);
      expect(qaStageState.messages.last.appliedPatchSummary, isNotEmpty);
      expect(qaStageState.readyToAdvance, isTrue);
      expect(
        qaStageState.stageSummary,
        'Suite TDD-001, FEAT-001 et RG-020 alignés.',
      );

      // Le tour IA QA complet s'annule et se rétablit en 1 clic via Undo / Redo
      expect(controller.canUndo, isTrue);
      await controller.undo();
      expect(controller.project!.qaSpec.tddSuites, isEmpty);
      expect(controller.project!.qaSpec.features, isEmpty);
      expect(
        controller.project!.qaSpec.gherkinLanguage,
        GherkinKeywordLanguage.fr,
      );
      expect(
        controller.project!
            .findBusinessObject('obj_commande')!
            .attributes
            .any((a) => a.name == 'codeControleQa'),
        isFalse,
      );
      expect(controller.project!.businessRules.length, 2);

      await controller.redo();
      expect(
        controller.project!.qaSpec.tddSuites.single.id,
        'tdd_credit_guard',
      );
      expect(controller.project!.businessRules.length, 3);
    });
  });
}
