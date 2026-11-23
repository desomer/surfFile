/// Modèles immuables d'Example Mapping BDD à 4 couleurs ([ExampleMapStory],
/// [ExampleMapRule], [ExampleMapExample], [ExampleMapQuestion]) destinés à
/// affiner les objets métiers et préparer les règles de gestion `RG-xxx` ainsi
/// que les jeux d'essais et scénarios Gherkin.
library;

import 'package:flutter/foundation.dart';

import 'business_rule_spec.dart';

/// Catégorie d'une carte verte d'exemple concret dans un tableau d'Example Mapping.
enum ExampleMapExampleKind {
  /// Cas nominal passant.
  nominal('Nominal', 'Cas nominal attendu'),

  /// Cas aux limites (seuils, min/max, longueurs exactes).
  boundary('Borne / Limite', 'Valeur aux bornes ou seuil critique'),

  /// Cas d'erreur ou de rejet métier.
  error('Erreur / Rejet', 'Données invalides ou précondition non respectée'),

  /// Cas illustrant une transition du cycle de vie.
  stateTransition(
    'Transition d’état',
    'Passage d’un état du cycle de vie à un autre',
  ),

  /// Cas d'habilitation ou de contrôle d'accès par rôle.
  permission('Habilitation', 'Comportement selon le rôle ou persona');

  /// Construit une catégorie d'exemple.
  const ExampleMapExampleKind(this.label, this.description);

  /// Libellé court affiché sur le badge de la carte verte.
  final String label;

  /// Description explicative.
  final String description;

  /// Résout une catégorie depuis JSON ou un alias courant.
  static ExampleMapExampleKind fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      switch (norm) {
        case 'nominal':
        case 'happy':
        case 'valid':
        case 'standard':
          return ExampleMapExampleKind.nominal;
        case 'boundary':
        case 'limit':
        case 'edge':
        case 'borne':
        case 'limite':
          return ExampleMapExampleKind.boundary;
        case 'error':
        case 'invalid':
        case 'reject':
        case 'rejected':
        case 'erreur':
        case 'rejet':
          return ExampleMapExampleKind.error;
        case 'statetransition':
        case 'state_transition':
        case 'state-transition':
        case 'transition':
        case 'lifecycle':
          return ExampleMapExampleKind.stateTransition;
        case 'permission':
        case 'auth':
        case 'role':
        case 'habilitation':
          return ExampleMapExampleKind.permission;
      }
    }
    return ExampleMapExampleKind.nominal;
  }
}

/// Carte verte : exemple concret illustrant une règle métier ([ExampleMapRule]).
@immutable
class ExampleMapExample {
  /// Construit une carte verte immuable.
  ExampleMapExample({
    required this.id,
    required this.title,
    this.kind = ExampleMapExampleKind.nominal,
    this.given = '',
    this.when = '',
    this.then = '',
    Map<String, Object?> inputValues = const <String, Object?>{},
    Map<String, Object?> expectedOutcome = const <String, Object?>{},
    List<String> discoveredAttributes = const <String>[],
    this.linkedFixtureId = '',
    this.notes = '',
  }) : inputValues = Map<String, Object?>.unmodifiable(
         _deepFreezeMap(inputValues),
       ),
       expectedOutcome = Map<String, Object?>.unmodifiable(
         _deepFreezeMap(expectedOutcome),
       ),
       discoveredAttributes = List<String>.unmodifiable(discoveredAttributes);

  /// Identifiant technique unique de l'exemple.
  final String id;

  /// Titre court et parlant du scénario concret.
  final String title;

  /// Nature du cas illustré (nominal, borne, erreur, transition, habilitation).
  final ExampleMapExampleKind kind;

  /// Contexte initial (`Étant donné...`).
  final String given;

  /// Action ou événement déclencheur (`Quand...`).
  final String when;

  /// Résultat attendu (`Alors...`).
  final String then;

  /// Valeurs concrètes d'entrée indexées par chemin d'attribut (ex. `montantHt: 1200`).
  final Map<String, Object?> inputValues;

  /// Valeurs ou état attendus en sortie (ex. `statut: "validee"`, `remise: 120`).
  final Map<String, Object?> expectedOutcome;

  /// Attributs, valeurs énumérées, contraintes ou états révélés par cet exemple.
  final List<String> discoveredAttributes;

  /// Identifiant éventuel de la fixture QA générée à partir de cet exemple.
  final String linkedFixtureId;

  /// Notes complémentaires sur l'exemple.
  final String notes;

  /// Vérifie les invariants de l'exemple.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'ExampleMapExample.id ne peut pas être vide.',
      );
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'ExampleMapExample.title ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  ExampleMapExample copyWith({
    String? id,
    String? title,
    ExampleMapExampleKind? kind,
    String? given,
    String? when,
    String? then,
    Map<String, Object?>? inputValues,
    Map<String, Object?>? expectedOutcome,
    List<String>? discoveredAttributes,
    String? linkedFixtureId,
    String? notes,
  }) => ExampleMapExample(
    id: id ?? this.id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    given: given ?? this.given,
    when: when ?? this.when,
    then: then ?? this.then,
    inputValues: inputValues ?? this.inputValues,
    expectedOutcome: expectedOutcome ?? this.expectedOutcome,
    discoveredAttributes: discoveredAttributes ?? this.discoveredAttributes,
    linkedFixtureId: linkedFixtureId ?? this.linkedFixtureId,
    notes: notes ?? this.notes,
  );

  /// Sérialise l'exemple en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'kind': kind.name,
    if (given.isNotEmpty) 'given': given,
    if (when.isNotEmpty) 'when': when,
    if (then.isNotEmpty) 'then': then,
    if (inputValues.isNotEmpty) 'inputValues': inputValues,
    if (expectedOutcome.isNotEmpty) 'expectedOutcome': expectedOutcome,
    if (discoveredAttributes.isNotEmpty)
      'discoveredAttributes': discoveredAttributes,
    if (linkedFixtureId.isNotEmpty) 'linkedFixtureId': linkedFixtureId,
    if (notes.isNotEmpty) 'notes': notes,
  };

  /// Désérialise un exemple depuis JSON.
  factory ExampleMapExample.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'ExampleMapExample doit être un objet JSON.',
      );
    }
    final title =
        ((raw['title'] ?? raw['name'] ?? raw['scenario']) as String?)?.trim() ??
        '';
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final effectiveTitle = title.isEmpty ? 'Exemple concret' : title;
    final example = ExampleMapExample(
      id: rawId.isEmpty ? 'ex_${effectiveTitle.hashCode.abs()}' : rawId,
      title: effectiveTitle,
      kind: ExampleMapExampleKind.fromJson(raw['kind']),
      given: (raw['given'] as String?)?.trim() ?? '',
      when: (raw['when'] as String?)?.trim() ?? '',
      then: (raw['then'] as String?)?.trim() ?? '',
      inputValues: _objectMap(raw['inputValues'] ?? raw['inputs']),
      expectedOutcome: _objectMap(raw['expectedOutcome'] ?? raw['expected']),
      discoveredAttributes: _stringList(raw['discoveredAttributes']),
      linkedFixtureId: (raw['linkedFixtureId'] as String?)?.trim() ?? '',
      notes: (raw['notes'] as String?)?.trim() ?? '',
    );
    example.validate();
    return example;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExampleMapExample &&
          other.id == id &&
          other.title == title &&
          other.kind == kind &&
          other.given == given &&
          other.when == when &&
          other.then == then &&
          _deepMapEquals(other.inputValues, inputValues) &&
          _deepMapEquals(other.expectedOutcome, expectedOutcome) &&
          listEquals(other.discoveredAttributes, discoveredAttributes) &&
          other.linkedFixtureId == linkedFixtureId &&
          other.notes == notes;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    kind,
    given,
    when,
    then,
    _deepMapHash(inputValues),
    _deepMapHash(expectedOutcome),
    Object.hashAll(discoveredAttributes),
    linkedFixtureId,
    notes,
  );
}

/// Carte bleue : règle métier explorée et illustrée par des cartes vertes ([ExampleMapExample]).
@immutable
class ExampleMapRule {
  /// Construit une carte bleue immuable.
  ExampleMapRule({
    required this.id,
    required this.title,
    this.description = '',
    this.category = BusinessRuleCategory.validation,
    this.linkedRuleId = '',
    List<String> targetObjectIds = const <String>[],
    List<String> targetAttributes = const <String>[],
    List<ExampleMapExample> examples = const <ExampleMapExample>[],
  }) : targetObjectIds = List<String>.unmodifiable(targetObjectIds),
       targetAttributes = List<String>.unmodifiable(targetAttributes),
       examples = List<ExampleMapExample>.unmodifiable(examples);

  /// Identifiant technique unique de la carte bleue.
  final String id;

  /// Énoncé synthétique de la règle métier.
  final String title;

  /// Précision ou rationale métier.
  final String description;

  /// Catégorie métier cible en vue d'une promotion en `RG-xxx`.
  final BusinessRuleCategory category;

  /// Identifiant ou code (`RG-xxx`) de la [BusinessRuleSpec] associée/promue.
  final String linkedRuleId;

  /// Identifiants des objets métiers concernés.
  final List<String> targetObjectIds;

  /// Chemins d'attributs concernés (ex. `Commande.montantHt`).
  final List<String> targetAttributes;

  /// Cartes vertes rattachées à cette règle.
  final List<ExampleMapExample> examples;

  /// Indique si cette carte bleue est déjà rattachée ou promue en `BusinessRuleSpec`.
  bool get isPromoted => linkedRuleId.trim().isNotEmpty;

  /// Vérifie les invariants de la règle et de ses exemples.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ExampleMapRule.id ne peut pas être vide.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'ExampleMapRule.title ne peut pas être vide.',
      );
    }
    final seenIds = <String>{};
    for (final ex in examples) {
      ex.validate();
      if (!seenIds.add(ex.id)) {
        throw FormatException('Exemple dupliqué dans règle $id : ${ex.id}');
      }
    }
  }

  /// Retourne une copie modifiée.
  ExampleMapRule copyWith({
    String? id,
    String? title,
    String? description,
    BusinessRuleCategory? category,
    String? linkedRuleId,
    List<String>? targetObjectIds,
    List<String>? targetAttributes,
    List<ExampleMapExample>? examples,
  }) => ExampleMapRule(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    category: category ?? this.category,
    linkedRuleId: linkedRuleId ?? this.linkedRuleId,
    targetObjectIds: targetObjectIds ?? this.targetObjectIds,
    targetAttributes: targetAttributes ?? this.targetAttributes,
    examples: examples ?? this.examples,
  );

  /// Sérialise la règle bleue en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    if (description.isNotEmpty) 'description': description,
    'category': category.name,
    if (linkedRuleId.isNotEmpty) 'linkedRuleId': linkedRuleId,
    if (targetObjectIds.isNotEmpty) 'targetObjectIds': targetObjectIds,
    if (targetAttributes.isNotEmpty) 'targetAttributes': targetAttributes,
    'examples': [for (final ex in examples) ex.toJson()],
  };

  /// Désérialise une règle bleue depuis JSON.
  factory ExampleMapRule.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('ExampleMapRule doit être un objet JSON.');
    }
    final rawTitle = ((raw['title'] ?? raw['rule']) as String?)?.trim() ?? '';
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final effectiveTitle = rawTitle.isEmpty ? 'Règle à préciser' : rawTitle;
    final rule = ExampleMapRule(
      id: rawId.isEmpty ? 'emr_${effectiveTitle.hashCode.abs()}' : rawId,
      title: effectiveTitle,
      description: (raw['description'] as String?)?.trim() ?? '',
      category: BusinessRuleCategory.fromJson(raw['category']),
      linkedRuleId: (raw['linkedRuleId'] as String?)?.trim() ?? '',
      targetObjectIds: _stringList(raw['targetObjectIds']),
      targetAttributes: _stringList(raw['targetAttributes']),
      examples: [
        if (raw['examples'] is List)
          for (final item in raw['examples'] as List)
            ExampleMapExample.fromJson(item),
      ],
    );
    rule.validate();
    return rule;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExampleMapRule &&
          other.id == id &&
          other.title == title &&
          other.description == description &&
          other.category == category &&
          other.linkedRuleId == linkedRuleId &&
          listEquals(other.targetObjectIds, targetObjectIds) &&
          listEquals(other.targetAttributes, targetAttributes) &&
          listEquals(other.examples, examples);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    category,
    linkedRuleId,
    Object.hashAll(targetObjectIds),
    Object.hashAll(targetAttributes),
    Object.hashAll(examples),
  );
}

/// Carte rouge : question ouverte ou zone d'ombre découverte pendant l'atelier.
@immutable
class ExampleMapQuestion {
  /// Construit une carte rouge immuable.
  const ExampleMapQuestion({
    required this.id,
    required this.question,
    this.impact = '',
    this.resolved = false,
    this.answer = '',
    this.linkedObjectId = '',
    this.linkedAttributePath = '',
  });

  /// Identifiant unique de la question rouge.
  final String id;

  /// Formulation claire de la zone d'ombre à trancher.
  final String question;

  /// Impact métier attendu sur les attributs, contraintes ou règles.
  final String impact;

  /// Indique si la question a reçu une réponse validée.
  final bool resolved;

  /// Décision ou réponse retenue une fois tranchée.
  final String answer;

  /// Objet métier éventuellement concerné par cette question.
  final String linkedObjectId;

  /// Chemin d'attribut éventuellement concerné.
  final String linkedAttributePath;

  /// Vérifie les invariants de la carte rouge.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'ExampleMapQuestion.id ne peut pas être vide.',
      );
    }
    if (question.trim().isEmpty) {
      throw const FormatException(
        'ExampleMapQuestion.question ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  ExampleMapQuestion copyWith({
    String? id,
    String? question,
    String? impact,
    bool? resolved,
    String? answer,
    String? linkedObjectId,
    String? linkedAttributePath,
  }) => ExampleMapQuestion(
    id: id ?? this.id,
    question: question ?? this.question,
    impact: impact ?? this.impact,
    resolved: resolved ?? this.resolved,
    answer: answer ?? this.answer,
    linkedObjectId: linkedObjectId ?? this.linkedObjectId,
    linkedAttributePath: linkedAttributePath ?? this.linkedAttributePath,
  );

  /// Sérialise la question rouge en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'question': question,
    if (impact.isNotEmpty) 'impact': impact,
    'resolved': resolved,
    if (answer.isNotEmpty) 'answer': answer,
    if (linkedObjectId.isNotEmpty) 'linkedObjectId': linkedObjectId,
    if (linkedAttributePath.isNotEmpty)
      'linkedAttributePath': linkedAttributePath,
  };

  /// Désérialise une question rouge depuis JSON.
  factory ExampleMapQuestion.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'ExampleMapQuestion doit être un objet JSON.',
      );
    }
    final text =
        ((raw['question'] ?? raw['title'] ?? raw['text']) as String?)?.trim() ??
        '';
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final effectiveQuestion = text.isEmpty ? 'Question à clarifier' : text;
    final question = ExampleMapQuestion(
      id: rawId.isEmpty ? 'emq_${effectiveQuestion.hashCode.abs()}' : rawId,
      question: effectiveQuestion,
      impact: (raw['impact'] as String?)?.trim() ?? '',
      resolved: raw['resolved'] == true,
      answer: (raw['answer'] as String?)?.trim() ?? '',
      linkedObjectId: (raw['linkedObjectId'] as String?)?.trim() ?? '',
      linkedAttributePath: (raw['linkedAttributePath'] as String?)?.trim() ?? '',
    );
    question.validate();
    return question;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExampleMapQuestion &&
          other.id == id &&
          other.question == question &&
          other.impact == impact &&
          other.resolved == resolved &&
          other.answer == answer &&
          other.linkedObjectId == linkedObjectId &&
          other.linkedAttributePath == linkedAttributePath;

  @override
  int get hashCode => Object.hash(
    id,
    question,
    impact,
    resolved,
    answer,
    linkedObjectId,
    linkedAttributePath,
  );
}

/// Carte jaune : tableau complet d'Example Mapping ancré sur un objet métier
/// (et optionnellement sur un cas d'usage et des exigences fonctionnelles).
@immutable
class ExampleMapStory {
  /// Construit un tableau d'Example Mapping immuable.
  ExampleMapStory({
    required this.id,
    required this.code,
    required this.title,
    this.description = '',
    this.targetObjectId = '',
    this.useCaseId = '',
    List<String> requirementIds = const <String>[],
    List<ExampleMapRule> rules = const <ExampleMapRule>[],
    List<ExampleMapQuestion> questions = const <ExampleMapQuestion>[],
    List<String> refinementNotes = const <String>[],
  }) : requirementIds = List<String>.unmodifiable(requirementIds),
       rules = List<ExampleMapRule>.unmodifiable(rules),
       questions = List<ExampleMapQuestion>.unmodifiable(questions),
       refinementNotes = List<String>.unmodifiable(refinementNotes);

  /// Identifiant technique unique du tableau.
  final String id;

  /// Code court séquentiel (`EM-001`, `EM-002`...).
  final String code;

  /// Titre de la story / périmètre métier exploré.
  final String title;

  /// Description synthétique du contexte et de l'objectif d'affinage.
  final String description;

  /// Identifiant du [BusinessObjectSpec] principal affiné par ce tableau.
  final String targetObjectId;

  /// Identifiant optionnel du [SpecUseCase] rattaché.
  final String useCaseId;

  /// Codes ou identifiants des exigences fonctionnelles (`EXF-xxx`) liées.
  final List<String> requirementIds;

  /// Cartes bleues (règles métier) contenant leurs cartes vertes (exemples).
  final List<ExampleMapRule> rules;

  /// Cartes rouges (zones d'ombre / questions ouvertes).
  final List<ExampleMapQuestion> questions;

  /// Journal synthétique des affinages apportés aux objets métiers suite à ce tableau.
  final List<String> refinementNotes;

  /// Nombre total de cartes vertes dans ce tableau.
  int get totalExampleCount =>
      rules.fold<int>(0, (sum, r) => sum + r.examples.length);

  /// Nombre de questions rouges encore non résolues.
  int get openQuestionCount => questions.where((q) => !q.resolved).length;

  /// Nombre de questions rouges résolues.
  int get resolvedQuestionCount => questions.where((q) => q.resolved).length;

  /// Nombre de cartes bleues déjà liées/promues vers `BusinessRuleSpec`.
  int get promotedRuleCount => rules.where((r) => r.isPromoted).length;

  /// Vérifie les invariants du tableau et de ses cartes enfants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ExampleMapStory.id ne peut pas être vide.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'ExampleMapStory.title ne peut pas être vide.',
      );
    }
    final ruleIds = <String>{};
    for (final r in rules) {
      r.validate();
      if (!ruleIds.add(r.id)) {
        throw FormatException('Règle bleue dupliquée dans $id : ${r.id}');
      }
    }
    final questionIds = <String>{};
    for (final q in questions) {
      q.validate();
      if (!questionIds.add(q.id)) {
        throw FormatException('Question rouge dupliquée dans $id : ${q.id}');
      }
    }
  }

  /// Retourne une copie modifiée.
  ExampleMapStory copyWith({
    String? id,
    String? code,
    String? title,
    String? description,
    String? targetObjectId,
    String? useCaseId,
    List<String>? requirementIds,
    List<ExampleMapRule>? rules,
    List<ExampleMapQuestion>? questions,
    List<String>? refinementNotes,
  }) => ExampleMapStory(
    id: id ?? this.id,
    code: code ?? this.code,
    title: title ?? this.title,
    description: description ?? this.description,
    targetObjectId: targetObjectId ?? this.targetObjectId,
    useCaseId: useCaseId ?? this.useCaseId,
    requirementIds: requirementIds ?? this.requirementIds,
    rules: rules ?? this.rules,
    questions: questions ?? this.questions,
    refinementNotes: refinementNotes ?? this.refinementNotes,
  );

  /// Sérialise le tableau complet en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'title': title,
    if (description.isNotEmpty) 'description': description,
    if (targetObjectId.isNotEmpty) 'targetObjectId': targetObjectId,
    if (useCaseId.isNotEmpty) 'useCaseId': useCaseId,
    if (requirementIds.isNotEmpty) 'requirementIds': requirementIds,
    'rules': [for (final r in rules) r.toJson()],
    'questions': [for (final q in questions) q.toJson()],
    if (refinementNotes.isNotEmpty) 'refinementNotes': refinementNotes,
  };

  /// Désérialise un tableau d'Example Mapping depuis JSON.
  factory ExampleMapStory.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'ExampleMapStory doit être un objet JSON.',
      );
    }
    final rawTitle = ((raw['title'] ?? raw['story']) as String?)?.trim() ?? '';
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final effectiveTitle = rawTitle.isEmpty ? 'Story métier' : rawTitle;
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final story = ExampleMapStory(
      id: rawId.isEmpty ? 'em_${effectiveTitle.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'EM' : rawCode,
      title: effectiveTitle,
      description: (raw['description'] as String?)?.trim() ?? '',
      targetObjectId:
          ((raw['targetObjectId'] ?? raw['objectId']) as String?)?.trim() ?? '',
      useCaseId: (raw['useCaseId'] as String?)?.trim() ?? '',
      requirementIds: _stringList(raw['requirementIds']),
      rules: [
        if (raw['rules'] is List)
          for (final item in raw['rules'] as List)
            ExampleMapRule.fromJson(item),
      ],
      questions: [
        if (raw['questions'] is List)
          for (final item in raw['questions'] as List)
            ExampleMapQuestion.fromJson(item),
      ],
      refinementNotes: _stringList(raw['refinementNotes']),
    );
    story.validate();
    return story;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExampleMapStory &&
          other.id == id &&
          other.code == code &&
          other.title == title &&
          other.description == description &&
          other.targetObjectId == targetObjectId &&
          other.useCaseId == useCaseId &&
          listEquals(other.requirementIds, requirementIds) &&
          listEquals(other.rules, rules) &&
          listEquals(other.questions, questions) &&
          listEquals(other.refinementNotes, refinementNotes);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    title,
    description,
    targetObjectId,
    useCaseId,
    Object.hashAll(requirementIds),
    Object.hashAll(rules),
    Object.hashAll(questions),
    Object.hashAll(refinementNotes),
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item != null && item.toString().trim().isNotEmpty)
        item.toString().trim(),
  ];
}

Map<String, Object?> _objectMap(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  return <String, Object?>{
    for (final entry in raw.entries)
      if (entry.key != null) entry.key.toString(): _deepFreezeValue(entry.value),
  };
}

Map<String, Object?> _deepFreezeMap(Map<String, Object?> raw) =>
    <String, Object?>{
      for (final entry in raw.entries)
        entry.key: _deepFreezeValue(entry.value),
    };

Object? _deepFreezeValue(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in value.entries)
        if (entry.key != null)
          entry.key.toString(): _deepFreezeValue(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable([
      for (final item in value) _deepFreezeValue(item),
    ]);
  }
  return value;
}

bool _deepMapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key)) return false;
    if (!_deepValueEquals(a[key], b[key])) return false;
  }
  return true;
}

bool _deepValueEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    return _deepMapEquals(a, b);
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepValueEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepMapHash(Map<String, Object?> map) => Object.hashAll(
  map.entries.map((e) => Object.hash(e.key, _deepValueHash(e.value))),
);

int _deepValueHash(Object? value) {
  if (value is Map<String, Object?>) return _deepMapHash(value);
  if (value is List) return Object.hashAll(value.map(_deepValueHash));
  return value.hashCode;
}
