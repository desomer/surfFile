/// Service principal SCRUD de `super_backend` : [SuperBackend] et [CollectionApi].
///
/// Orchestre les opérations génériques **Search**, **Create**, **Read**,
/// **Update** et **Delete** sur des collections JSON stockées via un
/// [CollectionStore] (`(nom_collection, id_entity, data_json)`).
///
/// Fournit à la fois :
/// * une API typée par collection via [SuperBackend.collection] ;
/// * un point d'entrée unifié [SuperBackend.execute] retournant des structures
///   JSON directement consommables par `DatasourceConfig` /
///   `CallbackDataProvider` (`items`, `total`, `nextCursor`, entité ou `null`).
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/scrud_exceptions.dart';
import '../models/scrud_query.dart';
import '../models/scrud_result.dart';
import '../storage/collection_store.dart';

const _uuid = Uuid();

String _defaultIdGenerator() => _uuid.v4();

/// Service générique SCRUD s'appuyant sur un [CollectionStore] local.
class SuperBackend {
  /// Crée une instance de backend adossée à [store].
  ///
  /// Si [keyField] est non nul (par défaut `'id'`), l'identifiant d'entité
  /// (`id_entity`) est lu depuis et synchronisé dans ce champ du JSON.
  SuperBackend({
    required this.store,
    this.keyField = 'id',
    String Function()? idGenerator,
  }) : _idGenerator = idGenerator ?? _defaultIdGenerator;

  final String Function() _idGenerator;

  /// Nom du champ JSON synchronisé avec `id_entity`, ou `null` pour ne pas
  /// modifier les données JSON.
  final String? keyField;

  /// Store sous-jacent utilisé pour la persistance.
  final CollectionStore store;

  /// Initialise le store sous-jacent.
  Future<void> init() => store.init();

  /// Ferme le store sous-jacent et libère ses ressources.
  Future<void> close() => store.close();

  /// Retourne une façade liée à la collection [collectionName].
  CollectionApi collection(String collectionName) {
    validateCollectionName(collectionName);
    return CollectionApi._(this, collectionName);
  }

  /// Exécute une recherche paginée, triée et filtrée sur [collection].
  ///
  /// Fournir soit [request], soit [parameters] (carte plate compatible avec
  /// `DatasourceConfig`), soit aucun des deux pour une recherche par défaut.
  Future<ScrudSearchResult> search(
    String collection, {
    ScrudSearchRequest? request,
    Map<String, Object?>? parameters,
  }) async {
    validateCollectionName(collection);
    if (request != null && parameters != null) {
      throw const InvalidQueryException(
        'Fournir soit « request », soit « parameters », mais pas les deux.',
      );
    }
    final effective =
        request ??
        (parameters != null
            ? ScrudSearchRequest.fromParameters(parameters)
            : ScrudSearchRequest());
    effective.validate();

    final pageResult = await store.query(collection, effective);
    final offset = effective.pagination.effectiveOffset;
    final pageSize = effective.pagination.pageSize;
    final hasPrevious = offset > 0;
    final hasNext = offset + pageResult.rows.length < pageResult.total;
    final nextCursor = hasNext
        ? ScrudPagination.encodeCursorOffset(offset + pageResult.rows.length)
        : null;

    final items = <Map<String, Object?>>[
      for (final row in pageResult.rows) _decodeRow(row),
    ];

    return ScrudSearchResult(
      items: items,
      total: pageResult.total,
      page: effective.pagination.normalizedPageNumber,
      pageSize: pageSize,
      offset: offset,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
      nextCursor: nextCursor,
      sort: effective.sort,
    );
  }

  /// Crée une nouvelle entité JSON dans [collection].
  ///
  /// L'identifiant est résolu dans l'ordre : [id] explicite, champ [keyField]
  /// présent dans [data] (si texte non vide), ou génération automatique.
  /// Si [upsert] vaut `true`, remplace une entité existante de même
  /// identifiant ; sinon lève [EntityAlreadyExistsException].
  Future<Map<String, Object?>> create(
    String collection,
    Map<String, Object?> data, {
    String? id,
    bool upsert = false,
  }) async {
    validateCollectionName(collection);
    final normalized = _normalizePayload(data);
    final resolvedId = _resolveCreateId(id, normalized);
    validateEntityId(resolvedId);

    if (keyField != null) {
      normalized[keyField!] = resolvedId;
    }

    final row = StoredJsonRow(
      nomCollection: collection,
      idEntity: resolvedId,
      dataJson: jsonEncode(normalized),
    );
    if (upsert) {
      await store.upsert(row);
    } else {
      await store.insert(row);
    }
    return _freezeMap(normalized);
  }

  /// Lit l'entité [id] de [collection], ou lève [EntityNotFoundException].
  Future<Map<String, Object?>> read(String collection, String id) async {
    final entity = await readOrNull(collection, id);
    if (entity == null) {
      throw EntityNotFoundException(collection: collection, entityId: id);
    }
    return entity;
  }

  /// Lit l'entité [id] de [collection], ou retourne `null` si elle est absente.
  Future<Map<String, Object?>?> readOrNull(String collection, String id) async {
    validateCollectionName(collection);
    validateEntityId(id);
    final row = await store.findById(collection, id);
    if (row == null) return null;
    return _freezeMap(_decodeRow(row));
  }

  /// Met à jour l'entité [id] de [collection].
  ///
  /// Si [merge] vaut `false` (défaut), remplace intégralement le document JSON.
  /// Si [merge] vaut `true`, fusionne récursivement les sous-objets JSON avec
  /// le document existant. Lève [EntityNotFoundException] si l'entité
  /// n'existe pas.
  Future<Map<String, Object?>> update(
    String collection,
    String id,
    Map<String, Object?> data, {
    bool merge = false,
  }) async {
    validateCollectionName(collection);
    validateEntityId(id);
    final patch = _normalizePayload(data);

    final Map<String, Object?> next;
    if (merge) {
      final existingRow = await store.findById(collection, id);
      if (existingRow == null) {
        throw EntityNotFoundException(collection: collection, entityId: id);
      }
      final existingData = _decodeRow(existingRow);
      next = _deepMerge(existingData, patch);
    } else {
      next = patch;
    }

    if (keyField != null) {
      next[keyField!] = id;
    }

    final updated = await store.update(
      StoredJsonRow(
        nomCollection: collection,
        idEntity: id,
        dataJson: jsonEncode(next),
      ),
    );
    if (!updated) {
      throw EntityNotFoundException(collection: collection, entityId: id);
    }
    return _freezeMap(next);
  }

  /// Supprime l'entité [id] de [collection].
  ///
  /// Lève [EntityNotFoundException] si l'entité n'existe pas, sauf si
  /// [ignoreMissing] vaut `true`.
  Future<void> delete(
    String collection,
    String id, {
    bool ignoreMissing = false,
  }) async {
    validateCollectionName(collection);
    validateEntityId(id);
    final deleted = await store.delete(collection, id);
    if (!deleted && !ignoreMissing) {
      throw EntityNotFoundException(collection: collection, entityId: id);
    }
  }

  /// Dispatch générique d'une opération SCRUD retournant directement une
  /// enveloppe JSON prête pour un provider (`Map` pour search/create/read/
  /// update, `null` pour delete).
  Future<Object?> execute(
    String collection,
    ScrudOperation operation, {
    String? id,
    Map<String, Object?>? data,
    ScrudSearchRequest? searchRequest,
    Map<String, Object?>? parameters,
    bool merge = false,
    bool upsert = false,
    bool ignoreMissing = false,
  }) async {
    switch (operation) {
      case ScrudOperation.search:
        final result = await search(
          collection,
          request: searchRequest,
          parameters: parameters,
        );
        return result.toJson();
      case ScrudOperation.create:
        return create(collection, data ?? const {}, id: id, upsert: upsert);
      case ScrudOperation.read:
        if (id == null) {
          throw const InvalidEntityIdException('');
        }
        return read(collection, id);
      case ScrudOperation.update:
        if (id == null) {
          throw const InvalidEntityIdException('');
        }
        return update(collection, id, data ?? const {}, merge: merge);
      case ScrudOperation.delete:
        if (id == null) {
          throw const InvalidEntityIdException('');
        }
        await delete(collection, id, ignoreMissing: ignoreMissing);
        return null;
    }
  }

  /// Retourne le nombre d'entités stockées dans [collection].
  Future<int> count(String collection) {
    validateCollectionName(collection);
    return store.count(collection);
  }

  /// Retourne la liste triée des collections non vides.
  Future<List<String>> listCollections() => store.listCollections();

  /// Vide toutes les entités de [collection] et retourne le nombre supprimé.
  Future<int> clearCollection(String collection) {
    validateCollectionName(collection);
    return store.clearCollection(collection);
  }

  String _resolveCreateId(String? explicitId, Map<String, Object?> data) {
    if (explicitId != null) return explicitId;
    final key = keyField;
    if (key != null && data[key] is String) {
      final candidate = (data[key] as String).trim();
      if (candidate.isNotEmpty) return candidate;
    }
    return _idGenerator();
  }

  Map<String, Object?> _decodeRow(StoredJsonRow row) {
    final decoded = row.decodeData();
    final key = keyField;
    if (key != null && !decoded.containsKey(key)) {
      decoded[key] = row.idEntity;
    }
    return decoded;
  }

  static Map<String, Object?> _normalizePayload(Map<String, Object?> data) {
    try {
      final encoded = jsonEncode(data);
      final decoded = jsonDecode(encoded);
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on Object catch (error) {
      throw InvalidJsonPayloadException(
        'La charge utile ne peut pas être sérialisée en objet JSON.',
        cause: error,
      );
    }
    throw const InvalidJsonPayloadException(
      'La charge utile doit être un objet JSON.',
    );
  }

  static Map<String, Object?> _deepMerge(
    Map<String, Object?> base,
    Map<String, Object?> patch,
  ) {
    final merged = Map<String, Object?>.of(base);
    for (final entry in patch.entries) {
      final current = merged[entry.key];
      final incoming = entry.value;
      if (current is Map && incoming is Map) {
        merged[entry.key] = _deepMerge(
          Map<String, Object?>.from(current),
          Map<String, Object?>.from(incoming),
        );
      } else {
        merged[entry.key] = incoming;
      }
    }
    return merged;
  }

  static Map<String, Object?> _freezeMap(Map<String, Object?> source) =>
      Map<String, Object?>.unmodifiable(source);
}

/// Vue scopée sur une collection précise, obtenue via [SuperBackend.collection].
class CollectionApi {
  const CollectionApi._(this._backend, this.name);

  final SuperBackend _backend;

  /// Nom de la collection (`nom_collection`).
  final String name;

  /// Recherche paginée, triée et filtrée dans cette collection.
  Future<ScrudSearchResult> search({
    ScrudSearchRequest? request,
    Map<String, Object?>? parameters,
  }) => _backend.search(name, request: request, parameters: parameters);

  /// Crée une entité dans cette collection.
  Future<Map<String, Object?>> create(
    Map<String, Object?> data, {
    String? id,
    bool upsert = false,
  }) => _backend.create(name, data, id: id, upsert: upsert);

  /// Lit l'entité [id], ou lève [EntityNotFoundException].
  Future<Map<String, Object?>> read(String id) => _backend.read(name, id);

  /// Lit l'entité [id], ou retourne `null` si absente.
  Future<Map<String, Object?>?> readOrNull(String id) =>
      _backend.readOrNull(name, id);

  /// Met à jour l'entité [id] (`merge: true` pour fusion partielle).
  Future<Map<String, Object?>> update(
    String id,
    Map<String, Object?> data, {
    bool merge = false,
  }) => _backend.update(name, id, data, merge: merge);

  /// Supprime l'entité [id].
  Future<void> delete(String id, {bool ignoreMissing = false}) =>
      _backend.delete(name, id, ignoreMissing: ignoreMissing);

  /// Nombre d'entités dans cette collection.
  Future<int> count() => _backend.count(name);

  /// Supprime toutes les entités de cette collection.
  Future<int> clear() => _backend.clearCollection(name);
}
