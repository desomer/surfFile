import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_sys_store'));

  SpecForgeProject? activeProject;

  @override
  Future<void> saveProject(SpecForgeProject project) async {
    activeProject = project;
  }

  @override
  Future<SpecForgeProject?> loadProject(String projectId) async =>
      activeProject?.id == projectId ? activeProject : null;

  @override
  Future<void> deleteProject(String projectId) async {
    if (activeProject?.id == projectId) activeProject = null;
  }

  @override
  Future<List<SpecProjectSummary>> listProjects() async => const [];

  @override
  Future<String?> getLastActiveProjectId() async => activeProject?.id;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {}
}

class _MemoryDomainCatalogStore extends DomainCatalogStore {
  _MemoryDomainCatalogStore([DomainCatalog? initial])
    : _catalog = initial ?? DomainCatalog.empty,
      super(Directory('memory_sys_store'));

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
  _MemoryCompanyGlossaryStore() : super(Directory('memory_sys_store'));

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
  _MemoryModelDictionaryStore() : super(Directory('memory_sys_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemoryEnterpriseRateCardStore extends EnterpriseRateCardStore {
  _MemoryEnterpriseRateCardStore() : super(Directory('memory_sys_store'));

  @override
  Future<EnterpriseRateCard> load() async => EnterpriseRateCard.defaults;

  @override
  Future<void> save(EnterpriseRateCard card) async {}
}

class _FakeSystemsServicesAiService implements SpecAiService {
  String? lastPrompt;

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
    final payload = jsonEncode(<String, Object?>{
      'message':
          'Cartographie Systèmes & Services complétée pour le domaine Commandes.',
      'askUser': null,
      'specPatch': <String, Object?>{
        'systems': <Object?>[
          <String, Object?>{
            'serviceCode': 'adyen-psp',
            'name': 'Adyen Paiement',
            'kind': 'externalApp',
            'vendor': 'Adyen',
            'description': 'Encaissement international',
          },
          <String, Object?>{
            'serviceCode': 'meilisearch-engine',
            'name': 'Meilisearch',
            'kind': 'openSourceTool',
            'vendor': 'MIT',
            'description': 'Moteur de recherche produits open-source',
          },
          <String, Object?>{
            'serviceCode': 'mobile-checkout-bff',
            'name': 'BFF Checkout Mobile',
            'kind': 'bff',
            'techStackId': 'ts-nestjs',
            'description': 'Agrégation API pour l’app mobile',
          },
        ],
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
    'Design › Systèmes & Services : CRUD par domaine, découverte IA et import 1-clic vers Event Storming EXT-*',
    (tester) async {
      tester.view.physicalSize = const Size(1560, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialProject = SpecForgeProject.fromIdea(
        id: 'proj_shop',
        name: 'Boutique Omnicanale',
        idea: 'Vente en ligne et encaissement multi-moyens de paiement',
      ).copyWith(
        currentStage: SpecForgeStage.eventStorming,
        eventStorming: EventStormingSpec(
          documents: [
            EventStormDocument(
              id: 'orders',
              meta: const EventStormMeta(
                domain: 'Commerce',
                boundedContext: 'Commandes',
                date: '2026-11-27',
              ),
            ),
          ],
        ),
      );

      final projectStore = _MemorySpecProjectStore()
        ..activeProject = initialProject;
      final domainStore = _MemoryDomainCatalogStore(
        DomainCatalog(
          domains: const [
            FunctionalDomain(
              id: 'dom_orders',
              domainCode: 'orders',
              name: 'Commandes',
            ),
            FunctionalDomain(
              id: 'dom_shipping',
              domainCode: 'shipping',
              name: 'Logistique',
            ),
          ],
          microservices: const [
            Microservice(
              id: 'svc_carrier',
              domainId: 'dom_shipping',
              serviceCode: 'carrier-service',
              name: 'Service Transporteurs',
              kind: DomainSystemKind.microservice,
              description: 'Calcul des tarifs et étiquettes colis',
            ),
          ],
        ),
      );
      final fakeAi = _FakeSystemsServicesAiService();

      final controller = SpecForgeController(
        store: projectStore,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        domainCatalogStore: domainStore,
        enterpriseRateCardStore: _MemoryEnterpriseRateCardStore(),
        aiService: fakeAi,
        initialQuestioningLevel: VibeQuestioningLevel.none,
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(home: SpecForgeShell(controller: controller)),
      );
      await tester.pumpAndSettle();

      // 1. Ouvre l'onglet Design puis clique sur le bouton existant « Systèmes & Services »
      await tester.tap(find.text('Design'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('design-link-systems_services')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('systems-services-view')),
        findsOneWidget,
      );
      expect(
        find.text('Systèmes & Services › Commandes'),
        findsOneWidget,
      );

      // 2. Ajoute manuellement une Application externe (Stripe) sur le domaine Commandes
      await tester.tap(
        find.byKey(const ValueKey('systems-services-empty-add-externalApp')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('systems-services-dialog-name')),
        'Stripe Connect',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('systems-services-dialog-vendor')),
        'Stripe',
      );
      await tester.enterText(
        find.byKey(const ValueKey('systems-services-dialog-description')),
        'Paiement partagé marketplace',
      );
      await tester.tap(
        find.byKey(const ValueKey('systems-services-dialog-save-btn')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stripe Connect'), findsOneWidget);
      expect(find.text('EXT-STRIPE_CONNECT'), findsOneWidget);

      // 3. Lance la découverte IA qui ajoute Adyen (externalApp) et un BFF Mobile
      await tester.tap(
        find.byKey(const ValueKey('systems-services-ai-generate-btn')),
      );
      await tester.pumpAndSettle();

      expect(fakeAi.lastPrompt, contains('Boutique Omnicanale'));
      expect(find.text('Adyen Paiement'), findsOneWidget);
      expect(find.text('Meilisearch'), findsOneWidget);
      expect(find.text('BFF Checkout Mobile'), findsOneWidget);

      // 4. Filtre par catégorie Tools openSource puis BFF puis réaffiche Tous
      await tester.tap(
        find.byKey(const ValueKey('systems-services-filter-openSourceTool')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Meilisearch'), findsOneWidget);
      expect(find.text('Stripe Connect'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('systems-services-filter-bff')),
      );
      await tester.pumpAndSettle();
      expect(find.text('BFF Checkout Mobile'), findsOneWidget);
      expect(find.text('Meilisearch'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('systems-services-filter-all')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stripe Connect'), findsOneWidget);

      // 4b. Change de domaine via le fil d'Ariane vers Logistique puis revient sur Commandes
      await tester.tap(find.byKey(const ValueKey('design-domain-crumb')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('design-domain-option-dom_shipping')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Systèmes & Services › Logistique'), findsOneWidget);
      expect(find.text('Service Transporteurs'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('design-domain-crumb')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('design-domain-option-dom_orders')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Systèmes & Services › Commandes'), findsOneWidget);

      // 5. Bascule directement vers l'Event Storming et importe les systèmes externes en 1 clic
      await tester.tap(
        find.byKey(const ValueKey('systems-services-open-event-storming-btn')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('event-storming-editor-view')),
        findsOneWidget,
      );

      await tester.tap(find.textContaining('Catalogue ('));
      await tester.pumpAndSettle();

      final importBtn = find.byKey(
        const ValueKey('spec-es-import-ext-systems-btn'),
      );
      await tester.ensureVisible(importBtn);
      await tester.pumpAndSettle();
      await tester.tap(importBtn);
      await tester.pumpAndSettle();

      // Les 2 applications externes sont pré-cochées ; on vérifie aussi Tools openSource et on coche le service de l'autre domaine
      expect(
        find.text('Applications externes déclarées (2)'),
        findsOneWidget,
      );
      expect(find.text('Tools openSource déclarés (1)'), findsOneWidget);
      expect(find.text('Services des autres domaines (1)'), findsOneWidget);

      final meiliCand = controller.domainCatalog.microservices.firstWhere(
        (s) => s.serviceCode == 'meilisearch-engine',
      );
      await tester.tap(
        find.byKey(ValueKey('spec-es-import-cand-${meiliCand.id}')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('spec-es-import-cand-svc_carrier')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('spec-es-import-confirm-btn')),
      );
      await tester.pumpAndSettle();

      final extSystems = controller
          .project!
          .eventStorming
          .documents
          .single
          .catalog
          .externalSystems;
      expect(
        extSystems.map((e) => e.name).toSet(),
        {
          'Adyen Paiement',
          'Stripe Connect',
          'Meilisearch',
          'Service Transporteurs',
        },
      );
    },
  );
}
