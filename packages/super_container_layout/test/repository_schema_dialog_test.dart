import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('schema-dialog-test-');
    store = JsonRepositoryStore(directory);
  });

  tearDown(() async {
    store.dispose();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  Future<void> editCode(WidgetTester tester, Finder field, String text) async {
    await tester.runAsync(() async {
      await tester.showKeyboard(field);
      final controller = tester.widget<EditableText>(field).controller;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.enterText(field, text);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('JsonRepositoryManager ouvre RepositorySchemaDialog, associe un schéma et bloque une sauvegarde invalide', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await store.create('Clients');
      final id = await store.idOf('Clients');
      await store.replaceDocumentById(id, {'nom': 'Alice', 'age': 30});
    });

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => JsonRepositoryManager(store: store),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tap(tester, find.text('Open'));
    await tap(tester, find.byKey(const ValueKey('repository-entry-Clients')));

    // Ouvre le dialogue JSON Schema.
    await tap(tester, find.byKey(const ValueKey('repository-json-schema')));
    expect(find.byKey(const ValueKey('repository-schema-editor')), findsOneWidget);

    // Génère un schéma depuis le document puis enregistre.
    await tap(tester, find.byKey(const ValueKey('repository-schema-infer')));
    await tap(tester, find.byKey(const ValueKey('repository-schema-save')));
    expect(find.byKey(const ValueKey('repository-schema-notice')), findsOneWidget);

    // Remplace le schéma par une règle stricte qui rejette age < 50 -> échec bloquant.
    final schemaEditable = find.descendant(
      of: find.byKey(const ValueKey('repository-schema-editor')),
      matching: find.byType(EditableText),
    );
    await editCode(
      tester,
      schemaEditable,
      jsonEncode({
        'type': 'object',
        'required': ['nom', 'age'],
        'properties': {
          'nom': {'type': 'string'},
          'age': {'type': 'integer', 'minimum': 50},
        },
      }),
    );
    await tap(tester, find.byKey(const ValueKey('repository-schema-save')));
    expect(find.byKey(const ValueKey('repository-schema-error')), findsOneWidget);

    // Ferme le dialogue de schéma et vérifie le badge actif dans JsonRepositoryManager.
    await tap(tester, find.byKey(const ValueKey('repository-schema-close')));
    expect(find.byKey(const ValueKey('repository-schema-badge')), findsOneWidget);

    // Modifie le document dans JsonRepositoryManager avec une valeur non conforme au schéma inféré ("age": "pas-un-entier") -> erreur à la sauvegarde.
    await tester.enterText(
      find.byKey(const ValueKey('repository-json')),
      '{\n  "nom": "Alice",\n  "age": "pas-un-entier"\n}\n',
    );
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('repository-save')));
    expect(find.byKey(const ValueKey('repository-error')), findsOneWidget);
  });

  testWidgets('_FloatingRepositoryEditor valide le JSON en direct contre le schéma associé', (
    tester,
  ) async {
    late String repoId;
    await tester.runAsync(() async {
      await store.create('Config');
      repoId = await store.idOf('Config');
      await store.replaceDocumentById(repoId, {'port': 8080});
      await store.saveJsonSchema(repoId, {
        'type': 'object',
        'required': ['port'],
        'properties': {
          'port': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
        },
      });
    });

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openFloatingRepositoryEditor(
                context,
                store: store,
                repositoryId: repoId,
                name: 'Config',
                text: '{\n  "port": 8080\n}\n',
              ),
              child: const Text('OpenFloat'),
            ),
          ),
        ),
      ),
    );

    await tap(tester, find.text('OpenFloat'));
    expect(find.byKey(const ValueKey('floating-repository-schema')), findsOneWidget);
    expect(find.byKey(const ValueKey('floating-repository-error')), findsNothing);

    final codeEditable = find.descendant(
      of: find.byKey(const ValueKey('floating-repository-code')),
      matching: find.byType(EditableText),
    );
    await editCode(tester, codeEditable, '{\n  "port": 99999\n}\n');
    expect(find.byKey(const ValueKey('floating-repository-error')), findsOneWidget);

    // Le document sur disque n'a pas été modifié par la saisie invalide.
    final storedDoc = await tester.runAsync(() => store.readDocument(repoId));
    expect((storedDoc as Map)['port'], 8080);

    // Une saisie valide efface l'erreur et sauvegarde.
    await editCode(tester, codeEditable, '{\n  "port": 3000\n}\n');
    expect(find.byKey(const ValueKey('floating-repository-error')), findsNothing);
    final updatedDoc = await tester.runAsync(() => store.readDocument(repoId));
    expect((updatedDoc as Map)['port'], 3000);
  });
}
