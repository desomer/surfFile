import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/super_container.dart';
import 'package:super_container_layout/widgets/super_layout.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/widgets/style_edit_banner.dart';
import 'package:super_container_layout/widgets/layout_selection.dart';

void main() {
  const config = SuperLayoutConfig(
    north: true,
    south: false,
    east: false,
    west: false,
    placements: {
      SuperLayoutZone.center: ['content'],
    },
  );
  Widget layout(
    String id, {
    Widget? child,
    bool editable = true,
    bool showZoneNames = true,
  }) => SuperLayout(
    key: ValueKey(id),
    name: id,
    config: config,
    editable: editable,
    showZoneNames: showZoneNames,
    slots: [
      BuilderSlot(
        id: 'content',
        label: id,
        builder: (_) => child ?? SizedBox.expand(key: ValueKey('$id-content')),
      ),
    ],
  );
  Future<void> pump(
    WidgetTester tester,
    ValueNotifier<bool> mode,
    Widget child,
  ) => tester.pumpWidget(
    MaterialApp(
      home: StyleEditScope(
        controller: mode,
        child: Scaffold(body: child),
      ),
    ),
  );
  Finder inside(String id, String key) => find.descendant(
    of: find.byKey(ValueKey(id)),
    matching: find.byKey(ValueKey(key)),
  );

  testWidgets('axis controls share zone configuration across all surfaces', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    final key = GlobalKey<SuperLayoutState>();
    final changes = <SuperLayoutConfig>[];
    await pump(
      tester,
      mode,
      Stack(
        children: [
          Positioned.fill(
            child: SuperLayout(
              key: key,
              config: const SuperLayoutConfig(
                north: true,
                south: false,
                east: false,
                west: false,
                placements: {
                  SuperLayoutZone.center: ['a', 'b'],
                  SuperLayoutZone.north: ['n'],
                },
              ),
              onChanged: changes.add,
              slots: [
                for (final id in ['a', 'b', 'n'])
                  BuilderSlot(
                    id: id,
                    label: id,
                    builder: (_) => Align(
                      alignment: Alignment.topLeft,
                      child: Text(id, key: ValueKey('axis-content-$id')),
                    ),
                  ),
              ],
            ),
          ),
          const Positioned.fill(child: StyleEditBanner()),
        ],
      ),
    );
    final banner = find.byKey(const ValueKey('style-edit-banner-axis'));
    expect(banner, findsNothing);
    await tester.tap(find.byKey(const ValueKey('axis-content-a')));
    await tester.pumpAndSettle();
    expect(banner, findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('style-edit-banner-drag')),
      const Offset(0, 450),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Centre : Column - Passer en Row'), findsNWidgets(2));
    final a = find.byKey(const ValueKey('axis-content-a'));
    final b = find.byKey(const ValueKey('axis-content-b'));
    expect(tester.getTopLeft(a).dx, tester.getTopLeft(b).dx);
    expect(tester.getTopLeft(b).dy, greaterThan(tester.getTopLeft(a).dy));
    await tester.tap(banner);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.config.axisOf(SuperLayoutZone.center),
      Axis.horizontal,
    );
    expect(tester.getTopLeft(a).dy, tester.getTopLeft(b).dy);
    expect(tester.getTopLeft(b).dx, greaterThan(tester.getTopLeft(a).dx));
    expect(find.byTooltip('Centre : Row - Passer en Column'), findsNWidgets(2));

    await tester.tap(
      find.byKey(const ValueKey('super-layout-toggle-axis-center')),
    );
    await tester.pumpAndSettle();
    expect(
      key.currentState!.config.axisOf(SuperLayoutZone.center),
      Axis.vertical,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('super-layout-name-north')),
        matching: find.text('Nord'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Nord : Column - Passer en Row'), findsNWidgets(2));
    await tester.tap(a, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('style-menu-axis-Super layout')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('style-menu-Super layout')), findsNothing);
    expect(find.byType(SuperLayoutEditor), findsNothing);
    expect(
      key.currentState!.config.axisOf(SuperLayoutZone.north),
      Axis.horizontal,
    );
    expect(
      key.currentState!.config.axisOf(SuperLayoutZone.center),
      Axis.vertical,
    );
    expect(find.byTooltip('Nord : Row - Passer en Column'), findsNWidgets(2));
    await tester.tap(banner);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.config.axisOf(SuperLayoutZone.north),
      Axis.vertical,
    );

    expect(
      find.byKey(const ValueKey('super-layout-toggle-axis-north')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('super-layout-toggle-axis-nw')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('super-layout-toggle-axis-center')),
    );
    await tester.pumpAndSettle();
    expect(
      key.currentState!.config.axisOf(SuperLayoutZone.center),
      Axis.horizontal,
    );
    expect(changes.length, 5);
    final restored = SuperLayoutConfig.fromJson(changes.last.toJson());
    expect(restored.axisOf(SuperLayoutZone.center), Axis.horizontal);
    mode.value = false;
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    expect(
      find.byKey(const ValueKey('super-layout-toggle-axis-center')),
      findsNothing,
    );
    mode.value = true;
    await tester.pumpAndSettle();
    expect(banner, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(LayoutSelection.axisAction.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'banner axis follows nested selection and hides for read-only layouts',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      await pump(
        tester,
        mode,
        Stack(
          children: [
            Positioned.fill(child: layout('parent', child: layout('child'))),
            const Positioned.fill(child: StyleEditBanner()),
          ],
        ),
      );
      await tester.tapAt(const Offset(600, 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-axis')));
      await tester.pumpAndSettle();
      final child = tester.state<SuperLayoutState>(
        find.byKey(const ValueKey('child')),
      );
      final parent = tester.state<SuperLayoutState>(
        find.byKey(const ValueKey('parent')),
      );
      expect(child.config.axisOf(SuperLayoutZone.center), Axis.horizontal);
      expect(parent.config.axisOf(SuperLayoutZone.center), Axis.vertical);
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-path-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-axis')));
      await tester.pumpAndSettle();
      expect(parent.config.axisOf(SuperLayoutZone.center), Axis.horizontal);
      expect(child.config.axisOf(SuperLayoutZone.center), Axis.horizontal);
      await pump(
        tester,
        mode,
        Stack(
          children: [
            Positioned.fill(child: layout('read-only', editable: false)),
            const Positioned.fill(child: StyleEditBanner()),
          ],
        ),
      );
      await tester.tapAt(const Offset(600, 350));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('style-edit-banner-axis')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('super-layout-toggle-axis-center')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('context menu adds slots to centre or selected zone', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    final changes = <SuperLayoutConfig>[];
    await pump(
      tester,
      mode,
      SuperLayout(
        label: 'Menu layout',
        config: const SuperLayoutConfig(
          north: true,
          south: false,
          east: false,
          west: false,
          placements: {
            SuperLayoutZone.north: ['north'],
            SuperLayoutZone.center: ['content'],
          },
        ),
        onChanged: changes.add,
        slots: [
          BuilderSlot(
            id: 'north',
            label: 'North slot',
            builder: (_) => const Text('North content'),
          ),
          BuilderSlot(
            id: 'content',
            label: 'Content slot',
            builder: (_) => const SuperContainer(
              label: 'Nested container',
              child: Align(
                alignment: Alignment.topLeft,
                child: Text('Menu content'),
              ),
            ),
          ),
          BuilderSlot(
            id: 'available',
            label: 'Available slot',
            builder: (_) => const Text('Added content'),
          ),
        ],
      ),
    );
    Future<void> openMenu() async {
      await tester.tap(
        find.text('Menu content'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(
      find.byKey(const ValueKey('style-menu-add-Nested container')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('style-menu-add-Menu layout')));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un slot dans Centre'), findsOneWidget);
    expect(find.byKey(const ValueKey('style-menu-Menu layout')), findsNothing);
    expect(find.byType(SuperLayoutEditor), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('super-layout-add-slot-available')),
    );
    await tester.pumpAndSettle();
    expect(changes.last.placementsOf(SuperLayoutZone.center), [
      'content',
      'available',
    ]);

    await tester.tap(find.text('North content'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('super-layout-name-north')),
        matching: find.text('Nord'),
      ),
    );
    await tester.pumpAndSettle();
    await openMenu();
    await tester.tap(find.byKey(const ValueKey('style-menu-add-Menu layout')));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un slot dans Nord'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('super-layout-add-slot-available')),
    );
    await tester.pumpAndSettle();
    expect(changes.last.placementsOf(SuperLayoutZone.north), [
      'north',
      'available',
    ]);
    expect(changes.last.placementsOf(SuperLayoutZone.center), ['content']);

    await openMenu();
    await tester.tap(find.text('Menu layout'));
    await tester.pumpAndSettle();
    expect(find.byType(SuperLayoutEditor), findsOneWidget);
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    mode.value = false;
    await tester.pumpAndSettle();
    await openMenu();
    expect(
      find.byKey(const ValueKey('style-menu-add-Menu layout')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('style-menu-Menu layout')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty zone placeholders hide labels only when editing overlays are shown',
    (tester) async {
      final mode = ValueNotifier(false);
      addTearDown(mode.dispose);
      await pump(
        tester,
        mode,
        Row(
          children: [
            Expanded(child: layout('left')),
            Expanded(child: layout('right')),
          ],
        ),
      );
      final placeholder = find.descendant(
        of: inside('left', 'super-layout-north'),
        matching: find.byType(DecoratedBox),
      );
      BoxBorder? placeholderBorder() =>
          (tester.widget<DecoratedBox>(placeholder).decoration as BoxDecoration)
              .border;
      expect(placeholderBorder(), isNull);
      expect(find.text('Nord'), findsNothing);
      mode.value = true;
      await tester.pumpAndSettle();
      final border = placeholderBorder();
      expect(border, isNotNull);
      expect(find.text('Nord'), findsNWidgets(2));

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: inside('left', 'super-layout-north'),
          matching: find.text('Nord'),
        ),
        findsNothing,
      );
      expect(inside('left', 'super-layout-add-north'), findsOneWidget);
      expect(inside('left', 'super-layout-toggle-axis-north'), findsNothing);
      expect(placeholderBorder(), border);
      expect(find.text('Nord'), findsOneWidget);

      await tester.tapAt(const Offset(420, 20));
      await tester.pumpAndSettle();
      expect(placeholderBorder(), border);
      expect(
        find.descendant(
          of: inside('left', 'super-layout-north'),
          matching: find.text('Nord'),
        ),
        findsOneWidget,
      );
      mode.value = false;
      await tester.pumpAndSettle();
      expect(placeholderBorder(), isNull);
      expect(find.text('Nord'), findsNothing);

      mode.value = true;
      await pump(tester, mode, layout('no-badges', showZoneNames: false));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Nord'), findsOneWidget);
      expect(inside('no-badges', 'super-layout-name-north'), findsNothing);
      await pump(tester, mode, layout('read-only', editable: false));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Nord'), findsOneWidget);
      expect(inside('read-only', 'super-layout-add-north'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('banner segments select ancestor layouts and their zones', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(
      tester,
      mode,
      Stack(
        children: [
          Positioned.fill(child: layout('parent', child: layout('child'))),
          const Positioned.fill(child: StyleEditBanner()),
        ],
      ),
    );
    Future<void> clickSegment(int index) async {
      final finder = find.byKey(ValueKey('style-edit-banner-path-$index'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tester.tapAt(const Offset(600, 350));
    await tester.pumpAndSettle();
    expect(inside('child', 'super-layout-name-center'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('super-layout-name-center')),
      findsOneWidget,
    );
    await clickSegment(0);
    expect(inside('child', 'super-layout-name-center'), findsNothing);
    expect(
      find.byKey(const ValueKey('super-layout-name-center')),
      findsOneWidget,
    );
    expect(inside('parent', 'super-layout-add-north'), findsOneWidget);

    await tester.tapAt(const Offset(600, 350));
    await tester.pumpAndSettle();
    await clickSegment(1);
    expect(inside('child', 'super-layout-name-center'), findsNothing);
    expect(
      inside('parent', 'super-layout-zone-selected-center'),
      findsOneWidget,
    );
    await clickSegment(0);
    expect(inside('parent', 'super-layout-zone-selected-center'), findsNothing);

    await tester.tapAt(const Offset(600, 350));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: inside('child', 'super-layout-name-center'),
        matching: find.text('Centre'),
      ),
    );
    await tester.pumpAndSettle();
    await clickSegment(2);
    expect(inside('child', 'super-layout-name-center'), findsOneWidget);
    expect(inside('child', 'super-layout-zone-selected-center'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'breadcrumb selection resolves identical labels through active ancestry',
    () {
      final first = Object();
      final second = Object();
      final child = Object();
      Object? selected;
      LayoutSelection.register(first, ['Layout'], (_) => selected = first);
      LayoutSelection.register(second, ['Layout'], (_) => selected = second);
      LayoutSelection.register(
        child,
        ['Layout', 'Centre', 'Layout'],
        (_) => selected = child,
        parent: first,
      );
      addTearDown(() {
        LayoutSelection.report(child, const []);
        for (final owner in [first, second, child]) {
          LayoutSelection.unregister(owner);
        }
      });
      LayoutSelection.report(child, ['Layout', 'Centre', 'Layout']);
      LayoutSelection.select(['Layout']);
      expect(selected, same(first));
      LayoutSelection.select(['Layout', 'Centre', 'Layout']);
      expect(selected, same(child));
    },
  );

  testWidgets('only the selected layout exposes all overlays', (tester) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(
      tester,
      mode,
      Row(
        children: [
          Expanded(child: layout('left')),
          Expanded(child: layout('right')),
        ],
      ),
    );
    expect(
      find.byKey(const ValueKey('super-layout-name-center')),
      findsNothing,
    );
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byKey(const ValueKey('slot-label-content')), findsNothing);
    expect(
      find.byKey(const ValueKey('super-layout-slot-drop-center')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('left-content')));
    await tester.pumpAndSettle();
    expect(inside('left', 'super-layout-name-center'), findsOneWidget);
    expect(inside('left', 'super-layout-add-north'), findsOneWidget);
    expect(inside('left', 'slot-label-content'), findsOneWidget);
    expect(inside('left', 'super-layout-slot-drop-center'), findsOneWidget);
    expect(inside('right', 'super-layout-name-center'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('right-content')));
    await tester.pumpAndSettle();
    expect(inside('right', 'super-layout-name-center'), findsOneWidget);
    expect(inside('left', 'super-layout-name-center'), findsNothing);
    expect(inside('left', 'super-layout-add-north'), findsNothing);
    expect(inside('left', 'slot-label-content'), findsNothing);
    mode.value = false;
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsNothing);
    expect(
      find.byKey(const ValueKey('super-layout-name-center')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing selected layout does not select its replacement', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(tester, mode, layout('first'));
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsOneWidget);
    await pump(tester, mode, layout('replacement'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'nested selection chooses deepest layout without stealing button taps',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      var presses = 0;
      await pump(
        tester,
        mode,
        layout(
          'parent',
          child: layout(
            'child',
            child: Center(
              child: TextButton(
                onPressed: () => presses++,
                child: const Text('Contenu'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Contenu'));
      await tester.pumpAndSettle();
      expect(presses, 1);
      expect(inside('child', 'super-layout-name-center'), findsOneWidget);
      final names = find.byKey(const ValueKey('super-layout-name-center'));
      expect(names, findsOneWidget);
      await tester.tapAt(const Offset(700, 20));
      await tester.pumpAndSettle();
      // La zone Nord du parent est libre ; cliquer dessus selectionne le parent.
      expect(inside('child', 'super-layout-name-center'), findsNothing);
      expect(names, findsOneWidget);
      expect(inside('parent', 'slot-label-content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outside edit mode clicks and right clicks do not select overlays',
    (tester) async {
      final mode = ValueNotifier(false);
      addTearDown(mode.dispose);
      await pump(tester, mode, layout('layout'));
      await tester.tap(find.byKey(const ValueKey('layout-content')));
      mode.value = true;
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('layout-content')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(inside('layout', 'super-layout-add-north'), findsNothing);
      expect(
        find.byKey(const ValueKey('style-menu-add-Super layout')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 590));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('layout-content')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), findsOneWidget);
    },
  );
}
