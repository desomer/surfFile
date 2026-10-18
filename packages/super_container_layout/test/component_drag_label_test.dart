import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
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
    expect(tester.takeException(), isNull);
  });
}
