import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_contract_tabs_store'));

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
    : super(Directory('memory_contract_tabs_store'));

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
    : super(Directory('memory_contract_tabs_store'));

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
    : super(Directory('memory_contract_tabs_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _NoopSpecAiService implements SpecAiService {
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

void main() {
  group('SpecSchemaDslBridge.applySingleObjectYamlSource', () {
    test('résout les références vers d’autres entrées du domaine et refuse un renommage de la racine', () {
      final current = BusinessObjectSpec(
        id: 'entry_cmd',
        name: 'Commande',
        technicalName: 'Commande',
        description: 'Commande client',
        attributes: [
          BusinessAttribute(
            id: 'attr_id',
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
            unique: true,
            description: 'Clé primaire conservée',
          ),
        ],
      );

      final updated = SpecSchemaDslBridge.applySingleObjectYamlSource(
        '''
Commande:
  id: uuid!
  client: Client!
  montantTotal: number!
''',
        current: current,
        referenceTargets: const {'entry_client': 'Client'},
      );

      expect(updated.id, 'entry_cmd');
      expect(updated.description, 'Commande client');
      expect(updated.attributes, hasLength(3));
      // Métadonnées existantes de id conservées
      expect(updated.attributes.first.id, 'attr_id');
      expect(updated.attributes.first.unique, isTrue);
      expect(updated.attributes.first.description, 'Clé primaire conservée');
      // Référence intra-domaine résolue vers entry_client
      final clientAttr = updated.attributes[1];
      expect(clientAttr.type, BusinessAttributeType.reference);
      expect(clientAttr.referenceObjectId, 'entry_client');
      expect(clientAttr.required, isTrue);

      // Refuse le renommage de la clé racine
      expect(
        () => SpecSchemaDslBridge.applySingleObjectYamlSource(
          'AutreNom:\n  id: uuid!\n',
          current: current,
          referenceTargets: const {},
        ),
        throwsFormatException,
      );

      // Refuse un type inconnu hors domaine
      expect(
        () => SpecSchemaDslBridge.applySingleObjectYamlSource(
          'Commande:\n  inconnu: TypeInexistant!\n',
          current: current,
          referenceTargets: const {},
        ),
        throwsFormatException,
      );
    });
  });

  testWidgets(
    'Design › Fiche modèle : onglets Objet, Repository (JSON Schema & Seed) et DSL (édition + application YAML)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var contracts = DomainContracts.parse(
        'models:\n  CommandeClient: model\n  Client: model\ncomponents:\n',
      );
      final cmdEntry = SpecDesignPromoter.findExistingEntry(
        contracts,
        'CommandeClient',
      )!;
      final clientEntry = SpecDesignPromoter.findExistingEntry(
        contracts,
        'Client',
      )!;
      contracts = contracts.withModel(
        cmdEntry.id,
        object: BusinessObjectSpec(
          id: cmdEntry.id,
          name: 'Commande client',
          technicalName: 'CommandeClient',
          description: 'Engagement client',
          attributes: [
            BusinessAttribute(
              id: 'attr_cmd_id',
              name: 'id',
              type: BusinessAttributeType.uuid,
              required: true,
              unique: true,
            ),
            BusinessAttribute(
              id: 'attr_cmd_montant',
              name: 'montantHt',
              type: BusinessAttributeType.number,
              required: true,
            ),
          ],
        ),
      );

      final catalogStore = _MemoryDomainCatalogStore(
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
      );
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        domainCatalogStore: catalogStore,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        aiService: _NoopSpecAiService(),
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
              schemaViewerSurfaceBuilder: (context, file, _) => Text(
                'HTML:${file.path}',
                key: const ValueKey('fake-html-surface'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ouvre la fiche de CommandeClient
      await tester.tap(
        find.byKey(const ValueKey('open-models.CommandeClient')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('contract-model-object-tab')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('contract-model-repository-tab')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('contract-model-dsl-tab')),
        findsOneWidget,
      );

      // Onglet 2 : Repository (SpecJsonSchemaViewerView uniquement pour CommandeClient)
      await tester.tap(
        find.byKey(const ValueKey('contract-model-repository-tab')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('contract-model-schema-viewer')),
        findsOneWidget,
      );
      expect(find.textContaining('commande_client'), findsWidgets);

      // Onglet 3 : DSL (CodeEditor YAML Light + Appliquer le YAML)
      await tester.tap(find.byKey(const ValueKey('contract-model-dsl-tab')));
      await tester.pumpAndSettle();

      final yamlEditorFinder = find.byKey(
        const ValueKey('contract-model-yaml-editor'),
      );
      expect(yamlEditorFinder, findsOneWidget);

      final editorState = tester.state<CodeEditorState>(yamlEditorFinder);
      expect(editorState.controller.fullText, contains('CommandeClient:'));
      expect(editorState.controller.fullText, contains('montantHt: number!'));

      // Modifie le YAML en ajoutant une référence vers Client et un champ devise
      editorState.controller.fullText = '''
CommandeClient:
  id: uuid!
  montantHt: number!
  client: Client!
  devise: string = EUR
''';
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('contract-model-apply-yaml')));
      await tester.pumpAndSettle();

      final savedDoc = controller.domainCatalog.domains.single.contracts!;
      final savedObj = savedDoc.objectFor(savedDoc.entryById(cmdEntry.id)!);
      expect(savedObj.attributes.map((a) => a.name), [
        'id',
        'montantHt',
        'client',
        'devise',
      ]);
      final savedClientAttr = savedObj.attributes.firstWhere(
        (a) => a.name == 'client',
      );
      expect(savedClientAttr.type, BusinessAttributeType.reference);
      expect(savedClientAttr.referenceObjectId, clientEntry.id);

      // Retour à l'onglet Objet : le nouvel attribut apparaît dans l'arbre
      await tester.tap(find.byKey(const ValueKey('contract-model-object-tab')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('contract-model-tree-pane')),
          matching: find.text('devise'),
        ),
        findsOneWidget,
      );
    },
  );
}
