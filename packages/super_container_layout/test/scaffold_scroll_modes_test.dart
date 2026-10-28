import 'dart:async';

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
      scrollDirection: Axis.horizontal,
      reverse: true,
      primary: false,
      scrollPadding: 16,
      clipBehavior: Clip.antiAlias,
    );
    expect(configured.bodyMode, ScaffoldBodyMode.customScrollView);
    expect(configured.scrollDirection, Axis.horizontal);
    expect(configured.reverse, isTrue);
    expect(configured.primary, isFalse);
    expect(configured.scrollPadding, 16.0);
    expect(configured.clipBehavior, Clip.antiAlias);

    final restored = ScaffoldPageConfig.fromJson(configured.toJson());
    expect(restored.bodyMode, ScaffoldBodyMode.customScrollView);
    expect(restored.scrollDirection, Axis.horizontal);
    expect(restored.reverse, isTrue);
    expect(restored.primary, isFalse);
    expect(restored.scrollPadding, 16.0);
    expect(restored.clipBehavior, Clip.antiAlias);

    final singleScroll = restored
        .withBodyMode(ScaffoldBodyMode.singleChildScrollView)
        .withScrollDirection(Axis.vertical)
        .withReverse(false)
        .withScrollPadding(8);
    expect(singleScroll.bodyMode, ScaffoldBodyMode.singleChildScrollView);
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
          appBar: SuperAppBar(title: Text('Fixed Header')),
          child: Text('Fixed Body'),
        ),
        registry: Registry(),
      );

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
        find.byKey(const ValueKey('super-app-bar-prop-expandedHeight')),
        findsOneWidget,
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
}
