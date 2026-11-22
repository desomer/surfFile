/// Modèles immuables et exceptions liés à l'association d'un JSON Schema
/// à un repository JSON ([RepositoryJsonSchemaDocument],
/// [JsonSchemaValidationResult], [JsonSchemaValidationException]).
library;

import 'dart:convert' show jsonEncode;

import 'package:flutter/foundation.dart';

/// Problème unitaire relevé lors de la validation d'un document JSON contre
/// un JSON Schema.
@immutable
class JsonSchemaValidationIssue {
  /// Crée une erreur de validation localisée dans l'instance et le schéma.
  const JsonSchemaValidationIssue({
    required this.instancePath,
    required this.schemaPath,
    required this.keyword,
    required this.message,
    this.invalidValue,
  });

  /// Chemin JSON dans le document validé (ex. `''` pour la racine,
  /// `clients[0].email` ou `/clients/0/email`).
  final String instancePath;

  /// Pointeur JSON vers le mot-clé du schéma qui a échoué (ex. `#/required`).
  final String schemaPath;

  /// Mot-clé JSON Schema à l'origine du rejet (`type`, `required`, `minimum`…).
  final String keyword;

  /// Description lisible en français de la violation.
  final String message;

  /// Aperçu compact de la valeur JSON ayant déclenché la violation
  /// (ex. `""`, `"22/11/2026"`, `42`, `null`), lorsqu'une valeur précise existe.
  final String? invalidValue;

  /// Formate [value] en aperçu compact et sûr pour les messages utilisateur et IA.
  static String formatInvalidValue(Object? value, {int maxLength = 60}) {
    if (value == null) return 'null';
    if (value is bool || value is num) return value.toString();
    if (value is String) {
      final encoded = jsonEncode(value);
      if (encoded.length <= maxLength) return encoded;
      final innerLimit = (maxLength - 3).clamp(4, maxLength);
      return '${encoded.substring(0, innerLimit)}…"';
    }
    if (value is List) {
      try {
        final encoded = jsonEncode(value);
        if (encoded.length <= maxLength) return encoded;
      } catch (_) {
        // Repli sur résumé de taille.
      }
      return '[…] (${value.length} élément${value.length > 1 ? 's' : ''})';
    }
    if (value is Map) {
      try {
        final encoded = jsonEncode(value);
        if (encoded.length <= maxLength) return encoded;
      } catch (_) {
        // Repli sur résumé de taille.
      }
      return '{…} (${value.length} clé${value.length > 1 ? 's' : ''})';
    }
    final raw = value.toString();
    return raw.length <= maxLength ? raw : '${raw.substring(0, maxLength - 1)}…';
  }

  /// Libellé compact utilisable dans un message d'erreur multi-lignes.
  String formatLine() {
    final location = instancePath.isEmpty ? '<racine>' : instancePath;
    final valuePart = invalidValue != null && !message.contains(invalidValue!)
        ? ' — valeur : $invalidValue'
        : '';
    return '$location : $message$valuePart ($keyword)';
  }

  /// Sérialise cette erreur au format JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'instancePath': instancePath,
    'schemaPath': schemaPath,
    'keyword': keyword,
    'message': message,
    if (invalidValue != null) 'value': invalidValue,
  };

  /// Désérialise une erreur depuis son JSON.
  factory JsonSchemaValidationIssue.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Une erreur de validation JSON Schema doit être un objet JSON.',
      );
    }
    final instancePath = json['instancePath'];
    final schemaPath = json['schemaPath'];
    final keyword = json['keyword'];
    final message = json['message'];
    final rawValue = json['value'] ?? json['invalidValue'];
    if (instancePath is! String ||
        schemaPath is! String ||
        keyword is! String ||
        message is! String ||
        (rawValue != null && rawValue is! String)) {
      throw const FormatException(
        'Champs invalides dans JsonSchemaValidationIssue.',
      );
    }
    return JsonSchemaValidationIssue(
      instancePath: instancePath,
      schemaPath: schemaPath,
      keyword: keyword,
      message: message,
      invalidValue: rawValue as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is JsonSchemaValidationIssue &&
      instancePath == other.instancePath &&
      schemaPath == other.schemaPath &&
      keyword == other.keyword &&
      message == other.message &&
      invalidValue == other.invalidValue;

  @override
  int get hashCode =>
      Object.hash(instancePath, schemaPath, keyword, message, invalidValue);

  @override
  String toString() => formatLine();
}

/// Résultat complet d'une validation JSON Schema.
@immutable
class JsonSchemaValidationResult {
  /// Crée un résultat de validation avec la liste des violations éventuelles.
  JsonSchemaValidationResult({
    List<JsonSchemaValidationIssue> issues = const [],
  }) : issues = List<JsonSchemaValidationIssue>.unmodifiable(issues);

  /// Résultat valide sans aucune erreur.
  static final JsonSchemaValidationResult valid = JsonSchemaValidationResult();

  /// Liste immuable des erreurs détectées.
  final List<JsonSchemaValidationIssue> issues;

  /// Vrai lorsque le document satisfait intégralement le schéma.
  bool get isValid => issues.isEmpty;

  /// Formate un résumé concis et lisible de [issues].
  String formatSummary({int maxIssues = 5}) {
    if (issues.isEmpty) return 'Document conforme au JSON Schema.';
    final displayed = issues.take(maxIssues).map((i) => '- ${i.formatLine()}');
    final extra = issues.length - maxIssues;
    final suffix = extra > 0 ? '\n… et $extra autre(s) erreur(s).' : '';
    return '${displayed.join('\n')}$suffix';
  }

  @override
  bool operator ==(Object other) =>
      other is JsonSchemaValidationResult && listEquals(issues, other.issues);

  @override
  int get hashCode => Object.hashAll(issues);
}

/// Exception levée lorsqu'une opération sur un repository viole le JSON Schema
/// qui lui est associé.
///
/// Étend [FormatException] afin de s'intégrer naturellement dans la gestion
/// d'erreur existante du store, des liaisons et des éditeurs.
class JsonSchemaValidationException extends FormatException {
  /// Crée une exception de validation pour [repositoryId] et [issues].
  factory JsonSchemaValidationException({
    required String repositoryId,
    required List<JsonSchemaValidationIssue> issues,
    String? prefix,
  }) {
    final frozen = List<JsonSchemaValidationIssue>.unmodifiable(issues);
    final result = JsonSchemaValidationResult(issues: frozen);
    final header =
        prefix ??
        'Le document du repository « $repositoryId » ne respecte pas le JSON Schema :';
    return JsonSchemaValidationException._(
      '$header\n${result.formatSummary()}',
      repositoryId,
      frozen,
    );
  }

  const JsonSchemaValidationException._(
    super.message,
    this.repositoryId,
    this.issues,
  );

  /// Identifiant technique du repository concerné.
  final String repositoryId;

  /// Liste immuable des violations relevées.
  final List<JsonSchemaValidationIssue> issues;
}

/// Document persisté associant un JSON Schema standard à un repository JSON.
@immutable
class RepositoryJsonSchemaDocument {
  /// Crée une association validée entre [repositoryId] et [schema].
  factory RepositoryJsonSchemaDocument({
    required String repositoryId,
    required Map<String, Object?> schema,
  }) {
    final trimmedId = repositoryId.trim();
    final frozenSchema = _freezeJsonMap(schema);
    final doc = RepositoryJsonSchemaDocument._(
      repositoryId: trimmedId,
      schema: frozenSchema,
    );
    doc.validate();
    return doc;
  }

  const RepositoryJsonSchemaDocument._({
    required this.repositoryId,
    required this.schema,
  });

  static final RegExp _idPattern = RegExp(r'^[a-z0-9_]{1,32}$');

  /// Identifiant technique du repository propriétaire.
  final String repositoryId;

  /// Objet JSON Schema standard (Draft 7 / Draft 2020-12) profondément immuable.
  final Map<String, Object?> schema;

  /// Vérifie les invariants structurels du document de schéma ; lève une
  /// [FormatException] en cas d'anomalie.
  void validate() {
    if (!_idPattern.hasMatch(repositoryId)) {
      throw FormatException('ID de repository invalide : « $repositoryId ».');
    }
    _validateJsonValue(schema, path: '');
  }

  /// Retourne une copie modifiée et validée de ce document.
  RepositoryJsonSchemaDocument copyWith({
    String? repositoryId,
    Map<String, Object?>? schema,
  }) => RepositoryJsonSchemaDocument(
    repositoryId: repositoryId ?? this.repositoryId,
    schema: schema ?? this.schema,
  );

  /// Sérialise ce document au format JSON canonique (`schemas/<id>.json`).
  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'repositoryId': repositoryId,
      'schema': deepCloneSchemaMap(schema),
    };
  }

  /// Sérialise ce document sous forme compacte pour les exports IA.
  Map<String, Object?> toCompactJson() => toJson();

  /// Désérialise un [RepositoryJsonSchemaDocument] depuis son JSON.
  factory RepositoryJsonSchemaDocument.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Le fichier de JSON Schema du repository doit être un objet JSON.',
      );
    }
    const allowedKeys = <String>{'repositoryId', 'schema'};
    for (final key in json.keys) {
      if (key is! String || !allowedKeys.contains(key)) {
        throw FormatException(
          'Clé inconnue « $key » dans le fichier de JSON Schema.',
        );
      }
    }
    final rawRepoId = json['repositoryId'];
    if (rawRepoId is! String) {
      throw const FormatException(
        'Champ "repositoryId" manquant dans le fichier de JSON Schema.',
      );
    }
    final rawSchema = json['schema'];
    if (rawSchema is! Map) {
      throw const FormatException(
        'Champ "schema" manquant ou invalide dans le fichier de JSON Schema.',
      );
    }
    final normalizedSchema = <String, Object?>{};
    for (final entry in rawSchema.entries) {
      final k = entry.key;
      if (k is! String) {
        throw const FormatException(
          'Toutes les clés d’un JSON Schema doivent être des chaînes.',
        );
      }
      normalizedSchema[k] = entry.value;
    }
    return RepositoryJsonSchemaDocument(
      repositoryId: rawRepoId,
      schema: normalizedSchema,
    );
  }

  /// Retourne une copie mutable profonde de [source].
  static Map<String, Object?> deepCloneSchemaMap(Map<Object?, Object?> source) {
    final copy = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException(
          'Toutes les clés d’un JSON Schema doivent être des chaînes.',
        );
      }
      copy[key] = _cloneJsonValue(entry.value);
    }
    return copy;
  }

  static Map<String, Object?> _freezeJsonMap(Map<Object?, Object?> source) {
    final copy = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException(
          'Toutes les clés d’un JSON Schema doivent être des chaînes.',
        );
      }
      copy[key] = _freezeJsonValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(copy);
  }

  static Object? _freezeJsonValue(Object? value) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const FormatException(
          'Nombre JSON non fini interdit dans un JSON Schema.',
        );
      }
      return value;
    }
    if (value is List) {
      return List<Object?>.unmodifiable([
        for (final item in value) _freezeJsonValue(item),
      ]);
    }
    if (value is Map) {
      return _freezeJsonMap(value);
    }
    throw FormatException(
      'Valeur non sérialisable en JSON dans le JSON Schema : ${value.runtimeType}.',
    );
  }

  static Object? _cloneJsonValue(Object? value) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const FormatException(
          'Nombre JSON non fini interdit dans un JSON Schema.',
        );
      }
      return value;
    }
    if (value is List) {
      return <Object?>[for (final item in value) _cloneJsonValue(item)];
    }
    if (value is Map) {
      return deepCloneSchemaMap(value);
    }
    throw FormatException(
      'Valeur non sérialisable en JSON dans le JSON Schema : ${value.runtimeType}.',
    );
  }

  static void _validateJsonValue(Object? value, {required String path}) {
    if (value == null || value is bool || value is String || value is int) {
      return;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw FormatException(
          'Nombre non fini interdit dans le JSON Schema ($path).',
        );
      }
      return;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _validateJsonValue(value[i], path: '$path[$i]');
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw FormatException(
            'Clé non textuelle dans le JSON Schema ($path).',
          );
        }
        final nextPath = path.isEmpty ? '${entry.key}' : '$path.${entry.key}';
        _validateJsonValue(entry.value, path: nextPath);
      }
      return;
    }
    throw FormatException(
      'Type de valeur invalide dans le JSON Schema ($path).',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RepositoryJsonSchemaDocument &&
      repositoryId == other.repositoryId &&
      _deepJsonEquals(schema, other.schema);

  @override
  int get hashCode =>
      Object.hash(repositoryId, _deepJsonHash(schema));

  static bool _deepJsonEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key) ||
            !_deepJsonEquals(entry.value, b[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepJsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static int _deepJsonHash(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return Object.hashAll([
        for (final k in keys) Object.hash(k, _deepJsonHash(value[k])),
      ]);
    }
    if (value is List) {
      return Object.hashAll([for (final item in value) _deepJsonHash(item)]);
    }
    return value.hashCode;
  }
}
