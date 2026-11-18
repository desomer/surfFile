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
    EditorSlotState.closePinnedMenu();
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets(
    'pin icon switches context menu to floating non-modal mode, preserves position, and tracks selection and right-clicks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => SuperPage(
              maxAutoZoomExtent: 0,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 360,
                  height: 320,
                  child: SuperLayout(
                    id: 'root-layout',
                    config: const SuperLayoutConfig(
                      north: false,
                      south: false,
                      west: false,
                      east: false,
                      placements: {
                        SuperLayoutZone.center: ['slot-alpha', 'slot-beta'],
                      },
                    ),
                    slots: [
                      BuilderSlot(
                        id: 'slot-alpha',
                        label: 'AlphaSlot',
                        builder: (_) => EditorSlot(
                          id: 'comp-alpha',
                          label: 'AlphaComp',
                          onEdit: () async {},
                          child: const SizedBox(
                            key: ValueKey('alpha-target'),
                            width: 140,
                            height: 80,
                            child: Center(child: Text('Alpha')),
                          ),
                        ),
                      ),
                      BuilderSlot(
                        id: 'slot-beta',
                        label: 'BetaSlot',
                        builder: (_) => EditorSlot(
                          id: 'comp-beta',
                          label: 'BetaComp',
                          onEdit: () async {},
                          child: const SizedBox(
                            key: ValueKey('beta-target'),
                            width: 140,
                            height: 80,
                            child: Center(child: Text('Beta')),
                          ),
                        ),
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

      final editMode = StyleEditScope.controllerOf(
        tester.element(find.byType(SuperPage)),
      )!;
      editMode.value = true;
      await tester.pumpAndSettle();

      // Open context menu on Alpha via right-click.
      await tester.tap(
        find.byKey(const ValueKey('alpha-target')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      final menuFinder = find.byKey(
        const ValueKey('editor-context-menu-dialog'),
      );
      final pinButton = find.byKey(const ValueKey('editor-context-menu-pin'));
      expect(menuFinder, findsOneWidget);
      expect(pinButton, findsOneWidget);
      expect(EditorSlotState.isMenuPinned, isFalse);
      expect(
        find.descendant(
          of: pinButton,
          matching: find.byIcon(Icons.push_pin_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('style-menu-AlphaComp')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('style-menu-BetaComp')), findsNothing);

      // Drag the menu to a custom position, then pin it.
      await tester.drag(
        find.byKey(const ValueKey('editor-context-menu-drag')),
        const Offset(40, 30),
      );
      await tester.pumpAndSettle();
      final draggedTopLeft = tester.getTopLeft(menuFinder);

      await tester.tap(pinButton);
      await tester.pumpAndSettle();

      expect(EditorSlotState.isMenuPinned, isTrue);
      expect(menuFinder, findsOneWidget);
      expect(tester.getTopLeft(menuFinder), draggedTopLeft);
      expect(
        find.descendant(of: pinButton, matching: find.byIcon(Icons.push_pin)),
        findsOneWidget,
      );

      // Clicking outside does not close the pinned menu, nor does closeActiveMenu().
      await tester.tapAt(const Offset(500, 700));
      await tester.pumpAndSettle();
      expect(menuFinder, findsOneWidget);

      EditorSlotState.closeActiveMenu();
      await tester.pumpAndSettle();
      expect(menuFinder, findsOneWidget);

      // Right-clicking Beta updates the pinned menu content without moving it.
      await tester.tap(
        find.byKey(const ValueKey('beta-target')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(menuFinder, findsOneWidget);
      expect(tester.getTopLeft(menuFinder), draggedTopLeft);
      expect(find.byKey(const ValueKey('style-menu-BetaComp')), findsOneWidget);
      expect(find.byKey(const ValueKey('style-menu-AlphaComp')), findsNothing);

      // Selecting Alpha via LayoutSelection updates the pinned menu back to Alpha
      // while keeping its pinned position.
      final alphaSlotState = tester.state<EditorSlotState>(
        find.byWidgetPredicate((w) => w is EditorSlot && w.id == 'comp-alpha'),
      );
      LayoutSelection.updateActiveFocus(
        alphaSlotState.context,
        id: 'comp-alpha',
      );
      await tester.pumpAndSettle();

      expect(menuFinder, findsOneWidget);
      expect(tester.getTopLeft(menuFinder), draggedTopLeft);
      expect(
        find.byKey(const ValueKey('style-menu-AlphaComp')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('style-menu-BetaComp')), findsNothing);

      // Unpinning in-place keeps the menu at the same position as unpinned,
      // and the next outside tap dismisses it.
      await tester.tap(pinButton);
      await tester.pumpAndSettle();

      expect(EditorSlotState.isMenuPinned, isFalse);
      expect(menuFinder, findsOneWidget);
      expect(tester.getTopLeft(menuFinder), draggedTopLeft);
      expect(
        find.descendant(
          of: pinButton,
          matching: find.byIcon(Icons.push_pin_outlined),
        ),
        findsOneWidget,
      );

      await tester.tapAt(const Offset(500, 700));
      await tester.pumpAndSettle();
      expect(menuFinder, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pinned context menu stays open on quick actions, hides temporarily during editor dialogs, and closes when exiting edit mode',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final editing = ValueNotifier<bool>(true);
      addTearDown(editing.dispose);
      var axis = Axis.horizontal;
      var subtitleText = 'Initial';
      late StateSetter rebuildHost;

      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: editing,
            child: StatefulBuilder(
              builder: (context, setHostState) {
                rebuildHost = setHostState;
                return Scaffold(
                  body: Center(
                    child: EditorSlot(
                      id: 'zone-host',
                      label: 'ZoneHost',
                      menuSubtitle: () => subtitleText,
                      axisAction: () => LayoutAxisAction(
                        zoneLabel: 'Centre',
                        axis: axis,
                        onToggle: () => rebuildHost(() {
                          axis = axis == Axis.horizontal
                              ? Axis.vertical
                              : Axis.horizontal;
                        }),
                      ),
                      onEdit: () async {
                        await showEditorDialog<void>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            key: const ValueKey('test-editor-dialog'),
                            title: const Text('Éditeur test'),
                            actions: [
                              TextButton(
                                key: const ValueKey('apply-and-close-dialog'),
                                onPressed: () {
                                  rebuildHost(() => subtitleText = 'Modifié');
                                  Navigator.of(dialogContext).pop();
                                },
                                child: const Text('Appliquer'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const SizedBox(
                        key: ValueKey('zone-target'),
                        width: 220,
                        height: 120,
                        child: Center(child: Text('Target')),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open and pin context menu.
      await tester.tap(
        find.byKey(const ValueKey('zone-target')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-context-menu-pin')));
      await tester.pumpAndSettle();

      final menuFinder = find.byKey(
        const ValueKey('editor-context-menu-dialog'),
      );
      expect(menuFinder, findsOneWidget);
      final pinnedPos = tester.getTopLeft(menuFinder);

      // 1. Quick action (axis toggle) keeps menu open and refreshes in-place.
      expect(axis, Axis.horizontal);
      await tester.tap(find.byKey(const ValueKey('style-menu-axis-ZoneHost')));
      await tester.pumpAndSettle();

      expect(axis, Axis.vertical);
      expect(menuFinder, findsOneWidget);
      expect(tester.getTopLeft(menuFinder), pinnedPos);

      // 2. Opening an editor dialog temporarily hides the pinned menu,
      // then restores it with updated state when the dialog closes.
      expect(find.text('Initial'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('style-menu-ZoneHost')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('test-editor-dialog')), findsOneWidget);
      expect(EditorSlotState.isMenuPinned, isTrue);
      expect(menuFinder, findsNothing);

      await tester.tap(find.byKey(const ValueKey('apply-and-close-dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('test-editor-dialog')), findsNothing);
      expect(menuFinder, findsOneWidget);
      expect(tester.getTopLeft(menuFinder), pinnedPos);
      expect(find.text('Modifié'), findsOneWidget);

      // 3. Exiting edit mode closes the pinned menu automatically.
      editing.value = false;
      await tester.pumpAndSettle();

      expect(EditorSlotState.isMenuPinned, isFalse);
      expect(menuFinder, findsNothing);

      // 4. Re-enter edit mode, pin again, and verify explicit close button (×).
      editing.value = true;
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('zone-target')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-context-menu-pin')));
      await tester.pumpAndSettle();
      expect(EditorSlotState.isMenuPinned, isTrue);

      await tester.tap(find.byKey(const ValueKey('editor-context-menu-close')));
      await tester.pumpAndSettle();
      expect(EditorSlotState.isMenuPinned, isFalse);
      expect(menuFinder, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pinned context menu can be dragged while pinned and falls back to parent slot when targeted child is removed',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final editing = ValueNotifier<bool>(true);
      addTearDown(editing.dispose);
      var showChild = true;
      late StateSetter rebuildHost;

      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: editing,
            child: StatefulBuilder(
              builder: (context, setHostState) {
                rebuildHost = setHostState;
                return Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: EditorSlot(
                      id: 'parent-slot',
                      label: 'ParentContainer',
                      onEdit: () async {},
                      child: SizedBox(
                        width: 240,
                        height: 160,
                        child: showChild
                            ? EditorSlotAction(
                                label: 'ChildSlot',
                                enabled: true,
                                inline: true,
                                showEdit: false,
                                onEdit: () async {},
                                onRemove: () async {
                                  rebuildHost(() => showChild = false);
                                },
                                child: EditorSlot(
                                  id: 'child-slot',
                                  label: 'ChildLeaf',
                                  onEdit: () async {},
                                  child: const Center(
                                    key: ValueKey('child-leaf-target'),
                                    child: Text('Leaf'),
                                  ),
                                ),
                              )
                            : const Center(child: Text('Empty parent')),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('child-leaf-target')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-context-menu-pin')));
      await tester.pumpAndSettle();

      final menuFinder = find.byKey(
        const ValueKey('editor-context-menu-dialog'),
      );
      final initialPinnedPos = tester.getTopLeft(menuFinder);

      // Drag while already pinned.
      await tester.drag(
        find.byKey(const ValueKey('editor-context-menu-drag')),
        const Offset(80, 50),
      );
      await tester.pumpAndSettle();
      final movedPinnedPos = tester.getTopLeft(menuFinder);
      expect(movedPinnedPos, initialPinnedPos + const Offset(80, 50));

      expect(find.byKey(const ValueKey('style-menu-ChildLeaf')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('style-menu-ParentContainer')),
        findsOneWidget,
      );

      // Delete the child slot directly from the pinned menu; menu stays open at
      // its dragged position and falls back cleanly to ParentContainer.
      await tester.tap(
        find.byKey(const ValueKey('style-menu-remove-ChildSlot')),
      );
      await tester.pumpAndSettle();

      expect(showChild, isFalse);
      expect(EditorSlotState.isMenuPinned, isTrue);
      expect(menuFinder, findsOneWidget);
      expect(tester.getTopLeft(menuFinder), movedPinnedPos);
      expect(find.byKey(const ValueKey('style-menu-ChildLeaf')), findsNothing);
      expect(
        find.byKey(const ValueKey('style-menu-ParentContainer')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
