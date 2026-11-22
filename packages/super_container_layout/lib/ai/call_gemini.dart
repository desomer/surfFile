/// Points d'entrée d'appel au modèle génératif Gemini pour l'assistant Vibe IA.
///
/// Expose la résolution mise en cache de `GEMINI_API_KEY` ([resolveGeminiApiKey]),
/// le préchauffage réseau/cache ([warmUpGemini]), le flux SSE incrémental
/// ([streamGemini]) et l'appel complet rétrocompatible ([callGemini]) appuyés sur
/// [GeminiRestClient].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'gemini_rest_client.dart';
import 'vibe_app_tools.dart';
import 'vibe_chat_attachment.dart';

export 'gemini_rest_client.dart';
export 'vibe_app_tools.dart';
export 'vibe_chat_attachment.dart';

const String _dartDefineGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

String? _cachedGeminiApiKey;
Future<String>? _inFlightApiKeyResolution;

/// Réinitialise la clé `GEMINI_API_KEY` mémorisée en mémoire par [resolveGeminiApiKey].
void resetGeminiApiKeyCache() {
  _cachedGeminiApiKey = null;
  _inFlightApiKeyResolution = null;
}

/// Résout la clé d'API Gemini en interrogeant dans l'ordre :
/// 1. Les variables déjà chargées dans [dotenv] (`GEMINI_API_KEY`), prioritaires en test/hot-reload.
/// 2. La clé précédemment résolue et mise en cache en mémoire.
/// 3. Les variables d'environnement système (`Platform.environment['GEMINI_API_KEY']`).
/// 4. La constante de compilation `--dart-define=GEMINI_API_KEY=...`.
/// 5. Les fichiers `env` ou `.env` découverts depuis le répertoire courant,
///    le répertoire de l'exécutable (`Platform.resolvedExecutable`), leurs ancêtres
///    et le dossier utilisateur `.super_container_layout`.
Future<String> resolveGeminiApiKey() async {
  if (dotenv.isInitialized) {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key != null && key.trim().isNotEmpty) {
      final trimmed = key.trim();
      _cachedGeminiApiKey = trimmed;
      return trimmed;
    }
  }

  final cached = _cachedGeminiApiKey;
  if (cached != null && cached.isNotEmpty) {
    _populateDotenvKey(cached);
    return cached;
  }

  final inFlight = _inFlightApiKeyResolution;
  if (inFlight != null) {
    return inFlight;
  }

  final future = _discoverGeminiApiKey();
  _inFlightApiKeyResolution = future;
  try {
    final resolved = await future;
    if (resolved.isNotEmpty) {
      _cachedGeminiApiKey = resolved;
    }
    return resolved;
  } finally {
    if (identical(_inFlightApiKeyResolution, future)) {
      _inFlightApiKeyResolution = null;
    }
  }
}

void _populateDotenvKey(String key) {
  if (!dotenv.isInitialized) {
    dotenv.loadFromString(
      envString: '',
      isOptional: true,
      mergeWith: {'GEMINI_API_KEY': key},
    );
  } else if ((dotenv.env['GEMINI_API_KEY'] ?? '').trim().isEmpty) {
    dotenv.env['GEMINI_API_KEY'] = key;
  }
}

Future<String> _discoverGeminiApiKey() {
  String? currentDir;
  String? executablePath;
  if (!kIsWeb) {
    try {
      currentDir = Directory.current.path;
    } catch (_) {}
    try {
      executablePath = Platform.resolvedExecutable;
    } catch (_) {}
  }
  final environment = kIsWeb ? const <String, String>{} : Platform.environment;
  return discoverGeminiApiKeyForTesting(
    environment: environment,
    dartDefineKey: _dartDefineGeminiApiKey,
    currentDirectoryPath: currentDir,
    executablePath: executablePath,
    homeDirectoryPath: environment['USERPROFILE'] ?? environment['HOME'],
  );
}

/// Recherche `GEMINI_API_KEY` à partir de sources configurables (exposée pour les tests unitaires).
@visibleForTesting
Future<String> discoverGeminiApiKeyForTesting({
  required Map<String, String> environment,
  String dartDefineKey = '',
  String? currentDirectoryPath,
  String? executablePath,
  String? homeDirectoryPath,
  bool isWeb = kIsWeb,
}) async {
  final envKey = environment['GEMINI_API_KEY'];
  if (envKey != null && envKey.trim().isNotEmpty) {
    final key = envKey.trim();
    _populateDotenvKey(key);
    return key;
  }

  final definedKey = dartDefineKey.trim();
  if (definedKey.isNotEmpty) {
    _populateDotenvKey(definedKey);
    return definedKey;
  }

  if (isWeb) {
    return '';
  }

  final sep = Platform.pathSeparator;
  final seenPaths = <String>{};
  final candidatePaths = <String>[];

  void addCandidate(String path) {
    final normalizedKey = Platform.isWindows ? path.toLowerCase() : path;
    if (seenPaths.add(normalizedKey)) {
      candidatePaths.add(path);
    }
  }

  void addDirectoryTreeCandidates(String? startDirPath) {
    if (startDirPath == null || startDirPath.trim().isEmpty) return;
    try {
      var dir = Directory(startDirPath).absolute;
      while (true) {
        final base = dir.path.endsWith(sep) && dir.path.length > 1
            ? dir.path.substring(0, dir.path.length - 1)
            : dir.path;
        for (final relativeParts in const [
          ['env'],
          ['.env'],
          ['packages', 'super_designer', 'env'],
          ['packages', 'super_designer', '.env'],
          ['packages', 'super_container_layout', 'env'],
          ['packages', 'super_container_layout', '.env'],
          ['super_designer', 'env'],
          ['super_designer', '.env'],
          ['super_container_layout', 'env'],
          ['super_container_layout', '.env'],
        ]) {
          addCandidate('$base$sep${relativeParts.join(sep)}');
        }
        if (dir.parent.path == dir.path) break;
        dir = dir.parent;
      }
    } catch (_) {}
  }

  addDirectoryTreeCandidates(currentDirectoryPath);
  if (executablePath != null && executablePath.trim().isNotEmpty) {
    try {
      addDirectoryTreeCandidates(File(executablePath).parent.path);
    } catch (_) {}
  }
  if (homeDirectoryPath != null && homeDirectoryPath.trim().isNotEmpty) {
    final home = homeDirectoryPath.endsWith(sep) && homeDirectoryPath.length > 1
        ? homeDirectoryPath.substring(0, homeDirectoryPath.length - 1)
        : homeDirectoryPath;
    addCandidate('$home$sep.super_container_layout${sep}env');
    addCandidate('$home$sep.super_container_layout$sep.env');
  }

  for (final path in candidatePaths) {
    final file = File(path);
    if (!await file.exists()) continue;
    final content = await file.readAsString();
    final probe = DotEnv();
    probe.loadFromString(envString: content, isOptional: true);
    final key = probe.env['GEMINI_API_KEY'];
    if (key != null && key.trim().isNotEmpty) {
      final existing = dotenv.isInitialized
          ? Map<String, String>.from(dotenv.env)
          : <String, String>{};
      existing.removeWhere(
        (k, v) => k == 'GEMINI_API_KEY' && v.trim().isEmpty,
      );
      dotenv.loadFromString(
        envString: content,
        isOptional: true,
        mergeWith: existing,
      );
      return key.trim();
    }
  }

  return '';
}

/// Préchauffe silencieusement la connexion Keep-Alive TLS et le cache de contexte Gemini.
Future<void> warmUpGemini({
  String? systemInstruction,
  String? staticGuide,
  VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
}) => GeminiRestClient.instance.warmUp(
  systemInstruction: systemInstruction,
  staticGuide: staticGuide,
  speedMode: speedMode,
  tools: tools,
);

/// Diffuse en flux SSE ([GeminiStreamEvent]) la génération JSON Gemini pour [prompt].
Stream<GeminiStreamEvent> streamGemini(
  String prompt, {
  String? systemInstruction,
  String? staticGuide,
  List<VibeChatAttachment> attachments = const [],
  VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
  List<Map<String, Object?>>? conversationContents,
  bool enforceJsonResponse = true,
  VibeCancellationToken? cancellationToken,
}) => GeminiRestClient.instance.streamGenerate(
  prompt,
  systemInstruction: systemInstruction,
  staticGuide: staticGuide,
  attachments: attachments,
  speedMode: speedMode,
  tools: tools,
  conversationContents: conversationContents,
  enforceJsonResponse: enforceJsonResponse,
  cancellationToken: cancellationToken,
);

/// Génère une réponse Gemini complète pour [prompt] tout en restant compatible avec les callbacks existants.
Future<String> callGemini(
  String prompt, {
  List<VibeChatAttachment> attachments = const [],
  String? systemInstruction,
  String? staticGuide,
  VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  VibeCancellationToken? cancellationToken,
}) => GeminiRestClient.instance.generate(
  prompt,
  attachments: attachments,
  systemInstruction: systemInstruction,
  staticGuide: staticGuide,
  speedMode: speedMode,
  cancellationToken: cancellationToken,
);

/// Transcrit un enregistrement audio WAV en texte via Gemini.
Future<String> transcribeSpeechWithGemini(
  List<int> audioBytes, {
  String mimeType = 'audio/wav',
  VibeAiSpeedMode speedMode = VibeAiSpeedMode.ultraFast,
}) => GeminiRestClient.instance.transcribeAudio(
  audioBytes,
  mimeType: mimeType,
  speedMode: speedMode,
);
