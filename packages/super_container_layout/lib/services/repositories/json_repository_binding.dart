/// État d'exécution (non persisté) des tableaux d'un repository JSON.
///
/// Pour chaque repository, `JsonRepositoryStore.bindingOf(id)` fournit un
/// [JsonRepositoryBinding] qui contient un [JsonArrayBinding] par *chemin
/// modèle* de tableau, par exemple `clients` ou `clients[?].commandes`.
/// Chaque [JsonArrayBinding] mémorise :
///
/// * la **ligne sélectionnée** du tableau, avec les indices des lignes
///   parentes ;
/// * les **composants liés**, qui sont ses écouteurs (`ChangeNotifier`) et
///   sont rafraîchis à chaque changement de sélection.
///
/// ## Fonctionnement
///
/// * un clic sur une ligne de `SuperListView` appelle
///   [JsonArrayBinding.select] ;
/// * toutes les listes sur le même chemin modèle surlignent cette ligne ;
/// * les composants dont un `[?]` n'est fourni par aucune liste englobante
///   (par exemple un `SuperValue` sur `clients[?].nom` hors de la liste)
///   lisent la ligne sélectionnée via `JsonListScope.resolveSelected`.
///
/// Il n'y a qu'une sélection par chemin modèle : sélectionner une commande du
/// client 2 remplace celle du client 0 pour `clients[?].commandes`.
///
/// Les sélections ne sont pas enregistrées : elles disparaissent au
/// redémarrage et avec le `JsonRepositoryStore`.
///
/// ```dart
/// final clients = store.bindingOf(repositoryId).array('clients');
/// clients.select(const [], 1);           // sélectionne le 2e client
/// clients.indexFor(const []);            // 1
/// store.bindingOf(repositoryId)
///     .array('clients[?].commandes')
///     .select(const [1], 0);             // 1re commande du 2e client
/// clients.addListener(rafraichir);       // composant lié
/// ```
library;

import 'package:flutter/foundation.dart';

/// Sélection d'un tableau d'un repository, partagée par toutes les instances
/// de son chemin modèle (par exemple `clients[?].commandes` pour les
/// commandes de chaque client).
///
/// Les composants liés s'abonnent avec [addListener] et sont notifiés quand
/// la sélection change.
class JsonArrayBinding extends ChangeNotifier {
  JsonArrayBinding(this.template);

  /// Chemin modèle canonique du tableau, par exemple `clients[?].commandes`.
  final String template;

  List<int>? _selection;
  String? _selectedNodePath;

  /// Valeurs des `[?]` du chemin modèle (lignes parentes), puis indice de la
  /// ligne sélectionnée ; `null` sans sélection.
  ///
  /// Par exemple `[2, 1]` pour la 2e commande du 3e client.
  List<int>? get selection => _selection;

  /// Chemin concret du nœud sélectionné lorsqu'il s'agit d'un arbre
  /// (par exemple `nodes[0].children[1]`), ou `null` pour une sélection
  /// de liste standard.
  String? get selectedNodePath => _selectedNodePath;

  /// Indice sélectionné dans l'instance du tableau désignée par [parents],
  /// ou `null` si la sélection appartient à une autre instance (autre client)
  /// ou s'il n'y a pas de sélection.
  int? indexFor(List<int> parents) {
    final selection = _selection;
    if (selection == null ||
        selection.length != parents.length + 1 ||
        !listEquals(selection.sublist(0, parents.length), parents)) {
      return null;
    }
    return selection.last;
  }

  /// Chemin concret du nœud d'arbre sélectionné dans l'instance [parents],
  /// ou `null`.
  String? nodePathFor(List<int> parents) =>
      indexFor(parents) == null ? null : _selectedNodePath;

  /// Sélectionne la ligne [index] de l'instance [parents] (et optionnellement
  /// le chemin concret [nodePath] d'un nœud d'arbre) et notifie les composants
  /// liés si la sélection change.
  void select(List<int> parents, int index, {String? nodePath}) {
    if (index < 0) throw RangeError.value(index, 'index');
    _set([...parents, index], nodePath: nodePath);
  }

  /// Efface la sélection et notifie les composants liés.
  void clear() => _set(null);

  /// Indique si au moins un composant écoute ce tableau.
  bool get isBound => hasListeners;

  void _set(List<int>? selection, {String? nodePath}) {
    if (listEquals(_selection, selection) && _selectedNodePath == nodePath) {
      return;
    }
    _selection = selection == null ? null : List.unmodifiable(selection);
    _selectedNodePath = selection == null ? null : nodePath;
    notifyListeners();
  }
}

/// Sélections non persistées des tableaux d'un repository, par chemin modèle.
///
/// Créé et détruit par `JsonRepositoryStore` ; ne pas appeler [dispose]
/// soi-même.
class JsonRepositoryBinding {
  JsonRepositoryBinding(this.repositoryId);

  /// ID du repository concerné.
  final String repositoryId;
  final _arrays = <String, JsonArrayBinding>{};

  /// Tableaux déjà utilisés.
  Iterable<JsonArrayBinding> get arrays => _arrays.values;

  /// Indique si au moins un tableau de ce repository a un composant lié actif.
  bool get isBound => _arrays.values.any((array) => array.isBound);

  /// Sélection du tableau [template] (chemin modèle canonique, voir
  /// `JsonAttributePath.toString`), créée au premier accès ; la même instance
  /// est toujours retournée.
  JsonArrayBinding array(String template) =>
      _arrays.putIfAbsent(template, () => JsonArrayBinding(template));

  /// Garde les sélections valides après la suppression de l'élément [index]
  /// de l'instance [parents] du tableau [template].
  ///
  /// Pour ce tableau et ses sous-tableaux (`template[?]…`) :
  /// * une sélection dans l'élément supprimé est effacée ;
  /// * une sélection dans un élément suivant est décalée de un ;
  /// * les autres instances (autres parents) ne changent pas.
  void removed(String template, List<int> parents, int index) {
    final nested = '$template[?]';
    for (final array in _arrays.values.toList()) {
      final selection = array.selection;
      if (selection == null) continue;
      final ownArray = array.template == template;
      if (!ownArray &&
          !(array.template.startsWith(nested) &&
              (array.template.length == nested.length ||
                  array.template[nested.length] == '.' ||
                  array.template[nested.length] == '['))) {
        continue;
      }
      if (selection.length <= parents.length ||
          !listEquals(selection.sublist(0, parents.length), parents)) {
        continue;
      }
      final element = selection[parents.length];
      if (element < index) continue;
      if (element == index) {
        array.clear();
      } else {
        array._set([...selection]..[parents.length] = element - 1);
      }
    }
  }

  /// Libère toutes les sélections.
  void dispose() {
    for (final array in _arrays.values) {
      array.dispose();
    }
    _arrays.clear();
  }
}
