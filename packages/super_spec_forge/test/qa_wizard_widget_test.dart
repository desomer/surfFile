import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/main.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemoryModelDictionaryStore extends ModelDictionaryStore {
  _MemoryModelDictionaryStore() : super(Directory('memory_qa_store'));

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
  _MemoryCompanyGlossaryStore() : super(Directory('memory_qa_store'));

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
  _MemoryDomainCatalogStore() : super(Directory('memory_qa_store'));

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
  _MemorySpecProjectStore() : super(Directory('memory_qa_store'));

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

class _QueuedQaAiTurn {
  _QueuedQaAiTurn({required this.payload, this.pauseAfterFirstChunk});

  final Map<String, Object?> payload;
  final Completer<void>? pauseAfterFirstChunk;
}

class _FakeQaSpecAiService implements SpecAiService {
  final List<String> receivedPrompts = [];
  final List<String?> receivedSystemInstructions = [];
  final List<_QueuedQaAiTurn> _queuedTurns = [];

  int get callCount => receivedPrompts.length;

  void enqueueResponse(
    Map<String, Object?> payload, {
    Completer<void>? pauseAfterFirstChunk,
  }) {
    _queuedTurns.add(
      _QueuedQaAiTurn(
        payload: payload,
        pauseAfterFirstChunk: pauseAfterFirstChunk,
      ),
    );
  }

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

    final queued = _queuedTurns.isNotEmpty
        ? _queuedTurns.removeAt(0)
        : _QueuedQaAiTurn(
            payload: <String, Object?>{
              'message': 'Réponse QA par défaut.',
              'askUser': null,
              'qaPatch': null,
              'specPatch': null,
              'stageReadyToAdvance': false,
            },
          );

    final encoded = jsonEncode(queued.payload);
    final gate = queued.pauseAfterFirstChunk;
    if (gate != null && encoded.length > 28) {
      final splitAt = (encoded.length ~/ 2).clamp(20, encoded.length - 4);
      final firstHalf = encoded.substring(0, splitAt);
      final secondHalf = encoded.substring(splitAt);
      yield GeminiStreamEvent(
        deltaText: firstHalf,
        accumulatedText: firstHalf,
        isDone: false,
        usedContextCache: false,
      );
      await gate.future;
      yield GeminiStreamEvent(
        deltaText: secondHalf,
        accumulatedText: encoded,
        isDone: true,
        usedContextCache: false,
      );
      return;
    }

    yield GeminiStreamEvent(
      deltaText: encoded,
      accumulatedText: encoded,
      isDone: true,
      usedContextCache: false,
    );
  }
}

void _configureDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

SpecForgeController _createController({
  _MemorySpecProjectStore? store,
  SpecAiService? aiService,
}) {
  return SpecForgeController(
    store: store ?? _MemorySpecProjectStore(),
    glossaryStore: _MemoryCompanyGlossaryStore(),
    modelDictionaryStore: _MemoryModelDictionaryStore(),
    domainCatalogStore: _MemoryDomainCatalogStore(),
    aiService: aiService ?? _FakeQaSpecAiService(),
  );
}

SpecForgeProject _buildSampleProject({
  SpecForgeStage currentSpecStage = SpecForgeStage.lexicon,
  UxForgeSpec? uxSpec,
  QaForgeSpec? qaSpec,
  List<BusinessObjectSpec>? businessObjects,
  List<BusinessRuleSpec>? businessRules,
}) {
  final base = SpecForgeProject.fromIdea(
    id: 'proj_artisan_qa',
    name: 'Artisan Devis QA',
    idea: 'Application Desktop de chiffrage, devis et validation d’encours BTP',
  );
  return base.copyWith(
    currentStage: currentSpecStage,
    vision: SpecVision(
      ideaSummary: 'Gestion intégrée et fiable des devis et chantiers artisans',
      personas: [
        SpecPersona(
          id: 'persona_chef',
          name: 'Chef de chantier',
          role: 'Conducteur de travaux',
          goals: const ['Chiffrer un devis conforme en moins de 3 minutes'],
          painPoints: const ['Erreurs de saisie sur les montants'],
        ),
        SpecPersona(
          id: 'persona_compta',
          name: 'Comptable',
          role: 'Responsable facturation',
          goals: const ['Contrôler les plafonds et acomptes'],
        ),
      ],
    ),
    cahierDesCharges: SpecCahierDesCharges(
      modules: const [
        SpecModule(
          id: 'mod_devis',
          name: 'Gestion des devis',
          description: 'Édition et validation des propositions chiffrées',
        ),
      ],
      functionalRequirements: [
        FunctionalRequirement(
          id: 'req_devis_001',
          code: 'EXF-001',
          title: 'Validation d’un devis à montant positif',
          moduleId: 'mod_devis',
          priority: RequirementPriority.must,
          actorIds: const ['persona_chef'],
          acceptanceCriteria: const [
            'Refuse un montant inférieur ou égal à 0',
            'Passe le devis au statut valide',
          ],
        ),
      ],
      useCases: [
        UseCaseSpec(
          id: 'uc_creer_devis',
          title: 'Créer et valider un devis client',
          actorId: 'persona_chef',
          preconditions: const ['Devis au statut brouillon'],
          mainFlow: const [
            'Saisir le numéro et le montant HT',
            'Soumettre le devis pour validation',
          ],
          postconditions: const ['Devis validé et prêt à l’envoi'],
        ),
      ],
    ),
    businessObjects:
        businessObjects ??
        [
          BusinessObjectSpec(
            id: 'obj_devis',
            name: 'Devis',
            technicalName: 'Devis',
            description: 'Proposition commerciale chiffrée',
            attributes: [
              BusinessAttribute(
                id: 'attr_devis_id',
                name: 'id',
                type: BusinessAttributeType.uuid,
                required: true,
                unique: true,
              ),
              BusinessAttribute(
                id: 'attr_devis_numero',
                name: 'numero',
                type: BusinessAttributeType.string,
                required: true,
                schemaConstraints: JsonSchemaConstraints(
                  examples: const ['DEV-2026-001'],
                ),
              ),
              BusinessAttribute(
                id: 'attr_devis_montant',
                name: 'montantHt',
                type: BusinessAttributeType.number,
                required: true,
                schemaConstraints: JsonSchemaConstraints(
                  minimum: 1,
                  examples: const [1250.0],
                ),
              ),
            ],
          ),
        ],
    businessRules:
        businessRules ??
        [
          BusinessRuleSpec(
            id: 'rule_rg_001',
            code: 'RG-001',
            title: 'Montant HT strictement positif',
            targetObjectIds: const ['obj_devis'],
            condition: 'montantHt <= 0',
            effect: 'Refuser la validation du devis',
            errorMessage: 'Le montant HT du devis doit être supérieur à 0.',
          ),
        ],
    uxSpec:
        uxSpec ??
        UxForgeSpec(
          currentStage: UxForgeStage.uxReviewExport,
          journeys: [
            UxJourneySpec(
              id: 'jrn_devis',
              code: 'JRN-001',
              name: 'Création express de devis chantier',
              personaId: 'persona_chef',
              useCaseIds: const ['uc_creer_devis'],
              requirementIds: const ['EXF-001'],
              steps: const [
                UxJourneyStep(
                  id: 'jstep_1',
                  order: 1,
                  title: 'Saisie des postes et validation',
                  actorAction: 'Renseigne le montant HT et clique sur Valider',
                  systemResponse: 'Contrôle RG-001 et confirme la validation',
                  targetRouteId: 'route_devis',
                ),
              ],
            ),
          ],
          navigation: UxNavigationSpec(
            homeRouteId: 'route_devis',
            routes: [
              UxRouteNode(
                id: 'route_devis',
                path: '/devis',
                title: 'Atelier Devis',
                moduleId: 'mod_devis',
              ),
            ],
          ),
          screens: [
            UxScreenSpec(
              id: 'scr_devis',
              code: 'SCR-001',
              name: 'Atelier Devis Clients',
              routeId: 'route_devis',
              pattern: UxScreenPattern.masterDetail,
              primaryObjectId: 'obj_devis',
            ),
          ],
        ),
    qaSpec: qaSpec ?? QaForgeSpec.empty,
  );
}

void main() {
  testWidgets(
    '1. Navigation & Handoffs inter-wizards : SpecLinksView (sans/avec projet), UxReviewExportView, ReviewExportView et bascules steppers 3 wizards',
    (WidgetTester tester) async {
      _configureDesktopViewport(tester);

      final memStore = _MemorySpecProjectStore();
      final controller = _createController(store: memStore);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      // 1a. Sans projet actif : la carte Wizard BDD / Gherkin & TDD affiche un SnackBar.
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );
      final qaLinkCard = find.byKey(const ValueKey('spec-link-qa_wizard'));
      expect(qaLinkCard, findsOneWidget);
      expect(find.text(SpecLinksView.qaWizardLabel), findsOneWidget);

      await tester.tap(qaLinkCard);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Aucun projet actif — ouvrez ou créez un projet dans Projets',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-forge-qa-wizard-view')),
        findsNothing,
      );

      // 1b. Activation d'un projet positionné sur ReviewExportView (W1) et UxReviewExportView (W2) non validées.
      final seeded = _buildSampleProject(
        currentSpecStage: SpecForgeStage.reviewExport,
      );
      expect(
        seeded.stageStateFor(SpecForgeStage.reviewExport).status,
        isNot(SpecStageStatus.validated),
      );
      expect(
        seeded.uxSpec.stageStateFor(UxForgeStage.uxReviewExport).status,
        isNot(SpecStageStatus.validated),
      );
      memStore.seedProject(seeded);
      await controller.openProject(seeded.id);
      await tester.pumpAndSettle();

      // Ouverture directe depuis la carte SpecLinksView avec projet actif.
      await tester.tap(find.byKey(const ValueKey('spec-link-qa_wizard')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-forge-qa-wizard-view')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('qa-wizard-stepper')), findsOneWidget);

      // Retour au menu Spec puis ouverture de l'étape 4 du Wizard UX.
      await tester.tap(find.byKey(const ValueKey('qa-subview-back-btn')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );

      // 1c. Handoff depuis Wizard 2 Étape 4 (UxReviewExportView -> ux-review-continue-to-qa-btn).
      await tester.tap(find.byKey(const ValueKey('spec-link-ux_wizard')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ux-review-export-view')),
        findsOneWidget,
      );

      final uxContinueToQaBtn = find.byKey(
        const ValueKey('ux-review-continue-to-qa-btn'),
      );
      expect(uxContinueToQaBtn, findsOneWidget);
      await tester.tap(uxContinueToQaBtn);
      await tester.pumpAndSettle();

      expect(
        controller.project!.uxSpec
            .stageStateFor(UxForgeStage.uxReviewExport)
            .status,
        SpecStageStatus.validated,
      );
      expect(
        find.byKey(const ValueKey('spec-forge-qa-wizard-view')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('qa-wizard-stepper')), findsOneWidget);

      // 1d. Bascule QA -> Wizard Métier (Étape 6 ReviewExportView) puis handoff spec-review-continue-to-qa-btn.
      await tester.tap(
        find.byKey(const ValueKey('qa-switch-to-spec-wizard-btn')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-forge-qa-wizard-view')),
        findsNothing,
      );
      expect(find.byType(ReviewExportView), findsOneWidget);

      final specContinueToQaBtn = find.byKey(
        const ValueKey('spec-review-continue-to-qa-btn'),
      );
      expect(specContinueToQaBtn, findsOneWidget);
      await tester.tap(specContinueToQaBtn);
      await tester.pumpAndSettle();

      expect(
        controller.project!.stageStateFor(SpecForgeStage.reviewExport).status,
        SpecStageStatus.validated,
      );
      expect(
        find.byKey(const ValueKey('spec-forge-qa-wizard-view')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('qa-wizard-stepper')), findsOneWidget);

      // 1e. Bascules inter-wizards bidirectionnelles entre les 3 steppers.
      await tester.tap(
        find.byKey(const ValueKey('qa-switch-to-spec-wizard-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-switch-to-qa-wizard-btn')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('spec-switch-to-qa-wizard-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-qa-wizard-view')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('qa-switch-to-ux-wizard-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-ux-wizard-view')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ux-switch-to-qa-wizard-btn')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('ux-switch-to-qa-wizard-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-qa-wizard-view')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('qa-wizard-stepper')), findsOneWidget);
    },
  );

  testWidgets(
    '2. Étape 1 (QaFixturesEditorView) & Étape 2 (QaGherkinEditorView) : seed fixtures JSON Schemas, filtres kind, payload JSON, seed Gherkin UC/UX et bascule FR <-> EN',
    (WidgetTester tester) async {
      _configureDesktopViewport(tester);

      final memStore = _MemorySpecProjectStore();
      final controller = _createController(store: memStore);
      addTearDown(controller.dispose);

      final project = _buildSampleProject();
      memStore.seedProject(project);
      await controller.openProject(project.id);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-link-qa_wizard')));
      await tester.pumpAndSettle();

      // 2a. Étape 1 : seed des fixtures depuis les JSON Schemas, filtre par catégorie et inspection du payload JSON.
      expect(
        find.byKey(const ValueKey('qa-fixtures-editor-view')),
        findsOneWidget,
      );
      expect(controller.project!.qaSpec.fixtures, isEmpty);

      final seedFixturesBtn = find.byKey(
        const ValueKey('qa-seed-fixtures-btn'),
      );
      expect(seedFixturesBtn, findsOneWidget);
      await tester.tap(seedFixturesBtn);
      await tester.pumpAndSettle();

      final seededFixtures = controller.project!.qaSpec.fixtures;
      expect(seededFixtures.length, greaterThanOrEqualTo(2));
      final nominalFixture = seededFixtures.firstWhere(
        (f) => f.kind == QaFixtureKind.nominal,
      );
      final negativeFixture = seededFixtures.firstWhere(
        (f) => f.kind != QaFixtureKind.nominal,
      );

      expect(
        find.byKey(ValueKey('qa-fixture-tile-${nominalFixture.id}')),
        findsOneWidget,
      );

      // Filtrage par catégorie (kind).
      await tester.tap(
        find.widgetWithText(ChoiceChip, QaFixtureKind.nominal.label),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('qa-fixture-tile-${nominalFixture.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('qa-fixture-tile-${negativeFixture.id}')),
        findsNothing,
      );

      await tester.tap(
        find.widgetWithText(ChoiceChip, negativeFixture.kind.label),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('qa-fixture-tile-${nominalFixture.id}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('qa-fixture-tile-${negativeFixture.id}')),
        findsOneWidget,
      );

      // Réinitialisation du filtre kind en recliquant la puce active.
      await tester.tap(
        find.widgetWithText(ChoiceChip, negativeFixture.kind.label),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('qa-fixture-tile-${nominalFixture.id}')),
        findsOneWidget,
      );

      // Sélection et inspection de la carte de payload JSON.
      await tester.tap(
        find.byKey(ValueKey('qa-fixture-tile-${nominalFixture.id}')),
      );
      await tester.pumpAndSettle();

      final payloadCard = find.byKey(const ValueKey('qa-fixture-payload-card'));
      expect(payloadCard, findsOneWidget);
      expect(
        find.byKey(const ValueKey('qa-copy-fixture-json-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('qa-edit-fixture-json-btn')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: payloadCard,
          matching: find.textContaining('"numero"'),
        ),
        findsOneWidget,
      );

      // 2b. Navigation vers l'étape 2 (Features Gherkin BDD) via le stepper QA.
      await tester.tap(
        find.byKey(const ValueKey('qa-step-tile-gherkinFeatures')),
      );
      await tester.pumpAndSettle();

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
        find.byKey(const ValueKey('qa-gherkin-editor-view')),
        findsOneWidget,
      );
      expect(controller.project!.qaSpec.features, isEmpty);

      // Seed Gherkin depuis les UC et parcours UX.
      final seedGherkinBtn = find.byKey(const ValueKey('qa-seed-gherkin-btn'));
      expect(seedGherkinBtn, findsOneWidget);
      await tester.tap(seedGherkinBtn);
      await tester.pumpAndSettle();

      expect(controller.project!.qaSpec.features, isNotEmpty);

      // Bascule sur l'onglet Aperçu .feature et vérification de la langue FR par défaut.
      final codePreviewTab = find.byKey(
        const ValueKey('qa-feature-code-preview-tab'),
      );
      expect(codePreviewTab, findsOneWidget);
      await tester.tap(codePreviewTab);
      await tester.pumpAndSettle();

      final previewPane = find.byKey(
        const ValueKey('qa-feature-code-preview-pane'),
      );
      expect(previewPane, findsOneWidget);
      expect(
        controller.project!.qaSpec.gherkinLanguage,
        GherkinKeywordLanguage.fr,
      );
      expect(
        find.descendant(
          of: previewPane,
          matching: find.textContaining('# language: fr'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: previewPane,
          matching: find.textContaining('Fonctionnalité:'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: previewPane,
          matching: find.textContaining('Feature:'),
        ),
        findsNothing,
      );

      // Bascule FR -> EN via qa-gherkin-lang-toggle.
      final langToggle = find.byKey(const ValueKey('qa-gherkin-lang-toggle'));
      expect(langToggle, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qa-gherkin-lang-en')));
      await tester.pumpAndSettle();

      expect(
        controller.project!.qaSpec.gherkinLanguage,
        GherkinKeywordLanguage.en,
      );
      expect(
        find.descendant(
          of: previewPane,
          matching: find.textContaining('# language: en'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: previewPane,
          matching: find.textContaining('Feature:'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: previewPane,
          matching: find.textContaining('Fonctionnalité:'),
        ),
        findsNothing,
      );

      // Bascule retour EN -> FR.
      await tester.tap(find.byKey(const ValueKey('qa-gherkin-lang-fr')));
      await tester.pumpAndSettle();

      expect(
        controller.project!.qaSpec.gherkinLanguage,
        GherkinKeywordLanguage.fr,
      );
      expect(
        find.descendant(
          of: previewPane,
          matching: find.textContaining('# language: fr'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: previewPane,
          matching: find.textContaining('Fonctionnalité:'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '3. Étape 3 (QaTddEditorView) : navigation stepper, seed TDD depuis RG-xxx, cartes AAA Red->Green->Refactor et ajout rapide RG-xxx avec Undo/Redo',
    (WidgetTester tester) async {
      _configureDesktopViewport(tester);

      final memStore = _MemorySpecProjectStore();
      final controller = _createController(store: memStore);
      addTearDown(controller.dispose);

      final project = _buildSampleProject();
      memStore.seedProject(project);
      await controller.openProject(project.id);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-link-qa_wizard')));
      await tester.pumpAndSettle();

      // Navigation vers l'étape 3 (Suites TDD Unitaires) via qa-step-tile-tddSuites.
      await tester.tap(find.byKey(const ValueKey('qa-step-tile-tddSuites')));
      await tester.pumpAndSettle();

      expect(controller.project!.qaSpec.currentStage, QaForgeStage.tddSuites);
      expect(find.byKey(const ValueKey('qa-tdd-editor-view')), findsOneWidget);
      expect(controller.project!.qaSpec.tddSuites, isEmpty);

      // 3a. Génération des suites TDD depuis les règles RG-xxx.
      final seedTddBtn = find.byKey(const ValueKey('qa-seed-tdd-btn'));
      expect(seedTddBtn, findsOneWidget);
      await tester.tap(seedTddBtn);
      await tester.pumpAndSettle();

      final suites = controller.project!.qaSpec.tddSuites;
      expect(suites, isNotEmpty);
      final firstSuite = suites.first;
      expect(firstSuite.cases, isNotEmpty);

      // 3b. Vérification de la section Red -> Green -> Refactor et des blocs AAA.
      expect(find.text('Progression Red → Green → Refactor'), findsOneWidget);
      expect(
        find.byKey(ValueKey('qa-tdd-suite-tile-${firstSuite.id}')),
        findsOneWidget,
      );
      final firstCase = firstSuite.cases.first;
      expect(
        find.byKey(ValueKey('qa-tdd-case-card-${firstCase.id}')),
        findsOneWidget,
      );
      expect(find.text('ARRANGE'), findsWidgets);
      expect(find.text('ACT'), findsWidgets);
      expect(find.text('ASSERT'), findsWidgets);

      // 3c. Ajout rapide d'une règle de gestion RG-xxx + Undo / Redo.
      expect(controller.project!.businessRules, hasLength(1));

      final quickAddRuleBtn = find.byKey(
        const ValueKey('qa-quick-add-rule-btn'),
      );
      expect(quickAddRuleBtn, findsOneWidget);
      await tester.tap(quickAddRuleBtn);
      await tester.pumpAndSettle();

      expect(find.text('Nouvelle règle de gestion RG'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Intitulé de la règle *'),
        'Remise commerciale plafonnée à 15 %',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Condition (Si ...)'),
        'tauxRemise > 15',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Effet ou calcul attendu (Alors ...)'),
        'Exiger une validation direction avant envoi',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();

      expect(controller.project!.businessRules, hasLength(2));
      expect(
        controller.project!.businessRules.map((r) => r.code),
        containsAll(<String>['RG-001', 'RG-002']),
      );
      expect(controller.canUndo, isTrue);

      // Annuler (Undo).
      await tester.tap(find.byTooltip('Annuler (Undo)'));
      await tester.pumpAndSettle();
      expect(controller.project!.businessRules, hasLength(1));
      expect(
        controller.project!.businessRules.map((r) => r.code),
        isNot(contains('RG-002')),
      );
      expect(controller.canRedo, isTrue);

      // Rétablir (Redo).
      await tester.tap(find.byTooltip('Rétablir (Redo)'));
      await tester.pumpAndSettle();
      expect(controller.project!.businessRules, hasLength(2));
      expect(
        controller.project!.businessRules.map((r) => r.code),
        containsAll(<String>['RG-001', 'RG-002']),
      );
    },
  );

  testWidgets(
    '4. Étape 4 (QaReviewExportView) & Chat IA QA en streaming SSE avec qaPatch et specPatch additif (zéro bouton HTML Navigateur)',
    (WidgetTester tester) async {
      _configureDesktopViewport(tester);

      final memStore = _MemorySpecProjectStore();
      final fakeAi = _FakeQaSpecAiService();
      final controller = _createController(store: memStore, aiService: fakeAi);
      addTearDown(controller.dispose);

      final project = _buildSampleProject(
        qaSpec: QaForgeSpec(currentStage: QaForgeStage.testFixtures),
      );
      memStore.seedProject(project);
      await controller.openProject(project.id);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-link-qa_wizard')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('qa-stage-ai-chat-pane')),
        findsOneWidget,
      );
      expect(fakeAi.callCount, 0);

      // 4a. Kickoff en streaming SSE sur QaStageAiChatPane.
      final streamGate = Completer<void>();
      fakeAi.enqueueResponse(<String, Object?>{
        'message': 'J’ai préparé une fixture nominale conforme pour Devis.',
        'askUser': null,
        'qaPatch': <String, Object?>{
          'fixtures': <Object?>[
            <String, Object?>{
              'id': 'fix_ia_nominal',
              'code': 'FIX-001',
              'name': 'Devis chantier nominal',
              'kind': 'nominal',
              'businessObjectId': 'obj_devis',
              'personaId': 'persona_chef',
              'businessRuleIds': <String>['RG-001'],
              'payload': <String, Object?>{
                'id': 'devis-001',
                'numero': 'DEV-2026-100',
                'montantHt': 2450.0,
              },
              'expectedValid': true,
            },
          ],
        },
        'specPatch': null,
        'stageSummary': 'Fixture nominale initialisée.',
        'stageReadyToAdvance': true,
      }, pauseAfterFirstChunk: streamGate);

      final kickoffBtn = find.byKey(const ValueKey('qa-stage-kickoff-btn'));
      expect(kickoffBtn, findsOneWidget);
      await tester.tap(kickoffBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(controller.isSendingQa, isTrue);
      expect(find.byType(SpecStreamingBubble), findsOneWidget);
      expect(
        find.byKey(const ValueKey('qa-chat-stop-streaming')),
        findsOneWidget,
      );

      streamGate.complete();
      await tester.pumpAndSettle();

      expect(controller.isSendingQa, isFalse);
      expect(fakeAi.callCount, 1);
      expect(controller.project!.qaSpec.fixtures, hasLength(1));
      expect(controller.project!.qaSpec.fixtures.single.code, 'FIX-001');
      expect(
        find.byKey(const ValueKey('qa-stage-ready-advance-btn')),
        findsOneWidget,
      );

      // 4b. Message utilisateur libre retournant conjointement qaPatch + specPatch additif.
      fakeAi.enqueueResponse(<String, Object?>{
        'message': 'Feature Gherkin, suite TDD et enrichissement métier additif appliqués.',
        'askUser': null,
        'qaPatch': <String, Object?>{
          'features': <Object?>[
            <String, Object?>{
              'id': 'feat_ia_devis',
              'code': 'FEAT-001',
              'title': 'Validation conforme des devis artisans',
              'moduleId': 'mod_devis',
              'personaId': 'persona_chef',
              'scenarios': <Object?>[
                <String, Object?>{
                  'id': 'scn_ia_1',
                  'code': 'SCN-001',
                  'title': 'Validation nominale d’un devis positif',
                  'requirementIds': <String>['EXF-001'],
                  'useCaseIds': <String>['uc_creer_devis'],
                  'businessRuleIds': <String>['RG-001'],
                  'journeyIds': <String>['JRN-001'],
                  'screenIds': <String>['SCR-001'],
                  'fixtureIds': <String>['FIX-001'],
                  'steps': <Object?>[
                    <String, Object?>{
                      'id': 'st_ia_1',
                      'keyword': 'given',
                      'text': 'la fixture FIX-001 de devis à 2450 EUR HT',
                    },
                    <String, Object?>{
                      'id': 'st_ia_2',
                      'keyword': 'when',
                      'text': 'le chef de chantier valide le devis',
                    },
                    <String, Object?>{
                      'id': 'st_ia_3',
                      'keyword': 'then',
                      'text': 'le devis passe au statut valide',
                    },
                  ],
                },
              ],
            },
          ],
          'tddSuites': <Object?>[
            <String, Object?>{
              'id': 'tdd_ia_devis',
              'code': 'TDD-001',
              'name': 'DevisMontantValidator',
              'layer': 'domainValidation',
              'targetObjectId': 'obj_devis',
              'moduleId': 'mod_devis',
              'cases': <Object?>[
                <String, Object?>{
                  'id': 'tc_ia_1',
                  'code': 'TC-001',
                  'order': 1,
                  'title': 'Accepte un devis dont le montant HT est > 0',
                  'fixtureId': 'FIX-001',
                  'arrange': 'Charger FIX-001 (montantHt = 2450)',
                  'act': 'validator.validate(devis)',
                  'outcomeKind': 'allowsAction',
                  'assertExpected': 'retourne valide sans erreur',
                  'businessRuleIds': <String>['RG-001'],
                  'requirementIds': <String>['EXF-001'],
                  'screenIds': <String>['SCR-001'],
                },
              ],
            },
          ],
        },
        'specPatch': <String, Object?>{
          // Clé destructrice ignorée par contrat additive_safe : obj_devis est préservé.
          'removeBusinessObjectIds': <String>['obj_devis'],
          'businessObjects': <Object?>[
            <String, Object?>{
              'id': 'obj_devis',
              'name': 'Devis',
              'technicalName': 'Devis',
              'attributes': <Object?>[
                <String, Object?>{
                  'id': 'attr_acompte_pct',
                  'name': 'tauxAcomptePct',
                  'type': 'decimal',
                  'required': false,
                },
              ],
            },
            <String, Object?>{
              'id': 'obj_acompte',
              'name': 'Acompte client',
              'technicalName': 'AcompteClient',
              'attributes': <Object?>[
                <String, Object?>{
                  'id': 'attr_acompte_id',
                  'name': 'id',
                  'type': 'uuid',
                  'required': true,
                },
              ],
            },
          ],
          'businessRules': <Object?>[
            <String, Object?>{
              'id': 'rule_rg_015',
              'code': 'RG-015',
              'title': 'Acompte obligatoire au-delà de 5 000 EUR HT',
              'category': 'validation',
              'targetObjectIds': <String>['obj_devis'],
            },
          ],
        },
        'stageReadyToAdvance': true,
      });

      await tester.enterText(
        find.byKey(const ValueKey('qa-chat-input')),
        'Complète la feature BDD, la suite TDD et la règle d’acompte.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('qa-chat-send')));
      await tester.pumpAndSettle();

      expect(fakeAi.callCount, 2);
      expect(controller.project!.qaSpec.features, hasLength(1));
      expect(controller.project!.qaSpec.tddSuites, hasLength(1));
      final updatedDevis = controller.project!.findBusinessObject('obj_devis');
      expect(updatedDevis, isNotNull);
      expect(
        updatedDevis!.attributes.map((a) => a.name),
        containsAll(<String>['id', 'numero', 'montantHt', 'tauxAcomptePct']),
      );
      expect(controller.project!.findBusinessObject('obj_acompte'), isNotNull);
      expect(
        controller.project!.businessRules.map((r) => r.code),
        containsAll(<String>['RG-001', 'RG-015']),
      );
      expect(controller.canUndo, isTrue);

      // 4c. Navigation vers l'étape 4 (QaReviewExportView) et inspection de tous les onglets.
      await tester.tap(
        find.byKey(const ValueKey('qa-step-tile-qaReviewExport')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('qa-review-export-view')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('qa-coverage-summary-card')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.open_in_browser_rounded), findsNothing);
      expect(find.text('Navigateur'), findsNothing);

      // Onglet Prompt Agent TDD.
      final promptTab = find.text('Prompt Agent TDD');
      await tester.ensureVisible(promptTab);
      await tester.pumpAndSettle();
      await tester.tap(promptTab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('qa-review-copy-tdd-prompt')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('qa-review-open-tdd-prompt-viewer')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.open_in_browser_rounded), findsNothing);
      expect(find.text('Navigateur'), findsNothing);

      // Onglet Features .feature.
      final featuresTab = find.textContaining('Features .feature');
      await tester.ensureVisible(featuresTab);
      await tester.pumpAndSettle();
      await tester.tap(featuresTab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('qa-review-copy-features')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Validation conforme des devis artisans'),
        findsWidgets,
      );
      expect(find.byIcon(Icons.open_in_browser_rounded), findsNothing);
      expect(find.text('Navigateur'), findsNothing);

      // Onglet Fixtures JSON.
      final fixturesTab = find.textContaining('Fixtures JSON');
      await tester.ensureVisible(fixturesTab);
      await tester.pumpAndSettle();
      await tester.tap(fixturesTab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('qa-review-copy-fixtures')),
        findsOneWidget,
      );
      expect(find.textContaining('DEV-2026-100'), findsWidgets);
      expect(find.byIcon(Icons.open_in_browser_rounded), findsNothing);
      expect(find.text('Navigateur'), findsNothing);

      // Onglet Cahier BDD/TDD (.md) : aucun bouton HTML Navigateur.
      final qaMdTab = find.text('Cahier BDD/TDD (.md)');
      await tester.ensureVisible(qaMdTab);
      await tester.pumpAndSettle();
      await tester.tap(qaMdTab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('qa-review-copy-qa-md')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('qa-review-open-qa-md-viewer')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.open_in_browser_rounded), findsNothing);
      expect(find.text('Navigateur'), findsNothing);
    },
  );

  testWidgets(
    '5. Responsive : aucun dépassement RenderFlex à 360px sur QaWizardStepper et les 4 ateliers QA (+ QaStageAiChatPane à 280px)',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final memStore = _MemorySpecProjectStore();
      final controller = _createController(store: memStore);
      addTearDown(controller.dispose);

      final project = _buildSampleProject(
        currentSpecStage: SpecForgeStage.reviewExport,
        qaSpec: QaForgeSpec(
          currentStage: QaForgeStage.testFixtures,
          stageStates: <QaForgeStage, QaStageState>{
            QaForgeStage.testFixtures: QaStageState(
              stage: QaForgeStage.testFixtures,
              status: SpecStageStatus.inProgress,
              readyToAdvance: true,
              messages: [
                SpecChatMessage(
                  id: 'qa_msg_narrow_1',
                  isUser: false,
                  text: 'Les fixtures nominales et invalides sont prêtes.',
                ),
              ],
            ),
          },
          fixtures: [
            QaFixtureSpec(
              id: 'fix_narrow_1',
              code: 'FIX-001',
              name: 'Devis chantier nominal complet',
              kind: QaFixtureKind.nominal,
              businessObjectId: 'obj_devis',
              personaId: 'persona_chef',
              businessRuleIds: const ['RG-001'],
              payload: const <String, Object?>{
                'id': 'dev-narrow-1',
                'numero': 'DEV-2026-001',
                'montantHt': 1890.50,
              },
              expectedValid: true,
            ),
            QaFixtureSpec(
              id: 'fix_narrow_2',
              code: 'FIX-002',
              name: 'Devis montant négatif rejeté par RG-001',
              kind: QaFixtureKind.invalid,
              businessObjectId: 'obj_devis',
              personaId: 'persona_chef',
              businessRuleIds: const ['RG-001'],
              payload: const <String, Object?>{
                'id': 'dev-narrow-2',
                'numero': 'DEV-2026-002',
                'montantHt': -50.0,
              },
              expectedValid: false,
              expectedErrorHint:
                  'Le montant HT du devis doit être supérieur à 0.',
            ),
          ],
          features: [
            GherkinFeatureSpec(
              id: 'feat_narrow_1',
              code: 'FEAT-001',
              title: 'Validation mobile et terrain étroit des devis',
              moduleId: 'mod_devis',
              personaId: 'persona_chef',
              narrative: 'En tant que Chef de chantier\nJe veux valider un devis conforme\nAfin d’envoyer rapidement la proposition au client',
              tags: const ['@smoke', '@rg-001'],
              backgroundSteps: [
                GherkinStep(
                  id: 'bg_narrow_1',
                  keyword: GherkinStepKeyword.given,
                  text: 'le référentiel chantier est initialisé',
                ),
              ],
              scenarios: [
                GherkinScenarioSpec(
                  id: 'scn_narrow_outline',
                  code: 'SCN-001',
                  title: 'Contrôle paramétré du montant HT des devis',
                  isOutline: true,
                  tags: const ['@outline'],
                  requirementIds: const ['EXF-001'],
                  businessRuleIds: const ['RG-001'],
                  journeyIds: const ['JRN-001'],
                  screenIds: const ['SCR-001'],
                  fixtureIds: const ['FIX-001', 'FIX-002'],
                  steps: [
                    GherkinStep(
                      id: 'st_narrow_1',
                      keyword: GherkinStepKeyword.given,
                      text: 'un devis brouillon avec montant <montant_ht> EUR',
                      dataTable: const [
                        ['numero', 'montantHt'],
                        ['DEV-2026-001', '<montant_ht>'],
                      ],
                    ),
                    GherkinStep(
                      id: 'st_narrow_2',
                      keyword: GherkinStepKeyword.when,
                      text: 'l’utilisateur valide la proposition',
                    ),
                    GherkinStep(
                      id: 'st_narrow_3',
                      keyword: GherkinStepKeyword.then,
                      text: 'le résultat retourné est "<statut_attendu>"',
                      docString: '{"statut": "<statut_attendu>"}',
                    ),
                  ],
                  examples: GherkinExamplesTable(
                    headers: const ['montant_ht', 'statut_attendu'],
                    rows: const [
                      ['1890.50', 'valide'],
                      ['-50.00', 'rejete'],
                    ],
                  ),
                ),
              ],
            ),
          ],
          tddSuites: [
            TddTestSuiteSpec(
              id: 'tdd_narrow_1',
              code: 'TDD-001',
              name: 'Validation unitaire des montants et règles RG-001',
              layer: TddTargetLayer.domainValidation,
              targetObjectId: 'obj_devis',
              moduleId: 'mod_devis',
              cases: [
                TddTestCaseSpec(
                  id: 'tc_narrow_1',
                  code: 'TC-001',
                  order: 1,
                  title: 'Rejette un devis avec montant négatif',
                  fixtureId: 'FIX-002',
                  arrange: 'Charger la fixture invalide FIX-002',
                  act: 'devisValidator.validate(devis)',
                  outcomeKind: TddExpectedOutcomeKind.rejectsWithError,
                  assertExpected: 'Lève une erreur métier RG-001',
                  expectedErrorMessage:
                      'Le montant HT du devis doit être supérieur à 0.',
                  businessRuleIds: const ['RG-001'],
                  requirementIds: const ['EXF-001'],
                  screenIds: const ['SCR-001'],
                ),
              ],
            ),
          ],
          coherenceIssues: const [
            QaCoherenceIssue(
              id: 'qa_issue_narrow_1',
              severity: CoherenceSeverity.warning,
              stage: QaForgeStage.tddSuites,
              code: 'COH-QA-TDD-001',
              title: 'Cas nominal complémentaire recommandé',
              description: 'Ajoutez un cas positif dédié à la borne minimale.',
              suggestion: 'Créer TC-002 avec montantHt = 1.',
              source: 'ai',
            ),
          ],
        ),
      );
      memStore.seedProject(project);
      await controller.openProject(project.id);

      Future<void> pumpConstrained(
        Widget child, {
        double width = 360,
        double height = 820,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: width, height: height, child: child),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await pumpConstrained(
        Column(
          children: [
            QaWizardStepper(
              project: controller.project!,
              onBack: () {},
              onSwitchToSpecWizard: () {},
              onSwitchToUxWizard: () {},
              onSelectStage: (_) {},
            ),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
        width: 360,
      );
      await pumpConstrained(
        QaStageAiChatPane(
          controller: controller,
          chatWidthFraction: 0.3,
          onCycleChatSize: () {},
        ),
        width: 280,
      );
      await pumpConstrained(QaFixturesEditorView(controller: controller));
      await pumpConstrained(QaGherkinEditorView(controller: controller));

      // Vérifie également l'onglet Aperçu .feature à 360px.
      final narrowPreviewTab = find.byKey(
        const ValueKey('qa-feature-code-preview-tab'),
      );
      await tester.ensureVisible(narrowPreviewTab);
      await tester.pumpAndSettle();
      await tester.tap(narrowPreviewTab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await pumpConstrained(
        QaTddEditorView(
          controller: controller,
          onJumpToSpecStage: (_, {objectId}) {},
        ),
      );
      await pumpConstrained(QaReviewExportView(controller: controller));
      for (final tabLabel in <String>[
        'Prompt Agent TDD',
        'Cahier BDD/TDD (.md)',
      ]) {
        final tab = find.text(tabLabel);
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
