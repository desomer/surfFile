/// Modèle immuable des diagnostics de cohérence financière et de couverture WBS/Run/Risques ([CostCoherenceIssue]).
library;

import 'package:flutter/foundation.dart';

import '../spec_coherence_issue.dart';
import 'cost_forge_stage.dart';

/// Anomalie de cohérence financière, oubli de chiffrage ou alerte FinOps relevée sur le volet Coûts.
@immutable
class CostCoherenceIssue {
  /// Construit un diagnostic de cohérence FinOps immuable.
  const CostCoherenceIssue({
    required this.id,
    required this.severity,
    required this.stage,
    required this.code,
    required this.title,
    required this.description,
    this.targetRef = '',
    this.suggestion = '',
    this.source = 'local',
  });

  /// Identifiant unique du diagnostic de chiffrage.
  final String id;

  /// Gravité du problème relevé.
  final CoherenceSeverity severity;

  /// Étape du wizard de chiffrage principalement concernée.
  final CostForgeStage stage;

  /// Code technique du contrôle (ex. `COST-EF-UNPRICED`, `COST-PROFILE-MISSING`).
  final String code;

  /// Titre concis du diagnostic.
  final String title;

  /// Description détaillée de l'écart budgétaire ou du trou de couverture détecté.
  final String description;

  /// Référence à l'élément ciblé (identifiant ou code `WBS-xxx`, `RUN-xxx`, `RSK-xxx`, `EF-xxx`, `SCR-xxx`).
  final String targetRef;

  /// Action corrective concrète recommandée.
  final String suggestion;

  /// Origine de la détection (`'local'` ou `'ai'`).
  final String source;

  /// Vérifie les invariants du diagnostic de cohérence FinOps.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'CostCoherenceIssue.id ne peut pas être vide.',
      );
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'CostCoherenceIssue.title ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  CostCoherenceIssue copyWith({
    String? id,
    CoherenceSeverity? severity,
    CostForgeStage? stage,
    String? code,
    String? title,
    String? description,
    String? targetRef,
    String? suggestion,
    String? source,
  }) => CostCoherenceIssue(
    id: id ?? this.id,
    severity: severity ?? this.severity,
    stage: stage ?? this.stage,
    code: code ?? this.code,
    title: title ?? this.title,
    description: description ?? this.description,
    targetRef: targetRef ?? this.targetRef,
    suggestion: suggestion ?? this.suggestion,
    source: source ?? this.source,
  );

  /// Sérialise le diagnostic FinOps en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'severity': severity.name,
    'stage': stage.name,
    'code': code,
    'title': title,
    'description': description,
    'targetRef': targetRef,
    'suggestion': suggestion,
    'source': source,
  };

  /// Désérialise un diagnostic de cohérence FinOps depuis JSON.
  factory CostCoherenceIssue.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'CostCoherenceIssue doit être un objet JSON.',
      );
    }
    final rawTitle = (raw['title'] as String?)?.trim() ?? '';
    final title = rawTitle.isEmpty ? 'Anomalie Coûts' : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final rawSource = (raw['source'] as String?)?.trim() ?? '';
    final issue = CostCoherenceIssue(
      id: rawId.isEmpty ? 'cost_coh_${title.hashCode.abs()}' : rawId,
      severity: CoherenceSeverity.fromJson(raw['severity']),
      stage: CostForgeStage.fromJson(raw['stage']),
      code: rawCode.isEmpty ? 'COST-COH' : rawCode,
      title: title,
      description: (raw['description'] as String?)?.trim() ?? '',
      targetRef: (raw['targetRef'] as String?)?.trim() ?? '',
      suggestion: (raw['suggestion'] as String?)?.trim() ?? '',
      source: rawSource.isEmpty ? 'local' : rawSource,
    );
    issue.validate();
    return issue;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostCoherenceIssue &&
          other.id == id &&
          other.severity == severity &&
          other.stage == stage &&
          other.code == code &&
          other.title == title &&
          other.description == description &&
          other.targetRef == targetRef &&
          other.suggestion == suggestion &&
          other.source == source;

  @override
  int get hashCode => Object.hash(
    id,
    severity,
    stage,
    code,
    title,
    description,
    targetRef,
    suggestion,
    source,
  );
}
