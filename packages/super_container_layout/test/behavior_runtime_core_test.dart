import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

/// Action de test enregistrant ses exécutions et supportant un callback personnalisé.
class _RecordingAction extends BehaviorAction {
  const _RecordingAction({required this.onRun});

  final FutureOr<void> Function(BuildContext context, BehaviorExecutionData data)
  onRun;

  @override
  String get type => 'testRecord';
  @override
  String get label => 'Test record';
  @override
  String get description => 'rec';
  @override
  IconData get icon => Icons.check;
  @override
  Map<String, Object?> toJson() => {'type': type};
  @override
  Future<void> execute(BuildContext context) async {}

  @override
  Future<void> executeWithData(
    BuildContext context,
    BehaviorExecutionData data,
  ) async {
    await onRun(context, data);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channels = [
    MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];

  setUp(() {
    ComponentRuntimeValueRegistry.instance.clear();
    SharedPreferences.setMockInitialValues({});
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    ComponentRuntimeValueRegistry.instance.clear();
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('ComponentRuntimeValueRegistry', () {
    test('scopeKeyOf builds deterministic keys and handles null/empty', () {
      expect(ComponentRuntimeValueRegistry.scopeKeyOf(null), isNull);
      expect(
        ComponentRuntimeValueRegistry.scopeKeyOf(
          const JsonListScope(
            repositoryId: null,
            indices: [],
            child: SizedBox.shrink(),
          ),
        ),
        isNull,
      );
      expect(
        ComponentRuntimeValueRegistry.scopeKeyOf(
          const JsonListScope(
            repositoryId: 'orders',
            indices: [0, 2],
            nodePath: 'nodes[0].children[2]',
            child: SizedBox.shrink(),
          ),
        ),
        'orders|0,2|nodes[0].children[2]',
      );
    });

    test('resolve prefers matching listScopeKey, then global, never wrong row', () {
      final registry = ComponentRuntimeValueRegistry();
      final globalToken = Object();
      final row0Token = Object();
      final row1Token = Object();

      registry.register(
        ComponentRuntimeValueEntry(
          token: globalToken,
          componentId: 'field',
          componentType: 'value',
          readValue: () => 'global',
        ),
      );
      registry.register(
        ComponentRuntimeValueEntry(
          token: row0Token,
          componentId: 'field',
          componentType: 'value',
          listScopeKey: 'repo|0|',
          readValue: () => 'row0',
        ),
      );
      registry.register(
        ComponentRuntimeValueEntry(
          token: row1Token,
          componentId: 'field',
          componentType: 'value',
          listScopeKey: 'repo|1|',
          readValue: () => 'row1',
        ),
      );

      expect(registry.entriesFor('field'), hasLength(3));
      expect(
        registry.resolve('field', preferredScopeKey: 'repo|0|')?.readValue(),
        'row0',
      );
      expect(
        registry.resolve('field', preferredScopeKey: 'repo|1|')?.readValue(),
        'row1',
      );
      expect(
        registry.resolve('field', preferredScopeKey: 'repo|99|')?.readValue(),
        'global',
      );
      expect(registry.resolve('field')?.readValue(), 'global');

      registry.unregister(globalToken);
      expect(registry.resolve('field', preferredScopeKey: 'repo|99|'), isNull);
      expect(registry.resolve('field'), isNull);

      registry.clear();
      expect(registry.entriesFor('field'), isEmpty);
    });
  });

  group('BehaviorValidatorEvaluator', () {
    Future<BuildContext> pumpBlankContext(WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              captured = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return captured;
    }

    testWidgets('evaluates all operators and edge cases accurately', (
      tester,
    ) async {
      final ctx = await pumpBlankContext(tester);
      final registry = ComponentRuntimeValueRegistry();

      Future<bool> eval(
        BehaviorValidator validator, {
        Map<String, Object?> data = const {},
      }) => BehaviorValidatorEvaluator.evaluate(
        validator,
        BehaviorValidationContext(
          context: ctx,
          componentId: 'self_comp',
          componentType: 'value',
          event: BehaviorEvent.onTap,
          executionData: data,
          valueRegistry: registry,
        ),
      );

      // isEmpty / isFill edge cases (0 and false are NOT empty)
      expect(await eval(const ValueBehaviorValidator.isEmpty(), data: {'value': null}), isTrue);
      expect(await eval(const ValueBehaviorValidator.isEmpty(), data: {'value': '   '}), isTrue);
      expect(await eval(const ValueBehaviorValidator.isEmpty(), data: {'value': const []}), isTrue);
      expect(await eval(const ValueBehaviorValidator.isEmpty(), data: {'value': const {}}), isTrue);
      expect(await eval(const ValueBehaviorValidator.isEmpty(), data: {'value': 0}), isFalse);
      expect(await eval(const ValueBehaviorValidator.isEmpty(), data: {'value': false}), isFalse);
      expect(await eval(const ValueBehaviorValidator.isFill(), data: {'value': 0}), isTrue);
      expect(await eval(const ValueBehaviorValidator.isFill(), data: {'value': 'abc'}), isTrue);

      // isTrue / isFalse
      for (final truthy in [true, 'true', '1', 'YES', 'oui']) {
        expect(
          await eval(const ValueBehaviorValidator.isTrue(), data: {'value': truthy}),
          isTrue,
          reason: 'Expected $truthy to match isTrue',
        );
      }
      for (final falsy in [false, 'false', '0', 'No', 'non']) {
        expect(
          await eval(const ValueBehaviorValidator.isFalse(), data: {'value': falsy}),
          isTrue,
          reason: 'Expected $falsy to match isFalse',
        );
      }

      // equals / notEquals (tolerant num/string & bool/string & deep JSON)
      expect(await eval(const ValueBehaviorValidator.equals(42), data: {'value': '42'}), isTrue);
      expect(await eval(const ValueBehaviorValidator.equals('42.5'), data: {'value': 42.5}), isTrue);
      expect(await eval(const ValueBehaviorValidator.equals(true), data: {'value': 'true'}), isTrue);
      expect(await eval(const ValueBehaviorValidator.equals([1, 'a']), data: {'value': [1.0, 'a']}), isTrue);
      expect(await eval(const ValueBehaviorValidator.notEquals('x'), data: {'value': 'y'}), isTrue);

      // contains / startsWith / greaterThan / lessThan / matchesRegex
      expect(
        await eval(
          const ValueBehaviorValidator(
            operator: BehaviorValidatorOperator.contains,
            expectedValue: 'bar',
          ),
          data: {'value': 'foobar'},
        ),
        isTrue,
      );
      expect(
        await eval(
          const ValueBehaviorValidator(
            operator: BehaviorValidatorOperator.contains,
            expectedValue: 2,
          ),
          data: {'value': [1, 2, 3]},
        ),
        isTrue,
      );
      expect(
        await eval(
          const ValueBehaviorValidator(
            operator: BehaviorValidatorOperator.startsWith,
            expectedValue: 'pre',
          ),
          data: {'value': 'prefix'},
        ),
        isTrue,
      );
      expect(
        await eval(
          const ValueBehaviorValidator(
            operator: BehaviorValidatorOperator.greaterThan,
            expectedValue: 10,
          ),
          data: {'value': '12.5'},
        ),
        isTrue,
      );
      expect(
        await eval(
          const ValueBehaviorValidator(
            operator: BehaviorValidatorOperator.lessThan,
            expectedValue: 10,
          ),
          data: {'value': 'not-a-number'},
        ),
        isFalse,
      );
      expect(
        await eval(
          const ValueBehaviorValidator(
            operator: BehaviorValidatorOperator.matchesRegex,
            expectedValue: r'^[A-Z]{2}\d+$',
          ),
          data: {'value': 'FR123'},
        ),
        isTrue,
      );

      // isValid / isInvalid via registry
      final token = Object();
      var validFlag = true;
      registry.register(
        ComponentRuntimeValueEntry(
          token: token,
          componentId: 'self_comp',
          componentType: 'value',
          readValue: () => 'hello',
          readIsValid: () => validFlag,
        ),
      );
      expect(await eval(const ValueBehaviorValidator.isValid()), isTrue);
      expect(await eval(const ValueBehaviorValidator.isInvalid()), isFalse);
      validFlag = false;
      expect(await eval(const ValueBehaviorValidator.isValid()), isFalse);
      expect(await eval(const ValueBehaviorValidator.isInvalid()), isTrue);

      // Composite validators: all, any, not
      expect(
        await eval(
          AllBehaviorValidator(
            validators: const [
              ValueBehaviorValidator.isFill(),
              ValueBehaviorValidator.equals('hello'),
            ],
          ),
        ),
        isTrue,
      );
      expect(
        await eval(
          AnyBehaviorValidator(
            validators: const [
              ValueBehaviorValidator.isEmpty(),
              ValueBehaviorValidator.equals('hello'),
            ],
          ),
        ),
        isTrue,
      );
      expect(
        await eval(
          const NotBehaviorValidator(
            validator: ValueBehaviorValidator.isEmpty(),
          ),
        ),
        isTrue,
      );
    });

    testWidgets(
      'resolves component fallback via Appearance.components and direct repository bindings',
      (tester) async {
        final ctx = await pumpBlankContext(tester);
        final store = JsonRepositoryStore.defaultStore();
        addTearDown(store.dispose);
        store.registerRepository(
          RepositoryImpl(
            id: 'crm',
            json: {
              'email': 'alice@example.com',
              'items': [
                {'title': 'A'},
              ],
            },
            onChanged: (_) {},
          ),
        );

        final appearance = Appearance(
          components: const {
            'email_field': SuperValueConfig(
              binding: JsonTextBinding(repositoryId: 'crm', path: 'email'),
            ),
            'orders_list': SuperListViewConfig(
              binding: JsonTextBinding(repositoryId: 'crm', path: 'items'),
            ),
          },
        );

        final valCtx = BehaviorValidationContext(
          context: ctx,
          componentId: 'submit_btn',
          componentType: 'action',
          event: BehaviorEvent.onTap,
          appearance: appearance,
          repositoryStore: store,
          valueRegistry: ComponentRuntimeValueRegistry(),
        );

        // Component fallback via Appearance.components (SuperValueConfig)
        expect(
          await BehaviorValidatorEvaluator.evaluate(
            const ValueBehaviorValidator.otherIsFill('email_field'),
            valCtx,
          ),
          isTrue,
        );
        // Component fallback via Appearance.components (SuperListViewConfig)
        expect(
          await BehaviorValidatorEvaluator.evaluate(
            const ValueBehaviorValidator.otherIsFill('orders_list'),
            valCtx,
          ),
          isTrue,
        );
        // Unknown target does not crash and evaluates as empty & invalid
        expect(
          await BehaviorValidatorEvaluator.evaluate(
            const ValueBehaviorValidator.otherIsEmpty('missing_comp'),
            valCtx,
          ),
          isTrue,
        );
        expect(
          await BehaviorValidatorEvaluator.evaluate(
            const ValueBehaviorValidator.otherIsInvalid('missing_comp'),
            valCtx,
          ),
          isTrue,
        );
        // Direct repository binding validator
        expect(
          await BehaviorValidatorEvaluator.evaluate(
            const ValueBehaviorValidator.bindingEquals(
              JsonTextBinding(repositoryId: 'crm', path: 'email'),
              'alice@example.com',
            ),
            valCtx,
          ),
          isTrue,
        );
      },
    );
  });

  group('BehaviorDispatcher & unified runtime listeners', () {
    testWidgets(
      'enforces edit-mode, disabled/invisible guards, validators, and anti-reentrancy',
      (tester) async {
        final editing = ValueNotifier<bool>(false);
        addTearDown(editing.dispose);
        final appearance = ValueNotifier<Appearance>(Appearance());
        addTearDown(appearance.dispose);

        var runs = 0;
        late BuildContext activeCtx;
        late BuildContext disabledCtx;

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: StyleEditScope(
              controller: editing,
              child: MaterialApp(
                home: Column(
                  children: [
                    Builder(
                      builder: (ctx) {
                        activeCtx = ctx;
                        return const SizedBox.shrink();
                      },
                    ),
                    ComponentBehaviorStateScope(
                      invisible: false,
                      maintainSize: false,
                      readOnly: false,
                      disabled: true,
                      child: Builder(
                        builder: (ctx) {
                          disabledCtx = ctx;
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final simpleBehavior = ComponentBehavior(
          id: 'b1',
          event: BehaviorEvent.onTap,
          validator: const ValueBehaviorValidator.isFill(),
          action: _RecordingAction(onRun: (_, _) => runs++),
        );

        // Validator blocks when value is empty
        expect(
          await BehaviorDispatcher.dispatch(
            activeCtx,
            componentId: 'comp',
            componentType: 'value',
            event: BehaviorEvent.onTap,
            data: const {'value': ''},
            behaviors: [simpleBehavior],
          ),
          isFalse,
        );
        expect(runs, 0);

        // Validator passes when value is filled
        expect(
          await BehaviorDispatcher.dispatch(
            activeCtx,
            componentId: 'comp',
            componentType: 'value',
            event: BehaviorEvent.onTap,
            data: const {'value': 'ok'},
            behaviors: [simpleBehavior],
          ),
          isTrue,
        );
        expect(runs, 1);

        // Edit mode blocks unless ignoreEditMode: true
        editing.value = true;
        expect(
          await BehaviorDispatcher.dispatch(
            activeCtx,
            componentId: 'comp',
            componentType: 'value',
            event: BehaviorEvent.onTap,
            data: const {'value': 'ok'},
            behaviors: [simpleBehavior],
          ),
          isFalse,
        );
        expect(runs, 1);

        expect(
          await BehaviorDispatcher.dispatch(
            activeCtx,
            componentId: 'comp',
            componentType: 'value',
            event: BehaviorEvent.onTap,
            data: const {'value': 'ok'},
            behaviors: [simpleBehavior],
            ignoreEditMode: true,
          ),
          isTrue,
        );
        expect(runs, 2);
        editing.value = false;

        // Disabled scope blocks execution
        expect(
          await BehaviorDispatcher.dispatch(
            disabledCtx,
            componentId: 'comp',
            componentType: 'value',
            event: BehaviorEvent.onTap,
            data: const {'value': 'ok'},
            behaviors: [simpleBehavior],
          ),
          isFalse,
        );
        expect(runs, 2);

        // Anti-reentrancy stops recursion at maxReentrancyDepth (8)
        var recursiveCalls = 0;
        late ComponentBehavior recursiveBehavior;
        recursiveBehavior = ComponentBehavior(
          id: 'loop',
          event: BehaviorEvent.onChanged,
          action: _RecordingAction(
            onRun: (ctx, _) async {
              recursiveCalls++;
              await BehaviorDispatcher.dispatch(
                ctx,
                componentId: 'loop_comp',
                componentType: 'value',
                event: BehaviorEvent.onChanged,
                behaviors: [recursiveBehavior],
              );
            },
          ),
        );

        await BehaviorDispatcher.dispatch(
          activeCtx,
          componentId: 'loop_comp',
          componentType: 'value',
          event: BehaviorEvent.onChanged,
          behaviors: [recursiveBehavior],
        );
        expect(recursiveCalls, BehaviorDispatcher.maxReentrancyDepth);
      },
    );

    testWidgets(
      'EditorSlot registers runtime values and BehaviorEventListener supports onMount, onHoverEnter/Exit, onLongPress, and SuperAction without double-firing',
      (tester) async {
        final log = <String>[];
        final bus = SuperEventBus();
        addTearDown(bus.close);
        final busEvents = <SuperComponentEvent>[];
        final sub = bus.on('submitted').listen(busEvents.add);
        addTearDown(sub.cancel);

        var inputValue = '';
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                body: Column(
                  children: [
                    EditorSlot(
                      id: 'input_field',
                      eventComponentType: 'value',
                      readValue: () => inputValue,
                      readIsValid: () => inputValue.isNotEmpty,
                      behaviors: [
                        ComponentBehavior(
                          id: 'mount-b',
                          event: BehaviorEvent.onMount,
                          action: _RecordingAction(
                            onRun: (_, d) => log.add('mount:${d.componentId}'),
                          ),
                        ),
                        ComponentBehavior(
                          id: 'hover-enter',
                          event: BehaviorEvent.onHoverEnter,
                          action: _RecordingAction(
                            onRun: (_, _) => log.add('hoverEnter'),
                          ),
                        ),
                        ComponentBehavior(
                          id: 'hover-exit',
                          event: BehaviorEvent.onHoverExit,
                          action: _RecordingAction(
                            onRun: (_, _) => log.add('hoverExit'),
                          ),
                        ),
                        ComponentBehavior(
                          id: 'long-press',
                          event: BehaviorEvent.onLongPress,
                          action: _RecordingAction(
                            onRun: (_, _) => log.add('longPress'),
                          ),
                        ),
                      ],
                      child: const SizedBox(
                        width: 120,
                        height: 40,
                        child: Text('Target'),
                      ),
                    ),
                    // Nested outer EditorSlot with same ID wrapping SuperAction
                    EditorSlot(
                      id: 'submit_btn',
                      child: SuperAction(
                        id: 'submit_btn',
                        config: const SuperActionConfig(label: 'Valider'),
                        behaviours: [
                          ComponentBehavior(
                            id: 'submit-tap',
                            event: BehaviorEvent.onTap,
                            validator: const ValueBehaviorValidator.otherIsFill(
                              'input_field',
                            ),
                            action: EmitEventAction(eventId: 'submitted'),
                          ),
                          ComponentBehavior(
                            id: 'submit-long',
                            event: BehaviorEvent.onLongPress,
                            action: _RecordingAction(
                              onRun: (_, _) => log.add('actionLongPress'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(SuperApp(router: router, eventBus: bus));
        await tester.pumpAndSettle();

        // onMount fired once post-frame outside edit mode
        expect(log, ['mount:input_field']);

        // EditorSlot registered input_field in ComponentRuntimeValueRegistry
        expect(
          ComponentRuntimeValueRegistry.instance.resolve('input_field'),
          isNotNull,
        );

        // Hover enter & exit
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await tester.pump();
        await mouse.moveTo(tester.getCenter(find.text('Target')));
        await tester.pump();
        expect(log, contains('hoverEnter'));
        await mouse.moveTo(const Offset(500, 500));
        await tester.pump();
        expect(log, contains('hoverExit'));

        // Long press on Target
        final press = await tester.startGesture(
          tester.getCenter(find.text('Target')),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await press.up();
        await tester.pump();
        expect(log, contains('longPress'));

        // SuperAction tap blocked by otherIsFill('input_field') while empty
        await tester.tap(find.text('Valider'));
        await tester.pump();
        expect(busEvents, isEmpty);

        // Fill input_field -> SuperAction tap fires EXACTLY ONCE (even with outer EditorSlot)
        inputValue = 'Alice';
        await tester.tap(find.text('Valider'));
        await tester.pump();
        expect(busEvents, hasLength(1));
        expect(busEvents.single.eventId, 'submitted');
        expect(busEvents.single.componentType, 'action');

        // SuperAction longPress still works through BehaviorEventListener
        final actionPress = await tester.startGesture(
          tester.getCenter(find.text('Valider')),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await actionPress.up();
        await tester.pump();
        expect(log, contains('actionLongPress'));
      },
    );
  });
}
