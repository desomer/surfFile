/// Définition des étapes du wizard IA spécialisé ([SpecForgeStage]) et de leur statut d'avancement ([SpecStageStatus]).
library;

import 'package:material_ui/material_ui.dart';

/// Étapes ordonnées du wizard de forge de spécifications.
enum SpecForgeStage {
  /// Étape 1 : Cadrage de l'idée, proposition de valeur, personas et contraintes.
  vision(
    stepNumber: 1,
    shortLabel: 'Cadrage',
    title: 'Cadrage & Acteurs',
    agentTitle: 'Product Strategist',
    agentSubtitle: 'Clarification de l’idée, objectifs, personas et contraintes',
    icon: Icons.lightbulb_outline_rounded,
  ),

  /// Étape 2 : Cahier des charges fonctionnel, cas d'usage et exigences non fonctionnelles.
  specifications(
    stepNumber: 2,
    shortLabel: 'Cahier des charges',
    title: 'Cahier des charges',
    agentTitle: 'Business Analyst',
    agentSubtitle: 'Modules, exigences fonctionnelles, cas d’usage et ENF',
    icon: Icons.assignment_outlined,
  ),

  /// Étape 3 : Objets métiers, attributs typés, relations et cycles de vie.
  businessObjects(
    stepNumber: 3,
    shortLabel: 'Objets métiers',
    title: 'Objets métiers',
    agentTitle: 'Domain Modeler',
    agentSubtitle: 'Entités, attributs typés, relations et cycles de vie',
    icon: Icons.hub_outlined,
  ),

  /// Étape 4 : Règles de gestion structurées (validations, calculs, transitions, droits).
  businessRules(
    stepNumber: 4,
    shortLabel: 'Règles de gestion',
    title: 'Règles de gestion',
    agentTitle: 'Rule Architect',
    agentSubtitle:
        'Règles RG-xxx : validations, calculs, transitions et habilitations',
    icon: Icons.gavel_rounded,
  ),

  /// Étape 5 : Audit de cohérence inter-étapes, revue finale et exports.
  reviewExport(
    stepNumber: 5,
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
  });

  /// Numéro d'ordre affiché (`1..5`).
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

  /// Étape précédente, ou `null` pour la première étape.
  SpecForgeStage? get previous =>
      index > 0 ? SpecForgeStage.values[index - 1] : null;

  /// Étape suivante, ou `null` pour la dernière étape.
  SpecForgeStage? get next => index < SpecForgeStage.values.length - 1
      ? SpecForgeStage.values[index + 1]
      : null;

  /// Résout une étape depuis son nom sérialisé en JSON, avec repli sur [vision].
  static SpecForgeStage fromJson(Object? raw) {
    if (raw is String) {
      for (final stage in SpecForgeStage.values) {
        if (stage.name == raw) return stage;
      }
    }
    return SpecForgeStage.vision;
  }
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
