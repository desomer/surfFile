import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/editing/overlay/editor_resize_handle.dart';

void main() {
  for (final (name, direction) in editorResizeDirections) {
    testWidgets('$name uses a small rectangle and keeps its drag target', (
      tester,
    ) async {
      var starts = 0;
      var updates = 0;
      var ends = 0;
      final key = ValueKey(name);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EditorResizeHandle(
                key: key,
                direction: direction,
                label: 'Component',
                onStart: (_) => starts++,
                onUpdate: (_) => updates++,
                onEnd: () => ends++,
              ),
            ),
          ),
        ),
      );
      final handle = find.byKey(key);
      final grip = find.descendant(
        of: handle,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints?.maxWidth == 8 &&
              widget.constraints?.maxHeight == 8,
        ),
      );
      expect(tester.getSize(handle), const Size(32, 32));
      expect(tester.getSize(grip), const Size(8, 8));
      expect(
        find.descendant(of: handle, matching: find.byType(Icon)),
        findsNothing,
      );
      final decoration =
          tester.widget<Container>(grip).decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.border!.top.width, 1);
      final bounds = tester.getRect(handle);
      final rect = tester.getRect(grip);
      expect(
        rect.center,
        bounds.center + Offset(direction.x * 12, direction.y * 12),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(rect.center);
      await tester.pumpAndSettle();
      final hovered =
          tester.widget<Container>(grip).decoration! as BoxDecoration;
      expect(hovered.color, isNot(decoration.color));
      await mouse.removePointer();
      await tester.pumpAndSettle();
      await tester.dragFrom(bounds.center, const Offset(45, 35));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(updates, greaterThan(0));
      expect(ends, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
