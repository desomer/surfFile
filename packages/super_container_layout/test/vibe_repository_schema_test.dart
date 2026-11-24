import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/services/repositories/repository_array_creation.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_prompt_builder.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vibe-schema-test-');
    store = JsonRepositoryStore(directory);
  });

  tearDown(() async {
    store.dispose();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('expose jsonSchema dans VibeRepositoryPromptFormatter et valide les patches Vibe', () async {
    final tx = VibeRepositoryTurnTransaction(store);
    final aliases = await tx.applyRepositoriesPatch({
      'crm_taches': {
        'name': 'Taches',
        'mode': 'replace',
        'jsonSchema': {
          'type': 'object',
          'required': ['taches'],
          'additionalProperties': false,
          'properties': {
            'taches': {
              'type': 'array',
              'items': {
                'type': 'object',
                'required': ['titre', 'priorite'],
                'properties': {
                  'titre': {'type': 'string', 'minLength': 1},
                  'priorite': {
                    'type': 'string',
                    'enum': ['haute', 'normale', 'basse'],
                  },
                },
              },
            },
          },
        },
        'data': {
          'taches': [
            {'titre': 'Initialiser le projet', 'priorite': 'haute'},
          ],
        },
      },
    });

    final repoId = aliases['crm_taches']!;
    expect(store.jsonSchemaOf(repoId), isNotNull);

    final promptContext = await VibeRepositoryPromptFormatter.formatStoreContext(
      store,
    );
    expect(promptContext, contains('"jsonSchema"'));
    expect(promptContext, contains('"priorite"'));

    // Un patch suivant avec une valeur invalide contre le schéma est rejeté.
    final txInvalid = VibeRepositoryTurnTransaction(store);
    await expectLater(
      txInvalid.applyRepositoriesPatch({
        repoId: {
          'mode': 'replace',
          'data': {
            'taches': [
              {'titre': 'Bug', 'priorite': 'critique'},
            ],
          },
        },
      }),
      throwsA(isA<JsonSchemaValidationException>()),
    );
    expect(
      ((await store.readDocument(repoId) as Map)['taches'] as List).first['titre'],
      'Initialiser le projet',
    );
  });

  test('savepoint, rollback, undo et redo restaurent les jsonSchema et données', () async {
    await store.create('catalogue');
    final repoId = await store.idOf('catalogue');
    await store.replaceDocumentById(repoId, {'items': []});

    final tx = VibeRepositoryTurnTransaction(store);
    await tx.applyRepositoriesPatch({
      repoId: {
        'mode': 'replace',
        'jsonSchema': {
          'type': 'object',
          'required': ['items'],
          'properties': {
            'items': {'type': 'array'},
          },
        },
        'data': {
          'items': ['A'],
        },
      },
    });
    final sp = tx.createSavepoint();

    await tx.applyRepositoriesPatch({
      repoId: {
        'mode': 'replace',
        'jsonSchema': {
          'type': 'object',
          'required': ['items', 'version'],
          'properties': {
            'items': {'type': 'array'},
            'version': {'type': 'integer'},
          },
        },
        'data': {
          'items': ['A', 'B'],
          'version': 2,
        },
      },
    });
    expect(
      (store.jsonSchemaOf(repoId)!['required'] as List),
      contains('version'),
    );

    await tx.restoreSavepoint(sp);
    expect(
      (store.jsonSchemaOf(repoId)!['required'] as List),
      isNot(contains('version')),
    );
    expect(((await store.readDocument(repoId) as Map)['items'] as List), ['A']);

    final callbacks = tx.buildHistoryCallbacks()!;
    await callbacks.undo();
    expect(store.jsonSchemaOf(repoId), isNull);
    expect(((await store.readDocument(repoId) as Map)['items'] as List), isEmpty);

    await callbacks.redo();
    expect(store.jsonSchemaOf(repoId), isNotNull);
    expect(((await store.readDocument(repoId) as Map)['items'] as List), ['A']);

    // Vérifie que applyRepositoriesPatchPartial rejette une entrée invalide sans bloquer une entrée valide.
    final txPartial = VibeRepositoryTurnTransaction(store);
    final partialResult = await txPartial.applyRepositoriesPatchPartial({
      repoId: {
        'mode': 'replace',
        'data': {'items': 'pas-un-tableau'},
      },
      'nouveau_repo': {
        'name': 'Valide',
        'data': {'ok': true},
      },
    });
    expect(partialResult.rejectedEntries, hasLength(1));
    expect(partialResult.rejectedEntries.first.key, repoId);
    expect(partialResult.appliedEntries.containsKey('nouveau_repo'), isTrue);
  });

  test('rollback annule un jsonSchema nouvellement ajouté sur un repo existant', () async {
    await store.create('notes');
    final repoId = await store.idOf('notes');
    await store.replaceDocumentById(repoId, {'titre': 'Note 1'});

    final tx = VibeRepositoryTurnTransaction(store);
    await tx.applyRepositoriesPatch({
      repoId: {
        'jsonSchema': {
          'type': 'object',
          'required': ['titre'],
          'properties': {
            'titre': {'type': 'string'},
          },
        },
      },
    });
    expect(store.jsonSchemaOf(repoId), isNotNull);

    await tx.rollback();
    expect(store.jsonSchemaOf(repoId), isNull);
  });

  test(
    'les prompts IA demandent systématiquement jsonSchema à la création et sa mise à jour à l’évolution',
    () {
      expect(
        VibeChatDialog.defaultSystemInstruction,
        contains('À CHAQUE création d\'un nouveau repository'),
      );
      expect(
        VibeChatDialog.defaultSystemInstruction,
        contains('génère SYSTÉMATIQUEMENT une clé "jsonSchema"'),
      );
      expect(
        VibeChatDialog.defaultSystemInstruction,
        contains('mets à jour "jsonSchema"'),
      );
      expect(
        VibeChatDialog.defaultSystemInstruction,
        contains('"additionalProperties": false'),
      );

      expect(
        VibePromptBuilder.planModePlanningDirective,
        contains('avec leur `"jsonSchema"` associé'),
      );
      expect(
        VibePromptBuilder.reactiveValuesDirective,
        contains('ni dans le `jsonSchema`'),
      );
      expect(
        VibeRepositoryPromptFormatter.emptyStoreMessage,
        contains('en fournissant "data" et son "jsonSchema" associé'),
      );

      final lotPrompt = VibePromptBuilder.buildLotTurnPrompt(
        plan: VibeExecutionPlan(
          title: 'Plan CRM',
          lots: [
            VibePlanLot(
              id: 'lot-1',
              title: 'Socle et repositories',
              description: 'Créer le repository CRM et le thème.',
            ),
          ],
        ),
        lotIndex: 0,
        sourcePrompt: 'Crée un CRM clients',
        appearance: Appearance(),
        codec: const AppearanceCodec(),
        scope: null,
        repositoriesContext: VibeRepositoryPromptFormatter.emptyStoreMessage,
      );
      expect(
        lotPrompt,
        contains('inclus systématiquement "jsonSchema" pour chaque nouveau repository'),
      );
    },
  );

  test(
    'buildDefaultArrayItem et appendSchemaRow produisent une ligne valide sur un jsonSchema riche',
    () async {
      final richSchema = <String, Object?>{
        'type': 'object',
        'required': ['dossiers'],
        'properties': <String, Object?>{
          'dossiers': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'object',
              'required': [
                'code',
                'statut',
                'dateCreation',
                'horodatage',
                'heure',
                'uid',
                'priorite',
                'montant',
              ],
              'properties': <String, Object?>{
                'code': <String, Object?>{'type': 'string', 'minLength': 3},
                'statut': <String, Object?>{
                  'type': 'string',
                  'enum': ['brouillon', 'valide'],
                },
                'dateCreation': <String, Object?>{
                  'type': 'string',
                  'format': 'date',
                },
                'horodatage': <String, Object?>{
                  'type': 'string',
                  'format': 'date-time',
                },
                'heure': <String, Object?>{'type': 'string', 'format': 'time'},
                'uid': <String, Object?>{'type': 'string', 'format': 'uuid'},
                'emailNullable': <String, Object?>{
                  'type': ['string', 'null'],
                  'format': 'email',
                },
                'siteOptionnel': <String, Object?>{
                  'type': 'string',
                  'format': 'uri',
                },
                'referencePatternOptionnelle': <String, Object?>{
                  'type': 'string',
                  'pattern': r'^REF-[0-9]{4}$',
                },
                'priorite': <String, Object?>{
                  'type': 'integer',
                  'minimum': 1,
                  'multipleOf': 5,
                },
                'montant': <String, Object?>{
                  'type': 'number',
                  'exclusiveMinimum': 0,
                  'maximum': 0.5,
                },
              },
            },
          },
        },
      };

      final tx = VibeRepositoryTurnTransaction(store);
      final aliases = await tx.applyRepositoriesPatch({
        'suivi_dossiers': {
          'name': 'Suivi Dossiers',
          'mode': 'replace',
          'jsonSchema': richSchema,
          'data': {'dossiers': <Object?>[]},
        },
      });
      final repoId = aliases['suivi_dossiers']!;

      final previewRow =
          JsonSchemaFieldResolver.buildDefaultArrayItem(richSchema, 'dossiers')
              as Map<String, Object?>;
      expect(previewRow['code'], '---');
      expect(previewRow['statut'], 'brouillon');
      expect(
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(previewRow['dateCreation']! as String),
        isTrue,
      );
      expect(
        (previewRow['horodatage']! as String).endsWith('Z'),
        isTrue,
      );
      expect(previewRow['heure'], '00:00:00');
      expect(previewRow['uid'], '00000000-0000-0000-0000-000000000000');
      expect(previewRow.containsKey('emailNullable'), isTrue);
      expect(previewRow['emailNullable'], isNull);
      expect(previewRow.containsKey('siteOptionnel'), isFalse);
      expect(previewRow.containsKey('referencePatternOptionnelle'), isFalse);
      expect(previewRow['priorite'], 5);
      expect(previewRow['montant'], greaterThan(0));
      expect(previewRow['montant'], lessThanOrEqualTo(0.5));

      final count = await RepositoryArrayCreationService.appendSchemaRow(
        store: store,
        repositoryId: repoId,
        concreteArrayPath: 'dossiers',
        arrayTemplatePath: 'dossiers',
      );
      expect(count, 1);

      final validation = await store.validateRepository(repoId);
      expect(validation.isValid, isTrue);
    },
  );
}
