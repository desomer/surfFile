/// Modèle immuable d'un lot de travaux Build WBS ([CostWbsItemSpec]) estimé par T-shirt, charge directe ou PERT 3 points et rattaché aux artefacts métier, UX et QA.
library;

import 'package:flutter/foundation.dart';

import '../enterprise_rate_card.dart';
import '../spec_cahier_des_charges.dart';

/// Élément de la Work Breakdown Structure (CAPEX / Build) traçable vers les spécifications Métier, UX et QA.
@immutable
class CostWbsItemSpec {
  /// Construit un lot WBS immuable.
  CostWbsItemSpec({
    required this.id,
    this.code = 'WBS-001',
    required this.title,
    this.description = '',
    this.discipline = CostDiscipline.backend,
    this.priority = RequirementPriority.must,
    this.profileId = 'prof_back',
    this.tshirtSize = CostTShirtSize.m,
    this.optimisticDays = 3.0,
    this.mostLikelyDays = 5.0,
    this.pessimisticDays = 8.0,
    this.aiEligible = true,
    this.moduleId = '',
    List<String> requirementIds = const <String>[],
    List<String> businessObjectIds = const <String>[],
    List<String> uxScreenIds = const <String>[],
    List<String> qaFeatureIds = const <String>[],
    List<String> tddSuiteIds = const <String>[],
    this.origin = 'manual',
  }) : requirementIds = List<String>.unmodifiable(requirementIds),
       businessObjectIds = List<String>.unmodifiable(businessObjectIds),
       uxScreenIds = List<String>.unmodifiable(uxScreenIds),
       qaFeatureIds = List<String>.unmodifiable(qaFeatureIds),
       tddSuiteIds = List<String>.unmodifiable(tddSuiteIds);

  /// Identifiant technique unique du poste WBS.
  final String id;

  /// Code lisible du lot WBS (ex. `WBS-001`).
  final String code;

  /// Intitulé synthétique de la tâche ou du lot de réalisation.
  final String title;

  /// Hypothèses techniques, périmètre inclus et livrables attendus.
  final String description;

  /// Discipline d'ingénierie principale du lot.
  final CostDiscipline discipline;

  /// Priorité MoSCoW déterminant le lotissement MVP / Cible.
  final RequirementPriority priority;

  /// Identifiant du profil tarifaire ([CostProfileRate.id]) réalisant le lot.
  final String profileId;

  /// Calibre T-shirt retenu ou [CostTShirtSize.custom] en saisie libre.
  final CostTShirtSize tshirtSize;

  /// Charge optimiste `O` en jours/homme (`>= 0`).
  final double optimisticDays;

  /// Charge nominale `M` en jours/homme (`>= optimisticDays`).
  final double mostLikelyDays;

  /// Charge pessimiste `P` en jours/homme (`>= mostLikelyDays`).
  final double pessimisticDays;

  /// Indique si ce lot bénéficie de l'accélération d'ingénierie assistée par IA.
  final bool aiEligible;

  /// Identifiant optionnel du module fonctionnel ([SpecModule.id]) de rattachement.
  final String moduleId;

  /// Identifiants ou codes des exigences fonctionnelles (`EF-xxx`) couvertes.
  final List<String> requirementIds;

  /// Identifiants des objets métiers (`BusinessObjectSpec.id`) implémentés.
  final List<String> businessObjectIds;

  /// Identifiants ou codes des écrans UX (`SCR-xxx`) réalisés.
  final List<String> uxScreenIds;

  /// Identifiants ou codes des features Gherkin (`FEAT-xxx`) automatisées.
  final List<String> qaFeatureIds;

  /// Identifiants ou codes des suites TDD (`TDD-xxx`) couvertes.
  final List<String> tddSuiteIds;

  /// Origine de création du lot (`'manual'`, `'seed'`, `'ai'`).
  final String origin;

  /// Vrai lorsque le lot est chiffré en charge directe fixe (`O == M == P` à `1e-6` près).
  bool get isDirectDays => (pessimisticDays - optimisticDays).abs() < 1e-6;

  /// Charge espérée PERT `(O + 4M + P) / 6` en jours/homme.
  double get expectedDays =>
      (optimisticDays + 4.0 * mostLikelyDays + pessimisticDays) / 6.0;

  /// Écart-type PERT `(P - O) / 6` en jours/homme.
  double get stdDevDays => (pessimisticDays - optimisticDays) / 6.0;

  /// Variance statistique `((P - O) / 6)²` utilisée pour l'agrégation P80 du portefeuille WBS.
  double get varianceDays => stdDevDays * stdDevDays;

  /// Retourne une copie configurée en charge fixe directe (`O = M = P = days` et calibre [CostTShirtSize.custom]).
  CostWbsItemSpec withDirectDays(double days) {
    final clamped = days.isFinite && days > 0.0 ? days : 0.0;
    return copyWith(
      tshirtSize: CostTShirtSize.custom,
      optimisticDays: clamped,
      mostLikelyDays: clamped,
      pessimisticDays: clamped,
    );
  }

  /// Retourne une copie appliquant les bornes PERT d'un [preset] T-shirt.
  CostWbsItemSpec withTShirtPreset(TShirtEffortPreset preset) => copyWith(
    tshirtSize: preset.size,
    optimisticDays: preset.optimisticDays,
    mostLikelyDays: preset.mostLikelyDays,
    pessimisticDays: preset.pessimisticDays,
  );

  /// Vérifie les invariants structurels et statistiques (`0 <= O <= M <= P`) du lot WBS.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('CostWbsItemSpec.id ne peut pas être vide.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'CostWbsItemSpec.title ne peut pas être vide.',
      );
    }
    if (!optimisticDays.isFinite || optimisticDays < 0.0) {
      throw const FormatException(
        'CostWbsItemSpec.optimisticDays doit être supérieur ou égal à 0.',
      );
    }
    if (!mostLikelyDays.isFinite || mostLikelyDays < optimisticDays) {
      throw const FormatException(
        'CostWbsItemSpec.mostLikelyDays doit être supérieur ou égal à optimisticDays.',
      );
    }
    if (!pessimisticDays.isFinite || pessimisticDays < mostLikelyDays) {
      throw const FormatException(
        'CostWbsItemSpec.pessimisticDays doit être supérieur ou égal à mostLikelyDays.',
      );
    }
  }

  /// Retourne une copie modifiée.
  CostWbsItemSpec copyWith({
    String? id,
    String? code,
    String? title,
    String? description,
    CostDiscipline? discipline,
    RequirementPriority? priority,
    String? profileId,
    CostTShirtSize? tshirtSize,
    double? optimisticDays,
    double? mostLikelyDays,
    double? pessimisticDays,
    bool? aiEligible,
    String? moduleId,
    List<String>? requirementIds,
    List<String>? businessObjectIds,
    List<String>? uxScreenIds,
    List<String>? qaFeatureIds,
    List<String>? tddSuiteIds,
    String? origin,
  }) => CostWbsItemSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    title: title ?? this.title,
    description: description ?? this.description,
    discipline: discipline ?? this.discipline,
    priority: priority ?? this.priority,
    profileId: profileId ?? this.profileId,
    tshirtSize: tshirtSize ?? this.tshirtSize,
    optimisticDays: optimisticDays ?? this.optimisticDays,
    mostLikelyDays: mostLikelyDays ?? this.mostLikelyDays,
    pessimisticDays: pessimisticDays ?? this.pessimisticDays,
    aiEligible: aiEligible ?? this.aiEligible,
    moduleId: moduleId ?? this.moduleId,
    requirementIds: requirementIds ?? this.requirementIds,
    businessObjectIds: businessObjectIds ?? this.businessObjectIds,
    uxScreenIds: uxScreenIds ?? this.uxScreenIds,
    qaFeatureIds: qaFeatureIds ?? this.qaFeatureIds,
    tddSuiteIds: tddSuiteIds ?? this.tddSuiteIds,
    origin: origin ?? this.origin,
  );

  /// Sérialise le lot WBS en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'title': title,
    'description': description,
    'discipline': discipline.name,
    'priority': priority.name,
    'profileId': profileId,
    'tshirtSize': tshirtSize.name,
    'optimisticDays': optimisticDays,
    'mostLikelyDays': mostLikelyDays,
    'pessimisticDays': pessimisticDays,
    'aiEligible': aiEligible,
    'moduleId': moduleId,
    'requirementIds': requirementIds,
    'businessObjectIds': businessObjectIds,
    'uxScreenIds': uxScreenIds,
    'qaFeatureIds': qaFeatureIds,
    'tddSuiteIds': tddSuiteIds,
    'origin': origin,
  };

  /// Désérialise un lot WBS depuis JSON (supporte PERT 3 points et raccourcis `days`/`directDays`/`manDays`).
  factory CostWbsItemSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('CostWbsItemSpec doit être un objet JSON.');
    }
    final rawTitle =
        (raw['title'] as String?)?.trim() ??
        (raw['name'] as String?)?.trim() ??
        (raw['label'] as String?)?.trim() ??
        '';
    final title = rawTitle.isEmpty ? 'Lot WBS sans titre' : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final discipline = CostDiscipline.fromJson(raw['discipline']);
    final priority = RequirementPriority.fromJson(raw['priority']);
    final rawProfileId = (raw['profileId'] as String?)?.trim() ?? '';
    final profileId = rawProfileId.isEmpty
        ? EnterpriseRateCard.defaults
              .resolveProfileForDiscipline(discipline)
              .id
        : rawProfileId;

    final rawSizeValue = raw['tshirtSize'] ?? raw['size'];
    final rawDirect = _tryParseDouble(
      raw['days'] ?? raw['directDays'] ?? raw['manDays'],
    );
    final rawO = _tryParseDouble(raw['optimisticDays'] ?? raw['optimistic']);
    final rawM = _tryParseDouble(
      raw['mostLikelyDays'] ?? raw['mostLikely'] ?? raw['nominalDays'],
    );
    final rawP = _tryParseDouble(raw['pessimisticDays'] ?? raw['pessimistic']);

    final CostTShirtSize tshirtSize;
    if (rawSizeValue != null) {
      tshirtSize = CostTShirtSize.fromJson(rawSizeValue);
    } else if (rawDirect != null &&
        rawO == null &&
        rawM == null &&
        rawP == null) {
      tshirtSize = CostTShirtSize.custom;
    } else {
      tshirtSize = CostTShirtSize.m;
    }

    final preset = EnterpriseRateCard.defaults.presetFor(tshirtSize);
    double o;
    double m;
    double p;
    if (rawO == null && rawM == null && rawP == null) {
      if (rawDirect != null) {
        final d = rawDirect < 0.0 ? 0.0 : rawDirect;
        o = d;
        m = d;
        p = d;
      } else {
        o = preset.optimisticDays;
        m = preset.mostLikelyDays;
        p = preset.pessimisticDays;
      }
    } else {
      final fallback = rawDirect ?? rawM ?? rawO ?? rawP ?? preset.mostLikelyDays;
      o = rawO ??
          (rawDirect ??
              (tshirtSize != CostTShirtSize.custom
                  ? preset.optimisticDays
                  : fallback));
      m = rawM ?? fallback;
      p = rawP ??
          (rawDirect ??
              (tshirtSize != CostTShirtSize.custom
                  ? preset.pessimisticDays
                  : fallback));
    }

    final normalized = <double>[
      o < 0.0 ? 0.0 : o,
      m < 0.0 ? 0.0 : m,
      p < 0.0 ? 0.0 : p,
    ]..sort();

    final rawOrigin = (raw['origin'] as String?)?.trim() ?? '';
    final item = CostWbsItemSpec(
      id: rawId.isEmpty ? 'wbs_${title.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'WBS-001' : rawCode,
      title: title,
      description: (raw['description'] as String?)?.trim() ?? '',
      discipline: discipline,
      priority: priority,
      profileId: profileId,
      tshirtSize: tshirtSize,
      optimisticDays: normalized[0],
      mostLikelyDays: normalized[1],
      pessimisticDays: normalized[2],
      aiEligible: raw['aiEligible'] is bool ? raw['aiEligible'] as bool : true,
      moduleId: (raw['moduleId'] as String?)?.trim() ?? '',
      requirementIds: _stringList(raw['requirementIds']),
      businessObjectIds: _stringList(raw['businessObjectIds']),
      uxScreenIds: _stringList(raw['uxScreenIds']),
      qaFeatureIds: _stringList(raw['qaFeatureIds']),
      tddSuiteIds: _stringList(raw['tddSuiteIds']),
      origin: rawOrigin.isEmpty ? 'manual' : rawOrigin,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostWbsItemSpec &&
          other.id == id &&
          other.code == code &&
          other.title == title &&
          other.description == description &&
          other.discipline == discipline &&
          other.priority == priority &&
          other.profileId == profileId &&
          other.tshirtSize == tshirtSize &&
          other.optimisticDays == optimisticDays &&
          other.mostLikelyDays == mostLikelyDays &&
          other.pessimisticDays == pessimisticDays &&
          other.aiEligible == aiEligible &&
          other.moduleId == moduleId &&
          listEquals(other.requirementIds, requirementIds) &&
          listEquals(other.businessObjectIds, businessObjectIds) &&
          listEquals(other.uxScreenIds, uxScreenIds) &&
          listEquals(other.qaFeatureIds, qaFeatureIds) &&
          listEquals(other.tddSuiteIds, tddSuiteIds) &&
          other.origin == origin;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    code,
    title,
    description,
    discipline,
    priority,
    profileId,
    tshirtSize,
    optimisticDays,
    mostLikelyDays,
    pessimisticDays,
    aiEligible,
    moduleId,
    Object.hashAll(requirementIds),
    Object.hashAll(businessObjectIds),
    Object.hashAll(uxScreenIds),
    Object.hashAll(qaFeatureIds),
    Object.hashAll(tddSuiteIds),
    origin,
  ]);
}

double? _tryParseDouble(Object? raw) {
  if (raw is num) {
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }
  if (raw is String) {
    final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
