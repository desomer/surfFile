import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

Widget _content(BuildContext context) => const SizedBox.expand();

void main() {
  test('include is any-match and exclude takes precedence', () {
    const unrestricted = ComponentTagFilter();
    const included = ComponentTagFilter(include: {'appBar', 'navigation'});
    const excluded = ComponentTagFilter(exclude: {'internal'});
    const combined = ComponentTagFilter(
      include: {'appBar', 'navigation'},
      exclude: {'internal'},
    );
    expect(unrestricted.accepts({}), isTrue);
    expect(unrestricted.accepts({'unknown'}), isTrue);
    expect(included.accepts({}), isFalse);
    expect(included.accepts({'content'}), isFalse);
    expect(included.accepts({'navigation', 'content'}), isTrue);
    expect(excluded.accepts({}), isTrue);
    expect(excluded.accepts({'content'}), isTrue);
    expect(excluded.accepts({'internal', 'content'}), isFalse);
    expect(combined.accepts({'navigation'}), isTrue);
    expect(combined.accepts({'appBar', 'internal'}), isFalse);
  });

  test('bootstrap and registration retain component tags', () {
    final registry = Registry()..bootstrap();
    expect(registry.registry['AppBar']!.tags, {'appBar'});
    expect(registry.registry['BottomNavigationBar']!.tags, {
      'bottomNavigationBar',
    });
    registry.registerFactory(
      'custom',
      const SizedBox(),
      tags: {'appBar', 'custom'},
    );
    expect(registry.registry['custom']!.tags, {'appBar', 'custom'});
    const component = RegisteredComponent(
      label: 'Custom',
      tags: {'navigation', 'custom'},
      builder: _content,
    );
    registry.registerComponent('registered', component);
    final slot = registry.component('registered').createSlot('instance');
    expect(slot.tags, component.tags);
    final wrapped = InstanceSlot(
      slot,
      label: 'Renamed',
      onRename: (_) {},
      onRestore: () {},
      overridden: true,
    );
    expect(wrapped.tags, component.tags);
    expect(
      const BuilderSlot(id: 'old', label: 'Old', builder: _content).tags,
      isEmpty,
    );
  });

  Future<void> pumpNative(
    WidgetTester tester, {
    required Registry registry,
    required ValueNotifier<NativeComponentConfig> config,
    List<SlotImplementation> slots = const [],
    NativeSlotAddedCallback? onSlotAdded,
    String renderedRegion = 'target',
    List<NativeRegion> regions = const [
      NativeRegion(
        'target',
        'Target',
        required: true,
        tagFilter: ComponentTagFilter(
          include: {'allowed'},
          exclude: {'blocked'},
        ),
      ),
      NativeRegion('free', 'Free', required: true),
    ],
  }) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StyleEditScope(
            controller: mode,
            child: ValueListenableBuilder<NativeComponentConfig>(
              valueListenable: config,
              builder: (context, value, _) => NativeComponentEditor(
                label: 'Native',
                keyPrefix: 'native-test',
                settingsTitle: 'Settings',
                config: value,
                onChanged: (value) => config.value = value,
                regions: regions,
                slots: slots,
                registry: registry,
                onSlotAdded: onSlotAdded,
                builder: (_, editor) => editor.region(renderedRegion),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openNative(WidgetTester tester, String region) async {
    final state = tester.state<NativeComponentEditorState>(
      find.byType(NativeComponentEditor),
    );
    unawaited(state.add(region));
    await tester.pumpAndSettle();
  }

  testWidgets('native catalog filters supplied, registered and factory slots', (
    tester,
  ) async {
    final registry = Registry()
      ..registerComponent(
        'yes',
        const RegisteredComponent(
          label: 'Yes',
          tags: {'allowed', 'other'},
          builder: _content,
        ),
      )
      ..registerComponent(
        'no',
        const RegisteredComponent(
          label: 'No',
          tags: {'allowed', 'blocked'},
          builder: _content,
        ),
      )
      ..registerFactory('plain', const SizedBox())
      ..registerFactory('tagged', const SizedBox(), tags: {'allowed'});
    final config = ValueNotifier(NativeComponentConfig());
    addTearDown(config.dispose);
    await pumpNative(
      tester,
      registry: registry,
      config: config,
      slots: const [
        BuilderSlot(
          id: 'provided',
          label: 'Provided',
          tags: {'allowed'},
          builder: _content,
        ),
        BuilderSlot(id: 'untagged', label: 'Untagged', builder: _content),
      ],
    );
    await openNative(tester, 'target');
    for (final type in ['provided', 'component:yes', 'factory:tagged']) {
      expect(
        find.byKey(ValueKey('native-test-add-slot-$type')),
        findsOneWidget,
      );
    }
    for (final type in ['untagged', 'component:no', 'factory:plain']) {
      expect(find.byKey(ValueKey('native-test-add-slot-$type')), findsNothing);
    }
    await tester.tap(
      find.byKey(const ValueKey('native-test-add-slot-component:yes')),
    );
    await tester.pumpAndSettle();
    final id = config.value.slotsOf('target').single;
    expect(config.value.slotTypeOf(id), 'component:yes');
    expect(
      tester
          .state<NativeComponentEditorState>(find.byType(NativeComponentEditor))
          .slotsFor('target')
          .single
          .tags,
      {'allowed', 'other'},
    );

    await openNative(tester, 'free');
    expect(
      find.byKey(const ValueKey('native-test-add-slot-factory:plain')),
      findsOneWidget,
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
  });

  testWidgets('native callback cannot replace with an incompatible type', (
    tester,
  ) async {
    final registry = Registry()
      ..registerFactory('yes', const SizedBox(), tags: {'allowed'})
      ..registerFactory('no', const SizedBox());
    final initial = NativeComponentConfig();
    final config = ValueNotifier(initial);
    addTearDown(config.dispose);
    await pumpNative(
      tester,
      registry: registry,
      config: config,
      onSlotAdded: (next, region, id, slot, siblings) =>
          next.withSlotAdded(id, region, type: 'factory:no'),
    );
    await openNative(tester, 'target');
    await tester.tap(
      find.byKey(const ValueKey('native-test-add-slot-factory:yes')),
    );
    await tester.pumpAndSettle();
    expect(config.value, same(initial));
    expect(
      find.text('Composant incompatible avec la zone Target.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('native legacy placements render and can be removed', (
    tester,
  ) async {
    final config = ValueNotifier(
      NativeComponentConfig(
        placements: {
          'target': ['old'],
        },
        slotTypes: {'old': 'registry:legacy'},
      ),
    );
    addTearDown(config.dispose);
    final registry = Registry()
      ..registerComponent(
        'legacy',
        const RegisteredComponent(label: 'Legacy', builder: _content),
      )
      ..registerFactory('yes', const SizedBox(), tags: {'allowed'});
    await pumpNative(tester, registry: registry, config: config);
    final editor = tester.state<NativeComponentEditorState>(
      find.byType(NativeComponentEditor),
    );
    expect(editor.slotsFor('target').single.id, 'old');
    await openNative(tester, 'target');
    await tester.tap(
      find.byKey(const ValueKey('native-test-add-slot-factory:yes')),
    );
    await tester.pumpAndSettle();
    expect(config.value.slotsOf('target'), hasLength(2));
    final nativeSlot = tester
        .widgetList<SlotStack>(find.byType(SlotStack))
        .where((stack) => stack.slots.any((slot) => slot.id == 'old'))
        .single;
    expect(nativeSlot.slots.first.tags, isEmpty);
    await nativeSlot.onRemoveSlot!(nativeSlot.slots.first);
    await tester.pumpAndSettle();
    expect(config.value.slotsOf('target'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('native moves enforce tags, capacity, ownership and ordering', (
    tester,
  ) async {
    final registry = Registry()
      ..registerFactory('yes', const SizedBox(), tags: {'allowed'})
      ..registerFactory('no', const SizedBox());
    final initial = NativeComponentConfig(
      placements: {
        'target': ['a', 'b'],
        'free': ['bad'],
        'single': ['occupied'],
      },
      slotTypes: {
        'a': 'factory:yes',
        'b': 'factory:yes',
        'bad': 'factory:no',
        'occupied': 'factory:yes',
      },
      slotPreferredSizes: {'a': const Size(50, 30)},
    );
    final config = ValueNotifier(initial);
    addTearDown(config.dispose);
    await pumpNative(
      tester,
      registry: registry,
      config: config,
      regions: const [
        NativeRegion(
          'target',
          'Target',
          required: true,
          tagFilter: ComponentTagFilter(include: {'allowed'}),
        ),
        NativeRegion('free', 'Free', required: true),
        NativeRegion('single', 'Single', single: true),
      ],
    );
    final editor = tester.state<NativeComponentEditorState>(
      find.byType(NativeComponentEditor),
    );
    final stack = tester.widget<SlotStack>(find.byType(SlotStack));
    final mover = stack.mover!;
    expect(mover.canMove!('bad'), isFalse);
    expect(mover.canMove!('a'), isTrue);
    final target = tester.widget<DragTarget<SlotDragData>>(
      find
          .descendant(
            of: find.byKey(const ValueKey('native-test-slot-drop-target')),
            matching: find.byType(DragTarget<SlotDragData>),
          )
          .first,
    );
    final hint = ValueNotifier<SlotDropHint?>(null);
    addTearDown(hint.dispose);
    for (final (owner, id) in [(editor, 'bad'), (Object(), 'a')]) {
      expect(
        target.onWillAcceptWithDetails!(
          DragTargetDetails(
            data: SlotDragData(id: id, owner: owner, hint: hint),
            offset: Offset.zero,
          ),
        ),
        isFalse,
      );
    }
    mover.onMove('bad');
    await tester.pumpAndSettle();
    expect(config.value, same(initial));
    mover.onMove('b', beforeId: 'a');
    await tester.pumpAndSettle();
    expect(config.value.slotsOf('target'), ['b', 'a']);
    expect(config.value.slotPreferredSizes, initial.slotPreferredSizes);
    final afterMove = config.value;
    tester
        .widget<SlotStack>(find.byType(SlotStack))
        .mover!
        .onMove('a', afterId: 'b');
    await tester.pumpAndSettle();
    expect(config.value, same(afterMove));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    await pumpNative(
      tester,
      registry: registry,
      config: config,
      renderedRegion: 'single',
      regions: const [
        NativeRegion('target', 'Target'),
        NativeRegion('free', 'Free'),
        NativeRegion('single', 'Single', single: true),
      ],
    );
    final singleMover = tester.widget<SlotStack>(find.byType(SlotStack)).mover!;
    expect(singleMover.canMove!('a'), isFalse);
    expect(singleMover.canMove!('occupied'), isTrue);
    singleMover.onMove('a');
    await tester.pumpAndSettle();
    expect(config.value, same(afterMove));
    expect(config.value.slotsOf('single'), ['occupied']);
    expect(tester.takeException(), isNull);
  });
}
