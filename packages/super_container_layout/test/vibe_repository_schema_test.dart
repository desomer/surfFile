import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';

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
}
