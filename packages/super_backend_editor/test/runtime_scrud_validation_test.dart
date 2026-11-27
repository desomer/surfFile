/// Tests unitaires et d'intégration SQLite de [JsonSchemaPayloadValidator] et
/// [ProvisionedBackendService] (`runtime-scrud-validation`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:super_backend/super_backend.dart';
import 'package:super_backend_editor/models/backend_overlay_config.dart';
import 'package:super_backend_editor/models/domain_design_spec.dart';
import 'package:super_backend_editor/services/runtime/provisioned_backend_service.dart';
import 'package:super_backend_editor/services/validation/json_schema_payload_validator.dart';

Map<String, Object?> _buildInvoiceSchema() => const <String, Object?>{
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'additionalProperties': false,
  'required': <String>[
    'invoiceNumber',
    'customerEmail',
    'customerId',
    'issueDate',
    'status',
    'total',
    'lines',
  ],
  'properties': <String, Object?>{
    'invoiceNumber': <String, Object?>{
      'type': 'string',
      'pattern': r'^INV-[0-9]{4}$',
    },
    'customerEmail': <String, Object?>{'type': 'string', 'format': 'email'},
    'customerId': <String, Object?>{'type': 'string', 'format': 'uuid'},
    'issueDate': <String, Object?>{'type': 'string', 'format': 'date'},
    'issuedAt': <String, Object?>{'type': 'string', 'format': 'date-time'},
    'paymentUrl': <String, Object?>{
      'type': <String>['string', 'null'],
      'format': 'uri',
    },
    'status': <String, Object?>{
      'type': 'string',
      'enum': <String>['draft', 'issued', 'paid', 'cancelled'],
    },
    'notes': <String, Object?>{
      'type': 'string',
      'minLength': 3,
      'maxLength': 120,
    },
    'total': <String, Object?>{r'$ref': r'#/$defs/Money'},
    'lines': <String, Object?>{
      'type': 'array',
      'minItems': 1,
      'maxItems': 10,
      'uniqueItems': true,
      'items': <String, Object?>{r'$ref': r'#/$defs/InvoiceLine'},
    },
  },
  r'$defs': <String, Object?>{
    'Money': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['amount', 'currency'],
      'properties': <String, Object?>{
        'amount': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 100000,
          'multipleOf': 0.5,
        },
        'currency': <String, Object?>{
          'type': 'string',
          'enum': <String>['EUR', 'USD', 'GBP'],
        },
      },
    },
    'InvoiceLine': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['sku', 'qty', 'unitPrice'],
      'properties': <String, Object?>{
        'sku': <String, Object?>{
          'type': 'string',
          'minLength': 2,
          'maxLength': 32,
        },
        'qty': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 500,
        },
        'unitPrice': <String, Object?>{'type': 'number', 'exclusiveMinimum': 0},
      },
    },
  },
};

Map<String, Object?> _validInvoicePayload({
  String invoiceNumber = 'INV-0001',
  double totalAmount = 120.5,
}) => <String, Object?>{
  'invoiceNumber': invoiceNumber,
  'customerEmail': 'alice@client.fr',
  'customerId': '550e8400-e29b-41d4-a716-446655440000',
  'issueDate': '2026-11-27',
  'issuedAt': '2026-11-27T10:30:00Z',
  'paymentUrl': 'https://pay.exemple.fr/inv/0001',
  'status': 'draft',
  'notes': 'Facture mensuelle abonnement',
  'total': <String, Object?>{'amount': totalAmount, 'currency': 'EUR'},
  'lines': <Map<String, Object?>>[
    <String, Object?>{'sku': 'LIC-PRO', 'qty': 2, 'unitPrice': 60.25},
  ],
};

DomainDesignSpec _buildTestDesignSpec() => DomainDesignSpec(
  exportedAt: DateTime.utc(2026, 11, 27, 20, 0),
  domain: const ImportedDomainIdentity(
    id: 'dom_billing',
    domainCode: 'billing-core',
    name: 'Facturation',
  ),
  valueObjects: <ImportedValueObjectSpec>[
    ImportedValueObjectSpec(
      id: 'vo_money',
      scope: 'shared',
      name: 'Montant monétaire',
      technicalName: 'Money',
      kind: 'composite',
      examples: const <Map<String, Object?>>[
        <String, Object?>{
          'id': 'ex_ok_1',
          'value': '{"amount":150.0,"currency":"EUR"}',
          'isValid': true,
        },
        <String, Object?>{
          'id': 'ex_ko_1',
          'value': '{"amount":-10,"currency":"ZZZ"}',
          'isValid': false,
        },
      ],
      specJson: const <String, Object?>{
        'id': 'vo_money',
        'technicalName': 'Money',
        'name': 'Montant monétaire',
        'kind': 'composite',
        'fields': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'f_amt',
            'name': 'amount',
            'type': 'number',
            'required': true,
            'schemaConstraints': <String, Object?>{'minimum': 0},
          },
          <String, Object?>{
            'id': 'f_cur',
            'name': 'currency',
            'type': 'enum',
            'required': true,
            'enumValues': <String>['EUR', 'USD', 'GBP'],
          },
        ],
      },
      jsonSchema: const <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['amount', 'currency'],
        'properties': <String, Object?>{
          'amount': <String, Object?>{'type': 'number', 'minimum': 0},
          'currency': <String, Object?>{
            'type': 'string',
            'enum': <String>['EUR', 'USD', 'GBP'],
          },
        },
      },
    ),
    ImportedValueObjectSpec(
      id: 'vo_vat_rate',
      scope: 'domain',
      name: 'Taux de TVA',
      technicalName: 'VatRate',
      kind: 'scalar',
      primitiveType: 'number',
      specJson: const <String, Object?>{
        'id': 'vo_vat_rate',
        'technicalName': 'VatRate',
        'name': 'Taux de TVA',
        'kind': 'scalar',
        'primitiveType': 'number',
        'schemaConstraints': <String, Object?>{
          'minimum': 0,
          'maximum': 100,
          'multipleOf': 0.5,
        },
      },
      // jsonSchema volontairement vide pour tester le repli sur specJson.
      jsonSchema: const <String, Object?>{},
    ),
    ImportedValueObjectSpec(
      id: 'vo_postal_address',
      scope: 'shared',
      name: 'Adresse postale',
      technicalName: 'PostalAddress',
      kind: 'composite',
      specJson: const <String, Object?>{
        'id': 'vo_postal_address',
        'technicalName': 'PostalAddress',
        'name': 'Adresse postale',
        'kind': 'composite',
        'fields': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'f_city',
            'name': 'city',
            'type': 'string',
            'required': true,
            'schemaConstraints': <String, Object?>{'minLength': 2},
          },
          <String, Object?>{
            'id': 'f_zip',
            'name': 'zipCode',
            'type': 'string',
            'required': true,
            'schemaConstraints': <String, Object?>{'pattern': r'^[0-9]{5}$'},
          },
        ],
      },
      jsonSchema: const <String, Object?>{},
    ),
  ],
  contractEntries: <ImportedContractEntry>[
    ImportedContractEntry(
      entryId: 'model_invoice',
      name: 'Invoice',
      technicalName: 'Invoice',
      groupName: 'models',
      dslType: 'model',
      title: 'Facture client',
      objectSpecJson: const <String, Object?>{
        'id': 'model_invoice',
        'technicalName': 'Invoice',
        'attributes': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'a_num',
            'name': 'invoiceNumber',
            'type': 'string',
            'required': true,
          },
          <String, Object?>{
            'id': 'a_total',
            'name': 'total',
            'type': 'vo',
            'valueObjectId': 'Money',
            'required': true,
          },
        ],
      },
      jsonSchema: _buildInvoiceSchema(),
      domainLayerJson: const <String, Object?>{
        'persistencePolicy': <String, Object?>{
          'repositoryPortName': 'InvoiceRepository',
          'concurrencyStrategy': 'optimisticVersion',
          'deletionStrategy': 'softDelete',
        },
      },
    ),
    ImportedContractEntry(
      entryId: 'model_audit_log',
      name: 'AuditLog',
      technicalName: 'AuditLog',
      groupName: 'models',
      dslType: 'model',
      title: 'Journal d’audit',
      jsonSchema: const <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['action', 'actorEmail'],
        'properties': <String, Object?>{
          'action': <String, Object?>{'type': 'string', 'minLength': 2},
          'actorEmail': <String, Object?>{'type': 'string', 'format': 'email'},
        },
      },
      domainLayerJson: const <String, Object?>{
        'persistencePolicy': <String, Object?>{
          'repositoryPortName': 'AuditLogRepository',
          'concurrencyStrategy': 'none',
          'deletionStrategy': 'immutableArchive',
        },
      },
    ),
  ],
);

void main() {
  group('JsonSchemaPayloadValidator (Draft 2020-12)', () {
    const validator = JsonSchemaPayloadValidator();
    final invoiceSchema = _buildInvoiceSchema();

    test(r'valide une charge utile complète conforme avec $defs/$ref', () {
      final result = validator.validate(_validInvoicePayload(), invoiceSchema);
      expect(result.isValid, isTrue);
      expect(result.violations, isEmpty);
    });

    test('détecte les champs required manquants à la racine et dans un tableau imbriqué', () {
      final badPayload = <String, Object?>{
        'invoiceNumber': 'INV-0002',
        'customerId': '550e8400-e29b-41d4-a716-446655440000',
        'issueDate': '2026-11-27',
        'status': 'draft',
        'total': <String, Object?>{'amount': 10.0, 'currency': 'EUR'},
        'lines': <Map<String, Object?>>[
          <String, Object?>{'sku': 'ITEM-1', 'unitPrice': 10.0},
        ],
      };

      final result = validator.validate(badPayload, invoiceSchema);
      expect(result.isValid, isFalse);
      expect(
        result.violations.any(
          (v) => v.path == r'$.customerEmail' && v.rule == 'required',
        ),
        isTrue,
      );
      expect(
        result.violations.any(
          (v) => v.path == r'$.lines[0].qty' && v.rule == 'required',
        ),
        isTrue,
      );

      final errorPayload = result.toErrorPayload();
      expect(errorPayload['code'], 'validation_failed');
      expect(errorPayload['violations'], isA<List<Map<String, Object?>>>());
    });

    test(
      'valide types, bornes numériques, pattern, enum, format et uniqueItems',
      () {
        final badPayload = <String, Object?>{
          'invoiceNumber': 'BAD-12',
          'customerEmail': 'pas-un-email',
          'customerId': 'not-a-uuid',
          'issueDate': '2026-02-30',
          'issuedAt': '2026-13-01T99:00:00',
          'paymentUrl': 'not a uri',
          'status': 'archived',
          'notes': 'ab',
          'total': <String, Object?>{'amount': -5.3, 'currency': 'JPY'},
          'lines': <Map<String, Object?>>[
            <String, Object?>{'sku': 'DUP', 'qty': 0, 'unitPrice': 0},
            <String, Object?>{'sku': 'DUP', 'qty': 0, 'unitPrice': 0},
          ],
        };

        final result = validator.validate(badPayload, invoiceSchema);
        expect(result.isValid, isFalse);

        final rulesByPath = <String, Set<String>>{};
        for (final v in result.violations) {
          rulesByPath.putIfAbsent(v.path, () => <String>{}).add(v.rule);
        }

        expect(rulesByPath[r'$.invoiceNumber'], contains('pattern'));
        expect(rulesByPath[r'$.customerEmail'], contains('format'));
        expect(rulesByPath[r'$.customerId'], contains('format'));
        expect(rulesByPath[r'$.issueDate'], contains('format'));
        expect(rulesByPath[r'$.issuedAt'], contains('format'));
        expect(rulesByPath[r'$.paymentUrl'], contains('format'));
        expect(rulesByPath[r'$.status'], contains('enum'));
        expect(rulesByPath[r'$.notes'], contains('minLength'));
        expect(
          rulesByPath[r'$.total.amount'],
          containsAll(<String>['minimum', 'multipleOf']),
        );
        expect(rulesByPath[r'$.total.currency'], contains('enum'));
        expect(rulesByPath[r'$.lines'], contains('uniqueItems'));
        expect(rulesByPath[r'$.lines[0].qty'], contains('minimum'));
        expect(
          rulesByPath[r'$.lines[0].unitPrice'],
          contains('exclusiveMinimum'),
        );
      },
    );

    test(
      'gère additionalProperties: false avec allowSystemFields: true vs false',
      () {
        final withSystemFields = <String, Object?>{
          ..._validInvoicePayload(),
          'id': 'inv_01',
          'version': 3,
          'deletedAt': null,
          'createdAt': '2026-11-27T10:00:00Z',
          'updatedAt': '2026-11-27T11:00:00Z',
        };

        final strictRes = validator.validate(
          withSystemFields,
          invoiceSchema,
          allowSystemFields: false,
        );
        expect(strictRes.isValid, isFalse);
        expect(
          strictRes.violations.every((v) => v.rule == 'additionalProperties'),
          isTrue,
        );

        final allowedRes = validator.validate(
          withSystemFields,
          invoiceSchema,
          allowSystemFields: true,
        );
        expect(allowedRes.isValid, isTrue);

        final withIntruder = <String, Object?>{
          ...withSystemFields,
          'unexpectedField': 42,
        };
        final intruderRes = validator.validate(
          withIntruder,
          invoiceSchema,
          allowSystemFields: true,
        );
        expect(intruderRes.isValid, isFalse);
        expect(intruderRes.violations.single.path, r'$.unexpectedField');
        expect(intruderRes.violations.single.rule, 'additionalProperties');
      },
    );

    test('gère partialUpdate: true pour les mises à jour PATCH', () {
      final validPatch = <String, Object?>{
        'status': 'paid',
        'paymentUrl': null,
      };
      expect(
        validator
            .validate(validPatch, invoiceSchema, partialUpdate: true)
            .isValid,
        isTrue,
      );

      final invalidPatch = <String, Object?>{
        'customerEmail': 'invalide@@domaine',
        'lines': <Map<String, Object?>>[
          <String, Object?>{'sku': 'ONLY-SKU'},
        ],
      };
      final patchRes = validator.validate(
        invalidPatch,
        invoiceSchema,
        partialUpdate: true,
      );
      expect(patchRes.isValid, isFalse);
      expect(
        patchRes.violations.any(
          (v) => v.path == r'$.customerEmail' && v.rule == 'format',
        ),
        isTrue,
      );
      expect(
        patchRes.violations.any(
          (v) => v.path == r'$.lines[0].qty' && v.rule == 'required',
        ),
        isTrue,
      );
    });

    test('valide allOf, anyOf, oneOf et const', () {
      const composedSchema = <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'kind': <String, Object?>{'const': 'payment'},
          'channel': <String, Object?>{
            'oneOf': <Map<String, Object?>>[
              <String, Object?>{'type': 'string', 'pattern': r'^SEPA-'},
              <String, Object?>{'type': 'string', 'pattern': r'^CARD-'},
            ],
          },
          'tag': <String, Object?>{
            'anyOf': <Map<String, Object?>>[
              <String, Object?>{'type': 'integer', 'minimum': 10},
              <String, Object?>{'type': 'string', 'minLength': 4},
            ],
          },
          'score': <String, Object?>{
            'allOf': <Map<String, Object?>>[
              <String, Object?>{'type': 'integer', 'minimum': 0},
              <String, Object?>{'maximum': 100},
            ],
          },
        },
      };

      expect(
        validator.validate(<String, Object?>{
          'kind': 'payment',
          'channel': 'SEPA-001',
          'tag': 12,
          'score': 80,
        }, composedSchema).isValid,
        isTrue,
      );

      final badRes = validator.validate(<String, Object?>{
        'kind': 'refund',
        'channel': 'WIRE-001',
        'tag': 'ab',
        'score': 150,
      }, composedSchema);
      expect(badRes.isValid, isFalse);
      final rules = badRes.violations.map((v) => v.rule).toSet();
      expect(
        rules,
        containsAll(<String>['const', 'oneOf', 'anyOf', 'maximum']),
      );
    });

    test('valide ImportedValueObjectSpec avec jsonSchema explicite ou repli specJson', () {
      final spec = _buildTestDesignSpec();
      final domainValidator = JsonSchemaPayloadValidator.fromDesignSpec(spec);

      final voMoney = spec.findValueObjectByName('Money')!;
      expect(
        domainValidator.validateAgainstValueObject(<String, Object?>{
          'amount': 45.0,
          'currency': 'EUR',
        }, voMoney).isValid,
        isTrue,
      );
      expect(
        domainValidator.validateAgainstValueObject(<String, Object?>{
          'amount': -1,
          'currency': 'EUR',
        }, voMoney).isValid,
        isFalse,
      );

      final voVat = spec.findValueObjectByName('VatRate')!;
      expect(voVat.jsonSchema, isEmpty);
      expect(
        domainValidator.validateAgainstValueObject(20.0, voVat).isValid,
        isTrue,
      );
      expect(
        domainValidator.validateAgainstValueObject(19.3, voVat).isValid,
        isFalse,
      );
      expect(
        domainValidator.validateAgainstValueObject(120, voVat).isValid,
        isFalse,
      );

      final voAddress = spec.findValueObjectByName('PostalAddress')!;
      expect(voAddress.jsonSchema, isEmpty);
      expect(
        domainValidator.validateAgainstValueObject(<String, Object?>{
          'city': 'Lyon',
          'zipCode': '69001',
        }, voAddress).isValid,
        isTrue,
      );
      expect(
        domainValidator.validateAgainstValueObject(<String, Object?>{
          'city': 'L',
          'zipCode': 'ABC',
        }, voAddress).isValid,
        isFalse,
      );
    });
  });

  group('ProvisionedBackendService sur SqliteCollectionStore.inMemory()', () {
    late ProvisionedBackendService service;
    late DomainDesignSpec designSpec;

    setUp(() async {
      designSpec = _buildTestDesignSpec();
      service = ProvisionedBackendService(
        backend: SuperBackend(store: SqliteCollectionStore.inMemory()),
        designSpec: designSpec,
        overlay: BackendOverlayConfig.bootstrapFromDesign(designSpec),
      );
      await service.init();
    });

    tearDown(() async {
      await service.close();
    });

    test('rejette les collections inconnues ou désactivées', () async {
      await expectLater(
        () => service.search('unknown-collection'),
        throwsA(
          isA<CollectionDisabledOrUnknownException>().having(
            (e) => e.isDisabled,
            'isDisabled',
            isFalse,
          ),
        ),
      );

      final disabledOverlay = service.overlay.copyWith(
        collections: <BackendCollectionConfig>[
          for (final c in service.overlay.collections)
            c.collectionName == 'invoices' ? c.copyWith(enabled: false) : c,
        ],
      );
      service.updateConfiguration(overlay: disabledOverlay);

      await expectLater(
        () => service.search('invoices'),
        throwsA(
          isA<CollectionDisabledOrUnknownException>().having(
            (e) => e.isDisabled,
            'isDisabled',
            isTrue,
          ),
        ),
      );
    });

    test(
      'applique la validation stricte JSON Schema sur create et update',
      () async {
        await expectLater(
          () => service.create('invoices', <String, Object?>{
            'invoiceNumber': 'INVALID',
          }),
          throwsA(isA<PayloadValidationException>()),
        );

        final created = await service.create(
          'invoices',
          _validInvoicePayload(),
          id: 'inv_valid_1',
        );
        expect(created['id'], 'inv_valid_1');
        expect(created['invoiceNumber'], 'INV-0001');

        await expectLater(
          () => service.update('invoices', 'inv_valid_1', <String, Object?>{
            'customerEmail': 'mauvais-email',
          }),
          throwsA(isA<PayloadValidationException>()),
        );

        final afterInvalidUpdate = await service.read(
          'invoices',
          'inv_valid_1',
        );
        expect(afterInvalidUpdate['customerEmail'], 'alice@client.fr');
      },
    );

    test('applique BackendConcurrencyMode.optimisticVersion et lève OptimisticConcurrencyException', () async {
      final created = await service.create(
        'invoices',
        _validInvoicePayload(invoiceNumber: 'INV-0010'),
        id: 'inv_opt_1',
      );
      expect(created['version'], 1);

      final updated = await service.update(
        'invoices',
        'inv_opt_1',
        <String, Object?>{'status': 'issued'},
        expectedVersion: 1,
      );
      expect(updated['version'], 2);
      expect(updated['status'], 'issued');

      await expectLater(
        () => service.update('invoices', 'inv_opt_1', <String, Object?>{
          'status': 'paid',
        }, expectedVersion: 1),
        throwsA(
          isA<OptimisticConcurrencyException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.expectedVersion, 'expectedVersion', 1)
              .having((e) => e.actualVersion, 'actualVersion', 2),
        ),
      );

      final updatedViaPayloadVersion = await service.update(
        'invoices',
        'inv_opt_1',
        <String, Object?>{'status': 'paid', 'version': 2},
      );
      expect(updatedViaPayloadVersion['version'], 3);
      expect(updatedViaPayloadVersion['status'], 'paid');
    });

    test(
      'applique BackendDeletionMode.softDelete et immutableArchive',
      () async {
        await service.create(
          'invoices',
          _validInvoicePayload(invoiceNumber: 'INV-0021'),
          id: 'inv_soft_1',
        );
        await service.create(
          'invoices',
          _validInvoicePayload(invoiceNumber: 'INV-0022'),
          id: 'inv_soft_2',
        );

        final deleted = await service.delete('invoices', 'inv_soft_1');
        expect(deleted, isTrue);

        final activeSearch = await service.search('invoices');
        expect(activeSearch.total, 1);
        expect(activeSearch.items.single['id'], 'inv_soft_2');

        final allSearch = await service.search(
          'invoices',
          includeSoftDeleted: true,
        );
        expect(allSearch.total, 2);

        await expectLater(
          () => service.read('invoices', 'inv_soft_1'),
          throwsA(isA<EntityNotFoundException>()),
        );

        final softDeletedEntity = await service.read(
          'invoices',
          'inv_soft_1',
          includeSoftDeleted: true,
        );
        expect(softDeletedEntity['deletedAt'], isA<String>());

        final activeCounts = await service.collectionRowCounts();
        expect(activeCounts['invoices'], 1);
        final allCounts = await service.collectionRowCounts(
          includeSoftDeleted: true,
        );
        expect(allCounts['invoices'], 2);

        // Collection AuditLog configurée en immutableArchive.
        await service.create('audit-logs', <String, Object?>{
          'action': 'INVOICE_CREATED',
          'actorEmail': 'auditor@domaine.fr',
        }, id: 'audit_1');

        await expectLater(
          () => service.delete('audit-logs', 'audit_1'),
          throwsA(isA<ImmutableCollectionArchiveException>()),
        );

        // Suppression forcée explicite (hard: true) autorisée pour l'administration studio.
        expect(
          await service.delete('audit-logs', 'audit_1', hard: true),
          isTrue,
        );
        expect((await service.collectionRowCounts())['audit-logs'], 0);
      },
    );

    test(
      'exécute invariantHook sur create et update et propage les rejets métier',
      () async {
        final hookCalls = <String>[];
        service.updateConfiguration(
          invariantHook:
              ({
                required collection,
                required contract,
                required entity,
                required operation,
              }) async {
                hookCalls.add('${collection.collectionName}:$operation');
                final total = entity['total'];
                if (total is Map && (total['amount'] as num) > 1000) {
                  throw StateError('Plafond métier dépassé (> 1000).');
                }
              },
        );

        await expectLater(
          () => service.create(
            'invoices',
            _validInvoicePayload(
              invoiceNumber: 'INV-0099',
              totalAmount: 2500.0,
            ),
            id: 'inv_rejected',
          ),
          throwsA(isA<StateError>()),
        );
        expect((await service.search('invoices')).total, 0);

        await service.create(
          'invoices',
          _validInvoicePayload(invoiceNumber: 'INV-0050', totalAmount: 500.0),
          id: 'inv_hook_ok',
        );

        await expectLater(
          () => service.update('invoices', 'inv_hook_ok', <String, Object?>{
            'total': <String, Object?>{'amount': 1500.0, 'currency': 'EUR'},
          }),
          throwsA(isA<StateError>()),
        );

        final persisted = await service.read('invoices', 'inv_hook_ok');
        expect((persisted['total'] as Map)['amount'], 500.0);
        expect(hookCalls, <String>[
          'invoices:create',
          'invoices:create',
          'invoices:update',
        ]);
      },
    );

    test('seedCollection génère 5 entités déterministes valides et requêtables dans SQLite', () async {
      final seeded = await service.seedCollection('invoices', count: 5);
      expect(seeded, hasLength(5));

      final invoiceContract = designSpec.findContractById('model_invoice')!;
      for (final entity in seeded) {
        expect(entity['version'], 1);
        expect(entity['deletedAt'], isNull);
        final validation = service.validator.validate(
          entity,
          invoiceContract.jsonSchema,
          allowSystemFields: true,
        );
        expect(validation.isValid, isTrue, reason: '$validation');
      }

      // Vérifie l'utilisation de l'exemple valide du Value Object Money (150.0 EUR).
      expect(seeded.first['total'], <String, Object?>{
        'amount': 150.0,
        'currency': 'EUR',
      });

      final page = await service.search('invoices');
      expect(page.total, 5);
      expect(page.items, hasLength(5));

      final counts = await service.collectionRowCounts();
      expect(counts['invoices'], 5);
    });
  });
}
