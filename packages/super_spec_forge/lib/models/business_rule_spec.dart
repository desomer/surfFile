/// Modèles immuables des règles de gestion ([BusinessRuleSpec], [BusinessRuleCategory], [BusinessRulePriority]).
library;

import 'package:flutter/foundation.dart';

/// Catégorie fonctionnelle d'une règle de gestion.
enum BusinessRuleCategory {
  validation('Validation', 'Contrôle d’intégrité et de cohérence des données'),
  calculation('Calcul', 'Formule, agrégation ou valeur dérivée'),
  stateTransition(
    'Transition d’état',
    'Condition de passage d’un état de cycle de vie à un autre',
  ),
  permission('Habilitation', 'Droits d’accès ou d’action selon le rôle'),
  trigger('Déclencheur', 'Effet automatique suite à un événement métier');

  /// Construit une catégorie de règle de gestion.
  const BusinessRuleCategory(this.label, this.description);

  /// Libellé court affiché.
  final String label;

  /// Description explicative.
  final String description;

  /// Résout une catégorie depuis JSON.
  static BusinessRuleCategory fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      switch (norm) {
        case 'validation':
        case 'constraint':
        case 'contrainte':
          return BusinessRuleCategory.validation;
        case 'calculation':
        case 'calcul':
        case 'formula':
        case 'derived':
          return BusinessRuleCategory.calculation;
        case 'statetransition':
        case 'state_transition':
        case 'transition':
        case 'workflow':
          return BusinessRuleCategory.stateTransition;
        case 'permission':
        case 'authorization':
        case 'habilitation':
        case 'access':
          return BusinessRuleCategory.permission;
        case 'trigger':
        case 'event':
        case 'declencheur':
          return BusinessRuleCategory.trigger;
      }
    }
    return BusinessRuleCategory.validation;
  }
}

/// Criticité d'une règle de gestion.
enum BusinessRulePriority {
  critical('Critique'),
  high('Élevée'),
  medium('Moyenne'),
  low('Faible');

  /// Construit une priorité.
  const BusinessRulePriority(this.label);

  /// Libellé français.
  final String label;

  /// Résout une priorité depuis JSON.
  static BusinessRulePriority fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in BusinessRulePriority.values) {
        if (value.name.toLowerCase() == norm ||
            value.label.toLowerCase() == norm) {
          return value;
        }
      }
    }
    return BusinessRulePriority.high;
  }
}

/// Règle de gestion métier structurée (`Quand / Si / Alors`) rattachée aux objets métiers.
@immutable
class BusinessRuleSpec {
  /// Construit une règle de gestion immuable.
  BusinessRuleSpec({
    required this.id,
    required this.code,
    required this.title,
    this.category = BusinessRuleCategory.validation,
    this.priority = BusinessRulePriority.high,
    this.description = '',
    List<String> targetObjectIds = const <String>[],
    List<String> targetAttributes = const <String>[],
    this.trigger = '',
    this.condition = '',
    this.effect = '',
    this.errorMessage = '',
    List<String> examples = const <String>[],
    this.active = true,
  }) : targetObjectIds = List<String>.unmodifiable(targetObjectIds),
       targetAttributes = List<String>.unmodifiable(targetAttributes),
       examples = List<String>.unmodifiable(examples);

  /// Identifiant technique unique.
  final String id;

  /// Code métier unique (ex. `RG-001`).
  final String code;

  /// Intitulé synthétique de la règle.
  final String title;

  /// Catégorie métier.
  final BusinessRuleCategory category;

  /// Criticité de la règle.
  final BusinessRulePriority priority;

  /// Explication métier complète.
  final String description;

  /// Identifiants des [BusinessObjectSpec] concernés.
  final List<String> targetObjectIds;

  /// Noms ou chemins d'attributs concernés (ex. `Commande.montantTotal`).
  final List<String> targetAttributes;

  /// Événement déclencheur (`Quand ...`).
  final String trigger;

  /// Condition d'application (`Si ...`).
  final String condition;

  /// Action, calcul ou blocage appliqué (`Alors ...`).
  final String effect;

  /// Message affiché à l'utilisateur en cas de non-respect (pour une validation/permission).
  final String errorMessage;

  /// Exemples concrets / cas limites illustrant la règle.
  final List<String> examples;

  /// Indique si la règle est active dans le périmètre courant.
  final bool active;

  /// Vérifie les invariants de la règle.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BusinessRuleSpec.id ne peut pas être vide.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'BusinessRuleSpec.title ne peut pas être vide.',
      );
    }
  }

  /// Copie modifiée.
  BusinessRuleSpec copyWith({
    String? id,
    String? code,
    String? title,
    BusinessRuleCategory? category,
    BusinessRulePriority? priority,
    String? description,
    List<String>? targetObjectIds,
    List<String>? targetAttributes,
    String? trigger,
    String? condition,
    String? effect,
    String? errorMessage,
    List<String>? examples,
    bool? active,
  }) => BusinessRuleSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    title: title ?? this.title,
    category: category ?? this.category,
    priority: priority ?? this.priority,
    description: description ?? this.description,
    targetObjectIds: targetObjectIds ?? this.targetObjectIds,
    targetAttributes: targetAttributes ?? this.targetAttributes,
    trigger: trigger ?? this.trigger,
    condition: condition ?? this.condition,
    effect: effect ?? this.effect,
    errorMessage: errorMessage ?? this.errorMessage,
    examples: examples ?? this.examples,
    active: active ?? this.active,
  );

  /// Sérialise la règle en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'title': title,
    'category': category.name,
    'priority': priority.name,
    'description': description,
    'targetObjectIds': targetObjectIds,
    'targetAttributes': targetAttributes,
    'trigger': trigger,
    'condition': condition,
    'effect': effect,
    'errorMessage': errorMessage,
    'examples': examples,
    'active': active,
  };

  /// Désérialise une règle depuis JSON.
  factory BusinessRuleSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('BusinessRuleSpec doit être un objet JSON.');
    }
    final title = (raw['title'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final code = (raw['code'] as String?)?.trim() ?? '';
    final rule = BusinessRuleSpec(
      id: id.isEmpty ? 'rule_${title.hashCode.abs()}' : id,
      code: code.isEmpty ? 'RG' : code,
      title: title.isEmpty ? 'Règle de gestion' : title,
      category: BusinessRuleCategory.fromJson(raw['category']),
      priority: BusinessRulePriority.fromJson(raw['priority']),
      description: (raw['description'] as String?)?.trim() ?? '',
      targetObjectIds: _stringList(raw['targetObjectIds']),
      targetAttributes: _stringList(raw['targetAttributes']),
      trigger: (raw['trigger'] as String?)?.trim() ?? '',
      condition: (raw['condition'] as String?)?.trim() ?? '',
      effect: (raw['effect'] as String?)?.trim() ?? '',
      errorMessage: (raw['errorMessage'] as String?)?.trim() ?? '',
      examples: _stringList(raw['examples']),
      active: raw['active'] is bool ? raw['active'] as bool : true,
    );
    rule.validate();
    return rule;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessRuleSpec &&
          other.id == id &&
          other.code == code &&
          other.title == title &&
          other.category == category &&
          other.priority == priority &&
          other.description == description &&
          listEquals(other.targetObjectIds, targetObjectIds) &&
          listEquals(other.targetAttributes, targetAttributes) &&
          other.trigger == trigger &&
          other.condition == condition &&
          other.effect == effect &&
          other.errorMessage == errorMessage &&
          listEquals(other.examples, examples) &&
          other.active == active;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    title,
    category,
    priority,
    description,
    Object.hashAll(targetObjectIds),
    Object.hashAll(targetAttributes),
    trigger,
    condition,
    effect,
    errorMessage,
    Object.hashAll(examples),
    active,
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
