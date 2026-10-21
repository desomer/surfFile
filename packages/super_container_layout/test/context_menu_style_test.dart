import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  testWidgets('a component type matching its menu title is not repeated', (
    tester,
  ) async {
    final editing = ValueNotifier(true);
    addTearDown(editing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: editing,
          child: Scaffold(
            body: EditorSlot(
              label: 'Configurer la carte',
              menuTitle: 'Card',
              menuType: 'Card',
              onEdit: () async {},
              child: const SizedBox(
                width: 160,
                height: 80,
                child: Text('Cible'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cible'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('style-menu-Configurer la carte'));
    expect(
      find.descendant(of: row, matching: find.text('Card')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Configurer la carte')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editor context menu prioritizes component title and compact actions',
    (tester) async {
      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: editing,
            child: Scaffold(
              body: Center(
                child: EditableSurface(
                  label: 'Parent',
                  child: EditableSurface(
                    label: 'Titre',
                    menuTitle: 'Composant',
                    menuType: 'Text',
                    menuSubtitle: () => 'Zone de titre',
                    onLabelChanged: (_) {},
                    onAdd: () async {},
                    child: const SizedBox(
                      width: 160,
                      height: 80,
                      child: Text('Cible'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Cible'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      final componentRow = find.byKey(const ValueKey('style-menu-Titre'));
      expect(tester.getSize(componentRow).height, lessThanOrEqualTo(48));
      expect(
        find.descendant(of: componentRow, matching: find.text('Composant')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: componentRow, matching: find.text('Zone de titre')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: componentRow, matching: find.text('Text')),
        findsNothing,
      );
      final componentTitle = tester.widget<Text>(
        find.descendant(of: componentRow, matching: find.text('Composant')),
      );
      final regionTitle = tester.widget<Text>(
        find.descendant(of: componentRow, matching: find.text('Zone de titre')),
      );
      expect(
        componentTitle.style!.fontSize,
        greaterThan(regionTitle.style!.fontSize!),
      );
      expect(
        find.descendant(
          of: componentRow,
          matching: find.byIcon(Icons.brush_outlined),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<PopupMenuDivider>(find.byType(PopupMenuDivider)).height,
        12,
      );

      for (final action in ['rename', 'add']) {
        final button = tester.widget<IconButton>(
          find.byKey(ValueKey('style-menu-$action-Titre')),
        );
        expect(button.style!.minimumSize!.resolve({}), const Size.square(36));
        expect(button.style!.visualDensity, VisualDensity.compact);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editor without a zone subtitle shows its component type', (
    tester,
  ) async {
    final editing = ValueNotifier(true);
    addTearDown(editing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: editing,
          child: Scaffold(
            body: Center(
              child: EditorSlot(
                label: 'Contenu',
                menuType: 'AppBar',
                onEdit: () async {},
                child: const SizedBox(
                  width: 160,
                  height: 80,
                  child: Text('Cible'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Cible'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('style-menu-Contenu'));
    expect(
      find.descendant(of: row, matching: find.text('Contenu')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('AppBar')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
