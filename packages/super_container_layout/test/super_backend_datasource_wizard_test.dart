import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/services/repositories/json_repository_scope.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/widgets/editing/datasources/datasource_manager.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('super-backend-wizard-');
    store = JsonRepositoryStore(directory);
    store.registerRepository(
      RepositoryImpl(
        id: 'filtre',
        json: {'city': '', 'state': <String, Object?>{}},
      ),
    );
    store.registerRepository(
      RepositoryImpl(id: 'formulaire', json: {'name': '', 'city': ''}),
    );
    store.registerRepository(
      RepositoryImpl(
        id: 'resultats',
        json: {'rows': <Object?>[], 'detail': <String, Object?>{}},
      ),
    );
    await store.superBackend.init();
    await store.superBackend.create('clients', {
      'name': 'Alice',
      'city': 'Lyon',
    }, id: 'c1');
    await store.superBackend.create('clients', {
      'name': 'Bob',
      'city': 'Paris',
    }, id: 'c2');
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    final progress = find.byWidgetPredicate(
      (widget) =>
          widget is ProgressIndicator ||
          widget is Text && widget.data == 'Chargement des repositories…',
    );
    for (var i = 0; i < 150; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (i >= 2 && progress.evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> choose(WidgetTester tester, Finder field, String item) async {
    await tap(tester, field);
    await tap(tester, find.text(item).last);
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await settle(tester);
  }

  Future<List<String?>> openManager(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final results = <String?>[];
    await tester.pumpWidget(
      JsonRepositoryScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => DatasourceManager(store: store),
                ).then(results.add),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await settle(tester);
    return results;
  }

  testWidgets(
    'Bouton SuperBackend dans DatasourceManager crée les 5 providers et la datasource puis exécute la recherche SQLite',
    (tester) async {
      final results = await openManager(tester);

      await tap(
        tester,
        find.byKey(const ValueKey('datasource-create-super-backend')),
      );
      expect(
        find.text('Connecter une datasource à SuperBackend'),
        findsOneWidget,
      );

      await type(tester, 'super-backend-wizard-id', 'clients');
      await type(tester, 'super-backend-wizard-label', 'Clients');

      await choose(
        tester,
        find.byKey(const ValueKey('super-backend-wizard-list-repository')),
        'resultats',
      );
      await type(tester, 'super-backend-wizard-list-repository-path', 'rows');

      await choose(
        tester,
        find.byKey(const ValueKey('super-backend-wizard-detail-repository')),
        'resultats',
      );
      await type(
        tester,
        'super-backend-wizard-detail-repository-path',
        'detail',
      );

      await choose(
        tester,
        find.byKey(const ValueKey('super-backend-wizard-filter-repo')),
        'filtre',
      );
      await choose(
        tester,
        find.byKey(const ValueKey('super-backend-wizard-form-repo')),
        'formulaire',
      );

      await tap(
        tester,
        find.byKey(const ValueKey('super-backend-wizard-submit')),
      );

      expect(
        find.text('Datasource SuperBackend « clients » créée.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('SuperBackend SQLite : collection « clients »'),
        findsWidgets,
      );

      // Teste la recherche depuis l'IHM sur la base SQLite locale
      await tap(tester, find.byKey(const ValueKey('datasource-test')));
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('datasource-test-result')),
            )
            .data,
        allOf(contains('2 ligne(s) reçue(s) sur 2.'), contains('"Alice"')),
      );

      // Lance la recherche réelle et vérifie l'écriture dans resultats.rows
      await tap(tester, find.byKey(const ValueKey('datasource-search')));
      final doc = store.peekDocument('resultats')?.document as Map?;
      expect((doc?['rows'] as List?)?.length, 2);

      await tap(tester, find.byKey(const ValueKey('datasource-close')));
      expect(results, ['clients']);
    },
  );

  testWidgets(
    'Bouton Préconfigurer avec SuperBackend dans DatasourceForm pré-remplit le formulaire',
    (tester) async {
      await openManager(tester);

      await tap(tester, find.byKey(const ValueKey('datasource-create')));
      await type(tester, 'datasource-id', 'clients');

      await tap(
        tester,
        find.byKey(const ValueKey('datasource-preconfigure-super-backend')),
      );
      expect(
        find.text('Connecter une datasource à SuperBackend'),
        findsOneWidget,
      );

      await choose(
        tester,
        find.byKey(const ValueKey('super-backend-wizard-list-repository')),
        'resultats',
      );
      await type(tester, 'super-backend-wizard-list-repository-path', 'rows');

      await tap(
        tester,
        find.byKey(const ValueKey('super-backend-wizard-submit')),
      );

      // Le formulaire est maintenant pré-rempli avec les 5 providers SuperBackend
      expect(
        find.textContaining('SuperBackend SQLite : collection « clients »'),
        findsWidgets,
      );

      await tap(tester, find.byKey(const ValueKey('datasource-save')));
      expect(find.text('Datasource enregistrée.'), findsOneWidget);
      expect(store.datasources.datasource('clients'), isNotNull);
    },
  );
}
