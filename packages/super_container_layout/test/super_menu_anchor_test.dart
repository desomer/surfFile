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
    directory = await Directory.systemTemp.createTemp(
      'super-menu-anchor-test-',
    );
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
    'SuperMenuAnchor mounts native Flutter MenuAnchor and toggles on header tap',
    (tester) async {
      final registry = Registry()..bootstrap();
      final states = <bool>[];
      var openedCount = 0;
      var closedCount = 0;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => SuperPage(
              child: Column(
                children: [
                  SuperMenuAnchor(
                    id: 'my-menu-anchor',
                    header: const Text('Menu Trigger'),
                    body: const Text('Popup Body Content'),
                    onExpansionChanged: states.add,
                    onOpen: () => openedCount++,
                    onClose: () => closedCount++,
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

      expect(find.byType(SuperMenuAnchor), findsOneWidget);
      expect(find.byType(MenuAnchor), findsOneWidget);
      expect(find.text('Menu Trigger'), findsOneWidget);
      // Closed by default: popup content is not mounted in the overlay
      expect(find.text('Popup Body Content'), findsNothing);

      // Tap header to open menu
      await tester.tap(find.text('Menu Trigger'));
      await tester.pumpAndSettle();

      expect(find.text('Popup Body Content'), findsOneWidget);
      expect(states, [true]);
      expect(openedCount, 1);
      expect(closedCount, 0);

      // Tap header again to close menu
      await tester.tap(find.text('Menu Trigger'));
      await tester.pumpAndSettle();

      expect(find.text('Popup Body Content'), findsNothing);
      expect(states, [true, false]);
      expect(openedCount, 1);
      expect(closedCount, 1);
    },
  );

  testWidgets(
    'SuperMenuAnchor supports two-way boolean JSON repository binding',
    (tester) async {
      final binding = JsonTextBinding(
        repositoryId: repositoryId,
        path: 'ui.menuOpen',
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
          .nativeComponentController('bound-menu')
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
                    SuperMenuAnchor(
                      id: 'bound-menu',
                      nativeConfig: registry
                          .nativeComponentController('bound-menu')
                          .value,
                      header: const Text('Bound Menu Header'),
                      body: const Text('Bound Menu Body'),
                    ),
                    SuperValue(
                      id: 'bound-switch',
                      config: SuperValueConfig(
                        mode: SuperValueMode.input,
                        kind: SuperValueKind.switchControl,
                        label: 'Toggle Menu',
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

      // Initial value in repository is true -> MenuAnchor starts open!
      expect(find.text('Bound Menu Body'), findsOneWidget);

      // Tap header to close -> writes false to JSON repository
      await real(
        tester,
        () => tester.tap(find.text('Bound Menu Header')),
        save: true,
      );
      expect(find.text('Bound Menu Body'), findsNothing);

      final afterClose = await tester.runAsync(
        () => repositoryStore.readAttribute(binding),
      );
      expect(afterClose?.value, isFalse);

      // Toggle the bound SuperValue Switch -> opens SuperMenuAnchor!
      await real(tester, () => tester.tap(find.byType(Switch)), save: true);
      expect(find.text('Bound Menu Body'), findsOneWidget);

      final afterSwitch = await tester.runAsync(
        () => repositoryStore.readAttribute(binding),
      );
      expect(afterSwitch?.value, isTrue);
    },
  );

  testWidgets(
    'SuperMenuAnchor resolves [?] wildcard bindings from array selection and supports edit mode toggle',
    (tester) async {
      await tester.runAsync(() async {
        final existing = await repositoryStore.read('StateRepo');
        await repositoryStore.save(
          'StateRepo',
          '{\n'
              '  "menus": [\n'
              '    {"title": "A", "open": false},\n'
              '    {"title": "B", "open": true}\n'
              '  ]\n'
              '}\n',
          expectedText: existing,
        );
      });

      final wildcardBinding = JsonTextBinding(
        repositoryId: repositoryId,
        path: 'menus[?].open',
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
                    SuperMenuAnchor(
                      id: 'wild-menu',
                      nativeConfig: initialConfig,
                      header: const Text('Wildcard Menu Header'),
                      body: const Text('Wildcard Menu Body'),
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

      // No row selected yet -> closed
      expect(find.text('Wildcard Menu Body'), findsNothing);

      // Select row 1 (where open == true) -> opens automatically!
      await real(tester, () async {
        repositoryStore
            .bindingOf(repositoryId)
            .array('menus')
            .select(const [], 1);
      });
      expect(find.text('Wildcard Menu Body'), findsOneWidget);

      // Select row 0 (where open == false) -> closes automatically!
      await real(tester, () async {
        repositoryStore
            .bindingOf(repositoryId)
            .array('menus')
            .select(const [], 0);
      });
      expect(find.text('Wildcard Menu Body'), findsNothing);

      // Enable edit mode and use the header region action button to toggle menu
      final context = tester.element(find.byType(SuperMenuAnchor));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      final editor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperMenuAnchor),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      editor.select('header');
      await tester.pumpAndSettle();

      final toggleBtn = find.byKey(
        const ValueKey('super-menu-anchor-toggle-wild-menu'),
      );
      expect(toggleBtn, findsOneWidget);
      await real(tester, () => tester.tap(toggleBtn), save: true);
      expect(find.text('Wildcard Menu Body'), findsOneWidget);

      final row0Open = await tester.runAsync(
        () => repositoryStore.readAttribute(
          JsonTextBinding(repositoryId: repositoryId, path: 'menus[0].open'),
        ),
      );
      expect(row0Open?.value, isTrue);

      // Tap toggle button again in edit mode to close it
      await real(tester, () => tester.tap(toggleBtn), save: true);
      expect(find.text('Wildcard Menu Body'), findsNothing);
    },
  );

  testWidgets(
    'Empty Menu placed in SuperLayout center zone in edit mode lays out without intrinsic or unbounded errors',
    (tester) async {
      final registry = Registry()..bootstrap();
      registry.nativeComponentController(
        'menu-center',
        fallback: NativeComponentConfig(
          properties: const {'initiallyExpanded': true},
          regions: const {'header': true, 'body': true},
        ),
      );
      registry.layoutController(
        'mainLayout',
        fallback: const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['menu-center'],
          },
          slotTypes: {'menu-center': 'registry:Menu'},
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
      expect(find.byType(SuperMenuAnchor), findsOneWidget);

      // Switch to edit mode with empty header and body regions
      final context = tester.element(find.byType(SuperMenuAnchor));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();

      final editor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperMenuAnchor),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      editor.select('header');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Toggle menu closed then open in edit mode
      await tester.tap(
        find.byKey(const ValueKey('super-menu-anchor-toggle-menu-center')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('super-menu-anchor-toggle-menu-center')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Right-click on the header zone to open context menu and verify "Taille et flux de la zone"
      await tester.tap(
        find.byKey(const ValueKey('super-menu-anchor-select-header')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      final flowMenuBtn = find.byKey(
        const ValueKey('style-menu-zone-flow-En-tête'),
      );
      expect(flowMenuBtn, findsOneWidget);
      await tester.tap(flowMenuBtn);
      await tester.pumpAndSettle();
      expect(find.text('Flux de la zone : En-tête'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey('super-menu-anchor-flow-dialog-header-auto-size'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();

      final updated = registry.nativeComponentController('menu-center').value;
      expect(updated.regionSizeOf('header'), 48.0);
    },
  );

  testWidgets(
    'NativeComponentConfig serializes Menu properties, MenuAnchorAddForm edits draft, and EditorPageGraph duplicates Menu',
    (tester) async {
      final binding = JsonTextBinding(
        repositoryId: repositoryId,
        path: 'clients[?].menuOpen',
      );
      final config = NativeComponentConfig(
        properties: const {
          'initiallyExpanded': true,
          'headerClickToggles': false,
          'consumeOutsideTap': true,
          'toggleIcon': 'triangle',
          'toggleIconPosition': 'leading',
          'alignmentOffsetX': 15.0,
          'alignmentOffsetY': -10.0,
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
      expect(decoded.headerClickToggles, isFalse);
      expect(decoded.consumeOutsideTap, isTrue);
      expect(decoded.toggleIcon, 'triangle');
      expect(decoded.toggleIconPosition, 'leading');
      expect(decoded.alignmentOffsetX, 15.0);
      expect(decoded.alignmentOffsetY, -10.0);
      expect(decoded.alignmentOffset, const Offset(15.0, -10.0));
      expect(decoded.binding, equals(binding));
      expect(decoded.regionAxisOf('header'), Axis.vertical);
      expect(decoded.regionFlowOf('body').spacing, 12);
      expect(decoded.regionFlowOf('body').scrollable, isTrue);
      expect(decoded.regionSizeOf('body'), 220);
      expect(decoded.slotsOf('header'), ['hdr-val']);
      expect(decoded.slotsOf('body'), ['body-val']);

      // Verify JsonComponentType alias normalization
      expect(JsonComponentType.normalize('Menu'), equals('registry:Menu'));
      expect(
        JsonComponentType.normalize('MenuAnchor'),
        equals('registry:Menu'),
      );
      expect(
        JsonComponentType.normalize('SuperMenuAnchor'),
        equals('registry:Menu'),
      );
      expect(JsonComponentType.shortName('registry:Menu'), equals('Menu'));

      // Verify MenuAnchorAddForm updates draft
      var draft = NativeComponentConfig(
        regions: const {'header': true, 'body': true},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MenuAnchorAddForm(
                draft: draft,
                onChanged: (next) => setState(() => draft = next),
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('add-menu-anchor-initially-expanded')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('add-menu-anchor-consume-outside-tap')),
      );
      await tester.pumpAndSettle();
      expect(draft.initiallyExpanded, isTrue);
      expect(draft.consumeOutsideTap, isTrue);
      expect(
        find.byKey(const ValueKey('add-menu-anchor-toggle-icon-position')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('add-menu-anchor-toggle-icon')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chevron (expand_more / expand_less)').last);
      await tester.pumpAndSettle();
      expect(draft.toggleIcon, 'chevron');
      expect(
        find.byKey(const ValueKey('add-menu-anchor-toggle-icon-position')),
        findsOneWidget,
      );

      // Verify EditorPageGraph duplication preserves Menu config & children
      final registry = Registry()..bootstrap();
      final appearance = Appearance(
        components: {
          'page-1': NativeComponentConfig(
            regions: const {'body': true},
            placements: const {
              'body': ['menu-1'],
            },
            slotTypes: const {'menu-1': 'registry:Menu'},
          ),
          'menu-1': config,
          'hdr-val': const SuperValueConfig(initialText: 'Ouvrir'),
          'body-val': const SuperValueConfig(initialText: 'Options'),
        },
      );

      final duplicated = EditorPageGraph.duplicate(
        appearance: appearance,
        registry: registry,
        sourcePageId: 'page-1',
        targetPageId: 'page-2',
      );

      final page2 = duplicated.nativeComponent('page-2');
      final copiedMenuId = page2.slotsOf('body').single;
      expect(copiedMenuId, isNot('menu-1'));
      final copiedMenu = duplicated.nativeComponent(copiedMenuId);
      expect(copiedMenu.initiallyExpanded, isTrue);
      expect(copiedMenu.headerClickToggles, isFalse);
      expect(copiedMenu.consumeOutsideTap, isTrue);
      expect(copiedMenu.toggleIcon, 'triangle');
      expect(copiedMenu.toggleIconPosition, 'leading');
      expect(copiedMenu.alignmentOffset, const Offset(15.0, -10.0));
      expect(copiedMenu.binding, equals(binding));
      expect(copiedMenu.slotsOf('header').single, isNot('hdr-val'));
      expect(copiedMenu.slotsOf('body').single, isNot('body-val'));
    },
  );

  testWidgets(
    'SuperMenuAnchor renders open/closed toggleIcon with position and respects headerClickToggles',
    (tester) async {
      final registry = Registry()..bootstrap();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const SuperPage(
              child: Column(
                children: [
                  SuperMenuAnchor(
                    id: 'menu-default',
                    header: Text('Default Menu'),
                    body: Text('Default Popup'),
                  ),
                  SuperMenuAnchor(
                    id: 'menu-icon',
                    toggleIcon: 'triangle',
                    toggleIconPosition: 'trailing',
                    header: Text('Icon Menu'),
                    body: Text('Icon Popup'),
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

      // Hidden by default
      expect(
        find.byKey(
          const ValueKey('super-menu-anchor-header-toggle-icon-menu-default'),
        ),
        findsNothing,
      );

      // Shown when toggleIcon is 'triangle' (closed -> Icons.arrow_drop_down)
      final iconFinder = find.byKey(
        const ValueKey('super-menu-anchor-header-toggle-icon-menu-icon'),
      );
      expect(iconFinder, findsOneWidget);
      expect(tester.widget<Icon>(iconFinder).icon, Icons.arrow_drop_down);

      // Trailing position: icon is to the right of the header text
      expect(
        tester.getTopLeft(iconFinder).dx,
        greaterThan(tester.getTopLeft(find.text('Icon Menu')).dx),
      );

      // Tap icon to open menu -> switches to Icons.arrow_drop_up
      await tester.tap(iconFinder);
      await tester.pumpAndSettle();
      expect(find.text('Icon Popup'), findsOneWidget);
      expect(tester.widget<Icon>(iconFinder).icon, Icons.arrow_drop_up);

      // Tap icon again to close menu
      await tester.tap(iconFinder);
      await tester.pumpAndSettle();
      expect(find.text('Icon Popup'), findsNothing);
      expect(tester.widget<Icon>(iconFinder).icon, Icons.arrow_drop_down);

      // Switch to leading and arrow via controller
      final controller = registry.nativeComponentController('menu-icon');
      controller.value = controller.value
          .withToggleIcon('arrow')
          .withToggleIconPosition('leading');
      await tester.pumpAndSettle();
      expect(tester.widget<Icon>(iconFinder).icon, Icons.arrow_downward);
      expect(
        tester.getTopLeft(iconFinder).dx,
        lessThan(tester.getTopLeft(find.text('Icon Menu')).dx),
      );
    },
  );
}
