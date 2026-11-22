/// Gestionnaire réactif de téléchargement, cache disque et chargement à chaud des polices ([DynamicFontManager]).
///
/// Orchestre la résolution d'une famille de polices entre les polices embarquées
/// ([Registry.bundledPackageFontFamilies]), les polices système ([Registry.defaultAvailableFontFamilies]),
/// le cache disque persistant (`~/.super_container_layout/fonts/<slug>/`) et le téléchargement
/// à la volée via [GoogleFontsDownloader]. Enregistre chaque variante dans Flutter grâce à
/// [FontLoader] et expose les octets `.ttf`/`.otf` mis en cache à [PdfFontResolver].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/services.dart' show FontLoader;

import '../../ai/design_md_parser.dart';
import '../../ai/design_system_catalog.dart';
import '../../models/registry.dart';
import '../../models/super_action_config.dart';
import '../../models/super_indicator_config.dart';
import '../../models/super_separator_config.dart';
import '../../models/super_value_config.dart';
import '../../theme/appearance.dart';
import '../repositories/json_repository_store.dart';
import 'design_md_font_extractor.dart';
import 'dynamic_font_models.dart';
import 'google_fonts_downloader.dart';

/// Callback d'enregistrement de variantes binaires auprès du moteur de polices Flutter.
typedef DynamicFontRegistrar =
    Future<void> Function(String family, List<ByteData> fonts);

/// Variante binaire mise en cache pour réutilisation par [PdfFontResolver].
typedef CachedFontVariantBytes = ({
  DynamicFontVariantFile meta,
  Uint8List bytes,
});

/// Gestionnaire central des polices chargées dynamiquement.
class DynamicFontManager extends ChangeNotifier {
  /// Crée un [DynamicFontManager] personnalisable (cache disque, téléchargeur, enregistreur).
  DynamicFontManager({
    Directory? cacheDirectory,
    GoogleFontsDownloader? downloader,
    DynamicFontRegistrar? registerFont,
    this.autoDownloadEnabled = true,
    bool useDefaultCacheDirectory = true,
  }) : cacheDirectory =
           cacheDirectory ??
           (useDefaultCacheDirectory ? tryDefaultCacheDirectory() : null),
       _downloader = downloader ?? GoogleFontsDownloader(),
       _registerFont = registerFont ?? _defaultFontRegistrar;

  /// Crée un gestionnaire stockant son cache sous `<store.directory>/fonts`.
  factory DynamicFontManager.forRepositoryStore(
    JsonRepositoryStore store, {
    GoogleFontsDownloader? downloader,
    DynamicFontRegistrar? registerFont,
    bool autoDownloadEnabled = true,
  }) => DynamicFontManager(
    cacheDirectory: Directory(
      '${store.directory.path}${Platform.pathSeparator}fonts',
    ),
    downloader: downloader,
    registerFont: registerFont,
    autoDownloadEnabled: autoDownloadEnabled,
  );

  /// Instance partagée par défaut utilisée lorsque aucun gestionnaire dédié n'est injecté.
  static final DynamicFontManager shared = DynamicFontManager();

  /// Résout le dossier utilisateur par défaut `~/.super_container_layout/fonts`.
  static Directory? tryDefaultCacheDirectory() {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.trim().isEmpty) return null;
    return Directory(
      '$home${Platform.pathSeparator}.super_container_layout'
      '${Platform.pathSeparator}fonts',
    );
  }

  static Future<void> _defaultFontRegistrar(
    String family,
    List<ByteData> fonts,
  ) async {
    final loader = FontLoader(family);
    for (final font in fonts) {
      loader.addFont(Future<ByteData>.value(font));
    }
    await loader.load();
  }

  /// Dossier de cache disque persistant (`null` = mode mémoire uniquement).
  final Directory? cacheDirectory;

  /// Autorise le téléchargement automatique déclenché par les composants et l'application.
  final bool autoDownloadEnabled;

  final GoogleFontsDownloader _downloader;
  final DynamicFontRegistrar _registerFont;

  final Map<String, DynamicFontEntry> _entries = <String, DynamicFontEntry>{};
  final Map<String, Future<DynamicFontLoadResult>> _inFlight =
      <String, Future<DynamicFontLoadResult>>{};
  final Map<String, List<CachedFontVariantBytes>> _variantBytesByKey =
      <String, List<CachedFontVariantBytes>>{};
  final List<String> _loadedFamiliesOrder = <String>[];
  bool _didLoadDiskCache = false;
  Future<int>? _loadDiskCacheFuture;

  /// Liste immuable des familles de polices chargées dynamiquement (ordre de chargement).
  List<String> get loadedFontFamilies =>
      List<String>.unmodifiable(_loadedFamiliesOrder);

  /// Indique si au moins un téléchargement de police est actuellement en cours.
  bool get hasPendingDownloads => _inFlight.isNotEmpty;

  /// Nombre de téléchargements simultanés en cours.
  int get pendingDownloadCount => _inFlight.length;

  static String _keyOf(String family) => family.trim().toLowerCase();

  static String? _canonicalBundled(String family) {
    final key = _keyOf(family);
    for (final bundled in Registry.bundledPackageFontFamilies) {
      if (bundled.toLowerCase() == key) return bundled;
    }
    return null;
  }

  static String? _canonicalBuiltInSystem(String family) {
    final key = _keyOf(family);
    for (final item in Registry.defaultAvailableFontFamilies) {
      if (item.toLowerCase() == key &&
          !Registry.bundledPackageFontFamilies.contains(item)) {
        return item;
      }
    }
    return null;
  }

  /// Retourne le statut actuel d'une famille [family] sans déclencher de téléchargement.
  DynamicFontStatus statusOf(String? family) {
    if (family == null || family.trim().isEmpty) {
      return DynamicFontStatus.system;
    }
    final cleaned = DesignMdFontExtractor.cleanFontFamilyToken(family);
    if (cleaned == null) return DynamicFontStatus.notFound;
    if (_canonicalBundled(cleaned) != null) return DynamicFontStatus.bundled;
    if (_canonicalBuiltInSystem(cleaned) != null) {
      return DynamicFontStatus.system;
    }
    final entry = _entries[_keyOf(cleaned)];
    if (entry != null) return entry.status;
    return DynamicFontStatus.notFound;
  }

  /// Retourne l'entrée détaillée associée à [family], si suivie par ce gestionnaire.
  DynamicFontEntry? entryOf(String? family) {
    if (family == null || family.trim().isEmpty) return null;
    final cleaned = DesignMdFontExtractor.cleanFontFamilyToken(family);
    if (cleaned == null) return null;
    return _entries[_keyOf(cleaned)];
  }

  /// Indique si [family] a déjà été résolue ou tentée durant cette session.
  bool hasAttempted(String family) {
    final cleaned = DesignMdFontExtractor.cleanFontFamilyToken(family);
    if (cleaned == null) return true;
    if (_canonicalBundled(cleaned) != null ||
        _canonicalBuiltInSystem(cleaned) != null) {
      return true;
    }
    return _entries.containsKey(_keyOf(cleaned));
  }

  /// Fusionne [base] avec les polices chargées dynamiquement, sans doublons.
  List<String> effectiveAvailableFontFamilies([
    List<String> base = Registry.defaultAvailableFontFamilies,
  ]) {
    if (_loadedFamiliesOrder.isEmpty) return base;
    final seen = <String>{for (final f in base) f.toLowerCase()};
    final merged = List<String>.of(base);
    for (final loaded in _loadedFamiliesOrder) {
      if (seen.add(loaded.toLowerCase())) {
        merged.add(loaded);
      }
    }
    return List<String>.unmodifiable(merged);
  }

  /// Retourne les variantes `.ttf`/`.otf` en mémoire (ou sur disque) pour [family], pour [PdfFontResolver].
  List<CachedFontVariantBytes>? cachedVariantsFor(String family) {
    final cleaned = DesignMdFontExtractor.cleanFontFamilyToken(family);
    if (cleaned == null) return null;
    final key = _keyOf(cleaned);
    final inMemory = _variantBytesByKey[key];
    if (inMemory != null && inMemory.isNotEmpty) return inMemory;

    final disk = _readCachedFamilyFromDiskSync(cleaned);
    if (disk != null && disk.variants.isNotEmpty) {
      _variantBytesByKey[key] = disk.variants;
      return disk.variants;
    }
    return null;
  }

  /// Recharge en arrière-plan toutes les polices déjà présentes dans [cacheDirectory].
  ///
  /// Retourne le nombre de familles rechargées avec succès. Idempotent.
  Future<int> loadCachedFonts() {
    if (_didLoadDiskCache) return Future<int>.value(_loadedFamiliesOrder.length);
    return _loadDiskCacheFuture ??= _loadCachedFontsInternal();
  }

  Future<int> _loadCachedFontsInternal() async {
    final dir = cacheDirectory;
    if (dir == null) {
      _didLoadDiskCache = true;
      return 0;
    }
    var loadedCount = 0;
    try {
      final dirType = FileSystemEntity.typeSync(dir.path, followLinks: false);
      if (dirType != FileSystemEntityType.directory) {
        _didLoadDiskCache = true;
        return 0;
      }
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final disk = _readManifestDirectorySync(entity);
        if (disk == null || disk.variants.isEmpty) continue;
        final key = _keyOf(disk.family);
        if (_canonicalBundled(disk.family) != null ||
            _canonicalBuiltInSystem(disk.family) != null) {
          continue;
        }
        if (_entries[key]?.status == DynamicFontStatus.loaded) continue;
        try {
          await _registerFont(
            disk.family,
            [
              for (final variant in disk.variants)
                ByteData.sublistView(variant.bytes),
            ],
          );
          _recordLoaded(
            family: disk.family,
            variants: disk.variants,
            cacheDirPath: entity.path,
            fromCache: true,
          );
          loadedCount++;
        } catch (_) {
          // Ignore un dossier de cache corrompu sans bloquer les autres polices.
        }
      }
    } catch (_) {
      // Ignore les erreurs d'accès au répertoire de cache.
    } finally {
      _didLoadDiskCache = true;
      if (loadedCount > 0) {
        notifyListeners();
      }
    }
    return loadedCount;
  }

  /// Garantit que [family] est chargée dans Flutter (cache disque ou Google Fonts).
  ///
  /// Déduplique les appels simultanés et mémorise les échecs sauf si [forceRetry] vaut `true`.
  Future<DynamicFontLoadResult> ensureFontLoaded(
    String family, {
    bool forceRetry = false,
  }) async {
    final cleaned = DesignMdFontExtractor.cleanFontFamilyToken(family);
    if (cleaned == null || DesignMdFontExtractor.isGenericOrIgnoredFontName(cleaned)) {
      return DynamicFontLoadResult(
        family: family.trim(),
        status: DynamicFontStatus.notFound,
        error: 'Nom de police générique ou invalide.',
      );
    }

    if (_canonicalBundled(cleaned) case final bundled?) {
      return DynamicFontLoadResult(
        family: bundled,
        status: DynamicFontStatus.bundled,
      );
    }
    if (_canonicalBuiltInSystem(cleaned) case final system?) {
      return DynamicFontLoadResult(
        family: system,
        status: DynamicFontStatus.system,
      );
    }

    final key = _keyOf(cleaned);
    final existing = _entries[key];
    if (existing != null && existing.status == DynamicFontStatus.loaded) {
      return DynamicFontLoadResult(
        family: existing.family,
        status: DynamicFontStatus.loaded,
        loadedFileCount: existing.variants.length,
        fromCache: existing.fromCache,
      );
    }

    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    if (!forceRetry &&
        existing != null &&
        (existing.status == DynamicFontStatus.notFound ||
            existing.status == DynamicFontStatus.failed)) {
      return DynamicFontLoadResult(
        family: existing.family,
        status: existing.status,
        error: existing.error,
      );
    }

    final future = _loadOrDownloadFamily(cleaned, key);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    }
  }

  /// Charge plusieurs familles [families] en parallèle et retourne le résultat par famille.
  Future<Map<String, DynamicFontLoadResult>> ensureFontsLoaded(
    Iterable<String> families, {
    bool forceRetry = false,
  }) async {
    final distinct = <String>[];
    final seen = <String>{};
    for (final raw in families) {
      final cleaned = DesignMdFontExtractor.cleanFontFamilyToken(raw);
      if (cleaned == null ||
          DesignMdFontExtractor.isGenericOrIgnoredFontName(cleaned)) {
        continue;
      }
      if (seen.add(cleaned.toLowerCase())) {
        distinct.add(cleaned);
      }
    }
    if (distinct.isEmpty) return const <String, DynamicFontLoadResult>{};

    final results = await Future.wait([
      for (final family in distinct)
        ensureFontLoaded(family, forceRetry: forceRetry),
    ]);
    return Map<String, DynamicFontLoadResult>.unmodifiable({
      for (var i = 0; i < distinct.length; i++) distinct[i]: results[i],
    });
  }

  /// Extrait et précharge toutes les polices manquantes référencées par [preset] (et [markdown]).
  Future<Map<String, DynamicFontLoadResult>> ensureDesignSystemFonts(
    DesignSystemPreset preset, {
    String? markdown,
    bool forceRetry = false,
  }) {
    final families = DesignMdFontExtractor.extractFontFamilies(
      fontHint: preset.palette.fontHint,
      markdown: markdown ?? preset.inlineMarkdown,
    );
    return ensureFontsLoaded(families, forceRetry: forceRetry);
  }

  /// Collecte et précharge toutes les polices référencées par les composants d'[appearance].
  Future<Map<String, DynamicFontLoadResult>> ensureAppearanceFonts(
    Appearance appearance, {
    bool forceRetry = false,
  }) {
    final families = extractAppearanceFontFamilies(appearance);
    return ensureFontsLoaded(families, forceRetry: forceRetry);
  }

  /// Extrait les familles de polices configurées dans les composants d'[appearance].
  static List<String> extractAppearanceFontFamilies(Appearance appearance) {
    final found = <String>[];
    final seen = <String>{};

    void add(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      final cleaned = DesignMdFontExtractor.cleanFontFamilyToken(raw);
      if (cleaned == null) return;
      if (seen.add(cleaned.toLowerCase())) {
        found.add(cleaned);
      }
    }

    for (final config in appearance.components.values) {
      switch (config) {
        case final SuperValueConfig value:
          add(value.fontFamily);
          final states = value.states;
          if (states != null) {
            add(states.hover?.config.fontFamily);
            add(states.selected?.config.fontFamily);
            for (final auto in states.automatic.values) {
              add(auto.config.fontFamily);
            }
            for (final named in states.named.values) {
              add(named.fontFamily);
            }
          }
        case final SuperActionConfig action:
          add(action.fontFamily);
          final states = action.states;
          if (states != null) {
            add(states.hover?.config.fontFamily);
            add(states.selected?.config.fontFamily);
            for (final auto in states.automatic.values) {
              add(auto.config.fontFamily);
            }
            for (final named in states.named.values) {
              add(named.fontFamily);
            }
          }
        case final SuperIndicatorConfig indicator:
          add(indicator.fontFamily);
          final states = indicator.states;
          if (states != null) {
            add(states.hover?.config.fontFamily);
            add(states.selected?.config.fontFamily);
            for (final auto in states.automatic.values) {
              add(auto.config.fontFamily);
            }
            for (final named in states.named.values) {
              add(named.fontFamily);
            }
          }
        case final SuperSeparatorConfig separator:
          add(separator.fontFamily);
          final states = separator.states;
          if (states != null) {
            add(states.hover?.config.fontFamily);
            add(states.selected?.config.fontFamily);
            for (final auto in states.automatic.values) {
              add(auto.config.fontFamily);
            }
            for (final named in states.named.values) {
              add(named.fontFamily);
            }
          }
        default:
          break;
      }
    }
    return List<String>.unmodifiable(found);
  }

  Future<DynamicFontLoadResult> _loadOrDownloadFamily(
    String canonicalFamily,
    String key,
  ) async {
    // 1. Vérifie d'abord le cache disque avant tout appel réseau.
    final cached = _readCachedFamilyFromDiskSync(canonicalFamily);
    if (cached != null && cached.variants.isNotEmpty) {
      try {
        await _registerFont(
          cached.family,
          [
            for (final variant in cached.variants)
              ByteData.sublistView(variant.bytes),
          ],
        );
        _recordLoaded(
          family: cached.family,
          variants: cached.variants,
          cacheDirPath: cached.directoryPath,
          fromCache: true,
        );
        notifyListeners();
        return DynamicFontLoadResult(
          family: cached.family,
          status: DynamicFontStatus.loaded,
          loadedFileCount: cached.variants.length,
          fromCache: true,
        );
      } catch (_) {
        // Si le cache est corrompu, retombe sur un téléchargement propre.
      }
    }

    // 2. Téléchargement Google Fonts.
    _entries[key] = DynamicFontEntry(
      family: canonicalFamily,
      status: DynamicFontStatus.loading,
    );
    notifyListeners();

    final response = await _downloader.download(canonicalFamily);
    if (!response.isSuccess) {
      final status = response.notFound
          ? DynamicFontStatus.notFound
          : DynamicFontStatus.failed;
      _entries[key] = DynamicFontEntry(
        family: canonicalFamily,
        status: status,
        error: response.error,
      );
      notifyListeners();
      return DynamicFontLoadResult(
        family: canonicalFamily,
        status: status,
        error: response.error,
      );
    }

    final variantEntries = <CachedFontVariantBytes>[];
    for (var i = 0; i < response.variants.length; i++) {
      final variant = response.variants[i];
      final styleTag = variant.italic ? 'italic' : 'regular';
      final fileName = 'w${variant.weight}_${styleTag}_$i.${variant.extension}';
      variantEntries.add((
        meta: DynamicFontVariantFile(
          fileName: fileName,
          weight: variant.weight,
          italic: variant.italic,
        ),
        bytes: variant.bytes,
      ));
    }

    try {
      await _registerFont(
        canonicalFamily,
        [
          for (final variant in variantEntries)
            ByteData.sublistView(variant.bytes),
        ],
      );
    } catch (error) {
      final message = 'Échec de l’enregistrement FontLoader : $error';
      _entries[key] = DynamicFontEntry(
        family: canonicalFamily,
        status: DynamicFontStatus.failed,
        error: message,
      );
      notifyListeners();
      return DynamicFontLoadResult(
        family: canonicalFamily,
        status: DynamicFontStatus.failed,
        error: message,
      );
    }

    final cacheDirPath = _writeFamilyToDiskCacheBestEffort(
      canonicalFamily,
      variantEntries,
    );

    _recordLoaded(
      family: canonicalFamily,
      variants: variantEntries,
      cacheDirPath: cacheDirPath,
      fromCache: false,
    );
    notifyListeners();
    return DynamicFontLoadResult(
      family: canonicalFamily,
      status: DynamicFontStatus.loaded,
      loadedFileCount: variantEntries.length,
      fromCache: false,
    );
  }

  void _recordLoaded({
    required String family,
    required List<CachedFontVariantBytes> variants,
    required String? cacheDirPath,
    required bool fromCache,
  }) {
    final key = _keyOf(family);
    _entries[key] = DynamicFontEntry(
      family: family,
      status: DynamicFontStatus.loaded,
      variants: [for (final v in variants) v.meta],
      cacheDirectoryPath: cacheDirPath,
      fromCache: fromCache,
    );
    _variantBytesByKey[key] = List<CachedFontVariantBytes>.unmodifiable(
      variants,
    );
    if (!_loadedFamiliesOrder.any((item) => item.toLowerCase() == key)) {
      _loadedFamiliesOrder.add(family);
    }
  }

  String? _writeFamilyToDiskCacheBestEffort(
    String family,
    List<CachedFontVariantBytes> variants,
  ) {
    final root = cacheDirectory;
    if (root == null) return null;
    try {
      final rootType = FileSystemEntity.typeSync(root.path, followLinks: false);
      if (rootType == FileSystemEntityType.link) return null;
      if (rootType == FileSystemEntityType.notFound) {
        root.createSync(recursive: true);
      }

      final slug = DesignMdParser.slugify(family);
      final familyDir = Directory(
        '${root.path}${Platform.pathSeparator}$slug',
      );
      final familyDirType = FileSystemEntity.typeSync(
        familyDir.path,
        followLinks: false,
      );
      if (familyDirType == FileSystemEntityType.link) return null;
      if (familyDirType == FileSystemEntityType.notFound) {
        familyDir.createSync(recursive: true);
      }

      final rng = Random();
      for (final variant in variants) {
        final target = File(
          '${familyDir.path}${Platform.pathSeparator}${variant.meta.fileName}',
        );
        final temp = File('${target.path}.tmp.$pid.${rng.nextInt(1 << 30)}');
        try {
          temp.writeAsBytesSync(variant.bytes, flush: true);
          temp.renameSync(target.path);
        } catch (_) {
          if (temp.existsSync()) temp.deleteSync();
          rethrow;
        }
      }

      final manifestFile = File(
        '${familyDir.path}${Platform.pathSeparator}manifest.json',
      );
      final manifestTemp = File(
        '${manifestFile.path}.tmp.$pid.${rng.nextInt(1 << 30)}',
      );
      final manifestJson = jsonEncode(<String, Object?>{
        'family': family,
        'variants': [for (final v in variants) v.meta.toJson()],
      });
      try {
        manifestTemp.writeAsStringSync(manifestJson, encoding: utf8, flush: true);
        manifestTemp.renameSync(manifestFile.path);
      } catch (_) {
        if (manifestTemp.existsSync()) manifestTemp.deleteSync();
        rethrow;
      }

      return familyDir.path;
    } catch (_) {
      return null;
    }
  }

  ({
    String family,
    String directoryPath,
    List<CachedFontVariantBytes> variants,
  })?
  _readCachedFamilyFromDiskSync(String family) {
    final root = cacheDirectory;
    if (root == null) return null;
    final slug = DesignMdParser.slugify(family);
    final familyDir = Directory('${root.path}${Platform.pathSeparator}$slug');
    return _readManifestDirectorySync(familyDir);
  }

  ({
    String family,
    String directoryPath,
    List<CachedFontVariantBytes> variants,
  })?
  _readManifestDirectorySync(Directory familyDir) {
    try {
      final dirType = FileSystemEntity.typeSync(
        familyDir.path,
        followLinks: false,
      );
      if (dirType != FileSystemEntityType.directory) return null;
      final manifestFile = File(
        '${familyDir.path}${Platform.pathSeparator}manifest.json',
      );
      if (FileSystemEntity.typeSync(manifestFile.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final raw = jsonDecode(manifestFile.readAsStringSync(encoding: utf8));
      if (raw is! Map) return null;
      final family = (raw['family'] as String? ?? '').trim();
      final rawVariants = raw['variants'];
      if (family.isEmpty || rawVariants is! List || rawVariants.isEmpty) {
        return null;
      }
      final loaded = <CachedFontVariantBytes>[];
      for (final item in rawVariants) {
        if (item is! Map) continue;
        final meta = DynamicFontVariantFile.fromJson(
          Map<String, Object?>.from(item),
        );
        // Empêche toute traversée de chemin hors du dossier de la famille.
        if (meta.fileName.contains('/') ||
            meta.fileName.contains(r'\') ||
            meta.fileName.contains('..')) {
          continue;
        }
        final file = File(
          '${familyDir.path}${Platform.pathSeparator}${meta.fileName}',
        );
        if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final bytes = file.readAsBytesSync();
        if (!GoogleFontsDownloader.hasValidFontSignature(bytes)) continue;
        loaded.add((meta: meta, bytes: bytes));
      }
      if (loaded.isEmpty) return null;
      return (
        family: family,
        directoryPath: familyDir.path,
        variants: loaded,
      );
    } catch (_) {
      return null;
    }
  }
}
