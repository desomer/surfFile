/// Construction des prompts par tour pour les agents IA spécialisés de `super_spec_forge` ([SpecPromptBuilder]).
library;

import 'dart:convert';

import 'package:super_container_layout/super_container_layout.dart';

import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_stage_chat.dart';
import 'spec_stage_agent.dart';

/// Assemble les prompts contextuels et consignes de questionnement pour chaque étape.
abstract final class SpecPromptBuilder {
  /// Construit la directive de questionnement adaptée au niveau choisi et au tour courant.
  static String questioningDirective({
    required VibeQuestioningLevel level,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
  }) {
    if (forceFollowUpQuestions) {
      return 'NIVEAU DE QUESTIONNEMENT : + de questions demandé (2 à 4 questions complémentaires OBLIGATOIRES) — '
          'Pose impérativement 2 à 4 nouvelles questions ciblées et non redondantes via "askUser" '
          '(avec des valeurs "default" pertinentes) pour approfondir cette étape, et laisse "specPatch": null sur ce tour.';
    }
    if (afterAskUserReply) {
      return 'NIVEAU DE QUESTIONNEMENT : Réponses utilisateur reçues — '
          'INTERDICTION d’émettre "askUser" sur ce tour ("askUser": null obligatoire). '
          'Intègre les réponses dans un "specPatch" complet et structuré pour cette étape.';
    }
    return switch (level) {
      VibeQuestioningLevel.none =>
        'NIVEAU DE QUESTIONNEMENT : 0/4 (Aucun) — '
            'INTERDICTION d’émettre "askUser" ("askUser": null obligatoire). '
            'Produis directement un "specPatch" complet avec des hypothèses métier solides.',
      VibeQuestioningLevel.light =>
        'NIVEAU DE QUESTIONNEMENT : 1/4 (Léger, 1 à 2 questions) — '
            'Pose 1 à 2 questions clés via "askUser" (avec "default") pour lever les ambiguïtés majeures avant de produire "specPatch".',
      VibeQuestioningLevel.balanced =>
        'NIVEAU DE QUESTIONNEMENT : 2/4 (Équilibré, 2 à 4 questions) — '
            'Pose 2 à 4 questions structurées via "askUser" (avec "default") adaptées à cette étape avant de finaliser "specPatch".',
      VibeQuestioningLevel.thorough =>
        'NIVEAU DE QUESTIONNEMENT : 3/4 (Approfondi, 4 à 6 questions) — '
            'Pose 4 à 6 questions ciblées via "askUser" (avec "default") couvrant les choix métier, cas limites et contraintes de cette étape.',
      VibeQuestioningLevel.exhaustive =>
        'NIVEAU DE QUESTIONNEMENT : 4/4 (Exhaustif, 6 à 10 questions) — '
            'Pose 6 à 10 questions complètes via "askUser" (avec "default") pour couvrir l’ensemble des détails et cas limites de cette étape.',
    };
  }

  /// Construit le prompt automatique d'amorce lorsqu'on entre dans une étape sans historique.
  static String buildStageKickoffPrompt(
    SpecForgeProject project,
    SpecForgeStage stage,
  ) => switch (stage) {
    SpecForgeStage.vision =>
      'Voici l’idée initiale du projet « ${project.name} » : « ${project.initialIdea} ». '
          'Analyse cette idée, pose tes questions de cadrage pour clarifier la vision, les objectifs, les acteurs/personas et les contraintes.',
    SpecForgeStage.specifications =>
      'Nous passons à l’étape 2 (Cahier des charges). En t’appuyant sur le cadrage et les acteurs validés, '
          'pose les questions nécessaires (ou propose la structure) pour détailler les modules, exigences fonctionnelles MoSCoW, cas d’usage et exigences non fonctionnelles.',
    SpecForgeStage.businessObjects =>
      'Nous passons à l’étape 3 (Objets métiers). En t’appuyant sur le cadrage et le cahier des charges, '
          'pose les questions nécessaires pour modéliser les entités métiers, leurs attributs typés, leurs relations et leurs cycles de vie.',
    SpecForgeStage.businessRules =>
      'Nous passons à l’étape 4 (Règles de gestion). En t’appuyant sur les objets métiers et le cahier des charges, '
          'pose les questions nécessaires pour formaliser les règles RG-xxx (validations, calculs, transitions d’état, habilitations et déclencheurs).',
    SpecForgeStage.reviewExport =>
      'Nous passons à l’étape 5 (Revue globale & Cohérence). Audite l’ensemble du projet (cadrage, cahier des charges, objets métiers et règles de gestion), '
          'signale toute incohérence ou oubli éventuel et propose un résumé ou des questions d’arbitrage final.',
  };

  /// Assemble le prompt complet envoyé à l'agent de [stage] pour le tour courant.
  static String buildTurnPrompt({
    required SpecForgeProject project,
    required SpecForgeStage stage,
    required String userInput,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    int maxHistoryEntries = 10,
  }) {
    final agent = SpecStageAgent.forStage(stage);
    final stageState = project.stageStateFor(stage);
    final contextJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(project.toCompactContextJson(stage));

    final previousSummaries = <String>[];
    for (final s in SpecForgeStage.values) {
      if (s.index >= stage.index) break;
      final summary = project.stageStateFor(s).stageSummary.trim();
      if (summary.isNotEmpty) {
        previousSummaries.add('- Étape ${s.stepNumber} (${s.title}) : $summary');
      }
    }

    final history = _buildHistory(
      stageState.messages,
      maxEntries: maxHistoryEntries,
    );

    final buffer = StringBuffer()
      ..writeln(
        'ÉTAPE ACTIVE : ${stage.stepNumber}/5 — ${stage.title} (Agent : ${agent.stage.agentTitle})',
      )
      ..writeln()
      ..writeln(
        questioningDirective(
          level: questioningLevel,
          afterAskUserReply: afterAskUserReply,
          forceFollowUpQuestions: forceFollowUpQuestions,
        ),
      );

    if (previousSummaries.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('SYNTHÈSE DES ÉTAPES PRÉCÉDENTES :')
        ..writeln(previousSummaries.join('\n'));
    }

    buffer
      ..writeln()
      ..writeln('ÉTAT COURANT DU PROJET (JSON) :')
      ..writeln(contextJson);

    if (history.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('HISTORIQUE RÉCENT DE CETTE ÉTAPE :')
        ..writeln(history);
    }

    buffer
      ..writeln()
      ..writeln('DEMANDE UTILISATEUR POUR CE TOUR :')
      ..writeln(userInput.trim());

    return buffer.toString();
  }

  static String _buildHistory(
    List<SpecChatMessage> messages, {
    required int maxEntries,
  }) {
    if (messages.isEmpty) return '';
    final slice = messages.length <= maxEntries
        ? messages
        : messages.sublist(messages.length - maxEntries);
    return slice.map((m) => m.toConversationEntry()).join('\n');
  }
}
