import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Registry registry;
  late Appearance appearance;
  setUp(() {
    registry = Registry()..bootstrap();
    appearance = Appearance(
      components: {
        'layout': const SuperLayoutConfig(
          west: true,
          placements: {
            SuperLayoutZone.center: ['card'],
            SuperLayoutZone.west: ['neighbor'],
          },
          slotTypes: {'card': 'registry:Card', 'neighbor': 'registry:Value'},
        ),
        'card': NativeComponentConfig(
          placements: {
            'child': ['text'],
          },
          slotTypes: {'text': 'registry:Value'},
        ),
        'text': const SuperValueConfig(initialText: 'Child'),
        'neighbor': const SuperValueConfig(initialText: 'Outside'),
      },
      styles: {
        'card': const ContainerStyle(radius: 12),
        'text': const ContainerStyle(radius: 4),
        'neighbor': const ContainerStyle(radius: 24),
      },
      behaviors: {
        'text': [
          ComponentBehavior(
            id: 'click',
            trigger: BehaviorTrigger.click,
            action: EmitEventAction(eventId: 'child.clicked'),
          ),
        ],
      },
    );
  });

  test(
    'exports exact descendants with styles, behaviors and standard envelope',
    () {
      final fragment = EditorPageGraph.fragment(
        appearance: appearance,
        registry: registry,
        componentId: 'card',
      );
      expect(fragment.components.keys, containsAll(['card', 'text']));
      expect(fragment.components.containsKey('layout'), isFalse);
      expect(fragment.components.containsKey('neighbor'), isFalse);
      expect(fragment.styles.keys, unorderedEquals(['card', 'text']));
      expect(fragment.behaviors.keys, ['text']);
      final imported = AppearanceTransfer.import(
        Appearance(),
        AppearanceTransfer.export(fragment, {...TransferGroup.values}),
        {...TransferGroup.values},
      );
      expect(imported.pageCatalog.homePageId, isNotNull);
      expect(imported.valueComponent('text').initialText, 'Child');
      expect(appearance.components.length, 4);
    },
  );

  test('exports only the requested zone', () {
    final fragment = EditorPageGraph.fragment(
      appearance: appearance,
      registry: registry,
      componentId: 'layout',
      zoneId: 'center',
    );
    expect(fragment.components.containsKey('layout'), isFalse);
    expect(fragment.components.containsKey('neighbor'), isFalse);
    expect(fragment.components.keys, containsAll(['card', 'text']));
  });

  test('includes instantiated defaults without persisting them', () {
    registry.valueController(
      'runtime',
      fallback: const SuperValueConfig(initialText: 'Runtime'),
    );
    final fragment = EditorPageGraph.fragment(
      appearance: appearance,
      registry: registry,
      componentId: 'runtime',
    );
    expect(fragment.valueComponent('runtime').initialText, 'Runtime');
    expect(appearance.components.containsKey('runtime'), isFalse);
  });

  test('cycles and unknown types fail explicitly', () {
    final cyclic = appearance.withComponent(
      'card',
      NativeComponentConfig(
        placements: {
          'child': ['card'],
        },
        slotTypes: {'card': 'registry:Card'},
      ),
    );
    expect(
      () => EditorPageGraph.fragment(
        appearance: cyclic,
        registry: registry,
        componentId: 'card',
      ),
      throwsFormatException,
    );
    final unknown = appearance.withComponent(
      'card',
      NativeComponentConfig(
        placements: {
          'child': ['custom'],
        },
        slotTypes: {'custom': 'registry:Unknown'},
      ),
    );
    expect(
      () => EditorPageGraph.fragment(
        appearance: unknown,
        registry: registry,
        componentId: 'card',
      ),
      throwsFormatException,
    );
  });

  for (final (type, config) in <(String, ComponentConfig)>[
    (
      'ListView',
      const SuperListViewConfig(
        template: SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['text'],
          },
          slotTypes: {'text': 'registry:Value'},
        ),
      ),
    ),
    (
      'Tab',
      SuperTabConfig(
        placements: {'tab0': ['text']},
        slotTypes: {'text': 'registry:Value'},
      ),
    ),
    (
      'TreeView',
      SuperTreeViewConfig(
        placements: {'header': ['text']},
        slotTypes: {'text': 'registry:Value'},
      ),
    ),
    (
      'Table',
      SuperTableConfig(
        placements: {'column0': ['text']},
        slotTypes: {'text': 'registry:Value'},
      ),
    ),
    for (final native in [
      'Card',
      'ApplicationBar',
      'BottomNavigationBar',
      'BottomAppBar',
      'NavigationRail',
      'Expansible',
      'Menu',
    ])
      (
        native,
        NativeComponentConfig(
          placements: {'child': ['text']},
          slotTypes: {'text': 'registry:Value'},
        ),
      ),
  ]) {
    test('$type exports descendant configurations', () {
      final source = appearance
          .withComponent('target', config)
          .withComponent(
            'parent',
            NativeComponentConfig(
              placements: {'child': ['target']},
              slotTypes: {'target': 'registry:$type'},
            ),
          );
      final fragment = EditorPageGraph.fragment(
        appearance: source,
        registry: registry,
        componentId: 'target',
      );
      expect(fragment.components.keys, containsAll(['target', 'text']));
      expect(fragment.components.containsKey('parent'), isFalse);
      expect(fragment.components.containsKey('neighbor'), isFalse);
    });
  }

  test('grid export excludes other zones and keeps shared descendants once', () {
    final source = appearance.withComponent(
      'grid',
      const SuperLayoutConfig(
        positioning: SuperLayoutPositioning.grid,
        grid: GridLayoutConfig(items: {'card': GridSlotPosition()}),
        placements: {
          SuperLayoutZone.west: ['neighbor'],
        },
        slotTypes: {'card': 'registry:Card', 'neighbor': 'registry:Value'},
      ),
    );
    final fragment = EditorPageGraph.fragment(
      appearance: source,
      registry: registry,
      componentId: 'grid',
      zoneId: 'grid',
    );
    expect(fragment.components.keys, containsAll(['card', 'text']));
    expect(fragment.components.containsKey('neighbor'), isFalse);
  });
}
