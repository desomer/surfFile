import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('planInsertion', () {
    const column = InsertionHost(axis: Axis.vertical);

    test('inserts along the stack axis', () {
      final plan = planInsertion(
        column,
        InsertDirection.down,
        InsertMode.beside,
      );
      expect(plan, isA<DirectInsertion>());
      expect((plan! as DirectInsertion).axis, isNull);
      expect(plan.newFirst, isFalse);
      expect(
        planInsertion(column, InsertDirection.up, InsertMode.beside)!.newFirst,
        isTrue,
      );
    });

    test('pushing places the new component at the target index', () {
      expect(
        planInsertion(column, InsertDirection.down, InsertMode.push)!.newFirst,
        isTrue,
      );
      expect(
        planInsertion(column, InsertDirection.up, InsertMode.push)!.newFirst,
        isFalse,
      );
    });

    test('switches the axis of a stack holding only the target', () {
      final plan = planInsertion(
        const InsertionHost(axis: Axis.vertical, axisMutable: true),
        InsertDirection.right,
        InsertMode.beside,
      );
      expect(plan, isA<DirectInsertion>());
      expect((plan! as DirectInsertion).axis, Axis.horizontal);
    });

    test('wraps across a stack with siblings, a single host or a grid', () {
      for (final host in const [
        InsertionHost(axis: Axis.vertical),
        InsertionHost(axis: Axis.horizontal, single: true),
        InsertionHost(axis: Axis.horizontal, stacked: false),
      ]) {
        final plan = planInsertion(
          host,
          InsertDirection.down,
          InsertMode.beside,
        );
        if (host.stacked && !host.single) {
          expect(plan, isA<DirectInsertion>());
          continue;
        }
        expect(plan, isA<WrapInsertion>());
        expect((plan! as WrapInsertion).axis, Axis.vertical);
      }
      expect(
        planInsertion(column, InsertDirection.left, InsertMode.beside),
        isA<WrapInsertion>(),
      );
    });

    test('is impossible when the host refuses a wrapper', () {
      expect(
        planInsertion(
          const InsertionHost(axis: Axis.vertical, canWrap: false),
          InsertDirection.right,
          InsertMode.beside,
        ),
        isNull,
      );
    });
  });

  const channels = [
    MethodChannel('com.alexmercerind/flutter_acrylic'),
    WindowTransparency.channel,
  ];
  const hostKey = ValueKey('contextual-host');
  const dimensions = SlotSizeConstraints(
    preferredWidth: SlotDimension(240, SlotSizeUnit.pixels),
    preferredHeight: SlotDimension(140, SlotSizeUnit.pixels),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });
  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  /// Mounts a root layout, native component or Card holding `source`.
  Future<ValueNotifier<Appearance>> mount(
    WidgetTester tester, {
    String owner = 'layout',
    SuperLayoutConfig? layout,
    Map<String, SuperLayoutConfig> innerLayouts = const {},
    ComponentTagFilter filter = const ComponentTagFilter(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final registry = Registry()..bootstrap();
    final root =
        layout ??
        const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['source'],
          },
          slotTypes: {'source': 'factory:Value'},
          slotLabels: {'source': 'My child'},
          slotSizeConstraints: {'source': dimensions},
        );
    final native = NativeComponentConfig(
      placements: {
        owner == 'surface' ? 'child' : 'body': ['source'],
      },
      slotTypes: {'source': 'factory:Value'},
      slotLabels: {'source': 'My child'},
      slotSizeConstraints: {'source': dimensions},
    );
    final layoutController = registry.layoutController('root', fallback: root);
    final nativeController = registry.nativeComponentController(
      'root',
      fallback: native,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: SizedBox(
                key: hostKey,
                width: 900,
                height: 700,
                child: switch (owner) {
                  'surface' => const EditableSurface(id: 'root', label: 'Root'),
                  'native' => ValueListenableBuilder<NativeComponentConfig>(
                    valueListenable: nativeController,
                    builder: (_, config, _) => NativeComponentEditor(
                      label: 'Root',
                      keyPrefix: 'contextual-native',
                      settingsTitle: 'Native settings',
                      editSurface: true,
                      registry: registry,
                      config: config,
                      onChanged: (value) => nativeController.value = value,
                      regions: [
                        NativeRegion(
                          'body',
                          'Body',
                          required: true,
                          tagFilter: filter,
                        ),
                        const NativeRegion(
                          'header',
                          'Header',
                          tagFilter: ComponentTagFilter(include: {'appBar'}),
                        ),
                      ],
                      slots: const [],
                      builder: (_, editor) => editor.region('body'),
                    ),
                  ),
                  _ => ValueListenableBuilder<SuperLayoutConfig>(
                    valueListenable: layoutController,
                    builder: (_, config, _) => SuperLayout(
                      label: 'Root',
                      config: config,
                      onChanged: (value) => layoutController.value = value,
                    ),
                  ),
                },
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router, registry: registry));
    await tester.pumpAndSettle();
    final context = tester.element(find.byKey(hostKey));
    final appearance = AppearanceScope.controllerOf(context)!;
    appearance.value = appearance.value.copyWith(
      layouts: owner == 'layout' ? {'root': root, ...innerLayouts} : const {},
      components: {
        if (owner != 'layout') 'root': native,
        for (final id in ['source', 'other'])
          id: SuperValueConfig(initialText: 'Text $id'),
      },
    );
    await tester.pumpAndSettle();
    StyleEditScope.controllerOf(context)!.value = true;
    await tester.pumpAndSettle();
    EditorHistoryScope.controllerOf(context)!.clear();
    return appearance;
  }

  Finder valueOf(String id) => find.byWidgetPredicate(
    (widget) => widget is SuperValue && widget.id == id,
  );

  Future<void> openInsertWizard(
    WidgetTester tester, {
    String id = 'source',
  }) async {
    await tester.tap(valueOf(id), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-menu-insert')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('contextual-add-wizard')), findsOneWidget);
  }

  Future<void> addVia(
    WidgetTester tester,
    String placement, {
    String component = 'factory:Value',
  }) async {
    final card = find.byKey(ValueKey('contextual-add-card-$component'));
    if (card.evaluate().isNotEmpty) {
      await tester.tap(card);
      await tester.pumpAndSettle();
    }
    final next = find.byKey(const ValueKey('contextual-add-next'));
    for (var step = 0; step < 6; step++) {
      final chip = find.byKey(ValueKey('contextual-add-placement-$placement'));
      if (chip.evaluate().isNotEmpty) {
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
      await tester.tap(next);
      await tester.pumpAndSettle();
      if (find
          .byKey(const ValueKey('contextual-add-wizard'))
          .evaluate()
          .isEmpty) {
        return;
      }
    }
    fail('Wizard did not close');
  }

  EditorHistoryController historyOf(WidgetTester tester) =>
      EditorHistoryScope.controllerOf(tester.element(find.byKey(hostKey)))!;

  testWidgets('« Composant… » and « Comportement… » are in the first context menu entry', (tester) async {
    await mount(tester);
    await tester.tap(valueOf('source'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final items = find.byWidgetPredicate((widget) => widget is PopupMenuItem);
    expect(items, findsAtLeastNWidgets(2));
    expect(
      tester.widget<PopupMenuItem<Object?>>(items.first).key,
      const ValueKey('style-menu-insert'),
    );
    expect(find.text('Composant…'), findsOneWidget);
    expect(find.text('Comportement…'), findsOneWidget);
  });

  testWidgets('switches a single-slot zone to a row without wrapper', (
    tester,
  ) async {
    final appearance = await mount(tester);
    final before = appearance.value;
    await openInsertWizard(tester);
    await addVia(tester, '0-beside-right');
    final root = appearance.value.layouts['root']!;
    final ids = root.placementsOf(SuperLayoutZone.center);
    expect(ids, hasLength(2));
    expect(ids.first, 'source');
    expect(root.slotTypeOf(ids.last), 'factory:Value');
    expect(root.axisOf(SuperLayoutZone.center), Axis.horizontal);
    expect(root.slotSizeConstraints['source'], same(dimensions));
    expect(find.byType(SuperValue), findsNWidgets(2));
    final history = historyOf(tester);
    history.undo();
    await tester.pumpAndSettle();
    expect(appearance.value, same(before));
    expect(history.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  const twoSlots = SuperLayoutConfig(
    placements: {
      SuperLayoutZone.center: ['source', 'other'],
    },
    slotTypes: {'source': 'factory:Value', 'other': 'factory:Value'},
    slotLabels: {'source': 'My child'},
    slotSizeConstraints: {'source': dimensions},
  );

  testWidgets('inserts along the zone axis', (tester) async {
    final appearance = await mount(tester, layout: twoSlots);
    await openInsertWizard(tester);
    await addVia(tester, '0-beside-down');
    final root = appearance.value.layouts['root']!;
    final ids = root.placementsOf(SuperLayoutZone.center);
    expect(ids, hasLength(3));
    expect(ids.first, 'source');
    expect(ids.last, 'other');
    expect(root.axisOf(SuperLayoutZone.center), Axis.vertical);
  });

  testWidgets('pushing gives the target size to the new component', (
    tester,
  ) async {
    final appearance = await mount(tester, layout: twoSlots);
    await openInsertWizard(tester);
    await addVia(tester, '0-push-down');
    final root = appearance.value.layouts['root']!;
    final ids = root.placementsOf(SuperLayoutZone.center);
    expect(ids, hasLength(3));
    expect(ids[1], 'source');
    expect(root.slotSizeConstraints[ids.first], same(dimensions));
    expect(root.slotSizeConstraints.containsKey('source'), isFalse);
  });

  testWidgets('wraps the target across a stack with siblings', (tester) async {
    final appearance = await mount(tester, layout: twoSlots);
    await openInsertWizard(tester);
    await addVia(tester, '0-beside-left');
    final after = appearance.value;
    final root = after.layouts['root']!;
    final ids = root.placementsOf(SuperLayoutZone.center);
    expect(ids, hasLength(2));
    expect(ids.last, 'other');
    final wrapper = ids.first;
    expect(root.slotTypeOf(wrapper), 'registry:Layout');
    expect(root.slotSizeConstraints[wrapper], same(dimensions));
    final inner = after.layouts[wrapper]!;
    final innerIds = inner.placementsOf(SuperLayoutZone.center);
    expect(innerIds, hasLength(2));
    expect(innerIds.last, 'source');
    expect(inner.slotTypeOf(innerIds.first), 'factory:Value');
    expect(inner.axisOf(SuperLayoutZone.center), Axis.horizontal);
    expect(find.byType(SuperValue), findsNWidgets(3));
    final history = historyOf(tester);
    history.undo();
    await tester.pumpAndSettle();
    expect(history.canUndo, isFalse);
    expect(
      appearance.value.layouts['root']!.placementsOf(SuperLayoutZone.center),
      ['source', 'other'],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers the parent level and adds next to it', (tester) async {
    final appearance = await mount(
      tester,
      layout: const SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['inner'],
        },
        slotTypes: {'inner': 'registry:Layout'},
        slotLabels: {'inner': 'Inner'},
      ),
      innerLayouts: const {
        'inner': SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['source'],
          },
          slotTypes: {'source': 'factory:Value'},
          slotLabels: {'source': 'My child'},
        ),
      },
    );
    await openInsertWizard(tester);
    await tester.tap(
      find.byKey(const ValueKey('contextual-add-card-factory:Value')),
    );
    await tester.pumpAndSettle();
    for (var step = 0; step < 2; step++) {
      await tester.tap(find.byKey(const ValueKey('contextual-add-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('My child'), findsWidgets);
    expect(find.text('Dans Inner'), findsOneWidget);
    expect(find.text('Inner'), findsWidgets);
    expect(find.text('Dans Root'), findsOneWidget);
    await addVia(tester, '1-beside-down');
    final after = appearance.value;
    final ids = after.layouts['root']!.placementsOf(SuperLayoutZone.center);
    expect(ids, hasLength(2));
    expect(ids.first, 'inner');
    expect(after.layouts['inner']!.placementsOf(SuperLayoutZone.center), [
      'source',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds directly next to the element', (tester) async {
    final appearance = await mount(tester);
    await openInsertWizard(tester);
    await tester.tap(
      find.byKey(const ValueKey('contextual-add-slot-factory:Value')),
    );
    await tester.pumpAndSettle();
    final root = appearance.value.layouts['root']!;
    expect(root.placementsOf(SuperLayoutZone.center).first, 'source');
    expect(root.placementsOf(SuperLayoutZone.center), hasLength(2));
    expect(root.axisOf(SuperLayoutZone.center), Axis.horizontal);
  });

  testWidgets('wraps a grid item', (tester) async {
    final appearance = await mount(
      tester,
      layout: const SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['source'],
        },
        slotTypes: {'source': 'factory:Value'},
        slotLabels: {'source': 'My child'},
        positioning: SuperLayoutPositioning.grid,
        grid: GridLayoutConfig(
          compact: false,
          items: {'source': GridSlotPosition(x: 2, y: 1, width: 5, height: 4)},
        ),
      ),
    );
    await openInsertWizard(tester);
    await addVia(tester, '0-beside-right');
    final after = appearance.value;
    final root = after.layouts['root']!;
    final wrapper = root.placedSlotIds.single;
    expect(root.slotTypeOf(wrapper), 'registry:Layout');
    expect(root.grid!.items, {
      wrapper: const GridSlotPosition(x: 2, y: 1, width: 5, height: 4),
    });
    final inner = after.layouts[wrapper]!;
    expect(inner.placementsOf(SuperLayoutZone.center).first, 'source');
    expect(inner.axisOf(SuperLayoutZone.center), Axis.horizontal);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wraps the single child of a Card', (tester) async {
    final appearance = await mount(tester, owner: 'surface');
    await openInsertWizard(tester);
    await addVia(tester, '0-beside-down');
    final after = appearance.value;
    final wrapper = after.nativeComponent('root').slotsOf('child').single;
    expect(
      after.nativeComponent('root').slotTypeOf(wrapper),
      'registry:Layout',
    );
    final inner = after.layouts[wrapper]!;
    expect(inner.placementsOf(SuperLayoutZone.center).first, 'source');
    expect(inner.axisOf(SuperLayoutZone.center), Axis.vertical);
    expect(find.byType(SuperValue), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a native region keeps its axis and may refuse wrappers', (
    tester,
  ) async {
    final appearance = await mount(
      tester,
      owner: 'native',
      filter: const ComponentTagFilter(exclude: {'layout'}),
    );
    await openInsertWizard(tester);
    await tester.tap(
      find.byKey(const ValueKey('contextual-add-card-factory:Value')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('contextual-add-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('contextual-add-next')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('contextual-add-placement-0-beside-down')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('contextual-add-placement-0-beside-right')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('contextual-add-cancel')));
    await tester.pumpAndSettle();
    await openInsertWizard(tester);
    await addVia(tester, '0-beside-up');
    final ids = appearance.value.nativeComponent('root').slotsOf('body');
    expect(ids, hasLength(2));
    expect(ids.last, 'source');
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds at the end of a zone of the containing layout', (
    tester,
  ) async {
    final appearance = await mount(tester, layout: twoSlots);
    await openInsertWizard(tester);
    await addVia(tester, 'z0-center');
    final root = appearance.value.layouts['root']!;
    final ids = root.placementsOf(SuperLayoutZone.center);
    expect(ids, hasLength(3));
    expect(ids.take(2), ['source', 'other']);
    expect(root.slotTypeOf(ids.last), 'factory:Value');
    final history = historyOf(tester);
    history.undo();
    await tester.pumpAndSettle();
    expect(history.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds in a region of the containing native component', (
    tester,
  ) async {
    final appearance = await mount(tester, owner: 'native');
    await openInsertWizard(tester);
    await addVia(tester, 'z0-body');
    final ids = appearance.value.nativeComponent('root').slotsOf('body');
    expect(ids, hasLength(2));
    expect(ids.first, 'source');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty zone offers « Ajouter… » with its zones', (
    tester,
  ) async {
    final appearance = await mount(
      tester,
      layout: const SuperLayoutConfig(north: true),
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(hostKey)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-menu-insert')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('contextual-add-slot-factory:Value')),
    );
    await tester.pumpAndSettle();
    final root = appearance.value.layouts['root']!;
    expect(root.placementsOf(SuperLayoutZone.center), hasLength(1));
    expect(root.placementsOf(SuperLayoutZone.north), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hidden side of the layout is enabled by the addition', (
    tester,
  ) async {
    final appearance = await mount(tester);
    expect(appearance.value.layouts['root']!.north, isFalse);
    await openInsertWizard(tester);
    await addVia(tester, 'z0-north');
    final root = appearance.value.layouts['root']!;
    expect(root.north, isTrue);
    expect(root.placementsOf(SuperLayoutZone.north), hasLength(1));
    expect(root.placementsOf(SuperLayoutZone.center), ['source']);
    expect(find.byType(SuperValue), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a disabled native region receives an application bar', (
    tester,
  ) async {
    final appearance = await mount(tester, owner: 'native');
    await openInsertWizard(tester);
    await addVia(tester, 'z0-header', component: 'factory:ApplicationBar');
    final native = appearance.value.nativeComponent('root');
    expect(native.slotsOf('header'), hasLength(1));
    expect(native.isEnabled('header'), isTrue);
    expect(
      native.slotTypeOf(native.slotsOf('header').single),
      'factory:ApplicationBar',
    );
    expect(native.slotsOf('body'), ['source']);
    expect(tester.takeException(), isNull);
  });

  test('placement tags restrict a component to dedicated zones', () {
    const free = ComponentTagFilter();
    const bar = ComponentTagFilter(include: {'appBar'});
    expect(free.admits({'appBar'}, {'appBar'}), isFalse);
    expect(bar.admits({'appBar'}, {'appBar'}), isTrue);
    expect(free.admits({'text'}, const {}), isTrue);
    expect(bar.admits({'text'}, const {}), isFalse);
    expect(ComponentTagFilter.fits(const {}, const {}), isTrue);
  });

  testWidgets('the zone wizard only offers compatible zones', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ComponentAddWizard(
            title: 'Ajouter',
            keyPrefix: 'tags',
            initialTargetId: 'body',
            candidates: [
              ComponentAddCandidate(id: 'text', label: 'Texte', tags: {'text'}),
              ComponentAddCandidate(
                id: 'bar',
                label: 'Barre',
                tags: {'appBar'},
                placementTags: {'appBar'},
              ),
              ComponentAddCandidate(
                id: 'nav',
                label: 'Navigation',
                tags: {'bottomNavigationBar'},
                placementTags: {'bottomNavigationBar'},
              ),
            ],
            targets: [
              ComponentAddTarget(id: 'body', label: 'Corps'),
              ComponentAddTarget(
                id: 'appBar',
                label: 'AppBar',
                zoneTags: {'appBar'},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('tags-add-card-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('tags-add-card-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('tags-add-card-nav')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tags-add-card-bar')));
    await tester.pumpAndSettle();
    for (var step = 0; step < 2; step++) {
      await tester.tap(find.byKey(const ValueKey('tags-add-next')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('tags-add-target')));
    await tester.pumpAndSettle();
    expect(find.text('AppBar'), findsWidgets);
    expect(find.text('Corps'), findsNothing);
  });

  testWidgets('a dedicated component is only offered in its zones', (
    tester,
  ) async {
    await mount(tester);
    await openInsertWizard(tester);
    expect(
      find.byKey(const ValueKey('contextual-add-card-factory:ApplicationBar')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('contextual-add-card-factory:Value')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('contextual-add-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('an application bar is only offered in the AppBar region', (
    tester,
  ) async {
    await mount(tester, owner: 'native');
    await openInsertWizard(tester);
    await tester.tap(
      find.byKey(const ValueKey('contextual-add-card-factory:ApplicationBar')),
    );
    await tester.pumpAndSettle();
    final next = find.byKey(const ValueKey('contextual-add-next'));
    for (
      var step = 0;
      step < 3 &&
          find
              .byKey(const ValueKey('contextual-add-placement'))
              .evaluate()
              .isEmpty;
      step++
    ) {
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    final chips = find.byWidgetPredicate(
      (widget) =>
          widget is ChoiceChip &&
          (widget.key as ValueKey<String>?)?.value.startsWith(
                'contextual-add-placement-',
              ) ==
              true,
    );
    expect(
      [
        for (final element in chips.evaluate())
          (element.widget.key! as ValueKey<String>).value,
      ],
      ['contextual-add-placement-z0-header'],
    );
  });

  testWidgets('nested layouts with the same name keep separate groups', (
    tester,
  ) async {
    await mount(
      tester,
      layout: const SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['inner'],
        },
        slotTypes: {'inner': 'registry:Layout'},
        slotLabels: {'inner': 'Root'},
      ),
      innerLayouts: const {
        'inner': SuperLayoutConfig(
          label: 'Root',
          placements: {
            SuperLayoutZone.center: ['source'],
          },
          slotTypes: {'source': 'factory:Value'},
          slotLabels: {'source': 'My child'},
        ),
      },
    );
    await openInsertWizard(tester);
    await tester.tap(
      find.byKey(const ValueKey('contextual-add-card-factory:Value')),
    );
    await tester.pumpAndSettle();
    for (var step = 0; step < 2; step++) {
      await tester.tap(find.byKey(const ValueKey('contextual-add-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Dans Root'), findsOneWidget);
    expect(find.text('Dans Root (parent)'), findsOneWidget);
    final keys = [
      for (final element
          in find
              .byWidgetPredicate((widget) => widget is ChoiceChip)
              .evaluate())
        (element.widget.key! as ValueKey<String>).value.substring(
          'contextual-add-placement-'.length,
        ),
    ];
    expect(keys.where((key) => key == 'z0-center'), hasLength(1));
    expect(keys.indexOf('z0-center'), lessThan(keys.indexOf('1-beside-right')));
    expect(keys.indexOf('1-beside-right'), lessThan(keys.indexOf('z1-center')));
  });
}
