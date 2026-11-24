import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/main.dart';
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
      'message':
          'J’ai structuré les comportements et règles de la couche Domain avec titres en français et méthodes en anglais.',
      'askUser': null,
      'specPatch': {
        'invariant_behaviors': [
          {
            'code': 'INV-01',
            'title': 'Vérifier que le montant HT est positif ou nul',
            'description':
                'Contrôle l’intégrité financière des montants de la commande.',
            'rules': [
              'Le montant montantHt doit être supérieur ou égal à 0.',
            ],
            'associatedMethods': [
              'validatePositiveAmountHt(montantHt)',
              'validateAmountPrecision(montantHt)',
            ],
            'relatedAttributes': ['montantHt'],
            'violationError': 'NegativeAmountError',
          },
        ],
        'state_changing_behaviors': [
          {
            'title': 'Confirmer la commande brouillon',
            'name': 'confirmOrder',
            'methodSignature': 'confirmOrder(): void',
            'stateChangeRule': 'BROUILLON -> CONFIRMEE si montantHt > 0',
            'preconditions': ['statut == BROUILLON'],
            'mutations': ['statut = CONFIRMEE'],
            'toState': 'CONFIRMEE',
            'emittedEvents': ['OrderConfirmed'],
            'relatedAttributes': ['montantHt'],
          },
        ],
        'query_behaviors': [
          {
            'title': 'Indiquer si la commande est annulable',
            'name': 'canBeCancelled',
            'methodSignature': 'canBeCancelled(): bool',
            'returnType': 'bool',
            'formula': 'statut == BROUILLON',
          },
        ],
        'policy_service_behaviors': [
          {
            'title': 'Appliquer la politique de remise volume',
            'name': 'applyVolumeDiscountPolicy',
            'methodSignature':
                'applyVolumeDiscountPolicy(order: CommandeClient): number',
            'relatedAttributes': ['montantHt'],
          },
        ],
        'factory_behaviors': [
          {
            'title': 'Créer une commande brouillon valide',
            'name': 'createDraftOrder',
            'methodSignature':
                'createDraftOrder(montantHt: number): CommandeClient',
            'initialState': 'BROUILLON',
            'relatedAttributes': ['montantHt'],
          },
        ],
        'domain_event_behaviors': [
          {
            'title': 'Publier l’événement de confirmation de commande',
            'name': 'publishOrderConfirmed',
            'methodSignature':
                'publishOrderConfirmed(event: OrderConfirmedEvent): void',
            'trigger': 'confirmOrder',
            'payloadFields': ['montantHt: number'],
            'relatedAttributes': ['montantHt'],
          },
        ],
        'persistence_policy_behaviors': {
          'repositoryPortName': 'CommandeClientRepository',
          'concurrencyStrategy': 'optimisticVersion',
          'rules': ['Index de recherche sur montantHt'],
          'portMethods': [
            {
              'category': 'crud',
              'title': 'Rechercher une commande par montant',
              'name': 'findByMontantHt',
              'methodSignature':
                  'findByMontantHt(montantHt: number): List<CommandeClient>',
              'relatedAttributes': ['montantHt'],
            },
            {
              'category': 'searchIndexRule',
              'title': 'Index de recherche sur le montant HT',
              'name': '',
              'methodSignature': '',
              'rules': ['Index B-Tree sur montantHt'],
              'relatedAttributes': ['montantHt'],
            },
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

      // La commande générée par l'IA affiche le titre, Rules: et Associated internal methods:
      expect(find.text('Confirmer la commande brouillon'), findsOneWidget);
      expect(find.text('Rules:'), findsWidgets);
      expect(find.text('Associated internal methods:'), findsWidgets);
      expect(find.text('confirmOrder(): void'), findsOneWidget);
      expect(
        find.textContaining('BROUILLON -> CONFIRMEE'),
        findsOneWidget,
      );

      // 4. Navigue sur Invariants et vérifie les 4 blocs + ajout manuel multi-méthodes
      await tester.tap(
        find.byKey(const ValueKey('domain-layer-tab-invariants')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Vérifier que le montant HT est positif ou nul'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Contrôle l’intégrité financière des montants de la commande.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('validatePositiveAmountHt(montantHt)'),
        findsOneWidget,
      );
      expect(
        find.text('validateAmountPrecision(montantHt)'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('domain-layer-add-invariants')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('domain-layer-field-title')),
        'Plafonner le montant HT unitaire',
      );
      await tester.enterText(
        find.byKey(const ValueKey('domain-layer-field-description')),
        'Empêche toute saisie au-delà du plafond autorisé.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('domain-layer-field-rules')),
        'Le montant montantHt ne doit pas dépasser 100000.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('domain-layer-field-associatedMethods')),
        'validateMaxAmountHt(montantHt)',
      );
      await tester.tap(
        find.byKey(const ValueKey('domain-layer-form-save-btn')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plafonner le montant HT unitaire'), findsOneWidget);
      expect(
        find.text('Empêche toute saisie au-delà du plafond autorisé.'),
        findsOneWidget,
      );
      expect(find.text('validateMaxAmountHt(montantHt)'), findsOneWidget);

      // 5. Vérifie l'onglet Persistence policy (méthode EN + règle pure d'index sans méthode associée)
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
      expect(find.text('Rechercher une commande par montant'), findsOneWidget);
      expect(
        find.text('findByMontantHt(montantHt: number): List<CommandeClient>'),
        findsOneWidget,
      );
      expect(find.text('Index de recherche'), findsOneWidget);
      expect(find.text('Règle sans méthode associée'), findsOneWidget);

      // 6. Retour vers la fiche modèle via le fil d'Ariane (aucun bouton retour local dans la vue) :
      // le badge du bouton indique les éléments créés.
      expect(
        find.byKey(const ValueKey('domain-layer-back-to-model-btn')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('contracts-entry-crumb')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('contract-entry-page')), findsOneWidget);
      expect(find.text('Couche Domain (9)'), findsOneWidget);
    },
  );

  testWidgets(
    'AppBar centralise les retours entre écrans : Couche Domain -> Fiche -> Liste -> Menu Design',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1480, 940));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final contracts = DomainContracts.parse(
        'models:\n  CommandeClient: model\n',
      );
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
        aiService: _FakeDomainLayerAiService(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        SuperSpecForgeApp(controller: controller, restoreLastProject: false),
      );
      await tester.pumpAndSettle();

      final backBtn = find.byKey(const ValueKey('spec-forge-appbar-back-btn'));
      expect(backBtn, findsNothing);

      // Design (menu racine) : aucun bouton retour dans l'AppBar
      await tester.tap(find.text('Design'));
      await tester.pumpAndSettle();
      expect(backBtn, findsNothing);
      expect(find.byType(DesignLinksView), findsOneWidget);

      // Liste des modèles et contrats (niveau 0)
      await tester.tap(find.byKey(const ValueKey('design-link-models_contracts')));
      await tester.pumpAndSettle();
      expect(backBtn, findsOneWidget);
      expect(find.byTooltip('Retour au menu Design'), findsOneWidget);

      // Fiche modèle (niveau 1)
      await tester.tap(
        find.byKey(const ValueKey('open-models.CommandeClient')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('contract-entry-page')), findsOneWidget);
      expect(
        find.byTooltip('Retour à la liste des modèles et contrats'),
        findsOneWidget,
      );

      // Couche Domain (niveau 2) : pas de bouton retour local, retour via AppBar
      await tester.tap(
        find.byKey(const ValueKey('contract-open-domain-layer-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('contract-domain-layer-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('domain-layer-back-to-model-btn')),
        findsNothing,
      );
      expect(find.byTooltip('Retour à la fiche du modèle'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Modèles & Contrats › CommandeClient › Couche Domain'),
        ),
        findsOneWidget,
      );

      // Retour 1 : Couche Domain -> Fiche modèle
      await tester.tap(backBtn);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('contract-entry-page')), findsOneWidget);
      expect(
        find.byTooltip('Retour à la liste des modèles et contrats'),
        findsOneWidget,
      );

      // Retour 2 : Fiche modèle -> Liste des modèles et contrats
      await tester.tap(backBtn);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('contract-entry-page')), findsNothing);
      expect(find.byTooltip('Retour au menu Design'), findsOneWidget);

      // Retour 3 : Liste -> Menu Design (bouton retour masqué à nouveau)
      await tester.tap(backBtn);
      await tester.pumpAndSettle();
      expect(find.byType(DesignLinksView), findsOneWidget);
      expect(backBtn, findsNothing);
    },
  );

  testWidgets(
    'Treeview des modèles : hauteur de ligne 28 et bouton Couche Domain au survol après le titre',
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
      contracts = contracts
          .edit(
            cmdEntry,
            'model',
            ContractDetails(
              title: 'Commande client',
              version: '1.2.0',
              states: const {
                ContractStage.design: ContractStatus.done,
                ContractStage.validation: ContractStatus.inProgress,
              },
            ),
          )
          .withModel(
            cmdEntry.id,
            object: BusinessObjectSpec(
              id: cmdEntry.id,
              name: 'Commande client',
              technicalName: 'CommandeClient',
              description: 'Agrégat principal de prise de commande.',
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
        aiService: _FakeDomainLayerAiService(),
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

      final tree = tester.widget<SuperTreeView>(
        find.byWidgetPredicate(
          (w) => w is SuperTreeView && w.id == 'domain-contracts-tree',
        ),
      );
      expect(tree.config?.rowHeight, 28);

      final modelHoverBtn = find.byKey(
        const ValueKey('domain-layer-models.CommandeClient'),
      );
      final dtoHoverBtn = find.byKey(
        const ValueKey('domain-layer-dto.CommandeDto'),
      );
      final titleTooltipCard = find.byKey(
        const ValueKey('contract-title-tooltip-models.CommandeClient'),
      );
      expect(modelHoverBtn, findsNothing);
      expect(dtoHoverBtn, findsNothing);
      expect(titleTooltipCard, findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      // Survol sur un DTO non éligible : aucun bouton Couche Domain affiché.
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('edit-dto.CommandeDto'))),
      );
      await tester.pumpAndSettle();
      expect(dtoHoverBtn, findsNothing);
      expect(modelHoverBtn, findsNothing);

      // Survol sur le titre du modèle éligible : bouton après le titre + beau tooltip riche.
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('title-models.CommandeClient')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(modelHoverBtn, findsOneWidget);
      expect(titleTooltipCard, findsOneWidget);
      expect(
        find.text('Agrégat principal de prise de commande.'),
        findsOneWidget,
      );
      expect(find.text('v1.2.0'), findsOneWidget);
      expect(find.text('1 attribut(s)'), findsOneWidget);
      expect(find.text('Conception : Terminé'), findsOneWidget);

      // Clic sur le bouton : ouvre directement la page Couche Domain.
      await tester.tap(modelHoverBtn);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('contract-domain-layer-page')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
