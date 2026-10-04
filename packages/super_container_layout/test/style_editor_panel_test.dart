import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/super_container.dart';

void main() {
  Future<void> openEditor(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SuperContainer(
              child: SizedBox(width: 120, height: 60, child: Text('Box')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Box'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuItem<SuperContainerState>).first);
    await tester.pumpAndSettle();
  }

  testWidgets('wide editor shows the property list, cards and preview', (
    tester,
  ) async {
    await openEditor(tester, const Size(1400, 1000));
    expect(find.text('PROPRIÉTÉS'), findsOneWidget);
    expect(find.byKey(const ValueKey('style-preview')), findsOneWidget);
    for (final id in ['design', 'fill', 'radius', 'border', 'shadow']) {
      expect(find.byKey(ValueKey('style-nav-$id')), findsOneWidget);
      expect(find.byKey(ValueKey('style-card-$id')), findsOneWidget);
    }
    // Marges et bordure/rayon partagent une ligne.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('style-card-margin'))).dy,
      tester.getTopLeft(find.byKey(const ValueKey('style-card-padding'))).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a property scrolls to its card', (tester) async {
    await openEditor(tester, const Size(1400, 1000));
    final card = find.byKey(const ValueKey('style-card-interaction'));
    final before = tester.getTopLeft(card).dy;
    await tester.tap(find.byKey(const ValueKey('style-nav-interaction')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card).dy, lessThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview can show the margin and padding zones', (tester) async {
    await openEditor(tester, const Size(1400, 1000));
    expect(find.text('Afficher les espacements'), findsOneWidget);
    final height = tester
        .getSize(find.byKey(const ValueKey('preview-Super container')))
        .height;
    await tester.tap(find.byKey(const ValueKey('preview-spacing')));
    await tester.pumpAndSettle();
    expect(find.text('Masquer les espacements'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('preview-Super container')))
          .height,
      isNot(height),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow editor falls back to chips with the preview on top', (
    tester,
  ) async {
    await openEditor(tester, const Size(800, 700));
    expect(find.text('PROPRIÉTÉS'), findsNothing);
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.byKey(const ValueKey('style-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
