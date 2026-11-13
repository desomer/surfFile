/// Modèle des providers de données : sources externes (appel d'API, code Dart)
/// qui alimentent un repository JSON.
///
/// Un [DataProvider] lit ses paramètres dans un repository de *filtre*,
/// récupère une liste de lignes ([DataProvider.fetch]) et laisse
/// `DataProviderRegistry` les écrire dans le repository *cible*, ainsi que
/// les indicateurs de chargement et d'erreur. Le comportement
/// `searchProvider` lance la recherche ; une recherche automatique
/// ([ProviderAutoSearch]) la relance quand le filtre change.
///
/// Les providers ne font pas partie de l'`Appearance` : ils sont déclarés par
/// le code hôte ([CallbackDataProvider]) ou chargés depuis des fichiers
/// (`HttpProviderConfig`). Seul `searchProvider { providerId }` est persisté
/// dans les comportements.
library;

import 'package:flutter/foundation.dart';

import '../json_text_binding.dart';

final _providerIdPattern = RegExp(r'^[a-z0-9_]{1,32}$');
final _segmentPattern = RegExp(r'([^.\[\]]+)|\[(\d+)\]');

/// Longueur maximale du libellé d'un provider.
const dataProviderLabelMaxLength = 80;

/// Vrai si [id] est un identifiant de provider valide (minuscules, chiffres
/// et `_`, 1 à 32 caractères).
bool isValidDataProviderId(String id) => _providerIdPattern.hasMatch(id);

/// Erreur d'un provider (réseau, réponse invalide, paramètres incorrects).
///
/// Le [message] est affichable tel quel dans l'interface et dans l'indicateur
/// d'erreur du repository.
class DataProviderException implements Exception {
  /// Crée une erreur de provider.
  const DataProviderException(this.message);

  /// Message lisible décrivant l'échec.
  final String message;

  @override
  String toString() => message;
}

/// Déclenchement automatique de la recherche d'un provider.
@immutable
class ProviderAutoSearch {
  /// Crée une recherche automatique : [debounceMs] est le délai de calme
  /// après la dernière modification du filtre, [onStart] lance une recherche
  /// au démarrage de l'application.
  const ProviderAutoSearch({
    this.debounceMs = defaultDebounceMs,
    this.onStart = false,
  });

  /// Lecture stricte : objet `{"debounceMs": 500, "onStart": false}` dont les
  /// deux clés sont facultatives.
  factory ProviderAutoSearch.fromJson(Object? json) {
    if (json is! Map ||
        json.keys.any((key) => key != 'debounceMs' && key != 'onStart')) {
      throw const FormatException('Recherche automatique invalide.');
    }
    final debounce = json['debounceMs'] ?? defaultDebounceMs;
    final onStart = json['onStart'] ?? false;
    if (debounce is! int || onStart is! bool) {
      throw const FormatException(
        'Recherche automatique : debounceMs doit être un entier et onStart '
        'un booléen.',
      );
    }
    final result = ProviderAutoSearch(debounceMs: debounce, onStart: onStart);
    result.validate();
    return result;
  }

  /// Délai de calme par défaut, en millisecondes.
  static const int defaultDebounceMs = 500;

  /// Délai de calme minimal, en millisecondes.
  static const int minDebounceMs = 100;

  /// Délai de calme maximal, en millisecondes.
  static const int maxDebounceMs = 10000;

  /// Délai écoulé sans modification du filtre avant de lancer la recherche.
  final int debounceMs;

  /// Lance une recherche au démarrage, une fois les providers chargés.
  final bool onStart;

  /// Vérifie que [debounceMs] est compris entre [minDebounceMs] et
  /// [maxDebounceMs].
  void validate() {
    if (debounceMs < minDebounceMs || debounceMs > maxDebounceMs) {
      throw const FormatException(
        'Recherche automatique : le délai doit être compris entre '
        '$minDebounceMs et $maxDebounceMs ms.',
      );
    }
  }

  /// Copie modifiée.
  ProviderAutoSearch copyWith({int? debounceMs, bool? onStart}) =>
      ProviderAutoSearch(
        debounceMs: debounceMs ?? this.debounceMs,
        onStart: onStart ?? this.onStart,
      );

  /// Forme JSON complète.
  Map<String, Object?> toJson() {
    validate();
    return {'debounceMs': debounceMs, 'onStart': onStart};
  }

  /// Forme compacte : les valeurs par défaut sont omises.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      if (debounceMs != defaultDebounceMs) 'debounceMs': debounceMs,
      if (onStart) 'onStart': true,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderAutoSearch &&
      debounceMs == other.debounceMs &&
      onStart == other.onStart;

  @override
  int get hashCode => Object.hash(debounceMs, onStart);
}

/// Phase d'une recherche de provider.
enum DataProviderPhase {
  /// Aucune recherche n'a encore été lancée.
  idle,

  /// Une recherche est en cours.
  loading,

  /// La dernière recherche a réussi.
  success,

  /// La dernière recherche a échoué.
  error,
}

/// État observable de la dernière recherche d'un provider.
@immutable
class DataProviderStatus {
  /// Crée un état de recherche.
  const DataProviderStatus({
    this.phase = DataProviderPhase.idle,
    this.run = 0,
    this.rowCount,
    this.message,
  });

  /// Provider qui n'a encore jamais cherché.
  static const idle = DataProviderStatus();

  /// Phase de la recherche.
  final DataProviderPhase phase;

  /// Numéro croissant de la recherche ; distingue deux états identiques
  /// successifs pour les observateurs.
  final int run;

  /// Nombre de lignes écrites par la dernière recherche réussie.
  final int? rowCount;

  /// Message d'erreur de la dernière recherche échouée.
  final String? message;

  /// Vrai pendant une recherche.
  bool get isLoading => phase == DataProviderPhase.loading;

  @override
  bool operator ==(Object other) =>
      other is DataProviderStatus &&
      phase == other.phase &&
      run == other.run &&
      rowCount == other.rowCount &&
      message == other.message;

  @override
  int get hashCode => Object.hash(phase, run, rowCount, message);
}

/// Segments (clés et indices) d'un chemin résolu, lus dans sa forme canonique.
List<Object> _segmentsOf(String path) => [
  for (final match in _segmentPattern.allMatches(path))
    match.group(1) ?? int.parse(match.group(2)!),
];

bool _isPrefix(List<Object> prefix, List<Object> segments) =>
    prefix.length <= segments.length &&
    Iterable<int>.generate(prefix.length)
        .every((i) => prefix[i] == segments[i]);

Object? _without(Object? node, List<Object> segments, int depth) {
  final segment = segments[depth];
  final last = depth == segments.length - 1;
  if (segment is String) {
    if (node is! Map || !node.containsKey(segment)) return node;
    final copy = Map<String, Object?>.of(node.cast<String, Object?>());
    if (last) {
      copy.remove(segment);
    } else {
      copy[segment] = _without(copy[segment], segments, depth + 1);
    }
    return copy;
  }
  final index = segment as int;
  if (node is! List || index >= node.length) return node;
  final copy = List<Object?>.of(node);
  copy[index] = last ? null : _without(copy[index], segments, depth + 1);
  return copy;
}

void _validateWritable(String name, JsonTextBinding binding) {
  try {
    binding.validateResolved();
    if (JsonAttributePath(binding.path).calculated != null) {
      throw const FormatException(
        'un attribut calculé (@) ne peut pas être écrit.',
      );
    }
  } on FormatException catch (error) {
    throw FormatException('$name : ${error.message}');
  }
}

/// Vérifie les champs communs à tous les providers.
///
/// * [id] : minuscules, chiffres et `_`, 1 à 32 caractères ;
/// * [label] : non vide, [dataProviderLabelMaxLength] caractères au plus ;
/// * [filterRepositoryId] : ID de repository valide, ou `null` ;
/// * [target], [loading] et [error] : liaisons concrètes (repository
///   explicite, sans `[?]` ni attribut calculé), qui ne se chevauchent pas ;
/// * [autoSearch] : exige un repository de filtre.
///
/// Lève une [FormatException] avec un message affichable sinon.
void validateProviderDefinition({
  required String id,
  required String label,
  required String? filterRepositoryId,
  required JsonTextBinding target,
  required JsonTextBinding? loading,
  required JsonTextBinding? error,
  required ProviderAutoSearch? autoSearch,
}) {
  if (!isValidDataProviderId(id)) {
    throw FormatException(
      'Identifiant de provider invalide « $id » : minuscules, chiffres et _ '
      '(1 à 32 caractères).',
    );
  }
  if (label.trim().isEmpty || label.length > dataProviderLabelMaxLength) {
    throw const FormatException(
      'Le libellé du provider doit contenir de 1 à '
      '$dataProviderLabelMaxLength caractères.',
    );
  }
  if (filterRepositoryId != null) {
    JsonTextBinding(repositoryId: filterRepositoryId, path: '_').validate();
  }
  final written = <(String, JsonTextBinding)>[
    ('Résultats', target),
    if (loading != null) ('Indicateur de chargement', loading),
    if (error != null) ('Indicateur d’erreur', error),
  ];
  for (final (name, binding) in written) {
    _validateWritable(name, binding);
  }
  for (var i = 0; i < written.length; i++) {
    for (var j = i + 1; j < written.length; j++) {
      final (firstName, first) = written[i];
      final (secondName, second) = written[j];
      if (first.repositoryId != second.repositoryId) continue;
      final firstSegments = _segmentsOf(first.path);
      final secondSegments = _segmentsOf(second.path);
      if (_isPrefix(firstSegments, secondSegments) ||
          _isPrefix(secondSegments, firstSegments)) {
        throw FormatException(
          '$firstName et $secondName se chevauchent : choisissez des '
          'attributs distincts.',
        );
      }
    }
  }
  if (autoSearch != null) {
    if (filterRepositoryId == null) {
      throw const FormatException(
        'La recherche automatique exige un repository de filtre.',
      );
    }
    autoSearch.validate();
  }
}

/// Source de données qui alimente un repository JSON.
///
/// Une implémentation décrit *où* écrire ([target], [loading], [error]) et
/// *comment* obtenir les lignes ([fetch]). L'orchestration (écriture des
/// indicateurs, ordre des recherches, recherche automatique) est assurée par
/// `DataProviderRegistry`.
@immutable
abstract class DataProvider {
  /// Crée un provider ; [label] est le libellé affiché dans l'éditeur.
  const DataProvider({
    required this.id,
    required this.label,
    required this.target,
    this.filterRepositoryId,
    this.loading,
    this.error,
    this.autoSearch,
  });

  /// Identifiant unique (minuscules, chiffres et `_`, 1 à 32 caractères).
  final String id;

  /// Libellé affiché dans les éditeurs.
  final String label;

  /// Repository qui porte les paramètres de recherche, ou `null`.
  final String? filterRepositoryId;

  /// Tableau du repository qui reçoit les lignes retournées.
  final JsonTextBinding target;

  /// Booléen mis à `true` pendant la recherche, ou `null`.
  final JsonTextBinding? loading;

  /// Texte qui reçoit le message de la dernière erreur (vide en cas de
  /// succès), ou `null`.
  final JsonTextBinding? error;

  /// Déclenchement automatique de la recherche, ou `null`.
  final ProviderAutoSearch? autoSearch;

  /// Récupère les lignes pour les [parameters] du filtre.
  ///
  /// [parameters] ne contient ni la cible ni les indicateurs du provider ; il
  /// ne doit pas être modifié. Lève une [DataProviderException] (message
  /// affichable) en cas d'échec.
  Future<List<Object?>> fetch(Map<String, Object?> parameters);

  /// Vérifie la définition (voir [validateProviderDefinition]).
  void validate() => validateProviderDefinition(
    id: id,
    label: label,
    filterRepositoryId: filterRepositoryId,
    target: target,
    loading: loading,
    error: error,
    autoSearch: autoSearch,
  );

  /// Vrai si le provider lit ou écrit le repository [repositoryId].
  bool usesRepository(String repositoryId) =>
      filterRepositoryId == repositoryId ||
      target.repositoryId == repositoryId ||
      loading?.repositoryId == repositoryId ||
      error?.repositoryId == repositoryId;

  /// Paramètres de recherche extraits du document [filter] du repository de
  /// filtre : la cible et les indicateurs écrits par le provider dans ce
  /// même repository en sont retirés.
  ///
  /// [filter] n'est pas modifié. Lève une [DataProviderException] si ce
  /// n'est pas un objet JSON ; `null` donne des paramètres vides.
  Map<String, Object?> parametersOf(Object? filter) {
    if (filterRepositoryId == null || filter == null) return const {};
    if (filter is! Map) {
      throw const DataProviderException(
        'Le repository de filtre doit contenir un objet JSON.',
      );
    }
    Object? result = filter;
    for (final binding in [target, loading, error]) {
      if (binding == null || binding.repositoryId != filterRepositoryId) {
        continue;
      }
      result = _without(result, _segmentsOf(binding.path), 0);
    }
    return Map<String, Object?>.unmodifiable(
      (result as Map).cast<String, Object?>(),
    );
  }
}

/// Fonction qui retourne les lignes d'un [CallbackDataProvider].
typedef DataProviderCallback = Future<List<Object?>> Function(
  Map<String, Object?> parameters,
);

/// Provider du code hôte : [callback] fournit les lignes.
///
/// Enregistré avec `store.providers.register(...)`, il n'est pas modifiable
/// dans l'éditeur.
class CallbackDataProvider extends DataProvider {
  /// Crée un provider de code ; [label] vaut [id] par défaut.
  const CallbackDataProvider({
    required super.id,
    required super.target,
    required this.callback,
    String? label,
    super.filterRepositoryId,
    super.loading,
    super.error,
    super.autoSearch,
  }) : super(label: label ?? id);

  /// Fonction appelée à chaque recherche.
  final DataProviderCallback callback;

  @override
  Future<List<Object?>> fetch(Map<String, Object?> parameters) =>
      callback(parameters);
}
