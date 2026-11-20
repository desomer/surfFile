/// Modèles immuables de cadrage de l'idée et des acteurs ([SpecVision], [SpecPersona]).
library;

import 'package:flutter/foundation.dart';

/// Acteur ou persona cible identifié lors du cadrage initial.
@immutable
class SpecPersona {
  /// Construit un persona métier immuable.
  SpecPersona({
    required this.id,
    required this.name,
    this.role = '',
    List<String> goals = const <String>[],
    List<String> painPoints = const <String>[],
  }) : goals = List<String>.unmodifiable(goals),
       painPoints = List<String>.unmodifiable(painPoints);

  /// Identifiant stable du persona (ex. `persona_admin`).
  final String id;

  /// Nom lisible du rôle ou persona (ex. `Gestionnaire de flotte`).
  final String name;

  /// Description synthétique des responsabilités.
  final String role;

  /// Objectifs principaux poursuivis dans l'application.
  final List<String> goals;

  /// Points de friction actuels à résoudre.
  final List<String> painPoints;

  /// Vérifie les invariants du persona.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('SpecPersona.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('SpecPersona.name ne peut pas être vide.');
    }
  }

  /// Retourne une copie modifiée.
  SpecPersona copyWith({
    String? id,
    String? name,
    String? role,
    List<String>? goals,
    List<String>? painPoints,
  }) => SpecPersona(
    id: id ?? this.id,
    name: name ?? this.name,
    role: role ?? this.role,
    goals: goals ?? this.goals,
    painPoints: painPoints ?? this.painPoints,
  );

  /// Sérialise ce persona en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'role': role,
    'goals': goals,
    'painPoints': painPoints,
  };

  /// Désérialise un persona depuis JSON.
  factory SpecPersona.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('SpecPersona doit être un objet JSON.');
    }
    final id = (raw['id'] as String?)?.trim() ?? '';
    final name = (raw['name'] as String?)?.trim() ?? '';
    final role = (raw['role'] as String?)?.trim() ?? '';
    final persona = SpecPersona(
      id: id.isEmpty ? 'persona_${name.hashCode.abs()}' : id,
      name: name.isEmpty ? 'Acteur sans nom' : name,
      role: role,
      goals: _stringList(raw['goals']),
      painPoints: _stringList(raw['painPoints']),
    );
    persona.validate();
    return persona;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecPersona &&
          other.id == id &&
          other.name == name &&
          other.role == role &&
          listEquals(other.goals, goals) &&
          listEquals(other.painPoints, painPoints);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    role,
    Object.hashAll(goals),
    Object.hashAll(painPoints),
  );
}

/// Synthèse structurée de la phase 1 (Cadrage & Acteurs).
@immutable
class SpecVision {
  /// Construit un modèle immuable de cadrage.
  SpecVision({
    this.ideaSummary = '',
    this.problemStatement = '',
    this.valueProposition = '',
    List<String> objectives = const <String>[],
    List<SpecPersona> personas = const <SpecPersona>[],
    List<String> constraints = const <String>[],
    List<String> outOfScope = const <String>[],
  }) : objectives = List<String>.unmodifiable(objectives),
       personas = List<SpecPersona>.unmodifiable(personas),
       constraints = List<String>.unmodifiable(constraints),
       outOfScope = List<String>.unmodifiable(outOfScope);

  /// Vision vide initiale.
  static final SpecVision empty = SpecVision();

  /// Résumé structuré de l'idée initiale.
  final String ideaSummary;

  /// Problème métier ou utilisateur adressé.
  final String problemStatement;

  /// Proposition de valeur principale du produit.
  final String valueProposition;

  /// Liste des objectifs mesurables ou stratégiques.
  final List<String> objectives;

  /// Acteurs / personas identifiés.
  final List<SpecPersona> personas;

  /// Contraintes techniques, réglementaires, budgétaires ou organisationnelles.
  final List<String> constraints;

  /// Éléments explicitement exclus du périmètre initial.
  final List<String> outOfScope;

  /// Vrai si au moins une donnée de cadrage a été renseignée.
  bool get hasContent =>
      ideaSummary.trim().isNotEmpty ||
      problemStatement.trim().isNotEmpty ||
      valueProposition.trim().isNotEmpty ||
      objectives.isNotEmpty ||
      personas.isNotEmpty ||
      constraints.isNotEmpty ||
      outOfScope.isNotEmpty;

  /// Valide la vision et chacun de ses personas.
  void validate() {
    final ids = <String>{};
    for (final persona in personas) {
      persona.validate();
      if (!ids.add(persona.id)) {
        throw FormatException('Identifiant de persona dupliqué : ${persona.id}');
      }
    }
  }

  /// Retourne une copie modifiée.
  SpecVision copyWith({
    String? ideaSummary,
    String? problemStatement,
    String? valueProposition,
    List<String>? objectives,
    List<SpecPersona>? personas,
    List<String>? constraints,
    List<String>? outOfScope,
  }) => SpecVision(
    ideaSummary: ideaSummary ?? this.ideaSummary,
    problemStatement: problemStatement ?? this.problemStatement,
    valueProposition: valueProposition ?? this.valueProposition,
    objectives: objectives ?? this.objectives,
    personas: personas ?? this.personas,
    constraints: constraints ?? this.constraints,
    outOfScope: outOfScope ?? this.outOfScope,
  );

  /// Sérialise la vision en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'ideaSummary': ideaSummary,
    'problemStatement': problemStatement,
    'valueProposition': valueProposition,
    'objectives': objectives,
    'personas': [for (final p in personas) p.toJson()],
    'constraints': constraints,
    'outOfScope': outOfScope,
  };

  /// Désérialise une vision depuis JSON.
  factory SpecVision.fromJson(Object? raw) {
    if (raw == null) return SpecVision.empty;
    if (raw is! Map) {
      throw const FormatException('SpecVision doit être un objet JSON.');
    }
    final rawPersonas = raw['personas'];
    final personas = rawPersonas is List
        ? [for (final p in rawPersonas) SpecPersona.fromJson(p)]
        : const <SpecPersona>[];
    final vision = SpecVision(
      ideaSummary: (raw['ideaSummary'] as String?)?.trim() ?? '',
      problemStatement: (raw['problemStatement'] as String?)?.trim() ?? '',
      valueProposition: (raw['valueProposition'] as String?)?.trim() ?? '',
      objectives: _stringList(raw['objectives']),
      personas: personas,
      constraints: _stringList(raw['constraints']),
      outOfScope: _stringList(raw['outOfScope']),
    );
    vision.validate();
    return vision;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecVision &&
          other.ideaSummary == ideaSummary &&
          other.problemStatement == problemStatement &&
          other.valueProposition == valueProposition &&
          listEquals(other.objectives, objectives) &&
          listEquals(other.personas, personas) &&
          listEquals(other.constraints, constraints) &&
          listEquals(other.outOfScope, outOfScope);

  @override
  int get hashCode => Object.hash(
    ideaSummary,
    problemStatement,
    valueProposition,
    Object.hashAll(objectives),
    Object.hashAll(personas),
    Object.hashAll(constraints),
    Object.hashAll(outOfScope),
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
