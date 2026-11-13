import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/theme/appearance.dart';

class _CountingRepositoryStore extends JsonRepositoryStore {
  _CountingRepositoryStore(super.directory);

  int diskReadCount = 0;

  @override
  Future<String> read(String name) {
    diskReadCount++;
    return super.read(name);
  }
}

void main() {
  late Directory directory;
  late JsonRepositoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('json-repository-test-');
    store = JsonRepositoryStore(directory);
  });

  tearDown(() async => directory.delete(recursive: true));

  test('named JSON files survive a new store and can be renamed', () async {
    await store.create('Clients');
    await store.create('Articles');
    final id = await store.idOf('Clients');
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(await store.idOf('Articles'), isNot(id));
    expect(await store.list(), ['Articles', 'Clients']);
    final text = await store.read('Clients');
    await store.save('Clients', '{"clients": [1, 2]}', expectedText: text);
    final restored = JsonRepositoryStore(Directory(directory.path));
    expect(jsonDecode(await restored.read('Clients')), {
      'clients': [1, 2],
    });
    await restored.rename('Clients', 'Contacts');
    expect(await restored.list(), ['Articles', 'Contacts']);
    expect(await restored.read('Contacts'), '{"clients": [1, 2]}');
    expect(await restored.idOf('Contacts'), id);
    expect(await store.idOf('Contacts'), id);
    expect(await File('${directory.path}\\Clients.json').exists(), isFalse);
    expect(await File('${directory.path}\\Clients.json.id').exists(), isFalse);
  });

  test(
    'registered repositories stay in memory and support component bindings',
    () async {
      const id = 'pan_model_repository';
      final changes = <ChangeContext>[];
      store.registerRepository(
        RepositoryImpl(
          id: id,
          onChanged: changes.add,
          json: {
            'name': 'Demo',
            'nodes': [
              {'name': 'First'},
            ],
          },
        ),
      );

      expect(await store.idOf(id), id);
      expect(await store.readArray(id, 'nodes'), [
        {'name': 'First'},
      ]);

      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'name'),
        'Updated',
        expectedValue: 'Demo',
        componentId: 'name-value',
      );
      await store.appendArrayItem(
        id,
        'nodes',
        expectedLength: 1,
        componentId: 'nodes-list',
      );

      expect(
        await store.readAttribute(
          const JsonTextBinding(repositoryId: id, path: 'name'),
        ),
        (value: 'Updated', text: 'Updated'),
      );
      expect(await store.readArray(id, 'nodes'), [
        {'name': 'First'},
        {'name': ''},
      ]);
      expect(await File('${directory.path}\\$id.json').exists(), isFalse);
      expect(await store.catalog(), contains((name: id, id: id)));
      expect(changes, hasLength(2));
      expect(changes[0].repositoryId, id);
      expect(changes[0].path, 'name');
      expect(changes[0].oldValue, 'Demo');
      expect(changes[0].newValue, 'Updated');
      expect(changes[0].componentId, 'name-value');
      expect(changes[1].path, 'nodes');
      expect(changes[1].oldValue, [
        {'name': 'First'},
      ]);
      expect(changes[1].newValue, [
        {'name': 'First'},
        {'name': ''},
      ]);
      expect(changes[1].componentId, 'nodes-list');

      await store.replaceArray(id, 'nodes', [
        {'name': 'Replaced'},
      ], componentId: 'yaml-validator');
      expect(await store.readArray(id, 'nodes'), [
        {'name': 'Replaced'},
      ]);
      expect(changes, hasLength(3));
      expect(changes[2].path, 'nodes');
      expect(changes[2].newValue, [
        {'name': 'Replaced'},
      ]);
      expect(changes[2].componentId, 'yaml-validator');
    },
  );

  test(
    'persistent registered repositories save all mutation paths and restore',
    () async {
      const id = 'pan_model_repository';
      const name = JsonTextBinding(repositoryId: id, path: 'name');
      final file = File(
        '${directory.path}${Platform.pathSeparator}registered'
        '${Platform.pathSeparator}$id.json',
      );
      final changes = <ChangeContext>[];
      expect(
        await store.registerPersistentRepository(
          RepositoryImpl(
            id: id,
            json: {'name': 'Initial', 'nodes': <Object?>[]},
            onChanged: changes.add,
          ),
        ),
        isFalse,
      );
      expect(jsonDecode(await file.readAsString()), {
        'name': 'Initial',
        'nodes': <Object?>[],
      });
      expect(await store.catalog(), [(name: id, id: id)]);

      await store.writeAttribute(
        name,
        'Changed',
        expectedValue: 'Initial',
        componentId: 'name',
      );
      await store.replaceArray(id, 'nodes', [
        {'id': 'first'},
      ]);
      final previous = await store.read(id);
      await store.save(
        id,
        jsonEncode({
          'name': 'From document editor',
          'nodes': [
            {'id': 'second'},
          ],
        }),
        expectedText: previous,
      );
      await store.saveRepository(id);
      expect(jsonDecode(await file.readAsString()), {
        'name': 'From document editor',
        'nodes': [
          {'id': 'second'},
        ],
      });
      expect(changes.map((change) => change.path), ['name', 'nodes', '']);
      expect(changes.last.isReload, isFalse);
      expect(changes.last.oldValue, {
        'name': 'Changed',
        'nodes': [
          {'id': 'first'},
        ],
      });

      final restored = JsonRepositoryStore(directory);
      addTearDown(restored.dispose);
      expect(
        await restored.registerPersistentRepository(
          RepositoryImpl(id: id, json: {'name': 'Default'}),
        ),
        isTrue,
      );
      expect(
        (await restored.readAttribute(name)).value,
        'From document editor',
      );
      expect(await restored.readArray(id, 'nodes'), [
        {'id': 'second'},
      ]);
      expect(await restored.catalog(), [(name: id, id: id)]);
    },
  );

  test(
    'manual persistence protects unsaved changes and supports reload',
    () async {
      const id = 'pan_model_repository';
      const name = JsonTextBinding(repositoryId: id, path: 'name');
      final file = File(
        '${directory.path}${Platform.pathSeparator}registered'
        '${Platform.pathSeparator}$id.json',
      );
      final changes = <ChangeContext>[];
      await store.registerPersistentRepository(
        RepositoryImpl(
          id: id,
          json: {'name': 'Initial'},
          onChanged: changes.add,
        ),
        autoSave: false,
      );
      expect(await file.exists(), isFalse);
      await expectLater(
        store.loadRepository(id),
        throwsA(isA<FileSystemException>()),
      );
      await store.writeAttribute(name, 'Saved', expectedValue: 'Initial');
      await store.saveRepository(id);
      expect(jsonDecode(await file.readAsString()), {'name': 'Saved'});

      await store.writeAttribute(name, 'Unsaved', expectedValue: 'Saved');
      expect(jsonDecode(await file.readAsString()), {'name': 'Saved'});
      await expectLater(store.loadRepository(id), throwsFormatException);
      expect((await store.readAttribute(name)).value, 'Unsaved');
      await store.loadRepository(id, discardChanges: true);
      expect((await store.readAttribute(name)).value, 'Saved');
      expect(changes.last.path, '');
      expect(changes.last.isReload, isTrue);

      await file.writeAsString('{"name":"External"}');
      await store.loadRepository(id);
      expect((await store.readAttribute(name)).value, 'External');
      await store.writeAttribute(name, 'Local', expectedValue: 'External');
      await file.writeAsString('{"name":"External again"}');
      await expectLater(store.saveRepository(id), throwsFormatException);
      expect(await file.readAsString(), '{"name":"External again"}');
      await expectLater(store.loadRepository(id), throwsFormatException);
      await store.loadRepository(id, discardChanges: true);
      expect((await store.readAttribute(name)).value, 'External again');
    },
  );

  test('manual document save flushes drafts and persists explicitly', () async {
    const id = 'pan_model_repository';
    const other = JsonTextBinding(repositoryId: id, path: 'other');
    final file = File(
      '${directory.path}${Platform.pathSeparator}registered'
      '${Platform.pathSeparator}$id.json',
    );
    await store.registerPersistentRepository(
      RepositoryImpl(id: id, json: {'name': 'Initial'}),
      autoSave: false,
    );
    expect(store.isPersistentRepository(id), isTrue);
    final original = await store.read(id);
    var flushed = false;
    Future<void> pendingDraft() async {
      if (flushed) return;
      flushed = true;
      await store.writeAttribute(other, 'Pending', expectedValue: null);
    }

    store.addFlusher(pendingDraft);
    await expectLater(
      store.save(id, '{"name":"Editor"}', expectedText: original),
      throwsFormatException,
    );
    expect((await store.readAttribute(other)).value, 'Pending');
    expect(await file.exists(), isFalse);
    store.removeFlusher(pendingDraft);

    await store.save(
      id,
      '{"name":"Editor","other":"Pending"}',
      expectedText: await store.read(id),
    );
    expect(jsonDecode(await file.readAsString()), {
      'name': 'Editor',
      'other': 'Pending',
    });
    await store.save(
      id,
      '{"name":"Updated","other":"Pending"}',
      expectedText: '{"name":"Editor","other":"Pending"}',
    );
    expect(jsonDecode(await file.readAsString()), {
      'name': 'Updated',
      'other': 'Pending',
    });
  });

  test(
    'automatic persistence rejects external changes before mutation',
    () async {
      const id = 'pan_model_repository';
      const name = JsonTextBinding(repositoryId: id, path: 'name');
      final file = File(
        '${directory.path}${Platform.pathSeparator}registered'
        '${Platform.pathSeparator}$id.json',
      );
      final changes = <ChangeContext>[];
      await store.registerPersistentRepository(
        RepositoryImpl(
          id: id,
          json: {'name': 'Initial'},
          onChanged: changes.add,
        ),
      );
      await file.writeAsString('{"name":"External"}');

      await expectLater(
        store.writeAttribute(name, 'Local', expectedValue: 'Initial'),
        throwsFormatException,
      );
      expect((await store.readAttribute(name)).value, 'Initial');
      expect(changes, isEmpty);
      expect(await file.readAsString(), '{"name":"External"}');

      await store.loadRepository(id);
      expect(changes.single.path, '');
      await store.writeAttribute(name, 'Updated', expectedValue: 'External');
      expect(jsonDecode(await file.readAsString()), {'name': 'Updated'});
    },
  );

  test(
    'persistent registration reports corrupt files without overwriting',
    () async {
      const id = 'pan_model_repository';
      final file = File(
        '${directory.path}${Platform.pathSeparator}registered'
        '${Platform.pathSeparator}$id.json',
      );
      await file.parent.create(recursive: true);
      await file.writeAsString('{broken');
      final repository = RepositoryImpl(id: id, json: {'name': 'Default'});
      await expectLater(
        store.registerPersistentRepository(repository),
        throwsFormatException,
      );
      expect(await file.readAsString(), '{broken');
      expect(await store.list(), isEmpty);

      await file.writeAsString('[]');
      await expectLater(
        store.registerPersistentRepository(repository),
        throwsFormatException,
      );
      expect(await file.readAsString(), '[]');
      await file.writeAsString('{"name":"Recovered"}');
      await store.registerPersistentRepository(repository);
      expect(jsonDecode(await store.read(id)), {'name': 'Recovered'});
    },
  );

  test(
    'explicit save flushes bindings and registered deletion removes data',
    () async {
      const id = 'pan_model_repository';
      const name = JsonTextBinding(repositoryId: id, path: 'name');
      final file = File(
        '${directory.path}${Platform.pathSeparator}registered'
        '${Platform.pathSeparator}$id.json',
      );
      await store.registerPersistentRepository(
        RepositoryImpl(id: id, json: {'name': 'Initial', 'nodes': <Object?>[]}),
        autoSave: false,
      );
      var flushed = false;
      Future<void> flush() async {
        if (flushed) return;
        flushed = true;
        await store.writeAttribute(name, 'Flushed', expectedValue: 'Initial');
      }

      store.addFlusher(flush);
      await store.saveRepository(id);
      store.removeFlusher(flush);
      expect(jsonDecode(await file.readAsString()), {
        'name': 'Flushed',
        'nodes': <Object?>[],
      });

      final owner = Object();
      store.registerBindings(owner, [id]);
      await expectLater(store.delete(id), throwsFormatException);
      expect(await file.exists(), isTrue);
      store.unregisterBindings(owner);
      final array = store.bindingOf(id).array('nodes')..select(const [], 0);
      await store.delete(id);
      expect(array.indexFor(const []), isNull);
      expect(await file.exists(), isFalse);
      expect(await store.list(), isEmpty);
    },
  );

  test(
    'persistent mutations are serialized and reject invalid roots',
    () async {
      const id = 'pan_model_repository';
      const first = JsonTextBinding(repositoryId: id, path: 'first');
      const second = JsonTextBinding(repositoryId: id, path: 'second');
      final file = File(
        '${directory.path}${Platform.pathSeparator}registered'
        '${Platform.pathSeparator}$id.json',
      );
      await store.registerPersistentRepository(
        RepositoryImpl(id: id, json: {'first': 'A', 'second': 'B'}),
      );
      await Future.wait([
        store.writeAttribute(first, 'A1', expectedValue: 'A'),
        store.writeAttribute(second, 'B1', expectedValue: 'B'),
      ]);
      expect(jsonDecode(await file.readAsString()), {
        'first': 'A1',
        'second': 'B1',
      });
      final previous = await store.read(id);
      await expectLater(
        store.save(id, '[]', expectedText: previous),
        throwsFormatException,
      );
      expect(await store.read(id), previous);
      expect(jsonDecode(await file.readAsString()), {
        'first': 'A1',
        'second': 'B1',
      });
    },
  );

  test('conditional array replacement protects concurrent changes', () async {
    const id = 'pan_model_repository';
    const title = JsonTextBinding(repositoryId: id, path: 'nodes[0].title');
    const source = JsonTextBinding(repositoryId: id, path: 'source');
    store.registerRepository(
      RepositoryImpl(
        id: id,
        json: {
          'source': 'first',
          'nodes': [
            {'title': 'Initial'},
          ],
        },
      ),
    );
    final oldNodes = await store.readArray(id, 'nodes');
    await store.writeAttribute(title, 'Edited', expectedValue: 'Initial');
    await expectLater(
      store.replaceArray(
        id,
        'nodes',
        [
          {'title': 'Derived'},
        ],
        expectedValues: {'source': 'first', 'nodes': oldNodes},
      ),
      throwsA(isA<JsonRepositoryConflictException>()),
    );
    expect((await store.readAttribute(title)).value, 'Edited');

    final currentNodes = await store.readArray(id, 'nodes');
    await store.writeAttribute(source, 'second', expectedValue: 'first');
    await expectLater(
      store.replaceArray(
        id,
        'nodes',
        [
          {'title': 'Derived'},
        ],
        expectedValues: {'source': 'first', 'nodes': currentNodes},
      ),
      throwsA(isA<JsonRepositoryConflictException>()),
    );
    await store.replaceArray(
      id,
      'nodes',
      [
        {'title': 'Derived'},
      ],
      expectedValues: {'source': 'second', 'nodes': currentNodes},
    );
    expect((await store.readAttribute(title)).value, 'Derived');
  });

  test('persistent file errors do not commit an in-memory mutation', () async {
    const id = 'pan_model_repository';
    const name = JsonTextBinding(repositoryId: id, path: 'name');
    final file = File(
      '${directory.path}${Platform.pathSeparator}registered'
      '${Platform.pathSeparator}$id.json',
    );
    await store.registerPersistentRepository(
      RepositoryImpl(id: id, json: {'name': 'Initial'}),
    );
    await file.delete();
    await Directory(file.path).create();
    await expectLater(
      store.writeAttribute(name, 'Changed', expectedValue: 'Initial'),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.readAttribute(name)).value, 'Initial');
  });

  test(
    'persistent registration refuses a conflicting named repository',
    () async {
      const id = 'pan_model_repository';
      await store.create(id);
      await expectLater(
        store.registerPersistentRepository(
          RepositoryImpl(id: id, json: {'name': 'Initial'}),
        ),
        throwsFormatException,
      );
      expect(await store.read(id), '{}\n');
    },
  );

  test('delete removes JSON and ID files and clears array selection', () async {
    await store.create('Clients');
    await store.create('Articles');
    final id = await store.idOf('Clients');
    final array = store.bindingOf(id).array('items')..select(const [], 0);
    expect(array.indexFor(const []), 0);

    var notified = 0;
    store.addListener(() => notified++);

    await store.delete('Clients');

    expect(notified, 1);
    expect(await store.list(), ['Articles']);
    expect(await File('${directory.path}\\Clients.json').exists(), isFalse);
    expect(await File('${directory.path}\\Clients.json.id').exists(), isFalse);
    expect(array.indexFor(const []), isNull);

    // Can recreate a repository with the same name after deletion.
    await store.create('Clients');
    expect(await store.list(), ['Articles', 'Clients']);

    await expectLater(
      store.delete('Missing'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'delete refuses when repository is still used by an application bind',
    () async {
      await store.create('Clients');
      final id = await store.idOf('Clients');

      // Bound via Appearance
      final appearance = Appearance().withValueComponent(
        'v1',
        SuperValueConfig(
          binding: JsonTextBinding(repositoryId: id, path: 'nom'),
        ),
      );
      expect(appearance.usesRepository(id), isTrue);
      expect(
        await store.isRepositoryInUse('Clients', appearance: appearance),
        isTrue,
      );
      await expectLater(
        store.delete('Clients', appearance: appearance),
        throwsFormatException,
      );
      expect(await store.list(), ['Clients']);

      // Bound via active runtime binding
      final owner = Object();
      store.registerBindings(owner, [id]);
      expect(await store.isRepositoryInUse('Clients'), isTrue);
      await expectLater(store.delete('Clients'), throwsFormatException);
      expect(await store.list(), ['Clients']);

      // Unbound -> can delete
      store.unregisterBindings(owner);
      expect(await store.isRepositoryInUse('Clients'), isFalse);
      await store.delete('Clients', appearance: Appearance());
      expect(await store.list(), isEmpty);
    },
  );

  test('invalid JSON and duplicate names never overwrite documents', () async {
    await store.create('Clients');
    final original = await store.read('Clients');
    await expectLater(store.create('clients'), throwsFormatException);
    await expectLater(
      store.save('Clients', '{broken', expectedText: original),
      throwsFormatException,
    );
    await store.create('Contacts');
    await expectLater(
      store.rename('Contacts', 'Clients'),
      throwsFormatException,
    );
    expect(await store.read('Clients'), original);
    expect(await store.list(), ['Clients', 'Contacts']);
  });

  test('external edits are not overwritten', () async {
    await store.create('Clients');
    final original = await store.read('Clients');
    await File('${directory.path}\\Clients.json')
        .writeAsString('{"external":true}');
    await expectLater(
      store.save('Clients', '[]', expectedText: original),
      throwsFormatException,
    );
    expect(await store.read('Clients'), '{"external":true}');
  });

  test('existing invalid JSON can be read and repaired', () async {
    await File('${directory.path}\\Broken.json').writeAsString('{broken');
    final original = await store.read('Broken');
    final id = await store.idOf('Broken');
    expect(await store.read('Broken'), original);
    await store.save('Broken', 'null', expectedText: original);
    expect(await store.read('Broken'), 'null');
    expect(await JsonRepositoryStore(directory).idOf('Broken'), id);
  });

  test(
    'corrupt IDs are reported and never regenerated or overwritten',
    () async {
      await store.create('Clients');
      final metadata = File('${directory.path}\\Clients.json.id');
      await metadata.writeAsString('invalid-id');
      await expectLater(store.idOf('Clients'), throwsFormatException);
      await expectLater(
        store.save('Clients', '[]', expectedText: '{}\n'),
        throwsFormatException,
      );
      await expectLater(
        store.rename('Clients', 'Contacts'),
        throwsFormatException,
      );
      expect(await metadata.readAsString(), 'invalid-id');
      expect(await store.read('Clients'), '{}\n');
    },
  );

  test('orphan IDs are not reused for a different repository', () async {
    final metadata = File('${directory.path}\\Clients.json.id');
    await metadata.writeAsString('pan_model_repository');
    await expectLater(store.create('Clients'), throwsFormatException);
    await store.create('Contacts');
    await expectLater(
      store.rename('Contacts', 'Clients'),
      throwsFormatException,
    );
    expect(await store.list(), ['Contacts']);
    expect(await metadata.readAsString(), 'pan_model_repository');
  });

  test('rejects unsafe filenames', () {
    for (final name in [
      '',
      ' ',
      '..',
      '..\\escape',
      '../escape',
      'CON',
      'nul.data',
      'LPT1',
      'bad:name',
      'trailing.',
      'bad\nname',
    ]) {
      expect(
        () => JsonRepositoryStore.validateName(name),
        throwsFormatException,
      );
    }
    expect(JsonRepositoryStore.validateName(' Mes données '), 'Mes données');
  });

  test(
    'file errors propagate instead of returning an empty repository',
    () async {
      await expectLater(
        store.read('Missing'),
        throwsA(isA<FileSystemException>()),
      );
      final file = File('${directory.path}\\not-a-directory');
      await file.writeAsString('');
      await expectLater(
        JsonRepositoryStore(Directory(file.path)).list(),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('concurrent reads coalesce into a single disk read and populate synchronous peek caches', () async {
    await store.create('Clients');
    await store.create('Articles');
    final clientsId = await store.idOf('Clients');
    final original = await store.read('Clients');
    await store.save(
      'Clients',
      jsonEncode({
        'title': 'Directory',
        'items': [
          {'name': 'Alice'},
          {'name': 'Bob'},
        ],
        'tree': {
          'key': 'root',
          'children': [
            {'key': 'child'},
          ],
        },
      }),
      expectedText: original,
    );

    final coldStore = _CountingRepositoryStore(Directory(directory.path));
    addTearDown(coldStore.dispose);

    // Before loading, synchronous peeks return null.
    expect(
      coldStore.peekAttribute(
        JsonTextBinding(repositoryId: clientsId, path: 'title'),
      ),
      isNull,
    );
    expect(coldStore.peekArray(clientsId, 'items'), isNull);
    expect(coldStore.peekTreeNodes(clientsId, 'tree'), isNull);

    // 30 concurrent component reads on a cold store should only read the
    // target JSON file once from disk (and never read Articles.json).
    final results = await Future.wait([
      for (var i = 0; i < 10; i++)
        coldStore.readAttribute(
          JsonTextBinding(
            repositoryId: clientsId,
            path: 'items[${i % 2}].name',
          ),
        ),
      for (var i = 0; i < 10; i++) coldStore.readArray(clientsId, 'items'),
      for (var i = 0; i < 10; i++) coldStore.readTreeNodes(clientsId, 'tree'),
    ]);

    expect(results, hasLength(30));
    expect(coldStore.diskReadCount, 1);

    // Subsequent reads and synchronous peeks hit the in-memory cache with 0 disk reads.
    expect(
      coldStore
          .peekAttribute(
            JsonTextBinding(repositoryId: clientsId, path: 'title'),
          )
          ?.text,
      'Directory',
    );
    expect(coldStore.peekArray(clientsId, 'items'), hasLength(2));
    expect(
      coldStore.peekTreeNodes(clientsId, 'tree')?.singleRootObject,
      isTrue,
    );
    await coldStore.readAttribute(
      JsonTextBinding(repositoryId: clientsId, path: 'items[0].name'),
    );
    expect(coldStore.diskReadCount, 1);

    // invalidateCache forces the next read to reload from disk.
    coldStore.invalidateCache(clientsId);
    expect(coldStore.peekArray(clientsId, 'items'), isNull);
    await coldStore.preload();
    expect(coldStore.peekArray(clientsId, 'items'), hasLength(2));
  });

  test(
    'readDocument returns a deep copy and peekDocument reads the cache',
    () async {
      await store.create('Filtre');
      final id = await store.idOf('Filtre');
      await store.save(
        'Filtre',
        '{"q": "a", "tags": ["x"]}',
        expectedText: await store.read('Filtre'),
      );

      final cold = JsonRepositoryStore(Directory(directory.path));
      addTearDown(cold.dispose);
      expect(cold.peekDocument(id), isNull);

      final copy = await cold.readDocument(id) as Map<String, dynamic>;
      expect(copy, {
        'q': 'a',
        'tags': ['x'],
      });
      (copy['tags'] as List).add('y');
      expect(cold.peekDocument(id)?.document, {
        'q': 'a',
        'tags': ['x'],
      });

      await expectLater(cold.readDocument('INVALIDE'), throwsFormatException);
      await expectLater(cold.readDocument('0' * 32), throwsFormatException);
    },
  );
}
