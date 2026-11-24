import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/component_config.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/models/super_action_config.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_tab_config.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/services/appearance/appearance_codec.dart';
import 'package:super_container_layout/services/appearance/appearance_store.dart';
import 'package:super_container_layout/services/inspection/vibe_app_inspector.dart';
import 'package:super_container_layout/services/inspection/vibe_diagnostics_inspector.dart';
import 'package:super_container_layout/services/inspection/vibe_mounted_slot_index.dart';
import 'package:super_container_layout/services/inspection/vibe_page_audit.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/appearance/appearance_scope.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_chat_dialog.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_prompt_builder.dart';

class _GuideBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final text = key.contains('DESIGN')
        ? 'Design de test.'
        : key.contains('REPOSITORY')
        ? 'Repositories de test.'
        : 'Guide de test.';
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

class _MemoryAppearanceStore extends AppearanceStore {
  _MemoryAppearanceStore(this.initial);

  final Appearance initial;

  @override
  Future<Appearance> load() async => initial;

  @override
  Future<void> save(Appearance appearance) async {}
}

void main() {
  testWidgets(
    'VibePageAuditService detects parent clipping, truncated text and excessive fixed-size margins',
    (tester) async {
      final slotIndex = VibeMountedSlotIndex.instance;
      final appKey = GlobalKey();
      final clippedSlotKey = GlobalKey();
      final clippedContentKey = GlobalKey();
      final truncatedSlotKey = GlobalKey();
      final truncatedContentKey = GlobalKey();
      final tokenClipped = Object();
      final tokenTruncated = Object();
      addTearDown(() {
        slotIndex.unregister(tokenClipped);
        slotIndex.unregister(tokenTruncated);
        slotIndex.unregisterAppRoot(appKey);
      });

      final appearance = Appearance(
        components: <String, ComponentConfig>{
          'root': const SuperLayoutConfig(
            placements: <SuperLayoutZone, List<String>>{
              SuperLayoutZone.center: <String>['clipped-card', 'truncated-kpi'],
            },
            slotTypes: <String, String>{
              'clipped-card': 'registry:Value',
              'truncated-kpi': 'registry:Value',
            },
            slotSizeConstraints: <String, SlotSizeConstraints>{
              'clipped-card': SlotSizeConstraints(
                preferredWidth: SlotDimension(100, SlotSizeUnit.pixels),
                preferredHeight: SlotDimension(40, SlotSizeUnit.pixels),
                fitContent: false,
              ),
            },
          ),
          'clipped-card': const SuperValueConfig(initialText: 'Carte'),
          'truncated-kpi': const SuperValueConfig(
            initialText:
                'Libelle beaucoup trop long pour tenir dans cent pixels',
          ),
        },
        styles: const <String, ContainerStyle>{
          // 50 px de marge/padding de chaque côté sur 100 px -> 0 px restant !
          'clipped-card': ContainerStyle(margin: 25, padding: 25),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              key: appKey,
              width: 400,
              height: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Simule un parent clippé (100x40) avec un enfant qui déborde (180x60)
                  ClipRect(
                    child: SizedBox(
                      key: clippedSlotKey,
                      width: 100,
                      height: 40,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: 0,
                        maxWidth: 250,
                        minHeight: 0,
                        maxHeight: 100,
                        child: SizedBox(
                          key: clippedContentKey,
                          width: 180,
                          height: 60,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    key: truncatedSlotKey,
                    width: 90,
                    height: 24,
                    child: SizedBox(
                      key: truncatedContentKey,
                      width: 90,
                      height: 24,
                      child: const Text(
                        'Libelle beaucoup trop long pour tenir dans cent pixels',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      slotIndex.registerAppRoot(appKey);
      slotIndex.register(
        VibeMountedSlotEntry(
          token: tokenClipped,
          componentId: 'clipped-card',
          zoneId: null,
          label: 'clipped-card',
          componentType: 'value',
          scrollable: false,
          fixedWidth: true,
          fixedHeight: true,
          slotContext: () => clippedSlotKey.currentContext,
          contentKey: clippedContentKey,
        ),
      );
      slotIndex.register(
        VibeMountedSlotEntry(
          token: tokenTruncated,
          componentId: 'truncated-kpi',
          zoneId: null,
          label: 'truncated-kpi',
          componentType: 'value',
          scrollable: false,
          fixedWidth: true,
          fixedHeight: true,
          slotContext: () => truncatedSlotKey.currentContext,
          contentKey: truncatedContentKey,
        ),
      );

      final inspector = VibeAppInspector(
        readAppearance: () => appearance,
        slotIndex: slotIndex,
      );
      final report = await VibePageAuditService.collect(inspector);

      expect(report.isClean, isFalse);
      final kinds = report.findings.map((f) => f.kind).toSet();
      expect(
        kinds,
        containsAll(<String>[
          'exceeds_parent_bounds',
          'clipped_by_ancestor',
          'truncated_text',
          'excessive_margin_or_padding_for_fixed_size',
        ]),
      );
      final summary = report.toPromptSummary();
      expect(summary, contains('clipped-card'));
      expect(summary, contains('truncated-kpi'));
    },
  );

  test('VibePageAuditService detects missing @calculs bindings and undeclared calculated attributes', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = await Directory.systemTemp.createTemp('vibe_audit_calc_');
    final repoStore = JsonRepositoryStore(tempDir);
    addTearDown(() async {
      repoStore.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    repoStore.registerRepository(
      RepositoryImpl(
        id: 'ventes',
        json: const <String, Object?>{
          'lignes': <Map<String, Object?>>[
            {'montant': 120},
            {'montant': 80},
          ],
        },
      ),
    );

    final appearance = Appearance(
      components: <String, ComponentConfig>{
        'root': const SuperLayoutConfig(
          placements: <SuperLayoutZone, List<String>>{
            SuperLayoutZone.center: <String>['kpi-total-ventes', 'kpi-marge'],
          },
          slotTypes: <String, String>{
            'kpi-total-ventes': 'registry:Value',
            'kpi-marge': 'registry:Value',
          },
        ),
        'kpi-total-ventes': const SuperValueConfig(
          label: 'Total des ventes',
          initialText: '0 €',
        ),
        'kpi-marge': const SuperValueConfig(
          label: 'Marge nette',
          binding: JsonTextBinding(
            repositoryId: 'ventes',
            path: '@calculs.margeNette',
          ),
        ),
      },
    );

    final inspector = VibeAppInspector(
      readAppearance: () => appearance,
      repositoryStore: repoStore,
    );
    final report = await VibePageAuditService.collect(inspector);

    expect(report.isClean, isFalse);
    expect(
      report.findings.any(
        (f) =>
            f.componentId == 'kpi-total-ventes' &&
            f.kind == 'suspected_missing_calculation' &&
            f.category == VibeAuditCategory.missingCalculation,
      ),
      isTrue,
    );
    expect(
      report.findings.any(
        (f) =>
            f.componentId == 'kpi-marge' &&
            f.kind == 'undeclared_calculated_attribute' &&
            f.category == VibeAuditCategory.missingCalculation,
      ),
      isTrue,
    );
  });

  testWidgets(
    'VibeChatDialog Audit & correction chip runs pre-audit, builds VibeExecutionPlan and executes fix lot',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final registry = Registry()..bootstrap();
      final initialAppearance = Appearance(
        components: <String, ComponentConfig>{
          'mainLayout': const SuperLayoutConfig(
            placements: <SuperLayoutZone, List<String>>{
              SuperLayoutZone.center: <String>['kpi-total'],
            },
            slotTypes: <String, String>{'kpi-total': 'registry:Value'},
            slotSizeConstraints: <String, SlotSizeConstraints>{
              'kpi-total': SlotSizeConstraints(
                preferredWidth: SlotDimension(60, SlotSizeUnit.pixels),
                fitContent: false,
              ),
            },
          ),
          'kpi-total': const SuperValueConfig(
            label: 'Total mensuel',
            initialText: '0 €',
          ),
        },
        styles: const <String, ContainerStyle>{
          'kpi-total': ContainerStyle(margin: 20, padding: 20),
        },
      );
      final store = _MemoryAppearanceStore(initialAppearance);
      final mainLayout = registry.layoutController('mainLayout');
      addTearDown(registry.unbindAppearance);

      final capturedPrompts = <String>[];
      late ValueNotifier<Appearance> appAppearance;

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              return Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: mainLayout,
                      builder: (_, cfg, _) => SuperLayout(config: cfg),
                    ),
                  ),
                  SizedBox(
                    width: 560,
                    height: 640,
                    child: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appAppearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (prompt) async {
                          capturedPrompts.add(prompt);
                          if (prompt.contains('VÉRIFICATION POST-RENDU')) {
                            return jsonEncode(<String, Object?>{
                              'message': 'Marges corrigées et vérifiées.',
                              'vibe': null,
                            });
                          }
                          if (prompt.contains('PHASE 2 — EXÉCUTION DU LOT')) {
                            return jsonEncode(<String, Object?>{
                              'message': 'Marges corrigées.',
                              'verifyRender': true,
                              'vibe': <String, Object?>{
                                'styles': <String, Object?>{
                                  'kpi-total': <String, Object?>{
                                    'margin': 0,
                                    'padding': 8,
                                  },
                                },
                                'components': <String, Object?>{
                                  'mainLayout': <String, Object?>{
                                    'type': 'layout',
                                    'slotSizeConstraints': <String, Object?>{
                                      'kpi-total': <String, Object?>{
                                        'fitContent': true,
                                      },
                                    },
                                  },
                                },
                              },
                            });
                          }
                          if (prompt.contains('MODE « AUDIT & CORRECTION »')) {
                            return jsonEncode(<String, Object?>{
                              'message': 'Audit terminé : 1 anomalie détectée.',
                              'plan': <String, Object?>{
                                'title': 'Plan d’audit et correction',
                                'lots': <Map<String, Object?>>[
                                  <String, Object?>{
                                    'id': 'lot-1',
                                    'title': 'Corriger les marges du KPI',
                                    'description': 'Réduire les marges/paddings de kpi-total et activer fitContent.',
                                  },
                                ],
                              },
                              'vibe': null,
                            });
                          }
                          if (prompt.contains('MODE « VALEURS RÉACTIVES »')) {
                            return jsonEncode(<String, Object?>{
                              'message': 'Consignes de valeurs réactives prises en compte.',
                              'vibe': null,
                            });
                          }
                          throw StateError('Unexpected prompt in test.');
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(router: router, appearanceStore: store, registry: registry),
      );
      await tester.pumpAndSettle();

      Future<void> pumpUntil(bool Function() condition) async {
        await tester.runAsync(() async {
          for (var i = 0; i < 120; i++) {
            await tester.pump();
            if (condition()) break;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await tester.pump();
        });
      }

      final reactiveChip = find.byKey(
        const ValueKey('vibe-chat-reactive-values'),
      );
      final auditChip = find.byKey(const ValueKey('vibe-chat-audit-page'));
      expect(reactiveChip, findsOneWidget);
      expect(auditChip, findsOneWidget);
      final reactivePlayIcon = find.descendant(
        of: reactiveChip,
        matching: find.byIcon(Icons.play_arrow_rounded),
      );
      final auditPlayIcon = find.descendant(
        of: auditChip,
        matching: find.byIcon(Icons.play_arrow_rounded),
      );
      expect(reactivePlayIcon, findsOneWidget);
      expect(auditPlayIcon, findsOneWidget);
      expect(
        tester.getTopLeft(reactivePlayIcon).dx,
        greaterThan(
          tester
              .getTopLeft(
                find.descendant(
                  of: reactiveChip,
                  matching: find.text('Valeur réactif'),
                ),
              )
              .dx,
        ),
      );
      expect(
        tester.getTopLeft(auditPlayIcon).dx,
        greaterThan(
          tester
              .getTopLeft(
                find.descendant(
                  of: auditChip,
                  matching: find.text('Audit & correction'),
                ),
              )
              .dx,
        ),
      );
      expect(
        tester.getTopLeft(reactiveChip).dx,
        lessThan(tester.getTopLeft(auditChip).dx),
      );
      await tester.ensureVisible(reactiveChip);
      await tester.tap(reactiveChip);
      await pumpUntil(() => capturedPrompts.isNotEmpty);
      await tester.pumpAndSettle();

      expect(capturedPrompts, hasLength(1));
      expect(capturedPrompts.first, contains('MODE « VALEURS RÉACTIVES »'));
      expect(capturedPrompts.first, contains('calculatedAttributes'));
      expect(capturedPrompts.first, contains('(row, ctx, doc)'));
      expect(capturedPrompts.first, contains('SuperValue'));
      expect(capturedPrompts.first, contains('lecture seule'));
      expect(capturedPrompts.first, contains('plan de réalisation par lots'));

      await tester.ensureVisible(auditChip);
      await tester.tap(auditChip);
      await pumpUntil(
        () =>
            find.byKey(const ValueKey('vibe-plan-start')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(capturedPrompts, hasLength(2));
      expect(capturedPrompts[1], contains('MODE « AUDIT & CORRECTION »'));
      expect(
        capturedPrompts[1],
        contains(
          "Contrôle systématique du budget de largeur en ligne (`zoneAxes: 'row'`)",
        ),
      );
      expect(
        capturedPrompts[1],
        contains('somme(width) > parentWidth - paddings'),
      );
      expect(
        capturedPrompts[1],
        contains(
          "Règle d'or sur les volets latéraux étroits (largeur ≤ 480 dp)",
        ),
      );
      expect(capturedPrompts[1], contains("kind: 'icon'"));
      expect(
        capturedPrompts[1],
        contains(
          'Audit visuel obligatoire par capture isolée (`capture_element_screenshot`)',
        ),
      );
      expect(capturedPrompts[1], contains('en-tête de carte maître'));
      expect(capturedPrompts[1], contains('occurrenceIndex: 0'));
      expect(
        capturedPrompts[1],
        contains('Maîtrise du budget de largeur & prévention de la troncature silencieuse'),
      );
      expect(capturedPrompts[1], contains('autoSides: ["east"]'));
      expect(
        capturedPrompts[1],
        contains('[somme(tailles fixes des côtés actifs) + paddings + marges]'),
      );
      expect(
        capturedPrompts[1],
        contains('excessive_margin_or_padding_for_fixed_size'),
      );
      expect(find.text('Plan d’audit et correction'), findsOneWidget);
      expect(find.textContaining('Corriger les marges du KPI'), findsOneWidget);
      // Hors mode Plan, le bouton « Exécution en parallèle » n'est pas affiché
      // et la directive de dépendances parallèles d'audit n'est pas injectée.
      expect(
        capturedPrompts[1],
        isNot(contains('DÉPENDANCES ENTRE LOTS D’AUDIT')),
      );
      expect(
        find.byKey(const ValueKey('vibe-plan-start-parallel')),
        findsNothing,
      );

      // Exécute le lot proposé par le plan d'audit.
      final startButton = find.byKey(const ValueKey('vibe-plan-start'));
      expect(startButton, findsOneWidget);
      await tester.ensureVisible(startButton);
      await tester.tap(startButton);
      await pumpUntil(
        () => find.textContaining('Plan terminé').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(capturedPrompts, hasLength(4));
      expect(capturedPrompts[2], contains('PHASE 2 — EXÉCUTION DU LOT 1/1'));
      expect(capturedPrompts[2], contains('verifyRender'));
      expect(
        capturedPrompts[2],
        contains(
          "Règle d'or sur les volets latéraux étroits (largeur ≤ 480 dp)",
        ),
      );
      expect(capturedPrompts[2], contains('en-tête de carte maître'));
      expect(capturedPrompts[2], contains('occurrenceIndex: 0'));
      expect(capturedPrompts[2], contains('autoSides: ["east"]'));
      expect(capturedPrompts[3], contains('VÉRIFICATION POST-RENDU'));
      expect(
        capturedPrompts[3],
        contains(
          "Contrôle systématique du budget de largeur en ligne (`zoneAxes: 'row'`)",
        ),
      );
      expect(
        capturedPrompts[3],
        contains('somme(width) > parentWidth - paddings'),
      );
      expect(
        capturedPrompts[3],
        contains('Maîtrise du budget de largeur & prévention de la troncature silencieuse'),
      );
      expect(capturedPrompts[3], contains('occurrenceIndex: 0'));
      expect(
        capturedPrompts[3],
        contains(
          "Règle d'or sur les volets latéraux étroits (largeur ≤ 480 dp)",
        ),
      );
      expect(
        capturedPrompts[3],
        contains(
          'Audit visuel obligatoire par capture isolée (`capture_element_screenshot`)',
        ),
      );
      expect(capturedPrompts[3], contains('en-tête de carte maître'));
      expect(capturedPrompts[3], contains('Balayage des onglets (hors scope)'));
      expect(
        capturedPrompts[1],
        contains('BALAYAGE COMPLET DES ONGLETS DE LA PAGE (HORS SCOPE)'),
      );
      expect(appAppearance.value.styles['kpi-total']?.padding, 8);
      expect(appAppearance.value.styles['kpi-total']?.margin, 0);
      final updatedLayout =
          appAppearance.value.components['mainLayout'] as SuperLayoutConfig;
      expect(
        updatedLayout.slotSizeConstraints['kpi-total']?.fitContent,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'VibePageAuditService sweeps all SuperTab tabs when unscoped (restoring initial tab), skips tab sweep when scoped, and preview_navigation_or_selection switches/restores tabs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final registry = Registry()..bootstrap();
      addTearDown(registry.unbindAppearance);

      final appearance = Appearance(
        components: <String, ComponentConfig>{
          'mainLayout': const SuperLayoutConfig(
            placements: <SuperLayoutZone, List<String>>{
              SuperLayoutZone.center: <String>['tabs_main'],
            },
            slotTypes: <String, String>{'tabs_main': 'registry:Tab'},
          ),
          'tabs_main': SuperTabConfig(
            mode: SuperTabMode.static,
            initialIndex: 0,
            placements: <String, List<String>>{
              SuperTabConfig.tabsZone: <String>['tab_btn_0', 'tab_btn_1'],
              SuperTabConfig.contentZoneFor('tab_btn_0'): <String>['clean_val'],
              SuperTabConfig.contentZoneFor('tab_btn_1'): <String>[
                'tab2_row_layout',
              ],
            },
            slotTypes: const <String, String>{
              'tab_btn_0': 'registry:Action',
              'tab_btn_1': 'registry:Action',
              'clean_val': 'registry:Value',
              'tab2_row_layout': 'registry:Layout',
            },
            slotLabels: const <String, String>{
              'tab_btn_0': 'Vue générale',
              'tab_btn_1': 'Détails avancés',
              'clean_val': 'Valeur saine',
              'tab2_row_layout': 'Ligne onglet 2',
            },
          ),
          'tab_btn_0': const SuperActionConfig(
            kind: SuperActionKind.text,
            variant: SuperActionVariant.text,
            label: 'Vue générale',
          ),
          'tab_btn_1': const SuperActionConfig(
            kind: SuperActionKind.text,
            variant: SuperActionVariant.text,
            label: 'Détails avancés',
          ),
          'clean_val': const SuperValueConfig(initialText: 'Tout va bien'),
          // Onglet 2 (initialement masqué) : zone horizontale dont 2 enfants fixes de 280px + spacing 20 = 580px
          // dépassent les ~500px disponibles (600px - padding 32*2 = 536px), plus un slot de taille 0.
          'tab2_row_layout': const SuperLayoutConfig(
            placements: <SuperLayoutZone, List<String>>{
              SuperLayoutZone.center: <String>['wide_child_1', 'wide_child_2'],
            },
            slotTypes: <String, String>{
              'wide_child_1': 'registry:Action',
              'wide_child_2': 'registry:Action',
            },
            zoneAxes: <SuperLayoutZone, Axis>{
              SuperLayoutZone.center: Axis.horizontal,
            },
            zoneFlows: <SuperLayoutZone, ZoneFlowConfig>{
              SuperLayoutZone.center: ZoneFlowConfig(
                expandSlots: false,
                spacing: 24,
                padding: 32,
              ),
            },
            slotSizeConstraints: <String, SlotSizeConstraints>{
              'wide_child_1': SlotSizeConstraints(
                preferredWidth: SlotDimension(70, SlotSizeUnit.pixels),
                fitContent: false,
              ),
              'wide_child_2': SlotSizeConstraints(fitContent: true),
            },
          ),
          'wide_child_1': const SuperActionConfig(
            label: 'Action avec un libellé beaucoup trop long pour 70 pixels',
          ),
          'wide_child_2': const SuperActionConfig(
            label: 'Seconde action extrêmement large qui dépasse le budget horizontal de la ligne',
          ),
        },
      );

      final store = _MemoryAppearanceStore(appearance);
      final mainLayout = registry.layoutController('mainLayout');
      late ValueNotifier<Appearance> appAppearance;

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              return SizedBox(
                width: 600,
                height: 500,
                child: ValueListenableBuilder<SuperLayoutConfig>(
                  valueListenable: mainLayout,
                  builder: (_, cfg, _) => SuperLayout(
                    id: 'mainLayout',
                    config: cfg,
                    editable: true,
                  ),
                ),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(router: router, appearanceStore: store, registry: registry),
      );
      await tester.pumpAndSettle();
      // Ignore toute erreur Flutter capturée si un RenderFlex déborde pendant le balayage de l'onglet 2.
      VibeChatScope? currentScope;
      final tracker = VibePreviewStateTracker();
      final inspector = VibeAppInspector(
        readAppearance: () => appAppearance.value,
        registry: registry,
        readScope: () => currentScope,
        previewTracker: tracker,
        waitForFrame: () async {
          await tester.pump();
          // Consomme l'exception éventuelle de débordement RenderFlex générée par l'onglet 2 défectueux.
          tester.takeException();
        },
      );

      // Avant l'audit, l'onglet 0 est actif et wide_child_1 n'est pas monté.
      expect(VibeMountedSlotIndex.instance.entriesFor('wide_child_1'), isEmpty);

      // 1) Sans scope : balayage automatique des 2 onglets + restauration de l'onglet 0.
      final unscopedReport = await VibePageAuditService.collect(inspector);
      expect(unscopedReport.sweptTabs, hasLength(2));
      expect(unscopedReport.sweptTabs[0].label, 'Vue générale');
      expect(unscopedReport.sweptTabs[1].label, 'Détails avancés');

      final summary = unscopedReport.toPromptSummary();
      expect(summary, contains('ONGLETS BALAYÉS (2)'));
      expect(summary, contains('Détails avancés'));
      expect(
        unscopedReport.findings.any(
          (f) =>
              f.tabContext != null &&
              f.tabContext!.contains('Détails avancés') &&
              (f.kind == 'row_width_budget_exceeded' ||
                  f.kind == 'render_overflow_debug_error' ||
                  f.kind == 'clips_child_content' ||
                  f.kind == 'exceeds_parent_bounds' ||
                  f.kind == 'truncated_text'),
        ),
        isTrue,
        reason: summary,
      );

      // Vérifie que l'onglet initial (0) a bien été restauré après le pré-audit.
      final restoredSnap = VibeMountedSlotIndex.instance
          .tabEntriesFor('tabs_main')
          .single
          .readSnapshot()!;
      expect(restoredSnap.activeIndex, 0);

      // 2) Avec un scope restreint : PAS de balayage des autres onglets ni de directive hors scope.
      currentScope = const VibeChatScope(
        componentId: 'clean_val',
        label: 'Valeur saine',
      );
      final scopedReport = await VibePageAuditService.collect(inspector);
      expect(scopedReport.sweptTabs, isEmpty);

      final unscopedPrompt = VibePromptBuilder.buildAuditTurnPrompt(
        report: unscopedReport,
        conversation: '',
        appearance: appAppearance.value,
        codec: const AppearanceCodec(),
        scope: null,
      );
      final unscopedPlanPrompt = VibePromptBuilder.buildAuditTurnPrompt(
        report: unscopedReport,
        conversation: '',
        appearance: appAppearance.value,
        codec: const AppearanceCodec(),
        scope: null,
        planMode: true,
      );
      final scopedPrompt = VibePromptBuilder.buildAuditTurnPrompt(
        report: scopedReport,
        conversation: '',
        appearance: appAppearance.value,
        codec: const AppearanceCodec(),
        scope: currentScope,
      );
      final scopedPlanPrompt = VibePromptBuilder.buildAuditTurnPrompt(
        report: scopedReport,
        conversation: '',
        appearance: appAppearance.value,
        codec: const AppearanceCodec(),
        scope: currentScope,
        planMode: true,
      );
      expect(
        unscopedPrompt,
        contains('BALAYAGE COMPLET DES ONGLETS DE LA PAGE (HORS SCOPE)'),
      );
      expect(unscopedPrompt, isNot(contains('DÉPENDANCES ENTRE LOTS D’AUDIT')));
      expect(
        unscopedPlanPrompt,
        contains('DÉPENDANCES ENTRE LOTS D’AUDIT (MODE « PLAN » ACTIF)'),
      );
      expect(
        scopedPrompt,
        isNot(contains('BALAYAGE COMPLET DES ONGLETS DE LA PAGE (HORS SCOPE)')),
      );
      expect(scopedPrompt, isNot(contains('DÉPENDANCES ENTRE LOTS D’AUDIT')));
      expect(
        scopedPlanPrompt,
        contains('DÉPENDANCES ENTRE LOTS D’AUDIT (MODE « PLAN » ACTIF)'),
      );

      // Sous scope restreint hors SuperTab, preview_navigation_or_selection refuse de changer d'onglet.
      final blockedSwitch = await inspector.previewNavigationOrSelection(
        'c-blocked',
        'preview_navigation_or_selection',
        <String, Object?>{'tabComponentId': 'tabs_main', 'tabIndex': 1},
      );
      expect(blockedSwitch.isError, isTrue);

      // 3) Hors scope : l'outil preview_navigation_or_selection bascule sur l'onglet 2 puis restoreTabs revient à 0.
      currentScope = null;
      final switchRes = await inspector.previewNavigationOrSelection(
        'c-tab',
        'preview_navigation_or_selection',
        <String, Object?>{
          'tabComponentId': 'tabs_main',
          'tabId': 'Détails avancés',
        },
      );
      expect(switchRes.isError, isFalse);
      expect(
        VibeMountedSlotIndex.instance
            .tabEntriesFor('tabs_main')
            .single
            .readSnapshot()!
            .activeIndex,
        1,
      );
      expect(
        VibeMountedSlotIndex.instance.entriesFor('wide_child_1'),
        isNotEmpty,
      );

      tracker.restoreTabs();
      await tester.pump();
      expect(
        VibeMountedSlotIndex.instance
            .tabEntriesFor('tabs_main')
            .single
            .readSnapshot()!
            .activeIndex,
        0,
      );
    },
  );

  testWidgets(
    'VibeChatDialog "Uniquement visible" chip sits after "À l’identique" and locks active tab & scroll during addition and audit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final registry = Registry()..bootstrap();
      addTearDown(registry.unbindAppearance);

      final initialAppearance = Appearance(
        components: <String, ComponentConfig>{
          'mainLayout': const SuperLayoutConfig(
            placements: <SuperLayoutZone, List<String>>{
              SuperLayoutZone.center: <String>['tabs_main'],
            },
            slotTypes: <String, String>{'tabs_main': 'registry:Tab'},
          ),
          'tabs_main': SuperTabConfig(
            mode: SuperTabMode.static,
            initialIndex: 0,
            placements: <String, List<String>>{
              SuperTabConfig.tabsZone: <String>['tab_btn_0', 'tab_btn_1'],
              SuperTabConfig.contentZoneFor('tab_btn_0'): <String>[
                'tab0_hidden',
              ],
              SuperTabConfig.contentZoneFor('tab_btn_1'): <String>[
                'scroll_layout',
              ],
            },
            slotTypes: const <String, String>{
              'tab_btn_0': 'registry:Action',
              'tab_btn_1': 'registry:Action',
              'tab0_hidden': 'registry:Value',
              'scroll_layout': 'registry:Layout',
            },
            slotLabels: const <String, String>{
              'tab_btn_0': 'Vue générale',
              'tab_btn_1': 'Détails avancés',
              'tab0_hidden': 'Secret onglet 1',
              'scroll_layout': 'Zone défilable',
            },
          ),
          'tab_btn_0': const SuperActionConfig(
            kind: SuperActionKind.text,
            variant: SuperActionVariant.text,
            label: 'Vue générale',
          ),
          'tab_btn_1': const SuperActionConfig(
            kind: SuperActionKind.text,
            variant: SuperActionVariant.text,
            label: 'Détails avancés',
          ),
          'tab0_hidden': const SuperValueConfig(
            initialText: 'Intact sur onglet 1',
          ),
          'scroll_layout': const SuperLayoutConfig(
            placements: <SuperLayoutZone, List<String>>{
              SuperLayoutZone.center: <String>[
                'top_scrolled_out',
                'spacer_mid',
                'bottom_visible',
              ],
            },
            slotTypes: <String, String>{
              'top_scrolled_out': 'registry:Value',
              'spacer_mid': 'registry:Value',
              'bottom_visible': 'registry:Value',
            },
            slotLabels: <String, String>{
              'top_scrolled_out': 'Section haute hors champ',
              'spacer_mid': 'Section intermédiaire',
              'bottom_visible': 'Section basse visible',
            },
            zoneFlows: <SuperLayoutZone, ZoneFlowConfig>{
              SuperLayoutZone.center: ZoneFlowConfig(
                expandSlots: false,
                scrollable: true,
                spacing: 16,
              ),
            },
            slotSizeConstraints: <String, SlotSizeConstraints>{
              'top_scrolled_out': SlotSizeConstraints(
                preferredHeight: SlotDimension(320, SlotSizeUnit.pixels),
                fitContent: false,
              ),
              'spacer_mid': SlotSizeConstraints(
                preferredHeight: SlotDimension(320, SlotSizeUnit.pixels),
                fitContent: false,
              ),
              'bottom_visible': SlotSizeConstraints(
                preferredHeight: SlotDimension(120, SlotSizeUnit.pixels),
                fitContent: false,
              ),
            },
          ),
          'top_scrolled_out': const SuperValueConfig(
            initialText: 'Ne pas modifier en haut',
          ),
          'spacer_mid': const SuperValueConfig(initialText: 'Intermédiaire'),
          'bottom_visible': const SuperValueConfig(
            initialText: 'Visible en bas',
          ),
        },
      );

      final store = _MemoryAppearanceStore(initialAppearance);
      final mainLayout = registry.layoutController('mainLayout');
      final capturedPrompts = <String>[];
      late ValueNotifier<Appearance> appAppearance;

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              return Row(
                children: [
                  SizedBox(
                    width: 640,
                    height: 360,
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: mainLayout,
                      builder: (_, cfg, _) => SuperLayout(
                        id: 'mainLayout',
                        config: cfg,
                        editable: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 600,
                    height: 640,
                    child: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appAppearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (prompt) async {
                          capturedPrompts.add(prompt);
                          if (prompt.contains('MODE « AUDIT & CORRECTION »')) {
                            return jsonEncode(<String, Object?>{
                              'message': 'Audit terminé sur la zone visible uniquement.',
                              'plan': null,
                              'vibe': null,
                            });
                          }
                          // Simule un ajout dans scroll_layout où le modèle tenterait par erreur
                          // d'omettre top_scrolled_out, de modifier tab0_hidden et de changer initialIndex.
                          return jsonEncode(<String, Object?>{
                            'message': 'Bouton ajouté dans la zone visible.',
                            'vibe': <String, Object?>{
                              'components': <String, Object?>{
                                'tabs_main': <String, Object?>{
                                  'type': 'tab',
                                  'initialIndex': 0,
                                },
                                'tab0_hidden': <String, Object?>{
                                  'type': 'value',
                                  'initialText': 'ÉCRASÉ PAR ERREUR',
                                },
                                'top_scrolled_out': <String, Object?>{
                                  'type': 'value',
                                  'initialText': 'ÉCRASÉ HORS SCROLL',
                                },
                                'scroll_layout': <String, Object?>{
                                  'type': 'layout',
                                  'placements': <String, Object?>{
                                    'center': <Object?>[
                                      'spacer_mid',
                                      'bottom_visible',
                                      <String, Object?>{
                                        'id': 'added_btn',
                                        'type': 'registry:Action',
                                        'label': 'Valider visible',
                                      },
                                    ],
                                  },
                                },
                                'added_btn': <String, Object?>{
                                  'type': 'action',
                                  'label': 'Valider visible',
                                },
                              },
                              'usages': <String, Object?>{
                                'added_btn': <String, Object?>{
                                  'kind': 'action',
                                },
                              },
                            },
                          });
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        SuperApp(router: router, appearanceStore: store, registry: registry),
      );
      await tester.pumpAndSettle();

      Future<void> pumpUntil(bool Function() condition) async {
        await tester.runAsync(() async {
          for (var i = 0; i < 120; i++) {
            await tester.pump();
            if (condition()) break;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await tester.pump();
        });
      }

      // 1) Vérifie la position dans la barre d'action : juste après "À l'identique" et avant "Valeur réactif".
      final exactChip = find.byKey(const ValueKey('vibe-chat-reproduce-exact'));
      final visibleChip = find.byKey(const ValueKey('vibe-chat-visible-only'));
      final reactiveChip = find.byKey(
        const ValueKey('vibe-chat-reactive-values'),
      );
      expect(exactChip, findsOneWidget);
      expect(visibleChip, findsOneWidget);
      expect(reactiveChip, findsOneWidget);
      expect(
        tester.getTopLeft(exactChip).dx,
        lessThan(tester.getTopLeft(visibleChip).dx),
      );
      expect(
        tester.getTopLeft(visibleChip).dx,
        lessThan(tester.getTopLeft(reactiveChip).dx),
      );

      // 2) Passe sur le 2e onglet ("Détails avancés") et scrolle tout en bas pour sortir top_scrolled_out du viewport.
      await tester.tap(find.text('Détails avancés'));
      await tester.pumpAndSettle();
      final bottomSlotEntry = VibeMountedSlotIndex.instance
          .entriesFor('bottom_visible')
          .single;
      final scrollableState = Scrollable.of(bottomSlotEntry.slotContext()!);
      scrollableState.position.jumpTo(scrollableState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final lockedScrollOffset = scrollableState.position.pixels;
      expect(lockedScrollOffset, greaterThan(350));

      // Active "Uniquement visible".
      await tester.tap(visibleChip);
      await tester.pumpAndSettle();

      // 3) Envoie une demande d'ajout dans le chat.
      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Ajoute un bouton Valider visible',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await pumpUntil(() => capturedPrompts.length == 1);
      await tester.pumpAndSettle();

      expect(
        capturedPrompts.single,
        contains('MODE « UNIQUEMENT VISIBLE » ACTIF'),
      );
      expect(capturedPrompts.single, contains('Détails avancés'));
      expect(capturedPrompts.single, contains('bottom_visible'));
      expect(capturedPrompts.single, contains('top_scrolled_out'));

      // L'onglet actif (1) et la position de scroll n'ont PAS bougé !
      expect(
        VibeMountedSlotIndex.instance
            .tabEntriesFor('tabs_main')
            .single
            .readSnapshot()!
            .activeIndex,
        1,
      );
      expect(scrollableState.position.pixels, closeTo(lockedScrollOffset, 0.5));

      // Le bouton a été ajouté ET les éléments hors champ / onglets masqués ont été préservés !
      final updatedScrollLayout =
          appAppearance.value.components['scroll_layout'] as SuperLayoutConfig;
      expect(
        updatedScrollLayout.placements[SuperLayoutZone.center],
        containsAllInOrder(<String>[
          'top_scrolled_out',
          'bottom_visible',
          'added_btn',
        ]),
      );
      expect(
        (appAppearance.value.components['top_scrolled_out'] as SuperValueConfig)
            .initialText,
        'Ne pas modifier en haut',
      );
      expect(
        (appAppearance.value.components['tab0_hidden'] as SuperValueConfig)
            .initialText,
        'Intact sur onglet 1',
      );

      // 4) Rouvre le chat étendu et lance un Audit & correction : reste sur l'onglet 1 et le scroll courant.
      final expandToggle = find.byKey(const ValueKey('vibe-chat-expand'));
      if (expandToggle.evaluate().isNotEmpty) {
        await tester.tap(expandToggle);
        await tester.pumpAndSettle();
      }
      final auditChip = find.byKey(const ValueKey('vibe-chat-audit-page'));
      await tester.ensureVisible(auditChip);
      await tester.tap(auditChip);
      await pumpUntil(() => capturedPrompts.length == 2);
      await tester.pumpAndSettle();

      expect(capturedPrompts[1], contains('MODE « AUDIT & CORRECTION »'));
      expect(capturedPrompts[1], contains('MODE « UNIQUEMENT VISIBLE » ACTIF'));
      expect(
        capturedPrompts[1],
        isNot(contains('BALAYAGE COMPLET DES ONGLETS DE LA PAGE (HORS SCOPE)')),
      );
      expect(capturedPrompts[1], isNot(contains('ONGLETS BALAYÉS')));
      expect(
        VibeMountedSlotIndex.instance
            .tabEntriesFor('tabs_main')
            .single
            .readSnapshot()!
            .activeIndex,
        1,
      );
      expect(scrollableState.position.pixels, closeTo(lockedScrollOffset, 0.5));

      // 5) Les outils d'inspection refusent le changement d'onglet/route et ne scrollent pas hors champ.
      final lockedInspector = VibeAppInspector(
        readAppearance: () => appAppearance.value,
        registry: registry,
        readVisibleOnly: () => true,
      );
      final deniedTab = await lockedInspector.previewNavigationOrSelection(
        'v-1',
        'preview_navigation_or_selection',
        <String, Object?>{'tabComponentId': 'tabs_main', 'tabIndex': 0},
      );
      expect(deniedTab.isError, isTrue);
      await lockedInspector.selectEditorElement(
        'v-2',
        'select_editor_element',
        <String, Object?>{
          'componentId': 'top_scrolled_out',
          'scrollIntoView': true,
        },
      );
      expect(scrollableState.position.pixels, closeTo(lockedScrollOffset, 0.5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'smartVerifyLocalGate skips post-render LLM round when mounted page is clean, escalates when an anomaly exists, and VibeVerifyRenderChip disables verifyRender',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final registry = Registry()..bootstrap();
      addTearDown(registry.unbindAppearance);

      final initialAppearance = Appearance(
        components: <String, ComponentConfig>{
          'mainLayout': const SuperLayoutConfig(
            placements: <SuperLayoutZone, List<String>>{
              SuperLayoutZone.center: <String>['kpi-card'],
            },
            slotTypes: <String, String>{'kpi-card': 'registry:Value'},
          ),
          'kpi-card': const SuperValueConfig(
            label: 'CA',
            initialText: '1 200 €',
          ),
        },
      );
      final store = _MemoryAppearanceStore(initialAppearance);
      final mainLayout = registry.layoutController('mainLayout');

      var llmCalls = 0;
      var returnClippedAnomaly = false;
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = previousDebugPrint);

      late ValueNotifier<Appearance> appAppearance;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (routeContext, _) {
              appAppearance = AppearanceScope.controllerOf(routeContext)!;
              return Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<SuperLayoutConfig>(
                      valueListenable: mainLayout,
                      builder: (_, cfg, _) => SuperLayout(
                        id: 'mainLayout',
                        config: cfg,
                        editable: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 560,
                    height: 640,
                    child: DefaultAssetBundle(
                      bundle: _GuideBundle(),
                      child: VibeChatDialog(
                        controller: appAppearance,
                        registry: registry,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        smartVerifyLocalGate: true,
                        throttleStreamingPreviewLogs: true,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (_) async => '',
                        streamGenerate:
                            (
                              prompt, {
                              systemInstruction,
                              staticGuide,
                              attachments = const [],
                              speedMode = VibeAiSpeedMode.fast,
                            }) async* {
                              llmCalls++;
                              if (prompt.contains('VÉRIFICATION POST-RENDU')) {
                                final fixResp = jsonEncode({
                                  'message': 'Marge excessive corrigée.',
                                  'vibe': {
                                    'styles': {
                                      'kpi-card': {'margin': 0, 'padding': 8},
                                    },
                                  },
                                });
                                yield GeminiStreamEvent(
                                  deltaText: fixResp,
                                  accumulatedText: fixResp,
                                  isDone: true,
                                  usedContextCache: true,
                                );
                                return;
                              }
                              if (!returnClippedAnomaly) {
                                const c1 =
                                    '{"message":"Mis à jour proprement.","verifyRender":true,"vibe":{"components":{"kpi-card":{"type":"value","label":"CA","text":"2 400 €"}},';
                                const c2 =
                                    '"styles":{"kpi-card":{"padding":8}}}}';
                                yield const GeminiStreamEvent(
                                  deltaText: c1,
                                  accumulatedText: c1,
                                  isDone: false,
                                  usedContextCache: true,
                                );
                                await Future<void>.delayed(
                                  const Duration(milliseconds: 260),
                                );
                                yield const GeminiStreamEvent(
                                  deltaText: c2,
                                  accumulatedText: '$c1$c2',
                                  isDone: true,
                                  usedContextCache: true,
                                );
                                return;
                              }
                              final anomalous = jsonEncode({
                                'message': 'Marge trop grande.',
                                'verifyRender': true,
                                'vibe': {
                                  'components': {
                                    'mainLayout': {
                                      'type': 'layout',
                                      'slotSizeConstraints': {
                                        'kpi-card': {
                                          'preferredWidth': 76,
                                          'fitContent': false,
                                        },
                                      },
                                    },
                                  },
                                  'styles': {
                                    'kpi-card': {'margin': 18, 'padding': 18},
                                  },
                                },
                              });
                              yield GeminiStreamEvent(
                                deltaText: anomalous,
                                accumulatedText: anomalous,
                                isDone: true,
                                usedContextCache: true,
                              );
                            },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _GuideBundle(),
          child: SuperApp(
            router: router,
            appearanceStore: store,
            registry: registry,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> pumpRealUntil(bool Function() condition) async {
        await tester.runAsync(() async {
          final sw = Stopwatch()..start();
          while (!condition() && sw.elapsed < const Duration(seconds: 6)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
      }

      // Cas 1 : Page saine + verifyRender: true -> 1 seul appel LLM (court-circuit local) + bilan logs streaming regroupé !
      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Double le CA',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await pumpRealUntil(
        () => logs.any((l) => l.contains('Apparence mise à jour')),
      );

      expect(llmCalls, 1, reason: logs.join('\n'));
      expect(
        logs.join('\n'),
        contains('[PostVerify] Court-circuit local : 0 anomalie détectée'),
      );
      expect(
        logs.join('\n'),
        contains(
          '[Vibe IA][Preview] Bilan streaming : 2 palier(s) appliqué(s)',
        ),
      );

      // Cas 2 : Anomalie locale (marge excessive 80px sur 60px) -> escalade automatique vers le tour LLM correctif !
      logs.clear();
      llmCalls = 0;
      returnClippedAnomaly = true;
      final expandBtn = find.byKey(const ValueKey('vibe-chat-expand'));
      if (expandBtn.evaluate().isNotEmpty) {
        await tester.tap(expandBtn);
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Teste une marge trop grande',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await pumpRealUntil(
        () => logs.any((l) => l.contains('Apparence mise à jour')),
      );

      expect(llmCalls, 2);
      expect(appAppearance.value.styles['kpi-card']?.margin, 0);
      expect(appAppearance.value.styles['kpi-card']?.padding, 8);

      // Cas 3 : Désactivation de la puce VibeVerifyRenderChip -> ignore verifyRender: true même avec anomalie non-runtime (1 seul appel LLM).
      logs.clear();
      llmCalls = 0;
      if (expandBtn.evaluate().isNotEmpty) {
        await tester.tap(expandBtn);
        await tester.pumpAndSettle();
      }
      final verifyChip = find.byKey(const ValueKey('vibe-chat-verify-render'));
      await tester.ensureVisible(verifyChip);
      await tester.tap(verifyChip);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('vibe-chat-input')),
        'Sans vérif rendu',
      );
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await pumpRealUntil(
        () => logs.any((l) => l.contains('Apparence mise à jour')),
      );

      expect(llmCalls, 1);
    },
  );

  testWidgets(
    'VibePageAuditService and VibeDiagnosticsInspector detect ghost components when mounted mainLayout has 0 placements',
    (tester) async {
      final appearance = Appearance(
        components: <String, ComponentConfig>{
          'mainLayout': const SuperLayoutConfig(),
          'dash-header': const SuperValueConfig(initialText: 'En-tête'),
          'kpis-row': const SuperLayoutConfig(),
          'card-chart-container': const SuperValueConfig(initialText: 'Graphe'),
        },
      );
      final inspector = VibeAppInspector(readAppearance: () => appearance);

      final report = await VibePageAuditService.collect(inspector);
      final ghostFindings = report.findings
          .where((f) => f.kind == 'ghost_components_empty_root')
          .toList();
      expect(ghostFindings, hasLength(1));
      expect(ghostFindings.single.severity, VibeAuditSeverity.error);
      expect(ghostFindings.single.componentId, 'mainLayout');
      expect(ghostFindings.single.message, contains('3 composant(s)'));

      final diag = await inspector.inspectBindingsAndDiagnostics(
        const <String, Object?>{},
      );
      expect(diag['orphanComponentCount'], 3);
      expect(diag['emptyMountedRootIds'], ['mainLayout']);
    },
  );
}
