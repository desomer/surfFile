import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/ai/gemini_rest_client.dart';

class _RecordedPostCall {
  const _RecordedPostCall({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final Map<String, Object?> body;
}

class _FakeGeminiHttpTransport extends GeminiHttpTransport {
  _FakeGeminiHttpTransport({this.onPostJson, this.onPostSseStream});

  final Future<GeminiHttpResponse> Function(_RecordedPostCall call)? onPostJson;
  final Future<GeminiHttpStreamResponse> Function(_RecordedPostCall call)?
  onPostSseStream;

  final List<_RecordedPostCall> postJsonCalls = <_RecordedPostCall>[];
  final List<_RecordedPostCall> postSseCalls = <_RecordedPostCall>[];
  final List<Uri> warmUpCalls = <Uri>[];
  int closeCount = 0;

  static Map<String, Object?> _cloneBody(Map<String, Object?> body) =>
      jsonDecode(jsonEncode(body)) as Map<String, Object?>;

  @override
  Future<GeminiHttpResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) {
    final recorded = _RecordedPostCall(
      uri: uri,
      headers: Map<String, String>.unmodifiable(headers),
      body: _cloneBody(body),
    );
    postJsonCalls.add(recorded);
    final handler = onPostJson;
    if (handler == null) {
      throw StateError('Unexpected postJson call to $uri');
    }
    return handler(recorded);
  }

  @override
  Future<GeminiHttpStreamResponse> postSseStream(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) {
    final recorded = _RecordedPostCall(
      uri: uri,
      headers: Map<String, String>.unmodifiable(headers),
      body: _cloneBody(body),
    );
    postSseCalls.add(recorded);
    final handler = onPostSseStream;
    if (handler == null) {
      throw StateError('Unexpected postSseStream call to $uri');
    }
    return handler(recorded);
  }

  @override
  Future<void> warmUp(Uri uri) async {
    warmUpCalls.add(uri);
  }

  @override
  void close({bool force = false}) {
    closeCount++;
  }
}

GeminiHttpStreamResponse _sseJsonChunks(List<Map<String, Object?>> chunks) {
  return GeminiHttpStreamResponse.fromLines([
    ': keep-alive',
    '',
    for (final chunk in chunks) 'data: ${jsonEncode(chunk)}',
    'data: [DONE]',
  ]);
}

void main() {
  String? previousGeminiModel;
  var hadDotenvInitialized = false;

  setUp(() {
    hadDotenvInitialized = dotenv.isInitialized;
    previousGeminiModel = dotenv.isInitialized
        ? dotenv.env['GEMINI_MODEL']
        : null;
    if (dotenv.isInitialized) {
      dotenv.env.remove('GEMINI_MODEL');
    }
  });

  tearDown(() {
    if (dotenv.isInitialized) {
      if (previousGeminiModel != null) {
        dotenv.env['GEMINI_MODEL'] = previousGeminiModel!;
      } else {
        dotenv.env.remove('GEMINI_MODEL');
      }
    } else if (hadDotenvInitialized && previousGeminiModel != null) {
      dotenv.loadFromString(
        envString: 'GEMINI_MODEL=$previousGeminiModel',
        isOptional: true,
      );
    }
  });

  group('GeminiRestClient', () {
    final largeGuide = 'G' * 9000;

    test('crée un cachedContent au premier appel, le réutilise au second sans rappeler cachedContents, et omet systemInstruction sur streamGenerateContent', () async {
      final now = DateTime.utc(2026, 11, 13, 12);
      final transport = _FakeGeminiHttpTransport(
        onPostJson: (call) async {
          expect(
            call.uri.toString(),
            'https://generativelanguage.googleapis.com/v1beta/cachedContents',
          );
          expect(call.headers['x-goog-api-key'], 'test-key');
          expect(call.body['model'], 'models/gemini-flash-latest');
          expect(call.body['ttl'], '3600s');
          expect(call.body['systemInstruction'], {
            'parts': [
              {'text': 'Règles système strictes'},
            ],
          });
          return GeminiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'name': 'cachedContents/guide-cache-001',
              'expireTime': '2026-11-13T13:00:00Z',
            }),
          );
        },
        onPostSseStream: (call) async {
          return _sseJsonChunks([
            {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"message":"Cache actif","vibe":null}'},
                    ],
                  },
                },
              ],
              'usageMetadata': {
                'promptTokenCount': 2500,
                'cachedContentTokenCount': 2400,
                'candidatesTokenCount': 12,
                'totalTokenCount': 2512,
              },
            },
          ]);
        },
      );

      final client = GeminiRestClient(
        transport: transport,
        clock: () => now,
        apiKeyResolver: () async => 'test-key',
      );

      // Premier appel : crée cachedContents puis lance streamGenerateContent avec cachedContent.
      final firstEvents = await client
          .streamGenerate(
            'Premier tour utilisateur',
            systemInstruction: 'Règles système strictes',
            staticGuide: largeGuide,
          )
          .toList();

      expect(transport.postJsonCalls, hasLength(1));
      expect(transport.postSseCalls, hasLength(1));
      expect(
        transport.postSseCalls[0].body['cachedContent'],
        'cachedContents/guide-cache-001',
      );
      expect(
        transport.postSseCalls[0].body.containsKey('systemInstruction'),
        isFalse,
      );
      expect(firstEvents, hasLength(2));
      expect(firstEvents.first.usedContextCache, isTrue);
      expect(firstEvents.last.isDone, isTrue);
      expect(firstEvents.last.usedContextCache, isTrue);
      expect(
        firstEvents.last.accumulatedText,
        '{"message":"Cache actif","vibe":null}',
      );

      // Second appel : réutilise cachedContents/guide-cache-001 sans nouveau POST vers cachedContents.
      final secondEvents = await client
          .streamGenerate(
            'Second tour utilisateur',
            systemInstruction: 'Règles système strictes',
            staticGuide: largeGuide,
          )
          .toList();

      expect(transport.postJsonCalls, hasLength(1));
      expect(transport.postSseCalls, hasLength(2));
      expect(
        transport.postSseCalls[1].body['cachedContent'],
        'cachedContents/guide-cache-001',
      );
      expect(
        transport.postSseCalls[1].body.containsKey('systemInstruction'),
        isFalse,
      );
      expect(secondEvents.last.usedContextCache, isTrue);
    });

    test('bascule sur systemInstruction (règles + guide) si cachedContents renvoie HTTP 400 et mémorise le repli au tour suivant', () async {
      final transport = _FakeGeminiHttpTransport(
        onPostJson: (_) async => const GeminiHttpResponse(
          statusCode: 400,
          body: '{"error":{"code":400,"message":"CachedContent token count is too small (minimum 2048)"}}',
        ),
        onPostSseStream: (_) async => _sseJsonChunks([
          {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"message":"Repli OK","vibe":null}'},
                  ],
                },
              },
            ],
          },
        ]),
      );

      final client = GeminiRestClient(
        transport: transport,
        apiKeyResolver: () async => 'test-key',
      );

      // Tour 1 : cachedContents échoue en HTTP 400 -> repli immédiat sur systemInstruction.
      final turn1Events = await client
          .streamGenerate(
            'Demande tour 1',
            systemInstruction: 'Consignes système',
            staticGuide: largeGuide,
          )
          .toList();

      expect(transport.postJsonCalls, hasLength(1));
      expect(transport.postSseCalls, hasLength(1));
      expect(
        transport.postSseCalls[0].body.containsKey('cachedContent'),
        isFalse,
      );
      final sys1 =
          ((transport.postSseCalls[0].body['systemInstruction'] as Map)['parts']
                      as List)
                  .single['text']
              as String;
      expect(sys1, contains('Consignes système'));
      expect(sys1, contains('GUIDE DE MODÉLISATION :\n$largeGuide'));
      expect(turn1Events.last.usedContextCache, isFalse);
      expect(
        turn1Events.last.accumulatedText,
        '{"message":"Repli OK","vibe":null}',
      );

      // Tour 2 : _unsupportedCacheKeys court-circuite cachedContents immédiatement.
      final turn2Events = await client
          .streamGenerate(
            'Demande tour 2',
            systemInstruction: 'Consignes système',
            staticGuide: largeGuide,
          )
          .toList();

      expect(transport.postJsonCalls, hasLength(1));
      expect(transport.postSseCalls, hasLength(2));
      expect(
        transport.postSseCalls[1].body.containsKey('cachedContent'),
        isFalse,
      );
      expect(
        transport.postSseCalls[1].body.containsKey('systemInstruction'),
        isTrue,
      );
      expect(turn2Events.last.usedContextCache, isFalse);
    });

    test('récupère automatiquement lorsqu\'un cachedContent a expiré côté serveur (HTTP 404 CachedContent sur streamGenerateContent)', () async {
      var sseAttempt = 0;
      final transport = _FakeGeminiHttpTransport(
        onPostJson: (_) async => GeminiHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'name': 'cachedContents/server-evicted-99',
            'expireTime': '2099-01-01T00:00:00Z',
          }),
        ),
        onPostSseStream: (call) async {
          sseAttempt++;
          if (sseAttempt == 1) {
            // Premier tour réussi avec le cache.
            return _sseJsonChunks([
              {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': '{"message":"Tour 1","vibe":null}'},
                      ],
                    },
                  },
                ],
              },
            ]);
          }
          if (sseAttempt == 2) {
            // Deuxième tour : le serveur a purgé le CachedContent prématurément -> HTTP 404.
            expect(
              call.body['cachedContent'],
              'cachedContents/server-evicted-99',
            );
            return GeminiHttpStreamResponse.fromString(
              '{"error":{"code":404,"message":"CachedContent cachedContents/server-evicted-99 not found."}}',
              statusCode: 404,
            );
          }
          // Relance automatique sans cachedContent, avec systemInstruction complet.
          expect(call.body.containsKey('cachedContent'), isFalse);
          final sys =
              ((call.body['systemInstruction'] as Map)['parts'] as List)
                      .single['text']
                  as String;
          expect(sys, contains('Règles Vibe'));
          expect(sys, contains('GUIDE DE MODÉLISATION :\n$largeGuide'));
          return _sseJsonChunks([
            {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"message":"Tour 2 récupéré","vibe":null}'},
                    ],
                  },
                },
              ],
            },
          ]);
        },
      );

      final client = GeminiRestClient(
        transport: transport,
        apiKeyResolver: () async => 'test-key',
      );

      final first = await client
          .streamGenerate(
            'Tour 1',
            systemInstruction: 'Règles Vibe',
            staticGuide: largeGuide,
          )
          .toList();
      expect(first.last.usedContextCache, isTrue);

      final second = await client
          .streamGenerate(
            'Tour 2',
            systemInstruction: 'Règles Vibe',
            staticGuide: largeGuide,
          )
          .toList();
      expect(transport.postJsonCalls, hasLength(1));
      expect(transport.postSseCalls, hasLength(3));
      expect(second.last.usedContextCache, isFalse);
      expect(
        second.last.accumulatedText,
        '{"message":"Tour 2 récupéré","vibe":null}',
      );
    });

    test('applique VibeAiSpeedMode (modèles + thinkingBudget), filtre les parts thought:true en SSE, et relance sans thinkingConfig sur HTTP 400 d\'un modèle personnalisé', () async {
      final transport = _FakeGeminiHttpTransport(
        onPostSseStream: (call) async {
          final uriPath = call.uri.path;
          final genConfig =
              call.body['generationConfig'] as Map<String, Object?>;
          expect(genConfig['responseMimeType'], 'application/json');

          if (uriPath.contains('gemini-legacy-custom') &&
              genConfig.containsKey('thinkingConfig')) {
            return GeminiHttpStreamResponse.fromString(
              '{"error":{"code":400,"message":"Invalid JSON payload: thinkingConfig is not supported for this model."}}',
              statusCode: 400,
            );
          }

          return _sseJsonChunks([
            {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'thought': true, 'text': 'BROUILLON INTERNE À IGNORER'},
                      {'text': '{"message":"Salut '},
                    ],
                  },
                },
              ],
            },
            {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'thought': true, 'text': 'SUITE RÉFLEXION'},
                      {'text': 'monde","vibe":null}'},
                    ],
                  },
                },
              ],
            },
          ]);
        },
      );

      final client = GeminiRestClient(
        transport: transport,
        apiKeyResolver: () async => 'test-key',
      );

      // 1. ultraFast -> gemini-flash-lite-latest + thinkingLevel: MINIMAL
      final ultraEvents = await client
          .streamGenerate(
            'Test ultraFast',
            speedMode: VibeAiSpeedMode.ultraFast,
          )
          .toList();
      expect(
        transport.postSseCalls[0].uri.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:streamGenerateContent?alt=sse',
      );
      expect(
        (transport.postSseCalls[0].body['generationConfig']
            as Map)['thinkingConfig'],
        {'thinkingLevel': 'MINIMAL'},
      );
      expect(ultraEvents, [
        const GeminiStreamEvent(
          deltaText: '{"message":"Salut ',
          accumulatedText: '{"message":"Salut ',
          isDone: false,
          usedContextCache: false,
        ),
        const GeminiStreamEvent(
          deltaText: 'monde","vibe":null}',
          accumulatedText: '{"message":"Salut monde","vibe":null}',
          isDone: false,
          usedContextCache: false,
        ),
        const GeminiStreamEvent(
          deltaText: '',
          accumulatedText: '{"message":"Salut monde","vibe":null}',
          isDone: true,
          usedContextCache: false,
        ),
      ]);

      // 2. fast -> gemini-flash-latest + thinkingBudget: 0
      await client.generate('Test fast', speedMode: VibeAiSpeedMode.fast);
      expect(
        transport.postSseCalls[1].uri.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent?alt=sse',
      );
      expect(
        (transport.postSseCalls[1].body['generationConfig']
            as Map)['thinkingConfig'],
        {'thinkingBudget': 0},
      );

      // 3. reasoning -> gemini-flash-latest + thinkingLevel: MEDIUM
      await client.generate(
        'Test reasoning',
        speedMode: VibeAiSpeedMode.reasoning,
      );
      expect(
        transport.postSseCalls[2].uri.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent?alt=sse',
      );
      expect(
        (transport.postSseCalls[2].body['generationConfig']
            as Map)['thinkingConfig'],
        {'thinkingLevel': 'MEDIUM'},
      );

      // 4. Modèle personnalisé via GEMINI_MODEL refusant thinkingConfig (HTTP 400) ->
      // relance automatique sans thinkingConfig, puis mémorisation au tour suivant.
      dotenv.loadFromString(
        envString: 'GEMINI_MODEL=models/gemini-legacy-custom',
        isOptional: true,
      );
      final customText = await client.generate(
        'Test custom model',
        speedMode: VibeAiSpeedMode.reasoning,
      );
      expect(customText, '{"message":"Salut monde","vibe":null}');
      expect(transport.postSseCalls, hasLength(5));
      expect(
        transport.postSseCalls[3].uri.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-legacy-custom:streamGenerateContent?alt=sse',
      );
      expect(
        (transport.postSseCalls[3].body['generationConfig'] as Map).containsKey(
          'thinkingConfig',
        ),
        isTrue,
      );
      expect(
        (transport.postSseCalls[4].body['generationConfig'] as Map).containsKey(
          'thinkingConfig',
        ),
        isFalse,
      );

      // Appel suivant sur ce modèle personnalisé : omet directement thinkingConfig.
      await client.generate('Test custom model 2');
      expect(transport.postSseCalls, hasLength(6));
      expect(
        (transport.postSseCalls[5].body['generationConfig'] as Map).containsKey(
          'thinkingConfig',
        ),
        isFalse,
      );
    });

    test('déduplique la création concurrente de cachedContents entre warmUp et streamGenerate (1 seul POST vers cachedContents)', () async {
      final cacheCreationCompleter = Completer<GeminiHttpResponse>();

      final transport = _FakeGeminiHttpTransport(
        onPostJson: (_) => cacheCreationCompleter.future,
        onPostSseStream: (_) async => _sseJsonChunks([
          {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"message":"Dédupliqué","vibe":null}'},
                  ],
                },
              },
            ],
          },
        ]),
      );

      final client = GeminiRestClient(
        transport: transport,
        apiKeyResolver: () async => 'test-key',
      );

      final warmUpFuture = client.warmUp(
        systemInstruction: 'Règles partagées',
        staticGuide: largeGuide,
        speedMode: VibeAiSpeedMode.fast,
      );
      final streamFuture = client
          .streamGenerate(
            'Prompt concurrent',
            systemInstruction: 'Règles partagées',
            staticGuide: largeGuide,
            speedMode: VibeAiSpeedMode.fast,
          )
          .toList();

      // Laisse les deux appels atteindre l'attente de _inFlightCacheCreations.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(transport.postJsonCalls, hasLength(1));
      expect(transport.postSseCalls, isEmpty);

      cacheCreationCompleter.complete(
        GeminiHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'name': 'cachedContents/shared-inflight-777',
            'expireTime': '2099-01-01T00:00:00Z',
          }),
        ),
      );

      await warmUpFuture;
      final events = await streamFuture;

      expect(transport.postJsonCalls, hasLength(1));
      expect(transport.postSseCalls, hasLength(1));
      expect(
        transport.postSseCalls.single.body['cachedContent'],
        'cachedContents/shared-inflight-777',
      );
      expect(events.last.usedContextCache, isTrue);
      expect(
        events.last.accumulatedText,
        '{"message":"Dédupliqué","vibe":null}',
      );
    });

    test(
      'bascule automatiquement sur le modèle suggéré/secours lors d\'un retrait HTTP 404 ("no longer available") et sur HTTP 400 INVALID_ARGUMENT',
      () async {
        dotenv.loadFromString(
          envString: 'GEMINI_MODEL=gemini-2.5-flash-lite',
          isOptional: true,
        );

        const retiredError = '''
{
  "error": {
    "code": 404,
    "message": "This model models/gemini-2.5-flash-lite is no longer available to new users. Please update your code to use models/gemini-3.5-flash-lite for the latest features and improvements.",
    "status": "NOT_FOUND"
  }
}''';

        final transport = _FakeGeminiHttpTransport(
          onPostJson: (call) async {
            if (call.body['model'] == 'models/gemini-2.5-flash-lite') {
              return const GeminiHttpResponse(
                statusCode: 404,
                body: retiredError,
              );
            }
            expect(call.body['model'], 'models/gemini-3.5-flash-lite');
            return GeminiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'name': 'cachedContents/migrated-35-lite',
                'expireTime': '2099-01-01T00:00:00Z',
              }),
            );
          },
          onPostSseStream: (call) async {
            expect(
              call.uri.toString(),
              'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:streamGenerateContent?alt=sse',
            );
            final genConfig =
                call.body['generationConfig'] as Map<String, Object?>;
            if (genConfig.containsKey('thinkingConfig')) {
              return GeminiHttpStreamResponse.fromString(
                '{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}',
                statusCode: 400,
              );
            }
            return _sseJsonChunks([
              {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': '{"message":"Formulaire B2B créé","vibe":null}'},
                      ],
                    },
                  },
                ],
              },
            ]);
          },
        );

        final client = GeminiRestClient(
          transport: transport,
          apiKeyResolver: () async => 'test-key',
        );

        final events = await client
            .streamGenerate(
              'je veux un formulaire d info client b2b',
              systemInstruction: 'Règles GenUI',
              staticGuide: largeGuide,
              speedMode: VibeAiSpeedMode.ultraFast,
            )
            .toList();

        // 1er cachedContents (2.5-flash-lite -> 404) puis 2e cachedContents (3.5-flash-lite -> 200).
        expect(transport.postJsonCalls, hasLength(2));
        expect(events.last.usedContextCache, isTrue);
        expect(
          events.last.accumulatedText,
          '{"message":"Formulaire B2B créé","vibe":null}',
        );

        // Tour suivant : cible directement gemini-3.5-flash-lite sans repasser par 2.5-flash-lite ni thinkingConfig.
        await client.generate(
          'Ajoute le champ SIRET',
          systemInstruction: 'Règles GenUI',
          staticGuide: largeGuide,
          speedMode: VibeAiSpeedMode.ultraFast,
        );
        expect(transport.postJsonCalls, hasLength(2));
        expect(transport.postSseCalls, hasLength(3));
        expect(
          transport.postSseCalls.last.uri.toString(),
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:streamGenerateContent?alt=sse',
        );
        expect(
          (transport.postSseCalls.last.body['generationConfig'] as Map)
              .containsKey('thinkingConfig'),
          isFalse,
        );
      },
    );
  });
}
