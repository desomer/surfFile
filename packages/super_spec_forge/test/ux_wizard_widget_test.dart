import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/main.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemoryModelDictionaryStore extends ModelDictionaryStore {
  _MemoryModelDictionaryStore() : super(Directory('memory_ux_store'));

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
  _MemoryCompanyGlossaryStore() : super(Directory('memory_ux_store'));

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
  _MemoryDomainCatalogStore() : super(Directory('memory_ux_store'));

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
  _MemorySpecProjectStore() : super(Directory('memory_ux_store'));

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

class _QueuedUxAiTurn {
  _QueuedUxAiTurn({required this.payload, this.pauseAfterFirstChunk});

  final Map<String, Object?> payload;
  final Completer<void>? pauseAfterFirstChunk;
}

class _FakeUxSpecAiService implements SpecAiService {
  final List<String> receivedPrompts = [];
  final List<String?> receivedSystemInstructions = [];
  final List<_QueuedUxAiTurn> _queuedTurns = [];

  int get callCount => receivedPrompts.length;

  void enqueueResponse(
    Map<String, Object?> payload, {
    Completer<void>? pauseAfterFirstChunk,
  }) {
    _queuedTurns.add(
      _QueuedUxAiTurn(
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
        : _QueuedUxAiTurn(
            payload: <String, Object?>{
              'message': 'Réponse UX par défaut.',
              'askUser': null,
              'uxPatch': null,
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
    aiService: aiService ?? _FakeUxSpecAiService(),
  );
}

SpecForgeProject _buildSampleProject({
  SpecForgeStage currentSpecStage = SpecForgeStage.lexicon,
  UxForgeSpec? uxSpec,
  List<BusinessObjectSpec>? businessObjects,
  List<BusinessRuleSpec>? businessRules,
}) {
  final base = SpecForgeProject.fromIdea(
    id: 'proj_artisan_ux',
    name: 'Artisan Devis Pro',
    idea: 'Application Desktop de chiffrage, devis et suivi de chantiers BTP',
  );
  return base.copyWith(
    currentStage: currentSpecStage,
    vision: SpecVision(
      ideaSummary: 'Gestion intégrée des devis et chantiers artisans',
      personas: [
        SpecPersona(
          id: 'persona_chef',
          name: 'Chef de chantier',
          role: 'Conducteur de travaux',
          goals: const ['Chiffrer un devis en moins de 3 minutes'],
          painPoints: const ['Double saisie sur tableur'],
        ),
        SpecPersona(
          id: 'persona_compta',
          name: 'Comptable',
          role: 'Responsable facturation',
          goals: const ['Valider les acomptes et factures'],
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
        SpecModule(
          id: 'mod_chantiers',
          name: 'Suivi des chantiers',
          description: 'Planification et avancement terrain',
        ),
      ],
      functionalRequirements: [
        FunctionalRequirement(
          id: 'req_devis_001',
          code: 'EXF-001',
          title: 'Calcul automatique du total HT/TTC',
          moduleId: 'mod_devis',
          actorIds: const ['persona_chef'],
        ),
      ],
      useCases: [
        UseCaseSpec(
          id: 'uc_creer_devis',
          title: 'Créer et envoyer un devis client',
          actorId: 'persona_chef',
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
            title: 'Montant de devis strictement positif',
            targetObjectIds: const ['obj_devis'],
            condition: 'montantTotal <= 0',
            effect: 'Refuser la validation du devis',
          ),
        ],
    uxSpec: uxSpec ?? UxForgeSpec.empty,
  );
}

void main() {
  testWidgets(
    '1. Navigation & Handoff : SpecLinksView (sans/avec projet) <-> ReviewExportView <-> UxWizardStepper',
    (WidgetTester tester) async {
      _configureDesktopViewport(tester);

      final memStore = _MemorySpecProjectStore();
      final controller = _createController(store: memStore);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      // 1a. Sans projet actif : la carte Wizard UX est affichée et déclenche un SnackBar.
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );
      final uxLinkCard = find.byKey(const ValueKey('spec-link-ux_wizard'));
      expect(uxLinkCard, findsOneWidget);
      expect(find.text(SpecLinksView.uxWizardLabel), findsOneWidget);

      await tester.tap(uxLinkCard);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Aucun projet actif — ouvrez ou créez un projet dans Projets',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-forge-ux-wizard-view')),
        findsNothing,
      );

      // 1b. Activation d'un projet positionné sur l'étape 6 (ReviewExportView, non validée).
      final seeded = _buildSampleProject(
        currentSpecStage: SpecForgeStage.reviewExport,
      );
      expect(
        seeded.stageStateFor(SpecForgeStage.reviewExport).status,
        isNot(SpecStageStatus.validated),
      );
      memStore.seedProject(seeded);
      await controller.openProject(seeded.id);
      await tester.pumpAndSettle();

      // Ouverture directe depuis la carte SpecLinksView avec projet actif.
      await tester.tap(find.byKey(const ValueKey('spec-link-ux_wizard')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-forge-ux-wizard-view')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ux-wizard-stepper')), findsOneWidget);

      // Retour au menu Spec puis ouverture de l'étape 6 du Wizard Métier.
      await tester.tap(find.byKey(const ValueKey('ux-subview-back-btn')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewExportView), findsOneWidget);

      // 1c. Clic sur « Poursuivre vers le Wizard UX » : valide l'étape 6 et bascule vers le Wizard UX.
      final continueToUxBtn = find.byKey(
        const ValueKey('spec-review-continue-to-ux-btn'),
      );
      expect(continueToUxBtn, findsOneWidget);
      expect(find.text('Poursuivre vers le Wizard UX'), findsOneWidget);

      await tester.tap(continueToUxBtn);
      await tester.pumpAndSettle();

      expect(
        controller.project!.stageStateFor(SpecForgeStage.reviewExport).status,
        SpecStageStatus.validated,
      );
      expect(
        find.byKey(const ValueKey('spec-forge-ux-wizard-view')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ux-wizard-stepper')), findsOneWidget);

      // 1d. Bascule rapide UX -> Wizard Métier -> retour Wizard UX.
      await tester.tap(
        find.byKey(const ValueKey('ux-switch-to-spec-wizard-btn')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-forge-ux-wizard-view')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('spec-switch-to-ux-wizard-btn')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('spec-switch-to-ux-wizard-btn')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-forge-ux-wizard-view')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ux-wizard-stepper')), findsOneWidget);
    },
  );

  testWidgets(
    '2. Étape 1 (UxJourneysEditorView) & Étape 2 (UxNavigationEditorView) : parcours, filtres personas, aperçu M3 live et routes depuis modules',
    (WidgetTester tester) async {
      _configureDesktopViewport(tester);

      final memStore = _MemorySpecProjectStore();
      final controller = _createController(store: memStore);
      addTearDown(controller.dispose);

      final project = _buildSampleProject(
        uxSpec: UxForgeSpec(
          currentStage: UxForgeStage.userJourneys,
          journeys: [
            UxJourneySpec(
              id: 'jrn_devis',
              code: 'JRN-001',
              name: 'Création rapide de devis',
              personaId: 'persona_chef',
              useCaseIds: const ['uc_creer_devis'],
              requirementIds: const ['EXF-001'],
              trigger: 'Appel client sur chantier',
              goal: 'Envoyer un devis signé immédiatement',
              steps: const [
                UxJourneyStep(
                  id: 'step_1',
                  order: 1,
                  title: 'Saisie des postes matériaux',
                  actorAction: 'Ajoute les lignes d’ouvrage',
                  systemResponse: 'Recalcule le montant HT/TTC en direct',
                ),
                UxJourneyStep(
                  id: 'step_2',
                  order: 2,
                  title: 'Émission PDF client',
                  actorAction: 'Clique sur Envoyer le devis',
                  systemResponse: 'Génère et archive le document A4',
                ),
              ],
            ),
            UxJourneySpec(
              id: 'jrn_facturation',
              code: 'JRN-002',
              name: 'Validation comptable des acomptes',
              personaId: 'persona_compta',
              steps: const [
                UxJourneyStep(
                  id: 'step_3',
                  order: 1,
                  title: 'Contrôle des règlements reçus',
                ),
              ],
            ),
          ],
        ),
      );
      memStore.seedProject(project);
      await controller.openProject(project.id);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-link-ux_wizard')));
      await tester.pumpAndSettle();

      // 2a. Étape 1 : parcours, étapes de timeline et filtrage par persona.
      expect(
        find.byKey(const ValueKey('ux-journeys-editor-view')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ux-journey-tile-jrn_devis')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ux-journey-tile-jrn_facturation')),
        findsOneWidget,
      );
      expect(find.text('Saisie des postes matériaux'), findsOneWidget);
      expect(find.text('Émission PDF client'), findsOneWidget);

      final comptableChip = find.widgetWithText(FilterChip, 'Comptable');
      expect(comptableChip, findsOneWidget);
      await tester.tap(comptableChip);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ux-journey-tile-jrn_devis')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ux-journey-tile-jrn_facturation')),
        findsOneWidget,
      );
      expect(find.text('Contrôle des règlements reçus'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Tous'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ux-journey-tile-jrn_devis')),
        findsOneWidget,
      );

      // 2b. Navigation vers l'étape 2 (Architecture & Navigation) via le stepper UX.
      await tester.tap(find.byKey(const ValueKey('ux-step-tile-iaNavigation')));
      await tester.pumpAndSettle();

      expect(
        controller.project!.uxSpec.currentStage,
        UxForgeStage.iaNavigation,
      );
      expect(
        controller.project!.uxSpec
            .stageStateFor(UxForgeStage.userJourneys)
            .status,
        SpecStageStatus.validated,
      );
      expect(
        find.byKey(const ValueKey('ux-navigation-editor-view')),
        findsOneWidget,
      );

      // 2c. Aperçu live Material 3 & bascule de luminosité Clair / Sombre.
      final previewCardFinder = find.byKey(
        const ValueKey('ux-live-theme-preview-card'),
      );
      final brightnessToggleFinder = find.byKey(
        const ValueKey('ux-preview-brightness-toggle'),
      );
      expect(previewCardFinder, findsOneWidget);
      expect(brightnessToggleFinder, findsOneWidget);

      final initialToggle = tester.widget<SegmentedButton<Brightness>>(
        brightnessToggleFinder,
      );
      expect(initialToggle.selected, equals(<Brightness>{Brightness.light}));
      final lightPreviewDecoration =
          tester.widget<Container>(previewCardFinder).decoration!
              as BoxDecoration;
      final lightBgColor = lightPreviewDecoration.color;

      await tester.ensureVisible(brightnessToggleFinder);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: brightnessToggleFinder,
          matching: find.text('Sombre'),
        ),
      );
      await tester.pumpAndSettle();

      final updatedToggle = tester.widget<SegmentedButton<Brightness>>(
        brightnessToggleFinder,
      );
      expect(updatedToggle.selected, equals(<Brightness>{Brightness.dark}));
      final darkPreviewDecoration =
          tester.widget<Container>(previewCardFinder).decoration!
              as BoxDecoration;
      expect(darkPreviewDecoration.color, isNot(equals(lightBgColor)));

      // 2d. Génération automatique des routes depuis les modules du cahier des charges.
      expect(controller.project!.uxSpec.navigation.routes, isEmpty);
      final seedRoutesBtn = find.byKey(
        const ValueKey('ux-seed-routes-from-modules-btn'),
      );
      await tester.ensureVisible(seedRoutesBtn);
      await tester.pumpAndSettle();
      await tester.tap(seedRoutesBtn);
      await tester.pumpAndSettle();

      final seededRoutes = controller.project!.uxSpec.navigation.routes;
      expect(seededRoutes, hasLength(3));
      expect(
        seededRoutes.map((r) => r.path),
        containsAll(<String>[
          '/',
          '/gestion-des-devis',
          '/suivi-des-chantiers',
        ]),
      );
      expect(
        controller.project!.uxSpec.navigation.homeRouteId,
        equals('route_accueil'),
      );
      expect(
        find.byKey(const ValueKey('ux-route-tile-route_accueil')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '3. Étape 3 (UxScreensEditorView) : génération depuis routes, blueprint interactif des zones, enrichissement métier additif avec Undo et saut Wizard Métier',
    (WidgetTester tester) async {
      _configureDesktopViewport(tester);

      final memStore = _MemorySpecProjectStore();
      final controller = _createController(store: memStore);
      addTearDown(controller.dispose);

      final project = _buildSampleProject(
        uxSpec: UxForgeSpec(
          currentStage: UxForgeStage.iaNavigation,
          navigation: UxNavigationSpec(
            homeRouteId: 'route_accueil',
            routes: [
              UxRouteNode(
                id: 'route_accueil',
                path: '/',
                title: 'Accueil',
                iconName: 'home_outlined',
              ),
              UxRouteNode(
                id: 'route_devis',
                path: '/devis',
                title: 'Gestion des devis',
                moduleId: 'mod_devis',
                allowedPersonaIds: const ['persona_chef'],
              ),
            ],
          ),
        ),
      );
      memStore.seedProject(project);
      await controller.openProject(project.id);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-link-ux_wizard')));
      await tester.pumpAndSettle();

      // Navigation vers l'étape 3 (Écrans, Zones & Interactions).
      await tester.tap(
        find.byKey(const ValueKey('ux-step-tile-screenBlueprints')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ux-screens-editor-view')),
        findsOneWidget,
      );
      expect(controller.project!.uxSpec.screens, isEmpty);

      // 3a. Génération des écrans depuis les routes de navigation.
      final seedScreensBtn = find.byKey(
        const ValueKey('ux-seed-screens-from-routes-btn'),
      );
      expect(seedScreensBtn, findsOneWidget);
      await tester.tap(seedScreensBtn);
      await tester.pumpAndSettle();

      expect(controller.project!.uxSpec.screens, hasLength(2));
      expect(
        find.byKey(const ValueKey('ux-screen-zone-blueprint')),
        findsOneWidget,
      );

      // 3b. Clic sur les zones Ouest et Centre du blueprint spatial interactif.
      final westZone = find.byKey(const ValueKey('ux-blueprint-zone-west'));
      final centerZone = find.byKey(const ValueKey('ux-blueprint-zone-center'));
      expect(westZone, findsOneWidget);
      expect(centerZone, findsOneWidget);

      await tester.ensureVisible(westZone);
      await tester.pumpAndSettle();
      await tester.tap(westZone);
      await tester.pumpAndSettle();

      expect(controller.focusedScreenZone, UxLayoutZoneName.west);
      expect(find.text('Inspecteur — Zone Ouest (west)'), findsOneWidget);

      await tester.tap(centerZone);
      await tester.pumpAndSettle();

      expect(controller.focusedScreenZone, UxLayoutZoneName.center);
      expect(find.text('Inspecteur — Zone Centre (center)'), findsOneWidget);

      // 3c. Enrichissement métier additif depuis l'UX : + Objet métier puis + Attribut métier, avec Undo.
      expect(controller.project!.businessObjects, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('ux-quick-add-object-btn')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('ux-quick-object-name-field')),
        'Chantier client',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ux-quick-object-save-btn')));
      await tester.pumpAndSettle();

      expect(controller.project!.businessObjects, hasLength(2));
      expect(
        controller.project!.businessObjects.map((o) => o.technicalName),
        containsAll(<String>['Devis', 'ChantierClient']),
      );
      expect(controller.canUndo, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('ux-quick-add-attribute-btn')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('ux-quick-attr-name-field')),
        'montantTotalHt',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ux-quick-attr-save-btn')));
      await tester.pumpAndSettle();

      final enrichedDevis = controller.project!.findBusinessObject(
        'obj_devis',
      )!;
      expect(
        enrichedDevis.attributes.map((a) => a.name),
        containsAll(<String>['id', 'numero', 'montantTotalHt']),
      );

      // Vérification de l'annulation (Undo) et du rétablissement (Redo).
      await tester.tap(find.byTooltip('Annuler (Undo)'));
      await tester.pumpAndSettle();
      expect(
        controller.project!
            .findBusinessObject('obj_devis')!
            .attributes
            .map((a) => a.name),
        isNot(contains('montantTotalHt')),
      );
      expect(
        controller.project!.businessObjects.map((o) => o.technicalName),
        containsAll(<String>['Devis', 'ChantierClient']),
      );

      await tester.tap(find.byTooltip('Rétablir (Redo)'));
      await tester.pumpAndSettle();
      expect(
        controller.project!
            .findBusinessObject('obj_devis')!
            .attributes
            .map((a) => a.name),
        contains('montantTotalHt'),
      );

      // 3d. Saut contextuel vers l'étape Objets métiers du Wizard Métier.
      await tester.tap(
        find.byKey(const ValueKey('ux-jump-to-business-objects-btn')),
      );
      await tester.pumpAndSettle();

      expect(controller.project!.currentStage, SpecForgeStage.businessObjects);
      expect(find.byType(BusinessObjectsEditorView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-forge-ux-wizard-view')),
        findsNothing,
      );
    },
  );

  testWidgets(
    '4. Étape 4 (UxReviewExportView) & Chat IA UX en streaming avec uxPatch et specPatch additif',
    (WidgetTester tester) async {
      _configureDesktopViewport(tester);

      final memStore = _MemorySpecProjectStore();
      final fakeAi = _FakeUxSpecAiService();
      final controller = _createController(store: memStore, aiService: fakeAi);
      addTearDown(controller.dispose);

      final project = _buildSampleProject(
        uxSpec: UxForgeSpec(
          currentStage: UxForgeStage.userJourneys,
          navigation: UxNavigationSpec(
            homeRouteId: 'route_accueil',
            routes: [
              UxRouteNode(
                id: 'route_accueil',
                path: '/',
                title: 'Pilotage',
                iconName: 'dashboard_outlined',
              ),
              UxRouteNode(
                id: 'route_devis',
                path: '/devis',
                title: 'Devis clients',
                moduleId: 'mod_devis',
              ),
            ],
          ),
          screens: [
            UxScreenSpec(
              id: 'scr_pilotage',
              code: 'SCR-001',
              name: 'Tableau de bord Pilotage',
              routeId: 'route_accueil',
              pattern: UxScreenPattern.dashboard,
              primaryObjectId: 'obj_devis',
              zones: UxScreenSpec.defaultZonesForPattern(
                UxScreenPattern.dashboard,
              ),
            ),
          ],
        ),
      );
      memStore.seedProject(project);
      await controller.openProject(project.id);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-link-ux_wizard')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ux-stage-ai-chat-pane')),
        findsOneWidget,
      );
      expect(fakeAi.callCount, 0);

      // 4a. Kickoff en streaming SSE sur UxStageAiChatPane.
      final streamGate = Completer<void>();
      fakeAi.enqueueResponse(<String, Object?>{
        'message': 'J’ai structuré le parcours principal du chef de chantier.',
        'askUser': null,
        'uxPatch': <String, Object?>{
          'journeys': <Object?>[
            <String, Object?>{
              'id': 'jrn_ia_chef',
              'code': 'JRN-001',
              'name': 'Chiffrage express terrain',
              'personaId': 'persona_chef',
              'useCaseIds': <String>['uc_creer_devis'],
              'requirementIds': <String>['EXF-001'],
              'steps': <Object?>[
                <String, Object?>{
                  'id': 'step_ia_1',
                  'order': 1,
                  'title': 'Sélection client et lignes de devis',
                  'targetRouteId': 'route_devis',
                },
              ],
            },
          ],
        },
        'specPatch': null,
        'stageSummary': 'Parcours chef de chantier initialisé.',
        'stageReadyToAdvance': true,
      }, pauseAfterFirstChunk: streamGate);

      final kickoffBtn = find.byKey(const ValueKey('ux-stage-kickoff-btn'));
      expect(kickoffBtn, findsOneWidget);
      await tester.tap(kickoffBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      // Pendant le flux SSE : la bulle de streaming UX et le bouton d'arrêt sont visibles.
      expect(controller.isSendingUx, isTrue);
      expect(find.byType(SpecStreamingBubble), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ux-chat-stop-streaming')),
        findsOneWidget,
      );

      streamGate.complete();
      await tester.pumpAndSettle();

      expect(controller.isSendingUx, isFalse);
      expect(fakeAi.callCount, 1);
      expect(controller.project!.uxSpec.journeys, hasLength(1));
      expect(
        controller.project!.uxSpec.journeys.first.name,
        'Chiffrage express terrain',
      );
      expect(
        find.byKey(const ValueKey('ux-stage-ready-advance-btn')),
        findsOneWidget,
      );

      // 4b. Message utilisateur libre retournant conjointement uxPatch + specPatch additif.
      fakeAi.enqueueResponse(<String, Object?>{
        'message': 'Écran Devis, charte Émeraude et attributs métiers complémentaires ajoutés.',
        'askUser': null,
        'uxPatch': <String, Object?>{
          'navigation': <String, Object?>{
            'visualTheme': <String, Object?>{
              'accentHex': '#0D9488',
              'fontFamily': 'Plus Jakarta Sans',
            },
          },
          'screens': <Object?>[
            <String, Object?>{
              'id': 'scr_devis_ia',
              'code': 'SCR-002',
              'name': 'Atelier Devis Clients',
              'routeId': 'route_devis',
              'pattern': 'masterDetail',
              'primaryObjectId': 'obj_devis',
            },
          ],
        },
        'specPatch': <String, Object?>{
          // Clé destructrice ignorée par contrat additif UX : obj_devis ne doit pas disparaître.
          'removeBusinessObjectIds': <String>['obj_devis'],
          'businessObjects': <Object?>[
            <String, Object?>{
              'id': 'obj_devis',
              'name': 'Devis',
              'technicalName': 'Devis',
              'attributes': <Object?>[
                <String, Object?>{
                  'id': 'attr_signature_client',
                  'name': 'signatureClient',
                  'type': 'bool',
                  'required': false,
                  'description': 'Statut de signature électronique client',
                },
              ],
            },
            <String, Object?>{
              'id': 'obj_relance',
              'name': 'Relance client',
              'technicalName': 'RelanceClient',
              'attributes': <Object?>[
                <String, Object?>{
                  'id': 'attr_relance_id',
                  'name': 'id',
                  'type': 'uuid',
                  'required': true,
                },
              ],
            },
          ],
          'businessRules': <Object?>[
            <String, Object?>{
              'id': 'rule_rg_010',
              'code': 'RG-010',
              'title': 'Blocage modification après signature client',
              'category': 'permission',
              'targetObjectIds': <String>['obj_devis'],
            },
          ],
        },
        'stageReadyToAdvance': true,
      });

      await tester.enterText(
        find.byKey(const ValueKey('ux-chat-input')),
        'Ajoute l’écran des devis, le suivi de signature client et le thème Teal.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ux-chat-send')));
      await tester.pumpAndSettle();

      expect(fakeAi.callCount, 2);
      expect(controller.project!.uxSpec.screens, hasLength(2));
      expect(
        controller.project!.uxSpec.navigation.visualTheme.accentHex,
        '#0D9488',
      );
      // Vérification de l'enrichissement strictement additif du modèle métier.
      final updatedDevis = controller.project!.findBusinessObject('obj_devis');
      expect(updatedDevis, isNotNull);
      expect(
        updatedDevis!.attributes.map((a) => a.name),
        containsAll(<String>['id', 'numero', 'signatureClient']),
      );
      expect(controller.project!.findBusinessObject('obj_relance'), isNotNull);
      expect(
        controller.project!.businessRules.map((r) => r.code),
        containsAll(<String>['RG-001', 'RG-010']),
      );
      expect(controller.canUndo, isTrue);

      // 4c. Navigation vers l'étape 4 (UxReviewExportView) et vérification des onglets.
      await tester.tap(
        find.byKey(const ValueKey('ux-step-tile-uxReviewExport')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ux-review-export-view')),
        findsOneWidget,
      );
      // Onglet 1 (Cohérence UX) affiché par défaut : le persona Comptable n'a pas encore de parcours.
      expect(find.textContaining('Cohérence UX'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'ux-coherence-issue-ux_jrn_uncovered_persona_persona_compta',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('COH-UX-JRN-001'), findsOneWidget);

      // Onglet Prompt SuperDesigner.
      final promptTab = find.text('Prompt SuperDesigner');
      await tester.ensureVisible(promptTab);
      await tester.pumpAndSettle();
      await tester.tap(promptTab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ux-review-copy-sd-prompt')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Prompt Vibe Chat SuperDesigner'),
        findsWidgets,
      );

      // Onglet JSON Schema & Repositories.
      final reposTab = find.textContaining('JSON Schema & Repositories');
      await tester.ensureVisible(reposTab);
      await tester.pumpAndSettle();
      await tester.tap(reposTab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ux-review-copy-repos-bundle')),
        findsOneWidget,
      );

      // Onglet Spécification UX (.md) : aucun bouton d'export HTML Navigateur.
      final uxMdTab = find.text('Spécification UX (.md)');
      await tester.ensureVisible(uxMdTab);
      await tester.pumpAndSettle();
      await tester.tap(uxMdTab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ux-review-copy-ux-md')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ux-review-open-ux-md-browser')),
        findsNothing,
      );

      // Onglet Charte DESIGN.md.
      final designMdTab = find.text('Charte DESIGN.md');
      await tester.ensureVisible(designMdTab);
      await tester.pumpAndSettle();
      await tester.tap(designMdTab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ux-review-copy-design-md')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ux-review-open-design-md-viewer')),
        findsOneWidget,
      );
      expect(find.textContaining('#0D9488'), findsWidgets);

      // Onglet 4 : Aperçu SuperDesigner.
      final superDesignerTab = find.text('Aperçu SuperDesigner');
      await tester.ensureVisible(superDesignerTab);
      await tester.pumpAndSettle();
      await tester.tap(superDesignerTab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ux-super-designer-summary-card')),
        findsOneWidget,
      );
      expect(
        find.text('Synthèse de l’apparence initiale SuperDesigner'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ux-super-designer-json-card')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '5. Responsive : aucun dépassement RenderFlex à 360px sur ReviewExportView et les 4 ateliers UX (+ UxStageAiChatPane à 280px)',
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
        uxSpec: UxForgeSpec(
          currentStage: UxForgeStage.userJourneys,
          stageStates: <UxForgeStage, UxStageState>{
            UxForgeStage.userJourneys: UxStageState(
              stage: UxForgeStage.userJourneys,
              status: SpecStageStatus.inProgress,
              readyToAdvance: true,
              messages: [
                SpecChatMessage(
                  id: 'msg_narrow_1',
                  isUser: false,
                  text: 'Parcours prêt.',
                ),
              ],
            ),
          },
          journeys: [
            UxJourneySpec(
              id: 'jrn_narrow',
              code: 'JRN-001',
              name: 'Parcours mobile et terrain étroit',
              personaId: 'persona_chef',
              trigger: 'Notification urgente chantier',
              goal: 'Valider le devis sans défilement horizontal',
              steps: const [
                UxJourneyStep(
                  id: 'step_narrow_1',
                  order: 1,
                  title: 'Ouverture rapide fiche client',
                  actorAction: 'Sélectionne le chantier actif',
                  systemResponse: 'Charge les lignes et totaux',
                  targetRouteId: 'route_devis',
                  branchCondition: 'Plafond dépassé',
                  painPointResolved: 'Double saisie sur tableur',
                ),
              ],
            ),
          ],
          navigation: UxNavigationSpec(
            homeRouteId: 'route_devis',
            routes: [
              UxRouteNode(
                id: 'route_devis',
                path: '/gestion-des-devis',
                title: 'Gestion complète des devis artisans',
                moduleId: 'mod_devis',
                allowedPersonaIds: const ['persona_chef'],
                permissionRuleIds: const ['RG-001'],
              ),
            ],
          ),
          screens: [
            UxScreenSpec(
              id: 'scr_narrow',
              code: 'SCR-001',
              name: 'Atelier Devis Compact',
              routeId: 'route_devis',
              pattern: UxScreenPattern.masterDetail,
              primaryObjectId: 'obj_devis',
              zones: UxScreenSpec.defaultZonesForPattern(
                UxScreenPattern.masterDetail,
              ),
              actions: [
                UxScreenAction(
                  id: 'act_narrow_1',
                  label: 'Valider et transmettre le devis client',
                  hierarchy: UxActionHierarchy.primary,
                  targetRouteId: 'route_devis',
                  businessRuleIds: const ['RG-001'],
                ),
              ],
            ),
          ],
        ),
      );
      memStore.seedProject(project);
      await controller.openProject(project.id);

      Future<void> pumpConstrained(Widget child, {double width = 360}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: width, height: 820, child: child),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await pumpConstrained(
        ReviewExportView(controller: controller, onContinueToUxWizard: () {}),
      );
      await pumpConstrained(
        UxStageAiChatPane(
          controller: controller,
          chatWidthFraction: 0.3,
          onCycleChatSize: () {},
        ),
        width: 280,
      );
      await pumpConstrained(UxJourneysEditorView(controller: controller));
      await pumpConstrained(UxNavigationEditorView(controller: controller));
      await pumpConstrained(
        UxScreensEditorView(
          controller: controller,
          onJumpToSpecStage: (_, {objectId}) {},
        ),
      );
      await pumpConstrained(UxReviewExportView(controller: controller));
    },
  );
}
