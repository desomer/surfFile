/// Modèles immuables de requête pour l'opération Search du moteur SCRUD.
///
/// Définit la pagination ([ScrudPagination], modes `page`, `offset` et
/// `cursor`), le tri ([ScrudSortOrder]), les filtres ([ScrudFilter]) et la
/// requête complète ([ScrudSearchRequest]).
///
/// [ScrudSearchRequest.fromParameters] permet de convertir directement une
/// carte de paramètres plats telle qu'émise par `DatasourceConfig` /
/// `HttpDataProvider` (`page`, `size`, `offset`, `limit`, `cursor`, `sort`,
/// `direction`, `-champ`, `q`, et filtres de champs).
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import 'scrud_exceptions.dart';

final _collectionPattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');
final _entityIdControlPattern = RegExp(r'[\x00-\x1f\x7f]');
final _jsonFieldPathPattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
);

/// Valide un nom de collection et lève [InvalidCollectionException] sinon.
void validateCollectionName(String collection) {
  if (!_collectionPattern.hasMatch(collection)) {
    throw InvalidCollectionException(collection);
  }
}

/// Valide un identifiant d'entité et lève [InvalidEntityIdException] sinon.
void validateEntityId(String id) {
  if (id.isEmpty || id.length > 256 || _entityIdControlPattern.hasMatch(id)) {
    throw InvalidEntityIdException(id);
  }
}

/// Valide un chemin de champ JSON (`champ` ou `parent.enfant`) utilisable
/// dans un tri ou un filtre SQL `json_extract` sans risque d'injection.
void validateJsonFieldPath(String field) {
  if (!_jsonFieldPathPattern.hasMatch(field) || field.length > 128) {
    throw InvalidQueryException(
      'Chemin de champ JSON invalide « $field » : segments alphanumériques '
      'séparés par « . » attendus.',
    );
  }
}

/// Mode de pagination d'une recherche SCRUD.
enum ScrudPaginationMode {
  /// Numéro de page et taille de page (`page` / `size`).
  page,

  /// Position de départ et limite (`offset` / `limit`).
  offset,

  /// Curseur opaque retourné par la page précédente (`cursor` / `limit`).
  cursor,
}

/// Configuration de pagination pour [ScrudSearchRequest].
@immutable
class ScrudPagination {
  /// Crée une pagination.
  const ScrudPagination({
    this.mode = ScrudPaginationMode.page,
    this.pageSize = defaultPageSize,
    this.page = 1,
    this.firstPage = 1,
    this.offset = 0,
    this.cursor,
  });

  /// Lecture depuis JSON.
  factory ScrudPagination.fromJson(Object? json) {
    if (json is! Map) {
      throw const InvalidQueryException('Pagination invalide : objet attendu.');
    }
    final modeName = json['mode'] ?? ScrudPaginationMode.page.name;
    final mode = ScrudPaginationMode.values
        .where((value) => value.name == modeName)
        .firstOrNull;
    if (mode == null) {
      throw const InvalidQueryException(
        'Pagination : mode « page », « offset » ou « cursor » attendu.',
      );
    }
    final pageSize = _asInt(json['pageSize'], 'pageSize') ?? defaultPageSize;
    final page = _asInt(json['page'], 'page') ?? 1;
    final firstPage = _asInt(json['firstPage'], 'firstPage') ?? 1;
    final offset = _asInt(json['offset'], 'offset') ?? 0;
    final rawCursor = json['cursor'];
    if (rawCursor != null && rawCursor is! String) {
      throw const InvalidQueryException(
        'Pagination : « cursor » doit être une chaîne.',
      );
    }
    final result = ScrudPagination(
      mode: mode,
      pageSize: pageSize,
      page: page,
      firstPage: firstPage,
      offset: offset,
      cursor: rawCursor as String?,
    );
    result.validate();
    return result;
  }

  /// Taille de page par défaut.
  static const int defaultPageSize = 20;

  /// Taille de page maximale autorisée.
  static const int maxPageSize = 1000;

  /// Mode de pagination actif.
  final ScrudPaginationMode mode;

  /// Nombre maximal d'entités retournées par page.
  final int pageSize;

  /// Numéro de page demandé (en mode [ScrudPaginationMode.page]).
  final int page;

  /// Indice de la première page en mode `page` (`0` ou `1`).
  final int firstPage;

  /// Décalage demandé (en mode [ScrudPaginationMode.offset]).
  final int offset;

  /// Curseur opaque (en mode [ScrudPaginationMode.cursor]).
  final String? cursor;

  /// Position de départ normalisée à partir de `0` pour `page` et `offset`.
  int get effectiveOffset => switch (mode) {
    ScrudPaginationMode.page => (page - firstPage) * pageSize,
    ScrudPaginationMode.offset => offset,
    ScrudPaginationMode.cursor => decodeCursorOffset(cursor),
  };

  /// Numéro de page logique (toujours à partir de `1`) calculé depuis
  /// [effectiveOffset].
  int get normalizedPageNumber =>
      pageSize <= 0 ? 1 : (effectiveOffset ~/ pageSize) + 1;

  /// Encode un décalage en curseur opaque URL-safe.
  static String encodeCursorOffset(int offset) {
    final payload = jsonEncode({'o': offset});
    return base64Url.encode(utf8.encode(payload));
  }

  /// Décode un curseur produit par [encodeCursorOffset] ; lève
  /// [InvalidQueryException] si le curseur est corrompu.
  static int decodeCursorOffset(String? cursor) {
    if (cursor == null || cursor.trim().isEmpty) return 0;
    try {
      final decoded = utf8.decode(base64Url.decode(cursor.trim()));
      final json = jsonDecode(decoded);
      if (json is Map && json['o'] is int && (json['o'] as int) >= 0) {
        return json['o'] as int;
      }
    } on Object catch (error) {
      throw InvalidQueryException(
        'Curseur de pagination invalide.',
        cause: error,
      );
    }
    throw const InvalidQueryException('Curseur de pagination invalide.');
  }

  /// Valide les bornes et cohérence des paramètres ; lève
  /// [InvalidQueryException] sinon.
  void validate() {
    if (pageSize < 1 || pageSize > maxPageSize) {
      throw const InvalidQueryException(
        'La taille de page doit être comprise entre 1 et $maxPageSize.',
      );
    }
    if (firstPage != 0 && firstPage != 1) {
      throw const InvalidQueryException('firstPage doit valoir 0 ou 1.');
    }
    if (mode == ScrudPaginationMode.page && page < firstPage) {
      throw InvalidQueryException(
        'Le numéro de page ($page) doit être >= $firstPage.',
      );
    }
    if (mode == ScrudPaginationMode.offset && offset < 0) {
      throw const InvalidQueryException('L’offset doit être positif ou nul.');
    }
    if (mode == ScrudPaginationMode.cursor && cursor != null) {
      decodeCursorOffset(cursor);
    }
  }

  /// Copie modifiée.
  ScrudPagination copyWith({
    ScrudPaginationMode? mode,
    int? pageSize,
    int? page,
    int? firstPage,
    int? offset,
    String? cursor,
    bool clearCursor = false,
  }) => ScrudPagination(
    mode: mode ?? this.mode,
    pageSize: pageSize ?? this.pageSize,
    page: page ?? this.page,
    firstPage: firstPage ?? this.firstPage,
    offset: offset ?? this.offset,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
  );

  /// Sérialisation JSON complète.
  Map<String, Object?> toJson() {
    validate();
    return {
      'mode': mode.name,
      'pageSize': pageSize,
      if (mode == ScrudPaginationMode.page) ...{
        'page': page,
        'firstPage': firstPage,
      },
      if (mode == ScrudPaginationMode.offset) 'offset': offset,
      if (mode == ScrudPaginationMode.cursor && cursor != null)
        'cursor': cursor,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ScrudPagination &&
      mode == other.mode &&
      pageSize == other.pageSize &&
      page == other.page &&
      firstPage == other.firstPage &&
      offset == other.offset &&
      cursor == other.cursor;

  @override
  int get hashCode =>
      Object.hash(mode, pageSize, page, firstPage, offset, cursor);
}

/// Sens de tri.
enum ScrudSortDirection {
  /// Ordre croissant.
  asc,

  /// Ordre décroissant.
  desc;

  /// Sens opposé.
  ScrudSortDirection get reversed => this == asc ? desc : asc;

  /// Retourne le sens correspondant à [name], ou `null`.
  static ScrudSortDirection? byName(Object? name) => switch (name) {
    'asc' => ScrudSortDirection.asc,
    'desc' => ScrudSortDirection.desc,
    _ => null,
  };
}

/// Spécification d'un tri sur un attribut JSON (ou `id` d'entité).
@immutable
class ScrudSortOrder {
  /// Crée un tri sur [field].
  const ScrudSortOrder(this.field, [this.direction = ScrudSortDirection.asc]);

  /// Lecture depuis JSON (`{"field": "name", "direction": "asc"}`).
  factory ScrudSortOrder.fromJson(Object? json) {
    if (json is! Map) {
      throw const InvalidQueryException('Tri invalide : objet attendu.');
    }
    final field = json['field'];
    final direction = json.containsKey('direction')
        ? ScrudSortDirection.byName(json['direction'])
        : ScrudSortDirection.asc;
    if (field is! String || direction == null) {
      throw const InvalidQueryException(
        'Tri invalide : champ texte et sens « asc » ou « desc » attendus.',
      );
    }
    final result = ScrudSortOrder(field, direction);
    result.validate();
    return result;
  }

  /// Nom du champ JSON (ex. `name` ou `address.city`).
  final String field;

  /// Sens du tri.
  final ScrudSortDirection direction;

  /// Vérifie que [field] est un chemin JSON sûr.
  void validate() => validateJsonFieldPath(field);

  /// Copie modifiée.
  ScrudSortOrder copyWith({String? field, ScrudSortDirection? direction}) =>
      ScrudSortOrder(field ?? this.field, direction ?? this.direction);

  /// Sérialisation JSON.
  Map<String, Object?> toJson() {
    validate();
    return {'field': field, 'direction': direction.name};
  }

  @override
  bool operator ==(Object other) =>
      other is ScrudSortOrder &&
      field == other.field &&
      direction == other.direction;

  @override
  int get hashCode => Object.hash(field, direction);
}

/// Opérateur d'un filtre [ScrudFilter] sur un champ JSON.
enum ScrudFilterOperator {
  /// Égalité stricte (`=`).
  equals,

  /// Différence (`!=`).
  notEquals,

  /// Sous-chaîne insensible à la casse (`LIKE %v%`).
  contains,

  /// Préfixe insensible à la casse (`LIKE v%`).
  startsWith,

  /// Supérieur strictement (`>`).
  greaterThan,

  /// Supérieur ou égal (`>=`).
  greaterThanOrEqual,

  /// Inférieur strictement (`<`).
  lessThan,

  /// Inférieur ou égal (`<=`).
  lessThanOrEqual,

  /// Appartenance à une liste (`IN (...)`).
  inList,

  /// Valeur nulle ou absente (`IS NULL`).
  isNull,

  /// Valeur non nulle (`IS NOT NULL`).
  isNotNull,
}

/// Condition de filtrage sur un attribut JSON d'une entité.
@immutable
class ScrudFilter {
  /// Crée un filtre sur [field].
  const ScrudFilter({
    required this.field,
    this.operator = ScrudFilterOperator.equals,
    this.value,
  });

  /// Lecture depuis JSON.
  factory ScrudFilter.fromJson(Object? json) {
    if (json is! Map) {
      throw const InvalidQueryException('Filtre invalide : objet attendu.');
    }
    final field = json['field'];
    final opName = json['operator'] ?? ScrudFilterOperator.equals.name;
    final op = ScrudFilterOperator.values
        .where((value) => value.name == opName)
        .firstOrNull;
    if (field is! String || op == null) {
      throw const InvalidQueryException(
        'Filtre invalide : « field » et « operator » valides attendus.',
      );
    }
    final result = ScrudFilter(
      field: field,
      operator: op,
      value: json['value'],
    );
    result.validate();
    return result;
  }

  /// Chemin du champ JSON filtré.
  final String field;

  /// Opérateur appliqué.
  final ScrudFilterOperator operator;

  /// Valeur comparée (ou `List<Object?>` pour [ScrudFilterOperator.inList]).
  final Object? value;

  /// Vérifie la validité du chemin et de la valeur selon l'opérateur.
  void validate() {
    validateJsonFieldPath(field);
    switch (operator) {
      case ScrudFilterOperator.isNull:
      case ScrudFilterOperator.isNotNull:
        break;
      case ScrudFilterOperator.inList:
        if (value is! List) {
          throw InvalidQueryException(
            'Le filtre « $field » (inList) attend une liste de valeurs.',
          );
        }
      case ScrudFilterOperator.contains:
      case ScrudFilterOperator.startsWith:
        if (value is! String) {
          throw InvalidQueryException(
            'Le filtre « $field » (${operator.name}) attend une chaîne.',
          );
        }
      case ScrudFilterOperator.greaterThan:
      case ScrudFilterOperator.greaterThanOrEqual:
      case ScrudFilterOperator.lessThan:
      case ScrudFilterOperator.lessThanOrEqual:
        if (value is! num && value is! String) {
          throw InvalidQueryException(
            'Le filtre « $field » (${operator.name}) attend un nombre ou un '
            'texte.',
          );
        }
      case ScrudFilterOperator.equals:
      case ScrudFilterOperator.notEquals:
        if (value is Map || value is List) {
          throw InvalidQueryException(
            'Le filtre « $field » attend une valeur scalaire ou null.',
          );
        }
    }
  }

  /// Sérialisation JSON.
  Map<String, Object?> toJson() {
    validate();
    return {
      'field': field,
      'operator': operator.name,
      if (operator != ScrudFilterOperator.isNull &&
          operator != ScrudFilterOperator.isNotNull)
        'value': value,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ScrudFilter &&
      field == other.field &&
      operator == other.operator &&
      _valueEquals(value, other.value);

  @override
  int get hashCode => Object.hash(field, operator, _valueHash(value));
}

/// Requête complète pour l'opération `search` d'une collection.
@immutable
class ScrudSearchRequest {
  /// Crée une requête de recherche.
  ScrudSearchRequest({
    this.pagination = const ScrudPagination(),
    this.sort,
    List<ScrudFilter> filters = const [],
    this.query,
  }) : filters = List<ScrudFilter>.unmodifiable(filters);

  /// Construit une requête depuis une carte de paramètres plats compatible
  /// avec `DatasourceConfig` / `HttpDataProvider` (`page`, `size`, `offset`,
  /// `limit`, `cursor`, `sort`, `direction`, `-champ`, `q`, et filtres).
  ///
  /// Les clés restantes (non vides) deviennent des [ScrudFilter] ; le suffixe
  /// `champ__op` permet de préciser un opérateur (`eq`, `ne`, `contains`,
  /// `startsWith`, `gt`, `gte`, `lt`, `lte`, `in`, `isNull`, `isNotNull`).
  factory ScrudSearchRequest.fromParameters(
    Map<String, Object?> parameters, {
    String pageParam = 'page',
    String sizeParam = 'size',
    int firstPage = 1,
    String offsetParam = 'offset',
    String limitParam = 'limit',
    String cursorParam = 'cursor',
    String sortParam = 'sort',
    String directionParam = 'direction',
    String queryParam = 'q',
    ScrudPaginationMode? mode,
    int defaultPageSize = ScrudPagination.defaultPageSize,
    Set<String> ignoredParameters = const {},
  }) {
    final consumed = <String>{
      pageParam,
      sizeParam,
      offsetParam,
      limitParam,
      cursorParam,
      sortParam,
      directionParam,
      queryParam,
      ...ignoredParameters,
    };

    final inferredMode =
        mode ??
        (parameters.containsKey(cursorParam)
            ? ScrudPaginationMode.cursor
            : parameters.containsKey(offsetParam)
            ? ScrudPaginationMode.offset
            : ScrudPaginationMode.page);

    final rawSize = switch (inferredMode) {
      ScrudPaginationMode.page =>
        parameters[sizeParam] ?? parameters[limitParam],
      ScrudPaginationMode.offset || ScrudPaginationMode.cursor =>
        parameters[limitParam] ?? parameters[sizeParam],
    };
    final pageSize = _asInt(rawSize, sizeParam) ?? defaultPageSize;
    final page = _asInt(parameters[pageParam], pageParam) ?? firstPage;
    final offset = _asInt(parameters[offsetParam], offsetParam) ?? 0;
    final rawCursor = parameters[cursorParam];
    final cursor = rawCursor?.toString();

    final pagination = ScrudPagination(
      mode: inferredMode,
      pageSize: pageSize,
      page: page,
      firstPage: firstPage,
      offset: offset,
      cursor: cursor != null && cursor.trim().isEmpty ? null : cursor,
    );

    ScrudSortOrder? sort;
    final rawSort = parameters[sortParam];
    if (rawSort is String && rawSort.trim().isNotEmpty) {
      var field = rawSort.trim();
      var direction = ScrudSortDirection.asc;
      if (field.startsWith('-')) {
        field = field.substring(1);
        direction = ScrudSortDirection.desc;
      } else if (parameters[directionParam] != null) {
        final parsedDir = ScrudSortDirection.byName(
          parameters[directionParam].toString().trim().toLowerCase(),
        );
        if (parsedDir == null) {
          throw InvalidQueryException(
            'Sens de tri invalide « ${parameters[directionParam]} » : '
            '« asc » ou « desc » attendu.',
          );
        }
        direction = parsedDir;
      }
      sort = ScrudSortOrder(field, direction);
    }

    final rawQuery = parameters[queryParam];
    final query = rawQuery is String && rawQuery.trim().isNotEmpty
        ? rawQuery.trim()
        : null;

    final filters = <ScrudFilter>[];
    for (final entry in parameters.entries) {
      if (consumed.contains(entry.key)) continue;
      final value = entry.value;
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      filters.add(_parseFilterEntry(entry.key, value));
    }

    final request = ScrudSearchRequest(
      pagination: pagination,
      sort: sort,
      filters: filters,
      query: query,
    );
    request.validate();
    return request;
  }

  /// Lecture depuis JSON.
  factory ScrudSearchRequest.fromJson(Object? json) {
    if (json is! Map) {
      throw const InvalidQueryException('Requête invalide : objet attendu.');
    }
    final rawPagination = json['pagination'];
    final rawSort = json['sort'];
    final rawFilters = json['filters'];
    final rawQuery = json['query'];
    if (rawQuery != null && rawQuery is! String) {
      throw const InvalidQueryException(
        'Requête invalide : « query » doit être une chaîne.',
      );
    }
    if (rawFilters != null && rawFilters is! List) {
      throw const InvalidQueryException(
        'Requête invalide : « filters » doit être une liste.',
      );
    }
    final request = ScrudSearchRequest(
      pagination: rawPagination == null
          ? const ScrudPagination()
          : ScrudPagination.fromJson(rawPagination),
      sort: rawSort == null ? null : ScrudSortOrder.fromJson(rawSort),
      filters: [
        if (rawFilters is List)
          for (final item in rawFilters) ScrudFilter.fromJson(item),
      ],
      query: (rawQuery as String?)?.trim().isEmpty == true
          ? null
          : rawQuery?.trim(),
    );
    request.validate();
    return request;
  }

  /// Pagination demandée.
  final ScrudPagination pagination;

  /// Tri optionnel.
  final ScrudSortOrder? sort;

  /// Filtres appliqués (combinés par `AND`).
  final List<ScrudFilter> filters;

  /// Terme de recherche texte libre (`q`) sur le document JSON.
  final String? query;

  /// Valide la pagination, le tri et tous les filtres.
  void validate() {
    pagination.validate();
    sort?.validate();
    for (final filter in filters) {
      filter.validate();
    }
  }

  /// Copie modifiée.
  ScrudSearchRequest copyWith({
    ScrudPagination? pagination,
    ScrudSortOrder? sort,
    bool clearSort = false,
    List<ScrudFilter>? filters,
    String? query,
    bool clearQuery = false,
  }) => ScrudSearchRequest(
    pagination: pagination ?? this.pagination,
    sort: clearSort ? null : (sort ?? this.sort),
    filters: filters ?? this.filters,
    query: clearQuery ? null : (query ?? this.query),
  );

  /// Sérialisation JSON.
  Map<String, Object?> toJson() {
    validate();
    return {
      'pagination': pagination.toJson(),
      if (sort != null) 'sort': sort!.toJson(),
      if (filters.isNotEmpty)
        'filters': [for (final filter in filters) filter.toJson()],
      if (query != null) 'query': query,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ScrudSearchRequest &&
      pagination == other.pagination &&
      sort == other.sort &&
      query == other.query &&
      _listEquals(filters, other.filters);

  @override
  int get hashCode =>
      Object.hash(pagination, sort, query, Object.hashAll(filters));
}

int? _asInt(Object? value, String name) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  throw InvalidQueryException('Le paramètre « $name » doit être un entier.');
}

ScrudFilter _parseFilterEntry(String key, Object? value) {
  final sep = key.lastIndexOf('__');
  if (sep > 0) {
    final field = key.substring(0, sep);
    final suffix = key.substring(sep + 2);
    final op = switch (suffix) {
      'eq' => ScrudFilterOperator.equals,
      'ne' => ScrudFilterOperator.notEquals,
      'contains' => ScrudFilterOperator.contains,
      'startsWith' => ScrudFilterOperator.startsWith,
      'gt' => ScrudFilterOperator.greaterThan,
      'gte' => ScrudFilterOperator.greaterThanOrEqual,
      'lt' => ScrudFilterOperator.lessThan,
      'lte' => ScrudFilterOperator.lessThanOrEqual,
      'in' => ScrudFilterOperator.inList,
      'isNull' => ScrudFilterOperator.isNull,
      'isNotNull' => ScrudFilterOperator.isNotNull,
      _ => null,
    };
    if (op != null) {
      return ScrudFilter(field: field, operator: op, value: value);
    }
  }
  return ScrudFilter(field: key, value: value);
}

bool _valueEquals(Object? a, Object? b) {
  if (a is List && b is List) return _listEquals(a, b);
  return a == b;
}

int _valueHash(Object? value) =>
    value is List ? Object.hashAll(value) : value.hashCode;

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
