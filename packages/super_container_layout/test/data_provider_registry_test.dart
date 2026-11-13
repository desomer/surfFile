import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/models/component_behavior.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/providers/data_provider.dart';
import 'package:super_container_layout/models/providers/http_provider_config.dart';
import 'package:super_container_layout/services/providers/data_provider_http_transport.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/theme/appearance.dart';

const _query = JsonTextBinding(repositoryId: 'filtre', path: 'q');
const _busy = JsonTextBinding(repositoryId: 'filtre', path: 'busy');
const _error = JsonTextBinding(repositoryId: 'filtre', path: 'error');
const _target = JsonTextBinding(repositoryId: 'resultats', path: 'rows');

class _FakeTransport extends DataProviderHttpTransport {
  final requests = <DataProviderHttpRequest>[];

  @override
  Future<DataProviderHttpResponse> send(DataProviderHttpRequest request) async {
    requests.add(request);
    return const DataProviderHttpResponse(statusCode: 200, body: '[{"id": 9}]');
  }
}

HttpProviderConfig _httpConfig({String id = 'clients'}) => HttpProviderConfig(
  id: id,
  label: 'Clients',
  filterRepositoryId: 'filtre',
  target: _target,
  loading: _busy,
  error: _error,
  request: HttpRequestTemplate(url: 'https://api.test/clients'),
);

void main() {
  late Directory directory;
  late JsonRepositoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('provider-registry-');
    store = JsonRepositoryStore(directory);
    store.registerRepository(
      RepositoryImpl(
        id: 'filtre',
        json: {'q': 'dupont', 'busy': false, 'error': 'ancienne'},
      ),
    );
    store.registerRepository(
      RepositoryImpl(id: 'resultats', json: {'rows': <Object?>[]}),
    );
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Future<Object?> valueOf(JsonTextBinding binding) async =>
      (await store.readAttribute(binding)).value;

  CallbackDataProvider provider(
    DataProviderCallback callback, {
    String id = 'clients',
    JsonTextBinding target = _target,
    ProviderAutoSearch? autoSearch,
  }) => CallbackDataProvider(
    id: id,
    label: 'Clients (code)',
    filterRepositoryId: 'filtre',
    target: target,
    loading: _busy,
    error: _error,
    autoSearch: autoSearch,
    callback: callback,
  );

  group('search', () {
    test('writes rows and flags from the filter parameters', () async {
      final calls = <Map<String, Object?>>[];
      Object? busyDuringFetch;
      store.providers.register(
        provider((parameters) async {
          calls.add(parameters);
          busyDuringFetch = await valueOf(_busy);
          return [
            {'name': 'Dupont'},
          ];
        }),
      );

      final status = await store.providers.search('clients');

      expect(calls, [
        {'q': 'dupont'},
      ]);
      expect(busyDuringFetch, isTrue);
      expect(await store.readArray('resultats', 'rows'), [
        {'name': 'Dupont'},
      ]);
      expect(await valueOf(_busy), isFalse);
      expect(await valueOf(_error), '');
      expect(status.phase, DataProviderPhase.success);
      expect(status.rowCount, 1);
      expect(store.providers.statusOf('clients').value, status);
    });

    test(
      'clears the error flag even if the loading flag cannot be written',
      () async {
        final brokenLoading = JsonTextBinding(
          repositoryId: 'filtre',
          path: 'items[0]',
        );
        store.providers.register(
          CallbackDataProvider(
            id: 'broken_flag',
            filterRepositoryId: 'filtre',
            target: _target,
            loading: brokenLoading,
            error: _error,
            callback: (_) async => const [],
          ),
        );

        final status = await store.providers.search('broken_flag');

        expect(status.phase, DataProviderPhase.success);
        expect(await valueOf(_error), '');
        expect(store.errors.value, contains('indicateur de chargement'));
      },
    );

    test('a failure sets the error flag and keeps previous rows', () async {
      store.providers.register(
        provider((_) async => throw const DataProviderException('Panne API')),
      );

      final quiet = await store.providers.search(
        'clients',
        reportErrors: false,
      );
      expect(quiet.phase, DataProviderPhase.error);
      expect(quiet.message, 'Panne API');
      expect(store.errors.value, isNull);
      expect(await valueOf(_error), 'Panne API');
      expect(await valueOf(_busy), isFalse);
      expect(await store.readArray('resultats', 'rows'), isEmpty);

      await store.providers.search('clients');
      expect(store.errors.value, 'Panne API');

      final unknown = await store.providers.search('inconnu');
      expect(unknown.message, contains('introuvable'));
    });

    test('a newer search supersedes a pending one', () async {
      final first = Completer<List<Object?>>();
      final started = Completer<void>();
      var calls = 0;
      store.providers.register(
        provider((_) {
          calls++;
          if (calls == 1) {
            started.complete();
            return first.future;
          }
          return Future.value(['récent']);
        }),
      );

      final pending = store.providers.search('clients');
      await started.future;
      final latest = await store.providers.search('clients');
      first.complete(['ancien']);
      final superseded = await pending;

      expect(latest.phase, DataProviderPhase.success);
      expect(superseded, latest);
      expect(await store.readArray('resultats', 'rows'), ['récent']);
      expect(await valueOf(_busy), isFalse);
    });

    test('preview runs a draft without writing anything', () async {
      final transport = _FakeTransport();
      store.providers.httpTransport = transport;

      expect(await store.providers.preview(_httpConfig()), [
        {'id': 9},
      ]);
      expect(transport.requests.single.uri.queryParameters, {'q': 'dupont'});
      expect(await store.readArray('resultats', 'rows'), isEmpty);
      expect(await valueOf(_error), 'ancienne');
    });
  });

  group('definitions', () {
    test('editor providers are saved, reloaded and deleted', () async {
      final transport = _FakeTransport();
      store.providers.httpTransport = transport;
      await store.providers.save(_httpConfig());
      final file = File(
        '${directory.path}${Platform.pathSeparator}providers'
        '${Platform.pathSeparator}clients.json',
      );
      expect(jsonDecode(await file.readAsString()), _httpConfig().toJson());

      final status = await store.providers.search('clients');
      expect(status.rowCount, 1);
      expect(await store.readArray('resultats', 'rows'), [
        {'id': 9},
      ]);

      final restored = JsonRepositoryStore(Directory(directory.path));
      addTearDown(restored.dispose);
      await restored.providers.ensureLoaded();
      expect(restored.providers.isEditable('clients'), isTrue);
      expect(restored.providers.configOf('clients'), _httpConfig());

      final appearance = Appearance(
        behaviors: {
          'button': [
            const ComponentBehavior(
              id: 'search',
              trigger: BehaviorTrigger.click,
              action: SearchProviderAction(providerId: 'clients'),
            ),
          ],
        },
      );
      await expectLater(
        store.providers.delete('clients', appearance: appearance),
        throwsFormatException,
      );
      expect(await file.exists(), isTrue);

      await store.providers.delete('clients', appearance: Appearance());
      expect(await file.exists(), isFalse);
      expect(store.providers.provider('clients'), isNull);
    });

    test(
      'code providers cannot be saved, deleted or registered twice',
      () async {
        final code = provider((_) async => const []);
        store.providers.register(code);

        expect(store.providers.isEditable('clients'), isFalse);
        expect(store.providers.provider('clients'), same(code));
        expect(() => store.providers.register(code), throwsArgumentError);
        await expectLater(
          store.providers.save(_httpConfig()),
          throwsFormatException,
        );
        await expectLater(
          store.providers.delete('clients'),
          throwsFormatException,
        );
        expect(store.providers.unregister('clients'), isTrue);
        expect(store.providers.provider('clients'), isNull);
      },
    );

    test('invalid provider files are reported and skipped', () async {
      final folder = Directory(
        '${directory.path}${Platform.pathSeparator}providers',
      )..createSync();
      void write(String name, String text) =>
          File('${folder.path}${Platform.pathSeparator}$name')
              .writeAsStringSync(text);
      write('clients.json', jsonEncode(_httpConfig().toJson()));
      write('casse.json', '{ pas du json');
      write('autre.json', jsonEncode(_httpConfig().toJson()));

      await store.providers.ensureLoaded();

      expect(store.providers.provider('clients'), isNotNull);
      expect(store.providers.provider('casse'), isNull);
      expect(store.providers.provider('autre'), isNull);
      expect(
        store.errors.value,
        allOf(
          startsWith('Providers ignorés'),
          contains('« casse » : JSON invalide.'),
          contains('« autre »'),
        ),
      );
    });

    test('a repository used by a provider cannot be deleted', () async {
      store.providers.register(provider((_) async => const []));
      await expectLater(
        store.delete('resultats'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('provider « Clients (code) »'),
          ),
        ),
      );
      expect(store.providers.unregister('clients'), isTrue);
      await store.delete('resultats');
    });
  });

  group('auto search', () {
    test(
      'runs once after the filter settles, not after its own writes',
      () async {
        final calls = <Map<String, Object?>>[];
        store.providers.register(
          provider(
            (parameters) async {
              calls.add(parameters);
              return ['ligne ${calls.length}'];
            },
            target: const JsonTextBinding(repositoryId: 'filtre', path: 'rows'),
            autoSearch: const ProviderAutoSearch(debounceMs: 100),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await store.writeAttribute(_query, 'martin', expectedValue: 'dupont');
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await store.writeAttribute(_query, 'durand', expectedValue: 'martin');
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(calls, [
          {'q': 'durand'},
        ]);
        expect(await store.readArray('filtre', 'rows'), ['ligne 1']);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(calls, hasLength(1));
      },
    );

    test('stale flags are reset on load and onStart searches run', () async {
      await store.writeAttribute(
        _busy,
        'true',
        expectedValue: false,
        asBool: true,
      );
      var manualCalls = 0;
      store.providers.register(
        provider((_) async {
          manualCalls++;
          return const [];
        }),
      );

      await store.providers.ensureLoaded();

      expect(await valueOf(_busy), isFalse);
      expect(manualCalls, 0);

      final started = Completer<Map<String, Object?>>();
      store.providers.register(
        provider(
          (parameters) async {
            started.complete(parameters);
            return const [];
          },
          id: 'auto',
          autoSearch: const ProviderAutoSearch(onStart: true),
        ),
      );
      expect(await started.future, {'q': 'dupont'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.providers.statusOf('auto').value.rowCount, 0);
      expect(manualCalls, 0);
    });
  });
}
