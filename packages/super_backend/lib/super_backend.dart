/// Point d'entrée public du package `super_backend`.
///
/// Expose les modèles SCRUD, l'abstraction de stockage local [CollectionStore],
/// l'implémentation SQLite [SqliteCollectionStore], l'implémentation mémoire
/// [MemoryCollectionStore] et le service générique [SuperBackend].
library;

export 'src/backend/super_backend_service.dart';
export 'src/connector/scrud_datasource_connector.dart';
export 'src/connector/super_backend_http_router.dart';
export 'src/models/scrud_exceptions.dart';
export 'src/models/scrud_query.dart';
export 'src/models/scrud_result.dart';
export 'src/storage/collection_store.dart';
export 'src/storage/memory_collection_store.dart';
export 'src/storage/sqlite_collection_store.dart';
