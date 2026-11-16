import 'package:super_backend/super_backend.dart';

Future<void> main() async {
  final backend = SuperBackend(store: SqliteCollectionStore.inMemory());
  await backend.init();

  final clients = backend.collection('clients');

  final alice = await clients.create({
    'name': 'Alice Martin',
    'city': 'Lyon',
    'age': 32,
  });
  await clients.create({'name': 'Bob Durand', 'city': 'Paris', 'age': 41});

  final id = alice['id'] as String;
  final fetched = await clients.read(id);
  print('Read: $fetched');

  final updated = await clients.update(id, {'city': 'Bordeaux'}, merge: true);
  print('Updated: $updated');

  final search = await clients.search(
    parameters: {'page': 1, 'size': 10, 'sort': '-age'},
  );
  print('Search envelope: ${search.toJson()}');

  await clients.delete(id);
  print('Remaining count: ${await clients.count()}');

  // Utilisation via le connecteur Datasource direct
  final connector = ScrudDatasourceConnector(
    backend: backend,
    collection: 'clients',
  );
  final dsSearch = await connector.execute(
    ScrudOperation.search,
    extraParameters: {'page': 1, 'size': 5},
  );
  print('Connector rows: ${dsSearch.data}');

  await backend.close();
}
