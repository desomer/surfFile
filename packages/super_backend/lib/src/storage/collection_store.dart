/// Contrat abstrait de stockage local pour les entités JSON de `super_backend`.
///
/// [CollectionStore] manipule directement le modèle tabulaire à trois colonnes
/// `(nom_collection, id_entity, data_json)` représenté par [StoredJsonRow].
/// Il peut être implémenté au-dessus de SQLite ([SqliteCollectionStore]), en
/// mémoire ([MemoryCollectionStore]), ou par tout autre moteur local.
library;

import 'package:meta/meta.dart';

import '../models/scrud_query.dart';
import '../models/scrud_result.dart';

/// Page brute retournée par [CollectionStore.query].
@immutable
class StoredQueryPage {
  /// Crée une page de résultats bruts.
  const StoredQueryPage({required this.rows, required this.total});

  /// Lignes de la page courante.
  final List<StoredJsonRow> rows;

  /// Nombre total de lignes satisfaisant la requête avant pagination.
  final int total;
}

/// Interface abstraite d'un moteur de stockage local pour collections JSON.
abstract class CollectionStore {
  /// Initialise la base ou le stockage sous-jacent (création des tables et
  /// index si nécessaire). Doit être idempotent.
  Future<void> init();

  /// Libère les ressources (connexion SQLite, verrous, etc.).
  Future<void> close();

  /// Insère une nouvelle ligne [row].
  ///
  /// Lève `EntityAlreadyExistsException` si `(nomCollection, idEntity)` existe
  /// déjà.
  Future<void> insert(StoredJsonRow row);

  /// Insère ou remplace la ligne [row] identifiée par
  /// `(nomCollection, idEntity)`.
  Future<void> upsert(StoredJsonRow row);

  /// Retourne la ligne correspondant à ([collection], [id]), ou `null` si
  /// absente.
  Future<StoredJsonRow?> findById(String collection, String id);

  /// Met à jour `data_json` pour une ligne existante.
  ///
  /// Retourne `true` si la ligne existait et a été mise à jour, `false` sinon.
  Future<bool> update(StoredJsonRow row);

  /// Supprime la ligne ([collection], [id]).
  ///
  /// Retourne `true` si une ligne a été supprimée, `false` sinon.
  Future<bool> delete(String collection, String id);

  /// Exécute une recherche filtrée, triée et paginée sur [collection].
  Future<StoredQueryPage> query(String collection, ScrudSearchRequest request);

  /// Retourne le nombre total d'entités stockées dans [collection].
  Future<int> count(String collection);

  /// Retourne la liste triée des noms de collections présentes dans le store.
  Future<List<String>> listCollections();

  /// Supprime toutes les entités de [collection] et retourne le nombre de lignes
  /// supprimées.
  Future<int> clearCollection(String collection);
}
