import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets('lookup without a SuperApp is optional or reports an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          expect(SuperApp.maybeOf(context), isNull);
          expect(() => SuperApp.of(context), throwsA(isA<FlutterError>()));
          return const SizedBox();
        },
      ),
    );
  });

  testWidgets('factory picker keeps metadata and uses layout ancestor scope', (
    tester,
  ) async {
    final registry = Registry();
    registry.registerComponent(
      'scoped',
      RegisteredComponent(
        label: 'Scoped component',
        slotId: 'historical-slot',
        sizing: SlotSizing.intrinsic,
        isAvailable: (context) =>
            context.dependOnInheritedWidgetOfExactType<_TestComponentScope>() !=
            null,
        builder: (context) {
          expect(
            context.dependOnInheritedWidgetOfExactType<_TestComponentScope>(),
            isNotNull,
          );
          return const Text('Factory content');
        },
      ),
    );
    registry.registerComponent(
      'unavailable',
      RegisteredComponent(
        label: 'Unavailable component',
        isAvailable: (_) => false,
        builder: (_) => const Text('Not built'),
      ),
    );
    final changes = <SuperLayoutConfig>[];
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    await tester.pumpWidget(
      SuperApp(
        registry: registry,
        home: _TestComponentScope(
          child: StyleEditScope(
            controller: editMode,
            child: SuperLayout(onChanged: changes.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-layout-add-center')));
    await tester.pumpAndSettle();
    expect(find.text('Scoped component'), findsOneWidget);
    expect(find.text('Unavailable component'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('super-layout-add-slot-historical-slot')),
    );
    await tester.pumpAndSettle();
    final instance = changes.single.placementsOf(SuperLayoutZone.center).single;
    expect(changes.single.slotTypeOf(instance), 'historical-slot');
    expect(instance, isNot('historical-slot'));
    expect(find.text('Factory content'), findsOneWidget);
    final stack = tester.widget<SlotStack>(find.byType(SlotStack));
    expect(stack.slots.single.sizing, SlotSizing.intrinsic);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout and container descendants subscribe to the SuperApp', (
    tester,
  ) async {
    final observed = <SuperApp>[];
    final home = SuperContainer(
      child: SuperLayout(
        config: const SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: ['lookup'],
          },
        ),
        slots: [
          BuilderSlot(
            id: 'lookup',
            label: 'Lookup',
            builder: (context) {
              final app = SuperApp.of(context);
              observed.add(app);
              return Text(app.title);
            },
          ),
        ],
      ),
    );
    final store = AppearanceStore();
    final first = SuperApp(title: 'First', home: home, appearanceStore: store);
    await tester.pumpWidget(first);
    await tester.pumpAndSettle();
    expect(observed.last, same(first));
    expect(find.text('First'), findsOneWidget);

    final second = SuperApp(
      title: 'Second',
      home: home,
      appearanceStore: store,
    );
    await tester.pumpWidget(second);
    await tester.pumpAndSettle();
    expect(observed.last, same(second));
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slot lookup only creates and checks requested components', (
    tester,
  ) async {
    final registry = Registry();
    var requestedCreations = 0;
    var unusedCreations = 0;
    var unusedAvailabilityChecks = 0;
    var unusedWidgetBuilds = 0;
    registry.registerComponent(
      'requested',
      _CountingComponent(
        label: 'Requested',
        slotId: 'historical-slot',
        sizing: SlotSizing.intrinsic,
        onCreate: () => requestedCreations++,
        builder: (_) => const Text('Requested content'),
      ),
    );
    registry.registerComponent(
      'unused',
      _CountingComponent(
        label: 'Unused',
        onCreate: () => unusedCreations++,
        isAvailable: (_) {
          unusedAvailabilityChecks++;
          return true;
        },
        builder: (_) => const Text('Unused content'),
      ),
    );
    registry.registry['unused-widget'] = ComponentBuilderDynamic(
      dynamicBuilder: (_) {
        unusedWidgetBuilds++;
        return const Text('Unused registry content');
      },
    );
    await tester.pumpWidget(
      SuperApp(
        registry: registry,
        home: const SuperLayout(
          config: SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['historical-slot', 'unknown'],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Requested content'), findsOneWidget);
    expect(requestedCreations, greaterThan(0));
    expect(unusedCreations, 0);
    expect(unusedAvailabilityChecks, 0);
    expect(unusedWidgetBuilds, 0);
    final stack = tester.widget<SlotStack>(find.byType(SlotStack));
    expect(stack.slots.single.sizing, SlotSizing.intrinsic);
    final state = tester.state<SuperLayoutState>(find.byType(SuperLayout));
    expect(state.searchSlot('unknown'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slot lookup preserves duplicate precedence and visibility', (
    tester,
  ) async {
    final registry = Registry();
    registry.registerComponent(
      'first',
      RegisteredComponent(
        label: 'First',
        slotId: 'duplicate',
        builder: (_) => const SizedBox(),
      ),
    );
    registry.registerComponent(
      'last',
      RegisteredComponent(
        label: 'Last',
        slotId: 'duplicate',
        builder: (_) => const SizedBox(),
      ),
    );
    registry.registerComponent(
      'unavailable',
      RegisteredComponent(
        label: 'Unavailable',
        slotId: 'duplicate',
        isAvailable: (_) => false,
        builder: (_) => const SizedBox(),
      ),
    );
    final hidden = BuilderSlot(
      id: 'hidden',
      label: 'Hidden',
      visible: false,
      builder: (_) => const Text('Hidden content'),
    );
    await tester.pumpWidget(
      SuperApp(
        registry: registry,
        home: SuperLayout(
          slots: [hidden],
          config: const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['hidden', 'duplicate'],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<SuperLayoutState>(find.byType(SuperLayout));
    expect(state.searchSlot('duplicate')?.label, 'Last');
    expect(state.searchSlot('hidden'), same(hidden));
    expect(find.text('Hidden content'), findsNothing);
    expect(
      tester.widget<SlotStack>(find.byType(SlotStack)).slots.single.id,
      'duplicate',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog routes can access the enclosing SuperApp', (
    tester,
  ) async {
    SuperApp? observed;
    final app = SuperApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) {
              observed = SuperApp.of(context);
              return const AlertDialog(content: Text('Dialog'));
            },
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(observed, same(app));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty zone picker adds independent registry instances', (
    tester,
  ) async {
    final registry = Registry();
    registry.registerFactory('clock', const Text('Registry content'));
    final changes = <SuperLayoutConfig>[];
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    await tester.pumpWidget(
      SuperApp(
        registry: registry,
        home: StyleEditScope(
          controller: editMode,
          child: SuperLayout(
            onChanged: changes.add,
            slots: [
              BuilderSlot(
                id: 'regular',
                label: 'Regular slot',
                builder: (_) => const Text('Regular content'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-layout-add-ne')));
    await tester.pumpAndSettle();
    expect(find.text('Regular slot'), findsOneWidget);
    expect(find.text('Registre : clock'), findsOneWidget);
    expect(find.text('Aucun slot visible disponible.'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('super-layout-add-slot-registry:clock')),
    );
    await tester.pumpAndSettle();
    final firstId = changes.single.placementsOf(SuperLayoutZone.ne).single;
    expect(changes.single.slotTypeOf(firstId), 'registry:clock');
    expect(find.text('Registry content'), findsOneWidget);
    expect(find.byKey(const ValueKey('super-layout-name-ne')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('super-layout-add-south')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('super-layout-add-slot-registry:clock')),
    );
    await tester.pumpAndSettle();
    final secondId = changes.last.placementsOf(SuperLayoutZone.south).single;
    expect(secondId, isNot(firstId));
    expect(changes.last.slotTypeOf(secondId), 'registry:clock');
    expect(changes.last.placementsOf(SuperLayoutZone.ne), [firstId]);
    expect(find.text('Registry content'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    final restored = SuperLayoutConfig.fromJson(changes.last.toJson());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      SuperApp(
        registry: registry,
        home: SuperLayout(config: restored),
      ),
    );
    await tester.pumpAndSettle();
    expect(restored.placementsOf(SuperLayoutZone.ne), [firstId]);
    expect(restored.placementsOf(SuperLayoutZone.south), [secondId]);
    expect(find.text('Registry content'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('default containers have independent persistent styles', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    final config = const SuperLayoutConfig()
        .withSlotMoved(
          'container-first',
          SuperLayoutZone.center,
          type: 'registry:New%20Container',
        )
        .withSlotMoved(
          'container-second',
          SuperLayoutZone.center,
          type: 'registry:New%20Container',
        );
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    await tester.pumpWidget(
      SuperApp(
        registry: registry,
        home: StyleEditScope(
          controller: editMode,
          child: SuperLayout(config: config),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final containers = find.byWidgetPredicate(
      (widget) => widget is SuperContainer && widget.label == 'New Container',
    );
    expect(containers, findsNWidgets(2));
    const style = ContainerStyle(radius: 23, padding: 12);
    tester.widgetList<SuperContainer>(containers).first.onStyleChanged!(style);
    await tester.pumpAndSettle();
    expect(registry.styleController('container-first').value, style);
    expect(
      registry.styleController('container-second').value,
      const ContainerStyle(),
    );
    expect(tester.widgetList<SuperContainer>(containers).first.style, style);

    await tester.tap(find.byKey(const ValueKey('super-layout-add-north')));
    await tester.pumpAndSettle();
    expect(find.text('Registre : New Container'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    final loaded = await AppearanceStore().load();
    expect(loaded.style('container-first').toJson(), style.toJson());
    final restarted = Registry()..bootstrap();
    await tester.pumpWidget(
      SuperApp(
        registry: restarted,
        home: SuperLayout(config: SuperLayoutConfig.fromJson(config.toJson())),
      ),
    );
    await tester.pumpAndSettle();
    expect(containers, findsNWidgets(2));
    expect(
      tester.widgetList<SuperContainer>(containers).first.style.toJson(),
      style.toJson(),
    );
    expect(
      restarted.styleController('container-first').value.toJson(),
      style.toJson(),
    );
    expect(
      restarted.styleController('container-second').value,
      const ContainerStyle(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested layouts reuse placement IDs after reconstruction', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    final config = const SuperLayoutConfig()
        .withSlotMoved(
          'nested-first',
          SuperLayoutZone.center,
          type: 'registry:New%20Layout',
        )
        .withSlotMoved(
          'nested-second',
          SuperLayoutZone.center,
          type: 'registry:New%20Layout',
        );
    final firstController = registry.layoutController('nested-first');
    firstController.value = const SuperLayoutConfig(
      swaps: {SuperLayoutZone.west},
    );
    await tester.pumpWidget(
      SuperApp(
        registry: registry,
        home: SuperLayout(config: config),
      ),
    );
    await tester.pumpAndSettle();
    expect(registry.superLayoutConfigById.keys.toSet(), {
      'nested-first',
      'nested-second',
    });
    expect(
      tester
          .widgetList<SuperLayout>(find.byType(SuperLayout))
          .map((w) => w.config),
      contains(firstController.value),
    );
    await tester.pumpWidget(
      SuperApp(
        registry: registry,
        home: SuperLayout(config: SuperLayoutConfig.fromJson(config.toJson())),
      ),
    );
    await tester.pumpAndSettle();
    expect(registry.superLayoutConfigById.keys.toSet(), {
      'nested-first',
      'nested-second',
    });
    expect(registry.layoutController('nested-first'), same(firstController));
    expect(tester.takeException(), isNull);
    final snapshot = Appearance(
      layouts: {
        'parent': config,
        'nested-first': firstController.value,
        'nested-second': registry.layoutController('nested-second').value,
      },
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await AppearanceStore().save(snapshot);
    final loaded = await AppearanceStore().load();
    final restartedRegistry = Registry()..bootstrap();
    await tester.pumpWidget(
      SuperApp(
        registry: restartedRegistry,
        home: SuperLayout(config: loaded.layout('parent')),
      ),
    );
    await tester.pumpAndSettle();
    expect(restartedRegistry.superLayoutConfigById.keys.toSet(), {
      'nested-first',
      'nested-second',
    });
    expect(
      restartedRegistry.layoutController('nested-first').value,
      snapshot.layout('nested-first'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('registry slots do not collide with supplied slot IDs', (
    tester,
  ) async {
    final registry = Registry();
    registry.registerFactory('clock', const Text('Registry content'));
    registry.registerFactory(
      'registry:clock',
      const Text('Other registry content'),
    );
    final changes = <SuperLayoutConfig>[];
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    await tester.pumpWidget(
      SuperApp(
        registry: registry,
        home: StyleEditScope(
          controller: editMode,
          child: SuperLayout(
            onChanged: changes.add,
            config: const SuperLayoutConfig(
              swaps: {SuperLayoutZone.north},
              placements: {
                SuperLayoutZone.center: ['registry:clock'],
              },
            ),
            slots: [
              BuilderSlot(
                id: 'registry:clock',
                label: 'Supplied slot',
                builder: (_) => const Text('Supplied content'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-layout-add-north')));
    await tester.pumpAndSettle();
    expect(find.text('Supplied slot'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('super-layout-add-slot-registry:registry%3Aclock'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey('super-layout-add-slot-registry:registry:clock'),
      ),
    );
    await tester.pumpAndSettle();
    final instance = changes.single.placementsOf(SuperLayoutZone.south).single;
    expect(changes.single.slotTypeOf(instance), 'registry:registry:clock');
    expect(changes.single.placementsOf(SuperLayoutZone.center), [
      'registry:clock',
    ]);
    expect(find.text('Registry content'), findsOneWidget);
    expect(find.text('Supplied content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestComponentScope extends InheritedWidget {
  const _TestComponentScope({required super.child});

  @override
  bool updateShouldNotify(_TestComponentScope oldWidget) => false;
}

class _CountingComponent extends RegisteredComponent {
  const _CountingComponent({
    required super.label,
    required super.builder,
    required this.onCreate,
    super.slotId,
    super.sizing,
    super.isAvailable,
  });

  final VoidCallback onCreate;

  @override
  BuilderSlot createSlot(String id, {bool visible = true}) {
    onCreate();
    return super.createSlot(id, visible: visible);
  }
}
