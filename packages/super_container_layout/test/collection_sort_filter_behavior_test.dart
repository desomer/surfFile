import 'dart:convert';
import 'dart:io' show Directory;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channels = [
    MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];

  JsonRepositoryStore? activeStore;
  Directory? tempDir;

  Future<({JsonRepositoryStore store, String repoId})> createStore(
    String name,
    Map<String, Object?> data,
  ) async {
    tempDir ??= Directory.systemTemp.createTempSync('scl_sort_filter_test_');
    final store = activeStore ??= JsonRepositoryStore(tempDir!);
    await store.create(name);
    final repoId = await store.idOf(name);
    await store.save(
      name,
      jsonEncode(data),
      expectedText: await store.read(name),
    );
    await store.readDocument(repoId);
    return (store: store, repoId: repoId);
  }

  Future<void> flushReal(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
  }

  setUp(() {
    ComponentRuntimeValueRegistry.instance.clear();
    CollectionViewStateRegistry.instance.clear();
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    activeStore?.dispose();
    activeStore = null;
    if (tempDir != null && tempDir!.existsSync()) {
      tempDir!.deleteSync(recursive: true);
    }
    tempDir = null;
    ComponentRuntimeValueRegistry.instance.clear();
    CollectionViewStateRegistry.instance.clear();
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('ValueBehaviorValidator dynamic comparison & case sensitivity', () {
    test('JSON roundtrip, compact JSON, validation and remapComponentIds', () {
      const compValidator = ValueBehaviorValidator(
        source: BehaviorValueSource.binding,
        operator: BehaviorValidatorOperator.contains,
        binding: JsonTextBinding(path: 'clients[?].nom'),
        expectedComponentId: 'search-input',
        caseSensitive: false,
      );

      final json = compValidator.toJson();
      expect(json, {
        'type': 'bindingContains',
        'binding': {'path': 'clients[?].nom'},
        'expectedComponentId': 'search-input',
        'caseSensitive': false,
      });
      final decoded = BehaviorValidatorCatalog.decode(json);
      expect(decoded, compValidator);
      expect(decoded.referencedComponentIds, {'search-input'});
      expect(decoded.referencedBindings, [
        const JsonTextBinding(path: 'clients[?].nom'),
      ]);

      final remapped = compValidator.remapComponentIds({
        'search-input': 'search-input-copy',
      });
      expect(remapped.expectedComponentId, 'search-input-copy');

      final compact = compValidator.toCompactJson();
      expect(compact['binding'], 'clients[?].nom');
      expect(compact['expectedComponentId'], 'search-input');
      expect(compact['caseSensitive'], false);
      expect(BehaviorValidatorCatalog.decode(compact), compValidator);

      const bindingExpected = ValueBehaviorValidator(
        source: BehaviorValueSource.binding,
        operator: BehaviorValidatorOperator.equals,
        binding: JsonTextBinding(path: 'clients[?].categorie'),
        expectedBinding: JsonTextBinding(
          repositoryId: 'filtres',
          path: 'categorie',
        ),
        caseSensitive: false,
      );
      expect(
        BehaviorValidatorCatalog.decode(bindingExpected.toJson()),
        bindingExpected,
      );
      expect(bindingExpected.referencedBindings.length, 2);

      // Mutual exclusivity & invalid configurations.
      expect(
        () => const ValueBehaviorValidator(
          source: BehaviorValueSource.self,
          operator: BehaviorValidatorOperator.equals,
          expectedValue: 'a',
          expectedComponentId: 'other',
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => const ValueBehaviorValidator(
          source: BehaviorValueSource.self,
          operator: BehaviorValidatorOperator.equals,
          expectedComponentId: 'other',
          expectedBinding: JsonTextBinding(path: 'x'),
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => const ValueBehaviorValidator(
          source: BehaviorValueSource.self,
          operator: BehaviorValidatorOperator.isFill,
          expectedComponentId: 'other',
        ).validate(),
        throwsFormatException,
      );
    });

    testWidgets(
      'BehaviorValidatorEvaluator evaluates dynamic expectedComponentId, expectedBinding and caseSensitive',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final valueRegistry = ComponentRuntimeValueRegistry();
        final token = Object();
        valueRegistry.register(
          ComponentRuntimeValueEntry(
            token: token,
            componentId: 'search-box',
            componentType: 'value',
            readValue: () => 'dup',
          ),
        );

        final created = (await tester.runAsync(
          () => createStore('filters', {'status': 'ACTIF'}),
        ))!;
        final store = created.store;
        final repoId = created.repoId;
        final ctx = BehaviorValidationContext(
          context: capturedContext,
          componentId: 'row',
          componentType: 'listView',
          event: BehaviorEvent.onBinding,
          executionData: {'value': 'Dupont'},
          repositoryStore: store,
          valueRegistry: valueRegistry,
        );

        const insensitive = ValueBehaviorValidator(
          source: BehaviorValueSource.self,
          operator: BehaviorValidatorOperator.contains,
          expectedComponentId: 'search-box',
          caseSensitive: false,
        );
        const sensitive = ValueBehaviorValidator(
          source: BehaviorValueSource.self,
          operator: BehaviorValidatorOperator.contains,
          expectedComponentId: 'search-box',
          caseSensitive: true,
        );
        expect(
          BehaviorValidatorEvaluator.tryEvaluateSync(insensitive, ctx),
          isTrue,
        );
        expect(
          await BehaviorValidatorEvaluator.evaluate(insensitive, ctx),
          isTrue,
        );
        expect(
          BehaviorValidatorEvaluator.tryEvaluateSync(sensitive, ctx),
          isFalse,
        );

        final bindingInsensitive = ValueBehaviorValidator(
          source: BehaviorValueSource.self,
          operator: BehaviorValidatorOperator.equals,
          expectedBinding: JsonTextBinding(
            repositoryId: repoId,
            path: 'status',
          ),
          caseSensitive: false,
        );
        final statusCtx = BehaviorValidationContext(
          context: capturedContext,
          componentId: 'row',
          componentType: 'listView',
          event: BehaviorEvent.onBinding,
          executionData: {'value': 'actif'},
          repositoryStore: store,
          valueRegistry: valueRegistry,
        );
        expect(
          await tester.runAsync(
            () => BehaviorValidatorEvaluator.evaluate(
              bindingInsensitive,
              statusCtx,
            ),
          ),
          isTrue,
        );
      },
    );
  });

  group('SortCollectionAction & FilterCollectionAction models & codegen', () {
    test('SortCollectionAction serialization, validation and remapComponentIds', () {
      final declarativeSort = ComponentBehavior(
        id: 'sort-decl',
        event: BehaviorEvent.onBinding,
        validator: const ValueBehaviorValidator.otherEquals('sort-mode', 'prix'),
        action: SortCollectionAction(
          criteria: const [
            CollectionSortCriterion(
              path: 'prix',
              direction: CollectionSortDirection.desc,
            ),
            CollectionSortCriterion(
              path: 'nom',
              direction: CollectionSortDirection.asc,
            ),
          ],
        ),
      );
      expect(
        ComponentBehavior.fromJson(declarativeSort.toJson()),
        declarativeSort,
      );
      expect(
        ComponentBehavior.fromJson(declarativeSort.toCompactJson()),
        declarativeSort,
      );

      // Single-criterion compact shorthand roundtrip.
      final singleSort = ComponentBehavior(
        id: 'sort-imp',
        event: BehaviorEvent.onTap,
        action: SortCollectionAction.single(
          path: 'nom',
          direction: CollectionSortDirection.toggle,
          targetComponentId: 'clients-table',
        ),
      );
      final compact = singleSort.toCompactJson();
      final actionJson = compact['action']! as Map<String, Object?>;
      expect(actionJson['path'], 'nom');
      expect(actionJson['direction'], 'toggle');
      expect(actionJson['targetComponentId'], 'clients-table');
      expect(ComponentBehavior.fromJson(compact), singleSort);

      final remapped = singleSort.remapComponentIds({
        'clients-table': 'clients-table-2',
      });
      expect(
        (remapped.action as SortCollectionAction).targetComponentId,
        'clients-table-2',
      );

      // Validation guards for declarative mode.
      expect(
        () => ComponentBehavior(
          id: 'bad-toggle',
          event: BehaviorEvent.onBinding,
          action: SortCollectionAction.single(
            path: 'nom',
            direction: CollectionSortDirection.toggle,
          ),
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => ComponentBehavior(
          id: 'bad-clear',
          event: BehaviorEvent.onBinding,
          action: const SortCollectionAction.clear(),
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => ComponentBehavior(
          id: 'bad-target',
          event: BehaviorEvent.onBinding,
          action: SortCollectionAction.single(
            path: 'nom',
            targetComponentId: 'list-1',
          ),
        ).validate(),
        throwsFormatException,
      );
    });

    test('FilterCollectionAction serialization, validation and remapComponentIds', () {
      // Declarative filter using behavior.validator directly as row predicate.
      final declDirect = ComponentBehavior(
        id: 'filter-decl-direct',
        event: BehaviorEvent.onBinding,
        validator: const ValueBehaviorValidator.bindingEquals(
          JsonTextBinding(path: 'clients[?].statut'),
          'actif',
        ),
        action: const FilterCollectionAction(),
      );
      expect(ComponentBehavior.fromJson(declDirect.toJson()), declDirect);
      expect(
        ComponentBehavior.fromJson(declDirect.toCompactJson()),
        declDirect,
      );

      // Declarative guarded filter (behavior.validator = guard, predicate = row filter).
      final declGuarded = ComponentBehavior(
        id: 'filter-decl-guarded',
        event: BehaviorEvent.onBinding,
        validator: const ValueBehaviorValidator.otherIsFill('search-input'),
        action: const FilterCollectionAction(
          predicate: ValueBehaviorValidator(
            source: BehaviorValueSource.binding,
            operator: BehaviorValidatorOperator.contains,
            binding: JsonTextBinding(path: 'clients[?].nom'),
            expectedComponentId: 'search-input',
            caseSensitive: false,
          ),
        ),
      );
      expect(ComponentBehavior.fromJson(declGuarded.toJson()), declGuarded);
      final remapped = declGuarded.remapComponentIds({
        'search-input': 'search-copy',
      });
      expect(
        (remapped.validator! as ValueBehaviorValidator).targetComponentId,
        'search-copy',
      );
      expect(
        ((remapped.action as FilterCollectionAction).predicate!
                as ValueBehaviorValidator)
            .expectedComponentId,
        'search-copy',
      );

      // Imperative filter with targetComponentId & filterKey.
      final impFilter = ComponentBehavior(
        id: 'filter-imp',
        event: BehaviorEvent.onTap,
        action: const FilterCollectionAction(
          mode: CollectionFilterMode.toggle,
          targetComponentId: 'clients-list',
          filterKey: 'vip',
          predicate: ValueBehaviorValidator.bindingEquals(
            JsonTextBinding(path: 'clients[?].vip'),
            true,
          ),
        ),
      );
      expect(ComponentBehavior.fromJson(impFilter.toJson()), impFilter);

      // Invalid declarative filter with neither predicate nor validator.
      expect(
        () => const ComponentBehavior(
          id: 'bad-empty-filter',
          event: BehaviorEvent.onBinding,
          action: FilterCollectionAction(),
        ).validate(),
        throwsFormatException,
      );

      // Invalid imperative apply filter without predicate.
      expect(
        () => const ComponentBehavior(
          id: 'bad-imp-filter',
          event: BehaviorEvent.onTap,
          action: FilterCollectionAction(targetComponentId: 'clients-list'),
        ).validate(),
        throwsFormatException,
      );
    });

    test('DartCodegenContext formats sort/filter actions and dynamic validators', () {
      final ctx = DartCodegenContext(
        appearance: Appearance(),
        registry: Registry(),
      );
      final sortCode = ctx.formatBehaviorAction(
        SortCollectionAction.single(
          path: 'prix',
          direction: CollectionSortDirection.desc,
          targetComponentId: 'clients-table',
        ),
      );
      expect(sortCode, contains('SortCollectionAction'));
      expect(sortCode, contains('CollectionSortCriterion'));
      expect(sortCode, contains('CollectionSortDirection.desc'));
      expect(sortCode, contains("'clients-table'"));

      final filterCode = ctx.formatBehaviorAction(
        const FilterCollectionAction(
          mode: CollectionFilterMode.toggle,
          targetComponentId: 'clients-list',
          filterKey: 'search',
          predicate: ValueBehaviorValidator(
            source: BehaviorValueSource.binding,
            operator: BehaviorValidatorOperator.contains,
            binding: JsonTextBinding(path: 'clients[?].nom'),
            expectedComponentId: 'search-input',
            caseSensitive: false,
          ),
        ),
      );
      expect(filterCode, contains('FilterCollectionAction'));
      expect(filterCode, contains('CollectionFilterMode.toggle'));
      expect(filterCode, contains("expectedComponentId: 'search-input'"));
      expect(filterCode, contains('caseSensitive: false'));
    });
  });

  group('SuperListView sorting & filtering via behaviors & validators', () {
    Widget buildListHost({
      required JsonRepositoryStore store,
      required String repoId,
      required List<ComponentBehavior> listBehaviors,
      List<ComponentBehavior> buttonBehaviors = const [],
      bool allowRemove = false,
      ValueNotifier<bool>? editMode,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: JsonRepositoryScope(
            store: store,
            child: StyleEditScope(
              controller: editMode ?? ValueNotifier<bool>(false),
              child: SizedBox(
                width: 700,
                height: 600,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: const SuperValue(
                            id: 'search-box',
                            config: SuperValueConfig(
                              mode: SuperValueMode.input,
                              label: 'Rechercher',
                            ),
                          ),
                        ),
                        Expanded(
                          child: const SuperValue(
                            id: 'sort-select',
                            config: SuperValueConfig(
                              mode: SuperValueMode.input,
                              label: 'Tri',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          height: 40,
                          child: SuperAction(
                            id: 'action-btn',
                            config: const SuperActionConfig(label: 'Action'),
                            behaviours: buttonBehaviors,
                          ),
                        ),
                      ],
                    ),
                    SuperValue(
                      id: 'detail-name',
                      config: SuperValueConfig(
                        binding: JsonTextBinding(
                          repositoryId: repoId,
                          path: 'clients[?].nom',
                        ),
                      ),
                    ),
                    Expanded(
                      child: SuperListView(
                        id: 'clients-list',
                        behaviours: listBehaviors,
                        config: SuperListViewConfig(
                          binding: JsonTextBinding(
                            repositoryId: repoId,
                            path: 'clients',
                          ),
                          itemExtent: 48,
                          allowRemove: allowRemove,
                          animateSelectionAndHover: false,
                        ),
                        template: SuperLayoutConfig(
                          placements: const {
                            SuperLayoutZone.center: ['row-nom'],
                          },
                        ),
                        slots: [
                          BuilderSlot(
                            id: 'row-nom',
                            label: 'Nom',
                            builder: (_) => const SuperValue(
                              id: 'row-nom',
                              config: SuperValueConfig(
                                binding: JsonTextBinding(
                                  path: 'clients[?].nom',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    List<String> renderedRowNames(WidgetTester tester) {
      final listFinder = find.byKey(const ValueKey('super-list-clients-list'));
      final textWidgets = tester
          .widgetList<Text>(
            find.descendant(of: listFinder, matching: find.byType(Text)),
          )
          .map((t) => t.data ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return textWidgets;
    }

    testWidgets(
      'Declarative filter (behavior.validator alone) and guarded dynamic search filter update live without mutating repository',
      (tester) async {
        final created = (await tester.runAsync(
          () => createStore('crm', {
            'clients': [
              {'nom': 'Charlie', 'statut': 'actif', 'prix': 200},
              {'nom': 'Alice', 'statut': 'inactif', 'prix': 50},
              {'nom': 'Bob', 'statut': 'actif', 'prix': 100},
              {'nom': 'alain', 'statut': 'actif', 'prix': 150},
            ],
          }),
        ))!;
        final store = created.store;
        final repoId = created.repoId;

        final editMode = ValueNotifier<bool>(false);
        addTearDown(editMode.dispose);

        await tester.pumpWidget(
          buildListHost(
            store: store,
            repoId: repoId,
            editMode: editMode,
            listBehaviors: [
              const ComponentBehavior(
                id: 'only-active',
                event: BehaviorEvent.onBinding,
                validator: ValueBehaviorValidator.bindingEquals(
                  JsonTextBinding(path: 'clients[?].statut'),
                  'actif',
                ),
                action: FilterCollectionAction(),
              ),
              const ComponentBehavior(
                id: 'search-filter',
                event: BehaviorEvent.onBinding,
                validator: ValueBehaviorValidator.otherIsFill('search-box'),
                action: FilterCollectionAction(
                  predicate: ValueBehaviorValidator(
                    source: BehaviorValueSource.binding,
                    operator: BehaviorValidatorOperator.contains,
                    binding: JsonTextBinding(path: 'clients[?].nom'),
                    expectedComponentId: 'search-box',
                    caseSensitive: false,
                  ),
                ),
              ),
            ],
          ),
        );
        await flushReal(tester);

        // Only active rows visible (Alice is inactive).
        expect(renderedRowNames(tester), ['Charlie', 'Bob', 'alain']);

        // Type 'AL' into search-box -> case-insensitive dynamic filter narrows to 'alain'.
        final searchField = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is SuperValue && w.id == 'search-box',
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(searchField, 'AL');
        await tester.pumpAndSettle();
        expect(renderedRowNames(tester), ['alain']);

        // Clear search -> guard becomes false, all active rows return.
        await tester.enterText(searchField, '');
        await tester.pumpAndSettle();
        expect(renderedRowNames(tester), ['Charlie', 'Bob', 'alain']);

        // Enter edit mode -> filter suspended, all 4 raw rows visible.
        editMode.value = true;
        await tester.pumpAndSettle();
        expect(renderedRowNames(tester), ['Charlie', 'Alice', 'Bob', 'alain']);

        // Exit edit mode -> filter active again.
        editMode.value = false;
        await tester.pumpAndSettle();
        expect(renderedRowNames(tester), ['Charlie', 'Bob', 'alain']);
      },
    );

    testWidgets(
      'Conditional declarative sort, imperative toggle sort, Master/Detail selection & delete preserve true sourceIndex',
      (tester) async {
        final created = (await tester.runAsync(
          () => createStore('crm2', {
            'clients': [
              {'nom': 'Charlie', 'statut': 'actif', 'prix': 200},
              {'nom': 'Alice', 'statut': 'inactif', 'prix': 50},
              {'nom': 'Bob', 'statut': 'actif', 'prix': 100},
            ],
          }),
        ))!;
        final store = created.store;
        final repoId = created.repoId;

        await tester.pumpWidget(
          buildListHost(
            store: store,
            repoId: repoId,
            allowRemove: true,
            listBehaviors: [
              const ComponentBehavior(
                id: 'only-active',
                event: BehaviorEvent.onBinding,
                validator: ValueBehaviorValidator.bindingEquals(
                  JsonTextBinding(path: 'clients[?].statut'),
                  'actif',
                ),
                action: FilterCollectionAction(),
              ),
              ComponentBehavior(
                id: 'sort-by-price-desc',
                event: BehaviorEvent.onBinding,
                validator: const ValueBehaviorValidator.otherEquals(
                  'sort-select',
                  'prix',
                ),
                action: SortCollectionAction.single(
                  path: 'prix',
                  direction: CollectionSortDirection.desc,
                ),
              ),
              ComponentBehavior(
                id: 'sort-by-name-asc',
                event: BehaviorEvent.onBinding,
                validator: const ValueBehaviorValidator.otherEquals(
                  'sort-select',
                  'nom',
                ),
                action: SortCollectionAction.single(
                  path: 'nom',
                  direction: CollectionSortDirection.asc,
                ),
              ),
            ],
            buttonBehaviors: [
              ComponentBehavior(
                id: 'imp-toggle-sort',
                event: BehaviorEvent.onTap,
                action: SortCollectionAction.single(
                  path: 'nom',
                  direction: CollectionSortDirection.toggle,
                  targetComponentId: 'clients-list',
                ),
              ),
            ],
          ),
        );
        await flushReal(tester);

        // Initially filtered (active only), unsorted: Charlie (idx 0), Bob (idx 2).
        expect(renderedRowNames(tester), ['Charlie', 'Bob']);

        // Activate declarative sort by name asc via sort-select.
        final sortField = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is SuperValue && w.id == 'sort-select',
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(sortField, 'nom');
        await tester.pumpAndSettle();
        expect(renderedRowNames(tester), ['Bob', 'Charlie']);

        // Tap first visual row ('Bob', which has sourceIndex = 2!).
        final listFinder = find.byKey(const ValueKey('super-list-clients-list'));
        await tester.tap(
          find.descendant(of: listFinder, matching: find.text('Bob')),
        );
        await tester.pumpAndSettle();

        // Master/Detail outside the list MUST show 'Bob' (sourceIndex 2), NOT 'Charlie' (index 0)!
        final detailFinder = find.byWidgetPredicate(
          (w) => w is SuperValue && w.id == 'detail-name',
        );
        expect(
          find.descendant(of: detailFinder, matching: find.text('Bob')),
          findsOneWidget,
        );
        expect(
          store.bindingOf(repoId).array('clients').indexFor(const []),
          2,
        );

        // Imperative button toggles sort on 'nom': 1st tap -> asc, 2nd tap -> desc.
        final actionBtn = find.byWidgetPredicate(
          (w) => w is SuperAction && w.id == 'action-btn',
        );
        await tester.tap(actionBtn);
        await tester.pumpAndSettle();
        expect(renderedRowNames(tester), ['Bob', 'Charlie']);

        await tester.tap(actionBtn);
        await tester.pumpAndSettle();
        expect(renderedRowNames(tester), ['Charlie', 'Bob']);

        // Delete Bob (visual row 1, sourceIndex 2) and confirm dialog.
        await tester.runAsync(() async {
          await tester.tap(
            find.byKey(const ValueKey('super-list-remove-clients-list-2')),
          );
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 120));
        });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 400));
          for (var i = 0; i < 4; i++) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 80));
          }
        });
        await tester.pumpAndSettle();

        // Repository must have removed Bob (sourceIndex 2), leaving Charlie & Alice.
        final remaining = (await tester.runAsync(
          () => store.readArray(repoId, 'clients'),
        ))!;
        expect(
          remaining.map((e) => (e! as Map)['nom']).toList(),
          ['Charlie', 'Alice'],
        );
      },
    );
  });

  group('SuperTable sorting & filtering via behaviors & validators', () {
    testWidgets(
      'Declarative filter + multi-criteria stable sort, imperative toggle, Master/Detail & edit-mode suspension',
      (tester) async {
        final created = (await tester.runAsync(
          () => createStore('orders', {
            'rows': [
              {'nom': 'Zoe', 'groupe': 'B', 'score': 10, 'actif': true},
              {'nom': 'Adam', 'groupe': 'A', 'score': 30, 'actif': false},
              {'nom': 'Bruno', 'groupe': 'A', 'score': 20, 'actif': true},
              {'nom': 'Alice', 'groupe': 'A', 'score': 10, 'actif': true},
            ],
          }),
        ))!;
        final store = created.store;
        final repoId = created.repoId;
        final editMode = ValueNotifier<bool>(false);
        addTearDown(editMode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: JsonRepositoryScope(
                store: store,
                child: StyleEditScope(
                  controller: editMode,
                  child: SizedBox(
                    width: 700,
                    height: 500,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 140,
                              height: 40,
                              child: SuperAction(
                                id: 'sort-name-btn',
                                config: const SuperActionConfig(
                                  label: 'Trier Nom',
                                ),
                                behaviours: [
                                  ComponentBehavior(
                                    id: 'table-sort-toggle',
                                    event: BehaviorEvent.onTap,
                                    action: SortCollectionAction.single(
                                      path: 'nom',
                                      direction: CollectionSortDirection.toggle,
                                      targetComponentId: 'orders-table',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 140,
                              height: 40,
                              child: SuperAction(
                                id: 'reset-sort-btn',
                                config: const SuperActionConfig(
                                  label: 'Reset Tri',
                                ),
                                behaviours: const [
                                  ComponentBehavior(
                                    id: 'table-sort-clear',
                                    event: BehaviorEvent.onTap,
                                    action: SortCollectionAction.clear(
                                      targetComponentId: 'orders-table',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SuperValue(
                          id: 'table-detail',
                          config: SuperValueConfig(
                            binding: JsonTextBinding(
                              repositoryId: repoId,
                              path: 'rows[?].nom',
                            ),
                          ),
                        ),
                        Expanded(
                          child: SuperTable(
                            id: 'orders-table',
                            behaviours: [
                              const ComponentBehavior(
                                id: 'table-filter-active',
                                event: BehaviorEvent.onBinding,
                                validator: ValueBehaviorValidator(
                                  source: BehaviorValueSource.binding,
                                  operator: BehaviorValidatorOperator.isTrue,
                                  binding: JsonTextBinding(
                                    path: 'rows[?].actif',
                                  ),
                                ),
                                action: FilterCollectionAction(),
                              ),
                              ComponentBehavior(
                                id: 'table-sort-multi',
                                event: BehaviorEvent.onBinding,
                                action: SortCollectionAction(
                                  criteria: const [
                                    CollectionSortCriterion(
                                      path: 'groupe',
                                      direction: CollectionSortDirection.asc,
                                    ),
                                    CollectionSortCriterion(
                                      path: 'score',
                                      direction: CollectionSortDirection.asc,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            config: SuperTableConfig(
                              binding: JsonTextBinding(
                                repositoryId: repoId,
                                path: 'rows',
                              ),
                              columns: const [
                                SuperTableColumnConfig(
                                  id: 'nom',
                                  title: 'Nom',
                                  width: 200,
                                ),
                              ],
                              placements: const {
                                'cell:nom': ['cell-nom'],
                              },
                              animateSelectionAndHover: false,
                            ),
                            slots: [
                              BuilderSlot(
                                id: 'cell-nom',
                                label: 'Nom',
                                builder: (_) => const SuperValue(
                                  id: 'cell-nom',
                                  config: SuperValueConfig(
                                    binding: JsonTextBinding(
                                      path: 'rows[?].nom',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await flushReal(tester);

        // Active rows sorted by (groupe asc, score asc):
        // Alice (A, 10, idx 3), Bruno (A, 20, idx 2), Zoe (B, 10, idx 0).
        // Adam (idx 1) is inactive so excluded.
        final tableFinder = find.byKey(
          const ValueKey('super-table-view-orders-table'),
        );
        Finder tableText(String text) =>
            find.descendant(of: tableFinder, matching: find.text(text));

        expect(tableText('Adam'), findsNothing);
        final yAlice = tester.getTopLeft(tableText('Alice')).dy;
        final yBruno = tester.getTopLeft(tableText('Bruno')).dy;
        final yZoe = tester.getTopLeft(tableText('Zoe')).dy;
        expect(yAlice, lessThan(yBruno));
        expect(yBruno, lessThan(yZoe));

        // Tap Alice (visual row 0, sourceIndex 3) -> Master/Detail shows 'Alice'.
        await tester.tap(tableText('Alice'));
        await tester.pumpAndSettle();
        expect(
          store.bindingOf(repoId).array('rows').indexFor(const []),
          3,
        );
        final detailFinder = find.byWidgetPredicate(
          (w) => w is SuperValue && w.id == 'table-detail',
        );
        expect(
          find.descendant(of: detailFinder, matching: find.text('Alice')),
          findsOneWidget,
        );

        // Imperative sort toggle on 'nom': 1st tap asc (Alice, Bruno, Zoe),
        // 2nd tap desc (Zoe, Bruno, Alice).
        await tester.tap(find.text('Trier Nom'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Trier Nom'));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(tableText('Zoe')).dy,
          lessThan(tester.getTopLeft(tableText('Alice')).dy),
        );

        // Reset imperative sort -> reverts to declarative (groupe asc, score asc).
        await tester.tap(find.text('Reset Tri'));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(tableText('Alice')).dy,
          lessThan(tester.getTopLeft(tableText('Zoe')).dy),
        );

        // Edit mode suspends filter & sort -> Adam reappears and Zoe (idx 0) is first!
        editMode.value = true;
        await tester.pumpAndSettle();
        expect(tableText('Adam'), findsOneWidget);
        expect(
          tester.getTopLeft(tableText('Zoe')).dy,
          lessThan(tester.getTopLeft(tableText('Adam')).dy),
        );
      },
    );

    testWidgets(
      'Imperative filter toggle & clearAll and in-place SuperTable cell editing write back to true sourceIndex',
      (tester) async {
        final created = (await tester.runAsync(
          () => createStore('orders_edit', {
            'rows': [
              {'nom': 'Zoe', 'vip': false},
              {'nom': 'Alice', 'vip': true},
              {'nom': 'Bruno', 'vip': true},
            ],
          }),
        ))!;
        final store = created.store;
        final repoId = created.repoId;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: JsonRepositoryScope(
                store: store,
                child: SizedBox(
                  width: 700,
                  height: 500,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 140,
                            height: 40,
                            child: SuperAction(
                              id: 'vip-toggle-btn',
                              config: const SuperActionConfig(label: 'VIP'),
                              behaviours: const [
                                ComponentBehavior(
                                  id: 'imp-vip-filter',
                                  event: BehaviorEvent.onTap,
                                  action: FilterCollectionAction(
                                    mode: CollectionFilterMode.toggle,
                                    targetComponentId: 'edit-table',
                                    filterKey: 'vip',
                                    predicate: ValueBehaviorValidator(
                                      source: BehaviorValueSource.binding,
                                      operator:
                                          BehaviorValidatorOperator.isTrue,
                                      binding: JsonTextBinding(
                                        path: 'rows[?].vip',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 160,
                            height: 40,
                            child: SuperAction(
                              id: 'clear-filters-btn',
                              config: const SuperActionConfig(
                                label: 'Effacer filtres',
                              ),
                              behaviours: const [
                                ComponentBehavior(
                                  id: 'imp-clear-all',
                                  event: BehaviorEvent.onTap,
                                  action: FilterCollectionAction.clearAll(
                                    targetComponentId: 'edit-table',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: SuperTable(
                          id: 'edit-table',
                          behaviours: [
                            ComponentBehavior(
                              id: 'sort-desc',
                              event: BehaviorEvent.onBinding,
                              action: SortCollectionAction.single(
                                path: 'nom',
                                direction: CollectionSortDirection.desc,
                              ),
                            ),
                          ],
                          config: SuperTableConfig(
                            binding: JsonTextBinding(
                              repositoryId: repoId,
                              path: 'rows',
                            ),
                            columns: const [
                              SuperTableColumnConfig(
                                id: 'nom',
                                title: 'Nom',
                                width: 220,
                              ),
                            ],
                            placements: const {
                              'cell:nom': ['edit-cell-nom'],
                            },
                            animateSelectionAndHover: false,
                          ),
                          slots: [
                            BuilderSlot(
                              id: 'edit-cell-nom',
                              label: 'Nom',
                              builder: (_) => const SuperValue(
                                id: 'edit-cell-nom',
                                config: SuperValueConfig(
                                  mode: SuperValueMode.input,
                                  binding: JsonTextBinding(path: 'rows[?].nom'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await flushReal(tester);

        // Toggle imperative VIP filter ON -> Zoe (vip=false) hidden, Bruno & Alice visible.
        await tester.tap(find.text('VIP'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Zoe'), findsNothing);
        expect(find.widgetWithText(TextField, 'Bruno'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Alice'), findsOneWidget);

        // Edit 'Bruno' (visual row 0 under desc sort, true sourceIndex = 2!).
        await tester.runAsync(() async {
          await tester.enterText(
            find.widgetWithText(TextField, 'Bruno'),
            'Bernard',
          );
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pumpAndSettle();

        final rowsAfterEdit = (await tester.runAsync(
          () => store.readArray(repoId, 'rows'),
        ))!;
        expect(
          rowsAfterEdit.map((e) => (e! as Map)['nom']).toList(),
          ['Zoe', 'Alice', 'Bernard'],
        );

        // Clear all imperative filters -> Zoe reappears.
        await tester.tap(find.text('Effacer filtres'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Zoe'), findsOneWidget);
      },
    );
  });

  group('Visual Editors for dynamic validators & collection sort/filter', () {
    testWidgets(
      'BehaviorValidatorEditor edits dynamic expectedComponentId and caseSensitive',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        BehaviorValidator? lastValidator;
        var lastValid = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BehaviorValidatorEditor(
                  validator: const ValueBehaviorValidator(
                    source: BehaviorValueSource.binding,
                    operator: BehaviorValidatorOperator.contains,
                    binding: JsonTextBinding(path: 'clients[?].nom'),
                    expectedValue: 'initial',
                  ),
                  availableTargets: const [
                    ValidatorTargetComponentOption(
                      id: 'search-input',
                      label: 'Recherche',
                      typeLabel: 'Valeur / Champ',
                      icon: Icons.text_fields_outlined,
                    ),
                  ],
                  onChanged: (v, valid) {
                    lastValidator = v;
                    lastValid = valid;
                  },
                ),
              ),
            ),
          ),
        );

        // Switch expected value mode to Component.
        final modeComp = find.byKey(
          const ValueKey('behavior-validator-expected-mode-component'),
        );
        await tester.ensureVisible(modeComp);
        await tester.tap(modeComp);
        await tester.pumpAndSettle();

        // Pick 'search-input'.
        final option = find.byKey(
          const ValueKey(
            'behavior-validator-expected-target-option-search-input',
          ),
        );
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();

        // Disable case sensitivity.
        final caseToggle = find.byKey(
          const ValueKey('behavior-validator-case-sensitive'),
        );
        await tester.ensureVisible(caseToggle);
        await tester.tap(caseToggle);
        await tester.pumpAndSettle();

        expect(lastValid, isTrue);
        expect(
          lastValidator,
          const ValueBehaviorValidator(
            source: BehaviorValueSource.binding,
            operator: BehaviorValidatorOperator.contains,
            binding: JsonTextBinding(path: 'clients[?].nom'),
            expectedComponentId: 'search-input',
            caseSensitive: false,
          ),
        );
      },
    );

    testWidgets(
      'ComponentBehaviorWizard creates a declarative SortCollectionAction on a SuperListView',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final appearance = ValueNotifier<Appearance>(
          Appearance(
            components: const {
              'clients-list': SuperListViewConfig(
                binding: JsonTextBinding(repositoryId: 'crm', path: 'clients'),
              ),
            },
          ),
        );
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: AppearanceScope(
              controller: appearance,
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showComponentBehaviorWizard(
                      context: context,
                      targets: const [
                        BehaviorTargetElement(
                          id: 'clients-list',
                          label: 'Clients',
                        ),
                      ],
                    ),
                    child: const Text('Ouvrir'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Ouvrir'));
        await tester.pumpAndSettle();

        // Step 1 -> Step 2 (Event).
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();

        // Pick onBinding.
        final onBindingCard = find.byKey(
          const ValueKey('behavior-event-onBinding'),
        );
        await tester.ensureVisible(onBindingCard);
        await tester.tap(onBindingCard);
        await tester.pumpAndSettle();

        // Step 2 -> Step 3 (Action).
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();

        // Pick sortCollection catalog item.
        final sortCard = find.byKey(
          const ValueKey('behavior-catalog-sort_collection'),
        );
        await tester.ensureVisible(sortCard);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: sortCard, matching: find.byType(InkWell)),
        );
        await tester.pumpAndSettle();

        // Enter sort path 'nom'.
        final pathField = find.byKey(const ValueKey('behavior-sort-path-0'));
        await tester.ensureVisible(pathField);
        await tester.enterText(pathField, 'nom');
        await tester.pumpAndSettle();

        // Step 3 -> Step 4 (Validator) -> Step 5 (Summary) -> Apply.
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('behavior-add-submit')));
        await tester.pumpAndSettle();

        final saved = appearance.value.behaviorsFor('clients-list');
        expect(saved, hasLength(1));
        expect(saved.single.event, BehaviorEvent.onBinding);
        expect(
          saved.single.action,
          SortCollectionAction.single(path: 'nom'),
        );
      },
    );
  });
}
