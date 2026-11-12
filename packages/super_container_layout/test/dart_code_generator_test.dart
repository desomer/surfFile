import 'dart:async' show unawaited;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_selection_region.dart';

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
    const repoId = 'pan_model_repository';

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

  testWidgets(
    'composed RegisteredComponent with unmounted tabs, mismatched slot IDs and EditableSurface exports without omitted widgets',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier<Appearance>(DefaultAppearance());
      addTearDown(appearance.dispose);
      registry.bindAppearance(appearance);

      registry.registerComponent(
        'sub-card',
        RegisteredComponent.composable(
          label: 'Sub Card',
          duplication: ComponentDuplicationContract.newContainer,
          instanceBuilder: (_, id) => EditableSurface(
            id: id,
            label: 'Sub Card',
            menuType: 'Card',
            style: const ContainerStyle(color: Color(0xFF2B382C)),
            child: const SuperValue(
              id: 'sub-card-value',
              config: SuperValueConfig(initialText: 'Inside Card'),
            ),
          ),
        ),
      );

      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
      );
      addTearDown(router.dispose);
      final app = SuperApp(router: router, registry: registry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppearanceScope(
              controller: appearance,
              child: SuperAppScope(
                app: app,
                child: SuperTab(
                  id: 'composed-tabs',
                  label: 'Composed Tabs',
                  config: SuperTabConfig(
                    placements: const {
                      'tabs': ['tab-1', 'tab-2'],
                      'content:tab-1': ['field-a', 'card-slot'],
                      'content:tab-2': ['unmounted-field'],
                    },
                    slotTypes: const {'card-slot': 'component:sub-card'},
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'tab-1',
                      label: 'Tab 1',
                      builder: (_) => const SuperAction(
                        id: 'tab-1-i',
                        config: SuperActionConfig(label: 'Tab 1'),
                      ),
                    ),
                    BuilderSlot(
                      id: 'tab-2',
                      label: 'Tab 2',
                      builder: (_) => const SuperAction(
                        id: 'tab-2-i',
                        config: SuperActionConfig(label: 'Tab 2'),
                      ),
                    ),
                    BuilderSlot(
                      id: 'field-a',
                      label: 'Field A',
                      builder: (_) => const SuperValue(
                        id: 'field-a-i',
                        config: SuperValueConfig(label: 'Label A'),
                      ),
                    ),
                    BuilderSlot(
                      id: 'card-slot',
                      label: 'Card Slot',
                      builder: (context) =>
                          SuperApp.of(context).registry!
                              .component('sub-card')
                              .builder(context),
                    ),
                    BuilderSlot(
                      id: 'unmounted-field',
                      label: 'Unmounted Field',
                      builder: (_) => const SuperValue(
                        id: 'unmounted-field-i',
                        config: SuperValueConfig(
                          initialText: 'Hidden tab text',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final slotFinder = find.byWidgetPredicate(
        (w) => w is EditorSlot && w.id == 'composed-tabs' && w.zoneId == null,
      );
      expect(slotFinder, findsOneWidget);
      final slotState = tester.state<EditorSlotState>(slotFinder);

      // Les actions des onglets fournies via BuilderSlot avec le même ID (ex. tab-1)
      // conservent bien leur libellé configuré au lieu d'être écrasées par un fallback vide.
      expect(find.text('Tab 1'), findsOneWidget);
      expect(find.text('Tab 2'), findsOneWidget);

      final export = slotState.buildContentExport();
      expect(export.omitted, isEmpty);

      final dartCode = slotState.buildDartContentExport(export);
      expect(dartCode, contains("label: 'Tab 1'"));
      expect(dartCode, contains("label: 'Tab 2'"));
      expect(dartCode, contains("label: 'Label A'"));
      expect(dartCode, contains("initialText: 'Hidden tab text'"));
      // Le dartCode généré avec decomposeComponents: false régénère AUSSI
      // le bloc _registry.registerComponent('sub-card', ...) du composant composé !
      expect(
        dartCode,
        contains(
          "_registry.registerComponent(\n  'sub-card',\n  RegisteredComponent.composable(",
        ),
      );
      expect(dartCode, contains("initialText: 'Inside Card'"));
      expect(
        dartCode,
        contains(
          "SuperApp.of(context).registry!.component('sub-card').builder(context)",
        ),
      );

      // Avec decomposeComponents: true, le composant marqué composable (sub-card)
      // est décomposé directement en EditableSurface + SuperValue sans appel au registre.
      final decomposedDartCode = slotState.buildDartContentExport(export, true);
      expect(
        decomposedDartCode.contains("registry!.component('sub-card')"),
        isFalse,
      );
      expect(decomposedDartCode, contains('EditableSurface('));
      expect(decomposedDartCode, contains("initialText: 'Inside Card'"));
    },
  );

  testWidgets(
    'AppearanceTransferDialog toggles decomposeComponents option in Code Dart mode',
    (tester) async {
      final registry = Registry()..bootstrap();
      registry.registerComponent(
        'composable-child',
        RegisteredComponent.composable(
          label: 'Composable Child',
          duplication: ComponentDuplicationContract.superValue,
          instanceBuilder: (_, id) => SuperValue(
            id: id,
            config: const SuperValueConfig(initialText: 'Decomposed Value'),
          ),
        ),
      );
      registry.registerComponent(
        'atomic-child',
        RegisteredComponent(
          label: 'Atomic Child',
          duplication: ComponentDuplicationContract.superValue,
          decomposableOnExport: false,
          instanceBuilder: (_, id) => SuperValue(
            id: id,
            config: const SuperValueConfig(initialText: 'Atomic Value'),
          ),
        ),
      );

      final appearance = DefaultAppearance(
        components: {
          'parent-layout': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['slot-comp', 'slot-atom'],
            },
            slotTypes: {
              'slot-comp': 'component:composable-child',
              'slot-atom': 'component:atomic-child',
            },
          ),
          'slot-comp': const SuperValueConfig(initialText: 'Decomposed Value'),
          'slot-atom': const SuperValueConfig(initialText: 'Atomic Value'),
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
              dartExportWithOptionsBuilder:
                  (current, {required decomposeComponents}) =>
                      DartCodeExporter.export(
                        appearance: current,
                        registry: registry,
                        componentId: 'parent-layout',
                        componentLabel: 'Parent Layout',
                        decomposeComponents: decomposeComponents,
                      ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Code Dart'));
      await tester.pumpAndSettle();

      final decomposeChip = find.byKey(
        const ValueKey('transfer-export-decompose'),
      );
      expect(decomposeChip, findsOneWidget);

      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey('transfer-export-text')),
      );
      // Coché par défaut : composable-child est décomposé, atomic-child reste en référence
      expect(
        textField.controller!.text,
        contains("initialText: 'Decomposed Value'"),
      );
      expect(
        textField.controller!.text.contains("component('composable-child')"),
        isFalse,
      );
      expect(textField.controller!.text, contains("component('atomic-child')"));

      // Décoche l'option : les deux composants sont conservés par référence
      await tester.tap(decomposeChip);
      await tester.pumpAndSettle();

      expect(
        textField.controller!.text,
        contains("component('composable-child')"),
      );
      expect(textField.controller!.text, contains("component('atomic-child')"));
    },
  );

  testWidgets(
    'Context menu 3-dots Configure as... opens dialog and extracts subcomponent on export',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier<Appearance>(DefaultAppearance());
      addTearDown(appearance.dispose);
      registry.bindAppearance(appearance);
      final editMode = ValueNotifier<bool>(true);
      addTearDown(editMode.dispose);

      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
      );
      addTearDown(router.dispose);
      final app = SuperApp(router: router, registry: registry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppearanceScope(
              controller: appearance,
              child: StyleEditScope(
                controller: editMode,
                child: SuperAppScope(
                  app: app,
                  child: SuperLayout(
                    id: 'root-layout',
                    label: 'Root Layout',
                    config: const SuperLayoutConfig(
                      placements: {
                        SuperLayoutZone.center: ['sub-value'],
                      },
                    ),
                    slots: [
                      BuilderSlot(
                        id: 'sub-value',
                        label: 'Sub Value',
                        builder: (_) => const SuperValue(
                          id: 'sub-value',
                          config: SuperValueConfig(initialText: 'Hello World'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final subSlotFinder = find.byWidgetPredicate(
        (w) => w is EditorSlot && w.id == 'sub-value' && w.zoneId == null,
      );
      expect(subSlotFinder, findsOneWidget);
      final subSlotState = tester.state<EditorSlotState>(subSlotFinder);

      // Ouvre le menu contextuel sur le sous-composant
      unawaited(subSlotState.openMenu(const Offset(100, 100)));
      await tester.pumpAndSettle();

      // Clique sur les 3 points verticaux de 'Valeur' (label par défaut de SuperValue)
      final moreButton = find.byKey(const ValueKey('style-menu-more-Valeur'));
      expect(moreButton, findsOneWidget);
      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      // Clique sur l'item 'Configure as...'
      final configureAsItem = find.byKey(
        const ValueKey('style-menu-configure-as-Valeur'),
      );
      expect(configureAsItem, findsOneWidget);
      await tester.tap(configureAsItem);
      await tester.pumpAndSettle();

      // Vérifie que la boîte de dialogue 'Configure as...' est ouverte
      expect(find.text('Configure as...'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('configure-as-component-name')),
        'my-custom-sub',
      );
      // Active 'Forcer en composant à l’export' (qui active aussi 'Générer un composant à l’export')
      await tester.tap(find.byKey(const ValueKey('configure-as-force-switch')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('configure-as-save')));
      await tester.pumpAndSettle();

      final savedOpts = registry.exportOptionsFor('sub-value');
      expect(savedOpts, isNotNull);
      expect(savedOpts!.componentName, 'my-custom-sub');
      expect(savedOpts.generateComponentOnExport, isTrue);
      expect(savedOpts.forceComponentOnExport, isTrue);

      // Exporte le parent 'root-layout' même avec decomposeComponents: true :
      // comme forceComponentOnExport est true, 'sub-value' génère son propre registerComponent
      // et est référencé dans 'root-layout'.
      final rootSlotFinder = find.byWidgetPredicate(
        (w) => w is EditorSlot && w.id == 'root-layout' && w.zoneId == null,
      );
      final rootSlotState = tester.state<EditorSlotState>(rootSlotFinder);
      final export = rootSlotState.buildContentExport();
      final dartCode = rootSlotState.buildDartContentExport(export, true);

      expect(
        dartCode,
        contains(
          "_registry.registerComponent(\n  'my-custom-sub',\n  RegisteredComponent(",
        ),
      );
      expect(
        dartCode,
        contains(
          "SuperApp.of(context).registry!.component('my-custom-sub').builder(context)",
        ),
      );
      expect(
        dartCode,
        contains(
          "_registry.registerComponent(\n  'root-layout',\n  RegisteredComponent(",
        ),
      );
    },
  );

  testWidgets(
    'RegisteredComponent.composable (like panString) displays visual composed badge on canvas and in context menu',
    (tester) async {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier<Appearance>(DefaultAppearance());
      addTearDown(appearance.dispose);
      registry.bindAppearance(appearance);
      final editMode = ValueNotifier<bool>(true);
      addTearDown(editMode.dispose);

      registry.registerComponent(
        'panString',
        RegisteredComponent.composable(
          label: 'panString',
          duplication: ComponentDuplicationContract.newContainer,
          instanceBuilder: (_, id) => EditableSurface(
            id: id,
            label: 'WBYiTwqr2a',
            menuType: 'Card',
            style: const ContainerStyle(color: Color(0xFFC5A9F5)),
            child: const SuperValue(
              id: 'field-description',
              config: SuperValueConfig(label: 'Description'),
            ),
          ),
        ),
      );

      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
      );
      addTearDown(router.dispose);
      final app = SuperApp(router: router, registry: registry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppearanceScope(
              controller: appearance,
              child: StyleEditScope(
                controller: editMode,
                child: SuperAppScope(
                  app: app,
                  child: Builder(
                    builder: (context) =>
                        SuperApp.of(context).registry!
                            .component('panString')
                            .builder(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Le slot racine de panString porte l'identité de composant composé
      final rootSlotFinder = find.byWidgetPredicate(
        (w) => w is EditorSlot && w.label == 'WBYiTwqr2a' && w.zoneId == null,
      );
      expect(rootSlotFinder, findsOneWidget);
      final rootSlotState = tester.state<EditorSlotState>(rootSlotFinder);
      expect(rootSlotState.composedComponentInfo, isNotNull);
      expect(rootSlotState.composedComponentInfo!.componentName, 'panString');
      expect(rootSlotState.composedComponentInfo!.composable, isTrue);

      // L'enfant interne (field-description) ne doit PAS hériter du badge de panString
      final childSlotFinder = find.byWidgetPredicate(
        (w) =>
            w is EditorSlot && w.id == 'field-description' && w.zoneId == null,
      );
      expect(childSlotFinder, findsOneWidget);
      final childSlotState = tester.state<EditorSlotState>(childSlotFinder);
      expect(childSlotState.composedComponentInfo, isNull);

      // Le CustomPaint sur le canevas utilise EditorComposedComponentBadgePainter
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.foregroundPainter is EditorComposedComponentBadgePainter &&
              (w.foregroundPainter as EditorComposedComponentBadgePainter)
                      .componentName ==
                  'panString',
        ),
        findsOneWidget,
      );

      // Dans le menu contextuel, l'indicateur 'style-menu-composed-indicator-WBYiTwqr2a' est affiché
      unawaited(rootSlotState.openMenu(const Offset(100, 100)));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('style-menu-composed-indicator-WBYiTwqr2a')),
        findsOneWidget,
      );
      expect(find.text('panString'), findsOneWidget);
    },
  );
}
