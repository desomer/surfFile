import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('UseCaseOrchestrationSpec & DomainCatalog', () {
    test('sérialise et restaure cartographie, Use Cases CQRS, Sagas et chat (sans octets de pièces jointes)', () {
      final spec = UseCaseOrchestrationSpec(
        cartography: [
          BoundedContextUseCaseMap(
            id: 'bc_catalog',
            boundedContext: 'Catalogue Produits',
            description: 'Gestion du catalogue et tarification',
            useCaseCodes: const ['UC-001'],
            sagaCodes: const ['SAGA-001'],
            notes: 'Publie ProductPriceUpdated',
          ),
        ],
        useCases: [
          ApplicationUseCaseSpec(
            id: 'uc_1',
            code: 'UC-001',
            name: 'UpdateProductPrice',
            title: 'Mise à jour du prix d’un produit',
            boundedContext: 'Catalogue Produits',
            cqrsType: UseCaseCqrsType.command,
            targetAggregate: 'Product',
            businessGoal: 'Permettre la mise à jour du prix d’un produit.',
            triggerInputs: const [
              UseCaseFieldSpec(
                name: 'productId',
                type: 'string',
                constraints: 'UUID',
              ),
              UseCaseFieldSpec(
                name: 'newPrice',
                type: 'number',
                constraints: '> 0',
              ),
            ],
            businessRules: const ['Le produit doit exister.'],
            inboundPort: 'UpdateProductPriceUseCase',
            outboundPorts: const [
              'ProductRepository',
              'PriceHistoryRepository',
            ],
            emittedEvents: const ['ProductPriceUpdated'],
            detailedProcess: const ['Charger', 'Valider', 'Sauvegarder'],
            outputs: const [
              UseCaseFieldSpec(name: 'productId', type: 'string'),
            ],
            possibleErrors: const ['ProductNotFound', 'InvalidPrice'],
            scenarios: [
              UseCaseScenarioSpec(
                id: 'scn_1',
                name: 'Scénario nominal : Mise à jour réussie',
                isNominal: true,
                given: const ['un produit existe'],
                when: const ['le prix est mis à jour'],
                then: const ['le produit est sauvegardé'],
              ),
            ],
            acceptanceCriteria: const ['Le prix positif est persisté.'],
            nonGoals: const ['La création d’un produit.'],
            concurrencyAndIdempotency: 'Version optimiste',
            linkedSpecRefs: const ['EXF-001', 'RG-001'],
          ),
        ],
        sagas: [
          OrchestrationSagaSpec(
            id: 'saga_1',
            code: 'SAGA-001',
            name: 'PriceSyncSaga',
            title: 'Synchronisation tarifaire',
            boundedContexts: const ['Catalogue Produits', 'Facturation'],
            coordinationMode: SagaCoordinationMode.orchestration,
            triggerEventOrCommand: 'ProductPriceUpdated',
            correlationKey: 'productId',
            failureRecoveryStrategy: 'Retry 3x puis DLQ',
            mermaidDiagram:
                'sequenceDiagram\n  Catalogue->>Facturation: syncPrice()',
            compensationMatrix: const [
              SagaCompensationRow(
                id: 'row_1',
                step: '1. Mise à jour tarif',
                nominalAction: 'updateTariff()',
                compensationAction: 'restorePreviousTariff()',
                rollbackTrigger: 'BillingSyncFailed',
                criticality: SagaStepCriticality.critical,
                idempotent: true,
                retryable: true,
                timeout: '10s',
              ),
            ],
          ),
        ],
        chatMessages: [
          SpecChatMessage(
            id: 'm1',
            isUser: true,
            text: 'Génère les Use Cases',
            attachments: [
              VibeChatAttachment(
                name: 'brief.txt',
                mimeType: 'text/plain',
                bytes: Uint8List.fromList([1, 2, 3]),
              ),
            ],
          ),
        ],
      );

      final catalog = DomainCatalog(
        domains: [
          FunctionalDomain(
            id: 'dom_cat',
            domainCode: 'catalogue',
            name: 'Catalogue',
            useCaseOrchestration: spec,
          ),
        ],
      );

      final restored = DomainCatalog.fromJson(
        jsonDecode(jsonEncode(catalog.toJson())),
      );
      final restoredSpec = restored.domains.single.useCaseOrchestration!;
      expect(restoredSpec.cartography, hasLength(1));
      expect(restoredSpec.useCases.single.cqrsType, UseCaseCqrsType.command);
      expect(restoredSpec.useCases.single.scenarios.single.given, [
        'un produit existe',
      ]);
      expect(
        restoredSpec.sagas.single.compensationMatrix.single.criticality,
        SagaStepCriticality.critical,
      );
      expect(
        restoredSpec.chatMessages.single.attachments.single.name,
        'brief.txt',
      );
      expect(
        restoredSpec.chatMessages.single.attachments.single.bytes,
        isEmpty,
      );

      final md = restoredSpec.toMarkdown(domainName: 'Catalogue');
      expect(md, contains('## 1. Cartographie par Bounded Context'));
      expect(md, contains('UpdateProductPrice'));
      expect(md, contains('```mermaid'));
      expect(
        md,
        contains(
          '| Étape | Action Nominale | Action de Compensation (Rollback) |',
        ),
      );
    });
  });

  group('UseCaseOrchestrationAiAgent', () {
    test('injecte les cas d’usage du projet actif et les contrats du domaine dans le prompt', () {
      var contracts = DomainContracts.parse('models:\n  Produit: model\n');
      final produitEntry = contracts.groups.single.children.single;
      contracts = contracts.withDomainLayer(
        produitEntry.id,
        layer: HexagonalDomainLayerSpec(
          stateChanges: [
            DomainStateChangeSpec(
              id: 'cmd_price',
              name: 'updatePrice',
              title: 'Mettre à jour le prix',
              associatedMethods: const ['updatePrice(newPrice)'],
            ),
          ],
          persistencePolicy: DomainPersistencePolicySpec(
            repositoryPortName: 'ProductRepository',
            portMethods: [
              DomainRepositoryMethodSpec(
                id: 'repo_save',
                associatedMethods: const ['save(product)', 'findById(id)'],
              ),
            ],
          ),
        ),
      );

      final domain = FunctionalDomain(
        id: 'dom_cat',
        domainCode: 'catalogue',
        name: 'Catalogue',
        contracts: contracts,
      );
      final catalog = DomainCatalog(
        domains: [
          domain,
          const FunctionalDomain(
            id: 'dom_bill',
            domainCode: 'billing',
            name: 'Facturation',
          ),
        ],
        microservices: const [
          Microservice(
            id: 'svc_1',
            domainId: 'dom_cat',
            serviceCode: 'catalog-api',
            name: 'Catalog API',
          ),
        ],
      );

      final now = DateTime.utc(2026, 6, 1);
      final project = SpecForgeProject(
        id: 'proj_1',
        name: 'ERP Commerce',
        initialIdea: 'Gestion catalogue',
        createdAt: now,
        updatedAt: now,
        cahierDesCharges: SpecCahierDesCharges(
          useCases: [
            UseCaseSpec(
              id: 'UC-SPEC-01',
              title: 'Modifier le tarif d’un produit',
              actorId: 'Gestionnaire',
              mainFlow: const ['Saisir nouveau tarif', 'Enregistrer'],
            ),
          ],
          functionalRequirements: [
            FunctionalRequirement(
              id: 'req_1',
              code: 'EXF-001',
              title: 'Historisation des prix',
            ),
          ],
        ),
        businessRules: [
          BusinessRuleSpec(
            id: 'rg_1',
            code: 'RG-001',
            title: 'Prix strictement positif',
            condition: 'newPrice > 0',
          ),
        ],
      );

      final prompt = UseCaseOrchestrationAiAgent.buildTurnPrompt(
        domain: domain,
        catalog: catalog,
        activeTab: UseCaseOrchestrationTab.useCases,
        history: const [],
        userInput: 'Génère les Use Cases',
        modelPreferences: BusinessObjectModelPreferences.defaults,
        questioningLevel: VibeQuestioningLevel.balanced,
        afterAskUserReply: false,
        activeProject: project,
      );

      expect(prompt, contains('ERP Commerce'));
      expect(prompt, contains('Modifier le tarif d’un produit'));
      expect(prompt, contains('EXF-001'));
      expect(prompt, contains('RG-001'));
      expect(prompt, contains('updatePrice(newPrice)'));
      expect(prompt, contains('ProductRepository'));
      expect(prompt, contains('Facturation (billing)'));
    });

    test(
      'applyPatch fusionne et supprime cartographie, Use Cases et Sagas',
      () {
        final first = UseCaseOrchestrationAiAgent.applyPatch(
          UseCaseOrchestrationSpec.empty,
          {
            'cartography': [
              {
                'boundedContext': 'Catalogue',
                'description': 'Produits et prix',
                'useCaseCodes': ['UC-001'],
                'sagaCodes': ['SAGA-001'],
              },
            ],
            'useCases': [
              {
                'code': 'UC-001',
                'name': 'UpdateProductPrice',
                'title': 'Mise à jour prix',
                'cqrsType': 'command',
                'businessGoal': 'Mettre à jour le prix',
                'triggerInputs': ['productId: string'],
                'outboundPorts': ['ProductRepository'],
                'possibleErrors': ['ProductNotFound'],
              },
            ],
            'sagas': [
              {
                'code': 'SAGA-001',
                'name': 'OrderSaga',
                'title': 'Validation commande',
                'mermaidDiagram': 'sequenceDiagram\n  A->>B: ok',
                'compensationMatrix': [
                  {
                    'step': '1. Stock',
                    'nominalAction': 'reserve()',
                    'compensationAction': 'release()',
                    'rollbackTrigger': 'PaymentFailed',
                    'criticality': 'critical',
                    'idempotent': true,
                    'retryable': true,
                    'timeout': '5s',
                  },
                ],
              },
            ],
          },
        );

        expect(first.spec.cartography, hasLength(1));
        expect(first.spec.useCases, hasLength(1));
        expect(first.spec.sagas, hasLength(1));
        expect(first.summary, contains('+1 contexte(s)'));
        expect(first.summary, contains('+1 Use Case(s)'));
        expect(first.summary, contains('+1 Saga(s)'));

        final second = UseCaseOrchestrationAiAgent.applyPatch(first.spec, {
          'useCases': [
            {
              'code': 'UC-001',
              'name': 'UpdateProductPrice',
              'title': 'Mise à jour prix enrichie',
              'cqrsType': 'command',
              'businessGoal': 'Objectif enrichi',
            },
          ],
          'removeSagas': ['SAGA-001'],
        });

        expect(second.spec.useCases.single.businessGoal, 'Objectif enrichi');
        expect(second.spec.sagas, isEmpty);
        expect(second.summary, contains('~1 Use Case(s)'));
        expect(second.summary, contains('-1 Saga(s)'));
      },
    );

    test('UseCaseFieldSpec supporte les champs imbriqués, tableaux, enums et syntaxe compacte', () {
      final compact = UseCaseFieldSpec.fromJson('items: OrderItem[]! (min 1)');
      expect(compact.name, 'items');
      expect(compact.type, 'OrderItem');
      expect(compact.isArray, isTrue);
      expect(compact.required, isTrue);
      expect(compact.effectiveRequired, isTrue);
      expect(compact.constraints, 'min 1');

      final nested = UseCaseFieldSpec.fromJson({
        'name': 'address',
        'type': 'object',
        'required': true,
        'description': 'Adresse de livraison',
        'children': [
          {
            'name': 'country',
            'type': 'enumeration',
            'enumValues': ['FR', 'BE'],
            'required': true,
          },
          {'name': 'zipCode', 'type': 'string', 'nullable': true},
        ],
      });
      expect(nested.totalFieldCount, 3);
      expect(nested.children.first.enumValues, ['FR', 'BE']);
      expect(nested.children.last.nullable, isTrue);

      final roundTrip = UseCaseFieldSpec.fromJson(nested.toJson());
      expect(roundTrip, nested);
    });

    test(
      'conserve les indicateurs d’avancement des phases sur Use Cases et Sagas',
      () {
        final initial = UseCaseOrchestrationSpec(
          useCases: [
            ApplicationUseCaseSpec(
              id: 'uc_1',
              code: 'UC-001',
              name: 'UpdateProductPrice',
              states: const {
                ContractStage.design: ContractStatus.done,
                ContractStage.validation: ContractStatus.inProgress,
              },
            ),
          ],
          sagas: [
            OrchestrationSagaSpec(
              id: 'saga_1',
              code: 'SAGA-001',
              name: 'OrderSaga',
              states: const {ContractStage.code: ContractStatus.done},
            ),
          ],
        );

        final restored = UseCaseOrchestrationSpec.fromJson(
          jsonDecode(jsonEncode(initial.toJson())),
        );
        expect(
          restored.useCases.single.states[ContractStage.design],
          ContractStatus.done,
        );
        expect(
          restored.useCases.single.states[ContractStage.validation],
          ContractStatus.inProgress,
        );
        expect(
          restored.sagas.single.states[ContractStage.code],
          ContractStatus.done,
        );

        final patched = UseCaseOrchestrationAiAgent.applyPatch(restored, {
          'useCases': [
            {
              'code': 'UC-001',
              'name': 'UpdateProductPrice',
              'businessGoal': 'Mis à jour par IA',
            },
          ],
          'sagas': [
            {
              'code': 'SAGA-001',
              'name': 'OrderSaga',
              'title': 'Saga mise à jour',
            },
          ],
        });
        expect(
          patched.spec.useCases.single.states[ContractStage.design],
          ContractStatus.done,
        );
        expect(
          patched.spec.sagas.single.states[ContractStage.code],
          ContractStatus.done,
        );
      },
    );

    test('valide et préserve version SemVer sur ApplicationUseCaseSpec et OrchestrationSagaSpec', () {
      expect(
        () => ApplicationUseCaseSpec(
          id: 'uc_bad',
          code: 'UC-009',
          name: 'InvalidVer',
          version: 'v1',
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => OrchestrationSagaSpec(
          id: 'saga_bad',
          code: 'SAGA-009',
          name: 'InvalidSagaVer',
          version: '1.0',
        ).validate(),
        throwsFormatException,
      );

      final initial = UseCaseOrchestrationSpec(
        useCases: [
          ApplicationUseCaseSpec(
            id: 'uc_1',
            code: 'UC-001',
            name: 'UpdateProductPrice',
            version: '1.4.0',
          ),
        ],
        sagas: [
          OrchestrationSagaSpec(
            id: 'saga_1',
            code: 'SAGA-001',
            name: 'OrderSaga',
            version: '2.0.3',
          ),
        ],
      );

      final restored = UseCaseOrchestrationSpec.fromJson(
        jsonDecode(jsonEncode(initial.toJson())),
      );
      expect(restored.useCases.single.version, '1.4.0');
      expect(restored.sagas.single.version, '2.0.3');

      final patchedWithoutVersion = UseCaseOrchestrationAiAgent.applyPatch(
        restored,
        {
          'useCases': [
            {
              'code': 'UC-001',
              'name': 'UpdateProductPrice',
              'businessGoal': 'Objectif mis à jour sans version explicite',
            },
          ],
          'sagas': [
            {
              'code': 'SAGA-001',
              'name': 'OrderSaga',
              'title': 'Titre mis à jour sans version explicite',
            },
          ],
        },
      );
      expect(patchedWithoutVersion.spec.useCases.single.version, '1.4.0');
      expect(patchedWithoutVersion.spec.sagas.single.version, '2.0.3');
    });
  });
}
