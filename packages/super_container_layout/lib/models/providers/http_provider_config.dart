/// Configuration sérialisable d'un provider HTTP : [HttpProviderConfig] et son
/// gabarit de requête [HttpRequestTemplate].
///
/// Une configuration décrit un appel d'API (méthode, URL, en-têtes, paramètres
/// de requête, corps JSON) dont les valeurs viennent du repository de filtre
/// (`{{q}}`) ou de l'environnement (`{{env.PROVIDER_TOKEN}}`, voir
/// `provider_template.dart`), le chemin des lignes dans la réponse
/// (`responsePath`) et les liaisons écrites par le provider (résultats,
/// chargement, erreur). Elle est stockée dans `<repertoire>/providers/<id>.json`
/// et exécutée par `HttpDataProvider`.
///
/// La lecture JSON est stricte (clés inconnues refusées) et la validation
/// bloque les configurations dangereuses : hôte de l'URL calculé (un secret ne
/// doit pas partir vers une destination variable), identifiants dans l'URL,
/// en-têtes de protocole, corps sur un `GET`, tailles et profondeurs non
/// bornées.
library;

import 'package:flutter/foundation.dart';

import '../json_text_binding.dart';
import 'data_provider.dart';
import 'provider_template.dart';

final _headerNamePattern = RegExp(r'^[A-Za-z0-9-]{1,64}$');
final _urlHeadPattern = RegExp(r'^(https?)://([^/?#]*)', caseSensitive: false);
final _urlForbiddenPattern = RegExp(r'[\s\x00-\x1f\x7f]');
final _controlPattern = RegExp(r'[\x00-\x1f\x7f]');

/// En-têtes gérés par le transport : les définir casserait le protocole.
const _deniedHeaders = <String>{
  'host',
  'content-length',
  'transfer-encoding',
  'connection',
  'keep-alive',
  'upgrade',
  'te',
  'trailer',
  'expect',
  'accept-encoding',
  'content-encoding',
  'proxy-authorization',
  'proxy-connection',
};

Object? _freezeJson(Object? value) {
  switch (value) {
    case Map map:
      final result = <String, Object?>{};
      for (final entry in map.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FormatException(
            'Les clés du corps doivent être du texte.',
          );
        }
        result[key] = _freezeJson(entry.value);
      }
      return Map<String, Object?>.unmodifiable(result);
    case List list:
      return List<Object?>.unmodifiable(list.map(_freezeJson));
    default:
      return value;
  }
}

Object? _copyJson(Object? value) => switch (value) {
  Map map => {
    for (final entry in map.entries)
      entry.key as String: _copyJson(entry.value),
  },
  List list => [for (final item in list) _copyJson(item)],
  _ => value,
};

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
  Map map => Object.hashAllUnordered([
    for (final entry in map.entries)
      Object.hash(entry.key, _jsonHash(entry.value)),
  ]),
  List list => Object.hashAll(list.map(_jsonHash)),
  _ => value.hashCode,
};

bool _mapEquals(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

Map<String, String> _stringMap(String name, Object? value) {
  if (value == null) return const <String, String>{};
  if (value is! Map ||
      value.entries.any(
        (entry) => entry.key is! String || entry.value is! String,
      )) {
    throw FormatException(
      '« $name » doit être un objet dont les valeurs sont du texte.',
    );
  }
  return {
    for (final entry in value.entries)
      entry.key as String: entry.value as String,
  };
}

/// Valide la syntaxe du gabarit [source] ; préfixe l'erreur par [where].
List<ProviderTemplateReference> _parseTemplate(String where, String source) {
  try {
    return ProviderTemplate.parse(source).references;
  } on FormatException catch (error) {
    throw FormatException('$where : ${error.message}');
  }
}

/// Gabarit de la requête HTTP d'un provider.
@immutable
class HttpRequestTemplate {
  /// Crée un gabarit ; les collections sont copiées et deviennent immuables.
  HttpRequestTemplate({
    required this.url,
    this.method = 'GET',
    Map<String, String> headers = const <String, String>{},
    Map<String, String> query = const <String, String>{},
    Object? body,
    this.autoParams = true,
    this.timeoutMs = defaultTimeoutMs,
  }) : headers = Map<String, String>.unmodifiable(headers),
       query = Map<String, String>.unmodifiable(query),
       body = _freezeJson(body);

  /// Lecture stricte du gabarit (`method`, `url`, `headers`, `query`, `body`,
  /// `autoParams`, `timeoutMs`). Lève une [FormatException] sinon.
  factory HttpRequestTemplate.fromJson(Object? json) {
    const keys = {
      'method',
      'url',
      'headers',
      'query',
      'body',
      'autoParams',
      'timeoutMs',
    };
    if (json is! Map || json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException(
        'Requête HTTP invalide : objet attendu, clés inconnues refusées.',
      );
    }
    final url = json['url'];
    final method = json['method'] ?? 'GET';
    final autoParams = json['autoParams'] ?? true;
    final timeoutMs = json['timeoutMs'] ?? defaultTimeoutMs;
    if (url is! String ||
        method is! String ||
        autoParams is! bool ||
        timeoutMs is! int) {
      throw const FormatException(
        'Requête HTTP : url, method, autoParams ou timeoutMs de type invalide.',
      );
    }
    final result = HttpRequestTemplate(
      url: url,
      method: method.toUpperCase(),
      headers: _stringMap('headers', json['headers']),
      query: _stringMap('query', json['query']),
      body: json['body'],
      autoParams: autoParams,
      timeoutMs: timeoutMs,
    );
    result.validate();
    return result;
  }

  /// Délai par défaut de l'échange, en millisecondes.
  static const int defaultTimeoutMs = 30000;

  /// Délai minimal, en millisecondes.
  static const int minTimeoutMs = 1000;

  /// Délai maximal, en millisecondes.
  static const int maxTimeoutMs = 120000;

  /// Longueur maximale de l'URL.
  static const int maxUrlLength = 2048;

  /// Nombre maximal d'en-têtes.
  static const int maxHeaders = 32;

  /// Nombre maximal de paramètres de requête.
  static const int maxQueryEntries = 64;

  /// Longueur maximale d'une valeur d'en-tête ou de paramètre.
  static const int maxValueLength = 4096;

  /// Méthodes HTTP prises en charge.
  static const List<String> methods = ['GET', 'POST'];

  /// Méthode HTTP : `GET` ou `POST`.
  final String method;

  /// URL `http(s)` ; l'hôte est fixe, le reste peut contenir des `{{...}}`.
  final String url;

  /// En-têtes ; les valeurs peuvent contenir des `{{...}}`.
  final Map<String, String> headers;

  /// Paramètres de requête explicites ; les valeurs peuvent contenir des
  /// `{{...}}`. Ils l'emportent sur les paramètres automatiques.
  final Map<String, String> query;

  /// Gabarit du corps JSON (`POST` seulement), ou `null`.
  final Object? body;

  /// Ajoute automatiquement les paramètres du filtre à la requête (query pour
  /// `GET`, corps JSON pour `POST` sans [body]).
  final bool autoParams;

  /// Durée maximale de l'échange, en millisecondes.
  final int timeoutMs;

  /// Références `{{...}}` de l'URL, des en-têtes, des paramètres et du corps.
  ///
  /// Lève une [FormatException] si un gabarit est invalide.
  List<ProviderTemplateReference> get references => [
    ..._parseTemplate('URL', url),
    for (final entry in headers.entries)
      ..._parseTemplate('En-tête « ${entry.key} »', entry.value),
    for (final entry in query.entries)
      ..._parseTemplate('Paramètre « ${entry.key} »', entry.value),
    ...providerBodyReferences(body),
  ];

  /// Clés de premier niveau du filtre lues par un gabarit : elles ne sont pas
  /// répétées par les paramètres automatiques.
  Set<String> get consumedFilterKeys => {
    for (final reference in references)
      if (!reference.isEnv) reference.filterKey,
  };

  /// Vérifie la méthode, l'URL, les en-têtes, les paramètres, le corps et le
  /// délai. Lève une [FormatException] avec un message affichable sinon.
  void validate() {
    if (!methods.contains(method)) {
      throw FormatException(
        'Méthode HTTP « $method » non prise en charge : GET ou POST.',
      );
    }
    _validateUrl();
    _validateHeaders();
    _validateQuery();
    if (body != null) {
      if (method == 'GET') {
        throw const FormatException('Un GET ne peut pas avoir de corps.');
      }
      try {
        providerBodyReferences(body);
      } on FormatException catch (error) {
        throw FormatException('Corps : ${error.message}');
      }
    }
    if (timeoutMs < minTimeoutMs || timeoutMs > maxTimeoutMs) {
      throw const FormatException(
        'Le délai doit être compris entre $minTimeoutMs et $maxTimeoutMs ms.',
      );
    }
  }

  void _validateUrl() {
    if (url.isEmpty || url.length > maxUrlLength) {
      throw const FormatException(
        'L’URL doit contenir de 1 à $maxUrlLength caractères.',
      );
    }
    if (_urlForbiddenPattern.hasMatch(url)) {
      throw const FormatException(
        'L’URL ne doit contenir ni espace ni caractère de contrôle.',
      );
    }
    final head = _urlHeadPattern.firstMatch(url);
    if (head == null) {
      throw const FormatException(
        'L’URL doit commencer par http:// ou https://.',
      );
    }
    final authority = head.group(2)!;
    if (authority.contains('{') || authority.contains('}')) {
      throw const FormatException(
        'L’hôte de l’URL ne peut pas contenir de gabarit {{...}} : la '
        'destination des requêtes, et les secrets qu’elles portent, doit '
        'rester fixe.',
      );
    }
    if (authority.contains('@')) {
      throw const FormatException(
        'L’URL ne doit pas contenir d’identifiants (utilisateur:mot de '
        'passe@) : utilisez un en-tête Authorization.',
      );
    }
    final parsed = Uri.tryParse('${head.group(1)}://$authority/');
    if (parsed == null || parsed.host.isEmpty) {
      throw const FormatException('L’URL ne contient pas d’hôte valide.');
    }
    _parseTemplate('URL', url);
  }

  void _validateHeaders() {
    if (headers.length > maxHeaders) {
      throw const FormatException('Trop d’en-têtes (maximum $maxHeaders).');
    }
    final seen = <String>{};
    for (final entry in headers.entries) {
      final name = entry.key;
      final lower = name.toLowerCase();
      if (!_headerNamePattern.hasMatch(name)) {
        throw FormatException(
          'Nom d’en-tête invalide « $name » : lettres, chiffres et - '
          '(1 à 64 caractères).',
        );
      }
      if (_deniedHeaders.contains(lower)) {
        throw FormatException(
          'L’en-tête « $name » est géré automatiquement et ne peut pas être '
          'défini.',
        );
      }
      if (!seen.add(lower)) {
        throw FormatException('En-tête en double : « $name ».');
      }
      final value = entry.value;
      if (value.length > maxValueLength || _controlPattern.hasMatch(value)) {
        throw FormatException(
          'En-tête « $name » : valeur trop longue ou contenant un caractère '
          'de contrôle.',
        );
      }
      _parseTemplate('En-tête « $name »', value);
    }
  }

  void _validateQuery() {
    if (query.length > maxQueryEntries) {
      throw const FormatException(
        'Trop de paramètres de requête (maximum $maxQueryEntries).',
      );
    }
    for (final entry in query.entries) {
      final name = entry.key;
      if (name.isEmpty ||
          name.length > 128 ||
          name.contains('{{') ||
          _controlPattern.hasMatch(name)) {
        throw FormatException(
          'Nom de paramètre invalide « $name » : texte littéral de 1 à 128 '
          'caractères.',
        );
      }
      if (entry.value.length > maxValueLength) {
        throw FormatException('Paramètre « $name » : valeur trop longue.');
      }
      _parseTemplate('Paramètre « $name »', entry.value);
    }
  }

  /// Copie modifiée ; [clearBody] retire le corps.
  HttpRequestTemplate copyWith({
    String? method,
    String? url,
    Map<String, String>? headers,
    Map<String, String>? query,
    Object? body,
    bool clearBody = false,
    bool? autoParams,
    int? timeoutMs,
  }) => HttpRequestTemplate(
    method: method ?? this.method,
    url: url ?? this.url,
    headers: headers ?? this.headers,
    query: query ?? this.query,
    body: clearBody ? null : (body ?? this.body),
    autoParams: autoParams ?? this.autoParams,
    timeoutMs: timeoutMs ?? this.timeoutMs,
  );

  /// Forme JSON complète.
  Map<String, Object?> toJson() {
    validate();
    return {
      'method': method,
      'url': url,
      'headers': Map<String, String>.of(headers),
      'query': Map<String, String>.of(query),
      if (body != null) 'body': _copyJson(body),
      'autoParams': autoParams,
      'timeoutMs': timeoutMs,
    };
  }

  /// Forme compacte : les valeurs par défaut sont omises.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      if (method != 'GET') 'method': method,
      'url': url,
      if (headers.isNotEmpty) 'headers': Map<String, String>.of(headers),
      if (query.isNotEmpty) 'query': Map<String, String>.of(query),
      if (body != null) 'body': _copyJson(body),
      if (!autoParams) 'autoParams': false,
      if (timeoutMs != defaultTimeoutMs) 'timeoutMs': timeoutMs,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is HttpRequestTemplate &&
      method == other.method &&
      url == other.url &&
      _mapEquals(headers, other.headers) &&
      _mapEquals(query, other.query) &&
      _jsonEquals(body, other.body) &&
      autoParams == other.autoParams &&
      timeoutMs == other.timeoutMs;

  @override
  int get hashCode => Object.hash(
    method,
    url,
    Object.hashAllUnordered(
      headers.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAllUnordered(
      query.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    _jsonHash(body),
    autoParams,
    timeoutMs,
  );
}

/// Définition complète, sérialisable, d'un provider HTTP.
@immutable
class HttpProviderConfig {
  /// Crée une configuration ; [label] est le libellé affiché (souvent [id]).
  const HttpProviderConfig({
    required this.id,
    required this.label,
    required this.target,
    required this.request,
    this.filterRepositoryId,
    this.loading,
    this.error,
    this.autoSearch,
    this.responsePath,
  });

  /// Lecture stricte d'un fichier de provider (`type` vaut `http`). Lève une
  /// [FormatException] si la structure ou une valeur est invalide.
  factory HttpProviderConfig.fromJson(Object? json) {
    const keys = {
      'id',
      'label',
      'type',
      'filter',
      'target',
      'loading',
      'error',
      'autoSearch',
      'request',
      'responsePath',
    };
    if (json is! Map || json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException(
        'Provider invalide : objet attendu, clés inconnues refusées.',
      );
    }
    final id = json['id'];
    final label = json['label'] ?? id;
    final filter = json['filter'];
    final responsePath = json['responsePath'];
    if (json['type'] != 'http' ||
        id is! String ||
        label is! String ||
        (filter != null && filter is! String) ||
        (responsePath != null && responsePath is! String) ||
        json['target'] == null ||
        json['request'] == null) {
      throw const FormatException(
        'Provider invalide : type « http », id, target et request '
        'obligatoires, textes attendus.',
      );
    }
    final result = HttpProviderConfig(
      id: id,
      label: label,
      filterRepositoryId: filter as String?,
      target: JsonTextBinding.fromJson(json['target']),
      loading: json['loading'] == null
          ? null
          : JsonTextBinding.fromJson(json['loading']),
      error: json['error'] == null
          ? null
          : JsonTextBinding.fromJson(json['error']),
      autoSearch: json['autoSearch'] == null
          ? null
          : ProviderAutoSearch.fromJson(json['autoSearch']),
      request: HttpRequestTemplate.fromJson(json['request']),
      responsePath: responsePath as String?,
    );
    result.validate();
    return result;
  }

  /// Identifiant unique, identique au nom du fichier.
  final String id;

  /// Libellé affiché dans l'éditeur.
  final String label;

  /// Repository qui porte les paramètres de recherche, ou `null`.
  final String? filterRepositoryId;

  /// Tableau du repository qui reçoit les lignes.
  final JsonTextBinding target;

  /// Booléen mis à `true` pendant la recherche, ou `null`.
  final JsonTextBinding? loading;

  /// Texte qui reçoit le message d'erreur, ou `null`.
  final JsonTextBinding? error;

  /// Déclenchement automatique de la recherche, ou `null`.
  final ProviderAutoSearch? autoSearch;

  /// Gabarit de la requête HTTP.
  final HttpRequestTemplate request;

  /// Chemin (`data.items`) des lignes dans la réponse JSON, ou `null` pour la
  /// racine.
  final String? responsePath;

  /// Vérifie la définition commune, la requête, `responsePath` et la
  /// cohérence entre les références `{{...}}` et le repository de filtre.
  ///
  /// Lève une [FormatException] avec un message affichable sinon.
  void validate() {
    validateProviderDefinition(
      id: id,
      label: label,
      filterRepositoryId: filterRepositoryId,
      target: target,
      loading: loading,
      error: error,
      autoSearch: autoSearch,
    );
    request.validate();
    if (filterRepositoryId == null &&
        request.references.any((reference) => !reference.isEnv)) {
      throw const FormatException(
        'La requête lit le filtre ({{...}}) mais aucun repository de filtre '
        'n’est choisi.',
      );
    }
    final path = responsePath;
    if (path != null) {
      try {
        final parsed = JsonAttributePath(path)..requireResolved();
        if (parsed.calculated != null) {
          throw const FormatException('un attribut calculé (@) est interdit.');
        }
      } on FormatException catch (error) {
        throw FormatException('Chemin de la réponse : ${error.message}');
      }
    }
  }

  /// Copie modifiée ; les `clear...` retirent la valeur facultative.
  HttpProviderConfig copyWith({
    String? id,
    String? label,
    String? filterRepositoryId,
    bool clearFilter = false,
    JsonTextBinding? target,
    JsonTextBinding? loading,
    bool clearLoading = false,
    JsonTextBinding? error,
    bool clearError = false,
    ProviderAutoSearch? autoSearch,
    bool clearAutoSearch = false,
    HttpRequestTemplate? request,
    String? responsePath,
    bool clearResponsePath = false,
  }) => HttpProviderConfig(
    id: id ?? this.id,
    label: label ?? this.label,
    filterRepositoryId: clearFilter
        ? null
        : (filterRepositoryId ?? this.filterRepositoryId),
    target: target ?? this.target,
    loading: clearLoading ? null : (loading ?? this.loading),
    error: clearError ? null : (error ?? this.error),
    autoSearch: clearAutoSearch ? null : (autoSearch ?? this.autoSearch),
    request: request ?? this.request,
    responsePath: clearResponsePath
        ? null
        : (responsePath ?? this.responsePath),
  );

  /// Forme JSON complète, écrite dans `providers/<id>.json`.
  Map<String, Object?> toJson() {
    validate();
    return {
      'id': id,
      'label': label,
      'type': 'http',
      'filter': ?filterRepositoryId,
      'target': target.toJson(),
      'loading': ?loading?.toJson(),
      'error': ?error?.toJson(),
      'autoSearch': ?autoSearch?.toJson(),
      'request': request.toJson(),
      'responsePath': ?responsePath,
    };
  }

  /// Forme compacte : le libellé égal à l'identifiant et les valeurs par
  /// défaut sont omis.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'id': id,
      if (label != id) 'label': label,
      'type': 'http',
      'filter': ?filterRepositoryId,
      'target': target.toCompactJson(),
      'loading': ?loading?.toCompactJson(),
      'error': ?error?.toCompactJson(),
      'autoSearch': ?autoSearch?.toCompactJson(),
      'request': request.toCompactJson(),
      'responsePath': ?responsePath,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is HttpProviderConfig &&
      id == other.id &&
      label == other.label &&
      filterRepositoryId == other.filterRepositoryId &&
      target == other.target &&
      loading == other.loading &&
      error == other.error &&
      autoSearch == other.autoSearch &&
      request == other.request &&
      responsePath == other.responsePath;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    filterRepositoryId,
    target,
    loading,
    error,
    autoSearch,
    request,
    responsePath,
  );
}
