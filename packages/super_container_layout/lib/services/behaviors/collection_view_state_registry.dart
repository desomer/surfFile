/// Registre runtime des états impératifs de tri et de filtrage des collections
/// ([CollectionViewStateRegistry]) pour `SuperListView` et `SuperTable`.
///
/// Stocke en mémoire, par identifiant technique de composant (`componentId`),
/// les critères de tri ([SortCollectionAction]) et les prédicats de filtre
/// ([FilterCollectionAction]) déclenchés par des comportements impératifs,
/// et notifie uniquement les collections abonnées à cet identifiant.
library;

import 'package:flutter/foundation.dart' show VoidCallback, immutable, listEquals, mapEquals;

import '../../models/behaviours/behavior_validator.dart';
import '../../models/behaviours/filter_collection_action.dart';
import '../../models/behaviours/sort_collection_action.dart';

/// État runtime impératif (tri + filtres actifs) d'un `SuperListView` ou `SuperTable`.
@immutable
class CollectionRuntimeViewState {
  /// Crée un état runtime de vue de collection.
  CollectionRuntimeViewState({
    List<CollectionSortCriterion>? sortCriteria,
    Map<String, BehaviorValidator> filters = const {},
  }) : sortCriteria = sortCriteria == null
           ? null
           : List<CollectionSortCriterion>.unmodifiable(sortCriteria),
       filters = Map<String, BehaviorValidator>.unmodifiable(filters);

  /// État vide (aucun tri ni filtre impératif actif).
  static final CollectionRuntimeViewState empty = CollectionRuntimeViewState();

  /// Critères de tri impératifs actifs (`null` signifie aucun override impératif).
  final List<CollectionSortCriterion>? sortCriteria;

  /// Prédicats de filtres impératifs actifs, indexés par `filterKey`.
  final Map<String, BehaviorValidator> filters;

  /// Indique si aucun tri ni filtre impératif n'est actif.
  bool get isEmpty =>
      (sortCriteria == null || sortCriteria!.isEmpty) && filters.isEmpty;

  /// Retourne une copie modifiée de cet état.
  CollectionRuntimeViewState copyWith({
    List<CollectionSortCriterion>? sortCriteria,
    bool clearSortCriteria = false,
    Map<String, BehaviorValidator>? filters,
  }) => CollectionRuntimeViewState(
    sortCriteria: clearSortCriteria
        ? null
        : (sortCriteria ?? this.sortCriteria),
    filters: filters ?? this.filters,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectionRuntimeViewState &&
          listEquals(other.sortCriteria, sortCriteria) &&
          mapEquals(other.filters, filters);

  @override
  int get hashCode => Object.hash(
    sortCriteria == null ? null : Object.hashAll(sortCriteria!),
    Object.hashAllUnordered(
      filters.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// Registre global des tris et filtres impératifs appliqués aux collections.
class CollectionViewStateRegistry {
  /// Crée une instance indépendante (utile pour isoler les tests).
  CollectionViewStateRegistry();

  /// Instance singleton partagée dans l'application.
  static final CollectionViewStateRegistry instance =
      CollectionViewStateRegistry();

  final Map<String, CollectionRuntimeViewState> _states = {};
  final Map<String, Set<VoidCallback>> _listeners = {};

  /// Retourne l'état runtime courant pour [componentId].
  CollectionRuntimeViewState stateFor(String componentId) =>
      _states[componentId] ?? CollectionRuntimeViewState.empty;

  /// Abonne [listener] aux modifications de tri/filtre de [componentId].
  void addListenerFor(String componentId, VoidCallback listener) {
    if (componentId.isEmpty) return;
    _listeners.putIfAbsent(componentId, () => <VoidCallback>{}).add(listener);
  }

  /// Désabonne [listener] pour [componentId].
  void removeListenerFor(String componentId, VoidCallback listener) {
    final listeners = _listeners[componentId];
    if (listeners == null) return;
    listeners.remove(listener);
    if (listeners.isEmpty) {
      _listeners.remove(componentId);
    }
  }

  /// Applique une [SortCollectionAction] impérative sur [componentId].
  void applySort(String componentId, SortCollectionAction action) {
    final id = componentId.trim();
    if (id.isEmpty) return;
    final current = stateFor(id);

    switch (action.mode) {
      case CollectionSortMode.clear:
        _updateState(id, current.copyWith(clearSortCriteria: true));
      case CollectionSortMode.set:
        final resolved = _resolveCriteria(
          action.criteria,
          existing: current.sortCriteria ?? const [],
        );
        _updateState(id, current.copyWith(sortCriteria: resolved));
      case CollectionSortMode.add:
        final next = List<CollectionSortCriterion>.of(
          current.sortCriteria ?? const [],
        );
        for (final criterion in action.criteria) {
          final resolved = _resolveSingleCriterion(criterion, existing: next);
          final existingIndex = next.indexWhere(
            (item) => item.path.trim() == resolved.path.trim(),
          );
          if (existingIndex >= 0) {
            next[existingIndex] = resolved;
          } else {
            next.add(resolved);
          }
        }
        _updateState(id, current.copyWith(sortCriteria: next));
    }
  }

  /// Applique une [FilterCollectionAction] impérative sur [componentId].
  void applyFilter(
    String componentId,
    FilterCollectionAction action, {
    String defaultKey = 'default',
  }) {
    final id = componentId.trim();
    if (id.isEmpty) return;
    final current = stateFor(id);
    final effectiveKey =
        action.filterKey != null && action.filterKey!.trim().isNotEmpty
        ? action.filterKey!.trim()
        : (defaultKey.trim().isEmpty ? 'default' : defaultKey.trim());

    switch (action.mode) {
      case CollectionFilterMode.clearAll:
        _updateState(id, current.copyWith(filters: const {}));
      case CollectionFilterMode.clear:
        if (!current.filters.containsKey(effectiveKey)) return;
        final next = Map<String, BehaviorValidator>.of(current.filters)
          ..remove(effectiveKey);
        _updateState(id, current.copyWith(filters: next));
      case CollectionFilterMode.apply:
        final predicate = action.predicate;
        if (predicate == null) return;
        final next = Map<String, BehaviorValidator>.of(current.filters)
          ..[effectiveKey] = predicate;
        _updateState(id, current.copyWith(filters: next));
      case CollectionFilterMode.toggle:
        final predicate = action.predicate;
        if (predicate == null) return;
        final next = Map<String, BehaviorValidator>.of(current.filters);
        if (next[effectiveKey] == predicate) {
          next.remove(effectiveKey);
        } else {
          next[effectiveKey] = predicate;
        }
        _updateState(id, current.copyWith(filters: next));
    }
  }

  /// Efface l'état runtime de [componentId] (ou de toutes les collections si `null`).
  void clear([String? componentId]) {
    if (componentId != null) {
      final id = componentId.trim();
      if (_states.remove(id) != null) {
        _notify(id);
      }
      return;
    }
    final impacted = _states.keys.toList();
    _states.clear();
    for (final id in impacted) {
      _notify(id);
    }
  }

  List<CollectionSortCriterion> _resolveCriteria(
    List<CollectionSortCriterion> incoming, {
    required List<CollectionSortCriterion> existing,
  }) => [
    for (final criterion in incoming)
      _resolveSingleCriterion(criterion, existing: existing),
  ];

  CollectionSortCriterion _resolveSingleCriterion(
    CollectionSortCriterion criterion, {
    required List<CollectionSortCriterion> existing,
  }) {
    if (criterion.direction != CollectionSortDirection.toggle) {
      return criterion;
    }
    final normalizedPath = criterion.path.trim();
    final previous = existing
        .where((item) => item.path.trim() == normalizedPath)
        .firstOrNull;
    final nextDirection =
        previous != null && previous.direction == CollectionSortDirection.asc
        ? CollectionSortDirection.desc
        : CollectionSortDirection.asc;
    return criterion.copyWith(direction: nextDirection);
  }

  void _updateState(String componentId, CollectionRuntimeViewState next) {
    final previous = stateFor(componentId);
    if (previous == next) return;
    if (next.isEmpty) {
      _states.remove(componentId);
    } else {
      _states[componentId] = next;
    }
    _notify(componentId);
  }

  void _notify(String componentId) {
    final listeners = _listeners[componentId];
    if (listeners == null || listeners.isEmpty) return;
    for (final listener in List<VoidCallback>.of(listeners)) {
      listener();
    }
  }
}
