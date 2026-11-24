/// Analyseur déterministe de cohérence financière, de validité des profils TJM et de couverture WBS/Run/Risques ([CostCoherenceAnalyzer]).
library;

import '../models/cost/cost_coherence_issue.dart';
import '../models/cost/cost_forge_stage.dart';
import '../models/cost/cost_run_item_spec.dart';
import '../models/event_storming_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/ux/ux_screen_spec.dart';

/// Vérifie de façon statique et déterministe la cohérence financière et la couverture 360° du volet Coûts d'un [SpecForgeProject].
abstract final class CostCoherenceAnalyzer {
  /// Exécute l'ensemble des contrôles FinOps sur [project] et retourne la liste immuable des anomalies triées.
  static List<CostCoherenceIssue> analyze(SpecForgeProject project) {
    final issues = <CostCoherenceIssue>[];
    final usedIssueIds = <String>{};

    void addIssue({
      required String id,
      required CoherenceSeverity severity,
      required CostForgeStage stage,
      required String code,
      required String title,
      required String description,
      String targetRef = '',
      String suggestion = '',
    }) {
      var candidateId = _sanitizeId(id);
      if (!usedIssueIds.add(candidateId)) {
        var suffix = 2;
        while (!usedIssueIds.add('${candidateId}_$suffix')) {
          suffix++;
        }
        candidateId = '${candidateId}_$suffix';
      }
      issues.add(
        CostCoherenceIssue(
          id: candidateId,
          severity: severity,
          stage: stage,
          code: code,
          title: title,
          description: description,
          targetRef: targetRef,
          suggestion: suggestion,
        ),
      );
    }

    final cost = project.costSpec;
    final functionalReqs = project.cahierDesCharges.functionalRequirements;

    // 1. COST-EF-UNCOVERED : Exigences fonctionnelles Must / Should non chiffrées dans le WBS
    if (functionalReqs.isNotEmpty &&
        (cost.hasContent || cost.wbsItems.isNotEmpty)) {
      for (final req in functionalReqs) {
        if (req.priority != RequirementPriority.must &&
            req.priority != RequirementPriority.should) {
          continue;
        }
        final covered = cost.wbsItems.any(
          (wbs) =>
              wbs.requirementIds.any((ref) => _matchesRequirement(req, ref)),
        );
        if (!covered) {
          final reqRef = req.code.trim().isNotEmpty ? req.code.trim() : req.id;
          addIssue(
            id: 'cost_ef_uncovered_${req.id}',
            severity: CoherenceSeverity.warning,
            stage: CostForgeStage.buildWbs,
            code: 'COST-EF-UNCOVERED',
            title:
                'Exigence ${req.priority.code} non chiffrée dans le WBS : $reqRef',
            description:
                'L’exigence fonctionnelle « ${req.title} » ($reqRef, priorité ${req.priority.code}) n’est rattachée à aucun lot Build WBS.',
            targetRef: reqRef,
            suggestion:
                'Associez $reqRef à un lot WBS existant ou lancez le pré-remplissage depuis le projet.',
          );
        }
      }
    }

    // 2. COST-UX-UNCOVERED : Écrans UX non chiffrés dans le WBS
    if (project.uxSpec.screens.isNotEmpty && cost.wbsItems.isNotEmpty) {
      for (final screen in project.uxSpec.screens) {
        final covered = cost.wbsItems.any(
          (wbs) => wbs.uxScreenIds.any((ref) => _matchesScreen(screen, ref)),
        );
        if (!covered) {
          final screenRef = screen.code.trim().isNotEmpty
              ? screen.code.trim()
              : screen.id;
          addIssue(
            id: 'cost_ux_uncovered_${screen.id}',
            severity: CoherenceSeverity.warning,
            stage: CostForgeStage.buildWbs,
            code: 'COST-UX-UNCOVERED',
            title: 'Écran UX non chiffré dans le WBS : $screenRef',
            description:
                'L’écran UX « ${screen.name} » ($screenRef) n’est couvert par aucun poste WBS (CostWbsItemSpec.uxScreenIds).',
            targetRef: screenRef,
            suggestion:
                'Créez un lot Frontend/UX dédié ou rattachez $screenRef à un poste WBS existant.',
          );
        }
      }
    }

    // 3. COST-PROFILE-MISSING & COST-ZERO-RATE sur les lots WBS et les risques EMV
    for (final wbs in cost.wbsItems) {
      final wbsRef = wbs.code.trim().isNotEmpty ? wbs.code.trim() : wbs.id;
      final profile = cost.findProfile(wbs.profileId);
      if (profile == null) {
        addIssue(
          id: 'cost_wbs_profile_missing_${wbs.id}',
          severity: CoherenceSeverity.error,
          stage: CostForgeStage.buildWbs,
          code: 'COST-PROFILE-MISSING',
          title: 'Profil TJM introuvable sur le lot $wbsRef',
          description:
              'Le lot WBS « ${wbs.title} » ($wbsRef) référence le profil inconnu « ${wbs.profileId} ».',
          targetRef: wbsRef,
          suggestion:
              'Sélectionnez un profil valide de la grille TJM ou réalignez la grille d’entreprise.',
        );
      } else {
        final rate = profile.effectiveDailyRate(cost.deliveryMode);
        if (rate <= 0.0) {
          addIssue(
            id: 'cost_wbs_zero_rate_${wbs.id}',
            severity: CoherenceSeverity.error,
            stage: CostForgeStage.rateCardAssumptions,
            code: 'COST-ZERO-RATE',
            title: 'TJM effectif nul sur le lot $wbsRef (${profile.name})',
            description:
                'Le profil « ${profile.name} » associé au lot « ${wbs.title} » ($wbsRef) a un TJM effectif de 0 en mode ${cost.deliveryMode.label}.',
            targetRef: wbsRef,
            suggestion:
                'Renseignez un TJM strictement positif pour « ${profile.name} » à l’étape 1.',
          );
        }
      }
    }

    for (final risk in cost.riskItems) {
      final riskRef = risk.code.trim().isNotEmpty ? risk.code.trim() : risk.id;
      final profile = cost.findProfile(risk.profileId);
      if (profile == null) {
        addIssue(
          id: 'cost_risk_profile_missing_${risk.id}',
          severity: CoherenceSeverity.error,
          stage: CostForgeStage.tcoReviewExport,
          code: 'COST-PROFILE-MISSING',
          title: 'Profil TJM introuvable sur le risque $riskRef',
          description:
              'Le risque « ${risk.title} » ($riskRef) référence le profil inconnu « ${risk.profileId} ».',
          targetRef: riskRef,
          suggestion:
              'Associez un profil valide de la grille TJM pour valoriser l’EMV de $riskRef.',
        );
      } else {
        final rate = profile.effectiveDailyRate(cost.deliveryMode);
        if (rate <= 0.0) {
          addIssue(
            id: 'cost_risk_zero_rate_${risk.id}',
            severity: CoherenceSeverity.error,
            stage: CostForgeStage.tcoReviewExport,
            code: 'COST-ZERO-RATE',
            title: 'TJM effectif nul sur le risque $riskRef (${profile.name})',
            description:
                'Le profil « ${profile.name} » utilisé par le risque « ${risk.title} » ($riskRef) a un TJM effectif nul en mode ${cost.deliveryMode.label}.',
            targetRef: riskRef,
            suggestion:
                'Renseignez un TJM strictement positif sur le profil « ${profile.name} ».',
          );
        }
      }
    }

    // 4. COST-RUN-MISSING : Absence d'hébergement Prod/Global ou de forfait MCO/TMA actif
    if (cost.wbsItems.isNotEmpty) {
      final hasProdOrGlobal = cost.runItems.any(
        (r) =>
            r.enabled &&
            (r.environment == CostEnvironmentScope.prod ||
                r.environment == CostEnvironmentScope.global),
      );
      if (!hasProdOrGlobal) {
        addIssue(
          id: 'cost_run_missing_prod_env',
          severity: CoherenceSeverity.warning,
          stage: CostForgeStage.runOpex,
          code: 'COST-RUN-MISSING',
          title: 'Aucun poste Run OPEX actif en Production ou Global',
          description:
              'Le projet comporte ${cost.wbsItems.length} lot(s) Build WBS mais aucun poste récurrent actif ne couvre la production ou un périmètre global.',
          targetRef: 'RUN',
          suggestion:
              'Ajoutez les coûts d’infrastructure Cloud de production et de base de données à l’étape Run & Cloud.',
        );
      }

      final hasSupportTma = cost.runItems.any(
        (r) => r.enabled && r.category == CostRunCategory.supportTma,
      );
      if (!hasSupportTma) {
        addIssue(
          id: 'cost_run_missing_support_tma',
          severity: CoherenceSeverity.warning,
          stage: CostForgeStage.runOpex,
          code: 'COST-RUN-MISSING',
          title: 'Aucun poste MCO / TMA actif dans le budget Run',
          description:
              'Aucun forfait actif de maintenance corrective/évolutive (`supportTma`) n’est provisionné dans les coûts récurrents OPEX.',
          targetRef: 'RUN',
          suggestion:
              'Ajoutez un poste mensuel ou annuel de MCO / TMA pour garantir la pérennité du TCO pluriannuel.',
        );
      }
    }

    // 5. COST-HOTSPOT-UNCOVERED : Hotspots Event Storming non provisionnés dans le registre des risques
    if (cost.wbsItems.isNotEmpty) {
      for (final flow in project.eventStorming.flows) {
        for (final node in flow.nodes) {
          if (node.kind != EventStormNodeKind.hotspot) continue;
          final covered = cost.riskItems.any(
            (r) => _matchesHotspot(node, r.linkedHotspotId),
          );
          if (!covered) {
            final hotspotRef = node.code.trim().isNotEmpty
                ? node.code.trim()
                : node.id;
            addIssue(
              id: 'cost_hotspot_uncovered_${node.id}',
              severity: CoherenceSeverity.warning,
              stage: CostForgeStage.tcoReviewExport,
              code: 'COST-HOTSPOT-UNCOVERED',
              title:
                  'Hotspot Event Storming sans provision de risque : « ${node.title} »',
              description:
                  'Le Hotspot « ${node.title} » ($hotspotRef, flux ${flow.code}) n’est relié à aucun risque budgétaire EMV (`linkedHotspotId`).',
              targetRef: hotspotRef,
              suggestion:
                  'Créez une entrée dans le registre des risques rattachée au Hotspot $hotspotRef afin d’en chiffrer l’EMV.',
            );
          }
        }
      }
    }

    issues.sort((a, b) {
      final bySeverity = a.severity.index.compareTo(b.severity.index);
      if (bySeverity != 0) return bySeverity;
      final byStage = a.stage.index.compareTo(b.stage.index);
      if (byStage != 0) return byStage;
      final byCode = a.code.compareTo(b.code);
      if (byCode != 0) return byCode;
      return a.id.compareTo(b.id);
    });
    return List<CostCoherenceIssue>.unmodifiable(issues);
  }

  static bool _matchesRequirement(FunctionalRequirement req, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return req.id.toLowerCase() == needle ||
        (req.code.trim().isNotEmpty && req.code.trim().toLowerCase() == needle);
  }

  static bool _matchesScreen(UxScreenSpec screen, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return screen.id.toLowerCase() == needle ||
        (screen.code.trim().isNotEmpty &&
            screen.code.trim().toLowerCase() == needle) ||
        (screen.routeId.trim().isNotEmpty &&
            screen.routeId.trim().toLowerCase() == needle) ||
        screen.name.toLowerCase() == needle;
  }

  static bool _matchesHotspot(EventStormNode hotspot, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return hotspot.id.toLowerCase() == needle ||
        (hotspot.code.trim().isNotEmpty &&
            hotspot.code.trim().toLowerCase() == needle);
  }

  static String _sanitizeId(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'cost_coh_issue' : cleaned;
  }
}
