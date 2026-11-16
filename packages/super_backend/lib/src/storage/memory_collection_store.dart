/// Implémentation en mémoire de [CollectionStore] pour les tests et usages
/// éphémères.
///
/// Reproduit fidèlement la sémantique de stockage `(nom_collection, id_entity,
/// data_json)` ainsi que les filtres, la recherche texte, le tri et la
/// pagination de `SqliteCollectionStore`.
library;

import '../models/scrud_exceptions.dart';
import '../models/scrud_query.dart';
import '../models/scrud_result.dart';
import 'collection_store.dart';

/// Stockage en mémoire organisé par `(nom_collection, id_entity, data_json)`.
class MemoryCollectionStore implements CollectionStore {
  /// Crée un store en mémoire vide.
  MemoryCollectionStore();

  final Map<String, Map<String, StoredJsonRow>> _collections = {};
  bool _initialized = false;
  bool _closed = false;

  void _requireReady() {
    if (!_initialized || _closed) {
      throw const BackendNotInitializedException();
    }
  }

  @override
  Future<void> init() async {
    if (_closed) {
      throw const BackendNotInitializedException(
        'Impossible de réinitialiser un MemoryCollectionStore déjà fermé.',
      );
    }
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _closed = true;
    _collections.clear();
  }

  @override
  Future<void> insert(StoredJsonRow row) async {
    _requireReady();
    validateCollectionName(row.nomCollection);
    validateEntityId(row.idEntity);
    final bucket = _collections.putIfAbsent(row.nomCollection, () => {});
    if (bucket.containsKey(row.idEntity)) {
      throw EntityAlreadyExistsException(
        collection: row.nomCollection,
        entityId: row.idEntity,
      );
    }
    bucket[row.idEntity] = row;
  }

  @override
  Future<void> upsert(StoredJsonRow row) async {
    _requireReady();
    validateCollectionName(row.nomCollection);
    validateEntityId(row.idEntity);
    final bucket = _collections.putIfAbsent(row.nomCollection, () => {});
    bucket[row.idEntity] = row;
  }

  @override
  Future<StoredJsonRow?> findById(String collection, String id) async {
    _requireReady();
    validateCollectionName(collection);
    validateEntityId(id);
    return _collections[collection]?[id];
  }

  @override
  Future<bool> update(StoredJsonRow row) async {
    _requireReady();
    validateCollectionName(row.nomCollection);
    validateEntityId(row.idEntity);
    final bucket = _collections[row.nomCollection];
    if (bucket == null || !bucket.containsKey(row.idEntity)) {
      return false;
    }
    bucket[row.idEntity] = row;
    return true;
  }

  @override
  Future<bool> delete(String collection, String id) async {
    _requireReady();
    validateCollectionName(collection);
    validateEntityId(id);
    final bucket = _collections[collection];
    if (bucket == null) return false;
    final removed = bucket.remove(id) != null;
    if (bucket.isEmpty) {
      _collections.remove(collection);
    }
    return removed;
  }

  @override
  Future<StoredQueryPage> query(
    String collection,
    ScrudSearchRequest request,
  ) async {
    _requireReady();
    validateCollectionName(collection);
    request.validate();

    final bucket = _collections[collection];
    if (bucket == null || bucket.isEmpty) {
      return const StoredQueryPage(rows: [], total: 0);
    }

    final matched = <({StoredJsonRow row, Map<String, Object?> data})>[];
    for (final row in bucket.values) {
      final data = row.decodeData();
      if (_matchesRequest(data, request)) {
        matched.add((row: row, data: data));
      }
    }

    final sort = request.sort;
    matched.sort((a, b) {
      if (sort != null) {
        final cmp = _compareJsonValues(
          _extractPath(a.data, sort.field),
          _extractPath(b.data, sort.field),
        );
        if (cmp != 0) {
          return sort.direction == ScrudSortDirection.asc ? cmp : -cmp;
        }
      }
      return a.row.idEntity.compareTo(b.row.idEntity);
    });

    final total = matched.length;
    final offset = request.pagination.effectiveOffset;
    if (offset >= total) {
      return StoredQueryPage(rows: const [], total: total);
    }
    final end = (offset + request.pagination.pageSize).clamp(0, total);
    return StoredQueryPage(
      rows: [for (var i = offset; i < end; i++) matched[i].row],
      total: total,
    );
  }

  @override
  Future<int> count(String collection) async {
    _requireReady();
    validateCollectionName(collection);
    return _collections[collection]?.length ?? 0;
  }

  @override
  Future<List<String>> listCollections() async {
    _requireReady();
    final names = _collections.keys.toList()..sort();
    return names;
  }

  @override
  Future<int> clearCollection(String collection) async {
    _requireReady();
    validateCollectionName(collection);
    final removed = _collections.remove(collection);
    return removed?.length ?? 0;
  }
}

bool _matchesRequest(Map<String, Object?> data, ScrudSearchRequest request) {
  for (final filter in request.filters) {
    final actual = _extractPath(data, filter.field);
    if (!_matchesFilter(actual, filter)) return false;
  }
  final query = request.query;
  if (query != null) {
    final needle = query.toLowerCase();
    if (!_containsScalarMatch(data, needle)) return false;
  }
  return true;
}

bool _matchesFilter(Object? actual, ScrudFilter filter) {
  final expected = filter.value;
  switch (filter.operator) {
    case ScrudFilterOperator.equals:
      return _scalarEquals(actual, expected);
    case ScrudFilterOperator.notEquals:
      return actual != null && !_scalarEquals(actual, expected);
    case ScrudFilterOperator.contains:
      return actual is String &&
          expected is String &&
          actual.toLowerCase().contains(expected.toLowerCase());
    case ScrudFilterOperator.startsWith:
      return actual is String &&
          expected is String &&
          actual.toLowerCase().startsWith(expected.toLowerCase());
    case ScrudFilterOperator.greaterThan:
      final cmp = _compareNonNull(actual, expected);
      return cmp != null && cmp > 0;
    case ScrudFilterOperator.greaterThanOrEqual:
      final cmp = _compareNonNull(actual, expected);
      return cmp != null && cmp >= 0;
    case ScrudFilterOperator.lessThan:
      final cmp = _compareNonNull(actual, expected);
      return cmp != null && cmp < 0;
    case ScrudFilterOperator.lessThanOrEqual:
      final cmp = _compareNonNull(actual, expected);
      return cmp != null && cmp <= 0;
    case ScrudFilterOperator.inList:
      if (expected is! List) return false;
      return expected.any((item) => _scalarEquals(actual, item));
    case ScrudFilterOperator.isNull:
      return actual == null;
    case ScrudFilterOperator.isNotNull:
      return actual != null;
  }
}

bool _scalarEquals(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  return a == b;
}

int? _compareNonNull(Object? a, Object? b) {
  if (a == null || b == null) return null;
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  return null;
}

int _compareJsonValues(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
  if (a is String && b is String) return a.compareTo(b);
  return a.toString().compareTo(b.toString());
}

Object? _extractPath(Map<String, Object?> root, String path) {
  Object? current = root;
  for (final segment in path.split('.')) {
    if (current is Map && current.containsKey(segment)) {
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
}

bool _containsScalarMatch(Object? node, String needle) {
  switch (node) {
    case null:
      return false;
    case String text:
      return text.toLowerCase().contains(needle);
    case num number:
      return number.toString().toLowerCase().contains(needle);
    case bool flag:
      return flag.toString().toLowerCase().contains(needle);
    case Map<Object?, Object?> map:
      return map.values.any((value) => _containsScalarMatch(value, needle));
    case List<Object?> list:
      return list.any((value) => _containsScalarMatch(value, needle));
    default:
      return false;
  }
}
