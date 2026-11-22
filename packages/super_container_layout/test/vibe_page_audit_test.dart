import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/component_config.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/services/appearance/appearance_codec.dart';
import 'package:super_container_layout/services/appearance/appearance_store.dart';
import 'package:super_container_layout/services/inspection/vibe_app_inspector.dart';
import 'package:super_container_layout/services/inspection/vibe_mounted_slot_index.dart';
import 'package:super_container_layout/services/inspection/vibe_page_audit.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/appearance/appearance_scope.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_chat_dialog.dart';

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
        contains("Contrôle budgétaire de largeur en ligne (`zoneAxes: 'row'`)"),
      );
      expect(
        capturedPrompts[1],
        contains('parentWidth - paddingLeft - paddingRight'),
      );
      expect(capturedPrompts[1], contains('Inspection visuelle par élément'));
      expect(capturedPrompts[1], contains('capture_element_screenshot'));
      expect(
        capturedPrompts[1],
        contains('excessive_margin_or_padding_for_fixed_size'),
      );
      expect(find.text('Plan d’audit et correction'), findsOneWidget);
      expect(find.textContaining('Corriger les marges du KPI'), findsOneWidget);

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
      expect(capturedPrompts[3], contains('VÉRIFICATION POST-RENDU'));
      expect(
        capturedPrompts[3],
        contains("Contrôle budgétaire de largeur en ligne (`zoneAxes: 'row'`)"),
      );
      expect(
        capturedPrompts[3],
        contains('parentWidth - paddingLeft - paddingRight'),
      );
      expect(capturedPrompts[3], contains('Inspection visuelle par élément'));
      expect(capturedPrompts[3], contains('capture_element_screenshot'));
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
}
