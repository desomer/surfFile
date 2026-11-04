import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_extensions/super_container_extensions.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  test('SuperCodeExtension and SuperChartExtension register dedicated Dart generators', () {
    final registry = Registry()
      ..bootstrap()
      ..registerAllExtensions();

    expect(registry.registry['Code']!.dartGenerator, isA<SuperCodeDartGenerator>());
    expect(registry.registry['Chart']!.dartGenerator, isA<SuperChartDartGenerator>());

    const repoId = '0123456789abcdef0123456789abcdef';
    final appearance = DefaultAppearance(
      components: {
        'explorer-code': const SuperCodeConfig(
          binding: JsonTextBinding(repositoryId: repoId, path: 'source'),
          errorBinding: JsonTextBinding(repositoryId: repoId, path: 'yamlError'),
        ),
        'sales-chart': const SuperChartConfig(
          kind: SuperChartKind.bar,
          binding: JsonTextBinding(repositoryId: repoId, path: 'sales'),
          barStacked: true,
        ),
      },
    );

    final codeExport = DartCodeExporter.export(
      appearance: appearance,
      registry: registry,
      componentId: 'explorer-code',
      componentLabel: 'Code',
    );
    expect(codeExport, contains('const SuperCode('));
    expect(codeExport, contains("path: 'source'"));
    expect(codeExport, contains("path: 'yamlError'"));

    final chartExport = DartCodeExporter.export(
      appearance: appearance,
      registry: registry,
      componentId: 'sales-chart',
      componentLabel: 'Sales',
    );
    expect(chartExport, contains('const SuperChart('));
    expect(chartExport, contains('kind: SuperChartKind.bar'));
    expect(chartExport, contains('barStacked: true'));
  });
}
