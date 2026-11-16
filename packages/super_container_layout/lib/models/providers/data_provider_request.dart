/// Requête et résultat d'une exécution de provider : [DataProviderRequest] et
/// [DataProviderResult].
///
/// `DataProvider.fetch` ne reçoit que les paramètres du filtre et retourne des
/// lignes. Pour les datasources (Search / Create / Read / Update / Delete),
/// `DataProvider.execute` reçoit en plus le contexte `ds` (entité courante,
/// clé, page, tri) lu par les gabarits `{{ds.*}}` et les paramètres de tri et
/// de pagination ajoutés automatiquement, puis retourne la donnée utile
/// (liste, objet ou rien) et la réponse brute (total, curseur suivant).
library;

import 'package:flutter/foundation.dart';

/// Requête complète transmise à `DataProvider.execute`.
@immutable
class DataProviderRequest {
  /// Crée une requête ; les collections sont copiées et deviennent
  /// immuables.
  DataProviderRequest({
    Map<String, Object?> parameters = const {},
    Map<String, Object?> context = const {},
    Map<String, Object?> extraParameters = const {},
  }) : parameters = Map<String, Object?>.unmodifiable(parameters),
       context = Map<String, Object?>.unmodifiable(context),
       extraParameters = Map<String, Object?>.unmodifiable(extraParameters);

  /// Paramètres lus dans le repository de filtre du provider.
  final Map<String, Object?> parameters;

  /// Contexte `ds` d'une datasource (`key`, `entity`, `page`, `pageSize`,
  /// `offset`, `limit`, `cursor`, `sort`, `direction`), lu par les gabarits
  /// `{{ds.*}}` ; vide hors datasource.
  final Map<String, Object?> context;

  /// Paramètres de tri et de pagination ajoutés par la datasource (nommés par
  /// sa configuration) ; ils l'emportent sur les paramètres du filtre.
  final Map<String, Object?> extraParameters;

  /// Paramètres du filtre complétés par [extraParameters].
  Map<String, Object?> get allParameters => extraParameters.isEmpty
      ? parameters
      : Map<String, Object?>.unmodifiable({...parameters, ...extraParameters});
}

/// Résultat d'une exécution de provider.
@immutable
class DataProviderResult {
  /// Crée un résultat : [data] est la donnée utile, [raw] la réponse entière.
  const DataProviderResult({this.data, this.raw});

  /// Résultat d'une liste de lignes ([raw] vaut la liste elle-même).
  const DataProviderResult.rows(List<Object?> rows) : data = rows, raw = rows;

  /// Donnée utile : liste de lignes, objet (une entité) ou `null` (aucune
  /// donnée, réponse 204 par exemple).
  final Object? data;

  /// Réponse entière décodée, lue par `totalPath` et `nextCursorPath`.
  final Object? raw;

  /// Lignes de [data] si c'est une liste, sinon `null`.
  List<Object?>? get rows => switch (data) {
    final List<Object?> list => list,
    _ => null,
  };
}
