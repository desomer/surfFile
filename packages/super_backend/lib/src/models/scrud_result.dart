/// Modèles immuables de résultats SCRUD et représentation des lignes stockées.
///
/// [StoredJsonRow] reflète fidèlement la structure de la table locale
/// `(nom_collection, id_entity, data_json)`.
/// [ScrudSearchResult] fournit une enveloppe JSON normalisée (`items`,
/// `total`, `nextCursor`, `page`, `pageSize`, `offset`, `hasNext`,
/// `hasPrevious`) directement compatible avec `DatasourceConfig` de
/// `super_container_layout`.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import 'scrud_exceptions.dart';
import 'scrud_query.dart';

/// Opération SCRUD générique prise en charge par `SuperBackend`.
enum ScrudOperation {
  /// Recherche paginée, triée et filtrée d'une collection.
  search,

  /// Création d'une entité dans une collection.
  create,

  /// Lecture d'une entité par identifiant.
  read,

  /// Mise à jour (complète ou partielle) d'une entité.
  update,

  /// Suppression d'une entité par identifiant.
  delete,
}

/// Ligne brute issue de la table `(nom_collection, id_entity, data_json)`.
@immutable
class StoredJsonRow {
  /// Crée une ligne stockée.
  const StoredJsonRow({
    required this.nomCollection,
    required this.idEntity,
    required this.dataJson,
  });

  /// Nom de la collection (`nom_collection`).
  final String nomCollection;

  /// Identifiant unique de l'entité dans la collection (`id_entity`).
  final String idEntity;

  /// Document JSON brut sérialisé (`data_json`).
  final String dataJson;

  /// Décode [dataJson] en objet JSON (`Map<String, Object?>`).
  Map<String, Object?> decodeData() {
    final Object? decoded;
    try {
      decoded = jsonDecode(dataJson);
    } on FormatException catch (error) {
      throw InvalidJsonPayloadException(
        'Document JSON stocké corrompu pour ($nomCollection, $idEntity).',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
      throw InvalidJsonPayloadException(
        'Le document stocké pour ($nomCollection, $idEntity) doit être un '
        'objet JSON.',
      );
    }
    return decoded;
  }

  /// Convertit cette ligne brute en enregistrement [ScrudEntityRecord].
  ScrudEntityRecord toRecord() => ScrudEntityRecord(
    collection: nomCollection,
    id: idEntity,
    data: decodeData(),
  );

  @override
  bool operator ==(Object other) =>
      other is StoredJsonRow &&
      nomCollection == other.nomCollection &&
      idEntity == other.idEntity &&
      dataJson == other.dataJson;

  @override
  int get hashCode => Object.hash(nomCollection, idEntity, dataJson);
}

/// Entité JSON décodée accompagnée de sa collection et de son identifiant.
@immutable
class ScrudEntityRecord {
  /// Crée un enregistrement décodé.
  ScrudEntityRecord({
    required this.collection,
    required this.id,
    required Map<String, Object?> data,
  }) : data = Map<String, Object?>.unmodifiable(data);

  /// Nom de la collection.
  final String collection;

  /// Identifiant de l'entité (`id_entity`).
  final String id;

  /// Données JSON de l'entité.
  final Map<String, Object?> data;

  /// Représentation JSON complète incluant les métadonnées de stockage.
  Map<String, Object?> toJson() => {
    'collection': collection,
    'id': id,
    'data': data,
  };

  @override
  bool operator ==(Object other) =>
      other is ScrudEntityRecord &&
      collection == other.collection &&
      id == other.id &&
      _jsonEquals(data, other.data);

  @override
  int get hashCode => Object.hash(collection, id, _jsonHash(data));
}

/// Page retournée par une opération `search`.
///
/// La forme [toJson] expose `items`, `total`, `nextCursor`, `page`,
/// `pageSize`, `offset`, `hasNext` et `hasPrevious`, prête pour
/// `DatasourceConfig` (`responsePath: "items"`, `totalPath: "total"`,
/// `nextCursorPath: "nextCursor"`).
@immutable
class ScrudSearchResult {
  /// Crée un résultat de recherche paginée.
  ScrudSearchResult({
    required List<Map<String, Object?>> items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.offset,
    required this.hasNext,
    required this.hasPrevious,
    this.nextCursor,
    this.sort,
  }) : items = List<Map<String, Object?>>.unmodifiable(
         items.map((item) => Map<String, Object?>.unmodifiable(item)),
       );

  /// Entités de la page courante.
  final List<Map<String, Object?>> items;

  /// Nombre total d'entités correspondant aux filtres.
  final int total;

  /// Numéro de page courant (à partir de `1`).
  final int page;

  /// Taille de page appliquée.
  final int pageSize;

  /// Position de départ dans le jeu de résultats (`0`-based).
  final int offset;

  /// Vrai s'il existe au moins une page suivante.
  final bool hasNext;

  /// Vrai s'il existe une page précédente.
  final bool hasPrevious;

  /// Curseur opaque de la page suivante, ou `null` sur la dernière page.
  final String? nextCursor;

  /// Tri appliqué lors de la requête, ou `null`.
  final ScrudSortOrder? sort;

  /// Nombre total de pages.
  int get pageCount => pageSize <= 0 ? 1 : (total / pageSize).ceil();

  /// Enveloppe JSON compatible `DatasourceConfig` / `HttpDataProvider`.
  Map<String, Object?> toJson() => {
    'items': items,
    'total': total,
    'page': page,
    'pageSize': pageSize,
    'pageCount': pageCount,
    'offset': offset,
    'hasNext': hasNext,
    'hasPrevious': hasPrevious,
    'nextCursor': nextCursor,
    if (sort != null) 'sort': sort!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ScrudSearchResult &&
      total == other.total &&
      page == other.page &&
      pageSize == other.pageSize &&
      offset == other.offset &&
      hasNext == other.hasNext &&
      hasPrevious == other.hasPrevious &&
      nextCursor == other.nextCursor &&
      sort == other.sort &&
      _jsonEquals(items, other.items);

  @override
  int get hashCode => Object.hash(
    total,
    page,
    pageSize,
    offset,
    hasNext,
    hasPrevious,
    nextCursor,
    sort,
    _jsonHash(items),
  );
}

bool _jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) ||
          !_jsonEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _jsonHash(Object? value) => switch (value) {
  Map<Object?, Object?> map => Object.hashAllUnordered([
    for (final entry in map.entries)
      Object.hash(entry.key, _jsonHash(entry.value)),
  ]),
  List<Object?> list => Object.hashAll(list.map(_jsonHash)),
  _ => value.hashCode,
};
