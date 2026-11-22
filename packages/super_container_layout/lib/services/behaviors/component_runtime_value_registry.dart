/// Registre runtime des valeurs et états de validation des composants montés
/// ([ComponentRuntimeValueRegistry]).
///
/// Permet à [BehaviorValidatorEvaluator] de lire la valeur courante et la
/// validité native d'un composant (`self` ou `targetComponentId`) en respectant
/// en priorité la portée de ligne [JsonListScope] courante, puis les instances
/// globales montées.
library;

import 'dart:async' show scheduleMicrotask;

import 'package:flutter/foundation.dart' show VoidCallback, immutable;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;

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
  final Map<String, Set<VoidCallback>> _listeners =
      <String, Set<VoidCallback>>{};
  final Set<String> _pendingNotifications = <String>{};

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

  /// Abonne [listener] aux changements de valeur ou d'enregistrement de [componentId].
  void addComponentListener(String componentId, VoidCallback listener) {
    final id = componentId.trim();
    if (id.isEmpty) return;
    _listeners.putIfAbsent(id, () => <VoidCallback>{}).add(listener);
  }

  /// Désabonne [listener] pour [componentId].
  void removeComponentListener(String componentId, VoidCallback listener) {
    final id = componentId.trim();
    final set = _listeners[id];
    if (set == null) return;
    set.remove(listener);
    if (set.isEmpty) {
      _listeners.remove(id);
    }
  }

  /// Notifie les écouteurs abonnés à [componentId] que sa valeur runtime a changé.
  ///
  /// Si l'appel survient pendant une phase de construction Flutter, la notification
  /// est différée dans une microtask afin d'éviter un `setState` pendant `build`.
  void notifyValueChanged(String componentId) {
    final id = componentId.trim();
    if (id.isEmpty) return;
    final listeners = _listeners[id];
    if (listeners == null || listeners.isEmpty) return;
    if (_isInBuildPhase) {
      _scheduleDeferredNotification(id);
      return;
    }
    for (final listener in List<VoidCallback>.of(listeners)) {
      listener();
    }
  }

  bool get _isInBuildPhase {
    try {
      return SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks;
    } catch (_) {
      return false;
    }
  }

  void _scheduleDeferredNotification(String componentId) {
    if (!_listeners.containsKey(componentId)) return;
    if (!_pendingNotifications.add(componentId)) return;
    scheduleMicrotask(() {
      _pendingNotifications.remove(componentId);
      final listeners = _listeners[componentId];
      if (listeners == null || listeners.isEmpty) return;
      for (final listener in List<VoidCallback>.of(listeners)) {
        listener();
      }
    });
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
    if (previous != null && previous.componentId != entry.componentId) {
      _scheduleDeferredNotification(previous.componentId);
    }
    _scheduleDeferredNotification(entry.componentId);
  }

  /// Supprime l'entrée associée à [token] lors du démontage du composant.
  void unregister(Object token) {
    final existing = _byToken.remove(token);
    if (existing != null) {
      _removeFromLookup(existing);
      _scheduleDeferredNotification(existing.componentId);
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
    _listeners.clear();
    _pendingNotifications.clear();
  }
}
