import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/services/repositories/json_list_scope.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/services/states/surface_state_binding.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late String repositoryId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('surface-state-binding-');
    store = JsonRepositoryStore(directory);
    await store.create('States');
    repositoryId = await store.idOf('States');
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> saveJson(Object value) async {
    final oldText = await store.read('States');
    await store.save(
      'States',
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
      expectedText: oldText,
    );
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 400 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue, reason: 'Timed out waiting for binding update');
  }

  test('reads string state and reacts to repository changes', () async {
    await saveJson({'surface': 'compact'});
    final binding = SurfaceStateBinding(
      store: store,
      binding: JsonTextBinding(repositoryId: repositoryId, path: 'surface'),
    );
    addTearDown(binding.dispose);

    await waitFor(() => !binding.loading);
    expect(binding.stateName, 'compact');
    expect(binding.error, isNull);

    await saveJson({'surface': 'expanded'});
    await waitFor(() => !binding.loading && binding.stateName == 'expanded');
    expect(binding.error, isNull);
  });

  test('listens to selected rows outside the list', () async {
    await saveJson({
      'clients': [
        {'surface': 'first'},
        {'surface': 'second'},
      ],
    });
    final binding = SurfaceStateBinding(
      store: store,
      binding: JsonTextBinding(
        repositoryId: repositoryId,
        path: 'clients[?].surface',
      ),
    );
    addTearDown(binding.dispose);

    await waitFor(() => !binding.loading);
    expect(binding.stateName, isNull);

    store.bindingOf(repositoryId).array('clients').select(const [], 1);
    await waitFor(() => !binding.loading && binding.stateName == 'second');
  });

  test('resolves inherited row and selected nested wildcard', () async {
    await saveJson({
      'clients': [
        {
          'states': [
            {'name': 'wrong'},
          ],
        },
        {
          'states': [
            {'name': 'inherited'},
          ],
        },
      ],
    });
    final scope = JsonListScope(
      repositoryId: repositoryId,
      indices: const [1],
      selected: true,
      child: const SizedBox(),
    );
    final binding = SurfaceStateBinding(
      store: store,
      binding: const JsonTextBinding(path: 'clients[?].states[?].name'),
      scope: scope,
    );
    addTearDown(binding.dispose);

    await waitFor(() => !binding.loading);
    expect(binding.stateName, isNull);
    store.bindingOf(repositoryId).array('clients[?].states').select(const [
      1,
    ], 0);
    await waitFor(() => !binding.loading && binding.stateName == 'inherited');
  });

  test(
    'null and missing are defaults; non-string values give diagnostics',
    () async {
      await saveJson({'surface': null, 'wrongType': 42});
      final binding = SurfaceStateBinding(
        store: store,
        binding: JsonTextBinding(repositoryId: repositoryId, path: 'surface'),
      );
      addTearDown(binding.dispose);

      await waitFor(() => !binding.loading);
      expect(binding.stateName, isNull);
      expect(binding.error, isNull);

      binding.reconfigure(
        store: store,
        binding: JsonTextBinding(repositoryId: repositoryId, path: 'missing'),
      );
      await waitFor(() => !binding.loading);
      expect(binding.stateName, isNull);
      expect(binding.error, isNull);

      binding.reconfigure(
        store: store,
        binding: JsonTextBinding(repositoryId: repositoryId, path: 'wrongType'),
      );
      await waitFor(() => !binding.loading && binding.error != null);
      expect(binding.stateName, isNull);
      expect(binding.error, 'Surface state name must be a string.');
      expect(store.errors.value, isNull);
    },
  );

  test(
    'placeholder avoids reads and reconfiguration ignores stale results',
    () async {
      await saveJson({'first': 'old', 'second': 'new'});
      final placeholder = JsonListScope(
        repositoryId: repositoryId,
        indices: const [],
        placeholder: true,
        child: const SizedBox(),
      );
      final binding = SurfaceStateBinding(
        store: store,
        binding: JsonTextBinding(repositoryId: repositoryId, path: 'first'),
        scope: placeholder,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(binding.loading, isFalse);
      expect(binding.stateName, isNull);

      binding.reconfigure(
        store: store,
        binding: JsonTextBinding(repositoryId: repositoryId, path: 'first'),
        placeholder: false,
      );
      binding.reconfigure(
        store: store,
        binding: JsonTextBinding(repositoryId: repositoryId, path: 'second'),
      );
      await waitFor(() => !binding.loading && binding.stateName == 'new');

      var notifications = 0;
      binding.addListener(() => notifications++);
      binding.dispose();
      await saveJson({'first': 'later', 'second': 'later'});
      expect(notifications, 0);
    },
  );

  test('selection-only and equivalent scope changes do not reload', () async {
    await saveJson({
      'rows': [
        {'surface': 'active'},
      ],
    });
    JsonListScope scope({bool selected = false}) => JsonListScope(
      repositoryId: repositoryId,
      indices: [0],
      selected: selected,
      child: const SizedBox(),
    );
    const rowBinding = JsonTextBinding(path: 'rows[?].surface');
    final binding = SurfaceStateBinding(
      store: store,
      binding: rowBinding,
      scope: scope(),
    );
    addTearDown(binding.dispose);
    await waitFor(() => !binding.loading && binding.stateName == 'active');

    var notifications = 0;
    binding.addListener(() => notifications++);
    binding.reconfigure(
      store: store,
      binding: const JsonTextBinding(path: 'rows[?].surface'),
      scope: scope(selected: true),
    );
    binding.reconfigure(store: store, binding: rowBinding, scope: scope());

    expect(notifications, 0);
    expect(binding.loading, isFalse);
    expect(binding.stateName, 'active');
    expect(binding.error, isNull);
  });

  test('a configured binding without a store reports a local diagnostic', () {
    final binding = SurfaceStateBinding(
      store: null,
      binding: const JsonTextBinding(path: 'surface'),
    );
    addTearDown(binding.dispose);

    expect(binding.loading, isFalse);
    expect(binding.stateName, isNull);
    expect(binding.error, 'Repository service unavailable.');
  });

  test('selected is included in JsonListScope notification comparison', () {
    const child = SizedBox();
    final oldScope = JsonListScope(
      repositoryId: repositoryId,
      indices: const [0],
      child: child,
    );
    final selectedScope = JsonListScope(
      repositoryId: repositoryId,
      indices: const [0],
      selected: true,
      child: child,
    );

    expect(selectedScope.updateShouldNotify(oldScope), isTrue);
  });
}
