/// Registre des providers de données ([DataProviderRegistry]).
///
/// Chaque `JsonRepositoryStore` possède un registre (`store.providers`) qui :
///
/// * référence les providers du code (`CallbackDataProvider`, [register]) et
///   ceux créés dans l'éditeur (`HttpProviderConfig`), persistés dans
///   `<dossier du store>/providers/<id>.json` ;
/// * orchestre une recherche ([search]) : lecture des paramètres dans le
///   repository de filtre, appel du provider, écriture des lignes dans le
///   repository cible et des indicateurs de chargement et d'erreur ;
/// * relance la recherche quand les paramètres changent (`ProviderAutoSearch`).
///
/// Les providers ne sont pas stockés dans l'`Appearance` : seule l'action
/// `searchProvider` y référence leur identifiant.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/json_text_binding.dart';
import '../../models/providers/data_provider.dart';
import '../../models/providers/http_provider_config.dart';
import '../../models/providers/provider_template.dart';
import '../../theme/appearance.dart';
import '../repositories/json_repository_store.dart';
import 'data_provider_http_transport.dart';
import 'http_data_provider.dart';

/// Nombre maximal de providers lus dans le dossier de l'éditeur.
const maxPersistedDataProviders = 200;

const _maxFileBytes = 256 * 1024;
const _maxMessageLength = 300;

/// Message affichable d'une erreur ; les détails inattendus sont tronqués.
String _messageOf(Object error) {
  final text = switch (error) {
    DataProviderException(:final message) => message,
    FormatException(:final message) => message,
    FileSystemException(:final message) => message,
    _ => error.toString(),
  };
  return text.length > _maxMessageLength
      ? '${text.substring(0, _maxMessageLength)}…'
      : text;
}

/// Suivi des paramètres d'un provider à recherche automatique.
class _AutoSearchState {
  Object? root;
  String? signature;
  Timer? timer;
  bool priming = false;
}

/// Registre, orchestrateur et persistance des providers d'un store.
class DataProviderRegistry extends ChangeNotifier {
  /// Crée le registre de [store] ; il observe ses modifications pour la
  /// recherche automatique. Préférez `store.providers`.
  DataProviderRegistry(this.store) {
    store.addListener(_onStoreChanged);
  }

  /// Store dont les repositories sont lus (filtre) et alimentés (cible).
  final JsonRepositoryStore store;

  /// Transport HTTP des providers de l'éditeur ; `null` utilise `dart:io`.
  DataProviderHttpTransport? httpTransport;

  /// Résolveur de `{{env.NOM}}` des providers de l'éditeur ; `null` utilise
  /// [defaultProviderEnv].
  ProviderEnvResolver? env;

  final _code = <String, DataProvider>{};
  final _configs = <String, HttpProviderConfig>{};
  final _statuses = <String, ValueNotifier<DataProviderStatus>>{};
  final _runs = <String, int>{};
  final _auto = <String, _AutoSearchState>{};
  Future<void>? _loading;
  Future<void> _fileQueue = Future.value();
  bool _started = false;
  bool _disposed = false;

  /// Tous les providers, triés par libellé.
  List<DataProvider> get providers {
    final result = _all().toList()
      ..sort((a, b) {
        final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
        return byLabel != 0 ? byLabel : a.id.compareTo(b.id);
      });
    return List<DataProvider>.unmodifiable(result);
  }

  Iterable<DataProvider> _all() sync* {
    yield* _code.values;
    for (final config in _configs.values) {
      if (!_code.containsKey(config.id)) yield _httpProvider(config);
    }
  }

  HttpDataProvider _httpProvider(HttpProviderConfig config) =>
      HttpDataProvider(config, transport: httpTransport, env: env);

  /// Provider d'identifiant [id], ou `null`.
  ///
  /// Un provider du code l'emporte sur un fichier de même identifiant.
  DataProvider? provider(String id) {
    final code = _code[id];
    if (code != null) return code;
    final config = _configs[id];
    return config == null ? null : _httpProvider(config);
  }

  /// Vrai si [id] est un provider de l'éditeur (modifiable et supprimable).
  bool isEditable(String id) =>
      !_code.containsKey(id) && _configs.containsKey(id);

  /// Configuration du provider de l'éditeur [id], ou `null`.
  HttpProviderConfig? configOf(String id) =>
      isEditable(id) ? _configs[id] : null;

  /// Vrai si un provider lit ou écrit le repository [repositoryId].
  bool usesRepository(String repositoryId) =>
      providerUsing(repositoryId) != null;

  /// Premier provider (par libellé) qui lit ou écrit [repositoryId].
  ///
  /// Les providers de l'éditeur ne sont connus qu'après [ensureLoaded].
  DataProvider? providerUsing(String repositoryId) {
    for (final candidate in providers) {
      if (candidate.usesRepository(repositoryId)) return candidate;
    }
    return null;
  }

  /// État observable de la dernière recherche du provider [id].
  ValueListenable<DataProviderStatus> statusOf(String id) => _statusOf(id);

  ValueNotifier<DataProviderStatus> _statusOf(String id) =>
      _statuses.putIfAbsent(
        id,
        () => ValueNotifier<DataProviderStatus>(DataProviderStatus.idle),
      );

  void _publish(String id, DataProviderStatus status) {
    if (!_disposed) _statusOf(id).value = status;
  }

  /// Enregistre un provider du code hôte.
  ///
  /// Lève une [FormatException] si sa définition est invalide et une
  /// [ArgumentError] si l'identifiant est déjà enregistré. Une recherche
  /// `onStart` est lancée immédiatement si le chargement initial est terminé.
  void register(DataProvider provider) {
    provider.validate();
    if (_code.containsKey(provider.id)) {
      throw ArgumentError.value(
        provider.id,
        'provider',
        'Un provider portant cet identifiant est déjà enregistré.',
      );
    }
    _code[provider.id] = provider;
    _definitionChanged(provider.id);
    notifyListeners();
    if (_started && (provider.autoSearch?.onStart ?? false)) {
      unawaited(search(provider.id, reportErrors: false));
    }
  }

  /// Retire un provider du code ; retourne `false` s'il n'existait pas.
  bool unregister(String id) {
    if (_code.remove(id) == null) return false;
    _definitionChanged(id);
    notifyListeners();
    return true;
  }

  /// Charge une seule fois les providers de l'éditeur, remet à `false`
  /// l'indicateur de chargement resté actif (application fermée pendant une
  /// recherche), puis lance les recherches `onStart`.
  Future<void> ensureLoaded() => _loading ??= _loadFirst();

  /// Relit le dossier des providers de l'éditeur (modification externe).
  Future<void> reload() async {
    await ensureLoaded();
    await _reload();
  }

  Future<void> _loadFirst() async {
    await _reload();
    await _resetStaleLoading();
    if (_disposed) return;
    _started = true;
    for (final provider in _all().toList()) {
      if (provider.autoSearch?.onStart ?? false) {
        unawaited(search(provider.id, reportErrors: false));
      }
    }
  }

  Future<void> _resetStaleLoading() async {
    for (final provider in _all().toList()) {
      final binding = provider.loading;
      if (_disposed) return;
      if (binding == null || _statusOf(provider.id).value.isLoading) continue;
      try {
        final current = await store.readAttribute(binding);
        if (current.value == true) {
          await store.writeAttribute(
            binding,
            'false',
            expectedValue: true,
            asBool: true,
            componentId: 'provider:${provider.id}',
          );
        }
      } on Object {
        // Repository pas encore disponible : rien à réinitialiser.
      }
    }
  }

  /// Enregistre (crée ou remplace) un provider de l'éditeur dans
  /// `<dossier du store>/providers/<id>.json`.
  ///
  /// Lève une [FormatException] si la configuration est invalide ou si
  /// l'identifiant est celui d'un provider du code.
  Future<void> save(HttpProviderConfig config) async {
    config.validate();
    if (_code.containsKey(config.id)) {
      throw FormatException(
        'Le provider « ${config.id} » est défini par le code de '
        'l’application : il ne peut pas être modifié.',
      );
    }
    await ensureLoaded();
    await _serial(() async {
      await _write(config);
      _configs[config.id] = config;
    });
    _definitionChanged(config.id);
    notifyListeners();
  }

  /// Supprime le provider de l'éditeur [id].
  ///
  /// Refuse un provider du code et, si [appearance] est fournie, un provider
  /// encore lancé par un comportement.
  Future<void> delete(String id, {Appearance? appearance}) async {
    if (_code.containsKey(id)) {
      throw FormatException(
        'Le provider « $id » est défini par le code de l’application : '
        'il ne peut pas être supprimé.',
      );
    }
    if (appearance?.usesProvider(id) ?? false) {
      throw FormatException(
        'Impossible de supprimer « $id » : '
        'ce provider est encore utilisé par un comportement.',
      );
    }
    await ensureLoaded();
    await _serial(() async {
      if (!_configs.containsKey(id)) return;
      final file = _fileOf(id);
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        await file.delete();
      } else if (type != FileSystemEntityType.notFound) {
        throw FileSystemException(
          'Fichier du provider invalide ou lien refusé.',
          file.path,
        );
      }
      _configs.remove(id);
    });
    _definitionChanged(id);
    notifyListeners();
  }

  /// Exécute [config] sans rien écrire dans les repositories et retourne les
  /// lignes obtenues (bouton « Tester » de l'éditeur).
  ///
  /// Lève une [DataProviderException] au message affichable.
  Future<List<Object?>> preview(HttpProviderConfig config) async {
    final provider = _httpProvider(config);
    try {
      provider.validate();
    } on FormatException catch (error) {
      throw DataProviderException(error.message);
    }
    final filterId = provider.filterRepositoryId;
    Object? filter;
    if (filterId != null) {
      try {
        await store.flushBindings();
        filter = await store.readDocument(filterId);
      } on Object catch (error) {
        throw DataProviderException(
          'Lecture du filtre impossible : ${_messageOf(error)}',
        );
      }
    }
    return provider.fetch(provider.parametersOf(filter));
  }

  /// Lance la recherche du provider [id] et retourne son état final.
  ///
  /// Les saisies en attente sont d'abord enregistrées, puis les paramètres lus
  /// dans le repository de filtre, le provider appelé, les lignes écrites dans
  /// la cible et les indicateurs mis à jour. Une recherche plus récente du même
  /// provider remplace celle en cours, dont le résultat est ignoré.
  ///
  /// Ne lève jamais : un échec devient l'état `error`, l'indicateur d'erreur
  /// du provider et, si [reportErrors] est vrai, une erreur du store.
  Future<DataProviderStatus> search(
    String id, {
    bool reportErrors = true,
  }) async {
    if (_disposed) return DataProviderStatus.idle;
    final definition = provider(id);
    if (definition == null) {
      final message = 'Provider « $id » introuvable.';
      if (reportErrors) store.reportBindingError(message);
      return DataProviderStatus(
        phase: DataProviderPhase.error,
        message: message,
      );
    }
    final run = _runs[id] = (_runs[id] ?? 0) + 1;
    bool isCurrent() => !_disposed && _runs[id] == run;
    final state = _auto[id];
    state?.timer?.cancel();
    state?.timer = null;
    _publish(
      id,
      DataProviderStatus(phase: DataProviderPhase.loading, run: run),
    );

    var stage = '';
    final flagIssues = <String>[];
    void recordFlagIssue(String? issue) {
      if (issue != null && !flagIssues.contains(issue)) flagIssues.add(issue);
    }

    try {
      recordFlagIssue(await _writeLoading(definition, true, isCurrent));
      recordFlagIssue(await _writeError(definition, '', isCurrent));
      if (!isCurrent()) return _statusOf(id).value;

      stage = 'Lecture du filtre impossible : ';
      await store.flushBindings();
      final filterId = definition.filterRepositoryId;
      final filter = filterId == null
          ? null
          : await store.readDocument(filterId);
      final parameters = definition.parametersOf(filter);
      if (!isCurrent()) return _statusOf(id).value;

      stage = '';
      final rows = await definition.fetch(parameters);
      if (!isCurrent()) return _statusOf(id).value;

      stage = 'Écriture des résultats impossible : ';
      await store.replaceArray(
        definition.target.repositoryId!,
        definition.target.path,
        rows,
        componentId: 'provider:$id',
      );
      if (!isCurrent()) return _statusOf(id).value;

      stage = '';
      recordFlagIssue(await _writeLoading(definition, false, isCurrent));
      if (!isCurrent()) return _statusOf(id).value;
      final status = DataProviderStatus(
        phase: DataProviderPhase.success,
        run: run,
        rowCount: rows.length,
      );
      _publish(id, status);
      if (flagIssues.isNotEmpty && reportErrors) {
        store.reportBindingError(flagIssues.join(' ; '));
      }
      return status;
    } on Object catch (error) {
      if (!isCurrent()) return _statusOf(id).value;
      final message = '$stage${_messageOf(error)}';
      recordFlagIssue(await _writeLoading(definition, false, isCurrent));
      recordFlagIssue(await _writeError(definition, message, isCurrent));
      if (!isCurrent()) return _statusOf(id).value;
      final surfacedMessage = [message, ...flagIssues].join(' ; ');
      final status = DataProviderStatus(
        phase: DataProviderPhase.error,
        run: run,
        message: surfacedMessage,
      );
      _publish(id, status);
      if (reportErrors) store.reportBindingError(surfacedMessage);
      return status;
    }
  }

  Future<String?> _writeLoading(
    DataProvider provider,
    bool value,
    bool Function() isCurrent,
  ) async {
    final binding = provider.loading;
    if (binding == null) return null;
    final issue = await _writeFlag(
      provider.id,
      binding,
      '$value',
      asBool: true,
      isCurrent: isCurrent,
    );
    return issue == null
        ? null
        : 'Écriture de l’indicateur de chargement impossible : $issue';
  }

  Future<String?> _writeError(
    DataProvider provider,
    String message,
    bool Function() isCurrent,
  ) async {
    final binding = provider.error;
    if (binding == null) return null;
    final issue = await _writeFlag(
      provider.id,
      binding,
      message,
      asBool: false,
      isCurrent: isCurrent,
    );
    return issue == null
        ? null
        : 'Écriture de l’indicateur d’erreur impossible : $issue';
  }

  /// Écrit un indicateur sans jamais lever ; retourne le message d'échec.
  ///
  /// Une écriture inutile (valeur déjà présente) est ignorée, et une
  /// modification concurrente est retentée une fois.
  Future<String?> _writeFlag(
    String providerId,
    JsonTextBinding binding,
    String text, {
    required bool asBool,
    required bool Function() isCurrent,
  }) async {
    String? failure;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final current = await store.readAttribute(binding);
        if (!isCurrent()) return null;
        final unchanged = asBool
            ? current.value == (text == 'true')
            : (current.value ?? '') == text;
        if (unchanged) return null;
        await store.writeAttribute(
          binding,
          text,
          expectedValue: current.value,
          asBool: asBool,
          componentId: 'provider:$providerId',
        );
        return null;
      } on Object catch (error) {
        failure = _messageOf(error);
      }
    }
    return failure;
  }

  void _definitionChanged(String id) {
    _auto.remove(id)?.timer?.cancel();
    final definition = provider(id);
    if (definition == null || definition.autoSearch == null) return;
    final state = _auto[id] = _AutoSearchState();
    unawaited(_prime(definition, state));
  }

  /// Mémorise les paramètres actuels comme référence de la recherche
  /// automatique, sans lancer de recherche.
  Future<void> _prime(DataProvider provider, _AutoSearchState state) async {
    final filterId = provider.filterRepositoryId;
    if (filterId == null || state.priming) return;
    state.priming = true;
    try {
      final document = await store.readDocument(filterId);
      if (!_disposed) state.signature ??= _signature(provider, document);
    } on Object {
      // Filtre pas encore disponible : nouvel essai à la prochaine
      // modification du store.
    } finally {
      state.priming = false;
    }
  }

  static String? _signature(DataProvider provider, Object? document) {
    try {
      return jsonEncode(provider.parametersOf(document));
    } on Object {
      return null;
    }
  }

  void _onStoreChanged() {
    if (_disposed) return;
    for (final provider in _all()) {
      final filterId = provider.filterRepositoryId;
      if (filterId == null || provider.autoSearch == null) continue;
      final state = _auto.putIfAbsent(provider.id, _AutoSearchState.new);
      final cached = store.peekDocument(filterId);
      if (cached != null) {
        _observe(provider, state, cached.document);
      } else {
        unawaited(_prime(provider, state));
      }
    }
  }

  /// Arme la recherche différée quand les paramètres ont changé.
  ///
  /// Les écritures du provider lui-même (cible, indicateurs) sont retirées des
  /// paramètres : elles ne relancent pas la recherche.
  void _observe(DataProvider provider, _AutoSearchState state, Object? root) {
    if (identical(root, state.root)) return;
    state.root = root;
    final signature = _signature(provider, root);
    if (signature == null) return;
    final previous = state.signature;
    state.signature = signature;
    if (previous == null || previous == signature) return;
    state.timer?.cancel();
    final id = provider.id;
    state.timer = Timer(
      Duration(milliseconds: provider.autoSearch!.debounceMs),
      () {
        state.timer = null;
        if (!_disposed) unawaited(search(id, reportErrors: false));
      },
    );
  }

  Directory get _folder =>
      Directory('${store.directory.path}${Platform.pathSeparator}providers');

  File _fileOf(String id) =>
      File('${_folder.path}${Platform.pathSeparator}$id.json');

  /// Exécute [action] après les opérations de fichier précédentes.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _fileQueue = _fileQueue.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> _reload() => _serial(() async {
    final loaded = <String, HttpProviderConfig>{};
    final problems = <String>[];
    final folder = _folder;
    try {
      if (await FileSystemEntity.type(folder.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        await for (final entity in folder.list(followLinks: false)) {
          if (entity is! File || !entity.path.endsWith('.json')) continue;
          final name = entity.uri.pathSegments.last;
          final id = name.substring(0, name.length - '.json'.length);
          if (loaded.length >= maxPersistedDataProviders) {
            problems.add(
              'au plus $maxPersistedDataProviders providers sont chargés',
            );
            break;
          }
          try {
            loaded[id] = await _read(entity, id);
          } on Object catch (error) {
            problems.add('« $id » : ${_messageOf(error)}');
          }
        }
      }
    } on FileSystemException catch (error) {
      problems.add('dossier illisible : ${error.message}');
    }
    if (_disposed) return;
    final previous = Map<String, HttpProviderConfig>.of(_configs);
    _configs
      ..clear()
      ..addAll(loaded);
    for (final id in {...previous.keys, ...loaded.keys}) {
      if (previous[id] != loaded[id]) _definitionChanged(id);
    }
    notifyListeners();
    if (problems.isNotEmpty) {
      store.reportBindingError('Providers ignorés — ${problems.join(' ; ')}');
    }
  });

  Future<HttpProviderConfig> _read(File file, String id) async {
    if (!isValidDataProviderId(id)) {
      throw const FormatException(
        'le nom du fichier doit utiliser a-z, 0-9 et _ (32 caractères au plus).',
      );
    }
    if (await file.length() > _maxFileBytes) {
      throw const FormatException('fichier trop volumineux.');
    }
    final Object? json;
    try {
      json = jsonDecode(await file.readAsString());
    } on FormatException {
      throw const FormatException('JSON invalide.');
    }
    final config = HttpProviderConfig.fromJson(json);
    if (config.id != id) {
      throw const FormatException('l’identifiant doit être celui du fichier.');
    }
    return config;
  }

  Future<void> _write(HttpProviderConfig config) async {
    final folder = _folder;
    final folderType = await FileSystemEntity.type(
      folder.path,
      followLinks: false,
    );
    if (folderType == FileSystemEntityType.notFound) {
      await folder.create(recursive: true);
    } else if (folderType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Dossier des providers invalide ou lien refusé.',
        folder.path,
      );
    }
    final file = _fileOf(config.id);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Fichier du provider invalide ou lien refusé.',
        file.path,
      );
    }
    final text =
        '${const JsonEncoder.withIndent('  ').convert(config.toJson())}\n';
    final random = Random.secure();
    final suffix = List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temporary = File('${file.path}.$suffix.tmp');
    await temporary.create(exclusive: true);
    try {
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await FileSystemEntity.type(temporary.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await temporary.delete();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    store.removeListener(_onStoreChanged);
    for (final state in _auto.values) {
      state.timer?.cancel();
    }
    _auto.clear();
    for (final status in _statuses.values) {
      status.dispose();
    }
    _statuses.clear();
    super.dispose();
  }
}
