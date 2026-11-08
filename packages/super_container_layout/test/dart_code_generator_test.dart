import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  test(
    'every bootstrapped component registers a dedicated ComponentDartGenerator',
    () {
      final registry = Registry()..bootstrap();
      for (final entry in registry.registry.entries) {
        expect(
          entry.value.dartGenerator,
          isNotNull,
          reason: 'Missing dartGenerator for registry component "${entry.key}"',
        );
      }
      expect(
        registry.registry['Layout']!.dartGenerator,
        isA<SuperLayoutDartGenerator>(),
      );
      expect(
        registry.registry['Value']!.dartGenerator,
        isA<SuperValueDartGenerator>(),
      );
      expect(
        registry.registry['Action']!.dartGenerator,
        isA<SuperActionDartGenerator>(),
      );
      expect(
        registry.registry['Indicator']!.dartGenerator,
        isA<SuperIndicatorDartGenerator>(),
      );
      expect(
        registry.registry['Separator']!.dartGenerator,
        isA<SuperSeparatorDartGenerator>(),
      );
      expect(
        registry.registry['ListView']!.dartGenerator,
        isA<SuperListViewDartGenerator>(),
      );
      expect(
        registry.registry['TreeView']!.dartGenerator,
        isA<SuperTreeViewDartGenerator>(),
      );
      expect(
        registry.registry['Tab']!.dartGenerator,
        isA<SuperTabDartGenerator>(),
      );
      expect(
        registry.registry['Table']!.dartGenerator,
        isA<SuperTableDartGenerator>(),
      );
      expect(
        registry.registry['Card']!.dartGenerator,
        isA<SuperCardDartGenerator>(),
      );
      expect(
        registry.registry['Renderer']!.dartGenerator,
        isA<SuperRendererDartGenerator>(),
      );
    },
  );

  test('DartCodeExporter generates RegisteredComponent code matching main.dart structure', () {
    final registry = Registry()..bootstrap();
    const repoId = '0123456789abcdef0123456789abcdef';

    final appearance = DefaultAppearance(
      components: {
        'A': const SuperLayoutConfig(
          label: 'layout',
          west: true,
          westSize: 320,
          east: true,
          eastSize: 300,
          autoSides: {SuperLayoutZone.center},
          sideResizing: {SuperLayoutZone.west: true},
          placements: {
            SuperLayoutZone.center: ['explorer-tree'],
            SuperLayoutZone.east: ['global-node-properties'],
          },
          slotLabels: {
            'explorer-tree': 'Tree',
            'global-node-properties': 'Global Node Properties',
          },
        ),
        'global-node-properties': const SuperValueConfig(
          binding: JsonTextBinding(
            repositoryId: repoId,
            path: 'nodes[?].propertiesText',
          ),
          minLines: 5,
          maxLines: 5,
        ),
        'explorer-tree': SuperTreeViewConfig(
          binding: const JsonTextBinding(repositoryId: repoId, path: 'nodes'),
          placements: const {
            SuperTreeViewConfig.headerZone: ['header'],
            SuperTreeViewConfig.dataZone: ['data'],
          },
        ),
        'header': const SuperLayoutConfig(
          label: 'Node header',
          zoneAxes: {SuperLayoutZone.center: Axis.horizontal},
          zoneFlows: {
            SuperLayoutZone.center: ZoneFlowConfig(
              expandSlots: false,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 8,
            ),
          },
          slotSizeConstraints: {
            'tree-node-separator': SlotSizeConstraints(fitContent: false),
          },
          placements: {
            SuperLayoutZone.center: [
              'tree-node-icon',
              'tree-node-name',
              'tree-node-separator',
              'tree-node-type',
            ],
          },
          slotLabels: {
            'tree-node-icon': 'Icon',
            'tree-node-name': 'Name',
            'tree-node-separator': 'Separator',
            'tree-node-type': 'Type',
          },
        ),
        'tree-node-icon': SuperIndicatorConfig(
          icon: 'description',
          iconSize: 18,
          states: IndicatorConfigStates(
            binding: const JsonTextBinding(path: 'typeIcon'),
            named: const {
              'container': SuperIndicatorConfig(icon: 'folder'),
              'value': SuperIndicatorConfig(icon: 'description'),
            },
            namedProperties: const {
              'container': {IndicatorStateProperty.icon},
              'value': {IndicatorStateProperty.icon},
            },
          ),
        ),
        'tree-node-name': const SuperValueConfig(
          binding: JsonTextBinding(path: 'name'),
        ),
        'tree-node-separator': const SuperSeparatorConfig(
          kind: SuperSeparatorKind.spacer,
        ),
        'tree-node-type': const SuperValueConfig(
          binding: JsonTextBinding(path: 'type'),
        ),
        'data': const SuperLayoutConfig(
          label: 'Node data',
          east: true,
          eastSize: 300,
          zoneAxes: {SuperLayoutZone.center: Axis.horizontal},
          zoneFlows: {
            SuperLayoutZone.center: ZoneFlowConfig(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
            ),
          },
          placements: {
            SuperLayoutZone.center: ['tree-node-id', 'tree-node-properties'],
          },
          slotLabels: {
            'tree-node-id': 'ID',
            'tree-node-properties': 'Properties',
          },
        ),
        'tree-node-id': const SuperValueConfig(
          binding: JsonTextBinding(path: 'id'),
        ),
        'tree-node-properties': const SuperValueConfig(
          binding: JsonTextBinding(path: 'propertiesText'),
        ),
      },
      behaviors: {
        'A': [
          ComponentBehavior(
            id: 'global-node-properties-size',
            trigger: BehaviorTrigger.binding,
            action: ZoneSizeBindingAction(
              zone: SuperLayoutZone.east,
              binding: const JsonTextBinding(
                repositoryId: repoId,
                path: 'estSize',
              ),
            ),
          ),
        ],
        'tree-node-name': [
          ComponentBehavior(
            id: 'tree-node-name-click',
            trigger: BehaviorTrigger.click,
            action: EmitEventAction(eventId: 'node.click'),
          ),
        ],
      },
    );

    final exportedFragment = EditorPageGraph.export(
      appearance: appearance,
      registry: registry,
      componentId: 'A',
    );

    final dartCode = DartCodeExporter.export(
      appearance: exportedFragment.appearance,
      registry: registry,
      componentId: 'A',
      componentLabel: 'A',
    );

    expect(
      dartCode,
      contains("_registry.registerComponent(\n  'A',\n  RegisteredComponent("),
    );
    expect(dartCode, contains('ZoneSizeBindingAction('));
    expect(dartCode, contains("SuperTreeView(\n"));
    expect(dartCode, contains('header: SuperLayout('));
    expect(dartCode, contains('data: SuperLayout('));
    expect(dartCode, contains('SuperIndicator('));
    expect(dartCode, contains('IndicatorConfigStates('));
    expect(dartCode, contains("EmitEventAction(eventId: 'node.click')"));
    expect(dartCode, contains('const SuperSeparator('));
    expect(dartCode, contains('kind: SuperSeparatorKind.spacer'));
  });

  testWidgets(
    'AppearanceTransferDialog switches between JSON and Code Dart in content export',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = DefaultAppearance(
        components: {
          'my-value': const SuperValueConfig(
            initialText: 'Bonjour',
            fontSize: 16,
          ),
        },
      );
      final controller = ValueNotifier<Appearance>(appearance);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppearanceTransferDialog(
              controller: controller,
              allowImport: false,
              dartExportBuilder: (current) => DartCodeExporter.export(
                appearance: current,
                registry: registry,
                componentId: 'my-value',
                componentLabel: 'Ma Valeur',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('transfer-export-format')),
        findsOneWidget,
      );
      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey('transfer-export-text')),
      );
      expect(textField.controller!.text, contains('"format"'));

      await tester.tap(find.text('Code Dart'));
      await tester.pumpAndSettle();

      expect(
        textField.controller!.text,
        contains("_registry.registerComponent("),
      );
      expect(textField.controller!.text, contains("'my-value'"));
      expect(textField.controller!.text, contains("initialText: 'Bonjour'"));

      final fileField = tester.widget<TextField>(
        find.byKey(const ValueKey('transfer-file')),
      );
      expect(fileField.controller!.text, endsWith('appearance.dart'));
    },
  );

  test(
    'RegisteredComponent with instanceBuilder propagates slot instance ID',
    () {
      final component = RegisteredComponent(
        label: 'Dynamic Field',
        instanceBuilder: (context, id) => SuperValue(id: id),
      );

      final slot1 = component.createSlot('slot-alpha');
      final slot2 = component.createSlot('slot-beta');

      expect(slot1.id, 'slot-alpha');
      expect(slot2.id, 'slot-beta');

      expect(component.builder, isNotNull);
    },
  );

  testWidgets(
    'RegisteredComponent with instanceBuilder produces independent widgets in tree',
    (tester) async {
      final component = RegisteredComponent(
        label: 'Dynamic Field',
        instanceBuilder: (context, id) => SuperValue(id: id),
      );

      final slot1 = component.createSlot('slot-alpha');
      final slot2 = component.createSlot('slot-beta');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [slot1.buildSlot(context), slot2.buildSlot(context)],
              ),
            ),
          ),
        ),
      );

      final values = tester
          .widgetList<SuperValue>(find.byType(SuperValue))
          .toList();
      expect(values.length, 2);
      expect(values[0].id, 'slot-alpha');
      expect(values[1].id, 'slot-beta');
    },
  );

  test(
    'DartCodeExporter generates dynamic instanceBuilder and cleans catalog key',
    () {
      final registry = Registry()..bootstrap();
      final appearance = DefaultAppearance(
        components: {
          'field-default-i': const SuperValueConfig(
            mode: SuperValueMode.input,
            label: 'Default',
            binding: JsonTextBinding(
              repositoryId: 'cc326cbbacbbbf804230e59ff54534ce',
              path: 'Default',
            ),
            field: SuperTextFieldConfig(variant: TextFieldVariant.outlined),
          ),
        },
      );

      final dartCode = DartCodeExporter.export(
        appearance: appearance,
        registry: registry,
        componentId: 'field-default-i',
        componentLabel: 'Valeur',
      );

      // Clé de catalogue nettoyée du suffixe d'instance technique '-i'
      expect(
        dartCode,
        contains(
          "_registry.registerComponent(\n  'field-default',\n  RegisteredComponent(",
        ),
      );
      // Utilise instanceBuilder au lieu de builder
      expect(dartCode, contains("instanceBuilder: (_, id) =>"));
      // Le widget intérieur utilise l'ID dynamique du slot et n'est pas const
      expect(dartCode, contains("SuperValue(\n          id: id,"));
      // L'ID 'field-default-i' n'est plus dupliqué dans le code généré
      expect(dartCode.contains("'field-default-i'"), isFalse);
    },
  );
}
