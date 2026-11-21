/// Persistance locale multi-projets sur disque pour `super_spec_forge` ([SpecProjectStore]).
///
/// Chaque projet est persisté sous `<rootDirectory>/projects/<projectId>/` selon
/// un découpage modulaire par domaine et conversations :
/// - `manifest.json` : métadonnées légères et compteurs lus par [SpecProjectStore.listProjects] ;
/// - `spec/*.json` : domaines métier (lexique, cadrage, cahier des charges, objets, règles, préférences, cohérence) ;
/// - `chats/*.json` : historique des conversations par étape et chat global ;
/// - `attachments/*` : contenu texte ou binaire des pièces jointes externalisées.
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
}

/// Magasin disque persistant les projets [SpecForgeProject] en fichiers JSON modulaires.
class SpecProjectStore {
  /// Crée un store ancré sur [rootDirectory] (ou `~/.super_spec_forge` par défaut).
  SpecProjectStore([Directory? rootDirectory])
    : rootDirectory = rootDirectory ?? defaultRootDirectory();

  /// Identifiant de format du manifeste projet (`manifest.json`).
  static const String manifestFormat = 'super_spec_forge.manifest';

  /// Version courante du format multi-fichiers.
  static const int storageVersion = 2;

  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');
  static final RegExp _safeStorageFileRegex = RegExp(r'^[A-Za-z0-9._-]+$');

  /// Dossier racine du magasin.
  final Directory rootDirectory;

  final Map<String, SpecForgeProject> _persistedSnapshots =
      <String, SpecForgeProject>{};
  final Map<String, Future<void>> _writeQueues = <String, Future<void>>{};
  String? _cachedLastActiveProjectId;
  int _tmpCounter = 0;

  /// Dossier par défaut sous le répertoire utilisateur (`~/.super_spec_forge`).
  static Directory defaultRootDirectory() {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final sep = Platform.pathSeparator;
    final cleanHome = home.endsWith(sep) && home.length > 1
        ? home.substring(0, home.length - 1)
        : home;
    return Directory('$cleanHome$sep.super_spec_forge');
  }

  Directory get _projectsDir =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}projects');

  File get _indexFile =>
      File('${rootDirectory.path}${Platform.pathSeparator}index.json');

  String _safeProjectId(String projectId) =>
      projectId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Directory _projectDir(String projectId) => Directory(
    '${_projectsDir.path}${Platform.pathSeparator}${_safeProjectId(projectId)}',
  );

  File _manifestFile(Directory projectDir) =>
      File('${projectDir.path}${Platform.pathSeparator}manifest.json');

  Directory _specDir(Directory projectDir) =>
      Directory('${projectDir.path}${Platform.pathSeparator}spec');

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

  File _businessObjectsFile(Directory projectDir) => File(
    '${_specDir(projectDir).path}${Platform.pathSeparator}business_objects.json',
  );

  File _businessRulesFile(Directory projectDir) => File(
    '${_specDir(projectDir).path}${Platform.pathSeparator}business_rules.json',
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

  /// Sauvegarde incrémentalement et atomiquement les partitions modifiées de [project],
  /// puis mémorise [project] comme dernier projet actif.
  Future<void> saveProject(SpecForgeProject project) {
    project.validate();
    return _enqueueProjectOp(project.id, () async {
      final projectDir = _projectDir(project.id);
      final prev = _persistedSnapshots[project.id];

      final writes = <Future<void>>[];

      final manifestChanged =
          prev == null ||
          prev.name != project.name ||
          prev.initialIdea != project.initialIdea ||
          prev.createdAt != project.createdAt ||
          prev.updatedAt != project.updatedAt ||
          prev.currentStage != project.currentStage ||
          prev.businessObjects.length != project.businessObjects.length ||
          prev.businessRules.length != project.businessRules.length;
      if (manifestChanged) {
        writes.add(
          _writeJsonAtomically(
            _manifestFile(projectDir),
            _manifestToJson(project),
          ),
        );
      }

      if (prev == null || prev.lexicon != project.lexicon) {
        writes.add(
          _writeJsonAtomically(_lexiconFile(projectDir), <String, Object?>{
            'format': 'super_spec_forge.lexicon',
            'version': storageVersion,
            'data': project.lexicon.toJson(),
          }),
        );
      }

      if (prev == null || prev.vision != project.vision) {
        writes.add(
          _writeJsonAtomically(_visionFile(projectDir), <String, Object?>{
            'format': 'super_spec_forge.vision',
            'version': storageVersion,
            'data': project.vision.toJson(),
          }),
        );
      }

      if (prev == null || prev.cahierDesCharges != project.cahierDesCharges) {
        writes.add(
          _writeJsonAtomically(
            _cahierDesChargesFile(projectDir),
            <String, Object?>{
              'format': 'super_spec_forge.cahier_des_charges',
              'version': storageVersion,
              'data': project.cahierDesCharges.toJson(),
            },
          ),
        );
      }

      if (prev == null ||
          !listEquals(prev.businessObjects, project.businessObjects)) {
        writes.add(
          _writeJsonAtomically(
            _businessObjectsFile(projectDir),
            <String, Object?>{
              'format': 'super_spec_forge.business_objects',
              'version': storageVersion,
              'items': [for (final o in project.businessObjects) o.toJson()],
            },
          ),
        );
      }

      if (prev == null ||
          !listEquals(prev.businessRules, project.businessRules)) {
        writes.add(
          _writeJsonAtomically(
            _businessRulesFile(projectDir),
            <String, Object?>{
              'format': 'super_spec_forge.business_rules',
              'version': storageVersion,
              'items': [for (final r in project.businessRules) r.toJson()],
            },
          ),
        );
      }

      if (prev == null ||
          prev.businessObjectModelPreferences !=
              project.businessObjectModelPreferences) {
        writes.add(
          _writeJsonAtomically(
            _modelPreferencesFile(projectDir),
            <String, Object?>{
              'format': 'super_spec_forge.model_preferences',
              'version': storageVersion,
              'data': project.businessObjectModelPreferences.toJson(),
            },
          ),
        );
      }

      if (prev == null ||
          !listEquals(prev.coherenceIssues, project.coherenceIssues)) {
        writes.add(
          _writeJsonAtomically(
            _coherenceIssuesFile(projectDir),
            <String, Object?>{
              'format': 'super_spec_forge.coherence_issues',
              'version': storageVersion,
              'items': [for (final i in project.coherenceIssues) i.toJson()],
            },
          ),
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
            _writeJsonAtomically(
              _stageChatFile(projectDir, stage),
              <String, Object?>{
                'format': 'super_spec_forge.stage_chat',
                'version': storageVersion,
                'data': <String, Object?>{
                  'stage': state.stage.name,
                  'status': state.status.name,
                  'messages': serializedMessages,
                  'stageSummary': state.stageSummary,
                  'readyToAdvance': state.readyToAdvance,
                },
              },
            ),
          );
        }

        if (globalChatChanged) {
          final serializedGlobal = <Map<String, Object?>>[
            for (final msg in project.globalChatMessages)
              _serializeChatMessage(msg, attachmentsToWrite),
          ];
          writes.add(
            _writeJsonAtomically(
              _globalChatFile(projectDir),
              <String, Object?>{
                'format': 'super_spec_forge.global_chat',
                'version': storageVersion,
                'items': serializedGlobal,
              },
            ),
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

  /// Charge un projet depuis son [projectId], ou retourne `null` s'il est introuvable.
  Future<SpecForgeProject?> loadProject(String projectId) {
    return _enqueueProjectOp(projectId, () async {
      final projectDir = _projectDir(projectId);
      final manifestFile = _manifestFile(projectDir);
      if (!await manifestFile.exists()) return null;

      final manifestRaw = jsonDecode(await manifestFile.readAsString());
      if (manifestRaw is! Map) {
        throw const FormatException('manifest.json doit être un objet JSON.');
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
      final objectsFuture = _readOptionalJsonMap(
        _businessObjectsFile(projectDir),
      );
      final rulesFuture = _readOptionalJsonMap(_businessRulesFile(projectDir));
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
      final objectsMap = results[3] as Map<dynamic, dynamic>?;
      final rulesMap = results[4] as Map<dynamic, dynamic>?;
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

      final rawObjects = objectsMap?['items'];
      final rawRules = rulesMap?['items'];
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
        businessObjects: [
          if (rawObjects is List)
            for (final item in rawObjects) BusinessObjectSpec.fromJson(item),
        ],
        businessRules: [
          if (rawRules is List)
            for (final item in rawRules) BusinessRuleSpec.fromJson(item),
        ],
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

  /// Supprime définitivement un projet du disque.
  Future<void> deleteProject(String projectId) {
    return _enqueueProjectOp(projectId, () async {
      _persistedSnapshots.remove(projectId);
      final dir = _projectDir(projectId);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      final activeId = await getLastActiveProjectId();
      if (activeId == projectId) {
        await setLastActiveProjectId(null);
      }
    });
  }

  /// Liste tous les projets valides présents sur disque en ne lisant que leur `manifest.json`,
  /// triés du plus récent au plus ancien.
  Future<List<SpecProjectSummary>> listProjects() async {
    if (!await _projectsDir.exists()) return const <SpecProjectSummary>[];
    final summaries = <SpecProjectSummary>[];
    await for (final entity in _projectsDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final manifest = _manifestFile(entity);
      if (!await manifest.exists()) continue;
      try {
        final decoded = jsonDecode(await manifest.readAsString());
        if (decoded is! Map) continue;
        final id = (decoded['id'] as String?)?.trim() ?? '';
        final name = (decoded['name'] as String?)?.trim() ?? '';
        final initialIdea = (decoded['initialIdea'] as String?)?.trim() ?? '';
        if (id.isEmpty || name.isEmpty || initialIdea.isEmpty) continue;
        final updatedAt =
            _parseDateTime(decoded['updatedAt']) ??
            _parseDateTime(decoded['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final objectCount = (decoded['objectCount'] as num?)?.toInt() ?? 0;
        final ruleCount = (decoded['ruleCount'] as num?)?.toInt() ?? 0;
        summaries.add(
          SpecProjectSummary(
            id: id,
            name: name,
            initialIdea: initialIdea,
            currentStage: SpecForgeStage.fromJson(decoded['currentStage']),
            updatedAt: updatedAt,
            objectCount: objectCount < 0 ? 0 : objectCount,
            ruleCount: ruleCount < 0 ? 0 : ruleCount,
          ),
        );
      } catch (_) {
        // Ignore un manifeste corrompu sans bloquer les autres projets.
      }
    }
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List<SpecProjectSummary>.unmodifiable(summaries);
  }

  /// Lit l'identifiant du dernier projet ouvert, ou `null`.
  Future<String?> getLastActiveProjectId() async {
    if (!await _indexFile.exists()) return null;
    try {
      final decoded = jsonDecode(await _indexFile.readAsString());
      if (decoded is Map && decoded['lastActiveProjectId'] is String) {
        final id = (decoded['lastActiveProjectId'] as String).trim();
        final resolved = id.isEmpty ? null : id;
        _cachedLastActiveProjectId = resolved;
        return resolved;
      }
    } catch (_) {}
    return null;
  }

  /// Mémorise l'identifiant du dernier projet actif dans `index.json`.
  Future<void> setLastActiveProjectId(String? projectId) async {
    if (_cachedLastActiveProjectId == projectId && await _indexFile.exists()) {
      return;
    }
    final payload = <String, Object?>{'lastActiveProjectId': projectId};
    await _writeJsonAtomically(_indexFile, payload);
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
        'objectCount': project.businessObjects.length,
        'ruleCount': project.businessRules.length,
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
      await _writeStringAtomically(targetFile, pending.textContent!);
    } else {
      await _writeBytesAtomically(targetFile, pending.bytes);
    }
  }

  Future<void> _pruneOrphanAttachments(
    Directory attachmentsDir,
    Set<String> referencedFiles,
  ) async {
    if (!await attachmentsDir.exists()) return;
    await for (final entity in attachmentsDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path.split(Platform.pathSeparator).last
          : entity.uri.pathSegments.last;
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

  Future<void> _writeJsonAtomically(
    File target,
    Map<String, Object?> payload,
  ) => _writeStringAtomically(target, _prettyEncoder.convert(payload));

  Future<void> _writeStringAtomically(File target, String content) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp.${_tmpCounter++}');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  }

  Future<void> _writeBytesAtomically(File target, Uint8List bytes) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp.${_tmpCounter++}');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }

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
