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
    expect(find.text('Configurer la page…'), findsNothing);
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
    'registered Scaffold additions use unique instances and undo atomically',
    (tester) async {
      final registry = Registry()..bootstrap();
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SuperPage()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(SuperApp(router: router, registry: registry));
      await tester.pumpAndSettle();
      final page = registry.scaffoldPageController('root');
      page.value = page.value.withRegionEnabled(
        ScaffoldPageRegion.appBar,
        true,
      );
      final context = tester.element(find.byType(SuperPage));
      StyleEditScope.controllerOf(context)!.value = true;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scaffold-page-add-appBar')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('scaffold-page-add-slot-factory:NewContainer'),
        ),
      );
      await tester.pumpAndSettle();
      final controller = registry.scaffoldPageController('root');
      final id = controller.value.slotsOf(ScaffoldPageRegion.appBar).single;
      expect(id, isNot('factory:NewContainer'));
      expect(controller.value.slotTypeOf(id), 'factory:NewContainer');
      final history = EditorHistoryScope.controllerOf(context)!;
      history.undo();
      await tester.pumpAndSettle();
      expect(controller.value.slotsOf(ScaffoldPageRegion.appBar), isEmpty);
      history.redo();
      await tester.pumpAndSettle();
      expect(controller.value.slotsOf(ScaffoldPageRegion.appBar), [id]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native Scaffold region slot can be removed and undone', (
    tester,
  ) async {
    final registry = Registry()
      ..registerComponent(
        'removable',
        const RegisteredComponent(label: 'Removable', builder: _removable),
      );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SuperPage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router, registry: registry));
    await tester.pumpAndSettle();
    final page = registry.scaffoldPageController('root');
    page.value = page.value.withSlotAdded(
      'removable',
      ScaffoldPageRegion.body,
      type: 'component:removable',
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SuperPage));
    final editMode = StyleEditScope.controllerOf(context)!;
    editMode.value = true;
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(find.text('Removable content')) + const Offset(2, 2),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final removeAction = find.byKey(
      const ValueKey('style-menu-remove-Taille préférée : Removable'),
    );
    expect(removeAction, findsOneWidget);
    await tester.tap(removeAction);
    await tester.pumpAndSettle();
    expect(find.text('Removable content'), findsNothing);
    expect(page.value.slotsOf(ScaffoldPageRegion.body), ['scaffold:body']);
    final history = EditorHistoryScope.controllerOf(context)!;
    history.undo();
    await tester.pumpAndSettle();
    expect(find.text('Removable content'), findsOneWidget);
    expect(page.value.slotsOf(ScaffoldPageRegion.body), [
      'scaffold:body',
      'removable',
    ]);
    editMode.value = false;
    await tester.pumpAndSettle();
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
              .nativeComponentController('root-appBar')
              .value
              .slotsOf(slot == 'title' ? 'title' : 'actions'),
          isEmpty,
        );
      }

      expect(find.byType(SuperAppBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _removable(BuildContext context) => const Text('Removable content');
