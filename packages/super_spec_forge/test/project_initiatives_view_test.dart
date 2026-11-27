import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
    if (systemInstructionOverride == PortfolioSlicingAiAgent.systemInstruction) {
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
                'definition':
                    'Certificat d’immatriculation associé à un véhicule du parc.',
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
          'Lexique métier — FEAT-02 · Réservations collaborateurs (AutoFleet)',
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
        _appBarText('Lexique métier — FEAT-01 · Parc véhicules (AutoFleet)'),
        findsOneWidget,
      );

      // 7b. Action rapide dans le chat pour rechercher un complément de lexique pour la feature active.
      final complementChip = find.byKey(
        const ValueKey('spec-chat-lexicon-complement-action'),
      );
      expect(complementChip, findsOneWidget);
      expect(find.text('Compléter le lexique (FEAT-01)'), findsOneWidget);
      await tester.tap(complementChip);
      await tester.pumpAndSettle();

      expect(fakeAi.receivedStages.last, SpecForgeStage.lexicon);
      expect(
        fakeAi.receivedPrompts.last,
        contains('FEAT-01 · Parc véhicules'),
      );
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
    },
  );
}
