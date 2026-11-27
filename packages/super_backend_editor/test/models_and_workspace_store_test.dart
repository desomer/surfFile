import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_backend_editor/super_backend_editor.dart';

DomainDesignSpec _buildSampleDesignSpec() => DomainDesignSpec(
  exportedAt: DateTime.utc(2026, 11, 27, 18, 30),
  sourceKind: DesignSourceKind.snapshot,
  snapshotMeta: ImportedSnapshotMeta(
    id: 'snap_1',
    iterationNumber: 2,
    label: 'Itération 2 — Facturation',
    notes: 'Jalon de référence',
    createdAt: DateTime.utc(2026, 11, 27, 18, 0),
    techStackId: 'stack_ts_nestjs',
  ),
  domain: const ImportedDomainIdentity(
    id: 'dom_billing',
    domainCode: 'billing-core',
    name: 'Facturation & Encaissements',
    description: 'Gestion du cycle de facturation client.',
    techStackId: 'stack_ts_nestjs',
    techStack: ImportedTechStackSummary(
      id: 'stack_ts_nestjs',
      code: 'ts-nestjs',
      name: 'TypeScript / NestJS',
      description: 'Stack hexagonale Node.js.',
    ),
  ),
  environments: const <ImportedEnvironmentSpec>[
    ImportedEnvironmentSpec(
      id: 'env_dev',
      domainId: 'dom_billing',
      environmentCode: 'local-dev',
      name: 'Développement local',
      status: 'active',
    ),
    ImportedEnvironmentSpec(
      id: 'env_prod',
      domainId: 'dom_billing',
      environmentCode: 'prod',
      name: 'Production',
      status: 'archived',
    ),
  ],
  systems: const <ImportedSystemSpec>[
    ImportedSystemSpec(
      id: 'sys_billing_api',
      domainId: 'dom_billing',
      serviceCode: 'billing-api',
      name: 'Billing API',
      kind: 'microservice',
    ),
    ImportedSystemSpec(
      id: 'sys_stripe',
      domainId: 'dom_billing',
      serviceCode: 'stripe-gateway',
      name: 'Stripe',
      kind: 'externalApp',
      vendor: 'Stripe',
    ),
  ],
  configurations: const <ImportedConfigurationSpec>[
    ImportedConfigurationSpec(
      id: 'cfg_currency',
      domainId: 'dom_billing',
      environmentId: 'env_dev',
      configKey: 'DEFAULT_CURRENCY',
      entryType: 'plainVariable',
      plainValue: 'EUR',
    ),
    ImportedConfigurationSpec(
      id: 'cfg_stripe_secret',
      domainId: 'dom_billing',
      environmentId: 'env_dev',
      microserviceId: 'sys_stripe',
      configKey: 'STRIPE_API_SECRET',
      entryType: 'secret',
    ),
  ],
  valueObjects: <ImportedValueObjectSpec>[
    ImportedValueObjectSpec(
      id: 'vo_money',
      scope: 'shared',
      name: 'Montant monétaire',
      technicalName: 'Money',
      kind: 'composite',
      description: 'Montant décimal associé à une devise ISO-4217.',
      examples: const <Map<String, Object?>>[
        <String, Object?>{
          'id': 'ex_1',
          'value': '{"amount":120.5,"currency":"EUR"}',
          'isValid': true,
        },
      ],
      specJson: const <String, Object?>{
        'id': 'vo_money',
        'technicalName': 'Money',
        'name': 'Montant monétaire',
        'kind': 'composite',
        'version': '1.2.0',
        'fields': <Map<String, Object?>>[
          <String, Object?>{'id': 'f_amt', 'name': 'amount', 'type': 'number'},
          <String, Object?>{
            'id': 'f_cur',
            'name': 'currency',
            'type': 'string',
          },
        ],
      },
      jsonSchema: const <String, Object?>{
        'type': 'object',
        'required': <String>['amount', 'currency'],
      },
    ),
  ],
  dslSource: 'models:\n  Invoice: model\n  AuditEntry: model\ndto:\n  CreateInvoiceDto: createxdto\nmessage:\n  InvoiceIssuedEvent: eventxpayloaddto\ncomponents:\n  PostalAddress: component\n',
  contractEntries: <ImportedContractEntry>[
    ImportedContractEntry(
      entryId: 'node_invoice',
      name: 'Invoice',
      technicalName: 'Invoice',
      groupName: 'models',
      dslType: 'model',
      title: 'Facture client',
      version: '1.1.0',
      states: const <String, String>{'conception': 'done'},
      objectSpecJson: const <String, Object?>{
        'id': 'node_invoice',
        'name': 'Facture client',
        'technicalName': 'Invoice',
        'aggregateRoot': true,
        'attributes': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'a_num',
            'name': 'invoiceNumber',
            'type': 'string',
          },
        ],
        'relations': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'r_cust',
            'name': 'customerId',
            'targetObjectId': 'cust',
          },
        ],
      },
      jsonSchema: const <String, Object?>{'type': 'object', 'title': 'Invoice'},
      domainLayerJson: const <String, Object?>{
        'invariants': <Map<String, Object?>>[
          <String, Object?>{'id': 'inv_1', 'name': 'positiveTotal'},
        ],
        'stateChanges': <Map<String, Object?>>[
          <String, Object?>{'id': 'cmd_1', 'name': 'issueInvoice'},
        ],
        'queries': <Map<String, Object?>>[
          <String, Object?>{'id': 'qry_1', 'name': 'isOverdue'},
        ],
        'policyServices': <Map<String, Object?>>[
          <String, Object?>{'id': 'pol_1', 'name': 'VatCalculationPolicy'},
        ],
        'factories': <Map<String, Object?>>[
          <String, Object?>{'id': 'fac_1', 'name': 'createDraftInvoice'},
        ],
        'domainEvents': <Map<String, Object?>>[
          <String, Object?>{'id': 'evt_1', 'name': 'InvoiceIssued'},
        ],
        'persistencePolicy': <String, Object?>{
          'repositoryPortName': 'InvoiceRepository',
          'aggregateBoundary': 'Invoice + InvoiceLines',
          'concurrencyStrategy': 'optimisticVersion',
          'deletionStrategy': 'softDelete',
        },
      },
    ),
    ImportedContractEntry(
      entryId: 'node_category',
      name: 'TaxCategory',
      technicalName: 'TaxCategory',
      groupName: 'models',
      dslType: 'model',
      title: 'Catégorie fiscale',
      version: '1.0.0',
      domainLayerJson: const <String, Object?>{
        'persistencePolicy': <String, Object?>{
          'repositoryPortName': 'TaxCategoryRepository',
          'concurrencyStrategy': 'none',
          'deletionStrategy': 'immutableArchive',
        },
      },
    ),
    ImportedContractEntry(
      entryId: 'node_create_dto',
      name: 'CreateInvoiceDto',
      technicalName: 'CreateInvoiceDto',
      groupName: 'dto',
      dslType: 'createxdto',
      title: 'Création de facture',
      version: '1.0.0',
    ),
    ImportedContractEntry(
      entryId: 'node_issued_evt',
      name: 'InvoiceIssuedEvent',
      technicalName: 'InvoiceIssuedEvent',
      groupName: 'message',
      dslType: 'eventxpayloaddto',
      title: 'Événement facture émise',
      version: '1.0.0',
    ),
    ImportedContractEntry(
      entryId: 'node_address',
      name: 'PostalAddress',
      technicalName: 'PostalAddress',
      groupName: 'components',
      dslType: 'component',
      title: 'Adresse postale',
      version: '1.0.0',
    ),
  ],
  cartography: const <Map<String, Object?>>[
    <String, Object?>{
      'id': 'bc_1',
      'boundedContext': 'Billing',
      'useCaseCodes': <String>['UC-001', 'UC-002'],
    },
  ],
  useCases: <ImportedUseCaseSpec>[
    ImportedUseCaseSpec(
      id: 'uc_create_invoice',
      code: 'UC-001',
      name: 'CreateInvoice',
      title: 'Créer une facture brouillon',
      version: '1.0.0',
      boundedContext: 'Billing',
      cqrsType: 'command',
      targetAggregate: 'Invoice',
      businessGoal: 'Émettre un brouillon de facture validé.',
      inboundPort: 'CreateInvoiceUseCase',
      outboundPorts: const <String>['InvoiceRepository'],
      emittedEvents: const <String>['InvoiceCreated'],
      businessRules: const <String>['Montant HT >= 0'],
      detailedProcess: const <String>['Valider payload', 'Persister Invoice'],
      possibleErrors: const <String>['INVALID_AMOUNT'],
      scenarios: const <Map<String, Object?>>[
        <String, Object?>{'id': 'sc_1', 'title': 'Nominal'},
      ],
      inputJsonSchema: const <String, Object?>{'type': 'object'},
      outputJsonSchema: const <String, Object?>{'type': 'object'},
    ),
    ImportedUseCaseSpec(
      id: 'uc_list_invoices',
      code: 'UC-002',
      name: 'ListInvoices',
      title: 'Lister les factures',
      version: '1.0.0',
      boundedContext: 'Billing',
      cqrsType: 'query',
      targetAggregate: 'Invoice',
    ),
  ],
  sagas: <ImportedSagaSpec>[
    ImportedSagaSpec(
      id: 'saga_payment',
      code: 'SAGA-001',
      name: 'InvoiceCollectionSaga',
      title: 'Encaissement et rapprochement',
      version: '1.0.0',
      boundedContext: 'Billing, Payments',
      coordinationMode: 'orchestration',
      triggerEvent: 'InvoiceIssued',
      mermaidDiagram: 'sequenceDiagram\nBilling->>Stripe: Charge',
      compensations: const <Map<String, Object?>>[
        <String, Object?>{
          'id': 'comp_1',
          'step': '1. Débit carte',
          'compensationAction': 'Rembourser débit',
        },
      ],
    ),
  ],
);

Directory _createScratchWorkspaceDir(String suffix) {
  final sep = Platform.pathSeparator;
  final dir = Directory(
    '${Directory.current.path}$sep.dart_tool${sep}test_workspaces$sep${suffix}_${DateTime.now().microsecondsSinceEpoch}',
  );
  dir.createSync(recursive: true);
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

void main() {
  group('DomainDesignSpec & invariants de confidentialité', () {
    test(
      'sérialise et désérialise intégralement en JSON avec égalité profonde',
      () {
        final spec = _buildSampleDesignSpec();
        final encoded = jsonEncode(spec.toJson());
        final restored = DomainDesignSpec.fromJson(jsonDecode(encoded));

        expect(restored, equals(spec));
        expect(restored.hashCode, equals(spec.hashCode));
        expect(restored.models.map((m) => m.technicalName), <String>[
          'Invoice',
          'TaxCategory',
        ]);
        expect(restored.dtos.single.technicalName, 'CreateInvoiceDto');
        expect(restored.messages.single.technicalName, 'InvoiceIssuedEvent');
        expect(restored.components.single.technicalName, 'PostalAddress');
        expect(
          restored.findContractById('node_invoice')?.title,
          'Facture client',
        );
        expect(
          restored.findContractByTechnicalName('invoice')?.entryId,
          'node_invoice',
        );
        expect(
          restored.findUseCaseById('uc_create_invoice')?.isCommand,
          isTrue,
        );
        expect(restored.findSagaById('saga_payment')?.code, 'SAGA-001');
        expect(restored.findValueObjectByName('Money')?.isShared, isTrue);

        final invoice = restored.findContractById('node_invoice')!;
        expect(invoice.hasDomainLayer, isTrue);
        expect(invoice.attributes, hasLength(1));
        expect(invoice.relations, hasLength(1));
        expect(invoice.invariants, hasLength(1));
        expect(invoice.stateChangingMethods, hasLength(1));
        expect(invoice.queryMethods, hasLength(1));
        expect(invoice.policyServices, hasLength(1));
        expect(invoice.factories, hasLength(1));
        expect(invoice.domainEvents, hasLength(1));
        expect(
          invoice.persistencePolicy['repositoryPortName'],
          'InvoiceRepository',
        );
        expect(
          invoice.persistencePolicy['concurrencyStrategy'],
          'optimisticVersion',
        );
        expect(invoice.persistencePolicy['deletionStrategy'], 'softDelete');
        expect(
          invoice.persistencePolicy['transactionalBoundary'],
          'Invoice + InvoiceLines',
        );

        expect(
          () => restored.environments.add(restored.environments.first),
          throwsUnsupportedError,
        );
        expect(
          () => invoice.objectSpecJson['injected'] = true,
          throwsUnsupportedError,
        );
      },
    );

    test('parse également le format imbriqué exporté par super_spec_forge', () {
      final rawExporterBundle = <String, Object?>{
        'format': DomainDesignSpec.formatId,
        'version': 1,
        'exportedAt': '2026-11-27T12:00:00.000Z',
        'sourceKind': 'current',
        'domain': <String, Object?>{
          'id': 'dom_orders',
          'domainCode': 'orders',
          'name': 'Commandes',
        },
        'valueObjects': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'vo_email',
            'scope': 'shared',
            'spec': <String, Object?>{
              'id': 'vo_email',
              'technicalName': 'EmailAddress',
              'name': 'Email',
              'kind': 'scalar',
              'primitiveType': 'email',
              'description': 'Email validé',
              'examples': <String>['contact@acme.fr'],
            },
            'jsonSchema': <String, Object?>{
              'type': 'string',
              'format': 'email',
            },
          },
        ],
        'contracts': <String, Object?>{
          'dslSource': 'models:\n  Order: model\n',
          'entries': <Map<String, Object?>>[
            <String, Object?>{
              'entryId': 'node_order',
              'name': 'Order',
              'technicalName': 'Order',
              'groupName': 'models',
              'dslType': 'model',
              'title': 'Commande',
              'version': '1.0.0',
              'objectSpec': <String, Object?>{'technicalName': 'Order'},
              'jsonSchema': <String, Object?>{'type': 'object'},
              'domainLayer': <String, Object?>{},
            },
          ],
        },
        'useCaseOrchestration': <String, Object?>{
          'cartography': const <Object?>[],
          'useCases': <Map<String, Object?>>[
            <String, Object?>{
              'spec': <String, Object?>{
                'id': 'uc_place_order',
                'code': 'UC-010',
                'name': 'PlaceOrder',
                'title': 'Passer commande',
                'version': '1.0.0',
                'cqrsType': 'command',
              },
              'inputJsonSchema': <String, Object?>{'type': 'object'},
              'outputJsonSchema': <String, Object?>{'type': 'object'},
            },
          ],
          'sagas': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'saga_ship',
              'code': 'SAGA-010',
              'name': 'OrderShippingSaga',
              'title': 'Expédition',
              'version': '1.0.0',
              'boundedContexts': <String>['Orders', 'Logistics'],
              'coordinationMode': 'choreography',
              'triggerEventOrCommand': 'OrderPlaced',
              'compensationMatrix': const <Object?>[],
            },
          ],
        },
      };

      final parsed = DomainDesignSpec.fromJson(rawExporterBundle);
      expect(parsed.dslSource, contains('Order: model'));
      expect(parsed.models.single.technicalName, 'Order');
      expect(parsed.valueObjects.single.primitiveType, 'email');
      expect(
        parsed.valueObjects.single.examples.single['value'],
        'contact@acme.fr',
      );
      expect(parsed.useCases.single.name, 'PlaceOrder');
      expect(parsed.sagas.single.boundedContext, 'Orders, Logistics');
      expect(parsed.sagas.single.triggerEvent, 'OrderPlaced');
    });

    test(
      'purge systématiquement plainValue et encryptedValue sur les secrets',
      () {
        final parsedSecret = ImportedConfigurationSpec.fromJson(
          <String, Object?>{
            'id': 'cfg_sec',
            'domainId': 'dom_billing',
            'environmentId': 'env_dev',
            'configKey': 'WEBHOOK_SIGNING_SECRET',
            'entryType': 'secret',
            'plainValue': 'should_be_dropped',
            'encryptedValue': 'aes256:ciphertext_never_kept',
          },
        );

        expect(parsedSecret.isSecret, isTrue);
        expect(parsedSecret.plainValue, isNull);
        final serialized = parsedSecret.toJson();
        expect(serialized.containsKey('plainValue'), isFalse);
        expect(serialized.containsKey('encryptedValue'), isFalse);

        const illegalSecret = ImportedConfigurationSpec(
          id: 'cfg_bad',
          environmentId: 'env_dev',
          configKey: 'JWT_SECRET',
          entryType: 'secret',
          plainValue: 'cleartext_forbidden',
        );
        expect(illegalSecret.validate, throwsFormatException);
      },
    );
  });

  group('BackendOverlayConfig.bootstrapFromDesign & modèles associés', () {
    test('dérive les collections (softDelete, concurrence) et les routes SCRUD / CQRS', () {
      final spec = _buildSampleDesignSpec();
      final overlay = BackendOverlayConfig.bootstrapFromDesign(
        spec,
        updatedAt: DateTime.utc(2026, 11, 27, 19, 0),
      );

      expect(overlay.domainCode, 'billing-core');
      expect(overlay.activeEnvironmentId, 'env_dev');
      expect(overlay.collections, hasLength(2));

      final invoicesCol = overlay.findCollectionForContract('node_invoice')!;
      expect(invoicesCol.collectionName, 'invoices');
      expect(invoicesCol.deletionMode, BackendDeletionMode.softDelete);
      expect(
        invoicesCol.concurrencyMode,
        BackendConcurrencyMode.optimisticVersion,
      );

      final taxCatCol = overlay.findCollectionForContract('node_category')!;
      expect(taxCatCol.collectionName, 'tax-categories');
      expect(taxCatCol.deletionMode, BackendDeletionMode.immutableArchive);
      expect(taxCatCol.concurrencyMode, BackendConcurrencyMode.none);

      final scrudInvoiceEp = overlay.endpoints.firstWhere(
        (e) =>
            e.kind == BackendEndpointKind.scrudCollection &&
            e.collectionId == 'node_invoice',
      );
      expect(scrudInvoiceEp.method, 'GET');
      expect(scrudInvoiceEp.path, '/api/invoices');

      final createCmdEp = overlay.endpoints.firstWhere(
        (e) => e.useCaseId == 'uc_create_invoice',
      );
      expect(createCmdEp.kind, BackendEndpointKind.cqrsCommand);
      expect(createCmdEp.method, 'POST');
      expect(createCmdEp.path, '/api/commands/create-invoice');
      expect(createCmdEp.collectionId, 'node_invoice');

      final listQueryEp = overlay.endpoints.firstWhere(
        (e) => e.useCaseId == 'uc_list_invoices',
      );
      expect(listQueryEp.kind, BackendEndpointKind.cqrsQuery);
      expect(listQueryEp.method, 'GET');
      expect(listQueryEp.path, '/api/queries/list-invoices');

      final roundTrip = BackendOverlayConfig.fromJson(
        jsonDecode(jsonEncode(overlay.toJson())),
      );
      expect(roundTrip, equals(overlay));
      expect(roundTrip.hashCode, equals(overlay.hashCode));
    });

    test('sérialise DomainDesignDiff, BackendCoherenceIssue et BackendDomainProject', () {
      final diff = DomainDesignDiff(
        domainCode: 'billing-core',
        computedAt: DateTime.utc(2026, 11, 27, 20, 0),
        entries: <DesignDiffEntry>[
          DesignDiffEntry(
            category: DesignDiffItemCategory.contract,
            changeKind: DesignDiffChangeKind.added,
            itemId: 'node_credit_note',
            itemName: 'CreditNote',
            nextVersion: '1.0.0',
            details: const <String>['Nouveau modèle persistant'],
          ),
          DesignDiffEntry(
            category: DesignDiffItemCategory.useCase,
            changeKind: DesignDiffChangeKind.modified,
            itemId: 'uc_create_invoice',
            itemName: 'CreateInvoice',
            previousVersion: '1.0.0',
            nextVersion: '1.1.0',
          ),
          DesignDiffEntry(
            category: DesignDiffItemCategory.saga,
            changeKind: DesignDiffChangeKind.unchanged,
            itemId: 'saga_payment',
            itemName: 'InvoiceCollectionSaga',
          ),
        ],
      );

      expect(diff.hasChanges, isTrue);
      expect(diff.addedCount, 1);
      expect(diff.modifiedCount, 1);
      expect(diff.removedCount, 0);
      expect(diff.unchangedCount, 1);
      expect(
        diff.entriesForCategory(DesignDiffItemCategory.contract),
        hasLength(1),
      );
      expect(DomainDesignDiff.fromJson(diff.toJson()), equals(diff));

      const issue = BackendCoherenceIssue(
        id: 'iss_1',
        severity: BackendIssueSeverity.warning,
        category: BackendIssueCategory.environmentSecret,
        title: 'Secret non renseigné',
        message: 'STRIPE_API_SECRET n’a pas de valeur locale de test.',
        targetId: 'cfg_stripe_secret',
        suggestion: 'Renseigner une clé de test Stripe dans .local.',
      );
      expect(issue.isWarning, isTrue);
      expect(BackendCoherenceIssue.fromJson(issue.toJson()), equals(issue));

      final spec = _buildSampleDesignSpec();
      final overlay = BackendOverlayConfig.bootstrapFromDesign(spec).copyWith(
        environmentVariableOverrides: const <String, Map<String, String>>{
          'env_dev': <String, String>{'DEFAULT_CURRENCY': 'CHF'},
        },
      );
      final project = BackendDomainProject(
        designSpec: spec,
        overlay: overlay,
        importHistory: <DomainImportHistoryRecord>[
          DomainImportHistoryRecord(
            id: 'imp_1',
            importedAt: DateTime.utc(2026, 11, 27, 19, 30),
            sourceKind: DesignSourceKind.snapshot,
            sourceLabel: 'billing-core.iter-2.domain-design.json',
            snapshotIteration: 2,
            addedCount: 5,
          ),
        ],
        localSecretValues: const <String, Map<String, String>>{
          'env_dev': <String, String>{'STRIPE_API_SECRET': 'sk_test_local_123'},
        },
      );

      expect(
        project.resolveEnvironmentVariables('env_dev'),
        equals(const <String, String>{
          'DEFAULT_CURRENCY': 'CHF',
          'STRIPE_API_SECRET': 'sk_test_local_123',
        }),
      );
      expect(
        project
            .toJson(includeLocalSecrets: false)
            .containsKey('localSecretValues'),
        isFalse,
      );
      expect(BackendDomainProject.fromJson(project.toJson()), equals(project));
    });
  });

  group('BackendWorkspaceStore — persistance atomique sur disque', () {
    test(
      'persiste projets, scripts QuickJS, chat IA et secrets .local séparément',
      () async {
        final rootDir = _createScratchWorkspaceDir('store_roundtrip');
        final store = BackendWorkspaceStore(rootDir);

        expect((await store.loadWorkspaceIndex()).domains, isEmpty);

        final spec = _buildSampleDesignSpec();
        final project = BackendDomainProject(
          designSpec: spec,
          overlay: BackendOverlayConfig.bootstrapFromDesign(
            spec,
            updatedAt: DateTime.utc(2026, 11, 27, 20, 15),
          ),
          importHistory: <DomainImportHistoryRecord>[
            DomainImportHistoryRecord(
              id: 'hist_initial',
              importedAt: DateTime.utc(2026, 11, 27, 20, 15),
              sourceKind: DesignSourceKind.snapshot,
              sourceLabel: 'billing-core.iter-2.domain-design.json',
              snapshotIteration: 2,
              addedCount: 5,
            ),
          ],
          localSecretValues: const <String, Map<String, String>>{
            'env_dev': <String, String>{'STRIPE_API_SECRET': 'sk_test_999'},
          },
        );

        await store.saveProject(project);

        expect(await store.gitignoreFile.exists(), isTrue);
        expect(await store.gitignoreFile.readAsString(), contains('.local/'));

        final index = await store.loadWorkspaceIndex();
        expect(index.activeDomainCode, 'billing-core');
        expect(index.domains, hasLength(1));
        expect(index.domains.single.modelsCount, 2);
        expect(index.domains.single.useCasesCount, 2);
        expect(index.domains.single.collectionsCount, 2);

        // Vérifie l'étanchéité : aucun secret local dans le dossier domains/<domainCode>/
        final domainDir = store.domainDirectoryFor('billing-core');
        await for (final entity in domainDir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.json')) {
            expect(await entity.readAsString(), isNot(contains('sk_test_999')));
          }
        }

        // Vérifie la présence dans .local/secrets_billing-core.json
        final loadedSecrets = await store.loadLocalSecrets('billing-core');
        expect(loadedSecrets['env_dev']?['STRIPE_API_SECRET'], 'sk_test_999');

        final reloaded = await store.loadProject('billing-core');
        expect(reloaded, isNotNull);
        expect(reloaded, equals(project));

        // Scripts QuickJS + protection contre traversée de chemin
        await Future.wait(<Future<void>>[
          store.writeScript(
            'billing-core',
            'invariants/node_invoice.js',
            'export function validate(entity) {\r\n  return entity.total >= 0;\r\n}',
          ),
          store.writeScript(
            'billing-core',
            'usecases/uc_create_invoice.js',
            'export async function handle(ctx) { return { ok: true }; }',
          ),
        ]);

        final scripts = await store.listScripts('billing-core');
        expect(scripts, <String>[
          'invariants/node_invoice.js',
          'usecases/uc_create_invoice.js',
        ]);
        final invSource = await store.readScript(
          'billing-core',
          'invariants/node_invoice.js',
        );
        expect(invSource, isNotNull);
        expect(invSource!.contains('\r'), isFalse);

        expect(
          () => store.writeScript('billing-core', '../escape.js', 'bad'),
          throwsFormatException,
        );

        expect(
          await store.deleteScript(
            'billing-core',
            'invariants/node_invoice.js',
          ),
          isTrue,
        );
        expect(await store.listScripts('billing-core'), <String>[
          'usecases/uc_create_invoice.js',
        ]);

        // Chat assistant IA & chemin SQLite
        await store.saveAssistantChat(
          'billing-core',
          const <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'Génère 5 factures'},
          ],
        );
        final chat = await store.loadAssistantChat('billing-core');
        expect(chat.single['content'], 'Génère 5 factures');

        final sqliteFile = store.sqliteFileFor('billing-core');
        expect(sqliteFile.path, endsWith('backend.sqlite'));
        expect(await sqliteFile.parent.exists(), isTrue);

        // Aucun fichier temporaire résiduel
        final leftovers = <String>[];
        await for (final entity in rootDir.list(recursive: true)) {
          if (entity.path.contains('.tmp.')) leftovers.add(entity.path);
        }
        expect(leftovers, isEmpty);

        // Changement de domaine actif et suppression complète
        await store.setActiveDomainCode(null);
        expect((await store.loadWorkspaceIndex()).activeDomainCode, isNull);

        expect(await store.deleteProject('billing-core'), isTrue);
        expect(await store.loadProject('billing-core'), isNull);
        expect(await store.loadLocalSecrets('billing-core'), isEmpty);
        expect(await store.listDomainSummaries(), isEmpty);
      },
    );
  });
}
