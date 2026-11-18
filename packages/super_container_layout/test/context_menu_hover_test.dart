import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  testWidgets(
    'hovering menu rows highlights their target and clears on close',
    (tester) async {
      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: editing,
            child: Scaffold(
              body: Center(
                child: EditableSurface(
                  label: 'Parent style',
                  child: SizedBox(
                    width: 500,
                    height: 300,
                    child: Center(
                      child: EditableSurface(
                        label: 'Child style',
                        child: const SizedBox(
                          width: 120,
                          height: 80,
                          child: Text('Target'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      bool highlighted(String label) {
        final container = find.byWidgetPredicate(
          (widget) => widget is EditableSurface && widget.label == label,
        );
        final paints = tester.widgetList<CustomPaint>(
          find.descendant(of: container, matching: find.byType(CustomPaint)),
        );
        return paints.any(
          (paint) => paint.foregroundPainter is EditorSelectionOutline,
        );
      }

      await tester.tap(find.text('Target'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('style-menu-Child style'))),
      );
      await tester.pumpAndSettle();
      expect(highlighted('Child style'), isTrue);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('style-menu-Parent style'))),
      );
      await tester.pumpAndSettle();
      expect(EditorSlotState.highlightedTarget.value?.label, 'Parent style');
      expect(highlighted('Child style'), isFalse);
      expect(highlighted('Parent style'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(highlighted('Child style'), isFalse);
      expect(highlighted('Parent style'), isFalse);
    },
  );

  testWidgets(
    'hovering sibling EditorSlots isolates repaints with RepaintBoundary and avoids rebuilding children',
    (tester) async {
      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);
      var buildsA = 0;
      var buildsB = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: editing,
            child: Scaffold(
              body: Column(
                children: [
                  EditorSlot(
                    id: 'slot-a',
                    label: 'Slot A',
                    child: Builder(
                      builder: (_) {
                        buildsA++;
                        return const SizedBox(
                          key: ValueKey('slot-a-content'),
                          width: 120,
                          height: 60,
                          child: Text('Alpha'),
                        );
                      },
                    ),
                  ),
                  EditorSlot(
                    id: 'slot-b',
                    label: 'Slot B',
                    child: Builder(
                      builder: (_) {
                        buildsB++;
                        return const SizedBox(
                          key: ValueKey('slot-b-content'),
                          width: 120,
                          height: 60,
                          child: Text('Beta'),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final slotAFinder = find.byWidgetPredicate(
        (w) => w is EditorSlot && w.id == 'slot-a',
      );
      final slotAContent = find.byKey(const ValueKey('slot-a-content'));
      final customPaintA = find.descendant(
        of: slotAFinder,
        matching: find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              tester
                  .widgetList<Widget>(
                    find.descendant(
                      of: find.byWidget(w),
                      matching: slotAContent,
                    ),
                  )
                  .isNotEmpty,
        ),
      );
      expect(customPaintA, findsOneWidget);
      // An outer RepaintBoundary isolates the foreground CustomPaint from ancestors/siblings,
      // and an inner RepaintBoundary isolates the slot content below it.
      expect(
        find.ancestor(
          of: customPaintA,
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: customPaintA,
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );

      final initialBuildsA = buildsA;
      final initialBuildsB = buildsB;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(find.text('Alpha')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CustomPaint>(customPaintA).foregroundPainter,
        isA<EditorSelectionOutline>(),
      );

      await mouse.moveTo(tester.getCenter(find.text('Beta')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CustomPaint>(customPaintA).foregroundPainter,
        isNull,
      );

      expect(buildsA, initialBuildsA);
      expect(buildsB, initialBuildsB);
    },
  );
}
