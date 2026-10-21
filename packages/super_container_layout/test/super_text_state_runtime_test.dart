import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    SuperTextConfig config, {
    bool selected = false,
    TextEditingController? controller,
    ValueChanged<String>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 100,
              child: JsonListScope(
                repositoryId: null,
                indices: const [0],
                selected: selected,
                child: SuperText(
                  id: 'state',
                  config: config,
                  controller: controller,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'hover and row selection resolve all Text properties and reset on transitions only',
    (tester) async {
      final changes = <String>[];
      final config = SuperTextConfig(
        mode: SuperTextMode.input,
        initialText: 'Default',
        states: TextConfigStates(
          hover: TextConfigOverride(
            config: const SuperTextConfig(fontSize: 24),
            properties: {TextStateProperty.fontSize},
          ),
        ),
      );
      await mount(tester, config, onChanged: changes.add);
      final field = find.byKey(const ValueKey('super-text-input-state'));
      await tester.enterText(field, 'Draft');
      await tester.pumpAndSettle();
      final count = changes.length;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(field));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).style!.fontSize, 24);
      expect(tester.widget<TextField>(field).controller!.text, 'Default');
      expect(changes, hasLength(count));
      await tester.enterText(field, 'Hovered draft');
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(field) + const Offset(1, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Hovered draft');
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Default');
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('controller ownership survives hover and nested row selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'External');
    addTearDown(controller.dispose);
    final config = SuperTextConfig(
      states: TextConfigStates(
        hover: TextConfigOverride(
          config: const SuperTextConfig(fontSize: 24),
          properties: {TextStateProperty.fontSize},
        ),
        selected: TextConfigOverride(
          config: const SuperTextConfig(color: Colors.red),
          properties: {TextStateProperty.color},
        ),
      ),
    );
    await mount(tester, config, selected: true, controller: controller);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('External')));
    await tester.pumpAndSettle();
    expect(controller.text, 'External');
    final text = tester.widget<Text>(
      find.byKey(const ValueKey('super-text-display-state')),
    );
    expect(text.style!.fontSize, 24);
    expect(text.style!.color!.toARGB32(), Colors.red.toARGB32());
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });
}
