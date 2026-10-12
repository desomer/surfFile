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

  testWidgets('nested container menu only exposes the nearest slot actions', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SuperPage(
            child: RegisteredSuperLayout(
              id: 'body-layout',
              label: 'Body layout',
              config: SuperLayoutConfig(),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router, registry: registry));
    await tester.pumpAndSettle();
    final layout = registry.layoutController('body-layout');
    layout.value = layout.value.withSlotMoved(
      'container-instance',
      SuperLayoutZone.center,
      type: 'registry:NewContainer',
    );
    await tester.pumpAndSettle();
    final container = find.byWidgetPredicate(
      (widget) => widget is SuperContainer && widget.label == 'New Container',
    );
    StyleEditScope.controllerOf(tester.element(container))!.value = true;
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('style-edit-banner-drag')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(container) + const Offset(100, 100),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final menuRow = find.byKey(const ValueKey('style-menu-New Container'));
    expect(menuRow, findsOneWidget);
    for (final icon in [Icons.straighten, Icons.delete_outline]) {
      expect(
        find.descendant(of: menuRow, matching: find.byIcon(icon)),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('style-menu-size-Taille préférée : body')),
      findsNothing,
    );
    for (final action in ['size', 'remove']) {
      expect(
        tester
            .widget<IconButton>(
              find.byKey(
                ValueKey('style-menu-$action-Taille préférée : NewContainer'),
              ),
            )
            .onPressed,
        isNotNull,
      );
    }
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'registered additions size the unique instance and undo atomically',
    (tester) async {
      final registry = Registry()..bootstrap();
      final additions = <SlotAddition>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => SuperPage(
              onSlotAdded: (addition) {
                additions.add(addition);
                return SuperLayout.defaultSlotAddition(addition);
              },
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(SuperApp(router: router, registry: registry));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SuperPage));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 450),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 28));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('super-layout-add-north')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('NewContainer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NewContainer'));
      await tester.pumpAndSettle();
      final controller = registry.layoutController('root');
      final id = controller.value.placementsOf(SuperLayoutZone.north).single;
      expect(id, isNot('registry:NewContainer'));
      expect(additions.single.slotId, id);
      expect(controller.value.slotTypeOf(id), 'registry:NewContainer');
      expect(
        controller.value.slotSizeConstraints[id]?.preferredHeight,
        const SlotDimension(20, SlotSizeUnit.percent),
      );
      expect(
        controller.value.slotSizeConstraints[id]?.percentBasis,
        SlotPercentBasis.layout,
      );
      final restored = SuperLayoutConfig.fromJson(controller.value.toJson());
      expect(
        restored.slotSizeConstraints[id],
        controller.value.slotSizeConstraints[id],
      );
      final history = EditorHistoryScope.controllerOf(context)!;
      history.undo();
      await tester.pumpAndSettle();
      expect(controller.value.placementsOf(SuperLayoutZone.north), isEmpty);
      expect(controller.value.slotSizeConstraints.containsKey(id), isFalse);
      history.redo();
      await tester.pumpAndSettle();
      expect(controller.value.placementsOf(SuperLayoutZone.north), [id]);
      expect(
        controller.value.slotSizeConstraints[id]?.preferredHeight,
        const SlotDimension(20, SlotSizeUnit.percent),
      );
      expect(additions, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nested app bar menu edits and removes its parent slot', (
    tester,
  ) async {
    final registry = Registry()..bootstrap();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SuperPage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router, registry: registry));
    await tester.pumpAndSettle();
    final page = registry.layoutController('root');
    page.value = page.value.withSlotMoved(
      'bar-instance',
      SuperLayoutZone.north,
      type: 'registry:SuperAppBar',
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SuperAppBar));
    final editMode = StyleEditScope.controllerOf(context)!;
    editMode.value = true;
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('style-edit-banner-drag')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    final barLayout = find.byWidgetPredicate(
      (widget) => widget is SuperLayout && widget.label == 'Super app bar',
    );
    Offset position() => tester
        .renderObject<RenderBox>(barLayout)
        .localToGlobal(const Offset(100, 48));
    await tester.tapAt(position());
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: barLayout,
        matching: find.byKey(const ValueKey('super-layout-add-center')),
      ),
      findsOneWidget,
    );

    await tester.tapAt(position(), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final sizeAction = find.byKey(
      const ValueKey('style-menu-size-Taille préférée : SuperAppBar'),
    );
    final removeAction = find.byKey(
      const ValueKey('style-menu-remove-Taille préférée : SuperAppBar'),
    );
    expect(sizeAction, findsOneWidget);
    expect(removeAction, findsOneWidget);
    await tester.tap(sizeAction);
    await tester.pumpAndSettle();
    expect(find.text('Tailles du slot : SuperAppBar'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('slot-preferred-height')),
      '80',
    );
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(
      page.value.slotSizeConstraints['bar-instance']?.preferredHeight,
      const SlotDimension(80, SlotSizeUnit.pixels),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('slot-bar-instance'))).height,
      80,
    );

    await tester.tapAt(position(), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(removeAction);
    await tester.pumpAndSettle();
    expect(find.byType(SuperAppBar), findsNothing);
    expect(page.value.placementsOf(SuperLayoutZone.north), isEmpty);
    final history = EditorHistoryScope.controllerOf(
      tester.element(find.byType(SuperPage)),
    )!;
    history.undo();
    await tester.pumpAndSettle();
    expect(find.byType(SuperAppBar), findsOneWidget);
    editMode.value = false;
    await tester.pumpAndSettle();
    await tester.tapAt(position(), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(sizeAction, findsNothing);
    expect(removeAction, findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'title and action slots expose size and removal in the bar menu',
    (tester) async {
      final registry = Registry();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => SuperPage(
              appBar: SuperAppBar(
                title: const Text('Editable title'),
                action: IconButton(
                  key: const ValueKey('editable-action'),
                  onPressed: () {},
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(SuperApp(router: router, registry: registry));
      await tester.pumpAndSettle();
      StyleEditScope.controllerOf(tester.element(find.byType(SuperAppBar)))!
              .value =
          true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      for (final slot in ['title', 'action']) {
        final content = slot == 'title'
            ? find.text('Editable title')
            : find.byKey(const ValueKey('editable-action'));
        await tester.tapAt(
          tester.getTopLeft(content) + const Offset(4, 4),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('style-menu-size-Taille préférée : $slot')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(ValueKey('style-menu-remove-Taille préférée : $slot')),
        );
        await tester.pumpAndSettle();
        expect(content, findsNothing);
        expect(
          registry
              .layoutController('root-appBar')
              .value
              .placementsOf(
                slot == 'title' ? SuperLayoutZone.center : SuperLayoutZone.east,
              ),
          isEmpty,
        );
      }
      expect(find.byType(SuperAppBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
