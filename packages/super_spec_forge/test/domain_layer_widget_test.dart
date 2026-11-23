import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_domain_layer_store'));

  @override
  Future<void> saveProject(SpecForgeProject project) async {}

  @override
  Future<SpecForgeProject?> loadProject(String projectId) async => null;

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<List<SpecProjectSummary>> listProjects() async => const [];

  @override
  Future<String?> getLastActiveProjectId() async => null;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {}
}

class _MemoryDomainCatalogStore extends DomainCatalogStore {
  _MemoryDomainCatalogStore(this._catalog)
    : super(Directory('memory_domain_layer_store'));

  DomainCatalog _catalog;

  @override
  Future<DomainCatalog> load() async => _catalog;

  @override
  Future<void> save(DomainCatalog catalog) async {
    catalog.validate();
    _catalog = catalog;
  }
}

class _MemoryCompanyGlossaryStore extends CompanyGlossaryStore {
  _MemoryCompanyGlossaryStore() : super(Directory('memory_domain_layer_store'));

  @override
  Future<CompanyGlossary> loadGlossary() async => CompanyGlossary.empty;

  @override
  Future<void> saveGlossary(CompanyGlossary glossary) async {}

  @override
  Future<List<SpecChatMessage>> loadChatMessages() async => const [];

  @override
  Future<void> saveChatMessages(List<SpecChatMessage> messages) async {}
}

class _MemoryModelDictionaryStore extends ModelDictionaryStore {
  _MemoryModelDictionaryStore() : super(Directory('memory_domain_layer_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _FakeDomainLayerAiService implements SpecAiService {
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
    final payload = jsonEncode({
      'message': 'J’ai structuré les invariants, la commande confirmer, l’événement CommandeConfirmee et le port Repository.',
      'askUser': null,
      'specPatch': {
        'invariants': [
          {
            'code': 'INV-01',
            'title': 'Montant HT positif',
            'expression': 'montantHt >= 0',
            'relatedAttributes': ['montantHt'],
            'violationError': 'MontantNegatif',
          },
        ],
        'stateChanges': [
          {
            'name': 'confirmer',
            'parameters': ['dateConfirmation: datetime'],
            'preconditions': ['statut == BROUILLON'],
            'mutations': ['statut = CONFIRMEE'],
            'toState': 'CONFIRMEE',
            'emittedEvents': ['CommandeConfirmee'],
          },
        ],
        'queries': [
          {
            'name': 'estAnnulable',
            'returnType': 'bool',
            'formula': 'statut == BROUILLON',
          },
        ],
        'policyServices': [
          {'name': 'PolitiqueRemise', 'operation': 'calculer(cmd) -> number'},
        ],
        'factories': [
          {
            'name': 'creerBrouillon',
            'parameters': ['clientId: uuid'],
            'initialState': 'BROUILLON',
          },
        ],
        'domainEvents': [
          {
            'name': 'CommandeConfirmee',
            'trigger': 'confirmer',
            'payloadFields': ['commandeId: uuid'],
          },
        ],
        'persistencePolicy': {
          'repositoryPortName': 'CommandeClientRepository',
          'concurrencyStrategy': 'optimisticVersion',
          'portMethods': [
            {'name': 'findById', 'signature': '(id: uuid) -> CommandeClient?'},
          ],
        },
      },
    });
    yield GeminiStreamEvent(
      deltaText: payload,
      accumulatedText: payload,
      isDone: true,
      usedContextCache: false,
    );
  }
}

void main() {
  testWidgets(
    'Design : bouton Couche Domain sur les objets du domaine, 7 onglets Archi Hexa, remplissage par chat IA et CRUD manuel',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1480, 940));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var contracts = DomainContracts.parse(
        'models:\n  CommandeClient: model\ndto:\n  CommandeDto: xresponsedto\n',
      );
      final cmdEntry = SpecDesignPromoter.findExistingEntry(
        contracts,
        'CommandeClient',
      )!;
      contracts = contracts.withModel(
        cmdEntry.id,
        object: BusinessObjectSpec(
          id: cmdEntry.id,
          name: 'Commande client',
          technicalName: 'CommandeClient',
          attributes: [
            BusinessAttribute(
              id: 'attr_montant',
              name: 'montantHt',
              type: BusinessAttributeType.number,
              required: true,
            ),
          ],
        ),
      );

      final fakeAi = _FakeDomainLayerAiService();
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        domainCatalogStore: _MemoryDomainCatalogStore(
          DomainCatalog(
            domains: [
              FunctionalDomain(
                id: 'dom_sales',
                domainCode: 'sales',
                name: 'Ventes',
                contracts: contracts,
              ),
            ],
          ),
        ),
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        aiService: fakeAi,
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelsContractsView(
              controller: controller,
              onBack: () {},
              onManageDomains: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Sur un DTO (xresponsedto), le bouton Couche Domain n'apparaît pas.
      await tester.tap(find.byKey(const ValueKey('open-dto.CommandeDto')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('contract-open-domain-layer-btn')),
        findsNothing,
      );

      // Retour à la liste puis ouverture de CommandeClient (type model)
      await tester.tap(find.byKey(const ValueKey('contracts-list-crumb')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('open-models.CommandeClient')),
      );
      await tester.pumpAndSettle();

      final openDomainBtn = find.byKey(
        const ValueKey('contract-open-domain-layer-btn'),
      );
      expect(openDomainBtn, findsOneWidget);

      // 2. Ouvre la nouvelle page Couche Domain (niveau 2)
      await tester.tap(openDomainBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('contract-domain-layer-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('domain-layer-chat-pane')),
        findsOneWidget,
      );

      // Vérifie la présence exacte des 7 onglets de la couche Domain
      for (final label in const [
        'Invariants',
        'State changing',
        'Query',
        'Policy Services',
        'Factory',
        'Domain events',
        'Persistence policy',
      ]) {
        expect(find.text(label), findsWidgets);
      }

      // 3. Sélectionne l'onglet "State changing" et envoie un message au chat IA
      await tester.tap(
        find.byKey(const ValueKey('domain-layer-tab-stateChanging')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('domain-layer-chat-input')),
        'Complète toute la couche Domain de cette commande',
      );
      await tester.tap(find.byKey(const ValueKey('domain-layer-chat-send')));
      await tester.pumpAndSettle();

      expect(fakeAi.lastSystemInstruction, contains('Architecture Hexagonale'));
      expect(fakeAi.lastPrompt, contains('State changing'));
      expect(fakeAi.lastPrompt, contains('montantHt'));

      // La commande générée par l'IA est affichée dans State changing
      expect(find.textContaining('confirmer('), findsOneWidget);

      // 4. Navigue sur Invariants et ajoute manuellement un second invariant
      await tester.tap(
        find.byKey(const ValueKey('domain-layer-tab-invariants')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('INV-01 · Montant HT positif'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('domain-layer-add-invariants')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('domain-layer-field-title')),
        'Client renseigné',
      );
      await tester.tap(
        find.byKey(const ValueKey('domain-layer-form-save-btn')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Client renseigné'), findsOneWidget);

      // 5. Vérifie l'onglet Persistence policy généré par l'IA
      final persistenceTab = find.byKey(
        const ValueKey('domain-layer-tab-persistencePolicy'),
      );
      await tester.ensureVisible(persistenceTab);
      await tester.pumpAndSettle();
      await tester.tap(persistenceTab);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Port sortant : CommandeClientRepository'),
        findsOneWidget,
      );
      expect(find.text('findById'), findsOneWidget);

      // 6. Retour vers la fiche modèle : le badge du bouton indique les éléments créés
      await tester.tap(
        find.byKey(const ValueKey('domain-layer-back-to-model-btn')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('contract-entry-page')), findsOneWidget);
      expect(find.text('Couche Domain (8)'), findsOneWidget);
    },
  );
}
