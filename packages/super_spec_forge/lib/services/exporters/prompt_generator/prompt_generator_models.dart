/// Modèles immuables des prompts IA en Architecture Hexagonale
/// ([BuildHexaPromptRole], [BuildHexaPromptSpec], [BuildItemPromptGroup]).
library;

import 'package:flutter/foundation.dart';

import '../../../models/build_design_item.dart';

/// Nature d'un prompt de génération de code en Architecture Hexagonale.
enum BuildHexaPromptRole {
  /// Implémentation de la couche métier (Domain) ou applicative (Use Case / Saga).
  implementation(
    label: 'Implémentation',
    subtitle: 'Code de production en Architecture Hexagonale (pur métier / application)',
  ),

  /// Suite de tests unitaires TDD isolée de l'infrastructure.
  unitTest(
    label: 'Tests unitaires',
    subtitle:
        'Tests unitaires TDD rapides et déterministes sans infrastructure',
  ),

  /// Port sortant Repository, mapper et adaptateur de persistance (modèles uniquement).
  persistence(
    label: 'Persistance',
    subtitle: 'Port sortant Repository, entité infra, mapper et adaptateur de persistance',
  );

  const BuildHexaPromptRole({required this.label, required this.subtitle});

  /// Libellé court affiché sur le badge du prompt.
  final String label;

  /// Description synthétique du périmètre couvert par le prompt.
  final String subtitle;
}

/// Prompt individuel prêt à être copié et exécuté.
@immutable
class BuildHexaPromptSpec {
  /// Crée une fiche de prompt IA en Architecture Hexagonale.
  const BuildHexaPromptSpec({
    required this.id,
    required this.item,
    required this.role,
    required this.title,
    required this.summary,
    required this.promptMarkdown,
  });

  /// Identifiant unique stable (`<kind>:<itemId>:<role>`).
  final String id;

  /// Élément de design auquel se rattache ce prompt.
  final BuildDesignItem item;

  /// Rôle architectural du prompt (`implementation`, `unitTest`, `persistence`).
  final BuildHexaPromptRole role;

  /// Titre lisible du prompt.
  final String title;

  /// Résumé court du livrable attendu.
  final String summary;

  /// Contenu complet du prompt au format Markdown.
  final String promptMarkdown;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildHexaPromptSpec &&
          other.id == id &&
          other.item == item &&
          other.role == role &&
          other.title == title &&
          other.summary == summary &&
          other.promptMarkdown == promptMarkdown;

  @override
  int get hashCode =>
      Object.hash(id, item, role, title, summary, promptMarkdown);
}

/// Groupe de prompts IA rattachés à un même [BuildDesignItem] sélectionné.
@immutable
class BuildItemPromptGroup {
  /// Crée un groupe de prompts pour [item].
  BuildItemPromptGroup({
    required this.item,
    required List<BuildHexaPromptSpec> prompts,
  }) : prompts = List<BuildHexaPromptSpec>.unmodifiable(prompts);

  /// Élément de design sélectionné (`Modèle`, `Use Case` ou `Saga`).
  final BuildDesignItem item;

  /// Liste ordonnée des `x` prompts IA générés pour [item] :
  /// - 3 prompts pour un `Modèle` (`Implémentation`, `Tests unitaires`, `Persistance`),
  /// - 2 prompts pour un `Use Case` ou une `Saga` (`Implémentation`, `Tests unitaires`).
  final List<BuildHexaPromptSpec> prompts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildItemPromptGroup &&
          other.item == item &&
          listEquals(other.prompts, prompts);

  @override
  int get hashCode => Object.hash(item, Object.hashAll(prompts));
}
