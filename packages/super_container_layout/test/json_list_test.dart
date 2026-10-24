/// Tests unitaires des listes JSON, sans widget de liste :
///
/// * chemins `[?]` (`JsonAttributePath`) et liaisons héritées
///   (`JsonTextBinding`) ;
/// * `SuperListViewConfig` : validation, JSON, apparence et duplication ;
/// * lecture, ajout et suppression d'éléments de tableau dans
///   `JsonRepositoryStore` ;
/// * maître / détail : sélections par chemin modèle (`JsonRepositoryBinding`),
///   décalage après suppression et résolution des `[?]` par la sélection.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = '0123456789abcdef0123456789abcdef';

  group('[?] paths', () {
    test('wildcards resolve from the outer list to the inner list', () {
      final path = JsonAttributePath('clients[?].orders[?].label');
      expect(path.wildcardCount, 2);
      expect(path.isResolved, isFalse);
      expect(path.toString(), 'clients[?].orders[?].label');
      expect(path.resolve([3, 1]).toString(), 'clients[3].orders[1].label');
      // Deeper rows can use a path that only needs the outer index.
      expect(
        JsonAttributePath('clients[?].name').resolve([2, 5]).toString(),
        'clients[2].name',
      );
      expect(() => path.resolve([0]), throwsFormatException);
      expect(() => path.read({}), throwsFormatException);
      expect(() => path.write({}, 'A', null), throwsFormatException);
      expect(() => path.requireResolvedWith(1), throwsFormatException);
      path.requireResolvedWith(2);
      for (final invalid in ['a[??]', 'a?', '?', 'a[?', 'a.[?]']) {
        expect(
          () => JsonAttributePath(invalid),
          throwsFormatException,
          reason: invalid,
        );
      }
    });

    test('bindings may inherit their repository and stay compatible', () {
      const inherited = JsonTextBinding(path: 'clients[?].name');
      final json = jsonDecode(jsonEncode(inherited.toJson()));
      expect(json, {'path': 'clients[?].name'});
      expect(JsonTextBinding.fromJson(json), inherited);
      expect(
        JsonTextBinding.fromJson({'repositoryId': id, 'path': 'a'}),
        const JsonTextBinding(repositoryId: id, path: 'a'),
      );
      expect(
        () => JsonTextBinding.fromJson({'repositoryId': null, 'path': 'a'}),
        throwsFormatException,
      );
      expect(inherited.isResolved, isFalse);
      expect(
        inherited.resolve(repositoryId: id, indices: [4]),
        const JsonTextBinding(repositoryId: id, path: 'clients[4].name'),
      );
      expect(() => inherited.resolve(indices: [4]), throwsFormatException);
      expect(() => inherited.resolve(repositoryId: id), throwsFormatException);
      const explicit = JsonTextBinding(repositoryId: id, path: 'x[?]');
      expect(
        explicit.resolve(repositoryId: 'f' * 32, indices: [0]).repositoryId,
        id,
      );
    });

    test('nodes are read and replaced without changing the input', () {
      final root = {
        'clients': [
          {'name': 'A'},
        ],
      };
      final path = JsonAttributePath('clients');
      expect(path.readNode(root), root['clients']);
      expect(JsonAttributePath('missing.list').readNode(root), isNull);
      final updated = path.replaceNode(root, []);
      expect(updated, {'clients': []});
      expect((root['clients'] as List).length, 1);
    });
  });

  test('list configuration is validated and serialized', () {
    const config = SuperListViewConfig(
      binding: JsonTextBinding(path: 'clients[?].orders'),
      axis: Axis.horizontal,
      wrap: true,
      wrapSizing: ListWrapSizing.automatic,
      itemWidth: 180,
      itemSize: SlotSizeConstraints(
        preferredWidth: SlotDimension(40, SlotSizeUnit.percent),
        minHeight: SlotDimension(30, SlotSizeUnit.pixels),
        padding: 4,
      ),
      itemExtent: 120,
      spacing: 4,
      allowAdd: true,
      allowRemove: true,
      emptyText: 'Rien',
    );
    final restored = SuperListViewConfig.fromJson(
      jsonDecode(jsonEncode(config.toJson())),
    );
    expect(restored, config);
    expect(restored.hashCode, config.hashCode);
    expect(
      SuperListViewConfig.fromJson(<String, dynamic>{}),
      const SuperListViewConfig(),
    );
    for (final invalid in [
      {'itemExtent': 0},
      {'spacing': -1},
      {'axis': 'diagonal'},
      {'wrap': 'yes'},
      {'wrapSizing': 'random'},
      {'itemWidth': 0},
      {'itemWidth': double.infinity},
      {'itemSize': 'invalid'},
      {
        'itemSize': {
          'preferredWidth': {'value': -1, 'unit': 'px'},
        },
      },
      {'allowAdd': 'yes'},
      {'unknown': true},
    ]) {
      expect(
        () => SuperListViewConfig.fromJson(invalid),
        throwsFormatException,
        reason: '$invalid',
      );
    }
  });

  test('appearance documents persist list components', () {
    const codec = AppearanceCodec();
    final appearance = Appearance().withListComponent(
      'list',
      const SuperListViewConfig(
        binding: JsonTextBinding(repositoryId: id, path: 'items'),
        allowAdd: true,
      ),
    );
    final restored = codec.decode(codec.encode(appearance));
    expect(restored.listComponents, appearance.listComponents);
    final legacy = codec.toJson(appearance)..remove('listComponents');
    expect(codec.fromJson(legacy).listComponents, isEmpty);
    expect(appearance.resetLayouts().listComponents, isEmpty);
    final defaults = DefaultAppearance().withListComponent(
      'list',
      const SuperListViewConfig(itemExtent: 80),
    );
    expect(defaults, isA<DefaultAppearance>());
    expect(defaults.listComponent('list').itemExtent, 80);
  });

  test('duplicating a list copies its settings and row template', () {
    final registry = Registry()..bootstrap();
    final contract = registry.registry['ListView']!.duplication!;
    expect(contract.ownedConfigs('x'), [
      const EditorConfigRef.layout('x'),
      const EditorConfigRef.style('x'),
      const EditorConfigRef.list('x'),
    ]);
  });

  group('repository arrays', () {
    late Directory directory;
    late JsonRepositoryStore store;
    late String repository;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('json-list-test-');
      store = JsonRepositoryStore(directory);
      await store.create('Shop');
      repository = await store.idOf('Shop');
      await store.save(
        'Shop',
        jsonEncode({
          'clients': [
            {
              'name': 'Alice',
              'age': 31,
              'vip': true,
              'orders': [
                {'label': 'A1'},
              ],
              'address': {'city': 'Paris'},
            },
          ],
          'scalar': 3,
        }),
        expectedText: await store.read('Shop'),
      );
    });
    tearDown(() async {
      store.dispose();
      await directory.delete(recursive: true);
    });

    Future<Object?> document() async => jsonDecode(await store.read('Shop'));

    test('arrays are read; missing ones are empty', () async {
      expect(await store.readArray(repository, 'clients'), hasLength(1));
      expect(await store.readArray(repository, 'clients[0].orders'), [
        {'label': 'A1'},
      ]);
      expect(await store.readArray(repository, 'missing'), isEmpty);
      await expectLater(
        store.readArray(repository, 'scalar'),
        throwsFormatException,
      );
      await expectLater(
        store.readArray(repository, 'clients[?].orders'),
        throwsFormatException,
      );
    });

    test('append adds a blank copy and checks the expected length', () async {
      expect(
        await store.appendArrayItem(repository, 'clients', expectedLength: 1),
        2,
      );
      final clients = (await document() as Map)['clients'] as List;
      expect(clients[1], {
        'name': '',
        'age': 0,
        'vip': false,
        'orders': [],
        'address': {'city': ''},
      });
      await expectLater(
        store.appendArrayItem(repository, 'clients', expectedLength: 1),
        throwsFormatException,
      );
      expect(
        await store.appendArrayItem(
          repository,
          'clients[1].orders',
          expectedLength: 0,
        ),
        1,
      );
      expect(
        await store.appendArrayItem(repository, 'new', expectedLength: 0),
        1,
      );
      expect((await document() as Map)['new'], [{}]);
    });

    test('remove checks the expected element', () async {
      final alice = (await store.readArray(repository, 'clients')).single;
      await expectLater(
        store.removeArrayItem(repository, 'clients', 0, expectedItem: {}),
        throwsFormatException,
      );
      await expectLater(
        store.removeArrayItem(repository, 'clients', 4, expectedItem: alice),
        throwsFormatException,
      );
      expect(
        await store.removeArrayItem(
          repository,
          'clients',
          0,
          expectedItem: jsonDecode(jsonEncode(alice)),
        ),
        0,
      );
      expect((await document() as Map)['clients'], isEmpty);
      expect((await document() as Map)['scalar'], 3);
    });

    test('bindings with unresolved [?] are refused by the store', () async {
      await expectLater(
        store.readAttribute(
          JsonTextBinding(repositoryId: repository, path: 'clients[?].name'),
        ),
        throwsFormatException,
      );
      await expectLater(
        store.readAttribute(const JsonTextBinding(path: 'scalar')),
        throwsFormatException,
      );
    });
  });

  group('master/detail', () {
    test('array templates key the [?] of a path', () {
      expect(JsonAttributePath('clients[?].orders[?].label').arrayTemplates, [
        'clients',
        'clients[?].orders',
      ]);
      expect(JsonAttributePath('a[0].b[?]').arrayTemplates, ['a[0].b']);
      expect(JsonAttributePath('a.b').arrayTemplates, isEmpty);
    });

    test('an array binding keeps one selection per template', () {
      final array = JsonArrayBinding('clients[?].orders');
      addTearDown(array.dispose);
      var notified = 0;
      array.addListener(() => notified++);
      array.select([2], 1);
      expect(array.selection, [2, 1]);
      expect(array.indexFor([2]), 1);
      // Another client's orders are not selected.
      expect(array.indexFor([0]), isNull);
      expect(array.indexFor([]), isNull);
      array.select([2], 1);
      expect(notified, 1);
      array.clear();
      expect(array.indexFor([2]), isNull);
      expect(notified, 2);
      expect(() => array.select([], -1), throwsRangeError);
    });

    test('selections follow removals in their array', () {
      final repository = JsonRepositoryBinding(id);
      addTearDown(repository.dispose);
      final clients = repository.array('clients')..select([], 2);
      final orders = repository.array('clients[?].orders')..select([3], 1);
      final before = repository.array('clients[?].tags')..select([0], 4);
      final lines = repository.array('clients[?].orders[?].lines')
        ..select([3, 1], 0);
      final other = repository.array('suppliers')..select([], 5);
      final similar = repository.array('clientsX')..select([], 5);
      expect(identical(repository.array('clients'), clients), isTrue);

      repository.removed('clients', [], 1);
      expect(clients.selection, [1]);
      // Rows inside a shifted element shift with it.
      expect(orders.selection, [2, 1]);
      expect(lines.selection, [2, 1, 0]);
      expect(before.selection, [0, 4]);
      expect(other.selection, [5]);
      expect(similar.selection, [5]);

      repository.removed('clients[?].orders', [2], 0);
      expect(orders.selection, [2, 0]);
      expect(lines.selection, [2, 0, 0]);
      // Another client's orders are untouched.
      repository.removed('clients[?].orders', [1], 0);
      expect(orders.selection, [2, 0]);

      repository.removed('clients', [], 1);
      expect(clients.selection, isNull);
      expect(orders.selection, [1, 0]);
      repository.removed('clients', [], 1);
      expect(orders.selection, isNull);
      expect(lines.selection, isNull);
    });

    testWidgets('[?] beyond the enclosing lists takes the selected row', (
      tester,
    ) async {
      final store = JsonRepositoryStore(Directory.systemTemp);
      addTearDown(store.dispose);
      const binding = JsonTextBinding(
        repositoryId: id,
        path: 'clients[?].orders[?].label',
      );
      final repository = store.bindingOf(id);
      var resolved = JsonListScope.resolveSelected(binding, null, store);
      expect(resolved.binding, isNull);
      expect(resolved.arrays, [repository.array('clients')]);

      repository.array('clients').select([], 2);
      resolved = JsonListScope.resolveSelected(binding, null, store);
      expect(resolved.binding, isNull);
      expect(resolved.indices, [2]);
      expect(resolved.arrays, [
        repository.array('clients'),
        repository.array('clients[?].orders'),
      ]);

      // The orders selection belongs to another client.
      repository.array('clients[?].orders').select([0], 1);
      expect(
        JsonListScope.resolveSelected(binding, null, store).binding,
        isNull,
      );
      repository.array('clients[?].orders').select([2], 1);
      resolved = JsonListScope.resolveSelected(binding, null, store);
      expect(resolved.binding!.path, 'clients[2].orders[1].label');
      expect(resolved.indices, [2, 1]);

      // An enclosing list provides the outer index.
      await tester.pumpWidget(
        JsonListScope(
          repositoryId: id,
          indices: const [0],
          child: Builder(
            builder: (context) {
              final scope = JsonListScope.maybeOf(context);
              expect(
                JsonListScope.resolveSelected(binding, scope, store).binding,
                isNull,
              );
              expect(
                JsonListScope.resolveSelected(
                  const JsonTextBinding(path: 'clients[?].name'),
                  scope,
                  store,
                ).binding,
                const JsonTextBinding(
                  repositoryId: id,
                  path: 'clients[0].name',
                ),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      // Outside any list an inherited repository is unavailable.
      expect(
        () => JsonListScope.resolveSelected(
          const JsonTextBinding(path: 'clients[?].name'),
          null,
          store,
        ),
        throwsFormatException,
      );
    });

    test('the appearance has no list detail anymore', () {
      const codec = AppearanceCodec();
      final json =
          jsonDecode(codec.encode(Appearance())) as Map<String, Object?>;
      expect(json.containsKey('listDetailComponents'), isFalse);
      expect(
        () => codec.decode(jsonEncode({...json, 'listDetailComponents': {}})),
        throwsFormatException,
      );
    });
  });

  test('blank keeps the JSON shape', () {
    expect(JsonRepositoryStore.blank([1]), []);
    expect(JsonRepositoryStore.blank(null), isNull);
    expect(
      JsonRepositoryStore.jsonEquals(
        {
          'a': [
            1,
            {'b': 2},
          ],
        },
        {
          'a': [
            1,
            {'b': 2},
          ],
        },
      ),
      isTrue,
    );
    expect(JsonRepositoryStore.jsonEquals({'a': 1}, {'a': 1, 'b': 2}), isFalse);
    expect(LogicalKeyboardKey.enter, isNotNull);
  });
}
