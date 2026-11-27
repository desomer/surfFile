/// Service de promotion des objets métiers de la Spec vers les catalogues
/// [DomainContracts] des domaines fonctionnels de l'espace Design ([SpecDesignPromoter]).
library;

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/domain_catalog.dart';
import '../models/domain_contracts.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_origin_baseline.dart';
import 'spec_design_merge_engine.dart';

/// Stratégie de résolution lorsqu'une entrée de même nom technique (ou même
/// origine Spec) existe déjà dans le domaine cible.
enum PromotionConflictResolution {
  /// Fusionne en 3-voies les évolutions de la Spec tout en conservant les
  /// Value Objects, attributs techniques et enrichissements propres au Design.
  smartMerge('Fusionner (conserver Design)'),

  /// Remplace intégralement le modèle par la projection de la Spec tout en
  /// conservant l'identifiant d'entrée et l'historique de chat IA.
  updateExisting('Écraser depuis la Spec'),

  /// Conserve l'entrée existante intacte sans l'écraser.
  skipExisting('Ignorer');

  /// Construit une stratégie de résolution de conflit.
  const PromotionConflictResolution(this.label);

  /// Libellé lisible affiché dans l'interface.
  final String label;
}

/// Choix unitaire de promotion d'un objet métier [objectId] vers un domaine Design.
@immutable
class ObjectPromotionChoice {
  /// Crée un choix de promotion pour [objectId].
  const ObjectPromotionChoice({
    required this.objectId,
    required this.domainId,
    required this.contractType,
    this.conflictResolution = PromotionConflictResolution.smartMerge,
    this.autoBumpVersion = false,
  });

  /// Identifiant de l'objet métier source dans [SpecForgeProject.businessObjects].
  final String objectId;

  /// Identifiant du [FunctionalDomain] cible, ou `null` si l'objet n'est pas promu.
  final String? domainId;

  /// Type DSL cible dans [DomainContracts.types] (ex. `model`, `component`, `part`).
  final String contractType;

  /// Stratégie appliquée si l'objet existe déjà dans le domaine cible.
  final PromotionConflictResolution conflictResolution;

  /// Indique si la version sémantique de l'entrée existante doit être incrémentée
  /// automatiquement selon l'impact structurel détecté.
  final bool autoBumpVersion;

  /// Vrai si ce choix demande effectivement une promotion vers un domaine.
  bool get isSelected => domainId != null && domainId!.trim().isNotEmpty;

  /// Copie modifiée.
  ObjectPromotionChoice copyWith({
    String? objectId,
    String? domainId,
    bool clearDomainId = false,
    String? contractType,
    PromotionConflictResolution? conflictResolution,
    bool? autoBumpVersion,
  }) => ObjectPromotionChoice(
    objectId: objectId ?? this.objectId,
    domainId: clearDomainId ? null : (domainId ?? this.domainId),
    contractType: contractType ?? this.contractType,
    conflictResolution: conflictResolution ?? this.conflictResolution,
    autoBumpVersion: autoBumpVersion ?? this.autoBumpVersion,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectPromotionChoice &&
          other.objectId == objectId &&
          other.domainId == domainId &&
          other.contractType == contractType &&
          other.conflictResolution == conflictResolution &&
          other.autoBumpVersion == autoBumpVersion;

  @override
  int get hashCode => Object.hash(
    objectId,
    domainId,
    contractType,
    conflictResolution,
    autoBumpVersion,
  );
}

/// Aperçu calculé avant exécution pour un choix de promotion [ObjectPromotionChoice].
@immutable
class ObjectPromotionPreview {
  /// Crée un aperçu immuable de promotion d'objet métier.
  const ObjectPromotionPreview({
    required this.choice,
    required this.specObject,
    required this.targetDomainId,
    required this.targetDomainName,
    required this.isNewEntry,
    this.existingEntryId,
    this.existingEntryPath,
    required this.currentVersion,
    required this.suggestedVersion,
    required this.externalRefCount,
    required this.resolvedSpecObject,
    this.mergeResult,
  });

  /// Choix de promotion évalué.
  final ObjectPromotionChoice choice;

  /// Objet métier source côté Spec.
  final BusinessObjectSpec specObject;

  /// Identifiant du domaine fonctionnel cible.
  final String targetDomainId;

  /// Nom affiché du domaine fonctionnel cible.
  final String targetDomainName;

  /// Vrai lorsqu'aucune entrée correspondante n'existe encore dans le domaine cible.
  final bool isNewEntry;

  /// Identifiant stable de l'entrée existante dans `DomainContracts`, ou `null` si création.
  final String? existingEntryId;

  /// Chemin DSL de l'entrée existante (ex. `models.Client`), ou `null` si création.
  final String? existingEntryPath;

  /// Version actuelle de l'entrée (`0.0.1` pour une création).
  final String currentVersion;

  /// Version sémantique recommandée après application du choix.
  final String suggestedVersion;

  /// Nombre de références/relations hors domaine converties en identifiant scalaire.
  final int externalRefCount;

  /// Projection résolue de l'objet Spec pour le domaine cible.
  final BusinessObjectSpec resolvedSpecObject;

  /// Résultat détaillé de la fusion 3-voies lorsque l'entrée existe déjà, ou `null` si création.
  final ObjectMergeResult? mergeResult;

  /// Vrai si l'entrée existe déjà et que la stratégie choisie est [PromotionConflictResolution.skipExisting].
  bool get willSkip =>
      !isNewEntry &&
      choice.conflictResolution == PromotionConflictResolution.skipExisting;

  /// Vrai si la promotion modifiera effectivement le catalogue du domaine cible.
  bool get hasEffectiveChanges {
    if (isNewEntry) return true;
    if (willSkip) return false;
    if (choice.conflictResolution == PromotionConflictResolution.smartMerge) {
      return mergeResult?.hasChanges ?? false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectPromotionPreview &&
          other.choice == choice &&
          other.specObject == specObject &&
          other.targetDomainId == targetDomainId &&
          other.targetDomainName == targetDomainName &&
          other.isNewEntry == isNewEntry &&
          other.existingEntryId == existingEntryId &&
          other.existingEntryPath == existingEntryPath &&
          other.currentVersion == currentVersion &&
          other.suggestedVersion == suggestedVersion &&
          other.externalRefCount == externalRefCount &&
          other.resolvedSpecObject == resolvedSpecObject &&
          other.mergeResult == mergeResult;

  @override
  int get hashCode => Object.hash(
    choice,
    specObject,
    targetDomainId,
    targetDomainName,
    isNewEntry,
    existingEntryId,
    existingEntryPath,
    currentVersion,
    suggestedVersion,
    externalRefCount,
    resolvedSpecObject,
    mergeResult,
  );
}

/// Bilan des promotions réalisées sur un [FunctionalDomain] donné.
@immutable
class DomainPromotionSummary {
  /// Crée le bilan d'un domaine.
  DomainPromotionSummary({
    required this.domainId,
    required this.domainName,
    List<String> createdEntryIds = const <String>[],
    List<String> updatedEntryIds = const <String>[],
    List<String> mergedEntryIds = const <String>[],
    List<String> skippedObjectNames = const <String>[],
    int? preservedValueObjectsCount,
    Map<String, ObjectMergeResult> mergeResultsByEntryId =
        const <String, ObjectMergeResult>{},
  }) : createdEntryIds = List<String>.unmodifiable(createdEntryIds),
       updatedEntryIds = List<String>.unmodifiable(updatedEntryIds),
       mergedEntryIds = List<String>.unmodifiable(mergedEntryIds),
       skippedObjectNames = List<String>.unmodifiable(skippedObjectNames),
       mergeResultsByEntryId = Map<String, ObjectMergeResult>.unmodifiable(
         mergeResultsByEntryId,
       ),
       preservedValueObjectsCount =
           preservedValueObjectsCount ??
           mergeResultsByEntryId.values.fold<int>(
             0,
             (sum, r) => sum + r.preservedValueObjectIds.length,
           );

  /// Identifiant du domaine cible.
  final String domainId;

  /// Nom affiché du domaine cible.
  final String domainName;

  /// Identifiants des nouvelles entrées créées dans [DomainContracts].
  final List<String> createdEntryIds;

  /// Identifiants des entrées existantes mises à jour (fusion 3-voies ou écrasement) dans [DomainContracts].
  final List<String> updatedEntryIds;

  /// Sous-ensemble des entrées mises à jour via la fusion 3-voies ([PromotionConflictResolution.smartMerge]).
  final List<String> mergedEntryIds;

  /// Noms des objets ignorés suite à un conflit en mode [PromotionConflictResolution.skipExisting].
  final List<String> skippedObjectNames;

  /// Nombre d'affectations de Value Objects conservées lors des fusions 3-voies sur ce domaine.
  final int preservedValueObjectsCount;

  /// Résultats détaillés de fusion 3-voies indexés par identifiant d'entrée (`JsonNode.id`).
  final Map<String, ObjectMergeResult> mergeResultsByEntryId;

  /// Vrai si le catalogue du domaine a été modifié (création ou mise à jour).
  bool get hasChanges =>
      createdEntryIds.isNotEmpty ||
      updatedEntryIds.isNotEmpty ||
      mergedEntryIds.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainPromotionSummary &&
          other.domainId == domainId &&
          other.domainName == domainName &&
          listEquals(other.createdEntryIds, createdEntryIds) &&
          listEquals(other.updatedEntryIds, updatedEntryIds) &&
          listEquals(other.mergedEntryIds, mergedEntryIds) &&
          listEquals(other.skippedObjectNames, skippedObjectNames) &&
          other.preservedValueObjectsCount == preservedValueObjectsCount &&
          mapEquals(other.mergeResultsByEntryId, mergeResultsByEntryId);

  @override
  int get hashCode => Object.hash(
    domainId,
    domainName,
    Object.hashAll(createdEntryIds),
    Object.hashAll(updatedEntryIds),
    Object.hashAll(mergedEntryIds),
    Object.hashAll(skippedObjectNames),
    preservedValueObjectsCount,
    Object.hashAllUnordered([
      for (final e in mergeResultsByEntryId.entries)
        Object.hash(e.key, e.value),
    ]),
  );
}

/// Résultat global d'une opération de promotion vers Design.
@immutable
class PromotionExecutionResult {
  /// Crée un résultat global de promotion.
  PromotionExecutionResult({
    required this.updatedCatalog,
    List<DomainPromotionSummary> domainSummaries =
        const <DomainPromotionSummary>[],
  }) : domainSummaries = List<DomainPromotionSummary>.unmodifiable(
         domainSummaries,
       );

  /// Nouveau [DomainCatalog] validé incluant les [DomainContracts] et le journal d'audit mis à jour.
  final DomainCatalog updatedCatalog;

  /// Détail des opérations par domaine impacté.
  final List<DomainPromotionSummary> domainSummaries;

  /// Nombre total d'entrées nouvellement créées.
  int get createdCount => domainSummaries.fold<int>(
    0,
    (sum, item) => sum + item.createdEntryIds.length,
  );

  /// Nombre total d'entrées existantes mises à jour (fusion 3-voies incluse).
  int get updatedCount => domainSummaries.fold<int>(
    0,
    (sum, item) => sum + item.updatedEntryIds.length,
  );

  /// Nombre total d'entrées fusionnées en 3-voies ([PromotionConflictResolution.smartMerge]).
  int get mergedCount => domainSummaries.fold<int>(
    0,
    (sum, item) => sum + item.mergedEntryIds.length,
  );

  /// Nombre total d'affectations de Value Objects préservées à travers les domaines.
  int get preservedValueObjectsCount => domainSummaries.fold<int>(
    0,
    (sum, item) => sum + item.preservedValueObjectsCount,
  );

  /// Résultats de fusion 3-voies agrégés par identifiant d'entrée à travers les domaines.
  Map<String, ObjectMergeResult> get mergeResultsByEntryId =>
      Map<String, ObjectMergeResult>.unmodifiable(<String, ObjectMergeResult>{
        for (final s in domainSummaries) ...s.mergeResultsByEntryId,
      });

  /// Nombre total d'objets ignorés suite à un conflit.
  int get skippedCount => domainSummaries.fold<int>(
    0,
    (sum, item) => sum + item.skippedObjectNames.length,
  );

  /// Premier domaine ayant reçu une création ou mise à jour (ou à défaut le premier domaine ciblé).
  String? get firstPromotedDomainId =>
      domainSummaries.where((s) => s.hasChanges).firstOrNull?.domainId ??
      domainSummaries.firstOrNull?.domainId;
}

/// Moteur pur de promotion des [BusinessObjectSpec] vers les [DomainContracts] de Design.
abstract final class SpecDesignPromoter {
  /// Type DSL par défaut suggéré pour un [BusinessObjectSpec] (`model` ou `component`).
  static String defaultContractTypeFor(BusinessObjectSpec object) =>
      object.aggregateRoot ? 'model' : 'component';

  /// Rubrique YAML cible associée à un [contractType] de [DomainContracts.types].
  static String defaultGroupForType(String contractType) =>
      switch (contractType) {
        'model' || 'part' => 'models',
        'component' => 'components',
        'eventxpayloaddto' || 'eventxenvelopedto' => 'message',
        _ => 'dto',
      };

  /// Recherche dans [contracts] une entrée existante de même nom technique que [technicalName]
  /// (comparaison insensible à la casse).
  static JsonNode? findExistingEntry(
    DomainContracts? contracts,
    String technicalName,
  ) {
    if (contracts == null) return null;
    final needle = technicalName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final group in contracts.groups) {
      for (final entry in group.children) {
        if (entry.name.toLowerCase() == needle ||
            DomainContracts.technicalNameOf(entry).toLowerCase() == needle) {
          return entry;
        }
      }
    }
    return null;
  }

  /// Recherche dans [contracts] l'entrée rattachée à [specObject] via son
  /// empreinte [SpecOriginBaseline] (lorsque `projectId` correspond), avec repli
  /// sur la correspondance de `technicalName`.
  static JsonNode? findEntryForSpecObject(
    DomainContracts? contracts,
    BusinessObjectSpec specObject, {
    String? projectId,
  }) {
    if (contracts == null) return null;
    for (final group in contracts.groups) {
      for (final entry in group.children) {
        final origin = contracts.details[entry.id]?.specOrigin;
        if (origin != null &&
            origin.specObjectId == specObject.id &&
            (projectId == null || origin.projectId == projectId)) {
          return entry;
        }
      }
    }
    return findExistingEntry(contracts, specObject.technicalName);
  }

  /// Construit l'empreinte d'origine [SpecOriginBaseline] capturant l'état de
  /// [specObject] et les empreintes canoniques des règles `RG-xxx` qui le ciblent.
  static SpecOriginBaseline buildSpecOriginBaseline({
    required SpecForgeProject project,
    required BusinessObjectSpec specObject,
    required DateTime promotedAt,
  }) {
    final fingerprints = <String, String>{};
    for (final rule in project.businessRules) {
      if (_isRuleLinkedToSpecObject(rule, specObject)) {
        final key = rule.code.trim().isNotEmpty
            ? rule.code.trim()
            : rule.id.trim();
        if (key.isNotEmpty) {
          fingerprints[key] = SpecOriginBaseline.computeRuleFingerprint(rule);
        }
      }
    }
    final activeFeature = project.activeFeature;
    final contribution = activeFeature.id.trim().isEmpty
        ? null
        : SpecFeatureContribution(
            featureId: activeFeature.id.trim(),
            featureCode: activeFeature.code.trim(),
            featureName: activeFeature.name.trim(),
            promotedAt: promotedAt,
          );
    return SpecOriginBaseline(
      projectId: project.id,
      projectName: project.name.trim(),
      featureId: activeFeature.id,
      featureCode: activeFeature.code,
      specObjectId: specObject.id,
      promotedAt: promotedAt,
      baseSpecObject: specObject,
      ruleFingerprints: fingerprints,
      contributingFeatures: <SpecFeatureContribution>[?contribution],
    );
  }

  static bool _isRuleLinkedToSpecObject(
    BusinessRuleSpec rule,
    BusinessObjectSpec specObject,
  ) {
    final objIdLower = specObject.id.trim().toLowerCase();
    final techLower = specObject.technicalName.trim().toLowerCase();
    final nameLower = specObject.name.trim().toLowerCase();

    for (final target in rule.targetObjectIds) {
      final t = target.trim().toLowerCase();
      if (t.isNotEmpty &&
          (t == objIdLower || t == techLower || t == nameLower)) {
        return true;
      }
    }
    for (final attrRef in rule.targetAttributes) {
      final dot = attrRef.indexOf('.');
      if (dot > 0) {
        final prefix = attrRef.substring(0, dot).trim().toLowerCase();
        if (prefix == techLower ||
            prefix == nameLower ||
            prefix == objIdLower) {
          return true;
        }
      }
    }
    if (specObject.technicalName.trim().length >= 3) {
      final wordPattern = RegExp(
        '\\b${RegExp.escape(specObject.technicalName.trim())}\\b',
        caseSensitive: false,
      );
      final corpus = <String>[
        rule.title,
        rule.description,
        rule.trigger,
        rule.condition,
        rule.effect,
      ].join(' ');
      if (wordPattern.hasMatch(corpus)) {
        return true;
      }
    }
    return false;
  }

  /// Suggère la prochaine version sémantique `x.y.z` à partir de [currentVersion]
  /// et du résultat de fusion [mergeResult] :
  /// - **majeur** : ajout d'attribut obligatoire, suppression d'attribut ou changement
  ///   incompatible (type, cardinalité tableau, caractère requis/nullable, retrait de valeur d'enum) ;
  /// - **mineur** : ajout d'attribut optionnel, extension d'énumération/cycle de vie ou
  ///   assouplissement de contrainte ;
  /// - **correctif (patch)** : modification documentaire uniquement (descriptions, libellés).
  static String suggestNextSemVer(
    String currentVersion,
    ObjectMergeResult mergeResult,
  ) {
    final match = ContractDetails.versionPattern.firstMatch(
      currentVersion.trim(),
    );
    final major = match != null ? int.parse(match.group(1)!) : 0;
    final minor = match != null ? int.parse(match.group(2)!) : 0;
    final patch = match != null ? int.parse(match.group(3)!) : 1;
    final normalizedCurrent = '$major.$minor.$patch';

    if (!mergeResult.hasChanges) {
      return normalizedCurrent;
    }

    var bumpLevel = 1; // 1 = patch, 2 = minor, 3 = major
    void escalate(int level) {
      if (level > bumpLevel) bumpLevel = level;
    }

    for (final decision in mergeResult.decisions) {
      switch (decision.kind) {
        case AttributeMergeKind.removedFromSpec:
          escalate(3);
        case AttributeMergeKind.addedFromSpec:
          if (decision.afterAttribute?.required == true) {
            escalate(3);
          } else {
            escalate(2);
          }
        case AttributeMergeKind.updatedFromSpec:
        case AttributeMergeKind.preservedDesignValueObject:
        case AttributeMergeKind.conflictKeptDesign:
          final before = decision.beforeAttribute;
          final after = decision.afterAttribute;
          if (before != null && after != null && before != after) {
            escalate(_classifyAttributeChangeLevel(before, after));
          }
        case AttributeMergeKind.preservedDesignOnly:
          break;
      }
    }

    final beforeObj = mergeResult.currentDesign;
    final afterObj = mergeResult.mergedObject;
    if (!_sameLifecycleStructure(beforeObj, afterObj)) {
      final beforeStateNames = <String>{
        for (final s in beforeObj.lifecycleStates) s.name.trim().toLowerCase(),
      };
      final afterStateNames = <String>{
        for (final s in afterObj.lifecycleStates) s.name.trim().toLowerCase(),
      };
      final removedState = beforeStateNames.any(
        (s) => !afterStateNames.contains(s),
      );
      escalate(removedState ? 3 : 2);
    }

    return switch (bumpLevel) {
      3 => '${major + 1}.0.0',
      2 => '$major.${minor + 1}.0',
      _ => '$major.$minor.${patch + 1}',
    };
  }

  static int _classifyAttributeChangeLevel(
    BusinessAttribute before,
    BusinessAttribute after,
  ) {
    if (before.name != after.name ||
        before.type != after.type ||
        before.isArray != after.isArray ||
        before.referenceObjectId != after.referenceObjectId ||
        before.valueObjectId != after.valueObjectId ||
        (!before.required && after.required) ||
        (before.nullable && !after.nullable)) {
      return 3;
    }
    if (before.enumValues.any((v) => !after.enumValues.contains(v))) {
      return 3;
    }
    if ((before.required && !after.required) ||
        (!before.nullable && after.nullable) ||
        before.unique != after.unique ||
        before.defaultValue != after.defaultValue ||
        before.estimatedMaxRows != after.estimatedMaxRows ||
        after.enumValues.length > before.enumValues.length ||
        before.schemaConstraints != after.schemaConstraints) {
      return 2;
    }
    return 1;
  }

  static bool _sameLifecycleStructure(
    BusinessObjectSpec a,
    BusinessObjectSpec b,
  ) {
    if (a.lifecycleStates.length != b.lifecycleStates.length ||
        a.lifecycleTransitions.length != b.lifecycleTransitions.length) {
      return false;
    }
    for (var i = 0; i < a.lifecycleStates.length; i++) {
      final sa = a.lifecycleStates[i];
      final sb = b.lifecycleStates[i];
      if (sa.name != sb.name ||
          sa.isInitial != sb.isInitial ||
          sa.isTerminal != sb.isTerminal) {
        return false;
      }
    }
    for (var i = 0; i < a.lifecycleTransitions.length; i++) {
      final ta = a.lifecycleTransitions[i];
      final tb = b.lifecycleTransitions[i];
      if (ta.fromState != tb.fromState ||
          ta.toState != tb.toState ||
          ta.trigger != tb.trigger) {
        return false;
      }
    }
    return true;
  }

  /// Construit la projection résolue d'un [specObject] pour une [entry] d'un
  /// [domain] fonctionnel (recâblage intra-domaine et conversion des références externes).
  static BusinessObjectSpec resolveSpecObjectForDomainEntry({
    required SpecForgeProject project,
    required DomainCatalog catalog,
    required FunctionalDomain domain,
    required JsonNode entry,
    required BusinessObjectSpec specObject,
    Map<String, String> plannedDomainBySpecObjectId = const <String, String>{},
    BusinessObjectModelPreferences? modelPreferences,
  }) => _buildDomainObject(
    project: project,
    catalog: catalog,
    currentDomain: domain,
    currentDocument: domain.contracts ?? DomainContracts.empty,
    entry: entry,
    specObject: specObject,
    plannedDomainBySpecObjectId: plannedDomainBySpecObjectId,
    modelPreferences:
        modelPreferences ?? project.businessObjectModelPreferences,
  );

  /// Compte le nombre de références ou relations sortantes de [object] dont la cible
  /// ne sera pas disponible dans [targetDomainId] (et sera donc convertie en identifiant scalaire).
  static int countExternalReferencesForObject({
    required SpecForgeProject project,
    required DomainCatalog catalog,
    required BusinessObjectSpec object,
    required String targetDomainId,
    required Map<String, String?> plannedDomainByObjectId,
  }) {
    final targetDomain = catalog.domains
        .where((d) => d.id == targetDomainId)
        .firstOrNull;
    final targetContracts = targetDomain?.contracts;

    bool isAvailableInTargetDomain(String rawRef) {
      final key = rawRef.trim();
      if (key.isEmpty) return true;
      final specTarget = _findSpecObject(project, key);
      if (specTarget != null) {
        if (specTarget.id == object.id) return true;
        if (plannedDomainByObjectId[specTarget.id] == targetDomainId) {
          return true;
        }
        if (findEntryForSpecObject(
              targetContracts,
              specTarget,
              projectId: project.id,
            ) !=
            null) {
          return true;
        }
        return false;
      }
      return findExistingEntry(targetContracts, key) != null;
    }

    var count = 0;
    void scanAttributes(List<BusinessAttribute> attrs) {
      for (final attr in attrs) {
        if (attr.type == BusinessAttributeType.reference &&
            !isAvailableInTargetDomain(attr.referenceObjectId)) {
          count++;
        }
        if (attr.children.isNotEmpty) {
          scanAttributes(attr.children);
        }
      }
    }

    scanAttributes(object.attributes);

    for (final rel in object.relations) {
      if (_hasEquivalentReferenceAttribute(object.attributes, rel, project)) {
        continue;
      }
      if (!isAvailableInTargetDomain(rel.targetObjectId)) {
        count++;
      }
    }
    return count;
  }

  /// Simule sans effet de bord la promotion des [choices] sélectionnés et retourne
  /// pour chacun un [ObjectPromotionPreview] incluant l'aperçu de fusion 3-voies,
  /// les Value Objects préservés et la version sémantique suggérée.
  static List<ObjectPromotionPreview> previewPromotion({
    required SpecForgeProject project,
    required DomainCatalog catalog,
    required List<ObjectPromotionChoice> choices,
    BusinessObjectModelPreferences? modelPreferences,
  }) {
    final effectivePrefs =
        modelPreferences ?? project.businessObjectModelPreferences;

    final activeChoices = <ObjectPromotionChoice>[];
    final plannedDomainByObjectId = <String, String?>{};
    final plannedDomainBySpecObjectId = <String, String>{};
    for (final choice in choices) {
      if (!choice.isSelected) continue;
      if (!DomainContracts.types.contains(choice.contractType)) {
        throw FormatException(
          'Type de contrat inconnu : ${choice.contractType}.',
        );
      }
      final domainId = choice.domainId!.trim();
      if (!catalog.domains.any((d) => d.id == domainId)) {
        throw FormatException('Domaine cible introuvable : $domainId.');
      }
      final specObj = project.businessObjects
          .where((o) => o.id == choice.objectId)
          .firstOrNull;
      if (specObj == null) {
        throw FormatException('Objet métier introuvable : ${choice.objectId}.');
      }
      activeChoices.add(choice);
      plannedDomainByObjectId[specObj.id] = domainId;
      plannedDomainBySpecObjectId[specObj.id] = domainId;
    }

    if (activeChoices.isEmpty) {
      return const <ObjectPromotionPreview>[];
    }

    // Prépare par domaine un document temporaire incluant les nouvelles entrées
    // afin que la résolution des références intra-domaine soit fidèle à promote().
    final simulatedDocByDomain = <String, DomainContracts>{};
    final choicesByDomain = <String, List<ObjectPromotionChoice>>{};
    for (final choice in activeChoices) {
      choicesByDomain
          .putIfAbsent(choice.domainId!.trim(), () => <ObjectPromotionChoice>[])
          .add(choice);
    }

    for (final entry in choicesByDomain.entries) {
      final domain = catalog.domains.firstWhere((d) => d.id == entry.key);
      var tempDoc = domain.contracts ?? DomainContracts.empty;
      for (final choice in entry.value) {
        final specObj = project.businessObjects.firstWhere(
          (o) => o.id == choice.objectId,
        );
        final existing = findEntryForSpecObject(
          tempDoc,
          specObj,
          projectId: project.id,
        );
        if (existing == null) {
          final nextSource = _insertEntryIntoYamlSource(
            tempDoc.source,
            groupName: defaultGroupForType(choice.contractType),
            entryName: specObj.technicalName,
            contractType: choice.contractType,
          );
          tempDoc = tempDoc.patch(nextSource);
        }
      }
      simulatedDocByDomain[domain.id] = tempDoc;
    }

    final previews = <ObjectPromotionPreview>[];
    for (final choice in activeChoices) {
      final domainId = choice.domainId!.trim();
      final domain = catalog.domains.firstWhere((d) => d.id == domainId);
      final specObj = project.businessObjects.firstWhere(
        (o) => o.id == choice.objectId,
      );
      final originalDoc = domain.contracts;
      final existing = findEntryForSpecObject(
        originalDoc,
        specObj,
        projectId: project.id,
      );
      final simulatedDoc = simulatedDocByDomain[domainId]!;
      final simulatedEntry = existing != null
          ? simulatedDoc.entryById(existing.id)!
          : findExistingEntry(simulatedDoc, specObj.technicalName)!;

      final resolvedSpecObject = _buildDomainObject(
        project: project,
        catalog: catalog,
        currentDomain: domain,
        currentDocument: simulatedDoc,
        entry: simulatedEntry,
        specObject: specObj,
        plannedDomainBySpecObjectId: plannedDomainBySpecObjectId,
        modelPreferences: effectivePrefs,
      );

      final isSkip =
          existing != null &&
          choice.conflictResolution == PromotionConflictResolution.skipExisting;
      final externalRefCount = isSkip
          ? 0
          : countExternalReferencesForObject(
              project: project,
              catalog: catalog,
              object: specObj,
              targetDomainId: domainId,
              plannedDomainByObjectId: plannedDomainByObjectId,
            );

      if (existing == null || originalDoc == null) {
        previews.add(
          ObjectPromotionPreview(
            choice: choice,
            specObject: specObj,
            targetDomainId: domain.id,
            targetDomainName: domain.name,
            isNewEntry: true,
            currentVersion: '0.0.1',
            suggestedVersion: '0.0.1',
            externalRefCount: externalRefCount,
            resolvedSpecObject: resolvedSpecObject,
          ),
        );
      } else {
        final prevDetails =
            originalDoc.details[existing.id] ?? ContractDetails.defaults;
        final currentDesign = originalDoc.objectFor(existing);
        final availableVos = catalog.resolvedValueObjectsForDomain(domain.id);
        final mergeResult = SpecDesignMergeEngine.merge(
          baseSpec: prevDetails.specOrigin?.baseSpecObject,
          nextSpecResolved: resolvedSpecObject,
          nextSpec: specObj,
          currentDesign: currentDesign,
          availableValueObjects: availableVos,
        );
        final suggestedVersion = switch (choice.conflictResolution) {
          PromotionConflictResolution.skipExisting => prevDetails.version,
          PromotionConflictResolution.smartMerge => suggestNextSemVer(
            prevDetails.version,
            mergeResult,
          ),
          PromotionConflictResolution.updateExisting => suggestNextSemVer(
            prevDetails.version,
            _buildOverwriteSyntheticMergeResult(
              currentDesign: currentDesign,
              overwrittenObject: resolvedSpecObject,
            ),
          ),
        };
        previews.add(
          ObjectPromotionPreview(
            choice: choice,
            specObject: specObj,
            targetDomainId: domain.id,
            targetDomainName: domain.name,
            isNewEntry: false,
            existingEntryId: existing.id,
            existingEntryPath: existing.path,
            currentVersion: prevDetails.version,
            suggestedVersion: suggestedVersion,
            externalRefCount: externalRefCount,
            resolvedSpecObject: resolvedSpecObject,
            mergeResult: mergeResult,
          ),
        );
      }
    }

    return List<ObjectPromotionPreview>.unmodifiable(previews);
  }

  /// Exécute la promotion des objets sélectionnés dans [choices] vers les domaines de [catalog].
  ///
  /// Fonctionne en deux passes par domaine :
  /// 1. Création ou mise à jour des entrées DSL et de leurs [ContractDetails] (incluant
  ///    l'empreinte [SpecOriginBaseline]) afin d'obtenir les identifiants stables
  ///    [JsonNode.id] de toutes les entrées du domaine.
  /// 2. Construction des [BusinessObjectSpec] cibles : recâblage des références intra-domaine,
  ///    conversion des références hors domaine en identifiants scalaires documentés, et
  ///    application de la fusion 3-voies lorsque [PromotionConflictResolution.smartMerge] est actif.
  static PromotionExecutionResult promote({
    required SpecForgeProject project,
    required DomainCatalog catalog,
    required List<ObjectPromotionChoice> choices,
    BusinessObjectModelPreferences? modelPreferences,
    String actorUsername = 'local-user',
    DateTime? now,
    bool autoBumpVersion = false,
  }) {
    final effectivePrefs =
        modelPreferences ?? project.businessObjectModelPreferences;
    final timestamp = (now ?? DateTime.now()).toUtc();

    final activeChoices = <ObjectPromotionChoice>[];
    final plannedDomainBySpecObjectId = <String, String>{};
    for (final choice in choices) {
      if (!choice.isSelected) continue;
      if (!DomainContracts.types.contains(choice.contractType)) {
        throw FormatException(
          'Type de contrat inconnu : ${choice.contractType}.',
        );
      }
      final domainId = choice.domainId!.trim();
      if (!catalog.domains.any((d) => d.id == domainId)) {
        throw FormatException('Domaine cible introuvable : $domainId.');
      }
      final specObj = project.businessObjects
          .where((o) => o.id == choice.objectId)
          .firstOrNull;
      if (specObj == null) {
        throw FormatException('Objet métier introuvable : ${choice.objectId}.');
      }
      activeChoices.add(choice);
      plannedDomainBySpecObjectId[specObj.id] = domainId;
    }

    if (activeChoices.isEmpty) {
      return PromotionExecutionResult(updatedCatalog: catalog);
    }

    final choicesByDomain = <String, List<ObjectPromotionChoice>>{};
    for (final choice in activeChoices) {
      choicesByDomain
          .putIfAbsent(choice.domainId!.trim(), () => <ObjectPromotionChoice>[])
          .add(choice);
    }

    final summaries = <DomainPromotionSummary>[];
    final updatedDomains = <FunctionalDomain>[];
    final newAuditEvents = <AuditLogEntry>[];

    for (final domain in catalog.domains) {
      final domainChoices = choicesByDomain[domain.id];
      if (domainChoices == null || domainChoices.isEmpty) {
        updatedDomains.add(domain);
        continue;
      }

      var document = domain.contracts ?? DomainContracts.empty;
      final availableVos = catalog.resolvedValueObjectsForDomain(domain.id);
      final createdIds = <String>[];
      final updatedIds = <String>[];
      final mergedIds = <String>[];
      final skippedNames = <String>[];
      final mergeResultsByEntryId = <String, ObjectMergeResult>{};
      final pendingObjectWrites =
          <
            ({
              ObjectPromotionChoice choice,
              BusinessObjectSpec specObject,
              String entryId,
              bool isExisting,
              BusinessObjectSpec? previousBaseSpec,
              BusinessObjectSpec? previousDesignObject,
              String previousVersion,
            })
          >[];

      // Passe 1 : création / mise à jour des entrées YAML et métadonnées ContractDetails.
      for (final choice in domainChoices) {
        final specObj = project.businessObjects.firstWhere(
          (o) => o.id == choice.objectId,
        );
        final existing = findEntryForSpecObject(
          document,
          specObj,
          projectId: project.id,
        );
        final freshOrigin = buildSpecOriginBaseline(
          project: project,
          specObject: specObj,
          promotedAt: timestamp,
        );

        if (existing != null) {
          if (choice.conflictResolution ==
              PromotionConflictResolution.skipExisting) {
            skippedNames.add(specObj.name);
            continue;
          }
          final prevDetails =
              document.details[existing.id] ?? ContractDetails.defaults;
          final prevOrigin = prevDetails.specOrigin;
          final SpecOriginBaseline nextOrigin;
          if (prevOrigin != null &&
              prevOrigin.projectId == project.id &&
              freshOrigin.contributingFeatures.isNotEmpty) {
            nextOrigin = prevOrigin.mergeContribution(
              freshOrigin.contributingFeatures.single,
              nextBaseSpecObject: specObj,
              nextRuleFingerprints: freshOrigin.ruleFingerprints,
              projectName: project.name.trim(),
            );
          } else {
            nextOrigin = freshOrigin;
          }
          final prevBaseSpec = prevOrigin?.baseSpecObject;
          final prevDesignObj = document.objectFor(existing);
          final prevStates = Map<ContractStage, ContractStatus>.from(
            prevDetails.states,
          );
          if ((prevStates[ContractStage.design] ?? ContractStatus.pending) ==
              ContractStatus.pending) {
            prevStates[ContractStage.design] = ContractStatus.inProgress;
          }
          final nextDetails = ContractDetails(
            title: specObj.name.trim(),
            version: prevDetails.version,
            states: prevStates,
            specOrigin: nextOrigin,
          );
          document = document.edit(existing, choice.contractType, nextDetails);
          updatedIds.add(existing.id);
          if (choice.conflictResolution ==
              PromotionConflictResolution.smartMerge) {
            mergedIds.add(existing.id);
          }
          pendingObjectWrites.add((
            choice: choice,
            specObject: specObj,
            entryId: existing.id,
            isExisting: true,
            previousBaseSpec: prevBaseSpec,
            previousDesignObject: prevDesignObj,
            previousVersion: prevDetails.version,
          ));
        } else {
          final groupName = defaultGroupForType(choice.contractType);
          final nextSource = _insertEntryIntoYamlSource(
            document.source,
            groupName: groupName,
            entryName: specObj.technicalName,
            contractType: choice.contractType,
          );
          document = document.patch(nextSource);
          final created = findExistingEntry(document, specObj.technicalName);
          if (created == null) {
            throw FormatException(
              'Impossible de créer l’entrée DSL « ${specObj.technicalName} » dans le domaine « ${domain.name} ».',
            );
          }
          final details = ContractDetails(
            title: specObj.name.trim(),
            version: '0.0.1',
            states: const <ContractStage, ContractStatus>{
              ContractStage.design: ContractStatus.inProgress,
            },
            specOrigin: freshOrigin,
          );
          document = document.edit(created, choice.contractType, details);
          createdIds.add(created.id);
          pendingObjectWrites.add((
            choice: choice,
            specObject: specObj,
            entryId: created.id,
            isExisting: false,
            previousBaseSpec: null,
            previousDesignObject: null,
            previousVersion: '0.0.1',
          ));
        }
      }

      // Passe 2 : construction, fusion éventuelle et attachement des BusinessObjectSpec résolus.
      for (final item in pendingObjectWrites) {
        final entry = document.entryById(item.entryId)!;
        final resolvedObject = _buildDomainObject(
          project: project,
          catalog: catalog,
          currentDomain: domain,
          currentDocument: document,
          entry: entry,
          specObject: item.specObject,
          plannedDomainBySpecObjectId: plannedDomainBySpecObjectId,
          modelPreferences: effectivePrefs,
        );

        BusinessObjectSpec targetObject = resolvedObject;
        String? bumpedVersion;
        final shouldAutoBump = autoBumpVersion || item.choice.autoBumpVersion;

        if (item.isExisting && item.previousDesignObject != null) {
          if (item.choice.conflictResolution ==
              PromotionConflictResolution.smartMerge) {
            final mergeResult = SpecDesignMergeEngine.merge(
              baseSpec: item.previousBaseSpec,
              nextSpecResolved: resolvedObject,
              nextSpec: item.specObject,
              currentDesign: item.previousDesignObject!,
              availableValueObjects: availableVos,
            );
            targetObject = mergeResult.mergedObject;
            mergeResultsByEntryId[item.entryId] = mergeResult;
            if (shouldAutoBump) {
              bumpedVersion = suggestNextSemVer(
                item.previousVersion,
                mergeResult,
              );
            }
          } else if (shouldAutoBump) {
            bumpedVersion = suggestNextSemVer(
              item.previousVersion,
              _buildOverwriteSyntheticMergeResult(
                currentDesign: item.previousDesignObject!,
                overwrittenObject: resolvedObject,
              ),
            );
          }
        }

        if (bumpedVersion != null && bumpedVersion != item.previousVersion) {
          final currentDetails =
              document.details[item.entryId] ?? ContractDetails.defaults;
          document = document.edit(
            entry,
            entry.type,
            currentDetails.copyWith(version: bumpedVersion),
          );
        }

        document = document.withModel(item.entryId, object: targetObject);
      }

      final summary = DomainPromotionSummary(
        domainId: domain.id,
        domainName: domain.name,
        createdEntryIds: createdIds,
        updatedEntryIds: updatedIds,
        mergedEntryIds: mergedIds,
        skippedObjectNames: skippedNames,
        mergeResultsByEntryId: mergeResultsByEntryId,
      );
      summaries.add(summary);

      if (summary.hasChanges) {
        updatedDomains.add(domain.copyWith(contracts: document));
        newAuditEvents.add(
          AuditLogEntry(
            id: 'audit_${shortid.generate()}',
            recordedAt: timestamp,
            actorUsername: actorUsername,
            domainId: domain.id,
            actionType: DomainAuditAction.update,
            details: _buildAuditDetails(project.name, summary),
          ),
        );
      } else {
        updatedDomains.add(domain);
      }
    }

    if (newAuditEvents.isEmpty) {
      return PromotionExecutionResult(
        updatedCatalog: catalog,
        domainSummaries: summaries,
      );
    }

    final nextCatalog = catalog.copyWith(
      domains: updatedDomains,
      auditLog: [...catalog.auditLog, ...newAuditEvents],
      updatedAt: timestamp,
    );
    nextCatalog.validate();

    return PromotionExecutionResult(
      updatedCatalog: nextCatalog,
      domainSummaries: summaries,
    );
  }

  static ObjectMergeResult _buildOverwriteSyntheticMergeResult({
    required BusinessObjectSpec currentDesign,
    required BusinessObjectSpec overwrittenObject,
  }) {
    // Compare directement currentDesign -> overwrittenObject (comme si baseSpec == currentDesign)
    // afin d'évaluer fidèlement l'impact SemVer d'un écrasement complet.
    return SpecDesignMergeEngine.merge(
      baseSpec: currentDesign,
      nextSpecResolved: overwrittenObject,
      currentDesign: currentDesign,
    );
  }

  static String _buildAuditDetails(
    String projectName,
    DomainPromotionSummary summary,
  ) {
    final overwrittenCount =
        summary.updatedEntryIds.length - summary.mergedEntryIds.length;
    final parts = <String>[
      if (summary.createdEntryIds.isNotEmpty)
        '${summary.createdEntryIds.length} créé(s)',
      if (summary.mergedEntryIds.isNotEmpty)
        '${summary.mergedEntryIds.length} fusionné(s)',
      if (overwrittenCount > 0) '$overwrittenCount mis à jour',
      if (summary.preservedValueObjectsCount > 0)
        '${summary.preservedValueObjectsCount} VO conservé(s)',
      if (summary.skippedObjectNames.isNotEmpty)
        '${summary.skippedObjectNames.length} ignoré(s)',
    ];
    final raw = 'Promotion Spec « $projectName » : ${parts.join(', ')}';
    return raw.length <= 2000 ? raw : raw.substring(0, 2000);
  }

  /// Insère `  <entryName>: <contractType>` sous la rubrique `<groupName>:` de [source]
  /// sans altérer les commentaires ni les autres entrées existantes.
  static String _insertEntryIntoYamlSource(
    String source, {
    required String groupName,
    required String entryName,
    required String contractType,
  }) {
    final normalized = source.replaceAll('\r\n', '\n');
    if (normalized.trim().isEmpty) {
      return '$groupName:\n  $entryName: $contractType\n';
    }

    final lines = normalized.split('\n');
    // Retire l'élément vide final dû au '\n' terminal pour simplifier l'indexation.
    final hadTrailingNewline = lines.isNotEmpty && lines.last.isEmpty;
    if (hadTrailingNewline) {
      lines.removeLast();
    }

    final headerPattern = RegExp(
      '^${RegExp.escape(groupName)}\\s*:(?:\\s*(?:#.*)?)?\$',
    );
    final topLevelLinePattern = RegExp(r'^[^\s#]');
    final childEntryPattern = RegExp(r'^\s+[^\s#]');

    var groupLineIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (headerPattern.hasMatch(lines[i])) {
        groupLineIndex = i;
        break;
      }
    }

    final entryLine = '  $entryName: $contractType';
    if (groupLineIndex >= 0) {
      var nextTopLevelIndex = lines.length;
      for (var i = groupLineIndex + 1; i < lines.length; i++) {
        if (topLevelLinePattern.hasMatch(lines[i])) {
          nextTopLevelIndex = i;
          break;
        }
      }
      var lastChildIndex = -1;
      for (var i = groupLineIndex + 1; i < nextTopLevelIndex; i++) {
        if (childEntryPattern.hasMatch(lines[i])) {
          lastChildIndex = i;
        }
      }
      final insertAt = lastChildIndex >= 0
          ? lastChildIndex + 1
          : groupLineIndex + 1;
      lines.insert(insertAt, entryLine);
    } else {
      if (lines.isNotEmpty && lines.last.trim().isNotEmpty) {
        lines.add('');
      }
      lines
        ..add('$groupName:')
        ..add(entryLine);
    }

    return '${lines.join('\n')}\n';
  }

  static BusinessObjectSpec _buildDomainObject({
    required SpecForgeProject project,
    required DomainCatalog catalog,
    required FunctionalDomain currentDomain,
    required DomainContracts currentDocument,
    required JsonNode entry,
    required BusinessObjectSpec specObject,
    required Map<String, String> plannedDomainBySpecObjectId,
    required BusinessObjectModelPreferences modelPreferences,
  }) {
    String? resolveSameDomainEntryId(String rawTarget) {
      final key = rawTarget.trim();
      if (key.isEmpty) return null;
      final targetSpec = _findSpecObject(project, key);
      if (targetSpec != null) {
        if (targetSpec.id == specObject.id) return entry.id;
        final matchInDoc = findExistingEntry(
          currentDocument,
          targetSpec.technicalName,
        );
        if (matchInDoc != null) return matchInDoc.id;
        return null;
      }
      return findExistingEntry(currentDocument, key)?.id;
    }

    BusinessAttribute transformAttribute(BusinessAttribute attr) {
      final transformedChildren = <BusinessAttribute>[
        for (final child in attr.children) transformAttribute(child),
      ];
      if (attr.type != BusinessAttributeType.reference) {
        return attr.copyWith(children: transformedChildren);
      }
      final sameDomainTargetId = resolveSameDomainEntryId(
        attr.referenceObjectId,
      );
      if (sameDomainTargetId != null) {
        return attr.copyWith(
          referenceObjectId: sameDomainTargetId,
          children: transformedChildren,
        );
      }
      final targetSpec = _findSpecObject(project, attr.referenceObjectId);
      final scalarType = _scalarIdTypeForTarget(targetSpec, modelPreferences);
      final note = _externalReferenceNote(
        rawTarget: attr.referenceObjectId,
        targetSpec: targetSpec,
        catalog: catalog,
        currentDomainId: currentDomain.id,
        plannedDomainBySpecObjectId: plannedDomainBySpecObjectId,
      );
      return attr.copyWith(
        type: scalarType,
        referenceObjectId: '',
        description: _appendNote(attr.description, note),
        children: transformedChildren,
      );
    }

    final mergedAttributes = <BusinessAttribute>[
      for (final attr in specObject.attributes) transformAttribute(attr),
    ];
    final usedNamesLower = <String>{
      for (final attr in mergedAttributes) attr.name.toLowerCase(),
    };

    for (final rel in specObject.relations) {
      if (_hasEquivalentReferenceAttribute(
        specObject.attributes,
        rel,
        project,
      )) {
        continue;
      }
      if (mergedAttributes.length >=
          BusinessObjectSpec.maxAttributesPerObject) {
        break;
      }
      final attrName = _uniqueAttributeName(rel.name, usedNamesLower);
      usedNamesLower.add(attrName.toLowerCase());
      final isArray =
          rel.cardinality == BusinessRelationCardinality.oneToMany ||
          rel.cardinality == BusinessRelationCardinality.manyToMany;
      final sameDomainTargetId = resolveSameDomainEntryId(rel.targetObjectId);
      if (sameDomainTargetId != null) {
        mergedAttributes.add(
          BusinessAttribute(
            id: 'attr_${rel.id}',
            name: attrName,
            type: BusinessAttributeType.reference,
            referenceObjectId: sameDomainTargetId,
            isArray: isArray,
            required: rel.required,
            description: rel.description,
          ),
        );
      } else {
        final targetSpec = _findSpecObject(project, rel.targetObjectId);
        final scalarType = _scalarIdTypeForTarget(targetSpec, modelPreferences);
        final note = _externalReferenceNote(
          rawTarget: rel.targetObjectId,
          targetSpec: targetSpec,
          catalog: catalog,
          currentDomainId: currentDomain.id,
          plannedDomainBySpecObjectId: plannedDomainBySpecObjectId,
        );
        mergedAttributes.add(
          BusinessAttribute(
            id: 'attr_${rel.id}',
            name: attrName,
            type: scalarType,
            referenceObjectId: '',
            isArray: isArray,
            required: rel.required,
            description: _appendNote(rel.description, note),
          ),
        );
      }
    }

    final result = BusinessObjectSpec(
      id: entry.id,
      name: specObject.name,
      technicalName: DomainContracts.technicalNameOf(entry),
      description: specObject.description,
      aggregateRoot: specObject.aggregateRoot,
      attributes: mergedAttributes,
      relations: const <BusinessRelation>[],
      lifecycleStates: specObject.lifecycleStates,
      lifecycleTransitions: specObject.lifecycleTransitions,
    );
    result.validate();
    return result;
  }

  static BusinessObjectSpec? _findSpecObject(
    SpecForgeProject project,
    String rawIdOrTechName,
  ) {
    final needle = rawIdOrTechName.trim();
    if (needle.isEmpty) return null;
    return project.findBusinessObject(needle) ??
        project.businessObjects
            .where(
              (o) =>
                  o.id.toLowerCase() == needle.toLowerCase() ||
                  o.technicalName.toLowerCase() == needle.toLowerCase(),
            )
            .firstOrNull;
  }

  static bool _hasEquivalentReferenceAttribute(
    List<BusinessAttribute> attributes,
    BusinessRelation rel,
    SpecForgeProject project,
  ) {
    final relIsArray =
        rel.cardinality == BusinessRelationCardinality.oneToMany ||
        rel.cardinality == BusinessRelationCardinality.manyToMany;
    final relTarget = _findSpecObject(project, rel.targetObjectId);
    for (final attr in attributes) {
      if (attr.name.toLowerCase() == rel.name.toLowerCase()) {
        return true;
      }
      if (attr.type == BusinessAttributeType.reference &&
          attr.isArray == relIsArray) {
        if (attr.referenceObjectId.trim().toLowerCase() ==
            rel.targetObjectId.trim().toLowerCase()) {
          return true;
        }
        final attrTarget = _findSpecObject(project, attr.referenceObjectId);
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
    required BusinessObjectSpec? targetSpec,
    required DomainCatalog catalog,
    required String currentDomainId,
    required Map<String, String> plannedDomainBySpecObjectId,
  }) {
    final targetLabel =
        targetSpec?.name ??
        (rawTarget.trim().isNotEmpty ? rawTarget.trim() : 'entité externe');
    String? otherDomainName;
    if (targetSpec != null) {
      final plannedDomainId = plannedDomainBySpecObjectId[targetSpec.id];
      if (plannedDomainId != null && plannedDomainId != currentDomainId) {
        otherDomainName = catalog.domains
            .where((d) => d.id == plannedDomainId)
            .firstOrNull
            ?.name;
      }
      otherDomainName ??= catalog.domains
          .where(
            (d) =>
                d.id != currentDomainId &&
                findExistingEntry(d.contracts, targetSpec.technicalName) !=
                    null,
          )
          .firstOrNull
          ?.name;
    }
    return otherDomainName != null
        ? 'Référence externe vers $targetLabel (domaine $otherDomainName)'
        : 'Référence externe vers $targetLabel';
  }

  static String _appendNote(String existingDescription, String note) {
    final clean = existingDescription.trim();
    if (clean.isEmpty) return note;
    if (clean.toLowerCase().contains(note.toLowerCase())) return clean;
    return '$clean — $note';
  }
}
