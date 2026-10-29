import 'dart:convert';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late String repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('super-chart-test-');
    store = JsonRepositoryStore(directory);
    await store.create('Analytics');
    repository = await store.idOf('Analytics');
    await store.save(
      'Analytics',
      jsonEncode({
        'ventes': [
          {'mois': 'Janvier', 'ca': 120, 'cout': 80, 'x': 1},
          {'mois': 'Février', 'ca': 180, 'cout': 95, 'x': 2},
          {'mois': 'Mars', 'ca': 150, 'cout': 90, 'x': 3},
        ],
        'clients': [
          {
            'nom': 'Alice',
            'commandes': [
              {'ref': 'A1', 'montant': 50},
              {'ref': 'A2', 'montant': 75},
            ],
          },
          {
            'nom': 'Bob',
            'commandes': [
              {'ref': 'B1', 'montant': 210},
            ],
          },
        ],
      }),
      expectedText: await store.read('Analytics'),
    );
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> real(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      await action();
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    });
    await tester.pumpAndSettle();
  }

  group('SuperChartConfig serialization & validation', () {
    test('round-trips through toTypedJson and ComponentConfig.fromJson', () {
      final config = SuperChartConfig(
        binding: JsonTextBinding(repositoryId: repository, path: 'ventes'),
        kind: SuperChartKind.bar,
        labelPath: 'mois',
        series: const [
          SuperChartSeries(
            id: 'ca',
            label: 'Chiffre d’affaires',
            valuePath: 'ca',
            color: Color(0xFF3B82F6),
            strokeWidth: 4,
            radius: 8,
          ),
          SuperChartSeries(
            id: 'cout',
            label: 'Coûts',
            valuePath: 'cout',
            color: Color(0xFFEF4444),
          ),
        ],
        barStacked: true,
        showGrid: false,
        showAxisTitles: true,
        xAxisTitle: 'Mois',
        yAxisTitle: 'EUR',
        minY: 0,
        maxY: 500,
      );

      final typed = config.toTypedJson();
      expect(typed['type'], 'chart');
      final decoded = ComponentConfig.fromJson(typed);
      expect(decoded, isA<SuperChartConfig>());
      expect(decoded, equals(config));

      final compact = config.toTypedCompactJson();
      final fromCompact = ComponentConfig.fromJson(compact);
      expect(fromCompact, equals(config));
    });

    test('validates invalid series and bounds', () {
      expect(
        () => SuperChartConfig(series: const []).validate(),
        throwsFormatException,
      );
      expect(
        () => SuperChartConfig(minY: 100, maxY: 50).validate(),
        throwsFormatException,
      );
      expect(
        () => SuperChartConfig(labelPath: 'clients[?].nom').validate(),
        throwsFormatException,
      );
      expect(
        () => SuperChartConfig(
          series: const [
            SuperChartSeries(id: 'dup', valuePath: 'a'),
            SuperChartSeries(id: 'dup', valuePath: 'b'),
          ],
        ).validate(),
        throwsFormatException,
      );
    });
  });

  group('SuperChart widget, repository binding & selection sync', () {
    testWidgets('renders all 5 fl_chart kinds from bound repository array', (
      tester,
    ) async {
      final notifier = ValueNotifier(
        SuperChartConfig(
          binding: JsonTextBinding(repositoryId: repository, path: 'ventes'),
          kind: SuperChartKind.line,
          labelPath: 'mois',
          series: const [
            SuperChartSeries(
              id: 's1',
              label: 'CA',
              valuePath: 'ca',
              secondaryValuePath: 'x',
            ),
          ],
        ),
      );

      await real(tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: JsonRepositoryScope(
                store: store,
                child: SizedBox(
                  width: 600,
                  height: 400,
                  child: ValueListenableBuilder<SuperChartConfig>(
                    valueListenable: notifier,
                    builder: (context, cfg, _) =>
                        SuperChart(id: 'sales-chart', config: cfg),
                  ),
                ),
              ),
            ),
          ),
        );
      });

      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Janvier'), findsWidgets);
      expect(find.text('Février'), findsWidgets);

      for (final (kind, type) in [
        (SuperChartKind.bar, BarChart),
        (SuperChartKind.pie, PieChart),
        (SuperChartKind.scatter, ScatterChart),
        (SuperChartKind.radar, RadarChart),
      ]) {
        notifier.value = notifier.value.copyWith(kind: kind);
        await tester.pumpAndSettle();
        expect(find.byType(type), findsOneWidget);
      }
    });

    testWidgets(
      'synchronizes selection bidirectionally with JsonArrayBinding and master/detail SuperValue',
      (tester) async {
        await real(tester, () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: JsonRepositoryScope(
                  store: store,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 600,
                        height: 320,
                        child: SuperChart(
                          id: 'ventes-chart',
                          config: SuperChartConfig(
                            binding: JsonTextBinding(
                              repositoryId: repository,
                              path: 'ventes',
                            ),
                            kind: SuperChartKind.bar,
                            labelPath: 'mois',
                            series: const [
                              SuperChartSeries(
                                id: 'ca',
                                label: 'CA',
                                valuePath: 'ca',
                              ),
                            ],
                          ),
                        ),
                      ),
                      SuperValue(
                        id: 'selected-month',
                        config: SuperValueConfig(
                          mode: SuperValueMode.display,
                          binding: JsonTextBinding(
                            repositoryId: repository,
                            path: 'ventes[?].mois',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });

        final arrayBinding = store.bindingOf(repository).array('ventes');
        expect(arrayBinding.selection, isNull);

        // Clic sur la 2e catégorie (Février, index 1) dans le graphique
        await real(tester, () async {
          await tester.tap(
            find.byKey(const ValueKey('super-chart-item-ventes-chart-1')),
          );
        });

        expect(arrayBinding.selection, equals([1]));
        expect(find.text('Février'), findsWidgets);

        // Changement externe de sélection sur le repository -> met à jour le graphique
        await real(tester, () async {
          arrayBinding.select(const [], 2);
        });
        expect(arrayBinding.selection, equals([2]));
      },
    );

    testWidgets('resolves nested wildcard path clients[?].commandes', (
      tester,
    ) async {
      await real(tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: JsonRepositoryScope(
                store: store,
                child: SizedBox(
                  width: 600,
                  height: 350,
                  child: SuperChart(
                    id: 'orders-chart',
                    config: SuperChartConfig(
                      binding: JsonTextBinding(
                        repositoryId: repository,
                        path: 'clients[?].commandes',
                      ),
                      kind: SuperChartKind.radar,
                      labelPath: 'ref',
                      series: const [
                        SuperChartSeries(
                          id: 'montant',
                          label: 'Montant',
                          valuePath: 'montant',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      });

      // Sans client sélectionné, affiche le message d'attente de sélection.
      expect(find.text('Aucune ligne sélectionnée.'), findsOneWidget);

      // Sélectionne Bob (index 1, qui n'a qu'1 commande -> RadarChart padde à 3 sans crash).
      await real(tester, () async {
        store.bindingOf(repository).array('clients').select(const [], 1);
      });

      expect(find.byType(RadarChart), findsOneWidget);
      expect(find.text('B1'), findsWidgets);
    });
  });

  group('SuperChartEditor & EditorPageGraph duplication', () {
    testWidgets(
      'right-click directly on fl_chart canvas opens context menu and chart editor',
      (tester) async {
        await real(tester, () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: JsonRepositoryScope(
                  store: store,
                  child: SizedBox(
                    width: 600,
                    height: 360,
                    child: SuperChart(
                      id: 'ctx-chart',
                      config: SuperChartConfig(
                        binding: JsonTextBinding(
                          repositoryId: repository,
                          path: 'ventes',
                        ),
                        kind: SuperChartKind.line,
                        labelPath: 'mois',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        });

        expect(find.byType(LineChart), findsOneWidget);

        // Clic droit au centre du LineChart (qui enregistre ses propres recognizers)
        await tester.tap(find.byType(LineChart), buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        final menuEntry = find.byKey(const ValueKey('style-menu-Graphique'));
        expect(menuEntry, findsOneWidget);

        await real(tester, () async {
          await tester.tap(menuEntry);
        });

        expect(
          find.byKey(const ValueKey('super-chart-editor')),
          findsOneWidget,
        );
      },
    );

    testWidgets('edits chart type and series in showSuperChartEditor', (
      tester,
    ) async {
      SuperChartConfig? saved;
      final initial = SuperChartConfig(
        binding: JsonTextBinding(repositoryId: repository, path: 'ventes'),
        kind: SuperChartKind.line,
        labelPath: 'mois',
      );

      await real(tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: JsonRepositoryScope(
                store: store,
                child: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () async {
                      saved = await showSuperChartEditor(
                        context: context,
                        config: initial,
                      );
                    },
                    child: const Text('Ouvrir'),
                  ),
                ),
              ),
            ),
          ),
        );
      });

      await real(tester, () async {
        await tester.tap(find.text('Ouvrir'));
      });

      expect(find.byKey(const ValueKey('super-chart-editor')), findsOneWidget);

      // Ajouter une 2e série
      await tester.tap(find.byKey(const ValueKey('super-chart-add-series')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('super-chart-series-path-0')),
        'ca',
      );
      await tester.enterText(
        find.byKey(const ValueKey('super-chart-series-path-1')),
        'cout',
      );

      await real(tester, () async {
        await tester.tap(find.byKey(const ValueKey('super-chart-apply')));
      });

      expect(saved, isNotNull);
      expect(saved!.series.length, 2);
      expect(saved!.series[0].valuePath, 'ca');
      expect(saved!.series[1].valuePath, 'cout');
    });

    test('EditorPageGraph duplicates page containing a Chart component', () {
      final registry = Registry()..bootstrap();
      final chartConfig = SuperChartConfig(
        binding: JsonTextBinding(repositoryId: repository, path: 'ventes'),
        kind: SuperChartKind.pie,
        labelPath: 'mois',
      );
      final appearance = Appearance(
        components: {
          'page-1': NativeComponentConfig(
            placements: const {
              'body': ['chart-1'],
            },
            slotTypes: const {'chart-1': 'registry:Chart'},
          ),
          'chart-1': chartConfig,
        },
      );

      final duplicated = EditorPageGraph.duplicate(
        appearance: appearance,
        registry: registry,
        sourcePageId: 'page-1',
        targetPageId: 'page-2',
      );

      final copiedPage = duplicated.nativeComponent('page-2');
      final copiedChartId = copiedPage.placements['body']!.single;
      expect(copiedChartId, isNot('chart-1'));
      expect(duplicated.chartComponent(copiedChartId), equals(chartConfig));
    });
  });
}
