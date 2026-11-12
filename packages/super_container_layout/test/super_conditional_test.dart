import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late JsonRepositoryStore repositoryStore;
  late String repositoryId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    directory = await Directory.systemTemp.createTemp('super-conditional-test-');
    repositoryStore = JsonRepositoryStore(directory);
    await repositoryStore.create('CondRepo');
    repositoryId = await repositoryStore.idOf('CondRepo');
  });

  tearDown(() async {
    repositoryStore.dispose();
    await directory.delete(recursive: true);
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> real(
    WidgetTester tester,
    Future<void> Function() action, {
    bool save = false,
  }) async {
    await tester.runAsync(() async {
      await action();
      await tester.pump();
      await Future<void>.delayed(Duration(milliseconds: save ? 500 : 120));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    Widget child,
    WidgetTester tester,
    Registry registry, {
    AppearanceStore? store,
  }) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => child)],
    );
    addTearDown(router.dispose);
    await real(
      tester,
      () => tester.pumpWidget(
        SuperApp(
          router: router,
          registry: registry,
          repositoryStore: repositoryStore,
          appearanceStore: store ?? AppearanceStore(),
        ),
      ),
    );
  }

  test(
    'SuperConditionalConfig round-trips through JSON, ComponentConfigCatalog and DartCodegen',
    () {
      final config = SuperConditionalConfig(
        binding: JsonTextBinding(
          repositoryId: repositoryId,
          path: 'nodes[?].type',
        ),
        cases: const ['string', 'number'],
        hasDefaultCase: true,
        initialCase: 'string',
        maintainState: true,
        emptyText: 'Aucune vue',
        placements: const {
          'case:string': ['val-str'],
          'case:number': ['val-num'],
          'default': ['val-def'],
        },
        slotTypes: const {
          'val-str': 'registry:Value',
          'val-num': 'registry:Value',
          'val-def': 'registry:Value',
        },
        zoneAxes: const {'case:string': Axis.horizontal},
      );

      final typedJson = config.toTypedJson();
      expect(typedJson['type'], 'conditional');
      final decoded = ComponentConfig.fromJson(typedJson);
      expect(decoded, isA<SuperConditionalConfig>());
      expect(decoded, equals(config));

      final compactJson = config.toTypedCompactJson();
      expect(ComponentConfig.fromJson(compactJson), equals(config));

      // Case mutations
      final withBool = config.withCaseAdded('boolean');
      expect(withBool.cases, ['string', 'number', 'boolean']);

      final renamed = withBool.withCaseRenamed('string', 'text');
      expect(renamed.cases, ['text', 'number', 'boolean']);
      expect(renamed.initialCase, 'text');
      expect(renamed.slotsOf('case:text'), ['val-str']);
      expect(renamed.zoneAxisOf('case:text'), Axis.horizontal);

      final removed = renamed.withoutCase('number');
      expect(removed.cases, ['text', 'boolean']);
      expect(removed.slotsOf('case:number'), isEmpty);
      expect(removed.placedSlotIds, {'val-str', 'val-def'});

      // Dart codegen check
      final registry = Registry()..bootstrap();
      final appearance = Appearance(
        components: {
          'cond-1': config,
          'val-str': const SuperValueConfig(initialText: 'Texte'),
          'val-num': const SuperValueConfig(initialText: 'Nombre'),
          'val-def': const SuperValueConfig(initialText: 'Défaut'),
        },
      );
      final codegenCtx = DartCodegenContext(
        appearance: appearance,
        registry: registry,
      );
      final code = const SuperConditionalDartGenerator().generateWidget(
        codegenCtx,
        id: 'cond-1',
      );
      expect(code, contains('SuperConditional('));
      expect(code, contains('SuperConditionalConfig('));
      expect(code, contains("'case:string': ['val-str']"));
    },
  );

  testWidgets(
    'SuperConditional switches displayed child according to repository binding and shows case toolbar in edit mode',
    (tester) async {
      final registry = Registry()..bootstrap();
      final typeBinding = JsonTextBinding(
        repositoryId: repositoryId,
        path: 'node.type',
      );
      await real(
        tester,
        () => repositoryStore.writeAttribute(
          typeBinding,
          'string',
          expectedValue: null,
        ),
      );

      final editController = ValueNotifier<bool>(false);
      addTearDown(editController.dispose);

      await mount(
        StyleEditScope(
          controller: editController,
          child: SuperPage(
            child: SuperConditional(
              id: 'my-cond',
              config: SuperConditionalConfig(
                binding: typeBinding,
                cases: const ['string', 'number'],
                hasDefaultCase: true,
                placements: const {
                  'case:string': ['slot-string'],
                  'case:number': ['slot-number'],
                  'default': ['slot-default'],
                },
              ),
              slots: [
                BuilderSlot(
                  id: 'slot-string',
                  label: 'slot-string',
                  builder: (_) => const Text('Vue String'),
                ),
                BuilderSlot(
                  id: 'slot-number',
                  label: 'slot-number',
                  builder: (_) => const Text('Vue Number'),
                ),
                BuilderSlot(
                  id: 'slot-default',
                  label: 'slot-default',
                  builder: (_) => const Text('Vue Default'),
                ),
              ],
            ),
          ),
        ),
        tester,
        registry,
      );

      // In runtime mode: shows 'Vue String' and hides edit toolbar
      expect(find.text('Vue String'), findsOneWidget);
      expect(find.text('Vue Number'), findsNothing);
      expect(find.text('Vue Default'), findsNothing);
      expect(
        find.byKey(const ValueKey('super-conditional-toolbar-my-cond')),
        findsNothing,
      );

      // Change bound value to 'number'
      await real(
        tester,
        () => repositoryStore.writeAttribute(
          typeBinding,
          'number',
          expectedValue: 'string',
        ),
      );
      expect(find.text('Vue String'), findsNothing);
      expect(find.text('Vue Number'), findsOneWidget);
      expect(find.text('Vue Default'), findsNothing);

      // Change bound value to an unknown case -> falls back to 'default'
      await real(
        tester,
        () => repositoryStore.writeAttribute(
          typeBinding,
          'boolean',
          expectedValue: 'number',
        ),
      );
      expect(find.text('Vue String'), findsNothing);
      expect(find.text('Vue Number'), findsNothing);
      expect(find.text('Vue Default'), findsOneWidget);

      // Enable edit mode -> toolbar appears and allows switching between cases
      editController.value = true;
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('super-conditional-toolbar-my-cond')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const ValueKey(
            'super-conditional-case-selector-my-cond-case:string',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Vue String'), findsOneWidget);
    },
  );
}
