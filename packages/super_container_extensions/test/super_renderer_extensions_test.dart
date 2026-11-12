import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_extensions/super_container_extensions.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  test('component extensions use the extended add family', () {
    final registry = Registry()
      ..bootstrap()
      ..registerAllExtensions();
    expect(registry.registry['Chart']!.addFamily, ComponentAddFamily.extended);
    expect(registry.registry['Code']!.addFamily, ComponentAddFamily.extended);
  });

  for (final (type, config, widgetType) in <(String, ComponentConfig, Type)>[
    ('Code', const SuperCodeConfig(), SuperCode),
    ('Chart', SuperChartConfig(), SuperChart),
  ]) {
    testWidgets('$type exports and renders with the host extension catalog', (
      tester,
    ) async {
      final registry = Registry()
        ..bootstrap()
        ..registerAllExtensions();
      addTearDown(registry.dispose);
      final appearance = Appearance(
        components: {
          'page': ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.body: ['extension'],
            },
            slotTypes: {'extension': 'registry:$type'},
          ),
          'extension': config,
        },
      );
      final fragment = EditorPageGraph.fragment(
        appearance: appearance,
        registry: registry,
        componentId: 'extension',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuperRenderer(
              registry: registry,
              source: AppearanceTransfer.export(
                fragment,
                {...TransferGroup.values},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(widgetType), findsOneWidget);
      expect(find.byKey(const ValueKey('renderer-error')), findsNothing);
      expect(registry.componentConfigById, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
