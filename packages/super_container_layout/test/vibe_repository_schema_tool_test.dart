import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

class _MinimalGuideBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      'Guide minimal.';

  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Asset binaire absent: $key');
}

void main() {
  late Directory directory;
  late JsonRepositoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vibe-schema-tool-test-');
    store = JsonRepositoryStore(directory);
  });

  tearDown(() async {
    store.dispose();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('query_repository_data et manage_repository_json_schema couvrent le cycle complet', () async {
    await store.create('Clients');
    final repoId = await store.idOf('Clients');
    await store.replaceDocumentById(repoId, {
      'nom': 'Alice',
      'age': 32,
    });

    final tx = VibeRepositoryTurnTransaction(store);
    final inspector = VibeAppInspector(
      readAppearance: () => Appearance(),
      repositoryStore: store,
      repoTransaction: tx,
    );
    final registry = inspector.buildToolRegistry();

    expect(
      registry.declarationFor('manage_repository_json_schema'),
      isNotNull,
    );

    // 1. Catalogue initial via query_repository_data : pas encore de schéma.
    final initialCatalog = await registry.execute(
      VibeToolCall(
        id: 't1',
        name: 'query_repository_data',
        arguments: const {},
      ),
    );
    expect(initialCatalog.isError, isFalse);
    final repoSummary =
        (initialCatalog.data['repositories'] as List).first as Map;
    expect(repoSummary['hasJsonSchema'], isFalse);

    // 2. Inférence via action="infer" (accessible par nom ou ID).
    final inferredRes = await registry.execute(
      VibeToolCall(
        id: 't2',
        name: 'manage_repository_json_schema',
        arguments: const {
          'action': 'infer',
          'repositoryId': 'Clients',
          'markPresentKeysRequired': true,
        },
      ),
    );
    expect(inferredRes.isError, isFalse);
    final inferredSchema =
        inferredRes.data['schema'] as Map<String, Object?>;
    expect(inferredSchema['required'], containsAll(['nom', 'age']));

    // 3. Tentative de création avec un schéma qui échoue contre le document -> erreur structurée avec issues.
    final badCreate = await registry.execute(
      VibeToolCall(
        id: 't3',
        name: 'manage_repository_json_schema',
        arguments: {
          'action': 'create',
          'repositoryId': repoId,
          'schema': {
            'type': 'object',
            'required': ['nom', 'age'],
            'properties': {
              'nom': {'type': 'string'},
              'age': {'type': 'integer', 'minimum': 50},
            },
          },
        },
      ),
    );
    expect(badCreate.isError, isTrue);
    expect(badCreate.data['issues'], isNotEmpty);
    expect(store.jsonSchemaOf(repoId), isNull);

    // 4. Création conforme via action="create".
    final created = await registry.execute(
      VibeToolCall(
        id: 't4',
        name: 'manage_repository_json_schema',
        arguments: {
          'action': 'create',
          'repositoryId': repoId,
          'schema': inferredSchema,
        },
      ),
    );
    expect(created.isError, isFalse);
    expect(created.data['hasJsonSchema'], isTrue);
    expect(store.jsonSchemaOf(repoId), isNotNull);

    // 5. Doublon sur action="create" refusé -> invite à utiliser "update".
    final duplicateCreate = await registry.execute(
      VibeToolCall(
        id: 't5',
        name: 'manage_repository_json_schema',
        arguments: {
          'action': 'create',
          'repositoryId': repoId,
          'schema': inferredSchema,
        },
      ),
    );
    expect(duplicateCreate.isError, isTrue);

    // 6. Lecture via query_repository_data et action="get".
    final detail = await registry.execute(
      VibeToolCall(
        id: 't6',
        name: 'query_repository_data',
        arguments: {'repositoryId': repoId},
      ),
    );
    expect(detail.data['hasJsonSchema'], isTrue);
    expect(detail.data['jsonSchema'], isNotNull);

    final got = await registry.execute(
      VibeToolCall(
        id: 't7',
        name: 'manage_repository_json_schema',
        arguments: {'action': 'get', 'repositoryId': repoId},
      ),
    );
    expect(got.isError, isFalse);
    expect(got.data['hasJsonSchema'], isTrue);

    // 7. Validation avec un schéma candidat via action="validate".
    final validated = await registry.execute(
      VibeToolCall(
        id: 't8',
        name: 'manage_repository_json_schema',
        arguments: {
          'action': 'validate',
          'repositoryId': repoId,
          'schema': {
            'type': 'object',
            'required': ['nom', 'email'],
          },
        },
      ),
    );
    expect(validated.isError, isFalse);
    expect(validated.data['valid'], isFalse);
    expect(validated.data['issueCount'], 1);

    // 8. Mise à jour avec validateCurrentDocument=false + validation différée assertAllSchemasValid.
    final deferredUpdate = await registry.execute(
      VibeToolCall(
        id: 't9',
        name: 'manage_repository_json_schema',
        arguments: {
          'action': 'update',
          'repositoryId': repoId,
          'validateCurrentDocument': false,
          'schema': {
            'type': 'object',
            'required': ['nom', 'age'],
            'properties': {
              'nom': {'type': 'string'},
              'age': {'type': 'integer', 'minimum': 40},
            },
          },
        },
      ),
    );
    expect(deferredUpdate.isError, isFalse);

    // Tant que le document a age=32, assertAllSchemasValid() lève JsonSchemaValidationException.
    await expectLater(
      tx.assertAllSchemasValid(),
      throwsA(isA<JsonSchemaValidationException>()),
    );

    // Une fois les données corrigées via applyRepositoriesPatch, assertAllSchemasValid() réussit.
    await tx.applyRepositoriesPatch({
      repoId: {
        'mode': 'merge',
        'data': {'age': 42},
      },
    });
    await tx.assertAllSchemasValid();

    // 9. Suppression via action="delete", puis Undo/Redo/Rollback via la transaction.
    final deleted = await registry.execute(
      VibeToolCall(
        id: 't10',
        name: 'manage_repository_json_schema',
        arguments: {'action': 'delete', 'repositoryId': repoId},
      ),
    );
    expect(deleted.isError, isFalse);
    expect(deleted.data['hadJsonSchema'], isTrue);
    expect(store.jsonSchemaOf(repoId), isNull);

    final historyCallbacks = tx.buildHistoryCallbacks()!;
    await historyCallbacks.undo();
    expect(store.jsonSchemaOf(repoId), isNull);
    expect((await store.readDocument(repoId) as Map)['age'], 32);

    await historyCallbacks.redo();
    expect(store.jsonSchemaOf(repoId), isNull);
    expect((await store.readDocument(repoId) as Map)['age'], 42);
  });

  test('refuse les modifications sur un RepositoryImpl avec jsonSchema figé dans le code', () async {
    store.registerRepository(
      RepositoryImpl(
        id: 'app_repo',
        json: const {'ok': true},
        jsonSchema: const {
          'type': 'object',
          'required': ['ok'],
          'properties': {
            'ok': {'type': 'boolean'},
          },
        },
      ),
    );

    final inspector = VibeAppInspector(
      readAppearance: () => Appearance(),
      repositoryStore: store,
    );
    final registry = inspector.buildToolRegistry();

    final getRes = await registry.execute(
      VibeToolCall(
        id: 'c1',
        name: 'manage_repository_json_schema',
        arguments: const {'action': 'get', 'repositoryId': 'app_repo'},
      ),
    );
    expect(getRes.isError, isFalse);
    expect(getRes.data['isCodeJsonSchema'], isTrue);

    final updateRes = await registry.execute(
      VibeToolCall(
        id: 'c2',
        name: 'manage_repository_json_schema',
        arguments: const {
          'action': 'update',
          'repositoryId': 'app_repo',
          'schema': {'type': 'object'},
        },
      ),
    );
    expect(updateRes.isError, isTrue);

    final deleteRes = await registry.execute(
      VibeToolCall(
        id: 'c3',
        name: 'manage_repository_json_schema',
        arguments: const {'action': 'delete', 'repositoryId': 'app_repo'},
      ),
    );
    expect(deleteRes.isError, isTrue);
  });

  testWidgets('VibeChatDialog conserve une création de schéma effectuée uniquement via toolCalls et supporte Undo/Redo', (
    tester,
  ) async {
    late String repoId;
    await tester.runAsync(() async {
      await store.create('Produits');
      repoId = await store.idOf('Produits');
      await store.replaceDocumentById(repoId, {'nom': 'Clavier', 'prix': 79});
    });

    final appearance = ValueNotifier(Appearance());
    addTearDown(appearance.dispose);
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: editMode,
      maxEntries: 20,
    );
    addTearDown(history.dispose);

    var round = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EditorHistoryScope(
          controller: history,
          child: JsonRepositoryScope(
            store: store,
            child: Scaffold(
              body: DefaultAssetBundle(
                bundle: _MinimalGuideBundle(),
                child: VibeChatDialog(
                  controller: appearance,
                  codec: const AppearanceCodec(),
                  repositoryStore: store,
                  initialQuestioningLevel: VibeQuestioningLevel.none,
                  onClose: () {},
                  onDrag: (_) {},
                  generate: (_) async => '',
                  streamGenerate:
                      (
                        prompt, {
                        systemInstruction,
                        staticGuide,
                        attachments = const [],
                        speedMode = VibeAiSpeedMode.fast,
                      }) async* {
                        round++;
                        if (round == 1) {
                          yield GeminiStreamEvent(
                            deltaText: '',
                            accumulatedText: '',
                            isDone: true,
                            usedContextCache: true,
                            functionCalls: [
                              VibeToolCall(
                                id: 'call-schema-1',
                                name: 'manage_repository_json_schema',
                                arguments: {
                                  'action': 'create',
                                  'repositoryId': repoId,
                                  'schema': {
                                    'type': 'object',
                                    'required': ['nom', 'prix'],
                                    'properties': {
                                      'nom': {'type': 'string'},
                                      'prix': {'type': 'number', 'minimum': 0},
                                    },
                                  },
                                },
                              ),
                            ],
                          );
                          return;
                        }
                        final donePayload = jsonEncode({
                          'message': 'Schéma JSON associé à Produits.',
                          'vibe': null,
                        });
                        yield GeminiStreamEvent(
                          deltaText: donePayload,
                          accumulatedText: donePayload,
                          isDone: true,
                          usedContextCache: true,
                        );
                      },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('vibe-chat-input')),
      'Ajoute un schéma sur Produits',
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();

    expect(find.text('Schéma JSON associé à Produits.'), findsWidgets);
    expect(store.jsonSchemaOf(repoId), isNotNull);

    // Undo annule l'association créée par l'outil.
    await tester.runAsync(() => history.undoAsync());
    expect(store.jsonSchemaOf(repoId), isNull);

    // Redo la rétablit.
    await tester.runAsync(() => history.redoAsync());
    expect(store.jsonSchemaOf(repoId), isNotNull);
  });
}
