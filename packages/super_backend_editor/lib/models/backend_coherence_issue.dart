/// Modèles immuables de diagnostic de cohérence entre la spécification Design
/// importée et la surcouche d'implémentation Backend ([BackendCoherenceIssue]).
library;

import 'package:flutter/foundation.dart';

/// Niveau de gravité d'une anomalie de cohérence Backend.
enum BackendIssueSeverity {
  /// Erreur bloquante empêchant l'exécution nominale d'une collection, route ou script.
  error('Erreur'),

  /// Avertissement de dérive, d'orphelin ou de configuration incomplète.
  warning('Avertissement'),

  /// Information ou recommandation d'alignement.
  info('Information');

  const BackendIssueSeverity(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise une gravité depuis JSON.
  static BackendIssueSeverity fromJson(Object? raw) {
    if (raw is String) {
      for (final sev in BackendIssueSeverity.values) {
        if (sev.name == raw.trim()) return sev;
      }
    }
    throw FormatException('Gravité de cohérence Backend inconnue : $raw');
  }
}

/// Catégorie fonctionnelle d'un diagnostic de cohérence Backend.
enum BackendIssueCategory {
  /// Anomalie dans un JSON Schema ou un contrat de modèle/DTO.
  contractSchema('Schéma de contrat'),

  /// Référence de Value Object introuvable ou incohérente.
  valueObjectRef('Référence Value Object'),

  /// Désalignement entre un modèle Design et sa collection `super_backend`.
  collectionMapping('Mapping de collection'),

  /// Liaison d'endpoint invalide (collection, Use Case ou contrat manquant/orphelin).
  endpointBinding('Liaison d’endpoint'),

  /// Fichier de script QuickJS référencé mais introuvable sur disque.
  scriptMissing('Script QuickJS manquant'),

  /// Clé secrète d'environnement non renseignée localement pour les tests.
  environmentSecret('Secret d’environnement');

  const BackendIssueCategory(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise une catégorie de diagnostic depuis JSON.
  static BackendIssueCategory fromJson(Object? raw) {
    if (raw is String) {
      for (final cat in BackendIssueCategory.values) {
        if (cat.name == raw.trim()) return cat;
      }
    }
    throw FormatException('Catégorie de cohérence Backend inconnue : $raw');
  }
}

/// Diagnostic unitaire immuable produit par l'analyseur de cohérence Backend.
@immutable
class BackendCoherenceIssue {
  /// Crée un diagnostic de cohérence immuable.
  const BackendCoherenceIssue({
    required this.id,
    required this.severity,
    required this.category,
    required this.title,
    required this.message,
    this.targetId,
    this.suggestion,
  });

  /// Identifiant stable du diagnostic.
  final String id;

  /// Niveau de gravité (`error`, `warning`, `info`).
  final BackendIssueSeverity severity;

  /// Catégorie fonctionnelle du diagnostic.
  final BackendIssueCategory category;

  /// Titre synthétique affiché dans la liste d'audit.
  final String title;

  /// Message explicatif détaillé.
  final String message;

  /// Identifiant optionnel de l'artefact ciblé (modèle, collection, endpoint, clé).
  final String? targetId;

  /// Action corrective suggérée à l'utilisateur ou à l'assistant IA.
  final String? suggestion;

  /// Vrai si la gravité vaut [BackendIssueSeverity.error].
  bool get isError => severity == BackendIssueSeverity.error;

  /// Vrai si la gravité vaut [BackendIssueSeverity.warning].
  bool get isWarning => severity == BackendIssueSeverity.warning;

  /// Vrai si la gravité vaut [BackendIssueSeverity.info].
  bool get isInfo => severity == BackendIssueSeverity.info;

  /// Vérifie les invariants du diagnostic.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BackendCoherenceIssue.id requis.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException('BackendCoherenceIssue.title requis.');
    }
    if (message.trim().isEmpty) {
      throw const FormatException('BackendCoherenceIssue.message requis.');
    }
  }

  /// Retourne une copie modifiée.
  BackendCoherenceIssue copyWith({
    String? id,
    BackendIssueSeverity? severity,
    BackendIssueCategory? category,
    String? title,
    String? message,
    String? targetId,
    bool clearTargetId = false,
    String? suggestion,
    bool clearSuggestion = false,
  }) => BackendCoherenceIssue(
    id: id ?? this.id,
    severity: severity ?? this.severity,
    category: category ?? this.category,
    title: title ?? this.title,
    message: message ?? this.message,
    targetId: clearTargetId ? null : (targetId ?? this.targetId),
    suggestion: clearSuggestion ? null : (suggestion ?? this.suggestion),
  );

  /// Sérialise le diagnostic en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'severity': severity.name,
    'category': category.name,
    'title': title,
    'message': message,
    if (targetId != null && targetId!.trim().isNotEmpty) 'targetId': targetId,
    if (suggestion != null && suggestion!.trim().isNotEmpty)
      'suggestion': suggestion,
  };

  /// Désérialise un diagnostic depuis JSON.
  factory BackendCoherenceIssue.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('BackendCoherenceIssue invalide.');
    }
    final rawTarget = (raw['targetId'] as String?)?.trim();
    final rawSuggestion = (raw['suggestion'] as String?)?.trim();
    final issue = BackendCoherenceIssue(
      id: (raw['id'] as String?)?.trim() ?? '',
      severity: BackendIssueSeverity.fromJson(raw['severity']),
      category: BackendIssueCategory.fromJson(raw['category']),
      title: (raw['title'] as String?)?.trim() ?? '',
      message: (raw['message'] as String?)?.trim() ?? '',
      targetId: (rawTarget == null || rawTarget.isEmpty) ? null : rawTarget,
      suggestion: (rawSuggestion == null || rawSuggestion.isEmpty)
          ? null
          : rawSuggestion,
    );
    issue.validate();
    return issue;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendCoherenceIssue &&
          other.id == id &&
          other.severity == severity &&
          other.category == category &&
          other.title == title &&
          other.message == message &&
          other.targetId == targetId &&
          other.suggestion == suggestion;

  @override
  int get hashCode => Object.hash(
    id,
    severity,
    category,
    title,
    message,
    targetId,
    suggestion,
  );
}
