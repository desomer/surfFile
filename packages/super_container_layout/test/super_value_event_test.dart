import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SuperEventBus bus;
  late List<SuperComponentEvent> received;
  late StreamSubscription<SuperComponentEvent> subscription;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    bus = SuperEventBus();
    received = [];
    subscription = bus.on('changed').listen(received.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await bus.close();
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<BuildContext> mount(
    WidgetTester tester,
    Widget child, {
    bool doubleClick = false,
    bool enabled = true,
    bool editing = false,
    JsonRepositoryStore? repositories,
    bool injectBus = true,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(child: SizedBox(width: 320, child: child)),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(
        router: router,
        eventBus: injectBus ? bus : null,
        repositoryStore: repositories,
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SuperValue).first);
    final appearance = AppearanceScope.controllerOf(context)!;
    appearance.value = appearance.value.withBehaviors('source', []);
    for (final trigger in [
      BehaviorTrigger.click,
      if (doubleClick) BehaviorTrigger.doubleClick,
    ]) {
      appearance.value = appearance.value.withAddedBehavior(
        'source',
        ComponentBehavior(
          id: trigger.name,
          trigger: trigger,
          enabled: enabled,
          action: EmitEventAction(
            eventId: 'changed',
            custom: {'origin': 'test'},
          ),
        ),
      );
    }
    StyleEditScope.controllerOf(context)!.value = editing;
    await tester.pumpAndSettle();
    return context;
  }

  Future<void> tapAtTime(
    WidgetTester tester,
    Finder target,
    Duration time, {
    Offset? position,
  }) async {
    final gesture = await tester.createGesture();
    await gesture.down(position ?? tester.getCenter(target), timeStamp: time);
    await gesture.up(timeStamp: time + const Duration(milliseconds: 10));
  }

  testWidgets('display emits the full JSON envelope exactly once', (
    tester,
  ) async {
    await mount(
      tester,
      const SuperValue(
        id: 'source',
        config: SuperValueConfig(initialText: 'Alice'),
      ),
    );
    await tester.tap(find.text('Alice'));
    await tester.pump();
    expect(received, hasLength(1));
    expect(received.single.toJson(), {
      'eventId': 'changed',
      'componentId': 'source',
      'componentType': 'value',
      'trigger': 'click',
      'data': {'previousValue': 'Alice', 'value': 'Alice'},
      'custom': {'origin': 'test'},
    });
  });

  for (final scenario in ['active', 'empty', 'disabled', 'editing']) {
    testWidgets('code behaviours override appearance: $scenario', (
      tester,
    ) async {
      final context = await mount(
        tester,
        SuperValue(
          id: 'source',
          config: const SuperValueConfig(initialText: 'Alice'),
          behaviours: [
            if (scenario != 'empty')
              ComponentBehavior(
                id: 'code-click',
                trigger: BehaviorTrigger.click,
                enabled: scenario != 'disabled',
                action: EmitEventAction(
                  eventId: 'changed',
                  custom: {'origin': 'code'},
                ),
              ),
          ],
        ),
        editing: scenario == 'editing',
      );
      await tester.tap(find.text('Alice'));
      await tester.pump();
      if (scenario == 'active') {
        expect(received, hasLength(1));
        expect(received.single.custom, {'origin': 'code'});
        expect(received.single.data, {
          'previousValue': 'Alice',
          'value': 'Alice',
        });
      } else {
        expect(received, isEmpty);
      }
      expect(
        AppearanceScope.of(context).behaviorsFor('source').single.id,
        'click',
      );
    });
  }

  testWidgets('double-click-only action does not emit simple clicks', (
    tester,
  ) async {
    final context = await mount(
      tester,
      const SuperValue(
        id: 'source',
        config: SuperValueConfig(initialText: 'Alice'),
      ),
      doubleClick: true,
    );
    final appearance = AppearanceScope.controllerOf(context)!;
    appearance.value = appearance.value.withRemovedBehavior('source', 'click');
    await tester.pumpAndSettle();
    await tapAtTime(tester, find.text('Alice'), const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(received, isEmpty);
    await tapAtTime(
      tester,
      find.text('Alice'),
      const Duration(milliseconds: 1070),
    );
    await tester.pump();
    expect(received.single.trigger, 'doubleClick');
  });

  testWidgets('bound values reflect the clicked runtime instance', (
    tester,
  ) async {
    const repositoryId = '0123456789abcdef0123456789abcdef';
    final store = JsonRepositoryStore.defaultStore();
    addTearDown(store.dispose);
    store.registerRepository(
      RepositoryImpl(
        id: repositoryId,
        json: {'name': 'Bound Alice'},
        onChanged: (_) {},
      ),
    );
    await mount(
      tester,
      const SuperValue(
        id: 'source',
        config: SuperValueConfig(
          binding: JsonTextBinding(repositoryId: repositoryId, path: 'name'),
        ),
      ),
      repositories: store,
    );
    await tester.tap(find.text('Bound Alice'));
    await tester.pump();
    expect(received.single.data, {
      'previousValue': 'Bound Alice',
      'value': 'Bound Alice',
    });
  });

  testWidgets(
    'event wizard validates JSON, persists trigger and supports undo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final context = await mount(
        tester,
        const SuperValue(
          id: 'source',
          config: SuperValueConfig(initialText: 'Alice'),
        ),
        editing: true,
      );
      final appearance = AppearanceScope.controllerOf(context)!;
      final history = EditorHistoryScope.controllerOf(context)!;
      history.clear();
      unawaited(
        showComponentBehaviorWizard(
          context: context,
          targets: const [BehaviorTargetElement(id: 'source', label: 'Source')],
        ),
      );
      await tester.pumpAndSettle();
      final next = find.byKey(const ValueKey('behavior-add-next'));
      await tester.tap(next);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('behavior-catalog-emit_event')),
      );
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('behavior-event-id')),
        'node.changed',
      );
      final custom = find.byKey(const ValueKey('behavior-event-custom'));
      await tester.enterText(custom, '[]');
      await tester.pump();
      expect(find.text('Un objet JSON est requis.'), findsOneWidget);
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.enterText(custom, '{');
      await tester.pump();
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.enterText(custom, '');
      await tester.pump();
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
      await tester.enterText(custom, '{"origin":"wizard"}');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('behavior-event-trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Double-clic').last);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('behavior-add-submit')));
      await tester.pumpAndSettle();
      final added = appearance.value.behaviorsFor('source').last;
      expect(added.trigger, BehaviorTrigger.doubleClick);
      expect(
        added.action,
        EmitEventAction(eventId: 'node.changed', custom: {'origin': 'wizard'}),
      );
      const codec = AppearanceCodec();
      final restored = codec.decode(codec.encode(appearance.value));
      expect(restored.behaviorsFor('source').last, added);
      expect(history.canUndo, isTrue);
      history.undo();
      expect(appearance.value.behaviorsFor('source'), hasLength(1));
      history.redo();
      expect(appearance.value.behaviorsFor('source').last, added);
    },
  );

  testWidgets('SuperAction uses the same bus without duplicate execution', (
    tester,
  ) async {
    var pressed = 0;
    await mount(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SuperValue(id: 'other'),
          SuperAction(
            id: 'source',
            config: const SuperActionConfig(label: 'Publish'),
            onPressed: () => pressed++,
          ),
        ],
      ),
    );
    await tester.tap(find.text('Publish'));
    await tester.pump();
    expect(pressed, 1);
    expect(received, hasLength(1));
    expect(received.single.componentId, 'source');
    expect(received.single.data, isEmpty);
  });

  testWidgets('input keeps focus, editing and native double-tap selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Alice Smith');
    addTearDown(controller.dispose);
    await mount(
      tester,
      SuperValue(
        id: 'source',
        controller: controller,
        config: const SuperValueConfig(mode: SuperValueMode.input),
      ),
      doubleClick: true,
    );
    final input = find.byKey(const ValueKey('super-value-input-source'));
    await tapAtTime(tester, input, const Duration(seconds: 1));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(received.single.data, {
      'previousValue': 'Alice Smith',
      'value': 'Alice Smith',
    });
    await tester.enterText(input, 'Bob Jones');
    await tester.pumpAndSettle();
    expect(received, hasLength(1));
    await tester.pump(kDoubleTapTimeout);
    received.clear();
    final wordPosition = Offset(
      tester.getTopLeft(input).dx + 20,
      tester.getCenter(input).dy,
    );
    await tapAtTime(
      tester,
      input,
      const Duration(seconds: 2),
      position: wordPosition,
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tapAtTime(
      tester,
      input,
      const Duration(milliseconds: 2070),
      position: wordPosition,
    );
    await tester.pumpAndSettle();
    expect(received.map((e) => e.trigger), ['click', 'click', 'doubleClick']);
    expect(received.last.data, {
      'previousValue': 'Bob Jones',
      'value': 'Bob Jones',
    });
    expect(controller.selection.isCollapsed, isFalse);
  });

  for (final kind in [SuperValueKind.checkbox, SuperValueKind.switchControl]) {
    testWidgets('$kind emits before/after without blocking native toggles', (
      tester,
    ) async {
      final toggles = <bool>[];
      await mount(
        tester,
        SuperValue(
          id: 'source',
          config: SuperValueConfig(kind: kind, mode: SuperValueMode.input),
          onBoolChanged: toggles.add,
        ),
        doubleClick: true,
      );
      final control = find.byKey(
        ValueKey(
          kind == SuperValueKind.checkbox
              ? 'super-value-checkbox-source'
              : 'super-value-switch-source',
        ),
      );
      await tapAtTime(tester, control, const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 60));
      expect(toggles, [true]);
      expect(received.single.data, {'previousValue': false, 'value': true});
      await tapAtTime(tester, control, const Duration(milliseconds: 1070));
      await tester.pump();
      expect(toggles, [true, false]);
      expect(received.map((e) => e.trigger), ['click', 'click', 'doubleClick']);
      expect(received[1].data, {'previousValue': true, 'value': false});
      expect(received[2].data, {'previousValue': false, 'value': false});
      expect(received.first.data['value'], isTrue);
    });
  }

  testWidgets('disabled and read-only controls keep their native state', (
    tester,
  ) async {
    for (final config in [
      const SuperValueConfig(
        kind: SuperValueKind.checkbox,
        mode: SuperValueMode.input,
        enabled: false,
      ),
      const SuperValueConfig(
        kind: SuperValueKind.checkbox,
        mode: SuperValueMode.input,
        readOnly: true,
      ),
    ]) {
      await mount(tester, SuperValue(id: 'source', config: config));
      received.clear();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(received.single.data, {'previousValue': false, 'value': false});
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('edit mode and disabled behaviours do not publish', (
    tester,
  ) async {
    final context = await mount(
      tester,
      const SuperValue(
        id: 'source',
        config: SuperValueConfig(initialText: 'Alice'),
      ),
      editing: true,
    );
    await tester.tap(find.text('Alice'));
    await tester.pump();
    expect(received, isEmpty);
    StyleEditScope.controllerOf(context)!.value = false;
    final appearance = AppearanceScope.controllerOf(context)!;
    final behavior = appearance.value.behaviorsFor('source').single;
    appearance.value = appearance.value
        .withRemovedBehavior('source', behavior.id)
        .withAddedBehavior('source', behavior.copyWith(enabled: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pump();
    expect(received, isEmpty);
  });

  testWidgets('drags, cancelled, long and secondary presses do not publish', (
    tester,
  ) async {
    await mount(
      tester,
      const SuperValue(
        id: 'source',
        config: SuperValueConfig(initialText: 'Alice'),
      ),
    );
    final target = find.text('Alice');
    await tester.drag(target, const Offset(100, 0));
    await tester.pump();
    final cancelled = await tester.startGesture(tester.getCenter(target));
    await cancelled.cancel();
    final long = await tester.createGesture();
    await long.down(
      tester.getCenter(target),
      timeStamp: const Duration(seconds: 1),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    await long.up(timeStamp: const Duration(seconds: 2));
    await tester.tap(target, buttons: kSecondaryMouseButton);
    await tester.pump();
    expect(received, isEmpty);
  });

  testWidgets('repeated IDs publish the actual instance value', (tester) async {
    await mount(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SuperValue(
            id: 'source',
            config: SuperValueConfig(initialText: 'First'),
          ),
          SuperValue(
            id: 'source',
            config: SuperValueConfig(initialText: 'Second'),
          ),
        ],
      ),
    );
    await tester.tap(find.text('Second'));
    await tester.pump();
    expect(received, hasLength(1));
    expect(received.single.data['value'], 'Second');
  });

  testWidgets('equivalent nested slots do not publish twice', (tester) async {
    await mount(
      tester,
      const EditorSlot(
        id: 'source',
        child: SuperValue(
          id: 'source',
          config: SuperValueConfig(initialText: 'Alice'),
        ),
      ),
    );
    await tester.tap(find.text('Alice'));
    await tester.pump();
    expect(received, hasLength(1));
    expect(received.single.componentType, 'value');
  });

  testWidgets('missing bus and missing execution data fail explicitly', (
    tester,
  ) async {
    final context = await mount(
      tester,
      const SuperValue(id: 'source'),
      injectBus: false,
    );
    final action = EmitEventAction(eventId: 'changed');
    await expectLater(action.execute(context), throwsStateError);
    await expectLater(
      action.executeWithData(
        context,
        BehaviorExecutionData(
          componentId: 'source',
          componentType: 'value',
          trigger: BehaviorTrigger.click,
        ),
      ),
      throwsStateError,
    );
  });

  testWidgets('sliver event slots preserve their render protocol', (
    tester,
  ) async {
    await mount(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SuperValue(id: 'other'),
          SizedBox(
            height: 200,
            child: CustomScrollView(
              slivers: [
                SliverSlotScope(
                  child: EditorSlot(
                    id: 'source',
                    child: SliverToBoxAdapter(
                      child: SizedBox(
                        height: 100,
                        child: Text('Sliver target'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      doubleClick: true,
    );
    final target = find.text('Sliver target');
    await tapAtTime(tester, target, const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 60));
    await tapAtTime(tester, target, const Duration(milliseconds: 1070));
    await tester.pump();
    expect(received.map((e) => e.trigger), ['click', 'click', 'doubleClick']);
    expect(received.every((e) => e.data.isEmpty), isTrue);
    expect(tester.takeException(), isNull);
  });
}
