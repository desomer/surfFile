import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

  const targetKey = ValueKey('editable-container');
  Finder target() => find.byKey(targetKey);
  Registry registry() => Registry()
    ..bootstrap()
    ..registerComponent(
      'message',
      RegisteredComponent(
        label: 'Message',
        builder: (_) => const Text('Catalog child'),
        duplication: const ComponentDuplicationContract.stateless(),
      ),
    );

  Future<void> mount(
    WidgetTester tester,
    Registry registry, {
    Widget? child,
    bool editing = true,
    bool identified = true,
    bool fromCatalog = false,
    Future<void> Function()? onAdd,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 180,
                child: fromCatalog
                    ? KeyedSubtree(
                        key: targetKey,
                        child: registry.getWidget(
                          'NewContainer',
                          XuiBuildCtx(id: 'box'),
                        ),
                      )
                    : SuperContainer(
                        key: targetKey,
                        id: identified ? 'box' : null,
                        label: 'Box',
                        onAdd: onAdd,
                        child: child,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router, registry: registry));
    await tester.pumpAndSettle();
    StyleEditScope.controllerOf(tester.element(target()))!.value = editing;
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, [String label = 'Box']) async {
    await tester.tap(target(), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('style-menu-add-$label')));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String type) async {
    await tester.tap(
      find.byKey(ValueKey('super-container-box-add-slot-$type')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'catalog container adds one child with persistence and undo redo',
    (tester) async {
      final components = registry();
      await mount(tester, components, fromCatalog: true);
      final context = tester.element(target());
      final history = EditorHistoryScope.controllerOf(context)!;
      final appearance = AppearanceScope.controllerOf(context)!;
      history.clear();
      await open(tester, 'New Container');
      await choose(tester, 'factory:SuperText');
      expect(find.byType(SuperText), findsOneWidget);
      final config = components.nativeComponentController('box').value;
      final id = config.slotsOf('child').single;
      expect(config.slotTypeOf(id), 'factory:SuperText');
      expect(tester.widget<SuperText>(find.byType(SuperText)).id, id);
      expect(history.canUndo, isTrue);
      final store = AppearanceStore();
      await store.save(appearance.value);
      final saved = await store.load();
      expect(saved.nativeComponents['box']!.toJson(), config.toJson());
      final encoded = const AppearanceCodec().encode(saved);
      expect(
        const AppearanceCodec()
            .decode(encoded)
            .nativeComponents['box']!
            .toJson(),
        config.toJson(),
      );
      final exported = AppearanceTransfer.export(saved, {
        TransferGroup.layouts,
      });
      final imported = AppearanceTransfer.import(Appearance(), exported, {
        TransferGroup.layouts,
      });
      expect(imported.nativeComponents['box']!.toJson(), config.toJson());
      history.undo();
      await tester.pumpAndSettle();
      expect(find.byType(SuperText), findsNothing);
      expect(history.canUndo, isFalse);
      history.redo();
      await tester.pumpAndSettle();
      expect(tester.widget<SuperText>(find.byType(SuperText)).id, id);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final restored = registry();
      await mount(tester, restored, fromCatalog: true);
      expect(tester.widget<SuperText>(find.byType(SuperText)).id, id);
      expect(
        restored.nativeComponentController('box').value.toJson(),
        config.toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacement confirms, cancellation preserves child, removal restores through undo',
    (tester) async {
      final components = registry();
      await mount(tester, components, child: const Text('Initial child'));
      final history = EditorHistoryScope.controllerOf(
        tester.element(target()),
      )!;
      history.clear();
      await open(tester);
      expect(find.text('Remplacer le composant enfant ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text('Initial child'), findsOneWidget);
      expect(history.canUndo, isFalse);
      await open(tester);
      await tester.tap(find.text('Remplacer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text('Initial child'), findsOneWidget);
      expect(history.canUndo, isFalse);
      await open(tester);
      await tester.tap(find.text('Remplacer'));
      await tester.pumpAndSettle();
      await choose(tester, 'component:message');
      expect(find.text('Initial child'), findsNothing);
      expect(find.text('Catalog child'), findsOneWidget);
      expect(
        components.nativeComponentController('box').value.slotsOf('child'),
        hasLength(1),
      );
      history.undo();
      await tester.pumpAndSettle();
      expect(find.text('Initial child'), findsOneWidget);
      history.redo();
      await tester.pumpAndSettle();
      await tester.tap(target(), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('style-menu-remove-child-Box')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Catalog child'), findsNothing);
      expect(find.text('Initial child'), findsNothing);
      history.undo();
      await tester.pumpAndSettle();
      expect(find.text('Catalog child'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('containers nest with independent children', (tester) async {
    final components = registry();
    await mount(tester, components);
    await open(tester);
    await choose(tester, 'factory:NewContainer');
    final parent = components.nativeComponentController('box').value;
    final nestedId = parent.slotsOf('child').single;
    await open(tester, 'New Container');
    await tester.tap(
      find.byKey(
        ValueKey('super-container-$nestedId-add-slot-component:message'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Catalog child'), findsOneWidget);
    expect(
      components.nativeComponentController('box').value.toJson(),
      parent.toJson(),
    );
    expect(
      components.nativeComponentController(nestedId).value.slotsOf('child'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'explicit add callback takes priority and edit mode gates actions',
    (tester) async {
      var calls = 0;
      final components = registry();
      await mount(
        tester,
        components,
        onAdd: () async {
          calls++;
        },
      );
      await open(tester);
      expect(calls, 1);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(
        components.nativeComponentController('box').value.slotsOf('child'),
        isEmpty,
      );
      StyleEditScope.controllerOf(tester.element(target()))!.value = false;
      await tester.pumpAndSettle();
      await tester.tap(target(), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-menu-add-Box')), findsNothing);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'no ID preserves application ownership and editing disabled hides menu',
    (tester) async {
      await mount(
        tester,
        registry(),
        identified: false,
        child: const Text('Owned child'),
      );
      await tester.tap(target(), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-menu-add-Box')), findsNothing);
      expect(find.text('Owned child'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      StyleEditScope.controllerOf(tester.element(target()))!.value = false;
      await tester.pumpAndSettle();
      await tester.tap(target(), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<Object>), findsNothing);
      expect(find.text('Owned child'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
