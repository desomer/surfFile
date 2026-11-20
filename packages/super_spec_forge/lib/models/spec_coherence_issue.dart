/// Modèles immuables des diagnostics de cohérence inter-étapes ([SpecCoherenceIssue]).
library;

import 'package:flutter/foundation.dart';

import 'spec_forge_stage.dart';

/// Sévérité d'une anomalie ou recommandation détectée sur la spécification.
enum CoherenceSeverity {
  error('Erreur'),
  warning('Attention'),
  info('Suggestion');

  /// Construit une sévérité.
  const CoherenceSeverity(this.label);

  /// Libellé français.
  final String label;

  /// Résout depuis JSON.
  static CoherenceSeverity fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final s in CoherenceSeverity.values) {
        if (s.name == norm || s.label.toLowerCase() == norm) return s;
      }
    }
    return CoherenceSeverity.warning;
  }
}

/// Anomalie de cohérence ou trou fonctionnel relevé sur le projet.
@immutable
class SpecCoherenceIssue {
  /// Construit un diagnostic de cohérence immuable.
  const SpecCoherenceIssue({
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

  /// Identifiant unique du diagnostic.
  final String id;

  /// Gravité du problème.
  final CoherenceSeverity severity;

  /// Étape du wizard concernée.
  final SpecForgeStage stage;

  /// Code technique du contrôle (ex. `COH-RG-TARGET`).
  final String code;

  /// Titre concis.
  final String title;

  /// Description détaillée du problème de cohérence.
  final String description;

  /// Référence à l'élément fautif (id ou code `RG-xxx` / `EXF-xxx`).
  final String targetRef;

  /// Action corrective proposée.
  final String suggestion;

  /// Origine de la détection (`local` ou `ai`).
  final String source;

  /// Copie modifiée.
  SpecCoherenceIssue copyWith({
    String? id,
    CoherenceSeverity? severity,
    SpecForgeStage? stage,
    String? code,
    String? title,
    String? description,
    String? targetRef,
    String? suggestion,
    String? source,
  }) => SpecCoherenceIssue(
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

  /// Sérialise en JSON.
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

  /// Désérialise depuis JSON.
  factory SpecCoherenceIssue.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'SpecCoherenceIssue doit être un objet JSON.',
      );
    }
    final title = (raw['title'] as String?)?.trim() ?? 'Anomalie';
    final id = (raw['id'] as String?)?.trim() ?? '';
    return SpecCoherenceIssue(
      id: id.isEmpty ? 'coh_${title.hashCode.abs()}' : id,
      severity: CoherenceSeverity.fromJson(raw['severity']),
      stage: SpecForgeStage.fromJson(raw['stage']),
      code: (raw['code'] as String?)?.trim() ?? 'COH',
      title: title,
      description: (raw['description'] as String?)?.trim() ?? '',
      targetRef: (raw['targetRef'] as String?)?.trim() ?? '',
      suggestion: (raw['suggestion'] as String?)?.trim() ?? '',
      source: (raw['source'] as String?)?.trim() ?? 'local',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecCoherenceIssue &&
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
