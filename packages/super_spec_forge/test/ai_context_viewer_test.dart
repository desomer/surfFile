import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';
import 'package:super_spec_forge/widgets/design/contract_model_chat_pane.dart';

class _MemoryProjectStore extends SpecProjectStore {
  _MemoryProjectStore() : super(Directory('memory_context_viewer_store'));

  final Map<String, SpecForgeProject> _projects = {};
  String? _lastActiveId;

  @override
  Future<void> saveProject(SpecForgeProject project) async {
    _projects[project.id] = project;
    _lastActiveId = project.id;
  }

  @override
  Future<SpecForgeProject?> loadProject(String projectId) async =>
      _projects[projectId];

  @override
  Future<void> deleteProject(String projectId) async {
    _projects.remove(projectId);
  }

  @override
  Future<List<SpecProjectSummary>> listProjects() async => const [];

  @override
  Future<String?> getLastActiveProjectId() async => _lastActiveId;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {
    _lastActiveId = projectId;
  }
}

class _MemoryGlossaryStore extends CompanyGlossaryStore {
  _MemoryGlossaryStore() : super(Directory('memory_context_viewer_store'));

  CompanyGlossary _glossary = CompanyGlossary.empty;
  List<SpecChatMessage> _chat = const [];

  @override
  Future<CompanyGlossary> loadGlossary() async => _glossary;

  @override
  Future<void> saveGlossary(CompanyGlossary glossary) async {
    _glossary = glossary;
  }

  @override
  Future<List<SpecChatMessage>> loadChatMessages() async => _chat;

  @override
  Future<void> saveChatMessages(List<SpecChatMessage> messages) async {
    _chat = List<SpecChatMessage>.unmodifiable(messages);
  }
}

class _MemoryModelDictStore extends ModelDictionaryStore {
  _MemoryModelDictStore() : super(Directory('memory_context_viewer_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemoryDomainCatalogStore extends DomainCatalogStore {
  _MemoryDomainCatalogStore(this._catalog)
    : super(Directory('memory_context_viewer_store'));

  DomainCatalog _catalog;

  @override
  Future<DomainCatalog> load() async => _catalog;

  @override
  Future<void> save(DomainCatalog catalog) async {
    _catalog = catalog;
  }
}

class _MemoryEnterpriseRateCardStore extends EnterpriseRateCardStore {
  _MemoryEnterpriseRateCardStore()
    : super(Directory('memory_context_viewer_store'));

  EnterpriseRateCard _card = EnterpriseRateCard.defaults;

  @override
  Future<EnterpriseRateCard> load() async => _card;

  @override
  Future<void> save(EnterpriseRateCard card) async {
    _card = card;
  }
}

class _RecordedCall {
  _RecordedCall({
    required this.stage,
    required this.prompt,
    required this.attachments,
    required this.tools,
    required this.conversationContents,
    required this.enforceJsonResponse,
    required this.systemInstructionOverride,
    required this.staticGuideOverride,
  });

  final SpecForgeStage stage;
  final String prompt;
  final List<VibeChatAttachment> attachments;
  final List<VibeToolDeclaration> tools;
  final List<Map<String, Object?>>? conversationContents;
  final bool enforceJsonResponse;
  final String? systemInstructionOverride;
  final String? staticGuideOverride;
}

class _RecordingSpecAiService implements SpecAiService {
  final List<_RecordedCall> calls = [];
  bool emitToolCallOnFirstRound = false;

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
    calls.add(
      _RecordedCall(
        stage: stage,
        prompt: prompt,
        attachments: List<VibeChatAttachment>.from(attachments),
        tools: List<VibeToolDeclaration>.from(tools),
        conversationContents: conversationContents == null
            ? null
            : List<Map<String, Object?>>.from(conversationContents),
        enforceJsonResponse: enforceJsonResponse,
        systemInstructionOverride: systemInstructionOverride,
        staticGuideOverride: staticGuideOverride,
      ),
    );

    if (emitToolCallOnFirstRound &&
        (conversationContents == null || conversationContents.length == 1) &&
        tools.any((t) => t.name == 'get_lexicon_and_synonyms')) {
      yield GeminiStreamEvent(
        deltaText: '',
        accumulatedText: '',
        isDone: true,
        usedContextCache: false,
        functionCalls: [
          VibeToolCall(
            id: 'call_1',
            name: 'get_lexicon_and_synonyms',
            arguments: const <String, Object?>{},
          ),
        ],
      );
      return;
    }

    final payload = jsonEncode({
      'message': 'Réponse IA simulée pour le test.',
      'askUser': null,
      'readyToAdvance': false,
      'specPatch': null,
    });
    yield GeminiStreamEvent(
      deltaText: payload,
      accumulatedText: payload,
      isDone: true,
      usedContextCache: false,
    );
  }
}

Future<({
  SpecForgeController controller,
  _RecordingSpecAiService ai,
  FunctionalDomain domain,
  String entryId,
})> _buildTestFixture() async {
  final contracts = DomainContracts.parse(
    'models:\n  CommandeClient: model\n',
  );
  final entry = contracts.groups.first.children.first;
  final domain = FunctionalDomain(
    id: 'dom_sales',
    name: 'Ventes',
    domainCode: 'SALES',
    contracts: contracts,
  );
  final catalog = DomainCatalog(domains: [domain]);
  final ai = _RecordingSpecAiService();
  final controller = SpecForgeController(
    store: _MemoryProjectStore(),
    glossaryStore: _MemoryGlossaryStore(),
    modelDictionaryStore: _MemoryModelDictStore(),
    domainCatalogStore: _MemoryDomainCatalogStore(catalog),
    enterpriseRateCardStore: _MemoryEnterpriseRateCardStore(),
    aiService: ai,
  );
  await controller.initialize(restoreLastProject: false);
  await controller.createProjectFromIdea(
    idea: 'Plateforme de gestion de commandes B2B',
    name: 'OrderHub',
    autoKickoff: false,
  );
  return (controller: controller, ai: ai, domain: domain, entryId: entry.id);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'Fidélité : les 12 inspect*AiContext produisent un aperçu complet et capturent exactement le dernier envoi réel (pièces jointes + rounds outils)',
    () async {
      final fixture = await _buildTestFixture();
      final controller = fixture.controller;
      final ai = fixture.ai;
      final domain = fixture.domain;
      final entryId = fixture.entryId;

      // 1. Les 12 chats disposent immédiatement d'un aperçu en direct avant tout envoi.
      final inspections = <String, SpecAiContextInspection?>{
        'spec': controller.inspectSpecStageAiContext(),
        'global': controller.inspectGlobalQuestionAiContext(),
        'ux': controller.inspectUxStageAiContext(),
        'qa': controller.inspectQaStageAiContext(),
        'cost': controller.inspectCostStageAiContext(),
        'portfolio': controller.inspectPortfolioAiContext(),
        'glossary': controller.inspectGlossaryAiContext(),
        'domainModel': controller.inspectDomainModelAiContext(
          domain.id,
          entryId,
        ),
        'domainLayer': controller.inspectDomainLayerAiContext(
          domain.id,
          entryId,
        ),
        'useCase': controller.inspectUseCaseOrchestrationAiContext(domain.id),
        'systemsServices': controller.inspectSystemsServicesAiContext(
          domain.id,
        ),
        'valueObjectsShared': controller.inspectValueObjectsAiContext(
          scope: ValueObjectScope.shared,
        ),
        'valueObjectsDomain': controller.inspectValueObjectsAiContext(
          scope: ValueObjectScope.domain,
          domainId: domain.id,
        ),
      };
      for (final entry in inspections.entries) {
        final inspection = entry.value;
        expect(
          inspection,
          isNotNull,
          reason: 'Aperçu attendu pour ${entry.key}',
        );
        expect(inspection!.preview.isLivePreview, isTrue);
        expect(inspection.hasLastSent, isFalse);
        expect(inspection.preview.systemInstruction.trim(), isNotEmpty);
        expect(inspection.preview.staticGuide.trim(), isNotEmpty);
        expect(inspection.preview.prompt.trim(), isNotEmpty);
        expect(inspection.preview.totalChars, greaterThan(0));
      }

      // 2. Envoi réel avec pièce jointe texte + image + round d'outil sur Spec.
      ai.emitToolCallOnFirstRound = true;
      final textAttachment = VibeChatAttachment.text(
        name: 'notes.txt',
        content: 'Règle métier spécifique au client ACME.',
      );
      final imageAttachment = VibeChatAttachment.image(
        name: 'maquette.png',
        bytes: Uint8List.fromList(List<int>.filled(64, 42)),
      );
      await controller.sendUserMessage(
        'Ajoute les concepts principaux du domaine',
        attachments: [textAttachment, imageAttachment],
      );

      expect(ai.calls.length, 2); // round 0 (tool call) + round 1 (final)
      final lastInspection = controller.inspectSpecStageAiContext()!;
      expect(lastInspection.hasLastSent, isTrue);

      final lastSent = lastInspection.lastSent!;
      expect(lastSent.isLivePreview, isFalse);
      expect(
        lastSent.systemInstruction,
        GeminiSpecAiService.defaultSystemInstructionFor(
          controller.project!.currentStage,
        ),
      );
      expect(
        lastSent.staticGuide,
        GeminiSpecAiService.defaultStaticGuideFor(
          controller.project!.currentStage,
        ),
      );
      expect(lastSent.prompt, ai.calls.first.prompt);
      expect(
        lastSent.tools.map((t) => t.name).toList(),
        ai.calls.last.tools.map((t) => t.name).toList(),
      );
      expect(lastSent.attachments.length, 2);
      expect(
        lastSent.attachmentsText,
        contains('Règle métier spécifique au client ACME.'),
      );
      expect(lastSent.attachmentsText, contains('base64 omis'));
      expect(lastSent.hasToolRounds, isTrue);
      expect(
        lastSent.conversationRoundsPrettyJson,
        contains('get_lexicon_and_synonyms'),
      );
      expect(
        lastSent.conversationRoundsPrettyJson,
        contains('functionResponse'),
      );
      expect(lastSent.conversationRoundsPrettyJson, contains('<base64 omis'));

      // 3. Effacer la conversation supprime le dernier envoi réel mais garde l'aperçu.
      await controller.clearStageChat();
      final afterClear = controller.inspectSpecStageAiContext()!;
      expect(afterClear.hasLastSent, isFalse);
      expect(afterClear.preview.prompt, contains('OrderHub'));
    },
  );

  testWidgets(
    'Modale Context lecture seule : onglets, recherche, copie, bascule Aperçu / Dernier envoi et absence de débordement sur volet étroit',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardText =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final fixture = await _buildTestFixture();
      final controller = fixture.controller;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => StageAiChatPane(
                  controller: controller,
                  chatWidthFraction: 0.3,
                  onCycleChatSize: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Le bouton Context est visible même avant le premier message et sans overflow.
      final contextBtn = find.byKey(const ValueKey('spec-chat-context-btn'));
      expect(contextBtn, findsOneWidget);
      expect(tester.takeException(), isNull);

      // Ouvre la modale lecture seule en aperçu en direct.
      await tester.tap(contextBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('spec-ai-context-dialog')), findsOneWidget);
      expect(find.text('Lecture seule'), findsOneWidget);

      // Bascule sur l'onglet System puis Outils.
      await tester.tap(find.byKey(const ValueKey('spec-ai-context-tab-system')));
      await tester.pumpAndSettle();
      final systemText = tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('spec-ai-context-content')),
          )
          .textSpan!
          .toPlainText();
      expect(systemText, contains('Lexique'));
      expect(systemText, isNot(contains('=== 4. OUTILS DÉCLARÉS')));

      await tester.tap(find.byKey(const ValueKey('spec-ai-context-tab-tools')));
      await tester.pumpAndSettle();
      final toolsText = tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('spec-ai-context-content')),
          )
          .textSpan!
          .toPlainText();
      expect(toolsText, contains('get_lexicon_and_synonyms'));
      expect(toolsText, isNot(contains('=== 1. SYSTEM INSTRUCTION')));

      // Recherche dans l'onglet actif.
      await tester.enterText(
        find.byKey(const ValueKey('spec-ai-context-search')),
        'get_lexicon_and_synonyms',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spec-ai-context-search-count')),
        findsOneWidget,
      );

      // Copie de la totalité du contexte.
      await tester.tap(find.byKey(const ValueKey('spec-ai-context-copy-all-btn')));
      await tester.pump();
      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('=== 1. SYSTEM INSTRUCTION'));
      expect(clipboardText, contains('=== 4. OUTILS DÉCLARÉS'));

      // Ferme la modale.
      await tester.tap(find.byKey(const ValueKey('spec-ai-context-close-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spec-ai-context-dialog')), findsNothing);

      // Envoie un vrai message avec pièce jointe et vérifie la bascule Dernier envoi / Aperçu.
      await controller.sendUserMessage(
        'Définis le terme Facture client',
        attachments: [
          VibeChatAttachment.text(
            name: 'glossaire.txt',
            content: 'Facture client : document comptable émis après livraison.',
          ),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(contextBtn);
      await tester.pumpAndSettle();

      // L'onglet Pièces jointes & Tours apparaît pour le dernier envoi réel.
      final extrasTab = find.byKey(const ValueKey('spec-ai-context-tab-extras'));
      expect(extrasTab, findsOneWidget);
      await tester.tap(extrasTab);
      await tester.pumpAndSettle();
      final extrasContent = tester.widget<SelectableText>(
        find.byKey(const ValueKey('spec-ai-context-content')),
      );
      expect(
        extrasContent.textSpan?.toPlainText(),
        contains('document comptable émis après livraison'),
      );

      // Revenir sur Aperçu prochain envoi retombe proprement sur l'onglet Complet sans erreur.
      await tester.tap(
        find.byKey(const ValueKey('spec-ai-context-source-preview')),
      );
      await tester.pumpAndSettle();
      expect(extrasTab, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Bouton Context présent et opérationnel sur tous les autres panneaux de chat IA de SuperSpecForge',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fixture = await _buildTestFixture();
      final controller = fixture.controller;
      final domain = fixture.domain;
      final entryId = fixture.entryId;

      final panes = <({String name, String buttonKey, Widget widget})>[
        (
          name: 'UxStageAiChatPane',
          buttonKey: 'ux-chat-context-btn',
          widget: UxStageAiChatPane(controller: controller),
        ),
        (
          name: 'QaStageAiChatPane',
          buttonKey: 'qa-chat-context-btn',
          widget: QaStageAiChatPane(controller: controller),
        ),
        (
          name: 'CostStageAiChatPane',
          buttonKey: 'cost-chat-context-btn',
          widget: CostStageAiChatPane(controller: controller),
        ),
        (
          name: 'GlobalQuestionChatPane',
          buttonKey: 'spec-global-chat-context-btn',
          widget: GlobalQuestionChatPane(controller: controller),
        ),
        (
          name: 'PortfolioAiChatPane',
          buttonKey: 'portfolio-chat-context-btn',
          widget: PortfolioAiChatPane(
            controller: controller,
            onCollapse: () {},
          ),
        ),
        (
          name: 'CompanyGlossaryView',
          buttonKey: 'company-glossary-chat-context-btn',
          widget: CompanyGlossaryView(controller: controller),
        ),
        (
          name: 'ContractModelChatPane',
          buttonKey: 'contract-chat-context-btn',
          widget: ContractModelChatPane(
            controller: controller,
            domainId: domain.id,
            entryId: entryId,
            modelName: 'CommandeClient',
            onCollapse: () {},
          ),
        ),
        (
          name: 'ContractDomainLayerChatPane',
          buttonKey: 'domain-layer-chat-context-btn',
          widget: ContractDomainLayerChatPane(
            controller: controller,
            domainId: domain.id,
            entryId: entryId,
            modelName: 'CommandeClient',
            activeTab: DomainLayerTab.invariants,
            onCollapse: () {},
          ),
        ),
        (
          name: 'UseCaseOrchestrationChatPane',
          buttonKey: 'usecase-orchestration-chat-context-btn',
          widget: UseCaseOrchestrationChatPane(
            controller: controller,
            domain: domain,
            activeTab: UseCaseOrchestrationTab.cartography,
            onCollapse: () {},
          ),
        ),
        (
          name: 'SystemsServicesChatPane',
          buttonKey: 'systems-services-chat-context-btn',
          widget: SystemsServicesChatPane(
            controller: controller,
            domain: domain,
            activeFilterKind: null,
            onCollapse: () {},
          ),
        ),
        (
          name: 'ValueObjectsChatPane',
          buttonKey: 'value-objects-chat-context-btn',
          widget: ValueObjectsChatPane(
            controller: controller,
            scope: ValueObjectScope.shared,
            onCollapse: () {},
          ),
        ),
      ];

      for (final pane in panes) {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: pane.widget)),
        );
        await tester.pumpAndSettle();

        final btn = find.byKey(ValueKey(pane.buttonKey));
        expect(
          btn,
          findsOneWidget,
          reason: 'Bouton Context manquant sur ${pane.name}',
        );

        await tester.tap(btn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('spec-ai-context-dialog')),
          findsOneWidget,
          reason: 'Modale Context non ouverte sur ${pane.name}',
        );
        await tester.tap(
          find.byKey(const ValueKey('spec-ai-context-close-btn')),
        );
        await tester.pumpAndSettle();
      }
    },
  );
}
