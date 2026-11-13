/// Points d'entrée d'appel au modèle génératif Gemini pour l'assistant Vibe IA.
///
/// Expose la résolution mise en cache de `GEMINI_API_KEY` ([resolveGeminiApiKey]),
/// le préchauffage réseau/cache ([warmUpGemini]), le flux SSE incrémental
/// ([streamGemini]) et l'appel complet rétrocompatible ([callGemini]) appuyés sur
/// [GeminiRestClient].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'gemini_rest_client.dart';
import 'vibe_chat_attachment.dart';

export 'gemini_rest_client.dart';
export 'vibe_chat_attachment.dart';

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
/// 4. Les fichiers `env` ou `.env` découverts dans le répertoire courant ou ses parents.
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

Future<String> _discoverGeminiApiKey() async {
  if (!kIsWeb) {
    final envKey = Platform.environment['GEMINI_API_KEY'];
    if (envKey != null && envKey.trim().isNotEmpty) {
      final key = envKey.trim();
      _populateDotenvKey(key);
      return key;
    }

    final sep = Platform.pathSeparator;
    final candidates = [
      'env',
      '.env',
      ['packages', 'super_designer', 'env'].join(sep),
      ['packages', 'super_designer', '.env'].join(sep),
      ['packages', 'super_container_layout', 'env'].join(sep),
      ['packages', 'super_container_layout', '.env'].join(sep),
      ['..', 'super_container_layout', 'env'].join(sep),
      ['..', 'super_container_layout', '.env'].join(sep),
      ['..', 'super_designer', 'env'].join(sep),
      ['..', 'super_designer', '.env'].join(sep),
      ['..', 'env'].join(sep),
      ['..', '.env'].join(sep),
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        dotenv.loadFromString(envString: content, isOptional: true);
        final key = dotenv.env['GEMINI_API_KEY'];
        if (key != null && key.trim().isNotEmpty) {
          return key.trim();
        }
      }
    }

    try {
      var dir = Directory.current;
      while (true) {
        for (final candidate in [
          'env',
          '.env',
          ['packages', 'super_container_layout', 'env'].join(sep),
          ['packages', 'super_designer', 'env'].join(sep),
        ]) {
          final file = File('${dir.path}$sep$candidate');
          if (await file.exists()) {
            final content = await file.readAsString();
            dotenv.loadFromString(envString: content, isOptional: true);
            final key = dotenv.env['GEMINI_API_KEY'];
            if (key != null && key.trim().isNotEmpty) {
              return key.trim();
            }
          }
        }
        if (dir.parent.path == dir.path) break;
        dir = dir.parent;
      }
    } catch (_) {}
  }

  return '';
}

/// Préchauffe silencieusement la connexion Keep-Alive TLS et le cache de contexte Gemini.
Future<void> warmUpGemini({
  String? systemInstruction,
  String? staticGuide,
  VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
}) => GeminiRestClient.instance.warmUp(
  systemInstruction: systemInstruction,
  staticGuide: staticGuide,
  speedMode: speedMode,
);

/// Diffuse en flux SSE ([GeminiStreamEvent]) la génération JSON Gemini pour [prompt].
Stream<GeminiStreamEvent> streamGemini(
  String prompt, {
  String? systemInstruction,
  String? staticGuide,
  List<VibeChatAttachment> attachments = const [],
  VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
}) => GeminiRestClient.instance.streamGenerate(
  prompt,
  systemInstruction: systemInstruction,
  staticGuide: staticGuide,
  attachments: attachments,
  speedMode: speedMode,
);

/// Génère une réponse Gemini complète pour [prompt] tout en restant compatible avec les callbacks existants.
Future<String> callGemini(
  String prompt, {
  List<VibeChatAttachment> attachments = const [],
  String? systemInstruction,
  String? staticGuide,
  VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
}) => GeminiRestClient.instance.generate(
  prompt,
  attachments: attachments,
  systemInstruction: systemInstruction,
  staticGuide: staticGuide,
  speedMode: speedMode,
);
