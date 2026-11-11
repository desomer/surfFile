/// Action de comportement publiant un événement interne sur le bus d'événements ([EmitEventAction]).
///
/// Transmet l'identifiant d'événement, les métadonnées automatiques de l'instance
/// déclenchante ([BehaviorExecutionData]) et une charge utile personnalisée au
/// [SuperEventBus] fourni par [SuperApp].
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../services/events/super_event_bus.dart';
import '../../super_app.dart';
import '../component_behavior.dart';

/// Publie un evenement interne avec les donnees automatiques et personnalisees.
@immutable
class EmitEventAction extends BehaviorAction {
  EmitEventAction({
    required this.eventId,
    Map<String, Object?> custom = const {},
  }) : custom = immutableEventJson(custom) {
    if (eventId.trim().isEmpty || eventId != eventId.trim()) {
      throw ArgumentError.value(
        eventId,
        'eventId',
        'Expected a non-empty ID without surrounding whitespace.',
      );
    }
  }

  final String eventId;
  final Map<String, Object?> custom;

  @override
  String get type => 'emitEvent';
  @override
  String get label => 'Emettre un evenement';
  @override
  String get description => eventId;
  @override
  IconData get icon => Icons.bolt;

  @override
  Future<void> execute(BuildContext context) async {
    throw StateError('EmitEventAction requires component execution data.');
  }

  @override
  Future<void> executeWithData(
    BuildContext context,
    BehaviorExecutionData data,
  ) async {
    final bus = SuperApp.maybeOf(context)?.eventBus;
    if (bus == null) {
      throw StateError('EmitEventAction requires SuperApp.eventBus.');
    }
    bus.emit(
      SuperComponentEvent(
        eventId: eventId,
        componentId: data.componentId,
        componentType: data.componentType,
        trigger: data.trigger.name,
        data: data.data,
        custom: custom,
      ),
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'eventId': eventId,
    'custom': custom,
  };

  factory EmitEventAction.fromJson(Map<String, dynamic> json) =>
      EmitEventAction(
        eventId: json['eventId'] as String,
        custom: (json['custom'] as Map<String, dynamic>?) ?? const {},
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmitEventAction &&
          other.eventId == eventId &&
          jsonEncode(other.custom) == jsonEncode(custom);

  @override
  int get hashCode => Object.hash(eventId, jsonEncode(custom));
}
