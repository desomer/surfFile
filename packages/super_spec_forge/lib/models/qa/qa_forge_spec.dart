/// Modèle agrégé immuable du volet de spécification BDD/Gherkin & TDD en 4 étapes ([QaForgeSpec]).
library;

import 'package:flutter/foundation.dart';

import '../spec_forge_stage.dart';
import 'gherkin_feature_spec.dart';
import 'qa_coherence_issue.dart';
import 'qa_fixture_spec.dart';
import 'qa_forge_stage.dart';
import 'tdd_suite_spec.dart';

/// Spécification QA complète d'un projet (jeux d'essais, features Gherkin BDD, suites TDD et couverture 360°).
@immutable
class QaForgeSpec {
  /// Construit une spécification QA immuable normalisée sur les 4 étapes de [QaForgeStage].
  QaForgeSpec({
    this.currentStage = QaForgeStage.testFixtures,
    this.gherkinLanguage = GherkinKeywordLanguage.fr,
    List<QaFixtureSpec> fixtures = const <QaFixtureSpec>[],
    List<GherkinFeatureSpec> features = const <GherkinFeatureSpec>[],
    List<TddTestSuiteSpec> tddSuites = const <TddTestSuiteSpec>[],
    Map<QaForgeStage, QaStageState>? stageStates,
    List<QaCoherenceIssue> coherenceIssues = const <QaCoherenceIssue>[],
  }) : fixtures = List<QaFixtureSpec>.unmodifiable(fixtures),
       features = List<GherkinFeatureSpec>.unmodifiable(features),
       tddSuites = List<TddTestSuiteSpec>.unmodifiable(tddSuites),
       stageStates = Map<QaForgeStage, QaStageState>.unmodifiable(
         _normalizeStageStates(stageStates),
       ),
       coherenceIssues = List<QaCoherenceIssue>.unmodifiable(coherenceIssues);

  /// Spécification QA vide initiale.
  static final QaForgeSpec empty = QaForgeSpec();

  /// Étape actuellement sélectionnée dans le wizard QA.
  final QaForgeStage currentStage;

  /// Langue des mots-clés Gherkin générés dans les exports `.feature` (`fr` par défaut).
  final GherkinKeywordLanguage gherkinLanguage;

  /// Livrable de l'étape QA 1 : jeux de données concrets, bornes et cas d'erreur.
  final List<QaFixtureSpec> fixtures;

  /// Livrable de l'étape QA 2 : fonctionnalités Gherkin BDD et scénarios.
  final List<GherkinFeatureSpec> features;

  /// Livrable de l'étape QA 3 : suites de tests unitaires et contrats TDD.
  final List<TddTestSuiteSpec> tddSuites;

  /// Historique conversationnel et statut de chacune des 4 étapes QA.
  final Map<QaForgeStage, QaStageState> stageStates;

  /// Diagnostics de couverture 360° et cohérence Métier+UX↔Tests relevés (locaux et/ou IA).
  final List<QaCoherenceIssue> coherenceIssues;

  /// Vrai si au moins un livrable QA, réglage de langue, diagnostic ou échange d'étape a été amorcé.
  bool get hasContent =>
      fixtures.isNotEmpty ||
      features.isNotEmpty ||
      tddSuites.isNotEmpty ||
      coherenceIssues.isNotEmpty ||
      gherkinLanguage != GherkinKeywordLanguage.fr ||
      stageStates.values.any(
        (s) =>
            s.messages.isNotEmpty ||
            s.status != SpecStageStatus.notStarted ||
            s.stageSummary.trim().isNotEmpty,
      );

  /// Nombre total de scénarios Gherkin cumulés sur l'ensemble des [features].
  int get totalScenarioCount =>
      features.fold<int>(0, (sum, feature) => sum + feature.scenarios.length);

  /// Nombre total de cas de tests TDD cumulés sur l'ensemble des [tddSuites].
  int get totalTddCaseCount =>
      tddSuites.fold<int>(0, (sum, suite) => sum + suite.cases.length);

  /// Retourne l'état d'une étape QA donnée (garanti non nul).
  QaStageState stageStateFor(QaForgeStage stage) =>
      stageStates[stage] ?? QaStageState(stage: stage);

  /// Retourne une copie avec l'état d'une étape QA mis à jour.
  QaForgeSpec withStageState(QaStageState nextState) {
    final nextMap = Map<QaForgeStage, QaStageState>.from(stageStates)
      ..[nextState.stage] = nextState;
    return copyWith(stageStates: nextMap);
  }

  /// Retourne une copie positionnée sur [targetStage] en validant optionnellement l'étape courante.
  QaForgeSpec moveToStage(
    QaForgeStage targetStage, {
    bool validateCurrentStage = false,
  }) {
    final nextMap = Map<QaForgeStage, QaStageState>.from(stageStates);
    if (validateCurrentStage && currentStage != targetStage) {
      final current = stageStateFor(currentStage);
      nextMap[currentStage] = current.copyWith(
        status: SpecStageStatus.validated,
      );
    }
    final target = nextMap[targetStage] ?? QaStageState(stage: targetStage);
    if (target.status == SpecStageStatus.notStarted) {
      nextMap[targetStage] = target.copyWith(
        status: SpecStageStatus.inProgress,
      );
    }
    return copyWith(currentStage: targetStage, stageStates: nextMap);
  }

  /// Recherche une fixture QA par identifiant, code `FIX-xxx` ou nom (insensible à la casse).
  QaFixtureSpec? findFixture(String idOrCodeOrName) {
    final needle = idOrCodeOrName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final fixture in fixtures) {
      if (fixture.id.toLowerCase() == needle ||
          (fixture.code.isNotEmpty && fixture.code.toLowerCase() == needle)) {
        return fixture;
      }
    }
    for (final fixture in fixtures) {
      if (fixture.name.toLowerCase() == needle) return fixture;
    }
    return null;
  }

  /// Recherche une feature Gherkin par identifiant, code `FEAT-xxx` ou titre (insensible à la casse).
  GherkinFeatureSpec? findFeature(String idOrCodeOrTitle) {
    final needle = idOrCodeOrTitle.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final feature in features) {
      if (feature.id.toLowerCase() == needle ||
          (feature.code.isNotEmpty && feature.code.toLowerCase() == needle)) {
        return feature;
      }
    }
    for (final feature in features) {
      if (feature.title.toLowerCase() == needle) return feature;
    }
    return null;
  }

  /// Recherche une suite TDD par identifiant, code `TDD-xxx` ou nom (insensible à la casse).
  TddTestSuiteSpec? findTddSuite(String idOrCodeOrName) {
    final needle = idOrCodeOrName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final suite in tddSuites) {
      if (suite.id.toLowerCase() == needle ||
          (suite.code.isNotEmpty && suite.code.toLowerCase() == needle)) {
        return suite;
      }
    }
    for (final suite in tddSuites) {
      if (suite.name.toLowerCase() == needle) return suite;
    }
    return null;
  }

  /// Vérifie les invariants structurels de l'ensemble de la spécification QA.
  void validate() {
    final fixtureIds = <String>{};
    for (final fixture in fixtures) {
      fixture.validate();
      if (!fixtureIds.add(fixture.id)) {
        throw FormatException('Fixture QA dupliquée : ${fixture.id}');
      }
    }

    final featureIds = <String>{};
    for (final feature in features) {
      feature.validate();
      if (!featureIds.add(feature.id)) {
        throw FormatException('Feature Gherkin dupliquée : ${feature.id}');
      }
    }

    final suiteIds = <String>{};
    for (final suite in tddSuites) {
      suite.validate();
      if (!suiteIds.add(suite.id)) {
        throw FormatException('Suite TDD dupliquée : ${suite.id}');
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
          'Diagnostic de cohérence QA dupliqué : ${issue.id}',
        );
      }
    }
  }

  /// Produit un instantané JSON concis adapté à l'injection dans le prompt de [stage].
  Map<String, Object?> toCompactContextJson(QaForgeStage stage) =>
      <String, Object?>{
        'currentQaStage': stage.name,
        'gherkinLanguage': gherkinLanguage.name,
        'fixtures': [for (final f in fixtures) f.toJson()],
        if (stage.index >= QaForgeStage.gherkinFeatures.index ||
            features.isNotEmpty)
          'features': [for (final f in features) f.toJson()],
        if (stage.index >= QaForgeStage.tddSuites.index ||
            tddSuites.isNotEmpty)
          'tddSuites': [for (final s in tddSuites) s.toJson()],
        if (stage == QaForgeStage.qaReviewExport &&
            coherenceIssues.isNotEmpty)
          'coherenceIssues': [for (final i in coherenceIssues) i.toJson()],
      };

  /// Retourne une copie modifiée.
  QaForgeSpec copyWith({
    QaForgeStage? currentStage,
    GherkinKeywordLanguage? gherkinLanguage,
    List<QaFixtureSpec>? fixtures,
    List<GherkinFeatureSpec>? features,
    List<TddTestSuiteSpec>? tddSuites,
    Map<QaForgeStage, QaStageState>? stageStates,
    List<QaCoherenceIssue>? coherenceIssues,
  }) => QaForgeSpec(
    currentStage: currentStage ?? this.currentStage,
    gherkinLanguage: gherkinLanguage ?? this.gherkinLanguage,
    fixtures: fixtures ?? this.fixtures,
    features: features ?? this.features,
    tddSuites: tddSuites ?? this.tddSuites,
    stageStates: stageStates ?? this.stageStates,
    coherenceIssues: coherenceIssues ?? this.coherenceIssues,
  );

  /// Sérialise la spécification QA complète en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'currentStage': currentStage.name,
    'gherkinLanguage': gherkinLanguage.name,
    'fixtures': [for (final f in fixtures) f.toJson()],
    'features': [for (final f in features) f.toJson()],
    'tddSuites': [for (final s in tddSuites) s.toJson()],
    'stageStates': <String, Object?>{
      for (final entry in stageStates.entries)
        entry.key.name: entry.value.toJson(),
    },
    'coherenceIssues': [for (final i in coherenceIssues) i.toJson()],
  };

  /// Désérialise une spécification QA depuis JSON (retourne [empty] si `raw == null`).
  factory QaForgeSpec.fromJson(Object? raw) {
    if (raw == null) return QaForgeSpec.empty;
    if (raw is! Map) {
      throw const FormatException('QaForgeSpec doit être un objet JSON.');
    }

    final parsedFixtures = <QaFixtureSpec>[];
    final seenFixtureIds = <String>{};
    if (raw['fixtures'] is List) {
      for (final item in raw['fixtures'] as List) {
        var fixture = QaFixtureSpec.fromJson(item);
        if (!seenFixtureIds.add(fixture.id)) {
          var suffix = 2;
          while (!seenFixtureIds.add('${fixture.id}_$suffix')) {
            suffix++;
          }
          fixture = fixture.copyWith(id: '${fixture.id}_$suffix');
        }
        parsedFixtures.add(fixture);
      }
    }

    final parsedFeatures = <GherkinFeatureSpec>[];
    final seenFeatureIds = <String>{};
    if (raw['features'] is List) {
      for (final item in raw['features'] as List) {
        var feature = GherkinFeatureSpec.fromJson(item);
        if (!seenFeatureIds.add(feature.id)) {
          var suffix = 2;
          while (!seenFeatureIds.add('${feature.id}_$suffix')) {
            suffix++;
          }
          feature = feature.copyWith(id: '${feature.id}_$suffix');
        }
        parsedFeatures.add(feature);
      }
    }

    final parsedSuites = <TddTestSuiteSpec>[];
    final seenSuiteIds = <String>{};
    if (raw['tddSuites'] is List) {
      for (final item in raw['tddSuites'] as List) {
        var suite = TddTestSuiteSpec.fromJson(item);
        if (!seenSuiteIds.add(suite.id)) {
          var suffix = 2;
          while (!seenSuiteIds.add('${suite.id}_$suffix')) {
            suffix++;
          }
          suite = suite.copyWith(id: '${suite.id}_$suffix');
        }
        parsedSuites.add(suite);
      }
    }

    final rawStageStates = raw['stageStates'];
    final parsedStageStates = <QaForgeStage, QaStageState>{};
    if (rawStageStates is Map) {
      for (final stage in QaForgeStage.values) {
        final rawStage = rawStageStates[stage.name];
        if (rawStage != null) {
          parsedStageStates[stage] = QaStageState.fromJson(
            rawStage,
            fallbackStage: stage,
          );
        }
      }
    }

    final parsedIssues = <QaCoherenceIssue>[];
    final seenIssueIds = <String>{};
    if (raw['coherenceIssues'] is List) {
      for (final item in raw['coherenceIssues'] as List) {
        var issue = QaCoherenceIssue.fromJson(item);
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

    final spec = QaForgeSpec(
      currentStage: QaForgeStage.fromJson(raw['currentStage']),
      gherkinLanguage: GherkinKeywordLanguage.fromJson(raw['gherkinLanguage']),
      fixtures: parsedFixtures,
      features: parsedFeatures,
      tddSuites: parsedSuites,
      stageStates: parsedStageStates,
      coherenceIssues: parsedIssues,
    );
    spec.validate();
    return spec;
  }

  static Map<QaForgeStage, QaStageState> _normalizeStageStates(
    Map<QaForgeStage, QaStageState>? source,
  ) => <QaForgeStage, QaStageState>{
    for (final stage in QaForgeStage.values)
      stage: source?[stage] ?? QaStageState(stage: stage),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QaForgeSpec &&
          other.currentStage == currentStage &&
          other.gherkinLanguage == gherkinLanguage &&
          listEquals(other.fixtures, fixtures) &&
          listEquals(other.features, features) &&
          listEquals(other.tddSuites, tddSuites) &&
          mapEquals(other.stageStates, stageStates) &&
          listEquals(other.coherenceIssues, coherenceIssues);

  @override
  int get hashCode => Object.hash(
    currentStage,
    gherkinLanguage,
    Object.hashAll(fixtures),
    Object.hashAll(features),
    Object.hashAll(tddSuites),
    Object.hashAll(stageStates.values),
    Object.hashAll(coherenceIssues),
  );
}
