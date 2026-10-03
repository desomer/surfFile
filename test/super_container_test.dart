import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/theme/container_style.dart';
import 'package:surf_file/widgets/container_style_editor.dart';
import 'package:surf_file/widgets/super_container.dart';

void main() {
  Future<List<ContainerStyle>> pump(WidgetTester tester) async {
    final changes = <ContainerStyle>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SuperContainer(
            style: const ContainerStyle(radius: 4),
            onStyleChanged: changes.add,
            child: const SizedBox(width: 120, height: 60, child: Text('Box')),
          ),
        ),
      ),
    ));
    return changes;
  }

  ContainerStyle current(WidgetTester tester) => tester
      .state<SuperContainerState>(find.byType(SuperContainer))
      .style;

  Future<void> setRadius(WidgetTester tester, double value) async {
    final slider = tester.widget<Slider>(find
        .descendant(
            of: find.byType(ContainerStyleEditor), matching: find.byType(Slider))
        .first);
    slider.onChanged!(value);
    await tester.pump();
  }

  testWidgets('long press opens the editor and applies styles live',
      (tester) async {
    final changes = await pump(tester);
    expect(find.byType(ContainerStyleEditor), findsNothing);

    await tester.longPress(find.text('Box'));
    await tester.pumpAndSettle();
    expect(find.byType(ContainerStyleEditor), findsOneWidget);

    await setRadius(tester, 20);
    expect(current(tester).radius, 20);
    expect(changes.last.radius, 20);

    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(find.byType(ContainerStyleEditor), findsNothing);
    expect(current(tester).radius, 20);
  });

  testWidgets('cancel restores the previous style', (tester) async {
    final changes = await pump(tester);
    await tester.longPress(find.text('Box'));
    await tester.pumpAndSettle();
    await setRadius(tester, 30);
    expect(current(tester).radius, 30);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(current(tester).radius, 4);
    expect(changes.last.radius, 4);
  });

  testWidgets('long press does nothing when not editable', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SuperContainer(
            editable: false,
            child: SizedBox(width: 120, height: 60, child: Text('Box')),
          ),
        ),
      ),
    ));
    await tester.longPress(find.text('Box'));
    await tester.pumpAndSettle();
    expect(find.byType(ContainerStyleEditor), findsNothing);
  });
}
