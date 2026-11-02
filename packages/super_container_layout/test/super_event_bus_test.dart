import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  SuperComponentEvent event(String id, int value) => SuperComponentEvent(
    eventId: id,
    componentId: 'source',
    componentType: 'value',
    trigger: 'click',
    data: {'value': value},
  );

  test('bus filters exact IDs, broadcasts in order, and cancels', () async {
    final bus = SuperEventBus();
    final first = <SuperComponentEvent>[];
    final second = <SuperComponentEvent>[];
    final subscription = bus.on('changed').listen(first.add);
    final other = bus.on('changed').listen(second.add);
    bus.emit(event('changed.child', 0));
    bus.emit(event('changed', 1));
    bus.emit(event('changed', 2));
    expect(first, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(first.map((e) => e.data['value']), [1, 2]);
    expect(second, first);
    await subscription.cancel();
    bus.emit(event('changed', 3));
    await Future<void>.delayed(Duration.zero);
    expect(first, hasLength(2));
    expect(second, hasLength(3));
    await other.cancel();
    await bus.close();
    expect(() => bus.on('changed'), throwsStateError);
    expect(() => bus.emit(event('changed', 4)), throwsStateError);
  });

  test('bus has no replay and validates IDs', () async {
    final bus = SuperEventBus();
    bus.emit(event('changed', 0));
    final received = <SuperComponentEvent>[];
    final subscription = bus.on('changed').listen(received.add);
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);
    for (final id in ['', ' ', ' changed', 'changed ']) {
      expect(() => bus.on(id), throwsArgumentError);
      expect(() => event(id, 1), throwsArgumentError);
      expect(() => EmitEventAction(eventId: id), throwsArgumentError);
    }
    await subscription.cancel();
    await bus.close();
  });

  test('event and action deeply freeze JSON and compare structurally', () {
    final source = <String, Object?>{
      'nested': <Object?>[
        <String, Object?>{'z': 1, 'a': false},
      ],
    };
    final action = EmitEventAction(eventId: 'changed', custom: source);
    final snapshot = SuperComponentEvent(
      eventId: 'changed',
      componentId: 'source',
      componentType: 'value',
      trigger: 'doubleClick',
      data: source,
      custom: source,
    );
    (source['nested']! as List).clear();
    expect(snapshot.data['nested'], hasLength(1));
    expect(action.custom['nested'], hasLength(1));
    expect(() => snapshot.data['new'] = 1, throwsUnsupportedError);
    expect(
      () => (snapshot.custom['nested']! as List).clear(),
      throwsUnsupportedError,
    );
    final nested = (action.custom['nested']! as List).single as Map;
    expect(() => nested['z'] = 2, throwsUnsupportedError);
    final equal = EmitEventAction(
      eventId: 'changed',
      custom: {
        'nested': [
          {'a': false, 'z': 1},
        ],
      },
    );
    expect(action, equal);
    expect(action.hashCode, equal.hashCode);
    expect(jsonDecode(jsonEncode(snapshot.toJson()))['trigger'], 'doubleClick');
    expect(
      () => EmitEventAction(eventId: 'e', custom: {'bad': Object()}),
      throwsArgumentError,
    );
    expect(
      () => EmitEventAction(eventId: 'e', custom: {'bad': double.nan}),
      throwsArgumentError,
    );
  });

  test('event behaviours survive appearance persistence', () {
    final behavior = ComponentBehavior(
      id: 'b',
      trigger: BehaviorTrigger.doubleClick,
      action: EmitEventAction(
        eventId: 'changed',
        custom: {
          'nested': [1, true, null],
        },
      ),
    );
    final initial = Appearance(
      behaviors: {
        'source': [behavior],
      },
    );
    const codec = AppearanceCodec();
    final restored = codec.decode(codec.encode(initial));
    expect(restored.behaviorsFor('source'), [behavior]);
    expect(
      BehaviorActionCatalog.decode(behavior.action.toJson()),
      behavior.action,
    );
    expect(BehaviorCatalog.items, contains(BehaviorCatalog.emitEvent));
  });
}
