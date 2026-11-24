/// Modèles immuables de la page « Cas d’usage & orchestration » d'un domaine
/// ([UseCaseOrchestrationSpec]) : cartographie par Bounded Context, Use Cases
/// CQRS détaillés (10 sections + scénarios Given/When/Then) et Sagas Mermaid
/// avec matrice des compensations.
library;

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart'
    show VibeChatAttachment;

import 'domain_contracts.dart';
import 'spec_stage_chat.dart';

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

Map<ContractStage, ContractStatus> _parseContractStates(Object? raw) {
  if (raw is! Map) return const <ContractStage, ContractStatus>{};
  final parsed = <ContractStage, ContractStatus>{};
  for (final e in raw.entries) {
    final stage = ContractStage.values
        .where((s) => s.name == e.key)
        .firstOrNull;
    final status = ContractStatus.values
        .where((s) => s.name == e.value)
        .firstOrNull;
    if (stage != null && status != null) {
      parsed[stage] = status;
    }
  }
  return parsed;
}

/// Les 3 onglets structurant l'atelier « Cas d’usage & orchestration » côté Design.
enum UseCaseOrchestrationTab {
  /// Cartographie des Use Cases et Sagas par Bounded Context.
  cartography(
    label: 'Cartographie',
    subtitle: 'Cartographie des Use Cases et Sagas de la couche applicative par Bounded Context',
  ),

  /// Spécifications détaillées des Use Cases applicatifs CQRS.
  useCases(
    label: 'Use Cases',
    subtitle: 'Spécifications détaillées (10 sections, ports, événements et scénarios Given/When/Then)',
  ),

  /// Sagas orchestrées / chorégraphiées avec diagramme Mermaid et matrice de compensation.
  sagas(
    label: 'Sagas & Compensations',
    subtitle: 'Diagrammes Mermaid et matrices de compensation / rollback des Sagas',
  );

  const UseCaseOrchestrationTab({required this.label, required this.subtitle});

  /// Libellé court affiché dans l'onglet.
  final String label;

  /// Sous-titre explicatif affiché dans le chat et les infobulles.
  final String subtitle;

  /// Résout un onglet depuis son nom JSON ou son libellé.
  static UseCaseOrchestrationTab fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final tab in UseCaseOrchestrationTab.values) {
        if (tab.name.toLowerCase() == norm || tab.label.toLowerCase() == norm) {
          return tab;
        }
      }
    }
    return UseCaseOrchestrationTab.cartography;
  }
}

/// Nature CQRS d'un Use Case de la couche applicative.
enum UseCaseCqrsType {
  /// Commande modifiant l'état d'un agrégat et publiant des événements.
  command('Command'),

  /// Requête en lecture pure sur un Read Model ou une projection.
  query('Query');

  const UseCaseCqrsType(this.label);

  /// Libellé affiché.
  final String label;

  /// Désérialise un type CQRS.
  static UseCaseCqrsType fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      if (norm == 'query' || norm.contains('lecture') || norm == 'q') {
        return UseCaseCqrsType.query;
      }
    }
    return UseCaseCqrsType.command;
  }
}

/// Mode de coordination d'une Saga distribuée.
enum SagaCoordinationMode {
  /// Un orchestrateur central pilote explicitement les étapes et compensations.
  orchestration('Orchestration'),

  /// Les services réagissent aux événements publiés sans orchestrateur central.
  choreography('Chorégraphie');

  const SagaCoordinationMode(this.label);

  /// Libellé lisible.
  final String label;

  /// Désérialise le mode de coordination.
  static SagaCoordinationMode fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      if (norm.contains('chore') || norm.contains('choré')) {
        return SagaCoordinationMode.choreography;
      }
    }
    return SagaCoordinationMode.orchestration;
  }
}

/// Criticité d'une étape dans la matrice des compensations d'une Saga.
enum SagaStepCriticality {
  /// Échec bloquant nécessitant compensation immédiate ou intervention DLQ.
  critical('Critique'),

  /// Criticité élevée.
  high('Élevée'),

  /// Criticité moyenne.
  medium('Moyenne'),

  /// Criticité faible / best effort.
  low('Faible');

  const SagaStepCriticality(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise une criticité.
  static SagaStepCriticality fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in SagaStepCriticality.values) {
        if (value.name.toLowerCase() == norm ||
            value.label.toLowerCase() == norm) {
          return value;
        }
      }
      if (norm.contains('crit')) return SagaStepCriticality.critical;
      if (norm.contains('high') ||
          norm.contains('élev') ||
          norm.contains('elev') ||
          norm.contains('haut')) {
        return SagaStepCriticality.high;
      }
      if (norm.contains('low') || norm.contains('faibl') || norm.contains('bas')) {
        return SagaStepCriticality.low;
      }
    }
    return SagaStepCriticality.medium;
  }
}

/// Champ structuré d'entrée (Déclencheur / Input) ou de sortie (Output) d'un Use Case.
@immutable
class UseCaseFieldSpec {
  /// Crée un champ d'entrée ou de sortie.
  const UseCaseFieldSpec({
    required this.name,
    this.type = 'string',
    this.constraints = '',
    this.description = '',
    this.required,
    this.nullable = false,
    this.isArray = false,
    this.enumValues = const <String>[],
    this.children = const <UseCaseFieldSpec>[],
  });

  /// Nom du champ (ex. `productId`, `newPrice`).
  final String name;

  /// Type attendu (ex. `string (UUID)`, `number`, `object`, `reference`).
  final String type;

  /// Contraintes éventuelles (ex. `> 0`, `requis`).
  final String constraints;

  /// Précision métier optionnelle.
  final String description;

  /// Caractère obligatoire explicite (`null` = inféré depuis [constraints]).
  final bool? required;

  /// Indique si la valeur peut être nulle (`?`).
  final bool nullable;

  /// Indique si le champ est un tableau (`[]`).
  final bool isArray;

  /// Valeurs possibles lorsqu'il s'agit d'une énumération.
  final List<String> enumValues;

  /// Sous-champs imbriqués lorsque le type est un objet ou tableau d'objets.
  final List<UseCaseFieldSpec> children;

  /// Indique si le champ est obligatoire (explicite ou inféré).
  bool get effectiveRequired {
    if (required != null) return required!;
    final lower = '${constraints.toLowerCase()} ${type.toLowerCase()}';
    if (lower.contains('optionnel') || lower.contains('optional')) {
      return false;
    }
    return lower.contains('requis') ||
        lower.contains('required') ||
        lower.contains('obligatoire') ||
        type.trim().endsWith('!');
  }

  /// Indique si le champ représente un tableau.
  bool get effectiveIsArray {
    if (isArray) return true;
    final lower = type.trim().toLowerCase();
    return lower.endsWith('[]') ||
        lower.startsWith('list<') ||
        lower.startsWith('array<');
  }

  /// Nombre total de champs en incluant récursivement [children].
  int get totalFieldCount =>
      1 + children.fold<int>(0, (sum, child) => sum + child.totalFieldCount);

  /// Vérifie les invariants du champ et de ses sous-champs.
  void validate() {
    if (name.trim().isEmpty) {
      throw const FormatException('UseCaseFieldSpec.name requis.');
    }
    for (final child in children) {
      child.validate();
    }
  }

  /// Copie modifiée.
  UseCaseFieldSpec copyWith({
    String? name,
    String? type,
    String? constraints,
    String? description,
    bool? required,
    bool clearRequired = false,
    bool? nullable,
    bool? isArray,
    List<String>? enumValues,
    List<UseCaseFieldSpec>? children,
  }) => UseCaseFieldSpec(
    name: name ?? this.name,
    type: type ?? this.type,
    constraints: constraints ?? this.constraints,
    description: description ?? this.description,
    required: clearRequired ? null : required ?? this.required,
    nullable: nullable ?? this.nullable,
    isArray: isArray ?? this.isArray,
    enumValues: enumValues ?? this.enumValues,
    children: children ?? this.children,
  );

  /// Sérialise le champ.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'type': type,
    'constraints': constraints,
    'description': description,
    if (required != null) 'required': required,
    if (nullable) 'nullable': nullable,
    if (isArray) 'isArray': isArray,
    if (enumValues.isNotEmpty) 'enumValues': enumValues,
    if (children.isNotEmpty)
      'children': [for (final child in children) child.toJson()],
  };

  /// Désérialise un champ depuis un objet JSON ou une chaîne compacte `nom: type`.
  factory UseCaseFieldSpec.fromJson(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      final idx = trimmed.indexOf(':');
      if (idx > 0) {
        final rawName = trimmed.substring(0, idx).trim();
        var rawType = trimmed.substring(idx + 1).trim();
        var constraints = '';
        final parenMatch = RegExp(r'^(.+?)\s*\(([^)]+)\)\s*$').firstMatch(
          rawType,
        );
        if (parenMatch != null) {
          rawType = parenMatch.group(1)!.trim();
          constraints = parenMatch.group(2)!.trim();
        }
        var nullable = false;
        bool? required;
        var isArray = false;
        if (rawType.endsWith('?')) {
          nullable = true;
          rawType = rawType.substring(0, rawType.length - 1).trim();
        }
        if (rawType.endsWith('!')) {
          required = true;
          rawType = rawType.substring(0, rawType.length - 1).trim();
        }
        if (rawType.endsWith('[]')) {
          isArray = true;
          rawType = rawType.substring(0, rawType.length - 2).trim();
        }
        final field = UseCaseFieldSpec(
          name: rawName,
          type: rawType.isEmpty ? 'string' : rawType,
          constraints: constraints,
          required: required,
          nullable: nullable,
          isArray: isArray,
        );
        field.validate();
        return field;
      }
      final field = UseCaseFieldSpec(name: trimmed);
      field.validate();
      return field;
    }
    if (raw is! Map) {
      throw const FormatException('Champ Input/Output de Use Case invalide.');
    }
    final rawChildren = raw['children'];
    final field = UseCaseFieldSpec(
      name: (raw['name'] as String?)?.trim() ?? '',
      type: (raw['type'] as String?)?.trim().isNotEmpty == true
          ? (raw['type'] as String).trim()
          : 'string',
      constraints: (raw['constraints'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
      required: raw['required'] is bool ? raw['required'] as bool : null,
      nullable: raw['nullable'] as bool? ?? false,
      isArray: raw['isArray'] as bool? ?? false,
      enumValues: List<String>.unmodifiable(
        _cleanStringList(raw['enumValues'] ?? raw['enum']),
      ),
      children: rawChildren is List
          ? List<UseCaseFieldSpec>.unmodifiable([
              for (final child in rawChildren) UseCaseFieldSpec.fromJson(child),
            ])
          : const <UseCaseFieldSpec>[],
    );
    field.validate();
    return field;
  }

  /// Format lisible `name: type (constraints)`.
  String formatLine() {
    final c = constraints.trim();
    final d = description.trim();
    final base = '$name: $type${c.isEmpty ? '' : ' ($c)'}';
    return d.isEmpty ? base : '$base — $d';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UseCaseFieldSpec &&
          other.name == name &&
          other.type == type &&
          other.constraints == constraints &&
          other.description == description &&
          other.required == required &&
          other.nullable == nullable &&
          other.isArray == isArray &&
          listEquals(other.enumValues, enumValues) &&
          listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(
    name,
    type,
    constraints,
    description,
    required,
    nullable,
    isArray,
    Object.hashAll(enumValues),
    Object.hashAll(children),
  );
}

/// Scénario comportemental Given / When / Then rattaché à un Use Case.
@immutable
class UseCaseScenarioSpec {
  /// Crée un scénario Given / When / Then.
  UseCaseScenarioSpec({
    required this.id,
    required this.name,
    this.isNominal = true,
    List<String> given = const <String>[],
    List<String> when = const <String>[],
    List<String> then = const <String>[],
  }) : given = List<String>.unmodifiable(_dedupStrings(given)),
       when = List<String>.unmodifiable(_dedupStrings(when)),
       then = List<String>.unmodifiable(_dedupStrings(then));

  /// Identifiant unique du scénario.
  final String id;

  /// Nom du scénario (ex. `Scénario nominal : Mise à jour réussie du prix`).
  final String name;

  /// Indique s'il s'agit d'un cas nominal (`true`) ou d'un cas d'erreur (`false`).
  final bool isNominal;

  /// Préconditions (`Given` / `And`).
  final List<String> given;

  /// Déclencheur (`When` / `And`).
  final List<String> when;

  /// Résultats attendus (`Then` / `And`).
  final List<String> then;

  /// Vérifie les invariants du scénario.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('UseCaseScenarioSpec.id requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('UseCaseScenarioSpec.name requis.');
    }
  }

  /// Copie modifiée.
  UseCaseScenarioSpec copyWith({
    String? id,
    String? name,
    bool? isNominal,
    List<String>? given,
    List<String>? when,
    List<String>? then,
  }) => UseCaseScenarioSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    isNominal: isNominal ?? this.isNominal,
    given: given ?? this.given,
    when: when ?? this.when,
    then: then ?? this.then,
  );

  /// Sérialise le scénario.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'isNominal': isNominal,
    'given': given,
    'when': when,
    'then': then,
  };

  /// Désérialise un scénario depuis JSON.
  factory UseCaseScenarioSpec.fromJson(Object? raw, {int fallbackIndex = 0}) {
    if (raw is! Map) {
      throw const FormatException('Scénario de Use Case invalide.');
    }
    final name = (raw['name'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final item = UseCaseScenarioSpec(
      id: id.isEmpty ? 'scn_${fallbackIndex}_${name.hashCode.abs()}' : id,
      name: name.isEmpty ? 'Scénario ${fallbackIndex + 1}' : name,
      isNominal:
          raw['isNominal'] as bool? ??
          !(name.toLowerCase().contains('erreur') ||
              name.toLowerCase().contains('error') ||
              name.toLowerCase().contains('échec')),
      given: _cleanStringList(raw['given']),
      when: _cleanStringList(raw['when']),
      then: _cleanStringList(raw['then']),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UseCaseScenarioSpec &&
          other.id == id &&
          other.name == name &&
          other.isNominal == isNominal &&
          listEquals(other.given, given) &&
          listEquals(other.when, when) &&
          listEquals(other.then, then);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    isNominal,
    Object.hashAll(given),
    Object.hashAll(when),
    Object.hashAll(then),
  );
}

/// Entrée de cartographie des Use Cases et Sagas par Bounded Context.
@immutable
class BoundedContextUseCaseMap {
  /// Crée une fiche de cartographie de Bounded Context.
  BoundedContextUseCaseMap({
    required this.id,
    required this.boundedContext,
    this.description = '',
    List<String> useCaseCodes = const <String>[],
    List<String> sagaCodes = const <String>[],
    this.notes = '',
  }) : useCaseCodes = List<String>.unmodifiable(_dedupStrings(useCaseCodes)),
       sagaCodes = List<String>.unmodifiable(_dedupStrings(sagaCodes));

  /// Identifiant technique stable.
  final String id;

  /// Nom du Bounded Context (ex. `Catalogue Produits`, `Facturation`).
  final String boundedContext;

  /// Responsabilité principale de ce Bounded Context.
  final String description;

  /// Codes ou noms des Use Cases applicatifs rattachés.
  final List<String> useCaseCodes;

  /// Codes ou noms des Sagas impliquant ce Bounded Context.
  final List<String> sagaCodes;

  /// Notes d'architecture (frontières, CQRS, événements d'intégration).
  final String notes;

  /// Vérifie les invariants de l'entrée de cartographie.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('BoundedContextUseCaseMap.id requis.');
    }
    if (boundedContext.trim().isEmpty) {
      throw const FormatException(
        'BoundedContextUseCaseMap.boundedContext requis.',
      );
    }
  }

  /// Copie modifiée.
  BoundedContextUseCaseMap copyWith({
    String? id,
    String? boundedContext,
    String? description,
    List<String>? useCaseCodes,
    List<String>? sagaCodes,
    String? notes,
  }) => BoundedContextUseCaseMap(
    id: id ?? this.id,
    boundedContext: boundedContext ?? this.boundedContext,
    description: description ?? this.description,
    useCaseCodes: useCaseCodes ?? this.useCaseCodes,
    sagaCodes: sagaCodes ?? this.sagaCodes,
    notes: notes ?? this.notes,
  );

  /// Sérialise l'entrée de cartographie.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'boundedContext': boundedContext,
    'description': description,
    'useCaseCodes': useCaseCodes,
    'sagaCodes': sagaCodes,
    'notes': notes,
  };

  /// Désérialise une entrée de cartographie depuis JSON.
  factory BoundedContextUseCaseMap.fromJson(
    Object? raw, {
    int fallbackIndex = 0,
  }) {
    if (raw is! Map) {
      throw const FormatException('Cartographie Bounded Context invalide.');
    }
    final contextName = (raw['boundedContext'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final item = BoundedContextUseCaseMap(
      id: id.isEmpty
          ? 'bcmap_${fallbackIndex}_${contextName.hashCode.abs()}'
          : id,
      boundedContext: contextName.isEmpty
          ? 'Contexte ${fallbackIndex + 1}'
          : contextName,
      description: (raw['description'] as String?)?.trim() ?? '',
      useCaseCodes: _cleanStringList(raw['useCaseCodes'] ?? raw['useCases']),
      sagaCodes: _cleanStringList(raw['sagaCodes'] ?? raw['sagas']),
      notes: (raw['notes'] as String?)?.trim() ?? '',
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoundedContextUseCaseMap &&
          other.id == id &&
          other.boundedContext == boundedContext &&
          other.description == description &&
          listEquals(other.useCaseCodes, useCaseCodes) &&
          listEquals(other.sagaCodes, sagaCodes) &&
          other.notes == notes;

  @override
  int get hashCode => Object.hash(
    id,
    boundedContext,
    description,
    Object.hashAll(useCaseCodes),
    Object.hashAll(sagaCodes),
    notes,
  );
}

/// Spécification détaillée d'un Use Case de la couche applicative (10 sections
/// + métadonnées CQRS, agrégat, ports, événements et traçabilité).
@immutable
class ApplicationUseCaseSpec {
  /// Crée une spécification complète de Use Case applicatif.
  ApplicationUseCaseSpec({
    required this.id,
    required this.code,
    required this.name,
    this.title = '',
    this.boundedContext = '',
    this.cqrsType = UseCaseCqrsType.command,
    this.targetAggregate = '',
    this.businessGoal = '',
    List<UseCaseFieldSpec> triggerInputs = const <UseCaseFieldSpec>[],
    List<String> businessRules = const <String>[],
    this.inboundPort = '',
    List<String> outboundPorts = const <String>[],
    List<String> emittedEvents = const <String>[],
    List<String> detailedProcess = const <String>[],
    List<UseCaseFieldSpec> outputs = const <UseCaseFieldSpec>[],
    List<String> possibleErrors = const <String>[],
    List<UseCaseScenarioSpec> scenarios = const <UseCaseScenarioSpec>[],
    List<String> acceptanceCriteria = const <String>[],
    List<String> nonGoals = const <String>[],
    this.concurrencyAndIdempotency = '',
    List<String> linkedSpecRefs = const <String>[],
    Map<ContractStage, ContractStatus> states =
        const <ContractStage, ContractStatus>{},
  }) : triggerInputs = List<UseCaseFieldSpec>.unmodifiable(triggerInputs),
       businessRules = List<String>.unmodifiable(_dedupStrings(businessRules)),
       outboundPorts = List<String>.unmodifiable(_dedupStrings(outboundPorts)),
       emittedEvents = List<String>.unmodifiable(_dedupStrings(emittedEvents)),
       detailedProcess = List<String>.unmodifiable(
         _cleanStringList(detailedProcess),
       ),
       outputs = List<UseCaseFieldSpec>.unmodifiable(outputs),
       possibleErrors = List<String>.unmodifiable(
         _dedupStrings(possibleErrors),
       ),
       scenarios = List<UseCaseScenarioSpec>.unmodifiable(scenarios),
       acceptanceCriteria = List<String>.unmodifiable(
         _dedupStrings(acceptanceCriteria),
       ),
       nonGoals = List<String>.unmodifiable(_dedupStrings(nonGoals)),
       linkedSpecRefs = List<String>.unmodifiable(
         _dedupStrings(linkedSpecRefs),
       ),
       states = Map<ContractStage, ContractStatus>.unmodifiable(states);

  /// Identifiant technique stable.
  final String id;

  /// Code court (ex. `UC-001`).
  final String code;

  /// Nom technique du Use Case en PascalCase anglais (ex. `UpdateProductPrice`).
  final String name;

  /// Titre fonctionnel en français.
  final String title;

  /// Bounded Context propriétaire.
  final String boundedContext;

  /// Qualification CQRS (`Command` ou `Query`).
  final UseCaseCqrsType cqrsType;

  /// Agrégat ou Read Model principalement ciblé.
  final String targetAggregate;

  /// 1. Objectif métier.
  final String businessGoal;

  /// 2. Déclencheur (Input).
  final List<UseCaseFieldSpec> triggerInputs;

  /// 3. Règles métier.
  final List<String> businessRules;

  /// Port entrant (Driving Port, ex. `UpdateProductPriceUseCase`).
  final String inboundPort;

  /// 4. Ports sortants utilisés (Driven Ports : Repositories, services, bus).
  final List<String> outboundPorts;

  /// Événements du domaine ou d'intégration publiés.
  final List<String> emittedEvents;

  /// 5. Processus détaillé étape par étape.
  final List<String> detailedProcess;

  /// 6. Sortie (Output).
  final List<UseCaseFieldSpec> outputs;

  /// 7. Erreurs possibles.
  final List<String> possibleErrors;

  /// 8. Scénarios (Given / When / Then).
  final List<UseCaseScenarioSpec> scenarios;

  /// 9. Critères d'acceptation.
  final List<String> acceptanceCriteria;

  /// 10. Non-objectifs.
  final List<String> nonGoals;

  /// Stratégie de concurrence optimiste, transaction et idempotence.
  final String concurrencyAndIdempotency;

  /// Références vers le cahier des charges (`EXF-xxx`, `RG-xxx`, `UC-xxx`).
  final List<String> linkedSpecRefs;

  /// Avancement des 4 phases (`Conception`, `Validation`, `Code`, `Livraison`).
  final Map<ContractStage, ContractStatus> states;

  /// Vérifie les invariants du Use Case.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('ApplicationUseCaseSpec.id requis.');
    }
    if (name.trim().isEmpty && title.trim().isEmpty) {
      throw const FormatException(
        'ApplicationUseCaseSpec.name ou title requis.',
      );
    }
    for (final input in triggerInputs) {
      input.validate();
    }
    for (final output in outputs) {
      output.validate();
    }
    for (final scenario in scenarios) {
      scenario.validate();
    }
  }

  /// Copie modifiée.
  ApplicationUseCaseSpec copyWith({
    String? id,
    String? code,
    String? name,
    String? title,
    String? boundedContext,
    UseCaseCqrsType? cqrsType,
    String? targetAggregate,
    String? businessGoal,
    List<UseCaseFieldSpec>? triggerInputs,
    List<String>? businessRules,
    String? inboundPort,
    List<String>? outboundPorts,
    List<String>? emittedEvents,
    List<String>? detailedProcess,
    List<UseCaseFieldSpec>? outputs,
    List<String>? possibleErrors,
    List<UseCaseScenarioSpec>? scenarios,
    List<String>? acceptanceCriteria,
    List<String>? nonGoals,
    String? concurrencyAndIdempotency,
    List<String>? linkedSpecRefs,
    Map<ContractStage, ContractStatus>? states,
  }) => ApplicationUseCaseSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    title: title ?? this.title,
    boundedContext: boundedContext ?? this.boundedContext,
    cqrsType: cqrsType ?? this.cqrsType,
    targetAggregate: targetAggregate ?? this.targetAggregate,
    businessGoal: businessGoal ?? this.businessGoal,
    triggerInputs: triggerInputs ?? this.triggerInputs,
    businessRules: businessRules ?? this.businessRules,
    inboundPort: inboundPort ?? this.inboundPort,
    outboundPorts: outboundPorts ?? this.outboundPorts,
    emittedEvents: emittedEvents ?? this.emittedEvents,
    detailedProcess: detailedProcess ?? this.detailedProcess,
    outputs: outputs ?? this.outputs,
    possibleErrors: possibleErrors ?? this.possibleErrors,
    scenarios: scenarios ?? this.scenarios,
    acceptanceCriteria: acceptanceCriteria ?? this.acceptanceCriteria,
    nonGoals: nonGoals ?? this.nonGoals,
    concurrencyAndIdempotency:
        concurrencyAndIdempotency ?? this.concurrencyAndIdempotency,
    linkedSpecRefs: linkedSpecRefs ?? this.linkedSpecRefs,
    states: states ?? this.states,
  );

  /// Sérialise le Use Case.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'title': title,
    'boundedContext': boundedContext,
    'cqrsType': cqrsType.name,
    'targetAggregate': targetAggregate,
    'businessGoal': businessGoal,
    'triggerInputs': [for (final f in triggerInputs) f.toJson()],
    'businessRules': businessRules,
    'inboundPort': inboundPort,
    'outboundPorts': outboundPorts,
    'emittedEvents': emittedEvents,
    'detailedProcess': detailedProcess,
    'outputs': [for (final f in outputs) f.toJson()],
    'possibleErrors': possibleErrors,
    'scenarios': [for (final s in scenarios) s.toJson()],
    'acceptanceCriteria': acceptanceCriteria,
    'nonGoals': nonGoals,
    'concurrencyAndIdempotency': concurrencyAndIdempotency,
    'linkedSpecRefs': linkedSpecRefs,
    if (states.isNotEmpty)
      'states': {for (final e in states.entries) e.key.name: e.value.name},
  };

  /// Désérialise un Use Case depuis JSON.
  factory ApplicationUseCaseSpec.fromJson(
    Object? raw, {
    int fallbackIndex = 0,
  }) {
    if (raw is! Map) {
      throw const FormatException('Use Case applicatif invalide.');
    }
    final name = (raw['name'] as String?)?.trim() ?? '';
    final title = (raw['title'] as String?)?.trim() ?? '';
    final code = (raw['code'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final rawInputs = raw['triggerInputs'] ?? raw['inputs'] ?? raw['input'];
    final rawOutputs = raw['outputs'] ?? raw['output'];
    final rawScenarios = raw['scenarios'];

    final item = ApplicationUseCaseSpec(
      id: id.isEmpty
          ? 'uc_${fallbackIndex}_${(name.isEmpty ? title : name).hashCode.abs()}'
          : id,
      code: code.isEmpty
          ? 'UC-${(fallbackIndex + 1).toString().padLeft(3, '0')}'
          : code,
      name: name.isEmpty ? title : name,
      title: title.isEmpty ? name : title,
      boundedContext: (raw['boundedContext'] as String?)?.trim() ?? '',
      cqrsType: UseCaseCqrsType.fromJson(raw['cqrsType'] ?? raw['type']),
      targetAggregate: (raw['targetAggregate'] as String?)?.trim() ?? '',
      businessGoal: (raw['businessGoal'] as String?)?.trim() ?? '',
      triggerInputs: rawInputs is List
          ? [for (final item in rawInputs) UseCaseFieldSpec.fromJson(item)]
          : const <UseCaseFieldSpec>[],
      businessRules: _cleanStringList(raw['businessRules'] ?? raw['rules']),
      inboundPort: (raw['inboundPort'] as String?)?.trim() ?? '',
      outboundPorts: _cleanStringList(
        raw['outboundPorts'] ?? raw['ports'] ?? raw['usedPorts'],
      ),
      emittedEvents: _cleanStringList(
        raw['emittedEvents'] ?? raw['events'] ?? raw['publishedEvents'],
      ),
      detailedProcess: _cleanStringList(
        raw['detailedProcess'] ?? raw['process'] ?? raw['steps'],
      ),
      outputs: rawOutputs is List
          ? [for (final item in rawOutputs) UseCaseFieldSpec.fromJson(item)]
          : const <UseCaseFieldSpec>[],
      possibleErrors: _cleanStringList(
        raw['possibleErrors'] ?? raw['errors'],
      ),
      scenarios: rawScenarios is List
          ? [
              for (var i = 0; i < rawScenarios.length; i++)
                UseCaseScenarioSpec.fromJson(rawScenarios[i], fallbackIndex: i),
            ]
          : const <UseCaseScenarioSpec>[],
      acceptanceCriteria: _cleanStringList(raw['acceptanceCriteria']),
      nonGoals: _cleanStringList(raw['nonGoals'] ?? raw['outOfScope']),
      concurrencyAndIdempotency:
          (raw['concurrencyAndIdempotency'] as String?)?.trim() ?? '',
      linkedSpecRefs: _cleanStringList(raw['linkedSpecRefs']),
      states: _parseContractStates(raw['states']),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApplicationUseCaseSpec &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.title == title &&
          other.boundedContext == boundedContext &&
          other.cqrsType == cqrsType &&
          other.targetAggregate == targetAggregate &&
          other.businessGoal == businessGoal &&
          listEquals(other.triggerInputs, triggerInputs) &&
          listEquals(other.businessRules, businessRules) &&
          other.inboundPort == inboundPort &&
          listEquals(other.outboundPorts, outboundPorts) &&
          listEquals(other.emittedEvents, emittedEvents) &&
          listEquals(other.detailedProcess, detailedProcess) &&
          listEquals(other.outputs, outputs) &&
          listEquals(other.possibleErrors, possibleErrors) &&
          listEquals(other.scenarios, scenarios) &&
          listEquals(other.acceptanceCriteria, acceptanceCriteria) &&
          listEquals(other.nonGoals, nonGoals) &&
          other.concurrencyAndIdempotency == concurrencyAndIdempotency &&
          listEquals(other.linkedSpecRefs, linkedSpecRefs) &&
          mapEquals(other.states, states);

  @override
  int get hashCode => Object.hashAll([
    id,
    code,
    name,
    title,
    boundedContext,
    cqrsType,
    targetAggregate,
    businessGoal,
    Object.hashAll(triggerInputs),
    Object.hashAll(businessRules),
    inboundPort,
    Object.hashAll(outboundPorts),
    Object.hashAll(emittedEvents),
    Object.hashAll(detailedProcess),
    Object.hashAll(outputs),
    Object.hashAll(possibleErrors),
    Object.hashAll(scenarios),
    Object.hashAll(acceptanceCriteria),
    Object.hashAll(nonGoals),
    concurrencyAndIdempotency,
    Object.hashAll(linkedSpecRefs),
    Object.hashAllUnordered([
      for (final e in states.entries) Object.hash(e.key, e.value),
    ]),
  ]);
}

/// Ligne de la matrice des compensations d'une Saga (8 colonnes).
@immutable
class SagaCompensationRow {
  /// Crée une ligne de compensation.
  const SagaCompensationRow({
    required this.id,
    required this.step,
    required this.nominalAction,
    this.compensationAction = '',
    this.rollbackTrigger = '',
    this.criticality = SagaStepCriticality.medium,
    this.idempotent = true,
    this.retryable = true,
    this.timeout = '5s',
  });

  /// Identifiant technique.
  final String id;

  /// Étape (ex. `1. Réservation stock`).
  final String step;

  /// Action Nominale exécutée en flux direct.
  final String nominalAction;

  /// Action de Compensation (Rollback).
  final String compensationAction;

  /// Déclencheur du Rollback.
  final String rollbackTrigger;

  /// Criticité de l'étape / compensation.
  final SagaStepCriticality criticality;

  /// Indique si l'action/compensation est idempotente.
  final bool idempotent;

  /// Indique si l'action/compensation peut être rejouée automatiquement.
  final bool retryable;

  /// Timeout d'exécution (ex. `5s`, `30s`).
  final String timeout;

  /// Vérifie les invariants de la ligne.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('SagaCompensationRow.id requis.');
    }
    if (step.trim().isEmpty) {
      throw const FormatException('SagaCompensationRow.step requis.');
    }
  }

  /// Copie modifiée.
  SagaCompensationRow copyWith({
    String? id,
    String? step,
    String? nominalAction,
    String? compensationAction,
    String? rollbackTrigger,
    SagaStepCriticality? criticality,
    bool? idempotent,
    bool? retryable,
    String? timeout,
  }) => SagaCompensationRow(
    id: id ?? this.id,
    step: step ?? this.step,
    nominalAction: nominalAction ?? this.nominalAction,
    compensationAction: compensationAction ?? this.compensationAction,
    rollbackTrigger: rollbackTrigger ?? this.rollbackTrigger,
    criticality: criticality ?? this.criticality,
    idempotent: idempotent ?? this.idempotent,
    retryable: retryable ?? this.retryable,
    timeout: timeout ?? this.timeout,
  );

  /// Sérialise la ligne.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'step': step,
    'nominalAction': nominalAction,
    'compensationAction': compensationAction,
    'rollbackTrigger': rollbackTrigger,
    'criticality': criticality.name,
    'idempotent': idempotent,
    'retryable': retryable,
    'timeout': timeout,
  };

  /// Désérialise une ligne depuis JSON.
  factory SagaCompensationRow.fromJson(Object? raw, {int fallbackIndex = 0}) {
    if (raw is! Map) {
      throw const FormatException('Ligne de compensation Saga invalide.');
    }
    final step = (raw['step'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final row = SagaCompensationRow(
      id: id.isEmpty ? 'comp_${fallbackIndex}_${step.hashCode.abs()}' : id,
      step: step.isEmpty ? 'Étape ${fallbackIndex + 1}' : step,
      nominalAction: (raw['nominalAction'] as String?)?.trim() ?? '',
      compensationAction:
          (raw['compensationAction'] as String?)?.trim() ?? '',
      rollbackTrigger: (raw['rollbackTrigger'] as String?)?.trim() ?? '',
      criticality: SagaStepCriticality.fromJson(raw['criticality']),
      idempotent: raw['idempotent'] as bool? ?? true,
      retryable: raw['retryable'] as bool? ?? true,
      timeout: (raw['timeout'] as String?)?.trim().isNotEmpty == true
          ? (raw['timeout'] as String).trim()
          : '5s',
    );
    row.validate();
    return row;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SagaCompensationRow &&
          other.id == id &&
          other.step == step &&
          other.nominalAction == nominalAction &&
          other.compensationAction == compensationAction &&
          other.rollbackTrigger == rollbackTrigger &&
          other.criticality == criticality &&
          other.idempotent == idempotent &&
          other.retryable == retryable &&
          other.timeout == timeout;

  @override
  int get hashCode => Object.hash(
    id,
    step,
    nominalAction,
    compensationAction,
    rollbackTrigger,
    criticality,
    idempotent,
    retryable,
    timeout,
  );
}

/// Spécification d'une Saga distribuée avec diagramme Mermaid et matrice des compensations.
@immutable
class OrchestrationSagaSpec {
  /// Crée une spécification de Saga.
  OrchestrationSagaSpec({
    required this.id,
    required this.code,
    required this.name,
    this.title = '',
    List<String> boundedContexts = const <String>[],
    this.coordinationMode = SagaCoordinationMode.orchestration,
    this.triggerEventOrCommand = '',
    this.correlationKey = '',
    this.failureRecoveryStrategy = '',
    this.mermaidDiagram = '',
    List<SagaCompensationRow> compensationMatrix =
        const <SagaCompensationRow>[],
    Map<ContractStage, ContractStatus> states =
        const <ContractStage, ContractStatus>{},
  }) : boundedContexts = List<String>.unmodifiable(
         _dedupStrings(boundedContexts),
       ),
       compensationMatrix = List<SagaCompensationRow>.unmodifiable(
         compensationMatrix,
       ),
       states = Map<ContractStage, ContractStatus>.unmodifiable(states);

  /// Identifiant technique stable.
  final String id;

  /// Code court (ex. `SAGA-001`).
  final String code;

  /// Nom technique de la Saga en PascalCase (ex. `OrderFulfillmentSaga`).
  final String name;

  /// Titre lisible en français.
  final String title;

  /// Bounded Contexts coordonnés par la Saga.
  final List<String> boundedContexts;

  /// Mode de coordination (`Orchestration` ou `Chorégraphie`).
  final SagaCoordinationMode coordinationMode;

  /// Événement ou commande déclenchant la Saga.
  final String triggerEventOrCommand;

  /// Clé de corrélation / d'idempotence partagée entre étapes.
  final String correlationKey;

  /// Stratégie de reprise en cas d'échec de compensation (DLQ, alertes, retry).
  final String failureRecoveryStrategy;

  /// Spécification visuelle de la Saga en syntaxe Mermaid.
  final String mermaidDiagram;

  /// Matrice des compensations de la Saga.
  final List<SagaCompensationRow> compensationMatrix;

  /// Avancement des 4 phases (`Conception`, `Validation`, `Code`, `Livraison`).
  final Map<ContractStage, ContractStatus> states;

  /// Vérifie les invariants de la Saga.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('OrchestrationSagaSpec.id requis.');
    }
    if (name.trim().isEmpty && title.trim().isEmpty) {
      throw const FormatException(
        'OrchestrationSagaSpec.name ou title requis.',
      );
    }
    for (final row in compensationMatrix) {
      row.validate();
    }
  }

  /// Copie modifiée.
  OrchestrationSagaSpec copyWith({
    String? id,
    String? code,
    String? name,
    String? title,
    List<String>? boundedContexts,
    SagaCoordinationMode? coordinationMode,
    String? triggerEventOrCommand,
    String? correlationKey,
    String? failureRecoveryStrategy,
    String? mermaidDiagram,
    List<SagaCompensationRow>? compensationMatrix,
    Map<ContractStage, ContractStatus>? states,
  }) => OrchestrationSagaSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    title: title ?? this.title,
    boundedContexts: boundedContexts ?? this.boundedContexts,
    coordinationMode: coordinationMode ?? this.coordinationMode,
    triggerEventOrCommand:
        triggerEventOrCommand ?? this.triggerEventOrCommand,
    correlationKey: correlationKey ?? this.correlationKey,
    failureRecoveryStrategy:
        failureRecoveryStrategy ?? this.failureRecoveryStrategy,
    mermaidDiagram: mermaidDiagram ?? this.mermaidDiagram,
    compensationMatrix: compensationMatrix ?? this.compensationMatrix,
    states: states ?? this.states,
  );

  /// Sérialise la Saga.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'title': title,
    'boundedContexts': boundedContexts,
    'coordinationMode': coordinationMode.name,
    'triggerEventOrCommand': triggerEventOrCommand,
    'correlationKey': correlationKey,
    'failureRecoveryStrategy': failureRecoveryStrategy,
    'mermaidDiagram': mermaidDiagram,
    'compensationMatrix': [for (final row in compensationMatrix) row.toJson()],
    if (states.isNotEmpty)
      'states': {for (final e in states.entries) e.key.name: e.value.name},
  };

  /// Désérialise une Saga depuis JSON.
  factory OrchestrationSagaSpec.fromJson(
    Object? raw, {
    int fallbackIndex = 0,
  }) {
    if (raw is! Map) {
      throw const FormatException('Spécification de Saga invalide.');
    }
    final name = (raw['name'] as String?)?.trim() ?? '';
    final title = (raw['title'] as String?)?.trim() ?? '';
    final code = (raw['code'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final rawMatrix = raw['compensationMatrix'] ?? raw['compensations'];

    final saga = OrchestrationSagaSpec(
      id: id.isEmpty
          ? 'saga_${fallbackIndex}_${(name.isEmpty ? title : name).hashCode.abs()}'
          : id,
      code: code.isEmpty
          ? 'SAGA-${(fallbackIndex + 1).toString().padLeft(3, '0')}'
          : code,
      name: name.isEmpty ? title : name,
      title: title.isEmpty ? name : title,
      boundedContexts: _cleanStringList(raw['boundedContexts']),
      coordinationMode: SagaCoordinationMode.fromJson(raw['coordinationMode']),
      triggerEventOrCommand:
          (raw['triggerEventOrCommand'] as String?)?.trim() ?? '',
      correlationKey: (raw['correlationKey'] as String?)?.trim() ?? '',
      failureRecoveryStrategy:
          (raw['failureRecoveryStrategy'] as String?)?.trim() ?? '',
      mermaidDiagram: (raw['mermaidDiagram'] as String?)?.trim() ?? '',
      compensationMatrix: rawMatrix is List
          ? [
              for (var i = 0; i < rawMatrix.length; i++)
                SagaCompensationRow.fromJson(rawMatrix[i], fallbackIndex: i),
            ]
          : const <SagaCompensationRow>[],
      states: _parseContractStates(raw['states']),
    );
    saga.validate();
    return saga;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrchestrationSagaSpec &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.title == title &&
          listEquals(other.boundedContexts, boundedContexts) &&
          other.coordinationMode == coordinationMode &&
          other.triggerEventOrCommand == triggerEventOrCommand &&
          other.correlationKey == correlationKey &&
          other.failureRecoveryStrategy == failureRecoveryStrategy &&
          other.mermaidDiagram == mermaidDiagram &&
          listEquals(other.compensationMatrix, compensationMatrix) &&
          mapEquals(other.states, states);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    title,
    Object.hashAll(boundedContexts),
    coordinationMode,
    triggerEventOrCommand,
    correlationKey,
    failureRecoveryStrategy,
    mermaidDiagram,
    Object.hashAll(compensationMatrix),
    Object.hashAllUnordered([
      for (final e in states.entries) Object.hash(e.key, e.value),
    ]),
  );
}

/// Spécification complète « Cas d’usage & orchestration » rattachée à un domaine
/// fonctionnel (cartographie, Use Cases CQRS, Sagas et historique chat IA).
@immutable
class UseCaseOrchestrationSpec {
  /// Crée une spécification complète immuable.
  UseCaseOrchestrationSpec({
    List<BoundedContextUseCaseMap> cartography =
        const <BoundedContextUseCaseMap>[],
    List<ApplicationUseCaseSpec> useCases = const <ApplicationUseCaseSpec>[],
    List<OrchestrationSagaSpec> sagas = const <OrchestrationSagaSpec>[],
    List<SpecChatMessage> chatMessages = const <SpecChatMessage>[],
  }) : cartography = List<BoundedContextUseCaseMap>.unmodifiable(cartography),
       useCases = List<ApplicationUseCaseSpec>.unmodifiable(useCases),
       sagas = List<OrchestrationSagaSpec>.unmodifiable(sagas),
       chatMessages = List<SpecChatMessage>.unmodifiable(chatMessages);

  /// Spécification vide.
  static final UseCaseOrchestrationSpec empty = UseCaseOrchestrationSpec();

  /// Cartographie des Use Cases et Sagas par Bounded Context.
  final List<BoundedContextUseCaseMap> cartography;

  /// Spécifications détaillées des Use Cases applicatifs.
  final List<ApplicationUseCaseSpec> useCases;

  /// Sagas distribuées avec diagrammes Mermaid et matrices de compensation.
  final List<OrchestrationSagaSpec> sagas;

  /// Historique des échanges IA sur cette page pour le domaine.
  final List<SpecChatMessage> chatMessages;

  /// Indique si aucune donnée ni conversation n'est encore enregistrée.
  bool get isEmpty =>
      cartography.isEmpty &&
      useCases.isEmpty &&
      sagas.isEmpty &&
      chatMessages.isEmpty;

  /// Nombre d'éléments affichés dans l'onglet [tab].
  int countForTab(UseCaseOrchestrationTab tab) => switch (tab) {
    UseCaseOrchestrationTab.cartography => cartography.length,
    UseCaseOrchestrationTab.useCases => useCases.length,
    UseCaseOrchestrationTab.sagas => sagas.length,
  };

  /// Vérifie la validité de toutes les entités et l'unicité de leurs identifiants.
  void validate() {
    final mapIds = <String>{};
    for (final entry in cartography) {
      entry.validate();
      if (!mapIds.add(entry.id)) {
        throw FormatException(
          'Identifiant de cartographie dupliqué : ${entry.id}',
        );
      }
    }
    final ucIds = <String>{};
    for (final uc in useCases) {
      uc.validate();
      if (!ucIds.add(uc.id)) {
        throw FormatException('Identifiant de Use Case dupliqué : ${uc.id}');
      }
    }
    final sagaIds = <String>{};
    for (final saga in sagas) {
      saga.validate();
      if (!sagaIds.add(saga.id)) {
        throw FormatException('Identifiant de Saga dupliqué : ${saga.id}');
      }
    }
  }

  /// Copie modifiée.
  UseCaseOrchestrationSpec copyWith({
    List<BoundedContextUseCaseMap>? cartography,
    List<ApplicationUseCaseSpec>? useCases,
    List<OrchestrationSagaSpec>? sagas,
    List<SpecChatMessage>? chatMessages,
  }) => UseCaseOrchestrationSpec(
    cartography: cartography ?? this.cartography,
    useCases: useCases ?? this.useCases,
    sagas: sagas ?? this.sagas,
    chatMessages: chatMessages ?? this.chatMessages,
  );

  /// Sérialise la spécification ; les octets bruts des pièces jointes du chat
  /// sont omis comme dans `DomainContracts`.
  Map<String, Object?> toJson() => <String, Object?>{
    if (cartography.isNotEmpty)
      'cartography': [for (final item in cartography) item.toJson()],
    if (useCases.isNotEmpty)
      'useCases': [for (final item in useCases) item.toJson()],
    if (sagas.isNotEmpty) 'sagas': [for (final item in sagas) item.toJson()],
    if (chatMessages.isNotEmpty)
      'chatMessages': [
        for (final message in chatMessages) _messageToJson(message),
      ],
  };

  static Map<String, Object?> _messageToJson(SpecChatMessage message) => message
      .copyWith(
        attachments: [
          for (final a in message.attachments)
            VibeChatAttachment(
              name: a.name,
              mimeType: a.mimeType,
              bytes: Uint8List(0),
            ),
        ],
      )
      .toJson();

  /// Désérialise une spécification depuis JSON.
  factory UseCaseOrchestrationSpec.fromJson(Object? raw) {
    if (raw == null) return UseCaseOrchestrationSpec.empty;
    if (raw is! Map) {
      throw const FormatException('UseCaseOrchestrationSpec invalide.');
    }
    final rawCartography = raw['cartography'];
    final rawUseCases = raw['useCases'];
    final rawSagas = raw['sagas'];
    final rawChat = raw['chatMessages'];
    final spec = UseCaseOrchestrationSpec(
      cartography: rawCartography is List
          ? [
              for (var i = 0; i < rawCartography.length; i++)
                BoundedContextUseCaseMap.fromJson(
                  rawCartography[i],
                  fallbackIndex: i,
                ),
            ]
          : const <BoundedContextUseCaseMap>[],
      useCases: rawUseCases is List
          ? [
              for (var i = 0; i < rawUseCases.length; i++)
                ApplicationUseCaseSpec.fromJson(
                  rawUseCases[i],
                  fallbackIndex: i,
                ),
            ]
          : const <ApplicationUseCaseSpec>[],
      sagas: rawSagas is List
          ? [
              for (var i = 0; i < rawSagas.length; i++)
                OrchestrationSagaSpec.fromJson(rawSagas[i], fallbackIndex: i),
            ]
          : const <OrchestrationSagaSpec>[],
      chatMessages: rawChat is List
          ? [for (final m in rawChat) SpecChatMessage.fromJson(m)]
          : const <SpecChatMessage>[],
    );
    spec.validate();
    return spec;
  }

  /// Génère un document Markdown structuré (incluant diagrammes Mermaid et
  /// tableaux de compensation) pour l'aperçu visuel ou l'export.
  String toMarkdown({required String domainName}) {
    final buf = StringBuffer()
      ..writeln('# Cas d’usage & orchestration — $domainName')
      ..writeln();

    if (cartography.isNotEmpty) {
      buf.writeln('## 1. Cartographie par Bounded Context');
      buf.writeln();
      for (final item in cartography) {
        buf.writeln('### ${item.boundedContext}');
        if (item.description.isNotEmpty) buf.writeln(item.description);
        if (item.useCaseCodes.isNotEmpty) {
          buf.writeln('- **Use Cases** : ${item.useCaseCodes.join(', ')}');
        }
        if (item.sagaCodes.isNotEmpty) {
          buf.writeln('- **Sagas** : ${item.sagaCodes.join(', ')}');
        }
        if (item.notes.isNotEmpty) {
          buf.writeln('- **Notes** : ${item.notes}');
        }
        buf.writeln();
      }
    }

    if (useCases.isNotEmpty) {
      buf.writeln('## 2. Spécification détaillée des Use Cases');
      buf.writeln();
      for (final uc in useCases) {
        buf.writeln(
          '### ${uc.code} · ${uc.name}'
          '${uc.title.isNotEmpty && uc.title != uc.name ? ' — ${uc.title}' : ''}',
        );
        buf.writeln(
          '- **Type CQRS** : `${uc.cqrsType.label}`'
          '${uc.boundedContext.isEmpty ? '' : ' · **Bounded Context** : ${uc.boundedContext}'}'
          '${uc.targetAggregate.isEmpty ? '' : ' · **Agrégat cible** : `${uc.targetAggregate}`'}',
        );
        if (uc.linkedSpecRefs.isNotEmpty) {
          buf.writeln('- **Traçabilité** : ${uc.linkedSpecRefs.join(', ')}');
        }
        buf.writeln();
        buf.writeln('#### 1. Objectif métier');
        buf.writeln(uc.businessGoal.isEmpty ? '_À préciser_' : uc.businessGoal);
        buf.writeln();
        buf.writeln('#### 2. Déclencheur (Input)');
        if (uc.triggerInputs.isEmpty) {
          buf.writeln('- _Aucun paramètre_');
        } else {
          for (final input in uc.triggerInputs) {
            buf.writeln('- ${input.formatLine()}');
          }
        }
        buf.writeln();
        buf.writeln('#### 3. Règles métier');
        if (uc.businessRules.isEmpty) {
          buf.writeln('- _Aucune règle spécifiée_');
        } else {
          for (final rule in uc.businessRules) {
            buf.writeln('- $rule');
          }
        }
        buf.writeln();
        buf.writeln('#### 4. Ports utilisés & événements');
        if (uc.inboundPort.isNotEmpty) {
          buf.writeln('- **Port entrant** : `${uc.inboundPort}`');
        }
        for (final port in uc.outboundPorts) {
          buf.writeln('- **Port sortant** : `$port`');
        }
        if (uc.emittedEvents.isNotEmpty) {
          buf.writeln(
            '- **Événements publiés** : ${uc.emittedEvents.map((e) => '`$e`').join(', ')}',
          );
        }
        if (uc.concurrencyAndIdempotency.isNotEmpty) {
          buf.writeln(
            '- **Concurrence / Idempotence** : ${uc.concurrencyAndIdempotency}',
          );
        }
        buf.writeln();
        buf.writeln('#### 5. Processus détaillé');
        for (var i = 0; i < uc.detailedProcess.length; i++) {
          buf.writeln('${i + 1}. ${uc.detailedProcess[i]}');
        }
        buf.writeln();
        buf.writeln('#### 6. Sortie (Output)');
        if (uc.outputs.isEmpty) {
          buf.writeln('- _Aucune sortie_');
        } else {
          for (final output in uc.outputs) {
            buf.writeln('- ${output.formatLine()}');
          }
        }
        buf.writeln();
        buf.writeln('#### 7. Erreurs possibles');
        for (final err in uc.possibleErrors) {
          buf.writeln('- `$err`');
        }
        buf.writeln();
        buf.writeln('#### 8. Scénarios (Given / When / Then)');
        for (final scn in uc.scenarios) {
          buf.writeln('**${scn.name}**');
          buf.writeln('```gherkin');
          for (var i = 0; i < scn.given.length; i++) {
            buf.writeln('${i == 0 ? 'Given' : 'And'} ${scn.given[i]}');
          }
          for (var i = 0; i < scn.when.length; i++) {
            buf.writeln('${i == 0 ? 'When' : 'And'} ${scn.when[i]}');
          }
          for (var i = 0; i < scn.then.length; i++) {
            buf.writeln('${i == 0 ? 'Then' : 'And'} ${scn.then[i]}');
          }
          buf.writeln('```');
        }
        buf.writeln();
        buf.writeln('#### 9. Critères d’acceptation');
        for (final ac in uc.acceptanceCriteria) {
          buf.writeln('- $ac');
        }
        buf.writeln();
        buf.writeln('#### 10. Non-objectifs');
        for (final ng in uc.nonGoals) {
          buf.writeln('- $ng');
        }
        buf.writeln();
      }
    }

    if (sagas.isNotEmpty) {
      buf.writeln('## 3. Sagas orchestrées & matrices de compensation');
      buf.writeln();
      for (final saga in sagas) {
        buf.writeln(
          '### ${saga.code} · ${saga.name}'
          '${saga.title.isNotEmpty && saga.title != saga.name ? ' — ${saga.title}' : ''}',
        );
        buf.writeln(
          '- **Mode** : ${saga.coordinationMode.label}'
          '${saga.boundedContexts.isEmpty ? '' : ' · **Bounded Contexts** : ${saga.boundedContexts.join(', ')}'}',
        );
        if (saga.triggerEventOrCommand.isNotEmpty) {
          buf.writeln('- **Déclencheur** : `${saga.triggerEventOrCommand}`');
        }
        if (saga.correlationKey.isNotEmpty) {
          buf.writeln('- **Clé de corrélation** : `${saga.correlationKey}`');
        }
        if (saga.failureRecoveryStrategy.isNotEmpty) {
          buf.writeln(
            '- **Stratégie de reprise / DLQ** : ${saga.failureRecoveryStrategy}',
          );
        }
        buf.writeln();
        if (saga.mermaidDiagram.isNotEmpty) {
          final diagram = saga.mermaidDiagram.trim();
          if (diagram.startsWith('```')) {
            buf.writeln(diagram);
          } else {
            buf.writeln('```mermaid');
            buf.writeln(diagram);
            buf.writeln('```');
          }
          buf.writeln();
        }
        if (saga.compensationMatrix.isNotEmpty) {
          buf.writeln(
            '| Étape | Action Nominale | Action de Compensation (Rollback) | '
            'Déclencheur du Rollback | Criticité | Idempotente | Retryable | Timeout |',
          );
          buf.writeln('| --- | --- | --- | --- | --- | --- | --- | --- |');
          for (final row in saga.compensationMatrix) {
            String esc(String s) => s.replaceAll('|', '\\|');
            buf.writeln(
              '| ${esc(row.step)} | ${esc(row.nominalAction)} | '
              '${esc(row.compensationAction)} | ${esc(row.rollbackTrigger)} | '
              '${row.criticality.label} | ${row.idempotent ? 'Oui' : 'Non'} | '
              '${row.retryable ? 'Oui' : 'Non'} | ${esc(row.timeout)} |',
            );
          }
          buf.writeln();
        }
      }
    }

    return buf.toString().trimRight();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UseCaseOrchestrationSpec &&
          listEquals(other.cartography, cartography) &&
          listEquals(other.useCases, useCases) &&
          listEquals(other.sagas, sagas) &&
          listEquals(other.chatMessages, chatMessages);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(cartography),
    Object.hashAll(useCases),
    Object.hashAll(sagas),
    Object.hashAll(chatMessages),
  );
}
