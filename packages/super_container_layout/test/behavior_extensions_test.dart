import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

bool _hasQuickJsDll() {
  if (!Platform.isWindows) return false;
  final candidates = [
    'quickjs_c_bridge.dll',
    '${Directory.current.path}\\build\\windows\\x64\\runner\\Debug\\quickjs_c_bridge.dll',
    '${Directory.current.path}\\build\\windows\\x64\\runner\\Release\\quickjs_c_bridge.dll',
  ];
  for (final path in candidates) {
    if (path != 'quickjs_c_bridge.dll' && !File(path).existsSync()) continue;
    try {
      ffi.DynamicLibrary.open(path);
      return true;
    } catch (_) {
      // Essayer le candidat suivant.
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channels = [
    MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ComponentRuntimeValueRegistry.instance.clear();
    BehaviorDispatcher.cancelPendingDebounces();
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    BehaviorDispatcher.cancelPendingDebounces();
    ComponentRuntimeValueRegistry.instance.clear();
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('New BehaviorActions (goBack, removeArrayItem, showMessage, copyToClipboard)', () {
    test('JSON roundtrip, validation, and DartCodegenContext formatting', () {
      const goBack = GoBackAction(fallbackPagePath: '/accueil');
      final removeItem = RemoveArrayItemAction(
        binding: const JsonTextBinding(repositoryId: 'crm', path: 'clients[?]'),
        confirm: false,
        selectAdjacent: true,
      );
      const showMsg = ShowMessageAction(
        message: 'Enregistré',
        severity: BehaviorMessageSeverity.success,
        durationMs: 2500,
      );
      const copy = CopyToClipboardAction(
        targetComponentId: 'field-email',
        feedbackMessage: 'Copié',
      );

      for (final action in [goBack, removeItem, showMsg, copy]) {
        final decoded = BehaviorActionCatalog.decode(action.toJson());
        expect(decoded, equals(action));
      }

      expect(removeItem.confirm, isFalse);
      expect(removeItem.toCompactJson().containsKey('confirm'), isFalse);

      expect(
        () => BehaviorActionCatalog.decode({'type': 'goBack', 'fallbackPagePath': '  '}),
        throwsFormatException,
      );
      expect(
        () => BehaviorActionCatalog.decode({
          'type': 'copyToClipboard',
          'text': 'abc',
          'targetComponentId': 'field-1',
        }),
        throwsFormatException,
      );
      expect(
        () => BehaviorActionCatalog.decode({
          'type': 'showMessage',
          'message': 'ok',
          'durationMs': 0,
        }),
        throwsFormatException,
      );

      final behavior = ComponentBehavior(
        id: 'b-else-debounce',
        event: BehaviorEvent.onChanged,
        validator: const ValueBehaviorValidator.isFill(),
        action: showMsg,
        elseAction: goBack,
        debounceMs: 300,
      );
      final decodedBehavior = ComponentBehavior.fromJson(behavior.toJson());
      expect(decodedBehavior, equals(behavior));
      expect(
        decodedBehavior.remapComponentIds({'field-email': 'field-email-2'}),
        equals(behavior),
      );

      final behaviorWithCopy = ComponentBehavior(
        id: 'b-copy',
        event: BehaviorEvent.onTap,
        action: copy,
      );
      final remappedCopy = behaviorWithCopy.remapComponentIds({
        'field-email': 'field-email-copy',
      });
      expect(
        (remappedCopy.action as CopyToClipboardAction).targetComponentId,
        'field-email-copy',
      );

      expect(
        () => ComponentBehavior(
          id: 'bad-else',
          event: BehaviorEvent.onTap,
          action: showMsg,
          elseAction: goBack,
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => ComponentBehavior(
          id: 'bad-debounce',
          event: BehaviorEvent.onHover,
          action: const TooltipAction(message: 'Info'),
          debounceMs: 200,
        ).validate(),
        throwsFormatException,
      );

      final codegen = DartCodegenContext(
        appearance: Appearance(),
        registry: Registry()..bootstrap(),
      );
      final formatted = codegen.formatBehavior(behavior);
      expect(formatted, contains('elseAction: const GoBackAction'));
      expect(formatted, contains('debounceMs: 300'));
      expect(formatted, contains('ShowMessageAction'));
      expect(codegen.formatBehaviorAction(removeItem), contains('RemoveArrayItemAction'));
      expect(codegen.formatBehaviorAction(copy), contains('CopyToClipboardAction'));
    });

    testWidgets('GoBackAction pops route and falls back when cannot pop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (_) => Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pushNamed('/second'),
                    child: const Text('Push'),
                  ),
                  ElevatedButton(
                    onPressed: () => const GoBackAction(
                      fallbackPagePath: '/fallback',
                    ).execute(context),
                    child: const Text('Fallback'),
                  ),
                ],
              ),
            ),
            '/second': (_) => Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => const GoBackAction().execute(context),
                child: const Text('Back'),
              ),
            ),
          },
        ),
      );

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(find.text('Back'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Push'), findsOneWidget);
    });

    testWidgets('ShowMessageAction & CopyToClipboardAction execute cleanly', (tester) async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final dir = Directory.systemTemp.createTempSync('scl_show_copy_test_');
      final store = JsonRepositoryStore(dir);
      addTearDown(() async {
        store.dispose();
        if (dir.existsSync()) await dir.delete(recursive: true);
      });
      store.registerRepository(
        RepositoryImpl(id: 'demo', json: {'email': 'contact@exemple.fr'}),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JsonRepositoryScope(
              store: store,
              child: Builder(
                builder: (context) => Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => const ShowMessageAction(
                        message: 'Sauvegarde OK',
                        severity: BehaviorMessageSeverity.success,
                      ).execute(context),
                      child: const Text('Notify'),
                    ),
                    ElevatedButton(
                      onPressed: () => const CopyToClipboardAction(
                        binding: JsonTextBinding(
                          repositoryId: 'demo',
                          path: 'email',
                        ),
                        feedbackMessage: 'Email copié !',
                      ).execute(context),
                      child: const Text('Copy'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Notify'));
      await tester.pump();
      expect(find.text('Sauvegarde OK'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.text('Copy'))).clearSnackBars();
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text('Copy'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(copiedText, 'contact@exemple.fr');
      expect(find.text('Email copié !'), findsOneWidget);
    });

    testWidgets('RemoveArrayItemAction deletes selected row immediately (confirm=false) and updates adjacent selection', (tester) async {
      final dir = Directory.systemTemp.createTempSync('scl_remove_action_');
      final store = JsonRepositoryStore(dir);
      addTearDown(() async {
        store.dispose();
        if (dir.existsSync()) await dir.delete(recursive: true);
      });
      store.registerRepository(
        RepositoryImpl(
          id: 'crm',
          json: {
            'clients': [
              {'nom': 'Alice'},
              {'nom': 'Bob'},
              {'nom': 'Claire'},
            ],
          },
        ),
      );
      final selection = store.bindingOf('crm').array('clients')..select(const [], 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JsonRepositoryScope(
              store: store,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => const RemoveArrayItemAction(
                    binding: JsonTextBinding(
                      repositoryId: 'crm',
                      path: 'clients',
                    ),
                  ).execute(context),
                  child: const Text('Delete'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await tester.tap(find.text('Delete'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      final items = await store.readArray('crm', 'clients');
      expect(items, [
        {'nom': 'Alice'},
        {'nom': 'Claire'},
      ]);
      expect(selection.indexFor(const []), 1);
    });
  });

  group('ComponentBehavior.elseAction & debounceMs in BehaviorDispatcher', () {
    testWidgets('executes elseAction when validator returns false and debounces rapid triggers', (tester) async {
      final bus = SuperEventBus();
      addTearDown(bus.close);
      final okEvents = <SuperComponentEvent>[];
      final errEvents = <SuperComponentEvent>[];
      final debouncedEvents = <SuperComponentEvent>[];
      final subs = [
        bus.on('valid.ok').listen(okEvents.add),
        bus.on('valid.err').listen(errEvents.add),
        bus.on('search.debounced').listen(debouncedEvents.add),
      ];
      addTearDown(() async {
        for (final s in subs) {
          await s.cancel();
        }
      });

      final dir = Directory.systemTemp.createTempSync('scl_else_debounce_');
      final store = JsonRepositoryStore(dir);
      addTearDown(() async {
        store.dispose();
        if (dir.existsSync()) await dir.delete(recursive: true);
      });
      store.registerRepository(
        RepositoryImpl(id: 'form', json: {'email': '', 'query': 'a'}),
      );

      final guardedBehavior = ComponentBehavior(
        id: 'b-guarded',
        event: BehaviorEvent.onTap,
        validator: const ValueBehaviorValidator.bindingIsFill(
          JsonTextBinding(repositoryId: 'form', path: 'email'),
        ),
        action: EmitEventAction(eventId: 'valid.ok'),
        elseAction: EmitEventAction(eventId: 'valid.err'),
      );
      final debouncedBehavior = ComponentBehavior(
        id: 'b-debounced',
        event: BehaviorEvent.onChanged,
        debounceMs: 120,
        action: EmitEventAction(eventId: 'search.debounced'),
      );

      final appearance = Appearance()
          .withAddedBehavior('btn', guardedBehavior)
          .withAddedBehavior('search', debouncedBehavior);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Column(
                children: [
                  Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => BehaviorDispatcher.dispatch(
                        context,
                        componentId: 'btn',
                        componentType: 'action',
                        event: BehaviorEvent.onTap,
                      ),
                      child: const Text('Submit'),
                    ),
                  ),
                  Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => BehaviorDispatcher.dispatch(
                        context,
                        componentId: 'search',
                        componentType: 'value',
                        event: BehaviorEvent.onChanged,
                        data: {'value': DateTime.now().microsecondsSinceEpoch},
                      ),
                      child: const Text('Type'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(
          router: router,
          eventBus: bus,
          repositoryStore: store,
        ),
      );
      await tester.pumpAndSettle();
      final scaffoldCtx = tester.element(find.byType(Scaffold).first);
      StyleEditScope.controllerOf(scaffoldCtx)!.value = false;
      AppearanceScope.controllerOf(scaffoldCtx)!.value = appearance;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(okEvents, isEmpty);
      expect(errEvents, hasLength(1));

      await tester.runAsync(() async {
        await store.replaceValue('form', 'email', 'a@b.fr');
      });
      await tester.tap(find.text('Submit'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(okEvents, hasLength(1));
      expect(errEvents, hasLength(1));

      // Debounce : 3 rafales rapides ne produisent qu'une seule exécution après 120ms.
      await tester.tap(find.text('Type'));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(find.text('Type'));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(find.text('Type'));
      await tester.pump(const Duration(milliseconds: 40));
      expect(debouncedEvents, isEmpty);

      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 30));
      expect(debouncedEvents, hasLength(1));
    });
  });

  group('Advanced BehaviorValidators (>=, <=, ISO dates, count*, containerIsValid)', () {
    testWidgets('evaluates greaterOrEqual, lessOrEqual, ISO dates, count*, and recursive container validity', (tester) async {
      final dir = Directory.systemTemp.createTempSync('scl_adv_validators_');
      final store = JsonRepositoryStore(dir);
      addTearDown(() async {
        store.dispose();
        if (dir.existsSync()) await dir.delete(recursive: true);
      });
      store.registerRepository(
        RepositoryImpl(
          id: 'adv',
          json: {
            'score': 10,
            'echeance': '2026-11-22',
            'items': ['a', 'b', 'c'],
          },
        ),
      );

      var field1Valid = true;
      var field2Valid = false;
      ComponentRuntimeValueRegistry.instance.register(
        ComponentRuntimeValueEntry(
          token: 'f1',
          componentId: 'field-1',
          componentType: 'value',
          readValue: () => 'ok',
          readIsValid: () => field1Valid,
        ),
      );
      ComponentRuntimeValueRegistry.instance.register(
        ComponentRuntimeValueEntry(
          token: 'f2',
          componentId: 'field-2',
          componentType: 'value',
          readValue: () => '',
          readIsValid: () => field2Valid,
        ),
      );

      final appearance = Appearance(
        components: {
          'form-card': SuperLayoutConfig(
            placements: const {
              SuperLayoutZone.center: ['field-1', 'field-2'],
            },
            slotTypes: const {
              'field-1': 'registry:Value',
              'field-2': 'registry:Value',
            },
          ),
          'field-1': const SuperValueConfig(mode: SuperValueMode.input),
          'field-2': const SuperValueConfig(mode: SuperValueMode.input),
        },
      );

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

      final evalCtx = BehaviorValidationContext(
        context: capturedContext,
        componentId: 'btn',
        componentType: 'action',
        event: BehaviorEvent.onTap,
        appearance: appearance,
        repositoryStore: store,
      );

      expect(
        await BehaviorValidatorEvaluator.evaluate(
          BehaviorValidatorCatalog.decode({
            'type': 'bindingGreaterOrEqual',
            'binding': {'repositoryId': 'adv', 'path': 'score'},
            'value': 10,
          }),
          evalCtx,
        ),
        isTrue,
      );
      expect(
        await BehaviorValidatorEvaluator.evaluate(
          BehaviorValidatorCatalog.decode({
            'type': 'bindingLessOrEqual',
            'binding': {'repositoryId': 'adv', 'path': 'echeance'},
            'value': '2026-11-22',
          }),
          evalCtx,
        ),
        isTrue,
      );
      expect(
        await BehaviorValidatorEvaluator.evaluate(
          BehaviorValidatorCatalog.decode({
            'type': 'bindingGreaterThan',
            'binding': {'repositoryId': 'adv', 'path': 'echeance'},
            'value': '2026-10-01',
          }),
          evalCtx,
        ),
        isTrue,
      );
      expect(
        await BehaviorValidatorEvaluator.evaluate(
          BehaviorValidatorCatalog.decode({
            'type': 'bindingCountEquals',
            'binding': {'repositoryId': 'adv', 'path': 'items'},
            'value': 3,
          }),
          evalCtx,
        ),
        isTrue,
      );
      expect(
        await BehaviorValidatorEvaluator.evaluate(
          BehaviorValidatorCatalog.decode({
            'type': 'bindingCountGreaterThan',
            'binding': {'repositoryId': 'adv', 'path': 'items'},
            'value': 2,
          }),
          evalCtx,
        ),
        isTrue,
      );
      expect(
        await BehaviorValidatorEvaluator.evaluate(
          BehaviorValidatorCatalog.decode({
            'type': 'bindingCountLessThan',
            'binding': {'repositoryId': 'adv', 'path': 'items'},
            'value': 4,
          }),
          evalCtx,
        ),
        isTrue,
      );

      // Validation récursive du conteneur 'form-card'
      const containerValid = ValueBehaviorValidator.otherIsValid('form-card');
      const containerInvalid = ValueBehaviorValidator.otherIsInvalid('form-card');
      expect(await BehaviorValidatorEvaluator.evaluate(containerValid, evalCtx), isFalse);
      expect(await BehaviorValidatorEvaluator.evaluate(containerInvalid, evalCtx), isTrue);

      field2Valid = true;
      expect(await BehaviorValidatorEvaluator.evaluate(containerValid, evalCtx), isTrue);
      expect(await BehaviorValidatorEvaluator.evaluate(containerInvalid, evalCtx), isFalse);
    });
  });

  if (_hasQuickJsDll()) {
    group('RunJavaScriptAction ctx.get, ctx.removeAt, and ctx.select (QuickJS)', () {
      test('supports cross-repo ctx.get, atomic ctx.removeAt, and ctx.select', () async {
        final dir = Directory.systemTemp.createTempSync('scl_js_ext_');
        final store = JsonRepositoryStore(dir);
        addTearDown(() async {
          store.dispose();
          if (dir.existsSync()) await dir.delete(recursive: true);
        });

        store.registerRepository(
          RepositoryImpl(id: 'config_repo', json: {'taux': 1.2}),
        );
        store.registerRepository(
          RepositoryImpl(
            id: 'orders_repo',
            json: {
              'totalTtc': 0,
              'items': [
                {'label': 'A', 'ht': 100},
                {'label': 'B', 'ht': 200},
                {'label': 'C', 'ht': 300},
              ],
            },
          ),
        );

        await store.runJavaScriptAction(
          repositoryId: 'orders_repo',
          code: '''
const taux = ctx.get('taux', 'config_repo', 1);
ctx.set('totalTtc', doc.items[2].ht * taux);
ctx.removeAt('items', 0);
ctx.select('items', 1);
''',
        );

        final doc = await store.readDocument('orders_repo') as Map<String, Object?>;
        expect(doc['totalTtc'], 360.0);
        expect(doc['items'], [
          {'label': 'B', 'ht': 200},
          {'label': 'C', 'ht': 300},
        ]);
        expect(store.bindingOf('orders_repo').array('items').indexFor(const []), 1);
      });
    });
  }
}
