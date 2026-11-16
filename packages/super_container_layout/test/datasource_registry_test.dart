import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/models/component_behavior.dart';
import 'package:super_container_layout/models/datasources/datasource_config.dart';
import 'package:super_container_layout/models/datasources/datasource_state.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/providers/data_provider.dart';
import 'package:super_container_layout/models/providers/http_provider_config.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/theme/appearance.dart';

const _rows = JsonTextBinding(repositoryId: 'clients', path: 'rows');
const _detail = JsonTextBinding(repositoryId: 'clients', path: 'detail');
const _state = JsonTextBinding(repositoryId: 'filtre', path: 'etat');

DatasourceConfig _config({String id = 'clients'}) => DatasourceConfig(
  id: id,
  label: 'Clients',
  keyPath: 'id',
  search: DatasourceSearchConfig(
    provider: 'clients_search',
    state: _state,
    sort: DatasourceSort(fields: ['nom', 'id']),
    pagination: const DatasourcePagination(pageSize: 2, totalPath: 'total'),
  ),
  create: const DatasourceCreateConfig(
    provider: 'clients_create',
    insert: DatasourceInsert.start,
  ),
  read: const DatasourceEntityConfig(provider: 'clients_read'),
  update: const DatasourceEntityConfig(provider: 'clients_update'),
  delete: const DatasourceEntityConfig(provider: 'clients_delete'),
);

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late List<Map<String, Object?>> server;
  late List<DataProviderRequest> searches;
  late List<DataProviderRequest> mutations;
  Completer<void>? readGate;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('datasource-registry-');
    store = JsonRepositoryStore(directory);
    store.registerRepository(
      RepositoryImpl(
        id: 'filtre',
        json: {'q': 'a', 'etat': <String, Object?>{}},
      ),
    );
    store.registerRepository(
      RepositoryImpl(
        id: 'clients',
        json: {'rows': <Object?>[], 'detail': <String, Object?>{}},
      ),
    );
    server = [
      for (var i = 1; i <= 5; i++) {'id': i, 'nom': 'Client $i'},
    ];
    searches = [];
    mutations = [];
    readGate = null;
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Map<String, Object?> find(Object? key) =>
      server.firstWhere((row) => row['id'] == key);

  void registerProviders() {
    final providers = store.providers;
    providers.register(
      CallbackDataProvider(
        id: 'clients_search',
        filterRepositoryId: 'filtre',
        target: _rows,
        onExecute: (request) async {
          searches.add(request);
          final page = request.context['page']! as int;
          final size = request.context['pageSize']! as int;
          final slice = server.skip((page - 1) * size).take(size).toList();
          return DataProviderResult(
            data: slice,
            raw: {'items': slice, 'total': server.length},
          );
        },
      ),
    );
    providers.register(
      CallbackDataProvider(
        id: 'clients_create',
        onExecute: (request) async {
          mutations.add(request);
          final entity = {'id': 99, 'nom': 'Nouveau'};
          server.insert(0, entity);
          return DataProviderResult(data: entity, raw: entity);
        },
      ),
    );
    providers.register(
      CallbackDataProvider(
        id: 'clients_read',
        target: _detail,
        onExecute: (request) async {
          final entity = Map<String, Object?>.of(find(request.context['key']));
          await readGate?.future;
          return DataProviderResult(data: entity, raw: entity);
        },
      ),
    );
    providers.register(
      CallbackDataProvider(
        id: 'clients_update',
        onExecute: (request) async {
          mutations.add(request);
          final entity = find(request.context['key'])..['nom'] = 'Modifié';
          return DataProviderResult(data: [entity]);
        },
      ),
    );
    providers.register(
      CallbackDataProvider(
        id: 'clients_delete',
        onExecute: (request) async {
          mutations.add(request);
          server.removeWhere((row) => row['id'] == request.context['key']);
          return const DataProviderResult();
        },
      ),
    );
  }

  Future<List<Object?>> ids() async => [
    for (final row in await store.readArray('clients', 'rows'))
      (row! as Map)['id'],
  ];

  Future<Map<Object?, Object?>> documentOf(String id) async =>
      (await store.readDocument(id))! as Map;

  Future<DatasourcePageState> pageState() async =>
      DatasourcePageState.fromJson((await documentOf('filtre'))['etat']);

  int? selected() =>
      store.bindingOf('clients').array('rows').indexFor(const []);

  void select(int index) =>
      store.bindingOf('clients').array('rows').select(const [], index);

  group('search', () {
    setUp(() {
      registerProviders();
      store.datasources.register(_config());
    });

    test('pages and sorts with the configured parameters', () async {
      final datasources = store.datasources;

      var status = await datasources.run('clients', DatasourceCommand.search);
      expect(status.phase, DataProviderPhase.success);
      expect(searches.last.parameters, {'q': 'a'});
      expect(searches.last.extraParameters, {'page': 1, 'size': 2});
      expect(await ids(), [1, 2]);
      var page = await pageState();
      expect(page.page, 1);
      expect(page.total, 5);
      expect(page.pageCount, 3);
      expect(page.hasNext, isTrue);
      expect(page.hasPrevious, isFalse);

      await datasources.run('clients', DatasourceCommand.nextPage);
      await datasources.run('clients', DatasourceCommand.nextPage);
      expect(searches.last.extraParameters, {'page': 3, 'size': 2});
      expect(await ids(), [5]);
      page = await pageState();
      expect(page.hasNext, isFalse);
      expect(page.hasPrevious, isTrue);

      // Pas de page suivante : rien n'est lancé.
      await datasources.run('clients', DatasourceCommand.nextPage);
      expect(searches, hasLength(3));

      await datasources.run('clients', DatasourceCommand.previousPage);
      expect(searches.last.extraParameters, {'page': 2, 'size': 2});

      await datasources.run('clients', DatasourceCommand.sort, field: 'nom');
      expect(searches.last.extraParameters, {
        'sort': 'nom',
        'page': 1,
        'size': 2,
      });
      expect(searches.last.context['sort'], 'nom');
      await datasources.run('clients', DatasourceCommand.sort, field: 'nom');
      expect(searches.last.extraParameters['sort'], '-nom');
      expect(
        (await pageState()).sort,
        const DatasourceSortOrder('nom', DatasourceSortDirection.desc),
      );

      status = await datasources.run(
        'clients',
        DatasourceCommand.sort,
        field: 'ville',
        reportErrors: false,
      );
      expect(status.phase, DataProviderPhase.error);
      expect(searches, hasLength(6));
      expect(datasources.stateOf('clients').value, status);
    });

    test('loadMore appends the next page without duplicate keys', () async {
      final datasources = store.datasources;
      await datasources.run('clients', DatasourceCommand.search);
      select(1);
      // Une insertion côté serveur décale la page suivante d'une ligne.
      server.insert(0, {'id': 0, 'nom': 'Client 0'});

      await datasources.run('clients', DatasourceCommand.loadMore);

      expect(await ids(), [1, 2, 3]);
      expect(selected(), 1);
      expect((await pageState()).page, 2);
      expect((await pageState()).hasPrevious, isFalse);
    });

    test('a new search keeps the selected row by key', () async {
      final datasources = store.datasources;
      await datasources.run('clients', DatasourceCommand.search);
      select(1);
      server.removeAt(0);

      await datasources.run('clients', DatasourceCommand.search);
      expect(await ids(), [2, 3]);
      expect(selected(), 0);

      server.removeAt(0);
      await datasources.run('clients', DatasourceCommand.refresh);
      expect(await ids(), [3, 4]);
      expect(selected(), isNull);
    });
  });

  group('entities', () {
    setUp(() {
      registerProviders();
      store.datasources.register(_config());
    });

    test(
      'create, update and delete keep the list and detail in sync',
      () async {
        final datasources = store.datasources;
        await datasources.run('clients', DatasourceCommand.search);
        select(1);

        var status = await datasources.run('clients', DatasourceCommand.create);
        expect(status.phase, DataProviderPhase.success);
        expect(await ids(), [99, 1, 2]);
        expect(selected(), 0);
        expect((await documentOf('clients'))['detail'], {
          'id': 99,
          'nom': 'Nouveau',
        });
        expect((await pageState()).total, 6);

        select(2);
        status = await datasources.run('clients', DatasourceCommand.update);
        expect(status.phase, DataProviderPhase.success);
        expect(mutations.last.context['key'], 2);
        expect(mutations.last.context['entity'], {'id': 2, 'nom': 'Client 2'});
        final rows = await store.readArray('clients', 'rows');
        expect(rows[2], {'id': 2, 'nom': 'Modifié'});
        // Le détail affiche une autre entité : il n'est pas modifié.
        expect((await documentOf('clients'))['detail'], {
          'id': 99,
          'nom': 'Nouveau',
        });

        await datasources.run('clients', DatasourceCommand.delete);
        expect(await ids(), [99, 1]);
        expect(selected(), isNull);
        expect((await pageState()).total, 5);

        select(0);
        await datasources.run('clients', DatasourceCommand.delete);
        expect(await ids(), [1]);
        expect((await documentOf('clients'))['detail'], <String, Object?>{});
      },
    );

    test('entity commands need a current entity', () async {
      final status = await store.datasources.run(
        'clients',
        DatasourceCommand.update,
        reportErrors: false,
      );
      expect(status.phase, DataProviderPhase.error);
      expect(status.message, contains('Aucune entité courante'));
      expect(mutations, isEmpty);
    });

    test('a read answered after an update does not overwrite it', () async {
      final datasources = store.datasources;
      await datasources.run('clients', DatasourceCommand.search);
      select(0);
      await datasources.run('clients', DatasourceCommand.read);
      expect((await documentOf('clients'))['detail'], {
        'id': 1,
        'nom': 'Client 1',
      });

      readGate = Completer<void>();
      final staleRead = datasources.run('clients', DatasourceCommand.read);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await datasources.run('clients', DatasourceCommand.update);
      readGate!.complete();
      await staleRead;

      expect((await documentOf('clients'))['detail'], {
        'id': 1,
        'nom': 'Modifié',
      });
    });
  });

  group('definitions', () {
    test('persists editor datasources and guards their use', () async {
      final datasources = store.datasources;
      final config = _config();
      await datasources.save(config);
      expect(
        File(
          '${directory.path}${Platform.pathSeparator}datasources'
          '${Platform.pathSeparator}clients.json',
        ).existsSync(),
        isTrue,
      );
      expect(datasources.isEditable('clients'), isTrue);
      expect(datasources.problemsOf(config), hasLength(5));

      final other = JsonRepositoryStore(directory);
      addTearDown(other.dispose);
      await other.datasources.ensureLoaded();
      expect(other.datasources.datasource('clients'), config);

      final appearance = Appearance(
        behaviors: {
          'button': [
            const ComponentBehavior(
              id: 'b-1',
              trigger: BehaviorTrigger.click,
              action: DatasourceAction(datasourceId: 'clients'),
            ),
          ],
        },
      );
      expect(appearance.usesDatasource('clients'), isTrue);
      await expectLater(
        datasources.delete('clients', appearance: appearance),
        throwsFormatException,
      );
      await datasources.delete('clients', appearance: Appearance());
      expect(datasources.datasource('clients'), isNull);

      datasources.register(_config(id: 'code'));
      expect(datasources.isEditable('code'), isFalse);
      await expectLater(
        datasources.save(_config(id: 'code')),
        throwsFormatException,
      );
    });

    test('a provider used by a datasource cannot be deleted', () async {
      await store.providers.save(
        HttpProviderConfig(
          id: 'clients_search',
          label: 'Recherche',
          target: _rows,
          request: HttpRequestTemplate(url: 'https://api.test/clients'),
        ),
      );
      await store.datasources.save(
        const DatasourceConfig(
          id: 'clients',
          label: 'Clients',
          search: DatasourceSearchConfig(provider: 'clients_search'),
        ),
      );

      await expectLater(
        store.providers.delete('clients_search'),
        throwsFormatException,
      );

      await store.datasources.delete('clients');
      await store.providers.delete('clients_search');
      expect(store.providers.provider('clients_search'), isNull);
    });
  });
}
