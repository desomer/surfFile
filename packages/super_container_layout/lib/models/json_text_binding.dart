/// Liaison de composants aux attributs d'un repository JSON.
///
/// Un *repository* est un fichier JSON nommé, géré par `JsonRepositoryStore`
/// et identifié par un ID stable de 32 caractères hexadécimaux. Ce fichier
/// définit :
///
/// * [JsonTextBinding] : la liaison persistée d'un composant (repository +
///   chemin), par exemple la valeur d'un `SuperText` ou le tableau d'une
///   `SuperListView` ;
/// * [JsonAttributePath] : la syntaxe des chemins et les lectures / écritures
///   immuables dans un arbre JSON.
///
/// ## Syntaxe des chemins
///
/// | Chemin                         | Signification                              |
/// |--------------------------------|--------------------------------------------|
/// | `client.nom`                   | clé `nom` de l'objet `client`              |
/// | `clients[0].nom`               | `nom` du premier élément de `clients`      |
/// | `clients[?].nom`               | `nom` de la ligne courante / sélectionnée  |
/// | `clients[?].commandes[?].ref`  | deux niveaux de tableaux imbriqués         |
///
/// Ce n'est pas du JSONPath : seules les clés pointées et les indices entre
/// crochets sont acceptés (pas de filtre, de `*`, de `..` ni de guillemets).
/// Les clés ne peuvent contenir ni `.`, ni `[`, `]`, `?`, ni espace.
///
/// ## Le joker `[?]`
///
/// Un `[?]` est un indice fourni à l'exécution. Les `[?]` sont remplis dans
/// l'ordre, du tableau le plus externe au plus interne :
///
/// 1. d'abord par les `SuperListView` englobantes (`JsonListScope`) : dans la
///    4e ligne d'une liste sur `clients`, `clients[?].nom` lit
///    `clients[3].nom` ;
/// 2. puis, pour les `[?]` restants, par la **ligne sélectionnée** (clic) du
///    tableau correspondant, mémorisée dans le `JsonRepositoryBinding` du
///    repository (voir `JsonListScope.resolveSelected`). Un `SuperText` placé
///    hors de toute liste avec `clients[?].nom` affiche donc le client
///    sélectionné : c'est le mécanisme maître / détail.
///
/// Sans ligne sélectionnée, la liaison n'est pas résolue et le composant
/// reste vide et non modifiable.
///
/// ## Exemple
///
/// Avec le repository suivant :
///
/// ```json
/// {
///   "clients": [
///     {"nom": "Alice", "commandes": [{"ref": "A1"}, {"ref": "A2"}]},
///     {"nom": "Bob", "commandes": [{"ref": "B1"}]}
///   ]
/// }
/// ```
///
/// * une `SuperListView` liée à `clients` répète son gabarit pour Alice et
///   Bob ; dans son gabarit, un `SuperText` lié à `clients[?].nom` avec le
///   repository hérité affiche le nom de la ligne ;
/// * une sous-liste liée à `clients[?].commandes` affiche les commandes de
///   chaque client ;
/// * hors de la liste, un `SuperText` lié à `clients[?].commandes[?].ref`
///   affiche la commande sélectionnée du client sélectionné.
///
/// ```dart
/// const ligne = JsonTextBinding(path: 'clients[?].nom'); // repository hérité
/// final concret = ligne.resolve(repositoryId: id, indices: [1]);
/// // concret.path == 'clients[1].nom'
///
/// final chemin = JsonAttributePath('clients[1].nom');
/// chemin.read(document); // 'Bob'
/// final nouveau = chemin.write(document, 'Robert', 'Bob'); // copie modifiée
/// ```
/// 
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

final _repositoryIdPattern = RegExp(r'^[0-9a-f]{32}$');

/// Liaison persistée d'un composant à un attribut (ou un tableau) d'un
/// repository JSON.
///
/// * [repositoryId] : ID du repository ; `null` signifie « hérité de la liste
///   englobante » (option *Hérité de la liste englobante* des éditeurs). Hors
///   de toute liste, un repository explicite est donc obligatoire.
/// * [path] : chemin [JsonAttributePath], pouvant contenir des `[?]`.
///
/// Une liaison est *concrète* ([isResolved]) quand elle a un repository et
/// aucun `[?]` : c'est la seule forme lisible ou modifiable par
/// `JsonRepositoryStore`. On obtient une liaison concrète avec [resolve], ou
/// avec `JsonListScope.resolve` / `JsonListScope.resolveSelected` depuis un
/// widget.
///
/// La valeur est immuable, comparable par valeur et sérialisée en
/// `{"repositoryId": "...", "path": "..."}` (la clé `repositoryId` est
/// omise quand elle est héritée).
///
/// ```dart
/// const liaison = JsonTextBinding(
///   repositoryId: '0123456789abcdef0123456789abcdef',
///   path: 'clients[?].nom',
/// );
/// liaison.isResolved; // false : un [?] reste à remplir
/// liaison.resolve(indices: [0]).path; // 'clients[0].nom'
/// ```
@immutable
class JsonTextBinding {
  const JsonTextBinding({this.repositoryId, required this.path});

  /// ID du repository (32 caractères hexadécimaux), ou `null` pour hériter
  /// celui de la liste englobante.
  final String? repositoryId;

  /// Chemin de l'attribut, par exemple `clients[?].nom`.
  final String path;

  /// Vérifie le format de l'ID et la syntaxe du chemin ; les `[?]` et le
  /// repository hérité sont autorisés.
  ///
  /// Lève une [FormatException] avec un message affichable sinon.
  void validate() {
    if (repositoryId != null && !_repositoryIdPattern.hasMatch(repositoryId!)) {
      throw const FormatException('ID de repository invalide.');
    }
    JsonAttributePath(path);
  }

  /// Vrai pour une liaison concrète : repository explicite et aucun `[?]`.
  bool get isResolved =>
      repositoryId != null && JsonAttributePath(path).isResolved;

  /// Comme [validate], et exige en plus une liaison concrète.
  ///
  /// Lève une [FormatException] si le repository est hérité ou s'il reste
  /// des `[?]`.
  void validateResolved() {
    validate();
    if (repositoryId == null) {
      throw const FormatException(
        'Repository hérité indisponible : placez ce composant dans une liste '
        'liée ou choisissez un repository.',
      );
    }
    JsonAttributePath(path).requireResolved();
  }

  /// Retourne la liaison concrète pour une ligne donnée.
  ///
  /// * [repositoryId] remplace le repository seulement s'il est hérité ;
  /// * [indices] remplissent les `[?]` dans l'ordre, liste externe d'abord.
  ///   Les indices en trop (listes plus profondes que le chemin) sont
  ///   ignorés.
  ///
  /// Lève une [FormatException] s'il manque le repository ou des indices.
  JsonTextBinding resolve({
    String? repositoryId,
    List<int> indices = const [],
  }) {
    validate();
    final result = JsonTextBinding(
      repositoryId: this.repositoryId ?? repositoryId,
      path: JsonAttributePath(path).resolve(indices).toString(),
    );
    result.validateResolved();
    return result;
  }

  /// Forme JSON persistée dans l'apparence ; `repositoryId` est omis quand
  /// il est hérité.
  Map<String, Object?> toJson() {
    validate();
    return {'repositoryId': ?repositoryId, 'path': path};
  }

  /// Lecture stricte : seules les clés `repositoryId` et `path` sont
  /// acceptées, sinon une [FormatException] est levée.
  factory JsonTextBinding.fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['path'] is! String ||
        json.keys.any((key) => key != 'repositoryId' && key != 'path') ||
        (json.containsKey('repositoryId') && json['repositoryId'] is! String)) {
      throw const FormatException('Liaison de repository invalide.');
    }
    final result = JsonTextBinding(
      repositoryId: json['repositoryId'] as String?,
      path: json['path'] as String,
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is JsonTextBinding &&
      repositoryId == other.repositoryId &&
      path == other.path;

  @override
  int get hashCode => Object.hash(repositoryId, path);
}

class _Wildcard {
  const _Wildcard();
}

const _wildcard = _Wildcard();

/// Chemin strict dans un arbre JSON : clés d'objet séparées par des points et
/// indices de tableau entre crochets (ce n'est pas du JSONPath).
///
/// Exemples valides : `nom`, `client.adresse.ville`, `clients[0].nom`,
/// `matrice[1][2]`, `clients[?].commandes[?].ref`.
/// Exemples invalides : `.nom`, `clients[]`, `clients[-1]`, `a[??]`, `a?`.
///
/// Un `[?]` est un indice à fournir ([resolve]) : par les listes englobantes
/// ou par la ligne sélectionnée du tableau (voir la documentation du
/// fichier). Les opérations de lecture et d'écriture exigent un chemin
/// résolu, sans `[?]`.
///
/// Toutes les écritures sont **immuables** : elles retournent un nouvel
/// arbre et ne modifient jamais celui reçu, même en cas d'erreur.
///
/// ```dart
/// final chemin = JsonAttributePath('clients[?].nom');
/// chemin.wildcardCount; // 1
/// chemin.arrayTemplates; // ['clients']
/// final concret = chemin.resolve([1]); // clients[1].nom
/// concret.read({'clients': [{'nom': 'A'}, {'nom': 'B'}]}); // 'B'
/// ```
class JsonAttributePath {
  /// Analyse [path] ; lève une [FormatException] si la syntaxe est invalide.
  JsonAttributePath(String path) : _segments = _parse(path);

  JsonAttributePath._(this._segments);

  /// Clés (`String`), indices (`int`) et jokers `[?]`.
  final List<Object> _segments;

  /// Nombre de `[?]` du chemin.
  int get wildcardCount =>
      _segments.where((segment) => identical(segment, _wildcard)).length;

  /// Vrai si le chemin ne contient aucun `[?]`.
  bool get isResolved => wildcardCount == 0;

  /// Lève une [FormatException] s'il reste des `[?]`.
  void requireResolved() {
    if (!isResolved) {
      throw FormatException(
        'Le chemin contient $wildcardCount [?] : placez ce composant dans '
        '$wildcardCount liste(s) imbriquée(s).',
      );
    }
  }

  /// Remplace chaque `[?]` par [indices], tableau externe d'abord.
  ///
  /// Les indices en trop appartiennent à des listes plus profondes que ce
  /// chemin n'utilise pas : `clients[?].nom` résolu avec `[2, 5]` donne
  /// `clients[2].nom`. Lève une [FormatException] s'il en manque.
  JsonAttributePath resolve(List<int> indices) {
    if (indices.length < wildcardCount) requireResolvedWith(indices.length);
    var next = 0;
    return JsonAttributePath._([
      for (final segment in _segments)
        identical(segment, _wildcard) ? indices[next++] : segment,
    ]);
  }

  /// Chemin modèle du tableau indexé par chaque `[?]`, dans l'ordre.
  ///
  /// Pour `clients[?].commandes[?].ref` : `['clients', 'clients[?].commandes']`.
  /// Ces chemins modèles identifient les tableaux dont la ligne sélectionnée
  /// est mémorisée par `JsonRepositoryBinding` : une seule sélection est
  /// gardée pour `clients[?].commandes`, quel que soit le client.
  List<String> get arrayTemplates => [
    for (var i = 0; i < _segments.length; i++)
      if (identical(_segments[i], _wildcard))
        JsonAttributePath._(_segments.sublist(0, i)).toString(),
  ];

  /// Lève une [FormatException] si le chemin a plus de `[?]` que [depth]
  /// listes englobantes ne peuvent en fournir.
  void requireResolvedWith(int depth) {
    if (wildcardCount > depth) {
      throw FormatException(
        'Le chemin contient $wildcardCount [?] mais seulement $depth liste(s) '
        'englobante(s).',
      );
    }
  }

  /// Forme canonique du chemin (par exemple `clients[?].nom`), utilisable
  /// comme clé de comparaison.
  @override
  String toString() {
    final buffer = StringBuffer();
    for (final segment in _segments) {
      if (segment is String) {
        if (buffer.isNotEmpty) buffer.write('.');
        buffer.write(segment);
      } else {
        buffer.write(identical(segment, _wildcard) ? '[?]' : '[$segment]');
      }
    }
    return buffer.toString();
  }

  static List<Object> _parse(String path) {
    final matches = RegExp(r'(^|\.)([^.\[\]\s?]+)|\[([0-9]+|\?)\]')
        .allMatches(path);
    final segments = <Object>[];
    var offset = 0;
    for (final match in matches) {
      if (match.start != offset ||
          (offset == 0 && match.group(1) == '.') ||
          (offset > 0 && match.group(1) == '')) {
        throw const FormatException('Chemin JSON invalide.');
      }
      final index = match.group(3);
      if (index == '?') {
        segments.add(_wildcard);
        offset = match.end;
        continue;
      }
      final parsedIndex = index == null ? null : int.tryParse(index);
      if (index != null && parsedIndex == null) {
        throw const FormatException('Indice JSON invalide.');
      }
      segments.add(index == null ? match.group(2)! : parsedIndex!);
      offset = match.end;
    }
    if (segments.isEmpty || offset != path.length) {
      throw const FormatException(
        'Chemin JSON invalide. Exemple : client.nom, clients[0].nom ou '
        'clients[?].nom.',
      );
    }
    return segments;
  }

  /// Lit n'importe quel nœud JSON (objet, tableau ou valeur), par exemple le
  /// tableau d'une liste.
  ///
  /// Une clé absente donne `null` ; un indice inexistant ou une structure
  /// incompatible (clé sur un tableau…) lève une [FormatException].
  Object? readNode(Object? root) {
    requireResolved();
    Object? value = root;
    for (final segment in _segments) {
      if (segment is String) {
        if (value == null) continue;
        if (value is! Map<String, dynamic>) _incompatible();
        value = value[segment];
      } else {
        final index = segment as int;
        if (value is! List || index >= value.length) {
          throw const FormatException('Indice de tableau JSON inexistant.');
        }
        value = value[index];
      }
    }
    return value;
  }

  /// Retourne un nouvel arbre JSON où [node] remplace la valeur de ce chemin.
  ///
  /// Les objets manquants sont créés, mais les indices de tableau doivent
  /// exister. Sert notamment à ajouter ou retirer des éléments d'un tableau.
  Object? replaceNode(Object? root, Object? node) {
    requireResolved();
    Object? update(Object? value, int depth) {
      if (depth == _segments.length) return node;
      final segment = _segments[depth];
      if (segment is String) {
        if (value != null && value is! Map<String, dynamic>) _incompatible();
        final map = value == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.of(value as Map<String, dynamic>);
        map[segment] = update(map[segment], depth + 1);
        return map;
      }
      final index = segment as int;
      if (value is! List || index >= value.length) {
        throw const FormatException('Indice de tableau JSON inexistant.');
      }
      final list = List<Object?>.of(value);
      list[index] = update(list[index], depth + 1);
      return list;
    }

    return update(root, 0);
  }

  /// Lit une valeur simple (`String`, `num` fini, `bool` ou `null`) pour un
  /// champ texte.
  ///
  /// Une clé absente donne `null`. Lève une [FormatException] si la valeur
  /// est un objet ou un tableau, si un indice n'existe pas ou si la structure
  /// ne correspond pas au chemin.
  Object? read(Object? root) {
    requireResolved();
    Object? value = root;
    for (final segment in _segments) {
      if (segment is String) {
        if (value == null) continue;
        if (value is! Map<String, dynamic>) _incompatible();
        value = value[segment];
      } else {
        final index = segment as int;
        if (value is! List || index >= value.length) {
          throw const FormatException('Indice de tableau JSON inexistant.');
        }
        value = value[index];
      }
    }
    if ((value != null &&
            value is! String &&
            value is! num &&
            value is! bool) ||
        (value is num && !value.isFinite)) {
      throw const FormatException('L’attribut doit être une valeur simple.');
    }
    return value;
  }

  static Never _incompatible() => throw const FormatException(
    'Structure JSON incompatible avec le chemin.',
  );

  /// Retourne un nouvel arbre JSON où ce chemin reçoit [text], converti selon
  /// le type de [previous] (la valeur actuelle, lue avec [read]).
  ///
  /// * `previous` `null` ou `String` : [text] est écrit tel quel (un attribut
  ///   absent devient une chaîne) ;
  /// * `num` ou `bool` : [text] doit être un nombre fini ou `true` / `false`
  ///   en JSON, sinon une [FormatException] est levée.
  ///
  /// Les objets manquants sont créés ; les indices de tableau doivent exister.
  /// [root] n'est jamais modifié, même en cas d'erreur.
  Object? write(Object? root, String text, Object? previous) {
    requireResolved();
    if (previous != null &&
        previous is! String &&
        previous is! num &&
        previous is! bool) {
      throw const FormatException('L’attribut doit être une valeur simple.');
    }
    final Object? replacement;
    if (previous == null || previous is String) {
      replacement = text;
    } else {
      Object? parsed;
      try {
        parsed = jsonDecode(text);
      } on FormatException {
        throw const FormatException('Valeur incompatible avec le type JSON.');
      }
      if ((previous is bool && parsed is! bool) ||
          (previous is num && (parsed is! num || !parsed.isFinite))) {
        throw const FormatException('Valeur incompatible avec le type JSON.');
      }
      replacement = parsed;
    }

    Object? update(Object? value, int depth) {
      if (depth == _segments.length) return replacement;
      final segment = _segments[depth];
      if (segment is String) {
        if (value != null && value is! Map<String, dynamic>) _incompatible();
        final map = value == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.of(value as Map<String, dynamic>);
        map[segment] = update(map[segment], depth + 1);
        return map;
      }
      final index = segment as int;
      if (value is! List || index >= value.length) {
        throw const FormatException('Indice de tableau JSON inexistant.');
      }
      final list = List<Object?>.of(value);
      list[index] = update(list[index], depth + 1);
      return list;
    }

    return update(root, 0);
  }
}
