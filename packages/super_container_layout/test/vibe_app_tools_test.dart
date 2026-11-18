import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/ai/call_gemini.dart';
import 'package:super_container_layout/ai/vibe_stream_parser.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/services/appearance/appearance_codec.dart';
import 'package:super_container_layout/services/inspection/vibe_app_inspector.dart';
import 'package:super_container_layout/services/inspection/vibe_mounted_slot_index.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_chat_dialog.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';

class _TestGuideBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key.contains('REPOSITORY_JSON_AI_GUIDE.md') ||
        key.contains('SCREEN_DESIGN_AI_GUIDE.md')) {
      return 'Guide secondaire minimal.';
    }
    if (key.contains('SCREEN_JSON_AI_GUIDE.md')) {
      return 'Guide JSON minimal.';
    }
    throw FlutterError('Asset not found: $key');
  }

  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Binary asset not found: $key');
}

class _FakeToolsTransport extends GeminiHttpTransport {
  _FakeToolsTransport({this.onPostJson, this.onPostSseStream});

  final Future<GeminiHttpResponse> Function(
    Uri uri,
    Map<String, Object?> body,
  )?
  onPostJson;
  final Future<GeminiHttpStreamResponse> Function(
    Uri uri,
    Map<String, Object?> body,
  )?
  onPostSseStream;

  final List<Map<String, Object?>> postJsonBodies = <Map<String, Object?>>[];
  final List<Map<String, Object?>> postSseBodies = <Map<String, Object?>>[];

  @override
  Future<GeminiHttpResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) {
    final cloned = jsonDecode(jsonEncode(body)) as Map<String, Object?>;
    postJsonBodies.add(cloned);
    return onPostJson!(uri, cloned);
  }

  @override
  Future<GeminiHttpStreamResponse> postSseStream(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) {
    final cloned = jsonDecode(jsonEncode(body)) as Map<String, Object?>;
    postSseBodies.add(cloned);
    return onPostSseStream!(uri, cloned);
  }
}

void main() {
  tearDown(() {
    VibeMountedSlotIndex.instance.clearForTesting();
  });

  group('VibeAppToolRegistry & VibeIncrementalStreamParser', () {
    test('détecte toolCalls dans VibeIncrementalStreamParser', () {
      final parser = VibeIncrementalStreamParser();
      final s1 = parser.addChunk(
        '{"message":"Inspection...","toolCalls":[{"id":"t1","name":"get_viewport_and_route","arguments":{}}],"vibe":null}',
      );
      expect(s1.message, 'Inspection...');
      expect(s1.isMessageComplete, isTrue);
      expect(s1.hasToolCallsObject, isTrue);
      expect(s1.hasVibeObject, isFalse);
    });

    test('retourne une erreur structurée pour un outil inconnu ou en exception', () async {
      final registry = VibeAppToolRegistry([
        VibeRegisteredTool(
          declaration: const VibeToolDeclaration(
            name: 'boom_tool',
            description: 'Lève une exception',
            parametersSchema: <String, Object?>{'type': 'object'},
          ),
          handler: (_) async => throw StateError('boom'),
        ),
      ]);

      final unknown = await registry.execute(
        VibeToolCall(id: 'c1', name: 'missing_tool'),
      );
      expect(unknown.isError, isTrue);
      expect(unknown.data['error'], contains('missing_tool'));

      final failed = await registry.execute(
        VibeToolCall(id: 'c2', name: 'boom_tool'),
      );
      expect(failed.isError, isTrue);
      expect(failed.data['error'], contains('boom'));
    });
  });

  group('VibeAppInspector (runtime UI & repositories)', () {
    testWidgets(
      'mesure la géométrie réelle, le viewport, l’arbre monté et capture un screenshot PNG',
      (tester) async {
        tester.view.physicalSize = const Size(900, 650);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final appearance = Appearance(
          components: {
            'root_layout': SuperLayoutConfig(
              placements: {
                SuperLayoutZone.center: ['card_1'],
              },
            ),
            'card_1': SuperValueConfig(label: 'Titre', initialText: 'Bonjour'),
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: EditorSlot(
                    id: 'root_layout',
                    label: 'Root Layout',
                    editable: false,
                    child: SizedBox(
                      width: 240,
                      height: 120,
                      child: EditorSlot(
                        id: 'card_1',
                        label: 'Card 1',
                        editable: false,
                        child: Container(
                          color: Colors.indigo,
                          alignment: Alignment.center,
                          child: const Text('Card Content'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final inspector = VibeAppInspector(
          readAppearance: () => appearance,
          fallbackContext: () => tester.element(find.byType(Scaffold)),
        );

        final viewport = await inspector.getViewportAndRoute();
        final vp = viewport['viewport'] as Map<String, Object?>;
        expect(vp['width'], 900.0);
        expect(vp['height'], 650.0);
        expect(viewport['mountedComponentCount'], greaterThanOrEqualTo(2));

        final geo = await inspector.getComponentGeometry({
          'ids': ['card_1', 'not_mounted'],
        });
        final comps = geo['components'] as Map<String, Object?>;
        final cardGeo = comps['card_1'] as Map<String, Object?>;
        expect(cardGeo['mounted'], isTrue);
        expect(cardGeo['occurrenceCount'], 1);
        final occ = (cardGeo['occurrences'] as List).first as Map<String, Object?>;
        final size = occ['size'] as Map<String, Object?>;
        expect(size['width'], 240.0);
        expect(size['height'], 120.0);
        final diagnostics = occ['diagnostics'] as Map<String, Object?>;
        expect(diagnostics['isZeroSized'], isFalse);

        final missingGeo = comps['not_mounted'] as Map<String, Object?>;
        expect(missingGeo['mounted'], isFalse);

        final tree = await inspector.getRuntimeTree({'rootId': 'root_layout'});
        final rootNode = tree['tree'] as Map<String, Object?>;
        expect(rootNode['id'], 'root_layout');
        expect(rootNode['mounted'], isTrue);
        final zones = rootNode['zones'] as Map<String, Object?>;
        final center = zones['center'] as Map<String, Object?>;
        final children = center['children'] as List;
        expect(children, hasLength(1));
        final childNode = children.first as Map<String, Object?>;
        expect(childNode['id'], 'card_1');
        expect((childNode['size'] as Map<String, Object?>)['width'], 240.0);

        final screenshot = await tester.runAsync(
          () => inspector.captureScreenshot(
            'shot-1',
            'capture_screenshot',
            {'componentId': 'card_1', 'maxDimension': 512},
          ),
        );
        expect(screenshot, isNotNull);
        expect(screenshot!.isError, isFalse);
        expect(screenshot.data['logicalWidth'], 240.0);
        expect(screenshot.data['logicalHeight'], 120.0);
        expect(screenshot.attachments, hasLength(1));
        final png = screenshot.attachments.first.bytes;
        // En-tête magique PNG : 89 50 4E 47
        expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      },
    );

    test('interroge le JsonRepositoryStore avec pagination et sélection', () async {
      final tempDir = await Directory.systemTemp.createTemp('vibe_tools_repo_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = JsonRepositoryStore(tempDir);
      addTearDown(store.dispose);
      store.registerRepository(
        RepositoryImpl(
          id: 'clients',
          json: {
            'items': [
              {'name': 'Alice'},
              {'name': 'Bob'},
              {'name': 'Charlie'},
            ],
          },
        ),
      );
      store.bindingOf('clients').array('items').select(const [], 1);

      final inspector = VibeAppInspector(
        readAppearance: () => Appearance(),
        repositoryStore: store,
      );

      final catalog = await inspector.queryRepositoryData(const {});
      expect(catalog['repositoryCount'], 1);
      final repos = catalog['repositories'] as List;
      final first = repos.first as Map<String, Object?>;
      expect(first['id'], 'clients');
      expect((first['selections'] as Map)['items'], [1]);

      final slice = await inspector.queryRepositoryData({
        'repositoryId': 'clients',
        'path': 'items',
        'offset': 1,
        'limit': 1,
      });
      final value = slice['value'] as Map<String, Object?>;
      expect(value['totalCount'], 3);
      expect(value['items'], [
        {'name': 'Bob'},
      ]);
    });
  });

  group('GeminiRestClient (Function Calling & fallback)', () {
    test(
      'inclut tools dans cachedContents, extrait functionCall SSE avec thoughtSignature, et gère le repli responseMimeType',
      () async {
        final now = DateTime.utc(2026, 11, 18, 12);
        var sseCallCount = 0;
        final transport = _FakeToolsTransport(
          onPostJson: (uri, body) async {
            expect(body['tools'], isNotNull);
            expect(body['toolConfig'], isNotNull);
            return GeminiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'name': 'cachedContents/tools-cache-001',
                'expireTime': '2026-11-18T13:00:00Z',
              }),
            );
          },
          onPostSseStream: (uri, body) async {
            sseCallCount++;
            if (sseCallCount == 1) {
              // Simule un modèle qui refuse responseMimeType + tools
              return GeminiHttpStreamResponse.fromString(
                jsonEncode({
                  'error': {
                    'code': 400,
                    'message':
                        'responseMimeType is not supported with function calling',
                  },
                }),
                statusCode: 400,
              );
            }
            return GeminiHttpStreamResponse.fromLines([
              'data: ${jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {
                          'functionCall': {
                            'name': 'get_component_geometry',
                            'args': {
                              'ids': ['card_1'],
                            },
                          },
                          'thoughtSignature': 'sig-abc',
                        },
                      ],
                    },
                  },
                ],
              })}',
              'data: [DONE]',
            ]);
          },
        );

        final client = GeminiRestClient(
          transport: transport,
          clock: () => now,
          apiKeyResolver: () async => 'test-key',
        );
        addTearDown(() => client.close(force: true));

        final events = await client
            .streamGenerate(
              'Quelle est la taille de card_1 ?',
              systemInstruction: 'System',
              staticGuide: 'G' * 9000,
              tools: VibeAppToolRegistry.standardDeclarations,
            )
            .toList();

        expect(transport.postJsonBodies, hasLength(1));
        expect(transport.postSseBodies, hasLength(2));
        // Le second appel SSE doit avoir retiré responseMimeType
        final secondGenConfig =
            transport.postSseBodies[1]['generationConfig'] as Map;
        expect(secondGenConfig.containsKey('responseMimeType'), isFalse);

        final done = events.last;
        expect(done.isDone, isTrue);
        expect(done.functionCalls, hasLength(1));
        expect(done.functionCalls.first.name, 'get_component_geometry');
        expect(done.functionCalls.first.arguments, {
          'ids': ['card_1'],
        });
        expect(done.rawModelParts.first['thoughtSignature'], 'sig-abc');
      },
    );
  });

  group('VibeChatDialog (boucle multi-tours hybride)', () {
    testWidgets(
      'exécute un functionCall natif via streamGenerate puis applique le patch final',
      (tester) async {
        var streamRound = 0;
        final receivedPrompts = <String>[];

        final appearance = ValueNotifier(
          Appearance(
            components: {
              'card_1': SuperValueConfig(label: 'Titre', initialText: 'Initial'),
            },
          ),
        );
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 240,
                    height: 120,
                    child: EditorSlot(
                      id: 'card_1',
                      label: 'Card 1',
                      editable: false,
                      child: const Text('Card Content'),
                    ),
                  ),
                  Expanded(
                    child: DefaultAssetBundle(
                      bundle: _TestGuideBundle(),
                      child: VibeChatDialog(
                        controller: appearance,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (_) => Future.error('Should use stream'),
                        streamGenerate:
                            (
                              prompt, {
                              systemInstruction,
                              staticGuide,
                              attachments = const [],
                              speedMode = VibeAiSpeedMode.fast,
                            }) async* {
                              streamRound++;
                              receivedPrompts.add(prompt);
                              if (streamRound == 1) {
                                yield GeminiStreamEvent(
                                  deltaText: '',
                                  accumulatedText: '',
                                  isDone: true,
                                  usedContextCache: true,
                                  functionCalls: [
                                    VibeToolCall(
                                      id: 'fc-1',
                                      name: 'get_component_geometry',
                                      arguments: const {
                                        'ids': ['card_1'],
                                      },
                                    ),
                                  ],
                                );
                                return;
                              }
                              const finalJson =
                                  '{"message":"Largeur mesurée: 240dp","vibe":{"components":{"card_1":{"type":"value","label":"Titre","text":"240x120"}}}}';
                              yield const GeminiStreamEvent(
                                deltaText: finalJson,
                                accumulatedText: finalJson,
                                isDone: true,
                                usedContextCache: true,
                              );
                            },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Mesure card_1 et mets sa taille dans le texte',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(streamRound, 2);
        expect(receivedPrompts[1], contains('240.0'));
        expect(receivedPrompts[1], contains('120.0'));
        expect(
          (appearance.value.components['card_1'] as SuperValueConfig).initialText,
          '240x120',
        );
      },
    );

    testWidgets(
      'exécute le protocole JSON "toolCalls" via generate puis applique le patch final',
      (tester) async {
        var genRound = 0;
        final receivedPrompts = <String>[];

        final appearance = ValueNotifier(
          Appearance(
            components: {
              'card_1': SuperValueConfig(label: 'Titre', initialText: 'Initial'),
            },
          ),
        );
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 320,
                    height: 90,
                    child: EditorSlot(
                      id: 'card_1',
                      label: 'Card 1',
                      editable: false,
                      child: const Text('Card Content'),
                    ),
                  ),
                  Expanded(
                    child: DefaultAssetBundle(
                      bundle: _TestGuideBundle(),
                      child: VibeChatDialog(
                        controller: appearance,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (prompt) async {
                          genRound++;
                          receivedPrompts.add(prompt);
                          if (genRound == 1) {
                            return jsonEncode({
                              'message': 'Je mesure card_1...',
                              'toolCalls': [
                                {
                                  'id': 'call-1',
                                  'name': 'get_component_geometry',
                                  'arguments': {
                                    'ids': ['card_1'],
                                  },
                                },
                              ],
                              'vibe': null,
                            });
                          }
                          return jsonEncode({
                            'message': 'Fait.',
                            'vibe': {
                              'components': {
                                'card_1': {
                                  'type': 'value',
                                  'label': 'Titre',
                                  'text': '320x90',
                                },
                              },
                            },
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Inspecte card_1',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(genRound, 2);
        expect(receivedPrompts[1], contains('RÉSULTATS DES OUTILS DEMANDÉS'));
        expect(receivedPrompts[1], contains('320.0'));
        expect(
          (appearance.value.components['card_1'] as SuperValueConfig).initialText,
          '320x90',
        );
      },
    );

    testWidgets(
      'respecte le garde-fou maxToolRounds en cas de boucle infinie d’outils',
      (tester) async {
        final appearance = ValueNotifier(Appearance());
        addTearDown(appearance.dispose);

        var totalCalls = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: _TestGuideBundle(),
                child: VibeChatDialog(
                  controller: appearance,
                  codec: const AppearanceCodec(),
                  initialQuestioningLevel: VibeQuestioningLevel.none,
                  onClose: () {},
                  onDrag: (_) {},
                  generate: (prompt) async {
                    totalCalls++;
                    return jsonEncode({
                      'message': 'Encore...',
                      'toolCalls': [
                        {
                          'id': 'loop-$totalCalls',
                          'name': 'get_viewport_and_route',
                          'arguments': const <String, Object?>{},
                        },
                      ],
                      'vibe': null,
                    });
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Boucle infinie',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        // 4 tentatives max * (maxToolRounds + 1) appels = 36, jamais infini
        expect(totalCalls, lessThanOrEqualTo(4 * (VibeChatDialog.maxToolRounds + 1)));
        expect(
          find.textContaining('Nombre maximal d’appels d’outils atteint'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'récupère proprement lorsque des functionCalls natifs dépassent maxToolRounds et réessaie avec les mesures collectées',
      (tester) async {
        var streamRound = 0;
        final receivedPrompts = <String>[];

        final appearance = ValueNotifier(
          Appearance(
            components: {
              'card_1': SuperValueConfig(label: 'Titre', initialText: 'Initial'),
            },
          ),
        );
        addTearDown(appearance.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const SizedBox(
                    width: 240,
                    height: 120,
                    child: EditorSlot(
                      id: 'card_1',
                      label: 'Card 1',
                      editable: false,
                      child: Text('Card'),
                    ),
                  ),
                  Expanded(
                    child: DefaultAssetBundle(
                      bundle: _TestGuideBundle(),
                      child: VibeChatDialog(
                        controller: appearance,
                        codec: const AppearanceCodec(),
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
                              streamRound++;
                              receivedPrompts.add(prompt);
                              if (streamRound <= VibeChatDialog.maxToolRounds + 1) {
                                yield GeminiStreamEvent(
                                  deltaText: '',
                                  accumulatedText: '',
                                  isDone: true,
                                  usedContextCache: true,
                                  functionCalls: [
                                    VibeToolCall(
                                      id: 'fc-$streamRound',
                                      name: 'get_component_geometry',
                                      arguments: const {
                                        'ids': ['card_1'],
                                      },
                                    ),
                                  ],
                                );
                                return;
                              }
                              const finalJson =
                                  '{"message":"Mesure récupérée: 240x120","vibe":{"components":{"card_1":{"type":"value","label":"Titre","text":"240x120"}}}}';
                              yield const GeminiStreamEvent(
                                deltaText: finalJson,
                                accumulatedText: finalJson,
                                isDone: true,
                                usedContextCache: true,
                              );
                            },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Mesure card_1',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        // Tentative 1 : maxToolRounds + 1 tours -> relance Tentative 2 avec les résultats déjà collectés.
        expect(streamRound, VibeChatDialog.maxToolRounds + 2);
        expect(
          receivedPrompts[VibeChatDialog.maxToolRounds],
          contains('limite maximale d’appels d’outils atteinte'),
        );
        expect(
          receivedPrompts.last,
          contains('MESURES D’OUTILS DÉJÀ COLLECTÉES'),
        );
        expect(receivedPrompts.last, contains('240.0'));
        expect(
          (appearance.value.components['card_1'] as SuperValueConfig).initialText,
          '240x120',
        );
        expect(find.text('Mesure récupérée: 240x120'), findsOneWidget);
      },
    );

    test(
      'composeStaticGuide inclut le catalogue et les règles de déclenchement des outils',
      () {
        final guide = VibeChatDialog.composeStaticGuide(
          screenGuide: 'Guide écran.',
        );
        expect(guide, contains('get_component_geometry'));
        expect(guide, contains('capture_screenshot'));
        expect(guide, contains('Règles de décision'));
        expect(guide, contains('"verifyRender": true'));
      },
    );

    test(
      'GeminiRestClient omet responseMimeType dès le 1er appel quand enforceJsonResponse=false',
      () async {
        final transport = _FakeToolsTransport(
          onPostSseStream: (uri, body) async => GeminiHttpStreamResponse.fromLines([
            'data: ${jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'functionCall': {
                          'name': 'get_viewport_and_route',
                          'args': const <String, Object?>{},
                        },
                      },
                    ],
                  },
                },
              ],
            })}',
            'data: [DONE]',
          ]),
        );

        final client = GeminiRestClient(
          transport: transport,
          apiKeyResolver: () async => 'test-key',
        );
        addTearDown(() => client.close(force: true));

        final events = await client
            .streamGenerate(
              'Inspecte le viewport',
              tools: VibeAppToolRegistry.standardDeclarations,
              enforceJsonResponse: false,
            )
            .toList();

        expect(transport.postSseBodies, hasLength(1));
        final genConfig = transport.postSseBodies.first['generationConfig'] as Map;
        expect(genConfig.containsKey('responseMimeType'), isFalse);
        expect(events.last.functionCalls.first.name, 'get_viewport_and_route');
      },
    );

    testWidgets(
      'injecte les EditorSlot montés (y compris codés en dur) dans le prompt du tour',
      (tester) async {
        final appearance = ValueNotifier(Appearance());
        addTearDown(appearance.dispose);
        String? capturedPrompt;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const SizedBox(
                    width: 180,
                    height: 60,
                    child: EditorSlot(
                      id: 'surf_sidebar',
                      label: 'Explorateur',
                      editable: false,
                      child: Text('Sidebar'),
                    ),
                  ),
                  Expanded(
                    child: DefaultAssetBundle(
                      bundle: _TestGuideBundle(),
                      child: VibeChatDialog(
                        controller: appearance,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (prompt) async {
                          capturedPrompt = prompt;
                          return '{"message":"OK","vibe":null}';
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Quelle est la largeur de la barre latérale ?',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(capturedPrompt, contains('Slots montés actuellement à l’écran'));
        expect(capturedPrompt, contains('surf_sidebar (Explorateur)'));
      },
    );

    testWidgets(
      'exécute la passe d’auto-vérification post-rendu via verifyRender: true et applique la correction',
      (tester) async {
        final appearance = ValueNotifier(
          Appearance(
            components: {
              'card_1': SuperValueConfig(label: 'Titre', initialText: 'Initial'),
            },
          ),
        );
        addTearDown(appearance.dispose);

        var callCount = 0;
        final observedPrompts = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const SizedBox(
                    width: 240,
                    height: 100,
                    child: EditorSlot(
                      id: 'card_1',
                      label: 'Card 1',
                      editable: false,
                      child: Text('Card'),
                    ),
                  ),
                  Expanded(
                    child: DefaultAssetBundle(
                      bundle: _TestGuideBundle(),
                      child: VibeChatDialog(
                        controller: appearance,
                        codec: const AppearanceCodec(),
                        initialQuestioningLevel: VibeQuestioningLevel.none,
                        onClose: () {},
                        onDrag: (_) {},
                        generate: (prompt) async {
                          callCount++;
                          observedPrompts.add(prompt);
                          if (callCount == 1) {
                            return jsonEncode({
                              'message': 'Patch appliqué, vérification...',
                              'verifyRender': true,
                              'vibe': {
                                'components': {
                                  'card_1': {
                                    'type': 'value',
                                    'label': 'Titre',
                                    'initialText': 'Brouillon',
                                  },
                                },
                              },
                            });
                          }
                          if (callCount == 2) {
                            return jsonEncode({
                              'message': 'Je mesure card_1...',
                              'toolCalls': [
                                {
                                  'id': 'v-1',
                                  'name': 'get_component_geometry',
                                  'arguments': {
                                    'ids': ['card_1'],
                                  },
                                },
                              ],
                              'vibe': null,
                            });
                          }
                          return jsonEncode({
                            'message': 'Rendu vérifié (240px).',
                            'vibe': {
                              'components': {
                                'card_1': {
                                  'type': 'value',
                                  'label': 'Titre',
                                  'initialText': 'Vérifié 240px',
                                },
                              },
                            },
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('vibe-chat-input')),
          'Mets à jour card_1 puis vérifie sa largeur réelle',
        );
        await tester.tap(find.byKey(const ValueKey('vibe-chat-send')));
        await tester.pumpAndSettle();

        expect(callCount, 3);
        expect(observedPrompts[1], contains('VÉRIFICATION POST-RENDU'));
        expect(observedPrompts[2], contains('240.0'));
        expect(
          (appearance.value.components['card_1'] as SuperValueConfig)
              .initialText,
          'Vérifié 240px',
        );
        expect(find.text('Rendu vérifié (240px).'), findsOneWidget);
      },
    );
  });
}
