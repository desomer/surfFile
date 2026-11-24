/// Exportateur du dossier exécutif FinOps, chiffrage WBS, OPEX Run, risques EMV et TCO au format Markdown ([CostMarkdownExporter]).
library;

import '../../models/cost/cost_coherence_issue.dart';
import '../../models/spec_coherence_issue.dart';
import '../../models/spec_forge_project.dart';
import '../cost_calculator.dart';
import '../cost_coherence_analyzer.dart';
import '../spec_storage_slug.dart';

/// Génère un rapport exécutif Markdown complet en français couvrant la synthèse TCO 1/3/5 ans,
/// la grille TJM, le détail WBS Build, le Run OPEX, les risques EMV et les diagnostics FinOps.
abstract final class CostMarkdownExporter {
  /// Exporte l'intégralité du volet Coûts & TCO de [project] au format Markdown structuré.
  static String export(SpecForgeProject project) {
    final cost = project.costSpec;
    final summary = CostCalculator.compute(cost);

    final buf = StringBuffer()
      ..writeln('# Dossier FinOps, Chiffrage WBS & TCO — ${project.name}')
      ..writeln()
      ..writeln('> Généré par **SuperSpecForge**')
      ..writeln(
        '> Dernière mise à jour : `${project.updatedAt.toIso8601String()}`',
      )
      ..writeln();

    _writeExecutiveKpis(buf, project, summary);
    _writeRateCardAndAssumptions(buf, project);
    _writeBuildWbsSection(buf, project, summary);
    _writeRunOpexSection(buf, project, summary);
    _writeRisksSection(buf, project, summary);
    _writeCoherenceSection(buf, project);

    return SpecStorageIo.normalizeLf(buf.toString());
  }

  static void _writeExecutiveKpis(
    StringBuffer buf,
    SpecForgeProject project,
    CostProjectSummary summary,
  ) {
    final cost = project.costSpec;
    final cur = summary.currency;
    final lots = <CostLotSummary>[
      summary.mvpLot,
      summary.v1Lot,
      summary.fullLot,
      if (summary.allLot.itemCount > summary.fullLot.itemCount) summary.allLot,
    ];

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 1. Synthèse Exécutive & Indicateurs Clés (KPI)')
      ..writeln()
      ..writeln(
        '- **Devise de référence** : ${cur.label} (`${cur.code}`)',
      )
      ..writeln(
        '- **Mode contractuel de delivery** : ${cost.deliveryMode.label} (`${cost.deliveryMode.name}`)',
      )
      ..writeln(
        '- **Base journalière** : ${_formatPctOrDec(cost.hoursPerDay)} h / jour · **Volumétrie cible** : ${cost.targetUsersCount} utilisateur(s) actif(s)',
      )
      ..writeln(
        '- **Ingénierie assistée par IA** : ${cost.aiProductivity.enabled ? 'Activée (scénario retenu)' : 'Désactivée (chiffrage classique retenu)'}',
      )
      ..writeln()
      ..writeln(
        '### 1.1 Comparatif Build CAPEX (MVP vs V1 vs Cible — Classique vs Assisté IA)',
      )
      ..writeln()
      ..writeln(
        '| Périmètre MoSCoW | Postes WBS | Charge Classique | Coût Classique | Charge Assistée IA | Coût Assisté IA | Économie IA | Enveloppe Prudente P80 |',
      )
      ..writeln('|---|---|---|---|---|---|---|---|');

    for (final lot in lots) {
      buf.writeln(
        '| **${_esc(lot.scope.label)}** | ${lot.itemCount} | ${CostCalculator.formatDays(lot.classicTotalDays)} | ${CostCalculator.formatAmount(lot.classicTotalCost, cur)} | ${CostCalculator.formatDays(lot.aiTotalDays)} | ${CostCalculator.formatAmount(lot.aiTotalCost, cur)} | ${CostCalculator.formatAmount(lot.aiSavedCost, cur)} _(${CostCalculator.formatDays(lot.aiSavedDays)})_ | ${CostCalculator.formatAmount(lot.effectiveP80Cost, cur)} |',
      );
    }

    buf
      ..writeln()
      ..writeln('### 1.2 Coût Complet de Possession (TCO 1 an / 3 ans / 5 ans)')
      ..writeln()
      ..writeln('| Composante financière | Horizon 1 an | Horizon 3 ans | Horizon 5 ans |')
      ..writeln('|---|---|---|---|')
      ..writeln(
        '| **Build CAPEX retenu (Cible)** | ${CostCalculator.formatAmount(summary.fullLot.effectiveTotalCost, cur)} | ${CostCalculator.formatAmount(summary.fullLot.effectiveTotalCost, cur)} | ${CostCalculator.formatAmount(summary.fullLot.effectiveTotalCost, cur)} |',
      )
      ..writeln(
        '| **Provision Risques (EMV)** | ${CostCalculator.formatAmount(summary.riskEmvCost, cur)} | ${CostCalculator.formatAmount(summary.riskEmvCost, cur)} | ${CostCalculator.formatAmount(summary.riskEmvCost, cur)} |',
      )
      ..writeln(
        '| **Run OPEX cumulé** | ${CostCalculator.formatAmount(summary.yearlyRunYear1, cur)} | ${CostCalculator.formatAmount(summary.cumulativeRun3Years, cur)} | ${CostCalculator.formatAmount(summary.cumulativeRun5Years, cur)} |',
      )
      ..writeln(
        '| **TCO Total consolidé** | **${CostCalculator.formatAmount(summary.tco1Year, cur)}** | **${CostCalculator.formatAmount(summary.tco3Years, cur)}** | **${CostCalculator.formatAmount(summary.tco5Years, cur)}** |',
      )
      ..writeln();

    final nonEmptyDisciplines = summary.fullLot.byDiscipline.values
        .where((b) => b.itemCount > 0)
        .toList();
    if (nonEmptyDisciplines.isNotEmpty) {
      buf
        ..writeln('### 1.3 Ventilation WBS Directe par Pôle (Périmètre Cible)')
        ..writeln()
        ..writeln(
          '| Pôle d’ingénierie | Postes | Charge Classique | Charge IA | Coût Classique | Coût IA | Gain IA |',
        )
        ..writeln('|---|---|---|---|---|---|---|');
      for (final b in nonEmptyDisciplines) {
        buf.writeln(
          '| **${_esc(b.discipline.label)}** | ${b.itemCount} | ${CostCalculator.formatDays(b.classicExpectedDays)} | ${CostCalculator.formatDays(b.aiExpectedDays)} | ${CostCalculator.formatAmount(b.classicCost, cur)} | ${CostCalculator.formatAmount(b.aiCost, cur)} | ${CostCalculator.formatAmount(b.savedCost, cur)} |',
        );
      }
      buf.writeln();
    }
  }

  static void _writeRateCardAndAssumptions(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final cost = project.costSpec;
    final cur = cost.currency;
    final ratios = cost.transverseRatios;
    final ai = cost.aiProductivity;

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 2. Grille TJM & Hypothèses Méthodologiques')
      ..writeln()
      ..writeln('### 2.1 Grille des Profils & TJM')
      ..writeln()
      ..writeln(
        '| Code | Profil | Séniorité | Pôle | TJM Interne | TJM Externe | TJM Effectif (${_esc(cost.deliveryMode.label)}) |',
      )
      ..writeln('|---|---|---|---|---|---|---|');

    for (final profile in cost.profiles) {
      final effective = profile.effectiveDailyRate(cost.deliveryMode);
      buf.writeln(
        '| `${_esc(profile.code)}` | **${_esc(profile.name)}** | ${_esc(profile.seniority)} | ${_esc(profile.discipline.shortLabel)} | ${CostCalculator.formatAmount(profile.internalDailyRate, cur)} | ${CostCalculator.formatAmount(profile.externalDailyRate, cur)} | **${CostCalculator.formatAmount(effective, cur)}** |',
      );
    }

    buf
      ..writeln()
      ..writeln('### 2.2 Barème T-shirt PERT 3 points')
      ..writeln()
      ..writeln(
        '| Taille | Optimiste (`O`) | Nominal (`M`) | Pessimiste (`P`) | Espérance PERT |',
      )
      ..writeln('|---|---|---|---|---|');
    for (final preset in cost.tshirtPresets) {
      buf.writeln(
        '| **${_esc(preset.size.code)}** (${_esc(preset.size.label)}) | ${CostCalculator.formatDays(preset.optimisticDays)} | ${CostCalculator.formatDays(preset.mostLikelyDays)} | ${CostCalculator.formatDays(preset.pessimisticDays)} | **${CostCalculator.formatDays(preset.expectedDays)}** |',
      );
    }

    buf
      ..writeln()
      ..writeln('### 2.3 Ratios d’Activités Transverses & Aléas')
      ..writeln()
      ..writeln(
        '- **Pilotage & Produit** : `${_formatPctOrDec(ratios.projectManagementPct)} %` de la charge WBS',
      )
      ..writeln(
        '- **Architecture & DevSecOps** : `${_formatPctOrDec(ratios.architectureDevOpsPct)} %` de la charge WBS',
      )
      ..writeln(
        '- **Recette & QA transverse** : `${_formatPctOrDec(ratios.transverseQaPct)} %` de la charge WBS',
      )
      ..writeln(
        '- **Provision pour aléas d’intégration** : `${_formatPctOrDec(ratios.contingencyPct)} %` sur `(WBS + Transverses)`',
      )
      ..writeln()
      ..writeln('### 2.4 Accélération Ingénierie Assistée par IA')
      ..writeln()
      ..writeln(
        '- **Statut** : ${ai.enabled ? 'Activée' : 'Désactivée'}',
      )
      ..writeln(
        '- **Gains par discipline** : Backend `${_formatPctOrDec(ai.backendGainPct)} %` · Frontend/UX `${_formatPctOrDec(ai.frontendUxGainPct)} %` · Data & Intégrations `${_formatPctOrDec(ai.dataIntegrationGainPct)} %` · QA/BDD/TDD `${_formatPctOrDec(ai.qaTestingGainPct)} %` · DevSecOps `${_formatPctOrDec(ai.devSecOpsGainPct)} %` · Pilotage/Specs `${_formatPctOrDec(ai.pmSpecsGainPct)} %`',
      )
      ..writeln();

    if (cost.assumptionsNotes.trim().isNotEmpty) {
      buf
        ..writeln('### 2.5 Notes & Hypothèses Contractuelles')
        ..writeln()
        ..writeln(cost.assumptionsNotes.trim())
        ..writeln();
    }
  }

  static void _writeBuildWbsSection(
    StringBuffer buf,
    SpecForgeProject project,
    CostProjectSummary summary,
  ) {
    final cost = project.costSpec;
    final cur = summary.currency;

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 3. Détail du Chiffrage Build (CAPEX / WBS)')
      ..writeln();

    if (cost.wbsItems.isEmpty) {
      buf
        ..writeln('_Aucun lot de travaux Build (`WBS-xxx`) défini._')
        ..writeln();
      return;
    }

    buf
      ..writeln(
        '| Code | Intitulé | Lot MoSCoW | Pôle | Profil | T-shirt | O / M / P (j/h) | PERT (j/h) | IA (j/h) | Coût Retenu | Traçabilité |',
      )
      ..writeln('|---|---|---|---|---|---|---|---|---|---|---|');

    for (final item in cost.wbsItems) {
      final profile = CostCalculator.resolveItemProfile(item, cost);
      final pertDays = CostCalculator.itemClassicDays(item);
      final aiDays = CostCalculator.itemAiDays(item, cost);
      final effectiveCost = CostCalculator.itemEffectiveCost(item, cost);
      final omp =
          '${_formatPctOrDec(item.optimisticDays)} / ${_formatPctOrDec(item.mostLikelyDays)} / ${_formatPctOrDec(item.pessimisticDays)}';
      final refs = <String>[
        ...item.requirementIds.map((r) => '`$r`'),
        ...item.businessObjectIds.map((o) => '`$o`'),
        ...item.uxScreenIds.map((s) => '`$s`'),
        ...item.qaFeatureIds.map((f) => '`$f`'),
        ...item.tddSuiteIds.map((t) => '`$t`'),
      ];
      buf.writeln(
        '| `${_esc(item.code)}` | **${_esc(item.title)}** | ${item.priority.code} | ${_esc(item.discipline.shortLabel)} | `${_esc(profile.code)}` | ${_esc(item.tshirtSize.code)} | $omp | ${CostCalculator.formatDays(pertDays)} | ${item.aiEligible ? CostCalculator.formatDays(aiDays) : '_(non éligible)_'} | **${CostCalculator.formatAmount(effectiveCost, cur)}** | ${refs.isEmpty ? '—' : _esc(refs.join(', '))} |',
      );
    }

    final full = summary.fullLot;
    buf
      ..writeln()
      ..writeln(
        '- **Sous-total WBS Cible (`Must + Should + Could`)** : ${CostCalculator.formatDays(cost.aiProductivity.enabled ? full.aiWbsExpectedDays : full.wbsExpectedDays)}',
      )
      ..writeln(
        '- **Activités transverses Cible** : ${CostCalculator.formatDays(cost.aiProductivity.enabled ? full.aiTransverseDays : full.transverseDays)}',
      )
      ..writeln(
        '- **Provision aléas Cible** : ${CostCalculator.formatDays(cost.aiProductivity.enabled ? full.aiContingencyDays : full.contingencyDays)}',
      )
      ..writeln(
        '- **Total Build Cible retenu** : **${CostCalculator.formatDays(full.effectiveTotalDays)}** → **${CostCalculator.formatAmount(full.effectiveTotalCost, cur)}** _(P80 : ${CostCalculator.formatAmount(full.effectiveP80Cost, cur)})_',
      )
      ..writeln();
  }

  static void _writeRunOpexSection(
    StringBuffer buf,
    SpecForgeProject project,
    CostProjectSummary summary,
  ) {
    final cost = project.costSpec;
    final cur = summary.currency;

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 4. Détail des Coûts Récurrents d’Exploitation (Run / OPEX)')
      ..writeln();

    if (cost.runItems.isEmpty) {
      buf
        ..writeln('_Aucun poste récurrent d’exploitation (`RUN-xxx`) défini._')
        ..writeln();
      return;
    }

    buf
      ..writeln(
        '| Code | Poste OPEX | Catégorie | Environnement | Cycle | Statut | Mensuel An 1 | Année 1 | Croissance/an | Année 3 |',
      )
      ..writeln('|---|---|---|---|---|---|---|---|---|---|');

    for (final run in cost.runItems) {
      buf.writeln(
        '| `${_esc(run.code)}` | **${_esc(run.name)}** | ${_esc(run.category.label)} | ${_esc(run.environment.label)} | ${run.billingCycle.label} | ${run.enabled ? 'Actif' : 'Inactif'} | ${CostCalculator.formatAmount(run.monthlyCost, cur)} | ${CostCalculator.formatAmount(run.yearlyCostForYear(1), cur)} | `${_formatPctOrDec(run.annualGrowthPct)} %` | ${CostCalculator.formatAmount(run.yearlyCostForYear(3), cur)} |',
      );
    }

    buf
      ..writeln()
      ..writeln(
        '- **Mensuel lissé Année 1** : **${CostCalculator.formatAmount(summary.monthlyRunYear1, cur)} / mois**',
      )
      ..writeln(
        '- **Projection annuelle** : Année 1 = **${CostCalculator.formatAmount(summary.yearlyRunYear1, cur)}** · Année 2 = **${CostCalculator.formatAmount(summary.yearlyRunYear2, cur)}** · Année 3 = **${CostCalculator.formatAmount(summary.yearlyRunYear3, cur)}**',
      )
      ..writeln(
        '- **Cumul OPEX** : 3 ans = **${CostCalculator.formatAmount(summary.cumulativeRun3Years, cur)}** · 5 ans = **${CostCalculator.formatAmount(summary.cumulativeRun5Years, cur)}**',
      )
      ..writeln();
  }

  static void _writeRisksSection(
    StringBuffer buf,
    SpecForgeProject project,
    CostProjectSummary summary,
  ) {
    final cost = project.costSpec;
    final cur = summary.currency;

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 5. Registre des Risques & Provision Probabilisée (EMV)')
      ..writeln();

    if (cost.riskItems.isEmpty) {
      buf
        ..writeln('_Aucun risque budgétaire (`RSK-xxx`) recensé._')
        ..writeln();
      return;
    }

    buf
      ..writeln(
        '| Code | Risque | Probabilité | Impact Charge | Impact Fixe | Profil | Charge EMV | Coût EMV | Mitigation |',
      )
      ..writeln('|---|---|---|---|---|---|---|---|---|');

    for (final risk in cost.riskItems) {
      final profile = CostCalculator.resolveRiskProfile(risk, cost);
      final emvCost = CostCalculator.riskItemEmvCost(risk, cost);
      buf.writeln(
        '| `${_esc(risk.code)}` | **${_esc(risk.title)}** | `${_formatPctOrDec(risk.probabilityPct)} %` | ${CostCalculator.formatDays(risk.impactDays)} | ${CostCalculator.formatAmount(risk.fixedCostImpact, cur)} | `${_esc(profile.code)}` | ${CostCalculator.formatDays(risk.expectedDays)} | **${CostCalculator.formatAmount(emvCost, cur)}** | ${_esc(risk.mitigation.isEmpty ? '—' : risk.mitigation)} |',
      );
    }

    buf
      ..writeln()
      ..writeln(
        '- **Provision totale EMV** : **${CostCalculator.formatDays(summary.riskEmvDays)}** → **${CostCalculator.formatAmount(summary.riskEmvCost, cur)}**',
      )
      ..writeln();
  }

  static void _writeCoherenceSection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final localIssues = CostCoherenceAnalyzer.analyze(project);
    final aiIssues = project.costSpec.coherenceIssues.where(
      (i) => i.source == 'ai',
    );
    final allIssues = <CostCoherenceIssue>[...localIssues, ...aiIssues];

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 6. Diagnostics de Cohérence Financière & Couverture')
      ..writeln();

    if (allIssues.isEmpty) {
      buf
        ..writeln('_Aucune anomalie de cohérence financière détectée._')
        ..writeln();
      return;
    }

    for (final issue in allIssues) {
      final badge = switch (issue.severity) {
        CoherenceSeverity.error => '[ERREUR]',
        CoherenceSeverity.warning => '[ATTENTION]',
        CoherenceSeverity.info => '[INFO]',
      };
      final suggestionSuffix = issue.suggestion.trim().isEmpty
          ? ''
          : ' _(Recommandation : ${issue.suggestion.trim()})_';
      buf.writeln(
        '- **$badge ${issue.code} — ${issue.title}** : ${issue.description}$suggestionSuffix',
      );
    }
    buf.writeln();
  }

  static String _formatPctOrDec(double value) {
    if (!value.isFinite) return '0';
    final rounded = (value * 100.0).round() / 100.0;
    if ((rounded - rounded.roundToDouble()).abs() < 1e-6) {
      return '${rounded.round()}';
    }
    return rounded
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  static String _esc(String value) =>
      value.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}
