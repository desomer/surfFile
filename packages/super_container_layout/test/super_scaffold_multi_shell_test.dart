import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/components/native/scaffold_page_layout.dart';

class _MemoryAppearanceStore extends AppearanceStore {
  _MemoryAppearanceStore(this.initial);

  final Appearance initial;

  @override
  Future<Appearance> load() async => initial;

  @override
  Future<void> save(Appearance appearance) async {}
}

DynamicFontManager _noopFontManager() => DynamicFontManager(
  useDefaultCacheDirectory: false,
  autoDownloadEnabled: false,
);

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

  // ---------------------------------------------------------------------------
  // 1. Serialization & Codec
  // ---------------------------------------------------------------------------
  group('Serialization & Codec', () {
    test(
      'ScaffoldPageConfig roundtrips sidebars, headerSpan, widths and omits defaults in toCompactJson',
      () {
        final full = ScaffoldPageConfig(
          regions: const {
            ScaffoldPageRegion.appBar: true,
            ScaffoldPageRegion.sidebarStart: true,
            ScaffoldPageRegion.sidebarEnd: true,
            ScaffoldPageRegion.body: true,
          },
          placements: const {
            ScaffoldPageRegion.appBar: ['shell-appbar'],
            ScaffoldPageRegion.sidebarStart: ['shell-rail'],
            ScaffoldPageRegion.sidebarEnd: ['shell-inspector'],
            ScaffoldPageRegion.body: ['scaffold:outlet'],
          },
          slotTypes: const {
            'shell-appbar': 'registry:ApplicationBar',
            'shell-rail': 'registry:NavigationRail',
            'shell-inspector': 'registry:Layout',
            'scaffold:outlet': 'scaffold:outlet',
          },
          headerSpan: ScaffoldHeaderSpan.contentOnly,
          sidebarStartWidth: 220,
          sidebarEndWidth: 320,
          responsiveSidebarToDrawer: true,
        );

        final json = full.toJson();
        final decoded = ScaffoldPageConfig.fromJson(json);
        expect(decoded, full);
        expect(decoded.headerSpan, ScaffoldHeaderSpan.contentOnly);
        expect(decoded.sidebarStartWidth, 220);
        expect(decoded.sidebarEndWidth, 320);
        expect(decoded.responsiveSidebarToDrawer, isTrue);
        expect(decoded.slotsOf(ScaffoldPageRegion.sidebarStart), ['shell-rail']);
        expect(decoded.slotsOf(ScaffoldPageRegion.sidebarEnd), [
          'shell-inspector',
        ]);

        final compact = full.toCompactJson();
        expect(compact['headerSpan'], 'contentOnly');
        expect(compact['sidebarStartWidth'], 220);
        expect(compact['sidebarEndWidth'], 320);
        expect(compact['responsiveSidebarToDrawer'], isTrue);
        expect(compact.containsKey('bodyMode'), isFalse);

        // Default values are omitted by toCompactJson().
        final defaults = ScaffoldPageConfig(
          headerSpan: ScaffoldHeaderSpan.fullWidth,
          bodyMode: ScaffoldBodyMode.standard,
          responsiveSidebarToDrawer: false,
        );
        final compactDefaults = defaults.toCompactJson();
        expect(compactDefaults.containsKey('headerSpan'), isFalse);
        expect(compactDefaults.containsKey('bodyMode'), isFalse);
        expect(compactDefaults.containsKey('responsiveSidebarToDrawer'), isFalse);

        // Invalid sidebar widths are rejected in constructor and fromJson.
        for (final invalid in [0.0, -10.0, 47.9, 2000.1, double.nan, double.infinity]) {
          expect(
            () => ScaffoldPageConfig(sidebarStartWidth: invalid),
            throwsArgumentError,
          );
          expect(
            () => ScaffoldPageConfig(sidebarEndWidth: invalid),
            throwsArgumentError,
          );
          if (invalid.isFinite) {
            expect(
              () => ScaffoldPageConfig.fromJson({
                'properties': {'sidebarStartWidth': invalid},
              }),
              throwsFormatException,
            );
            expect(
              () => ScaffoldPageConfig.fromJson({
                'properties': {'sidebarEndWidth': invalid},
              }),
              throwsFormatException,
            );
          }
        }
      },
    );

    test(
      'superScaffold alias decodes via ComponentConfig/AppearanceCodec and patches across scaffold/superScaffold/native',
      () {
        final decodedComp = ComponentConfig.fromJson({
          'type': 'superScaffold',
          'headerSpan': 'contentOnly',
          'sidebarStartWidth': 240,
          'responsiveSidebarToDrawer': true,
          'placements': {
            'body': [
              {'id': 'scaffold:outlet', 'type': 'scaffold:outlet'},
            ],
            'sidebarStart': [
              {'id': 'nav-rail', 'type': 'NavigationRail'},
            ],
          },
        });
        expect(decodedComp, isA<ScaffoldPageConfig>());
        final scaffold = decodedComp as ScaffoldPageConfig;
        expect(scaffold.headerSpan, ScaffoldHeaderSpan.contentOnly);
        expect(scaffold.sidebarStartWidth, 240);
        expect(scaffold.responsiveSidebarToDrawer, isTrue);
        expect(scaffold.slotsOf(ScaffoldPageRegion.sidebarStart), ['nav-rail']);

        final codec = AppearanceCodec();
        final base = codec.fromJson({
          'version': codec.schemaVersion,
          'components': {
            'main-shell': {
              'type': 'superScaffold',
              'sidebarStartWidth': 200,
              'placements': {
                'appBar': [
                  {'id': 'bar-1', 'type': 'AppBar'},
                ],
                'body': [
                  {'id': 'scaffold:outlet', 'type': 'scaffold:outlet'},
                ],
              },
            },
            'legacy-native-shell': {
              'type': 'native',
              'placements': {
                'body': [
                  {'id': 'scaffold:outlet', 'type': 'scaffold:outlet'},
                ],
              },
            },
          },
        });
        expect(base.components['main-shell'], isA<ScaffoldPageConfig>());
        expect(
          (base.components['main-shell'] as ScaffoldPageConfig)
              .sidebarStartWidth,
          200,
        );

        // Patch a scaffold created with "superScaffold" using "scaffold" type.
        final patched1 = codec.patchFromJson(base, {
          'components': {
            'main-shell': {
              'type': 'scaffold',
              'headerSpan': 'contentOnly',
              'sidebarEndWidth': 300,
            },
          },
        });
        final patchedShell1 =
            patched1.components['main-shell'] as ScaffoldPageConfig;
        expect(patchedShell1.headerSpan, ScaffoldHeaderSpan.contentOnly);
        expect(patchedShell1.sidebarStartWidth, 200);
        expect(patchedShell1.sidebarEndWidth, 300);
        expect(patchedShell1.slotsOf(ScaffoldPageRegion.appBar), ['bar-1']);

        // Patch back using "superScaffold" and upgrade a "native" component to "superScaffold".
        final patched2 = codec.patchFromJson(patched1, {
          'components': {
            'main-shell': {
              'type': 'superScaffold',
              'responsiveSidebarToDrawer': true,
            },
            'legacy-native-shell': {
              'type': 'superScaffold',
              'sidebarStartWidth': 250,
            },
          },
        });
        final patchedShell2 =
            patched2.components['main-shell'] as ScaffoldPageConfig;
        expect(patchedShell2.headerSpan, ScaffoldHeaderSpan.contentOnly);
        expect(patchedShell2.responsiveSidebarToDrawer, isTrue);
        expect(patchedShell2.sidebarStartWidth, 200);

        final upgradedNative = patched2.components['legacy-native-shell'];
        expect(upgradedNative, isA<ScaffoldPageConfig>());
        expect(
          (upgradedNative as ScaffoldPageConfig).sidebarStartWidth,
          250,
        );
        expect(upgradedNative.slotsOf(ScaffoldPageRegion.body), [
          'scaffold:outlet',
        ]);
      },
    );

    test(
      'EditorPageCatalog supports multiple shells, rootShellId, rejects modal shellId, and patchFromJson preserves shells/rootShellId',
      () {
        final catalog = EditorPageCatalog(
          shells: [
            EditorShellConfig(id: 'main-shell', name: 'Principal'),
            EditorShellConfig(id: 'admin-shell', name: 'Administration'),
          ],
          rootShellId: 'main-shell',
          pages: [
            EditorPageConfig(
              id: 'clients',
              name: 'Clients',
              path: '/clients',
              shellId: 'main-shell',
            ),
            EditorPageConfig(
              id: 'admin-users',
              name: 'Utilisateurs',
              path: '/admin/users',
              shellId: 'admin-shell',
            ),
            EditorPageConfig(id: 'login', name: 'Connexion', path: '/login'),
          ],
        );

        final decoded = EditorPageCatalog.fromJson(catalog.toJson());
        expect(decoded, catalog);
        expect(decoded.shells, hasLength(2));
        expect(decoded.rootShellId, 'main-shell');
        expect(decoded.pages.first.shellId, 'main-shell');

        // Modal pages must reject shellId.
        for (final modalType in [
          EditorPageType.dialog,
          EditorPageType.bottomSheet,
          EditorPageType.sideSheet,
        ]) {
          expect(
            () => EditorPageConfig(
              id: 'm1',
              name: 'Modal',
              path: '/modal',
              pageType: modalType,
              shellId: 'main-shell',
            ),
            throwsArgumentError,
          );
          expect(
            () => EditorPageConfig.fromJson({
              'id': 'm1',
              'name': 'Modal',
              'path': '/modal',
              'pageType': modalType.name,
              'shellId': 'main-shell',
            }),
            throwsFormatException,
          );
        }

        // Incremental patchFromJson updating only pages preserves shells & rootShellId.
        final patchedCatalog = catalog.patchFromJson({
          'pages': [
            {
              'id': 'clients',
              'name': 'Clients',
              'path': '/clients',
              'shellId': 'main-shell',
            },
            {
              'id': 'factures',
              'name': 'Factures',
              'path': '/factures',
              'shellId': 'main-shell',
            },
          ],
        });
        expect(patchedCatalog.shells, catalog.shells);
        expect(patchedCatalog.rootShellId, 'main-shell');
        expect(patchedCatalog.pages.map((p) => p.id), ['clients', 'factures']);

        // Also verified through AppearanceCodec.patchFromJson.
        final codec = AppearanceCodec();
        final baseApp = Appearance(pageCatalog: catalog);
        final patchedApp = codec.patchFromJson(baseApp, {
          'pageCatalog': {
            'pages': [
              {
                'id': 'clients',
                'name': 'Clients',
                'path': '/clients',
                'shellId': 'main-shell',
              },
            ],
          },
        });
        expect(patchedApp.pageCatalog.shells, catalog.shells);
        expect(patchedApp.pageCatalog.rootShellId, 'main-shell');
        expect(patchedApp.pageCatalog.pages.map((p) => p.id), ['clients']);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 2. Widget Rendering (ScaffoldPageLayout / SuperScaffold)
  // ---------------------------------------------------------------------------
  group('SuperScaffold / ScaffoldPageLayout rendering', () {
    Future<void> pumpScaffold(
      WidgetTester tester, {
      required Size viewport,
      required ScaffoldHeaderSpan headerSpan,
      bool responsiveSidebarToDrawer = false,
      double sidebarStartWidth = 220,
      double sidebarEndWidth = 260,
    }) async {
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: SuperScaffold(
            id: 'test-shell',
            appBar: AppBar(
              key: const ValueKey('test-appbar'),
              title: const Text('Shell Header'),
            ),
            sidebarStart: const ColoredBox(
              key: ValueKey('test-sidebar-start'),
              color: Color(0xFF223344),
              child: Center(child: Text('Sidebar Start')),
            ),
            sidebarEnd: const ColoredBox(
              key: ValueKey('test-sidebar-end'),
              color: Color(0xFF443322),
              child: Center(child: Text('Sidebar End')),
            ),
            outlet: const Center(
              key: ValueKey('test-outlet'),
              child: Text('Outlet Body'),
            ),
            headerSpan: headerSpan,
            sidebarStartWidth: sidebarStartWidth,
            sidebarEndWidth: sidebarEndWidth,
            responsiveSidebarToDrawer: responsiveSidebarToDrawer,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'renders sidebarStart, sidebarEnd, appBar and outlet in fullWidth and contentOnly headerSpan',
      (tester) async {
        // fullWidth: AppBar spans full viewport width above both sidebars.
        await pumpScaffold(
          tester,
          viewport: const Size(1280, 800),
          headerSpan: ScaffoldHeaderSpan.fullWidth,
        );

        expect(find.text('Shell Header'), findsOneWidget);
        expect(find.text('Sidebar Start'), findsOneWidget);
        expect(find.text('Sidebar End'), findsOneWidget);
        expect(find.text('Outlet Body'), findsOneWidget);

        final fullAppBar = tester.getRect(
          find.byKey(const ValueKey('test-appbar')),
        );
        final fullStart = tester.getRect(
          find.byKey(const ValueKey('test-sidebar-start')),
        );
        final fullEnd = tester.getRect(
          find.byKey(const ValueKey('test-sidebar-end')),
        );
        final fullOutlet = tester.getRect(
          find.byKey(const ValueKey('test-outlet')),
        );

        expect(fullAppBar.left, closeTo(0, 0.5));
        expect(fullAppBar.width, closeTo(1280, 0.5));
        expect(fullStart.top, greaterThanOrEqualTo(fullAppBar.bottom - 0.5));
        expect(fullStart.width, closeTo(220, 0.5));
        expect(fullEnd.top, greaterThanOrEqualTo(fullAppBar.bottom - 0.5));
        expect(fullEnd.width, closeTo(260, 0.5));
        expect(fullOutlet.left, greaterThanOrEqualTo(fullStart.right - 0.5));
        expect(fullOutlet.right, lessThanOrEqualTo(fullEnd.left + 0.5));

        // contentOnly: sidebars run full height from top; AppBar sits between them.
        await pumpScaffold(
          tester,
          viewport: const Size(1280, 800),
          headerSpan: ScaffoldHeaderSpan.contentOnly,
        );

        final contentAppBar = tester.getRect(
          find.byKey(const ValueKey('test-appbar')),
        );
        final contentStart = tester.getRect(
          find.byKey(const ValueKey('test-sidebar-start')),
        );
        final contentEnd = tester.getRect(
          find.byKey(const ValueKey('test-sidebar-end')),
        );
        final contentOutlet = tester.getRect(
          find.byKey(const ValueKey('test-outlet')),
        );

        expect(contentStart.top, closeTo(0, 0.5));
        expect(contentStart.height, closeTo(800, 0.5));
        expect(contentEnd.top, closeTo(0, 0.5));
        expect(contentEnd.height, closeTo(800, 0.5));
        expect(contentAppBar.left, closeTo(220, 0.5));
        expect(contentAppBar.right, closeTo(1280 - 260, 0.5));
        expect(contentOutlet.top, greaterThanOrEqualTo(contentAppBar.bottom - 0.5));
      },
    );

    testWidgets(
      'responsiveSidebarToDrawer keeps sidebarStart docked on desktop and folds it into Drawer on mobile',
      (tester) async {
        // Desktop width (>= tabletMinWidth 600): docked sidebarStart, no drawer.
        await pumpScaffold(
          tester,
          viewport: const Size(1280, 800),
          headerSpan: ScaffoldHeaderSpan.fullWidth,
          responsiveSidebarToDrawer: true,
        );
        expect(find.text('Sidebar Start'), findsOneWidget);
        final desktopScaffold = tester.state<ScaffoldState>(
          find.byType(Scaffold),
        );
        expect(desktopScaffold.hasDrawer, isFalse);

        // Mobile width (< tabletMinWidth 600): sidebarStart folded into Drawer.
        await pumpScaffold(
          tester,
          viewport: const Size(500, 800),
          headerSpan: ScaffoldHeaderSpan.fullWidth,
          responsiveSidebarToDrawer: true,
          sidebarEndWidth: 100,
        );
        expect(find.text('Sidebar Start'), findsNothing);
        final mobileScaffold = tester.state<ScaffoldState>(
          find.byType(Scaffold),
        );
        expect(mobileScaffold.hasDrawer, isTrue);

        mobileScaffold.openDrawer();
        await tester.pumpAndSettle();
        expect(find.byType(Drawer), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Drawer),
            matching: find.text('Sidebar Start'),
          ),
          findsOneWidget,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 3. Multi-shell EditorPageRouter + Active Route Sync + GoToPageAction
  // ---------------------------------------------------------------------------
  group('Multi-shell EditorPageRouter & active route sync', () {
    const unselectedBg = Color(0xFF333333);
    const selectedBg = Color(0xFF00AA66);

    Appearance buildMultiShellAppearance() {
      return Appearance(
        pageCatalog: EditorPageCatalog(
          shells: [
            EditorShellConfig(id: 'main-shell', name: 'Navigation principale'),
            EditorShellConfig(id: 'admin-shell', name: 'Administration'),
          ],
          rootShellId: 'main-shell',
          pages: [
            EditorPageConfig(
              id: 'page-clients',
              name: 'Clients',
              path: '/clients',
              shellId: 'main-shell',
            ),
            EditorPageConfig(
              id: 'page-factures',
              name: 'Factures',
              path: '/factures',
              shellId: 'main-shell',
            ),
            EditorPageConfig(
              id: 'page-admin-users',
              name: 'Utilisateurs',
              path: '/admin/users',
              shellId: 'admin-shell',
            ),
            EditorPageConfig(
              id: 'page-login',
              name: 'Connexion',
              path: '/login',
            ),
            EditorPageConfig(
              id: 'legacy-layout',
              name: 'Legacy Layout',
              path: '/legacy-layout',
            ),
          ],
        ),
        components: {
          // Main shell with AppBar (containing a GoToPageAction SuperAction),
          // sidebarStart (NavigationRail), bottomNavigationBar, and outlet.
          'main-shell': ScaffoldPageConfig(
            regions: const {
              ScaffoldPageRegion.appBar: true,
              ScaffoldPageRegion.sidebarStart: true,
              ScaffoldPageRegion.bottomNavigationBar: true,
              ScaffoldPageRegion.body: true,
            },
            placements: const {
              ScaffoldPageRegion.appBar: ['main-appbar'],
              ScaffoldPageRegion.sidebarStart: ['main-rail'],
              ScaffoldPageRegion.bottomNavigationBar: ['main-bottom-nav'],
              ScaffoldPageRegion.body: ['scaffold:outlet'],
            },
            slotTypes: const {
              'main-appbar': 'registry:ApplicationBar',
              'main-rail': 'registry:NavigationRail',
              'main-bottom-nav': 'registry:BottomNavigationBar',
              'scaffold:outlet': 'scaffold:outlet',
            },
            sidebarStartWidth: 96,
          ),
          'main-appbar': NativeComponentConfig(
            regions: const {'title': true, 'actions': true},
            placements: const {
              'title': ['main-appbar-title'],
              'actions': ['topbar-clients-btn'],
            },
            slotTypes: const {
              'main-appbar-title': 'registry:Value',
              'topbar-clients-btn': 'registry:Action',
            },
          ),
          'main-appbar-title': const SuperValueConfig(initialText: 'Main App'),
          'topbar-clients-btn': SuperActionConfig(
            label: 'Raccourci Clients',
            variant: SuperActionVariant.filled,
            backgroundColor: unselectedBg,
            states: ActionConfigStates(
              selected: ActionConfigOverride(
                config: const SuperActionConfig(backgroundColor: selectedBg),
                properties: const {ActionStateProperty.backgroundColor},
              ),
            ),
          ),
          'main-rail': NativeComponentConfig(
            regions: const {'destinations': true},
            placements: const {
              'destinations': ['rail-home', 'rail-clients', 'rail-factures'],
            },
            slotTypes: const {
              'rail-home': 'registry:Action',
              'rail-clients': 'registry:Action',
              'rail-factures': 'registry:Action',
            },
          ),
          'rail-home': const SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            label: 'Accueil',
            icon: 'home',
          ),
          'rail-clients': const SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            label: 'Clients',
            icon: 'people',
          ),
          'rail-factures': const SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            label: 'Factures',
            icon: 'receipt',
          ),
          'main-bottom-nav': NativeComponentConfig(
            properties: const {'height': 64.0},
            regions: const {'destinations': true},
            placements: const {
              'destinations': ['bot-home', 'bot-clients', 'bot-factures'],
            },
            slotTypes: const {
              'bot-home': 'registry:Action',
              'bot-clients': 'registry:Action',
              'bot-factures': 'registry:Action',
            },
          ),
          'bot-home': const SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            label: 'Accueil',
            icon: 'home',
          ),
          'bot-clients': const SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            label: 'Clients',
            icon: 'people',
          ),
          'bot-factures': const SuperActionConfig(
            kind: SuperActionKind.textAndIcon,
            label: 'Factures',
            icon: 'receipt',
          ),

          // Direct layout pages inside main-shell.
          'page-clients': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['clients-title'],
            },
            slotTypes: {'clients-title': 'registry:Value'},
          ),
          'clients-title': const SuperValueConfig(
            initialText: 'Ecran Clients',
          ),
          'page-factures': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['factures-title'],
            },
            slotTypes: {'factures-title': 'registry:Value'},
          ),
          'factures-title': const SuperValueConfig(
            initialText: 'Ecran Factures',
          ),

          // Admin shell + page.
          'admin-shell': ScaffoldPageConfig(
            regions: const {
              ScaffoldPageRegion.appBar: true,
              ScaffoldPageRegion.body: true,
            },
            placements: const {
              ScaffoldPageRegion.appBar: ['admin-appbar'],
              ScaffoldPageRegion.body: ['scaffold:outlet'],
            },
            slotTypes: const {
              'admin-appbar': 'registry:ApplicationBar',
              'scaffold:outlet': 'scaffold:outlet',
            },
          ),
          'admin-appbar': NativeComponentConfig(
            regions: const {'title': true},
            placements: const {
              'title': ['admin-appbar-title'],
            },
            slotTypes: const {'admin-appbar-title': 'registry:Value'},
          ),
          'admin-appbar-title': const SuperValueConfig(
            initialText: 'Espace Admin',
          ),
          'page-admin-users': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['admin-users-title'],
            },
            slotTypes: {'admin-users-title': 'registry:Value'},
          ),
          'admin-users-title': const SuperValueConfig(
            initialText: 'Liste Utilisateurs Admin',
          ),

          // Standalone login page with its own Scaffold.
          'page-login': ScaffoldPageConfig(
            placements: const {
              ScaffoldPageRegion.body: ['login-title'],
            },
            slotTypes: const {'login-title': 'registry:Value'},
          ),
          'login-title': const SuperValueConfig(
            initialText: 'Page Connexion Autonome',
          ),

          // Standalone page whose root component is directly a SuperLayoutConfig
          // (AI tolerance / non-blank render).
          'legacy-layout': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['legacy-title'],
            },
            slotTypes: {'legacy-title': 'registry:Value'},
          ),
          'legacy-title': const SuperValueConfig(
            initialText: 'Contenu Legacy Layout',
          ),
        },
        behaviors: {
          'topbar-clients-btn': [
            ComponentBehavior(
              id: 'go-clients-topbar',
              action: GoToPageAction(pagePath: '/clients', pageId: 'page-clients'),
            ),
          ],
          'rail-home': [
            ComponentBehavior(
              id: 'go-home-rail',
              action: GoToPageAction(pagePath: '/'),
            ),
          ],
          'rail-clients': [
            ComponentBehavior(
              id: 'go-clients-rail',
              action: GoToPageAction(pagePath: '/clients', pageId: 'page-clients'),
            ),
          ],
          'rail-factures': [
            ComponentBehavior(
              id: 'go-factures-rail',
              action: GoToPageAction(
                pagePath: '/factures',
                pageId: 'page-factures',
              ),
            ),
          ],
          'bot-home': [
            ComponentBehavior(
              id: 'go-home-bot',
              action: GoToPageAction(pagePath: '/'),
            ),
          ],
          'bot-clients': [
            ComponentBehavior(
              id: 'go-clients-bot',
              action: GoToPageAction(pagePath: '/clients', pageId: 'page-clients'),
            ),
          ],
          'bot-factures': [
            ComponentBehavior(
              id: 'go-factures-bot',
              action: GoToPageAction(
                pagePath: '/factures',
                pageId: 'page-factures',
              ),
            ),
          ],
        },
      );
    }

    Color? topbarClientsButtonBackground(WidgetTester tester) {
      final actionFinder = find.byWidgetPredicate(
        (w) => w is SuperAction && w.id == 'topbar-clients-btn',
      );
      expect(actionFinder, findsOneWidget);
      final buttonFinder = find.descendant(
        of: actionFinder,
        matching: find.byType(FilledButton),
      );
      expect(buttonFinder, findsOneWidget);
      final button = tester.widget<FilledButton>(buttonFinder);
      return button.style?.backgroundColor?.resolve(const <WidgetState>{});
    }

    testWidgets(
      'preserves main-shell state across / -> /clients -> /factures, syncs rail/bottomNav/SuperAction, switches shells and renders direct layout standalone page',
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
                  child: Center(child: Text('Accueil Hote')),
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
            registry: registry,
            appearanceStore: _MemoryAppearanceStore(
              buildMultiShellAppearance(),
            ),
            fontManager: _noopFontManager(),
          ),
        );
        await tester.pumpAndSettle();

        // At "/": main-shell is mounted with root content inside outlet.
        expect(
          find.byKey(const ValueKey('editor-shell-main-shell')),
          findsOneWidget,
        );
        expect(find.text('Main App'), findsOneWidget);
        expect(find.text('Accueil Hote'), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
        expect(
          tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
          0,
        );
        expect(
          tester
              .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
              .currentIndex,
          0,
        );
        expect(topbarClientsButtonBackground(tester), unselectedBg);

        // Capture live State instances of the shell chrome.
        final shellLayoutState0 = tester.state(
          find.descendant(
            of: find.byKey(const ValueKey('editor-shell-main-shell')),
            matching: find.byType(ScaffoldPageLayout),
          ),
        );
        final appBarState0 = tester.state(find.byType(SuperAppBar));
        final railState0 = tester.state(find.byType(SuperNavigationRail));

        // Navigate "/" -> "/clients" via the SuperAction GoToPageAction button.
        await tester.tap(find.text('Raccourci Clients'));
        await tester.pumpAndSettle();

        expect(routing.currentUri.path, '/clients');
        expect(find.text('Ecran Clients'), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
        expect(
          tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
          1,
        );
        expect(
          tester
              .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
              .currentIndex,
          1,
        );
        expect(topbarClientsButtonBackground(tester), selectedBg);

        // Shell chrome states were NOT unmounted/remounted!
        expect(
          identical(
            shellLayoutState0,
            tester.state(
              find.descendant(
                of: find.byKey(const ValueKey('editor-shell-main-shell')),
                matching: find.byType(ScaffoldPageLayout),
              ),
            ),
          ),
          isTrue,
        );
        expect(
          identical(appBarState0, tester.state(find.byType(SuperAppBar))),
          isTrue,
        );
        expect(
          identical(railState0, tester.state(find.byType(SuperNavigationRail))),
          isTrue,
        );

        // Navigate "/clients" -> "/factures" via the NavigationRail destination.
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text('Factures'),
          ),
        );
        await tester.pumpAndSettle();

        expect(routing.currentUri.path, '/factures');
        expect(find.text('Ecran Factures'), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
        expect(
          tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
          2,
        );
        expect(
          tester
              .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
              .currentIndex,
          2,
        );
        expect(topbarClientsButtonBackground(tester), unselectedBg);

        // Shell chrome states are still the exact same mounted instances.
        expect(
          identical(
            shellLayoutState0,
            tester.state(
              find.descendant(
                of: find.byKey(const ValueKey('editor-shell-main-shell')),
                matching: find.byType(ScaffoldPageLayout),
              ),
            ),
          ),
          isTrue,
        );
        expect(
          identical(appBarState0, tester.state(find.byType(SuperAppBar))),
          isTrue,
        );
        expect(
          identical(railState0, tester.state(find.byType(SuperNavigationRail))),
          isTrue,
        );

        // Navigate "/factures" -> "/login": exits main-shell cleanly.
        routing.router.go('/login');
        await tester.pumpAndSettle();

        expect(routing.currentUri.path, '/login');
        expect(find.text('Page Connexion Autonome'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('editor-shell-main-shell')),
          findsNothing,
        );
        expect(find.byType(NavigationRail), findsNothing);
        expect(find.text('Main App'), findsNothing);

        // Navigate "/login" -> "/admin/users": mounts admin-shell.
        routing.router.go('/admin/users');
        await tester.pumpAndSettle();

        expect(routing.currentUri.path, '/admin/users');
        expect(
          find.byKey(const ValueKey('editor-shell-admin-shell')),
          findsOneWidget,
        );
        expect(find.text('Espace Admin'), findsOneWidget);
        expect(find.text('Liste Utilisateurs Admin'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('editor-shell-main-shell')),
          findsNothing,
        );

        // Navigate "/admin/users" -> "/legacy-layout": renders standalone direct SuperLayoutConfig.
        routing.router.go('/legacy-layout');
        await tester.pumpAndSettle();

        expect(routing.currentUri.path, '/legacy-layout');
        expect(
          find.byKey(const ValueKey('editor-shell-admin-shell')),
          findsNothing,
        );
        expect(find.text('Contenu Legacy Layout'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 4. Graph, Detachment, Persistence & Codegen
  // ---------------------------------------------------------------------------
  group('EditorPageGraph, PagedFileAppearanceStore & DartCodeExporter', () {
    Appearance buildShellGraphAppearance() {
      return Appearance(
        pageCatalog: EditorPageCatalog(
          shells: [
            EditorShellConfig(id: 'main-shell', name: 'Shell Principal'),
          ],
          rootShellId: 'main-shell',
          pages: [
            EditorPageConfig(
              id: 'page-clients',
              name: 'Clients',
              path: '/clients',
              shellId: 'main-shell',
            ),
            EditorPageConfig(
              id: 'page-factures',
              name: 'Factures',
              path: '/factures',
              shellId: 'main-shell',
            ),
          ],
        ),
        styles: const {
          'background': ContainerStyle(color: Color(0xFF101010)),
          'shell-appbar': ContainerStyle(color: Color(0xFF202020)),
          'clients-title': ContainerStyle(color: Color(0xFF303030)),
          'shared-badge': ContainerStyle(color: Color(0xFF404040)),
        },
        components: {
          'root': ScaffoldPageConfig(
            placements: const {
              ScaffoldPageRegion.body: ['mainLayout'],
            },
            slotTypes: const {'mainLayout': 'registry:Layout'},
          ),
          'mainLayout': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['shared-badge'],
            },
            slotTypes: {'shared-badge': 'registry:Value'},
          ),
          'shared-badge': const SuperValueConfig(initialText: 'Badge Partage'),
          'main-shell': ScaffoldPageConfig(
            regions: const {
              ScaffoldPageRegion.appBar: true,
              ScaffoldPageRegion.sidebarStart: true,
              ScaffoldPageRegion.body: true,
            },
            placements: const {
              ScaffoldPageRegion.appBar: ['shell-appbar'],
              ScaffoldPageRegion.sidebarStart: ['shell-sidebar'],
              ScaffoldPageRegion.body: ['scaffold:outlet'],
            },
            slotTypes: const {
              'shell-appbar': 'registry:ApplicationBar',
              'shell-sidebar': 'registry:Layout',
              'scaffold:outlet': 'scaffold:outlet',
            },
            headerSpan: ScaffoldHeaderSpan.contentOnly,
            sidebarStartWidth: 260,
          ),
          'shell-appbar': NativeComponentConfig(
            regions: const {'title': true, 'actions': true},
            placements: const {
              'title': ['shell-title'],
              'actions': ['shared-badge'],
            },
            slotTypes: const {
              'shell-title': 'registry:Value',
              'shared-badge': 'registry:Value',
            },
          ),
          'shell-title': const SuperValueConfig(initialText: 'Mon App'),
          'shell-sidebar': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['shell-nav-btn'],
            },
            slotTypes: {'shell-nav-btn': 'registry:Action'},
          ),
          'shell-nav-btn': const SuperActionConfig(label: 'Clients'),
          'page-clients': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['clients-title'],
            },
            slotTypes: {'clients-title': 'registry:Value'},
          ),
          'clients-title': const SuperValueConfig(initialText: 'Clients Body'),
          'page-factures': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['factures-title'],
            },
            slotTypes: {'factures-title': 'registry:Value'},
          ),
          'factures-title': const SuperValueConfig(
            initialText: 'Factures Body',
          ),
        },
        behaviors: {
          'shell-nav-btn': [
            ComponentBehavior(
              id: 'beh-nav-clients',
              action: GoToPageAction(pagePath: '/clients', pageId: 'page-clients'),
            ),
          ],
        },
      );
    }

    test(
      'EditorPageGraph.detachPageFromShell deep-copies shell chrome with fresh IDs and preserves original layout & sibling',
      () {
        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final appearance = buildShellGraphAppearance();

        var counter = 0;
        final detached = EditorPageGraph.detachPageFromShell(
          appearance: appearance,
          registry: registry,
          pageId: 'page-clients',
          generateId: () => 'copy-${++counter}',
        );

        // Catalog: page-clients detached; page-factures & main-shell intact.
        final clientsPage = detached.pageCatalog.pages.firstWhere(
          (p) => p.id == 'page-clients',
        );
        final facturesPage = detached.pageCatalog.pages.firstWhere(
          (p) => p.id == 'page-factures',
        );
        expect(clientsPage.shellId, isNull);
        expect(facturesPage.shellId, 'main-shell');
        expect(detached.pageCatalog.shells.map((s) => s.id), ['main-shell']);

        // page-clients is now a standalone ScaffoldPageConfig preserving shell props.
        final detachedRoot = detached.components['page-clients'];
        expect(detachedRoot, isA<ScaffoldPageConfig>());
        final detachedScaffold = detachedRoot as ScaffoldPageConfig;
        expect(detachedScaffold.headerSpan, ScaffoldHeaderSpan.contentOnly);
        expect(detachedScaffold.sidebarStartWidth, 260);

        // Deep-copied appBar & sidebarStart have fresh IDs distinct from main-shell's.
        final copiedAppBarId =
            detachedScaffold.slotsOf(ScaffoldPageRegion.appBar).single;
        final copiedSidebarId =
            detachedScaffold.slotsOf(ScaffoldPageRegion.sidebarStart).single;
        expect(copiedAppBarId, isNot('shell-appbar'));
        expect(copiedSidebarId, isNot('shell-sidebar'));
        expect(detached.components[copiedAppBarId], isA<NativeComponentConfig>());
        expect(detached.components[copiedSidebarId], isA<SuperLayoutConfig>());
        expect(detached.styles[copiedAppBarId], appearance.styles['shell-appbar']);

        // Original page-clients SuperLayoutConfig was relocated into body (no scaffold:outlet left).
        final bodySlots = detachedScaffold.slotsOf(ScaffoldPageRegion.body);
        expect(bodySlots, hasLength(1));
        expect(bodySlots.single, isNot('scaffold:outlet'));
        final relocatedLayout = detached.components[bodySlots.single];
        expect(relocatedLayout, isA<SuperLayoutConfig>());
        expect(
          (relocatedLayout as SuperLayoutConfig)
              .placements[SuperLayoutZone.center],
          ['clients-title'],
        );
        expect(detached.components['clients-title'], isA<SuperValueConfig>());

        // Original shell remains completely intact for sibling page-factures.
        final originalShell =
            detached.components['main-shell'] as ScaffoldPageConfig;
        expect(originalShell.slotsOf(ScaffoldPageRegion.appBar), [
          'shell-appbar',
        ]);
        expect(originalShell.slotsOf(ScaffoldPageRegion.sidebarStart), [
          'shell-sidebar',
        ]);
        expect(originalShell.slotsOf(ScaffoldPageRegion.body), [
          'scaffold:outlet',
        ]);
      },
    );

    test(
      'EditorPageGraph.removeShell detaches pages, clears rootShellId, removes shell-exclusive components and preserves shared ones',
      () {
        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final appearance = buildShellGraphAppearance();

        final result = EditorPageGraph.removeShell(
          appearance: appearance,
          registry: registry,
          shellId: 'main-shell',
        );

        final next = result.appearance;
        expect(next.pageCatalog.shells, isEmpty);
        expect(next.pageCatalog.rootShellId, isNull);
        expect(next.pageCatalog.pages.every((p) => p.shellId == null), isTrue);

        // Shell-exclusive components removed.
        expect(next.components.containsKey('main-shell'), isFalse);
        expect(next.components.containsKey('shell-appbar'), isFalse);
        expect(next.components.containsKey('shell-title'), isFalse);
        expect(next.components.containsKey('shell-sidebar'), isFalse);
        expect(next.components.containsKey('shell-nav-btn'), isFalse);

        // Shared component (also referenced by mainLayout) & page components preserved.
        expect(next.components.containsKey('shared-badge'), isTrue);
        expect(next.styles.containsKey('shared-badge'), isTrue);
        expect(next.components.containsKey('page-clients'), isTrue);
        expect(next.components.containsKey('clients-title'), isTrue);
        expect(next.components.containsKey('page-factures'), isTrue);
        expect(next.components.containsKey('factures-title'), isTrue);
      },
    );

    test(
      'PagedFileAppearanceStore keeps shells in appearance.json, creates no pages/<shellId>.json, and stores pages in pages/<pageId>.json',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'paged-shell-test-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);

        final appearanceFile = File(
          '${tempDir.path}${Platform.pathSeparator}appearance.json',
        );
        final pagesDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}pages',
        );
        final store = PagedFileAppearanceStore(
          appearanceFile,
          pagesDirectory: pagesDir,
          registry: registry,
        );

        final appearance = buildShellGraphAppearance();
        await store.save(appearance);

        // Verify disk layout: appearance.json has shells & shell components,
        // no pages/main-shell.json exists, and page files exist for both pages.
        expect(await appearanceFile.exists(), isTrue);
        expect(await store.pageFileFor('main-shell').exists(), isFalse);
        expect(await store.pageFileFor('page-clients').exists(), isTrue);
        expect(await store.pageFileFor('page-factures').exists(), isTrue);

        final globalJson =
            jsonDecode(await appearanceFile.readAsString())
                as Map<String, dynamic>;
        final globalComponents =
            globalJson['components'] as Map<String, dynamic>;
        expect(globalComponents.containsKey('main-shell'), isTrue);
        expect(globalComponents.containsKey('shell-appbar'), isTrue);
        expect(globalComponents.containsKey('shell-sidebar'), isTrue);
        expect(globalComponents.containsKey('page-clients'), isFalse);
        expect(globalComponents.containsKey('page-factures'), isFalse);

        final globalCatalog =
            globalJson['pageCatalog'] as Map<String, dynamic>;
        expect(globalCatalog['rootShellId'], 'main-shell');
        expect((globalCatalog['shells'] as List).length, 1);

        // Reload in a brand-new PagedFileAppearanceStore and load pages on demand.
        final reloadedStore = PagedFileAppearanceStore(
          appearanceFile,
          pagesDirectory: pagesDir,
          registry: registry,
        );
        final loadedGlobal = await reloadedStore.load();
        expect(reloadedStore.isKnownCatalogShell('main-shell'), isTrue);
        expect(loadedGlobal.pageCatalog.shells.single.id, 'main-shell');
        expect(loadedGlobal.pageCatalog.rootShellId, 'main-shell');
        expect(loadedGlobal.components.containsKey('main-shell'), isTrue);
        expect(loadedGlobal.components.containsKey('page-clients'), isFalse);

        final clientsSlice = await reloadedStore.loadPage('page-clients');
        expect(clientsSlice.components.containsKey('page-clients'), isTrue);
        expect(clientsSlice.components.containsKey('clients-title'), isTrue);
        expect(clientsSlice.components.containsKey('main-shell'), isFalse);
      },
    );

    test(
      'DartCodeExporter.export emits sidebarStart, headerSpan and sidebarStartWidth for ScaffoldPageConfig',
      () {
        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final appearance = buildShellGraphAppearance();

        final code = DartCodeExporter.export(
          appearance: appearance,
          registry: registry,
          componentId: 'main-shell',
          componentLabel: 'Shell Principal',
        );

        expect(code, contains('ScaffoldHeaderSpan.contentOnly'));
        expect(code, contains('sidebarStartWidth: 260'));
        expect(code, contains('sidebarStart'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 5. EditorPageManager UI Smoke Test
  // ---------------------------------------------------------------------------
  group('EditorPageManager multi-shell UI', () {
    testWidgets(
      'creates a shell, toggles rootShellId, assigns a page to it, and detaches via page-detach-shell-<id>',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final routing = EditorPageRouter(
          baseConfig: RoutingConfig(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const SuperPage(child: Text('Home Coded')),
              ),
            ],
          ),
        );
        addTearDown(routing.dispose);

        await tester.pumpWidget(
          SuperApp(
            router: routing.router,
            pageRouting: routing,
            registry: registry,
            fontManager: _noopFontManager(),
          ),
        );
        await tester.pumpAndSettle();

        final context = tester.element(find.text('Home Coded'));
        final appearance = AppearanceScope.controllerOf(context)!;
        StyleEditScope.controllerOf(context)!.value = true;
        await tester.pumpAndSettle();

        // Open Page Manager.
        await tester.tap(find.byKey(const ValueKey('style-edit-banner-pages')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('editor-pages-manager')), findsOneWidget);

        // 1. Create a new shell.
        await tester.tap(find.byKey(const ValueKey('page-manager-add-shell')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('page-manager-shell-name')),
          'Shell CRM',
        );
        await tester.tap(find.text('Valider'));
        await tester.pumpAndSettle();

        expect(find.text('Shell CRM'), findsOneWidget);

        // Extract generated shell ID from the shell row ValueKey.
        final shellRowWidget = tester.widget<Card>(
          find.byWidgetPredicate(
            (w) =>
                w is Card &&
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith(
                  'editor-shell-row-',
                ),
          ),
        );
        final shellId = (shellRowWidget.key as ValueKey<String>).value
            .substring('editor-shell-row-'.length);

        // 2. Toggle rootShellId on the newly created shell.
        await tester.tap(find.byKey(ValueKey('editor-shell-root-$shellId')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('editor-shell-root-badge-$shellId')),
          findsOneWidget,
        );

        // 3. Add a page and assign it to Shell CRM.
        await tester.tap(find.byKey(const ValueKey('editor-pages-add')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-page-name')),
          'Clients',
        );
        await tester.enterText(
          find.byKey(const ValueKey('editor-page-path')),
          '/clients',
        );
        await tester.tap(
          find.byKey(const ValueKey('page-details-shell-dropdown')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shell CRM').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Valider'));
        await tester.pumpAndSettle();

        // Extract generated page ID from its row ValueKey.
        final pageRowWidget = tester.widget<Card>(
          find.byWidgetPredicate(
            (w) =>
                w is Card &&
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith(
                  'editor-page-row-',
                ),
          ),
        );
        final pageId = (pageRowWidget.key as ValueKey<String>).value.substring(
          'editor-page-row-'.length,
        );

        // Detach button is visible while attached to the shell.
        final detachFinder = find.byKey(ValueKey('page-detach-shell-$pageId'));
        expect(detachFinder, findsOneWidget);

        // 4. Click detach button.
        await tester.tap(detachFinder);
        await tester.pumpAndSettle();

        expect(detachFinder, findsNothing);
        expect(find.text('Autonome'), findsOneWidget);

        // 5. Apply changes and verify persisted Appearance state.
        await tester.tap(find.text('Appliquer'));
        await tester.pumpAndSettle();

        expect(appearance.value.pageCatalog.shells.single.id, shellId);
        expect(appearance.value.pageCatalog.shells.single.name, 'Shell CRM');
        expect(appearance.value.pageCatalog.rootShellId, shellId);
        final savedPage = appearance.value.pageCatalog.pages.single;
        expect(savedPage.id, pageId);
        expect(savedPage.shellId, isNull);
        expect(appearance.value.components[pageId], isA<ScaffoldPageConfig>());
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 6. VibePageAuditService & VibeDeltaRecovery
  // ---------------------------------------------------------------------------
  group('VibePageAuditService & VibeDeltaRecovery', () {
    test(
      'VibePageAuditService detects missing_page_navigation and missing_shell_outlet accurately',
      () async {
        // Case A: Secondary page without shellId and without navigation region -> missing_page_navigation,
        // and shell missing scaffold:outlet -> missing_shell_outlet.
        final badAppearance = Appearance(
          pageCatalog: EditorPageCatalog(
            shells: [
              EditorShellConfig(id: 'broken-shell', name: 'Shell Cassé'),
            ],
            pages: [
              EditorPageConfig(
                id: 'orphan-page',
                name: 'Page Sans Nav',
                path: '/orphan',
              ),
            ],
          ),
          components: {
            'broken-shell': ScaffoldPageConfig(
              regions: const {
                ScaffoldPageRegion.appBar: true,
                ScaffoldPageRegion.body: true,
              },
              placements: const {
                ScaffoldPageRegion.appBar: ['bar-1'],
                // Missing scaffold:outlet!
                ScaffoldPageRegion.body: ['static-body'],
              },
              slotTypes: const {
                'bar-1': 'registry:ApplicationBar',
                'static-body': 'registry:Value',
              },
            ),
            'bar-1': NativeComponentConfig(),
            'static-body': const SuperValueConfig(initialText: 'Static'),
            'orphan-page': const SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: ['orphan-val'],
              },
              slotTypes: {'orphan-val': 'registry:Value'},
            ),
            'orphan-val': const SuperValueConfig(initialText: 'Dead end'),
          },
        );

        final badReport = await VibePageAuditService.collect(
          VibeAppInspector(readAppearance: () => badAppearance),
        );
        expect(
          badReport.findings.any(
            (f) =>
                f.kind == 'missing_shell_outlet' &&
                f.componentId == 'broken-shell',
          ),
          isTrue,
        );
        expect(
          badReport.findings.any(
            (f) =>
                f.kind == 'missing_page_navigation' &&
                f.componentId == 'orphan-page',
          ),
          isTrue,
        );

        // Case B: Good shell with scaffold:outlet, page attached to shell,
        // and standalone page with its own appBar/sidebarStart -> zero navigation/shell findings.
        final goodAppearance = Appearance(
          pageCatalog: EditorPageCatalog(
            shells: [
              EditorShellConfig(id: 'main-shell', name: 'Shell Principal'),
            ],
            pages: [
              EditorPageConfig(
                id: 'shelled-page',
                name: 'Clients',
                path: '/clients',
                shellId: 'main-shell',
              ),
              EditorPageConfig(
                id: 'standalone-with-appbar',
                name: 'Avec AppBar',
                path: '/with-appbar',
              ),
              EditorPageConfig(
                id: 'standalone-with-sidebar',
                name: 'Avec Sidebar',
                path: '/with-sidebar',
              ),
            ],
          ),
          components: {
            'main-shell': ScaffoldPageConfig(
              regions: const {
                ScaffoldPageRegion.appBar: true,
                ScaffoldPageRegion.body: true,
              },
              placements: const {
                ScaffoldPageRegion.appBar: ['shell-bar'],
                ScaffoldPageRegion.body: ['scaffold:outlet'],
              },
              slotTypes: const {
                'shell-bar': 'registry:ApplicationBar',
                'scaffold:outlet': 'scaffold:outlet',
              },
            ),
            'shell-bar': NativeComponentConfig(),
            'shelled-page': const SuperLayoutConfig(),
            'standalone-with-appbar': ScaffoldPageConfig(
              regions: const {
                ScaffoldPageRegion.appBar: true,
                ScaffoldPageRegion.body: true,
              },
              placements: const {
                ScaffoldPageRegion.appBar: ['p1-bar'],
                ScaffoldPageRegion.body: ['p1-body'],
              },
              slotTypes: const {
                'p1-bar': 'registry:ApplicationBar',
                'p1-body': 'registry:Value',
              },
            ),
            'p1-bar': NativeComponentConfig(),
            'p1-body': const SuperValueConfig(initialText: 'Ok'),
            'standalone-with-sidebar': ScaffoldPageConfig(
              regions: const {
                ScaffoldPageRegion.sidebarStart: true,
                ScaffoldPageRegion.body: true,
              },
              placements: const {
                ScaffoldPageRegion.sidebarStart: ['p2-rail'],
                ScaffoldPageRegion.body: ['p2-body'],
              },
              slotTypes: const {
                'p2-rail': 'registry:NavigationRail',
                'p2-body': 'registry:Value',
              },
            ),
            'p2-rail': NativeComponentConfig(),
            'p2-body': const SuperValueConfig(initialText: 'Ok'),
          },
        );

        final goodReport = await VibePageAuditService.collect(
          VibeAppInspector(readAppearance: () => goodAppearance),
        );
        expect(
          goodReport.findings.where(
            (f) =>
                f.kind == 'missing_shell_outlet' ||
                f.kind == 'missing_page_navigation',
          ),
          isEmpty,
        );
      },
    );

    test(
      'VibeDeltaRecovery.computeReachableIds includes shell components and descendants',
      () {
        final appearance = Appearance(
          pageCatalog: EditorPageCatalog(
            shells: [
              EditorShellConfig(id: 'main-shell', name: 'Shell Principal'),
            ],
            rootShellId: 'main-shell',
            pages: [
              EditorPageConfig(
                id: 'page-clients',
                name: 'Clients',
                path: '/clients',
                shellId: 'main-shell',
              ),
            ],
          ),
          components: {
            'main-shell': ScaffoldPageConfig(
              regions: const {
                ScaffoldPageRegion.appBar: true,
                ScaffoldPageRegion.sidebarStart: true,
                ScaffoldPageRegion.body: true,
              },
              placements: const {
                ScaffoldPageRegion.appBar: ['shell-appbar'],
                ScaffoldPageRegion.sidebarStart: ['shell-rail'],
                ScaffoldPageRegion.body: ['scaffold:outlet'],
              },
              slotTypes: const {
                'shell-appbar': 'registry:ApplicationBar',
                'shell-rail': 'registry:NavigationRail',
                'scaffold:outlet': 'scaffold:outlet',
              },
            ),
            'shell-appbar': NativeComponentConfig(
              regions: const {'title': true},
              placements: const {
                'title': ['shell-title'],
              },
              slotTypes: const {'shell-title': 'registry:Value'},
            ),
            'shell-title': const SuperValueConfig(initialText: 'Titre Shell'),
            'shell-rail': NativeComponentConfig(
              regions: const {'destinations': true},
              placements: const {
                'destinations': ['rail-dest-1'],
              },
              slotTypes: const {'rail-dest-1': 'registry:Action'},
            ),
            'rail-dest-1': const SuperActionConfig(label: 'Clients'),
            'page-clients': const SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: ['clients-val'],
              },
              slotTypes: {'clients-val': 'registry:Value'},
            ),
            'clients-val': const SuperValueConfig(initialText: 'Clients'),
            'true-orphan': const SuperValueConfig(initialText: 'Orphelin'),
          },
        );

        final reachable = VibeDeltaRecovery.computeReachableIds(
          baseForScope: Appearance(),
          next: appearance,
          scope: null,
          instantiatedIds: const {'root', 'mainLayout'},
          initialPageIds: const {},
        );

        expect(
          reachable,
          containsAll(<String>[
            'main-shell',
            'shell-appbar',
            'shell-title',
            'shell-rail',
            'rail-dest-1',
            'page-clients',
            'clients-val',
          ]),
        );
        expect(reachable.contains('true-orphan'), isFalse);
      },
    );
  });
}
