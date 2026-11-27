/// Moteur pur et déterministe de synchronisation 3-voies d'objets métiers
/// inter-features (`Feature → Feature`) et depuis l'espace Design (`Design → Spec`)
/// ([FeatureObjectSyncEngine], [FeatureObjectSyncCandidate], [FeatureObjectSyncChoice],
/// [FeatureObjectSyncPreview], [FeatureObjectSyncResult], [FeatureObjectSyncResolution]).
library;

import 'package:flutter/foundation.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/domain_catalog.dart';
import '../models/domain_contracts.dart';
import '../models/feature_object_sync_baseline.dart';
import '../models/json_schema_constraints.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_initiative.dart';
import '../models/value_object_spec.dart';
import 'spec_design_merge_engine.dart';

/// Stratégie de résolution lorsqu'un objet métier existe déjà dans la Feature cible.
enum FeatureObjectSyncResolution {
  /// Fusionne en 3-voies les évolutions de la source tout en conservant les
  /// attributs, relations et états de cycle de vie propres à la Feature cible.
  smartMerge('Fusionner 3-voies (conserver ajouts locaux)'),

  /// Remplace la structure de l'objet cible par la projection de la source tout
  /// en conservant l'identifiant canonique et le nom technique de la cible.
  overwriteFromSource('Remplacer par la source'),

  /// Conserve l'objet existant de la Feature cible sans le modifier.
  skipExisting('Ignorer');

  /// Construit une stratégie de résolution de synchronisation.
  const FeatureObjectSyncResolution(this.label);

  /// Libellé lisible en français affiché dans l'interface.
  final String label;

  /// Résout une stratégie depuis une valeur JSON ou un alias courant, ou `null` si inconnue.
  static FeatureObjectSyncResolution? tryFromJson(Object? raw) {
    if (raw is FeatureObjectSyncResolution) return raw;
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in FeatureObjectSyncResolution.values) {
        if (value.name.toLowerCase() == norm ||
            value.label.toLowerCase() == norm) {
          return value;
        }
      }
      switch (norm) {
        case 'smart_merge':
        case 'smart-merge':
        case 'merge':
          return FeatureObjectSyncResolution.smartMerge;
        case 'overwrite':
        case 'overwrite_from_source':
        case 'overwrite-from-source':
        case 'replace':
          return FeatureObjectSyncResolution.overwriteFromSource;
        case 'skip':
        case 'skip_existing':
        case 'skip-existing':
        case 'ignore':
          return FeatureObjectSyncResolution.skipExisting;
      }
    }
    return null;
  }

  /// Désérialise une stratégie depuis JSON (repli sur [smartMerge]).
  static FeatureObjectSyncResolution fromJson(Object? raw) =>
      tryFromJson(raw) ?? FeatureObjectSyncResolution.smartMerge;
}

/// Objet métier candidat disponible à l'import ou à la re-synchronisation depuis
/// une autre Feature du portefeuille ou depuis un domaine fonctionnel Design.
@immutable
class FeatureObjectSyncCandidate {
  /// Crée un candidat immuable de synchronisation d'objet métier.
  const FeatureObjectSyncCandidate({
    required this.id,
    required this.sourceKind,
    this.sourceFeatureId = '',
    this.sourceFeatureCode = '',
    this.sourceFeatureName = '',
    this.sourceFeatureStatus,
    this.sourceDomainId = '',
    this.sourceDomainName = '',
    this.sourceEntryId = '',
    this.contractType = '',
    required this.rawObject,
  });

  /// Clé unique stable identifiant le candidat dans sa source (`rawObject.id` ou `sourceEntryId`).
  final String id;

  /// Nature de la source amont ([ObjectSyncSourceKind.feature] ou [ObjectSyncSourceKind.designDomain]).
  final ObjectSyncSourceKind sourceKind;

  /// Identifiant de la Feature source lorsque [sourceKind] vaut [ObjectSyncSourceKind.feature].
  final String sourceFeatureId;

  /// Code métier de la Feature source (ex. `FEAT-01`).
  final String sourceFeatureCode;

  /// Nom fonctionnel de la Feature source.
  final String sourceFeatureName;

  /// Statut effectif de la Feature source dans le portefeuille, le cas échéant.
  final SpecPortfolioStatus? sourceFeatureStatus;

  /// Identifiant du domaine fonctionnel source lorsque [sourceKind] vaut [ObjectSyncSourceKind.designDomain].
  final String sourceDomainId;

  /// Nom affiché du domaine fonctionnel source.
  final String sourceDomainName;

  /// Identifiant de l'entrée source dans le catalogue Design (ou ID de l'objet dans la Feature source).
  final String sourceEntryId;

  /// Type DSL du contrat Design (`model`, `component`, `part`, etc.) lorsque applicable.
  final String contractType;

  /// Objet métier projeté au format Spec (avec conversion inverse des Value Objects le cas échéant).
  final BusinessObjectSpec rawObject;

  /// Libellé synthétique en français identifiant la provenance du candidat.
  String get sourceDisplayLabel {
    switch (sourceKind) {
      case ObjectSyncSourceKind.feature:
        final code = sourceFeatureCode.trim();
        final name = sourceFeatureName.trim();
        if (code.isNotEmpty && name.isNotEmpty) return '$code · $name';
        if (code.isNotEmpty) return code;
        if (name.isNotEmpty) return name;
        return 'Feature';
      case ObjectSyncSourceKind.designDomain:
        final domain = sourceDomainName.trim();
        return domain.isNotEmpty ? 'Design · $domain' : 'Domaine Design';
    }
  }

  /// Construit un [FeatureObjectSyncChoice] ciblant ce candidat avec la [resolution] souhaitée.
  FeatureObjectSyncChoice toChoice({
    FeatureObjectSyncResolution resolution =
        FeatureObjectSyncResolution.smartMerge,
  }) => FeatureObjectSyncChoice(
    sourceObjectKey: id,
    sourceKind: sourceKind,
    sourceFeatureId: sourceKind == ObjectSyncSourceKind.feature
        ? sourceFeatureId
        : null,
    sourceDomainId: sourceKind == ObjectSyncSourceKind.designDomain
        ? sourceDomainId
        : null,
    resolution: resolution,
  );

  /// Retourne une copie modifiée de ce candidat.
  FeatureObjectSyncCandidate copyWith({
    String? id,
    ObjectSyncSourceKind? sourceKind,
    String? sourceFeatureId,
    String? sourceFeatureCode,
    String? sourceFeatureName,
    SpecPortfolioStatus? sourceFeatureStatus,
    bool clearSourceFeatureStatus = false,
    String? sourceDomainId,
    String? sourceDomainName,
    String? sourceEntryId,
    String? contractType,
    BusinessObjectSpec? rawObject,
  }) => FeatureObjectSyncCandidate(
    id: id ?? this.id,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceFeatureId: sourceFeatureId ?? this.sourceFeatureId,
    sourceFeatureCode: sourceFeatureCode ?? this.sourceFeatureCode,
    sourceFeatureName: sourceFeatureName ?? this.sourceFeatureName,
    sourceFeatureStatus: clearSourceFeatureStatus
        ? null
        : (sourceFeatureStatus ?? this.sourceFeatureStatus),
    sourceDomainId: sourceDomainId ?? this.sourceDomainId,
    sourceDomainName: sourceDomainName ?? this.sourceDomainName,
    sourceEntryId: sourceEntryId ?? this.sourceEntryId,
    contractType: contractType ?? this.contractType,
    rawObject: rawObject ?? this.rawObject,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureObjectSyncCandidate &&
          other.id == id &&
          other.sourceKind == sourceKind &&
          other.sourceFeatureId == sourceFeatureId &&
          other.sourceFeatureCode == sourceFeatureCode &&
          other.sourceFeatureName == sourceFeatureName &&
          other.sourceFeatureStatus == sourceFeatureStatus &&
          other.sourceDomainId == sourceDomainId &&
          other.sourceDomainName == sourceDomainName &&
          other.sourceEntryId == sourceEntryId &&
          other.contractType == contractType &&
          other.rawObject == rawObject;

  @override
  int get hashCode => Object.hash(
    id,
    sourceKind,
    sourceFeatureId,
    sourceFeatureCode,
    sourceFeatureName,
    sourceFeatureStatus,
    sourceDomainId,
    sourceDomainName,
    sourceEntryId,
    contractType,
    rawObject,
  );
}

/// Choix unitaire de synchronisation d'un objet métier vers une Feature cible.
@immutable
class FeatureObjectSyncChoice {
  /// Crée un choix immuable de synchronisation d'objet métier.
  const FeatureObjectSyncChoice({
    required this.sourceObjectKey,
    required this.sourceKind,
    this.sourceFeatureId,
    this.sourceDomainId,
    this.resolution = FeatureObjectSyncResolution.smartMerge,
  });

  /// Clé identifiant l'objet candidat dans sa source (`candidate.id`, `sourceEntryId`, `rawObject.id` ou `technicalName`).
  final String sourceObjectKey;

  /// Nature de la source amont ([ObjectSyncSourceKind.feature] ou [ObjectSyncSourceKind.designDomain]).
  final ObjectSyncSourceKind sourceKind;

  /// Identifiant de la Feature source lorsque [sourceKind] vaut [ObjectSyncSourceKind.feature].
  final String? sourceFeatureId;

  /// Identifiant du domaine fonctionnel source lorsque [sourceKind] vaut [ObjectSyncSourceKind.designDomain].
  final String? sourceDomainId;

  /// Stratégie de résolution appliquée si l'objet existe déjà dans la Feature cible.
  final FeatureObjectSyncResolution resolution;

  /// Retourne une copie modifiée de ce choix.
  FeatureObjectSyncChoice copyWith({
    String? sourceObjectKey,
    ObjectSyncSourceKind? sourceKind,
    String? sourceFeatureId,
    bool clearSourceFeatureId = false,
    String? sourceDomainId,
    bool clearSourceDomainId = false,
    FeatureObjectSyncResolution? resolution,
  }) => FeatureObjectSyncChoice(
    sourceObjectKey: sourceObjectKey ?? this.sourceObjectKey,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceFeatureId: clearSourceFeatureId
        ? null
        : (sourceFeatureId ?? this.sourceFeatureId),
    sourceDomainId: clearSourceDomainId
        ? null
        : (sourceDomainId ?? this.sourceDomainId),
    resolution: resolution ?? this.resolution,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureObjectSyncChoice &&
          other.sourceObjectKey == sourceObjectKey &&
          other.sourceKind == sourceKind &&
          other.sourceFeatureId == sourceFeatureId &&
          other.sourceDomainId == sourceDomainId &&
          other.resolution == resolution;

  @override
  int get hashCode => Object.hash(
    sourceObjectKey,
    sourceKind,
    sourceFeatureId,
    sourceDomainId,
    resolution,
  );
}

/// Aperçu détaillé et sans effet de bord d'un [FeatureObjectSyncChoice] avant application.
@immutable
class FeatureObjectSyncPreview {
  /// Crée un aperçu immuable de synchronisation d'objet métier.
  FeatureObjectSyncPreview({
    required this.choice,
    required this.projectedSourceObject,
    this.existingTargetObject,
    this.baseSnapshotObject,
    this.mergeResult,
    this.unresolvedExternalRefCount = 0,
    List<String> localImpactedArtifactWarnings = const <String>[],
  }) : localImpactedArtifactWarnings = List<String>.unmodifiable(
         localImpactedArtifactWarnings,
       );

  /// Choix de synchronisation évalué.
  final FeatureObjectSyncChoice choice;

  /// Objet source projeté et recâblé pour le périmètre de la Feature cible.
  final BusinessObjectSpec projectedSourceObject;

  /// Objet existant dans la Feature cible (`null` en cas de création initiale).
  final BusinessObjectSpec? existingTargetObject;

  /// Photographie ancêtre (`baseSpec`) issue de `targetFeature.syncBaselineFor(existingTargetObject.id)`.
  final BusinessObjectSpec? baseSnapshotObject;

  /// Résultat détaillé de la fusion 3-voies lorsque l'objet existe déjà et que la résolution est [FeatureObjectSyncResolution.smartMerge].
  final ObjectMergeResult? mergeResult;

  /// Nombre de références ou relations sortantes absentes de la cible et converties en attributs scalaires d'identifiant.
  final int unresolvedExternalRefCount;

  /// Avertissements signalant les règles de gestion, écrans UX ou tests QA locaux impactés par la suppression ou le retypage d'un attribut.
  final List<String> localImpactedArtifactWarnings;

  /// Vrai si l'objet n'existe pas encore dans la Feature cible.
  bool get isNewInTarget => existingTargetObject == null;

  /// Vrai si l'objet existe déjà dans la Feature cible et ne présente aucun écart effectif selon la résolution choisie.
  bool get isIdentical =>
      existingTargetObject != null &&
      (choice.resolution == FeatureObjectSyncResolution.smartMerge
          ? !(mergeResult?.hasChanges ?? false)
          : projectedSourceObject == existingTargetObject);

  /// Vrai si l'objet existe déjà et sera ignoré ([FeatureObjectSyncResolution.skipExisting]).
  bool get willSkip =>
      existingTargetObject != null &&
      choice.resolution == FeatureObjectSyncResolution.skipExisting;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureObjectSyncPreview &&
          other.choice == choice &&
          other.projectedSourceObject == projectedSourceObject &&
          other.existingTargetObject == existingTargetObject &&
          other.baseSnapshotObject == baseSnapshotObject &&
          other.mergeResult == mergeResult &&
          other.unresolvedExternalRefCount == unresolvedExternalRefCount &&
          listEquals(
            other.localImpactedArtifactWarnings,
            localImpactedArtifactWarnings,
          );

  @override
  int get hashCode => Object.hash(
    choice,
    projectedSourceObject,
    existingTargetObject,
    baseSnapshotObject,
    mergeResult,
    unresolvedExternalRefCount,
    Object.hashAll(localImpactedArtifactWarnings),
  );
}

/// Résultat immuable de l'exécution d'une synchronisation d'objets métiers dans une Feature.
@immutable
class FeatureObjectSyncResult {
  /// Crée un résultat immuable de synchronisation d'objets métiers.
  FeatureObjectSyncResult({
    required this.updatedProject,
    List<String> importedObjectIds = const <String>[],
    List<String> mergedObjectIds = const <String>[],
    List<String> overwrittenObjectIds = const <String>[],
    List<String> skippedObjectNames = const <String>[],
  }) : importedObjectIds = List<String>.unmodifiable(importedObjectIds),
       mergedObjectIds = List<String>.unmodifiable(mergedObjectIds),
       overwrittenObjectIds = List<String>.unmodifiable(overwrittenObjectIds),
       skippedObjectNames = List<String>.unmodifiable(skippedObjectNames);

  /// Nouveau projet validé contenant la Feature cible mise à jour.
  final SpecForgeProject updatedProject;

  /// Identifiants des nouveaux objets métiers importés dans la Feature cible.
  final List<String> importedObjectIds;

  /// Identifiants des objets existants fusionnés en 3-voies dans la Feature cible.
  final List<String> mergedObjectIds;

  /// Identifiants des objets existants remplacés depuis la source dans la Feature cible.
  final List<String> overwrittenObjectIds;

  /// Noms métier des objets existants ignorés en mode [FeatureObjectSyncResolution.skipExisting].
  final List<String> skippedObjectNames;

  /// Vrai lorsqu'au moins un objet a été importé, fusionné ou remplacé dans la Feature cible.
  bool get hasChanges =>
      importedObjectIds.isNotEmpty ||
      mergedObjectIds.isNotEmpty ||
      overwrittenObjectIds.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureObjectSyncResult &&
          other.updatedProject == updatedProject &&
          listEquals(other.importedObjectIds, importedObjectIds) &&
          listEquals(other.mergedObjectIds, mergedObjectIds) &&
          listEquals(other.overwrittenObjectIds, overwrittenObjectIds) &&
          listEquals(other.skippedObjectNames, skippedObjectNames);

  @override
  int get hashCode => Object.hash(
    updatedProject,
    Object.hashAll(importedObjectIds),
    Object.hashAll(mergedObjectIds),
    Object.hashAll(overwrittenObjectIds),
    Object.hashAll(skippedObjectNames),
  );
}

/// Moteur statique pur et déterministe d'import et de re-synchronisation 3-voies
/// d'objets métiers entre Features d'un même projet ou depuis l'espace Design.
abstract final class FeatureObjectSyncEngine {
  /// Types d'entrées de contrats Design assimilés par défaut à des entités/objets métiers.
  static const Set<String> defaultEntityContractTypes = <String>{
    'model',
    'part',
    'component',
  };

  /// Liste les objets métiers candidats disponibles dans la Feature [sourceFeatureId] de [project].
  static List<FeatureObjectSyncCandidate> listCandidatesFromFeature({
    required SpecForgeProject project,
    required String sourceFeatureId,
  }) {
    final feature = project.featureById(sourceFeatureId.trim());
    if (feature == null) {
      return const <FeatureObjectSyncCandidate>[];
    }
    final status = feature.effectiveStatus;
    return List<FeatureObjectSyncCandidate>.unmodifiable(<
      FeatureObjectSyncCandidate
    >[
      for (final obj in feature.businessObjects)
        FeatureObjectSyncCandidate(
          id: obj.id,
          sourceKind: ObjectSyncSourceKind.feature,
          sourceFeatureId: feature.id,
          sourceFeatureCode: feature.code,
          sourceFeatureName: feature.name,
          sourceFeatureStatus: status,
          sourceEntryId: obj.id,
          rawObject: obj,
        ),
    ]);
  }

  /// Liste et projette au format Spec les contrats candidats du domaine Design [domain].
  ///
  /// Convertit récursivement les attributs de type [BusinessAttributeType.valueObject]
  /// vers leur type primitif (VO scalaire) ou un sous-objet typé (VO composite), et
  /// préserve l'identifiant canonique `specOrigin.specObjectId` lorsque l'entrée provient
  /// d'une promotion du projet courant.
  static List<FeatureObjectSyncCandidate> listCandidatesFromDesignDomain({
    required FunctionalDomain domain,
    DomainCatalog? catalog,
    SpecForgeProject? project,
    BusinessObjectModelPreferences? modelPreferences,
    bool includeDtosAndMessages = false,
  }) {
    final contracts = domain.contracts;
    if (contracts == null) {
      return const <FeatureObjectSyncCandidate>[];
    }

    // Résolution préalable de l'ID Spec canonique de chaque entrée du domaine
    // afin de recâbler proprement les références intra-domaine vers cet ID Spec.
    final usedSpecIds = <String>{};
    final entrySpecIds = <String, String>{};
    for (final group in contracts.groups) {
      for (final entry in group.children) {
        final detail = contracts.details[entry.id];
        final origin = detail?.specOrigin;
        final canUseOriginId =
            origin != null &&
            origin.specObjectId.trim().isNotEmpty &&
            (project == null || origin.projectId == project.id);
        String desiredId;
        if (canUseOriginId) {
          desiredId = origin.specObjectId.trim();
        } else {
          final slug = BusinessAttribute.normalizeDslIdentifier(
            entry.name,
            fallback: 'objet',
          ).toLowerCase();
          desiredId = slug.isNotEmpty ? 'obj_$slug' : entry.id;
        }
        var uniqueId = desiredId;
        var suffix = 2;
        while (!usedSpecIds.add(uniqueId)) {
          uniqueId = '${desiredId}_$suffix';
          suffix++;
        }
        entrySpecIds[entry.id] = uniqueId;
      }
    }

    final candidates = <FeatureObjectSyncCandidate>[];
    for (final group in contracts.groups) {
      for (final entry in group.children) {
        final normalizedType = entry.type.trim().toLowerCase();
        if (!includeDtosAndMessages &&
            !defaultEntityContractTypes.contains(normalizedType)) {
          continue;
        }
        final designObj = contracts.objectFor(entry);
        final hasStoredModel = contracts.objects.containsKey(entry.id);
        final effectiveAggregateRoot = hasStoredModel
            ? designObj.aggregateRoot
            : normalizedType == 'model';

        final projectedAttrs = <BusinessAttribute>[
          for (final attr in designObj.attributes)
            _projectDesignAttributeToSpec(
              attr: attr,
              domain: domain,
              catalog: catalog,
              entrySpecIds: entrySpecIds,
              visitedVoIds: const <String>{},
            ),
        ];

        final projectedRelations = <BusinessRelation>[
          for (final rel in designObj.relations)
            entrySpecIds.containsKey(rel.targetObjectId)
                ? rel.copyWith(targetObjectId: entrySpecIds[rel.targetObjectId])
                : rel,
        ];

        final projectedObj = BusinessObjectSpec(
          id: entrySpecIds[entry.id]!,
          name: designObj.name,
          technicalName: designObj.technicalName,
          description: designObj.description,
          aggregateRoot: effectiveAggregateRoot,
          attributes: projectedAttrs,
          relations: projectedRelations,
          lifecycleStates: designObj.lifecycleStates,
          lifecycleTransitions: designObj.lifecycleTransitions,
        );
        projectedObj.validate();

        candidates.add(
          FeatureObjectSyncCandidate(
            id: entry.id,
            sourceKind: ObjectSyncSourceKind.designDomain,
            sourceDomainId: domain.id,
            sourceDomainName: domain.name,
            sourceEntryId: entry.id,
            contractType: entry.type,
            rawObject: projectedObj,
          ),
        );
      }
    }

    return List<FeatureObjectSyncCandidate>.unmodifiable(candidates);
  }

  /// Calcule sans effet de bord les aperçus de synchronisation [FeatureObjectSyncPreview]
  /// pour l'ensemble des [choices] à destination de [targetFeatureId] (ou `project.activeFeature`).
  static List<FeatureObjectSyncPreview> previewSync({
    required SpecForgeProject project,
    String? targetFeatureId,
    DomainCatalog? catalog,
    BusinessObjectModelPreferences? modelPreferences,
    required List<FeatureObjectSyncChoice> choices,
  }) {
    final plan = _buildSyncPlan(
      project: project,
      targetFeatureId: targetFeatureId,
      catalog: catalog,
      modelPreferences: modelPreferences,
      choices: choices,
    );
    return List<FeatureObjectSyncPreview>.unmodifiable(plan.previews);
  }

  /// Exécute de manière déterministe la synchronisation des [choices] dans [targetFeatureId]
  /// (par défaut `project.activeFeature`) sans jamais modifier aucune autre Feature du projet.
  static FeatureObjectSyncResult executeSync({
    required SpecForgeProject project,
    String? targetFeatureId,
    DomainCatalog? catalog,
    BusinessObjectModelPreferences? modelPreferences,
    required List<FeatureObjectSyncChoice> choices,
    DateTime? now,
  }) {
    final plan = _buildSyncPlan(
      project: project,
      targetFeatureId: targetFeatureId,
      catalog: catalog,
      modelPreferences: modelPreferences,
      choices: choices,
    );
    if (plan.items.isEmpty) {
      return FeatureObjectSyncResult(updatedProject: project);
    }

    final timestamp = (now ?? DateTime.now()).toUtc();
    final targetFeature = plan.targetFeature;
    final nextObjects = List<BusinessObjectSpec>.from(
      targetFeature.businessObjects,
    );
    final nextBaselines = Map<String, FeatureObjectSyncBaseline>.from(
      targetFeature.objectSyncBaselines,
    );

    final importedIds = <String>[];
    final mergedIds = <String>[];
    final overwrittenIds = <String>[];
    final skippedNames = <String>[];

    for (final item in plan.items) {
      final preview = item.preview;
      final candidate = item.candidate;
      final existing = preview.existingTargetObject;
      final choice = preview.choice;

      if (existing == null) {
        final importedObj = preview.projectedSourceObject;
        importedObj.validate();
        nextObjects.add(importedObj);
        nextBaselines[importedObj.id] = _buildSyncBaseline(
          objectId: importedObj.id,
          candidate: candidate,
          baseObject: preview.projectedSourceObject,
          syncedAt: timestamp,
        );
        importedIds.add(importedObj.id);
        continue;
      }

      switch (choice.resolution) {
        case FeatureObjectSyncResolution.skipExisting:
          skippedNames.add(existing.name);
        case FeatureObjectSyncResolution.smartMerge:
          final mergedObj = preview.mergeResult!.mergedObject;
          mergedObj.validate();
          final prevBaseline = nextBaselines[existing.id];
          final baselineUnchanged =
              prevBaseline != null &&
              prevBaseline.sourceKind == candidate.sourceKind &&
              prevBaseline.sourceFeatureId == candidate.sourceFeatureId &&
              prevBaseline.sourceDomainId == candidate.sourceDomainId &&
              prevBaseline.baseObject == preview.projectedSourceObject;
          if (mergedObj == existing && baselineUnchanged) {
            break;
          }
          final idx = nextObjects.indexWhere((o) => o.id == existing.id);
          if (idx >= 0) {
            nextObjects[idx] = mergedObj;
          }
          nextBaselines[mergedObj.id] = _buildSyncBaseline(
            objectId: mergedObj.id,
            candidate: candidate,
            baseObject: preview.projectedSourceObject,
            syncedAt: timestamp,
          );
          mergedIds.add(mergedObj.id);
        case FeatureObjectSyncResolution.overwriteFromSource:
          final overwrittenObj = preview.projectedSourceObject;
          overwrittenObj.validate();
          final prevBaseline = nextBaselines[existing.id];
          final baselineUnchanged =
              prevBaseline != null &&
              prevBaseline.sourceKind == candidate.sourceKind &&
              prevBaseline.sourceFeatureId == candidate.sourceFeatureId &&
              prevBaseline.sourceDomainId == candidate.sourceDomainId &&
              prevBaseline.baseObject == preview.projectedSourceObject;
          if (overwrittenObj == existing && baselineUnchanged) {
            break;
          }
          final idx = nextObjects.indexWhere((o) => o.id == existing.id);
          if (idx >= 0) {
            nextObjects[idx] = overwrittenObj;
          }
          nextBaselines[overwrittenObj.id] = _buildSyncBaseline(
            objectId: overwrittenObj.id,
            candidate: candidate,
            baseObject: preview.projectedSourceObject,
            syncedAt: timestamp,
          );
          overwrittenIds.add(overwrittenObj.id);
      }
    }

    final hasEffectiveMutations =
        importedIds.isNotEmpty ||
        mergedIds.isNotEmpty ||
        overwrittenIds.isNotEmpty;

    if (!hasEffectiveMutations) {
      return FeatureObjectSyncResult(
        updatedProject: project,
        skippedObjectNames: skippedNames,
      );
    }

    final updatedFeature = targetFeature.copyWith(
      businessObjects: nextObjects,
      objectSyncBaselines: nextBaselines,
    );
    updatedFeature.validate();

    final updatedProject = project.updateFeature(
      updatedFeature,
      updatedAt: timestamp,
    );
    updatedProject.validate();

    return FeatureObjectSyncResult(
      updatedProject: updatedProject,
      importedObjectIds: importedIds,
      mergedObjectIds: mergedIds,
      overwrittenObjectIds: overwrittenIds,
      skippedObjectNames: skippedNames,
    );
  }

  // ---------------------------------------------------------------------------
  // Planification interne & recâblage des références
  // ---------------------------------------------------------------------------

  static ({
    SpecFeatureSpec targetFeature,
    List<({FeatureObjectSyncCandidate candidate, FeatureObjectSyncPreview preview})>
    items,
    List<FeatureObjectSyncPreview> previews,
  })
  _buildSyncPlan({
    required SpecForgeProject project,
    required String? targetFeatureId,
    required DomainCatalog? catalog,
    required BusinessObjectModelPreferences? modelPreferences,
    required List<FeatureObjectSyncChoice> choices,
  }) {
    final effectiveTargetId =
        (targetFeatureId != null && targetFeatureId.trim().isNotEmpty)
        ? targetFeatureId.trim()
        : project.activeFeature.id;
    final targetFeature = project.featureById(effectiveTargetId);
    if (targetFeature == null) {
      throw FormatException('Feature cible introuvable : $effectiveTargetId.');
    }

    if (choices.isEmpty) {
      return (
        targetFeature: targetFeature,
        items:
            const <
              ({
                FeatureObjectSyncCandidate candidate,
                FeatureObjectSyncPreview preview,
              })
            >[],
        previews: const <FeatureObjectSyncPreview>[],
      );
    }

    final effectivePrefs =
        modelPreferences ?? project.businessObjectModelPreferences;

    // Cache des candidats par source pour éviter les projections redondantes.
    final featureCandidatesCache =
        <String, List<FeatureObjectSyncCandidate>>{};
    final domainCandidatesCache =
        <String, List<FeatureObjectSyncCandidate>>{};

    final resolvedChoices =
        <
          ({
            FeatureObjectSyncChoice choice,
            FeatureObjectSyncCandidate candidate,
            BusinessObjectSpec? existingTarget,
            String targetObjectId,
            String targetTechnicalName,
          })
        >[];

    final usedTargetIds = <String>{
      for (final obj in targetFeature.businessObjects) obj.id,
    };
    final usedTargetTechNamesLower = <String>{
      for (final obj in targetFeature.businessObjects)
        obj.technicalName.toLowerCase(),
    };
    final seenTargetIdsInBatch = <String>{};

    for (final choice in choices) {
      final key = choice.sourceObjectKey.trim();
      if (key.isEmpty) {
        throw const FormatException(
          'FeatureObjectSyncChoice.sourceObjectKey ne peut pas être vide.',
        );
      }

      final FeatureObjectSyncCandidate candidate;
      switch (choice.sourceKind) {
        case ObjectSyncSourceKind.feature:
          final srcFeatureId = choice.sourceFeatureId?.trim() ?? '';
          if (srcFeatureId.isEmpty) {
            throw const FormatException(
              'sourceFeatureId est requis lorsque sourceKind vaut feature.',
            );
          }
          if (srcFeatureId == targetFeature.id) {
            throw FormatException(
              'Impossible de synchroniser la Feature « ${targetFeature.id} » depuis elle-même.',
            );
          }
          if (project.featureById(srcFeatureId) == null) {
            throw FormatException(
              'Feature source introuvable : $srcFeatureId.',
            );
          }
          final pool = featureCandidatesCache.putIfAbsent(
            srcFeatureId,
            () => listCandidatesFromFeature(
              project: project,
              sourceFeatureId: srcFeatureId,
            ),
          );
          final found = _findCandidate(pool, key);
          if (found == null) {
            throw FormatException(
              'Objet candidat « $key » introuvable dans la Feature « $srcFeatureId ».',
            );
          }
          candidate = found;

        case ObjectSyncSourceKind.designDomain:
          final srcDomainId = choice.sourceDomainId?.trim() ?? '';
          if (srcDomainId.isEmpty) {
            throw const FormatException(
              'sourceDomainId est requis lorsque sourceKind vaut designDomain.',
            );
          }
          final domain = catalog?.domains
              .where((d) => d.id == srcDomainId)
              .firstOrNull;
          if (domain == null) {
            throw FormatException(
              'Domaine Design source introuvable : $srcDomainId.',
            );
          }
          final pool = domainCandidatesCache.putIfAbsent(
            srcDomainId,
            () => listCandidatesFromDesignDomain(
              domain: domain,
              catalog: catalog,
              project: project,
              modelPreferences: effectivePrefs,
              includeDtosAndMessages: true,
            ),
          );
          final found = _findCandidate(pool, key);
          if (found == null) {
            throw FormatException(
              'Contrat candidat « $key » introuvable dans le domaine « ${domain.name} ».',
            );
          }
          candidate = found;
      }

      final existingTarget = _findMatchingTargetObject(
        targetFeature: targetFeature,
        candidate: candidate,
      );

      final String targetObjId;
      final String targetTechName;
      if (existingTarget != null) {
        targetObjId = existingTarget.id;
        targetTechName = existingTarget.technicalName;
      } else {
        var candidateId = candidate.rawObject.id;
        var idSuffix = 2;
        while (!usedTargetIds.add(candidateId)) {
          candidateId = '${candidate.rawObject.id}_$idSuffix';
          idSuffix++;
        }
        targetObjId = candidateId;

        var candidateTech = candidate.rawObject.technicalName;
        var techSuffix = 2;
        while (!usedTargetTechNamesLower.add(candidateTech.toLowerCase())) {
          candidateTech = '${candidate.rawObject.technicalName}$techSuffix';
          techSuffix++;
        }
        targetTechName = candidateTech;
      }

      // Évite de traiter deux fois la même cible dans un même lot d'appels.
      if (!seenTargetIdsInBatch.add(targetObjId)) {
        continue;
      }

      resolvedChoices.add((
        choice: choice,
        candidate: candidate,
        existingTarget: existingTarget,
        targetObjectId: targetObjId,
        targetTechnicalName: targetTechName,
      ));
    }

    // Table de résolution des identifiants disponibles dans la Feature cible
    // (objets existants + nouveaux objets co-sélectionnés dans ce lot).
    final availableIdByAliasLower = <String, String>{};
    void registerTargetAlias(String alias, String canonicalTargetId) {
      final clean = alias.trim().toLowerCase();
      if (clean.isEmpty) return;
      availableIdByAliasLower.putIfAbsent(clean, () => canonicalTargetId);
    }

    for (final existing in targetFeature.businessObjects) {
      registerTargetAlias(existing.id, existing.id);
      registerTargetAlias(existing.technicalName, existing.id);
      final baseline = targetFeature.syncBaselineFor(existing.id);
      if (baseline != null && baseline.sourceEntryId.trim().isNotEmpty) {
        registerTargetAlias(baseline.sourceEntryId, existing.id);
      }
    }

    for (final entry in resolvedChoices) {
      registerTargetAlias(entry.targetObjectId, entry.targetObjectId);
      registerTargetAlias(entry.targetTechnicalName, entry.targetObjectId);
      registerTargetAlias(entry.candidate.id, entry.targetObjectId);
      registerTargetAlias(entry.candidate.sourceEntryId, entry.targetObjectId);
      registerTargetAlias(entry.candidate.rawObject.id, entry.targetObjectId);
      registerTargetAlias(
        entry.candidate.rawObject.technicalName,
        entry.targetObjectId,
      );
    }

    final items =
        <
          ({
            FeatureObjectSyncCandidate candidate,
            FeatureObjectSyncPreview preview,
          })
        >[];
    final previews = <FeatureObjectSyncPreview>[];

    for (final entry in resolvedChoices) {
      final rewired = _rewireSourceObjectForTarget(
        project: project,
        catalog: catalog,
        candidate: entry.candidate,
        targetObjectId: entry.targetObjectId,
        targetTechnicalName: entry.targetTechnicalName,
        availableIdByAliasLower: availableIdByAliasLower,
        modelPreferences: effectivePrefs,
      );

      final existingTarget = entry.existingTarget;
      final baseSnapshot = existingTarget == null
          ? null
          : targetFeature.syncBaselineFor(existingTarget.id)?.baseObject;

      final ObjectMergeResult? mergeResult;
      if (existingTarget != null &&
          entry.choice.resolution == FeatureObjectSyncResolution.smartMerge) {
        mergeResult = SpecDesignMergeEngine.merge(
          baseSpec: baseSnapshot,
          nextSpecResolved: rewired.object,
          currentDesign: existingTarget,
        );
      } else {
        mergeResult = null;
      }

      final List<String> warnings;
      if (existingTarget != null &&
          entry.choice.resolution != FeatureObjectSyncResolution.skipExisting) {
        final effectiveAfter =
            entry.choice.resolution == FeatureObjectSyncResolution.smartMerge
            ? mergeResult!.mergedObject
            : rewired.object;
        warnings = _computeLocalImpactedArtifactWarnings(
          targetFeature: targetFeature,
          beforeObject: existingTarget,
          afterObject: effectiveAfter,
        );
      } else {
        warnings = const <String>[];
      }

      final preview = FeatureObjectSyncPreview(
        choice: entry.choice,
        projectedSourceObject: rewired.object,
        existingTargetObject: existingTarget,
        baseSnapshotObject: baseSnapshot,
        mergeResult: mergeResult,
        unresolvedExternalRefCount: rewired.unresolvedExternalRefCount,
        localImpactedArtifactWarnings: warnings,
      );

      items.add((candidate: entry.candidate, preview: preview));
      previews.add(preview);
    }

    return (targetFeature: targetFeature, items: items, previews: previews);
  }

  static FeatureObjectSyncCandidate? _findCandidate(
    List<FeatureObjectSyncCandidate> pool,
    String key,
  ) {
    final needle = key.trim();
    final lower = needle.toLowerCase();
    for (final c in pool) {
      if (c.id == needle ||
          (c.sourceEntryId.isNotEmpty && c.sourceEntryId == needle) ||
          c.rawObject.id == needle) {
        return c;
      }
    }
    for (final c in pool) {
      if (c.id.toLowerCase() == lower ||
          (c.sourceEntryId.isNotEmpty &&
              c.sourceEntryId.toLowerCase() == lower) ||
          c.rawObject.id.toLowerCase() == lower ||
          c.rawObject.technicalName.toLowerCase() == lower) {
        return c;
      }
    }
    return null;
  }

  static BusinessObjectSpec? _findMatchingTargetObject({
    required SpecFeatureSpec targetFeature,
    required FeatureObjectSyncCandidate candidate,
  }) {
    for (final obj in targetFeature.businessObjects) {
      if (obj.id == candidate.rawObject.id) {
        return obj;
      }
    }
    final techLower = candidate.rawObject.technicalName.toLowerCase();
    for (final obj in targetFeature.businessObjects) {
      if (obj.technicalName.toLowerCase() == techLower) {
        return obj;
      }
    }
    if (candidate.sourceEntryId.trim().isNotEmpty) {
      for (final baseline in targetFeature.objectSyncBaselines.values) {
        if (baseline.sourceKind == candidate.sourceKind &&
            baseline.sourceEntryId == candidate.sourceEntryId) {
          final byBaselineId = targetFeature.businessObjects
              .where((o) => o.id == baseline.objectId)
              .firstOrNull;
          if (byBaselineId != null) return byBaselineId;
        }
      }
    }
    return null;
  }

  static FeatureObjectSyncBaseline _buildSyncBaseline({
    required String objectId,
    required FeatureObjectSyncCandidate candidate,
    required BusinessObjectSpec baseObject,
    required DateTime syncedAt,
  }) => FeatureObjectSyncBaseline(
    objectId: objectId,
    sourceKind: candidate.sourceKind,
    sourceFeatureId: candidate.sourceKind == ObjectSyncSourceKind.feature
        ? candidate.sourceFeatureId
        : '',
    sourceFeatureCode: candidate.sourceKind == ObjectSyncSourceKind.feature
        ? candidate.sourceFeatureCode
        : '',
    sourceFeatureName: candidate.sourceKind == ObjectSyncSourceKind.feature
        ? candidate.sourceFeatureName
        : '',
    sourceDomainId: candidate.sourceKind == ObjectSyncSourceKind.designDomain
        ? candidate.sourceDomainId
        : '',
    sourceDomainName: candidate.sourceKind == ObjectSyncSourceKind.designDomain
        ? candidate.sourceDomainName
        : '',
    sourceEntryId: candidate.sourceEntryId,
    syncedAt: syncedAt,
    baseObject: baseObject,
  );

  // ---------------------------------------------------------------------------
  // Projection inverse Design (Value Objects -> Spec)
  // ---------------------------------------------------------------------------

  static BusinessAttribute _projectDesignAttributeToSpec({
    required BusinessAttribute attr,
    required FunctionalDomain domain,
    required DomainCatalog? catalog,
    required Map<String, String> entrySpecIds,
    required Set<String> visitedVoIds,
  }) {
    if (attr.type == BusinessAttributeType.valueObject) {
      final vo = _resolveValueObjectForAttribute(
        rawVoId: attr.valueObjectId,
        domain: domain,
        catalog: catalog,
      );
      if (vo == null || visitedVoIds.contains(vo.id)) {
        return attr.copyWith(
          type: BusinessAttributeType.string,
          valueObjectId: '',
          referenceObjectId: '',
          enumValues: const <String>[],
          children: const <BusinessAttribute>[],
        );
      }

      if (vo.isScalar) {
        final nextType = vo.primitiveType;
        final nextEnums = nextType == BusinessAttributeType.enumeration
            ? (attr.enumValues.isNotEmpty ? attr.enumValues : vo.enumValues)
            : const <String>[];
        final nextSchemaConstraints = attr.schemaConstraints.isEmpty
            ? vo.schemaConstraints
            : _mergeVoBaseWithAttributeConstraints(
                voConstraints: vo.schemaConstraints,
                attrConstraints: attr.schemaConstraints,
              );
        final nextDescription = _appendVoMarker(
          attr.description,
          '(VO: ${vo.technicalName})',
        );
        return attr.copyWith(
          type: nextType,
          valueObjectId: '',
          referenceObjectId: '',
          enumValues: nextEnums,
          schemaConstraints: nextSchemaConstraints,
          description: nextDescription,
          children: const <BusinessAttribute>[],
        );
      }

      // Value Object composite -> sous-objet typé récursif avec IDs enfants préfixés.
      final nextVisited = <String>{...visitedVoIds, vo.id};
      final usedChildIds = <String>{};
      final projectedChildren = <BusinessAttribute>[];
      for (final field in vo.fields) {
        final baseChildId = '${attr.id}_${field.id}';
        var uniqueChildId = baseChildId;
        var suffix = 2;
        while (!usedChildIds.add(uniqueChildId)) {
          uniqueChildId = '${baseChildId}_$suffix';
          suffix++;
        }
        final prefixedField = _prefixNestedChildrenIds(field, uniqueChildId);
        projectedChildren.add(
          _projectDesignAttributeToSpec(
            attr: prefixedField,
            domain: domain,
            catalog: catalog,
            entrySpecIds: entrySpecIds,
            visitedVoIds: nextVisited,
          ),
        );
      }

      final nextDescription = _appendVoMarker(
        attr.description,
        '(VO composite: ${vo.technicalName})',
      );
      return attr.copyWith(
        type: BusinessAttributeType.object,
        valueObjectId: '',
        referenceObjectId: '',
        enumValues: const <String>[],
        description: nextDescription,
        children: projectedChildren,
      );
    }

    final nextChildren = attr.children.isEmpty
        ? const <BusinessAttribute>[]
        : <BusinessAttribute>[
            for (final child in attr.children)
              _projectDesignAttributeToSpec(
                attr: child,
                domain: domain,
                catalog: catalog,
                entrySpecIds: entrySpecIds,
                visitedVoIds: visitedVoIds,
              ),
          ];

    if (attr.type == BusinessAttributeType.reference) {
      final mappedRef = entrySpecIds[attr.referenceObjectId.trim()];
      if (mappedRef != null) {
        return attr.copyWith(
          referenceObjectId: mappedRef,
          children: nextChildren,
        );
      }
    }

    return nextChildren.isEmpty && attr.children.isEmpty
        ? attr
        : attr.copyWith(children: nextChildren);
  }

  static BusinessAttribute _prefixNestedChildrenIds(
    BusinessAttribute field,
    String newId,
  ) {
    if (field.children.isEmpty) {
      return field.copyWith(id: newId);
    }
    final usedIds = <String>{};
    final nextChildren = <BusinessAttribute>[];
    for (final child in field.children) {
      final baseId = '${newId}_${child.id}';
      var uniqueId = baseId;
      var suffix = 2;
      while (!usedIds.add(uniqueId)) {
        uniqueId = '${baseId}_$suffix';
        suffix++;
      }
      nextChildren.add(_prefixNestedChildrenIds(child, uniqueId));
    }
    return field.copyWith(id: newId, children: nextChildren);
  }

  static ValueObjectSpec? _resolveValueObjectForAttribute({
    required String rawVoId,
    required FunctionalDomain domain,
    required DomainCatalog? catalog,
  }) {
    final needle = rawVoId.trim();
    if (needle.isEmpty) return null;
    final lower = needle.toLowerCase();

    if (catalog != null) {
      final fromCatalog = catalog.findValueObject(needle, domainId: domain.id);
      if (fromCatalog != null) return fromCatalog.spec;
      for (final resolved in catalog.resolvedValueObjectsForDomain(domain.id)) {
        if (resolved.spec.id.toLowerCase() == lower ||
            resolved.spec.technicalName.toLowerCase() == lower) {
          return resolved.spec;
        }
      }
    }

    for (final vo in domain.valueObjects) {
      if (vo.id == needle) return vo;
    }
    for (final vo in domain.valueObjects) {
      if (vo.id.toLowerCase() == lower ||
          vo.technicalName.toLowerCase() == lower) {
        return vo;
      }
    }
    return null;
  }

  static JsonSchemaConstraints _mergeVoBaseWithAttributeConstraints({
    required JsonSchemaConstraints voConstraints,
    required JsonSchemaConstraints attrConstraints,
  }) {
    if (voConstraints.isEmpty) return attrConstraints;
    if (attrConstraints.isEmpty) return voConstraints;
    final merged = <String, Object?>{
      ...voConstraints.toSchemaMap(),
      ...attrConstraints.toSchemaMap(),
    };
    try {
      final parsed = JsonSchemaConstraints.fromJson(merged);
      parsed.validate();
      return parsed;
    } on FormatException {
      return attrConstraints;
    }
  }

  static String _appendVoMarker(String description, String marker) {
    final clean = description.trim();
    if (clean.isEmpty) return marker;
    if (clean.toLowerCase().contains(marker.toLowerCase())) return clean;
    return '$clean $marker';
  }

  // ---------------------------------------------------------------------------
  // Recâblage intra-feature & conversion des références externes non résolues
  // ---------------------------------------------------------------------------

  static ({BusinessObjectSpec object, int unresolvedExternalRefCount})
  _rewireSourceObjectForTarget({
    required SpecForgeProject project,
    required DomainCatalog? catalog,
    required FeatureObjectSyncCandidate candidate,
    required String targetObjectId,
    required String targetTechnicalName,
    required Map<String, String> availableIdByAliasLower,
    required BusinessObjectModelPreferences modelPreferences,
  }) {
    final rawObj = candidate.rawObject;
    var unresolvedCount = 0;

    String? resolveAvailableTargetId(String rawRef) {
      final clean = rawRef.trim();
      if (clean.isEmpty) return null;
      final lower = clean.toLowerCase();
      if (lower == rawObj.id.toLowerCase() ||
          lower == rawObj.technicalName.toLowerCase() ||
          (candidate.sourceEntryId.isNotEmpty &&
              lower == candidate.sourceEntryId.toLowerCase())) {
        return targetObjectId;
      }
      final fromTarget = availableIdByAliasLower[lower];
      if (fromTarget != null) return fromTarget;

      // Si la référence source désigne un objet connu dans la Feature ou le domaine
      // amont sous un ID interne, tente aussi une résolution via son technicalName.
      final upstream = _lookupUpstreamObject(
        project: project,
        catalog: catalog,
        candidate: candidate,
        rawTarget: clean,
      );
      if (upstream != null) {
        final byUpstreamId =
            availableIdByAliasLower[upstream.object.id.toLowerCase()];
        if (byUpstreamId != null) return byUpstreamId;
        final byUpstreamTech = availableIdByAliasLower[
          upstream.object.technicalName.toLowerCase()
        ];
        if (byUpstreamTech != null) return byUpstreamTech;
      }
      return null;
    }

    BusinessAttribute transformAttribute(BusinessAttribute attr) {
      final nextChildren = attr.children.isEmpty
          ? const <BusinessAttribute>[]
          : <BusinessAttribute>[
              for (final child in attr.children) transformAttribute(child),
            ];

      if (attr.type != BusinessAttributeType.reference) {
        return nextChildren.isEmpty && attr.children.isEmpty
            ? attr
            : attr.copyWith(children: nextChildren);
      }

      final resolvedId = resolveAvailableTargetId(attr.referenceObjectId);
      if (resolvedId != null) {
        return attr.copyWith(
          referenceObjectId: resolvedId,
          children: nextChildren,
        );
      }

      unresolvedCount++;
      final upstream = _lookupUpstreamObject(
        project: project,
        catalog: catalog,
        candidate: candidate,
        rawTarget: attr.referenceObjectId,
      );
      final scalarType = _scalarIdTypeForTarget(
        upstream?.object,
        modelPreferences,
      );
      final note = _externalReferenceNote(
        rawTarget: attr.referenceObjectId,
        upstream: upstream,
        candidate: candidate,
      );
      return attr.copyWith(
        type: scalarType,
        referenceObjectId: '',
        description: _appendExplanationNote(attr.description, note),
        children: nextChildren,
      );
    }

    final rewiredAttributes = <BusinessAttribute>[
      for (final attr in rawObj.attributes) transformAttribute(attr),
    ];
    final usedAttrNamesLower = <String>{
      for (final attr in rewiredAttributes) attr.name.toLowerCase(),
    };

    final rewiredRelations = <BusinessRelation>[];
    for (final rel in rawObj.relations) {
      final resolvedId = resolveAvailableTargetId(rel.targetObjectId);
      if (resolvedId != null) {
        rewiredRelations.add(rel.copyWith(targetObjectId: resolvedId));
        continue;
      }

      if (_hasEquivalentRefAttributeInRaw(
        rawAttributes: rawObj.attributes,
        rel: rel,
        project: project,
        catalog: catalog,
        candidate: candidate,
      )) {
        continue;
      }

      unresolvedCount++;
      if (rewiredAttributes.length >=
          BusinessObjectSpec.maxAttributesPerObject) {
        continue;
      }
      final attrName = _uniqueAttributeName(rel.name, usedAttrNamesLower);
      usedAttrNamesLower.add(attrName.toLowerCase());
      final isArray =
          rel.cardinality == BusinessRelationCardinality.oneToMany ||
          rel.cardinality == BusinessRelationCardinality.manyToMany;
      final upstream = _lookupUpstreamObject(
        project: project,
        catalog: catalog,
        candidate: candidate,
        rawTarget: rel.targetObjectId,
      );
      final scalarType = _scalarIdTypeForTarget(
        upstream?.object,
        modelPreferences,
      );
      final note = _externalReferenceNote(
        rawTarget: rel.targetObjectId,
        upstream: upstream,
        candidate: candidate,
      );
      rewiredAttributes.add(
        BusinessAttribute(
          id: 'attr_${rel.id}',
          name: attrName,
          type: scalarType,
          referenceObjectId: '',
          isArray: isArray,
          required: rel.required,
          description: _appendExplanationNote(rel.description, note),
        ),
      );
    }

    final projected = BusinessObjectSpec(
      id: targetObjectId,
      name: rawObj.name,
      technicalName: targetTechnicalName,
      description: rawObj.description,
      aggregateRoot: rawObj.aggregateRoot,
      attributes: rewiredAttributes,
      relations: rewiredRelations,
      lifecycleStates: rawObj.lifecycleStates,
      lifecycleTransitions: rawObj.lifecycleTransitions,
    );
    projected.validate();
    return (object: projected, unresolvedExternalRefCount: unresolvedCount);
  }

  static ({BusinessObjectSpec object, String? originLabel})?
  _lookupUpstreamObject({
    required SpecForgeProject project,
    required DomainCatalog? catalog,
    required FeatureObjectSyncCandidate candidate,
    required String rawTarget,
  }) {
    final needle = rawTarget.trim();
    if (needle.isEmpty) return null;
    final lower = needle.toLowerCase();

    if (candidate.sourceKind == ObjectSyncSourceKind.feature) {
      final srcFeature = project.featureById(candidate.sourceFeatureId);
      if (srcFeature != null) {
        for (final obj in srcFeature.businessObjects) {
          if (obj.id.toLowerCase() == lower ||
              obj.technicalName.toLowerCase() == lower ||
              obj.name.toLowerCase() == lower) {
            return (
              object: obj,
              originLabel: 'Feature ${srcFeature.displayLabel}',
            );
          }
        }
      }
    } else if (catalog != null) {
      final srcDomain = catalog.domains
          .where((d) => d.id == candidate.sourceDomainId)
          .firstOrNull;
      final contracts = srcDomain?.contracts;
      if (srcDomain != null && contracts != null) {
        for (final group in contracts.groups) {
          for (final JsonNode entry in group.children) {
            final originSpecId =
                contracts.details[entry.id]?.specOrigin?.specObjectId ?? '';
            final slugId =
                'obj_${BusinessAttribute.normalizeDslIdentifier(entry.name, fallback: 'objet').toLowerCase()}';
            if (entry.id.toLowerCase() == lower ||
                entry.name.toLowerCase() == lower ||
                DomainContracts.technicalNameOf(entry).toLowerCase() == lower ||
                (originSpecId.isNotEmpty &&
                    originSpecId.toLowerCase() == lower) ||
                slugId == lower) {
              return (
                object: contracts.objectFor(entry),
                originLabel: 'domaine ${srcDomain.name}',
              );
            }
          }
        }
      }
    }

    // Recherche élargie dans les autres features du projet ou autres domaines Design.
    for (final feature in project.allFeatures) {
      for (final obj in feature.businessObjects) {
        if (obj.id.toLowerCase() == lower ||
            obj.technicalName.toLowerCase() == lower) {
          return (object: obj, originLabel: 'Feature ${feature.displayLabel}');
        }
      }
    }
    if (catalog != null) {
      for (final domain in catalog.domains) {
        final contracts = domain.contracts;
        if (contracts == null) continue;
        for (final group in contracts.groups) {
          for (final entry in group.children) {
            if (entry.id.toLowerCase() == lower ||
                DomainContracts.technicalNameOf(entry).toLowerCase() == lower) {
              return (
                object: contracts.objectFor(entry),
                originLabel: 'domaine ${domain.name}',
              );
            }
          }
        }
      }
    }
    return null;
  }

  static bool _hasEquivalentRefAttributeInRaw({
    required List<BusinessAttribute> rawAttributes,
    required BusinessRelation rel,
    required SpecForgeProject project,
    required DomainCatalog? catalog,
    required FeatureObjectSyncCandidate candidate,
  }) {
    final relIsArray =
        rel.cardinality == BusinessRelationCardinality.oneToMany ||
        rel.cardinality == BusinessRelationCardinality.manyToMany;
    final relTarget = _lookupUpstreamObject(
      project: project,
      catalog: catalog,
      candidate: candidate,
      rawTarget: rel.targetObjectId,
    )?.object;

    for (final attr in rawAttributes) {
      if (attr.name.toLowerCase() == rel.name.toLowerCase()) {
        return true;
      }
      if (attr.type == BusinessAttributeType.reference &&
          attr.isArray == relIsArray) {
        if (attr.referenceObjectId.trim().toLowerCase() ==
            rel.targetObjectId.trim().toLowerCase()) {
          return true;
        }
        final attrTarget = _lookupUpstreamObject(
          project: project,
          catalog: catalog,
          candidate: candidate,
          rawTarget: attr.referenceObjectId,
        )?.object;
        if (relTarget != null && attrTarget?.id == relTarget.id) {
          return true;
        }
      }
    }
    return false;
  }

  static String _uniqueAttributeName(String rawBase, Set<String> usedLower) {
    final base = BusinessAttribute.isValidDslIdentifier(rawBase)
        ? rawBase
        : BusinessAttribute.normalizeDslIdentifier(rawBase, fallback: 'ref');
    if (!usedLower.contains(base.toLowerCase())) return base;
    for (var i = 2; ; i++) {
      final candidate = '${base}_$i';
      if (!usedLower.contains(candidate.toLowerCase())) return candidate;
    }
  }

  static BusinessAttributeType _scalarIdTypeForTarget(
    BusinessObjectSpec? targetSpec,
    BusinessObjectModelPreferences prefs,
  ) {
    if (targetSpec != null) {
      final pk =
          targetSpec.attributes
              .where((a) => !a.isArray && a.name.toLowerCase() == 'id')
              .firstOrNull ??
          targetSpec.attributes
              .where((a) => !a.isArray && a.unique && a.required)
              .firstOrNull;
      if (pk != null) {
        switch (pk.type) {
          case BusinessAttributeType.uuid:
          case BusinessAttributeType.integer:
          case BusinessAttributeType.string:
          case BusinessAttributeType.number:
            return pk.type;
          default:
            break;
        }
      }
    }
    return switch (prefs.idStrategy) {
      PrimaryIdStrategy.uuid => BusinessAttributeType.uuid,
      PrimaryIdStrategy.autoIncrementInt => BusinessAttributeType.integer,
      PrimaryIdStrategy.ulid ||
      PrimaryIdStrategy.businessKeyOnly ||
      PrimaryIdStrategy.none => BusinessAttributeType.string,
    };
  }

  static String _externalReferenceNote({
    required String rawTarget,
    required ({BusinessObjectSpec object, String? originLabel})? upstream,
    required FeatureObjectSyncCandidate candidate,
  }) {
    final targetLabel =
        upstream?.object.name ??
        (rawTarget.trim().isNotEmpty ? rawTarget.trim() : 'entité externe');
    final originLabel =
        upstream?.originLabel ??
        (candidate.sourceKind == ObjectSyncSourceKind.feature
            ? 'Feature ${candidate.sourceDisplayLabel}'
            : 'domaine ${candidate.sourceDomainName}');
    return originLabel.trim().isNotEmpty
        ? 'Référence externe vers $targetLabel ($originLabel)'
        : 'Référence externe vers $targetLabel';
  }

  static String _appendExplanationNote(String existingDescription, String note) {
    final clean = existingDescription.trim();
    if (clean.isEmpty) return note;
    if (clean.toLowerCase().contains(note.toLowerCase())) return clean;
    return '$clean — $note';
  }

  // ---------------------------------------------------------------------------
  // Détection d'impact sur les artefacts locaux (RG, Écrans UX, Tests QA)
  // ---------------------------------------------------------------------------

  static List<String> _computeLocalImpactedArtifactWarnings({
    required SpecFeatureSpec targetFeature,
    required BusinessObjectSpec beforeObject,
    required BusinessObjectSpec afterObject,
  }) {
    final mutations =
        <
          ({
            String path,
            String leafName,
            bool isRemoved,
            String? typeTransitionLabel,
          })
        >[];

    void diffAttributes(
      List<BusinessAttribute> beforeAttrs,
      List<BusinessAttribute> afterAttrs,
      String parentPath,
    ) {
      for (final bAttr in beforeAttrs) {
        final path = parentPath.isEmpty ? bAttr.name : '$parentPath.${bAttr.name}';
        final aAttr =
            afterAttrs.where((a) => a.id == bAttr.id).firstOrNull ??
            afterAttrs
                .where((a) => a.name.toLowerCase() == bAttr.name.toLowerCase())
                .firstOrNull;
        if (aAttr == null) {
          mutations.add((
            path: path,
            leafName: bAttr.name,
            isRemoved: true,
            typeTransitionLabel: null,
          ));
          continue;
        }
        if (bAttr.type != aAttr.type || bAttr.isArray != aAttr.isArray) {
          final beforeType =
              '${bAttr.type.dslKeyword}${bAttr.isArray ? '[]' : ''}';
          final afterType =
              '${aAttr.type.dslKeyword}${aAttr.isArray ? '[]' : ''}';
          mutations.add((
            path: path,
            leafName: bAttr.name,
            isRemoved: false,
            typeTransitionLabel: '$beforeType → $afterType',
          ));
        }
        if (bAttr.children.isNotEmpty) {
          diffAttributes(bAttr.children, aAttr.children, path);
        }
      }
    }

    diffAttributes(beforeObject.attributes, afterObject.attributes, '');

    for (final bRel in beforeObject.relations) {
      final stillInRelations = afterObject.relations.any(
        (r) => r.id == bRel.id || r.name.toLowerCase() == bRel.name.toLowerCase(),
      );
      final convertedToAttr = afterObject.attributes.any(
        (a) => a.name.toLowerCase() == bRel.name.toLowerCase(),
      );
      if (!stillInRelations && !convertedToAttr) {
        mutations.add((
          path: bRel.name,
          leafName: bRel.name,
          isRemoved: true,
          typeTransitionLabel: null,
        ));
      }
    }

    if (mutations.isEmpty) {
      return const <String>[];
    }

    final objAliasesLower = <String>{
      beforeObject.id.trim().toLowerCase(),
      beforeObject.technicalName.trim().toLowerCase(),
      beforeObject.name.trim().toLowerCase(),
      afterObject.id.trim().toLowerCase(),
      afterObject.technicalName.trim().toLowerCase(),
    }..remove('');

    bool matchesObjectRef(String rawRef) {
      final clean = rawRef.trim().toLowerCase();
      return clean.isNotEmpty && objAliasesLower.contains(clean);
    }

    final warnings = <String>[];
    final seenWarnings = <String>{};
    void addWarning(String message) {
      if (seenWarnings.add(message)) {
        warnings.add(message);
      }
    }

    for (final m in mutations) {
      final pathLower = m.path.toLowerCase();
      final leafLower = m.leafName.toLowerCase();
      final wordRegex = m.leafName.length >= 3
          ? RegExp('\\b${RegExp.escape(m.leafName)}\\b', caseSensitive: false)
          : null;
      final changeDesc = m.isRemoved
          ? 'supprimé « ${m.path} »'
          : 'retypé « ${m.path} » (${m.typeTransitionLabel})';

      // 1. Règles de gestion locales (businessRules).
      for (final rule in targetFeature.businessRules) {
        final ruleTargetsObject = rule.targetObjectIds.any(matchesObjectRef);
        var referencesAttr = false;
        var hasObjPrefixRef = false;

        for (final targetAttr in rule.targetAttributes) {
          final clean = targetAttr.trim();
          if (clean.isEmpty) continue;
          final dot = clean.indexOf('.');
          if (dot > 0) {
            final prefix = clean.substring(0, dot);
            final suffix = clean.substring(dot + 1).trim().toLowerCase();
            if (matchesObjectRef(prefix)) {
              hasObjPrefixRef = true;
              if (suffix == pathLower ||
                  suffix == leafLower ||
                  suffix.startsWith('$pathLower.')) {
                referencesAttr = true;
                break;
              }
            }
          } else if (ruleTargetsObject) {
            final attrLower = clean.toLowerCase();
            if (attrLower == pathLower || attrLower == leafLower) {
              referencesAttr = true;
              break;
            }
          }
        }

        if (!referencesAttr &&
            (ruleTargetsObject || hasObjPrefixRef) &&
            wordRegex != null) {
          final corpus = <String>[
            rule.condition,
            rule.effect,
            rule.trigger,
            rule.description,
          ].join(' ');
          if (wordRegex.hasMatch(corpus)) {
            referencesAttr = true;
          }
        }

        if (referencesAttr) {
          final ruleLabel = rule.code.trim().isNotEmpty
              ? rule.code.trim()
              : rule.id;
          addWarning(
            'L’attribut $changeDesc est référencé par la règle de gestion '
            '$ruleLabel (« ${rule.title} »).',
          );
        }
      }

      // 2. Écrans UX locaux (uxSpec.screens).
      for (final screen in targetFeature.uxSpec.screens) {
        final screenTargetsObj = matchesObjectRef(screen.primaryObjectId);
        final screenLabel = screen.code.trim().isNotEmpty
            ? screen.code.trim()
            : screen.id;

        for (final zone in screen.zones) {
          for (final slot in zone.slots) {
            final slotTargetsObj = slot.businessObjectId.trim().isNotEmpty
                ? matchesObjectRef(slot.businessObjectId)
                : screenTargetsObj;
            if (!slotTargetsObj) continue;

            final usesAttr = slot.attributeNames.any((rawAttr) {
              final clean = rawAttr.trim().toLowerCase();
              return clean == pathLower ||
                  clean == leafLower ||
                  clean.startsWith('$pathLower.');
            });
            if (usesAttr) {
              addWarning(
                'L’attribut $changeDesc est utilisé dans l’écran UX '
                '$screenLabel (« ${screen.name} », bloc « ${slot.title} »).',
              );
            }
          }
        }
      }

      // 3. Spécification QA locale (qaSpec : fixtures, suites TDD, features Gherkin).
      final objectFixtureIdsLower = <String>{};
      for (final fixture in targetFeature.qaSpec.fixtures) {
        if (!matchesObjectRef(fixture.businessObjectId)) continue;
        objectFixtureIdsLower.add(fixture.id.trim().toLowerCase());
        if (fixture.code.trim().isNotEmpty) {
          objectFixtureIdsLower.add(fixture.code.trim().toLowerCase());
        }
        if (_payloadContainsAttributePath(fixture.payload, m.path, m.leafName)) {
          final fixLabel = fixture.code.trim().isNotEmpty
              ? fixture.code.trim()
              : fixture.id;
          addWarning(
            'L’attribut $changeDesc est renseigné dans le jeu d’essai QA '
            '$fixLabel (« ${fixture.name} »).',
          );
        }
      }

      for (final suite in targetFeature.qaSpec.tddSuites) {
        final suiteTargetsObj = matchesObjectRef(suite.targetObjectId);
        final suiteUsesObjFixture = suite.cases.any(
          (c) =>
              c.fixtureId.trim().isNotEmpty &&
              objectFixtureIdsLower.contains(c.fixtureId.trim().toLowerCase()),
        );
        if (!suiteTargetsObj && !suiteUsesObjFixture) continue;
        if (wordRegex == null) continue;

        final matchedCase = suite.cases.where((c) {
          final corpus = <String>[
            c.title,
            c.arrange,
            c.act,
            c.assertExpected,
            c.expectedErrorMessage,
          ].join(' ');
          return wordRegex.hasMatch(corpus);
        }).firstOrNull;

        if (matchedCase != null || wordRegex.hasMatch(suite.description)) {
          final suiteLabel = suite.code.trim().isNotEmpty
              ? suite.code.trim()
              : suite.id;
          addWarning(
            'L’attribut $changeDesc est référencé dans la suite TDD '
            '$suiteLabel (« ${suite.name} »).',
          );
        }
      }

      for (final ghkFeature in targetFeature.qaSpec.features) {
        final ghkLabel = ghkFeature.code.trim().isNotEmpty
            ? ghkFeature.code.trim()
            : ghkFeature.id;
        for (final scenario in ghkFeature.scenarios) {
          final linksObjFixture = scenario.fixtureIds.any(
            (fid) => objectFixtureIdsLower.contains(fid.trim().toLowerCase()),
          );
          final mentionsHeader = scenario.examples.headers.any(
            (h) => h.trim().toLowerCase() == leafLower,
          );
          final stepsCorpus = <String>[
            scenario.title,
            for (final step in scenario.steps) step.text,
            for (final step in scenario.steps) step.docString,
          ].join(' ');
          final mentionsObjInSteps =
              beforeObject.technicalName.length >= 3 &&
              RegExp(
                '\\b${RegExp.escape(beforeObject.technicalName)}\\b',
                caseSensitive: false,
              ).hasMatch(stepsCorpus);

          if ((linksObjFixture || mentionsObjInSteps) &&
              (mentionsHeader ||
                  (wordRegex != null && wordRegex.hasMatch(stepsCorpus)))) {
            addWarning(
              'L’attribut $changeDesc est référencé dans le scénario Gherkin '
              '« ${scenario.title} » ($ghkLabel).',
            );
          }
        }
      }
    }

    return warnings;
  }

  static bool _payloadContainsAttributePath(
    Map<String, Object?> payload,
    String dottedPath,
    String leafName,
  ) {
    if (payload.isEmpty) return false;
    final segments = dottedPath.split('.');
    Object? current = payload;
    var foundDotted = true;
    for (final segment in segments) {
      if (current is Map) {
        final segLower = segment.toLowerCase();
        Object? matchedVal;
        var matched = false;
        for (final entry in current.entries) {
          if ('${entry.key}'.trim().toLowerCase() == segLower) {
            matched = true;
            matchedVal = entry.value;
            break;
          }
        }
        if (!matched) {
          foundDotted = false;
          break;
        }
        current = matchedVal;
      } else {
        foundDotted = false;
        break;
      }
    }
    if (foundDotted) return true;

    if (segments.length == 1) {
      final leafLower = leafName.toLowerCase();
      return payload.keys.any((k) => k.trim().toLowerCase() == leafLower);
    }
    return false;
  }
}
