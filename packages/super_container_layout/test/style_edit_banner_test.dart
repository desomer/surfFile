import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/services/appearance/appearance_codec.dart';
import 'package:super_container_layout/services/appearance/appearance_store.dart';
import 'package:super_container_layout/services/pages/editor_page_router.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/components/super_layout/layout_selection.dart';
import 'package:super_container_layout/widgets/editing/overlay/style_edit_banner.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';

void main() {
  Future<void> pump(WidgetTester tester, ValueNotifier<bool> editMode) =>
      tester.pumpWidget(
        StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            builder: (context, child) => Stack(
              children: [
                child!,
                const Positioned.fill(child: StyleEditBanner()),
              ],
            ),
            home: const Scaffold(),
          ),
        ),
      );

  Rect banner(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('style-edit-banner')));

  Future<void> move(WidgetTester tester, Offset delta) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('style-edit-banner-drag'))),
    );
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    await gesture.moveBy(delta);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('repository action is immediately beside page management', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      StyleEditScope(
        controller: mode,
        child: MaterialApp(
          home: Scaffold(body: StyleEditBanner(onManagePages: () async {})),
        ),
      ),
    );
    final pages = find.byKey(const ValueKey('style-edit-banner-pages'));
    final repository = find.byKey(
      const ValueKey('style-edit-banner-repository'),
    );
    expect(repository, findsOneWidget);
    expect(find.byTooltip('Repository'), findsOneWidget);
    expect(tester.getRect(repository).left, tester.getRect(pages).right);
    expect(tester.takeException(), isNull);
  });

  testWidgets('banner moves and retains its position when editing is toggled', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, mode);
    final initial = banner(tester);
    expect(initial.center.dx, 400);
    expect(initial.top, 8);
    await move(tester, const Offset(100, 80));
    final moved = banner(tester);
    expect(moved.left, closeTo(initial.left + 100, 1));
    expect(moved.top, greaterThan(initial.top + 70));

    await tester.tap(find.byKey(const ValueKey('style-edit-banner-close')));
    await tester.pump();
    expect(mode.value, isFalse);
    expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);
    mode.value = true;
    await tester.pump();
    expect(banner(tester), moved);
    await move(tester, const Offset(-50, 30));
    expect(banner(tester).left, closeTo(moved.left - 50, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging is bounded and immediately reverses at the edges', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, mode);
    await move(tester, const Offset(-2000, -2000));
    expect(banner(tester).topLeft, Offset.zero);
    await move(tester, const Offset(30, 30));
    expect(banner(tester).left, 30);
    expect(banner(tester).top, greaterThan(0));
    await move(tester, const Offset(2000, 2000));
    expect(banner(tester).right, 800);
    expect(banner(tester).bottom, 600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('consecutive pointer events accumulate before the next frame', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, mode);
    final initial = banner(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('style-edit-banner-drag'))),
    );
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    final start = banner(tester);
    await gesture.moveBy(const Offset(20, 10));
    await gesture.moveBy(const Offset(30, 15));
    await tester.pump();
    await gesture.up();
    expect(banner(tester).left, initial.left + 50);
    expect(banner(tester).top, start.top + 25);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing keeps the banner in the viewport', (tester) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    addTearDown(tester.view.reset);
    await pump(tester, mode);
    await move(tester, const Offset(2000, 2000));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 240);
    await tester.pumpAndSettle();
    expect(banner(tester).left, greaterThanOrEqualTo(0));
    expect(banner(tester).top, greaterThanOrEqualTo(0));
    expect(banner(tester).right, lessThanOrEqualTo(360));
    expect(banner(tester).bottom, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI chat applies a Vibe response to the current appearance', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier(Appearance());
    final assetBundle = _FallbackGuideBundle();
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    String? prompt;
    await tester.pumpWidget(
      StyleEditScope(
        controller: mode,
        child: AppearanceScope(
          controller: appearance,
          child: AppearanceServicesScope(
            codec: const AppearanceCodec(),
            child: MaterialApp(
              builder: (context, child) => DefaultAssetBundle(
                bundle: assetBundle,
                child: Stack(
                  children: [
                    child!,
                    Positioned.fill(
                      child: StyleEditBanner(
                        aiResponseGenerator: (value) async {
                          prompt = value;
                          return '{"message":"Accent modifié.","vibe":{"accent":"#00AACC"}}';
                        },
                      ),
                    ),
                  ],
                ),
              ),
              home: const Scaffold(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('vibe-chat-input')),
      'Crée un écran moderne.',
    );
    await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
    await tester.pumpAndSettle();

    expect(appearance.value.accent, const Color(0xFF00AACC));
    expect(find.text('Accent modifié.'), findsOneWidget);
    expect(prompt, contains('GUIDE DE MODÉLISATION'));
    expect(
      prompt,
      contains('guide de test disponible uniquement via le chemin de package'),
    );
    expect(assetBundle.loads, [
      'SCREEN_JSON_AI_GUIDE.md',
      'packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md',
    ]);
    expect(prompt, contains('ÉTAT ACTUEL (JSON)'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI chat retries a page with an invalid route path', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier(Appearance());
    final routing = EditorPageRouter(
      baseConfig: RoutingConfig(
        routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
      ),
    );
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    addTearDown(routing.dispose);
    var requests = 0;
    String? retryPrompt;

    await tester.pumpWidget(
      StyleEditScope(
        controller: mode,
        child: AppearanceScope(
          controller: appearance,
          child: AppearanceServicesScope(
            codec: const AppearanceCodec(),
            child: MaterialApp(
              builder: (context, child) => DefaultAssetBundle(
                bundle: _FallbackGuideBundle(),
                child: Stack(
                  children: [
                    child!,
                    Positioned.fill(
                      child: StyleEditBanner(
                        validateAppearance: (value) =>
                            routing.validate(value.pageCatalog),
                        aiResponseGenerator: (prompt) async {
                          requests++;
                          if (requests == 1) {
                            return jsonEncode({
                              'message': 'Créer une page.',
                              'vibe': {
                                'pageCatalog': {
                                  'pages': [
                                    {
                                      'id': 'page-vibe',
                                      'name': 'Page Vibe',
                                      'path': '/bad route',
                                    },
                                  ],
                                },
                              },
                            });
                          }
                          retryPrompt = prompt;
                          return jsonEncode({
                            'message': 'La route a été corrigée.',
                            'vibe': {
                              'pageCatalog': {
                                'pages': [
                                  {
                                    'id': 'page-vibe',
                                    'name': 'Page Vibe',
                                    'path': '/bad-route',
                                  },
                                ],
                              },
                            },
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              home: const Scaffold(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('vibe-chat-input')),
      'Ajoute une page.',
    );
    await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(retryPrompt, contains('CORRECTION REQUISE'));
    expect(appearance.value.pageCatalog.pages.single.path, '/bad-route');
    expect(find.text('La route a été corrigée.'), findsOneWidget);
    expect(find.textContaining('Réponse Vibe invalide'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI chat window can be moved independently', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier(Appearance());
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      StyleEditScope(
        controller: mode,
        child: AppearanceScope(
          controller: appearance,
          child: AppearanceServicesScope(
            codec: const AppearanceCodec(),
            child: MaterialApp(
              builder: (context, child) => Stack(
                children: [
                  child!,
                  const Positioned.fill(child: StyleEditBanner()),
                ],
              ),
              home: const Scaffold(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
    await tester.pumpAndSettle();
    final initial = tester.getRect(
      find.byKey(const ValueKey('vibe-chat-dialog')),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('vibe-chat-drag'))),
    );
    await gesture.moveBy(const Offset(-50, -40));
    await tester.pumpAndSettle();
    await gesture.up();

    final moved = tester.getRect(
      find.byKey(const ValueKey('vibe-chat-dialog')),
    );
    expect(moved.left, closeTo(initial.left - 50, 1));
    expect(moved.top, closeTo(initial.top - 40, 1));
    expect(moved.right, lessThanOrEqualTo(1000));
    expect(moved.bottom, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a growing path stays bounded and its segments remain clickable',
    (tester) async {
      final mode = ValueNotifier(true);
      final owner = Object();
      addTearDown(mode.dispose);
      addTearDown(tester.view.reset);
      addTearDown(() => LayoutSelection.report(owner, const []));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 240);
      await pump(tester, mode);
      await move(tester, const Offset(1000, 1000));
      String? selected;
      LayoutSelection.register(owner, [
        'Disposition avec un titre tres long',
      ], (zone) => selected = zone);
      addTearDown(() => LayoutSelection.unregister(owner));
      LayoutSelection.report(owner, [
        'Disposition avec un titre tres long',
        'Nord',
      ]);
      await tester.pumpAndSettle();
      expect(banner(tester).right, lessThanOrEqualTo(360));
      expect(banner(tester).bottom, lessThanOrEqualTo(240));
      final segment = find.byKey(const ValueKey('style-edit-banner-path-1'));
      await tester.ensureVisible(segment);
      await tester.tap(segment);
      await tester.pump();
      expect(selected, 'Nord');
      await move(tester, const Offset(-20, -20));
      expect(banner(tester).left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    },
  );
}

class _FallbackGuideBundle extends CachingAssetBundle {
  final loads = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    if (key == 'packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md') {
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(
            'guide de test disponible uniquement via le chemin de package',
          ),
        ),
      );
    }
    throw FlutterError('Asset "$key" not found.');
  }
}
