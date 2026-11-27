/// Modèles immuables de découpage produit d'un projet en Initiatives ([SpecInitiative])
/// et Features ([SpecFeatureSpec]), chaque Feature portant ses propres livrables Wizards.
library;

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';

import 'business_object_spec.dart';
import 'business_rule_spec.dart';
import 'cost/cost_forge_spec.dart';
import 'event_storming_spec.dart';
import 'example_mapping_spec.dart';
import 'feature_object_sync_baseline.dart';
import 'qa/qa_forge_spec.dart';
import 'spec_cahier_des_charges.dart';
import 'spec_coherence_issue.dart';
import 'spec_forge_stage.dart';
import 'spec_stage_chat.dart';
import 'spec_vision.dart';
import 'ux/ux_forge_spec.dart';

/// Statut de cycle de vie d'une initiative ou d'une feature dans le portefeuille projet.
enum SpecPortfolioStatus {
  /// Élément identifié mais pas encore démarré dans les wizards.
  draft('À cadrer'),

  /// Spécification ou conception en cours dans les wizards.
  inProgress('En cours'),

  /// Spécification validée et prête pour le Design / Build.
  validated('Validée'),

  /// Élément écarté ou archivé.
  archived('Archivée');

  const SpecPortfolioStatus(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un [SpecPortfolioStatus] depuis une chaîne JSON.
  static SpecPortfolioStatus fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final value in SpecPortfolioStatus.values) {
        if (value.name.toLowerCase() == norm ||
            value.label.toLowerCase() == norm) {
          return value;
        }
      }
      if (norm == 'in_progress' || norm == 'in-progress') {
        return SpecPortfolioStatus.inProgress;
      }
    }
    return SpecPortfolioStatus.draft;
  }
}

/// Feature unitaire d'une [SpecInitiative] encapsulant les livrables des 4 Wizards
/// (Spec étape 1 et étapes 3..8, UX, BDD/TDD et Estimation de coût IT).
///
/// Le Lexique métier (étape 2 du wizard et référentiel transverse de niveau projet)
/// et les préférences de modélisation restent partagés à l'échelle du projet parent
/// ([SpecForgeProject]).
@immutable
class SpecFeatureSpec {
  /// Construit une feature immuable de spécification.
  SpecFeatureSpec({
    required this.id,
    this.code = '',
    required this.name,
    this.description = '',
    this.targetRelease = '',
    this.priority = RequirementPriority.must,
    this.status = SpecPortfolioStatus.draft,
    SpecForgeStage currentStage = SpecForgeStage.vision,
    Set<SpecForgeStage> disabledSpecStages = const <SpecForgeStage>{},
    SpecVision? vision,
    SpecCahierDesCharges? cahierDesCharges,
    EventStormingSpec? eventStorming,
    List<BusinessObjectSpec> businessObjects = const <BusinessObjectSpec>[],
    Map<String, FeatureObjectSyncBaseline> objectSyncBaselines =
        const <String, FeatureObjectSyncBaseline>{},
    List<ExampleMapStory> exampleMappings = const <ExampleMapStory>[],
    List<BusinessRuleSpec> businessRules = const <BusinessRuleSpec>[],
    Map<SpecForgeStage, SpecStageState>? stageStates,
    List<SpecCoherenceIssue> coherenceIssues = const <SpecCoherenceIssue>[],
    UxForgeSpec? uxSpec,
    QaForgeSpec? qaSpec,
    CostForgeSpec? costSpec,
  }) : disabledSpecStages = _normalizeDisabledSpecStages(disabledSpecStages),
       currentStage = _normalizeCurrentStage(
         currentStage,
         _normalizeDisabledSpecStages(disabledSpecStages),
       ),
       vision = vision ?? SpecVision.empty,
       cahierDesCharges = cahierDesCharges ?? SpecCahierDesCharges.empty,
       eventStorming = eventStorming ?? EventStormingSpec.empty,
       businessObjects = List<BusinessObjectSpec>.unmodifiable(businessObjects),
       objectSyncBaselines =
           Map<String, FeatureObjectSyncBaseline>.unmodifiable(
             objectSyncBaselines,
           ),
       exampleMappings = List<ExampleMapStory>.unmodifiable(exampleMappings),
       businessRules = List<BusinessRuleSpec>.unmodifiable(businessRules),
       stageStates = Map<SpecForgeStage, SpecStageState>.unmodifiable(
         _normalizeFeatureStageStates(stageStates),
       ),
       coherenceIssues = List<SpecCoherenceIssue>.unmodifiable(coherenceIssues),
       uxSpec = uxSpec ?? UxForgeSpec.empty,
       qaSpec = qaSpec ?? QaForgeSpec.empty,
       costSpec = costSpec ?? CostForgeSpec.empty;

  /// Identifiant stable de la feature initiale créée par défaut pour un projet.
  static const String defaultFeatureId = 'feat_initial';

  /// Code court par défaut de la feature initiale.
  static const String defaultFeatureCode = 'FEAT-01';

  /// Nom par défaut de la feature initiale.
  static const String defaultFeatureName = 'Feature initiale';

  /// Étapes du wizard Spec propres à chaque feature (toutes sauf l'étape 2 Lexique partagée au niveau projet).
  static const List<SpecForgeStage> featureScopedStages = <SpecForgeStage>[
    SpecForgeStage.vision,
    SpecForgeStage.specifications,
    SpecForgeStage.eventStorming,
    SpecForgeStage.businessObjects,
    SpecForgeStage.exampleMapping,
    SpecForgeStage.businessRules,
    SpecForgeStage.reviewExport,
  ];

  /// Crée une nouvelle feature vierge (pré-alimentant `vision.ideaSummary` si une description est fournie).
  factory SpecFeatureSpec.create({
    String? id,
    required String code,
    required String name,
    String description = '',
    String targetRelease = '',
    RequirementPriority priority = RequirementPriority.must,
    SpecPortfolioStatus status = SpecPortfolioStatus.draft,
    Set<SpecForgeStage> disabledSpecStages = const <SpecForgeStage>{},
  }) {
    final featureId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : 'feat_${shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}';
    final trimmedDesc = description.trim();
    return SpecFeatureSpec(
      id: featureId,
      code: code.trim(),
      name: name.trim(),
      description: trimmedDesc,
      targetRelease: targetRelease.trim(),
      priority: priority,
      status: status,
      currentStage: SpecForgeStage.vision,
      disabledSpecStages: disabledSpecStages,
      vision: trimmedDesc.isNotEmpty
          ? SpecVision(ideaSummary: trimmedDesc)
          : SpecVision.empty,
      stageStates: <SpecForgeStage, SpecStageState>{
        for (final stage in featureScopedStages)
          stage: SpecStageState(
            stage: stage,
            status: SpecStageStatus.notStarted,
          ),
      },
    );
  }

  /// Crée la feature initiale par défaut (utilisée à la création d'un projet ou lors d'une migration v1..v3).
  factory SpecFeatureSpec.createDefault({
    String initialIdea = '',
    SpecForgeStage currentStage = SpecForgeStage.vision,
    Set<SpecForgeStage> disabledSpecStages = const <SpecForgeStage>{},
    SpecVision? vision,
    SpecCahierDesCharges? cahierDesCharges,
    EventStormingSpec? eventStorming,
    List<BusinessObjectSpec> businessObjects = const <BusinessObjectSpec>[],
    Map<String, FeatureObjectSyncBaseline> objectSyncBaselines =
        const <String, FeatureObjectSyncBaseline>{},
    List<ExampleMapStory> exampleMappings = const <ExampleMapStory>[],
    List<BusinessRuleSpec> businessRules = const <BusinessRuleSpec>[],
    Map<SpecForgeStage, SpecStageState>? stageStates,
    List<SpecCoherenceIssue> coherenceIssues = const <SpecCoherenceIssue>[],
    UxForgeSpec? uxSpec,
    QaForgeSpec? qaSpec,
    CostForgeSpec? costSpec,
  }) {
    final effectiveVision =
        vision ??
        (initialIdea.trim().isNotEmpty
            ? SpecVision(ideaSummary: initialIdea.trim())
            : SpecVision.empty);
    return SpecFeatureSpec(
      id: defaultFeatureId,
      code: defaultFeatureCode,
      name: defaultFeatureName,
      currentStage: currentStage,
      disabledSpecStages: disabledSpecStages,
      vision: effectiveVision,
      cahierDesCharges: cahierDesCharges,
      eventStorming: eventStorming,
      businessObjects: businessObjects,
      objectSyncBaselines: objectSyncBaselines,
      exampleMappings: exampleMappings,
      businessRules: businessRules,
      stageStates: stageStates,
      coherenceIssues: coherenceIssues,
      uxSpec: uxSpec,
      qaSpec: qaSpec,
      costSpec: costSpec,
    );
  }

  /// Identifiant unique stable de la feature dans le projet.
  final String id;

  /// Code court métier (ex. `FEAT-01`).
  final String code;

  /// Nom fonctionnel de la feature.
  final String name;

  /// Hypothèse de valeur, résumé fonctionnel ou périmètre de la feature.
  final String description;

  /// Lot ou jalon cible optionnel (ex. `MVP`, `Lot 1`, `V2`).
  final String targetRelease;

  /// Priorité MoSCoW de la feature.
  final RequirementPriority priority;

  /// Statut déclaré de la feature dans le portefeuille.
  final SpecPortfolioStatus status;

  /// Étape courante sélectionnée dans le Wizard de spécification pour cette feature.
  final SpecForgeStage currentStage;

  /// Ensemble des étapes optionnelles (ex. Event Storming, Example Mapping)
  /// désactivées dans le Wizard de spécification pour cette feature.
  final Set<SpecForgeStage> disabledSpecStages;

  /// Vrai si [stage] est active dans le parcours de spécification de cette feature.
  bool isStageEnabled(SpecForgeStage stage) =>
      !disabledSpecStages.contains(stage);

  /// Étapes ordonnées actives dans le Wizard de spécification (incluant le Lexique partagé).
  List<SpecForgeStage> get enabledSpecStages => <SpecForgeStage>[
    for (final stage in SpecForgeStage.values)
      if (isStageEnabled(stage)) stage,
  ];

  /// Étapes actives propres à cette feature (sous-ensemble de [featureScopedStages]).
  List<SpecForgeStage> get enabledFeatureScopedStages => <SpecForgeStage>[
    for (final stage in featureScopedStages)
      if (isStageEnabled(stage)) stage,
  ];

  /// Numéro d'ordre dynamique (1-based) de [stage] dans le parcours actif de cette feature.
  int stepNumberFor(SpecForgeStage stage) {
    final idx = enabledSpecStages.indexOf(stage);
    return idx >= 0 ? idx + 1 : stage.stepNumber;
  }

  /// Étape active suivante après [stage], ou `null` s'il n'y en a aucune.
  SpecForgeStage? nextEnabledStage(SpecForgeStage stage) {
    for (var i = stage.index + 1; i < SpecForgeStage.values.length; i++) {
      final candidate = SpecForgeStage.values[i];
      if (isStageEnabled(candidate)) return candidate;
    }
    return null;
  }

  /// Étape active précédente avant [stage], ou `null` s'il n'y en a aucune.
  SpecForgeStage? previousEnabledStage(SpecForgeStage stage) {
    for (var i = stage.index - 1; i >= 0; i--) {
      final candidate = SpecForgeStage.values[i];
      if (isStageEnabled(candidate)) return candidate;
    }
    return null;
  }

  /// Livrable de l'étape 1 (Cadrage & Acteurs).
  final SpecVision vision;

  /// Livrable de l'étape 3 (Cahier des charges fonctionnel et non fonctionnel).
  final SpecCahierDesCharges cahierDesCharges;

  /// Livrable de l'étape 4 (Event Storming).
  final EventStormingSpec eventStorming;

  /// Livrable de l'étape 5 (Objets métiers).
  final List<BusinessObjectSpec> businessObjects;

  /// Empreintes de synchronisation inter-features ou depuis Design par identifiant d'objet métier (`objectId -> baseline`).
  final Map<String, FeatureObjectSyncBaseline> objectSyncBaselines;

  /// Retourne l'empreinte de synchronisation associée à [objectId], ou `null` si absente.
  FeatureObjectSyncBaseline? syncBaselineFor(String objectId) =>
      objectSyncBaselines[objectId];

  /// Livrable de l'étape 6 (Example Mapping).
  final List<ExampleMapStory> exampleMappings;

  /// Livrable de l'étape 7 (Règles de gestion).
  final List<BusinessRuleSpec> businessRules;

  /// États et conversations des étapes propres à cette feature (toutes sauf l'étape 2 Lexique).
  final Map<SpecForgeStage, SpecStageState> stageStates;

  /// Diagnostics de cohérence relevés sur cette feature.
  final List<SpecCoherenceIssue> coherenceIssues;

  /// Spécification UX propre à cette feature.
  final UxForgeSpec uxSpec;

  /// Spécification QA BDD/Gherkin & TDD propre à cette feature.
  final QaForgeSpec qaSpec;

  /// Estimation de coût IT propre à cette feature.
  final CostForgeSpec costSpec;

  /// Vrai si cette feature est la feature racine historique persistée à la racine du projet.
  bool get usesProjectRootStorage => id == defaultFeatureId;

  /// Vrai si les métadonnées de cadrage de la feature sont encore celles par défaut.
  bool get isDefaultMetadata =>
      id == defaultFeatureId &&
      code == defaultFeatureCode &&
      name == defaultFeatureName &&
      description.isEmpty &&
      targetRelease.isEmpty &&
      priority == RequirementPriority.must &&
      status == SpecPortfolioStatus.draft;

  /// Libellé combinant le code court et le nom (ex. `FEAT-01 · Paiement CB`).
  String get displayLabel => code.trim().isEmpty ? name : '${code.trim()} · $name';

  /// Vrai dès qu'au moins un livrable métier, UX, QA ou Coûts contient des données.
  bool get hasDeliverableContent =>
      vision.hasContent ||
      cahierDesCharges.hasContent ||
      eventStorming.hasContent ||
      businessObjects.isNotEmpty ||
      exampleMappings.isNotEmpty ||
      businessRules.isNotEmpty ||
      uxSpec.hasContent ||
      qaSpec.hasContent ||
      costSpec.hasContent;

  /// Vrai si cette feature est encore une coquille initiale vierge (sans livrables au-delà du rappel automatique de [projectInitialIdea]).
  bool isUntouchedPlaceholder(String projectInitialIdea) {
    if (!isDefaultMetadata) return false;
    final onlyInitialIdeaVision =
        vision == SpecVision.empty ||
        vision == SpecVision(ideaSummary: projectInitialIdea.trim());
    if (!onlyInitialIdeaVision) return false;
    if (cahierDesCharges.hasContent ||
        eventStorming.hasContent ||
        businessObjects.isNotEmpty ||
        objectSyncBaselines.isNotEmpty ||
        exampleMappings.isNotEmpty ||
        businessRules.isNotEmpty ||
        uxSpec.hasContent ||
        qaSpec.hasContent ||
        costSpec.hasContent) {
      return false;
    }
    return featureScopedStages.every((s) => stageStateFor(s).messages.isEmpty);
  }

  /// Nombre d'étapes métier propres à la feature (étapes actives parmi 2..8) validées.
  int get validatedFeatureStagesCount => [
    for (final stage in enabledFeatureScopedStages)
      if (stageStateFor(stage).status == SpecStageStatus.validated) stage,
  ].length;

  /// Statut effectif affiché (passe automatiquement en `En cours` si `draft` mais déjà travaillée).
  SpecPortfolioStatus get effectiveStatus {
    if (status != SpecPortfolioStatus.draft) return status;
    final scoped = enabledFeatureScopedStages;
    if (scoped.isNotEmpty && validatedFeatureStagesCount == scoped.length) {
      return SpecPortfolioStatus.validated;
    }
    final hasWorkedStage = scoped.any((s) {
      final st = stageStateFor(s);
      return st.messages.isNotEmpty || st.status == SpecStageStatus.validated;
    });
    if (hasWorkedStage ||
        cahierDesCharges.hasContent ||
        (isStageEnabled(SpecForgeStage.eventStorming) &&
            eventStorming.hasContent) ||
        businessObjects.isNotEmpty ||
        (isStageEnabled(SpecForgeStage.exampleMapping) &&
            exampleMappings.isNotEmpty) ||
        businessRules.isNotEmpty ||
        uxSpec.hasContent ||
        qaSpec.hasContent ||
        costSpec.hasContent) {
      return SpecPortfolioStatus.inProgress;
    }
    return SpecPortfolioStatus.draft;
  }

  /// Retourne l'état d'une étape de la feature (garanti non nul).
  SpecStageState stageStateFor(SpecForgeStage stage) =>
      stageStates[stage] ?? SpecStageState(stage: stage);

  /// Valide les invariants structurels de la feature et de tous ses livrables.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('SpecFeatureSpec.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'SpecFeatureSpec.name ne peut pas être vide.',
      );
    }
    vision.validate();
    cahierDesCharges.validate();
    eventStorming.validate();

    final objIds = <String>{};
    for (final obj in businessObjects) {
      obj.validate();
      if (!objIds.add(obj.id)) {
        throw FormatException('Objet métier dupliqué : ${obj.id}');
      }
    }

    for (final entry in objectSyncBaselines.entries) {
      if (entry.key.trim().isEmpty) {
        throw const FormatException(
          'Clé objectSyncBaselines vide dans SpecFeatureSpec.',
        );
      }
      entry.value.validate();
      if (entry.key != entry.value.objectId) {
        throw FormatException(
          'Incohérence de clé objectSyncBaselines : "${entry.key}" != "${entry.value.objectId}".',
        );
      }
    }

    final emIds = <String>{};
    for (final story in exampleMappings) {
      story.validate();
      if (!emIds.add(story.id)) {
        throw FormatException('Tableau Example Mapping dupliqué : ${story.id}');
      }
    }

    final ruleIds = <String>{};
    for (final rule in businessRules) {
      rule.validate();
      if (!ruleIds.add(rule.id)) {
        throw FormatException('Règle de gestion dupliquée : ${rule.id}');
      }
    }

    uxSpec.validate();
    qaSpec.validate();
    costSpec.validate();
  }

  /// Copie modifiée.
  SpecFeatureSpec copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    String? targetRelease,
    RequirementPriority? priority,
    SpecPortfolioStatus? status,
    SpecForgeStage? currentStage,
    Set<SpecForgeStage>? disabledSpecStages,
    SpecVision? vision,
    SpecCahierDesCharges? cahierDesCharges,
    EventStormingSpec? eventStorming,
    List<BusinessObjectSpec>? businessObjects,
    Map<String, FeatureObjectSyncBaseline>? objectSyncBaselines,
    List<ExampleMapStory>? exampleMappings,
    List<BusinessRuleSpec>? businessRules,
    Map<SpecForgeStage, SpecStageState>? stageStates,
    List<SpecCoherenceIssue>? coherenceIssues,
    UxForgeSpec? uxSpec,
    QaForgeSpec? qaSpec,
    CostForgeSpec? costSpec,
  }) => SpecFeatureSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    description: description ?? this.description,
    targetRelease: targetRelease ?? this.targetRelease,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    currentStage: currentStage ?? this.currentStage,
    disabledSpecStages: disabledSpecStages ?? this.disabledSpecStages,
    vision: vision ?? this.vision,
    cahierDesCharges: cahierDesCharges ?? this.cahierDesCharges,
    eventStorming: eventStorming ?? this.eventStorming,
    businessObjects: businessObjects ?? this.businessObjects,
    objectSyncBaselines: objectSyncBaselines ?? this.objectSyncBaselines,
    exampleMappings: exampleMappings ?? this.exampleMappings,
    businessRules: businessRules ?? this.businessRules,
    stageStates: stageStates ?? this.stageStates,
    coherenceIssues: coherenceIssues ?? this.coherenceIssues,
    uxSpec: uxSpec ?? this.uxSpec,
    qaSpec: qaSpec ?? this.qaSpec,
    costSpec: costSpec ?? this.costSpec,
  );

  /// Sérialise uniquement les métadonnées légères de la feature (pour `feature.json`).
  Map<String, Object?> toMetadataJson() => <String, Object?>{
    'id': id,
    if (code.isNotEmpty) 'code': code,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    if (targetRelease.isNotEmpty) 'targetRelease': targetRelease,
    'priority': priority.name,
    'status': status.name,
    'currentStage': currentStage.name,
    if (disabledSpecStages.isNotEmpty)
      'disabledSpecStages': [for (final s in disabledSpecStages) s.name],
  };

  /// Sérialise la feature complète (métadonnées + livrables des 4 wizards) en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    ...toMetadataJson(),
    'vision': vision.toJson(),
    'cahierDesCharges': cahierDesCharges.toJson(),
    if (eventStorming.hasContent) 'eventStorming': eventStorming.toJson(),
    'businessObjects': [for (final o in businessObjects) o.toJson()],
    if (objectSyncBaselines.isNotEmpty)
      'objectSyncBaselines': <String, Object?>{
        for (final entry in objectSyncBaselines.entries)
          entry.key: entry.value.toJson(),
      },
    if (exampleMappings.isNotEmpty)
      'exampleMappings': [for (final s in exampleMappings) s.toJson()],
    'businessRules': [for (final r in businessRules) r.toJson()],
    'stageStates': <String, Object?>{
      for (final entry in stageStates.entries)
        entry.key.name: entry.value.toJson(),
    },
    if (coherenceIssues.isNotEmpty)
      'coherenceIssues': [for (final i in coherenceIssues) i.toJson()],
    if (uxSpec.hasContent) 'uxSpec': uxSpec.toJson(),
    if (qaSpec.hasContent) 'qaSpec': qaSpec.toJson(),
    if (costSpec.hasContent) 'costSpec': costSpec.toJson(),
  };

  /// Désérialise une feature complète depuis JSON.
  factory SpecFeatureSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('SpecFeatureSpec doit être un objet JSON.');
    }
    final rawStageStates = raw['stageStates'];
    final parsedStageStates = <SpecForgeStage, SpecStageState>{};
    if (rawStageStates is Map) {
      for (final stage in featureScopedStages) {
        final rawStage = rawStageStates[stage.name];
        if (rawStage != null) {
          parsedStageStates[stage] = SpecStageState.fromJson(
            rawStage,
            fallbackStage: stage,
          );
        }
      }
    }
    final feature = SpecFeatureSpec(
      id: (raw['id'] as String?)?.trim() ?? '',
      code: (raw['code'] as String?)?.trim() ?? '',
      name: (raw['name'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
      targetRelease: (raw['targetRelease'] as String?)?.trim() ?? '',
      priority: RequirementPriority.fromJson(raw['priority']),
      status: SpecPortfolioStatus.fromJson(raw['status']),
      currentStage: SpecForgeStage.fromJson(raw['currentStage']),
      disabledSpecStages: parseDisabledSpecStages(raw['disabledSpecStages']),
      vision: SpecVision.fromJson(raw['vision']),
      cahierDesCharges: SpecCahierDesCharges.fromJson(raw['cahierDesCharges']),
      eventStorming: EventStormingSpec.fromJson(raw['eventStorming']),
      businessObjects: [
        if (raw['businessObjects'] is List)
          for (final item in raw['businessObjects'] as List)
            BusinessObjectSpec.fromJson(item),
      ],
      objectSyncBaselines: parseObjectSyncBaselines(
        raw['objectSyncBaselines'],
      ),
      exampleMappings: [
        if (raw['exampleMappings'] is List)
          for (final item in raw['exampleMappings'] as List)
            ExampleMapStory.fromJson(item),
      ],
      businessRules: [
        if (raw['businessRules'] is List)
          for (final item in raw['businessRules'] as List)
            BusinessRuleSpec.fromJson(item),
      ],
      stageStates: parsedStageStates,
      coherenceIssues: [
        if (raw['coherenceIssues'] is List)
          for (final item in raw['coherenceIssues'] as List)
            SpecCoherenceIssue.fromJson(item),
      ],
      uxSpec: UxForgeSpec.fromJson(raw['uxSpec']),
      qaSpec: QaForgeSpec.fromJson(raw['qaSpec']),
      costSpec: CostForgeSpec.fromJson(raw['costSpec']),
    );
    feature.validate();
    return feature;
  }

  /// Désérialise une table JSON d'empreintes de synchronisation d'objets métiers (`objectId -> baseline`).
  static Map<String, FeatureObjectSyncBaseline> parseObjectSyncBaselines(
    Object? raw,
  ) {
    if (raw == null) return const <String, FeatureObjectSyncBaseline>{};
    if (raw is! Map) {
      throw const FormatException(
        'objectSyncBaselines doit être un objet JSON.',
      );
    }
    if (raw.isEmpty) return const <String, FeatureObjectSyncBaseline>{};
    final parsed = <String, FeatureObjectSyncBaseline>{};
    for (final entry in raw.entries) {
      final key = '${entry.key}'.trim();
      if (key.isEmpty) {
        throw const FormatException(
          'Clé objectSyncBaselines vide dans le JSON.',
        );
      }
      parsed[key] = FeatureObjectSyncBaseline.fromJson(entry.value);
    }
    return Map<String, FeatureObjectSyncBaseline>.unmodifiable(parsed);
  }

  /// Désérialise une liste JSON de noms d'étapes optionnelles désactivées.
  static Set<SpecForgeStage> parseDisabledSpecStages(Object? raw) {
    if (raw is! Iterable) return const <SpecForgeStage>{};
    final parsed = <SpecForgeStage>{};
    for (final item in raw) {
      final stage = item is SpecForgeStage
          ? item
          : SpecForgeStage.tryFromJson(item);
      if (stage != null && stage.isOptional) {
        parsed.add(stage);
      }
    }
    return _normalizeDisabledSpecStages(parsed);
  }

  static Set<SpecForgeStage> _normalizeDisabledSpecStages(
    Set<SpecForgeStage> source,
  ) {
    if (source.isEmpty) return const <SpecForgeStage>{};
    return Set<SpecForgeStage>.unmodifiable(<SpecForgeStage>{
      for (final stage in SpecForgeStage.optionalStages)
        if (source.contains(stage)) stage,
    });
  }

  static SpecForgeStage _normalizeCurrentStage(
    SpecForgeStage stage,
    Set<SpecForgeStage> disabled,
  ) {
    if (!disabled.contains(stage)) return stage;
    for (var i = stage.index - 1; i >= 0; i--) {
      final candidate = SpecForgeStage.values[i];
      if (!disabled.contains(candidate)) return candidate;
    }
    for (var i = stage.index + 1; i < SpecForgeStage.values.length; i++) {
      final candidate = SpecForgeStage.values[i];
      if (!disabled.contains(candidate)) return candidate;
    }
    return SpecForgeStage.vision;
  }

  static Map<SpecForgeStage, SpecStageState> _normalizeFeatureStageStates(
    Map<SpecForgeStage, SpecStageState>? source,
  ) => <SpecForgeStage, SpecStageState>{
    for (final stage in featureScopedStages)
      stage: source?[stage] ?? SpecStageState(stage: stage),
  };

  /// Compare uniquement les métadonnées légères (sans les livrables des wizards).
  bool hasSameMetadata(SpecFeatureSpec other) =>
      id == other.id &&
      code == other.code &&
      name == other.name &&
      description == other.description &&
      targetRelease == other.targetRelease &&
      priority == other.priority &&
      status == other.status &&
      currentStage == other.currentStage &&
      setEquals(disabledSpecStages, other.disabledSpecStages);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecFeatureSpec &&
          hasSameMetadata(other) &&
          other.vision == vision &&
          other.cahierDesCharges == cahierDesCharges &&
          other.eventStorming == eventStorming &&
          listEquals(other.businessObjects, businessObjects) &&
          mapEquals(other.objectSyncBaselines, objectSyncBaselines) &&
          listEquals(other.exampleMappings, exampleMappings) &&
          listEquals(other.businessRules, businessRules) &&
          mapEquals(other.stageStates, stageStates) &&
          listEquals(other.coherenceIssues, coherenceIssues) &&
          other.uxSpec == uxSpec &&
          other.qaSpec == qaSpec &&
          other.costSpec == costSpec;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    code,
    name,
    description,
    targetRelease,
    priority,
    status,
    currentStage,
    Object.hashAll(disabledSpecStages),
    vision,
    cahierDesCharges,
    eventStorming,
    Object.hashAll(businessObjects),
    Object.hashAllUnordered([
      for (final e in objectSyncBaselines.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAll(exampleMappings),
    Object.hashAll(businessRules),
    Object.hashAll(stageStates.values),
    Object.hashAll(coherenceIssues),
    uxSpec,
    qaSpec,
    costSpec,
  ]);
}

/// Initiative produit regroupant un ensemble ordonné de [SpecFeatureSpec] au sein d'un projet.
@immutable
class SpecInitiative {
  /// Construit une initiative immuable.
  SpecInitiative({
    required this.id,
    this.code = '',
    required this.name,
    this.description = '',
    this.owner = '',
    this.targetTimeframe = '',
    this.priority = RequirementPriority.must,
    this.status = SpecPortfolioStatus.draft,
    List<SpecFeatureSpec> features = const <SpecFeatureSpec>[],
  }) : features = List<SpecFeatureSpec>.unmodifiable(features);

  /// Identifiant stable de l'initiative principale créée par défaut.
  static const String defaultInitiativeId = 'init_main';

  /// Code court par défaut de l'initiative principale.
  static const String defaultInitiativeCode = 'INIT-01';

  /// Nom par défaut de l'initiative principale.
  static const String defaultInitiativeName = 'Initiative principale';

  /// Crée une nouvelle initiative avec un identifiant généré si [id] est omis.
  factory SpecInitiative.create({
    String? id,
    required String code,
    required String name,
    String description = '',
    String owner = '',
    String targetTimeframe = '',
    RequirementPriority priority = RequirementPriority.must,
    SpecPortfolioStatus status = SpecPortfolioStatus.draft,
    List<SpecFeatureSpec> features = const <SpecFeatureSpec>[],
  }) {
    final initId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : 'init_${shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}';
    return SpecInitiative(
      id: initId,
      code: code.trim(),
      name: name.trim(),
      description: description.trim(),
      owner: owner.trim(),
      targetTimeframe: targetTimeframe.trim(),
      priority: priority,
      status: status,
      features: features,
    );
  }

  /// Crée l'initiative principale par défaut enveloppant [feature].
  factory SpecInitiative.createDefault({required SpecFeatureSpec feature}) =>
      SpecInitiative(
        id: defaultInitiativeId,
        code: defaultInitiativeCode,
        name: defaultInitiativeName,
        features: <SpecFeatureSpec>[feature],
      );

  /// Identifiant unique stable de l'initiative.
  final String id;

  /// Code court métier (ex. `INIT-01`).
  final String code;

  /// Intitulé de l'initiative.
  final String name;

  /// Objectif stratégique, problème métier adressé ou résultats attendus (OKR).
  final String description;

  /// Sponsor ou responsable produit optionnel.
  final String owner;

  /// Horizon ou trimestre cible optionnel (ex. `T1 2027`, `Phase 1`).
  final String targetTimeframe;

  /// Priorité MoSCoW de l'initiative.
  final RequirementPriority priority;

  /// Statut déclaré de l'initiative.
  final SpecPortfolioStatus status;

  /// Liste ordonnée des features rattachées à cette initiative.
  final List<SpecFeatureSpec> features;

  /// Vrai si les métadonnées de l'initiative sont encore celles créées par défaut.
  bool get isDefaultMetadata =>
      id == defaultInitiativeId &&
      code == defaultInitiativeCode &&
      name == defaultInitiativeName &&
      description.isEmpty &&
      owner.isEmpty &&
      targetTimeframe.isEmpty &&
      priority == RequirementPriority.must &&
      status == SpecPortfolioStatus.draft;

  /// Libellé combinant le code court et le nom (ex. `INIT-01 · Socle e-commerce`).
  String get displayLabel => code.trim().isEmpty ? name : '${code.trim()} · $name';

  /// Statut effectif agrégé de l'initiative en fonction de ses features.
  SpecPortfolioStatus get effectiveStatus {
    if (status != SpecPortfolioStatus.draft) return status;
    if (features.isEmpty) return SpecPortfolioStatus.draft;
    final allValidated = features.every(
      (f) => f.effectiveStatus == SpecPortfolioStatus.validated,
    );
    if (allValidated) return SpecPortfolioStatus.validated;
    final anyStarted = features.any(
      (f) => f.effectiveStatus != SpecPortfolioStatus.draft,
    );
    return anyStarted ? SpecPortfolioStatus.inProgress : SpecPortfolioStatus.draft;
  }

  /// Recherche une feature de cette initiative par son [featureId].
  SpecFeatureSpec? featureById(String? featureId) {
    if (featureId == null || featureId.trim().isEmpty) return null;
    for (final feature in features) {
      if (feature.id == featureId) return feature;
    }
    return null;
  }

  /// Valide l'initiative et ses features.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('SpecInitiative.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('SpecInitiative.name ne peut pas être vide.');
    }
    final featureIds = <String>{};
    for (final feature in features) {
      feature.validate();
      if (!featureIds.add(feature.id)) {
        throw FormatException('Feature dupliquée dans $id : ${feature.id}');
      }
    }
  }

  /// Copie modifiée.
  SpecInitiative copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    String? owner,
    String? targetTimeframe,
    RequirementPriority? priority,
    SpecPortfolioStatus? status,
    List<SpecFeatureSpec>? features,
  }) => SpecInitiative(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    description: description ?? this.description,
    owner: owner ?? this.owner,
    targetTimeframe: targetTimeframe ?? this.targetTimeframe,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    features: features ?? this.features,
  );

  /// Compare uniquement les métadonnées légères de l'initiative (hors liste de features).
  bool hasSameMetadata(SpecInitiative other) =>
      id == other.id &&
      code == other.code &&
      name == other.name &&
      description == other.description &&
      owner == other.owner &&
      targetTimeframe == other.targetTimeframe &&
      priority == other.priority &&
      status == other.status;

  /// Sérialise uniquement les métadonnées de l'initiative (pour `initiative.json`).
  Map<String, Object?> toMetadataJson() => <String, Object?>{
    'id': id,
    if (code.isNotEmpty) 'code': code,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    if (owner.isNotEmpty) 'owner': owner,
    if (targetTimeframe.isNotEmpty) 'targetTimeframe': targetTimeframe,
    'priority': priority.name,
    'status': status.name,
  };

  /// Sérialise l'initiative et ses features en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    ...toMetadataJson(),
    'features': [for (final f in features) f.toJson()],
  };

  /// Désérialise une initiative complète depuis JSON.
  factory SpecInitiative.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('SpecInitiative doit être un objet JSON.');
    }
    final initiative = SpecInitiative(
      id: (raw['id'] as String?)?.trim() ?? '',
      code: (raw['code'] as String?)?.trim() ?? '',
      name: (raw['name'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
      owner: (raw['owner'] as String?)?.trim() ?? '',
      targetTimeframe: (raw['targetTimeframe'] as String?)?.trim() ?? '',
      priority: RequirementPriority.fromJson(raw['priority']),
      status: SpecPortfolioStatus.fromJson(raw['status']),
      features: [
        if (raw['features'] is List)
          for (final item in raw['features'] as List)
            SpecFeatureSpec.fromJson(item),
      ],
    );
    initiative.validate();
    return initiative;
  }

  /// Désérialise uniquement les métadonnées de `initiative.json` en lui associant [features].
  factory SpecInitiative.fromMetadataJson(
    Object? raw, {
    List<SpecFeatureSpec> features = const <SpecFeatureSpec>[],
  }) {
    if (raw is! Map) {
      throw const FormatException('initiative.json doit être un objet JSON.');
    }
    return SpecInitiative(
      id: (raw['id'] as String?)?.trim() ?? '',
      code: (raw['code'] as String?)?.trim() ?? '',
      name: (raw['name'] as String?)?.trim() ?? '',
      description: (raw['description'] as String?)?.trim() ?? '',
      owner: (raw['owner'] as String?)?.trim() ?? '',
      targetTimeframe: (raw['targetTimeframe'] as String?)?.trim() ?? '',
      priority: RequirementPriority.fromJson(raw['priority']),
      status: SpecPortfolioStatus.fromJson(raw['status']),
      features: features,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecInitiative &&
          hasSameMetadata(other) &&
          listEquals(other.features, features);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    description,
    owner,
    targetTimeframe,
    priority,
    status,
    Object.hashAll(features),
  );
}
