import 'dart:async';
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
import 'package:super_container_layout/widgets/editing/ai/vibe_task_completion_alert.dart';
import 'package:super_container_layout/widgets/editing/overlay/style_edit_banner.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';
import 'package:super_container_layout/widgets/appearance/appearance_scope.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    ValueNotifier<bool> editMode, {
    Alignment? initialAlignment,
    Widget home = const Scaffold(),
  }) => tester.pumpWidget(
    StyleEditScope(
      controller: editMode,
      child: MaterialApp(
        builder: (context, child) => Stack(
          children: [
            child!,
            Positioned.fill(
              child: StyleEditBanner(initialAlignment: initialAlignment),
            ),
          ],
        ),
        home: home,
      ),
    ),
  );

  Future<void> pumpWithAppearance(
    WidgetTester tester,
    ValueNotifier<bool> editMode,
    ValueNotifier<Appearance> appearance, {
    Alignment? initialAlignment,
    double textScale = 1,
  }) => tester.pumpWidget(
    StyleEditScope(
      controller: editMode,
      child: AppearanceScope(
        controller: appearance,
        child: AppearanceServicesScope(
          codec: const AppearanceCodec(),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: Stack(
                children: [
                  child!,
                  Positioned.fill(
                    child: StyleEditBanner(initialAlignment: initialAlignment),
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

  testWidgets('bottom alignment follows the viewport and stays draggable', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    addTearDown(tester.view.reset);
    addTearDown(() => LayoutSelection.editorViewport.value = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    await pump(tester, mode, initialAlignment: Alignment.bottomCenter);
    expect(banner(tester).center.dx, 400);
    expect(banner(tester).bottom, 592);

    LayoutSelection.editorViewport.value = const Rect.fromLTWH(
      100,
      50,
      600,
      400,
    );
    await tester.pumpAndSettle();
    expect(banner(tester).center.dx, 400);
    expect(banner(tester).bottom, 442);
    LayoutSelection.editorViewport.value = null;
    tester.view.physicalSize = const Size(800, 700);
    await tester.pumpAndSettle();
    expect(banner(tester).bottom, 692);

    await move(tester, const Offset(60, -100));
    final moved = banner(tester);
    expect(moved.bottom, lessThan(620));
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-close')));
    await tester.pump();
    mode.value = true;
    await tester.pump();
    expect(banner(tester), moved);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the initial alignment repositions the banner', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, mode);
    expect(banner(tester).top, 8);
    await pump(tester, mode, initialAlignment: Alignment.bottomCenter);
    expect(banner(tester).bottom, 592);
    await pump(tester, mode);
    expect(banner(tester).top, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom banner allows clicks through to the page', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    var clicks = 0;
    await pump(
      tester,
      mode,
      initialAlignment: Alignment.bottomCenter,
      home: Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => clicks++,
            child: const Text('Page action'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Page action'));
    await tester.pump();
    expect(clicks, 1);
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
    expect(prompt, contains('GUIDE DE MODÉLISATION DES REPOSITORIES :'));
    expect(
      prompt,
      contains(
        'guide repositories disponible uniquement via le chemin de package',
      ),
    );
    expect(
      prompt,
      contains(
        'GUIDE DES COMPORTEMENTS (BEHAVIORS, EVENTS, VALIDATORS & ACTIONS) :',
      ),
    );
    expect(
      prompt,
      contains(
        'guide behaviors disponible uniquement via le chemin de package',
      ),
    );
    expect(
      prompt,
      contains('guide design disponible uniquement via le chemin de package'),
    );
    expect(assetBundle.loads, [
      'SCREEN_JSON_AI_GUIDE.md',
      'packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md',
      'REPOSITORY_JSON_AI_GUIDE.md',
      'packages/super_container_layout/REPOSITORY_JSON_AI_GUIDE.md',
      'BEHAVIOR_JSON_AI_GUIDE.md',
      'packages/super_container_layout/BEHAVIOR_JSON_AI_GUIDE.md',
      'SCREEN_DESIGN_AI_GUIDE.md',
      'packages/super_container_layout/SCREEN_DESIGN_AI_GUIDE.md',
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
    await pumpWithAppearance(tester, mode, appearance);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
    await tester.pumpAndSettle();
    final initial = tester.getRect(
      find.byKey(const ValueKey('vibe-chat-dialog')),
    );
    expect(initial.width, 880);
    expect(initial.center.dx, 500);
    expect(initial.overlaps(banner(tester)), isFalse);
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

    // Réduction manuelle en bas à droite : position compacte indépendante du drag étendu
    await tester.tap(find.byKey(const ValueKey('vibe-chat-toggle-expand')));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('vibe-chat-dialog'))),
      const Rect.fromLTWH(544, 184, 440, 600),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom banner remains usable while AI chat is open', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    addTearDown(() => LayoutSelection.editorViewport.value = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier(Appearance());
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    await pumpWithAppearance(
      tester,
      mode,
      appearance,
      initialAlignment: Alignment.bottomCenter,
    );
    await tester.pumpAndSettle();
    final aiButton = find.byKey(const ValueKey('style-edit-banner-ai'));
    final chat = find.byKey(const ValueKey('vibe-chat-dialog'));
    await tester.tap(aiButton);
    await tester.pumpAndSettle();
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);

    tester.view.physicalSize = const Size(400, 320);
    await tester.pumpAndSettle();
    final chatViewport = find.byKey(
      const ValueKey('style-edit-banner-chat-viewport'),
    );
    expect(tester.getRect(chatViewport).overlaps(banner(tester)), isFalse);
    expect(tester.takeException(), isNull);
    expect(
      VibeChatScope.onOpenRequested!(
        const VibeChatScope(componentId: 'page', label: 'Page'),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('vibe-chat-scope-banner')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('vibe-chat-clear-scope')));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(400, 260);
    await tester.pumpAndSettle();
    expect(tester.getRect(chatViewport).overlaps(banner(tester)), isFalse);
    expect(tester.getSize(chatViewport).height, 200);
    expect(tester.getSize(chat).height, 260);
    expect(tester.takeException(), isNull);
    final input = find.byKey(const ValueKey('vibe-chat-input'));
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'Texte dans une petite fenêtre');
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Texte dans une petite fenêtre',
    );
    final send = find.byKey(const ValueKey('vibe-chat-send'));
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(send.hitTestable(), findsOneWidget);
    await tester.tap(aiButton);
    await tester.pumpAndSettle();
    expect(chat, findsNothing);
    await tester.tap(aiButton);
    await tester.pumpAndSettle();
    expect(tester.getRect(chatViewport).overlaps(banner(tester)), isFalse);

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);

    LayoutSelection.editorViewport.value = const Rect.fromLTWH(
      100,
      50,
      700,
      600,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);

    LayoutSelection.editorViewport.value = null;
    await tester.pumpAndSettle();
    await move(tester, const Offset(-60, -200));
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);

    await tester.tap(aiButton);
    await tester.pumpAndSettle();
    expect(chat, findsNothing);

    expect(
      VibeChatScope.onOpenRequested!(
        const VibeChatScope(componentId: 'page', label: 'Page'),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('vibe-chat-scope-banner')),
      findsOneWidget,
    );
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);
    final initialChat = tester.getRect(chat);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('vibe-chat-drag'))),
    );
    await gesture.moveBy(const Offset(-50, 40));
    await tester.pumpAndSettle();
    await gesture.up();
    expect(tester.getRect(chat).left, closeTo(initialChat.left - 50, 1));
    expect(tester.getRect(chat).top, closeTo(initialChat.top + 40, 1));
    await tester.tap(find.byKey(const ValueKey('vibe-chat-close')));
    await tester.pumpAndSettle();
    expect(chat, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a growing bottom banner keeps the AI chat accessible', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier(Appearance());
    final owner = Object();
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    addTearDown(() => LayoutSelection.report(owner, const []));
    await pumpWithAppearance(
      tester,
      mode,
      appearance,
      initialAlignment: Alignment.bottomCenter,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
    await tester.pumpAndSettle();
    final chat = find.byKey(const ValueKey('vibe-chat-dialog'));
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);

    // En mode compact (bas droit), une bannière courte laisse le chat descendre jusqu'en bas (884),
    // puis l'élargissement de la bannière le remonte au-dessus d'elle.
    await tester.tap(find.byKey(const ValueKey('vibe-chat-toggle-expand')));
    await tester.pumpAndSettle();
    expect(tester.getRect(chat).bottom, 884);
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);

    LayoutSelection.report(owner, [
      'Une disposition avec un titre suffisamment long pour elargir la banniere',
      'Nord',
    ]);
    await tester.pumpAndSettle();
    expect(banner(tester).right, greaterThan(tester.getRect(chat).left));
    expect(tester.getRect(chat).bottom, lessThan(banner(tester).top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit top alignment keeps the AI chat below the banner', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier(Appearance());
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    await pumpWithAppearance(
      tester,
      mode,
      appearance,
      initialAlignment: Alignment.topCenter,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
    await tester.pumpAndSettle();
    final chat = tester.getRect(find.byKey(const ValueKey('vibe-chat-dialog')));
    expect(chat.top, greaterThanOrEqualTo(banner(tester).bottom + 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing banner alignment preserves an open AI chat', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier(Appearance());
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    await pumpWithAppearance(tester, mode, appearance);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('vibe-chat-input'));
    await tester.enterText(input, 'brouillon');
    await tester.pumpAndSettle();
    await pumpWithAppearance(
      tester,
      mode,
      appearance,
      initialAlignment: Alignment.bottomCenter,
    );
    await tester.pumpAndSettle();
    final chat = find.byKey(const ValueKey('vibe-chat-dialog'));
    expect(banner(tester).bottom, 592);
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);
    expect(tester.widget<TextField>(input).controller!.text, 'brouillon');
    expect(tester.takeException(), isNull);
  });

  testWidgets('text scaling keeps the bottom banner clear of the AI chat', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1300, 900);
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier(Appearance());
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    await pumpWithAppearance(
      tester,
      mode,
      appearance,
      initialAlignment: Alignment.bottomCenter,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
    await tester.pumpAndSettle();
    final chat = find.byKey(const ValueKey('vibe-chat-dialog'));
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);
    await tester.tap(find.byKey(const ValueKey('vibe-chat-toggle-expand')));
    await tester.pumpAndSettle();
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);
    expect(tester.getRect(chat).bottom, 884);
    await pumpWithAppearance(
      tester,
      mode,
      appearance,
      initialAlignment: Alignment.bottomCenter,
      textScale: 1.75,
    );
    await tester.pumpAndSettle();
    expect(banner(tester).right, greaterThan(tester.getRect(chat).left));
    expect(tester.getRect(chat).bottom, lessThan(banner(tester).top));
    expect(tester.getRect(chat).overlaps(banner(tester)), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom breadcrumb tree remains usable with AI chat open', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    final mode = ValueNotifier(true);
    final appearance = ValueNotifier(Appearance());
    final owner = Object();
    var selections = 0;
    addTearDown(mode.dispose);
    addTearDown(appearance.dispose);
    addTearDown(() => LayoutSelection.report(owner, const []));
    addTearDown(() => LayoutSelection.unregister(owner));
    LayoutSelection.register(
      owner,
      ['Main'],
      (_) {},
      treeBuilder: () => [
        LayoutSelectionNode(
          label: 'Nord',
          path: const ['Main', 'Nord'],
          onSelect: () => selections++,
        ),
      ],
    );
    LayoutSelection.report(owner, ['Main', 'Nord']);
    await pumpWithAppearance(
      tester,
      mode,
      appearance,
      initialAlignment: Alignment.bottomCenter,
    );
    await tester.pumpAndSettle();
    final chevron = find.byKey(const ValueKey('style-edit-banner-chevron-0'));
    final dialog = find.byKey(const ValueKey('style-edit-banner-tree-dialog'));
    final node = find.byKey(
      const ValueKey('style-edit-banner-tree-node-Main/Nord'),
    );
    await tester.tap(chevron);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(dialog).bottom,
      lessThan(tester.getRect(chevron).top),
    );
    await tester.tap(node);
    await tester.pumpAndSettle();
    expect(selections, 1);

    await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('vibe-chat-input'));
    await tester.enterText(input, 'brouillon');
    await tester.pumpAndSettle();
    await tester.tap(chevron);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('style-edit-banner-tree-close')),
    );
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(tester.widget<TextField>(input).controller!.text, 'brouillon');
    await tester.tap(chevron);
    await tester.pumpAndSettle();
    await tester.tap(node);
    await tester.pumpAndSettle();
    expect(selections, 2);
    expect(tester.widget<TextField>(input).controller!.text, 'brouillon');
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
      expect(selected, isNull);
      await move(tester, const Offset(-20, -20));
      expect(banner(tester).left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AI chat wizard expands in the center during question phases and shrinks to bottom-right during AI construction',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);

      final mode = ValueNotifier(true);
      final appearance = ValueNotifier(Appearance());
      addTearDown(mode.dispose);
      addTearDown(appearance.dispose);

      var turn = 0;
      late Completer<String> constructionCompleter;

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
                          aiResponseGenerator: (_) {
                            turn++;
                            if (turn == 1 || turn == 3) {
                              return Future.value(
                                jsonEncode({
                                  'message': 'Précise le style souhaité :',
                                  'askUser': {
                                    'questions': [
                                      {
                                        'id': 'theme_choice',
                                        'title': 'Palette principale',
                                        'type': 'single',
                                        'options': [
                                          'Océan profond',
                                          'Forêt boréale',
                                          'Ambre solaire',
                                        ],
                                        'default': 'Océan profond',
                                      },
                                    ],
                                  },
                                  'vibe': null,
                                }),
                              );
                            }
                            constructionCompleter = Completer<String>();
                            return constructionCompleter.future;
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

      // 1. Ouverture : wizard centré sur presque tout l'écran (88% de 1200 = 1056px)
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-ai')));
      await tester.pumpAndSettle();
      final chatFinder = find.byKey(const ValueKey('vibe-chat-dialog'));
      final openRect = tester.getRect(chatFinder);
      expect(openRect.width, 1056);
      expect(openRect.center.dx, 600);
      expect(openRect.height, greaterThan(700));
      expect(openRect.overlaps(banner(tester)), isFalse);

      // 2. Envoi initial -> l'IA répond avec un questionnaire askUser : reste grand et centré,
      // et la carte de questions profite de la grande largeur (> 700px au lieu de 340px)
      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Crée un écran d’accueil.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      final askRect = tester.getRect(chatFinder);
      expect(askRect.width, 1056);
      expect(askRect.center.dx, 600);
      final askCardRect = tester.getRect(
        find.byKey(const ValueKey('vibe-ask-user-card')),
      );
      expect(askCardRect.width, greaterThan(700));

      // 3. Validation des questions -> entrée immédiate en phase de construction IA :
      // le wizard se réduit en bas à droite (440 × 600) avant même la fin de la réponse !
      await tester.tap(find.byKey(const ValueKey('vibe-ask-user-skip')));
      await tester.pump();
      expect(
        tester.getRect(chatFinder),
        const Rect.fromLTWH(1200 - 440 - 16, 900 - 600 - 16, 440, 600),
      );

      // La construction se termine : le panneau reste réduit en bas à droite pour laisser voir l'écran
      constructionCompleter.complete(
        '{"message":"Écran construit.","vibe":{"accent":"#0EA5E9"}}',
      );
      await tester.pumpAndSettle();
      expect(appearance.value.accent, const Color(0xFF0EA5E9));
      expect(
        tester.getRect(chatFinder),
        const Rect.fromLTWH(1200 - 440 - 16, 900 - 600 - 16, 440, 600),
      );

      // 4. Nouvelle demande déclenchant une nouvelle phase de questions -> se ré-agrandit au centre !
      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Ajoute une section analytique.',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pumpAndSettle();

      final reExpandedRect = tester.getRect(chatFinder);
      expect(reExpandedRect.width, 1056);
      expect(reExpandedRect.center.dx, 600);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'affiche une pastille et un toast visuel sur la bannière lorsqu’une tâche IA se termine chat fermé',
    (tester) async {
      final mode = ValueNotifier(true);
      final appearance = ValueNotifier(Appearance());
      addTearDown(mode.dispose);
      addTearDown(appearance.dispose);
      addTearDown(VibeTaskCompletionController.instance.dismiss);

      await pumpWithAppearance(tester, mode, appearance);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('style-edit-banner-ai-badge')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('style-edit-banner-ai-toast')),
        findsNothing,
      );

      VibeTaskCompletionController.instance.notifyCompleted(
        outcome: VibeTaskOutcome.success,
        title: 'Tâche IA terminée',
        detail: 'Écran généré avec succès.',
        playSound: false,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('style-edit-banner-ai-badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('style-edit-banner-ai-toast')),
        findsOneWidget,
      );
      expect(find.text('Tâche IA terminée'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('vibe-chat-completion-dismiss')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('style-edit-banner-ai-badge')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('style-edit-banner-ai-toast')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edit banner dial adjusts global binding debounce and blur-only save mode',
    (tester) async {
      final mode = ValueNotifier(true);
      final appearance = ValueNotifier(Appearance());
      addTearDown(mode.dispose);
      addTearDown(appearance.dispose);

      await pumpWithAppearance(tester, mode, appearance);
      await tester.pumpAndSettle();

      final settingsButton = find.byKey(
        const ValueKey('style-edit-banner-settings'),
      );
      expect(settingsButton, findsOneWidget);
      expect(
        find.byKey(const ValueKey('style-edit-banner-transfer')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('style-edit-banner-save-timing')),
        findsNothing,
      );

      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('style-edit-banner-transfer')),
        findsOneWidget,
      );
      final button = find.byKey(
        const ValueKey('style-edit-banner-save-timing'),
      );
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('binding-save-timing-dialog')),
        findsOneWidget,
      );
      final slider = find.byKey(const ValueKey('global-save-timing-slider'));
      await tester.drag(slider, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(appearance.value.bindingDebounceMs, greaterThan(350));
      expect(appearance.value.bindingDebounceMs % 50, 0);

      await tester.tap(
        find.byKey(const ValueKey('global-save-timing-blur-only')),
      );
      await tester.pumpAndSettle();
      expect(appearance.value.bindingSaveOnBlurOnly, isTrue);
      expect(tester.widget<Slider>(slider).onChanged, isNull);

      await tester.tap(find.byKey(const ValueKey('global-save-timing-reset')));
      await tester.pumpAndSettle();
      expect(appearance.value.bindingDebounceMs, 350);
      expect(appearance.value.bindingSaveOnBlurOnly, isFalse);

      await tester.tap(find.byKey(const ValueKey('binding-save-timing-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('binding-save-timing-dialog')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'F1 toggles global AI chat outside edit mode without enabling edit mode and ignores modified F1',
    (tester) async {
      final mode = ValueNotifier(false);
      final appearance = ValueNotifier(Appearance());
      addTearDown(mode.dispose);
      addTearDown(appearance.dispose);

      await pumpWithAppearance(tester, mode, appearance);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);
      expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsNothing);

      // Ctrl+F1, Alt+F1 et Shift+F1 sont ignorés.
      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.shiftLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsNothing);
      }

      // F1 hors mode édition ouvre le chat IA sans activer le mode édition ni afficher la bannière.
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(mode.value, isFalse);
      expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);
      expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('vibe-chat-scope-banner')),
        findsNothing,
      );

      // Un second appui sur F1 referme le chat IA.
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(mode.value, isFalse);
      expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'F1 toggles global AI chat in edit mode even when a component is selected',
    (tester) async {
      final mode = ValueNotifier(true);
      final appearance = ValueNotifier(Appearance());
      addTearDown(mode.dispose);
      addTearDown(appearance.dispose);
      addTearDown(() => LayoutSelection.select(const []));

      await pumpWithAppearance(tester, mode, appearance);
      await tester.pumpAndSettle();

      LayoutSelection.select(const ['Page', 'Corps', 'Carte']);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-edit-banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('vibe-chat-scope-banner')),
        findsNothing,
      );

      // Un second appui sur F1 referme le chat tout en gardant le mode édition actif.
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(mode.value, isTrue);
      expect(find.byKey(const ValueKey('style-edit-banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'F12 toggles edit mode and ignores modified F12 combinations',
    (tester) async {
      final mode = ValueNotifier(false);
      final appearance = ValueNotifier(Appearance());
      addTearDown(mode.dispose);
      addTearDown(appearance.dispose);

      await pumpWithAppearance(tester, mode, appearance);
      await tester.pumpAndSettle();

      expect(mode.value, isFalse);
      expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);

      // Ctrl+F12, Alt+F12, Shift+F12 et Meta+F12 sont ignorés.
      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.f12);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(mode.value, isFalse);
        expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);
      }

      // F12 ouvre le mode édition et affiche la bannière.
      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.pumpAndSettle();
      expect(mode.value, isTrue);
      expect(find.byKey(const ValueKey('style-edit-banner')), findsOneWidget);

      // Un second appui sur F12 referme le mode édition.
      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.pumpAndSettle();
      expect(mode.value, isFalse);
      expect(find.byKey(const ValueKey('style-edit-banner')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'F3 opens page manager even outside edit mode, guards against re-entry and ignores modified F3',
    (tester) async {
      final mode = ValueNotifier(false);
      addTearDown(mode.dispose);
      var openCalls = 0;
      Completer<void>? pendingOpen;

      await tester.pumpWidget(
        StyleEditScope(
          controller: mode,
          child: MaterialApp(
            home: Scaffold(
              body: StyleEditBanner(
                onManagePages: () {
                  openCalls++;
                  pendingOpen = Completer<void>();
                  return pendingOpen!.future;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Modificateurs ignorés.
      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.f3);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(openCalls, 0);
      }

      // F3 déclenche onManagePages hors mode édition et ignore les appuis répétés tant qu'il est ouvert.
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pump();
      expect(openCalls, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pump();
      expect(openCalls, 1);

      pendingOpen!.complete();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pump();
      expect(openCalls, 2);

      pendingOpen!.complete();
      await tester.pumpAndSettle();
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
    if (key == 'packages/super_container_layout/REPOSITORY_JSON_AI_GUIDE.md') {
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(
            'guide repositories disponible uniquement via le chemin de package',
          ),
        ),
      );
    }
    if (key == 'packages/super_container_layout/BEHAVIOR_JSON_AI_GUIDE.md') {
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(
            'guide behaviors disponible uniquement via le chemin de package',
          ),
        ),
      );
    }
    if (key == 'packages/super_container_layout/SCREEN_DESIGN_AI_GUIDE.md') {
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(
            'guide design disponible uniquement via le chemin de package',
          ),
        ),
      );
    }
    throw FlutterError('Asset "$key" not found.');
  }
}
