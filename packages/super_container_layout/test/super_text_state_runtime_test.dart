import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    SuperTextConfig config, {
    bool selected = false,
    bool outerSelected = false,
    TextEditingController? controller,
    String? value,
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
                indices: const [],
                selected: outerSelected,
                child: JsonListScope(
                  repositoryId: null,
                  indices: const [0],
                  selected: selected,
                  child: SuperText(
                    id: 'state',
                    config: config,
                    controller: controller,
                    value: value,
                    onChanged: onChanged,
                  ),
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

  testWidgets(
    'nearest row shadows selection and persisted priority changes the winner',
    (tester) async {
      final config = SuperTextConfig(
        initialText: 'Text',
        states: TextConfigStates(
          hover: TextConfigOverride(
            config: const SuperTextConfig(color: Colors.blue),
            properties: {TextStateProperty.color},
          ),
          selected: TextConfigOverride(
            config: const SuperTextConfig(color: Colors.red),
            properties: {TextStateProperty.color},
          ),
        ),
      );
      final display = find.byKey(const ValueKey('super-text-display-state'));
      await mount(tester, config, outerSelected: true);
      expect(
        tester.widget<Text>(display).style!.color!.toARGB32(),
        isNot(Colors.red.toARGB32()),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(display));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(display).style!.color!.toARGB32(),
        Colors.blue.toARGB32(),
      );
      await mount(tester, config, selected: true);
      expect(
        tester.widget<Text>(display).style!.color!.toARGB32(),
        Colors.red.toARGB32(),
      );
      await mount(
        tester,
        config.copyWith(
          states: config.states!.copyWith(
            order: [TextConfigStates.selectedKey, TextConfigStates.hoverKey],
          ),
        ),
        selected: true,
      );
      expect(
        tester.widget<Text>(display).style!.color!.toARGB32(),
        Colors.blue.toARGB32(),
      );
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'effective content edits and removing states reset without artificial changes',
    (tester) async {
      final changes = <String>[];
      final config = SuperTextConfig(
        mode: SuperTextMode.input,
        initialText: 'First',
        states: TextConfigStates(),
      );
      final field = find.byKey(const ValueKey('super-text-input-state'));
      await mount(tester, config, onChanged: changes.add);
      await tester.enterText(field, 'Draft');
      await tester.pumpAndSettle();
      final count = changes.length;
      await mount(
        tester,
        config.copyWith(initialText: 'Second'),
        onChanged: changes.add,
      );
      expect(tester.widget<TextField>(field).controller!.text, 'Second');
      expect(changes, hasLength(count));
      await tester.enterText(field, 'Other draft');
      await tester.pumpAndSettle();
      final nextCount = changes.length;
      await mount(
        tester,
        config.copyWith(clearStates: true),
        onChanged: changes.add,
      );
      expect(tester.widget<TextField>(field).controller!.text, 'First');
      expect(changes, hasLength(nextCount));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'controlled value is not reset on hover or selection transitions',
    (tester) async {
      final changes = <String>[];
      final config = SuperTextConfig(
        mode: SuperTextMode.input,
        states: TextConfigStates(
          hover: TextConfigOverride(
            config: const SuperTextConfig(
              mode: SuperTextMode.input,
              initialText: 'Hovered',
            ),
            properties: {TextStateProperty.content},
          ),
        ),
      );
      await mount(tester, config, value: 'Owned', onChanged: changes.add);
      final field = find.byKey(const ValueKey('super-text-input-state'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(field));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Owned');
      expect(changes, isEmpty);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );
}
