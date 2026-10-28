import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/components/super_text_field_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MaterialIconCatalog search supports FR/EN keywords, accents and categories', () {
    // Search by French accent-insensitive keyword
    final starResults = MaterialIconCatalog.search(query: 'étoile');
    expect(starResults.map((e) => e.id), contains('star'));

    // Search by English keyword
    final trashResults = MaterialIconCatalog.search(query: 'trash');
    expect(trashResults.map((e) => e.id), contains('delete'));

    // Search by category filter
    final commerceResults = MaterialIconCatalog.search(
      category: MaterialIconCategory.commerce,
    );
    expect(commerceResults, isNotEmpty);
    expect(
      commerceResults.every((e) => e.category == MaterialIconCategory.commerce),
      isTrue,
    );
    expect(commerceResults.map((e) => e.id), contains('shopping_cart'));

    // Search with allowedIds restriction
    final restricted = MaterialIconCatalog.search(
      query: '',
      allowedIds: const ['person', 'email'],
    );
    expect(restricted.map((e) => e.id).toSet(), {'person', 'email'});
  });

  testWidgets(
    'MaterialIconPickerField opens dialog, searches and selects icon',
    (tester) async {
      String? selected = 'add';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MaterialIconPickerField(
                key: const ValueKey('test-icon-picker'),
                label: 'Icône',
                value: selected,
                nullable: true,
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Ajouter (add)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('test-icon-picker')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('material-icon-picker-dialog')),
        findsOneWidget,
      );

      // Filter by category chip
      await tester.tap(
        find.byKey(const ValueKey('material-icon-category-commerce')),
      );
      await tester.pumpAndSettle();

      // Search by French keyword
      await tester.enterText(
        find.byKey(const ValueKey('material-icon-picker-search')),
        'panier',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('material-icon-option-shopping_cart')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('material-icon-option-shopping_cart')),
      );
      await tester.pumpAndSettle();

      expect(selected, 'shopping_cart');
      expect(find.text('Panier (shopping_cart)'), findsOneWidget);

      // Clear via inline clear button
      await tester.tap(find.byTooltip('Aucune icône'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.text('Thème / aucune'), findsOneWidget);
    },
  );

  testWidgets(
    'SuperActionAddForm selects icon through MaterialIconPickerField',
    (tester) async {
      var draft = const SuperActionConfig(
        kind: SuperActionKind.textAndIcon,
        icon: 'touch_app',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SuperActionAddForm(
                draft: draft,
                availableFontFamilies: const ['Roboto'],
                onChanged: (next) => setState(() => draft = next),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('add-action-icon')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('material-icon-picker-search')),
        'dossier',
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('material-icon-option-folder')),
      );
      await tester.pumpAndSettle();

      expect(draft.icon, 'folder');
      expect(find.text('Dossier'), findsOneWidget);

      // Clear icon choice via inline clear button
      await tester.tap(find.byTooltip('Aucune icône'));
      await tester.pumpAndSettle();

      expect(draft.icon, isEmpty);
      expect(() => draft.validate(), returnsNormally);
    },
  );

  testWidgets(
    'ContainerAddForm and styleColorTile allow clearing color to null',
    (tester) async {
      var draft = const ContainerStyle(color: Color(0xFF112233));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ContainerAddForm(
                draft: draft,
                onChanged: (next) => setState(() => draft = next),
              ),
            ),
          ),
        ),
      );

      expect(draft.color, const Color(0xFF112233));
      await tester.tap(find.byKey(const ValueKey('add-container-color-clear')));
      await tester.pumpAndSettle();
      expect(draft.color, isNull);
    },
  );

  testWidgets(
    'SuperTextFieldSettings updates prefixIcon and suffixIcon via icon picker',
    (tester) async {
      var config = const SuperTextFieldConfig();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SuperTextFieldSettings(
                value: config,
                onChanged: (next) => config = next,
                builder: (sections) =>
                    Column(children: [for (final s in sections) s.child]),
              ),
            ),
          ),
        ),
      );

      final prefixFinder = find.byKey(
        const ValueKey('text-field-setting-prefixIcon-null'),
      );
      await tester.ensureVisible(prefixFinder);
      await tester.pumpAndSettle();
      await tester.tap(prefixFinder);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('material-icon-picker-search')),
        'calendrier',
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('material-icon-option-calendar')),
      );
      await tester.pumpAndSettle();

      expect(config.prefixIcon, TextFieldIcon.calendar);
    },
  );
}
