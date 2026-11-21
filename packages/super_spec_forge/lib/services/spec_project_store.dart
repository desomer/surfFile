/// Persistance locale multi-projets adaptée à Git pour `super_spec_forge` ([SpecProjectStore]).
///
/// Chaque projet est persisté sous `<rootDirectory>/projects/<project-slug>/` :
/// - `project.json` : métadonnées légères du projet ;
/// - `spec/*.json` : domaines (lexique, cadrage, cahier des charges, préférences, cohérence) ;
/// - `spec/business_objects/<slug>.json` : 1 fichier par objet métier (+ `_order.json`) ;
/// - `spec/business_rules/<slug>.json` : 1 fichier par règle de gestion (+ `_order.json`) ;
/// - `chats/*.json` : historique des conversations par étape et chat global ;
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
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_lexicon.dart';
import '../models/spec_stage_chat.dart';
import '../models/spec_vision.dart';
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

  /// Identifiant de format d'un fichier objet métier unitaire.
  static const String businessObjectFormat = 'super_spec_forge.business_object';

  /// Identifiant de format d'un fichier règle de gestion unitaire.
  static const String businessRuleFormat = 'super_spec_forge.business_rule';

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

  Directory _businessObjectsDir(Directory projectDir) => Directory(
    '${_specDir(projectDir).path}${Platform.pathSeparator}business_objects',
  );

  Directory _businessRulesDir(Directory projectDir) => Directory(
    '${_specDir(projectDir).path}${Platform.pathSeparator}business_rules',
  );

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
        final raw = jsonDecode(await _projectManifestFile(cached).readAsString());
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
          prev.currentStage != project.currentStage;
      if (manifestChanged) {
        writes.add(
          _writeJson(_projectManifestFile(projectDir), _manifestToJson(project)),
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

      if (prev == null ||
          !listEquals(prev.businessObjects, project.businessObjects)) {
        writes.add(_syncBusinessObjects(projectDir, project.businessObjects));
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

      final changedStages = <SpecForgeStage>[
        for (final stage in SpecForgeStage.values)
          if (prev == null ||
              prev.stageStateFor(stage) != project.stageStateFor(stage))
            stage,
      ];
      final globalChatChanged =
          prev == null ||
          !listEquals(prev.globalChatMessages, project.globalChatMessages);

      if (changedStages.isNotEmpty || globalChatChanged) {
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
      _persistedSnapshots[project.id] = project;
      await setLastActiveProjectId(project.id);
    });
  }

  Future<void> _syncBusinessObjects(
    Directory projectDir,
    List<BusinessObjectSpec> objects,
  ) async {
    final dir = _businessObjectsDir(projectDir);
    final fileMap = SpecStorageSlug.assignUniqueJsonFiles<BusinessObjectSpec>(
      objects,
      labelFor: (o) =>
          o.technicalName.trim().isNotEmpty ? o.technicalName : o.name,
      idFor: (o) => o.id,
      fallback: 'object',
      separator: '_',
    );

    final writes = <Future<void>>[];
    final keepFiles = <String>{...fileMap.keys};
    final orderFile = File('${dir.path}${Platform.pathSeparator}_order.json');
    if (objects.isNotEmpty) {
      keepFiles.add('_order.json');
      writes.add(
        _writeJson(orderFile, <String, Object?>{
          'format': orderFormat,
          'version': storageVersion,
          'ids': [for (final o in objects) o.id],
        }),
      );
    }

    for (final entry in fileMap.entries) {
      writes.add(
        _writeJson(
          File('${dir.path}${Platform.pathSeparator}${entry.key}'),
          <String, Object?>{
            'format': businessObjectFormat,
            'version': storageVersion,
            'data': entry.value.toJson(),
          },
        ),
      );
    }

    await Future.wait(writes);
    await SpecStorageIo.pruneUnexpectedFiles(dir, keepFiles);
  }

  Future<void> _syncBusinessRules(
    Directory projectDir,
    List<BusinessRuleSpec> rules,
  ) async {
    final dir = _businessRulesDir(projectDir);
    final fileMap = SpecStorageSlug.assignUniqueJsonFiles<BusinessRuleSpec>(
      rules,
      labelFor: (r) =>
          r.code.trim().isNotEmpty ? '${r.code} ${r.title}' : r.title,
      idFor: (r) => r.id,
      fallback: 'rule',
      separator: '-',
    );

    final writes = <Future<void>>[];
    final keepFiles = <String>{...fileMap.keys};
    final orderFile = File('${dir.path}${Platform.pathSeparator}_order.json');
    if (rules.isNotEmpty) {
      keepFiles.add('_order.json');
      writes.add(
        _writeJson(orderFile, <String, Object?>{
          'format': orderFormat,
          'version': storageVersion,
          'ids': [for (final r in rules) r.id],
        }),
      );
    }

    for (final entry in fileMap.entries) {
      writes.add(
        _writeJson(
          File('${dir.path}${Platform.pathSeparator}${entry.key}'),
          <String, Object?>{
            'format': businessRuleFormat,
            'version': storageVersion,
            'data': entry.value.toJson(),
          },
        ),
      );
    }

    await Future.wait(writes);
    await SpecStorageIo.pruneUnexpectedFiles(dir, keepFiles);
  }

  /// Charge un projet depuis son [projectId], ou retourne `null` s'il est introuvable.
  Future<SpecForgeProject?> loadProject(String projectId) {
    return _enqueueProjectOp(projectId, () async {
      final projectDir = await _findExistingProjectDir(projectId);
      if (projectDir == null) return null;
      final manifestFile = _projectManifestFile(projectDir);
      if (!await manifestFile.exists()) return null;

      final manifestRaw = jsonDecode(await manifestFile.readAsString());
      if (manifestRaw is! Map) {
        throw const FormatException('project.json doit être un objet JSON.');
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
      final objectsFuture = _loadSplitEntities<BusinessObjectSpec>(
        _businessObjectsDir(projectDir),
        parseItem: BusinessObjectSpec.fromJson,
        idOf: (o) => o.id,
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
      final stageFutures = <SpecForgeStage, Future<Map<dynamic, dynamic>?>>{
        for (final stage in SpecForgeStage.values)
          stage: _readOptionalJsonMap(_stageChatFile(projectDir, stage)),
      };
      final globalChatFuture = _readOptionalJsonMap(
        _globalChatFile(projectDir),
      );

      final results = await Future.wait<Object?>([
        lexiconFuture,
        visionFuture,
        cdcFuture,
        objectsFuture,
        rulesFuture,
        prefsFuture,
        issuesFuture,
        globalChatFuture,
        for (final stage in SpecForgeStage.values) stageFutures[stage]!,
      ]);

      final lexiconMap = results[0] as Map<dynamic, dynamic>?;
      final visionMap = results[1] as Map<dynamic, dynamic>?;
      final cdcMap = results[2] as Map<dynamic, dynamic>?;
      final businessObjects = results[3] as List<BusinessObjectSpec>;
      final businessRules = results[4] as List<BusinessRuleSpec>;
      final prefsMap = results[5] as Map<dynamic, dynamic>?;
      final issuesMap = results[6] as Map<dynamic, dynamic>?;
      final globalChatMap = results[7] as Map<dynamic, dynamic>?;

      final stageStates = <SpecForgeStage, SpecStageState>{};
      final stageHydrationFutures = <Future<void>>[];
      for (var i = 0; i < SpecForgeStage.values.length; i++) {
        final stage = SpecForgeStage.values[i];
        final rawStageWrapper = results[8 + i] as Map<dynamic, dynamic>?;
        final rawStageData = rawStageWrapper?['data'];
        if (rawStageData != null) {
          stageHydrationFutures.add(
            _deserializeStageState(
              rawStageData,
              fallbackStage: stage,
              attachmentsDir: attachmentsDir,
            ).then((state) => stageStates[stage] = state),
          );
        }
      }

      late final List<SpecChatMessage> globalChatMessages;
      final rawGlobalItems = globalChatMap?['items'];
      await Future.wait([
        ...stageHydrationFutures,
        _deserializeChatMessages(
          rawGlobalItems,
          attachmentsDir: attachmentsDir,
        ).then((msgs) => globalChatMessages = msgs),
      ]);

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
        businessObjects: businessObjects,
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
      );
      project.validate();
      _persistedSnapshots[project.id] = project;
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
      (a, b) => SpecStorageIo.fileNameOf(a.path)
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
      final activeId = await getLastActiveProjectId();
      if (activeId == projectId) {
        await setLastActiveProjectId(null);
      }
    });
  }

  /// Liste tous les projets valides présents sur disque en lisant `project.json`
  /// et en comptant les fichiers sous `spec/business_objects/` et `spec/business_rules/`,
  /// triés du plus récent au plus ancien.
  Future<List<SpecProjectSummary>> listProjects() async {
    if (!await _projectsDir.exists()) return const <SpecProjectSummary>[];
    final summaries = <SpecProjectSummary>[];
    await for (final entity in _projectsDir.list(followLinks: false)) {
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

        final updatedAt =
            _parseDateTime(decoded['updatedAt']) ??
            _parseDateTime(decoded['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final counts = await Future.wait<int>([
          _countJsonEntityFiles(_businessObjectsDir(entity)),
          _countJsonEntityFiles(_businessRulesDir(entity)),
        ]);
        summaries.add(
          SpecProjectSummary(
            id: id,
            name: name,
            initialIdea: initialIdea,
            currentStage: SpecForgeStage.fromJson(decoded['currentStage']),
            updatedAt: updatedAt,
            objectCount: counts[0],
            ruleCount: counts[1],
            folderName: SpecStorageIo.fileNameOf(entity.path),
          ),
        );
      } catch (_) {
        // Ignore un manifeste corrompu sans bloquer les autres projets.
      }
    }
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List<SpecProjectSummary>.unmodifiable(summaries);
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
      };

  Future<Map<dynamic, dynamic>?> _readOptionalJsonMap(File file) async {
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map) return decoded;
    return null;
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
