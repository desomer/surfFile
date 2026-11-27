/// Analyseur d'impact et de gouvernance inter-features des objets métiers
/// ([CrossFeatureObjectAnalyzer]) selon la politique `additive_warn_on_validated`.
library;

import 'package:flutter/foundation.dart';

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/json_schema_constraints.dart';
import '../models/qa/qa_fixture_spec.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_initiative.dart';
import '../models/ux/ux_screen_spec.dart';

/// Nature de la divergence structurelle d'un objet métier entre la feature
/// analysée et une feature sœur du portefeuille.
enum CrossFeatureDivergenceKind {
  /// Correspondance structurelle exacte entre les deux features.
  identical('Identique'),

  /// Extension purement additive et 100 % rétrocompatible (ajout d'attributs
  /// optionnels, assouplissement de contraintes, ajout de valeurs d'énumération
  /// ou d'états/transitions de cycle de vie).
  additive('Extension additive'),

  /// La feature sœur possède des attributs ou éléments optionnels supplémentaires
  /// non encore importés dans la feature analysée, sans conflit de type ni de contrainte.
  behindSibling('En retrait (attributs manquants)'),

  /// Divergence cassante (type ou cardinalité incompatible, durcissement d'obligation
  /// ou de contrainte, suppression d'attribut/état d'une feature validée ou référencé
  /// en aval, ou ajout d'attribut obligatoire sans valeur par défaut face à une feature validée).
  breaking('Divergence cassante');

  /// Construit une catégorie de divergence inter-features.
  const CrossFeatureDivergenceKind(this.label);

  /// Libellé lisible en français.
  final String label;
}

/// Domaine aval impacté par une divergence d'objet métier dans une feature.
enum CrossFeatureDownstreamArea {
  /// Règle de gestion métier (`RG-xxx`).
  businessRule('RG'),

  /// Écran ou composant du volet UX (`SCR-xxx`).
  ux('UX'),

  /// Jeu d'essai, scénario Gherkin ou suite TDD du volet QA (`FIX-xxx`, `SCN-xxx`, `TDD-xxx`).
  qa('QA');

  /// Construit un domaine aval d'impact.
  const CrossFeatureDownstreamArea(this.label);

  /// Code court affiché dans les badges (`RG`, `UX`, `QA`).
  final String label;
}

/// Impact aval détecté sur un livrable (`RG`, `UX` ou `QA`) suite à la modification
/// incompatible ou à l'absence d'un attribut ou d'un état d'objet métier.
@immutable
class CrossFeatureDownstreamImpact {
  /// Construit un diagnostic immuable d'impact aval inter-features.
  const CrossFeatureDownstreamImpact({
    required this.area,
    required this.featureId,
    required this.featureCode,
    required this.artifactRef,
    required this.artifactTitle,
    required this.attributeOrStateName,
    required this.summary,
  });

  /// Volet aval concerné (`RG`, `UX`, `QA`).
  final CrossFeatureDownstreamArea area;

  /// Identifiant unique de la feature porteuse de l'artefact impacté.
  final String featureId;

  /// Code court de la feature porteuse (ex. `FEAT-01`).
  final String featureCode;

  /// Référence courte de l'artefact impacté (ex. `RG-003`, `SCR-001`, `FIX-001`, `TDD-002`).
  final String artifactRef;

  /// Intitulé lisible de l'artefact impacté.
  final String artifactTitle;

  /// Nom ou chemin de l'attribut ou de l'état à l'origine de l'impact.
  final String attributeOrStateName;

  /// Explication synthétique en français de l'impact détecté.
  final String summary;

  /// Retourne une copie modifiée de cet impact aval.
  CrossFeatureDownstreamImpact copyWith({
    CrossFeatureDownstreamArea? area,
    String? featureId,
    String? featureCode,
    String? artifactRef,
    String? artifactTitle,
    String? attributeOrStateName,
    String? summary,
  }) => CrossFeatureDownstreamImpact(
    area: area ?? this.area,
    featureId: featureId ?? this.featureId,
    featureCode: featureCode ?? this.featureCode,
    artifactRef: artifactRef ?? this.artifactRef,
    artifactTitle: artifactTitle ?? this.artifactTitle,
    attributeOrStateName: attributeOrStateName ?? this.attributeOrStateName,
    summary: summary ?? this.summary,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CrossFeatureDownstreamImpact &&
          other.area == area &&
          other.featureId == featureId &&
          other.featureCode == featureCode &&
          other.artifactRef == artifactRef &&
          other.artifactTitle == artifactTitle &&
          other.attributeOrStateName == attributeOrStateName &&
          other.summary == summary;

  @override
  int get hashCode => Object.hash(
    area,
    featureId,
    featureCode,
    artifactRef,
    artifactTitle,
    attributeOrStateName,
    summary,
  );
}

/// Lien de comparaison et d'impact entre un objet métier de la feature analysée
/// et son homologue canonique dans une feature sœur non archivée.
@immutable
class SiblingFeatureObjectLink {
  /// Construit un lien immuable de comparaison avec une feature sœur.
  SiblingFeatureObjectLink({
    required this.featureId,
    required this.featureCode,
    required this.featureName,
    required this.initiativeCode,
    required this.effectiveStatus,
    required this.siblingObjectId,
    required this.divergence,
    List<String> differenceSummaries = const <String>[],
    List<CrossFeatureDownstreamImpact> downstreamImpacts =
        const <CrossFeatureDownstreamImpact>[],
  }) : differenceSummaries = List<String>.unmodifiable(differenceSummaries),
       downstreamImpacts = List<CrossFeatureDownstreamImpact>.unmodifiable(
         downstreamImpacts,
       );

  /// Identifiant unique de la feature sœur.
  final String featureId;

  /// Code court de la feature sœur (ex. `FEAT-01`).
  final String featureCode;

  /// Nom fonctionnel de la feature sœur.
  final String featureName;

  /// Code court de l'initiative parente de la feature sœur (ex. `INIT-01`).
  final String initiativeCode;

  /// Statut effectif de la feature sœur dans le portefeuille.
  final SpecPortfolioStatus effectiveStatus;

  /// Identifiant du [BusinessObjectSpec] homologue dans la feature sœur.
  final String siblingObjectId;

  /// Nature de la divergence constatée vis-à-vis de la feature sœur.
  final CrossFeatureDivergenceKind divergence;

  /// Lignes synthétiques en français décrivant les écarts détectés.
  final List<String> differenceSummaries;

  /// Impacts aval relevés sur les livrables `RG`, `UX` et `QA` de la feature sœur.
  final List<CrossFeatureDownstreamImpact> downstreamImpacts;

  /// Vrai lorsque la feature sœur est au statut [SpecPortfolioStatus.validated].
  bool get isSiblingValidated =>
      effectiveStatus == SpecPortfolioStatus.validated;

  /// Vrai lorsqu'une alerte de gouvernance doit être remontée (rupture face à une
  /// feature validée ou impact aval sur `RG`/`UX`/`QA`).
  bool get hasValidatedWarning =>
      (isSiblingValidated && divergence == CrossFeatureDivergenceKind.breaking) ||
      downstreamImpacts.isNotEmpty;

  /// Référence courte de la feature sœur (code court s'il est renseigné, sinon son nom).
  String get effectiveFeatureRef =>
      featureCode.trim().isNotEmpty ? featureCode.trim() : featureName.trim();

  /// Libellé complet combinant code court et nom de la feature sœur.
  String get featureDisplayLabel => featureCode.trim().isEmpty
      ? featureName
      : '${featureCode.trim()} · $featureName';

  /// Retourne une copie modifiée de ce lien inter-features.
  SiblingFeatureObjectLink copyWith({
    String? featureId,
    String? featureCode,
    String? featureName,
    String? initiativeCode,
    SpecPortfolioStatus? effectiveStatus,
    String? siblingObjectId,
    CrossFeatureDivergenceKind? divergence,
    List<String>? differenceSummaries,
    List<CrossFeatureDownstreamImpact>? downstreamImpacts,
  }) => SiblingFeatureObjectLink(
    featureId: featureId ?? this.featureId,
    featureCode: featureCode ?? this.featureCode,
    featureName: featureName ?? this.featureName,
    initiativeCode: initiativeCode ?? this.initiativeCode,
    effectiveStatus: effectiveStatus ?? this.effectiveStatus,
    siblingObjectId: siblingObjectId ?? this.siblingObjectId,
    divergence: divergence ?? this.divergence,
    differenceSummaries: differenceSummaries ?? this.differenceSummaries,
    downstreamImpacts: downstreamImpacts ?? this.downstreamImpacts,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SiblingFeatureObjectLink &&
          other.featureId == featureId &&
          other.featureCode == featureCode &&
          other.featureName == featureName &&
          other.initiativeCode == initiativeCode &&
          other.effectiveStatus == effectiveStatus &&
          other.siblingObjectId == siblingObjectId &&
          other.divergence == divergence &&
          listEquals(other.differenceSummaries, differenceSummaries) &&
          listEquals(other.downstreamImpacts, downstreamImpacts);

  @override
  int get hashCode => Object.hash(
    featureId,
    featureCode,
    featureName,
    initiativeCode,
    effectiveStatus,
    siblingObjectId,
    divergence,
    Object.hashAll(differenceSummaries),
    Object.hashAll(downstreamImpacts),
  );
}

/// Rapport de partage et d'impact inter-features pour un [BusinessObjectSpec] donné.
@immutable
class ObjectCrossFeatureReport {
  /// Construit un rapport immuable inter-features pour un objet métier.
  ObjectCrossFeatureReport({
    required this.objectId,
    required this.objectName,
    required this.technicalName,
    List<SiblingFeatureObjectLink> siblingLinks =
        const <SiblingFeatureObjectLink>[],
    List<CrossFeatureDownstreamImpact> selfValidatedImpacts =
        const <CrossFeatureDownstreamImpact>[],
  }) : siblingLinks = List<SiblingFeatureObjectLink>.unmodifiable(siblingLinks),
       selfValidatedImpacts = List<CrossFeatureDownstreamImpact>.unmodifiable(
         selfValidatedImpacts,
       );

  /// Identifiant unique de l'objet métier dans la feature analysée.
  final String objectId;

  /// Nom métier lisible de l'objet.
  final String objectName;

  /// Nom technique `PascalCase` de l'objet.
  final String technicalName;

  /// Liens vers les features sœurs non archivées partageant cet objet canonique.
  final List<SiblingFeatureObjectLink> siblingLinks;

  /// Impacts locaux détectés sur la feature analysée elle-même (lorsqu'elle est
  /// validée, possède une baseline de synchronisation ou des références locales cassées).
  final List<CrossFeatureDownstreamImpact> selfValidatedImpacts;

  /// Vrai si cet objet métier existe également dans au moins une autre feature active.
  bool get isSharedAcrossFeatures => siblingLinks.isNotEmpty;

  /// Vrai si au moins une feature sœur partageant cet objet est au statut `Validée`.
  bool get sharedWithValidatedFeature =>
      siblingLinks.any((l) => l.isSiblingValidated);

  /// Vrai si l'objet présente une divergence cassante vis-à-vis d'une feature validée
  /// ou impacte des livrables `RG`/`UX`/`QA` d'une feature sœur.
  bool get hasBreakingValidatedWarning =>
      siblingLinks.any((l) => l.hasValidatedWarning);

  /// Nombre total d'impacts aval `RG`/`UX`/`QA` cumulés sur les features sœurs.
  int get totalDownstreamImpactCount =>
      siblingLinks.fold<int>(0, (s, l) => s + l.downstreamImpacts.length);

  /// Résumé compact des codes (ou noms) des features sœurs partageant cet objet (ex. `'FEAT-01, FEAT-03'`).
  String get sharedFeaturesSummary {
    if (siblingLinks.isEmpty) return '';
    final refs = <String>[];
    final seen = <String>{};
    for (final link in siblingLinks) {
      final ref = link.effectiveFeatureRef;
      if (ref.isNotEmpty && seen.add(ref)) {
        refs.add(ref);
      }
    }
    return refs.join(', ');
  }

  /// Retourne une copie modifiée de ce rapport d'objet.
  ObjectCrossFeatureReport copyWith({
    String? objectId,
    String? objectName,
    String? technicalName,
    List<SiblingFeatureObjectLink>? siblingLinks,
    List<CrossFeatureDownstreamImpact>? selfValidatedImpacts,
  }) => ObjectCrossFeatureReport(
    objectId: objectId ?? this.objectId,
    objectName: objectName ?? this.objectName,
    technicalName: technicalName ?? this.technicalName,
    siblingLinks: siblingLinks ?? this.siblingLinks,
    selfValidatedImpacts: selfValidatedImpacts ?? this.selfValidatedImpacts,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectCrossFeatureReport &&
          other.objectId == objectId &&
          other.objectName == objectName &&
          other.technicalName == technicalName &&
          listEquals(other.siblingLinks, siblingLinks) &&
          listEquals(other.selfValidatedImpacts, selfValidatedImpacts);

  @override
  int get hashCode => Object.hash(
    objectId,
    objectName,
    technicalName,
    Object.hashAll(siblingLinks),
    Object.hashAll(selfValidatedImpacts),
  );
}

/// Rapport consolidé de partage et de gouvernance inter-features à l'échelle d'une [SpecFeatureSpec].
@immutable
class FeatureCrossObjectReport {
  /// Construit un rapport immuable inter-features pour une feature donnée.
  FeatureCrossObjectReport({
    required this.featureId,
    Map<String, ObjectCrossFeatureReport> byObjectId =
        const <String, ObjectCrossFeatureReport>{},
  }) : byObjectId = Map<String, ObjectCrossFeatureReport>.unmodifiable(
         byObjectId,
       );

  /// Identifiant de la feature analysée.
  final String featureId;

  /// Rapports individuels par identifiant d'objet métier (`objectId -> report`).
  final Map<String, ObjectCrossFeatureReport> byObjectId;

  /// Nombre d'objets métiers de cette feature partagés avec au moins une feature sœur non archivée.
  int get sharedObjectCount =>
      byObjectId.values.where((r) => r.isSharedAcrossFeatures).length;

  /// Nombre d'objets métiers propres exclusivement à cette feature.
  int get localOnlyObjectCount =>
      byObjectId.values.where((r) => !r.isSharedAcrossFeatures).length;

  /// Liste des objets métiers présentant une alerte de divergence cassante ou d'impact aval.
  List<ObjectCrossFeatureReport> get warnings =>
      List<ObjectCrossFeatureReport>.unmodifiable([
        for (final report in byObjectId.values)
          if (report.hasBreakingValidatedWarning) report,
      ]);

  /// Nombre d'objets métiers de cette feature présentant une alerte inter-features.
  int get warningObjectCount =>
      byObjectId.values.where((r) => r.hasBreakingValidatedWarning).length;

  /// Recherche le rapport inter-features associé à [objectId], ou `null` si absent.
  ObjectCrossFeatureReport? reportFor(String objectId) => byObjectId[objectId];

  /// Retourne une copie modifiée de ce rapport de feature.
  FeatureCrossObjectReport copyWith({
    String? featureId,
    Map<String, ObjectCrossFeatureReport>? byObjectId,
  }) => FeatureCrossObjectReport(
    featureId: featureId ?? this.featureId,
    byObjectId: byObjectId ?? this.byObjectId,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureCrossObjectReport &&
          other.featureId == featureId &&
          mapEquals(other.byObjectId, byObjectId);

  @override
  int get hashCode => Object.hash(
    featureId,
    Object.hashAllUnordered([
      for (final e in byObjectId.entries) Object.hash(e.key, e.value),
    ]),
  );
}

/// Synthèse globale du partage d'objets métiers et des alertes inter-features
/// sur l'ensemble du portefeuille d'un [SpecForgeProject].
@immutable
class PortfolioCrossObjectSummary {
  /// Construit une synthèse portefeuille immuable.
  PortfolioCrossObjectSummary({
    Map<String, FeatureCrossObjectReport> byFeatureId =
        const <String, FeatureCrossObjectReport>{},
    required this.uniqueCanonicalObjectCount,
    required this.sharedCanonicalObjectCount,
    required this.featuresWithWarningsCount,
  }) : byFeatureId = Map<String, FeatureCrossObjectReport>.unmodifiable(
         byFeatureId,
       );

  /// Rapports détaillés indexés par identifiant de feature (`featureId -> report`).
  final Map<String, FeatureCrossObjectReport> byFeatureId;

  /// Nombre total d'objets métiers canoniques distincts à travers les features non archivées.
  final int uniqueCanonicalObjectCount;

  /// Nombre d'objets métiers canoniques partagés par au moins 2 features non archivées.
  final int sharedCanonicalObjectCount;

  /// Nombre de features non archivées comportant au moins une alerte inter-features.
  final int featuresWithWarningsCount;

  /// Recherche le rapport inter-features d'une feature donnée, ou `null` si absente.
  FeatureCrossObjectReport? reportForFeature(String featureId) =>
      byFeatureId[featureId];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PortfolioCrossObjectSummary &&
          mapEquals(other.byFeatureId, byFeatureId) &&
          other.uniqueCanonicalObjectCount == uniqueCanonicalObjectCount &&
          other.sharedCanonicalObjectCount == sharedCanonicalObjectCount &&
          other.featuresWithWarningsCount == featuresWithWarningsCount;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered([
      for (final e in byFeatureId.entries) Object.hash(e.key, e.value),
    ]),
    uniqueCanonicalObjectCount,
    sharedCanonicalObjectCount,
    featuresWithWarningsCount,
  );
}

/// Moteur pur et déterministe d'analyse de gouvernance et d'impact inter-features
/// des objets métiers selon la politique `additive_warn_on_validated`.
abstract final class CrossFeatureObjectAnalyzer {
  /// Analyse le partage, les divergences (`identical`, `additive`, `behindSibling`,
  /// `breaking`) et les impacts aval (`RG`, `UX`, `QA`) des objets métiers de
  /// [featureId] (ou de `project.activeFeatureId` par défaut) vis-à-vis des
  /// features sœurs non archivées du [project].
  ///
  /// Retourne immédiatement un rapport sans liens partagés lorsque le projet ne
  /// comporte qu'une seule feature (`project.allFeatures.length <= 1`) ou que la
  /// feature ciblée est archivée.
  static FeatureCrossObjectReport analyzeFeature(
    SpecForgeProject project, {
    String? featureId,
  }) {
    final trimmedId = featureId?.trim();
    final targetFeature = (trimmedId == null || trimmedId.isEmpty)
        ? project.activeFeature
        : project.featureById(trimmedId);

    if (targetFeature == null) {
      return FeatureCrossObjectReport(featureId: trimmedId ?? '');
    }

    if (project.allFeatures.length <= 1 || _isArchived(targetFeature)) {
      return _buildIsolatedReport(targetFeature);
    }

    final siblingEntries = <({SpecInitiative initiative, SpecFeatureSpec feature})>[
      for (final init in project.initiatives)
        for (final feat in init.features)
          if (feat.id != targetFeature.id && !_isArchived(feat))
            (initiative: init, feature: feat),
    ];

    if (siblingEntries.isEmpty) {
      return _buildIsolatedReport(targetFeature);
    }

    final byObjectId = <String, ObjectCrossFeatureReport>{};
    for (final activeObj in targetFeature.businessObjects) {
      final links = <SiblingFeatureObjectLink>[];
      for (final entry in siblingEntries) {
        final siblingFeat = entry.feature;
        final siblingObj = _findMatchingSiblingObject(
          activeFeature: targetFeature,
          activeObj: activeObj,
          siblingFeature: siblingFeat,
        );
        if (siblingObj == null) continue;

        links.add(
          _buildSiblingLink(
            activeFeature: targetFeature,
            activeObj: activeObj,
            siblingInitiative: entry.initiative,
            siblingFeature: siblingFeat,
            siblingObj: siblingObj,
          ),
        );
      }

      final selfImpacts = _computeSelfValidatedImpacts(
        feature: targetFeature,
        activeObj: activeObj,
      );

      byObjectId[activeObj.id] = ObjectCrossFeatureReport(
        objectId: activeObj.id,
        objectName: activeObj.name,
        technicalName: activeObj.technicalName,
        siblingLinks: links,
        selfValidatedImpacts: selfImpacts,
      );
    }

    return FeatureCrossObjectReport(
      featureId: targetFeature.id,
      byObjectId: byObjectId,
    );
  }

  /// Construit la synthèse portefeuille complète sur `project.allFeatures` en
  /// ignorant les features archivées pour le décompte canonique et les alertes.
  static PortfolioCrossObjectSummary analyzePortfolio(
    SpecForgeProject project,
  ) {
    final byFeatureId = <String, FeatureCrossObjectReport>{};
    final nonArchivedFeatures = <SpecFeatureSpec>[];

    for (final feature in project.allFeatures) {
      final report = analyzeFeature(project, featureId: feature.id);
      byFeatureId[feature.id] = report;
      if (!_isArchived(feature)) {
        nonArchivedFeatures.add(feature);
      }
    }

    final nodes = <({SpecFeatureSpec feature, BusinessObjectSpec object})>[
      for (final feat in nonArchivedFeatures)
        for (final obj in feat.businessObjects) (feature: feat, object: obj),
    ];

    if (nodes.isEmpty) {
      final warnFeatures = nonArchivedFeatures
          .where((f) => (byFeatureId[f.id]?.warningObjectCount ?? 0) > 0)
          .length;
      return PortfolioCrossObjectSummary(
        byFeatureId: byFeatureId,
        uniqueCanonicalObjectCount: 0,
        sharedCanonicalObjectCount: 0,
        featuresWithWarningsCount: warnFeatures,
      );
    }

    final parents = List<int>.generate(nodes.length, (i) => i);
    int findRoot(int x) {
      var r = x;
      while (parents[r] != r) {
        r = parents[r];
      }
      var curr = x;
      while (parents[curr] != r) {
        final next = parents[curr];
        parents[curr] = r;
        curr = next;
      }
      return r;
    }

    void unionNodes(int a, int b) {
      final ra = findRoot(a);
      final rb = findRoot(b);
      if (ra != rb) {
        parents[rb] = ra;
      }
    }

    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        if (nodes[i].feature.id == nodes[j].feature.id) continue;
        if (_objectsMatchCanonically(
          featureA: nodes[i].feature,
          objA: nodes[i].object,
          featureB: nodes[j].feature,
          objB: nodes[j].object,
        )) {
          unionNodes(i, j);
        }
      }
    }

    final featureIdsByRoot = <int, Set<String>>{};
    for (var i = 0; i < nodes.length; i++) {
      final root = findRoot(i);
      (featureIdsByRoot[root] ??= <String>{}).add(nodes[i].feature.id);
    }

    final uniqueCount = featureIdsByRoot.length;
    final sharedCount = featureIdsByRoot.values
        .where((fIds) => fIds.length >= 2)
        .length;
    final featuresWithWarnings = nonArchivedFeatures
        .where((f) => (byFeatureId[f.id]?.warningObjectCount ?? 0) > 0)
        .length;

    return PortfolioCrossObjectSummary(
      byFeatureId: byFeatureId,
      uniqueCanonicalObjectCount: uniqueCount,
      sharedCanonicalObjectCount: sharedCount,
      featuresWithWarningsCount: featuresWithWarnings,
    );
  }

  static bool _isArchived(SpecFeatureSpec feature) =>
      feature.effectiveStatus == SpecPortfolioStatus.archived;

  static FeatureCrossObjectReport _buildIsolatedReport(
    SpecFeatureSpec feature,
  ) => FeatureCrossObjectReport(
    featureId: feature.id,
    byObjectId: <String, ObjectCrossFeatureReport>{
      for (final obj in feature.businessObjects)
        obj.id: ObjectCrossFeatureReport(
          objectId: obj.id,
          objectName: obj.name,
          technicalName: obj.technicalName,
        ),
    },
  );

  static BusinessObjectSpec? _findMatchingSiblingObject({
    required SpecFeatureSpec activeFeature,
    required BusinessObjectSpec activeObj,
    required SpecFeatureSpec siblingFeature,
  }) {
    if (siblingFeature.businessObjects.isEmpty) return null;

    // 1. Lien explicite de baseline de synchronisation inter-features.
    final activeBase = activeFeature.syncBaselineFor(activeObj.id);
    if (activeBase != null &&
        activeBase.sourceFeatureId == siblingFeature.id &&
        activeBase.sourceEntryId.trim().isNotEmpty) {
      final targetLower = activeBase.sourceEntryId.trim().toLowerCase();
      for (final candidate in siblingFeature.businessObjects) {
        if (candidate.id.trim().toLowerCase() == targetLower) {
          return candidate;
        }
      }
    }
    for (final candidate in siblingFeature.businessObjects) {
      final sibBase = siblingFeature.syncBaselineFor(candidate.id);
      if (sibBase != null &&
          sibBase.sourceFeatureId == activeFeature.id &&
          sibBase.sourceEntryId.trim().toLowerCase() ==
              activeObj.id.trim().toLowerCase()) {
        return candidate;
      }
    }

    // 2. Identifiant technique exact (insensible à la casse).
    final idLower = activeObj.id.trim().toLowerCase();
    for (final candidate in siblingFeature.businessObjects) {
      if (candidate.id.trim().toLowerCase() == idLower) {
        return candidate;
      }
    }

    // 3. Nom technique PascalCase exact (insensible à la casse).
    final techLower = activeObj.technicalName.trim().toLowerCase();
    for (final candidate in siblingFeature.businessObjects) {
      if (candidate.technicalName.trim().toLowerCase() == techLower) {
        return candidate;
      }
    }

    // 4. Nom métier lisible exact (insensible à la casse).
    final nameLower = activeObj.name.trim().toLowerCase();
    for (final candidate in siblingFeature.businessObjects) {
      if (candidate.name.trim().toLowerCase() == nameLower) {
        return candidate;
      }
    }

    return null;
  }

  static bool _objectsMatchCanonically({
    required SpecFeatureSpec featureA,
    required BusinessObjectSpec objA,
    required SpecFeatureSpec featureB,
    required BusinessObjectSpec objB,
  }) {
    final baseA = featureA.syncBaselineFor(objA.id);
    if (baseA != null &&
        baseA.sourceFeatureId == featureB.id &&
        baseA.sourceEntryId.trim().toLowerCase() ==
            objB.id.trim().toLowerCase()) {
      return true;
    }
    final baseB = featureB.syncBaselineFor(objB.id);
    if (baseB != null &&
        baseB.sourceFeatureId == featureA.id &&
        baseB.sourceEntryId.trim().toLowerCase() ==
            objA.id.trim().toLowerCase()) {
      return true;
    }
    if (objA.id.trim().toLowerCase() == objB.id.trim().toLowerCase()) {
      return true;
    }
    if (objA.technicalName.trim().toLowerCase() ==
        objB.technicalName.trim().toLowerCase()) {
      return true;
    }
    if (objA.name.trim().toLowerCase() == objB.name.trim().toLowerCase()) {
      return true;
    }
    return false;
  }

  static SiblingFeatureObjectLink _buildSiblingLink({
    required SpecFeatureSpec activeFeature,
    required BusinessObjectSpec activeObj,
    required SpecInitiative siblingInitiative,
    required SpecFeatureSpec siblingFeature,
    required BusinessObjectSpec siblingObj,
  }) {
    final isSiblingValidated =
        siblingFeature.effectiveStatus == SpecPortfolioStatus.validated;
    final isActiveValidated =
        activeFeature.effectiveStatus == SpecPortfolioStatus.validated;
    final syncBaseObj = activeFeature.syncBaselineFor(activeObj.id)?.baseObject;
    final siblingSyncBase = siblingFeature.syncBaselineFor(siblingObj.id);
    final siblingSyncedFromActiveObj =
        (siblingSyncBase != null &&
            siblingSyncBase.sourceFeatureId == activeFeature.id)
        ? siblingSyncBase.baseObject
        : null;

    final acc = _ComparisonAccumulator(
      activeFeature: activeFeature,
      activeObj: activeObj,
      siblingFeature: siblingFeature,
      siblingObj: siblingObj,
      isSiblingValidated: isSiblingValidated,
      treatUnimportedSiblingExtensionsAsBreaking:
          isSiblingValidated && !isActiveValidated,
      syncBaselineObject: syncBaseObj,
      siblingSyncedFromActiveObject: siblingSyncedFromActiveObj,
    );
    acc.compareObjects();

    // Évaluation des impacts aval RG / UX / QA dans la feature sœur.
    final downstreamImpacts = _collectDownstreamImpacts(
      targetFeature: siblingFeature,
      targetObj: siblingObj,
      impactCandidates: acc.impactCandidates,
    );

    // Si la feature sœur est validée (face à une feature en cours ou suite à une
    // suppression explicite) et qu'une omission impacte RG/UX/QA, elle est cassante.
    final impactedNamesLower = <String>{
      for (final imp in downstreamImpacts)
        imp.attributeOrStateName.trim().toLowerCase(),
    };
    var hasBreaking = acc.hasBreaking;
    if (!hasBreaking &&
        isSiblingValidated &&
        !isActiveValidated &&
        impactedNamesLower.isNotEmpty) {
      hasBreaking = true;
    }

    final CrossFeatureDivergenceKind divergence;
    if (hasBreaking) {
      divergence = CrossFeatureDivergenceKind.breaking;
    } else if (acc.hasMissingOptionalFromSibling) {
      divergence = CrossFeatureDivergenceKind.behindSibling;
    } else if (acc.hasAdditive) {
      divergence = CrossFeatureDivergenceKind.additive;
    } else {
      divergence = CrossFeatureDivergenceKind.identical;
    }

    final summaries = <String>[
      ...acc.breakingSummaries,
      if (acc.addedOptionalAttrs.isNotEmpty)
        _formatCountSummary(
          count: acc.addedOptionalAttrs.length,
          singular: 'attribut(s) additif(s)',
          names: acc.addedOptionalAttrs,
          prefix: '+',
        ),
      ...acc.additiveDetailSummaries,
      ...acc.missingOptionalSummaries,
    ];

    return SiblingFeatureObjectLink(
      featureId: siblingFeature.id,
      featureCode: siblingFeature.code,
      featureName: siblingFeature.name,
      initiativeCode: siblingInitiative.code,
      effectiveStatus: siblingFeature.effectiveStatus,
      siblingObjectId: siblingObj.id,
      divergence: divergence,
      differenceSummaries: summaries,
      downstreamImpacts: downstreamImpacts,
    );
  }

  static List<CrossFeatureDownstreamImpact> _computeSelfValidatedImpacts({
    required SpecFeatureSpec feature,
    required BusinessObjectSpec activeObj,
  }) {
    final candidates = <_ImpactCandidate>[];
    final seenNamesLower = <String>{};

    final baseline = feature.syncBaselineFor(activeObj.id);
    if (baseline != null) {
      final isValidated =
          feature.effectiveStatus == SpecPortfolioStatus.validated;
      final acc = _ComparisonAccumulator(
        activeFeature: feature,
        activeObj: activeObj,
        siblingFeature: feature,
        siblingObj: baseline.baseObject,
        isSiblingValidated: isValidated,
        treatUnimportedSiblingExtensionsAsBreaking: isValidated,
        syncBaselineObject: baseline.baseObject,
      );
      acc.compareObjects();
      for (final c in acc.impactCandidates) {
        if (seenNamesLower.add(c.name.toLowerCase())) {
          candidates.add(c);
        }
      }
    }

    // Détection directe d'attributs explicitement référencés en local (RG / UX)
    // mais absents de activeObj.
    for (final rule in feature.businessRules) {
      if (!rule.active || !_ruleTargetsObject(rule, activeObj)) continue;
      for (final rawAttr in rule.targetAttributes) {
        final cleaned = _stripObjectPrefix(activeObj, rawAttr);
        if (cleaned.isEmpty) continue;
        if (!_objectHasAttributeOrRelation(activeObj, cleaned) &&
            seenNamesLower.add(cleaned.toLowerCase())) {
          candidates.add(
            _ImpactCandidate(
              name: cleaned,
              kind: _CandidateKind.attribute,
              reason: _ImpactReason.missing,
            ),
          );
        }
      }
    }

    for (final screen in feature.uxSpec.screens) {
      final screenTargetsObj =
          screen.primaryObjectId.trim().isNotEmpty &&
          _matchesObject(activeObj, screen.primaryObjectId);
      for (final zone in screen.zones) {
        for (final slot in zone.slots) {
          final slotObjId = slot.businessObjectId.trim();
          final targetsObj = slotObjId.isNotEmpty
              ? _matchesObject(activeObj, slotObjId)
              : screenTargetsObj;
          if (!targetsObj) continue;
          for (final rawAttr in slot.attributeNames) {
            final cleaned = _stripObjectPrefix(activeObj, rawAttr);
            if (cleaned.isEmpty) continue;
            if (!_objectHasAttributeOrRelation(activeObj, cleaned) &&
                seenNamesLower.add(cleaned.toLowerCase())) {
              candidates.add(
                _ImpactCandidate(
                  name: cleaned,
                  kind: _CandidateKind.attribute,
                  reason: _ImpactReason.missing,
                ),
              );
            }
          }
        }
      }
    }

    if (candidates.isEmpty) {
      return const <CrossFeatureDownstreamImpact>[];
    }
    return _collectDownstreamImpacts(
      targetFeature: feature,
      targetObj: activeObj,
      impactCandidates: candidates,
    );
  }

  static String _stripObjectPrefix(BusinessObjectSpec obj, String rawAttr) {
    var cleaned = rawAttr.trim().replaceAll('[?]', '').replaceAll('[]', '');
    if (cleaned.isEmpty) return '';
    final dot = cleaned.indexOf('.');
    if (dot > 0) {
      final prefix = cleaned.substring(0, dot).trim();
      if (_matchesObject(obj, prefix)) {
        cleaned = cleaned.substring(dot + 1).trim();
      }
    }
    return cleaned;
  }

  static bool _objectHasAttributeOrRelation(
    BusinessObjectSpec obj,
    String cleanedPath,
  ) {
    final segments = cleanedPath
        .split('.')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return false;
    if (segments.length == 1 &&
        obj.relations.any(
          (r) => r.name.toLowerCase() == segments.first.toLowerCase(),
        )) {
      return true;
    }
    List<BusinessAttribute> level = obj.attributes;
    for (var i = 0; i < segments.length; i++) {
      final segLower = segments[i].toLowerCase();
      BusinessAttribute? found;
      for (final a in level) {
        if (a.name.toLowerCase() == segLower ||
            a.id.toLowerCase() == segLower) {
          found = a;
          break;
        }
      }
      if (found == null) return false;
      if (i < segments.length - 1) {
        level = found.children;
      }
    }
    return true;
  }

  static String _formatCountSummary({
    required int count,
    required String singular,
    required List<String> names,
    required String prefix,
  }) {
    final preview = names.length <= 3
        ? names.map((n) => "'$n'").join(', ')
        : "${names.take(3).map((n) => "'$n'").join(', ')}, …";
    return '$prefix$count $singular ($preview)';
  }

  // ---------------------------------------------------------------------------
  // Détection des impacts aval RG / UX / QA dans une feature
  // ---------------------------------------------------------------------------

  static List<CrossFeatureDownstreamImpact> _collectDownstreamImpacts({
    required SpecFeatureSpec targetFeature,
    required BusinessObjectSpec targetObj,
    required List<_ImpactCandidate> impactCandidates,
  }) {
    if (impactCandidates.isEmpty) {
      return const <CrossFeatureDownstreamImpact>[];
    }

    final impacts = <CrossFeatureDownstreamImpact>[];
    final seenKeys = <String>{};
    final featCode = targetFeature.code.trim().isNotEmpty
        ? targetFeature.code.trim()
        : targetFeature.name.trim();
    final statusLabel = targetFeature.effectiveStatus.label;

    void recordImpact({
      required CrossFeatureDownstreamArea area,
      required String artifactRef,
      required String artifactTitle,
      required _ImpactCandidate candidate,
    }) {
      final key =
          '${area.name}|${artifactRef.toLowerCase()}|${candidate.name.toLowerCase()}';
      if (!seenKeys.add(key)) return;
      final summary = _buildImpactSummary(
        candidate: candidate,
        artifactRef: artifactRef,
        featureCode: featCode,
        statusLabel: statusLabel,
      );
      impacts.add(
        CrossFeatureDownstreamImpact(
          area: area,
          featureId: targetFeature.id,
          featureCode: featCode,
          artifactRef: artifactRef,
          artifactTitle: artifactTitle,
          attributeOrStateName: candidate.name,
          summary: summary,
        ),
      );
    }

    final impactedRuleRefsByAttrLower = <String, Set<String>>{};
    final impactedScreenRefsByAttrLower = <String, Set<String>>{};
    final impactedFixtureRefsByAttrLower = <String, Set<String>>{};

    // 1. Règles de gestion (RG)
    for (final rule in targetFeature.businessRules) {
      if (!rule.active) continue;
      final targetsObj = _ruleTargetsObject(rule, targetObj);
      final ruleRef = rule.code.trim().isNotEmpty ? rule.code.trim() : rule.id;

      for (final candidate in impactCandidates) {
        if (candidate.reason == _ImpactReason.addedRequiredWithoutDefault) {
          continue;
        }
        if (_ruleReferencesCandidate(
          rule: rule,
          targetObj: targetObj,
          ruleTargetsObj: targetsObj,
          candidate: candidate,
        )) {
          recordImpact(
            area: CrossFeatureDownstreamArea.businessRule,
            artifactRef: ruleRef,
            artifactTitle: rule.title,
            candidate: candidate,
          );
          final key = candidate.name.toLowerCase();
          final set = impactedRuleRefsByAttrLower[key] ??= <String>{};
          set.add(rule.id.toLowerCase());
          if (rule.code.trim().isNotEmpty) {
            set.add(rule.code.trim().toLowerCase());
          }
        }
      }
    }

    // 2. Écrans & blocs UX (SCR)
    for (final screen in targetFeature.uxSpec.screens) {
      final screenRef = screen.code.trim().isNotEmpty
          ? screen.code.trim()
          : screen.id;
      final screenTargetsObj =
          screen.primaryObjectId.trim().isNotEmpty &&
          _matchesObject(targetObj, screen.primaryObjectId);

      for (final candidate in impactCandidates) {
        if (candidate.reason == _ImpactReason.addedRequiredWithoutDefault) {
          continue;
        }
        if (_screenReferencesCandidate(
          screen: screen,
          targetObj: targetObj,
          screenTargetsObj: screenTargetsObj,
          candidate: candidate,
        )) {
          recordImpact(
            area: CrossFeatureDownstreamArea.ux,
            artifactRef: screenRef,
            artifactTitle: screen.name,
            candidate: candidate,
          );
          final key = candidate.name.toLowerCase();
          final set = impactedScreenRefsByAttrLower[key] ??= <String>{};
          set.add(screen.id.toLowerCase());
          if (screen.code.trim().isNotEmpty) {
            set.add(screen.code.trim().toLowerCase());
          }
          if (screen.routeId.trim().isNotEmpty) {
            set.add(screen.routeId.trim().toLowerCase());
          }
        }
      }
    }

    // 3a. QA — Jeux d'essais (FIX)
    for (final fixture in targetFeature.qaSpec.fixtures) {
      if (fixture.businessObjectId.trim().isEmpty ||
          !_matchesObject(targetObj, fixture.businessObjectId)) {
        continue;
      }
      final fixtureRef = fixture.code.trim().isNotEmpty
          ? fixture.code.trim()
          : fixture.id;

      for (final candidate in impactCandidates) {
        if (_fixtureImpactedByCandidate(fixture, candidate)) {
          recordImpact(
            area: CrossFeatureDownstreamArea.qa,
            artifactRef: fixtureRef,
            artifactTitle: fixture.name,
            candidate: candidate,
          );
          final key = candidate.name.toLowerCase();
          final set = impactedFixtureRefsByAttrLower[key] ??= <String>{};
          set.add(fixture.id.toLowerCase());
          if (fixture.code.trim().isNotEmpty) {
            set.add(fixture.code.trim().toLowerCase());
          }
        }
      }
    }

    // 3b. QA — Suites de tests unitaires TDD (TDD)
    for (final suite in targetFeature.qaSpec.tddSuites) {
      final suiteRef = suite.code.trim().isNotEmpty
          ? suite.code.trim()
          : suite.id;
      final suiteTargetsObj =
          suite.targetObjectId.trim().isNotEmpty &&
          _matchesObject(targetObj, suite.targetObjectId);

      for (final candidate in impactCandidates) {
        final key = candidate.name.toLowerCase();
        final impactedFixSet =
            impactedFixtureRefsByAttrLower[key] ?? const <String>{};
        final impactedRuleSet =
            impactedRuleRefsByAttrLower[key] ?? const <String>{};

        var matched = false;
        if (suiteTargetsObj &&
            candidate.reason != _ImpactReason.addedRequiredWithoutDefault &&
            _textMentionsCandidate(suite.description, candidate)) {
          matched = true;
        }
        if (!matched) {
          for (final tc in suite.cases) {
            if (tc.fixtureId.trim().isNotEmpty &&
                impactedFixSet.contains(tc.fixtureId.trim().toLowerCase())) {
              matched = true;
              break;
            }
            if (tc.businessRuleIds.any(
                  (r) => impactedRuleSet.contains(r.trim().toLowerCase()),
                ) &&
                _testCaseMentionsOrTargets(
                  suiteTargetsObj: suiteTargetsObj,
                  texts: <String>[
                    tc.title,
                    tc.arrange,
                    tc.act,
                    tc.assertExpected,
                    tc.expectedErrorMessage,
                  ],
                  candidate: candidate,
                )) {
              matched = true;
              break;
            }
            if (suiteTargetsObj &&
                candidate.reason != _ImpactReason.addedRequiredWithoutDefault &&
                _anyTextMentionsCandidate(<String>[
                  tc.title,
                  tc.arrange,
                  tc.act,
                  tc.assertExpected,
                  tc.expectedErrorMessage,
                ], candidate)) {
              matched = true;
              break;
            }
          }
        }

        if (matched) {
          recordImpact(
            area: CrossFeatureDownstreamArea.qa,
            artifactRef: suiteRef,
            artifactTitle: suite.name,
            candidate: candidate,
          );
        }
      }
    }

    // 3c. QA — Fonctionnalités / scénarios Gherkin (SCN / FEAT)
    for (final ghFeature in targetFeature.qaSpec.features) {
      for (final scenario in ghFeature.scenarios) {
        final scnRef =
            scenario.code.trim().isNotEmpty &&
                scenario.code.trim().toUpperCase() != 'SCN'
            ? scenario.code.trim()
            : (ghFeature.code.trim().isNotEmpty
                  ? ghFeature.code.trim()
                  : scenario.id);

        for (final candidate in impactCandidates) {
          if (candidate.reason == _ImpactReason.addedRequiredWithoutDefault) {
            continue;
          }
          final key = candidate.name.toLowerCase();
          final impactedFixSet =
              impactedFixtureRefsByAttrLower[key] ?? const <String>{};
          final impactedRuleSet =
              impactedRuleRefsByAttrLower[key] ?? const <String>{};
          final impactedScrSet =
              impactedScreenRefsByAttrLower[key] ?? const <String>{};

          final linkedToObjContext =
              scenario.fixtureIds.any(
                (f) => impactedFixSet.contains(f.trim().toLowerCase()),
              ) ||
              scenario.businessRuleIds.any(
                (r) => impactedRuleSet.contains(r.trim().toLowerCase()),
              ) ||
              scenario.screenIds.any(
                (s) => impactedScrSet.contains(s.trim().toLowerCase()),
              ) ||
              _textMentionsToken(ghFeature.title, targetObj.name) ||
              _textMentionsToken(ghFeature.title, targetObj.technicalName) ||
              _textMentionsToken(scenario.title, targetObj.name) ||
              _textMentionsToken(scenario.title, targetObj.technicalName);

          if (!linkedToObjContext) continue;

          final headerHit = scenario.examples.headers.any(
            (h) =>
                h.trim().toLowerCase() == candidate.leafName.toLowerCase() ||
                h.trim().toLowerCase() == candidate.name.toLowerCase(),
          );
          final stepTexts = <String>[
            scenario.title,
            for (final s in scenario.steps) ...<String>[s.text, s.docString],
          ];
          if (headerHit || _anyTextMentionsCandidate(stepTexts, candidate)) {
            recordImpact(
              area: CrossFeatureDownstreamArea.qa,
              artifactRef: scnRef,
              artifactTitle: scenario.title,
              candidate: candidate,
            );
          }
        }
      }
    }

    return impacts;
  }

  static String _buildImpactSummary({
    required _ImpactCandidate candidate,
    required String artifactRef,
    required String featureCode,
    required String statusLabel,
  }) {
    final noun = switch (candidate.kind) {
      _CandidateKind.attribute => "L'attribut '${candidate.name}'",
      _CandidateKind.relation => "La relation '${candidate.name}'",
      _CandidateKind.lifecycleState => "L'état '${candidate.name}'",
    };
    return switch (candidate.reason) {
      _ImpactReason.missing =>
        '$noun absent est référencé par $artifactRef dans $featureCode ($statusLabel).',
      _ImpactReason.incompatible =>
        '$noun modifié est référencé par $artifactRef dans $featureCode ($statusLabel).',
      _ImpactReason.addedRequiredWithoutDefault =>
        "L'attribut obligatoire '${candidate.name}' (sans valeur par défaut) impacte $artifactRef dans $featureCode ($statusLabel).",
    };
  }

  static bool _matchesObject(BusinessObjectSpec obj, String rawRef) {
    final needle = rawRef.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return obj.id.trim().toLowerCase() == needle ||
        obj.technicalName.trim().toLowerCase() == needle ||
        obj.name.trim().toLowerCase() == needle;
  }

  static bool _ruleTargetsObject(
    BusinessRuleSpec rule,
    BusinessObjectSpec obj,
  ) {
    for (final target in rule.targetObjectIds) {
      if (_matchesObject(obj, target)) return true;
    }
    for (final rawAttr in rule.targetAttributes) {
      final dot = rawAttr.indexOf('.');
      if (dot > 0) {
        final prefix = rawAttr.substring(0, dot).trim();
        if (_matchesObject(obj, prefix)) return true;
      }
    }
    return false;
  }

  static bool _ruleReferencesCandidate({
    required BusinessRuleSpec rule,
    required BusinessObjectSpec targetObj,
    required bool ruleTargetsObj,
    required _ImpactCandidate candidate,
  }) {
    for (final rawAttr in rule.targetAttributes) {
      final cleaned = rawAttr
          .trim()
          .replaceAll('[?]', '')
          .replaceAll('[]', '');
      if (cleaned.isEmpty) continue;
      final dot = cleaned.indexOf('.');
      if (dot > 0) {
        final prefix = cleaned.substring(0, dot).trim();
        final rest = cleaned.substring(dot + 1).trim();
        if (_matchesObject(targetObj, prefix)) {
          if (_pathMatchesCandidate(rest, candidate)) return true;
          continue;
        }
      }
      if (ruleTargetsObj && _pathMatchesCandidate(cleaned, candidate)) {
        return true;
      }
    }

    if (!ruleTargetsObj) return false;
    return _anyTextMentionsCandidate(<String>[
      rule.condition,
      rule.effect,
      rule.trigger,
      rule.description,
      ...rule.examples,
    ], candidate);
  }

  static bool _screenReferencesCandidate({
    required UxScreenSpec screen,
    required BusinessObjectSpec targetObj,
    required bool screenTargetsObj,
    required _ImpactCandidate candidate,
  }) {
    for (final zone in screen.zones) {
      for (final slot in zone.slots) {
        final String slotObjId = slot.businessObjectId.trim();
        final bool slotTargetsObj = slotObjId.isNotEmpty
            ? _matchesObject(targetObj, slotObjId)
            : screenTargetsObj;
        if (!slotTargetsObj) continue;

        for (final String rawAttr in slot.attributeNames) {
          var cleaned = rawAttr
              .trim()
              .replaceAll('[?]', '')
              .replaceAll('[]', '');
          if (cleaned.isEmpty) continue;
          final dot = cleaned.indexOf('.');
          if (dot > 0) {
            final prefix = cleaned.substring(0, dot).trim();
            if (_matchesObject(targetObj, prefix)) {
              cleaned = cleaned.substring(dot + 1).trim();
            }
          }
          if (_pathMatchesCandidate(cleaned, candidate)) {
            return true;
          }
        }

        if (_textMentionsCandidate(slot.summary, candidate)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _fixtureImpactedByCandidate(
    QaFixtureSpec fixture,
    _ImpactCandidate candidate,
  ) {
    if (candidate.reason == _ImpactReason.addedRequiredWithoutDefault) {
      if (!fixture.expectedValid || fixture.payload.isEmpty) return false;
      return !_payloadHasPath(fixture.payload, candidate.name);
    }

    if (candidate.kind == _CandidateKind.lifecycleState) {
      if (_payloadContainsScalarValue(fixture.payload, candidate.name)) {
        return true;
      }
      return _textMentionsCandidate(fixture.description, candidate) ||
          _textMentionsCandidate(fixture.expectedErrorHint, candidate);
    }

    if (_payloadHasPath(fixture.payload, candidate.name)) {
      if (candidate.removedEnumValues.isNotEmpty) {
        final val = _payloadValueAtPath(fixture.payload, candidate.name);
        if (val != null &&
            candidate.removedEnumValues.any(
              (ev) => ev.toLowerCase() == '$val'.trim().toLowerCase(),
            )) {
          return true;
        }
      }
      return true;
    }

    return _textMentionsCandidate(fixture.description, candidate) ||
        _textMentionsCandidate(fixture.expectedErrorHint, candidate);
  }

  static bool _testCaseMentionsOrTargets({
    required bool suiteTargetsObj,
    required List<String> texts,
    required _ImpactCandidate candidate,
  }) {
    if (_anyTextMentionsCandidate(texts, candidate)) return true;
    return suiteTargetsObj;
  }

  static bool _pathMatchesCandidate(String rawPath, _ImpactCandidate candidate) {
    final lower = rawPath.trim().toLowerCase();
    if (lower.isEmpty) return false;
    final candLower = candidate.name.toLowerCase();
    if (lower == candLower || lower.startsWith('$candLower.')) return true;
    if (!lower.contains('.') &&
        lower == candidate.leafName.toLowerCase() &&
        !candidate.name.contains('.')) {
      return true;
    }
    return false;
  }

  static bool _payloadHasPath(Map<String, Object?> payload, String path) {
    if (payload.isEmpty) return false;
    final segments = path
        .split('.')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return false;

    bool checkNode(Object? current, int index) {
      if (index >= segments.length) return true;
      final segLower = segments[index].toLowerCase();
      if (current is Map) {
        for (final entry in current.entries) {
          if ('${entry.key}'.trim().toLowerCase() == segLower) {
            return checkNode(entry.value, index + 1);
          }
        }
        return false;
      }
      if (current is List) {
        return current.any((item) => checkNode(item, index));
      }
      return false;
    }

    return checkNode(payload, 0);
  }

  static Object? _payloadValueAtPath(
    Map<String, Object?> payload,
    String path,
  ) {
    final segments = path
        .split('.')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    Object? current = payload;
    for (final seg in segments) {
      if (current is! Map) return null;
      final segLower = seg.toLowerCase();
      Object? found;
      var hit = false;
      for (final entry in current.entries) {
        if ('${entry.key}'.trim().toLowerCase() == segLower) {
          found = entry.value;
          hit = true;
          break;
        }
      }
      if (!hit) return null;
      current = found;
    }
    return current;
  }

  static bool _payloadContainsScalarValue(
    Map<String, Object?> payload,
    String expected,
  ) {
    final lower = expected.trim().toLowerCase();
    bool visit(Object? value) {
      if (value is String) return value.trim().toLowerCase() == lower;
      if (value is Map) return value.values.any(visit);
      if (value is Iterable) return value.any(visit);
      return false;
    }

    return visit(payload);
  }

  static bool _anyTextMentionsCandidate(
    Iterable<String> texts,
    _ImpactCandidate candidate,
  ) {
    for (final text in texts) {
      if (_textMentionsCandidate(text, candidate)) return true;
    }
    return false;
  }

  static bool _textMentionsCandidate(String text, _ImpactCandidate candidate) {
    if (text.trim().isEmpty) return false;
    if (_textMentionsToken(text, candidate.name)) return true;
    if (candidate.leafName != candidate.name &&
        _textMentionsToken(text, candidate.leafName)) {
      return true;
    }
    for (final alias in candidate.aliases) {
      if (_textMentionsToken(text, alias)) return true;
    }
    return false;
  }

  static bool _textMentionsToken(String text, String token) {
    final trimmed = token.trim();
    if (text.trim().isEmpty || trimmed.isEmpty) return false;
    final pattern = RegExp(
      '(?<![A-Za-z0-9_])${RegExp.escape(trimmed)}(?![A-Za-z0-9_])',
      caseSensitive: false,
    );
    return pattern.hasMatch(text);
  }
}

enum _CandidateKind { attribute, relation, lifecycleState }

enum _ImpactReason { missing, incompatible, addedRequiredWithoutDefault }

class _ImpactCandidate {
  const _ImpactCandidate({
    required this.name,
    required this.kind,
    required this.reason,
    this.aliases = const <String>[],
    this.removedEnumValues = const <String>[],
  });

  final String name;
  final _CandidateKind kind;
  final _ImpactReason reason;
  final List<String> aliases;
  final List<String> removedEnumValues;

  String get leafName {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1) : name;
  }
}

class _ComparisonAccumulator {
  _ComparisonAccumulator({
    required this.activeFeature,
    required this.activeObj,
    required this.siblingFeature,
    required this.siblingObj,
    required this.isSiblingValidated,
    required this.treatUnimportedSiblingExtensionsAsBreaking,
    required this.syncBaselineObject,
    this.siblingSyncedFromActiveObject,
  });

  final SpecFeatureSpec activeFeature;
  final BusinessObjectSpec activeObj;
  final SpecFeatureSpec siblingFeature;
  final BusinessObjectSpec siblingObj;
  final bool isSiblingValidated;
  final bool treatUnimportedSiblingExtensionsAsBreaking;
  final BusinessObjectSpec? syncBaselineObject;
  final BusinessObjectSpec? siblingSyncedFromActiveObject;

  bool hasBreaking = false;
  bool hasAdditive = false;
  bool hasMissingOptionalFromSibling = false;

  final List<String> breakingSummaries = <String>[];
  final List<String> addedOptionalAttrs = <String>[];
  final List<String> additiveDetailSummaries = <String>[];
  final List<String> missingOptionalSummaries = <String>[];
  final List<_ImpactCandidate> impactCandidates = <_ImpactCandidate>[];

  void compareObjects() {
    if (siblingObj.aggregateRoot != activeObj.aggregateRoot) {
      hasBreaking = true;
      breakingSummaries.add(
        '~ nature Aggregate Root modifiée (${siblingObj.aggregateRoot} vs ${activeObj.aggregateRoot})',
      );
    }

    _compareAttributeLists(
      sibAttrs: siblingObj.attributes,
      actAttrs: activeObj.attributes,
      baseAttrs: syncBaselineObject?.attributes ?? const <BusinessAttribute>[],
      sibFromActAttrs:
          siblingSyncedFromActiveObject?.attributes ??
          const <BusinessAttribute>[],
      prefix: '',
    );
    _compareRelations();
    _compareLifecycle();
  }

  void _compareAttributeLists({
    required List<BusinessAttribute> sibAttrs,
    required List<BusinessAttribute> actAttrs,
    required List<BusinessAttribute> baseAttrs,
    required List<BusinessAttribute> sibFromActAttrs,
    required String prefix,
  }) {
    final matchedSibIndices = <int>{};
    final actToSib = <int, int>{};

    // 1. Appariement par identifiant exact.
    for (var ai = 0; ai < actAttrs.length; ai++) {
      for (var si = 0; si < sibAttrs.length; si++) {
        if (matchedSibIndices.contains(si)) continue;
        if (sibAttrs[si].id == actAttrs[ai].id) {
          actToSib[ai] = si;
          matchedSibIndices.add(si);
          break;
        }
      }
    }

    // 2. Appariement par nom (insensible à la casse).
    for (var ai = 0; ai < actAttrs.length; ai++) {
      if (actToSib.containsKey(ai)) continue;
      final lower = actAttrs[ai].name.toLowerCase();
      for (var si = 0; si < sibAttrs.length; si++) {
        if (matchedSibIndices.contains(si)) continue;
        if (sibAttrs[si].name.toLowerCase() == lower) {
          actToSib[ai] = si;
          matchedSibIndices.add(si);
          break;
        }
      }
    }

    // 3. Attributs présents dans activeObj (ajoutés ou partagés).
    for (var ai = 0; ai < actAttrs.length; ai++) {
      final actAttr = actAttrs[ai];
      final path = prefix.isEmpty ? actAttr.name : '$prefix.${actAttr.name}';
      final si = actToSib[ai];

      if (si == null) {
        final hasDefault =
            actAttr.defaultValue != null &&
            actAttr.defaultValue!.trim().isNotEmpty;
        if (actAttr.required && !hasDefault) {
          hasBreaking = true;
          breakingSummaries.add(
            "+ attribut obligatoire '$path' sans valeur par défaut",
          );
          impactCandidates.add(
            _ImpactCandidate(
              name: path,
              kind: _CandidateKind.attribute,
              reason: _ImpactReason.addedRequiredWithoutDefault,
            ),
          );
        } else {
          hasAdditive = true;
          addedOptionalAttrs.add(path);
        }
        continue;
      }

      final sibAttr = sibAttrs[si];
      final sibPath = prefix.isEmpty ? sibAttr.name : '$prefix.${sibAttr.name}';
      final baseChildAttrs = _findMatchingAttr(baseAttrs, sibAttr)?.children ??
          const <BusinessAttribute>[];
      final sibFromActChildAttrs =
          _findMatchingAttr(sibFromActAttrs, sibAttr)?.children ??
          const <BusinessAttribute>[];

      _compareSharedAttribute(
        sibAttr: sibAttr,
        actAttr: actAttr,
        sibPath: sibPath,
        actPath: path,
        baseChildAttrs: baseChildAttrs,
        sibFromActChildAttrs: sibFromActChildAttrs,
      );
    }

    // 4. Attributs présents dans siblingObj mais absents dans activeObj.
    for (var si = 0; si < sibAttrs.length; si++) {
      if (matchedSibIndices.contains(si)) continue;
      final sibAttr = sibAttrs[si];
      final sibPath = prefix.isEmpty ? sibAttr.name : '$prefix.${sibAttr.name}';
      final wasInSyncBaseline = _findMatchingAttr(baseAttrs, sibAttr) != null;
      final addedBySiblingOnTopOfActive =
          siblingSyncedFromActiveObject != null &&
          _findMatchingAttr(sibFromActAttrs, sibAttr) == null;

      if (sibAttr.required || wasInSyncBaseline) {
        hasBreaking = true;
        breakingSummaries.add("- attribut '$sibPath' absent");
        impactCandidates.add(
          _ImpactCandidate(
            name: sibPath,
            kind: _CandidateKind.attribute,
            reason: _ImpactReason.missing,
          ),
        );
      } else if (treatUnimportedSiblingExtensionsAsBreaking &&
          !addedBySiblingOnTopOfActive) {
        // Pour une feature sœur validée face à une feature non validée : si cet
        // attribut optionnel est référencé par RG/UX/QA de la feature validée,
        // _buildSiblingLink le promouvra en breaking.
        missingOptionalSummaries.add("- attribut '$sibPath' absent");
        hasMissingOptionalFromSibling = true;
        impactCandidates.add(
          _ImpactCandidate(
            name: sibPath,
            kind: _CandidateKind.attribute,
            reason: _ImpactReason.missing,
          ),
        );
      } else {
        hasMissingOptionalFromSibling = true;
        missingOptionalSummaries.add(
          "- attribut optionnel '$sibPath' non importé",
        );
      }
    }
  }

  BusinessAttribute? _findMatchingAttr(
    List<BusinessAttribute> list,
    BusinessAttribute needle,
  ) {
    for (final item in list) {
      if (item.id == needle.id ||
          item.name.toLowerCase() == needle.name.toLowerCase()) {
        return item;
      }
    }
    return null;
  }

  void _compareSharedAttribute({
    required BusinessAttribute sibAttr,
    required BusinessAttribute actAttr,
    required String sibPath,
    required String actPath,
    required List<BusinessAttribute> baseChildAttrs,
    required List<BusinessAttribute> sibFromActChildAttrs,
  }) {
    var attrBroken = false;
    final removedEnumValues = <String>[];

    if (sibAttr.name.toLowerCase() != actAttr.name.toLowerCase()) {
      attrBroken = true;
      breakingSummaries.add(
        "~ attribut '$sibPath' renommé en '$actPath'",
      );
    }

    if (sibAttr.type != actAttr.type) {
      attrBroken = true;
      breakingSummaries.add(
        "~ type de '$sibPath' : ${sibAttr.type.name} vs ${actAttr.type.name}",
      );
    }

    if (sibAttr.isArray != actAttr.isArray) {
      attrBroken = true;
      breakingSummaries.add(
        "~ cardinalité de '$sibPath' : ${sibAttr.isArray ? 'tableau' : 'scalaire'} vs ${actAttr.isArray ? 'tableau' : 'scalaire'}",
      );
    }

    if (sibAttr.type == BusinessAttributeType.reference &&
        actAttr.type == BusinessAttributeType.reference) {
      final sibTarget = _canonicalObjectRef(
        siblingFeature,
        sibAttr.referenceObjectId,
      );
      final actTarget = _canonicalObjectRef(
        activeFeature,
        actAttr.referenceObjectId,
      );
      if (sibTarget != actTarget) {
        attrBroken = true;
        breakingSummaries.add(
          "~ cible de référence sur '$sibPath' : $sibTarget vs $actTarget",
        );
      }
    }

    if (sibAttr.type == BusinessAttributeType.valueObject &&
        actAttr.type == BusinessAttributeType.valueObject) {
      final sibVo = sibAttr.valueObjectId.trim().toLowerCase();
      final actVo = actAttr.valueObjectId.trim().toLowerCase();
      if (sibVo != actVo) {
        attrBroken = true;
        breakingSummaries.add(
          "~ Value Object de '$sibPath' : '${sibAttr.valueObjectId}' vs '${actAttr.valueObjectId}'",
        );
      }
    }

    if (sibAttr.required != actAttr.required) {
      if (actAttr.required) {
        attrBroken = true;
        breakingSummaries.add(
          "~ obligation durcie sur '$sibPath' : optionnel → obligatoire",
        );
      } else {
        hasAdditive = true;
        additiveDetailSummaries.add(
          "~ obligation assouplie sur '$sibPath' (devenu optionnel)",
        );
      }
    }

    if (sibAttr.nullable != actAttr.nullable) {
      if (!actAttr.nullable) {
        attrBroken = true;
        breakingSummaries.add(
          "~ nullabilité durcie sur '$sibPath' : nullable → non-nullable",
        );
      } else {
        hasAdditive = true;
        additiveDetailSummaries.add(
          "~ nullabilité assouplie sur '$sibPath' (rendu nullable)",
        );
      }
    }

    if (sibAttr.unique != actAttr.unique) {
      if (actAttr.unique) {
        attrBroken = true;
        breakingSummaries.add("~ unicité imposée sur '$sibPath'");
      } else {
        hasAdditive = true;
        additiveDetailSummaries.add("~ unicité assouplie sur '$sibPath'");
      }
    }

    if (sibAttr.enumValues.isNotEmpty || actAttr.enumValues.isNotEmpty) {
      final sibSet = sibAttr.enumValues.toSet();
      final actSet = actAttr.enumValues.toSet();
      final removed = sibAttr.enumValues
          .where((v) => !actSet.contains(v))
          .toList();
      final added = actAttr.enumValues
          .where((v) => !sibSet.contains(v))
          .toList();
      if (removed.isNotEmpty) {
        attrBroken = true;
        removedEnumValues.addAll(removed);
        breakingSummaries.add(
          "- valeur(s) d'énumération retirée(s) sur '$sibPath' : ${removed.join(', ')}",
        );
      }
      if (added.isNotEmpty) {
        hasAdditive = true;
        additiveDetailSummaries.add(
          "+${added.length} valeur(s) d'énumération sur '$sibPath' (${added.join(', ')})",
        );
      }
    }

    final constraintDiff = _compareConstraints(
      sibAttr.schemaConstraints,
      actAttr.schemaConstraints,
      sibPath,
    );
    if (constraintDiff.breakingReasons.isNotEmpty) {
      attrBroken = true;
      breakingSummaries.addAll(constraintDiff.breakingReasons);
    }
    if (constraintDiff.additiveReasons.isNotEmpty) {
      hasAdditive = true;
      additiveDetailSummaries.addAll(constraintDiff.additiveReasons);
    }

    if (attrBroken) {
      hasBreaking = true;
      impactCandidates.add(
        _ImpactCandidate(
          name: sibPath,
          kind: _CandidateKind.attribute,
          reason: _ImpactReason.incompatible,
          aliases: actPath.toLowerCase() != sibPath.toLowerCase()
              ? <String>[actPath]
              : const <String>[],
          removedEnumValues: removedEnumValues,
        ),
      );
    }

    if (sibAttr.children.isNotEmpty || actAttr.children.isNotEmpty) {
      _compareAttributeLists(
        sibAttrs: sibAttr.children,
        actAttrs: actAttr.children,
        baseAttrs: baseChildAttrs,
        sibFromActAttrs: sibFromActChildAttrs,
        prefix: sibPath,
      );
    }
  }

  ({List<String> breakingReasons, List<String> additiveReasons})
  _compareConstraints(
    JsonSchemaConstraints sib,
    JsonSchemaConstraints act,
    String path,
  ) {
    if (sib == act) {
      return (
        breakingReasons: const <String>[],
        additiveReasons: const <String>[],
      );
    }
    final breaking = <String>[];
    final additive = <String>[];

    void checkLower(String kw, num? s, num? a, {bool ignoreZeroAdd = false}) {
      if (s == a) return;
      if (s == null && a != null) {
        if (ignoreZeroAdd && a <= 0) return;
        breaking.add("~ contrainte $kw ajoutée sur '$path' ($a)");
      } else if (s != null && a == null) {
        additive.add("~ contrainte $kw retirée sur '$path'");
      } else if (s != null && a != null) {
        if (a > s) {
          breaking.add("~ contrainte $kw durcie sur '$path' ($s → $a)");
        } else {
          additive.add("~ contrainte $kw assouplie sur '$path' ($s → $a)");
        }
      }
    }

    void checkUpper(String kw, num? s, num? a) {
      if (s == a) return;
      if (s == null && a != null) {
        breaking.add("~ contrainte $kw ajoutée sur '$path' ($a)");
      } else if (s != null && a == null) {
        additive.add("~ contrainte $kw retirée sur '$path'");
      } else if (s != null && a != null) {
        if (a < s) {
          breaking.add("~ contrainte $kw réduite sur '$path' ($s → $a)");
        } else {
          additive.add("~ contrainte $kw assouplie sur '$path' ($s → $a)");
        }
      }
    }

    checkLower('minimum', sib.minimum, act.minimum);
    checkUpper('maximum', sib.maximum, act.maximum);
    checkLower('exclusiveMinimum', sib.exclusiveMinimum, act.exclusiveMinimum);
    checkUpper('exclusiveMaximum', sib.exclusiveMaximum, act.exclusiveMaximum);
    checkLower(
      'minLength',
      sib.minLength,
      act.minLength,
      ignoreZeroAdd: true,
    );
    checkUpper('maxLength', sib.maxLength, act.maxLength);
    checkLower('minItems', sib.minItems, act.minItems, ignoreZeroAdd: true);
    checkUpper('maxItems', sib.maxItems, act.maxItems);
    checkLower(
      'minProperties',
      sib.minProperties,
      act.minProperties,
      ignoreZeroAdd: true,
    );
    checkUpper('maxProperties', sib.maxProperties, act.maxProperties);
    checkLower(
      'minContains',
      sib.minContains,
      act.minContains,
      ignoreZeroAdd: true,
    );
    checkUpper('maxContains', sib.maxContains, act.maxContains);

    String? cleanOpt(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();

    final sibPat = cleanOpt(sib.pattern);
    final actPat = cleanOpt(act.pattern);
    if (sibPat != actPat) {
      if (actPat == null) {
        additive.add("~ pattern retiré sur '$path'");
      } else {
        breaking.add("~ pattern modifié sur '$path' ($actPat)");
      }
    }

    final sibFmt = cleanOpt(sib.format);
    final actFmt = cleanOpt(act.format);
    if (sibFmt != actFmt) {
      if (actFmt == null) {
        additive.add("~ format retiré sur '$path'");
      } else {
        breaking.add("~ format modifié sur '$path' ($actFmt)");
      }
    }

    if (sib.multipleOf != act.multipleOf) {
      if (act.multipleOf == null) {
        additive.add("~ multipleOf retiré sur '$path'");
      } else {
        breaking.add("~ multipleOf modifié sur '$path' (${act.multipleOf})");
      }
    }

    final sibUnique = sib.uniqueItems == true;
    final actUnique = act.uniqueItems == true;
    if (sibUnique != actUnique) {
      if (actUnique) {
        breaking.add("~ uniqueItems activé sur '$path'");
      } else {
        additive.add("~ uniqueItems désactivé sur '$path'");
      }
    }

    if (sib.hasConst != act.hasConst ||
        (act.hasConst && sib.constValue != act.constValue)) {
      if (!act.hasConst) {
        additive.add("~ valeur constante retirée sur '$path'");
      } else {
        breaking.add("~ valeur constante imposée sur '$path'");
      }
    }

    return (breakingReasons: breaking, additiveReasons: additive);
  }

  void _compareRelations() {
    final matchedSibIdx = <int>{};
    final addedOptRels = <String>[];
    final baseRels = syncBaselineObject?.relations ?? const <BusinessRelation>[];

    for (final actRel in activeObj.relations) {
      var si = -1;
      for (var i = 0; i < siblingObj.relations.length; i++) {
        if (matchedSibIdx.contains(i)) continue;
        final s = siblingObj.relations[i];
        if (s.id == actRel.id ||
            s.name.toLowerCase() == actRel.name.toLowerCase()) {
          si = i;
          break;
        }
      }
      if (si < 0) {
        if (actRel.required) {
          hasBreaking = true;
          breakingSummaries.add(
            "+ relation obligatoire '${actRel.name}' ajoutée",
          );
        } else {
          hasAdditive = true;
          addedOptRels.add(actRel.name);
        }
        continue;
      }

      matchedSibIdx.add(si);
      final sibRel = siblingObj.relations[si];
      final sibTarget = _canonicalObjectRef(
        siblingFeature,
        sibRel.targetObjectId,
      );
      final actTarget = _canonicalObjectRef(
        activeFeature,
        actRel.targetObjectId,
      );

      if (sibRel.name.toLowerCase() != actRel.name.toLowerCase() ||
          sibTarget != actTarget ||
          sibRel.cardinality != actRel.cardinality ||
          (!sibRel.required && actRel.required)) {
        hasBreaking = true;
        breakingSummaries.add("~ relation '${sibRel.name}' incompatible");
        impactCandidates.add(
          _ImpactCandidate(
            name: sibRel.name,
            kind: _CandidateKind.relation,
            reason: _ImpactReason.incompatible,
          ),
        );
      } else if (sibRel.required && !actRel.required) {
        hasAdditive = true;
        additiveDetailSummaries.add(
          "~ relation '${sibRel.name}' rendue optionnelle",
        );
      }
    }

    if (addedOptRels.isNotEmpty) {
      additiveDetailSummaries.add(
        '+${addedOptRels.length} relation(s) optionnelle(s) (${addedOptRels.join(', ')})',
      );
    }

    for (var i = 0; i < siblingObj.relations.length; i++) {
      if (matchedSibIdx.contains(i)) continue;
      final sibRel = siblingObj.relations[i];
      final wasInBase = baseRels.any(
        (r) =>
            r.id == sibRel.id ||
            r.name.toLowerCase() == sibRel.name.toLowerCase(),
      );
      if (sibRel.required || wasInBase) {
        hasBreaking = true;
        breakingSummaries.add("- relation '${sibRel.name}' absente");
        impactCandidates.add(
          _ImpactCandidate(
            name: sibRel.name,
            kind: _CandidateKind.relation,
            reason: _ImpactReason.missing,
          ),
        );
      } else if (treatUnimportedSiblingExtensionsAsBreaking) {
        hasMissingOptionalFromSibling = true;
        missingOptionalSummaries.add("- relation '${sibRel.name}' absente");
        impactCandidates.add(
          _ImpactCandidate(
            name: sibRel.name,
            kind: _CandidateKind.relation,
            reason: _ImpactReason.missing,
          ),
        );
      } else {
        hasMissingOptionalFromSibling = true;
        missingOptionalSummaries.add(
          "- relation optionnelle '${sibRel.name}' non importée",
        );
      }
    }
  }

  void _compareLifecycle() {
    final sibStatesByLower = <String, LifecycleState>{
      for (final s in siblingObj.lifecycleStates) s.name.toLowerCase(): s,
    };
    final actStatesByLower = <String, LifecycleState>{
      for (final s in activeObj.lifecycleStates) s.name.toLowerCase(): s,
    };
    final baseStatesLower = <String>{
      for (final s in syncBaselineObject?.lifecycleStates ??
          const <LifecycleState>[])
        s.name.toLowerCase(),
    };

    final addedStates = <String>[];
    for (final actState in activeObj.lifecycleStates) {
      final lower = actState.name.toLowerCase();
      final sibState = sibStatesByLower[lower];
      if (sibState == null) {
        hasAdditive = true;
        addedStates.add(actState.name);
      } else if (sibState.isInitial && !actState.isInitial) {
        hasBreaking = true;
        breakingSummaries.add(
          "~ état initial '${sibState.name}' retiré",
        );
        impactCandidates.add(
          _ImpactCandidate(
            name: sibState.name,
            kind: _CandidateKind.lifecycleState,
            reason: _ImpactReason.incompatible,
          ),
        );
      }
    }
    if (addedStates.isNotEmpty) {
      additiveDetailSummaries.add(
        '+${addedStates.length} état(s) de cycle de vie (${addedStates.join(', ')})',
      );
    }

    final sibFromActStatesLower = <String>{
      for (final s in siblingSyncedFromActiveObject?.lifecycleStates ??
          const <LifecycleState>[])
        s.name.toLowerCase(),
    };

    for (final sibState in siblingObj.lifecycleStates) {
      final lower = sibState.name.toLowerCase();
      if (actStatesByLower.containsKey(lower)) continue;
      final wasInBase = baseStatesLower.contains(lower);
      final addedBySiblingOnTopOfActive =
          siblingSyncedFromActiveObject != null &&
          !sibFromActStatesLower.contains(lower);
      if (sibState.isInitial ||
          wasInBase ||
          (treatUnimportedSiblingExtensionsAsBreaking &&
              !addedBySiblingOnTopOfActive)) {
        hasBreaking = true;
        breakingSummaries.add(
          "- état de cycle de vie '${sibState.name}' absent",
        );
        impactCandidates.add(
          _ImpactCandidate(
            name: sibState.name,
            kind: _CandidateKind.lifecycleState,
            reason: _ImpactReason.missing,
          ),
        );
      } else {
        hasMissingOptionalFromSibling = true;
        missingOptionalSummaries.add(
          "- état de cycle de vie '${sibState.name}' non importé",
        );
      }
    }

    String trKey(LifecycleTransition t) =>
        '${t.fromState.trim().toLowerCase()}->${t.toState.trim().toLowerCase()}';

    final sibTrKeys = <String, LifecycleTransition>{
      for (final t in siblingObj.lifecycleTransitions) trKey(t): t,
    };
    final actTrKeys = <String, LifecycleTransition>{
      for (final t in activeObj.lifecycleTransitions) trKey(t): t,
    };
    final baseTrKeys = <String>{
      for (final t in syncBaselineObject?.lifecycleTransitions ??
          const <LifecycleTransition>[])
        trKey(t),
    };

    var addedTrCount = 0;
    for (final key in actTrKeys.keys) {
      if (!sibTrKeys.containsKey(key)) {
        addedTrCount++;
      }
    }
    if (addedTrCount > 0) {
      hasAdditive = true;
      additiveDetailSummaries.add(
        '+$addedTrCount transition(s) de cycle de vie',
      );
    }

    final sibFromActTrKeys = <String>{
      for (final t in siblingSyncedFromActiveObject?.lifecycleTransitions ??
          const <LifecycleTransition>[])
        trKey(t),
    };

    for (final entry in sibTrKeys.entries) {
      if (actTrKeys.containsKey(entry.key)) continue;
      final tr = entry.value;
      final addedBySiblingOnTopOfActive =
          siblingSyncedFromActiveObject != null &&
          !sibFromActTrKeys.contains(entry.key);
      if (baseTrKeys.contains(entry.key) ||
          (treatUnimportedSiblingExtensionsAsBreaking &&
              !addedBySiblingOnTopOfActive)) {
        hasBreaking = true;
        breakingSummaries.add(
          "- transition '${tr.fromState} → ${tr.toState}' absente",
        );
      } else {
        hasMissingOptionalFromSibling = true;
        missingOptionalSummaries.add(
          "- transition '${tr.fromState} → ${tr.toState}' non importée",
        );
      }
    }
  }

  static String _canonicalObjectRef(SpecFeatureSpec feature, String rawRef) {
    final trimmed = rawRef.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    for (final obj in feature.businessObjects) {
      if (obj.id.trim().toLowerCase() == lower ||
          obj.technicalName.trim().toLowerCase() == lower ||
          obj.name.trim().toLowerCase() == lower) {
        return obj.technicalName.trim().toLowerCase();
      }
    }
    return lower;
  }
}
