/// Modèle racine immuable d'un projet de forge de spécifications ([SpecForgeProject]).
library;

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';

import 'business_object_model_preferences.dart';
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
import 'spec_initiative.dart';
import 'spec_lexicon.dart';
import 'spec_stage_chat.dart';
import 'spec_vision.dart';
import 'ux/ux_forge_spec.dart';

/// Projet complet de spécification structuré en Initiatives & Features et construit au fil des wizards IA.
@immutable
class SpecForgeProject {
  /// Construit un projet immuable de spécification.
  SpecForgeProject({
    required String id,
    required String name,
    required String initialIdea,
    required DateTime createdAt,
    required DateTime updatedAt,
    SpecForgeStage currentStage = SpecForgeStage.lexicon,
    Set<SpecForgeStage> disabledSpecStages = const <SpecForgeStage>{},
    SpecLexicon? lexicon,
    SpecStageState? lexiconStageState,
    SpecVision? vision,
    SpecCahierDesCharges? cahierDesCharges,
    EventStormingSpec? eventStorming,
    List<BusinessObjectSpec> businessObjects = const <BusinessObjectSpec>[],
    Map<String, FeatureObjectSyncBaseline> objectSyncBaselines =
        const <String, FeatureObjectSyncBaseline>{},
    List<ExampleMapStory> exampleMappings = const <ExampleMapStory>[],
    List<BusinessRuleSpec> businessRules = const <BusinessRuleSpec>[],
    BusinessObjectModelPreferences? businessObjectModelPreferences,
    BusinessObjectModelPreferences? businessObjectLanguageSettings,
    Map<SpecForgeStage, SpecStageState>? stageStates,
    List<SpecCoherenceIssue> coherenceIssues = const <SpecCoherenceIssue>[],
    List<SpecChatMessage> globalChatMessages = const <SpecChatMessage>[],
    List<SpecChatMessage> portfolioChatMessages = const <SpecChatMessage>[],
    UxForgeSpec? uxSpec,
    QaForgeSpec? qaSpec,
    CostForgeSpec? costSpec,
    List<SpecInitiative>? initiatives,
    String? activeFeatureId,
  }) : this._resolved(
         id: id,
         name: name,
         initialIdea: initialIdea,
         createdAt: createdAt,
         updatedAt: updatedAt,
         lexicon: lexicon ?? SpecLexicon.empty,
         lexiconStageState: _normalizeLexiconStageState(
           lexiconStageState ?? stageStates?[SpecForgeStage.lexicon],
         ),
         businessObjectModelPreferences:
             businessObjectModelPreferences ??
             businessObjectLanguageSettings ??
             BusinessObjectModelPreferences.defaults,
         globalChatMessages: List<SpecChatMessage>.unmodifiable(
           globalChatMessages,
         ),
         portfolioChatMessages: List<SpecChatMessage>.unmodifiable(
           portfolioChatMessages,
         ),
         resolvedPortfolio: _resolvePortfolio(
           initiatives: initiatives,
           activeFeatureId: activeFeatureId,
           currentStage: currentStage,
           disabledSpecStages: disabledSpecStages,
           vision: vision,
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
         ),
       );

  SpecForgeProject._resolved({
    required this.id,
    required this.name,
    required this.initialIdea,
    required this.createdAt,
    required this.updatedAt,
    required this.lexicon,
    required this.lexiconStageState,
    required this.businessObjectModelPreferences,
    required this.globalChatMessages,
    required this.portfolioChatMessages,
    required ({
      List<SpecInitiative> initiatives,
      String activeFeatureId,
      SpecInitiative activeInitiative,
      SpecFeatureSpec activeFeature,
    })
    resolvedPortfolio,
  }) : initiatives = resolvedPortfolio.initiatives,
       activeFeatureId = resolvedPortfolio.activeFeatureId,
       _activeInitiative = resolvedPortfolio.activeInitiative,
       _activeFeature = resolvedPortfolio.activeFeature,
       _mergedStageStates = Map<SpecForgeStage, SpecStageState>.unmodifiable(
         <SpecForgeStage, SpecStageState>{
           SpecForgeStage.lexicon: lexiconStageState,
           for (final stage in SpecFeatureSpec.featureScopedStages)
             stage: resolvedPortfolio.activeFeature.stageStateFor(stage),
         },
       );

  /// Crée un nouveau projet à partir d'une idée initiale saisie par l'utilisateur.
  factory SpecForgeProject.fromIdea({
    required String idea,
    String? name,
    String? id,
  }) {
    final trimmedIdea = idea.trim();
    if (trimmedIdea.isEmpty) {
      throw const FormatException('L’idée initiale ne peut pas être vide.');
    }
    final now = DateTime.now().toUtc();
    final derivedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : _deriveProjectName(trimmedIdea);
    final projectId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : 'proj_${shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}';
    return SpecForgeProject(
      id: projectId,
      name: derivedName,
      initialIdea: trimmedIdea,
      createdAt: now,
      updatedAt: now,
      currentStage: SpecForgeStage.lexicon,
      lexicon: SpecLexicon.empty,
      vision: SpecVision(ideaSummary: trimmedIdea),
      stageStates: <SpecForgeStage, SpecStageState>{
        for (final stage in SpecForgeStage.values)
          stage: SpecStageState(
            stage: stage,
            status: stage == SpecForgeStage.lexicon
                ? SpecStageStatus.inProgress
                : SpecStageStatus.notStarted,
          ),
      },
    );
  }

  /// Identifiant unique stable du projet sur disque.
  final String id;

  /// Nom du projet affiché dans l'application et les exports.
  final String name;

  /// Idée brute émise au démarrage du wizard.
  final String initialIdea;

  /// Horodatage UTC de création.
  final DateTime createdAt;

  /// Horodatage UTC de dernière modification.
  final DateTime updatedAt;

  /// Livrable de l'étape 1 (Lexique métier), partagé entre toutes les features du projet.
  final SpecLexicon lexicon;

  /// État et historique du chat de l'étape 1 (Lexique métier), partagés à l'échelle du projet.
  final SpecStageState lexiconStageState;

  /// Préférences unifiées de modélisation partagées à l'échelle du projet.
  final BusinessObjectModelPreferences businessObjectModelPreferences;

  /// Liste ordonnée des initiatives produit du projet (contenant chacune leurs features).
  final List<SpecInitiative> initiatives;

  /// Identifiant de la [SpecFeatureSpec] actuellement active dans les wizards.
  final String activeFeatureId;

  /// Historique des échanges du chat IA de découpage produit (Initiatives & Features).
  final List<SpecChatMessage> portfolioChatMessages;

  /// Historique des échanges du chat global de questions sur le projet.
  final List<SpecChatMessage> globalChatMessages;

  final SpecInitiative _activeInitiative;
  final SpecFeatureSpec _activeFeature;
  final Map<SpecForgeStage, SpecStageState> _mergedStageStates;

  /// Initiative parente contenant la [activeFeature] courante.
  SpecInitiative get activeInitiative => _activeInitiative;

  /// Feature actuellement sélectionnée et projetée dans les 4 wizards.
  SpecFeatureSpec get activeFeature => _activeFeature;

  /// Liste aplatie de toutes les features du projet dans l'ordre de leurs initiatives.
  List<SpecFeatureSpec> get allFeatures => <SpecFeatureSpec>[
    for (final init in initiatives) ...init.features,
  ];

  /// Nombre total de features déclarées dans l'ensemble des initiatives.
  int get totalFeatureCount =>
      initiatives.fold<int>(0, (sum, init) => sum + init.features.length);

  /// Vrai lorsque le projet ne contient encore que l'initiative et la feature initiales par défaut.
  bool get hasSingleDefaultFeature =>
      initiatives.length == 1 &&
      initiatives.single.isDefaultMetadata &&
      initiatives.single.features.length == 1 &&
      initiatives.single.features.single.isDefaultMetadata;

  /// Vrai dès que des initiatives/features personnalisées ou un chat portefeuille ont été enregistrés.
  bool get hasPortfolioCustomization =>
      !hasSingleDefaultFeature || portfolioChatMessages.isNotEmpty;

  /// Étape actuellement sélectionnée dans le wizard de la feature active.
  SpecForgeStage get currentStage => _activeFeature.currentStage;

  /// Étapes optionnelles désactivées pour la feature active.
  Set<SpecForgeStage> get disabledSpecStages =>
      _activeFeature.disabledSpecStages;

  /// Étapes ordonnées actives dans le wizard de spécification pour la feature active.
  List<SpecForgeStage> get enabledSpecStages =>
      _activeFeature.enabledSpecStages;

  /// Vrai si [stage] est active pour la feature active.
  bool isStageEnabled(SpecForgeStage stage) =>
      _activeFeature.isStageEnabled(stage);

  /// Numéro d'ordre dynamique (1-based) de [stage] dans la feature active.
  int stepNumberFor(SpecForgeStage stage) =>
      _activeFeature.stepNumberFor(stage);

  /// Étape active suivante après [stage] dans la feature active, ou `null`.
  SpecForgeStage? nextEnabledStage(SpecForgeStage stage) =>
      _activeFeature.nextEnabledStage(stage);

  /// Étape active précédente avant [stage] dans la feature active, ou `null`.
  SpecForgeStage? previousEnabledStage(SpecForgeStage stage) =>
      _activeFeature.previousEnabledStage(stage);

  /// Livrable de l'étape 2 (Cadrage & Acteurs) de la feature active.
  SpecVision get vision => _activeFeature.vision;

  /// Livrable de l'étape 3 (Cahier des charges) de la feature active.
  SpecCahierDesCharges get cahierDesCharges => _activeFeature.cahierDesCharges;

  /// Livrable de l'étape 4 (Event Storming) de la feature active.
  EventStormingSpec get eventStorming => _activeFeature.eventStorming;

  /// Livrable de l'étape 5 (Objets métiers) de la feature active.
  List<BusinessObjectSpec> get businessObjects =>
      _activeFeature.businessObjects;

  /// Empreintes de synchronisation des objets métiers de la feature active.
  Map<String, FeatureObjectSyncBaseline> get objectSyncBaselines =>
      _activeFeature.objectSyncBaselines;

  /// Livrable de l'étape 6 (Tableaux d'Example Mapping) de la feature active.
  List<ExampleMapStory> get exampleMappings => _activeFeature.exampleMappings;

  /// Livrable de l'étape 7 (Règles de gestion) de la feature active.
  List<BusinessRuleSpec> get businessRules => _activeFeature.businessRules;

  /// Alias rétrocompatible vers [businessObjectModelPreferences].
  BusinessObjectModelPreferences get businessObjectLanguageSettings =>
      businessObjectModelPreferences;

  /// Historique et statut de chaque étape du wizard (étape 1 partagée + étapes 2..8 de la feature active).
  Map<SpecForgeStage, SpecStageState> get stageStates => _mergedStageStates;

  /// Diagnostics de cohérence relevés sur la feature active.
  List<SpecCoherenceIssue> get coherenceIssues =>
      _activeFeature.coherenceIssues;

  /// Spécification UX en 4 étapes de la feature active.
  UxForgeSpec get uxSpec => _activeFeature.uxSpec;

  /// Spécification QA BDD/Gherkin & TDD en 4 étapes de la feature active.
  QaForgeSpec get qaSpec => _activeFeature.qaSpec;

  /// Spécification FinOps & Chiffrage en 4 étapes de la feature active.
  CostForgeSpec get costSpec => _activeFeature.costSpec;

  /// Recherche une initiative par son identifiant.
  SpecInitiative? initiativeById(String? initiativeId) {
    if (initiativeId == null || initiativeId.trim().isEmpty) return null;
    for (final init in initiatives) {
      if (init.id == initiativeId) return init;
    }
    return null;
  }

  /// Recherche une feature par son identifiant à travers toutes les initiatives.
  SpecFeatureSpec? featureById(String? featureId) {
    if (featureId == null || featureId.trim().isEmpty) return null;
    for (final init in initiatives) {
      final found = init.featureById(featureId);
      if (found != null) return found;
    }
    return null;
  }

  /// Retourne l'initiative parente d'une feature [featureId], ou `null` si introuvable.
  SpecInitiative? initiativeOfFeature(String? featureId) {
    if (featureId == null || featureId.trim().isEmpty) return null;
    for (final init in initiatives) {
      if (init.featureById(featureId) != null) return init;
    }
    return null;
  }

  /// Sélectionne [featureId] comme feature active du projet.
  SpecForgeProject selectFeature(String featureId, {DateTime? updatedAt}) {
    if (featureById(featureId) == null) {
      throw FormatException('Feature introuvable : $featureId');
    }
    if (activeFeatureId == featureId && updatedAt == null) return this;
    return copyWith(activeFeatureId: featureId, updatedAt: updatedAt);
  }

  /// Remplace une feature existante par [updatedFeature] dans son initiative parente.
  SpecForgeProject updateFeature(
    SpecFeatureSpec updatedFeature, {
    DateTime? updatedAt,
  }) {
    var replaced = false;
    final nextInitiatives = <SpecInitiative>[
      for (final init in initiatives)
        init.featureById(updatedFeature.id) == null
            ? init
            : init.copyWith(
                features: <SpecFeatureSpec>[
                  for (final f in init.features)
                    if (f.id == updatedFeature.id)
                      (() {
                        replaced = true;
                        return updatedFeature;
                      })()
                    else
                      f,
                ],
              ),
    ];
    if (!replaced) {
      throw FormatException('Feature introuvable : ${updatedFeature.id}');
    }
    return copyWith(initiatives: nextInitiatives, updatedAt: updatedAt);
  }

  /// Génère le prochain code court d'initiative libre (`INIT-01`, `INIT-02`, …).
  String nextInitiativeCode() {
    final existing = <String>{
      for (final i in initiatives) i.code.trim().toUpperCase(),
    };
    var index = initiatives.length + 1;
    while (true) {
      final candidate = 'INIT-${index.toString().padLeft(2, '0')}';
      if (!existing.contains(candidate)) return candidate;
      index++;
    }
  }

  /// Génère le prochain code court de feature libre (`FEAT-01`, `FEAT-02`, …).
  String nextFeatureCode() {
    final existing = <String>{
      for (final f in allFeatures) f.code.trim().toUpperCase(),
    };
    var index = totalFeatureCount + 1;
    while (true) {
      final candidate = 'FEAT-${index.toString().padLeft(2, '0')}';
      if (!existing.contains(candidate)) return candidate;
      index++;
    }
  }

  /// Retourne l'état d'une étape donnée (garanti non nul).
  SpecStageState stageStateFor(SpecForgeStage stage) =>
      stageStates[stage] ?? SpecStageState(stage: stage);

  /// Retourne une copie du projet avec l'état d'une étape mis à jour.
  SpecForgeProject withStageState(
    SpecStageState nextState, {
    DateTime? updatedAt,
  }) {
    final nextMap = Map<SpecForgeStage, SpecStageState>.from(stageStates)
      ..[nextState.stage] = nextState;
    return copyWith(stageStates: nextMap, updatedAt: updatedAt);
  }

  /// Retourne une copie du projet en avançant à [targetStage] et en marquant
  /// éventuellement l'étape courante comme validée.
  SpecForgeProject moveToStage(
    SpecForgeStage targetStage, {
    bool validateCurrentStage = false,
  }) {
    if (!isStageEnabled(targetStage)) {
      return this;
    }
    final nextMap = Map<SpecForgeStage, SpecStageState>.from(stageStates);
    if (validateCurrentStage && currentStage != targetStage) {
      final current = stageStateFor(currentStage);
      nextMap[currentStage] = current.copyWith(
        status: SpecStageStatus.validated,
      );
    }
    final target = nextMap[targetStage] ?? SpecStageState(stage: targetStage);
    if (target.status == SpecStageStatus.notStarted) {
      nextMap[targetStage] = target.copyWith(
        status: SpecStageStatus.inProgress,
      );
    }
    return copyWith(currentStage: targetStage, stageStates: nextMap);
  }

  /// Recherche un objet métier par identifiant ou nom technique (insensible à la casse).
  BusinessObjectSpec? findBusinessObject(String idOrName) {
    final needle = idOrName.trim().toLowerCase();
    for (final obj in businessObjects) {
      if (obj.id.toLowerCase() == needle ||
          obj.technicalName.toLowerCase() == needle ||
          obj.name.toLowerCase() == needle) {
        return obj;
      }
    }
    return null;
  }

  /// Valide les invariants structurels du projet complet.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('SpecForgeProject.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException(
        'SpecForgeProject.name ne peut pas être vide.',
      );
    }
    if (initialIdea.trim().isEmpty) {
      throw const FormatException(
        'SpecForgeProject.initialIdea ne peut pas être vide.',
      );
    }
    lexicon.validate();
    if (lexiconStageState.stage != SpecForgeStage.lexicon) {
      throw const FormatException(
        'lexiconStageState doit cibler SpecForgeStage.lexicon.',
      );
    }
    businessObjectModelPreferences.validate();
    if (initiatives.isEmpty) {
      throw const FormatException(
        'SpecForgeProject doit contenir au moins une initiative.',
      );
    }
    final initIds = <String>{};
    final featIds = <String>{};
    for (final init in initiatives) {
      init.validate();
      if (!initIds.add(init.id)) {
        throw FormatException('Initiative dupliquée : ${init.id}');
      }
      for (final feat in init.features) {
        if (!featIds.add(feat.id)) {
          throw FormatException('Feature dupliquée dans le projet : ${feat.id}');
        }
      }
    }
    if (featIds.isEmpty) {
      throw const FormatException(
        'SpecForgeProject doit contenir au moins une feature.',
      );
    }
    if (!featIds.contains(activeFeatureId)) {
      throw FormatException(
        'SpecForgeProject.activeFeatureId introuvable : $activeFeatureId',
      );
    }
  }

  /// Produit un instantané JSON concis adapté à l'injection dans le prompt de [stage].
  Map<String, Object?> toCompactContextJson(SpecForgeStage stage) =>
      <String, Object?>{
        'projectName': name,
        'initialIdea': initialIdea,
        if (!hasSingleDefaultFeature) ...<String, Object?>{
          'activeInitiative': <String, Object?>{
            'id': activeInitiative.id,
            if (activeInitiative.code.isNotEmpty) 'code': activeInitiative.code,
            'name': activeInitiative.name,
            if (activeInitiative.description.isNotEmpty)
              'description': activeInitiative.description,
          },
          'activeFeature': <String, Object?>{
            'id': activeFeature.id,
            if (activeFeature.code.isNotEmpty) 'code': activeFeature.code,
            'name': activeFeature.name,
            if (activeFeature.description.isNotEmpty)
              'description': activeFeature.description,
            if (activeFeature.targetRelease.isNotEmpty)
              'targetRelease': activeFeature.targetRelease,
            'priority': activeFeature.priority.name,
          },
          'projectPortfolio': [
            for (final init in initiatives)
              <String, Object?>{
                'id': init.id,
                if (init.code.isNotEmpty) 'code': init.code,
                'name': init.name,
                'features': [
                  for (final f in init.features)
                    <String, Object?>{
                      'id': f.id,
                      if (f.code.isNotEmpty) 'code': f.code,
                      'name': f.name,
                      'active': f.id == activeFeatureId,
                    },
                ],
              },
          ],
        },
        'currentStage': stage.name,
        'enabledSpecStages': [for (final s in enabledSpecStages) s.name],
        if (disabledSpecStages.isNotEmpty)
          'disabledSpecStages': [for (final s in disabledSpecStages) s.name],
        'lexicon': lexicon.toJson(),
        if (stage.index >= SpecForgeStage.vision.index || vision.hasContent)
          'vision': vision.toJson(),
        if (stage.index >= SpecForgeStage.specifications.index ||
            cahierDesCharges.hasContent)
          'cahierDesCharges': cahierDesCharges.toJson(),
        if (isStageEnabled(SpecForgeStage.eventStorming) &&
            (stage.index >= SpecForgeStage.eventStorming.index ||
                eventStorming.hasContent))
          'eventStorming': eventStorming.toJson(),
        if (stage.index >= SpecForgeStage.businessObjects.index ||
            businessObjects.isNotEmpty)
          'businessObjects': [for (final o in businessObjects) o.toJson()],
        if (stage.index >= SpecForgeStage.businessObjects.index ||
            !businessObjectModelPreferences.isDefault)
          'businessObjectModelPreferences':
              businessObjectModelPreferences.toJson(),
        if (isStageEnabled(SpecForgeStage.exampleMapping) &&
            (stage.index >= SpecForgeStage.exampleMapping.index ||
                exampleMappings.isNotEmpty))
          'exampleMappings': [for (final s in exampleMappings) s.toJson()],
        if (stage.index >= SpecForgeStage.businessRules.index ||
            businessRules.isNotEmpty)
          'businessRules': [for (final r in businessRules) r.toJson()],
        if (stage == SpecForgeStage.reviewExport && coherenceIssues.isNotEmpty)
          'coherenceIssues': [for (final i in coherenceIssues) i.toJson()],
        if (uxSpec.hasContent)
          'uxSummary': <String, Object?>{
            'currentStage': uxSpec.currentStage.name,
            'journeyCount': uxSpec.journeys.length,
            'routeCount': uxSpec.navigation.routes.length,
            'screenCount': uxSpec.screens.length,
            'shellPattern': uxSpec.navigation.shellPattern.name,
            if (uxSpec.journeys.isNotEmpty)
              'journeys': [
                for (final j in uxSpec.journeys)
                  <String, Object?>{
                    'id': j.id,
                    'code': j.code,
                    'name': j.name,
                  },
              ],
            if (uxSpec.navigation.routes.isNotEmpty)
              'routes': [
                for (final r in uxSpec.navigation.routes)
                  <String, Object?>{
                    'id': r.id,
                    'path': r.path,
                    'title': r.title,
                  },
              ],
            if (uxSpec.screens.isNotEmpty)
              'screens': [
                for (final s in uxSpec.screens)
                  <String, Object?>{
                    'id': s.id,
                    'code': s.code,
                    'name': s.name,
                    'routeId': s.routeId,
                    'pattern': s.pattern.name,
                  },
              ],
          },
        if (qaSpec.hasContent)
          'qaSummary': <String, Object?>{
            'currentStage': qaSpec.currentStage.name,
            'gherkinLanguage': qaSpec.gherkinLanguage.name,
            'fixtureCount': qaSpec.fixtures.length,
            'featureCount': qaSpec.features.length,
            'scenarioCount': qaSpec.totalScenarioCount,
            'tddSuiteCount': qaSpec.tddSuites.length,
            'tddCaseCount': qaSpec.totalTddCaseCount,
            if (qaSpec.fixtures.isNotEmpty)
              'fixtures': [
                for (final f in qaSpec.fixtures)
                  <String, Object?>{
                    'id': f.id,
                    'code': f.code,
                    'name': f.name,
                    'kind': f.kind.name,
                  },
              ],
            if (qaSpec.features.isNotEmpty)
              'features': [
                for (final f in qaSpec.features)
                  <String, Object?>{
                    'id': f.id,
                    'code': f.code,
                    'title': f.title,
                    'scenarioCount': f.scenarios.length,
                  },
              ],
            if (qaSpec.tddSuites.isNotEmpty)
              'tddSuites': [
                for (final s in qaSpec.tddSuites)
                  <String, Object?>{
                    'id': s.id,
                    'code': s.code,
                    'name': s.name,
                    'layer': s.layer.name,
                    'caseCount': s.cases.length,
                  },
              ],
          },
        if (costSpec.hasContent)
          'costSummary': <String, Object?>{
            'currentStage': costSpec.currentStage.name,
            'currency': costSpec.currency.code,
            'deliveryMode': costSpec.deliveryMode.name,
            'hoursPerDay': costSpec.hoursPerDay,
            'targetUsersCount': costSpec.targetUsersCount,
            'aiProductivityEnabled': costSpec.aiProductivity.enabled,
            'wbsItemCount': costSpec.wbsItems.length,
            'runItemCount': costSpec.runItems.length,
            'riskItemCount': costSpec.riskItems.length,
            if (costSpec.wbsItems.isNotEmpty)
              'wbsItems': [
                for (final w in costSpec.wbsItems)
                  <String, Object?>{
                    'id': w.id,
                    'code': w.code,
                    'title': w.title,
                    'discipline': w.discipline.name,
                    'priority': w.priority.name,
                    'expectedDays': w.expectedDays,
                  },
              ],
            if (costSpec.runItems.isNotEmpty)
              'runItems': [
                for (final r in costSpec.runItems)
                  <String, Object?>{
                    'id': r.id,
                    'code': r.code,
                    'name': r.name,
                    'category': r.category.name,
                    'yearlyCost': r.yearlyCost,
                  },
              ],
            if (costSpec.riskItems.isNotEmpty)
              'riskItems': [
                for (final r in costSpec.riskItems)
                  <String, Object?>{
                    'id': r.id,
                    'code': r.code,
                    'title': r.title,
                    'probabilityPct': r.probabilityPct,
                    'expectedDays': r.expectedDays,
                  },
              ],
          },
      };

  /// Copie modifiée (met à jour [updatedAt] automatiquement si non fourni).
  SpecForgeProject copyWith({
    String? id,
    String? name,
    String? initialIdea,
    DateTime? createdAt,
    DateTime? updatedAt,
    SpecForgeStage? currentStage,
    Set<SpecForgeStage>? disabledSpecStages,
    SpecLexicon? lexicon,
    SpecStageState? lexiconStageState,
    SpecVision? vision,
    SpecCahierDesCharges? cahierDesCharges,
    EventStormingSpec? eventStorming,
    List<BusinessObjectSpec>? businessObjects,
    Map<String, FeatureObjectSyncBaseline>? objectSyncBaselines,
    List<ExampleMapStory>? exampleMappings,
    List<BusinessRuleSpec>? businessRules,
    BusinessObjectModelPreferences? businessObjectModelPreferences,
    BusinessObjectModelPreferences? businessObjectLanguageSettings,
    Map<SpecForgeStage, SpecStageState>? stageStates,
    List<SpecCoherenceIssue>? coherenceIssues,
    List<SpecChatMessage>? globalChatMessages,
    List<SpecChatMessage>? portfolioChatMessages,
    UxForgeSpec? uxSpec,
    QaForgeSpec? qaSpec,
    CostForgeSpec? costSpec,
    List<SpecInitiative>? initiatives,
    String? activeFeatureId,
  }) {
    final baseInitiatives = initiatives ?? this.initiatives;
    final targetFeatureId = activeFeatureId ?? this.activeFeatureId;
    final hasFeatureOverrides =
        currentStage != null ||
        disabledSpecStages != null ||
        vision != null ||
        cahierDesCharges != null ||
        eventStorming != null ||
        businessObjects != null ||
        objectSyncBaselines != null ||
        exampleMappings != null ||
        businessRules != null ||
        stageStates != null ||
        coherenceIssues != null ||
        uxSpec != null ||
        qaSpec != null ||
        costSpec != null;

    final nextInitiatives = !hasFeatureOverrides
        ? baseInitiatives
        : <SpecInitiative>[
            for (final init in baseInitiatives)
              init.copyWith(
                features: <SpecFeatureSpec>[
                  for (final f in init.features)
                    if (f.id == targetFeatureId)
                      f.copyWith(
                        currentStage: currentStage,
                        disabledSpecStages: disabledSpecStages,
                        vision: vision,
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
                      )
                    else
                      f,
                ],
              ),
          ];

    final nextLexiconState =
        lexiconStageState ??
        stageStates?[SpecForgeStage.lexicon] ??
        this.lexiconStageState;

    return SpecForgeProject(
      id: id ?? this.id,
      name: name ?? this.name,
      initialIdea: initialIdea ?? this.initialIdea,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
      lexicon: lexicon ?? this.lexicon,
      lexiconStageState: nextLexiconState,
      businessObjectModelPreferences:
          businessObjectModelPreferences ??
          businessObjectLanguageSettings ??
          this.businessObjectModelPreferences,
      globalChatMessages: globalChatMessages ?? this.globalChatMessages,
      portfolioChatMessages:
          portfolioChatMessages ?? this.portfolioChatMessages,
      initiatives: nextInitiatives,
      activeFeatureId: targetFeatureId,
    );
  }

  /// Sérialise le projet complet en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'format': 'super_spec_forge.project',
    'version': hasPortfolioCustomization ? 2 : 1,
    'id': id,
    'name': name,
    'initialIdea': initialIdea,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'currentStage': currentStage.name,
    if (disabledSpecStages.isNotEmpty)
      'disabledSpecStages': [for (final s in disabledSpecStages) s.name],
    'lexicon': lexicon.toJson(),
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
    if (!businessObjectModelPreferences.isDefault)
      'businessObjectModelPreferences': businessObjectModelPreferences.toJson(),
    'stageStates': <String, Object?>{
      for (final entry in stageStates.entries)
        entry.key.name: entry.value.toJson(),
    },
    'coherenceIssues': [for (final i in coherenceIssues) i.toJson()],
    if (globalChatMessages.isNotEmpty)
      'globalChatMessages': [for (final m in globalChatMessages) m.toJson()],
    if (portfolioChatMessages.isNotEmpty)
      'portfolioChatMessages': [
        for (final m in portfolioChatMessages) m.toJson(),
      ],
    if (uxSpec.hasContent) 'uxSpec': uxSpec.toJson(),
    if (qaSpec.hasContent) 'qaSpec': qaSpec.toJson(),
    if (costSpec.hasContent) 'costSpec': costSpec.toJson(),
    if (!hasSingleDefaultFeature) ...<String, Object?>{
      'activeFeatureId': activeFeatureId,
      'initiatives': [for (final i in initiatives) i.toJson()],
    },
  };

  /// Désérialise et valide un projet depuis JSON.
  factory SpecForgeProject.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('SpecForgeProject doit être un objet JSON.');
    }
    final id = (raw['id'] as String?)?.trim() ?? '';
    final name = (raw['name'] as String?)?.trim() ?? '';
    final initialIdea = (raw['initialIdea'] as String?)?.trim() ?? '';
    final now = DateTime.now().toUtc();
    final createdAt = _parseDateTime(raw['createdAt']) ?? now;
    final updatedAt = _parseDateTime(raw['updatedAt']) ?? createdAt;

    final rawStageStates = raw['stageStates'];
    final parsedStageStates = <SpecForgeStage, SpecStageState>{};
    if (rawStageStates is Map) {
      for (final stage in SpecForgeStage.values) {
        final rawStage = rawStageStates[stage.name];
        if (rawStage != null) {
          parsedStageStates[stage] = SpecStageState.fromJson(
            rawStage,
            fallbackStage: stage,
          );
        }
      }
    }

    final parsedInitiatives = raw['initiatives'] is List
        ? <SpecInitiative>[
            for (final item in raw['initiatives'] as List)
              SpecInitiative.fromJson(item),
          ]
        : null;

    final project = SpecForgeProject(
      id: id,
      name: name,
      initialIdea: initialIdea,
      createdAt: createdAt,
      updatedAt: updatedAt,
      currentStage: SpecForgeStage.fromJson(raw['currentStage']),
      disabledSpecStages: SpecFeatureSpec.parseDisabledSpecStages(
        raw['disabledSpecStages'],
      ),
      lexicon: SpecLexicon.fromJson(raw['lexicon']),
      lexiconStageState: parsedStageStates[SpecForgeStage.lexicon],
      vision: SpecVision.fromJson(raw['vision']),
      cahierDesCharges: SpecCahierDesCharges.fromJson(raw['cahierDesCharges']),
      eventStorming: EventStormingSpec.fromJson(raw['eventStorming']),
      businessObjects: [
        if (raw['businessObjects'] is List)
          for (final item in raw['businessObjects'] as List)
            BusinessObjectSpec.fromJson(item),
      ],
      objectSyncBaselines: SpecFeatureSpec.parseObjectSyncBaselines(
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
      businessObjectModelPreferences:
          BusinessObjectModelPreferences.fromJson(
            raw['businessObjectModelPreferences'] ??
                raw['businessObjectLanguageSettings'],
          ),
      stageStates: parsedStageStates,
      coherenceIssues: [
        if (raw['coherenceIssues'] is List)
          for (final item in raw['coherenceIssues'] as List)
            SpecCoherenceIssue.fromJson(item),
      ],
      globalChatMessages: [
        if (raw['globalChatMessages'] is List)
          for (final item in raw['globalChatMessages'] as List)
            SpecChatMessage.fromJson(item),
      ],
      portfolioChatMessages: [
        if (raw['portfolioChatMessages'] is List)
          for (final item in raw['portfolioChatMessages'] as List)
            SpecChatMessage.fromJson(item),
      ],
      uxSpec: UxForgeSpec.fromJson(raw['uxSpec']),
      qaSpec: QaForgeSpec.fromJson(raw['qaSpec']),
      costSpec: CostForgeSpec.fromJson(raw['costSpec']),
      initiatives: parsedInitiatives,
      activeFeatureId: (raw['activeFeatureId'] as String?)?.trim(),
    );
    project.validate();
    return project;
  }

  static SpecStageState _normalizeLexiconStageState(SpecStageState? source) {
    if (source == null) {
      return SpecStageState(stage: SpecForgeStage.lexicon);
    }
    if (source.stage == SpecForgeStage.lexicon) return source;
    return SpecStageState(
      stage: SpecForgeStage.lexicon,
      status: source.status,
      messages: source.messages,
      stageSummary: source.stageSummary,
      readyToAdvance: source.readyToAdvance,
    );
  }

  static ({
    List<SpecInitiative> initiatives,
    String activeFeatureId,
    SpecInitiative activeInitiative,
    SpecFeatureSpec activeFeature,
  })
  _resolvePortfolio({
    required List<SpecInitiative>? initiatives,
    required String? activeFeatureId,
    required SpecForgeStage currentStage,
    required Set<SpecForgeStage> disabledSpecStages,
    required SpecVision? vision,
    required SpecCahierDesCharges? cahierDesCharges,
    required EventStormingSpec? eventStorming,
    required List<BusinessObjectSpec> businessObjects,
    required Map<String, FeatureObjectSyncBaseline> objectSyncBaselines,
    required List<ExampleMapStory> exampleMappings,
    required List<BusinessRuleSpec> businessRules,
    required Map<SpecForgeStage, SpecStageState>? stageStates,
    required List<SpecCoherenceIssue> coherenceIssues,
    required UxForgeSpec? uxSpec,
    required QaForgeSpec? qaSpec,
    required CostForgeSpec? costSpec,
  }) {
    SpecFeatureSpec buildFallbackFeature() => SpecFeatureSpec.createDefault(
      currentStage: currentStage,
      disabledSpecStages: disabledSpecStages,
      vision: vision,
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

    List<SpecInitiative> normalized;
    if (initiatives == null || initiatives.isEmpty) {
      normalized = <SpecInitiative>[
        SpecInitiative.createDefault(feature: buildFallbackFeature()),
      ];
    } else {
      final hasAnyFeature = initiatives.any((i) => i.features.isNotEmpty);
      if (!hasAnyFeature) {
        normalized = <SpecInitiative>[
          initiatives.first.copyWith(
            features: <SpecFeatureSpec>[buildFallbackFeature()],
          ),
          ...initiatives.skip(1),
        ];
      } else {
        normalized = initiatives;
      }
    }

    final frozenInitiatives = List<SpecInitiative>.unmodifiable(normalized);
    final trimmedActive = activeFeatureId?.trim();
    SpecInitiative? matchedInitiative;
    SpecFeatureSpec? matchedFeature;
    if (trimmedActive != null && trimmedActive.isNotEmpty) {
      for (final init in frozenInitiatives) {
        final found = init.featureById(trimmedActive);
        if (found != null) {
          matchedInitiative = init;
          matchedFeature = found;
          break;
        }
      }
    }
    if (matchedFeature == null || matchedInitiative == null) {
      for (final init in frozenInitiatives) {
        if (init.features.isNotEmpty) {
          matchedInitiative = init;
          matchedFeature = init.features.first;
          break;
        }
      }
    }

    return (
      initiatives: frozenInitiatives,
      activeFeatureId: matchedFeature!.id,
      activeInitiative: matchedInitiative!,
      activeFeature: matchedFeature,
    );
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  static String _deriveProjectName(String idea) {
    final firstLine = idea.split(RegExp(r'[\r\n]+')).first.trim();
    if (firstLine.length <= 48) return firstLine;
    return '${firstLine.substring(0, 45).trimRight()}…';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecForgeProject &&
          other.id == id &&
          other.name == name &&
          other.initialIdea == initialIdea &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.lexicon == lexicon &&
          other.lexiconStageState == lexiconStageState &&
          other.businessObjectModelPreferences ==
              businessObjectModelPreferences &&
          other.activeFeatureId == activeFeatureId &&
          listEquals(other.initiatives, initiatives) &&
          listEquals(other.globalChatMessages, globalChatMessages) &&
          listEquals(other.portfolioChatMessages, portfolioChatMessages);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    name,
    initialIdea,
    createdAt,
    updatedAt,
    lexicon,
    lexiconStageState,
    businessObjectModelPreferences,
    activeFeatureId,
    Object.hashAll(initiatives),
    Object.hashAll(globalChatMessages),
    Object.hashAll(portfolioChatMessages),
  ]);
}
