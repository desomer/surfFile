import 'package:flutter_test/flutter_test.dart';
import 'package:super_designer/json_browser.dart';

void main() {
  test('creates one node with a unique ID for each JSON node', () {
    var next = 0;
    final browser = JsonBrowser(generateId: () => 'id${next++}');
    final roots = browser.browse({
      'name': 'demo',
      'items': [
        {'count': 2, 'active': true},
        null,
      ],
    });

    expect(roots.map((node) => node.name), ['name', 'items']);
    final items = roots[1];
    expect(items.type, 'Array');
    expect(items.children.map((node) => node.name), ['[0]', '[1]']);
    final count = items.children[0].children[0];
    expect(count.type, 'Number');
    expect(count.parent, same(items.children[0]));
    expect(count.path, 'items[0].count');
    expect(browser.nodesById, hasLength(6));
    expect(browser.nodesById[count.id], same(count));
    expect(roots[0].toJson(), {
      'id': 'id0',
      'name': 'name',
      'type': 'String',
      'typeIcon': 'value',
      'description': 'demo',
      'propertiesText': '',
    });
    expect(items.toJson()['typeIcon'], 'container');
    expect(items.toJson()['children'], hasLength(2));
  });

  test('default generator yields unique short IDs', () {
    final browser = JsonBrowser();
    browser.browse({
      'a': [1, 2, 3],
      'b': {'c': 'd'},
    });
    expect(browser.nodesById, hasLength(6));
    expect(browser.nodesById.keys.every((id) => id.isNotEmpty), isTrue);
    expect(browser.browse('scalar'), isEmpty);
    expect(browser.nodesById, isEmpty);
  });

  test('model names a JSON structure with its top-level nodes', () {
    var next = 0;
    final browser = JsonBrowser(generateId: () => 'id${next++}');
    final json = {
      'title': 'Stock',
      'items': [
        {'count': 2},
      ],
    };
    final model = browser.model('Inventory', json);

    expect(model.name, 'Inventory');
    expect(model.json, same(json));
    expect(model.nodes.map((node) => node.name), ['title', 'items']);
    expect(model.nodes.every((node) => node.parent == null), isTrue);
    final items = model.nodes[1];
    final count = items.children.single.children.single;
    expect(count.path, 'items[0].count');
    expect(count.parent!.parent, same(items));
    expect(model.nodeById(items.id), same(items));
    expect(model.nodeById(count.id), same(count));
    expect(model.nodeById('missing'), isNull);
    expect(() => model.nodes.add(items), throwsUnsupportedError);
    expect(browser.nodesById, hasLength(4));

    expect(browser.model('Value', 42).nodes, isEmpty);
  });

  group('patch', () {
    late JsonModel model;
    late Map<String, String> ids;

    String idAt(String path) =>
        descendants(model).firstWhere((n) => n.path == path).id;

    setUp(() {
      model = JsonBrowser().model('Doc', {
        'title': 'Demo',
        'settings': {'color': 'red', 'size': 3, 'visible': true},
        'items': [
          {'name': 'a', 'qty': 1},
          {'name': 'b', 'qty': 2},
          {'name': 'c', 'qty': 3},
        ],
      });
      ids = {for (final n in descendants(model)) n.path: n.id};
    });

    test('keeps IDs of unchanged and modified values', () {
      model.patch('''
title: Changed
settings: {color: red, size: 4, visible: true}
items:
  - {name: a, qty: 1}
  - {name: b, qty: 2}
  - {name: c, qty: 3}
''');
      expect(model.json, isA<Map<String, Object?>>());
      expect(ids, {for (final n in descendants(model)) n.path: n.id});
      expect(model.nodeById(ids['title']!)!.value, 'Changed');
    });

    test('keeps IDs of renamed nodes, including modified containers', () {
      model.patch('''
heading: Demo
options: {color: blue, size: 3, visible: true}
items:
  - {name: a, qty: 1}
  - {name: b, qty: 2}
  - {name: c, qty: 3}
''');
      expect(idAt('heading'), ids['title']);
      expect(idAt('options'), ids['settings']);
      expect(idAt('options.color'), ids['settings.color']);
      expect(idAt('options.size'), ids['settings.size']);
    });

    test('keeps IDs of moved and reordered nodes', () {
      model.patch('''
title: Demo
items:
  - {name: c, qty: 3}
  - {name: a, qty: 1}
  - name: b
    qty: 2
    settings: {color: red, size: 3, visible: true}
''');
      expect(idAt('items[0]'), ids['items[2]']);
      expect(idAt('items[0].name'), ids['items[2].name']);
      expect(idAt('items[1]'), ids['items[0]']);
      expect(idAt('items[2]'), ids['items[1]']);
      expect(idAt('items[2].settings'), ids['settings']);
      expect(idAt('items[2].settings.color'), ids['settings.color']);
      final moved = model.nodeById(ids['settings']!)!;
      expect(moved.parent!.id, ids['items[1]']);
    });

    test('adds new IDs for inserted nodes and drops removed ones', () {
      model.patch('''
title: Demo
items:
  - {name: z, qty: 0}
  - {name: a, qty: 1}
  - {name: b, qty: 2}
  - {name: c, qty: 3}
''');
      expect(idAt('items[1]'), ids['items[0]']);
      expect(idAt('items[2]'), ids['items[1]']);
      expect(idAt('items[3]'), ids['items[2]']);
      final inserted = idAt('items[0]');
      expect(ids.values, isNot(contains(inserted)));
      expect(model.nodeById(ids['settings']!), isNull);
      final all = [for (final n in descendants(model)) n.id];
      expect(all.toSet(), hasLength(all.length));
    });

    test('stores removed subtrees and restores their IDs elsewhere', () {
      model.patch('''
title: Demo
items:
  - {name: a, qty: 1}
  - {name: b, qty: 2}
  - {name: c, qty: 3}
''');
      expect(model.nodeById(ids['settings']!), isNull);
      expect(model.removedNodes.map((node) => node.id), [ids['settings']]);

      model.patch('''
title: Demo
items:
  - {name: a, qty: 1}
  - {name: b, qty: 2}
  - {name: c, qty: 3}
archive:
  config: {color: red, size: 3, visible: true}
''');
      expect(idAt('archive.config'), ids['settings']);
      expect(idAt('archive.config.color'), ids['settings.color']);
      expect(idAt('archive.config.visible'), ids['settings.visible']);
      expect(model.removedNodes, isEmpty);
    });

    test('restores a removed value and keeps IDs unique', () {
      model.patch('''
settings: {color: red, size: 3, visible: true}
items:
  - {name: a, qty: 1}
  - {name: b, qty: 2}
  - {name: c, qty: 3}
''');
      expect(model.removedNodes.map((node) => node.id), [ids['title']]);

      // settings.color leaves its parent, then the parent is removed.
      model.patch('''
color: red
items:
  - {name: a, qty: 1}
  - {name: b, qty: 2}
  - {name: c, qty: 3}
''');
      expect(idAt('color'), ids['settings.color']);
      model.patch('''
title: Demo
items:
  - {name: a, qty: 1}
  - {name: b, qty: 2}
  - {name: c, qty: 3}
  - {color: red, size: 3, visible: true}
''');
      expect(idAt('title'), ids['title']);
      expect(idAt('items[3].size'), ids['settings.size']);
      expect(idAt('items[3].color'), ids['settings.color']);
      final all = [for (final n in descendants(model)) n.id];
      expect(all.toSet(), hasLength(all.length));
      expect(
        model.removedNodes.every((node) => !all.contains(node.id)),
        isTrue,
      );
    });

    test('keeps only the most recent removed subtrees', () {
      final limited = JsonModel(
        name: 'Limited',
        json: null,
        nodes: const [],
        maxRemovedNodes: 1,
      )..patch('a: 1\nb: 2');
      final b = limited.nodes[1].id;
      limited
        ..patch('{}')
        ..clearRemovedNodes();
      expect(limited.removedNodes, isEmpty);
      limited.patch('a: 1\nb: 2');
      expect(limited.nodes[1].id, isNot(b));
      limited.patch('c: 3');
      expect(limited.removedNodes.map((node) => node.name), ['b']);
    });
    test('invalid YAML throws and leaves the model untouched', () {
      final before = model.nodes;
      expect(() => model.patch('a: [1'), throwsFormatException);
      expect(model.nodes, same(before));
    });
  });
}

Iterable<JsonNode> descendants(JsonModel model) sync* {
  Iterable<JsonNode> walk(List<JsonNode> nodes) sync* {
    for (final node in nodes) {
      yield node;
      yield* walk(node.children);
    }
  }

  yield* walk(model.nodes);
}
