/// Contexte de ligne des listes JSON et résolution des jokers `[?]`.
///
/// Chaque ligne d'une `SuperListView` est enveloppée dans un [JsonListScope]
/// qui transmet à ses descendants :
///
/// * le repository de la liste, hérité par les liaisons sans repository
///   explicite (option « Hérité de la liste englobante ») ;
/// * les indices des lignes englobantes, liste externe d'abord, qui
///   remplissent les `[?]` des chemins.
///
/// Les `[?]` qu'aucune liste englobante ne fournit prennent la ligne
/// sélectionnée (clic) du tableau correspondant, mémorisée dans le
/// `JsonRepositoryBinding` du repository : c'est ainsi qu'un composant placé
/// hors de la liste affiche la ligne sélectionnée (maître / détail).
///
/// ## Utilisation dans un composant lié
///
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   final scope = JsonListScope.maybeOf(context);
///   final store = JsonRepositoryScope.maybeOf(context);
///   final resolved = JsonListScope.resolveSelected(binding, scope, store);
///   // resolved.binding : liaison concrète, ou null sans ligne sélectionnée.
///   // resolved.arrays : sélections à écouter pour se rafraîchir.
///   ...
/// }
/// ```
///
/// Un composant qui dépend d'une sélection doit écouter chaque
/// `JsonArrayBinding` de `arrays` et se résoudre à nouveau à chaque
/// notification (voir `SuperValue` et `SuperListView`).
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/json_text_binding.dart';
import 'json_repository_binding.dart';
import 'json_repository_store.dart';

/// Résultat de [JsonListScope.resolveSelected].
///
/// * `binding` : liaison concrète, ou `null` quand un `[?]` n'a pas de ligne
///   sélectionnée (le composant doit alors rester vide) ;
/// * `indices` : valeurs des `[?]` déjà résolus, liste externe d'abord ;
/// * `arrays` : sélections de tableaux dont dépend le résultat, à écouter.
///   Vide quand les listes englobantes fournissent tous les indices.
typedef JsonSelectedBinding = ({
  JsonTextBinding? binding,
  List<int> indices,
  List<JsonArrayBinding> arrays,
});

/// Contexte de la ligne courante des `SuperListView` englobantes.
///
/// Placé par `SuperListView` autour de chaque ligne ; une liste imbriquée
/// ajoute son indice à la suite de ceux de son parent. Les liaisons
/// descendantes héritent de [repositoryId] et reçoivent [indices] dans leurs
/// `[?]`.
///
/// Exemple : dans la 2e commande du 1er client, [indices] vaut `[0, 1]` et
/// `clients[?].commandes[?].ref` se résout en `clients[0].commandes[1].ref`.
class JsonListScope extends InheritedWidget {
  const JsonListScope({
    required this.repositoryId,
    required this.indices,
    this.selected = false,
    this.placeholder = false,
    required super.child,
    super.key,
  });

  /// Repository de la liste, ou `null` s'il n'est pas encore connu.
  final String? repositoryId;

  /// Indices des lignes englobantes, liste externe d'abord.
  final List<int> indices;

  /// Whether the nearest row is selected in its list.
  final bool selected;

  /// Ligne de gabarit affichée sans donnée (tableau vide ou illisible, en
  /// mode édition) : les composants ne doivent ni lire ni écrire.
  final bool placeholder;

  /// Contexte de la ligne englobante la plus proche, ou `null` hors liste.
  /// Le widget appelant est reconstruit quand le contexte change.
  static JsonListScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<JsonListScope>();

  /// Liaison concrète de [binding] dans la ligne [scope], sans utiliser les
  /// sélections.
  ///
  /// Lève une [FormatException] si le repository hérité manque ou si
  /// [binding] a plus de `[?]` que de listes englobantes.
  static JsonTextBinding resolve(
    JsonTextBinding binding,
    JsonListScope? scope,
  ) => binding.resolve(
    repositoryId: scope?.repositoryId,
    indices: scope?.indices ?? const [],
  );

  /// Comme [resolve], mais chaque `[?]` au-delà des listes englobantes prend
  /// la ligne sélectionnée de son tableau dans [store].
  ///
  /// Par exemple, hors de toute liste, `clients[?].commandes[?].ref` lit la
  /// commande sélectionnée du client sélectionné. Une sélection n'est
  /// utilisée que si ses lignes parentes correspondent aux indices déjà
  /// résolus : la commande sélectionnée d'un autre client est ignorée et
  /// `binding` vaut alors `null`.
  ///
  /// Lève une [FormatException] si le chemin est invalide, si le repository
  /// hérité manque ou si [store] est `null` alors qu'une sélection est
  /// nécessaire.
  static JsonSelectedBinding resolveSelected(
    JsonTextBinding binding,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final path = JsonAttributePath(binding.path);
    final count = path.wildcardCount;
    final indices = [...?scope?.indices];
    if (count <= indices.length) {
      return (
        binding: resolve(binding, scope),
        indices: indices.take(count).toList(),
        arrays: const [],
      );
    }
    binding.validate();
    final repositoryId = binding.repositoryId ?? scope?.repositoryId;
    if (repositoryId == null) {
      // Lève l'erreur « repository hérité indisponible ».
      return (
        binding: binding.resolve(indices: List.filled(count, 0)),
        indices: const [],
        arrays: const [],
      );
    }
    if (store == null) {
      throw const FormatException('Service de repositories indisponible.');
    }
    final repository = store.bindingOf(repositoryId);
    final templates = path.arrayTemplates;
    final arrays = <JsonArrayBinding>[];
    for (var i = indices.length; i < count; i++) {
      final array = repository.array(templates[i]);
      arrays.add(array);
      final index = array.indexFor(indices);
      if (index == null) {
        return (binding: null, indices: indices, arrays: arrays);
      }
      indices.add(index);
    }
    return (
      binding: binding.resolve(repositoryId: repositoryId, indices: indices),
      indices: indices,
      arrays: arrays,
    );
  }

  @override
  bool updateShouldNotify(JsonListScope oldWidget) =>
      repositoryId != oldWidget.repositoryId ||
      selected != oldWidget.selected ||
      placeholder != oldWidget.placeholder ||
      !listEquals(indices, oldWidget.indices);
}
