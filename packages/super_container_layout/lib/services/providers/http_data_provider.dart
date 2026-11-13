/// Provider HTTP : exécute l'appel d'API décrit par une [HttpProviderConfig].
///
/// [HttpDataProvider] transforme les paramètres du repository de filtre en
/// requête (`{{...}}` de l'URL, des en-têtes, des paramètres et du corps,
/// paramètres automatiques), l'envoie par un [DataProviderHttpTransport] puis
/// extrait les lignes de la réponse JSON (`responsePath`). Les erreurs sont
/// des [DataProviderException] au message affichable, sans URL ni en-tête
/// (ils peuvent contenir un secret issu de `{{env.NOM}}`).
///
/// Les variables d'environnement lisibles par `{{env.NOM}}` doivent toutes
/// commencer par [providerEnvPrefix] : une configuration importée ne peut
/// ainsi pas exfiltrer `PATH`, `USERPROFILE` ou une clé sans rapport.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../models/json_text_binding.dart';
import '../../models/providers/data_provider.dart';
import '../../models/providers/http_provider_config.dart';
import '../../models/providers/provider_template.dart';
import 'data_provider_http_transport.dart';

/// Préfixe obligatoire des variables d'environnement lisibles par
/// `{{env.NOM}}`.
const providerEnvPrefix = 'PROVIDER_';

/// Taille maximale d'une URL après application des paramètres.
const _maxRequestUrlLength = 8192;

/// Taille maximale du corps JSON d'une requête, après application des
/// paramètres.
const _maxRequestBodyBytes = 1024 * 1024;

/// Nombre de caractères conservés d'un corps d'erreur HTTP dans un message.
const _errorExcerptLength = 200;

final _headerControlPattern = RegExp(r'[\x00-\x08\x0a-\x1f\x7f]');
final _whitespacePattern = RegExp(r'\s+');
final DataProviderHttpTransport _sharedTransport =
    DartIoDataProviderHttpTransport();

/// Résolveur par défaut de `{{env.NOM}}` : `.env` chargé par `flutter_dotenv`,
/// puis variables d'environnement du système.
///
/// Seuls les noms commençant par [providerEnvPrefix] sont résolus ; les
/// valeurs vides sont considérées comme absentes.
String? defaultProviderEnv(String name) {
  if (!name.startsWith(providerEnvPrefix)) return null;
  final loaded = dotenv.isInitialized ? dotenv.env[name]?.trim() : null;
  if (loaded != null && loaded.isNotEmpty) return loaded;
  if (kIsWeb) return null;
  final system = Platform.environment[name]?.trim();
  return system == null || system.isEmpty ? null : system;
}

/// Provider qui récupère ses lignes par un appel HTTP `GET` ou `POST`.
class HttpDataProvider extends DataProvider {
  /// Crée le provider de [config].
  ///
  /// [transport] remplace le transport `dart:io` partagé (tests, proxy) et
  /// [env] le résolveur [defaultProviderEnv].
  HttpDataProvider(
    this.config, {
    DataProviderHttpTransport? transport,
    ProviderEnvResolver? env,
  }) : _transport = transport ?? _sharedTransport,
       _env = env ?? defaultProviderEnv,
       super(
         id: config.id,
         label: config.label,
         filterRepositoryId: config.filterRepositoryId,
         target: config.target,
         loading: config.loading,
         error: config.error,
         autoSearch: config.autoSearch,
       );

  /// Configuration exécutée par ce provider.
  final HttpProviderConfig config;

  final DataProviderHttpTransport _transport;
  final ProviderEnvResolver _env;
  late final Set<String> _consumedKeys = config.request.consumedFilterKeys;

  @override
  void validate() => config.validate();

  @override
  Future<List<Object?>> fetch(Map<String, Object?> parameters) async {
    final DataProviderHttpRequest request;
    try {
      request = _buildRequest(parameters);
    } on FormatException catch (error) {
      throw DataProviderException('Requête invalide : ${error.message}');
    }
    return _parseResponse(await _transport.send(request));
  }

  DataProviderHttpRequest _buildRequest(Map<String, Object?> parameters) {
    final template = config.request;
    final context = ProviderTemplateContext(filter: parameters, env: _env);
    final uri = _withQuery(
      _renderUrl(template.url, context),
      template,
      parameters,
      context,
    );
    if (uri.toString().length > _maxRequestUrlLength) {
      throw const FormatException('l’URL de la requête est trop longue.');
    }
    final headers = _renderHeaders(template, context);
    String? body;
    if (template.method == 'POST') {
      final payload = template.body != null
          ? renderProviderBody(template.body, context)
          : template.autoParams
          ? {
              for (final entry in parameters.entries)
                if (!_consumedKeys.contains(entry.key)) entry.key: entry.value,
            }
          : null;
      if (payload != null) {
        body = jsonEncode(payload);
        if (utf8.encode(body).length > _maxRequestBodyBytes) {
          throw const FormatException(
            'le corps de la requête est trop volumineux.',
          );
        }
        if (!headers.keys.any((name) => name.toLowerCase() == 'content-type')) {
          headers['Content-Type'] = 'application/json; charset=utf-8';
        }
      }
    }
    return DataProviderHttpRequest(
      method: template.method,
      uri: uri,
      headers: headers,
      body: body,
      timeout: Duration(milliseconds: template.timeoutMs),
    );
  }

  static Uri _renderUrl(String url, ProviderTemplateContext context) {
    final rendered = ProviderTemplate.parse(url)
        .render(context, strict: true, encode: true)!;
    final uri = Uri.tryParse(rendered);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('l’URL obtenue est invalide.');
    }
    return uri;
  }

  /// Fusionne, par ordre croissant de priorité, les paramètres déjà présents
  /// dans l'URL, les paramètres automatiques du filtre (`GET` seulement) puis
  /// les paramètres explicites `query`.
  Uri _withQuery(
    Uri uri,
    HttpRequestTemplate template,
    Map<String, Object?> parameters,
    ProviderTemplateContext context,
  ) {
    final params = <String, List<String>>{...uri.queryParametersAll};
    var changed = false;
    if (template.autoParams && template.method == 'GET') {
      for (final entry in parameters.entries) {
        if (_consumedKeys.contains(entry.key) ||
            template.query.containsKey(entry.key) ||
            params.containsKey(entry.key)) {
          continue;
        }
        final values = _queryValues(entry.value);
        if (values == null) continue;
        params[entry.key] = values;
        changed = true;
      }
    }
    for (final entry in template.query.entries) {
      final value = ProviderTemplate.parse(entry.value).render(context);
      if (value == null) continue;
      params[entry.key] = [value];
      changed = true;
    }
    return changed ? uri.replace(queryParameters: params) : uri;
  }

  /// Valeurs d'un paramètre automatique : scalaire ou tableau de scalaires ;
  /// `null` pour une valeur vide, un objet ou un tableau d'objets.
  static List<String>? _queryValues(Object? value) {
    String? text(Object? item) => switch (item) {
      String string when string.trim().isNotEmpty => string,
      bool flag => flag.toString(),
      num number => number.toString(),
      _ => null,
    };
    if (value is List) {
      final result = <String>[];
      for (final item in value) {
        if (item == null) continue;
        if (item is! String && item is! num && item is! bool) return null;
        final converted = text(item);
        if (converted != null) result.add(converted);
      }
      return result.isEmpty ? null : result;
    }
    final single = text(value);
    return single == null ? null : [single];
  }

  static Map<String, String> _renderHeaders(
    HttpRequestTemplate template,
    ProviderTemplateContext context,
  ) {
    final headers = <String, String>{};
    for (final entry in template.headers.entries) {
      final value = ProviderTemplate.parse(entry.value).render(context);
      if (value == null) continue;
      if (_headerControlPattern.hasMatch(value)) {
        throw FormatException(
          'l’en-tête « ${entry.key} » contient un caractère de contrôle.',
        );
      }
      headers[entry.key] = value;
    }
    if (!headers.keys.any((name) => name.toLowerCase() == 'accept')) {
      headers['Accept'] = 'application/json';
    }
    return headers;
  }

  List<Object?> _parseResponse(DataProviderHttpResponse response) {
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      throw DataProviderException(_failureMessage(response));
    }
    if (status == 204) return <Object?>[];
    var text = response.body;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    if (text.trim().isEmpty) {
      throw DataProviderException('Réponse vide (HTTP $status).');
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const DataProviderException('La réponse n’est pas du JSON valide.');
    }
    var node = json;
    final path = config.responsePath;
    if (path != null) {
      try {
        node = JsonAttributePath(path).readNode(json);
      } on FormatException {
        node = null;
      }
      if (node == null) {
        throw DataProviderException('Chemin « $path » absent de la réponse.');
      }
    }
    if (node is List) return List<Object?>.of(node);
    if (node is Map) return <Object?>[node];
    throw const DataProviderException(
      'La réponse doit être un tableau ou un objet JSON.',
    );
  }

  static String _failureMessage(DataProviderHttpResponse response) {
    final code = response.statusCode;
    if (code >= 300 && code < 400) {
      return 'Redirection non suivie (HTTP $code).';
    }
    var excerpt = response.body.replaceAll(_whitespacePattern, ' ').trim();
    if (excerpt.length > _errorExcerptLength) {
      excerpt = '${excerpt.substring(0, _errorExcerptLength)}…';
    }
    return excerpt.isEmpty
        ? 'Erreur HTTP $code.'
        : 'Erreur HTTP $code : $excerpt';
  }
}
