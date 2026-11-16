/// Implémentation SQLite de [CollectionStore] via `package:sqlite3`.
///
/// Stocke chaque entité JSON dans une table locale possédant exactement les
/// colonnes `(nom_collection, id_entity, data_json)` avec une clé primaire
/// composite `(nom_collection, id_entity)` et un index sur `nom_collection`.
///
/// Les filtres, la recherche plein texte (`q`) et le tri exploitent les
/// fonctions JSON1 natives de SQLite (`json_extract`, `json_type`, `json_tree`)
/// avec validation stricte des chemins et requêtes paramétrées pour prévenir
/// toute injection SQL.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../models/scrud_exceptions.dart';
import '../models/scrud_query.dart';
import '../models/scrud_result.dart';
import 'collection_store.dart';

final _tableNamePattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]{0,63}$');

/// Store local SQLite stockant les documents JSON dans une table
/// `(nom_collection, id_entity, data_json)`.
class SqliteCollectionStore implements CollectionStore {
  /// Crée un store SQLite persistant dans le fichier [databasePath].
  SqliteCollectionStore(
    this.databasePath, {
    this.tableName = defaultTableName,
    this.enableWal = true,
  }) {
    if (databasePath.trim().isEmpty) {
      throw ArgumentError.value(
        databasePath,
        'databasePath',
        'Le chemin de la base SQLite ne peut pas être vide.',
      );
    }
    if (!_tableNamePattern.hasMatch(tableName)) {
      throw ArgumentError.value(
        tableName,
        'tableName',
        'Nom de table SQLite invalide.',
      );
    }
  }

  /// Crée un store SQLite en mémoire (`:memory:`), idéal pour les tests.
  SqliteCollectionStore.inMemory({this.tableName = defaultTableName})
    : databasePath = ':memory:',
      enableWal = false {
    if (!_tableNamePattern.hasMatch(tableName)) {
      throw ArgumentError.value(
        tableName,
        'tableName',
        'Nom de table SQLite invalide.',
      );
    }
  }

  /// Nom par défaut de la table SQLite.
  static const String defaultTableName = 'collection_entities';

  /// Chemin du fichier SQLite, ou `:memory:`.
  final String databasePath;

  /// Nom de la table contenant `(nom_collection, id_entity, data_json)`.
  final String tableName;

  /// Active le mode `PRAGMA journal_mode = WAL` pour les bases sur disque.
  final bool enableWal;

  Database? _db;
  bool _closed = false;

  Database get _database {
    final db = _db;
    if (db == null || _closed) {
      throw const BackendNotInitializedException();
    }
    return db;
  }

  @override
  Future<void> init() async {
    if (_closed) {
      throw const BackendNotInitializedException(
        'Impossible de réinitialiser un SqliteCollectionStore déjà fermé.',
      );
    }
    if (_db != null) return;

    final Database db;
    if (databasePath == ':memory:') {
      db = sqlite3.openInMemory();
    } else {
      final parent = File(databasePath).parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      db = sqlite3.open(databasePath);
    }

    try {
      if (enableWal && databasePath != ':memory:') {
        db.execute('PRAGMA journal_mode = WAL;');
      }
      db.execute('''
        CREATE TABLE IF NOT EXISTS "$tableName" (
          nom_collection TEXT NOT NULL,
          id_entity TEXT NOT NULL,
          data_json TEXT NOT NULL,
          PRIMARY KEY (nom_collection, id_entity)
        );
      ''');
      db.execute('''
        CREATE INDEX IF NOT EXISTS "idx_${tableName}_collection"
          ON "$tableName" (nom_collection);
      ''');
      _db = db;
    } on Object {
      db.close();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _db?.close();
    _db = null;
  }

  @override
  Future<void> insert(StoredJsonRow row) async {
    final db = _database;
    validateCollectionName(row.nomCollection);
    validateEntityId(row.idEntity);
    try {
      db.execute(
        'INSERT INTO "$tableName" (nom_collection, id_entity, data_json) '
        'VALUES (?, ?, ?);',
        [row.nomCollection, row.idEntity, row.dataJson],
      );
    } on SqliteException catch (error) {
      // 19 = SQLITE_CONSTRAINT (conflit de clé primaire composite).
      if (error.resultCode == 19) {
        throw EntityAlreadyExistsException(
          collection: row.nomCollection,
          entityId: row.idEntity,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> upsert(StoredJsonRow row) async {
    final db = _database;
    validateCollectionName(row.nomCollection);
    validateEntityId(row.idEntity);
    db.execute(
      'INSERT INTO "$tableName" (nom_collection, id_entity, data_json) '
      'VALUES (?, ?, ?) '
      'ON CONFLICT(nom_collection, id_entity) '
      'DO UPDATE SET data_json = excluded.data_json;',
      [row.nomCollection, row.idEntity, row.dataJson],
    );
  }

  @override
  Future<StoredJsonRow?> findById(String collection, String id) async {
    final db = _database;
    validateCollectionName(collection);
    validateEntityId(id);
    final rows = db.select(
      'SELECT nom_collection, id_entity, data_json '
      'FROM "$tableName" '
      'WHERE nom_collection = ? AND id_entity = ? '
      'LIMIT 1;',
      [collection, id],
    );
    if (rows.isEmpty) return null;
    return _rowFromResult(rows.first);
  }

  @override
  Future<bool> update(StoredJsonRow row) async {
    final db = _database;
    validateCollectionName(row.nomCollection);
    validateEntityId(row.idEntity);
    db.execute(
      'UPDATE "$tableName" '
      'SET data_json = ? '
      'WHERE nom_collection = ? AND id_entity = ?;',
      [row.dataJson, row.nomCollection, row.idEntity],
    );
    return db.updatedRows > 0;
  }

  @override
  Future<bool> delete(String collection, String id) async {
    final db = _database;
    validateCollectionName(collection);
    validateEntityId(id);
    db.execute(
      'DELETE FROM "$tableName" '
      'WHERE nom_collection = ? AND id_entity = ?;',
      [collection, id],
    );
    return db.updatedRows > 0;
  }

  @override
  Future<StoredQueryPage> query(
    String collection,
    ScrudSearchRequest request,
  ) async {
    final db = _database;
    validateCollectionName(collection);
    request.validate();

    final clauses = <String>['nom_collection = ?'];
    final params = <Object?>[collection];

    for (final filter in request.filters) {
      _appendFilterClause(filter, clauses, params);
    }

    final queryText = request.query;
    if (queryText != null) {
      clauses.add(
        'EXISTS ('
        'SELECT 1 FROM json_tree(data_json) '
        'WHERE atom IS NOT NULL '
        "AND LOWER(CASE WHEN type IN ('true', 'false') "
        'THEN type ELSE CAST(atom AS TEXT) END) '
        "LIKE ? ESCAPE '\\'"
        ')',
      );
      params.add('%${_escapeLike(queryText.toLowerCase())}%');
    }

    final whereSql = clauses.join(' AND ');
    final countResult = db.select(
      'SELECT COUNT(*) AS cnt FROM "$tableName" WHERE $whereSql;',
      params,
    );
    final total = countResult.first['cnt'] as int;

    final offset = request.pagination.effectiveOffset;
    if (total == 0 || offset >= total) {
      return StoredQueryPage(rows: const [], total: total);
    }

    final sort = request.sort;
    final orderBy = sort == null
        ? 'id_entity ASC'
        : "json_extract(data_json, '\$.${sort.field}') "
              '${sort.direction == ScrudSortDirection.asc ? 'ASC' : 'DESC'}, '
              'id_entity ASC';

    final result = db.select(
      'SELECT nom_collection, id_entity, data_json '
      'FROM "$tableName" '
      'WHERE $whereSql '
      'ORDER BY $orderBy '
      'LIMIT ? OFFSET ?;',
      [...params, request.pagination.pageSize, offset],
    );

    return StoredQueryPage(
      rows: [for (final row in result) _rowFromResult(row)],
      total: total,
    );
  }

  @override
  Future<int> count(String collection) async {
    final db = _database;
    validateCollectionName(collection);
    final result = db.select(
      'SELECT COUNT(*) AS cnt FROM "$tableName" WHERE nom_collection = ?;',
      [collection],
    );
    return result.first['cnt'] as int;
  }

  @override
  Future<List<String>> listCollections() async {
    final db = _database;
    final result = db.select(
      'SELECT DISTINCT nom_collection FROM "$tableName" '
      'ORDER BY nom_collection ASC;',
    );
    return [for (final row in result) row['nom_collection'] as String];
  }

  @override
  Future<int> clearCollection(String collection) async {
    final db = _database;
    validateCollectionName(collection);
    db.execute('DELETE FROM "$tableName" WHERE nom_collection = ?;', [
      collection,
    ]);
    return db.updatedRows;
  }

  static StoredJsonRow _rowFromResult(Row row) => StoredJsonRow(
    nomCollection: row['nom_collection'] as String,
    idEntity: row['id_entity'] as String,
    dataJson: row['data_json'] as String,
  );
}

void _appendFilterClause(
  ScrudFilter filter,
  List<String> clauses,
  List<Object?> params,
) {
  final path = '\$.${filter.field}';
  final extract = "json_extract(data_json, '$path')";
  final jsonType = "json_type(data_json, '$path')";
  final value = filter.value;

  switch (filter.operator) {
    case ScrudFilterOperator.equals:
      if (value == null) {
        clauses.add('$extract IS NULL');
      } else if (value is bool) {
        clauses.add('$jsonType = ?');
        params.add(value ? 'true' : 'false');
      } else if (value is num) {
        clauses.add("$jsonType IN ('integer', 'real') AND $extract = ?");
        params.add(value);
      } else {
        clauses.add("$jsonType = 'text' AND $extract = ?");
        params.add(value.toString());
      }
    case ScrudFilterOperator.notEquals:
      if (value == null) {
        clauses.add('$extract IS NOT NULL');
      } else if (value is bool) {
        clauses.add('$extract IS NOT NULL AND $jsonType != ?');
        params.add(value ? 'true' : 'false');
      } else if (value is num) {
        clauses.add(
          "$extract IS NOT NULL AND ($jsonType NOT IN ('integer', 'real') OR $extract != ?)",
        );
        params.add(value);
      } else {
        clauses.add(
          "$extract IS NOT NULL AND ($jsonType != 'text' OR $extract != ?)",
        );
        params.add(value.toString());
      }
    case ScrudFilterOperator.contains:
      final needle = _escapeLike((value as String).toLowerCase());
      clauses.add("$jsonType = 'text' AND LOWER($extract) LIKE ? ESCAPE '\\'");
      params.add('%$needle%');
    case ScrudFilterOperator.startsWith:
      final prefix = _escapeLike((value as String).toLowerCase());
      clauses.add("$jsonType = 'text' AND LOWER($extract) LIKE ? ESCAPE '\\'");
      params.add('$prefix%');
    case ScrudFilterOperator.greaterThan:
      _appendRangeClause(extract, jsonType, '>', value, clauses, params);
    case ScrudFilterOperator.greaterThanOrEqual:
      _appendRangeClause(extract, jsonType, '>=', value, clauses, params);
    case ScrudFilterOperator.lessThan:
      _appendRangeClause(extract, jsonType, '<', value, clauses, params);
    case ScrudFilterOperator.lessThanOrEqual:
      _appendRangeClause(extract, jsonType, '<=', value, clauses, params);
    case ScrudFilterOperator.inList:
      final items = value as List<Object?>;
      if (items.isEmpty) {
        clauses.add('1 = 0');
        return;
      }
      final subClauses = <String>[];
      for (final item in items) {
        if (item == null) {
          subClauses.add('$extract IS NULL');
        } else if (item is bool) {
          subClauses.add('$jsonType = ?');
          params.add(item ? 'true' : 'false');
        } else if (item is num) {
          subClauses.add("($jsonType IN ('integer', 'real') AND $extract = ?)");
          params.add(item);
        } else {
          subClauses.add("($jsonType = 'text' AND $extract = ?)");
          params.add(item.toString());
        }
      }
      clauses.add('(${subClauses.join(' OR ')})');
    case ScrudFilterOperator.isNull:
      clauses.add('$extract IS NULL');
    case ScrudFilterOperator.isNotNull:
      clauses.add('$extract IS NOT NULL');
  }
}

void _appendRangeClause(
  String extract,
  String jsonType,
  String op,
  Object? value,
  List<String> clauses,
  List<Object?> params,
) {
  if (value is num) {
    clauses.add("$jsonType IN ('integer', 'real') AND $extract $op ?");
    params.add(value);
  } else {
    clauses.add("$jsonType = 'text' AND $extract $op ?");
    params.add(value.toString());
  }
}

String _escapeLike(String input) => input
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
