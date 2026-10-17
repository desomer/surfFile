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

  EditorPageRouter routing({String initial = '/'}) {
    final result = EditorPageRouter(
      initialLocation: initial,
      baseConfig: RoutingConfig(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SuperPage(child: Text('Coded home')),
          ),
          ShellRoute(
            builder: (_, _, child) => child,
            routes: [
              GoRoute(
                path: '/coded',
                builder: (_, _) => const SuperPage(child: Text('Coded')),
                routes: [
                  GoRoute(
                    path: 'details/:id',
                    builder: (_, _) => const Text('Coded detail'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(result.dispose);
    return result;
  }

  test(
    'GoRouter validates parameter constraints and constructs encoded locations',
    () {
      final controller = routing();
      final page = EditorPageConfig(
        id: 'p',
        name: 'Clients',
        path: r'/clients/:id(\d+)',
      );
      expect(controller.parametersOf(page), ['id']);
      expect(controller.locationFor(page, {'id': '42'}), '/clients/42');
      expect(
        () => controller.locationFor(page, {'id': 'abc'}),
        throwsFormatException,
      );
      expect(() => controller.locationFor(page, {}), throwsFormatException);
      final any = page.copyWith(path: '/names/:name');
      expect(
        controller.locationFor(any, {'name': 'Jean Dupont'}),
        '/names/Jean%20Dupont',
      );
      expect(
        controller.locationFor(any, {'name': 'a/b?é#x'}),
        '/names/a%2Fb%3F%C3%A9%23x',
      );
      final literalParentheses = page.copyWith(path: '/values/(:id)');
      expect(controller.parametersOf(literalParentheses), ['id']);
      expect(
        controller.locationFor(literalParentheses, {'id': '42'}),
        '/values/(42)',
      );
      final colonInConstraint = page.copyWith(path: '/values/:id(:literal)');
      expect(controller.parametersOf(colonInConstraint), ['id']);
    },
  );

  test(
    'code route catalog resolves nested routes through ShellRoute paths',
    () {
      final controller = routing();
      final route = controller.codedRoutes.singleWhere(
        (route) => route.name == null && route.path == '/coded/details/:id',
      );
      expect(route.parameters, ['id']);
      expect(
        controller.locationForCodedRoute(route, {'id': '42'}),
        '/coded/details/42',
      );
      expect(
        controller.locationForCodedRoute(route, {'id': 'a/b'}),
        '/coded/details/a%2Fb',
      );
    },
  );

  test('case-insensitive coded paths cannot overlap dynamic editor paths', () {
    final controller = EditorPageRouter(
      baseConfig: RoutingConfig(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox()),
          GoRoute(
            path: '/CLIENTS/42',
            caseSensitive: false,
            builder: (_, _) => const SizedBox(),
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    expect(
      () => controller.validate(
        EditorPageCatalog(
          pages: [EditorPageConfig(id: 'p', name: 'P', path: '/clients/:id')],
        ),
      ),
      throwsFormatException,
    );
  });

  test('home requires valid complete concrete defaults', () {
    final controller = routing();
    final home = EditorPageConfig(id: 'p', name: 'P', path: r'/users/:id(\d+)');
    expect(
      () => controller.validate(
        EditorPageCatalog(pages: [home], homePageId: 'p'),
      ),
      throwsFormatException,
    );
    expect(
      () => controller.validate(
        EditorPageCatalog(
          pages: [
            home.copyWith(defaultParameters: {'id': 'abc'}),
          ],
          homePageId: 'p',
        ),
      ),
      throwsFormatException,
    );
    controller.validate(
      EditorPageCatalog(
        pages: [
          home.copyWith(defaultParameters: {'id': '42'}),
        ],
        homePageId: 'p',
      ),
    );
  });

  test(
    'conflict checking protects coded nested routes and uncertain regexes',
    () {
      final controller = routing();
      EditorPageConfig page(String id, String path) =>
          EditorPageConfig(id: id, name: id, path: path);
      for (final path in [
        '/',
        '/coded',
        '/coded/details/:who',
        '/:anything',
        '/clients?query=true',
        '/broken/:id([)',
        '/space here',
      ]) {
        expect(
          () =>
              controller.validate(EditorPageCatalog(pages: [page('p', path)])),
          throwsFormatException,
          reason: path,
        );
      }
      expect(
        () => controller.validate(
          EditorPageCatalog(
            pages: [
              page('a', r'/clients/:id(\d+)'),
              page('b', r'/clients/:name([a-z]+)'),
            ],
          ),
        ),
        throwsFormatException,
      );
      controller.validate(
        EditorPageCatalog(
          pages: [page('a', r'/clients/:id(\d+)'), page('b', '/help/:name')],
        ),
      );
    },
  );

  testWidgets(
    'restored deep link wins over home and keeps stable router ownership',
    (tester) async {
      final controller = routing(initial: '/clients/42');
      final catalog = EditorPageCatalog(
        pages: [
          EditorPageConfig(
            id: 'client',
            name: 'Client',
            path: r'/clients/:id(\d+)',
          ),
          EditorPageConfig(id: 'help', name: 'Help', path: '/help'),
        ],
        homePageId: 'help',
      );
      final store = AppearanceStore(key: 'deep-link-pages');
      await store.save(Appearance(pageCatalog: catalog));
      await tester.pumpWidget(
        SuperApp(
          router: controller.router,
          pageRouting: controller,
          registry: Registry()..bootstrap(),
          appearanceStore: store,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-page-client')), findsOneWidget);
      expect(
        controller.router.routeInformationProvider.value.uri.path,
        '/clients/42',
      );
      final router = controller.router;
      controller.synchronize(catalog);
      expect(controller.router, same(router));
      await tester.pumpWidget(const SizedBox());
      router.go('/coded');
      expect(router.routeInformationProvider.value.uri.path, '/coded');
    },
  );

  testWidgets(
    'home used on initial root only; rename and deletion follow stable ID',
    (tester) async {
      final controller = routing();
      final home = EditorPageConfig(
        id: 'home',
        name: 'Welcome',
        path: '/welcome/:name',
        defaultParameters: {'name': 'World'},
      );
      var catalog = EditorPageCatalog(pages: [home], homePageId: home.id);
      controller.synchronize(catalog);
      await tester.pumpWidget(SuperApp(router: controller.router));
      await tester.pumpAndSettle();
      expect(
        controller.router.routeInformationProvider.value.uri.path,
        '/welcome/World',
      );
      controller.router.go('/');
      await tester.pumpAndSettle();
      expect(find.text('Coded home'), findsOneWidget);
      controller.router.go('/welcome/Alice');
      await tester.pumpAndSettle();
      catalog = catalog.copyWith(pages: [home.copyWith(path: '/hello/:name')]);
      controller.synchronize(catalog);
      await tester.pumpAndSettle();
      expect(
        controller.router.routeInformationProvider.value.uri.path,
        '/hello/Alice',
      );
      expect(controller.synchronize(EditorPageCatalog()), isNotNull);
      await tester.pumpAndSettle();
      expect(find.text('Coded home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('coded redirects survive dynamic reconfiguration', (
    tester,
  ) async {
    var redirects = 0;
    final controller = EditorPageRouter(
      baseConfig: RoutingConfig(
        redirect: (_, state) {
          redirects++;
          return state.uri.path == '/old' ? '/new' : null;
        },
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('Home')),
          GoRoute(path: '/old', builder: (_, _) => const Text('Old')),
          GoRoute(path: '/new', builder: (_, _) => const Text('New')),
        ],
      ),
    );
    addTearDown(controller.dispose);
    controller.synchronize(
      EditorPageCatalog(
        pages: [EditorPageConfig(id: 'help', name: 'Help', path: '/help')],
      ),
    );
    await tester.pumpWidget(SuperApp(router: controller.router));
    await tester.pumpAndSettle();
    controller.router.go('/old');
    await tester.pumpAndSettle();
    expect(find.text('New'), findsOneWidget);
    expect(redirects, greaterThan(0));
  });

  testWidgets(
    'restore applies home and reset safely leaves a deleted active page',
    (tester) async {
      final controller = routing();
      final catalog = EditorPageCatalog(
        pages: [
          EditorPageConfig(id: 'home', name: 'Welcome', path: '/welcome'),
        ],
        homePageId: 'home',
      );
      final store = AppearanceStore(key: 'page-home-reset');
      await store.save(Appearance(pageCatalog: catalog));
      await tester.pumpWidget(
        SuperApp(
          router: controller.router,
          pageRouting: controller,
          appearanceStore: store,
          registry: Registry()..bootstrap(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        controller.router.routeInformationProvider.value.uri.path,
        '/welcome',
      );
      final context = tester.element(
        find.byKey(const ValueKey('editor-page-home')),
      );
      final appearance = AppearanceScope.controllerOf(context)!;
      appearance.value = appearance.value.resetLayouts();
      await tester.pumpAndSettle();
      expect(controller.router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('Coded home'), findsOneWidget);
      expect(
        find.textContaining('La page courante a été supprimée'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid page imports fail before publication or persistence', (
    tester,
  ) async {
    final controller = routing();
    final store = AppearanceStore(key: 'invalid-page-import');
    await tester.pumpWidget(
      SuperApp(
        router: controller.router,
        pageRouting: controller,
        appearanceStore: store,
        registry: Registry()..bootstrap(),
      ),
    );
    await tester.pumpAndSettle();
    final appearance = AppearanceScope.controllerOf(
      tester.element(find.text('Coded home')),
    )!;
    final original = appearance.value;
    expect(
      () => appearance.value = original.copyWith(
        pageCatalog: EditorPageCatalog(
          pages: [EditorPageConfig(id: 'bad', name: 'Bad', path: '/coded')],
        ),
      ),
      throwsFormatException,
    );
    expect(appearance.value, same(original));
    await tester.pumpAndSettle();
    expect((await store.load()).pageCatalog.pages, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
