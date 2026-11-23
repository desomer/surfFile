/// Modèles immuables de la couche Domain en Architecture Hexagonale ([HexagonalDomainLayerSpec])
/// rattachée à une entrée de modèle d'un domaine fonctionnel.
library;

import 'package:flutter/foundation.dart';

List<String> _cleanStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
  ];
}

/// Les 7 onglets structurant la couche Domain d'un objet métier en Architecture Hexagonale.
enum DomainLayerTab {
  /// Invariants métier et contraintes d'intégrité permanentes.
  invariants(
    label: 'Invariants',
    subtitle: 'Règles d’intégrité garanties à tout instant par l’objet métier',
  ),

  /// Méthodes et commandes modifiant l'état interne de l'agrégat/entité.
  stateChanging(
    label: 'State changing',
    subtitle:
        'Comportements et commandes métier mutant l’état avec préconditions et événements',
  ),

  /// Calculs purs, projections locales et prédicats sans effet de bord.
  query(
    label: 'Query',
    subtitle: 'Méthodes pures, calculs dérivés et prédicats sans effet de bord',
  ),

  /// Services du domaine et politiques métier sans état (Strategy / Policy).
  policyServices(
    label: 'Policy Services',
    subtitle: 'Politiques et services métier purs orchestrant des règles transverses',
  ),

  /// Fabriques et constructeurs métier garantissant un état initial valide.
  factory(
    label: 'Factory',
    subtitle: 'Fabriques d’instanciation et de reconstitution de l’objet métier',
  ),

  /// Événements du domaine émis suite aux transitions d'état.
  domainEvents(
    label: 'Domain events',
    subtitle: 'Faits métier immuables publiés par l’agrégat',
  ),

  /// Politique de persistance et contrat du port sortant Repository.
  persistencePolicy(
    label: 'Persistence policy',
    subtitle:
        'Contrat du port sortant Repository, frontière transactionnelle et concurrence',
  );

  const DomainLayerTab({required this.label, required this.subtitle});

  /// Libellé exact de l'onglet dans l'interface.
  final String label;

  /// Sous-titre explicatif affiché dans l'atelier et transmis à l'IA.
  final String subtitle;

  /// Résout un onglet depuis son nom JSON ou son libellé.
  static DomainLayerTab fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final tab in DomainLayerTab.values) {
        if (tab.name.toLowerCase() == norm || tab.label.toLowerCase() == norm) {
          return tab;
        }
      }
    }
    return DomainLayerTab.invariants;
  }
}

/// Stratégie de contrôle de concurrence sur l'agrégat persisté.
enum DomainConcurrencyStrategy {
  /// Verrouillage optimiste par numéro de version ou ETag.
  optimisticVersion('Verrouillage optimiste (version)'),

  /// Verrouillage pessimiste exclusif lors des mutations critiques.
  pessimisticLock('Verrouillage pessimiste'),

  /// Journal d'événements ou écritures immuables append-only.
  appendOnly('Append-only / Event Sourcing'),

  /// Pas de contrôle de concurrence spécifique (dernier écrivain gagne).
  none('Aucun (standard)');

  const DomainConcurrencyStrategy(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise une stratégie de concurrence.
  static DomainConcurrencyStrategy fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in DomainConcurrencyStrategy.values) {
        if (value.name.toLowerCase() == norm) return value;
      }
      if (norm.contains('pessim')) return pessimisticLock;
      if (norm.contains('append') || norm.contains('event')) return appendOnly;
      if (norm == 'none' || norm.contains('aucun')) return none;
    }
    return DomainConcurrencyStrategy.optimisticVersion;
  }
}

/// Politique de suppression et de rétention de l'agrégat.
enum DomainDeletionStrategy {
  /// Suppression logique (marquage d'archivage / date de désactivation).
  softDelete('Suppression logique (soft delete)'),

  /// Suppression physique directe autorisée sous conditions métier.
  hardDelete('Suppression physique (hard delete)'),

  /// Entité immuable ou clôturée par transition métier uniquement (jamais supprimée).
  immutableArchive('Conservation légale / Archivage sans suppression');

  const DomainDeletionStrategy(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise une politique de suppression.
  static DomainDeletionStrategy fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in DomainDeletionStrategy.values) {
        if (value.name.toLowerCase() == norm) return value;
      }
      if (norm.contains('hard') || norm.contains('physique')) return hardDelete;
      if (norm.contains('immut') || norm.contains('archiv')) {
        return immutableArchive;
      }
    }
    return DomainDeletionStrategy.softDelete;
  }
}

/// Invariant métier garantissant la validité permanente de l'objet.
@immutable
class DomainInvariantSpec {
  /// Crée un invariant immuable.
  DomainInvariantSpec({
    required this.id,
    required this.code,
    required this.title,
    this.expression = '',
    List<String> relatedAttributes = const <String>[],
    this.violationError = '',
    this.description = '',
  }) : relatedAttributes = List<String>.unmodifiable(relatedAttributes);

  /// Identifiant technique stable.
  final String id;

  /// Code court de l'invariant (ex. `INV-01`).
  final String code;

  /// Titre synthétique de l'invariant.
  final String title;

  /// Expression logique ou condition formelle (ex. `montantHt >= 0`).
  final String expression;

  /// Noms des attributs du modèle impliqués dans l'invariant.
  final List<String> relatedAttributes;

  /// Code ou classe d'erreur du domaine levée en cas de violation.
  final String violationError;

  /// Explication métier détaillée.
  final String description;

  /// Vérifie les invariants structurels.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainInvariantSpec.id requis.');
    }
    if (title.trim().isEmpty && code.trim().isEmpty) {
      throw const FormatException(
        'Un invariant doit avoir au moins un code ou un titre.',
      );
    }
  }

  /// Copie modifiée.
  DomainInvariantSpec copyWith({
    String? id,
    String? code,
    String? title,
    String? expression,
    List<String>? relatedAttributes,
    String? violationError,
    String? description,
  }) => DomainInvariantSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    title: title ?? this.title,
    expression: expression ?? this.expression,
    relatedAttributes: relatedAttributes ?? this.relatedAttributes,
    violationError: violationError ?? this.violationError,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'title': title,
    if (expression.isNotEmpty) 'expression': expression,
    if (relatedAttributes.isNotEmpty) 'relatedAttributes': relatedAttributes,
    if (violationError.isNotEmpty) 'violationError': violationError,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainInvariantSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainInvariantSpec invalide.');
    }
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final rawTitle = (raw['title'] as String?)?.trim() ?? '';
    final effectiveCode = rawCode.isEmpty ? 'INV' : rawCode;
    final effectiveTitle = rawTitle.isEmpty ? effectiveCode : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainInvariantSpec(
      id: rawId.isEmpty
          ? 'inv_${(effectiveCode + effectiveTitle).hashCode.abs()}'
          : rawId,
      code: effectiveCode,
      title: effectiveTitle,
      expression: (raw['expression'] as String?)?.trim() ?? '',
      relatedAttributes: _cleanStringList(raw['relatedAttributes']),
      violationError: (raw['violationError'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainInvariantSpec &&
          other.id == id &&
          other.code == code &&
          other.title == title &&
          other.expression == expression &&
          listEquals(other.relatedAttributes, relatedAttributes) &&
          other.violationError == violationError &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    title,
    expression,
    Object.hashAll(relatedAttributes),
    violationError,
    description,
  );
}

/// Comportement / commande métier modifiant l'état de l'objet (`State changing`).
@immutable
class DomainStateChangeSpec {
  /// Crée une méthode de mutation d'état immuable.
  DomainStateChangeSpec({
    required this.id,
    required this.name,
    List<String> parameters = const <String>[],
    List<String> preconditions = const <String>[],
    List<String> mutations = const <String>[],
    List<String> fromStates = const <String>[],
    this.toState = '',
    List<String> emittedEvents = const <String>[],
    List<String> domainErrors = const <String>[],
    this.description = '',
  }) : parameters = List<String>.unmodifiable(parameters),
       preconditions = List<String>.unmodifiable(preconditions),
       mutations = List<String>.unmodifiable(mutations),
       fromStates = List<String>.unmodifiable(fromStates),
       emittedEvents = List<String>.unmodifiable(emittedEvents),
       domainErrors = List<String>.unmodifiable(domainErrors);

  /// Identifiant technique stable.
  final String id;

  /// Nom de la commande / méthode métier (ex. `confirmer`, `appliquerRemise`).
  final String name;

  /// Paramètres d'entrée typés (ex. `motif: string`, `dateValidation: datetime`).
  final List<String> parameters;

  /// Gardes et préconditions métier vérifiées avant mutation.
  final List<String> preconditions;

  /// Attributs ou états internes modifiés (postconditions).
  final List<String> mutations;

  /// États sources autorisés (si l'objet possède un cycle de vie).
  final List<String> fromStates;

  /// État cible après exécution (si applicable).
  final String toState;

  /// Noms des événements du domaine levés lors du succès.
  final List<String> emittedEvents;

  /// Exceptions ou refus métier pouvant être levés.
  final List<String> domainErrors;

  /// Intention métier de l'opération.
  final String description;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainStateChangeSpec.id requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('DomainStateChangeSpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainStateChangeSpec copyWith({
    String? id,
    String? name,
    List<String>? parameters,
    List<String>? preconditions,
    List<String>? mutations,
    List<String>? fromStates,
    String? toState,
    List<String>? emittedEvents,
    List<String>? domainErrors,
    String? description,
  }) => DomainStateChangeSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    parameters: parameters ?? this.parameters,
    preconditions: preconditions ?? this.preconditions,
    mutations: mutations ?? this.mutations,
    fromStates: fromStates ?? this.fromStates,
    toState: toState ?? this.toState,
    emittedEvents: emittedEvents ?? this.emittedEvents,
    domainErrors: domainErrors ?? this.domainErrors,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (parameters.isNotEmpty) 'parameters': parameters,
    if (preconditions.isNotEmpty) 'preconditions': preconditions,
    if (mutations.isNotEmpty) 'mutations': mutations,
    if (fromStates.isNotEmpty) 'fromStates': fromStates,
    if (toState.isNotEmpty) 'toState': toState,
    if (emittedEvents.isNotEmpty) 'emittedEvents': emittedEvents,
    if (domainErrors.isNotEmpty) 'domainErrors': domainErrors,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainStateChangeSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainStateChangeSpec invalide.');
    }
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isEmpty ? 'executerAction' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainStateChangeSpec(
      id: rawId.isEmpty ? 'cmd_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      parameters: _cleanStringList(raw['parameters']),
      preconditions: _cleanStringList(raw['preconditions']),
      mutations: _cleanStringList(raw['mutations']),
      fromStates: _cleanStringList(raw['fromStates']),
      toState: (raw['toState'] as String?)?.trim() ?? '',
      emittedEvents: _cleanStringList(raw['emittedEvents']),
      domainErrors: _cleanStringList(raw['domainErrors']),
      description: (raw['description'] as String?)?.trim() ?? '',
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainStateChangeSpec &&
          other.id == id &&
          other.name == name &&
          listEquals(other.parameters, parameters) &&
          listEquals(other.preconditions, preconditions) &&
          listEquals(other.mutations, mutations) &&
          listEquals(other.fromStates, fromStates) &&
          other.toState == toState &&
          listEquals(other.emittedEvents, emittedEvents) &&
          listEquals(other.domainErrors, domainErrors) &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(parameters),
    Object.hashAll(preconditions),
    Object.hashAll(mutations),
    Object.hashAll(fromStates),
    toState,
    Object.hashAll(emittedEvents),
    Object.hashAll(domainErrors),
    description,
  );
}

/// Calcul pur ou méthode de lecture métier sans effet de bord (`Query`).
@immutable
class DomainQuerySpec {
  /// Crée une query métier immuable.
  DomainQuerySpec({
    required this.id,
    required this.name,
    List<String> parameters = const <String>[],
    this.returnType = 'bool',
    this.formula = '',
    this.description = '',
  }) : parameters = List<String>.unmodifiable(parameters);

  /// Identifiant technique stable.
  final String id;

  /// Nom de la méthode pure ou du prédicat (ex. `calculerTotalTtc`, `estEligibleRemise`).
  final String name;

  /// Paramètres éventuels (ex. `tauxTva: number`).
  final List<String> parameters;

  /// Type retourné (ex. `number`, `bool`, `Montant`).
  final String returnType;

  /// Formule ou règle de calcul pure.
  final String formula;

  /// Description fonctionnelle.
  final String description;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainQuerySpec.id requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('DomainQuerySpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainQuerySpec copyWith({
    String? id,
    String? name,
    List<String>? parameters,
    String? returnType,
    String? formula,
    String? description,
  }) => DomainQuerySpec(
    id: id ?? this.id,
    name: name ?? this.name,
    parameters: parameters ?? this.parameters,
    returnType: returnType ?? this.returnType,
    formula: formula ?? this.formula,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (parameters.isNotEmpty) 'parameters': parameters,
    'returnType': returnType,
    if (formula.isNotEmpty) 'formula': formula,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainQuerySpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainQuerySpec invalide.');
    }
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isEmpty ? 'verifierCondition' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawReturn = (raw['returnType'] as String?)?.trim() ?? '';
    final item = DomainQuerySpec(
      id: rawId.isEmpty ? 'qry_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      parameters: _cleanStringList(raw['parameters']),
      returnType: rawReturn.isEmpty ? 'bool' : rawReturn,
      formula: (raw['formula'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainQuerySpec &&
          other.id == id &&
          other.name == name &&
          listEquals(other.parameters, parameters) &&
          other.returnType == returnType &&
          other.formula == formula &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(parameters),
    returnType,
    formula,
    description,
  );
}

/// Service du domaine ou politique métier sans état (`Policy Services`).
@immutable
class DomainPolicyServiceSpec {
  /// Crée une policy / service du domaine immuable.
  DomainPolicyServiceSpec({
    required this.id,
    required this.name,
    this.operation = '',
    List<String> collaborators = const <String>[],
    List<String> rules = const <String>[],
    this.description = '',
  }) : collaborators = List<String>.unmodifiable(collaborators),
       rules = List<String>.unmodifiable(rules);

  /// Identifiant technique stable.
  final String id;

  /// Nom du service ou de la policy (ex. `PolitiqueRemiseVolume`, `CalculFraisPortPolicy`).
  final String name;

  /// Opération ou signature principale exposée.
  final String operation;

  /// Autres objets du domaine ou ports impliqués.
  final List<String> collaborators;

  /// Règles de décision encapsulées par la policy.
  final List<String> rules;

  /// Rôle métier du service.
  final String description;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainPolicyServiceSpec.id requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('DomainPolicyServiceSpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainPolicyServiceSpec copyWith({
    String? id,
    String? name,
    String? operation,
    List<String>? collaborators,
    List<String>? rules,
    String? description,
  }) => DomainPolicyServiceSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    operation: operation ?? this.operation,
    collaborators: collaborators ?? this.collaborators,
    rules: rules ?? this.rules,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (operation.isNotEmpty) 'operation': operation,
    if (collaborators.isNotEmpty) 'collaborators': collaborators,
    if (rules.isNotEmpty) 'rules': rules,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainPolicyServiceSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainPolicyServiceSpec invalide.');
    }
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isEmpty ? 'DomainPolicy' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainPolicyServiceSpec(
      id: rawId.isEmpty ? 'pol_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      operation: (raw['operation'] as String?)?.trim() ?? '',
      collaborators: _cleanStringList(raw['collaborators']),
      rules: _cleanStringList(raw['rules']),
      description: (raw['description'] as String?)?.trim() ?? '',
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainPolicyServiceSpec &&
          other.id == id &&
          other.name == name &&
          other.operation == operation &&
          listEquals(other.collaborators, collaborators) &&
          listEquals(other.rules, rules) &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    operation,
    Object.hashAll(collaborators),
    Object.hashAll(rules),
    description,
  );
}

/// Fabrique métier d'instanciation ou de reconstitution (`Factory`).
@immutable
class DomainFactorySpec {
  /// Crée une fabrique métier immuable.
  DomainFactorySpec({
    required this.id,
    required this.name,
    List<String> parameters = const <String>[],
    this.initialState = '',
    List<String> enforcedInvariants = const <String>[],
    List<String> emittedEvents = const <String>[],
    this.description = '',
  }) : parameters = List<String>.unmodifiable(parameters),
       enforcedInvariants = List<String>.unmodifiable(enforcedInvariants),
       emittedEvents = List<String>.unmodifiable(emittedEvents);

  /// Identifiant technique stable.
  final String id;

  /// Nom de la fabrique (ex. `creerBrouillon`, `depuisDevisAccepte`).
  final String name;

  /// Paramètres requis à la création.
  final List<String> parameters;

  /// État initial assigné à l'instance créée.
  final String initialState;

  /// Codes ou titres des invariants garantis dès la construction.
  final List<String> enforcedInvariants;

  /// Événements du domaine émis à la création.
  final List<String> emittedEvents;

  /// Rôle métier de la fabrique.
  final String description;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainFactorySpec.id requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('DomainFactorySpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainFactorySpec copyWith({
    String? id,
    String? name,
    List<String>? parameters,
    String? initialState,
    List<String>? enforcedInvariants,
    List<String>? emittedEvents,
    String? description,
  }) => DomainFactorySpec(
    id: id ?? this.id,
    name: name ?? this.name,
    parameters: parameters ?? this.parameters,
    initialState: initialState ?? this.initialState,
    enforcedInvariants: enforcedInvariants ?? this.enforcedInvariants,
    emittedEvents: emittedEvents ?? this.emittedEvents,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (parameters.isNotEmpty) 'parameters': parameters,
    if (initialState.isNotEmpty) 'initialState': initialState,
    if (enforcedInvariants.isNotEmpty) 'enforcedInvariants': enforcedInvariants,
    if (emittedEvents.isNotEmpty) 'emittedEvents': emittedEvents,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainFactorySpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainFactorySpec invalide.');
    }
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isEmpty ? 'creer' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainFactorySpec(
      id: rawId.isEmpty ? 'fac_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      parameters: _cleanStringList(raw['parameters']),
      initialState: (raw['initialState'] as String?)?.trim() ?? '',
      enforcedInvariants: _cleanStringList(raw['enforcedInvariants']),
      emittedEvents: _cleanStringList(raw['emittedEvents']),
      description: (raw['description'] as String?)?.trim() ?? '',
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainFactorySpec &&
          other.id == id &&
          other.name == name &&
          listEquals(other.parameters, parameters) &&
          other.initialState == initialState &&
          listEquals(other.enforcedInvariants, enforcedInvariants) &&
          listEquals(other.emittedEvents, emittedEvents) &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(parameters),
    initialState,
    Object.hashAll(enforcedInvariants),
    Object.hashAll(emittedEvents),
    description,
  );
}

/// Événement immuable du domaine émis par l'agrégat (`Domain events`).
@immutable
class DomainEventSpec {
  /// Crée un événement du domaine immuable.
  DomainEventSpec({
    required this.id,
    required this.name,
    this.trigger = '',
    List<String> payloadFields = const <String>[],
    this.contractEntryRef = '',
    this.description = '',
  }) : payloadFields = List<String>.unmodifiable(payloadFields);

  /// Identifiant technique stable.
  final String id;

  /// Nom de l'événement au passé (ex. `CommandeConfirmee`, `FactureEmise`).
  final String name;

  /// Action *State changing* ou *Factory* à l'origine de l'émission.
  final String trigger;

  /// Attributs portés par la charge utile de l'événement.
  final List<String> payloadFields;

  /// Nom technique ou ID optionnel d'une entrée `eventxpayloaddto` du domaine.
  final String contractEntryRef;

  /// Sens métier de l'événement.
  final String description;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainEventSpec.id requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('DomainEventSpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainEventSpec copyWith({
    String? id,
    String? name,
    String? trigger,
    List<String>? payloadFields,
    String? contractEntryRef,
    String? description,
  }) => DomainEventSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    trigger: trigger ?? this.trigger,
    payloadFields: payloadFields ?? this.payloadFields,
    contractEntryRef: contractEntryRef ?? this.contractEntryRef,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (trigger.isNotEmpty) 'trigger': trigger,
    if (payloadFields.isNotEmpty) 'payloadFields': payloadFields,
    if (contractEntryRef.isNotEmpty) 'contractEntryRef': contractEntryRef,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainEventSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainEventSpec invalide.');
    }
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isEmpty ? 'EvenementDomaine' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainEventSpec(
      id: rawId.isEmpty ? 'evt_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      trigger: (raw['trigger'] as String?)?.trim() ?? '',
      payloadFields: _cleanStringList(raw['payloadFields']),
      contractEntryRef: (raw['contractEntryRef'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainEventSpec &&
          other.id == id &&
          other.name == name &&
          other.trigger == trigger &&
          listEquals(other.payloadFields, payloadFields) &&
          other.contractEntryRef == contractEntryRef &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    trigger,
    Object.hashAll(payloadFields),
    contractEntryRef,
    description,
  );
}

/// Méthode déclarée sur le port sortant Repository de l'agrégat.
@immutable
class DomainRepositoryMethodSpec {
  /// Crée une méthode de port Repository immuable.
  const DomainRepositoryMethodSpec({
    required this.id,
    required this.name,
    this.signature = '',
    this.description = '',
  });

  /// Identifiant technique stable.
  final String id;

  /// Nom de l'opération (ex. `findById`, `save`, `findByNumero`).
  final String name;

  /// Signature complète côté Domain (ex. `(id: uuid) -> CommandeClient?`).
  final String signature;

  /// Rôle et garanties attendues de l'opération.
  final String description;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainRepositoryMethodSpec.id requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('DomainRepositoryMethodSpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainRepositoryMethodSpec copyWith({
    String? id,
    String? name,
    String? signature,
    String? description,
  }) => DomainRepositoryMethodSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    signature: signature ?? this.signature,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (signature.isNotEmpty) 'signature': signature,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainRepositoryMethodSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainRepositoryMethodSpec invalide.');
    }
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isEmpty ? 'findById' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainRepositoryMethodSpec(
      id: rawId.isEmpty ? 'repm_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      signature: (raw['signature'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainRepositoryMethodSpec &&
          other.id == id &&
          other.name == name &&
          other.signature == signature &&
          other.description == description;

  @override
  int get hashCode => Object.hash(id, name, signature, description);
}

/// Politique de persistance et contrat du port sortant Repository (`Persistence policy`).
@immutable
class DomainPersistencePolicySpec {
  /// Crée une politique de persistance immuable.
  DomainPersistencePolicySpec({
    this.repositoryPortName = '',
    this.aggregateBoundary = '',
    this.concurrencyStrategy = DomainConcurrencyStrategy.optimisticVersion,
    this.deletionStrategy = DomainDeletionStrategy.softDelete,
    this.consistencyNotes = '',
    List<DomainRepositoryMethodSpec> portMethods =
        const <DomainRepositoryMethodSpec>[],
  }) : portMethods = List<DomainRepositoryMethodSpec>.unmodifiable(portMethods);

  /// Politique par défaut vierge.
  static final DomainPersistencePolicySpec empty =
      DomainPersistencePolicySpec();

  /// Nom de l'interface du port sortant Repository (ex. `CommandeClientRepository`).
  final String repositoryPortName;

  /// Périmètre transactionnel de l'agrégat sauvegardé/chargé atomiquement.
  final String aggregateBoundary;

  /// Stratégie de gestion des accès concurrents.
  final DomainConcurrencyStrategy concurrencyStrategy;

  /// Stratégie de suppression et d'archivage.
  final DomainDeletionStrategy deletionStrategy;

  /// Contraintes d'unicité, index métier, rétention ou cohérence éventuelle.
  final String consistencyNotes;

  /// Opérations exposées par le port sortant Repository.
  final List<DomainRepositoryMethodSpec> portMethods;

  /// Vrai si au moins un élément de la politique a été renseigné.
  bool get isConfigured =>
      repositoryPortName.trim().isNotEmpty ||
      aggregateBoundary.trim().isNotEmpty ||
      consistencyNotes.trim().isNotEmpty ||
      portMethods.isNotEmpty ||
      concurrencyStrategy != DomainConcurrencyStrategy.optimisticVersion ||
      deletionStrategy != DomainDeletionStrategy.softDelete;

  /// Vérifie les invariants.
  void validate() {
    for (final method in portMethods) {
      method.validate();
    }
  }

  /// Copie modifiée.
  DomainPersistencePolicySpec copyWith({
    String? repositoryPortName,
    String? aggregateBoundary,
    DomainConcurrencyStrategy? concurrencyStrategy,
    DomainDeletionStrategy? deletionStrategy,
    String? consistencyNotes,
    List<DomainRepositoryMethodSpec>? portMethods,
  }) => DomainPersistencePolicySpec(
    repositoryPortName: repositoryPortName ?? this.repositoryPortName,
    aggregateBoundary: aggregateBoundary ?? this.aggregateBoundary,
    concurrencyStrategy: concurrencyStrategy ?? this.concurrencyStrategy,
    deletionStrategy: deletionStrategy ?? this.deletionStrategy,
    consistencyNotes: consistencyNotes ?? this.consistencyNotes,
    portMethods: portMethods ?? this.portMethods,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    if (repositoryPortName.isNotEmpty) 'repositoryPortName': repositoryPortName,
    if (aggregateBoundary.isNotEmpty) 'aggregateBoundary': aggregateBoundary,
    'concurrencyStrategy': concurrencyStrategy.name,
    'deletionStrategy': deletionStrategy.name,
    if (consistencyNotes.isNotEmpty) 'consistencyNotes': consistencyNotes,
    if (portMethods.isNotEmpty)
      'portMethods': [for (final m in portMethods) m.toJson()],
  };

  /// Désérialise depuis JSON.
  factory DomainPersistencePolicySpec.fromJson(Object? raw) {
    if (raw == null) return DomainPersistencePolicySpec.empty;
    if (raw is! Map) {
      throw const FormatException('DomainPersistencePolicySpec invalide.');
    }
    final rawMethods = raw['portMethods'];
    final item = DomainPersistencePolicySpec(
      repositoryPortName: (raw['repositoryPortName'] as String?)?.trim() ?? '',
      aggregateBoundary: (raw['aggregateBoundary'] as String?)?.trim() ?? '',
      concurrencyStrategy: DomainConcurrencyStrategy.fromJson(
        raw['concurrencyStrategy'],
      ),
      deletionStrategy: DomainDeletionStrategy.fromJson(
        raw['deletionStrategy'],
      ),
      consistencyNotes: (raw['consistencyNotes'] as String?)?.trim() ?? '',
      portMethods: [
        if (rawMethods is List)
          for (final entry in rawMethods)
            DomainRepositoryMethodSpec.fromJson(entry),
      ],
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainPersistencePolicySpec &&
          other.repositoryPortName == repositoryPortName &&
          other.aggregateBoundary == aggregateBoundary &&
          other.concurrencyStrategy == concurrencyStrategy &&
          other.deletionStrategy == deletionStrategy &&
          other.consistencyNotes == consistencyNotes &&
          listEquals(other.portMethods, portMethods);

  @override
  int get hashCode => Object.hash(
    repositoryPortName,
    aggregateBoundary,
    concurrencyStrategy,
    deletionStrategy,
    consistencyNotes,
    Object.hashAll(portMethods),
  );
}

/// Spécification complète de la couche Domain (Architecture Hexagonale) d'un objet métier.
@immutable
class HexagonalDomainLayerSpec {
  /// Crée la spécification immuable de la couche Domain.
  HexagonalDomainLayerSpec({
    List<DomainInvariantSpec> invariants = const <DomainInvariantSpec>[],
    List<DomainStateChangeSpec> stateChanges = const <DomainStateChangeSpec>[],
    List<DomainQuerySpec> queries = const <DomainQuerySpec>[],
    List<DomainPolicyServiceSpec> policyServices =
        const <DomainPolicyServiceSpec>[],
    List<DomainFactorySpec> factories = const <DomainFactorySpec>[],
    List<DomainEventSpec> domainEvents = const <DomainEventSpec>[],
    DomainPersistencePolicySpec? persistencePolicy,
  }) : invariants = List<DomainInvariantSpec>.unmodifiable(invariants),
       stateChanges = List<DomainStateChangeSpec>.unmodifiable(stateChanges),
       queries = List<DomainQuerySpec>.unmodifiable(queries),
       policyServices = List<DomainPolicyServiceSpec>.unmodifiable(
         policyServices,
       ),
       factories = List<DomainFactorySpec>.unmodifiable(factories),
       domainEvents = List<DomainEventSpec>.unmodifiable(domainEvents),
       persistencePolicy = persistencePolicy ?? DomainPersistencePolicySpec.empty;

  /// Couche Domain vide.
  static final HexagonalDomainLayerSpec empty = HexagonalDomainLayerSpec();

  /// Types DSL d'entrées de [DomainContracts] éligibles à la couche Domain.
  static const Set<String> eligibleContractTypes = <String>{
    'model',
    'part',
    'component',
  };

  /// Indique si une entrée de type DSL [contractType] expose la page Couche Domain.
  static bool isEligibleType(String contractType) =>
      eligibleContractTypes.contains(contractType.trim().toLowerCase());

  /// 1. Invariants métier.
  final List<DomainInvariantSpec> invariants;

  /// 2. Comportements modifiant l'état (`State changing`).
  final List<DomainStateChangeSpec> stateChanges;

  /// 3. Calculs purs et prédicats (`Query`).
  final List<DomainQuerySpec> queries;

  /// 4. Services et politiques du domaine (`Policy Services`).
  final List<DomainPolicyServiceSpec> policyServices;

  /// 5. Fabriques métier (`Factory`).
  final List<DomainFactorySpec> factories;

  /// 6. Événements du domaine (`Domain events`).
  final List<DomainEventSpec> domainEvents;

  /// 7. Politique de persistance et contrat du port Repository (`Persistence policy`).
  final DomainPersistencePolicySpec persistencePolicy;

  /// Nombre d'éléments renseignés pour l'onglet [tab].
  int countForTab(DomainLayerTab tab) => switch (tab) {
    DomainLayerTab.invariants => invariants.length,
    DomainLayerTab.stateChanging => stateChanges.length,
    DomainLayerTab.query => queries.length,
    DomainLayerTab.policyServices => policyServices.length,
    DomainLayerTab.factory => factories.length,
    DomainLayerTab.domainEvents => domainEvents.length,
    DomainLayerTab.persistencePolicy =>
      persistencePolicy.portMethods.length +
          (persistencePolicy.isConfigured ? 1 : 0),
  };

  /// Nombre total d'éléments définis dans la couche Domain.
  int get totalItemsCount =>
      invariants.length +
      stateChanges.length +
      queries.length +
      policyServices.length +
      factories.length +
      domainEvents.length +
      persistencePolicy.portMethods.length +
      (persistencePolicy.isConfigured && persistencePolicy.portMethods.isEmpty
          ? 1
          : 0);

  /// Vrai si aucune section n'a encore été renseignée.
  bool get isEmpty =>
      invariants.isEmpty &&
      stateChanges.isEmpty &&
      queries.isEmpty &&
      policyServices.isEmpty &&
      factories.isEmpty &&
      domainEvents.isEmpty &&
      !persistencePolicy.isConfigured;

  /// Vrai si au moins une section contient des informations.
  bool get isNotEmpty => !isEmpty;

  /// Vérifie la validité de toutes les sections.
  void validate() {
    for (final item in invariants) {
      item.validate();
    }
    for (final item in stateChanges) {
      item.validate();
    }
    for (final item in queries) {
      item.validate();
    }
    for (final item in policyServices) {
      item.validate();
    }
    for (final item in factories) {
      item.validate();
    }
    for (final item in domainEvents) {
      item.validate();
    }
    persistencePolicy.validate();
  }

  /// Copie modifiée.
  HexagonalDomainLayerSpec copyWith({
    List<DomainInvariantSpec>? invariants,
    List<DomainStateChangeSpec>? stateChanges,
    List<DomainQuerySpec>? queries,
    List<DomainPolicyServiceSpec>? policyServices,
    List<DomainFactorySpec>? factories,
    List<DomainEventSpec>? domainEvents,
    DomainPersistencePolicySpec? persistencePolicy,
  }) => HexagonalDomainLayerSpec(
    invariants: invariants ?? this.invariants,
    stateChanges: stateChanges ?? this.stateChanges,
    queries: queries ?? this.queries,
    policyServices: policyServices ?? this.policyServices,
    factories: factories ?? this.factories,
    domainEvents: domainEvents ?? this.domainEvents,
    persistencePolicy: persistencePolicy ?? this.persistencePolicy,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    if (invariants.isNotEmpty)
      'invariants': [for (final item in invariants) item.toJson()],
    if (stateChanges.isNotEmpty)
      'stateChanges': [for (final item in stateChanges) item.toJson()],
    if (queries.isNotEmpty)
      'queries': [for (final item in queries) item.toJson()],
    if (policyServices.isNotEmpty)
      'policyServices': [for (final item in policyServices) item.toJson()],
    if (factories.isNotEmpty)
      'factories': [for (final item in factories) item.toJson()],
    if (domainEvents.isNotEmpty)
      'domainEvents': [for (final item in domainEvents) item.toJson()],
    if (persistencePolicy.isConfigured)
      'persistencePolicy': persistencePolicy.toJson(),
  };

  /// Désérialise depuis JSON.
  factory HexagonalDomainLayerSpec.fromJson(Object? raw) {
    if (raw == null) return HexagonalDomainLayerSpec.empty;
    if (raw is! Map) {
      throw const FormatException('HexagonalDomainLayerSpec invalide.');
    }
    final spec = HexagonalDomainLayerSpec(
      invariants: [
        if (raw['invariants'] is List)
          for (final item in raw['invariants'] as List)
            DomainInvariantSpec.fromJson(item),
      ],
      stateChanges: [
        if (raw['stateChanges'] is List)
          for (final item in raw['stateChanges'] as List)
            DomainStateChangeSpec.fromJson(item),
      ],
      queries: [
        if (raw['queries'] is List)
          for (final item in raw['queries'] as List)
            DomainQuerySpec.fromJson(item),
      ],
      policyServices: [
        if (raw['policyServices'] is List)
          for (final item in raw['policyServices'] as List)
            DomainPolicyServiceSpec.fromJson(item),
      ],
      factories: [
        if (raw['factories'] is List)
          for (final item in raw['factories'] as List)
            DomainFactorySpec.fromJson(item),
      ],
      domainEvents: [
        if (raw['domainEvents'] is List)
          for (final item in raw['domainEvents'] as List)
            DomainEventSpec.fromJson(item),
      ],
      persistencePolicy: raw.containsKey('persistencePolicy')
          ? DomainPersistencePolicySpec.fromJson(raw['persistencePolicy'])
          : DomainPersistencePolicySpec.empty,
    );
    spec.validate();
    return spec;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HexagonalDomainLayerSpec &&
          listEquals(other.invariants, invariants) &&
          listEquals(other.stateChanges, stateChanges) &&
          listEquals(other.queries, queries) &&
          listEquals(other.policyServices, policyServices) &&
          listEquals(other.factories, factories) &&
          listEquals(other.domainEvents, domainEvents) &&
          other.persistencePolicy == persistencePolicy;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(invariants),
    Object.hashAll(stateChanges),
    Object.hashAll(queries),
    Object.hashAll(policyServices),
    Object.hashAll(factories),
    Object.hashAll(domainEvents),
    persistencePolicy,
  );
}
