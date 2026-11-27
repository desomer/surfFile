/// Tests unitaires du pont d'export `super_designer` ([SuperDesignerBackendBridge])
/// et du service d'assistance IA orienté domaine ([BackendEditorAiService],
/// [GeminiBackendEditorAiService], [BackendAiResponseParser]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';

import 'package:super_backend_editor/ai/backend_editor_ai_service.dart';
import 'package:super_backend_editor/models/backend_domain_project.dart';
import 'package:super_backend_editor/models/backend_overlay_config.dart';
import 'package:super_backend_editor/models/domain_design_spec.dart';
import 'package:super_backend_editor/services/bridge/super_designer_backend_bridge.dart';

/// Double de test implémentant [BackendEditorAiService] sans appel réseau.
class _MockBackendEditorAiService implements BackendEditorAiService {
  _MockBackendEditorAiService({required this.chunks});

  final List<String> chunks;
  int warmUpCalls = 0;
  BackendAiTaskKind? lastTaskKind;
  String? lastFocusedTargetId;
  String? lastUserMessage;

  @override
  Stream<GeminiStreamEvent> streamAssistantTurn({
    required BackendDomainProject project,
    required String userMessage,
    BackendAiTaskKind taskKind = BackendAiTaskKind.generalAssistant,
    String? focusedTargetId,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<Map<String, Object?>>? conversationContents,
  }) async* {
    lastTaskKind = taskKind;
    lastFocusedTargetId = focusedTargetId;
    lastUserMessage = userMessage;

    final buffer = StringBuffer();
    for (var i = 0; i < chunks.length; i++) {
      final delta = chunks[i];
      buffer.write(delta);
      yield GeminiStreamEvent(
        deltaText: delta,
        accumulatedText: buffer.toString(),
        isDone: i == chunks.length - 1,
        usedContextCache: true,
      );
    }
  }

  @override
  Future<void> warmUp({
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  }) async {
    warmUpCalls++;
  }
}

BackendDomainProject _buildSampleBillingProject() {
  final spec = DomainDesignSpec(
    domain: const ImportedDomainIdentity(
      id: 'dom_billing',
      domainCode: 'billing-core',
      name: 'Facturation & Encaissements',
      description: 'Gestion des factures clients et rapprochements.',
      techStack: ImportedTechStackSummary(
        id: 'stack_ts',
        code: 'ts-nestjs',
        name: 'TypeScript / NestJS',
      ),
    ),
    environments: const <ImportedEnvironmentSpec>[
      ImportedEnvironmentSpec(
        id: 'env_dev',
        domainId: 'dom_billing',
        environmentCode: 'local-dev',
        name: 'Développement Local',
      ),
    ],
    configurations: const <ImportedConfigurationSpec>[
      ImportedConfigurationSpec(
        id: 'cfg_currency',
        environmentId: 'env_dev',
        configKey: 'DEFAULT_CURRENCY',
        entryType: 'plainVariable',
        plainValue: 'EUR',
      ),
      ImportedConfigurationSpec(
        id: 'cfg_stripe',
        environmentId: 'env_dev',
        configKey: 'STRIPE_API_KEY',
        entryType: 'secret',
      ),
    ],
    valueObjects: <ImportedValueObjectSpec>[
      ImportedValueObjectSpec(
        id: 'vo_money',
        scope: 'shared',
        name: 'Montant Monétaire',
        technicalName: 'Money',
        kind: 'composite',
        description: 'Montant décimal positif accompagné de sa devise ISO.',
        specJson: const <String, Object?>{
          'fields': <Map<String, Object?>>[
            <String, Object?>{'name': 'amount', 'type': 'number'},
            <String, Object?>{'name': 'currency', 'type': 'string'},
          ],
        },
        examples: const <Map<String, Object?>>[
          <String, Object?>{'value': '120.50 EUR', 'isValid': true},
        ],
      ),
    ],
    contractEntries: <ImportedContractEntry>[
      ImportedContractEntry(
        entryId: 'mdl_invoice',
        name: 'Facture',
        technicalName: 'Invoice',
        groupName: 'models',
        dslType: 'model',
        title: 'Facture Client',
        objectSpecJson: const <String, Object?>{
          'description': 'Agrégat racine représentant une facture émise.',
          'aggregateRoot': true,
          'attributes': <Map<String, Object?>>[
            <String, Object?>{
              'technicalName': 'reference',
              'type': 'string',
              'required': true,
            },
            <String, Object?>{
              'technicalName': 'totalAmount',
              'type': 'number',
              'required': true,
            },
            <String, Object?>{
              'technicalName': 'status',
              'type': 'string',
              'required': true,
            },
            <String, Object?>{
              'technicalName': 'dueDate',
              'type': 'date',
              'required': false,
            },
          ],
        },
        jsonSchema: const <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'type': 'object',
          r'$defs': <String, Object?>{
            'CustomerRef': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'customerId': <String, Object?>{'type': 'string'},
              },
            },
          },
          'required': <String>['id', 'reference', 'totalAmount', 'status'],
          'properties': <String, Object?>{
            'id': <String, Object?>{'type': 'string'},
            'reference': <String, Object?>{
              'type': 'string',
              'minLength': 3,
              'default': 'INV-0001',
            },
            'totalAmount': <String, Object?>{
              'type': 'number',
              'minimum': 0,
              'default': 0,
            },
            'status': <String, Object?>{
              'type': 'string',
              'enum': <String>['draft', 'issued', 'paid'],
              'default': 'draft',
            },
            'dueDate': <String, Object?>{'type': 'string', 'format': 'date'},
            'customer': <String, Object?>{r'$ref': r'#/$defs/CustomerRef'},
          },
          'additionalProperties': false,
        },
        domainLayerJson: const <String, Object?>{
          'invariants': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'MontantPositif',
              'description': 'totalAmount doit toujours être >= 0.',
            },
          ],
          'stateChangingMethods': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'issueInvoice',
              'description': 'Passe la facture de draft à issued.',
            },
          ],
          'queryMethods': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'isOverdue',
              'description': 'Calcule si dueDate est dépassée.',
            },
          ],
          'policyServices': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'VatCalculationPolicy',
              'description': 'Applique le taux de TVA territorial.',
            },
          ],
          'factories': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'createDraft',
              'description': 'Initialise une facture brouillon.',
            },
          ],
          'domainEvents': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'InvoiceIssued',
              'description': 'Émis lors de la validation de la facture.',
            },
          ],
          'persistencePolicy': <String, Object?>{
            'repositoryPortName': 'InvoiceRepositoryPort',
            'concurrencyStrategy': 'optimisticVersion',
            'deletionStrategy': 'softDelete',
            'transactionalBoundary': 'Invoice',
          },
        },
      ),
      ImportedContractEntry(
        entryId: 'mdl_credit_line',
        name: 'Ligne d’Avoir Client Détaillée',
        technicalName: 'CustomerCreditNoteDetailedLineItem',
        groupName: 'models',
        dslType: 'model',
        title: 'Ligne d’Avoir Client Détaillée',
        jsonSchema: const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'id': <String, Object?>{'type': 'string'},
            'label': <String, Object?>{'type': 'string'},
            'amount': <String, Object?>{'type': 'number', 'minimum': 0},
          },
        },
      ),
    ],
    useCases: <ImportedUseCaseSpec>[
      ImportedUseCaseSpec(
        id: 'uc_issue_invoice',
        code: 'UC-001',
        name: 'IssueInvoice',
        title: 'Émettre une facture',
        cqrsType: 'command',
        targetAggregate: 'Invoice',
        businessGoal: 'Valider et émettre une facture brouillon.',
        businessRules: const <String>[
          'Seule une facture au statut draft peut être émise.',
        ],
        emittedEvents: const <String>['InvoiceIssued'],
        possibleErrors: const <String>['INVOICE_ALREADY_ISSUED'],
        scenarios: const <Map<String, Object?>>[
          <String, Object?>{
            'title': 'Émission nominale',
            'given':
                'Une facture INV-1001 en statut draft avec totalAmount > 0',
            'when': 'La commande IssueInvoice est exécutée',
            'then': 'Le statut passe à issued et InvoiceIssued est publié',
          },
        ],
        inputJsonSchema: const <String, Object?>{
          'type': 'object',
          'required': <String>['invoiceId'],
          'properties': <String, Object?>{
            'invoiceId': <String, Object?>{'type': 'string'},
            'issueDate': <String, Object?>{'type': 'string', 'format': 'date'},
          },
        },
        outputJsonSchema: const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'id': <String, Object?>{'type': 'string'},
            'status': <String, Object?>{'type': 'string'},
          },
        },
      ),
      ImportedUseCaseSpec(
        id: 'uc_list_overdue',
        code: 'UC-002',
        name: 'ListOverdueInvoices',
        title: 'Lister les factures échues',
        cqrsType: 'query',
        targetAggregate: 'Invoice',
        businessGoal:
            'Retourne les factures non payées dont l’échéance est passée.',
        inputJsonSchema: const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'asOfDate': <String, Object?>{'type': 'string', 'format': 'date'},
          },
        },
        outputJsonSchema: const <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'id': <String, Object?>{'type': 'string'},
              'reference': <String, Object?>{'type': 'string'},
            },
          },
        },
      ),
    ],
    sagas: <ImportedSagaSpec>[
      ImportedSagaSpec(
        id: 'saga_payment',
        code: 'SAGA-01',
        name: 'InvoicePaymentReconciliationSaga',
        title: 'Rapprochement de paiement Stripe',
        triggerEvent: 'InvoiceIssued',
        steps: const <Map<String, Object?>>[
          <String, Object?>{'step': 1, 'action': 'CreatePaymentIntent'},
        ],
      ),
    ],
  );

  final baseProject = BackendDomainProject.bootstrap(
    spec,
    localSecretValues: const <String, Map<String, String>>{
      'env_dev': <String, String>{
        'STRIPE_API_KEY': 'sk_test_TOP_SECRET_DO_NOT_LEAK_999',
      },
    },
  );

  // Ajoute aussi une commande CQRS avec paramètre de route `:invoiceId` pour
  // vérifier la conversion vers un gabarit `{{invoice_id}}` valide.
  final extraEndpoint = BackendEndpointConfig(
    id: 'ep_cmd_pay_invoice',
    kind: BackendEndpointKind.cqrsCommand,
    method: 'POST',
    path: '/api/commands/invoices/:invoiceId/pay',
    summary: 'Payer une facture par ID',
    useCaseId: 'uc_issue_invoice',
  );

  return baseProject.copyWith(
    overlay: baseProject.overlay.copyWith(
      endpoints: <BackendEndpointConfig>[
        ...baseProject.overlay.endpoints,
        extraEndpoint,
      ],
    ),
  );
}

void main() {
  group('SuperDesignerBackendBridge', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'super_backend_bridge_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('exportToDirectory (useLiveLocalHttpUrl: true) génère des providers, '
        'datasources et repositories 100% valides sur disque', () async {
      final project = _buildSampleBillingProject();
      final seedEntities = <String, List<Map<String, Object?>>>{
        'invoices': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'inv_001',
            'reference': 'INV-1001',
            'totalAmount': 1250.5,
            'status': 'issued',
            'dueDate': '2026-12-15',
          },
          <String, Object?>{
            'id': 'inv_002',
            'reference': 'INV-1002',
            'totalAmount': 480.0,
            'status': 'draft',
            'dueDate': '2026-12-31',
          },
        ],
      };

      final result = await SuperDesignerBackendBridge.exportToDirectory(
        targetDirectory: tempDir,
        project: project,
        options: const SuperDesignerBridgeOptions(
          useLiveLocalHttpUrl: true,
          includeScrudDatasources: true,
          includeCqrsProviders: true,
          includeRepositorySchemasAndSeeds: true,
        ),
        existingEntitiesByCollection: seedEntities,
      );

      expect(result.targetDirectoryPath, equals(tempDir.path));
      // 2 collections * 5 SCRUD = 10 providers + 3 endpoints CQRS = 13 providers.
      expect(result.providersJson.length, equals(13));
      expect(result.providerFilesWritten.length, equals(13));
      // 2 collections SCRUD = 2 datasources.
      expect(result.datasourcesJson.length, equals(2));
      expect(result.datasourceFilesWritten.length, equals(2));
      expect(result.repositoriesJson, isNotEmpty);
      expect(
        result.repositorySchemasJson.keys,
        equals(result.repositoriesJson.keys),
      );
      expect(
        result.repositoryFilesWritten.length,
        equals(result.repositoriesJson.length * 2),
      );

      // Chaque fichier providers/*.json sur disque doit passer HttpProviderConfig.fromJson.
      for (final filePath in result.providerFilesWritten) {
        final file = File(filePath);
        expect(await file.exists(), isTrue);
        final decoded = jsonDecode(await file.readAsString());
        final parsed = HttpProviderConfig.fromJson(decoded);
        expect(parsed.request.url, startsWith('http://127.0.0.1:8080/api/'));
      }

      // Chaque fichier datasources/*.json sur disque doit passer DatasourceConfig.fromJson.
      for (final filePath in result.datasourceFilesWritten) {
        final file = File(filePath);
        expect(await file.exists(), isTrue);
        final decoded = jsonDecode(await file.readAsString());
        final parsed = DatasourceConfig.fromJson(decoded);
        expect(parsed.operations.length, equals(5));
        for (final pid in parsed.providerIds) {
          expect(result.providersJson.containsKey(pid), isTrue);
        }
      }

      // Vérifie la structure exacte de invoices_repo, invoices_filter, invoices_form.
      expect(result.repositoriesJson.containsKey('invoices_repo'), isTrue);
      expect(result.repositoriesJson.containsKey('invoices_filter'), isTrue);
      expect(result.repositoriesJson.containsKey('invoices_form'), isTrue);

      final invoicesRepo = result.repositoriesJson['invoices_repo']!;
      expect(invoicesRepo['total'], equals(2));
      expect(invoicesRepo['loading'], isFalse);
      expect(invoicesRepo['error'], equals(''));
      expect(invoicesRepo['selectedItem'], equals(const <String, Object?>{}));
      expect((invoicesRepo['items'] as List).length, equals(2));

      // Vérifie chaque couple <id>.json + <id>.schema.json sur disque via JsonSchemaValidator.
      for (final repoId in result.repositoriesJson.keys) {
        final sep = Platform.pathSeparator;
        final dataFile = File(
          '${tempDir.path}${sep}repositories$sep$repoId.json',
        );
        final schemaFile = File(
          '${tempDir.path}${sep}repositories$sep$repoId.schema.json',
        );
        expect(await dataFile.exists(), isTrue);
        expect(await schemaFile.exists(), isTrue);

        final doc = jsonDecode(await dataFile.readAsString());
        final schema =
            jsonDecode(await schemaFile.readAsString()) as Map<String, Object?>;
        expect(
          () => JsonSchemaValidator.assertValid(
            repositoryId: repoId,
            document: doc,
            schema: schema,
          ),
          returnsNormally,
        );
      }

      // Vérifie les providers CQRS (command + query + paramètre de route).
      final issueCmd = HttpProviderConfig.fromJson(
        result.providersJson['ep_uc_uc_issue_invoice'],
      );
      expect(issueCmd.request.method, equals('POST'));
      expect(
        issueCmd.request.url,
        equals('http://127.0.0.1:8080/api/commands/issue-invoice'),
      );

      final overdueQuery = HttpProviderConfig.fromJson(
        result.providersJson['ep_uc_uc_list_overdue'],
      );
      expect(overdueQuery.request.method, equals('GET'));
      expect(
        overdueQuery.request.url,
        equals('http://127.0.0.1:8080/api/queries/list-overdue-invoices'),
      );

      final payWithParam = HttpProviderConfig.fromJson(
        result.providersJson['ep_cmd_pay_invoice'],
      );
      expect(
        payWithParam.request.url,
        equals(
          'http://127.0.0.1:8080/api/commands/invoices/{{invoice_id}}/pay',
        ),
      );
      expect(payWithParam.filterRepositoryId, isNotNull);
      expect(
        result.repositoriesJson[payWithParam.filterRepositoryId]!.containsKey(
          'invoice_id',
        ),
        isTrue,
      );
    });

    test('buildBundle (useLiveLocalHttpUrl: false) cible https://super.backend/api/... '
        'et respecte les options de filtrage', () {
      final project = _buildSampleBillingProject();
      final virtualBundle = SuperDesignerBackendBridge.buildBundle(
        project: project,
        options: const SuperDesignerBridgeOptions(
          useLiveLocalHttpUrl: false,
          includeScrudDatasources: true,
          includeCqrsProviders: true,
          includeRepositorySchemasAndSeeds: false,
        ),
      );

      expect(virtualBundle.providerFilesWritten, isEmpty);
      expect(virtualBundle.repositoriesJson, isEmpty);
      expect(virtualBundle.repositorySchemasJson, isEmpty);
      expect(virtualBundle.datasourcesJson.length, equals(2));
      expect(virtualBundle.providersJson.length, equals(13));

      for (final entry in virtualBundle.providersJson.entries) {
        final parsed = HttpProviderConfig.fromJson(entry.value);
        expect(parsed.request.url, startsWith('https://super.backend/api/'));
      }

      final searchProvider = HttpProviderConfig.fromJson(
        virtualBundle.providersJson['invoices_search'],
      );
      expect(
        SuperBackendDatasourceBridge.collectionFromUrl(
          searchProvider.request.url,
        ),
        equals('invoices'),
      );

      // Vérifie aussi que le nom kebab-case long de la 2e collection reste intact dans l'URL
      // tout en produisant un ID de datasource valide (<= 32 chars, snake_case).
      final secondDsId = virtualBundle.datasourcesJson.keys.firstWhere(
        (id) => id != 'invoices',
      );
      expect(isValidDatasourceId(secondDsId), isTrue);
      final secondSearch = HttpProviderConfig.fromJson(
        virtualBundle.providersJson['${secondDsId}_search'],
      );
      expect(
        SuperBackendDatasourceBridge.collectionFromUrl(
          secondSearch.request.url,
        ),
        equals('customer-credit-note-detailed-line-items'),
      );
    });
  });

  group('BackendEditorAiService & BackendAiResponseParser', () {
    test('buildDomainContextPrompt et buildStaticRuntimeGuide résument le domaine '
        '(7 onglets DDD, CQRS, API ctx) sans divulguer les secrets locaux', () {
      final project = _buildSampleBillingProject();
      final systemInstruction =
          GeminiBackendEditorAiService.buildSystemInstruction(
            BackendAiTaskKind.generateQuickJsHandler,
          );
      final runtimeGuide =
          GeminiBackendEditorAiService.buildStaticRuntimeGuide();
      final prompt = GeminiBackendEditorAiService.buildDomainContextPrompt(
        project: project,
        userMessage: 'Génère le handler QuickJS pour UC-001 IssueInvoice.',
        taskKind: BackendAiTaskKind.generateQuickJsHandler,
        focusedTargetId: 'ep_uc_uc_issue_invoice',
      );

      expect(systemInstruction, contains('DomainDesignSpec'));
      expect(systemInstruction, contains('ctx.env'));

      // Vérifie la présence complète du contrat QuickJS `ctx`.
      for (final apiSymbol in const <String>[
        'ctx.input',
        'ctx.params',
        'ctx.query',
        'ctx.env(',
        'ctx.collection(',
        '.search(',
        '.read(',
        '.create(',
        '.update(',
        '.delete(',
        'ctx.emit(',
        'ctx.assert(',
      ]) {
        expect(runtimeGuide, contains(apiSymbol));
      }

      // Vérifie la synthèse complète du domaine, des 7 onglets et des scénarios CQRS.
      expect(prompt, contains('billing-core'));
      expect(prompt, contains('Money'));
      expect(prompt, contains('[1. Invariants]'));
      expect(prompt, contains('MontantPositif'));
      expect(prompt, contains('[2. Commandes d’agrégat (State changing)]'));
      expect(prompt, contains('issueInvoice'));
      expect(prompt, contains('[3. Méthodes Query pures]'));
      expect(prompt, contains('[4. Policy Services]'));
      expect(prompt, contains('[5. Factories]'));
      expect(prompt, contains('[6. Domain Events]'));
      expect(prompt, contains('[7. Persistence Policy]'));
      expect(prompt, contains('UC-001'));
      expect(prompt, contains('Émission nominale'));
      expect(prompt, contains('Given ['));
      expect(prompt, contains('invoices'));
      expect(prompt, contains('STRIPE_API_KEY [SECRET via ctx.env]'));

      // SÉCURITÉ CRITIQUE : la valeur secrète locale ne doit jamais apparaître.
      expect(prompt, isNot(contains('sk_test_TOP_SECRET_DO_NOT_LEAK_999')));
    });

    test('BackendAiResponseParser.parse gère le JSON strict avec suggestions '
        'quickjs_script, seed_entities et endpoint_payload', () {
      final rawJson = jsonEncode(<String, Object?>{
        'reply':
            'Voici le handler QuickJS et un jeu de données pour `invoices`.',
        'suggestions': <Map<String, Object?>>[
          <String, Object?>{
            'kind': 'quickjs_script',
            'targetId': 'usecases/uc_issue_invoice.js',
            'title': 'Handler IssueInvoice',
            'codeOrJson':
                'const inv = ctx.collection("invoices").read(ctx.input.invoiceId);\n'
                'ctx.assert(inv && inv.status === "draft", "Facture non brouillon");\n'
                'const updated = ctx.collection("invoices").update(inv.id, { status: "issued" });\n'
                'ctx.emit("InvoiceIssued", { invoiceId: inv.id });\n'
                'return updated;',
          },
          <String, Object?>{
            'kind': 'seed_entities',
            'targetId': 'invoices',
            'title': 'Factures de démonstration',
            'entities': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'inv_10',
                'reference': 'INV-2010',
                'totalAmount': 990.0,
                'status': 'draft',
              },
            ],
          },
          <String, Object?>{
            'kind': 'endpoint_payload',
            'targetId': 'ep_uc_uc_issue_invoice',
            'title': 'Payload IssueInvoice',
            'codeOrJson': <String, Object?>{
              'invoiceId': 'inv_10',
              'issueDate': '2026-11-27',
            },
          },
        ],
      });

      final parsed = BackendAiResponseParser.parse(rawJson);
      expect(parsed.replyMarkdown, contains('Voici le handler QuickJS'));
      expect(parsed.suggestions.length, equals(3));

      final scriptSuggestion = parsed.suggestions[0];
      expect(scriptSuggestion.isQuickJsScript, isTrue);
      expect(scriptSuggestion.targetId, equals('usecases/uc_issue_invoice.js'));
      expect(scriptSuggestion.codeOrJson, contains('ctx.emit("InvoiceIssued"'));

      final seedSuggestion = parsed.suggestions[1];
      expect(seedSuggestion.isSeedEntities, isTrue);
      expect(seedSuggestion.targetId, equals('invoices'));
      expect(seedSuggestion.entities.length, equals(1));
      expect(seedSuggestion.entities.first['reference'], equals('INV-2010'));
      expect(seedSuggestion.codeOrJson, contains('INV-2010'));

      final payloadSuggestion = parsed.suggestions[2];
      expect(payloadSuggestion.isEndpointPayload, isTrue);
      expect(payloadSuggestion.codeOrJson, contains('"invoiceId": "inv_10"'));
    });

    test('BackendAiResponseParser.parse gère un bloc ```json clôturé et un texte libre sans planter', () {
      const fencedResponse = '''
Analyse terminée :

```json
{
  "reply": "Diagnostic : le champ `totalAmount` doit rester positif.",
  "suggestions": [
    {
      "kind": "quickjs_script",
      "targetId": "invariants/invoice_invariant.js",
      "title": "Invariant MontantPositif",
      "codeOrJson": "ctx.assert(ctx.input.totalAmount >= 0, 'Montant négatif interdit');"
    }
  ]
}
```
''';
      final fromFence = BackendAiResponseParser.parse(fencedResponse);
      expect(fromFence.replyMarkdown, contains('Diagnostic : le champ'));
      expect(fromFence.suggestions.length, equals(1));
      expect(
        fromFence.suggestions.single.targetId,
        equals('invariants/invoice_invariant.js'),
      );

      const plainMarkdown =
          'Tout est cohérent entre `DomainDesignSpec` et `BackendOverlayConfig`.';
      final fallback = BackendAiResponseParser.parse(plainMarkdown);
      expect(fallback.replyMarkdown, equals(plainMarkdown));
      expect(fallback.suggestions, isEmpty);

      final empty = BackendAiResponseParser.parse('   ');
      expect(empty.replyMarkdown, isEmpty);
      expect(empty.suggestions, isEmpty);
    });

    test('Flux SSE mocké de BackendEditorAiService émet les deltas et se décode proprement', () async {
      final project = _buildSampleBillingProject();
      final mockService = _MockBackendEditorAiService(
        chunks: <String>[
          '{"reply": "Script prêt.", ',
          '"suggestions": [{"kind": "quickjs_script", ',
          '"targetId": "usecases/uc_issue.js", ',
          '"title": "Handler", ',
          '"codeOrJson": "return { ok: true };"}]}',
        ],
      );

      await mockService.warmUp();
      expect(mockService.warmUpCalls, equals(1));

      final events = await mockService
          .streamAssistantTurn(
            project: project,
            userMessage: 'Crée le handler UC-001',
            taskKind: BackendAiTaskKind.generateQuickJsHandler,
            focusedTargetId: 'uc_issue_invoice',
          )
          .toList();

      expect(events.length, equals(5));
      expect(events.first.isDone, isFalse);
      expect(events.last.isDone, isTrue);
      expect(
        mockService.lastTaskKind,
        equals(BackendAiTaskKind.generateQuickJsHandler),
      );
      expect(mockService.lastFocusedTargetId, equals('uc_issue_invoice'));

      final turnResponse = BackendAiResponseParser.parse(
        events.last.accumulatedText,
      );
      expect(turnResponse.replyMarkdown, equals('Script prêt.'));
      expect(turnResponse.suggestions.length, equals(1));
      expect(turnResponse.suggestions.single.isQuickJsScript, isTrue);
    });
  });
}
