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

  Rect screenRect(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  Future<ValueNotifier<bool>> pumpPage(
    WidgetTester tester, {
    Size size = const Size(320, 240),
    bool twoSlots = false,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => SuperPage(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: SuperLayout(
                  label: 'Zoom target',
                  config: SuperLayoutConfig(
                    north: false,
                    south: false,
                    west: false,
                    east: false,
                    placements: {
                      SuperLayoutZone.center: [
                        'target',
                        if (twoSlots) 'second',
                      ],
                    },
                    slotPreferredSizes: {
                      if (twoSlots) 'target': const Size(120, 80),
                    },
                  ),
                  slots: [
                    const BuilderSlot(
                      id: 'target',
                      label: 'Target',
                      builder: _target,
                    ),
                    if (twoSlots)
                      const BuilderSlot(
                        id: 'second',
                        label: 'Second',
                        builder: _second,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router));
    await tester.pumpAndSettle();
    final mode = StyleEditScope.controllerOf(
      tester.element(find.byType(SuperPage)),
    )!;
    mode.value = true;
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('style-edit-banner-drag')),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    return mode;
  }

  testWidgets(
    'selection centers and fits content while editor overlays keep their scale',
    (tester) async {
      final mode = await pumpPage(tester);
      final target = find.byKey(const ValueKey('zoom-target-content'));
      final original = screenRect(tester, target);
      final banner = find.byKey(const ValueKey('style-edit-banner-drag'));
      final bannerSize = screenRect(tester, banner).size;
      await tester.tapAt(original.topLeft + const Offset(100, 180));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final label = find.byKey(const ValueKey('slot-label-select-target'));
      final labelSize = screenRect(tester, label).size;
      await tester.pump(const Duration(milliseconds: 150));
      final during = screenRect(tester, target);
      expect(during.width, greaterThan(original.width));
      expect(during.width, lessThan(560));
      await tester.pumpAndSettle();
      final zoomed = screenRect(tester, target);
      expect(zoomed.width, closeTo(560, .01));
      expect(zoomed.height, closeTo(420, .01));
      expect(zoomed.center, const Offset(400, 300));
      expect(screenRect(tester, label).size, labelSize);
      expect(screenRect(tester, banner).size, bannerSize);

      // The label remains tappable at its screen position after the animation.
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.last, 'Target');
      final layoutPath = LayoutSelection.path.value.sublist(
        0,
        LayoutSelection.path.value.length - 2,
      );
      LayoutSelection.select(layoutPath);
      await tester.pumpAndSettle();
      LayoutSelection.toggle(layoutPath);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(screenRect(tester, target).width, lessThan(zoomed.width));
      await tester.pumpAndSettle();
      expect(screenRect(tester, target), original);

      await tester.tapAt(original.topLeft + const Offset(100, 180));
      await tester.pumpAndSettle();
      expect(screenRect(tester, target).width, closeTo(560, .01));
      mode.value = false;
      await tester.pumpAndSettle();
      expect(screenRect(tester, target), const Rect.fromLTWH(0, 0, 320, 240));
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('editor-zoom-transform')),
            )
            .transform,
        Matrix4.identity(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small targets are capped at three and menus stay unscaled', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(100, 80));
    final target = find.byKey(const ValueKey('zoom-target-content'));
    await tester.tapAt(screenRect(tester, target).center);
    await tester.pumpAndSettle();
    final rect = screenRect(tester, target);
    expect(rect.size, const Size(300, 240));
    expect(rect.center, const Offset(400, 300));
    await tester.tapAt(
      rect.bottomRight - const Offset(20, 20),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final button = find.byKey(
      const ValueKey('style-menu-size-Taille préférée : Target'),
    );
    expect(
      button,
      findsOneWidget,
      reason: find
          .byType(IconButton)
          .evaluate()
          .map((element) => element.widget.key)
          .toList()
          .toString(),
    );
    expect(screenRect(tester, button).size, tester.getSize(button));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Tailles du slot : Target'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'slot selection retargets zoom and viewport resize does not compound scale',
    (tester) async {
      await pumpPage(tester, twoSlots: true);
      final target = find.byKey(const ValueKey('zoom-target-content'));
      await tester.tapAt(
        screenRect(tester, target).topLeft + const Offset(100, 50),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-label-select-target')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.last, 'Target');
      expect(screenRect(tester, target).size, const Size(360, 240));
      expect(screenRect(tester, target).center, const Offset(400, 300));
      final handle = find.byKey(const ValueKey('slot-resize-target-se'));
      expect(screenRect(tester, handle).size, tester.getSize(handle));
      expect(
        (screenRect(tester, handle).bottomRight -
                screenRect(tester, target).bottomRight)
            .distance,
        lessThan(1),
      );
      await tester.tap(
        find.byKey(const ValueKey('slot-label-select-target')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('style-menu-size-Taille préférée : Target')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(790, 590));
      await tester.pumpAndSettle();

      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpAndSettle();
      expect(screenRect(tester, target).size, const Size(360, 240));
      expect(screenRect(tester, target).center, const Offset(500, 350));
      expect(
        (screenRect(tester, handle).bottomRight -
                screenRect(tester, target).bottomRight)
            .distance,
        lessThan(1),
      );

      final second = find.byKey(const ValueKey('zoom-second-content'));
      await tester.tap(find.byKey(const ValueKey('slot-label-select-second')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.last, 'Second');
      expect(screenRect(tester, second).center, const Offset(500, 350));
      expect(screenRect(tester, second).width, closeTo(700, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resizing a zoomed slot uses content coordinates, not screen pixels',
    (tester) async {
      await pumpPage(tester, twoSlots: true);
      final target = find.byKey(const ValueKey('zoom-target-content'));
      await tester.tapAt(
        screenRect(tester, target).topLeft + const Offset(100, 50),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-label-select-target')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('slot-resize-target-se')),
        const Offset(60, 30),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(target), const Size(140, 90));
      expect(screenRect(tester, target).size, const Size(420, 270));
      expect(screenRect(tester, target).center, const Offset(400, 300));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced-motion preferences frame selections without animation', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpPage(tester, size: const Size(100, 80));
    final target = find.byKey(const ValueKey('zoom-target-content'));
    await tester.tapAt(screenRect(tester, target).center);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(screenRect(tester, target).size, const Size(300, 240));
    expect(screenRect(tester, target).center, const Offset(400, 300));
    expect(tester.takeException(), isNull);
  });
}

Widget _target(BuildContext context) =>
    const ColoredBox(key: ValueKey('zoom-target-content'), color: Colors.blue);

Widget _second(BuildContext context) =>
    const ColoredBox(key: ValueKey('zoom-second-content'), color: Colors.green);
