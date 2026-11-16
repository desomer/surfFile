import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:super_backend/super_backend.dart';
import 'package:test/test.dart';

void _runStoreContractTests(String label, CollectionStore Function() factory) {
  group('Contrat CollectionStore ($label)', () {
    late CollectionStore store;

    setUp(() async {
      store = factory();
      await store.init();
    });

    tearDown(() async {
      await store.close();
    });

    test('insert, findById, conflit d’identifiant et upsert', () async {
      final row1 = StoredJsonRow(
        nomCollection: 'clients',
        idEntity: 'c1',
        dataJson: jsonEncode({'id': 'c1', 'name': 'Alice'}),
      );
      await store.insert(row1);

      final found = await store.findById('clients', 'c1');
      expect(found, equals(row1));
      expect(await store.findById('clients', 'missing'), isNull);

      await expectLater(
        () => store.insert(row1),
        throwsA(isA<EntityAlreadyExistsException>()),
      );

      final row1Updated = StoredJsonRow(
        nomCollection: 'clients',
        idEntity: 'c1',
        dataJson: jsonEncode({'id': 'c1', 'name': 'Alice Bis'}),
      );
      await store.upsert(row1Updated);
      expect(await store.findById('clients', 'c1'), equals(row1Updated));
    });

    test('update et delete retournent un booléen fiable', () async {
      final row = StoredJsonRow(
        nomCollection: 'orders',
        idEntity: 'o1',
        dataJson: jsonEncode({'id': 'o1', 'total': 42}),
      );
      expect(await store.update(row), isFalse);
      expect(await store.delete('orders', 'o1'), isFalse);

      await store.insert(row);
      final updated = StoredJsonRow(
        nomCollection: 'orders',
        idEntity: 'o1',
        dataJson: jsonEncode({'id': 'o1', 'total': 99}),
      );
      expect(await store.update(updated), isTrue);
      expect((await store.findById('orders', 'o1'))?.decodeData()['total'], 99);

      expect(await store.delete('orders', 'o1'), isTrue);
      expect(await store.findById('orders', 'o1'), isNull);
    });

    test(
      'isolation par nom_collection, count, listCollections et clear',
      () async {
        await store.insert(
          StoredJsonRow(
            nomCollection: 'clients',
            idEntity: 'shared-id',
            dataJson: jsonEncode({'kind': 'client'}),
          ),
        );
        await store.insert(
          StoredJsonRow(
            nomCollection: 'products',
            idEntity: 'shared-id',
            dataJson: jsonEncode({'kind': 'product'}),
          ),
        );

        expect(
          (await store.findById('clients', 'shared-id'))?.decodeData()['kind'],
          'client',
        );
        expect(
          (await store.findById('products', 'shared-id'))?.decodeData()['kind'],
          'product',
        );
        expect(await store.count('clients'), 1);
        expect(await store.count('products'), 1);
        expect(await store.listCollections(), ['clients', 'products']);

        expect(await store.clearCollection('clients'), 1);
        expect(await store.count('clients'), 0);
        expect(await store.listCollections(), ['products']);
      },
    );

    test('cycle de vie init / close', () async {
      final fresh = factory();
      await expectLater(
        () => fresh.count('clients'),
        throwsA(isA<BackendNotInitializedException>()),
      );
      await fresh.init();
      await fresh.init();
      expect(await fresh.count('clients'), 0);
      await fresh.close();
      await expectLater(
        () => fresh.count('clients'),
        throwsA(isA<BackendNotInitializedException>()),
      );
      await expectLater(
        () => fresh.init(),
        throwsA(isA<BackendNotInitializedException>()),
      );
    });
  });
}

void main() {
  _runStoreContractTests('Memory', MemoryCollectionStore.new);
  _runStoreContractTests('SQLite :memory:', SqliteCollectionStore.inMemory);

  test('SqliteCollectionStore crée la table (nom_collection, id_entity, data_json)', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'super_backend_schema_',
    );
    final dbPath = '${tempDir.path}${Platform.pathSeparator}schema.db';
    final store = SqliteCollectionStore(dbPath);
    try {
      await store.init();
      await store.close();

      final db = sqlite3.open(dbPath);
      try {
        final cols = db.select(
          "PRAGMA table_info('${SqliteCollectionStore.defaultTableName}');",
        );
        final names = [for (final row in cols) row['name'] as String];
        expect(names, ['nom_collection', 'id_entity', 'data_json']);
      } finally {
        db.close();
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
