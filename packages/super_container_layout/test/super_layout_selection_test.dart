import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/components/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/widgets/editing/overlay/style_edit_banner.dart';
import 'package:super_container_layout/widgets/components/super_layout/layout_selection.dart';
import 'package:super_container_layout/widgets/editing/overlay/editor_zoom.dart';

Widget _menuContent(BuildContext context) =>
    const ColoredBox(color: Colors.blue);

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

  testWidgets(
    'right click selects actual zones in nested layout menu entries',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      await pump(tester, mode, layout('parent', child: layout('child')));
      await tester.tapAt(const Offset(600, 400));
      await tester.pumpAndSettle();
      LayoutSelection.select(['parent', 'Centre', 'child', 'Centre', 'child']);
      await tester.pumpAndSettle();
      final north = tester.getRect(inside('child', 'super-layout-north'));
      await tester.tapAt(
        Offset(north.left + 30, north.center.dy),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['parent', 'Centre', 'child', 'Nord']);
      final selectedZoneRow = find.byKey(const ValueKey('style-menu-Nord'));
      final selectedLayoutRow = find
          .byKey(const ValueKey('style-menu-Layout'))
          .first;
      final parentZoneRow = find.byKey(const ValueKey('style-menu-Centre'));
      final parentLayoutRow = find
          .byKey(const ValueKey('style-menu-Layout'))
          .last;
      expect(selectedZoneRow, findsOneWidget);
      expect(parentZoneRow, findsOneWidget);
      expect(
        tester.getCenter(selectedZoneRow).dy,
        lessThan(tester.getCenter(selectedLayoutRow).dy),
      );
      expect(
        tester.getCenter(selectedLayoutRow).dy,
        lessThan(tester.getCenter(parentZoneRow).dy),
      );
      expect(
        tester.getCenter(parentZoneRow).dy,
        lessThan(tester.getCenter(parentLayoutRow).dy),
      );
      await tester.tapAt(const Offset(10, 590));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(600, 20), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['parent', 'Nord']);
      expect(find.byKey(const ValueKey('style-menu-Nord')), findsOneWidget);
      expect(find.byKey(const ValueKey('style-menu-Centre')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('right click targets transformed zones with custom labels', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await pump(
      tester,
      mode,
      EditorZoom(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: SuperLayout(
              label: 'Zoom menu',
              config: config.copyWith(autoSides: {}, northSize: 80),
              zoneLabels: const {SuperLayoutZone.north: 'En haut'},
              slots: const [
                BuilderSlot(
                  id: 'content',
                  label: 'Content',
                  builder: _menuContent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(300, 200));
    await tester.pumpAndSettle();
    Offset screenPoint(Finder finder, Offset local) {
      return tester.renderObject<RenderBox>(finder).localToGlobal(local);
    }

    final north = find.byKey(const ValueKey('super-layout-north'));
    await tester.tapAt(
      screenPoint(north, const Offset(30, 20)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(LayoutSelection.path.value, ['Zoom menu', 'En haut']);
    expect(find.byKey(const ValueKey('style-menu-En haut')), findsOneWidget);
    expect(find.byKey(const ValueKey('style-menu-Zoom menu')), findsOneWidget);
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    final center = find.byKey(const ValueKey('super-layout-center'));
    await tester.tapAt(
      screenPoint(center, const Offset(120, 25)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(LayoutSelection.path.value, ['Zoom menu', 'Centre', 'Content']);
    expect(find.byKey(const ValueKey('style-menu-Centre')), findsOneWidget);
    expect(find.byKey(const ValueKey('style-menu-Zoom menu')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final breadcrumb in [true, false]) {
    testWidgets(
      'returning to parent clears child and grandchild selections via ${breadcrumb ? 'breadcrumb' : 'click'}',
      (tester) async {
        final mode = ValueNotifier(true);
        addTearDown(mode.dispose);
        await pump(
          tester,
          mode,
          layout('parent', child: layout('child', child: layout('grandchild'))),
        );
        await tester.tapAt(const Offset(600, 400));
        await tester.pumpAndSettle();
        LayoutSelection.select([
          'parent',
          'Centre',
          'child',
          'Centre',
          'grandchild',
        ]);
        await tester.pumpAndSettle();
        await tester.tap(inside('grandchild', 'slot-label-select-content'));
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value.last, 'grandchild');
        expect(inside('grandchild', 'slot-resize-content-se'), findsOneWidget);
        await tester.tapAt(const Offset(600, 80));
        await tester.pumpAndSettle();
        LayoutSelection.select([
          'parent',
          'Centre',
          'child',
          'Centre',
          'child',
        ]);
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value.last, 'child');
        if (breadcrumb) {
          LayoutSelection.select(['parent']);
        } else {
          await tester.tapAt(const Offset(600, 20));
        }
        await tester.pumpAndSettle();
        expect(
          LayoutSelection.path.value,
          breadcrumb ? ['parent'] : ['parent', 'Nord'],
        );
        await tester.tapAt(const Offset(600, 80));
        await tester.pumpAndSettle();
        expect(inside('child', 'slot-resize-content-se'), findsNothing);
        LayoutSelection.select([
          'parent',
          'Centre',
          'child',
          'Centre',
          'grandchild',
        ]);
        await tester.pumpAndSettle();
        expect(LayoutSelection.path.value, [
          'parent',
          'Centre',
          'child',
          'Centre',
          'grandchild',
        ]);
        expect(inside('grandchild', 'slot-resize-content-se'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('descendant clearing uses ancestry rather than identical labels', () {
    final root = Object();
    final child = Object();
    final grandchild = Object();
    final sibling = Object();
    final cleared = <Object>[];
    for (final owner in [root, child, grandchild, sibling]) {
      LayoutSelection.register(
        owner,
        ['Same'],
        (_) {},
        parent: identical(owner, child)
            ? root
            : identical(owner, grandchild)
            ? child
            : null,
        onDeselect: () => cleared.add(owner),
      );
    }
    addTearDown(() {
      for (final owner in [root, child, grandchild, sibling]) {
        LayoutSelection.unregister(owner);
      }
    });
    LayoutSelection.deselectDescendants(root);
    expect(cleared, [child, grandchild]);
  });

  testWidgets(
    'switching layouts by content click clears the previous zone and slot',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      await pump(
        tester,
        mode,
        Row(
          children: [
            Expanded(child: layout('first')),
            Expanded(child: layout('second')),
          ],
        ),
      );
      await tester.tapAt(const Offset(300, 350));
      await tester.pumpAndSettle();
      LayoutSelection.select(['first', 'Centre', 'first']);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['first', 'Centre', 'first']);
      expect(inside('first', 'slot-resize-content-se'), findsOneWidget);
      await tester.tapAt(const Offset(700, 350));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['second', 'Centre']);
      await tester.tapAt(const Offset(300, 350));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['first', 'Centre']);
      expect(inside('first', 'slot-resize-content-se'), findsNothing);
      expect(
        inside('first', 'super-layout-zone-selected-center'),
        findsOneWidget,
      );

      LayoutSelection.select(['first', 'Centre']);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(700, 350));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(300, 350));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['first', 'Centre']);
      await tester.pump(const Duration(seconds: 1));
      // Only a double click enters the zone's direct slot.
      await tester.tapAt(const Offset(300, 350));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(300, 350));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['first', 'Centre', 'first']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clicking slot labels selects their banner path without changing layout',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      final changes = <SuperLayoutConfig>[];
      await pump(
        tester,
        mode,
        Stack(
          children: [
            Positioned.fill(
              child: SuperLayout(
                name: 'Layout',
                config: config.copyWith(
                  placements: {
                    SuperLayoutZone.center: ['a', 'b'],
                  },
                ),
                onChanged: changes.add,
                slots: [
                  for (final id in ['a', 'b'])
                    BuilderSlot(
                      id: id,
                      label: 'Slot $id',
                      builder: (_) =>
                          SizedBox.expand(key: ValueKey('select-content-$id')),
                    ),
                ],
              ),
            ),
            const Positioned.fill(child: StyleEditBanner()),
          ],
        ),
      );
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('select-content-a'))),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('style-edit-banner-drag')),
        const Offset(0, 450),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-label-select-a')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Layout', 'Centre', 'Slot a']);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('style-edit-banner-path')),
          matching: find.text('Slot a'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('slot-label-select-b')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Layout', 'Centre', 'Slot b']);
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-path-2')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Layout', 'Centre']);
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-path-1')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Layout']);
      await tester.tap(find.byKey(const ValueKey('slot-label-select-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-label-select-a')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Layout', 'Centre']);
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-path-0')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Layout']);
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-path-0')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, isEmpty);
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('select-content-a'))),
      );
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Layout', 'Centre']);
      expect(changes, isEmpty);
      mode.value = false;
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, isEmpty);
    },
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
    await tester.tap(
      find.byKey(const ValueKey('axis-content-n')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final menuZone = find.byKey(const ValueKey('style-menu-Nord'));
    expect(menuZone, findsOneWidget);
    final menuRow = find.byKey(const ValueKey('style-menu-Layout'));
    final menuLabel = find.descendant(
      of: menuZone,
      matching: find.text('zone Nord'),
    );
    final menuAxis = find.byKey(const ValueKey('style-menu-axis-Nord'));
    expect(
      tester.getCenter(menuRow).dy,
      greaterThan(tester.getCenter(menuZone).dy),
    );
    expect(
      tester.getRect(menuLabel).right,
      lessThan(tester.getRect(menuAxis).left),
    );
    await tester.tap(find.byKey(const ValueKey('style-menu-axis-Nord')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('style-menu-Layout')), findsNothing);
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
            builder: (_) => const EditableSurface(
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
    expect(
      find.byKey(const ValueKey('style-menu-add-Menu layout')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('style-menu-add-Centre')));
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
    await tester.tap(
      find.text('North content'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-menu-add-Nord')));
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
    await tester.tap(find.byKey(const ValueKey('style-menu-Centre')));
    await tester.pumpAndSettle();
    expect(find.text('Flux de la zone : Centre'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await openMenu();
    await tester.tap(find.text('Menu layout'));
    await tester.pumpAndSettle();
    expect(find.byType(SuperLayoutEditor), findsOneWidget);
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    mode.value = false;
    await tester.pumpAndSettle();
    await openMenu();
    expect(find.byKey(const ValueKey('style-menu-add-Centre')), findsNothing);
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

    Future<void> selectChild() async {
      LayoutSelection.select(['parent', 'Centre', 'child', 'Nord']);
      await tester.pumpAndSettle();
      LayoutSelection.select(['parent', 'Centre', 'child']);
      await tester.pumpAndSettle();
    }

    await tester.tapAt(const Offset(600, 350));
    await tester.pumpAndSettle();
    await selectChild();
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

    await selectChild();
    await clickSegment(1);
    expect(inside('child', 'super-layout-name-center'), findsNothing);
    expect(
      inside('parent', 'super-layout-zone-selected-center'),
      findsOneWidget,
    );
    await clickSegment(0);
    expect(inside('parent', 'super-layout-zone-selected-center'), findsNothing);

    await selectChild();
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
    await clickSegment(2);
    expect(LayoutSelection.path.value, isEmpty);
    expect(inside('child', 'super-layout-name-center'), findsNothing);
    await tester.tapAt(const Offset(600, 350));
    await tester.pumpAndSettle();
    expect(LayoutSelection.path.value, ['parent', 'Centre']);
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
    'nested selection descends progressively without stealing button taps',
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
      expect(LayoutSelection.path.value, ['parent', 'Centre']);
      for (var level = 0; level < 2; level++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.tapAt(const Offset(600, 400));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(const Offset(600, 400));
        await tester.pumpAndSettle();
      }
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
      expect(inside('layout', 'super-layout-add-north'), findsOneWidget);
      expect(LayoutSelection.path.value, ['layout', 'Centre', 'layout']);
      expect(
        find.byKey(const ValueKey('style-menu-add-Centre')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('style-menu-Layout')), findsOneWidget);
      await tester.tapAt(const Offset(10, 590));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('layout-content')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), findsOneWidget);
    },
  );

  testWidgets(
    'dedicated zone context menu entry separates zone actions from layout config',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      await pump(tester, mode, layout('layout'));
      await tester.tapAt(const Offset(300, 350));
      await tester.pumpAndSettle();

      // Right-click on the zone name badge opens the menu with the dedicated zone entry.
      await tester.tap(
        find.byKey(const ValueKey('super-layout-name-center')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      final zoneRow = find.byKey(const ValueKey('style-menu-Centre'));
      final layoutRow = find.byKey(const ValueKey('style-menu-Layout'));
      expect(zoneRow, findsOneWidget);
      expect(layoutRow, findsOneWidget);
      final zoneTitle = find.descendant(
        of: zoneRow,
        matching: find.text('zone Centre'),
      );
      final zoneSubtitle = find.byKey(const ValueKey('style-menu-zone-Centre'));
      final layoutSubtitle = find.byKey(
        const ValueKey('style-menu-zone-Layout'),
      );
      expect(zoneTitle, findsOneWidget);
      expect(zoneSubtitle, findsOneWidget);
      expect(tester.widget<Text>(zoneSubtitle).data, 'Layout');
      expect(layoutSubtitle, findsOneWidget);
      expect(tester.widget<Text>(layoutSubtitle).data, 'Zones');
      expect(
        find.descendant(
          of: zoneRow,
          matching: find.byIcon(EditorSlot.zoneMenuIcon),
        ),
        findsOneWidget,
      );
      expect(
        tester.getCenter(zoneSubtitle).dy,
        greaterThan(tester.getCenter(zoneTitle).dy),
      );
      expect(
        tester.getCenter(zoneRow).dy,
        lessThan(tester.getCenter(layoutRow).dy),
      );

      // Zone actions are exclusively on the zone row, with the ruler icon.
      expect(
        find.byKey(const ValueKey('style-menu-axis-Centre')),
        findsOneWidget,
      );
      final zoneRuler = find.byKey(
        const ValueKey('style-menu-zone-flow-Centre'),
      );
      expect(zoneRuler, findsOneWidget);
      expect(
        find.descendant(of: zoneRuler, matching: find.byIcon(Icons.straighten)),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('style-menu-add-Centre')),
        findsOneWidget,
      );

      // Layout row does not duplicate zone actions.
      expect(
        find.byKey(const ValueKey('style-menu-axis-Layout')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('style-menu-zone-flow-Layout')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('style-menu-add-Layout')), findsNothing);

      // Clicking the zone row opens the zone flow editor (no side size card for center).
      await tester.tap(
        find.descendant(of: zoneRow, matching: find.text('zone Centre')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Flux de la zone : Centre'), findsOneWidget);
      expect(find.text('Taille de la zone'), findsNothing);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      // Right-click on the North side zone and click the ruler icon to edit side size.
      await tester.tapAt(const Offset(300, 20), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-menu-zone-flow-Nord')));
      await tester.pumpAndSettle();
      expect(find.text('Flux de la zone : Nord'), findsOneWidget);
      expect(find.text('Taille de la zone'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('zone-flow-dialog-north-auto-size')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('zone-flow-dialog-north-resizable')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('zone-flow-dialog-north-auto-size')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('zone-flow-dialog-north-size')),
        findsWidgets,
      );
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();

      // Clicking the layout row opens the simplified SuperLayoutEditor.
      await tester.tapAt(
        const Offset(300, 350),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: layoutRow, matching: find.text('Layout')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SuperLayoutEditor), findsOneWidget);
      expect(find.text('Axe et flux d’affichage des zones'), findsNothing);
      expect(
        find.byKey(const ValueKey('super-layout-corner-nw')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('super-layout-side-west')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-layout-corner-nw')),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'right click displays deepest component in EditBanner including inside a Card',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      await pump(
        tester,
        mode,
        Stack(
          children: [
            Positioned.fill(
              child: SuperLayout(
                name: 'Main',
                config: config.copyWith(
                  placements: {
                    SuperLayoutZone.center: ['card-slot'],
                  },
                ),
                slots: [
                  BuilderSlot(
                    id: 'card-slot',
                    label: 'Ma Carte',
                    builder: (_) => EditableSurface(
                      id: 'card-slot',
                      label: 'Ma Carte',
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: SizedBox(
                          width: 120,
                          height: 48,
                          child: EditorSlot(
                            label: 'Mon Bouton',
                            onEdit: () async {},
                            child: const Center(child: Text('Action')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Positioned.fill(child: StyleEditBanner()),
          ],
        ),
      );

      // Right-click on the inner button inside the Card: banner shows full path to button.
      await tester.tap(find.text('Action'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, [
        'Main',
        'Centre',
        'Ma Carte',
        'Mon Bouton',
      ]);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('style-edit-banner-path')),
          matching: find.text('Mon Bouton'),
        ),
        findsOneWidget,
      );
      // Dismiss context menu.
      await tester.tapAt(const Offset(10, 590));
      await tester.pumpAndSettle();

      // Clicking 'Ma Carte' in the banner steps up to the Card slot in SuperLayout.
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-path-2')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Main', 'Centre', 'Ma Carte']);
      expect(find.byKey(const ValueKey('slot-resize-card-slot-se')), findsOneWidget);

      // Right-clicking directly on the Card outside the button selects the Card.
      await tester.tapAt(
        const Offset(100, 200),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Main', 'Centre', 'Ma Carte']);
      await tester.tapAt(const Offset(10, 590));
      await tester.pumpAndSettle();

      // Clicking segment 0 ('Main') twice clears selection, then 1 click = zone,
      // double-click = Card, second double-click = inner button.
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-path-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-edit-banner-path-0')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, isEmpty);

      final history = <List<String>>[];
      void record() => history.add(List.of(LayoutSelection.path.value));
      LayoutSelection.path.addListener(record);
      addTearDown(() => LayoutSelection.path.removeListener(record));

      final actionPoint = tester.getCenter(find.text('Action'));
      await tester.tapAt(actionPoint);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Main', 'Centre']);

      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(actionPoint);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(actionPoint);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Main', 'Centre', 'Ma Carte']);

      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(actionPoint);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(actionPoint);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, [
        'Main',
        'Centre',
        'Ma Carte',
        'Mon Bouton',
      ]);
      // Subsequent single click or double click on the deepest selected
      // component keeps it selected without flickering back to the zone.
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(actionPoint);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, [
        'Main',
        'Centre',
        'Ma Carte',
        'Mon Bouton',
      ]);
      expect(history, [
        ['Main', 'Centre'],
        ['Main', 'Centre', 'Ma Carte'],
        ['Main', 'Centre', 'Ma Carte', 'Mon Bouton'],
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clicking a path chevron opens the complete children tree dialog near the chevron and selects any descendant',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      await pump(
        tester,
        mode,
        Stack(
          children: [
            Positioned.fill(
              child: SuperLayout(
                name: 'Main',
                config: config.copyWith(
                  placements: {
                    SuperLayoutZone.center: ['card-slot'],
                  },
                ),
                slots: [
                  BuilderSlot(
                    id: 'card-slot',
                    label: 'Ma Carte',
                    builder: (_) => EditableSurface(
                      id: 'card-slot',
                      label: 'Ma Carte',
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: SizedBox(
                          width: 120,
                          height: 48,
                          child: EditorSlot(
                            label: 'Mon Bouton',
                            onEdit: () async {},
                            child: const Center(child: Text('Action')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Positioned.fill(child: StyleEditBanner()),
          ],
        ),
      );

      // Select 'Main > Centre' with a single click.
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Main', 'Centre']);

      // Click chevron 0 (between 'Main' and 'Centre') to open the full children tree of 'Main'.
      final chevron0 = find.byKey(const ValueKey('style-edit-banner-chevron-0'));
      expect(chevron0, findsOneWidget);
      final chevronRect = tester.getRect(chevron0);
      await tester.tap(chevron0);
      await tester.pumpAndSettle();

      final dialog = find.byKey(const ValueKey('style-edit-banner-tree-dialog'));
      expect(dialog, findsOneWidget);
      final dialogRect = tester.getRect(dialog);
      // Positioned right below and aligned with the clicked chevron.
      expect(dialogRect.top, closeTo(chevronRect.bottom + 6, 2));
      expect(dialogRect.left, closeTo(chevronRect.left, 2));

      // Complete tree of 'Main' is displayed: zones, Card slot, and inner button.
      final nordNode = find.byKey(
        const ValueKey('style-edit-banner-tree-node-Main/Nord'),
      );
      final centreNode = find.byKey(
        const ValueKey('style-edit-banner-tree-node-Main/Centre'),
      );
      final cardNode = find.byKey(
        const ValueKey('style-edit-banner-tree-node-Main/Centre/Ma Carte'),
      );
      final buttonNode = find.byKey(
        const ValueKey(
          'style-edit-banner-tree-node-Main/Centre/Ma Carte/Mon Bouton',
        ),
      );
      expect(nordNode, findsOneWidget);
      expect(centreNode, findsOneWidget);
      expect(cardNode, findsOneWidget);
      expect(buttonNode, findsOneWidget);

      // Select the deepest descendant ('Mon Bouton') directly from the tree dialog.
      await tester.tap(buttonNode);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(LayoutSelection.path.value, [
        'Main',
        'Centre',
        'Ma Carte',
        'Mon Bouton',
      ]);

      // Click chevron 2 (after 'Ma Carte') while 'Mon Bouton' is selected to open 'Ma Carte' subtree.
      final chevron2 = find.byKey(const ValueKey('style-edit-banner-chevron-2'));
      expect(chevron2, findsOneWidget);
      await tester.tap(chevron2);
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(buttonNode, findsOneWidget);
      expect(cardNode, findsNothing);

      // Click chevron 1 (after 'Centre') to open the subtree under 'Main > Centre'.
      final chevron1 = find.byKey(const ValueKey('style-edit-banner-chevron-1'));
      await tester.tap(chevron1);
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(nordNode, findsNothing);
      expect(cardNode, findsOneWidget);
      expect(buttonNode, findsOneWidget);

      // Select 'Ma Carte' from the subtree dialog.
      await tester.tap(cardNode);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(LayoutSelection.path.value, ['Main', 'Centre', 'Ma Carte']);

      // Selecting 'Nord' via chevron 0 switches zone.
      await tester.tap(chevron0);
      await tester.pumpAndSettle();
      await tester.tap(nordNode);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Main', 'Nord']);
      expect(tester.takeException(), isNull);
    },
  );
}
