import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/widgets/interaction/mouse_back_navigation.dart';

void main() {
  testWidgets('forward acts on press and never triggers back', (tester) async {
    var back = 0;
    var forward = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: MouseBackNavigation(
                  enabled: true,
                  forwardEnabled: true,
                  onBack: () => back++,
                  onForward: () => forward++,
                  child: const SizedBox.expand(),
                ),
              )),
    ));
    final gesture = await tester.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.mouse,
      buttons: kForwardMouseButton,
    );
    expect(forward, 1);
    expect(back, 0);
    await gesture.up();
    expect(forward, 1);
  });

  testWidgets('mouse back acts on press over children or empty space',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: MouseBackNavigation(
                  enabled: true,
                  onBack: () => calls++,
                  child: Column(children: [
                    TextButton(onPressed: () {}, child: const Text('Child')),
                    const Expanded(child: SizedBox.expand()),
                  ]),
                ),
              )),
    ));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Child')),
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    expect(calls, 1);
    await gesture.up();
    expect(calls, 1);
    final blank = await tester.startGesture(
      const Offset(300, 300),
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    expect(calls, 2);
    await blank.up();
  });

  testWidgets('disabled navigation and unrelated buttons do nothing',
      (tester) async {
    var calls = 0;
    Future<void> show(bool enabled) => tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: MouseBackNavigation(
                      enabled: enabled,
                      onBack: () => calls++,
                      child: const SizedBox.expand(),
                    ),
                  )),
        ));
    await show(false);
    Future<void> press(int buttons) async {
      final gesture = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.mouse,
        buttons: buttons,
      );
      await gesture.up();
    }

    await press(kBackMouseButton);
    await show(true);
    for (final buttons in [
      kPrimaryMouseButton,
      kSecondaryMouseButton,
      kMiddleMouseButton,
      kForwardMouseButton,
      kBackMouseButton | kPrimaryMouseButton,
    ]) {
      await press(buttons);
    }
    expect(calls, 0);
  });

  testWidgets('back does not navigate underneath an open dialog',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: MouseBackNavigation(
                  enabled: true,
                  onBack: () => calls++,
                  child: SizedBox.expand(
                      child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierColor: Colors.transparent,
                      builder: (_) =>
                          const AlertDialog(content: Text('Dialog')),
                    ),
                    child: const Text('Open'),
                  )),
                ),
              )),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      const Offset(20, 20),
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await gesture.up();
    expect(calls, 0);
    expect(find.text('Dialog'), findsOneWidget);
  });
}
