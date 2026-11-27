import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_vo_widget_store'));

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
    : super(Directory('memory_vo_widget_store'));

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
  _MemoryCompanyGlossaryStore() : super(Directory('memory_vo_widget_store'));

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
  _MemoryModelDictionaryStore() : super(Directory('memory_vo_widget_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemoryRateCardStore extends EnterpriseRateCardStore {
  _MemoryRateCardStore() : super(Directory('memory_vo_widget_store'));

  @override
  Future<EnterpriseRateCard> load() async => EnterpriseRateCard.defaults;

  @override
  Future<void> save(EnterpriseRateCard card) async {}
}

class _FakeAiService implements SpecAiService {
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
  }) => const Stream<GeminiStreamEvent>.empty();
}

Future<SpecForgeController> _createController(DomainCatalog initial) async {
  final controller = SpecForgeController(
    store: _MemorySpecProjectStore(),
    glossaryStore: _MemoryCompanyGlossaryStore(),
    modelDictionaryStore: _MemoryModelDictionaryStore(),
    domainCatalogStore: _MemoryDomainCatalogStore(initial),
    enterpriseRateCardStore: _MemoryRateCardStore(),
    aiService: _FakeAiService(),
  );
  await controller.initialize();
  return controller;
}

void main() {
  testWidgets('DesignLinksView expose la carte Catalogue des Value Objects', (
    tester,
  ) async {
    String? tappedId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesignLinksView(onLinkTap: (item) => tappedId = item.id),
        ),
      ),
    );
    final card = find.byKey(const ValueKey('design-link-value_objects'));
    expect(card, findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(tappedId, 'value_objects');
  });

  testWidgets(
    'ValueObjectsCatalogView crée un VO, importe des presets et bascule Shared Kernel / Domaine',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final catalog = DomainCatalog(
        domains: [
          FunctionalDomain(
            id: 'dom_sales',
            domainCode: 'sales',
            name: 'Ventes',
          ),
        ],
      );
      final controller = await _createController(catalog);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueObjectsCatalogView(
              controller: controller,
              initialDomainId: 'dom_sales',
              onBack: () {},
              onManageDomains: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Création manuelle d'un VO dans le domaine Ventes
      await tester.tap(find.byKey(const ValueKey('vo-add-btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('vo-editor-tech-name')),
        'OrderCode',
      );
      await tester.enterText(
        find.byKey(const ValueKey('vo-editor-name')),
        'Code commande',
      );
      await tester.tap(find.byKey(const ValueKey('vo-editor-save-btn')));
      await tester.pumpAndSettle();

      expect(controller.domainCatalog.domains.single.valueObjects.length, 1);
      expect(
        find.byKey(const ValueKey('vo-list-item-OrderCode')),
        findsOneWidget,
      );

      // Promotion du VO vers le Shared Kernel
      await tester.tap(
        find.byKey(const ValueKey('vo-detail-promote-shared-btn')),
      );
      await tester.pumpAndSettle();

      expect(controller.domainCatalog.domains.single.valueObjects, isEmpty);
      expect(controller.domainCatalog.sharedValueObjects.length, 1);
      expect(
        controller.domainCatalog.sharedValueObjects.single.technicalName,
        'OrderCode',
      );

      // Import de presets DDD dans le Shared Kernel
      await tester.tap(find.byKey(const ValueKey('vo-presets-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vo-presets-import-confirm')));
      await tester.pumpAndSettle();

      expect(
        controller.domainCatalog.sharedValueObjects.length,
        greaterThan(5),
      );
    },
  );

  testWidgets(
    'ContractEntryView affiche les suggestions Primitive Obsession et promeut un attribut en VO',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var contracts = DomainContracts.parse('models:\n  Customer: model\n');
      final customerNode = contracts.groups.first.children.single;
      contracts = contracts.withModel(
        customerNode.id,
        object: contracts
            .objectFor(customerNode)
            .copyWith(
              attributes: [
                BusinessAttribute(
                  id: 'a_email',
                  name: 'email',
                  type: BusinessAttributeType.email,
                  required: true,
                ),
              ],
            ),
      );

      final emailPreset = ValueObjectPresets.standardPresets.firstWhere(
        (v) => v.technicalName == 'EmailAddress',
      );
      final catalog = DomainCatalog(
        domains: [
          FunctionalDomain(
            id: 'dom_crm',
            domainCode: 'crm',
            name: 'CRM',
            contracts: contracts,
          ),
        ],
        sharedValueObjects: [emailPreset],
      );
      final controller = await _createController(catalog);
      addTearDown(controller.dispose);

      var openedCatalog = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContractEntryView(
              controller: controller,
              domainId: 'dom_crm',
              document: contracts,
              entry: customerNode,
              onOpenValueObjectsCatalog: () => openedCatalog = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bouton d'accès direct au catalogue
      final openCatalogBtn = find.byKey(
        const ValueKey('contract-open-vo-catalog-btn'),
      );
      expect(openCatalogBtn, findsOneWidget);
      await tester.tap(openCatalogBtn);
      await tester.pump();
      expect(openedCatalog, isTrue);

      // Bouton Suggestions VO détecte `email` -> `EmailAddress`
      final suggestBtn = find.byKey(
        const ValueKey('contract-vo-suggestions-btn'),
      );
      expect(suggestBtn, findsOneWidget);
      await tester.tap(suggestBtn);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('contract-vo-suggest-apply-a_email')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('vo-promote-confirm-btn')));
      await tester.pumpAndSettle();

      final updatedObj = controller.domainCatalog.domains.single.contracts!
          .objectFor(customerNode);
      expect(
        updatedObj.attributes.single.type,
        BusinessAttributeType.valueObject,
      );
      expect(updatedObj.attributes.single.valueObjectId, emailPreset.id);
    },
  );

  testWidgets(
    'ValueObjectsCatalogView : bascule des étapes ContractStage, préservation de states à l’édition, badge de dérive et bump SemVer 1-clic',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final initialVo = ValueObjectSpec(
        id: 'vo_invoice_num',
        technicalName: 'InvoiceNumber',
        name: 'Numéro de facture',
        version: '1.0.0',
        primitiveType: BusinessAttributeType.string,
        schemaConstraints: JsonSchemaConstraints(pattern: r'^FAC-\d{6}$'),
      );
      final catalog = DomainCatalog(
        domains: [
          FunctionalDomain(
            id: 'dom_billing',
            domainCode: 'billing',
            name: 'Facturation',
            valueObjects: [initialVo],
          ),
        ],
      );
      final controller = await _createController(catalog);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueObjectsCatalogView(
              controller: controller,
              initialDomainId: 'dom_billing',
              onBack: () {},
              onManageDomains: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Barre de jalon visible sous l'en-tête
      expect(find.byType(DomainIterationSnapshotBar), findsOneWidget);

      // 2. Bascule de l'étape Conception (pending -> inProgress -> done) directement sur la carte VO
      final designStageFinder = find.byKey(
        const ValueKey('vo-stage-vo_invoice_num-design'),
      );
      expect(designStageFinder, findsOneWidget);
      await tester.tap(designStageFinder);
      await tester.pumpAndSettle();
      expect(
        controller
            .domainCatalog
            .domains
            .single
            .valueObjects
            .single
            .states[ContractStage.design],
        ContractStatus.inProgress,
      );
      await tester.tap(designStageFinder);
      await tester.pumpAndSettle();
      expect(
        controller
            .domainCatalog
            .domains
            .single
            .valueObjects
            .single
            .states[ContractStage.design],
        ContractStatus.done,
      );

      // 3. Capture d'un jalon d'itération de référence (v1.0.0)
      await controller.createDomainIterationSnapshot(
        'dom_billing',
        label: 'Itération 1',
      );
      await tester.pumpAndSettle();

      // 4. Ouverture de ValueObjectEditorDialog : modification et sauvegarde SANS perte de `states` !
      await tester.tap(find.byKey(const ValueKey('vo-detail-edit-btn')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('vo-editor-description')),
        'Identifiant légal séquentiel de facture',
      );
      await tester.tap(find.byKey(const ValueKey('vo-editor-save-btn')));
      await tester.pumpAndSettle();

      final savedVo =
          controller.domainCatalog.domains.single.valueObjects.single;
      expect(
        savedVo.states[ContractStage.design],
        ContractStatus.done,
        reason: 'L’enregistrement de ValueObjectEditorDialog ne doit jamais écraser states',
      );
      expect(savedVo.description, 'Identifiant légal séquentiel de facture');

      // 5. EvolutionDriftBadge + dialogue de diff + SemVerBumpActionChip 1-clic
      final evoBadge = find.byKey(
        const ValueKey('vo-evolution-badge-vo_invoice_num'),
      );
      final bumpChip = find.byKey(
        const ValueKey('vo-semver-bump-vo_invoice_num'),
      );
      expect(evoBadge, findsOneWidget);
      expect(bumpChip, findsOneWidget);

      await tester.tap(evoBadge);
      await tester.pumpAndSettle();
      expect(find.byType(ArtifactEvolutionDiffDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('artifact-diff-close-btn')));
      await tester.pumpAndSettle();

      // Application 1-clic du bump SemVer (1.0.0 -> 1.0.1 pour modification documentaire)
      await tester.tap(bumpChip);
      await tester.pumpAndSettle();

      final bumpedVo =
          controller.domainCatalog.domains.single.valueObjects.single;
      expect(bumpedVo.version, '1.0.1');
      expect(bumpedVo.states[ContractStage.design], ContractStatus.done);
      expect(
        find.byKey(const ValueKey('vo-semver-bump-vo_invoice_num')),
        findsNothing,
      );
    },
  );
}
