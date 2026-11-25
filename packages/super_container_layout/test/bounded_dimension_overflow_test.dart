import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

class _MemoryAppearanceStore extends AppearanceStore {
  _MemoryAppearanceStore(this.initial);

  final Appearance initial;

  @override
  Future<Appearance> load() async => initial;

  @override
  Future<void> save(Appearance appearance) async {}
}

void main() {
  Future<void> pumpReal(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    await tester.runAsync(() async {
      await action();
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  void mockDesktopWindowChannels() {
    for (final channel in const <MethodChannel>[
      MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    }
  }

  group('Bounded Dimension Overflow & Silent Clipping', () {
    setUp(mockDesktopWindowChannels);
    testWidgets(
      'VibePageAuditService detects vertical_budget_overflow on bounded SuperLayout, ListView.template and SuperTable',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'bounded_overflow_audit_',
        );
        final repoStore = JsonRepositoryStore(tempDir);
        final registry = Registry()..bootstrap();
        addTearDown(() {
          registry.unbindAppearance();
          repoStore.dispose();
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        repoStore.registerRepository(
          RepositoryImpl(
            id: 'crm',
            json: const <String, Object?>{
              'clients': <Map<String, Object?>>[
                {'nom': 'Alice Martin', 'statut': 'Actif'},
              ],
            },
          ),
        );

        final appearance = Appearance(
          styles: const <String, ContainerStyle>{
            'list_clients:item': ContainerStyle(padding: 12),
          },
          components: <String, ComponentConfig>{
            'mainLayout': const SuperLayoutConfig(
              north: true,
              northSize: 44,
              autoSides: <SuperLayoutZone>{},
              placements: <SuperLayoutZone, List<String>>{
                SuperLayoutZone.north: <String>['toolbar_title', 'toolbar_btn'],
                SuperLayoutZone.center: <String>[
                  'list_clients',
                  'table_clients',
                ],
              },
              slotTypes: <String, String>{
                'toolbar_title': 'registry:Value',
                'toolbar_btn': 'registry:Action',
                'list_clients': 'registry:ListView',
                'table_clients': 'registry:Table',
              },
              zoneFlows: <SuperLayoutZone, ZoneFlowConfig>{
                SuperLayoutZone.north: ZoneFlowConfig(
                  expandSlots: false,
                  spacing: 6,
                ),
              },
            ),
            'toolbar_title': const SuperValueConfig(initialText: 'Clients'),
            'toolbar_btn': const SuperActionConfig(label: 'Ajouter'),
            // ListView avec itemExtent: 52 - padding 24 = 28 dp utiles, empilant 2 enfants en center (column).
            'list_clients': const SuperListViewConfig(
              binding: JsonTextBinding(repositoryId: 'crm', path: 'clients'),
              itemExtent: 52,
              template: SuperLayoutConfig(
                placements: <SuperLayoutZone, List<String>>{
                  SuperLayoutZone.center: <String>['row_name', 'row_cta'],
                },
                slotTypes: <String, String>{
                  'row_name': 'registry:Value',
                  'row_cta': 'registry:Action',
                },
                zoneFlows: <SuperLayoutZone, ZoneFlowConfig>{
                  SuperLayoutZone.center: ZoneFlowConfig(
                    expandSlots: false,
                    spacing: 4,
                  ),
                },
              ),
            ),
            'row_name': const SuperValueConfig(
              binding: JsonTextBinding(path: 'clients[?].nom'),
            ),
            'row_cta': const SuperActionConfig(label: 'Ouvrir'),
            // SuperTable avec rowHeight: 34 empilant verticalement 2 boutons dans cell:col_actions.
            'table_clients': SuperTableConfig(
              binding: const JsonTextBinding(
                repositoryId: 'crm',
                path: 'clients',
              ),
              rowHeight: 34,
              headerRowHeight: 34,
              columns: const <SuperTableColumnConfig>[
                SuperTableColumnConfig(
                  id: 'col_actions',
                  title: 'Actions',
                  width: 160,
                ),
              ],
              placements: const <String, List<String>>{
                'cell:col_actions': <String>['tbl_btn_1', 'tbl_btn_2'],
              },
              slotTypes: const <String, String>{
                'tbl_btn_1': 'registry:Action',
                'tbl_btn_2': 'registry:Action',
              },
              zoneAxes: const <String, Axis>{'cell:col_actions': Axis.vertical},
              zoneFlows: const <String, ZoneFlowConfig>{
                'cell:col_actions': ZoneFlowConfig(expandSlots: false),
              },
            ),
            'tbl_btn_1': const SuperActionConfig(label: 'Éditer'),
            'tbl_btn_2': const SuperActionConfig(label: 'Supprimer'),
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
                  width: 800,
                  height: 600,
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

        await pumpReal(
          tester,
          () => tester.pumpWidget(
            SuperApp(
              router: router,
              appearanceStore: store,
              registry: registry,
              repositoryStore: repoStore,
            ),
          ),
        );

        final inspector = VibeAppInspector(
          readAppearance: () => appAppearance.value,
          registry: registry,
        );
        final report = await VibePageAuditService.collect(inspector);

        final verticalFindings = report.findings
            .where((f) => f.kind == 'vertical_budget_overflow')
            .toList();
        expect(verticalFindings, isNotEmpty);
        expect(
          verticalFindings.every((f) => f.severity == VibeAuditSeverity.error),
          isTrue,
        );

        final flaggedTargets = verticalFindings
            .map((f) => '${f.componentId}::${f.zoneId}')
            .toSet();
        expect(
          flaggedTargets,
          containsAll(<String>[
            'mainLayout::north',
            'list_clients::center',
            'table_clients::cell:col_actions',
          ]),
        );

        // Bascule mainLayout.north en row avec hauteur suffisante -> l'anomalie sur mainLayout::north disparaît.
        appAppearance.value = appAppearance.value.withComponent(
          'mainLayout',
          (appAppearance.value.components['mainLayout']! as SuperLayoutConfig)
              .withSize(SuperLayoutZone.north, 56)
              .withAxis(SuperLayoutZone.north, Axis.horizontal),
        );
        await tester.pumpAndSettle();

        final fixedReport = await VibePageAuditService.collect(inspector);
        expect(
          fixedReport.findings.any(
            (f) =>
                f.kind == 'vertical_budget_overflow' &&
                f.componentId == 'mainLayout' &&
                f.zoneId == 'north',
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'SuperLayout resolves peripheral east/west multi-child zones to row by default in ListView.template and Table.cell when height <= 64 dp',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'compact_row_default_axis_',
        );
        final repoStore = JsonRepositoryStore(tempDir);
        final registry = Registry()..bootstrap();
        addTearDown(() {
          registry.unbindAppearance();
          repoStore.dispose();
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        repoStore.registerRepository(
          RepositoryImpl(
            id: 'items_repo',
            json: const <String, Object?>{
              'rows': <Map<String, Object?>>[
                {'title': 'Ligne 1'},
              ],
            },
          ),
        );

        final appearance = Appearance(
          components: <String, ComponentConfig>{
            'mainLayout': const SuperLayoutConfig(
              placements: <SuperLayoutZone, List<String>>{
                SuperLayoutZone.center: <String>[
                  'compact_list',
                  'tall_list',
                  'compact_table',
                ],
              },
              slotTypes: <String, String>{
                'compact_list': 'registry:ListView',
                'tall_list': 'registry:ListView',
                'compact_table': 'registry:Table',
              },
            ),
            // 1) ListView compacte (56 dp <= 64 dp) sans zoneAxes sur east -> doit basculer en row !
            'compact_list': const SuperListViewConfig(
              binding: JsonTextBinding(
                repositoryId: 'items_repo',
                path: 'rows',
              ),
              itemExtent: 56,
              template: SuperLayoutConfig(
                east: true,
                eastSize: 180,
                autoSides: <SuperLayoutZone>{},
                placements: <SuperLayoutZone, List<String>>{
                  SuperLayoutZone.center: <String>['compact_title'],
                  SuperLayoutZone.east: <String>[
                    'compact_act_1',
                    'compact_act_2',
                  ],
                },
                slotTypes: <String, String>{
                  'compact_title': 'registry:Value',
                  'compact_act_1': 'registry:Action',
                  'compact_act_2': 'registry:Action',
                },
              ),
            ),
            'compact_title': const SuperValueConfig(initialText: 'Titre'),
            'compact_act_1': const SuperActionConfig(
              kind: SuperActionKind.icon,
              variant: SuperActionVariant.icon,
              icon: 'edit',
              label: 'A1',
            ),
            'compact_act_2': const SuperActionConfig(
              kind: SuperActionKind.icon,
              variant: SuperActionVariant.icon,
              icon: 'delete',
              label: 'A2',
            ),
            // 2) ListView haute (84 dp > 64 dp) sans zoneAxes sur east -> conserve column par défaut.
            'tall_list': const SuperListViewConfig(
              binding: JsonTextBinding(
                repositoryId: 'items_repo',
                path: 'rows',
              ),
              itemExtent: 84,
              template: SuperLayoutConfig(
                east: true,
                eastSize: 180,
                autoSides: <SuperLayoutZone>{},
                placements: <SuperLayoutZone, List<String>>{
                  SuperLayoutZone.east: <String>['tall_act_1', 'tall_act_2'],
                },
                slotTypes: <String, String>{
                  'tall_act_1': 'registry:Value',
                  'tall_act_2': 'registry:Value',
                },
              ),
            ),
            'tall_act_1': const SuperValueConfig(initialText: 'Haut 1'),
            'tall_act_2': const SuperValueConfig(initialText: 'Haut 2'),
            // 3) SuperTable (rowHeight: 44 <= 64 dp) contenant un SuperLayout dans cell:col_main avec west multi-enfants sans zoneAxes.
            'compact_table': SuperTableConfig(
              binding: const JsonTextBinding(
                repositoryId: 'items_repo',
                path: 'rows',
              ),
              rowHeight: 44,
              columns: const <SuperTableColumnConfig>[
                SuperTableColumnConfig(
                  id: 'col_main',
                  title: 'Principal',
                  width: 320,
                ),
              ],
              placements: const <String, List<String>>{
                'cell:col_main': <String>['cell_layout'],
              },
              slotTypes: const <String, String>{
                'cell_layout': 'registry:Layout',
              },
            ),
            'cell_layout': const SuperLayoutConfig(
              west: true,
              westSize: 120,
              autoSides: <SuperLayoutZone>{},
              placements: <SuperLayoutZone, List<String>>{
                SuperLayoutZone.west: <String>['cell_w1', 'cell_w2'],
              },
              slotTypes: <String, String>{
                'cell_w1': 'registry:Value',
                'cell_w2': 'registry:Value',
              },
            ),
            'cell_w1': const SuperValueConfig(initialText: 'W1'),
            'cell_w2': const SuperValueConfig(initialText: 'W2'),
          },
        );

        final store = _MemoryAppearanceStore(appearance);
        final mainLayout = registry.layoutController('mainLayout');
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => SizedBox(
                width: 800,
                height: 700,
                child: ValueListenableBuilder<SuperLayoutConfig>(
                  valueListenable: mainLayout,
                  builder: (_, cfg, _) => SuperLayout(
                    id: 'mainLayout',
                    config: cfg,
                    editable: true,
                  ),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await pumpReal(
          tester,
          () => tester.pumpWidget(
            SuperApp(
              router: router,
              appearanceStore: store,
              registry: registry,
              repositoryStore: repoStore,
            ),
          ),
        );

        // 1) Dans compact_list (56 dp), compact_act_1 et compact_act_2 sont côte à côte (row).
        final act1Slot = find.byKey(const ValueKey('slot-compact_act_1'));
        final act2Slot = find.byKey(const ValueKey('slot-compact_act_2'));
        expect(act1Slot, findsOneWidget);
        expect(act2Slot, findsOneWidget);
        expect(
          tester.getTopLeft(act2Slot).dx,
          greaterThan(tester.getTopLeft(act1Slot).dx + 10),
        );
        expect(
          (tester.getCenter(act1Slot).dy - tester.getCenter(act2Slot).dy).abs(),
          lessThan(2.0),
        );

        // 2) Dans tall_list (84 dp > 64 dp), tall_act_1 et tall_act_2 restent empilés verticalement (column).
        final tall1Slot = find.byKey(const ValueKey('slot-tall_act_1'));
        final tall2Slot = find.byKey(const ValueKey('slot-tall_act_2'));
        expect(
          tester.getTopLeft(tall2Slot).dy,
          greaterThan(tester.getTopLeft(tall1Slot).dy + 10),
        );

        // 3) Dans Table.cell (44 dp <= 64 dp), cell_w1 et cell_w2 dans west sont côte à côte (row).
        final cellW1 = find.byKey(const ValueKey('slot-cell_w1'));
        final cellW2 = find.byKey(const ValueKey('slot-cell_w2'));
        expect(
          tester.getTopLeft(cellW2).dx,
          greaterThan(tester.getTopLeft(cellW1).dx + 10),
        );
      },
    );

    testWidgets(
      'EditorSilentClipIndicator activates hatched warning border in edit mode when child overflows a clipBehavior != Clip.none parent',
      (tester) async {
        final editController = ValueNotifier<bool>(true);
        addTearDown(editController.dispose);
        final clippedSlotKey = GlobalKey();
        final unclippedSlotKey = GlobalKey();
        final fittingSlotKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StyleEditScope(
                controller: editController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Enfant 160x80 rogné par un ClipRect (clipBehavior: Clip.hardEdge) de 100x40.
                    SizedBox(
                      width: 100,
                      height: 40,
                      child: EditorSlot(
                        key: clippedSlotKey,
                        id: 'clipped-box',
                        child: ClipRect(
                          clipBehavior: Clip.hardEdge,
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: 0,
                            maxWidth: 200,
                            minHeight: 0,
                            maxHeight: 120,
                            child: const SizedBox(width: 160, height: 80),
                          ),
                        ),
                      ),
                    ),
                    // 2. Même débordement mais clipBehavior: Clip.none -> pas de clipping silencieux !
                    SizedBox(
                      width: 100,
                      height: 40,
                      child: EditorSlot(
                        key: unclippedSlotKey,
                        id: 'unclipped-box',
                        child: ClipRect(
                          clipBehavior: Clip.none,
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: 0,
                            maxWidth: 200,
                            minHeight: 0,
                            maxHeight: 120,
                            child: const SizedBox(width: 160, height: 80),
                          ),
                        ),
                      ),
                    ),
                    // 3. Contenu qui tient dans 100x40 avec ClipRect -> pas d'avertissement !
                    SizedBox(
                      width: 100,
                      height: 40,
                      child: EditorSlot(
                        key: fittingSlotKey,
                        id: 'fitting-box',
                        child: ClipRect(
                          clipBehavior: Clip.hardEdge,
                          child: const SizedBox(width: 90, height: 36),
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

        RenderEditorSilentClipIndicator indicatorOf(GlobalKey slotKey) {
          final finder = find.descendant(
            of: find.byKey(slotKey),
            matching: find.byType(EditorSilentClipIndicator),
          );
          return tester.renderObject<RenderEditorSilentClipIndicator>(finder);
        }

        final clippedIndicator = indicatorOf(clippedSlotKey);
        final unclippedIndicator = indicatorOf(unclippedSlotKey);
        final fittingIndicator = indicatorOf(fittingSlotKey);

        expect(clippedIndicator.hasSilentClipOverflow, isTrue);
        expect(
          clippedIndicator.clippedEdges,
          containsAll(<AxisDirection>[AxisDirection.right, AxisDirection.down]),
        );
        expect(unclippedIndicator.hasSilentClipOverflow, isFalse);
        expect(fittingIndicator.hasSilentClipOverflow, isFalse);

        // Hors mode édition (StyleEditScope = false), l'indicateur se désactive proprement.
        editController.value = false;
        await tester.pump();
        expect(clippedIndicator.enabled, isFalse);
        expect(clippedIndicator.hasSilentClipOverflow, isFalse);
      },
    );
  });
}
