/// Routeur HTTP REST virtuel (sans réseau) pour [SuperBackend] :
/// [SuperBackendHttpRequest], [SuperBackendHttpResponse] et
/// [SuperBackendHttpRouter].
///
/// Traduit des requêtes HTTP REST standards (`GET`, `POST`, `PUT`, `PATCH`,
/// `DELETE` sur `/<apiPrefix>/<collection>[/<id>]`) en appels SCRUD sur
/// [SuperBackend], et retourne des réponses JSON avec codes HTTP normalisés
/// (`200`, `201`, `204`, `400`, `404`, `405`, `409`, `500`).
///
/// Ce routeur peut être branché directement derrière le
/// `DataProviderHttpTransport` de `super_container_layout` (pour rendre les
/// `HttpProviderConfig` de l'éditeur visuel 100 % fonctionnels en local) ou
/// derrière un serveur `dart:io` / `shelf`.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../backend/super_backend_service.dart';
import '../models/scrud_exceptions.dart';

/// Requête HTTP entrante traitée par [SuperBackendHttpRouter].
@immutable
class SuperBackendHttpRequest {
  /// Crée une requête HTTP entrante.
  const SuperBackendHttpRequest({
    required this.method,
    required this.uri,
    this.headers = const <String, String>{},
    this.body,
  });

  /// Méthode HTTP (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`).
  final String method;

  /// URI complète incluant chemin et paramètres de requête (`queryParameters`).
  final Uri uri;

  /// En-têtes HTTP éventuels.
  final Map<String, String> headers;

  /// Corps JSON brut éventuel.
  final String? body;
}

/// Réponse HTTP produite par [SuperBackendHttpRouter].
@immutable
class SuperBackendHttpResponse {
  /// Crée une réponse HTTP avec [statusCode], [body] et [headers].
  const SuperBackendHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  });

  /// Crée une réponse JSON sérialisée depuis [payload].
  factory SuperBackendHttpResponse.json(int statusCode, Object? payload) =>
      SuperBackendHttpResponse(
        statusCode: statusCode,
        body: payload == null ? '' : jsonEncode(payload),
      );

  /// Code de statut HTTP (`200`, `201`, `204`, `400`, `404`, `409`, `500`).
  final int statusCode;

  /// Corps texte encodé en JSON (vide pour `204`).
  final String body;

  /// En-têtes HTTP de réponse.
  final Map<String, String> headers;
}

/// Routeur HTTP REST exposant toutes les collections de [SuperBackend].
///
/// Convention de routage (avec `apiPrefix = '/api'`) :
/// * `GET /api/<collection>?...` → `search` (`200 OK` `{items, total, ...}`)
/// * `POST /api/<collection>` → `create` (`201 Created` `{id, ...}`)
/// * `GET /api/<collection>/<id>` → `read` (`200 OK` `{id, ...}`)
/// * `PUT /api/<collection>/<id>` → `update(merge: false)` (`200 OK`)
/// * `PATCH /api/<collection>/<id>` → `update(merge: true)` (`200 OK`)
/// * `DELETE /api/<collection>/<id>` → `delete` (`204 No Content`)
class SuperBackendHttpRouter {
  /// Crée un routeur HTTP REST pour [backend].
  SuperBackendHttpRouter({
    required this.backend,
    this.apiPrefix = '/api',
    this.virtualHost = 'super.backend',
  }) : _prefixSegments = _splitSegments(apiPrefix);

  /// Backend SCRUD cible.
  final SuperBackend backend;

  /// Préfixe de chemin attendu avant `<collection>` (ex. `'/api'` ou `''`).
  final String apiPrefix;

  /// Nom d'hôte virtuel reconnu par [matchesUri] (insensible à la casse).
  final String virtualHost;

  final List<String> _prefixSegments;

  /// Vrai si [uri] cible l'hôte virtuel [virtualHost] et commence par
  /// [apiPrefix].
  bool matchesUri(Uri uri) {
    if (uri.host.toLowerCase() != virtualHost.toLowerCase()) return false;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < _prefixSegments.length + 1) return false;
    for (var i = 0; i < _prefixSegments.length; i++) {
      if (segments[i] != _prefixSegments[i]) return false;
    }
    return true;
  }

  /// Traite [request] et retourne une [SuperBackendHttpResponse] sans jamais
  /// lever d'exception non interceptée.
  Future<SuperBackendHttpResponse> handle(
    SuperBackendHttpRequest request,
  ) async {
    try {
      final route = _matchRoute(request.uri);
      if (route == null) {
        return SuperBackendHttpResponse.json(404, {
          'code': 'route_not_found',
          'message': 'Route introuvable : ${request.uri.path}',
          'statusCode': 404,
        });
      }

      final method = request.method.toUpperCase().trim();
      final collection = route.collection;
      final entityId = route.entityId;

      if (entityId == null) {
        switch (method) {
          case 'GET':
            final params = _decodeQueryParameters(request.uri);
            final result = await backend.search(collection, parameters: params);
            return SuperBackendHttpResponse.json(200, result.toJson());
          case 'POST':
            final payload = _decodeJsonBody(request.body);
            final upsert =
                request.uri.queryParameters['upsert']?.toLowerCase() == 'true';
            final created = await backend.create(
              collection,
              payload,
              upsert: upsert,
            );
            return SuperBackendHttpResponse.json(201, created);
          default:
            return _methodNotAllowed(method, request.uri.path);
        }
      } else {
        switch (method) {
          case 'GET':
            final entity = await backend.read(collection, entityId);
            return SuperBackendHttpResponse.json(200, entity);
          case 'PUT':
            final payload = _decodeJsonBody(request.body);
            final updated = await backend.update(
              collection,
              entityId,
              payload,
              merge: false,
            );
            return SuperBackendHttpResponse.json(200, updated);
          case 'PATCH':
            final payload = _decodeJsonBody(request.body);
            final updated = await backend.update(
              collection,
              entityId,
              payload,
              merge: true,
            );
            return SuperBackendHttpResponse.json(200, updated);
          case 'DELETE':
            await backend.delete(collection, entityId);
            return const SuperBackendHttpResponse(statusCode: 204, body: '');
          default:
            return _methodNotAllowed(method, request.uri.path);
        }
      }
    } on SuperBackendException catch (error) {
      return SuperBackendHttpResponse.json(error.statusCode, error.toJson());
    } on Object catch (error) {
      return SuperBackendHttpResponse.json(500, {
        'code': 'internal_error',
        'message': error.toString(),
        'statusCode': 500,
      });
    }
  }

  ({String collection, String? entityId})? _matchRoute(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < _prefixSegments.length + 1 ||
        segments.length > _prefixSegments.length + 2) {
      return null;
    }
    for (var i = 0; i < _prefixSegments.length; i++) {
      if (segments[i] != _prefixSegments[i]) return null;
    }
    final collection = Uri.decodeComponent(segments[_prefixSegments.length]);
    final entityId = segments.length == _prefixSegments.length + 2
        ? Uri.decodeComponent(segments[_prefixSegments.length + 1])
        : null;
    return (collection: collection, entityId: entityId);
  }

  static Map<String, Object?> _decodeQueryParameters(Uri uri) {
    final result = <String, Object?>{};
    uri.queryParametersAll.forEach((key, values) {
      if (values.isEmpty) return;
      if (values.length == 1 && !key.endsWith('__in')) {
        result[key] = _coerceScalar(values.single);
      } else {
        result[key] = [for (final v in values) _coerceScalar(v)];
      }
    });
    return result;
  }

  static Object? _coerceScalar(String raw) {
    final trimmed = raw.trim();
    if (trimmed == 'true') return true;
    if (trimmed == 'false') return false;
    final asInt = int.tryParse(trimmed);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(trimmed);
    if (asDouble != null) return asDouble;
    return raw;
  }

  static Map<String, Object?> _decodeJsonBody(String? body) {
    if (body == null || body.trim().isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw InvalidJsonPayloadException(
        'Corps de requête JSON invalide : ${error.message}',
        cause: error,
      );
    }
    if (decoded is Map<String, Object?>) {
      return Map<String, Object?>.of(decoded);
    }
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    throw const InvalidJsonPayloadException(
      'Le corps de la requête HTTP doit être un objet JSON.',
    );
  }

  static SuperBackendHttpResponse _methodNotAllowed(
    String method,
    String path,
  ) => SuperBackendHttpResponse.json(405, {
    'code': 'method_not_allowed',
    'message': 'Méthode HTTP « $method » non supportée sur « $path ».',
    'statusCode': 405,
  });

  static List<String> _splitSegments(String prefix) => prefix
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
}
