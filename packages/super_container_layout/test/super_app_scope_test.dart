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
            context.dependOnInheritedWidgetOfExactType<_TestComponentScope>() != null,
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
    await tester.tap(find.byKey(const ValueKey('super-layout-add-slot-historical-slot')));
    await tester.pumpAndSettle();
    expect(changes.single.placementsOf(SuperLayoutZone.center), ['historical-slot']);
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

  testWidgets('empty zone picker adds and moves application registry slots', (
    tester,
  ) async {
    final registry = Registry();
    registry.registry['clock'] = const Text('Registry content');
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
    expect(changes.single.placementsOf(SuperLayoutZone.ne), ['registry:clock']);
    expect(find.text('Registry content'), findsOneWidget);
    expect(find.byKey(const ValueKey('super-layout-name-ne')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('super-layout-add-south')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('super-layout-add-slot-registry:clock')),
    );
    await tester.pumpAndSettle();
    expect(changes.last.placementsOf(SuperLayoutZone.ne), isEmpty);
    expect(changes.last.placementsOf(SuperLayoutZone.south), [
      'registry:clock',
    ]);
    expect(find.text('Registry content'), findsOneWidget);
    expect(find.byKey(const ValueKey('super-layout-add-ne')), findsOneWidget);
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
    expect(find.text('Registry content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registry slots do not collide with supplied slot IDs', (
    tester,
  ) async {
    final registry = Registry();
    registry.registry['clock'] = const Text('Registry content');
    registry.registry['registry:clock'] = const Text('Other registry content');
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
    expect(changes.single.placementsOf(SuperLayoutZone.south), [
      'registry:registry:clock',
    ]);
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
