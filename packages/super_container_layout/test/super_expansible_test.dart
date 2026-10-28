import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
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
    directory = await Directory.systemTemp.createTemp('super-expansible-test-');
    repositoryStore = JsonRepositoryStore(directory);
    await repositoryStore.create('StateRepo');
    repositoryId = await repositoryStore.idOf('StateRepo');
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
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {});
    await tester.pump();
  }

  testWidgets(
    'SuperExpansible mounts native Flutter Expansible and toggles on header tap',
    (tester) async {
      final registry = Registry()..bootstrap();
      final states = <bool>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => SuperPage(
              child: Column(
                children: [
                  SuperExpansible(
                    id: 'my-expansible',
                    header: const Text('Section Header'),
                    body: const Text('Hidden Body Content'),
                    onExpansionChanged: states.add,
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
          registry: registry,
          appearanceStore: AppearanceStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SuperExpansible), findsOneWidget);
      expect(find.byType(Expansible), findsOneWidget);
      expect(find.text('Section Header'), findsOneWidget);
      // Collapsed by default: body is offstage and hit-test invisible
      expect(find.text('Hidden Body Content'), findsNothing);
      expect(
        find.text('Hidden Body Content', skipOffstage: false),
        findsOneWidget,
      );

      // Tap header to expand
      await tester.tap(find.text('Section Header'));
      await tester.pumpAndSettle();

      expect(find.text('Hidden Body Content'), findsOneWidget);
      expect(states, [true]);

      // Tap header again to collapse
      await tester.tap(find.text('Section Header'));
      await tester.pumpAndSettle();

      expect(find.text('Hidden Body Content'), findsNothing);
      expect(states, [true, false]);
    },
  );

  testWidgets(
    'SuperExpansible supports two-way boolean JSON repository binding',
    (tester) async {
      final binding = JsonTextBinding(
        repositoryId: repositoryId,
        path: 'ui.panelOpen',
      );
      await tester.runAsync(
        () => repositoryStore.writeAttribute(
          binding,
          'true',
          expectedValue: null,
          asBool: true,
        ),
      );

      final registry = Registry()..bootstrap();
      registry
          .nativeComponentController('bound-exp')
          .value = NativeComponentConfig(
        binding: binding,
        regions: const {'header': true, 'body': true},
        placements: const {
          'header': ['header'],
          'body': ['body'],
        },
      );

      await real(
        tester,
        () => tester.pumpWidget(
          JsonRepositoryScope(
            store: repositoryStore,
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    SuperExpansible(
                      id: 'bound-exp',
                      nativeConfig: registry
                          .nativeComponentController('bound-exp')
                          .value,
                      header: const Text('Bound Header'),
                      body: const Text('Bound Body'),
                    ),
                    SuperValue(
                      id: 'bound-switch',
                      config: SuperValueConfig(
                        mode: SuperValueMode.input,
                        kind: SuperValueKind.switchControl,
                        label: 'Toggle Panel',
                        binding: binding,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // Initial value in repository is true -> Expansible starts expanded!
      expect(find.text('Bound Body'), findsOneWidget);

      // Tap header to collapse -> writes false to JSON repository
      await real(
        tester,
        () => tester.tap(find.text('Bound Header')),
        save: true,
      );
      expect(find.text('Bound Body'), findsNothing);

      final afterCollapse = await tester.runAsync(
        () => repositoryStore.readAttribute(binding),
      );
      expect(afterCollapse?.value, isFalse);

      // Toggle the bound SuperValue Switch -> expands SuperExpansible!
      await real(tester, () => tester.tap(find.byType(Switch)), save: true);
      expect(find.text('Bound Body'), findsOneWidget);

      final afterSwitch = await tester.runAsync(
        () => repositoryStore.readAttribute(binding),
      );
      expect(afterSwitch?.value, isTrue);
    },
  );

  testWidgets(
    'SuperExpansible resolves [?] wildcard bindings from array selection and supports edit mode controls',
    (tester) async {
      await tester.runAsync(() async {
        final existing = await repositoryStore.read('StateRepo');
        await repositoryStore.save(
          'StateRepo',
          '{\n'
              '  "sections": [\n'
              '    {"title": "A", "open": false},\n'
              '    {"title": "B", "open": true}\n'
              '  ]\n'
              '}\n',
          expectedText: existing,
        );
      });

      final wildcardBinding = JsonTextBinding(
        repositoryId: repositoryId,
        path: 'sections[?].open',
      );
      final initialConfig = NativeComponentConfig(
        binding: wildcardBinding,
        regions: const {'header': true, 'body': true},
        placements: const {
          'header': ['header'],
          'body': ['body'],
        },
      );
      final registry = Registry()..bootstrap();

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => SuperPage(
              maxAutoZoomExtent: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SuperExpansible(
                      id: 'wild-exp',
                      nativeConfig: initialConfig,
                      header: const Text('Wildcard Header'),
                      body: const Text('Wildcard Body'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await real(
        tester,
        () => tester.pumpWidget(
          SuperApp(
            router: router,
            registry: registry,
            repositoryStore: repositoryStore,
            appearanceStore: AppearanceStore(),
          ),
        ),
      );

      // No row selected yet -> collapsed
      expect(find.text('Wildcard Body'), findsNothing);

      // Select row 1 (where open == true) -> expands automatically!
      await real(tester, () async {
        repositoryStore
            .bindingOf(repositoryId)
            .array('sections')
            .select(const [], 1);
      });
      expect(find.text('Wildcard Body'), findsOneWidget);

      // Select row 0 (where open == false) -> collapses automatically!
      await real(tester, () async {
        repositoryStore
            .bindingOf(repositoryId)
            .array('sections')
            .select(const [], 0);
      });
      expect(find.text('Wildcard Body'), findsNothing);

      // Enable edit mode and use the header region action button to toggle expansion
      final context = tester.element(find.byType(SuperExpansible));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      final editor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperExpansible),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      editor.select('header');
      await tester.pumpAndSettle();

      final toggleBtn = find.byKey(
        const ValueKey('super-expansible-toggle-wild-exp'),
      );
      expect(toggleBtn, findsOneWidget);
      await real(tester, () => tester.tap(toggleBtn), save: true);
      expect(find.text('Wildcard Body'), findsOneWidget);

      final row0Open = await tester.runAsync(
        () => repositoryStore.readAttribute(
          JsonTextBinding(repositoryId: repositoryId, path: 'sections[0].open'),
        ),
      );
      expect(row0Open?.value, isTrue);
    },
  );

  testWidgets(
    'Empty Expansible placed in SuperLayout center zone in edit mode lays out without unbounded height error',
    (tester) async {
      final registry = Registry()..bootstrap();
      registry.nativeComponentController(
        'exp-center',
        fallback: NativeComponentConfig(
          properties: const {'initiallyExpanded': true},
          regions: const {'header': true, 'body': true},
        ),
      );
      registry.layoutController(
        'mainLayout',
        fallback: const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['exp-center'],
          },
          slotTypes: {'exp-center': 'registry:Expansible'},
        ),
      );

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => SuperPage(
              maxAutoZoomExtent: 0,
              child: Builder(
                builder: (ctx) {
                  final layoutConfig = SuperApp.of(ctx)
                      .getLayoutConfigById('mainLayout');
                  return ValueListenableBuilder<SuperLayoutConfig>(
                    valueListenable: layoutConfig,
                    builder: (context, config, _) => SuperLayout(
                      config: config,
                      onChanged: (value) => layoutConfig.value = value,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(
          router: router,
          registry: registry,
          appearanceStore: AppearanceStore(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SuperExpansible), findsOneWidget);

      // Switch to edit mode with empty header and body regions
      final context = tester.element(find.byType(SuperExpansible));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();

      // Expand in edit mode to also verify empty body region layout
      final editor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperExpansible),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      editor.select('header');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('super-expansible-toggle-exp-center')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Right-click on the header zone to open context menu and verify "Taille et flux de la zone"
      await tester.tap(
        find.byKey(const ValueKey('super-expansible-select-header')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      final flowMenuBtn = find.byKey(
        const ValueKey('style-menu-zone-flow-En-tête'),
      );
      expect(flowMenuBtn, findsOneWidget);
      expect(
        tester.widget<IconButton>(flowMenuBtn).tooltip,
        'Taille et flux de la zone En-tête\n'
        'Taille : Auto\n'
        'Direction : Ligne (Row) · Éléments : Étirer (flex : 1)\n'
        'Espacement : 0 px · Marge : 0 px',
      );
      expect(
        find.byKey(const ValueKey('style-menu-axis-En-tête')),
        findsOneWidget,
      );

      await tester.tap(flowMenuBtn);
      await tester.pumpAndSettle();
      expect(find.text('Flux de la zone : En-tête'), findsOneWidget);

      // Toggle off auto-size to set a fixed size on header
      await tester.tap(
        find.byKey(
          const ValueKey('super-expansible-flow-dialog-header-auto-size'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();

      final updated = registry.nativeComponentController('exp-center').value;
      expect(updated.regionSizeOf('header'), 48.0);
    },
  );

  testWidgets(
    'NativeComponentConfig serializes Expansible properties and duplicates in EditorPageGraph',
    (tester) async {
      final binding = JsonTextBinding(
        repositoryId: repositoryId,
        path: 'clients[?].expanded',
      );
      final config = NativeComponentConfig(
        properties: const {
          'initiallyExpanded': true,
          'maintainState': false,
          'headerClickToggles': false,
        },
        binding: binding,
        regions: const {'header': true, 'body': true},
        regionAxes: const {'header': Axis.vertical},
        regionFlows: const {
          'body': ZoneFlowConfig(spacing: 12, scrollable: true),
        },
        regionSizes: const {'body': 220},
        placements: const {
          'header': ['hdr-val'],
          'body': ['body-val'],
        },
        slotTypes: const {
          'hdr-val': 'registry:Value',
          'body-val': 'registry:Value',
        },
      );

      final json = config.toTypedJson();
      final decoded = ComponentConfig.fromJson(json) as NativeComponentConfig;
      expect(decoded.initiallyExpanded, isTrue);
      expect(decoded.maintainState, isFalse);
      expect(decoded.headerClickToggles, isFalse);
      expect(decoded.binding, equals(binding));
      expect(decoded.regionAxisOf('header'), Axis.vertical);
      expect(decoded.regionFlowOf('body').spacing, 12);
      expect(decoded.regionFlowOf('body').scrollable, isTrue);
      expect(decoded.regionSizeOf('body'), 220);
      expect(decoded.slotsOf('header'), ['hdr-val']);
      expect(decoded.slotsOf('body'), ['body-val']);

      // Verify JsonComponentType alias normalization
      expect(
        JsonComponentType.normalize('Expansible'),
        equals('registry:Expansible'),
      );

      // Verify EditorPageGraph duplication preserves Expansible config & children
      final registry = Registry()..bootstrap();
      final appearance = Appearance(
        components: {
          'page-1': NativeComponentConfig(
            regions: const {'body': true},
            placements: const {
              'body': ['exp-1'],
            },
            slotTypes: const {'exp-1': 'registry:Expansible'},
          ),
          'exp-1': config,
          'hdr-val': const SuperValueConfig(initialText: 'Titre'),
          'body-val': const SuperValueConfig(initialText: 'Détails'),
        },
      );

      final duplicated = EditorPageGraph.duplicate(
        appearance: appearance,
        registry: registry,
        sourcePageId: 'page-1',
        targetPageId: 'page-2',
      );

      final page2 = duplicated.nativeComponent('page-2');
      final copiedExpId = page2.slotsOf('body').single;
      expect(copiedExpId, isNot('exp-1'));
      final copiedExp = duplicated.nativeComponent(copiedExpId);
      expect(copiedExp.initiallyExpanded, isTrue);
      expect(copiedExp.maintainState, isFalse);
      expect(copiedExp.headerClickToggles, isFalse);
      expect(copiedExp.binding, equals(binding));
      expect(copiedExp.slotsOf('header').single, isNot('hdr-val'));
      expect(copiedExp.slotsOf('body').single, isNot('body-val'));
    },
  );
}
