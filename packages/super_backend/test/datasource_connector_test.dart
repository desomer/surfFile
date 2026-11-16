import 'dart:convert';

import 'package:super_backend/super_backend.dart';
import 'package:test/test.dart';

void main() {
  group('ScrudDatasourceConnector', () {
    late SuperBackend backend;
    late ScrudDatasourceConnector connector;

    setUp(() async {
      backend = SuperBackend(store: SqliteCollectionStore.inMemory());
      await backend.init();
      connector = ScrudDatasourceConnector(
        backend: backend,
        collection: 'clients',
      );
    });

    tearDown(() async {
      await backend.close();
    });

    test(
      'exécute le cycle complet Create / Search / Read / Update / Delete',
      () async {
        final created = await connector.execute(
          ScrudOperation.create,
          parameters: {'id': 'c1', 'name': 'Alice', 'city': 'Lyon'},
        );
        expect((created.data as Map)['id'], 'c1');

        await connector.execute(
          ScrudOperation.create,
          parameters: {'id': 'c2', 'name': 'Bob', 'city': 'Paris'},
        );

        final search = await connector.execute(
          ScrudOperation.search,
          parameters: {'city': 'Lyon'},
          extraParameters: {'page': 1, 'size': 10, 'sort': 'name'},
        );
        final rows = search.data as List;
        final raw = search.raw as Map<String, Object?>;
        expect(rows.length, 1);
        expect((rows.first as Map)['name'], 'Alice');
        expect(raw['total'], 1);
        expect((raw['items'] as List).length, 1);

        final read = await connector.execute(
          ScrudOperation.read,
          context: {'key': 'c1'},
        );
        expect((read.data as Map)['city'], 'Lyon');

        final updated = await connector.execute(
          ScrudOperation.update,
          parameters: {'city': 'Bordeaux'},
          context: {'key': 'c1'},
        );
        expect((updated.data as Map)['name'], 'Alice');
        expect((updated.data as Map)['city'], 'Bordeaux');

        final deleted = await connector.execute(
          ScrudOperation.delete,
          context: {'key': 'c1'},
        );
        expect(deleted.data, isNull);
        expect(await backend.count('clients'), 1);
      },
    );
  });

  group('SuperBackendHttpRouter & ScrudDatasourceBlueprint', () {
    late SuperBackend backend;
    late SuperBackendHttpRouter router;

    setUp(() async {
      backend = SuperBackend(store: SqliteCollectionStore.inMemory());
      await backend.init();
      router = SuperBackendHttpRouter(backend: backend);
    });

    tearDown(() async {
      await backend.close();
    });

    test('route les requêtes HTTP REST (POST, GET list, GET id, PATCH, PUT, DELETE)', () async {
      final baseUri = Uri.parse('https://super.backend/api/clients');
      expect(router.matchesUri(baseUri), isTrue);
      expect(
        router.matchesUri(Uri.parse('https://example.com/api/clients')),
        isFalse,
      );

      final createRes = await router.handle(
        SuperBackendHttpRequest(
          method: 'POST',
          uri: baseUri,
          body: jsonEncode({'id': 'c1', 'name': 'Alice', 'score': 10}),
        ),
      );
      expect(createRes.statusCode, 201);
      expect((jsonDecode(createRes.body) as Map)['id'], 'c1');

      final listRes = await router.handle(
        SuperBackendHttpRequest(
          method: 'GET',
          uri: Uri.parse(
            'https://super.backend/api/clients?page=1&size=5&score=10',
          ),
        ),
      );
      expect(listRes.statusCode, 200);
      final listBody = jsonDecode(listRes.body) as Map<String, Object?>;
      expect(listBody['total'], 1);
      expect(((listBody['items'] as List).first as Map)['name'], 'Alice');

      final readRes = await router.handle(
        SuperBackendHttpRequest(
          method: 'GET',
          uri: Uri.parse('https://super.backend/api/clients/c1'),
        ),
      );
      expect(readRes.statusCode, 200);
      expect((jsonDecode(readRes.body) as Map)['name'], 'Alice');

      final patchRes = await router.handle(
        SuperBackendHttpRequest(
          method: 'PATCH',
          uri: Uri.parse('https://super.backend/api/clients/c1'),
          body: jsonEncode({'score': 25}),
        ),
      );
      expect(patchRes.statusCode, 200);
      final patched = jsonDecode(patchRes.body) as Map<String, Object?>;
      expect(patched['name'], 'Alice');
      expect(patched['score'], 25);

      final deleteRes = await router.handle(
        SuperBackendHttpRequest(
          method: 'DELETE',
          uri: Uri.parse('https://super.backend/api/clients/c1'),
        ),
      );
      expect(deleteRes.statusCode, 204);

      final missingRes = await router.handle(
        SuperBackendHttpRequest(
          method: 'GET',
          uri: Uri.parse('https://super.backend/api/clients/c1'),
        ),
      );
      expect(missingRes.statusCode, 404);
    });

    test(
      'ScrudDatasourceBlueprint génère les JSON Datasource et HttpProviders',
      () {
        const blueprint = ScrudDatasourceBlueprint(
          datasourceId: 'clients',
          label: 'Clients',
          listTarget: (repositoryId: 'clients_repo', path: 'rows'),
          detailTarget: (repositoryId: 'clients_repo', path: 'detail'),
          stateTarget: (repositoryId: 'filter_repo', path: 'state'),
          searchFilterRepositoryId: 'filter_repo',
          formRepositoryId: 'form_repo',
          sortFields: ['name', 'city'],
        );

        final providers = blueprint.buildHttpProviderJsons();
        expect(providers.length, 5);
        expect(providers.map((p) => p['id']).toList(), [
          'clients_search',
          'clients_create',
          'clients_read',
          'clients_update',
          'clients_delete',
        ]);

        final dsJson = blueprint.buildDatasourceJson();
        expect(dsJson['id'], 'clients');
        expect(dsJson['keyPath'], 'id');
        expect((dsJson['search'] as Map)['provider'], 'clients_search');
        expect((dsJson['read'] as Map)['provider'], 'clients_read');
      },
    );
  });
}
