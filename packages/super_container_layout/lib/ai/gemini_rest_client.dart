/// Client REST haute performance pour l'API Gemini `v1beta` (`GeminiRestClient`).
///
/// Fournit une connexion TLS persistante (`Keep-Alive`), le contrôle du budget
/// de réflexion ([VibeAiSpeedMode]), le cache de contexte explicite (`cachedContents`)
/// avec repli automatique sur `systemInstruction`, le streaming SSE incrémental
/// ([GeminiStreamEvent]) et le préchauffage réseau/cache.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'call_gemini.dart' show resolveGeminiApiKey;
import 'vibe_chat_attachment.dart';

/// Modes de vitesse et de raisonnement proposés par l'assistant Vibe IA.
enum VibeAiSpeedMode {
  /// Génération ultra-rapide via `gemini-flash-lite-latest` avec réflexion minimale.
  ultraFast(
    label: 'Éclair',
    tooltip: 'Ultra-rapide (Flash-Lite, sans réflexion)',
    defaultModel: 'gemini-flash-lite-latest',
    fallbackModels: <String>['gemini-3.5-flash-lite', 'gemini-flash-latest'],
    thinkingBudget: 0,
    thinkingConfig: <String, Object?>{'thinkingLevel': 'MINIMAL'},
  ),

  /// Génération rapide par défaut via `gemini-flash-latest` sans budget de réflexion.
  fast(
    label: 'Rapide',
    tooltip: 'Rapide par défaut (Flash, sans réflexion)',
    defaultModel: 'gemini-flash-latest',
    fallbackModels: <String>['gemini-3.5-flash'],
    thinkingBudget: 0,
    thinkingConfig: <String, Object?>{'thinkingBudget': 0},
  ),

  /// Génération avec raisonnement actif pour les écrans et mises en page complexes.
  reasoning(
    label: 'Précis',
    tooltip: 'Raisonnement actif pour écrans complexes',
    defaultModel: 'gemini-flash-latest',
    fallbackModels: <String>['gemini-3.5-flash'],
    thinkingBudget: 2048,
    thinkingConfig: <String, Object?>{'thinkingLevel': 'MEDIUM'},
  );

  /// Crée un mode de vitesse Vibe IA.
  const VibeAiSpeedMode({
    required this.label,
    required this.tooltip,
    required this.defaultModel,
    required this.fallbackModels,
    required this.thinkingBudget,
    required this.thinkingConfig,
  });

  /// Libellé court affiché dans le sélecteur d'interface.
  final String label;

  /// Info-bulle détaillant le compromis vitesse / réflexion.
  final String tooltip;

  /// Identifiant du modèle Gemini glissant utilisé par défaut pour ce mode.
  final String defaultModel;

  /// Chaîne ordonnée de modèles de secours en cas de retrait (HTTP 404) du modèle principal.
  final List<String> fallbackModels;

  /// Budget indicatif de jetons de réflexion associé à ce profil.
  final int thinkingBudget;

  /// Objet `thinkingConfig` adapté au modèle cible dans `generationConfig`.
  final Map<String, Object?> thinkingConfig;
}

/// Événement immuable émis au fil du flux SSE de génération Gemini.
@immutable
class GeminiStreamEvent {
  /// Construit un événement de flux Gemini.
  const GeminiStreamEvent({
    required this.deltaText,
    required this.accumulatedText,
    required this.isDone,
    required this.usedContextCache,
  });

  /// Fragment de texte nouvellement reçu dans ce paquet SSE (vide sur l'événement final).
  final String deltaText;

  /// Texte complet accumulé depuis le début de la réponse.
  final String accumulatedText;

  /// Indique si le flux SSE est terminé.
  final bool isDone;

  /// Indique si la requête a exploité un `cachedContent` explicite côté serveur.
  final bool usedContextCache;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeminiStreamEvent &&
          other.deltaText == deltaText &&
          other.accumulatedText == accumulatedText &&
          other.isDone == isDone &&
          other.usedContextCache == usedContextCache;

  @override
  int get hashCode =>
      Object.hash(deltaText, accumulatedText, isDone, usedContextCache);

  @override
  String toString() =>
      'GeminiStreamEvent(delta: ${deltaText.length} chars, '
      'accumulated: ${accumulatedText.length} chars, '
      'isDone: $isDone, usedContextCache: $usedContextCache)';
}

/// Réponse HTTP complète (statut et corps texte) retournée par [GeminiHttpTransport.postJson].
@immutable
class GeminiHttpResponse {
  /// Construit une réponse HTTP JSON.
  const GeminiHttpResponse({required this.statusCode, required this.body});

  /// Code de statut HTTP (ex. `200`, `400`, `404`).
  final int statusCode;

  /// Corps brut décodé en UTF-8.
  final String body;

  /// Vrai lorsque [statusCode] appartient à la plage `200..299`.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Réponse HTTP en flux retournée par [GeminiHttpTransport.postSseStream].
class GeminiHttpStreamResponse {
  /// Construit une réponse HTTP en flux d'octets.
  const GeminiHttpStreamResponse({
    required this.statusCode,
    required this.byteStream,
  });

  /// Construit une réponse SSE directement à partir de lignes texte (utile pour les tests).
  factory GeminiHttpStreamResponse.fromLines(
    Iterable<String> lines, {
    int statusCode = 200,
  }) {
    final encoded = lines.map((line) => utf8.encode('$line\n')).toList();
    return GeminiHttpStreamResponse(
      statusCode: statusCode,
      byteStream: Stream<List<int>>.fromIterable(encoded),
    );
  }

  /// Construit une réponse HTTP en flux à partir d'un corps texte complet.
  factory GeminiHttpStreamResponse.fromString(
    String body, {
    int statusCode = 200,
  }) {
    return GeminiHttpStreamResponse(
      statusCode: statusCode,
      byteStream: Stream<List<int>>.value(utf8.encode(body)),
    );
  }

  /// Code de statut HTTP de la réponse.
  final int statusCode;

  /// Flux brut d'octets du corps HTTP (lignes SSE lorsque `statusCode` vaut `200`).
  final Stream<List<int>> byteStream;

  /// Vrai lorsque [statusCode] appartient à la plage `200..299`.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Lit et décode l'intégralité du flux en chaîne UTF-8 (pour diagnostiquer une erreur HTTP).
  Future<String> readBodyAsString() => utf8.decoder.bind(byteStream).join();
}

/// Exception levée lorsqu'un appel à l'API REST Gemini échoue avec un statut HTTP d'erreur.
@immutable
class GeminiApiException implements Exception {
  /// Construit une exception d'erreur API Gemini.
  const GeminiApiException({
    required this.statusCode,
    required this.message,
    this.responseBody = '',
  });

  /// Code de statut HTTP retourné par le serveur Gemini.
  final int statusCode;

  /// Message synthétique décrivant l'erreur.
  final String message;

  /// Corps brut éventuel retourné par l'API pour faciliter le diagnostic.
  final String responseBody;

  @override
  String toString() {
    if (responseBody.isEmpty) {
      return 'GeminiApiException(HTTP $statusCode): $message';
    }
    return 'GeminiApiException(HTTP $statusCode): $message — $responseBody';
  }
}

/// Abstraction injectable de transport HTTP/SSE utilisée par [GeminiRestClient].
///
/// Permet de substituer un transport simulé en mémoire dans les tests unitaires
/// sans ouvrir de socket réseau réel.
abstract class GeminiHttpTransport {
  /// Constructeur de base pour les implémentations de transport Gemini.
  const GeminiHttpTransport();

  /// Envoie une requête `POST` JSON et attend le corps complet de la réponse.
  Future<GeminiHttpResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  });

  /// Envoie une requête `POST` JSON et retourne immédiatement les en-têtes/statut et le flux d'octets SSE.
  Future<GeminiHttpStreamResponse> postSseStream(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  });

  /// Préchauffe optionnellement la connexion TCP/TLS vers [uri].
  Future<void> warmUp(Uri uri) async {}

  /// Libère les ressources sous-jacentes éventuelles du transport.
  void close({bool force = false}) {}
}

/// Implémentation de [GeminiHttpTransport] fondée sur `dart:io` [HttpClient] avec Keep-Alive TLS.
class DartIoGeminiHttpTransport extends GeminiHttpTransport {
  /// Crée un transport `dart:io` persistant (5 minutes d'`idleTimeout`, 4 connexions max par hôte).
  DartIoGeminiHttpTransport({HttpClient? httpClient})
    : _injectedClient = httpClient;

  /// Délai maximal de maintien en vie d'une connexion TLS inactive.
  static const Duration defaultIdleTimeout = Duration(minutes: 5);

  /// Nombre maximal de connexions simultanées par hôte Gemini.
  static const int defaultMaxConnectionsPerHost = 4;

  final HttpClient? _injectedClient;
  HttpClient? _ownedClient;
  DateTime? _lastActivityAt;

  HttpClient _ensureClient() {
    if (_injectedClient != null) return _injectedClient;
    var client = _ownedClient;
    if (client == null) {
      client = HttpClient()
        ..idleTimeout = defaultIdleTimeout
        ..maxConnectionsPerHost = defaultMaxConnectionsPerHost;
      _ownedClient = client;
    }
    return client;
  }

  void _touchActivity() {
    _lastActivityAt = DateTime.now();
  }

  @override
  Future<GeminiHttpResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    final client = _ensureClient();
    final request = await client.postUrl(uri);
    request.persistentConnection = true;
    headers.forEach(request.headers.set);
    final payload = utf8.encode(jsonEncode(body));
    request.contentLength = payload.length;
    request.add(payload);
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    _touchActivity();
    return GeminiHttpResponse(
      statusCode: response.statusCode,
      body: responseBody,
    );
  }

  @override
  Future<GeminiHttpStreamResponse> postSseStream(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    final client = _ensureClient();
    final request = await client.postUrl(uri);
    request.persistentConnection = true;
    headers.forEach(request.headers.set);
    final payload = utf8.encode(jsonEncode(body));
    request.contentLength = payload.length;
    request.add(payload);
    final response = await request.close();
    _touchActivity();
    return GeminiHttpStreamResponse(
      statusCode: response.statusCode,
      byteStream: response,
    );
  }

  @override
  Future<void> warmUp(Uri uri) async {
    final last = _lastActivityAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 4)) {
      return;
    }
    final client = _ensureClient();
    final request = await client
        .openUrl('HEAD', uri)
        .timeout(const Duration(seconds: 5));
    request.persistentConnection = true;
    final response = await request.close().timeout(const Duration(seconds: 5));
    await response.drain<void>();
    _touchActivity();
  }

  @override
  void close({bool force = false}) {
    _ownedClient?.close(force: force);
    _ownedClient = null;
    _lastActivityAt = null;
  }
}

@immutable
class _CachedContentEntry {
  const _CachedContentEntry({required this.name, required this.expiresAt});

  final String name;
  final DateTime expiresAt;
}

/// Client REST Gemini `v1beta` gérant le Keep-Alive TLS, `cachedContents` et le flux SSE.
class GeminiRestClient {
  /// Crée une instance configurable de [GeminiRestClient] (injectable pour les tests).
  GeminiRestClient({
    GeminiHttpTransport? transport,
    this.minGuideCharsForExplicitCache = defaultMinGuideCharsForExplicitCache,
    DateTime Function()? clock,
    Future<String> Function()? apiKeyResolver,
  }) : _transport = transport ?? DartIoGeminiHttpTransport(),
       _clock = clock ?? DateTime.now,
       _apiKeyResolver = apiKeyResolver ?? resolveGeminiApiKey;

  /// Instance singleton partagée par défaut dans l'application.
  static final GeminiRestClient instance = GeminiRestClient();

  /// Taille minimale (en caractères) du guide statique pour tenter `cachedContents` (~2 000+ jetons).
  static const int defaultMinGuideCharsForExplicitCache = 8192;

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta';
  static final Uri _baseUri = Uri.parse(_baseUrl);
  static final Uri _cachedContentsUri = Uri.parse('$_baseUrl/cachedContents');

  static const Duration _cacheReuseSafetyMargin = Duration(minutes: 2);
  static const Duration _defaultCacheTtl = Duration(seconds: 3600);

  /// Seuil minimal de longueur de `staticGuide` requis pour activer le cache explicite.
  final int minGuideCharsForExplicitCache;

  final GeminiHttpTransport _transport;
  final DateTime Function() _clock;
  final Future<String> Function() _apiKeyResolver;

  final Map<String, _CachedContentEntry> _activeCaches =
      <String, _CachedContentEntry>{};
  final Map<String, Future<String?>> _inFlightCacheCreations =
      <String, Future<String?>>{};
  final Set<String> _unsupportedCacheKeys = <String>{};
  final Set<String> _unsupportedThinkingModels = <String>{};
  final Set<String> _unsupportedThinkingConfigs = <String>{};
  final Set<String> _unavailableModels = <String>{};
  final Map<String, String> _suggestedReplacementModels = <String, String>{};

  /// Retourne la liste ordonnée et dédupliquée des modèles candidats actifs pour [speedMode].
  List<String> resolveModelCandidates(VibeAiSpeedMode speedMode) {
    final candidates = <String>[];
    void addCandidate(String? raw) {
      if (raw == null) return;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return;
      final normalized = trimmed.startsWith('models/')
          ? trimmed.substring('models/'.length)
          : trimmed;
      if (normalized.isNotEmpty && !candidates.contains(normalized)) {
        candidates.add(normalized);
      }
      final replacement = _suggestedReplacementModels[normalized];
      if (replacement != null && !candidates.contains(replacement)) {
        candidates.add(replacement);
      }
    }

    if (dotenv.isInitialized) {
      addCandidate(dotenv.env['GEMINI_MODEL']);
    }
    addCandidate(speedMode.defaultModel);
    for (final fallback in speedMode.fallbackModels) {
      addCandidate(fallback);
    }

    final available = candidates
        .where((m) => !_unavailableModels.contains(m))
        .toList();
    return available.isNotEmpty ? available : <String>[candidates.last];
  }

  /// Résout l'identifiant du modèle Gemini actif pour [speedMode] en tenant compte de `GEMINI_MODEL` et des replis 404.
  String resolveModel(VibeAiSpeedMode speedMode) =>
      resolveModelCandidates(speedMode).first;

  void _markModelUnavailable(String model, String errorBody) {
    _unavailableModels.add(model);
    final suggested = _extractSuggestedModel(errorBody, currentModel: model);
    if (suggested != null) {
      _suggestedReplacementModels[model] = suggested;
    }
  }

  /// Vide les caches de contexte actifs et les mémorisations de repli en mémoire.
  void clearCaches() {
    _activeCaches.clear();
    _inFlightCacheCreations.clear();
    _unsupportedCacheKeys.clear();
    _unsupportedThinkingModels.clear();
    _unsupportedThinkingConfigs.clear();
    _unavailableModels.clear();
    _suggestedReplacementModels.clear();
  }

  /// Ferme le transport HTTP sous-jacent et réinitialise l'état en mémoire.
  void close({bool force = false}) {
    clearCaches();
    _transport.close(force: force);
  }

  /// Préchauffe silencieusement la connexion TLS Keep-Alive et le `cachedContent` éventuel.
  ///
  /// Ne lève jamais d'exception vers l'appelant : toute erreur réseau ou de configuration
  /// est interceptée et journalisée via [debugPrint].
  Future<void> warmUp({
    String? apiKey,
    String? systemInstruction,
    String? staticGuide,
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  }) async {
    try {
      final resolvedKey = (apiKey ?? await _apiKeyResolver()).trim();
      if (resolvedKey.isEmpty) {
        debugPrint(
          '[Vibe IA][Gemini REST] warmUp ignoré : clé GEMINI_API_KEY absente.',
        );
        return;
      }
      var model = resolveModel(speedMode);
      if (staticGuide != null &&
          staticGuide.trim().isNotEmpty &&
          staticGuide.length >= minGuideCharsForExplicitCache) {
        final cacheKey = _buildCacheKey(
          model: model,
          systemInstruction: systemInstruction,
          staticGuide: staticGuide,
        );
        final existing = _activeCaches[cacheKey];
        final now = _clock();
        if (existing != null &&
            existing.expiresAt.isAfter(now.add(_cacheReuseSafetyMargin))) {
          return;
        }
        if (!_unsupportedCacheKeys.contains(cacheKey)) {
          final created = await ensureCachedContent(
            apiKey: resolvedKey,
            model: model,
            systemInstruction: systemInstruction,
            staticGuide: staticGuide,
          );
          if (created == null && _unavailableModels.contains(model)) {
            final nextModel = resolveModel(speedMode);
            if (nextModel != model) {
              model = nextModel;
              await ensureCachedContent(
                apiKey: resolvedKey,
                model: model,
                systemInstruction: systemInstruction,
                staticGuide: staticGuide,
              );
            }
          }
          return;
        }
      }
      await _transport.warmUp(_baseUri);
    } catch (error) {
      debugPrint('[Vibe IA][Gemini REST] warmUp ignoré après erreur : $error');
    }
  }

  /// Crée ou réutilise un `cachedContent` explicite pour [model], [systemInstruction] et [staticGuide].
  ///
  /// Retourne le nom de ressource (`cachedContents/...`) en cas de succès, ou `null`
  /// lorsque [staticGuide] est trop court ou que l'API refuse la mise en cache.
  Future<String?> ensureCachedContent({
    required String apiKey,
    required String model,
    String? systemInstruction,
    String? staticGuide,
  }) async {
    if (staticGuide == null ||
        staticGuide.trim().isEmpty ||
        staticGuide.length < minGuideCharsForExplicitCache) {
      return null;
    }

    final cacheKey = _buildCacheKey(
      model: model,
      systemInstruction: systemInstruction,
      staticGuide: staticGuide,
    );
    if (_unsupportedCacheKeys.contains(cacheKey)) {
      return null;
    }

    final now = _clock();
    final existing = _activeCaches[cacheKey];
    if (existing != null) {
      if (existing.expiresAt.isAfter(now.add(_cacheReuseSafetyMargin))) {
        return existing.name;
      }
      _activeCaches.remove(cacheKey);
    }

    final inFlight = _inFlightCacheCreations[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _createCachedContent(
      cacheKey: cacheKey,
      apiKey: apiKey,
      model: model,
      systemInstruction: systemInstruction,
      staticGuide: staticGuide,
    );
    _inFlightCacheCreations[cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightCacheCreations[cacheKey], future)) {
        _inFlightCacheCreations.remove(cacheKey);
      }
    }
  }

  Future<String?> _createCachedContent({
    required String cacheKey,
    required String apiKey,
    required String model,
    required String? systemInstruction,
    required String staticGuide,
  }) async {
    final stopwatch = Stopwatch()..start();
    final requestBody = <String, Object?>{
      'model': 'models/$model',
      if (systemInstruction != null && systemInstruction.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'GUIDE DE MODÉLISATION DE RÉFÉRENCE :\n$staticGuide'},
          ],
        },
        {
          'role': 'model',
          'parts': [
            {'text': '{"message":"Guide prêt.","vibe":null}'},
          ],
        },
      ],
      'ttl': '3600s',
    };

    try {
      final response = await _transport.postJson(
        _cachedContentsUri,
        headers: _jsonHeaders(apiKey),
        body: requestBody,
      );
      stopwatch.stop();

      if (!response.isSuccess) {
        if (response.statusCode == 404 &&
            _isModelNotFoundError(response.body)) {
          _markModelUnavailable(model, response.body);
        }
        _unsupportedCacheKeys.add(cacheKey);
        debugPrint(
          '[Vibe IA][Gemini REST] cachedContents indisponible '
          '(HTTP ${response.statusCode} en ${stopwatch.elapsedMilliseconds} ms), '
          'repli sur systemInstruction.',
        );
        return null;
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _unsupportedCacheKeys.add(cacheKey);
        return null;
      }
      final name = decoded['name'];
      if (name is! String || name.trim().isEmpty) {
        _unsupportedCacheKeys.add(cacheKey);
        return null;
      }

      final expireTimeRaw = decoded['expireTime'];
      final expiresAt =
          (expireTimeRaw is String ? DateTime.tryParse(expireTimeRaw) : null) ??
          _clock().add(_defaultCacheTtl);

      _activeCaches[cacheKey] = _CachedContentEntry(
        name: name,
        expiresAt: expiresAt,
      );
      debugPrint(
        '[Vibe IA][Gemini REST] cachedContent prêt ($name) en '
        '${stopwatch.elapsedMilliseconds} ms (modèle: $model).',
      );
      return name;
    } catch (error) {
      stopwatch.stop();
      _unsupportedCacheKeys.add(cacheKey);
      debugPrint(
        '[Vibe IA][Gemini REST] Échec de cachedContents après '
        '${stopwatch.elapsedMilliseconds} ms ($error), '
        'repli sur systemInstruction.',
      );
      return null;
    }
  }

  /// Génère une réponse JSON en streaming SSE incrémental ([GeminiStreamEvent]).
  ///
  /// Utilise automatiquement un `cachedContent` lorsque [staticGuide] dépasse
  /// [minGuideCharsForExplicitCache], et bascule sans coupure sur `systemInstruction`
  /// ou sans `thinkingConfig` si l'API le requiert.
  Stream<GeminiStreamEvent> streamGenerate(
    String prompt, {
    String? apiKey,
    String? systemInstruction,
    String? staticGuide,
    List<VibeChatAttachment> attachments = const [],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  }) async* {
    final resolvedKey = (apiKey ?? await _apiKeyResolver()).trim();
    if (resolvedKey.isEmpty) {
      debugPrint(
        '[Vibe IA][Gemini REST] Clé GEMINI_API_KEY absente '
        '(dotenv.isInitialized=${dotenv.isInitialized}).',
      );
      throw Exception('GEMINI_API_KEY dotenv is not defined');
    }

    var model = resolveModel(speedMode);
    final triedModels = <String>{model};
    final totalStopwatch = Stopwatch()..start();

    final hasCacheableGuide =
        staticGuide != null &&
        staticGuide.trim().isNotEmpty &&
        staticGuide.length >= minGuideCharsForExplicitCache;

    String? cacheKey = hasCacheableGuide
        ? _buildCacheKey(
            model: model,
            systemInstruction: systemInstruction,
            staticGuide: staticGuide,
          )
        : null;

    var cachedContentName = await ensureCachedContent(
      apiKey: resolvedKey,
      model: model,
      systemInstruction: systemInstruction,
      staticGuide: staticGuide,
    );

    if (cachedContentName == null && _unavailableModels.contains(model)) {
      final fallback = resolveModelCandidates(speedMode)
          .where((m) => !triedModels.contains(m))
          .firstOrNull;
      if (fallback != null) {
        debugPrint(
          '[Vibe IA][Gemini REST] Modèle $model retiré lors du cache (HTTP 404), '
          'bascule automatique vers $fallback.',
        );
        model = fallback;
        triedModels.add(model);
        cacheKey = hasCacheableGuide
            ? _buildCacheKey(
                model: model,
                systemInstruction: systemInstruction,
                staticGuide: staticGuide,
              )
            : null;
        cachedContentName = await ensureCachedContent(
          apiKey: resolvedKey,
          model: model,
          systemInstruction: systemInstruction,
          staticGuide: staticGuide,
        );
      }
    }

    final userParts = _buildUserParts(prompt, attachments);
    var streamUri = Uri.parse(
      '$_baseUrl/models/$model:streamGenerateContent?alt=sse',
    );

    var retriedWithoutCache = false;
    var retriedWithoutThinking = false;
    late GeminiHttpStreamResponse streamResponse;

    while (true) {
      final thinkingKey = '$model|${speedMode.name}';
      final includeThinking =
          !_unsupportedThinkingModels.contains(model) &&
          !_unsupportedThinkingConfigs.contains(thinkingKey);
      final requestBody = _buildGenerateRequestBody(
        userParts: userParts,
        cachedContentName: cachedContentName,
        systemInstruction: systemInstruction,
        staticGuide: staticGuide,
        speedMode: speedMode,
        includeThinkingConfig: includeThinking,
      );

      streamResponse = await _transport.postSseStream(
        streamUri,
        headers: _sseHeaders(resolvedKey),
        body: requestBody,
      );

      if (streamResponse.isSuccess) {
        break;
      }

      final errorBody = await streamResponse.readBodyAsString();
      final status = streamResponse.statusCode;

      if (status == 404 && _isModelNotFoundError(errorBody)) {
        _markModelUnavailable(model, errorBody);
        final nextModel = resolveModelCandidates(speedMode)
            .where((m) => !triedModels.contains(m))
            .firstOrNull;
        if (nextModel != null) {
          debugPrint(
            '[Vibe IA][Gemini REST] Modèle $model indisponible (HTTP 404), '
            'bascule automatique vers $nextModel.',
          );
          model = nextModel;
          triedModels.add(model);
          cacheKey = hasCacheableGuide
              ? _buildCacheKey(
                  model: model,
                  systemInstruction: systemInstruction,
                  staticGuide: staticGuide,
                )
              : null;
          cachedContentName = await ensureCachedContent(
            apiKey: resolvedKey,
            model: model,
            systemInstruction: systemInstruction,
            staticGuide: staticGuide,
          );
          streamUri = Uri.parse(
            '$_baseUrl/models/$model:streamGenerateContent?alt=sse',
          );
          retriedWithoutCache = false;
          retriedWithoutThinking = false;
          continue;
        }
      }

      if (cachedContentName != null &&
          !retriedWithoutCache &&
          (status == 404 ||
              (status == 400 && _mentionsCachedContent(errorBody)))) {
        if (cacheKey != null) {
          _activeCaches.remove(cacheKey);
        }
        debugPrint(
          '[Vibe IA][Gemini REST] cachedContent expiré ou invalide '
          '(HTTP $status), éviction et nouvelle tentative avec systemInstruction.',
        );
        cachedContentName = null;
        retriedWithoutCache = true;
        continue;
      }

      if (includeThinking &&
          !retriedWithoutThinking &&
          status == 400 &&
          (_mentionsThinkingConfig(errorBody) ||
              _isGenericInvalidArgument(errorBody))) {
        _unsupportedThinkingConfigs.add(thinkingKey);
        if (_mentionsModelWideThinkingUnsupported(errorBody)) {
          _unsupportedThinkingModels.add(model);
        }
        debugPrint(
          '[Vibe IA][Gemini REST] Modèle $model incompatible avec thinkingConfig '
          '(HTTP 400), nouvelle tentative sans thinkingConfig.',
        );
        retriedWithoutThinking = true;
        continue;
      }

      totalStopwatch.stop();
      debugPrint(
        '[Vibe IA][Gemini REST] Échec HTTP $status après '
        '${totalStopwatch.elapsedMilliseconds} ms : $errorBody',
      );
      throw GeminiApiException(
        statusCode: status,
        message: _extractApiErrorMessage(errorBody) ?? 'HTTP $status',
        responseBody: errorBody,
      );
    }

    final usedCache = cachedContentName != null;
    final accumulatedBuffer = StringBuffer();
    int? ttftMs;
    Map<String, dynamic>? lastUsageMetadata;

    final lineStream = utf8.decoder
        .bind(streamResponse.byteStream)
        .transform(const LineSplitter());

    await for (final rawLine in lineStream) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith(':')) {
        continue;
      }
      if (!line.startsWith('data:')) {
        continue;
      }
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') {
        continue;
      }

      final Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException catch (error) {
        debugPrint(
          '[Vibe IA][Gemini REST] Ligne SSE JSON ignorée (${error.message}).',
        );
        continue;
      }
      if (decoded is! Map<String, dynamic>) {
        continue;
      }

      if (decoded['error'] case final Map<Object?, Object?> errorMap
          when decoded['candidates'] == null) {
        final code = (errorMap['code'] as num?)?.toInt() ?? 500;
        final message =
            errorMap['message']?.toString() ?? 'Erreur du flux SSE Gemini';
        throw GeminiApiException(
          statusCode: code,
          message: message,
          responseBody: payload,
        );
      }

      if (decoded['usageMetadata'] case final Map<String, dynamic> usage) {
        lastUsageMetadata = usage;
      }

      final chunkText = _extractCandidateChunkText(decoded);
      if (chunkText.isNotEmpty) {
        ttftMs ??= totalStopwatch.elapsedMilliseconds;
        accumulatedBuffer.write(chunkText);
        yield GeminiStreamEvent(
          deltaText: chunkText,
          accumulatedText: accumulatedBuffer.toString(),
          isDone: false,
          usedContextCache: usedCache,
        );
      }
    }

    totalStopwatch.stop();
    final usageSummary = _formatUsageSummary(lastUsageMetadata);
    debugPrint(
      '[Vibe IA][Gemini REST] $model (${speedMode.name}) terminé — '
      'TTFT: ${ttftMs ?? totalStopwatch.elapsedMilliseconds} ms, '
      'total: ${totalStopwatch.elapsedMilliseconds} ms, '
      'cache: ${usedCache ? "HIT" : "MISS"}'
      '${usageSummary.isEmpty ? "" : ", $usageSummary"}.',
    );

    yield GeminiStreamEvent(
      deltaText: '',
      accumulatedText: accumulatedBuffer.toString(),
      isDone: true,
      usedContextCache: usedCache,
    );
  }

  /// Génère la réponse complète sous forme de chaîne unique en consommant [streamGenerate].
  Future<String> generate(
    String prompt, {
    String? apiKey,
    List<VibeChatAttachment> attachments = const [],
    String? systemInstruction,
    String? staticGuide,
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  }) async {
    var result = '';
    await for (final event in streamGenerate(
      prompt,
      apiKey: apiKey,
      systemInstruction: systemInstruction,
      staticGuide: staticGuide,
      attachments: attachments,
      speedMode: speedMode,
    )) {
      result = event.accumulatedText;
    }
    return result;
  }

  static Map<String, String> _jsonHeaders(String apiKey) => <String, String>{
    'x-goog-api-key': apiKey,
    'Content-Type': 'application/json; charset=utf-8',
  };

  static Map<String, String> _sseHeaders(String apiKey) => <String, String>{
    'x-goog-api-key': apiKey,
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'text/event-stream',
  };

  static List<Map<String, Object?>> _buildUserParts(
    String prompt,
    List<VibeChatAttachment> attachments,
  ) {
    final parts = <Map<String, Object?>>[
      {'text': prompt},
    ];
    for (final a in attachments) {
      if (a.isImage) {
        parts.add({
          'text': 'Fichier image joint : "${a.name}" (${a.mimeType})',
        });
        parts.add({
          'inlineData': {'mimeType': a.mimeType, 'data': base64Encode(a.bytes)},
        });
      } else if (a.isText && !prompt.contains(a.textContent!)) {
        parts.add({
          'text':
              'Fichier texte joint "${a.name}" (${a.mimeType}) :\n'
              '${a.textContent}',
        });
      }
    }
    return parts;
  }

  static Map<String, Object?> _buildGenerateRequestBody({
    required List<Map<String, Object?>> userParts,
    required String? cachedContentName,
    required String? systemInstruction,
    required String? staticGuide,
    required VibeAiSpeedMode speedMode,
    required bool includeThinkingConfig,
  }) {
    final body = <String, Object?>{};

    if (cachedContentName != null) {
      body['cachedContent'] = cachedContentName;
    } else {
      final combinedSystem = [
        if (systemInstruction != null && systemInstruction.trim().isNotEmpty)
          systemInstruction.trim(),
        if (staticGuide != null && staticGuide.trim().isNotEmpty)
          'GUIDE DE MODÉLISATION :\n$staticGuide',
      ].join('\n\n');
      if (combinedSystem.isNotEmpty) {
        body['systemInstruction'] = {
          'parts': [
            {'text': combinedSystem},
          ],
        };
      }
    }

    body['contents'] = [
      {'role': 'user', 'parts': userParts},
    ];

    body['generationConfig'] = <String, Object?>{
      'temperature': 0.15,
      'responseMimeType': 'application/json',
      if (includeThinkingConfig) 'thinkingConfig': speedMode.thinkingConfig,
    };

    return body;
  }

  static String _extractCandidateChunkText(Map<String, dynamic> chunk) {
    final candidates = chunk['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final first = candidates.first;
    if (first is! Map) return '';
    final content = first['content'];
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) return '';

    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map && part['thought'] != true) {
        final text = part['text'];
        if (text is String && text.isNotEmpty) {
          buffer.write(text);
        }
      }
    }
    return buffer.toString();
  }

  static bool _mentionsCachedContent(String errorBody) =>
      errorBody.contains('cachedContent') ||
      errorBody.contains('CachedContent') ||
      errorBody.contains('cached_content');

  static bool _mentionsThinkingConfig(String errorBody) {
    final lower = errorBody.toLowerCase();
    return lower.contains('thinkingconfig') ||
        lower.contains('thinkingbudget') ||
        lower.contains('thinkinglevel') ||
        lower.contains('thinking_config') ||
        lower.contains('thinking_budget') ||
        lower.contains('thinking_level') ||
        lower.contains('thinking');
  }

  static bool _mentionsModelWideThinkingUnsupported(String errorBody) {
    final lower = errorBody.toLowerCase();
    return lower.contains('thinkingconfig') ||
        lower.contains('thinking_config');
  }

  static bool _isGenericInvalidArgument(String errorBody) {
    final lower = errorBody.toLowerCase();
    return lower.contains('request contains an invalid argument') ||
        lower.contains('"status": "invalid_argument"') ||
        lower.contains('"status":"invalid_argument"');
  }

  static bool _isModelNotFoundError(String errorBody) {
    if (_mentionsCachedContent(errorBody)) return false;
    final lower = errorBody.toLowerCase();
    return lower.contains('no longer available') ||
        lower.contains('is not found') ||
        lower.contains('models/') ||
        lower.contains('"status": "not_found"') ||
        lower.contains('"status":"not_found"');
  }

  static final RegExp _suggestedModelPattern = RegExp(
    r'use\s+models/([A-Za-z0-9._-]+)',
    caseSensitive: false,
  );

  static String? _extractSuggestedModel(
    String errorBody, {
    required String currentModel,
  }) {
    final match = _suggestedModelPattern.firstMatch(errorBody);
    final candidate = match?.group(1)?.trim();
    if (candidate == null || candidate.isEmpty || candidate == currentModel) {
      return null;
    }
    return candidate;
  }

  static String? _extractApiErrorMessage(String errorBody) {
    if (errorBody.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(errorBody);
      if (decoded is Map && decoded['error'] is Map) {
        final message = (decoded['error'] as Map)['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  static String _formatUsageSummary(Map<String, dynamic>? usage) {
    if (usage == null || usage.isEmpty) return '';
    final promptTokens = usage['promptTokenCount'];
    final cachedTokens = usage['cachedContentTokenCount'];
    final candidateTokens = usage['candidatesTokenCount'];
    final thoughtTokens = usage['thoughtsTokenCount'];
    final totalTokens = usage['totalTokenCount'];
    final metrics = <String>[
      if (promptTokens != null) 'prompt=$promptTokens',
      if (cachedTokens != null) 'cached=$cachedTokens',
      if (candidateTokens != null) 'réponse=$candidateTokens',
      if (thoughtTokens != null) 'réflexion=$thoughtTokens',
      if (totalTokens != null) 'total=$totalTokens',
    ];
    return metrics.isEmpty ? '' : 'tokens(${metrics.join(", ")})';
  }

  static String _buildCacheKey({
    required String model,
    required String? systemInstruction,
    required String? staticGuide,
  }) =>
      '$model|${_stableHash(systemInstruction ?? '')}|'
      '${_stableHash(staticGuide ?? '')}';

  static String _stableHash(String input) {
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (var i = 0; i < input.length; i++) {
      final unit = input.codeUnitAt(i);
      h1 = ((h1 ^ unit) * 0x01000193) & 0xffffffff;
      h2 = ((h2 ^ (unit + i)) * 0x85ebca6b) & 0xffffffff;
    }
    return '${input.length}_'
        '${h1.toRadixString(16).padLeft(8, '0')}'
        '${h2.toRadixString(16).padLeft(8, '0')}';
  }
}
