import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';
import 'package:super_spec_forge/widgets/workspace/event_storming/event_storming_dialogs.dart';

const String _referenceGestionCommandesYaml = '''
# yaml-language-server: \$schema=./es-dsl.schema.json
event_storming:
  dsl_version: "1.0"

  meta:
    domain: "E-Commerce"
    bounded_context: "Gestion des commandes"
    format: "process_modeling"
    date: "2026-11-24"
    facilitator: "Product Owner"

  catalog:
    actors:
      - id: "ACT-CLIENT"
        name: "Client"
        type: "human"
    aggregates:
      - id: "AGG-COMMANDE"
        name: "Commande"
      - id: "AGG-STOCK"
        name: "StockProduit"
      - id: "AGG-EXPEDITION"
        name: "Expédition"
    external_systems:
      - id: "EXT-STRIPE"
        name: "Stripe"
      - id: "EXT-EMAIL"
        name: "Service Notification Email"

  flow:
    - step: 1
      backlog:
        epic: "EPIC-01"
        story: "US-101"
      read_model:
        name: "Écran récapitulatif panier"
        source_events: ["EVT-00"]
        fields: ["lignes_panier", "montant_ttc", "adresse_livraison"]
      actor: "ACT-CLIENT"
      command:
        name: "Valider le panier"
        payload: ["panier_id", "mode_paiement_id"]
      aggregate: "AGG-COMMANDE"
      domain_event:
        id: "EVT-01"
        name: "Panier validé"
        data: ["commande_id", "client_id", "articles", "montant_ttc"]
      hotspots:
        - id: "HS-01"
          question: "Appliquer le code promo avant ou après le calcul des frais de port ?"
          severity: "high"
          owner: "PO + Métier Pricing"
          status: "open"

    - step: 2
      backlog:
        epic: "EPIC-01"
        story: "US-102"
      triggered_by: "EVT-01"
      policy:
        name: "Déclencher l'encaissement"
        rule: "Quand Panier validé, alors Demander le paiement"
      command:
        name: "Demander le paiement"
        payload: ["commande_id", "montant_ttc", "mode_paiement_id"]
      external_system: "EXT-STRIPE"
      outcomes:
        - condition: "Autorisation bancaire accordée"
          is_error: false
          domain_event:
            id: "EVT-02A"
            name: "Commande payée"
            data: ["commande_id", "transaction_id"]
        - condition: "Fonds insuffisants ou carte expirée"
          is_error: true
          domain_event:
            id: "EVT-02B"
            name: "Paiement refusé"
            data: ["commande_id", "motif_refus"]

    - step: 3
      backlog:
        epic: "EPIC-02"
        story: "US-201"
      triggered_by: "EVT-02A"
      policy:
        name: "Allouer les articles"
        rule: "Quand Commande payée, alors Réserver le stock"
      command:
        name: "Réserver le stock"
        payload: ["commande_id", "articles"]
      aggregate: "AGG-STOCK"
      outcomes:
        - condition: "Quantité disponible en entrepôt"
          is_error: false
          domain_event:
            id: "EVT-03A"
            name: "Stock réservé"
            data: ["commande_id", "entrepot_id"]
        - condition: "Stock épuisé entre la validation et le paiement"
          is_error: true
          domain_event:
            id: "EVT-03B"
            name: "Rupture de stock détectée"
            data: ["commande_id", "articles_manquants"]

    - step: 4
      backlog:
        epic: "EPIC-01"
        story: "US-103"
      triggered_by: "EVT-02A"
      policy:
        name: "Confirmer l'achat au client"
        rule: "Quand Commande payée, alors Envoyer le reçu"
      command:
        name: "Envoyer l'email de confirmation"
        payload: ["commande_id", "client_id", "transaction_id"]
      external_system: "EXT-EMAIL"
      domain_event:
        id: "EVT-04"
        name: "Confirmation envoyée"
        data: ["commande_id", "email_id"]

    - step: 5
      backlog:
        epic: "EPIC-02"
        story: "US-202"
      triggered_by:
        all_of: ["EVT-03A", "EVT-04"]
      policy:
        name: "Libérer pour la logistique"
        rule: "Quand Stock réservé ET Confirmation envoyée, alors Créer le bon d'expédition"
      command:
        name: "Créer le bon d'expédition"
        payload: ["commande_id", "entrepot_id"]
      aggregate: "AGG-EXPEDITION"
      domain_event:
        id: "EVT-05"
        name: "Bon d'expédition créé"
        data: ["commande_id", "bon_id"]

    - step: 6
      backlog:
        epic: "EPIC-01"
        story: "US-104"
      triggered_by:
        any_of: ["EVT-02B", "EVT-03B"]
      policy:
        name: "Clôturer les commandes en échec"
        rule: "Quand Paiement refusé OU Rupture de stock détectée, alors Annuler la commande"
      command:
        name: "Annuler la commande"
        payload: ["commande_id", "motif"]
      aggregate: "AGG-COMMANDE"
      domain_event:
        id: "EVT-06"
        name: "Commande annulée"
        data: ["commande_id", "motif_annulation"]
''';

class _MemProjectStore extends SpecProjectStore {
  _MemProjectStore() : super(Directory('memory_es_store'));

  final Map<String, SpecForgeProject> _projects = {};
  String? _lastId;

  void seed(SpecForgeProject project) {
    _projects[project.id] = project;
    _lastId = project.id;
  }

  @override
  Future<void> saveProject(SpecForgeProject project) async {
    project.validate();
    _projects[project.id] = project;
    _lastId = project.id;
  }

  @override
  Future<SpecForgeProject?> loadProject(String projectId) async =>
      _projects[projectId];

  @override
  Future<void> deleteProject(String projectId) async {
    _projects.remove(projectId);
    if (_lastId == projectId) _lastId = null;
  }

  @override
  Future<List<SpecProjectSummary>> listProjects() async => [
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

  @override
  Future<String?> getLastActiveProjectId() async => _lastId;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {
    _lastId = projectId;
  }
}

class _MemGlossaryStore extends CompanyGlossaryStore {
  _MemGlossaryStore() : super(Directory('memory_es_store'));

  @override
  Future<CompanyGlossary> loadGlossary() async => CompanyGlossary.empty;

  @override
  Future<void> saveGlossary(CompanyGlossary glossary) async {}

  @override
  Future<List<SpecChatMessage>> loadChatMessages() async => const [];

  @override
  Future<void> saveChatMessages(List<SpecChatMessage> messages) async {}
}

class _MemDictStore extends ModelDictionaryStore {
  _MemDictStore() : super(Directory('memory_es_store'));

  @override
  Future<BusinessObjectModelPreferences> load() async =>
      BusinessObjectModelPreferences.defaults;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {}
}

class _MemDomainStore extends DomainCatalogStore {
  _MemDomainStore() : super(Directory('memory_es_store'));

  @override
  Future<DomainCatalog> load() async => DomainCatalog.empty;

  @override
  Future<void> save(DomainCatalog catalog) async {}
}

class _MemRateCardStore extends EnterpriseRateCardStore {
  _MemRateCardStore() : super(Directory('memory_es_store'));

  @override
  Future<EnterpriseRateCard> load() async => EnterpriseRateCard.defaults;

  @override
  Future<void> save(EnterpriseRateCard card) async {}
}

class _FakeEventStormingAi implements SpecAiService {
  final List<SpecForgeStage> calledStages = [];
  final List<String> receivedPrompts = [];

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
    final payload = jsonEncode(<String, Object?>{
      'message':
          'Bounded Context facturation.es.yaml modélisé en Event Storming DSL v1.0.',
      'askUser': null,
      'specPatch': <String, Object?>{
        'eventStorming': <String, Object?>{
          'documents': <Object?>[
            <String, Object?>{
              'id': 'facturation',
              'event_storming': <String, Object?>{
                'dsl_version': '1.0',
                'meta': <String, Object?>{
                  'domain': 'E-Commerce',
                  'bounded_context': 'Facturation',
                  'format': 'process_modeling',
                  'date': '2026-11-24',
                  'facilitator': 'Product Owner',
                },
                'catalog': <String, Object?>{
                  'aggregates': <Object?>[
                    <String, Object?>{'id': 'AGG-FACTURE', 'name': 'Facture'},
                  ],
                },
                'flow': <Object?>[
                  <String, Object?>{
                    'step': 1,
                    'backlog': <String, Object?>{
                      'epic': 'EPIC-03',
                      'story': 'US-301',
                    },
                    'triggered_by': 'CMD:EVT-02A',
                    'policy': <String, Object?>{
                      'name': 'Émettre la facture',
                      'rule':
                          'Quand Commande payée, alors Générer la facture',
                    },
                    'command': <String, Object?>{
                      'name': 'Générer la facture',
                      'payload': <String>['commande_id', 'montant_ttc'],
                    },
                    'aggregate': 'AGG-FACTURE',
                    'domain_event': <String, Object?>{
                      'id': 'EVT-01',
                      'name': 'Facture émise',
                      'data': <String>['facture_id', 'commande_id'],
                    },
                  },
                ],
              },
            },
          ],
        },
      },
      'stageSummary': 'Contexte Facturation modélisé',
      'stageReadyToAdvance': true,
    });
    yield GeminiStreamEvent(
      deltaText: payload,
      accumulatedText: payload,
      isDone: true,
      usedContextCache: false,
    );
  }
}

SpecForgeProject _buildSampleProject({
  EventStormingSpec? eventStorming,
  SpecForgeStage currentStage = SpecForgeStage.eventStorming,
}) {
  final now = DateTime.utc(2026, 11, 24, 19);
  return SpecForgeProject(
    id: 'proj_es_test',
    name: 'E-Commerce',
    initialIdea:
        'Plateforme e-commerce avec paiement Stripe, gestion stock et expédition',
    createdAt: now,
    updatedAt: now,
    currentStage: currentStage,
    vision: SpecVision(
      personas: [
        SpecPersona(
          id: 'p_client',
          name: 'Client',
          role: 'Valide son panier et paie sa commande',
        ),
      ],
    ),
    cahierDesCharges: SpecCahierDesCharges(
      modules: const [
        SpecModule(
          id: 'mod_cmd',
          name: 'Gestion des commandes',
          description: 'Validation panier, paiement et expédition',
        ),
      ],
      functionalRequirements: [
        FunctionalRequirement(
          id: 'req_1',
          code: 'EXF-001',
          title: 'Valider le panier',
          moduleId: 'mod_cmd',
          actorIds: const ['p_client'],
        ),
      ],
      useCases: [
        UseCaseSpec(
          id: 'uc_valider_panier',
          title: 'Valider le panier',
          actorId: 'p_client',
          mainFlow: const ['Vérifier lignes', 'Valider montant'],
          alternativeFlows: const ['Fonds insuffisants'],
          postconditions: const ['Panier validé'],
        ),
      ],
    ),
    eventStorming: eventStorming,
  );
}

void main() {
  group('Event Storming DSL v1.0 : YAML, Schéma, Validation & Migration', () {
    test('SpecForgeStage compte 8 étapes avec eventStorming en étape 4', () {
      expect(SpecForgeStage.values.length, 8);
      expect(SpecForgeStage.eventStorming.stepNumber, 4);
      expect(SpecForgeStage.specifications.next, SpecForgeStage.eventStorming);
      expect(
        SpecForgeStage.eventStorming.previous,
        SpecForgeStage.specifications,
      );
      expect(SpecForgeStage.eventStorming.next, SpecForgeStage.businessObjects);
    });

    test(
      'Round-trip complet du fichier de référence gestion-commandes.es.yaml (séquence, outcomes, parallèle, all_of, any_of)',
      () {
        final doc = EventStormingDslCodec.fromYaml(
          _referenceGestionCommandesYaml,
          idHint: 'gestion-commandes',
        );

        expect(doc.id, 'gestion-commandes');
        expect(doc.fileName, 'gestion-commandes.es.yaml');
        expect(doc.dslVersion, '1.0');
        expect(doc.meta.domain, 'E-Commerce');
        expect(doc.meta.boundedContext, 'Gestion des commandes');
        expect(doc.meta.format, EventStormFormat.processModeling);
        expect(doc.meta.date, '2026-11-24');
        expect(doc.meta.facilitator, 'Product Owner');

        // Catalogue complet : 1 acteur, 3 agrégats, 2 systèmes externes
        expect(doc.catalog.actors, hasLength(1));
        expect(doc.catalog.actors.single.id, 'ACT-CLIENT');
        expect(doc.catalog.actors.single.type, EventStormActorType.human);
        expect(doc.catalog.aggregates, hasLength(3));
        expect(doc.catalog.externalSystems, hasLength(2));
        expect(doc.catalog.externalSystems.first.id, 'EXT-STRIPE');

        // 6 étapes couvrant tous les mécanismes
        expect(doc.flow, hasLength(6));
        expect(doc.flow[0].backlog?.epic, 'EPIC-01');
        expect(doc.flow[0].backlog?.story, 'US-101');
        expect(doc.flow[0].readModel?.name, 'Écran récapitulatif panier');
        expect(doc.flow[0].readModel?.sourceEvents, ['EVT-00']);
        expect(doc.flow[0].hotspots.single.id, 'HS-01');
        expect(
          doc.flow[0].hotspots.single.severity,
          EventStormHotspotSeverity.high,
        );

        // Étape 2 : OU exclusif (outcomes) + système externe EXT-STRIPE
        expect(doc.flow[1].triggeredBy?.mode, EventStormTriggerMode.single);
        expect(doc.flow[1].triggeredBy?.singleEventId, 'EVT-01');
        expect(doc.flow[1].externalSystem, 'EXT-STRIPE');
        expect(doc.flow[1].hasOutcomes, isTrue);
        expect(doc.flow[1].domainEvent, isNull);
        expect(doc.flow[1].outcomes, hasLength(2));
        expect(doc.flow[1].outcomes[0].isError, isFalse);
        expect(doc.flow[1].outcomes[0].domainEvent.id, 'EVT-02A');
        expect(doc.flow[1].outcomes[1].isError, isTrue);
        expect(doc.flow[1].outcomes[1].domainEvent.id, 'EVT-02B');

        // Étapes 3 & 4 : ET parallèle sur EVT-02A
        expect(doc.flow[2].triggeredBy?.singleEventId, 'EVT-02A');
        expect(doc.flow[3].triggeredBy?.singleEventId, 'EVT-02A');

        // Étape 5 : Synchronisation ET (all_of)
        expect(doc.flow[4].triggeredBy?.mode, EventStormTriggerMode.allOf);
        expect(doc.flow[4].triggeredBy?.eventIds, ['EVT-03A', 'EVT-04']);

        // Étape 6 : Convergence OU (any_of)
        expect(doc.flow[5].triggeredBy?.mode, EventStormTriggerMode.anyOf);
        expect(doc.flow[5].triggeredBy?.eventIds, ['EVT-02B', 'EVT-03B']);

        // Validation stricte DSL v1.0 : 0 erreur et 0 avertissement grammatical !
        final diagnostics = EventStormingDslCodec.validateDocument(doc);
        expect(diagnostics, isEmpty);

        // Re-sérialisation YAML -> re-parsing == identique
        final exportedYaml = EventStormingDslCodec.toYaml(doc);
        expect(
          exportedYaml,
          startsWith('# yaml-language-server: \$schema=./es-dsl.schema.json'),
        );
        expect(exportedYaml, contains('all_of: ["EVT-03A", "EVT-04"]'));
        expect(exportedYaml, contains('any_of: ["EVT-02B", "EVT-03B"]'));
        final reparsed = EventStormingDslCodec.fromYaml(
          exportedYaml,
          idHint: 'gestion-commandes',
        );
        expect(reparsed, equals(doc));
      },
    );

    test(
      'Schéma es-dsl.schema.json et validation détectent erreurs de références et avertissements grammaticaux',
      () {
        final schema = jsonDecode(EventStormingDslCodec.esDslSchemaJson) as Map;
        expect(schema['title'], 'Event Storming DSL v1.0');
        expect(schema['required'], ['event_storming']);

        // Exclusivité mutuelle domain_event vs outcomes rejetée par validate()
        expect(
          () => EventStormStep(
            step: 1,
            command: EventStormCommand(name: 'Valider le panier'),
            domainEvent: EventStormDomainEvent(
              id: 'EVT-01',
              name: 'Panier validé',
            ),
            outcomes: [
              EventStormOutcome(
                condition: 'OK',
                domainEvent: EventStormDomainEvent(
                  id: 'EVT-01A',
                  name: 'Panier validé',
                ),
              ),
              EventStormOutcome(
                condition: 'KO',
                isError: true,
                domainEvent: EventStormDomainEvent(
                  id: 'EVT-01B',
                  name: 'Panier refusé',
                ),
              ),
            ],
          ).validate(),
          throwsFormatException,
        );

        // Référence catalogue manquante + grammaire non conforme (non bloquants)
        final flawedDoc = EventStormDocument(
          id: 'test-bc',
          meta: const EventStormMeta(
            domain: 'Test',
            boundedContext: 'Test BC',
            date: '2026-11-24',
          ),
          flow: [
            EventStormStep(
              step: 1,
              actor: 'ACT-INCONNU',
              command: EventStormCommand(name: 'Validation panier'),
              domainEvent: EventStormDomainEvent(
                id: 'EVT-01',
                name: 'Panier en cours',
              ),
            ),
          ],
        );

        final diags = EventStormingDslCodec.validateDocument(flawedDoc);
        expect(diags.any((d) => d.code == 'DSL-ES-REF-ACTOR'), isTrue);
        expect(diags.any((d) => d.code == 'GRAM-ES-CMD'), isTrue);
        expect(diags.any((d) => d.code == 'GRAM-ES-EVT'), isTrue);
      },
    );

    test(
      'Supporte les références inter-Bounded Contexts (CMD:EVT-02A) sans faux positif',
      () {
        final cmdDoc = EventStormingDslCodec.fromYaml(
          _referenceGestionCommandesYaml,
          idHint: 'gestion-commandes',
        );
        final factDoc = EventStormDocument(
          id: 'facturation',
          meta: const EventStormMeta(
            domain: 'E-Commerce',
            boundedContext: 'Facturation',
            date: '2026-11-24',
          ),
          catalog: EventStormCatalog(
            aggregates: const [
              EventStormCatalogItem(id: 'AGG-FACTURE', name: 'Facture'),
            ],
          ),
          flow: [
            EventStormStep(
              step: 1,
              triggeredBy: EventStormTrigger.single('CMD:EVT-02A'),
              policy: const EventStormPolicy(
                name: 'Émettre la facture',
                rule: 'Quand Commande payée, alors Générer la facture',
              ),
              command: EventStormCommand(
                name: 'Générer la facture',
                payload: const ['commande_id'],
              ),
              aggregate: 'AGG-FACTURE',
              domainEvent: EventStormDomainEvent(
                id: 'EVT-01',
                name: 'Facture générée',
                data: const ['facture_id'],
              ),
            ),
          ],
        );

        final diags = EventStormingDslCodec.validateDocument(
          factDoc,
          allDocuments: [cmdDoc, factDoc],
        );
        expect(diags, isEmpty);
      },
    );

    test(
      'Migration rétrocompatible transparente depuis l’ancien format JSON nodes/links',
      () {
        final legacyJson = <String, Object?>{
          'boundedContexts': <Object?>[
            <String, Object?>{
              'id': 'bc_ventes',
              'code': 'BC-001',
              'name': 'Ventes',
            },
          ],
          'flows': <Object?>[
            <String, Object?>{
              'id': 'es_1',
              'code': 'ES-001',
              'title': 'Validation commande',
              'boundedContextIds': <String>['bc_ventes'],
              'requirementIds': <String>['EXF-001'],
              'nodes': <Object?>[
                <String, Object?>{
                  'id': 'n1',
                  'kind': 'actor',
                  'title': 'Client',
                  'sequenceOrder': 1,
                },
                <String, Object?>{
                  'id': 'n2',
                  'kind': 'command',
                  'title': 'Valider la commande',
                  'sequenceOrder': 2,
                  'payloadFields': <String>['commande_id'],
                },
                <String, Object?>{
                  'id': 'n3',
                  'kind': 'aggregate',
                  'title': 'Commande',
                  'sequenceOrder': 3,
                },
                <String, Object?>{
                  'id': 'n4',
                  'kind': 'domainEvent',
                  'code': 'EVT-01',
                  'title': 'Commande validée',
                  'sequenceOrder': 4,
                  'payloadFields': <String>['commande_id'],
                },
                <String, Object?>{
                  'id': 'n5',
                  'kind': 'hotspot',
                  'title': 'TVA intracommunautaire ?',
                  'sequenceOrder': 5,
                  'resolved': false,
                },
              ],
            },
          ],
        };

        final migrated = EventStormingSpec.fromJson(legacyJson);
        expect(migrated.documents, hasLength(1));
        final doc = migrated.documents.single;
        expect(doc.meta.boundedContext, 'Ventes');
        expect(doc.catalog.actors, hasLength(1));
        expect(doc.catalog.aggregates, hasLength(1));
        expect(doc.flow, hasLength(1));
        expect(doc.flow.single.command.name, 'Valider la commande');
        expect(doc.flow.single.domainEvent?.id, 'EVT-01');
        expect(doc.flow.single.hotspots, hasLength(1));
      },
    );

    test(
      'SpecProjectStore persiste 1 fichier <slug>.es.yaml par Bounded Context + es-dsl.schema.json et recharge à l’identique',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ssf_es_yaml_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final sep = Platform.pathSeparator;
        final store = SpecProjectStore(tempDir);
        final cmdDoc = EventStormingDslCodec.fromYaml(
          _referenceGestionCommandesYaml,
          idHint: 'gestion-commandes',
        );
        final project = _buildSampleProject(
          eventStorming: EventStormingSpec(documents: [cmdDoc]),
        );

        await store.saveProject(project);

        final esDir = Directory(
          '${tempDir.path}${sep}projects${sep}e-commerce${sep}spec${sep}event_storming',
        );
        final yamlFile = File(
          '${esDir.path}${sep}gestion-commandes.es.yaml',
        );
        final schemaFile = File('${esDir.path}${sep}es-dsl.schema.json');
        expect(await yamlFile.exists(), isTrue);
        expect(await schemaFile.exists(), isTrue);

        final reloaded = await store.loadProject(project.id);
        expect(reloaded, isNotNull);
        expect(reloaded!.eventStorming.documents, hasLength(1));
        expect(reloaded.eventStorming.documents.single, equals(cmdDoc));
      },
    );
  });

  group('Opérations déterministes, Cohérence, Export & Outils IA', () {
    test(
      'Seed depuis CDC, synthèse Objets métiers (avec outcomes) et promotion Politique -> RG-xxx',
      () {
        final base = _buildSampleProject();
        final seeded = EventStormingOperations.seedFromCahierDesCharges(base);
        expect(seeded.addedDocumentsCount, 1);
        expect(seeded.addedStepsCount, 1);
        final seededDoc = seeded.updated.documents.single;
        expect(seededDoc.flow.single.hasOutcomes, isTrue);

        // Synthèse Objets métiers depuis le document de référence complet
        final refDoc = EventStormingDslCodec.fromYaml(
          _referenceGestionCommandesYaml,
          idHint: 'gestion-commandes',
        );
        final projectWithRef = base.copyWith(
          eventStorming: EventStormingSpec(documents: [refDoc]),
        );

        final synth =
            EventStormingOperations.synthesizeBusinessObjectsFromEventStorming(
              projectWithRef,
            );
        expect(synth.createdObjectsCount, 3); // Commande, StockProduit, Expédition
        final cmdObj = synth.project.businessObjects.firstWhere(
          (o) => o.technicalName == 'Commande',
        );
        expect(cmdObj.lifecycleStates.length, greaterThanOrEqualTo(3));

        // Promotion de la politique de l'étape 2 en RG-001
        final promoted = EventStormingOperations.promotePolicyToBusinessRule(
          synth.project,
          documentId: 'gestion-commandes',
          stepNumber: 2,
        );
        expect(promoted.createdNew, isTrue);
        expect(promoted.rule.code, 'RG-001');
        expect(promoted.rule.category, BusinessRuleCategory.trigger);
        expect(promoted.rule.title, "Déclencher l'encaissement");
        expect(promoted.rule.trigger, contains('EVT-01'));
      },
    );

    test(
      'SpecCoherenceAnalyzer, SpecMarkdownExporter (Mermaid) et get_event_storming fonctionnent sur DSL v1.0',
      () async {
        final refDoc = EventStormingDslCodec.fromYaml(
          _referenceGestionCommandesYaml,
          idHint: 'gestion-commandes',
        );
        final project = _buildSampleProject(
          eventStorming: EventStormingSpec(documents: [refDoc]),
        );

        final issues = SpecCoherenceAnalyzer.analyze(project);
        // HS-01 est ouvert -> COH-ES-002
        expect(issues.any((i) => i.code == 'COH-ES-002'), isTrue);
        // Aucune erreur DSL ou grammaire sur le fichier de référence !
        expect(issues.any((i) => i.code == 'COH-ES-003'), isFalse);
        expect(issues.any((i) => i.code == 'COH-ES-005'), isFalse);

        final md = SpecMarkdownExporter.export(project);
        expect(md, contains('gestion-commandes.es.yaml'));
        expect(md, contains('flowchart LR'));
        expect(md, contains('classDef externalSystem'));
        expect(md, contains('ET (all_of)'));
        expect(md, contains('OU (any_of)'));
        expect(md, contains('Autorisation bancaire accordée'));
        expect(md, contains('HS-01'));

        SpecForgeStage? navigated;
        String? focusedDoc;
        final registry = SpecForgeToolRegistry.build(
          readProject: () => project,
          onNavigateStage: (s) async => navigated = s,
          onFocusEventStormFlow: (id) => focusedDoc = id,
        );
        final res = await registry.execute(
          VibeToolCall(
            id: 'tc_es',
            name: 'get_event_storming',
            arguments: const {'onlyOpenHotspots': true, 'includeYaml': true},
          ),
        );
        expect(res.isError, isFalse);
        expect(res.data['documentCount'], 1);
        expect(res.data['openHotspotCount'], 1);
        final docsList = res.data['documents'] as List;
        expect((docsList.first as Map)['yaml'], contains('dsl_version: "1.0"'));

        final focusRes = await registry.execute(
          VibeToolCall(
            id: 'tc_focus_es',
            name: 'focus_stage_or_object',
            arguments: const {
              'stage': 'eventStorming',
              'eventStormFlowId': 'gestion-commandes',
            },
          ),
        );
        expect(focusRes.isError, isFalse);
        expect(navigated, SpecForgeStage.eventStorming);
        expect(focusedDoc, 'gestion-commandes');
      },
    );
  });

  group('Atelier UI & Stepper Event Storming DSL v1.0', () {
    testWidgets(
      'EventStormingEditorView : seed 1-clic, génération objets, tour IA DSL v1.0, onglet YAML et promotion RG',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1480, 920));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final store = _MemProjectStore()..seed(_buildSampleProject());
        final fakeAi = _FakeEventStormingAi();
        final controller = SpecForgeController(
          store: store,
          glossaryStore: _MemGlossaryStore(),
          modelDictionaryStore: _MemDictStore(),
          domainCatalogStore: _MemDomainStore(),
          enterpriseRateCardStore: _MemRateCardStore(),
          aiService: fakeAi,
          initialQuestioningLevel: VibeQuestioningLevel.none,
        );
        await controller.initialize();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Row(
                  children: [
                    SizedBox(
                      width: 460,
                      child: StageAiChatPane(controller: controller),
                    ),
                    Expanded(
                      child: EventStormingEditorView(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Amorçage 1-clic depuis le Cahier des charges
        await tester.tap(find.byKey(const ValueKey('spec-es-seed-btn')));
        await tester.pumpAndSettle();
        expect(controller.project!.eventStorming.documents, hasLength(1));

        // 2. Génération 1-clic des Objets métiers
        await tester.tap(
          find.byKey(const ValueKey('spec-es-generate-objects-btn')),
        );
        await tester.pumpAndSettle();
        expect(controller.project!.businessObjects, isNotEmpty);

        // 3. Tour IA Event Storming Facilitator (ajoute facturation.es.yaml avec politique)
        await tester.tap(find.byKey(const ValueKey('spec-stage-start-ai')));
        await tester.pumpAndSettle();
        expect(fakeAi.calledStages, [SpecForgeStage.eventStorming]);
        expect(
          controller.project!.eventStorming.findDocument('facturation'),
          isNotNull,
        );

        // 4. Sélection de facturation.es.yaml et promotion de la politique en RG-001
        await tester.tap(
          find.byKey(const ValueKey('spec-es-doc-tile-facturation')),
        );
        await tester.pumpAndSettle();
        final promoteBtn = find.byKey(
          const ValueKey('spec-es-promote-policy-facturation-1'),
        );
        await tester.ensureVisible(promoteBtn);
        await tester.pumpAndSettle();
        await tester.tap(promoteBtn);
        await tester.pumpAndSettle();
        expect(controller.project!.businessRules, hasLength(1));
        expect(controller.project!.businessRules.single.code, 'RG-001');

        // 5. Bascule sur l'onglet YAML (.es.yaml) et vérification de la sortie
        await tester.tap(find.textContaining('YAML (.es.yaml)'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('spec-es-yaml-preview')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'showEventStormStepDialog : aucun overflow RenderFlex avec de longs libellés catalogue',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final doc = EventStormDocument(
          id: 'long-labels',
          meta: const EventStormMeta(
            domain: 'E-Commerce',
            boundedContext: 'Gestion avancée',
            date: '2026-11-27',
          ),
          catalog: EventStormCatalog(
            actors: const [
              EventStormCatalogItem(
                id: 'ACT-ADMIN-SUPER',
                name: 'Administrateur plateforme e-commerce multi-boutiques',
                type: EventStormActorType.human,
              ),
            ],
            aggregates: const [
              EventStormCatalogItem(
                id: 'AGG-COMMANDE-CLIENT',
                name: 'CommandeClientAvecHistoriqueEtValidationComplexe',
              ),
            ],
            externalSystems: const [
              EventStormCatalogItem(
                id: 'EXT-PSP-INTERNAT',
                name: 'Passerelle de Paiement Internationale 3DSecure v2',
              ),
            ],
          ),
        );

        final initialStep = EventStormStep(
          step: 1,
          triggeredBy: EventStormTrigger.single('EVT-00'),
          actor: 'ACT-ADMIN-SUPER',
          command: EventStormCommand(name: 'Valider la commande'),
          aggregate: 'AGG-COMMANDE-CLIENT',
          externalSystem: 'EXT-PSP-INTERNAT',
          domainEvent: EventStormDomainEvent(
            id: 'EVT-01',
            name: 'Commande validée',
          ),
          hotspots: const [
            EventStormHotspot(
              id: 'HS-01',
              question: 'Vérifier le plafond ?',
              severity: EventStormHotspotSeverity.high,
              status: EventStormHotspotStatus.open,
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    key: const ValueKey('open-step-dialog'),
                    onPressed: () => showEventStormStepDialog(
                      context,
                      document: doc,
                      step: initialStep,
                    ),
                    child: const Text('Ouvrir'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('open-step-dialog')));
        await tester.pumpAndSettle();

        expect(find.text('Modifier Step 1'), findsOneWidget);
        expect(find.byKey(const ValueKey('spec-es-step-help-btn')), findsOneWidget);
      },
    );

    testWidgets(
      'EventStormingEditorView : le bouton Aide cartes ouvre le guide détaillant chaque type de carte',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 860));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final store = _MemProjectStore()..seed(_buildSampleProject());
        final controller = SpecForgeController(
          store: store,
          glossaryStore: _MemGlossaryStore(),
          modelDictionaryStore: _MemDictStore(),
          domainCatalogStore: _MemDomainStore(),
          enterpriseRateCardStore: _MemRateCardStore(),
          aiService: _FakeEventStormingAi(),
        );
        await controller.initialize();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EventStormingEditorView(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('spec-es-help-btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('spec-es-help-dialog')), findsOneWidget);
        expect(
          find.text('Guide des cartes Event Storming (DSL v1.0)'),
          findsOneWidget,
        );
        for (final badge in [
          'ACTEUR',
          'READ MODEL',
          'POLITIQUE',
          'COMMANDE',
          'AGRÉGAT',
          'SYSTÈME EXTERNE',
          'ÉVÉNEMENT',
          'OUTCOMES (OU)',
          'HOTSPOT',
        ]) {
          expect(find.text(badge), findsOneWidget);
        }

        await tester.tap(find.byKey(const ValueKey('spec-es-help-close-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('spec-es-help-dialog')), findsNothing);
      },
    );

    test(
      'SpecPromptBuilder & resolveEventStormExternalCandidates injectent et proposent les Systèmes & Services en Event Storming',
      () {
        final refDoc = EventStormingDslCodec.fromYaml(
          _referenceGestionCommandesYaml,
          idHint: 'gestion-commandes',
        );
        final project = _buildSampleProject(
          eventStorming: EventStormingSpec(documents: [refDoc]),
        );

        final domainCatalog = DomainCatalog(
          domains: const [
            FunctionalDomain(
              id: 'dom_cmd',
              domainCode: 'gestion-commandes',
              name: 'Gestion des commandes',
            ),
            FunctionalDomain(
              id: 'dom_billing',
              domainCode: 'billing',
              name: 'Facturation',
            ),
          ],
          microservices: const [
            // Déjà présent dans refDoc ("Stripe") -> ne doit pas être reproposé à l'import
            Microservice(
              id: 'svc_stripe',
              domainId: 'dom_cmd',
              serviceCode: 'stripe',
              name: 'Stripe',
              kind: DomainSystemKind.externalApp,
              vendor: 'Stripe',
            ),
            // Nouvelle application externe -> proposée en candidat direct EXT-*
            Microservice(
              id: 'svc_sendgrid',
              domainId: 'dom_cmd',
              serviceCode: 'sendgrid-mailer',
              name: 'SendGrid',
              kind: DomainSystemKind.externalApp,
              vendor: 'Twilio SendGrid',
              description: 'Envoi transactionnel d’emails',
            ),
            // Tool openSource -> proposé dans la section dédiée EXT-* et dans le prompt IA
            Microservice(
              id: 'svc_keycloak',
              domainId: 'dom_cmd',
              serviceCode: 'keycloak-iam',
              name: 'Keycloak',
              kind: DomainSystemKind.openSourceTool,
              vendor: 'Apache 2.0',
              description: 'Authentification OIDC open-source',
            ),
            // Front Web du domaine courant -> mentionné dans le prompt IA
            Microservice(
              id: 'svc_portal_web',
              domainId: 'dom_cmd',
              serviceCode: 'checkout-web',
              name: 'Portail Checkout Web',
              kind: DomainSystemKind.webFront,
            ),
            // Service interne du MÊME domaine -> pas proposé comme EXT-* de ce BC
            Microservice(
              id: 'svc_order_core',
              domainId: 'dom_cmd',
              serviceCode: 'order-service',
              name: 'Service Commandes',
              kind: DomainSystemKind.microservice,
            ),
            // Service d'un AUTRE domaine -> proposé en candidat EXT-* inter-domaines !
            Microservice(
              id: 'svc_billing_api',
              domainId: 'dom_billing',
              serviceCode: 'billing-api',
              name: 'Service Facturation',
              kind: DomainSystemKind.microservice,
            ),
          ],
        );

        final prompt = SpecPromptBuilder.buildTurnPrompt(
          project: project,
          stage: SpecForgeStage.eventStorming,
          userInput: 'Complète les systèmes externes',
          questioningLevel: VibeQuestioningLevel.none,
          afterAskUserReply: false,
          domainCatalog: domainCatalog,
          focusedEventStormFlowId: 'gestion-commandes',
        );
        expect(
          prompt,
          contains('CARTOGRAPHIE « SYSTÈMES & SERVICES » DU WORKSPACE'),
        );
        expect(prompt, contains('EXT-SENDGRID -> « SendGrid »'));
        expect(prompt, contains('EXT-KEYCLOAK -> « Keycloak » [Tools openSource]'));
        expect(prompt, contains('Portail Checkout Web'));
        expect(
          prompt,
          contains('[AUTRE DOMAINE -> candidat EXT-* inter-contexte : EXT-SERVICE_FACTURATION]'),
        );

        final candidates = resolveEventStormExternalCandidates(
          domainCatalog,
          refDoc,
        );
        expect(
          candidates.map((c) => c.service.serviceCode).toList(),
          ['sendgrid-mailer', 'keycloak-iam', 'billing-api'],
        );
        expect(candidates[0].isDirectExternalApp, isTrue);
        expect(candidates[1].isOpenSourceTool, isTrue);
        expect(candidates[2].isDirectExternalApp, isFalse);
        expect(candidates[2].isOpenSourceTool, isFalse);
      },
    );
  });
}
