import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  Future<void> pumpPage(
    WidgetTester tester,
    SuperPage page, {
    Registry? registry,
    AppearanceStore? store,
    JsonRepositoryStore? repositoryStore,
  }) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => page)],
    );
    addTearDown(router.dispose);
    Widget app = SuperApp(
      router: router,
      registry: registry,
      appearanceStore: store,
    );
    if (repositoryStore != null) {
      app = JsonRepositoryScope(store: repositoryStore, child: app);
    }
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  test('ScaffoldPageConfig and property descriptors serialize all body modes and scroll options', () {
    for (final descriptors in [
      ScaffoldPageConfig.propertyDescriptors,
      SuperAppBar.sliverPropertyDescriptors,
    ]) {
      final jsonList = NativePropertyDescriptor.listToJson(descriptors);
      final roundTripped = NativePropertyDescriptor.listFromJson(jsonList);
      expect(roundTripped, descriptors);
    }

    final defaultConfig = ScaffoldPageConfig();
    expect(defaultConfig.bodyMode, ScaffoldBodyMode.standard);
    expect(defaultConfig.extendBody, isFalse);
    expect(defaultConfig.extendBodyBehindAppBar, isFalse);
    expect(defaultConfig.scrollDirection, Axis.vertical);
    expect(defaultConfig.reverse, isFalse);
    expect(defaultConfig.primary, isNull);
    expect(defaultConfig.scrollPadding, isNull);
    expect(defaultConfig.clipBehavior, isNull);
    expect(defaultConfig.toJson().containsKey('bodyMode'), isFalse);

    final configured = ScaffoldPageConfig(
      placements: {
        ScaffoldPageRegion.appBar: const ['scaffold:appBar'],
        ScaffoldPageRegion.body: const ['scaffold:body'],
      },
      bodyMode: ScaffoldBodyMode.customScrollView,
      extendBody: true,
      extendBodyBehindAppBar: true,
      scrollDirection: Axis.horizontal,
      reverse: true,
      primary: false,
      scrollPadding: 16,
      clipBehavior: Clip.antiAlias,
    );
    expect(configured.bodyMode, ScaffoldBodyMode.customScrollView);
    expect(configured.extendBody, isTrue);
    expect(configured.extendBodyBehindAppBar, isTrue);
    expect(configured.scrollDirection, Axis.horizontal);
    expect(configured.reverse, isTrue);
    expect(configured.primary, isFalse);
    expect(configured.scrollPadding, 16.0);
    expect(configured.clipBehavior, Clip.antiAlias);

    final restored = ScaffoldPageConfig.fromJson(configured.toJson());
    expect(restored.bodyMode, ScaffoldBodyMode.customScrollView);
    expect(restored.extendBody, isTrue);
    expect(restored.extendBodyBehindAppBar, isTrue);
    expect(restored.scrollDirection, Axis.horizontal);
    expect(restored.reverse, isTrue);
    expect(restored.primary, isFalse);
    expect(restored.scrollPadding, 16.0);
    expect(restored.clipBehavior, Clip.antiAlias);

    final singleScroll = restored
        .withBodyMode(ScaffoldBodyMode.singleChildScrollView)
        .withExtendBody(false)
        .withExtendBodyBehindAppBar(false)
        .withScrollDirection(Axis.vertical)
        .withReverse(false)
        .withScrollPadding(8);
    expect(singleScroll.bodyMode, ScaffoldBodyMode.singleChildScrollView);
    expect(singleScroll.extendBody, isFalse);
    expect(singleScroll.extendBodyBehindAppBar, isFalse);
    expect(singleScroll.scrollDirection, Axis.vertical);
    expect(singleScroll.reverse, isFalse);
    expect(singleScroll.scrollPadding, 8.0);

    final resetToStandard = singleScroll.withBodyMode(
      ScaffoldBodyMode.standard,
    );
    expect(resetToStandard.bodyMode, ScaffoldBodyMode.standard);
    expect(resetToStandard.toJson().containsKey('bodyMode'), isFalse);
  });

  testWidgets(
    'standard mode keeps fixed Scaffold body without scroll view wrappers',
    (tester) async {
      await pumpPage(
        tester,
        const SuperPage(
          extendBody: true,
          extendBodyBehindAppBar: true,
          appBar: SuperAppBar(title: Text('Fixed Header')),
          child: Text('Fixed Body'),
        ),
        registry: Registry(),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.extendBody, isTrue);
      expect(scaffold.extendBodyBehindAppBar, isTrue);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(SliverAppBar), findsNothing);
      expect(
        find.byKey(const ValueKey('scaffold-page-single-child-scroll-view')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-custom-scroll-view')),
        findsNothing,
      );
      expect(find.text('Fixed Header'), findsOneWidget);
      expect(find.text('Fixed Body'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'singleChildScrollView mode wraps the body zone, scrolls tall content, and supports SuperLayout',
    (tester) async {
      final registry = Registry()..bootstrap();
      await pumpPage(
        tester,
        SuperPage(
          bodyMode: ScaffoldBodyMode.singleChildScrollView,
          scrollPadding: 12,
          clipBehavior: Clip.antiAlias,
          appBar: const SuperAppBar(title: Text('Fixed Top AppBar')),
          pageConfig: ScaffoldPageConfig(
            bodyMode: ScaffoldBodyMode.singleChildScrollView,
            scrollPadding: 12,
            clipBehavior: Clip.antiAlias,
            placements: {
              ScaffoldPageRegion.appBar: const ['scaffold:appBar'],
              ScaffoldPageRegion.body: const ['tall-1', 'tall-2', 'layout-3'],
            },
          ),
          slots: [
            BuilderSlot(
              id: 'tall-1',
              label: 'Section 1',
              preferredSize: const Size(double.infinity, 450),
              builder: (_) => const ColoredBox(
                color: Colors.teal,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text('Top Section 1'),
                ),
              ),
            ),
            BuilderSlot(
              id: 'tall-2',
              label: 'Section 2',
              preferredSize: const Size(double.infinity, 450),
              builder: (_) => const ColoredBox(
                color: Colors.amber,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text('Bottom Section 2'),
                ),
              ),
            ),
            BuilderSlot(
              id: 'layout-3',
              label: 'Nested Layout',
              builder: (_) => SuperLayout(
                name: 'ScrollableLayout',
                slots: [
                  BuilderSlot(
                    id: 'nested-text',
                    label: 'Nested Text',
                    sizing: SlotSizing.intrinsic,
                    builder: (_) => const SizedBox(
                      height: 120,
                      child: Text('Inside SuperLayout'),
                    ),
                  ),
                ],
                config: const SuperLayoutConfig(
                  placements: {
                    SuperLayoutZone.center: ['nested-text'],
                  },
                ),
              ),
            ),
          ],
        ),
        registry: registry,
      );

      expect(find.byType(AppBar), findsOneWidget);
      final scrollFinder = find.byKey(
        const ValueKey('scaffold-page-single-child-scroll-view'),
      );
      expect(scrollFinder, findsOneWidget);
      final scrollView = tester.widget<SingleChildScrollView>(scrollFinder);
      expect(scrollView.padding, const EdgeInsets.all(12));
      expect(scrollView.clipBehavior, Clip.antiAlias);

      final initialTop1 = tester.getTopLeft(find.text('Top Section 1')).dy;
      await tester.drag(scrollFinder, const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Top Section 1')).dy,
        lessThan(initialTop1 - 300),
      );
      expect(find.text('Fixed Top AppBar'), findsOneWidget);
      expect(find.text('Inside SuperLayout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'customScrollView mode renders SuperAppBar as SliverAppBar, SuperListView as SliverList, and wraps other slots in SliverToBoxAdapter',
    (tester) async {
      final registry = Registry()..bootstrap();
      await pumpPage(
        tester,
        SuperPage(
          bodyMode: ScaffoldBodyMode.customScrollView,
          appBar: const SuperAppBar(
            id: 'sliver-header',
            title: Text('Sliver Header Title'),
            pinned: true,
            floating: true,
            stretch: true,
            stretchTriggerOffset: 150,
            forceElevated: true,
            useDefaultSemanticsOrder: false,
            actionsPadding: 12,
            expandedHeight: 140,
            flexibleSpace: ColoredBox(color: Colors.indigo),
          ),
          pageConfig: ScaffoldPageConfig(
            bodyMode: ScaffoldBodyMode.customScrollView,
            placements: {
              ScaffoldPageRegion.appBar: const ['scaffold:appBar'],
              ScaffoldPageRegion.body: const [
                'intro-box',
                'sliver-list',
                'footer-box',
              ],
            },
          ),
          slots: [
            BuilderSlot(
              id: 'intro-box',
              label: 'Intro Banner',
              preferredSize: const Size(double.infinity, 120),
              builder: (_) => const ColoredBox(
                key: ValueKey('intro-banner-widget'),
                color: Colors.blueGrey,
                child: Text('Intro Box Content'),
              ),
            ),
            BuilderSlot(
              id: 'sliver-list',
              label: 'Main List',
              builder: (_) => SuperListView(
                id: 'sliver-list',
                config: const SuperListViewConfig(itemExtent: 72),
                template: const SuperLayoutConfig(
                  placements: {
                    SuperLayoutZone.center: ['row-label'],
                  },
                ),
                slots: [
                  BuilderSlot(
                    id: 'row-label',
                    label: 'Row Label',
                    builder: (_) => const Text('Template Row Item'),
                  ),
                ],
              ),
            ),
            BuilderSlot(
              id: 'footer-box',
              label: 'Footer Box',
              preferredSize: const Size(double.infinity, 500),
              builder: (_) => const ColoredBox(
                key: ValueKey('footer-box-widget'),
                color: Colors.deepOrange,
                child: Text('Footer Box Content'),
              ),
            ),
          ],
        ),
        registry: registry,
      );

      // Scaffold.appBar is null because the appBar is inside the CustomScrollView
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.appBar, isNull);

      final customScrollFinder = find.byKey(
        const ValueKey('scaffold-page-custom-scroll-view'),
      );
      expect(customScrollFinder, findsOneWidget);

      // SuperAppBar rendered a SliverAppBar with its configured sliver properties
      final sliverAppBarFinder = find.byType(SliverAppBar);
      expect(sliverAppBarFinder, findsOneWidget);
      final sliverAppBar = tester.widget<SliverAppBar>(sliverAppBarFinder);
      expect(sliverAppBar.pinned, isTrue);
      expect(sliverAppBar.floating, isTrue);
      expect(sliverAppBar.stretch, isTrue);
      expect(sliverAppBar.stretchTriggerOffset, 150.0);
      expect(sliverAppBar.forceElevated, isTrue);
      expect(sliverAppBar.useDefaultSemanticsOrder, isFalse);
      expect(
        sliverAppBar.actionsPadding,
        const EdgeInsets.symmetric(horizontal: 12),
      );
      expect(sliverAppBar.expandedHeight, 140.0);
      expect(find.text('Sliver Header Title'), findsOneWidget);

      // SuperListView rendered a SliverFixedExtentList (and no nested ListView)
      expect(
        find.descendant(
          of: find.byType(SuperListView),
          matching: find.byType(ListView),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('super-list-message-sliver-list')),
        findsOneWidget,
      );

      // Non-sliver components ('intro-box', 'footer-box') are wrapped in SliverToBoxAdapter
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('intro-banner-widget')),
          matching: find.byType(SliverToBoxAdapter),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('footer-box-widget')),
          matching: find.byType(SliverToBoxAdapter),
        ),
        findsOneWidget,
      );

      // Scrolling the CustomScrollView collapses the SliverAppBar and scrolls the slivers together
      final introBefore = tester.getTopLeft(find.text('Intro Box Content')).dy;
      await tester.drag(customScrollFinder, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Intro Box Content')).dy,
        lessThan(introBefore - 100),
      );
      // Because pinned: true, the SliverAppBar title remains visible at the top
      expect(find.text('Sliver Header Title'), findsOneWidget);

      // Enable edit mode: template row in SuperListView is rendered as a SliverFixedExtentList
      final context = tester.element(find.byType(SuperPage));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(SliverFixedExtentList), findsOneWidget);
      expect(find.text('Template Row Item'), findsOneWidget);

      // SliverAppBar settings dialog exposes SliverAppBar properties when in sliver mode
      final appBarEditor = tester.state<NativeComponentEditorState>(
        find.descendant(
          of: find.byType(SuperAppBar),
          matching: find.byType(NativeComponentEditor),
        ),
      );
      unawaited(appBarEditor.configure());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-app-bar-prop-pinned')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-app-bar-prop-floating')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-app-bar-prop-stretchTriggerOffset')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-app-bar-prop-forceElevated')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('super-app-bar-prop-useDefaultSemanticsOrder'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-app-bar-prop-actionsPadding')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-app-bar-prop-expandedHeight')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-app-bar-prop-toolbarOpacity')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('super-app-bar-prop-bottomOpacity')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('super-app-bar-settings-cancel')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page settings dialog switches between standard, singleChildScrollView, and customScrollView with undo/redo',
    (tester) async {
      final registry = Registry()..bootstrap();
      await pumpPage(
        tester,
        const SuperPage(
          appBar: SuperAppBar(title: Text('Dynamic Mode Header')),
          child: SizedBox(height: 200, child: Text('Dynamic Mode Body')),
        ),
        registry: registry,
      );

      final context = tester.element(find.byType(SuperPage));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      final history = EditorHistoryScope.controllerOf(context)!;
      final controller = registry.scaffoldPageController('root');

      final pageEditor = tester.state<NativeComponentEditorState>(
        find
            .descendant(
              of: find.byType(SuperPage),
              matching: find.byType(NativeComponentEditor),
            )
            .first,
      );

      // Open page settings dialog in standard mode
      unawaited(pageEditor.configure());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scaffold-page-prop-bodyMode')),
        findsOneWidget,
      );
      // Scroll options are hidden while in standard mode
      expect(
        find.byKey(const ValueKey('scaffold-page-prop-scrollDirection')),
        findsNothing,
      );

      // Switch to singleChildScrollView
      final bodyModeDropdown = find.byKey(
        const ValueKey('scaffold-page-prop-bodyMode'),
      );
      await tester.ensureVisible(bodyModeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(bodyModeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Défilement simple (SingleChildScrollView)').last,
      );
      await tester.pumpAndSettle();

      // Scroll options dynamically appear in the dialog
      expect(
        find.byKey(const ValueKey('scaffold-page-prop-scrollDirection')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-prop-reverse')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-prop-scrollPadding')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('scaffold-page-settings-apply')),
      );
      await tester.pumpAndSettle();

      expect(controller.value.bodyMode, ScaffoldBodyMode.singleChildScrollView);
      expect(
        find.byKey(const ValueKey('scaffold-page-single-child-scroll-view')),
        findsOneWidget,
      );

      // Switch to customScrollView
      unawaited(pageEditor.configure());
      await tester.pumpAndSettle();
      await tester.ensureVisible(bodyModeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(bodyModeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Défilement Slivers (CustomScrollView)').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('scaffold-page-settings-apply')),
      );
      await tester.pumpAndSettle();

      expect(controller.value.bodyMode, ScaffoldBodyMode.customScrollView);
      expect(
        find.byKey(const ValueKey('scaffold-page-custom-scroll-view')),
        findsOneWidget,
      );
      expect(find.byType(SliverAppBar), findsOneWidget);

      // Undo returns to singleChildScrollView, then to standard
      history.undo();
      await tester.pumpAndSettle();
      expect(controller.value.bodyMode, ScaffoldBodyMode.singleChildScrollView);
      expect(
        find.byKey(const ValueKey('scaffold-page-single-child-scroll-view')),
        findsOneWidget,
      );

      history.undo();
      await tester.pumpAndSettle();
      expect(controller.value.bodyMode, ScaffoldBodyMode.standard);
      expect(
        find.byKey(const ValueKey('scaffold-page-single-child-scroll-view')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('scaffold-page-custom-scroll-view')),
        findsNothing,
      );

      history.redo();
      await tester.pumpAndSettle();
      expect(controller.value.bodyMode, ScaffoldBodyMode.singleChildScrollView);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog ApplicationBar and ListView instances render as native slivers in customScrollView',
    (tester) async {
      final registry = Registry()..bootstrap();
      await pumpPage(
        tester,
        SuperPage(
          pageConfig: ScaffoldPageConfig(
            bodyMode: ScaffoldBodyMode.customScrollView,
            placements: {
              ScaffoldPageRegion.appBar: const ['cat-appbar'],
              ScaffoldPageRegion.body: const [
                'cat-card',
                'cat-list-fixed',
                'cat-list-varied',
              ],
            },
            slotTypes: const {
              'cat-appbar': 'factory:ApplicationBar',
              'cat-card': 'factory:Card',
              'cat-list-fixed': 'factory:ListView',
              'cat-list-varied': 'factory:ListView',
            },
          ),
        ),
        registry: registry,
      );

      final pageController = registry.scaffoldPageController('root');
      pageController.value = ScaffoldPageConfig.fromNative(
        pageController.value.native.withSlotSize(
          'cat-card',
          const Size(double.infinity, 80),
        ),
      );
      final variedController = registry.listController('cat-list-varied');
      variedController.value = variedController.value.copyWith(
        itemSize: const SlotSizeConstraints(
          preferredHeight: SlotDimension(64, SlotSizeUnit.pixels),
        ),
      );

      final context = tester.element(find.byType(SuperPage));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();

      // Catalog ApplicationBar renders as SliverAppBar
      expect(find.byType(SliverAppBar), findsOneWidget);
      // Catalog ListView without itemSize renders as SliverFixedExtentList
      expect(find.byType(SliverFixedExtentList), findsOneWidget);
      // Catalog ListView with itemSize renders as SliverList
      expect(find.byType(SliverList), findsOneWidget);
      // Catalog Card is wrapped in SliverToBoxAdapter
      expect(
        find.ancestor(
          of: find.byType(EditableSurface),
          matching: find.byType(SliverToBoxAdapter),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'non-SuperAppBar PreferredSizeWidget in customScrollView falls back to SliverToBoxAdapter',
    (tester) async {
      await pumpPage(
        tester,
        SuperPage(
          bodyMode: ScaffoldBodyMode.customScrollView,
          appBar: AppBar(title: const Text('Classic AppBar Header')),
          child: const SizedBox(height: 150, child: Text('Body Content')),
        ),
        registry: Registry(),
      );

      expect(
        find.byKey(const ValueKey('scaffold-page-custom-scroll-view')),
        findsOneWidget,
      );
      expect(find.text('Classic AppBar Header'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Classic AppBar Header'),
          matching: find.byType(SliverToBoxAdapter),
        ),
        findsOneWidget,
      );
      expect(find.text('Body Content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SuperLayout as SuperPage body child sizes to its center children height and scrolls without explicit pixel height on MainLayout',
    (tester) async {
      for (final mode in [
        ScaffoldBodyMode.singleChildScrollView,
        ScaffoldBodyMode.customScrollView,
      ]) {
        final registry = Registry()..bootstrap();
        await pumpPage(
          tester,
          SuperPage(
            id: 'page-${mode.name}',
            bodyMode: mode,
            appBar: const SuperAppBar(title: Text('Header')),
            child: SuperLayout(
              key: ValueKey('main-layout-${mode.name}'),
              label: 'Main Layout',
              slots: [
                BuilderSlot(
                  id: 'child-1',
                  label: 'Child 1',
                  preferredSize: const Size(double.infinity, 420),
                  builder: (_) => const ColoredBox(
                    color: Colors.blue,
                    child: Text('MainLayout Child 1'),
                  ),
                ),
                BuilderSlot(
                  id: 'child-2',
                  label: 'Child 2',
                  preferredSize: const Size(double.infinity, 420),
                  builder: (_) => const ColoredBox(
                    color: Colors.green,
                    child: Text('MainLayout Child 2'),
                  ),
                ),
                BuilderSlot(
                  id: 'child-3',
                  label: 'Child 3',
                  sizing: SlotSizing.intrinsic,
                  builder: (_) => const SizedBox(
                    height: 360,
                    child: Text('MainLayout Child 3'),
                  ),
                ),
              ],
              config: const SuperLayoutConfig(
                placements: {
                  SuperLayoutZone.center: ['child-1', 'child-2', 'child-3'],
                },
              ),
            ),
          ),
          registry: registry,
        );

        final mainLayoutFinder = find.byKey(
          ValueKey('main-layout-${mode.name}'),
        );
        final mainLayoutSize = tester.getSize(mainLayoutFinder);
        // 420 + 420 + 360 = 1200 px (> 600 px test viewport height)
        expect(mainLayoutSize.height, 1200.0);
        expect(mainLayoutSize.width, 800.0);

        final scrollFinder = find.byKey(
          ValueKey(
            mode == ScaffoldBodyMode.singleChildScrollView
                ? 'scaffold-page-single-child-scroll-view'
                : 'scaffold-page-custom-scroll-view',
          ),
        );
        final initialTop = tester.getTopLeft(find.text('MainLayout Child 1')).dy;
        await tester.drag(scrollFinder, const Offset(0, -450));
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(find.text('MainLayout Child 1')).dy,
          lessThan(initialTop - 350),
        );
        expect(find.text('MainLayout Child 3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  test(
    'SCREEN_JSON_AI_GUIDE documents all Scaffold bodyMode/scroll and SliverAppBar properties and applyVibe accepts them',
    () {
      final guideFile = File('SCREEN_JSON_AI_GUIDE.md').existsSync()
          ? File('SCREEN_JSON_AI_GUIDE.md')
          : File('packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md');
      final guideText = guideFile.readAsStringSync();

      for (final descriptor in [
        ...ScaffoldPageConfig.propertyDescriptors,
        ...SuperAppBar.sliverPropertyDescriptors,
      ]) {
        expect(
          guideText,
          contains(descriptor.id),
          reason:
              'Property "${descriptor.id}" must be documented in SCREEN_JSON_AI_GUIDE.md',
        );
      }

      final patched = AppearanceTransfer.applyVibe(
        Appearance(),
        jsonEncode({
          'components': {
            'root': {
              'type': 'native',
              'bodyMode': 'customScrollView',
              'extendBody': true,
              'extendBodyBehindAppBar': true,
              'scrollDirection': 'vertical',
              'reverse': true,
              'primary': false,
              'scrollPadding': 20,
              'clipBehavior': 'antiAlias',
              'regions': {'appBar': true, 'body': true},
              'placements': {
                'appBar': [
                  {'id': 'main-appbar', 'type': 'registry:ApplicationBar'},
                ],
                'body': [
                  {'id': 'scaffold:body', 'type': 'scaffold:body'},
                ],
              },
            },
            'main-appbar': {
              'type': 'native',
              'pinned': true,
              'floating': true,
              'snap': true,
              'stretch': true,
              'stretchTriggerOffset': 160,
              'expandedHeight': 220,
              'collapsedHeight': 64,
              'forceElevated': true,
              'useDefaultSemanticsOrder': false,
              'actionsPadding': 16,
              'regions': {'title': true},
              'placements': {'title': []},
            },
          },
        }),
      );

      final rootConfig = ScaffoldPageConfig.fromNative(
        patched.components['root']! as NativeComponentConfig,
      );
      expect(rootConfig.bodyMode, ScaffoldBodyMode.customScrollView);
      expect(rootConfig.extendBody, isTrue);
      expect(rootConfig.extendBodyBehindAppBar, isTrue);
      expect(rootConfig.scrollDirection, Axis.vertical);
      expect(rootConfig.reverse, isTrue);
      expect(rootConfig.primary, isFalse);
      expect(rootConfig.scrollPadding, 20.0);
      expect(rootConfig.clipBehavior, Clip.antiAlias);

      final appBarConfig =
          patched.components['main-appbar']! as NativeComponentConfig;
      expect(appBarConfig.boolProperty('pinned'), isTrue);
      expect(appBarConfig.boolProperty('floating'), isTrue);
      expect(appBarConfig.boolProperty('snap'), isTrue);
      expect(appBarConfig.boolProperty('stretch'), isTrue);
      expect(appBarConfig.doubleProperty('stretchTriggerOffset'), 160.0);
      expect(appBarConfig.doubleProperty('expandedHeight'), 220.0);
      expect(appBarConfig.doubleProperty('collapsedHeight'), 64.0);
      expect(appBarConfig.boolProperty('forceElevated'), isTrue);
      expect(appBarConfig.boolProperty('useDefaultSemanticsOrder'), isFalse);
      expect(appBarConfig.doubleProperty('actionsPadding'), 16.0);
    },
  );
}
