import 'package:super_backend/super_backend.dart';
import 'package:test/test.dart';

void _runScrudTests(String label, CollectionStore Function() factory) {
  group('SCRUD SuperBackend ($label)', () {
    late SuperBackend backend;
    late CollectionApi clients;

    setUp(() async {
      backend = SuperBackend(store: factory());
      await backend.init();
      clients = backend.collection('clients');
    });

    tearDown(() async {
      await backend.close();
    });

    test('create génère un id ou réutilise id / keyField', () async {
      final auto = await clients.create({'name': 'Alice'});
      expect(auto['id'], isA<String>());
      expect((auto['id'] as String).isNotEmpty, isTrue);

      final explicit = await clients.create({'name': 'Bob'}, id: 'bob-1');
      expect(explicit['id'], 'bob-1');

      final fromPayload = await clients.create({
        'id': 'claire-2',
        'name': 'Claire',
      });
      expect(fromPayload['id'], 'claire-2');

      await expectLater(
        () => clients.create({'name': 'Duplicate'}, id: 'bob-1'),
        throwsA(isA<EntityAlreadyExistsException>()),
      );

      final upserted = await clients.create(
        {'name': 'Bob Updated'},
        id: 'bob-1',
        upsert: true,
      );
      expect(upserted['name'], 'Bob Updated');
    });

    test('read, readOrNull et EntityNotFoundException', () async {
      await clients.create({'name': 'Alice'}, id: 'a1');
      final read = await clients.read('a1');
      expect(read['name'], 'Alice');

      expect(await clients.readOrNull('missing'), isNull);
      await expectLater(
        () => clients.read('missing'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('update complet et update merge récursif', () async {
      await clients.create({
        'name': 'Alice',
        'profile': {'city': 'Lyon', 'zip': '69000'},
        'tags': ['vip'],
      }, id: 'a1');

      final merged = await clients.update('a1', {
        'id': 'tentative-override',
        'profile': {'city': 'Paris'},
      }, merge: true);
      expect(merged['id'], 'a1');
      expect(merged['name'], 'Alice');
      expect((merged['profile'] as Map)['city'], 'Paris');
      expect((merged['profile'] as Map)['zip'], '69000');
      expect(merged['tags'], ['vip']);

      final replaced = await clients.update('a1', {'name': 'Alice Only'});
      expect(replaced, {'id': 'a1', 'name': 'Alice Only'});

      await expectLater(
        () => clients.update('missing', {'name': 'X'}),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('delete et ignoreMissing', () async {
      await clients.create({'name': 'Alice'}, id: 'a1');
      await clients.delete('a1');
      expect(await clients.readOrNull('a1'), isNull);

      await expectLater(
        () => clients.delete('a1'),
        throwsA(isA<EntityNotFoundException>()),
      );
      await clients.delete('a1', ignoreMissing: true);
    });

    test('execute() dispatch générique compatible Datasource', () async {
      final created = await backend.execute(
        'tasks',
        ScrudOperation.create,
        id: 't1',
        data: {'title': 'Tâche 1', 'done': false},
      ) as Map<String, Object?>;
      expect(created['id'], 't1');

      final read = await backend.execute(
        'tasks',
        ScrudOperation.read,
        id: 't1',
      ) as Map<String, Object?>;
      expect(read['title'], 'Tâche 1');

      final updated = await backend.execute(
        'tasks',
        ScrudOperation.update,
        id: 't1',
        data: {'done': true},
        merge: true,
      ) as Map<String, Object?>;
      expect(updated['done'], isTrue);
      expect(updated['title'], 'Tâche 1');

      final search = await backend.execute(
        'tasks',
        ScrudOperation.search,
        parameters: {'done': true},
      ) as Map<String, Object?>;
      expect(search['total'], 1);
      expect((search['items'] as List).length, 1);

      final deleted = await backend.execute(
        'tasks',
        ScrudOperation.delete,
        id: 't1',
      );
      expect(deleted, isNull);
      expect(await backend.count('tasks'), 0);
    });

    test(
      'validations strictes (collection, id, payload, injection SQL)',
      () async {
        await expectLater(
          () => backend.read('bad collection!', '1'),
          throwsA(isA<InvalidCollectionException>()),
        );
        await expectLater(
          () => backend.read('clients', ''),
          throwsA(isA<InvalidEntityIdException>()),
        );
        await expectLater(
          () => clients.create({'bad': Object()}),
          throwsA(isA<InvalidJsonPayloadException>()),
        );
        await expectLater(
          () => clients.search(
            parameters: {'sort': "name'; DROP TABLE collection_entities;--"},
          ),
          throwsA(isA<InvalidQueryException>()),
        );
      },
    );
  });
}

void main() {
  _runScrudTests('Memory', MemoryCollectionStore.new);
  _runScrudTests('SQLite :memory:', SqliteCollectionStore.inMemory);
}
