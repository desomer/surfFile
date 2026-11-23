import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart'
    show VibeQuestioningLevel;
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('HexagonalDomainLayerSpec & DomainContracts', () {
    test('éligibilité limitée aux objets du domaine (model, part, component)', () {
      expect(HexagonalDomainLayerSpec.isEligibleType('model'), isTrue);
      expect(HexagonalDomainLayerSpec.isEligibleType('part'), isTrue);
      expect(HexagonalDomainLayerSpec.isEligibleType('component'), isTrue);
      expect(HexagonalDomainLayerSpec.isEligibleType('xresponsedto'), isFalse);
      expect(
        HexagonalDomainLayerSpec.isEligibleType('eventxpayloaddto'),
        isFalse,
      );
      expect(HexagonalDomainLayerSpec.isEligibleType('flatfile'), isFalse);
    });

    test(
      'sérialise les 7 onglets et préserve la couche Domain + chat lors des déplacements/renommages DSL',
      () {
        var doc = DomainContracts.parse(
          'models:\n  Commande: model\ncomponents:\n',
        );
        final entry = doc.groups.first.children.single;
        final layer = HexagonalDomainLayerSpec(
          invariants: [
            DomainInvariantSpec(
              id: 'inv_1',
              code: 'INV-01',
              title: 'Total positif',
              expression: 'totalHt >= 0',
              relatedAttributes: const ['totalHt'],
              violationError: 'MontantNegatif',
            ),
          ],
          stateChanges: [
            DomainStateChangeSpec(
              id: 'cmd_1',
              name: 'confirmer',
              parameters: const ['dateConfirmation: datetime'],
              preconditions: const ['statut == BROUILLON'],
              mutations: const ['statut = CONFIRMEE'],
              fromStates: const ['BROUILLON'],
              toState: 'CONFIRMEE',
              emittedEvents: const ['CommandeConfirmee'],
            ),
          ],
          queries: [
            DomainQuerySpec(
              id: 'qry_1',
              name: 'estAnnulable',
              returnType: 'bool',
              formula: 'statut == BROUILLON',
            ),
          ],
          policyServices: [
            DomainPolicyServiceSpec(
              id: 'pol_1',
              name: 'PolitiqueRemise',
              operation: 'calculerRemise(cmd) -> number',
              collaborators: const ['Client'],
              rules: const ['Max 15%'],
            ),
          ],
          factories: [
            DomainFactorySpec(
              id: 'fac_1',
              name: 'creerBrouillon',
              parameters: const ['clientId: uuid'],
              initialState: 'BROUILLON',
              enforcedInvariants: const ['INV-01'],
            ),
          ],
          domainEvents: [
            DomainEventSpec(
              id: 'evt_1',
              name: 'CommandeConfirmee',
              trigger: 'confirmer',
              payloadFields: const ['commandeId: uuid'],
            ),
          ],
          persistencePolicy: DomainPersistencePolicySpec(
            repositoryPortName: 'CommandeRepository',
            aggregateBoundary: 'Commande + lignes',
            concurrencyStrategy: DomainConcurrencyStrategy.optimisticVersion,
            deletionStrategy: DomainDeletionStrategy.immutableArchive,
            portMethods: const [
              DomainRepositoryMethodSpec(
                id: 'repm_1',
                name: 'findById',
                signature: '(id: uuid) -> Commande?',
              ),
            ],
          ),
        );

        doc = doc.withDomainLayer(
          entry.id,
          layer: layer,
          chat: [
            SpecChatMessage(
              id: 'msg_dl_1',
              isUser: true,
              text: 'Génère la couche domain',
            ),
          ],
        );

        // Déplacement dans une autre rubrique et renommage + aller-retour JSON
        final moved = doc.patch(
          'models:\ncomponents:\n  CommandeClient: component\n',
        );
        final restored = DomainContracts.fromJson(
          jsonDecode(jsonEncode(moved.toJson())),
        );

        expect(restored.domainLayerFor(entry), layer);
        expect(restored.domainLayerChats[entry.id], hasLength(1));
        expect(restored.domainLayerFor(entry).totalItemsCount, 7);
      },
    );
  });

  group('DomainLayerAiAgent', () {
    test('applyPatch fusionne ajouts, mises à jour par clé naturelle et suppressions sur les 7 onglets', () {
      final first = DomainLayerAiAgent.applyPatch(
        HexagonalDomainLayerSpec.empty,
        {
          'invariants': [
            {
              'code': 'INV-01',
              'title': 'Montant >= 0',
              'expression': 'montant >= 0',
            },
            {
              'code': 'INV-02',
              'title': 'Devise obligatoire',
            },
          ],
          'stateChanges': [
            {
              'name': 'confirmer',
              'toState': 'CONFIRMEE',
              'emittedEvents': ['CommandeConfirmee'],
            },
          ],
          'queries': [
            {'name': 'estPayee', 'returnType': 'bool'},
          ],
          'policyServices': [
            {'name': 'TarificationPolicy'},
          ],
          'factories': [
            {'name': 'creer', 'initialState': 'BROUILLON'},
          ],
          'domainEvents': [
            {'name': 'CommandeConfirmee', 'trigger': 'confirmer'},
          ],
          'persistencePolicy': {
            'repositoryPortName': 'CommandeRepository',
            'concurrencyStrategy': 'pessimisticLock',
            'portMethods': [
              {'name': 'save', 'signature': '(c: Commande) -> void'},
            ],
          },
        },
      );

      expect(first.layer.invariants, hasLength(2));
      expect(first.layer.stateChanges.single.name, 'confirmer');
      expect(first.layer.queries.single.name, 'estPayee');
      expect(first.layer.policyServices.single.name, 'TarificationPolicy');
      expect(first.layer.factories.single.name, 'creer');
      expect(first.layer.domainEvents.single.name, 'CommandeConfirmee');
      expect(
        first.layer.persistencePolicy.concurrencyStrategy,
        DomainConcurrencyStrategy.pessimisticLock,
      );
      expect(first.layer.persistencePolicy.portMethods, hasLength(1));
      expect(first.summary, contains('+2 invariant(s)'));

      final inv01Id = first.layer.invariants.first.id;
      final second = DomainLayerAiAgent.applyPatch(first.layer, {
        'invariants': [
          {
            'code': 'INV-01',
            'title': 'Montant strictement positif',
            'expression': 'montant > 0',
          },
        ],
        'removeInvariants': ['INV-02'],
        'persistencePolicy': {
          'deletionStrategy': 'immutableArchive',
        },
      });

      expect(second.layer.invariants, hasLength(1));
      expect(second.layer.invariants.single.id, inv01Id);
      expect(second.layer.invariants.single.expression, 'montant > 0');
      // repositoryPortName et portMethods précédents sont conservés
      expect(
        second.layer.persistencePolicy.repositoryPortName,
        'CommandeRepository',
      );
      expect(
        second.layer.persistencePolicy.deletionStrategy,
        DomainDeletionStrategy.immutableArchive,
      );
      expect(second.layer.persistencePolicy.portMethods, hasLength(1));
    });

    test('buildTurnPrompt injecte les attributs du modèle et l’onglet actif', () {
      var contracts = DomainContracts.parse(
        'models:\n  Commande: model\nmessage:\n  CommandeConfirmeePayload: eventxpayloaddto\n',
      );
      final cmdEntry = contracts.groups.first.children.single;
      contracts = contracts.withModel(
        cmdEntry.id,
        object: BusinessObjectSpec(
          id: cmdEntry.id,
          name: 'Commande',
          technicalName: 'Commande',
          attributes: [
            BusinessAttribute(
              id: 'attr_1',
              name: 'montantHt',
              type: BusinessAttributeType.number,
              required: true,
            ),
          ],
        ),
      );

      final prompt = DomainLayerAiAgent.buildTurnPrompt(
        domainName: 'Ventes',
        contracts: contracts,
        entry: cmdEntry,
        activeTab: DomainLayerTab.stateChanging,
        history: const [],
        userInput: 'Propose la commande confirmer',
        modelPreferences: BusinessObjectModelPreferences.defaults,
        questioningLevel: VibeQuestioningLevel.balanced,
        afterAskUserReply: false,
      );

      expect(prompt, contains('State changing'));
      expect(prompt, contains('montantHt'));
      expect(prompt, contains('CommandeConfirmeePayload'));
    });
  });
}
