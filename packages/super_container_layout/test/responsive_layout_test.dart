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

  group('ResponsiveLayoutConfig & codecs', () {
    test('default values keep fullPage and standard breakpoints/gutters', () {
      const config = ResponsiveLayoutConfig();
      expect(config.containerMode, PageContainerMode.fullPage);
      expect(config.maxWidth, 1440);
      expect(config.gutters.mobile, 24);
      expect(config.gutters.desktop, 32);
      expect(config.breakpoints.mobileWidth, 375);
      expect(config.breakpoints.tabletMinWidth, 768);
      expect(config.breakpoints.desktopMinWidth, 1280);
      expect(config.breakpoints.largeDesktopMinWidth, 1440);
      expect(config.toCompactJson(), isEmpty);

      final resolvedFull = config.resolveForWidth(1920);
      expect(resolvedFull.breakpoint, ResponsiveBreakpoint.largeDesktop);
      expect(resolvedFull.isConstrained, isFalse);
      expect(resolvedFull.maxWidth, isNull);
      expect(resolvedFull.gutter, 0);
    });

    test('resolves breakpoints and gutters accurately across thresholds', () {
      const config = ResponsiveLayoutConfig(
        containerMode: PageContainerMode.constrained,
      );
      expect(
        config.resolveForWidth(374),
        const ResolvedPageLayout(
          breakpoint: ResponsiveBreakpoint.mobile,
          containerMode: PageContainerMode.constrained,
          maxWidth: 1440,
          gutter: 24,
        ),
      );
      expect(
        config.resolveForWidth(375).breakpoint,
        ResponsiveBreakpoint.mobile,
      );
      expect(config.resolveForWidth(767).gutter, 24);
      expect(
        config.resolveForWidth(768),
        const ResolvedPageLayout(
          breakpoint: ResponsiveBreakpoint.tablet,
          containerMode: PageContainerMode.constrained,
          maxWidth: 1440,
          gutter: 24,
        ),
      );
      expect(
        config.resolveForWidth(1279).breakpoint,
        ResponsiveBreakpoint.tablet,
      );
      expect(
        config.resolveForWidth(1280),
        const ResolvedPageLayout(
          breakpoint: ResponsiveBreakpoint.desktop,
          containerMode: PageContainerMode.constrained,
          maxWidth: 1440,
          gutter: 32,
        ),
      );
      expect(
        config.resolveForWidth(1439).breakpoint,
        ResponsiveBreakpoint.desktop,
      );
      expect(
        config.resolveForWidth(1440),
        const ResolvedPageLayout(
          breakpoint: ResponsiveBreakpoint.largeDesktop,
          containerMode: PageContainerMode.constrained,
          maxWidth: 1440,
          gutter: 32,
        ),
      );
    });

    test('validates breakpoint order, maxWidth, and gutter bounds', () {
      expect(
        () => const ResponsiveBreakpointsConfig(
          mobileWidth: 800,
          tabletMinWidth: 768,
        ).validate(),
        throwsArgumentError,
      );
      expect(
        () => const ResponsiveLayoutConfig(maxWidth: 100).validate(),
        throwsArgumentError,
      );
      expect(
        () => const ResponsiveGuttersConfig(mobile: -4).validate(),
        throwsArgumentError,
      );
    });

    test('serializes via AppearanceCodec and DefaultAppearanceCodec', () {
      const codec = AppearanceCodec();
      const defaultCodec = DefaultAppearanceCodec();
      final page = EditorPageConfig(
        id: 'landing',
        name: 'Landing',
        path: '/landing',
        layoutOverride: const ResponsiveLayoutOverride(
          containerMode: PageContainerMode.constrained,
          maxWidth: 1200,
          mobileGutter: 16,
        ),
      );
      final appearance = DefaultAppearance(
        responsiveLayout: const ResponsiveLayoutConfig(
          containerMode: PageContainerMode.constrained,
          maxWidth: 1440,
          gutters: ResponsiveGuttersConfig(mobile: 24, desktop: 32),
        ),
        pageCatalog: EditorPageCatalog(pages: [page]),
      );

      final encoded = defaultCodec.encode(appearance);
      final decoded = defaultCodec.decode(encoded);
      expect(decoded.responsiveLayout, appearance.responsiveLayout);
      expect(
        decoded.pageCatalog.pages.single.layoutOverride,
        page.layoutOverride,
      );

      final patched = codec.patchFromJson(Appearance(), {
        'responsiveLayout': {
          'containerMode': 'constrained',
          'gutters': {'mobile': 20},
        },
      });
      expect(
        patched.responsiveLayout.containerMode,
        PageContainerMode.constrained,
      );
      expect(patched.responsiveLayout.gutters.mobile, 20);
      expect(patched.responsiveLayout.gutters.desktop, 32);

      final exported = AppearanceTransfer.export(appearance, {
        TransferGroup.layouts,
      }, codec: codec);
      final imported = AppearanceTransfer.import(Appearance(), exported, {
        TransferGroup.layouts,
      }, codec: codec);
      expect(imported.responsiveLayout, appearance.responsiveLayout);
    });
  });

  group('ResponsiveBodyContainer & SuperPage rendering', () {
    Future<void> pumpStandalonePage(
      WidgetTester tester, {
      required Size screenSize,
      required Appearance appearance,
      required SuperPage page,
    }) async {
      await tester.binding.setSurfaceSize(screenSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ValueNotifier<Appearance>(appearance);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AppearanceScope(controller: controller, child: page),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('fullPage mode keeps full width without gutters', (
      tester,
    ) async {
      ResponsiveBreakpointScope? scope;
      await pumpStandalonePage(
        tester,
        screenSize: const Size(1920, 900),
        appearance: Appearance(),
        page: SuperPage(
          appBar: AppBar(
            title: const SizedBox(
              key: ValueKey('appbar-title'),
              child: Text('Header'),
            ),
          ),
          child: Builder(
            builder: (context) {
              scope = ResponsiveBreakpointScope.maybeOf(context);
              return const SizedBox.expand(key: ValueKey('body-content'));
            },
          ),
        ),
      );

      final bodyBox = tester.getRect(find.byKey(const ValueKey('body-content')));
      expect(bodyBox.left, 0);
      expect(bodyBox.width, 1920);
      expect(scope?.layout.containerMode, PageContainerMode.fullPage);
      expect(scope?.layout.breakpoint, ResponsiveBreakpoint.largeDesktop);
      expect(scope?.layout.gutter, 0);
    });

    testWidgets(
      'constrained mode centers 1440px body with flexible margins and 32px desktop gutters while keeping AppBar full width',
      (tester) async {
        ResponsiveBreakpointScope? scope;
        await pumpStandalonePage(
          tester,
          screenSize: const Size(1920, 900),
          appearance: Appearance(
            responsiveLayout: const ResponsiveLayoutConfig(
              containerMode: PageContainerMode.constrained,
            ),
          ),
          page: SuperPage(
            appBar: AppBar(
              title: const Text('Site Header'),
            ),
            child: Builder(
              builder: (context) {
                scope = ResponsiveBreakpointScope.maybeOf(context);
                return const SizedBox.expand(key: ValueKey('body-content'));
              },
            ),
          ),
        );

        final appBarBox = tester.getRect(find.byType(AppBar));
        expect(appBarBox.width, 1920);

        final containerBox = tester.getRect(
          find.byKey(const ValueKey('responsive-body-constrained')),
        );
        expect(containerBox.width, 1440);
        expect(containerBox.left, 240);
        expect(containerBox.right, 1680);

        final contentBox = tester.getRect(
          find.byKey(const ValueKey('body-content')),
        );
        expect(contentBox.left, 240 + 32);
        expect(contentBox.width, 1440 - 64);
        expect(scope?.layout.breakpoint, ResponsiveBreakpoint.largeDesktop);
        expect(scope?.layout.gutter, 32);
      },
    );

    testWidgets('constrained mode applies 24px gutter on mobile (375px)', (
      tester,
    ) async {
      ResponsiveBreakpointScope? scope;
      await pumpStandalonePage(
        tester,
        screenSize: const Size(375, 800),
        appearance: Appearance(
          responsiveLayout: const ResponsiveLayoutConfig(
            containerMode: PageContainerMode.constrained,
          ),
        ),
        page: SuperPage(
          child: Builder(
            builder: (context) {
              scope = ResponsiveBreakpointScope.maybeOf(context);
              return const SizedBox.expand(key: ValueKey('body-content'));
            },
          ),
        ),
      );

      final contentBox = tester.getRect(
        find.byKey(const ValueKey('body-content')),
      );
      expect(contentBox.left, 24);
      expect(contentBox.width, 375 - 48);
      expect(scope?.layout.breakpoint, ResponsiveBreakpoint.mobile);
      expect(scope?.layout.gutter, 24);
    });

    testWidgets('per-page layoutOverride overrides global fullPage', (
      tester,
    ) async {
      await pumpStandalonePage(
        tester,
        screenSize: const Size(1920, 900),
        appearance: Appearance(
          pageCatalog: EditorPageCatalog(
            pages: [
              EditorPageConfig(
                id: 'site-home',
                name: 'Accueil',
                path: '/accueil',
                layoutOverride: const ResponsiveLayoutOverride(
                  containerMode: PageContainerMode.constrained,
                  maxWidth: 1440,
                ),
              ),
            ],
          ),
        ),
        page: const SuperPage(
          id: 'site-home',
          child: SizedBox.expand(key: ValueKey('body-content')),
        ),
      );

      final contentBox = tester.getRect(
        find.byKey(const ValueKey('body-content')),
      );
      expect(contentBox.left, 240 + 32);
      expect(contentBox.width, 1440 - 64);
    });

    testWidgets(
      'works in singleChildScrollView and customScrollView body modes',
      (tester) async {
        for (final mode in [
          ScaffoldBodyMode.singleChildScrollView,
          ScaffoldBodyMode.customScrollView,
        ]) {
          await pumpStandalonePage(
            tester,
            screenSize: const Size(1920, 900),
            appearance: Appearance(
              responsiveLayout: const ResponsiveLayoutConfig(
                containerMode: PageContainerMode.constrained,
              ),
            ),
            page: SuperPage(
              bodyMode: mode,
              child: const SizedBox(
                key: ValueKey('scroll-body-content'),
                height: 200,
                width: double.infinity,
              ),
            ),
          );

          final contentBox = tester.getRect(
            find.byKey(const ValueKey('scroll-body-content')),
          );
          expect(contentBox.left, 240 + 32);
          expect(contentBox.width, 1440 - 64);
        }
      },
    );
  });

  group('Editor viewport preview & settings UI', () {
    testWidgets(
      'StyleEditBanner viewport preview simulates mobile 375px and resets to Auto',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => SuperPage(
                  responsiveLayout: const ResponsiveLayoutConfig(
                    containerMode: PageContainerMode.constrained,
                  ),
                  child: Builder(
                    builder: (context) {
                      final bp = ResponsiveBreakpointScope.breakpointOf(
                        context,
                      );
                      final mediaWidth = MediaQuery.sizeOf(context).width;
                      return Text(
                        'bp:${bp?.name ?? "none"} w:${mediaWidth.round()}',
                        key: const ValueKey('preview-probe'),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
        addTearDown(routing.dispose);

        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: Registry()..bootstrap(),
          ),
        );
        await tester.pumpAndSettle();

        final probeFinder = find.byKey(const ValueKey('preview-probe'));
        expect(probeFinder, findsOneWidget);
        expect(tester.widget<Text>(probeFinder).data, 'bp:largeDesktop w:1600');

        final probeCtx = tester.element(probeFinder);
        StyleEditScope.controllerOf(probeCtx)!.value = true;
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('style-edit-banner-viewport')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('viewport-preview-mobile')));
        await tester.pumpAndSettle();

        expect(find.text('bp:mobile w:375'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('editor-viewport-preview-frame-mobile')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('style-edit-banner-viewport')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('viewport-preview-auto')));
        await tester.pumpAndSettle();

        expect(find.text('bp:largeDesktop w:1600'), findsOneWidget);
      },
    );

    testWidgets(
      'AppearanceSettings toggles global constrained container mode',
      (tester) async {
        final controller = ValueNotifier<Appearance>(Appearance());
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: AppearanceServicesScope(
              codec: const AppearanceCodec(),
              child: AppearanceScope(
                controller: controller,
                child: const Scaffold(body: AppearanceSettings()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('appearance-section-responsive')),
        );
        await tester.pumpAndSettle();

        expect(
          controller.value.responsiveLayout.containerMode,
          PageContainerMode.fullPage,
        );
        await tester.tap(find.text('Conteneur centré'));
        await tester.pumpAndSettle();

        expect(
          controller.value.responsiveLayout.containerMode,
          PageContainerMode.constrained,
        );
        expect(find.byKey(const ValueKey('responsive-max-width')), findsOne);
      },
    );

    testWidgets(
      'EditorPageManager configures per-page layoutOverride',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const SuperPage(child: Text('Home')),
              ),
            ],
          ),
        );
        addTearDown(routing.dispose);
        final registry = Registry()..bootstrap();

        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
          ),
        );
        await tester.pumpAndSettle();

        final ctx = tester.element(find.text('Home'));
        StyleEditScope.controllerOf(ctx)!.value = true;
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('style-edit-banner-pages')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('editor-pages-add')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('editor-page-name')),
          'Portail',
        );
        await tester.enterText(
          find.byKey(const ValueKey('editor-page-path')),
          '/portail',
        );
        await tester.tap(find.text('Centré'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-page-max-width')),
          '1440',
        );
        await tester.enterText(
          find.byKey(const ValueKey('editor-page-gutter-mobile')),
          '24',
        );
        await tester.enterText(
          find.byKey(const ValueKey('editor-page-gutter-desktop')),
          '32',
        );
        await tester.tap(find.text('Valider').hitTestable());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Appliquer'));
        await tester.pumpAndSettle();

        final appearance = AppearanceScope.of(
          tester.element(find.text('Home')),
        );
        expect(appearance.pageCatalog.pages, hasLength(1));
        final override = appearance.pageCatalog.pages.single.layoutOverride;
        expect(override, isNotNull);
        expect(override!.containerMode, PageContainerMode.constrained);
        expect(override.maxWidth, 1440);
        expect(override.mobileGutter, 24);
        expect(override.desktopGutter, 32);
      },
    );
  });
}
