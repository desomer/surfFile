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
                child: SuperContainer(
                  label: 'Parent style',
                  child: SizedBox(
                    width: 500,
                    height: 300,
                    child: Center(
                      child: SuperContainer(
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
          (widget) => widget is SuperContainer && widget.label == label,
        );
        final paints = tester.widgetList<CustomPaint>(
          find.descendant(of: container, matching: find.byType(CustomPaint)),
        );
        return paints.first.foregroundPainter != null;
      }

      await tester.tap(find.text('Target'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('style-menu-Child style'))),
      );
      await tester.pump();
      expect(highlighted('Child style'), isTrue);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('style-menu-Parent style'))),
      );
      await tester.pump();
      expect(highlighted('Child style'), isFalse);
      expect(highlighted('Parent style'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(highlighted('Child style'), isFalse);
      expect(highlighted('Parent style'), isFalse);
    },
  );
}
