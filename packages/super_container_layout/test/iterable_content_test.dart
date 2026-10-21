import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_single_child.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    ContainerStyle style = const ContainerStyle(),
    ValueChanged<ContainerStyle>? onStyleChanged,
  }) async {
    final editing = ValueNotifier(true);
    addTearDown(editing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: editing,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 500,
                height: 400,
                child: IterableContent(
                  style: style,
                  onStyleChanged: onStyleChanged,
                  config: const SuperLayoutConfig(
                    north: false,
                    south: false,
                    west: false,
                    east: false,
                    placements: {
                      SuperLayoutZone.center: ['text'],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'text',
                      label: 'Text',
                      builder: (_) => const Text('Target'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('IterableContent starts transparent with a structural layout', (
    tester,
  ) async {
    await mount(tester);
    final surface = tester.widget<SuperContainer>(find.byType(SuperContainer));
    expect(surface.fallbackColor, Colors.transparent);
    expect(surface.style.color, isNull);
    expect(surface.style.outerMargin, EdgeInsets.zero);
    expect(surface.style.contentPadding, EdgeInsets.zero);
    expect(surface.style.elevation, 0);
    expect(surface.style.borderWidth, 0);
    expect(find.byType(SuperLayout), findsOneWidget);
    expect(find.byType(EditableSingleChild), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'IterableContent applies Card styling and keeps layout controls separate',
    (tester) async {
      const style = ContainerStyle(
        color: Colors.red,
        borderWidth: 2,
        radius: 12,
        padding: 10,
        margin: 8,
        elevation: 3,
      );
      await mount(tester, style: style);
      final surface = tester.widget<SuperContainer>(
        find.byType(SuperContainer),
      );
      expect(surface.style.color, Colors.red);
      expect(surface.style.radius, 12);
      expect(surface.style.contentPadding, const EdgeInsets.all(10));
      expect(surface.style.elevation, 3);
      await tester.tap(find.text('Target'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      for (final label in ['IterableContent', 'Layout']) {
        expect(find.byKey(ValueKey('style-menu-$label')), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('style-menu-add-IterableContent')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('style-menu-add-Layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('style-menu-remove-child-IterableContent')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling IterableContent style editing restores its style', (
    tester,
  ) async {
    final changes = <ContainerStyle>[];
    await mount(tester, onStyleChanged: changes.add);
    final state = tester.state<EditableSurfaceState>(
      find.byType(EditableSurface),
    );
    final dialog = state.openEditor();
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Slider &&
            widget.key == const ValueKey('padding-IterableContent'),
      ),
    );
    slider.onChanged!(12);
    await tester.pumpAndSettle();
    expect(changes.last.padding, 12);
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    await dialog;
    expect(changes.last.padding, 0);
    expect(tester.takeException(), isNull);
  });
}
