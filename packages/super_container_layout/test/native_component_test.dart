import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

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

  Future<GoRouter> mount(
    Widget page,
    WidgetTester tester,
    Registry registry, {
    AppearanceStore? store,
  }) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => page)],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      SuperApp(router: router, registry: registry, appearanceStore: store),
    );
    await tester.pumpAndSettle();
    return router;
  }

  test(
    'generic placements are immutable, validated and losslessly serialized',
    () {
      final ids = ['first'];
      final config = NativeComponentConfig(
        placements: {'title': ids},
        slotTypes: {'first': 'component:heading'},
      ).withSlotSize('first', const Size(120, double.infinity));
      ids.clear();
      expect(config.slotsOf('title'), ['first']);
      expect(() => config.slotsOf('title').clear(), throwsUnsupportedError);
      expect(() => config.regions.clear(), throwsUnsupportedError);
      final hidden = config.withRegionEnabled('title', false);
      expect(hidden.slotsOf('title'), ['first']);
      expect(hidden.isEnabled('title'), isFalse);
      final restored = NativeComponentConfig.fromJson(hidden.toJson());
      expect(restored.toJson(), hidden.toJson());
      expect(
        restored.slotPreferredSizes['first'],
        const Size(120, double.infinity),
      );
      final replaced = restored.withSlotAdded('next', 'title', replace: true);
      expect(replaced.slotsOf('title'), ['next']);
      expect(replaced.slotTypes, isEmpty);
      expect(replaced.slotPreferredSizes, isEmpty);
      expect(replaced.withoutSlot('next').isEnabled('title'), isTrue);
      expect(
        () => NativeComponentConfig(
          placements: {
            'a': ['same'],
            'b': ['same'],
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => NativeComponentConfig.fromJson({
          'placements': {
            'title': [
              {'id': '', 'type': 'heading'},
            ],
          },
        }),
        throwsFormatException,
      );
      expect(
        () => ScaffoldPageConfig().withRegionEnabled(
          ScaffoldPageRegion.body,
          false,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'native configs persist, transfer, reset and retain the appearance subtype',
    () async {
      final appearance = DefaultAppearance(
        spacing: 19,
        nativeComponents: {
          'bar': NativeComponentConfig(
            placements: {
              'title': ['heading'],
            },
          ),
        },
      );
      const codec = DefaultAppearanceCodec();
      final store = AppearanceStore(codec: codec);
      await store.save(appearance);
      final restored = await store.load();
      expect(codec.encode(restored), codec.encode(appearance));
      final transferred = AppearanceTransfer.import(
        DefaultAppearance(),
        AppearanceTransfer.export(appearance, {
          TransferGroup.layouts,
        }, codec: codec),
        {TransferGroup.layouts},
        codec: codec,
      );
      expect(transferred.nativeComponent('bar').slotsOf('title'), ['heading']);
      final changed = appearance.withNativeComponent(
        'bar',
        NativeComponentConfig(),
      );
      expect(changed, isA<DefaultAppearance>());
      expect((changed as DefaultAppearance).spacing, 19);
      expect(changed.resetLayouts().nativeComponents, isEmpty);
    },
  );

  test('Scaffold compatibility controller shares generic storage and follows undo/reset', () {
    final original = ScaffoldPageConfig(
      placements: {
        ScaffoldPageRegion.body: ['body'],
      },
    );
    final appearance = ValueNotifier<Appearance>(
      Appearance(scaffoldPages: {'page': original}),
    );
    final registry = Registry()..bindAppearance(appearance);
    addTearDown(registry.unbindAppearance);
    addTearDown(appearance.dispose);
    final page = registry.scaffoldPageController('page');
    final native = registry.nativeComponentController('page');
    expect(page.value.slotsOf(ScaffoldPageRegion.body), ['body']);
    page.value = page.value.withRegionEnabled(ScaffoldPageRegion.drawer, true);
    expect(native.value.isEnabled('drawer'), isTrue);
    expect(appearance.value.nativeComponents.containsKey('page'), isTrue);
    expect(appearance.value.scaffoldPages.containsKey('page'), isFalse);
    expect(
      appearance.value
          .scaffoldPage('page')
          .isEnabled(ScaffoldPageRegion.drawer),
      isTrue,
    );
    native.value = native.value.withRegionEnabled('drawer', false);
    expect(page.value.isEnabled(ScaffoldPageRegion.drawer), isFalse);
    appearance.value = appearance.value.resetLayouts();
    expect(page.value.slotsOf(ScaffoldPageRegion.body), isEmpty);
  });

  testWidgets(
    'AppBar uses all five native properties without a registered layout',
    (tester) async {
      final registry = Registry();
      await mount(
        const SuperPage(
          appBar: SuperAppBar(
            leading: Text('Back content'),
            title: Text('Native title'),
            actions: [Text('One'), Text('Two')],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(32),
              child: Text('Tabs'),
            ),
            flexibleSpace: ColoredBox(color: Colors.blue),
          ),
          child: Text('Body content'),
        ),
        tester,
        registry,
      );
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.leading, isNotNull);
      expect(bar.title, isNotNull);
      expect(bar.actions, hasLength(2));
      expect(bar.bottom!.preferredSize.height, 32);
      expect(bar.flexibleSpace, isNotNull);
      expect(find.byType(RegisteredSuperLayout), findsNothing);
      expect(registry.superLayoutConfigById, isEmpty);
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Body content')).dy, 88);
      final config = registry.nativeComponentController('root-appBar');
      config.value = config.value.withRegionEnabled('bottom', false);
      await tester.pumpAndSettle();
      expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
      expect(tester.getTopLeft(find.text('Body content')).dy, 56);
      config.value = config.value.withRegionEnabled('bottom', true);
      await tester.pumpAndSettle();
      expect(find.text('Tabs'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Body content')).dy, 88);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved AppBar layout migrates title/actions and resets to source defaults',
    (tester) async {
      final store = AppearanceStore();
      await store.save(
        Appearance(
          layouts: {
            'bar': const SuperLayoutConfig(
              east: true,
              placements: {
                SuperLayoutZone.center: ['heading'],
                SuperLayoutZone.east: ['refresh'],
              },
              slotTypes: {'heading': 'title', 'refresh': 'action'},
            ),
          },
        ),
      );
      final registry = Registry();
      await mount(
        const SuperPage(
          appBar: SuperAppBar(
            id: 'bar',
            title: Text('Migrated heading'),
            action: Text('Migrated action'),
          ),
        ),
        tester,
        registry,
        store: store,
      );
      final controller = registry.nativeComponentController('bar');
      expect(controller.value.slotsOf('title'), ['heading']);
      expect(controller.value.slotsOf('actions'), ['refresh']);
      expect(find.text('Migrated heading'), findsOneWidget);
      expect(find.text('Migrated action'), findsOneWidget);
      controller.value = controller.value.withRegionEnabled('actions', false);
      await tester.pumpAndSettle();
      expect(find.text('Migrated action'), findsNothing);
      final appearance = AppearanceScope.controllerOf(
        tester.element(find.byType(SuperAppBar)),
      )!;
      appearance.value = appearance.value.resetLayouts();
      await tester.pumpAndSettle();
      expect(controller.value.slotsOf('title'), ['title']);
      expect(controller.value.slotsOf('actions'), ['action']);
      expect(find.text('Migrated action'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AppBar context config, hierarchy and overlays use the shared editor',
    (tester) async {
      final registry = Registry();
      await mount(
        const SuperPage(appBar: SuperAppBar(title: Text('Heading'))),
        tester,
        registry,
      );
      final context = tester.element(find.byType(SuperAppBar));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getTopLeft(find.text('Heading')) + const Offset(3, 3),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Page', 'AppBar', 'AppBar', 'Titre']);
      expect(
        find.byKey(const ValueKey('scaffold-page-add-appBar')),
        findsNothing,
      );
      final row = find.byKey(const ValueKey('style-menu-Titre'));
      await tester.tap(find.descendant(of: row, matching: find.text('Titre')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-app-bar-settings')),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNWidgets(5));
      final toggle = find.byKey(const ValueKey('super-app-bar-switch-actions'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-app-bar-add-actions')),
        findsOneWidget,
      );
      LayoutSelection.select(['Page']);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-app-bar-add-actions')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-add-appBar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'single regions replace atomically while native additions undo and redo',
    (tester) async {
      final registry = Registry()
        ..registerComponent(
          'item',
          const RegisteredComponent(label: 'Item', builder: _item),
        );
      await mount(
        const SuperPage(
          appBar: SuperAppBar(
            title: Text('Heading'),
            leading: Text('Original leading'),
          ),
        ),
        tester,
        registry,
      );
      final context = tester.element(find.byType(SuperAppBar));
      final history = EditorHistoryScope.controllerOf(context)!;
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getTopLeft(find.text('Original leading')) + const Offset(2, 2),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('super-app-bar-add-leading')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('super-app-bar-add-slot-component:item')),
      );
      await tester.pumpAndSettle();
      final controller = registry.nativeComponentController('root-appBar');
      final id = controller.value.slotsOf('leading').single;
      expect(id, isNot('component:item'));
      expect(controller.value.slotTypeOf(id), 'component:item');
      expect(find.text('Original leading'), findsNothing);
      history.undo();
      await tester.pumpAndSettle();
      expect(find.text('Original leading'), findsOneWidget);
      history.redo();
      await tester.pumpAndSettle();
      expect(controller.value.slotsOf('leading'), [id]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('migrated slot aliases remain removable by instance ID', (
    tester,
  ) async {
    final registry = Registry();
    await mount(
      SuperPage(
        appBar: SuperAppBar(
          title: const Text('Alias heading'),
          nativeConfig: NativeComponentConfig(
            placements: {
              'title': ['alias'],
            },
            slotTypes: {'alias': 'title'},
          ),
        ),
      ),
      tester,
      registry,
    );
    StyleEditScope.controllerOf(tester.element(find.byType(SuperAppBar)))!
            .value =
        true;
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('style-edit-banner-drag')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(find.text('Alias heading')) + const Offset(3, 3),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('style-menu-remove-Taille préférée : title')),
    );
    await tester.pumpAndSettle();
    expect(
      registry.nativeComponentController('root-appBar').value.slotsOf('title'),
      isEmpty,
    );
    expect(find.text('Alias heading'), findsNothing);
    expect(
      find.byKey(const ValueKey('super-app-bar-add-title')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'explicit native switches suppress automatically implied Scaffold controls',
    (tester) async {
      final registry = Registry();
      await mount(
        const SuperPage(
          appBar: SuperAppBar(title: Text('Heading')),
          drawer: Drawer(child: Text('Left')),
          endDrawer: Drawer(child: Text('Right')),
        ),
        tester,
        registry,
      );
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).automaticallyImplyLeading,
        isTrue,
      );
      expect(find.byIcon(Icons.menu), findsNWidgets(2));
      final controller = registry.nativeComponentController('root-appBar');
      controller.value = controller.value
          .withRegionEnabled('leading', false)
          .withRegionEnabled('actions', false);
      await tester.pumpAndSettle();
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.automaticallyImplyLeading, isFalse);
      expect(bar.actions, isEmpty);
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing another native region preserves child state and percentage sizes',
    (tester) async {
      final registry = Registry();
      await mount(
        SuperPage(
          appBar: SuperAppBar(
            title: const TextField(key: ValueKey('stateful-title')),
            action: const SizedBox(
              key: ValueKey('sized-action'),
              width: 20,
              height: 20,
            ),
            nativeConfig: NativeComponentConfig(
              placements: {
                'title': ['title'],
                'actions': ['action'],
              },
              slotSizeConstraints: {
                'action': const SlotSizeConstraints(
                  preferredWidth: SlotDimension(20, SlotSizeUnit.percent),
                  percentBasis: SlotPercentBasis.layout,
                ),
              },
            ),
          ),
        ),
        tester,
        registry,
      );
      await tester.enterText(
        find.byKey(const ValueKey('stateful-title')),
        'Preserved',
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('slot-item-action'))).width,
        closeTo(160, .1),
      );
      final controller = registry.nativeComponentController('root-appBar');
      controller.value = controller.value.withRegionEnabled(
        'flexibleSpace',
        true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Preserved'), findsOneWidget);
      controller.value = controller.value.withRegionEnabled(
        'flexibleSpace',
        false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Preserved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'registered native AppBar instances propagate edited preferred heights',
    (tester) async {
      final registry = Registry()..bootstrap();
      await mount(
        SuperPage(
          pageConfig: ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.appBar: ['created-bar'],
              ScaffoldPageRegion.body: ['scaffold:body'],
            },
            slotTypes: {'created-bar': 'factory:SuperAppBar'},
          ),
          child: const Text('Remaining body'),
        ),
        tester,
        registry,
      );
      expect(tester.getTopLeft(find.text('Remaining body')).dy, 56);
      final controller = registry.nativeComponentController('created-bar');
      controller.value = controller.value
          .withSlotAdded('tab-item', 'bottom', type: 'factory:NewContainer')
          .withSlotSize('tab-item', const Size(double.infinity, 40));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Remaining body')).dy, 96);
      expect(tester.getSize(find.byType(AppBar)).height, 96);
      controller.value = controller.value.withRegionEnabled('bottom', false);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Remaining body')).dy, 56);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native size editor validates dimensions and persists the result',
    (tester) async {
      final registry = Registry();
      await mount(
        const SuperPage(appBar: SuperAppBar(title: Text('Sized heading'))),
        tester,
        registry,
      );
      StyleEditScope.controllerOf(tester.element(find.byType(SuperAppBar)))!
              .value =
          true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getTopLeft(find.text('Sized heading')) + const Offset(3, 3),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('style-menu-size-Taille préférée : title')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '-1');
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(find.text('Saisissez une dimension positive.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '120');
      await tester.enterText(find.byType(TextFormField).last, '40');
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(
        registry
            .nativeComponentController('root-appBar')
            .value
            .slotPreferredSizes['title'],
        const Size(120, 40),
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final fromRegistry in [false, true]) {
    testWidgets(
      'empty AppBar exposes configuration and breadcrumbs (${fromRegistry ? 'catalog' : 'provided'})',
      (tester) async {
        final registry = Registry()..bootstrap();
        await mount(
          fromRegistry
              ? SuperPage(
                  pageConfig: ScaffoldPageConfig(
                    placements: {
                      ScaffoldPageRegion.appBar: ['empty-bar'],
                      ScaffoldPageRegion.body: ['scaffold:body'],
                    },
                    slotTypes: {'empty-bar': 'factory:SuperAppBar'},
                  ),
                )
              : const SuperPage(appBar: SuperAppBar()),
          tester,
          registry,
        );
        StyleEditScope.controllerOf(tester.element(find.byType(SuperPage)))!
                .value =
            true;
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('style-edit-banner-drag')),
          const Offset(0, 200),
        );
        await tester.pumpAndSettle();
        final bar = find.byType(AppBar);
        await tester.tapAt(tester.getTopLeft(bar) + const Offset(8, 8));
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value, ['Page', 'AppBar', 'AppBar']);
        expect(
          find.byKey(const ValueKey('scaffold-page-add-appBar')),
          findsNothing,
        );
        await tester.tapAt(
          tester.getTopLeft(bar) + const Offset(8, 8),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        final configure = find.byKey(
          const ValueKey('style-menu-Configurer la barre'),
        );
        expect(configure, findsOneWidget);
        expect(find.byKey(const ValueKey('style-menu-AppBar')), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: configure,
            matching: find.text('Configurer la barre'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('super-app-bar-settings')),
          findsOneWidget,
        );
        final toggle = find.byKey(const ValueKey('super-app-bar-switch-title'));
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fermer'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('super-app-bar-add-title')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('super-app-bar-add-title')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey('super-app-bar-add-slot-factory:NewContainer'),
          ),
        );
        await tester.pumpAndSettle();
        final controller = registry.nativeComponentController(
          fromRegistry ? 'empty-bar' : 'root-appBar',
        );
        expect(controller.value.slotsOf('title'), hasLength(1));
        expect(
          controller.value.slotTypeOf(controller.value.slotsOf('title').single),
          'factory:NewContainer',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'free bottom bar uses native bounded regions and preserves callbacks',
    (tester) async {
      final registry = Registry();
      var taps = 0;
      await mount(
        SuperPage(
          bottomNavigationBar: SuperBottomNavigationBar(
            left: TextButton(
              onPressed: () => taps++,
              child: const Text('Home'),
            ),
            center: const Text('Status'),
            right: const Text('Tools'),
          ),
          child: const SizedBox.expand(key: ValueKey('bottom-bar-body')),
        ),
        tester,
        registry,
      );
      expect(find.byType(BottomAppBar), findsOneWidget);
      expect(find.byType(RegisteredSuperLayout), findsNothing);
      expect(tester.getSize(find.byType(BottomAppBar)).height, 56);
      expect(
        tester.getSize(find.byKey(const ValueKey('bottom-bar-body'))).height,
        544,
      );
      await tester.tap(find.text('Home'));
      expect(taps, 1);
      final controller = registry.nativeComponentController(
        'root-bottomNavigationBar',
      );
      controller.value = controller.value.withRegionEnabled('center', false);
      await tester.pumpAndSettle();
      expect(find.text('Status'), findsNothing);
      expect(controller.value.slotsOf('center'), ['center']);
      final restored = AppearanceStore.decode(
        AppearanceStore.encode(
          AppearanceScope.of(
            tester.element(find.byType(SuperBottomNavigationBar)),
          ),
        ),
      );
      expect(
        restored
            .nativeComponent('root-bottomNavigationBar')
            .isEnabled('center'),
        isFalse,
      );
      controller.value = controller.value.withRegionEnabled('center', true);
      await tester.pumpAndSettle();
      expect(find.text('Status'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog bottom bar exposes settings, adds multiple slots and undoes removal',
    (tester) async {
      final registry = Registry()..bootstrap();
      await mount(
        SuperPage(
          pageConfig: ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.body: ['scaffold:body'],
              ScaffoldPageRegion.bottomNavigationBar: ['free-bar'],
            },
            slotTypes: {'free-bar': 'factory:SuperBottomNavigationBar'},
          ),
        ),
        tester,
        registry,
      );
      final pageContext = tester.element(find.byType(SuperPage));
      final history = EditorHistoryScope.controllerOf(pageContext)!;
      StyleEditScope.controllerOf(pageContext)!.value = true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      final bar = find.byType(BottomAppBar);
      await tester.tapAt(
        tester.getTopLeft(bar) + const Offset(4, 4),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.take(3), [
        'Page',
        'Barre basse',
        'Barre basse',
      ]);
      expect(
        find.byKey(const ValueKey('scaffold-page-add-bottomNavigationBar')),
        findsNothing,
      );
      final settings = find.byKey(
        const ValueKey('style-menu-Configurer la barre basse'),
      );
      await tester.tap(
        find.descendant(
          of: settings,
          matching: find.text('Configurer la barre basse'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      final toggle = find.byKey(
        const ValueKey('super-bottom-navigation-bar-switch-right'),
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-bottom-navigation-bar-add-right')),
        findsNothing,
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(
          find.byKey(const ValueKey('super-bottom-navigation-bar-add-left')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey(
              'super-bottom-navigation-bar-add-slot-factory:NewContainer',
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      final controller = registry.nativeComponentController('free-bar');
      final ids = controller.value.slotsOf('left');
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));
      expect(tester.getSize(find.byType(BottomAppBar)).height, 56);
      final slot = find.byKey(ValueKey('slot-item-${ids.last}'));
      await tester.tapAt(
        tester.getTopLeft(slot) + const Offset(2, 2),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('style-menu-remove-Taille préférée : NewContainer'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.value.slotsOf('left'), [ids.first]);
      history.undo();
      await tester.pumpAndSettle();
      expect(controller.value.slotsOf('left'), ids);
      history.redo();
      await tester.pumpAndSettle();
      expect(controller.value.slotsOf('left'), [ids.first]);
      LayoutSelection.select(['Page']);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-bottom-navigation-bar-add-left')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-add-bottomNavigationBar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('catalog bottom bar includes the native bottom safe area', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    await mount(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(bottom: 24),
        ),
        child: SuperPage(
          pageConfig: ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.body: ['scaffold:body'],
              ScaffoldPageRegion.bottomNavigationBar: ['safe-bar'],
            },
            slotTypes: {'safe-bar': 'factory:SuperBottomNavigationBar'},
          ),
          child: const SizedBox.expand(key: ValueKey('safe-body')),
        ),
      ),
      tester,
      registry,
    );
    expect(tester.getSize(find.byType(BottomAppBar)).height, 80);
    expect(tester.getSize(find.byKey(const ValueKey('safe-body'))).height, 520);
    expect(tester.takeException(), isNull);
  });
}

Widget _item(BuildContext context) => const SizedBox(width: 32, height: 32);
