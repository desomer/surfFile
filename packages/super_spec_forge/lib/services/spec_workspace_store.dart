/// Gestionnaire de dossiers Workspace versionnables sous Git ([SpecWorkspaceStore]).
///
/// Un workspace regroupe dans un même dossier racine :
/// - `workspace.json` : métadonnées du workspace ;
/// - `.gitignore` : ignore l'état machine local (`.local/`), `exports/` et `*.tmp.*` ;
/// - `.local/state.json` : dernier projet actif sur cette machine ;
/// - `glossary/` : glossaire terminologique d'entreprise ;
/// - `dictionary/` : dictionnaire technique et préférences globales ;
/// - `projects/<project-slug>/` : projets de spécification.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'spec_storage_slug.dart';

/// Exception levée lorsqu'un dossier non vide ne contient pas encore de workspace
/// `super_spec_forge` (`workspace.json`) et qu'une confirmation est attendue.
class NonEmptyNonWorkspaceException extends FormatException {
  /// Construit l'exception avec un message explicatif.
  const NonEmptyNonWorkspaceException(super.message, [super.source]);
}

/// Métadonnées persistées dans `<workspaceRoot>/workspace.json`.
@immutable
class SpecWorkspaceMetadata {
  /// Construit des métadonnées de workspace.
  SpecWorkspaceMetadata({
    required String name,
    required this.createdAt,
  }) : name = name.trim() {
    if (this.name.isEmpty) {
      throw const FormatException('Le nom du workspace est requis.');
    }
  }

  /// Identifiant de format du fichier `workspace.json`.
  static const String formatId = 'super_spec_forge.workspace';

  /// Version courante du format de stockage par dossier.
  static const int storageVersion = 3;

  /// Nom lisible du workspace.
  final String name;

  /// Date UTC de création du workspace.
  final DateTime createdAt;

  /// Copie modifiée.
  SpecWorkspaceMetadata copyWith({
    String? name,
    DateTime? createdAt,
  }) => SpecWorkspaceMetadata(
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );

  /// Sérialise en JSON déterministe.
  Map<String, Object?> toJson() => <String, Object?>{
    'format': formatId,
    'version': storageVersion,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Désérialise depuis JSON.
  factory SpecWorkspaceMetadata.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('workspace.json doit être un objet JSON.');
    }
    final format = raw['format'];
    if (format != null && format != formatId) {
      throw const FormatException('Format de workspace.json inconnu.');
    }
    final name = (raw['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      throw const FormatException('Nom manquant dans workspace.json.');
    }
    final createdAt = _parseDateTime(raw['createdAt']) ?? DateTime.now().toUtc();
    return SpecWorkspaceMetadata(name: name, createdAt: createdAt);
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecWorkspaceMetadata &&
          other.name == name &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(name, createdAt);
}

/// Entrée d'historique d'un workspace récent mémorisé localement.
@immutable
class SpecWorkspaceEntry {
  /// Construit une entrée d'historique de workspace.
  const SpecWorkspaceEntry({
    required this.path,
    required this.name,
    required this.lastOpenedAt,
  });

  /// Chemin absolu du dossier workspace.
  final String path;

  /// Nom affiché du workspace.
  final String name;

  /// Date UTC de dernière ouverture.
  final DateTime lastOpenedAt;

  /// Sérialise en JSON pour `SharedPreferences`.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'name': name,
    'lastOpenedAt': lastOpenedAt.toUtc().toIso8601String(),
  };

  /// Désérialise depuis JSON, ou retourne `null` si invalide.
  static SpecWorkspaceEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = (raw['path'] as String?)?.trim() ?? '';
    final name = (raw['name'] as String?)?.trim() ?? '';
    if (path.isEmpty || name.isEmpty) return null;
    final lastOpenedAt =
        (raw['lastOpenedAt'] is String
            ? DateTime.tryParse(raw['lastOpenedAt'] as String)?.toUtc()
            : null) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return SpecWorkspaceEntry(
      path: path,
      name: name,
      lastOpenedAt: lastOpenedAt,
    );
  }
}

/// Service gérant l'ouverture, l'initialisation et l'historique des dossiers
/// Workspace `super_spec_forge` compatibles Git.
class SpecWorkspaceStore {
  /// Crée un gestionnaire de workspaces.
  SpecWorkspaceStore({
    this.fallbackRootDirectory,
    this.maxRecentWorkspaces = 12,
    this.usePreferences = true,
  });

  /// Clé `SharedPreferences` du dernier workspace actif.
  static const String activeWorkspacePrefKey =
      'super_spec_forge.active_workspace_path';

  /// Clé `SharedPreferences` de la liste des workspaces récents.
  static const String recentWorkspacesPrefKey =
      'super_spec_forge.recent_workspaces';

  /// Clé `SharedPreferences` des largeurs personnalisées de panneaux UI.
  static const String panelWidthsPrefKey = 'super_spec_forge.panel_widths';

  /// Contenu par défaut du `.gitignore` généré à la racine d'un workspace.
  static const String defaultGitignoreContent =
      '# État local machine (dernier projet actif, caches UI)\n'
      '.local/\n'
      '\n'
      '# Exports HTML/Markdown/JSON générés localement\n'
      'exports/\n'
      '\n'
      '# Fichiers temporaires d’écriture atomique\n'
      '*.tmp.*\n';

  final Directory? fallbackRootDirectory;

  /// Nombre maximal de workspaces récents conservés dans `SharedPreferences`.
  final int maxRecentWorkspaces;

  /// Active ou désactive l'usage de `SharedPreferences` (utile en tests unitaires).
  final bool usePreferences;
  int _tmpCounter = 0;

  /// Dossier racine par défaut sous le répertoire utilisateur (`~/.super_spec_forge`).
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

  /// Dossier de repli utilisé si aucun workspace n'est encore enregistré.
  Directory get effectiveFallbackRootDirectory =>
      fallbackRootDirectory ?? defaultRootDirectory();

  /// Fichier `workspace.json` d'un dossier [workspaceDir].
  static File metadataFileFor(Directory workspaceDir) => File(
    '${_normalizeDirPath(workspaceDir.path)}${Platform.pathSeparator}workspace.json',
  );

  /// Fichier `.gitignore` d'un dossier [workspaceDir].
  static File gitignoreFileFor(Directory workspaceDir) => File(
    '${_normalizeDirPath(workspaceDir.path)}${Platform.pathSeparator}.gitignore',
  );

  /// Résout le dossier workspace à ouvrir au démarrage.
  Future<Directory> resolveInitialWorkspaceDirectory() async {
    final saved = await getActiveWorkspacePath();
    if (saved != null && saved.trim().isNotEmpty) {
      final dir = Directory(saved.trim());
      if (await dir.exists() && await metadataFileFor(dir).exists()) {
        return dir;
      }
    }
    return effectiveFallbackRootDirectory;
  }

  /// Retourne le chemin du dernier workspace actif mémorisé, ou `null`.
  Future<String?> getActiveWorkspacePath() async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) return null;
    final raw = prefs.getString(activeWorkspacePrefKey)?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  /// Retourne la liste des workspaces récents enregistrés localement.
  Future<List<SpecWorkspaceEntry>> listRecentWorkspaces() async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) return const <SpecWorkspaceEntry>[];
    final raw = prefs.getString(recentWorkspacesPrefKey);
    if (raw == null || raw.trim().isEmpty) return const <SpecWorkspaceEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <SpecWorkspaceEntry>[];
      final entries = <SpecWorkspaceEntry>[
        for (final item in decoded) ?SpecWorkspaceEntry.tryFromJson(item),
      ]..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      return List<SpecWorkspaceEntry>.unmodifiable(entries);
    } catch (_) {
      return const <SpecWorkspaceEntry>[];
    }
  }

  /// Supprime [path] de l'historique local des workspaces récents.
  Future<void> removeRecentWorkspace(String path) async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) return;
    final norm = _canonicalKey(path);
    final entries = (await listRecentWorkspaces())
        .where((e) => _canonicalKey(e.path) != norm)
        .toList();
    await prefs.setString(
      recentWorkspacesPrefKey,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  /// Lit les largeurs personnalisées des panneaux redimensionnables depuis `SharedPreferences`.
  Future<Map<String, double>> loadPanelWidths() async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) return const <String, double>{};
    final raw = prefs.getString(panelWidthsPrefKey);
    if (raw == null || raw.trim().isEmpty) return const <String, double>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, double>{};
      final result = <String, double>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final val = entry.value;
        if (key is String && val is num && val.isFinite && val > 0) {
          result[key] = val.toDouble();
        }
      }
      return result;
    } catch (_) {
      return const <String, double>{};
    }
  }

  /// Enregistre les largeurs personnalisées des panneaux redimensionnables dans `SharedPreferences`.
  Future<void> savePanelWidths(Map<String, double> widths) async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) return;
    final sanitized = <String, double>{
      for (final entry in widths.entries)
        if (entry.value.isFinite && entry.value > 0) entry.key: entry.value,
    };
    if (sanitized.isEmpty) {
      await prefs.remove(panelWidthsPrefKey);
      return;
    }
    await prefs.setString(panelWidthsPrefKey, jsonEncode(sanitized));
  }

  /// Ouvre un dossier workspace existant ou l'initialise s'il est vide (ou si
  /// [initializeNonEmpty] vaut `true`).
  ///
  /// Lève [NonEmptyNonWorkspaceException] si le dossier contient déjà d'autres
  /// fichiers sans `workspace.json` ni structure v3 et que [initializeNonEmpty]
  /// vaut `false`.
  Future<SpecWorkspaceMetadata> openWorkspace(
    Directory workspaceDir, {
    bool initializeNonEmpty = false,
    String? defaultName,
    bool recordAsActive = true,
  }) async {
    final normalizedDir = Directory(_normalizeDirPath(workspaceDir.path));
    await normalizedDir.create(recursive: true);

    final metaFile = metadataFileFor(normalizedDir);
    late final SpecWorkspaceMetadata metadata;

    if (await metaFile.exists()) {
      final decoded = jsonDecode(await metaFile.readAsString());
      metadata = SpecWorkspaceMetadata.fromJson(decoded);
    } else {
      final hasWorkspaceDirs =
          await Directory(
            '${normalizedDir.path}${Platform.pathSeparator}projects',
          ).exists() ||
          await Directory(
            '${normalizedDir.path}${Platform.pathSeparator}glossary',
          ).exists() ||
          await Directory(
            '${normalizedDir.path}${Platform.pathSeparator}dictionary',
          ).exists();
      if (!initializeNonEmpty && !hasWorkspaceDirs) {
        final nonGitEntries = await _listMeaningfulEntries(normalizedDir);
        if (nonGitEntries.isNotEmpty) {
          throw NonEmptyNonWorkspaceException(
            'Le dossier « ${normalizedDir.path} » n’est pas vide et ne contient pas encore de workspace SuperSpecForge.',
            normalizedDir.path,
          );
        }
      }
      final folderName = _deriveFolderName(normalizedDir.path);
      final resolvedName = (defaultName != null && defaultName.trim().isNotEmpty)
          ? defaultName.trim()
          : folderName;
      metadata = SpecWorkspaceMetadata(
        name: resolvedName,
        createdAt: DateTime.now().toUtc(),
      );
      await SpecStorageIo.writeJsonAtomicallyIfChanged(
        metaFile,
        metadata.toJson(),
        nextTmpId: () => _tmpCounter++,
      );
    }

    await ensureGitignore(normalizedDir);
    if (recordAsActive) {
      await _recordWorkspaceOpened(normalizedDir, metadata);
    }
    return metadata;
  }

  /// Crée ou réinitialise explicitement un workspace nommé [name] dans [workspaceDir].
  Future<SpecWorkspaceMetadata> createWorkspace(
    Directory workspaceDir, {
    required String name,
    bool allowNonEmpty = true,
    bool recordAsActive = true,
  }) async {
    final normalizedDir = Directory(_normalizeDirPath(workspaceDir.path));
    await normalizedDir.create(recursive: true);
    if (!allowNonEmpty && !await metadataFileFor(normalizedDir).exists()) {
      final nonGitEntries = await _listMeaningfulEntries(normalizedDir);
      if (nonGitEntries.isNotEmpty) {
        throw NonEmptyNonWorkspaceException(
          'Le dossier « ${normalizedDir.path} » n’est pas vide.',
          normalizedDir.path,
        );
      }
    }
    final metadata = SpecWorkspaceMetadata(
      name: name,
      createdAt: DateTime.now().toUtc(),
    );
    await SpecStorageIo.writeJsonAtomicallyIfChanged(
      metadataFileFor(normalizedDir),
      metadata.toJson(),
      nextTmpId: () => _tmpCounter++,
    );
    await ensureGitignore(normalizedDir);
    if (recordAsActive) {
      await _recordWorkspaceOpened(normalizedDir, metadata);
    }
    return metadata;
  }

  /// Crée `<workspaceDir>/.gitignore` uniquement s'il n'existe pas encore.
  Future<void> ensureGitignore(Directory workspaceDir) async {
    final file = gitignoreFileFor(workspaceDir);
    if (await file.exists()) return;
    await SpecStorageIo.writeTextAtomicallyIfChanged(
      file,
      SpecStorageIo.normalizeLf(defaultGitignoreContent),
      nextTmpId: () => _tmpCounter++,
    );
  }

  Future<void> _recordWorkspaceOpened(
    Directory dir,
    SpecWorkspaceMetadata metadata,
  ) async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) return;
    final cleanPath = _normalizeDirPath(dir.path);
    await prefs.setString(activeWorkspacePrefKey, cleanPath);

    final normKey = _canonicalKey(cleanPath);
    final existing = await listRecentWorkspaces();
    final updated = <SpecWorkspaceEntry>[
      SpecWorkspaceEntry(
        path: cleanPath,
        name: metadata.name,
        lastOpenedAt: DateTime.now().toUtc(),
      ),
      for (final entry in existing)
        if (_canonicalKey(entry.path) != normKey) entry,
    ];
    final trimmed = updated.length > maxRecentWorkspaces
        ? updated.sublist(0, maxRecentWorkspaces)
        : updated;
    await prefs.setString(
      recentWorkspacesPrefKey,
      jsonEncode([for (final e in trimmed) e.toJson()]),
    );
  }

  Future<SharedPreferences?> _tryGetPreferences() async {
    if (!usePreferences) return null;
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static Future<List<FileSystemEntity>> _listMeaningfulEntries(
    Directory dir,
  ) async {
    final items = <FileSystemEntity>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = SpecStorageIo.fileNameOf(entity.path);
      if (name == '.git' ||
          name == '.gitignore' ||
          name == '.gitattributes' ||
          name == '.DS_Store' ||
          name == 'Thumbs.db') {
        continue;
      }
      items.add(entity);
    }
    return items;
  }

  static String _deriveFolderName(String path) {
    final normalized = _normalizeDirPath(path);
    final name = SpecStorageIo.fileNameOf(normalized);
    if (name.isEmpty || name == '.super_spec_forge') {
      return 'Workspace principal';
    }
    return name;
  }

  static String _normalizeDirPath(String path) {
    var clean = path.trim();
    final sep = Platform.pathSeparator;
    while (clean.length > 1 &&
        (clean.endsWith(sep) || clean.endsWith('/')) &&
        !(Platform.isWindows && clean.length == 3 && clean[1] == ':')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  static String _canonicalKey(String path) {
    final normalized = _normalizeDirPath(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
