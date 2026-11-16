import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/models/datasources/datasource_config.dart';
import 'package:super_container_layout/models/datasources/datasource_state.dart';
import 'package:super_container_layout/models/json_text_binding.dart';

final _full = DatasourceConfig(
  id: 'clients',
  label: 'Clients',
  keyPath: 'id',
  search: DatasourceSearchConfig(
    provider: 'clients_search',
    state: const JsonTextBinding(repositoryId: 'filtre', path: 'etat'),
    sort: DatasourceSort(
      directionParam: 'order',
      fields: ['nom', 'ville'],
      defaultOrder: const DatasourceSortOrder(
        'nom',
        DatasourceSortDirection.desc,
      ),
    ),
    pagination: const DatasourcePagination(
      mode: DatasourcePaginationMode.cursor,
      pageSize: 50,
      nextCursorPath: 'meta.next',
      totalPath: 'meta.total',
    ),
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
  group('DatasourceConfig', () {
    test('round-trips through full and compact JSON', () {
      expect(DatasourceConfig.fromJson(_full.toJson()), _full);
      expect(DatasourceConfig.fromJson(_full.toCompactJson()), _full);

      const minimal = DatasourceConfig(
        id: 'pays',
        label: 'pays',
        search: DatasourceSearchConfig(provider: 'pays_search'),
      );
      expect(minimal.toCompactJson(), {
        'id': 'pays',
        'search': {'provider': 'pays_search'},
      });
      expect(DatasourceConfig.fromJson(minimal.toCompactJson()), minimal);
    });

    test('rejects unknown keys and invalid definitions', () {
      final invalid = <Map<String, Object?>>[
        {
          'id': 'clients',
          'search': {'provider': 'p'},
          'url': 'x',
        },
        {
          'id': 'clients',
          'search': {'provider': 'p', 'extra': true},
        },
        // Aucune opération.
        {'id': 'clients'},
        // Clé obligatoire hors recherche seule.
        {
          'id': 'clients',
          'update': {'provider': 'p'},
        },
        {
          'id': 'Clients',
          'search': {'provider': 'p'},
        },
        // Le curseur exige le chemin du curseur suivant.
        {
          'id': 'clients',
          'search': {
            'provider': 'p',
            'pagination': {'mode': 'cursor'},
          },
        },
        // Clé propre à un autre mode.
        {
          'id': 'clients',
          'search': {
            'provider': 'p',
            'pagination': {'mode': 'offset', 'pageParam': 'p'},
          },
        },
        {
          'id': 'clients',
          'search': {
            'provider': 'p',
            'pagination': {'pageSize': 0},
          },
        },
        {
          'id': 'clients',
          'search': {
            'provider': 'p',
            'sort': {
              'fields': ['nom'],
              'default': {'field': 'ville'},
            },
          },
        },
      ];
      for (final json in invalid) {
        expect(
          () => DatasourceConfig.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });

    test('lists the supported commands', () {
      expect(_full.commands, DatasourceCommand.values);
      const searchOnly = DatasourceConfig(
        id: 'pays',
        label: 'Pays',
        search: DatasourceSearchConfig(provider: 'pays_search'),
      );
      expect(searchOnly.commands, [
        DatasourceCommand.search,
        DatasourceCommand.refresh,
      ]);
      expect(_full.usesProvider('clients_delete'), isTrue);
      expect(_full.usesProvider('autre'), isFalse);
      expect(_full.usesRepository('filtre'), isTrue);
    });
  });

  group('request parameters', () {
    test('sort uses a separate direction or a minus prefix', () {
      const order = DatasourceSortOrder('nom', DatasourceSortDirection.desc);
      expect(DatasourceSort().parametersFor(order), {'sort': '-nom'});
      expect(
        DatasourceSort(
          fieldParam: 'by',
          directionParam: 'order',
        ).parametersFor(order),
        {'by': 'nom', 'order': 'desc'},
      );
      expect(DatasourceSort(fields: ['ville']).allows('nom'), isFalse);
    });

    test('pagination modes name their parameters', () {
      expect(
        const DatasourcePagination(pageSize: 10, firstPage: 0).parametersFor(2),
        {'page': 2, 'size': 10},
      );
      expect(
        const DatasourcePagination(
          mode: DatasourcePaginationMode.offset,
          pageSize: 10,
        ).parametersFor(2),
        {'offset': 20, 'limit': 10},
      );
      const cursor = DatasourcePagination(
        mode: DatasourcePaginationMode.cursor,
        pageSize: 10,
        nextCursorPath: 'next',
      );
      expect(cursor.parametersFor(0), {'limit': 10});
      expect(cursor.parametersFor(1, cursor: 'abc'), {
        'cursor': 'abc',
        'limit': 10,
      });
    });
  });

  test('DatasourcePageState round-trips through JSON', () {
    const state = DatasourcePageState(
      page: 2,
      pageSize: 20,
      offset: 20,
      total: 45,
      pageCount: 3,
      hasNext: true,
      hasPrevious: true,
      sort: DatasourceSortOrder('nom'),
    );
    expect(DatasourcePageState.fromJson(state.toJson()), state);
    expect(DatasourcePageState.fromJson(state.toCompactJson()), state);
  });
}
