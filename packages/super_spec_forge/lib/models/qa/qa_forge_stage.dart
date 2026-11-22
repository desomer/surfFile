/// Étapes ordonnées du wizard BDD/Gherkin & TDD ([QaForgeStage]), langue des mots-clés Gherkin ([GherkinKeywordLanguage]) et état conversationnel par étape ([QaStageState]).
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../spec_forge_stage.dart';
import '../spec_stage_chat.dart';

/// Langue officielle des mots-clés Gherkin générés dans les fichiers `.feature`.
enum GherkinKeywordLanguage {
  /// Syntaxe Gherkin officielle en français (`# language: fr`).
  fr(
    'Français (# language: fr)',
    'Fonctionnalité',
    'Contexte',
    'Scénario',
    'Plan du Scénario',
    'Exemples',
    'Étant donné',
    'Quand',
    'Alors',
    'Et',
    'Mais',
  ),

  /// Syntaxe Gherkin standard internationale en anglais.
  en(
    'English (Feature / Given / When / Then)',
    'Feature',
    'Background',
    'Scenario',
    'Scenario Outline',
    'Examples',
    'Given',
    'When',
    'Then',
    'And',
    'But',
  );

  /// Construit une langue de mots-clés Gherkin.
  const GherkinKeywordLanguage(
    this.label,
    this.featureKeyword,
    this.backgroundKeyword,
    this.scenarioKeyword,
    this.scenarioOutlineKeyword,
    this.examplesKeyword,
    this.givenKeyword,
    this.whenKeyword,
    this.thenKeyword,
    this.andKeyword,
    this.butKeyword,
  );

  /// Libellé lisible affiché dans le sélecteur de langue Gherkin.
  final String label;

  /// Mot-clé d'en-tête de fonctionnalité (`Fonctionnalité` / `Feature`).
  final String featureKeyword;

  /// Mot-clé de contexte partagé (`Contexte` / `Background`).
  final String backgroundKeyword;

  /// Mot-clé de scénario simple (`Scénario` / `Scenario`).
  final String scenarioKeyword;

  /// Mot-clé de plan de scénario paramétré (`Plan du Scénario` / `Scenario Outline`).
  final String scenarioOutlineKeyword;

  /// Mot-clé de table d'exemples (`Exemples` / `Examples`).
  final String examplesKeyword;

  /// Mot-clé de précondition (`Étant donné` / `Given`).
  final String givenKeyword;

  /// Mot-clé d'événement déclencheur (`Quand` / `When`).
  final String whenKeyword;

  /// Mot-clé de vérification attendue (`Alors` / `Then`).
  final String thenKeyword;

  /// Mot-clé de conjonction positive (`Et` / `And`).
  final String andKeyword;

  /// Mot-clé de conjonction restrictive (`Mais` / `But`).
  final String butKeyword;

  /// Directive d'en-tête Gherkin (`# language: fr` ou `# language: en`).
  String get gherkinHeader => '# language: $name';

  /// Résout la langue Gherkin depuis JSON ou un alias courant, avec repli sur [fr].
  static GherkinKeywordLanguage fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final lang in GherkinKeywordLanguage.values) {
        if (lang.name.toLowerCase() == norm ||
            lang.label.toLowerCase() == norm) {
          return lang;
        }
      }
      switch (norm) {
        case 'en-us':
        case 'en_us':
        case 'en-gb':
        case 'en_gb':
        case 'english':
        case 'anglais':
          return GherkinKeywordLanguage.en;
        case 'fr-fr':
        case 'fr_fr':
        case 'french':
        case 'français':
        case 'francais':
          return GherkinKeywordLanguage.fr;
      }
    }
    return GherkinKeywordLanguage.fr;
  }
}

/// Étapes ordonnées du troisième wizard dédié aux spécifications BDD/Gherkin et TDD.
enum QaForgeStage {
  /// Étape 1 : Jeux de données concrètes, valeurs aux bornes JSON Schema et cas d'erreur RG.
  testFixtures(
    stepNumber: 1,
    shortLabel: 'Jeux d’essais',
    title: 'Jeux de données & Cas aux limites',
    agentTitle: 'Test Strategist & Fixture Designer',
    agentSubtitle:
        'Fixtures nominales, valeurs aux bornes JSON Schema et cas d’erreur RG',
    icon: Icons.dataset_outlined,
  ),

  /// Étape 2 : Fonctionnalités Gherkin BDD exécutables (`.feature`), scénarios et tables d'exemples.
  gherkinFeatures(
    stepNumber: 2,
    shortLabel: 'Gherkin BDD',
    title: 'Features Gherkin BDD (.feature)',
    agentTitle: 'BDD & Gherkin Architect',
    agentSubtitle:
        'Fonctionnalités, Contexte, Scénarios et Plans de Scénario / Exemples',
    icon: Icons.fact_check_outlined,
  ),

  /// Étape 3 : Suites TDD unitaires et contrats techniques (Arrange / Act / Assert).
  tddSuites(
    stepNumber: 3,
    shortLabel: 'Suites TDD',
    title: 'Suites TDD Unitaires & Contrats',
    agentTitle: 'TDD & Contract Engineer',
    agentSubtitle:
        'Cas atomiques Arrange / Act / Assert en progression Red → Green → Refactor',
    icon: Icons.science_outlined,
  ),

  /// Étape 4 : Audit de couverture 360° Métier+UX↔Tests et exports BDD/TDD.
  qaReviewExport(
    stepNumber: 4,
    shortLabel: 'Couverture & Export',
    title: 'Couverture 360° & Export BDD/TDD',
    agentTitle: 'QA Coverage Auditor & Export Lead',
    agentSubtitle:
        'Traçabilité Métier+UX↔Tests, fichiers .feature, fixtures et prompt TDD',
    icon: Icons.verified_rounded,
  );

  /// Construit une étape du wizard QA BDD/TDD.
  const QaForgeStage({
    required this.stepNumber,
    required this.shortLabel,
    required this.title,
    required this.agentTitle,
    required this.agentSubtitle,
    required this.icon,
  });

  /// Numéro d'ordre affiché (`1..4`).
  final int stepNumber;

  /// Libellé compact affiché dans le stepper horizontal.
  final String shortLabel;

  /// Titre complet de l'étape QA.
  final String title;

  /// Nom du rôle de l'agent IA spécialisé associé à cette étape.
  final String agentTitle;

  /// Sous-titre résumant la mission de l'agent IA pour cette étape.
  final String agentSubtitle;

  /// Icône représentative de l'étape dans le stepper.
  final IconData icon;

  /// Étape précédente, ou `null` pour la première étape.
  QaForgeStage? get previous =>
      index > 0 ? QaForgeStage.values[index - 1] : null;

  /// Étape suivante, ou `null` pour la dernière étape.
  QaForgeStage? get next => index < QaForgeStage.values.length - 1
      ? QaForgeStage.values[index + 1]
      : null;

  /// Résout une étape QA depuis son nom JSON ou un alias courant, avec repli sur [testFixtures].
  static QaForgeStage fromJson(Object? raw) {
    if (raw is int) {
      for (final stage in QaForgeStage.values) {
        if (stage.stepNumber == raw) return stage;
      }
      return QaForgeStage.testFixtures;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      for (final stage in QaForgeStage.values) {
        if (stage.name == trimmed) return stage;
      }
      final norm = trimmed.toLowerCase();
      for (final stage in QaForgeStage.values) {
        if (stage.name.toLowerCase() == norm ||
            stage.shortLabel.toLowerCase() == norm ||
            stage.title.toLowerCase() == norm) {
          return stage;
        }
      }
      switch (norm) {
        case '1':
        case 'test_fixtures':
        case 'test-fixtures':
        case 'fixtures':
        case 'fixture':
        case 'datasets':
        case 'jeux_essais':
        case 'jeux-essais':
          return QaForgeStage.testFixtures;
        case '2':
        case 'gherkin_features':
        case 'gherkin-features':
        case 'gherkin':
        case 'bdd':
        case 'features':
        case 'feature':
        case 'scenarios':
          return QaForgeStage.gherkinFeatures;
        case '3':
        case 'tdd_suites':
        case 'tdd-suites':
        case 'tdd':
        case 'suites':
        case 'unit_tests':
        case 'unit-tests':
        case 'contracts':
          return QaForgeStage.tddSuites;
        case '4':
        case 'qa_review_export':
        case 'qa-review-export':
        case 'review_export':
        case 'reviewexport':
        case 'review':
        case 'export':
        case 'coverage':
        case 'audit':
          return QaForgeStage.qaReviewExport;
      }
    }
    return QaForgeStage.testFixtures;
  }
}

/// État conversationnel et statut d'avancement d'une étape du wizard QA BDD/TDD.
@immutable
class QaStageState {
  /// Construit un état d'étape QA immuable.
  QaStageState({
    required this.stage,
    this.status = SpecStageStatus.notStarted,
    List<SpecChatMessage> messages = const <SpecChatMessage>[],
    this.stageSummary = '',
    this.readyToAdvance = false,
  }) : messages = List<SpecChatMessage>.unmodifiable(messages);

  /// Étape du wizard QA concernée.
  final QaForgeStage stage;

  /// Statut d'avancement de l'étape.
  final SpecStageStatus status;

  /// Historique des échanges avec l'agent spécialisé de cette étape.
  final List<SpecChatMessage> messages;

  /// Synthèse consolidée produite à la fin de l'étape pour alimenter les suivantes.
  final String stageSummary;

  /// Vrai lorsque l'agent a indiqué que l'étape peut être validée.
  final bool readyToAdvance;

  /// Vérifie les invariants de l'état d'étape QA.
  void validate() {
    for (final message in messages) {
      if (message.id.trim().isEmpty) {
        throw const FormatException(
          'QaStageState contient un message sans identifiant.',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  QaStageState copyWith({
    QaForgeStage? stage,
    SpecStageStatus? status,
    List<SpecChatMessage>? messages,
    String? stageSummary,
    bool? readyToAdvance,
  }) => QaStageState(
    stage: stage ?? this.stage,
    status: status ?? this.status,
    messages: messages ?? this.messages,
    stageSummary: stageSummary ?? this.stageSummary,
    readyToAdvance: readyToAdvance ?? this.readyToAdvance,
  );

  /// Sérialise l'état de l'étape en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'stage': stage.name,
    'status': status.name,
    'messages': [for (final m in messages) m.toJson()],
    'stageSummary': stageSummary,
    'readyToAdvance': readyToAdvance,
  };

  /// Désérialise un état d'étape QA depuis JSON.
  factory QaStageState.fromJson(
    Object? raw, {
    QaForgeStage fallbackStage = QaForgeStage.testFixtures,
  }) {
    if (raw is! Map) {
      throw const FormatException('QaStageState doit être un objet JSON.');
    }
    final stage = raw['stage'] != null
        ? QaForgeStage.fromJson(raw['stage'])
        : fallbackStage;
    final state = QaStageState(
      stage: stage,
      status: SpecStageStatus.fromJson(raw['status']),
      messages: [
        if (raw['messages'] is List)
          for (final item in raw['messages'] as List)
            SpecChatMessage.fromJson(item),
      ],
      stageSummary: (raw['stageSummary'] as String?) ?? '',
      readyToAdvance: raw['readyToAdvance'] == true,
    );
    state.validate();
    return state;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QaStageState &&
          other.stage == stage &&
          other.status == status &&
          listEquals(other.messages, messages) &&
          other.stageSummary == stageSummary &&
          other.readyToAdvance == readyToAdvance;

  @override
  int get hashCode => Object.hash(
    stage,
    status,
    Object.hashAll(messages),
    stageSummary,
    readyToAdvance,
  );
}
