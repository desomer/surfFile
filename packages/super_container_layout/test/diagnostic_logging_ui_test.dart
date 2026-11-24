import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  setUp(() {
    clearDebugEntries();
  });

  tearDown(() {
    clearDebugEntries();
  });

  testWidgets(
    'SuperAction affiche en rouge une police indisponible en édition et la journalise en font/warning',
    (tester) async {
      final editMode = ValueNotifier<bool>(true);
      addTearDown(editMode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: editMode,
            child: Scaffold(
              body: SuperAction(
                id: 'btn_missing_font',
                config: const SuperActionConfig(
                  label: 'Valider',
                  fontFamily: 'PoliceInexistante',
                ),
                availableFontFamilies: const ['Inter', 'Roboto'],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('super-action-font-error-btn_missing_font')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Police indisponible : PoliceInexistante'),
        findsOneWidget,
      );

      final fontErrors = debugEntries
          .where(
            (e) =>
                e.category == DebugErrorCategory.font &&
                e.componentId == 'btn_missing_font',
          )
          .toList();
      expect(fontErrors, hasLength(1));
      expect(fontErrors.single.severity, DebugSeverity.warning);
      expect(fontErrors.single.visibleInUi, isTrue);
    },
  );

  testWidgets(
    'SuperValue journalise erreur de binding en binding/error et erreur de saisie en userInput/warning',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('scl_diag_val_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = JsonRepositoryStore(dir);
      addTearDown(store.dispose);

      // 1. Erreur de liaison (repository inexistant) affichée en rouge + loggée.
      await tester.pumpWidget(
        MaterialApp(
          home: JsonRepositoryScope(
            store: store,
            child: Scaffold(
              body: Column(
                children: [
                  SuperValue(
                    id: 'val_bad_binding',
                    config: const SuperValueConfig(
                      mode: SuperValueMode.display,
                      binding: JsonTextBinding(path: 'client.nom'),
                    ),
                  ),
                  SuperValue(
                    id: 'val_input_check',
                    config: const SuperValueConfig(
                      mode: SuperValueMode.input,
                      field: SuperTextFieldConfig(
                        required: true,
                        minLength: 5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('super-value-binding-error-val_bad_binding')),
        findsOneWidget,
      );
      final bindingErrors = debugEntries
          .where(
            (e) =>
                e.category == DebugErrorCategory.binding &&
                e.componentId == 'val_bad_binding',
          )
          .toList();
      expect(bindingErrors, isNotEmpty);
      expect(bindingErrors.first.severity, DebugSeverity.error);
      expect(bindingErrors.first.visibleInUi, isTrue);

      // 2. Saisie utilisateur invalide (trop courte) → erreur rouge + userInput/warning.
      await tester.enterText(
        find.byKey(const ValueKey('super-value-input-val_input_check')),
        'ab',
      );
      await tester.pump();

      final inputErrors = debugEntries
          .where(
            (e) =>
                e.category == DebugErrorCategory.userInput &&
                e.componentId == 'val_input_check',
          )
          .toList();
      expect(inputErrors, isNotEmpty);
      expect(inputErrors.first.severity, DebugSeverity.warning);
      expect(inputErrors.first.visibleInUi, isTrue);
    },
  );

  testWidgets(
    'RunJavaScriptAction en erreur journalise en javascript/critical et renseigne errorReports',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('scl_diag_js_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = JsonRepositoryStore(dir);
      addTearDown(store.dispose);

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: JsonRepositoryScope(
            store: store,
            child: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      const action = RunJavaScriptAction(code: 'ctx.set("x", 1);');
      await action.executeWithData(
        capturedContext,
        BehaviorExecutionData(
          componentId: 'btn_js_fail',
          componentType: 'action',
          event: BehaviorEvent.onTap,
        ),
      );

      expect(store.errorReports.value, isNotNull);
      expect(store.errorReports.value!.category, DebugErrorCategory.javascript);
      expect(store.errorReports.value!.componentId, 'btn_js_fail');

      final jsEntries = debugEntries
          .where(
            (e) =>
                e.category == DebugErrorCategory.javascript &&
                e.componentId == 'btn_js_fail',
          )
          .toList();
      expect(jsEntries, hasLength(1));
      expect(jsEntries.single.visibleInUi, isTrue);
    },
  );

  test(
    'VibeAppInspector.getDebugEntries expose countsBySeverity, countsByCategory et filtres typés',
    () async {
      saveDiagnostic(
        message: 'JS syntax crash',
        category: DebugErrorCategory.javascript,
        severity: DebugSeverity.critical,
        componentId: 'btn_calc',
        visibleInUi: true,
      );
      saveDiagnostic(
        message: 'Chemin inconnu',
        category: DebugErrorCategory.binding,
        severity: DebugSeverity.error,
        componentId: 'kpi_1',
        visibleInUi: true,
      );
      saveDiagnostic(
        message: 'Police absente',
        category: DebugErrorCategory.font,
        severity: DebugSeverity.warning,
        componentId: 'hero_title',
        visibleInUi: false,
      );
      saveDiagnostic(
        message: 'Email invalide',
        category: DebugErrorCategory.userInput,
        severity: DebugSeverity.warning,
        componentId: 'email_field',
        visibleInUi: true,
      );

      final inspector = VibeAppInspector(readAppearance: () => Appearance());

      final allErrors = await inspector.getDebugEntries({'type': 'error'});
      expect(allErrors['totalErrors'], 4);
      expect(allErrors['uiVisibleErrorCount'], 3);
      expect((allErrors['countsBySeverity'] as Map)['critical'], 1);
      expect((allErrors['countsBySeverity'] as Map)['error'], 1);
      expect((allErrors['countsBySeverity'] as Map)['warning'], 2);
      expect((allErrors['countsByCategory'] as Map)['javascript'], 1);
      expect((allErrors['countsByCategory'] as Map)['binding'], 1);
      expect((allErrors['countsByCategory'] as Map)['font'], 1);
      expect((allErrors['countsByCategory'] as Map)['userInput'], 1);

      final onlyCriticalAndError = await inspector.getDebugEntries({
        'type': 'error',
        'minSeverity': 'error',
      });
      expect(onlyCriticalAndError['returnedCount'], 2);

      final onlyFont = await inspector.getDebugEntries({
        'type': 'error',
        'category': 'font',
      });
      expect(onlyFont['returnedCount'], 1);
      expect(
        ((onlyFont['entries'] as List).single as Map)['componentId'],
        'hero_title',
      );

      final onlyUi = await inspector.getDebugEntries({
        'type': 'error',
        'visibleInUiOnly': true,
      });
      expect(onlyUi['returnedCount'], 3);
    },
  );

  testWidgets(
    'DiagnosticLogBannerButton et DiagnosticLogPanel affichent, filtrent et effacent les erreurs typées',
    (tester) async {
      saveDiagnostic(
        message: 'Erreur JS critique test',
        category: DebugErrorCategory.javascript,
        severity: DebugSeverity.critical,
        componentId: 'btn_run',
        visibleInUi: true,
      );
      saveDiagnostic(
        message: 'Police manquante test',
        category: DebugErrorCategory.font,
        severity: DebugSeverity.warning,
        componentId: 'lbl_title',
        visibleInUi: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DiagnosticLogBannerButton(onPressed: () {}),
                const Expanded(child: DiagnosticLogPanel()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Badge affiche 2 erreurs.
      expect(
        find.byKey(const ValueKey('style-edit-banner-diagnostics-badge')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Erreur JS critique test'), findsOneWidget);
      expect(find.text('Police manquante test'), findsOneWidget);

      // Filtre par catégorie JavaScript.
      await tester.tap(
        find.byKey(const ValueKey('diagnostic-category-javascript')),
      );
      await tester.pump();
      expect(find.text('Erreur JS critique test'), findsOneWidget);
      expect(find.text('Police manquante test'), findsNothing);

      // Retour à toutes catégories puis filtre IHM rouge uniquement.
      await tester.tap(find.byKey(const ValueKey('diagnostic-category-all')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('diagnostic-filter-ui-only')),
      );
      await tester.pump();
      expect(find.text('Erreur JS critique test'), findsOneWidget);
      expect(find.text('Police manquante test'), findsNothing);

      // Effacement global.
      await tester.tap(find.byKey(const ValueKey('diagnostic-log-clear')));
      await tester.pump();
      expect(debugEntries, isEmpty);
      expect(
        find.byKey(const ValueKey('style-edit-banner-diagnostics-badge')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'SuperLayout racine vide lève une alerte explicite dans debugEntries si des composants fantômes existent, sans faux positif sur écran vierge',
    (tester) async {
      // 1. Écran vierge (seuls root & mainLayout configurés) -> aucune alerte fantôme.
      final blankAppearance = ValueNotifier<Appearance>(
        Appearance(
          components: <String, ComponentConfig>{
            'mainLayout': const SuperLayoutConfig(),
          },
        ),
      );
      addTearDown(blankAppearance.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AppearanceScope(
            controller: blankAppearance,
            child: ValueListenableBuilder<Appearance>(
              valueListenable: blankAppearance,
              builder: (_, app, _) => SuperLayout(
                id: 'mainLayout',
                config: app.components['mainLayout']! as SuperLayoutConfig,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        debugEntries.where((e) => e.source == 'SuperLayout.ghostComponents'),
        isEmpty,
      );

      // 2. Composants configurés non placés dans mainLayout -> alerte explicite dans debugEntries.
      blankAppearance.value = Appearance(
        components: <String, ComponentConfig>{
          'mainLayout': const SuperLayoutConfig(),
          'dash-header': const SuperValueConfig(initialText: 'En-tête'),
          'kpis-row': const SuperLayoutConfig(),
          'card-chart-container': const SuperValueConfig(initialText: 'Graphe'),
        },
      );
      await tester.pump();
      // Deuxième pump pour vérifier la déduplication.
      await tester.pump();

      final ghostErrors = debugEntries
          .where((e) => e.source == 'SuperLayout.ghostComponents')
          .toList();
      expect(ghostErrors, hasLength(1));
      expect(ghostErrors.single.category, DebugErrorCategory.rendering);
      expect(ghostErrors.single.severity, DebugSeverity.error);
      expect(ghostErrors.single.componentId, 'mainLayout');
      expect(ghostErrors.single.message, contains('mainLayout'));
      expect(ghostErrors.single.message, contains('0 slot placé'));
      expect(ghostErrors.single.message, contains('3 composant(s)'));
      expect(ghostErrors.single.message, contains('dash-header'));

      // 3. Dès que mainLayout reçoit des placements, le diagnostic est libéré
      //    (et peut se redéclencher si les placements sont retirés à nouveau).
      blankAppearance.value = Appearance(
        components: <String, ComponentConfig>{
          'mainLayout': const SuperLayoutConfig(
            placements: <SuperLayoutZone, List<String>>{
              SuperLayoutZone.center: <String>[
                'dash-header',
                'kpis-row',
                'card-chart-container',
              ],
            },
            slotTypes: <String, String>{
              'dash-header': 'registry:Value',
              'kpis-row': 'registry:Layout',
              'card-chart-container': 'registry:Value',
            },
          ),
          'dash-header': const SuperValueConfig(initialText: 'En-tête'),
          'kpis-row': const SuperLayoutConfig(),
          'card-chart-container': const SuperValueConfig(initialText: 'Graphe'),
        },
      );
      await tester.pump();

      // Re-vider mainLayout doit pouvoir réémettre l'alerte car la clé a été libérée.
      clearDebugEntries();
      blankAppearance.value = Appearance(
        components: <String, ComponentConfig>{
          'mainLayout': const SuperLayoutConfig(),
          'dash-header': const SuperValueConfig(initialText: 'En-tête'),
        },
      );
      await tester.pump();
      expect(
        debugEntries.where((e) => e.source == 'SuperLayout.ghostComponents'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'Les erreurs de validation champ obligatoire dans debugEntries et flushBindings précisent le champ concerné',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('scl_diag_req_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = JsonRepositoryStore(dir);
      addTearDown(store.dispose);
      store.registerRepository(
        RepositoryImpl(
          id: 'client_repo',
          json: {'tel': '0600000000'},
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: JsonRepositoryScope(
            store: store,
            child: const Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 260,
                    child: SuperValue(
                      id: 'gen-tel',
                      config: SuperValueConfig(
                        mode: SuperValueMode.input,
                        label: 'Téléphone',
                        binding: JsonTextBinding(
                          repositoryId: 'client_repo',
                          path: 'tel',
                        ),
                        field: SuperTextFieldConfig(required: true),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('super-value-input-gen-tel')),
        '',
      );
      await tester.pump();

      final validationEntries = debugEntries
          .where(
            (e) =>
                e.category == DebugErrorCategory.userInput &&
                e.componentId == 'gen-tel',
          )
          .toList();
      expect(validationEntries, isNotEmpty);
      expect(
        validationEntries.last.message,
        'Champ « Téléphone » (tel) : Ce champ est obligatoire.',
      );

      // En UI du champ, le message court reste conservé.
      final indicator = find.byKey(
        const ValueKey('super-value-error-indicator-gen-tel'),
      );
      expect(indicator, findsOneWidget);
      final tooltip = tester.widget<Tooltip>(
        find.descendant(of: indicator, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, 'Ce champ est obligatoire.');

      // Lors d'un flushBindings (ex. SuperListView), l'exception précise aussi le champ et le compId.
      await expectLater(
        () => store.flushBindings(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Champ « Téléphone » (tel, comp:gen-tel) : Ce champ est obligatoire.',
          ),
        ),
      );
    },
  );
}
