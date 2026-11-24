import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

class _FakeGuideBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      '# Guide de test minimal\n';

  @override
  Future<ByteData> load(String key) async => ByteData(0);
}

DynamicFontManager _noopFontManager() => DynamicFontManager(
  useDefaultCacheDirectory: false,
  autoDownloadEnabled: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    VibeWorkHighlightController.instance.clearAll();
    tempDir = await Directory.systemTemp.createTemp('vibe-live-page-router-');
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() async {
    VibeWorkHighlightController.instance.clearAll();
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  EditorPageRouter createRouter() => EditorPageRouter(
    baseConfig: RoutingConfig(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            final app = SuperApp.maybeOf(context);
            final layout = app?.getLayoutConfigById('mainLayout');
            if (layout == null) {
              return const SuperPage(child: Text('Racine codée'));
            }
            return SuperPage(
              child: ValueListenableBuilder<SuperLayoutConfig>(
                valueListenable: layout,
                builder: (context, config, _) => SuperLayout(
                  id: 'mainLayout',
                  label: 'Main Layout',
                  config: config,
                  onChanged: (next) => layout.value = next,
                ),
              ),
            );
          },
        ),
      ],
    ),
  );

  group('VibeLivePageRouter unit resolution', () {
    test('tracks sequential pages across streaming steps without flickering on unpopulated styles or trailing usages', () {
      final routing = createRouter();
      addTearDown(routing.dispose);

      final base = Appearance();
      routing.synchronize(base.pageCatalog);
      expect(routing.currentUri.path, '/');

      final catalog = EditorPageCatalog(
        homePageId: 'page-a',
        pages: [
          EditorPageConfig(id: 'page-a', name: 'Page A', path: '/page-a'),
          EditorPageConfig(id: 'page-b', name: 'Page B', path: '/page-b'),
        ],
      );

      // Step 1: pageCatalog arrives -> navigates to homePageId (/page-a).
      final step1 = base.copyWith(pageCatalog: catalog);
      final dec1 = VibeLivePageRouter.resolveForPreviewStep(
        routing: routing,
        previousAppearance: base,
        nextAppearance: step1,
        effectivePatch: {'pageCatalog': catalog.toJson()},
        initialPageIds: const <String>{},
        hasNavigatedForVisualChange: false,
      );
      expect(dec1?.target.pageId, 'page-a');
      expect(
        VibeLivePageRouter.navigateToTarget(
          routing: routing,
          appearance: step1,
          target: dec1!.target,
        ),
        isTrue,
      );
      expect(routing.currentUri.path, '/page-a');

      // Step 2: style for unpopulated new page-b arrives before components -> stays on /page-a.
      final step2 = step1.withStyle(
        'page-b',
        const ContainerStyle(color: Color(0xFF112233)),
      );
      final dec2 = VibeLivePageRouter.resolveForPreviewStep(
        routing: routing,
        previousAppearance: step1,
        nextAppearance: step2,
        effectivePatch: {
          'pageCatalog': catalog.toJson(),
          'styles': {
            'page-b': const ContainerStyle(color: Color(0xFF112233)).toJson(),
          },
        },
        initialPageIds: const <String>{},
        hasNavigatedForVisualChange: false,
      );
      expect(dec2, isNull);
      expect(routing.currentUri.path, '/page-a');

      // Step 3: page-a scaffold + child arrive -> stays on /page-a and marks visual change.
      final step3 = step2
          .withScaffoldPage(
            'page-a',
            ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['val-a'],
              },
              slotTypes: const {'val-a': 'registry:Value'},
            ),
          )
          .withValueComponent(
            'val-a',
            const SuperValueConfig(initialText: 'Bonjour A'),
          );
      final dec3 = VibeLivePageRouter.resolveForPreviewStep(
        routing: routing,
        previousAppearance: step2,
        nextAppearance: step3,
        effectivePatch: {
          'components': {
            'page-a': <String, Object?>{},
            'val-a': <String, Object?>{},
          },
        },
        initialPageIds: const <String>{},
        hasNavigatedForVisualChange: false,
      );
      expect(dec3?.target.pageId, 'page-a');
      expect(dec3?.isVisualChange, isTrue);

      // Step 4: streaming starts on "page-b" component -> switches immediately to /page-b!
      final streamB = VibeLivePageRouter.resolveForStreamingEntry(
        routing: routing,
        appearance: step3,
        activeSection: 'components',
        activeEntryKey: 'page-b',
        initialPageIds: const <String>{},
        hasNavigatedForVisualChange: true,
      );
      expect(streamB?.target.pageId, 'page-b');
      expect(
        VibeLivePageRouter.navigateToTarget(
          routing: routing,
          appearance: step3,
          target: streamB!.target,
        ),
        isTrue,
      );
      expect(routing.currentUri.path, '/page-b');

      // Step 5: page-b components close -> stays on /page-b.
      final step5 = step3
          .withScaffoldPage(
            'page-b',
            ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['val-b'],
              },
              slotTypes: const {'val-b': 'registry:Value'},
            ),
          )
          .withValueComponent(
            'val-b',
            const SuperValueConfig(initialText: 'Bonjour B'),
          );
      final dec5 = VibeLivePageRouter.resolveForPreviewStep(
        routing: routing,
        previousAppearance: step3,
        nextAppearance: step5,
        effectivePatch: {
          'components': {
            'page-a': <String, Object?>{},
            'val-a': <String, Object?>{},
            'page-b': <String, Object?>{},
            'val-b': <String, Object?>{},
          },
        },
        initialPageIds: const <String>{},
        hasNavigatedForVisualChange: true,
      );
      expect(dec5?.target.pageId, 'page-b');

      // Step 6: trailing behaviors on val-a do NOT yank away from /page-b after visual changes.
      final step6 = step5.copyWith(
        behaviors: {
          'val-a': [
            ComponentBehavior(
              id: 'go-b',
              action: GoToPageAction(pagePath: '/page-b', pageId: 'page-b'),
            ),
          ],
        },
      );
      final dec6 = VibeLivePageRouter.resolveForPreviewStep(
        routing: routing,
        previousAppearance: step5,
        nextAppearance: step6,
        effectivePatch: {
          'behaviors': {'val-a': <Object?>[]},
        },
        initialPageIds: const <String>{},
        hasNavigatedForVisualChange: true,
      );
      expect(dec6, isNull);
      expect(routing.currentUri.path, '/page-b');
    });

    test('synthesizes preview parameters for parameterized pages and preserves active concrete URI', () {
      final routing = createRouter();
      addTearDown(routing.dispose);

      final detailPage = EditorPageConfig(
        id: 'client-detail',
        name: 'Détail Client',
        path: r'/clients/:id(\d+)',
      );
      final appearance = Appearance(
        pageCatalog: EditorPageCatalog(pages: [detailPage]),
        components: {
          'client-detail': ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.body: const ['detail-title'],
            },
            slotTypes: const {'detail-title': 'registry:Value'},
          ),
          'detail-title': const SuperValueConfig(initialText: 'Fiche'),
        },
      );
      routing.synchronize(appearance.pageCatalog);

      final target = VibeRouteTarget.catalogPage(detailPage);
      expect(VibeLivePageRouter.resolveLocation(routing, target), '/clients/1');
      expect(
        VibeLivePageRouter.navigateToTarget(
          routing: routing,
          appearance: appearance,
          target: target,
        ),
        isTrue,
      );
      expect(routing.currentUri.path, '/clients/1');

      // If user is already viewing /clients/42, patching client-detail stays on /clients/42.
      routing.openLocation('/clients/42');
      expect(routing.currentUri.path, '/clients/42');
      expect(
        VibeLivePageRouter.isAlreadyOnTarget(routing, appearance, target),
        isTrue,
      );
      expect(
        VibeLivePageRouter.navigateToTarget(
          routing: routing,
          appearance: appearance,
          target: target,
        ),
        isFalse,
      );
      expect(routing.currentUri.path, '/clients/42');
    });

    test('routes back to coded root "/" when mainLayout is patched and lands on new page when nav link is added on "/"', () {
      final routing = createRouter();
      addTearDown(routing.dispose);

      final pageReports = EditorPageConfig(
        id: 'reports',
        name: 'Rapports',
        path: '/rapports',
      );
      final base = Appearance(
        components: {'mainLayout': const SuperLayoutConfig()},
      );
      routing.synchronize(base.pageCatalog);

      // Turn 1 creates /rapports (3 components) AND adds 1 nav action on mainLayout ('/').
      final afterTurn1 = base.copyWith(
        pageCatalog: EditorPageCatalog(pages: [pageReports]),
        components: {
          'mainLayout': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.north: ['btn-reports'],
            },
            slotTypes: {'btn-reports': 'registry:Action'},
          ),
          'btn-reports': const SuperActionConfig(label: 'Rapports'),
          'reports': ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.body: const ['reports-layout'],
            },
            slotTypes: const {'reports-layout': 'registry:Layout'},
          ),
          'reports-layout': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['reports-kpi'],
            },
            slotTypes: {'reports-kpi': 'registry:Value'},
          ),
          'reports-kpi': const SuperValueConfig(initialText: '42 rapports'),
        },
      );
      routing.synchronize(afterTurn1.pageCatalog);
      // Even if streaming briefly ended on '/', outcome resolves to the newly added page '/rapports'!
      routing.openLocation('/');
      final outcome1 = VibeLivePageRouter.resolveForTurnOutcome(
        routing: routing,
        baseAppearance: base,
        finalAppearance: afterTurn1,
        initialPageIds: const <String>{},
      );
      expect(outcome1?.pageId, 'reports');
      VibeLivePageRouter.navigateToTarget(
        routing: routing,
        appearance: afterTurn1,
        target: outcome1!,
      );
      expect(routing.currentUri.path, '/rapports');

      // Turn 2 modifies mainLayout on '/' while currently on '/rapports' -> routes back to '/'!
      final afterTurn2 = afterTurn1.copyWith(
        components: {
          ...afterTurn1.components,
          'mainLayout': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.north: ['btn-reports'],
              SuperLayoutZone.center: ['home-hero'],
            },
            slotTypes: {
              'btn-reports': 'registry:Action',
              'home-hero': 'registry:Value',
            },
          ),
          'home-hero': const SuperValueConfig(initialText: 'Bienvenue Accueil'),
        },
      );
      final stepRoot = VibeLivePageRouter.resolveForPreviewStep(
        routing: routing,
        previousAppearance: afterTurn1,
        nextAppearance: afterTurn2,
        effectivePatch: {
          'components': {
            'mainLayout': <String, Object?>{},
            'home-hero': <String, Object?>{},
          },
        },
        initialPageIds: const {'reports'},
        hasNavigatedForVisualChange: false,
      );
      expect(stepRoot?.target.isCodedRoot, isTrue);
      VibeLivePageRouter.navigateToTarget(
        routing: routing,
        appearance: afterTurn2,
        target: stepRoot!.target,
      );
      expect(routing.currentUri.path, '/');
    });
  });

  group('VibeChatDialog live page routing widget integration', () {
    testWidgets(
      'streams multi-page construction live across Page A then Page B and renders each page during its build',
      (tester) async {
        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final pageRouting = createRouter();
        addTearDown(pageRouting.dispose);
        final store = AppearanceStore(key: 'multi-page-stream-test');
        final controller = PersistentAppearanceController(
          store,
          (_) {},
          validateAppearance: (value) =>
              pageRouting.validate(value.pageCatalog),
        );
        registry.bindAppearance(controller);
        addTearDown(registry.unbindAppearance);
        addTearDown(controller.dispose);

        late StreamController<GeminiStreamEvent> streamController;

        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: _FakeGuideBundle(),
            child: SuperAppScope(
              app: SuperApp(
                router: pageRouting.router,
                pageRouting: pageRouting,
                registry: registry,
                fontManager: _noopFontManager(),
              ),
              child: AppearanceScope(
                controller: controller,
                child: MaterialApp.router(
                  routerConfig: pageRouting.router,
                  builder: (context, child) => Scaffold(
                    body: Row(
                      children: [
                        Expanded(child: child!),
                        SizedBox(
                          width: 380,
                          height: 580,
                          child: Overlay(
                            initialEntries: [
                              OverlayEntry(
                                builder: (_) => VibeChatDialog(
                                  controller: controller,
                                  registry: registry,
                                  pageRouting: pageRouting,
                                  validateAppearance: (value) =>
                                      pageRouting.validate(value.pageCatalog),
                                  codec: const AppearanceCodec(),
                                  initialQuestioningLevel:
                                      VibeQuestioningLevel.none,
                                  onClose: () {},
                                  onDrag: (_) {},
                                  generate: (_) =>
                                      Future.error('Use streamGenerate'),
                                  streamGenerate:
                                      (
                                        prompt, {
                                        systemInstruction,
                                        staticGuide,
                                        attachments = const [],
                                        speedMode = VibeAiSpeedMode.fast,
                                      }) {
                                        streamController =
                                            StreamController<
                                              GeminiStreamEvent
                                            >();
                                        return streamController.stream;
                                      },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(pageRouting.currentUri.path, '/');

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Crée /dashboard et /clients.',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pump();

        var acc = '';
        void emitChunk(String chunk, {bool isDone = false}) {
          acc += chunk;
          streamController.add(
            GeminiStreamEvent(
              deltaText: chunk,
              accumulatedText: acc,
              isDone: isDone,
              usedContextCache: true,
            ),
          );
        }

        // 1. Catalogue avec 2 pages + construction de /dashboard -> affiche /dashboard en direct.
        emitChunk(
          '{"message":"Construction multi-pages.","vibe":{'
          '"pageCatalog":{"homePageId":"dashboard","pages":['
          '{"id":"dashboard","name":"Dashboard","path":"/dashboard"},'
          '{"id":"clients","name":"Clients","path":"/clients"}]},'
          '"components":{'
          '"dashboard":{"type":"scaffold","placements":{"body":[{"id":"dash-kpi","type":"registry:Value"}]}},'
          '"dash-kpi":{"type":"value","text":"KPI Dashboard : 98%"}',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(pageRouting.currentUri.path, '/dashboard');
        expect(find.text('KPI Dashboard : 98%'), findsOneWidget);

        // 2. Début de construction de /clients -> bascule automatiquement sur /clients en direct !
        emitChunk(
          ',"clients":{"type":"scaffold","placements":{"body":[{"id":"clients-kpi","type":"registry:Value"}]}},'
          '"clients-kpi":{"type":"value","text":"Total Clients : 240"}',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(pageRouting.currentUri.path, '/clients');
        expect(find.text('Total Clients : 240'), findsOneWidget);

        // 3. Fin du flux.
        emitChunk('}}}', isDone: true);
        await streamController.close();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(pageRouting.currentUri.path, '/clients');
        expect(find.text('Total Clients : 240'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Plan mode routes to each existing catalog page as Lot 1, Lot 2 and Lot 3 build them',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final pageRouting = createRouter();
        addTearDown(pageRouting.dispose);
        final store = AppearanceStore(key: 'plan-lots-routing-test');

        var callCount = 0;
        final lot2Gate = Completer<void>();
        final lot3Gate = Completer<void>();

        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: _FakeGuideBundle(),
            child: SuperApp(
              router: pageRouting.router,
              pageRouting: pageRouting,
              registry: registry,
              appearanceStore: store,
              fontManager: _noopFontManager(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pageContext = tester.element(find.byType(SuperPage));
        final controller = AppearanceScope.controllerOf(pageContext)!;

        // Open VibeChatDialog in an overlay on top of SuperApp, just like StyleEditBanner.
        late OverlayEntry chatEntry;
        chatEntry = OverlayEntry(
          builder: (overlayCtx) => Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 680,
              height: 640,
              child: Material(
                child: VibeChatDialog(
                  controller: controller,
                  registry: registry,
                  pageRouting: pageRouting,
                  validateAppearance: (a) =>
                      pageRouting.validate(a.pageCatalog),
                  codec: const AppearanceCodec(),
                  initialQuestioningLevel: VibeQuestioningLevel.none,
                  initialPlanMode: true,
                  expanded: true,
                  onClose: () => chatEntry.remove(),
                  onDrag: (_) {},
                  generate: (prompt) async {
                    callCount++;
                    switch (callCount) {
                      case 1:
                        return jsonEncode({
                          'message': 'Plan en 3 lots prêt.',
                          'plan': {
                            'title': 'App Boutique',
                            'lots': [
                              {
                                'id': 'lot-1',
                                'title': 'Catalogue de pages et Accueil',
                                'description':
                                    'Créer les pages et construire /accueil.',
                              },
                              {
                                'id': 'lot-2',
                                'title': 'Page Catalogue',
                                'description': 'Construire /catalogue.',
                              },
                              {
                                'id': 'lot-3',
                                'title': 'Page Panier',
                                'description': 'Construire /panier.',
                              },
                            ],
                          },
                          'vibe': null,
                        });
                      case 2:
                        return jsonEncode({
                          'message': 'Lot 1 terminé.',
                          'vibe': {
                            'pageCatalog': {
                              'homePageId': 'p-accueil',
                              'pages': [
                                {
                                  'id': 'p-accueil',
                                  'name': 'Accueil',
                                  'path': '/accueil',
                                },
                                {
                                  'id': 'p-catalogue',
                                  'name': 'Catalogue',
                                  'path': '/catalogue',
                                },
                                {
                                  'id': 'p-panier',
                                  'name': 'Panier',
                                  'path': '/panier',
                                },
                              ],
                            },
                            'components': {
                              'p-accueil': {
                                'type': 'scaffold',
                                'placements': {
                                  'body': [
                                    {
                                      'id': 'accueil-val',
                                      'type': 'registry:Value',
                                    },
                                  ],
                                },
                              },
                              'accueil-val': {
                                'type': 'value',
                                'text': 'Bienvenue Boutique',
                              },
                            },
                          },
                        });
                      case 3:
                        await lot2Gate.future;
                        return jsonEncode({
                          'message': 'Lot 2 terminé.',
                          'vibe': {
                            'components': {
                              'p-catalogue': {
                                'type': 'scaffold',
                                'placements': {
                                  'body': [
                                    {'id': 'cat-val', 'type': 'registry:Value'},
                                  ],
                                },
                              },
                              'cat-val': {
                                'type': 'value',
                                'text': '150 Articles en stock',
                              },
                            },
                          },
                        });
                      default:
                        await lot3Gate.future;
                        return jsonEncode({
                          'message': 'Lot 3 terminé.',
                          'vibe': {
                            'components': {
                              'p-panier': {
                                'type': 'scaffold',
                                'placements': {
                                  'body': [
                                    {
                                      'id': 'panier-val',
                                      'type': 'registry:Value',
                                    },
                                  ],
                                },
                              },
                              'panier-val': {
                                'type': 'value',
                                'text': 'Votre Panier (3)',
                              },
                            },
                          },
                        });
                    }
                  },
                ),
              ),
            ),
          ),
        );
        addTearDown(() {
          if (chatEntry.mounted) chatEntry.remove();
        });
        Overlay.of(pageContext).insert(chatEntry);
        await tester.pump();

        // Phase 1 : génération du plan.
        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Construis la boutique.',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(callCount, 1);
        expect(find.byKey(const ValueKey('vibe-plan-start')), findsOneWidget);

        // Lot 1 s'exécute et affiche immédiatement /accueil pendant que Lot 2 attend.
        await tester.tap(find.byKey(const ValueKey('vibe-plan-start')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(pageRouting.currentUri.path, '/accueil');
        expect(find.text('Bienvenue Boutique'), findsOneWidget);

        // Débloque Lot 2 -> bascule automatiquement sur /catalogue pendant que Lot 3 attend !
        lot2Gate.complete();
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(pageRouting.currentUri.path, '/catalogue');
        expect(find.text('150 Articles en stock'), findsOneWidget);

        // Débloque Lot 3 -> bascule automatiquement sur /panier !
        lot3Gate.complete();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(callCount, 4);
        expect(pageRouting.currentUri.path, '/panier');
        expect(find.text('Votre Panier (3)'), findsOneWidget);
        expect(
          controller.value
              .tryComponent<SuperValueConfig>('accueil-val')
              ?.initialText,
          'Bienvenue Boutique',
        );
        expect(
          controller.value
              .tryComponent<SuperValueConfig>('cat-val')
              ?.initialText,
          '150 Articles en stock',
        );
        expect(tester.takeException(), isNull);

        if (chatEntry.mounted) chatEntry.remove();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'PagedFileAppearanceStore preloads unloaded pages before AI patch and displays newly patched or created page immediately',
      (tester) async {
        Future<void> pumpAsync(Future<void> Function() action) async {
          await tester.runAsync(() async {
            await action();
            for (var i = 0; i < 20; i++) {
              await tester.pump();
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          });
          await tester.pump();
        }

        final appDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}sandboxed',
        );
        final seedAppearance = Appearance(
          components: {
            'mainLayout': const SuperLayoutConfig(),
            'page-a': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['val-a'],
              },
              slotTypes: const {'val-a': 'registry:Value'},
            ),
            'val-a': const SuperValueConfig(initialText: 'Contenu Initial A'),
            'page-b': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['val-b'],
              },
              slotTypes: const {'val-b': 'registry:Value'},
            ),
            'val-b': const SuperValueConfig(initialText: 'Contenu Initial B'),
          },
          pageCatalog: EditorPageCatalog(
            pages: [
              EditorPageConfig(id: 'page-a', name: 'Page A', path: '/page-a'),
              EditorPageConfig(id: 'page-b', name: 'Page B', path: '/page-b'),
            ],
          ),
        );
        await tester.runAsync(
          () =>
              SandboxedApplicationStore.appearanceStoreFor(appDir)
                  .save(seedAppearance),
        );

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final pagedStore = SandboxedApplicationStore.appearanceStoreFor(
          appDir,
          registry: registry,
        );
        final pageRouting = createRouter();
        addTearDown(pageRouting.dispose);

        String? capturedPrompt;

        await pumpAsync(() async {
          await tester.pumpWidget(
            DefaultAssetBundle(
              bundle: _FakeGuideBundle(),
              child: SuperApp(
                router: pageRouting.router,
                pageRouting: pageRouting,
                registry: registry,
                appearanceStore: pagedStore,
                fontManager: _noopFontManager(),
              ),
            ),
          );
        });

        // Au démarrage sur '/', ni page-a ni page-b ne sont encore chargées depuis le disque.
        expect(pageRouting.currentUri.path, '/');
        expect(pagedStore.isPageLoaded('page-a'), isFalse);
        expect(pagedStore.isPageLoaded('page-b'), isFalse);

        final pageContext = tester.element(find.byType(SuperPage));
        final controller =
            AppearanceScope.controllerOf(pageContext)!
                as PersistentAppearanceController;

        late OverlayEntry chatEntry;
        chatEntry = OverlayEntry(
          builder: (_) => Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 400,
              height: 560,
              child: Material(
                child: VibeChatDialog(
                  controller: controller,
                  registry: registry,
                  pageRouting: pageRouting,
                  validateAppearance: (a) =>
                      pageRouting.validate(a.pageCatalog),
                  codec: const AppearanceCodec(),
                  initialQuestioningLevel: VibeQuestioningLevel.none,
                  onClose: () => chatEntry.remove(),
                  onDrag: (_) {},
                  generate: (prompt) async {
                    capturedPrompt = prompt;
                    return jsonEncode({
                      'message': 'Page B enrichie.',
                      'vibe': {
                        'components': {
                          'val-b': {
                            'type': 'value',
                            'text': 'Contenu B Mis à Jour par IA',
                          },
                        },
                      },
                    });
                  },
                ),
              ),
            ),
          ),
        );
        addTearDown(() {
          if (chatEntry.mounted) chatEntry.remove();
        });
        Overlay.of(pageContext).insert(chatEntry);
        await tester.pump();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Mets à jour le texte de la page B.',
        );
        await pumpAsync(() async {
          await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        });

        // Les pages paginées ont été préchargées avant la construction du prompt,
        // le routeur a basculé sur /page-b et Page A est restée intacte !
        expect(capturedPrompt, contains('Contenu Initial B'));
        expect(pagedStore.isPageLoaded('page-a'), isTrue);
        expect(pagedStore.isPageLoaded('page-b'), isTrue);
        expect(pageRouting.currentUri.path, '/page-b');
        expect(find.text('Contenu B Mis à Jour par IA'), findsOneWidget);
        expect(
          controller.value.tryComponent<SuperValueConfig>('val-a')?.initialText,
          'Contenu Initial A',
        );

        if (chatEntry.mounted) chatEntry.remove();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Visible-only mode keeps the current route locked even when another page exists',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final registry = Registry()..bootstrap();
        addTearDown(registry.dispose);
        final pageRouting = createRouter();
        addTearDown(pageRouting.dispose);

        final initial = Appearance(
          components: {
            'page-first': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['first-val'],
              },
              slotTypes: const {'first-val': 'registry:Value'},
            ),
            'first-val': const SuperValueConfig(initialText: 'Première Page'),
            'page-second': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.body: const ['second-val'],
              },
              slotTypes: const {'second-val': 'registry:Value'},
            ),
            'second-val': const SuperValueConfig(initialText: 'Deuxième Page'),
          },
          pageCatalog: EditorPageCatalog(
            homePageId: 'page-first',
            pages: [
              EditorPageConfig(
                id: 'page-first',
                name: 'Première',
                path: '/first',
              ),
              EditorPageConfig(
                id: 'page-second',
                name: 'Deuxième',
                path: '/second',
              ),
            ],
          ),
        );
        final store = AppearanceStore(key: 'visible-only-route-lock');
        await store.save(initial);

        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: _FakeGuideBundle(),
            child: SuperApp(
              router: pageRouting.router,
              pageRouting: pageRouting,
              registry: registry,
              appearanceStore: store,
              fontManager: _noopFontManager(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(pageRouting.currentUri.path, '/first');
        expect(find.text('Première Page'), findsOneWidget);

        final pageContext = tester.element(find.byType(SuperPage));
        final controller = AppearanceScope.controllerOf(pageContext)!;

        late OverlayEntry chatEntry;
        chatEntry = OverlayEntry(
          builder: (_) => Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 360,
              height: 420,
              child: Material(
                child: VibeChatDialog(
                  controller: controller,
                  registry: registry,
                  pageRouting: pageRouting,
                  validateAppearance: (a) =>
                      pageRouting.validate(a.pageCatalog),
                  codec: const AppearanceCodec(),
                  initialQuestioningLevel: VibeQuestioningLevel.none,
                  initialVisibleOnlyMode: true,
                  onClose: () => chatEntry.remove(),
                  onDrag: (_) {},
                  generate: (prompt) async => jsonEncode({
                    'message': 'Mis à jour.',
                    'vibe': {
                      'components': {
                        'second-val': {
                          'type': 'value',
                          'text': 'Deuxième Page Modifiée',
                        },
                      },
                    },
                  }),
                ),
              ),
            ),
          ),
        );
        addTearDown(() {
          if (chatEntry.mounted) chatEntry.remove();
        });
        Overlay.of(pageContext).insert(chatEntry);
        await tester.pump();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Modifie le texte.',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        // La route reste verrouillée sur /first en mode « Uniquement visible ».
        expect(pageRouting.currentUri.path, '/first');
        expect(find.text('Première Page'), findsOneWidget);
        expect(tester.takeException(), isNull);

        if (chatEntry.mounted) chatEntry.remove();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    test('caches _PageOwnershipIndex across repeated streaming/preview lookups when components and pageCatalog are unchanged', () {
      final routing = createRouter();
      addTearDown(routing.dispose);
      final appearance = Appearance(
        components: {
          'p-dash': ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.body: const ['kpi-a'],
            },
            slotTypes: const {'kpi-a': 'registry:Value'},
          ),
          'kpi-a': const SuperValueConfig(initialText: '100'),
        },
        pageCatalog: EditorPageCatalog(
          homePageId: 'p-dash',
          pages: [EditorPageConfig(id: 'p-dash', name: 'Dash', path: '/dash')],
        ),
      );
      routing.synchronize(appearance.pageCatalog);
      VibeLivePageRouter.resetDebugCache();

      for (var i = 0; i < 10; i++) {
        final decision = VibeLivePageRouter.resolveForStreamingEntry(
          routing: routing,
          appearance: appearance,
          activeSection: 'components',
          activeEntryKey: 'kpi-a',
          initialPageIds: const <String>{},
          hasNavigatedForVisualChange: false,
        );
        expect(decision?.target.pageId, 'p-dash');
      }
      // Un changement purement cosmétique (`styles`) conserve les mêmes composants et le même catalogue -> 0 reconstruction d'index !
      final restyled = appearance.copyWith(
        styles: const {'kpi-a': ContainerStyle(padding: 12)},
      );
      VibeLivePageRouter.resolveForPreviewStep(
        routing: routing,
        previousAppearance: appearance,
        nextAppearance: restyled,
        effectivePatch: const {
          'styles': {
            'kpi-a': {'padding': 12},
          },
        },
        initialPageIds: const <String>{},
        hasNavigatedForVisualChange: false,
      );
      VibeLivePageRouter.resolveForTurnOutcome(
        routing: routing,
        baseAppearance: appearance,
        finalAppearance: restyled,
        initialPageIds: const <String>{},
      );

      expect(VibeLivePageRouter.debugOwnershipIndexBuildCount, 1);
    });

    test(
      'maps shell components and descendants to coded root when rootShellId matches or first shelled page otherwise',
      () {
        final routing = createRouter();
        addTearDown(routing.dispose);
        VibeLivePageRouter.resetDebugCache();

        final catalogWithRootShell = EditorPageCatalog(
          shells: [EditorShellConfig(id: 'app-shell', name: 'Shell')],
          rootShellId: 'app-shell',
          pages: [
            EditorPageConfig(
              id: 'orders',
              name: 'Commandes',
              path: '/orders',
              shellId: 'app-shell',
            ),
            EditorPageConfig(
              id: 'login',
              name: 'Connexion',
              path: '/login',
            ),
          ],
        );

        final appearanceWithRootShell = Appearance(
          pageCatalog: catalogWithRootShell,
          components: {
            'app-shell': ScaffoldPageConfig(
              placements: {
                ScaffoldPageRegion.appBar: const ['app-header'],
                ScaffoldPageRegion.sidebarStart: const ['app-rail'],
                ScaffoldPageRegion.body: const ['scaffold:outlet'],
              },
              slotTypes: const {
                'app-header': 'registry:ApplicationBar',
                'app-rail': 'registry:NavigationRail',
              },
            ),
            'app-header': NativeComponentConfig(),
            'app-rail': NativeComponentConfig(),
            'login': ScaffoldPageConfig(),
          },
        );

        routing.synchronize(catalogWithRootShell);
        routing.openLocation('/login');
        expect(routing.currentUri.path, '/login');

        // Streaming a shell descendant from /login resolves to coded root '/'.
        final streamToRoot = VibeLivePageRouter.resolveForStreamingEntry(
          routing: routing,
          appearance: appearanceWithRootShell,
          activeSection: 'components',
          activeEntryKey: 'app-header',
          initialPageIds: const {'orders', 'login'},
          hasNavigatedForVisualChange: false,
        );
        expect(streamToRoot?.target.isCodedRoot, isTrue);

        // Preview step updating app-rail from /login resolves to coded root '/'.
        final updatedHeader = appearanceWithRootShell.withStyle(
          'app-rail',
          const ContainerStyle(padding: 8),
        );
        final stepToRoot = VibeLivePageRouter.resolveForPreviewStep(
          routing: routing,
          previousAppearance: appearanceWithRootShell,
          nextAppearance: updatedHeader,
          effectivePatch: {
            'styles': {
              'app-rail': const ContainerStyle(padding: 8).toJson(),
            },
          },
          initialPageIds: const {'orders', 'login'},
          hasNavigatedForVisualChange: false,
        );
        expect(stepToRoot?.target.isCodedRoot, isTrue);

        // When already on /orders (same shell), editing app-header stays on /orders.
        routing.openLocation('/orders');
        final stayOnOrders = VibeLivePageRouter.resolveForStreamingEntry(
          routing: routing,
          appearance: appearanceWithRootShell,
          activeSection: 'components',
          activeEntryKey: 'app-header',
          initialPageIds: const {'orders', 'login'},
          hasNavigatedForVisualChange: false,
        );
        expect(stayOnOrders?.target.pageId, 'orders');

        // Without rootShellId, shell edits map to the first page using that shell.
        final catalogNoRootShell = catalogWithRootShell.copyWith(
          clearRootShellId: true,
        );
        final appearanceNoRootShell = appearanceWithRootShell.copyWith(
          pageCatalog: catalogNoRootShell,
        );
        routing.synchronize(catalogNoRootShell);
        routing.openLocation('/login');

        final streamToFirstShelled = VibeLivePageRouter.resolveForStreamingEntry(
          routing: routing,
          appearance: appearanceNoRootShell,
          activeSection: 'components',
          activeEntryKey: 'app-shell',
          initialPageIds: const {'orders', 'login'},
          hasNavigatedForVisualChange: false,
        );
        expect(streamToFirstShelled?.target.pageId, 'orders');

        final outcomeToFirstShelled = VibeLivePageRouter.resolveForTurnOutcome(
          routing: routing,
          baseAppearance: appearanceNoRootShell,
          finalAppearance: appearanceNoRootShell.withStyle(
            'app-header',
            const ContainerStyle(padding: 12),
          ),
          initialPageIds: const {'orders', 'login'},
        );
        expect(outcomeToFirstShelled?.pageId, 'orders');
      },
    );
  });
}
