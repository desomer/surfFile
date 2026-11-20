/// Service de persistance multi-fichiers ([PagedFileAppearanceStore]) de l'[Appearance].
///
/// Conserve les réglages globaux, le catalogue [EditorPageCatalog], la page `'/'`
/// (`root` / `mainLayout`), le fond global et les éléments partagés dans
/// `<appDir>/appearance.json`, et persiste les configurations exclusives de
/// chaque page du catalogue dans un fichier dédié `<appDir>/pages/<pageId>.json`
/// chargé à la demande et réécrit de manière incrémentale et atomique.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate' show Isolate;
import 'dart:math';

import '../../models/json_numbers.dart';
import '../../models/registry.dart';
import '../../theme/appearance.dart';
import '../pages/editor_page_graph.dart';
import 'appearance_codec.dart';
import 'file_appearance_store.dart';

Map<String, dynamic> _decodePagedJsonMapInIsolate(String text) {
  final json = jsonDecode(text);
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Document JSON d’apparence invalide.');
  }
  return json;
}

String _normalizeAndEncodePagedMapInIsolate(Map<String, Object?> rawJson) =>
    jsonEncode(JsonNumbers.normalizeMap(rawJson));

({Map<String, dynamic> raw, String normalized})
_decodeAndNormalizePagedMapInIsolate(String encoded) {
  final decoded = _decodePagedJsonMapInIsolate(encoded);
  final normalized = jsonEncode(JsonNumbers.normalize(decoded));
  return (raw: decoded, normalized: normalized);
}

Future<Map<String, dynamic>> _runDecodePagedJsonMapInIsolate(String text) =>
    Isolate.run(() => _decodePagedJsonMapInIsolate(text));

Future<String> _runNormalizeAndEncodePagedMapInIsolate(
  Map<String, Object?> rawJson,
) => Isolate.run(() => _normalizeAndEncodePagedMapInIsolate(rawJson));

Future<({Map<String, dynamic> raw, String normalized})>
_runDecodeAndNormalizePagedMapInIsolate(String encoded) =>
    Isolate.run(() => _decodeAndNormalizePagedMapInIsolate(encoded));

/// Magasin d'apparence persistant l'état global dans [file] (`appearance.json`)
/// et chaque page du catalogue dans un fichier individuel sous [pagesDirectory] (`pages/<pageId>.json`).
class PagedFileAppearanceStore extends FileAppearanceStore {
  /// Crée un magasin paginé associé à [file] et au dossier [pagesDirectory].
  PagedFileAppearanceStore(
    super.file, {
    required this.pagesDirectory,
    this.registry,
    super.codec,
    super.isolateThresholdBytes,
    super.isolateThresholdEntries,
    super.maxFileBytes,
  });

  /// Identifiant de format des fichiers de page (`pages/<pageId>.json`).
  static const String pageFormatId = 'super_container_layout.page';

  /// Version courante du schéma des fichiers de page.
  static const int pageSchemaVersion = 1;

  /// Dossier contenant les fichiers JSON individuels des pages (`<appDir>/pages`).
  final Directory pagesDirectory;

  /// Registre optionnel utilisé pour résoudre la propriété des composants lors du partitionnement.
  Registry? registry;
  final Set<String> _loadedPageIds = <String>{};
  final Set<String> _knownCatalogPageIds = <String>{};
  final Set<String> _globalProtectedIds = <String>{};
  final Map<String, EditorPageAppearanceSlice> _persistedPages =
      <String, EditorPageAppearanceSlice>{};
  final Map<String, Future<EditorPageAppearanceSlice>> _inFlightPageLoads =
      <String, Future<EditorPageAppearanceSlice>>{};
  String? _persistedGlobalEncoded;
  Future<void>? _ioQueue;

  /// Associe ou met à jour le [Registry] utilisé pour résoudre la propriété des composants.
  void bindRegistry(Registry? value) {
    registry = value;
  }

  /// Retourne l'ensemble non modifiable des identifiants de pages déjà chargés ou créés en session.
  Set<String> get loadedPageIds => Set.unmodifiable(_loadedPageIds);

  /// Indique si la page [pageId] a déjà été chargée depuis le disque (ou créée en session).
  bool isPageLoaded(String pageId) => _loadedPageIds.contains(pageId);

  /// Retourne le nom de fichier sûr correspondant à [pageId] dans [pagesDirectory].
  static String pageFileNameFor(String pageId) {
    final trimmed = pageId.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Identifiant de page vide.');
    }
    var encoded = Uri.encodeComponent(trimmed).replaceAll('.', '%2E');
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
      caseSensitive: false,
    ).hasMatch(encoded)) {
      encoded = 'page_$encoded';
    }
    return '$encoded.json';
  }

  /// Retourne le fichier cible `<pagesDirectory>/<pageId>.json` pour [pageId].
  static File pageFileForDirectory(Directory pagesDir, String pageId) => File(
    '${_normalizeDirPath(pagesDir.path)}${Platform.pathSeparator}'
    '${pageFileNameFor(pageId)}',
  );

  /// Retourne le fichier cible de [pageId] pour ce magasin.
  File pageFileFor(String pageId) =>
      pageFileForDirectory(pagesDirectory, pageId);

  static String _normalizeDirPath(String rawPath) {
    var path = rawPath.trim();
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

  Future<R> _serializedIo<R>(Future<R> Function() action) async {
    final previous = _ioQueue;
    final gate = Completer<void>();
    _ioQueue = gate.future;
    if (previous != null) {
      await previous.catchError((Object _) {});
    }
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_ioQueue, gate.future)) {
        _ioQueue = null;
      }
    }
  }

  Future<void> _ensureSafeFileTarget(
    File target, {
    required bool createParent,
  }) async {
    final parentType = await FileSystemEntity.type(
      target.parent.path,
      followLinks: false,
    );
    if (parentType == FileSystemEntityType.link) {
      throw FileSystemException(
        'Le dossier cible ne peut pas être un lien symbolique.',
        target.parent.path,
      );
    }
    if (parentType == FileSystemEntityType.notFound) {
      if (createParent) {
        await target.parent.create(recursive: true);
      }
    } else if (parentType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Le parent du fichier cible n’est pas un dossier.',
        target.parent.path,
      );
    }

    final targetType = await FileSystemEntity.type(
      target.path,
      followLinks: false,
    );
    if (targetType == FileSystemEntityType.link) {
      throw FileSystemException(
        'Le fichier cible ne peut pas être un lien symbolique.',
        target.path,
      );
    }
    if (targetType != FileSystemEntityType.notFound &&
        targetType != FileSystemEntityType.file) {
      throw FileSystemException(
        'La cible n’est pas un fichier régulier.',
        target.path,
      );
    }
  }

  Future<String?> _readTextIfPresent(File target) async {
    await _ensureSafeFileTarget(target, createParent: false);
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    final stat = await target.stat();
    if (stat.size > maxFileBytes) {
      throw FileSystemException(
        'Le fichier dépasse la taille maximale autorisée.',
        target.path,
      );
    }
    return target.readAsString(encoding: utf8);
  }

  Future<void> _writeAtomicallyTo(File target, String content) async {
    await _ensureSafeFileTarget(target, createParent: true);
    final suffix = List.generate(
      12,
      (_) => Random().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temp = File('${target.path}.$pid.$suffix.tmp');
    await temp.create(exclusive: true);
    try {
      await temp.writeAsString(content, encoding: utf8, flush: true);
      await temp.rename(target.path);
    } finally {
      if (await FileSystemEntity.type(temp.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await temp.delete();
      }
    }
  }

  Future<void> _deleteIfPresent(File target) async {
    await _ensureSafeFileTarget(target, createParent: false);
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      await target.delete();
    }
  }

  static Set<String> _collectIds(Appearance appearance) => <String>{
    ...appearance.styles.keys,
    ...appearance.components.keys,
    ...appearance.behaviors.keys,
    ...appearance.usages.keys,
  };

  @override
  Future<Appearance> load() async {
    _loadedPageIds.clear();
    _knownCatalogPageIds.clear();
    _globalProtectedIds.clear();
    _persistedPages.clear();
    _inFlightPageLoads.clear();
    _persistedGlobalEncoded = null;

    final stored = await _serializedIo(() => _readTextIfPresent(file));
    if (stored == null || stored.trim().isEmpty) {
      codec.resetAdditional();
      return codec.defaults;
    }

    final Appearance result;
    if (stored.length >= isolateThresholdBytes) {
      final decoded = await _runDecodePagedJsonMapInIsolate(stored);
      result = codec.fromJson(decoded);
      _persistedGlobalEncoded = await _runNormalizeAndEncodePagedMapInIsolate(
        decoded,
      );
    } else {
      final decoded = _decodePagedJsonMapInIsolate(stored);
      result = codec.fromJson(decoded);
      _persistedGlobalEncoded = jsonEncode(JsonNumbers.normalize(decoded));
    }
    codec.restoreAdditional(stored);
    _knownCatalogPageIds.addAll(result.pageCatalog.pages.map((p) => p.id));
    _globalProtectedIds.addAll(_collectIds(result));
    if (codec.needsMigration(stored)) {
      await save(result);
    }
    return result;
  }

  /// Charge à la demande la tranche JSON dédiée à [pageId] depuis [pagesDirectory].
  ///
  /// Retourne une tranche vide si le fichier `pages/<pageId>.json` n'existe pas
  /// encore sur disque. Les lectures concurrentes pour un même [pageId] sont
  /// dédupliquées.
  Future<EditorPageAppearanceSlice> loadPage(String pageId) {
    final trimmed = pageId.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Identifiant de page vide.');
    }
    if (_loadedPageIds.contains(trimmed)) {
      return Future<EditorPageAppearanceSlice>.value(
        const EditorPageAppearanceSlice.empty(),
      );
    }
    final inFlight = _inFlightPageLoads[trimmed];
    if (inFlight != null) return inFlight;

    final future = _performLoadPage(trimmed);
    _inFlightPageLoads[trimmed] = future;
    return future.whenComplete(() {
      if (identical(_inFlightPageLoads[trimmed], future)) {
        _inFlightPageLoads.remove(trimmed);
      }
    });
  }

  Future<EditorPageAppearanceSlice> _performLoadPage(String pageId) async {
    final target = pageFileFor(pageId);
    final rawText = await _serializedIo(() => _readTextIfPresent(target));
    if (rawText == null || rawText.trim().isEmpty) {
      _loadedPageIds.add(pageId);
      _persistedPages[pageId] = const EditorPageAppearanceSlice.empty();
      return const EditorPageAppearanceSlice.empty();
    }

    final Map<String, dynamic> decoded;
    if (rawText.length >= isolateThresholdBytes) {
      decoded = await _runDecodePagedJsonMapInIsolate(rawText);
    } else {
      decoded = _decodePagedJsonMapInIsolate(rawText);
    }

    final slice = _decodePageSlice(pageId, decoded);
    _loadedPageIds.add(pageId);
    _persistedPages[pageId] = slice;
    return slice;
  }

  EditorPageAppearanceSlice _decodePageSlice(
    String expectedPageId,
    Map<String, dynamic> json,
  ) {
    const allowedKeys = {
      'format',
      'version',
      'pageId',
      'styles',
      'components',
      'behaviors',
      'usages',
    };
    final unknownKeys = json.keys
        .where((key) => !allowedKeys.contains(key))
        .toList();
    if (unknownKeys.isNotEmpty) {
      throw FormatException(
        'Clé inconnue dans le fichier de page "$expectedPageId" : '
        '${unknownKeys.join(', ')}.',
      );
    }
    final format = json['format'];
    if (format != null && format != pageFormatId) {
      throw FormatException(
        'Format de fichier de page invalide pour "$expectedPageId" : $format.',
      );
    }
    final version = json['version'];
    if (version != null && version != pageSchemaVersion) {
      throw FormatException(
        'Version de fichier de page non prise en charge pour "$expectedPageId" : $version.',
      );
    }
    final declaredPageId = json['pageId'];
    if (declaredPageId != null &&
        (declaredPageId is! String || declaredPageId.trim() != expectedPageId)) {
      throw FormatException(
        'Identifiant de page incohérent dans le fichier "$expectedPageId" : $declaredPageId.',
      );
    }

    final synthetic = <String, dynamic>{
      'version': codec.schemaVersion,
      if (json.containsKey('styles')) 'styles': json['styles'],
      if (json.containsKey('components')) 'components': json['components'],
      if (json.containsKey('behaviors')) 'behaviors': json['behaviors'],
      if (json.containsKey('usages')) 'usages': json['usages'],
    };
    final parsed = codec.additionalKeys.isEmpty
        ? codec.fromJson(synthetic)
        : const AppearanceCodec().fromJson(synthetic);

    return EditorPageAppearanceSlice(
      styles: parsed.styles,
      components: parsed.components,
      behaviors: parsed.behaviors,
      usages: parsed.usages,
    );
  }

  Map<String, Object?> _encodePageSliceMap(
    String pageId,
    EditorPageAppearanceSlice slice,
  ) => {
    'format': pageFormatId,
    'version': pageSchemaVersion,
    'pageId': pageId,
    'styles': {
      for (final entry in slice.styles.entries) entry.key: entry.value.toJson(),
    },
    'components': {
      for (final entry in slice.components.entries)
        entry.key: entry.value.toTypedJson(),
    },
    'behaviors': {
      for (final entry in slice.behaviors.entries)
        entry.key: [for (final b in entry.value) b.toJson()],
    },
    'usages': {
      for (final entry in slice.usages.entries) entry.key: entry.value.toJson(),
    },
  };

  Future<String> _encodeAppearanceMap(Appearance appearance) async {
    final entryCount =
        appearance.styles.length +
        appearance.components.length +
        appearance.behaviors.length;
    if (entryCount >= isolateThresholdEntries) {
      final rawJson = codec.toJson(appearance);
      return _runNormalizeAndEncodePagedMapInIsolate(rawJson);
    }
    return codec.encode(appearance);
  }

  Future<String> _encodePageSlice(
    String pageId,
    EditorPageAppearanceSlice slice,
  ) async {
    final rawJson = _encodePageSliceMap(pageId, slice);
    final entryCount =
        slice.styles.length + slice.components.length + slice.behaviors.length;
    if (entryCount >= isolateThresholdEntries) {
      return _runNormalizeAndEncodePagedMapInIsolate(rawJson);
    }
    return jsonEncode(JsonNumbers.normalizeMap(rawJson));
  }

  @override
  Future<void> save(Appearance appearance) async {
    final currentCatalogIds = <String>{
      for (final page in appearance.pageCatalog.pages) page.id,
    };

    // Toute page nouvellement créée en mémoire (absente du catalogue initial
    // et sans fichier préexistant) est considérée comme chargée pour pouvoir
    // être persistée immédiatement dans son propre fichier.
    for (final pageId in currentCatalogIds) {
      if (_loadedPageIds.contains(pageId)) continue;
      if (!_knownCatalogPageIds.contains(pageId)) {
        final target = pageFileFor(pageId);
        final type = await FileSystemEntity.type(
          target.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) {
          _loadedPageIds.add(pageId);
        }
      }
    }

    final deletedPageIds = _knownCatalogPageIds.difference(currentCatalogIds);

    final partition = EditorPageGraph.partitionForPages(
      appearance: appearance,
      registry: registry,
      loadedPageIds: _loadedPageIds,
      globalProtectedIds: _globalProtectedIds,
    );

    final globalEncoded = await _encodeAppearanceMap(partition.global);
    final globalNeedsWrite = _persistedGlobalEncoded != globalEncoded;

    final dirtyPages = <String, String>{};
    for (final entry in partition.pages.entries) {
      final pageId = entry.key;
      final slice = entry.value;
      final previous = _persistedPages[pageId];
      if (previous == null || previous != slice) {
        dirtyPages[pageId] = await _encodePageSlice(pageId, slice);
      }
    }

    if (!globalNeedsWrite && dirtyPages.isEmpty && deletedPageIds.isEmpty) {
      _knownCatalogPageIds
        ..clear()
        ..addAll(currentCatalogIds);
      return;
    }

    await _serializedIo(() async {
      if (globalNeedsWrite) {
        await _writeAtomicallyTo(file, globalEncoded);
        _persistedGlobalEncoded = globalEncoded;
      }
      for (final entry in dirtyPages.entries) {
        final pageId = entry.key;
        await _writeAtomicallyTo(pageFileFor(pageId), entry.value);
        _persistedPages[pageId] = partition.pages[pageId]!;
      }
      for (final deletedId in deletedPageIds) {
        await _deleteIfPresent(pageFileFor(deletedId));
        _persistedPages.remove(deletedId);
        _loadedPageIds.remove(deletedId);
      }
      _knownCatalogPageIds
        ..clear()
        ..addAll(currentCatalogIds);
    });
  }

  @override
  Future<void> saveEncoded(String encoded) async {
    final Appearance decoded;
    if (encoded.length >= isolateThresholdBytes) {
      final parsed = await _runDecodeAndNormalizePagedMapInIsolate(encoded);
      decoded = codec.fromJson(parsed.raw);
    } else {
      final raw = _decodePagedJsonMapInIsolate(encoded);
      decoded = codec.fromJson(raw);
    }
    await save(decoded);
  }
}
