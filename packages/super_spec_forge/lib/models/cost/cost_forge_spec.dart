/// Modèle agrégé immuable du volet FinOps & Chiffrage en 4 étapes ([CostForgeSpec]).
library;

import 'package:flutter/foundation.dart';

import '../enterprise_rate_card.dart';
import '../spec_forge_stage.dart';
import 'cost_coherence_issue.dart';
import 'cost_forge_stage.dart';
import 'cost_risk_item_spec.dart';
import 'cost_run_item_spec.dart';
import 'cost_wbs_item_spec.dart';

/// Spécification financière complète d'un projet (hypothèses TJM, Build WBS CAPEX, Run OPEX, risques EMV et TCO).
@immutable
class CostForgeSpec {
  /// Construit une spécification de chiffrage immuable normalisée sur les 4 étapes de [CostForgeStage].
  CostForgeSpec({
    this.currentStage = CostForgeStage.rateCardAssumptions,
    this.currency = CostCurrency.eur,
    this.hoursPerDay = 7.5,
    this.deliveryMode = CostDeliveryMode.hybrid,
    this.targetUsersCount = 100,
    List<CostProfileRate> profiles = CostProfileRate.defaults,
    List<TShirtEffortPreset> tshirtPresets = TShirtEffortPreset.defaults,
    this.transverseRatios = TransverseRatioSettings.defaults,
    this.aiProductivity = AiProductivitySettings.defaults,
    this.assumptionsNotes = '',
    List<CostWbsItemSpec> wbsItems = const <CostWbsItemSpec>[],
    List<CostRunItemSpec> runItems = const <CostRunItemSpec>[],
    List<CostRiskItemSpec> riskItems = const <CostRiskItemSpec>[],
    Map<CostForgeStage, CostStageState>? stageStates,
    List<CostCoherenceIssue> coherenceIssues = const <CostCoherenceIssue>[],
  }) : profiles = List<CostProfileRate>.unmodifiable(profiles),
       tshirtPresets = List<TShirtEffortPreset>.unmodifiable(tshirtPresets),
       wbsItems = List<CostWbsItemSpec>.unmodifiable(wbsItems),
       runItems = List<CostRunItemSpec>.unmodifiable(runItems),
       riskItems = List<CostRiskItemSpec>.unmodifiable(riskItems),
       stageStates = Map<CostForgeStage, CostStageState>.unmodifiable(
         _normalizeStageStates(stageStates),
       ),
       coherenceIssues = List<CostCoherenceIssue>.unmodifiable(coherenceIssues);

  /// Spécification de chiffrage vide initiale.
  static final CostForgeSpec empty = CostForgeSpec();

  /// Étape actuellement sélectionnée dans le wizard de chiffrage.
  final CostForgeStage currentStage;

  /// Devise monétaire du chiffrage projet.
  final CostCurrency currency;

  /// Nombre d'heures ouvrées par jour/homme (`7.5` par défaut).
  final double hoursPerDay;

  /// Mode contractuel de réalisation retenu pour ce projet.
  final CostDeliveryMode deliveryMode;

  /// Volumétrie cible d'utilisateurs actifs servant au dimensionnement Run/TCO (`100` par défaut).
  final int targetUsersCount;

  /// Grille des profils TJM propres au projet.
  final List<CostProfileRate> profiles;

  /// Calibrages PERT par taille T-shirt propres au projet.
  final List<TShirtEffortPreset> tshirtPresets;

  /// Ratios forfaitaires transverses et provision d'aléas Build.
  final TransverseRatioSettings transverseRatios;

  /// Paramètres d'accélération d'ingénierie assistée par IA.
  final AiProductivitySettings aiProductivity;

  /// Hypothèses générales, périmètre contractuel et exclusions budgétaires.
  final String assumptionsNotes;

  /// Livrable de l'étape 2 : postes de travaux Build (CAPEX / WBS).
  final List<CostWbsItemSpec> wbsItems;

  /// Livrable de l'étape 3 : postes récurrents d'exploitation (OPEX / Run).
  final List<CostRunItemSpec> runItems;

  /// Livrable de l'étape 4 : registre des risques valorisés en EMV.
  final List<CostRiskItemSpec> riskItems;

  /// Historique conversationnel et statut de chacune des 4 étapes FinOps.
  final Map<CostForgeStage, CostStageState> stageStates;

  /// Diagnostics de cohérence financière relevés (locaux et/ou IA).
  final List<CostCoherenceIssue> coherenceIssues;

  /// Vrai si au moins une hypothèse tarifaire ou méthodologique diffère de [empty].
  bool get hasCustomAssumptions =>
      currency != CostCurrency.eur ||
      hoursPerDay != 7.5 ||
      deliveryMode != CostDeliveryMode.hybrid ||
      targetUsersCount != 100 ||
      !listEquals(profiles, CostProfileRate.defaults) ||
      !listEquals(tshirtPresets, TShirtEffortPreset.defaults) ||
      transverseRatios != TransverseRatioSettings.defaults ||
      aiProductivity != AiProductivitySettings.defaults ||
      assumptionsNotes.isNotEmpty;

  /// Vrai uniquement si un livrable, une hypothèse personnalisée, un changement d'étape ou un échange existe.
  bool get hasContent =>
      wbsItems.isNotEmpty ||
      runItems.isNotEmpty ||
      riskItems.isNotEmpty ||
      coherenceIssues.isNotEmpty ||
      hasCustomAssumptions ||
      currentStage != CostForgeStage.rateCardAssumptions ||
      stageStates.values.any(
        (s) =>
            s.messages.isNotEmpty ||
            s.status != SpecStageStatus.notStarted ||
            s.stageSummary.trim().isNotEmpty,
      );

  /// Retourne l'état d'une étape de chiffrage donnée (garanti non nul).
  CostStageState stageStateFor(CostForgeStage stage) =>
      stageStates[stage] ?? CostStageState(stage: stage);

  /// Retourne une copie avec l'état d'une étape de chiffrage mis à jour.
  CostForgeSpec withStageState(CostStageState nextState) {
    final nextMap = Map<CostForgeStage, CostStageState>.from(stageStates)
      ..[nextState.stage] = nextState;
    return copyWith(stageStates: nextMap);
  }

  /// Retourne une copie positionnée sur [targetStage] en validant optionnellement l'étape courante.
  CostForgeSpec moveToStage(
    CostForgeStage targetStage, {
    bool validateCurrentStage = false,
  }) {
    final nextMap = Map<CostForgeStage, CostStageState>.from(stageStates);
    if (validateCurrentStage && currentStage != targetStage) {
      final current = stageStateFor(currentStage);
      nextMap[currentStage] = current.copyWith(
        status: SpecStageStatus.validated,
      );
    }
    final target = nextMap[targetStage] ?? CostStageState(stage: targetStage);
    if (target.status == SpecStageStatus.notStarted) {
      nextMap[targetStage] = target.copyWith(
        status: SpecStageStatus.inProgress,
      );
    }
    return copyWith(currentStage: targetStage, stageStates: nextMap);
  }

  /// Recherche un profil TJM par identifiant, code `PRF-xxx` ou nom (insensible à la casse).
  CostProfileRate? findProfile(String idOrCodeOrName) {
    final needle = idOrCodeOrName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final profile in profiles) {
      if (profile.id.toLowerCase() == needle ||
          (profile.code.isNotEmpty && profile.code.toLowerCase() == needle)) {
        return profile;
      }
    }
    for (final profile in profiles) {
      if (profile.name.toLowerCase() == needle) return profile;
    }
    return null;
  }

  /// Résout le profil TJM associé à [discipline] (premier profil correspondant, sinon premier profil disponible, sinon défaut).
  CostProfileRate resolveProfileForDiscipline(CostDiscipline discipline) {
    for (final profile in profiles) {
      if (profile.discipline == discipline) return profile;
    }
    if (profiles.isNotEmpty) return profiles.first;
    return CostProfileRate.defaults.first;
  }

  /// Retourne le calibre PERT correspondant à [size] (repli sur [TShirtEffortPreset.defaults] puis `M`).
  TShirtEffortPreset presetFor(CostTShirtSize size) {
    final target = size == CostTShirtSize.custom ? CostTShirtSize.m : size;
    for (final preset in tshirtPresets) {
      if (preset.size == target) return preset;
    }
    for (final preset in TShirtEffortPreset.defaults) {
      if (preset.size == target) return preset;
    }
    return TShirtEffortPreset.defaults[2];
  }

  /// Recherche un lot WBS par identifiant, code `WBS-xxx` ou titre (insensible à la casse).
  CostWbsItemSpec? findWbsItem(String idOrCodeOrTitle) {
    final needle = idOrCodeOrTitle.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final item in wbsItems) {
      if (item.id.toLowerCase() == needle ||
          (item.code.isNotEmpty && item.code.toLowerCase() == needle)) {
        return item;
      }
    }
    for (final item in wbsItems) {
      if (item.title.toLowerCase() == needle) return item;
    }
    return null;
  }

  /// Recherche un poste Run par identifiant, code `RUN-xxx` ou nom (insensible à la casse).
  CostRunItemSpec? findRunItem(String idOrCodeOrName) {
    final needle = idOrCodeOrName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final item in runItems) {
      if (item.id.toLowerCase() == needle ||
          (item.code.isNotEmpty && item.code.toLowerCase() == needle)) {
        return item;
      }
    }
    for (final item in runItems) {
      if (item.name.toLowerCase() == needle) return item;
    }
    return null;
  }

  /// Recherche un risque budgétaire par identifiant, code `RSK-xxx` ou titre (insensible à la casse).
  CostRiskItemSpec? findRiskItem(String idOrCodeOrTitle) {
    final needle = idOrCodeOrTitle.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final item in riskItems) {
      if (item.id.toLowerCase() == needle ||
          (item.code.isNotEmpty && item.code.toLowerCase() == needle)) {
        return item;
      }
    }
    for (final item in riskItems) {
      if (item.title.toLowerCase() == needle) return item;
    }
    return null;
  }

  /// Applique une [EnterpriseRateCard] au projet et réaligne les profils/calibres T-shirt des lots existants.
  CostForgeSpec applyEnterpriseRateCard(EnterpriseRateCard card) {
    final updatedWbs = <CostWbsItemSpec>[
      for (final item in wbsItems)
        () {
          final resolvedProfileId =
              card.findProfile(item.profileId)?.id ??
              card.resolveProfileForDiscipline(item.discipline).id;
          final reprofiled = item.copyWith(profileId: resolvedProfileId);
          return reprofiled.tshirtSize == CostTShirtSize.custom
              ? reprofiled
              : reprofiled.withTShirtPreset(
                  card.presetFor(reprofiled.tshirtSize),
                );
        }(),
    ];
    final updatedRisks = <CostRiskItemSpec>[
      for (final risk in riskItems)
        card.findProfile(risk.profileId) != null
            ? risk
            : risk.copyWith(
                profileId: card
                    .resolveProfileForDiscipline(CostDiscipline.backend)
                    .id,
              ),
    ];
    return copyWith(
      currency: card.currency,
      hoursPerDay: card.hoursPerDay,
      deliveryMode: card.defaultDeliveryMode,
      profiles: card.profiles,
      tshirtPresets: card.tshirtPresets,
      transverseRatios: card.transverseRatios,
      aiProductivity: card.aiProductivity,
      assumptionsNotes: assumptionsNotes.isEmpty
          ? card.notes
          : assumptionsNotes,
      wbsItems: updatedWbs,
      riskItems: updatedRisks,
    );
  }

  /// Extrait les hypothèses tarifaires du projet sous forme d'[EnterpriseRateCard].
  EnterpriseRateCard toEnterpriseRateCard() => EnterpriseRateCard(
    currency: currency,
    hoursPerDay: hoursPerDay,
    defaultDeliveryMode: deliveryMode,
    profiles: profiles,
    tshirtPresets: tshirtPresets,
    transverseRatios: transverseRatios,
    aiProductivity: aiProductivity,
    notes: assumptionsNotes,
  );

  /// Vérifie les invariants structurels et financiers de l'ensemble de la spécification Coûts.
  void validate() {
    if (!hoursPerDay.isFinite || hoursPerDay <= 0.0 || hoursPerDay > 24.0) {
      throw const FormatException(
        'CostForgeSpec.hoursPerDay doit être compris dans ]0, 24].',
      );
    }
    if (targetUsersCount < 1) {
      throw const FormatException(
        'CostForgeSpec.targetUsersCount doit être supérieur ou égal à 1.',
      );
    }

    final profileIds = <String>{};
    for (final profile in profiles) {
      profile.validate();
      if (!profileIds.add(profile.id)) {
        throw FormatException('Profil TJM dupliqué : ${profile.id}');
      }
    }

    final presetSizes = <CostTShirtSize>{};
    for (final preset in tshirtPresets) {
      preset.validate();
      if (!presetSizes.add(preset.size)) {
        throw FormatException(
          'Calibre T-shirt dupliqué : ${preset.size.code}',
        );
      }
    }

    transverseRatios.validate();
    aiProductivity.validate();

    final wbsIds = <String>{};
    for (final item in wbsItems) {
      item.validate();
      if (!wbsIds.add(item.id)) {
        throw FormatException('Lot WBS dupliqué : ${item.id}');
      }
    }

    final runIds = <String>{};
    for (final item in runItems) {
      item.validate();
      if (!runIds.add(item.id)) {
        throw FormatException('Poste Run dupliqué : ${item.id}');
      }
    }

    final riskIds = <String>{};
    for (final item in riskItems) {
      item.validate();
      if (!riskIds.add(item.id)) {
        throw FormatException('Risque budgétaire dupliqué : ${item.id}');
      }
    }

    for (final state in stageStates.values) {
      state.validate();
    }

    final issueIds = <String>{};
    for (final issue in coherenceIssues) {
      issue.validate();
      if (!issueIds.add(issue.id)) {
        throw FormatException(
          'Diagnostic de cohérence Coûts dupliqué : ${issue.id}',
        );
      }
    }
  }

  /// Produit un instantané JSON concis adapté à l'injection dans le prompt de [stage].
  Map<String, Object?> toCompactContextJson(CostForgeStage stage) =>
      <String, Object?>{
        'currentCostStage': stage.name,
        'currency': currency.code,
        'hoursPerDay': hoursPerDay,
        'deliveryMode': deliveryMode.name,
        'targetUsersCount': targetUsersCount,
        'profiles': [for (final p in profiles) p.toJson()],
        'tshirtPresets': [for (final t in tshirtPresets) t.toJson()],
        'transverseRatios': transverseRatios.toJson(),
        'aiProductivity': aiProductivity.toJson(),
        if (assumptionsNotes.trim().isNotEmpty)
          'assumptionsNotes': assumptionsNotes,
        if (stage.index >= CostForgeStage.buildWbs.index || wbsItems.isNotEmpty)
          'wbsItems': [for (final w in wbsItems) w.toJson()],
        if (stage.index >= CostForgeStage.runOpex.index || runItems.isNotEmpty)
          'runItems': [for (final r in runItems) r.toJson()],
        if (stage.index >= CostForgeStage.tcoReviewExport.index ||
            riskItems.isNotEmpty)
          'riskItems': [for (final r in riskItems) r.toJson()],
        if (stage == CostForgeStage.tcoReviewExport &&
            coherenceIssues.isNotEmpty)
          'coherenceIssues': [for (final i in coherenceIssues) i.toJson()],
      };

  /// Retourne une copie modifiée.
  CostForgeSpec copyWith({
    CostForgeStage? currentStage,
    CostCurrency? currency,
    double? hoursPerDay,
    CostDeliveryMode? deliveryMode,
    int? targetUsersCount,
    List<CostProfileRate>? profiles,
    List<TShirtEffortPreset>? tshirtPresets,
    TransverseRatioSettings? transverseRatios,
    AiProductivitySettings? aiProductivity,
    String? assumptionsNotes,
    List<CostWbsItemSpec>? wbsItems,
    List<CostRunItemSpec>? runItems,
    List<CostRiskItemSpec>? riskItems,
    Map<CostForgeStage, CostStageState>? stageStates,
    List<CostCoherenceIssue>? coherenceIssues,
  }) => CostForgeSpec(
    currentStage: currentStage ?? this.currentStage,
    currency: currency ?? this.currency,
    hoursPerDay: hoursPerDay ?? this.hoursPerDay,
    deliveryMode: deliveryMode ?? this.deliveryMode,
    targetUsersCount: targetUsersCount ?? this.targetUsersCount,
    profiles: profiles ?? this.profiles,
    tshirtPresets: tshirtPresets ?? this.tshirtPresets,
    transverseRatios: transverseRatios ?? this.transverseRatios,
    aiProductivity: aiProductivity ?? this.aiProductivity,
    assumptionsNotes: assumptionsNotes ?? this.assumptionsNotes,
    wbsItems: wbsItems ?? this.wbsItems,
    runItems: runItems ?? this.runItems,
    riskItems: riskItems ?? this.riskItems,
    stageStates: stageStates ?? this.stageStates,
    coherenceIssues: coherenceIssues ?? this.coherenceIssues,
  );

  /// Sérialise la spécification Coûts complète en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'currentStage': currentStage.name,
    'currency': currency.name,
    'hoursPerDay': hoursPerDay,
    'deliveryMode': deliveryMode.name,
    'targetUsersCount': targetUsersCount,
    'profiles': [for (final p in profiles) p.toJson()],
    'tshirtPresets': [for (final t in tshirtPresets) t.toJson()],
    'transverseRatios': transverseRatios.toJson(),
    'aiProductivity': aiProductivity.toJson(),
    'assumptionsNotes': assumptionsNotes,
    'wbsItems': [for (final w in wbsItems) w.toJson()],
    'runItems': [for (final r in runItems) r.toJson()],
    'riskItems': [for (final r in riskItems) r.toJson()],
    'stageStates': <String, Object?>{
      for (final entry in stageStates.entries)
        entry.key.name: entry.value.toJson(),
    },
    'coherenceIssues': [for (final i in coherenceIssues) i.toJson()],
  };

  /// Désérialise une spécification Coûts depuis JSON (retourne [empty] si `raw == null`).
  factory CostForgeSpec.fromJson(Object? raw) {
    if (raw == null) return CostForgeSpec.empty;
    if (raw is! Map) {
      throw const FormatException('CostForgeSpec doit être un objet JSON.');
    }

    List<CostProfileRate> parsedProfiles = CostProfileRate.defaults;
    if (raw['profiles'] is List) {
      final list = <CostProfileRate>[];
      final seenProfileIds = <String>{};
      for (final item in raw['profiles'] as List) {
        var profile = CostProfileRate.fromJson(item);
        if (!seenProfileIds.add(profile.id)) {
          var suffix = 2;
          while (!seenProfileIds.add('${profile.id}_$suffix')) {
            suffix++;
          }
          profile = profile.copyWith(id: '${profile.id}_$suffix');
        }
        list.add(profile);
      }
      parsedProfiles = list;
    }

    List<TShirtEffortPreset> parsedPresets = TShirtEffortPreset.defaults;
    if (raw['tshirtPresets'] is List) {
      final list = <TShirtEffortPreset>[];
      final seenSizes = <CostTShirtSize>{};
      for (final item in raw['tshirtPresets'] as List) {
        final preset = TShirtEffortPreset.fromJson(item);
        if (seenSizes.add(preset.size)) {
          list.add(preset);
        }
      }
      parsedPresets = list;
    }

    final parsedWbs = <CostWbsItemSpec>[];
    final seenWbsIds = <String>{};
    if (raw['wbsItems'] is List) {
      for (final item in raw['wbsItems'] as List) {
        var wbs = CostWbsItemSpec.fromJson(item);
        if (!seenWbsIds.add(wbs.id)) {
          var suffix = 2;
          while (!seenWbsIds.add('${wbs.id}_$suffix')) {
            suffix++;
          }
          wbs = wbs.copyWith(id: '${wbs.id}_$suffix');
        }
        parsedWbs.add(wbs);
      }
    }

    final parsedRun = <CostRunItemSpec>[];
    final seenRunIds = <String>{};
    if (raw['runItems'] is List) {
      for (final item in raw['runItems'] as List) {
        var run = CostRunItemSpec.fromJson(item);
        if (!seenRunIds.add(run.id)) {
          var suffix = 2;
          while (!seenRunIds.add('${run.id}_$suffix')) {
            suffix++;
          }
          run = run.copyWith(id: '${run.id}_$suffix');
        }
        parsedRun.add(run);
      }
    }

    final parsedRisks = <CostRiskItemSpec>[];
    final seenRiskIds = <String>{};
    if (raw['riskItems'] is List) {
      for (final item in raw['riskItems'] as List) {
        var risk = CostRiskItemSpec.fromJson(item);
        if (!seenRiskIds.add(risk.id)) {
          var suffix = 2;
          while (!seenRiskIds.add('${risk.id}_$suffix')) {
            suffix++;
          }
          risk = risk.copyWith(id: '${risk.id}_$suffix');
        }
        parsedRisks.add(risk);
      }
    }

    final rawStageStates = raw['stageStates'];
    final parsedStageStates = <CostForgeStage, CostStageState>{};
    if (rawStageStates is Map) {
      for (final stage in CostForgeStage.values) {
        final rawStage = rawStageStates[stage.name];
        if (rawStage != null) {
          parsedStageStates[stage] = CostStageState.fromJson(
            rawStage,
            fallbackStage: stage,
          );
        }
      }
    }

    final parsedIssues = <CostCoherenceIssue>[];
    final seenIssueIds = <String>{};
    if (raw['coherenceIssues'] is List) {
      for (final item in raw['coherenceIssues'] as List) {
        var issue = CostCoherenceIssue.fromJson(item);
        if (!seenIssueIds.add(issue.id)) {
          var suffix = 2;
          while (!seenIssueIds.add('${issue.id}_$suffix')) {
            suffix++;
          }
          issue = issue.copyWith(id: '${issue.id}_$suffix');
        }
        parsedIssues.add(issue);
      }
    }

    final spec = CostForgeSpec(
      currentStage: CostForgeStage.fromJson(raw['currentStage']),
      currency: CostCurrency.fromJson(raw['currency']),
      hoursPerDay: _clampedDouble(raw['hoursPerDay'], 7.5, 0.5, 24.0),
      deliveryMode: CostDeliveryMode.fromJson(raw['deliveryMode']),
      targetUsersCount: _positiveInt(raw['targetUsersCount'], 100),
      profiles: parsedProfiles,
      tshirtPresets: parsedPresets,
      transverseRatios: TransverseRatioSettings.fromJson(
        raw['transverseRatios'],
      ),
      aiProductivity: AiProductivitySettings.fromJson(raw['aiProductivity']),
      assumptionsNotes: (raw['assumptionsNotes'] as String?) ?? '',
      wbsItems: parsedWbs,
      runItems: parsedRun,
      riskItems: parsedRisks,
      stageStates: parsedStageStates,
      coherenceIssues: parsedIssues,
    );
    spec.validate();
    return spec;
  }

  static Map<CostForgeStage, CostStageState> _normalizeStageStates(
    Map<CostForgeStage, CostStageState>? source,
  ) => <CostForgeStage, CostStageState>{
    for (final stage in CostForgeStage.values)
      stage: source?[stage] ?? CostStageState(stage: stage),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostForgeSpec &&
          other.currentStage == currentStage &&
          other.currency == currency &&
          other.hoursPerDay == hoursPerDay &&
          other.deliveryMode == deliveryMode &&
          other.targetUsersCount == targetUsersCount &&
          listEquals(other.profiles, profiles) &&
          listEquals(other.tshirtPresets, tshirtPresets) &&
          other.transverseRatios == transverseRatios &&
          other.aiProductivity == aiProductivity &&
          other.assumptionsNotes == assumptionsNotes &&
          listEquals(other.wbsItems, wbsItems) &&
          listEquals(other.runItems, runItems) &&
          listEquals(other.riskItems, riskItems) &&
          mapEquals(other.stageStates, stageStates) &&
          listEquals(other.coherenceIssues, coherenceIssues);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    currentStage,
    currency,
    hoursPerDay,
    deliveryMode,
    targetUsersCount,
    Object.hashAll(profiles),
    Object.hashAll(tshirtPresets),
    transverseRatios,
    aiProductivity,
    assumptionsNotes,
    Object.hashAll(wbsItems),
    Object.hashAll(runItems),
    Object.hashAll(riskItems),
    Object.hashAll(stageStates.values),
    Object.hashAll(coherenceIssues),
  ]);
}

double _clampedDouble(Object? raw, double fallback, double min, double max) {
  double? parsed;
  if (raw is num) {
    final value = raw.toDouble();
    if (value.isFinite) parsed = value;
  } else if (raw is String) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value != null && value.isFinite) parsed = value;
  }
  if (parsed == null) return fallback;
  if (parsed < min) return min;
  if (parsed > max) return max;
  return parsed;
}

int _positiveInt(Object? raw, int fallback) {
  int? parsed;
  if (raw is int) {
    parsed = raw;
  } else if (raw is num && raw.isFinite) {
    parsed = raw.round();
  } else if (raw is String) {
    parsed = int.tryParse(raw.trim());
  }
  if (parsed == null) return fallback;
  return parsed < 1 ? 1 : parsed;
}
