/// Moteur déterministe de calcul financier Build (PERT, P80, ratios transverses, gains IA), Run (OPEX pluriannuel), Risques (EMV) et TCO 1/3/5 ans ([CostCalculator]).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/cost/cost_forge_spec.dart';
import '../models/cost/cost_risk_item_spec.dart';
import '../models/cost/cost_wbs_item_spec.dart';
import '../models/enterprise_rate_card.dart';
import '../models/spec_cahier_des_charges.dart';

/// Filtre de périmètre MoSCoW permettant de simuler les enveloppes MVP, V1, Cible ou complète.
enum CostScopeFilter {
  /// Lot MVP restreint aux seules exigences indispensables (`Must`).
  mvpMust('MVP (Must)'),

  /// Lot V1 regroupant les exigences `Must` et `Should`.
  v1Should('V1 (Must + Should)'),

  /// Périmètre cible regroupant `Must`, `Should` et `Could` (hors `Won't`).
  fullTarget('Cible (Must + Should + Could)'),

  /// Intégralité des postes WBS y compris les éléments reportés (`Won't`).
  allWithWont('Tout (incl. Won\'t)');

  /// Construit un filtre de lotissement MoSCoW.
  const CostScopeFilter(this.label);

  /// Libellé lisible en français affiché dans les sélecteurs et tableaux.
  final String label;

  /// Indique si un lot de priorité [priority] est retenu dans ce périmètre.
  bool includes(RequirementPriority priority) => switch (this) {
    CostScopeFilter.mvpMust => priority == RequirementPriority.must,
    CostScopeFilter.v1Should =>
      priority == RequirementPriority.must ||
          priority == RequirementPriority.should,
    CostScopeFilter.fullTarget => priority != RequirementPriority.wont,
    CostScopeFilter.allWithWont => true,
  };
}

/// Agrégation des charges et coûts WBS directs pour une [CostDiscipline] donnée.
@immutable
class CostDisciplineBreakdown {
  /// Construit une ventilation immuable par discipline d'ingénierie.
  const CostDisciplineBreakdown({
    required this.discipline,
    required this.itemCount,
    required this.classicExpectedDays,
    required this.aiExpectedDays,
    required this.classicCost,
    required this.aiCost,
  });

  /// Discipline d'ingénierie concernée.
  final CostDiscipline discipline;

  /// Nombre de postes WBS rattachés à cette discipline dans le lot.
  final int itemCount;

  /// Charge espérée PERT classique cumulée en jours/homme.
  final double classicExpectedDays;

  /// Charge espérée cumulée avec ingénierie assistée par IA en jours/homme.
  final double aiExpectedDays;

  /// Coût direct classique valorisé aux TJM effectifs des postes.
  final double classicCost;

  /// Coût direct assisté par IA valorisé aux TJM effectifs des postes.
  final double aiCost;

  /// Nombre de jours/homme économisés grâce à l'accélération IA sur cette discipline.
  double get savedDays => classicExpectedDays - aiExpectedDays;

  /// Montant économisé grâce à l'accélération IA sur cette discipline.
  double get savedCost => classicCost - aiCost;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostDisciplineBreakdown &&
          other.discipline == discipline &&
          other.itemCount == itemCount &&
          other.classicExpectedDays == classicExpectedDays &&
          other.aiExpectedDays == aiExpectedDays &&
          other.classicCost == classicCost &&
          other.aiCost == aiCost;

  @override
  int get hashCode => Object.hash(
    discipline,
    itemCount,
    classicExpectedDays,
    aiExpectedDays,
    classicCost,
    aiCost,
  );
}

/// Synthèse consolidée des charges (j/h) et coûts Build (CAPEX) pour un [CostScopeFilter] donné.
@immutable
class CostLotSummary {
  /// Construit le récapitulatif financier immuable d'un lot Build.
  CostLotSummary({
    required this.scope,
    required this.itemCount,
    required this.wbsOptimisticDays,
    required this.wbsExpectedDays,
    required this.wbsPessimisticDays,
    required this.wbsP80Days,
    required this.transverseDays,
    required this.contingencyDays,
    required this.classicTotalDays,
    required this.classicTotalCost,
    required this.aiWbsExpectedDays,
    required this.aiTransverseDays,
    required this.aiContingencyDays,
    required this.aiTotalDays,
    required this.aiTotalCost,
    required this.effectiveTotalDays,
    required this.effectiveTotalCost,
    required this.effectiveP80Cost,
    required Map<CostDiscipline, CostDisciplineBreakdown> byDiscipline,
  }) : byDiscipline =
           Map<CostDiscipline, CostDisciplineBreakdown>.unmodifiable(
             byDiscipline,
           );

  /// Périmètre MoSCoW couvert par ce lot.
  final CostScopeFilter scope;

  /// Nombre de lots WBS inclus dans ce périmètre.
  final int itemCount;

  /// Somme des charges optimistes `O` des postes WBS du lot (j/h).
  final double wbsOptimisticDays;

  /// Somme des charges espérées PERT `(O + 4M + P) / 6` des postes WBS du lot (j/h).
  final double wbsExpectedDays;

  /// Somme des charges pessimistes `P` des postes WBS du lot (j/h).
  final double wbsPessimisticDays;

  /// Charge WBS au percentile P80 (`wbsExpectedDays + 0.8416 * sqrt(sumVariance)`).
  final double wbsP80Days;

  /// Charge d'activités transverses classique (Pilotage + Archi/DevOps + QA transverse).
  final double transverseDays;

  /// Provision d'aléas classique en jours/homme sur `(wbsExpectedDays + transverseDays)`.
  final double contingencyDays;

  /// Charge Build totale classique (`wbsExpectedDays + transverseDays + contingencyDays`).
  final double classicTotalDays;

  /// Coût Build total classique (WBS + transverses valorisés aux profils dédiés + aléas).
  final double classicTotalCost;

  /// Somme des charges WBS après application des gains de productivité IA.
  final double aiWbsExpectedDays;

  /// Charge d'activités transverses après application des gains IA sur Pilotage, DevSecOps et QA.
  final double aiTransverseDays;

  /// Provision d'aléas en mode assisté par IA en jours/homme.
  final double aiContingencyDays;

  /// Charge Build totale en mode assisté par IA (`aiWbsExpectedDays + aiTransverseDays + aiContingencyDays`).
  final double aiTotalDays;

  /// Coût Build total en mode assisté par IA.
  final double aiTotalCost;

  /// Charge totale retenue selon l'activation ou non de `aiProductivity.enabled`.
  final double effectiveTotalDays;

  /// Coût Build total retenu selon l'activation ou non de `aiProductivity.enabled`.
  final double effectiveTotalCost;

  /// Enveloppe financière prudente P80 extrapolée depuis `wbsP80Days / wbsExpectedDays`.
  final double effectiveP80Cost;

  /// Répartition détaillée des postes WBS directs par discipline d'ingénierie.
  final Map<CostDiscipline, CostDisciplineBreakdown> byDiscipline;

  /// Gain total en jours/homme procuré par l'ingénierie assistée par IA sur ce lot.
  double get aiSavedDays => classicTotalDays - aiTotalDays;

  /// Économie budgétaire totale procurée par l'ingénierie assistée par IA sur ce lot.
  double get aiSavedCost => classicTotalCost - aiTotalCost;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostLotSummary &&
          other.scope == scope &&
          other.itemCount == itemCount &&
          other.wbsOptimisticDays == wbsOptimisticDays &&
          other.wbsExpectedDays == wbsExpectedDays &&
          other.wbsPessimisticDays == wbsPessimisticDays &&
          other.wbsP80Days == wbsP80Days &&
          other.transverseDays == transverseDays &&
          other.contingencyDays == contingencyDays &&
          other.classicTotalDays == classicTotalDays &&
          other.classicTotalCost == classicTotalCost &&
          other.aiWbsExpectedDays == aiWbsExpectedDays &&
          other.aiTransverseDays == aiTransverseDays &&
          other.aiContingencyDays == aiContingencyDays &&
          other.aiTotalDays == aiTotalDays &&
          other.aiTotalCost == aiTotalCost &&
          other.effectiveTotalDays == effectiveTotalDays &&
          other.effectiveTotalCost == effectiveTotalCost &&
          other.effectiveP80Cost == effectiveP80Cost &&
          mapEquals(other.byDiscipline, byDiscipline);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    scope,
    itemCount,
    wbsOptimisticDays,
    wbsExpectedDays,
    wbsPessimisticDays,
    wbsP80Days,
    transverseDays,
    contingencyDays,
    classicTotalDays,
    classicTotalCost,
    aiWbsExpectedDays,
    aiTransverseDays,
    aiContingencyDays,
    aiTotalDays,
    aiTotalCost,
    effectiveTotalDays,
    effectiveTotalCost,
    effectiveP80Cost,
    Object.hashAll(byDiscipline.entries.map((e) => Object.hash(e.key, e.value))),
  ]);
}

/// Synthèse financière globale d'un projet : lots Build (MVP/V1/Cible/Tout), OPEX Run, Risques EMV et TCO 1/3/5 ans.
@immutable
class CostProjectSummary {
  /// Construit la synthèse financière consolidée du projet.
  const CostProjectSummary({
    required this.currency,
    required this.mvpLot,
    required this.v1Lot,
    required this.fullLot,
    required this.allLot,
    required this.monthlyRunYear1,
    required this.yearlyRunYear1,
    required this.yearlyRunYear2,
    required this.yearlyRunYear3,
    required this.cumulativeRun3Years,
    required this.cumulativeRun5Years,
    required this.riskEmvDays,
    required this.riskEmvCost,
    required this.tco1Year,
    required this.tco3Years,
    required this.tco5Years,
  });

  /// Devise monétaire de référence du chiffrage.
  final CostCurrency currency;

  /// Synthèse Build du lot MVP (`Must`).
  final CostLotSummary mvpLot;

  /// Synthèse Build du lot V1 (`Must + Should`).
  final CostLotSummary v1Lot;

  /// Synthèse Build du périmètre cible (`Must + Should + Could`).
  final CostLotSummary fullLot;

  /// Synthèse Build complète incluant les postes `Won't`.
  final CostLotSummary allLot;

  /// Coût mensuel récurrent lissé d'exploitation en année 1.
  final double monthlyRunYear1;

  /// Coût annuel d'exploitation (OPEX) en année 1.
  final double yearlyRunYear1;

  /// Coût annuel d'exploitation projeté en année 2 (avec croissance annuelle composée).
  final double yearlyRunYear2;

  /// Coût annuel d'exploitation projeté en année 3 (avec croissance annuelle composée).
  final double yearlyRunYear3;

  /// Cumul des coûts d'exploitation OPEX sur 3 ans (années 1 à 3).
  final double cumulativeRun3Years;

  /// Cumul des coûts d'exploitation OPEX sur 5 ans (années 1 à 5).
  final double cumulativeRun5Years;

  /// Espérance mathématique totale de charge des risques identifiés (j/h EMV).
  final double riskEmvDays;

  /// Provision financière totale des risques identifiés (EMV j/h valorisés + impacts forfaitaires).
  final double riskEmvCost;

  /// Coût complet de possession à 1 an (`fullLot.effectiveTotalCost + riskEmvCost + yearlyRunYear1`).
  final double tco1Year;

  /// Coût complet de possession à 3 ans (`fullLot.effectiveTotalCost + riskEmvCost + cumulativeRun3Years`).
  final double tco3Years;

  /// Coût complet de possession à 5 ans (`fullLot.effectiveTotalCost + riskEmvCost + cumulativeRun5Years`).
  final double tco5Years;

  /// Retourne la synthèse Build associée au filtre [filter].
  CostLotSummary lotFor(CostScopeFilter filter) => switch (filter) {
    CostScopeFilter.mvpMust => mvpLot,
    CostScopeFilter.v1Should => v1Lot,
    CostScopeFilter.fullTarget => fullLot,
    CostScopeFilter.allWithWont => allLot,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostProjectSummary &&
          other.currency == currency &&
          other.mvpLot == mvpLot &&
          other.v1Lot == v1Lot &&
          other.fullLot == fullLot &&
          other.allLot == allLot &&
          other.monthlyRunYear1 == monthlyRunYear1 &&
          other.yearlyRunYear1 == yearlyRunYear1 &&
          other.yearlyRunYear2 == yearlyRunYear2 &&
          other.yearlyRunYear3 == yearlyRunYear3 &&
          other.cumulativeRun3Years == cumulativeRun3Years &&
          other.cumulativeRun5Years == cumulativeRun5Years &&
          other.riskEmvDays == riskEmvDays &&
          other.riskEmvCost == riskEmvCost &&
          other.tco1Year == tco1Year &&
          other.tco3Years == tco3Years &&
          other.tco5Years == tco5Years;

  @override
  int get hashCode => Object.hash(
    currency,
    mvpLot,
    v1Lot,
    fullLot,
    allLot,
    monthlyRunYear1,
    yearlyRunYear1,
    yearlyRunYear2,
    yearlyRunYear3,
    cumulativeRun3Years,
    cumulativeRun5Years,
    riskEmvDays,
    riskEmvCost,
    tco1Year,
    tco3Years,
    tco5Years,
  );
}

/// Calculateur statique pur des indicateurs Build (CAPEX), Run (OPEX), Risques (EMV) et TCO.
abstract final class CostCalculator {
  static const double _zScoreP80 = 0.8416;

  /// Calcule la synthèse financière complète ([CostProjectSummary]) à partir de [spec].
  static CostProjectSummary compute(CostForgeSpec spec) {
    final mvpLot = _computeLot(spec, CostScopeFilter.mvpMust);
    final v1Lot = _computeLot(spec, CostScopeFilter.v1Should);
    final fullLot = _computeLot(spec, CostScopeFilter.fullTarget);
    final allLot = _computeLot(spec, CostScopeFilter.allWithWont);

    var monthlyRunYear1 = 0.0;
    var yearlyRunYear1 = 0.0;
    var yearlyRunYear2 = 0.0;
    var yearlyRunYear3 = 0.0;
    var yearlyRunYear4 = 0.0;
    var yearlyRunYear5 = 0.0;

    for (final run in spec.runItems) {
      if (!run.enabled) continue;
      monthlyRunYear1 += run.monthlyCost;
      yearlyRunYear1 += run.yearlyCostForYear(1);
      yearlyRunYear2 += run.yearlyCostForYear(2);
      yearlyRunYear3 += run.yearlyCostForYear(3);
      yearlyRunYear4 += run.yearlyCostForYear(4);
      yearlyRunYear5 += run.yearlyCostForYear(5);
    }

    final cumulativeRun3Years =
        yearlyRunYear1 + yearlyRunYear2 + yearlyRunYear3;
    final cumulativeRun5Years =
        cumulativeRun3Years + yearlyRunYear4 + yearlyRunYear5;

    var riskEmvDays = 0.0;
    var riskEmvCost = 0.0;
    for (final risk in spec.riskItems) {
      riskEmvDays += risk.expectedDays;
      riskEmvCost += riskItemEmvCost(risk, spec);
    }

    final baseCapexAndRisks = fullLot.effectiveTotalCost + riskEmvCost;
    return CostProjectSummary(
      currency: spec.currency,
      mvpLot: mvpLot,
      v1Lot: v1Lot,
      fullLot: fullLot,
      allLot: allLot,
      monthlyRunYear1: monthlyRunYear1,
      yearlyRunYear1: yearlyRunYear1,
      yearlyRunYear2: yearlyRunYear2,
      yearlyRunYear3: yearlyRunYear3,
      cumulativeRun3Years: cumulativeRun3Years,
      cumulativeRun5Years: cumulativeRun5Years,
      riskEmvDays: riskEmvDays,
      riskEmvCost: riskEmvCost,
      tco1Year: baseCapexAndRisks + yearlyRunYear1,
      tco3Years: baseCapexAndRisks + cumulativeRun3Years,
      tco5Years: baseCapexAndRisks + cumulativeRun5Years,
    );
  }

  /// Résout le profil TJM applicable au lot WBS [item] dans [spec] (avec repli sur la discipline du lot).
  static CostProfileRate resolveItemProfile(
    CostWbsItemSpec item,
    CostForgeSpec spec,
  ) =>
      spec.findProfile(item.profileId) ??
      spec.resolveProfileForDiscipline(item.discipline);

  /// Résout le profil TJM applicable au risque [risk] dans [spec] (avec repli sur la discipline Backend).
  static CostProfileRate resolveRiskProfile(
    CostRiskItemSpec risk,
    CostForgeSpec spec,
  ) =>
      spec.findProfile(risk.profileId) ??
      spec.resolveProfileForDiscipline(CostDiscipline.backend);

  /// Calcule le coût probabilisé EMV complet d'un risque [risk] (jours pondérés × TJM + surcoût fixe pondéré).
  static double riskItemEmvCost(CostRiskItemSpec risk, CostForgeSpec spec) {
    final dailyRate = resolveRiskProfile(
      risk,
      spec,
    ).effectiveDailyRate(spec.deliveryMode);
    return risk.expectedDays * dailyRate + risk.expectedFixedCost;
  }

  /// Retourne la charge espérée PERT classique d'un poste WBS en jours/homme.
  static double itemClassicDays(CostWbsItemSpec item) => item.expectedDays;

  /// Calcule la charge espérée d'un poste WBS en mode assisté par IA.
  static double itemAiDays(CostWbsItemSpec item, CostForgeSpec spec) {
    if (!spec.aiProductivity.enabled || !item.aiEligible) {
      return item.expectedDays;
    }
    final gainPct = spec.aiProductivity.gainPctFor(item.discipline);
    final factor = (1.0 - gainPct / 100.0).clamp(0.0, 1.0);
    return item.expectedDays * factor;
  }

  /// Retourne la charge effective retenue d'un poste WBS selon `spec.aiProductivity.enabled`.
  static double itemEffectiveDays(CostWbsItemSpec item, CostForgeSpec spec) =>
      spec.aiProductivity.enabled
      ? itemAiDays(item, spec)
      : itemClassicDays(item);

  /// Calcule le coût direct classique d'un poste WBS au TJM effectif de son profil.
  static double itemClassicCost(CostWbsItemSpec item, CostForgeSpec spec) =>
      itemClassicDays(item) *
      resolveItemProfile(item, spec).effectiveDailyRate(spec.deliveryMode);

  /// Calcule le coût direct assisté par IA d'un poste WBS au TJM effectif de son profil.
  static double itemAiCost(CostWbsItemSpec item, CostForgeSpec spec) =>
      itemAiDays(item, spec) *
      resolveItemProfile(item, spec).effectiveDailyRate(spec.deliveryMode);

  /// Retourne le coût direct effectif retenu d'un poste WBS selon `spec.aiProductivity.enabled`.
  static double itemEffectiveCost(CostWbsItemSpec item, CostForgeSpec spec) =>
      spec.aiProductivity.enabled
      ? itemAiCost(item, spec)
      : itemClassicCost(item, spec);

  /// Formate un montant financier en français avec le symbole de [currency] (ex. `92 400 €`, ou `92,4 k€` / `1,2 M€` si [compact] vaut `true`).
  static String formatAmount(
    double amount,
    CostCurrency currency, {
    bool compact = false,
  }) {
    if (!amount.isFinite) return '0 ${currency.symbol}';
    final sign = amount < -1e-6 ? '-' : '';
    final abs = amount.abs();

    if (compact) {
      if (abs >= 1000000.0) {
        return '$sign${_formatDecimalFr(abs / 1000000.0, 1)} M${currency.symbol}';
      }
      if (abs >= 1000.0) {
        return '$sign${_formatDecimalFr(abs / 1000.0, 1)} k${currency.symbol}';
      }
    }

    final roundedInt = abs.round();
    if (abs >= 10.0 || (abs - roundedInt).abs() < 0.005) {
      return '$sign${_groupThousands(roundedInt)} ${currency.symbol}';
    }
    return '$sign${_formatDecimalFr(abs, 2)} ${currency.symbol}';
  }

  /// Formate une charge en jours/homme selon les conventions françaises (ex. `12,5 j/h` ou `12 j/h`).
  static String formatDays(double days) {
    if (!days.isFinite || days.abs() < 1e-6) return '0 j/h';
    final sign = days < 0 ? '-' : '';
    final abs = days.abs();
    return '$sign${_formatDecimalFr(abs, 1)} j/h';
  }

  static CostLotSummary _computeLot(
    CostForgeSpec spec,
    CostScopeFilter scope,
  ) {
    final items = [
      for (final item in spec.wbsItems)
        if (scope.includes(item.priority)) item,
    ];

    var wbsOptimisticDays = 0.0;
    var wbsExpectedDays = 0.0;
    var wbsPessimisticDays = 0.0;
    var sumVariance = 0.0;
    var classicWbsCost = 0.0;
    var aiWbsExpectedDays = 0.0;
    var aiWbsCost = 0.0;

    final countByDisc = <CostDiscipline, int>{};
    final classicDaysByDisc = <CostDiscipline, double>{};
    final aiDaysByDisc = <CostDiscipline, double>{};
    final classicCostByDisc = <CostDiscipline, double>{};
    final aiCostByDisc = <CostDiscipline, double>{};

    for (final item in items) {
      final cDays = itemClassicDays(item);
      final aDays = itemAiDays(item, spec);
      final cCost = itemClassicCost(item, spec);
      final aCost = itemAiCost(item, spec);

      wbsOptimisticDays += item.optimisticDays;
      wbsExpectedDays += cDays;
      wbsPessimisticDays += item.pessimisticDays;
      sumVariance += item.varianceDays;
      classicWbsCost += cCost;
      aiWbsExpectedDays += aDays;
      aiWbsCost += aCost;

      final d = item.discipline;
      countByDisc[d] = (countByDisc[d] ?? 0) + 1;
      classicDaysByDisc[d] = (classicDaysByDisc[d] ?? 0.0) + cDays;
      aiDaysByDisc[d] = (aiDaysByDisc[d] ?? 0.0) + aDays;
      classicCostByDisc[d] = (classicCostByDisc[d] ?? 0.0) + cCost;
      aiCostByDisc[d] = (aiCostByDisc[d] ?? 0.0) + aCost;
    }

    final stdDevPortfolio = sumVariance > 0.0 ? math.sqrt(sumVariance) : 0.0;
    final wbsP80Days = wbsExpectedDays + _zScoreP80 * stdDevPortfolio;

    final ratios = spec.transverseRatios;
    final pmDays = (ratios.projectManagementPct / 100.0) * wbsExpectedDays;
    final archOpsDays =
        (ratios.architectureDevOpsPct / 100.0) * wbsExpectedDays;
    final qaTransverseDays = (ratios.transverseQaPct / 100.0) * wbsExpectedDays;

    final transverseDays =
        ((ratios.projectManagementPct +
                ratios.architectureDevOpsPct +
                ratios.transverseQaPct) /
            100.0) *
        wbsExpectedDays;
    final contingencyDays =
        (ratios.contingencyPct / 100.0) * (wbsExpectedDays + transverseDays);
    final classicTotalDays = wbsExpectedDays + transverseDays + contingencyDays;

    final pmRate = spec
        .resolveProfileForDiscipline(CostDiscipline.projectManagement)
        .effectiveDailyRate(spec.deliveryMode);
    final archOpsRate = spec
        .resolveProfileForDiscipline(CostDiscipline.devSecOps)
        .effectiveDailyRate(spec.deliveryMode);
    final qaRate = spec
        .resolveProfileForDiscipline(CostDiscipline.qaTesting)
        .effectiveDailyRate(spec.deliveryMode);

    final classicTransverseCost =
        pmDays * pmRate + archOpsDays * archOpsRate + qaTransverseDays * qaRate;
    final classicSubtotalCost = classicWbsCost + classicTransverseCost;
    final classicTotalCost =
        classicSubtotalCost * (1.0 + ratios.contingencyPct / 100.0);

    final double aiTransverseDays;
    final double aiContingencyDays;
    final double aiTotalDays;
    final double aiTotalCost;

    if (!spec.aiProductivity.enabled) {
      aiTransverseDays = transverseDays;
      aiContingencyDays = contingencyDays;
      aiTotalDays = classicTotalDays;
      aiTotalCost = classicTotalCost;
    } else {
      final ai = spec.aiProductivity;
      final pmFactor =
          (1.0 - ai.gainPctFor(CostDiscipline.projectManagement) / 100.0).clamp(
            0.0,
            1.0,
          );
      final archOpsFactor =
          (1.0 - ai.gainPctFor(CostDiscipline.devSecOps) / 100.0).clamp(
            0.0,
            1.0,
          );
      final qaFactor = (1.0 - ai.gainPctFor(CostDiscipline.qaTesting) / 100.0)
          .clamp(0.0, 1.0);

      final aiPmDays = pmDays * pmFactor;
      final aiArchOpsDays = archOpsDays * archOpsFactor;
      final aiQaTransverseDays = qaTransverseDays * qaFactor;

      aiTransverseDays = aiPmDays + aiArchOpsDays + aiQaTransverseDays;
      aiContingencyDays =
          (ratios.contingencyPct / 100.0) *
          (aiWbsExpectedDays + aiTransverseDays);
      aiTotalDays = aiWbsExpectedDays + aiTransverseDays + aiContingencyDays;

      final aiTransverseCost =
          aiPmDays * pmRate +
          aiArchOpsDays * archOpsRate +
          aiQaTransverseDays * qaRate;
      final aiSubtotalCost = aiWbsCost + aiTransverseCost;
      aiTotalCost = aiSubtotalCost * (1.0 + ratios.contingencyPct / 100.0);
    }

    final effectiveTotalDays = spec.aiProductivity.enabled
        ? aiTotalDays
        : classicTotalDays;
    final effectiveTotalCost = spec.aiProductivity.enabled
        ? aiTotalCost
        : classicTotalCost;
    final effectiveP80Cost = wbsExpectedDays > 1e-6
        ? effectiveTotalCost * (wbsP80Days / wbsExpectedDays)
        : 0.0;

    final byDiscipline = <CostDiscipline, CostDisciplineBreakdown>{
      for (final d in CostDiscipline.values)
        d: CostDisciplineBreakdown(
          discipline: d,
          itemCount: countByDisc[d] ?? 0,
          classicExpectedDays: classicDaysByDisc[d] ?? 0.0,
          aiExpectedDays: aiDaysByDisc[d] ?? 0.0,
          classicCost: classicCostByDisc[d] ?? 0.0,
          aiCost: aiCostByDisc[d] ?? 0.0,
        ),
    };

    return CostLotSummary(
      scope: scope,
      itemCount: items.length,
      wbsOptimisticDays: wbsOptimisticDays,
      wbsExpectedDays: wbsExpectedDays,
      wbsPessimisticDays: wbsPessimisticDays,
      wbsP80Days: wbsP80Days,
      transverseDays: transverseDays,
      contingencyDays: contingencyDays,
      classicTotalDays: classicTotalDays,
      classicTotalCost: classicTotalCost,
      aiWbsExpectedDays: aiWbsExpectedDays,
      aiTransverseDays: aiTransverseDays,
      aiContingencyDays: aiContingencyDays,
      aiTotalDays: aiTotalDays,
      aiTotalCost: aiTotalCost,
      effectiveTotalDays: effectiveTotalDays,
      effectiveTotalCost: effectiveTotalCost,
      effectiveP80Cost: effectiveP80Cost,
      byDiscipline: byDiscipline,
    );
  }

  static String _groupThousands(int nonNegativeValue) {
    final digits = nonNegativeValue.toString();
    if (digits.length <= 3) return digits;
    final buf = StringBuffer();
    final firstGroupLen = digits.length % 3;
    if (firstGroupLen > 0) {
      buf.write(digits.substring(0, firstGroupLen));
    }
    for (var i = firstGroupLen; i < digits.length; i += 3) {
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(digits.substring(i, i + 3));
    }
    return buf.toString();
  }

  static String _formatDecimalFr(double nonNegativeValue, int maxDecimals) {
    final scale = math.pow(10, maxDecimals).toDouble();
    final rounded = (nonNegativeValue * scale).round() / scale;
    final intPart = rounded.truncate();
    final fixed = rounded.toStringAsFixed(maxDecimals);
    final dotIndex = fixed.indexOf('.');
    final groupedInt = _groupThousands(intPart);
    if (dotIndex < 0) return groupedInt;
    final frac = fixed
        .substring(dotIndex + 1)
        .replaceFirst(RegExp(r'0+$'), '');
    if (frac.isEmpty) return groupedInt;
    return '$groupedInt,$frac';
  }
}
