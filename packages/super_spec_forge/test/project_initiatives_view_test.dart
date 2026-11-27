import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/main.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_portfolio_store'));

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
  Future<List<SpecProjectSummary>> listProjects() async => [
    for (final p in _projects.values)
      SpecProjectSummary(
        id: p.id,
        name: p.name,
        initialIdea: p.initialIdea,
        currentStage: p.currentStage,
        updatedAt: p.updatedAt,
        objectCount: p.allFeatures.fold<int>(
          0,
          (s, f) => s + f.businessObjects.length,
        ),
        ruleCount: p.allFeatures.fold<int>(
          0,
          (s, f) => s + f.businessRules.length,
        ),
        initiativeCount: p.initiatives.length,
        specFeatureCount: p.totalFeatureCount,
        activeFeatureName: p.activeFeature.name,
      ),
  ];

  @override
  Future<String?> getLastActiveProjectId() async => _lastActiveId;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {
    _lastActiveId = projectId;
  }
}

class _MemoryGlossaryStore extends CompanyGlossaryStore {
  _MemoryGlossaryStore() : super(Directory('memory_portfolio_store'));

  @override
  Future<CompanyGlossary> loadGlossary() async => CompanyGlossary.empty;

  @override
  Future<void> saveGlossary(CompanyGlossary glossary) async {}

  @override
  Future<List<SpecChatMessage>> loadChatMessages() async => const [];

  @override
  Future<void> saveChatMessages(List<SpecChatMessage> messages) async {}
}

class _MemoryDictStore extends ModelDictionaryStore {
  _MemoryDictStore() : super(Directory('memory_portfolio_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemoryDomainStore extends DomainCatalogStore {
  _MemoryDomainStore([DomainCatalog? initial])
    : _catalog = initial ?? DomainCatalog.empty,
      super(Directory('memory_portfolio_store'));

  DomainCatalog _catalog;

  @override
  Future<DomainCatalog> load() async => _catalog;

  @override
  Future<void> save(DomainCatalog catalog) async {
    catalog.validate();
    _catalog = catalog;
  }
}

class _MemoryRateCardStore extends EnterpriseRateCardStore {
  _MemoryRateCardStore() : super(Directory('memory_portfolio_store'));

  @override
  Future<EnterpriseRateCard> load() async => EnterpriseRateCard.defaults;

  @override
  Future<void> save(EnterpriseRateCard card) async {}
}

class _FakePortfolioAiService implements SpecAiService {
  final List<String> receivedPrompts = <String>[];
  final List<SpecForgeStage> receivedStages = <SpecForgeStage>[];

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
    receivedStages.add(stage);
    receivedPrompts.add(prompt);
    final Map<String, Object?> payload;
    if (systemInstructionOverride ==
        PortfolioSlicingAiAgent.systemInstruction) {
      payload = <String, Object?>{
        'message':
            'Voici un découpage en 2 initiatives et 3 features verticales.',
        'askUser': null,
        'specPatch': <String, Object?>{
          'replaceDefaultPlaceholder': true,
          'activeFeatureId': 'feat_reservations',
          'initiatives': [
            {
              'id': 'init_flotte',
              'code': 'INIT-01',
              'name': 'Socle Flotte & Réservations',
              'priority': 'must',
              'features': [
                {
                  'id': 'feat_parc',
                  'code': 'FEAT-01',
                  'name': 'Parc véhicules',
                  'description': 'Inventaire et cartes grises.',
                  'targetRelease': 'MVP',
                  'priority': 'must',
                },
                {
                  'id': 'feat_reservations',
                  'code': 'FEAT-02',
                  'name': 'Réservations collaborateurs',
                  'description': 'Prêt de véhicule et check-in/out.',
                  'targetRelease': 'MVP',
                  'priority': 'must',
                },
              ],
            },
            {
              'id': 'init_finances',
              'code': 'INIT-02',
              'name': 'Refacturation analytique',
              'priority': 'should',
              'features': [
                {
                  'id': 'feat_refact',
                  'code': 'FEAT-03',
                  'name': 'Ventilation par centre de coût',
                  'targetRelease': 'Lot 2',
                  'priority': 'should',
                },
              ],
            },
          ],
        },
      };
    } else {
      payload = <String, Object?>{
        'message': 'Complément de lexique ajouté pour la feature active.',
        'askUser': null,
        'specPatch': <String, Object?>{
          'lexicon': <String, Object?>{
            'terms': [
              {
                'id': 'term_carte_grise',
                'term': 'Carte grise',
                'definition': 'Certificat d’immatriculation associé à un véhicule du parc.',
                'domain': 'Parc véhicules',
              },
            ],
          },
        },
      };
    }
    final encoded = jsonEncode(payload);
    yield GeminiStreamEvent(
      deltaText: encoded,
      accumulatedText: encoded,
      isDone: true,
      usedContextCache: false,
    );
  }
}

Finder _appBarText(String title) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(title));

void main() {
  testWidgets(
    'Parcours complet : Menu Spec -> Projets -> Initiatives & Features (découpage IA + CRUD) -> ouverture des 4 Wizards -> Retour hiérarchique & sélecteur AppBar',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeAi = _FakePortfolioAiService();
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: fakeAi,
        initialQuestioningLevel: VibeQuestioningLevel.none,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      // 1. La carte « Initiatives & Features » est présente dans le menu Spec juste après « Projets ».
      expect(
        find.byKey(const ValueKey('spec-link-initiatives')),
        findsOneWidget,
      );
      expect(find.text(SpecLinksView.initiativesLabel), findsOneWidget);

      // 2. Création d'un projet depuis Projets via « Créer & découper en Initiatives / Features ».
      await tester.tap(find.byKey(const ValueKey('spec-link-projects')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'AutoFleet');
      await tester.enterText(
        find.byType(TextField).at(1),
        'Suivi d’une flotte automobile et réservations collaborateurs',
      );
      await tester.pump();

      final openInitiativesBtn = find.byKey(
        const ValueKey('idea-launcher-open-initiatives-btn'),
      );
      await tester.ensureVisible(openInitiativesBtn);
      await tester.pumpAndSettle();
      await tester.tap(openInitiativesBtn);
      await tester.pumpAndSettle();

      // 3. On arrive sur la page intermédiaire ProjectInitiativesView.
      expect(
        find.byKey(const ValueKey('spec-project-initiatives-view')),
        findsOneWidget,
      );
      expect(
        _appBarText('Spec › AutoFleet › Initiatives & Features'),
        findsOneWidget,
      );

      // 4. Lancement du découpage produit via le Chat IA.
      await tester.tap(
        find.byKey(const ValueKey('portfolio-chat-kickoff-btn')),
      );
      await tester.pumpAndSettle();

      expect(controller.project!.initiatives.length, 2);
      expect(controller.project!.totalFeatureCount, 3);
      expect(controller.project!.activeFeatureId, 'feat_reservations');
      expect(
        find.byKey(const ValueKey('portfolio-feature-tile-feat_reservations')),
        findsOneWidget,
      );

      // 5. Ajout manuel d'une feature via le bouton « + Feature ».
      await tester.tap(find.byKey(const ValueKey('portfolio-add-feature-btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('portfolio-feature-name-field')),
        'Alertes contrôle technique',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('portfolio-feature-save-btn')),
      );
      await tester.pumpAndSettle();

      expect(controller.project!.totalFeatureCount, 4);
      expect(
        controller.project!.activeFeature.name,
        'Alertes contrôle technique',
      );

      // Resélectionner FEAT-02 dans l'arbre.
      await tester.tap(
        find.byKey(const ValueKey('portfolio-feature-tile-feat_reservations')),
      );
      await tester.pumpAndSettle();
      expect(controller.project!.activeFeatureId, 'feat_reservations');

      // 6. Ouverture du Wizard Spec depuis la carte de la feature active.
      final specCard = find.byKey(const ValueKey('portfolio-open-wizard-spec'));
      await tester.ensureVisible(specCard);
      await tester.pumpAndSettle();
      await tester.tap(specCard);
      await tester.pumpAndSettle();

      expect(
        _appBarText(
          'Cadrage & Acteurs — FEAT-02 · Réservations collaborateurs (AutoFleet)',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-appbar-feature-switcher')),
        findsOneWidget,
      );

      // 7. Changement rapide de feature active directement depuis le menu de l'AppBar.
      await tester.tap(
        find.byKey(const ValueKey('spec-appbar-feature-switcher')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-appbar-feature-item-feat_parc')),
      );
      await tester.pumpAndSettle();

      expect(controller.project!.activeFeatureId, 'feat_parc');
      expect(
        _appBarText('Cadrage & Acteurs — FEAT-01 · Parc véhicules (AutoFleet)'),
        findsOneWidget,
      );

      // 7b. Passage à l'étape 2 (Lexique métier) et action rapide dans le chat pour rechercher un complément de lexique.
      await controller.goToStage(SpecForgeStage.lexicon);
      await tester.pumpAndSettle();
      expect(
        _appBarText('Lexique métier — FEAT-01 · Parc véhicules (AutoFleet)'),
        findsOneWidget,
      );
      final complementChip = find.byKey(
        const ValueKey('spec-chat-lexicon-complement-action'),
      );
      expect(complementChip, findsOneWidget);
      expect(find.text('Compléter le lexique (FEAT-01)'), findsOneWidget);
      await tester.tap(complementChip);
      await tester.pumpAndSettle();

      expect(fakeAi.receivedStages.last, SpecForgeStage.lexicon);
      expect(fakeAi.receivedPrompts.last, contains('FEAT-01 · Parc véhicules'));
      expect(
        controller.project!.lexicon.terms.any((t) => t.term == 'Carte grise'),
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('spec-chat-lexicon-audit-action')),
        findsOneWidget,
      );

      // 8. Le bouton Retour de l'AppBar ramène à la page intermédiaire Initiatives & Features.
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-project-initiatives-view')),
        findsOneWidget,
      );

      // 8b. Le chip « Lexique partagé » ouvre le référentiel transverse de niveau Projet hors stepper,
      // sans modifier l'étape active de la feature, et Retour ramène aux Initiatives & Features.
      await controller.goToStage(SpecForgeStage.businessObjects);
      await tester.pumpAndSettle();
      expect(controller.project!.currentStage, SpecForgeStage.businessObjects);

      await tester.tap(
        find.byKey(const ValueKey('portfolio-shared-lexicon-chip')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-project-lexicon-view')),
        findsOneWidget,
      );
      expect(find.byType(SpecWizardStepper), findsNothing);
      expect(
        _appBarText('Spec › AutoFleet › Lexique du projet'),
        findsOneWidget,
      );
      expect(controller.project!.currentStage, SpecForgeStage.businessObjects);

      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-project-initiatives-view')),
        findsOneWidget,
      );

      // 9. Ouverture du Wizard UX puis retour à Initiatives & Features.
      final uxCard = find.byKey(const ValueKey('portfolio-open-wizard-ux'));
      await tester.ensureVisible(uxCard);
      await tester.pumpAndSettle();
      await tester.tap(uxCard);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-ux-wizard-view')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-project-initiatives-view')),
        findsOneWidget,
      );

      // 10. Le panneau gauche des initiatives/features (à droite du chat IA) est redimensionnable.
      final treePaneFinder = find.byKey(const ValueKey('portfolio-tree-pane'));
      final treeHandleFinder = find.byKey(
        const ValueKey('portfolio-tree-split-handle'),
      );
      expect(treePaneFinder, findsOneWidget);
      expect(treeHandleFinder, findsOneWidget);

      final initialTreeWidth = tester.getSize(treePaneFinder).width;
      expect(initialTreeWidth, 370.0);

      await tester.drag(treeHandleFinder, const Offset(90, 0));
      await tester.pumpAndSettle();
      final widenedTreeWidth = tester.getSize(treePaneFinder).width;
      expect(widenedTreeWidth, greaterThan(initialTreeWidth));

      // Navigation vers un wizard puis retour : la taille du panneau gauche reste conservée.
      final specCardAfterResize = find.byKey(
        const ValueKey('portfolio-open-wizard-spec'),
      );
      await tester.ensureVisible(specCardAfterResize);
      await tester.pumpAndSettle();
      await tester.tap(specCardAfterResize);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(treePaneFinder).width, widenedTreeWidth);

      await tester.tap(treeHandleFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(treeHandleFinder);
      await tester.pumpAndSettle();
      expect(tester.getSize(treePaneFinder).width, initialTreeWidth);
    },
  );

  testWidgets(
    'ProjectInitiativesView : la largeur redimensionnée du panneau gauche persiste après redémarrage du contrôleur',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final store = _MemorySpecProjectStore();
      final project = SpecForgeProject.fromIdea(
        id: 'proj_persist',
        name: 'AutoFleet',
        idea: 'Gestion de flotte',
      );
      await store.saveProject(project);

      SpecForgeController makeController() => SpecForgeController(
        store: store,
        glossaryStore: _MemoryGlossaryStore(),
        modelDictionaryStore: _MemoryDictStore(),
        domainCatalogStore: _MemoryDomainStore(),
        enterpriseRateCardStore: _MemoryRateCardStore(),
        workspaceStore: SpecWorkspaceStore(),
        aiService: _FakePortfolioAiService(),
      );

      final controller1 = makeController();
      addTearDown(controller1.dispose);
      await controller1.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProjectInitiativesView(
              controller: controller1,
              onOpenWizard: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final treePaneFinder = find.byKey(const ValueKey('portfolio-tree-pane'));
      final treeHandleFinder = find.byKey(
        const ValueKey('portfolio-tree-split-handle'),
      );
      final initialWidth = tester.getSize(treePaneFinder).width;
      expect(initialWidth, 370.0);

      await tester.drag(treeHandleFinder, const Offset(90, 0));
      await tester.pumpAndSettle();
      final widenedWidth = tester.getSize(treePaneFinder).width;
      expect(widenedWidth, greaterThan(initialWidth));

      // Nouveau contrôleur rechargé depuis SharedPreferences.
      final controller2 = makeController();
      addTearDown(controller2.dispose);
      await controller2.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProjectInitiativesView(
              controller: controller2,
              onOpenWizard: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(treePaneFinder).width, widenedWidth);

      // Double-clic réinitialise et efface la préférence persistée.
      await tester.tap(treeHandleFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(treeHandleFinder);
      await tester.pumpAndSettle();
      expect(tester.getSize(treePaneFinder).width, initialWidth);

      final controller3 = makeController();
      addTearDown(controller3.dispose);
      await controller3.initialize();
      expect(
        controller3.panelWidth(SpecForgeController.portfolioTreePanelKey),
        isNull,
      );
    },
  );

  testWidgets(
    'Initiatives & Features : choix par feature des étapes optionnelles (Event Storming & Example Mapping) répercuté dans le Wizard Spec',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final store = _MemorySpecProjectStore();
      final now = DateTime.utc(2026, 6, 1);
      final seeded = SpecForgeProject(
        id: 'proj_stages_ui',
        name: 'FleetStages',
        initialIdea: 'Gestion de flotte',
        createdAt: now,
        updatedAt: now,
        initiatives: [
          SpecInitiative(
            id: 'init_1',
            code: 'INIT-01',
            name: 'Socle',
            features: [
              SpecFeatureSpec.create(
                id: 'feat_a',
                code: 'FEAT-01',
                name: 'Feature rapide',
                description: 'Sans Event Storming ni Example Mapping.',
              ),
              SpecFeatureSpec.create(
                id: 'feat_b',
                code: 'FEAT-02',
                name: 'Feature complète',
                description: 'Conserve toutes les étapes.',
              ),
            ],
          ),
        ],
        activeFeatureId: 'feat_a',
      );
      await store.saveProject(seeded);

      final controller = SpecForgeController(
        store: store,
        glossaryStore: _MemoryGlossaryStore(),
        modelDictionaryStore: _MemoryDictStore(),
        domainCatalogStore: _MemoryDomainStore(),
        enterpriseRateCardStore: _MemoryRateCardStore(),
        workspaceStore: SpecWorkspaceStore(),
        aiService: _FakePortfolioAiService(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(SuperSpecForgeApp(controller: controller));
      await tester.pumpAndSettle();

      // 1. Ouvre la page Initiatives & Features.
      await tester.tap(find.text(SpecLinksView.initiativesLabel));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('portfolio-feature-spec-stages-card')),
        findsOneWidget,
      );
      expect(
        find.text('Étapes de spécification (8/8 actives)'),
        findsOneWidget,
      );

      // 2. Désactive Event Storming puis Example Mapping sur feat_a.
      await tester.tap(
        find.byKey(
          const ValueKey('portfolio-feature-stage-toggle-eventStorming'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Étapes de spécification (7/8 actives)'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('portfolio-feature-stage-toggle-exampleMapping'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Étapes de spécification (6/8 actives)'),
        findsOneWidget,
      );
      expect(
        controller.project!.featureById('feat_a')!.disabledSpecStages,
        const {SpecForgeStage.eventStorming, SpecForgeStage.exampleMapping},
      );
      expect(
        controller.project!.featureById('feat_b')!.disabledSpecStages,
        isEmpty,
      );

      // 3. Crée une 3e feature via le dialogue en décochant Event Storming.
      await tester.tap(find.byKey(const ValueKey('portfolio-add-feature-btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('portfolio-feature-name-field')),
        'Feature sans ES',
      );
      await tester.pump();
      final esCheckbox = find.byKey(
        const ValueKey('portfolio-feature-dialog-stage-eventStorming'),
      );
      await tester.ensureVisible(esCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(esCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('portfolio-feature-save-btn')),
      );
      await tester.pumpAndSettle();
      expect(controller.project!.activeFeature.disabledSpecStages, const {
        SpecForgeStage.eventStorming,
      });
      expect(
        find.text('Étapes de spécification (7/8 actives)'),
        findsOneWidget,
      );

      // 4. Revient sur feat_a (6 étapes actives) et ouvre le Wizard Spec.
      await tester.tap(
        find.byKey(const ValueKey('portfolio-feature-tile-feat_a')),
      );
      await tester.pumpAndSettle();
      final openSpecCard = find.byKey(
        const ValueKey('portfolio-open-wizard-spec'),
      );
      await tester.ensureVisible(openSpecCard);
      await tester.pumpAndSettle();
      await tester.tap(openSpecCard);
      await tester.pumpAndSettle();

      // Le stepper masque Event Storming et Example Map.
      final stepper = find.byType(SpecWizardStepper);
      expect(stepper, findsOneWidget);
      expect(
        find.descendant(of: stepper, matching: find.text('Event Storming')),
        findsNothing,
      );
      expect(
        find.descendant(of: stepper, matching: find.text('Example Map')),
        findsNothing,
      );
      expect(
        find.descendant(of: stepper, matching: find.text('Objets métiers')),
        findsOneWidget,
      );

      // Avance depuis Cahier des charges -> saute directement à Objets métiers,
      // puis depuis Objets métiers -> saute directement à Règles de gestion.
      await controller.goToStage(SpecForgeStage.specifications);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider & Suivant'));
      await tester.pumpAndSettle();
      expect(controller.project!.currentStage, SpecForgeStage.businessObjects);

      await tester.tap(find.text('Valider & Suivant'));
      await tester.pumpAndSettle();
      expect(controller.project!.currentStage, SpecForgeStage.businessRules);

      // 5. Bascule sur feat_b (8 étapes actives) via le sélecteur AppBar :
      // Event Storming et Example Map réapparaissent dans le stepper.
      await tester.tap(
        find.byKey(const ValueKey('spec-appbar-feature-switcher')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-appbar-feature-item-feat_b')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: stepper, matching: find.text('Event Storming')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stepper, matching: find.text('Example Map')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ProjectInitiativesView : carte Objets métiers & Partage inter-features (extension additive puis alerte de divergence cassante sur feature Validée)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final now = DateTime.utc(2026, 8, 1);
      final feat1 = SpecFeatureSpec(
        id: 'feat_01',
        code: 'FEAT-01',
        name: 'Parc véhicules',
        status: SpecPortfolioStatus.validated,
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_vehicule_1',
            name: 'Véhicule',
            technicalName: 'Vehicule',
            aggregateRoot: true,
            attributes: [
              BusinessAttribute(
                id: 'attr_immat_1',
                name: 'immatriculation',
                type: BusinessAttributeType.string,
                required: true,
              ),
            ],
          ),
        ],
        businessRules: [
          BusinessRuleSpec(
            id: 'rule_immat',
            code: 'RG-001',
            title: 'Format plaque SIV',
            description: 'Toute immatriculation respecte le format SIV.',
            targetObjectIds: const ['obj_vehicule_1'],
            targetAttributes: const ['immatriculation'],
          ),
        ],
      );

      final feat2Additive = SpecFeatureSpec(
        id: 'feat_02',
        code: 'FEAT-02',
        name: 'Réservations collaborateurs',
        status: SpecPortfolioStatus.inProgress,
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_vehicule_2',
            name: 'Véhicule',
            technicalName: 'Vehicule',
            aggregateRoot: true,
            attributes: [
              BusinessAttribute(
                id: 'attr_immat_2',
                name: 'immatriculation',
                type: BusinessAttributeType.string,
                required: true,
              ),
              BusinessAttribute(
                id: 'attr_km_2',
                name: 'kilometrage',
                type: BusinessAttributeType.integer,
              ),
            ],
          ),
          BusinessObjectSpec(
            id: 'obj_resa_2',
            name: 'Réservation',
            technicalName: 'Reservation',
            aggregateRoot: true,
            attributes: [
              BusinessAttribute(
                id: 'attr_resa_id',
                name: 'id',
                type: BusinessAttributeType.uuid,
                required: true,
              ),
            ],
          ),
        ],
      );

      final store = _MemorySpecProjectStore();
      final initialProject = SpecForgeProject(
        id: 'proj_shared_objs',
        name: 'AutoFleet',
        initialIdea: 'Gestion de flotte et réservations',
        createdAt: now,
        updatedAt: now,
        initiatives: [
          SpecInitiative(
            id: 'init_fleet',
            code: 'INIT-01',
            name: 'Flotte',
            features: [feat1, feat2Additive],
          ),
        ],
        activeFeatureId: feat2Additive.id,
      );
      await store.saveProject(initialProject);

      final controller = SpecForgeController(
        store: store,
        glossaryStore: _MemoryGlossaryStore(),
        modelDictionaryStore: _MemoryDictStore(),
        domainCatalogStore: _MemoryDomainStore(),
        enterpriseRateCardStore: _MemoryRateCardStore(),
        workspaceStore: SpecWorkspaceStore(),
        aiService: _FakePortfolioAiService(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => ProjectInitiativesView(
                controller: controller,
                onOpenWizard: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. État additif sain : 1 partagé, 1 propre, Extension additive, aucune icône d'alerte.
      final sharedCard = find.byKey(
        const ValueKey('portfolio-feature-shared-objects-card'),
      );
      expect(sharedCard, findsOneWidget);
      expect(
        find.descendant(
          of: sharedCard,
          matching: find.text('1 partagé(s) inter-features'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sharedCard,
          matching: find.textContaining('1 propre(s)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sharedCard,
          matching: find.text('Extension additive'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sharedCard,
          matching: find.text('Partagé avec FEAT-01'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('portfolio-feature-obj-warning-${feat1.id}')),
        findsNothing,
      );
      expect(
        find.byKey(
          ValueKey('portfolio-feature-obj-warning-${feat2Additive.id}'),
        ),
        findsNothing,
      );
      expect(find.textContaining('alerte(s) Validée'), findsNothing);

      // 2. Changement de type cassant sur immatriculation dans FEAT-02 face à FEAT-01 Validée.
      final feat2Breaking = feat2Additive.copyWith(
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_vehicule_2',
            name: 'Véhicule',
            technicalName: 'Vehicule',
            aggregateRoot: true,
            attributes: [
              BusinessAttribute(
                id: 'attr_immat_2',
                name: 'immatriculation',
                type: BusinessAttributeType.integer,
                required: true,
              ),
            ],
          ),
          feat2Additive.businessObjects[1],
        ],
      );
      await controller.updateProject(
        controller.project!.copyWith(
          initiatives: [
            SpecInitiative(
              id: 'init_fleet',
              code: 'INIT-01',
              name: 'Flotte',
              features: [feat1, feat2Breaking],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          ValueKey('portfolio-feature-obj-warning-${feat2Breaking.id}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sharedCard,
          matching: find.text('1 alerte(s) Validée'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sharedCard,
          matching: find.text('⚠ Divergence cassante'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sharedCard,
          matching: find.text('1 impact(s) (1 RG)'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ContractEntryView : affiche toutes les contributingFeatures dans le badge d’origine Spec',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final now = DateTime.utc(2026, 8, 15);
      final vehiculeObj = BusinessObjectSpec(
        id: 'spec_obj_vehicule',
        name: 'Véhicule',
        technicalName: 'Vehicule',
        aggregateRoot: true,
        attributes: [
          BusinessAttribute(
            id: 'attr_immat',
            name: 'immatriculation',
            type: BusinessAttributeType.string,
            required: true,
          ),
        ],
      );

      var contracts = DomainContracts.parse('models:\n  Vehicule: model\n');
      final entry = contracts.groups.first.children.single;
      final specOrigin = SpecOriginBaseline(
        projectId: 'proj_autofleet',
        projectName: 'AutoFleet',
        featureId: 'feat_02',
        featureCode: 'FEAT-02',
        specObjectId: vehiculeObj.id,
        promotedAt: now,
        baseSpecObject: vehiculeObj,
        contributingFeatures: [
          SpecFeatureContribution(
            featureId: 'feat_01',
            featureCode: 'FEAT-01',
            featureName: 'Parc véhicules',
            promotedAt: now.subtract(const Duration(days: 2)),
          ),
          SpecFeatureContribution(
            featureId: 'feat_02',
            featureCode: 'FEAT-02',
            featureName: 'Réservations collaborateurs',
            promotedAt: now,
          ),
        ],
      );
      contracts = contracts
          .patch(contracts.source, {
            entry.id: ContractDetails(specOrigin: specOrigin),
          })
          .withModel(entry.id, object: vehiculeObj.copyWith(id: entry.id));

      final domain = FunctionalDomain(
        id: 'dom_fleet',
        domainCode: 'fleet',
        name: 'Flotte',
        contracts: contracts,
      );
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        glossaryStore: _MemoryGlossaryStore(),
        modelDictionaryStore: _MemoryDictStore(),
        domainCatalogStore: _MemoryDomainStore(
          DomainCatalog(domains: [domain]),
        ),
        enterpriseRateCardStore: _MemoryRateCardStore(),
        workspaceStore: SpecWorkspaceStore(),
        aiService: _FakePortfolioAiService(),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContractEntryView(
              controller: controller,
              domainId: domain.id,
              document: contracts,
              entry: contracts.entryById(entry.id)!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badgeFinder = find.byKey(
        ValueKey('contract-spec-origin-badge-${entry.id}'),
      );
      expect(badgeFinder, findsOneWidget);
      expect(
        find.descendant(
          of: badgeFinder,
          matching: find.textContaining('(FEAT-01, FEAT-02)'),
        ),
        findsOneWidget,
      );

      final tooltipFinder = find.ancestor(
        of: badgeFinder,
        matching: find.byType(Tooltip),
      );
      final tooltip = tester.widget<Tooltip>(tooltipFinder.first);
      expect(tooltip.message, contains('FEAT-01 · Parc véhicules'));
      expect(
        tooltip.message,
        contains('FEAT-02 · Réservations collaborateurs'),
      );
    },
  );
}
