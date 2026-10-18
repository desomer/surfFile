import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/services/json_repository_store.dart';

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
    await metadata.writeAsString('0123456789abcdef0123456789abcdef');
    await expectLater(store.create('Clients'), throwsFormatException);
    await store.create('Contacts');
    await expectLater(
      store.rename('Contacts', 'Clients'),
      throwsFormatException,
    );
    expect(await store.list(), ['Contacts']);
    expect(await metadata.readAsString(), '0123456789abcdef0123456789abcdef');
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
}
