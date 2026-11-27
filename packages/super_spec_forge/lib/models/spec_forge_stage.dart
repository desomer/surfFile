/// Définition des étapes du wizard IA spécialisé ([SpecForgeStage]) et de leur statut d'avancement ([SpecStageStatus]).
library;

import 'package:material_ui/material_ui.dart';

/// Étapes ordonnées du wizard de forge de spécifications.
enum SpecForgeStage {
  /// Étape 1 : Lexique métier et langage omniprésent (termes, synonymes, sigles).
  lexicon(
    stepNumber: 1,
    shortLabel: 'Lexique',
    title: 'Lexique métier',
    agentTitle: 'Ubiquitous Language Expert',
    agentSubtitle:
        'Définition des termes, synonymes, sigles et vocabulaire partagé',
    icon: Icons.menu_book_outlined,
  ),

  /// Étape 2 : Cadrage de l'idée, proposition de valeur, personas et contraintes.
  vision(
    stepNumber: 2,
    shortLabel: 'Cadrage',
    title: 'Cadrage & Acteurs',
    agentTitle: 'Product Strategist',
    agentSubtitle: 'Clarification de l’idée, objectifs, personas et contraintes',
    icon: Icons.lightbulb_outline_rounded,
  ),

  /// Étape 3 : Cahier des charges fonctionnel, cas d'usage et exigences non fonctionnelles.
  specifications(
    stepNumber: 3,
    shortLabel: 'Cahier des charges',
    title: 'Cahier des charges',
    agentTitle: 'Business Analyst',
    agentSubtitle: 'Modules, exigences fonctionnelles, cas d’usage et ENF',
    icon: Icons.assignment_outlined,
  ),

  /// Étape 4 : Event Storming (événements domaine, commandes, acteurs, agrégats, politiques, read models et hotspots).
  eventStorming(
    stepNumber: 4,
    shortLabel: 'Event Storming',
    title: 'Event Storming',
    agentTitle: 'Event Storming Facilitator',
    agentSubtitle:
        'Chronologie des événements, commandes, acteurs, agrégats, politiques, read models et hotspots',
    icon: Icons.bolt_rounded,
    isOptional: true,
  ),

  /// Étape 5 : Objets métiers, attributs typés, relations et cycles de vie.
  businessObjects(
    stepNumber: 5,
    shortLabel: 'Objets métiers',
    title: 'Objets métiers',
    agentTitle: 'Domain Modeler',
    agentSubtitle: 'Entités, attributs typés, relations et cycles de vie',
    icon: Icons.hub_outlined,
  ),

  /// Étape 6 : Example Mapping (Story jaune, Règles bleues, Exemples verts, Questions rouges).
  exampleMapping(
    stepNumber: 6,
    shortLabel: 'Example Map',
    title: 'Example Mapping',
    agentTitle: 'Example Mapper',
    agentSubtitle:
        'Exemples concrets, cas limites et zones d’ombre pour affiner les objets métiers',
    icon: Icons.view_kanban_outlined,
    isOptional: true,
  ),

  /// Étape 7 : Règles de gestion structurées (validations, calculs, transitions, droits).
  businessRules(
    stepNumber: 7,
    shortLabel: 'Règles de gestion',
    title: 'Règles de gestion',
    agentTitle: 'Rule Architect',
    agentSubtitle:
        'Règles RG-xxx : validations, calculs, transitions et habilitations',
    icon: Icons.gavel_rounded,
  ),

  /// Étape 8 : Audit de cohérence inter-étapes, revue finale et exports.
  reviewExport(
    stepNumber: 8,
    shortLabel: 'Revue & Export',
    title: 'Revue, Cohérence & Export',
    agentTitle: 'Consistency Auditor',
    agentSubtitle: 'Vérification inter-étapes et export des livrables',
    icon: Icons.verified_outlined,
  );

  /// Construit une étape du wizard.
  const SpecForgeStage({
    required this.stepNumber,
    required this.shortLabel,
    required this.title,
    required this.agentTitle,
    required this.agentSubtitle,
    required this.icon,
    this.isOptional = false,
  });

  /// Liste ordonnée des étapes de spécification pouvant être désactivées par feature.
  static const List<SpecForgeStage> optionalStages = <SpecForgeStage>[
    SpecForgeStage.eventStorming,
    SpecForgeStage.exampleMapping,
  ];

  /// Numéro d'ordre affiché (`1..8`).
  final int stepNumber;

  /// Libellé compact affiché dans le stepper horizontal.
  final String shortLabel;

  /// Titre complet de l'étape.
  final String title;

  /// Nom du rôle de l'agent IA spécialisé associé à cette étape.
  final String agentTitle;

  /// Sous-titre résumant la mission de l'agent IA pour cette étape.
  final String agentSubtitle;

  /// Icône représentative de l'étape dans le stepper.
  final IconData icon;

  /// Vrai si cette étape est optionnelle et peut être activée/désactivée par feature.
  final bool isOptional;

  /// Étape précédente, ou `null` pour la première étape.
  SpecForgeStage? get previous =>
      index > 0 ? SpecForgeStage.values[index - 1] : null;

  /// Étape suivante, ou `null` pour la dernière étape.
  SpecForgeStage? get next => index < SpecForgeStage.values.length - 1
      ? SpecForgeStage.values[index + 1]
      : null;

  /// Tente de résoudre une étape depuis son nom sérialisé en JSON, ou `null` si inconnue.
  static SpecForgeStage? tryFromJson(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    for (final stage in SpecForgeStage.values) {
      if (stage.name == trimmed) return stage;
    }
    final norm = trimmed.toLowerCase();
    switch (norm) {
      case 'event_storming':
      case 'event-storming':
      case 'eventstorming':
      case 'event_storm':
      case 'event-storm':
      case 'eventstorm':
        return SpecForgeStage.eventStorming;
      case 'example_mapping':
      case 'example-mapping':
      case 'examplemapping':
      case 'example_map':
      case 'example-map':
      case 'examplemap':
        return SpecForgeStage.exampleMapping;
    }
    return null;
  }

  /// Résout une étape depuis son nom sérialisé en JSON, avec repli sur [lexicon].
  static SpecForgeStage fromJson(Object? raw) =>
      tryFromJson(raw) ?? SpecForgeStage.lexicon;
}

/// État de progression d'une étape individuelle dans le wizard.
enum SpecStageStatus {
  /// Étape pas encore amorcée.
  notStarted('À démarrer'),

  /// Discussion ou édition en cours.
  inProgress('En cours'),

  /// Étape validée par l'utilisateur (reste rééditable à tout moment).
  validated('Validée');

  /// Construit un statut d'étape.
  const SpecStageStatus(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un [SpecStageStatus] depuis son nom JSON.
  static SpecStageStatus fromJson(Object? raw) {
    if (raw is String) {
      for (final status in SpecStageStatus.values) {
        if (status.name == raw) return status;
      }
    }
    return SpecStageStatus.notStarted;
  }
}
