/// Étapes ordonnées du wizard UX spécialisé ([UxForgeStage]) et état conversationnel par étape ([UxStageState]).
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../spec_forge_stage.dart';
import '../spec_stage_chat.dart';

/// Étapes ordonnées du second wizard dédié à la conception UX et à l'architecture d'écrans.
enum UxForgeStage {
  /// Étape 1 : Parcours utilisateurs bout-en-bout, embranchements et critères de succès.
  userJourneys(
    stepNumber: 1,
    shortLabel: 'Parcours',
    title: 'Parcours utilisateurs & Flows',
    agentTitle: 'User Journey Architect',
    agentSubtitle:
        'Parcours bout-en-bout, embranchements et critères de succès par persona',
    icon: Icons.route_outlined,
  ),

  /// Étape 2 : Architecture de l'information, shell applicatif, thème visuel et routes.
  iaNavigation(
    stepNumber: 2,
    shortLabel: 'Navigation',
    title: 'Architecture & Navigation',
    agentTitle: 'Information Architect',
    agentSubtitle:
        'Shell applicatif, identité visuelle, routes et matrice d’accès',
    icon: Icons.account_tree_outlined,
  ),

  /// Étape 3 : Schémas directeurs d'écrans, zones spatiales, liaisons métiers et actions RG.
  screenBlueprints(
    stepNumber: 3,
    shortLabel: 'Écrans',
    title: 'Écrans, Zones & Interactions',
    agentTitle: 'Interaction & Screen Designer',
    agentSubtitle:
        'Patterns spatiaux, zones, liaisons métiers, actions RG et états UX',
    icon: Icons.dashboard_customize_outlined,
  ),

  /// Étape 4 : Audit de cohérence Métier↔UX, génération DESIGN.md et export vers SuperDesigner.
  uxReviewExport(
    stepNumber: 4,
    shortLabel: 'Revue & Export',
    title: 'Audit UX & Export SuperDesigner',
    agentTitle: 'UX Auditor & Handoff Lead',
    agentSubtitle:
        'Traçabilité Métier↔UX, charte DESIGN.md et squelettes d’écrans',
    icon: Icons.verified_user_outlined,
  );

  /// Construit une étape du wizard UX.
  const UxForgeStage({
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

  /// Titre complet de l'étape UX.
  final String title;

  /// Nom du rôle de l'agent IA spécialisé associé à cette étape.
  final String agentTitle;

  /// Sous-titre résumant la mission de l'agent IA pour cette étape.
  final String agentSubtitle;

  /// Icône représentative de l'étape dans le stepper.
  final IconData icon;

  /// Étape précédente, ou `null` pour la première étape.
  UxForgeStage? get previous =>
      index > 0 ? UxForgeStage.values[index - 1] : null;

  /// Étape suivante, ou `null` pour la dernière étape.
  UxForgeStage? get next => index < UxForgeStage.values.length - 1
      ? UxForgeStage.values[index + 1]
      : null;

  /// Résout une étape UX depuis son nom JSON ou un alias courant, avec repli sur [userJourneys].
  static UxForgeStage fromJson(Object? raw) {
    if (raw is int) {
      for (final stage in UxForgeStage.values) {
        if (stage.stepNumber == raw) return stage;
      }
      return UxForgeStage.userJourneys;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      for (final stage in UxForgeStage.values) {
        if (stage.name == trimmed) return stage;
      }
      final norm = trimmed.toLowerCase();
      for (final stage in UxForgeStage.values) {
        if (stage.name.toLowerCase() == norm ||
            stage.shortLabel.toLowerCase() == norm ||
            stage.title.toLowerCase() == norm) {
          return stage;
        }
      }
      switch (norm) {
        case '1':
        case 'user_journeys':
        case 'user-journeys':
        case 'journeys':
        case 'journey':
        case 'flows':
          return UxForgeStage.userJourneys;
        case '2':
        case 'ia_navigation':
        case 'ia-navigation':
        case 'nav':
        case 'ia':
        case 'architecture':
        case 'routes':
          return UxForgeStage.iaNavigation;
        case '3':
        case 'screen_blueprints':
        case 'screen-blueprints':
        case 'screens':
        case 'screen':
        case 'blueprints':
        case 'ecrans':
          return UxForgeStage.screenBlueprints;
        case '4':
        case 'ux_review_export':
        case 'ux-review-export':
        case 'review_export':
        case 'reviewexport':
        case 'review':
        case 'export':
        case 'audit':
          return UxForgeStage.uxReviewExport;
      }
    }
    return UxForgeStage.userJourneys;
  }
}

/// État conversationnel et statut d'avancement d'une étape du wizard UX.
@immutable
class UxStageState {
  /// Construit un état d'étape UX immuable.
  UxStageState({
    required this.stage,
    this.status = SpecStageStatus.notStarted,
    List<SpecChatMessage> messages = const <SpecChatMessage>[],
    this.stageSummary = '',
    this.readyToAdvance = false,
  }) : messages = List<SpecChatMessage>.unmodifiable(messages);

  /// Étape du wizard UX concernée.
  final UxForgeStage stage;

  /// Statut d'avancement de l'étape.
  final SpecStageStatus status;

  /// Historique des échanges avec l'agent spécialisé de cette étape.
  final List<SpecChatMessage> messages;

  /// Synthèse consolidée produite à la fin de l'étape pour alimenter les suivantes.
  final String stageSummary;

  /// Vrai lorsque l'agent a indiqué que l'étape peut être validée.
  final bool readyToAdvance;

  /// Vérifie les invariants de l'état d'étape UX.
  void validate() {
    for (final message in messages) {
      if (message.id.trim().isEmpty) {
        throw const FormatException(
          'UxStageState contient un message sans identifiant.',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  UxStageState copyWith({
    UxForgeStage? stage,
    SpecStageStatus? status,
    List<SpecChatMessage>? messages,
    String? stageSummary,
    bool? readyToAdvance,
  }) => UxStageState(
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

  /// Désérialise un état d'étape UX depuis JSON.
  factory UxStageState.fromJson(
    Object? raw, {
    UxForgeStage fallbackStage = UxForgeStage.userJourneys,
  }) {
    if (raw is! Map) {
      throw const FormatException('UxStageState doit être un objet JSON.');
    }
    final stage = raw['stage'] != null
        ? UxForgeStage.fromJson(raw['stage'])
        : fallbackStage;
    final state = UxStageState(
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
      other is UxStageState &&
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
