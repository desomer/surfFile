/// Exportateur de feuilles budgétaires CSV compatibles Excel UTF-8 (WBS Build, OPEX Run et Synthèse TCO) ([CostCsvExporter]).
library;

import '../../models/spec_forge_project.dart';
import '../cost_calculator.dart';

/// Génère les fichiers CSV UTF-8 conformes RFC-4180 (séparateur `;` et BOM UTF-8 optionnel pour Excel FR) du volet FinOps.
abstract final class CostCsvExporter {
  static const String _utf8Bom = '\uFEFF';

  /// Exporte le détail des lots de travaux Build WBS au format CSV.
  static String exportWbsCsv(
    SpecForgeProject project, {
    bool includeBom = true,
    String delimiter = ';',
  }) {
    final cost = project.costSpec;
    final rows = <List<String>>[
      <String>[
        'Code',
        'ID',
        'Intitulé',
        'Description',
        'Priorité MoSCoW',
        'Module',
        'Discipline',
        'Code Profil',
        'Profil',
        'TJM Effectif',
        'Devise',
        'Taille T-shirt',
        'Optimiste (j/h)',
        'Nominal (j/h)',
        'Pessimiste (j/h)',
        'Charge PERT (j/h)',
        'Éligible IA',
        'Charge IA (j/h)',
        'Charge Retenue (j/h)',
        'Coût Classique',
        'Coût Assisté IA',
        'Coût Retenu',
        'Exigences liées',
        'Objets métiers liés',
        'Écrans UX liés',
        'Features BDD liées',
        'Suites TDD liées',
        'Origine',
      ],
    ];

    for (final item in cost.wbsItems) {
      final profile = CostCalculator.resolveItemProfile(item, cost);
      final rate = profile.effectiveDailyRate(cost.deliveryMode);
      final classicDays = CostCalculator.itemClassicDays(item);
      final aiDays = CostCalculator.itemAiDays(item, cost);
      final effectiveDays = CostCalculator.itemEffectiveDays(item, cost);
      final classicCost = CostCalculator.itemClassicCost(item, cost);
      final aiCost = CostCalculator.itemAiCost(item, cost);
      final effectiveCost = CostCalculator.itemEffectiveCost(item, cost);

      rows.add(<String>[
        item.code,
        item.id,
        item.title,
        item.description,
        item.priority.code,
        item.moduleId,
        item.discipline.label,
        profile.code,
        profile.name,
        _num(rate, delimiter: delimiter),
        cost.currency.code,
        item.tshirtSize.code,
        _num(item.optimisticDays, delimiter: delimiter),
        _num(item.mostLikelyDays, delimiter: delimiter),
        _num(item.pessimisticDays, delimiter: delimiter),
        _num(classicDays, delimiter: delimiter),
        item.aiEligible ? 'Oui' : 'Non',
        _num(aiDays, delimiter: delimiter),
        _num(effectiveDays, delimiter: delimiter),
        _num(classicCost, delimiter: delimiter),
        _num(aiCost, delimiter: delimiter),
        _num(effectiveCost, delimiter: delimiter),
        item.requirementIds.join(', '),
        item.businessObjectIds.join(', '),
        item.uxScreenIds.join(', '),
        item.qaFeatureIds.join(', '),
        item.tddSuiteIds.join(', '),
        item.origin,
      ]);
    }

    return _encodeCsv(rows, includeBom: includeBom, delimiter: delimiter);
  }

  /// Exporte le détail des postes récurrents d'exploitation Run / OPEX au format CSV.
  static String exportRunCsv(
    SpecForgeProject project, {
    bool includeBom = true,
    String delimiter = ';',
  }) {
    final cost = project.costSpec;
    final rows = <List<String>>[
      <String>[
        'Code',
        'ID',
        'Poste OPEX',
        'Description',
        'Catégorie',
        'Environnement',
        'Périodicité',
        'Actif',
        'Coût Unitaire',
        'Quantité',
        'Devise',
        'Mensuel Année 1',
        'Annuel Année 1',
        'Croissance Annuelle (%)',
        'Annuel Année 2',
        'Annuel Année 3',
        'Cumul 3 ans',
        'Cumul 5 ans',
      ],
    ];

    for (final run in cost.runItems) {
      final y1 = run.yearlyCostForYear(1);
      final y2 = run.yearlyCostForYear(2);
      final y3 = run.yearlyCostForYear(3);
      final y4 = run.yearlyCostForYear(4);
      final y5 = run.yearlyCostForYear(5);
      final cum3 = y1 + y2 + y3;
      final cum5 = cum3 + y4 + y5;

      rows.add(<String>[
        run.code,
        run.id,
        run.name,
        run.description,
        run.category.label,
        run.environment.label,
        run.billingCycle.label,
        run.enabled ? 'Oui' : 'Non',
        _num(run.unitCost, delimiter: delimiter),
        _num(run.quantity, delimiter: delimiter),
        cost.currency.code,
        _num(run.monthlyCost, delimiter: delimiter),
        _num(y1, delimiter: delimiter),
        _num(run.annualGrowthPct, delimiter: delimiter),
        _num(y2, delimiter: delimiter),
        _num(y3, delimiter: delimiter),
        _num(cum3, delimiter: delimiter),
        _num(cum5, delimiter: delimiter),
      ]);
    }

    return _encodeCsv(rows, includeBom: includeBom, delimiter: delimiter);
  }

  /// Exporte la synthèse globale (grille TJM, lots MVP/V1/Cible, Classique vs IA, Risques EMV et TCO 1/3/5 ans) au format CSV.
  static String exportSummaryAndTcoCsv(
    SpecForgeProject project, {
    bool includeBom = true,
    String delimiter = ';',
  }) {
    final cost = project.costSpec;
    final summary = CostCalculator.compute(cost);
    final curCode = summary.currency.code;

    final rows = <List<String>>[
      <String>[
        'Section',
        'Code / Référence',
        'Libellé',
        'Détail / Pôle',
        'Charge Classique (j/h)',
        'Charge IA / EMV (j/h)',
        'Montant Classique / Interne',
        'Montant IA / Externe',
        'Montant Retenu / Effectif',
        'Devise',
      ],
      <String>[
        'Hypothèses',
        'PROJET',
        project.name,
        'Mode: ${cost.deliveryMode.label} | IA: ${cost.aiProductivity.enabled ? 'Oui' : 'Non'} | Utilisateurs: ${cost.targetUsersCount}',
        _num(cost.hoursPerDay, delimiter: delimiter),
        '',
        '',
        '',
        '',
        curCode,
      ],
    ];

    // Grille TJM
    for (final profile in cost.profiles) {
      rows.add(<String>[
        'Grille TJM',
        profile.code,
        '${profile.name} (${profile.seniority})',
        profile.discipline.label,
        '',
        '',
        _num(profile.internalDailyRate, delimiter: delimiter),
        _num(profile.externalDailyRate, delimiter: delimiter),
        _num(
          profile.effectiveDailyRate(cost.deliveryMode),
          delimiter: delimiter,
        ),
        curCode,
      ]);
    }

    // Lots Build MVP / V1 / Cible / Tout
    final lots = <CostLotSummary>[
      summary.mvpLot,
      summary.v1Lot,
      summary.fullLot,
      summary.allLot,
    ];
    for (final lot in lots) {
      rows.add(<String>[
        'Lots Build CAPEX',
        lot.scope.name,
        lot.scope.label,
        '${lot.itemCount} poste(s) | P80: ${CostCalculator.formatAmount(lot.effectiveP80Cost, summary.currency)}',
        _num(lot.classicTotalDays, delimiter: delimiter),
        _num(lot.aiTotalDays, delimiter: delimiter),
        _num(lot.classicTotalCost, delimiter: delimiter),
        _num(lot.aiTotalCost, delimiter: delimiter),
        _num(lot.effectiveTotalCost, delimiter: delimiter),
        curCode,
      ]);
    }

    // Risques EMV
    for (final risk in cost.riskItems) {
      final emvCost = CostCalculator.riskItemEmvCost(risk, cost);
      rows.add(<String>[
        'Risques EMV',
        risk.code,
        risk.title,
        'Probabilité ${_num(risk.probabilityPct, delimiter: delimiter)} %',
        _num(risk.impactDays, delimiter: delimiter),
        _num(risk.expectedDays, delimiter: delimiter),
        _num(risk.fixedCostImpact, delimiter: delimiter),
        '',
        _num(emvCost, delimiter: delimiter),
        curCode,
      ]);
    }
    rows.add(<String>[
      'Risques EMV',
      'TOTAL_EMV',
      'Provision totale des risques (EMV)',
      '${cost.riskItems.length} risque(s)',
      '',
      _num(summary.riskEmvDays, delimiter: delimiter),
      '',
      '',
      _num(summary.riskEmvCost, delimiter: delimiter),
      curCode,
    ]);

    // Synthèse Run & TCO 1 / 3 / 5 ans
    rows
      ..add(<String>[
        'Run OPEX',
        'RUN_MENSUEL_Y1',
        'Coût récurrent mensuel Année 1',
        'OPEX mensuel lissé',
        '',
        '',
        '',
        '',
        _num(summary.monthlyRunYear1, delimiter: delimiter),
        curCode,
      ])
      ..add(<String>[
        'Run OPEX',
        'RUN_Y1',
        'Coût récurrent annuel Année 1',
        'OPEX Année 1',
        '',
        '',
        '',
        '',
        _num(summary.yearlyRunYear1, delimiter: delimiter),
        curCode,
      ])
      ..add(<String>[
        'Run OPEX',
        'RUN_CUMUL_3Y',
        'Cumul Run OPEX sur 3 ans',
        'Années 1 à 3',
        '',
        '',
        '',
        '',
        _num(summary.cumulativeRun3Years, delimiter: delimiter),
        curCode,
      ])
      ..add(<String>[
        'Run OPEX',
        'RUN_CUMUL_5Y',
        'Cumul Run OPEX sur 5 ans',
        'Années 1 à 5',
        '',
        '',
        '',
        '',
        _num(summary.cumulativeRun5Years, delimiter: delimiter),
        curCode,
      ])
      ..add(<String>[
        'TCO Global',
        'TCO_1Y',
        'TCO 1 an (Build Cible + Risques EMV + Run 1 an)',
        'Horizon 12 mois',
        _num(summary.fullLot.classicTotalDays, delimiter: delimiter),
        _num(summary.fullLot.effectiveTotalDays, delimiter: delimiter),
        '',
        '',
        _num(summary.tco1Year, delimiter: delimiter),
        curCode,
      ])
      ..add(<String>[
        'TCO Global',
        'TCO_3Y',
        'TCO 3 ans (Build Cible + Risques EMV + Run 3 ans)',
        'Horizon 36 mois',
        _num(summary.fullLot.classicTotalDays, delimiter: delimiter),
        _num(summary.fullLot.effectiveTotalDays, delimiter: delimiter),
        '',
        '',
        _num(summary.tco3Years, delimiter: delimiter),
        curCode,
      ])
      ..add(<String>[
        'TCO Global',
        'TCO_5Y',
        'TCO 5 ans (Build Cible + Risques EMV + Run 5 ans)',
        'Horizon 60 mois',
        _num(summary.fullLot.classicTotalDays, delimiter: delimiter),
        _num(summary.fullLot.effectiveTotalDays, delimiter: delimiter),
        '',
        '',
        _num(summary.tco5Years, delimiter: delimiter),
        curCode,
      ]);

    return _encodeCsv(rows, includeBom: includeBom, delimiter: delimiter);
  }

  /// Génère l'ensemble des 3 fichiers CSV budgétaires (`nom_fichier.csv` -> contenu UTF-8).
  static Map<String, String> exportAllFiles(
    SpecForgeProject project, {
    bool includeBom = true,
    String delimiter = ';',
  }) => Map<String, String>.unmodifiable(<String, String>{
    'cost_summary_tco.csv': exportSummaryAndTcoCsv(
      project,
      includeBom: includeBom,
      delimiter: delimiter,
    ),
    'cost_build_wbs.csv': exportWbsCsv(
      project,
      includeBom: includeBom,
      delimiter: delimiter,
    ),
    'cost_run_opex.csv': exportRunCsv(
      project,
      includeBom: includeBom,
      delimiter: delimiter,
    ),
  });

  static String _encodeCsv(
    List<List<String>> rows, {
    required bool includeBom,
    required String delimiter,
  }) {
    final buf = StringBuffer();
    if (includeBom) {
      buf.write(_utf8Bom);
    }
    for (final row in rows) {
      for (var i = 0; i < row.length; i++) {
        if (i > 0) buf.write(delimiter);
        buf.write(_escapeCell(row[i], delimiter));
      }
      buf.write('\n');
    }
    return buf.toString();
  }

  static String _escapeCell(String raw, String delimiter) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final mustQuote =
        normalized.contains(delimiter) ||
        normalized.contains('"') ||
        normalized.contains('\n');
    if (!mustQuote) return normalized;
    return '"${normalized.replaceAll('"', '""')}"';
  }

  static String _num(double value, {required String delimiter}) {
    if (!value.isFinite) return '0';
    final rounded = (value * 100.0).round() / 100.0;
    final formatted = (rounded - rounded.roundToDouble()).abs() < 1e-6
        ? '${rounded.round()}'
        : rounded.toStringAsFixed(2);
    return delimiter == ';' ? formatted.replaceAll('.', ',') : formatted;
  }
}
