import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';
import 'package:super_container_layout/widgets/editing/styles/style_editor_panel.dart';

void main() {
  setUp(() => StyleEditorPanel.preferredDense = false);
  tearDown(() => StyleEditorPanel.preferredDense = false);

  Future<void> openEditor(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: EditableSurface(
              child: SizedBox(width: 120, height: 60, child: Text('Box')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Box'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuItem<EditorSlotState>).first);
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
        .getSize(find.byKey(const ValueKey('preview-Card')))
        .height;
    await tester.tap(find.byKey(const ValueKey('preview-spacing')));
    await tester.pumpAndSettle();
    expect(find.text('Masquer les espacements'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('preview-Card'))).height,
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

  for (final size in [const Size(1400, 1000), const Size(400, 700)]) {
    testWidgets('dense mode hides preview and navigation labels at $size', (
      tester,
    ) async {
      await openEditor(tester, size);
      double contentWidth() => tester
          .getSize(
            find.byWidget(
              tester.widget<AlertDialog>(find.byType(AlertDialog)).content!,
            ),
          )
          .width;
      final completeWidth = contentWidth();
      final toggle = find.byKey(const ValueKey('style-dense-toggle'));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final denseWidth = contentWidth();
      if (size.width > 1000) {
        expect(denseWidth, completeWidth - 400);
      } else {
        expect(denseWidth, completeWidth);
      }
      expect(find.byKey(const ValueKey('style-preview')), findsNothing);
      expect(find.text('PROPRIÉTÉS'), findsNothing);
      expect(find.text('Du visuel au code'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(StyleEditorPanel),
          matching: find.byType(ChoiceChip),
        ),
        findsNothing,
      );
      final navigation = find.byKey(const ValueKey('style-nav-fill'));
      expect(
        tester.widget<IconButton>(navigation).tooltip,
        'Fond & décoration',
      );
      expect(
        find.descendant(of: navigation, matching: find.byType(Text)),
        findsNothing,
      );
      final card = find.byKey(const ValueKey('style-card-interaction'));
      final before = tester.getTopLeft(card).dy;
      final interaction = find.byKey(const ValueKey('style-nav-interaction'));
      await tester.scrollUntilVisible(
        interaction,
        120,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(interaction);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(card).dy, lessThan(before));
      expect(find.byKey(const ValueKey('style-dense-reset')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-preview')), findsOneWidget);
      expect(contentWidth(), completeWidth);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dialog remembers both modes and width across openings', (
    tester,
  ) async {
    await openEditor(tester, const Size(1400, 1000));
    Future<void> reopen() async {
      Navigator.of(tester.element(find.byType(StyleEditorPanel))).pop();
      await tester.pumpAndSettle();
      tester
          .state<EditableSurfaceState>(find.byType(EditableSurface))
          .openEditor();
      await tester.pumpAndSettle();
    }

    double contentWidth() => tester
        .getSize(
          find.byWidget(
            tester.widget<AlertDialog>(find.byType(AlertDialog)).content!,
          ),
        )
        .width;
    final completeWidth = contentWidth();
    final toggle = find.byKey(const ValueKey('style-dense-toggle'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final denseWidth = contentWidth();
    await reopen();
    expect(find.byKey(const ValueKey('style-preview')), findsNothing);
    expect(contentWidth(), denseWidth);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await reopen();
    expect(find.byKey(const ValueKey('style-preview')), findsOneWidget);
    expect(contentWidth(), completeWidth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new panels inherit the mode unless explicitly overridden', (
    tester,
  ) async {
    Widget panel({bool? dense}) => MaterialApp(
      home: Scaffold(
        body: StyleEditorPanel(
          dense: dense,
          preview: const Text('Shared preview'),
          sections: const [],
        ),
      ),
    );
    await tester.pumpWidget(panel());
    await tester.tap(find.byKey(const ValueKey('style-dense-toggle')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(panel());
    expect(find.text('Shared preview'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(panel(dense: false));
    expect(find.text('Shared preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel can start dense and preserves control state on toggle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StyleEditorPanel(
            dense: true,
            preview: const Text('Test preview'),
            sections: const [
              StyleEditorSection(
                id: 'test',
                title: 'Test section',
                icon: Icons.settings,
                child: TextField(key: ValueKey('dense-test-input')),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Test preview'), findsNothing);
    final input = find.byKey(const ValueKey('dense-test-input'));
    await tester.enterText(input, 'kept');
    await tester.tap(find.byKey(const ValueKey('style-dense-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Test preview'), findsOneWidget);
    expect(find.text('kept'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('style-dense-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('kept'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
