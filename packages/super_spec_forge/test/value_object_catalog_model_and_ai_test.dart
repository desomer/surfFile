import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('ValueObjectSpec & DomainCatalog double portée', () {
    test('sérialisation JSON aller-retour scalaire et composite + presets valides', () {
      for (final preset in ValueObjectPresets.standardPresets) {
        preset.validate();
        final roundtrip = ValueObjectSpec.fromJson(preset.toJson());
        expect(roundtrip, equals(preset));
      }
      ValueObjectSpec.validateNoCycles(ValueObjectPresets.standardPresets);
    });

    test('détecte les cycles entre Value Objects composites', () {
      final voA = ValueObjectSpec(
        id: 'vo_a',
        technicalName: 'AlphaRange',
        name: 'Alpha',
        kind: ValueObjectKind.composite,
        fields: [
          BusinessAttribute(
            id: 'f1',
            name: 'beta',
            type: BusinessAttributeType.valueObject,
            valueObjectId: 'vo_b',
          ),
        ],
      );
      final voB = ValueObjectSpec(
        id: 'vo_b',
        technicalName: 'BetaRange',
        name: 'Beta',
        kind: ValueObjectKind.composite,
        fields: [
          BusinessAttribute(
            id: 'f2',
            name: 'alpha',
            type: BusinessAttributeType.valueObject,
            valueObjectId: 'vo_a',
          ),
        ],
      );
      expect(
        () => ValueObjectSpec.validateNoCycles([voA, voB]),
        throwsFormatException,
      );
    });

    test('priorité Domaine sur Shared Kernel et persistance DomainCatalogStore', () async {
      final sharedEmail = ValueObjectPresets.standardPresets.firstWhere(
        (v) => v.technicalName == 'EmailAddress',
      );
      final sharedMoney = ValueObjectPresets.standardPresets.firstWhere(
        (v) => v.technicalName == 'Money',
      );
      final domainEmail = sharedEmail.copyWith(
        id: 'vo_dom_email',
        name: 'Email professionnel facturation',
      );

      final catalog = DomainCatalog(
        domains: [
          FunctionalDomain(
            id: 'dom_billing',
            domainCode: 'billing',
            name: 'Facturation',
            valueObjects: [domainEmail],
          ),
        ],
        sharedValueObjects: [sharedEmail, sharedMoney],
      );
      catalog.validate();

      final resolved = catalog.resolvedValueObjectsForDomain('dom_billing');
      expect(resolved.length, 2);
      final effectiveEmail = catalog.findValueObject(
        'EmailAddress',
        domainId: 'dom_billing',
      );
      expect(effectiveEmail, isNotNull);
      expect(effectiveEmail!.scope, ValueObjectScope.domain);
      expect(effectiveEmail.spec.id, 'vo_dom_email');

      final effectiveMoney = catalog.findValueObject(
        'Money',
        domainId: 'dom_billing',
      );
      expect(effectiveMoney, isNotNull);
      expect(effectiveMoney!.scope, ValueObjectScope.shared);

      // Aller-retour sur disque
      final tempDir = await Directory.systemTemp.createTemp('vo_catalog_test_');
      try {
        final store = DomainCatalogStore(tempDir);
        await store.save(catalog);
        final reloaded = await store.load();
        expect(reloaded.sharedValueObjects.length, 2);
        expect(reloaded.domains.single.valueObjects.single, equals(domainEmail));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('DSL YAML Light, JSON Schema Draft 2020-12 & Primitive Obsession', () {
    final emailVo = ValueObjectPresets.standardPresets.firstWhere(
      (v) => v.technicalName == 'EmailAddress',
    );
    final moneyVo = ValueObjectPresets.standardPresets.firstWhere(
      (v) => v.technicalName == 'Money',
    );
    final allVos = [emailVo, moneyVo];

    test('aller-retour YAML Light (montant: Money!, emails: EmailAddress[]?) et JSON Schema', () {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      final invoice = BusinessObjectSpec(
        id: 'ent_invoice',
        name: 'Facture',
        technicalName: 'Invoice',
        attributes: [
          BusinessAttribute(
            id: 'a1',
            name: 'totalAmount',
            type: BusinessAttributeType.valueObject,
            valueObjectId: moneyVo.id,
            required: true,
          ),
          BusinessAttribute(
            id: 'a2',
            name: 'recipientEmails',
            type: BusinessAttributeType.valueObject,
            valueObjectId: emailVo.id,
            isArray: true,
            nullable: true,
          ),
        ],
      );
      final project = SpecForgeProject(
        id: 'p1',
        name: 'Facturation',
        initialIdea: '',
        createdAt: epoch,
        updatedAt: epoch,
        businessObjects: [invoice],
      );

      final yaml = SpecSchemaDslBridge.toSingleObjectYamlLight(
        project,
        invoice,
        valueObjects: allVos,
      );
      expect(yaml, contains('totalAmount: Money!'));
      expect(yaml, contains('recipientEmails: EmailAddress[]?'));

      final reparsed = SpecSchemaDslBridge.applySingleObjectYamlSource(
        yaml,
        current: invoice.copyWith(attributes: const []),
        referenceTargets: const {},
        valueObjects: allVos,
      );
      expect(reparsed.attributes.length, 2);
      expect(reparsed.attributes[0].type, BusinessAttributeType.valueObject);
      expect(reparsed.attributes[0].valueObjectId, moneyVo.id);
      expect(reparsed.attributes[0].required, isTrue);
      expect(reparsed.attributes[1].type, BusinessAttributeType.valueObject);
      expect(reparsed.attributes[1].valueObjectId, emailVo.id);
      expect(reparsed.attributes[1].isArray, isTrue);
      expect(reparsed.attributes[1].nullable, isTrue);

      final schema = SpecSuperDesignerExporter.objectToJsonSchema(
        project,
        reparsed,
        valueObjects: allVos,
        valueObjectScopes: {
          moneyVo.id: ValueObjectScope.shared,
          emailVo.id: ValueObjectScope.shared,
        },
      );
      final props = schema['properties'] as Map<String, Object?>;
      final totalSchema = props['totalAmount'] as Map<String, Object?>;
      expect(totalSchema['type'], 'object');
      expect(totalSchema['x-value-object'], 'Money');
      expect(totalSchema['x-value-object-scope'], 'shared');
      expect(totalSchema['x-cross-field-rules'], isNotEmpty);

      final emailsSchema = props['recipientEmails'] as Map<String, Object?>;
      expect(emailsSchema['type'], 'array');
      final itemSchema = emailsSchema['items'] as Map<String, Object?>;
      expect(itemSchema['x-value-object'], 'EmailAddress');
      expect(itemSchema['x-normalization'], contains('lowercase'));
    });

    test('détecte la Primitive Obsession, remplace un attribut et compte les usages', () {
      var contracts = DomainContracts.parse('models:\n  Customer: model\n');
      final customerNode = contracts.groups.first.children.single;
      final customerObj = contracts.objectFor(customerNode).copyWith(
        attributes: [
          BusinessAttribute(
            id: 'a_email',
            name: 'contactEmail',
            type: BusinessAttributeType.email,
            required: true,
          ),
          BusinessAttribute(
            id: 'a_iban',
            name: 'bankIban',
            type: BusinessAttributeType.string,
          ),
        ],
      );
      contracts = contracts.withModel(customerNode.id, object: customerObj);

      final catalog = DomainCatalog(
        domains: [
          FunctionalDomain(
            id: 'dom_crm',
            domainCode: 'crm',
            name: 'CRM',
            contracts: contracts,
          ),
        ],
        sharedValueObjects: [emailVo],
      );

      final suggestions = ValueObjectPrimitiveDetector.detectForDomain(
        catalog,
        'dom_crm',
      );
      expect(suggestions.length, 2);
      final emailSuggestion = suggestions.firstWhere(
        (s) => s.attribute.id == 'a_email',
      );
      expect(
        emailSuggestion.matchKind,
        PrimitiveObsessionMatchKind.existingCatalogVo,
      );
      expect(emailSuggestion.matchedVo?.spec.id, emailVo.id);

      final ibanSuggestion = suggestions.firstWhere(
        (s) => s.attribute.id == 'a_iban',
      );
      expect(
        ibanSuggestion.matchKind,
        PrimitiveObsessionMatchKind.newValueObjectCandidate,
      );
      expect(ibanSuggestion.proposedSpec.technicalName, 'Iban');

      final replaced = ValueObjectPrimitiveDetector.replaceAttributeAtPath(
        customerObj,
        ['a_email'],
        valueObjectId: emailVo.id,
      );
      expect(replaced.attributes.first.type, BusinessAttributeType.valueObject);
      expect(replaced.attributes.first.valueObjectId, emailVo.id);

      final updatedCatalog = catalog.copyWith(
        domains: [
          catalog.domains.single.copyWith(
            contracts: contracts.withModel(customerNode.id, object: replaced),
          ),
        ],
      );
      final usages = ValueObjectPrimitiveDetector.findUsages(
        updatedCatalog,
        emailVo,
        scope: ValueObjectScope.shared,
      );
      expect(usages.length, 1);
      expect(usages.single.entryName, 'Customer');
      expect(usages.single.attributeName, 'contactEmail');
    });
  });

  group('Agents IA & Injection Prompts Build', () {
    test('ValueObjectsAiAgent applique un patch scalaire/composite et DomainModelAiAgent résout les VOs', () {
      var contracts = DomainContracts.parse('models:\n  Order: model\n');
      final orderNode = contracts.groups.first.children.single;
      final catalog = DomainCatalog(
        domains: [
          FunctionalDomain(
            id: 'dom_sales',
            domainCode: 'sales',
            name: 'Ventes',
            contracts: contracts,
          ),
        ],
      );

      final voPatch = ValueObjectsAiAgent.applyPatch(
        catalog,
        scope: ValueObjectScope.domain,
        domainId: 'dom_sales',
        patch: {
          'upsertValueObjects': [
            {
              'technicalName': 'OrderNumber',
              'name': 'Numéro de commande',
              'kind': 'scalar',
              'primitiveType': 'string',
              'schemaConstraints': {'pattern': r'^CMD-\d{6}$'},
              'normalizationRules': ['trim', 'uppercase'],
              'examples': [
                {'value': 'CMD-000042', 'isValid': true, 'reason': 'Valide'},
                {'value': '42', 'isValid': false, 'reason': 'Préfixe manquant'},
              ],
            },
          ],
        },
      );
      expect(voPatch.addedCount, 1);
      final orderNumberVo = voPatch.catalog.domains.single.valueObjects.single;
      expect(orderNumberVo.technicalName, 'OrderNumber');

      final modelApplied = DomainModelAiAgent.applyPatch(
        contracts.objectFor(orderNode),
        {
          'attributes': [
            {
              'name': 'number',
              'type': 'valueObject',
              'valueObjectId': 'OrderNumber',
              'required': true,
            },
          ],
        },
        referenceTargets: const {},
        valueObjects: voPatch.catalog.valueObjectsForDomain('dom_sales'),
      );
      expect(
        modelApplied.object.attributes.single.type,
        BusinessAttributeType.valueObject,
      );
      expect(
        modelApplied.object.attributes.single.valueObjectId,
        orderNumberVo.id,
      );

      expect(
        () => DomainModelAiAgent.applyPatch(
          contracts.objectFor(orderNode),
          {
            'attributes': [
              {
                'name': 'unknownVoField',
                'type': 'valueObject',
                'valueObjectId': 'DoesNotExist',
              },
            ],
          },
          referenceTargets: const {},
          valueObjects: voPatch.catalog.valueObjectsForDomain('dom_sales'),
        ),
        throwsFormatException,
      );
    });

    test('BuildHexaPromptGenerator injecte les VOs référencés uniquement sur les modèles qui les utilisent', () {
      final moneyVo = ValueObjectPresets.standardPresets.firstWhere(
        (v) => v.technicalName == 'Money',
      );
      var contracts = DomainContracts.parse(
        'models:\n  Invoice: model\n  AuditNote: model\n',
      );
      final invoiceNode = contracts.groups.first.children[0];
      final noteNode = contracts.groups.first.children[1];
      contracts = contracts.withModel(
        invoiceNode.id,
        object: contracts.objectFor(invoiceNode).copyWith(
          attributes: [
            BusinessAttribute(
              id: 'a_tot',
              name: 'total',
              type: BusinessAttributeType.valueObject,
              valueObjectId: moneyVo.id,
              required: true,
            ),
          ],
        ),
      );
      contracts = contracts.withModel(
        noteNode.id,
        object: contracts.objectFor(noteNode).copyWith(
          attributes: [
            BusinessAttribute(
              id: 'a_txt',
              name: 'message',
              type: BusinessAttributeType.string,
            ),
          ],
        ),
      );

      final domain = FunctionalDomain(
        id: 'dom_billing',
        domainCode: 'billing',
        name: 'Facturation',
        contracts: contracts,
      );
      final catalog = DomainCatalog(
        domains: [domain],
        sharedValueObjects: [moneyVo],
      );

      final domainItems = BuildDomainDesignItems.fromDomain(domain);
      // Pas d'item Build autonome pour les Value Objects : uniquement les 2 modèles.
      expect(domainItems.models.length, 2);

      final groups = BuildHexaPromptGenerator.generateGroups(
        domain: domain,
        selectedItems: domainItems.models,
        catalog: catalog,
        includeDomainAdapters: false,
      );
      expect(groups.length, 2);

      final invoicePrompts = groups[0].prompts;
      final implPrompt = invoicePrompts
          .firstWhere(
            (p) =>
                p.section == BuildTechStackSection.domain &&
                p.role == BuildHexaPromptRole.implementation,
          )
          .promptMarkdown;
      final testPrompt = invoicePrompts
          .firstWhere(
            (p) =>
                p.section == BuildTechStackSection.domain &&
                p.role == BuildHexaPromptRole.unitTest,
          )
          .promptMarkdown;
      final persistencePrompt = invoicePrompts
          .firstWhere(
            (p) =>
                p.section == BuildTechStackSection.persistence &&
                p.role == BuildHexaPromptRole.implementation,
          )
          .promptMarkdown;
      final persistenceTestPrompt = invoicePrompts
          .firstWhere(
            (p) =>
                p.section == BuildTechStackSection.persistence &&
                p.role == BuildHexaPromptRole.unitTest,
          )
          .promptMarkdown;

      expect(implPrompt, contains('Value Objects Référencés'));
      expect(implPrompt, contains('`Money`'));
      expect(implPrompt, contains('"x-value-object": "Money"'));

      expect(testPrompt, contains('Tests Unitaires des Value Objects Référencés'));
      expect(testPrompt, contains('Montant négatif interdit'));

      expect(persistencePrompt, contains('Mapping Persistance ↔ Value Objects'));
      expect(persistencePrompt, contains('`Money`'));

      expect(persistenceTestPrompt, contains('Cas de Mapping Value Objects à Tester'));
      expect(persistenceTestPrompt, contains('`Money`'));

      // Le modèle sans Value Object ne reçoit pas de section VO parasite.
      final noteImplPrompt = groups[1].prompts.first.promptMarkdown;
      expect(noteImplPrompt, isNot(contains('Value Objects Référencés')));
    });
  });
}
