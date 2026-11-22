import 'dart:async';
import 'dart:io' show Directory;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

/// Évaluateur JS déterministe pour tester `RunJavaScriptAction` sans dépendre
/// de la présence d'une DLL native QuickJS dans l'environnement `flutter test`.
class _DeterministicJsEvaluator
    implements JsCalculatedEvaluator, JsRepositoryActionEvaluator {
  int actionExecutions = 0;

  @override
  FutureOr<Object?> evaluate({
    required String code,
    required Object? scopeData,
    required Object? rootData,
    required CalculatedAttributeContext context,
  }) => null;

  @override
  FutureOr<List<JsRepositoryScriptWrite>> executeAction({
    required String code,
    required Object? rootData,
    required Map<String, Object?> eventData,
    required String repositoryId,
  }) {
    actionExecutions++;
    final doc = rootData is Map ? rootData : const <String, Object?>{};
    final payload = eventData['data'] is Map
        ? eventData['data'] as Map
        : const <String, Object?>{};

    switch (code) {
      case 'mark_double_tap':
        final prevRuns = (doc['doubleTapRuns'] as int?) ?? 0;
        return [
          (path: 'doubleTapRuns', value: prevRuns + 1),
          (path: 'lastEvent', value: eventData['event']),
          (path: 'lastComponentId', value: eventData['componentId']),
        ];
      case 'mark_form_submitted':
        final prevSubmits = (doc['submitCount'] as int?) ?? 0;
        return [(path: 'submitCount', value: prevSubmits + 1)];
      case 'sync_a_to_b':
        final val = '${payload['value'] ?? ''}'.toUpperCase();
        final runs = ((doc['scriptRuns'] as int?) ?? 0) + 1;
        return [(path: 'b', value: val), (path: 'scriptRuns', value: runs)];
      case 'sync_b_to_a':
        final val = '${payload['value'] ?? ''}'.toLowerCase();
        final runs = ((doc['scriptRuns'] as int?) ?? 0) + 1;
        return [(path: 'a', value: val), (path: 'scriptRuns', value: runs)];
      default:
        throw JsCalculationException('Script de test inconnu : $code');
    }
  }

  @override
  void invalidateDocument([String? repositoryId]) {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channels = [
    MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];

  late _DeterministicJsEvaluator jsEvaluator;
  JsonRepositoryStore? activeStore;
  late SuperEventBus bus;
  late List<SuperComponentEvent> events;
  late List<StreamSubscription<SuperComponentEvent>> subscriptions;

  void listenEvents(List<String> ids) {
    for (final id in ids) {
      subscriptions.add(bus.on(id).listen(events.add));
    }
  }

  JsonRepositoryStore obtainStore() {
    if (activeStore != null) return activeStore!;
    final created = JsonRepositoryStore(
      Directory('${Directory.systemTemp.path}\\scl_in_memory_behavior_tests'),
      jsEvaluator: jsEvaluator,
    );
    activeStore = created;
    addTearDown(() {
      created.dispose();
      if (identical(activeStore, created)) activeStore = null;
    });
    return created;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ComponentRuntimeValueRegistry.instance.clear();
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    jsEvaluator = _DeterministicJsEvaluator();
    activeStore = null;
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
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<BuildContext> mountInSuperApp(
    WidgetTester tester,
    Widget child, {
    Appearance? initialAppearance,
    List<GoRoute> extraRoutes = const [],
  }) async {
    final store = obtainStore();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: SizedBox(width: 720, height: 560, child: child),
            ),
          ),
        ),
        ...extraRoutes,
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      SuperApp(router: router, eventBus: bus, repositoryStore: store),
    );
    await tester.pumpAndSettle();

    final scaffoldCtx = tester.element(find.byType(Scaffold).first);
    StyleEditScope.controllerOf(scaffoldCtx)!.value = false;
    if (initialAppearance != null) {
      AppearanceScope.controllerOf(scaffoldCtx)!.value = initialAppearance;
    }
    await tester.pumpAndSettle();
    return scaffoldCtx;
  }

  Future<void> tapAtTime(
    WidgetTester tester,
    Finder target,
    Duration time,
  ) async {
    final gesture = await tester.createGesture();
    await gesture.down(tester.getCenter(target), timeStamp: time);
    await gesture.up(timeStamp: time + const Duration(milliseconds: 10));
    await gesture.removePointer();
  }

  Future<void> performDoubleTap(
    WidgetTester tester,
    Finder target, {
    required Duration startTime,
  }) async {
    await tapAtTime(tester, target, startTime);
    await tester.pump(const Duration(milliseconds: 60));
    await tapAtTime(
      tester,
      target,
      startTime + const Duration(milliseconds: 70),
    );
    await tester.pumpAndSettle();
  }

  group('Non-EmitEvent actions on onDoubleTap', () {
    testWidgets(
      'RunJavaScriptAction and GoToPageAction attached to onDoubleTap ignore single click and execute on double-tap',
      (tester) async {
        final store = obtainStore();
        store.registerRepository(
          RepositoryImpl(
            id: 'dbl_repo',
            json: {'doubleTapRuns': 0, 'lastEvent': '', 'lastComponentId': ''},
          ),
        );

        await mountInSuperApp(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SuperAction(
                id: 'js_dbl_btn',
                config: const SuperActionConfig(label: 'Double-clic Script'),
                behaviours: const [
                  ComponentBehavior(
                    id: 'b_js_dbl',
                    event: BehaviorEvent.onDoubleTap,
                    action: RunJavaScriptAction(
                      repositoryId: 'dbl_repo',
                      code: 'mark_double_tap',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SuperAction(
                id: 'nav_dbl_btn',
                config: const SuperActionConfig(label: 'Double-clic Page'),
                behaviours: const [
                  ComponentBehavior(
                    id: 'b_nav_dbl',
                    event: BehaviorEvent.onDoubleTap,
                    action: GoToPageAction(pagePath: '/details'),
                  ),
                ],
              ),
            ],
          ),
          extraRoutes: [
            GoRoute(
              path: '/details',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('Page Details Ouverte')),
              ),
            ),
          ],
        );

        // Single click on RunJavaScriptAction button (wait past kDoubleTapTimeout).
        await tapAtTime(
          tester,
          find.text('Double-clic Script'),
          const Duration(milliseconds: 100),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(store.peekDocument('dbl_repo')?.document, {
          'doubleTapRuns': 0,
          'lastEvent': '',
          'lastComponentId': '',
        });

        // Single click on GoToPageAction button (wait past kDoubleTapTimeout).
        await tapAtTime(
          tester,
          find.text('Double-clic Page'),
          const Duration(milliseconds: 600),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.text('Page Details Ouverte'), findsNothing);

        // Double-tap on RunJavaScriptAction button -> executes!
        await performDoubleTap(
          tester,
          find.text('Double-clic Script'),
          startTime: const Duration(milliseconds: 1200),
        );
        expect(store.peekDocument('dbl_repo')?.document, {
          'doubleTapRuns': 1,
          'lastEvent': 'onDoubleTap',
          'lastComponentId': 'js_dbl_btn',
        });

        // Double-tap on GoToPageAction button -> navigates!
        await performDoubleTap(
          tester,
          find.text('Double-clic Page'),
          startTime: const Duration(milliseconds: 2000),
        );
        expect(find.text('Page Details Ouverte'), findsOneWidget);
      },
    );
  });

  group('Form validation guard (AllBehaviorValidator)', () {
    testWidgets(
      'blocks Submit until email is filled & valid AND terms checkbox is checked',
      (tester) async {
        final store = obtainStore();
        listenEvents(['form.submitted']);
        store.registerRepository(
          RepositoryImpl(
            id: 'form_repo',
            json: {'email': '', 'terms': false, 'submitCount': 0},
          ),
        );

        final formGuard = AllBehaviorValidator(
          validators: const [
            ValueBehaviorValidator.otherIsFill('email'),
            ValueBehaviorValidator.otherIsValid('email'),
            ValueBehaviorValidator.otherIsTrue('terms'),
          ],
        );

        await mountInSuperApp(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SuperValue(
                id: 'email',
                config: const SuperValueConfig(
                  mode: SuperValueMode.input,
                  label: 'Email',
                  binding: JsonTextBinding(
                    repositoryId: 'form_repo',
                    path: 'email',
                  ),
                  field: SuperTextFieldConfig(
                    required: true,
                    format: TextFieldFormat.email,
                  ),
                ),
              ),
              SuperValue(
                id: 'terms',
                config: const SuperValueConfig(
                  kind: SuperValueKind.checkbox,
                  mode: SuperValueMode.input,
                  label: 'Accepter les conditions',
                  binding: JsonTextBinding(
                    repositoryId: 'form_repo',
                    path: 'terms',
                  ),
                ),
              ),
              SuperAction(
                id: 'submit_btn',
                config: const SuperActionConfig(label: 'Soumettre'),
                behaviours: [
                  ComponentBehavior(
                    id: 'b_submit_event',
                    event: BehaviorEvent.onTap,
                    validator: formGuard,
                    action: EmitEventAction(eventId: 'form.submitted'),
                  ),
                  ComponentBehavior(
                    id: 'b_submit_js',
                    event: BehaviorEvent.onTap,
                    validator: formGuard,
                    action: const RunJavaScriptAction(
                      repositoryId: 'form_repo',
                      code: 'mark_form_submitted',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        final emailInput = find.byKey(
          const ValueKey('super-value-input-email'),
        );
        final termsCheckbox = find.byKey(
          const ValueKey('super-value-checkbox-terms'),
        );
        final submitButton = find.text('Soumettre');

        // 1. Empty form -> blocked.
        await tester.tap(submitButton);
        await tester.pumpAndSettle();
        expect(events, isEmpty);
        expect(
          (store.peekDocument('form_repo')?.document as Map)['submitCount'],
          0,
        );

        // 2. Email invalid (even when terms is checked) -> blocked by otherIsValid('email').
        await tester.enterText(emailInput, 'not-an-email');
        await tester.pumpAndSettle();
        await tester.tap(termsCheckbox);
        await tester.pumpAndSettle();
        await tester.tap(submitButton);
        await tester.pumpAndSettle();
        expect(events, isEmpty);
        expect(
          (store.peekDocument('form_repo')?.document as Map)['submitCount'],
          0,
        );

        // Uncheck terms, then enter a valid email -> blocked by otherIsTrue('terms').
        await tester.tap(termsCheckbox);
        await tester.pumpAndSettle();
        await tester.enterText(emailInput, 'alice@example.com');
        await tester.pumpAndSettle();
        await tester.tap(submitButton);
        await tester.pumpAndSettle();
        expect(events, isEmpty);
        expect(
          (store.peekDocument('form_repo')?.document as Map)['submitCount'],
          0,
        );

        // 4. Check terms while email is filled and valid -> executes!
        await tester.tap(termsCheckbox);
        await tester.pumpAndSettle();
        await tester.tap(submitButton);
        await tester.pumpAndSettle();
        expect(events, hasLength(1));
        expect(events.single.eventId, 'form.submitted');
        expect(
          (store.peekDocument('form_repo')?.document as Map)['submitCount'],
          1,
        );
      },
    );
  });

  group('Collection events & row-scoped validators', () {
    testWidgets(
      'SuperListView dispatches onSelected on list and <listId>:item with row-scoped validators and exposes list emptiness to otherIsEmpty/otherIsFill',
      (tester) async {
        final store = obtainStore();
        listenEvents([
          'list.selected',
          'item.binding.selected',
          'item.comp.selected',
          'check.has_items',
          'check.is_empty',
        ]);
        store.registerRepository(
          RepositoryImpl(
            id: 'shop_repo',
            json: {
              'items': [
                {'title': 'Sans code', 'code': ''},
                {'title': 'Avec code', 'code': 'PROMO-25'},
              ],
            },
          ),
        );

        final appearance = Appearance(
          behaviors: {
            'orders_list:item': [
              ComponentBehavior(
                id: 'row_binding_guard',
                event: BehaviorEvent.onSelected,
                validator: const ValueBehaviorValidator.bindingIsFill(
                  JsonTextBinding(path: 'items[?].code'),
                ),
                action: EmitEventAction(eventId: 'item.binding.selected'),
              ),
              ComponentBehavior(
                id: 'row_comp_guard',
                event: BehaviorEvent.onSelected,
                validator: const ValueBehaviorValidator.otherIsFill('row_code'),
                action: EmitEventAction(eventId: 'item.comp.selected'),
              ),
            ],
          },
        );

        await mountInSuperApp(
          tester,
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SuperAction(
                      id: 'btn_when_filled',
                      config: const SuperActionConfig(label: 'ActionSiRempli'),
                      behaviours: [
                        ComponentBehavior(
                          id: 'b_has_items',
                          event: BehaviorEvent.onTap,
                          validator: const ValueBehaviorValidator.otherIsFill(
                            'orders_list',
                          ),
                          action: EmitEventAction(eventId: 'check.has_items'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SuperAction(
                      id: 'btn_when_empty',
                      config: const SuperActionConfig(label: 'ActionSiVide'),
                      behaviours: [
                        ComponentBehavior(
                          id: 'b_is_empty',
                          event: BehaviorEvent.onTap,
                          validator: const ValueBehaviorValidator.otherIsEmpty(
                            'orders_list',
                          ),
                          action: EmitEventAction(eventId: 'check.is_empty'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SuperListView(
                  id: 'orders_list',
                  config: const SuperListViewConfig(
                    binding: JsonTextBinding(
                      repositoryId: 'shop_repo',
                      path: 'items',
                    ),
                    itemExtent: 56,
                    animateSelectionAndHover: false,
                  ),
                  template: const SuperLayoutConfig(
                    placements: {
                      SuperLayoutZone.center: ['row_title', 'row_code'],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'row_title',
                      label: 'Titre',
                      showLabel: false,
                      builder: (_) => const SuperValue(
                        id: 'row_title',
                        config: SuperValueConfig(
                          binding: JsonTextBinding(path: 'items[?].title'),
                        ),
                      ),
                    ),
                    BuilderSlot(
                      id: 'row_code',
                      label: 'Code',
                      showLabel: false,
                      builder: (_) => const SuperValue(
                        id: 'row_code',
                        config: SuperValueConfig(
                          binding: JsonTextBinding(path: 'items[?].code'),
                        ),
                      ),
                    ),
                  ],
                  behaviours: [
                    ComponentBehavior(
                      id: 'list_on_sel',
                      event: BehaviorEvent.onSelected,
                      action: EmitEventAction(eventId: 'list.selected'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          initialAppearance: appearance,
        );

        // Click Row 0 (empty code): list.selected fires, but BOTH row-scoped item behaviors are blocked!
        await tester.tap(find.text('Sans code'));
        await tester.pumpAndSettle();
        expect(
          events.where((e) => e.eventId == 'list.selected').map((e) => e.data),
          [
            {'index': 0},
          ],
        );
        expect(
          events.where((e) => e.eventId == 'item.binding.selected'),
          isEmpty,
        );
        expect(events.where((e) => e.eventId == 'item.comp.selected'), isEmpty);

        // Click Row 1 (filled code 'PROMO-25'): list.selected AND both row-scoped item behaviors fire!
        events.clear();
        await tester.tap(find.text('Avec code'));
        await tester.pumpAndSettle();
        expect(events.where((e) => e.eventId == 'list.selected').single.data, {
          'index': 1,
          'previousIndex': 0,
        });
        final rowBindingEv = events
            .where((e) => e.eventId == 'item.binding.selected')
            .single;
        expect(rowBindingEv.componentId, 'orders_list:item');
        expect(rowBindingEv.componentType, 'iterableContent');
        expect(rowBindingEv.data, {'index': 1, 'previousIndex': 0});

        final rowCompEv = events
            .where((e) => e.eventId == 'item.comp.selected')
            .single;
        expect(rowCompEv.componentId, 'orders_list:item');
        expect(rowCompEv.data, {'index': 1, 'previousIndex': 0});

        // List currently has 2 items -> otherIsFill('orders_list') passes, otherIsEmpty('orders_list') blocks.
        events.clear();
        await tester.tap(find.text('ActionSiRempli'));
        await tester.tap(find.text('ActionSiVide'));
        await tester.pumpAndSettle();
        expect(
          events.where((e) => e.eventId == 'check.has_items'),
          hasLength(1),
        );
        expect(events.where((e) => e.eventId == 'check.is_empty'), isEmpty);

        // Empty the repository array -> otherIsFill('orders_list') blocks, otherIsEmpty('orders_list') passes!
        await store.replaceDocumentById('shop_repo', {'items': <Object?>[]});
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();
        events.clear();
        await tester.tap(find.text('ActionSiRempli'));
        await tester.tap(find.text('ActionSiVide'));
        await tester.pumpAndSettle();
        expect(events.where((e) => e.eventId == 'check.has_items'), isEmpty);
        expect(
          events.where((e) => e.eventId == 'check.is_empty'),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'SuperTable dispatches onSelected with {index, previousIndex} when selecting rows',
      (tester) async {
        final store = obtainStore();
        listenEvents(['table.selected']);
        store.registerRepository(
          RepositoryImpl(
            id: 'crm_repo',
            json: {
              'clients': [
                {'nom': 'Alice', 'ville': 'Paris'},
                {'nom': 'Bob', 'ville': 'Lyon'},
              ],
            },
          ),
        );

        await mountInSuperApp(
          tester,
          SuperTable(
            id: 'clients_table',
            config: SuperTableConfig(
              binding: const JsonTextBinding(
                repositoryId: 'crm_repo',
                path: 'clients',
              ),
              columns: const [
                SuperTableColumnConfig(id: 'col_nom', title: 'Nom', width: 200),
                SuperTableColumnConfig(
                  id: 'col_ville',
                  title: 'Ville',
                  width: 200,
                ),
              ],
              placements: const {
                'cell:col_nom': ['cell:col_nom'],
                'cell:col_ville': ['cell:col_ville'],
              },
              animateSelectionAndHover: false,
            ),
            cells: const {
              'col_nom': SuperValue(
                id: 'val_nom',
                config: SuperValueConfig(
                  binding: JsonTextBinding(path: 'clients[?].nom'),
                ),
              ),
              'col_ville': SuperValue(
                id: 'val_ville',
                config: SuperValueConfig(
                  binding: JsonTextBinding(path: 'clients[?].ville'),
                ),
              ),
            },
            behaviours: [
              ComponentBehavior(
                id: 'table_sel',
                event: BehaviorEvent.onSelected,
                action: EmitEventAction(eventId: 'table.selected'),
              ),
            ],
          ),
        );

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();
        expect(events, hasLength(1));
        expect(events.single.componentId, 'clients_table');
        expect(events.single.componentType, 'table');
        expect(events.single.data, {'index': 0});

        events.clear();
        await tester.tap(find.text('Bob'));
        await tester.pumpAndSettle();
        expect(events, hasLength(1));
        expect(events.single.data, {'index': 1, 'previousIndex': 0});

        events.clear();
        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();
        expect(events, hasLength(1));
        expect(events.single.data, {'index': 0, 'previousIndex': 1});
      },
    );

    testWidgets(
      'SuperTreeView dispatches onSelected on node click and onCollapsed / onExpanded on node toggle',
      (tester) async {
        final store = obtainStore();
        listenEvents(['tree.selected', 'tree.expanded', 'tree.collapsed']);
        store.registerRepository(
          RepositoryImpl(
            id: 'tree_repo',
            json: {
              'nodes': [
                {
                  'key': 'Parent 1',
                  'data': 'Root A',
                  'children': [
                    {'key': 'Child 1.1', 'data': 'Leaf A1', 'children': []},
                  ],
                },
                {'key': 'Parent 2', 'data': 'Leaf B', 'children': []},
              ],
            },
          ),
        );

        await mountInSuperApp(
          tester,
          SuperTreeView(
            id: 'catalog_tree',
            config: SuperTreeViewConfig(
              binding: const JsonTextBinding(
                repositoryId: 'tree_repo',
                path: 'nodes',
              ),
              childrenKey: 'children',
              headerSize: 220,
              rowHeight: 36,
              initiallyExpanded: true,
              animateSelectionAndHover: false,
              placements: const {
                SuperTreeViewConfig.headerZone: ['header'],
                SuperTreeViewConfig.dataZone: ['data'],
              },
            ),
            header: const SuperValue(
              id: 'tree_header',
              config: SuperValueConfig(binding: JsonTextBinding(path: 'key')),
            ),
            data: const SuperValue(
              id: 'tree_data',
              config: SuperValueConfig(binding: JsonTextBinding(path: 'data')),
            ),
            behaviours: [
              ComponentBehavior(
                id: 'tree_sel',
                event: BehaviorEvent.onSelected,
                action: EmitEventAction(eventId: 'tree.selected'),
              ),
              ComponentBehavior(
                id: 'tree_exp',
                event: BehaviorEvent.onExpanded,
                action: EmitEventAction(eventId: 'tree.expanded'),
              ),
              ComponentBehavior(
                id: 'tree_col',
                event: BehaviorEvent.onCollapsed,
                action: EmitEventAction(eventId: 'tree.collapsed'),
              ),
            ],
          ),
        );

        // Click Parent 1 -> onSelected without previousNodePath
        await tester.tap(find.text('Parent 1'));
        await tester.pumpAndSettle();
        expect(events.where((e) => e.eventId == 'tree.selected').single.data, {
          'nodePath': 'nodes[0]',
          'rootIndex': 0,
        });
        expect(events.where((e) => e.eventId == 'tree.expanded'), isEmpty);
        expect(events.where((e) => e.eventId == 'tree.collapsed'), isEmpty);

        // Click Child 1.1 (and its empty toggle column area) -> onSelected with previousNodePath, no toggle events on leaf
        events.clear();
        final toggleX = tester.getCenter(find.byIcon(Icons.arrow_drop_down)).dx;
        final leafRowY = tester
            .getCenter(
              find.byKey(
                const ValueKey(
                  'super-tree-row-catalog_tree-nodes[0].children[0]',
                ),
              ),
            )
            .dy;
        await tester.tapAt(Offset(toggleX, leafRowY));
        await tester.pumpAndSettle();
        expect(events.where((e) => e.eventId == 'tree.selected').single.data, {
          'nodePath': 'nodes[0].children[0]',
          'rootIndex': 0,
          'previousNodePath': 'nodes[0]',
        });
        expect(events.where((e) => e.eventId == 'tree.expanded'), isEmpty);
        expect(events.where((e) => e.eventId == 'tree.collapsed'), isEmpty);

        // Collapse Parent 1 via toggle arrow -> emits onCollapsed
        events.clear();
        await tester.tap(find.byIcon(Icons.arrow_drop_down));
        await tester.pumpAndSettle();
        final collapsedEv = events
            .where((e) => e.eventId == 'tree.collapsed')
            .single;
        expect(collapsedEv.componentId, 'catalog_tree');
        expect(collapsedEv.componentType, 'treeView');
        expect(collapsedEv.data, {
          'nodePath': 'nodes[0]',
          'rootIndex': 0,
          'expanded': false,
        });

        // Expand Parent 1 via toggle arrow -> emits onExpanded
        events.clear();
        await tester.tap(find.byIcon(Icons.arrow_right_sharp));
        await tester.pumpAndSettle();
        final expandedEv = events
            .where((e) => e.eventId == 'tree.expanded')
            .single;
        expect(expandedEv.componentId, 'catalog_tree');
        expect(expandedEv.componentType, 'treeView');
        expect(expandedEv.data, {
          'nodePath': 'nodes[0]',
          'rootIndex': 0,
          'expanded': true,
        });
      },
    );

    testWidgets(
      'SuperTab dispatches onSelected with {index, previousIndex, tabId} when switching tabs',
      (tester) async {
        listenEvents(['tabs.selected', 'tab_b.selected']);

        await mountInSuperApp(
          tester,
          SuperTab(
            id: 'workspace_tabs',
            tabs: [
              SuperAction(
                id: 'tab_overview',
                config: const SuperActionConfig(label: 'Apercu'),
              ),
              SuperAction(
                id: 'tab_settings',
                config: const SuperActionConfig(label: 'Parametres'),
                behaviours: [
                  ComponentBehavior(
                    id: 'b_tab_b_sel',
                    event: BehaviorEvent.onSelected,
                    action: EmitEventAction(eventId: 'tab_b.selected'),
                  ),
                ],
              ),
            ],
            behaviours: [
              ComponentBehavior(
                id: 'b_tabs_sel',
                event: BehaviorEvent.onSelected,
                action: EmitEventAction(eventId: 'tabs.selected'),
              ),
            ],
            children: const [
              Center(child: Text('Contenu Apercu')),
              Center(child: Text('Contenu Parametres')),
            ],
          ),
        );

        await tester.tap(find.text('Parametres'));
        await tester.pumpAndSettle();
        final tabSel = events.where((e) => e.eventId == 'tabs.selected').single;
        expect(tabSel.componentId, 'workspace_tabs');
        expect(tabSel.componentType, 'tab');
        expect(tabSel.data, {
          'index': 1,
          'previousIndex': 0,
          'tabId': 'tab_settings',
        });
        expect(events.where((e) => e.eventId == 'tab_b.selected').single.data, {
          'index': 1,
          'previousIndex': 0,
        });

        events.clear();
        await tester.tap(find.text('Apercu'));
        await tester.pumpAndSettle();
        expect(events.where((e) => e.eventId == 'tabs.selected').single.data, {
          'index': 0,
          'previousIndex': 1,
          'tabId': 'tab_overview',
        });
      },
    );

    testWidgets(
      'SuperTab dynamic mode also includes tabId in onSelected payload',
      (tester) async {
        final store = obtainStore();
        listenEvents(['dyn_tabs.selected']);
        store.registerRepository(
          RepositoryImpl(
            id: 'tabs_repo',
            json: {
              'sections': [
                {'title': 'Section Une'},
                {'title': 'Section Deux'},
              ],
            },
          ),
        );

        await mountInSuperApp(
          tester,
          SuperTab(
            id: 'dyn_tabs',
            config: SuperTabConfig(
              mode: SuperTabMode.dynamic,
              binding: const JsonTextBinding(
                repositoryId: 'tabs_repo',
                path: 'sections',
              ),
              placements: const {
                SuperTabConfig.tabsZone: ['tpl_tab_btn'],
                SuperTabConfig.dynamicContentZone: ['tab-child:0'],
              },
            ),
            tab: SuperAction(
              id: 'tpl_tab_btn',
              config: const SuperActionConfig(
                label: 'Section',
                propertyBindings: {
                  SuperActionProperty.label: JsonTextBinding(
                    path: 'sections[?].title',
                  ),
                },
              ),
            ),
            behaviours: [
              ComponentBehavior(
                id: 'b_dyn_sel',
                event: BehaviorEvent.onSelected,
                action: EmitEventAction(eventId: 'dyn_tabs.selected'),
              ),
            ],
            children: const [
              SuperValue(
                id: 'dyn_tab_content',
                config: SuperValueConfig(
                  binding: JsonTextBinding(path: 'sections[?].title'),
                ),
              ),
            ],
          ),
        );

        await tester.tap(find.text('Section Deux'));
        await tester.pumpAndSettle();
        expect(events, hasLength(1));
        expect(events.single.componentId, 'dyn_tabs');
        expect(events.single.componentType, 'tab');
        expect(events.single.data, {
          'index': 1,
          'previousIndex': 0,
          'tabId': 'tpl_tab_btn',
        });
      },
    );
  });

  group('Anti-loop protection', () {
    testWidgets(
      'SuperValue onChanged -> RunJavaScriptAction writing to repository does not trigger an infinite loop',
      (tester) async {
        final store = obtainStore();
        store.registerRepository(
          RepositoryImpl(
            id: 'loop_repo',
            json: {'a': '', 'b': '', 'scriptRuns': 0},
          ),
        );

        await mountInSuperApp(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SuperValue(
                id: 'field_a',
                config: const SuperValueConfig(
                  mode: SuperValueMode.input,
                  binding: JsonTextBinding(
                    repositoryId: 'loop_repo',
                    path: 'a',
                  ),
                ),
                behaviours: const [
                  ComponentBehavior(
                    id: 'a_to_b',
                    event: BehaviorEvent.onChanged,
                    action: RunJavaScriptAction(
                      repositoryId: 'loop_repo',
                      code: 'sync_a_to_b',
                    ),
                  ),
                ],
              ),
              SuperValue(
                id: 'field_b',
                config: const SuperValueConfig(
                  mode: SuperValueMode.input,
                  binding: JsonTextBinding(
                    repositoryId: 'loop_repo',
                    path: 'b',
                  ),
                ),
                behaviours: const [
                  ComponentBehavior(
                    id: 'b_to_a',
                    event: BehaviorEvent.onChanged,
                    action: RunJavaScriptAction(
                      repositoryId: 'loop_repo',
                      code: 'sync_b_to_a',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        await tester.enterText(
          find.byKey(const ValueKey('super-value-input-field_a')),
          'hello',
        );
        // Wait past binding debounce (350ms) and let all microtasks/frames settle.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(jsEvaluator.actionExecutions, 1);
        expect(
          store.peekDocument('loop_repo')?.document,
          {'a': 'hello', 'b': 'HELLO', 'scriptRuns': 1},
          reason:
              'activeMutations=${store.hasActiveMutations}, err=${store.errors.value}, execs=${jsEvaluator.actionExecutions}',
        );
        expect(
          ComponentRuntimeValueRegistry.instance
              .resolve('field_b')
              ?.readValue(),
          'HELLO',
        );
      },
    );
  });
}
