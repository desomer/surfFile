/// Modèle immuable des diagnostics de couverture 360° et cohérence Métier+UX↔QA ([QaCoherenceIssue]).
library;

import 'package:flutter/foundation.dart';

import '../spec_coherence_issue.dart';
import 'qa_forge_stage.dart';

/// Anomalie de cohérence, trou de couverture de test ou alerte syntaxique Gherkin/TDD relevée sur le volet QA.
@immutable
class QaCoherenceIssue {
  /// Construit un diagnostic de cohérence QA immuable.
  const QaCoherenceIssue({
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

  /// Identifiant unique du diagnostic QA.
  final String id;

  /// Gravité du problème relevé.
  final CoherenceSeverity severity;

  /// Étape du wizard QA principalement concernée.
  final QaForgeStage stage;

  /// Code technique du contrôle (ex. `QA-RG-UNCOVERED`, `QA-OUTLINE-VAR`).
  final String code;

  /// Titre concis du diagnostic.
  final String title;

  /// Description détaillée du trou de couverture ou de l'incohérence détectée.
  final String description;

  /// Référence à l'élément ciblé (identifiant ou code `FIX-xxx`, `FEAT-xxx`, `SCN-xxx`, `TDD-xxx`, `RG-xxx`).
  final String targetRef;

  /// Action corrective concrète recommandée.
  final String suggestion;

  /// Origine de la détection (`'local'` ou `'ai'`).
  final String source;

  /// Vérifie les invariants du diagnostic de cohérence QA.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'QaCoherenceIssue.id ne peut pas être vide.',
      );
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'QaCoherenceIssue.title ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  QaCoherenceIssue copyWith({
    String? id,
    CoherenceSeverity? severity,
    QaForgeStage? stage,
    String? code,
    String? title,
    String? description,
    String? targetRef,
    String? suggestion,
    String? source,
  }) => QaCoherenceIssue(
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

  /// Sérialise le diagnostic QA en JSON.
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

  /// Désérialise un diagnostic de cohérence QA depuis JSON.
  factory QaCoherenceIssue.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'QaCoherenceIssue doit être un objet JSON.',
      );
    }
    final rawTitle = (raw['title'] as String?)?.trim() ?? '';
    final title = rawTitle.isEmpty ? 'Anomalie QA' : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final rawSource = (raw['source'] as String?)?.trim() ?? '';
    final issue = QaCoherenceIssue(
      id: rawId.isEmpty ? 'qa_coh_${title.hashCode.abs()}' : rawId,
      severity: CoherenceSeverity.fromJson(raw['severity']),
      stage: QaForgeStage.fromJson(raw['stage']),
      code: rawCode.isEmpty ? 'QA-COH' : rawCode,
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
      other is QaCoherenceIssue &&
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
