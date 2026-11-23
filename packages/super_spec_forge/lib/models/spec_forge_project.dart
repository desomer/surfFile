/// Modèle racine immuable d'un projet de forge de spécifications ([SpecForgeProject]).
library;

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';

import 'business_object_model_preferences.dart';
import 'business_object_spec.dart';
import 'business_rule_spec.dart';
import 'example_mapping_spec.dart';
import 'qa/qa_forge_spec.dart';
import 'spec_cahier_des_charges.dart';
import 'spec_coherence_issue.dart';
import 'spec_forge_stage.dart';
import 'spec_lexicon.dart';
import 'spec_stage_chat.dart';
import 'spec_vision.dart';
import 'ux/ux_forge_spec.dart';

/// Projet complet de spécification construit au fil des 7 étapes du wizard IA.
@immutable
class SpecForgeProject {
  /// Construit un projet immuable de spécification.
  SpecForgeProject({
    required this.id,
    required this.name,
    required this.initialIdea,
    required this.createdAt,
    required this.updatedAt,
    this.currentStage = SpecForgeStage.lexicon,
    SpecLexicon? lexicon,
    SpecVision? vision,
    SpecCahierDesCharges? cahierDesCharges,
    List<BusinessObjectSpec> businessObjects = const <BusinessObjectSpec>[],
    List<ExampleMapStory> exampleMappings = const <ExampleMapStory>[],
    List<BusinessRuleSpec> businessRules = const <BusinessRuleSpec>[],
    BusinessObjectModelPreferences? businessObjectModelPreferences,
    BusinessObjectModelPreferences? businessObjectLanguageSettings,
    Map<SpecForgeStage, SpecStageState>? stageStates,
    List<SpecCoherenceIssue> coherenceIssues = const <SpecCoherenceIssue>[],
    List<SpecChatMessage> globalChatMessages = const <SpecChatMessage>[],
    UxForgeSpec? uxSpec,
    QaForgeSpec? qaSpec,
  }) : lexicon = lexicon ?? SpecLexicon.empty,
       vision = vision ?? SpecVision.empty,
       cahierDesCharges = cahierDesCharges ?? SpecCahierDesCharges.empty,
       businessObjects = List<BusinessObjectSpec>.unmodifiable(businessObjects),
       _exampleMappings = List<ExampleMapStory>.unmodifiable(exampleMappings),
       businessRules = List<BusinessRuleSpec>.unmodifiable(businessRules),
       businessObjectModelPreferences =
           businessObjectModelPreferences ??
           businessObjectLanguageSettings ??
           BusinessObjectModelPreferences.defaults,
       stageStates = Map<SpecForgeStage, SpecStageState>.unmodifiable(
         _normalizeStageStates(stageStates),
       ),
       coherenceIssues = List<SpecCoherenceIssue>.unmodifiable(coherenceIssues),
       globalChatMessages = List<SpecChatMessage>.unmodifiable(
         globalChatMessages,
       ),
       uxSpec = uxSpec ?? UxForgeSpec.empty,
       qaSpec = qaSpec ?? QaForgeSpec.empty;

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

  /// Étape actuellement sélectionnée dans le wizard.
  final SpecForgeStage currentStage;

  /// Livrable de l'étape 1 (Lexique métier).
  final SpecLexicon lexicon;

  /// Livrable de l'étape 2 (Cadrage & Acteurs).
  final SpecVision vision;

  /// Livrable de l'étape 2 (Cahier des charges fonctionnel et non fonctionnel).
  final SpecCahierDesCharges cahierDesCharges;

  /// Livrable de l'étape 4 (Objets métiers, attributs, relations, cycles de vie).
  final List<BusinessObjectSpec> businessObjects;

  final List<ExampleMapStory>? _exampleMappings;

  /// Livrable de l'étape 5 (Tableaux d'Example Mapping à 4 couleurs).
  List<ExampleMapStory> get exampleMappings =>
      _exampleMappings ?? const <ExampleMapStory>[];

  /// Livrable de l'étape 6 (Règles de gestion structurées).
  final List<BusinessRuleSpec> businessRules;

  /// Préférences unifiées de modélisation (langues, casse, clés/audit, rigueur JSON Schema, profil régional).
  final BusinessObjectModelPreferences businessObjectModelPreferences;

  /// Alias rétrocompatible vers [businessObjectModelPreferences].
  BusinessObjectModelPreferences get businessObjectLanguageSettings =>
      businessObjectModelPreferences;

  /// Historique et statut de chaque étape du wizard.
  final Map<SpecForgeStage, SpecStageState> stageStates;

  /// Diagnostics de cohérence relevés (locaux et/ou IA).
  final List<SpecCoherenceIssue> coherenceIssues;

  /// Historique des échanges du chat global de questions sur le projet.
  final List<SpecChatMessage> globalChatMessages;

  /// Spécification UX en 4 étapes (parcours, architecture/navigation, écrans et audit UX).
  final UxForgeSpec uxSpec;

  /// Spécification QA BDD/Gherkin & TDD en 4 étapes (jeux d'essais, features Gherkin, suites TDD et couverture 360°).
  final QaForgeSpec qaSpec;

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
    vision.validate();
    cahierDesCharges.validate();
    businessObjectModelPreferences.validate();

    final objIds = <String>{};
    for (final obj in businessObjects) {
      obj.validate();
      if (!objIds.add(obj.id)) {
        throw FormatException('Objet métier dupliqué : ${obj.id}');
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
  }

  /// Produit un instantané JSON concis adapté à l'injection dans le prompt de [stage].
  Map<String, Object?> toCompactContextJson(SpecForgeStage stage) =>
      <String, Object?>{
        'projectName': name,
        'initialIdea': initialIdea,
        'currentStage': stage.name,
        'lexicon': lexicon.toJson(),
        if (stage.index >= SpecForgeStage.vision.index || vision.hasContent)
          'vision': vision.toJson(),
        if (stage.index >= SpecForgeStage.specifications.index ||
            cahierDesCharges.hasContent)
          'cahierDesCharges': cahierDesCharges.toJson(),
        if (stage.index >= SpecForgeStage.businessObjects.index ||
            businessObjects.isNotEmpty)
          'businessObjects': [for (final o in businessObjects) o.toJson()],
        if (stage.index >= SpecForgeStage.businessObjects.index ||
            !businessObjectModelPreferences.isDefault)
          'businessObjectModelPreferences':
              businessObjectModelPreferences.toJson(),
        if (stage.index >= SpecForgeStage.exampleMapping.index ||
            exampleMappings.isNotEmpty)
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
      };

  /// Copie modifiée (met à jour [updatedAt] automatiquement si non fourni).
  SpecForgeProject copyWith({
    String? id,
    String? name,
    String? initialIdea,
    DateTime? createdAt,
    DateTime? updatedAt,
    SpecForgeStage? currentStage,
    SpecLexicon? lexicon,
    SpecVision? vision,
    SpecCahierDesCharges? cahierDesCharges,
    List<BusinessObjectSpec>? businessObjects,
    List<ExampleMapStory>? exampleMappings,
    List<BusinessRuleSpec>? businessRules,
    BusinessObjectModelPreferences? businessObjectModelPreferences,
    BusinessObjectModelPreferences? businessObjectLanguageSettings,
    Map<SpecForgeStage, SpecStageState>? stageStates,
    List<SpecCoherenceIssue>? coherenceIssues,
    List<SpecChatMessage>? globalChatMessages,
    UxForgeSpec? uxSpec,
    QaForgeSpec? qaSpec,
  }) => SpecForgeProject(
    id: id ?? this.id,
    name: name ?? this.name,
    initialIdea: initialIdea ?? this.initialIdea,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    currentStage: currentStage ?? this.currentStage,
    lexicon: lexicon ?? this.lexicon,
    vision: vision ?? this.vision,
    cahierDesCharges: cahierDesCharges ?? this.cahierDesCharges,
    businessObjects: businessObjects ?? this.businessObjects,
    exampleMappings: exampleMappings ?? this.exampleMappings,
    businessRules: businessRules ?? this.businessRules,
    businessObjectModelPreferences:
        businessObjectModelPreferences ??
        businessObjectLanguageSettings ??
        this.businessObjectModelPreferences,
    stageStates: stageStates ?? this.stageStates,
    coherenceIssues: coherenceIssues ?? this.coherenceIssues,
    globalChatMessages: globalChatMessages ?? this.globalChatMessages,
    uxSpec: uxSpec ?? this.uxSpec,
    qaSpec: qaSpec ?? this.qaSpec,
  );

  /// Sérialise le projet complet en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'format': 'super_spec_forge.project',
    'version': 1,
    'id': id,
    'name': name,
    'initialIdea': initialIdea,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'currentStage': currentStage.name,
    'lexicon': lexicon.toJson(),
    'vision': vision.toJson(),
    'cahierDesCharges': cahierDesCharges.toJson(),
    'businessObjects': [for (final o in businessObjects) o.toJson()],
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
    if (uxSpec.hasContent) 'uxSpec': uxSpec.toJson(),
    if (qaSpec.hasContent) 'qaSpec': qaSpec.toJson(),
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

    final project = SpecForgeProject(
      id: id,
      name: name,
      initialIdea: initialIdea,
      createdAt: createdAt,
      updatedAt: updatedAt,
      currentStage: SpecForgeStage.fromJson(raw['currentStage']),
      lexicon: SpecLexicon.fromJson(raw['lexicon']),
      vision: SpecVision.fromJson(raw['vision']),
      cahierDesCharges: SpecCahierDesCharges.fromJson(raw['cahierDesCharges']),
      businessObjects: [
        if (raw['businessObjects'] is List)
          for (final item in raw['businessObjects'] as List)
            BusinessObjectSpec.fromJson(item),
      ],
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
      uxSpec: UxForgeSpec.fromJson(raw['uxSpec']),
      qaSpec: QaForgeSpec.fromJson(raw['qaSpec']),
    );
    project.validate();
    return project;
  }

  static Map<SpecForgeStage, SpecStageState> _normalizeStageStates(
    Map<SpecForgeStage, SpecStageState>? source,
  ) => <SpecForgeStage, SpecStageState>{
    for (final stage in SpecForgeStage.values)
      stage: source?[stage] ?? SpecStageState(stage: stage),
  };

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
          other.currentStage == currentStage &&
          other.lexicon == lexicon &&
          other.vision == vision &&
          other.cahierDesCharges == cahierDesCharges &&
          listEquals(other.businessObjects, businessObjects) &&
          listEquals(other.exampleMappings, exampleMappings) &&
          listEquals(other.businessRules, businessRules) &&
          other.businessObjectModelPreferences ==
              businessObjectModelPreferences &&
          mapEquals(other.stageStates, stageStates) &&
          listEquals(other.coherenceIssues, coherenceIssues) &&
          listEquals(other.globalChatMessages, globalChatMessages) &&
          other.uxSpec == uxSpec &&
          other.qaSpec == qaSpec;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    initialIdea,
    createdAt,
    updatedAt,
    currentStage,
    lexicon,
    vision,
    cahierDesCharges,
    Object.hashAll(businessObjects),
    Object.hashAll(exampleMappings),
    Object.hashAll(businessRules),
    businessObjectModelPreferences,
    Object.hashAll(stageStates.values),
    Object.hashAll(coherenceIssues),
    Object.hashAll(globalChatMessages),
    uxSpec,
    qaSpec,
  );
}
