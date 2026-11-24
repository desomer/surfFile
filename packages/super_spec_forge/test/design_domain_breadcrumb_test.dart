import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  const domains = [
    FunctionalDomain(
      id: 'dom_sales',
      domainCode: 'sales',
      name: 'Commercial Offer Management',
    ),
    FunctionalDomain(
      id: 'dom_crm',
      domainCode: 'crm',
      name: 'CRM',
    ),
  ];

  testWidgets(
    'DesignDomainBreadcrumbBar emboîte les chevrons sans jour et gère clics et menu domaine',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      FunctionalDomain? chosenDomain;
      var parentTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: const Color(0xFF3F51B5),
            brightness: Brightness.dark,
          ),
          home: Scaffold(
            body: DesignDomainBreadcrumbBar(
              domains: domains,
              selectedDomain: domains.first,
              onDomainSelected: (domain) => chosenDomain = domain,
              segments: [
                DesignBreadcrumbSegment(
                  key: const ValueKey('parent-crumb'),
                  label: 'Modèles et contrats',
                  isParent: true,
                  onTap: () => parentTapped = true,
                ),
                const DesignBreadcrumbSegment(
                  key: ValueKey('entry-crumb'),
                  label: 'BudgetEnvelope',
                ),
                const DesignBreadcrumbSegment(
                  key: ValueKey('version-crumb'),
                  label: '0.0.1',
                  isSecondary: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Vérifie que les chevrons se chevauchent bien horizontalement (emboîtement).
      final domainRect = tester.getRect(
        find.byKey(const ValueKey('design-domain-crumb')),
      );
      final parentRect = tester.getRect(
        find.byKey(const ValueKey('parent-crumb')),
      );
      final entryRect = tester.getRect(
        find.byKey(const ValueKey('entry-crumb')),
      );
      final versionRect = tester.getRect(
        find.byKey(const ValueKey('version-crumb')),
      );

      expect(parentRect.left, lessThan(domainRect.right));
      expect(entryRect.left, lessThan(parentRect.right));
      expect(versionRect.left, lessThan(entryRect.right));

      // Clic sur le segment parent cliquable.
      await tester.tap(find.byKey(const ValueKey('parent-crumb')));
      await tester.pumpAndSettle();
      expect(parentTapped, isTrue);

      // Clic sur le segment secondaire (inactif, ne doit pas lever d'erreur).
      await tester.tap(find.byKey(const ValueKey('version-crumb')));
      await tester.pumpAndSettle();

      // Ouverture du menu domaine et sélection d'un autre domaine.
      await tester.tap(find.byKey(const ValueKey('design-domain-crumb')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('design-domain-option-dom_crm')),
      );
      await tester.pumpAndSettle();
      expect(chosenDomain?.id, 'dom_crm');
    },
  );

  testWidgets(
    'DesignDomainBreadcrumbBar s’adapte au thème clair et à l’absence de domaine',
    (WidgetTester tester) async {
      final lightTheme = ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F51B5),
        brightness: Brightness.light,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: Scaffold(
            body: DesignDomainBreadcrumbBar(
              domains: const [],
              selectedDomain: null,
              onDomainSelected: (_) {},
              segments: const [
                DesignBreadcrumbSegment(
                  key: ValueKey('empty-page-crumb'),
                  label: 'Cas d’usage & orchestration',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aucun domaine'), findsOneWidget);
      expect(find.text('Cas d’usage & orchestration'), findsOneWidget);

      final barBox = tester.widget<Container>(
        find.descendant(
          of: find.byType(DesignDomainBreadcrumbBar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        ),
      );
      final decoration = barBox.decoration! as BoxDecoration;
      expect(decoration.color, lightTheme.colorScheme.surfaceContainerLow);
    },
  );
}
