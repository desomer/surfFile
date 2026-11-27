/// Modèles immuables des snapshots d'itération d'un domaine fonctionnel
/// ([DomainIterationSnapshot], [SnapshotModelArtifact], [SnapshotValueObjectArtifact]).
library;

import 'package:flutter/foundation.dart';

import 'business_object_spec.dart';
import 'domain_catalog.dart';
import 'domain_contracts.dart';
import 'domain_layer_spec.dart';
import 'usecase_orchestration_spec.dart';
import 'value_object_spec.dart';

/// Photographie immuable d'une entrée de modèle ou contrat ([DomainContracts])
/// au sein d'un [DomainIterationSnapshot].
@immutable
class SnapshotModelArtifact {
  /// Crée une photographie d'entrée de contrat immuable.
  SnapshotModelArtifact({
    required this.entryId,
    required this.name,
    required this.dslType,
    required this.groupName,
    this.title = '',
    this.version = '0.0.1',
    required this.objectSpec,
    HexagonalDomainLayerSpec? domainLayerSpec,
  }) : domainLayerSpec = domainLayerSpec ?? HexagonalDomainLayerSpec.empty;

  /// Identifiant stable du nœud dans [DomainContracts].
  final String entryId;

  /// Nom du nœud dans l'arbre DSL.
  final String name;

  /// Type DSL de l'entrée (`model`, `component`, `createxdto`, etc.).
  final String dslType;

  /// Rubrique parente dans le DSL (`models`, `components`, `dto`, `message`).
  final String groupName;

  /// Libellé métier de l'entrée.
  final String title;

  /// Version sémantique `x.y.z` de l'entrée.
  final String version;

  /// Spécification complète des attributs et relations de l'objet métier.
  final BusinessObjectSpec objectSpec;

  /// Spécification de la couche Domain (Architecture Hexagonale) de l'entrée.
  final HexagonalDomainLayerSpec domainLayerSpec;

  /// Vérifie les invariants de l'artefact de modèle.
  void validate() {
    if (entryId.trim().isEmpty) {
      throw const FormatException(
        'SnapshotModelArtifact.entryId ne peut pas être vide.',
      );
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'SnapshotModelArtifact.name ne peut pas être vide.',
      );
    }
    if (dslType.trim().isEmpty) {
      throw const FormatException(
        'SnapshotModelArtifact.dslType ne peut pas être vide.',
      );
    }
    if (groupName.trim().isEmpty) {
      throw const FormatException(
        'SnapshotModelArtifact.groupName ne peut pas être vide.',
      );
    }
    if (!ContractDetails.versionPattern.hasMatch(version)) {
      throw FormatException(
        'Version invalide pour SnapshotModelArtifact « $name » : $version.',
      );
    }
    objectSpec.validate();
    domainLayerSpec.validate();
  }

  /// Retourne une copie modifiée de cet artefact de modèle.
  SnapshotModelArtifact copyWith({
    String? entryId,
    String? name,
    String? dslType,
    String? groupName,
    String? title,
    String? version,
    BusinessObjectSpec? objectSpec,
    HexagonalDomainLayerSpec? domainLayerSpec,
  }) => SnapshotModelArtifact(
    entryId: entryId ?? this.entryId,
    name: name ?? this.name,
    dslType: dslType ?? this.dslType,
    groupName: groupName ?? this.groupName,
    title: title ?? this.title,
    version: version ?? this.version,
    objectSpec: objectSpec ?? this.objectSpec,
    domainLayerSpec: domainLayerSpec ?? this.domainLayerSpec,
  );

  /// Sérialise l'artefact de modèle en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'entryId': entryId,
    'name': name,
    'dslType': dslType,
    'groupName': groupName,
    if (title.isNotEmpty) 'title': title,
    'version': version,
    'objectSpec': objectSpec.toJson(),
    if (domainLayerSpec.isNotEmpty) 'domainLayerSpec': domainLayerSpec.toJson(),
  };

  /// Désérialise et valide un artefact de modèle depuis JSON.
  factory SnapshotModelArtifact.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'SnapshotModelArtifact doit être un objet JSON.',
      );
    }
    if (raw['objectSpec'] is! Map) {
      throw const FormatException(
        'SnapshotModelArtifact.objectSpec invalide.',
      );
    }
    final artifact = SnapshotModelArtifact(
      entryId: (raw['entryId'] as String?)?.trim() ?? '',
      name: (raw['name'] as String?)?.trim() ?? '',
      dslType: (raw['dslType'] as String?)?.trim() ?? '',
      groupName: (raw['groupName'] as String?)?.trim() ?? '',
      title: (raw['title'] as String?) ?? '',
      version: (raw['version'] as String?)?.trim() ?? '0.0.1',
      objectSpec: BusinessObjectSpec.fromJson(raw['objectSpec']),
      domainLayerSpec: raw['domainLayerSpec'] != null
          ? HexagonalDomainLayerSpec.fromJson(raw['domainLayerSpec'])
          : HexagonalDomainLayerSpec.empty,
    );
    artifact.validate();
    return artifact;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapshotModelArtifact &&
          other.entryId == entryId &&
          other.name == name &&
          other.dslType == dslType &&
          other.groupName == groupName &&
          other.title == title &&
          other.version == version &&
          other.objectSpec == objectSpec &&
          other.domainLayerSpec == domainLayerSpec;

  @override
  int get hashCode => Object.hash(
    entryId,
    name,
    dslType,
    groupName,
    title,
    version,
    objectSpec,
    domainLayerSpec,
  );
}

/// Photographie immuable d'un Value Object visible par un domaine au sein d'un
/// [DomainIterationSnapshot].
@immutable
class SnapshotValueObjectArtifact {
  /// Crée une photographie de Value Object immuable.
  const SnapshotValueObjectArtifact({
    required this.id,
    required this.scope,
    required this.spec,
  });

  /// Identifiant technique du Value Object ([ValueObjectSpec.id]).
  final String id;

  /// Portée d'origine (`domain` ou `shared`).
  final ValueObjectScope scope;

  /// Spécification complète du Value Object au moment du snapshot.
  final ValueObjectSpec spec;

  /// Vérifie les invariants de l'artefact de Value Object.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'SnapshotValueObjectArtifact.id ne peut pas être vide.',
      );
    }
    spec.validate();
    if (id != spec.id) {
      throw FormatException(
        'SnapshotValueObjectArtifact.id ($id) doit correspondre à spec.id (${spec.id}).',
      );
    }
  }

  /// Retourne une copie modifiée de cet artefact de Value Object.
  SnapshotValueObjectArtifact copyWith({
    String? id,
    ValueObjectScope? scope,
    ValueObjectSpec? spec,
  }) => SnapshotValueObjectArtifact(
    id: id ?? this.id,
    scope: scope ?? this.scope,
    spec: spec ?? this.spec,
  );

  /// Sérialise l'artefact de Value Object en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'scope': scope.name,
    'spec': spec.toJson(),
  };

  /// Désérialise et valide un artefact de Value Object depuis JSON.
  factory SnapshotValueObjectArtifact.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'SnapshotValueObjectArtifact doit être un objet JSON.',
      );
    }
    if (raw['spec'] is! Map) {
      throw const FormatException(
        'SnapshotValueObjectArtifact.spec invalide.',
      );
    }
    final spec = ValueObjectSpec.fromJson(raw['spec']);
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final artifact = SnapshotValueObjectArtifact(
      id: rawId.isEmpty ? spec.id : rawId,
      scope: ValueObjectScope.fromJson(raw['scope']),
      spec: spec,
    );
    artifact.validate();
    return artifact;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapshotValueObjectArtifact &&
          other.id == id &&
          other.scope == scope &&
          other.spec == spec;

  @override
  int get hashCode => Object.hash(id, scope, spec);
}

/// Jalon figé (baseline d'itération) d'un [FunctionalDomain], capturant l'état
/// complet des modèles, Value Objects, Use Cases et Sagas pour l'analyse de
/// dérive et la génération de prompts incrémentaux entre itérations.
@immutable
class DomainIterationSnapshot {
  /// Crée un snapshot d'itération de domaine immuable.
  DomainIterationSnapshot({
    required this.id,
    required this.iterationNumber,
    required this.label,
    this.notes = '',
    required DateTime createdAt,
    this.techStackId,
    Map<String, SnapshotModelArtifact> models =
        const <String, SnapshotModelArtifact>{},
    Map<String, SnapshotValueObjectArtifact> valueObjects =
        const <String, SnapshotValueObjectArtifact>{},
    Map<String, ApplicationUseCaseSpec> useCases =
        const <String, ApplicationUseCaseSpec>{},
    Map<String, OrchestrationSagaSpec> sagas =
        const <String, OrchestrationSagaSpec>{},
  }) : createdAt = createdAt.toUtc(),
       models = Map<String, SnapshotModelArtifact>.unmodifiable(models),
       valueObjects = Map<String, SnapshotValueObjectArtifact>.unmodifiable(
         valueObjects,
       ),
       useCases = Map<String, ApplicationUseCaseSpec>.unmodifiable(useCases),
       sagas = Map<String, OrchestrationSagaSpec>.unmodifiable(sagas);

  /// Capture une photographie complète de l'état courant de [domain] (et des
  /// Value Objects partagés de [catalog] lorsqu'il est fourni).
  factory DomainIterationSnapshot.capture({
    required String id,
    required int iterationNumber,
    required String label,
    String notes = '',
    DateTime? createdAt,
    required FunctionalDomain domain,
    DomainCatalog? catalog,
  }) {
    final capturedModels = <String, SnapshotModelArtifact>{};
    final contracts = domain.contracts;
    if (contracts != null) {
      for (final group in contracts.groups) {
        for (final node in group.children) {
          final detail = contracts.details[node.id] ?? ContractDetails.defaults;
          capturedModels[node.id] = SnapshotModelArtifact(
            entryId: node.id,
            name: node.name,
            dslType: node.type,
            groupName: group.name,
            title: detail.title,
            version: detail.version,
            objectSpec: contracts.objectFor(node),
            domainLayerSpec: contracts.domainLayerFor(node),
          );
        }
      }
    }

    final resolvedVos = catalog != null
        ? (catalog.domains.any((d) => d.id == domain.id && identical(d, domain))
              ? catalog.resolvedValueObjectsForDomain(domain.id)
              : catalog
                    .copyWith(
                      domains: <FunctionalDomain>[
                        for (final d in catalog.domains)
                          if (d.id != domain.id) d,
                        domain,
                      ],
                    )
                    .resolvedValueObjectsForDomain(domain.id))
        : <ResolvedValueObject>[
            for (final vo in domain.valueObjects)
              ResolvedValueObject(
                spec: vo,
                scope: ValueObjectScope.domain,
                domainId: domain.id,
              ),
          ];
    final capturedVos = <String, SnapshotValueObjectArtifact>{
      for (final resolved in resolvedVos)
        resolved.spec.id: SnapshotValueObjectArtifact(
          id: resolved.spec.id,
          scope: resolved.scope,
          spec: resolved.spec,
        ),
    };

    final orchestration = domain.useCaseOrchestration;
    final capturedUseCases = <String, ApplicationUseCaseSpec>{
      if (orchestration != null)
        for (final uc in orchestration.useCases) uc.id: uc,
    };
    final capturedSagas = <String, OrchestrationSagaSpec>{
      if (orchestration != null)
        for (final saga in orchestration.sagas) saga.id: saga,
    };

    final rawStackId = domain.techStackId?.trim();
    final snapshot = DomainIterationSnapshot(
      id: id,
      iterationNumber: iterationNumber,
      label: label,
      notes: notes,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
      techStackId: (rawStackId == null || rawStackId.isEmpty)
          ? null
          : rawStackId,
      models: capturedModels,
      valueObjects: capturedVos,
      useCases: capturedUseCases,
      sagas: capturedSagas,
    );
    snapshot.validate();
    return snapshot;
  }

  /// Identifiant unique du snapshot.
  final String id;

  /// Numéro d'ordre séquentiel de l'itération (`>= 1`).
  final int iterationNumber;

  /// Libellé lisible du jalon (ex. `Itération 1 — MVP`, 1 à 120 caractères).
  final String label;

  /// Notes libres de livraison ou de périmètre (max 2000 caractères).
  final String notes;

  /// Horodatage UTC de création du snapshot.
  final DateTime createdAt;

  /// Identifiant optionnel du profil de stack technique actif lors de la capture.
  final String? techStackId;

  /// Entrées de modèles et contrats indexées par `entryId`.
  final Map<String, SnapshotModelArtifact> models;

  /// Value Objects visibles du domaine indexés par `vo.id`.
  final Map<String, SnapshotValueObjectArtifact> valueObjects;

  /// Use Cases applicatifs indexés par `uc.id`.
  final Map<String, ApplicationUseCaseSpec> useCases;

  /// Sagas d'orchestration/chorégraphie indexées par `saga.id`.
  final Map<String, OrchestrationSagaSpec> sagas;

  /// Vérifie les invariants du snapshot et de tous ses artefacts.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'DomainIterationSnapshot.id ne peut pas être vide.',
      );
    }
    if (iterationNumber < 1) {
      throw const FormatException(
        'DomainIterationSnapshot.iterationNumber doit être supérieur ou égal à 1.',
      );
    }
    if (label.trim().isEmpty || label.length > 120) {
      throw const FormatException(
        'Le libellé de l’itération doit contenir entre 1 et 120 caractères.',
      );
    }
    if (notes.length > 2000) {
      throw const FormatException(
        'Les notes de l’itération dépassent 2000 caractères.',
      );
    }
    for (final entry in models.entries) {
      entry.value.validate();
      if (entry.key != entry.value.entryId) {
        throw FormatException(
          'Clé de modèle incohérente dans le snapshot $id : ${entry.key} != ${entry.value.entryId}.',
        );
      }
    }
    for (final entry in valueObjects.entries) {
      entry.value.validate();
      if (entry.key != entry.value.id) {
        throw FormatException(
          'Clé de Value Object incohérente dans le snapshot $id : ${entry.key} != ${entry.value.id}.',
        );
      }
    }
    for (final entry in useCases.entries) {
      entry.value.validate();
      if (entry.key != entry.value.id) {
        throw FormatException(
          'Clé de Use Case incohérente dans le snapshot $id : ${entry.key} != ${entry.value.id}.',
        );
      }
    }
    for (final entry in sagas.entries) {
      entry.value.validate();
      if (entry.key != entry.value.id) {
        throw FormatException(
          'Clé de Saga incohérente dans le snapshot $id : ${entry.key} != ${entry.value.id}.',
        );
      }
    }
  }

  /// Retourne une copie modifiée de ce snapshot d'itération.
  DomainIterationSnapshot copyWith({
    String? id,
    int? iterationNumber,
    String? label,
    String? notes,
    DateTime? createdAt,
    String? techStackId,
    bool clearTechStackId = false,
    Map<String, SnapshotModelArtifact>? models,
    Map<String, SnapshotValueObjectArtifact>? valueObjects,
    Map<String, ApplicationUseCaseSpec>? useCases,
    Map<String, OrchestrationSagaSpec>? sagas,
  }) => DomainIterationSnapshot(
    id: id ?? this.id,
    iterationNumber: iterationNumber ?? this.iterationNumber,
    label: label ?? this.label,
    notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt,
    techStackId: clearTechStackId ? null : (techStackId ?? this.techStackId),
    models: models ?? this.models,
    valueObjects: valueObjects ?? this.valueObjects,
    useCases: useCases ?? this.useCases,
    sagas: sagas ?? this.sagas,
  );

  /// Sérialise le snapshot d'itération en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'iterationNumber': iterationNumber,
    'label': label,
    if (notes.isNotEmpty) 'notes': notes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (techStackId != null && techStackId!.trim().isNotEmpty)
      'techStackId': techStackId,
    if (models.isNotEmpty)
      'models': <String, Object?>{
        for (final e in models.entries) e.key: e.value.toJson(),
      },
    if (valueObjects.isNotEmpty)
      'valueObjects': <String, Object?>{
        for (final e in valueObjects.entries) e.key: e.value.toJson(),
      },
    if (useCases.isNotEmpty)
      'useCases': <String, Object?>{
        for (final e in useCases.entries) e.key: e.value.toJson(),
      },
    if (sagas.isNotEmpty)
      'sagas': <String, Object?>{
        for (final e in sagas.entries) e.key: e.value.toJson(),
      },
  };

  /// Désérialise et valide un snapshot d'itération depuis JSON.
  factory DomainIterationSnapshot.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'DomainIterationSnapshot doit être un objet JSON.',
      );
    }
    final rawCreatedAt = raw['createdAt'];
    final parsedCreatedAt = rawCreatedAt is String
        ? DateTime.tryParse(rawCreatedAt)
        : null;
    if (parsedCreatedAt == null) {
      throw const FormatException(
        'DomainIterationSnapshot.createdAt invalide.',
      );
    }
    final rawIteration = raw['iterationNumber'];
    final iterationNumber = switch (rawIteration) {
      int value => value,
      num value => value.toInt(),
      _ => throw const FormatException(
        'DomainIterationSnapshot.iterationNumber invalide.',
      ),
    };

    final rawModels = raw['models'];
    final rawVos = raw['valueObjects'];
    final rawUseCases = raw['useCases'];
    final rawSagas = raw['sagas'];
    if ((rawModels != null && rawModels is! Map) ||
        (rawVos != null && rawVos is! Map) ||
        (rawUseCases != null && rawUseCases is! Map) ||
        (rawSagas != null && rawSagas is! Map)) {
      throw const FormatException(
        'Collections d’artefacts de DomainIterationSnapshot invalides.',
      );
    }

    final rawStackId = (raw['techStackId'] as String?)?.trim();
    final snapshot = DomainIterationSnapshot(
      id: (raw['id'] as String?)?.trim() ?? '',
      iterationNumber: iterationNumber,
      label: (raw['label'] as String?) ?? '',
      notes: (raw['notes'] as String?) ?? '',
      createdAt: parsedCreatedAt,
      techStackId: (rawStackId == null || rawStackId.isEmpty)
          ? null
          : rawStackId,
      models: <String, SnapshotModelArtifact>{
        if (rawModels is Map)
          for (final entry in rawModels.entries)
            '${entry.key}': SnapshotModelArtifact.fromJson(entry.value),
      },
      valueObjects: <String, SnapshotValueObjectArtifact>{
        if (rawVos is Map)
          for (final entry in rawVos.entries)
            '${entry.key}': SnapshotValueObjectArtifact.fromJson(entry.value),
      },
      useCases: <String, ApplicationUseCaseSpec>{
        if (rawUseCases is Map)
          for (final entry in rawUseCases.entries)
            '${entry.key}': ApplicationUseCaseSpec.fromJson(entry.value),
      },
      sagas: <String, OrchestrationSagaSpec>{
        if (rawSagas is Map)
          for (final entry in rawSagas.entries)
            '${entry.key}': OrchestrationSagaSpec.fromJson(entry.value),
      },
    );
    snapshot.validate();
    return snapshot;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainIterationSnapshot &&
          other.id == id &&
          other.iterationNumber == iterationNumber &&
          other.label == label &&
          other.notes == notes &&
          other.createdAt == createdAt &&
          other.techStackId == techStackId &&
          mapEquals(other.models, models) &&
          mapEquals(other.valueObjects, valueObjects) &&
          mapEquals(other.useCases, useCases) &&
          mapEquals(other.sagas, sagas);

  @override
  int get hashCode => Object.hash(
    id,
    iterationNumber,
    label,
    notes,
    createdAt,
    techStackId,
    Object.hashAllUnordered([
      for (final e in models.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAllUnordered([
      for (final e in valueObjects.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAllUnordered([
      for (final e in useCases.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAllUnordered([
      for (final e in sagas.entries) Object.hash(e.key, e.value),
    ]),
  );
}
