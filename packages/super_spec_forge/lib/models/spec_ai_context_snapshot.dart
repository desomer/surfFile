/// Modèles immuables d'inspection du contexte envoyé à l'IA ([SpecAiContextSnapshot],
/// [SpecAiContextAttachmentSummary], [SpecAiContextInspection]).
///
/// Permet d'exposer en lecture seule la totalité du contexte transmis à Gemini
/// (instruction système, guide statique, prompt dynamique, outils déclarés,
/// pièces jointes et éventuels échanges multi-rounds d'outils), aussi bien en
/// aperçu en direct du prochain envoi que pour le dernier envoi réel.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart';

/// Résumé immuable d'une pièce jointe transmise avec un message au modèle IA.
@immutable
class SpecAiContextAttachmentSummary {
  /// Crée un résumé de pièce jointe pour l'inspecteur de contexte.
  const SpecAiContextAttachmentSummary({
    required this.name,
    required this.mimeType,
    required this.byteLength,
    required this.isImage,
    this.textContent,
  });

  /// Construit le résumé à partir d'une [VibeChatAttachment].
  factory SpecAiContextAttachmentSummary.fromAttachment(
    VibeChatAttachment attachment,
  ) => SpecAiContextAttachmentSummary(
    name: attachment.name,
    mimeType: attachment.mimeType,
    byteLength: attachment.bytes.length,
    isImage: attachment.isImage,
    textContent: attachment.textContent,
  );

  /// Nom du fichier joint.
  final String name;

  /// Type MIME (ex. `image/png`, `text/plain`, `application/json`).
  final String mimeType;

  /// Taille binaire en octets.
  final int byteLength;

  /// Indique si la pièce jointe est une image transmise en `inlineData`.
  final bool isImage;

  /// Contenu texte intégral lorsque la pièce jointe est textuelle.
  final String? textContent;

  /// Retourne la représentation lisible de la pièce jointe telle qu'injectée.
  String formatDisplay() {
    final sizeLabel = _formatByteSize(byteLength);
    if (isImage) {
      final base64Chars = ((byteLength + 2) ~/ 3) * 4;
      return '--- Image jointe : "$name" ($mimeType, $sizeLabel) ---\n'
          '[inlineData base64 omis en affichage : $base64Chars car. encodés]';
    }
    final content = textContent ?? '';
    return '--- Fichier texte joint : "$name" ($mimeType, $sizeLabel) ---\n'
        '$content';
  }
}

/// Instantané immuable de la totalité du contexte transmis au modèle IA pour un chat donné.
@immutable
class SpecAiContextSnapshot {
  /// Crée un instantané de contexte IA.
  SpecAiContextSnapshot({
    required this.scopeKey,
    required this.title,
    required this.isLivePreview,
    required this.capturedAt,
    required this.speedMode,
    required this.questioningLevel,
    required this.enforceJsonResponse,
    required this.systemInstruction,
    required this.staticGuide,
    required this.prompt,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
    List<SpecAiContextAttachmentSummary> attachments =
        const <SpecAiContextAttachmentSummary>[],
    List<Map<String, Object?>> conversationContents =
        const <Map<String, Object?>>[],
  }) : tools = List<VibeToolDeclaration>.unmodifiable(tools),
       attachments = List<SpecAiContextAttachmentSummary>.unmodifiable(
         attachments,
       ),
       conversationContents = List<Map<String, Object?>>.unmodifiable(
         sanitizeConversationContents(conversationContents),
       );

  /// Identifiant unique du scope de chat (ex. `spec:vision`, `ux:screens`, `domainModel:d1/o1`).
  final String scopeKey;

  /// Libellé humain du chat / agent inspecté.
  final String title;

  /// `true` pour un aperçu en direct du prochain envoi, `false` pour le dernier envoi réel capturé.
  final bool isLivePreview;

  /// Horodatage UTC de génération ou de capture.
  final DateTime capturedAt;

  /// Profil de vitesse / modèle Gemini utilisé.
  final VibeAiSpeedMode speedMode;

  /// Niveau de questionnement `askUser` actif.
  final VibeQuestioningLevel questioningLevel;

  /// Indique si `responseMimeType: application/json` est demandé sur le tour final.
  final bool enforceJsonResponse;

  /// Instruction système envoyée dans `systemInstruction` (ou `cachedContent`).
  final String systemInstruction;

  /// Guide statique (schéma de patch + documentation des outils) envoyé avec `systemInstruction` ou mis en cache.
  final String staticGuide;

  /// Prompt dynamique construit pour le tour utilisateur (état métier, historique, focus, demande).
  final String prompt;

  /// Déclarations d'outils (`functionDeclarations`) exposées au modèle pour ce chat.
  final List<VibeToolDeclaration> tools;

  /// Pièces jointes associées au tour (texte intégral ou métadonnées image).
  final List<SpecAiContextAttachmentSummary> attachments;

  /// Historique multi-rounds `contents` (appels `functionCall` / `functionResponse`) assaini.
  final List<Map<String, Object?>> conversationContents;

  /// Indique si `staticGuide` dépasse le seuil d'éligibilité au cache explicite Gemini (`cachedContents`).
  bool get usesExplicitCacheCandidate =>
      staticGuide.trim().isNotEmpty &&
      staticGuide.length >=
          GeminiRestClient.defaultMinGuideCharsForExplicitCache;

  /// Représentation JSON indentée des `functionDeclarations` envoyées au modèle.
  String get toolsPrettyJson {
    if (tools.isEmpty) return '';
    return const JsonEncoder.withIndent('  ').convert([
      for (final tool in tools) tool.toGeminiFunctionDeclaration(),
    ]);
  }

  /// Texte formaté de toutes les pièces jointes associées au tour.
  String get attachmentsText {
    if (attachments.isEmpty) return '';
    return attachments.map((a) => a.formatDisplay()).join('\n\n');
  }

  /// Indique si plusieurs rounds d'échanges (appels/réponses d'outils) ont eu lieu.
  bool get hasToolRounds => conversationContents.length > 1;

  /// Représentation JSON indentée de `conversationContents` (assainie sans blobs base64).
  String get conversationRoundsPrettyJson {
    if (conversationContents.isEmpty) return '';
    return const JsonEncoder.withIndent('  ').convert(conversationContents);
  }

  /// Indique si l'onglet « Pièces jointes & Tours » contient des éléments à inspecter.
  bool get hasAttachmentsOrRounds => attachments.isNotEmpty || hasToolRounds;

  /// Nombre de caractères de [systemInstruction].
  int get systemChars => systemInstruction.length;

  /// Nombre de caractères de [staticGuide].
  int get staticGuideChars => staticGuide.length;

  /// Nombre de caractères de [prompt].
  int get promptChars => prompt.length;

  /// Nombre de caractères de [toolsPrettyJson].
  int get toolsChars => toolsPrettyJson.length;

  /// Nombre de caractères de [attachmentsText].
  int get attachmentsChars => attachmentsText.length;

  /// Nombre de caractères des échanges multi-rounds d'outils (lorsqu'il y a plus d'un round).
  int get roundsChars =>
      hasToolRounds ? conversationRoundsPrettyJson.length : 0;

  /// Taille totale cumulée (en caractères) de l'ensemble du contexte textuel envoyé.
  int get totalChars =>
      systemChars +
      staticGuideChars +
      promptChars +
      toolsChars +
      attachmentsChars +
      roundsChars;

  /// Estimation indicative en tokens (~4 caractères par token).
  int get estimatedTokens => totalChars == 0 ? 0 : (totalChars / 4).ceil();

  /// Assemble en un texte unique la totalité du contexte envoyé à l'IA.
  String toFullText() {
    final buf = StringBuffer()
      ..writeln('================================================================')
      ..writeln('CONTEXTE IA — $title')
      ..writeln(
        'Source : ${isLivePreview ? 'Aperçu en direct du prochain envoi' : 'Dernier envoi réel capturé'}',
      )
      ..writeln('Scope : $scopeKey')
      ..writeln(
        'Modèle : ${speedMode.defaultModel} (mode ${speedMode.label}) | '
        'Questionnement : ${questioningLevel.label} | '
        'JSON forcé : ${enforceJsonResponse ? 'oui' : 'non'} | '
        'Cache explicite éligible : ${usesExplicitCacheCandidate ? 'oui' : 'non'}',
      )
      ..writeln(
        'Volume total : $totalChars car. (~$estimatedTokens tokens) — '
        'System: $systemChars | Guide: $staticGuideChars | Prompt: $promptChars | '
        'Outils (${tools.length}): $toolsChars'
        '${attachments.isNotEmpty ? ' | Pièces jointes (${attachments.length}): $attachmentsChars' : ''}'
        '${hasToolRounds ? ' | Rounds outils (${conversationContents.length}): $roundsChars' : ''}',
      )
      ..writeln('================================================================');

    buf
      ..writeln()
      ..writeln('=== 1. SYSTEM INSTRUCTION ($systemChars car.) ===')
      ..writeln(
        systemInstruction.trim().isEmpty ? '(vide)' : systemInstruction.trim(),
      );

    buf
      ..writeln()
      ..writeln('=== 2. GUIDE STATIQUE / SCHÉMA ($staticGuideChars car.) ===')
      ..writeln(staticGuide.trim().isEmpty ? '(vide)' : staticGuide.trim());

    buf
      ..writeln()
      ..writeln('=== 3. PROMPT DYNAMIQUE ($promptChars car.) ===')
      ..writeln(prompt.trim().isEmpty ? '(vide)' : prompt.trim());

    buf
      ..writeln()
      ..writeln(
        '=== 4. OUTILS DÉCLARÉS — functionDeclarations (${tools.length} outil(s), $toolsChars car.) ===',
      )
      ..writeln(tools.isEmpty ? '(aucun outil déclaré)' : toolsPrettyJson);

    if (attachments.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(
          '=== 5. PIÈCES JOINTES (${attachments.length}, $attachmentsChars car.) ===',
        )
        ..writeln(attachmentsText);
    }

    if (hasToolRounds) {
      buf
        ..writeln()
        ..writeln(
          '=== 6. CONTENU MULTI-ROUNDS D’OUTILS (${conversationContents.length} entrée(s), $roundsChars car.) ===',
        )
        ..writeln(conversationRoundsPrettyJson);
    }

    return buf.toString();
  }

  /// Assainit une liste `conversationContents` Gemini en remplaçant les blobs base64
  /// `inlineData.data` par un marqueur de taille lisible tout en conservant tous les
  /// textes, `functionCall` et `functionResponse`.
  static List<Map<String, Object?>> sanitizeConversationContents(
    List<Map<String, Object?>>? raw,
  ) {
    if (raw == null || raw.isEmpty) return const <Map<String, Object?>>[];
    return [for (final item in raw) _sanitizeMap(item)];
  }

  static Map<String, Object?> _sanitizeMap(Map<Object?, Object?> source) {
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key?.toString() ?? '';
      final value = entry.value;
      if (key == 'inlineData' && value is Map) {
        final mime = value['mimeType']?.toString() ?? 'application/octet-stream';
        final rawData = value['data'];
        final dataLen = rawData is String ? rawData.length : 0;
        final approxBytes = (dataLen * 3) ~/ 4;
        result[key] = <String, Object?>{
          'mimeType': mime,
          'data':
              '<base64 omis : $dataLen car. (~${_formatByteSize(approxBytes)})>',
        };
      } else {
        result[key] = _sanitizeValue(value);
      }
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  static Object? _sanitizeValue(Object? value) {
    if (value is Map) {
      return _sanitizeMap(value);
    }
    if (value is List) {
      return List<Object?>.unmodifiable([
        for (final item in value) _sanitizeValue(item),
      ]);
    }
    return value;
  }
}

/// Paire d'inspection contenant toujours l'aperçu en direct et, s'il existe,
/// le dernier contexte réellement envoyé à l'IA sur le même chat.
@immutable
class SpecAiContextInspection {
  /// Crée une inspection de contexte combinant [preview] et un éventuel [lastSent].
  const SpecAiContextInspection({required this.preview, this.lastSent});

  /// Aperçu en direct du contexte qui sera envoyé au prochain tour.
  final SpecAiContextSnapshot preview;

  /// Dernier contexte réellement envoyé lors d'un tour précédent, ou `null` si aucun envoi encore.
  final SpecAiContextSnapshot? lastSent;

  /// Indique si un envoi réel a déjà été capturé pour ce chat.
  bool get hasLastSent => lastSent != null;
}

String _formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} Ko';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} Mo';
}
