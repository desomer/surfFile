import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/main.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_store'));

  final Map<String, SpecForgeProject> _projects = {};
  String? _lastActiveId;

  void seedRaw(SpecForgeProject project) {
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

class _FakeSpecAiService implements SpecAiService {
  final List<SpecForgeStage> calledStages = [];
  final List<String> receivedPrompts = [];
  final List<List<VibeChatAttachment>> receivedAttachments = [];
  int _lexiconTurn = 0;

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
    receivedAttachments.add(attachments);

    late final Map<String, Object?> payload;
    if (stage == SpecForgeStage.lexicon && _lexiconTurn == 0) {
      _lexiconTurn++;
      payload = {
        'message': 'Clarifions d’abord le vocabulaire métier (devis vs chantier).',
        'askUser': {
          'questions': [
            {
              'id': 'q_terme_devis',
              'title': 'Quel terme canonique retenir pour les propositions chiffrées ?',
              'type': 'single',
              'options': ['Devis', 'Chiffrage'],
              'default': 'Devis',
            },
          ],
        },
        'specPatch': null,
        'stageReadyToAdvance': false,
      };
    } else if (stage == SpecForgeStage.lexicon) {
      _lexiconTurn++;
      payload = {
        'message': 'Lexique métier mis à jour.',
        'askUser': null,
        'specPatch': {
          'lexicon': {
            'terms': [
              {
                'id': 'term_devis',
                'term': 'Devis',
                'definition': 'Proposition chiffrée remise à un client artisan.',
                'synonyms': ['Chiffrage'],
                'domain': 'Commercial',
              },
            ],
            'conventions': ['Montants en EUR HT'],
          },
        },
        'stageSummary': 'Terme Devis unifié.',
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
    'Wizard IA complet : idée -> lexique métier (étape 1) -> VibeAskUserCard -> cadrage (étape 2)',
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
        find.text('Démarrer le wizard (Étape 1 : Lexique métier)'),
      );
      await tester.pumpAndSettle();

      // 2. Aucun échange IA n'a encore démarré : le bouton « Commencer » est affiché.
      expect(fakeAi.calledStages, isEmpty);
      final startButton = find.byKey(const ValueKey('spec-stage-start-ai'));
      expect(startButton, findsOneWidget);
      expect(find.text('Commencer'), findsOneWidget);

      await tester.tap(startButton);
      await tester.pumpAndSettle();

      // 3. L'agent Étape 1 (Ubiquitous Language Expert) a posé une question terminologique.
      expect(
        find.text(
          'Quel terme canonique retenir pour les propositions chiffrées ?',
        ),
        findsOneWidget,
      );
      expect(fakeAi.calledStages, [SpecForgeStage.lexicon]);

      // 4. Soumission de la réponse au questionnaire VibeAskUserCard.
      await tester.tap(find.byKey(const ValueKey('vibe-ask-user-submit')));
      await tester.pumpAndSettle();

      // 5. Le patch a enrichi le Lexique métier (LexiconEditorView) et débloqué le passage.
      expect(
        find.text('Proposition chiffrée remise à un client artisan.'),
        findsOneWidget,
      );
      expect(find.text('Montants en EUR HT'), findsOneWidget);
      expect(controller.canUndo, isTrue);

      // 6. Passage à l'étape 2 (Cadrage & Acteurs / Product Strategist) :
      // l'IA ne démarre pas automatiquement sans clic sur « Commencer ».
      await tester.tap(find.text('Valider & Suivant'));
      await tester.pumpAndSettle();

      expect(
        controller.project!.currentStage,
        SpecForgeStage.vision,
      );
      expect(
        controller.project!.stageStateFor(SpecForgeStage.lexicon).status,
        SpecStageStatus.validated,
      );
      expect(
        fakeAi.calledStages,
        [
          SpecForgeStage.lexicon,
          SpecForgeStage.lexicon,
        ],
      );
      expect(find.byKey(const ValueKey('spec-stage-start-ai')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('spec-stage-start-ai')));
      await tester.pumpAndSettle();

      expect(
        fakeAi.calledStages,
        [
          SpecForgeStage.lexicon,
          SpecForgeStage.lexicon,
          SpecForgeStage.vision,
        ],
      );
    },
  );

  testWidgets(
    'Pièces jointes et presse-papiers dans le chat IA (fichier, bouton coller, Ctrl+V, retrait et envoi)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeAi = _FakeSpecAiService();
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: fakeAi,
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Outil de facturation',
        autoKickoff: false,
      );

      var clipboardEmpty = false;
      final pngBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);

      await tester.pumpWidget(
        SuperSpecForgeApp(
          controller: controller,
          restoreLastProject: false,
          pickAttachments: () async => [
            VibeChatAttachment.text(
              name: 'brief.md',
              content: 'Notes du client',
            ),
          ],
          pasteAttachments: () async => clipboardEmpty
              ? const []
              : [
                  VibeChatAttachment.text(
                    name: 'extrait.txt',
                    content: 'Texte collé',
                  ),
                ],
          hasClipboardMedia: () => true,
          pasteClipboardMedia: () async => [
            VibeChatAttachment.image(name: 'capture.png', bytes: pngBytes),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 1. Bouton joindre un fichier -> puce en attente.
      await tester.tap(find.byKey(const ValueKey('spec-chat-attach')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-chat-pending-attachment-0')),
        findsOneWidget,
      );
      expect(find.text('brief.md'), findsOneWidget);

      // 2. Bouton presse-papiers -> 2e puce en attente.
      await tester.tap(find.byKey(const ValueKey('spec-chat-paste-attachment')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-chat-pending-attachment-1')),
        findsOneWidget,
      );
      expect(find.text('extrait.txt'), findsOneWidget);

      // 3. Suppression de la 2e puce.
      await tester.tap(
        find.byKey(const ValueKey('spec-chat-remove-attachment-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('extrait.txt'), findsNothing);

      // 4. Ctrl+V dans le champ texte quand un média est présent -> attache capture.png.
      await tester.tap(find.byKey(const ValueKey('spec-chat-input')));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('capture.png'), findsOneWidget);

      // 5. Envoi sans texte -> transmet les 2 pièces jointes au service IA.
      await tester.tap(find.byKey(const ValueKey('spec-chat-send')));
      await tester.pumpAndSettle();

      expect(fakeAi.receivedAttachments.single.length, 2);
      expect(
        fakeAi.receivedAttachments.single.map((a) => a.name).toList(),
        ['brief.md', 'capture.png'],
      );
      expect(
        find.byKey(const ValueKey('spec-chat-pending-attachment-0')),
        findsNothing,
      );

      // 6. Presse-papiers vide -> bannière d'erreur explicite.
      clipboardEmpty = true;
      await tester.tap(find.byKey(const ValueKey('spec-chat-paste-attachment')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-chat-attachment-error')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Reprise automatique sur exception moteur IA + traçage debugEntries + bouton Réessayer',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      debugEntries.clear();
      final scriptedAi = _ScriptedRecoveryAiService();
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: scriptedAi,
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion de bibliothèque',
        autoKickoff: false,
      );

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      // 1. Scénario de reprise automatique : tentative 1 invalide (@bad) -> reprise delta -> tentative 2 OK.
      await controller.goToStage(
        SpecForgeStage.businessObjects,
        autoKickoffIfEmpty: false,
      );
      await controller.sendUserMessage('Modélise Livre et Auteur');
      await tester.pumpAndSettle();

      expect(scriptedAi.prompts.length, 2);
      expect(scriptedAi.prompts[1], contains('REPRISE AUTOMATIQUE'));
      expect(
        controller.project!.businessObjects.map((o) => o.id).toList(),
        containsAll(['obj_livre', 'obj_auteur']),
      );
      expect(
        debugEntries.any(
          (e) =>
              e.type == DebugEntryType.error &&
              e.message.contains('[SpecForge IA]'),
        ),
        isTrue,
      );

      // 2. Scénario d'échec complet (3 tentatives JSON invalides) -> bouton Réessayer -> succès.
      scriptedAi.mode = _ScriptedMode.alwaysBadJsonThenRecoverOnFourth;
      await controller.sendUserMessage('Ajoute Adhérent');
      await tester.pumpAndSettle();

      expect(find.text('Réessayer / Corriger'), findsOneWidget);

      await tester.tap(find.text('Réessayer / Corriger'));
      await tester.pumpAndSettle();

      expect(
        controller.project!.businessObjects.any((o) => o.id == 'obj_adherent'),
        isTrue,
      );
    },
  );

  testWidgets(
    'SuperTreeView affiche les objets structurés, extrait un tableau >200 lignes et synchronise YAML Light',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Facturation clients',
        autoKickoff: false,
      );
      final base = controller.project!;
      await controller.updateProject(
        base.copyWith(
          currentStage: SpecForgeStage.businessObjects,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_facture',
              name: 'Facture',
              technicalName: 'Facture',
              attributes: [
                BusinessAttribute(
                  id: 'a_num',
                  name: 'numero',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
                BusinessAttribute(
                  id: 'a_adr',
                  name: 'adresseFacturation',
                  type: BusinessAttributeType.object,
                  children: [
                    BusinessAttribute(
                      id: 'a_ville',
                      name: 'ville',
                      type: BusinessAttributeType.string,
                      required: true,
                    ),
                  ],
                ),
                BusinessAttribute(
                  id: 'a_lignes',
                  name: 'lignes',
                  type: BusinessAttributeType.object,
                  isArray: true,
                  estimatedMaxRows: 120,
                  children: [
                    BusinessAttribute(
                      id: 'a_lib',
                      name: 'libelle',
                      type: BusinessAttributeType.string,
                      required: true,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      // 1. SuperTreeView affiche l'objet racine et ses sous-nœuds alignés en haut.
      expect(find.text('Arbre & Inspecteur'), findsOneWidget);
      expect(find.text('Arbre & Inspecteur (SuperTreeView)'), findsNothing);
      expect(find.byType(SuperTreeView), findsOneWidget);
      final treeTop = tester.getTopLeft(find.byType(SuperTreeView)).dy;
      final tabViewTop = tester.getTopLeft(find.byType(TabBarView)).dy;
      expect((treeTop - tabViewTop).abs(), lessThan(4.0));
      expect(find.text('Facture (Facture)'), findsNWidgets(2));
      expect(find.text('adresseFacturation'), findsAtLeastNWidgets(1));
      expect(find.text('lignes'), findsAtLeastNWidgets(1));
      expect(find.text('5 / 200 attributs'), findsOneWidget);

      // 2. Sélection du nœud tableau `lignes` dans le SuperTreeView puis extraction en objet dédié.
      await tester.tap(
        find.byKey(
          const ValueKey(
            'super-tree-row-spec-objects-tree-nodes[0].children[2]',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final extractBtn = find.byKey(
        const ValueKey('spec-objects-extract-array'),
      );
      expect(extractBtn, findsOneWidget);
      await tester.ensureVisible(extractBtn);
      await tester.pumpAndSettle();
      await tester.tap(extractBtn);
      await tester.pumpAndSettle();

      expect(controller.project!.businessObjects.length, 2);
      expect(
        controller.project!.businessObjects[0].relations.single.name,
        'lignes',
      );
      expect(controller.project!.businessObjects[1].technicalName, 'Ligne');

      // 3. Onglet Source YAML (CodeEditor) : édition manuelle et application.
      await tester.tap(find.text('Source YAML'));
      await tester.pumpAndSettle();

      final codeEditorFinder = find.byKey(
        const ValueKey('spec-objects-yaml-editor'),
      );
      expect(codeEditorFinder, findsOneWidget);
      expect(
        find.descendant(
          of: codeEditorFinder,
          matching: find.byType(CodeEditor),
        ),
        findsNothing, // codeEditorFinder IS the CodeEditor itself
      );
      final codeEditorState = tester.state<CodeEditorState>(codeEditorFinder);
      codeEditorState.controller.fullText = '''
Facture:
  numero: string!
  client:
    nom: string!
    email: email
''';
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('spec-objects-apply-yaml')));
      await tester.pumpAndSettle();

      expect(controller.project!.businessObjects.length, 1);
      final updated = controller.project!.businessObjects.single;
      expect(updated.attributes.length, 2);
      expect(updated.attributes[1].name, 'client');
      expect(updated.attributes[1].type, BusinessAttributeType.object);
      expect(updated.attributes[1].children.length, 2);
    },
  );

  testWidgets(
    'NavigationRail gauche : Spec affiche le contenu actuel, Design et Build restent vides',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('spec-forge-nav-rail')), findsOneWidget);
      expect(find.text('Spec'), findsOneWidget);
      expect(find.text('Design'), findsOneWidget);
      expect(find.text('Build'), findsOneWidget);
      expect(find.text('Nouvelle forge à partir d’une idée'), findsOneWidget);

      await tester.tap(find.text('Design'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-design-empty')),
        findsOneWidget,
      );
      expect(find.text('Nouvelle forge à partir d’une idée'), findsNothing);

      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-build-empty')),
        findsOneWidget,
      );

      await tester.tap(find.text('Spec'));
      await tester.pumpAndSettle();
      expect(find.text('Nouvelle forge à partir d’une idée'), findsOneWidget);
    },
  );

  testWidgets(
    'Stopper une réflexion IA en cours via le bouton Arrêter',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var canceled = false;
      final streamCtrl = StreamController<GeminiStreamEvent>(
        onCancel: () {
          canceled = true;
        },
      );
      addTearDown(() async {
        if (!streamCtrl.isClosed) await streamCtrl.close();
      });

      final hangingAi = _ControllableStreamAiService(streamCtrl.stream);
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: hangingAi,
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Outil de suivi chantier',
        autoKickoff: false,
      );

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      unawaited(controller.sendUserMessage('Analyse le vocabulaire'));
      await tester.pump();
      streamCtrl.add(
        const GeminiStreamEvent(
          deltaText: '{"message":"Analyse partielle',
          accumulatedText: '{"message":"Analyse partielle',
          isDone: false,
          usedContextCache: false,
        ),
      );
      await tester.pump();

      expect(controller.isSending, isTrue);
      expect(find.byKey(const ValueKey('spec-chat-stop')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-chat-stop-streaming')),
        findsOneWidget,
      );
      expect(find.text('Analyse partielle'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('spec-chat-stop')));
      await tester.pumpAndSettle();

      expect(canceled, isTrue);
      expect(controller.isSending, isFalse);
      expect(
        find.text(
          'Analyse partielle\n\n[Réflexion IA interrompue par l’utilisateur.]',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('spec-chat-send')), findsOneWidget);
    },
  );

  testWidgets(
    'Appels d’outils IA multi-tours (functionCall -> functionResponse) et affichage des traces',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final toolAi = _ToolCallingAiService();
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: toolAi,
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion commerciale',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          lexicon: SpecLexicon(
            terms: [
              LexiconTerm(
                id: 't1',
                term: 'Facture',
                definition: 'Pièce comptable client',
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      await controller.sendUserMessage('Vérifie le lexique et lance un audit');
      await tester.pumpAndSettle();

      expect(toolAi.roundCount, 2);
      expect(toolAi.secondRoundHasFunctionResponse, isTrue);
      expect(
        find.byKey(const ValueKey('spec-chat-tools-section')),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 outils utilisés'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('spec-chat-tools-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('get_lexicon_and_synonyms'),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.textContaining('run_coherence_audit'),
        findsAtLeastNWidgets(1),
      );
    },
  );

  testWidgets(
    'NavigationRail item Question : chat global sur l’ensemble du projet',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final globalAi = _GlobalQuestionAiService();
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: globalAi,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      // 1. Sans projet ouvert, l'item Question invite à ouvrir/créer un projet.
      await tester.tap(find.text('Question'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-global-chat-no-project')),
        findsOneWidget,
      );

      // 2. Création d'un projet avec lexique, objet et règle de gestion.
      await controller.createProjectFromIdea(
        idea: 'Gestion des commandes clients',
        name: 'OrderSuite',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          lexicon: SpecLexicon(
            terms: [
              LexiconTerm(
                id: 't1',
                term: 'Commande',
                definition: 'Engagement client',
              ),
            ],
          ),
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_cmd',
              name: 'Commande',
              technicalName: 'Commande',
              attributes: [
                BusinessAttribute(id: 'a1', name: 'numero', required: true),
              ],
            ),
          ],
          businessRules: [
            BusinessRuleSpec(
              id: 'rg1',
              code: 'RG-001',
              title: 'Numéro obligatoire',
              targetObjectIds: const ['obj_cmd'],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-global-chat-pane')),
        findsOneWidget,
      );

      // 3. Envoi d'une question globale sur le projet.
      await tester.enterText(
        find.byKey(const ValueKey('spec-global-chat-input')),
        'Résume les règles sur Commande',
      );
      await tester.tap(find.byKey(const ValueKey('spec-global-chat-send')));
      await tester.pumpAndSettle();

      expect(
        globalAi.lastSystemInstruction,
        SpecStageAgent.globalQuestionSystemInstruction,
      );
      expect(globalAi.lastPrompt, contains('RG-001'));
      expect(globalAi.lastPrompt, contains('Engagement client'));
      expect(
        find.text('La règle RG-001 impose un numéro sur Commande.'),
        findsOneWidget,
      );

      // 4. Effacement du fil global.
      await tester.tap(find.byKey(const ValueKey('spec-global-chat-clear')));
      await tester.pumpAndSettle();
      expect(controller.project!.globalChatMessages, isEmpty);
    },
  );

  testWidgets(
    'Édition des contraintes JSON Schema sur un attribut (UI + validation + aperçu)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Catalogue articles',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.businessObjects,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_article',
              name: 'Article',
              technicalName: 'Article',
              attributes: [
                BusinessAttribute(
                  id: 'a_code',
                  name: 'code',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      // 0. Redimensionnement SplitView entre SuperTreeView et l'inspecteur.
      final treePaneFinder = find.byKey(
        const ValueKey('spec-objects-tree-pane'),
      );
      final inspectorPaneFinder = find.byKey(
        const ValueKey('spec-objects-inspector-pane'),
      );
      final splitHandleFinder = find.byKey(
        const ValueKey('spec-objects-tree-split-handle'),
      );
      expect(splitHandleFinder, findsOneWidget);
      final initialTreeWidth = tester.getSize(treePaneFinder).width;
      final initialInspectorWidth = tester.getSize(inspectorPaneFinder).width;

      await tester.drag(splitHandleFinder, const Offset(80, 0));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(treePaneFinder).width,
        greaterThan(initialTreeWidth),
      );
      expect(
        tester.getSize(inspectorPaneFinder).width,
        lessThan(initialInspectorWidth),
      );

      // 1. Sélection de l'attribut `code` dans SuperTreeView -> aperçu JSON Schema dispo.
      await tester.tap(
        find.byKey(
          const ValueKey(
            'super-tree-row-spec-objects-tree-nodes[0].children[0]',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-attr-toggle-json-schema')),
        findsOneWidget,
      );

      // 2. Ouvre le dialogue d'édition d'attribut (agrandi + exemples dans Général sous Description).
      await tester.tap(find.byTooltip('Modifier'));
      await tester.pumpAndSettle();

      final dialogBoxSize = tester.getSize(find.byType(AlertDialog));
      expect(dialogBoxSize.width, greaterThan(800));
      expect(dialogBoxSize.height, greaterThan(600));

      final descField = find.widgetWithText(TextField, 'Description');
      final examplesField = find.byKey(
        const ValueKey('spec-attr-examples-field'),
      );
      expect(examplesField, findsOneWidget);
      expect(
        tester.getTopLeft(examplesField).dy,
        greaterThan(tester.getBottomLeft(descField).dy),
      );
      await tester.enterText(examplesField, 'ARTONE\nARTTWO');

      // 3. Onglet Contraintes JSON Schema : minLength=3, maxLength=20, pattern.
      await tester.tap(find.text('Contraintes JSON Schema'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('spec-attr-min-length-field')),
        '3',
      );
      await tester.enterText(
        find.byKey(const ValueKey('spec-attr-max-length-field')),
        '20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('spec-attr-pattern-field')),
        r'^[A-Z]+$',
      );

      // 4. Onglet Avancé : ajout d'une extension x-mask.
      await tester.tap(find.text('Avancé (Composition / JSON)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('spec-attr-advanced-json-field')),
        '{"x-mask": "AAA-###"}',
      );

      await tester.tap(find.byKey(const ValueKey('spec-attr-save-btn')));
      await tester.pumpAndSettle();

      final savedAttr = controller.project!.businessObjects.single.attributes.single;
      expect(savedAttr.schemaConstraints.examples, ['ARTONE', 'ARTTWO']);
      expect(savedAttr.schemaConstraints.minLength, 3);
      expect(savedAttr.schemaConstraints.maxLength, 20);
      expect(savedAttr.schemaConstraints.pattern, r'^[A-Z]+$');
      expect(savedAttr.schemaConstraints.extraKeywords['x-mask'], 'AAA-###');

      // 5. Les exemples sont visibles dans l'inspecteur d'attribut puis déplie l'aperçu JSON Schema.
      expect(
        find.byKey(const ValueKey('spec-attr-inspector-examples')),
        findsOneWidget,
      );
      expect(find.text('ARTONE'), findsAtLeastNWidgets(1));
      expect(find.text('ARTTWO'), findsAtLeastNWidgets(1));
      await tester.tap(find.byKey(const ValueKey('spec-attr-toggle-json-schema')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-attr-json-schema-preview')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Chat IA des étapes : icône de réduction cyclique (50 % -> 30 % -> masqué -> 50 %) et splitView redimensionnable',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion de stock',
        autoKickoff: false,
      );

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      final chatPaneFinder = find.byKey(const ValueKey('spec-chat-pane'));
      final cycleBtnFinder = find.byKey(
        const ValueKey('spec-chat-cycle-size-btn'),
      );
      final chatSplitHandleFinder = find.byKey(
        const ValueKey('spec-chat-split-handle'),
      );

      expect(chatPaneFinder, findsOneWidget);
      expect(cycleBtnFinder, findsOneWidget);
      expect(chatSplitHandleFinder, findsOneWidget);

      final width50 = tester.getSize(chatPaneFinder).width;

      // 1er clic : 50 % -> 30 %
      await tester.tap(cycleBtnFinder);
      await tester.pumpAndSettle();
      final width30 = tester.getSize(chatPaneFinder).width;
      expect(width30, lessThan(width50));
      expect((width30 / width50), closeTo(0.6, 0.05));

      // 2e clic : 30 % -> disparition (0 %)
      await tester.tap(cycleBtnFinder);
      await tester.pumpAndSettle();
      expect(chatPaneFinder, findsNothing);
      expect(
        find.byKey(const ValueKey('spec-chat-collapsed-bar')),
        findsOneWidget,
      );

      // 3e clic : masqué -> retour à 50 %
      await tester.tap(cycleBtnFinder);
      await tester.pumpAndSettle();
      expect(chatPaneFinder, findsOneWidget);
      expect(tester.getSize(chatPaneFinder).width, closeTo(width50, 1.0));

      // Redimensionnement manuel 1:1 par glisser-déposer (même sur plusieurs événements avant rebuild).
      final gesture = await tester.startGesture(
        tester.getCenter(chatSplitHandleFinder),
      );
      await gesture.moveBy(const Offset(-45, 0));
      await gesture.moveBy(const Offset(-45, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(chatPaneFinder).width, closeTo(width50 - 90, 2.0));

      // Double-clic : réinitialisation à 50 % et persistance sur une autre étape.
      await controller.goToStage(SpecForgeStage.businessObjects);
      await tester.pumpAndSettle();
      expect(cycleBtnFinder, findsOneWidget);
      await tester.tap(cycleBtnFinder);
      await tester.pumpAndSettle();
      expect(tester.getSize(chatPaneFinder).width, closeTo(width30, 1.0));
    },
  );

  testWidgets(
    'BusinessObjectsEditorView ne plante pas sur un nom d’attribut accentué et propose la correction auto',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final memStore = _MemorySpecProjectStore();
      final controller = SpecForgeController(
        store: memStore,
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Suivi kilométrique',
        autoKickoff: false,
      );
      memStore.seedRaw(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.businessObjects,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_releve',
              name: 'Relevé kilométrique',
              technicalName: 'ReleveKilometrique',
              attributes: [
                BusinessAttribute(
                  id: 'a_statut',
                  name: 'statutCohérence',
                  type: BusinessAttributeType.string,
                ),
              ],
            ),
          ],
        ),
      );
      await controller.openProject(controller.project!.id);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      // Aucune exception de build ; carte d'erreur et bouton de correction affichés.
      expect(
        find.byKey(const ValueKey('spec-objects-tree-error-card')),
        findsOneWidget,
      );
      final fixBtn = find.byKey(
        const ValueKey('spec-objects-normalize-ids-btn'),
      );
      expect(fixBtn, findsOneWidget);

      await tester.tap(fixBtn);
      await tester.pumpAndSettle();

      expect(
        controller.project!.businessObjects.single.attributes.single.name,
        'statutCoherence',
      );
      expect(
        find.byKey(const ValueKey('spec-objects-tree-error-card')),
        findsNothing,
      );
      expect(find.byType(SuperTreeView), findsOneWidget);
    },
  );

  testWidgets(
    'Survol d’un attribut dans le SuperTreeView affiche la card tooltip détaillée',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Catalogue produits',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.businessObjects,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_produit',
              name: 'Produit',
              technicalName: 'Produit',
              attributes: [
                BusinessAttribute(
                  id: 'a_sku',
                  name: 'sku',
                  type: BusinessAttributeType.string,
                  required: true,
                  unique: true,
                  description: 'Code article unique au format SKU.',
                  constraints: 'Majuscules et tirets uniquement',
                  schemaConstraints: JsonSchemaConstraints(
                    minLength: 4,
                    maxLength: 20,
                    pattern: r'^[A-Z0-9-]+$',
                    examples: const ['SKU-2026-AB', 'PRD-0099'],
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      final rowFinder = find.byKey(
        const ValueKey(
          'super-tree-row-spec-objects-tree-nodes[0].children[0]',
        ),
      );
      expect(rowFinder, findsOneWidget);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(rowFinder));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-tree-node-tooltip-card')),
        findsOneWidget,
      );
      expect(
        find.text('Code article unique au format SKU.'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('Obligatoire (!)'), findsAtLeastNWidgets(1));
      expect(find.text('Unique'), findsAtLeastNWidgets(1));
      expect(find.text('Contraintes JSON Schema'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-tree-tooltip-examples')),
        findsOneWidget,
      );
      expect(find.text('SKU-2026-AB'), findsAtLeastNWidgets(1));
      expect(find.text('PRD-0099'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'ReviewExportView onglet .md ouvre le visualisateur Markdown avancé et déclenche TOC/Thème/Print/Navigateur',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion commandes',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.reviewExport,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_cmd',
              name: 'Commande',
              technicalName: 'Commande',
              attributes: [
                BusinessAttribute(
                  id: 'a_ref',
                  name: 'reference',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
              ],
            ),
          ],
        ),
      );

      final executedJs = <String>[];
      final launchedFiles = <File>[];
      File? renderedFile;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewExportView(
              controller: controller,
              markdownBrowserLauncher: (file) async {
                launchedFiles.add(file);
              },
              markdownViewerSurfaceBuilder: (context, htmlFile, registerJs) {
                renderedFile = htmlFile;
                registerJs((js) async {
                  executedJs.add(js);
                });
                return Center(
                  key: const ValueKey('spec-md-mock-surface'),
                  child: Text('Aperçu HTML : ${htmlFile.path}'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bascule vers l'onglet Cahier des charges (.md).
      await tester.tap(find.text('Cahier des charges (.md)'));
      await tester.pumpAndSettle();

      final openViewerBtn = find.byKey(
        const ValueKey('spec-review-open-md-viewer'),
      );
      expect(openViewerBtn, findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-review-open-md-browser')),
        findsOneWidget,
      );

      await tester.tap(openViewerBtn);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
        if (find
            .byKey(const ValueKey('spec-md-mock-surface'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-md-mock-surface')),
        findsOneWidget,
      );
      expect(renderedFile, isNotNull);
      final htmlContent = await tester.runAsync(() => renderedFile!.readAsString());
      expect(htmlContent, contains('erDiagram'));
      expect(htmlContent, contains('ssf-mermaid-card'));
      expect(htmlContent, contains('renderMathInElement'));

      // Toggle Sommaire (TOC), Thème, Impression PDF et Navigateur.
      await tester.tap(
        find.byKey(const ValueKey('spec-md-viewer-toggle-toc')),
      );
      await tester.pumpAndSettle();
      expect(executedJs.last, contains('setTocVisible(false)'));

      await tester.tap(
        find.byKey(const ValueKey('spec-md-viewer-toggle-theme')),
      );
      await tester.pumpAndSettle();
      expect(executedJs.last, contains("setTheme('dark')"));

      await tester.tap(find.byKey(const ValueKey('spec-md-viewer-print')));
      await tester.pumpAndSettle();
      expect(executedJs.last, 'window.print();');

      await tester.tap(
        find.byKey(const ValueKey('spec-md-viewer-open-browser')),
      );
      await tester.pump();
      for (var i = 0; i < 30 && launchedFiles.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(launchedFiles.length, 1);
      expect(
        await tester.runAsync(() => launchedFiles.single.exists()),
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('spec-md-viewer-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spec-md-mock-surface')), findsNothing);
    },
  );

  testWidgets(
    'ReviewExportView onglet JSON Schema & Seed : inspecteur natif, validateur live et doc HTML WebView2',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion commandes B2B',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.reviewExport,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_cmd',
              name: 'Commande',
              technicalName: 'Commande',
              attributes: [
                BusinessAttribute(
                  id: 'a_ref',
                  name: 'reference',
                  type: BusinessAttributeType.string,
                  required: true,
                  schemaConstraints: JsonSchemaConstraints(minLength: 3),
                ),
                BusinessAttribute(
                  id: 'a_total',
                  name: 'totalHt',
                  type: BusinessAttributeType.number,
                  required: true,
                  schemaConstraints: JsonSchemaConstraints(minimum: 1),
                ),
              ],
            ),
            BusinessObjectSpec(
              id: 'obj_cli',
              name: 'Client',
              technicalName: 'Client',
              attributes: [
                BusinessAttribute(
                  id: 'a_nom',
                  name: 'raisonSociale',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
              ],
            ),
          ],
        ),
      );

      final executedJs = <String>[];
      final launchedFiles = <File>[];
      File? renderedHtmlFile;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewExportView(
              controller: controller,
              markdownBrowserLauncher: (file) async {
                launchedFiles.add(file);
              },
              markdownViewerSurfaceBuilder: (context, htmlFile, registerJs) {
                renderedHtmlFile = htmlFile;
                registerJs((js) async {
                  executedJs.add(js);
                });
                return Center(
                  key: const ValueKey('spec-schema-html-mock-surface'),
                  child: Text('Doc HTML : ${htmlFile.path}'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Onglet JSON Schema & Seed -> boutons visualisateur et navigateur présents.
      await tester.tap(find.text('JSON Schema & Seed'));
      await tester.pumpAndSettle();

      final openSchemaViewerBtn = find.byKey(
        const ValueKey('spec-review-open-schema-viewer'),
      );
      expect(openSchemaViewerBtn, findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-review-open-schema-browser')),
        findsOneWidget,
      );

      await tester.tap(openSchemaViewerBtn);
      await tester.pumpAndSettle();

      // 2. Inspecteur natif : liste des repositories + Arbre du Schéma.
      expect(
        find.byKey(const ValueKey('spec-schema-repo-tile-commande')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-schema-repo-tile-client')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('spec-schema-repo-tile-commande')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Arbre du Schéma'), findsOneWidget);
      expect(find.text('reference'), findsAtLeastNWidgets(1));

      // Filtre de recherche sur l'arbre du schéma.
      await tester.enterText(
        find.byKey(const ValueKey('spec-schema-tree-search')),
        'totalHt',
      );
      await tester.pumpAndSettle();
      expect(find.text('totalHt'), findsAtLeastNWidgets(1));

      await tester.tap(
        find.byKey(const ValueKey('spec-schema-repo-tile-client')),
      );
      await tester.pumpAndSettle();

      // 3. Onglet Seed & Validateur live : conforme puis édition invalide puis reset.
      await tester.tap(find.text('Seed & Validateur live'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Document Seed conforme au JSON Schema'),
        findsOneWidget,
      );

      final seedEditorFinder = find.byKey(
        const ValueKey('spec-schema-seed-editor-client'),
      );
      expect(seedEditorFinder, findsOneWidget);
      final seedEditorState = tester.state<CodeEditorState>(seedEditorFinder);
      seedEditorState.controller.fullText = '{"clients": [{"raisonSociale": 123}]}';
      await tester.pumpAndSettle();

      expect(
        find.textContaining('erreur(s) de validation JSON Schema'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('spec-schema-reset-seed')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Document Seed conforme au JSON Schema'),
        findsOneWidget,
      );

      // 4. Onglet Source JSON Schema.
      await tester.tap(find.text('Source JSON Schema'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-schema-raw-editor-client')),
        findsOneWidget,
      );

      // 5. Bascule vers Doc HTML (WebView2) + thème + impression + navigateur + fermeture.
      await tester.tap(find.text('Doc HTML'));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
        if (find
            .byKey(const ValueKey('spec-schema-html-mock-surface'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-schema-html-mock-surface')),
        findsOneWidget,
      );
      expect(renderedHtmlFile, isNotNull);
      final htmlDoc = await tester.runAsync(() => renderedHtmlFile!.readAsString());
      expect(htmlDoc, contains('ssf-repos-data'));
      expect(htmlDoc, contains('commande'));
      expect(htmlDoc, contains('client'));

      await tester.tap(
        find.byKey(const ValueKey('spec-schema-viewer-toggle-theme')),
      );
      await tester.pumpAndSettle();
      expect(executedJs.last, contains("setTheme('dark')"));

      await tester.tap(find.byKey(const ValueKey('spec-schema-viewer-print')));
      await tester.pumpAndSettle();
      expect(executedJs.last, 'window.print();');

      await tester.tap(
        find.byKey(const ValueKey('spec-schema-viewer-open-browser')),
      );
      await tester.pump();
      for (var i = 0; i < 30 && launchedFiles.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(launchedFiles.length, 1);

      await tester.tap(find.byKey(const ValueKey('spec-schema-viewer-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-schema-html-mock-surface')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Wizard Objets métiers : paramétrage de langue des attributs et des textes/exemples transmis à l’IA',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeAi = _FakeSpecAiService();
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: fakeAi,
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion de flotte',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.businessObjects,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_vehicule',
              name: 'Véhicule',
              technicalName: 'Vehicule',
              attributes: [
                BusinessAttribute(
                  id: 'a_date',
                  name: 'dateMiseEnService',
                  type: BusinessAttributeType.date,
                ),
                BusinessAttribute(
                  id: 'a_statut',
                  name: 'statut',
                  type: BusinessAttributeType.enumeration,
                  enumValues: const ['enCours', 'archive'],
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      final prefsBtn = find.byKey(const ValueKey('spec-objects-prefs-btn'));
      expect(prefsBtn, findsOneWidget);
      expect(
        find.text('Préférences du modèle (EN · camel / FR · Std)'),
        findsOneWidget,
      );

      await tester.tap(prefsBtn);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-objects-prefs-dialog')),
        findsOneWidget,
      );

      // Par défaut : attributs en anglais (`en`) et valeurs d'enum en anglais (`en`).
      expect(
        controller.project!.businessObjectModelPreferences.attributeLanguage,
        'en',
      );
      expect(
        controller.project!.businessObjectModelPreferences.enumLanguage,
        'en',
      );
      expect(
        find.byKey(const ValueKey('spec-objects-enum-lang-dropdown')),
        findsOneWidget,
      );

      // Onglet 1 : Langues & Nommage
      final namingScrollable = find.descendant(
        of: find.descendant(
          of: find.byKey(const ValueKey('spec-objects-prefs-dialog')),
          matching: find.byType(ListView),
        ),
        matching: find.byType(Scrollable),
      );

      await tester.tap(
        find.byKey(const ValueKey('spec-objects-attr-case-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('snake_case (ex. delivery_address)').last);
      await tester.pumpAndSettle();

      final enumCaseDropdown = find.byKey(
        const ValueKey('spec-objects-enum-case-dropdown'),
      );
      await tester.drag(namingScrollable, const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(enumCaseDropdown);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('SCREAMING_SNAKE_CASE (ex. PENDING_APPROVAL)').last,
      );
      await tester.pumpAndSettle();

      await tester.drag(namingScrollable, const Offset(0, -340));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-objects-apply-case-existing')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-objects-apply-enum-case-existing')),
      );
      await tester.pumpAndSettle();

      // Onglet 2 : Clés & Audit
      await tester.tap(find.text('Clés & Audit'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-objects-id-strategy-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ULID (26 car.)').last);
      await tester.pumpAndSettle();

      // Onglet 3 : Schéma & Relations
      await tester.tap(find.text('Schéma & Relations'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-objects-schema-strictness-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Strict (additionalProperties: false)').last);
      await tester.pumpAndSettle();

      // Onglet 4 : Régional & Consignes
      await tester.tap(find.text('Régional & Consignes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('spec-objects-custom-instructions-field')),
        'Prefix booleans with is',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-objects-prefs-prompt-preview')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('spec-objects-prefs-save')),
      );
      await tester.pumpAndSettle();

      final savedPrefs = controller.project!.businessObjectModelPreferences;
      expect(savedPrefs.attributeLanguage, 'en');
      expect(savedPrefs.enumLanguage, 'en');
      expect(savedPrefs.attributeCase, AttributeNamingCase.snakeCase);
      expect(savedPrefs.enumCase, EnumValueNamingCase.screamingSnakeCase);
      expect(savedPrefs.idStrategy, PrimaryIdStrategy.ulid);
      expect(savedPrefs.schemaStrictness, JsonSchemaStrictness.strict);
      expect(savedPrefs.customInstructions, 'Prefix booleans with is');
      expect(
        controller.project!.businessObjects.single.attributes.first.name,
        'date_mise_en_service',
      );
      expect(
        controller.project!.businessObjects.single.attributes[1].enumValues,
        ['EN_COURS', 'ARCHIVE'],
      );
      expect(
        find.text('Préférences du modèle (EN · snake / FR · Strict)'),
        findsOneWidget,
      );

      // Lancement de l'échange IA sur Objets métiers -> reçoit toutes les préférences.
      await tester.tap(find.byKey(const ValueKey('spec-stage-start-ai')));
      await tester.pumpAndSettle();

      expect(fakeAi.calledStages, [SpecForgeStage.businessObjects]);
      expect(fakeAi.receivedPrompts.single, contains('English (en)'));
      expect(fakeAi.receivedPrompts.single, contains('snake_case'));
      expect(fakeAi.receivedPrompts.single, contains('SCREAMING_SNAKE_CASE'));
      expect(fakeAi.receivedPrompts.single, contains('ULID'));
      expect(
        fakeAi.receivedPrompts.single,
        contains('additionalProperties: false'),
      );
      expect(
        fakeAi.receivedPrompts.single,
        contains('Prefix booleans with is'),
      );
    },
  );

  testWidgets(
    'Wizard Objets métiers : sous-onglet JSON Schema & Seed identique au visualisateur (inspecteur natif, validateur live, synchronisation et Doc HTML)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion des devis',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.businessObjects,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_devis',
              name: 'Devis',
              technicalName: 'Devis',
              attributes: [
                BusinessAttribute(
                  id: 'a_code',
                  name: 'code',
                  type: BusinessAttributeType.string,
                  required: true,
                  schemaConstraints: JsonSchemaConstraints(minLength: 3),
                ),
                BusinessAttribute(
                  id: 'a_montant',
                  name: 'totalAmount',
                  type: BusinessAttributeType.number,
                  required: true,
                  schemaConstraints: JsonSchemaConstraints(minimum: 10),
                ),
              ],
            ),
          ],
        ),
      );

      final executedJs = <String>[];
      final launchedFiles = <File>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => BusinessObjectsEditorView(
                controller: controller,
                schemaBrowserLauncher: (file) async {
                  launchedFiles.add(file);
                },
                schemaViewerSurfaceBuilder: (context, htmlFile, registerJs) {
                  registerJs((js) async {
                    executedJs.add(js);
                  });
                  return Center(
                    key: const ValueKey('spec-objects-schema-html-mock'),
                    child: Text('Doc HTML : ${htmlFile.path}'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Le sous-onglet « JSON Schema & Seed » est présent dans BusinessObjectsEditorView.
      final schemaTab = find.byKey(const ValueKey('spec-objects-schema-tab'));
      expect(schemaTab, findsOneWidget);
      await tester.tap(schemaTab);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-objects-schema-viewer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-schema-viewer-mode-switch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-schema-viewer-close')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('spec-schema-repo-tile-devis')),
        findsOneWidget,
      );
      expect(find.text('Arbre du Schéma'), findsOneWidget);
      expect(find.text('totalAmount'), findsAtLeastNWidgets(1));

      // 2. Onglet Seed & Validateur live : validation conforme puis erreur puis reset.
      await tester.tap(find.text('Seed & Validateur live'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Document Seed conforme au JSON Schema'),
        findsOneWidget,
      );

      final seedEditorFinder = find.byKey(
        const ValueKey('spec-schema-seed-editor-devis'),
      );
      final seedEditorState = tester.state<CodeEditorState>(seedEditorFinder);
      seedEditorState.controller.fullText =
          '{"devis": [{"code": "A", "totalAmount": 2}]}';
      await tester.pumpAndSettle();
      expect(
        find.textContaining('erreur(s) de validation JSON Schema'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('spec-schema-reset-seed')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Document Seed conforme au JSON Schema'),
        findsOneWidget,
      );

      // 3. Synchronisation dynamique quand un nouvel objet métier est ajouté au projet.
      await controller.updateProject(
        controller.project!.copyWith(
          businessObjects: [
            ...controller.project!.businessObjects,
            BusinessObjectSpec(
              id: 'obj_client',
              name: 'Client',
              technicalName: 'Client',
              attributes: [
                BusinessAttribute(
                  id: 'a_nom',
                  name: 'companyName',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-schema-repo-tile-client')),
        findsOneWidget,
      );

      // 4. Bascule vers le mode « Doc HTML » (WebView2) + Thème + Print + Navigateur.
      await tester.tap(find.text('Doc HTML'));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
        if (find
            .byKey(const ValueKey('spec-objects-schema-html-mock'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-objects-schema-html-mock')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('spec-schema-viewer-toggle-theme')),
      );
      await tester.pumpAndSettle();
      expect(executedJs.last, contains("setTheme('dark')"));

      await tester.tap(find.byKey(const ValueKey('spec-schema-viewer-print')));
      await tester.pumpAndSettle();
      expect(executedJs.last, 'window.print();');

      await tester.tap(
        find.byKey(const ValueKey('spec-schema-viewer-open-browser')),
      );
      await tester.pump();
      for (var i = 0; i < 30 && launchedFiles.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(launchedFiles.length, 1);
    },
  );
}

class _GlobalQuestionAiService implements SpecAiService {
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
    final json = jsonEncode({
      'message': 'La règle RG-001 impose un numéro sur Commande.',
      'askUser': null,
      'specPatch': null,
    });
    yield GeminiStreamEvent(
      deltaText: json,
      accumulatedText: json,
      isDone: true,
      usedContextCache: false,
    );
  }
}

class _ToolCallingAiService implements SpecAiService {
  int roundCount = 0;
  bool secondRoundHasFunctionResponse = false;

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
    roundCount++;
    if (roundCount == 1) {
      yield GeminiStreamEvent(
        deltaText: '',
        accumulatedText: '',
        isDone: true,
        usedContextCache: false,
        functionCalls: [
          VibeToolCall(
            id: 'call_1',
            name: 'get_lexicon_and_synonyms',
          ),
          VibeToolCall(
            id: 'call_2',
            name: 'run_coherence_audit',
          ),
        ],
      );
      return;
    }
    if (conversationContents != null && conversationContents.length >= 3) {
      final userTurn = conversationContents.last;
      final parts = userTurn['parts'];
      if (parts is List &&
          parts.any((p) => p is Map && p.containsKey('functionResponse'))) {
        secondRoundHasFunctionResponse = true;
      }
    }
    final finalJson = jsonEncode({
      'message': 'Audit et lexique vérifiés via les outils.',
      'askUser': null,
      'specPatch': null,
      'stageReadyToAdvance': true,
    });
    yield GeminiStreamEvent(
      deltaText: finalJson,
      accumulatedText: finalJson,
      isDone: true,
      usedContextCache: false,
    );
  }
}

class _ControllableStreamAiService implements SpecAiService {
  _ControllableStreamAiService(this._stream);

  final Stream<GeminiStreamEvent> _stream;

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
  }) => _stream;
}

enum _ScriptedMode { autoRecoverOnSecond, alwaysBadJsonThenRecoverOnFourth }

class _ScriptedRecoveryAiService implements SpecAiService {
  final List<String> prompts = [];
  _ScriptedMode mode = _ScriptedMode.autoRecoverOnSecond;
  int _callCount = 0;

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
    prompts.add(prompt);
    _callCount++;

    late final String raw;
    if (mode == _ScriptedMode.autoRecoverOnSecond) {
      if (_callCount == 1) {
        // Livre valide + Auteur invalide (@bad) -> déclenche FormatException + checkpoint Livre.
        raw = jsonEncode({
          'message': 'Première proposition',
          'askUser': null,
          'specPatch': {
            'businessObjects': [
              {
                'id': 'obj_livre',
                'name': 'Livre',
                'attributes': [
                  {'id': 'a1', 'name': 'titre', 'type': 'string'},
                ],
              },
              {
                'id': 'obj_auteur',
                'name': 'Auteur',
                'attributes': [
                  {'id': 'a2', 'name': '@bad', 'type': 'string'},
                ],
              },
            ],
          },
        });
      } else {
        raw = jsonEncode({
          'message': 'Auteur corrigé suite à la reprise.',
          'askUser': null,
          'specPatch': {
            'businessObjects': [
              {
                'id': 'obj_auteur',
                'name': 'Auteur',
                'attributes': [
                  {'id': 'a2', 'name': 'nom', 'type': 'string'},
                ],
              },
            ],
          },
        });
      }
    } else {
      // Échoue 3 fois sur JSON invalide, puis réussit à la relance manuelle (4e appel de cette phase).
      if (_callCount <= 5) {
        raw = '{"message": "tronqué"';
      } else {
        raw = jsonEncode({
          'message': 'Adhérent ajouté après relance manuelle.',
          'askUser': null,
          'specPatch': {
            'businessObjects': [
              {
                'id': 'obj_adherent',
                'name': 'Adhérent',
                'attributes': [
                  {'id': 'a3', 'name': 'email', 'type': 'email'},
                ],
              },
            ],
          },
        });
      }
    }

    yield GeminiStreamEvent(
      deltaText: raw,
      accumulatedText: raw,
      isDone: true,
      usedContextCache: false,
    );
  }
}
