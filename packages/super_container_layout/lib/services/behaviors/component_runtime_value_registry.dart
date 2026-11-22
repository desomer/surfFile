/// Registre runtime des valeurs et états de validation des composants montés
/// ([ComponentRuntimeValueRegistry]).
///
/// Permet à [BehaviorValidatorEvaluator] de lire la valeur courante et la
/// validité native d'un composant (`self` ou `targetComponentId`) en respectant
/// en priorité la portée de ligne [JsonListScope] courante, puis les instances
/// globales montées.
library;

import 'package:flutter/foundation.dart' show immutable;

import '../repositories/json_list_scope.dart';

/// Entrée décrivant un composant monté capable d'exposer sa valeur runtime
/// et, facultativement, son état de validation native.
@immutable
class ComponentRuntimeValueEntry {
  /// Crée une entrée d'index runtime pour un composant monté.
  const ComponentRuntimeValueEntry({
    required this.token,
    required this.componentId,
    required this.componentType,
    this.listScopeKey,
    required this.readValue,
    this.readIsValid,
  });

  /// Jeton unique identifiant l'instance de `State` propriétaire.
  final Object token;

  /// Identifiant technique du composant (`effectiveComponentId`).
  final String componentId;

  /// Type d'événement / composant (ex. `'value'`, `'listView'`, `'action'`).
  final String componentType;

  /// Clé déterministe de la portée [JsonListScope] englobante, ou `null` hors liste.
  final String? listScopeKey;

  /// Lecteur paresseux de la valeur runtime courante du composant.
  final Object? Function() readValue;

  /// Lecteur paresseux de la validité native du composant (`true` si valide),
  /// ou `null` si le composant ne déclare pas de règles de validation propres.
  final bool Function()? readIsValid;
}

/// Registre léger des valeurs runtime exposées par les composants montés.
class ComponentRuntimeValueRegistry {
  /// Crée une instance indépendante (utile notamment pour isoler des tests).
  ComponentRuntimeValueRegistry();

  /// Instance singleton partagée dans l'application.
  static final ComponentRuntimeValueRegistry instance =
      ComponentRuntimeValueRegistry();

  final Map<Object, ComponentRuntimeValueEntry> _byToken =
      <Object, ComponentRuntimeValueEntry>{};
  final Map<String, List<ComponentRuntimeValueEntry>> _byComponentId =
      <String, List<ComponentRuntimeValueEntry>>{};

  /// Calcule une clé déterministe identifiant la ligne courante d'un [JsonListScope],
  /// ou `null` lorsque le composant n'est pas dans une portée de liste/arbre.
  static String? scopeKeyOf(JsonListScope? scope) {
    if (scope == null) return null;
    final repo = scope.repositoryId ?? '';
    final nodePath = scope.nodePath ?? '';
    if (repo.isEmpty && scope.indices.isEmpty && nodePath.isEmpty) {
      return null;
    }
    final indices = scope.indices.join(',');
    return '$repo|$indices|$nodePath';
  }

  /// Enregistre ou met à jour l'entrée associée à [entry.token].
  void register(ComponentRuntimeValueEntry entry) {
    final previous = _byToken[entry.token];
    if (previous != null) {
      _removeFromLookup(previous);
    }
    _byToken[entry.token] = entry;
    _byComponentId
        .putIfAbsent(entry.componentId, () => <ComponentRuntimeValueEntry>[])
        .add(entry);
  }

  /// Supprime l'entrée associée à [token] lors du démontage du composant.
  void unregister(Object token) {
    final existing = _byToken.remove(token);
    if (existing != null) {
      _removeFromLookup(existing);
    }
  }

  void _removeFromLookup(ComponentRuntimeValueEntry entry) {
    final entries = _byComponentId[entry.componentId];
    if (entries == null) return;
    entries.removeWhere((item) => identical(item.token, entry.token));
    if (entries.isEmpty) {
      _byComponentId.remove(entry.componentId);
    }
  }

  /// Résout la meilleure entrée montée pour [componentId].
  ///
  /// Ordre de priorité :
  /// 1. Entrée partageant exactement [preferredScopeKey] (même ligne de liste/arbre) ;
  /// 2. Entrée globale montée hors liste (`listScopeKey == null`).
  ComponentRuntimeValueEntry? resolve(
    String componentId, {
    String? preferredScopeKey,
  }) {
    final entries = _byComponentId[componentId];
    if (entries == null || entries.isEmpty) return null;

    if (preferredScopeKey != null) {
      for (var i = entries.length - 1; i >= 0; i--) {
        if (entries[i].listScopeKey == preferredScopeKey) {
          return entries[i];
        }
      }
    }

    for (var i = entries.length - 1; i >= 0; i--) {
      if (entries[i].listScopeKey == null) {
        return entries[i];
      }
    }

    return null;
  }

  /// Retourne toutes les entrées actuellement enregistrées pour [componentId].
  List<ComponentRuntimeValueEntry> entriesFor(String componentId) =>
      List<ComponentRuntimeValueEntry>.unmodifiable(
        _byComponentId[componentId] ?? const [],
      );

  /// Vide toutes les entrées enregistrées (utile pour isoler les tests).
  void clear() {
    _byToken.clear();
    _byComponentId.clear();
  }
}
