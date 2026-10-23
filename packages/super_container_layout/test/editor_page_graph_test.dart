import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/models/editor_page_config.dart';
import 'package:super_container_layout/models/native_component_config.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/models/super_text_field_config.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/automatic_state.dart';
import 'package:super_container_layout/services/pages/editor_page_graph.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';

Registry _registry() => Registry()
  ..bootstrap()
  ..registerFactory('A', const SizedBox());

String Function() _ids([List<String> first = const []]) {
  var i = 0;
  final queue = [...first];
  return () => queue.isNotEmpty ? queue.removeAt(0) : 'new${i++}';
}

EditorPageCatalog _catalog(List<String> ids) => EditorPageCatalog(
  pages: [
    for (final id in ids) EditorPageConfig(id: id, name: id, path: '/$id'),
  ],
);

Appearance _sample() => Appearance(
  styles: {
    'background': const ContainerStyle(radius: 1),
    'cont1': const ContainerStyle(radius: 7),
  },
  layouts: {
    'contA': const SuperLayoutConfig(label: 'global'),
    'lay1': const SuperLayoutConfig(
      label: 'Body',
      north: false,
      positioning: SuperLayoutPositioning.grid,
      swaps: {SuperLayoutZone.west},
      placements: {
        SuperLayoutZone.center: ['cont1', 'txt2', 'nested'],
        SuperLayoutZone.north: ['hiddenTxt'],
      },
      slotTypes: {
        'cont1': 'registry:Card',
        'txt2': 'registry:Value',
        'nested': 'registry:Layout',
        'hiddenTxt': 'registry:Value',
      },
      slotLabels: {'txt2': 'Titre'},
      slotPreferredSizes: {'cont1': Size(10, 20)},
      slotSizeConstraints: {
        'txt2': SlotSizeConstraints(
          minWidth: SlotDimension(5, SlotSizeUnit.pixels),
        ),
      },
      grid: GridLayoutConfig(
        items: {
          'cont1': GridSlotPosition(),
          'txt2': GridSlotPosition(y: 3),
          'nested': GridSlotPosition(y: 6),
        },
      ),
    ),
    'nested': const SuperLayoutConfig(
      placements: {
        SuperLayoutZone.center: ['txt3'],
      },
      slotTypes: {'txt3': 'registry:Value'},
    ),
  },
  nativeComponents: {
    'root': NativeComponentConfig(
      placements: {
        'body': ['scaffold:body'],
      },
    ),
    'p1': NativeComponentConfig(
      placements: {
        'appBar': ['bar1'],
        'body': ['lay1'],
        'drawer': ['txtHidden'],
      },
      regions: {'drawer': false},
      slotTypes: {
        'bar1': 'factory:AppBar',
        'lay1': 'factory:Layout',
        'txtHidden': 'factory:Value',
      },
      slotPreferredSizes: {'lay1': const Size(1, 2)},
    ),
    'bar1': NativeComponentConfig(
      placements: {
        'title': ['txt1'],
      },
      slotTypes: {'txt1': 'factory:Value'},
    ),
  },
  valueComponents: {
    for (final id in ['txt1', 'txt2', 'txt3', 'hiddenTxt', 'txtHidden'])
      id: SuperValueConfig(initialText: id),
  },
  pageCatalog: _catalog(['p1']),
);

void main() {
  test(
    'container children are copied with new IDs and removed with their page',
    () {
      final source = _sample()
          .withNativeComponent(
            'cont1',
            NativeComponentConfig(
              placements: {
                'child': ['inside'],
              },
              slotTypes: {'inside': 'factory:Value'},
            ),
          )
          .withValueComponent(
            'inside',
            const SuperValueConfig(initialText: 'Nested'),
          );
      final copy = EditorPageGraph.duplicate(
        appearance: source,
        registry: _registry(),
        sourcePageId: 'p1',
        targetPageId: 'p2',
        generateId: _ids(),
      );
      final layout = copy.nativeComponents['p2']!.slotsOf('body').single;
      final container = copy.layouts[layout]!
          .placementsOf(SuperLayoutZone.center)
          .first;
      final child = copy.nativeComponents[container]!.slotsOf('child').single;
      expect(child, isNot('inside'));
      expect(
        copy.nativeComponents[container]!.slotTypeOf(child),
        'factory:Value',
      );
      expect(copy.valueComponents[child]!.initialText, 'Nested');
      expect(copy.styles[container], source.styles['cont1']);
      expect(copy.nativeComponents['cont1'], source.nativeComponents['cont1']);
      final removed = EditorPageGraph.remove(
        appearance: source,
        registry: _registry(),
        pageId: 'p1',
      );
      expect(removed.nativeComponents.containsKey('cont1'), isFalse);
      expect(removed.valueComponents.containsKey('inside'), isFalse);
    },
  );

  test(
    'page duplication preserves external repository IDs and binding paths',
    () {
      const binding = JsonTextBinding(
        repositoryId: '0123456789abcdef0123456789abcdef',
        path: 'client.name',
      );
      final source = _sample().withValueComponent(
        'txt1',
        SuperValueConfig(
          binding: binding,
          states: ValueConfigStates(
            binding: const JsonTextBinding(
              repositoryId: '0123456789abcdef0123456789abcdef',
              path: 'client.status',
            ),
            named: {'ready': const SuperValueConfig(binding: binding)},
            namedProperties: {
              'ready': {ValueStateProperty.binding},
            },
            hover: ValueConfigOverride(
              config: const SuperValueConfig(fontSize: 20),
              properties: {ValueStateProperty.fontSize},
            ),
            automatic: {
              AutomaticState.contentHover: ValueConfigOverride(
                config: const SuperValueConfig(binding: binding),
                properties: {ValueStateProperty.binding},
              ),
            },
            order: [
              ValueConfigStates.hoverKey,
              'ready',
              ValueConfigStates.selectedKey,
              AutomaticState.contentHover.key,
            ],
          ),
          field: const SuperTextFieldConfig(
            variant: TextFieldVariant.outlined,
            maxLength: 30,
          ),
        ),
      );
      final result = EditorPageGraph.duplicate(
        appearance: source,
        registry: _registry(),
        sourcePageId: 'p1',
        targetPageId: 'p2',
        generateId: _ids(),
      );
      final copies = result.valueComponents.entries.where(
        (entry) => entry.key != 'txt1' && entry.value.binding != null,
      );
      expect(copies, hasLength(1));
      expect(copies.single.value.binding, binding);
      expect(copies.single.value.field, source.valueComponents['txt1']!.field);
      expect(source.valueComponents['txt1']!.binding, binding);
      expect(
        copies.single.value.states,
        source.valueComponents['txt1']!.states,
      );
      final removed = EditorPageGraph.remove(
        appearance: result,
        registry: _registry(),
        pageId: 'p2',
      );
      expect(removed.valueComponents.containsKey(copies.single.key), isFalse);
      expect(removed.valueComponents['txt1'], source.valueComponents['txt1']);
    },
  );

  test('duplicates an independent deep copy with new IDs', () {
    final source = _sample();
    final originals = {
      'p1',
      'bar1',
      'lay1',
      'txtHidden',
      'txt1',
      'cont1',
      'txt2',
      'nested',
      'hiddenTxt',
      'txt3',
    };
    final result = EditorPageGraph.duplicate(
      appearance: source,
      registry: _registry(),
      sourcePageId: 'p1',
      targetPageId: 'p2',
      // Existing IDs proposed by the generator must never be reused.
      generateId: _ids(['lay1', 'p1', 'txt3']),
    );

    expect(identical(result.pageCatalog, source.pageCatalog), isTrue);
    for (final id in originals) {
      expect(result.nativeComponents[id], source.nativeComponents[id]);
      expect(result.layouts[id], source.layouts[id]);
      expect(result.valueComponents[id], source.valueComponents[id]);
    }
    expect(result.layouts['contA'], source.layouts['contA']);
    expect(result.styles['background'], source.styles['background']);
    expect(result.nativeComponents['root'], source.nativeComponents['root']);
    expect(result.layouts.length, source.layouts.length + 2);
    expect(result.nativeComponents.length, source.nativeComponents.length + 2);
    expect(result.valueComponents.length, source.valueComponents.length + 5);
    expect(result.styles.length, source.styles.length + 1);

    final page = result.nativeComponents['p2']!;
    expect(page.regions, {'drawer': false});
    final bar = page.slotsOf('appBar').single;
    final lay = page.slotsOf('body').single;
    final hidden = page.slotsOf('drawer').single;
    for (final id in [bar, lay, hidden]) {
      expect(originals, isNot(contains(id)));
    }
    expect(page.slotTypeOf(bar), 'factory:AppBar');
    expect(page.slotPreferredSizes, {lay: const Size(1, 2)});
    expect(result.valueComponents[hidden]!.initialText, 'txtHidden');

    final title = result.nativeComponents[bar]!.slotsOf('title').single;
    expect(originals, isNot(contains(title)));
    expect(result.valueComponents[title]!.initialText, 'txt1');

    final layout = result.layouts[lay]!;
    final [cont, txt, nested] = layout.placementsOf(SuperLayoutZone.center);
    final hiddenTxt = layout.placementsOf(SuperLayoutZone.north).single;
    final copied = {cont, txt, nested, hiddenTxt};
    expect(copied.intersection(originals), isEmpty);
    expect(copied.length, 4);
    expect(layout.label, 'Body');
    expect(layout.north, isFalse);
    expect(layout.swaps, {SuperLayoutZone.west});
    expect(layout.positioning, SuperLayoutPositioning.grid);
    expect(layout.slotTypeOf(nested), 'registry:Layout');
    expect(layout.slotLabels, {txt: 'Titre'});
    expect(layout.slotPreferredSizes, {cont: const Size(10, 20)});
    expect(layout.slotSizeConstraints.keys, [txt]);
    expect(layout.grid!.items.keys.toSet(), {cont, txt, nested});
    expect(layout.grid!.items[txt], const GridSlotPosition(y: 3));
    expect(result.styles[cont], const ContainerStyle(radius: 7));
    expect(result.valueComponents[txt]!.initialText, 'txt2');
    expect(result.valueComponents[hiddenTxt]!.initialText, 'hiddenTxt');
    final txt3 = result.layouts[nested]!.placementsOf(SuperLayoutZone.center);
    expect(originals, isNot(contains(txt3.single)));
    expect(result.valueComponents[txt3.single]!.initialText, 'txt3');

    // Editing the copy leaves the original untouched.
    final edited = result.withStyle(cont, const ContainerStyle(radius: 2));
    expect(edited.styles['cont1'], const ContainerStyle(radius: 7));
  });

  test('uses the default generator and copies a shared graph safely', () {
    final source = _sample();
    final first = EditorPageGraph.duplicate(
      appearance: source,
      registry: _registry(),
      sourcePageId: 'p1',
      targetPageId: 'p2',
    );
    final second = EditorPageGraph.duplicate(
      appearance: first,
      registry: _registry(),
      sourcePageId: 'p1',
      targetPageId: 'p3',
    );
    final ids2 = first.layouts.keys.toSet().difference(
      source.layouts.keys.toSet(),
    );
    final ids3 = second.layouts.keys.toSet().difference(
      first.layouts.keys.toSet(),
    );
    expect(ids2.intersection(ids3), isEmpty);
    expect(second.nativeComponents['p2'], first.nativeComponents['p2']);
    expect(
      () => EditorPageGraph.duplicate(
        appearance: first,
        registry: _registry(),
        sourcePageId: 'p1',
        targetPageId: 'p2',
      ),
      throwsFormatException,
    );
  });

  test('refuses custom components without contract atomically', () {
    final source = Appearance(
      nativeComponents: {
        'p1': NativeComponentConfig(
          placements: {
            'body': ['lay'],
          },
          slotTypes: {'lay': 'factory:Layout'},
        ),
      },
      layouts: {
        'lay': const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['a1'],
          },
          slotTypes: {'a1': 'registry:A'},
        ),
      },
    );
    expect(
      () => EditorPageGraph.duplicate(
        appearance: source,
        registry: _registry(),
        sourcePageId: 'p1',
        targetPageId: 'p2',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('« A »'), contains('contrat de duplication')),
        ),
      ),
    );
    expect(source.nativeComponents.keys, ['p1']);
    expect(source.layouts.keys, ['lay']);

    final replaced = _registry()..registerFactory('Value', const SizedBox());
    final text = Appearance(
      nativeComponents: {
        'p1': NativeComponentConfig(
          placements: {
            'body': ['t'],
          },
          slotTypes: {'t': 'factory:Value'},
        ),
      },
    );
    expect(
      () => EditorPageGraph.duplicate(
        appearance: text,
        registry: replaced,
        sourcePageId: 'p1',
        targetPageId: 'p2',
      ),
      throwsFormatException,
    );
  });

  test('refuses unknown components and cycles', () {
    Appearance page(String type) => Appearance(
      nativeComponents: {
        'p1': NativeComponentConfig(
          placements: {
            'body': ['x'],
          },
          slotTypes: {'x': type},
        ),
      },
      layouts: {
        'x': const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['x'],
          },
          slotTypes: {'x': 'registry:Layout'},
        ),
      },
    );
    for (final type in ['factory:Missing', 'component:missing']) {
      expect(
        () => EditorPageGraph.duplicate(
          appearance: page(type),
          registry: _registry(),
          sourcePageId: 'p1',
          targetPageId: 'p2',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('introuvable'),
          ),
        ),
      );
    }
    final cyclic = page('factory:Layout');
    expect(
      () => EditorPageGraph.duplicate(
        appearance: cyclic,
        registry: _registry(),
        sourcePageId: 'p1',
        targetPageId: 'p2',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('cycle'),
        ),
      ),
    );
    final removed = EditorPageGraph.remove(
      appearance: cyclic,
      registry: _registry(),
      pageId: 'p1',
    );
    expect(removed.nativeComponents, isEmpty);
    expect(removed.layouts, isEmpty);
  });

  test('supports explicit custom duplication contracts', () {
    final registry = _registry()
      ..registerFactory(
        'Card',
        const SizedBox(),
        duplication: ComponentDuplicationContract(
          ownedConfigs: (id) => [
            EditorConfigRef.value('$id.title'),
            EditorConfigRef.layout('$id.body'),
          ],
          copyConfig: (ref, value, remap) => switch (value) {
            SuperValueConfig() => SuperValueConfig(
              initialText: '${value.initialText} (copie)',
            ),
            SuperLayoutConfig() => SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: [
                  for (final id in value.placementsOf(SuperLayoutZone.center))
                    remap(id),
                ],
              },
              slotTypes: {
                for (final entry in value.slotTypes.entries)
                  remap(entry.key): entry.value,
              },
            ),
            _ => value,
          },
        ),
      )
      ..registerComponent(
        'badge',
        RegisteredComponent(
          label: 'Badge',
          builder: (_) => const SizedBox(),
          duplication: const ComponentDuplicationContract.stateless(),
        ),
      );
    final source = Appearance(
      nativeComponents: {
        'p1': NativeComponentConfig(
          placements: {
            'body': ['card'],
            'appBar': ['b'],
          },
          slotTypes: {'card': 'factory:Card', 'b': 'component:badge'},
        ),
      },
      valueComponents: {
        'card.title': const SuperValueConfig(initialText: 'Titre'),
        'inner': const SuperValueConfig(initialText: 'inner'),
      },
      layouts: {
        'card.body': const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['inner'],
          },
          slotTypes: {'inner': 'registry:Value'},
        ),
      },
    );
    final result = EditorPageGraph.duplicate(
      appearance: source,
      registry: registry,
      sourcePageId: 'p1',
      targetPageId: 'p2',
      generateId: _ids(),
    );
    final page = result.nativeComponents['p2']!;
    final card = page.slotsOf('body').single;
    final badge = page.slotsOf('appBar').single;
    expect(card, isNot('card'));
    expect(badge, isNot('b'));
    expect(page.slotTypeOf(badge), 'component:badge');
    expect(result.valueComponents['$card.title']!.initialText, 'Titre (copie)');
    final inner = result.layouts['$card.body']!
        .placementsOf(SuperLayoutZone.center)
        .single;
    expect(inner, isNot('inner'));
    // Nested bootstrap components keep their own structural copy.
    expect(result.valueComponents[inner]!.initialText, 'inner');
    expect(result.valueComponents['card.title']!.initialText, 'Titre');
  });

  test('bootstrap builders carry their contract metadata', () {
    final registry = _registry();
    expect(
      registry.registry['Layout']!.duplication,
      same(ComponentDuplicationContract.newLayout),
    );
    expect(registry.registry['AppBar']!.duplication!.ownedConfigs('x'), [
      const EditorConfigRef.nativeComponent('x'),
      const EditorConfigRef.layout('x'),
    ]);
    expect(registry.registry['A']!.duplication, isNull);
  });

  test('removes only owned configurations and keeps shared ones', () {
    final source = Appearance(
      styles: {
        'background': const ContainerStyle(radius: 1),
        'own': const ContainerStyle(radius: 2),
        'shared': const ContainerStyle(radius: 3),
        'global': const ContainerStyle(radius: 4),
        'a1': const ContainerStyle(radius: 5),
      },
      layouts: {
        'l1': const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['own', 'shared', 'global', 'a1'],
          },
          slotTypes: {
            'own': 'registry:Card',
            'shared': 'registry:Card',
            'global': 'registry:Card',
            'a1': 'registry:A',
          },
        ),
        'l2': const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['shared'],
          },
          slotTypes: {'shared': 'registry:Card'},
        ),
        'contA': const SuperLayoutConfig(label: 'global'),
      },
      nativeComponents: {
        'p1': NativeComponentConfig(
          placements: {
            'body': ['l1'],
          },
          slotTypes: {'l1': 'factory:Layout'},
        ),
        'p2': NativeComponentConfig(
          placements: {
            'body': ['l2'],
          },
          slotTypes: {'l2': 'factory:Layout'},
        ),
        // Code-defined page, absent from the catalog.
        'root': NativeComponentConfig(
          placements: {
            'body': ['global'],
          },
          slotTypes: {'global': 'factory:Card'},
        ),
      },
      pageCatalog: _catalog(['p1', 'p2']),
    );
    final removal = EditorPageGraph.removal(
      appearance: source,
      registry: _registry(),
      pageId: 'p1',
    );
    final result = removal.appearance;
    expect(identical(result.pageCatalog, source.pageCatalog), isTrue);
    expect(result.nativeComponents.keys, unorderedEquals(['p2', 'root']));
    expect(result.layouts.keys, unorderedEquals(['l2', 'contA']));
    expect(
      result.styles.keys,
      unorderedEquals(['background', 'shared', 'global', 'a1']),
    );
    expect(removal.removed, {
      const EditorConfigRef.nativeComponent('p1'),
      const EditorConfigRef.layout('l1'),
      const EditorConfigRef.style('own'),
    });
    expect(removal.preserved, {
      const EditorConfigRef.style('shared'),
      const EditorConfigRef.style('global'),
    });
    expect(removal.limitations.single, contains('« A »'));
    expect(
      EditorPageGraph.remove(
        appearance: source,
        registry: _registry(),
        pageId: 'p1',
      ).styles.keys,
      result.styles.keys,
    );
  });

  test('removing the original keeps its duplicate intact', () {
    final copied = EditorPageGraph.duplicate(
      appearance: _sample(),
      registry: _registry(),
      sourcePageId: 'p1',
      targetPageId: 'p2',
    );
    final removed = EditorPageGraph.remove(
      appearance: copied,
      registry: _registry(),
      pageId: 'p1',
    );
    final bar = copied.nativeComponents['p2']!.slotsOf('appBar').single;
    expect(removed.nativeComponents.keys, unorderedEquals(['root', 'p2', bar]));
    for (final id in ['lay1', 'nested', 'txt1', 'cont1']) {
      expect(removed.layouts.containsKey(id), isFalse);
      expect(removed.valueComponents.containsKey(id), isFalse);
      expect(removed.styles.containsKey(id), isFalse);
    }
    expect(removed.layouts.keys, contains('contA'));
    expect(removed.styles.keys, contains('background'));
    expect(removed.valueComponents.length, 5);
    expect(removed.layouts.length, 3);
  });

  group('removeInstance', () {
    Appearance unplaced(Appearance appearance) => appearance.copyWith(
      nativeComponents: {
        ...appearance.nativeComponents,
        'p1': appearance.nativeComponents['p1']!.withoutSlot('lay1'),
      },
    );

    test('recursively deletes the subtree of an unplaced container', () {
      final registry = _registry();
      final removed = EditorPageGraph.removeInstance(
        appearance: unplaced(_sample()),
        registry: registry,
        instanceId: 'lay1',
        type: 'factory:Layout',
        containerKind: EditorConfigKind.nativeComponent,
      );
      expect(removed.layouts.keys, unorderedEquals(['contA']));
      expect(removed.styles.keys, unorderedEquals(['background']));
      expect(
        removed.valueComponents.keys,
        unorderedEquals(['txt1', 'txtHidden']),
      );
      expect(
        removed.nativeComponents.keys,
        containsAll(['root', 'p1', 'bar1']),
      );
    });

    test('keeps everything while the instance is still placed', () {
      final appearance = _sample();
      expect(
        EditorPageGraph.removeInstance(
          appearance: appearance,
          registry: _registry(),
          instanceId: 'lay1',
          type: 'factory:Layout',
          containerKind: EditorConfigKind.nativeComponent,
        ),
        same(appearance),
      );
    });

    test('keeps descendants shared with a remaining container', () {
      final sample = unplaced(_sample());
      final appearance = sample.copyWith(
        layouts: {
          ...sample.layouts,
          'contA': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['nested'],
            },
            slotTypes: {'nested': 'registry:Layout'},
          ),
        },
      );
      final removed = EditorPageGraph.removeInstance(
        appearance: appearance,
        registry: _registry(),
        instanceId: 'lay1',
        type: 'factory:Layout',
        containerKind: EditorConfigKind.nativeComponent,
      );
      expect(removed.layouts.keys, unorderedEquals(['contA', 'nested']));
      expect(removed.valueComponents.keys, contains('txt3'));
      expect(removed.valueComponents.keys, isNot(contains('txt2')));
    });
  });
}
