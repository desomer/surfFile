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

    test(
      'enregistre SpecOriginBaseline avec ruleFingerprints et exécute smartMerge par défaut en préservant les ValueObjects et champs Design',
      () {
        final t1 = DateTime.utc(2026, 2, 1);
        final t2 = DateTime.utc(2026, 2, 10);
        final emailVo = ValueObjectPresets.standardPresets.firstWhere(
          (v) => v.technicalName == 'EmailAddress',
        );
        final moneyVo = ValueObjectPresets.standardPresets.firstWhere(
          (v) => v.technicalName == 'Money',
        );

        final clientV1 = BusinessObjectSpec(
          id: 'obj_client',
          name: 'Client',
          technicalName: 'Client',
          description: 'Client B2B v1',
          attributes: [
            BusinessAttribute(
              id: 'attr_id',
              name: 'id',
              type: BusinessAttributeType.uuid,
              required: true,
              unique: true,
            ),
            BusinessAttribute(
              id: 'attr_email',
              name: 'emailContact',
              type: BusinessAttributeType.email,
              required: false,
              description: 'Email initial',
            ),
            BusinessAttribute(
              id: 'attr_plafond',
              name: 'plafondEncours',
              type: BusinessAttributeType.number,
              required: true,
            ),
            BusinessAttribute(
              id: 'attr_fax',
              name: 'faxObsol',
              type: BusinessAttributeType.string,
            ),
          ],
        );
        final rgPlafond = BusinessRuleSpec(
          id: 'rule_1',
          code: 'RG-001',
          title: 'Plafond positif',
          targetObjectIds: const ['obj_client'],
          condition: 'plafondEncours >= 0',
          effect: 'Autoriser la création',
        );

        final projectV1 = SpecForgeProject(
          id: 'proj_b2b',
          name: 'Portail B2B',
          initialIdea: 'Portail commandes',
          createdAt: t1,
          updatedAt: t1,
          businessObjects: [clientV1],
          businessRules: [rgPlafond],
        );

        final initialCatalog = DomainCatalog(
          sharedValueObjects: [emailVo, moneyVo],
          domains: const [
            FunctionalDomain(
              id: 'dom_crm',
              domainCode: 'crm',
              name: 'CRM',
            ),
          ],
        );

        // 1re promotion : création initiale et capture de SpecOriginBaseline
        final firstPromo = SpecDesignPromoter.promote(
          project: projectV1,
          catalog: initialCatalog,
          now: t1,
          choices: const [
            ObjectPromotionChoice(
              objectId: 'obj_client',
              domainId: 'dom_crm',
              contractType: 'model',
            ),
          ],
        );

        var crmDomain = firstPromo.updatedCatalog.domains.single;
        var crmContracts = crmDomain.contracts!;
        final clientEntry = SpecDesignPromoter.findExistingEntry(
          crmContracts,
          'Client',
        )!;
        final originV1 = crmContracts.details[clientEntry.id]?.specOrigin;
        expect(originV1, isNotNull);
        expect(originV1!.projectId, 'proj_b2b');
        expect(originV1.specObjectId, 'obj_client');
        expect(originV1.promotedAt, t1);
        expect(originV1.baseSpecObject, clientV1);
        expect(originV1.ruleFingerprints, contains('RG-001'));

        // Enrichissement côté Design : ValueObjects (EmailAddress, Money), index DB, et champ technique tenantId
        var enrichedDesignObj = crmContracts.objectFor(clientEntry);
        enrichedDesignObj = ValueObjectPrimitiveDetector.replaceAttributeAtPath(
          enrichedDesignObj,
          const ['attr_email'],
          valueObjectId: emailVo.id,
        );
        enrichedDesignObj = ValueObjectPrimitiveDetector.replaceAttributeAtPath(
          enrichedDesignObj,
          const ['attr_plafond'],
          valueObjectId: moneyVo.id,
        );
        enrichedDesignObj = enrichedDesignObj.copyWith(
          attributes: [
            for (final a in enrichedDesignObj.attributes)
              if (a.id == 'attr_email')
                a.copyWith(
                  schemaConstraints: JsonSchemaConstraints(
                    extraKeywords: const {
                      'x-database-index': true,
                      'x-searchable': true,
                    },
                  ),
                )
              else
                a,
            BusinessAttribute(
              id: 'attr_design_tenant',
              name: 'tenantId',
              type: BusinessAttributeType.uuid,
              required: true,
              description: 'Clé de partitionnement multi-tenant Design',
            ),
          ],
        );
        crmContracts = crmContracts.withModel(
          clientEntry.id,
          object: enrichedDesignObj,
        );
        final enrichedCatalog = firstPromo.updatedCatalog.copyWith(
          domains: [crmDomain.copyWith(contracts: crmContracts)],
        );

        // Évolution Spec v2 :
        // - emailContact devient obligatoire + nouvelle description
        // - faxObsol est supprimé
        // - siret (optionnel) est ajouté
        final clientV2 = clientV1.copyWith(
          description: 'Client B2B v2',
          attributes: [
            clientV1.attributes[0],
            clientV1.attributes[1].copyWith(
              required: true,
              description: 'Email de facturation obligatoire',
            ),
            clientV1.attributes[2],
            BusinessAttribute(
              id: 'attr_siret',
              name: 'siret',
              type: BusinessAttributeType.string,
              required: false,
              schemaConstraints: JsonSchemaConstraints(
                minLength: 14,
                maxLength: 14,
              ),
            ),
          ],
        );
        final projectV2 = projectV1.copyWith(businessObjects: [clientV2]);

        // Aperçu avant exécution via previewPromotion
        final previews = SpecDesignPromoter.previewPromotion(
          project: projectV2,
          catalog: enrichedCatalog,
          choices: const [
            ObjectPromotionChoice(
              objectId: 'obj_client',
              domainId: 'dom_crm',
              contractType: 'model',
            ),
          ],
        );
        expect(previews, hasLength(1));
        final preview = previews.single;
        expect(preview.isNewEntry, isFalse);
        expect(preview.existingEntryId, clientEntry.id);
        // Suppression de faxObsol + passage de emailContact à required => bump majeur 1.0.0
        expect(preview.suggestedVersion, '1.0.0');
        expect(preview.mergeResult, isNotNull);
        expect(preview.mergeResult!.addedCount, 1);
        expect(preview.mergeResult!.removedCount, 1);
        expect(
          preview.mergeResult!.preservedValueObjectIds,
          containsAll([emailVo.id, moneyVo.id]),
        );

        // 2de promotion en mode smartMerge (par défaut) avec autoBumpVersion: true
        final secondPromo = SpecDesignPromoter.promote(
          project: projectV2,
          catalog: enrichedCatalog,
          now: t2,
          autoBumpVersion: true,
          choices: const [
            ObjectPromotionChoice(
              objectId: 'obj_client',
              domainId: 'dom_crm',
              contractType: 'model',
            ),
          ],
        );

        expect(secondPromo.updatedCount, 1);
        expect(secondPromo.mergedCount, 1);
        expect(secondPromo.preservedValueObjectsCount, 2);
        expect(
          secondPromo.domainSummaries.single.mergedEntryIds,
          [clientEntry.id],
        );

        final mergedContracts =
            secondPromo.updatedCatalog.domains.single.contracts!;
        final mergedDetails = mergedContracts.details[clientEntry.id]!;
        expect(mergedDetails.version, '1.0.0');
        expect(mergedDetails.specOrigin?.baseSpecObject, clientV2);
        expect(mergedDetails.specOrigin?.promotedAt, t2);

        final mergedObj = mergedContracts.objectFor(clientEntry);
        final byName = {for (final a in mergedObj.attributes) a.name: a};

        // faxObsol retiré, siret ajouté, tenantId conservé
        expect(byName.containsKey('faxObsol'), isFalse);
        expect(byName.containsKey('siret'), isTrue);
        expect(byName.containsKey('tenantId'), isTrue);

        // EmailAddress VO préservé + métadonnées Spec mises à jour + enrichissements x-* préservés
        final emailAttr = byName['emailContact']!;
        expect(emailAttr.type, BusinessAttributeType.valueObject);
        expect(emailAttr.valueObjectId, emailVo.id);
        expect(emailAttr.required, isTrue);
        expect(emailAttr.description, 'Email de facturation obligatoire');
        expect(emailAttr.schemaConstraints.xDatabaseIndex, isTrue);
        expect(emailAttr.schemaConstraints.xSearchable, isTrue);

        // Money VO composite préservé
        final plafondAttr = byName['plafondEncours']!;
        expect(plafondAttr.type, BusinessAttributeType.valueObject);
        expect(plafondAttr.valueObjectId, moneyVo.id);
      },
    );

    test(
      'suggestNextSemVer distingue patch, minor et major selon la nature des changements',
      () {
        final baseObj = BusinessObjectSpec(
          id: 'entry_1',
          name: 'Produit',
          technicalName: 'Produit',
          description: 'Desc v1',
          attributes: [
            BusinessAttribute(
              id: 'a1',
              name: 'code',
              type: BusinessAttributeType.string,
              required: true,
            ),
          ],
        );

        // Aucun changement -> même version
        final noChange = SpecDesignMergeEngine.merge(
          baseSpec: baseObj,
          nextSpecResolved: baseObj,
          currentDesign: baseObj,
        );
        expect(SpecDesignPromoter.suggestNextSemVer('1.2.3', noChange), '1.2.3');

        // Changement de description uniquement -> patch
        final descChangeObj = baseObj.copyWith(description: 'Desc v2 enrichie');
        final patchMerge = SpecDesignMergeEngine.merge(
          baseSpec: baseObj,
          nextSpecResolved: descChangeObj,
          currentDesign: baseObj,
        );
        expect(
          SpecDesignPromoter.suggestNextSemVer('1.2.3', patchMerge),
          '1.2.4',
        );

        // Ajout d'un attribut optionnel -> minor
        final minorObj = baseObj.copyWith(
          attributes: [
            ...baseObj.attributes,
            BusinessAttribute(
              id: 'a2',
              name: 'marque',
              type: BusinessAttributeType.string,
              required: false,
            ),
          ],
        );
        final minorMerge = SpecDesignMergeEngine.merge(
          baseSpec: baseObj,
          nextSpecResolved: minorObj,
          currentDesign: baseObj,
        );
        expect(
          SpecDesignPromoter.suggestNextSemVer('1.2.3', minorMerge),
          '1.3.0',
        );

        // Ajout d'un attribut obligatoire -> major
        final majorObj = baseObj.copyWith(
          attributes: [
            ...baseObj.attributes,
            BusinessAttribute(
              id: 'a3',
              name: 'prixHt',
              type: BusinessAttributeType.number,
              required: true,
            ),
          ],
        );
        final majorMerge = SpecDesignMergeEngine.merge(
          baseSpec: baseObj,
          nextSpecResolved: majorObj,
          currentDesign: baseObj,
        );
        expect(
          SpecDesignPromoter.suggestNextSemVer('1.2.3', majorMerge),
          '2.0.0',
        );
      },
    );
  });
}
