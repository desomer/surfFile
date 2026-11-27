/// Analyseur déterministe de dérive amont entre un projet de spécification
/// ([SpecForgeProject]) et un domaine fonctionnel de l'espace Design
/// ([SpecDesignDriftAnalyzer]).
library;

import 'package:flutter/foundation.dart';

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/domain_catalog.dart';
import '../models/domain_contracts.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_initiative.dart';
import '../models/spec_origin_baseline.dart';
import 'spec_design_merge_engine.dart';
import 'spec_design_promoter.dart';

/// État de synchronisation d'une entrée de contrat Design vis-à-vis de la Spec.
enum ContractSpecDriftStatus {
  /// Le contrat est aligné avec la dernière photographie Spec connue (ou la Spec courante).
  inSync('Synchronisé'),

  /// L'objet métier source ou l'une de ses règles liées a évolué dans la Spec.
  specModified('Spec modifiée'),

  /// L'objet métier d'origine promu depuis ce projet a été supprimé côté Spec.
  missingInSpec('Supprimé de la Spec'),

  /// Contrat propre au Design (ex. DTO dédié ou entité sans objet Spec associé).
  designOnly('Propre au Design');

  /// Construit un statut de dérive de contrat.
  const ContractSpecDriftStatus(this.label);

  /// Libellé court en français affiché dans les badges.
  final String label;

  /// Vrai lorsque le contrat présente un écart avec la Spec (`specModified` ou `missingInSpec`).
  bool get hasDrift =>
      this == ContractSpecDriftStatus.specModified ||
      this == ContractSpecDriftStatus.missingInSpec;
}

/// Nature d'une référence documentaire vers la spécification fonctionnelle.
enum SpecRefKind {
  /// Règle de gestion (`RG-xxx`).
  businessRule('Règle de gestion'),

  /// Exigence fonctionnelle (`EXF-xxx` / `EF-xxx`).
  functionalRequirement('Exigence fonctionnelle'),

  /// Exigence non fonctionnelle (`ENF-xxx`).
  nonFunctionalRequirement('Exigence non fonctionnelle'),

  /// Cas d'usage du cahier des charges (`UC-xxx`).
  useCase('Cas d’usage Spec'),

  /// Référence Spec non reconnue.
  unknown('Référence Spec');

  /// Construit une catégorie de référence Spec.
  const SpecRefKind(this.label);

  /// Libellé lisible en français.
  final String label;
}

/// Nature de la dérive relevée sur une référence Spec amont (`RG-xxx`, `EXF-xxx`, `UC-xxx`).
enum SpecRefDriftStatus {
  /// La règle ou exigence existe toujours mais son contenu (ou son statut actif) a changé.
  modifiedInSpec('Modifiée dans la Spec'),

  /// La règle, l'exigence ou le cas d'usage référencé n'existe plus dans la Spec.
  missingInSpec('Introuvable dans la Spec'),

  /// Une nouvelle règle de gestion ciblant l'objet métier a été ajoutée dans la Spec après promotion.
  addedInSpec('Nouvelle règle dans la Spec');

  /// Construit un statut de dérive de référence Spec.
  const SpecRefDriftStatus(this.label);

  /// Libellé court en français.
  final String label;
}

/// Dérive détectée sur une référence amont (`RG-xxx`, `EXF-xxx`, `ENF-xxx`, `UC-xxx`)
/// rattachée à un contrat ou à un Use Case applicatif Design.
@immutable
class LinkedSpecRefDrift {
  /// Crée un diagnostic immuable de dérive sur une référence Spec.
  const LinkedSpecRefDrift({
    required this.refCode,
    required this.refKind,
    required this.status,
    required this.ownerKind,
    required this.ownerId,
    required this.ownerName,
    required this.summary,
  });

  /// Code ou identifiant de la référence Spec (ex. `RG-001`, `EXF-002`, `UC-001`).
  final String refCode;

  /// Catégorie fonctionnelle de la référence Spec.
  final SpecRefKind refKind;

  /// Statut de dérive constaté (`modifiedInSpec`, `missingInSpec`, `addedInSpec`).
  final SpecRefDriftStatus status;

  /// Type d'artefact Design porteur du lien (`contract` ou `useCase`).
  final String ownerKind;

  /// Identifiant stable de l'entrée de contrat ou du Use Case applicatif Design.
  final String ownerId;

  /// Libellé ou nom technique de l'artefact Design porteur.
  final String ownerName;

  /// Explication en français prête à être affichée dans l'interface.
  final String summary;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkedSpecRefDrift &&
          other.refCode == refCode &&
          other.refKind == refKind &&
          other.status == status &&
          other.ownerKind == ownerKind &&
          other.ownerId == ownerId &&
          other.ownerName == ownerName &&
          other.summary == summary;

  @override
  int get hashCode => Object.hash(
    refCode,
    refKind,
    status,
    ownerKind,
    ownerId,
    ownerName,
    summary,
  );
}

/// Diagnostic complet de dérive Spec ↔ Design pour une entrée de `DomainContracts`.
@immutable
class ContractSpecDrift {
  /// Crée un diagnostic immuable de dérive pour une entrée de contrat.
  ContractSpecDrift({
    required this.entryId,
    required this.entryName,
    required this.contractType,
    required this.status,
    this.specOrigin,
    this.currentSpecObject,
    List<String> addedAttributeNames = const <String>[],
    List<String> updatedAttributeNames = const <String>[],
    List<String> removedAttributeNames = const <String>[],
    this.metadataChanged = false,
    List<LinkedSpecRefDrift> ruleDrifts = const <LinkedSpecRefDrift>[],
    this.previewMergeResult,
    required this.summary,
  }) : addedAttributeNames = List<String>.unmodifiable(addedAttributeNames),
       updatedAttributeNames = List<String>.unmodifiable(updatedAttributeNames),
       removedAttributeNames = List<String>.unmodifiable(removedAttributeNames),
       ruleDrifts = List<LinkedSpecRefDrift>.unmodifiable(ruleDrifts);

  /// Identifiant stable (`JsonNode.id`) de l'entrée dans `DomainContracts`.
  final String entryId;

  /// Nom DSL de l'entrée (ex. `CommandeClient`).
  final String entryName;

  /// Type DSL de l'entrée (ex. `model`, `component`, `xresponsedto`).
  final String contractType;

  /// Statut synthétique de synchronisation avec la Spec.
  final ContractSpecDriftStatus status;

  /// Photographie d'origine enregistrée lors de la dernière promotion, si présente.
  final SpecOriginBaseline? specOrigin;

  /// Objet métier actuel résolu dans le projet Spec (`null` si supprimé ou `designOnly`).
  final BusinessObjectSpec? currentSpecObject;

  /// Chemins des attributs (ou relations) ajoutés dans la Spec depuis la promotion.
  final List<String> addedAttributeNames;

  /// Chemins des attributs modifiés dans la Spec depuis la promotion.
  final List<String> updatedAttributeNames;

  /// Chemins des attributs supprimés dans la Spec depuis la promotion.
  final List<String> removedAttributeNames;

  /// Vrai lorsque le nom, la description, la nature d'agrégat ou le cycle de vie a changé côté Spec.
  final bool metadataChanged;

  /// Dérives relevées sur les règles `RG-xxx` rattachées à ce contrat.
  final List<LinkedSpecRefDrift> ruleDrifts;

  /// Aperçu pré-calculé de la fusion 3-voies si une re-promotion était lancée.
  final ObjectMergeResult? previewMergeResult;

  /// Résumé lisible en français de l'état de synchronisation.
  final String summary;

  /// Vrai dès qu'une dérive structurelle ou réglementaire est détectée.
  bool get hasDrift => status.hasDrift || ruleDrifts.isNotEmpty;

  /// Vrai lorsque l'objet métier source a disparu du projet Spec.
  bool get isMissingInSpec => status == ContractSpecDriftStatus.missingInSpec;

  /// Vrai lorsque l'objet métier source (ou ses règles) a évolué dans la Spec.
  bool get isSpecModified => status == ContractSpecDriftStatus.specModified;

  /// Vrai lorsque le contrat est aligné avec la Spec sans dérive de règle.
  bool get isInSync =>
      status == ContractSpecDriftStatus.inSync && ruleDrifts.isEmpty;

  /// Vrai lorsque le contrat a été rapproché par `technicalName` sans `specOrigin` persisté.
  bool get hasLegacyMatchWithoutBaseline =>
      specOrigin == null && currentSpecObject != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContractSpecDrift &&
          other.entryId == entryId &&
          other.entryName == entryName &&
          other.contractType == contractType &&
          other.status == status &&
          other.specOrigin == specOrigin &&
          other.currentSpecObject == currentSpecObject &&
          listEquals(other.addedAttributeNames, addedAttributeNames) &&
          listEquals(other.updatedAttributeNames, updatedAttributeNames) &&
          listEquals(other.removedAttributeNames, removedAttributeNames) &&
          other.metadataChanged == metadataChanged &&
          listEquals(other.ruleDrifts, ruleDrifts) &&
          other.previewMergeResult == previewMergeResult &&
          other.summary == summary;

  @override
  int get hashCode => Object.hash(
    entryId,
    entryName,
    contractType,
    status,
    specOrigin,
    currentSpecObject,
    Object.hashAll(addedAttributeNames),
    Object.hashAll(updatedAttributeNames),
    Object.hashAll(removedAttributeNames),
    metadataChanged,
    Object.hashAll(ruleDrifts),
    previewMergeResult,
    summary,
  );
}

/// Rapport consolidé de dérive Spec ↔ Design à l'échelle d'un [FunctionalDomain].
@immutable
class DomainSpecDriftReport {
  /// Crée un rapport immuable de dérive Spec ↔ Design pour un domaine.
  DomainSpecDriftReport({
    required this.projectId,
    required this.domainId,
    required this.domainName,
    List<ContractSpecDrift> contractDrifts = const <ContractSpecDrift>[],
    List<LinkedSpecRefDrift> linkedSpecRefDrifts = const <LinkedSpecRefDrift>[],
    List<BusinessObjectSpec> unpromotedSpecObjects =
        const <BusinessObjectSpec>[],
  }) : contractDrifts = List<ContractSpecDrift>.unmodifiable(contractDrifts),
       linkedSpecRefDrifts = List<LinkedSpecRefDrift>.unmodifiable(
         linkedSpecRefDrifts,
       ),
       unpromotedSpecObjects = List<BusinessObjectSpec>.unmodifiable(
         unpromotedSpecObjects,
       );

  /// Identifiant du projet Spec comparé.
  final String projectId;

  /// Identifiant du domaine fonctionnel analysé.
  final String domainId;

  /// Nom affiché du domaine fonctionnel analysé.
  final String domainName;

  /// Diagnostics de dérive pour chaque entrée de `domain.contracts`.
  final List<ContractSpecDrift> contractDrifts;

  /// Ensemble des dérives sur les références Spec (`RG-xxx`, `EXF-xxx`, `UC-xxx`)
  /// portées tant par les contrats que par les Use Cases applicatifs du domaine.
  final List<LinkedSpecRefDrift> linkedSpecRefDrifts;

  /// Objets métiers de la feature active du projet Spec qui ne sont encore promus
  /// dans aucun domaine du catalogue analysé.
  final List<BusinessObjectSpec> unpromotedSpecObjects;

  /// Contrats présentant une dérive effective (`specModified` ou `missingInSpec`).
  List<ContractSpecDrift> get driftedContracts =>
      contractDrifts.where((c) => c.hasDrift).toList(growable: false);

  /// Nombre de contrats présentant une dérive avec la Spec.
  int get driftedContractsCount =>
      contractDrifts.where((c) => c.hasDrift).length;

  /// Nombre de contrats dont l'objet Spec d'origine a été supprimé.
  int get missingInSpecCount =>
      contractDrifts.where((c) => c.isMissingInSpec).length;

  /// Nombre de contrats dont l'objet Spec ou les règles liées ont été modifiés.
  int get modifiedInSpecCount =>
      contractDrifts.where((c) => c.isSpecModified).length;

  /// Vrai si au moins un contrat ou une référence `RG`/`EXF`/`UC` est en dérive.
  bool get hasAnyDrift =>
      driftedContractsCount > 0 || linkedSpecRefDrifts.isNotEmpty;

  /// Vrai si la Spec contient des objets métiers non encore promus en Design.
  bool get hasUnpromotedSpecObjects => unpromotedSpecObjects.isNotEmpty;

  /// Recherche le diagnostic de dérive du contrat d'identifiant [entryId].
  ContractSpecDrift? driftForEntry(String entryId) =>
      contractDrifts.where((c) => c.entryId == entryId).firstOrNull;

  /// Recherche le diagnostic d'un contrat rattaché à l'objet Spec [specObjectId].
  ContractSpecDrift? driftForSpecObject(String specObjectId) => contractDrifts
      .where(
        (c) =>
            c.specOrigin?.specObjectId == specObjectId ||
            c.currentSpecObject?.id == specObjectId,
      )
      .firstOrNull;

  /// Retourne les dérives de références amont affectant le Use Case applicatif [useCaseId].
  List<LinkedSpecRefDrift> driftsForUseCase(String useCaseId) =>
      linkedSpecRefDrifts
          .where((d) => d.ownerKind == 'useCase' && d.ownerId == useCaseId)
          .toList(growable: false);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainSpecDriftReport &&
          other.projectId == projectId &&
          other.domainId == domainId &&
          other.domainName == domainName &&
          listEquals(other.contractDrifts, contractDrifts) &&
          listEquals(other.linkedSpecRefDrifts, linkedSpecRefDrifts) &&
          listEquals(other.unpromotedSpecObjects, unpromotedSpecObjects);

  @override
  int get hashCode => Object.hash(
    projectId,
    domainId,
    domainName,
    Object.hashAll(contractDrifts),
    Object.hashAll(linkedSpecRefDrifts),
    Object.hashAll(unpromotedSpecObjects),
  );
}

/// Service pur d'analyse de dérive entre [SpecForgeProject] et [FunctionalDomain].
abstract final class SpecDesignDriftAnalyzer {
  static final RegExp _positionalUseCaseCodePattern = RegExp(
    r'^uc[-_]?0*(\d+)$',
    caseSensitive: false,
  );

  /// Analyse les dérives entre [project] et un [domain] fonctionnel Design
  /// (contrats promus, règles `RG-xxx` liées, références `linkedSpecRefs` des
  /// Use Cases applicatifs et objets Spec non encore promus).
  static DomainSpecDriftReport analyzeDomain({
    required SpecForgeProject project,
    required FunctionalDomain domain,
    DomainCatalog? catalog,
  }) {
    final effectiveCatalog =
        catalog ?? DomainCatalog(domains: <FunctionalDomain>[domain]);
    final contracts = domain.contracts;
    final availableVos = effectiveCatalog.resolvedValueObjectsForDomain(
      domain.id,
    );

    final contractDrifts = <ContractSpecDrift>[];
    final allRefDrifts = <LinkedSpecRefDrift>[];

    // Collecte les empreintes de règles connues à travers les baselines du domaine
    // (et du catalogue s'il est fourni) pour enrichir aussi l'audit des Use Cases.
    final baselineRuleFingerprintsByCodeLower = <String, String>{};
    for (final d in effectiveCatalog.domains) {
      final doc = d.contracts;
      if (doc == null) continue;
      for (final detail in doc.details.values) {
        final origin = detail.specOrigin;
        if (origin == null || origin.projectId != project.id) continue;
        for (final entry in origin.ruleFingerprints.entries) {
          baselineRuleFingerprintsByCodeLower.putIfAbsent(
            entry.key.trim().toLowerCase(),
            () => entry.value,
          );
        }
      }
    }

    if (contracts != null) {
      for (final group in contracts.groups) {
        for (final entry in group.children) {
          final detail =
              contracts.details[entry.id] ?? ContractDetails.defaults;
          final origin = detail.specOrigin;
          final resolved = _resolveSpecObjectForEntry(
            project: project,
            contracts: contracts,
            entryId: entry.id,
            entryTechnicalName: DomainContracts.technicalNameOf(entry),
            origin: origin,
          );

          if (resolved.isMissingInSpec) {
            final ruleDrifts = _inspectContractRuleFingerprints(
              project: project,
              sourceFeature: resolved.sourceFeature,
              origin: origin!,
              specObject: null,
              entryId: entry.id,
              entryName: entry.name,
            );
            allRefDrifts.addAll(ruleDrifts);
            contractDrifts.add(
              ContractSpecDrift(
                entryId: entry.id,
                entryName: entry.name,
                contractType: entry.type,
                status: ContractSpecDriftStatus.missingInSpec,
                specOrigin: origin,
                addedAttributeNames: const <String>[],
                updatedAttributeNames: const <String>[],
                removedAttributeNames: const <String>[],
                ruleDrifts: ruleDrifts,
                summary:
                    'L’objet métier source « ${origin.baseSpecObject.name} » (${origin.specObjectId}) a été supprimé du projet Spec.',
              ),
            );
            continue;
          }

          final specObj = resolved.specObject;
          if (specObj == null) {
            contractDrifts.add(
              ContractSpecDrift(
                entryId: entry.id,
                entryName: entry.name,
                contractType: entry.type,
                status: ContractSpecDriftStatus.designOnly,
                specOrigin: origin,
                summary: 'Contrat propre au Design (sans objet Spec lié).',
              ),
            );
            continue;
          }

          final currentDesign = contracts.objectFor(entry);
          final resolvedSpecForDomain =
              SpecDesignPromoter.resolveSpecObjectForDomainEntry(
                project: project,
                catalog: effectiveCatalog,
                domain: domain,
                entry: entry,
                specObject: specObj,
              );
          final hasSameProjectBaseline =
              origin != null && origin.projectId == project.id;
          final previewMerge = SpecDesignMergeEngine.merge(
            baseSpec: hasSameProjectBaseline ? origin.baseSpecObject : null,
            nextSpecResolved: resolvedSpecForDomain,
            nextSpec: specObj,
            currentDesign: currentDesign,
            availableValueObjects: availableVos,
          );

          final ruleDrifts = hasSameProjectBaseline
              ? _inspectContractRuleFingerprints(
                  project: project,
                  sourceFeature: resolved.sourceFeature,
                  origin: origin,
                  specObject: specObj,
                  entryId: entry.id,
                  entryName: entry.name,
                )
              : const <LinkedSpecRefDrift>[];
          allRefDrifts.addAll(ruleDrifts);

          if (hasSameProjectBaseline) {
            final specDiff = _diffSpecObjects(origin.baseSpecObject, specObj);
            final drifted = specDiff.hasAnyChange || ruleDrifts.isNotEmpty;
            contractDrifts.add(
              ContractSpecDrift(
                entryId: entry.id,
                entryName: entry.name,
                contractType: entry.type,
                status: drifted
                    ? ContractSpecDriftStatus.specModified
                    : ContractSpecDriftStatus.inSync,
                specOrigin: origin,
                currentSpecObject: specObj,
                addedAttributeNames: specDiff.added,
                updatedAttributeNames: specDiff.updated,
                removedAttributeNames: specDiff.removed,
                metadataChanged: specDiff.metadataChanged,
                ruleDrifts: ruleDrifts,
                previewMergeResult: previewMerge,
                summary: drifted
                    ? _formatDriftSummary(
                        addedCount: specDiff.added.length,
                        updatedCount: specDiff.updated.length,
                        removedCount: specDiff.removed.length,
                        metadataChanged: specDiff.metadataChanged,
                        ruleDriftsCount: ruleDrifts.length,
                      )
                    : 'Synchronisé avec la Spec.',
              ),
            );
          } else {
            final added = <String>[
              for (final d in previewMerge.decisions)
                if (d.kind == AttributeMergeKind.addedFromSpec) d.attributePath,
            ];
            final updated = <String>[
              for (final d in previewMerge.decisions)
                if (d.kind == AttributeMergeKind.updatedFromSpec ||
                    d.kind == AttributeMergeKind.conflictKeptDesign ||
                    (d.kind == AttributeMergeKind.preservedDesignValueObject &&
                        d.beforeAttribute != d.afterAttribute))
                  d.attributePath,
            ];
            final removed = <String>[
              for (final d in previewMerge.decisions)
                if (d.kind == AttributeMergeKind.removedFromSpec)
                  d.attributePath,
            ];
            final metadataChanged =
                previewMerge.mergedObject.description !=
                    currentDesign.description ||
                !listEquals(
                  previewMerge.mergedObject.lifecycleStates,
                  currentDesign.lifecycleStates,
                ) ||
                !listEquals(
                  previewMerge.mergedObject.lifecycleTransitions,
                  currentDesign.lifecycleTransitions,
                );
            final drifted = previewMerge.hasChanges;
            contractDrifts.add(
              ContractSpecDrift(
                entryId: entry.id,
                entryName: entry.name,
                contractType: entry.type,
                status: drifted
                    ? ContractSpecDriftStatus.specModified
                    : ContractSpecDriftStatus.inSync,
                specOrigin: origin,
                currentSpecObject: specObj,
                addedAttributeNames: added,
                updatedAttributeNames: updated,
                removedAttributeNames: removed,
                metadataChanged: metadataChanged,
                previewMergeResult: previewMerge,
                summary: drifted
                    ? _formatDriftSummary(
                        addedCount: added.length,
                        updatedCount: updated.length,
                        removedCount: removed.length,
                        metadataChanged: metadataChanged,
                        ruleDriftsCount: 0,
                      )
                    : 'Aligné avec l’objet Spec correspondant.',
              ),
            );
          }
        }
      }
    }

    // Analyse des références linkedSpecRefs (RG-xxx, EXF-xxx, ENF-xxx, UC-xxx)
    // sur les Use Cases applicatifs du domaine.
    final orchestration = domain.useCaseOrchestration;
    if (orchestration != null) {
      for (final appUc in orchestration.useCases) {
        final ownerName = appUc.code.trim().isNotEmpty
            ? '${appUc.code.trim()} · ${appUc.name}'
            : appUc.name;
        for (final rawRef in appUc.linkedSpecRefs) {
          final ref = rawRef.trim();
          if (ref.isEmpty) continue;
          final refDrift = _inspectUseCaseLinkedSpecRef(
            project: project,
            ref: ref,
            useCaseId: appUc.id,
            useCaseDisplayName: ownerName,
            baselineRuleFingerprintsByCodeLower:
                baselineRuleFingerprintsByCodeLower,
          );
          if (refDrift != null) {
            allRefDrifts.add(refDrift);
          }
        }
      }
    }

    // Détection des objets métiers Spec de la feature active non encore promus.
    final unpromoted = <BusinessObjectSpec>[
      for (final specObj in project.businessObjects)
        if (!effectiveCatalog.domains.any(
          (d) =>
              SpecDesignPromoter.findEntryForSpecObject(
                d.contracts,
                specObj,
                projectId: project.id,
              ) !=
              null,
        ))
          specObj,
    ];

    return DomainSpecDriftReport(
      projectId: project.id,
      domainId: domain.id,
      domainName: domain.name,
      contractDrifts: contractDrifts,
      linkedSpecRefDrifts: allRefDrifts,
      unpromotedSpecObjects: unpromoted,
    );
  }

  /// Exécute [analyzeDomain] pour chacun des domaines de [catalog] et retourne
  /// les rapports indexés par `domain.id`.
  static Map<String, DomainSpecDriftReport> analyzeCatalog({
    required SpecForgeProject project,
    required DomainCatalog catalog,
  }) => Map<String, DomainSpecDriftReport>.unmodifiable(<
    String,
    DomainSpecDriftReport
  >{
    for (final domain in catalog.domains)
      domain.id: analyzeDomain(
        project: project,
        domain: domain,
        catalog: catalog,
      ),
  });

  static ({
    BusinessObjectSpec? specObject,
    SpecFeatureSpec? sourceFeature,
    bool isMissingInSpec,
  })
  _resolveSpecObjectForEntry({
    required SpecForgeProject project,
    required DomainContracts contracts,
    required String entryId,
    required String entryTechnicalName,
    required SpecOriginBaseline? origin,
  }) {
    final techLower = entryTechnicalName.trim().toLowerCase();

    if (origin != null && origin.projectId == project.id) {
      final preferredFeature = origin.featureId.isNotEmpty
          ? project.featureById(origin.featureId)
          : project.activeFeature;

      if (preferredFeature != null) {
        final byId = preferredFeature.businessObjects
            .where((o) => o.id == origin.specObjectId)
            .firstOrNull;
        if (byId != null) {
          return (
            specObject: byId,
            sourceFeature: preferredFeature,
            isMissingInSpec: false,
          );
        }
      }

      for (final feature in project.allFeatures) {
        final byId = feature.businessObjects
            .where((o) => o.id == origin.specObjectId)
            .firstOrNull;
        if (byId != null) {
          return (
            specObject: byId,
            sourceFeature: feature,
            isMissingInSpec: false,
          );
        }
      }

      // Repli si l'objet a été recréé avec le même technicalName dans la Spec.
      final byTechInActive = project.businessObjects
          .where((o) => o.technicalName.toLowerCase() == techLower)
          .firstOrNull;
      if (byTechInActive != null) {
        return (
          specObject: byTechInActive,
          sourceFeature: project.activeFeature,
          isMissingInSpec: false,
        );
      }
      if (preferredFeature != null) {
        final byTechInPref = preferredFeature.businessObjects
            .where((o) => o.technicalName.toLowerCase() == techLower)
            .firstOrNull;
        if (byTechInPref != null) {
          return (
            specObject: byTechInPref,
            sourceFeature: preferredFeature,
            isMissingInSpec: false,
          );
        }
      }

      return (
        specObject: null,
        sourceFeature: preferredFeature,
        isMissingInSpec: true,
      );
    }

    // Sans baseline du projet courant : rapprochement par technicalName dans la feature active.
    final fallbackObj = project.businessObjects
        .where((o) => o.technicalName.toLowerCase() == techLower)
        .firstOrNull;
    if (fallbackObj != null) {
      return (
        specObject: fallbackObj,
        sourceFeature: project.activeFeature,
        isMissingInSpec: false,
      );
    }

    return (specObject: null, sourceFeature: null, isMissingInSpec: false);
  }

  static List<LinkedSpecRefDrift> _inspectContractRuleFingerprints({
    required SpecForgeProject project,
    required SpecFeatureSpec? sourceFeature,
    required SpecOriginBaseline origin,
    required BusinessObjectSpec? specObject,
    required String entryId,
    required String entryName,
  }) {
    final drifts = <LinkedSpecRefDrift>[];
    final seenCodesLower = <String>{};

    for (final entry in origin.ruleFingerprints.entries) {
      final code = entry.key.trim();
      if (code.isEmpty) continue;
      seenCodesLower.add(code.toLowerCase());

      final rule = _findRuleInProject(
        project,
        code,
        preferredFeature: sourceFeature,
      );
      if (rule == null) {
        drifts.add(
          LinkedSpecRefDrift(
            refCode: code,
            refKind: SpecRefKind.businessRule,
            status: SpecRefDriftStatus.missingInSpec,
            ownerKind: 'contract',
            ownerId: entryId,
            ownerName: entryName,
            summary:
                'La règle de gestion « $code » liée au contrat « $entryName » a été supprimée de la Spec.',
          ),
        );
      } else {
        final currentFp = SpecOriginBaseline.computeRuleFingerprint(rule);
        if (currentFp != entry.value) {
          drifts.add(
            LinkedSpecRefDrift(
              refCode: code,
              refKind: SpecRefKind.businessRule,
              status: SpecRefDriftStatus.modifiedInSpec,
              ownerKind: 'contract',
              ownerId: entryId,
              ownerName: entryName,
              summary:
                  'La règle de gestion « $code » (${rule.title}) rattachée à « $entryName » a été modifiée dans la Spec.',
            ),
          );
        }
      }
    }

    if (specObject != null) {
      final rulesPool = (sourceFeature ?? project.activeFeature).businessRules;
      for (final rule in rulesPool) {
        if (!rule.active) continue;
        final key = rule.code.trim().isNotEmpty
            ? rule.code.trim()
            : rule.id.trim();
        if (key.isEmpty || seenCodesLower.contains(key.toLowerCase())) continue;
        if (_ruleTargetsObject(rule, specObject)) {
          seenCodesLower.add(key.toLowerCase());
          drifts.add(
            LinkedSpecRefDrift(
              refCode: key,
              refKind: SpecRefKind.businessRule,
              status: SpecRefDriftStatus.addedInSpec,
              ownerKind: 'contract',
              ownerId: entryId,
              ownerName: entryName,
              summary:
                  'Nouvelle règle de gestion « $key » (${rule.title}) ajoutée dans la Spec sur « ${specObject.name} ».',
            ),
          );
        }
      }
    }

    return drifts;
  }

  static bool _ruleTargetsObject(
    BusinessRuleSpec rule,
    BusinessObjectSpec specObject,
  ) {
    final idLower = specObject.id.trim().toLowerCase();
    final techLower = specObject.technicalName.trim().toLowerCase();
    final nameLower = specObject.name.trim().toLowerCase();
    for (final target in rule.targetObjectIds) {
      final t = target.trim().toLowerCase();
      if (t == idLower || t == techLower || t == nameLower) return true;
    }
    for (final attr in rule.targetAttributes) {
      final dot = attr.indexOf('.');
      if (dot > 0) {
        final prefix = attr.substring(0, dot).trim().toLowerCase();
        if (prefix == idLower || prefix == techLower || prefix == nameLower) {
          return true;
        }
      }
    }
    return false;
  }

  static LinkedSpecRefDrift? _inspectUseCaseLinkedSpecRef({
    required SpecForgeProject project,
    required String ref,
    required String useCaseId,
    required String useCaseDisplayName,
    required Map<String, String> baselineRuleFingerprintsByCodeLower,
  }) {
    final lower = ref.toLowerCase();
    final inferredKind = _inferSpecRefKind(lower);

    // 1. Règle de gestion (RG-xxx).
    if (inferredKind == SpecRefKind.businessRule ||
        _findRuleInProject(project, ref) != null) {
      final rule = _findRuleInProject(project, ref);
      if (rule == null) {
        return LinkedSpecRefDrift(
          refCode: ref,
          refKind: SpecRefKind.businessRule,
          status: SpecRefDriftStatus.missingInSpec,
          ownerKind: 'useCase',
          ownerId: useCaseId,
          ownerName: useCaseDisplayName,
          summary:
              'La règle « $ref » référencée par le Use Case « $useCaseDisplayName » est introuvable dans la Spec.',
        );
      }
      final codeKey = rule.code.trim().toLowerCase();
      final baselineFp =
          baselineRuleFingerprintsByCodeLower[codeKey] ??
          baselineRuleFingerprintsByCodeLower[lower];
      if (baselineFp != null &&
          SpecOriginBaseline.computeRuleFingerprint(rule) != baselineFp) {
        return LinkedSpecRefDrift(
          refCode: ref,
          refKind: SpecRefKind.businessRule,
          status: SpecRefDriftStatus.modifiedInSpec,
          ownerKind: 'useCase',
          ownerId: useCaseId,
          ownerName: useCaseDisplayName,
          summary:
              'La règle « $ref » (${rule.title}) référencée par « $useCaseDisplayName » a évolué dans la Spec.',
        );
      }
      if (!rule.active) {
        return LinkedSpecRefDrift(
          refCode: ref,
          refKind: SpecRefKind.businessRule,
          status: SpecRefDriftStatus.modifiedInSpec,
          ownerKind: 'useCase',
          ownerId: useCaseId,
          ownerName: useCaseDisplayName,
          summary:
              'La règle « $ref » (${rule.title}) référencée par « $useCaseDisplayName » est désormais désactivée dans la Spec.',
        );
      }
      return null;
    }

    // 2. Exigence fonctionnelle (EXF-xxx / EF-xxx).
    if (inferredKind == SpecRefKind.functionalRequirement ||
        _findFunctionalRequirementInProject(project, ref) != null) {
      final req = _findFunctionalRequirementInProject(project, ref);
      if (req == null) {
        return LinkedSpecRefDrift(
          refCode: ref,
          refKind: SpecRefKind.functionalRequirement,
          status: SpecRefDriftStatus.missingInSpec,
          ownerKind: 'useCase',
          ownerId: useCaseId,
          ownerName: useCaseDisplayName,
          summary:
              'L’exigence fonctionnelle « $ref » référencée par « $useCaseDisplayName » est introuvable dans le cahier des charges.',
        );
      }
      if (req.priority == RequirementPriority.wont) {
        return LinkedSpecRefDrift(
          refCode: ref,
          refKind: SpecRefKind.functionalRequirement,
          status: SpecRefDriftStatus.modifiedInSpec,
          ownerKind: 'useCase',
          ownerId: useCaseId,
          ownerName: useCaseDisplayName,
          summary:
              'L’exigence fonctionnelle « $ref » (${req.title}) liée à « $useCaseDisplayName » a été dépriorisée en Won’t.',
        );
      }
      return null;
    }

    // 3. Exigence non fonctionnelle (ENF-xxx).
    if (inferredKind == SpecRefKind.nonFunctionalRequirement ||
        _findNonFunctionalRequirementInProject(project, ref) != null) {
      final enf = _findNonFunctionalRequirementInProject(project, ref);
      if (enf == null) {
        return LinkedSpecRefDrift(
          refCode: ref,
          refKind: SpecRefKind.nonFunctionalRequirement,
          status: SpecRefDriftStatus.missingInSpec,
          ownerKind: 'useCase',
          ownerId: useCaseId,
          ownerName: useCaseDisplayName,
          summary:
              'L’exigence non fonctionnelle « $ref » référencée par « $useCaseDisplayName » est introuvable dans la Spec.',
        );
      }
      return null;
    }

    // 4. Cas d'usage du cahier des charges (UC-xxx).
    if (inferredKind == SpecRefKind.useCase ||
        _findSpecUseCaseInProject(project, ref) != null) {
      final uc = _findSpecUseCaseInProject(project, ref);
      if (uc == null) {
        return LinkedSpecRefDrift(
          refCode: ref,
          refKind: SpecRefKind.useCase,
          status: SpecRefDriftStatus.missingInSpec,
          ownerKind: 'useCase',
          ownerId: useCaseId,
          ownerName: useCaseDisplayName,
          summary:
              'Le cas d’usage Spec « $ref » référencé par « $useCaseDisplayName » est introuvable dans le cahier des charges.',
        );
      }
      return null;
    }

    // 5. Référence inconnue absente de toutes les collections Spec.
    return LinkedSpecRefDrift(
      refCode: ref,
      refKind: SpecRefKind.unknown,
      status: SpecRefDriftStatus.missingInSpec,
      ownerKind: 'useCase',
      ownerId: useCaseId,
      ownerName: useCaseDisplayName,
      summary:
          'La référence Spec « $ref » portée par « $useCaseDisplayName » est introuvable dans le projet Spec.',
    );
  }

  static SpecRefKind _inferSpecRefKind(String lowerRef) {
    if (lowerRef.startsWith('rg-') ||
        lowerRef.startsWith('rg_') ||
        lowerRef.startsWith('rule_')) {
      return SpecRefKind.businessRule;
    }
    if (lowerRef.startsWith('exf-') ||
        lowerRef.startsWith('exf_') ||
        lowerRef.startsWith('ef-') ||
        lowerRef.startsWith('ef_') ||
        lowerRef.startsWith('req_')) {
      return SpecRefKind.functionalRequirement;
    }
    if (lowerRef.startsWith('enf-') ||
        lowerRef.startsWith('enf_') ||
        lowerRef.startsWith('nfr-') ||
        lowerRef.startsWith('nfr_')) {
      return SpecRefKind.nonFunctionalRequirement;
    }
    if (lowerRef.startsWith('uc-') || lowerRef.startsWith('uc_')) {
      return SpecRefKind.useCase;
    }
    return SpecRefKind.unknown;
  }

  static BusinessRuleSpec? _findRuleInProject(
    SpecForgeProject project,
    String ref, {
    SpecFeatureSpec? preferredFeature,
  }) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;

    BusinessRuleSpec? searchIn(List<BusinessRuleSpec> list) {
      for (final r in list) {
        if (r.id.toLowerCase() == needle ||
            (r.code.trim().isNotEmpty &&
                r.code.trim().toLowerCase() == needle)) {
          return r;
        }
      }
      return null;
    }

    if (preferredFeature != null) {
      final hit = searchIn(preferredFeature.businessRules);
      if (hit != null) return hit;
    }
    final activeHit = searchIn(project.businessRules);
    if (activeHit != null) return activeHit;
    for (final f in project.allFeatures) {
      final hit = searchIn(f.businessRules);
      if (hit != null) return hit;
    }
    return null;
  }

  static FunctionalRequirement? _findFunctionalRequirementInProject(
    SpecForgeProject project,
    String ref,
  ) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;

    FunctionalRequirement? searchIn(SpecCahierDesCharges cdc) {
      for (final req in cdc.functionalRequirements) {
        if (req.id.toLowerCase() == needle ||
            (req.code.trim().isNotEmpty &&
                req.code.trim().toLowerCase() == needle)) {
          return req;
        }
      }
      return null;
    }

    final activeHit = searchIn(project.cahierDesCharges);
    if (activeHit != null) return activeHit;
    for (final f in project.allFeatures) {
      final hit = searchIn(f.cahierDesCharges);
      if (hit != null) return hit;
    }
    return null;
  }

  static NonFunctionalRequirement? _findNonFunctionalRequirementInProject(
    SpecForgeProject project,
    String ref,
  ) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;

    NonFunctionalRequirement? searchIn(SpecCahierDesCharges cdc) {
      for (final enf in cdc.nonFunctionalRequirements) {
        if (enf.id.toLowerCase() == needle ||
            (enf.code.trim().isNotEmpty &&
                enf.code.trim().toLowerCase() == needle)) {
          return enf;
        }
      }
      return null;
    }

    final activeHit = searchIn(project.cahierDesCharges);
    if (activeHit != null) return activeHit;
    for (final f in project.allFeatures) {
      final hit = searchIn(f.cahierDesCharges);
      if (hit != null) return hit;
    }
    return null;
  }

  static UseCaseSpec? _findSpecUseCaseInProject(
    SpecForgeProject project,
    String ref,
  ) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final posMatch = _positionalUseCaseCodePattern.firstMatch(needle);
    final posIndex = posMatch != null ? int.tryParse(posMatch.group(1)!) : null;

    UseCaseSpec? searchIn(SpecCahierDesCharges cdc) {
      for (final uc in cdc.useCases) {
        final idLower = uc.id.toLowerCase();
        final titleLower = uc.title.trim().toLowerCase();
        if (idLower == needle ||
            titleLower == needle ||
            titleLower.startsWith('$needle ') ||
            titleLower.startsWith('$needle:') ||
            titleLower.startsWith('$needle -') ||
            titleLower.startsWith('$needle ·')) {
          return uc;
        }
      }
      if (posIndex != null && posIndex >= 1 && posIndex <= cdc.useCases.length) {
        return cdc.useCases[posIndex - 1];
      }
      return null;
    }

    final activeHit = searchIn(project.cahierDesCharges);
    if (activeHit != null) return activeHit;
    for (final f in project.allFeatures) {
      final hit = searchIn(f.cahierDesCharges);
      if (hit != null) return hit;
    }
    return null;
  }

  static ({
    List<String> added,
    List<String> updated,
    List<String> removed,
    bool metadataChanged,
    bool hasAnyChange,
  })
  _diffSpecObjects(BusinessObjectSpec base, BusinessObjectSpec current) {
    final added = <String>[];
    final updated = <String>[];
    final removed = <String>[];

    void diffLists(
      List<BusinessAttribute> baseList,
      List<BusinessAttribute> nextList,
      String prefix,
    ) {
      final matchedBaseIndices = <int>{};
      final nextToBase = <int, int>{};

      for (var ni = 0; ni < nextList.length; ni++) {
        for (var bi = 0; bi < baseList.length; bi++) {
          if (matchedBaseIndices.contains(bi)) continue;
          if (baseList[bi].id == nextList[ni].id) {
            nextToBase[ni] = bi;
            matchedBaseIndices.add(bi);
            break;
          }
        }
      }
      for (var ni = 0; ni < nextList.length; ni++) {
        if (nextToBase.containsKey(ni)) continue;
        final lower = nextList[ni].name.toLowerCase();
        for (var bi = 0; bi < baseList.length; bi++) {
          if (matchedBaseIndices.contains(bi)) continue;
          if (baseList[bi].name.toLowerCase() == lower) {
            nextToBase[ni] = bi;
            matchedBaseIndices.add(bi);
            break;
          }
        }
      }

      for (var ni = 0; ni < nextList.length; ni++) {
        final nextAttr = nextList[ni];
        final path = prefix.isEmpty ? nextAttr.name : '$prefix.${nextAttr.name}';
        final bi = nextToBase[ni];
        if (bi == null) {
          added.add(path);
          continue;
        }
        final baseAttr = baseList[bi];
        final ownChanged =
            baseAttr.copyWith(children: const <BusinessAttribute>[]) !=
            nextAttr.copyWith(children: const <BusinessAttribute>[]);
        if (ownChanged) {
          updated.add(path);
        }
        if (baseAttr.children.isNotEmpty || nextAttr.children.isNotEmpty) {
          diffLists(baseAttr.children, nextAttr.children, path);
        }
      }

      for (var bi = 0; bi < baseList.length; bi++) {
        if (matchedBaseIndices.contains(bi)) continue;
        final baseAttr = baseList[bi];
        final path = prefix.isEmpty ? baseAttr.name : '$prefix.${baseAttr.name}';
        removed.add(path);
      }
    }

    diffLists(base.attributes, current.attributes, '');

    // Compare également les relations déclarées directement sur l'objet Spec.
    final matchedBaseRels = <int>{};
    for (final nextRel in current.relations) {
      var bi = -1;
      for (var i = 0; i < base.relations.length; i++) {
        if (matchedBaseRels.contains(i)) continue;
        if (base.relations[i].id == nextRel.id ||
            base.relations[i].name.toLowerCase() ==
                nextRel.name.toLowerCase()) {
          bi = i;
          break;
        }
      }
      if (bi < 0) {
        added.add(nextRel.name);
      } else {
        matchedBaseRels.add(bi);
        if (base.relations[bi] != nextRel) {
          updated.add(nextRel.name);
        }
      }
    }
    for (var i = 0; i < base.relations.length; i++) {
      if (!matchedBaseRels.contains(i)) {
        removed.add(base.relations[i].name);
      }
    }

    final metadataChanged =
        base.name != current.name ||
        base.technicalName != current.technicalName ||
        base.description != current.description ||
        base.aggregateRoot != current.aggregateRoot ||
        !listEquals(base.lifecycleStates, current.lifecycleStates) ||
        !listEquals(base.lifecycleTransitions, current.lifecycleTransitions);

    return (
      added: added,
      updated: updated,
      removed: removed,
      metadataChanged: metadataChanged,
      hasAnyChange:
          added.isNotEmpty ||
          updated.isNotEmpty ||
          removed.isNotEmpty ||
          metadataChanged,
    );
  }

  static String _formatDriftSummary({
    required int addedCount,
    required int updatedCount,
    required int removedCount,
    required bool metadataChanged,
    required int ruleDriftsCount,
  }) {
    final parts = <String>[
      if (addedCount > 0) '+$addedCount attr.',
      if (updatedCount > 0) '~$updatedCount modifié(s)',
      if (removedCount > 0) '-$removedCount retiré(s)',
      if (metadataChanged) 'métadonnées/cycle de vie modifiés',
      if (ruleDriftsCount > 0) '$ruleDriftsCount règle(s) RG dérivée(s)',
    ];
    return parts.isEmpty
        ? 'Spec modifiée depuis la promotion.'
        : 'Spec modifiée (${parts.join(', ')}).';
  }
}
