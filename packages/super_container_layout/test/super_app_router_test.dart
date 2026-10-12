import 'dart:async';

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

  GoRouter createRouter({String initialLocation = '/'}) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => SuperPage(
            appBar: const SuperAppBar(title: Text('Home')),
            child: Center(
              child: FilledButton(
                onPressed: () => context.push('/details/42'),
                child: const Text('Open details'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/details/:id',
          builder: (context, state) => SuperPage(
            id: 'details',
            appBar: const SuperAppBar(
              id: 'details-appBar',
              title: Text('Details'),
            ),
            child: Center(child: Text('Item ${state.pathParameters['id']}')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    return router;
  }

  testWidgets('SuperPage provides an empty root page by default', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SuperPage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(SuperPage), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(SuperApp.of(tester.element(find.byType(SuperPage))).router,
        same(router));
    expect(tester.takeException(), isNull);
  });

  testWidgets('routed pages can push and navigate back using their app bar', (
    tester,
  ) async {
    final router = createRouter();
    await tester.pumpWidget(SuperApp(router: router));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    expect(find.text('Item 42'), findsOneWidget);
    expect(router.canPop(), isTrue);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoration gates deep links and exposes shared services', (
    tester,
  ) async {
    final router = createRouter(initialLocation: '/details/73');
    final store = _DeferredAppearanceStore();
    final registry = Registry();
    final app = SuperApp(
      router: router,
      appearanceStore: store,
      registry: registry,
    );
    await tester.pumpWidget(app);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SuperPage), findsNothing);
    store.result.complete(Appearance(mode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Item 73'));
    expect(SuperApp.of(context), same(app));
    expect(SuperApp.of(context).router, same(router));
    expect(SuperApp.of(context).registry, same(registry));
    expect(
      AppearanceScope.controllerOf(context),
      isA<PersistentAppearanceController>(),
    );
    expect(EditorHistoryScope.controllerOf(context), isNotNull);
    expect(StyleEditScope.controllerOf(context), isNotNull);
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(find.byKey(const ValueKey('background-neon')), findsOneWidget);

    AppearanceScope.controllerOf(context)!.value = Appearance(
      mode: ThemeMode.light,
    );
    await tester.pumpAndSettle();
    expect(find.text('Item 73'), findsOneWidget);
    expect(Theme.of(context).brightness, Brightness.light);
    expect(tester.takeException(), isNull);
  });

  for (final reset in [false, true]) {
    testWidgets(
      'restoration errors retain the deep link after ${reset ? 'reset' : 'retry'}',
      (tester) async {
        final router = createRouter(initialLocation: '/details/99');
        final store = _FailingAppearanceStore();
        await tester.pumpWidget(
          SuperApp(router: router, appearanceStore: store),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Impossible de charger les paramètres'),
          findsOneWidget,
        );
        expect(find.byType(SuperPage), findsNothing);
        store.failing = false;
        await tester.tap(
          find.text(reset ? 'Réinitialiser les paramètres' : 'Réessayer'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Item 99'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('edit banner opens its dialog through the router navigator', (
    tester,
  ) async {
    final router = createRouter();
    await tester.pumpWidget(SuperApp(router: router));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Home'));
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-transfer')));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceTransferDialog), findsOneWidget);
    router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceTransferDialog), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell routes keep edit dialogs on the root navigator', (
    tester,
  ) async {
    final shellNavigator = GlobalKey<NavigatorState>();
    final router = GoRouter(
      routes: [
        ShellRoute(
          navigatorKey: shellNavigator,
          builder: (context, state, child) => child,
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) =>
                  const SuperPage(child: Text('Shell content')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Shell content'));
    expect(SuperApp.of(context).router, same(router));
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-transfer')));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceTransferDialog), findsOneWidget);
    expect(router.routerDelegate.navigatorKey.currentState!.canPop(), isTrue);
    expect(shellNavigator.currentState!.canPop(), isFalse);
    router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Shell content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'router replacement and app disposal leave caller routers alive',
    (tester) async {
      final first = createRouter();
      final second = createRouter(initialLocation: '/details/7');
      final store = AppearanceStore();
      await tester.pumpWidget(
        SuperApp(router: first, appearanceStore: store),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        SuperApp(router: second, appearanceStore: store),
      );
      await tester.pumpAndSettle();
      expect(find.text('Item 7'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      first.go('/details/8');
      second.go('/');
      await tester.pumpWidget(
        SuperApp(router: first, appearanceStore: store),
      );
      await tester.pumpAndSettle();
      expect(find.text('Item 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _DeferredAppearanceStore extends AppearanceStore {
  final result = Completer<Appearance>();

  @override
  Future<Appearance> load() => result.future;
}

class _FailingAppearanceStore extends AppearanceStore {
  bool failing = true;

  @override
  Future<Appearance> load() async {
    if (failing) throw const FormatException('Invalid test appearance');
    return codec.defaults;
  }
}
