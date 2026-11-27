/// Tests unitaires et disque de l'importateur Design ([DomainDesignImporter]),
/// du moteur différentiel et de réconciliation ([DomainDesignDiffEngine]) et
/// de l'analyseur de cohérence ([BackendCoherenceAnalyzer]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_backend_editor/models/backend_coherence_issue.dart';
import 'package:super_backend_editor/models/backend_overlay_config.dart';
import 'package:super_backend_editor/models/domain_design_diff.dart';
import 'package:super_backend_editor/models/domain_design_spec.dart';
import 'package:super_backend_editor/services/backend_coherence_analyzer.dart';
import 'package:super_backend_editor/services/backend_workspace_store.dart';
import 'package:super_backend_editor/services/importer/domain_design_diff_engine.dart';
import 'package:super_backend_editor/services/importer/domain_design_importer.dart';

Directory _createScratchDir(String suffix) {
  final sep = Platform.pathSeparator;
  final dir = Directory(
    '${Directory.current.path}$sep.dart_tool${sep}test_workspaces'
    '${sep}importer_diff_${suffix}_${DateTime.now().microsecondsSinceEpoch}',
  );
  dir.createSync(recursive: true);
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

Map<String, Object?> _buildExporterStyleBundleJson() => <String, Object?>{
  'format': 'super_spec_forge.domain_design_spec',
  'version': 1,
  'exportedAt': '2026-11-27T20:00:00.000Z',
  'sourceKind': 'current',
  'domain': <String, Object?>{
    'id': 'dom_billing',
    'domainCode': 'billing-core',
    'name': 'Facturation & Encaissements',
    'description': 'Domaine de facturation B2B.',
    'isActive': true,
    'techStackId': 'stack_ts_nestjs',
    'techStack': <String, Object?>{
      'id': 'stack_ts_nestjs',
      'code': 'ts-nestjs',
      'name': 'TypeScript / NestJS',
      'description': 'Architecture hexagonale NestJS.',
    },
  },
  'environments': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'env_dev',
      'domainId': 'dom_billing',
      'environmentCode': 'local-dev',
      'name': 'Développement local',
      'description': 'Poste développeur',
      'status': 'active',
      'isCloned': false,
    },
    <String, Object?>{
      'id': 'env_prod',
      'domainId': 'dom_billing',
      'environmentCode': 'production',
      'name': 'Production',
      'description': 'Cluster prod',
      'status': 'active',
      'isCloned': false,
    },
  ],
  'systems': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'svc_billing',
      'domainId': 'dom_billing',
      'serviceCode': 'billing-service',
      'name': 'Billing Service',
      'kind': 'microservice',
      'description': 'Cœur métier facturation',
      'isActive': true,
      'techStackId': 'stack_ts_nestjs',
    },
    <String, Object?>{
      'id': 'svc_stripe',
      'domainId': 'dom_billing',
      'serviceCode': 'stripe-api',
      'name': 'Stripe API',
      'kind': 'externalApp',
      'description': 'Passerelle de paiement',
      'isActive': true,
      'vendor': 'Stripe',
    },
  ],
  'configurations': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'cfg_currency',
      'domainId': 'dom_billing',
      'environmentId': 'env_dev',
      'configKey': 'DEFAULT_CURRENCY',
      'entryType': 'plainVariable',
      'plainValue': 'EUR',
      'isInitialized': true,
      'description': 'Devise par défaut',
    },
    <String, Object?>{
      'id': 'cfg_stripe_key_dev',
      'domainId': 'dom_billing',
      'environmentId': 'env_dev',
      'microserviceId': 'svc_stripe',
      'configKey': 'STRIPE_SECRET_KEY',
      'entryType': 'secret',
      'isInitialized': true,
      'description': 'Clé API Stripe de dev',
    },
    <String, Object?>{
      'id': 'cfg_stripe_key_prod',
      'domainId': 'dom_billing',
      'environmentId': 'env_prod',
      'microserviceId': 'svc_stripe',
      'configKey': 'STRIPE_SECRET_KEY',
      'entryType': 'secret',
      'isInitialized': true,
      'description': 'Clé API Stripe de prod',
    },
  ],
  'valueObjects': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'vo_money',
      'scope': 'shared',
      'spec': <String, Object?>{
        'id': 'vo_money',
        'technicalName': 'Money',
        'name': 'Montant monétaire',
        'description': 'Montant décimal et devise ISO.',
        'category': 'Finance',
        'version': '1.0.0',
        'kind': 'composite',
        'fields': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'f_amount',
            'name': 'amount',
            'type': 'number',
            'required': true,
          },
          <String, Object?>{
            'id': 'f_currency',
            'name': 'currency',
            'type': 'string',
            'required': true,
          },
        ],
      },
      'jsonSchema': <String, Object?>{
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'title': 'Money',
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['amount', 'currency'],
        'properties': <String, Object?>{
          'amount': <String, Object?>{'type': 'number'},
          'currency': <String, Object?>{'type': 'string'},
        },
        'x-value-object': 'Money',
        'x-value-object-scope': 'shared',
      },
    },
  ],
  'contracts': <String, Object?>{
    'dslSource': 'models:\n  Invoice: model\n  LegacyCreditNote: model\ndto:\n  CreateInvoiceDto: createxdto\n',
    'entries': <Map<String, Object?>>[
      <String, Object?>{
        'entryId': 'node_invoice',
        'name': 'Invoice',
        'technicalName': 'Invoice',
        'groupName': 'models',
        'dslType': 'model',
        'title': 'Facture client',
        'version': '1.0.0',
        'states': <String, String>{'conception': 'done'},
        'objectSpec': <String, Object?>{
          'id': 'node_invoice',
          'name': 'Facture client',
          'technicalName': 'Invoice',
          'aggregateRoot': true,
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
              'type': 'valueObject',
              'valueObjectId': 'Money',
              'required': true,
            },
          ],
        },
        'jsonSchema': <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'title': 'Invoice',
          'type': 'object',
          'additionalProperties': false,
          'required': <String>['invoiceNumber', 'total'],
          'properties': <String, Object?>{
            'invoiceNumber': <String, Object?>{'type': 'string'},
            'total': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'amount': <String, Object?>{'type': 'number'},
                'currency': <String, Object?>{'type': 'string'},
              },
            },
          },
        },
        'domainLayer': <String, Object?>{
          'invariants': <Map<String, Object?>>[
            <String, Object?>{'id': 'inv_total', 'name': 'nonNegativeTotal'},
          ],
          'persistencePolicy': <String, Object?>{
            'repositoryPortName': 'InvoiceRepository',
            'concurrencyStrategy': 'optimisticVersion',
            'deletionStrategy': 'softDelete',
          },
        },
      },
      <String, Object?>{
        'entryId': 'node_credit_note',
        'name': 'LegacyCreditNote',
        'technicalName': 'LegacyCreditNote',
        'groupName': 'models',
        'dslType': 'model',
        'title': 'Avoir historique',
        'version': '1.0.0',
        'states': const <String, String>{},
        'objectSpec': <String, Object?>{
          'id': 'node_credit_note',
          'name': 'Avoir historique',
          'technicalName': 'LegacyCreditNote',
          'attributes': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'a_reason',
              'name': 'reason',
              'type': 'string',
              'required': true,
            },
          ],
        },
        'jsonSchema': <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'title': 'LegacyCreditNote',
          'type': 'object',
          'properties': <String, Object?>{
            'reason': <String, Object?>{'type': 'string'},
          },
        },
        'domainLayer': const <String, Object?>{},
      },
      <String, Object?>{
        'entryId': 'node_create_dto',
        'name': 'CreateInvoiceDto',
        'technicalName': 'CreateInvoiceDto',
        'groupName': 'dto',
        'dslType': 'createxdto',
        'title': 'DTO Création facture',
        'version': '1.0.0',
        'states': const <String, String>{},
        'objectSpec': <String, Object?>{
          'id': 'node_create_dto',
          'name': 'DTO Création facture',
          'technicalName': 'CreateInvoiceDto',
        },
        'jsonSchema': <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'title': 'CreateInvoiceDto',
          'type': 'object',
          'properties': const <String, Object?>{},
        },
        'domainLayer': const <String, Object?>{},
      },
    ],
  },
  'useCaseOrchestration': <String, Object?>{
    'cartography': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'bc_billing',
        'boundedContext': 'Billing',
        'useCaseCodes': <String>['UC-001', 'UC-002'],
      },
    ],
    'useCases': <Map<String, Object?>>[
      <String, Object?>{
        'spec': <String, Object?>{
          'id': 'uc_create_invoice',
          'code': 'UC-001',
          'name': 'CreateInvoice',
          'title': 'Créer une facture',
          'version': '1.0.0',
          'boundedContext': 'Billing',
          'cqrsType': 'command',
          'targetAggregate': 'Invoice',
          'businessGoal': 'Émettre une nouvelle facture client.',
          'triggerInputs': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'customerId',
              'type': 'uuid',
              'required': true,
            },
          ],
          'businessRules': <String>['Montant positif'],
          'inboundPort': 'CreateInvoicePort',
          'outboundPorts': <String>['InvoiceRepository'],
          'emittedEvents': <String>['InvoiceCreated'],
          'outputs': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'invoiceId',
              'type': 'uuid',
              'required': true,
            },
          ],
        },
        'inputJsonSchema': <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'title': 'CreateInvoiceInput',
          'type': 'object',
          'additionalProperties': false,
          'required': <String>['customerId'],
          'properties': <String, Object?>{
            'customerId': <String, Object?>{'type': 'string', 'format': 'uuid'},
          },
        },
        'outputJsonSchema': <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'title': 'CreateInvoiceOutput',
          'type': 'object',
          'additionalProperties': false,
          'required': <String>['invoiceId'],
          'properties': <String, Object?>{
            'invoiceId': <String, Object?>{'type': 'string', 'format': 'uuid'},
          },
        },
      },
      <String, Object?>{
        'spec': <String, Object?>{
          'id': 'uc_void_credit_note',
          'code': 'UC-002',
          'name': 'VoidLegacyCreditNote',
          'title': 'Annuler un avoir historique',
          'version': '1.0.0',
          'boundedContext': 'Billing',
          'cqrsType': 'command',
          'targetAggregate': 'LegacyCreditNote',
        },
        'inputJsonSchema': <String, Object?>{
          'type': 'object',
          'properties': const <String, Object?>{},
        },
        'outputJsonSchema': <String, Object?>{
          'type': 'object',
          'properties': const <String, Object?>{},
        },
      },
    ],
    'sagas': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'saga_collect',
        'code': 'SAGA-001',
        'name': 'CollectInvoicePaymentSaga',
        'title': 'Encaissement facture',
        'version': '1.0.0',
        'boundedContexts': <String>['Billing', 'Payments'],
        'coordinationMode': 'orchestration',
        'triggerEventOrCommand': 'InvoiceIssued',
        'mermaidDiagram': 'sequenceDiagram\nBilling->>Stripe: Charge',
        'steps': <Map<String, Object?>>[
          <String, Object?>{'id': 'st_1', 'name': 'ChargeCard'},
        ],
        'compensationMatrix': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'cmp_1',
            'step': 'ChargeCard',
            'compensationAction': 'RefundCard',
          },
        ],
      },
    ],
  },
};

Map<String, Object?> _buildSimulatedSpecForgeCatalogJson() => <String, Object?>{
  'format': 'super_spec_forge.domain_catalog',
  'version': 1,
  'data': <String, Object?>{
    'techStacks': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'stack_custom_dart',
        'code': 'dart-shelf',
        'name': 'Dart / Shelf Hexagonal',
        'description': 'Backend Dart natif.',
      },
    ],
    'sharedValueObjects': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'vo_shared_money',
        'technicalName': 'Money',
        'name': 'Montant générique partagé',
        'description':
            'Version Shared Kernel devant être masquée par le domaine.',
        'version': '1.0.0',
        'kind': 'scalar',
        'primitiveType': 'number',
      },
      <String, Object?>{
        'id': 'vo_shared_email',
        'technicalName': 'EmailAddress',
        'name': 'Adresse email',
        'description': 'Email normalisé RFC 5322.',
        'version': '1.1.0',
        'kind': 'scalar',
        'primitiveType': 'email',
        'normalizationRules': <String>['trim', 'lowercase'],
        'schemaConstraints': <String, Object?>{
          'minLength': 5,
          'maxLength': 254,
        },
        'examples': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'ex_ok',
            'value': 'client@acme.fr',
            'isValid': true,
          },
          <String, Object?>{
            'id': 'ex_ko',
            'value': 'invalide',
            'isValid': false,
            'reason': 'Format invalide',
          },
        ],
      },
    ],
    'environments': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'env_orders_dev',
        'domainId': 'dom_orders',
        'environmentCode': 'dev',
        'name': 'Dev Orders',
        'status': 'active',
      },
      <String, Object?>{
        'id': 'env_other',
        'domainId': 'dom_inventory',
        'environmentCode': 'dev',
        'name': 'Dev Inventory',
        'status': 'active',
      },
    ],
    'microservices': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'ms_orders',
        'domainId': 'dom_orders',
        'serviceCode': 'orders-core',
        'name': 'Orders Core Service',
        'kind': 'microservice',
        'isActive': true,
      },
    ],
    'configurationEntries': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'cfg_max_lines',
        'domainId': 'dom_orders',
        'environmentId': 'env_orders_dev',
        'configKey': 'MAX_ORDER_LINES',
        'entryType': 'plainVariable',
        'plainValue': '50',
        'isInitialized': true,
        'description': 'Plafond de lignes par commande',
      },
      <String, Object?>{
        'id': 'cfg_webhook_hmac',
        'domainId': 'dom_orders',
        'environmentId': 'env_orders_dev',
        'microserviceId': 'ms_orders',
        'configKey': 'WEBHOOK_HMAC_SECRET',
        'entryType': 'secret',
        'plainValue': 'SHOULD_BE_STRIPPED',
        'encryptedValue': 'AES256:9f8a7b6c5d4e',
        'isInitialized': true,
        'description': 'Secret de signature HMAC',
      },
    ],
    'domains': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'dom_orders',
        'domainCode': 'orders-management',
        'name': 'Gestion des Commandes',
        'description': 'Prise de commande et cycle logistique.',
        'isActive': true,
        'techStackId': 'stack_custom_dart',
        'valueObjects': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'vo_domain_money',
            'technicalName': 'money',
            'name': 'Montant Commande EUR',
            'description': 'Surcharge domaine de Money en centimes + devise.',
            'version': '2.0.0',
            'kind': 'composite',
            'crossFieldRules': <String>['amount >= 0'],
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
                'enumValues': <String>['EUR', 'USD'],
              },
            ],
          },
        ],
        'contracts': <String, Object?>{
          'source': 'models:\n  Order: model\ncomponents:\n  ShippingAddress: component\n',
          'nodes': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'grp_models',
              'name': 'models',
              'type': 'object',
              'value': null,
              'children': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'ent_order',
                  'name': 'Order',
                  'type': 'model',
                  'value': 'model',
                },
              ],
            },
            <String, Object?>{
              'id': 'grp_components',
              'name': 'components',
              'type': 'object',
              'value': null,
              'children': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'ent_addr',
                  'name': 'ShippingAddress',
                  'type': 'component',
                  'value': 'component',
                },
              ],
            },
          ],
          'details': <String, Object?>{
            'ent_order': <String, Object?>{
              'title': 'Commande client',
              'version': '1.3.0',
              'states': <String, String>{'conception': 'done'},
            },
            'ent_addr': <String, Object?>{
              'title': 'Adresse de livraison',
              'version': '1.0.0',
              'states': const <String, String>{},
            },
          },
          'objects': <String, Object?>{
            'ent_addr': <String, Object?>{
              'id': 'ent_addr',
              'name': 'Adresse de livraison',
              'technicalName': 'ShippingAddress',
              'attributes': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'a_city',
                  'name': 'city',
                  'type': 'string',
                  'required': true,
                },
              ],
            },
            'ent_order': <String, Object?>{
              'id': 'ent_order',
              'name': 'Commande client',
              'technicalName': 'Order',
              'description': 'Agrégat racine Order.',
              'attributes': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'a_email',
                  'name': 'buyerEmail',
                  'type': 'valueObject',
                  'valueObjectId': 'EmailAddress',
                  'required': true,
                },
                <String, Object?>{
                  'id': 'a_total',
                  'name': 'totalAmount',
                  'type': 'valueObject',
                  'valueObjectId': 'money',
                  'required': true,
                },
                <String, Object?>{
                  'id': 'a_ship',
                  'name': 'shippingAddress',
                  'type': 'reference',
                  'referenceObjectId': 'ent_addr',
                  'required': true,
                },
                <String, Object?>{
                  'id': 'a_tags',
                  'name': 'tags',
                  'type': 'string',
                  'isArray': true,
                  'estimatedMaxRows': 10,
                  'schemaConstraints': <String, Object?>{
                    'minItems': 1,
                    'uniqueItems': true,
                    'minLength': 2,
                  },
                },
                <String, Object?>{
                  'id': 'a_notes',
                  'name': 'notes',
                  'type': 'string',
                  'nullable': true,
                },
              ],
            },
          },
          'domainLayers': <String, Object?>{
            'ent_order': <String, Object?>{
              'persistencePolicy': <String, Object?>{
                'repositoryPortName': 'OrderRepository',
                'concurrencyStrategy': 'optimisticVersion',
                'deletionStrategy': 'softDelete',
              },
            },
          },
        },
        'useCaseOrchestration': <String, Object?>{
          'cartography': <Map<String, Object?>>[
            <String, Object?>{'id': 'c_1', 'boundedContext': 'Orders'},
          ],
          'useCases': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'uc_place_order',
              'code': 'UC-101',
              'name': 'PlaceOrder',
              'title': 'Passer une commande',
              'version': '1.2.0',
              'boundedContext': 'Orders',
              'cqrsType': 'command',
              'targetAggregate': 'Order',
              'businessGoal': 'Valider et enregistrer un panier client.',
              'triggerInputs': <Object?>[
                <String, Object?>{
                  'name': 'buyerEmail',
                  'type': 'email',
                  'required': true,
                },
                <String, Object?>{
                  'name': 'totalCents',
                  'type': 'integer',
                  'constraints': '> 0',
                  'required': true,
                },
              ],
              'outputs': <Object?>['orderId: uuid! (UUID)'],
            },
          ],
          'sagas': const <Object?>[],
        },
        'iterationSnapshots': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'snap_mvp_1',
            'iterationNumber': 1,
            'label': 'Itération 1 — MVP Commandes',
            'notes': 'Version initiale',
            'createdAt': '2026-10-01T10:00:00.000Z',
            'techStackId': 'stack_custom_dart',
            'models': <String, Object?>{
              'ent_order': <String, Object?>{
                'entryId': 'ent_order',
                'name': 'Order',
                'dslType': 'model',
                'groupName': 'models',
                'title': 'Commande MVP',
                'version': '1.0.0',
                'objectSpec': <String, Object?>{
                  'id': 'ent_order',
                  'name': 'Commande MVP',
                  'technicalName': 'Order',
                  'attributes': <Map<String, Object?>>[
                    <String, Object?>{
                      'id': 'a_code',
                      'name': 'orderCode',
                      'type': 'string',
                      'required': true,
                    },
                  ],
                },
              },
            },
            'valueObjects': <String, Object?>{
              'vo_shared_email': <String, Object?>{
                'id': 'vo_shared_email',
                'scope': 'shared',
                'spec': <String, Object?>{
                  'id': 'vo_shared_email',
                  'technicalName': 'EmailAddress',
                  'name': 'Adresse email',
                  'version': '1.0.0',
                  'kind': 'scalar',
                  'primitiveType': 'email',
                },
              },
            },
            'useCases': <String, Object?>{
              'uc_place_order': <String, Object?>{
                'id': 'uc_place_order',
                'code': 'UC-101',
                'name': 'PlaceOrder',
                'title': 'Passer une commande MVP',
                'version': '1.0.0',
                'cqrsType': 'command',
                'targetAggregate': 'Order',
                'triggerInputs': <Map<String, Object?>>[
                  <String, Object?>{
                    'name': 'orderCode',
                    'type': 'string',
                    'required': true,
                  },
                ],
                'outputs': const <Object?>[],
              },
            },
            'sagas': const <String, Object?>{},
          },
        ],
      },
      <String, Object?>{
        'id': 'dom_inventory',
        'domainCode': 'inventory-stock',
        'name': 'Gestion des Stocks',
        'isActive': false,
      },
    ],
  },
};

void main() {
  const importer = DomainDesignImporter();

  group('DomainDesignImporter — Bundle portable .domain-design.json', () {
    test('importe fidèlement un bundle au format exact de DomainDesignSpecExporter', () async {
      final scratch = _createScratchDir('bundle');
      final sep = Platform.pathSeparator;
      final bundleFile = File(
        '${scratch.path}${sep}billing-core.domain-design.json',
      );
      final rawBundle = _buildExporterStyleBundleJson();
      await bundleFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(rawBundle),
        flush: true,
      );

      final spec = await importer.importFromBundleFile(bundleFile);

      expect(spec.format, DomainDesignSpec.formatId);
      expect(spec.version, 1);
      expect(spec.sourceKind, DesignSourceKind.current);
      expect(spec.domain.domainCode, 'billing-core');
      expect(spec.domain.techStack?.code, 'ts-nestjs');
      expect(spec.environments, hasLength(2));
      expect(spec.systems, hasLength(2));
      expect(spec.configurations, hasLength(3));
      expect(spec.valueObjects.single.technicalName, 'Money');
      expect(spec.models.map((m) => m.technicalName), <String>[
        'Invoice',
        'LegacyCreditNote',
      ]);
      expect(spec.dtos.single.technicalName, 'CreateInvoiceDto');
      expect(spec.useCases, hasLength(2));
      expect(spec.sagas.single.code, 'SAGA-001');

      final stripeCfg = spec.configurations.firstWhere(
        (c) => c.id == 'cfg_stripe_key_dev',
      );
      expect(stripeCfg.isSecret, isTrue);
      expect(stripeCfg.plainValue, isNull);
    });
  });

  group('DomainDesignImporter — Workspace super_spec_forge (catalog.json)', () {
    test('inspecte le workspace et importe l’état courant avec masquage des secrets, '
        'précédence VO domaine > shared et synthèse Draft 2020-12', () async {
      final workspaceDir = _createScratchDir('spec_forge_ws');
      final sep = Platform.pathSeparator;
      final domainsDir = Directory('${workspaceDir.path}${sep}domains')
        ..createSync(recursive: true);
      final catalogFile = File('${domainsDir.path}${sep}catalog.json');
      await catalogFile.writeAsString(
        jsonEncode(_buildSimulatedSpecForgeCatalogJson()),
        flush: true,
      );

      // Inspection depuis la racine du workspace ET depuis domains/.
      final summariesFromRoot = await importer.inspectSpecForgeWorkspace(
        workspaceDir,
      );
      final summariesFromDomains = await importer.inspectSpecForgeWorkspace(
        domainsDir,
      );
      expect(summariesFromRoot, equals(summariesFromDomains));
      expect(summariesFromRoot, hasLength(2));

      final ordersSummary = summariesFromRoot.firstWhere(
        (d) => d.domainCode == 'orders-management',
      );
      expect(ordersSummary.modelsCount, 1);
      expect(ordersSummary.useCasesCount, 1);
      expect(ordersSummary.snapshots, hasLength(1));
      expect(ordersSummary.snapshots.single.id, 'snap_mvp_1');
      expect(ordersSummary.snapshots.single.iterationNumber, 1);

      // Import de l'état courant vivant.
      final liveSpec = await importer.importFromSpecForgeWorkspace(
        workspaceDirectory: workspaceDir,
        domainIdOrCode: 'orders-management',
        importedAt: DateTime.utc(2026, 11, 27, 21, 0),
      );

      expect(liveSpec.sourceKind, DesignSourceKind.workspaceCatalog);
      expect(liveSpec.snapshotMeta, isNull);
      expect(liveSpec.domain.techStack?.code, 'dart-shelf');
      expect(liveSpec.environments.single.id, 'env_orders_dev');
      expect(liveSpec.systems.single.serviceCode, 'orders-core');

      // Vérification stricte du nettoyage de `encryptedValue` et `plainValue` secrète.
      final secretCfg = liveSpec.configurations.firstWhere(
        (c) => c.configKey == 'WEBHOOK_HMAC_SECRET',
      );
      expect(secretCfg.isSecret, isTrue);
      expect(secretCfg.plainValue, isNull);
      expect(secretCfg.toJson().containsKey('encryptedValue'), isFalse);
      expect(secretCfg.toJson().containsKey('plainValue'), isFalse);

      // Précédence insensible à la casse : Money du domaine écrase Money partagé,
      // tandis que EmailAddress partagé est conservé.
      expect(liveSpec.valueObjects, hasLength(2));
      final moneyVo = liveSpec.findValueObjectByName('Money')!;
      expect(moneyVo.id, 'vo_domain_money');
      expect(moneyVo.scope, 'domain');
      expect(moneyVo.isComposite, isTrue);
      expect(
        moneyVo.jsonSchema[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema',
      );
      expect(moneyVo.jsonSchema['additionalProperties'], isFalse);
      expect(moneyVo.jsonSchema['required'], <String>['amount', 'currency']);
      expect(moneyVo.jsonSchema['x-cross-field-rules'], <String>[
        'amount >= 0',
      ]);

      final emailVo = liveSpec.findValueObjectByName('EmailAddress')!;
      expect(emailVo.scope, 'shared');
      expect(emailVo.jsonSchema['format'], 'email');
      expect(emailVo.jsonSchema['minLength'], 5);
      expect(emailVo.jsonSchema['x-normalization'], <String>[
        'trim',
        'lowercase',
      ]);
      expect(emailVo.jsonSchema['examples'], <String>['client@acme.fr']);

      // Synthèse JSON Schema Draft 2020-12 sur le modèle Order.
      final orderModel = liveSpec.findContractById('ent_order')!;
      final orderSchema = orderModel.jsonSchema;
      expect(
        orderSchema[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema',
      );
      expect(orderSchema['title'], 'Order');
      expect(orderSchema['additionalProperties'], isFalse);
      expect(orderSchema['required'], <String>[
        'buyerEmail',
        'totalAmount',
        'shippingAddress',
      ]);
      final props = orderSchema['properties']! as Map<String, Object?>;
      expect((props['buyerEmail']! as Map)['format'], 'email');
      expect((props['totalAmount']! as Map)['x-value-object'], 'money');
      final shipSchema = props['shippingAddress']! as Map<String, Object?>;
      expect(shipSchema['x-reference'], 'ShippingAddress');
      expect((shipSchema['properties']! as Map).containsKey('city'), isTrue);
      final tagsSchema = props['tags']! as Map<String, Object?>;
      expect(tagsSchema['type'], 'array');
      expect(tagsSchema['minItems'], 1);
      expect(tagsSchema['maxItems'], 10);
      expect(tagsSchema['uniqueItems'], isTrue);
      expect((tagsSchema['items']! as Map)['minLength'], 2);
      expect((props['notes']! as Map)['type'], <String>['string', 'null']);

      // Synthèse JSON Schema Input / Output sur le Use Case PlaceOrder.
      final placeOrder = liveSpec.findUseCaseById('uc_place_order')!;
      expect(placeOrder.inputJsonSchema['title'], 'PlaceOrderInput');
      expect(placeOrder.inputJsonSchema['required'], <String>[
        'buyerEmail',
        'totalCents',
      ]);
      final inProps =
          placeOrder.inputJsonSchema['properties']! as Map<String, Object?>;
      expect((inProps['totalCents']! as Map)['exclusiveMinimum'], 0);
      expect(placeOrder.outputJsonSchema['required'], <String>['orderId']);
      final outProps =
          placeOrder.outputJsonSchema['properties']! as Map<String, Object?>;
      expect((outProps['orderId']! as Map)['format'], 'uuid');
    });

    test(
      'importe un jalon figé (iterationSnapshots) depuis domains/catalog.json',
      () async {
        final snapSpec = importer.importFromCatalogMap(
          _buildSimulatedSpecForgeCatalogJson(),
          domainIdOrCode: 'dom_orders',
          snapshotId: 'snap_mvp_1',
          importedAt: DateTime.utc(2026, 11, 27, 21, 15),
        );

        expect(snapSpec.sourceKind, DesignSourceKind.snapshot);
        expect(snapSpec.snapshotMeta?.id, 'snap_mvp_1');
        expect(snapSpec.snapshotMeta?.iterationNumber, 1);
        expect(snapSpec.contractEntries, hasLength(1));
        expect(snapSpec.models.single.version, '1.0.0');
        expect(snapSpec.models.single.title, 'Commande MVP');
        expect(
          (snapSpec.models.single.jsonSchema['properties']! as Map).keys,
          <String>['orderCode'],
        );
        expect(snapSpec.valueObjects.single.technicalName, 'EmailAddress');
        expect(snapSpec.useCases.single.version, '1.0.0');
        expect(snapSpec.useCases.single.inputJsonSchema['required'], <String>[
          'orderCode',
        ]);
      },
    );
  });

  group('DomainDesignDiffEngine — Diff & Réconciliation non destructive', () {
    test('amorce le projet initial puis réconcilie une v2 sans écraser les scripts, '
        'surcharges et collections/routes personnalisées, en marquant les suppressions orphelines', () {
      final v1Spec = importer.parseBundleMap(_buildExporterStyleBundleJson());
      final initialProject = DomainDesignDiffEngine.applyInitialImport(
        spec: v1Spec,
        sourceLabel: 'billing-core.v1.domain-design.json',
        notes: 'Import initial',
        importedAt: DateTime.utc(2026, 11, 27, 19, 0),
      );

      expect(initialProject.importHistory, hasLength(1));
      expect(initialProject.overlay.collections, hasLength(2));
      final initialInvoiceCol = initialProject.overlay
          .findCollectionForContract('node_invoice')!;
      expect(initialInvoiceCol.deletionMode, BackendDeletionMode.softDelete);
      expect(
        initialInvoiceCol.concurrencyMode,
        BackendConcurrencyMode.optimisticVersion,
      );

      // Personnalisations locales par l'utilisateur sur la v1.
      final customizedCollections = <BackendCollectionConfig>[
        for (final col in initialProject.overlay.collections)
          if (col.id == 'node_invoice')
            col.copyWith(
              collectionName: 'vip_invoices',
              label: 'Factures Grands Comptes',
              strictSchemaValidation: false,
              invariantScriptPath: 'invariants/invoice_guard.js',
            )
          else
            col,
        const BackendCollectionConfig(
          id: 'col_custom_audit',
          collectionName: 'local_audit_trail',
          label: 'Journal local',
        ),
      ];

      final customizedEndpoints = <BackendEndpointConfig>[
        for (final ep in initialProject.overlay.endpoints)
          if (ep.useCaseId == 'uc_create_invoice')
            ep.copyWith(
              path: '/api/v2/commands/issue-invoice',
              handlerScriptPath: 'usecases/create_invoice.js',
            )
          else
            ep,
        BackendEndpointConfig(
          id: 'ep_custom_webhook',
          kind: BackendEndpointKind.custom,
          method: 'POST',
          path: '/api/webhooks/stripe',
          summary: 'Webhook Stripe entrant',
          handlerScriptPath: 'webhooks/stripe.js',
        ),
      ];

      final customizedScripts = <BackendScriptBinding>[
        const BackendScriptBinding(
          id: 'sb_invoice_cmd',
          targetKind: BackendScriptTargetKind.aggregateCommand,
          targetId: 'node_invoice',
          targetSubName: 'issue',
          label: 'Émission facture',
          scriptPath: 'aggregates/invoice_issue.js',
        ),
        const BackendScriptBinding(
          id: 'sb_legacy_credit',
          targetKind: BackendScriptTargetKind.modelInvariant,
          targetId: 'node_credit_note',
          label: 'Invariant avoir historique',
          scriptPath: 'invariants/legacy_credit.js',
        ),
        const BackendScriptBinding(
          id: 'sb_custom_ep',
          targetKind: BackendScriptTargetKind.customEndpoint,
          targetId: 'ep_custom_webhook',
          label: 'Handler Webhook Stripe',
          scriptPath: 'webhooks/stripe.js',
        ),
      ];

      final customizedProject = initialProject.copyWith(
        overlay: initialProject.overlay.copyWith(
          collections: customizedCollections,
          endpoints: customizedEndpoints,
          scripts: customizedScripts,
          environmentVariableOverrides: const <String, Map<String, String>>{
            'env_dev': <String, String>{'DEFAULT_CURRENCY': 'CHF'},
          },
          superDesignerExportPath: 'C:/exports/billing_ui',
        ),
        localSecretValues: const <String, Map<String, String>>{
          'env_dev': <String, String>{'STRIPE_SECRET_KEY': 'sk_test_local'},
        },
      );

      // Construction d'une v2 :
      // - modification de Invoice (v1.2.0 + attribut dueDate) et CreateInvoice (v1.1.0 + input dueDate)
      // - ajout du modèle PaymentReceipt et de la requête GetPaymentSummary
      // - suppression de LegacyCreditNote et VoidLegacyCreditNote
      final updatedInvoice = v1Spec
          .findContractById('node_invoice')!
          .copyWith(
            version: '1.2.0',
            title: 'Facture client consolidée',
            objectSpecJson: <String, Object?>{
              ...v1Spec.findContractById('node_invoice')!.objectSpecJson,
              'attributes': <Map<String, Object?>>[
                ...v1Spec.findContractById('node_invoice')!.attributes,
                const <String, Object?>{
                  'id': 'a_due',
                  'name': 'dueDate',
                  'type': 'date',
                  'required': true,
                },
              ],
            },
          );

      final addedReceiptModel = ImportedContractEntry(
        entryId: 'node_receipt',
        name: 'PaymentReceipt',
        technicalName: 'PaymentReceipt',
        groupName: 'models',
        dslType: 'model',
        title: 'Reçu de paiement',
        version: '1.0.0',
        jsonSchema: const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'receiptCode': <String, Object?>{'type': 'string'},
          },
        },
      );

      final updatedCreateUc = v1Spec
          .findUseCaseById('uc_create_invoice')!
          .copyWith(
            version: '1.1.0',
            businessRules: const <String>[
              'Montant positif',
              'Échéance >= date facture',
            ],
            specJson: <String, Object?>{
              ...v1Spec.findUseCaseById('uc_create_invoice')!.specJson,
              'triggerInputs': const <Map<String, Object?>>[
                <String, Object?>{
                  'name': 'customerId',
                  'type': 'uuid',
                  'required': true,
                },
                <String, Object?>{
                  'name': 'dueDate',
                  'type': 'date',
                  'required': true,
                },
              ],
            },
          );

      final addedSummaryQuery = ImportedUseCaseSpec(
        id: 'uc_payment_summary',
        code: 'UC-003',
        name: 'GetPaymentSummary',
        title: 'Consulter la synthèse des paiements',
        version: '1.0.0',
        boundedContext: 'Billing',
        cqrsType: 'query',
        targetAggregate: 'PaymentReceipt',
      );

      final v2Spec = v1Spec.copyWith(
        exportedAt: DateTime.utc(2026, 11, 27, 22, 0),
        contractEntries: <ImportedContractEntry>[
          updatedInvoice,
          addedReceiptModel,
          v1Spec.findContractById('node_create_dto')!,
        ],
        useCases: <ImportedUseCaseSpec>[updatedCreateUc, addedSummaryQuery],
      );

      final preview = DomainDesignDiffEngine.previewReimport(
        currentProject: customizedProject,
        nextSpec: v2Spec,
        sourceLabel: 'billing-core.v2.domain-design.json',
        notes: 'Ajout reçus et retrait avoirs historiques',
        importedAt: DateTime.utc(2026, 11, 27, 22, 5),
      );

      expect(preview.diff.hasChanges, isTrue);
      expect(preview.diff.addedCount, 2);
      expect(preview.diff.modifiedCount, 2);
      expect(preview.diff.removedCount, 2);

      final invoiceDiff = preview.diff
          .entriesForCategory(DesignDiffItemCategory.contract)
          .firstWhere((e) => e.itemId == 'node_invoice');
      expect(invoiceDiff.changeKind, DesignDiffChangeKind.modified);
      expect(invoiceDiff.previousVersion, '1.0.0');
      expect(invoiceDiff.nextVersion, '1.2.0');
      expect(invoiceDiff.details.any((d) => d.contains('dueDate')), isTrue);

      final ucDiff = preview.diff
          .entriesForCategory(DesignDiffItemCategory.useCase)
          .firstWhere((e) => e.itemId == 'uc_create_invoice');
      expect(ucDiff.changeKind, DesignDiffChangeKind.modified);
      expect(ucDiff.details.any((d) => d.contains('dueDate')), isTrue);
      expect(ucDiff.details.any((d) => d.contains('Règles métier')), isTrue);

      final reimported = DomainDesignDiffEngine.applyReimport(
        currentProject: customizedProject,
        nextSpec: v2Spec,
        sourceLabel: 'billing-core.v2.domain-design.json',
        notes: 'Ajout reçus et retrait avoirs historiques',
        importedAt: DateTime.utc(2026, 11, 27, 22, 5),
      );

      expect(reimported.importHistory, hasLength(2));
      expect(
        reimported.localSecretValues['env_dev']?['STRIPE_SECRET_KEY'],
        'sk_test_local',
      );
      expect(
        reimported
            .overlay
            .environmentVariableOverrides['env_dev']?['DEFAULT_CURRENCY'],
        'CHF',
      );
      expect(
        reimported.overlay.superDesignerExportPath,
        'C:/exports/billing_ui',
      );

      // Collection Invoice personnalisée préservée.
      final mergedInvoiceCol = reimported.overlay.findCollectionForContract(
        'node_invoice',
      )!;
      expect(mergedInvoiceCol.isOrphaned, isFalse);
      expect(mergedInvoiceCol.collectionName, 'vip_invoices');
      expect(mergedInvoiceCol.label, 'Factures Grands Comptes');
      expect(mergedInvoiceCol.strictSchemaValidation, isFalse);
      expect(
        mergedInvoiceCol.invariantScriptPath,
        'invariants/invoice_guard.js',
      );

      // Collection personnalisée hors Design intacte.
      final customCol = reimported.overlay.findCollectionById(
        'col_custom_audit',
      )!;
      expect(customCol.isOrphaned, isFalse);
      expect(customCol.collectionName, 'local_audit_trail');

      // Ancienne collection conservée mais marquée orpheline.
      final orphanedCol = reimported.overlay.findCollectionForContract(
        'node_credit_note',
      )!;
      expect(orphanedCol.isOrphaned, isTrue);

      // Nouvelle collection + endpoint SCRUD + endpoint CQRS Query amorcés.
      final receiptCol = reimported.overlay.findCollectionForContract(
        'node_receipt',
      )!;
      expect(receiptCol.isOrphaned, isFalse);
      expect(receiptCol.collectionName, 'payment-receipts');
      expect(
        reimported.overlay.endpoints.any(
          (ep) =>
              ep.kind == BackendEndpointKind.scrudCollection &&
              ep.collectionId == receiptCol.id &&
              ep.path == '/api/payment-receipts',
        ),
        isTrue,
      );
      final summaryEp = reimported.overlay.endpoints.firstWhere(
        (ep) => ep.useCaseId == 'uc_payment_summary',
      );
      expect(summaryEp.kind, BackendEndpointKind.cqrsQuery);
      expect(summaryEp.method, 'GET');
      expect(summaryEp.path, '/api/queries/get-payment-summary');
      expect(summaryEp.collectionId, receiptCol.id);

      // Endpoints personnalisés et surchargés préservés, anciens marqués orphelins.
      final customEp = reimported.overlay.findEndpointById(
        'ep_custom_webhook',
      )!;
      expect(customEp.isOrphaned, isFalse);
      expect(customEp.handlerScriptPath, 'webhooks/stripe.js');

      final createUcEp = reimported.overlay.endpoints.firstWhere(
        (ep) => ep.useCaseId == 'uc_create_invoice',
      );
      expect(createUcEp.isOrphaned, isFalse);
      expect(createUcEp.path, '/api/v2/commands/issue-invoice');
      expect(createUcEp.handlerScriptPath, 'usecases/create_invoice.js');

      final voidUcEp = reimported.overlay.endpoints.firstWhere(
        (ep) => ep.useCaseId == 'uc_void_credit_note',
      );
      expect(voidUcEp.isOrphaned, isTrue);

      // Scripts QuickJS conservés et état orphelin calculé.
      final scriptsById = <String, BackendScriptBinding>{
        for (final s in reimported.overlay.scripts) s.id: s,
      };
      expect(scriptsById['sb_invoice_cmd']!.isOrphaned, isFalse);
      expect(scriptsById['sb_custom_ep']!.isOrphaned, isFalse);
      expect(scriptsById['sb_legacy_credit']!.isOrphaned, isTrue);
    });
  });

  group('BackendCoherenceAnalyzer — Diagnostics mémoire & store disque', () {
    test(
      'détecte les routes HTTP dupliquées, scripts manquants via BackendWorkspaceStore, '
      'secrets locaux non renseignés, références cassées et éléments orphelins',
      () async {
        final wsRoot = _createScratchDir('coherence_store');
        final store = BackendWorkspaceStore(wsRoot);

        final baseSpec = importer.parseBundleMap(
          _buildExporterStyleBundleJson(),
        );
        // Ajout d'un modèle au schéma vide et d'une référence VO cassée pour couvrir les 6 catégories.
        final brokenModel = ImportedContractEntry(
          entryId: 'node_broken_draft',
          name: 'BrokenDraft',
          technicalName: 'BrokenDraft',
          groupName: 'models',
          dslType: 'model',
          title: 'Brouillon incomplet',
          version: '0.1.0',
          objectSpecJson: const <String, Object?>{
            'id': 'node_broken_draft',
            'name': 'Brouillon incomplet',
            'technicalName': 'BrokenDraft',
            'attributes': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'a_unknown_vo',
                'name': 'iban',
                'type': 'valueObject',
                'valueObjectId': 'UnknownIbanVo',
              },
            ],
          },
          jsonSchema: const <String, Object?>{},
        );

        final v1Project = DomainDesignDiffEngine.applyInitialImport(
          spec: baseSpec,
          sourceLabel: 'v1',
        );

        // Ré-import supprimant LegacyCreditNote pour générer des orphelins, tout en ajoutant BrokenDraft.
        final v2Spec = baseSpec.copyWith(
          contractEntries: <ImportedContractEntry>[
            baseSpec.findContractById('node_invoice')!,
            brokenModel,
            baseSpec.findContractById('node_create_dto')!,
          ],
          useCases: <ImportedUseCaseSpec>[
            baseSpec.findUseCaseById('uc_create_invoice')!,
          ],
        );
        var project = DomainDesignDiffEngine.applyReimport(
          currentProject: v1Project,
          nextSpec: v2Spec,
          sourceLabel: 'v2',
        );

        // Injection d'une route HTTP dupliquée et de deux références de scripts (1 présent, 1 absent).
        final endpointsWithDuplicateAndScripts = <BackendEndpointConfig>[
          ...project.overlay.endpoints.map(
            (ep) => ep.useCaseId == 'uc_create_invoice'
                ? ep.copyWith(handlerScriptPath: 'usecases/existing_create.js')
                : ep,
          ),
          BackendEndpointConfig(
            id: 'ep_dup_conflict',
            kind: BackendEndpointKind.custom,
            method: 'POST',
            path: '/api/commands/create-invoice/',
            summary: 'Doublon conflictuel',
            handlerScriptPath: 'custom/missing_handler.js',
          ),
        ];

        project = project.copyWith(
          overlay: project.overlay.copyWith(
            endpoints: endpointsWithDuplicateAndScripts,
          ),
        );

        await store.saveProject(project);
        await store.writeScript(
          project.domainCode,
          'usecases/existing_create.js',
          'export default function handle(ctx) { return { ok: true }; }\n',
        );

        final issues = await BackendCoherenceAnalyzer.analyzeFromStore(
          project,
          store,
        );

        // 1. Conflit de route HTTP -> erreur bloquante.
        final duplicateErrors = issues.where(
          (i) =>
              i.category == BackendIssueCategory.endpointBinding &&
              i.isError &&
              i.id.startsWith('ep_duplicate_route_'),
        );
        expect(duplicateErrors.length, 2);

        // 2. Script manquant sur disque détecté (missing_handler.js), mais existing_create.js OK.
        final missingScriptIssues = issues
            .where((i) => i.category == BackendIssueCategory.scriptMissing)
            .toList();
        expect(
          missingScriptIssues.any(
            (i) => i.isError && i.message.contains('custom/missing_handler.js'),
          ),
          isTrue,
        );
        expect(
          missingScriptIssues.any(
            (i) => i.message.contains('usecases/existing_create.js'),
          ),
          isFalse,
        );

        // 3. Secrets d'environnement non renseignés : warning sur env actif (env_dev), info sur env_prod.
        final secretIssues = issues
            .where((i) => i.category == BackendIssueCategory.environmentSecret)
            .toList();
        expect(
          secretIssues.any(
            (i) => i.targetId == 'cfg_stripe_key_dev' && i.isWarning,
          ),
          isTrue,
        );
        expect(
          secretIssues.any(
            (i) => i.targetId == 'cfg_stripe_key_prod' && i.isInfo,
          ),
          isTrue,
        );
        expect(
          secretIssues.every(
            (i) => i.suggestion != null && i.suggestion!.contains('.local/'),
          ),
          isTrue,
        );

        // 4. Collection et endpoint orphelins signalés en warning.
        expect(
          issues.any(
            (i) =>
                i.category == BackendIssueCategory.collectionMapping &&
                i.isWarning &&
                i.targetId == 'node_credit_note',
          ),
          isTrue,
        );
        expect(
          issues.any(
            (i) =>
                i.category == BackendIssueCategory.endpointBinding &&
                i.isWarning &&
                i.targetId == 'ep_uc_uc_void_credit_note',
          ),
          isTrue,
        );

        // 5. Référence Value Object inconnue et schéma JSON vide signalés.
        expect(
          issues.any(
            (i) =>
                i.category == BackendIssueCategory.valueObjectRef &&
                i.targetId == 'node_broken_draft',
          ),
          isTrue,
        );
        expect(
          issues.any(
            (i) =>
                i.category == BackendIssueCategory.contractSchema &&
                i.targetId == 'node_broken_draft',
          ),
          isTrue,
        );

        // Après écriture du script manquant et ajout du secret local de dev, les diagnostics correspondants disparaissent.
        await store.writeScript(
          project.domainCode,
          'custom/missing_handler.js',
          'export default function handle() { return {}; }\n',
        );
        final resolvedProject = project.copyWith(
          localSecretValues: const <String, Map<String, String>>{
            'env_dev': <String, String>{'STRIPE_SECRET_KEY': 'sk_test_ok'},
          },
        );
        final issuesAfterFix = await BackendCoherenceAnalyzer.analyzeFromStore(
          resolvedProject,
          store,
        );
        expect(
          issuesAfterFix.any(
            (i) =>
                i.category == BackendIssueCategory.scriptMissing && i.isError,
          ),
          isFalse,
        );
        expect(
          issuesAfterFix.any((i) => i.targetId == 'cfg_stripe_key_dev'),
          isFalse,
        );

        // Restauration en v3 : si LegacyCreditNote réapparaît, sa collection redevient active (isOrphaned: false).
        final restoredProject = DomainDesignDiffEngine.applyReimport(
          currentProject: resolvedProject,
          nextSpec: baseSpec,
          sourceLabel: 'v3-restore',
        );
        expect(
          restoredProject.overlay
              .findCollectionForContract('node_credit_note')!
              .isOrphaned,
          isFalse,
        );
      },
    );

    test(
      'computeDiff appaire par clés secondaires (environmentCode, serviceCode, '
      'triplet config et technicalName VO) lorsque les IDs techniques changent',
      () {
        final v1 = importer.parseBundleMap(_buildExporterStyleBundleJson());
        final v2 = v1.copyWith(
          environments: <ImportedEnvironmentSpec>[
            v1.environments.first.copyWith(
              id: 'env_dev_regenerated',
              name: 'Développement local v2',
            ),
            v1.environments.last,
          ],
          systems: <ImportedSystemSpec>[
            v1.systems.first.copyWith(
              id: 'svc_billing_regenerated',
              description: 'Nouvelle description service',
            ),
            v1.systems.last,
          ],
          configurations: <ImportedConfigurationSpec>[
            v1.configurations.first.copyWith(
              id: 'cfg_currency_regenerated',
              plainValue: 'USD',
            ),
            v1.configurations[1],
            v1.configurations[2],
          ],
          valueObjects: <ImportedValueObjectSpec>[
            v1.valueObjects.single.copyWith(
              id: 'vo_money_regenerated',
              description: 'Montant mis à jour',
            ),
          ],
        );

        final diff = DomainDesignDiffEngine.computeDiff(v1, v2);
        expect(diff.addedCount, 0);
        expect(diff.removedCount, 0);
        expect(diff.modifiedCount, 4);

        final summary = SpecForgeCatalogDomainSummary(
          id: 'dom_1',
          domainCode: 'billing-core',
          name: 'Facturation',
          modelsCount: 2,
          useCasesCount: 2,
        );
        expect(
          SpecForgeCatalogDomainSummary.fromJson(summary.toJson()),
          equals(summary),
        );
      },
    );
  });
}
