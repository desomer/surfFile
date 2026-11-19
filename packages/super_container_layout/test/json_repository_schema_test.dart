import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('repo-schema-test-');
    store = JsonRepositoryStore(directory);
  });

  tearDown(() async {
    store.dispose();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  const clientSchema = <String, Object?>{
    'type': 'object',
    'required': ['nom', 'articles'],
    'additionalProperties': false,
    'properties': {
      'nom': {'type': 'string', 'minLength': 2},
      'articles': {
        'type': 'array',
        'items': {
          'type': 'object',
          'required': ['titre', 'prix'],
          'properties': {
            'titre': {'type': 'string', 'minLength': 1},
            'prix': {'type': 'number', 'minimum': 0},
          },
        },
      },
    },
  };

  test('associe, persiste schemas/<id>.json, survit au renommage et bloque les écritures invalides', () async {
    await store.create('clients');
    final id = await store.idOf('clients');
    await store.save(
      'clients',
      '{"nom":"Alice","articles":[{"titre":"Livre","prix":12}]}\n',
      expectedText: await store.read('clients'),
    );

    await store.saveJsonSchema('clients'.isEmpty ? id : id, clientSchema);
    expect(store.jsonSchemaOf(id), isNotNull);
    final schemaFile = File(
      '${directory.path}${Platform.pathSeparator}schemas${Platform.pathSeparator}$id.json',
    );
    expect(schemaFile.existsSync(), isTrue);

    // Toute écriture violant le schéma est bloquée avec JsonSchemaValidationException.
    await expectLater(
      store.writeAttribute(
        JsonTextBinding(repositoryId: id, path: 'nom'),
        'A',
        expectedValue: 'Alice',
      ),
      throwsA(isA<JsonSchemaValidationException>()),
    );
    await expectLater(
      store.replaceValue(id, 'inconnu', 42),
      throwsA(isA<JsonSchemaValidationException>()),
    );
    await expectLater(
      store.appendArrayItem(id, 'articles', expectedLength: 1),
      throwsA(isA<JsonSchemaValidationException>()),
    );
    await expectLater(
      store.save(
        'clients',
        '{"nom":"Alice","articles":[{"titre":"Livre","prix":-5}]}\n',
        expectedText: await store.read('clients'),
      ),
      throwsA(isA<JsonSchemaValidationException>()),
    );

    // Le document intact n'a pas été corrompu.
    final doc = await store.readDocument(id) as Map<String, Object?>;
    expect(doc['nom'], 'Alice');

    // Une écriture conforme réussit.
    await store.writeAttribute(
      JsonTextBinding(repositoryId: id, path: 'nom'),
      'Bob',
      expectedValue: 'Alice',
    );
    expect((await store.readDocument(id) as Map)['nom'], 'Bob');

    // Le renommage conserve le schéma (indexé par ID technique), et un rechargement
    // depuis un nouveau store restaure la validation.
    await store.rename('clients', 'clients_vip');
    final reloadedStore = JsonRepositoryStore(directory);
    addTearDown(reloadedStore.dispose);
    await reloadedStore.preload();
    expect(reloadedStore.jsonSchemaOf(id), isNotNull);
    await expectLater(
      reloadedStore.replaceValue(id, 'nom', 'X'),
      throwsA(isA<JsonSchemaValidationException>()),
    );

    // La suppression du repository supprime aussi schemas/<id>.json.
    await reloadedStore.delete('clients_vip');
    expect(schemaFile.existsSync(), isFalse);
  });

  test('refuse d’associer un schéma incompatible avec le document existant', () async {
    await store.create('produits');
    final id = await store.idOf('produits');
    await store.replaceValue(id, 'nom', '');

    await expectLater(
      store.saveJsonSchema(id, {
        'type': 'object',
        'required': ['nom'],
        'properties': {
          'nom': {'type': 'string', 'minLength': 3},
        },
      }),
      throwsA(isA<JsonSchemaValidationException>()),
    );
    expect(store.jsonSchemaOf(id), isNull);
  });

  test('RepositoryImpl(jsonSchema: ...) valide à l’initialisation, en persistance et bloque les mutations invalides', () async {
    expect(
      () => RepositoryImpl(
        id: 'app_cfg',
        json: const {'port': -1},
        jsonSchema: const {
          'type': 'object',
          'required': ['port'],
          'properties': {
            'port': {'type': 'integer', 'minimum': 1},
          },
        },
      ),
      throwsA(isA<JsonSchemaValidationException>()),
    );

    final repo = RepositoryImpl(
      id: 'app_cfg',
      json: const {'port': 8080},
      jsonSchema: const {
        'type': 'object',
        'required': ['port'],
        'additionalProperties': false,
        'properties': {
          'port': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
        },
      },
    );
    await store.registerPersistentRepository(repo);
    expect(store.isCodeJsonSchema('app_cfg'), isTrue);

    await expectLater(
      store.writeAttribute(
        const JsonTextBinding(repositoryId: 'app_cfg', path: 'port'),
        '70000',
        expectedValue: 8080,
      ),
      throwsA(isA<JsonSchemaValidationException>()),
    );

    await expectLater(
      store.saveJsonSchema('app_cfg', const {'type': 'object'}),
      throwsFormatException,
    );

    await store.writeAttribute(
      const JsonTextBinding(repositoryId: 'app_cfg', path: 'port'),
      '9090',
      expectedValue: 8080,
    );
    expect((await store.readDocument('app_cfg') as Map)['port'], 9090);
  });
}
