import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_chat_widgets.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_prompt_builder.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_scope_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VibeMountedSlotIndex.instance.clearForTesting();
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    VibeMountedSlotIndex.instance.clearForTesting();
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('EditorLassoResolver', () {
    test('rejects micro-clicks and accepts intentional strokes', () {
      expect(EditorLassoResolver.isValidStroke(const [Offset(10, 10)]), isFalse);
      expect(
        EditorLassoResolver.isValidStroke(const [
          Offset(10, 10),
          Offset(13, 12),
        ]),
        isFalse,
      );
      expect(
        EditorLassoResolver.isValidStroke(const [
          Offset(10, 10),
          Offset(30, 10),
        ]),
        isTrue,
      );
    });

    test(
      'selects deepest intersected children and drops enclosing layout ancestors',
      () {
        const candidates = [
          EditorLassoCandidate(
            target: VibeChatScopeTarget(componentId: 'root', label: 'Page'),
            rect: Rect.fromLTWH(0, 0, 800, 600),
            depth: 0,
            isRoot: true,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'mainLayout',
              label: 'Main Layout',
              zoneId: 'center',
              zoneLabel: 'Centre',
            ),
            rect: Rect.fromLTWH(0, 0, 800, 600),
            depth: 1,
            parentIndex: 0,
            isZone: true,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'card-1',
              label: 'Carte 1',
              parentComponentId: 'mainLayout',
            ),
            rect: Rect.fromLTWH(40, 40, 260, 200),
            depth: 2,
            parentIndex: 1,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'title-1',
              label: 'Titre 1',
              parentComponentId: 'card-1',
            ),
            rect: Rect.fromLTWH(60, 60, 140, 24),
            depth: 3,
            parentIndex: 2,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'subtitle-1',
              label: 'Sous-titre 1',
              parentComponentId: 'card-1',
            ),
            rect: Rect.fromLTWH(60, 96, 140, 24),
            depth: 3,
            parentIndex: 2,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'btn-1',
              label: 'Bouton 1',
              parentComponentId: 'card-1',
            ),
            rect: Rect.fromLTWH(60, 180, 100, 36),
            depth: 3,
            parentIndex: 2,
          ),
        ];

        final resolution = EditorLassoResolver.resolveSelection(
          candidates: candidates,
          strokes: const [
            [
              Offset(50, 72),
              Offset(210, 72),
              Offset(210, 108),
              Offset(50, 108),
            ],
          ],
        );

        expect(resolution, isNotNull);
        expect(
          resolution!.selectedCandidates.map((c) => c.target.componentId),
          ['title-1', 'subtitle-1'],
        );
        expect(resolution.scope.isMultiTarget, isTrue);
        expect(resolution.scope.canonicalComponentIds, {
          'title-1',
          'subtitle-1',
        });
      },
    );

    test(
      'consolidates enclosed container when all 4 corners lie inside the lasso',
      () {
        const candidates = [
          EditorLassoCandidate(
            target: VibeChatScopeTarget(componentId: 'root', label: 'Page'),
            rect: Rect.fromLTWH(0, 0, 800, 600),
            depth: 0,
            isRoot: true,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'mainLayout',
              label: 'Main Layout',
              zoneId: 'center',
              zoneLabel: 'Centre',
            ),
            rect: Rect.fromLTWH(0, 0, 800, 600),
            depth: 1,
            parentIndex: 0,
            isZone: true,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'card-1',
              label: 'Carte 1',
              parentComponentId: 'mainLayout',
            ),
            rect: Rect.fromLTWH(40, 40, 200, 120),
            depth: 2,
            parentIndex: 1,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'title-1',
              label: 'Titre 1',
              parentComponentId: 'card-1',
            ),
            rect: Rect.fromLTWH(60, 60, 140, 24),
            depth: 3,
            parentIndex: 2,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'card-2',
              label: 'Carte 2',
              parentComponentId: 'mainLayout',
            ),
            rect: Rect.fromLTWH(320, 40, 200, 120),
            depth: 2,
            parentIndex: 1,
          ),
        ];

        final resolution = EditorLassoResolver.resolveSelection(
          candidates: candidates,
          strokes: const [
            // Boucle englobant entièrement card-1 sans toucher card-2.
            [
              Offset(20, 20),
              Offset(260, 20),
              Offset(260, 180),
              Offset(20, 180),
            ],
          ],
        );

        expect(resolution, isNotNull);
        expect(
          resolution!.selectedCandidates.map((c) => c.target.componentId),
          ['card-1'],
        );
        expect(resolution.scope.isMultiTarget, isFalse);
        expect(resolution.scope.componentId, 'card-1');
      },
    );

    test(
      'falls back to empty zone and combines multiple strokes while deduplicating',
      () {
        const candidates = [
          EditorLassoCandidate(
            target: VibeChatScopeTarget(componentId: 'root', label: 'Page'),
            rect: Rect.fromLTWH(0, 0, 800, 600),
            depth: 0,
            isRoot: true,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'mainLayout',
              label: 'Main Layout',
              zoneId: 'west',
              zoneLabel: 'Ouest',
            ),
            rect: Rect.fromLTWH(0, 0, 200, 600),
            depth: 1,
            parentIndex: 0,
            isZone: true,
          ),
          EditorLassoCandidate(
            target: VibeChatScopeTarget(
              componentId: 'btn-save',
              label: 'Enregistrer',
              parentComponentId: 'mainLayout',
            ),
            rect: Rect.fromLTWH(400, 200, 120, 40),
            depth: 2,
            parentIndex: 0,
          ),
        ];

        final zoneOnly = EditorLassoResolver.resolveSelection(
          candidates: candidates,
          strokes: const [
            [Offset(40, 40), Offset(120, 40), Offset(120, 120)],
          ],
        );
        expect(zoneOnly, isNotNull);
        expect(zoneOnly!.scope.componentId, 'mainLayout');
        expect(zoneOnly.scope.zoneId, 'west');

        final combined = EditorLassoResolver.resolveSelection(
          candidates: candidates,
          strokes: const [
            [Offset(40, 40), Offset(120, 40), Offset(120, 120)],
            [Offset(390, 220), Offset(530, 220)],
            [Offset(410, 210), Offset(450, 230)],
          ],
        );
        expect(combined, isNotNull);
        expect(combined!.scope.allTargets, hasLength(2));
        expect(
          combined.scope.allTargets.map((t) => (t.componentId, t.zoneId)),
          [('mainLayout', 'west'), ('btn-save', null)],
        );
      },
    );
  });

  group('Multi-target VibeChatScope helpers', () {
    test(
      'filterPatchToScope and exportScopedAi isolate selected siblings and protect unselected siblings',
      () {
        final initial = AppearanceTransfer.applyVibe(
          Appearance(),
          jsonEncode({
            'styles': {
              'background': {'color': '#111827'},
              'card-1': {'color': '#FFFFFF', 'radius': 8},
              'card-2': {'color': '#FFFFFF', 'radius': 8},
              'card-3': {'color': '#FFFFFF', 'radius': 8},
            },
            'components': {
              'mainLayout': {
                'type': 'layout',
                'placements': {
                  'center': [
                    {'id': 'card-1', 'type': 'registry:Card'},
                    {'id': 'card-2', 'type': 'registry:Card'},
                    {'id': 'card-3', 'type': 'registry:Card'},
                  ],
                },
              },
              'card-1': {
                'type': 'native',
                'regions': {'child': true},
                'placements': {
                  'child': [
                    {'id': 'title-1', 'type': 'registry:Value'},
                  ],
                },
              },
              'title-1': {'type': 'value', 'text': 'Carte 1'},
              'card-2': {
                'type': 'native',
                'regions': {'child': true},
                'placements': {
                  'child': [
                    {'id': 'title-2', 'type': 'registry:Value'},
                  ],
                },
              },
              'title-2': {'type': 'value', 'text': 'Carte 2'},
              'card-3': {
                'type': 'native',
                'regions': {'child': true},
                'placements': {
                  'child': [
                    {'id': 'title-3', 'type': 'registry:Value'},
                  ],
                },
              },
              'title-3': {'type': 'value', 'text': 'Carte 3 intacte'},
            },
          }),
        );

        final scope = VibeChatScope.fromTargets(const [
          VibeChatScopeTarget(
            componentId: 'card-1',
            label: 'Carte 1',
            parentComponentId: 'mainLayout',
          ),
          VibeChatScopeTarget(
            componentId: 'card-2',
            label: 'Carte 2',
            parentComponentId: 'mainLayout',
          ),
        ]);

        final exported =
            jsonDecode(VibeScopeHelpers.exportScopedAi(initial, scope))
                as Map<String, dynamic>;
        final exportedComponents =
            exported['components'] as Map<String, dynamic>;
        expect(exportedComponents.keys, containsAll(['mainLayout', 'card-1', 'title-1', 'card-2', 'title-2']));
        expect(exportedComponents.containsKey('card-3'), isFalse);
        expect(exportedComponents.containsKey('title-3'), isFalse);

        final prompt = VibePromptBuilder.buildTurnPrompt(
          questioningDirective: 'Aucune question.',
          conversation: 'Aligne Carte 1 et Carte 2',
          appearance: initial,
          codec: const AppearanceCodec(),
          scope: scope,
        );
        expect(prompt, contains('SÉLECTION LASSO MULTI-CIBLES'));
        expect(prompt, contains('Carte 1'));
        expect(prompt, contains('Carte 2'));

        final aiPatch = <String, dynamic>{
          'mode': 'dark',
          'accent': '#FF0000',
          'styles': {
            'background': {'color': '#000000'},
            'mainLayout': {'color': '#123456'},
            'card-1': {'radius': 20},
            'card-2': {'radius': 20},
            'card-3': {'radius': 40},
          },
          'components': {
            'card-1': {'type': 'native', 'regions': {'child': true}, 'placements': {'child': [{'id': 'title-1', 'type': 'registry:Value'}]}},
            'title-1': {'text': 'Carte 1 modifiée'},
            'title-2': {'text': 'Carte 2 modifiée'},
            'card-3': null,
            'title-3': {'text': 'Piraté'},
          },
        };

        final filtered = VibeScopeHelpers.filterPatchToScope(
          initial,
          aiPatch,
          scope,
        );
        final updated = AppearanceTransfer.applyVibe(
          initial,
          jsonEncode(filtered),
        );

        expect(updated.style('card-1').radius, 20);
        expect(updated.style('card-2').radius, 20);
        expect(updated.valueComponent('title-1').initialText, 'Carte 1 modifiée');
        expect(updated.valueComponent('title-2').initialText, 'Carte 2 modifiée');

        // Hors scope et frères non sélectionnés préservés :
        expect(updated.backgroundStyle.color, const Color(0xFF111827));
        expect(updated.styles.containsKey('mainLayout'), isFalse);
        expect(updated.style('card-3').radius, 8);
        expect(updated.valueComponent('title-3').initialText, 'Carte 3 intacte');
      },
    );
  });

  group('Widget lasso integration in EditorZoom & StyleEditBanner', () {
    Future<({Registry registry, ValueNotifier<bool> editMode})> pumpLassoApp(
      WidgetTester tester,
    ) async {
      final registry = Registry()..bootstrap();
      addTearDown(registry.unbindAppearance);

      final initialAppearance = AppearanceTransfer.applyVibe(
        Appearance(),
        jsonEncode({
          'components': {
            'mainLayout': {
              'type': 'layout',
              'north': false,
              'south': false,
              'west': false,
              'east': false,
              'slotLabels': {
                'title-a': 'Titre A',
                'action-b': 'Action B',
                'title-c': 'Titre C',
              },
              'placements': {
                'center': [
                  {'id': 'title-a', 'type': 'registry:Value'},
                  {'id': 'action-b', 'type': 'registry:Action'},
                  {'id': 'title-c', 'type': 'registry:Value'},
                ],
              },
            },
            'title-a': {'type': 'value', 'text': 'Titre A'},
            'action-b': {'type': 'action', 'label': 'Action B'},
            'title-c': {'type': 'value', 'text': 'Titre C'},
          },
        }),
      );

      final store = _MemoryAppearanceStore(initialAppearance);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) {
              final layoutCtrl = SuperApp.of(
                context,
              ).getLayoutConfigById('mainLayout');
              return SuperPage(
                maxAutoZoomExtent: 1000,
                child: ValueListenableBuilder<SuperLayoutConfig>(
                  valueListenable: layoutCtrl,
                  builder: (_, cfg, _) => SuperLayout(
                    id: 'mainLayout',
                    label: 'Main Layout',
                    config: cfg,
                    onChanged: (next) => layoutCtrl.value = next,
                  ),
                ),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(
          router: router,
          registry: registry,
          appearanceStore: store,
          editorBannerAlignment: Alignment.bottomCenter,
        ),
      );
      await tester.pumpAndSettle();

      final editMode = StyleEditScope.controllerOf(
        tester.element(find.byType(SuperPage)),
      )!;
      return (registry: registry, editMode: editMode);
    }

    Future<void> drawMouseStroke(
      WidgetTester tester,
      Offset start,
      Offset end,
    ) async {
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      await tester.pump();
      await gesture.moveTo(Offset((start.dx + end.dx) / 2, end.dy));
      await tester.pump();
      await gesture.moveTo(end);
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    testWidgets(
      'Ctrl alone or outside edit mode does not open VibeChatDialog; multi-stroke Ctrl+drag opens VibeChatDialog on Ctrl release and updates scope when reopened',
      (tester) async {
        final ctx = await pumpLassoApp(tester);

        // Hors mode édition : Ctrl + drag ne fait rien.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(find.byKey(const ValueKey('editor-lasso-layer')), findsNothing);
        await drawMouseStroke(
          tester,
          const Offset(20, 20),
          const Offset(240, 80),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsNothing);

        // Active le mode édition.
        ctx.editMode.value = true;
        await tester.pumpAndSettle();

        // Ctrl seul (ex. avant Ctrl+Z) sans tracé ne déclenche pas le chat.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(find.byKey(const ValueKey('editor-lasso-layer')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('editor-lasso-status-pill')),
          findsNothing,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsNothing);

        final rectA = tester.getRect(find.text('Titre A'));
        final rectB = tester.getRect(find.text('Action B'));

        // Maintient Ctrl, dessine deux tracés distincts sur Titre A puis Action B.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        await drawMouseStroke(
          tester,
          Offset((rectA.left - 16).clamp(2.0, 790.0), rectA.center.dy),
          Offset((rectA.right + 16).clamp(20.0, 798.0), rectA.center.dy),
        );
        expect(
          find.byKey(const ValueKey('editor-lasso-status-pill')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsNothing);

        await drawMouseStroke(
          tester,
          Offset((rectB.left - 16).clamp(2.0, 790.0), rectB.center.dy),
          Offset((rectB.right + 16).clamp(20.0, 798.0), rectB.center.dy),
        );
        expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsNothing);

        // Relâche Ctrl -> ouvre VibeChatDialog avec les 2 éléments dans le scope.
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('vibe-chat-scope-banner')),
          findsOneWidget,
        );
        expect(find.textContaining('2 éléments'), findsOneWidget);

        VibeSpeedModeChip speedChip(VibeAiSpeedMode mode) => tester
            .widgetList<VibeSpeedModeChip>(find.byType(VibeSpeedModeChip))
            .firstWhere((c) => c.mode == mode);

        // Le mode lasso bascule automatiquement en mode Éclair + questionnement à 0.
        expect(speedChip(VibeAiSpeedMode.ultraFast).selected, isTrue);
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('vibe-chat-questioning-slider')),
              )
              .value,
          0.0,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('vibe-chat-questioning-label')),
            matching: find.text('Aucun'),
          ),
          findsOneWidget,
        );

        // L'utilisateur repasse manuellement en Raisonnement + Approfondi,
        // puis réduit le chat et refait un lasso : il repasse en Éclair + 0.
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is VibeSpeedModeChip && w.mode == VibeAiSpeedMode.reasoning,
          ),
        );
        await tester.pump();
        tester
            .widget<Slider>(
              find.byKey(const ValueKey('vibe-chat-questioning-slider')),
            )
            .onChanged!(3);
        await tester.pump();
        expect(speedChip(VibeAiSpeedMode.reasoning).selected, isTrue);

        // Réduit le chat en bas à droite, puis redessine un lasso sur Titre A uniquement.
        await tester.tap(
          find.byKey(const ValueKey('vibe-chat-toggle-expand')),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await drawMouseStroke(
          tester,
          Offset((rectA.left - 12).clamp(2.0, 790.0), rectA.center.dy),
          Offset((rectA.right + 12).clamp(20.0, 798.0), rectA.center.dy),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('vibe-chat-scope-banner')),
          findsOneWidget,
        );
        expect(find.textContaining('2 éléments'), findsNothing);
        expect(find.text('Scope : Titre A'), findsOneWidget);
        expect(speedChip(VibeAiSpeedMode.ultraFast).selected, isTrue);
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('vibe-chat-questioning-slider')),
              )
              .value,
          0.0,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('vibe-chat-questioning-label')),
            matching: find.text('Aucun'),
          ),
          findsOneWidget,
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Escape cancels active lasso without opening VibeChatDialog', (
      tester,
    ) async {
      final ctx = await pumpLassoApp(tester);
      ctx.editMode.value = true;
      await tester.pumpAndSettle();

      final rectA = tester.getRect(find.text('Titre A'));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await drawMouseStroke(
        tester,
        Offset((rectA.left - 12).clamp(2.0, 790.0), rectA.center.dy),
        Offset((rectA.right + 12).clamp(20.0, 798.0), rectA.center.dy),
      );
      expect(
        find.byKey(const ValueKey('editor-lasso-status-pill')),
        findsOneWidget,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('editor-lasso-status-pill')),
        findsNothing,
      );

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('vibe-chat-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

class _MemoryAppearanceStore extends AppearanceStore {
  _MemoryAppearanceStore(this._value);

  Appearance _value;

  @override
  Future<Appearance> load() async => _value;

  @override
  Future<void> save(Appearance value) async {
    _value = value;
  }
}
