/// Magasin réactif multi-documents JSON ([JsonRepositoryStore]).
///
/// Gère l'ajout, la mise à jour, la suppression et l'indexation des entrées
/// [JsonRepositoryEntry] ainsi que leurs [JsonRepositoryBinding] associés.
library;

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/json_text_binding.dart';
import '../../theme/appearance.dart';
import 'calculated_attribute.dart';
import 'json_repository_binding.dart';

/// Entrée immuable décrivant un repository JSON enregistré (identifiant, nom et contenu JSON).
typedef JsonRepositoryEntry = ({String name, String id});

/// Couple associant un chemin d'attribut JSON à sa valeur brute ou résolue.
typedef JsonAttributeValue = ({Object? value, String text});

/// Conflit détecté lors d'une modification conditionnelle d'un repository.
class JsonRepositoryConflictException extends FormatException {
  const JsonRepositoryConflictException(super.message);
}

/// Describes a change made to a registered in-memory repository.
///
/// An empty [path] denotes replacement of the whole document.
class ChangeContext {
  ChangeContext({
    required this.repositoryId,
    required this.path,
    required Object? oldValue,
    required Object? newValue,
    this.componentId,
    this.isReload = false,
  }) : oldValue = _snapshot(oldValue),
       newValue = _snapshot(newValue);

  final String repositoryId;
  final String path;
  final Object? oldValue;
  final Object? newValue;
  final String? componentId;

  /// Indique que le document entier provient d'un rechargement explicite.
  final bool isReload;

  static Object? _snapshot(Object? value) => switch (value) {
    Map() => Map<Object?, Object?>.unmodifiable({
      for (final entry in value.entries) entry.key: _snapshot(entry.value),
    }),
    List() => List<Object?>.unmodifiable(value.map(_snapshot)),
    _ => value,
  };
}

/// Repository JSON fourni par l'application et conservé en mémoire.
class RepositoryImpl {
  factory RepositoryImpl({
    required String id,
    required Map<String, Object?> json,
    ValueChanged<ChangeContext>? onChanged,
  }) {
    if (!RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(id)) {
      throw FormatException('ID de repository invalide. $id');
    }
    final copy = jsonDecode(jsonEncode(json));
    if (copy is! Map<String, dynamic>) {
      throw const FormatException('Le repository doit être un objet JSON.');
    }
    return RepositoryImpl._(
      id,
      Map<String, Object?>.unmodifiable(copy),
      onChanged,
    );
  }

  RepositoryImpl._(this.id, this.json, this.onChanged);

  final String id;
  final Map<String, Object?> json;
  final ValueChanged<ChangeContext>? onChanged;

  final _calculatedAttributes = <String, CalculatedAttributeFunction>{};
  bool _registered = false;

  /// Fonctions de calcul déclarées, indexées par nom (copie en lecture seule).
  Map<String, CalculatedAttributeFunction> get calculatedAttributes =>
      Map.unmodifiable(_calculatedAttributes);

  /// Déclare l'attribut calculé [name], lu par les composants via le chemin
  /// de liaison `@name` (lecture seule).
  ///
  /// [function] reçoit un [CalculatedAttributeContext] : chaque
  /// `ctx.getValue(...)` enregistre une dépendance et le résultat est mis en
  /// cache jusqu'à la modification d'une dépendance. À appeler avant
  /// l'enregistrement du repository dans le store.
  ///
  /// [scope] déclare un calcul par ligne (par exemple `articles[?]`),
  /// accessible avec le chemin `articles[?].@name`.
  ///
  /// Lève une [FormatException] si le nom est invalide, une [ArgumentError]
  /// s'il est déjà déclaré et une [StateError] après enregistrement.
  void addCalculatedAttribute(
    String name,
    CalculatedAttributeFunction function, {
    String? scope,
  }) {
    if (_registered) {
      throw StateError(
        'Attributs calculés figés : déclarez-les avant registerRepository.',
      );
    }
    CalculatedAttributeEngine.validateName(name);
    final key = scope == null
        ? name
        : '${CalculatedAttributeEngine.validateScope(scope)}.@$name';
    if (_calculatedAttributes.containsKey(key)) {
      throw ArgumentError.value(name, 'name', 'Attribut calculé déjà déclaré.');
    }
    _calculatedAttributes[key] = function;
  }
}

class _RegisteredRepositoryPersistence {
  _RegisteredRepositoryPersistence({
    required this.file,
    required this.autoSave,
  });

  final File file;
  final bool autoSave;
  String? savedText;
}

/// One repository is one named JSON file, without an application envelope.
class JsonRepositoryStore extends ChangeNotifier {
  JsonRepositoryStore(this.directory);

  factory JsonRepositoryStore.defaultStore() {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw FileSystemException('Dossier utilisateur introuvable.');
    }
    return JsonRepositoryStore(
      Directory(
        '$home${Platform.pathSeparator}.super_container_layout'
        '${Platform.pathSeparator}repositories',
      ),
    );
  }

  final Directory directory;
  final errors = ValueNotifier<String?>(null);

  final _bindings = <String, JsonRepositoryBinding>{};
  final _activeBindings = <Object, Set<String>>{};
  final _documentCache = <String, Object?>{};
  final _memoryRepositories = <String, Object?>{};
  final _memoryRepositoryCallbacks = <String, ValueChanged<ChangeContext>?>{};
  late final _calculatedEngine = CalculatedAttributeEngine.forStore(
    document: _calculatedDocument,
    onAsyncValue: _changed,
  );
  Map<String, _RegisteredRepositoryPersistence>? _persistentRepositoryState;
  Map<String, _RegisteredRepositoryPersistence> get _persistentRepositories =>
      _persistentRepositoryState ??= {};
  final _loadingDocuments = <String, Future<Object?>>{};
  Map<String, String>? _idToNameCache;
  Future<Map<String, String>>? _loadingCatalog;
  int _activeMutations = 0;

  /// Registers an application-provided repository without writing it to disk.
  void registerRepository(RepositoryImpl repository) {
    if (_memoryRepositories.containsKey(repository.id)) {
      throw ArgumentError.value(
        repository.id,
        'repository.id',
        'Repository déjà enregistré.',
      );
    }
    final document = jsonDecode(jsonEncode(repository.json));
    _memoryRepositories[repository.id] = document;
    _memoryRepositoryCallbacks[repository.id] = repository.onChanged;
    _loadingDocuments.remove(repository.id);
    _calculatedEngine.registerRepository(
      repository.id,
      repository._calculatedAttributes,
    );
    repository._registered = true;
    _documentCache[repository.id] = document;
    _idToNameCache?[repository.id] = repository.id;
    _changed();
  }

  /// Enregistre un repository applicatif et restaure son document s'il existe.
  ///
  /// Le fichier est `registered/<id>.json` dans [directory]. Par défaut,
  /// chaque modification est enregistrée avant d'être publiée. Avec
  /// [autoSave] désactivé, [saveRepository] effectue les écritures explicites.
  /// Retourne `true` si un document existant a été chargé.
  Future<bool> registerPersistentRepository(
    RepositoryImpl repository, {
    bool autoSave = true,
  }) => _exclusive(() async {
    if (_memoryRepositories.containsKey(repository.id)) {
      throw ArgumentError.value(
        repository.id,
        'repository.id',
        'Repository déjà enregistré.',
      );
    }
    final catalog = await _catalog();
    if (catalog.any(
      (entry) =>
          entry.id == repository.id ||
          entry.name.toLowerCase() == repository.id,
    )) {
      throw const FormatException(
        'Un repository utilise déjà cet identifiant ou ce nom.',
      );
    }
    final persistence = _RegisteredRepositoryPersistence(
      file: File(
        '${directory.path}${Platform.pathSeparator}registered'
        '${Platform.pathSeparator}${repository.id}.json',
      ),
      autoSave: autoSave,
    );
    final text = await _readRegisteredText(persistence.file);
    final document = text == null
        ? repository.json
        : _decodeRegisteredDocument(text);
    persistence.savedText = text;
    if (autoSave && text == null) {
      await _writeRegisteredDocument(persistence, document);
    }
    if (_memoryRepositories.containsKey(repository.id)) {
      throw ArgumentError.value(
        repository.id,
        'repository.id',
        'Repository déjà enregistré.',
      );
    }
    _persistentRepositories[repository.id] = persistence;
    registerRepository(
      RepositoryImpl(
        id: repository.id,
        json: document,
        onChanged: repository.onChanged,
      ).._calculatedAttributes.addAll(repository._calculatedAttributes),
    );
    repository._registered = true;
    return text != null;
  });

  /// Enregistre explicitement l'état courant d'un repository persistant.
  ///
  /// Les liaisons en attente sont d'abord vidées. Une modification externe
  /// du fichier depuis le dernier chargement ou enregistrement est refusée.
  Future<void> saveRepository(String repositoryId) async {
    await flushBindings();
    await _exclusive(() async {
      final persistence = _registeredPersistenceOf(repositoryId);
      await _writeRegisteredDocument(
        persistence,
        _memoryRepositories[repositoryId],
      );
    });
  }

  /// Recharge un repository persistant et notifie ses composants liés.
  ///
  /// Les modifications locales non enregistrées sont protégées, sauf si
  /// [discardChanges] vaut `true`. Le callback reçoit un chemin vide lorsque
  /// le document entier a changé.
  Future<void> loadRepository(
    String repositoryId, {
    bool discardChanges = false,
  }) async {
    await flushBindings();
    await _exclusive(() async {
      final persistence = _registeredPersistenceOf(repositoryId);
      final text = await _readRegisteredText(persistence.file);
      if (text == null) {
        throw FileSystemException(
          'Fichier du repository persistant introuvable.',
          persistence.file.path,
        );
      }
      final document = _decodeRegisteredDocument(text);
      final previous = _memoryRepositories[repositoryId];
      final savedText = persistence.savedText;
      if (!discardChanges &&
          (savedText == null ||
              !jsonEquals(previous, _decodeRegisteredDocument(savedText)))) {
        throw const FormatException(
          'Le repository contient des modifications non enregistrées.',
        );
      }
      _memoryRepositories[repositoryId] = document;
      _documentCache[repositoryId] = document;
      _invalidateCalculated(repositoryId, '');
      persistence.savedText = text;
      _changed();
      _notifyMemoryRepositoryChanged(
        repositoryId: repositoryId,
        path: '',
        oldValue: previous,
        newValue: document,
        isReload: true,
      );
    });
  }

  _RegisteredRepositoryPersistence _registeredPersistenceOf(String id) {
    final persistence = _persistentRepositories[id];
    if (persistence == null || !_memoryRepositories.containsKey(id)) {
      throw ArgumentError.value(
        id,
        'repositoryId',
        'Repository non persistant.',
      );
    }
    return persistence;
  }

  /// Indique si un repository applicatif est associé à un fichier persistant.
  bool isPersistentRepository(String repositoryId) =>
      _persistentRepositoryState?.containsKey(repositoryId) ?? false;

  /// Indique si le repository applicatif existe uniquement en mémoire.
  bool isMemoryOnlyRepository(String repositoryId) =>
      _memoryRepositories.containsKey(repositoryId) &&
      !isPersistentRepository(repositoryId);

  Future<String?> _readRegisteredText(File file) async {
    final parentType = await FileSystemEntity.type(
      file.parent.path,
      followLinks: false,
    );
    if (parentType == FileSystemEntityType.notFound) return null;
    if (parentType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Dossier des repositories applicatifs invalide ou lien refusé.',
        file.parent.path,
      );
    }
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Fichier du repository persistant invalide ou lien refusé.',
        file.path,
      );
    }
    return file.readAsString();
  }

  Map<String, Object?> _decodeRegisteredDocument(String text) {
    final document = _decode(text);
    if (document is! Map<String, dynamic>) {
      throw const FormatException(
        'Le repository applicatif doit être un objet JSON.',
      );
    }
    return Map<String, Object?>.from(document);
  }

  Future<void> _writeRegisteredDocument(
    _RegisteredRepositoryPersistence persistence,
    Object? document,
  ) async {
    if (document is! Map<String, Object?>) {
      throw const FormatException(
        'Le repository applicatif doit être un objet JSON.',
      );
    }
    final file = persistence.file;
    if (await _readRegisteredText(file) != persistence.savedText) {
      throw const FormatException(
        'Le repository a été modifié sur le disque. Rechargez-le avant '
        'de réessayer.',
      );
    }
    final text = _encode(document);
    if (text == persistence.savedText) return;
    await file.parent.create(recursive: true);
    if (await _readRegisteredText(file) != persistence.savedText) {
      throw const FormatException(
        'Le repository a été modifié sur le disque. Rechargez-le avant '
        'de réessayer.',
      );
    }
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temporary = File('${file.path}.$suffix.tmp');
    await temporary.create(exclusive: true);
    try {
      await temporary.writeAsString(text, flush: true);
      if (await _readRegisteredText(file) != persistence.savedText) {
        throw const FormatException(
          'Le repository a été modifié sur le disque. Rechargez-le avant '
          'de réessayer.',
        );
      }
      await temporary.rename(file.path);
      persistence.savedText = text;
    } finally {
      if (await FileSystemEntity.type(temporary.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await temporary.delete();
      }
    }
  }

  Future<void> _saveRegisteredAutomatically(String id, Object? document) async {
    final persistence = _persistentRepositories[id];
    if (persistence != null && persistence.autoSave) {
      await _writeRegisteredDocument(persistence, document);
    }
  }

  /// Vide le cache mémoire des documents JSON (ou uniquement celui de
  /// [repositoryId] s'il est précisé) afin de forcer une relecture sur disque.
  void invalidateCache([String? repositoryId]) {
    if (repositoryId == null) {
      _documentCache.clear();
      _loadingDocuments.clear();
      _idToNameCache = null;
      _calculatedEngine.invalidateAll();
    } else {
      _documentCache.remove(repositoryId);
      _invalidateCalculated(repositoryId, '');
    }
  }

  void _invalidateCalculated(String repositoryId, String path) {
    _loadingDocuments.remove(repositoryId);
    _calculatedEngine.invalidateForChange(path, repositoryId: repositoryId);
  }

  /// Runtime selections and bound components of [repositoryId]'s arrays.
  JsonRepositoryBinding bindingOf(String repositoryId) => _bindings.putIfAbsent(
    repositoryId,
    () => JsonRepositoryBinding(repositoryId),
  );

  /// Enregistre les identifiants de repositories utilisés par un bind actif [owner].
  void registerBindings(Object owner, Iterable<String?> repositoryIds) {
    final ids = {
      for (final id in repositoryIds)
        if (id != null && id.isNotEmpty) id,
    };
    if (ids.isEmpty) {
      _activeBindings.remove(owner);
    } else {
      _activeBindings[owner] = ids;
    }
  }

  /// Désenregistre les liaisons actives associées à [owner].
  void unregisterBindings(Object owner) => _activeBindings.remove(owner);

  /// Indique si [repositoryId] est actuellement utilisé par un bind actif du store.
  bool isRepositoryBound(String repositoryId) =>
      (_bindings[repositoryId]?.isBound ?? false) ||
      _activeBindings.values.any((ids) => ids.contains(repositoryId));

  /// Indique si le repository [name] est utilisé par un bind actif du store
  /// ou par une liaison configurée dans [appearance].
  Future<bool> isRepositoryInUse(String name, {Appearance? appearance}) =>
      _exclusive(() => _isRepositoryInUse(name, appearance: appearance));

  Future<bool> _isRepositoryInUse(String name, {Appearance? appearance}) async {
    final idFile = _idFile(name);
    if (await FileSystemEntity.type(idFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    final id = (await idFile.readAsString()).trim();
    if (id.isEmpty) return false;
    return isRepositoryBound(id) || (appearance?.usesRepository(id) ?? false);
  }

  Future<void> _pending = Future.value();
  final Object _flushers = <Future<void> Function()>{};
  Set<Future<void> Function()>? _migratedFlushers;
  Map<Future<void> Function(), String? Function()>? _flusherErrors;
  bool _disposed = false;

  Set<Future<void> Function()> get _activeFlushers {
    final flushers = _flushers;
    if (flushers is Set<Future<void> Function()>) return flushers;
    // Une session rechargée à chaud peut encore contenir l'ancienne map.
    if (flushers is Map<Future<void> Function(), String? Function()?>) {
      final migrated = _migratedFlushers;
      if (migrated != null) return migrated;
      final errors = _flusherErrors ??= {};
      for (final entry in flushers.entries) {
        final pendingError = entry.value;
        if (pendingError != null) errors[entry.key] = pendingError;
      }
      return _migratedFlushers = flushers.keys.toSet();
    }
    throw StateError('Collection de liaisons en attente invalide.');
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _activeMutations++;
    _pending = _pending.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _activeMutations--;
      }
    });
    return result.future;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _notifyMemoryRepositoryChanged({
    required String repositoryId,
    required String path,
    required Object? oldValue,
    required Object? newValue,
    String? componentId,
    bool isReload = false,
  }) {
    if (jsonEquals(oldValue, newValue)) return;
    _memoryRepositoryCallbacks[repositoryId]?.call(
      ChangeContext(
        repositoryId: repositoryId,
        path: path,
        oldValue: oldValue,
        newValue: newValue,
        componentId: componentId,
        isReload: isReload,
      ),
    );
  }

  /// Enregistre une liaison et, si fourni, son éventuel échec non résolu.
  void addFlusher(
    Future<void> Function() flush, {
    String? Function()? pendingError,
  }) {
    _activeFlushers.add(flush);
    if (pendingError == null) {
      _flusherErrors?.remove(flush);
    } else {
      (_flusherErrors ??= {})[flush] = pendingError;
    }
  }

  /// Désenregistre une liaison de la synchronisation des saisies en attente.
  void removeFlusher(Future<void> Function() flush) {
    _activeFlushers.remove(flush);
    _flusherErrors?.remove(flush);
  }

  /// Enregistre les saisies liées ou signale celles qui restent en échec.
  Future<void> flushBindings() async {
    final flushers = {
      for (final flusher in _activeFlushers) flusher: _flusherErrors?[flusher],
    };
    await Future.wait([for (final flusher in flushers.keys) flusher()]);
    for (final pendingError in flushers.values) {
      final error = pendingError?.call();
      if (error != null) throw FormatException(error);
    }
  }

  void reportBindingError(String message) {
    if (!_disposed) errors.value = message;
  }

  @override
  void dispose() {
    _disposed = true;
    _calculatedEngine.dispose();
    errors.dispose();
    for (final binding in _bindings.values) {
      binding.dispose();
    }
    super.dispose();
  }

  static String validateName(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name.endsWith('.') ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
        RegExp(
          r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
          caseSensitive: false,
        ).hasMatch(name)) {
      throw const FormatException('Nom de repository invalide.');
    }
    return name;
  }

  File _file(String name) => File(
    '${directory.path}${Platform.pathSeparator}${validateName(name)}.json',
  );

  File _idFile(String name) => File('${_file(name).path}.id');

  /// Assigned once, outside the editable JSON, and preserved when renamed.
  /// Existing repositories receive their ID on first access.
  Future<String> idOf(String name) => _exclusive(() => _idOf(name));

  Future<String> _idOf(String name) async {
    if (_memoryRepositories.containsKey(name)) return name;
    final jsonFile = _file(name);
    if (await FileSystemEntity.type(jsonFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Fichier JSON introuvable ou lien refusé.',
        jsonFile.path,
      );
    }
    final file = _idFile(name);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await file.create(exclusive: true);
      await file.writeAsString(id, flush: true);
      return id;
    }
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Fichier d’identifiant invalide.', file.path);
    }
    final id = await file.readAsString();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const FormatException(
        'Identifiant technique corrompu : restaurez le fichier .json.id '
        'depuis une sauvegarde.',
      );
    }
    return id;
  }

  Future<List<String>> list() async {
    await directory.create(recursive: true);
    final names = <String>{..._memoryRepositories.keys};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final filename = entity.uri.pathSegments.last;
      names.add(filename.substring(0, filename.length - 5));
    }
    final result = names.toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  Future<List<JsonRepositoryEntry>> catalog() => _exclusive(_catalog);

  Future<List<JsonRepositoryEntry>> _catalog() async {
    final names = await list();
    final entries = <JsonRepositoryEntry>[];
    final ids = <String>{};
    final idToName = <String, String>{};
    for (final name in names) {
      final id = await _idOf(name);
      if (!ids.add(id)) {
        _idToNameCache = null;
        _documentCache.clear();
        throw const FormatException('ID technique de repository dupliqué.');
      }
      entries.add((name: name, id: id));
      idToName[id] = name;
    }
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    _idToNameCache = idToName;
    return entries;
  }

  Future<Map<String, String>> _ensureCatalogMap() {
    final cached = _idToNameCache;
    if (cached != null) return Future.value(cached);
    final inFlight = _loadingCatalog;
    if (inFlight != null) return inFlight;
    final future = () async {
      try {
        await _catalog();
        return _idToNameCache!;
      } finally {
        _loadingCatalog = null;
      }
    }();
    _loadingCatalog = future;
    return future;
  }

  Future<String> _resolveNameOf(String id) async {
    final cached = _idToNameCache?[id];
    if (cached != null) return cached;
    final map = await _ensureCatalogMap();
    final name = map[id];
    if (name == null) {
      throw const FormatException('Repository lié introuvable.');
    }
    return name;
  }

  Future<String> _nameOf(String id) async {
    if (_memoryRepositories.containsKey(id)) return id;
    final matches = (await _catalog()).where((entry) => entry.id == id);
    if (matches.isEmpty) {
      throw const FormatException('Repository lié introuvable.');
    }
    return matches.single.name;
  }

  Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      // Parser diagnostics can contain repository data, including passwords.
      throw const FormatException('Le repository contient un JSON invalide.');
    }
  }

  static String _encode(Object? document) =>
      '${const JsonEncoder.withIndent('  ').convert(document)}\n';

  Future<Object?> _getDocument(String repoId) async {
    if (_activeMutations > 0) {
      await _pending;
      await Future<void>.delayed(Duration.zero);
    }
    if (_documentCache.containsKey(repoId)) {
      return _documentCache[repoId];
    }
    if (_memoryRepositories.containsKey(repoId)) {
      return _documentCache[repoId] = _memoryRepositories[repoId];
    }
    final inFlight = _loadingDocuments[repoId];
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<Object?> future;
    future = () async {
      try {
        final name = await _resolveNameOf(repoId);
        final root = _decode(await read(name));
        if (!identical(_loadingDocuments[repoId], future)) {
          return await _getDocument(repoId);
        }
        _documentCache[repoId] = root;
        return root;
      } finally {
        if (identical(_loadingDocuments[repoId], future)) {
          _loadingDocuments.remove(repoId);
        }
      }
    }();
    _loadingDocuments[repoId] = future;
    return future;
  }

  /// Précharge en mémoire le catalogue et les documents JSON des repositories
  /// existants afin de permettre un binding synchrone dès le premier frame.
  Future<void> preload() async {
    try {
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return;
      }
      final map = await _ensureCatalogMap();
      await Future.wait([
        for (final id in map.keys)
          _getDocument(id).then<void>((_) {}, onError: (_) {}),
      ]);
    } catch (_) {
      // Les erreurs de lecture ou de format sont gérées par les composants liés.
    }
  }

  static String _formatAttributeText(Object? value) {
    if (value is List) {
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .join(',');
    }
    return value?.toString() ?? '';
  }

  FutureOr<Object?> _calculatedDocument(String repositoryId) {
    if (_memoryRepositories.containsKey(repositoryId)) {
      return _memoryRepositories[repositoryId];
    }
    if (_documentCache.containsKey(repositoryId)) {
      return _documentCache[repositoryId];
    }
    return _getDocument(repositoryId);
  }

  /// Définitions disponibles pour les suggestions, sans exécuter les calculs.
  List<CalculatedAttributeDescriptor> calculatedAttributeCatalog(
    String repositoryId,
  ) => _calculatedEngine.catalog(repositoryId);

  /// Vérifie une définition, y compris les modèles de ligne et sous-chemins.
  bool hasCalculatedAttribute(String repositoryId, String path) =>
      JsonTextBinding.isCalculatedPath(path) &&
      _calculatedEngine.contains(path, repositoryId: repositoryId);

  /// Relance volontairement un calcul et ses lecteurs après une erreur.
  Future<JsonAttributeValue> refreshCalculatedAttribute(
    JsonTextBinding binding,
  ) async {
    binding.validateResolved();
    _calculatedEngine.invalidateCalculation(
      binding.repositoryId!,
      binding.path,
    );
    _changed();
    return readAttribute(binding);
  }

  /// Lit de manière synchrone la valeur de [binding] depuis le cache mémoire
  /// du repository lorsque le document JSON a déjà été chargé.
  ///
  /// Retourne `null` si le repository n'est pas encore en cache ou si le
  /// chemin ne peut pas être résolu sans erreur.
  JsonAttributeValue? peekAttribute(
    JsonTextBinding binding, {
    bool allowStringList = false,
  }) {
    final repoId = binding.repositoryId;
    if (repoId == null) return null;
    try {
      binding.validateResolved();
      if (JsonTextBinding.isCalculatedPath(binding.path)) {
        final result = _calculatedEngine.peek(
          binding.path,
          repositoryId: repoId,
        );
        if (result == null) return null;
        return (value: result.value, text: _formatAttributeText(result.value));
      }
      if (!_documentCache.containsKey(repoId)) return null;
      final root = _documentCache[repoId];
      final value = JsonAttributePath(binding.path)
          .read(root, allowStringList: allowStringList);
      return (value: value, text: _formatAttributeText(value));
    } on FormatException {
      return null;
    }
  }

  /// Lit de manière synchrone le tableau à [path] depuis le cache mémoire
  /// du repository lorsque le document JSON a déjà été chargé.
  ///
  /// Retourne `null` si le repository n'est pas encore en cache ou si le
  /// chemin ne peut pas être résolu sans erreur.
  List<Object?>? peekArray(String repositoryId, String path) {
    try {
      final binding = JsonTextBinding(repositoryId: repositoryId, path: path)
        ..validateResolved();
      if (JsonTextBinding.isCalculatedPath(binding.path)) {
        final result = _calculatedEngine.peek(
          binding.path,
          repositoryId: repositoryId,
        );
        if (result == null) return null;
        return List<Object?>.unmodifiable(_array(result.value));
      }
      if (!_documentCache.containsKey(repositoryId)) return null;
      final root = _documentCache[repositoryId];
      return List<Object?>.unmodifiable(
        _array(JsonAttributePath(binding.path).readNode(root)),
      );
    } on FormatException {
      return null;
    }
  }

  /// Lit de manière synchrone la racine d'un arbre JSON à [path] depuis le
  /// cache mémoire lorsque le document JSON a déjà été chargé.
  ///
  /// Retourne `null` si le repository n'est pas encore en cache ou si le
  /// chemin ne peut pas être résolu sans erreur.
  ({List<Object?> nodes, bool singleRootObject})? peekTreeNodes(
    String repositoryId,
    String path,
  ) {
    try {
      final binding = JsonTextBinding(repositoryId: repositoryId, path: path)
        ..validateResolved();
      Object? node;
      if (JsonTextBinding.isCalculatedPath(binding.path)) {
        final result = _calculatedEngine.peek(
          binding.path,
          repositoryId: repositoryId,
        );
        if (result == null) return null;
        node = result.value;
      } else {
        if (!_documentCache.containsKey(repositoryId)) return null;
        node = JsonAttributePath(binding.path)
            .readNode(_documentCache[repositoryId]);
      }
      if (node == null) {
        return (nodes: const <Object?>[], singleRootObject: false);
      }
      if (node is List) {
        return (
          nodes: List<Object?>.unmodifiable(node),
          singleRootObject: false,
        );
      }
      if (node is Map<String, dynamic>) {
        return (
          nodes: List<Object?>.unmodifiable([node]),
          singleRootObject: true,
        );
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<JsonAttributeValue> readAttribute(
    JsonTextBinding binding, {
    bool allowStringList = false,
  }) async {
    binding.validateResolved();
    final repoId = binding.repositoryId!;
    if (JsonTextBinding.isCalculatedPath(binding.path)) {
      final value = await _calculatedEngine.read(
        binding.path,
        repositoryId: repoId,
      );
      return (value: value, text: _formatAttributeText(value));
    }
    final root = await _getDocument(repoId);
    final value = JsonAttributePath(binding.path)
        .read(root, allowStringList: allowStringList);
    return (value: value, text: _formatAttributeText(value));
  }

  Future<JsonAttributeValue> writeAttribute(
    JsonTextBinding binding,
    String text, {
    required Object? expectedValue,
    bool asBool = false,
    bool asStringList = false,
    String? componentId,
  }) => _exclusive(() async {
    binding.validateResolved();
    final repoId = binding.repositoryId!;
    if (JsonTextBinding.isCalculatedPath(binding.path)) {
      throw FormatException(
        'L’attribut calculé « ${binding.path} » est en lecture seule.',
      );
    }
    if (_memoryRepositories.containsKey(repoId)) {
      final root = _memoryRepositories[repoId];
      final path = JsonAttributePath(binding.path);
      final current = path.read(root, allowStringList: asStringList);
      if (!jsonEquals(current, expectedValue)) {
        throw const FormatException(
          'L’attribut lié a été modifié. Rechargez la liaison avant de réessayer.',
        );
      }
      final updated = path.write(
        root,
        text,
        expectedValue,
        asBool: asBool,
        asStringList: asStringList,
      );
      await _saveRegisteredAutomatically(repoId, updated);
      final value = path.read(updated, allowStringList: asStringList);
      _memoryRepositories[repoId] = updated;
      _documentCache[repoId] = updated;
      if (!jsonEquals(current, value)) {
        _invalidateCalculated(repoId, binding.path);
      }
      _changed();
      _notifyMemoryRepositoryChanged(
        repositoryId: repoId,
        path: binding.path,
        oldValue: expectedValue,
        newValue: value,
        componentId: componentId,
      );
      return (value: value, text: _formatAttributeText(value));
    }
    final name = await _nameOf(repoId);
    final original = await read(name);
    final root = _decode(original);
    final path = JsonAttributePath(binding.path);
    final current = path.read(root, allowStringList: asStringList);
    if (!jsonEquals(current, expectedValue)) {
      throw const FormatException(
        'L’attribut lié a été modifié. Rechargez la liaison avant de réessayer.',
      );
    }
    final updated = path.write(
      root,
      text,
      expectedValue,
      asBool: asBool,
      asStringList: asStringList,
    );
    await _save(
      name,
      _encode(updated),
      expectedText: original,
      changedPath: binding.path,
    );
    _documentCache[repoId] = updated;
    final value = path.read(updated, allowStringList: asStringList);
    return (value: value, text: _formatAttributeText(value));
  });

  /// Elements of the array at [path]; a missing attribute is an empty list.
  Future<List<Object?>> readArray(String repositoryId, String path) async {
    final binding = JsonTextBinding(repositoryId: repositoryId, path: path)
      ..validateResolved();
    if (JsonTextBinding.isCalculatedPath(binding.path)) {
      final value = await _calculatedEngine.read(
        binding.path,
        repositoryId: repositoryId,
      );
      return List<Object?>.unmodifiable(_array(value));
    }
    final root = await _getDocument(repositoryId);
    return List<Object?>.unmodifiable(
      _array(JsonAttributePath(binding.path).readNode(root)),
    );
  }

  static List<Object?> _array(Object? node) {
    if (node == null) return const [];
    if (node is! List) {
      throw const FormatException(
        'Le chemin de la liste doit désigner un tableau JSON.',
      );
    }
    return node;
  }

  /// Reads a JSON tree root at [path] (either a JSON array of node objects or
  /// a single root JSON object).
  Future<({List<Object?> nodes, bool singleRootObject})> readTreeNodes(
    String repositoryId,
    String path,
  ) async {
    final binding = JsonTextBinding(repositoryId: repositoryId, path: path)
      ..validateResolved();
    final node = JsonTextBinding.isCalculatedPath(binding.path)
        ? await _calculatedEngine.read(binding.path, repositoryId: repositoryId)
        : JsonAttributePath(binding.path)
              .readNode(await _getDocument(repositoryId));
    if (node == null) {
      return (nodes: const <Object?>[], singleRootObject: false);
    }
    if (node is List) {
      return (nodes: List<Object?>.unmodifiable(node), singleRootObject: false);
    }
    if (node is Map<String, dynamic>) {
      return (
        nodes: List<Object?>.unmodifiable([node]),
        singleRootObject: true,
      );
    }
    throw const FormatException(
      'Le chemin du TreeView doit désigner un tableau ou un objet JSON.',
    );
  }

  /// Appends a blank copy of the last element, or `{}` to an empty array.
  Future<int> appendArrayItem(
    String repositoryId,
    String path, {
    required int expectedLength,
    String? componentId,
  }) => _updateArray(repositoryId, path, (items) {
    if (items.length != expectedLength) _arrayConflict();
    return [...items, items.isEmpty ? <String, dynamic>{} : blank(items.last)];
  }, componentId: componentId);

  Future<int> removeArrayItem(
    String repositoryId,
    String path,
    int index, {
    required Object? expectedItem,
    String? componentId,
  }) => _updateArray(repositoryId, path, (items) {
    if (index < 0 ||
        index >= items.length ||
        !jsonEquals(items[index], expectedItem)) {
      _arrayConflict();
    }
    return [...items]..removeAt(index);
  }, componentId: componentId);

  static Never _arrayConflict() => throw const FormatException(
    'La liste a été modifiée. Rechargez-la avant de réessayer.',
  );

  /// Remplace un tableau entier (créé s'il est absent) par [items].
  ///
  /// Les chemins et valeurs de [expectedValues] doivent encore correspondre
  /// au document au moment de l'écriture, sinon un
  /// [JsonRepositoryConflictException] est levé.
  Future<int> replaceArray(
    String repositoryId,
    String path,
    List<Object?> items, {
    String? componentId,
    Map<String, Object?>? expectedValues,
  }) {
    final copy = jsonDecode(jsonEncode(items)) as List<Object?>;
    final expectations = expectedValues == null
        ? null
        : Map<String, Object?>.from(
            jsonDecode(jsonEncode(expectedValues)) as Map<String, dynamic>,
          );
    return _updateArray(
      repositoryId,
      path,
      (_) => copy,
      componentId: componentId,
      expectedValues: expectations,
    );
  }

  static void _checkExpectedValues(
    Object? root,
    Map<String, Object?>? expectedValues,
  ) {
    if (expectedValues == null) return;
    for (final entry in expectedValues.entries) {
      final path = JsonAttributePath(entry.key)..requireResolved();
      if (!jsonEquals(path.readNode(root), entry.value)) {
        throw const JsonRepositoryConflictException(
          'Le repository a été modifié. Rechargez les données avant de réessayer.',
        );
      }
    }
  }

  Future<int> _updateArray(
    String repositoryId,
    String path,
    List<Object?> Function(List<Object?>) change, {
    String? componentId,
    Map<String, Object?>? expectedValues,
  }) => _exclusive(() async {
    final binding = JsonTextBinding(repositoryId: repositoryId, path: path)
      ..validateResolved();
    if (JsonTextBinding.isCalculatedPath(binding.path)) {
      throw FormatException(
        'L’attribut calculé « ${binding.path} » est en lecture seule.',
      );
    }
    if (_memoryRepositories.containsKey(repositoryId)) {
      final root = _memoryRepositories[repositoryId];
      _checkExpectedValues(root, expectedValues);
      final attribute = JsonAttributePath(binding.path);
      final previous = _array(attribute.readNode(root));
      final items = change(previous);
      final updated = attribute.replaceNode(root, items);
      await _saveRegisteredAutomatically(repositoryId, updated);
      _memoryRepositories[repositoryId] = updated;
      _documentCache[repositoryId] = updated;
      if (!jsonEquals(previous, items)) {
        _invalidateCalculated(repositoryId, binding.path);
      }
      _changed();
      _notifyMemoryRepositoryChanged(
        repositoryId: repositoryId,
        path: binding.path,
        oldValue: previous,
        newValue: items,
        componentId: componentId,
      );
      return items.length;
    }
    final name = await _nameOf(repositoryId);
    final original = await read(name);
    final root = _decode(original);
    _checkExpectedValues(root, expectedValues);
    final attribute = JsonAttributePath(binding.path);
    final items = change(_array(attribute.readNode(root)));
    final updated = attribute.replaceNode(root, items);
    await _save(
      name,
      _encode(updated),
      expectedText: original,
      changedPath: binding.path,
    );
    return items.length;
  });

  /// Same structure with empty values: "", 0, false, [] and null.
  static Object? blank(Object? value) => switch (value) {
    String() => '',
    num() => 0,
    bool() => false,
    List() => <Object?>[],
    Map() => <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: blank(entry.value),
    },
    _ => null,
  };

  static bool jsonEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.entries.every(
            (entry) =>
                b.containsKey(entry.key) &&
                jsonEquals(entry.value, b[entry.key]),
          );
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!jsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  Future<void> _checkAvailable(String name) async {
    final normalized = validateName(name).toLowerCase();
    if ((await list()).any((entry) => entry.toLowerCase() == normalized) ||
        await FileSystemEntity.type(_file(name).path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        await FileSystemEntity.type(_idFile(name).path, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw const FormatException('Un repository porte déjà ce nom.');
    }
  }

  Future<String> read(String name) async {
    if (_memoryRepositories.containsKey(name)) {
      return _encode(_memoryRepositories[name]);
    }
    final file = _file(name);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Fichier JSON introuvable ou lien refusé.',
        file.path,
      );
    }
    return file.readAsString();
  }

  Future<void> create(String name) => _exclusive(() async {
    await _checkAvailable(name);
    await _file(name).create(exclusive: true);
    await _file(name).writeAsString('{}\n', flush: true);
    final id = await _idOf(name);
    _idToNameCache = null;
    _documentCache.clear();
    _invalidateCalculated(id, '');
    _changed();
  });

  /// Enregistre un document entier après contrôle de sa version précédente.
  ///
  /// Pour un repository applicatif persistant, les liaisons sont vidées et
  /// le fichier est enregistré même lorsque la sauvegarde automatique est
  /// désactivée. La version précédente est comparée comme un document JSON,
  /// indépendamment de sa mise en forme.
  Future<void> save(
    String name,
    String text, {
    required String expectedText,
  }) async {
    if (isPersistentRepository(name)) await flushBindings();
    await _exclusive(() => _save(name, text, expectedText: expectedText));
  }

  Future<void> _save(
    String name,
    String text, {
    required String expectedText,
    String changedPath = '',
  }) async {
    final decoded = jsonDecode(text);
    if (_memoryRepositories.containsKey(name)) {
      final persistence = _persistentRepositories[name];
      final matches = persistence == null
          ? await read(name) == expectedText
          : jsonEquals(_memoryRepositories[name], _decode(expectedText));
      if (!matches) {
        throw const FormatException(
          'Le repository a été modifié. Copiez vos modifications puis rechargez-le.',
        );
      }
      if (persistence != null && decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Le repository applicatif doit être un objet JSON.',
        );
      }
      final previous = _memoryRepositories[name];
      if (persistence != null) {
        await _writeRegisteredDocument(persistence, decoded);
      }
      _memoryRepositories[name] = decoded;
      _documentCache[name] = decoded;
      if (!jsonEquals(previous, decoded)) {
        _invalidateCalculated(name, changedPath);
      }
      _changed();
      _notifyMemoryRepositoryChanged(
        repositoryId: name,
        path: '',
        oldValue: previous,
        newValue: decoded,
      );
      return;
    }
    if (await read(name) != expectedText) {
      throw const FormatException(
        'Le fichier a été modifié sur le disque. '
        'Copiez vos modifications puis rechargez le repository.',
      );
    }
    final id = await _idOf(name);
    await _file(name).writeAsString(text, flush: true);
    _documentCache[id] = decoded;
    _idToNameCache?[id] = validateName(name);
    if (changedPath.isEmpty || !jsonEquals(_decode(expectedText), decoded)) {
      _invalidateCalculated(id, changedPath);
    }
    _changed();
  }

  Future<void> rename(String name, String newName) => _exclusive(() async {
    if (_memoryRepositories.containsKey(name)) {
      throw const FormatException(
        'Le nom d’un repository fourni par l’application ne peut pas être modifié.',
      );
    }
    final validated = validateName(newName);
    if (name == validated) return;
    await _checkAvailable(validated);
    await _idOf(name);
    final metadata = await _idFile(name).rename(_idFile(validated).path);
    try {
      await _file(name).rename(_file(validated).path);
    } on FileSystemException {
      await metadata.rename(_idFile(name).path);
      rethrow;
    }
    _idToNameCache = null;
    _changed();
  });

  Future<void> delete(
    String name, {
    Appearance? appearance,
  }) => _exclusive(() async {
    final validated = validateName(name);
    if (_memoryRepositories.containsKey(validated)) {
      if (isRepositoryBound(validated) ||
          (appearance?.usesRepository(validated) ?? false)) {
        throw FormatException(
          'Impossible de supprimer « $validated » : '
          'ce repository est encore utilisé par un bind de l’application.',
        );
      }
      final persistence = _persistentRepositories[validated];
      if (persistence != null) {
        final text = await _readRegisteredText(persistence.file);
        if (text != persistence.savedText) {
          throw const FormatException(
            'Le repository a été modifié sur le disque. Rechargez-le avant '
            'de le supprimer.',
          );
        }
        if (text != null) await persistence.file.delete();
        _persistentRepositories.remove(validated);
        final binding = _bindings[validated];
        if (binding != null) {
          for (final array in binding.arrays) {
            array.clear();
          }
        }
      }
      _memoryRepositories.remove(validated);
      _memoryRepositoryCallbacks.remove(validated);
      _documentCache.remove(validated);
      _idToNameCache?.remove(validated);
      _loadingDocuments.remove(validated);
      _calculatedEngine.unregisterRepository(validated);
      _changed();
      return;
    }
    final file = _file(validated);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Fichier JSON introuvable ou lien refusé.',
        file.path,
      );
    }
    final idFile = _idFile(validated);
    final idType = await FileSystemEntity.type(idFile.path, followLinks: false);
    if (idType != FileSystemEntityType.notFound &&
        idType != FileSystemEntityType.file) {
      throw FileSystemException('Fichier d’identifiant invalide.', idFile.path);
    }
    String? id;
    if (idType == FileSystemEntityType.file) {
      id = (await idFile.readAsString()).trim();
    }
    if (id != null &&
        id.isNotEmpty &&
        (isRepositoryBound(id) || (appearance?.usesRepository(id) ?? false))) {
      throw FormatException(
        'Impossible de supprimer « $validated » : '
        'ce repository est encore utilisé par un bind de l’application.',
      );
    }
    await file.delete();
    if (idType == FileSystemEntityType.file) {
      await idFile.delete();
    }
    if (id != null) {
      _documentCache.remove(id);
      _invalidateCalculated(id, '');
    }
    _idToNameCache = null;
    final binding = id == null ? null : _bindings[id];
    if (binding != null) {
      for (final array in binding.arrays) {
        array.clear();
      }
    }
    _changed();
  });
}
