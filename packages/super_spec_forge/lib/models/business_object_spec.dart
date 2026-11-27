/// Modèles immuables des objets métiers ([BusinessObjectSpec], [BusinessAttribute], [BusinessRelation], cycles de vie).
library;

import 'package:flutter/foundation.dart';

import 'json_schema_constraints.dart';

/// Type de donnée d'un attribut d'objet métier.
enum BusinessAttributeType {
  string('string', 'Texte'),
  integer('int', 'Entier'),
  number('number', 'Décimal'),
  boolean('bool', 'Booléen'),
  date('date', 'Date'),
  datetime('datetime', 'Date & heure'),
  uuid('uuid', 'UUID'),
  email('email', 'Email'),
  url('url', 'URL'),
  enumeration('enum', 'Énumération'),
  reference('ref', 'Référence'),
  valueObject('vo', 'Value Object'),
  object('object', 'Sous-objet'),
  json('json', 'JSON libre');

  /// Construit un type d'attribut métier.
  const BusinessAttributeType(this.dslKeyword, this.label);

  /// Mot-clé compatible avec le DSL YAML « JSON Schemas Light ».
  final String dslKeyword;

  /// Libellé affiché dans l'atelier.
  final String label;

  /// Résout un type depuis une chaîne JSON ou un alias courant.
  static BusinessAttributeType fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      switch (norm) {
        case 'string':
        case 'text':
        case 'str':
          return BusinessAttributeType.string;
        case 'int':
        case 'integer':
          return BusinessAttributeType.integer;
        case 'number':
        case 'float':
        case 'double':
        case 'decimal':
          return BusinessAttributeType.number;
        case 'bool':
        case 'boolean':
          return BusinessAttributeType.boolean;
        case 'date':
          return BusinessAttributeType.date;
        case 'datetime':
        case 'date-time':
        case 'timestamp':
          return BusinessAttributeType.datetime;
        case 'uuid':
          return BusinessAttributeType.uuid;
        case 'email':
          return BusinessAttributeType.email;
        case 'url':
        case 'uri':
          return BusinessAttributeType.url;
        case 'enum':
        case 'enumeration':
          return BusinessAttributeType.enumeration;
        case 'ref':
        case 'reference':
          return BusinessAttributeType.reference;
        case 'vo':
        case 'valueobject':
        case 'value_object':
        case 'value-object':
          return BusinessAttributeType.valueObject;
        case 'object':
        case 'subobject':
        case 'sub_object':
        case 'sous-objet':
        case 'struct':
          return BusinessAttributeType.object;
        case 'json':
        case 'any':
          return BusinessAttributeType.json;
      }
    }
    return BusinessAttributeType.string;
  }
}

/// Cardinalité d'une relation entre deux objets métiers.
enum BusinessRelationCardinality {
  oneToOne('1:1', 'Un à un'),
  oneToMany('1:N', 'Un à plusieurs'),
  manyToMany('N:M', 'Plusieurs à plusieurs');

  /// Construit une cardinalité.
  const BusinessRelationCardinality(this.symbol, this.label);

  /// Notation courte (`1:1`, `1:N`, `N:M`).
  final String symbol;

  /// Libellé français.
  final String label;

  /// Résout une cardinalité depuis JSON.
  static BusinessRelationCardinality fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in BusinessRelationCardinality.values) {
        if (value.name.toLowerCase() == norm ||
            value.symbol.toLowerCase() == norm) {
          return value;
        }
      }
    }
    return BusinessRelationCardinality.oneToMany;
  }
}

/// Attribut typé d'un [BusinessObjectSpec] (pouvant contenir des sous-attributs imbriqués).
@immutable
class BusinessAttribute {
  /// Construit un attribut immuable.
  BusinessAttribute({
    required this.id,
    required this.name,
    this.type = BusinessAttributeType.string,
    this.required = false,
    this.nullable = false,
    this.unique = false,
    this.isArray = false,
    this.estimatedMaxRows,
    this.defaultValue,
    List<String> enumValues = const <String>[],
    this.referenceObjectId = '',
    this.valueObjectId = '',
    this.description = '',
    this.constraints = '',
    JsonSchemaConstraints? schemaConstraints,
    List<BusinessAttribute> children = const <BusinessAttribute>[],
  }) : enumValues = List<String>.unmodifiable(enumValues),
       schemaConstraints = schemaConstraints ?? JsonSchemaConstraints.empty,
       children = List<BusinessAttribute>.unmodifiable(children);

  /// Identifiant technique stable.
  final String id;

  /// Expression régulière stricte des identifiants DSL compatibles `Yaml2JsonSchemasParser` / `JsonAttributePath`.
  static final RegExp validDslIdentifierPattern = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_-]*$',
  );

  /// Indique si [candidate] est un identifiant ASCII valide pour le DSL YAML et `JsonAttributePath`.
  static bool isValidDslIdentifier(String candidate) =>
      validDslIdentifierPattern.hasMatch(candidate);

  /// Transcrit les diacritiques latins/français courants en ASCII puis normalise en identifiant DSL valide.
  static String normalizeDslIdentifier(
    String input, {
    String fallback = 'champ',
  }) => _sanitizeIdentifier(input, fallback: fallback);

  /// Convertit un libellé lisible en `PascalCase` ASCII valide (ex. `Relevé Kilométrique` → `ReleveKilometrique`).
  static String toPascalCaseDslIdentifier(String input) =>
      _toPascalCase(input);

  /// Nom technique de l'attribut (camelCase ou snake_case ASCII, sans accent, espace, `.[]?` ni `@`).
  final String name;

  /// Type métier de l'attribut.
  final BusinessAttributeType type;

  /// Indique si le champ est obligatoire.
  final bool required;

  /// Indique si le champ accepte `null`.
  final bool nullable;

  /// Indique si la valeur doit être unique.
  final bool unique;

  /// Indique si l'attribut est une collection.
  final bool isArray;

  /// Nombre maximal fonctionnel de lignes attendu lorsque [isArray] vaut `true` (plafond 200).
  final int? estimatedMaxRows;

  /// Valeur par défaut éventuelle.
  final String? defaultValue;

  /// Valeurs possibles si [type] vaut [BusinessAttributeType.enumeration].
  final List<String> enumValues;

  /// Identifiant de l'objet cible si [type] vaut [BusinessAttributeType.reference].
  final String referenceObjectId;

  /// Identifiant (ou nom technique) du Value Object cible si [type] vaut
  /// [BusinessAttributeType.valueObject].
  final String valueObjectId;

  /// Description fonctionnelle.
  final String description;

  /// Contraintes complémentaires en texte libre (ex. `min >= 0`, `max 120 caractères`).
  final String constraints;

  /// Contraintes structurées complètes du standard JSON Schema Draft 7 / 2020-12.
  final JsonSchemaConstraints schemaConstraints;

  /// Sous-attributs imbriqués lorsque [type] vaut [BusinessAttributeType.object].
  final List<BusinessAttribute> children;

  /// Nombre total récursif d'attributs (cet attribut + tous ses sous-attributs).
  int get totalAttributeCount =>
      1 + children.fold<int>(0, (sum, child) => sum + child.totalAttributeCount);

  /// Vérifie les invariants de l'attribut, ses contraintes JSON Schema et ses sous-attributs.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BusinessAttribute.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'BusinessAttribute.name ne peut pas être vide.',
      );
    }
    if (!validDslIdentifierPattern.hasMatch(name)) {
      throw FormatException(
        'Nom d\'attribut métier incompatible avec JsonAttributePath : $name '
        '(utilisez uniquement des caractères ASCII [A-Za-z_][A-Za-z0-9_-]*, sans accent ni espace).',
      );
    }
    if (estimatedMaxRows != null && estimatedMaxRows! < 0) {
      throw FormatException(
        'estimatedMaxRows doit être positif sur « $name ».',
      );
    }
    schemaConstraints.validate();
    final childNames = <String>{};
    for (final child in children) {
      child.validate();
      if (!childNames.add(child.name)) {
        throw FormatException(
          'Sous-attribut dupliqué « ${child.name} » dans « $name ».',
        );
      }
    }
  }

  /// Copie modifiée.
  BusinessAttribute copyWith({
    String? id,
    String? name,
    BusinessAttributeType? type,
    bool? required,
    bool? nullable,
    bool? unique,
    bool? isArray,
    int? estimatedMaxRows,
    bool clearEstimatedMaxRows = false,
    String? defaultValue,
    bool clearDefaultValue = false,
    List<String>? enumValues,
    String? referenceObjectId,
    String? valueObjectId,
    String? description,
    String? constraints,
    JsonSchemaConstraints? schemaConstraints,
    List<BusinessAttribute>? children,
  }) => BusinessAttribute(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    required: required ?? this.required,
    nullable: nullable ?? this.nullable,
    unique: unique ?? this.unique,
    isArray: isArray ?? this.isArray,
    estimatedMaxRows: clearEstimatedMaxRows
        ? null
        : (estimatedMaxRows ?? this.estimatedMaxRows),
    defaultValue: clearDefaultValue
        ? null
        : (defaultValue ?? this.defaultValue),
    enumValues: enumValues ?? this.enumValues,
    referenceObjectId: referenceObjectId ?? this.referenceObjectId,
    valueObjectId: valueObjectId ?? this.valueObjectId,
    description: description ?? this.description,
    constraints: constraints ?? this.constraints,
    schemaConstraints: schemaConstraints ?? this.schemaConstraints,
    children: children ?? this.children,
  );

  /// Sérialise l'attribut en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'type': type.name,
    'required': required,
    'nullable': nullable,
    'unique': unique,
    'isArray': isArray,
    if (estimatedMaxRows != null) 'estimatedMaxRows': estimatedMaxRows,
    if (defaultValue != null) 'defaultValue': defaultValue,
    'enumValues': enumValues,
    'referenceObjectId': referenceObjectId,
    if (valueObjectId.isNotEmpty) 'valueObjectId': valueObjectId,
    'description': description,
    'constraints': constraints,
    if (schemaConstraints.isNotEmpty)
      'schemaConstraints': schemaConstraints.toJson(),
    if (children.isNotEmpty)
      'children': [for (final c in children) c.toJson()],
  };

  /// Désérialise un attribut depuis JSON.
  factory BusinessAttribute.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'BusinessAttribute doit être un objet JSON.',
      );
    }
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isEmpty ? 'attribut' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawMaxRows = raw['estimatedMaxRows'];
    final int? parsedMaxRows = switch (rawMaxRows) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v.trim()),
      _ => null,
    };
    final rawChildren = raw['children'];
    final parsedChildren = rawChildren is List
        ? [for (final item in rawChildren) BusinessAttribute.fromJson(item)]
        : const <BusinessAttribute>[];
    final resolvedType = BusinessAttributeType.fromJson(raw['type']);
    final effectiveType =
        (parsedChildren.isNotEmpty && resolvedType == BusinessAttributeType.json)
            ? BusinessAttributeType.object
            : resolvedType;

    final rawSchemaConstraints = raw['schemaConstraints'];
    final parsedSchemaConstraints = rawSchemaConstraints != null
        ? JsonSchemaConstraints.fromJson(rawSchemaConstraints)
        : JsonSchemaConstraints.fromJson(raw);

    final attr = BusinessAttribute(
      id: rawId.isEmpty ? 'attr_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      type: effectiveType,
      required: raw['required'] == true,
      nullable: raw['nullable'] == true,
      unique: raw['unique'] == true,
      isArray: raw['isArray'] == true,
      estimatedMaxRows: parsedMaxRows,
      defaultValue: raw['defaultValue']?.toString(),
      enumValues: _stringList(raw['enumValues']),
      referenceObjectId: (raw['referenceObjectId'] as String?)?.trim() ?? '',
      valueObjectId: (raw['valueObjectId'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
      constraints: (raw['constraints'] as String?)?.trim() ?? '',
      schemaConstraints: parsedSchemaConstraints,
      children: parsedChildren,
    );
    attr.validate();
    return attr;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessAttribute &&
          other.id == id &&
          other.name == name &&
          other.type == type &&
          other.required == required &&
          other.nullable == nullable &&
          other.unique == unique &&
          other.isArray == isArray &&
          other.estimatedMaxRows == estimatedMaxRows &&
          other.defaultValue == defaultValue &&
          listEquals(other.enumValues, enumValues) &&
          other.referenceObjectId == referenceObjectId &&
          other.valueObjectId == valueObjectId &&
          other.description == description &&
          other.constraints == constraints &&
          other.schemaConstraints == schemaConstraints &&
          listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    required,
    nullable,
    unique,
    isArray,
    estimatedMaxRows,
    defaultValue,
    Object.hashAll(enumValues),
    referenceObjectId,
    valueObjectId,
    description,
    constraints,
    schemaConstraints,
    Object.hashAll(children),
  );
}

/// Relation entre cet objet métier et un [targetObjectId].
@immutable
class BusinessRelation {
  /// Construit une relation immuable.
  const BusinessRelation({
    required this.id,
    required this.name,
    required this.targetObjectId,
    this.cardinality = BusinessRelationCardinality.oneToMany,
    this.description = '',
    this.inverseName = '',
    this.required = false,
  });

  /// Identifiant unique de la relation.
  final String id;

  /// Nom du champ relationnel (ex. `lignes`, `client`).
  final String name;

  /// Identifiant de l'objet métier cible.
  final String targetObjectId;

  /// Cardinalité (`1:1`, `1:N`, `N:M`).
  final BusinessRelationCardinality cardinality;

  /// Description métier de la relation.
  final String description;

  /// Nom de la relation inverse sur la cible (optionnel).
  final String inverseName;

  /// Indique si la relation est obligatoire.
  final bool required;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BusinessRelation.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'BusinessRelation.name ne peut pas être vide.',
      );
    }
    if (!BusinessAttribute.isValidDslIdentifier(name)) {
      throw FormatException(
        'Nom de relation métier incompatible avec le DSL YAML : $name '
        '(utilisez uniquement des caractères ASCII [A-Za-z_][A-Za-z0-9_-]*, sans accent ni espace).',
      );
    }
    if (targetObjectId.trim().isEmpty) {
      throw const FormatException(
        'BusinessRelation.targetObjectId ne peut pas être vide.',
      );
    }
  }

  /// Copie modifiée.
  BusinessRelation copyWith({
    String? id,
    String? name,
    String? targetObjectId,
    BusinessRelationCardinality? cardinality,
    String? description,
    String? inverseName,
    bool? required,
  }) => BusinessRelation(
    id: id ?? this.id,
    name: name ?? this.name,
    targetObjectId: targetObjectId ?? this.targetObjectId,
    cardinality: cardinality ?? this.cardinality,
    description: description ?? this.description,
    inverseName: inverseName ?? this.inverseName,
    required: required ?? this.required,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'targetObjectId': targetObjectId,
    'cardinality': cardinality.name,
    'description': description,
    'inverseName': inverseName,
    'required': required,
  };

  /// Désérialise depuis JSON.
  factory BusinessRelation.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'BusinessRelation doit être un objet JSON.',
      );
    }
    final name = _sanitizeIdentifier((raw['name'] as String?)?.trim() ?? 'rel');
    final target = (raw['targetObjectId'] as String?)?.trim() ?? 'inconnu';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final rel = BusinessRelation(
      id: id.isEmpty ? 'rel_${name.hashCode.abs()}' : id,
      name: name,
      targetObjectId: target.isEmpty ? 'inconnu' : target,
      cardinality: BusinessRelationCardinality.fromJson(raw['cardinality']),
      description: (raw['description'] as String?)?.trim() ?? '',
      inverseName: (raw['inverseName'] as String?)?.trim() ?? '',
      required: raw['required'] == true,
    );
    rel.validate();
    return rel;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessRelation &&
          other.id == id &&
          other.name == name &&
          other.targetObjectId == targetObjectId &&
          other.cardinality == cardinality &&
          other.description == description &&
          other.inverseName == inverseName &&
          other.required == required;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    targetObjectId,
    cardinality,
    description,
    inverseName,
    required,
  );
}

/// État dans le cycle de vie d'un objet métier.
@immutable
class LifecycleState {
  /// Construit un état immuable de cycle de vie.
  const LifecycleState({
    required this.name,
    this.label = '',
    this.isInitial = false,
    this.isTerminal = false,
    this.description = '',
  });

  /// Code technique de l'état (ex. `brouillon`, `validee`).
  final String name;

  /// Libellé lisible affiché (ex. `Brouillon`).
  final String label;

  /// Vrai s'il s'agit de l'état initial à la création.
  final bool isInitial;

  /// Vrai s'il s'agit d'un état final.
  final bool isTerminal;

  /// Description métier de l'état.
  final String description;

  /// Libellé effectif (retombe sur [name] si [label] est vide).
  String get effectiveLabel => label.trim().isNotEmpty ? label : name;

  /// Copie modifiée.
  LifecycleState copyWith({
    String? name,
    String? label,
    bool? isInitial,
    bool? isTerminal,
    String? description,
  }) => LifecycleState(
    name: name ?? this.name,
    label: label ?? this.label,
    isInitial: isInitial ?? this.isInitial,
    isTerminal: isTerminal ?? this.isTerminal,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'label': label,
    'isInitial': isInitial,
    'isTerminal': isTerminal,
    'description': description,
  };

  /// Désérialise depuis JSON.
  factory LifecycleState.fromJson(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      return LifecycleState(name: trimmed, label: trimmed);
    }
    if (raw is! Map) {
      throw const FormatException('LifecycleState doit être un objet JSON.');
    }
    final name = (raw['name'] as String?)?.trim() ?? 'etat';
    return LifecycleState(
      name: name.isEmpty ? 'etat' : name,
      label: (raw['label'] as String?)?.trim() ?? '',
      isInitial: raw['isInitial'] == true,
      isTerminal: raw['isTerminal'] == true,
      description: (raw['description'] as String?)?.trim() ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LifecycleState &&
          other.name == name &&
          other.label == label &&
          other.isInitial == isInitial &&
          other.isTerminal == isTerminal &&
          other.description == description;

  @override
  int get hashCode =>
      Object.hash(name, label, isInitial, isTerminal, description);
}

/// Transition autorisée entre deux états du cycle de vie d'un objet métier.
@immutable
class LifecycleTransition {
  /// Construit une transition immuable.
  const LifecycleTransition({
    required this.id,
    required this.fromState,
    required this.toState,
    this.trigger = '',
    this.guardSummary = '',
  });

  /// Identifiant unique de la transition.
  final String id;

  /// Nom de l'état source.
  final String fromState;

  /// Nom de l'état cible.
  final String toState;

  /// Événement ou action déclenchant la transition.
  final String trigger;

  /// Résumé de la condition de garde.
  final String guardSummary;

  /// Copie modifiée.
  LifecycleTransition copyWith({
    String? id,
    String? fromState,
    String? toState,
    String? trigger,
    String? guardSummary,
  }) => LifecycleTransition(
    id: id ?? this.id,
    fromState: fromState ?? this.fromState,
    toState: toState ?? this.toState,
    trigger: trigger ?? this.trigger,
    guardSummary: guardSummary ?? this.guardSummary,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'fromState': fromState,
    'toState': toState,
    'trigger': trigger,
    'guardSummary': guardSummary,
  };

  /// Désérialise depuis JSON.
  factory LifecycleTransition.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'LifecycleTransition doit être un objet JSON.',
      );
    }
    final fromState = (raw['fromState'] as String?)?.trim() ?? '';
    final toState = (raw['toState'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    return LifecycleTransition(
      id: id.isEmpty ? 'tr_${fromState}_$toState' : id,
      fromState: fromState,
      toState: toState,
      trigger: (raw['trigger'] as String?)?.trim() ?? '',
      guardSummary: (raw['guardSummary'] as String?)?.trim() ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LifecycleTransition &&
          other.id == id &&
          other.fromState == fromState &&
          other.toState == toState &&
          other.trigger == trigger &&
          other.guardSummary == guardSummary;

  @override
  int get hashCode =>
      Object.hash(id, fromState, toState, trigger, guardSummary);
}

/// Définition complète d'un objet métier (étape 3).
@immutable
class BusinessObjectSpec {
  /// Construit un objet métier immuable.
  BusinessObjectSpec({
    required this.id,
    required this.name,
    String? technicalName,
    this.description = '',
    this.aggregateRoot = true,
    List<BusinessAttribute> attributes = const <BusinessAttribute>[],
    List<BusinessRelation> relations = const <BusinessRelation>[],
    List<LifecycleState> lifecycleStates = const <LifecycleState>[],
    List<LifecycleTransition> lifecycleTransitions =
        const <LifecycleTransition>[],
  }) : technicalName = (technicalName == null || technicalName.trim().isEmpty)
           ? _toPascalCase(name)
           : technicalName.trim(),
       attributes = List<BusinessAttribute>.unmodifiable(attributes),
       relations = List<BusinessRelation>.unmodifiable(relations),
       lifecycleStates = List<LifecycleState>.unmodifiable(lifecycleStates),
       lifecycleTransitions = List<LifecycleTransition>.unmodifiable(
         lifecycleTransitions,
       );

  /// Plafond strict d'attributs (directs + sous-objets) par objet métier.
  static const int maxAttributesPerObject = 200;

  /// Plafond strict de lignes pour tout tableau imbriqué dans un objet métier.
  static const int maxEmbeddedArrayRows = 200;

  /// Identifiant unique de l'objet (ex. `obj_commande`).
  final String id;

  /// Nom métier lisible (ex. `Commande client`).
  final String name;

  /// Nom technique PascalCase utilisé dans les exports YAML/JSON Schema (ex. `CommandeClient`).
  final String technicalName;

  /// Description du rôle métier de l'entité.
  final String description;

  /// Indique s'il s'agit d'un agrégat racine (ou d'un sous-objet valeur).
  final bool aggregateRoot;

  /// Attributs typés de l'objet.
  final List<BusinessAttribute> attributes;

  /// Relations sortantes vers d'autres objets métiers.
  final List<BusinessRelation> relations;

  /// États du cycle de vie (si l'objet est stateful).
  final List<LifecycleState> lifecycleStates;

  /// Transitions autorisées entre états.
  final List<LifecycleTransition> lifecycleTransitions;

  /// Nombre total récursif d'attributs (directs + sous-attributs imbriqués).
  int get totalAttributeCount =>
      attributes.fold<int>(0, (sum, attr) => sum + attr.totalAttributeCount);

  /// Vérifie les invariants de l'objet métier et les règles de dimensionnement (≤ 200).
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BusinessObjectSpec.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'BusinessObjectSpec.name ne peut pas être vide.',
      );
    }
    if (!BusinessAttribute.isValidDslIdentifier(technicalName)) {
      throw FormatException(
        'Nom technique d’objet métier incompatible avec le DSL YAML : $technicalName '
        '(utilisez uniquement des caractères ASCII [A-Za-z_][A-Za-z0-9_-]*, sans accent ni espace).',
      );
    }
    final totalAttrs = totalAttributeCount;
    if (totalAttrs > maxAttributesPerObject) {
      throw FormatException(
        'L’objet métier « $name » contient $totalAttrs attributs, ce qui dépasse la limite de $maxAttributesPerObject attributs. Scindez-le en plusieurs objets métiers.',
      );
    }
    final attrNames = <String>{};
    for (final attr in attributes) {
      attr.validate();
      if (!attrNames.add(attr.name)) {
        throw FormatException(
          'Attribut dupliqué « ${attr.name} » sur l\'objet « $name ».',
        );
      }
      _validateArrayRowBounds(attr);
    }
    for (final rel in relations) {
      rel.validate();
    }
  }

  void _validateArrayRowBounds(BusinessAttribute attr) {
    final effectiveMaxRows = attr.estimatedMaxRows ?? attr.schemaConstraints.maxItems;
    if (attr.isArray &&
        effectiveMaxRows != null &&
        effectiveMaxRows > maxEmbeddedArrayRows) {
      throw FormatException(
        'Le tableau imbriqué « ${attr.name} » de l’objet « $name » prévoit $effectiveMaxRows lignes (> $maxEmbeddedArrayRows). Modélisez-le comme un objet métier dédié relié par référence.',
      );
    }
    for (final child in attr.children) {
      _validateArrayRowBounds(child);
    }
  }

  /// Copie modifiée.
  BusinessObjectSpec copyWith({
    String? id,
    String? name,
    String? technicalName,
    String? description,
    bool? aggregateRoot,
    List<BusinessAttribute>? attributes,
    List<BusinessRelation>? relations,
    List<LifecycleState>? lifecycleStates,
    List<LifecycleTransition>? lifecycleTransitions,
  }) => BusinessObjectSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    technicalName: technicalName ?? this.technicalName,
    description: description ?? this.description,
    aggregateRoot: aggregateRoot ?? this.aggregateRoot,
    attributes: attributes ?? this.attributes,
    relations: relations ?? this.relations,
    lifecycleStates: lifecycleStates ?? this.lifecycleStates,
    lifecycleTransitions: lifecycleTransitions ?? this.lifecycleTransitions,
  );

  /// Sérialise l'objet métier en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'technicalName': technicalName,
    'description': description,
    'aggregateRoot': aggregateRoot,
    'attributes': [for (final a in attributes) a.toJson()],
    'relations': [for (final r in relations) r.toJson()],
    'lifecycleStates': [for (final s in lifecycleStates) s.toJson()],
    'lifecycleTransitions': [for (final t in lifecycleTransitions) t.toJson()],
  };

  /// Désérialise depuis JSON.
  factory BusinessObjectSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'BusinessObjectSpec doit être un objet JSON.',
      );
    }
    final name = (raw['name'] as String?)?.trim() ?? 'Objet';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final obj = BusinessObjectSpec(
      id: id.isEmpty ? 'obj_${_sanitizeIdentifier(name).toLowerCase()}' : id,
      name: name.isEmpty ? 'Objet' : name,
      technicalName: (raw['technicalName'] as String?)?.trim(),
      description: (raw['description'] as String?)?.trim() ?? '',
      aggregateRoot: raw['aggregateRoot'] is bool
          ? raw['aggregateRoot'] as bool
          : true,
      attributes: [
        if (raw['attributes'] is List)
          for (final item in raw['attributes'] as List)
            BusinessAttribute.fromJson(item),
      ],
      relations: [
        if (raw['relations'] is List)
          for (final item in raw['relations'] as List)
            BusinessRelation.fromJson(item),
      ],
      lifecycleStates: [
        if (raw['lifecycleStates'] is List)
          for (final item in raw['lifecycleStates'] as List)
            LifecycleState.fromJson(item),
      ],
      lifecycleTransitions: [
        if (raw['lifecycleTransitions'] is List)
          for (final item in raw['lifecycleTransitions'] as List)
            LifecycleTransition.fromJson(item),
      ],
    );
    obj.validate();
    return obj;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessObjectSpec &&
          other.id == id &&
          other.name == name &&
          other.technicalName == technicalName &&
          other.description == description &&
          other.aggregateRoot == aggregateRoot &&
          listEquals(other.attributes, attributes) &&
          listEquals(other.relations, relations) &&
          listEquals(other.lifecycleStates, lifecycleStates) &&
          listEquals(other.lifecycleTransitions, lifecycleTransitions);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    technicalName,
    description,
    aggregateRoot,
    Object.hashAll(attributes),
    Object.hashAll(relations),
    Object.hashAll(lifecycleStates),
    Object.hashAll(lifecycleTransitions),
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

String _foldLatinAccents(String input) {
  const map = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'æ': 'ae',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ø': 'o',
    'œ': 'oe',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'À': 'A',
    'Á': 'A',
    'Â': 'A',
    'Ã': 'A',
    'Ä': 'A',
    'Å': 'A',
    'Æ': 'AE',
    'Ç': 'C',
    'È': 'E',
    'É': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'Ì': 'I',
    'Í': 'I',
    'Î': 'I',
    'Ï': 'I',
    'Ñ': 'N',
    'Ò': 'O',
    'Ó': 'O',
    'Ô': 'O',
    'Õ': 'O',
    'Ö': 'O',
    'Ø': 'O',
    'Œ': 'OE',
    'Ù': 'U',
    'Ú': 'U',
    'Û': 'U',
    'Ü': 'U',
    'Ý': 'Y',
    'Ÿ': 'Y',
  };
  final buf = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    buf.write(map[ch] ?? ch);
  }
  return buf.toString();
}

String _sanitizeIdentifier(String input, {String fallback = 'champ'}) {
  final folded = _foldLatinAccents(input.trim());
  var cleaned = folded.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  cleaned = cleaned.replaceAll(RegExp(r'^[^A-Za-z_]+'), '');
  return cleaned.isEmpty ? fallback : cleaned;
}

String _toPascalCase(String input) {
  final folded = _foldLatinAccents(input.trim());
  final words = folded
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'ObjetMetier';
  return words
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join();
}
