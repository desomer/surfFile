import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/dialogs/editor_dialog.dart';
import 'package:super_container_layout/widgets/editing/overlay/editor_zoom.dart';

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
            maxAutoZoomExtent: 1000,
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

  Future<void> selectTargetZone(WidgetTester tester) async {
    LayoutSelection.select(const ['Page', 'Corps', 'Zoom target', 'Centre']);
    await tester.pump();
  }

  testWidgets(
    'wheel zoom requires Ctrl, centers on the mouse pointer and restores full page at one',
    (tester) async {
      final mode = await pumpPage(tester);
      final target = find.byKey(const ValueKey('zoom-target-content'));
      final original = screenRect(tester, target);
      const pointer = Offset(220, 140);
      Future<void> wheel(
        double delta, {
        Offset position = pointer,
        bool ctrl = true,
      }) async {
        if (ctrl) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        }
        await tester.sendEventToBinding(
          PointerScrollEvent(position: position, scrollDelta: Offset(0, delta)),
        );
        if (ctrl) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
      }

      // Without Ctrl, wheel events do not zoom even in edit mode.
      await wheel(-60, ctrl: false);
      await tester.pumpAndSettle();
      expect(screenRect(tester, target), original);

      await selectTargetZone(tester);
      await tester.pumpAndSettle();
      final automatic = screenRect(tester, target);
      final banner = find.byKey(const ValueKey('style-edit-banner-drag'));
      final bannerSize = screenRect(tester, banner).size;
      final label = find.byKey(const ValueKey('slot-label-select-target'));
      final labelSize = screenRect(tester, label).size;

      // Without Ctrl, wheel still does not zoom an active selection.
      await wheel(-60, ctrl: false);
      await tester.pumpAndSettle();
      expect(screenRect(tester, target), automatic);

      // With Ctrl held, wheel zooms centered on the mouse pointer.
      final relativeBefore = (pointer - automatic.topLeft).dx / automatic.width;
      final relativeBeforeY =
          (pointer - automatic.topLeft).dy / automatic.height;
      await wheel(-60);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(screenRect(tester, target).width, greaterThan(automatic.width));
      await tester.pumpAndSettle();
      final afterZoomIn = screenRect(tester, target);
      expect(afterZoomIn.width, closeTo(automatic.width * math.exp(.15), .01));
      // The point under the mouse pointer remains anchored at `pointer`.
      expect(
        afterZoomIn.left + relativeBefore * afterZoomIn.width,
        closeTo(pointer.dx, .05),
      );
      expect(
        afterZoomIn.top + relativeBeforeY * afterZoomIn.height,
        closeTo(pointer.dy, .05),
      );
      expect(screenRect(tester, banner).size, bannerSize);
      expect(screenRect(tester, label).size, labelSize);

      await wheel(60);
      await tester.pumpAndSettle();
      expect(
        screenRect(tester, target),
        within(distance: .05, from: automatic),
      );

      await wheel(-2000);
      await tester.pumpAndSettle();
      final maxed = screenRect(tester, target);
      expect(maxed.width, closeTo(320 * 3, .01));
      expect(
        maxed.left + relativeBefore * maxed.width,
        closeTo(pointer.dx, .05),
      );
      expect(
        maxed.top + relativeBeforeY * maxed.height,
        closeTo(pointer.dy, .05),
      );

      await wheel(2000);
      await tester.pumpAndSettle();
      expect(screenRect(tester, target), original);
      final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('editor-zoom-transform')),
      );
      expect(transform.transform, Matrix4.identity());
      await wheel(2000);
      await tester.pumpAndSettle();
      expect(screenRect(tester, target), original);
      LayoutSelection.focus.value = LayoutFocus(tester.element(target));
      await tester.pumpAndSettle();
      expect(screenRect(tester, target).width, closeTo(automatic.width, .01));
      mode.value = false;
      await tester.pumpAndSettle();
      await wheel(-60);
      await tester.pumpAndSettle();
      expect(screenRect(tester, target), const Rect.fromLTWH(0, 0, 320, 240));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wheel over an editor overlay zooms without scaling the overlay',
    (tester) async {
      await pumpPage(tester, twoSlots: true);
      final target = find.byKey(const ValueKey('zoom-target-content'));
      await selectTargetZone(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-label-select-target')));
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('slot-resize-target-se'));
      final handleSize = screenRect(tester, handle).size;
      final before = screenRect(tester, target);
      final east = find.byKey(const ValueKey('slot-resize-target-e'));
      expect(screenRect(tester, east).size, const Size(32, 32));
      expect(
        screenRect(tester, east).center.dy,
        closeTo(before.center.dy, .01),
      );
      expect(screenRect(tester, east).right, closeTo(before.right, .01));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: screenRect(tester, handle).center,
          scrollDelta: const Offset(0, 60),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        screenRect(tester, target).width,
        closeTo(before.width * math.exp(-.15), .01),
      );
      expect(screenRect(tester, handle).size, handleSize);
      final label = find.byKey(const ValueKey('slot-label-select-target'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: screenRect(tester, label).center,
          scrollDelta: const Offset(0, 30),
        ),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: screenRect(tester, label).center,
          scrollDelta: const Offset(0, 30),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        screenRect(tester, target).width,
        closeTo(before.width * math.exp(-.3), .01),
      );
      expect(
        screenRect(tester, label).width,
        closeTo(tester.getSize(label).width, .01),
      );
      expect(
        screenRect(tester, label).height,
        closeTo(tester.getSize(label).height, .01),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scrollable content keeps priority over wheel zoom', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    final scroll = ScrollController();
    final targetKey = GlobalKey();
    addTearDown(mode.dispose);
    addTearDown(scroll.dispose);
    addTearDown(() => LayoutSelection.focus.value = null);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: EditorZoom(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: targetKey,
                width: 320,
                height: 240,
                child: ListView(
                  controller: scroll,
                  children: const [SizedBox(height: 1600)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    LayoutSelection.focus.value = LayoutFocus(targetKey.currentContext!);
    await tester.pumpAndSettle();
    final before = screenRect(tester, find.byKey(targetKey));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: before.center,
        scrollDelta: const Offset(0, 60),
      ),
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(screenRect(tester, find.byKey(targetKey)), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selection centers and fits content while editor overlays keep their scale',
    (tester) async {
      final mode = await pumpPage(tester);
      final target = find.byKey(const ValueKey('zoom-target-content'));
      final original = screenRect(tester, target);
      final banner = find.byKey(const ValueKey('style-edit-banner-drag'));
      final bannerSize = screenRect(tester, banner).size;
      await selectTargetZone(tester);
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

      await selectTargetZone(tester);
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
    await selectTargetZone(tester);
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
      const ValueKey('style-menu-size-Taille et marge préférées : Target'),
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
    final banner = find.byKey(const ValueKey('style-edit-banner'));
    final bannerBefore = screenRect(tester, banner);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Taille et marge préférées : Target'), findsOneWidget);
    expect(
      screenRect(tester, target).overlaps(
        screenRect(tester, find.byKey(const ValueKey('editor-dialog-panel'))),
      ),
      isFalse,
    );
    expect(
      screenRect(tester, banner).overlaps(
        screenRect(tester, find.byKey(const ValueKey('editor-dialog-panel'))),
      ),
      isFalse,
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(screenRect(tester, target), rect);
    expect(screenRect(tester, banner), bannerBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'slot selection retargets zoom and viewport resize does not compound scale',
    (tester) async {
      await pumpPage(tester, twoSlots: true);
      final target = find.byKey(const ValueKey('zoom-target-content'));
      await selectTargetZone(tester);
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
        find.byKey(
          const ValueKey('style-menu-size-Taille et marge préférées : Target'),
        ),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(790, 590));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.last, 'Target');

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
      LayoutSelection.select(const [
        'Page',
        'Corps',
        'Zoom target',
        'Centre',
        'Second',
      ]);
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
      await selectTargetZone(tester);
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
    await selectTargetZone(tester);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(screenRect(tester, target).size, const Size(300, 240));
    expect(screenRect(tester, target).center, const Offset(400, 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'floating zoom toolbar appears only in edit mode, drags in bottom-right and controls zoom slider',
    (tester) async {
      final mode = await pumpPage(tester);
      const toolbarKey = ValueKey('editor-zoom-toolbar');
      const dragKey = ValueKey('editor-zoom-toolbar-drag');
      const sliderKey = ValueKey('editor-zoom-slider');
      const percentageKey = ValueKey('editor-zoom-percentage');
      final target = find.byKey(const ValueKey('zoom-target-content'));

      expect(find.byKey(toolbarKey), findsOneWidget);
      expect(find.byKey(dragKey), findsOneWidget);
      expect(find.byKey(sliderKey), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      final initialToolbar = tester.getRect(find.byKey(toolbarKey));
      expect(initialToolbar.right, 800 - 16);
      expect(initialToolbar.bottom, 600 - 12);

      // Drag the floating zoom toolbar and verify it stays bounded in viewport.
      Future<void> moveToolbar(Offset delta) async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(dragKey)),
        );
        await gesture.moveBy(const Offset(-24, 0));
        await tester.pump();
        await gesture.moveBy(delta);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await moveToolbar(const Offset(-100, -80));
      expect(
        tester.getRect(find.byKey(toolbarKey)).left,
        initialToolbar.left - 100,
      );
      expect(
        tester.getRect(find.byKey(toolbarKey)).top,
        initialToolbar.top - 80,
      );

      // Clamp at viewport edges and reverse immediately.
      await moveToolbar(const Offset(2000, 2000));
      expect(
        tester.getRect(find.byKey(toolbarKey)).bottomRight,
        const Offset(800, 600),
      );

      // Adjust zoom using the slider.
      final slider = tester.widget<Slider>(find.byKey(sliderKey));
      slider.onChanged!(2.0);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(percentageKey)).data, '200%');
      expect(screenRect(tester, target).width, closeTo(320 * 2, .01));
      // The floating toolbar itself stays unscaled.
      expect(tester.getRect(find.byKey(toolbarKey)).size, initialToolbar.size);

      // Reset to 100% via slider.
      tester.widget<Slider>(find.byKey(sliderKey)).onChanged!(1.0);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(percentageKey)).data, '100%');
      expect(screenRect(tester, target), const Rect.fromLTWH(0, 0, 320, 240));

      // Exiting edit mode hides the floating zoom toolbar.
      mode.value = false;
      await tester.pumpAndSettle();
      expect(find.byKey(toolbarKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'right click drag pans the zoom and right click + wheel zooms centered on pointer',
    (tester) async {
      await pumpPage(tester);
      final target = find.byKey(const ValueKey('zoom-target-content'));
      final original = screenRect(tester, target);

      // 1. Right click drag pans the view.
      final panGesture = await tester.startGesture(
        const Offset(400, 300),
        buttons: kSecondaryMouseButton,
      );
      await panGesture.moveBy(const Offset(50, 40));
      await tester.pumpAndSettle();
      await panGesture.up();
      await tester.pumpAndSettle();

      final panned = screenRect(tester, target);
      expect(panned.left, original.left + 50);
      expect(panned.top, original.top + 40);

      // Context menu should NOT be opened after right click drag.
      expect(find.text('Renommer le composant'), findsNothing);
      expect(find.byKey(const ValueKey('editor-dialog-panel')), findsNothing);

      // 2. Right click + wheel zooms centered on mouse pointer without Ctrl.
      const mousePos = Offset(300, 200);
      final relativeX = (mousePos.dx - panned.left) / panned.width;
      final relativeY = (mousePos.dy - panned.top) / panned.height;

      // Hold right click down.
      final holdRightClick = await tester.startGesture(
        mousePos,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();

      // Scroll wheel while holding right click.
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: mousePos,
          scrollDelta: const Offset(0, -60),
        ),
      );
      // Slight mouse twitch during wheel does not trigger accidental panning.
      await holdRightClick.moveBy(const Offset(2, 2));
      await tester.pumpAndSettle();

      final zoomed = screenRect(tester, target);
      expect(zoomed.width, closeTo(panned.width * math.exp(.15), .01));
      expect(zoomed.left + relativeX * zoomed.width, closeTo(mousePos.dx, .05));
      expect(zoomed.top + relativeY * zoomed.height, closeTo(mousePos.dy, .05));

      // Release right click: context menu should NOT open.
      await holdRightClick.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-dialog-panel')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zoom and pan work while property editor dialog is open',
    (tester) async {
      await pumpPage(tester);
      final target = find.byKey(const ValueKey('zoom-target-content'));
      await selectTargetZone(tester);
      await tester.pumpAndSettle();

      // Open a property dialog beside the target.
      showEditorDialog<void>(
        context: tester.element(target),
        builder: (dialogContext) => const SizedBox(
          width: 300,
          child: Text('Propriétés du composant'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-dialog-panel')), findsOneWidget);
      expect(find.text('Propriétés du composant'), findsOneWidget);

      screenRect(tester, target);

      // 1. Zoom toolbar and slider are available and working in dialog.
      expect(find.byKey(const ValueKey('editor-zoom-toolbar')), findsOneWidget);
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('editor-zoom-slider')),
      );
      slider.onChanged!(2.5);
      await tester.pumpAndSettle();
      expect(screenRect(tester, target).width, closeTo(320 * 2.5, .1));

      // 2. Right click drag pans the canvas while dialog is open.
      final beforePan = screenRect(tester, target);
      final panGesture = await tester.startGesture(
        const Offset(100, 100),
        buttons: kSecondaryMouseButton,
      );
      await panGesture.moveBy(const Offset(40, 30));
      await tester.pumpAndSettle();
      await panGesture.up();
      await tester.pumpAndSettle();
      final afterPan = screenRect(tester, target);
      expect(afterPan.left, beforePan.left + 40);
      expect(afterPan.top, beforePan.top + 30);
      expect(find.byKey(const ValueKey('editor-dialog-panel')), findsOneWidget);

      // 3. Ctrl + wheel zooms centered on mouse pointer on the canvas beside dialog.
      const wheelPos = Offset(150, 150);
      final relX = (wheelPos.dx - afterPan.left) / afterPan.width;
      final relY = (wheelPos.dy - afterPan.top) / afterPan.height;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: wheelPos,
          scrollDelta: Offset(0, -60),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final zoomedWithCtrl = screenRect(tester, target);
      expect(zoomedWithCtrl.width, greaterThan(afterPan.width));
      expect(zoomedWithCtrl.left + relX * zoomedWithCtrl.width, closeTo(wheelPos.dx, .05));
      expect(zoomedWithCtrl.top + relY * zoomedWithCtrl.height, closeTo(wheelPos.dy, .05));
      expect(find.byKey(const ValueKey('editor-dialog-panel')), findsOneWidget);

      // 4. Right click + wheel zooms centered on mouse pointer beside dialog.
      final relX2 = (wheelPos.dx - zoomedWithCtrl.left) / zoomedWithCtrl.width;
      final relY2 = (wheelPos.dy - zoomedWithCtrl.top) / zoomedWithCtrl.height;
      final holdSecondary = await tester.startGesture(
        wheelPos,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: wheelPos,
          scrollDelta: Offset(0, -60),
        ),
      );
      await tester.pumpAndSettle();
      final zoomedWithSecondary = screenRect(tester, target);
      expect(zoomedWithSecondary.width, greaterThan(zoomedWithCtrl.width));
      expect(zoomedWithSecondary.left + relX2 * zoomedWithSecondary.width, closeTo(wheelPos.dx, .05));
      expect(zoomedWithSecondary.top + relY2 * zoomedWithSecondary.height, closeTo(wheelPos.dy, .05));
      await holdSecondary.up();
      await tester.pumpAndSettle();

      // Dialog is still open.
      expect(find.byKey(const ValueKey('editor-dialog-panel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _target(BuildContext context) =>
    const ColoredBox(key: ValueKey('zoom-target-content'), color: Colors.blue);

Widget _second(BuildContext context) =>
    const ColoredBox(key: ValueKey('zoom-second-content'), color: Colors.green);
