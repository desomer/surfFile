import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/main.dart' as demo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> pumpPage(
    WidgetTester tester,
    SuperPage page, {
    Registry? registry,
    AppearanceStore? store,
  }) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => page)],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(router: router, registry: registry, appearanceStore: store),
    );
    await tester.pumpAndSettle();
  }

  Future<void> toggleRegion(
    WidgetTester tester,
    ScaffoldPageRegion region,
  ) async {
    final toggle = find.byKey(ValueKey('scaffold-page-switch-${region.name}'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }

  for (final (region, factory) in [
    (ScaffoldPageRegion.appBar, 'AppBar'),
    (ScaffoldPageRegion.bottomNavigationBar, 'BottomNavigationBar'),
  ]) {
    testWidgets('${region.name} catalog accepts only its category', (
      tester,
    ) async {
      final registry = Registry()..bootstrap();
      await pumpPage(
        tester,
        SuperPage(
          appBar: AppBar(title: const Text('Provided header')),
          bottomNavigationBar: const SizedBox(height: 40),
        ),
        registry: registry,
      );
      final editor = tester.state<NativeComponentEditorState>(
        find.byType(NativeComponentEditor),
      );
      unawaited(editor.add(region.name));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('scaffold-page-add-slot-factory:$factory')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('scaffold-page-add-slot-scaffold:${region.name}')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-add-slot-scaffold:body')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-add-slot-factory:Layout')),
        findsNothing,
      );
      final other = region == ScaffoldPageRegion.appBar
          ? 'BottomNavigationBar'
          : 'AppBar';
      expect(
        find.byKey(ValueKey('scaffold-page-add-slot-factory:$other')),
        findsNothing,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('layout registry catalog and instances retain their tags', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    registry.registerComponent(
      'tagged',
      const RegisteredComponent(
        label: 'Tagged',
        slotId: 'legacy-tagged',
        tags: {'appBar', 'text'},
        builder: _title,
      ),
    );
    await pumpPage(
      tester,
      const SuperPage(
        child: SuperLayout(
          config: SuperLayoutConfig(
            slotTypes: {
              'factory-instance': 'registry:AppBar',
              'registered-instance': 'legacy-tagged',
            },
          ),
          zoneTagFilters: {
            SuperLayoutZone.center: ComponentTagFilter(include: {'appBar'}),
          },
        ),
      ),
      registry: registry,
    );
    final layout = tester.state<SuperLayoutState>(find.byType(SuperLayout));
    expect(layout.searchSlot('factory-instance')!.tags, {'appBar'});
    expect(layout.searchSlot('registered-instance')!.tags, {'appBar', 'text'});
    final surface = tester.widget<EditorSlot>(
      find
          .descendant(
            of: find.byType(SuperLayout),
            matching: find.byType(EditorSlot),
          )
          .first,
    );
    unawaited(surface.onAdd!());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('super-layout-add-slot-registry:AppBar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('super-layout-add-slot-legacy-tagged')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('super-layout-add-slot-registry:Card')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('super-layout-add-slot-legacy-tagged')),
    );
    await tester.pumpAndSettle();
    final id = layout.config.placedSlotIds.single;
    expect(id, isNot('legacy-tagged'));
    expect(layout.config.slotTypeOf(id), 'legacy-tagged');
    expect(layout.searchSlot(id)!.tags, {'appBar', 'text'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('history preserves legacy incompatible native placements', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    registry.registerFactory(
      'compatible',
      const SizedBox(height: 24),
      tags: {'appBar'},
    );
    registry.registerComponent(
      'legacy',
      const RegisteredComponent(label: 'Legacy title', builder: _title),
    );
    await pumpPage(
      tester,
      SuperPage(
        pageConfig: ScaffoldPageConfig(
          placements: {
            ScaffoldPageRegion.appBar: ['old'],
            ScaffoldPageRegion.body: ['scaffold:body'],
          },
          slotTypes: {'old': 'component:legacy'},
        ),
      ),
      registry: registry,
    );
    expect(find.text('Registered title'), findsOneWidget);
    final context = tester.element(find.byType(SuperPage));
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    final history = EditorHistoryScope.controllerOf(context)!;
    final editor = tester.state<NativeComponentEditorState>(
      find.byType(NativeComponentEditor),
    );
    unawaited(editor.add('appBar'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scaffold-page-add-slot-factory:compatible')),
    );
    await tester.pumpAndSettle();
    final controller = registry.scaffoldPageController('root');
    expect(controller.value.slotsOf(ScaffoldPageRegion.appBar), hasLength(2));
    history.undo();
    await tester.pumpAndSettle();
    expect(controller.value.slotsOf(ScaffoldPageRegion.appBar), ['old']);
    expect(find.text('Registered title'), findsOneWidget);
    history.redo();
    await tester.pumpAndSettle();
    expect(controller.value.slotsOf(ScaffoldPageRegion.appBar), hasLength(2));
    expect(find.text('Registered title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('region switches round trip and keep disabled placements', () {
    final config =
        ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.drawer: ['navigation'],
              },
              slotTypes: {'navigation': 'component:navigation'},
            )
            .withRegionEnabled(ScaffoldPageRegion.drawer, false)
            .withRegionEnabled(ScaffoldPageRegion.appBar, true);
    final restored = ScaffoldPageConfig.fromJson(config.toJson());
    expect(restored.isEnabled(ScaffoldPageRegion.body), isTrue);
    expect(restored.isEnabled(ScaffoldPageRegion.appBar), isTrue);
    expect(restored.isEnabled(ScaffoldPageRegion.drawer), isFalse);
    expect(restored.slotsOf(ScaffoldPageRegion.drawer), ['navigation']);
    expect(restored.withoutSlot('navigation').regions, restored.regions);
    final legacy = ScaffoldPageConfig.fromJson({
      'placements': {
        'drawer': [
          {'id': 'navigation', 'type': 'component:navigation'},
        ],
      },
    });
    expect(legacy.isEnabled(ScaffoldPageRegion.drawer), isTrue);
    for (final regions in [
      {'drawer': 'yes'},
      {'unknown': true},
      {'body': false},
    ]) {
      expect(
        () =>
            ScaffoldPageConfig.fromJson({'placements': {}, 'regions': regions}),
        throwsFormatException,
      );
    }
  });

  testWidgets(
    'context switches reveal selectable regions with local additions',
    (tester) async {
      final registry = Registry()
        ..registerComponent(
          'test-title',
          const RegisteredComponent(
            label: 'Test title',
            tags: {'bottomNavigationBar'},
            builder: _title,
          ),
        );
      await pumpPage(tester, const SuperPage(), registry: registry);
      final context = tester.element(find.byType(SuperPage));
      final editMode = StyleEditScope.controllerOf(context)!;
      final controller = registry.scaffoldPageController('root');
      editMode.value = true;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scaffold-page-add-appBar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-add-drawer')),
        findsNothing,
      );
      await tester.tapAt(const Offset(40, 120), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      final bodySubtitle = find.byKey(const ValueKey('style-menu-zone-Corps'));
      expect(bodySubtitle, findsOneWidget);
      expect(tester.widget<Text>(bodySubtitle).data, 'Page');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('style-menu-Corps')),
          matching: find.byIcon(EditorSlot.zoneMenuIcon),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('style-menu-Corps')),
          matching: find.text('zone Corps'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNWidgets(6));
      expect(
        find.byKey(const ValueKey('scaffold-page-switch-body')),
        findsNothing,
      );
      await toggleRegion(tester, ScaffoldPageRegion.bottomNavigationBar);
      expect(
        controller.value.isEnabled(ScaffoldPageRegion.bottomNavigationBar),
        isTrue,
      );
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('scaffold-page-select-bottomNavigationBar')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('scaffold-page-selected-bottomNavigationBar'),
        ),
        findsOneWidget,
      );
      expect(LayoutSelection.path.value, ['Page', 'Barre basse']);
      expect(
        find
            .byKey(const ValueKey('scaffold-page-add-bottomNavigationBar'))
            .hitTestable(),
        findsOneWidget,
      );
      final history = EditorHistoryScope.controllerOf(context)!;
      history.undo();
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, isEmpty);
      expect(
        controller.value.isEnabled(ScaffoldPageRegion.bottomNavigationBar),
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-add-bottomNavigationBar')),
        findsNothing,
      );
      history.redo();
      await tester.pumpAndSettle();
      LayoutSelection.select(['Page']);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scaffold-page-add-bottomNavigationBar')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('scaffold-page-add-bottomNavigationBar')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('scaffold-page-add-slot-component:test-title'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Registered title'), findsOneWidget);
      history.undo();
      await tester.pumpAndSettle();
      editMode.value = false;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scaffold-page-add-body')),
        findsNothing,
      );
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
        isNull,
      );
      expect(LayoutSelection.path.value, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final region in [
    ScaffoldPageRegion.drawer,
    ScaffoldPageRegion.endDrawer,
  ]) {
    testWidgets('${region.name} switch opens its empty editing region', (
      tester,
    ) async {
      final registry = Registry();
      await pumpPage(tester, const SuperPage(), registry: registry);
      StyleEditScope.controllerOf(tester.element(find.byType(SuperPage)))!
              .value =
          true;
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(40, 120), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('style-menu-Corps')),
          matching: find.text('zone Corps'),
        ),
      );
      await tester.pumpAndSettle();
      await toggleRegion(tester, region);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('scaffold-page-add-${region.name}')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ValueKey('scaffold-page-select-${region.name}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('scaffold-page-selected-${region.name}')),
        findsOneWidget,
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(Drawer)) + const Offset(20, 100),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Configurer la page…'), findsNothing);
      final label = region == ScaffoldPageRegion.drawer
          ? 'Drawer gauche'
          : 'Drawer droit';
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('style-menu-$label')),
          matching: find.text('zone $label'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scaffold-page-settings')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'switches hide provided content without losing it across restart',
    (tester) async {
      final store = AppearanceStore();
      final registry = Registry();
      const page = SuperPage(
        bottomNavigationBar: SizedBox(height: 32, child: Text('Saved footer')),
        child: Text('Body'),
      );
      await pumpPage(tester, page, registry: registry, store: store);
      final context = tester.element(find.byType(SuperPage));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(40, 120), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('style-menu-Corps')),
          matching: find.text('zone Corps'),
        ),
      );
      await tester.pumpAndSettle();
      await toggleRegion(tester, ScaffoldPageRegion.bottomNavigationBar);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(find.text('Saved footer'), findsNothing);
      final appearance =
          AppearanceScope.controllerOf(context)!
              as PersistentAppearanceController;
      await appearance.saved;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final restarted = Registry();
      await pumpPage(tester, page, registry: restarted, store: store);
      final controller = restarted.scaffoldPageController('root');
      expect(
        controller.value.isEnabled(ScaffoldPageRegion.bottomNavigationBar),
        isFalse,
      );
      expect(controller.value.slotsOf(ScaffoldPageRegion.bottomNavigationBar), [
        'scaffold:bottomNavigationBar',
      ]);
      expect(find.text('Saved footer'), findsNothing);
      controller.value = controller.value.withRegionEnabled(
        ScaffoldPageRegion.bottomNavigationBar,
        true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved footer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in {
    ScaffoldPageRegion.appBar: 'AppBar',
    ScaffoldPageRegion.bottomNavigationBar: 'Barre basse',
    ScaffoldPageRegion.floatingActionButton: 'Bouton flottant',
    ScaffoldPageRegion.bottomSheet: 'Panneau bas',
  }.entries) {
    testWidgets('${entry.key.name} menu opens page configuration', (
      tester,
    ) async {
      await pumpPage(
        tester,
        SuperPage(
          label: 'Workspace',
          pageConfig: ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.body: ['scaffold:body'],
            },
            regions: {entry.key: true},
          ),
        ),
        registry: Registry(),
      );
      StyleEditScope.controllerOf(tester.element(find.byType(SuperPage)))!
              .value =
          true;
      await tester.pumpAndSettle();
      final region = find.byWidgetPredicate(
        (widget) => widget is EditorSlot && widget.label == entry.value,
      );
      await tester.tapAt(
        tester.getTopLeft(region) + const Offset(24, 24),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final menu = find.byKey(ValueKey('style-menu-${entry.value}'));
      final title = find.descendant(
        of: menu,
        matching: find.text('zone ${entry.value}'),
      );
      final subtitle = find.descendant(
        of: menu,
        matching: find.text('Workspace'),
      );
      expect(title, findsOneWidget);
      expect(subtitle, findsOneWidget);
      expect(
        find.descendant(
          of: menu,
          matching: find.byIcon(EditorSlot.zoneMenuIcon),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('style-menu-add-${entry.value}')),
        findsOneWidget,
      );
      expect(find.text('Configurer la page…'), findsNothing);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scaffold-page-settings')),
        findsOneWidget,
      );
      expect(find.byType(ContainerStyleEditor), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('body menu opens page configuration without a separate command', (
    tester,
  ) async {
    await tester.pumpWidget(const demo.TestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-mode')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(40, 120), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final body = find.byKey(const ValueKey('style-menu-Corps'));
    final command = find.byKey(
      const ValueKey('style-menu-entry-Configurer la page…'),
    );
    final background = find.byKey(const ValueKey('style-menu-Fond'));
    expect(body, findsOneWidget);
    expect(command, findsNothing);
    expect(background, findsOneWidget);
    expect(
      tester.getTopLeft(body).dy,
      lessThan(tester.getTopLeft(background).dy),
    );
    double labelLeft(Finder entry, String label) => tester
        .getTopLeft(find.descendant(of: entry, matching: find.text(label)))
        .dx;
    expect(labelLeft(background, 'Fond') - labelLeft(body, 'Page'), 12);
    await tester.tap(find.descendant(of: body, matching: find.text('Page')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('scaffold-page-settings')),
      findsOneWidget,
    );
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-mode')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(40, 120), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(command, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final grid in [false, true]) {
    testWidgets(
      'page breadcrumbs navigate into and out of ${grid ? 'grid' : 'layout'} children',
      (tester) async {
        final registry = Registry();
        await pumpPage(
          tester,
          SuperPage(
            appBar: AppBar(title: const Text('Header')),
            child: SuperLayout(
              name: 'Child',
              config: SuperLayoutConfig(
                positioning: grid
                    ? SuperLayoutPositioning.grid
                    : SuperLayoutPositioning.zones,
              ),
              slots: const [],
            ),
          ),
          registry: registry,
        );
        final context = tester.element(find.byType(SuperPage));
        StyleEditScope.controllerOf(context)!.value = true;
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value, ['Page']);
        expect(
          find.byKey(const ValueKey('scaffold-page-add-body')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('scaffold-page-add-appBar')),
          findsNothing,
        );
        await tester.tapAt(const Offset(650, 450));
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value.take(3), ['Page', 'Corps', 'Child']);
        expect(
          find.byKey(const ValueKey('scaffold-page-add-body')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('scaffold-page-select-body')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('style-edit-banner-path-0')),
        );
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value, ['Page']);
        expect(
          find.byKey(const ValueKey('scaffold-page-add-body')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('super-layout-add-center')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('scaffold-page-select-body')),
        );
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value, ['Page', 'Corps']);
        expect(
          find.byKey(const ValueKey('scaffold-page-add-appBar')),
          findsNothing,
        );
        await tester.tapAt(const Offset(650, 450));
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value.take(3), ['Page', 'Corps', 'Child']);
        await tester.tap(
          find.byKey(const ValueKey('style-edit-banner-path-1')),
        );
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value, ['Page', 'Corps']);
        expect(
          find.byKey(const ValueKey('scaffold-page-add-body')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final emptyBody in [false, true]) {
    testWidgets(
      'demo controls survive a persisted ${emptyBody ? 'empty' : 'replaced'} body',
      (tester) async {
        final store = AppearanceStore();
        await store.save(
          Appearance(
            components: {
              'root': ScaffoldPageConfig(
                placements: {
                  ScaffoldPageRegion.body: [if (!emptyBody) 'replacement'],
                },
                slotTypes: {if (!emptyBody) 'replacement': 'factory:Layout'},
              ),
            },
          ),
        );
        await tester.pumpWidget(const demo.TestApp());
        await tester.pumpAndSettle();
        final edit = find.byKey(const ValueKey('style-edit-mode'));
        final settings = find.byKey(const ValueKey('appearance-settings'));
        expect(edit.hitTestable(), findsOneWidget);
        expect(settings.hitTestable(), findsOneWidget);
        expect(
          find.descendant(of: find.byType(SuperPage), matching: edit),
          findsNothing,
        );
        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('style-edit-banner')), findsOneWidget);
        final context = tester.element(find.byType(SuperPage));
        final config = SuperApp.of(context).registry!
            .scaffoldPageController('root')
            .value;
        expect(
          config.slotsOf(ScaffoldPageRegion.body),
          emptyBody ? [] : ['replacement'],
        );
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('demo tooltips preserve semantics while editing', (tester) async {
    await tester.pumpWidget(const demo.TestApp());
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    try {
      await tester.tap(find.byKey(const ValueKey('style-edit-mode')));
      await tester.pumpAndSettle();
      for (final key in ['appearance-settings', 'style-edit-mode']) {
        await mouse.moveTo(tester.getCenter(find.byKey(ValueKey(key))));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
      }
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('style-edit-banner-transfer')),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        find.text('Importer / exporter le style et la disposition'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('appearance-settings'))),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Paramètres d’apparence'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
    }
  });

  testWidgets('empty Scaffold regions take no space outside edit mode', (
    tester,
  ) async {
    final registry = Registry();
    await pumpPage(
      tester,
      const SuperPage(child: SizedBox.expand(key: ValueKey('body-content'))),
      registry: registry,
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.appBar, isNull);
    expect(scaffold.bottomNavigationBar, isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('body-content'))),
      const Size(800, 600),
    );
    expect(find.byType(SuperLayout), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final region in [
    ScaffoldPageRegion.bottomNavigationBar,
    ScaffoldPageRegion.bottomSheet,
    ScaffoldPageRegion.floatingActionButton,
  ]) {
    testWidgets('fill layout in ${region.name} keeps the body visible', (
      tester,
    ) async {
      final registry = Registry()
        ..registerComponent(
          'nested-layout',
          RegisteredComponent(
            label: 'Nested layout',
            builder: (_) =>
                SuperLayout(config: const SuperLayoutConfig(), slots: const []),
          ),
        );
      final store = AppearanceStore();
      await store.save(
        Appearance(
          components: {
            'root': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: ['scaffold:body'],
                region: ['nested'],
              },
              slotTypes: {'nested': 'component:nested-layout'},
            ),
          },
        ),
      );
      await pumpPage(
        tester,
        const SuperPage(
          child: SizedBox.expand(
            key: ValueKey('visible-body'),
            child: Center(child: Text('Body remains visible')),
          ),
        ),
        registry: registry,
        store: store,
      );
      expect(
        tester.getSize(find.byType(SuperLayout)).height,
        region == ScaffoldPageRegion.floatingActionButton
            ? 56
            : kBottomNavigationBarHeight,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('visible-body'))).height,
        region == ScaffoldPageRegion.bottomNavigationBar
            ? 600 - kBottomNavigationBarHeight
            : 600,
      );
      expect(find.text('Body remains visible').hitTestable(), findsOneWidget);
      if (region == ScaffoldPageRegion.floatingActionButton) {
        expect(tester.getSize(find.byType(SuperLayout)).width, 56);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('provided page content uses native Scaffold regions', (
    tester,
  ) async {
    await pumpPage(
      tester,
      SuperPage(
        id: 'provided',
        appBar: AppBar(
          title: const Text('Page title'),
          actions: [
            IconButton(
              key: const ValueKey('page-action'),
              onPressed: () {},
              icon: const Icon(Icons.settings),
            ),
          ],
        ),
        bottomNavigationBar: const SizedBox(
          height: 32,
          child: Text('Bottom content'),
        ),
        endDrawer: const Drawer(child: Text('End navigation')),
        floatingActionButton: FloatingActionButton(
          onPressed: null,
          child: const Icon(Icons.add),
        ),
        bottomSheet: const SizedBox(height: 24, child: Text('Bottom sheet')),
        child: const SizedBox.expand(key: ValueKey('page-body')),
      ),
      registry: Registry(),
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.appBar, isA<PreferredSizeWidget>());
    expect(scaffold.bottomNavigationBar, isNotNull);
    expect(scaffold.endDrawer, isNotNull);
    expect(scaffold.floatingActionButton, isNotNull);
    expect(scaffold.bottomSheet, isNotNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('page-body'))).height,
      600 - kToolbarHeight - 32,
    );
    expect(find.text('Page title'), findsOneWidget);
    expect(find.text('Bottom content'), findsOneWidget);
    expect(find.text('Bottom sheet'), findsOneWidget);
    final action = tester.getRect(find.byKey(const ValueKey('page-action')));
    final title = tester.getRect(find.text('Page title'));
    expect(action.left, greaterThan(title.right));
    expect(action.right, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('provided drawer opens from the app bar menu', (tester) async {
    await pumpPage(
      tester,
      SuperPage(
        appBar: AppBar(title: const Text('Page title')),
        drawer: const Drawer(child: Text('Navigation drawer')),
        child: const SizedBox.expand(),
      ),
      registry: Registry(),
    );

    expect(find.text('Navigation drawer'), findsNothing);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('Navigation drawer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('occupied app bar region hides its overlay add action', (
    tester,
  ) async {
    final registry = Registry();
    await pumpPage(
      tester,
      SuperPage(appBar: AppBar(title: const Text('Page title'))),
      registry: registry,
    );
    final context = tester.element(find.byType(SuperPage));
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('style-edit-banner-drag')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('scaffold-page-add-appBar')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('scaffold-page-select-appBar')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scaffold region placements persist and reset', (tester) async {
    final registry = Registry();
    registry.registerComponent(
      'test-title',
      const RegisteredComponent(label: 'Test title', builder: _title),
    );
    final store = AppearanceStore();
    const page = SuperPage(id: 'persisted-page', child: Text('Original body'));
    await pumpPage(tester, page, registry: registry, store: store);
    final pageController = registry.scaffoldPageController('persisted-page');
    pageController.value = pageController.value
        .withSlotAdded(
          'header-title',
          ScaffoldPageRegion.appBar,
          type: 'component:test-title',
        )
        .withSlotAdded(
          'footer-title',
          ScaffoldPageRegion.bottomNavigationBar,
          type: 'component:test-title',
        );
    await tester.pumpAndSettle();
    expect(find.text('Registered title'), findsNWidgets(2));
    final appearance = AppearanceScope.controllerOf(
      tester.element(find.byType(SuperPage)),
    )!;
    await (appearance as PersistentAppearanceController).saved;
    final saved = await store.load();
    expect(
      saved.scaffoldPage('persisted-page').placements,
      pageController.value.placements,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final restarted = Registry();
    restarted.registerComponent(
      'test-title',
      const RegisteredComponent(label: 'Test title', builder: _title),
    );
    await pumpPage(tester, page, registry: restarted, store: store);
    expect(find.text('Registered title'), findsNWidgets(2));
    final restored = AppearanceScope.controllerOf(
      tester.element(find.byType(SuperPage)),
    )!;
    restored.value = restored.value.resetLayouts();
    await tester.pumpAndSettle();
    expect(find.text('Registered title'), findsNothing);
    expect(find.text('Original body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scaffold region slots retain semantics in edit mode', (
    tester,
  ) async {
    final registry = Registry();
    registry.registerComponent(
      'test-title',
      const RegisteredComponent(label: 'Test title', builder: _title),
    );
    await pumpPage(tester, const SuperPage(), registry: registry);
    final context = tester.element(find.byType(SuperPage));
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    try {
      final controller = registry.scaffoldPageController('root');
      controller.value = controller.value
          .withSlotAdded(
            'bar-title',
            ScaffoldPageRegion.appBar,
            type: 'component:test-title',
          )
          .withSlotAdded(
            'footer-title',
            ScaffoldPageRegion.bottomNavigationBar,
            type: 'component:test-title',
          );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Registered title'), findsNWidgets(2));
      controller.value = controller.value.withoutSlot('footer-title');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Registered title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  }, semanticsEnabled: false);
}

Widget _title(BuildContext context) => const Text('Registered title');
