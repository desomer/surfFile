import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bootstrap defines menu icons for all standard components', () {
    final registry = Registry()..bootstrap();
    expect(
      registry.registry.map(
        (key, component) => MapEntry(key, component.menuIcon),
      ),
      {
        'Text': Icons.text_fields,
        'AppBar': Icons.web_asset,
        'BottomNavigationBar': Icons.space_dashboard_outlined,
        'Card': Icons.crop_square,
        'IterableContent': Icons.loop,
        'ListView': Icons.view_list,
        'Layout': Icons.dashboard_outlined,
      },
    );
  });

  test(
    'bootstrap exposes only the renamed component types without aliases',
    () {
      final registry = Registry()..bootstrap();
      expect(
        registry.registry.keys,
        unorderedEquals([
          'Card',
          'IterableContent',
          'Layout',
          'Text',
          'ListView',
          'AppBar',
          'BottomNavigationBar',
        ]),
      );
      for (final oldType in [
        'SuperContainer',
        'NewContainer',
        'SuperLayout',
        'NewLayout',
        'SuperText',
        'SuperListView',
        'SuperAppBar',
        'SuperBottomNavigationBar',
      ]) {
        expect(registry.registry.containsKey(oldType), isFalse);
      }
    },
  );

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

  for (final native in [false, true]) {
    for (final kind in ['component', 'factory', 'dynamic']) {
      for (final icon in [null, Icons.star_outline]) {
        testWidgets(
          '${native ? 'native' : 'layout'} $kind uses '
          '${icon == null ? 'default' : 'registered'} menu icon without leaking',
          (tester) async {
            const content = EditorSlot(
              label: 'Component editor',
              child: EditorSlot(
                label: 'Nested editor',
                child: SizedBox(width: 100, height: 60, child: Text('Target')),
              ),
            );
            final registry = Registry();
            switch (kind) {
              case 'component':
                registry.registerComponent(
                  'custom',
                  RegisteredComponent(
                    label: 'Custom',
                    menuIcon: icon,
                    builder: (_) => content,
                  ),
                );
              case 'factory':
                registry.registerFactory('custom', content, menuIcon: icon);
              case 'dynamic':
                registry.registry['custom'] = ComponentBuilderDynamic(
                  menuIcon: icon,
                  dynamicBuilder: (_) => content,
                );
            }
            final Widget page;
            if (native) {
              page = NativeComponentEditor(
                label: 'Native parent',
                registry: registry,
                config: NativeComponentConfig(
                  placements: {
                    'body': ['instance'],
                  },
                  slotTypes: {'instance': 'registry:custom'},
                  slotLabels: {'instance': 'Renamed'},
                ),
                onChanged: (_) {},
                regions: const [NativeRegion('body', 'Body')],
                slots: const [],
                keyPrefix: 'menu-icon',
                settingsTitle: 'Settings',
                builder: (_, state) => state.slotsFor('body').single,
              );
            } else {
              page = SuperLayout(
                label: 'Layout parent',
                config: const SuperLayoutConfig(
                  north: false,
                  south: false,
                  east: false,
                  west: false,
                  placements: {
                    SuperLayoutZone.center: ['instance'],
                  },
                  slotTypes: {'instance': 'registry:custom'},
                  slotLabels: {'instance': 'Renamed'},
                ),
              );
            }
            final router = GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => Scaffold(body: page),
                ),
              ],
            );
            addTearDown(router.dispose);
            await tester.pumpWidget(
              SuperApp(router: router, registry: registry),
            );
            await tester.pumpAndSettle();
            StyleEditScope.controllerOf(tester.element(find.text('Target')))!
                    .value =
                true;
            await tester.pumpAndSettle();
            await tester.tap(
              find.text('Target'),
              buttons: kSecondaryMouseButton,
            );
            await tester.pumpAndSettle();

            Finder row(String label) =>
                find.byKey(ValueKey('style-menu-$label'));
            expect(
              find.descendant(
                of: row('Renamed'),
                matching: find.byIcon(icon ?? Icons.subdirectory_arrow_left),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: row('Nested editor'),
                matching: find.byIcon(Icons.brush_outlined),
              ),
              findsOneWidget,
            );
            if (!native) {
              expect(
                find.descendant(
                  of: row('Layout parent'),
                  matching: find.byIcon(Icons.subdirectory_arrow_left),
                ),
                findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
