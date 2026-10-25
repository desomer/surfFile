import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/overlay/editor_zoom.dart';

void main() {
  testWidgets('Windows drag label uses supported native cursors', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final dragging = ValueNotifier(false);
    addTearDown(dragging.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: dragging,
              builder: (_, active, _) => ComponentDragLabel(
                draggable: true,
                dragging: active,
                child: const Text('Windows drag'),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Windows drag')));
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
    dragging.value = true;
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.move,
    );
    await mouse.removePointer();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
    'portaled component label exposes grab cursor above nested content',
    (tester) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: mode,
            child: Scaffold(
              body: EditorZoom(
                child: SuperLayout(
                  name: 'Root',
                  config: const SuperLayoutConfig(
                    north: false,
                    south: false,
                    east: false,
                    west: false,
                    placements: {
                      SuperLayoutZone.center: ['child'],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'child',
                      label: 'Child',
                      builder: (_) => const EditableSurface(
                        label: 'Nested surface',
                        child: SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(600, 400));
      await tester.pumpAndSettle();
      final label = find.byKey(const ValueKey('slot-label-child'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(label));
      await tester.pumpAndSettle();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.grab,
      );
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('hover highlights only component labels in the same zone', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StyleEditScope(
            controller: mode,
            child: SuperLayout(
              config: const SuperLayoutConfig(
                north: true,
                south: false,
                west: false,
                east: false,
                autoSides: {},
                placements: {
                  SuperLayoutZone.north: ['a', 'b'],
                  SuperLayoutZone.center: ['c'],
                },
              ),
              slots: [
                for (final id in ['a', 'b', 'c'])
                  BuilderSlot(
                    id: id,
                    label: 'Component $id',
                    sizing: SlotSizing.fill,
                    builder: (_) => const SizedBox.expand(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    Finder label(String id) => find.byKey(ValueKey('slot-label-$id'));
    Color? background(String id) => tester
        .widget<Material>(
          find.descendant(of: label(id), matching: find.byType(Material)).first,
        )
        .color;
    final bounds = {
      for (final id in ['a', 'b', 'c']) id: tester.getRect(label(id)),
    };
    final colors = {
      for (final id in ['a', 'b', 'c']) id: background(id),
    };
    final highlight = Theme.of(tester.element(label('a'))).colorScheme.tertiary;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(790, 590));
    for (final hovered in ['a', 'b', 'c']) {
      await mouse.moveTo(bounds[hovered]!.center);
      await tester.pumpAndSettle();
      for (final id in ['a', 'b', 'c']) {
        expect(
          background(id),
          (id == 'c') == (hovered == 'c') ? highlight : colors[id],
        );
        expect(tester.getRect(label(id)), bounds[id]);
      }
    }
    await mouse.moveTo(const Offset(790, 590));
    await tester.pumpAndSettle();
    for (final id in ['a', 'b', 'c']) {
      expect(background(id), colors[id]);
    }
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  for (final editable in [true, false]) {
    testWidgets('zone drag icons match draggable zones (editable=$editable)', (
      tester,
    ) async {
      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StyleEditScope(
              controller: mode,
              child: SuperLayout(
                editable: editable,
                config: const SuperLayoutConfig(
                  north: true,
                  south: true,
                  west: true,
                  east: true,
                  autoSides: {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      final draggables = tester
          .widgetList<Draggable<SuperLayoutZone>>(
            find.byType(Draggable<SuperLayoutZone>),
          )
          .map((widget) => widget.data)
          .toSet();
      for (final zone in SuperLayoutZone.values) {
        final icon = find.byKey(
          ValueKey('super-layout-zone-drag-${zone.name}'),
        );
        expect(icon, draggables.contains(zone) ? findsOneWidget : findsNothing);
      }
      expect(
        find.byKey(const ValueKey('super-layout-zone-drag-center')),
        findsNothing,
      );
      if (editable) {
        expect(
          draggables,
          containsAll([
            SuperLayoutZone.north,
            SuperLayoutZone.south,
            SuperLayoutZone.west,
            SuperLayoutZone.east,
          ]),
        );
      } else {
        expect(draggables, isEmpty);
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(790, 590));
      await mouse.moveTo(
        tester.getCenter(
          find.descendant(
            of: find.byKey(const ValueKey('super-layout-add-overlay-north')),
            matching: find.text('Nord'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        editable ? SystemMouseCursors.grab : SystemMouseCursors.click,
      );
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('zone component label uses the shared grid badge and drag icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: SlotStack(
              showLabels: true,
              mover: SlotMover(
                owner: Object(),
                onMove: (_, {beforeId, afterId}) {},
              ),
              slots: [
                BuilderSlot(
                  id: 'a',
                  label: 'Component A',
                  builder: (_) => const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final label = find.byKey(const ValueKey('slot-label-a'));
    expect(tester.widget(label), isA<ComponentDragLabel>());
    expect(
      find.descendant(of: label, matching: find.byIcon(Icons.drag_indicator)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: label, matching: find.text('Component A')),
      findsOneWidget,
    );
    final material = tester.widget<Material>(
      find.descendant(of: label, matching: find.byType(Material)).first,
    );
    expect(material.borderRadius, BorderRadius.circular(6));
    expect(
      material.color,
      Theme.of(tester.element(label)).colorScheme.tertiaryContainer
          .withValues(alpha: tester.widget<ComponentDragLabel>(label).opacity),
    );
    final bounds = tester.getRect(label);
    expect(bounds.topRight, const Offset(316, 4));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(bounds.center);
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grab,
    );
    final hovered = tester.widget<Material>(
      find.descendant(of: label, matching: find.byType(Material)).first,
    );
    expect(hovered.color, Theme.of(tester.element(label)).colorScheme.tertiary);
    expect(tester.getRect(label), bounds);
    expect(
      find.ancestor(of: label, matching: find.byType(EmphasizedLabel)),
      findsNothing,
    );
    await mouse.moveTo(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(tester.widget<ComponentDragLabel>(label).highlighted, isFalse);
    expect(tester.getRect(label), bounds);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  for (final draggable in [true, false]) {
    testWidgets(
      'component grip stays visible in narrow labels (draggable=$draggable)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 80,
                  child: ComponentDragLabel(
                    draggable: draggable,
                    child: const Text('Long component label'),
                  ),
                ),
              ),
            ),
          ),
        );
        final icon = find.byIcon(Icons.drag_indicator);
        expect(icon, draggable ? findsOneWidget : findsNothing);
        if (draggable) expect(tester.getSize(icon), const Size(12, 12));
        expect(
          DefaultTextStyle.of(tester.element(find.text('Long component label')))
              .style
              .fontSize,
          10,
        );
        expect(find.text('Long component label'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('movable label uses grab and grabbing mouse cursors', (
    tester,
  ) async {
    final dragging = ValueNotifier(false);
    addTearDown(dragging.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: dragging,
              builder: (context, active, _) => ComponentDragLabel(
                draggable: true,
                dragging: active,
                child: const Text('Move me'),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Move me')));
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grab,
    );
    dragging.value = true;
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grabbing,
    );
    dragging.value = false;
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grab,
    );
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });
}
