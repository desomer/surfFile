import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/models/datasources/datasource_config.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/providers/data_provider.dart';
import 'package:super_container_layout/services/datasources/super_backend_datasource_bridge.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';

const _rowsBinding = JsonTextBinding(
  repositoryId: 'clients_repo',
  path: 'rows',
);
const _detailBinding = JsonTextBinding(
  repositoryId: 'clients_repo',
  path: 'detail',
);
const _stateBinding = JsonTextBinding(
  repositoryId: 'filter_repo',
  path: 'state',
);

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late SuperBackend backend;
  late SuperBackendDatasourceBridge bridge;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('super-backend-bridge-');
    store = JsonRepositoryStore(directory);
    store.registerRepository(
      RepositoryImpl(
        id: 'filter_repo',
        json: {'city': '', 'state': <String, Object?>{}},
      ),
    );
    store.registerRepository(
      RepositoryImpl(id: 'form_repo', json: {'name': '', 'city': '', 'age': 0}),
    );
    store.registerRepository(
      RepositoryImpl(
        id: 'clients_repo',
        json: {'rows': <Object?>[], 'detail': <String, Object?>{}},
      ),
    );

    backend = SuperBackend(store: SqliteCollectionStore.inMemory());
    await backend.init();
    bridge = SuperBackendDatasourceBridge(backend: backend, store: store);
  });

  tearDown(() async {
    store.dispose();
    await backend.close();
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> readRepo(String id) async =>
      (await store.readDocument(id))! as Map<String, Object?>;

  test('Mode Code (registerCodeDatasource) exécute tout le cycle SCRUD sur SQLite', () async {
    await backend.create('clients', {
      'name': 'Alice',
      'city': 'Lyon',
      'age': 30,
    }, id: 'c1');
    await backend.create('clients', {
      'name': 'Bob',
      'city': 'Paris',
      'age': 25,
    }, id: 'c2');
    await backend.create('clients', {
      'name': 'Charlie',
      'city': 'Lyon',
      'age': 40,
    }, id: 'c3');

    bridge.registerCodeDatasource(
      datasourceId: 'clients',
      label: 'Clients',
      listTarget: _rowsBinding,
      detailTarget: _detailBinding,
      stateTarget: _stateBinding,
      searchFilterRepositoryId: 'filter_repo',
      formRepositoryId: 'form_repo',
      sort: DatasourceSort(
        fields: const ['name', 'age'],
        defaultOrder: const DatasourceSortOrder('age'),
      ),
      pagination: const DatasourcePagination(pageSize: 2, totalPath: 'total'),
    );

    // 1. Search (page 1, tri par age asc)
    var status = await store.datasources.run(
      'clients',
      DatasourceCommand.search,
    );
    expect(status.phase, DataProviderPhase.success);
    expect(status.page.total, 3);
    expect(status.page.page, 1);
    expect(status.page.hasNext, isTrue);

    var clientsDoc = await readRepo('clients_repo');
    var rows = clientsDoc['rows'] as List;
    expect(rows.map((r) => (r as Map)['name']).toList(), ['Bob', 'Alice']);

    // 2. Next page
    status = await store.datasources.run('clients', DatasourceCommand.nextPage);
    expect(status.phase, DataProviderPhase.success);
    expect(status.page.page, 2);
    expect(status.page.hasNext, isFalse);
    clientsDoc = await readRepo('clients_repo');
    rows = clientsDoc['rows'] as List;
    expect(rows.map((r) => (r as Map)['name']).toList(), ['Charlie']);

    // 3. Create depuis form_repo
    await store.updateValue('form_repo', 'name', (_) => 'Diane');
    await store.updateValue('form_repo', 'city', (_) => 'Bordeaux');
    await store.updateValue('form_repo', 'age', (_) => 28);

    status = await store.datasources.run('clients', DatasourceCommand.create);
    expect(status.phase, DataProviderPhase.success);
    expect(status.page.total, 4);
    clientsDoc = await readRepo('clients_repo');
    final detailAfterCreate = clientsDoc['detail'] as Map;
    expect(detailAfterCreate['name'], 'Diane');
    final dianeId = detailAfterCreate['id'] as String;

    // 4. Read de la ligne sélectionnée (Diane a été sélectionnée à la création)
    status = await store.datasources.run('clients', DatasourceCommand.read);
    expect(status.phase, DataProviderPhase.success);

    // 5. Update (merge) de Diane
    await store.updateValue('form_repo', 'city', (_) => 'Nantes');
    status = await store.datasources.run('clients', DatasourceCommand.update);
    expect(status.phase, DataProviderPhase.success);
    expect((await backend.read('clients', dianeId))['city'], 'Nantes');

    // 6. Delete de Diane
    status = await store.datasources.run('clients', DatasourceCommand.delete);
    expect(status.phase, DataProviderPhase.success);
    expect(await backend.readOrNull('clients', dianeId), isNull);
    expect(status.page.total, 3);

    bridge.unregisterCodeDatasource('clients');
    expect(store.datasources.datasource('clients'), isNull);
  });

  test('Mode Éditeur HTTP (installHttpTransport + saveEditorDatasource) fonctionne de bout en bout', () async {
    await backend.create('clients', {
      'name': 'Alice',
      'city': 'Lyon',
      'age': 30,
    }, id: 'c1');
    await backend.create('clients', {
      'name': 'Bob',
      'city': 'Paris',
      'age': 25,
    }, id: 'c2');

    bridge.installHttpTransport();
    await bridge.saveEditorDatasource(
      const ScrudDatasourceBlueprint(
        datasourceId: 'clients',
        label: 'Clients HTTP',
        listTarget: (repositoryId: 'clients_repo', path: 'rows'),
        detailTarget: (repositoryId: 'clients_repo', path: 'detail'),
        stateTarget: (repositoryId: 'filter_repo', path: 'state'),
        searchFilterRepositoryId: 'filter_repo',
        formRepositoryId: 'form_repo',
        pageSize: 5,
        sortFields: ['name', 'age'],
        defaultSort: ScrudSortOrder('name'),
      ),
    );

    // Recherche filtrée par ville = Lyon
    await store.updateValue('filter_repo', 'city', (_) => 'Lyon');
    var status = await store.datasources.run(
      'clients',
      DatasourceCommand.search,
    );
    expect(status.phase, DataProviderPhase.success);
    expect(status.page.total, 1);

    var clientsDoc = await readRepo('clients_repo');
    var rows = clientsDoc['rows'] as List;
    expect(rows.length, 1);
    expect((rows.first as Map)['id'], 'c1');

    // Sélectionne la première ligne et exécute Read / Update / Delete via HTTP virtuel
    store.bindingOf('clients_repo').array('rows').select(const [], 0);
    status = await store.datasources.run('clients', DatasourceCommand.read);
    expect(status.phase, DataProviderPhase.success);
    clientsDoc = await readRepo('clients_repo');
    expect((clientsDoc['detail'] as Map)['name'], 'Alice');

    await store.updateValue('form_repo', 'name', (_) => 'Alice Modifiée');
    await store.updateValue('form_repo', 'city', (_) => 'Lyon');
    await store.updateValue('form_repo', 'age', (_) => 31);
    status = await store.datasources.run('clients', DatasourceCommand.update);
    expect(status.phase, DataProviderPhase.success);
    expect((await backend.read('clients', 'c1'))['name'], 'Alice Modifiée');

    status = await store.datasources.run('clients', DatasourceCommand.delete);
    expect(status.phase, DataProviderPhase.success);
    expect(await backend.readOrNull('clients', 'c1'), isNull);
  });
}
