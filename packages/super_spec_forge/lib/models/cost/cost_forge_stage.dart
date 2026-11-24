/// Étapes ordonnées du wizard FinOps & Chiffrage ([CostForgeStage]) et état conversationnel par étape ([CostStageState]).
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../spec_forge_stage.dart';
import '../spec_stage_chat.dart';

/// Étapes ordonnées du quatrième wizard dédié au chiffrage Build (CAPEX / WBS), Run (OPEX) et TCO.
enum CostForgeStage {
  /// Étape 1 : Grille TJM, mode de delivery, ratios transverses et accélération IA.
  rateCardAssumptions(
    stepNumber: 1,
    shortLabel: 'TJM & Équipe',
    title: 'Équipe, TJM & Hypothèses',
    agentTitle: 'FinOps & Delivery Strategist',
    agentSubtitle:
        'Grille TJM, mode de delivery, ratios transverses et accélération IA',
    icon: Icons.badge_outlined,
  ),

  /// Étape 2 : Découpage WBS traçable, charges j/h PERT 3 points et lots MoSCoW.
  buildWbs(
    stepNumber: 2,
    shortLabel: 'Build (WBS)',
    title: 'Chiffrage Build (CAPEX / WBS)',
    agentTitle: 'WBS & PERT Cost Estimator',
    agentSubtitle:
        'Découpage WBS traçable, charges j/h PERT 3 points et lots MoSCoW',
    icon: Icons.account_tree_outlined,
  ),

  /// Étape 3 : Coûts récurrents d'hébergement Cloud, BDD, APIs/LLM, licences SaaS et TMA/MCO.
  runOpex(
    stepNumber: 3,
    shortLabel: 'Run & Cloud',
    title: 'Coûts Run, Cloud & Licences (OPEX)',
    agentTitle: 'Cloud & FinOps Architect',
    agentSubtitle:
        'Hébergement Cloud, BDD, APIs/LLM, licences SaaS et TMA/MCO',
    icon: Icons.cloud_outlined,
  ),

  /// Étape 4 : Synthèse TCO 1/3/5 ans, provisions risques, cohérence financière et exports.
  tcoReviewExport(
    stepNumber: 4,
    shortLabel: 'TCO & Export',
    title: 'Synthèse TCO, Risques & Export',
    agentTitle: 'Executive TCO & Risk Auditor',
    agentSubtitle:
        'TCO 1/3/5 ans, provisions risques, cohérence financière et exports',
    icon: Icons.analytics_outlined,
  );

  /// Construit une étape du wizard de chiffrage.
  const CostForgeStage({
    required this.stepNumber,
    required this.shortLabel,
    required this.title,
    required this.agentTitle,
    required this.agentSubtitle,
    required this.icon,
  });

  /// Numéro d'ordre affiché (`1..4`).
  final int stepNumber;

  /// Libellé compact affiché dans le stepper horizontal.
  final String shortLabel;

  /// Titre complet de l'étape de chiffrage.
  final String title;

  /// Nom du rôle de l'agent IA spécialisé associé à cette étape.
  final String agentTitle;

  /// Sous-titre résumant la mission de l'agent IA pour cette étape.
  final String agentSubtitle;

  /// Icône représentative de l'étape dans le stepper.
  final IconData icon;

  /// Étape précédente, ou `null` pour la première étape.
  CostForgeStage? get previous =>
      index > 0 ? CostForgeStage.values[index - 1] : null;

  /// Étape suivante, ou `null` pour la dernière étape.
  CostForgeStage? get next => index < CostForgeStage.values.length - 1
      ? CostForgeStage.values[index + 1]
      : null;

  /// Résout une étape de chiffrage depuis son nom JSON ou un alias courant, avec repli sur [rateCardAssumptions].
  static CostForgeStage fromJson(Object? raw) {
    if (raw is int) {
      for (final stage in CostForgeStage.values) {
        if (stage.stepNumber == raw) return stage;
      }
      return CostForgeStage.rateCardAssumptions;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      for (final stage in CostForgeStage.values) {
        if (stage.name == trimmed) return stage;
      }
      final norm = trimmed.toLowerCase();
      for (final stage in CostForgeStage.values) {
        if (stage.name.toLowerCase() == norm ||
            stage.shortLabel.toLowerCase() == norm ||
            stage.title.toLowerCase() == norm) {
          return stage;
        }
      }
      switch (norm) {
        case '1':
        case 'rate_card_assumptions':
        case 'rate-card-assumptions':
        case 'rate_card':
        case 'rate-card':
        case 'ratecard':
        case 'assumptions':
        case 'rates':
        case 'tjm':
        case 'hypotheses':
        case 'hypothèses':
          return CostForgeStage.rateCardAssumptions;
        case '2':
        case 'build_wbs':
        case 'build-wbs':
        case 'wbs':
        case 'build':
        case 'capex':
          return CostForgeStage.buildWbs;
        case '3':
        case 'run_opex':
        case 'run-opex':
        case 'run':
        case 'opex':
        case 'cloud':
        case 'licenses':
        case 'licences':
          return CostForgeStage.runOpex;
        case '4':
        case 'tco_review_export':
        case 'tco-review-export':
        case 'review_export':
        case 'reviewexport':
        case 'tco':
        case 'risks':
        case 'risques':
        case 'review':
        case 'export':
        case 'audit':
          return CostForgeStage.tcoReviewExport;
      }
    }
    return CostForgeStage.rateCardAssumptions;
  }
}

/// État conversationnel et statut d'avancement d'une étape du wizard FinOps & Chiffrage.
@immutable
class CostStageState {
  /// Construit un état d'étape de chiffrage immuable.
  CostStageState({
    required this.stage,
    this.status = SpecStageStatus.notStarted,
    List<SpecChatMessage> messages = const <SpecChatMessage>[],
    this.stageSummary = '',
    this.readyToAdvance = false,
  }) : messages = List<SpecChatMessage>.unmodifiable(messages);

  /// Étape du wizard de chiffrage concernée.
  final CostForgeStage stage;

  /// Statut d'avancement de l'étape.
  final SpecStageStatus status;

  /// Historique des échanges avec l'agent spécialisé de cette étape.
  final List<SpecChatMessage> messages;

  /// Synthèse consolidée produite à la fin de l'étape pour alimenter les suivantes.
  final String stageSummary;

  /// Vrai lorsque l'agent a indiqué que l'étape peut être validée.
  final bool readyToAdvance;

  /// Vérifie les invariants de l'état d'étape de chiffrage.
  void validate() {
    for (final message in messages) {
      if (message.id.trim().isEmpty) {
        throw const FormatException(
          'CostStageState contient un message sans identifiant.',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  CostStageState copyWith({
    CostForgeStage? stage,
    SpecStageStatus? status,
    List<SpecChatMessage>? messages,
    String? stageSummary,
    bool? readyToAdvance,
  }) => CostStageState(
    stage: stage ?? this.stage,
    status: status ?? this.status,
    messages: messages ?? this.messages,
    stageSummary: stageSummary ?? this.stageSummary,
    readyToAdvance: readyToAdvance ?? this.readyToAdvance,
  );

  /// Sérialise l'état de l'étape en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'stage': stage.name,
    'status': status.name,
    'messages': [for (final m in messages) m.toJson()],
    'stageSummary': stageSummary,
    'readyToAdvance': readyToAdvance,
  };

  /// Désérialise un état d'étape de chiffrage depuis JSON.
  factory CostStageState.fromJson(
    Object? raw, {
    CostForgeStage fallbackStage = CostForgeStage.rateCardAssumptions,
  }) {
    if (raw is! Map) {
      throw const FormatException('CostStageState doit être un objet JSON.');
    }
    final stage = raw['stage'] != null
        ? CostForgeStage.fromJson(raw['stage'])
        : fallbackStage;
    final state = CostStageState(
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
    state.validate();
    return state;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostStageState &&
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
