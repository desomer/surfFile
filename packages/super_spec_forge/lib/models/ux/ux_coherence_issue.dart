/// Modèle immuable des diagnostics de cohérence Métier↔UX ([UxCoherenceIssue]).
library;

import 'package:flutter/foundation.dart';

import '../spec_coherence_issue.dart';
import 'ux_forge_stage.dart';

/// Anomalie de cohérence, rupture de traçabilité ou recommandation ergonomique relevée sur le volet UX.
@immutable
class UxCoherenceIssue {
  /// Construit un diagnostic de cohérence UX immuable.
  const UxCoherenceIssue({
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

  /// Identifiant unique du diagnostic UX.
  final String id;

  /// Gravité du problème relevé.
  final CoherenceSeverity severity;

  /// Étape du wizard UX principalement concernée.
  final UxForgeStage stage;

  /// Code technique du contrôle (ex. `UX-ROUTE-ORPHAN`, `UX-RG-UNBOUND`).
  final String code;

  /// Titre concis du diagnostic.
  final String title;

  /// Description détaillée de l'écart ou du risque UX/métier.
  final String description;

  /// Référence à l'élément ciblé (identifiant ou code `JRN-xxx`, `SCR-xxx`, `RG-xxx`).
  final String targetRef;

  /// Action corrective concrète recommandée.
  final String suggestion;

  /// Origine de la détection (`'local'` ou `'ai'`).
  final String source;

  /// Vérifie les invariants du diagnostic de cohérence UX.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'UxCoherenceIssue.id ne peut pas être vide.',
      );
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'UxCoherenceIssue.title ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  UxCoherenceIssue copyWith({
    String? id,
    CoherenceSeverity? severity,
    UxForgeStage? stage,
    String? code,
    String? title,
    String? description,
    String? targetRef,
    String? suggestion,
    String? source,
  }) => UxCoherenceIssue(
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

  /// Sérialise le diagnostic UX en JSON.
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

  /// Désérialise un diagnostic de cohérence UX depuis JSON.
  factory UxCoherenceIssue.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'UxCoherenceIssue doit être un objet JSON.',
      );
    }
    final rawTitle = (raw['title'] as String?)?.trim() ?? '';
    final title = rawTitle.isEmpty ? 'Anomalie UX' : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final rawSource = (raw['source'] as String?)?.trim() ?? '';
    final issue = UxCoherenceIssue(
      id: rawId.isEmpty ? 'ux_coh_${title.hashCode.abs()}' : rawId,
      severity: CoherenceSeverity.fromJson(raw['severity']),
      stage: UxForgeStage.fromJson(raw['stage']),
      code: rawCode.isEmpty ? 'UX-COH' : rawCode,
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
      other is UxCoherenceIssue &&
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
