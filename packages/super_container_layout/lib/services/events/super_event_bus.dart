/// Bus applicatif et instantanes JSON des evenements de composants.
library;

import 'dart:async';
import 'dart:convert';

/// Copie, valide et protege recursivement un objet JSON.
Map<String, Object?> immutableEventJson(Map<String, Object?> value) {
  Object? freeze(Object? item) {
    if (item == null || item is String || item is bool || item is int) {
      return item;
    }
    if (item is double && item.isFinite) return item;
    if (item is List) return List<Object?>.unmodifiable(item.map(freeze));
    if (item is Map) {
      if (item.keys.any((key) => key is! String)) {
        throw ArgumentError('Event JSON keys must be strings.');
      }
      final keys = item.keys.cast<String>().toList()..sort();
      return Map<String, Object?>.unmodifiable({
        for (final key in keys) key: freeze(item[key]),
      });
    }
    throw ArgumentError.value(item, 'value', 'Expected a JSON value.');
  }

  return freeze(value)! as Map<String, Object?>;
}

/// Evenement immutable emis par une instance de composant.
class SuperComponentEvent {
  SuperComponentEvent({
    required this.eventId,
    required this.componentId,
    required this.componentType,
    required this.trigger,
    Map<String, Object?> data = const {},
    Map<String, Object?> custom = const {},
  }) : data = immutableEventJson(data),
       custom = immutableEventJson(custom) {
    if (eventId.trim().isEmpty || eventId != eventId.trim()) {
      throw ArgumentError.value(
        eventId,
        'eventId',
        'Expected a non-empty ID without surrounding whitespace.',
      );
    }
  }

  final String eventId;
  final String componentId;
  final String componentType;
  final String trigger;
  final Map<String, Object?> data;
  final Map<String, Object?> custom;

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'componentId': componentId,
    'componentType': componentType,
    'trigger': trigger,
    'data': data,
    'custom': custom,
  };

  @override
  String toString() => jsonEncode(toJson());
}

/// Bus broadcast asynchrone, sans replay, possede par l'application hote.
class SuperEventBus {
  final _controller = StreamController<SuperComponentEvent>.broadcast();

  /// Ecoute un ID exact. Annuler l'abonnement lors de la destruction du client.
  Stream<SuperComponentEvent> on(String eventId) {
    _checkOpen();
    if (eventId.trim().isEmpty || eventId != eventId.trim()) {
      throw ArgumentError.value(
        eventId,
        'eventId',
        'Expected a non-empty ID without surrounding whitespace.',
      );
    }
    return _controller.stream.where((event) => event.eventId == eventId);
  }

  /// Publie sans attendre les listeners ; leurs erreurs restent explicites.
  void emit(SuperComponentEvent event) {
    _checkOpen();
    _controller.add(event);
  }

  void _checkOpen() {
    if (_controller.isClosed) throw StateError('SuperEventBus is closed.');
  }

  /// Ferme le bus une fois les abonnements de l'application annules.
  Future<void> close() => _controller.close();
}
