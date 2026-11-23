import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  final epoch = DateTime.utc(2026, 1, 1);

  SpecForgeProject buildProject() {
    final client = BusinessObjectSpec(
      id: 'obj_client',
      name: 'Client',
      technicalName: 'Client',
      description: 'Client acheteur',
      aggregateRoot: true,
      attributes: [
        BusinessAttribute(
          id: 'attr_cli_id',
          name: 'id',
          type: BusinessAttributeType.uuid,
          required: true,
          unique: true,
        ),
        BusinessAttribute(
          id: 'attr_cli_nom',
          name: 'raisonSociale',
          type: BusinessAttributeType.string,
          required: true,
        ),
      ],
    );
    final adresse = BusinessObjectSpec(
      id: 'obj_adresse',
      name: 'Adresse postale',
      technicalName: 'AdressePostale',
      description: 'Sous-objet valeur d’adresse',
      aggregateRoot: false,
      attributes: [
        BusinessAttribute(
          id: 'attr_adr_rue',
          name: 'rue',
          type: BusinessAttributeType.string,
          required: true,
        ),
        BusinessAttribute(
          id: 'attr_adr_ville',
          name: 'ville',
          type: BusinessAttributeType.string,
          required: true,
        ),
      ],
    );
    final commande = BusinessObjectSpec(
      id: 'obj_commande',
      name: 'Commande client',
      technicalName: 'CommandeClient',
      description: 'Commande enregistrée',
      aggregateRoot: true,
      attributes: [
        BusinessAttribute(
          id: 'attr_cmd_id',
          name: 'id',
          type: BusinessAttributeType.uuid,
          required: true,
          unique: true,
        ),
        BusinessAttribute(
          id: 'attr_cmd_adr',
          name: 'adresseLivraison',
          type: BusinessAttributeType.reference,
          referenceObjectId: 'obj_adresse',
          required: true,
        ),
      ],
      relations: const [
        BusinessRelation(
          id: 'rel_cmd_client',
          name: 'client',
          targetObjectId: 'obj_client',
          cardinality: BusinessRelationCardinality.oneToOne,
          required: true,
          description: 'Client donneur d’ordre',
        ),
      ],
    );

    return SpecForgeProject(
      id: 'proj_1',
      name: 'Portail B2B',
      initialIdea: 'Commandes B2B',
      createdAt: epoch,
      updatedAt: epoch,
      businessObjects: [client, adresse, commande],
    );
  }

  group('SpecDesignPromoter', () {
    test(
      'promeut vers différents domaines, recâble les références intra-domaine et convertit celles hors domaine en ID scalaire',
      () {
        final project = buildProject();
        final catalog = DomainCatalog(
          domains: const [
            FunctionalDomain(
              id: 'dom_crm',
              domainCode: 'crm',
              name: 'CRM',
            ),
            FunctionalDomain(
              id: 'dom_oms',
              domainCode: 'oms',
              name: 'Commandes',
            ),
          ],
        );

        final planned = <String, String?>{
          'obj_client': 'dom_crm',
          'obj_adresse': 'dom_oms',
          'obj_commande': 'dom_oms',
        };
        expect(
          SpecDesignPromoter.countExternalReferencesForObject(
            project: project,
            catalog: catalog,
            object: project.findBusinessObject('obj_commande')!,
            targetDomainId: 'dom_oms',
            plannedDomainByObjectId: planned,
          ),
          1,
        );

        final result = SpecDesignPromoter.promote(
          project: project,
          catalog: catalog,
          now: epoch,
          choices: [
            ObjectPromotionChoice(
              objectId: 'obj_client',
              domainId: 'dom_crm',
              contractType: SpecDesignPromoter.defaultContractTypeFor(
                project.findBusinessObject('obj_client')!,
              ),
            ),
            ObjectPromotionChoice(
              objectId: 'obj_adresse',
              domainId: 'dom_oms',
              contractType: SpecDesignPromoter.defaultContractTypeFor(
                project.findBusinessObject('obj_adresse')!,
              ),
            ),
            ObjectPromotionChoice(
              objectId: 'obj_commande',
              domainId: 'dom_oms',
              contractType: SpecDesignPromoter.defaultContractTypeFor(
                project.findBusinessObject('obj_commande')!,
              ),
            ),
          ],
        );

        expect(result.createdCount, 3);
        expect(result.updatedCount, 0);
        expect(result.skippedCount, 0);
        expect(result.updatedCatalog.auditLog, hasLength(2));

        final crmContracts = result.updatedCatalog.domains
            .firstWhere((d) => d.id == 'dom_crm')
            .contracts!;
        final clientEntry = SpecDesignPromoter.findExistingEntry(
          crmContracts,
          'Client',
        );
        expect(clientEntry, isNotNull);
        expect(clientEntry!.parent?.name, 'models');
        expect(clientEntry.type, 'model');
        expect(crmContracts.details[clientEntry.id]?.title, 'Client');
        expect(
          crmContracts.objectFor(clientEntry).attributes,
          hasLength(2),
        );

        final omsContracts = result.updatedCatalog.domains
            .firstWhere((d) => d.id == 'dom_oms')
            .contracts!;
        final adresseEntry = SpecDesignPromoter.findExistingEntry(
          omsContracts,
          'AdressePostale',
        )!;
        final commandeEntry = SpecDesignPromoter.findExistingEntry(
          omsContracts,
          'CommandeClient',
        )!;

        expect(adresseEntry.parent?.name, 'components');
        expect(adresseEntry.type, 'component');
        expect(commandeEntry.parent?.name, 'models');
        expect(commandeEntry.type, 'model');

        final commandeObj = omsContracts.objectFor(commandeEntry);
        expect(commandeObj.id, commandeEntry.id);
        expect(commandeObj.relations, isEmpty);

        // Référence intra-domaine (AdressePostale dans OMS) -> pointe sur adresseEntry.id
        final adrAttr = commandeObj.attributes.firstWhere(
          (a) => a.name == 'adresseLivraison',
        );
        expect(adrAttr.type, BusinessAttributeType.reference);
        expect(adrAttr.referenceObjectId, adresseEntry.id);

        // Relation hors domaine (Client dans CRM) -> convertie en attribut scalaire uuid documenté
        final clientAttr = commandeObj.attributes.firstWhere(
          (a) => a.name == 'client',
        );
        expect(clientAttr.type, BusinessAttributeType.uuid);
        expect(clientAttr.referenceObjectId, isEmpty);
        expect(clientAttr.required, isTrue);
        expect(clientAttr.description, contains('CRM'));
      },
    );

    test(
      'gère les conflits par objet : updateExisting préserve l’ID/chat/version, skipExisting ignore',
      () {
        final project = buildProject();
        var existingContracts = DomainContracts.parse(
          'models:\n  Client: model # commentaire conservé\n  CommandeClient: model\ncomponents:\n',
        );
        final prevClientEntry = SpecDesignPromoter.findExistingEntry(
          existingContracts,
          'Client',
        )!;
        final prevCmdEntry = SpecDesignPromoter.findExistingEntry(
          existingContracts,
          'CommandeClient',
        )!;
        existingContracts = existingContracts
            .edit(
              prevClientEntry,
              'model',
              ContractDetails(
                title: 'Ancien Client',
                version: '1.2.0',
                states: const {ContractStage.design: ContractStatus.done},
              ),
            )
            .withModel(
              prevClientEntry.id,
              chat: [
                SpecChatMessage(
                  id: 'msg_1',
                  isUser: true,
                  text: 'Ajoute le SIRET',
                  timestamp: epoch,
                ),
              ],
            )
            .withModel(
              prevCmdEntry.id,
              object: BusinessObjectSpec(
                id: prevCmdEntry.id,
                name: 'Commande existante',
                technicalName: 'CommandeClient',
                description: 'Ne doit pas bouger',
              ),
            );

        final catalog = DomainCatalog(
          domains: [
            FunctionalDomain(
              id: 'dom_crm',
              domainCode: 'crm',
              name: 'CRM',
              contracts: existingContracts,
            ),
          ],
        );

        final result = SpecDesignPromoter.promote(
          project: project,
          catalog: catalog,
          now: epoch,
          choices: const [
            ObjectPromotionChoice(
              objectId: 'obj_client',
              domainId: 'dom_crm',
              contractType: 'part',
              conflictResolution: PromotionConflictResolution.updateExisting,
            ),
            ObjectPromotionChoice(
              objectId: 'obj_commande',
              domainId: 'dom_crm',
              contractType: 'model',
              conflictResolution: PromotionConflictResolution.skipExisting,
            ),
          ],
        );

        expect(result.createdCount, 0);
        expect(result.updatedCount, 1);
        expect(result.skippedCount, 1);

        final updatedContracts = result.updatedCatalog.domains.single.contracts!;
        expect(updatedContracts.source, contains('# commentaire conservé'));

        // Client mis à jour : même ID, chat préservé, version 1.2.0 et état done préservés, type passé à part
        final nextClient = updatedContracts.entryById(prevClientEntry.id)!;
        expect(nextClient.type, 'part');
        expect(updatedContracts.details[prevClientEntry.id]?.version, '1.2.0');
        expect(
          updatedContracts.details[prevClientEntry.id]?.states[ContractStage.design],
          ContractStatus.done,
        );
        expect(updatedContracts.chats[prevClientEntry.id], hasLength(1));
        expect(
          updatedContracts.objectFor(nextClient).attributes.map((a) => a.name),
          containsAll(['id', 'raisonSociale']),
        );

        // CommandeClient ignorée : description d'origine intacte
        final nextCmd = updatedContracts.entryById(prevCmdEntry.id)!;
        expect(
          updatedContracts.objectFor(nextCmd).description,
          'Ne doit pas bouger',
        );
      },
    );

    test(
      'résout les références vers une entrée déjà présente dans le domaine et les sous-attributs imbriqués',
      () {
        final baseProject = buildProject();
        final ligne = BusinessObjectSpec(
          id: 'obj_facture',
          name: 'Facture',
          technicalName: 'Facture',
          aggregateRoot: true,
          attributes: [
            BusinessAttribute(
              id: 'attr_entete',
              name: 'entete',
              type: BusinessAttributeType.object,
              children: [
                BusinessAttribute(
                  id: 'attr_payeur',
                  name: 'payeurId',
                  type: BusinessAttributeType.reference,
                  referenceObjectId: 'obj_client',
                ),
                BusinessAttribute(
                  id: 'attr_transporteur',
                  name: 'transporteurId',
                  type: BusinessAttributeType.reference,
                  referenceObjectId: 'TransporteurExterne',
                ),
              ],
            ),
          ],
        );
        final project = baseProject.copyWith(
          businessObjects: [...baseProject.businessObjects, ligne],
        );

        // Client est déjà dans dom_crm avant cette promotion
        final preExistingCrm = DomainContracts.parse(
          'models:\n  Client: model\ncomponents:\n',
        );
        final preClientEntry = SpecDesignPromoter.findExistingEntry(
          preExistingCrm,
          'Client',
        )!;
        final catalog = DomainCatalog(
          domains: [
            FunctionalDomain(
              id: 'dom_crm',
              domainCode: 'crm',
              name: 'CRM',
              contracts: preExistingCrm,
            ),
          ],
        );

        final result = SpecDesignPromoter.promote(
          project: project,
          catalog: catalog,
          modelPreferences: const BusinessObjectModelPreferences(
            idStrategy: PrimaryIdStrategy.autoIncrementInt,
          ),
          now: epoch,
          choices: const [
            ObjectPromotionChoice(
              objectId: 'obj_facture',
              domainId: 'dom_crm',
              contractType: 'xresponsedto',
            ),
          ],
        );

        final crmContracts = result.updatedCatalog.domains.single.contracts!;
        final factureEntry = SpecDesignPromoter.findExistingEntry(
          crmContracts,
          'Facture',
        )!;
        expect(factureEntry.parent?.name, 'dto');
        expect(factureEntry.type, 'xresponsedto');

        final factureObj = crmContracts.objectFor(factureEntry);
        final children = factureObj.attributes.single.children;
        final payeur = children.firstWhere((c) => c.name == 'payeurId');
        expect(payeur.type, BusinessAttributeType.reference);
        expect(payeur.referenceObjectId, preClientEntry.id);

        final transporteur = children.firstWhere(
          (c) => c.name == 'transporteurId',
        );
        expect(transporteur.type, BusinessAttributeType.integer);
        expect(transporteur.referenceObjectId, isEmpty);
        expect(transporteur.description, contains('TransporteurExterne'));
      },
    );
  });
}
