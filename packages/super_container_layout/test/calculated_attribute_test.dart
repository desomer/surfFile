import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/services/repositories/calculated_attribute.dart';
import 'package:super_container_layout/services/repositories/json_list_scope.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';

class _DelayedRepositoryStore extends JsonRepositoryStore {
  _DelayedRepositoryStore(super.directory);

  Completer<void>? pause;
  final readStarted = Completer<void>();
  final readFinished = Completer<void>();

  @override
  Future<String> read(String name) async {
    final value = await super.read(name);
    final gate = pause;
    if (gate != null) {
      pause = null;
      readStarted.complete();
      await gate.future;
      readFinished.complete();
    }
    return value;
  }
}

void main() {
  late Directory directory;
  late JsonRepositoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('calculated-attr-test-');
    store = JsonRepositoryStore(directory);
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  const id = 'calc_repository';
  const totalBinding = JsonTextBinding(repositoryId: id, path: '@total');

  Future<Object?> read(String path, {String repositoryId = id}) async =>
      (await store.readAttribute(
        JsonTextBinding(repositoryId: repositoryId, path: path),
      )).value;

  test(
    'invalidated async readers join the newest generation immediately',
    () async {
      final gates = [Completer<void>(), Completer<void>()];
      final started = [Completer<void>(), Completer<void>()];
      late Future<int?> oldFuture;
      var calls = 0;
      final repository = RepositoryImpl(id: id, json: {'a': 1});
      repository.addCalculatedAttribute('total', (ctx) {
        final generation = calls++;
        final value = ctx.sync.getInt('a');
        started[generation].complete();
        final result = gates[generation].future.then((_) => value);
        if (generation == 0) oldFuture = result;
        return result;
      });
      store.registerRepository(repository);
      var notifications = 0;
      store.addListener(() => notifications++);
      final first = read('@total');
      final second = read('@total');
      await started[0].future;
      expect(calls, 1);
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'a'),
        '2',
        expectedValue: 1,
      );
      await started[1].future;
      gates[1].complete();
      expect(await first, 2);
      expect(await second, 2);
      expect(await read('@total'), 2);
      final currentNotifications = notifications;
      gates[0].complete();
      await oldFuture;
      expect(await read('@total'), 2);
      expect(calls, 2);
      expect(notifications, currentNotifications);
    },
  );

  test('late async reads cannot mix document generations', () async {
    final gate = Completer<void>();
    var calls = 0;
    final repository = RepositoryImpl(id: id, json: {'a': 1});
    repository.addCalculatedAttribute('total', (ctx) async {
      calls++;
      await gate.future;
      return ctx.getInt('a');
    });
    store.registerRepository(repository);
    final pending = read('@total');
    await store.writeAttribute(
      const JsonTextBinding(repositoryId: id, path: 'a'),
      '2',
      expectedValue: 1,
    );
    gate.complete();
    expect(await pending, 2);
    expect(calls, 2);
  });

  test('calculated tree bindings resolve the concrete recursive node', () {
    const scope = JsonListScope(
      repositoryId: id,
      indices: [0],
      nodePath: '@tree[0].children[1]',
      treeTemplatePath: '@tree',
      child: SizedBox.shrink(),
    );
    final result = JsonListScope.resolve(
      const JsonTextBinding(path: '@tree[?].name'),
      scope,
    );
    expect(result.path, '@tree[0].children[1].name');
    expect(result.repositoryId, id);
    expect(
      JsonListScope.resolve(
        const JsonTextBinding(path: '@stats.total'),
        scope,
      ).path,
      '@stats.total',
    );
    expect(JsonTextBinding.fromJson(result.toJson()), result);
  });

  test(
    'deleting a repository releases readers of its pending calculation',
    () async {
      final gate = Completer<int>();
      final repository = RepositoryImpl(id: id, json: {});
      repository.addCalculatedAttribute('total', (_) => gate.future);
      store.registerRepository(repository);
      final pending = read('@total');
      final expectation = expectLater(pending, throwsFormatException);
      await store.delete(id);
      await expectation;
      gate.complete(8);
      expect(store.calculatedAttributeCatalog(id), isEmpty);
      expect(store.peekAttribute(totalBinding), isNull);
    },
  );

  test('concurrent asynchronous cycles fail instead of deadlocking', () async {
    final gate = Completer<void>();
    final repository = RepositoryImpl(id: id, json: {});
    repository.addCalculatedAttribute('first', (ctx) async {
      await gate.future;
      return ctx.getValue('@second');
    });
    repository.addCalculatedAttribute('second', (ctx) async {
      await gate.future;
      return ctx.getValue('@first');
    });
    store.registerRepository(repository);
    final expectations = [
      expectLater(read('@first'), throwsFormatException),
      expectLater(read('@second'), throwsFormatException),
    ];
    gate.complete();
    await Future.wait(expectations);
  });

  test(
    'async errors are cached until explicit refresh or dependency changes',
    () async {
      var calls = 0;
      var fail = true;
      final repository = RepositoryImpl(id: id, json: {'a': 1});
      repository.addCalculatedAttribute('total', (ctx) async {
        calls++;
        final value = ctx.sync.getInt('a');
        if (fail) throw const FormatException('Calcul indisponible.');
        return value;
      });
      store.registerRepository(repository);
      var notifications = 0;
      store.addListener(() => notifications++);
      await expectLater(read('@total'), throwsFormatException);
      final initialNotifications = notifications;
      expect(store.peekAttribute(totalBinding), isNull);
      await expectLater(read('@total'), throwsFormatException);
      expect(calls, 1);
      expect(notifications, initialNotifications);
      fail = false;
      expect((await store.refreshCalculatedAttribute(totalBinding)).value, 1);
      expect(calls, 2);
      fail = true;
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'a'),
        '2',
        expectedValue: 1,
      );
      await expectLater(read('@total'), throwsFormatException);
      expect(calls, 3);
    },
  );

  test('defaults and sync getters preserve dependency tracking and errors', () async {
    final repository = RepositoryImpl(id: id, json: {'bad': 'not a number'});
    repository.addCalculatedAttribute(
      'total',
      (ctx) =>
          (ctx.sync.getNum('missing', defaultValue: 3) ?? 0) +
          (ctx.sync.getInt('count', defaultValue: 2) ?? 0),
    );
    repository.addCalculatedAttribute(
      'defaults',
      (ctx) => [
        ctx.sync.getString('missing', defaultValue: 'none'),
        ctx.sync.getDouble('missing', defaultValue: 0.5),
        ctx.sync.getBool('missing', defaultValue: false),
        ctx.sync.getValue('missing'),
      ],
    );
    repository.addCalculatedAttribute(
      'invalid',
      (ctx) => ctx.getNum('bad', defaultValue: 0),
    );
    store.registerRepository(repository);
    expect(await read('@total'), 5);
    expect(await read('@defaults'), ['none', 0.5, false, null]);
    await expectLater(read('@invalid'), throwsFormatException);
    await store.writeAttribute(
      const JsonTextBinding(repositoryId: id, path: 'missing'),
      'new',
      expectedValue: null,
    );
    // L'ajout d'une valeur de mauvais type ne conserve pas le défaut en cache.
    await expectLater(read('@total'), throwsFormatException);
  });

  test(
    'sync facade rejects pending async values but accepts cached values',
    () async {
      final gate = Completer<int>();
      final repository = RepositoryImpl(id: id, json: {});
      repository.addCalculatedAttribute('source', (_) => gate.future);
      repository.addCalculatedAttribute(
        'total',
        (ctx) => ctx.sync.getNum('@source', defaultValue: 0),
      );
      store.registerRepository(repository);
      await expectLater(read('@total'), throwsFormatException);
      gate.complete(8);
      expect(await read('@source'), 8);
      expect((await store.refreshCalculatedAttribute(totalBinding)).value, 8);
    },
  );

  test(
    'structured calculated paths support arrays trees and master detail',
    () async {
      final repository = RepositoryImpl(id: id, json: {});
      repository.addCalculatedAttribute('stats', (_) => {'total': 4});
      repository.addCalculatedAttribute(
        'items',
        (_) => [
          {'name': 'Alice'},
          {'name': 'Bob'},
        ],
      );
      repository.addCalculatedAttribute(
        'tree',
        (_) => {
          'name': 'root',
          'children': [
            {'name': 'child'},
          ],
        },
      );
      store.registerRepository(repository);
      expect(await read('@stats.total'), 4);
      expect(await read('@items[1].name'), 'Bob');
      expect((await store.readTreeNodes(id, '@tree')).singleRootObject, isTrue);
      expect(store.peekTreeNodes(id, '@items')?.nodes, hasLength(2));
      store.bindingOf(id).array('@items').select([], 1);
      final resolved = JsonListScope.resolveSelected(
        const JsonTextBinding(repositoryId: id, path: '@items[?].name'),
        null,
        store,
      );
      expect(resolved.binding?.path, '@items[1].name');
      expect(await read(resolved.binding!.path), 'Bob');
      await expectLater(
        store.writeAttribute(
          resolved.binding!,
          'Changed',
          expectedValue: 'Bob',
        ),
        throwsFormatException,
      );
      for (final path in ['@stats.@bad', 'items.@', '@bad-name']) {
        expect(
          () => JsonTextBinding(repositoryId: id, path: path).validate(),
          throwsFormatException,
        );
      }
      const binding = JsonTextBinding(path: '@items[?].name');
      expect(JsonTextBinding.fromJson(binding.toCompactJson()), binding);
    },
  );

  test(
    'row calculations use independent caches and follow array reindexing',
    () async {
      final calls = <String, int>{};
      final repository = RepositoryImpl(
        id: id,
        json: {
          'articles': [
            {'prix': 3, 'quantite': 2},
            {'prix': 7, 'quantite': 1},
          ],
        },
      );
      repository.addCalculatedAttribute('montant', (ctx) {
        calls.update(ctx.scopePath, (value) => value + 1, ifAbsent: () => 1);
        return ctx.sync.getNum('prix')! * ctx.sync.getInt('quantite')!;
      }, scope: 'articles[?]');
      store.registerRepository(repository);
      expect(await read('articles[0].@montant'), 6);
      expect(await read('articles[1].@montant'), 7);
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'articles[0].prix'),
        '4',
        expectedValue: 3,
      );
      expect(await read('articles[0].@montant'), 8);
      expect(await read('articles[1].@montant'), 7);
      expect(calls, {'articles[0]': 2, 'articles[1]': 1});
      await store.removeArrayItem(
        id,
        'articles',
        0,
        expectedItem: {'prix': 4, 'quantite': 2},
      );
      expect(await read('articles[0].@montant'), 7);
      await expectLater(read('articles[1].@montant'), throwsFormatException);
    },
  );

  test(
    'nested scopes resolve wildcard root reads and keep catalog lazy',
    () async {
      var calls = 0;
      final repository = RepositoryImpl(
        id: id,
        json: {
          'orders': [
            {
              'discount': 2,
              'items': [
                {'price': 9},
              ],
            },
          ],
        },
      );
      repository.addCalculatedAttribute('stats', (ctx) {
        calls++;
        return {
          'total':
              ctx.sync.getNum('price')! -
              ctx.sync.getNum(
                'orders[?].discount',
                repositoryId: ctx.repositoryId,
              )!,
        };
      }, scope: 'orders[?].items[?]');
      store.registerRepository(repository);
      final catalog = store.calculatedAttributeCatalog(id);
      expect(catalog.single.path, 'orders[?].items[?].@stats');
      expect(
        store.hasCalculatedAttribute(id, 'orders[0].items[0].@stats.total'),
        isTrue,
      );
      expect(calls, 0);
      expect(await read('orders[0].items[0].@stats.total'), 7);
      expect(() => catalog.clear(), throwsUnsupportedError);
    },
  );

  test(
    'cross repository changes invalidate only dependent calculations',
    () async {
      final calls = <String, int>{};
      final repository = RepositoryImpl(id: id, json: {'local': 4});
      repository.addCalculatedAttribute('total', (ctx) {
        calls.update('total', (v) => v + 1, ifAbsent: () => 1);
        return ctx.getNum('tax', repositoryId: 'rates');
      });
      repository.addCalculatedAttribute('local', (ctx) {
        calls.update('local', (v) => v + 1, ifAbsent: () => 1);
        return ctx.getInt('local');
      });
      store.registerRepository(repository);
      store.registerRepository(RepositoryImpl(id: 'rates', json: {'tax': 2}));
      expect(await read('@total'), 2);
      expect(await read('@local'), 4);
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: 'rates', path: 'tax'),
        '3',
        expectedValue: 2,
      );
      expect(await read('@total'), 3);
      expect(await read('@local'), 4);
      expect(calls, {'total': 2, 'local': 1});
      await store.delete('rates');
      await expectLater(read('@total'), throwsFormatException);
      store.registerRepository(RepositoryImpl(id: 'rates', json: {'tax': 5}));
      expect(await read('@total'), 5);
    },
  );

  test(
    'missing repositories invalidate cached errors when registered',
    () async {
      final repository = RepositoryImpl(id: id, json: {});
      repository.addCalculatedAttribute(
        'total',
        (ctx) => ctx.getNum('value', repositoryId: 'missing', defaultValue: 9),
      );
      store.registerRepository(repository);
      await expectLater(read('@total'), throwsFormatException);
      store.registerRepository(
        RepositoryImpl(id: 'missing', json: {'value': 2}),
      );
      expect(await read('@total'), 2);
    },
  );

  test('cycles crossing repositories are detected', () async {
    final first = RepositoryImpl(id: id, json: {});
    first.addCalculatedAttribute(
      'total',
      (ctx) => ctx.getValue('@other', repositoryId: 'second'),
    );
    final second = RepositoryImpl(id: 'second', json: {});
    second.addCalculatedAttribute(
      'other',
      (ctx) => ctx.getValue('@total', repositoryId: id),
    );
    store.registerRepository(first);
    store.registerRepository(second);
    await expectLater(read('@total'), throwsFormatException);
  });

  test(
    'calculated collections and context data are deeply immutable',
    () async {
      final repository = RepositoryImpl(
        id: id,
        json: {
          'items': [
            {'value': 1},
          ],
        },
      );
      repository.addCalculatedAttribute(
        'items',
        (ctx) => ctx.getValue('items'),
      );
      store.registerRepository(repository);
      final result = await store.readArray(id, '@items');
      expect(() => (result.first as Map)['value'] = 5, throwsUnsupportedError);
      expect(await read('items[0].value'), 1);
      final frozen = RepositoryImpl(
        id: 'frozen',
        json: {
          'items': [1],
        },
      );
      frozen.addCalculatedAttribute('invalid', (ctx) {
        (ctx.sync.getValue('items') as List).add(2);
        return 0;
      });
      store.registerRepository(frozen);
      await expectLater(
        read('@invalid', repositoryId: 'frozen'),
        throwsFormatException,
      );
    },
  );

  test('ordinary JSON marker collisions are reported explicitly', () async {
    final repository = RepositoryImpl(id: id, json: {'@total': 5});
    repository.addCalculatedAttribute('total', (_) => 2);
    store.registerRepository(repository);
    await expectLater(
      read('@total'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Collision'),
        ),
      ),
    );
  });

  test(
    'disposing a store resolves pending readers with an explicit error',
    () async {
      final other = JsonRepositoryStore(directory);
      final gate = Completer<int>();
      final repository = RepositoryImpl(id: id, json: {});
      repository.addCalculatedAttribute('total', (_) => gate.future);
      other.registerRepository(repository);
      final pending = other.readAttribute(totalBinding);
      final expectation = expectLater(pending, throwsFormatException);
      other.dispose();
      await expectation;
      gate.complete(1);
    },
  );

  test(
    'conditional dependencies are replaced and equal writes keep caches',
    () async {
      var calls = 0;
      final repository = RepositoryImpl(
        id: id,
        json: {'useA': true, 'a': 1, 'b': 2},
      );
      repository.addCalculatedAttribute('total', (ctx) {
        calls++;
        return ctx.sync.getInt(ctx.sync.getBool('useA')! ? 'a' : 'b');
      });
      store.registerRepository(repository);
      expect(await read('@total'), 1);
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'a'),
        '1',
        expectedValue: 1,
      );
      expect(await read('@total'), 1);
      expect(calls, 1);
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'useA'),
        'false',
        expectedValue: true,
        asBool: true,
      );
      expect(await read('@total'), 2);
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'a'),
        '3',
        expectedValue: 1,
      );
      expect(await read('@total'), 2);
      expect(calls, 2);
    },
  );

  test(
    'file source writes preserve unrelated caches and cache reloads refresh',
    () async {
      await store.create('rates');
      await store.save(
        'rates',
        '{"a": 1, "b": 2}',
        expectedText: await store.read('rates'),
      );
      final sourceId = await store.idOf('rates');
      final calls = <String, int>{};
      final repository = RepositoryImpl(id: id, json: {});
      for (final name in ['a', 'b']) {
        repository.addCalculatedAttribute(name, (ctx) {
          calls.update(name, (v) => v + 1, ifAbsent: () => 1);
          return ctx.getNum(name, repositoryId: sourceId);
        });
      }
      store.registerRepository(repository);
      expect(await read('@a'), 1);
      expect(await read('@b'), 2);
      final sourceBinding = JsonTextBinding(repositoryId: sourceId, path: 'a');
      await store.writeAttribute(sourceBinding, '3', expectedValue: 1);
      expect(await read('@a'), 3);
      expect(await read('@b'), 2);
      expect(calls, {'a': 2, 'b': 1});
      await store.writeAttribute(sourceBinding, '3', expectedValue: 3);
      expect(await read('@a'), 3);
      expect(calls['a'], 2);
      await File('${directory.path}${Platform.pathSeparator}rates.json')
          .writeAsString('{"a": 4, "b": 5}');
      store.invalidateCache(sourceId);
      expect(await read('@a'), 4);
      expect(await read('@b'), 5);
    },
  );

  test('stale file loads cannot repopulate current document caches', () async {
    final delayed = _DelayedRepositoryStore(directory);
    addTearDown(delayed.dispose);
    await delayed.create('rates');
    await delayed.save(
      'rates',
      '{"a": 1}',
      expectedText: await delayed.read('rates'),
    );
    final sourceId = await delayed.idOf('rates');
    final repository = RepositoryImpl(id: id, json: {});
    repository.addCalculatedAttribute(
      'total',
      (ctx) => ctx.getNum('a', repositoryId: sourceId),
    );
    delayed.registerRepository(repository);
    delayed.invalidateCache(sourceId);
    final gate = Completer<void>();
    delayed.pause = gate;
    final pending = delayed.readAttribute(totalBinding);
    await delayed.readStarted.future;
    final sourceBinding = JsonTextBinding(repositoryId: sourceId, path: 'a');
    await delayed.writeAttribute(sourceBinding, '2', expectedValue: 1);
    expect((await pending).value, 2);
    gate.complete();
    await delayed.readFinished.future;
    await Future<void>.value();
    expect((await delayed.readAttribute(sourceBinding)).value, 2);
    expect((await delayed.readAttribute(totalBinding)).value, 2);
  });

  test(
    'separate stores never share calculated caches or invalidations',
    () async {
      final secondStore = JsonRepositoryStore(directory);
      addTearDown(secondStore.dispose);
      var calls = 0;
      RepositoryImpl repository() =>
          RepositoryImpl(id: id, json: {})
            ..addCalculatedAttribute('total', (ctx) {
              calls++;
              return ctx.getInt('value', repositoryId: 'source');
            });
      store.registerRepository(repository());
      secondStore.registerRepository(repository());
      store.registerRepository(
        RepositoryImpl(id: 'source', json: {'value': 1}),
      );
      secondStore.registerRepository(
        RepositoryImpl(id: 'source', json: {'value': 2}),
      );
      expect(await read('@total'), 1);
      expect((await secondStore.readAttribute(totalBinding)).value, 2);
      await secondStore.writeAttribute(
        const JsonTextBinding(repositoryId: 'source', path: 'value'),
        '3',
        expectedValue: 2,
      );
      expect(await read('@total'), 1);
      expect((await secondStore.readAttribute(totalBinding)).value, 3);
      expect(calls, 3);
    },
  );

  test(
    'persistent registration retains scoped functions after reload',
    () async {
      final repository = RepositoryImpl(
        id: id,
        json: {
          'items': [
            {'price': 3},
          ],
        },
      );
      repository.addCalculatedAttribute(
        'cost',
        (ctx) => ctx.sync.getInt('price'),
        scope: 'items[?]',
      );
      await store.registerPersistentRepository(repository);
      expect(await read('items[0].@cost'), 3);
      await File(
        '${directory.path}${Platform.pathSeparator}registered'
        '${Platform.pathSeparator}$id.json',
      ).writeAsString('{"items":[{"price":7}]}');
      await store.loadRepository(id);
      expect(await read('items[0].@cost'), 7);
      expect(store.calculatedAttributeCatalog(id).single.scope, 'items[?]');
    },
  );

  test('typed getters preserve synchronous values and numeric types', () {
    final repository = RepositoryImpl(
      id: id,
      json: {
        'client': {'nom': 'Alice'},
        'integer': 2,
        'decimal': 2.5,
        'enabled': false,
        'empty': '',
        'zero': 0,
      },
    );
    repository.addCalculatedAttribute(
      'values',
      (ctx) => [
        ctx.getString('client.nom'),
        ctx.getNum('integer'),
        ctx.getNum('decimal'),
        ctx.getInt('integer'),
        ctx.getDouble('integer'),
        ctx.getDouble('decimal'),
        ctx.getBool('enabled'),
        ctx.getString('empty'),
        ctx.getInt('zero'),
      ],
    );
    store.registerRepository(repository);

    final values = store
        .peekAttribute(const JsonTextBinding(repositoryId: id, path: '@values'))
        ?.value;
    expect(values, ['Alice', 2, 2.5, 2, 2.0, 2.5, false, '', 0]);
    expect((values as List<Object?>)[4], isA<double>());
  });

  final typedReaders = <String, CalculatedAttributeFunction Function(String)>{
    'string': (path) =>
        (ctx) => ctx.getString(path),
    'num': (path) =>
        (ctx) => ctx.getNum(path),
    'int': (path) =>
        (ctx) => ctx.getInt(path),
    'double': (path) =>
        (ctx) => ctx.getDouble(path),
    'bool': (path) =>
        (ctx) => ctx.getBool(path),
    'list': (path) =>
        (ctx) => ctx.getList(path),
    'object': (path) =>
        (ctx) => ctx.getObject(path),
  };
  final typedValues = <String, Object>{
    'string': 'Alice',
    'num': 2.5,
    'int': 2,
    'double': 2.0,
    'bool': false,
    'list': [
      {'name': 'Alice', 'optional': null},
    ],
    'object': {'name': 'Alice'},
  };

  for (final entry in typedReaders.entries) {
    test(
      '${entry.key} getter preserves null and rejects incompatible values',
      () async {
        final repository = RepositoryImpl(id: id, json: {'value': null});
        repository.addCalculatedAttribute('typed', entry.value('value'));
        store.registerRepository(repository);
        const binding = JsonTextBinding(repositoryId: id, path: '@typed');

        expect((await store.readAttribute(binding)).value, isNull);
        await store.save(id, '{}', expectedText: await store.read(id));
        expect((await store.readAttribute(binding)).value, isNull);

        // Une chaîne numérique ne devient pas un nombre ni un booléen.
        final invalidValue = entry.key == 'string' ? '42' : '"42"';
        await store.save(
          id,
          '{"value": $invalidValue}',
          expectedText: await store.read(id),
        );
        await expectLater(
          store.readAttribute(binding),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              allOf(contains('value'), contains('type')),
            ),
          ),
        );
      },
    );

    test(
      '${entry.key} getter supports asynchronous calculated dependencies',
      () async {
        final repository = RepositoryImpl(
          id: id,
          json: {'value': typedValues[entry.key]},
        );
        repository.addCalculatedAttribute('source', (ctx) async {
          await Future<void>.delayed(Duration.zero);
          return ctx.getValue('value');
        });
        repository.addCalculatedAttribute('typed', entry.value('@source'));
        store.registerRepository(repository);
        const binding = JsonTextBinding(repositoryId: id, path: '@typed');

        expect(store.peekAttribute(binding), isNull);
        expect(
          (await store.readAttribute(binding)).value,
          typedValues[entry.key],
        );
        await store.save(
          id,
          '{"value": null}',
          expectedText: await store.read(id),
        );
        expect((await store.readAttribute(binding)).value, isNull);
        await store.save(
          id,
          '{"value": ${entry.key == 'list' ? '{}' : '[]'}}',
          expectedText: await store.read(id),
        );
        await expectLater(
          store.readAttribute(binding),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              allOf(contains('@source'), contains('type')),
            ),
          ),
        );
      },
    );
  }

  test('collection getters support immediate values and typed defaults', () {
    final repository = RepositoryImpl(
      id: id,
      json: {
        'items': [
          {'value': 1},
        ],
        'emptyList': [],
        'profile': {'name': 'Alice'},
        'empty': null,
      },
    );
    repository.addCalculatedAttribute(
      'collections',
      (ctx) => {
        'list': ctx.getList('items'),
        'object': ctx.getObject('profile'),
        'syncList': ctx.sync.getList('items'),
        'emptyList': ctx.getList('emptyList'),
        'syncEmptyList': ctx.sync.getList('emptyList'),
        'syncObject': ctx.sync.getObject('profile'),
        'listDefault': ctx.getList(
          'empty',
          defaultValue: const [
            {'value': 2},
          ],
        ),
        'objectDefault': ctx.getObject(
          'empty',
          defaultValue: const {'value': 2},
        ),
        'syncListDefault': ctx.sync.getList(
          'missing',
          defaultValue: const [
            {'value': 3},
          ],
        ),
        'syncObjectDefault': ctx.sync.getObject(
          'missing',
          defaultValue: const {'value': 3},
        ),
        'syncMissingList': ctx.sync.getList('missing'),
        'syncMissingObject': ctx.sync.getObject('missing'),
      },
    );
    store.registerRepository(repository);
    expect(
      store
          .peekAttribute(
            const JsonTextBinding(repositoryId: id, path: '@collections'),
          )
          ?.value,
      {
        'list': [
          {'value': 1},
        ],
        'object': {'name': 'Alice'},
        'syncList': [
          {'value': 1},
        ],
        'emptyList': [],
        'syncEmptyList': [],
        'syncObject': {'name': 'Alice'},
        'listDefault': [
          {'value': 2},
        ],
        'objectDefault': {'value': 2},
        'syncListDefault': [
          {'value': 3},
        ],
        'syncObjectDefault': {'value': 3},
        'syncMissingList': null,
        'syncMissingObject': null,
      },
    );
  });

  test(
    'list getters eagerly reject non-object elements without fallback',
    () async {
      final invalidLists = <List<Object?>>[
        [1],
        [null],
        [
          {'value': 1},
          'invalid',
        ],
        [<Object?>[]],
        [
          <Object?, Object?>{1: 'invalid'},
        ],
      ];
      final repository = RepositoryImpl(id: id, json: {});
      for (var index = 0; index < invalidLists.length; index++) {
        final source = '@source_$index';
        final value = invalidLists[index];
        repository.addCalculatedAttribute('source_$index', (_) => value);
        repository.addCalculatedAttribute(
          'count_$index',
          (ctx) async =>
              (await ctx.getList(source, defaultValue: const []))!.length,
        );
        repository.addCalculatedAttribute(
          'sync_count_$index',
          (ctx) => ctx.sync.getList(source, defaultValue: const [])!.length,
        );
      }
      store.registerRepository(repository);
      for (var index = 0; index < invalidLists.length; index++) {
        await expectLater(read('@count_$index'), throwsFormatException);
        await expectLater(read('@sync_count_$index'), throwsFormatException);
      }
    },
  );

  for (final name in ['list', 'object']) {
    test(
      'sync $name getter rejects pending values but reads cached values',
      () async {
        final gate = Completer<Object?>();
        final repository = RepositoryImpl(id: id, json: {});
        repository.addCalculatedAttribute('source', (_) => gate.future);
        repository.addCalculatedAttribute(
          'typed',
          (ctx) => name == 'list'
              ? ctx.sync.getList('@source', defaultValue: const [])
              : ctx.sync.getObject('@source', defaultValue: const {}),
        );
        store.registerRepository(repository);
        await expectLater(read('@typed'), throwsFormatException);
        gate.complete(typedValues[name]);
        expect(await read('@source'), typedValues[name]);
        expect(
          (await store.refreshCalculatedAttribute(
            const JsonTextBinding(repositoryId: id, path: '@typed'),
          )).value,
          typedValues[name],
        );
      },
    );
  }

  test(
    'collection getters retain scoped cross-repository dependencies',
    () async {
      var calls = 0;
      late List<Map<String, Object?>> listSnapshot;
      late Map<String, Object?> objectSnapshot;
      final repository = RepositoryImpl(
        id: id,
        json: {
          'rows': [
            {
              'values': [
                {'value': 1},
              ],
              'info': {'label': 'first'},
            },
          ],
        },
      );
      repository.addCalculatedAttribute('data', (ctx) async {
        calls++;
        listSnapshot = (await ctx.getList('values'))!;
        objectSnapshot = ctx.sync.getObject('info')!;
        return {
          'localList': listSnapshot,
          'localObject': objectSnapshot,
          'externalList': await ctx.getList('offsets', repositoryId: 'source'),
          'externalObject': ctx.sync.getObject(
            'options',
            repositoryId: 'source',
          ),
        };
      }, scope: 'rows[?]');
      store.registerRepository(repository);
      store.registerRepository(
        RepositoryImpl(
          id: 'source',
          json: {
            'offsets': [
              {'value': 2},
            ],
            'options': {'unit': 'USD'},
          },
        ),
      );
      final expected = <String, Object?>{
        'localList': [
          {'value': 1},
        ],
        'localObject': {'label': 'first'},
        'externalList': [
          {'value': 2},
        ],
        'externalObject': {'unit': 'USD'},
      };
      expect(await read('rows[0].@data'), expected);
      expect(await read('rows[0].@data'), expected);
      expect(calls, 1);
      expect(() => listSnapshot.add({}), throwsUnsupportedError);
      expect(() => listSnapshot.first['value'] = 9, throwsUnsupportedError);
      expect(() => objectSnapshot['label'] = 'changed', throwsUnsupportedError);
      await store.writeAttribute(
        const JsonTextBinding(
          repositoryId: id,
          path: 'rows[0].values[0].value',
        ),
        '3',
        expectedValue: 1,
      );
      expected['localList'] = [
        {'value': 3},
      ];
      expect(await read('rows[0].@data'), expected);
      expect(calls, 2);
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: 'source', path: 'options.unit'),
        'EUR',
        expectedValue: 'USD',
      );
      expected['externalObject'] = {'unit': 'EUR'};
      expect(await read('rows[0].@data'), expected);
      expect(calls, 3);
    },
  );

  test('integer getter rejects fractional values without truncation', () async {
    final repository = RepositoryImpl(id: id, json: {'value': 2.5});
    repository.addCalculatedAttribute('total', (ctx) => ctx.getInt('value'));
    store.registerRepository(repository);

    await expectLater(
      store.readAttribute(totalBinding),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'typed getters retain caching and deep dependency invalidation',
    () async {
      var calls = 0;
      final repository = RepositoryImpl(
        id: id,
        json: {
          'client': {'nom': 'Alice'},
          'other': 'x',
        },
      );
      repository.addCalculatedAttribute('name', (ctx) {
        calls++;
        return ctx.getString('client.nom');
      });
      store.registerRepository(repository);
      const binding = JsonTextBinding(repositoryId: id, path: '@name');

      expect((await store.readAttribute(binding)).value, 'Alice');
      expect(store.peekAttribute(binding)?.value, 'Alice');
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'other'),
        'y',
        expectedValue: 'x',
      );
      expect((await store.readAttribute(binding)).value, 'Alice');
      expect(calls, 1);
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'client.nom'),
        'Bob',
        expectedValue: 'Alice',
      );
      expect((await store.readAttribute(binding)).value, 'Bob');
      expect(calls, 2);
    },
  );

  test(
    'sync calculated attribute is readable through @name bindings',
    () async {
      final repository = RepositoryImpl(id: id, json: {'a': 2, 'b': 3});
      repository.addCalculatedAttribute(
        'total',
        (ctx) => (ctx.getValue('a')! as num) + (ctx.getValue('b')! as num),
      );
      store.registerRepository(repository);

      expect(await store.readAttribute(totalBinding), (value: 5, text: '5'));
      expect(store.peekAttribute(totalBinding), (value: 5, text: '5'));
    },
  );

  test(
    'values are cached and recomputed only when a dependency changes',
    () async {
      var calls = 0;
      final repository = RepositoryImpl(
        id: id,
        json: {'a': 2, 'b': 3, 'other': 'x'},
      );
      repository.addCalculatedAttribute('total', (ctx) {
        calls++;
        return (ctx.getValue('a')! as num) + (ctx.getValue('b')! as num);
      });
      store.registerRepository(repository);

      expect((await store.readAttribute(totalBinding)).value, 5);
      expect((await store.readAttribute(totalBinding)).value, 5);
      expect(store.peekAttribute(totalBinding)?.value, 5);
      expect(calls, 1);

      // Une écriture sur un chemin indépendant n'invalide pas le cache.
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'other'),
        'y',
        expectedValue: 'x',
      );
      expect((await store.readAttribute(totalBinding)).value, 5);
      expect(calls, 1);

      // Une écriture sur une dépendance force le recalcul.
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: id, path: 'a'),
        '10',
        expectedValue: 2,
      );
      expect((await store.readAttribute(totalBinding)).value, 13);
      expect(calls, 2);
    },
  );

  test(
    'deep dependencies are invalidated by overlapping array changes',
    () async {
      var calls = 0;
      final repository = RepositoryImpl(
        id: id,
        json: {
          'clients': [
            {'nom': 'Alice'},
            {'nom': 'Bob'},
          ],
        },
      );
      repository.addCalculatedAttribute('first_name', (ctx) {
        calls++;
        return ctx.getValue('clients[0].nom');
      });
      store.registerRepository(repository);
      const binding = JsonTextBinding(repositoryId: id, path: '@first_name');

      expect((await store.readAttribute(binding)).value, 'Alice');
      // Un ajout dans « clients » recouvre la dépendance « clients[0].nom ».
      await store.appendArrayItem(id, 'clients', expectedLength: 2);
      expect((await store.readAttribute(binding)).value, 'Alice');
      expect(calls, 2);
    },
  );

  test(
    'async calculated attribute resolves through readAttribute and peek',
    () async {
      final repository = RepositoryImpl(id: id, json: {'a': 4});
      repository.addCalculatedAttribute('double', (ctx) async {
        final a = ctx.getValue('a')! as num;
        await Future<void>.delayed(Duration.zero);
        return a * 2;
      });
      store.registerRepository(repository);
      const binding = JsonTextBinding(repositoryId: id, path: '@double');

      var notified = false;
      store.addListener(() => notified = true);
      // Le calcul asynchrone n'est pas disponible de manière synchrone.
      expect(store.peekAttribute(binding), isNull);
      expect(await store.readAttribute(binding), (value: 8, text: '8'));
      expect(notified, isTrue);
      expect(store.peekAttribute(binding), (value: 8, text: '8'));
    },
  );

  test('chained attributes propagate invalidation transitively', () async {
    var totalCalls = 0;
    var doubleCalls = 0;
    final repository = RepositoryImpl(id: id, json: {'a': 2, 'b': 3});
    repository.addCalculatedAttribute('total', (ctx) {
      totalCalls++;
      return (ctx.getValue('a')! as num) + (ctx.getValue('b')! as num);
    });
    repository.addCalculatedAttribute('double_total', (ctx) async {
      doubleCalls++;
      return ((await ctx.getValue('@total'))! as num) * 2;
    });
    store.registerRepository(repository);
    const binding = JsonTextBinding(repositoryId: id, path: '@double_total');

    expect((await store.readAttribute(binding)).value, 10);
    expect((await store.readAttribute(binding)).value, 10);
    expect(totalCalls, 1);
    expect(doubleCalls, 1);

    await store.writeAttribute(
      const JsonTextBinding(repositoryId: id, path: 'b'),
      '8',
      expectedValue: 3,
    );
    expect((await store.readAttribute(binding)).value, 20);
    expect(totalCalls, 2);
    expect(doubleCalls, 2);
  });

  test('calculated attribute cycles raise a displayable error', () async {
    final repository = RepositoryImpl(id: id, json: {'a': 1});
    repository.addCalculatedAttribute(
      'first',
      (ctx) => ctx.getValue('@second'),
    );
    repository.addCalculatedAttribute(
      'second',
      (ctx) => ctx.getValue('@first'),
    );
    store.registerRepository(repository);

    await expectLater(
      store.readAttribute(
        const JsonTextBinding(repositoryId: id, path: '@first'),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Cycle'),
        ),
      ),
    );
  });

  test('calculated attributes are read-only', () async {
    final repository = RepositoryImpl(id: id, json: {'a': 1});
    repository.addCalculatedAttribute('total', (ctx) => ctx.getValue('a'));
    store.registerRepository(repository);

    await expectLater(
      store.writeAttribute(totalBinding, '9', expectedValue: 1),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('lecture seule'),
        ),
      ),
    );
    await expectLater(
      store.appendArrayItem(id, '@total', expectedLength: 0),
      throwsA(isA<FormatException>()),
    );
  });

  test('invalid or duplicate declarations are rejected', () {
    final repository = RepositoryImpl(id: id, json: {'a': 1});
    expect(
      () => repository.addCalculatedAttribute('nom invalide', (_) => null),
      throwsFormatException,
    );
    repository.addCalculatedAttribute('total', (_) => 1);
    expect(
      () => repository.addCalculatedAttribute('total', (_) => 2),
      throwsArgumentError,
    );
    store.registerRepository(repository);
    expect(
      () => repository.addCalculatedAttribute('after', (_) => 3),
      throwsStateError,
    );
  });

  test(
    'a calculated list is readable through readArray and peekArray',
    () async {
      final repository = RepositoryImpl(
        id: id,
        json: {
          'clients': [
            {'nom': 'Alice', 'actif': true},
            {'nom': 'Bob', 'actif': false},
          ],
        },
      );
      repository.addCalculatedAttribute('actifs', (ctx) {
        final clients = ctx.getValue('clients')! as List;
        return [
          for (final client in clients)
            if ((client as Map)['actif'] == true) client,
        ];
      });
      store.registerRepository(repository);

      expect(await store.readArray(id, '@actifs'), [
        {'nom': 'Alice', 'actif': true},
      ]);
      expect(store.peekArray(id, '@actifs'), [
        {'nom': 'Alice', 'actif': true},
      ]);
    },
  );

  test('unknown calculated attribute raises a displayable error', () async {
    store.registerRepository(RepositoryImpl(id: id, json: {'a': 1}));
    await expectLater(
      store.readAttribute(
        const JsonTextBinding(repositoryId: id, path: '@missing'),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('@missing'),
        ),
      ),
    );
    expect(
      store.peekAttribute(
        const JsonTextBinding(repositoryId: id, path: '@missing'),
      ),
      isNull,
    );
  });

  test(
    'whole-document replacement invalidates every calculated value',
    () async {
      var calls = 0;
      final repository = RepositoryImpl(id: id, json: {'a': 1});
      repository.addCalculatedAttribute('total', (ctx) {
        calls++;
        return ctx.getValue('a');
      });
      store.registerRepository(repository);

      expect((await store.readAttribute(totalBinding)).value, 1);
      final text = await store.read(id);
      await store.save(id, '{"a": 7}', expectedText: text);
      expect((await store.readAttribute(totalBinding)).value, 7);
      expect(calls, 2);
    },
  );
}
