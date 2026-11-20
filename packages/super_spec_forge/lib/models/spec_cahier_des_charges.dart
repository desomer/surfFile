/// Modèles immuables du cahier des charges fonctionnel et non fonctionnel ([SpecCahierDesCharges]).
library;

import 'package:flutter/foundation.dart';

/// Priorité MoSCoW d'une exigence fonctionnelle.
enum RequirementPriority {
  must('Must', 'Indispensable'),
  should('Should', 'Important'),
  could('Could', 'Souhaitable'),
  wont('Won\'t', 'Reporté');

  /// Construit une priorité MoSCoW.
  const RequirementPriority(this.code, this.label);

  /// Code court MoSCoW.
  final String code;

  /// Libellé français.
  final String label;

  /// Résout une priorité depuis une chaîne JSON.
  static RequirementPriority fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in RequirementPriority.values) {
        if (value.name == norm || value.code.toLowerCase() == norm) {
          return value;
        }
      }
    }
    return RequirementPriority.must;
  }
}

/// Catégorie d'exigence non fonctionnelle.
enum NonFunctionalCategory {
  performance('Performance'),
  security('Sécurité'),
  usability('Ergonomie'),
  reliability('Fiabilité'),
  compliance('Conformité'),
  scalability('Évolutivité'),
  interoperability('Interopérabilité');

  /// Construit une catégorie ENF.
  const NonFunctionalCategory(this.label);

  /// Libellé affiché.
  final String label;

  /// Résout une catégorie depuis JSON.
  static NonFunctionalCategory fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in NonFunctionalCategory.values) {
        if (value.name.toLowerCase() == norm ||
            value.label.toLowerCase() == norm) {
          return value;
        }
      }
    }
    return NonFunctionalCategory.performance;
  }
}

/// Domaine ou module fonctionnel regroupant des exigences.
@immutable
class SpecModule {
  /// Construit un module fonctionnel immuable.
  const SpecModule({
    required this.id,
    required this.name,
    this.description = '',
  });

  /// Identifiant technique stable du module.
  final String id;

  /// Nom du module (ex. `Gestion des commandes`).
  final String name;

  /// Description synthétique du périmètre du module.
  final String description;

  /// Vérifie les invariants du module.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('SpecModule.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('SpecModule.name ne peut pas être vide.');
    }
  }

  /// Copie modifiée.
  SpecModule copyWith({String? id, String? name, String? description}) =>
      SpecModule(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
      );

  /// Sérialise le module en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
  };

  /// Désérialise un module depuis JSON.
  factory SpecModule.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('SpecModule doit être un objet JSON.');
    }
    final name = (raw['name'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final module = SpecModule(
      id: id.isEmpty ? 'mod_${name.hashCode.abs()}' : id,
      name: name.isEmpty ? 'Module sans nom' : name,
      description: (raw['description'] as String?)?.trim() ?? '',
    );
    module.validate();
    return module;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecModule &&
          other.id == id &&
          other.name == name &&
          other.description == description;

  @override
  int get hashCode => Object.hash(id, name, description);
}

/// Exigence fonctionnelle du cahier des charges.
@immutable
class FunctionalRequirement {
  /// Construit une exigence fonctionnelle immuable.
  FunctionalRequirement({
    required this.id,
    required this.code,
    required this.title,
    this.description = '',
    this.moduleId = '',
    this.priority = RequirementPriority.must,
    List<String> actorIds = const <String>[],
    List<String> acceptanceCriteria = const <String>[],
  }) : actorIds = List<String>.unmodifiable(actorIds),
       acceptanceCriteria = List<String>.unmodifiable(acceptanceCriteria);

  /// Identifiant technique unique.
  final String id;

  /// Code métier lisible (ex. `EXF-001`).
  final String code;

  /// Intitulé court de l'exigence.
  final String title;

  /// Description détaillée du comportement attendu.
  final String description;

  /// Identifiant du [SpecModule] parent (optionnel).
  final String moduleId;

  /// Priorité MoSCoW.
  final RequirementPriority priority;

  /// Identifiants des personas concernés.
  final List<String> actorIds;

  /// Critères d'acceptation vérifiables.
  final List<String> acceptanceCriteria;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'FunctionalRequirement.id ne peut pas être vide.',
      );
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'FunctionalRequirement.title ne peut pas être vide.',
      );
    }
  }

  /// Copie modifiée.
  FunctionalRequirement copyWith({
    String? id,
    String? code,
    String? title,
    String? description,
    String? moduleId,
    RequirementPriority? priority,
    List<String>? actorIds,
    List<String>? acceptanceCriteria,
  }) => FunctionalRequirement(
    id: id ?? this.id,
    code: code ?? this.code,
    title: title ?? this.title,
    description: description ?? this.description,
    moduleId: moduleId ?? this.moduleId,
    priority: priority ?? this.priority,
    actorIds: actorIds ?? this.actorIds,
    acceptanceCriteria: acceptanceCriteria ?? this.acceptanceCriteria,
  );

  /// Sérialise l'exigence en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'title': title,
    'description': description,
    'moduleId': moduleId,
    'priority': priority.name,
    'actorIds': actorIds,
    'acceptanceCriteria': acceptanceCriteria,
  };

  /// Désérialise une exigence fonctionnelle depuis JSON.
  factory FunctionalRequirement.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'FunctionalRequirement doit être un objet JSON.',
      );
    }
    final title = (raw['title'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final code = (raw['code'] as String?)?.trim() ?? '';
    final req = FunctionalRequirement(
      id: id.isEmpty ? 'req_${title.hashCode.abs()}' : id,
      code: code.isEmpty ? 'EXF' : code,
      title: title.isEmpty ? 'Exigence sans titre' : title,
      description: (raw['description'] as String?)?.trim() ?? '',
      moduleId: (raw['moduleId'] as String?)?.trim() ?? '',
      priority: RequirementPriority.fromJson(raw['priority']),
      actorIds: _stringList(raw['actorIds']),
      acceptanceCriteria: _stringList(raw['acceptanceCriteria']),
    );
    req.validate();
    return req;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionalRequirement &&
          other.id == id &&
          other.code == code &&
          other.title == title &&
          other.description == description &&
          other.moduleId == moduleId &&
          other.priority == priority &&
          listEquals(other.actorIds, actorIds) &&
          listEquals(other.acceptanceCriteria, acceptanceCriteria);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    title,
    description,
    moduleId,
    priority,
    Object.hashAll(actorIds),
    Object.hashAll(acceptanceCriteria),
  );
}

/// Cas d'usage ou scénario utilisateur structuré.
@immutable
class UseCaseSpec {
  /// Construit un cas d'usage immuable.
  UseCaseSpec({
    required this.id,
    required this.title,
    this.actorId = '',
    List<String> preconditions = const <String>[],
    List<String> mainFlow = const <String>[],
    List<String> alternativeFlows = const <String>[],
    List<String> postconditions = const <String>[],
  }) : preconditions = List<String>.unmodifiable(preconditions),
       mainFlow = List<String>.unmodifiable(mainFlow),
       alternativeFlows = List<String>.unmodifiable(alternativeFlows),
       postconditions = List<String>.unmodifiable(postconditions);

  /// Identifiant unique.
  final String id;

  /// Titre du cas d'usage.
  final String title;

  /// Acteur principal (id ou libellé).
  final String actorId;

  /// Préconditions requises.
  final List<String> preconditions;

  /// Étapes du scénario nominal.
  final List<String> mainFlow;

  /// Scénarios alternatifs ou d'erreur.
  final List<String> alternativeFlows;

  /// Postconditions après exécution.
  final List<String> postconditions;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('UseCaseSpec.id ne peut pas être vide.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException('UseCaseSpec.title ne peut pas être vide.');
    }
  }

  /// Copie modifiée.
  UseCaseSpec copyWith({
    String? id,
    String? title,
    String? actorId,
    List<String>? preconditions,
    List<String>? mainFlow,
    List<String>? alternativeFlows,
    List<String>? postconditions,
  }) => UseCaseSpec(
    id: id ?? this.id,
    title: title ?? this.title,
    actorId: actorId ?? this.actorId,
    preconditions: preconditions ?? this.preconditions,
    mainFlow: mainFlow ?? this.mainFlow,
    alternativeFlows: alternativeFlows ?? this.alternativeFlows,
    postconditions: postconditions ?? this.postconditions,
  );

  /// Sérialise le cas d'usage en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'actorId': actorId,
    'preconditions': preconditions,
    'mainFlow': mainFlow,
    'alternativeFlows': alternativeFlows,
    'postconditions': postconditions,
  };

  /// Désérialise depuis JSON.
  factory UseCaseSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('UseCaseSpec doit être un objet JSON.');
    }
    final title = (raw['title'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final uc = UseCaseSpec(
      id: id.isEmpty ? 'uc_${title.hashCode.abs()}' : id,
      title: title.isEmpty ? 'Cas d\'usage sans titre' : title,
      actorId: (raw['actorId'] as String?)?.trim() ?? '',
      preconditions: _stringList(raw['preconditions']),
      mainFlow: _stringList(raw['mainFlow']),
      alternativeFlows: _stringList(raw['alternativeFlows']),
      postconditions: _stringList(raw['postconditions']),
    );
    uc.validate();
    return uc;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UseCaseSpec &&
          other.id == id &&
          other.title == title &&
          other.actorId == actorId &&
          listEquals(other.preconditions, preconditions) &&
          listEquals(other.mainFlow, mainFlow) &&
          listEquals(other.alternativeFlows, alternativeFlows) &&
          listEquals(other.postconditions, postconditions);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    actorId,
    Object.hashAll(preconditions),
    Object.hashAll(mainFlow),
    Object.hashAll(alternativeFlows),
    Object.hashAll(postconditions),
  );
}

/// Exigence non fonctionnelle (performance, sécurité, conformité, etc.).
@immutable
class NonFunctionalRequirement {
  /// Construit une exigence non fonctionnelle immuable.
  const NonFunctionalRequirement({
    required this.id,
    required this.code,
    required this.category,
    required this.title,
    this.description = '',
    this.targetMetric = '',
  });

  /// Identifiant technique unique.
  final String id;

  /// Code lisible (ex. `ENF-001`).
  final String code;

  /// Catégorie technique ou qualité.
  final NonFunctionalCategory category;

  /// Titre concis.
  final String title;

  /// Description détaillée.
  final String description;

  /// Indicateur ou seuil cible (ex. `< 200 ms p95`).
  final String targetMetric;

  /// Vérifie les invariants.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'NonFunctionalRequirement.id ne peut pas être vide.',
      );
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'NonFunctionalRequirement.title ne peut pas être vide.',
      );
    }
  }

  /// Copie modifiée.
  NonFunctionalRequirement copyWith({
    String? id,
    String? code,
    NonFunctionalCategory? category,
    String? title,
    String? description,
    String? targetMetric,
  }) => NonFunctionalRequirement(
    id: id ?? this.id,
    code: code ?? this.code,
    category: category ?? this.category,
    title: title ?? this.title,
    description: description ?? this.description,
    targetMetric: targetMetric ?? this.targetMetric,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'category': category.name,
    'title': title,
    'description': description,
    'targetMetric': targetMetric,
  };

  /// Désérialise depuis JSON.
  factory NonFunctionalRequirement.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'NonFunctionalRequirement doit être un objet JSON.',
      );
    }
    final title = (raw['title'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final code = (raw['code'] as String?)?.trim() ?? '';
    final enf = NonFunctionalRequirement(
      id: id.isEmpty ? 'enf_${title.hashCode.abs()}' : id,
      code: code.isEmpty ? 'ENF' : code,
      category: NonFunctionalCategory.fromJson(raw['category']),
      title: title.isEmpty ? 'Exigence non fonctionnelle' : title,
      description: (raw['description'] as String?)?.trim() ?? '',
      targetMetric: (raw['targetMetric'] as String?)?.trim() ?? '',
    );
    enf.validate();
    return enf;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NonFunctionalRequirement &&
          other.id == id &&
          other.code == code &&
          other.category == category &&
          other.title == title &&
          other.description == description &&
          other.targetMetric == targetMetric;

  @override
  int get hashCode =>
      Object.hash(id, code, category, title, description, targetMetric);
}

/// Cahier des charges complet (étape 2).
@immutable
class SpecCahierDesCharges {
  /// Construit un cahier des charges immuable.
  SpecCahierDesCharges({
    List<SpecModule> modules = const <SpecModule>[],
    List<FunctionalRequirement> functionalRequirements =
        const <FunctionalRequirement>[],
    List<UseCaseSpec> useCases = const <UseCaseSpec>[],
    List<NonFunctionalRequirement> nonFunctionalRequirements =
        const <NonFunctionalRequirement>[],
  }) : modules = List<SpecModule>.unmodifiable(modules),
       functionalRequirements = List<FunctionalRequirement>.unmodifiable(
         functionalRequirements,
       ),
       useCases = List<UseCaseSpec>.unmodifiable(useCases),
       nonFunctionalRequirements = List<NonFunctionalRequirement>.unmodifiable(
         nonFunctionalRequirements,
       );

  /// Cahier des charges vide.
  static final SpecCahierDesCharges empty = SpecCahierDesCharges();

  /// Modules fonctionnels identifiés.
  final List<SpecModule> modules;

  /// Exigences fonctionnelles.
  final List<FunctionalRequirement> functionalRequirements;

  /// Cas d'usage clés.
  final List<UseCaseSpec> useCases;

  /// Exigences non fonctionnelles.
  final List<NonFunctionalRequirement> nonFunctionalRequirements;

  /// Vrai si au moins un élément est renseigné.
  bool get hasContent =>
      modules.isNotEmpty ||
      functionalRequirements.isNotEmpty ||
      useCases.isNotEmpty ||
      nonFunctionalRequirements.isNotEmpty;

  /// Valide l'ensemble des modules, exigences et cas d'usage.
  void validate() {
    final modIds = <String>{};
    for (final m in modules) {
      m.validate();
      if (!modIds.add(m.id)) {
        throw FormatException('Module dupliqué : ${m.id}');
      }
    }
    final reqIds = <String>{};
    for (final r in functionalRequirements) {
      r.validate();
      if (!reqIds.add(r.id)) {
        throw FormatException('Exigence fonctionnelle dupliquée : ${r.id}');
      }
    }
    final ucIds = <String>{};
    for (final uc in useCases) {
      uc.validate();
      if (!ucIds.add(uc.id)) {
        throw FormatException('Cas d\'usage dupliqué : ${uc.id}');
      }
    }
    final enfIds = <String>{};
    for (final enf in nonFunctionalRequirements) {
      enf.validate();
      if (!enfIds.add(enf.id)) {
        throw FormatException(
          'Exigence non fonctionnelle dupliquée : ${enf.id}',
        );
      }
    }
  }

  /// Copie modifiée.
  SpecCahierDesCharges copyWith({
    List<SpecModule>? modules,
    List<FunctionalRequirement>? functionalRequirements,
    List<UseCaseSpec>? useCases,
    List<NonFunctionalRequirement>? nonFunctionalRequirements,
  }) => SpecCahierDesCharges(
    modules: modules ?? this.modules,
    functionalRequirements:
        functionalRequirements ?? this.functionalRequirements,
    useCases: useCases ?? this.useCases,
    nonFunctionalRequirements:
        nonFunctionalRequirements ?? this.nonFunctionalRequirements,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'modules': [for (final m in modules) m.toJson()],
    'functionalRequirements': [
      for (final r in functionalRequirements) r.toJson(),
    ],
    'useCases': [for (final uc in useCases) uc.toJson()],
    'nonFunctionalRequirements': [
      for (final enf in nonFunctionalRequirements) enf.toJson(),
    ],
  };

  /// Désérialise depuis JSON.
  factory SpecCahierDesCharges.fromJson(Object? raw) {
    if (raw == null) return SpecCahierDesCharges.empty;
    if (raw is! Map) {
      throw const FormatException(
        'SpecCahierDesCharges doit être un objet JSON.',
      );
    }
    final cdc = SpecCahierDesCharges(
      modules: [
        if (raw['modules'] is List)
          for (final item in raw['modules'] as List) SpecModule.fromJson(item),
      ],
      functionalRequirements: [
        if (raw['functionalRequirements'] is List)
          for (final item in raw['functionalRequirements'] as List)
            FunctionalRequirement.fromJson(item),
      ],
      useCases: [
        if (raw['useCases'] is List)
          for (final item in raw['useCases'] as List)
            UseCaseSpec.fromJson(item),
      ],
      nonFunctionalRequirements: [
        if (raw['nonFunctionalRequirements'] is List)
          for (final item in raw['nonFunctionalRequirements'] as List)
            NonFunctionalRequirement.fromJson(item),
      ],
    );
    cdc.validate();
    return cdc;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecCahierDesCharges &&
          listEquals(other.modules, modules) &&
          listEquals(other.functionalRequirements, functionalRequirements) &&
          listEquals(other.useCases, useCases) &&
          listEquals(
            other.nonFunctionalRequirements,
            nonFunctionalRequirements,
          );

  @override
  int get hashCode => Object.hash(
    Object.hashAll(modules),
    Object.hashAll(functionalRequirements),
    Object.hashAll(useCases),
    Object.hashAll(nonFunctionalRequirements),
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
