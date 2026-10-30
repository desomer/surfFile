import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channels = [
    MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('ComponentBehavior models', () {
    test('GoToPageAction serialization and execution', () {
      const action = GoToPageAction(
        pagePath: '/details',
        pageId: 'page-1',
        pageName: 'Détails',
      );
      expect(action.type, 'goToPage');
      expect(action.label, 'Aller à la page');
      expect(action.description, 'Détails (/details)');

      final json = action.toJson();
      expect(json['type'], 'goToPage');
      expect(json['pagePath'], '/details');
      expect(json['pageId'], 'page-1');
      expect(json['pageName'], 'Détails');

      final decoded = BehaviorActionCatalog.decode(json);
      expect(decoded, isA<GoToPageAction>());
      expect(decoded, equals(action));
      expect(decoded.hashCode, equals(action.hashCode));
    });

    test('ComponentBehavior serialization and catalog', () {
      const behavior = ComponentBehavior(
        id: 'b-1',
        trigger: BehaviorTrigger.click,
        action: GoToPageAction(pagePath: '/home'),
      );
      final json = behavior.toJson();
      final decoded = ComponentBehavior.fromJson(json);
      expect(decoded.id, 'b-1');
      expect(decoded.trigger, BehaviorTrigger.click);
      expect(decoded.action, isA<GoToPageAction>());
      expect((decoded.action as GoToPageAction).pagePath, '/home');
      expect(decoded, equals(behavior));

      expect(BehaviorCatalog.items, contains(BehaviorCatalog.goToPage));
    });

    test(
      'Appearance with behaviors survives AppearanceCodec encode and decode',
      () {
        const codec = AppearanceCodec();
        final initial = Appearance(
          behaviors: {
            'comp-1': [
              const ComponentBehavior(
                id: 'b-1',
                trigger: BehaviorTrigger.click,
                action: GoToPageAction(pagePath: '/target', pageName: 'Cible'),
              ),
            ],
          },
        );

        final encoded = codec.encode(initial);
        final restored = codec.decode(encoded);

        expect(restored.behaviorsFor('comp-1'), hasLength(1));
        final b = restored.behaviorsFor('comp-1').first;
        expect(b.id, 'b-1');
        expect(b.trigger, BehaviorTrigger.click);
        expect((b.action as GoToPageAction).pagePath, '/target');
        expect((b.action as GoToPageAction).pageName, 'Cible');

        final updated = initial.withAddedBehavior(
          'comp-1',
          const ComponentBehavior(
            id: 'b-2',
            trigger: BehaviorTrigger.click,
            action: GoToPageAction(pagePath: '/second'),
          ),
        );
        expect(updated.behaviorsFor('comp-1'), hasLength(2));

        final removed = updated.withRemovedBehavior('comp-1', 'b-1');
        expect(removed.behaviorsFor('comp-1'), hasLength(1));
        expect(removed.behaviorsFor('comp-1').first.id, 'b-2');
      },
    );
  });

  group('Behavior Context Menu and Editor Widget Tests', () {
    testWidgets('Context menu offers Composant and Comportement buttons', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);

      final appearance = ValueNotifier(
        Appearance(
          pageCatalog: EditorPageCatalog(
            pages: [
              EditorPageConfig(id: 'home', name: 'Accueil', path: '/home'),
              EditorPageConfig(id: 'about', name: 'À propos', path: '/about'),
            ],
          ),
        ),
      );
      addTearDown(appearance.dispose);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, _) => Scaffold(
              body: Center(
                child: EditorSlotAction(
                  label: 'Mon bouton',
                  enabled: true,
                  onEdit: () async {},
                  insertion: EditorSlotInsertion(
                    label: 'Mon bouton',
                    host: const InsertionHost(axis: Axis.vertical),
                    acceptsTags: (_) => true,
                    insert: (plan, comp) async {},
                  ),
                  child: EditorSlot(
                    id: 'btn-target',
                    label: 'Mon bouton',
                    child: const Text('Target Text'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/about',
            builder: (context, _) =>
                const Scaffold(body: Center(child: Text('About Page Content'))),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: StyleEditScope(
            controller: editing,
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Right-click on target
      await tester.tap(
        find.text('Target Text'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      // Check that both buttons are displayed
      expect(find.text('Composant…'), findsOneWidget);
      expect(find.text('Comportement…'), findsOneWidget);

      // Tap on Comportement… button
      await tester.tap(find.byKey(const ValueKey('style-menu-behavior')));
      await tester.pumpAndSettle();

      // Behavior wizard should be open
      expect(find.byKey(const ValueKey('behavior-add-wizard')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('behavior-add-stepper')),
        findsOneWidget,
      );

      // Step 0: Élément
      expect(
        find.byKey(const ValueKey('behavior-target-btn-target')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();

      // Step 1: Comportement
      expect(
        find.byKey(const ValueKey('behavior-catalog-go_to_page')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();

      // Step 2: Configuration
      expect(
        find.byKey(const ValueKey('behavior-page-dropdown')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
      await tester.pumpAndSettle();

      // Step 3: Récapitulatif
      expect(find.byKey(const ValueKey('behavior-add-submit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('behavior-add-submit')));
      await tester.pumpAndSettle();

      // Check that behavior is now in appearance for 'btn-target'
      expect(appearance.value.behaviorsFor('btn-target'), hasLength(1));
      final b = appearance.value.behaviorsFor('btn-target').first;
      expect(b.trigger, BehaviorTrigger.click);
      expect(b.action, isA<GoToPageAction>());

      // Switch off edit mode
      editing.value = false;
      await tester.pumpAndSettle();

      // Now click on the component in run mode -> should trigger navigation to '/home'
      await tester.tap(find.text('Target Text'));
      await tester.pumpAndSettle();
    });

    testWidgets('Click behavior triggers navigation to selected page', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final editing = ValueNotifier(false);
      addTearDown(editing.dispose);

      final appearance = ValueNotifier(
        Appearance(
          behaviors: {
            'card-target': [
              const ComponentBehavior(
                id: 'b-nav',
                trigger: BehaviorTrigger.click,
                action: GoToPageAction(pagePath: '/about'),
              ),
            ],
          },
        ),
      );
      addTearDown(appearance.dispose);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, _) => Scaffold(
              body: Center(
                child: EditorSlot(
                  id: 'card-target',
                  label: 'Ma Carte',
                  child: const Text('Clickable Card'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/about',
            builder: (context, _) => const Scaffold(
              body: Center(child: Text('Arrived on About Page!')),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: StyleEditScope(
            controller: editing,
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clickable Card'), findsOneWidget);
      expect(find.text('Arrived on About Page!'), findsNothing);

      // Tap on the card
      await tester.tap(find.text('Clickable Card'));
      await tester.pumpAndSettle();

      // Navigation should have executed!
      expect(find.text('Arrived on About Page!'), findsOneWidget);
    });

    testWidgets(
      'Wizard allows selecting parent element in hierarchy to attach behavior',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final editing = ValueNotifier(true);
        addTearDown(editing.dispose);

        final appearance = ValueNotifier(
          Appearance(
            pageCatalog: EditorPageCatalog(
              pages: [
                EditorPageConfig(
                  id: 'details',
                  name: 'Détails',
                  path: '/details',
                ),
              ],
            ),
          ),
        );
        addTearDown(appearance.dispose);

        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, _) => Scaffold(
                body: Center(
                  child: EditorSlotAction(
                    label: 'Parent Card',
                    enabled: true,
                    onEdit: () async {},
                    child: EditorSlot(
                      id: 'parent-card',
                      label: 'Parent Card',
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: EditorSlot(
                          id: 'child-text',
                          label: 'Child Text',
                          child: const Text('Nested Child'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/details',
              builder: (context, _) =>
                  const Scaffold(body: Center(child: Text('Details Screen'))),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: StyleEditScope(
              controller: editing,
              child: MaterialApp.router(routerConfig: router),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Right-click on child
        await tester.tap(
          find.text('Nested Child'),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        // Tap on Comportement…
        await tester.tap(find.byKey(const ValueKey('style-menu-behavior')));
        await tester.pumpAndSettle();

        // In Step 0: both child and parent card should be offered!
        expect(
          find.byKey(const ValueKey('behavior-target-child-text')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('behavior-target-parent-card')),
          findsOneWidget,
        );

        // Hover over parent-card target in EditorTargetSelector -> parent EditorSlot should show outline!
        final parentSlotFinder = find.ancestor(
          of: find.text('Nested Child'),
          matching: find.byWidgetPredicate(
            (w) => w is EditorSlot && w.id == 'parent-card',
          ),
        );
        CustomPaint parentOutlinePaint() => tester.widget<CustomPaint>(
          find
              .descendant(
                of: parentSlotFinder,
                matching: find.byType(CustomPaint),
              )
              .first,
        );

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(gesture.removePointer);
        await gesture.addPointer(location: Offset.zero);
        await tester.pump();
        await gesture.moveTo(
          tester.getCenter(
            find.byKey(const ValueKey('behavior-target-parent-card')),
          ),
        );
        await tester.pump();
        expect(parentOutlinePaint().foregroundPainter, isNotNull);

        await gesture.moveTo(Offset.zero);
        await tester.pump();
        expect(parentOutlinePaint().foregroundPainter, isNull);

        // Select parent-card instead of child-text
        await tester.tap(
          find.byKey(const ValueKey('behavior-target-parent-card')),
        );
        await tester.pumpAndSettle();

        // Move to step 1 (catalog)
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();

        // Move to step 2 (settings)
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();

        // Move to step 3 (summary)
        await tester.tap(find.byKey(const ValueKey('behavior-add-next')));
        await tester.pumpAndSettle();

        // Apply
        await tester.tap(find.byKey(const ValueKey('behavior-add-submit')));
        await tester.pumpAndSettle();

        // Behavior should be attached to parent-card, NOT child-text!
        expect(appearance.value.behaviorsFor('child-text'), isEmpty);
        expect(appearance.value.behaviorsFor('parent-card'), hasLength(1));
      },
    );

    testWidgets(
      'SuperListView row IterableContent has a distinct ID from the ListView',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final editing = ValueNotifier(true);
        addTearDown(editing.dispose);

        final appearance = ValueNotifier(
          Appearance(
            pageCatalog: EditorPageCatalog(
              pages: [
                EditorPageConfig(
                  id: 'item-details',
                  name: 'Détails Élément',
                  path: '/item-details',
                ),
              ],
            ),
          ),
        );
        addTearDown(appearance.dispose);

        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, _) => const Scaffold(
                body: Center(
                  child: SuperListView(
                    id: 'clients-list',
                    itemId: 'clients-row-item',
                    config: SuperListViewConfig(emptyText: 'Aucun client'),
                  ),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: StyleEditScope(
              controller: editing,
              child: MaterialApp.router(routerConfig: router),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check that IterableContent widget has the distinct id 'clients-row-item'
        final iterable = tester.widget<IterableContent>(
          find.byType(IterableContent),
        );
        expect(iterable.id, 'clients-row-item');
        expect(iterable.id, isNot('clients-list'));

        // Right-click on the IterableContent row
        await tester.tap(
          find.byType(IterableContent),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        // Tap on Comportement…
        await tester.tap(find.byKey(const ValueKey('style-menu-behavior')));
        await tester.pumpAndSettle();

        // Check that the wizard offers IterableContent with the exact id 'clients-row-item'
        expect(
          find.byKey(const ValueKey('behavior-target-clients-row-item')),
          findsOneWidget,
        );
        expect(find.text('ID : clients-row-item'), findsOneWidget);

        // Check that the parent list is offered with id 'clients-list'
        expect(
          find.byKey(const ValueKey('behavior-target-clients-list')),
          findsOneWidget,
        );
        expect(find.text('ID : clients-list'), findsOneWidget);
      },
    );
  });
}
