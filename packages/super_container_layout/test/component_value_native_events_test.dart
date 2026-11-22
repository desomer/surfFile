import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SuperEventBus bus;
  late List<SuperComponentEvent> events;
  late List<StreamSubscription<SuperComponentEvent>> subscriptions;

  void listenEventIds(List<String> ids) {
    for (final id in ids) {
      subscriptions.add(bus.on(id).listen(events.add));
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ComponentRuntimeValueRegistry.instance.clear();
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    bus = SuperEventBus();
    events = [];
    subscriptions = [];
  });

  tearDown(() async {
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    await bus.close();
    ComponentRuntimeValueRegistry.instance.clear();
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<BuildContext> mountWidget(
    WidgetTester tester,
    Widget child, {
    JsonRepositoryStore? repositories,
    bool editing = false,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(child: SizedBox(width: 480, height: 600, child: child)),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(
        router: router,
        eventBus: bus,
        repositoryStore: repositories,
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    StyleEditScope.controllerOf(context)!.value = editing;
    await tester.pumpAndSettle();
    return context;
  }

  testWidgets(
    'SuperValue text emits onChanged, onSubmitted, onFocus, onBlur and exposes readValue/readIsValid before touched',
    (tester) async {
      listenEventIds([
        'val.changed',
        'val.submitted',
        'val.focus',
        'val.blur',
        'form.submitted',
      ]);
      final store = JsonRepositoryStore.defaultStore();
      addTearDown(store.dispose);
      final repo = RepositoryImpl(
        id: 'form_repo',
        json: {'email': ''},
        onChanged: (_) {},
      );
      store.registerRepository(repo);

      await mountWidget(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SuperValue(
              id: 'email_field',
              config: const SuperValueConfig(
                mode: SuperValueMode.input,
                binding: JsonTextBinding(
                  repositoryId: 'form_repo',
                  path: 'email',
                ),
                field: SuperTextFieldConfig(
                  required: true,
                  format: TextFieldFormat.email,
                ),
              ),
              behaviours: [
                ComponentBehavior(
                  id: 'b_changed',
                  event: BehaviorEvent.onChanged,
                  action: EmitEventAction(eventId: 'val.changed'),
                ),
                ComponentBehavior(
                  id: 'b_submitted',
                  event: BehaviorEvent.onSubmitted,
                  action: EmitEventAction(eventId: 'val.submitted'),
                ),
                ComponentBehavior(
                  id: 'b_focus',
                  event: BehaviorEvent.onFocus,
                  action: EmitEventAction(eventId: 'val.focus'),
                ),
                ComponentBehavior(
                  id: 'b_blur',
                  event: BehaviorEvent.onBlur,
                  action: EmitEventAction(eventId: 'val.blur'),
                ),
              ],
            ),
            SuperAction(
              id: 'submit_btn',
              config: const SuperActionConfig(label: 'Valider'),
              behaviours: [
                ComponentBehavior(
                  id: 'b_submit',
                  event: BehaviorEvent.onTap,
                  validator: const ValueBehaviorValidator(
                    source: BehaviorValueSource.component,
                    targetComponentId: 'email_field',
                    operator: BehaviorValidatorOperator.isValid,
                  ),
                  action: EmitEventAction(eventId: 'form.submitted'),
                ),
              ],
            ),
            const TextField(key: ValueKey('other-input')),
          ],
        ),
        repositories: store,
      );

      // Initial load must NOT emit onChanged.
      expect(events, isEmpty);

      // Even BEFORE touching the field, readIsValid() is false so submit validator blocks.
      final entry = ComponentRuntimeValueRegistry.instance.resolve(
        'email_field',
      );
      expect(entry, isNotNull);
      expect(entry!.readValue(), '');
      expect(entry.readIsValid?.call(), isFalse);

      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(events.where((e) => e.eventId == 'form.submitted'), isEmpty);

      // Programmatic repository sync must NOT emit onChanged, and updates tracked value.
      await store.writeAttribute(
        const JsonTextBinding(repositoryId: 'form_repo', path: 'email'),
        'init@example.com',
        expectedValue: '',
      );
      await tester.pumpAndSettle();
      expect(events, isEmpty);
      expect(entry.readValue(), 'init@example.com');
      expect(entry.readIsValid?.call(), isTrue);

      // Focus -> onFocus
      final input = find.byKey(const ValueKey('super-value-input-email_field'));
      await tester.tap(input);
      await tester.pumpAndSettle();
      expect(
        events.where((e) => e.eventId == 'val.focus').map((e) => e.data),
        [
          {'value': 'init@example.com', 'hasFocus': true},
        ],
      );

      // User typing -> onChanged with accurate previousValue
      await tester.enterText(input, 'user@example.com');
      await tester.pumpAndSettle();
      final changedEvents = events
          .where((e) => e.eventId == 'val.changed')
          .toList();
      expect(changedEvents, hasLength(1));
      expect(changedEvents.single.data, {
        'value': 'user@example.com',
        'previousValue': 'init@example.com',
      });

      // Keyboard submit -> onSubmitted
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final submittedEvents = events
          .where((e) => e.eventId == 'val.submitted')
          .toList();
      expect(submittedEvents, hasLength(1));
      expect(submittedEvents.single.data, {'value': 'user@example.com'});

      // Blur -> onBlur
      await tester.tap(find.byKey(const ValueKey('other-input')));
      await tester.pumpAndSettle();
      final blurEvents = events.where((e) => e.eventId == 'val.blur').toList();
      expect(blurEvents, hasLength(1));
      expect(blurEvents.single.data, {
        'value': 'user@example.com',
        'hasFocus': false,
      });

      // Now Submit button validator passes!
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(events.where((e) => e.eventId == 'form.submitted'), hasLength(1));
    },
  );

  testWidgets('SuperValue checkbox and choice emit onChanged and onSelected', (
    tester,
  ) async {
    listenEventIds(['cb.changed', 'ch.changed', 'ch.selected']);
    await mountWidget(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SuperValue(
            id: 'agree_cb',
            config: const SuperValueConfig(
              kind: SuperValueKind.checkbox,
              mode: SuperValueMode.input,
              label: 'Accepter',
            ),
            behaviours: [
              ComponentBehavior(
                id: 'cb_changed',
                event: BehaviorEvent.onChanged,
                action: EmitEventAction(eventId: 'cb.changed'),
              ),
            ],
          ),
          SuperValue(
            id: 'tags_choice',
            config: const SuperValueConfig(
              kind: SuperValueKind.choice,
              mode: SuperValueMode.input,
              choice: SuperChoiceConfig(
                variant: ChoiceVariant.filterChip,
                options: [
                  SuperChoiceOption(value: 'a', label: 'Alpha'),
                  SuperChoiceOption(value: 'b', label: 'Beta'),
                ],
              ),
            ),
            behaviours: [
              ComponentBehavior(
                id: 'ch_changed',
                event: BehaviorEvent.onChanged,
                action: EmitEventAction(eventId: 'ch.changed'),
              ),
              ComponentBehavior(
                id: 'ch_selected',
                event: BehaviorEvent.onSelected,
                action: EmitEventAction(eventId: 'ch.selected'),
              ),
            ],
          ),
        ],
      ),
    );

    expect(events, isEmpty);

    await tester.tap(find.byKey(const ValueKey('super-value-checkbox-agree_cb')));
    await tester.pumpAndSettle();
    expect(events.where((e) => e.eventId == 'cb.changed').single.data, {
      'value': true,
      'previousValue': false,
    });
    expect(
      ComponentRuntimeValueRegistry.instance.resolve('agree_cb')?.readValue(),
      isTrue,
    );

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(events.where((e) => e.eventId == 'ch.changed').single.data, {
      'value': ['a'],
      'previousValue': <String>[],
    });
    expect(events.where((e) => e.eventId == 'ch.selected').single.data, {
      'value': ['a'],
      'previousValue': <String>[],
    });
    expect(
      ComponentRuntimeValueRegistry.instance.resolve('tags_choice')?.readValue(),
      ['a'],
    );
  });

  testWidgets(
    'SuperExpansible and SuperMenuAnchor expose readValue and emit onExpanded/onCollapsed/onChanged',
    (tester) async {
      listenEventIds([
        'exp.open',
        'exp.close',
        'exp.change',
        'menu.open',
        'menu.close',
        'menu.change',
      ]);
      await mountWidget(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SuperExpansible(
              id: 'panel_1',
              header: const Text('Ouvrir panneau'),
              body: const Text('Contenu panneau'),
              behaviours: [
                ComponentBehavior(
                  id: 'exp_open',
                  event: BehaviorEvent.onExpanded,
                  action: EmitEventAction(eventId: 'exp.open'),
                ),
                ComponentBehavior(
                  id: 'exp_close',
                  event: BehaviorEvent.onCollapsed,
                  action: EmitEventAction(eventId: 'exp.close'),
                ),
                ComponentBehavior(
                  id: 'exp_change',
                  event: BehaviorEvent.onChanged,
                  action: EmitEventAction(eventId: 'exp.change'),
                ),
              ],
            ),
            SuperMenuAnchor(
              id: 'menu_1',
              header: const Text('Ouvrir menu'),
              body: const Text('Item menu'),
              behaviours: [
                ComponentBehavior(
                  id: 'menu_open',
                  event: BehaviorEvent.onExpanded,
                  action: EmitEventAction(eventId: 'menu.open'),
                ),
                ComponentBehavior(
                  id: 'menu_close',
                  event: BehaviorEvent.onCollapsed,
                  action: EmitEventAction(eventId: 'menu.close'),
                ),
                ComponentBehavior(
                  id: 'menu_change',
                  event: BehaviorEvent.onChanged,
                  action: EmitEventAction(eventId: 'menu.change'),
                ),
              ],
            ),
          ],
        ),
      );

      expect(events, isEmpty);
      final expEntry = ComponentRuntimeValueRegistry.instance.resolve('panel_1');
      final menuEntry = ComponentRuntimeValueRegistry.instance.resolve('menu_1');
      expect(expEntry?.componentType, 'expansible');
      expect(expEntry?.readValue(), isFalse);
      expect(menuEntry?.componentType, 'menu');
      expect(menuEntry?.readValue(), isFalse);

      // Expand panel
      await tester.tap(find.text('Ouvrir panneau'));
      await tester.pumpAndSettle();
      expect(expEntry?.readValue(), isTrue);
      expect(events.where((e) => e.eventId == 'exp.open').single.data, {
        'expanded': true,
        'value': true,
        'previousValue': false,
      });
      expect(events.where((e) => e.eventId == 'exp.change').single.data, {
        'expanded': true,
        'value': true,
        'previousValue': false,
      });

      // Collapse panel
      events.clear();
      await tester.tap(find.text('Ouvrir panneau'));
      await tester.pumpAndSettle();
      expect(expEntry?.readValue(), isFalse);
      expect(events.where((e) => e.eventId == 'exp.close').single.data, {
        'expanded': false,
        'value': false,
        'previousValue': true,
      });
      expect(events.where((e) => e.eventId == 'exp.change').single.data, {
        'expanded': false,
        'value': false,
        'previousValue': true,
      });

      // Open menu
      events.clear();
      await tester.tap(find.text('Ouvrir menu'));
      await tester.pumpAndSettle();
      expect(menuEntry?.readValue(), isTrue);
      expect(events.where((e) => e.eventId == 'menu.open').single.data, {
        'expanded': true,
        'value': true,
        'previousValue': false,
      });
      expect(events.where((e) => e.eventId == 'menu.change').single.data, {
        'expanded': true,
        'value': true,
        'previousValue': false,
      });

      // Close menu
      events.clear();
      await tester.tap(find.text('Ouvrir menu'));
      await tester.pumpAndSettle();
      expect(menuEntry?.readValue(), isFalse);
      expect(events.where((e) => e.eventId == 'menu.close').single.data, {
        'expanded': false,
        'value': false,
        'previousValue': true,
      });
      expect(events.where((e) => e.eventId == 'menu.change').single.data, {
        'expanded': false,
        'value': false,
        'previousValue': true,
      });
    },
  );

  testWidgets(
    'SuperBottomNavigationBar and SuperNavigationRail expose readValue and dispatch onSelected on bar/rail and destination',
    (tester) async {
      listenEventIds([
        'rail.dest.tap',
        'rail.dest.sel',
        'rail.sel',
        'bar.dest.tap',
        'bar.dest.sel',
        'bar.sel',
      ]);
      await mountWidget(
        tester,
        Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SuperNavigationRail(
                    id: 'main_rail',
                    destinations: [
                      SuperAction(
                        id: 'rail_home',
                        config: const SuperActionConfig(
                          label: 'AccueilRail',
                          icon: 'home',
                        ),
                      ),
                      SuperAction(
                        id: 'rail_settings',
                        config: const SuperActionConfig(
                          label: 'ReglagesRail',
                          icon: 'settings',
                        ),
                        behaviours: [
                          ComponentBehavior(
                            id: 'rail_dest_tap',
                            event: BehaviorEvent.onTap,
                            action: EmitEventAction(eventId: 'rail.dest.tap'),
                          ),
                          ComponentBehavior(
                            id: 'rail_dest_sel',
                            event: BehaviorEvent.onSelected,
                            action: EmitEventAction(eventId: 'rail.dest.sel'),
                          ),
                        ],
                      ),
                    ],
                    behaviours: [
                      ComponentBehavior(
                        id: 'rail_sel',
                        event: BehaviorEvent.onSelected,
                        action: EmitEventAction(eventId: 'rail.sel'),
                      ),
                    ],
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
            SuperBottomNavigationBar(
              id: 'main_bar',
              destinations: [
                SuperAction(
                  id: 'bar_home',
                  config: const SuperActionConfig(
                    label: 'AccueilBar',
                    icon: 'home',
                  ),
                ),
                SuperAction(
                  id: 'bar_profile',
                  config: const SuperActionConfig(
                    label: 'ProfilBar',
                    icon: 'person',
                  ),
                  behaviours: [
                    ComponentBehavior(
                      id: 'bar_dest_tap',
                      event: BehaviorEvent.onTap,
                      action: EmitEventAction(eventId: 'bar.dest.tap'),
                    ),
                    ComponentBehavior(
                      id: 'bar_dest_sel',
                      event: BehaviorEvent.onSelected,
                      action: EmitEventAction(eventId: 'bar.dest.sel'),
                    ),
                  ],
                ),
              ],
              behaviours: [
                ComponentBehavior(
                  id: 'bar_sel',
                  event: BehaviorEvent.onSelected,
                  action: EmitEventAction(eventId: 'bar.sel'),
                ),
              ],
            ),
          ],
        ),
      );

      final railEntry = ComponentRuntimeValueRegistry.instance.resolve(
        'main_rail',
      );
      final barEntry = ComponentRuntimeValueRegistry.instance.resolve(
        'main_bar',
      );
      expect(railEntry?.componentType, 'navigationRail');
      expect(railEntry?.readValue(), 0);
      expect(barEntry?.componentType, 'bottomNavigationBar');
      expect(barEntry?.readValue(), 0);

      await tester.tap(find.text('ReglagesRail'));
      await tester.pumpAndSettle();
      expect(railEntry?.readValue(), 1);
      expect(events.where((e) => e.eventId == 'rail.dest.tap'), hasLength(1));
      final railSel = events.where((e) => e.eventId == 'rail.sel').single;
      expect(railSel.componentId, 'main_rail');
      expect(railSel.componentType, 'navigationRail');
      expect(railSel.data, {
        'index': 1,
        'previousIndex': 0,
        'destinationId': 'rail_settings',
      });
      final railDestSel = events
          .where((e) => e.eventId == 'rail.dest.sel')
          .single;
      expect(railDestSel.componentId, 'rail_settings');
      expect(railDestSel.componentType, 'action');
      expect(railDestSel.data, {'index': 1, 'previousIndex': 0});

      events.clear();
      await tester.tap(find.text('ProfilBar'));
      await tester.pumpAndSettle();
      expect(barEntry?.readValue(), 1);
      expect(events.where((e) => e.eventId == 'bar.dest.tap'), hasLength(1));
      final barSel = events.where((e) => e.eventId == 'bar.sel').single;
      expect(barSel.componentId, 'main_bar');
      expect(barSel.componentType, 'bottomNavigationBar');
      expect(barSel.data, {
        'index': 1,
        'previousIndex': 0,
        'destinationId': 'bar_profile',
      });
      final barDestSel = events
          .where((e) => e.eventId == 'bar.dest.sel')
          .single;
      expect(barDestSel.componentId, 'bar_profile');
      expect(barDestSel.componentType, 'action');
      expect(barDestSel.data, {'index': 1, 'previousIndex': 0});
    },
  );
}
