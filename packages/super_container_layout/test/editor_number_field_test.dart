import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  Future<void> open(WidgetTester tester, [Finder? badge]) async {
    await tester.tap(badge ?? find.byType(EditorNumberField));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  }

  Future<void> enter(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField), value);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'only clicking a badge opens the popup; Enter and blur commit once',
    (tester) async {
      var value = 2.0;
      final changes = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 300,
                child: EditorHistorySlider(
                  value: value,
                  min: -10,
                  max: 10,
                  onChanged: (next) => setState(() {
                    changes.add(next);
                    value = next;
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('2.00'), findsOneWidget);
      await open(tester);
      await tester.enterText(find.byType(TextField), '3,456');
      expect(changes, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(value, 3.46);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('3.46'), findsOneWidget);
      expect(changes, [3.46]);
      await open(tester);
      await tester.enterText(find.byType(TextField), '-1.25');
      await tester.tapAt(const Offset(10, 300));
      await tester.pumpAndSettle();
      expect(value, -1.25);
      expect(changes, [3.46, -1.25]);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(4.567);
      await tester.pump();
      expect(value, 4.57);
      expect(find.text('4.57'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid or structurally out of range values keep the popup open',
    (tester) async {
      final changes = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EditorNumberField(
                value: .5,
                min: 0,
                max: 1,
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      );
      await open(tester);
      for (final text in ['', 'oops', 'NaN', 'Infinity', '-1', '1.001']) {
        await enter(tester, text);
        expect(
          tester
              .widget<TextField>(find.byType(TextField))
              .decoration!
              .errorText,
          isNotNull,
          reason: text,
        );
        expect(changes, isEmpty);
      }
      await enter(tester, '0,99');
      expect(changes, [.99]);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('Escape cancels without changing the value', (tester) async {
    final changes = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorNumberField(
            value: 3,
            min: 0,
            max: 10,
            onChanged: changes.add,
          ),
        ),
      ),
    );
    await open(tester);
    await tester.enterText(find.byType(TextField), '7');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('integer percentage input preserves a two decimal ratio', (
    tester,
  ) async {
    var value = .5;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => EditorHistorySlider(
              value: value,
              valueScale: 100,
              integer: true,
              unit: '%',
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    expect(find.text('50 %'), findsOneWidget);
    await open(tester);
    await enter(tester, '12,34');
    expect(value, .5);
    expect(find.text('Entier requis'), findsOneWidget);
    await enter(tester, '12');
    expect(value, .12);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(.45678);
    await tester.pump();
    expect(value, .46);
    expect(find.text('46 %'), findsOneWidget);
  });

  testWidgets(
    'extensible sizes above 10x max persist without expanding the slider',
    (tester) async {
      var style = const ContainerStyle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 300,
                child: StyleSliderField(
                  label: 'Rayon',
                  value: style.radius,
                  min: 0,
                  max: 36,
                  onChanged: (next) =>
                      setState(() => style = style.copyWith(radius: next)),
                ),
              ),
            ),
          ),
        ),
      );
      await open(tester);
      await enter(tester, '1000,1234');
      expect(style.radius, 1000.12);
      expect(find.text('1000.12 dp'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.max, 36);
      expect(slider.value, 36);
      final restored = AppearanceStore.decode(
        AppearanceStore.encode(Appearance(styles: {'card': style})),
      );
      expect(restored.style('card').radius, 1000.12);
      await open(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '1000.12',
      );
      await enter(tester, '24.5');
      expect(style.radius, 24.5);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 24.5);
    },
  );

  testWidgets(
    'integer parameters reject decimals and disabled badges do not edit',
    (tester) async {
      final changes = <double>[];
      Future<void> mount(ValueChanged<double>? callback) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorNumberField(
              value: 3,
              min: 1,
              max: 8,
              integer: true,
              onChanged: callback,
            ),
          ),
        ),
      );
      await mount(changes.add);
      await open(tester);
      await enter(tester, '3.5');
      expect(changes, isEmpty);
      expect(find.text('Entier requis'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await mount(null);
      await tester.tap(find.byType(EditorNumberField));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('popup edits and slider drags retain atomic undo redo', (
    tester,
  ) async {
    final appearance = ValueNotifier<Appearance>(Appearance());
    final editing = ValueNotifier(true);
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: editing,
    );
    addTearDown(appearance.dispose);
    addTearDown(editing.dispose);
    addTearDown(history.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorHistoryScope(
            controller: history,
            child: ValueListenableBuilder<Appearance>(
              valueListenable: appearance,
              builder: (context, current, _) => EditorHistorySlider(
                value: current.backgroundOpacity,
                onChanged: (value) => appearance.value = appearance.value
                    .copyWith(backgroundOpacity: value),
              ),
            ),
          ),
        ),
      ),
    );
    await open(tester);
    await enter(tester, '0,75');
    history.undo();
    await tester.pump();
    expect(appearance.value.backgroundOpacity, 1);
    expect(history.canUndo, isFalse);
    expect(find.text('1.00'), findsOneWidget);
    history.redo();
    await tester.pump();
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(.75);
    slider.onChanged!(.6);
    slider.onChanged!(.4);
    slider.onChangeEnd!(.4);
    await tester.pump();
    history.undo();
    await tester.pump();
    expect(appearance.value.backgroundOpacity, .75);
    expect(find.text('0.75'), findsOneWidget);
  });
}
