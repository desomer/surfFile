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
        'message':
            'Clarifions d’abord le vocabulaire métier (devis vs chantier).',
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
                'definition':
                    'Proposition chiffrée remise à un client artisan.',
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

Finder _appBarText(String title) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(title));

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

      // 0. Ouverture de Projets depuis le menu Spec.
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('spec-link-projects')));
      await tester.pumpAndSettle();

      // 1. Saisie de l'idée sur l'écran Projets.
      expect(find.text('Nouvelle forge à partir d’une idée'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).at(1),
        'Une application de gestion de devis pour artisans',
      );
      await tester.pump();

      final startWizardButton = find.text(
        'Démarrer le wizard (Étape 1 : Lexique métier)',
      );
      await tester.ensureVisible(startWizardButton);
      await tester.pumpAndSettle();
      await tester.tap(startWizardButton);
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

      expect(controller.project!.currentStage, SpecForgeStage.vision);
      expect(
        controller.project!.stageStateFor(SpecForgeStage.lexicon).status,
        SpecStageStatus.validated,
      );
      expect(fakeAi.calledStages, [
        SpecForgeStage.lexicon,
        SpecForgeStage.lexicon,
      ]);
      expect(find.byKey(const ValueKey('spec-stage-start-ai')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('spec-stage-start-ai')));
      await tester.pumpAndSettle();

      expect(fakeAi.calledStages, [
        SpecForgeStage.lexicon,
        SpecForgeStage.lexicon,
        SpecForgeStage.vision,
      ]);
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
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
      await tester.tap(
        find.byKey(const ValueKey('spec-chat-paste-attachment')),
      );
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
      expect(fakeAi.receivedAttachments.single.map((a) => a.name).toList(), [
        'brief.md',
        'capture.png',
      ]);
      expect(
        find.byKey(const ValueKey('spec-chat-pending-attachment-0')),
        findsNothing,
      );

      // 6. Presse-papiers vide -> bannière d'erreur explicite.
      clipboardEmpty = true;
      await tester.tap(
        find.byKey(const ValueKey('spec-chat-paste-attachment')),
      );
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      // 1. La ListView des repositories affiche Facture dépliée avec son SuperTreeView aligné en haut.
      expect(
        find.byKey(const ValueKey('spec-objects-tree-tab')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-objects-schema-tab')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-objects-dsl-tab')),
        findsOneWidget,
      );
      expect(find.text('Objets'), findsOneWidget);
      expect(find.text('Repositories'), findsOneWidget);
      expect(find.text('DSL'), findsOneWidget);
      expect(find.text('Arbre & Inspecteur'), findsNothing);
      expect(find.text('Arbre & Inspecteur (SuperTreeView)'), findsNothing);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('spec-objects-tree-tab')))
            .dx,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('spec-objects-schema-tab')))
              .dx,
        ),
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('spec-objects-schema-tab')))
            .dx,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('spec-objects-dsl-tab')))
              .dx,
        ),
      );
      expect(
        find.byKey(const ValueKey('spec-objects-repo-listview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-objects-repo-tile-obj_facture')),
        findsOneWidget,
      );
      expect(find.text('Objets métiers (1)'), findsNWidgets(2));
      expect(find.text('Agrégat'), findsOneWidget);
      expect(find.text('Valide'), findsOneWidget);
      expect(find.byType(SuperTreeView), findsOneWidget);
      final repoPaneTop = tester
          .getTopLeft(find.byKey(const ValueKey('spec-objects-tree-pane')))
          .dy;
      final tabViewTop = tester.getTopLeft(find.byType(TabBarView)).dy;
      expect((repoPaneTop - tabViewTop).abs(), lessThan(4.0));
      expect(find.text('Facture (Facture)'), findsOneWidget);
      expect(find.text('adresseFacturation'), findsAtLeastNWidgets(1));
      expect(find.text('lignes'), findsAtLeastNWidgets(1));
      expect(find.text('5 / 200 attributs'), findsOneWidget);

      // 2. Sélection du nœud tableau `lignes` dans le SuperTreeView puis extraction en objet dédié.
      await tester.tap(
        find.byKey(
          const ValueKey(
            'super-tree-row-spec-objects-tree-obj_facture-nodes[2]',
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

      // 3. Onglet DSL (CodeEditor) : édition manuelle et application.
      await tester.tap(find.text('DSL'));
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

  testWidgets('Modèles & Contrats : le badge change le domaine de la page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final aiService = _DomainModelFakeAiService();
    final controller = SpecForgeController(
      store: _MemorySpecProjectStore(),
      glossaryStore: _MemoryCompanyGlossaryStore(),
      modelDictionaryStore: _MemoryModelDictionaryStore(),
      domainCatalogStore: _MemoryDomainCatalogStore(),
      aiService: aiService,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      SuperSpecForgeApp(controller: controller, restoreLastProject: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Design'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modèles & Contrats'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun domaine'), findsOneWidget);
    expect(_appBarText('Design › Modèles & Contrats'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('contracts-manage-domains-btn')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DomainManagementView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('domain-management-back-btn')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('spec-forge-appbar-back-btn')));
    await tester.pumpAndSettle();

    await controller.updateDomainCatalog(
      DomainCatalog(
        domains: const [
          FunctionalDomain(id: 'oms', domainCode: 'oms', name: 'OMS'),
          FunctionalDomain(id: 'rh', domainCode: 'rh', name: 'RH'),
        ],
      ),
    );
    await tester.tap(find.text('Modèles & Contrats'));
    await tester.pumpAndSettle();
    expect(find.text('OMS'), findsOneWidget);
    await tester.tap(find.byTooltip('Choisir un domaine'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'OMS'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'RH'));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('RH'), findsOneWidget);
    expect(find.byType(SuperTreeView), findsOneWidget);
    expect(find.text('OMS'), findsNothing);
    final editor = tester.state<CodeEditorState>(find.byType(CodeEditor));
    expect(editor.controller.fullText, contains('components:'));
    expect(find.text('models'), findsOneWidget);
    expect(find.text('Modèles métiers'), findsNothing);
    expect(find.byTooltip('Appliquer le DSL'), findsNothing);
    editor.controller.fullText =
        'models:\n  sales: model # ventes\n  events: eventxpayloaddto\n';
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.text('sales'), findsOneWidget);
    expect(
      controller.domainCatalog.domains.last.contracts?.source,
      contains('sales: model # ventes'),
    );
    final badge = find.byKey(const ValueKey('type-models.sales'));
    final properties = find.byKey(const ValueKey('edit-models.sales'));
    expect(
      tester.getTopRight(badge).dx,
      tester.getTopRight(find.byKey(const ValueKey('type-models.events'))).dx,
    );
    expect(
      tester.getTopRight(badge).dx,
      lessThanOrEqualTo(tester.getTopLeft(properties).dx),
    );
    await tester.tap(badge);
    await tester.pumpAndSettle();
    await tester.tap(find.text('flatfile'));
    await tester.pumpAndSettle();
    expect(editor.controller.fullText, contains('sales: flatfile # ventes'));
    expect(
      controller.domainCatalog.domains.last.contracts?.source,
      contains('sales: flatfile # ventes'),
    );
    await tester.tap(properties);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Titre'),
      'Ventes',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Version'),
      '0.0.2',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Ventes'), findsOneWidget);
    expect(editor.controller.fullText, contains('sales: flatfile # ventes'));
    // Le fil d’Ariane n’affiche le modèle qu’une fois sa fiche ouverte.
    expect(find.text('0.0.2'), findsOneWidget);
    expect(controller.domainCatalog.domains.first.contracts, isNull);
    editor.controller.fullText = 'models:\n  sales: invalide';
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.textContaining('type inconnu'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CodeEditor),
        matching: find.textContaining('type inconnu'),
      ),
      findsOneWidget,
    );
    expect(find.text('Ventes'), findsOneWidget);
    expect(
      controller.domainCatalog.domains.last.contracts?.source,
      contains('sales: flatfile # ventes'),
    );
    editor.controller.fullText = 'models:\n  events: eventxpayloaddto\ncomponents:\n  sales: flatfile # ventes\n';
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.textContaining('type inconnu'), findsNothing);
    // Le bloc déplacé garde son ID : titre, version et sélection le suivent.
    expect(find.byKey(const ValueKey('edit-components.sales')), findsOneWidget);
    expect(find.text('Ventes'), findsOneWidget);
    expect(find.text('0.0.2'), findsOneWidget);
    final codePane = find.byKey(const ValueKey('domain-contracts-code-pane'));
    final splitHandle = find.byKey(
      const ValueKey('domain-contracts-split-handle'),
    );
    final initialCodeWidth = tester.getSize(codePane).width;
    await tester.drag(splitHandle, const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(codePane).width, closeTo(initialCodeWidth + 150, 1));
    expect(
      tester.getTopLeft(find.byType(SuperTreeView)).dx,
      greaterThan(tester.getTopRight(codePane).dx),
    );
    await tester.tap(splitHandle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(splitHandle);
    await tester.pumpAndSettle();
    expect(tester.getSize(codePane).width, closeTo(initialCodeWidth, 1));
    final link = find.byKey(const ValueKey('open-components.sales'));
    final entryPage = find.byKey(const ValueKey('contract-entry-page'));
    expect(
      tester
          .widget<Text>(find.descendant(of: link, matching: find.text('sales')))
          .style
          ?.decoration,
      TextDecoration.underline,
    );
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(entryPage, findsOneWidget);
    expect(find.byType(SuperTreeView), findsNothing);
    // Fil d’Ariane : domaine › liste › modèle › version.
    expect(_appBarText('Modèles & Contrats › sales'), findsOneWidget);
    expect(find.text('RH'), findsOneWidget);
    expect(find.text('sales'), findsNWidgets(2));
    expect(find.text('0.0.2'), findsOneWidget);
    expect(find.text('Ventes'), findsOneWidget);
    expect(find.text('flatfile'), findsOneWidget);
    // Fiche : le chat IA crée les attributs de l'objet unique du modèle.
    expect(find.byKey(const ValueKey('contract-chat-pane')), findsOneWidget);
    expect(
      find.textContaining('Aucun attribut : décrivez le modèle'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('contract-chat-input')),
      'Ajoute le montant, le client et l’événement',
    );
    await tester.tap(find.byKey(const ValueKey('contract-chat-send')));
    await tester.pumpAndSettle();
    expect(aiService.lastPrompt, contains('nom technique : sales'));
    expect(aiService.lastPrompt, contains('nom technique : events'));
    expect(aiService.lastStaticGuide, contains('removeAttributes'));
    // Mêmes consignes que l'étape Objets métier : règles x-*, préférences du
    // modèle et dictionnaire technique.
    expect(
      aiService.lastSystemInstruction,
      contains(SpecStageAgent.attributeModelingRules),
    );
    expect(
      aiService.lastStaticGuide,
      contains(SpecStageAgent.attributeExamplesJson),
    );
    expect(
      aiService.lastPrompt,
      contains(controller.modelPreferences.toPromptDirective()),
    );
    expect(
      aiService.lastPrompt,
      contains('DICTIONNAIRE DE RÈGLES TECHNIQUES ACTIVES'),
    );
    var contracts = controller.domainCatalog.domains.last.contracts!;
    final salesId = contracts.objects.keys.single;
    final sales = contracts.objects[salesId]!;
    expect(sales.description, 'Ventes du jour');
    expect(sales.attributes[1].schemaConstraints.xMask, 'CLI-####');
    expect(sales.attributes[1].schemaConstraints.xSearchable, isTrue);
    expect(
      [for (final attribute in sales.attributes) attribute.name],
      ['montant', 'client', 'evenement'],
    );
    expect(
      contracts.entryById(sales.attributes.last.referenceObjectId)?.name,
      'events',
    );
    expect(contracts.chats[salesId], hasLength(2));
    expect(
      find.text('Mis à jour : sales (+3 attribut(s), description)'),
      findsOneWidget,
    );
    final treePane = find.byKey(const ValueKey('contract-model-tree-pane'));
    expect(
      find.descendant(of: treePane, matching: find.byType(SuperTreeView)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: treePane, matching: find.text('montant')),
      findsOneWidget,
    );
    // Le chat se replie sur un rail et se rouvre.
    await tester.tap(find.byKey(const ValueKey('contract-chat-collapse')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('contract-chat-pane')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('contract-chat-expand')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('contract-chat-pane')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('contracts-list-crumb')));
    await tester.pumpAndSettle();
    expect(_appBarText('Design › Modèles & Contrats'), findsOneWidget);
    expect(entryPage, findsNothing);
    expect(find.byType(SuperTreeView), findsOneWidget);
    expect(find.text('sales'), findsOneWidget);
    // L’éditeur est resté vivant pendant l’affichage de la fiche.
    expect(
      tester.state<CodeEditorState>(find.byType(CodeEditor)),
      same(editor),
    );
    // Le détail et le chat suivent l’entrée déplacée dans le DSL (même ID).
    editor.controller.fullText =
        'components:\n  sales: flatfile # ventes\n'
        'models:\n  events: eventxpayloaddto\n';
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    contracts = controller.domainCatalog.domains.last.contracts!;
    expect(contracts.source, startsWith('components:'));
    expect(contracts.objects[salesId]?.attributes, hasLength(3));
    expect(contracts.chats[salesId], hasLength(2));
    // La flèche remonte d’un niveau du fil d’Ariane : fiche → liste.
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(entryPage, findsOneWidget);
    expect(
      find.text('Mis à jour : sales (+3 attribut(s), description)'),
      findsOneWidget,
    );
    // Mêmes outils que l'étape Objets métier, restreints à l'objet du modèle.
    expect(aiService.lastToolNames, contains('focus_stage_or_object'));
    expect(aiService.lastToolNames, contains('filter_business_objects'));
    expect(
      aiService.lastToolNames,
      isNot(contains('get_requirements_summary')),
    );
    expect(aiService.lastStaticGuide, contains('focus_stage_or_object'));
    expect(
      aiService.lastStaticGuide,
      isNot(contains('get_requirements_summary')),
    );
    // L'IA sélectionne un attribut : arbre, inspecteur et trace d'outil.
    await tester.enterText(
      find.byKey(const ValueKey('contract-chat-input')),
      'Sélectionne le client',
    );
    await tester.tap(find.byKey(const ValueKey('contract-chat-send')));
    await tester.pumpAndSettle();
    final clientId = contracts.objects[salesId]!.attributes[1].id;
    expect(controller.domainModelAttributePath('rh', salesId), [clientId]);
    expect(
      find.byKey(const ValueKey('spec-attr-inspector-x-mask')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('contract-chat-tools-section')),
      findsOneWidget,
    );
    // Le tour suivant reçoit le focus et le glossaire ; l'IA filtre l'arbre.
    await controller.upsertCompanyGlossaryTerm(
      CompanyGlossaryTerm(id: 'cg_vente', term: 'Vente'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('contract-chat-input')),
      'Filtre sur montant',
    );
    await tester.tap(find.byKey(const ValueKey('contract-chat-send')));
    await tester.pumpAndSettle();
    expect(aiService.lastPrompt, contains('FOCUS COURANT'));
    expect(
      aiService.lastPrompt,
      contains('Attribut sélectionné : sales.client'),
    );
    expect(aiService.lastPrompt, contains('GLOSSAIRE D’ENTREPRISE'));
    expect(controller.domainModelFilter('rh', salesId), 'montant');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('contract-model-filter-field')),
          )
          .controller
          ?.text,
      'montant',
    );
    expect(
      find.descendant(of: treePane, matching: find.text('evenement')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('contract-model-filter-clear')));
    await tester.pumpAndSettle();
    expect(controller.domainModelFilter('rh', salesId), isEmpty);
    expect(
      find.descendant(of: treePane, matching: find.text('evenement')),
      findsOneWidget,
    );
    // « + Questions » force des questions complémentaires, comme dans la spec.
    await tester.tap(find.byKey(const ValueKey('contract-chat-ask-more')));
    await tester.pumpAndSettle();
    expect(aiService.lastPrompt, contains('+ de questions demandé'));
    expect(find.text('Quelques précisions ?'), findsOneWidget);
    await tester.tap(
      find.byTooltip('Retour à la liste des modèles et contrats'),
    );
    await tester.pumpAndSettle();
    expect(entryPage, findsNothing);
    expect(find.byType(SuperTreeView), findsOneWidget);
    // Changer de domaine ferme la fiche et rétablit le titre de la liste.
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choisir un domaine'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'OMS'));
    await tester.pumpAndSettle();
    expect(_appBarText('Design › Modèles & Contrats'), findsOneWidget);
    // Depuis la fiche, un clic sur Design dans le rail revient directement au menu Design.
    await tester.tap(find.byTooltip('Choisir un domaine'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'RH'));
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Design'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesignLinksView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      findsNothing,
    );
    // Depuis la liste, le bouton retour de l'AppBar remonte au menu Design.
    await tester.tap(find.text('Modèles & Contrats'));
    await tester.pumpAndSettle();
    expect(find.byType(SuperTreeView), findsOneWidget);
    await tester.tap(find.byTooltip('Retour au menu Design'));
    await tester.pumpAndSettle();
    expect(find.byType(DesignLinksView), findsOneWidget);
  });

  testWidgets(
    'NavigationRail gauche : Spec affiche le menu Spec (Projets et Wizard), Design affiche la page de liens et Build affiche la vue de suivi par domaine',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        domainCatalogStore: _MemoryDomainCatalogStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('spec-forge-nav-rail')), findsOneWidget);
      expect(_appBarText('Spec'), findsOneWidget);
      expect(find.widgetWithText(NavigationRail, 'Spec'), findsOneWidget);
      expect(find.text('Design'), findsOneWidget);
      expect(find.text('Build'), findsOneWidget);

      // Onglet Spec : affiche le dicton d'Alberto Brandolini en haut, puis « Entreprise » et « Projets & Spécification ».
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('spec-quote-banner')), findsOneWidget);
      expect(find.text(SpecLinksView.quoteText), findsOneWidget);
      expect(find.text('— Alberto Brandolini'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('spec-quote-banner'))).dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('spec-section-header-enterprise')),
              )
              .dy,
        ),
      );
      expect(find.text('Entreprise'), findsOneWidget);
      expect(find.text('Projets & Spécification'), findsOneWidget);
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('spec-section-header-enterprise')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(
                  const ValueKey('spec-section-header-spec_workspace'),
                ),
              )
              .dy,
        ),
      );
      expect(find.text('Projets'), findsOneWidget);
      expect(find.text('Wizard de spécification'), findsOneWidget);
      expect(find.text('Glossaire d’entreprise'), findsOneWidget);
      expect(find.text('Dictionnaire technique & Modèle'), findsOneWidget);
      expect(find.text('Aucun projet actif'), findsOneWidget);
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('spec-link-company_glossary')),
            )
            .dy,
        tester
            .getTopLeft(
              find.byKey(const ValueKey('spec-link-modeling_dictionary')),
            )
            .dy,
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('spec-link-company_glossary')),
            )
            .dx,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('spec-link-modeling_dictionary')),
              )
              .dx,
        ),
      );

      // Replier puis déplier « Entreprise » vérifie que Glossaire d'entreprise en fait bien partie.
      await tester.tap(
        find.byKey(const ValueKey('spec-section-header-enterprise')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Glossaire d’entreprise'), findsNothing);
      expect(find.text('Projets'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('spec-section-header-enterprise')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Glossaire d’entreprise'), findsOneWidget);

      // Clic sur Glossaire d'entreprise depuis Spec -> sous-vue puis retour via spec-forge-appbar-back-btn.
      await tester.tap(
        find.byKey(const ValueKey('spec-link-company_glossary')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('company-glossary-view')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('spec-subview-back-btn')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('spec-link-modeling_dictionary')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('model-dictionary-view')),
        findsOneWidget,
      );
      expect(
        _appBarText('Spec › Dictionnaire technique & Modèle'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );

      // Le bouton Projets n'est pas dans l'AppBar.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Projets'),
        ),
        findsNothing,
      );

      // Clic sur Wizard sans projet actif -> SnackBar d'invitation.
      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Aucun projet actif — ouvrez ou créez un projet dans Projets',
        ),
        findsOneWidget,
      );

      // Clic sur Projets -> ouvre IdeaLauncherView, puis retour au menu Spec via l'AppBar.
      await tester.tap(find.byKey(const ValueKey('spec-link-projects')));
      await tester.pumpAndSettle();
      expect(_appBarText('Spec › Projets'), findsOneWidget);
      expect(find.text('Nouvelle forge à partir d’une idée'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );

      // Création d'un projet : le bouton Projets reste absent de l'AppBar et Spec garde le menu d'abord.
      await controller.createProjectFromIdea(
        idea: 'Gestion des devis',
        name: 'DevisApp',
        autoKickoff: false,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Projets'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );
      expect(find.text('DevisApp'), findsOneWidget);

      // Ouverture du Wizard -> bouton retour centralisé dans l'AppBar présent et fonctionnel.
      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
        findsOneWidget,
      );

      // Re-clic sur l'item Spec actif dans le rail ramène au menu Spec.
      expect(_appBarText('Lexique métier — DevisApp'), findsOneWidget);
      await controller.goToStage(SpecForgeStage.vision);
      await tester.pumpAndSettle();
      expect(_appBarText('Cadrage & Acteurs — DevisApp'), findsOneWidget);
      await tester.tap(find.text('Spec').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsOneWidget,
      );

      // Ouvrir Projets puis revenir ne ferme pas le projet actif.
      await tester.tap(
        find.byKey(const ValueKey('spec-link-company_glossary')),
      );
      await tester.pumpAndSettle();
      expect(_appBarText('Spec › Glossaire d’entreprise'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('spec-link-projects')));
      await tester.pumpAndSettle();
      expect(controller.project?.name, 'DevisApp');
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
        findsOneWidget,
      );

      // Onglet Design accessible même avec ou sans projet ouvert.
      await tester.tap(find.text('Design'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-design-view')),
        findsOneWidget,
      );
      expect(find.text('Nouvelle forge à partir d’une idée'), findsNothing);

      // Vérifie les deux sections (urbaniste & architecte en premier) et les 9 liens de Design.
      expect(find.text('Pour l’urbaniste & architecte'), findsOneWidget);
      expect(find.text('Pour le concepteur backend'), findsOneWidget);
      expect(find.text('Glossaire d’entreprise'), findsNothing);
      expect(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey('design-section-header-urban_planner_architect'),
              ),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(
                  const ValueKey('design-section-header-backend_designer'),
                ),
              )
              .dy,
        ),
      );
      expect(find.text('Gestion des domaines'), findsOneWidget);
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('design-link-domain_management')),
            )
            .dx,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('design-link-systems_services')),
              )
              .dx,
        ),
      );
      expect(find.text('Dictionnaire technique & Modèle'), findsNothing);
      expect(find.text('Modèles & Contrats'), findsOneWidget);
      expect(find.text('Mapping sortant'), findsOneWidget);
      expect(find.text('Cas d’usage & orchestration'), findsOneWidget);
      expect(find.text('Points d’entrée entrants'), findsOneWidget);
      expect(find.text('Adaptateurs d’infrastructure'), findsOneWidget);
      expect(find.text('Systèmes & Services'), findsOneWidget);
      expect(find.text('Cartes des flux système'), findsOneWidget);

      // Gestion des domaines : ouvre le catalogue puis revient au menu Design.
      await tester.tap(
        find.byKey(const ValueKey('design-link-domain_management')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('domain-management-view')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('domain-management-add-domain-btn')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('domain-code-field')),
        'billing-domain',
      );
      await tester.enterText(
        find.byKey(const ValueKey('domain-name-field')),
        'Facturation',
      );
      await tester.tap(find.byKey(const ValueKey('domain-save-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Facturation'), findsNWidgets(2));
      expect(_appBarText('Gestion des domaines › Facturation'), findsOneWidget);
      final catalog = controller.domainCatalog;
      await controller.updateDomainCatalog(
        catalog.copyWith(
          domains: [catalog.domains.single.copyWith(name: 'Comptabilité')],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        _appBarText('Gestion des domaines › Comptabilité'),
        findsOneWidget,
      );
      expect(find.textContaining('billing-domain'), findsNWidgets(2));
      await tester.tap(
        find.byKey(const ValueKey('domain-add-environment-btn')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('environment-code-field')),
        'review-pr-12',
      );
      await tester.enterText(
        find.byKey(const ValueKey('environment-name-field')),
        'Revue 12',
      );
      await tester.tap(find.byKey(const ValueKey('environment-save-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Revue 12'), findsOneWidget);
      expect(find.textContaining('review-pr-12'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-design-view')),
        findsOneWidget,
      );

      // Replier puis déplier la section concepteur backend.
      await tester.tap(
        find.byKey(const ValueKey('design-section-header-backend_designer')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Systèmes & Services'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('design-section-header-backend_designer')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dictionnaire technique & Modèle'), findsNothing);

      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      expect(_appBarText('Build'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-forge-build-view')),
        findsOneWidget,
      );
      expect(find.text('Items de design & avancement'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
        findsNothing,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Spec'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-forge-spec-menu-view')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Stopper une réflexion IA en cours via le bouton Arrêter', (
    WidgetTester tester,
  ) async {
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

    await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
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
  });

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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      await controller.sendUserMessage('Vérifie le lexique et lance un audit');
      await tester.pumpAndSettle();

      expect(toolAi.roundCount, 2);
      expect(toolAi.secondRoundHasFunctionResponse, isTrue);
      expect(
        find.byKey(const ValueKey('spec-chat-tools-section')),
        findsOneWidget,
      );
      expect(find.textContaining('2 outils utilisés'), findsOneWidget);

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
      expect(_appBarText('Question'), findsOneWidget);
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
      expect(_appBarText('Question — OrderSuite'), findsOneWidget);

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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
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
            'super-tree-row-spec-objects-tree-obj_article-nodes[0]',
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

      final savedAttr =
          controller.project!.businessObjects.single.attributes.single;
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
      await tester.tap(
        find.byKey(const ValueKey('spec-attr-toggle-json-schema')),
      );
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      final rowFinder = find.byKey(
        const ValueKey('super-tree-row-spec-objects-tree-obj_produit-nodes[0]'),
      );
      expect(rowFinder, findsOneWidget);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(rowFinder));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(
        find.byKey(const ValueKey('spec-tree-node-tooltip-card')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 600));
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
      final htmlContent = await tester.runAsync(
        () => renderedFile!.readAsString(),
      );
      expect(htmlContent, contains('erDiagram'));
      expect(htmlContent, contains('ssf-mermaid-card'));
      expect(htmlContent, contains('renderMathInElement'));

      // Toggle Sommaire (TOC), Thème, Impression PDF et Navigateur.
      await tester.tap(find.byKey(const ValueKey('spec-md-viewer-toggle-toc')));
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
      seedEditorState.controller.fullText =
          '{"clients": [{"raisonSociale": 123}]}';
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
      final htmlDoc = await tester.runAsync(
        () => renderedHtmlFile!.readAsString(),
      );
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
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      // Le bouton « Préférences du modèle » a bien été retiré de Spec > Objets métiers.
      expect(
        find.byKey(const ValueKey('spec-objects-prefs-btn')),
        findsNothing,
      );

      // Navigation vers Spec -> Dictionnaire technique & Modèle.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Spec'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-link-modeling_dictionary')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('model-dictionary-view')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('model-dict-live-json-preview')),
        findsOneWidget,
      );
      expect(find.text('*Number'), findsOneWidget);
      expect(find.text('*Ref'), findsOneWidget);

      // Section 2 : Identifiants (ULID)
      await tester.tap(
        find.byKey(const ValueKey('model-dict-id-strategy-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ULID (26 car.)').last);
      await tester.pumpAndSettle();

      // Section 1 : Langues & Nommage (snake_case + SCREAMING_SNAKE_CASE)
      await tester.tap(find.byKey(const ValueKey('model-dict-section-naming')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('model-dict-enum-lang-dropdown')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('model-dict-attr-case-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('snake_case (ex. delivery_address)').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('model-dict-enum-case-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('SCREAMING_SNAKE_CASE (ex. PENDING_APPROVAL)').last,
      );
      await tester.pumpAndSettle();

      // Section 5 : Contraintes JSON Schema (Strict)
      await tester.tap(find.byKey(const ValueKey('model-dict-section-schema')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('model-dict-schema-strictness-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Strict (additionalProperties: false)').last);
      await tester.pumpAndSettle();

      // Section 6 : Dictionnaire des règles -> ajout d'une règle technique
      await tester.tap(find.byKey(const ValueKey('model-dict-section-rules')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model-dict-add-rule-btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('model-dict-rule-field-name')),
        'Suffixe *Token',
      );
      await tester.enterText(
        find.byKey(const ValueKey('model-dict-rule-field-pattern')),
        '*Token',
      );
      await tester.enterText(
        find.byKey(const ValueKey('model-dict-rule-field-when')),
        'Jeton technique opaque à durée de vie limitée.',
      );
      await tester.tap(find.byKey(const ValueKey('model-dict-rule-save-btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('model-dict-rules-search')),
        'Token',
      );
      await tester.pumpAndSettle();
      expect(find.text('Suffixe *Token'), findsOneWidget);

      // Section 7 : Régional & Consignes IA
      await tester.tap(find.byKey(const ValueKey('model-dict-section-locale')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('model-dict-custom-instructions-field')),
        'Prefix booleans with is',
      );
      await tester.pumpAndSettle();

      // Onglet Aperçu Prompt IA
      await tester.tap(find.text('Prompt IA'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('model-dict-live-prompt-preview')),
        findsOneWidget,
      );

      // Application de la casse au projet actif
      await tester.tap(
        find.byKey(const ValueKey('model-dict-apply-case-project-btn')),
      );
      await tester.pumpAndSettle();

      final savedPrefs = controller.modelPreferences;
      expect(savedPrefs.attributeLanguage, 'en');
      expect(savedPrefs.enumLanguage, 'en');
      expect(savedPrefs.attributeCase, AttributeNamingCase.snakeCase);
      expect(savedPrefs.enumCase, EnumValueNamingCase.screamingSnakeCase);
      expect(savedPrefs.idStrategy, PrimaryIdStrategy.ulid);
      expect(savedPrefs.schemaStrictness, JsonSchemaStrictness.strict);
      expect(savedPrefs.customInstructions, 'Prefix booleans with is');
      expect(
        savedPrefs.technicalRules.any((r) => r.suffixOrPattern == '*Token'),
        isTrue,
      );
      expect(
        controller.project!.businessObjects.single.attributes.first.name,
        'date_mise_en_service',
      );
      expect(
        controller.project!.businessObjects.single.attributes[1].enumValues,
        ['EN_COURS', 'ARCHIVE'],
      );

      // Retour dans Spec > Objets métiers et lancement de l'IA -> reçoit les règles globales.
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('spec-stage-start-ai')));
      await tester.pumpAndSettle();

      expect(fakeAi.calledStages, [SpecForgeStage.businessObjects]);
      expect(fakeAi.receivedPrompts.single, contains('English (en)'));
      expect(fakeAi.receivedPrompts.single, contains('snake_case'));
      expect(fakeAi.receivedPrompts.single, contains('SCREAMING_SNAKE_CASE'));
      expect(fakeAi.receivedPrompts.single, contains('ULID'));
      expect(fakeAi.receivedPrompts.single, contains('*Token'));
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

  testWidgets(
    'Écran d’accueil : exemples d’idées (CRM B2B, Comptabilité, Budget IT, etc.) pré-remplissent le formulaire',
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

      await tester.tap(find.byKey(const ValueKey('spec-link-projects')));
      await tester.pumpAndSettle();

      for (final expectedTitle in const [
        'Gestion de flotte automobile',
        'Location & maintenance matériels',
        'Portail SAV & tickets clients',
        'CRM B2B',
        'Comptabilité',
        'Gestion RH & Paie',
        'E-commerce & Stocks',
        'Gestion de projets & Facturation temps',
        'Gestion de budget IT',
      ]) {
        expect(find.text(expectedTitle), findsOneWidget);
      }

      await tester.tap(find.text('CRM B2B'));
      await tester.pumpAndSettle();

      final nameField = tester.widget<TextField>(find.byType(TextField).at(0));
      final ideaField = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(nameField.controller!.text, 'CRM B2B');
      expect(ideaField.controller!.text, contains('pipeline'));

      final budgetItChip = find.text('Gestion de budget IT');
      await tester.ensureVisible(budgetItChip);
      await tester.pumpAndSettle();
      await tester.tap(budgetItChip);
      await tester.pumpAndSettle();
      expect(nameField.controller!.text, 'Gestion de budget IT');
      expect(ideaField.controller!.text, contains('CAPEX/OPEX'));

      final startWizardButton = find.text(
        'Démarrer le wizard (Étape 1 : Lexique métier)',
      );
      await tester.ensureVisible(startWizardButton);
      await tester.pumpAndSettle();
      await tester.tap(startWizardButton);
      await tester.pumpAndSettle();

      expect(controller.project, isNotNull);
      expect(controller.project!.name, 'Gestion de budget IT');
      expect(find.byKey(const ValueKey('spec-stage-start-ai')), findsOneWidget);
    },
  );

  testWidgets(
    'Spec -> Glossaire d’entreprise : CRUD, filtres, import CSV, assistant IA et passerelle Étape 1',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final glossaryAi = _CompanyGlossaryFakeAiService();
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        glossaryStore: _MemoryCompanyGlossaryStore(),
        aiService: glossaryAi,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      // 1. Accès au Glossaire d'entreprise depuis le menu Spec (sans projet actif).
      await tester.tap(
        find.byKey(const ValueKey('spec-link-company_glossary')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('company-glossary-view')),
        findsOneWidget,
      );

      // 2. Ajout manuel d'un terme d'entreprise avec statut, domaine et termes à proscrire.
      await tester.tap(
        find.byKey(const ValueKey('company-glossary-add-term-btn')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('company-glossary-field-term')),
        'Bon de livraison',
      );
      await tester.enterText(
        find.byKey(const ValueKey('company-glossary-field-domain')),
        'Logistique',
      );
      await tester.enterText(
        find.byKey(const ValueKey('company-glossary-field-tech')),
        'DeliveryNote',
      );
      await tester.enterText(
        find.byKey(const ValueKey('company-glossary-field-definition')),
        'Preuve de remise des marchandises.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('company-glossary-field-forbidden')),
        'Ticket sortie',
      );
      await tester.tap(
        find.byKey(const ValueKey('company-glossary-save-term-btn')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bon de livraison'), findsOneWidget);
      expect(find.text('DeliveryNote'), findsOneWidget);
      expect(find.text('Ticket sortie'), findsOneWidget);

      final blTerm = controller.companyGlossary.terms.firstWhere(
        (t) => t.term == 'Bon de livraison',
      );
      expect(blTerm.createdAt, isNotNull);
      expect(blTerm.updatedAt, isNotNull);
      expect(
        find.byKey(ValueKey('company-glossary-dates-${blTerm.id}')),
        findsOneWidget,
      );
      expect(find.textContaining('Ajouté le '), findsAtLeastNWidgets(1));
      expect(find.textContaining('Modifié le '), findsAtLeastNWidgets(1));

      // Vérifie le sélecteur de tri (Modifiés récemment / Ajoutés récemment).
      await tester.tap(find.byKey(const ValueKey('company-glossary-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifiés récemment').last);
      await tester.pumpAndSettle();
      expect(find.text('Bon de livraison'), findsOneWidget);

      // 3. Import CSV via la modale Importer / Exporter.
      await tester.tap(
        find.byKey(const ValueKey('company-glossary-import-export-btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importer (JSON / CSV)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('company-glossary-import-text-input')),
        'term,status,domain,definition\nFacture,draft,Finance,Pièce comptable',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('+1 ajout(s)'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('company-glossary-apply-import')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Facture'), findsOneWidget);

      // 4. Filtrage par statut Brouillon.
      await tester.tap(
        find.byKey(const ValueKey('company-glossary-filter-draft')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Facture'), findsOneWidget);
      expect(find.text('Bon de livraison'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('company-glossary-filter-all')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bon de livraison'), findsOneWidget);

      // 5. Assistant IA du glossaire (VibeAskUserCard -> patch appliqué).
      await tester.enterText(
        find.byKey(const ValueKey('company-glossary-chat-input')),
        'Ajoute le terme Commande client',
      );
      await tester.tap(
        find.byKey(const ValueKey('company-glossary-chat-send')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VibeAskUserCard), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vibe-ask-user-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Commande client'), findsOneWidget);

      // 6. Passerelle avec l'étape 1 d'un projet (Import + Promotion).
      await controller.createProjectFromIdea(
        idea: 'Gestion commerciale',
        autoKickoff: false,
      );
      await tester.tap(
        find.byKey(const ValueKey('spec-forge-appbar-back-btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('spec-lexicon-import-company-glossary')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-lexicon-confirm-company-import')),
      );
      await tester.pumpAndSettle();

      expect(
        controller.project!.lexicon.terms.any(
          (t) => t.term == 'Bon de livraison',
        ),
        isTrue,
      );

      // Promotion d'un terme projet vers le glossaire d'entreprise.
      final importedBl = controller.project!.lexicon.terms.firstWhere(
        (t) => t.term == 'Bon de livraison',
      );
      await tester.tap(
        find.byKey(ValueKey('spec-lexicon-promote-${importedBl.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          '« Bon de livraison » mis à jour dans le glossaire d’entreprise.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'LexiconEditorView indique si chaque notion existe ou non dans le lexique entreprise et permet de filtrer',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.upsertCompanyGlossaryTerm(
        CompanyGlossaryTerm(
          id: 'cg_bl',
          term: 'Bon de livraison',
          synonyms: const ['BL'],
          forbiddenTerms: const ['Ticket sortie'],
          status: CompanyGlossaryStatus.approved,
        ),
      );

      await controller.createProjectFromIdea(
        idea: 'Suivi des expéditions',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          lexicon: SpecLexicon(
            terms: [
              LexiconTerm(id: 'l_exact', term: 'Bon de livraison'),
              LexiconTerm(id: 'l_syn', term: 'BL'),
              LexiconTerm(id: 'l_forb', term: 'Ticket sortie'),
              LexiconTerm(id: 'l_absent', term: 'Palette Europe'),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LexiconEditorView(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('spec-lexicon-company-status-l_exact')),
          matching: find.text('Dans le lexique entreprise · Validé'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('spec-lexicon-company-status-l_syn')),
          matching: find.text(
            'Dans le lexique entreprise · Synonyme de « Bon de livraison »',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('spec-lexicon-company-status-l_forb')),
          matching: find.text(
            'Proscrit dans le lexique entreprise → « Bon de livraison »',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('spec-lexicon-company-status-l_absent'),
          ),
          matching: find.text('Absent du lexique entreprise'),
        ),
        findsOneWidget,
      );

      // Filtrer sur les notions absentes du lexique entreprise.
      await tester.tap(
        find.byKey(const ValueKey('spec-lexicon-filter-absent')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Palette Europe'), findsOneWidget);
      expect(find.text('Bon de livraison'), findsNothing);

      // Filtrer sur les notions présentes dans le lexique entreprise.
      await tester.tap(
        find.byKey(const ValueKey('spec-lexicon-filter-in-company')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bon de livraison'), findsOneWidget);
      expect(find.text('Palette Europe'), findsNothing);

      // Revenir à tous et promouvoir la notion absente -> statut mis à jour.
      await tester.tap(find.byKey(const ValueKey('spec-lexicon-filter-all')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-lexicon-promote-l_absent')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('spec-lexicon-company-status-l_absent'),
          ),
          matching: find.text('Dans le lexique entreprise · Validé'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Arbre & Inspecteur : ListView de repositories dépliables (1er déplié, badges Agrégat/Entité liée et sélection)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion des commandes',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.businessObjects,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_commande',
              name: 'Commande Client',
              technicalName: 'CommandeClient',
              aggregateRoot: true,
              attributes: [
                BusinessAttribute(
                  id: 'a_ref',
                  name: 'referenceCommande',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
              ],
            ),
            BusinessObjectSpec(
              id: 'obj_ligne',
              name: 'Ligne Commande',
              technicalName: 'LigneCommande',
              aggregateRoot: false,
              attributes: [
                BusinessAttribute(
                  id: 'a_qte',
                  name: 'quantiteLigne',
                  type: BusinessAttributeType.integer,
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      // 1. Les deux repositories apparaissent avec leurs alias et badges Agrégat / Entité liée.
      expect(find.text('Objets métiers (2)'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('spec-objects-repo-tile-obj_commande')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-objects-repo-tile-obj_ligne')),
        findsOneWidget,
      );
      expect(find.text('commande_client · CommandeClient'), findsOneWidget);
      expect(find.text('ligne_commande · LigneCommande'), findsOneWidget);
      expect(find.text('Agrégat'), findsOneWidget);
      expect(find.text('Entité liée'), findsOneWidget);
      expect(find.text('Valide'), findsNWidgets(2));

      // 2. Seul le premier repository est déplié par défaut (mode un seul objet ouvert = true).
      expect(controller.modelPreferences.singleExpandedBusinessObject, isTrue);
      expect(
        find.byKey(const ValueKey('spec-objects-expand-all')),
        findsNothing,
      );
      expect(find.byType(SuperTreeView), findsOneWidget);
      expect(find.text('referenceCommande'), findsAtLeastNWidgets(1));
      expect(find.text('quantiteLigne'), findsNothing);
      expect(find.text('Commande Client (CommandeClient)'), findsOneWidget);

      // 3. Dépliage du second repository via son bouton chevron -> replie automatiquement le premier.
      await tester.tap(
        find.byKey(const ValueKey('spec-objects-repo-toggle-obj_ligne')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SuperTreeView), findsOneWidget);
      expect(find.text('quantiteLigne'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(
          const ValueKey(
            'super-tree-row-spec-objects-tree-obj_commande-nodes[0]',
          ),
        ),
        findsNothing,
      );

      // 4. Sélection de l'attribut `quantiteLigne` dans le second SuperTreeView -> inspecteur d'attribut.
      await tester.tap(
        find.byKey(
          const ValueKey('super-tree-row-spec-objects-tree-obj_ligne-nodes[0]'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('quantiteLigne'), findsAtLeastNWidgets(2));
      expect(find.text('LigneCommande'), findsOneWidget);

      // 5. Désactivation de l'option -> plusieurs objets peuvent être dépliés simultanément.
      await controller.updateModelPreferences(
        controller.modelPreferences.copyWith(
          singleExpandedBusinessObject: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-objects-expand-all')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('spec-objects-repo-toggle-obj_commande')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SuperTreeView), findsNWidgets(2));
      expect(find.text('referenceCommande'), findsAtLeastNWidgets(1));
      expect(find.text('quantiteLigne'), findsAtLeastNWidgets(1));

      // 6. Réactivation de l'option -> ne conserve qu'un seul objet métier ouvert.
      await controller.updateModelPreferences(
        controller.modelPreferences.copyWith(
          singleExpandedBusinessObject: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SuperTreeView), findsOneWidget);
    },
  );

  testWidgets(
    'Préférences du modèle : option un seul objet métier ouvert (défaut true) dans le dialogue et JSON',
    (WidgetTester tester) async {
      final prefsJson = BusinessObjectModelPreferences.defaults.toJson();
      expect(prefsJson['singleExpandedBusinessObject'], isTrue);
      final parsedFalse = BusinessObjectModelPreferences.fromJson({
        ...prefsJson,
        'singleExpandedBusinessObject': false,
      });
      expect(parsedFalse.singleExpandedBusinessObject, isFalse);

      ModelPreferencesDialogResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showBusinessObjectModelPreferencesDialog(
                    context,
                    initialPreferences: BusinessObjectModelPreferences.defaults,
                    hasExistingObjects: false,
                  );
                },
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Schéma & Relations'));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('spec-objects-single-expanded-switch'),
      );
      await tester.drag(
        find.byKey(const ValueKey('spec-objects-relation-style-dropdown')),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-objects-prefs-save')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.preferences.singleExpandedBusinessObject, isFalse);
    },
  );

  testWidgets(
    'Arbre & Inspecteur : en-têtes de repositories sticky en SliverMainAxisGroup lors du scroll',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Inventaire détaillé',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.businessObjects,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_article_long',
              name: 'Article Long',
              technicalName: 'ArticleLong',
              aggregateRoot: true,
              attributes: [
                for (var i = 0; i < 30; i++)
                  BusinessAttribute(
                    id: 'a_long_$i',
                    name: 'champ_$i',
                    type: BusinessAttributeType.string,
                  ),
              ],
            ),
            BusinessObjectSpec(
              id: 'obj_depot',
              name: 'Dépôt',
              technicalName: 'Depot',
              aggregateRoot: true,
              attributes: [
                BusinessAttribute(
                  id: 'a_dep',
                  name: 'codeDepot',
                  type: BusinessAttributeType.string,
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      final scrollFinder = find.byKey(
        const ValueKey('spec-objects-repo-listview'),
      );
      expect(tester.widget(scrollFinder), isA<CustomScrollView>());
      final headerFinder = find.byKey(
        const ValueKey('spec-objects-repo-tile-obj_article_long'),
      );
      final initialTop = tester.getTopLeft(headerFinder).dy;

      // Scroll modéré dans le premier repository : son en-tête reste épinglé en haut.
      await tester.drag(scrollFinder, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(headerFinder, findsOneWidget);
      expect(
        (tester.getTopLeft(headerFinder).dy - initialTop).abs(),
        lessThan(1.0),
      );
    },
  );

  testWidgets(
    'Attribut enum : tableau avec x-enumNames et x-enumDescriptions dans l’inspecteur, le dialogue et le JSON Schema',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Workflow demandes',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.businessObjects,
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_demande',
              name: 'Demande',
              technicalName: 'Demande',
              attributes: [
                BusinessAttribute(
                  id: 'a_statut',
                  name: 'statut',
                  type: BusinessAttributeType.enumeration,
                  required: true,
                  enumValues: const ['pending', 'approved'],
                  schemaConstraints: JsonSchemaConstraints(
                    extraKeywords: const {
                      'x-enumNames': ['En attente', 'Approuvée'],
                      'x-enumDescriptions': [
                        'La demande n’a pas encore été traitée',
                        'La demande a été validée',
                      ],
                    },
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      // 1. Sélection de l'attribut `statut` -> tableau enum affiché dans l'inspecteur.
      await tester.tap(
        find.byKey(
          const ValueKey(
            'super-tree-row-spec-objects-tree-obj_demande-nodes[0]',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-attr-inspector-enum-table')),
        findsOneWidget,
      );
      expect(find.text('En attente'), findsOneWidget);
      expect(find.text('Approuvée'), findsOneWidget);
      expect(
        find.text('La demande n’a pas encore été traitée'),
        findsOneWidget,
      );
      expect(find.text('La demande a été validée'), findsOneWidget);

      // 2. Ouvre le dialogue d'édition -> tableau éditable avec ajout d'un 3e choix.
      await tester.tap(find.byTooltip('Modifier'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-attr-enum-table')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('spec-attr-enum-add-row')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('spec-attr-enum-value-2')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('spec-attr-enum-value-2')),
        'refused',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('spec-attr-enum-name-2')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('spec-attr-enum-name-2')),
        'Refusée',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('spec-attr-enum-desc-2')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('spec-attr-enum-desc-2')),
        'La demande a été refusée',
      );

      await tester.tap(find.byKey(const ValueKey('spec-attr-save-btn')));
      await tester.pumpAndSettle();

      final errFinder = find.byKey(
        const ValueKey('spec-attr-validation-error'),
      );
      if (errFinder.evaluate().isNotEmpty) {
        final errText = tester
            .widget<Text>(
              find.descendant(of: errFinder, matching: find.byType(Text)),
            )
            .data;
        fail('Validation error in dialog: $errText');
      }
      expect(find.byKey(const ValueKey('spec-attr-save-btn')), findsNothing);

      final savedAttr =
          controller.project!.businessObjects.single.attributes.single;
      expect(savedAttr.enumValues, ['pending', 'approved', 'refused']);
      expect(savedAttr.schemaConstraints.enumNames, [
        'En attente',
        'Approuvée',
        'Refusée',
      ]);
      expect(savedAttr.schemaConstraints.enumDescriptions, [
        'La demande n’a pas encore été traitée',
        'La demande a été validée',
        'La demande a été refusée',
      ]);

      final jsonSchema = SpecSuperDesignerExporter.attributeToJsonSchema(
        savedAttr,
      );
      expect(jsonSchema['enum'], ['pending', 'approved', 'refused']);
      expect(jsonSchema['x-enumNames'], ['En attente', 'Approuvée', 'Refusée']);
      expect(jsonSchema['x-enumDescriptions'], [
        'La demande n’a pas encore été traitée',
        'La demande a été validée',
        'La demande a été refusée',
      ]);
      expect(find.text('Refusée'), findsOneWidget);
      expect(find.text('La demande a été refusée'), findsOneWidget);
    },
  );

  testWidgets(
    'Extensions x-mask et x-searchable : édition dans les propriétés, affichage inspecteur et consignes IA',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final agent = SpecStageAgent.forStage(SpecForgeStage.businessObjects);
      expect(agent.systemInstruction, contains('x-enumNames'));
      expect(agent.systemInstruction, contains('x-enumDescriptions'));
      expect(agent.systemInstruction, contains('x-mask'));
      expect(agent.systemInstruction, contains('x-searchable'));
      expect(agent.systemInstruction, contains('x-database-index'));
      expect(agent.patchSchemaGuide, contains('"x-mask"'));
      expect(agent.patchSchemaGuide, contains('"x-searchable"'));
      expect(agent.patchSchemaGuide, contains('"x-database-index"'));
      expect(agent.patchSchemaGuide, contains('"x-enumNames"'));
      expect(agent.patchSchemaGuide, contains('"x-enumDescriptions"'));

      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion parc',
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
                  id: 'a_plaque',
                  name: 'immatriculation',
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey(
            'super-tree-row-spec-objects-tree-obj_vehicule-nodes[0]',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Modifier'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Contraintes JSON Schema'));
      await tester.pumpAndSettle();

      final maskField = find.byKey(const ValueKey('spec-attr-x-mask-field'));
      await tester.ensureVisible(maskField);
      await tester.pumpAndSettle();
      await tester.enterText(maskField, 'UU-###-UU');

      final searchDropdown = find.byKey(
        const ValueKey('spec-attr-x-searchable-dropdown'),
      );
      await tester.ensureVisible(searchDropdown);
      await tester.pumpAndSettle();
      await tester.tap(searchDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recherchable (true)').last);
      await tester.pumpAndSettle();

      final dbIndexDropdown = find.byKey(
        const ValueKey('spec-attr-x-database-index-dropdown'),
      );
      await tester.ensureVisible(dbIndexDropdown);
      await tester.pumpAndSettle();
      await tester.tap(dbIndexDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Indexé en base (true)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-attr-save-btn')));
      await tester.pumpAndSettle();

      final saved =
          controller.project!.businessObjects.single.attributes.single;
      expect(saved.schemaConstraints.xMask, 'UU-###-UU');
      expect(saved.schemaConstraints.xSearchable, isTrue);
      expect(saved.schemaConstraints.xDatabaseIndex, isTrue);

      final schema = SpecSuperDesignerExporter.attributeToJsonSchema(saved);
      expect(schema['x-mask'], 'UU-###-UU');
      expect(schema['x-searchable'], isTrue);
      expect(schema['x-database-index'], isTrue);

      expect(
        find.byKey(const ValueKey('spec-attr-inspector-x-mask')),
        findsOneWidget,
      );
      expect(find.text('x-mask: UU-###-UU'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const ValueKey('spec-attr-inspector-x-searchable')),
        findsOneWidget,
      );
      expect(find.text('x-searchable'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const ValueKey('spec-attr-inspector-x-database-index')),
        findsOneWidget,
      );
      expect(find.text('x-database-index'), findsAtLeastNWidgets(1));

      // Lorsqu'ils valent false, ils ne sont pas affichés dans la visu des propriétés.
      await tester.tap(find.byTooltip('Modifier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contraintes JSON Schema'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('spec-attr-x-searchable-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-attr-x-searchable-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Non recherchable (false)').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('spec-attr-x-database-index-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spec-attr-x-database-index-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Non indexé (false)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-attr-save-btn')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('spec-attr-inspector-x-searchable')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('spec-attr-inspector-x-database-index')),
        findsNothing,
      );
      expect(find.text('x-searchable: false'), findsNothing);
      expect(find.text('x-database-index: false'), findsNothing);
    },
  );

  testWidgets(
    'Objets métiers : filtre IHM/IA, sélection d’attribut par l’IA et injection du scope sélectionné dans le prompt',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final aiService = _ObjectScopeAndFilterAiService();
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        aiService: aiService,
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion commandes',
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
                  id: 'a_prix',
                  name: 'prixUnitaire',
                  type: BusinessAttributeType.number,
                ),
              ],
            ),
            BusinessObjectSpec(
              id: 'obj_client',
              name: 'Client',
              technicalName: 'Client',
              attributes: [
                BusinessAttribute(
                  id: 'a_adr',
                  name: 'adresse',
                  type: BusinessAttributeType.object,
                  children: [
                    BusinessAttribute(
                      id: 'a_cp',
                      name: 'codePostal',
                      type: BusinessAttributeType.string,
                      required: true,
                    ),
                    BusinessAttribute(
                      id: 'a_ville',
                      name: 'ville',
                      type: BusinessAttributeType.string,
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

      await tester.tap(find.byKey(const ValueKey('spec-link-wizard')));
      await tester.pumpAndSettle();

      // 1. Filtre IHM via l'icône loupe/filtre : filtre sur un attribut imbriqué (`codePostal`).
      expect(find.text('Objets métiers (2)'), findsNWidgets(2));
      await tester.tap(
        find.byKey(const ValueKey('spec-objects-filter-toggle')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('spec-objects-filter-field')),
        'codePostal',
      );
      await tester.pumpAndSettle();

      expect(find.text('Objets métiers (1/2)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-objects-repo-tile-obj_client')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-objects-repo-tile-obj_article')),
        findsNothing,
      );
      expect(find.text('codePostal'), findsAtLeastNWidgets(1));
      expect(find.text('ville'), findsNothing);

      // Effacement du filtre IHM.
      await tester.tap(find.byKey(const ValueKey('spec-objects-filter-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Objets métiers (2)'), findsNWidgets(2));

      // 2. Demande au chat IA de sélectionner `adresse.codePostal` sur `Client` -> outil focus_stage_or_object.
      await tester.enterText(
        find.byKey(const ValueKey('spec-chat-input')),
        'Sélectionne l’attribut codePostal de Client',
      );
      await tester.tap(find.byKey(const ValueKey('spec-chat-send')));
      await tester.pumpAndSettle();

      expect(controller.focusedObjectId, 'obj_client');
      expect(controller.focusedAttributePath, ['a_adr', 'a_cp']);
      // L'inspecteur affiche maintenant l'attribut sélectionné `codePostal`.
      expect(find.text('Client'), findsAtLeastNWidgets(1));
      expect(find.text('codePostal'), findsAtLeastNWidgets(2));

      // 3. Nouvelle demande ciblée -> le prompt transmis à l'IA inclut le scope de l'attribut sélectionné.
      await tester.enterText(
        find.byKey(const ValueKey('spec-chat-input')),
        'Modifie cet attribut',
      );
      await tester.tap(find.byKey(const ValueKey('spec-chat-send')));
      await tester.pumpAndSettle();

      expect(
        aiService.prompts.last,
        contains('FOCUS COURANT DANS L’ATELIER (SCOPE DE SÉLECTION)'),
      );
      expect(
        aiService.prompts.last,
        contains('Client.adresse.codePostal (id: a_cp'),
      );

      // 4. L'IA peut aussi filtrer les objets & attributs via `filter_business_objects`.
      await tester.enterText(
        find.byKey(const ValueKey('spec-chat-input')),
        'Filtre sur prixUnitaire',
      );
      await tester.tap(find.byKey(const ValueKey('spec-chat-send')));
      await tester.pumpAndSettle();

      expect(controller.businessObjectFilter, 'prixUnitaire');
      expect(find.text('Objets métiers (1/2)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spec-objects-repo-tile-obj_article')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'StageAiChatPane : le bouton Effacer la conversation vide les échanges de l’étape active',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = _MemorySpecProjectStore();
      final controller = SpecForgeController(
        store: store,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        domainCatalogStore: _MemoryDomainCatalogStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion des commandes clients',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          currentStage: SpecForgeStage.lexicon,
          stageStates: <SpecForgeStage, SpecStageState>{
            SpecForgeStage.lexicon: SpecStageState(
              stage: SpecForgeStage.lexicon,
              status: SpecStageStatus.inProgress,
              readyToAdvance: true,
              messages: [
                SpecChatMessage(
                  id: 'm1',
                  isUser: true,
                  text: 'Ajoute le terme Commande.',
                ),
                SpecChatMessage(
                  id: 'm2',
                  isUser: false,
                  text: 'Terme Commande ajouté.',
                ),
              ],
            ),
            SpecForgeStage.vision: SpecStageState(
              stage: SpecForgeStage.vision,
              status: SpecStageStatus.inProgress,
              messages: [
                SpecChatMessage(
                  id: 'm_vision',
                  isUser: true,
                  text: 'Vision conservée.',
                ),
              ],
            ),
          },
        ),
        recordUndo: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 760,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => StageAiChatPane(
                  controller: controller,
                  onCycleChatSize: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final clearBtn = find.byKey(const ValueKey('spec-chat-clear-btn'));
      expect(clearBtn, findsOneWidget);

      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      final lexiconState = controller.project!.stageStateFor(
        SpecForgeStage.lexicon,
      );
      expect(lexiconState.messages, isEmpty);
      expect(lexiconState.readyToAdvance, isFalse);
      expect(
        controller.project!.stageStateFor(SpecForgeStage.vision).messages,
        hasLength(1),
      );
      expect(clearBtn, findsNothing);
    },
  );

  testWidgets(
    'SuperSpecForgeApp & SpecForgeShell : hauteur réduite des AppBar (clair et sombre)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = _MemorySpecProjectStore();
      final controller = SpecForgeController(
        store: store,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        domainCatalogStore: _MemoryDomainCatalogStore(),
        aiService: _FakeSpecAiService(),
      );
      addTearDown(controller.dispose);

      await controller.createProjectFromIdea(
        idea: 'Gestion de commandes',
        name: 'Orders',
        autoKickoff: false,
      );

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.theme?.appBarTheme.toolbarHeight, 40.0);
      expect(materialApp.darkTheme?.appBarTheme.toolbarHeight, 40.0);

      final appBarBox = tester.getSize(find.byType(AppBar));
      expect(appBarBox.height, 40.0);
      expect(appBarBox.height, lessThan(kToolbarHeight));
    },
  );
}

class _ObjectScopeAndFilterAiService implements SpecAiService {
  final List<String> prompts = <String>[];

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
    final hasFunctionResponse =
        conversationContents != null &&
        conversationContents.length >= 3 &&
        (conversationContents.last['parts'] is List) &&
        (conversationContents.last['parts'] as List).any(
          (p) => p is Map && p.containsKey('functionResponse'),
        );

    if (!hasFunctionResponse) {
      prompts.add(prompt);
      final currentTurnRequest = prompt
          .split('DEMANDE UTILISATEUR POUR CE TOUR :')
          .last;
      if (currentTurnRequest.contains('Sélectionne l’attribut codePostal')) {
        yield GeminiStreamEvent(
          deltaText: '',
          accumulatedText: '',
          isDone: true,
          usedContextCache: false,
          functionCalls: [
            VibeToolCall(
              id: 'call_select_attr',
              name: 'focus_stage_or_object',
              arguments: const <String, Object?>{
                'stage': 'businessObjects',
                'objectId': 'Client',
                'attributePath': 'adresse.codePostal',
              },
            ),
          ],
        );
        return;
      }
      if (currentTurnRequest.contains('Filtre sur prixUnitaire')) {
        yield GeminiStreamEvent(
          deltaText: '',
          accumulatedText: '',
          isDone: true,
          usedContextCache: false,
          functionCalls: [
            VibeToolCall(
              id: 'call_filter',
              name: 'filter_business_objects',
              arguments: const <String, Object?>{'query': 'prixUnitaire'},
            ),
          ],
        );
        return;
      }
    }

    final json = jsonEncode({
      'message': 'Action effectuée.',
      'askUser': null,
      'specPatch': null,
      'stageReadyToAdvance': false,
    });
    yield GeminiStreamEvent(
      deltaText: json,
      accumulatedText: json,
      isDone: true,
      usedContextCache: false,
    );
  }
}

class _DomainModelFakeAiService implements SpecAiService {
  String? lastPrompt;
  String? lastStaticGuide;
  String? lastSystemInstruction;
  List<String> lastToolNames = const <String>[];

  GeminiStreamEvent _json(Map<String, Object?> payload) {
    final encoded = jsonEncode(payload);
    return GeminiStreamEvent(
      deltaText: encoded,
      accumulatedText: encoded,
      isDone: true,
      usedContextCache: false,
    );
  }

  GeminiStreamEvent _call(String name, Map<String, Object?> arguments) =>
      GeminiStreamEvent(
        deltaText: '',
        accumulatedText: '',
        isDone: true,
        usedContextCache: false,
        functionCalls: [
          VibeToolCall(id: 'call_$name', name: name, arguments: arguments),
        ],
      );

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
    final afterToolCall =
        conversationContents != null &&
        conversationContents.length >= 3 &&
        (conversationContents.last['parts'] is List) &&
        (conversationContents.last['parts'] as List).any(
          (p) => p is Map && p.containsKey('functionResponse'),
        );
    if (afterToolCall) {
      yield _json({'message': 'Action effectuée.', 'specPatch': null});
      return;
    }
    lastPrompt = prompt;
    lastStaticGuide = staticGuideOverride;
    lastSystemInstruction = systemInstructionOverride;
    lastToolNames = [for (final tool in tools) tool.name];
    final request = prompt.split('DEMANDE UTILISATEUR :').last;
    if (request.contains('Sélectionne le client')) {
      yield _call('focus_stage_or_object', const {
        'objectId': 'sales',
        'attributePath': 'client',
      });
      return;
    }
    if (request.contains('Filtre sur montant')) {
      yield _call('filter_business_objects', const {'query': 'montant'});
      return;
    }
    if (prompt.contains('+ de questions demandé')) {
      yield _json({
        'message': 'Quelques précisions ?',
        'askUser': null,
        'specPatch': null,
      });
      return;
    }
    yield _json({
      'message': 'Montant, client et événement ajoutés.',
      'askUser': null,
      'specPatch': {
        'description': 'Ventes du jour',
        'attributes': [
          {'name': 'montant', 'type': 'number', 'required': true},
          {
            'name': 'client',
            'type': 'string',
            'schemaConstraints': {'x-mask': 'CLI-####', 'x-searchable': true},
          },
          {
            'name': 'evenement',
            'type': 'reference',
            'referenceObjectId': 'events',
          },
        ],
      },
    });
  }
}

class _CompanyGlossaryFakeAiService implements SpecAiService {
  int _turn = 0;

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
    _turn++;
    final payload = _turn == 1
        ? {
            'message': 'Quel statut attribuer à Commande client ?',
            'askUser': {
              'questions': [
                {
                  'id': 'q_status',
                  'title': 'Statut initial de Commande client ?',
                  'type': 'single',
                  'options': ['Validé', 'Brouillon'],
                  'default': 'Validé',
                },
              ],
            },
            'specPatch': null,
          }
        : {
            'message': 'Terme Commande client ajouté au glossaire.',
            'askUser': null,
            'specPatch': {
              'terms': [
                {
                  'id': 'cg_commande_client',
                  'term': 'Commande client',
                  'definition': 'Engagement ferme d’achat.',
                  'domain': 'Ventes',
                  'status': 'approved',
                },
              ],
            },
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
          VibeToolCall(id: 'call_1', name: 'get_lexicon_and_synonyms'),
          VibeToolCall(id: 'call_2', name: 'run_coherence_audit'),
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
