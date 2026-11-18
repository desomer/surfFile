/// Définition immuable et sérialisable d'un attribut calculé en JavaScript
/// attaché à un repository JSON ([CalculatedAttributeDefinition]).
library;

import 'package:flutter/foundation.dart';

import 'json_text_binding.dart';

/// Langage d'exécution d'un attribut calculé persisté.
enum CalculatedAttributeLanguage {
  /// JavaScript évalué via le runtime embarqué (QuickJS sur Windows Desktop).
  js('js', 'JavaScript');

  const CalculatedAttributeLanguage(this.id, this.label);

  /// Identifiant sérialisé dans le JSON (`'js'`).
  final String id;

  /// Libellé affichable dans l'interface d'édition.
  final String label;

  /// Décode [raw] en [CalculatedAttributeLanguage] ou lève une [FormatException].
  static CalculatedAttributeLanguage fromJson(Object? raw) {
    if (raw == null || raw == 'js') return CalculatedAttributeLanguage.js;
    throw FormatException('Langage d’attribut calculé non supporté : « $raw ».');
  }
}

/// Définition persistée d'un attribut calculé JavaScript pour un repository.
@immutable
class CalculatedAttributeDefinition {
  /// Crée une définition d'attribut calculé ; appelle [validate] pour garantir
  /// la validité du nom, de la portée éventuelle et du code JavaScript.
  factory CalculatedAttributeDefinition({
    required String name,
    String? scope,
    CalculatedAttributeLanguage language = CalculatedAttributeLanguage.js,
    required String code,
    String? description,
  }) {
    final trimmedName = name.trim();
    final trimmedScope = scope?.trim();
    final normalizedScope = trimmedScope == null || trimmedScope.isEmpty
        ? null
        : _canonicalScope(trimmedScope);
    final trimmedDescription = description?.trim();
    final def = CalculatedAttributeDefinition._(
      name: trimmedName,
      scope: normalizedScope,
      language: language,
      code: code,
      description: trimmedDescription == null || trimmedDescription.isEmpty
          ? null
          : trimmedDescription,
    );
    def.validate();
    return def;
  }

  const CalculatedAttributeDefinition._({
    required this.name,
    required this.scope,
    required this.language,
    required this.code,
    required this.description,
  });

  static final RegExp _namePattern = RegExp(r'^[a-zA-Z0-9_]{1,64}$');

  /// Nom de l'attribut calculé sans le préfixe `@`.
  final String name;

  /// Chemin modèle de ligne JSON (ex. `articles[?]`), ou `null` pour un
  /// calcul à la racine du repository.
  final String? scope;

  /// Langage d'exécution de la formule (actuellement [CalculatedAttributeLanguage.js]).
  final CalculatedAttributeLanguage language;

  /// Code source JavaScript (expression, corps de fonction ou fonction `(row, ctx)`).
  final String code;

  /// Description fonctionnelle optionnelle affichée dans l'éditeur et le contexte IA.
  final String? description;

  /// Chemin modèle complet utilisable dans une liaison (`@nom` ou `<scope>.@nom`).
  String get path => scope == null ? '@$name' : '$scope.@$name';

  static String _canonicalScope(String scope) {
    final parsed = JsonAttributePath(scope);
    if (parsed.calculated != null || !parsed.toString().endsWith('[?]')) {
      throw const FormatException(
        'La portée (scope) doit désigner une ligne JSON se terminant par [?], '
        'par exemple articles[?].',
      );
    }
    return parsed.toString();
  }

  /// Vérifie tous les invariants de la définition ; lève une [FormatException] sinon.
  void validate() {
    if (!_namePattern.hasMatch(name)) {
      throw FormatException('Nom d’attribut calculé invalide : « $name ».');
    }
    if (scope != null) {
      _canonicalScope(scope!);
    }
    if (code.trim().isEmpty) {
      throw FormatException(
        'Le code JavaScript de « $path » ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée et validée de cette définition.
  CalculatedAttributeDefinition copyWith({
    String? name,
    String? scope,
    bool clearScope = false,
    CalculatedAttributeLanguage? language,
    String? code,
    String? description,
    bool clearDescription = false,
  }) => CalculatedAttributeDefinition(
    name: name ?? this.name,
    scope: clearScope ? null : (scope ?? this.scope),
    language: language ?? this.language,
    code: code ?? this.code,
    description: clearDescription ? null : (description ?? this.description),
  );

  /// Sérialise la définition en JSON canonique.
  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'name': name,
      if (scope != null) 'scope': scope,
      'language': language.id,
      'code': code,
      if (description != null) 'description': description,
    };
  }

  /// Sérialise la définition en JSON compact (omet `language` s'il vaut `'js'`).
  Map<String, Object?> toCompactJson() {
    validate();
    return <String, Object?>{
      'name': name,
      if (scope != null) 'scope': scope,
      if (language != CalculatedAttributeLanguage.js) 'language': language.id,
      'code': code,
      if (description != null) 'description': description,
    };
  }

  /// Désérialise une définition depuis un objet JSON ou lève une [FormatException].
  factory CalculatedAttributeDefinition.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'La définition d’attribut calculé doit être un objet JSON.',
      );
    }
    const allowedKeys = <String>{
      'name',
      'scope',
      'language',
      'code',
      'description',
    };
    for (final key in json.keys) {
      if (key is! String || !allowedKeys.contains(key)) {
        throw FormatException(
          'Clé inconnue « $key » dans la définition d’attribut calculé.',
        );
      }
    }
    final rawName = json['name'];
    if (rawName is! String) {
      throw const FormatException(
        'Le nom de l’attribut calculé doit être une chaîne.',
      );
    }
    final rawScope = json['scope'];
    if (rawScope != null && rawScope is! String) {
      throw const FormatException(
        'La portée (scope) de l’attribut calculé doit être une chaîne.',
      );
    }
    final rawCode = json['code'];
    if (rawCode is! String) {
      throw const FormatException(
        'Le code JavaScript de l’attribut calculé doit être une chaîne.',
      );
    }
    final rawDescription = json['description'];
    if (rawDescription != null && rawDescription is! String) {
      throw const FormatException(
        'La description de l’attribut calculé doit être une chaîne.',
      );
    }
    return CalculatedAttributeDefinition(
      name: rawName,
      scope: rawScope as String?,
      language: CalculatedAttributeLanguage.fromJson(json['language']),
      code: rawCode,
      description: rawDescription as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CalculatedAttributeDefinition &&
      name == other.name &&
      scope == other.scope &&
      language == other.language &&
      code == other.code &&
      description == other.description;

  @override
  int get hashCode => Object.hash(name, scope, language, code, description);
}

/// Collection persistée des définitions d'attributs calculés d'un repository.
@immutable
class RepositoryCalculatedAttributesDocument {
  /// Crée le document des définitions pour [repositoryId], sans doublon de chemin.
  factory RepositoryCalculatedAttributesDocument({
    required String repositoryId,
    List<CalculatedAttributeDefinition> attributes = const [],
  }) {
    final trimmedId = repositoryId.trim();
    if (!RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(trimmedId)) {
      throw FormatException('ID de repository invalide : « $repositoryId ».');
    }
    final seen = <String>{};
    final validated = <CalculatedAttributeDefinition>[];
    for (final attr in attributes) {
      attr.validate();
      if (!seen.add(attr.path)) {
        throw FormatException(
          'Attribut calculé en double dans le repository « $trimmedId » : ${attr.path}.',
        );
      }
      validated.add(attr);
    }
    return RepositoryCalculatedAttributesDocument._(
      repositoryId: trimmedId,
      attributes: List<CalculatedAttributeDefinition>.unmodifiable(validated),
    );
  }

  const RepositoryCalculatedAttributesDocument._({
    required this.repositoryId,
    required this.attributes,
  });

  /// Identifiant du repository propriétaire.
  final String repositoryId;

  /// Liste immuable des définitions JS de ce repository.
  final List<CalculatedAttributeDefinition> attributes;

  /// Sérialise le document complet.
  Map<String, Object?> toJson() => <String, Object?>{
    'repositoryId': repositoryId,
    'attributes': <Object?>[for (final attr in attributes) attr.toJson()],
  };

  /// Désérialise le document depuis son fichier JSON.
  factory RepositoryCalculatedAttributesDocument.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Le fichier des attributs calculés doit être un objet JSON.',
      );
    }
    final rawRepoId = json['repositoryId'];
    if (rawRepoId is! String) {
      throw const FormatException(
        'Champ "repositoryId" manquant dans le fichier des attributs calculés.',
      );
    }
    final rawList = json['attributes'];
    if (rawList is! List) {
      throw const FormatException(
        'Champ "attributes" invalide dans le fichier des attributs calculés.',
      );
    }
    return RepositoryCalculatedAttributesDocument(
      repositoryId: rawRepoId,
      attributes: <CalculatedAttributeDefinition>[
        for (final item in rawList)
          CalculatedAttributeDefinition.fromJson(item),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RepositoryCalculatedAttributesDocument &&
      repositoryId == other.repositoryId &&
      listEquals(attributes, other.attributes);

  @override
  int get hashCode => Object.hash(repositoryId, Object.hashAll(attributes));
}
