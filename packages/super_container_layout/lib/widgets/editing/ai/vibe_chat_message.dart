/// Représentation d'un message Vibe et de son entrée dans le prompt.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import '../../../ai/vibe_app_tools.dart';
import '../../../ai/vibe_ask_user.dart';
import '../../../ai/vibe_chat_attachment.dart';
import '../../../ai/vibe_plan.dart';

/// Message de conversation temporaire affiché par le dialogue Vibe.
@immutable
class VibeChatMessage {
  /// Crée un message utilisateur ou assistant du chat Vibe.
  const VibeChatMessage({
    required this.text,
    required this.isUser,
    this.promptText,
    this.failedResponse,
    this.attachments = const [],
    this.askUser,
    this.askUserAnswers,
    this.askUserUsedDefaults = false,
    this.askUserDismissed = false,
    this.askUserRequestedMore = false,
    this.requestsMoreQuestions = false,
    this.plan,
    this.planSourcePrompt,
    this.planSourceAttachments = const [],
    this.toolTraces = const [],
  });

  /// Texte affiché dans la bulle.
  final String text;

  /// Indique si le message a été écrit par l'utilisateur.
  final bool isUser;

  /// Texte effectivement envoyé, différent du texte affiché après clarification.
  final String? promptText;

  /// Réponse IA rejetée, conservée pour permettre sa correction au tour suivant.
  final String? failedResponse;

  /// Pièces jointes associées à ce tour utilisateur.
  final List<VibeChatAttachment> attachments;

  /// Questionnaire interactif associé à la réponse.
  final VibeAskUserRequest? askUser;

  /// Réponses saisies dans le questionnaire.
  final Map<String, Object?>? askUserAnswers;

  /// Indique si les valeurs proposées ont été utilisées sans modification.
  final bool askUserUsedDefaults;

  /// Indique si le questionnaire a été ignoré.
  final bool askUserDismissed;

  /// Indique si l'utilisateur a validé ces réponses en demandant une série complémentaire (« + de questions »).
  final bool askUserRequestedMore;

  /// Indique si ce message utilisateur force l'émission de 2 à 4 questions complémentaires au tour suivant.
  final bool requestsMoreQuestions;

  /// Plan d'exécution par lots associé à la réponse.
  final VibeExecutionPlan? plan;

  /// Demande textuelle d'origine ayant déclenché ce plan.
  final String? planSourcePrompt;

  /// Pièces jointes sources conservées pour être réinjectées dans chaque lot du plan.
  final List<VibeChatAttachment> planSourceAttachments;

  /// Appels d'outils d'introspection exécutés pour produire cette réponse.
  final List<VibeToolTrace> toolTraces;

  /// Copie ce message en conservant les valeurs non spécifiées.
  VibeChatMessage copyWith({
    String? text,
    bool? isUser,
    String? promptText,
    String? failedResponse,
    List<VibeChatAttachment>? attachments,
    VibeAskUserRequest? askUser,
    Map<String, Object?>? askUserAnswers,
    bool? askUserUsedDefaults,
    bool? askUserDismissed,
    bool? askUserRequestedMore,
    bool? requestsMoreQuestions,
    VibeExecutionPlan? plan,
    String? planSourcePrompt,
    List<VibeChatAttachment>? planSourceAttachments,
    List<VibeToolTrace>? toolTraces,
  }) => VibeChatMessage(
    text: text ?? this.text,
    isUser: isUser ?? this.isUser,
    promptText: promptText ?? this.promptText,
    failedResponse: failedResponse ?? this.failedResponse,
    attachments: attachments ?? this.attachments,
    askUser: askUser ?? this.askUser,
    askUserAnswers: askUserAnswers ?? this.askUserAnswers,
    askUserUsedDefaults: askUserUsedDefaults ?? this.askUserUsedDefaults,
    askUserDismissed: askUserDismissed ?? this.askUserDismissed,
    askUserRequestedMore: askUserRequestedMore ?? this.askUserRequestedMore,
    requestsMoreQuestions: requestsMoreQuestions ?? this.requestsMoreQuestions,
    plan: plan ?? this.plan,
    planSourcePrompt: planSourcePrompt ?? this.planSourcePrompt,
    planSourceAttachments:
        planSourceAttachments ?? this.planSourceAttachments,
    toolTraces: toolTraces ?? this.toolTraces,
  );

  /// Formate le message à inclure dans l'historique transmis à l'IA.
  String toConversationEntry() {
    if (isUser) {
      final effectiveText = text.isEmpty && attachments.isNotEmpty
          ? 'Analyse les fichiers joints et applique les modifications correspondantes.'
          : text;
      final promptBody = promptText ?? effectiveText;
      if (attachments.isEmpty) {
        return 'Utilisateur : $promptBody';
      }
      final buffer = StringBuffer('Utilisateur : $promptBody');
      for (final attachment in attachments) {
        if (attachment.isImage) {
          buffer.write(
            '\n[Fichier image joint : "${attachment.name}" (${attachment.mimeType})]',
          );
        } else if (attachment.isText) {
          buffer.write(
            '\n[Fichier texte joint : "${attachment.name}" (${attachment.mimeType})]\n'
            '${attachment.textContent}',
          );
        }
      }
      return buffer.toString();
    }
    final rejected = failedResponse?.trim();
    if (rejected == null || rejected.isEmpty) {
      if (askUser != null) {
        return 'Assistant : $text\n'
            'Questions posées : ${jsonEncode(askUser!.toJson())}';
      }
      if (plan != null) {
        return 'Assistant : $text\n'
            'Plan proposé : ${jsonEncode(plan!.toJson())}';
      }
      return 'Assistant : $text';
    }
    return 'Assistant (ERREUR À CORRIGER) : $text\n'
        'Réponse précédente invalide :\n$rejected';
  }
}
