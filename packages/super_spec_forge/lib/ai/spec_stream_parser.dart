/// Parseur incrémental des réponses JSON SSE pour les agents `super_spec_forge` ([SpecStreamParser], [SpecAgentResponse]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart';

/// Instantané temps réel produit pendant la réception d'un flux JSON Gemini.
@immutable
class SpecStreamSnapshot {
  /// Construit un instantané de progression.
  const SpecStreamSnapshot({
    this.message,
    this.isMessageComplete = false,
    this.hasAskUser = false,
    this.hasSpecPatch = false,
    this.hasUxPatch = false,
    this.hasQaPatch = false,
    this.receivedChars = 0,
  });

  /// Instantané vide initial.
  static const SpecStreamSnapshot empty = SpecStreamSnapshot();

  /// Texte streaming du champ `"message"`, ou `null` tant qu'il n'est pas entamé.
  final String? message;

  /// Vrai lorsque le guillemet fermant de `"message"` a été atteint.
  final bool isMessageComplete;

  /// Vrai si une clé `"askUser": {` a été détectée dans le flux.
  final bool hasAskUser;

  /// Vrai si une clé `"specPatch": {` a été détectée dans le flux.
  final bool hasSpecPatch;

  /// Vrai si une clé `"uxPatch": {` a été détectée dans le flux.
  final bool hasUxPatch;

  /// Vrai si une clé `"qaPatch": {` a été détectée dans le flux.
  final bool hasQaPatch;

  /// Nombre total de caractères reçus.
  final int receivedChars;
}

/// Réponse structurée complète décodée à la fin d'un tour d'agent IA.
@immutable
class SpecAgentResponse {
  /// Construit une réponse d'agent décodée.
  const SpecAgentResponse({
    required this.message,
    this.askUser,
    this.specPatch,
    this.uxPatch,
    this.qaPatch,
    this.toolCalls = const <VibeToolCall>[],
    this.stageSummary = '',
    this.stageReadyToAdvance = false,
    this.rawJson = '',
  });

  /// Texte principal destiné à l'utilisateur.
  final String message;

  /// Questionnaire interactif éventuel.
  final VibeAskUserRequest? askUser;

  /// Patch structuré à appliquer sur le [SpecForgeProject].
  final Map<String, Object?>? specPatch;

  /// Patch structuré à appliquer sur le volet UX du [SpecForgeProject].
  final Map<String, Object?>? uxPatch;

  /// Patch structuré à appliquer sur le volet QA du [SpecForgeProject].
  final Map<String, Object?>? qaPatch;

  /// Appels d'outils éventuels émis via le repli JSON `"toolCalls"`.
  final List<VibeToolCall> toolCalls;

  /// Synthèse optionnelle de l'étape.
  final String stageSummary;

  /// Indique si l'agent estime que l'étape est prête à être validée.
  final bool stageReadyToAdvance;

  /// JSON brut décodé pour diagnostic.
  final String rawJson;

  /// Parse une réponse brute (éventuellement entourée de fences ```json).
  static SpecAgentResponse parse(String rawText) {
    final cleaned = _stripCodeFences(rawText).trim();
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map) {
      throw const FormatException(
        'La réponse de l’agent IA doit être un objet JSON.',
      );
    }
    final map = <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };

    final rawMessage = map['message'];
    final message = rawMessage is String && rawMessage.trim().isNotEmpty
        ? rawMessage.trim()
        : 'Réponse reçue.';

    final rawAskUser = map['askUser'];
    final askUser = rawAskUser == null
        ? null
        : VibeAskUserRequest.tryFromJson(rawAskUser);

    final rawPatch = map['specPatch'];
    final Map<String, Object?>? specPatch = rawPatch is Map
        ? <String, Object?>{
            for (final entry in rawPatch.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }
        : null;

    final rawUxPatch = map['uxPatch'];
    final Map<String, Object?>? uxPatch = rawUxPatch is Map
        ? <String, Object?>{
            for (final entry in rawUxPatch.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }
        : null;

    final rawQaPatch = map['qaPatch'];
    final Map<String, Object?>? qaPatch = rawQaPatch is Map
        ? <String, Object?>{
            for (final entry in rawQaPatch.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }
        : null;

    final toolCalls = VibeToolCall.tryListFromJson(map['toolCalls']);

    final rawSummary = map['stageSummary'];
    final stageSummary = rawSummary is String ? rawSummary.trim() : '';

    return SpecAgentResponse(
      message: message,
      askUser: askUser,
      specPatch: specPatch,
      uxPatch: uxPatch,
      qaPatch: qaPatch,
      toolCalls: toolCalls,
      stageSummary: stageSummary,
      stageReadyToAdvance: map['stageReadyToAdvance'] == true,
      rawJson: cleaned,
    );
  }

  static String _stripCodeFences(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final firstNewline = trimmed.indexOf('\n');
    if (firstNewline < 0) return trimmed;
    final withoutOpen = trimmed.substring(firstNewline + 1);
    final lastFence = withoutOpen.lastIndexOf('```');
    return lastFence >= 0 ? withoutOpen.substring(0, lastFence) : withoutOpen;
  }
}

/// Analyseur incrémental tolérant pour extraire en streaming le champ `"message"`.
class SpecStreamParser {
  final StringBuffer _buffer = StringBuffer();
  String _cachedText = '';

  /// Ajoute un fragment de texte SSE et retourne l'[SpecStreamSnapshot] courant.
  SpecStreamSnapshot addChunk(String delta) {
    if (delta.isNotEmpty) {
      _buffer.write(delta);
      _cachedText = _buffer.toString();
    }
    return snapshot();
  }

  /// Réinitialise l'état du parseur.
  void reset() {
    _buffer.clear();
    _cachedText = '';
  }

  /// Texte brut complet accumulé jusqu'ici.
  String get rawText => _cachedText;

  /// Calcule l'instantané actuel sans lever d'exception sur un JSON incomplet.
  SpecStreamSnapshot snapshot() {
    final text = _cachedText;
    if (text.isEmpty) return SpecStreamSnapshot.empty;

    final extracted = _extractTopLevelStringField(text, 'message');
    final hasAskUser = RegExp(r'"askUser"\s*:\s*[\{\[]').hasMatch(text);
    final hasSpecPatch = RegExp(r'"specPatch"\s*:\s*\{').hasMatch(text);
    final hasUxPatch = RegExp(r'"uxPatch"\s*:\s*\{').hasMatch(text);
    final hasQaPatch = RegExp(r'"qaPatch"\s*:\s*\{').hasMatch(text);

    return SpecStreamSnapshot(
      message: extracted?.value,
      isMessageComplete: extracted?.complete ?? false,
      hasAskUser: hasAskUser,
      hasSpecPatch: hasSpecPatch,
      hasUxPatch: hasUxPatch,
      hasQaPatch: hasQaPatch,
      receivedChars: text.length,
    );
  }

  static ({String value, bool complete})? _extractTopLevelStringField(
    String input,
    String key,
  ) {
    final pattern = RegExp('"$key"\\s*:\\s*"');
    final match = pattern.firstMatch(input);
    if (match == null) return null;
    final out = StringBuffer();
    var i = match.end;
    while (i < input.length) {
      final ch = input[i];
      if (ch == '\\') {
        if (i + 1 >= input.length) {
          break;
        }
        final next = input[i + 1];
        switch (next) {
          case '"':
            out.write('"');
            i += 2;
          case '\\':
            out.write('\\');
            i += 2;
          case '/':
            out.write('/');
            i += 2;
          case 'n':
            out.write('\n');
            i += 2;
          case 'r':
            out.write('\r');
            i += 2;
          case 't':
            out.write('\t');
            i += 2;
          case 'u':
            if (i + 5 < input.length) {
              final hex = input.substring(i + 2, i + 6);
              final code = int.tryParse(hex, radix: 16);
              if (code != null) {
                out.writeCharCode(code);
                i += 6;
                continue;
              }
            }
            i += 2;
          default:
            out.write(next);
            i += 2;
        }
      } else if (ch == '"') {
        return (value: out.toString(), complete: true);
      } else {
        out.write(ch);
        i++;
      }
    }
    return (value: out.toString(), complete: false);
  }
}
