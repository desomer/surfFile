/// Modèles immuables de la couche Domain en Architecture Hexagonale ([HexagonalDomainLayerSpec])
/// rattachée à une entrée de modèle d'un domaine fonctionnel.
library;

import 'package:flutter/foundation.dart';

List<String> _cleanStringList(Object? raw) {
  if (raw is String) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? const <String>[] : <String>[trimmed];
  }
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
  ];
}

List<String> _parseAssociatedMethods(Map<dynamic, dynamic> raw) =>
    _cleanStringList(
      raw['associatedMethods'] ??
          raw['associatedInternalMethods'] ??
          raw['associated_internal_methods'] ??
          raw['methods'],
    );

List<String> _dedupStrings(Iterable<String> values) {
  final seen = <String>{};
  final out = <String>[];
  for (final v in values) {
    final clean = v.trim();
    if (clean.isNotEmpty && seen.add(clean)) {
      out.add(clean);
    }
  }
  return out;
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
    subtitle: 'Comportements et commandes métier mutant l’état avec préconditions et événements',
  ),

  /// Calculs purs, projections locales et prédicats sans effet de bord.
  query(
    label: 'Query',
    subtitle: 'Méthodes pures, calculs dérivés et prédicats sans effet de bord',
  ),

  /// Services du domaine et politiques métier sans état (Strategy / Policy).
  policyServices(
    label: 'Policy Services',
    subtitle:
        'Politiques et services métier purs orchestrant des règles transverses',
  ),

  /// Fabriques et constructeurs métier garantissant un état initial valide.
  factory(
    label: 'Factory',
    subtitle:
        'Fabriques d’instanciation et de reconstitution de l’objet métier',
  ),

  /// Événements du domaine émis suite aux transitions d'état.
  domainEvents(
    label: 'Domain events',
    subtitle: 'Faits métier immuables publiés par l’agrégat',
  ),

  /// Politique de persistance et contrat du port sortant Repository.
  persistencePolicy(
    label: 'Persistence policy',
    subtitle: 'Contrat du port sortant Repository, frontière transactionnelle et concurrence',
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

/// Catégorie fonctionnelle d'un comportement ou d'une règle de `persistence_policy_behaviors`.
enum PersistenceBehaviorCategory {
  /// CRUD métier (`saveXXX()`, `findByXXX()`).
  crud('CRUD métier'),

  /// Vérification (`existsXXX()`, `isUniqueXXX()`, `canBeDeletedXXX()`, `isAvailableXXX()`, `hasActiveXXX()`…).
  verification('Vérification'),

  /// Recherche métier (`findByStatusXXX()`, `findByXXXAndYYY()`, `findByXXXOrYYY()`…).
  search('Recherche métier'),

  /// Pagination métier (`findPaginatedXXX()`, `findRecentXXX()`, `findByPeriodXXX()`, `findTopXXX()`).
  pagination('Pagination métier'),

  /// Agrégats (`loadAggregateXXX()`, `findAggregateByXXX()`, `saveAggregateXXX()`, `findChildrenByXXX()`).
  aggregate('Agrégats'),

  /// Transaction métier (`reserveXXX()`, `lockXXX()`, `unlockXXX()`, `commitReserveXXX()`).
  transaction('Transaction métier'),

  /// Statistiques (`countXXX()`, `countByXXX()`, `countForPeriod()`).
  statistics('Statistiques'),

  /// Batch (`saveAllXXX()`).
  batch('Batch'),

  /// Contrainte d'unicité pure (avec ou sans méthode associée).
  uniquenessRule('Contrainte d’unicité'),

  /// Index de recherche (avec ou sans méthode associée).
  searchIndexRule('Index de recherche'),

  /// Autre règle transverse de persistance ou transactionnelle.
  persistenceRule('Règle de persistance');

  const PersistenceBehaviorCategory(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise une catégorie depuis son identifiant ou un libellé libre.
  static PersistenceBehaviorCategory fromJson(
    Object? raw, {
    bool hasMethod = true,
  }) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in PersistenceBehaviorCategory.values) {
        if (value.name.toLowerCase() == norm ||
            value.label.toLowerCase() == norm) {
          return value;
        }
      }
      if (norm.contains('crud')) return crud;
      if (norm.contains('verif') || norm.contains('vérif')) {
        return verification;
      }
      if (norm.contains('pagin')) return pagination;
      if (norm.contains('agreg') ||
          norm.contains('agrég') ||
          norm.contains('aggreg')) {
        return aggregate;
      }
      if (norm.contains('transac') ||
          norm.contains('lock') ||
          norm.contains('reserv')) {
        return transaction;
      }
      if (norm.contains('stat') || norm.contains('count')) return statistics;
      if (norm.contains('batch')) return batch;
      if (norm.contains('unic') || norm.contains('unique')) {
        return uniquenessRule;
      }
      if (norm.contains('index')) return searchIndexRule;
      if (norm.contains('rech') || norm.contains('search')) return search;
      if (norm.contains('rule') ||
          norm.contains('regle') ||
          norm.contains('règle')) {
        return persistenceRule;
      }
    }
    return hasMethod ? crud : persistenceRule;
  }
}

/// Invariant métier garantissant la validité permanente de l'objet (`invariant_behaviors`).
@immutable
class DomainInvariantSpec {
  /// Crée un invariant immuable.
  DomainInvariantSpec({
    required this.id,
    this.code = '',
    required this.title,
    this.methodSignature = '',
    this.expression = '',
    List<String> rules = const <String>[],
    List<String> associatedMethods = const <String>[],
    List<String> relatedAttributes = const <String>[],
    this.violationError = '',
    this.description = '',
  }) : rules = List<String>.unmodifiable(rules),
       associatedMethods = List<String>.unmodifiable(associatedMethods),
       relatedAttributes = List<String>.unmodifiable(relatedAttributes);

  /// Identifiant technique stable.
  final String id;

  /// Code court optionnel de l'invariant (ex. `INV-01`).
  final String code;

  /// Titre en français affiché dans l'item.
  final String title;

  /// Signature unitaire (compatibilité ; préférer [associatedMethods]).
  final String methodSignature;

  /// Expression logique ou condition formelle (ex. `montantHt >= 0`).
  final String expression;

  /// Liste des règles métier associées (`Rules:`).
  final List<String> rules;

  /// Liste des méthodes internes en anglais à coder (`Associated internal methods:`, ex. `validateIdentity(id)`).
  final List<String> associatedMethods;

  /// Noms des attributs existants du modèle impliqués dans l'invariant.
  final List<String> relatedAttributes;

  /// Code ou classe d'erreur du domaine levée en cas de violation.
  final String violationError;

  /// Descriptif métier en français.
  final String description;

  /// Règles effectives affichées sous `Rules:`.
  List<String> get effectiveRules => _dedupStrings([
    ...rules,
    if (expression.trim().isNotEmpty) expression.trim(),
  ]);

  /// Méthodes internes en anglais effectives affichées sous `Associated internal methods:`.
  List<String> get effectiveAssociatedMethods {
    final merged = _dedupStrings([
      ...associatedMethods,
      if (methodSignature.trim().isNotEmpty) methodSignature.trim(),
    ]);
    return merged.isNotEmpty ? merged : const <String>['validateInvariant()'];
  }

  /// Signature anglaise principale.
  String get effectiveMethodSignature => effectiveAssociatedMethods.first;

  /// Vérifie les invariants structurels.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainInvariantSpec.id requis.');
    }
    if (title.trim().isEmpty &&
        code.trim().isEmpty &&
        methodSignature.trim().isEmpty &&
        associatedMethods.isEmpty) {
      throw const FormatException(
        'Un invariant doit avoir un titre en français ou une méthode validateXXX().',
      );
    }
  }

  /// Copie modifiée.
  DomainInvariantSpec copyWith({
    String? id,
    String? code,
    String? title,
    String? methodSignature,
    String? expression,
    List<String>? rules,
    List<String>? associatedMethods,
    List<String>? relatedAttributes,
    String? violationError,
    String? description,
  }) => DomainInvariantSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    title: title ?? this.title,
    methodSignature: methodSignature ?? this.methodSignature,
    expression: expression ?? this.expression,
    rules: rules ?? this.rules,
    associatedMethods: associatedMethods ?? this.associatedMethods,
    relatedAttributes: relatedAttributes ?? this.relatedAttributes,
    violationError: violationError ?? this.violationError,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (code.isNotEmpty) 'code': code,
    'title': title,
    if (methodSignature.isNotEmpty) 'methodSignature': methodSignature,
    if (expression.isNotEmpty) 'expression': expression,
    if (rules.isNotEmpty) 'rules': rules,
    if (associatedMethods.isNotEmpty) 'associatedMethods': associatedMethods,
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
    final rawTitle =
        ((raw['title'] ?? raw['titleFr']) as String?)?.trim() ?? '';
    final rawMethod =
        ((raw['methodSignature'] ?? raw['method'] ?? raw['methodDetail'])
                as String?)
            ?.trim() ??
        '';
    final parsedMethods = _parseAssociatedMethods(raw);
    final effectiveTitle = rawTitle.isNotEmpty
        ? rawTitle
        : (rawCode.isNotEmpty
              ? rawCode
              : (rawMethod.isNotEmpty
                    ? rawMethod
                    : (parsedMethods.isNotEmpty ? parsedMethods.first : '')));
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainInvariantSpec(
      id: rawId.isEmpty
          ? 'inv_${(rawCode + effectiveTitle + rawMethod + parsedMethods.join(',')).hashCode.abs()}'
          : rawId,
      code: rawCode,
      title: effectiveTitle.isEmpty ? 'Contrôle invariant' : effectiveTitle,
      methodSignature: rawMethod,
      expression: (raw['expression'] as String?)?.trim() ?? '',
      rules: _cleanStringList(raw['rules']),
      associatedMethods: parsedMethods,
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
          other.methodSignature == methodSignature &&
          other.expression == expression &&
          listEquals(other.rules, rules) &&
          listEquals(other.associatedMethods, associatedMethods) &&
          listEquals(other.relatedAttributes, relatedAttributes) &&
          other.violationError == violationError &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    title,
    methodSignature,
    expression,
    Object.hashAll(rules),
    Object.hashAll(associatedMethods),
    Object.hashAll(relatedAttributes),
    violationError,
    description,
  );
}

/// Comportement / commande métier modifiant l'état de l'objet (`state_changing_behaviors`).
@immutable
class DomainStateChangeSpec {
  /// Crée une méthode de mutation d'état immuable.
  DomainStateChangeSpec({
    required this.id,
    required this.name,
    this.title = '',
    this.methodSignature = '',
    this.stateChangeRule = '',
    List<String> rules = const <String>[],
    List<String> associatedMethods = const <String>[],
    List<String> parameters = const <String>[],
    List<String> preconditions = const <String>[],
    List<String> mutations = const <String>[],
    List<String> fromStates = const <String>[],
    this.toState = '',
    List<String> emittedEvents = const <String>[],
    List<String> domainErrors = const <String>[],
    List<String> relatedAttributes = const <String>[],
    this.description = '',
  }) : rules = List<String>.unmodifiable(rules),
       associatedMethods = List<String>.unmodifiable(associatedMethods),
       parameters = List<String>.unmodifiable(parameters),
       preconditions = List<String>.unmodifiable(preconditions),
       mutations = List<String>.unmodifiable(mutations),
       fromStates = List<String>.unmodifiable(fromStates),
       emittedEvents = List<String>.unmodifiable(emittedEvents),
       domainErrors = List<String>.unmodifiable(domainErrors),
       relatedAttributes = List<String>.unmodifiable(relatedAttributes);

  /// Identifiant technique stable.
  final String id;

  /// Nom technique de la méthode (ex. `confirmOrder`).
  final String name;

  /// Titre en français affiché dans l'item.
  final String title;

  /// Signature unitaire (compatibilité ; préférer [associatedMethods]).
  final String methodSignature;

  /// Règle explicite de changement d'état (ex. `BROUILLON -> CONFIRMEE si montantHt > 0`).
  final String stateChangeRule;

  /// Liste des règles métier associées (`Rules:`).
  final List<String> rules;

  /// Liste des méthodes internes en anglais à coder (`Associated internal methods:`).
  final List<String> associatedMethods;

  /// Paramètres d'entrée typés.
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

  /// Attributs existants du modèle lus ou modifiés par cette méthode.
  final List<String> relatedAttributes;

  /// Descriptif métier en français.
  final String description;

  /// Titre français effectif affiché dans l'en-tête.
  String get effectiveTitle => title.trim().isNotEmpty ? title.trim() : name;

  /// Règle de changement d'état effective.
  String get effectiveStateChangeRule {
    if (stateChangeRule.trim().isNotEmpty) return stateChangeRule.trim();
    if (fromStates.isNotEmpty || toState.isNotEmpty) {
      final left = fromStates.isEmpty ? '*' : fromStates.join(' | ');
      final right = toState.isEmpty ? '*' : toState;
      return '$left → $right';
    }
    return '';
  }

  /// Règles effectives affichées sous `Rules:`.
  List<String> get effectiveRules => _dedupStrings([
    if (effectiveStateChangeRule.isNotEmpty) effectiveStateChangeRule,
    ...rules,
    ...preconditions,
    ...mutations,
  ]);

  /// Méthodes internes en anglais effectives affichées sous `Associated internal methods:`.
  List<String> get effectiveAssociatedMethods {
    final merged = _dedupStrings([
      ...associatedMethods,
      if (methodSignature.trim().isNotEmpty) methodSignature.trim(),
    ]);
    return merged.isNotEmpty
        ? merged
        : <String>['$name(${parameters.join(', ')})'];
  }

  /// Signature anglaise principale.
  String get effectiveMethodSignature => effectiveAssociatedMethods.first;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainStateChangeSpec.id requis.');
    }
    if (name.trim().isEmpty &&
        title.trim().isEmpty &&
        methodSignature.trim().isEmpty &&
        associatedMethods.isEmpty) {
      throw const FormatException('DomainStateChangeSpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainStateChangeSpec copyWith({
    String? id,
    String? name,
    String? title,
    String? methodSignature,
    String? stateChangeRule,
    List<String>? rules,
    List<String>? associatedMethods,
    List<String>? parameters,
    List<String>? preconditions,
    List<String>? mutations,
    List<String>? fromStates,
    String? toState,
    List<String>? emittedEvents,
    List<String>? domainErrors,
    List<String>? relatedAttributes,
    String? description,
  }) => DomainStateChangeSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    title: title ?? this.title,
    methodSignature: methodSignature ?? this.methodSignature,
    stateChangeRule: stateChangeRule ?? this.stateChangeRule,
    rules: rules ?? this.rules,
    associatedMethods: associatedMethods ?? this.associatedMethods,
    parameters: parameters ?? this.parameters,
    preconditions: preconditions ?? this.preconditions,
    mutations: mutations ?? this.mutations,
    fromStates: fromStates ?? this.fromStates,
    toState: toState ?? this.toState,
    emittedEvents: emittedEvents ?? this.emittedEvents,
    domainErrors: domainErrors ?? this.domainErrors,
    relatedAttributes: relatedAttributes ?? this.relatedAttributes,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (title.isNotEmpty) 'title': title,
    if (methodSignature.isNotEmpty) 'methodSignature': methodSignature,
    if (stateChangeRule.isNotEmpty) 'stateChangeRule': stateChangeRule,
    if (rules.isNotEmpty) 'rules': rules,
    if (associatedMethods.isNotEmpty) 'associatedMethods': associatedMethods,
    if (parameters.isNotEmpty) 'parameters': parameters,
    if (preconditions.isNotEmpty) 'preconditions': preconditions,
    if (mutations.isNotEmpty) 'mutations': mutations,
    if (fromStates.isNotEmpty) 'fromStates': fromStates,
    if (toState.isNotEmpty) 'toState': toState,
    if (emittedEvents.isNotEmpty) 'emittedEvents': emittedEvents,
    if (domainErrors.isNotEmpty) 'domainErrors': domainErrors,
    if (relatedAttributes.isNotEmpty) 'relatedAttributes': relatedAttributes,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainStateChangeSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainStateChangeSpec invalide.');
    }
    final rawMethod =
        ((raw['methodSignature'] ?? raw['method'] ?? raw['methodDetail'])
                as String?)
            ?.trim() ??
        '';
    final parsedMethods = _parseAssociatedMethods(raw);
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final primaryMethod = rawMethod.isNotEmpty
        ? rawMethod
        : (parsedMethods.isNotEmpty ? parsedMethods.first : '');
    final inferredName = rawName.isNotEmpty
        ? rawName
        : _extractMethodIdentifier(primaryMethod, fallback: 'applyStateChange');
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainStateChangeSpec(
      id: rawId.isEmpty ? 'cmd_${inferredName.hashCode.abs()}' : rawId,
      name: inferredName,
      title: ((raw['title'] ?? raw['titleFr']) as String?)?.trim() ?? '',
      methodSignature: rawMethod,
      stateChangeRule:
          ((raw['stateChangeRule'] ?? raw['rule']) as String?)?.trim() ?? '',
      rules: _cleanStringList(raw['rules']),
      associatedMethods: parsedMethods,
      parameters: _cleanStringList(raw['parameters']),
      preconditions: _cleanStringList(raw['preconditions']),
      mutations: _cleanStringList(raw['mutations']),
      fromStates: _cleanStringList(raw['fromStates']),
      toState: (raw['toState'] as String?)?.trim() ?? '',
      emittedEvents: _cleanStringList(raw['emittedEvents']),
      domainErrors: _cleanStringList(raw['domainErrors']),
      relatedAttributes: _cleanStringList(raw['relatedAttributes']),
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
          other.title == title &&
          other.methodSignature == methodSignature &&
          other.stateChangeRule == stateChangeRule &&
          listEquals(other.rules, rules) &&
          listEquals(other.associatedMethods, associatedMethods) &&
          listEquals(other.parameters, parameters) &&
          listEquals(other.preconditions, preconditions) &&
          listEquals(other.mutations, mutations) &&
          listEquals(other.fromStates, fromStates) &&
          other.toState == toState &&
          listEquals(other.emittedEvents, emittedEvents) &&
          listEquals(other.domainErrors, domainErrors) &&
          listEquals(other.relatedAttributes, relatedAttributes) &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    title,
    methodSignature,
    stateChangeRule,
    Object.hashAll(rules),
    Object.hashAll(associatedMethods),
    Object.hashAll(parameters),
    Object.hashAll(preconditions),
    Object.hashAll(mutations),
    Object.hashAll(fromStates),
    toState,
    Object.hashAll(emittedEvents),
    Object.hashAll(domainErrors),
    Object.hashAll(relatedAttributes),
    description,
  );
}

/// Calcul pur ou méthode de lecture métier sans effet de bord (`query_behaviors`).
@immutable
class DomainQuerySpec {
  /// Crée une query métier immuable.
  DomainQuerySpec({
    required this.id,
    required this.name,
    this.title = '',
    this.methodSignature = '',
    List<String> rules = const <String>[],
    List<String> associatedMethods = const <String>[],
    List<String> parameters = const <String>[],
    this.returnType = 'bool',
    this.formula = '',
    List<String> relatedAttributes = const <String>[],
    this.description = '',
  }) : rules = List<String>.unmodifiable(rules),
       associatedMethods = List<String>.unmodifiable(associatedMethods),
       parameters = List<String>.unmodifiable(parameters),
       relatedAttributes = List<String>.unmodifiable(relatedAttributes);

  /// Identifiant technique stable.
  final String id;

  /// Nom technique de la méthode en anglais (`isXXX`, `canXXX`, `getXXX`, `computeXXX`).
  final String name;

  /// Titre en français affiché dans l'item.
  final String title;

  /// Signature unitaire (compatibilité ; préférer [associatedMethods]).
  final String methodSignature;

  /// Liste des règles / calculs métier (`Rules:`).
  final List<String> rules;

  /// Liste des méthodes internes en anglais à coder (`Associated internal methods:`).
  final List<String> associatedMethods;

  /// Paramètres éventuels.
  final List<String> parameters;

  /// Type retourné (ex. `number`, `bool`, `Decimal`).
  final String returnType;

  /// Formule ou règle de calcul pure.
  final String formula;

  /// Attributs existants du modèle lus par cette query.
  final List<String> relatedAttributes;

  /// Descriptif métier en français.
  final String description;

  /// Titre français effectif affiché dans l'en-tête.
  String get effectiveTitle => title.trim().isNotEmpty ? title.trim() : name;

  /// Règles effectives affichées sous `Rules:`.
  List<String> get effectiveRules => _dedupStrings([
    ...rules,
    if (formula.trim().isNotEmpty) formula.trim(),
  ]);

  /// Méthodes internes en anglais effectives affichées sous `Associated internal methods:`.
  List<String> get effectiveAssociatedMethods {
    final merged = _dedupStrings([
      ...associatedMethods,
      if (methodSignature.trim().isNotEmpty) methodSignature.trim(),
    ]);
    return merged.isNotEmpty
        ? merged
        : <String>['$name(${parameters.join(', ')}): $returnType'];
  }

  /// Signature anglaise principale.
  String get effectiveMethodSignature => effectiveAssociatedMethods.first;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainQuerySpec.id requis.');
    }
    if (name.trim().isEmpty &&
        title.trim().isEmpty &&
        methodSignature.trim().isEmpty &&
        associatedMethods.isEmpty) {
      throw const FormatException('DomainQuerySpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainQuerySpec copyWith({
    String? id,
    String? name,
    String? title,
    String? methodSignature,
    List<String>? rules,
    List<String>? associatedMethods,
    List<String>? parameters,
    String? returnType,
    String? formula,
    List<String>? relatedAttributes,
    String? description,
  }) => DomainQuerySpec(
    id: id ?? this.id,
    name: name ?? this.name,
    title: title ?? this.title,
    methodSignature: methodSignature ?? this.methodSignature,
    rules: rules ?? this.rules,
    associatedMethods: associatedMethods ?? this.associatedMethods,
    parameters: parameters ?? this.parameters,
    returnType: returnType ?? this.returnType,
    formula: formula ?? this.formula,
    relatedAttributes: relatedAttributes ?? this.relatedAttributes,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (title.isNotEmpty) 'title': title,
    if (methodSignature.isNotEmpty) 'methodSignature': methodSignature,
    if (rules.isNotEmpty) 'rules': rules,
    if (associatedMethods.isNotEmpty) 'associatedMethods': associatedMethods,
    if (parameters.isNotEmpty) 'parameters': parameters,
    'returnType': returnType,
    if (formula.isNotEmpty) 'formula': formula,
    if (relatedAttributes.isNotEmpty) 'relatedAttributes': relatedAttributes,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainQuerySpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainQuerySpec invalide.');
    }
    final rawMethod =
        ((raw['methodSignature'] ?? raw['method'] ?? raw['methodDetail'])
                as String?)
            ?.trim() ??
        '';
    final parsedMethods = _parseAssociatedMethods(raw);
    final primaryMethod = rawMethod.isNotEmpty
        ? rawMethod
        : (parsedMethods.isNotEmpty ? parsedMethods.first : '');
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isNotEmpty
        ? rawName
        : _extractMethodIdentifier(primaryMethod, fallback: 'isEligible');
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawReturn = (raw['returnType'] as String?)?.trim() ?? '';
    final item = DomainQuerySpec(
      id: rawId.isEmpty ? 'qry_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      title: ((raw['title'] ?? raw['titleFr']) as String?)?.trim() ?? '',
      methodSignature: rawMethod,
      rules: _cleanStringList(raw['rules']),
      associatedMethods: parsedMethods,
      parameters: _cleanStringList(raw['parameters']),
      returnType: rawReturn.isEmpty ? 'bool' : rawReturn,
      formula: (raw['formula'] as String?)?.trim() ?? '',
      relatedAttributes: _cleanStringList(raw['relatedAttributes']),
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
          other.title == title &&
          other.methodSignature == methodSignature &&
          listEquals(other.rules, rules) &&
          listEquals(other.associatedMethods, associatedMethods) &&
          listEquals(other.parameters, parameters) &&
          other.returnType == returnType &&
          other.formula == formula &&
          listEquals(other.relatedAttributes, relatedAttributes) &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    title,
    methodSignature,
    Object.hashAll(rules),
    Object.hashAll(associatedMethods),
    Object.hashAll(parameters),
    returnType,
    formula,
    Object.hashAll(relatedAttributes),
    description,
  );
}

/// Service du domaine ou politique métier sans état (`policy_service_behaviors`).
@immutable
class DomainPolicyServiceSpec {
  /// Crée une policy / service du domaine immuable.
  DomainPolicyServiceSpec({
    required this.id,
    required this.name,
    this.title = '',
    this.methodSignature = '',
    this.operation = '',
    List<String> collaborators = const <String>[],
    List<String> rules = const <String>[],
    List<String> associatedMethods = const <String>[],
    List<String> relatedAttributes = const <String>[],
    this.description = '',
  }) : collaborators = List<String>.unmodifiable(collaborators),
       rules = List<String>.unmodifiable(rules),
       associatedMethods = List<String>.unmodifiable(associatedMethods),
       relatedAttributes = List<String>.unmodifiable(relatedAttributes);

  /// Identifiant technique stable.
  final String id;

  /// Nom du service ou de la méthode de policy (en anglais).
  final String name;

  /// Titre en français affiché dans l'item.
  final String title;

  /// Signature unitaire (compatibilité ; préférer [associatedMethods]).
  final String methodSignature;

  /// Opération ou signature principale exposée (alias historique de [methodSignature]).
  final String operation;

  /// Autres objets du domaine ou ports impliqués.
  final List<String> collaborators;

  /// Règles complexes appliquées à l'agrégat ou inter-agrégats (`Rules:`).
  final List<String> rules;

  /// Liste des méthodes internes en anglais à coder (`Associated internal methods:`).
  final List<String> associatedMethods;

  /// Attributs existants du modèle consultés par cette policy.
  final List<String> relatedAttributes;

  /// Descriptif métier en français.
  final String description;

  /// Titre français effectif affiché dans l'en-tête.
  String get effectiveTitle => title.trim().isNotEmpty ? title.trim() : name;

  /// Règles effectives affichées sous `Rules:`.
  List<String> get effectiveRules => rules;

  /// Méthodes internes en anglais effectives affichées sous `Associated internal methods:`.
  List<String> get effectiveAssociatedMethods {
    final merged = _dedupStrings([
      ...associatedMethods,
      if (methodSignature.trim().isNotEmpty) methodSignature.trim(),
      if (operation.trim().isNotEmpty) operation.trim(),
    ]);
    return merged.isNotEmpty ? merged : <String>['$name()'];
  }

  /// Signature anglaise principale.
  String get effectiveMethodSignature => effectiveAssociatedMethods.first;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainPolicyServiceSpec.id requis.');
    }
    if (name.trim().isEmpty &&
        title.trim().isEmpty &&
        methodSignature.trim().isEmpty &&
        operation.trim().isEmpty &&
        associatedMethods.isEmpty) {
      throw const FormatException('DomainPolicyServiceSpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainPolicyServiceSpec copyWith({
    String? id,
    String? name,
    String? title,
    String? methodSignature,
    String? operation,
    List<String>? collaborators,
    List<String>? rules,
    List<String>? associatedMethods,
    List<String>? relatedAttributes,
    String? description,
  }) => DomainPolicyServiceSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    title: title ?? this.title,
    methodSignature: methodSignature ?? this.methodSignature,
    operation: operation ?? this.operation,
    collaborators: collaborators ?? this.collaborators,
    rules: rules ?? this.rules,
    associatedMethods: associatedMethods ?? this.associatedMethods,
    relatedAttributes: relatedAttributes ?? this.relatedAttributes,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (title.isNotEmpty) 'title': title,
    if (methodSignature.isNotEmpty) 'methodSignature': methodSignature,
    if (operation.isNotEmpty) 'operation': operation,
    if (collaborators.isNotEmpty) 'collaborators': collaborators,
    if (rules.isNotEmpty) 'rules': rules,
    if (associatedMethods.isNotEmpty) 'associatedMethods': associatedMethods,
    if (relatedAttributes.isNotEmpty) 'relatedAttributes': relatedAttributes,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainPolicyServiceSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainPolicyServiceSpec invalide.');
    }
    final rawOperation = (raw['operation'] as String?)?.trim() ?? '';
    final rawMethod =
        ((raw['methodSignature'] ?? raw['method'] ?? raw['methodDetail'])
                as String?)
            ?.trim() ??
        '';
    final parsedMethods = _parseAssociatedMethods(raw);
    final primaryMethod = rawMethod.isNotEmpty
        ? rawMethod
        : (parsedMethods.isNotEmpty ? parsedMethods.first : rawOperation);
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isNotEmpty
        ? rawName
        : _extractMethodIdentifier(primaryMethod, fallback: 'DomainPolicy');
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainPolicyServiceSpec(
      id: rawId.isEmpty ? 'pol_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      title: ((raw['title'] ?? raw['titleFr']) as String?)?.trim() ?? '',
      methodSignature: rawMethod,
      operation: rawOperation,
      collaborators: _cleanStringList(raw['collaborators']),
      rules: _cleanStringList(raw['rules']),
      associatedMethods: parsedMethods,
      relatedAttributes: _cleanStringList(raw['relatedAttributes']),
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
          other.title == title &&
          other.methodSignature == methodSignature &&
          other.operation == operation &&
          listEquals(other.collaborators, collaborators) &&
          listEquals(other.rules, rules) &&
          listEquals(other.associatedMethods, associatedMethods) &&
          listEquals(other.relatedAttributes, relatedAttributes) &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    title,
    methodSignature,
    operation,
    Object.hashAll(collaborators),
    Object.hashAll(rules),
    Object.hashAll(associatedMethods),
    Object.hashAll(relatedAttributes),
    description,
  );
}

/// Fabrique métier d'instanciation ou de reconstitution (`factory_behaviors`).
@immutable
class DomainFactorySpec {
  /// Crée une fabrique métier immuable.
  DomainFactorySpec({
    required this.id,
    required this.name,
    this.title = '',
    this.methodSignature = '',
    List<String> rules = const <String>[],
    List<String> associatedMethods = const <String>[],
    List<String> parameters = const <String>[],
    this.initialState = '',
    List<String> enforcedInvariants = const <String>[],
    List<String> emittedEvents = const <String>[],
    List<String> relatedAttributes = const <String>[],
    this.description = '',
  }) : rules = List<String>.unmodifiable(rules),
       associatedMethods = List<String>.unmodifiable(associatedMethods),
       parameters = List<String>.unmodifiable(parameters),
       enforcedInvariants = List<String>.unmodifiable(enforcedInvariants),
       emittedEvents = List<String>.unmodifiable(emittedEvents),
       relatedAttributes = List<String>.unmodifiable(relatedAttributes);

  /// Identifiant technique stable.
  final String id;

  /// Nom technique de la fabrique en anglais (`createXXX`, `fromSnapshot`).
  final String name;

  /// Titre en français affiché dans l'item.
  final String title;

  /// Signature unitaire (compatibilité ; préférer [associatedMethods]).
  final String methodSignature;

  /// Liste des règles d'instanciation (`Rules:`).
  final List<String> rules;

  /// Liste des méthodes internes en anglais à coder (`Associated internal methods:`).
  final List<String> associatedMethods;

  /// Paramètres requis à la création.
  final List<String> parameters;

  /// État initial assigné à l'instance créée.
  final String initialState;

  /// Codes ou titres des invariants garantis dès la construction.
  final List<String> enforcedInvariants;

  /// Événements du domaine émis à la création.
  final List<String> emittedEvents;

  /// Attributs existants du modèle initialisés par la fabrique.
  final List<String> relatedAttributes;

  /// Descriptif métier en français.
  final String description;

  /// Titre français effectif affiché dans l'en-tête.
  String get effectiveTitle => title.trim().isNotEmpty ? title.trim() : name;

  /// Règles effectives affichées sous `Rules:`.
  List<String> get effectiveRules => _dedupStrings([
    ...rules,
    if (initialState.trim().isNotEmpty) 'État initial : ${initialState.trim()}',
  ]);

  /// Méthodes internes en anglais effectives affichées sous `Associated internal methods:`.
  List<String> get effectiveAssociatedMethods {
    final merged = _dedupStrings([
      ...associatedMethods,
      if (methodSignature.trim().isNotEmpty) methodSignature.trim(),
    ]);
    return merged.isNotEmpty
        ? merged
        : <String>['$name(${parameters.join(', ')})'];
  }

  /// Signature anglaise principale.
  String get effectiveMethodSignature => effectiveAssociatedMethods.first;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainFactorySpec.id requis.');
    }
    if (name.trim().isEmpty &&
        title.trim().isEmpty &&
        methodSignature.trim().isEmpty &&
        associatedMethods.isEmpty) {
      throw const FormatException('DomainFactorySpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainFactorySpec copyWith({
    String? id,
    String? name,
    String? title,
    String? methodSignature,
    List<String>? rules,
    List<String>? associatedMethods,
    List<String>? parameters,
    String? initialState,
    List<String>? enforcedInvariants,
    List<String>? emittedEvents,
    List<String>? relatedAttributes,
    String? description,
  }) => DomainFactorySpec(
    id: id ?? this.id,
    name: name ?? this.name,
    title: title ?? this.title,
    methodSignature: methodSignature ?? this.methodSignature,
    rules: rules ?? this.rules,
    associatedMethods: associatedMethods ?? this.associatedMethods,
    parameters: parameters ?? this.parameters,
    initialState: initialState ?? this.initialState,
    enforcedInvariants: enforcedInvariants ?? this.enforcedInvariants,
    emittedEvents: emittedEvents ?? this.emittedEvents,
    relatedAttributes: relatedAttributes ?? this.relatedAttributes,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (title.isNotEmpty) 'title': title,
    if (methodSignature.isNotEmpty) 'methodSignature': methodSignature,
    if (rules.isNotEmpty) 'rules': rules,
    if (associatedMethods.isNotEmpty) 'associatedMethods': associatedMethods,
    if (parameters.isNotEmpty) 'parameters': parameters,
    if (initialState.isNotEmpty) 'initialState': initialState,
    if (enforcedInvariants.isNotEmpty) 'enforcedInvariants': enforcedInvariants,
    if (emittedEvents.isNotEmpty) 'emittedEvents': emittedEvents,
    if (relatedAttributes.isNotEmpty) 'relatedAttributes': relatedAttributes,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainFactorySpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainFactorySpec invalide.');
    }
    final rawMethod =
        ((raw['methodSignature'] ?? raw['method'] ?? raw['methodDetail'])
                as String?)
            ?.trim() ??
        '';
    final parsedMethods = _parseAssociatedMethods(raw);
    final primaryMethod = rawMethod.isNotEmpty
        ? rawMethod
        : (parsedMethods.isNotEmpty ? parsedMethods.first : '');
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isNotEmpty
        ? rawName
        : _extractMethodIdentifier(primaryMethod, fallback: 'createEntity');
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainFactorySpec(
      id: rawId.isEmpty ? 'fac_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      title: ((raw['title'] ?? raw['titleFr']) as String?)?.trim() ?? '',
      methodSignature: rawMethod,
      rules: _cleanStringList(raw['rules']),
      associatedMethods: parsedMethods,
      parameters: _cleanStringList(raw['parameters']),
      initialState: (raw['initialState'] as String?)?.trim() ?? '',
      enforcedInvariants: _cleanStringList(raw['enforcedInvariants']),
      emittedEvents: _cleanStringList(raw['emittedEvents']),
      relatedAttributes: _cleanStringList(raw['relatedAttributes']),
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
          other.title == title &&
          other.methodSignature == methodSignature &&
          listEquals(other.rules, rules) &&
          listEquals(other.associatedMethods, associatedMethods) &&
          listEquals(other.parameters, parameters) &&
          other.initialState == initialState &&
          listEquals(other.enforcedInvariants, enforcedInvariants) &&
          listEquals(other.emittedEvents, emittedEvents) &&
          listEquals(other.relatedAttributes, relatedAttributes) &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    title,
    methodSignature,
    Object.hashAll(rules),
    Object.hashAll(associatedMethods),
    Object.hashAll(parameters),
    initialState,
    Object.hashAll(enforcedInvariants),
    Object.hashAll(emittedEvents),
    Object.hashAll(relatedAttributes),
    description,
  );
}

/// Comportement de publication ou de réaction aux événements du domaine (`domain_event_behaviors`).
@immutable
class DomainEventSpec {
  /// Crée un comportement d'événement du domaine immuable.
  DomainEventSpec({
    required this.id,
    required this.name,
    this.title = '',
    this.methodSignature = '',
    List<String> rules = const <String>[],
    List<String> associatedMethods = const <String>[],
    this.trigger = '',
    List<String> payloadFields = const <String>[],
    this.contractEntryRef = '',
    List<String> relatedAttributes = const <String>[],
    this.description = '',
  }) : rules = List<String>.unmodifiable(rules),
       associatedMethods = List<String>.unmodifiable(associatedMethods),
       payloadFields = List<String>.unmodifiable(payloadFields),
       relatedAttributes = List<String>.unmodifiable(relatedAttributes);

  /// Identifiant technique stable.
  final String id;

  /// Nom technique de l'événement ou de la méthode (`publishXXX`, `onXXX`).
  final String name;

  /// Titre en français affiché dans l'item.
  final String title;

  /// Signature unitaire (compatibilité ; préférer [associatedMethods]).
  final String methodSignature;

  /// Liste des règles de publication ou de réaction (`Rules:`).
  final List<String> rules;

  /// Liste des méthodes internes en anglais à coder (`Associated internal methods:`).
  final List<String> associatedMethods;

  /// Action *State changing* ou *Factory* à l'origine de l'émission.
  final String trigger;

  /// Attributs existants du modèle portés par la charge utile de l'événement.
  final List<String> payloadFields;

  /// Nom technique ou ID optionnel d'une entrée `eventxpayloaddto` du domaine.
  final String contractEntryRef;

  /// Attributs existants du modèle impliqués.
  final List<String> relatedAttributes;

  /// Descriptif métier en français.
  final String description;

  /// Titre français effectif affiché dans l'en-tête.
  String get effectiveTitle => title.trim().isNotEmpty ? title.trim() : name;

  /// Règles effectives affichées sous `Rules:`.
  List<String> get effectiveRules => _dedupStrings([
    ...rules,
    if (payloadFields.isNotEmpty) 'Payload : ${payloadFields.join(', ')}',
  ]);

  /// Méthodes internes en anglais effectives affichées sous `Associated internal methods:`.
  List<String> get effectiveAssociatedMethods {
    final merged = _dedupStrings([
      ...associatedMethods,
      if (methodSignature.trim().isNotEmpty) methodSignature.trim(),
    ]);
    if (merged.isNotEmpty) return merged;
    if (name.startsWith('publish') || name.startsWith('on')) {
      return <String>['$name(${payloadFields.join(', ')})'];
    }
    return <String>['publish$name(${payloadFields.join(', ')})'];
  }

  /// Signature anglaise principale.
  String get effectiveMethodSignature => effectiveAssociatedMethods.first;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainEventSpec.id requis.');
    }
    if (name.trim().isEmpty &&
        title.trim().isEmpty &&
        methodSignature.trim().isEmpty &&
        associatedMethods.isEmpty) {
      throw const FormatException('DomainEventSpec.name requis.');
    }
  }

  /// Copie modifiée.
  DomainEventSpec copyWith({
    String? id,
    String? name,
    String? title,
    String? methodSignature,
    List<String>? rules,
    List<String>? associatedMethods,
    String? trigger,
    List<String>? payloadFields,
    String? contractEntryRef,
    List<String>? relatedAttributes,
    String? description,
  }) => DomainEventSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    title: title ?? this.title,
    methodSignature: methodSignature ?? this.methodSignature,
    rules: rules ?? this.rules,
    associatedMethods: associatedMethods ?? this.associatedMethods,
    trigger: trigger ?? this.trigger,
    payloadFields: payloadFields ?? this.payloadFields,
    contractEntryRef: contractEntryRef ?? this.contractEntryRef,
    relatedAttributes: relatedAttributes ?? this.relatedAttributes,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (title.isNotEmpty) 'title': title,
    if (methodSignature.isNotEmpty) 'methodSignature': methodSignature,
    if (rules.isNotEmpty) 'rules': rules,
    if (associatedMethods.isNotEmpty) 'associatedMethods': associatedMethods,
    if (trigger.isNotEmpty) 'trigger': trigger,
    if (payloadFields.isNotEmpty) 'payloadFields': payloadFields,
    if (contractEntryRef.isNotEmpty) 'contractEntryRef': contractEntryRef,
    if (relatedAttributes.isNotEmpty) 'relatedAttributes': relatedAttributes,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainEventSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainEventSpec invalide.');
    }
    final rawMethod =
        ((raw['methodSignature'] ?? raw['method'] ?? raw['methodDetail'])
                as String?)
            ?.trim() ??
        '';
    final parsedMethods = _parseAssociatedMethods(raw);
    final primaryMethod = rawMethod.isNotEmpty
        ? rawMethod
        : (parsedMethods.isNotEmpty ? parsedMethods.first : '');
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final effectiveName = rawName.isNotEmpty
        ? rawName
        : _extractMethodIdentifier(primaryMethod, fallback: 'publishDomainEvent');
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainEventSpec(
      id: rawId.isEmpty ? 'evt_${effectiveName.hashCode.abs()}' : rawId,
      name: effectiveName,
      title: ((raw['title'] ?? raw['titleFr']) as String?)?.trim() ?? '',
      methodSignature: rawMethod,
      rules: _cleanStringList(raw['rules']),
      associatedMethods: parsedMethods,
      trigger: (raw['trigger'] as String?)?.trim() ?? '',
      payloadFields: _cleanStringList(raw['payloadFields']),
      contractEntryRef: (raw['contractEntryRef'] as String?)?.trim() ?? '',
      relatedAttributes: _cleanStringList(raw['relatedAttributes']),
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
          other.title == title &&
          other.methodSignature == methodSignature &&
          listEquals(other.rules, rules) &&
          listEquals(other.associatedMethods, associatedMethods) &&
          other.trigger == trigger &&
          listEquals(other.payloadFields, payloadFields) &&
          other.contractEntryRef == contractEntryRef &&
          listEquals(other.relatedAttributes, relatedAttributes) &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    title,
    methodSignature,
    Object.hashAll(rules),
    Object.hashAll(associatedMethods),
    trigger,
    Object.hashAll(payloadFields),
    contractEntryRef,
    Object.hashAll(relatedAttributes),
    description,
  );
}

/// Comportement de persistance ou règle d'unicité/d'index sur le port Repository
/// (`persistence_policy_behaviors`).
///
/// Peut représenter soit un groupe de méthodes du port (`saveXXX()`, `findByXXX()`,
/// `isUniqueByXXX()`, `findPaginatedXXX()`, etc.) soit une règle pure de
/// persistance **sans méthode associée** (contrainte d'unicité, index de
/// recherche, règle transactionnelle).
@immutable
class DomainRepositoryMethodSpec {
  /// Crée un comportement ou une règle de persistance immuable.
  DomainRepositoryMethodSpec({
    required this.id,
    this.name = '',
    this.title = '',
    this.methodSignature = '',
    this.signature = '',
    this.category = PersistenceBehaviorCategory.crud,
    List<String> rules = const <String>[],
    List<String> associatedMethods = const <String>[],
    List<String> relatedAttributes = const <String>[],
    this.description = '',
  }) : rules = List<String>.unmodifiable(rules),
       associatedMethods = List<String>.unmodifiable(associatedMethods),
       relatedAttributes = List<String>.unmodifiable(relatedAttributes);

  /// Identifiant technique stable.
  final String id;

  /// Identifiant court de la méthode (vide lorsqu'il s'agit d'une règle sans méthode associée).
  final String name;

  /// Titre en français affiché dans l'item.
  final String title;

  /// Signature unitaire (compatibilité ; préférer [associatedMethods]).
  final String methodSignature;

  /// Signature complémentaire (alias historique de [methodSignature]).
  final String signature;

  /// Catégorie fonctionnelle (`CRUD métier`, `Vérification`, `Recherche métier`, `Index de recherche`, etc.).
  final PersistenceBehaviorCategory category;

  /// Règles explicites associées (`Rules:` : contraintes d'unicité, index de recherche, verrous, transactions).
  final List<String> rules;

  /// Méthodes internes en anglais à coder (`Associated internal methods:`, vide si règle sans méthode associée).
  final List<String> associatedMethods;

  /// Attributs existants du modèle ciblés par cette méthode ou cette règle.
  final List<String> relatedAttributes;

  /// Descriptif métier en français.
  final String description;

  /// Méthodes en anglais effectives affichées sous `Associated internal methods:` (vide si règle pure).
  List<String> get effectiveAssociatedMethods {
    if (associatedMethods.isNotEmpty) return associatedMethods;
    if (methodSignature.trim().isNotEmpty) return <String>[methodSignature.trim()];
    final cleanName = name.trim();
    final cleanSig = signature.trim();
    if (cleanName.isEmpty && cleanSig.isEmpty) return const <String>[];
    if (cleanSig.isEmpty) {
      return <String>[cleanName.contains('(') ? cleanName : '$cleanName()'];
    }
    if (cleanSig.startsWith('(') && cleanName.isNotEmpty) {
      return <String>['$cleanName$cleanSig'];
    }
    return <String>[cleanSig];
  }

  /// Indique si cet élément possède au moins une méthode à coder (sinon il s'agit d'une règle pure).
  bool get hasMethod => effectiveAssociatedMethods.isNotEmpty;

  /// Titre français effectif affiché dans l'en-tête.
  String get effectiveTitle {
    if (title.trim().isNotEmpty) return title.trim();
    if (rules.isNotEmpty) return rules.first;
    return name;
  }

  /// Signature anglaise principale (vide pour une règle sans méthode).
  String get effectiveMethodSignature =>
      effectiveAssociatedMethods.isNotEmpty
          ? effectiveAssociatedMethods.first
          : '';

  /// Règles effectives affichées sous `Rules:`.
  List<String> get effectiveRules => rules;

  /// Clé naturelle utilisée lors de la fusion de patches IA.
  List<String> get naturalMergeKeys => <String>[
    if (name.trim().isNotEmpty) name.trim(),
    if (methodSignature.trim().isNotEmpty) methodSignature.trim(),
    ...associatedMethods,
    if (title.trim().isNotEmpty) title.trim(),
  ];

  /// Vérifie les invariants (autorise les règles sans méthode associée dès lors qu'un titre ou une règle est présent).
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainRepositoryMethodSpec.id requis.');
    }
    if (name.trim().isEmpty &&
        title.trim().isEmpty &&
        methodSignature.trim().isEmpty &&
        associatedMethods.isEmpty &&
        rules.isEmpty) {
      throw const FormatException(
        'Un élément de persistence_policy_behaviors doit avoir un titre, une méthode ou une règle.',
      );
    }
  }

  /// Copie modifiée.
  DomainRepositoryMethodSpec copyWith({
    String? id,
    String? name,
    String? title,
    String? methodSignature,
    String? signature,
    PersistenceBehaviorCategory? category,
    List<String>? rules,
    List<String>? associatedMethods,
    List<String>? relatedAttributes,
    String? description,
  }) => DomainRepositoryMethodSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    title: title ?? this.title,
    methodSignature: methodSignature ?? this.methodSignature,
    signature: signature ?? this.signature,
    category: category ?? this.category,
    rules: rules ?? this.rules,
    associatedMethods: associatedMethods ?? this.associatedMethods,
    relatedAttributes: relatedAttributes ?? this.relatedAttributes,
    description: description ?? this.description,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (name.isNotEmpty) 'name': name,
    if (title.isNotEmpty) 'title': title,
    if (methodSignature.isNotEmpty) 'methodSignature': methodSignature,
    if (signature.isNotEmpty) 'signature': signature,
    'category': category.name,
    if (rules.isNotEmpty) 'rules': rules,
    if (associatedMethods.isNotEmpty) 'associatedMethods': associatedMethods,
    if (relatedAttributes.isNotEmpty) 'relatedAttributes': relatedAttributes,
    if (description.isNotEmpty) 'description': description,
  };

  /// Désérialise depuis JSON.
  factory DomainRepositoryMethodSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainRepositoryMethodSpec invalide.');
    }
    final rawTitle =
        ((raw['title'] ?? raw['titleFr']) as String?)?.trim() ?? '';
    final rawMethod =
        ((raw['methodSignature'] ?? raw['method'] ?? raw['methodDetail'])
                as String?)
            ?.trim() ??
        '';
    final parsedMethods = _parseAssociatedMethods(raw);
    final rawSig = (raw['signature'] as String?)?.trim() ?? '';
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final parsedRules = _cleanStringList(raw['rules']);
    final singleRule = (raw['rule'] as String?)?.trim() ?? '';
    final allRules = <String>[
      ...parsedRules,
      if (singleRule.isNotEmpty && !parsedRules.contains(singleRule))
        singleRule,
    ];
    final primaryMethod = rawMethod.isNotEmpty
        ? rawMethod
        : (parsedMethods.isNotEmpty ? parsedMethods.first : '');
    final effectiveName = rawName.isNotEmpty
        ? rawName
        : (primaryMethod.isNotEmpty
              ? _extractMethodIdentifier(primaryMethod, fallback: '')
              : '');
    final hasAnyMethod =
        effectiveName.isNotEmpty ||
        rawMethod.isNotEmpty ||
        rawSig.isNotEmpty ||
        parsedMethods.isNotEmpty;
    final effectiveTitle = rawTitle.isNotEmpty
        ? rawTitle
        : (!hasAnyMethod && allRules.isNotEmpty ? allRules.first : '');
    final seedForId =
        '$effectiveName|$effectiveTitle|$rawMethod|${parsedMethods.join(',')}|${allRules.join(',')}';
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final item = DomainRepositoryMethodSpec(
      id: rawId.isEmpty ? 'repm_${seedForId.hashCode.abs()}' : rawId,
      name: effectiveName,
      title: effectiveTitle,
      methodSignature: rawMethod,
      signature: rawSig,
      category: PersistenceBehaviorCategory.fromJson(
        raw['category'],
        hasMethod: hasAnyMethod,
      ),
      rules: allRules,
      associatedMethods: parsedMethods,
      relatedAttributes: _cleanStringList(raw['relatedAttributes']),
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
          other.title == title &&
          other.methodSignature == methodSignature &&
          other.signature == signature &&
          other.category == category &&
          listEquals(other.rules, rules) &&
          listEquals(other.associatedMethods, associatedMethods) &&
          listEquals(other.relatedAttributes, relatedAttributes) &&
          other.description == description;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    title,
    methodSignature,
    signature,
    category,
    Object.hashAll(rules),
    Object.hashAll(associatedMethods),
    Object.hashAll(relatedAttributes),
    description,
  );
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
    List<String> rules = const <String>[],
    List<DomainRepositoryMethodSpec> portMethods =
        const <DomainRepositoryMethodSpec>[],
  }) : rules = List<String>.unmodifiable(rules),
       portMethods = List<DomainRepositoryMethodSpec>.unmodifiable(portMethods);

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

  /// Contraintes complémentaires de cohérence ou rétention.
  final String consistencyNotes;

  /// Règles transverses explicites de persistance (contraintes d'unicité, index de recherche, transactions).
  final List<String> rules;

  /// Comportements et règles unitaires de `persistence_policy_behaviors` (avec ou sans méthode associée).
  final List<DomainRepositoryMethodSpec> portMethods;

  /// Vrai si au moins un élément de la politique a été renseigné.
  bool get isConfigured =>
      repositoryPortName.trim().isNotEmpty ||
      aggregateBoundary.trim().isNotEmpty ||
      consistencyNotes.trim().isNotEmpty ||
      rules.isNotEmpty ||
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
    List<String>? rules,
    List<DomainRepositoryMethodSpec>? portMethods,
  }) => DomainPersistencePolicySpec(
    repositoryPortName: repositoryPortName ?? this.repositoryPortName,
    aggregateBoundary: aggregateBoundary ?? this.aggregateBoundary,
    concurrencyStrategy: concurrencyStrategy ?? this.concurrencyStrategy,
    deletionStrategy: deletionStrategy ?? this.deletionStrategy,
    consistencyNotes: consistencyNotes ?? this.consistencyNotes,
    rules: rules ?? this.rules,
    portMethods: portMethods ?? this.portMethods,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    if (repositoryPortName.isNotEmpty) 'repositoryPortName': repositoryPortName,
    if (aggregateBoundary.isNotEmpty) 'aggregateBoundary': aggregateBoundary,
    'concurrencyStrategy': concurrencyStrategy.name,
    'deletionStrategy': deletionStrategy.name,
    if (consistencyNotes.isNotEmpty) 'consistencyNotes': consistencyNotes,
    if (rules.isNotEmpty) 'rules': rules,
    if (portMethods.isNotEmpty)
      'portMethods': [for (final m in portMethods) m.toJson()],
  };

  /// Désérialise depuis JSON.
  factory DomainPersistencePolicySpec.fromJson(Object? raw) {
    if (raw == null) return DomainPersistencePolicySpec.empty;
    if (raw is List) {
      final item = DomainPersistencePolicySpec(
        portMethods: [
          for (final entry in raw) DomainRepositoryMethodSpec.fromJson(entry),
        ],
      );
      item.validate();
      return item;
    }
    if (raw is! Map) {
      throw const FormatException('DomainPersistencePolicySpec invalide.');
    }
    final rawMethods = raw['portMethods'] ?? raw['behaviors'] ?? raw['items'];
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
      rules: _cleanStringList(raw['rules']),
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
          listEquals(other.rules, rules) &&
          listEquals(other.portMethods, portMethods);

  @override
  int get hashCode => Object.hash(
    repositoryPortName,
    aggregateBoundary,
    concurrencyStrategy,
    deletionStrategy,
    consistencyNotes,
    Object.hashAll(rules),
    Object.hashAll(portMethods),
  );
}

String _extractMethodIdentifier(String rawMethod, {required String fallback}) {
  final trimmed = rawMethod.trim();
  if (trimmed.isEmpty) return fallback;
  final openParen = trimmed.indexOf('(');
  final head = (openParen > 0 ? trimmed.substring(0, openParen) : trimmed)
      .trim();
  return head.isEmpty ? fallback : head;
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
       persistencePolicy =
           persistencePolicy ?? DomainPersistencePolicySpec.empty;

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
    final rawInvariants = raw['invariant_behaviors'] ?? raw['invariants'];
    final rawStateChanges =
        raw['state_changing_behaviors'] ?? raw['stateChanges'];
    final rawQueries = raw['query_behaviors'] ?? raw['queries'];
    final rawPolicies =
        raw['policy_service_behaviors'] ?? raw['policyServices'];
    final rawFactories = raw['factory_behaviors'] ?? raw['factories'];
    final rawEvents = raw['domain_event_behaviors'] ?? raw['domainEvents'];
    final rawPersistence =
        raw['persistence_policy_behaviors'] ?? raw['persistencePolicy'];
    final spec = HexagonalDomainLayerSpec(
      invariants: [
        if (rawInvariants is List)
          for (final item in rawInvariants) DomainInvariantSpec.fromJson(item),
      ],
      stateChanges: [
        if (rawStateChanges is List)
          for (final item in rawStateChanges)
            DomainStateChangeSpec.fromJson(item),
      ],
      queries: [
        if (rawQueries is List)
          for (final item in rawQueries) DomainQuerySpec.fromJson(item),
      ],
      policyServices: [
        if (rawPolicies is List)
          for (final item in rawPolicies)
            DomainPolicyServiceSpec.fromJson(item),
      ],
      factories: [
        if (rawFactories is List)
          for (final item in rawFactories) DomainFactorySpec.fromJson(item),
      ],
      domainEvents: [
        if (rawEvents is List)
          for (final item in rawEvents) DomainEventSpec.fromJson(item),
      ],
      persistencePolicy: rawPersistence != null
          ? DomainPersistencePolicySpec.fromJson(rawPersistence)
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
