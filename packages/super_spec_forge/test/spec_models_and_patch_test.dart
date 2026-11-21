import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('SpecForgeProject & modèles métier', () {
    test('round-trip JSON complet et validation', () {
      final base = SpecForgeProject.fromIdea(
        idea: 'Gestion de flotte automobile d’entreprise',
        name: 'FlotteAuto',
      );
      final enriched = base.copyWith(
        lexicon: SpecLexicon(
          terms: [
            LexiconTerm(
              id: 'term_flotte',
              term: 'Véhicule',
              definition: 'Bien roulant immatriculé affecté à un service.',
              synonyms: const ['Voiture', 'Utilitaire'],
              domain: 'Parc auto',
            ),
          ],
          conventions: const ['Kilométrage exprimé en km'],
        ),
        vision: base.vision.copyWith(
          problemStatement: 'Manque de visibilité sur les entretiens',
          objectives: const ['Réduire les pannes de 30%'],
          personas: [
            SpecPersona(
              id: 'persona_gestionnaire',
              name: 'Gestionnaire de flotte',
              role: 'Planifie les entretiens',
              goals: const ['Suivre les échéances'],
            ),
          ],
        ),
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_vehicule',
            name: 'Véhicule',
            technicalName: 'Vehicule',
            attributes: [
              BusinessAttribute(
                id: 'attr_immat',
                name: 'immatriculation',
                type: BusinessAttributeType.string,
                required: true,
                unique: true,
              ),
            ],
            lifecycleStates: const [
              LifecycleState(name: 'actif', isInitial: true),
              LifecycleState(name: 'reforme', isTerminal: true),
            ],
          ),
        ],
        businessRules: [
          BusinessRuleSpec(
            id: 'rule_rg_001',
            code: 'RG-001',
            title: 'Alerte entretien 15 000 km',
            category: BusinessRuleCategory.trigger,
            targetObjectIds: const ['obj_vehicule'],
            trigger: 'Mise à jour kilométrage',
            condition: 'kmDepuisEntretien >= 15000',
            effect: 'Créer une alerte entretien',
          ),
        ],
      );

      final decoded = SpecForgeProject.fromJson(enriched.toJson());
      expect(decoded, equals(enriched));
      expect(decoded.businessObjects.single.technicalName, 'Vehicule');
      expect(decoded.businessRules.single.code, 'RG-001');
    });

    test('SpecChatMessage sérialise et restaure les pièces jointes texte et image', () {
      final msg = SpecChatMessage(
        id: 'm1',
        isUser: true,
        text: 'Voici le cahier initial',
        attachments: [
          VibeChatAttachment.text(
            name: 'notes.md',
            content: '# Idée\nGestion de stock',
          ),
          VibeChatAttachment.image(
            name: 'maquette.png',
            bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]),
          ),
        ],
        toolTraces: [
          VibeToolTrace(
            name: 'run_coherence_audit',
            arguments: const <String, Object?>{},
            summary: '0 point(s)',
          ),
        ],
      );

      final decoded = SpecChatMessage.fromJson(msg.toJson());
      expect(decoded, equals(msg));
      expect(decoded.attachments.length, 2);
      expect(decoded.toolTraces.single.name, 'run_coherence_audit');
      expect(decoded.attachments[0].textContent, '# Idée\nGestion de stock');
      expect(decoded.attachments[1].isImage, isTrue);
      expect(decoded.toConversationEntry(), contains('notes.md, maquette.png'));
    });

    test('rejette les noms d’attributs et objets incompatibles avec JsonAttributePath / YAML DSL', () {
      final invalid = BusinessAttribute(id: 'a1', name: '@calcul');
      expect(invalid.validate, throwsFormatException);

      final invalidDot = BusinessAttribute(id: 'a2', name: 'client.nom');
      expect(invalidDot.validate, throwsFormatException);

      final invalidAccent = BusinessAttribute(
        id: 'a3',
        name: 'statutCohérence',
      );
      expect(invalidAccent.validate, throwsFormatException);

      final invalidTechName = BusinessObjectSpec(
        id: 'o1',
        name: 'Relevé',
        technicalName: 'RelevéKilométrique',
      );
      expect(invalidTechName.validate, throwsFormatException);

      expect(
        BusinessAttribute.normalizeDslIdentifier('statutCohérence'),
        'statutCoherence',
      );
      expect(
        BusinessAttribute.toPascalCaseDslIdentifier('Relevé Kilométrique'),
        'ReleveKilometrique',
      );
    });
  });

  group('SpecStreamParser & SpecPatchApplier', () {
    test('extrait le champ message en streaming puis décode askUser/specPatch', () {
      final parser = SpecStreamParser();
      var snap = parser.addChunk('{"message":"Bonjour ');
      expect(snap.message, 'Bonjour ');
      expect(snap.isMessageComplete, isFalse);

      snap = parser.addChunk('utilisateur\\nSuite","askUser":{"questions":[');
      expect(snap.message, 'Bonjour utilisateur\nSuite');
      expect(snap.isMessageComplete, isTrue);
      expect(snap.hasAskUser, isTrue);

      parser.addChunk(
        '{"id":"q1","title":"Cible ?","type":"single","options":["B2B","B2C"],"default":"B2B"}]},"specPatch":null,"stageReadyToAdvance":false}',
      );
      final resp = SpecAgentResponse.parse(parser.rawText);
      expect(resp.message, 'Bonjour utilisateur\nSuite');
      expect(resp.askUser, isNotNull);
      expect(resp.askUser!.questions.single.options, ['B2B', 'B2C']);
      expect(resp.specPatch, isNull);
    });

    test('fusionne incrémentalement et supprime par ID via SpecPatchApplier', () {
      final project = SpecForgeProject.fromIdea(
        idea: 'Suivi de commandes clients',
        name: 'OrderHub',
      );
      final res1 = SpecPatchApplier.apply(project, {
        'lexicon': {
          'terms': [
            {
              'id': 't1',
              'term': 'Commande',
              'definition': 'Engagement client ferme',
              'synonyms': ['Bon de commande'],
            },
          ],
          'conventions': ['Montants HT en EUR'],
        },
        'vision': {
          'objectives': ['Automatiser la validation'],
          'personas': [
            {'id': 'p1', 'name': 'Commercial', 'role': 'Saisit les commandes'},
          ],
        },
        'businessObjects': [
          {
            'id': 'obj_cmd',
            'name': 'Commande',
            'technicalName': 'Commande',
            'attributes': [
              {'id': 'a1', 'name': 'numero', 'type': 'string', 'required': true},
            ],
          },
        ],
        'businessRules': [
          {
            'id': 'r1',
            'code': 'RG-001',
            'title': 'Numéro obligatoire',
            'targetObjectIds': ['obj_cmd'],
          },
          {
            'id': 'r2',
            'code': 'RG-002',
            'title': 'Temporaire',
            'targetObjectIds': ['obj_cmd'],
          },
        ],
      });

      expect(res1.project.lexicon.terms.length, 1);
      expect(res1.project.lexicon.terms.single.term, 'Commande');
      expect(res1.project.vision.personas.length, 1);
      expect(res1.project.businessObjects.length, 1);
      expect(res1.project.businessRules.length, 2);

      final res2 = SpecPatchApplier.apply(res1.project, {
        'removeBusinessRuleIds': ['r2'],
        'businessRules': [
          {
            'id': 'r1',
            'code': 'RG-001',
            'title': 'Numéro unique et obligatoire',
            'targetObjectIds': ['obj_cmd'],
          },
        ],
      });

      expect(res2.project.businessRules.length, 1);
      expect(
        res2.project.businessRules.single.title,
        'Numéro unique et obligatoire',
      );
    });

    test('SpecPatchApplier.applyPartial et SpecDeltaRecovery isolent les erreurs et sauvent le checkpoint', () {
      final project = SpecForgeProject.fromIdea(
        idea: 'Gestion de stock',
        name: 'StockApp',
      );

      final partial = SpecPatchApplier.applyPartial(project, {
        'businessObjects': [
          {
            'id': 'obj_article',
            'name': 'Article',
            'technicalName': 'Article',
            'attributes': [
              {'id': 'a1', 'name': 'code', 'type': 'string', 'required': true},
            ],
          },
          {
            'id': 'obj_bad',
            'name': 'Invalide',
            'attributes': [
              {'id': 'a2', 'name': '@interdit', 'type': 'string'},
            ],
          },
        ],
      });

      expect(partial.project.businessObjects.length, 1);
      expect(partial.project.businessObjects.single.id, 'obj_article');
      expect(partial.rejectedEntries.length, 1);
      expect(partial.rejectedEntries.single.key, 'obj_bad');

      const truncatedRaw =
          '{"message":"Objets générés","specPatch":{"businessObjects":[{"id":"obj_client","name":"Client","attributes":[{"id":"c1","name":"nom","type":"string"}]},{"id":"obj_tr';
      final salvage = SpecDeltaRecovery.salvageFailedAttempt(
        workingProject: project,
        rawResponse: truncatedRaw,
      );
      expect(salvage.hasCheckpoint, isTrue);
      expect(salvage.wasTruncated, isTrue);
      expect(salvage.checkpointProject.businessObjects.single.id, 'obj_client');

      final retryPrompt = SpecDeltaRecovery.buildDeltaRetryPrompt(
        refreshedTurnPrompt: 'Contexte',
        priorCauses: const ['Tentative 1 (FormatException) : JSON tronqué'],
        salvage: salvage,
      );
      expect(retryPrompt, contains('REPRISE AUTOMATIQUE'));
      expect(retryPrompt, contains('Checkpoint partiel DÉJÀ APPLIQUÉ'));
    });

    test('Sous-objets imbriqués, règles <= 200 attributs / <= 200 lignes et pont Yaml2JsonSchemasParser', () {
      final project = SpecForgeProject.fromIdea(
        idea: 'Gestion de devis',
        name: 'DevisPro',
      );

      final structured = BusinessObjectSpec(
        id: 'obj_devis',
        name: 'Devis',
        technicalName: 'Devis',
        attributes: [
          BusinessAttribute(
            id: 'a_num',
            name: 'numero',
            type: BusinessAttributeType.string,
            required: true,
          ),
          BusinessAttribute(
            id: 'a_client_adr',
            name: 'adresseChantier',
            type: BusinessAttributeType.object,
            required: true,
            children: [
              BusinessAttribute(
                id: 'a_rue',
                name: 'rue',
                type: BusinessAttributeType.string,
                required: true,
              ),
              BusinessAttribute(
                id: 'a_ville',
                name: 'ville',
                type: BusinessAttributeType.string,
                required: true,
              ),
            ],
          ),
          BusinessAttribute(
            id: 'a_lignes',
            name: 'lignes',
            type: BusinessAttributeType.object,
            isArray: true,
            estimatedMaxRows: 150,
            description: 'Lignes du devis',
            children: [
              BusinessAttribute(
                id: 'a_lig_des',
                name: 'designation',
                type: BusinessAttributeType.string,
                required: true,
              ),
              BusinessAttribute(
                id: 'a_lig_prix',
                name: 'prixHt',
                type: BusinessAttributeType.number,
                required: true,
              ),
            ],
          ),
        ],
      );

      structured.validate();
      expect(structured.totalAttributeCount, 7);

      final enriched = project.copyWith(businessObjects: [structured]);
      final yaml = SpecSchemaDslBridge.toYamlLight(enriched);
      expect(yaml, contains('adresseChantier!:'));
      expect(yaml, contains('lignes[]:'));

      final treeNodes = SpecSchemaDslBridge.buildTreeNodes(enriched);
      expect(treeNodes.length, 1);
      expect(treeNodes.single['displayName'], 'Devis (Devis)');
      expect(treeNodes.single['totalAttributes'], 7);
      final rootChildren = treeNodes.single['children'] as List;
      expect(rootChildren.length, 3);

      final roundTripped = SpecSchemaDslBridge.fromYamlLight(
        yaml,
        existing: enriched.businessObjects,
      );
      expect(roundTripped.single.id, 'obj_devis');
      expect(roundTripped.single.attributes[1].children.length, 2);
      expect(roundTripped.single.attributes[2].isArray, isTrue);
      expect(roundTripped.single.attributes[2].estimatedMaxRows, 150);

      // Règle 1 : > 200 attributs rejeté
      final tooMany = BusinessObjectSpec(
        id: 'obj_huge',
        name: 'Geant',
        attributes: [
          for (var i = 0; i < 195; i++)
            BusinessAttribute(id: 'a_$i', name: 'champ_$i'),
          BusinessAttribute(
            id: 'a_sub',
            name: 'bloc',
            type: BusinessAttributeType.object,
            children: [
              for (var j = 0; j < 6; j++)
                BusinessAttribute(id: 's_$j', name: 'sous_$j'),
            ],
          ),
        ],
      );
      expect(tooMany.validate, throwsFormatException);

      // Règle 2 : > 200 lignes par tableau imbriqué rejeté
      final tooManyRows = BusinessObjectSpec(
        id: 'obj_catalogue',
        name: 'Catalogue',
        attributes: [
          BusinessAttribute(
            id: 'a_items',
            name: 'produits',
            type: BusinessAttributeType.object,
            isArray: true,
            estimatedMaxRows: 5000,
            children: [
              BusinessAttribute(id: 'a_sku', name: 'sku'),
            ],
          ),
        ],
      );
      expect(tooManyRows.validate, throwsFormatException);
    });

    test('SpecForgeToolRegistry exécute les 9 outils métier et de validation', () async {
      debugEntries.clear();
      saveError('Erreur test outil', null);

      var current = SpecForgeProject.fromIdea(
        idea: 'Gestion des devis',
        name: 'DevisApp',
      ).copyWith(
        lexicon: SpecLexicon(
          terms: [
            LexiconTerm(
              id: 't1',
              term: 'Devis',
              definition: 'Offre chiffrée',
              synonyms: const ['Chiffrage'],
            ),
          ],
        ),
        cahierDesCharges: SpecCahierDesCharges(
          modules: const [SpecModule(id: 'm1', name: 'Ventes')],
          functionalRequirements: [
            FunctionalRequirement(
              id: 'r1',
              code: 'EXF-001',
              title: 'Créer devis',
              moduleId: 'm1',
            ),
          ],
        ),
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_devis',
            name: 'Devis',
            technicalName: 'Devis',
            attributes: [
              BusinessAttribute(id: 'a1', name: 'numero', required: true),
              BusinessAttribute(
                id: 'a2',
                name: 'lignes',
                type: BusinessAttributeType.object,
                isArray: true,
                estimatedMaxRows: 100,
                children: [
                  BusinessAttribute(id: 'a3', name: 'produit', required: true),
                ],
              ),
            ],
          ),
        ],
        businessRules: [
          BusinessRuleSpec(
            id: 'rg1',
            code: 'RG-001',
            title: 'Numéro unique',
            targetObjectIds: const ['obj_devis'],
          ),
        ],
      );

      SpecForgeStage? navigatedStage;
      String? focusedObj;
      List<String> focusedAttrPath = const <String>[];
      String appliedFilter = '';
      final registry = SpecForgeToolRegistry.build(
        readProject: () => current,
        onUpdateProject: (updated) async => current = updated,
        onNavigateStage: (s) async => navigatedStage = s,
        onFocusObject: (id) => focusedObj = id,
        onFocusSelection: ({objectId, attributePath = const <String>[]}) {
          focusedObj = objectId;
          focusedAttrPath = attributePath;
        },
        onFilterBusinessObjects: (q) => appliedFilter = q,
      );

      expect(registry.declarations.length, 10);

      final lexRes = await registry.execute(
        VibeToolCall(id: '1', name: 'get_lexicon_and_synonyms', arguments: const {'query': 'chiffrage'}),
      );
      expect(lexRes.isError, isFalse);
      expect(lexRes.data['termCount'], 1);

      final reqRes = await registry.execute(
        VibeToolCall(id: '2', name: 'get_requirements_summary'),
      );
      expect(reqRes.data['functionalRequirementCount'], 1);

      final objRes = await registry.execute(
        VibeToolCall(
          id: '3',
          name: 'inspect_business_object',
          arguments: const {'objectIdOrName': 'Devis', 'includeYaml': true},
        ),
      );
      expect(objRes.data['totalAttributeCount'], 3);
      expect(objRes.data['yamlLight'], contains('Devis:'));

      final ruleRes = await registry.execute(
        VibeToolCall(
          id: '4',
          name: 'get_business_rules',
          arguments: const {'objectId': 'Devis'},
        ),
      );
      expect(ruleRes.data['ruleCount'], 1);

      final dbgRes = await registry.execute(
        VibeToolCall(id: '5', name: 'get_debug_entries'),
      );
      expect(dbgRes.data['returnedCount'], 1);

      final auditRes = await registry.execute(
        VibeToolCall(id: '6', name: 'run_coherence_audit'),
      );
      expect(auditRes.isError, isFalse);

      final yamlOk = await registry.execute(
        VibeToolCall(
          id: '7',
          name: 'validate_yaml_light_schema',
          arguments: const {'yaml': 'Client:\n  nom: string!'},
        ),
      );
      expect(yamlOk.data['valid'], isTrue);

      final yamlBad = await registry.execute(
        VibeToolCall(
          id: '8',
          name: 'validate_yaml_light_schema',
          arguments: const {'yaml': 'Client:\n  type: InconnuType'},
        ),
      );
      expect(yamlBad.isError, isTrue);

      final extractRes = await registry.execute(
        VibeToolCall(
          id: '9',
          name: 'extract_array_to_business_object',
          arguments: const {'objectId': 'obj_devis', 'attributeName': 'lignes'},
        ),
      );
      expect(extractRes.isError, isFalse);
      expect(current.businessObjects.length, 2);
      expect(current.businessObjects.first.relations.single.name, 'lignes');

      final focusRes = await registry.execute(
        VibeToolCall(
          id: '10',
          name: 'focus_stage_or_object',
          arguments: const {
            'stage': 'businessObjects',
            'objectId': 'obj_devis',
            'attributePath': 'numero',
          },
        ),
      );
      expect(focusRes.isError, isFalse);
      expect(navigatedStage, SpecForgeStage.businessObjects);
      expect(focusedObj, 'obj_devis');
      expect(focusedAttrPath, ['a1']);

      final filterRes = await registry.execute(
        VibeToolCall(
          id: '11',
          name: 'filter_business_objects',
          arguments: const {'query': 'numero'},
        ),
      );
      expect(filterRes.isError, isFalse);
      expect(appliedFilter, 'numero');
      expect(filterRes.data['matchingObjectCount'], 1);
    });

    test('JsonSchemaConstraints : validation complète, sérialisation, bornes et mots-clés avancés', () {
      final sc = JsonSchemaConstraints(
        minimum: 0,
        maximum: 1000,
        exclusiveMaximum: 1001,
        multipleOf: 0.5,
        minLength: 3,
        maxLength: 50,
        pattern: r'^[A-Z0-9-]+$',
        format: 'uuid',
        contentMediaType: 'application/json',
        contentEncoding: 'utf-8',
        minItems: 1,
        maxItems: 20,
        uniqueItems: true,
        minContains: 1,
        maxContains: 5,
        minProperties: 2,
        maxProperties: 10,
        additionalProperties: false,
        dependentRequired: const {
          'carte': ['cvv'],
        },
        hasConst: true,
        constValue: null,
        examples: const ['EX-01'],
        readOnly: true,
        deprecated: true,
        title: 'Référence',
        comment: 'Note interne',
        oneOf: const [
          {'minLength': 4},
        ],
        extraKeywords: const {'x-mask': 'AA-###'},
      );
      sc.validate();
      final json = sc.toJson();
      expect(json['const'], isNull);
      expect(json.containsKey('const'), isTrue);
      expect(json['x-mask'], 'AA-###');
      expect(json['dependentRequired'], {
        'carte': ['cvv'],
      });

      final roundTrip = JsonSchemaConstraints.fromJson(json);
      expect(roundTrip, equals(sc));
      expect(roundTrip.hasConst, isTrue);
      expect(roundTrip.constValue, isNull);
      expect(roundTrip.describeBadges(), isNotEmpty);

      // Cas invalides rejetés :
      expect(
        JsonSchemaConstraints(minimum: 10, maximum: 5).validate,
        throwsFormatException,
      );
      expect(
        JsonSchemaConstraints(minLength: 8, maxLength: 3).validate,
        throwsFormatException,
      );
      expect(
        JsonSchemaConstraints(multipleOf: 0).validate,
        throwsFormatException,
      );
      expect(
        JsonSchemaConstraints(pattern: '[unclosed').validate,
        throwsFormatException,
      );
    });

    test('BusinessObjectModelPreferences : sérialisation, rétrocompatibilité et injection IA', () {
      final base = SpecForgeProject.fromIdea(
        idea: 'Suivi de chantier',
        name: 'ChantierApp',
      );
      expect(base.businessObjectModelPreferences.isDefault, isTrue);
      expect(base.businessObjectModelPreferences.attributeLanguage, 'en');
      expect(base.businessObjectModelPreferences.enumLanguage, 'en');
      expect(base.businessObjectModelPreferences.contentLanguage, 'fr');

      final updated = base.copyWith(
        businessObjectModelPreferences: const BusinessObjectModelPreferences(
          attributeLanguage: 'en',
          enumLanguage: 'fr',
          contentLanguage: 'fr',
          attributeCase: AttributeNamingCase.snakeCase,
          enumCase: EnumValueNamingCase.screamingSnakeCase,
          idStrategy: PrimaryIdStrategy.ulid,
          foreignKeyStyle: ForeignKeyNamingStyle.prefixId,
          auditPreset: AuditFieldsPreset.timestamps,
          schemaStrictness: JsonSchemaStrictness.strict,
          nullabilityStyle: NullabilityStyle.explicitNullable,
          relationStyle: RelationModelingStyle.normalizedRefs,
          localeProfile: ModelLocaleProfile.usUsd,
          currencyStyle: CurrencyRepresentation.integerCents,
          customInstructions: 'Prefix booleans with is',
        ),
      );
      final decoded = SpecForgeProject.fromJson(updated.toJson());
      expect(decoded.businessObjectModelPreferences, equals(updated.businessObjectModelPreferences));

      // Rétrocompatibilité clé JSON `businessObjectLanguageSettings`.
      final legacyJson = updated.toJson();
      legacyJson['businessObjectLanguageSettings'] =
          legacyJson.remove('businessObjectModelPreferences');
      final decodedLegacy = SpecForgeProject.fromJson(legacyJson);
      expect(
        decodedLegacy.businessObjectLanguageSettings.attributeCase,
        AttributeNamingCase.snakeCase,
      );

      expect(
        AttributeNamingCase.snakeCase.formatIdentifier('adresseLivraison'),
        'adresse_livraison',
      );
      expect(
        AttributeNamingCase.camelCase.formatIdentifier('delivery_address'),
        'deliveryAddress',
      );
      expect(
        AttributeNamingCase.pascalCase.formatIdentifier('delivery_address'),
        'DeliveryAddress',
      );
      expect(
        AttributeNamingCase.kebabCase.formatIdentifier('adresseLivraison'),
        'adresse-livraison',
      );
      expect(
        AttributeNamingCase.screamingSnakeCase.formatIdentifier('adresseLivraison'),
        'ADRESSE_LIVRAISON',
      );
      expect(
        EnumValueNamingCase.screamingSnakeCase.formatValue('enAttente'),
        'EN_ATTENTE',
      );

      final kickoff = SpecPromptBuilder.buildStageKickoffPrompt(
        decoded,
        SpecForgeStage.businessObjects,
      );
      expect(kickoff, contains('PRÉFÉRENCES DU MODÈLE D’OBJETS MÉTIERS'));
      expect(kickoff, contains('English (en)'));
      expect(kickoff, contains('snake_case'));
      expect(kickoff, contains('SCREAMING_SNAKE_CASE'));
      expect(kickoff, contains('ULID'));
      expect(kickoff, contains('additionalProperties: false'));
      expect(kickoff, contains('Prefix booleans with is'));

      final turnPrompt = SpecPromptBuilder.buildTurnPrompt(
        project: decoded,
        stage: SpecForgeStage.businessObjects,
        userInput: 'Modélise Chantier',
        questioningLevel: VibeQuestioningLevel.balanced,
        afterAskUserReply: false,
      );
      expect(
        turnPrompt,
        contains('PRÉFÉRENCES DU MODÈLE D’OBJETS MÉTIERS'),
      );
      expect(turnPrompt, contains('English (en)'));
      expect(turnPrompt, contains('snake_case'));
      expect(turnPrompt, contains('Français (fr)'));
      expect(turnPrompt, contains('"attributeLanguage": "en"'));
      expect(turnPrompt, contains('"enumLanguage": "fr"'));
      expect(turnPrompt, contains('"attributeCase": "snakeCase"'));
      expect(turnPrompt, contains('"schemaStrictness": "strict"'));
      expect(turnPrompt, contains('schemaConstraints.examples'));

      final objectsAgent = SpecStageAgent.forStage(
        SpecForgeStage.businessObjects,
      );
      expect(
        objectsAgent.systemInstruction,
        contains('EXEMPLES JSON SCHEMA OBLIGATOIRES'),
      );
      expect(objectsAgent.patchSchemaGuide, contains('"examples": [2, 5]'));
    });
  });
}
