/// Persistance locale multi-projets adaptée à Git pour `super_spec_forge` ([SpecProjectStore]).
///
/// Chaque projet est persisté sous `<rootDirectory>/projects/<project-slug>/` :
/// - `project.json` : métadonnées légères du projet ;
/// - `spec/*.json` : domaines (lexique, cadrage, cahier des charges, préférences, cohérence) ;
/// - `spec/event_storming/<slug>.es.yaml` : 1 fichier Event Storming DSL v1.0 par Bounded Context (+ `es-dsl.schema.json` et `_order.json`) ;
/// - `spec/business_objects/<slug>.json` : 1 fichier par objet métier (+ `_order.json`) ;
/// - `spec/business_rules/<slug>.json` : 1 fichier par règle de gestion (+ `_order.json`) ;
/// - `ux/navigation.json` : étape UX courante, architecture de navigation et thème visuel ;
/// - `ux/coherence_issues.json` : diagnostics de cohérence Métier↔UX ;
/// - `ux/journeys/<slug>.json` : 1 fichier par parcours utilisateur (+ `_order.json`) ;
/// - `ux/screens/<slug>.json` : 1 fichier par écran UX (+ `_order.json`) ;
/// - `qa/meta.json` : étape QA courante et langue des mots-clés Gherkin ;
/// - `qa/coherence_issues.json` : diagnostics de couverture 360° et cohérence Métier+UX↔QA ;
/// - `qa/fixtures/<slug>.json` : 1 fichier par jeu d'essai QA (+ `_order.json`) ;
/// - `qa/features/<slug>.json` : 1 fichier par fonctionnalité Gherkin BDD (+ `_order.json`) ;
/// - `qa/tdd_suites/<slug>.json` : 1 fichier par suite de tests TDD (+ `_order.json`) ;
/// - `cost/assumptions.json` : étape Coûts courante, devise, TJM, calibres T-shirt, ratios transverses, gains IA et notes d'hypothèses ;
/// - `cost/coherence_issues.json` : diagnostics de cohérence financière et couverture WBS/Run/Risques ;
/// - `cost/wbs/<slug>.json` : 1 fichier par lot de travaux Build WBS (+ `_order.json`) ;
/// - `cost/run/<slug>.json` : 1 fichier par poste récurrent d'exploitation Run / OPEX (+ `_order.json`) ;
/// - `cost/risks/<slug>.json` : 1 fichier par risque budgétaire EMV (+ `_order.json`) ;
/// - `chats/*.json` : historique des conversations par étape (`stage_*.json`, `ux_*.json`, `qa_*.json`, `cost_*.json`) et chat global ;
/// - `attachments/*` : contenu texte ou binaire des pièces jointes externalisées.
///
/// L'état local machine (dernier projet actif) est stocké dans
/// `<rootDirectory>/.local/state.json` (ignoré par Git).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/cost/cost_coherence_issue.dart';
import '../models/cost/cost_forge_spec.dart';
import '../models/cost/cost_forge_stage.dart';
import '../models/cost/cost_risk_item_spec.dart';
import '../models/cost/cost_run_item_spec.dart';
import '../models/cost/cost_wbs_item_spec.dart';
import '../models/event_storming_spec.dart';
import '../models/example_mapping_spec.dart';
import '../models/qa/gherkin_feature_spec.dart';
import '../models/qa/qa_coherence_issue.dart';
import '../models/qa/qa_fixture_spec.dart';
import '../models/qa/qa_forge_spec.dart';
import '../models/qa/qa_forge_stage.dart';
import '../models/qa/tdd_suite_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_lexicon.dart';
import '../models/spec_stage_chat.dart';
import '../models/spec_vision.dart';
import '../models/ux/ux_coherence_issue.dart';
import '../models/ux/ux_forge_spec.dart';
import '../models/ux/ux_forge_stage.dart';
import '../models/ux/ux_journey_spec.dart';
import '../models/ux/ux_navigation_spec.dart';
import '../models/ux/ux_screen_spec.dart';
import 'exporters/event_storming_dsl_codec.dart';
import 'spec_storage_slug.dart';
import 'spec_workspace_store.dart';

/// Métadonnées légères d'un projet sauvegardé sur disque.
@immutable
class SpecProjectSummary {
  /// Construit un résumé de projet.
  const SpecProjectSummary({
    required this.id,
    required this.name,
    required this.initialIdea,
    required this.currentStage,
    required this.updatedAt,
    required this.objectCount,
    required this.ruleCount,
    this.exampleMapCount = 0,
    this.journeyCount = 0,
    this.screenCount = 0,
    this.currentUxStage = UxForgeStage.userJourneys,
    this.featureCount = 0,
    this.tddCaseCount = 0,
    this.currentQaStage = QaForgeStage.testFixtures,
    this.wbsItemCount = 0,
    this.runItemCount = 0,
    this.currentCostStage = CostForgeStage.rateCardAssumptions,
    this.folderName,
  });

  /// Identifiant unique du projet.
  final String id;

  /// Nom du projet.
  final String name;

  /// Idée initiale.
  final String initialIdea;

  /// Étape active lors de la dernière sauvegarde.
  final SpecForgeStage currentStage;

  /// Date de dernière modification.
  final DateTime updatedAt;

  /// Nombre d'objets métiers modélisés.
  final int objectCount;

  /// Nombre de règles de gestion formalisées.
  final int ruleCount;

  /// Nombre de tableaux d'Example Mapping formalisés.
  final int exampleMapCount;

  /// Nombre de parcours utilisateurs UX formalisés.
  final int journeyCount;

  /// Nombre d'écrans UX modélisés.
  final int screenCount;

  /// Étape UX active lors de la dernière sauvegarde.
  final UxForgeStage currentUxStage;

  /// Nombre de fonctionnalités Gherkin BDD formalisées.
  final int featureCount;

  /// Nombre total de cas de tests TDD cumulés.
  final int tddCaseCount;

  /// Étape QA active lors de la dernière sauvegarde.
  final QaForgeStage currentQaStage;

  /// Nombre de lots de travaux Build WBS chiffrés.
  final int wbsItemCount;

  /// Nombre de postes récurrents d'exploitation Run / OPEX.
  final int runItemCount;

  /// Étape Coûts active lors de la dernière sauvegarde.
  final CostForgeStage currentCostStage;

  /// Nom du dossier slug sous `projects/`, si disponible sur disque.
  final String? folderName;
}

/// Magasin disque persistant les projets [SpecForgeProject] en fichiers JSON
/// modulaires et découpés par entité pour faciliter le suivi Git.
class SpecProjectStore {
  /// Crée un store ancré sur [rootDirectory] (ou `~/.super_spec_forge` par défaut).
  SpecProjectStore([Directory? rootDirectory])
    : rootDirectory = rootDirectory ?? defaultRootDirectory();

  /// Identifiant de format du manifeste projet (`project.json`).
  static const String manifestFormat = 'super_spec_forge.project_manifest';

  /// Identifiant de format historique d'un projet complet mono-fichier.
  static const String legacyProjectFormat = 'super_spec_forge.project';

  /// Identifiant de format d'un fichier objet métier unitaire.
  static const String businessObjectFormat = 'super_spec_forge.business_object';

  /// Identifiant de format d'un fichier tableau d'Example Mapping unitaire.
  static const String exampleMapFormat = 'super_spec_forge.example_map';

  /// Identifiant de format d'un fichier règle de gestion unitaire.
  static const String businessRuleFormat = 'super_spec_forge.business_rule';

  /// Identifiant de format de la navigation et de l'étape UX (`ux/navigation.json`).
  static const String uxNavigationFormat = 'super_spec_forge.ux_navigation';

  /// Identifiant de format des diagnostics de cohérence UX (`ux/coherence_issues.json`).
  static const String uxCoherenceIssuesFormat =
      'super_spec_forge.ux_coherence_issues';

  /// Identifiant de format d'un fichier parcours utilisateur UX unitaire (`ux/journeys/*.json`).
  static const String uxJourneyFormat = 'super_spec_forge.ux_journey';

  /// Identifiant de format d'un fichier écran UX unitaire (`ux/screens/*.json`).
  static const String uxScreenFormat = 'super_spec_forge.ux_screen';

  /// Identifiant de format d'un fichier de conversation d'étape UX (`chats/ux_*.json`).
  static const String uxStageChatFormat = 'super_spec_forge.ux_stage_chat';

  /// Identifiant de format des métadonnées QA (`qa/meta.json`).
  static const String qaMetaFormat = 'super_spec_forge.qa_meta';

  /// Identifiant de format des diagnostics de cohérence QA (`qa/coherence_issues.json`).
  static const String qaCoherenceIssuesFormat =
      'super_spec_forge.qa_coherence_issues';

  /// Identifiant de format d'un fichier jeu d'essai QA unitaire (`qa/fixtures/*.json`).
  static const String qaFixtureFormat = 'super_spec_forge.qa_fixture';

  /// Identifiant de format d'un fichier fonctionnalité Gherkin unitaire (`qa/features/*.json`).
  static const String qaFeatureFormat = 'super_spec_forge.qa_feature';

  /// Identifiant de format d'un fichier suite TDD unitaire (`qa/tdd_suites/*.json`).
  static const String qaTddSuiteFormat = 'super_spec_forge.qa_tdd_suite';

  /// Identifiant de format d'un fichier de conversation d'étape QA (`chats/qa_*.json`).
  static const String qaStageChatFormat = 'super_spec_forge.qa_stage_chat';

  /// Identifiant de format des hypothèses et TJM Coûts (`cost/assumptions.json`).
  static const String costAssumptionsFormat =
      'super_spec_forge.cost_assumptions';

  /// Identifiant de format des diagnostics de cohérence Coûts (`cost/coherence_issues.json`).
  static const String costCoherenceIssuesFormat =
      'super_spec_forge.cost_coherence_issues';

  /// Identifiant de format d'un fichier lot Build WBS unitaire (`cost/wbs/*.json`).
  static const String costWbsItemFormat = 'super_spec_forge.cost_wbs_item';

  /// Identifiant de format d'un fichier poste Run / OPEX unitaire (`cost/run/*.json`).
  static const String costRunItemFormat = 'super_spec_forge.cost_run_item';

  /// Identifiant de format d'un fichier risque budgétaire unitaire (`cost/risks/*.json`).
  static const String costRiskItemFormat = 'super_spec_forge.cost_risk_item';

  /// Identifiant de format d'un fichier de conversation d'étape Coûts (`chats/cost_*.json`).
  static const String costStageChatFormat = 'super_spec_forge.cost_stage_chat';

  /// Identifiant de format d'un fichier d'ordre `_order.json`.
  static const String orderFormat = 'super_spec_forge.order';

  /// Version courante du format par dossier.
  static const int storageVersion = 3;

  static final RegExp _safeStorageFileRegex = RegExp(r'^[A-Za-z0-9._-]+$');

  /// Dossier racine du workspace.
  final Directory rootDirectory;

  final Map<String, SpecForgeProject> _persistedSnapshots =
      <String, SpecForgeProject>{};
  final Map<String, Directory> _projectDirsById = <String, Directory>{};
  final Map<String, Future<void>> _writeQueues = <String, Future<void>>{};
  String? _cachedLastActiveProjectId;
  int _tmpCounter = 0;

  /// Dossier par défaut sous le répertoire utilisateur (`~/.super_spec_forge`).
  static Directory defaultRootDirectory() =>
      SpecWorkspaceStore.defaultRootDirectory();

  Directory get _projectsDir =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}projects');

  Directory get _localStateDir =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}.local');

  File get _localStateFile =>
      File('${_localStateDir.path}${Platform.pathSeparator}state.json');

  File _projectManifestFile(Directory projectDir) =>
      File('${projectDir.path}${Platform.pathSeparator}project.json');

  Directory _specDir(Directory projectDir) =>
      Directory('${projectDir.path}${Platform.pathSeparator}spec');

  Directory _eventStormingDir(Directory projectDir) => Directory(
    '${_specDir(projectDir).path}${Platform.pathSeparator}event_storming',
  );

  Directory _businessObjectsDir(Directory projectDir) => Directory(
    '${_specDir(projectDir).path}${Platform.pathSeparator}business_objects',
  );

  Directory _exampleMapsDir(Directory projectDir) => Directory(
    '${_specDir(projectDir).path}${Platform.pathSeparator}example_maps',
  );

  Directory _businessRulesDir(Directory projectDir) => Directory(
    '${_specDir(projectDir).path}${Platform.pathSeparator}business_rules',
  );

  Directory _uxDir(Directory projectDir) =>
      Directory('${projectDir.path}${Platform.pathSeparator}ux');

  File _uxNavigationFile(Directory projectDir) => File(
    '${_uxDir(projectDir).path}${Platform.pathSeparator}navigation.json',
  );

  File _uxCoherenceIssuesFile(Directory projectDir) => File(
    '${_uxDir(projectDir).path}${Platform.pathSeparator}coherence_issues.json',
  );

  Directory _uxJourneysDir(Directory projectDir) =>
      Directory('${_uxDir(projectDir).path}${Platform.pathSeparator}journeys');

  Directory _uxScreensDir(Directory projectDir) =>
      Directory('${_uxDir(projectDir).path}${Platform.pathSeparator}screens');

  Directory _qaDir(Directory projectDir) =>
      Directory('${projectDir.path}${Platform.pathSeparator}qa');

  File _qaMetaFile(Directory projectDir) =>
      File('${_qaDir(projectDir).path}${Platform.pathSeparator}meta.json');

  File _qaCoherenceIssuesFile(Directory projectDir) => File(
    '${_qaDir(projectDir).path}${Platform.pathSeparator}coherence_issues.json',
  );

  Directory _qaFixturesDir(Directory projectDir) =>
      Directory('${_qaDir(projectDir).path}${Platform.pathSeparator}fixtures');

  Directory _qaFeaturesDir(Directory projectDir) =>
      Directory('${_qaDir(projectDir).path}${Platform.pathSeparator}features');

  Directory _qaTddSuitesDir(Directory projectDir) => Directory(
    '${_qaDir(projectDir).path}${Platform.pathSeparator}tdd_suites',
  );

  Directory _costDir(Directory projectDir) =>
      Directory('${projectDir.path}${Platform.pathSeparator}cost');

  File _costAssumptionsFile(Directory projectDir) => File(
    '${_costDir(projectDir).path}${Platform.pathSeparator}assumptions.json',
  );

  File _costCoherenceIssuesFile(Directory projectDir) => File(
    '${_costDir(projectDir).path}${Platform.pathSeparator}coherence_issues.json',
  );

  Directory _costWbsDir(Directory projectDir) =>
      Directory('${_costDir(projectDir).path}${Platform.pathSeparator}wbs');

  Directory _costRunDir(Directory projectDir) =>
      Directory('${_costDir(projectDir).path}${Platform.pathSeparator}run');

  Directory _costRisksDir(Directory projectDir) =>
      Directory('${_costDir(projectDir).path}${Platform.pathSeparator}risks');

  Directory _chatsDir(Directory projectDir) =>
      Directory('${projectDir.path}${Platform.pathSeparator}chats');

  Directory _attachmentsDir(Directory projectDir) =>
      Directory('${projectDir.path}${Platform.pathSeparator}attachments');

  File _lexiconFile(Directory projectDir) =>
      File('${_specDir(projectDir).path}${Platform.pathSeparator}lexicon.json');

  File _visionFile(Directory projectDir) =>
      File('${_specDir(projectDir).path}${Platform.pathSeparator}vision.json');

  File _cahierDesChargesFile(Directory projectDir) => File(
    '${_specDir(projectDir).path}${Platform.pathSeparator}cahier_des_charges.json',
  );

  File _modelPreferencesFile(Directory projectDir) => File(
    '${_specDir(projectDir).path}${Platform.pathSeparator}model_preferences.json',
  );

  File _coherenceIssuesFile(Directory projectDir) => File(
    '${_specDir(projectDir).path}${Platform.pathSeparator}coherence_issues.json',
  );

  File _stageChatFile(Directory projectDir, SpecForgeStage stage) => File(
    '${_chatsDir(projectDir).path}${Platform.pathSeparator}stage_${stage.name}.json',
  );

  File _uxStageChatFile(Directory projectDir, UxForgeStage stage) => File(
    '${_chatsDir(projectDir).path}${Platform.pathSeparator}ux_${stage.name}.json',
  );

  File _qaStageChatFile(Directory projectDir, QaForgeStage stage) => File(
    '${_chatsDir(projectDir).path}${Platform.pathSeparator}qa_${stage.name}.json',
  );

  File _costStageChatFile(Directory projectDir, CostForgeStage stage) => File(
    '${_chatsDir(projectDir).path}${Platform.pathSeparator}cost_${stage.name}.json',
  );

  File _globalChatFile(Directory projectDir) => File(
    '${_chatsDir(projectDir).path}${Platform.pathSeparator}global_chat.json',
  );

  Future<T> _enqueueProjectOp<T>(
    String projectId,
    Future<T> Function() action,
  ) {
    final prev = _writeQueues[projectId] ?? Future<void>.value();
    final completer = Completer<void>();
    final next = prev.catchError((_) {}).then((_) => action());
    _writeQueues[projectId] = completer.future;
    return next.whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (identical(_writeQueues[projectId], completer.future)) {
        _writeQueues.remove(projectId);
      }
    });
  }

  Future<Directory?> _findExistingProjectDir(String projectId) async {
    final cached = _projectDirsById[projectId];
    if (cached != null && await _projectManifestFile(cached).exists()) {
      try {
        final raw = jsonDecode(
          await _projectManifestFile(cached).readAsString(),
        );
        if (raw is Map && (raw['id'] as String?)?.trim() == projectId) {
          return cached;
        }
      } catch (_) {}
      _projectDirsById.remove(projectId);
    }
    if (!await _projectsDir.exists()) return null;
    await for (final entity in _projectsDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final manifest = _projectManifestFile(entity);
      if (!await manifest.exists()) continue;
      try {
        final raw = jsonDecode(await manifest.readAsString());
        if (raw is Map && (raw['id'] as String?)?.trim() == projectId) {
          _projectDirsById[projectId] = entity;
          return entity;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<File?> _findLegacyProjectFile(String projectId) async {
    if (!await _projectsDir.exists()) return null;
    await for (final entity in _projectsDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = SpecStorageIo.fileNameOf(entity.path);
      if (name.contains('.tmp.') || !name.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final raw = jsonDecode(await entity.readAsString());
        if (raw is Map && (raw['id'] as String?)?.trim() == projectId) {
          return entity;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<Set<UxForgeStage>> _findExistingUxChatStages(
    Directory projectDir,
  ) async {
    final chatsDir = _chatsDir(projectDir);
    if (!await chatsDir.exists()) return const <UxForgeStage>{};
    final checks = await Future.wait<bool>([
      for (final stage in UxForgeStage.values)
        _uxStageChatFile(projectDir, stage).exists(),
    ]);
    return <UxForgeStage>{
      for (var i = 0; i < UxForgeStage.values.length; i++)
        if (checks[i]) UxForgeStage.values[i],
    };
  }

  Future<Set<QaForgeStage>> _findExistingQaChatStages(
    Directory projectDir,
  ) async {
    final chatsDir = _chatsDir(projectDir);
    if (!await chatsDir.exists()) return const <QaForgeStage>{};
    final checks = await Future.wait<bool>([
      for (final stage in QaForgeStage.values)
        _qaStageChatFile(projectDir, stage).exists(),
    ]);
    return <QaForgeStage>{
      for (var i = 0; i < QaForgeStage.values.length; i++)
        if (checks[i]) QaForgeStage.values[i],
    };
  }

  Future<Set<CostForgeStage>> _findExistingCostChatStages(
    Directory projectDir,
  ) async {
    final chatsDir = _chatsDir(projectDir);
    if (!await chatsDir.exists()) return const <CostForgeStage>{};
    final checks = await Future.wait<bool>([
      for (final stage in CostForgeStage.values)
        _costStageChatFile(projectDir, stage).exists(),
    ]);
    return <CostForgeStage>{
      for (var i = 0; i < CostForgeStage.values.length; i++)
        if (checks[i]) CostForgeStage.values[i],
    };
  }

  Future<Directory> _resolveOrAllocateProjectDir(
    SpecForgeProject project,
  ) async {
    final existing = await _findExistingProjectDir(project.id);
    if (existing != null) return existing;

    final baseSlug = SpecStorageSlug.slugify(
      project.name,
      fallback: 'project',
      separator: '-',
    );
    var candidateName = baseSlug;
    var candidateDir = Directory(
      '${_projectsDir.path}${Platform.pathSeparator}$candidateName',
    );
    var counter = 2;
    while (await candidateDir.exists()) {
      final manifest = _projectManifestFile(candidateDir);
      if (!await manifest.exists()) {
        final isEmpty = await candidateDir.list(followLinks: false).isEmpty;
        if (isEmpty) break;
      } else {
        try {
          final raw = jsonDecode(await manifest.readAsString());
          if (raw is Map && (raw['id'] as String?)?.trim() == project.id) {
            break;
          }
        } catch (_) {}
      }
      candidateName = '$baseSlug-$counter';
      candidateDir = Directory(
        '${_projectsDir.path}${Platform.pathSeparator}$candidateName',
      );
      counter++;
    }
    _projectDirsById[project.id] = candidateDir;
    return candidateDir;
  }

  /// Sauvegarde incrémentalement et atomiquement les fichiers modifiés de [project],
  /// puis mémorise [project] comme dernier projet actif dans `.local/state.json`.
  Future<void> saveProject(SpecForgeProject project) {
    project.validate();
    return _enqueueProjectOp(project.id, () async {
      final projectDir = await _resolveOrAllocateProjectDir(project);
      final prev = _persistedSnapshots[project.id];

      final writes = <Future<void>>[];

      final manifestChanged =
          prev == null ||
          prev.name != project.name ||
          prev.initialIdea != project.initialIdea ||
          prev.createdAt != project.createdAt ||
          prev.updatedAt != project.updatedAt ||
          prev.currentStage != project.currentStage ||
          prev.exampleMappings.length != project.exampleMappings.length ||
          prev.uxSpec.currentStage != project.uxSpec.currentStage ||
          prev.uxSpec.journeys.length != project.uxSpec.journeys.length ||
          prev.uxSpec.screens.length != project.uxSpec.screens.length ||
          prev.qaSpec.currentStage != project.qaSpec.currentStage ||
          prev.qaSpec.features.length != project.qaSpec.features.length ||
          prev.qaSpec.totalTddCaseCount != project.qaSpec.totalTddCaseCount ||
          prev.costSpec.currentStage != project.costSpec.currentStage ||
          prev.costSpec.wbsItems.length != project.costSpec.wbsItems.length ||
          prev.costSpec.runItems.length != project.costSpec.runItems.length;
      if (manifestChanged) {
        writes.add(
          _writeJson(
            _projectManifestFile(projectDir),
            _manifestToJson(project),
          ),
        );
      }

      if (prev == null || prev.lexicon != project.lexicon) {
        writes.add(
          _writeJson(_lexiconFile(projectDir), <String, Object?>{
            'format': 'super_spec_forge.lexicon',
            'version': storageVersion,
            'data': project.lexicon.toJson(),
          }),
        );
      }

      if (prev == null || prev.vision != project.vision) {
        writes.add(
          _writeJson(_visionFile(projectDir), <String, Object?>{
            'format': 'super_spec_forge.vision',
            'version': storageVersion,
            'data': project.vision.toJson(),
          }),
        );
      }

      if (prev == null || prev.cahierDesCharges != project.cahierDesCharges) {
        writes.add(
          _writeJson(_cahierDesChargesFile(projectDir), <String, Object?>{
            'format': 'super_spec_forge.cahier_des_charges',
            'version': storageVersion,
            'data': project.cahierDesCharges.toJson(),
          }),
        );
      }

      if (prev == null || prev.eventStorming != project.eventStorming) {
        writes.add(_syncEventStorming(projectDir, project.eventStorming));
      }

      if (prev == null ||
          !listEquals(prev.businessObjects, project.businessObjects)) {
        writes.add(_syncBusinessObjects(projectDir, project.businessObjects));
      }

      if (prev == null ||
          !listEquals(prev.exampleMappings, project.exampleMappings)) {
        writes.add(_syncExampleMaps(projectDir, project.exampleMappings));
      }

      if (prev == null ||
          !listEquals(prev.businessRules, project.businessRules)) {
        writes.add(_syncBusinessRules(projectDir, project.businessRules));
      }

      if (prev == null ||
          prev.businessObjectModelPreferences !=
              project.businessObjectModelPreferences) {
        writes.add(
          _writeJson(_modelPreferencesFile(projectDir), <String, Object?>{
            'format': 'super_spec_forge.model_preferences',
            'version': storageVersion,
            'data': project.businessObjectModelPreferences.toJson(),
          }),
        );
      }

      if (prev == null ||
          !listEquals(prev.coherenceIssues, project.coherenceIssues)) {
        writes.add(
          _writeJson(_coherenceIssuesFile(projectDir), <String, Object?>{
            'format': 'super_spec_forge.coherence_issues',
            'version': storageVersion,
            'items': [for (final i in project.coherenceIssues) i.toJson()],
          }),
        );
      }

      final uxHasState =
          project.uxSpec.hasContent || project.uxSpec != UxForgeSpec.empty;
      final prevHadUxState =
          prev != null &&
          (prev.uxSpec.hasContent || prev.uxSpec != UxForgeSpec.empty);
      final uxDirExisted = prevHadUxState || await _uxDir(projectDir).exists();
      final existingUxChatStages = (!uxHasState && !uxDirExisted)
          ? await _findExistingUxChatStages(projectDir)
          : const <UxForgeStage>{};
      final shouldPersistUx =
          uxHasState || uxDirExisted || existingUxChatStages.isNotEmpty;
      final forceInitUx =
          uxHasState && (prev == null || !prevHadUxState || !uxDirExisted);

      if (shouldPersistUx) {
        if (forceInitUx ||
            (uxDirExisted && prev == null) ||
            (prev != null &&
                (prev.uxSpec.currentStage != project.uxSpec.currentStage ||
                    prev.uxSpec.navigation != project.uxSpec.navigation))) {
          writes.add(
            _writeJson(_uxNavigationFile(projectDir), <String, Object?>{
              'format': uxNavigationFormat,
              'version': storageVersion,
              'currentStage': project.uxSpec.currentStage.name,
              'navigation': project.uxSpec.navigation.toJson(),
            }),
          );
        }

        if (forceInitUx ||
            (uxDirExisted && prev == null) ||
            (prev != null &&
                !listEquals(
                  prev.uxSpec.coherenceIssues,
                  project.uxSpec.coherenceIssues,
                ))) {
          writes.add(
            _writeJson(_uxCoherenceIssuesFile(projectDir), <String, Object?>{
              'format': uxCoherenceIssuesFormat,
              'version': storageVersion,
              'items': [
                for (final i in project.uxSpec.coherenceIssues) i.toJson(),
              ],
            }),
          );
        }

        if ((forceInitUx && project.uxSpec.journeys.isNotEmpty) ||
            prev == null ||
            !listEquals(prev.uxSpec.journeys, project.uxSpec.journeys)) {
          writes.add(_syncUxJourneys(projectDir, project.uxSpec.journeys));
        }

        if ((forceInitUx && project.uxSpec.screens.isNotEmpty) ||
            prev == null ||
            !listEquals(prev.uxSpec.screens, project.uxSpec.screens)) {
          writes.add(_syncUxScreens(projectDir, project.uxSpec.screens));
        }
      }

      final qaHasState =
          project.qaSpec.hasContent || project.qaSpec != QaForgeSpec.empty;
      final prevHadQaState =
          prev != null &&
          (prev.qaSpec.hasContent || prev.qaSpec != QaForgeSpec.empty);
      final qaDirExisted = prevHadQaState || await _qaDir(projectDir).exists();
      final existingQaChatStages = (!qaHasState && !qaDirExisted)
          ? await _findExistingQaChatStages(projectDir)
          : const <QaForgeStage>{};
      final shouldPersistQa =
          qaHasState || qaDirExisted || existingQaChatStages.isNotEmpty;
      final forceInitQa =
          qaHasState && (prev == null || !prevHadQaState || !qaDirExisted);

      if (shouldPersistQa) {
        if (forceInitQa ||
            (qaDirExisted && prev == null) ||
            (prev != null &&
                (prev.qaSpec.currentStage != project.qaSpec.currentStage ||
                    prev.qaSpec.gherkinLanguage !=
                        project.qaSpec.gherkinLanguage))) {
          writes.add(
            _writeJson(_qaMetaFile(projectDir), <String, Object?>{
              'format': qaMetaFormat,
              'version': storageVersion,
              'currentStage': project.qaSpec.currentStage.name,
              'gherkinLanguage': project.qaSpec.gherkinLanguage.name,
            }),
          );
        }

        if (forceInitQa ||
            (qaDirExisted && prev == null) ||
            (prev != null &&
                !listEquals(
                  prev.qaSpec.coherenceIssues,
                  project.qaSpec.coherenceIssues,
                ))) {
          writes.add(
            _writeJson(_qaCoherenceIssuesFile(projectDir), <String, Object?>{
              'format': qaCoherenceIssuesFormat,
              'version': storageVersion,
              'items': [
                for (final i in project.qaSpec.coherenceIssues) i.toJson(),
              ],
            }),
          );
        }

        if ((forceInitQa && project.qaSpec.fixtures.isNotEmpty) ||
            prev == null ||
            !listEquals(prev.qaSpec.fixtures, project.qaSpec.fixtures)) {
          writes.add(_syncQaFixtures(projectDir, project.qaSpec.fixtures));
        }

        if ((forceInitQa && project.qaSpec.features.isNotEmpty) ||
            prev == null ||
            !listEquals(prev.qaSpec.features, project.qaSpec.features)) {
          writes.add(_syncQaFeatures(projectDir, project.qaSpec.features));
        }

        if ((forceInitQa && project.qaSpec.tddSuites.isNotEmpty) ||
            prev == null ||
            !listEquals(prev.qaSpec.tddSuites, project.qaSpec.tddSuites)) {
          writes.add(_syncQaTddSuites(projectDir, project.qaSpec.tddSuites));
        }
      }

      final costHasState = project.costSpec.hasContent;
      final prevHadCostState = prev != null && prev.costSpec.hasContent;
      final costDirExisted =
          prevHadCostState || await _costDir(projectDir).exists();
      final existingCostChatStages =
          (!costHasState && !costDirExisted && prev == null)
          ? await _findExistingCostChatStages(projectDir)
          : const <CostForgeStage>{};
      final forceInitCost =
          costHasState &&
          (prev == null || !prevHadCostState || !costDirExisted);
      final shouldPruneEmptyCost =
          !costHasState &&
          (costDirExisted || existingCostChatStages.isNotEmpty);

      if (costHasState) {
        if (forceInitCost ||
            prev == null ||
            !_hasSameCostAssumptions(prev.costSpec, project.costSpec)) {
          writes.add(
            _writeJson(
              _costAssumptionsFile(projectDir),
              _costAssumptionsToJson(project.costSpec),
            ),
          );
        }

        if (forceInitCost ||
            prev == null ||
            !listEquals(
              prev.costSpec.coherenceIssues,
              project.costSpec.coherenceIssues,
            )) {
          writes.add(
            _writeJson(_costCoherenceIssuesFile(projectDir), <String, Object?>{
              'format': costCoherenceIssuesFormat,
              'version': storageVersion,
              'items': [
                for (final i in project.costSpec.coherenceIssues) i.toJson(),
              ],
            }),
          );
        }

        if ((forceInitCost && project.costSpec.wbsItems.isNotEmpty) ||
            prev == null ||
            !listEquals(prev.costSpec.wbsItems, project.costSpec.wbsItems)) {
          writes.add(_syncCostWbs(projectDir, project.costSpec.wbsItems));
        }

        if ((forceInitCost && project.costSpec.runItems.isNotEmpty) ||
            prev == null ||
            !listEquals(prev.costSpec.runItems, project.costSpec.runItems)) {
          writes.add(_syncCostRun(projectDir, project.costSpec.runItems));
        }

        if ((forceInitCost && project.costSpec.riskItems.isNotEmpty) ||
            prev == null ||
            !listEquals(prev.costSpec.riskItems, project.costSpec.riskItems)) {
          writes.add(_syncCostRisks(projectDir, project.costSpec.riskItems));
        }
      } else if (shouldPruneEmptyCost) {
        writes.add(_pruneEmptyCostArtifacts(projectDir));
      }

      final changedStages = <SpecForgeStage>[
        for (final stage in SpecForgeStage.values)
          if (prev == null ||
              prev.stageStateFor(stage) != project.stageStateFor(stage))
            stage,
      ];
      final changedUxStages = !shouldPersistUx
          ? const <UxForgeStage>[]
          : (forceInitUx
                ? UxForgeStage.values
                : (prev == null
                      ? <UxForgeStage>[
                          for (final stage in UxForgeStage.values)
                            if (existingUxChatStages.contains(stage) ||
                                uxDirExisted)
                              stage,
                        ]
                      : <UxForgeStage>[
                          for (final stage in UxForgeStage.values)
                            if (prev.uxSpec.stageStateFor(stage) !=
                                project.uxSpec.stageStateFor(stage))
                              stage,
                        ]));
      final changedQaStages = !shouldPersistQa
          ? const <QaForgeStage>[]
          : (forceInitQa
                ? QaForgeStage.values
                : (prev == null
                      ? <QaForgeStage>[
                          for (final stage in QaForgeStage.values)
                            if (existingQaChatStages.contains(stage) ||
                                qaDirExisted)
                              stage,
                        ]
                      : <QaForgeStage>[
                          for (final stage in QaForgeStage.values)
                            if (prev.qaSpec.stageStateFor(stage) !=
                                project.qaSpec.stageStateFor(stage))
                              stage,
                        ]));
      final changedCostStages = !costHasState
          ? const <CostForgeStage>[]
          : ((forceInitCost || prev == null)
                ? CostForgeStage.values
                : <CostForgeStage>[
                    for (final stage in CostForgeStage.values)
                      if (prev.costSpec.stageStateFor(stage) !=
                          project.costSpec.stageStateFor(stage))
                        stage,
                  ]);
      final globalChatChanged =
          prev == null ||
          !listEquals(prev.globalChatMessages, project.globalChatMessages);

      if (changedStages.isNotEmpty ||
          changedUxStages.isNotEmpty ||
          changedQaStages.isNotEmpty ||
          changedCostStages.isNotEmpty ||
          shouldPruneEmptyCost ||
          globalChatChanged) {
        final attachmentsToWrite = <String, _PendingAttachmentWrite>{};
        for (final stage in changedStages) {
          final state = project.stageStateFor(stage);
          final serializedMessages = <Map<String, Object?>>[
            for (final msg in state.messages)
              _serializeChatMessage(msg, attachmentsToWrite),
          ];
          writes.add(
            _writeJson(_stageChatFile(projectDir, stage), <String, Object?>{
              'format': 'super_spec_forge.stage_chat',
              'version': storageVersion,
              'data': <String, Object?>{
                'stage': state.stage.name,
                'status': state.status.name,
                'messages': serializedMessages,
                'stageSummary': state.stageSummary,
                'readyToAdvance': state.readyToAdvance,
              },
            }),
          );
        }

        for (final stage in changedUxStages) {
          final state = project.uxSpec.stageStateFor(stage);
          final serializedMessages = <Map<String, Object?>>[
            for (final msg in state.messages)
              _serializeChatMessage(msg, attachmentsToWrite),
          ];
          writes.add(
            _writeJson(_uxStageChatFile(projectDir, stage), <String, Object?>{
              'format': uxStageChatFormat,
              'version': storageVersion,
              'data': <String, Object?>{
                'stage': state.stage.name,
                'status': state.status.name,
                'messages': serializedMessages,
                'stageSummary': state.stageSummary,
                'readyToAdvance': state.readyToAdvance,
              },
            }),
          );
        }

        for (final stage in changedQaStages) {
          final state = project.qaSpec.stageStateFor(stage);
          final serializedMessages = <Map<String, Object?>>[
            for (final msg in state.messages)
              _serializeChatMessage(msg, attachmentsToWrite),
          ];
          writes.add(
            _writeJson(_qaStageChatFile(projectDir, stage), <String, Object?>{
              'format': qaStageChatFormat,
              'version': storageVersion,
              'data': <String, Object?>{
                'stage': state.stage.name,
                'status': state.status.name,
                'messages': serializedMessages,
                'stageSummary': state.stageSummary,
                'readyToAdvance': state.readyToAdvance,
              },
            }),
          );
        }

        for (final stage in changedCostStages) {
          final state = project.costSpec.stageStateFor(stage);
          final serializedMessages = <Map<String, Object?>>[
            for (final msg in state.messages)
              _serializeChatMessage(msg, attachmentsToWrite),
          ];
          writes.add(
            _writeJson(_costStageChatFile(projectDir, stage), <String, Object?>{
              'format': costStageChatFormat,
              'version': storageVersion,
              'data': <String, Object?>{
                'stage': state.stage.name,
                'status': state.status.name,
                'messages': serializedMessages,
                'stageSummary': state.stageSummary,
                'readyToAdvance': state.readyToAdvance,
              },
            }),
          );
        }

        if (globalChatChanged) {
          final serializedGlobal = <Map<String, Object?>>[
            for (final msg in project.globalChatMessages)
              _serializeChatMessage(msg, attachmentsToWrite),
          ];
          writes.add(
            _writeJson(_globalChatFile(projectDir), <String, Object?>{
              'format': 'super_spec_forge.global_chat',
              'version': storageVersion,
              'items': serializedGlobal,
            }),
          );
        }

        final attachmentsDir = _attachmentsDir(projectDir);
        for (final entry in attachmentsToWrite.entries) {
          final targetFile = File(
            '${attachmentsDir.path}${Platform.pathSeparator}${entry.key}',
          );
          writes.add(_writeAttachmentIfMissing(targetFile, entry.value));
        }

        writes.add(
          _pruneOrphanAttachments(
            attachmentsDir,
            _collectAllAttachmentFileNames(project),
          ),
        );
      }

      if (writes.isNotEmpty) {
        await Future.wait(writes);
      }
      if (prev == null) {
        final legacyFile = await _findLegacyProjectFile(project.id);
        if (legacyFile != null && await legacyFile.exists()) {
          try {
            await legacyFile.delete();
          } catch (_) {}
        }
      }
      _persistedSnapshots[project.id] = project;
      await setLastActiveProjectId(project.id);
    });
  }

  Future<void> _syncEventStorming(
    Directory projectDir,
    EventStormingSpec spec,
  ) async {
    final dir = _eventStormingDir(projectDir);
    final sep = Platform.pathSeparator;
    final orderFile = File('${dir.path}${sep}_order.json');
    final schemaFile = File(
      '${dir.path}$sep${EventStormingDslCodec.schemaFileName}',
    );

    if (spec.documents.isEmpty) {
      if (await dir.exists()) {
        await SpecStorageIo.pruneUnexpectedFiles(
          dir,
          const <String>{},
          extension: '.es.yaml',
        );
        if (await orderFile.exists()) {
          try {
            await orderFile.delete();
          } catch (_) {}
        }
        if (await schemaFile.exists()) {
          try {
            await schemaFile.delete();
          } catch (_) {}
        }
      }
      return;
    }

    await dir.create(recursive: true);

    final fileMap = <String, EventStormDocument>{};
    final usedLower = <String>{};
    for (final doc in spec.documents) {
      final base = SpecStorageSlug.slugify(
        doc.id.trim().isNotEmpty ? doc.id : doc.meta.boundedContext,
        fallback: 'bounded-context',
        separator: '-',
      );
      var candidate = '$base.es.yaml';
      if (!usedLower.add(candidate.toLowerCase())) {
        var idx = 2;
        while (!usedLower.add('$base-$idx.es.yaml'.toLowerCase())) {
          idx++;
        }
        candidate = '$base-$idx.es.yaml';
      }
      fileMap[candidate] = doc;
    }

    await SpecStorageIo.pruneUnexpectedFiles(
      dir,
      fileMap.keys.toSet(),
      extension: '.es.yaml',
    );

    final writes = <Future<bool>>[
      SpecStorageIo.writeTextAtomicallyIfChanged(
        schemaFile,
        SpecStorageIo.normalizeLf(EventStormingDslCodec.esDslSchemaJson),
        nextTmpId: () => _tmpCounter++,
      ),
      _writeJson(orderFile, <String, Object?>{
        'format': orderFormat,
        'version': storageVersion,
        'ids': [for (final doc in spec.documents) doc.id],
      }),
      for (final entry in fileMap.entries)
        SpecStorageIo.writeTextAtomicallyIfChanged(
          File('${dir.path}$sep${entry.key}'),
          SpecStorageIo.normalizeLf(EventStormingDslCodec.toYaml(entry.value)),
          nextTmpId: () => _tmpCounter++,
        ),
    ];
    await Future.wait(writes);
  }

  Future<EventStormingSpec> _loadEventStorming(Directory projectDir) async {
    final dir = _eventStormingDir(projectDir);
    if (!await dir.exists()) return EventStormingSpec.empty;

    final yamlFiles = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = SpecStorageIo.fileNameOf(entity.path);
      if (name.contains('.tmp.')) continue;
      if (name.toLowerCase().endsWith('.es.yaml')) {
        yamlFiles.add(entity);
      }
    }
    if (yamlFiles.isEmpty) return EventStormingSpec.empty;

    yamlFiles.sort(
      (a, b) => SpecStorageIo.fileNameOf(
        a.path,
      ).toLowerCase().compareTo(SpecStorageIo.fileNameOf(b.path).toLowerCase()),
    );

    final docs = <EventStormDocument>[];
    final usedIds = <String>{};
    for (final file in yamlFiles) {
      final name = SpecStorageIo.fileNameOf(file.path);
      final idHint = name.substring(0, name.length - '.es.yaml'.length);
      final rawText = await file.readAsString();
      var doc = EventStormingDslCodec.fromYaml(rawText, idHint: idHint);
      if (!usedIds.add(doc.id)) {
        var suffix = 2;
        while (!usedIds.add('${doc.id}-$suffix')) {
          suffix++;
        }
        doc = doc.copyWith(id: '${doc.id}-$suffix');
      }
      docs.add(doc);
    }

    final orderFile = File(
      '${dir.path}${Platform.pathSeparator}_order.json',
    );
    final orderMap = await _readOptionalJsonMap(orderFile);
    final orderIds = <String>[
      if (orderMap?['ids'] is List)
        for (final item in orderMap!['ids'] as List)
          if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
    if (orderIds.isNotEmpty) {
      final orderIndex = <String, int>{
        for (var i = 0; i < orderIds.length; i++) orderIds[i]: i,
      };
      docs.sort((a, b) {
        final ia = orderIndex[a.id] ?? 1 << 20;
        final ib = orderIndex[b.id] ?? 1 << 20;
        if (ia != ib) return ia.compareTo(ib);
        return a.id.compareTo(b.id);
      });
    }

    final spec = EventStormingSpec(documents: docs);
    spec.validate();
    return spec;
  }

  Future<void> _syncBusinessObjects(
    Directory projectDir,
    List<BusinessObjectSpec> objects,
  ) => _syncSplitEntities<BusinessObjectSpec>(
    _businessObjectsDir(projectDir),
    objects,
    format: businessObjectFormat,
    labelFor: (o) =>
        o.technicalName.trim().isNotEmpty ? o.technicalName : o.name,
    idFor: (o) => o.id,
    toJson: (o) => o.toJson(),
    fallback: 'object',
    separator: '_',
  );

  Future<void> _syncExampleMaps(
    Directory projectDir,
    List<ExampleMapStory> stories,
  ) => _syncSplitEntities<ExampleMapStory>(
    _exampleMapsDir(projectDir),
    stories,
    format: exampleMapFormat,
    labelFor: (s) =>
        s.code.trim().isNotEmpty ? '${s.code} ${s.title}' : s.title,
    idFor: (s) => s.id,
    toJson: (s) => s.toJson(),
    fallback: 'example-map',
    separator: '-',
  );

  Future<void> _syncBusinessRules(
    Directory projectDir,
    List<BusinessRuleSpec> rules,
  ) => _syncSplitEntities<BusinessRuleSpec>(
    _businessRulesDir(projectDir),
    rules,
    format: businessRuleFormat,
    labelFor: (r) =>
        r.code.trim().isNotEmpty ? '${r.code} ${r.title}' : r.title,
    idFor: (r) => r.id,
    toJson: (r) => r.toJson(),
    fallback: 'rule',
    separator: '-',
  );

  Future<void> _syncUxJourneys(
    Directory projectDir,
    List<UxJourneySpec> journeys,
  ) => _syncSplitEntities<UxJourneySpec>(
    _uxJourneysDir(projectDir),
    journeys,
    format: uxJourneyFormat,
    labelFor: (j) => j.code.trim().isNotEmpty ? '${j.code} ${j.name}' : j.name,
    idFor: (j) => j.id,
    toJson: (j) => j.toJson(),
    fallback: 'journey',
    separator: '-',
  );

  Future<void> _syncUxScreens(
    Directory projectDir,
    List<UxScreenSpec> screens,
  ) => _syncSplitEntities<UxScreenSpec>(
    _uxScreensDir(projectDir),
    screens,
    format: uxScreenFormat,
    labelFor: (s) => s.code.trim().isNotEmpty ? '${s.code} ${s.name}' : s.name,
    idFor: (s) => s.id,
    toJson: (s) => s.toJson(),
    fallback: 'screen',
    separator: '-',
  );

  Future<void> _syncQaFixtures(
    Directory projectDir,
    List<QaFixtureSpec> fixtures,
  ) => _syncSplitEntities<QaFixtureSpec>(
    _qaFixturesDir(projectDir),
    fixtures,
    format: qaFixtureFormat,
    labelFor: (f) => f.code.trim().isNotEmpty ? '${f.code} ${f.name}' : f.name,
    idFor: (f) => f.id,
    toJson: (f) => f.toJson(),
    fallback: 'fixture',
    separator: '-',
  );

  Future<void> _syncQaFeatures(
    Directory projectDir,
    List<GherkinFeatureSpec> features,
  ) => _syncSplitEntities<GherkinFeatureSpec>(
    _qaFeaturesDir(projectDir),
    features,
    format: qaFeatureFormat,
    labelFor: (f) =>
        f.code.trim().isNotEmpty ? '${f.code} ${f.title}' : f.title,
    idFor: (f) => f.id,
    toJson: (f) => f.toJson(),
    fallback: 'feature',
    separator: '-',
  );

  Future<void> _syncQaTddSuites(
    Directory projectDir,
    List<TddTestSuiteSpec> suites,
  ) => _syncSplitEntities<TddTestSuiteSpec>(
    _qaTddSuitesDir(projectDir),
    suites,
    format: qaTddSuiteFormat,
    labelFor: (s) => s.code.trim().isNotEmpty ? '${s.code} ${s.name}' : s.name,
    idFor: (s) => s.id,
    toJson: (s) => s.toJson(),
    fallback: 'tdd-suite',
    separator: '-',
  );

  Future<void> _syncCostWbs(
    Directory projectDir,
    List<CostWbsItemSpec> items,
  ) => _syncSplitEntities<CostWbsItemSpec>(
    _costWbsDir(projectDir),
    items,
    format: costWbsItemFormat,
    labelFor: (w) =>
        w.code.trim().isNotEmpty ? '${w.code} ${w.title}' : w.title,
    idFor: (w) => w.id,
    toJson: (w) => w.toJson(),
    fallback: 'wbs',
    separator: '-',
  );

  Future<void> _syncCostRun(
    Directory projectDir,
    List<CostRunItemSpec> items,
  ) => _syncSplitEntities<CostRunItemSpec>(
    _costRunDir(projectDir),
    items,
    format: costRunItemFormat,
    labelFor: (r) => r.code.trim().isNotEmpty ? '${r.code} ${r.name}' : r.name,
    idFor: (r) => r.id,
    toJson: (r) => r.toJson(),
    fallback: 'run',
    separator: '-',
  );

  Future<void> _syncCostRisks(
    Directory projectDir,
    List<CostRiskItemSpec> items,
  ) => _syncSplitEntities<CostRiskItemSpec>(
    _costRisksDir(projectDir),
    items,
    format: costRiskItemFormat,
    labelFor: (r) =>
        r.code.trim().isNotEmpty ? '${r.code} ${r.title}' : r.title,
    idFor: (r) => r.id,
    toJson: (r) => r.toJson(),
    fallback: 'risk',
    separator: '-',
  );

  Future<void> _pruneEmptyCostArtifacts(Directory projectDir) async {
    final costDir = _costDir(projectDir);
    if (await costDir.exists()) {
      try {
        await costDir.delete(recursive: true);
      } catch (_) {}
    }
    final chatsDir = _chatsDir(projectDir);
    if (await chatsDir.exists()) {
      await Future.wait<void>([
        for (final stage in CostForgeStage.values)
          () async {
            final chatFile = _costStageChatFile(projectDir, stage);
            if (await chatFile.exists()) {
              try {
                await chatFile.delete();
              } catch (_) {}
            }
          }(),
      ]);
    }
  }

  Future<void> _syncSplitEntities<T>(
    Directory dir,
    List<T> items, {
    required String format,
    required String Function(T item) labelFor,
    required String Function(T item) idFor,
    required Map<String, Object?> Function(T item) toJson,
    required String fallback,
    String separator = '-',
  }) async {
    final fileMap = SpecStorageSlug.assignUniqueJsonFiles<T>(
      items,
      labelFor: labelFor,
      idFor: idFor,
      fallback: fallback,
      separator: separator,
    );

    final writes = <Future<void>>[];
    final keepFiles = <String>{...fileMap.keys};
    final orderFile = File('${dir.path}${Platform.pathSeparator}_order.json');
    if (items.isNotEmpty) {
      keepFiles.add('_order.json');
      writes.add(
        _writeJson(orderFile, <String, Object?>{
          'format': orderFormat,
          'version': storageVersion,
          'ids': [for (final item in items) idFor(item)],
        }),
      );
    }

    for (final entry in fileMap.entries) {
      writes.add(
        _writeJson(
          File('${dir.path}${Platform.pathSeparator}${entry.key}'),
          <String, Object?>{
            'format': format,
            'version': storageVersion,
            'data': toJson(entry.value),
          },
        ),
      );
    }

    if (writes.isNotEmpty) {
      await Future.wait(writes);
    }
    await SpecStorageIo.pruneUnexpectedFiles(dir, keepFiles);
  }

  /// Charge un projet depuis son [projectId], ou retourne `null` s'il est introuvable.
  Future<SpecForgeProject?> loadProject(String projectId) {
    return _enqueueProjectOp(projectId, () async {
      final projectDir = await _findExistingProjectDir(projectId);
      if (projectDir == null) {
        final legacyFile = await _findLegacyProjectFile(projectId);
        if (legacyFile == null || !await legacyFile.exists()) return null;
        final legacyRaw = jsonDecode(await legacyFile.readAsString());
        return SpecForgeProject.fromJson(legacyRaw);
      }
      final manifestFile = _projectManifestFile(projectDir);
      if (!await manifestFile.exists()) return null;

      final manifestRaw = jsonDecode(await manifestFile.readAsString());
      if (manifestRaw is! Map) {
        throw const FormatException('project.json doit être un objet JSON.');
      }

      final specDirExists = await _specDir(projectDir).exists();
      final uxDirExists = await _uxDir(projectDir).exists();
      final qaDirExists = await _qaDir(projectDir).exists();
      final costDirExists = await _costDir(projectDir).exists();
      if (!specDirExists &&
          !uxDirExists &&
          !qaDirExists &&
          !costDirExists &&
          (manifestRaw['format'] == legacyProjectFormat ||
              manifestRaw.containsKey('lexicon') ||
              manifestRaw.containsKey('businessObjects'))) {
        return SpecForgeProject.fromJson(manifestRaw);
      }

      final id = (manifestRaw['id'] as String?)?.trim() ?? '';
      final name = (manifestRaw['name'] as String?)?.trim() ?? '';
      final initialIdea = (manifestRaw['initialIdea'] as String?)?.trim() ?? '';
      final now = DateTime.now().toUtc();
      final createdAt = _parseDateTime(manifestRaw['createdAt']) ?? now;
      final updatedAt = _parseDateTime(manifestRaw['updatedAt']) ?? createdAt;
      final currentStage = SpecForgeStage.fromJson(manifestRaw['currentStage']);

      final attachmentsDir = _attachmentsDir(projectDir);

      final lexiconFuture = _readOptionalJsonMap(_lexiconFile(projectDir));
      final visionFuture = _readOptionalJsonMap(_visionFile(projectDir));
      final cdcFuture = _readOptionalJsonMap(_cahierDesChargesFile(projectDir));
      final eventStormingFuture = _loadEventStorming(projectDir);
      final objectsFuture = _loadSplitEntities<BusinessObjectSpec>(
        _businessObjectsDir(projectDir),
        parseItem: BusinessObjectSpec.fromJson,
        idOf: (o) => o.id,
      );
      final exampleMapsFuture = _loadSplitEntities<ExampleMapStory>(
        _exampleMapsDir(projectDir),
        parseItem: ExampleMapStory.fromJson,
        idOf: (s) => s.id,
      );
      final rulesFuture = _loadSplitEntities<BusinessRuleSpec>(
        _businessRulesDir(projectDir),
        parseItem: BusinessRuleSpec.fromJson,
        idOf: (r) => r.id,
      );
      final prefsFuture = _readOptionalJsonMap(
        _modelPreferencesFile(projectDir),
      );
      final issuesFuture = _readOptionalJsonMap(
        _coherenceIssuesFile(projectDir),
      );
      final globalChatFuture = _readOptionalJsonMap(
        _globalChatFile(projectDir),
      );
      final stageFutures = <SpecForgeStage, Future<Map<dynamic, dynamic>?>>{
        for (final stage in SpecForgeStage.values)
          stage: _readOptionalJsonMap(_stageChatFile(projectDir, stage)),
      };

      final uxNavFuture = _readOptionalJsonMap(_uxNavigationFile(projectDir));
      final uxIssuesFuture = _readOptionalJsonValue(
        _uxCoherenceIssuesFile(projectDir),
      );
      final uxJourneysFuture = _loadSplitEntities<UxJourneySpec>(
        _uxJourneysDir(projectDir),
        parseItem: UxJourneySpec.fromJson,
        idOf: (j) => j.id,
      );
      final uxScreensFuture = _loadSplitEntities<UxScreenSpec>(
        _uxScreensDir(projectDir),
        parseItem: UxScreenSpec.fromJson,
        idOf: (s) => s.id,
      );
      final uxStageFutures = <UxForgeStage, Future<Map<dynamic, dynamic>?>>{
        for (final stage in UxForgeStage.values)
          stage: _readOptionalJsonMap(_uxStageChatFile(projectDir, stage)),
      };

      final qaMetaFuture = _readOptionalJsonMap(_qaMetaFile(projectDir));
      final qaIssuesFuture = _readOptionalJsonValue(
        _qaCoherenceIssuesFile(projectDir),
      );
      final qaFixturesFuture = _loadSplitEntities<QaFixtureSpec>(
        _qaFixturesDir(projectDir),
        parseItem: QaFixtureSpec.fromJson,
        idOf: (f) => f.id,
      );
      final qaFeaturesFuture = _loadSplitEntities<GherkinFeatureSpec>(
        _qaFeaturesDir(projectDir),
        parseItem: GherkinFeatureSpec.fromJson,
        idOf: (f) => f.id,
      );
      final qaTddSuitesFuture = _loadSplitEntities<TddTestSuiteSpec>(
        _qaTddSuitesDir(projectDir),
        parseItem: TddTestSuiteSpec.fromJson,
        idOf: (s) => s.id,
      );
      final qaStageFutures = <QaForgeStage, Future<Map<dynamic, dynamic>?>>{
        for (final stage in QaForgeStage.values)
          stage: _readOptionalJsonMap(_qaStageChatFile(projectDir, stage)),
      };

      final costAssumptionsFuture = _readOptionalJsonMap(
        _costAssumptionsFile(projectDir),
      );
      final costIssuesFuture = _readOptionalJsonValue(
        _costCoherenceIssuesFile(projectDir),
      );
      final costWbsFuture = _loadSplitEntities<CostWbsItemSpec>(
        _costWbsDir(projectDir),
        parseItem: CostWbsItemSpec.fromJson,
        idOf: (w) => w.id,
      );
      final costRunFuture = _loadSplitEntities<CostRunItemSpec>(
        _costRunDir(projectDir),
        parseItem: CostRunItemSpec.fromJson,
        idOf: (r) => r.id,
      );
      final costRisksFuture = _loadSplitEntities<CostRiskItemSpec>(
        _costRisksDir(projectDir),
        parseItem: CostRiskItemSpec.fromJson,
        idOf: (r) => r.id,
      );
      final costStageFutures = <CostForgeStage, Future<Map<dynamic, dynamic>?>>{
        for (final stage in CostForgeStage.values)
          stage: _readOptionalJsonMap(_costStageChatFile(projectDir, stage)),
      };

      await Future.wait<Object?>([
        lexiconFuture,
        visionFuture,
        cdcFuture,
        eventStormingFuture,
        objectsFuture,
        exampleMapsFuture,
        rulesFuture,
        prefsFuture,
        issuesFuture,
        globalChatFuture,
        uxNavFuture,
        uxIssuesFuture,
        uxJourneysFuture,
        uxScreensFuture,
        qaMetaFuture,
        qaIssuesFuture,
        qaFixturesFuture,
        qaFeaturesFuture,
        qaTddSuitesFuture,
        costAssumptionsFuture,
        costIssuesFuture,
        costWbsFuture,
        costRunFuture,
        costRisksFuture,
        for (final stage in SpecForgeStage.values) stageFutures[stage]!,
        for (final stage in UxForgeStage.values) uxStageFutures[stage]!,
        for (final stage in QaForgeStage.values) qaStageFutures[stage]!,
        for (final stage in CostForgeStage.values) costStageFutures[stage]!,
      ]);

      final lexiconMap = await lexiconFuture;
      final visionMap = await visionFuture;
      final cdcMap = await cdcFuture;
      final eventStorming = await eventStormingFuture;
      final businessObjects = await objectsFuture;
      final exampleMappings = await exampleMapsFuture;
      final businessRules = await rulesFuture;
      final prefsMap = await prefsFuture;
      final issuesMap = await issuesFuture;
      final globalChatMap = await globalChatFuture;
      final uxNavMap = await uxNavFuture;
      final uxIssuesRaw = await uxIssuesFuture;
      final uxJourneys = await uxJourneysFuture;
      final uxScreens = await uxScreensFuture;
      final qaMetaMap = await qaMetaFuture;
      final qaIssuesRaw = await qaIssuesFuture;
      final qaFixtures = await qaFixturesFuture;
      final qaFeatures = await qaFeaturesFuture;
      final qaTddSuites = await qaTddSuitesFuture;
      final costAssumptionsMap = await costAssumptionsFuture;
      final costIssuesRaw = await costIssuesFuture;
      final costWbsItems = await costWbsFuture;
      final costRunItems = await costRunFuture;
      final costRiskItems = await costRisksFuture;

      final stageStates = <SpecForgeStage, SpecStageState>{};
      final uxStageStates = <UxForgeStage, UxStageState>{};
      final qaStageStates = <QaForgeStage, QaStageState>{};
      final costStageStates = <CostForgeStage, CostStageState>{};
      final hydrationFutures = <Future<void>>[];
      for (final stage in SpecForgeStage.values) {
        final rawStageWrapper = await stageFutures[stage]!;
        final rawStageData = rawStageWrapper?['data'];
        if (rawStageData != null) {
          hydrationFutures.add(
            _deserializeStageState(
              rawStageData,
              fallbackStage: stage,
              attachmentsDir: attachmentsDir,
            ).then((state) => stageStates[stage] = state),
          );
        }
      }

      for (final stage in UxForgeStage.values) {
        final rawUxWrapper = await uxStageFutures[stage]!;
        if (rawUxWrapper != null) {
          final rawUxData = rawUxWrapper['data'] is Map
              ? rawUxWrapper['data']
              : rawUxWrapper;
          hydrationFutures.add(
            _deserializeUxStageState(
              rawUxData,
              fallbackStage: stage,
              attachmentsDir: attachmentsDir,
            ).then((state) => uxStageStates[stage] = state),
          );
        }
      }

      for (final stage in QaForgeStage.values) {
        final rawQaWrapper = await qaStageFutures[stage]!;
        if (rawQaWrapper != null) {
          final rawQaData = rawQaWrapper['data'] is Map
              ? rawQaWrapper['data']
              : rawQaWrapper;
          hydrationFutures.add(
            _deserializeQaStageState(
              rawQaData,
              fallbackStage: stage,
              attachmentsDir: attachmentsDir,
            ).then((state) => qaStageStates[stage] = state),
          );
        }
      }

      for (final stage in CostForgeStage.values) {
        final rawCostWrapper = await costStageFutures[stage]!;
        if (rawCostWrapper != null) {
          final rawCostData = rawCostWrapper['data'] is Map
              ? rawCostWrapper['data']
              : rawCostWrapper;
          hydrationFutures.add(
            _deserializeCostStageState(
              rawCostData,
              fallbackStage: stage,
              attachmentsDir: attachmentsDir,
            ).then((state) => costStageStates[stage] = state),
          );
        }
      }

      late final List<SpecChatMessage> globalChatMessages;
      final rawGlobalItems = globalChatMap?['items'];
      await Future.wait([
        ...hydrationFutures,
        _deserializeChatMessages(
          rawGlobalItems,
          attachmentsDir: attachmentsDir,
        ).then((msgs) => globalChatMessages = msgs),
      ]);

      final hasModularUx =
          uxDirExists ||
          uxNavMap != null ||
          uxIssuesRaw != null ||
          uxJourneys.isNotEmpty ||
          uxScreens.isNotEmpty ||
          uxStageStates.isNotEmpty;

      final UxForgeSpec uxSpec;
      var loadedFromLegacyInlineUx = false;
      if (hasModularUx) {
        final rawCurrentUxStage =
            uxNavMap?['currentStage'] ??
            (uxNavMap?['data'] is Map
                ? (uxNavMap!['data'] as Map)['currentStage']
                : null) ??
            manifestRaw['currentUxStage'];
        uxSpec = UxForgeSpec(
          currentStage: UxForgeStage.fromJson(rawCurrentUxStage),
          journeys: uxJourneys,
          navigation: UxNavigationSpec.fromJson(
            _extractUxNavigationPayload(uxNavMap),
          ),
          screens: uxScreens,
          stageStates: uxStageStates,
          coherenceIssues: _parseUxCoherenceIssues(uxIssuesRaw),
        );
      } else if (manifestRaw['uxSpec'] != null) {
        uxSpec = UxForgeSpec.fromJson(manifestRaw['uxSpec']);
        loadedFromLegacyInlineUx = uxSpec != UxForgeSpec.empty;
      } else if (manifestRaw['currentUxStage'] != null) {
        uxSpec = UxForgeSpec(
          currentStage: UxForgeStage.fromJson(manifestRaw['currentUxStage']),
        );
        loadedFromLegacyInlineUx = uxSpec != UxForgeSpec.empty;
      } else {
        uxSpec = UxForgeSpec.empty;
      }

      final hasModularQa =
          qaDirExists ||
          qaMetaMap != null ||
          qaIssuesRaw != null ||
          qaFixtures.isNotEmpty ||
          qaFeatures.isNotEmpty ||
          qaTddSuites.isNotEmpty ||
          qaStageStates.isNotEmpty;

      final QaForgeSpec qaSpec;
      var loadedFromLegacyInlineQa = false;
      if (hasModularQa) {
        final rawCurrentQaStage =
            qaMetaMap?['currentStage'] ??
            (qaMetaMap?['data'] is Map
                ? (qaMetaMap!['data'] as Map)['currentStage']
                : null) ??
            manifestRaw['currentQaStage'];
        final rawGherkinLanguage =
            qaMetaMap?['gherkinLanguage'] ??
            (qaMetaMap?['data'] is Map
                ? (qaMetaMap!['data'] as Map)['gherkinLanguage']
                : null);
        qaSpec = QaForgeSpec(
          currentStage: QaForgeStage.fromJson(rawCurrentQaStage),
          gherkinLanguage: GherkinKeywordLanguage.fromJson(rawGherkinLanguage),
          fixtures: _deduplicateById(
            qaFixtures,
            idOf: (f) => f.id,
            withId: (f, id) => f.copyWith(id: id),
          ),
          features: _deduplicateById(
            qaFeatures,
            idOf: (f) => f.id,
            withId: (f, id) => f.copyWith(id: id),
          ),
          tddSuites: _deduplicateById(
            qaTddSuites,
            idOf: (s) => s.id,
            withId: (s, id) => s.copyWith(id: id),
          ),
          stageStates: qaStageStates,
          coherenceIssues: _parseQaCoherenceIssues(qaIssuesRaw),
        );
      } else if (manifestRaw['qaSpec'] != null) {
        qaSpec = QaForgeSpec.fromJson(manifestRaw['qaSpec']);
        loadedFromLegacyInlineQa = qaSpec != QaForgeSpec.empty;
      } else if (manifestRaw['currentQaStage'] != null) {
        qaSpec = QaForgeSpec(
          currentStage: QaForgeStage.fromJson(manifestRaw['currentQaStage']),
        );
        loadedFromLegacyInlineQa = qaSpec != QaForgeSpec.empty;
      } else {
        qaSpec = QaForgeSpec.empty;
      }

      final hasModularCost =
          costDirExists ||
          costAssumptionsMap != null ||
          costIssuesRaw != null ||
          costWbsItems.isNotEmpty ||
          costRunItems.isNotEmpty ||
          costRiskItems.isNotEmpty ||
          costStageStates.isNotEmpty;

      final CostForgeSpec costSpec;
      var loadedFromLegacyInlineCost = false;
      if (hasModularCost) {
        final baseCostSpec = CostForgeSpec.fromJson(
          _extractCostAssumptionsPayload(
            costAssumptionsMap,
            fallbackStage: manifestRaw['currentCostStage'],
          ),
        );
        costSpec = baseCostSpec.copyWith(
          wbsItems: _deduplicateById(
            costWbsItems,
            idOf: (w) => w.id,
            withId: (w, id) => w.copyWith(id: id),
          ),
          runItems: _deduplicateById(
            costRunItems,
            idOf: (r) => r.id,
            withId: (r, id) => r.copyWith(id: id),
          ),
          riskItems: _deduplicateById(
            costRiskItems,
            idOf: (r) => r.id,
            withId: (r, id) => r.copyWith(id: id),
          ),
          stageStates: costStageStates,
          coherenceIssues: _parseCostCoherenceIssues(costIssuesRaw),
        );
      } else if (manifestRaw['costSpec'] != null) {
        costSpec = CostForgeSpec.fromJson(manifestRaw['costSpec']);
        loadedFromLegacyInlineCost = costSpec.hasContent;
      } else if (manifestRaw['currentCostStage'] != null) {
        costSpec = CostForgeSpec(
          currentStage: CostForgeStage.fromJson(
            manifestRaw['currentCostStage'],
          ),
        );
        loadedFromLegacyInlineCost = costSpec.hasContent;
      } else {
        costSpec = CostForgeSpec.empty;
      }

      final rawIssues = issuesMap?['items'];

      final project = SpecForgeProject(
        id: id,
        name: name,
        initialIdea: initialIdea,
        createdAt: createdAt,
        updatedAt: updatedAt,
        currentStage: currentStage,
        lexicon: SpecLexicon.fromJson(lexiconMap?['data']),
        vision: SpecVision.fromJson(visionMap?['data']),
        cahierDesCharges: SpecCahierDesCharges.fromJson(cdcMap?['data']),
        eventStorming: eventStorming,
        businessObjects: businessObjects,
        exampleMappings: exampleMappings,
        businessRules: businessRules,
        businessObjectModelPreferences: BusinessObjectModelPreferences.fromJson(
          prefsMap?['data'],
        ),
        stageStates: stageStates,
        coherenceIssues: [
          if (rawIssues is List)
            for (final item in rawIssues) SpecCoherenceIssue.fromJson(item),
        ],
        globalChatMessages: globalChatMessages,
        uxSpec: uxSpec,
        qaSpec: qaSpec,
        costSpec: costSpec,
      );
      project.validate();
      if (specDirExists &&
          !loadedFromLegacyInlineUx &&
          !loadedFromLegacyInlineQa &&
          !loadedFromLegacyInlineCost) {
        _persistedSnapshots[project.id] = project;
      }
      return project;
    });
  }

  Future<List<T>> _loadSplitEntities<T>(
    Directory dir, {
    required T Function(Object? raw) parseItem,
    required String Function(T item) idOf,
  }) async {
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = SpecStorageIo.fileNameOf(entity.path);
      if (name.contains('.tmp.') || !name.toLowerCase().endsWith('.json')) {
        continue;
      }
      if (name == '_order.json') continue;
      files.add(entity);
    }
    files.sort(
      (a, b) =>
          SpecStorageIo.fileNameOf(a.path)
              .toLowerCase()
              .compareTo(SpecStorageIo.fileNameOf(b.path).toLowerCase()),
    );

    final parsedByFile = await Future.wait<T>(
      files.map((file) async {
        final decoded = jsonDecode(await file.readAsString());
        final payload = (decoded is Map && decoded['data'] is Map)
            ? decoded['data']
            : decoded;
        return parseItem(payload);
      }),
    );

    final orderFile = File('${dir.path}${Platform.pathSeparator}_order.json');
    if (!await orderFile.exists()) {
      return parsedByFile;
    }
    try {
      final rawOrder = jsonDecode(await orderFile.readAsString());
      final ids = rawOrder is Map ? rawOrder['ids'] : null;
      if (ids is! List) return parsedByFile;

      final byId = <String, T>{
        for (final item in parsedByFile) idOf(item): item,
      };
      final ordered = <T>[];
      final placed = <String>{};
      for (final rawId in ids) {
        if (rawId is! String) continue;
        final item = byId[rawId];
        if (item != null && placed.add(rawId)) {
          ordered.add(item);
        }
      }
      for (final item in parsedByFile) {
        if (placed.add(idOf(item))) {
          ordered.add(item);
        }
      }
      return ordered;
    } catch (_) {
      return parsedByFile;
    }
  }

  /// Supprime définitivement un projet du disque.
  Future<void> deleteProject(String projectId) {
    return _enqueueProjectOp(projectId, () async {
      _persistedSnapshots.remove(projectId);
      final dir = await _findExistingProjectDir(projectId);
      _projectDirsById.remove(projectId);
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
      final legacyFile = await _findLegacyProjectFile(projectId);
      if (legacyFile != null && await legacyFile.exists()) {
        await legacyFile.delete();
      }
      final activeId = await getLastActiveProjectId();
      if (activeId == projectId) {
        await setLastActiveProjectId(null);
      }
    });
  }

  /// Liste tous les projets valides présents sur disque en lisant `project.json`
  /// et en comptant les fichiers sous `spec/`, `ux/`, `qa/` et `cost/` (avec repli sur le manifeste),
  /// triés du plus récent au plus ancien.
  Future<List<SpecProjectSummary>> listProjects() async {
    if (!await _projectsDir.exists()) return const <SpecProjectSummary>[];
    final summaries = <SpecProjectSummary>[];
    final seenIds = <String>{};
    final legacyFiles = <File>[];
    await for (final entity in _projectsDir.list(followLinks: false)) {
      if (entity is File) {
        final fileName = SpecStorageIo.fileNameOf(entity.path);
        if (!fileName.contains('.tmp.') &&
            fileName.toLowerCase().endsWith('.json')) {
          legacyFiles.add(entity);
        }
        continue;
      }
      if (entity is! Directory) continue;
      final manifest = _projectManifestFile(entity);
      if (!await manifest.exists()) continue;
      try {
        final decoded = jsonDecode(await manifest.readAsString());
        if (decoded is! Map) continue;
        final id = (decoded['id'] as String?)?.trim() ?? '';
        final name = (decoded['name'] as String?)?.trim() ?? '';
        final initialIdea = (decoded['initialIdea'] as String?)?.trim() ?? '';
        if (id.isEmpty || name.isEmpty || initialIdea.isEmpty) continue;
        _projectDirsById[id] = entity;
        seenIds.add(id);

        final updatedAt =
            _parseDateTime(decoded['updatedAt']) ??
            _parseDateTime(decoded['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final rawUxSpec = decoded['uxSpec'] is Map
            ? decoded['uxSpec'] as Map
            : null;
        final rawQaSpec = decoded['qaSpec'] is Map
            ? decoded['qaSpec'] as Map
            : null;
        final rawCostSpec = decoded['costSpec'] is Map
            ? decoded['costSpec'] as Map
            : null;
        final resolvedMeta = await Future.wait<Object>([
          _resolveSummaryCount(
            _businessObjectsDir(entity),
            decoded['objectCount'],
            fallbackList: decoded['businessObjects'],
          ),
          _resolveSummaryCount(
            _businessRulesDir(entity),
            decoded['ruleCount'],
            fallbackList: decoded['businessRules'],
          ),
          _resolveSummaryCount(
            _uxJourneysDir(entity),
            decoded['journeyCount'],
            fallbackList: rawUxSpec?['journeys'],
          ),
          _resolveSummaryCount(
            _uxScreensDir(entity),
            decoded['screenCount'],
            fallbackList: rawUxSpec?['screens'],
          ),
          _resolveSummaryUxStage(entity, decoded),
          _resolveSummaryCount(
            _qaFeaturesDir(entity),
            decoded['featureCount'],
            fallbackList: rawQaSpec?['features'],
          ),
          _resolveSummaryTddCaseCount(
            entity,
            decoded,
            fallbackSuites: rawQaSpec?['tddSuites'],
          ),
          _resolveSummaryQaStage(entity, decoded),
          _resolveSummaryCount(
            _exampleMapsDir(entity),
            decoded['exampleMapCount'],
            fallbackList: decoded['exampleMappings'],
          ),
          _resolveSummaryCount(
            _costWbsDir(entity),
            decoded['wbsItemCount'],
            fallbackList: rawCostSpec?['wbsItems'],
          ),
          _resolveSummaryCount(
            _costRunDir(entity),
            decoded['runItemCount'],
            fallbackList: rawCostSpec?['runItems'],
          ),
          _resolveSummaryCostStage(entity, decoded),
        ]);
        summaries.add(
          SpecProjectSummary(
            id: id,
            name: name,
            initialIdea: initialIdea,
            currentStage: SpecForgeStage.fromJson(decoded['currentStage']),
            updatedAt: updatedAt,
            objectCount: resolvedMeta[0] as int,
            ruleCount: resolvedMeta[1] as int,
            exampleMapCount: resolvedMeta[8] as int,
            journeyCount: resolvedMeta[2] as int,
            screenCount: resolvedMeta[3] as int,
            currentUxStage: resolvedMeta[4] as UxForgeStage,
            featureCount: resolvedMeta[5] as int,
            tddCaseCount: resolvedMeta[6] as int,
            currentQaStage: resolvedMeta[7] as QaForgeStage,
            wbsItemCount: resolvedMeta[9] as int,
            runItemCount: resolvedMeta[10] as int,
            currentCostStage: resolvedMeta[11] as CostForgeStage,
            folderName: SpecStorageIo.fileNameOf(entity.path),
          ),
        );
      } catch (_) {
        // Ignore un manifeste corrompu sans bloquer les autres projets.
      }
    }

    for (final file in legacyFiles) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final id = (decoded['id'] as String?)?.trim() ?? '';
        final name = (decoded['name'] as String?)?.trim() ?? '';
        final initialIdea = (decoded['initialIdea'] as String?)?.trim() ?? '';
        if (id.isEmpty ||
            name.isEmpty ||
            initialIdea.isEmpty ||
            !seenIds.add(id)) {
          continue;
        }
        final updatedAt =
            _parseDateTime(decoded['updatedAt']) ??
            _parseDateTime(decoded['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final rawUxSpec = decoded['uxSpec'] is Map
            ? decoded['uxSpec'] as Map
            : null;
        final rawQaSpec = decoded['qaSpec'] is Map
            ? decoded['qaSpec'] as Map
            : null;
        final rawCostSpec = decoded['costSpec'] is Map
            ? decoded['costSpec'] as Map
            : null;
        summaries.add(
          SpecProjectSummary(
            id: id,
            name: name,
            initialIdea: initialIdea,
            currentStage: SpecForgeStage.fromJson(decoded['currentStage']),
            updatedAt: updatedAt,
            objectCount: _parseManifestCount(
              decoded['objectCount'],
              fallbackList: decoded['businessObjects'],
            ),
            ruleCount: _parseManifestCount(
              decoded['ruleCount'],
              fallbackList: decoded['businessRules'],
            ),
            journeyCount: _parseManifestCount(
              decoded['journeyCount'],
              fallbackList: rawUxSpec?['journeys'],
            ),
            screenCount: _parseManifestCount(
              decoded['screenCount'],
              fallbackList: rawUxSpec?['screens'],
            ),
            currentUxStage: UxForgeStage.fromJson(
              decoded['currentUxStage'] ?? rawUxSpec?['currentStage'],
            ),
            featureCount: _parseManifestCount(
              decoded['featureCount'],
              fallbackList: rawQaSpec?['features'],
            ),
            tddCaseCount: _parseManifestTddCaseCount(
              decoded['tddCaseCount'],
              fallbackSuites: rawQaSpec?['tddSuites'],
            ),
            currentQaStage: QaForgeStage.fromJson(
              decoded['currentQaStage'] ?? rawQaSpec?['currentStage'],
            ),
            wbsItemCount: _parseManifestCount(
              decoded['wbsItemCount'],
              fallbackList: rawCostSpec?['wbsItems'],
            ),
            runItemCount: _parseManifestCount(
              decoded['runItemCount'],
              fallbackList: rawCostSpec?['runItems'],
            ),
            currentCostStage: CostForgeStage.fromJson(
              decoded['currentCostStage'] ?? rawCostSpec?['currentStage'],
            ),
          ),
        );
      } catch (_) {}
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List<SpecProjectSummary>.unmodifiable(summaries);
  }

  Future<int> _resolveSummaryCount(
    Directory dir,
    Object? manifestCount, {
    Object? fallbackList,
  }) async {
    if (await dir.exists()) {
      return _countJsonEntityFiles(dir);
    }
    return _parseManifestCount(manifestCount, fallbackList: fallbackList);
  }

  Future<UxForgeStage> _resolveSummaryUxStage(
    Directory projectDir,
    Map<dynamic, dynamic> manifest,
  ) async {
    final navFile = _uxNavigationFile(projectDir);
    if (await navFile.exists()) {
      try {
        final navRaw = jsonDecode(await navFile.readAsString());
        if (navRaw is Map) {
          final rawStage =
              navRaw['currentStage'] ??
              (navRaw['data'] is Map
                  ? (navRaw['data'] as Map)['currentStage']
                  : null);
          if (rawStage != null) {
            return UxForgeStage.fromJson(rawStage);
          }
        }
      } catch (_) {}
    }
    final rawUxSpec = manifest['uxSpec'] is Map
        ? manifest['uxSpec'] as Map
        : null;
    return UxForgeStage.fromJson(
      manifest['currentUxStage'] ?? rawUxSpec?['currentStage'],
    );
  }

  Future<QaForgeStage> _resolveSummaryQaStage(
    Directory projectDir,
    Map<dynamic, dynamic> manifest,
  ) async {
    final metaFile = _qaMetaFile(projectDir);
    if (await metaFile.exists()) {
      try {
        final metaRaw = jsonDecode(await metaFile.readAsString());
        if (metaRaw is Map) {
          final rawStage =
              metaRaw['currentStage'] ??
              (metaRaw['data'] is Map
                  ? (metaRaw['data'] as Map)['currentStage']
                  : null);
          if (rawStage != null) {
            return QaForgeStage.fromJson(rawStage);
          }
        }
      } catch (_) {}
    }
    final rawQaSpec = manifest['qaSpec'] is Map
        ? manifest['qaSpec'] as Map
        : null;
    return QaForgeStage.fromJson(
      manifest['currentQaStage'] ?? rawQaSpec?['currentStage'],
    );
  }

  Future<CostForgeStage> _resolveSummaryCostStage(
    Directory projectDir,
    Map<dynamic, dynamic> manifest,
  ) async {
    final assumptionsFile = _costAssumptionsFile(projectDir);
    if (await assumptionsFile.exists()) {
      try {
        final assumptionsRaw = jsonDecode(await assumptionsFile.readAsString());
        if (assumptionsRaw is Map) {
          final rawStage =
              assumptionsRaw['currentStage'] ??
              (assumptionsRaw['data'] is Map
                  ? (assumptionsRaw['data'] as Map)['currentStage']
                  : null);
          if (rawStage != null) {
            return CostForgeStage.fromJson(rawStage);
          }
        }
      } catch (_) {}
    }
    final rawCostSpec = manifest['costSpec'] is Map
        ? manifest['costSpec'] as Map
        : null;
    return CostForgeStage.fromJson(
      manifest['currentCostStage'] ?? rawCostSpec?['currentStage'],
    );
  }

  Future<int> _resolveSummaryTddCaseCount(
    Directory projectDir,
    Map<dynamic, dynamic> manifest, {
    Object? fallbackSuites,
  }) async {
    final rawCount = manifest['tddCaseCount'];
    final parsed = switch (rawCount) {
      final int v => v,
      final num v => v.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };
    if (parsed != null && parsed >= 0) return parsed;
    final tddSuitesDir = _qaTddSuitesDir(projectDir);
    if (await tddSuitesDir.exists()) {
      var total = 0;
      await for (final entity in tddSuitesDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = SpecStorageIo.fileNameOf(entity.path);
        if (name == '_order.json' ||
            name.contains('.tmp.') ||
            !name.toLowerCase().endsWith('.json')) {
          continue;
        }
        try {
          final raw = jsonDecode(await entity.readAsString());
          final payload = (raw is Map && raw['data'] is Map)
              ? raw['data'] as Map
              : raw;
          if (payload is Map && payload['cases'] is List) {
            total += (payload['cases'] as List).length;
          }
        } catch (_) {}
      }
      return total;
    }
    return _countInlineTddCases(fallbackSuites);
  }

  static int _parseManifestTddCaseCount(
    Object? rawCount, {
    Object? fallbackSuites,
  }) {
    final parsed = switch (rawCount) {
      final int v => v,
      final num v => v.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };
    if (parsed != null && parsed >= 0) return parsed;
    return _countInlineTddCases(fallbackSuites);
  }

  static int _countInlineTddCases(Object? rawSuites) {
    if (rawSuites is! List) return 0;
    var total = 0;
    for (final suite in rawSuites) {
      if (suite is Map && suite['cases'] is List) {
        total += (suite['cases'] as List).length;
      }
    }
    return total;
  }

  static int _parseManifestCount(Object? raw, {Object? fallbackList}) {
    final parsed = switch (raw) {
      final int v => v,
      final num v => v.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };
    if (parsed != null && parsed >= 0) return parsed;
    if (fallbackList is List) return fallbackList.length;
    return 0;
  }

  Future<int> _countJsonEntityFiles(Directory dir) async {
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = SpecStorageIo.fileNameOf(entity.path);
      if (name == '_order.json' ||
          name.contains('.tmp.') ||
          !name.toLowerCase().endsWith('.json')) {
        continue;
      }
      count++;
    }
    return count;
  }

  /// Lit l'identifiant du dernier projet ouvert depuis `.local/state.json`, ou `null`.
  Future<String?> getLastActiveProjectId() async {
    if (!await _localStateFile.exists()) return null;
    try {
      final decoded = jsonDecode(await _localStateFile.readAsString());
      if (decoded is Map && decoded['lastActiveProjectId'] is String) {
        final id = (decoded['lastActiveProjectId'] as String).trim();
        final resolved = id.isEmpty ? null : id;
        _cachedLastActiveProjectId = resolved;
        return resolved;
      }
    } catch (_) {}
    return null;
  }

  /// Mémorise l'identifiant du dernier projet actif dans `.local/state.json`.
  Future<void> setLastActiveProjectId(String? projectId) async {
    if (_cachedLastActiveProjectId == projectId &&
        await _localStateFile.exists()) {
      return;
    }
    final payload = <String, Object?>{'lastActiveProjectId': projectId};
    await _writeJson(_localStateFile, payload);
    _cachedLastActiveProjectId = projectId;
  }

  Map<String, Object?> _manifestToJson(SpecForgeProject project) =>
      <String, Object?>{
        'format': manifestFormat,
        'version': storageVersion,
        'id': project.id,
        'name': project.name,
        'initialIdea': project.initialIdea,
        'createdAt': project.createdAt.toUtc().toIso8601String(),
        'updatedAt': project.updatedAt.toUtc().toIso8601String(),
        'currentStage': project.currentStage.name,
        'exampleMapCount': project.exampleMappings.length,
        'currentUxStage': project.uxSpec.currentStage.name,
        'journeyCount': project.uxSpec.journeys.length,
        'screenCount': project.uxSpec.screens.length,
        'currentQaStage': project.qaSpec.currentStage.name,
        'featureCount': project.qaSpec.features.length,
        'tddCaseCount': project.qaSpec.totalTddCaseCount,
        'currentCostStage': project.costSpec.currentStage.name,
        'wbsItemCount': project.costSpec.wbsItems.length,
        'runItemCount': project.costSpec.runItems.length,
      };

  Map<String, Object?> _costAssumptionsToJson(CostForgeSpec costSpec) =>
      <String, Object?>{
        'format': costAssumptionsFormat,
        'version': storageVersion,
        'currentStage': costSpec.currentStage.name,
        'currency': costSpec.currency.name,
        'hoursPerDay': costSpec.hoursPerDay,
        'deliveryMode': costSpec.deliveryMode.name,
        'targetUsersCount': costSpec.targetUsersCount,
        'profiles': [for (final p in costSpec.profiles) p.toJson()],
        'tshirtPresets': [for (final t in costSpec.tshirtPresets) t.toJson()],
        'transverseRatios': costSpec.transverseRatios.toJson(),
        'aiProductivity': costSpec.aiProductivity.toJson(),
        'assumptionsNotes': costSpec.assumptionsNotes,
      };

  static bool _hasSameCostAssumptions(CostForgeSpec a, CostForgeSpec b) =>
      a.currentStage == b.currentStage &&
      a.currency == b.currency &&
      a.hoursPerDay == b.hoursPerDay &&
      a.deliveryMode == b.deliveryMode &&
      a.targetUsersCount == b.targetUsersCount &&
      listEquals(a.profiles, b.profiles) &&
      listEquals(a.tshirtPresets, b.tshirtPresets) &&
      a.transverseRatios == b.transverseRatios &&
      a.aiProductivity == b.aiProductivity &&
      a.assumptionsNotes == b.assumptionsNotes;

  static Map<String, Object?> _extractCostAssumptionsPayload(
    Map<dynamic, dynamic>? raw, {
    Object? fallbackStage,
  }) {
    if (raw == null) {
      return <String, Object?>{
        'currentStage': ?fallbackStage,
      };
    }
    final source = raw['data'] is Map ? raw['data'] as Map : raw;
    final resolvedStage =
        source['currentStage'] ?? raw['currentStage'] ?? fallbackStage;
    return <String, Object?>{
      for (final entry in source.entries)
        if (entry.key is String) entry.key as String: entry.value,
      'currentStage': ?resolvedStage,
    };
  }

  Future<Map<dynamic, dynamic>?> _readOptionalJsonMap(File file) async {
    final decoded = await _readOptionalJsonValue(file);
    if (decoded is Map) return decoded;
    return null;
  }

  Future<Object?> _readOptionalJsonValue(File file) async {
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  }

  static Object? _extractUxNavigationPayload(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    if (raw['navigation'] != null) return raw['navigation'];
    if (raw['data'] is Map) {
      final data = raw['data'] as Map;
      return data['navigation'] ?? data;
    }
    if (raw.containsKey('shellPattern') ||
        raw.containsKey('routes') ||
        raw.containsKey('visualTheme')) {
      return raw;
    }
    return null;
  }

  static List<UxCoherenceIssue> _parseUxCoherenceIssues(Object? raw) {
    final Object? items = switch (raw) {
      final List<dynamic> list => list,
      final Map<dynamic, dynamic> map =>
        map['items'] ?? map['coherenceIssues'] ?? map['data'],
      _ => null,
    };
    if (items is! List || items.isEmpty) {
      return const <UxCoherenceIssue>[];
    }
    final parsed = <UxCoherenceIssue>[];
    final seenIds = <String>{};
    for (final item in items) {
      var issue = UxCoherenceIssue.fromJson(item);
      if (!seenIds.add(issue.id)) {
        var suffix = 2;
        while (!seenIds.add('${issue.id}_$suffix')) {
          suffix++;
        }
        issue = issue.copyWith(id: '${issue.id}_$suffix');
      }
      parsed.add(issue);
    }
    return parsed;
  }

  static List<QaCoherenceIssue> _parseQaCoherenceIssues(Object? raw) {
    final Object? items = switch (raw) {
      final List<dynamic> list => list,
      final Map<dynamic, dynamic> map =>
        map['items'] ?? map['coherenceIssues'] ?? map['data'],
      _ => null,
    };
    if (items is! List || items.isEmpty) {
      return const <QaCoherenceIssue>[];
    }
    final parsed = <QaCoherenceIssue>[];
    final seenIds = <String>{};
    for (final item in items) {
      var issue = QaCoherenceIssue.fromJson(item);
      if (!seenIds.add(issue.id)) {
        var suffix = 2;
        while (!seenIds.add('${issue.id}_$suffix')) {
          suffix++;
        }
        issue = issue.copyWith(id: '${issue.id}_$suffix');
      }
      parsed.add(issue);
    }
    return parsed;
  }

  static List<CostCoherenceIssue> _parseCostCoherenceIssues(Object? raw) {
    final Object? items = switch (raw) {
      final List<dynamic> list => list,
      final Map<dynamic, dynamic> map =>
        map['items'] ?? map['coherenceIssues'] ?? map['data'],
      _ => null,
    };
    if (items is! List || items.isEmpty) {
      return const <CostCoherenceIssue>[];
    }
    final parsed = <CostCoherenceIssue>[];
    final seenIds = <String>{};
    for (final item in items) {
      var issue = CostCoherenceIssue.fromJson(item);
      if (!seenIds.add(issue.id)) {
        var suffix = 2;
        while (!seenIds.add('${issue.id}_$suffix')) {
          suffix++;
        }
        issue = issue.copyWith(id: '${issue.id}_$suffix');
      }
      parsed.add(issue);
    }
    return parsed;
  }

  static List<T> _deduplicateById<T>(
    List<T> items, {
    required String Function(T item) idOf,
    required T Function(T item, String newId) withId,
  }) {
    if (items.length <= 1) return items;
    final seenIds = <String>{};
    var hasDuplicates = false;
    for (final item in items) {
      if (!seenIds.add(idOf(item))) {
        hasDuplicates = true;
        break;
      }
    }
    if (!hasDuplicates) return items;
    seenIds.clear();
    final deduplicated = <T>[];
    for (final item in items) {
      final baseId = idOf(item);
      if (seenIds.add(baseId)) {
        deduplicated.add(item);
      } else {
        var suffix = 2;
        while (!seenIds.add('${baseId}_$suffix')) {
          suffix++;
        }
        deduplicated.add(withId(item, '${baseId}_$suffix'));
      }
    }
    return deduplicated;
  }

  Map<String, Object?> _serializeChatMessage(
    SpecChatMessage message,
    Map<String, _PendingAttachmentWrite> attachmentsToWrite,
  ) {
    final json = message.toJson();
    if (message.attachments.isEmpty) return json;
    final externalized = <Map<String, Object?>>[];
    for (final attachment in message.attachments) {
      final descriptor = _describeAttachment(attachment);
      if (descriptor.bytes.isNotEmpty || descriptor.isText) {
        attachmentsToWrite[descriptor.fileName] = descriptor;
      }
      externalized.add(<String, Object?>{
        'name': attachment.name,
        'mimeType': attachment.mimeType,
        if (attachment.path != null) 'path': attachment.path,
        'isText': descriptor.isText,
        if (!descriptor.isText && attachment.textContent != null)
          'textContent': attachment.textContent,
        if (descriptor.bytes.isNotEmpty || descriptor.isText)
          'storageFile': descriptor.fileName,
      });
    }
    json['attachments'] = externalized;
    return json;
  }

  Future<SpecStageState> _deserializeStageState(
    Object? raw, {
    required SpecForgeStage fallbackStage,
    required Directory attachmentsDir,
  }) async {
    if (raw is! Map) {
      return SpecStageState(stage: fallbackStage);
    }
    final messages = await _deserializeChatMessages(
      raw['messages'],
      attachmentsDir: attachmentsDir,
    );
    return SpecStageState(
      stage: raw['stage'] != null
          ? SpecForgeStage.fromJson(raw['stage'])
          : fallbackStage,
      status: SpecStageStatus.fromJson(raw['status']),
      messages: messages,
      stageSummary: (raw['stageSummary'] as String?) ?? '',
      readyToAdvance: raw['readyToAdvance'] == true,
    );
  }

  Future<UxStageState> _deserializeUxStageState(
    Object? raw, {
    required UxForgeStage fallbackStage,
    required Directory attachmentsDir,
  }) async {
    if (raw is! Map) {
      return UxStageState(stage: fallbackStage);
    }
    final messages = await _deserializeChatMessages(
      raw['messages'],
      attachmentsDir: attachmentsDir,
    );
    final state = UxStageState(
      stage: raw['stage'] != null
          ? UxForgeStage.fromJson(raw['stage'])
          : fallbackStage,
      status: SpecStageStatus.fromJson(raw['status']),
      messages: messages,
      stageSummary: (raw['stageSummary'] as String?) ?? '',
      readyToAdvance: raw['readyToAdvance'] == true,
    );
    state.validate();
    return state;
  }

  Future<QaStageState> _deserializeQaStageState(
    Object? raw, {
    required QaForgeStage fallbackStage,
    required Directory attachmentsDir,
  }) async {
    if (raw is! Map) {
      return QaStageState(stage: fallbackStage);
    }
    final messages = await _deserializeChatMessages(
      raw['messages'],
      attachmentsDir: attachmentsDir,
    );
    final state = QaStageState(
      stage: raw['stage'] != null
          ? QaForgeStage.fromJson(raw['stage'])
          : fallbackStage,
      status: SpecStageStatus.fromJson(raw['status']),
      messages: messages,
      stageSummary: (raw['stageSummary'] as String?) ?? '',
      readyToAdvance: raw['readyToAdvance'] == true,
    );
    state.validate();
    return state;
  }

  Future<CostStageState> _deserializeCostStageState(
    Object? raw, {
    required CostForgeStage fallbackStage,
    required Directory attachmentsDir,
  }) async {
    if (raw is! Map) {
      return CostStageState(stage: fallbackStage);
    }
    final messages = await _deserializeChatMessages(
      raw['messages'],
      attachmentsDir: attachmentsDir,
    );
    final state = CostStageState(
      stage: raw['stage'] != null
          ? CostForgeStage.fromJson(raw['stage'])
          : fallbackStage,
      status: SpecStageStatus.fromJson(raw['status']),
      messages: messages,
      stageSummary: (raw['stageSummary'] as String?) ?? '',
      readyToAdvance: raw['readyToAdvance'] == true,
    );
    state.validate();
    return state;
  }

  Future<List<SpecChatMessage>> _deserializeChatMessages(
    Object? rawList, {
    required Directory attachmentsDir,
  }) async {
    if (rawList is! List || rawList.isEmpty) {
      return const <SpecChatMessage>[];
    }
    return Future.wait<SpecChatMessage>([
      for (final rawMsg in rawList)
        _deserializeChatMessage(rawMsg, attachmentsDir: attachmentsDir),
    ]);
  }

  Future<SpecChatMessage> _deserializeChatMessage(
    Object? raw, {
    required Directory attachmentsDir,
  }) async {
    if (raw is! Map) {
      throw const FormatException('SpecChatMessage doit être un objet JSON.');
    }
    final rawAttachments = raw['attachments'];
    if (rawAttachments is! List || rawAttachments.isEmpty) {
      return SpecChatMessage.fromJson(raw);
    }

    final strippedMap = <Object?, Object?>{
      for (final entry in raw.entries)
        if (entry.key != 'attachments') entry.key: entry.value,
    };
    final baseMessage = SpecChatMessage.fromJson(strippedMap);
    final hydratedAttachments = <VibeChatAttachment>[];

    for (final rawAtt in rawAttachments) {
      if (rawAtt is! Map) continue;
      final storageFile = rawAtt['storageFile'];
      if (storageFile is String &&
          storageFile.isNotEmpty &&
          _isSafeStorageFileName(storageFile)) {
        final name = rawAtt['name'];
        final mimeType = rawAtt['mimeType'];
        if (name is! String || name.isEmpty || mimeType is! String) continue;
        final path = rawAtt['path'] is String ? rawAtt['path'] as String : null;
        final isText = rawAtt['isText'] == true;
        final file = File(
          '${attachmentsDir.path}${Platform.pathSeparator}$storageFile',
        );
        if (await file.exists()) {
          if (isText) {
            final content = await file.readAsString();
            hydratedAttachments.add(
              VibeChatAttachment.text(
                name: name,
                content: content,
                mimeType: mimeType,
                path: path,
              ),
            );
          } else {
            final bytes = await file.readAsBytes();
            hydratedAttachments.add(
              VibeChatAttachment(
                name: name,
                mimeType: mimeType,
                bytes: Uint8List.fromList(bytes),
                textContent: rawAtt['textContent'] is String
                    ? rawAtt['textContent'] as String
                    : null,
                path: path,
              ),
            );
          }
        } else {
          hydratedAttachments.add(
            VibeChatAttachment(
              name: name,
              mimeType: mimeType,
              bytes: Uint8List(0),
              path: path,
            ),
          );
        }
      } else {
        // Repli si la pièce jointe est déjà inline (sans storageFile) ou vide.
        final parsed = SpecChatMessage.fromJson(<String, Object?>{
          'id': baseMessage.id,
          'isUser': baseMessage.isUser,
          'text': baseMessage.text,
          'attachments': [rawAtt],
        });
        hydratedAttachments.addAll(parsed.attachments);
      }
    }

    return baseMessage.copyWith(attachments: hydratedAttachments);
  }

  _PendingAttachmentWrite _describeAttachment(VibeChatAttachment attachment) {
    final text = attachment.textContent;
    final encodedText = text == null ? null : utf8.encode(text);
    final isText =
        text != null &&
        encodedText != null &&
        listEquals(attachment.bytes, encodedText);
    final bytes = isText ? Uint8List.fromList(encodedText) : attachment.bytes;
    final fileName = _attachmentFileName(bytes, isText: isText);
    return _PendingAttachmentWrite(
      fileName: fileName,
      isText: isText,
      textContent: isText ? text : null,
      bytes: bytes,
    );
  }

  Set<String> _collectAllAttachmentFileNames(SpecForgeProject project) {
    final files = <String>{};
    for (final stageState in project.stageStates.values) {
      for (final msg in stageState.messages) {
        for (final att in msg.attachments) {
          final desc = _describeAttachment(att);
          if (desc.bytes.isNotEmpty || desc.isText) {
            files.add(desc.fileName);
          }
        }
      }
    }
    for (final uxStageState in project.uxSpec.stageStates.values) {
      for (final msg in uxStageState.messages) {
        for (final att in msg.attachments) {
          final desc = _describeAttachment(att);
          if (desc.bytes.isNotEmpty || desc.isText) {
            files.add(desc.fileName);
          }
        }
      }
    }
    for (final qaStageState in project.qaSpec.stageStates.values) {
      for (final msg in qaStageState.messages) {
        for (final att in msg.attachments) {
          final desc = _describeAttachment(att);
          if (desc.bytes.isNotEmpty || desc.isText) {
            files.add(desc.fileName);
          }
        }
      }
    }
    for (final costStageState in project.costSpec.stageStates.values) {
      for (final msg in costStageState.messages) {
        for (final att in msg.attachments) {
          final desc = _describeAttachment(att);
          if (desc.bytes.isNotEmpty || desc.isText) {
            files.add(desc.fileName);
          }
        }
      }
    }
    for (final msg in project.globalChatMessages) {
      for (final att in msg.attachments) {
        final desc = _describeAttachment(att);
        if (desc.bytes.isNotEmpty || desc.isText) {
          files.add(desc.fileName);
        }
      }
    }
    return files;
  }

  Future<void> _writeAttachmentIfMissing(
    File targetFile,
    _PendingAttachmentWrite pending,
  ) async {
    if (await targetFile.exists()) return;
    if (pending.isText && pending.textContent != null) {
      await SpecStorageIo.writeTextAtomicallyIfChanged(
        targetFile,
        SpecStorageIo.normalizeLf(pending.textContent!, trailingNewline: false),
        nextTmpId: () => _tmpCounter++,
      );
    } else {
      await SpecStorageIo.writeBytesAtomically(
        targetFile,
        pending.bytes,
        nextTmpId: () => _tmpCounter++,
      );
    }
  }

  Future<void> _pruneOrphanAttachments(
    Directory attachmentsDir,
    Set<String> referencedFiles,
  ) async {
    if (!await attachmentsDir.exists()) return;
    await for (final entity in attachmentsDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = SpecStorageIo.fileNameOf(entity.path);
      if (name.contains('.tmp.')) continue;
      if (!referencedFiles.contains(name)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  static bool _isSafeStorageFileName(String name) =>
      _safeStorageFileRegex.hasMatch(name) && !name.contains('..');

  static String _attachmentFileName(Uint8List bytes, {required bool isText}) {
    var h0 = 0x811c9dc5;
    var h1 = 0x9e3779b9;
    var h2 = 0x85ebca6b;
    var h3 = 0xc2b2ae35;
    final tag = isText ? 1 : 0;
    h0 = ((h0 ^ tag) * 0x01000193) & 0xffffffff;
    h1 = ((h1 ^ (bytes.length & 0xff)) * 0x01000193) & 0xffffffff;
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      h0 = ((h0 ^ b) * 0x01000193) & 0xffffffff;
      h1 = ((h1 + b + ((h0 >> 16) & 0xffff)) * 0x85ebca6b) & 0xffffffff;
      h2 = ((h2 ^ ((b << (i % 8)) ^ i)) * 0xc2b2ae35) & 0xffffffff;
      h3 = ((h3 + (h1 ^ h2 ^ b)) * 0x27d4eb2f) & 0xffffffff;
    }
    String hex32(int v) => v.toRadixString(16).padLeft(8, '0');
    final ext = isText ? 'txt' : 'bin';
    return 'att_${bytes.length}_${hex32(h0)}${hex32(h1)}${hex32(h2)}${hex32(h3)}.$ext';
  }

  Future<bool> _writeJson(File target, Object? payload) =>
      SpecStorageIo.writeJsonAtomicallyIfChanged(
        target,
        payload,
        nextTmpId: () => _tmpCounter++,
      );

  static DateTime? _parseDateTime(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }
}

class _PendingAttachmentWrite {
  const _PendingAttachmentWrite({
    required this.fileName,
    required this.isText,
    required this.textContent,
    required this.bytes,
  });

  final String fileName;
  final bool isText;
  final String? textContent;
  final Uint8List bytes;
}
