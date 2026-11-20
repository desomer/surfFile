/// Gestionnaire de dossiers d'applications sandboxées ([SandboxedApplicationStore]).
///
/// Chaque application est représentée par un dossier autonome contenant :
/// - `app.json` : métadonnées de l'application ([SandboxedApplicationManifest]) ;
/// - `appearance.json` : état global de l'interface (thème, catalogue, page `'/'` et éléments partagés) ;
/// - `pages/<pageId>.json` : persistance individuelle de chaque page du catalogue via [PagedFileAppearanceStore] ;
/// - `repositories/` : magasin [JsonRepositoryStore] isolé (documents JSON,
///   schémas, attributs calculés, providers, datasources, SQLite, `registered/`).
///
/// L'historique des applications récentes et le chemin de l'application active
/// sont conservés dans `SharedPreferences`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/registry.dart';
import '../appearance/appearance_codec.dart';
import '../appearance/paged_file_appearance_store.dart';
import '../repositories/json_repository_store.dart';

/// Exception levée lors de l'ouverture d'un dossier non vide ne contenant
/// pas encore de structure d'application sandboxée.
class NonEmptyNonAppDirectoryException extends FormatException {
  const NonEmptyNonAppDirectoryException(super.message, [super.source]);
}

/// Manifeste JSON (`app.json`) stocké à la racine d'un dossier d'application.
@immutable
class SandboxedApplicationManifest {
  SandboxedApplicationManifest({
    required String name,
    required this.createdAt,
    required this.updatedAt,
  }) : name = name.trim() {
    if (this.name.isEmpty) {
      throw const FormatException('Le nom de l’application est requis.');
    }
  }

  /// Identifiant de format du manifeste.
  static const String formatId = 'super_container_layout.application';

  /// Version courante du schéma `app.json`.
  static const int currentVersion = 1;

  /// Nom affiché de l'application.
  final String name;

  /// Horodatage UTC de création.
  final DateTime createdAt;

  /// Horodatage UTC de dernière ouverture / modification.
  final DateTime updatedAt;

  /// Retourne une copie modifiée du manifeste.
  SandboxedApplicationManifest copyWith({
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SandboxedApplicationManifest(
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Sérialise le manifeste en objet JSON.
  Map<String, Object?> toJson() => {
    'format': formatId,
    'version': currentVersion,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// Désérialise et valide un manifeste depuis un objet JSON décodé.
  factory SandboxedApplicationManifest.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Manifeste app.json invalide.');
    }
    final map = Map<String, Object?>.from(raw);
    final format = map['format'];
    if (format != null && format != formatId) {
      throw const FormatException('Format de manifeste app.json inconnu.');
    }
    final version = map['version'];
    if (version != null && version != currentVersion) {
      throw const FormatException(
        'Version de manifeste app.json non prise en charge.',
      );
    }
    final name = map['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Nom manquant dans app.json.');
    }
    final now = DateTime.now().toUtc();
    final createdAt = _parseDateTime(map['createdAt']) ?? now;
    final updatedAt = _parseDateTime(map['updatedAt']) ?? createdAt;
    return SandboxedApplicationManifest(
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SandboxedApplicationManifest &&
          name == other.name &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(name, createdAt, updatedAt);
}

/// Entrée de l'historique des applications récentes.
@immutable
class SandboxedApplicationEntry {
  const SandboxedApplicationEntry({
    required this.path,
    required this.name,
    required this.lastOpenedAt,
  });

  /// Chemin complet du dossier d'application.
  final String path;

  /// Nom affiché de l'application.
  final String name;

  /// Date UTC de dernière ouverture.
  final DateTime lastOpenedAt;

  /// Indique si le dossier existe actuellement sur le disque (sans suivre les liens).
  bool get exists =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;

  /// Retourne une copie modifiée de l'entrée.
  SandboxedApplicationEntry copyWith({
    String? path,
    String? name,
    DateTime? lastOpenedAt,
  }) => SandboxedApplicationEntry(
    path: path ?? this.path,
    name: name ?? this.name,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
  );

  /// Sérialise l'entrée pour `SharedPreferences`.
  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'lastOpenedAt': lastOpenedAt.toUtc().toIso8601String(),
  };

  /// Désérialise une entrée depuis JSON.
  factory SandboxedApplicationEntry.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Entrée d’application récente invalide.');
    }
    final map = Map<String, Object?>.from(raw);
    final path = map['path'];
    final name = map['name'];
    if (path is! String || path.trim().isEmpty) {
      throw const FormatException('Chemin d’application invalide.');
    }
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Nom d’application invalide.');
    }
    final opened =
        SandboxedApplicationManifest._parseDateTime(map['lastOpenedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return SandboxedApplicationEntry(
      path: path,
      name: name,
      lastOpenedAt: opened,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SandboxedApplicationEntry &&
          path == other.path &&
          name == other.name &&
          lastOpenedAt == other.lastOpenedAt;

  @override
  int get hashCode => Object.hash(path, name, lastOpenedAt);
}

/// Résultat d'inspection d'un dossier candidat pour une application sandboxée.
@immutable
class SandboxedApplicationInspection {
  const SandboxedApplicationInspection({
    required this.directory,
    required this.exists,
    required this.isSymlink,
    required this.isDirectory,
    required this.isEmpty,
    required this.hasManifest,
    required this.hasAppearance,
    this.hasPages = false,
    required this.hasRepositories,
    this.manifest,
  });

  final Directory directory;
  final bool exists;
  final bool isSymlink;
  final bool isDirectory;
  final bool isEmpty;
  final bool hasManifest;
  final bool hasAppearance;
  final bool hasPages;
  final bool hasRepositories;
  final SandboxedApplicationManifest? manifest;

  /// Indique si le dossier contient déjà au moins un élément d'application sandboxée.
  bool get looksLikeSandboxedApp =>
      hasManifest || hasAppearance || hasPages || hasRepositories;
}

/// Service gérant l'ouverture, la création, le clonage et l'historique des
/// dossiers d'applications sandboxées.
class SandboxedApplicationStore {
  SandboxedApplicationStore({
    this.activePathKey = 'super_container_layout.active_application.v1',
    this.recentAppsKey = 'super_container_layout.recent_applications.v1',
    this.maxRecentCount = 20,
  });

  /// Nom du fichier manifeste dans le dossier de l'application.
  static const String manifestFileName = 'app.json';

  /// Nom du fichier d'apparence dans le dossier de l'application.
  static const String appearanceFileName = 'appearance.json';

  /// Nom du sous-dossier des fichiers individuels de pages dans le dossier de l'application.
  static const String pagesFolderName = 'pages';

  /// Nom du sous-dossier de repositories dans le dossier de l'application.
  static const String repositoriesFolderName = 'repositories';

  /// Clé `SharedPreferences` mémorisant le chemin de l'application active.
  final String activePathKey;

  /// Clé `SharedPreferences` mémorisant la liste des applications récentes.
  final String recentAppsKey;

  /// Nombre maximal d'entrées conservées dans la liste des récentes.
  final int maxRecentCount;

  /// Retourne le répertoire racine par défaut des nouvelles applications (`~/.super_container_layout/apps`).
  static Directory defaultAppsRootDirectory() {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.trim().isEmpty) {
      throw const FileSystemException('Dossier utilisateur introuvable.');
    }
    return Directory(
      '$home${Platform.pathSeparator}.super_container_layout'
      '${Platform.pathSeparator}apps',
    );
  }

  /// Retourne le dossier de l'application par défaut (`~/.super_container_layout/apps/default`).
  static Directory defaultApplicationDirectory() => Directory(
    '${defaultAppsRootDirectory().path}${Platform.pathSeparator}default',
  );

  /// Normalise un chemin de dossier en supprimant les séparateurs finaux superflus.
  static String normalizePath(String rawPath) {
    var path = rawPath.trim();
    if (path.isEmpty) return path;
    final sep = Platform.pathSeparator;
    path = path.replaceAll(sep == r'\' ? '/' : r'\', sep);
    while (path.length > 1 && path.endsWith(sep)) {
      if (Platform.isWindows && path.length == 3 && path[1] == ':') {
        break;
      }
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  /// Compare deux chemins de dossiers selon la sensibilité à la casse du système.
  static bool samePath(String a, String b) {
    final na = normalizePath(a);
    final nb = normalizePath(b);
    return Platform.isWindows
        ? na.toLowerCase() == nb.toLowerCase()
        : na == nb;
  }

  /// Indique si [candidate] est identique à [parent] ou situé à l'intérieur de [parent].
  static bool isSameOrSubpath(String candidate, String parent) {
    final nc = normalizePath(candidate);
    final np = normalizePath(parent);
    if (samePath(nc, np)) return true;
    final prefix = np.endsWith(Platform.pathSeparator)
        ? np
        : '$np${Platform.pathSeparator}';
    return Platform.isWindows
        ? nc.toLowerCase().startsWith(prefix.toLowerCase())
        : nc.startsWith(prefix);
  }

  /// Propose un nom de dossier sûr à partir d'un nom d'application.
  static String suggestFolderName(String appName) {
    final lower = appName.trim().toLowerCase();
    final replaced = lower
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return replaced.isEmpty ? 'app' : replaced;
  }

  /// Retourne le nom dérivé du dossier [appDir].
  static String fallbackNameForDirectory(Directory appDir) {
    final normalized = normalizePath(appDir.path);
    final segments = normalized
        .split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .toList();
    return segments.isEmpty ? 'Application' : segments.last;
  }

  /// Fichier `app.json` de [appDir].
  static File manifestFileFor(Directory appDir) => File(
    '${normalizePath(appDir.path)}${Platform.pathSeparator}$manifestFileName',
  );

  /// Fichier `appearance.json` de [appDir].
  static File appearanceFileFor(Directory appDir) => File(
    '${normalizePath(appDir.path)}${Platform.pathSeparator}$appearanceFileName',
  );

  /// Dossier `pages` de [appDir].
  static Directory pagesDirectoryFor(Directory appDir) => Directory(
    '${normalizePath(appDir.path)}${Platform.pathSeparator}$pagesFolderName',
  );

  /// Fichier JSON dédié à [pageId] dans `<appDir>/pages`.
  static File pageFileFor(Directory appDir, String pageId) =>
      PagedFileAppearanceStore.pageFileForDirectory(
        pagesDirectoryFor(appDir),
        pageId,
      );

  /// Dossier `repositories` de [appDir].
  static Directory repositoriesDirectoryFor(Directory appDir) => Directory(
    '${normalizePath(appDir.path)}${Platform.pathSeparator}$repositoriesFolderName',
  );

  /// Crée un [PagedFileAppearanceStore] lié à `<appDir>/appearance.json` et `<appDir>/pages/`.
  static PagedFileAppearanceStore appearanceStoreFor(
    Directory appDir, {
    AppearanceCodec codec = const AppearanceCodec(),
    Registry? registry,
  }) => PagedFileAppearanceStore(
    appearanceFileFor(appDir),
    pagesDirectory: pagesDirectoryFor(appDir),
    registry: registry,
    codec: codec,
  );

  /// Crée un [JsonRepositoryStore] isolé dans `<appDir>/repositories`.
  static JsonRepositoryStore repositoryStoreFor(Directory appDir) =>
      JsonRepositoryStore(repositoriesDirectoryFor(appDir));

  /// Inspecte un dossier sur disque sans suivre les liens symboliques.
  Future<SandboxedApplicationInspection> inspectDirectory(
    Directory appDir,
  ) async {
    final normalized = Directory(normalizePath(appDir.path));
    final type = await FileSystemEntity.type(
      normalized.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      return SandboxedApplicationInspection(
        directory: normalized,
        exists: false,
        isSymlink: false,
        isDirectory: false,
        isEmpty: true,
        hasManifest: false,
        hasAppearance: false,
        hasRepositories: false,
      );
    }
    if (type == FileSystemEntityType.link) {
      return SandboxedApplicationInspection(
        directory: normalized,
        exists: true,
        isSymlink: true,
        isDirectory: false,
        isEmpty: false,
        hasManifest: false,
        hasAppearance: false,
        hasRepositories: false,
      );
    }
    if (type != FileSystemEntityType.directory) {
      return SandboxedApplicationInspection(
        directory: normalized,
        exists: true,
        isSymlink: false,
        isDirectory: false,
        isEmpty: false,
        hasManifest: false,
        hasAppearance: false,
        hasRepositories: false,
      );
    }

    final entities = await normalized.list(followLinks: false).toList();
    final manifestFile = manifestFileFor(normalized);
    final appearanceFile = appearanceFileFor(normalized);
    final pagesDir = pagesDirectoryFor(normalized);
    final reposDir = repositoriesDirectoryFor(normalized);

    final hasManifest =
        await FileSystemEntity.type(manifestFile.path, followLinks: false) ==
        FileSystemEntityType.file;
    final hasAppearance =
        await FileSystemEntity.type(appearanceFile.path, followLinks: false) ==
        FileSystemEntityType.file;
    final hasPages =
        await FileSystemEntity.type(pagesDir.path, followLinks: false) ==
        FileSystemEntityType.directory;
    final hasRepositories =
        await FileSystemEntity.type(reposDir.path, followLinks: false) ==
        FileSystemEntityType.directory;

    SandboxedApplicationManifest? manifest;
    if (hasManifest) {
      try {
        final raw = jsonDecode(
          await manifestFile.readAsString(encoding: utf8),
        );
        manifest = SandboxedApplicationManifest.fromJson(raw);
      } on Object {
        manifest = null;
      }
    }

    return SandboxedApplicationInspection(
      directory: normalized,
      exists: true,
      isSymlink: false,
      isDirectory: true,
      isEmpty: entities.isEmpty,
      hasManifest: hasManifest,
      hasAppearance: hasAppearance,
      hasPages: hasPages,
      hasRepositories: hasRepositories,
      manifest: manifest,
    );
  }

  /// Lit le chemin de la dernière application active dans `SharedPreferences`.
  Future<String?> loadActiveApplicationPath() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(activePathKey);
    if (value == null || value.trim().isEmpty) return null;
    return normalizePath(value);
  }

  /// Enregistre le chemin de l'application active dans `SharedPreferences`.
  Future<void> saveActiveApplicationPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(activePathKey);
    } else {
      await prefs.setString(activePathKey, normalizePath(path));
    }
  }

  /// Charge la liste des applications récentes, triée par date décroissante.
  Future<List<SandboxedApplicationEntry>> loadRecentApplications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(recentAppsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <SandboxedApplicationEntry>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <SandboxedApplicationEntry>[];
      final entries = <SandboxedApplicationEntry>[];
      for (final item in decoded) {
        try {
          var entry = SandboxedApplicationEntry.fromJson(item);
          final normalized = normalizePath(entry.path);
          final manifest = _tryReadManifestSync(Directory(normalized));
          entry = entry.copyWith(
            path: normalized,
            name: manifest?.name ?? entry.name,
          );
          if (!entries.any((existing) => samePath(existing.path, entry.path))) {
            entries.add(entry);
          }
        } on Object {
          // Ignore une entrée corrompue sans bloquer les autres.
        }
      }
      entries.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      return List<SandboxedApplicationEntry>.unmodifiable(entries);
    } on Object {
      return const <SandboxedApplicationEntry>[];
    }
  }

  /// Ajoute ou met à jour [appDir] en tête de l'historique des applications récentes.
  Future<List<SandboxedApplicationEntry>> recordRecentApplication(
    Directory appDir, {
    String? name,
  }) async {
    final normalized = normalizePath(appDir.path);
    final manifest = await _tryReadManifest(Directory(normalized));
    final resolvedName =
        (name?.trim().isNotEmpty == true ? name!.trim() : null) ??
        manifest?.name ??
        fallbackNameForDirectory(Directory(normalized));
    final current = await loadRecentApplications();
    final next = <SandboxedApplicationEntry>[
      SandboxedApplicationEntry(
        path: normalized,
        name: resolvedName,
        lastOpenedAt: DateTime.now().toUtc(),
      ),
      for (final item in current)
        if (!samePath(item.path, normalized)) item,
    ];
    final bounded = next.take(maxRecentCount).toList(growable: false);
    await _saveRecentEntries(bounded);
    return List<SandboxedApplicationEntry>.unmodifiable(bounded);
  }

  /// Retire [path] de la liste des applications récentes sans supprimer les fichiers sur disque.
  Future<List<SandboxedApplicationEntry>> removeRecentApplication(
    String path,
  ) async {
    final current = await loadRecentApplications();
    final next = current
        .where((item) => !samePath(item.path, path))
        .toList(growable: false);
    await _saveRecentEntries(next);
    return List<SandboxedApplicationEntry>.unmodifiable(next);
  }

  Future<void> _saveRecentEntries(
    List<SandboxedApplicationEntry> entries,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      recentAppsKey,
      jsonEncode([for (final entry in entries) entry.toJson()]),
    );
  }

  /// Ouvre un dossier d'application existant, vérifie son intégrité et le
  /// mémorise comme application active et récente.
  Future<SandboxedApplicationManifest> openApplication(
    Directory appDir, {
    bool initializeNonEmpty = false,
  }) async {
    final normalized = Directory(normalizePath(appDir.path));
    final inspection = await inspectDirectory(normalized);
    if (!inspection.exists) {
      throw FileSystemException(
        'Le dossier d’application est introuvable.',
        normalized.path,
      );
    }
    if (inspection.isSymlink || !inspection.isDirectory) {
      throw FileSystemException(
        'La cible sélectionnée doit être un dossier réel (hors lien symbolique).',
        normalized.path,
      );
    }
    if (!inspection.isEmpty &&
        !inspection.looksLikeSandboxedApp &&
        !initializeNonEmpty) {
      throw NonEmptyNonAppDirectoryException(
        'Ce dossier contient déjà d’autres fichiers et ne ressemble pas à une application sandboxée.',
        normalized.path,
      );
    }

    final now = DateTime.now().toUtc();
    final existing = inspection.manifest;
    final manifest = existing != null
        ? existing.copyWith(updatedAt: now)
        : SandboxedApplicationManifest(
            name: fallbackNameForDirectory(normalized),
            createdAt: now,
            updatedAt: now,
          );
    await _writeManifestAtomically(normalized, manifest);
    await repositoriesDirectoryFor(normalized).create(recursive: true);
    await saveActiveApplicationPath(normalized.path);
    await recordRecentApplication(normalized, name: manifest.name);
    return manifest;
  }

  /// Crée une nouvelle application sandboxée dans [targetDir], soit vide, soit
  /// en clonant `appearance.json` et `repositories/` depuis [cloneFromDirectory].
  Future<SandboxedApplicationManifest> createApplication(
    Directory targetDir, {
    required String name,
    Directory? cloneFromDirectory,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const FormatException('Le nom de l’application est requis.');
    }
    final normalized = Directory(normalizePath(targetDir.path));
    final inspection = await inspectDirectory(normalized);
    if (inspection.isSymlink) {
      throw FileSystemException(
        'Le dossier cible ne peut pas être un lien symbolique.',
        normalized.path,
      );
    }
    if (inspection.exists && !inspection.isDirectory) {
      throw FileSystemException(
        'La cible existe déjà et n’est pas un dossier.',
        normalized.path,
      );
    }
    if (inspection.exists && !inspection.isEmpty) {
      throw FileSystemException(
        'Le dossier cible doit être vide pour créer une nouvelle application.',
        normalized.path,
      );
    }

    if (cloneFromDirectory != null) {
      final source = Directory(normalizePath(cloneFromDirectory.path));
      final sourceInspection = await inspectDirectory(source);
      if (!sourceInspection.exists ||
          sourceInspection.isSymlink ||
          !sourceInspection.isDirectory) {
        throw FileSystemException(
          'Le dossier source à cloner est introuvable ou invalide.',
          source.path,
        );
      }
      if (isSameOrSubpath(normalized.path, source.path)) {
        throw const FormatException(
          'Le nouveau dossier ne peut pas être placé à l’intérieur de l’application clonée.',
        );
      }
      await normalized.create(recursive: true);
      await _copySandboxedData(source: source, target: normalized);
    } else {
      await normalized.create(recursive: true);
    }

    await repositoriesDirectoryFor(normalized).create(recursive: true);
    final now = DateTime.now().toUtc();
    final manifest = SandboxedApplicationManifest(
      name: trimmedName,
      createdAt: now,
      updatedAt: now,
    );
    await _writeManifestAtomically(normalized, manifest);
    await saveActiveApplicationPath(normalized.path);
    await recordRecentApplication(normalized, name: manifest.name);
    return manifest;
  }

  /// Résout (ou initialise au besoin) le dossier d'application actif au démarrage.
  Future<Directory> ensureDefaultApplication({
    String defaultName = 'Application par défaut',
  }) async {
    final savedPath = await loadActiveApplicationPath();
    if (savedPath != null) {
      final candidate = Directory(savedPath);
      final inspection = await inspectDirectory(candidate);
      if (inspection.exists && !inspection.isSymlink && inspection.isDirectory) {
        if (inspection.looksLikeSandboxedApp || inspection.isEmpty) {
          await openApplication(candidate);
          return Directory(normalizePath(candidate.path));
        }
      }
    }

    final fallback = Directory(normalizePath(defaultApplicationDirectory().path));
    final inspection = await inspectDirectory(fallback);
    if (!inspection.exists) {
      await createApplication(fallback, name: defaultName);
    } else if (!inspection.isSymlink && inspection.isDirectory) {
      await openApplication(fallback, initializeNonEmpty: true);
    } else {
      throw FileSystemException(
        'Le dossier d’application par défaut est invalide.',
        fallback.path,
      );
    }
    return fallback;
  }

  SandboxedApplicationManifest? _tryReadManifestSync(Directory appDir) {
    final file = manifestFileFor(appDir);
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
      return SandboxedApplicationManifest.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<SandboxedApplicationManifest?> _tryReadManifest(
    Directory appDir,
  ) async => _tryReadManifestSync(appDir);

  Future<void> _writeManifestAtomically(
    Directory appDir,
    SandboxedApplicationManifest manifest,
  ) async {
    final file = manifestFileFor(appDir);
    final fileType = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );
    if (fileType == FileSystemEntityType.link) {
      throw FileSystemException(
        'Le fichier app.json ne peut pas être un lien symbolique.',
        file.path,
      );
    }
    final content =
        '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n';
    final suffix = List.generate(
      12,
      (_) => Random().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temp = File('${file.path}.$pid.$suffix.tmp');
    await temp.create(exclusive: true);
    try {
      await temp.writeAsString(content, encoding: utf8, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await FileSystemEntity.type(temp.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await temp.delete();
      }
    }
  }

  Future<void> _copySandboxedData({
    required Directory source,
    required Directory target,
  }) async {
    final sourceAppearance = appearanceFileFor(source);
    if (await FileSystemEntity.type(
          sourceAppearance.path,
          followLinks: false,
        ) ==
        FileSystemEntityType.file) {
      await sourceAppearance.copy(appearanceFileFor(target).path);
    }
    final sourcePages = pagesDirectoryFor(source);
    if (await FileSystemEntity.type(sourcePages.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      await _copyDirectoryRecursive(
        source: sourcePages,
        target: pagesDirectoryFor(target),
      );
    }
    final sourceRepos = repositoriesDirectoryFor(source);
    if (await FileSystemEntity.type(sourceRepos.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      await _copyDirectoryRecursive(
        source: sourceRepos,
        target: repositoriesDirectoryFor(target),
      );
    }
  }

  Future<void> _copyDirectoryRecursive({
    required Directory source,
    required Directory target,
  }) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final type = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link) continue;
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (name.endsWith('.tmp')) continue;
      final destinationPath =
          '${target.path}${Platform.pathSeparator}$name';
      if (type == FileSystemEntityType.directory) {
        await _copyDirectoryRecursive(
          source: Directory(entity.path),
          target: Directory(destinationPath),
        );
      } else if (type == FileSystemEntityType.file) {
        await File(entity.path).copy(destinationPath);
      }
    }
  }
}
