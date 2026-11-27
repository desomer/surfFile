/// Persistance atomique sur disque de l'espace de travail `super_backend_editor`
/// ([BackendWorkspaceStore], [BackendWorkspaceIndex]) : domaines, spécification
/// Design en lecture seule, surcouche Backend, scripts QuickJS, base SQLite,
/// conversations IA et secrets locaux isolés sous `.local/`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/backend_domain_project.dart';
import '../models/backend_overlay_config.dart';
import '../models/domain_design_diff.dart';
import '../models/domain_design_spec.dart';
import '../models/json_value_utils.dart';

final RegExp _safeDomainCodePattern = RegExp(r'^[a-z0-9]+(?:[-_][a-z0-9]+)*$');

const JsonEncoder _prettyJsonEncoder = JsonEncoder.withIndent('  ');

/// Index immuable de l'espace de travail persisté dans `<root>/workspace.json`.
@immutable
class BackendWorkspaceIndex {
  /// Crée un index d'espace de travail immuable.
  BackendWorkspaceIndex({
    this.format = formatId,
    this.version = storageVersion,
    this.activeDomainCode,
    List<BackendDomainProjectSummary> domains =
        const <BackendDomainProjectSummary>[],
  }) : domains = List<BackendDomainProjectSummary>.unmodifiable(domains);

  /// Identifiant canonique de format pour `workspace.json`.
  static const String formatId = 'super_backend_editor.workspace';

  /// Version courante du schéma `workspace.json`.
  static const int storageVersion = 1;

  /// Index vide par défaut.
  static final BackendWorkspaceIndex empty = BackendWorkspaceIndex();

  /// Identifiant de format du fichier.
  final String format;

  /// Version du format persisté.
  final int version;

  /// Code du domaine actuellement sélectionné dans le studio, ou `null`.
  final String? activeDomainCode;

  /// Résumés ordonnés des domaines enregistrés dans l'espace de travail.
  final List<BackendDomainProjectSummary> domains;

  /// Vérifie les invariants de l'index.
  void validate() {
    if (format != formatId) {
      throw FormatException(
        'Format workspace.json invalide : $format (attendu : $formatId).',
      );
    }
    if (version < 1) {
      throw FormatException('Version workspace.json invalide : $version.');
    }
    final seen = <String>{};
    for (final summary in domains) {
      summary.validate();
      if (!seen.add(summary.domainCode)) {
        throw FormatException(
          'Domaine dupliqué dans workspace.json : ${summary.domainCode}.',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  BackendWorkspaceIndex copyWith({
    String? format,
    int? version,
    String? activeDomainCode,
    bool clearActiveDomainCode = false,
    List<BackendDomainProjectSummary>? domains,
  }) => BackendWorkspaceIndex(
    format: format ?? this.format,
    version: version ?? this.version,
    activeDomainCode: clearActiveDomainCode
        ? null
        : (activeDomainCode ?? this.activeDomainCode),
    domains: domains ?? this.domains,
  );

  /// Sérialise l'index en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'format': format,
    'version': version,
    'activeDomainCode': activeDomainCode,
    'domains': <Map<String, Object?>>[
      for (final d in domains) d.toJson(),
    ],
  };

  /// Désérialise l'index depuis JSON.
  factory BackendWorkspaceIndex.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('workspace.json doit être un objet JSON.');
    }
    final rawFormat = (raw['format'] as String?)?.trim();
    final rawVersion = raw['version'];
    final parsedVersion = switch (rawVersion) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v.trim()) ?? storageVersion,
      _ => storageVersion,
    };
    final rawActive = (raw['activeDomainCode'] as String?)?.trim();
    final index = BackendWorkspaceIndex(
      format: (rawFormat == null || rawFormat.isEmpty) ? formatId : rawFormat,
      version: parsedVersion,
      activeDomainCode: (rawActive == null || rawActive.isEmpty)
          ? null
          : rawActive,
      domains: <BackendDomainProjectSummary>[
        if (raw['domains'] case final List list)
          for (final item in list) BackendDomainProjectSummary.fromJson(item),
      ],
    );
    index.validate();
    return index;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendWorkspaceIndex &&
          other.format == format &&
          other.version == version &&
          other.activeDomainCode == activeDomainCode &&
          listEquals(other.domains, domains);

  @override
  int get hashCode => Object.hash(
    format,
    version,
    activeDomainCode,
    Object.hashAll(domains),
  );
}

/// Magasin disque atomique et sérialisé gérant l'arborescence d'un espace de
/// travail `super_backend_editor` sous [rootDirectory].
class BackendWorkspaceStore {
  /// Crée un magasin ancré sur [rootDirectory] (`~/.super_backend_editor` par défaut).
  BackendWorkspaceStore([Directory? rootDirectory])
    : rootDirectory = rootDirectory ?? defaultRootDirectory();

  /// Contenu standard du `.gitignore` généré à la racine du workspace.
  static const String defaultGitignoreContent = '.local/\n*.tmp.*\n';

  /// Identifiant de format du fichier `import_history.json`.
  static const String importHistoryFormat =
      'super_backend_editor.import_history';

  /// Identifiant de format du fichier `.local/secrets_<domainCode>.json`.
  static const String localSecretsFormat = 'super_backend_editor.local_secrets';

  /// Identifiant de format du fichier `chats/assistant.json`.
  static const String assistantChatFormat =
      'super_backend_editor.assistant_chat';

  /// Résout le dossier par défaut `~/.super_backend_editor` selon l'OS hôte.
  static Directory defaultRootDirectory() {
    final env = Platform.environment;
    final home =
        env['USERPROFILE'] ?? env['HOME'] ?? Directory.current.path;
    final sep = Platform.pathSeparator;
    return Directory('$home$sep.super_backend_editor');
  }

  /// Dossier racine de l'espace de travail.
  final Directory rootDirectory;

  Future<void> _opQueue = Future<void>.value();
  int _tmpCounter = 0;

  /// Fichier `.gitignore` racine protégeant `.local/` et `*.tmp.*`.
  File get gitignoreFile =>
      File('${rootDirectory.path}${Platform.pathSeparator}.gitignore');

  /// Fichier d'index global `workspace.json`.
  File get workspaceIndexFile =>
      File('${rootDirectory.path}${Platform.pathSeparator}workspace.json');

  /// Dossier `.local/` non versionné contenant les secrets de test locaux.
  Directory get localSecretsDirectory =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}.local');

  /// Dossier `domains/` regroupant les domaines importés.
  Directory get domainsDirectory =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}domains');

  /// Retourne le dossier racine `domains/<domainCode>/` d'un domaine.
  Directory domainDirectoryFor(String domainCode) {
    final clean = _validateDomainCode(domainCode);
    return Directory(
      '${domainsDirectory.path}${Platform.pathSeparator}$clean',
    );
  }

  /// Retourne le dossier `domains/<domainCode>/scripts/` d'un domaine.
  Directory scriptsDirectoryFor(String domainCode) {
    final sep = Platform.pathSeparator;
    return Directory('${domainDirectoryFor(domainCode).path}${sep}scripts');
  }

  /// Retourne le fichier SQLite `domains/<domainCode>/data/backend.sqlite`.
  File sqliteFileFor(String domainCode) {
    final sep = Platform.pathSeparator;
    return File(
      '${domainDirectoryFor(domainCode).path}${sep}data${sep}backend.sqlite',
    );
  }

  /// Retourne le fichier cible sous `scripts/` pour [relativeScriptPath].
  File scriptFileFor(String domainCode, String relativeScriptPath) {
    final normalized = _normalizeScriptPath(relativeScriptPath);
    final osRelative = normalized.replaceAll('/', Platform.pathSeparator);
    return File(
      '${scriptsDirectoryFor(domainCode).path}${Platform.pathSeparator}$osRelative',
    );
  }

  File _designSpecFile(String domainCode) => File(
    '${domainDirectoryFor(domainCode).path}${Platform.pathSeparator}design_spec.json',
  );

  File _overlayFile(String domainCode) => File(
    '${domainDirectoryFor(domainCode).path}${Platform.pathSeparator}backend_overlay.json',
  );

  File _importHistoryFile(String domainCode) => File(
    '${domainDirectoryFor(domainCode).path}${Platform.pathSeparator}import_history.json',
  );

  File _assistantChatFile(String domainCode) {
    final sep = Platform.pathSeparator;
    return File(
      '${domainDirectoryFor(domainCode).path}${sep}chats${sep}assistant.json',
    );
  }

  File _localSecretsFile(String domainCode) {
    final clean = _validateDomainCode(domainCode);
    return File(
      '${localSecretsDirectory.path}${Platform.pathSeparator}secrets_$clean.json',
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final previous = _opQueue;
    final completer = Completer<void>();
    final next = previous.catchError((_) {}).then((_) => action());
    _opQueue = completer.future;
    return next.whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
  }

  static String _validateDomainCode(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty || !_safeDomainCodePattern.hasMatch(clean)) {
      throw FormatException('Code de domaine invalide : « $raw ».');
    }
    return clean;
  }

  static String _normalizeScriptPath(String relativePath) {
    final trimmed = relativePath.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty ||
        trimmed.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(trimmed)) {
      throw FormatException(
        'Chemin de script relatif invalide : « $relativePath ».',
      );
    }
    final segments = trimmed.split('/');
    for (final seg in segments) {
      if (seg.isEmpty || seg == '.' || seg == '..') {
        throw FormatException(
          'Segment de chemin interdit dans le script : « $relativePath ».',
        );
      }
    }
    return segments.join('/');
  }

  static String _encodePrettyJson(Object? payload) {
    final formatted = _prettyJsonEncoder.convert(payload).replaceAll('\r\n', '\n');
    return formatted.endsWith('\n') ? formatted : '$formatted\n';
  }

  static String _normalizeLf(String text) {
    final lf = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return lf.endsWith('\n') ? lf : '$lf\n';
  }

  Future<void> _writeTextAtomicallyUnlocked(File target, String content) async {
    if (await target.exists()) {
      try {
        if (await target.readAsString() == content) return;
      } catch (_) {}
    }
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp.${++_tmpCounter}');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  }

  Future<void> _writeJsonAtomicallyUnlocked(
    File target,
    Object? payload,
  ) => _writeTextAtomicallyUnlocked(target, _encodePrettyJson(payload));

  Future<void> _ensureWorkspaceScaffoldUnlocked() async {
    await rootDirectory.create(recursive: true);
    if (!await gitignoreFile.exists()) {
      await _writeTextAtomicallyUnlocked(gitignoreFile, defaultGitignoreContent);
    }
  }

  Future<BackendWorkspaceIndex> _loadWorkspaceIndexUnlocked() async {
    if (await workspaceIndexFile.exists()) {
      final decoded = jsonDecode(await workspaceIndexFile.readAsString());
      return BackendWorkspaceIndex.fromJson(decoded);
    }
    if (!await domainsDirectory.exists()) {
      return BackendWorkspaceIndex.empty;
    }
    final discovered = <BackendDomainProjectSummary>[];
    await for (final entity in domainsDirectory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final folderName = entity.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .lastOrNull;
      if (folderName == null || !_safeDomainCodePattern.hasMatch(folderName)) {
        continue;
      }
      final project = await _loadProjectUnlocked(folderName);
      if (project != null) {
        discovered.add(project.toSummary());
      }
    }
    discovered.sort((a, b) => a.domainCode.compareTo(b.domainCode));
    return BackendWorkspaceIndex(
      activeDomainCode: discovered.firstOrNull?.domainCode,
      domains: discovered,
    );
  }

  Future<Map<String, Map<String, String>>> _loadLocalSecretsUnlocked(
    String domainCode,
  ) async {
    final file = _localSecretsFile(domainCode);
    if (!await file.exists()) {
      return const <String, Map<String, String>>{};
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw FormatException(
        'Fichier de secrets locaux invalide pour $domainCode.',
      );
    }
    final rawSecrets = decoded.containsKey('secrets')
        ? decoded['secrets']
        : decoded;
    return freezeNestedStringMap(rawSecrets);
  }

  Future<void> _saveLocalSecretsUnlocked(
    String domainCode,
    Map<String, Map<String, String>> secrets,
  ) async {
    final cleanCode = _validateDomainCode(domainCode);
    final frozen = freezeNestedStringMap(secrets);
    final nonEmpty = <String, Map<String, String>>{
      for (final env in frozen.entries)
        if (env.value.isNotEmpty) env.key: env.value,
    };
    final target = _localSecretsFile(cleanCode);
    if (nonEmpty.isEmpty) {
      if (await target.exists()) {
        await target.delete();
      }
      return;
    }
    await _ensureWorkspaceScaffoldUnlocked();
    await _writeJsonAtomicallyUnlocked(target, <String, Object?>{
      'format': localSecretsFormat,
      'version': 1,
      'domainCode': cleanCode,
      'secrets': nonEmpty,
    });
  }

  Future<BackendDomainProject?> _loadProjectUnlocked(String domainCode) async {
    final cleanCode = _validateDomainCode(domainCode);
    final specFile = _designSpecFile(cleanCode);
    if (!await specFile.exists()) return null;

    final designSpec = DomainDesignSpec.fromJson(
      jsonDecode(await specFile.readAsString()),
    );

    final overlayFile = _overlayFile(cleanCode);
    final overlay = await overlayFile.exists()
        ? BackendOverlayConfig.fromJson(
            jsonDecode(await overlayFile.readAsString()),
          )
        : BackendOverlayConfig.bootstrapFromDesign(designSpec);

    final historyFile = _importHistoryFile(cleanCode);
    var history = const <DomainImportHistoryRecord>[];
    if (await historyFile.exists()) {
      final rawHistory = jsonDecode(await historyFile.readAsString());
      final list = rawHistory is List
          ? rawHistory
          : (rawHistory is Map ? rawHistory['records'] : null);
      if (list is List) {
        history = List<DomainImportHistoryRecord>.unmodifiable(<DomainImportHistoryRecord>[
          for (final item in list) DomainImportHistoryRecord.fromJson(item),
        ]);
      }
    }

    final secrets = await _loadLocalSecretsUnlocked(cleanCode);
    final project = BackendDomainProject(
      designSpec: designSpec,
      overlay: overlay,
      importHistory: history,
      localSecretValues: secrets,
    );
    project.validate();
    return project;
  }

  /// Charge l'index courant `workspace.json` (ou un index vide s'il n'existe pas encore).
  Future<BackendWorkspaceIndex> loadWorkspaceIndex() =>
      _enqueue(_loadWorkspaceIndexUnlocked);

  /// Met à jour le domaine actif dans `workspace.json`.
  Future<void> setActiveDomainCode(String? code) => _enqueue(() async {
    final normalized = (code == null || code.trim().isEmpty)
        ? null
        : _validateDomainCode(code);
    await _ensureWorkspaceScaffoldUnlocked();
    final current = await _loadWorkspaceIndexUnlocked();
    final updated = normalized == null
        ? current.copyWith(clearActiveDomainCode: true)
        : current.copyWith(activeDomainCode: normalized);
    await _writeJsonAtomicallyUnlocked(workspaceIndexFile, updated.toJson());
  });

  /// Retourne la liste ordonnée des résumés de domaines enregistrés dans le workspace.
  Future<List<BackendDomainProjectSummary>> listDomainSummaries() =>
      _enqueue(() async => (await _loadWorkspaceIndexUnlocked()).domains);

  /// Charge le projet complet d'un domaine par son [domainCode], ou `null` s'il est absent.
  Future<BackendDomainProject?> loadProject(String domainCode) =>
      _enqueue(() => _loadProjectUnlocked(domainCode));

  /// Sauvegarde atomiquement [project] (couche Design, overlay Backend,
  /// historique d'import, secrets `.local/` et mise à jour de `workspace.json`).
  Future<void> saveProject(
    BackendDomainProject project, {
    bool setActiveIfUnset = true,
  }) => _enqueue(() async {
    project.validate();
    final domainCode = project.domainCode;
    await _ensureWorkspaceScaffoldUnlocked();

    await scriptsDirectoryFor(domainCode).create(recursive: true);
    await sqliteFileFor(domainCode).parent.create(recursive: true);
    await _assistantChatFile(domainCode).parent.create(recursive: true);

    await _writeJsonAtomicallyUnlocked(
      _designSpecFile(domainCode),
      project.designSpec.toJson(),
    );
    await _writeJsonAtomicallyUnlocked(
      _overlayFile(domainCode),
      project.overlay.toJson(),
    );
    await _writeJsonAtomicallyUnlocked(
      _importHistoryFile(domainCode),
      <String, Object?>{
        'format': importHistoryFormat,
        'version': 1,
        'records': <Map<String, Object?>>[
          for (final record in project.importHistory) record.toJson(),
        ],
      },
    );
    await _saveLocalSecretsUnlocked(domainCode, project.localSecretValues);

    final currentIndex = await _loadWorkspaceIndexUnlocked();
    final summary = project.toSummary();
    final updatedDomains = <BackendDomainProjectSummary>[];
    var replaced = false;
    for (final existing in currentIndex.domains) {
      if (existing.domainCode == domainCode) {
        updatedDomains.add(summary);
        replaced = true;
      } else {
        updatedDomains.add(existing);
      }
    }
    if (!replaced) {
      updatedDomains.add(summary);
    }
    final nextActive =
        (currentIndex.activeDomainCode == null && setActiveIfUnset)
        ? domainCode
        : currentIndex.activeDomainCode;
    final nextIndex = currentIndex.copyWith(
      activeDomainCode: nextActive,
      domains: updatedDomains,
    );
    await _writeJsonAtomicallyUnlocked(workspaceIndexFile, nextIndex.toJson());
  });

  /// Supprime le dossier d'un domaine, ses secrets locaux et son entrée dans `workspace.json`.
  Future<bool> deleteProject(String domainCode) => _enqueue(() async {
    final cleanCode = _validateDomainCode(domainCode);
    final dir = domainDirectoryFor(cleanCode);
    final secretsFile = _localSecretsFile(cleanCode);
    var deleted = false;

    if (await dir.exists()) {
      await dir.delete(recursive: true);
      deleted = true;
    }
    if (await secretsFile.exists()) {
      await secretsFile.delete();
      deleted = true;
    }

    if (await workspaceIndexFile.exists()) {
      final currentIndex = await _loadWorkspaceIndexUnlocked();
      final remaining = currentIndex.domains
          .where((d) => d.domainCode != cleanCode)
          .toList(growable: false);
      final clearActive = currentIndex.activeDomainCode == cleanCode;
      final fallbackActive = clearActive
          ? remaining.firstOrNull?.domainCode
          : currentIndex.activeDomainCode;
      final nextIndex = fallbackActive == null
          ? currentIndex.copyWith(
              clearActiveDomainCode: true,
              domains: remaining,
            )
          : currentIndex.copyWith(
              activeDomainCode: fallbackActive,
              domains: remaining,
            );
      if (remaining.length != currentIndex.domains.length || clearActive) {
        deleted = true;
        await _writeJsonAtomicallyUnlocked(
          workspaceIndexFile,
          nextIndex.toJson(),
        );
      }
    }
    return deleted;
  });

  /// Lit le code source JavaScript d'un script sous `domains/<domainCode>/scripts/`, ou `null` si absent.
  Future<String?> readScript(String domainCode, String relativeScriptPath) =>
      _enqueue(() async {
        final file = scriptFileFor(domainCode, relativeScriptPath);
        if (!await file.exists()) return null;
        return file.readAsString();
      });

  /// Écrit atomiquement un script QuickJS sous `domains/<domainCode>/scripts/`.
  Future<void> writeScript(
    String domainCode,
    String relativeScriptPath,
    String jsSource,
  ) => _enqueue(() async {
    await _ensureWorkspaceScaffoldUnlocked();
    final file = scriptFileFor(domainCode, relativeScriptPath);
    await _writeTextAtomicallyUnlocked(file, _normalizeLf(jsSource));
  });

  /// Supprime un script QuickJS sous `domains/<domainCode>/scripts/`.
  Future<bool> deleteScript(String domainCode, String relativeScriptPath) =>
      _enqueue(() async {
        final file = scriptFileFor(domainCode, relativeScriptPath);
        if (!await file.exists()) return false;
        await file.delete();
        return true;
      });

  /// Liste les chemins relatifs normalisés (`/` et triés) de tous les scripts `.js` d'un domaine.
  Future<List<String>> listScripts(String domainCode) => _enqueue(() async {
    final scriptsDir = scriptsDirectoryFor(domainCode);
    if (!await scriptsDir.exists()) return const <String>[];
    final rootPath = scriptsDir.path;
    final relativePaths = <String>[];
    await for (final entity in scriptsDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final fullPath = entity.path;
      if (fullPath.contains('.tmp.')) continue;
      if (!fullPath.toLowerCase().endsWith('.js')) continue;
      if (!fullPath.startsWith(rootPath)) continue;
      var rel = fullPath.substring(rootPath.length);
      rel = rel.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
      if (rel.isNotEmpty) {
        relativePaths.add(rel);
      }
    }
    relativePaths.sort();
    return List<String>.unmodifiable(relativePaths);
  });

  /// Charge les valeurs de test locales des secrets depuis `.local/secrets_<domainCode>.json`.
  Future<Map<String, Map<String, String>>> loadLocalSecrets(
    String domainCode,
  ) => _enqueue(() => _loadLocalSecretsUnlocked(domainCode));

  /// Sauvegarde atomiquement les secrets locaux de test dans `.local/secrets_<domainCode>.json`.
  Future<void> saveLocalSecrets(
    String domainCode,
    Map<String, Map<String, String>> secrets,
  ) => _enqueue(() => _saveLocalSecretsUnlocked(domainCode, secrets));

  /// Charge l'historique de conversation de l'assistant IA (`chats/assistant.json`).
  Future<List<Map<String, Object?>>> loadAssistantChat(String domainCode) =>
      _enqueue(() async {
        final file = _assistantChatFile(domainCode);
        if (!await file.exists()) return const <Map<String, Object?>>[];
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          return freezeJsonMapList(decoded);
        }
        if (decoded is Map && decoded['messages'] is List) {
          return freezeJsonMapList(decoded['messages']);
        }
        return const <Map<String, Object?>>[];
      });

  /// Sauvegarde atomiquement l'historique de conversation IA dans `chats/assistant.json`.
  Future<void> saveAssistantChat(
    String domainCode,
    List<Map<String, Object?>> messages,
  ) => _enqueue(() async {
    final cleanCode = _validateDomainCode(domainCode);
    await _ensureWorkspaceScaffoldUnlocked();
    final frozen = freezeJsonMapList(messages);
    await _writeJsonAtomicallyUnlocked(
      _assistantChatFile(cleanCode),
      <String, Object?>{
        'format': assistantChatFormat,
        'version': 1,
        'messages': frozen,
      },
    );
  });
}
