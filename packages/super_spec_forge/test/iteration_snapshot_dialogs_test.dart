import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/ai/spec_ai_service.dart';
import 'package:super_spec_forge/models/business_object_model_preferences.dart';
import 'package:super_spec_forge/models/business_object_spec.dart';
import 'package:super_spec_forge/models/company_glossary.dart';
import 'package:super_spec_forge/models/domain_catalog.dart';
import 'package:super_spec_forge/models/domain_contracts.dart';
import 'package:super_spec_forge/models/enterprise_rate_card.dart';
import 'package:super_spec_forge/models/json_schema_constraints.dart';
import 'package:super_spec_forge/models/spec_forge_project.dart';
import 'package:super_spec_forge/models/spec_forge_stage.dart';
import 'package:super_spec_forge/models/spec_stage_chat.dart';
import 'package:super_spec_forge/models/usecase_orchestration_spec.dart';
import 'package:super_spec_forge/models/value_object_spec.dart';
import 'package:super_spec_forge/services/company_glossary_store.dart';
import 'package:super_spec_forge/services/design_evolution_analyzer.dart';
import 'package:super_spec_forge/services/domain_catalog_store.dart';
import 'package:super_spec_forge/services/enterprise_rate_card_store.dart';
import 'package:super_spec_forge/services/model_dictionary_store.dart';
import 'package:super_spec_forge/services/spec_forge_controller.dart';
import 'package:super_spec_forge/services/spec_project_store.dart';
import 'package:super_spec_forge/widgets/design/iteration_snapshot_dialogs.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_snapshot_dialogs_store'));

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
    : super(Directory('memory_snapshot_dialogs_store'));

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
  _MemoryCompanyGlossaryStore()
    : super(Directory('memory_snapshot_dialogs_store'));

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
  _MemoryModelDictionaryStore()
    : super(Directory('memory_snapshot_dialogs_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemoryRateCardStore extends EnterpriseRateCardStore {
  _MemoryRateCardStore() : super(Directory('memory_snapshot_dialogs_store'));

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

({DomainCatalog catalog, String orderModelEntryId}) _buildSampleSalesCatalog() {
  final orderAmountVo = ValueObjectSpec(
    id: 'vo_amount',
    technicalName: 'OrderAmount',
    name: 'Montant commande',
    description: 'Montant HT de la commande.',
    version: '1.0.0',
    kind: ValueObjectKind.scalar,
    primitiveType: BusinessAttributeType.number,
    schemaConstraints: JsonSchemaConstraints(minimum: 0, maximum: 10000),
  );
  final legacyVo = ValueObjectSpec(
    id: 'vo_legacy',
    technicalName: 'LegacyDiscountCode',
    name: 'Code remise hérité',
    version: '1.0.0',
  );

  var contracts = DomainContracts.parse('models:\n  CustomerOrder: model\n');
  final orderNode = contracts.groups.first.children.first;
  contracts = contracts
      .edit(
        orderNode,
        'model',
        ContractDetails(title: 'Commande client', version: '1.0.0'),
      )
      .withModel(
        orderNode.id,
        object: BusinessObjectSpec(
          id: orderNode.id,
          name: 'Commande client',
          technicalName: 'CustomerOrder',
          attributes: <BusinessAttribute>[
            BusinessAttribute(
              id: 'attr_amount',
              name: 'totalAmount',
              type: BusinessAttributeType.valueObject,
              valueObjectId: orderAmountVo.id,
              required: true,
            ),
          ],
        ),
      );

  final placeOrderUc = ApplicationUseCaseSpec(
    id: 'uc_place_order',
    code: 'UC-001',
    name: 'PlaceCustomerOrder',
    title: 'Passer une commande client',
    version: '1.0.0',
    cqrsType: UseCaseCqrsType.command,
    targetAggregate: 'CustomerOrder',
    inboundPort: 'PlaceCustomerOrderUseCase',
    outboundPorts: const <String>['CustomerOrderRepository'],
    triggerInputs: const <UseCaseFieldSpec>[
      UseCaseFieldSpec(name: 'amount', type: 'OrderAmount', required: true),
    ],
  );

  final orderSaga = OrchestrationSagaSpec(
    id: 'saga_order',
    code: 'SAGA-001',
    name: 'CustomerOrderSaga',
    title: 'Orchestration commande',
    version: '1.0.0',
    boundedContexts: const <String>['Ventes'],
    triggerEventOrCommand: 'OrderPlaced',
    correlationKey: 'orderId',
    compensationMatrix: const <SagaCompensationRow>[
      SagaCompensationRow(
        id: 'step_1',
        step: '1. Créer commande',
        nominalAction: 'PlaceCustomerOrder',
        compensationAction: 'CancelCustomerOrder',
      ),
    ],
  );

  final domain = FunctionalDomain(
    id: 'dom_sales',
    domainCode: 'sales',
    name: 'Ventes',
    valueObjects: <ValueObjectSpec>[orderAmountVo, legacyVo],
    contracts: contracts,
    useCaseOrchestration: UseCaseOrchestrationSpec(
      useCases: <ApplicationUseCaseSpec>[placeOrderUc],
      sagas: <OrchestrationSagaSpec>[orderSaga],
    ),
  );

  return (
    catalog: DomainCatalog(domains: <FunctionalDomain>[domain]),
    orderModelEntryId: orderNode.id,
  );
}

void main() {
  group('EvolutionDriftBadge & SemVerBumpActionChip', () {
    testWidgets(
      'rend les états attendus, ouvre ArtifactEvolutionDiffDialog et applique le bump 1-clic',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final unchangedReport = ArtifactEvolutionReport(
          kind: DesignArtifactKind.valueObject,
          id: 'vo_ok',
          name: 'EmailAddress',
          state: ArtifactEvolutionState.unchanged,
          baselineVersion: '1.0.0',
          currentVersion: '1.0.0',
        );
        final modifiedMajorReport = ArtifactEvolutionReport(
          kind: DesignArtifactKind.model,
          id: 'mdl_order',
          name: 'CustomerOrder',
          subtitle: 'Commande client',
          state: ArtifactEvolutionState.modified,
          baselineVersion: '1.0.0',
          currentVersion: '1.0.0',
          directBump: SemVerBump.major,
          directChanges: const <ArtifactChangeEntry>[
            ArtifactChangeEntry(
              category: 'Attribut',
              summary: "- Attribut 'legacyRef' supprimé",
              impact: SemVerBump.major,
            ),
            ArtifactChangeEntry(
              category: 'Attribut',
              summary: "+ Attribut 'channel' (string) ajouté",
              impact: SemVerBump.minor,
            ),
          ],
        );
        final impactedReport = ArtifactEvolutionReport(
          kind: DesignArtifactKind.useCase,
          id: 'uc_1',
          name: 'PlaceOrder',
          state: ArtifactEvolutionState.impacted,
          baselineVersion: '1.2.0',
          currentVersion: '1.2.0',
          effectiveBump: SemVerBump.minor,
          impactedBy: const <String>['Modèle CustomerOrder (Mineur)'],
        );

        String? appliedFromChip;
        String? appliedFromDialog;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const EvolutionDriftBadge(
                      key: ValueKey('badge-null'),
                      report: null,
                    ),
                    EvolutionDriftBadge(
                      key: const ValueKey('badge-unchanged'),
                      report: unchangedReport,
                    ),
                    EvolutionDriftBadge(
                      key: const ValueKey('badge-modified'),
                      report: modifiedMajorReport,
                      onTap: () => ArtifactEvolutionDiffDialog.show(
                        context,
                        report: modifiedMajorReport,
                        baselineLabel: 'Itération 1',
                        onApplyRecommendedVersion: (v) => appliedFromDialog = v,
                      ),
                    ),
                    EvolutionDriftBadge(
                      key: const ValueKey('badge-impacted'),
                      report: impactedReport,
                    ),
                    SemVerBumpActionChip(
                      key: const ValueKey('chip-unchanged'),
                      report: unchangedReport,
                      onApplyVersion: (_) {},
                    ),
                    SemVerBumpActionChip(
                      key: const ValueKey('chip-impacted'),
                      report: impactedReport,
                      onApplyVersion: (v) => appliedFromChip = v,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Les badges null / unchanged ne rendent aucun texte.
        expect(find.text('Conforme'), findsNothing);
        expect(find.text('Δ depuis v1.0.0 · Majeur'), findsOneWidget);
        expect(find.text('⇄ Impacté (1)'), findsOneWidget);
        expect(find.text('Bump v1.2.0 → v1.3.0 (Mineur)'), findsOneWidget);

        // Clic 1-clic sur SemVerBumpActionChip.
        await tester.tap(find.byKey(const ValueKey('chip-impacted')));
        await tester.pumpAndSettle();
        expect(appliedFromChip, '1.3.0');

        // Clic sur EvolutionDriftBadge -> ouvre ArtifactEvolutionDiffDialog.
        await tester.tap(find.byKey(const ValueKey('badge-modified')));
        await tester.pumpAndSettle();

        expect(find.text('v1.0.0 → v1.0.0'), findsOneWidget);
        expect(find.text('SemVer : Majeur (Breaking)'), findsOneWidget);
        expect(find.text('Attribut (2)'), findsOneWidget);
        expect(find.text("Attribut 'legacyRef' supprimé"), findsOneWidget);
        expect(find.text("Attribut 'channel' (string) ajouté"), findsOneWidget);
        expect(find.text('Appliquer v2.0.0'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('artifact-diff-apply-version-btn')),
        );
        await tester.pumpAndSettle();
        expect(appliedFromDialog, '2.0.0');
      },
    );

    testWidgets(
      'gère le mode compact des badges Nouveau / Supprimé / Δ et un panneau étroit sans débordement',
      (tester) async {
        tester.view.physicalSize = const Size(640, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final sample = _buildSampleSalesCatalog();
        final controller = await _createController(sample.catalog);
        addTearDown(controller.dispose);

        await controller.createDomainIterationSnapshot(
          'dom_sales',
          label: 'Itération 1 — Socle compact',
        );

        final addedReport = ArtifactEvolutionReport(
          kind: DesignArtifactKind.valueObject,
          id: 'vo_new',
          name: 'PhoneNumber',
          state: ArtifactEvolutionState.added,
          currentVersion: '1.0.0',
        );
        final removedReport = ArtifactEvolutionReport(
          kind: DesignArtifactKind.saga,
          id: 'saga_old',
          name: 'LegacySaga',
          state: ArtifactEvolutionState.removed,
          baselineVersion: '1.0.0',
          currentVersion: '1.0.0',
          directBump: SemVerBump.major,
        );
        final modifiedCompactReport = ArtifactEvolutionReport(
          kind: DesignArtifactKind.model,
          id: 'mdl_1',
          name: 'Invoice',
          state: ArtifactEvolutionState.modified,
          baselineVersion: '1.0.0',
          currentVersion: '1.0.0',
          directBump: SemVerBump.minor,
        );
        final noBaselineReport = ArtifactEvolutionReport(
          kind: DesignArtifactKind.useCase,
          id: 'uc_none',
          name: 'DraftUc',
          state: ArtifactEvolutionState.noBaseline,
          currentVersion: '0.1.0',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 580,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DomainIterationSnapshotBar(
                      controller: controller,
                      domain: controller.domainCatalog.domains.single,
                      compact: true,
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        EvolutionDriftBadge(report: addedReport, compact: true),
                        EvolutionDriftBadge(
                          report: removedReport,
                          compact: true,
                        ),
                        EvolutionDriftBadge(
                          report: modifiedCompactReport,
                          compact: true,
                        ),
                        EvolutionDriftBadge(
                          report: noBaselineReport,
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nouveau'), findsOneWidget);
        expect(find.text('Supprimé'), findsOneWidget);
        expect(find.text('Δ Mineur'), findsOneWidget);
        expect(find.text('Sans jalon'), findsNothing);
        expect(find.text('Conforme au jalon'), findsOneWidget);
      },
    );
  });

  group('DomainIterationSnapshotBar & dialogues de jalons / évolution', () {
    testWidgets(
      'capture Itération 1, détecte la dérive en direct, inspecte les diffs et applique les bumps SemVer',
      (tester) async {
        tester.view.physicalSize = const Size(1560, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final sample = _buildSampleSalesCatalog();
        final controller = await _createController(sample.catalog);
        addTearDown(controller.dispose);

        final initialDomain = controller.domainCatalog.domains.single;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  DomainIterationSnapshotBar(
                    controller: controller,
                    domain: initialDomain,
                  ),
                ],
              ),
            ),
          ),
        );

        // État initial sans jalon.
        expect(find.text('Jalon de référence : Aucun'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('snapshot-bar-manage-dom_sales')),
          findsNothing,
        );

        // Capture de l'Itération 1 via CreateIterationSnapshotDialog.
        await tester.tap(
          find.byKey(const ValueKey('snapshot-bar-capture-dom_sales')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            '1 modèles/contrats, 2 Value Objects, 1 Use Cases, 1 Sagas',
          ),
          findsOneWidget,
        );
        final labelField = tester.widget<TextField>(
          find.byKey(const ValueKey('create-snapshot-label-field')),
        );
        expect(labelField.controller?.text, 'Itération 1');

        await tester.enterText(
          find.byKey(const ValueKey('create-snapshot-label-field')),
          'Itération 1 — MVP Ventes',
        );
        await tester.enterText(
          find.byKey(const ValueKey('create-snapshot-notes-field')),
          'Périmètre validé en sprint 1.',
        );
        await tester.tap(
          find.byKey(const ValueKey('create-snapshot-submit-btn')),
        );
        await tester.pumpAndSettle();

        // La barre affiche désormais « Conforme au jalon » et le bouton d'historique.
        expect(find.text('Conforme au jalon'), findsOneWidget);
        expect(
          find.textContaining('Itération 1 — MVP Ventes (Itération #1 · '),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('snapshot-bar-manage-dom_sales')),
          findsOneWidget,
        );

        // Mutations métier sur le contrôleur :
        // 1) Assouplissement mineur de OrderAmount (impacte CustomerOrder -> PlaceCustomerOrder -> CustomerOrderSaga)
        // 2) Ajout d'un nouveau VO CustomerComment
        // 3) Suppression du VO LegacyDiscountCode
        final currentAmountVo = controller
            .domainCatalog
            .domains
            .single
            .valueObjects
            .firstWhere((v) => v.id == 'vo_amount');
        await controller.upsertValueObject(
          currentAmountVo.copyWith(
            schemaConstraints: JsonSchemaConstraints(
              minimum: 0,
              maximum: 50000,
            ),
          ),
          scope: ValueObjectScope.domain,
          domainId: 'dom_sales',
        );
        await controller.upsertValueObject(
          ValueObjectSpec(
            id: 'vo_comment',
            technicalName: 'CustomerComment',
            name: 'Commentaire client',
            version: '1.0.0',
          ),
          scope: ValueObjectScope.domain,
          domainId: 'dom_sales',
        );
        await controller.deleteValueObject(
          'vo_legacy',
          scope: ValueObjectScope.domain,
          domainId: 'dom_sales',
        );
        await tester.pumpAndSettle();

        // Les compteurs se mettent à jour en direct sur DomainIterationSnapshotBar.
        expect(find.text('Conforme au jalon'), findsNothing);
        expect(find.text('+1 nouveau(x)'), findsOneWidget);
        expect(find.text('Δ 1 modifié(s)'), findsOneWidget);
        expect(find.text('⇄ 3 impacté(s)'), findsOneWidget);
        expect(find.text('-1 supprimé(s)'), findsOneWidget);

        // Clic sur la puce « Δ 1 modifié(s) » -> ouvre DomainEvolutionSummaryDialog.
        await tester.tap(
          find.byKey(const ValueKey('snapshot-bar-summary-modified-dom_sales')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Synthèse d’évolution — Ventes'), findsOneWidget);
        expect(find.text('Tout bumper (SemVer suggéré)'), findsOneWidget);

        // Vérifie le filtrage par état dans DomainEvolutionSummaryDialog.
        await tester.tap(
          find.byKey(const ValueKey('domain-evolution-filter-removed')),
        );
        await tester.pumpAndSettle();
        expect(find.text('LegacyDiscountCode'), findsOneWidget);
        expect(find.text('CustomerOrder'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('domain-evolution-filter-all')),
        );
        await tester.pumpAndSettle();

        // Inspection du diff d'un artefact impacté (CustomerOrder) en cliquant sa ligne.
        await tester.tap(
          find.byKey(
            ValueKey('domain-evolution-row-model-${sample.orderModelEntryId}'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('artifact-diff-impacted-section')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(ArtifactEvolutionDiffDialog),
            matching: find.textContaining(
              'Value Object OrderAmount (v1.0.0 → v1.1.0 · Mineur)',
            ),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('artifact-diff-close-btn')));
        await tester.pumpAndSettle();

        // Bump unitaire sur OrderAmount depuis sa ligne dans DomainEvolutionSummaryDialog.
        await tester.tap(
          find.byKey(
            const ValueKey('domain-evolution-bump-valueObject-vo_amount'),
          ),
        );
        await tester.pumpAndSettle();

        final bumpedVo = controller.domainCatalog.domains.single.valueObjects
            .firstWhere((v) => v.id == 'vo_amount');
        expect(bumpedVo.version, '1.1.0');

        // Bump global « Tout bumper (SemVer suggéré) » pour le modèle, le UC et la Saga impactés.
        await tester.tap(
          find.byKey(const ValueKey('domain-evolution-bump-all-btn')),
        );
        await tester.pumpAndSettle();

        // Plus aucun artefact n'a besoin de bump -> le bouton global disparaît.
        expect(
          find.byKey(const ValueKey('domain-evolution-bump-all-btn')),
          findsNothing,
        );
        final updatedDomain = controller.domainCatalog.domains.single;
        expect(
          updatedDomain.contracts!.details[sample.orderModelEntryId]!.version,
          '1.1.0',
        );
        expect(
          updatedDomain.useCaseOrchestration!.useCases.single.version,
          '1.1.0',
        );
        expect(
          updatedDomain.useCaseOrchestration!.sagas.single.version,
          '1.1.0',
        );

        await tester.tap(
          find.byKey(const ValueKey('domain-evolution-close-btn')),
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'gère plusieurs jalons (bascule, désactivation et suppression avec confirmation) via ManageIterationSnapshotsDialog',
      (tester) async {
        tester.view.physicalSize = const Size(1560, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final sample = _buildSampleSalesCatalog();
        final controller = await _createController(sample.catalog);
        addTearDown(controller.dispose);

        final snap1 = await controller.createDomainIterationSnapshot(
          'dom_sales',
          label: 'Itération 1',
          notes: 'Premier jalon',
        );
        // Ajout d'un VO puis capture de l'Itération 2.
        await controller.upsertValueObject(
          ValueObjectSpec(
            id: 'vo_vip_tier',
            technicalName: 'VipTier',
            name: 'Palier VIP',
            version: '1.0.0',
          ),
          scope: ValueObjectScope.domain,
          domainId: 'dom_sales',
        );
        final snap2 = await controller.createDomainIterationSnapshot(
          'dom_sales',
          label: 'Itération 2',
          notes: 'Second jalon avec VIP',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  DomainIterationSnapshotBar(
                    controller: controller,
                    domain: controller.domainCatalog.domains.single,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Sur l'Itération 2 active, le domaine est conforme.
        expect(find.text('Conforme au jalon'), findsOneWidget);

        // Ouvre ManageIterationSnapshotsDialog depuis l'icône d'historique.
        await tester.tap(
          find.byKey(const ValueKey('snapshot-bar-manage-dom_sales')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Historique des jalons — Ventes (2)'), findsOneWidget);
        expect(
          find.byKey(ValueKey('manage-snapshot-active-badge-${snap2.id}')),
          findsOneWidget,
        );

        // Bascule sur l'Itération 1 comme référence active.
        await tester.tap(
          find.byKey(ValueKey('manage-snapshot-toggle-${snap1.id}')),
        );
        await tester.pumpAndSettle();

        expect(
          controller.domainCatalog.domains.single.activeBaselineSnapshotId,
          snap1.id,
        );
        expect(
          find.byKey(ValueKey('manage-snapshot-active-badge-${snap1.id}')),
          findsOneWidget,
        );

        // Ferme le dialogue : la barre affiche désormais « +1 nouveau(x) » (VipTier).
        await tester.tap(
          find.byKey(const ValueKey('manage-snapshots-close-btn')),
        );
        await tester.pumpAndSettle();
        expect(find.text('+1 nouveau(x)'), findsOneWidget);

        // Désactive la comparaison depuis le sélecteur de la barre.
        await tester.tap(
          find.byKey(const ValueKey('snapshot-bar-selector-dom_sales')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('snapshot-bar-disable-dom_sales')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Jalon de référence : Aucun'), findsOneWidget);

        // Réactive snap2 via le sélecteur de la barre, puis supprime snap2 depuis ManageIterationSnapshotsDialog.
        await tester.tap(
          find.byKey(const ValueKey('snapshot-bar-selector-dom_sales')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('snapshot-bar-option-${snap2.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Conforme au jalon'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('snapshot-bar-manage-dom_sales')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(ValueKey('manage-snapshot-delete-${snap2.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('manage-snapshot-confirm-delete-btn')),
        );
        await tester.pumpAndSettle();

        // Après suppression de snap2 (qui était actif), la baseline retombe automatiquement sur snap1.
        final remainingDomain = controller.domainCatalog.domains.single;
        expect(remainingDomain.iterationSnapshots.single.id, snap1.id);
        expect(remainingDomain.activeBaselineSnapshotId, snap1.id);
      },
    );
  });
}
