import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/main.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

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

class _FakeSpecAiService implements SpecAiService {
  final List<SpecForgeStage> calledStages = [];
  int _visionTurn = 0;

  @override
  Future<void> warmUp(
    SpecForgeStage stage, {
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  }) async {}

  @override
  Stream<GeminiStreamEvent> streamTurn({
    required SpecForgeStage stage,
    required String prompt,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  }) async* {
    calledStages.add(stage);

    late final Map<String, Object?> payload;
    if (stage == SpecForgeStage.vision && _visionTurn == 0) {
      _visionTurn++;
      payload = {
        'message': 'Commençons par préciser les acteurs principaux.',
        'askUser': {
          'questions': [
            {
              'id': 'q_cible',
              'title': 'Quel est le public cible principal ?',
              'type': 'single',
              'options': ['PME', 'Grands Comptes'],
              'default': 'PME',
            },
          ],
        },
        'specPatch': null,
        'stageReadyToAdvance': false,
      };
    } else if (stage == SpecForgeStage.vision) {
      _visionTurn++;
      payload = {
        'message': 'Cadrage mis à jour avec le persona PME.',
        'askUser': null,
        'specPatch': {
          'vision': {
            'problemStatement': 'Suivi manuel des commandes PME',
            'valueProposition': 'Gestion automatisée',
            'objectives': ['Gagner 5h/semaine'],
            'personas': [
              {
                'id': 'p_dirigeant',
                'name': 'Dirigeant PME',
                'role': 'Valide les devis',
              },
            ],
          },
        },
        'stageSummary': 'Cible PME validée.',
        'stageReadyToAdvance': true,
      };
    } else {
      payload = {
        'message': 'Voici mes premières questions pour ${stage.title}.',
        'askUser': null,
        'specPatch': null,
        'stageReadyToAdvance': false,
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

void main() {
  testWidgets(
    'Wizard IA complet : idée -> questions VibeAskUserCard -> patch cadrage -> étape 2',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeAi = _FakeSpecAiService();
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: fakeAi,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      // 1. Saisie de l'idée sur l'écran d'accueil.
      expect(find.text('Nouvelle forge à partir d’une idée'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).at(1),
        'Une application de gestion de devis pour artisans',
      );
      await tester.pump();

      await tester.tap(
        find.text('Démarrer le wizard (Étape 1 : Cadrage)'),
      );
      await tester.pumpAndSettle();

      // 2. L'agent Étape 1 (Product Strategist) a posé une question interactive.
      expect(find.text('Quel est le public cible principal ?'), findsOneWidget);
      expect(fakeAi.calledStages, [SpecForgeStage.vision]);

      // 3. Soumission de la réponse au questionnaire VibeAskUserCard.
      await tester.tap(find.byKey(const ValueKey('vibe-ask-user-submit')));
      await tester.pumpAndSettle();

      // 4. Le patch a enrichi la vue droite (VisionEditorView) et débloqué le passage.
      expect(find.text('Dirigeant PME'), findsOneWidget);
      expect(find.text('Gagner 5h/semaine'), findsOneWidget);
      expect(controller.canUndo, isTrue);

      // 5. Passage à l'étape 2 (Business Analyst).
      await tester.tap(find.text('Valider & Suivant'));
      await tester.pumpAndSettle();

      expect(
        controller.project!.currentStage,
        SpecForgeStage.specifications,
      );
      expect(
        controller.project!.stageStateFor(SpecForgeStage.vision).status,
        SpecStageStatus.validated,
      );
      expect(
        fakeAi.calledStages,
        [
          SpecForgeStage.vision,
          SpecForgeStage.vision,
          SpecForgeStage.specifications,
        ],
      );
    },
  );
}
