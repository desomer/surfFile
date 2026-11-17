import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

class _InMemoryStore extends AppearanceStore {
  _InMemoryStore(this.initial);

  final Appearance initial;

  @override
  Future<Appearance> load() async => initial;

  @override
  Future<void> save(Appearance appearance) async {}
}

bool _hasVibeWorkPainter(WidgetTester tester, String slotKey) {
  final finder = find.byKey(ValueKey(slotKey));
  if (finder.evaluate().isEmpty) return false;
  final paints = tester.widgetList<CustomPaint>(
    find.descendant(of: finder, matching: find.byType(CustomPaint)),
  );
  return paints.any((paint) => paint.foregroundPainter is VibeWorkHighlightPainter);
}

VibeWorkHighlightPainter? _findVibeWorkPainter(
  WidgetTester tester,
  String slotKey,
) {
  final finder = find.byKey(ValueKey(slotKey));
  final paints = tester.widgetList<CustomPaint>(
    find.descendant(of: finder, matching: find.byType(CustomPaint)),
  );
  for (final paint in paints) {
    final fg = paint.foregroundPainter;
    if (fg is VibeWorkHighlightPainter) return fg;
  }
  return null;
}

void main() {
  tearDown(() {
    VibeWorkHighlightController.instance.clearAll();
  });

  group('VibeAppearanceDiff', () {
    test(
      'cible uniquement le nouvel enfant sans marquer le SuperLayout parent comme modifié quand seuls ses placements grandissent',
      () {
        final previous = Appearance(
          components: {
            'mainLayout': SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: const ['title'],
              },
              slotTypes: const {'title': 'registry:Value'},
            ),
            'title': const SuperValueConfig(label: 'Titre'),
          },
        );

        final next = Appearance(
          components: {
            'mainLayout': SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: const ['title', 'kpi'],
              },
              slotTypes: const {
                'title': 'registry:Value',
                'kpi': 'registry:Value',
              },
            ),
            'title': const SuperValueConfig(label: 'Titre'),
            'kpi': const SuperValueConfig(label: 'KPI'),
          },
        );

        final diff = VibeAppearanceDiff.compute(previous, next);
        expect(diff.addedIds, {'kpi'});
        expect(diff.modifiedIds, isEmpty);
      },
    );

    test(
      'marque le SuperLayout comme modifié si une propriété structurelle change, ainsi que styles, behaviors et usages modifiés',
      () {
        final previous = Appearance(
          styles: {'card-1': const ContainerStyle(radius: 8)},
          components: {
            'mainLayout': SuperLayoutConfig(west: true, westSize: 240),
            'btn': const SuperActionConfig(label: 'OK'),
          },
        );

        final next = Appearance(
          styles: {
            'card-1': const ContainerStyle(radius: 16),
            'card-new': const ContainerStyle(radius: 12),
          },
          components: {
            'mainLayout': SuperLayoutConfig(west: true, westSize: 320),
            'btn': const SuperActionConfig(label: 'Valider'),
          },
          behaviors: {
            'btn': [
              ComponentBehavior(
                id: 'b1',
                trigger: BehaviorTrigger.click,
                action: EmitEventAction(eventId: 'submit'),
              ),
            ],
          },
          usages: {
            'btn': const ComponentUsage(kind: ComponentUsageKind.staticData),
          },
        );

        final diff = VibeAppearanceDiff.compute(previous, next);
        expect(diff.addedIds, {'card-new'});
        expect(diff.modifiedIds, {'card-1', 'mainLayout', 'btn'});
      },
    );
  });

  group('VibeWorkHighlightController & EditorSlot', () {
    testWidgets(
      'affiche VibeWorkHighlightPainter en streaming puis le pulse temporaire de 500 ms avant expiration',
      (tester) async {
        final editMode = ValueNotifier<bool>(true);
        final appearance = ValueNotifier<Appearance>(Appearance());
        addTearDown(editMode.dispose);
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: AppearanceScope(
              controller: appearance,
              child: StyleEditScope(
                controller: editMode,
                child: Scaffold(
                  body: Column(
                    children: [
                      EditorSlot(
                        key: const ValueKey('slot-card'),
                        id: 'card-1',
                        outlineRadius: 12,
                        child: const SizedBox(
                          width: 140,
                          height: 60,
                          child: Text('Carte 1'),
                        ),
                      ),
                      EditorSlot(
                        key: const ValueKey('slot-card-zone'),
                        id: 'card-1',
                        zoneId: 'center',
                        child: const SizedBox(width: 100, height: 40),
                      ),
                      EditorSlot(
                        key: const ValueKey('slot-other'),
                        id: 'other-1',
                        child: const SizedBox(width: 100, height: 40),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        expect(_hasVibeWorkPainter(tester, 'slot-card'), isFalse);
        expect(_hasVibeWorkPainter(tester, 'slot-card-zone'), isFalse);
        expect(_hasVibeWorkPainter(tester, 'slot-other'), isFalse);

        // 1. Streaming en cours sur card-1 -> seul slot-card s'allume (pas sa zone ni other-1).
        VibeWorkHighlightController.instance.setStreamingTargets(['card-1']);
        await tester.pump();
        expect(_hasVibeWorkPainter(tester, 'slot-card'), isTrue);
        expect(
          _findVibeWorkPainter(tester, 'slot-card')!.state.kind,
          VibeWorkKind.streaming,
        );
        expect(_hasVibeWorkPainter(tester, 'slot-card-zone'), isFalse);
        expect(_hasVibeWorkPainter(tester, 'slot-other'), isFalse);

        // 2. Fin du streaming + pulse d'ajout de 500 ms sur card-1.
        VibeWorkHighlightController.instance.clearStreamingTargets();
        VibeWorkHighlightController.instance.pulseTargets(
          addedIds: const {'card-1'},
          modifiedIds: const {'other-1'},
        );
        await tester.pump();
        expect(
          _findVibeWorkPainter(tester, 'slot-card')!.state.kind,
          VibeWorkKind.added,
        );
        expect(
          _findVibeWorkPainter(tester, 'slot-other')!.state.kind,
          VibeWorkKind.modified,
        );

        // À 250 ms, la surbrillance est encore active.
        await tester.pump(const Duration(milliseconds: 250));
        expect(_hasVibeWorkPainter(tester, 'slot-card'), isTrue);
        expect(_hasVibeWorkPainter(tester, 'slot-other'), isTrue);

        // Après 500 ms, pumpAndSettle converge et retire les peintres temporaires.
        await tester.pumpAndSettle();
        expect(_hasVibeWorkPainter(tester, 'slot-card'), isFalse);
        expect(_hasVibeWorkPainter(tester, 'slot-other'), isFalse);
        expect(VibeWorkHighlightController.instance.hasActiveHighlights, isFalse);
      },
    );

    testWidgets(
      'fonctionne aussi lorsque StyleEditScope est désactivé (mode exécution)',
      (tester) async {
        final editMode = ValueNotifier<bool>(false);
        final appearance = ValueNotifier<Appearance>(Appearance());
        addTearDown(editMode.dispose);
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: AppearanceScope(
              controller: appearance,
              child: StyleEditScope(
                controller: editMode,
                child: const Scaffold(
                  body: EditorSlot(
                    key: ValueKey('slot-runtime'),
                    id: 'runtime-kpi',
                    child: SizedBox(width: 120, height: 48, child: Text('42')),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(_hasVibeWorkPainter(tester, 'slot-runtime'), isFalse);

        VibeWorkHighlightController.instance.pulseTargets(
          addedIds: const {'runtime-kpi'},
        );
        await tester.pump();
        expect(_hasVibeWorkPainter(tester, 'slot-runtime'), isTrue);

        await tester.pumpAndSettle();
        expect(_hasVibeWorkPainter(tester, 'slot-runtime'), isFalse);
      },
    );

    testWidgets(
      'bascule automatiquement SuperTab sur l’onglet dont le contenu (y compris imbriqué) est travaillé par l’IA sans bloquer la navigation manuelle ensuite',
      (tester) async {
        final initialAppearance = Appearance(
          components: {
            'main-tab': SuperTabConfig(
              placements: {
                SuperTabConfig.tabsZone: const ['tab_1', 'tab_2'],
                SuperTabConfig.contentZoneFor('tab_1'): const ['val_tab_1'],
                SuperTabConfig.contentZoneFor('tab_2'): const ['layout_tab_2'],
              },
              slotTypes: const {
                'tab_1': 'registry:Action',
                'tab_2': 'registry:Action',
                'val_tab_1': 'registry:Value',
                'layout_tab_2': 'registry:Layout',
              },
            ),
            'tab_1': const SuperActionConfig(label: 'Général'),
            'tab_2': const SuperActionConfig(label: 'Détails'),
            'val_tab_1': const SuperValueConfig(label: 'Contenu Onglet 1'),
            'layout_tab_2': SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: const ['val_tab_2'],
              },
              slotTypes: const {'val_tab_2': 'registry:Value'},
            ),
            'val_tab_2': const SuperValueConfig(label: 'Contenu Onglet 2'),
          },
        );

        final registry = Registry()..bootstrap();
        final store = _InMemoryStore(initialAppearance);
        final tabController = registry.tabController('main-tab');
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => ValueListenableBuilder<SuperTabConfig>(
                valueListenable: tabController,
                builder: (_, cfg, _) => SuperTab(id: 'main-tab', config: cfg),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          SuperApp(router: router, appearanceStore: store, registry: registry),
        );
        await tester.pumpAndSettle();

        // Onglet 1 actif initialement.
        expect(find.text('Contenu Onglet 1'), findsOneWidget);
        expect(find.text('Contenu Onglet 2'), findsNothing);

        // L'IA commence à streamer un composant imbriqué dans l'onglet 2 -> bascule automatique !
        VibeWorkHighlightController.instance.setStreamingTargets(['val_tab_2']);
        await tester.pumpAndSettle();

        expect(find.text('Contenu Onglet 2'), findsOneWidget);
        expect(find.text('Contenu Onglet 1'), findsNothing);

        // Fin du streaming + pulse -> le tab reste sur l'onglet 2 puis l'utilisateur peut recliquer sur l'onglet 1.
        VibeWorkHighlightController.instance.clearStreamingTargets();
        VibeWorkHighlightController.instance.pulseTargets(
          modifiedIds: const {'val_tab_2'},
        );
        await tester.pumpAndSettle();
        expect(find.text('Contenu Onglet 2'), findsOneWidget);

        await tester.tap(find.text('Général'));
        await tester.pumpAndSettle();
        expect(find.text('Contenu Onglet 1'), findsOneWidget);
        expect(find.text('Contenu Onglet 2'), findsNothing);
      },
    );
  });
}
