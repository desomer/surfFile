/// Connecteur SCRUD de `super_backend` vers une `Datasource` :
/// [ScrudDatasourceConnector], [ScrudConnectorResult] et le générateur de
/// définitions JSON [ScrudDatasourceBlueprint].
///
/// Permet :
/// * d'exécuter directement chacune des 5 opérations d'une datasource
///   (`search`, `create`, `read`, `update`, `delete`) à partir des paramètres
///   du repository de filtre, du contexte `{{ds.*}}` (`key`, `entity`, `page`,
///   `pageSize`, `sort`…) et des paramètres additionnels de tri/pagination ;
/// * de générer les définitions JSON complètes (`DatasourceConfig` et les 5
///   `HttpProviderConfig` associés) prêtes à être chargées dans l'éditeur
///   visuel de `super_container_layout`.
library;

import 'package:meta/meta.dart';

import '../backend/super_backend_service.dart';
import '../models/scrud_exceptions.dart';
import '../models/scrud_query.dart';
import '../models/scrud_result.dart';

/// Résultat d'une opération exécutée par [ScrudDatasourceConnector].
///
/// S'aligne directement sur `DataProviderResult(data, raw)` de
/// `super_container_layout` :
/// * pour `search`, [data] contient la liste `items` et [raw] l'enveloppe
///   complète `{items, total, nextCursor, page, pageSize, ...}` ;
/// * pour `create`, `read` et `update`, [data] et [raw] contiennent l'entité
///   JSON ;
/// * pour `delete`, [data] et [raw] valent `null`.
@immutable
class ScrudConnectorResult {
  /// Crée un résultat de connecteur.
  const ScrudConnectorResult({this.data, this.raw});

  /// Donnée utile retournée au provider (`List<Map<String, Object?>>`,
  /// `Map<String, Object?>` ou `null`).
  final Object? data;

  /// Réponse brute complète lue par `totalPath` et `nextCursorPath`.
  final Object? raw;
}

/// Connecteur direct reliant une collection de [SuperBackend] aux opérations
/// d'une `Datasource` (`search`, `create`, `read`, `update`, `delete`).
class ScrudDatasourceConnector {
  /// Crée un connecteur pour la [collection] sur [backend].
  ScrudDatasourceConnector({
    required this.backend,
    required this.collection,
    this.mergeUpdates = true,
    this.upsertCreates = false,
  }) {
    validateCollectionName(collection);
  }

  /// Instance de backend cible.
  final SuperBackend backend;

  /// Nom de la collection (`nom_collection`) manipulée par cette datasource.
  final String collection;

  /// Si vrai (défaut), l'opération `update` fusionne partiellement les champs
  /// reçus avec l'entité existante (`merge: true`).
  final bool mergeUpdates;

  /// Si vrai, l'opération `create` autorise le remplacement d'une entité
  /// existante (`upsert: true`).
  final bool upsertCreates;

  /// Exécute [operation] à partir des [parameters] du filtre, du [context]
  /// `{{ds.*}}` de la datasource et des [extraParameters] de tri/pagination.
  Future<ScrudConnectorResult> execute(
    ScrudOperation operation, {
    Map<String, Object?> parameters = const {},
    Map<String, Object?> context = const {},
    Map<String, Object?> extraParameters = const {},
  }) => switch (operation) {
    ScrudOperation.search => search(
      parameters: parameters,
      context: context,
      extraParameters: extraParameters,
    ),
    ScrudOperation.create => create(parameters: parameters, context: context),
    ScrudOperation.read => read(parameters: parameters, context: context),
    ScrudOperation.update => update(parameters: parameters, context: context),
    ScrudOperation.delete => delete(parameters: parameters, context: context),
  };

  /// Exécute l'opération `search` et retourne `items` dans `data` et
  /// l'enveloppe complète dans `raw`.
  Future<ScrudConnectorResult> search({
    Map<String, Object?> parameters = const {},
    Map<String, Object?> context = const {},
    Map<String, Object?> extraParameters = const {},
  }) async {
    final merged = <String, Object?>{...parameters, ...extraParameters};
    final result = await backend.search(collection, parameters: merged);
    final raw = result.toJson();
    return ScrudConnectorResult(data: result.items, raw: raw);
  }

  /// Exécute l'opération `create` à partir des champs de [parameters].
  Future<ScrudConnectorResult> create({
    Map<String, Object?> parameters = const {},
    Map<String, Object?> context = const {},
  }) async {
    final explicitId = _extractOptionalKey(parameters, context);
    final created = await backend.create(
      collection,
      parameters,
      id: explicitId,
      upsert: upsertCreates,
    );
    return ScrudConnectorResult(data: created, raw: created);
  }

  /// Exécute l'opération `read` pour la clé présente dans `context['key']` ou
  /// dans [parameters].
  Future<ScrudConnectorResult> read({
    Map<String, Object?> parameters = const {},
    Map<String, Object?> context = const {},
  }) async {
    final id = _requireEntityKey(parameters, context);
    final entity = await backend.read(collection, id);
    return ScrudConnectorResult(data: entity, raw: entity);
  }

  /// Exécute l'opération `update` pour la clé présente dans `context['key']`
  /// (ou [parameters]) avec les valeurs de [parameters].
  Future<ScrudConnectorResult> update({
    Map<String, Object?> parameters = const {},
    Map<String, Object?> context = const {},
  }) async {
    final id = _requireEntityKey(parameters, context);
    final payload = parameters.isNotEmpty
        ? parameters
        : (context['entity'] is Map
              ? Map<String, Object?>.from(context['entity'] as Map)
              : const <String, Object?>{});
    final updated = await backend.update(
      collection,
      id,
      payload,
      merge: mergeUpdates,
    );
    return ScrudConnectorResult(data: updated, raw: updated);
  }

  /// Exécute l'opération `delete` pour la clé présente dans `context['key']`
  /// (ou [parameters]).
  Future<ScrudConnectorResult> delete({
    Map<String, Object?> parameters = const {},
    Map<String, Object?> context = const {},
  }) async {
    final id = _requireEntityKey(parameters, context);
    await backend.delete(collection, id);
    return const ScrudConnectorResult();
  }

  String? _extractOptionalKey(
    Map<String, Object?> parameters,
    Map<String, Object?> context,
  ) {
    final keyField = backend.keyField;
    final raw =
        (keyField != null ? parameters[keyField] : null) ?? context['key'];
    if (raw == null) return null;
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }

  String _requireEntityKey(
    Map<String, Object?> parameters,
    Map<String, Object?> context,
  ) {
    final keyField = backend.keyField ?? 'id';
    final Object? raw =
        context['key'] ??
        parameters[keyField] ??
        (context['entity'] is Map
            ? (context['entity'] as Map)[keyField]
            : null);
    if (raw == null) {
      throw const InvalidEntityIdException('');
    }
    final text = raw.toString().trim();
    if (text.isEmpty) {
      throw const InvalidEntityIdException('');
    }
    return text;
  }
}

/// Gabarit JSON permettant de générer une `DatasourceConfig` et ses 5
/// `HttpProviderConfig` associés pour une collection de `super_backend`.
@immutable
class ScrudDatasourceBlueprint {
  /// Crée un blueprint de configuration Datasource + Providers HTTP.
  const ScrudDatasourceBlueprint({
    required this.datasourceId,
    String? collection,
    String? label,
    this.keyPath = 'id',
    this.baseUrl = defaultBaseUrl,
    this.apiPrefix = '/api',
    required this.listTarget,
    this.detailTarget,
    this.stateTarget,
    this.searchFilterRepositoryId,
    this.formRepositoryId,
    this.pageSize = ScrudPagination.defaultPageSize,
    this.paginationMode = ScrudPaginationMode.page,
    this.sortFields = const [],
    this.defaultSort,
    this.mergeUpdates = true,
  }) : collection = collection ?? datasourceId,
       label = label ?? datasourceId;

  /// URL de base virtuelle par défaut interceptée par le transport local.
  static const String defaultBaseUrl = 'https://super.backend';

  /// Identifiant de la datasource (ex. `clients`).
  final String datasourceId;

  /// Nom de la collection dans `SuperBackend` (par défaut [datasourceId]).
  final String collection;

  /// Libellé lisible de la datasource.
  final String label;

  /// Chemin de la clé primaire dans une entité JSON (par défaut `'id'`).
  final String keyPath;

  /// URL de base HTTP (`https://super.backend` par défaut).
  final String baseUrl;

  /// Préfixe de chemin REST (`/api` par défaut).
  final String apiPrefix;

  /// Cible JSON `{repositoryId, path}` qui reçoit le tableau `items` du Search.
  final ({String repositoryId, String path}) listTarget;

  /// Cible JSON `{repositoryId, path}` optionnelle qui reçoit le détail (Read).
  final ({String repositoryId, String path})? detailTarget;

  /// Cible JSON `{repositoryId, path}` optionnelle qui reçoit l'état de
  /// pagination (`DatasourcePageState`).
  final ({String repositoryId, String path})? stateTarget;

  /// Repository de filtre pour l'opération `search`, ou `null`.
  final String? searchFilterRepositoryId;

  /// Repository portant les champs saisis pour `create` et `update`, ou `null`.
  final String? formRepositoryId;

  /// Taille de page de la recherche.
  final int pageSize;

  /// Mode de pagination (`page`, `offset`, `cursor`).
  final ScrudPaginationMode paginationMode;

  /// Champs triables déclarés sur la datasource.
  final List<String> sortFields;

  /// Tri par défaut optionnel.
  final ScrudSortOrder? defaultSort;

  /// Utilise `PATCH` (fusion partielle) si vrai, `PUT` (remplacement) sinon.
  final bool mergeUpdates;

  /// Identifiant du provider `search`.
  String get searchProviderId => '${datasourceId}_search';

  /// Identifiant du provider `create`.
  String get createProviderId => '${datasourceId}_create';

  /// Identifiant du provider `read`.
  String get readProviderId => '${datasourceId}_read';

  /// Identifiant du provider `update`.
  String get updateProviderId => '${datasourceId}_update';

  /// Identifiant du provider `delete`.
  String get deleteProviderId => '${datasourceId}_delete';

  /// URL de la collection (`<baseUrl><apiPrefix>/<collection>`).
  String get collectionUrl {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPrefix = apiPrefix.isEmpty
        ? ''
        : (apiPrefix.startsWith('/') ? apiPrefix : '/$apiPrefix');
    final trimmedPrefix = cleanPrefix.endsWith('/')
        ? cleanPrefix.substring(0, cleanPrefix.length - 1)
        : cleanPrefix;
    return '$cleanBase$trimmedPrefix/$collection';
  }

  /// URL d'une entité individuelle (`<collectionUrl>/{{ds.key}}`).
  String get entityUrlTemplate => '$collectionUrl/{{ds.key}}';

  /// Génère les 5 configurations JSON de `HttpProviderConfig` (`search`,
  /// `create`, `read`, `update`, `delete`).
  List<Map<String, Object?>> buildHttpProviderJsons() => [
    {
      'id': searchProviderId,
      'label': '$label (Search)',
      'type': 'http',
      if (searchFilterRepositoryId != null) 'filter': searchFilterRepositoryId,
      'target': {
        'repositoryId': listTarget.repositoryId,
        'path': listTarget.path,
      },
      'request': {'method': 'GET', 'url': collectionUrl, 'autoParams': true},
      'responsePath': 'items',
    },
    {
      'id': createProviderId,
      'label': '$label (Create)',
      'type': 'http',
      if (formRepositoryId != null) 'filter': formRepositoryId,
      'request': {'method': 'POST', 'url': collectionUrl, 'autoParams': true},
    },
    {
      'id': readProviderId,
      'label': '$label (Read)',
      'type': 'http',
      if (detailTarget != null)
        'target': {
          'repositoryId': detailTarget!.repositoryId,
          'path': detailTarget!.path,
        },
      'request': {
        'method': 'GET',
        'url': entityUrlTemplate,
        'autoParams': false,
      },
    },
    {
      'id': updateProviderId,
      'label': '$label (Update)',
      'type': 'http',
      if (formRepositoryId != null) 'filter': formRepositoryId,
      'request': {
        'method': mergeUpdates ? 'PATCH' : 'PUT',
        'url': entityUrlTemplate,
        'autoParams': true,
      },
    },
    {
      'id': deleteProviderId,
      'label': '$label (Delete)',
      'type': 'http',
      'request': {
        'method': 'DELETE',
        'url': entityUrlTemplate,
        'autoParams': false,
      },
    },
  ];

  /// Génère la configuration JSON complète de `DatasourceConfig`.
  Map<String, Object?> buildDatasourceJson() => {
    'id': datasourceId,
    'label': label,
    'keyPath': keyPath,
    'search': {
      'provider': searchProviderId,
      if (stateTarget != null)
        'state': {
          'repositoryId': stateTarget!.repositoryId,
          'path': stateTarget!.path,
        },
      'sort': {
        'fieldParam': 'sort',
        'directionParam': 'direction',
        'fields': sortFields,
        if (defaultSort != null) 'default': defaultSort!.toJson(),
      },
      'pagination': {
        'mode': paginationMode.name,
        'pageSize': pageSize,
        if (paginationMode == ScrudPaginationMode.cursor)
          'nextCursorPath': 'nextCursor',
        'totalPath': 'total',
      },
    },
    'create': {'provider': createProviderId, 'insert': 'end'},
    'read': {'provider': readProviderId},
    'update': {'provider': updateProviderId},
    'delete': {'provider': deleteProviderId},
  };
}
