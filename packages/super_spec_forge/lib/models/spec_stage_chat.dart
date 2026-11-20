/// Modèles immuables de conversation et d'état par étape du wizard ([SpecChatMessage], [SpecStageState]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart';

import 'spec_forge_stage.dart';

/// Message échangé avec l'agent IA spécialisé d'une étape du wizard.
@immutable
class SpecChatMessage {
  /// Construit un message immuable.
  SpecChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    this.promptText,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    List<VibeToolTrace> toolTraces = const <VibeToolTrace>[],
    this.askUser,
    Map<String, Object?>? askUserAnswers,
    this.askUserUsedDefaults = false,
    this.askUserDismissed = false,
    this.askUserRequestedMore = false,
    this.requestsMoreQuestions = false,
    this.appliedPatchSummary = '',
    this.stageReadyToAdvance = false,
    this.failedResponse,
    DateTime? timestamp,
  }) : attachments = List<VibeChatAttachment>.unmodifiable(attachments),
       toolTraces = List<VibeToolTrace>.unmodifiable(toolTraces),
       askUserAnswers = askUserAnswers == null
           ? null
           : Map<String, Object?>.unmodifiable(askUserAnswers),
       timestamp = timestamp ?? DateTime.now().toUtc();

  /// Identifiant unique du message.
  final String id;

  /// Vrai si le message provient de l'utilisateur.
  final bool isUser;

  /// Texte lisible affiché dans la bulle de conversation.
  final String text;

  /// Texte détaillé envoyé au modèle (ex. réponses formatées d'un questionnaire).
  final String? promptText;

  /// Pièces jointes (images, documents texte/JSON/YAML/Markdown) associées à ce message.
  final List<VibeChatAttachment> attachments;

  /// Appels d'outils IA exécutés pour produire cette réponse.
  final List<VibeToolTrace> toolTraces;

  /// Questionnaire interactif éventuel proposé par l'agent IA.
  final VibeAskUserRequest? askUser;

  /// Réponses soumises par l'utilisateur au questionnaire [askUser].
  final Map<String, Object?>? askUserAnswers;

  /// Indique si l'utilisateur a validé les valeurs par défaut sans les éditer.
  final bool askUserUsedDefaults;

  /// Indique si le questionnaire a été ignoré.
  final bool askUserDismissed;

  /// Indique si l'utilisateur a demandé une série complémentaire de questions.
  final bool askUserRequestedMore;

  /// Indique si ce message utilisateur force de nouvelles questions au tour suivant.
  final bool requestsMoreQuestions;

  /// Résumé court des modifications appliquées au modèle via `specPatch`.
  final String appliedPatchSummary;

  /// Indique si l'agent estime l'étape suffisamment mûre pour passer à la suivante.
  final bool stageReadyToAdvance;

  /// Réponse brute en erreur conservée pour reprise au tour suivant.
  final String? failedResponse;

  /// Horodatage UTC du message.
  final DateTime timestamp;

  /// Formate ce message pour l'historique envoyé au LLM.
  String toConversationEntry() {
    if (isUser) {
      final base = (promptText ?? text).trim();
      if (attachments.isEmpty) return 'Utilisateur: $base';
      final names = attachments.map((a) => a.name).join(', ');
      return 'Utilisateur [Pièces jointes : $names]: $base';
    }
    if (failedResponse != null && failedResponse!.trim().isNotEmpty) {
      return 'Assistant (réponse précédente rejetée : $text): $failedResponse';
    }
    final buffer = StringBuffer('Assistant: $text');
    if (askUser != null) {
      buffer.write(
        ' [Questions posées: ${askUser!.questions.map((q) => q.title).join(' | ')}]',
      );
    }
    if (appliedPatchSummary.trim().isNotEmpty) {
      buffer.write(' [Mises à jour appliquées: $appliedPatchSummary]');
    }
    return buffer.toString();
  }

  /// Copie modifiée.
  SpecChatMessage copyWith({
    String? id,
    bool? isUser,
    String? text,
    String? promptText,
    List<VibeChatAttachment>? attachments,
    List<VibeToolTrace>? toolTraces,
    VibeAskUserRequest? askUser,
    Map<String, Object?>? askUserAnswers,
    bool? askUserUsedDefaults,
    bool? askUserDismissed,
    bool? askUserRequestedMore,
    bool? requestsMoreQuestions,
    String? appliedPatchSummary,
    bool? stageReadyToAdvance,
    String? failedResponse,
    DateTime? timestamp,
  }) => SpecChatMessage(
    id: id ?? this.id,
    isUser: isUser ?? this.isUser,
    text: text ?? this.text,
    promptText: promptText ?? this.promptText,
    attachments: attachments ?? this.attachments,
    toolTraces: toolTraces ?? this.toolTraces,
    askUser: askUser ?? this.askUser,
    askUserAnswers: askUserAnswers ?? this.askUserAnswers,
    askUserUsedDefaults: askUserUsedDefaults ?? this.askUserUsedDefaults,
    askUserDismissed: askUserDismissed ?? this.askUserDismissed,
    askUserRequestedMore: askUserRequestedMore ?? this.askUserRequestedMore,
    requestsMoreQuestions:
        requestsMoreQuestions ?? this.requestsMoreQuestions,
    appliedPatchSummary: appliedPatchSummary ?? this.appliedPatchSummary,
    stageReadyToAdvance: stageReadyToAdvance ?? this.stageReadyToAdvance,
    failedResponse: failedResponse ?? this.failedResponse,
    timestamp: timestamp ?? this.timestamp,
  );

  /// Sérialise le message en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'isUser': isUser,
    'text': text,
    if (promptText != null) 'promptText': promptText,
    if (attachments.isNotEmpty)
      'attachments': [for (final a in attachments) _attachmentToJson(a)],
    if (toolTraces.isNotEmpty)
      'toolTraces': [
        for (final t in toolTraces)
          <String, Object?>{
            'name': t.name,
            'arguments': t.arguments,
            'isError': t.isError,
            'summary': t.summary,
          },
      ],
    if (askUser != null)
      'askUser': <String, Object?>{
        'questions': [for (final q in askUser!.questions) q.toJson()],
      },
    if (askUserAnswers != null) 'askUserAnswers': askUserAnswers,
    if (askUserUsedDefaults) 'askUserUsedDefaults': true,
    if (askUserDismissed) 'askUserDismissed': true,
    if (askUserRequestedMore) 'askUserRequestedMore': true,
    if (requestsMoreQuestions) 'requestsMoreQuestions': true,
    if (appliedPatchSummary.isNotEmpty)
      'appliedPatchSummary': appliedPatchSummary,
    if (stageReadyToAdvance) 'stageReadyToAdvance': true,
    if (failedResponse != null) 'failedResponse': failedResponse,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };

  /// Désérialise un message depuis JSON.
  factory SpecChatMessage.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('SpecChatMessage doit être un objet JSON.');
    }
    final rawAskUser = raw['askUser'];
    final askUser = rawAskUser == null
        ? null
        : VibeAskUserRequest.tryFromJson(rawAskUser);
    final rawAttachments = raw['attachments'];
    final attachments = <VibeChatAttachment>[
      if (rawAttachments is List)
        for (final item in rawAttachments)
          if (_attachmentFromJson(item) case final VibeChatAttachment parsed)
            parsed,
    ];
    final rawTraces = raw['toolTraces'];
    final toolTraces = <VibeToolTrace>[
      if (rawTraces is List)
        for (final item in rawTraces)
          if (item is Map && item['name'] is String)
            VibeToolTrace(
              name: item['name'] as String,
              arguments: item['arguments'] is Map
                  ? <String, Object?>{
                      for (final e in (item['arguments'] as Map).entries)
                        if (e.key is String) e.key as String: e.value,
                    }
                  : const <String, Object?>{},
              isError: item['isError'] == true,
              summary: (item['summary'] as String?) ?? '',
            ),
    ];
    final rawAnswers = raw['askUserAnswers'];
    final answers = rawAnswers is Map
        ? <String, Object?>{
            for (final entry in rawAnswers.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }
        : null;
    final tsRaw = raw['timestamp'];
    final ts = tsRaw is String ? DateTime.tryParse(tsRaw)?.toUtc() : null;
    return SpecChatMessage(
      id: (raw['id'] as String?)?.trim() ?? 'msg_${raw.hashCode.abs()}',
      isUser: raw['isUser'] == true,
      text: (raw['text'] as String?) ?? '',
      promptText: raw['promptText'] as String?,
      attachments: attachments,
      toolTraces: toolTraces,
      askUser: askUser,
      askUserAnswers: answers,
      askUserUsedDefaults: raw['askUserUsedDefaults'] == true,
      askUserDismissed: raw['askUserDismissed'] == true,
      askUserRequestedMore: raw['askUserRequestedMore'] == true,
      requestsMoreQuestions: raw['requestsMoreQuestions'] == true,
      appliedPatchSummary: (raw['appliedPatchSummary'] as String?) ?? '',
      stageReadyToAdvance: raw['stageReadyToAdvance'] == true,
      failedResponse: raw['failedResponse'] as String?,
      timestamp: ts,
    );
  }

  static Map<String, Object?> _attachmentToJson(VibeChatAttachment a) =>
      <String, Object?>{
        'name': a.name,
        'mimeType': a.mimeType,
        if (a.path != null) 'path': a.path,
        if (a.textContent != null)
          'textContent': a.textContent
        else if (a.bytes.length <= 2 * 1024 * 1024)
          'bytesBase64': base64Encode(a.bytes),
      };

  static VibeChatAttachment? _attachmentFromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final mimeType = raw['mimeType'];
    if (name is! String || name.isEmpty || mimeType is! String) return null;
    final path = raw['path'] is String ? raw['path'] as String : null;
    final textContent = raw['textContent'];
    if (textContent is String) {
      return VibeChatAttachment.text(
        name: name,
        content: textContent,
        mimeType: mimeType,
        path: path,
      );
    }
    final bytesBase64 = raw['bytesBase64'];
    if (bytesBase64 is String && bytesBase64.isNotEmpty) {
      try {
        return VibeChatAttachment(
          name: name,
          mimeType: mimeType,
          bytes: Uint8List.fromList(base64Decode(bytesBase64)),
          path: path,
        );
      } catch (_) {
        return null;
      }
    }
    return VibeChatAttachment(
      name: name,
      mimeType: mimeType,
      bytes: Uint8List(0),
      path: path,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecChatMessage &&
          other.id == id &&
          other.isUser == isUser &&
          other.text == text &&
          other.promptText == promptText &&
          _attachmentsEqual(other.attachments, attachments) &&
          listEquals(other.toolTraces, toolTraces) &&
          other.askUser == askUser &&
          mapEquals(other.askUserAnswers, askUserAnswers) &&
          other.askUserUsedDefaults == askUserUsedDefaults &&
          other.askUserDismissed == askUserDismissed &&
          other.askUserRequestedMore == askUserRequestedMore &&
          other.requestsMoreQuestions == requestsMoreQuestions &&
          other.appliedPatchSummary == appliedPatchSummary &&
          other.stageReadyToAdvance == stageReadyToAdvance &&
          other.failedResponse == failedResponse &&
          other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(
    id,
    isUser,
    text,
    promptText,
    attachments.length,
    Object.hashAll(toolTraces),
    askUser,
    askUserAnswers == null ? null : Object.hashAll(askUserAnswers!.keys),
    askUserUsedDefaults,
    askUserDismissed,
    askUserRequestedMore,
    requestsMoreQuestions,
    appliedPatchSummary,
    stageReadyToAdvance,
    failedResponse,
    timestamp,
  );

  static bool _attachmentsEqual(
    List<VibeChatAttachment> a,
    List<VibeChatAttachment> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name ||
          a[i].mimeType != b[i].mimeType ||
          a[i].textContent != b[i].textContent ||
          !listEquals(a[i].bytes, b[i].bytes)) {
        return false;
      }
    }
    return true;
  }
}

/// État conversationnel et avancement d'une étape du wizard.
@immutable
class SpecStageState {
  /// Construit un état d'étape immuable.
  SpecStageState({
    required this.stage,
    this.status = SpecStageStatus.notStarted,
    List<SpecChatMessage> messages = const <SpecChatMessage>[],
    this.stageSummary = '',
    this.readyToAdvance = false,
  }) : messages = List<SpecChatMessage>.unmodifiable(messages);

  /// Étape du wizard concernée.
  final SpecForgeStage stage;

  /// Statut d'avancement de l'étape.
  final SpecStageStatus status;

  /// Historique des échanges avec l'agent spécialisé de cette étape.
  final List<SpecChatMessage> messages;

  /// Synthèse consolidée produite à la fin de l'étape pour alimenter les suivantes.
  final String stageSummary;

  /// Vrai lorsque l'agent a indiqué que l'étape peut être validée.
  final bool readyToAdvance;

  /// Copie modifiée.
  SpecStageState copyWith({
    SpecForgeStage? stage,
    SpecStageStatus? status,
    List<SpecChatMessage>? messages,
    String? stageSummary,
    bool? readyToAdvance,
  }) => SpecStageState(
    stage: stage ?? this.stage,
    status: status ?? this.status,
    messages: messages ?? this.messages,
    stageSummary: stageSummary ?? this.stageSummary,
    readyToAdvance: readyToAdvance ?? this.readyToAdvance,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'stage': stage.name,
    'status': status.name,
    'messages': [for (final m in messages) m.toJson()],
    'stageSummary': stageSummary,
    'readyToAdvance': readyToAdvance,
  };

  /// Désérialise depuis JSON.
  factory SpecStageState.fromJson(Object? raw, {SpecForgeStage? fallbackStage}) {
    if (raw is! Map) {
      throw const FormatException('SpecStageState doit être un objet JSON.');
    }
    final stage = raw['stage'] != null
        ? SpecForgeStage.fromJson(raw['stage'])
        : (fallbackStage ?? SpecForgeStage.vision);
    return SpecStageState(
      stage: stage,
      status: SpecStageStatus.fromJson(raw['status']),
      messages: [
        if (raw['messages'] is List)
          for (final item in raw['messages'] as List)
            SpecChatMessage.fromJson(item),
      ],
      stageSummary: (raw['stageSummary'] as String?) ?? '',
      readyToAdvance: raw['readyToAdvance'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecStageState &&
          other.stage == stage &&
          other.status == status &&
          listEquals(other.messages, messages) &&
          other.stageSummary == stageSummary &&
          other.readyToAdvance == readyToAdvance;

  @override
  int get hashCode => Object.hash(
    stage,
    status,
    Object.hashAll(messages),
    stageSummary,
    readyToAdvance,
  );
}
