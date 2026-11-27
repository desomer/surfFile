/// Générateur déterministe et non destructif d'amorçage WBS, Run OPEX et Risques EMV depuis les artefacts du projet ([CostAutoSeeder], [CostSeedResult], [CostCoverageGaps]).
library;

import 'package:flutter/foundation.dart';

import '../models/business_object_spec.dart';
import '../models/cost/cost_forge_spec.dart';
import '../models/cost/cost_risk_item_spec.dart';
import '../models/cost/cost_run_item_spec.dart';
import '../models/cost/cost_wbs_item_spec.dart';
import '../models/enterprise_rate_card.dart';
import '../models/event_storming_spec.dart';
import '../models/qa/gherkin_feature_spec.dart';
import '../models/qa/tdd_suite_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_forge_project.dart';
import '../models/ux/ux_screen_spec.dart';

/// Résultat immuable d'un amorçage automatique FinOps sur un [SpecForgeProject].
@immutable
class CostSeedResult {
  /// Construit le bilan d'un pré-remplissage FinOps.
  const CostSeedResult({
    required this.spec,
    this.addedWbsCount = 0,
    this.addedRunCount = 0,
    this.addedRiskCount = 0,
  });

  /// Spécification de chiffrage enrichie (préservant l'intégralité des éléments existants).
  final CostForgeSpec spec;

  /// Nombre de lots Build WBS ajoutés.
  final int addedWbsCount;

  /// Nombre de postes récurrents Run OPEX ajoutés.
  final int addedRunCount;

  /// Nombre de risques budgétaires EMV ajoutés.
  final int addedRiskCount;

  /// Nombre total d'éléments financiers créés lors de l'opération.
  int get totalAdded => addedWbsCount + addedRunCount + addedRiskCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostSeedResult &&
          other.spec == spec &&
          other.addedWbsCount == addedWbsCount &&
          other.addedRunCount == addedRunCount &&
          other.addedRiskCount == addedRiskCount;

  @override
  int get hashCode =>
      Object.hash(spec, addedWbsCount, addedRunCount, addedRiskCount);
}

/// Bilan déterministe des artefacts projet non encore couverts par le volet FinOps ([CostAutoSeeder.findUncoveredArtifacts]).
@immutable
class CostCoverageGaps {
  /// Construit le bilan immuable des écarts de couverture FinOps.
  CostCoverageGaps({
    List<String> functionalRequirements = const <String>[],
    List<String> nonFunctionalRequirements = const <String>[],
    List<String> businessObjects = const <String>[],
    List<String> uxScreens = const <String>[],
    List<String> qaFeatures = const <String>[],
    List<String> tddSuites = const <String>[],
    List<String> eventStormHotspots = const <String>[],
    this.missingRunBaseline = false,
  }) : functionalRequirements = List<String>.unmodifiable(
         functionalRequirements,
       ),
       nonFunctionalRequirements = List<String>.unmodifiable(
         nonFunctionalRequirements,
       ),
       businessObjects = List<String>.unmodifiable(businessObjects),
       uxScreens = List<String>.unmodifiable(uxScreens),
       qaFeatures = List<String>.unmodifiable(qaFeatures),
       tddSuites = List<String>.unmodifiable(tddSuites),
       eventStormHotspots = List<String>.unmodifiable(eventStormHotspots);

  /// Exigences fonctionnelles (`EF-xxx` / `EXF-xxx`) non rattachées à un lot WBS.
  final List<String> functionalRequirements;

  /// Exigences non fonctionnelles sécurité/scalabilité/conformité (`ENF-xxx`) non rattachées à un lot WBS.
  final List<String> nonFunctionalRequirements;

  /// Objets métiers non rattachés à un lot WBS.
  final List<String> businessObjects;

  /// Écrans UX (`SCR-xxx`) non rattachés à un lot WBS.
  final List<String> uxScreens;

  /// Features Gherkin (`FEAT-xxx`) non rattachées à un lot WBS.
  final List<String> qaFeatures;

  /// Suites TDD (`TDD-xxx`) non rattachées à un lot WBS.
  final List<String> tddSuites;

  /// Hotspots Event Storming (`HS-xxx`) sans risque budgétaire EMV lié.
  final List<String> eventStormHotspots;

  /// Indique qu'aucun poste récurrent Run OPEX n'a encore été défini.
  final bool missingRunBaseline;

  /// Nombre total d'artefacts projet non couverts (hors socle Run).
  int get totalUncoveredArtifacts =>
      functionalRequirements.length +
      nonFunctionalRequirements.length +
      businessObjects.length +
      uxScreens.length +
      qaFeatures.length +
      tddSuites.length +
      eventStormHotspots.length;

  /// Vrai lorsqu'aucun artefact ni socle Run ne manque.
  bool get isComplete => totalUncoveredArtifacts == 0 && !missingRunBaseline;

  /// Sérialise le bilan d'écarts de couverture pour les outils IA FinOps.
  Map<String, Object?> toJson() => <String, Object?>{
    'totalUncoveredArtifacts': totalUncoveredArtifacts,
    'missingRunBaseline': missingRunBaseline,
    'isComplete': isComplete,
    'functionalRequirements': functionalRequirements,
    'nonFunctionalRequirements': nonFunctionalRequirements,
    'businessObjects': businessObjects,
    'uxScreens': uxScreens,
    'qaFeatures': qaFeatures,
    'tddSuites': tddSuites,
    'eventStormHotspots': eventStormHotspots,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostCoverageGaps &&
          listEquals(other.functionalRequirements, functionalRequirements) &&
          listEquals(
            other.nonFunctionalRequirements,
            nonFunctionalRequirements,
          ) &&
          listEquals(other.businessObjects, businessObjects) &&
          listEquals(other.uxScreens, uxScreens) &&
          listEquals(other.qaFeatures, qaFeatures) &&
          listEquals(other.tddSuites, tddSuites) &&
          listEquals(other.eventStormHotspots, eventStormHotspots) &&
          other.missingRunBaseline == missingRunBaseline;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(functionalRequirements),
    Object.hashAll(nonFunctionalRequirements),
    Object.hashAll(businessObjects),
    Object.hashAll(uxScreens),
    Object.hashAll(qaFeatures),
    Object.hashAll(tddSuites),
    Object.hashAll(eventStormHotspots),
    missingRunBaseline,
  );
}

/// Pré-remplit de manière idempotente et non destructive les lots WBS, le socle Run et les risques Hotspots.
abstract final class CostAutoSeeder {
  static final RegExp _wbsCodeRegex = RegExp(
    r'^WBS-(\d+)$',
    caseSensitive: false,
  );
  static final RegExp _runCodeRegex = RegExp(
    r'^RUN-(\d+)$',
    caseSensitive: false,
  );
  static final RegExp _riskCodeRegex = RegExp(
    r'^RSK-(\d+)$',
    caseSensitive: false,
  );
  static final RegExp _aiKeywordsRegex = RegExp(
    r'\b(ia|ai|llm|gpt|gemini|claude|openai|mistral|rag|embedding|embeddings|agent\s+ia|intelligence\s+artificielle|machine\s+learning)\b',
    caseSensitive: false,
  );

  /// Génère les postes WBS, Run et Risques manquants depuis [project] sans écraser l'existant.
  static CostSeedResult seedFromProject(
    SpecForgeProject project, {
    EnterpriseRateCard? enterpriseRateCard,
  }) {
    var workingSpec = project.costSpec;
    if (workingSpec.wbsItems.isEmpty &&
        enterpriseRateCard != null &&
        !workingSpec.hasCustomAssumptions) {
      workingSpec = workingSpec.applyEnterpriseRateCard(enterpriseRateCard);
    }

    final nextWbsList = List<CostWbsItemSpec>.from(workingSpec.wbsItems);
    final nextRunList = List<CostRunItemSpec>.from(workingSpec.runItems);
    final nextRiskList = List<CostRiskItemSpec>.from(workingSpec.riskItems);

    final usedWbsIds = <String>{for (final w in nextWbsList) w.id};
    final usedWbsCodes = <String>{
      for (final w in nextWbsList) w.code.trim().toUpperCase(),
    };
    var wbsCounter = _maxSequenceNumber(
      nextWbsList.map((w) => w.code),
      _wbsCodeRegex,
    );

    final coveredReqRefs = <String>{
      for (final w in nextWbsList)
        for (final r in w.requirementIds) r.trim().toLowerCase(),
    };
    final coveredObjRefs = <String>{
      for (final w in nextWbsList)
        for (final o in w.businessObjectIds) o.trim().toLowerCase(),
    };
    final coveredScreenRefs = <String>{
      for (final w in nextWbsList)
        for (final s in w.uxScreenIds) s.trim().toLowerCase(),
    };
    final coveredFeatureRefs = <String>{
      for (final w in nextWbsList)
        for (final f in w.qaFeatureIds) f.trim().toLowerCase(),
    };
    final coveredTddRefs = <String>{
      for (final w in nextWbsList)
        for (final t in w.tddSuiteIds) t.trim().toLowerCase(),
    };

    var addedWbs = 0;

    CostWbsItemSpec buildSeededWbs({
      required String idHint,
      required String title,
      required String description,
      required CostDiscipline discipline,
      required RequirementPriority priority,
      required CostTShirtSize size,
      String moduleId = '',
      List<String> requirementIds = const <String>[],
      List<String> businessObjectIds = const <String>[],
      List<String> uxScreenIds = const <String>[],
      List<String> qaFeatureIds = const <String>[],
      List<String> tddSuiteIds = const <String>[],
    }) {
      String code;
      do {
        wbsCounter++;
        code = 'WBS-${wbsCounter.toString().padLeft(3, '0')}';
      } while (!usedWbsCodes.add(code.toUpperCase()));

      final id = _uniqueId('wbs_${_cleanToken(idHint)}', usedWbsIds);
      final profile = workingSpec.resolveProfileForDiscipline(discipline);
      final preset = workingSpec.presetFor(size);
      return CostWbsItemSpec(
        id: id,
        code: code,
        title: title,
        description: description,
        discipline: discipline,
        priority: priority,
        profileId: profile.id,
        tshirtSize: preset.size,
        optimisticDays: preset.optimisticDays,
        mostLikelyDays: preset.mostLikelyDays,
        pessimisticDays: preset.pessimisticDays,
        aiEligible: true,
        moduleId: moduleId,
        requirementIds: requirementIds,
        businessObjectIds: businessObjectIds,
        uxScreenIds: uxScreenIds,
        qaFeatureIds: qaFeatureIds,
        tddSuiteIds: tddSuiteIds,
        origin: 'seed',
      );
    }

    // 1. Exigences fonctionnelles -> lots Backend
    for (final req in project.cahierDesCharges.functionalRequirements) {
      if (_isRequirementCovered(req, coveredReqRefs)) continue;
      final size = _sizeForFunctionalRequirement(req);
      final refCode = req.code.trim().isNotEmpty ? req.code.trim() : req.id;
      final title = req.code.trim().isNotEmpty
          ? '${req.code.trim()} — ${req.title}'
          : req.title;
      nextWbsList.add(
        buildSeededWbs(
          idHint: req.id,
          title: title,
          description: req.description.isNotEmpty
              ? req.description
              : 'Implémentation métier et règles associées à l’exigence $refCode.',
          discipline: CostDiscipline.backend,
          priority: req.priority,
          size: size,
          moduleId: req.moduleId,
          requirementIds: <String>[refCode],
        ),
      );
      coveredReqRefs.add(req.id.toLowerCase());
      if (req.code.trim().isNotEmpty) {
        coveredReqRefs.add(req.code.trim().toLowerCase());
      }
      addedWbs++;
    }

    // 2. Objets métiers -> lots Data & Modélisation
    for (final obj in project.businessObjects) {
      if (_isBusinessObjectCovered(obj, coveredObjRefs)) continue;
      final size = _sizeForBusinessObject(obj);
      nextWbsList.add(
        buildSeededWbs(
          idHint: obj.id,
          title: 'Modèle & persistance — ${obj.name}',
          description: obj.description.isNotEmpty
              ? obj.description
              : 'Schéma de données, contraintes et persistance de l’entité ${obj.technicalName}.',
          discipline: CostDiscipline.dataModel,
          priority: RequirementPriority.must,
          size: size,
          businessObjectIds: <String>[obj.id],
        ),
      );
      coveredObjRefs
        ..add(obj.id.toLowerCase())
        ..add(obj.technicalName.toLowerCase())
        ..add(obj.name.toLowerCase());
      addedWbs++;
    }

    // 3. Écrans UX -> lots Frontend & UX/UI
    for (final screen in project.uxSpec.screens) {
      if (_isScreenCovered(screen, coveredScreenRefs)) continue;
      final size = _sizeForUxScreen(screen);
      final refCode = screen.code.trim().isNotEmpty
          ? screen.code.trim()
          : screen.id;
      final routeModuleId = screen.routeId.trim().isEmpty
          ? ''
          : (project.uxSpec.navigation.findRoute(screen.routeId)?.moduleId ??
                '');
      final priority = _priorityFromLinkedRequirements(
        project,
        screen.requirementIds,
        fallback: RequirementPriority.must,
      );
      final title = screen.code.trim().isNotEmpty
          ? 'Écran ${screen.code.trim()} — ${screen.name}'
          : 'Écran — ${screen.name}';
      nextWbsList.add(
        buildSeededWbs(
          idHint: screen.id,
          title: title,
          description: screen.purpose.isNotEmpty
              ? screen.purpose
              : 'Réalisation de l’interface ${screen.pattern.label} et de ses états UX.',
          discipline: CostDiscipline.frontendUx,
          priority: priority,
          size: size,
          moduleId: routeModuleId,
          uxScreenIds: <String>[refCode],
        ),
      );
      coveredScreenRefs.add(screen.id.toLowerCase());
      if (screen.code.trim().isNotEmpty) {
        coveredScreenRefs.add(screen.code.trim().toLowerCase());
      }
      addedWbs++;
    }

    // 4a. Features Gherkin -> lots QA, BDD & Tests
    for (final feature in project.qaSpec.features) {
      if (_isFeatureCovered(feature, coveredFeatureRefs)) continue;
      final size = _sizeForQaFeature(feature);
      final refCode = feature.code.trim().isNotEmpty
          ? feature.code.trim()
          : feature.id;
      final scenarioReqIds = <String>[
        for (final sc in feature.scenarios) ...sc.requirementIds,
      ];
      final priority = _priorityFromLinkedRequirements(
        project,
        scenarioReqIds,
        fallback: RequirementPriority.must,
      );
      final title = feature.code.trim().isNotEmpty
          ? 'Tests BDD ${feature.code.trim()} — ${feature.title}'
          : 'Tests BDD — ${feature.title}';
      nextWbsList.add(
        buildSeededWbs(
          idHint: feature.id,
          title: title,
          description:
              'Automatisation de ${feature.scenarios.length} scénario(s) Gherkin BDD.',
          discipline: CostDiscipline.qaTesting,
          priority: priority,
          size: size,
          moduleId: feature.moduleId,
          qaFeatureIds: <String>[refCode],
        ),
      );
      coveredFeatureRefs.add(feature.id.toLowerCase());
      if (feature.code.trim().isNotEmpty) {
        coveredFeatureRefs.add(feature.code.trim().toLowerCase());
      }
      addedWbs++;
    }

    // 4b. Suites TDD -> lots QA, BDD & Tests
    for (final suite in project.qaSpec.tddSuites) {
      if (_isTddSuiteCovered(suite, coveredTddRefs)) continue;
      final size = _sizeForTddSuite(suite);
      final refCode = suite.code.trim().isNotEmpty
          ? suite.code.trim()
          : suite.id;
      final caseReqIds = <String>[
        for (final tc in suite.cases) ...tc.requirementIds,
      ];
      final priority = _priorityFromLinkedRequirements(
        project,
        caseReqIds,
        fallback: RequirementPriority.must,
      );
      final title = suite.code.trim().isNotEmpty
          ? 'Suite TDD ${suite.code.trim()} — ${suite.name}'
          : 'Suite TDD — ${suite.name}';
      nextWbsList.add(
        buildSeededWbs(
          idHint: suite.id,
          title: title,
          description: suite.description.isNotEmpty
              ? suite.description
              : 'Implémentation de ${suite.cases.length} cas unitaire(s) TDD (${suite.layer.label}).',
          discipline: CostDiscipline.qaTesting,
          priority: priority,
          size: size,
          moduleId: suite.moduleId,
          tddSuiteIds: <String>[refCode],
        ),
      );
      coveredTddRefs.add(suite.id.toLowerCase());
      if (suite.code.trim().isNotEmpty) {
        coveredTddRefs.add(suite.code.trim().toLowerCase());
      }
      addedWbs++;
    }

    // 5. Exigences non fonctionnelles sécurité / scalabilité / conformité -> lots DevSecOps
    for (final enf in project.cahierDesCharges.nonFunctionalRequirements) {
      if (enf.category != NonFunctionalCategory.security &&
          enf.category != NonFunctionalCategory.scalability &&
          enf.category != NonFunctionalCategory.compliance) {
        continue;
      }
      if (_isNonFunctionalCovered(enf, coveredReqRefs)) continue;
      final refCode = enf.code.trim().isNotEmpty ? enf.code.trim() : enf.id;
      final size =
          (enf.targetMetric.trim().isNotEmpty &&
              enf.description.trim().length > 80)
          ? CostTShirtSize.m
          : CostTShirtSize.s;
      final title = enf.code.trim().isNotEmpty
          ? '${enf.code.trim()} (${enf.category.label}) — ${enf.title}'
          : '${enf.category.label} — ${enf.title}';
      nextWbsList.add(
        buildSeededWbs(
          idHint: enf.id,
          title: title,
          description: [
            if (enf.description.isNotEmpty) enf.description,
            if (enf.targetMetric.isNotEmpty) 'Cible : ${enf.targetMetric}',
          ].join(' — '),
          discipline: CostDiscipline.devSecOps,
          priority: RequirementPriority.must,
          size: size,
          requirementIds: <String>[refCode],
        ),
      );
      coveredReqRefs.add(enf.id.toLowerCase());
      if (enf.code.trim().isNotEmpty) {
        coveredReqRefs.add(enf.code.trim().toLowerCase());
      }
      addedWbs++;
    }

    // 6. Socle Run OPEX par défaut (uniquement lorsque runItems est vide)
    var addedRun = 0;
    if (nextRunList.isEmpty) {
      final usedRunIds = <String>{};
      final usedRunCodes = <String>{};
      var runCounter = _maxSequenceNumber(
        nextRunList.map((r) => r.code),
        _runCodeRegex,
      );

      CostRunItemSpec buildSeededRun({
        required String idHint,
        required String name,
        required String description,
        required CostRunCategory category,
        required CostEnvironmentScope environment,
        required double unitCost,
        double annualGrowthPct = 5.0,
      }) {
        String code;
        do {
          runCounter++;
          code = 'RUN-${runCounter.toString().padLeft(3, '0')}';
        } while (!usedRunCodes.add(code.toUpperCase()));
        final id = _uniqueId('run_${_cleanToken(idHint)}', usedRunIds);
        return CostRunItemSpec(
          id: id,
          code: code,
          name: name,
          description: description,
          category: category,
          environment: environment,
          billingCycle: CostBillingCycle.monthly,
          unitCost: unitCost,
          quantity: 1.0,
          annualGrowthPct: annualGrowthPct,
          enabled: true,
        );
      }

      final highVolume = workingSpec.targetUsersCount >= 1000;
      nextRunList
        ..add(
          buildSeededRun(
            idHint: 'cloud_prod',
            name: 'Infrastructure Cloud Production',
            description:
                'Compute applicatif, load-balancing, réseau et observabilité de production (${workingSpec.targetUsersCount} utilisateurs cibles).',
            category: CostRunCategory.cloudInfra,
            environment: CostEnvironmentScope.prod,
            unitCost: highVolume ? 450.0 : 180.0,
            annualGrowthPct: 10.0,
          ),
        )
        ..add(
          buildSeededRun(
            idHint: 'cloud_staging_dev',
            name: 'Environnements Staging & Développement',
            description:
                'Environnements hors-production mutualisés (intégration continue, recette UAT).',
            category: CostRunCategory.cloudInfra,
            environment: CostEnvironmentScope.staging,
            unitCost: 90.0,
            annualGrowthPct: 5.0,
          ),
        )
        ..add(
          buildSeededRun(
            idHint: 'managed_db_backups',
            name: 'Base de données managée & Sauvegardes',
            description:
                'Instance BDD managée haute disponibilité, stockage et sauvegardes automatisées PITR.',
            category: CostRunCategory.databaseStorage,
            environment: CostEnvironmentScope.prod,
            unitCost: highVolume ? 280.0 : 120.0,
            annualGrowthPct: 10.0,
          ),
        )
        ..add(
          buildSeededRun(
            idHint: 'tma_support',
            name: 'Forfait MCO / TMA & Support mensuel',
            description:
                'Maintien en condition opérationnelle, correctifs de sécurité et support applicatif.',
            category: CostRunCategory.supportTma,
            environment: CostEnvironmentScope.global,
            unitCost: 1200.0,
            annualGrowthPct: 3.0,
          ),
        );
      addedRun = 4;

      if (highVolume || _projectMentionsAiLlm(project)) {
        nextRunList.add(
          buildSeededRun(
            idHint: 'ai_llm_tokens',
            name: 'Consommation API IA / Tokens LLM',
            description:
                'Forfait mensuel d’inférence LLM, embeddings et passerelle IA.',
            category: CostRunCategory.aiTokensLlm,
            environment: CostEnvironmentScope.prod,
            unitCost: highVolume ? 350.0 : 150.0,
            annualGrowthPct: 15.0,
          ),
        );
        addedRun++;
      }
    }

    // 7. Hotspots Event Storming -> Risques budgétaires EMV
    final usedRiskIds = <String>{for (final r in nextRiskList) r.id};
    final usedRiskCodes = <String>{
      for (final r in nextRiskList) r.code.trim().toUpperCase(),
    };
    final coveredHotspots = <String>{
      for (final r in nextRiskList)
        if (r.linkedHotspotId.trim().isNotEmpty)
          r.linkedHotspotId.trim().toLowerCase(),
    };
    var riskCounter = _maxSequenceNumber(
      nextRiskList.map((r) => r.code),
      _riskCodeRegex,
    );
    var addedRisk = 0;

    final defaultRiskProfileId = workingSpec
        .resolveProfileForDiscipline(CostDiscipline.backend)
        .id;

    for (final entry in project.eventStorming.allHotspots) {
      final doc = entry.document;
      final hs = entry.hotspot;
      final idLower = hs.id.trim().toLowerCase();
      final qualifiedLower = '${doc.id}:${hs.id}'.toLowerCase();
      if (coveredHotspots.contains(idLower) ||
          coveredHotspots.contains(qualifiedLower)) {
        continue;
      }

      String code;
      do {
        riskCounter++;
        code = 'RSK-${riskCounter.toString().padLeft(3, '0')}';
      } while (!usedRiskCodes.add(code.toUpperCase()));

      final (probPct, impactDays) = switch (hs.severity) {
        EventStormHotspotSeverity.blocker => (70.0, 10.0),
        EventStormHotspotSeverity.high => (55.0, 7.0),
        EventStormHotspotSeverity.medium => (40.0, 5.0),
        EventStormHotspotSeverity.low => (20.0, 2.0),
      };

      final step = doc.findStep(entry.stepNumber);
      final reqRefs = <String>[
        if (step?.backlog?.story.isNotEmpty == true) step!.backlog!.story,
      ];

      final id = _uniqueId('rsk_${_cleanToken('${doc.id}_${hs.id}')}', usedRiskIds);
      nextRiskList.add(
        CostRiskItemSpec(
          id: id,
          code: code,
          title: hs.question,
          description:
              'Hotspot ${hs.id} (${hs.severity.label}, statut: ${hs.status.label}'
              '${hs.owner.isEmpty ? '' : ', owner: ${hs.owner}'}) '
              'issu du Bounded Context « ${doc.meta.boundedContext} » (étape ${entry.stepNumber}).',
          probabilityPct: probPct,
          impactDays: impactDays,
          fixedCostImpact: 0.0,
          profileId: defaultRiskProfileId,
          mitigation: hs.isResolved
              ? 'Hotspot résolu (${hs.owner.isEmpty ? 'atelier' : hs.owner}).'
              : 'Atelier de cadrage ciblé${hs.owner.isEmpty ? '' : ' avec ${hs.owner}'}.',
          linkedHotspotId: hs.id,
          linkedRequirementIds: reqRefs,
        ),
      );
      coveredHotspots.add(idLower);
      coveredHotspots.add(qualifiedLower);
      addedRisk++;
    }

    final seededSpec = workingSpec.copyWith(
      wbsItems: nextWbsList,
      runItems: nextRunList,
      riskItems: nextRiskList,
    );
    return CostSeedResult(
      spec: seededSpec,
      addedWbsCount: addedWbs,
      addedRunCount: addedRun,
      addedRiskCount: addedRisk,
    );
  }

  /// Recense de façon déterministe tous les artefacts de [project] non encore couverts dans [SpecForgeProject.costSpec].
  static CostCoverageGaps findUncoveredArtifacts(SpecForgeProject project) {
    final cost = project.costSpec;
    final coveredReqRefs = <String>{
      for (final w in cost.wbsItems)
        for (final r in w.requirementIds) r.trim().toLowerCase(),
    };
    final coveredObjRefs = <String>{
      for (final w in cost.wbsItems)
        for (final o in w.businessObjectIds) o.trim().toLowerCase(),
    };
    final coveredScreenRefs = <String>{
      for (final w in cost.wbsItems)
        for (final s in w.uxScreenIds) s.trim().toLowerCase(),
    };
    final coveredFeatureRefs = <String>{
      for (final w in cost.wbsItems)
        for (final f in w.qaFeatureIds) f.trim().toLowerCase(),
    };
    final coveredTddRefs = <String>{
      for (final w in cost.wbsItems)
        for (final t in w.tddSuiteIds) t.trim().toLowerCase(),
    };
    final coveredHotspots = <String>{
      for (final r in cost.riskItems)
        if (r.linkedHotspotId.trim().isNotEmpty)
          r.linkedHotspotId.trim().toLowerCase(),
    };

    final uncoveredReqs = <String>[
      for (final req in project.cahierDesCharges.functionalRequirements)
        if (!_isRequirementCovered(req, coveredReqRefs))
          req.code.trim().isNotEmpty
              ? '${req.code.trim()} (${req.priority.code}) — ${req.title}'
              : '${req.id} (${req.priority.code}) — ${req.title}',
    ];

    final uncoveredEnfs = <String>[
      for (final enf in project.cahierDesCharges.nonFunctionalRequirements)
        if ((enf.category == NonFunctionalCategory.security ||
                enf.category == NonFunctionalCategory.scalability ||
                enf.category == NonFunctionalCategory.compliance) &&
            !_isNonFunctionalCovered(enf, coveredReqRefs))
          enf.code.trim().isNotEmpty
              ? '${enf.code.trim()} (${enf.category.label}) — ${enf.title}'
              : '${enf.id} (${enf.category.label}) — ${enf.title}',
    ];

    final uncoveredObjs = <String>[
      for (final obj in project.businessObjects)
        if (!_isBusinessObjectCovered(obj, coveredObjRefs))
          '${obj.technicalName} (${obj.name})',
    ];

    final uncoveredScreens = <String>[
      for (final screen in project.uxSpec.screens)
        if (!_isScreenCovered(screen, coveredScreenRefs))
          screen.code.trim().isNotEmpty
              ? '${screen.code.trim()} — ${screen.name}'
              : '${screen.id} — ${screen.name}',
    ];

    final uncoveredFeatures = <String>[
      for (final feature in project.qaSpec.features)
        if (!_isFeatureCovered(feature, coveredFeatureRefs))
          feature.code.trim().isNotEmpty
              ? '${feature.code.trim()} — ${feature.title}'
              : '${feature.id} — ${feature.title}',
    ];

    final uncoveredSuites = <String>[
      for (final suite in project.qaSpec.tddSuites)
        if (!_isTddSuiteCovered(suite, coveredTddRefs))
          suite.code.trim().isNotEmpty
              ? '${suite.code.trim()} — ${suite.name}'
              : '${suite.id} — ${suite.name}',
    ];

    final uncoveredHotspots = <String>[
      for (final entry in project.eventStorming.allHotspots)
        if (!coveredHotspots.contains(entry.hotspot.id.trim().toLowerCase()) &&
            !coveredHotspots.contains(
              '${entry.document.id}:${entry.hotspot.id}'.toLowerCase(),
            ))
          '${entry.hotspot.id} (${entry.hotspot.severity.label}) — ${entry.hotspot.question}',
    ];

    return CostCoverageGaps(
      functionalRequirements: uncoveredReqs,
      nonFunctionalRequirements: uncoveredEnfs,
      businessObjects: uncoveredObjs,
      uxScreens: uncoveredScreens,
      qaFeatures: uncoveredFeatures,
      tddSuites: uncoveredSuites,
      eventStormHotspots: uncoveredHotspots,
      missingRunBaseline: cost.runItems.isEmpty,
    );
  }

  static bool _isRequirementCovered(
    FunctionalRequirement req,
    Set<String> covered,
  ) =>
      covered.contains(req.id.trim().toLowerCase()) ||
      (req.code.trim().isNotEmpty &&
          covered.contains(req.code.trim().toLowerCase()));

  static bool _isNonFunctionalCovered(
    NonFunctionalRequirement enf,
    Set<String> covered,
  ) =>
      covered.contains(enf.id.trim().toLowerCase()) ||
      (enf.code.trim().isNotEmpty &&
          covered.contains(enf.code.trim().toLowerCase()));

  static bool _isBusinessObjectCovered(
    BusinessObjectSpec obj,
    Set<String> covered,
  ) =>
      covered.contains(obj.id.trim().toLowerCase()) ||
      covered.contains(obj.technicalName.trim().toLowerCase()) ||
      covered.contains(obj.name.trim().toLowerCase());

  static bool _isScreenCovered(UxScreenSpec screen, Set<String> covered) =>
      covered.contains(screen.id.trim().toLowerCase()) ||
      (screen.code.trim().isNotEmpty &&
          covered.contains(screen.code.trim().toLowerCase()));

  static bool _isFeatureCovered(
    GherkinFeatureSpec feature,
    Set<String> covered,
  ) =>
      covered.contains(feature.id.trim().toLowerCase()) ||
      (feature.code.trim().isNotEmpty &&
          covered.contains(feature.code.trim().toLowerCase()));

  static bool _isTddSuiteCovered(
    TddTestSuiteSpec suite,
    Set<String> covered,
  ) =>
      covered.contains(suite.id.trim().toLowerCase()) ||
      (suite.code.trim().isNotEmpty &&
          covered.contains(suite.code.trim().toLowerCase()));

  static CostTShirtSize _sizeForFunctionalRequirement(
    FunctionalRequirement req,
  ) {
    final score = req.acceptanceCriteria.length + req.actorIds.length;
    if (score <= 2) return CostTShirtSize.s;
    if (score <= 5) return CostTShirtSize.m;
    return CostTShirtSize.l;
  }

  static CostTShirtSize _sizeForBusinessObject(BusinessObjectSpec obj) {
    final score =
        obj.totalAttributeCount +
        obj.relations.length * 2 +
        obj.lifecycleStates.length +
        obj.lifecycleTransitions.length;
    if (score <= 4) return CostTShirtSize.xs;
    if (score <= 10) return CostTShirtSize.s;
    if (score <= 22) return CostTShirtSize.m;
    return CostTShirtSize.l;
  }

  static CostTShirtSize _sizeForUxScreen(UxScreenSpec screen) {
    final widgetCount =
        screen.zones.fold<int>(0, (sum, z) => sum + z.slots.length) +
        screen.actions.length;
    return switch (screen.pattern) {
      UxScreenPattern.dashboard ||
      UxScreenPattern.kanban ||
      UxScreenPattern.wizard =>
        widgetCount >= 5 ? CostTShirtSize.l : CostTShirtSize.m,
      UxScreenPattern.form ||
      UxScreenPattern.masterDetail ||
      UxScreenPattern.tableExplorer ||
      UxScreenPattern.documentA4 ||
      UxScreenPattern.custom =>
        widgetCount >= 4 ? CostTShirtSize.m : CostTShirtSize.s,
    };
  }

  static CostTShirtSize _sizeForQaFeature(GherkinFeatureSpec feature) {
    final count = feature.scenarios.length;
    if (count <= 2) return CostTShirtSize.xs;
    if (count <= 5) return CostTShirtSize.s;
    if (count <= 10) return CostTShirtSize.m;
    return CostTShirtSize.l;
  }

  static CostTShirtSize _sizeForTddSuite(TddTestSuiteSpec suite) {
    final count = suite.cases.length;
    if (count <= 3) return CostTShirtSize.xs;
    if (count <= 7) return CostTShirtSize.s;
    if (count <= 14) return CostTShirtSize.m;
    return CostTShirtSize.l;
  }

  static RequirementPriority _priorityFromLinkedRequirements(
    SpecForgeProject project,
    List<String> refs, {
    required RequirementPriority fallback,
  }) {
    RequirementPriority? best;
    for (final rawRef in refs) {
      final needle = rawRef.trim().toLowerCase();
      if (needle.isEmpty) continue;
      for (final req in project.cahierDesCharges.functionalRequirements) {
        if (req.id.toLowerCase() == needle ||
            (req.code.trim().isNotEmpty &&
                req.code.trim().toLowerCase() == needle)) {
          if (best == null || req.priority.index < best.index) {
            best = req.priority;
          }
        }
      }
    }
    return best ?? fallback;
  }

  static bool _projectMentionsAiLlm(SpecForgeProject project) {
    final probes = <String>[
      project.name,
      project.initialIdea,
      project.vision.ideaSummary,
      project.vision.problemStatement,
      project.vision.valueProposition,
      for (final req in project.cahierDesCharges.functionalRequirements) ...[
        req.title,
        req.description,
      ],
    ];
    return probes.any(_aiKeywordsRegex.hasMatch);
  }

  static int _maxSequenceNumber(Iterable<String> codes, RegExp pattern) {
    var maxNum = 0;
    for (final code in codes) {
      final match = pattern.firstMatch(code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1) ?? '');
        if (parsed != null && parsed > maxNum) {
          maxNum = parsed;
        }
      }
    }
    return maxNum;
  }

  static String _cleanToken(String raw) {
    final cleaned = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'item' : cleaned;
  }

  static String _uniqueId(String baseId, Set<String> usedIds) {
    if (usedIds.add(baseId)) return baseId;
    var suffix = 2;
    while (!usedIds.add('${baseId}_$suffix')) {
      suffix++;
    }
    return '${baseId}_$suffix';
  }
}
