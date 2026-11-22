 import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channels = [
    MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('ComponentBehavior models', () {
    test('GoToPageAction serialization and execution', () {
      const action = GoToPageAction(
        pagePath: '/details',
        pageId: 'page-1',
        pageName: 'Détails',
      );
      expect(action.type, 'goToPage');
      expect(action.label, 'Aller à la page');
      expect(action.description, 'Détails (/details)');

      final json = action.toJson();
      expect(json['type'], 'goToPage');
      expect(json['pagePath'], '/details');
      expect(json['pageId'], 'page-1');
      expect(json['pageName'], 'Détails');

      final decoded = BehaviorActionCatalog.decode(json);
      expect(decoded, isA<GoToPageAction>());
      expect(decoded, equals(action));
      expect(decoded.hashCode, equals(action.hashCode));
    });

    test('ComponentBehavior serialization and catalog', () {
      const behavior = ComponentBehavior(
        id: 'b-1',
        trigger: BehaviorTrigger.click,
        action: GoToPageAction(pagePath: '/home'),
      );
      final json = behavior.toJson();
      final decoded = ComponentBehavior.fromJson(json);
      expect(decoded.id, 'b-1');
      expect(decoded.trigger, BehaviorTrigger.click);
      expect(decoded.action, isA<GoToPageAction>());
      expect((decoded.action as GoToPageAction).pagePath, '/home');
      expect(decoded, equals(behavior));

      expect(BehaviorCatalog.items, contains(BehaviorCatalog.goToPage));
      expect(BehaviorCatalog.items, contains(BehaviorCatalog.bindState));
    });

    test('BehaviorEvent parsing, legacy aliases and ComponentBehavior event/validator JSON', () {
      for (final event in BehaviorEvent.values) {
        expect(BehaviorEvent.fromJson(event.name), event);
        expect(BehaviorEvent.tryParse(event.name), event);
      }
      expect(BehaviorEvent.fromJson(null), BehaviorEvent.onTap);
      expect(BehaviorEvent.fromJson('click'), BehaviorEvent.onTap);
      expect(BehaviorEvent.fromJson('doubleClick'), BehaviorEvent.onDoubleTap);
      expect(BehaviorEvent.fromJson('hover'), BehaviorEvent.onHover);
      expect(BehaviorEvent.fromJson('binding'), BehaviorEvent.onBinding);
      expect(BehaviorEvent.fromJson('create'), BehaviorEvent.onCreate);
      expect(BehaviorEvent.onTap.legacyTriggerName, 'click');
      expect(BehaviorEvent.onDoubleTap.legacyTriggerName, 'doubleClick');
      expect(BehaviorEvent.onHover.legacyTriggerName, 'hover');
      expect(BehaviorEvent.onBinding.legacyTriggerName, 'binding');
      expect(BehaviorEvent.onCreate.legacyTriggerName, 'create');
      expect(BehaviorEvent.onSelected.legacyTriggerName, 'onSelected');
      expect(BehaviorEvent.tryParse(''), isNull);
      expect(BehaviorEvent.tryParse('unknownEvent'), isNull);
      expect(
        () => BehaviorEvent.fromJson('unknownEvent'),
        throwsFormatException,
      );
      expect(() => BehaviorEvent.fromJson(42), throwsFormatException);

      // Backwards compatibility with legacy "trigger" field in JSON
      final fromLegacy = ComponentBehavior.fromJson({
        'id': 'legacy-1',
        'trigger': 'doubleClick',
        'action': {'type': 'goToPage', 'pagePath': '/legacy'},
      });
      expect(fromLegacy.event, BehaviorEvent.onDoubleTap);
      expect(fromLegacy.trigger, BehaviorTrigger.doubleClick);
      expect(fromLegacy.validator, isNull);

      // toJson and toCompactJson emit "event" and "validator"
      const withValidator = ComponentBehavior(
        id: 'b-validated',
        event: BehaviorEvent.onDoubleTap,
        validator: ValueBehaviorValidator.otherIsFill('email-input'),
        action: GoToPageAction(pagePath: '/next'),
      );
      final fullJson = withValidator.toJson();
      expect(fullJson.containsKey('trigger'), isFalse);
      expect(fullJson['event'], 'onDoubleTap');
      expect(fullJson['enabled'], isTrue);
      expect(fullJson['validator'], {
        'type': 'otherIsFill',
        'targetComponentId': 'email-input',
      });

      final compactJson = withValidator.toCompactJson();
      expect(compactJson.containsKey('trigger'), isFalse);
      expect(compactJson.containsKey('enabled'), isFalse);
      expect(compactJson['event'], 'onDoubleTap');
      expect(compactJson['validator'], {
        'type': 'otherIsFill',
        'targetComponentId': 'email-input',
      });

      expect(ComponentBehavior.fromJson(fullJson), withValidator);
      expect(
        ComponentBehavior.fromJson(Map<String, dynamic>.from(compactJson)),
        withValidator,
      );
    });

    test('BehaviorValidator models, catalog decode, validation errors and remapComponentIds', () {
      const isEmpty = ValueBehaviorValidator.isEmpty();
      expect(BehaviorValidatorCatalog.decode(isEmpty.toJson()), isEmpty);

      const isFill = ValueBehaviorValidator.isFill();
      expect(BehaviorValidatorCatalog.decode(isFill.toJson()), isFill);
      expect(BehaviorValidatorCatalog.decode({'type': 'isFilled'}), isFill);
      expect(BehaviorValidatorCatalog.decode({'type': 'isNotEmpty'}), isFill);

      const otherEmpty = ValueBehaviorValidator.otherIsEmpty('comp-a');
      expect(BehaviorValidatorCatalog.decode(otherEmpty.toJson()), otherEmpty);

      const otherFill = ValueBehaviorValidator.otherIsFill('comp-a');
      expect(BehaviorValidatorCatalog.decode(otherFill.toJson()), otherFill);
      expect(
        BehaviorValidatorCatalog.decode({
          'type': 'otherIsFilled',
          'targetComponentId': 'comp-a',
        }),
        otherFill,
      );
      expect(
        BehaviorValidatorCatalog.decode({
          'type': 'otherIsNotEmpty',
          'targetComponentId': 'comp-a',
        }),
        otherFill,
      );

      const otherEq = ValueBehaviorValidator.otherEquals('comp-b', 'VIP');
      expect(BehaviorValidatorCatalog.decode(otherEq.toJson()), otherEq);
      expect(otherEq.toJson(), {
        'type': 'otherEquals',
        'targetComponentId': 'comp-b',
        'value': 'VIP',
      });

      const otherValid = ValueBehaviorValidator.otherIsValid('comp-c');
      expect(BehaviorValidatorCatalog.decode(otherValid.toJson()), otherValid);

      const binding = JsonTextBinding(
        repositoryId: 'crm',
        path: 'clients[?].nom',
      );
      const bindingFill = ValueBehaviorValidator.bindingIsFill(binding);
      expect(
        BehaviorValidatorCatalog.decode(
          jsonDecode(jsonEncode(bindingFill.toJson())) as Map<String, dynamic>,
        ),
        bindingFill,
      );
      expect(
        BehaviorValidatorCatalog.decode(
          jsonDecode(jsonEncode(bindingFill.toCompactJson()))
              as Map<String, dynamic>,
        ),
        bindingFill,
      );
      expect(bindingFill.referencedBindings, [binding]);

      final composite = AllBehaviorValidator(
        validators: [
          isFill,
          AnyBehaviorValidator(
            validators: [
              otherFill,
              const NotBehaviorValidator(validator: otherValid),
            ],
          ),
          bindingFill,
        ],
      );
      expect(
        BehaviorValidatorCatalog.decode(
          jsonDecode(jsonEncode(composite.toJson())) as Map<String, dynamic>,
        ),
        composite,
      );
      expect(
        BehaviorValidatorCatalog.decode(
          jsonDecode(jsonEncode(composite.toCompactJson()))
              as Map<String, dynamic>,
        ),
        composite,
      );
      expect(composite.referencedComponentIds, {'comp-a', 'comp-c'});

      // remapComponentIds across nested validators and ComponentBehavior
      final remapped = composite.remapComponentIds({
        'comp-a': 'new-a',
        'comp-c': 'new-c',
      });
      expect(remapped.referencedComponentIds, {'new-a', 'new-c'});

      final behaviorWithComposite = ComponentBehavior(
        id: 'b-remap',
        event: BehaviorEvent.onTap,
        validator: composite,
        action: const GoToPageAction(pagePath: '/ok'),
      );
      final remappedBehavior = behaviorWithComposite.remapComponentIds({
        'comp-a': 'mapped-a',
      });
      expect(remappedBehavior.validator!.referencedComponentIds, {
        'mapped-a',
        'comp-c',
      });

      // Validation errors
      expect(
        () => BehaviorValidatorCatalog.decode({'type': 'otherIsFill'}),
        throwsFormatException,
      );
      expect(
        () => BehaviorValidatorCatalog.decode({
          'type': 'otherIsFill',
          'targetComponentId': '   ',
        }),
        throwsFormatException,
      );
      expect(
        () => BehaviorValidatorCatalog.decode({
          'type': 'matchesRegex',
          'value': '[unclosed',
        }),
        throwsFormatException,
      );
      expect(
        () => AllBehaviorValidator(validators: const []).validate(),
        throwsFormatException,
      );
      expect(
        () => BehaviorValidatorCatalog.decode({
          'type': 'all',
          'validators': <Object?>[],
        }),
        throwsFormatException,
      );
      expect(
        () => AnyBehaviorValidator(validators: const []).validate(),
        throwsFormatException,
      );
    });

    test('RunJavaScriptAction serialization and validation', () {
      const behavior = ComponentBehavior(
        id: 'b-script',
        trigger: BehaviorTrigger.click,
        action: RunJavaScriptAction(
          repositoryId: 'orders',
          code: "ctx.set('status', 'done');",
        ),
      );
      expect(ComponentBehavior.fromJson(behavior.toJson()), behavior);
      expect(
        ComponentBehavior.fromJson(
          Map<String, dynamic>.from(behavior.toCompactJson()),
        ),
        behavior,
      );
      expect(
        BehaviorActionCatalog.decode({
          'type': 'runJavaScript',
          'code': "ctx.set('status', 'done');",
        }),
        const RunJavaScriptAction(code: "ctx.set('status', 'done');"),
      );
      expect(BehaviorCatalog.items, contains(BehaviorCatalog.runJavaScript));
      expect(
        () => ComponentBehavior(
          id: 'b-script-hover',
          trigger: BehaviorTrigger.hover,
          action: behavior.action,
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => const RunJavaScriptAction(
          repositoryId: 'Invalid-ID',
          code: 'ctx.set("value", 1);',
        ).validate(),
        throwsFormatException,
      );
    });

    test('StateBindingAction serialization, compact JSON, and validation', () {
      const action = StateBindingAction(
        state: BehaviorBoundState.invisible,
        binding: JsonTextBinding(path: 'ui.hidden'),
        whenValue: false,
        maintainSize: true,
      );
      expect(action.type, 'bindState');
      expect(action.description, contains('Invisible'));
      expect(action.description, contains('si faux'));
      expect(action.description, contains('espace conservé'));
      expect(action.matchesValue(false), isTrue);
      expect(action.matchesValue('false'), isTrue);
      expect(action.matchesValue(true), isFalse);
      expect(action.matchesValue(null), isFalse);

      final behavior = const ComponentBehavior(
        id: 'b-state',
        trigger: BehaviorTrigger.binding,
        action: action,
      );
      final json = behavior.toJson();
      final compact = behavior.toCompactJson();
      expect(
        (compact['action'] as Map<String, Object?>)['binding'],
        'ui.hidden',
      );

      final decoded = ComponentBehavior.fromJson(json);
      expect(decoded, equals(behavior));
      expect(
        ComponentBehavior.fromJson(Map<String, dynamic>.from(compact)),
        equals(behavior),
      );

      expect(
        () => const ComponentBehavior(
          id: 'bad-trigger',
          trigger: BehaviorTrigger.click,
          action: action,
        ).validate(),
        throwsFormatException,
      );
    });

    test('SearchProviderAction serialization and validation', () {
      const behavior = ComponentBehavior(
        id: 'b-search',
        trigger: BehaviorTrigger.doubleClick,
        action: SearchProviderAction(providerId: 'clients'),
      );
      expect(behavior.toJson()['action'], {
        'type': 'searchProvider',
        'providerId': 'clients',
      });
      expect(ComponentBehavior.fromJson(behavior.toJson()), behavior);
      expect(
        ComponentBehavior.fromJson(
          Map<String, dynamic>.from(behavior.toCompactJson()),
        ),
        behavior,
      );
      expect(BehaviorCatalog.items, contains(BehaviorCatalog.searchProvider));

      for (final action in [
        {'type': 'searchProvider', 'providerId': 'Clients'},
        {'type': 'searchProvider'},
        {'type': 'searchProvider', 'providerId': 'clients', 'url': 'x'},
      ]) {
        expect(
          () => BehaviorActionCatalog.decode(action),
          throwsFormatException,
          reason: '$action',
        );
      }
      expect(
        () => const ComponentBehavior(
          id: 'b-hover',
          trigger: BehaviorTrigger.hover,
          action: SearchProviderAction(providerId: 'clients'),
        ).validate(),
        throwsFormatException,
      );

      final appearance = Appearance(
        behaviors: {
          'button': [behavior],
        },
      );
      expect(appearance.usesProvider('clients'), isTrue);
      expect(appearance.usesProvider('autre'), isFalse);
    });

    test('DatasourceAction serialization, validation and codegen', () {
      const sort = ComponentBehavior(
        id: 'b-sort',
        trigger: BehaviorTrigger.click,
        action: DatasourceAction(
          datasourceId: 'clients',
          command: DatasourceCommand.sort,
          field: 'nom',
          direction: DatasourceSortDirection.desc,
        ),
      );
      expect(sort.toJson()['action'], {
        'type': 'datasource',
        'datasourceId': 'clients',
        'command': 'sort',
        'field': 'nom',
        'direction': 'desc',
      });
      expect(ComponentBehavior.fromJson(sort.toJson()), sort);
      expect(
        ComponentBehavior.fromJson(
          Map<String, dynamic>.from(sort.toCompactJson()),
        ),
        sort,
      );
      expect(
        BehaviorActionCatalog.decode({
          'type': 'datasource',
          'datasourceId': 'clients',
        }),
        const DatasourceAction(datasourceId: 'clients'),
      );
      expect(BehaviorCatalog.items, contains(BehaviorCatalog.datasource));

      for (final action in [
        {'type': 'datasource', 'datasourceId': 'Clients'},
        {'type': 'datasource', 'datasourceId': 'clients', 'command': 'x'},
        {'type': 'datasource', 'datasourceId': 'clients', 'command': 'sort'},
        {'type': 'datasource', 'datasourceId': 'clients', 'field': 'nom'},
        {
          'type': 'datasource',
          'datasourceId': 'clients',
          'command': 'sort',
          'field': 'nom',
          'direction': 'up',
        },
        {'type': 'datasource', 'datasourceId': 'clients', 'url': 'x'},
      ]) {
        expect(
          () => BehaviorActionCatalog.decode(action),
          throwsFormatException,
          reason: '$action',
        );
      }
      expect(
        () => const ComponentBehavior(
          id: 'b-hover',
          trigger: BehaviorTrigger.hover,
          action: DatasourceAction(datasourceId: 'clients'),
        ).validate(),
        throwsFormatException,
      );

      final appearance = Appearance(
        behaviors: {
          'button': [sort],
        },
      );
      expect(appearance.usesDatasource('clients'), isTrue);
      expect(appearance.usesDatasource('autre'), isFalse);

      final codegen = DartCodegenContext(
        appearance: Appearance(),
        registry: Registry(),
      );
      final code = codegen.formatBehaviorAction(sort.action);
      expect(code, contains('const DatasourceAction('));
      expect(code, contains("datasourceId: 'clients'"));
      expect(code, contains('command: DatasourceCommand.sort'));
      expect(code, contains("field: 'nom'"));
      expect(code, contains('direction: DatasourceSortDirection.desc'));
      expect(
        codegen.formatBehaviorAction(
          const DatasourceAction(datasourceId: 'clients'),
        ),
        isNot(contains('command:')),
      );
    });

    testWidgets('DatasourceAction runs the command with the row scope', (
      tester,
    ) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('datasource-action-'),
      );
      final store = JsonRepositoryStore(directory!);
      addTearDown(() async {
        store.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      });
      store.registerRepository(
        RepositoryImpl(
          id: 'clients',
          json: {
            'rows': [
              {'id': 1, 'nom': 'Dupont'},
              {'id': 2, 'nom': 'Martin'},
            ],
          },
        ),
      );
      const rows = JsonTextBinding(repositoryId: 'clients', path: 'rows');
      final deleted = <Object?>[];
      store.providers.register(
        CallbackDataProvider(
          id: 'clients_search',
          target: rows,
          callback: (_) async => const [],
        ),
      );
      store.providers.register(
        CallbackDataProvider(
          id: 'clients_delete',
          onExecute: (request) async {
            deleted.add(request.context['key']);
            return const DataProviderResult();
          },
        ),
      );
      store.datasources.register(
        const DatasourceConfig(
          id: 'clients',
          label: 'Clients',
          keyPath: 'id',
          search: DatasourceSearchConfig(provider: 'clients_search'),
          delete: DatasourceEntityConfig(provider: 'clients_delete'),
        ),
      );
      late BuildContext context;
      await tester.pumpWidget(
        JsonRepositoryScope(
          store: store,
          child: JsonListScope(
            repositoryId: 'clients',
            indices: const [1],
            arrayTemplate: 'rows',
            child: Builder(
              builder: (inner) {
                context = inner;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.runAsync(
        () => const DatasourceAction(
          datasourceId: 'clients',
          command: DatasourceCommand.delete,
        ).execute(context),
      );
      final status = store.datasources.stateOf('clients');
      for (
        var i = 0;
        i < 20 && (deleted.isEmpty || status.value.isLoading);
        i++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }

      expect(deleted, [2]);
      expect(status.value.phase, DataProviderPhase.success);
      expect(await tester.runAsync(() => store.readArray('clients', 'rows')), [
        {'id': 1, 'nom': 'Dupont'},
      ]);
    });

    testWidgets('SearchProviderAction runs the provider search', (
      tester,
    ) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('search-provider-action-'),
      );
      final store = JsonRepositoryStore(directory!);
      addTearDown(() async {
        store.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      });
      store.registerRepository(
        RepositoryImpl(id: 'resultats', json: {'rows': <Object?>[]}),
      );
      final calls = <Map<String, Object?>>[];
      store.providers.register(
        CallbackDataProvider(
          id: 'clients',
          target: const JsonTextBinding(
            repositoryId: 'resultats',
            path: 'rows',
          ),
          callback: (parameters) async {
            calls.add(parameters);
            return ['Dupont'];
          },
        ),
      );
      late BuildContext context;
      await tester.pumpWidget(
        JsonRepositoryScope(
          store: store,
          child: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.runAsync(
        () =>
            const SearchProviderAction(providerId: 'clients').execute(context),
      );
      final status = store.providers.statusOf('clients');
      for (var i = 0; i < 20 && status.value.isLoading; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }

      expect(calls, [<String, Object?>{}]);
      expect(status.value.phase, DataProviderPhase.success);
      expect(
        await tester.runAsync(() => store.readArray('resultats', 'rows')),
        ['Dupont'],
      );
    });

    test(
      'Appearance with behaviors survives AppearanceCodec encode and decode',
      () {
        const codec = AppearanceCodec();
        final initial = Appearance(
          behaviors: {
            'comp-1': [
              const ComponentBehavior(
                id: 'b-1',
                trigger: BehaviorTrigger.click,
                action: GoToPageAction(pagePath: '/target', pageName: 'Cible'),
              ),
            ],
          },
        );

        final encoded = codec.encode(initial);
        final restored = codec.decode(encoded);

        expect(restored.behaviorsFor('comp-1'), hasLength(1));
        final b = restored.behaviorsFor('comp-1').first;
        expect(b.id, 'b-1');
        expect(b.trigger, BehaviorTrigger.click);
        expect((b.action as GoToPageAction).pagePath, '/target');
        expect((b.action as GoToPageAction).pageName, 'Cible');

        final updated = initial.withAddedBehavior(
          'comp-1',
          const ComponentBehavior(
            id: 'b-2',
            trigger: BehaviorTrigger.click,
            action: GoToPageAction(pagePath: '/second'),
          ),
        );
        expect(updated.behaviorsFor('comp-1'), hasLength(2));

        final removed = updated.withRemovedBehavior('comp-1', 'b-1');
        expect(removed.behaviorsFor('comp-1'), hasLength(1));
        expect(removed.behaviorsFor('comp-1').first.id, 'b-2');
      },
    );
  });

  group('Behavior Context Menu and Editor Widget Tests', () {
    testWidgets('Context menu offers Composant and Comportement buttons', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);

      final appearance = ValueNotifier(
        Appearance(
          pageCatalog: EditorPageCatalog(
            pages: [
              EditorPageConfig(id: 'home', name: 'Accueil', path: '/home'),
              EditorPageConfig(id: 'about', name: 'À propos', path: '/about'),
            ],
          ),
        ),
      );
      addTearDown(appearance.dispose);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, _) => Scaffold(
              body: Center(
                child: EditorSlotAction(
                  label: 'Mon bouton',
                  enabled: true,
                  onEdit: () async {},
                  insertion: EditorSlotInsertion(
                    label: 'Mon bouton',
                    host: const InsertionHost(axis: Axis.vertical),
                    acceptsTags: (_) => true,
                    insert: (plan, comp) async {},
                  ),
                  child: EditorSlot(
                    id: 'btn-target',
                    label: 'Mon bouton',
                    child: const Text('Target Text'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/about',
            builder: (context, _) =>
                const Scaffold(body: Center(child: Text('About Page Content'))),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: StyleEditScope(
            controller: editing,
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Right-click on target
      await tester.tap(
        find.text('Target Text'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      // Check that both buttons are displayed
      expect(find.text('Composant…'), findsOneWidget);
      expect(find.text('Comportement…'), findsOneWidget);

      // Tap on Comportement… button
      await tester.tap(find.byKey(const ValueKey('style-menu-behavior')));
      await tester.pumpAndSettle();

      // Behavior wizard should be open
      expect(find.byKey(const ValueKey('behavior-add-wizard')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('behavior-add-stepper')),
        findsOneWidget,
      );

      // Step 0: Élément
      expect(
        find.byKey(const ValueKey('behavior-target-btn-target')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();

      // Step 1: Événement
      expect(
        find.byKey(const ValueKey('behavior-event-onTap')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();

      // Step 2: Action (catalog + inline settings)
      expect(
        find.byKey(const ValueKey('behavior-catalog-go_to_page')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('behavior-page-dropdown')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('behavior-page-dropdown')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();

      // Step 3: Validateur
      expect(
        find.byKey(const ValueKey('behavior-validator-mode-none')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();

      // Step 4: Récapitulatif
      expect(find.byKey(const ValueKey('behavior-add-submit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('behavior-add-submit')));
      await tester.pumpAndSettle();

      // Check that behavior is now in appearance for 'btn-target'
      expect(appearance.value.behaviorsFor('btn-target'), hasLength(1));
      final b = appearance.value.behaviorsFor('btn-target').first;
      expect(b.trigger, BehaviorTrigger.click);
      expect(b.action, isA<GoToPageAction>());

      // Switch off edit mode
      editing.value = false;
      await tester.pumpAndSettle();

      // Now click on the component in run mode -> should trigger navigation to '/home'
      await tester.tap(find.text('Target Text'));
      await tester.pumpAndSettle();
    });

    testWidgets('Edit, cancel, delete and undo an existing behavior in place', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const first = ComponentBehavior(
        id: 'first',
        action: GoToPageAction(pagePath: '/home'),
      );
      final original = ComponentBehavior(
        id: 'second',
        enabled: false,
        trigger: BehaviorTrigger.doubleClick,
        action: EmitEventAction(eventId: 'old.event', custom: {'count': 2}),
      );
      final appearance = ValueNotifier(
        Appearance(
          behaviors: {
            'target': [first, original],
            'other': [original],
          },
        ),
      );
      final editing = ValueNotifier(true);
      final history = EditorHistoryController(
        appearance: appearance,
        editMode: editing,
      );
      addTearDown(appearance.dispose);
      addTearDown(editing.dispose);
      addTearDown(history.dispose);
      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: EditorHistoryScope(
            controller: history,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    key: const ValueKey('open'),
                    onPressed: () => showComponentBehaviorEditor(
                      context: context,
                      componentId: 'target',
                      componentLabel: 'Bouton',
                    ),
                    child: const Text('Ouvrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Finder keyed(String key) => find.byKey(ValueKey(key));
      Future<void> tapKey(String key) async {
        await tester.ensureVisible(keyed(key));
        await tester.tap(keyed(key));
        await tester.pumpAndSettle();
      }

      List<ComponentBehavior> current() =>
          appearance.value.behaviorsFor('target');

      await tapKey('open');
      await tapKey('behavior-edit-second');
      // Edit opens on Step 1 (event)
      expect(find.text('Double-clic (onDoubleTap)'), findsOneWidget);
      await tapKey('behavior-add-next');
      // Step 2 (action): inline settings
      await tester.ensureVisible(keyed('behavior-event-id'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(keyed('behavior-event-id')).controller!.text,
        'old.event',
      );
      expect(
        tester
            .widget<TextField>(keyed('behavior-event-custom'))
            .controller!
            .text,
        '{"count":2}',
      );
      await tester.enterText(keyed('behavior-event-id'), 'discard.me');
      await tapKey('behavior-add-cancel');
      expect(current(), [first, original]);
      expect(history.canUndo, isFalse);

      await tapKey('open');
      await tapKey('behavior-edit-second');
      // Step 1 (event): switch to onTap (click)
      await tapKey('behavior-event-onTap');
      await tapKey('behavior-add-next');
      // Step 2 (action): switch to go_to_page and enter custom path
      await tapKey('behavior-catalog-go_to_page');
      await tester.ensureVisible(keyed('behavior-custom-path-input'));
      await tester.pumpAndSettle();
      await tester.enterText(keyed('behavior-custom-path-input'), '/changed');
      await tester.pumpAndSettle();
      // Step 2 -> Step 3 (validator) -> Step 4 (summary) -> submit
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-submit');
      const changed = ComponentBehavior(
        id: 'second',
        enabled: false,
        trigger: BehaviorTrigger.click,
        action: GoToPageAction(pagePath: '/changed'),
      );
      expect(current(), [first, changed]);
      expect(appearance.value.behaviorsFor('other'), [original]);
      history.undo();
      expect(current(), [first, original]);
      expect(history.canUndo, isFalse);
      history.redo();
      expect(current(), [first, changed]);

      await tapKey('open');
      await tapKey('behavior-delete-second');
      expect(current(), [first]);
      expect(keyed('behavior-delete-second'), findsNothing);
      history.undo();
      await tester.pumpAndSettle();
      expect(current(), [first, changed]);
      expect(keyed('behavior-edit-second'), findsOneWidget);
      await tapKey('behavior-add-cancel');
    });

    testWidgets('Wizard adds a searchProvider behavior that runs on click', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('search-provider-wizard-'),
      );
      final store = JsonRepositoryStore(directory!);
      addTearDown(() async {
        store.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      });
      store.registerRepository(
        RepositoryImpl(id: 'resultats', json: {'rows': <Object?>[]}),
      );
      var searches = 0;
      store.providers.register(
        CallbackDataProvider(
          id: 'clients',
          label: 'Clients',
          target: const JsonTextBinding(
            repositoryId: 'resultats',
            path: 'rows',
          ),
          callback: (_) async {
            searches++;
            return ['Dupont'];
          },
        ),
      );
      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);
      final appearance = ValueNotifier(Appearance());
      addTearDown(appearance.dispose);

      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        JsonRepositoryScope(
          store: store,
          child: AppearanceScope(
            controller: appearance,
            child: StyleEditScope(
              controller: editing,
              child: MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: EditorSlotAction(
                      label: 'Rechercher',
                      enabled: true,
                      onEdit: () async {},
                      child: const EditorSlot(
                        id: 'btn-search',
                        label: 'Rechercher',
                        child: Text('Rechercher'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rechercher'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-menu-behavior')));
      await tester.pumpAndSettle();
      // Step 0 (target) -> Step 1 (event) -> Step 2 (action)
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();
      final card = find.byKey(
        const ValueKey('behavior-catalog-search_provider'),
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await settle();

      final next = find.byKey(const ValueKey('behavior-add-next'));
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      final providerTile = find.byKey(
        const ValueKey('behavior-provider-clients'),
      );
      await tester.ensureVisible(providerTile);
      await tester.pumpAndSettle();
      expect(find.text('clients · code'), findsOneWidget);
      await tester.tap(providerTile);
      await tester.pumpAndSettle();
      // Step 2 (action) -> Step 3 (validator) -> Step 4 (summary)
      await tester.tap(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(find.text('Clients (clients)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('behavior-add-submit')));
      await tester.pumpAndSettle();

      final behavior = appearance.value.behaviorsFor('btn-search').single;
      expect(behavior.trigger, BehaviorTrigger.click);
      expect(
        behavior.action,
        const SearchProviderAction(providerId: 'clients'),
      );
      expect(appearance.value.usesProvider('clients'), isTrue);

      editing.value = false;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rechercher'));
      await settle();
      expect(searches, 1);
      expect(store.peekDocument('resultats')?.document, {
        'rows': ['Dupont'],
      });
    });

    testWidgets('Wizard adds a datasource sort behavior that runs on click', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('datasource-wizard-'),
      );
      final store = JsonRepositoryStore(directory!);
      addTearDown(() async {
        store.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      });
      store.registerRepository(
        RepositoryImpl(id: 'resultats', json: {'rows': <Object?>[]}),
      );
      final requests = <DataProviderRequest>[];
      store.providers.register(
        CallbackDataProvider(
          id: 'clients_search',
          target: const JsonTextBinding(
            repositoryId: 'resultats',
            path: 'rows',
          ),
          onExecute: (request) async {
            requests.add(request);
            return DataProviderResult.rows(const [
              {'id': 1, 'nom': 'Dupont'},
            ]);
          },
        ),
      );
      store.datasources.register(
        DatasourceConfig(
          id: 'clients',
          label: 'Clients',
          keyPath: 'id',
          search: DatasourceSearchConfig(
            provider: 'clients_search',
            sort: DatasourceSort(fields: ['nom']),
          ),
        ),
      );
      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);
      final appearance = ValueNotifier(Appearance());
      addTearDown(appearance.dispose);

      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        JsonRepositoryScope(
          store: store,
          child: AppearanceScope(
            controller: appearance,
            child: StyleEditScope(
              controller: editing,
              child: MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: EditorSlotAction(
                      label: 'Trier',
                      enabled: true,
                      onEdit: () async {},
                      child: const EditorSlot(
                        id: 'btn-sort',
                        label: 'Trier par nom',
                        child: Text('Trier par nom'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Trier par nom'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-menu-behavior')));
      await tester.pumpAndSettle();
      // Step 0 (target) -> Step 1 (event) -> Step 2 (action)
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('behavior-catalog-datasource'));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await settle();

      final next = find.byKey(const ValueKey('behavior-add-next'));
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      final dsTile = find.byKey(const ValueKey('behavior-datasource-clients'));
      await tester.ensureVisible(dsTile);
      await tester.pumpAndSettle();
      await tester.tap(dsTile);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);

      final cmdField = find.byKey(
        const ValueKey('behavior-datasource-command'),
      );
      await tester.ensureVisible(cmdField);
      await tester.pumpAndSettle();
      await tester.tap(cmdField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trier').last);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(next).onPressed, isNull);

      final sortField = find.byKey(const ValueKey('behavior-datasource-field'));
      await tester.ensureVisible(sortField);
      await tester.pumpAndSettle();
      await tester.enterText(sortField, 'ville');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('behavior-datasource-error')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(next).onPressed, isNull);

      await tester.enterText(sortField, 'nom');
      await tester.ensureVisible(find.text('Décroissant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Décroissant'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('behavior-datasource-error')),
        findsNothing,
      );
      // Step 2 (action) -> Step 3 (validator) -> Step 4 (summary)
      await tester.tap(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(find.text('Clients (clients)'), findsOneWidget);
      expect(find.text('Trier sur nom (décroissant)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('behavior-add-submit')));
      await tester.pumpAndSettle();

      final behavior = appearance.value.behaviorsFor('btn-sort').single;
      expect(behavior.trigger, BehaviorTrigger.click);
      expect(
        behavior.action,
        const DatasourceAction(
          datasourceId: 'clients',
          command: DatasourceCommand.sort,
          field: 'nom',
          direction: DatasourceSortDirection.desc,
        ),
      );
      expect(appearance.value.usesDatasource('clients'), isTrue);

      editing.value = false;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trier par nom'));
      await settle();
      expect(requests, hasLength(1));
      expect(requests.single.extraParameters, {'sort': '-nom'});
      expect(store.peekDocument('resultats')?.document, {
        'rows': [
          {'id': 1, 'nom': 'Dupont'},
        ],
      });
    });

    testWidgets('Click behavior triggers navigation to selected page', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final editing = ValueNotifier(false);
      addTearDown(editing.dispose);

      final appearance = ValueNotifier(
        Appearance(
          behaviors: {
            'card-target': [
              const ComponentBehavior(
                id: 'b-nav',
                trigger: BehaviorTrigger.click,
                action: GoToPageAction(pagePath: '/about'),
              ),
            ],
          },
        ),
      );
      addTearDown(appearance.dispose);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, _) => Scaffold(
              body: Center(
                child: EditorSlot(
                  id: 'card-target',
                  label: 'Ma Carte',
                  child: const Text('Clickable Card'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/about',
            builder: (context, _) => Scaffold(
              appBar: const SuperAppBar(id: 'about-app-bar'),
              body: const Center(child: Text('Arrived on About Page!')),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: StyleEditScope(
            controller: editing,
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clickable Card'), findsOneWidget);
      expect(find.text('Arrived on About Page!'), findsNothing);

      // Tap on the card
      await tester.tap(find.text('Clickable Card'));
      await tester.pumpAndSettle();

      // Navigation should have pushed the page and displayed the AppBar back button
      expect(find.text('Arrived on About Page!'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);

      // Tap on the AppBar back button to return to the previous page
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Clickable Card'), findsOneWidget);
      expect(find.text('Arrived on About Page!'), findsNothing);
    });

    testWidgets(
      'Wizard allows selecting parent element in hierarchy to attach behavior',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final editing = ValueNotifier(true);
        addTearDown(editing.dispose);

        final appearance = ValueNotifier(
          Appearance(
            pageCatalog: EditorPageCatalog(
              pages: [
                EditorPageConfig(
                  id: 'details',
                  name: 'Détails',
                  path: '/details',
                ),
              ],
            ),
          ),
        );
        addTearDown(appearance.dispose);

        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, _) => Scaffold(
                body: Center(
                  child: EditorSlotAction(
                    label: 'Parent Card',
                    enabled: true,
                    onEdit: () async {},
                    child: EditorSlot(
                      id: 'parent-card',
                      label: 'Parent Card',
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: EditorSlot(
                          id: 'child-text',
                          label: 'Child Text',
                          child: const Text('Nested Child'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/details',
              builder: (context, _) =>
                  const Scaffold(body: Center(child: Text('Details Screen'))),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: StyleEditScope(
              controller: editing,
              child: MaterialApp.router(routerConfig: router),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Right-click on child
        await tester.tap(
          find.text('Nested Child'),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        // Tap on Comportement…
        await tester.tap(find.byKey(const ValueKey('style-menu-behavior')));
        await tester.pumpAndSettle();

        // In Step 0: both child and parent card should be offered!
        expect(
          find.byKey(const ValueKey('behavior-target-child-text')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('behavior-target-parent-card')),
          findsOneWidget,
        );

        // Hover over parent-card target in EditorTargetSelector -> parent EditorSlot should show outline!
        final parentSlotFinder = find.ancestor(
          of: find.text('Nested Child'),
          matching: find.byWidgetPredicate(
            (w) => w is EditorSlot && w.id == 'parent-card',
          ),
        );
        CustomPaint parentOutlinePaint() => tester.widget<CustomPaint>(
          find
              .descendant(
                of: parentSlotFinder,
                matching: find.byType(CustomPaint),
              )
              .first,
        );

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(gesture.removePointer);
        await gesture.addPointer(location: Offset.zero);
        await tester.pump();
        await gesture.moveTo(
          tester.getCenter(
            find.byKey(const ValueKey('behavior-target-parent-card')),
          ),
        );
        await tester.pump();
        expect(parentOutlinePaint().foregroundPainter, isNotNull);

        await gesture.moveTo(Offset.zero);
        await tester.pump();
        expect(parentOutlinePaint().foregroundPainter, isNull);

        // Select parent-card instead of child-text
        await tester.tap(
          find.byKey(const ValueKey('behavior-target-parent-card')),
        );
        await tester.pumpAndSettle();

        // Move to step 1 (event)
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();

        // Move to step 2 (action)
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();

        // Move to step 3 (validator)
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();

        // Move to step 4 (summary)
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();

        // Apply
        await tester.tap(find.byKey(const ValueKey('behavior-add-submit')));
        await tester.pumpAndSettle();

        // Behavior should be attached to parent-card, NOT child-text!
        expect(appearance.value.behaviorsFor('child-text'), isEmpty);
        expect(appearance.value.behaviorsFor('parent-card'), hasLength(1));
      },
    );

    testWidgets(
      'SuperListView row IterableContent has a distinct ID from the ListView',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final editing = ValueNotifier(true);
        addTearDown(editing.dispose);

        final appearance = ValueNotifier(
          Appearance(
            pageCatalog: EditorPageCatalog(
              pages: [
                EditorPageConfig(
                  id: 'item-details',
                  name: 'Détails Élément',
                  path: '/item-details',
                ),
              ],
            ),
          ),
        );
        addTearDown(appearance.dispose);

        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, _) => const Scaffold(
                body: Center(
                  child: SuperListView(
                    id: 'clients-list',
                    itemId: 'clients-row-item',
                    config: SuperListViewConfig(emptyText: 'Aucun client'),
                  ),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: StyleEditScope(
              controller: editing,
              child: MaterialApp.router(routerConfig: router),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check that IterableContent widget has the distinct id 'clients-row-item'
        final iterable = tester.widget<IterableContent>(
          find.byType(IterableContent),
        );
        expect(iterable.id, 'clients-row-item');
        expect(iterable.id, isNot('clients-list'));

        // Right-click on the IterableContent row
        await tester.tap(
          find.byType(IterableContent),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        // Tap on Comportement…
        await tester.tap(find.byKey(const ValueKey('style-menu-behavior')));
        await tester.pumpAndSettle();

        // Check that the wizard offers IterableContent with the exact id 'clients-row-item'
        expect(
          find.byKey(const ValueKey('behavior-target-clients-row-item')),
          findsOneWidget,
        );
        expect(find.text('ID : clients-row-item'), findsOneWidget);

        // Check that the parent list is offered with id 'clients-list'
        expect(
          find.byKey(const ValueKey('behavior-target-clients-list')),
          findsOneWidget,
        );
        expect(find.text('ID : clients-list'), findsOneWidget);
      },
    );

    testWidgets(
      'StateBindingAction dynamically toggles invisible, readOnly, and disabled from repository bool',
      (tester) async {
        late Directory tempDir;
        late JsonRepositoryStore store;
        late String repoId;

        await tester.runAsync(() async {
          tempDir = await Directory.systemTemp.createTemp(
            'state_behavior_test_',
          );
          store = JsonRepositoryStore(tempDir);
          await store.create('Flags');
          repoId = await store.idOf('Flags');
          final before = await store.read('Flags');
          await store.save(
            'Flags',
            jsonEncode({'hidden': false, 'readOnly': false, 'active': true}),
            expectedText: before,
          );
          // Warm cache via readAttribute
          await store.readAttribute(
            JsonTextBinding(repositoryId: repoId, path: 'hidden'),
          );
        });
        addTearDown(() async {
          store.dispose();
          await tempDir.delete(recursive: true);
        });

        final editing = ValueNotifier(false);
        addTearDown(editing.dispose);

        final appearance = ValueNotifier(
          Appearance(
            behaviors: {
              'box-hidden': [
                ComponentBehavior(
                  id: 'b-inv',
                  trigger: BehaviorTrigger.binding,
                  action: StateBindingAction(
                    state: BehaviorBoundState.invisible,
                    binding: JsonTextBinding(
                      repositoryId: repoId,
                      path: 'hidden',
                    ),
                  ),
                ),
              ],
              'val-input': [
                ComponentBehavior(
                  id: 'b-ro',
                  trigger: BehaviorTrigger.binding,
                  action: StateBindingAction(
                    state: BehaviorBoundState.readOnly,
                    binding: JsonTextBinding(
                      repositoryId: repoId,
                      path: 'readOnly',
                    ),
                  ),
                ),
              ],
              'btn-action': [
                ComponentBehavior(
                  id: 'b-dis',
                  trigger: BehaviorTrigger.binding,
                  action: StateBindingAction(
                    state: BehaviorBoundState.disabled,
                    binding: JsonTextBinding(
                      repositoryId: repoId,
                      path: 'active',
                    ),
                    whenValue: false,
                  ),
                ),
              ],
            },
          ),
        );
        addTearDown(appearance.dispose);

        var actionClicks = 0;

        await tester.pumpWidget(
          JsonRepositoryScope(
            store: store,
            child: AppearanceScope(
              controller: appearance,
              child: StyleEditScope(
                controller: editing,
                child: MaterialApp(
                  home: Scaffold(
                    body: Column(
                      children: [
                        const EditorSlot(
                          id: 'box-hidden',
                          label: 'Hidden Box',
                          child: Text('Secret Content'),
                        ),
                        const SuperValue(
                          id: 'val-input',
                          config: SuperValueConfig(
                            mode: SuperValueMode.input,
                            initialText: 'Initial',
                          ),
                        ),
                        SuperAction(
                          id: 'btn-action',
                          config: const SuperActionConfig(label: 'Valider'),
                          onPressed: () => actionClicks++,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially: visible, editable, and enabled
        expect(find.text('Secret Content'), findsOneWidget);
        final textFieldBefore = tester.widget<TextField>(
          find.byKey(const ValueKey('super-value-input-val-input')),
        );
        expect(textFieldBefore.readOnly, isFalse);

        await tester.tap(
          find.byKey(const ValueKey('super-action-button-btn-action')),
        );
        await tester.pump();
        expect(actionClicks, 1);

        // Update repository booleans: hidden=true, readOnly=true, active=false
        await tester.runAsync(() async {
          final before = await store.read('Flags');
          await store.save(
            'Flags',
            jsonEncode({'hidden': true, 'readOnly': true, 'active': false}),
            expectedText: before,
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();

        // Secret Content is now hidden offstage by Visibility(visible: false)
        expect(find.text('Secret Content'), findsNothing);

        // SuperValue input is now readOnly
        final textFieldAfter = tester.widget<TextField>(
          find.byKey(const ValueKey('super-value-input-val-input')),
        );
        expect(textFieldAfter.readOnly, isTrue);

        // SuperAction is now disabled
        await tester.tap(
          find.byKey(const ValueKey('super-action-button-btn-action')),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(actionClicks, 1);

        // In edit mode, hidden component becomes visible again for editing
        editing.value = true;
        await tester.pumpAndSettle();
        expect(find.text('Secret Content'), findsOneWidget);
      },
    );

    test(
      'AddArrayItemAction and CreationDefaultAction serialize and validate',
      () {
        const addAction = AddArrayItemAction(
          binding: JsonTextBinding(repositoryId: 'crm', path: 'clients'),
          selectCreated: true,
        );
        final addBehavior = ComponentBehavior(
          id: 'b-add',
          trigger: BehaviorTrigger.click,
          action: addAction,
        );
        final decodedAdd = ComponentBehavior.fromJson(addBehavior.toJson());
        expect(decodedAdd, addBehavior);
        expect(BehaviorCatalog.items, contains(BehaviorCatalog.addArrayItem));

        expect(
          () => ComponentBehavior(
            id: 'b-bad-add',
            trigger: BehaviorTrigger.binding,
            action: addAction,
          ).validate(),
          throwsFormatException,
        );

        const defaultAction = CreationDefaultAction(defaultValue: 'Nouveau');
        const defaultBehavior = ComponentBehavior(
          id: 'b-def',
          trigger: BehaviorTrigger.create,
          action: defaultAction,
        );
        final decodedDefault = ComponentBehavior.fromJson(
          defaultBehavior.toJson(),
        );
        expect(decodedDefault, defaultBehavior);
        expect(
          BehaviorCatalog.items,
          contains(BehaviorCatalog.creationDefault),
        );

        expect(
          () => ComponentBehavior(
            id: 'b-bad-def',
            trigger: BehaviorTrigger.click,
            action: defaultAction,
          ).validate(),
          throwsFormatException,
        );
        expect(
          () => ComponentBehavior(
            id: 'b-bad-trigger',
            trigger: BehaviorTrigger.create,
            action: const GoToPageAction(pagePath: '/home'),
          ).validate(),
          throwsFormatException,
        );
      },
    );

    testWidgets(
      'AddArrayItemAction creates row from JSON Schema merged with SuperValue CreationDefaultAction',
      (tester) async {
        late Directory tempDir;
        late JsonRepositoryStore store;
        late String repoId;

        await tester.runAsync(() async {
          tempDir = await Directory.systemTemp.createTemp(
            'add_array_schema_test_',
          );
          store = JsonRepositoryStore(tempDir);
          await store.create('CRM');
          repoId = await store.idOf('CRM');
          final before = await store.read('CRM');
          await store.save(
            'CRM',
            jsonEncode(<String, Object?>{'clients': <Object?>[]}),
            expectedText: before,
          );
          await store.saveJsonSchema(repoId, <String, Object?>{
            r'$schema': 'https://json-schema.org/draft/2020-12/schema',
            'type': 'object',
            'required': ['clients'],
            'properties': <String, Object?>{
              'clients': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{
                  'type': 'object',
                  'required': ['nom', 'statut', 'priorite', 'actif'],
                  'properties': <String, Object?>{
                    'nom': <String, Object?>{
                      'type': 'string',
                      'default': 'Nouveau client',
                    },
                    'statut': <String, Object?>{
                      'type': 'string',
                      'enum': ['Standard', 'VIP'],
                      'default': 'Standard',
                    },
                    'priorite': <String, Object?>{
                      'type': 'integer',
                      'minimum': 1,
                    },
                    'actif': <String, Object?>{
                      'type': 'boolean',
                      'default': true,
                    },
                  },
                },
              },
            },
          });
        });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          store.dispose();
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            if (await tempDir.exists()) {
              await tempDir.delete(recursive: true);
            }
          });
        });

        final editing = ValueNotifier(false);
        addTearDown(editing.dispose);

        final appearance = ValueNotifier(
          Appearance(
            components: {
              'main-layout': const SuperLayoutConfig(
                placements: {
                  SuperLayoutZone.center: [
                    'btn-add-client',
                    'list-clients',
                    'detail-priorite',
                  ],
                },
                slotTypes: {
                  'btn-add-client': 'registry:Action',
                  'list-clients': 'registry:ListView',
                  'detail-priorite': 'registry:Value',
                },
              ),
              'btn-add-client': const SuperActionConfig(label: 'Ajouter'),
              'list-clients': SuperListViewConfig(
                binding: JsonTextBinding(repositoryId: repoId, path: 'clients'),
                template: const SuperLayoutConfig(
                  placements: {
                    SuperLayoutZone.center: ['row-statut'],
                  },
                  slotTypes: {'row-statut': 'registry:Value'},
                ),
              ),
              'row-statut': const SuperValueConfig(
                binding: JsonTextBinding(path: 'clients[?].statut'),
              ),
              'detail-priorite': SuperValueConfig(
                binding: JsonTextBinding(
                  repositoryId: repoId,
                  path: 'clients[?].priorite',
                ),
              ),
            },
            behaviors: {
              'btn-add-client': [
                ComponentBehavior(
                  id: 'b-add-client',
                  trigger: BehaviorTrigger.click,
                  action: AddArrayItemAction(
                    binding: JsonTextBinding(
                      repositoryId: repoId,
                      path: 'clients',
                    ),
                  ),
                ),
              ],
              'row-statut': [
                const ComponentBehavior(
                  id: 'b-default-statut',
                  trigger: BehaviorTrigger.create,
                  action: CreationDefaultAction(defaultValue: 'VIP'),
                ),
              ],
              'detail-priorite': [
                const ComponentBehavior(
                  id: 'b-default-priorite',
                  trigger: BehaviorTrigger.create,
                  action: CreationDefaultAction(defaultValue: '3'),
                ),
              ],
            },
          ),
        );
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          JsonRepositoryScope(
            store: store,
            child: AppearanceScope(
              controller: appearance,
              child: StyleEditScope(
                controller: editing,
                child: MaterialApp(
                  home: Scaffold(
                    body: SuperAction(
                      id: 'btn-add-client',
                      config: const SuperActionConfig(label: 'Ajouter'),
                      behaviours: appearance.value.behaviorsFor(
                        'btn-add-client',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        List<Object?>? created;
        await tester.runAsync(() async {
          await tester.tap(
            find.byKey(const ValueKey('super-action-button-btn-add-client')),
          );
          for (var i = 0; i < 60; i++) {
            await tester.pump();
            created = await store.readArray(repoId, 'clients');
            if (created != null && created!.isNotEmpty) break;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();

        expect(created, hasLength(1));
        expect(created!.single, <String, Object?>{
          'nom': 'Nouveau client',
          'statut': 'VIP',
          'priorite': 3,
          'actif': true,
        });
        expect(store.bindingOf(repoId).array('clients').selection, [0]);
      },
    );

    testWidgets(
      'ComponentBehaviorWizard exposes creationDefault on SuperValue and hides it on SuperAction',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final appearance = ValueNotifier(
          Appearance(
            components: {
              'val-statut': const SuperValueConfig(
                binding: JsonTextBinding(
                  repositoryId: 'crm',
                  path: 'clients[?].statut',
                ),
              ),
              'btn-add': const SuperActionConfig(label: 'Ajouter'),
            },
          ),
        );
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      ElevatedButton(
                        key: const ValueKey('open-value-wizard'),
                        onPressed: () => showComponentBehaviorEditor(
                          context: context,
                          componentId: 'val-statut',
                          componentLabel: 'Statut',
                        ),
                        child: const Text('Value Wizard'),
                      ),
                      ElevatedButton(
                        key: const ValueKey('open-action-wizard'),
                        onPressed: () => showComponentBehaviorEditor(
                          context: context,
                          componentId: 'btn-add',
                          componentLabel: 'Ajouter',
                        ),
                        child: const Text('Action Wizard'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // Sur SuperValue : onCreate et creationDefault sont proposés, ainsi que addArrayItem sur un événement impératif.
        await tester.tap(find.byKey(const ValueKey('open-value-wizard')));
        await tester.pumpAndSettle();
        // Step 0 -> Step 1 (event)
        await tester.tap(find.text('Suivant'));
        await tester.pumpAndSettle();
        final onCreateCard = find.byKey(
          const ValueKey('behavior-event-onCreate'),
        );
        await tester.ensureVisible(onCreateCard);
        await tester.pumpAndSettle();
        expect(onCreateCard, findsOneWidget);

        // Avec onTap (par défaut), Step 2 expose addArrayItem
        await tester.tap(find.text('Suivant'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('behavior-catalog-add_array_item')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ajouter une ligne (JSON Schema)'), findsOneWidget);

        // Retour à Step 1, sélection de onCreate -> Step 2 expose creationDefault
        await tester.tap(find.text('Précédent'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(onCreateCard);
        await tester.pumpAndSettle();
        await tester.tap(onCreateCard);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Suivant'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('behavior-catalog-creation_default')),
          findsOneWidget,
        );
        expect(find.text('Valeur par défaut à la création'), findsWidgets);

        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();

        // Sur SuperAction : onCreate et creationDefault ne sont pas proposés.
        await tester.tap(find.byKey(const ValueKey('open-action-wizard')));
        await tester.pumpAndSettle();
        // Step 0 -> Step 1 (event)
        await tester.tap(find.text('Suivant'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('behavior-event-onCreate')),
          findsNothing,
        );
        // Step 1 (onTap) -> Step 2 (action)
        await tester.tap(find.text('Suivant'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('behavior-catalog-add_array_item')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Valeur par défaut à la création'), findsNothing);
        expect(find.text('Ajouter une ligne (JSON Schema)'), findsOneWidget);
      },
    );

    testWidgets(
      'ComponentBehaviorWizard configures event, action and validator end-to-end and supports editing validator',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final appearance = ValueNotifier(
          Appearance(
            pageCatalog: EditorPageCatalog(
              pages: [
                EditorPageConfig(
                  id: 'confirm',
                  name: 'Confirmation',
                  path: '/confirm',
                ),
              ],
            ),
            components: {
              'btn-submit': const SuperActionConfig(label: 'Valider'),
              'email-input': const SuperValueConfig(
                label: 'Email',
                mode: SuperValueMode.input,
              ),
              'name-input': const SuperValueConfig(
                label: 'Nom',
                mode: SuperValueMode.input,
              ),
            },
          ),
        );
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    key: const ValueKey('open-wizard'),
                    onPressed: () => showComponentBehaviorEditor(
                      context: context,
                      componentId: 'btn-submit',
                      componentLabel: 'Valider',
                    ),
                    child: const Text('Ouvrir Wizard'),
                  ),
                ),
              ),
            ),
          ),
        );

        Finder keyed(String key) => find.byKey(ValueKey(key));
        Future<void> tapKey(String key) async {
          await tester.ensureVisible(keyed(key));
          await tester.pumpAndSettle();
          await tester.tap(keyed(key));
          await tester.pumpAndSettle();
        }

        // Open wizard -> Step 0 (target)
        await tapKey('open-wizard');
        expect(keyed('behavior-target-btn-submit'), findsOneWidget);
        await tapKey('behavior-add-next');

        // Step 1 (event): select onDoubleTap
        await tapKey('behavior-event-onDoubleTap');
        await tapKey('behavior-add-next');

        // Step 2 (action): select emit_event and configure payload
        await tapKey('behavior-catalog-emit_event');
        await tester.ensureVisible(keyed('behavior-event-id'));
        await tester.pumpAndSettle();
        await tester.enterText(keyed('behavior-event-id'), 'form.submitted');
        await tester.ensureVisible(keyed('behavior-event-custom'));
        await tester.pumpAndSettle();
        await tester.enterText(keyed('behavior-event-custom'), '{"step":1}');
        await tester.pumpAndSettle();
        await tapKey('behavior-add-next');

        // Step 3 (validator): Condition simple -> Autre composant -> email-input (otherIsFill)
        await tapKey('behavior-validator-mode-simple');
        await tapKey('behavior-validator-source-component');
        // Without a targetComponentId, continuing is disabled and an error box is shown
        expect(
          tester.widget<FilledButton>(keyed('behavior-add-next')).onPressed,
          isNull,
        );
        expect(keyed('behavior-validator-error'), findsOneWidget);

        await tapKey('behavior-validator-target-option-email-input');
        expect(keyed('behavior-validator-error'), findsNothing);
        expect(
          tester.widget<FilledButton>(keyed('behavior-add-next')).onPressed,
          isNotNull,
        );
        await tapKey('behavior-add-next');

        // Step 4 (summary): check summary & apply
        expect(find.text('Double-clic (onDoubleTap)'), findsOneWidget);
        expect(find.text('« email-input » est rempli'), findsOneWidget);
        expect(find.text('form.submitted'), findsWidgets);
        await tapKey('behavior-add-submit');

        final saved = appearance.value.behaviorsFor('btn-submit').single;
        expect(saved.event, BehaviorEvent.onDoubleTap);
        expect(
          saved.validator,
          const ValueBehaviorValidator.otherIsFill('email-input'),
        );
        expect(
          saved.action,
          EmitEventAction(eventId: 'form.submitted', custom: {'step': 1}),
        );

        // Edit the existing behavior and update its validator target to name-input
        await tapKey('open-wizard');
        await tapKey('behavior-edit-${saved.id}');
        // Step 1 (event) -> Step 2 (action) -> Step 3 (validator)
        await tapKey('behavior-add-next');
        await tapKey('behavior-add-next');
        expect(
          tester
              .widget<TextField>(keyed('behavior-validator-target'))
              .controller!
              .text,
          'email-input',
        );
        await tester.ensureVisible(keyed('behavior-validator-target'));
        await tester.pumpAndSettle();
        await tester.enterText(keyed('behavior-validator-target'), '');
        await tester.pumpAndSettle();
        await tapKey('behavior-validator-target-option-name-input');
        await tapKey('behavior-add-next');
        expect(find.text('« name-input » est rempli'), findsOneWidget);
        await tapKey('behavior-add-submit');

        final updated = appearance.value.behaviorsFor('btn-submit').single;
        expect(updated.id, saved.id);
        expect(updated.event, BehaviorEvent.onDoubleTap);
        expect(
          updated.validator,
          const ValueBehaviorValidator.otherIsFill('name-input'),
        );
        expect(
          updated.action,
          EmitEventAction(eventId: 'form.submitted', custom: {'step': 1}),
        );
      },
    );
  });
}
