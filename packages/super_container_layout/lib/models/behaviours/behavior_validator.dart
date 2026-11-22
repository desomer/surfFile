/// Modélisation polymorphe des validateurs de comportements ([BehaviorValidator]).
///
/// Permet de conditionner l'exécution réelle d'une [BehaviorAction] lors du
/// déclenchement d'un [BehaviorEvent] :
/// - [ValueBehaviorValidator] : teste la valeur ou la validité du composant
///   courant (`self`), d'un autre composant (`component` via `targetComponentId`)
///   ou d'une liaison de repository (`binding` via [JsonTextBinding]) à l'aide
///   d'un [BehaviorValidatorOperator] (`isEmpty`, `isFill`, `equals`, `isTrue`,
///   `isValid`, etc.).
/// - [AllBehaviorValidator], [AnyBehaviorValidator], [NotBehaviorValidator] :
///   combinaisons logiques (`ET`, `OU`, `NON`).
/// - [BehaviorValidatorCatalog] : registre extensible de décodage JSON avec
///   raccourcis lisibles (`isEmpty`, `isFill`, `otherIsEmpty`, `otherIsFill`,
///   `otherEquals`, `bindingIsFill`, etc.).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:material_ui/material_ui.dart';

import '../json_text_binding.dart';

/// Source de la valeur inspectée par un [ValueBehaviorValidator].
enum BehaviorValueSource {
  /// Valeur ou état courant du composant qui a déclenché l'événement.
  self('Ce composant', Icons.crop_square_outlined),

  /// Valeur ou état d'un autre composant identifié par son ID technique.
  component('Autre composant', Icons.compare_arrows_outlined),

  /// Valeur lue directement sur un attribut d'un repository JSON.
  binding('Liaison repository', Icons.dataset_linked_outlined);

  const BehaviorValueSource(this.label, this.icon);

  /// Libellé français affiché dans l'éditeur.
  final String label;

  /// Icône représentative.
  final IconData icon;
}

/// Opérateur de comparaison ou de vérification appliqué par un [ValueBehaviorValidator].
enum BehaviorValidatorOperator {
  /// Vérifie que la valeur est absente ou vide (`null`, chaîne vide/espaces, collection vide).
  isEmpty('Est vide', 'isEmpty', requiresValue: false),

  /// Vérifie que la valeur est renseignée (`!isEmpty`).
  isFill('Est rempli', 'isFill', requiresValue: false),

  /// Vérifie que la valeur booléenne vaut `true`.
  isTrue('Est vrai', 'isTrue', requiresValue: false),

  /// Vérifie que la valeur booléenne vaut `false`.
  isFalse('Est faux', 'isFalse', requiresValue: false),

  /// Vérifie l'égalité avec [ValueBehaviorValidator.expectedValue].
  equals('Est égal à', 'equals', requiresValue: true),

  /// Vérifie la différence avec [ValueBehaviorValidator.expectedValue].
  notEquals('Est différent de', 'notEquals', requiresValue: true),

  /// Vérifie que la chaîne ou collection contient [ValueBehaviorValidator.expectedValue].
  contains('Contient', 'contains', requiresValue: true),

  /// Vérifie que la chaîne commence par [ValueBehaviorValidator.expectedValue].
  startsWith('Commence par', 'startsWith', requiresValue: true),

  /// Vérifie que la valeur numérique est strictement supérieure à [ValueBehaviorValidator.expectedValue].
  greaterThan('Est supérieur à', 'greaterThan', requiresValue: true),

  /// Vérifie que la valeur numérique est strictement inférieure à [ValueBehaviorValidator.expectedValue].
  lessThan('Est inférieur à', 'lessThan', requiresValue: true),

  /// Vérifie que la chaîne correspond à l'expression régulière [ValueBehaviorValidator.expectedValue].
  matchesRegex('Correspond au motif (RegExp)', 'matchesRegex', requiresValue: true),

  /// Vérifie que le composant satisfait ses règles de validation natives (requis, format, schéma).
  isValid('Est valide', 'isValid', requiresValue: false, requiresComponent: true),

  /// Vérifie que le composant est en erreur de validation native.
  isInvalid(
    'Est invalide',
    'isInvalid',
    requiresValue: false,
    requiresComponent: true,
  );

  const BehaviorValidatorOperator(
    this.label,
    this.shortName, {
    required this.requiresValue,
    this.requiresComponent = false,
  });

  /// Libellé français affiché dans l'éditeur.
  final String label;

  /// Nom court canonique utilisé dans la sérialisation JSON.
  final String shortName;

  /// Indique si une valeur attendue (`value`) est requise.
  final bool requiresValue;

  /// Indique si l'opérateur ne s'applique qu'à un composant (`self` ou `component`, pas `binding`).
  final bool requiresComponent;

  /// Nom de type JSON canonique pour une [source] donnée (ex. `isFill`, `otherIsEmpty`, `bindingEquals`).
  String typeNameFor(BehaviorValueSource source) {
    final pascal = shortName[0].toUpperCase() + shortName.substring(1);
    return switch (source) {
      BehaviorValueSource.self => shortName,
      BehaviorValueSource.component => 'other$pascal',
      BehaviorValueSource.binding => 'binding$pascal',
    };
  }
}

/// Contrat immuable de tout validateur conditionnant l'exécution d'un [ComponentBehavior].
@immutable
abstract class BehaviorValidator {
  const BehaviorValidator();

  /// Identifiant canonique du type JSON (ex. `'isFill'`, `'otherIsEmpty'`, `'all'`).
  String get type;

  /// Libellé court décrivant la règle.
  String get label;

  /// Résumé lisible en français de la condition complète.
  String get description;

  /// Identifiants d'autres composants référencés par ce validateur (et ses sous-validateurs).
  Set<String> get referencedComponentIds => const {};

  /// Liaisons JSON référencées par ce validateur (et ses sous-validateurs).
  List<JsonTextBinding> get referencedBindings => const [];

  /// Remplace récursivement les identifiants de composants présents dans [idMap].
  BehaviorValidator remapComponentIds(Map<String, String> idMap) => this;

  /// Vérifie les invariants du validateur ; lève [FormatException] si invalide.
  void validate();

  /// Sérialisation JSON complète.
  Map<String, Object?> toJson();

  /// Sérialisation JSON compacte (compatible export compact et `applyVibe`).
  Map<String, Object?> toCompactJson() => toJson();
}

/// Validateur évaluant la valeur ou la validité du composant courant, d'un autre
/// composant ou d'une liaison repository JSON.
@immutable
class ValueBehaviorValidator extends BehaviorValidator {
  /// Crée un validateur paramétré par [source] et [operator].
  const ValueBehaviorValidator({
    this.source = BehaviorValueSource.self,
    required this.operator,
    this.targetComponentId,
    this.binding,
    this.expectedValue,
  });

  /// Vérifie que la valeur du composant courant est vide.
  const ValueBehaviorValidator.isEmpty()
    : this(
        source: BehaviorValueSource.self,
        operator: BehaviorValidatorOperator.isEmpty,
      );

  /// Vérifie que la valeur du composant courant est remplie.
  const ValueBehaviorValidator.isFill()
    : this(
        source: BehaviorValueSource.self,
        operator: BehaviorValidatorOperator.isFill,
      );

  /// Vérifie que la valeur booléenne du composant courant vaut `true`.
  const ValueBehaviorValidator.isTrue()
    : this(
        source: BehaviorValueSource.self,
        operator: BehaviorValidatorOperator.isTrue,
      );

  /// Vérifie que la valeur booléenne du composant courant vaut `false`.
  const ValueBehaviorValidator.isFalse()
    : this(
        source: BehaviorValueSource.self,
        operator: BehaviorValidatorOperator.isFalse,
      );

  /// Vérifie que le composant courant est valide selon ses règles natives.
  const ValueBehaviorValidator.isValid()
    : this(
        source: BehaviorValueSource.self,
        operator: BehaviorValidatorOperator.isValid,
      );

  /// Vérifie que le composant courant est invalide selon ses règles natives.
  const ValueBehaviorValidator.isInvalid()
    : this(
        source: BehaviorValueSource.self,
        operator: BehaviorValidatorOperator.isInvalid,
      );

  /// Vérifie que la valeur du composant courant est égale à [value].
  const ValueBehaviorValidator.equals(Object? value)
    : this(
        source: BehaviorValueSource.self,
        operator: BehaviorValidatorOperator.equals,
        expectedValue: value,
      );

  /// Vérifie que la valeur du composant courant est différente de [value].
  const ValueBehaviorValidator.notEquals(Object? value)
    : this(
        source: BehaviorValueSource.self,
        operator: BehaviorValidatorOperator.notEquals,
        expectedValue: value,
      );

  /// Vérifie qu'un autre composant identifié par [targetComponentId] est vide.
  const ValueBehaviorValidator.otherIsEmpty(String targetComponentId)
    : this(
        source: BehaviorValueSource.component,
        operator: BehaviorValidatorOperator.isEmpty,
        targetComponentId: targetComponentId,
      );

  /// Vérifie qu'un autre composant identifié par [targetComponentId] est rempli.
  const ValueBehaviorValidator.otherIsFill(String targetComponentId)
    : this(
        source: BehaviorValueSource.component,
        operator: BehaviorValidatorOperator.isFill,
        targetComponentId: targetComponentId,
      );

  /// Vérifie qu'un autre composant vaut `true`.
  const ValueBehaviorValidator.otherIsTrue(String targetComponentId)
    : this(
        source: BehaviorValueSource.component,
        operator: BehaviorValidatorOperator.isTrue,
        targetComponentId: targetComponentId,
      );

  /// Vérifie qu'un autre composant vaut `false`.
  const ValueBehaviorValidator.otherIsFalse(String targetComponentId)
    : this(
        source: BehaviorValueSource.component,
        operator: BehaviorValidatorOperator.isFalse,
        targetComponentId: targetComponentId,
      );

  /// Vérifie qu'un autre composant est valide.
  const ValueBehaviorValidator.otherIsValid(String targetComponentId)
    : this(
        source: BehaviorValueSource.component,
        operator: BehaviorValidatorOperator.isValid,
        targetComponentId: targetComponentId,
      );

  /// Vérifie qu'un autre composant est invalide.
  const ValueBehaviorValidator.otherIsInvalid(String targetComponentId)
    : this(
        source: BehaviorValueSource.component,
        operator: BehaviorValidatorOperator.isInvalid,
        targetComponentId: targetComponentId,
      );

  /// Vérifie qu'un autre composant est égal à [value].
  const ValueBehaviorValidator.otherEquals(
    String targetComponentId,
    Object? value,
  ) : this(
        source: BehaviorValueSource.component,
        operator: BehaviorValidatorOperator.equals,
        targetComponentId: targetComponentId,
        expectedValue: value,
      );

  /// Vérifie qu'un autre composant est différent de [value].
  const ValueBehaviorValidator.otherNotEquals(
    String targetComponentId,
    Object? value,
  ) : this(
        source: BehaviorValueSource.component,
        operator: BehaviorValidatorOperator.notEquals,
        targetComponentId: targetComponentId,
        expectedValue: value,
      );

  /// Vérifie qu'une liaison repository est vide.
  const ValueBehaviorValidator.bindingIsEmpty(JsonTextBinding binding)
    : this(
        source: BehaviorValueSource.binding,
        operator: BehaviorValidatorOperator.isEmpty,
        binding: binding,
      );

  /// Vérifie qu'une liaison repository est remplie.
  const ValueBehaviorValidator.bindingIsFill(JsonTextBinding binding)
    : this(
        source: BehaviorValueSource.binding,
        operator: BehaviorValidatorOperator.isFill,
        binding: binding,
      );

  /// Vérifie qu'une liaison repository est égale à [value].
  const ValueBehaviorValidator.bindingEquals(
    JsonTextBinding binding,
    Object? value,
  ) : this(
        source: BehaviorValueSource.binding,
        operator: BehaviorValidatorOperator.equals,
        binding: binding,
        expectedValue: value,
      );

  /// Origine de la valeur inspectée.
  final BehaviorValueSource source;

  /// Opérateur de comparaison ou d'état appliqué.
  final BehaviorValidatorOperator operator;

  /// Identifiant technique du composant cible lorsque [source] vaut [BehaviorValueSource.component].
  final String? targetComponentId;

  /// Liaison repository lorsque [source] vaut [BehaviorValueSource.binding].
  final JsonTextBinding? binding;

  /// Valeur attendue pour les opérateurs binaires (`equals`, `contains`, `greaterThan`, etc.).
  final Object? expectedValue;

  @override
  String get type => operator.typeNameFor(source);

  @override
  String get label => switch (source) {
    BehaviorValueSource.self => operator.label,
    BehaviorValueSource.component => 'Autre composant : ${operator.label.toLowerCase()}',
    BehaviorValueSource.binding => 'Liaison : ${operator.label.toLowerCase()}',
  };

  @override
  String get description {
    final subject = switch (source) {
      BehaviorValueSource.self => 'Ce composant',
      BehaviorValueSource.component =>
        '« ${targetComponentId?.trim().isNotEmpty == true ? targetComponentId!.trim() : '?'} »',
      BehaviorValueSource.binding =>
        '« ${binding?.path ?? '?'} »',
    };
    final opText = operator.label.toLowerCase();
    if (!operator.requiresValue) {
      return '$subject $opText';
    }
    return '$subject $opText ${_formatExpectedPreview(expectedValue)}';
  }

  @override
  Set<String> get referencedComponentIds {
    if (source != BehaviorValueSource.component) return const {};
    final id = targetComponentId?.trim();
    return id == null || id.isEmpty ? const {} : {id};
  }

  @override
  List<JsonTextBinding> get referencedBindings =>
      source == BehaviorValueSource.binding && binding != null
      ? [binding!]
      : const [];

  @override
  ValueBehaviorValidator remapComponentIds(Map<String, String> idMap) {
    if (source != BehaviorValueSource.component) return this;
    final current = targetComponentId?.trim();
    if (current == null || !idMap.containsKey(current)) return this;
    return copyWith(targetComponentId: idMap[current]);
  }

  /// Retourne une copie modifiée de ce validateur.
  ValueBehaviorValidator copyWith({
    BehaviorValueSource? source,
    BehaviorValidatorOperator? operator,
    String? targetComponentId,
    bool clearTargetComponentId = false,
    JsonTextBinding? binding,
    bool clearBinding = false,
    Object? expectedValue = _keepExpectedValue,
  }) => ValueBehaviorValidator(
    source: source ?? this.source,
    operator: operator ?? this.operator,
    targetComponentId: clearTargetComponentId
        ? null
        : (targetComponentId ?? this.targetComponentId),
    binding: clearBinding ? null : (binding ?? this.binding),
    expectedValue: identical(expectedValue, _keepExpectedValue)
        ? this.expectedValue
        : expectedValue,
  );

  @override
  void validate() {
    switch (source) {
      case BehaviorValueSource.self:
        if (targetComponentId != null && targetComponentId!.trim().isNotEmpty) {
          throw const FormatException(
            'targetComponentId n’est pas autorisé pour un validateur sur le composant courant.',
          );
        }
        if (binding != null) {
          throw const FormatException(
            'binding n’est pas autorisé pour un validateur sur le composant courant.',
          );
        }
      case BehaviorValueSource.component:
        if (targetComponentId == null || targetComponentId!.trim().isEmpty) {
          throw const FormatException(
            'targetComponentId est requis pour un validateur sur un autre composant.',
          );
        }
        if (binding != null) {
          throw const FormatException(
            'binding n’est pas autorisé pour un validateur sur un autre composant.',
          );
        }
      case BehaviorValueSource.binding:
        if (binding == null) {
          throw const FormatException(
            'binding est requis pour un validateur de liaison repository.',
          );
        }
        binding!.validate();
        if (operator.requiresComponent) {
          throw FormatException(
            'L’opérateur "${operator.shortName}" nécessite un composant (non applicable sur une liaison brute).',
          );
        }
        if (targetComponentId != null && targetComponentId!.trim().isNotEmpty) {
          throw const FormatException(
            'targetComponentId n’est pas autorisé pour un validateur de liaison repository.',
          );
        }
    }

    if (operator.requiresValue) {
      if (expectedValue == null &&
          operator != BehaviorValidatorOperator.equals &&
          operator != BehaviorValidatorOperator.notEquals) {
        throw FormatException(
          'Une valeur attendue ("value") est requise pour "${operator.shortName}".',
        );
      }
      if (operator == BehaviorValidatorOperator.matchesRegex) {
        if (expectedValue is! String || (expectedValue as String).isEmpty) {
          throw const FormatException(
            'L’opérateur "matchesRegex" attend une expression régulière non vide.',
          );
        }
        try {
          RegExp(expectedValue as String);
        } on FormatException catch (error) {
          throw FormatException(
            'Expression régulière invalide dans le validateur : ${error.message}',
          );
        }
      }
      if (operator == BehaviorValidatorOperator.greaterThan ||
          operator == BehaviorValidatorOperator.lessThan) {
        final numeric = _tryParseNum(expectedValue);
        if (numeric == null || !numeric.isFinite) {
          throw FormatException(
            'L’opérateur "${operator.shortName}" attend une valeur numérique finie.',
          );
        }
      }
      if (operator == BehaviorValidatorOperator.startsWith &&
          expectedValue is! String) {
        throw const FormatException(
          'L’opérateur "startsWith" attend une chaîne de caractères.',
        );
      }
      _ensureJsonValue(expectedValue);
    }
  }

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      if (source == BehaviorValueSource.component)
        'targetComponentId': targetComponentId!.trim(),
      if (source == BehaviorValueSource.binding) 'binding': binding!.toJson(),
      if (operator.requiresValue) 'value': _cloneJson(expectedValue),
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'type': type,
      if (source == BehaviorValueSource.component)
        'targetComponentId': targetComponentId!.trim(),
      if (source == BehaviorValueSource.binding)
        'binding': binding!.toCompactJson(),
      if (operator.requiresValue) 'value': _cloneJson(expectedValue),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValueBehaviorValidator &&
          other.source == source &&
          other.operator == operator &&
          other.targetComponentId?.trim() == targetComponentId?.trim() &&
          other.binding == binding &&
          _jsonEquals(other.expectedValue, expectedValue);

  @override
  int get hashCode => Object.hash(
    source,
    operator,
    targetComponentId?.trim(),
    binding,
    _deepHash(expectedValue),
  );
}

/// Validateur composite vérifiant que **tous** les sous-validateurs sont satisfaits (ET logique).
@immutable
class AllBehaviorValidator extends BehaviorValidator {
  /// Crée un validateur composite `all`.
  AllBehaviorValidator({required List<BehaviorValidator> validators})
    : validators = List<BehaviorValidator>.unmodifiable(validators);

  /// Liste ordonnée des sous-validateurs requis.
  final List<BehaviorValidator> validators;

  @override
  String get type => 'all';

  @override
  String get label => 'Toutes les conditions (ET)';

  @override
  String get description =>
      validators.map((v) => v.description).join(' ET ');

  @override
  Set<String> get referencedComponentIds => {
    for (final v in validators) ...v.referencedComponentIds,
  };

  @override
  List<JsonTextBinding> get referencedBindings => [
    for (final v in validators) ...v.referencedBindings,
  ];

  @override
  AllBehaviorValidator remapComponentIds(Map<String, String> idMap) =>
      AllBehaviorValidator(
        validators: [
          for (final v in validators) v.remapComponentIds(idMap),
        ],
      );

  @override
  void validate() {
    if (validators.isEmpty) {
      throw const FormatException(
        'Le validateur "all" doit contenir au moins une condition.',
      );
    }
    for (final child in validators) {
      child.validate();
    }
  }

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'validators': [for (final v in validators) v.toJson()],
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'type': type,
      'validators': [for (final v in validators) v.toCompactJson()],
    };
  }

  /// Décode un [AllBehaviorValidator] depuis JSON.
  factory AllBehaviorValidator.fromJson(Map<String, dynamic> json) {
    final raw = json['validators'];
    if (raw is! List) {
      throw const FormatException(
        'Le validateur "all" attend une liste "validators".',
      );
    }
    final list = <BehaviorValidator>[];
    for (final item in raw) {
      if (item is! Map) {
        throw const FormatException(
          'Chaque entrée de "validators" doit être un objet JSON.',
        );
      }
      list.add(BehaviorValidatorCatalog.decode(Map<String, dynamic>.from(item)));
    }
    return AllBehaviorValidator(validators: list)..validate();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AllBehaviorValidator && listEquals(other.validators, validators);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(validators));
}

/// Validateur composite vérifiant qu'**au moins un** sous-validateur est satisfait (OU logique).
@immutable
class AnyBehaviorValidator extends BehaviorValidator {
  /// Crée un validateur composite `any`.
  AnyBehaviorValidator({required List<BehaviorValidator> validators})
    : validators = List<BehaviorValidator>.unmodifiable(validators);

  /// Liste ordonnée des sous-validateurs alternatifs.
  final List<BehaviorValidator> validators;

  @override
  String get type => 'any';

  @override
  String get label => 'Au moins une condition (OU)';

  @override
  String get description =>
      validators.map((v) => v.description).join(' OU ');

  @override
  Set<String> get referencedComponentIds => {
    for (final v in validators) ...v.referencedComponentIds,
  };

  @override
  List<JsonTextBinding> get referencedBindings => [
    for (final v in validators) ...v.referencedBindings,
  ];

  @override
  AnyBehaviorValidator remapComponentIds(Map<String, String> idMap) =>
      AnyBehaviorValidator(
        validators: [
          for (final v in validators) v.remapComponentIds(idMap),
        ],
      );

  @override
  void validate() {
    if (validators.isEmpty) {
      throw const FormatException(
        'Le validateur "any" doit contenir au moins une condition.',
      );
    }
    for (final child in validators) {
      child.validate();
    }
  }

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'validators': [for (final v in validators) v.toJson()],
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'type': type,
      'validators': [for (final v in validators) v.toCompactJson()],
    };
  }

  /// Décode un [AnyBehaviorValidator] depuis JSON.
  factory AnyBehaviorValidator.fromJson(Map<String, dynamic> json) {
    final raw = json['validators'];
    if (raw is! List) {
      throw const FormatException(
        'Le validateur "any" attend une liste "validators".',
      );
    }
    final list = <BehaviorValidator>[];
    for (final item in raw) {
      if (item is! Map) {
        throw const FormatException(
          'Chaque entrée de "validators" doit être un objet JSON.',
        );
      }
      list.add(BehaviorValidatorCatalog.decode(Map<String, dynamic>.from(item)));
    }
    return AnyBehaviorValidator(validators: list)..validate();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnyBehaviorValidator && listEquals(other.validators, validators);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(validators));
}

/// Validateur inverseur (NON logique) autour d'un sous-validateur.
@immutable
class NotBehaviorValidator extends BehaviorValidator {
  /// Crée une négation autour de [validator].
  const NotBehaviorValidator({required this.validator});

  /// Sous-validateur dont le résultat booléen est inversé.
  final BehaviorValidator validator;

  @override
  String get type => 'not';

  @override
  String get label => 'Inverser la condition (NON)';

  @override
  String get description => 'NON (${validator.description})';

  @override
  Set<String> get referencedComponentIds => validator.referencedComponentIds;

  @override
  List<JsonTextBinding> get referencedBindings => validator.referencedBindings;

  @override
  NotBehaviorValidator remapComponentIds(Map<String, String> idMap) =>
      NotBehaviorValidator(validator: validator.remapComponentIds(idMap));

  @override
  void validate() => validator.validate();

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'validator': validator.toJson(),
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'type': type,
      'validator': validator.toCompactJson(),
    };
  }

  /// Décode un [NotBehaviorValidator] depuis JSON.
  factory NotBehaviorValidator.fromJson(Map<String, dynamic> json) {
    final inner = json['validator'];
    if (inner is! Map) {
      throw const FormatException(
        'Le validateur "not" attend un objet "validator".',
      );
    }
    return NotBehaviorValidator(
      validator: BehaviorValidatorCatalog.decode(
        Map<String, dynamic>.from(inner),
      ),
    )..validate();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotBehaviorValidator && other.validator == validator;

  @override
  int get hashCode => Object.hash(type, validator);
}

/// Registre extensible pour décoder les validateurs polymorphes depuis JSON.
abstract final class BehaviorValidatorCatalog {
  static final Map<String, BehaviorValidator Function(Map<String, dynamic>)>
  _customCodecs = {};

  /// Table pré-construite des types courts canoniques et alias usuels.
  static final Map<
    String,
    ({BehaviorValueSource source, BehaviorValidatorOperator operator})
  >
  _shorthandTypes = _buildShorthandTypes();

  static Map<
    String,
    ({BehaviorValueSource source, BehaviorValidatorOperator operator})
  >
  _buildShorthandTypes() {
    final map =
        <
          String,
          ({BehaviorValueSource source, BehaviorValidatorOperator operator})
        >{};
    for (final source in BehaviorValueSource.values) {
      for (final op in BehaviorValidatorOperator.values) {
        if (source == BehaviorValueSource.binding && op.requiresComponent) {
          continue;
        }
        map[op.typeNameFor(source)] = (source: source, operator: op);
      }
    }
    // Alias usuels tolérés en entrée JSON (humains et IA).
    map['isFilled'] = (
      source: BehaviorValueSource.self,
      operator: BehaviorValidatorOperator.isFill,
    );
    map['isNotEmpty'] = (
      source: BehaviorValueSource.self,
      operator: BehaviorValidatorOperator.isFill,
    );
    map['otherIsFilled'] = (
      source: BehaviorValueSource.component,
      operator: BehaviorValidatorOperator.isFill,
    );
    map['otherIsNotEmpty'] = (
      source: BehaviorValueSource.component,
      operator: BehaviorValidatorOperator.isFill,
    );
    map['bindingIsFilled'] = (
      source: BehaviorValueSource.binding,
      operator: BehaviorValidatorOperator.isFill,
    );
    map['bindingIsNotEmpty'] = (
      source: BehaviorValueSource.binding,
      operator: BehaviorValidatorOperator.isFill,
    );
    return Map.unmodifiable(map);
  }

  /// Enregistre un décodeur de validateur personnalisé.
  static void register(
    String type,
    BehaviorValidator Function(Map<String, dynamic> json) fromJson,
  ) {
    _customCodecs[type.trim()] = fromJson;
  }

  /// Décode et valide un [BehaviorValidator] depuis un objet JSON.
  static BehaviorValidator decode(Map<String, dynamic> json) {
    final rawType = (json['type'] as String?)?.trim() ?? '';
    if (rawType.isEmpty) {
      throw const FormatException('Type de validateur de comportement manquant.');
    }
    final custom = _customCodecs[rawType];
    if (custom != null) {
      return custom(json)..validate();
    }
    switch (rawType) {
      case 'all':
        return AllBehaviorValidator.fromJson(json);
      case 'any':
        return AnyBehaviorValidator.fromJson(json);
      case 'not':
        return NotBehaviorValidator.fromJson(json);
      case 'value':
        return _decodeGenericValue(json);
    }
    final shorthand = _shorthandTypes[rawType];
    if (shorthand != null) {
      return _decodeValue(
        json,
        source: shorthand.source,
        operator: shorthand.operator,
      );
    }
    throw FormatException('Type de validateur de comportement inconnu : "$rawType"');
  }

  static ValueBehaviorValidator _decodeGenericValue(Map<String, dynamic> json) {
    final sourceName = (json['source'] as String?)?.trim() ?? 'self';
    final source = BehaviorValueSource.values
        .where((s) => s.name == sourceName || (sourceName == 'other' && s == BehaviorValueSource.component))
        .firstOrNull;
    if (source == null) {
      throw FormatException('Source de validateur inconnue : "$sourceName"');
    }
    final rawOp = (json['operator'] as String?)?.trim() ?? '';
    final normalizedOp = switch (rawOp) {
      'isFilled' || 'isNotEmpty' => 'isFill',
      _ => rawOp,
    };
    final operator = BehaviorValidatorOperator.values
        .where((op) => op.shortName == normalizedOp || op.name == normalizedOp)
        .firstOrNull;
    if (operator == null) {
      throw FormatException('Opérateur de validateur inconnu : "$rawOp"');
    }
    return _decodeValue(json, source: source, operator: operator);
  }

  static ValueBehaviorValidator _decodeValue(
    Map<String, dynamic> json, {
    required BehaviorValueSource source,
    required BehaviorValidatorOperator operator,
  }) {
    final rawTarget = json['targetComponentId'] ?? json['targetId'];
    if (rawTarget != null && rawTarget is! String) {
      throw const FormatException(
        'targetComponentId doit être une chaîne de caractères.',
      );
    }
    final rawBinding = json['binding'];
    final binding = rawBinding == null
        ? null
        : JsonTextBinding.fromJson(rawBinding);
    final expected = json.containsKey('value')
        ? _cloneJson(json['value'])
        : json.containsKey('expectedValue')
        ? _cloneJson(json['expectedValue'])
        : null;
    final validator = ValueBehaviorValidator(
      source: source,
      operator: operator,
      targetComponentId: rawTarget as String?,
      binding: binding,
      expectedValue: expected,
    );
    validator.validate();
    return validator;
  }
}

const Object _keepExpectedValue = Object();

num? _tryParseNum(Object? value) {
  if (value is num) return value;
  if (value is String) {
    final trimmed = value.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    return num.tryParse(trimmed);
  }
  return null;
}

void _ensureJsonValue(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw const FormatException('Les nombres non finis sont interdits.');
    }
    return;
  }
  if (value is List) {
    for (final item in value) {
      _ensureJsonValue(item);
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Les clés JSON doivent être des chaînes.');
      }
      _ensureJsonValue(entry.value);
    }
    return;
  }
  throw FormatException('Valeur de validateur non sérialisable en JSON : $value');
}

Object? _cloneJson(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_cloneJson));
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): _cloneJson(entry.value),
    });
  }
  return value;
}

bool _jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map((e) => Object.hash(e.key, _deepHash(e.value))),
    );
  }
  return value.hashCode;
}

String _formatExpectedPreview(Object? value) {
  if (value == null) return 'null';
  if (value is String) return '« $value »';
  if (value is bool || value is num) return '$value';
  try {
    return jsonEncode(value);
  } catch (_) {
    return '$value';
  }
}
