import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('TechnicalModelingRule & BusinessObjectModelPreferences enrichis', () {
    test('catalogue par défaut couvre Id, Ref, Code, Number, Key, At/Date, booléens et unités', () {
      final patterns = {
        for (final r in TechnicalModelingRule.defaultRules) r.suffixOrPattern,
      };
      expect(patterns, containsAll([
        'id / *Id',
        '*Ref',
        '*Code',
        '*Number',
        '*Key',
        '*At / *Date',
        'is* / has* / can*',
      ]));
      for (final rule in TechnicalModelingRule.defaultRules) {
        rule.validate();
      }

      const prefs = BusinessObjectModelPreferences(
        enforceIdRefCodeNumberDistinction: true,
        dateTimeSuffixPolicy: DateTimeSuffixPolicy.strictAtAndDate,
        booleanPrefixPolicy: BooleanPrefixPolicy.strictIsHasCan,
        unitSuffixPolicy: UnitSuffixPolicy.explicitSuffix,
        softDeleteStrategy: SoftDeleteStrategy.deletedAtTimestamp,
        optimisticLockingStrategy: OptimisticLockingStrategy.integerVersion,
        defaultCodeMaxLength: 48,
        defaultLabelMaxLength: 180,
        defaultDescriptionMaxLength: 1500,
      );
      prefs.validate();

      final decoded = BusinessObjectModelPreferences.fromJson(prefs.toJson());
      expect(decoded, prefs);

      final directive = prefs.toPromptDirective();
      expect(directive, contains('Arbitrage Id / Ref / Code / Number / Key'));
      expect(directive, contains('deletedAt'));
      expect(directive, contains('version'));
      expect(directive, contains('codes/références <= 48 car.'));
      expect(directive, contains('DICTIONNAIRE DE RÈGLES TECHNIQUES ACTIVES'));
    });

    test('rétrocompatibilité fromJson sans les nouveaux champs techniques', () {
      final legacy = BusinessObjectModelPreferences.fromJson({
        'attributeLanguage': 'fr',
        'attributeCase': 'snakeCase',
        'schemaStrictness': 'strict',
      });
      expect(legacy.attributeLanguage, 'fr');
      expect(legacy.attributeCase, AttributeNamingCase.snakeCase);
      expect(legacy.schemaStrictness, JsonSchemaStrictness.strict);
      expect(legacy.enforceIdRefCodeNumberDistinction, isTrue);
      expect(
        legacy.technicalRules.length,
        TechnicalModelingRule.defaultRules.length,
      );
    });
  });

  group('ModelDictionaryStore & ModelDictionaryCodec', () {
    test('sauvegarde atomique, rechargement et export/import JSON & Markdown', () async {
      final tempDir = await Directory.systemTemp.createTemp('model_dict_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = ModelDictionaryStore(tempDir);
      expect(await store.load(), BusinessObjectModelPreferences.defaults);

      final customRule = const TechnicalModelingRule(
        id: 'rule_iban',
        name: 'Compte bancaire IBAN',
        suffixOrPattern: '*Iban',
        category: TechnicalRuleCategory.custom,
        whenToUse: 'Coordonnées bancaires normalisées ISO 13616.',
        whenNotToUse: 'Ne pas utiliser pour un numéro interne de compte client.',
        recommendedType: 'string (maxLength: 34)',
        goodExamples: ['supplierIban'],
      );
      final updated = BusinessObjectModelPreferences.defaults.copyWith(
        attributeCase: AttributeNamingCase.snakeCase,
        softDeleteStrategy: SoftDeleteStrategy.both,
        optimisticLockingStrategy: OptimisticLockingStrategy.integerVersion,
        technicalRules: [...TechnicalModelingRule.defaultRules, customRule],
      );

      await store.save(updated);
      final reloaded = await ModelDictionaryStore(tempDir).load();
      expect(reloaded, updated);

      final jsonStr = ModelDictionaryCodec.toJsonString(reloaded);
      expect(ModelDictionaryCodec.parseJson(jsonStr), reloaded);

      final md = ModelDictionaryCodec.toMarkdown(reloaded);
      expect(md, contains('# Dictionnaire technique & Règles de modélisation'));
      expect(md, contains('*Iban'));
      expect(md, contains('Suffixe *Number'));
    });
  });

  group('SpecCoherenceAnalyzer & SpecForgeController héritage global', () {
    test('détecte COH-MOD-001..004 sur booléens, *At/*Date et *Number', () {
      final project = SpecForgeProject.fromIdea(idea: 'Facturation B2B').copyWith(
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_inv',
            name: 'Facture',
            technicalName: 'Invoice',
            attributes: [
              BusinessAttribute(
                id: 'a_bool',
                name: 'active',
                type: BusinessAttributeType.boolean,
              ),
              BusinessAttribute(
                id: 'a_dt',
                name: 'createdDate',
                type: BusinessAttributeType.datetime,
              ),
              BusinessAttribute(
                id: 'a_d',
                name: 'dueAt',
                type: BusinessAttributeType.date,
              ),
              BusinessAttribute(
                id: 'a_num',
                name: 'invoiceNumber',
                type: BusinessAttributeType.uuid,
              ),
            ],
          ),
        ],
      );

      final issues = SpecCoherenceAnalyzer.analyze(
        project,
        modelPreferences: BusinessObjectModelPreferences.defaults,
      );
      expect(issues.any((i) => i.code == 'COH-MOD-001'), isTrue);
      expect(issues.any((i) => i.code == 'COH-MOD-002'), isTrue);
      expect(issues.any((i) => i.code == 'COH-MOD-003'), isTrue);
      expect(issues.any((i) => i.code == 'COH-MOD-004'), isTrue);
    });

    test('SpecForgeController hérite globalement, supporte Undo/Redo et conversion de casse', () async {
      final tempDir = await Directory.systemTemp.createTemp('model_ctrl_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final controller = SpecForgeController(
        store: SpecProjectStore(tempDir),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      await controller.updateModelPreferences(
        controller.modelPreferences.copyWith(
          attributeCase: AttributeNamingCase.snakeCase,
          enumCase: EnumValueNamingCase.screamingSnakeCase,
          idStrategy: PrimaryIdStrategy.ulid,
        ),
      );
      await controller.upsertTechnicalRule(
        const TechnicalModelingRule(
          id: 'rule_slug',
          name: 'Slug URL',
          suffixOrPattern: '*Slug',
          category: TechnicalRuleCategory.custom,
          whenToUse: 'Identifiant lisible dans une URL publique.',
        ),
      );
      expect(
        controller.modelPreferences.technicalRules.any((r) => r.id == 'rule_slug'),
        isTrue,
      );

      await controller.undoModelPreferences();
      expect(
        controller.modelPreferences.technicalRules.any((r) => r.id == 'rule_slug'),
        isFalse,
      );
      await controller.redoModelPreferences();
      expect(
        controller.modelPreferences.technicalRules.any((r) => r.id == 'rule_slug'),
        isTrue,
      );

      await controller.createProjectFromIdea(
        idea: 'Gestion commandes',
        autoKickoff: false,
      );
      await controller.updateProject(
        controller.project!.copyWith(
          businessObjects: [
            BusinessObjectSpec(
              id: 'o1',
              name: 'Commande',
              technicalName: 'Order',
              attributes: [
                BusinessAttribute(
                  id: 'a1',
                  name: 'orderDate',
                  type: BusinessAttributeType.date,
                ),
                BusinessAttribute(
                  id: 'a2',
                  name: 'status',
                  type: BusinessAttributeType.enumeration,
                  enumValues: const ['enCours'],
                ),
              ],
            ),
          ],
        ),
      );

      final converted = await controller.applyModelCaseToActiveProject();
      expect(converted, isTrue);
      expect(
        controller.project!.businessObjects.single.attributes.first.name,
        'order_date',
      );
      expect(
        controller.project!.businessObjects.single.attributes[1].enumValues,
        ['EN_COURS'],
      );

      // Le prompt généré pour le projet hérite des préférences globales.
      final prompt = SpecPromptBuilder.buildTurnPrompt(
        project: controller.project!,
        stage: SpecForgeStage.businessObjects,
        userInput: 'Modélise',
        questioningLevel: VibeQuestioningLevel.none,
        afterAskUserReply: false,
        modelPreferencesOverride: controller.modelPreferences,
      );
      expect(prompt, contains('ULID'));
      expect(prompt, contains('*Slug'));
    });
  });
}
