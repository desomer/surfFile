import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  testWidgets(
    'content clicks select slots only in the already selected layout',
    (tester) async {
      final mode = ValueNotifier(false);
      addTearDown(mode.dispose);
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: mode,
            child: Scaffold(
              body: SuperLayout(
                label: 'Content selection',
                config: const SuperLayoutConfig(
                  north: false,
                  south: false,
                  west: false,
                  east: false,
                  placements: {
                    SuperLayoutZone.center: ['first', 'second'],
                  },
                ),
                slots: [
                  BuilderSlot(
                    id: 'first',
                    label: 'First',
                    builder: (_) => Center(
                      child: FilledButton(
                        key: const ValueKey('component-button'),
                        onPressed: () => presses++,
                        child: const Text('Action'),
                      ),
                    ),
                  ),
                  BuilderSlot(
                    id: 'second',
                    label: 'Second',
                    builder: (_) => const ColoredBox(color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('slot-first'));
      final second = find.byKey(const ValueKey('slot-second'));
      final handle = find.byKey(const ValueKey('slot-resize-first-se'));
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(handle, findsNothing);
      mode.value = true;
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, ['Content selection']);
      expect(handle, findsNothing);
      await tester.tap(find.byKey(const ValueKey('component-button')));
      await tester.pumpAndSettle();
      expect(presses, 3);
      expect(LayoutSelection.path.value.last, 'First');
      expect(handle, findsOneWidget);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.last, 'First');
      await tester.drag(second, const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.last, 'First');
      await tester.tap(second, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.last, SuperLayoutZone.center.label);
      await tester.tapAt(const Offset(10, 590));
      await tester.pumpAndSettle();
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.last, 'Second');
      await tester.tap(find.byKey(const ValueKey('slot-label-select-second')));
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value.last, SuperLayoutZone.center.label);
      mode.value = false;
      await tester.pumpAndSettle();
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(LayoutSelection.path.value, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
