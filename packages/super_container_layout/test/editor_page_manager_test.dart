import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Finder action(String tooltip) => find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == tooltip,
  );
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

  Future<EditorPageRouter> mount(WidgetTester tester, {Size? screen}) async {
    if (screen != null) {
      await tester.binding.setSurfaceSize(screen);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    final routing = EditorPageRouter(
      baseConfig: RoutingConfig(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SuperPage(child: Text('Coded')),
            routes: [
              GoRoute(
                path: r'detail/:id(\d+)',
                name: 'coded-detail',
                builder: (_, state) =>
                    Text('Code ${state.pathParameters['id']}'),
              ),
            ],
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
    final context = tester.element(find.text('Coded'));
    expect(find.byKey(const ValueKey('style-edit-banner-pages')), findsNothing);
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    return routing;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-pages')));
    await tester.pumpAndSettle();
  }

  Future<void> add(
    WidgetTester tester,
    String name,
    String path, {
    bool valid = true,
  }) async {
    await tester.tap(find.byKey(const ValueKey('editor-pages-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-page-name')),
      name,
    );
    await tester.enterText(
      find.byKey(const ValueKey('editor-page-path')),
      path,
    );
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    if (!valid) return;
    expect(
      find.byKey(const ValueKey('editor-page-name')),
      findsNothing,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join('\n'),
    );
    expect(
      find.text(name),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join('\n'),
    );
  }

  testWidgets('manager adds only on Apply and supports atomic undo redo', (
    tester,
  ) async {
    final routing = await mount(tester);
    final context = tester.element(find.text('Coded'));
    final appearance = AppearanceScope.controllerOf(context)!;
    final history = EditorHistoryScope.controllerOf(context)!;
    await open(tester);
    await add(tester, 'Help', '/help');
    expect(appearance.value.pageCatalog.pages, isEmpty);
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    expect(appearance.value.pageCatalog.pages, isEmpty);
    await open(tester);
    await add(tester, 'Help', '/help');
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(appearance.value.pageCatalog.pages.single.name, 'Help');
    expect(history.canUndo, isTrue);
    history.undo();
    await tester.pumpAndSettle();
    expect(appearance.value.pageCatalog.pages, isEmpty);
    expect(history.canUndo, isFalse);
    history.redo();
    await tester.pumpAndSettle();
    expect(appearance.value.pageCatalog.pages.single.path, '/help');
    routing.router.go('/help');
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        ValueKey('editor-page-${appearance.value.pageCatalog.pages.single.id}'),
      ),
      findsOneWidget,
    );
    LayoutSelection.select(['Help']);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scaffold-page-add-body')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scaffold-page-add-slot-factory:NewContainer')),
    );
    await tester.pumpAndSettle();
    final pageId = appearance.value.pageCatalog.pages.single.id;
    expect(
      appearance.value.nativeComponents[pageId]!.slotsOf('body'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manager duplicates reorders chooses home and confirms deletion',
    (tester) async {
      await mount(tester);
      final appearance = AppearanceScope.controllerOf(
        tester.element(find.text('Coded')),
      )!;
      await open(tester);
      await add(tester, 'Help', '/help');
      await tester.tap(action('Dupliquer'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('editor-page-name')),
        'Copy',
      );
      await tester.enterText(
        find.byKey(const ValueKey('editor-page-path')),
        '/copy',
      );
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(action('Monter').last);
      await tester.pumpAndSettle();
      await tester.tap(action('Page d’accueil').first);
      await tester.pumpAndSettle();
      await tester.tap(action('Supprimer').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer').last);
      await tester.pumpAndSettle();
      expect(find.text('Help'), findsNothing);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      final catalog = appearance.value.pageCatalog;
      expect(catalog.pages.single.name, 'Copy');
      expect(catalog.homePageId, catalog.pages.single.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening dirty page confirms apply and navigates to actual route',
    (tester) async {
      final routing = await mount(tester);
      final appearance = AppearanceScope.controllerOf(
        tester.element(find.text('Coded')),
      )!;
      await open(tester);
      await add(tester, 'Help', '/help');
      await tester.tap(action('Ouvrir').first);
      await tester.pumpAndSettle();
      expect(find.text('Appliquer avant d’ouvrir ?'), findsOneWidget);
      await tester.tap(find.text('Appliquer et ouvrir'));
      await tester.pumpAndSettle();
      expect(routing.router.routeInformationProvider.value.uri.path, '/help');
      expect(appearance.value.pageCatalog.pages.single.name, 'Help');
      expect(find.byKey(const ValueKey('editor-pages-manager')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manager refuses coded route collisions and stale drafts', (
    tester,
  ) async {
    await mount(tester);
    final appearance = AppearanceScope.controllerOf(
      tester.element(find.text('Coded')),
    )!;
    await open(tester);
    await add(tester, 'Bad', '/', valid: false);
    expect(find.byKey(const ValueKey('editor-page-name')), findsOneWidget);
    expect(find.textContaining('Chemin absolu requis'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('editor-page-path')),
      '/valid',
    );
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    appearance.value = appearance.value.copyWith(accent: Colors.red);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Les dispositions ont changé ailleurs'),
      findsOneWidget,
    );
    expect(appearance.value.pageCatalog.pages, isEmpty);
    await tester.tap(find.text('Recharger le brouillon'));
    await tester.pumpAndSettle();
    expect(find.text('Bad'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manager remains usable on a narrow viewport', (tester) async {
    await mount(tester, screen: const Size(400, 700));
    await open(tester);
    await add(tester, 'Help', '/help');
    expect(find.text('Help'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('parameterized home editing and Open validate concrete values', (
    tester,
  ) async {
    final routing = await mount(tester);
    final appearance = AppearanceScope.controllerOf(
      tester.element(find.text('Coded')),
    )!;
    await open(tester);
    await add(tester, 'Client', r'/clients/:id(\d+)');
    await tester.tap(action('Page d’accueil'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Les valeurs ne respectent pas'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '42');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(action('Modifier'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-page-name')),
      'Customer',
    );
    await tester.enterText(
      find.byKey(const ValueKey('editor-page-path')),
      r'/customers/:id(\d+)',
    );
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Customer'), findsOneWidget);
    await tester.tap(action('Ouvrir').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '42',
    );
    await tester.enterText(find.byType(TextField), '84');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    expect(appearance.value.pageCatalog.pages, isEmpty);
    expect(find.text('Customer'), findsOneWidget);
    await tester.tap(action('Ouvrir').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '84');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer et ouvrir'));
    await tester.pumpAndSettle();
    expect(
      routing.router.routeInformationProvider.value.uri.path,
      '/customers/84',
    );
    final catalog = appearance.value.pageCatalog;
    expect(catalog.homePageId, catalog.pages.single.id);
    expect(catalog.pages.single.defaultParameters, {'id': '42'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain router integration never exposes page management', (
    tester,
  ) async {
    final routing = EditorPageRouter(
      baseConfig: RoutingConfig(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SuperPage(child: Text('Plain')),
          ),
        ],
      ),
    );
    addTearDown(routing.dispose);
    await tester.pumpWidget(
      SuperApp(router: routing.router, registry: Registry()..bootstrap()),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Plain'));
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('style-edit-banner-pages')), findsNothing);
  });

  testWidgets(
    'coded pages are read-only entries and parameterized routes open',
    (tester) async {
      final routing = await mount(tester);
      await open(tester);
      final row = find.byKey(
        const ValueKey(r'editor-coded-route-/detail/:id(\d+)'),
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byType(IconButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey(r'editor-coded-route-open-/detail/:id(\d+)')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not-a-number');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Les valeurs ne respectent pas'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '42');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(
        routing.router.routeInformationProvider.value.uri.path,
        '/detail/42',
      );
      expect(find.text('Code 42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
