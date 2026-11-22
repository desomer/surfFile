import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

class _TestAppearanceCodec extends AppearanceCodec {
  const _TestAppearanceCodec(this._defaults);

  final Appearance _defaults;

  @override
  Appearance get defaults => _defaults;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final channels = [
    const MethodChannel('com.alexmercerind/flutter_acrylic'),
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

  DynamicFontManager testFontManager() => DynamicFontManager(
    useDefaultCacheDirectory: false,
    autoDownloadEnabled: false,
  );

  group('EditorPageType.sideSheet navigation, sizing & dismissal', () {
    testWidgets(
      'applies modalWidth, clamps to viewport, preserves root behind barrier, and closes via button, barrier and GoBackAction',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const SuperPage(
                  child: Center(child: Text('Root Underlying')),
                ),
              ),
            ],
          ),
        );
        addTearDown(routing.dispose);

        final catalog = EditorPageCatalog(
          pages: [
            EditorPageConfig(
              id: 'side-1',
              name: 'Détails latéraux',
              path: '/side',
              pageType: EditorPageType.sideSheet,
              modalWidth: 360,
            ),
            EditorPageConfig(
              id: 'side-wide',
              name: 'Panneau large',
              path: '/side-wide',
              pageType: EditorPageType.sideSheet,
              modalWidth: 900,
            ),
          ],
        );

        final appearance = Appearance(
          pageCatalog: catalog,
          components: {
            'side-1': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['side-layout'],
              },
              slotTypes: const {'side-layout': 'registry:Layout'},
            ),
            'side-layout': const SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: ['side-close-btn'],
              },
              slotTypes: {'side-close-btn': 'registry:Action'},
            ),
            'side-close-btn': const SuperActionConfig(
              label: 'Fermer via GoBack',
            ),
          },
          behaviors: {
            'side-close-btn': [
              ComponentBehavior(
                id: 'close-action',
                trigger: BehaviorTrigger.click,
                action: const GoBackAction(),
              ),
            ],
          },
        );

        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
            fontManager: testFontManager(),
            appearanceStore: AppearanceStore(
              codec: _TestAppearanceCodec(appearance),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Root Underlying'), findsOneWidget);

        // 1. Ouverture via openLocation -> push par-dessus '/'.
        routing.openLocation('/side');
        await tester.pumpAndSettle();

        final containerFinder = find.byKey(
          const ValueKey('editor-side-sheet-page-container'),
        );
        expect(containerFinder, findsOneWidget);
        expect(tester.getSize(containerFinder).width, 360);
        // La route racine reste présente dans l'arbre Navigator derrière le voile.
        expect(find.text('Root Underlying', skipOffstage: false), findsOneWidget);

        // 2. Fermeture par le bouton close.
        await tester.tap(find.byKey(const ValueKey('editor-modal-page-close')));
        await tester.pumpAndSettle();
        expect(containerFinder, findsNothing);
        expect(find.text('Root Underlying'), findsOneWidget);

        // 3. Fermeture par clic sur le backdrop (à gauche du panneau droit).
        routing.openLocation('/side');
        await tester.pumpAndSettle();
        expect(containerFinder, findsOneWidget);
        await tester.tapAt(const Offset(50, 400));
        await tester.pumpAndSettle();
        expect(containerFinder, findsNothing);

        // 4. Fermeture via GoBackAction déclenché dans le panneau.
        routing.openLocation('/side');
        await tester.pumpAndSettle();
        expect(containerFinder, findsOneWidget);
        await tester.tap(find.text('Fermer via GoBack'));
        await tester.pumpAndSettle();
        expect(containerFinder, findsNothing);
        expect(find.text('Root Underlying'), findsOneWidget);

        // 5. Clamping de modalWidth lorsque la fenêtre est plus étroite (500px).
        await tester.binding.setSurfaceSize(const Size(500, 700));
        await tester.pumpAndSettle();
        routing.openLocation('/side-wide');
        await tester.pumpAndSettle();
        expect(containerFinder, findsOneWidget);
        expect(tester.getSize(containerFinder).width, 500 - 32);
      },
    );

    testWidgets(
      'GoToPageAction opens sideSheet sharing Master/Detail selection and GoBackAction closes it',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repoDir = Directory.systemTemp.createTempSync('side_sheet_md_');
        addTearDown(() {
          if (repoDir.existsSync()) repoDir.deleteSync(recursive: true);
        });
        final repoStore = JsonRepositoryStore(repoDir);
        addTearDown(repoStore.dispose);
        repoStore.registerRepository(
          RepositoryImpl(
            id: 'items_repo',
            json: {
              'items': [
                {'title': 'Premier article', 'detail': 'Description alpha'},
                {'title': 'Deuxième article', 'detail': 'Description bêta'},
              ],
            },
          ),
        );

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => SuperPage(
                  id: 'root',
                  pageConfig: ScaffoldPageConfig(
                    placements: const {
                      ScaffoldPageRegion.body: ['master-layout'],
                    },
                    slotTypes: const {'master-layout': 'registry:Layout'},
                  ),
                ),
              ),
            ],
          ),
        );
        addTearDown(routing.dispose);

        final appearance = Appearance(
          pageCatalog: EditorPageCatalog(
            pages: [
              EditorPageConfig(
                id: 'detail-sheet',
                name: 'Fiche article',
                path: '/detail',
                pageType: EditorPageType.sideSheet,
                modalWidth: 440,
              ),
            ],
          ),
          components: {
            'master-layout': const SuperLayoutConfig(
              north: true,
              placements: {
                SuperLayoutZone.north: ['open-detail-btn'],
                SuperLayoutZone.center: ['items-list'],
              },
              slotTypes: {
                'open-detail-btn': 'registry:Action',
                'items-list': 'registry:ListView',
              },
            ),
            'open-detail-btn': const SuperActionConfig(
              label: 'Ouvrir fiche',
            ),
            'items-list': SuperListViewConfig(
              binding: const JsonTextBinding(
                repositoryId: 'items_repo',
                path: 'items',
              ),
              template: const SuperLayoutConfig(
                placements: {
                  SuperLayoutZone.center: ['row-title'],
                },
                slotTypes: {'row-title': 'registry:Value'},
              ),
            ),
            'row-title': const SuperValueConfig(
              binding: JsonTextBinding(path: 'items[?].title'),
            ),
            'detail-sheet': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['sheet-layout'],
              },
              slotTypes: const {'sheet-layout': 'registry:Layout'},
            ),
            'sheet-layout': const SuperLayoutConfig(
              south: true,
              placements: {
                SuperLayoutZone.center: ['detail-title', 'detail-desc'],
                SuperLayoutZone.south: ['sheet-back-btn'],
              },
              slotTypes: {
                'detail-title': 'registry:Value',
                'detail-desc': 'registry:Value',
                'sheet-back-btn': 'registry:Action',
              },
            ),
            'detail-title': const SuperValueConfig(
              binding: JsonTextBinding(
                repositoryId: 'items_repo',
                path: 'items[?].title',
              ),
            ),
            'detail-desc': const SuperValueConfig(
              binding: JsonTextBinding(
                repositoryId: 'items_repo',
                path: 'items[?].detail',
              ),
            ),
            'sheet-back-btn': const SuperActionConfig(label: 'Retour liste'),
          },
          behaviors: {
            'open-detail-btn': [
              ComponentBehavior(
                id: 'go-detail',
                trigger: BehaviorTrigger.click,
                action: const GoToPageAction(
                  pagePath: '/detail',
                  pageId: 'detail-sheet',
                ),
              ),
            ],
            'sheet-back-btn': [
              ComponentBehavior(
                id: 'back-list',
                trigger: BehaviorTrigger.click,
                action: const GoBackAction(),
              ),
            ],
          },
        );

        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
            repositoryStore: repoStore,
            fontManager: testFontManager(),
            appearanceStore: AppearanceStore(
              codec: _TestAppearanceCodec(appearance),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Sélectionne le 2e élément dans la liste maître.
        await tester.tap(find.text('Deuxième article'));
        await tester.pumpAndSettle();

        // Ouvre le panneau latéral via GoToPageAction.
        await tester.tap(find.text('Ouvrir fiche'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('editor-side-sheet-page-container')),
          findsOneWidget,
        );
        expect(find.text('Description bêta'), findsOneWidget);

        // Ferme le panneau via GoBackAction.
        await tester.tap(find.text('Retour liste'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-side-sheet-page-container')),
          findsNothing,
        );
        expect(find.text('Premier article'), findsOneWidget);
      },
    );
  });

  group('EditorPageManager & homePageId modal policy', () {
    test(
      'EditorPageRouter.validate rejects modal homePageId',
      () {
        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
          ),
        );
        addTearDown(routing.dispose);

        for (final modalType in [
          EditorPageType.dialog,
          EditorPageType.bottomSheet,
          EditorPageType.sideSheet,
        ]) {
          expect(
            () => routing.validate(
              EditorPageCatalog(
                homePageId: 'p',
                pages: [
                  EditorPageConfig(
                    id: 'p',
                    name: 'Modal',
                    path: '/modal',
                    pageType: modalType,
                  ),
                ],
              ),
            ),
            throwsFormatException,
          );
        }
      },
    );

    testWidgets(
      'EditorPageManager creates, opens via push, disables home on sideSheet, and clears homePageId when switching to sideSheet',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const SuperPage(
                  child: Center(child: Text('Coded Base')),
                ),
              ),
            ],
          ),
        );
        addTearDown(routing.dispose);

        final initial = Appearance(
          pageCatalog: EditorPageCatalog(
            homePageId: 'std-home',
            pages: [
              EditorPageConfig(
                id: 'std-home',
                name: 'Accueil Standard',
                path: '/accueil',
              ),
            ],
          ),
        );

        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
            fontManager: testFontManager(),
            appearanceStore: AppearanceStore(
              codec: _TestAppearanceCodec(initial),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ctx = tester.element(find.byType(SuperPage));
        final appearance = AppearanceScope.controllerOf(ctx)!;
        StyleEditScope.controllerOf(ctx)!.value = true;
        await tester.pumpAndSettle();

        // Ouvre le gestionnaire de pages.
        await tester.tap(find.byKey(const ValueKey('style-edit-banner-pages')));
        await tester.pumpAndSettle();

        // 1. Crée une page Panneau latéral avec largeur 390px.
        await tester.tap(find.byKey(const ValueKey('editor-pages-add')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-page-name')),
          'Inspecteur',
        );
        await tester.enterText(
          find.byKey(const ValueKey('editor-page-path')),
          '/inspecteur',
        );
        await tester.tap(
          find.byKey(const ValueKey('editor-page-type-sideSheet')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-page-modal-width')),
          '390',
        );
        await tester.tap(find.text('Valider'));
        await tester.pumpAndSettle();

        // Le bouton Page d'accueil sur la ligne du panneau latéral doit être désactivé.
        final inspecteurRow = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('editor-page-row-') &&
              w.key != const ValueKey('editor-page-row-std-home'),
        );
        final homeButton = tester.widget<IconButton>(
          find.descendant(
            of: inspecteurRow,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is IconButton &&
                  w.tooltip == 'Une page modale ne peut pas être page d’accueil',
            ),
          ),
        );
        expect(homeButton.onPressed, isNull);

        // 2. Ouvre le panneau latéral via le bouton « Ouvrir » du gestionnaire.
        await tester.tap(
          find.descendant(
            of: inspecteurRow,
            matching: find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Ouvrir',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Appliquer avant d’ouvrir ?'), findsOneWidget);
        await tester.tap(find.text('Appliquer et ouvrir'));
        await tester.pumpAndSettle();

        final sideContainer = find.byKey(
          const ValueKey('editor-side-sheet-page-container'),
        );
        expect(sideContainer, findsOneWidget);
        expect(tester.getSize(sideContainer).width, 390);
        // Fermer revient sur la page sous-jacente sans crash.
        await tester.tap(find.byKey(const ValueKey('editor-modal-page-close')));
        await tester.pumpAndSettle();
        expect(sideContainer, findsNothing);

        // 3. Basculer la page d'accueil actuelle vers sideSheet nettoie homePageId.
        await tester.tap(find.byKey(const ValueKey('style-edit-banner-pages')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('editor-page-row-std-home')),
            matching: find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Modifier',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('editor-page-type-sideSheet')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('le statut de page d’accueil sera retiré'),
          findsOneWidget,
        );
        await tester.tap(find.text('Valider'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Appliquer'));
        await tester.pumpAndSettle();

        expect(appearance.value.pageCatalog.homePageId, isNull);
        expect(
          appearance.value.pageCatalog.pages
              .firstWhere((p) => p.id == 'std-home')
              .pageType,
          EditorPageType.sideSheet,
        );
      },
    );

    testWidgets(
      'openLocation switches cleanly between modal pages over root',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const SuperPage(child: Text('Base')),
              ),
            ],
          ),
        );
        addTearDown(routing.dispose);

        final catalog = EditorPageCatalog(
          pages: [
            EditorPageConfig(
              id: 'dlg',
              name: 'Dialogue',
              path: '/dlg',
              pageType: EditorPageType.dialog,
            ),
            EditorPageConfig(
              id: 'side',
              name: 'Panneau',
              path: '/side',
              pageType: EditorPageType.sideSheet,
            ),
          ],
        );

        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
            fontManager: testFontManager(),
            appearanceStore: AppearanceStore(
              codec: _TestAppearanceCodec(Appearance(pageCatalog: catalog)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        routing.openLocation('/dlg');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-dialog-page-container')),
          findsOneWidget,
        );

        routing.openLocation('/side');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-dialog-page-container')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('editor-side-sheet-page-container')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('editor-modal-page-close')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-side-sheet-page-container')),
          findsNothing,
        );
        expect(find.text('Base'), findsOneWidget);
      },
    );
  });

  group('Edit mode, lazy loading, VibeAppInspector & SuperRenderer with sideSheet', () {
    testWidgets(
      'supports edit mode selection, adding a Card inside sideSheet, and undo/redo',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const SuperPage(child: Text('Base')),
              ),
            ],
          ),
        );
        addTearDown(routing.dispose);

        final appearance = Appearance(
          pageCatalog: EditorPageCatalog(
            pages: [
              EditorPageConfig(
                id: 'side-edit',
                name: 'Panneau Éditable',
                path: '/side-edit',
                pageType: EditorPageType.sideSheet,
                modalWidth: 420,
              ),
            ],
          ),
        );

        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
            fontManager: testFontManager(),
            appearanceStore: AppearanceStore(
              codec: _TestAppearanceCodec(appearance),
            ),
          ),
        );
        await tester.pumpAndSettle();

        routing.openLocation('/side-edit');
        await tester.pumpAndSettle();

        final sheetCtx = tester.element(
          find.byKey(const ValueKey('editor-page-side-edit')),
        );
        final controller = AppearanceScope.controllerOf(sheetCtx)!;
        final history = EditorHistoryScope.controllerOf(sheetCtx)!;
        StyleEditScope.controllerOf(sheetCtx)!.value = true;
        await tester.pumpAndSettle();

        LayoutSelection.select(['Panneau Éditable']);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('scaffold-page-add-body')));
        await tester.pumpAndSettle();
        final addCard = find.byKey(
          const ValueKey('scaffold-page-add-slot-factory:Card'),
        );
        await tester.ensureVisible(addCard);
        await tester.pumpAndSettle();
        await tester.tap(addCard);
        await tester.pumpAndSettle();

        expect(
          controller.value.nativeComponent('side-edit').slotsOf('body'),
          hasLength(1),
        );
        expect(history.canUndo, isTrue);
        history.undo();
        await tester.pumpAndSettle();
        expect(
          controller.value.nativeComponent('side-edit').slotsOf('body'),
          isEmpty,
        );
        history.redo();
        await tester.pumpAndSettle();
        expect(
          controller.value.nativeComponent('side-edit').slotsOf('body'),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PagedFileAppearanceStore loads sideSheet lazily on openLocation',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('paged_side_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final pagesDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}pages',
        );
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}appearance.json',
        );

        final seeded = Appearance(
          pageCatalog: EditorPageCatalog(
            homePageId: 'home-std',
            pages: [
              EditorPageConfig(
                id: 'home-std',
                name: 'Accueil',
                path: '/home',
              ),
              EditorPageConfig(
                id: 'side-lazy',
                name: 'Panneau Paresseux',
                path: '/side-lazy',
                pageType: EditorPageType.sideSheet,
                modalWidth: 360,
              ),
            ],
          ),
          components: {
            'home-std': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['val-home'],
              },
              slotTypes: const {'val-home': 'registry:Value'},
            ),
            'val-home': const SuperValueConfig(initialText: 'Accueil chargé'),
            'side-lazy': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['val-side'],
              },
              slotTypes: const {'val-side': 'registry:Value'},
            ),
            'val-side': const SuperValueConfig(
              initialText: 'Contenu panneau paresseux',
            ),
          },
        );
        await tester.runAsync(() async {
          await PagedFileAppearanceStore(
            file,
            pagesDirectory: pagesDir,
          ).save(seeded);
        });

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final store = PagedFileAppearanceStore(
          file,
          pagesDirectory: pagesDir,
          registry: registry,
        );
        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const SuperPage(child: Text('Coded')),
              ),
            ],
          ),
        );
        addTearDown(routing.dispose);

        await tester.runAsync(() async {
          await tester.pumpWidget(
            SuperApp(
              router: routing.router,
              pageRouting: routing,
              registry: registry,
              fontManager: testFontManager(),
              appearanceStore: store,
            ),
          );
          for (var i = 0; i < 20; i++) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();

        expect(store.isPageLoaded('home-std'), isTrue);
        expect(store.isPageLoaded('side-lazy'), isFalse);
        expect(find.text('Accueil chargé'), findsOneWidget);

        await tester.runAsync(() async {
          routing.openLocation('/side-lazy');
          for (var i = 0; i < 25; i++) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();

        expect(store.isPageLoaded('side-lazy'), isTrue);
        expect(
          find.byKey(const ValueKey('editor-side-sheet-page-container')),
          findsOneWidget,
        );
        expect(find.text('Contenu panneau paresseux'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('editor-modal-page-close')));
        await tester.pumpAndSettle();
        expect(find.text('Accueil chargé'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'VibeAppInspector detects pushed sideSheet, exposes modal metadata, and restores cleanly on rollback',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const SuperPage(child: Text('Root')),
              ),
            ],
          ),
        );
        addTearDown(routing.dispose);

        final appearance = Appearance(
          responsiveLayout: const ResponsiveLayoutConfig(
            containerMode: PageContainerMode.constrained,
            maxWidth: 1100,
          ),
          pageCatalog: EditorPageCatalog(
            homePageId: 'main-std',
            pages: [
              EditorPageConfig(
                id: 'main-std',
                name: 'Principal',
                path: '/main',
              ),
              EditorPageConfig(
                id: 'side-vibe',
                name: 'Volet Vibe',
                path: '/volet',
                pageType: EditorPageType.sideSheet,
                modalWidth: 410,
              ),
            ],
          ),
          components: {
            'main-std': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['main-val'],
              },
              slotTypes: const {'main-val': 'registry:Value'},
            ),
            'main-val': const SuperValueConfig(initialText: 'Page Principale'),
            'side-vibe': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['side-val'],
              },
              slotTypes: const {'side-val': 'registry:Value'},
            ),
            'side-val': const SuperValueConfig(initialText: 'Contenu Volet'),
          },
        );

        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
            fontManager: testFontManager(),
            appearanceStore: AppearanceStore(
              codec: _TestAppearanceCodec(appearance),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ctx = tester.element(find.byType(SuperPage));
        final controller = AppearanceScope.controllerOf(ctx)!;
        final tracker = VibePreviewStateTracker();
        final inspector = VibeAppInspector(
          readAppearance: () => controller.value,
          registry: registry,
          pageRouting: routing,
          previewTracker: tracker,
        );

        final previewRes = await inspector.previewNavigationOrSelection(
          'call-1',
          'preview_navigation_or_selection',
          const {'pageId': 'side-vibe'},
        );
        expect(previewRes.isError, isFalse);
        await tester.pumpAndSettle();

        expect(tracker.hasNavigated, isTrue);
        expect(
          find.byKey(const ValueKey('editor-side-sheet-page-container')),
          findsOneWidget,
        );
        expect(find.text('Contenu Volet'), findsOneWidget);

        expect(inspector.resolveActivePage(controller.value)?.id, 'side-vibe');
        final viewport = await inspector.getViewportAndRoute();
        final route = viewport['route']! as Map<String, Object?>;
        final activePage = route['activePage']! as Map<String, Object?>;
        final responsive = viewport['responsive']! as Map<String, Object?>;
        expect(route['location'], '/volet');
        expect(activePage['id'], 'side-vibe');
        expect(activePage['pageType'], 'sideSheet');
        expect(activePage['isModal'], isTrue);
        expect(activePage['modalWidth'], 410);
        expect(responsive['containerMode'], 'fullPage');

        // Rollback dépile le panneau latéral et revient sur /main intact.
        routing.restoreLocation('/main');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-side-sheet-page-container')),
          findsNothing,
        );
        expect(find.text('Page Principale'), findsOneWidget);
        expect(inspector.resolveActivePage(controller.value)?.id, 'main-std');
      },
    );

    testWidgets(
      'SuperRenderer renders sideSheet page as a side sheet modal over root page',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final sourceAppearance = Appearance(
          pageCatalog: EditorPageCatalog(
            homePageId: 'home-r',
            pages: [
              EditorPageConfig(
                id: 'home-r',
                name: 'Accueil Renderer',
                path: '/home-r',
              ),
              EditorPageConfig(
                id: 'side-r',
                name: 'Panneau Renderer',
                path: '/side-r',
                pageType: EditorPageType.sideSheet,
                modalWidth: 340,
              ),
            ],
          ),
          components: {
            'home-r': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['btn-open-r'],
              },
              slotTypes: const {'btn-open-r': 'registry:Action'},
            ),
            'btn-open-r': const SuperActionConfig(label: 'Ouvrir panneau R'),
            'side-r': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['val-side-r'],
              },
              slotTypes: const {'val-side-r': 'registry:Value'},
            ),
            'val-side-r': const SuperValueConfig(
              initialText: 'Dans SuperRenderer',
            ),
          },
          behaviors: {
            'btn-open-r': [
              ComponentBehavior(
                id: 'nav-side-r',
                trigger: BehaviorTrigger.click,
                action: const GoToPageAction(
                  pagePath: '/side-r',
                  pageId: 'side-r',
                ),
              ),
            ],
          },
        );

        final exported = AppearanceTransfer.export(
          sourceAppearance,
          {...TransferGroup.values},
        );
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                body: SuperRenderer(source: exported, rootId: 'home-r'),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          SuperApp(
            router: router,
            registry: Registry()..bootstrap(),
            fontManager: testFontManager(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Ouvrir panneau R'));
        await tester.pumpAndSettle();

        final sheetFinder = find.byKey(
          const ValueKey('editor-side-sheet-page-container'),
        );
        expect(sheetFinder, findsOneWidget);
        expect(tester.getSize(sheetFinder).width, 340);
        expect(find.text('Dans SuperRenderer'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('editor-modal-page-close')));
        await tester.pumpAndSettle();
        expect(sheetFinder, findsNothing);
        expect(find.text('Ouvrir panneau R'), findsOneWidget);
        expect(jsonDecode(exported), isA<Map<String, dynamic>>());
      },
    );
  });
}
