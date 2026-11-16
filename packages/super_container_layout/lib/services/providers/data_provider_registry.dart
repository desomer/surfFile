/// Registre des providers de données ([DataProviderRegistry]).
///
/// Chaque `JsonRepositoryStore` possède un registre (`store.providers`) qui :
///
/// * référence les providers du code (`CallbackDataProvider`, [register]) et
///   ceux créés dans l'éditeur (`HttpProviderConfig`), persistés dans
///   `<dossier du store>/providers/<id>.json` ;
/// * orchestre une recherche ([DataProviderRegistry.search]) : lecture des
///   paramètres dans le repository de filtre, appel du provider, écriture des
///   lignes dans le repository cible et des indicateurs de chargement et
///   d'erreur ;
/// * expose la même orchestration pour les opérations d'une datasource
///   ([DataProviderRegistry.execute]) : requête complète, donnée quelconque
///   et traitement du résultat par l'appelant ;
/// * relance la recherche quand les paramètres changent (`ProviderAutoSearch`),
///   ou la confie à la datasource qui pilote le provider
///   ([DataProviderCoordinator]).
///
/// Les providers ne sont pas stockés dans l'`Appearance` : seule l'action
/// `searchProvider` y référence leur identifiant.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/json_text_binding.dart';
import '../../models/providers/data_provider.dart';
import '../../models/providers/http_provider_config.dart';
import '../../models/providers/provider_template.dart';
import '../../theme/appearance.dart';
import '../repositories/json_repository_store.dart';
import 'data_provider_http_transport.dart';
import 'http_data_provider.dart';
import 'json_definition_folder.dart';

/// Nombre maximal de providers lus dans le dossier de l'éditeur.
const maxPersistedDataProviders = 200;

const _maxMessageLength = 300;

/// Traitement du résultat d'une exécution ([DataProviderRegistry.execute]),
/// appelé après l'écriture éventuelle de la cible du provider.
///
/// [isCurrent] devient faux si l'exécution a été remplacée ou si le registre
/// a été libéré : aucune écriture ne doit alors avoir lieu. Retourne le
/// nombre de lignes à publier dans l'état, ou `null` pour garder celui
/// calculé par le registre. Une [DataProviderException] est affichée telle
/// quelle ; toute autre erreur est préfixée par « Écriture des résultats
/// impossible ».
typedef DataProviderResultHandler = Future<int?> Function(
  DataProvider provider,
  DataProviderResult result,
  bool Function() isCurrent,
);

/// Coordination des providers par les datasources (`DatasourceRegistry`).
abstract interface class DataProviderCoordinator {
  /// Charge les définitions coordonnées ; attendu avant les recherches
  /// `onStart` et la suppression d'un provider.
  Future<void> ensureLoaded();

  /// Liaisons écrites par une datasource dans le filtre du provider
  /// [providerId] (état de pagination) : retirées de ses paramètres.
  Iterable<JsonTextBinding> excludedBindingsOf(String providerId);

  /// Lance la recherche automatique du provider [providerId] si une
  /// datasource la pilote (retour à la première page) ; retourne vrai alors.
  bool runAutoSearch(String providerId);

  /// Identifiant de la première datasource qui utilise [providerId], ou
  /// `null`.
  String? datasourceUsing(String providerId);
}

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
    _folder = JsonDefinitionFolder<HttpProviderConfig>(
      directory: () => Directory(
        '${store.directory.path}${Platform.pathSeparator}providers',
      ),
      ofOne: 'du provider',
      plural: 'providers',
      maxFiles: maxPersistedDataProviders,
      decode: HttpProviderConfig.fromJson,
      encode: (config) => config.toJson(),
      idOf: (config) => config.id,
      isValidId: isValidDataProviderId,
    );
    store.addListener(_onStoreChanged);
  }

  /// Store dont les repositories sont lus (filtre) et alimentés (cible).
  final JsonRepositoryStore store;

  /// Transport HTTP des providers de l'éditeur ; `null` utilise `dart:io`.
  DataProviderHttpTransport? httpTransport;

  /// Résolveur de `{{env.NOM}}` des providers de l'éditeur ; `null` utilise
  /// [defaultProviderEnv].
  ProviderEnvResolver? env;

  /// Datasources qui pilotent certains providers (installé par le store).
  DataProviderCoordinator? coordinator;

  late final JsonDefinitionFolder<HttpProviderConfig> _folder;
  final _code = <String, DataProvider>{};
  final _configs = <String, HttpProviderConfig>{};
  final _statuses = <String, ValueNotifier<DataProviderStatus>>{};
  final _runs = <String, int>{};
  final _auto = <String, _AutoSearchState>{};
  Future<void>? _loading;
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
      _autoSearch(provider.id);
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
    try {
      await coordinator?.ensureLoaded();
    } on Object {
      // Les problèmes des datasources sont signalés par leur registre.
    }
    if (_disposed) return;
    _started = true;
    for (final provider in _all().toList()) {
      if (provider.autoSearch?.onStart ?? false) _autoSearch(provider.id);
    }
  }

  /// Recherche automatique : confiée à la datasource qui pilote le provider,
  /// sinon recherche simple.
  void _autoSearch(String id) {
    if (_disposed) return;
    if (coordinator?.runAutoSearch(id) ?? false) return;
    unawaited(search(id, reportErrors: false));
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
    await _folder.serial(() async {
      await _folder.write(config);
      _configs[config.id] = config;
    });
    _definitionChanged(config.id);
    notifyListeners();
  }

  /// Supprime le provider de l'éditeur [id].
  ///
  /// Refuse un provider du code, un provider utilisé par une datasource et,
  /// si [appearance] est fournie, un provider encore lancé par un
  /// comportement.
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
    final datasource = coordinator?.datasourceUsing(id);
    if (datasource != null) {
      throw FormatException(
        'Impossible de supprimer « $id » : '
        'ce provider est utilisé par la datasource « $datasource ».',
      );
    }
    await _folder.serial(() async {
      if (!_configs.containsKey(id)) return;
      await _folder.delete(id);
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
    return provider.fetch(await _previewParameters(provider));
  }

  /// Comme [preview], mais retourne la donnée brute (tableau de lignes ou
  /// objet d'une entité) sans exiger de liste.
  ///
  /// Lève une [DataProviderException] au message affichable.
  Future<DataProviderResult> previewResult(HttpProviderConfig config) async {
    final provider = _httpProvider(config);
    try {
      provider.validate();
    } on FormatException catch (error) {
      throw DataProviderException(error.message);
    }
    return provider.execute(
      DataProviderRequest(parameters: await _previewParameters(provider)),
    );
  }

  /// Exécute le provider enregistré [id] sans rien écrire dans les
  /// repositories ; [request] complète les paramètres du filtre (aperçu de la
  /// recherche d'une datasource).
  ///
  /// Lève une [DataProviderException] au message affichable.
  Future<DataProviderResult> previewExecute(
    String id, {
    DataProviderRequest Function(Map<String, Object?> parameters)? request,
    Iterable<JsonTextBinding> excludeParameters = const [],
  }) async {
    final definition = provider(id);
    if (definition == null) {
      throw DataProviderException('Provider « $id » introuvable.');
    }
    final parameters = await _previewParameters(
      definition,
      exclude: excludeParameters,
    );
    return definition.execute(
      request?.call(parameters) ?? DataProviderRequest(parameters: parameters),
    );
  }

  Future<Map<String, Object?>> _previewParameters(
    DataProvider provider, {
    Iterable<JsonTextBinding> exclude = const [],
  }) async {
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
    return _parametersOf(provider, filter, exclude);
  }

  /// Paramètres de [provider] lus dans [filter], sans les liaisons écrites
  /// par une datasource ni [exclude].
  Map<String, Object?> _parametersOf(
    DataProvider provider,
    Object? filter, [
    Iterable<JsonTextBinding> exclude = const [],
  ]) => provider.parametersOf(
    filter,
    exclude: [...?coordinator?.excludedBindingsOf(provider.id), ...exclude],
  );

  /// Lance la recherche du provider [id] et retourne son état final.
  ///
  /// Les saisies en attente sont d'abord enregistrées, puis les paramètres lus
  /// dans le repository de filtre, le provider appelé, les lignes écrites dans
  /// la cible et les indicateurs mis à jour. Une recherche plus récente du même
  /// provider remplace celle en cours, dont le résultat est ignoré. Un
  /// provider sans cible ne peut être lancé que par une datasource.
  ///
  /// Ne lève jamais : un échec devient l'état `error`, l'indicateur d'erreur
  /// du provider et, si [reportErrors] est vrai, une erreur du store.
  Future<DataProviderStatus> search(
    String id, {
    bool reportErrors = true,
  }) async {
    if (_disposed) return DataProviderStatus.idle;
    if (provider(id) case final definition? when definition.target == null) {
      final message =
          'Le provider « $id » n’a pas de tableau de résultats : il ne peut '
          'être lancé que par une datasource.';
      if (reportErrors) store.reportBindingError(message);
      return DataProviderStatus(
        phase: DataProviderPhase.error,
        message: message,
      );
    }
    return _run(
      id,
      call: (definition, parameters) async =>
          DataProviderResult.rows(await definition.fetch(parameters)),
      reportErrors: reportErrors,
    );
  }

  /// Exécute le provider [id] pour une opération de datasource et retourne
  /// son état final.
  ///
  /// Même orchestration que [search] (saisies enregistrées, indicateurs,
  /// exécution plus récente prioritaire), mais [request] construit la requête
  /// complète à partir des paramètres du filtre (sans [excludeParameters]) et
  /// [DataProvider.execute] est appelé. Si [writeTarget] est vrai, la donnée
  /// retournée est écrite dans la cible du provider (liste remplacée, objet
  /// écrit, rien si `null`), puis [onResult] traite le résultat.
  ///
  /// Ne lève jamais : un échec (y compris de [request] ou [onResult]) devient
  /// l'état `error`.
  Future<DataProviderStatus> execute(
    String id, {
    DataProviderRequest Function(Map<String, Object?> parameters)? request,
    DataProviderResultHandler? onResult,
    bool writeTarget = true,
    Iterable<JsonTextBinding> excludeParameters = const [],
    bool reportErrors = true,
  }) {
    if (_disposed) return Future.value(DataProviderStatus.idle);
    return _run(
      id,
      call: (definition, parameters) => definition.execute(
        request?.call(parameters) ??
            DataProviderRequest(parameters: parameters),
      ),
      onResult: onResult,
      writeTarget: writeTarget,
      exclude: excludeParameters,
      reportErrors: reportErrors,
    );
  }

  Future<DataProviderStatus> _run(
    String id, {
    required Future<DataProviderResult> Function(
      DataProvider provider,
      Map<String, Object?> parameters,
    )
    call,
    required bool reportErrors,
    DataProviderResultHandler? onResult,
    bool writeTarget = true,
    Iterable<JsonTextBinding> exclude = const [],
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
    var handling = false;
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
      final parameters = _parametersOf(definition, filter, exclude);
      if (!isCurrent()) return _statusOf(id).value;

      stage = '';
      final result = await call(definition, parameters);
      if (!isCurrent()) return _statusOf(id).value;

      stage = 'Écriture des résultats impossible : ';
      if (writeTarget) await _writeTarget(definition, result);
      if (!isCurrent()) return _statusOf(id).value;
      var rowCount = result.rows?.length;
      if (onResult != null) {
        handling = true;
        rowCount = await onResult(definition, result, isCurrent) ?? rowCount;
        handling = false;
        if (!isCurrent()) return _statusOf(id).value;
      }

      stage = '';
      recordFlagIssue(await _writeLoading(definition, false, isCurrent));
      if (!isCurrent()) return _statusOf(id).value;
      final status = DataProviderStatus(
        phase: DataProviderPhase.success,
        run: run,
        rowCount: rowCount,
      );
      _publish(id, status);
      if (flagIssues.isNotEmpty && reportErrors) {
        store.reportBindingError(flagIssues.join(' ; '));
      }
      return status;
    } on Object catch (error) {
      if (!isCurrent()) return _statusOf(id).value;
      final prefix = handling && error is DataProviderException ? '' : stage;
      final message = '$prefix${_messageOf(error)}';
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

  /// Écrit la donnée de [result] dans la cible de [provider] : une liste
  /// remplace le tableau, un objet ou une valeur remplace l'attribut ; rien
  /// n'est écrit sans cible ni donnée.
  Future<void> _writeTarget(
    DataProvider provider,
    DataProviderResult result,
  ) async {
    final target = provider.target;
    final data = result.data;
    if (target == null || data == null) return;
    final componentId = 'provider:${provider.id}';
    if (data is List) {
      await store.replaceArray(
        target.repositoryId!,
        target.path,
        List<Object?>.of(data),
        componentId: componentId,
      );
    } else {
      await store.replaceValue(
        target.repositoryId!,
        target.path,
        data,
        componentId: componentId,
      );
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

  /// Recalcule la référence des recherches automatiques quand la
  /// coordination des datasources change (liaisons exclues des paramètres).
  void coordinationChanged() {
    if (_disposed) return;
    for (final provider in _all().toList()) {
      if (provider.autoSearch != null) _definitionChanged(provider.id);
    }
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

  String? _signature(DataProvider provider, Object? document) {
    try {
      return jsonEncode(_parametersOf(provider, document));
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
  /// Les écritures du provider lui-même (cible, indicateurs) et de sa
  /// datasource (état de pagination) sont retirées des paramètres : elles ne
  /// relancent pas la recherche.
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
        _autoSearch(id);
      },
    );
  }

  Future<void> _reload() => _folder.serial(() async {
    final (:loaded, :problems) = await _folder.readAll(describe: _messageOf);
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
