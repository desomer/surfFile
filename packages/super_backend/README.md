# super_backend

Package Dart pur fournissant une API générique **SCRUD** (*Search, Create, Read, Update, Delete*) adossée à une abstraction de stockage local (`CollectionStore`) et à une implémentation SQLite (`SqliteCollectionStore`).

## Modèle de stockage

Chaque entité JSON est stockée dans une table à trois colonnes :

| Colonne          | Type   | Description                                  |
| ---------------- | ------ | -------------------------------------------- |
| `nom_collection` | `TEXT` | Nom logique de la collection (`clients`, …)  |
| `id_entity`      | `TEXT` | Identifiant unique de l'entité               |
| `data_json`      | `TEXT` | Charge utile JSON sérialisée de l'entité     |

Clé primaire composite : `(nom_collection, id_entity)`.

## Utilisation rapide

```dart
import 'package:super_backend/super_backend.dart';

Future<void> main() async {
  final store = SqliteCollectionStore.inMemory();
  final backend = SuperBackend(store: store);
  await backend.init();

  final clients = backend.collection('clients');
  final created = await clients.create({'name': 'Alice', 'city': 'Lyon'});
  final id = created['id'] as String;

  final fetched = await clients.read(id);
  final updated = await clients.update(id, {'city': 'Paris'}, merge: true);
  final page = await clients.search(
    request: ScrudSearchRequest(
      pagination: const ScrudPagination(mode: ScrudPaginationMode.page, pageSize: 20),
      sort: const ScrudSortOrder('name'),
    ),
  );

  await clients.delete(id);
  await backend.close();
}
```

## Connecteur `Datasource` (`super_container_layout`)

`super_backend` fournit deux modes de connexion aux `Datasource` de `super_container_layout` via `SuperBackendDatasourceBridge` :

1. **Mode Code (`registerCodeDatasource`)** : enregistre directement les 5 `CallbackDataProvider` (`<id>_search`, `<id>_create`, `<id>_read`, `<id>_update`, `<id>_delete`) et la `DatasourceConfig` dans `store.providers` et `store.datasources`.
2. **Mode Éditeur / HTTP virtuel (`installHttpTransport` + `saveEditorDatasource`)** : installe un `SuperBackendHttpTransport` qui route les appels vers `https://super.backend/api/<collection>` sur `SuperBackendHttpRouter` et génère les 5 fichiers `HttpProviderConfig` + `DatasourceConfig` modifiables dans l'éditeur visuel.

