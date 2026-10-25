import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  group('ListViewAddConfigurator & _ListViewAddForm', () {
    test('summary reflects standard and wrap mode with item dimensions', () {
      const standard = SuperListViewConfig(
        axis: Axis.vertical,
        itemExtent: 64,
        spacing: 8,
        allowAdd: true,
        allowRemove: false,
        emptyText: 'Aucune donnée',
      );
      final standardSummary = listViewAddConfigurator.summarize(standard);
      expect(standardSummary, contains(const ('Disposition', 'Verticale')));
      expect(standardSummary, contains(const ('Taille des items', '64.0')));
      expect(standardSummary, contains(const ('Espacement', '8.0')));

      const wrap = SuperListViewConfig(
        wrap: true,
        itemWidth: 180,
        itemExtent: 90,
        spacing: 12,
      );
      final wrapSummary = listViewAddConfigurator.summarize(wrap);
      expect(wrapSummary, contains(const ('Disposition', 'Wrap')));
      expect(wrapSummary, contains(const ('Largeur des items', '180.0')));
      expect(wrapSummary, contains(const ('Taille des items', '90.0')));
      expect(wrapSummary, contains(const ('Espacement', '12.0')));
    });

    testWidgets(
      'ListView add form displays cards and handles mode transitions',
      (tester) async {
        var current = const SuperListViewConfig(
          axis: Axis.vertical,
          itemExtent: 56,
          spacing: 4,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) =>
                    listViewAddConfigurator.buildDraft(
                      context,
                      current,
                      (next) =>
                          setState(() => current = next as SuperListViewConfig),
                    ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check Cards
        expect(find.byType(Card), findsAtLeastNWidgets(3));
        expect(find.text('Disposition & Dimensions'), findsOneWidget);
        expect(find.text('Actions interactives'), findsOneWidget);
        expect(find.text('Contenu & Messages'), findsOneWidget);

        // Label: "Taille des items" (not "Taille des lignes")
        expect(find.text('Taille des items'), findsOneWidget);
        expect(find.text('Taille des lignes'), findsNothing);

        // In vertical mode: itemWidth is not shown
        expect(find.byKey(const ValueKey('add-list-item-width')), findsNothing);

        // Switch to Wrap mode
        await tester.tap(find.text('Wrap'));
        await tester.pumpAndSettle();

        expect(current.wrap, isTrue);
        // In wrap mode: both Largeur des items and Taille des items are shown
        expect(
          find.byKey(const ValueKey('add-list-item-width')),
          findsOneWidget,
        );
        expect(find.text('Largeur des items'), findsOneWidget);
        expect(find.byKey(const ValueKey('add-list-extent')), findsOneWidget);

        // Change itemWidth
        await tester.enterText(
          find.byKey(const ValueKey('add-list-item-width')),
          '200',
        );
        await tester.pumpAndSettle();
        expect(current.itemWidth, 200.0);

        // Change itemExtent (Taille des items)
        await tester.enterText(
          find.byKey(const ValueKey('add-list-extent')),
          '80',
        );
        await tester.pumpAndSettle();
        expect(current.itemExtent, 80.0);

        // Change spacing
        await tester.enterText(
          find.byKey(const ValueKey('add-list-spacing')),
          '16',
        );
        await tester.pumpAndSettle();
        expect(current.spacing, 16.0);

        // Toggle allowAdd
        await tester.tap(find.byKey(const ValueKey('add-list-allow-add')));
        await tester.pumpAndSettle();
        expect(current.allowAdd, isTrue);

        // Toggle allowRemove
        await tester.tap(find.byKey(const ValueKey('add-list-allow-remove')));
        await tester.pumpAndSettle();
        expect(current.allowRemove, isTrue);

        // Change emptyText
        await tester.enterText(
          find.byKey(const ValueKey('add-list-empty')),
          'Rien à afficher',
        );
        await tester.pumpAndSettle();
        expect(current.emptyText, 'Rien à afficher');

        // Switch back to Horizontale
        await tester.tap(find.text('Horizontale'));
        await tester.pumpAndSettle();
        expect(current.wrap, isFalse);
        expect(current.axis, Axis.horizontal);
        expect(find.byKey(const ValueKey('add-list-item-width')), findsNothing);
      },
    );
  });
}
