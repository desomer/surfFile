/// Registre et orchestrateur des datasources ([DatasourceRegistry]).
///
/// Chaque `JsonRepositoryStore` possède un registre (`store.datasources`)
/// qui :
///
/// * référence les datasources du code ([DatasourceRegistry.register]) et
///   celles créées dans l'éditeur, persistées dans
///   `<dossier du store>/datasources/<id>.json` ;
/// * exécute les commandes des comportements ([DatasourceRegistry.run]) en
///   appelant le provider de l'opération par `DataProviderRegistry.execute`
///   (indicateurs, erreurs et exécutions obsolètes gérés par le provider) ;
/// * ajoute le tri, la pagination et le contexte `{{ds.*}}` (entité
///   courante, clé) aux requêtes ;
/// * met à jour localement, **par clé**, la liste (cible du provider Search)
///   et le détail (cible du provider Read) après Create / Update / Delete,
///   sans relancer la recherche : `needsRefresh` signale alors dans l'état
///   que l'ordre, les pages ou le filtrage du serveur peuvent différer ;
/// * relit l'entité par Read quand Create / Update ne la retourne pas, ou
///   signale « opération réussie, synchronisation locale incomplète » ;
/// * pilote la recherche automatique de ses providers Search
///   (`DataProviderCoordinator`).
///
/// Concurrence : une mutation est refusée tant qu'une autre est en cours
/// sur la même datasource, une mutation invalide les recherches lancées
/// avant elle (relancées ensuite), une lecture obsolète n'écrase pas un
/// détail plus récent, et aucune écriture n'a lieu après
/// [DatasourceRegistry.dispose] ou le remplacement d'une définition.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/datasources/datasource_config.dart';
import '../../models/datasources/datasource_state.dart';
import '../../models/json_text_binding.dart';
import '../../models/providers/data_provider.dart';
import '../../theme/appearance.dart';
import '../providers/data_provider_registry.dart';
import '../providers/json_definition_folder.dart';
import '../repositories/json_list_scope.dart';
import '../repositories/json_repository_store.dart';

/// Nombre maximal de datasources lues dans le dossier de l'éditeur.
const maxPersistedDatasources = 200;

const _maxMessageLength = 300;

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

/// Écriture annulée : la commande est devenue obsolète.
class _Stale implements Exception {
  const _Stale();
}

/// Copie JSON normalisée (`Map<String, dynamic>`) ; lève une
/// [DataProviderException] si [value] n'est pas du JSON.
Object? _normalized(Object? value) {
  try {
    return jsonDecode(jsonEncode(value));
  } on Object {
    throw const DataProviderException('La réponse n’est pas du JSON.');
  }
}

/// Chemin modèle canonique d'un tableau (clé des sélections).
String _canonical(String path) => JsonAttributePath(path).toString();

Object? _readAt(Object? root, String path) {
  try {
    return JsonAttributePath(path).readNode(root);
  } on FormatException {
    return null;
  }
}

/// Demande de page d'une recherche.
class _SearchRequest {
  const _SearchRequest({
    required this.pageIndex,
    required this.firstIndex,
    required this.cursor,
    required this.sort,
    required this.append,
  });

  /// Indice de la page demandée (0 pour la première).
  final int pageIndex;

  /// Indice de la première page affichée après la recherche (« Charger
  /// plus » garde les pages précédentes).
  final int firstIndex;

  final String? cursor;
  final DatasourceSortOrder? sort;
  final bool append;
}

/// Exécution d'une datasource : position, compteurs et mutation en cours.
class _Runtime {
  final status = ValueNotifier<DatasourceStatus>(DatasourceStatus.idle);

  /// Incrémenté quand la définition change : les écritures en cours sont
  /// abandonnées.
  int epoch = 0;

  /// Numéro de la dernière commande.
  int run = 0;

  /// Position de la dernière page écrite.
  int pageIndex = 0;
  int firstIndex = 0;
  List<String?> cursors = const [null];
  DatasourceSortOrder? sort;
  bool sortChosen = false;
  DatasourcePageState page = DatasourcePageState.initial;

  /// Dernière recherche lancée (relancée après une mutation concurrente).
  _SearchRequest? lastSearch;
  int searchesInFlight = 0;

  /// Nombre de mutations lancées : une recherche lancée avant n'écrit pas.
  int mutationsStarted = 0;
  bool searchNeedsRerun = false;

  /// Incrémenté à chaque écriture du détail par une mutation.
  int detailVersion = 0;

  /// Mutation en cours : une autre est refusée jusqu'à sa fin.
  DatasourceCommand? mutation;

  void reset() {
    epoch++;
    pageIndex = 0;
    firstIndex = 0;
    cursors = const [null];
    sort = null;
    sortChosen = false;
    page = DatasourcePageState.initial;
    lastSearch = null;
    searchNeedsRerun = false;
  }
}

/// Entité courante d'une commande Read / Update / Delete.
typedef _Entity = ({Object key, Map<String, Object?> entity});

/// Registre, persistance et orchestrateur des datasources d'un store.
class DatasourceRegistry extends ChangeNotifier
    implements DataProviderCoordinator {
  /// Crée le registre de [store] ; il coordonne [providers] (recherche
  /// automatique, paramètres exclus). Préférez `store.datasources`.
  DatasourceRegistry(this.store, this.providers) {
    _folder = JsonDefinitionFolder<DatasourceConfig>(
      directory: () => Directory(
        '${store.directory.path}${Platform.pathSeparator}datasources',
      ),
      ofOne: 'de la datasource',
      plural: 'datasources',
      maxFiles: maxPersistedDatasources,
      decode: DatasourceConfig.fromJson,
      encode: (config) => config.toJson(),
      idOf: (config) => config.id,
      isValidId: isValidDatasourceId,
    );
    providers.coordinator = this;
  }

  /// Store dont les repositories sont lus et mis à jour.
  final JsonRepositoryStore store;

  /// Providers appelés par les opérations.
  final DataProviderRegistry providers;

  late final JsonDefinitionFolder<DatasourceConfig> _folder;
  final _code = <String, DatasourceConfig>{};
  final _configs = <String, DatasourceConfig>{};
  final _runtimes = <String, _Runtime>{};
  Future<void>? _loading;
  bool _disposed = false;

  /// Toutes les datasources, triées par libellé.
  List<DatasourceConfig> get datasources {
    final result = _all().toList()
      ..sort((a, b) {
        final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
        return byLabel != 0 ? byLabel : a.id.compareTo(b.id);
      });
    return List<DatasourceConfig>.unmodifiable(result);
  }

  Iterable<DatasourceConfig> _all() sync* {
    yield* _code.values;
    for (final config in _configs.values) {
      if (!_code.containsKey(config.id)) yield config;
    }
  }

  /// Datasource [id], ou `null` ; une datasource du code l'emporte sur un
  /// fichier de même identifiant.
  DatasourceConfig? datasource(String id) => _code[id] ?? _configs[id];

  /// Vrai si [id] est une datasource de l'éditeur (modifiable et
  /// supprimable).
  bool isEditable(String id) =>
      !_code.containsKey(id) && _configs.containsKey(id);

  /// Configuration de la datasource de l'éditeur [id], ou `null`.
  DatasourceConfig? configOf(String id) => isEditable(id) ? _configs[id] : null;

  /// Datasources (par libellé) qui référencent le provider [providerId].
  List<DatasourceConfig> datasourcesUsingProvider(String providerId) => [
    for (final config in datasources)
      if (config.usesProvider(providerId)) config,
  ];

  @override
  String? datasourceUsing(String providerId) =>
      datasourcesUsingProvider(providerId).firstOrNull?.id;

  /// Vrai si l'état d'une datasource est écrit dans [repositoryId].
  bool usesRepository(String repositoryId) =>
      datasourceUsingRepository(repositoryId) != null;

  /// Première datasource (par libellé) dont l'état est écrit dans
  /// [repositoryId].
  DatasourceConfig? datasourceUsingRepository(String repositoryId) {
    for (final config in datasources) {
      if (config.usesRepository(repositoryId)) return config;
    }
    return null;
  }

  @override
  Iterable<JsonTextBinding> excludedBindingsOf(String providerId) => [
    for (final config in _all())
      if (config.search
          case DatasourceSearchConfig(provider: final id, state: final state?)
          when id == providerId)
        state,
  ];

  @override
  bool runAutoSearch(String providerId) {
    if (_disposed) return false;
    final owners = [
      for (final config in _all())
        if (config.search?.provider == providerId) config.id,
    ];
    for (final id in owners) {
      unawaited(run(id, DatasourceCommand.search, reportErrors: false));
    }
    return owners.isNotEmpty;
  }

  /// Problèmes de [config] avec les providers actuels (provider introuvable,
  /// recherche sans tableau de résultats) ; vide si elle est exécutable.
  List<String> problemsOf(DatasourceConfig config) => [
    for (final operation in config.operations) ?_problemOf(config, operation),
  ];

  String? _problemOf(DatasourceConfig config, DatasourceOperation operation) {
    final id = config.providerOf(operation);
    if (id == null) return null;
    final provider = providers.provider(id);
    if (provider == null) {
      return '${operation.title} : provider « $id » introuvable.';
    }
    if (operation == DatasourceOperation.search && provider.target == null) {
      return 'Search : le provider « $id » n’a pas de tableau de résultats.';
    }
    return null;
  }

  /// État observable de la dernière commande de la datasource [id].
  ValueListenable<DatasourceStatus> stateOf(String id) => _runtimeOf(id).status;

  _Runtime _runtimeOf(String id) => _runtimes.putIfAbsent(id, _Runtime.new);

  void _publish(_Runtime runtime, DatasourceStatus status) {
    if (!_disposed) runtime.status.value = status;
  }

  /// Enregistre une datasource du code hôte (non modifiable dans l'éditeur).
  ///
  /// Lève une [FormatException] si sa définition est invalide et une
  /// [ArgumentError] si l'identifiant est déjà enregistré.
  void register(DatasourceConfig config) {
    config.validate();
    if (_code.containsKey(config.id)) {
      throw ArgumentError.value(
        config.id,
        'datasource',
        'Une datasource portant cet identifiant est déjà enregistrée.',
      );
    }
    _code[config.id] = config;
    _definitionsChanged({config.id});
  }

  /// Retire une datasource du code ; retourne `false` si elle n'existait pas.
  bool unregister(String id) {
    if (_code.remove(id) == null) return false;
    _definitionsChanged({id});
    return true;
  }

  @override
  Future<void> ensureLoaded() => _loading ??= _reload();

  /// Relit le dossier des datasources de l'éditeur (modification externe).
  Future<void> reload() async {
    await ensureLoaded();
    await _reload();
  }

  Future<void> _reload() => _folder.serial(() async {
    final (:loaded, :problems) = await _folder.readAll(describe: _messageOf);
    if (_disposed) return;
    final previous = Map<String, DatasourceConfig>.of(_configs);
    _configs
      ..clear()
      ..addAll(loaded);
    _definitionsChanged({
      for (final id in {...previous.keys, ...loaded.keys})
        if (previous[id] != loaded[id]) id,
    });
    if (problems.isNotEmpty) {
      store.reportBindingError(
        'Datasources ignorées — ${problems.join(' ; ')}',
      );
    }
  });

  /// Enregistre (crée ou remplace) une datasource de l'éditeur dans
  /// `<dossier du store>/datasources/<id>.json`.
  ///
  /// Lève une [FormatException] si la configuration est invalide ou si
  /// l'identifiant est celui d'une datasource du code.
  Future<void> save(DatasourceConfig config) async {
    config.validate();
    if (_code.containsKey(config.id)) {
      throw FormatException(
        'La datasource « ${config.id} » est définie par le code de '
        'l’application : elle ne peut pas être modifiée.',
      );
    }
    await ensureLoaded();
    await _folder.serial(() async {
      await _folder.write(config);
      _configs[config.id] = config;
    });
    _definitionsChanged({config.id});
  }

  /// Supprime la datasource de l'éditeur [id].
  ///
  /// Refuse une datasource du code et, si [appearance] est fournie, une
  /// datasource encore utilisée par un comportement.
  Future<void> delete(String id, {Appearance? appearance}) async {
    if (_code.containsKey(id)) {
      throw FormatException(
        'La datasource « $id » est définie par le code de l’application : '
        'elle ne peut pas être supprimée.',
      );
    }
    if (appearance?.usesDatasource(id) ?? false) {
      throw FormatException(
        'Impossible de supprimer « $id » : '
        'cette datasource est encore utilisée par un comportement.',
      );
    }
    await ensureLoaded();
    await _folder.serial(() async {
      if (!_configs.containsKey(id)) return;
      await _folder.delete(id);
      _configs.remove(id);
    });
    _definitionsChanged({id});
  }

  void _definitionsChanged(Set<String> ids) {
    if (_disposed) return;
    for (final id in ids) {
      _runtimes[id]?.reset();
    }
    providers.coordinationChanged();
    notifyListeners();
  }

  /// Exécute [command] sur la datasource [id] et retourne son état final.
  ///
  /// [scope] est la ligne du composant déclencheur : elle désigne l'entité
  /// courante de Read / Update / Delete si sa liste affiche exactement le
  /// tableau de la recherche ; sinon la ligne sélectionnée de ce tableau,
  /// puis le contenu de la cible Read sont utilisés. [field] et [direction]
  /// paramètrent [DatasourceCommand.sort].
  ///
  /// Ne lève jamais : un échec devient l'état `error` et, si [reportErrors]
  /// est vrai, une erreur du store.
  Future<DatasourceStatus> run(
    String id,
    DatasourceCommand command, {
    JsonListScope? scope,
    String? field,
    DatasourceSortDirection? direction,
    bool reportErrors = true,
  }) async {
    if (_disposed) return DatasourceStatus.idle;
    final config = datasource(id);
    final runtime = _runtimeOf(id);
    if (config == null) {
      return _fail(
        runtime,
        command,
        'Datasource « $id » introuvable.',
        reportErrors,
      );
    }
    if (!config.supports(command)) {
      return _fail(
        runtime,
        command,
        'La datasource « $id » ne propose pas « ${command.label} ».',
        reportErrors,
      );
    }
    final problem = _problemOf(config, command.operation);
    if (problem != null) {
      return _fail(runtime, command, problem, reportErrors);
    }
    switch (command.operation) {
      case DatasourceOperation.search:
        final request = _searchRequestFor(
          config,
          runtime,
          command,
          field,
          direction,
        );
        if (request == null) {
          if (command == DatasourceCommand.sort) {
            return _fail(
              runtime,
              command,
              'Tri impossible sur « ${field ?? ''} » : champ non triable.',
              reportErrors,
            );
          }
          return runtime.status.value;
        }
        return _search(config, runtime, command, request, reportErrors);
      case DatasourceOperation.create:
        return _mutate(
          runtime,
          command,
          reportErrors,
          () => _create(config, runtime, reportErrors),
        );
      case DatasourceOperation.read:
        final entity = await _currentEntity(config, scope);
        if (entity == null) {
          return _fail(runtime, command, _noEntity, reportErrors);
        }
        return _read(config, runtime, entity, reportErrors);
      case DatasourceOperation.update:
      case DatasourceOperation.delete:
        // Verrou pris avant de lire l'entité : un double clic ne peut pas
        // viser une entité déjà supprimée.
        return _mutate(runtime, command, reportErrors, () async {
          final entity = await _currentEntity(config, scope);
          if (entity == null) {
            return _fail(runtime, command, _noEntity, reportErrors);
          }
          return command == DatasourceCommand.update
              ? _update(config, runtime, entity, reportErrors)
              : _delete(config, runtime, entity, reportErrors);
        });
    }
  }

  static const _noEntity =
      'Aucune entité courante : sélectionnez une ligne qui porte une clé.';

  DatasourceStatus _fail(
    _Runtime runtime,
    DatasourceCommand command,
    String message,
    bool reportErrors,
  ) {
    final status = runtime.status.value.copyWith(
      phase: DataProviderPhase.error,
      command: command,
      run: ++runtime.run,
      message: message,
    );
    _publish(runtime, status);
    if (reportErrors && !_disposed) store.reportBindingError(message);
    return status;
  }

  int _start(_Runtime runtime, DatasourceCommand command) {
    final run = ++runtime.run;
    _publish(
      runtime,
      runtime.status.value.copyWith(
        phase: DataProviderPhase.loading,
        command: command,
        run: run,
        clearMessage: true,
      ),
    );
    return run;
  }

  /// État final d'une commande d'après l'état de son provider ; publié
  /// seulement si aucune commande plus récente n'a été lancée.
  DatasourceStatus _finish(
    _Runtime runtime,
    int run,
    DatasourceCommand command,
    DataProviderStatus provider, {
    String? notice,
  }) {
    if (_disposed) return DatasourceStatus.idle;
    final status = switch (provider.phase) {
      DataProviderPhase.success => DatasourceStatus(
        phase: DataProviderPhase.success,
        command: command,
        run: run,
        message: notice,
        page: runtime.page,
      ),
      DataProviderPhase.error => DatasourceStatus(
        phase: DataProviderPhase.error,
        command: command,
        run: run,
        message: provider.message,
        page: runtime.page,
      ),
      // Exécution remplacée par une plus récente du même provider.
      _ => runtime.status.value,
    };
    if (runtime.run == run) {
      _publish(runtime, status);
    } else if (runtime.status.value.page != runtime.page) {
      _publish(runtime, runtime.status.value.copyWith(page: runtime.page));
    }
    return status;
  }

  /// Exécute la mutation [action] si aucune autre n'est en cours sur la
  /// datasource ; sinon la refuse (double clic, Create répété) avec un état
  /// `error` retourné sans remplacer l'état publié de la mutation en cours.
  Future<DatasourceStatus> _mutate(
    _Runtime runtime,
    DatasourceCommand command,
    bool reportErrors,
    Future<DatasourceStatus> Function() action,
  ) async {
    final running = runtime.mutation;
    if (running != null) {
      final message =
          '« ${command.label} » refusé : « ${running.label} » est déjà en '
          'cours sur cette datasource.';
      if (reportErrors && !_disposed) store.reportBindingError(message);
      return runtime.status.value.copyWith(
        phase: DataProviderPhase.error,
        command: command,
        message: message,
      );
    }
    runtime.mutation = command;
    try {
      return await action();
    } on Object catch (error) {
      return _fail(runtime, command, _messageOf(error), reportErrors);
    } finally {
      runtime.mutation = null;
      _rerunInvalidatedSearch(runtime);
    }
  }

  void _rerunInvalidatedSearch(_Runtime runtime) {
    final request = runtime.lastSearch;
    if (_disposed ||
        request == null ||
        (runtime.searchesInFlight == 0 && !runtime.searchNeedsRerun)) {
      return;
    }
    runtime.searchNeedsRerun = false;
    final id = _runtimes.entries
        .where((entry) => identical(entry.value, runtime))
        .firstOrNull
        ?.key;
    final config = id == null ? null : datasource(id);
    if (config == null) return;
    unawaited(
      _search(config, runtime, DatasourceCommand.refresh, request, false),
    );
  }

  // ---------------------------------------------------------------- Search

  DatasourceSortOrder? _currentSort(DatasourceConfig config, _Runtime runtime) {
    final sort = config.search?.sort;
    if (sort == null) return null;
    final current = runtime.sortChosen ? runtime.sort : sort.defaultOrder;
    return current != null && sort.allows(current.field) ? current : null;
  }

  /// Page demandée par [command], ou `null` si elle n'existe pas (page
  /// précédente de la première page, page suivante de la dernière) ou si le
  /// tri demandé est invalide.
  _SearchRequest? _searchRequestFor(
    DatasourceConfig config,
    _Runtime runtime,
    DatasourceCommand command,
    String? field,
    DatasourceSortDirection? direction,
  ) {
    final sort = _currentSort(config, runtime);
    final page = runtime.page;
    _SearchRequest first([DatasourceSortOrder? order]) => _SearchRequest(
      pageIndex: 0,
      firstIndex: 0,
      cursor: null,
      sort: order ?? sort,
      append: false,
    );
    switch (command) {
      case DatasourceCommand.search:
      case DatasourceCommand.firstPage:
        return first();
      case DatasourceCommand.refresh:
        final index = runtime.firstIndex;
        return _SearchRequest(
          pageIndex: index,
          firstIndex: index,
          cursor: index < runtime.cursors.length
              ? runtime.cursors[index]
              : null,
          sort: sort,
          append: false,
        );
      case DatasourceCommand.previousPage:
        final index = runtime.firstIndex - 1;
        if (index < 0) return null;
        return _SearchRequest(
          pageIndex: index,
          firstIndex: index,
          cursor: index < runtime.cursors.length
              ? runtime.cursors[index]
              : null,
          sort: sort,
          append: false,
        );
      case DatasourceCommand.nextPage:
      case DatasourceCommand.loadMore:
        if (!page.hasNext) return null;
        final index = runtime.pageIndex + 1;
        final append = command == DatasourceCommand.loadMore;
        return _SearchRequest(
          pageIndex: index,
          firstIndex: append ? runtime.firstIndex : index,
          cursor: page.nextCursor,
          sort: sort,
          append: append,
        );
      case DatasourceCommand.sort:
        final sortConfig = config.search!.sort!;
        if (field == null || !sortConfig.allows(field)) return null;
        final next =
            direction ??
            (sort?.field == field
                ? sort!.direction.reversed
                : DatasourceSortDirection.asc);
        return first(DatasourceSortOrder(field, next));
      case DatasourceCommand.create:
      case DatasourceCommand.read:
      case DatasourceCommand.update:
      case DatasourceCommand.delete:
        return null;
    }
  }

  /// Contexte `{{ds.*}}` et paramètres automatiques de la page [request].
  static ({Map<String, Object?> context, Map<String, Object?> extra})
  _searchParameters(DatasourceSearchConfig search, _SearchRequest request) {
    final pagination = search.pagination;
    final order = request.sort;
    return (
      context: {
        'page': pagination?.pageNumber(request.pageIndex) ?? 1,
        'pageSize': ?pagination?.pageSize,
        'offset': request.pageIndex * (pagination?.pageSize ?? 0),
        'limit': ?pagination?.pageSize,
        'cursor': ?request.cursor,
        'sort': ?order?.field,
        'direction': ?order?.direction.name,
      },
      extra: {
        if (order != null) ...search.sort!.parametersFor(order),
        ...?pagination?.parametersFor(
          request.pageIndex,
          cursor: request.cursor,
        ),
      },
    );
  }

  /// Exécute la recherche de [config] (page 1, tri par défaut) sans rien
  /// écrire (aperçu de l'éditeur) ; retourne les lignes, le total et le
  /// curseur suivant lus dans la réponse.
  ///
  /// Lève une [DataProviderException] au message affichable.
  Future<({List<Object?> rows, int? total, String? nextCursor})> previewSearch(
    DatasourceConfig config,
  ) async {
    final search = config.search;
    if (search == null) {
      throw const DataProviderException('Aucune recherche configurée.');
    }
    final request = _SearchRequest(
      pageIndex: 0,
      firstIndex: 0,
      cursor: null,
      sort: search.sort?.defaultOrder,
      append: false,
    );
    final (:context, :extra) = _searchParameters(search, request);
    final result = await providers.previewExecute(
      search.provider,
      request: (parameters) => DataProviderRequest(
        parameters: parameters,
        context: context,
        extraParameters: extra,
      ),
      excludeParameters: [?search.state],
    );
    final rows = result.rows;
    if (rows == null) {
      throw const DataProviderException(
        'La recherche doit retourner une liste de lignes.',
      );
    }
    final raw = _normalized(result.raw);
    final pagination = search.pagination;
    return (
      rows: rows,
      total: pagination?.totalPath == null
          ? null
          : _intAt(raw, pagination!.totalPath!),
      nextCursor: pagination?.nextCursorPath == null
          ? null
          : _cursorAt(raw, pagination!.nextCursorPath!),
    );
  }

  static int? _intAt(Object? raw, String path) {
    final value = _readAt(raw, path);
    final number = switch (value) {
      final int number => number,
      final double number when number.isFinite && number % 1 == 0 =>
        number.toInt(),
      final String text => int.tryParse(text.trim()),
      _ => null,
    };
    return number != null && number >= 0 ? number : null;
  }

  static String? _cursorAt(Object? raw, String path) =>
      switch (_readAt(raw, path)) {
        final String text when text.isNotEmpty => text,
        final int number => '$number',
        _ => null,
      };

  Future<DatasourceStatus> _search(
    DatasourceConfig config,
    _Runtime runtime,
    DatasourceCommand command,
    _SearchRequest request,
    bool reportErrors,
  ) async {
    final search = config.search!;
    final epoch = runtime.epoch;
    final mutations = runtime.mutationsStarted;
    final run = _start(runtime, command);
    runtime.lastSearch = request;
    runtime.searchesInFlight++;
    final (:context, :extra) = _searchParameters(search, request);
    try {
      final status = await providers.execute(
        search.provider,
        request: (parameters) => DataProviderRequest(
          parameters: parameters,
          context: context,
          extraParameters: extra,
        ),
        writeTarget: false,
        excludeParameters: [?search.state],
        reportErrors: reportErrors,
        onResult: (provider, result, isCurrent) async {
          bool live() => isCurrent() && !_disposed && runtime.epoch == epoch;
          if (!live()) return null;
          if (runtime.mutationsStarted != mutations) {
            runtime.searchNeedsRerun = true;
            return null;
          }
          final rows = result.rows;
          if (rows == null) {
            throw const DataProviderException(
              'La recherche doit retourner une liste de lignes.',
            );
          }
          final normalizedRows = _normalized(rows) as List<Object?>;
          final raw = _normalized(result.raw);
          final written = await _writeSearchRows(
            config,
            provider.target!,
            normalizedRows,
            request.append,
            () => live() && runtime.mutationsStarted == mutations,
          );
          if (written == null) return null;
          _commitSearch(config, runtime, request, normalizedRows, raw);
          await _writeState(config, runtime, live);
          return normalizedRows.length;
        },
      );
      return _finish(runtime, run, command, status);
    } finally {
      runtime.searchesInFlight--;
    }
  }

  /// Remplace (ou complète) la liste et retrouve la sélection par clé ;
  /// retourne `null` si l'écriture a été abandonnée.
  Future<List<Object?>?> _writeSearchRows(
    DatasourceConfig config,
    JsonTextBinding target,
    List<Object?> rows,
    bool append,
    bool Function() live,
  ) async {
    final repositoryId = target.repositoryId!;
    final selection = store
        .bindingOf(repositoryId)
        .array(_canonical(target.path));
    final selectedIndex = selection.indexFor(const []);
    Object? selectedKey;
    final List<Object?> written;
    try {
      written = await store.updateArray(repositoryId, target.path, (items) {
        if (!live()) throw const _Stale();
        if (selectedIndex != null && selectedIndex < items.length) {
          selectedKey = _keyOf(config, items[selectedIndex]);
        }
        if (!append) return rows;
        final known = {for (final item in items) ?_keyOf(config, item)};
        return [
          ...items,
          for (final row in rows)
            if (!known.contains(_keyOf(config, row))) row,
        ];
      }, componentId: 'datasource:${config.id}');
    } on _Stale {
      return null;
    }
    if (selectedIndex == null || append) return written;
    final key = selectedKey;
    final index = key == null
        ? -1
        : written.indexWhere((row) => _keyOf(config, row) == key);
    if (index < 0) {
      selection.clear();
    } else if (index != selectedIndex) {
      selection.select(const [], index);
    }
    return written;
  }

  void _commitSearch(
    DatasourceConfig config,
    _Runtime runtime,
    _SearchRequest request,
    List<Object?> rows,
    Object? raw,
  ) {
    final search = config.search!;
    final pagination = search.pagination;
    final size = pagination?.pageSize;
    final total = pagination == null
        ? rows.length
        : pagination.totalPath == null
        ? null
        : _intAt(raw, pagination.totalPath!);
    final nextCursor = pagination?.mode == DatasourcePaginationMode.cursor
        ? _cursorAt(raw, pagination!.nextCursorPath!)
        : null;
    final hasNext = switch (pagination) {
      null => false,
      DatasourcePagination(mode: DatasourcePaginationMode.cursor) =>
        nextCursor != null,
      _ when total != null => (request.pageIndex + 1) * size! < total,
      _ => rows.length >= size!,
    };
    runtime
      ..pageIndex = request.pageIndex
      ..firstIndex = request.firstIndex
      ..cursors = [
        ...runtime.cursors.take(request.pageIndex),
        for (var i = runtime.cursors.length; i < request.pageIndex; i++) null,
        request.cursor,
      ]
      ..sort = request.sort
      ..sortChosen = true
      ..page = DatasourcePageState(
        page: request.pageIndex + 1,
        pageSize: size,
        offset: request.pageIndex * (size ?? 0),
        total: total,
        pageCount: total == null
            ? null
            : size == null
            ? 1
            : (total / size).ceil(),
        hasNext: hasNext,
        hasPrevious: request.firstIndex > 0,
        cursor: request.cursor,
        nextCursor: nextCursor,
        sort: request.sort,
        // « Charger plus » garde les lignes déjà modifiées localement.
        needsRefresh: request.append && runtime.page.needsRefresh,
      );
  }

  /// Écrit l'état de pagination dans `state` (si configuré).
  Future<void> _writeState(
    DatasourceConfig config,
    _Runtime runtime,
    bool Function() live,
  ) async {
    final state = config.search?.state;
    if (state == null || !live()) return;
    final json = runtime.page.toJson();
    await store.updateValue(
      state.repositoryId!,
      state.path,
      (_) => json,
      componentId: 'datasource:${config.id}',
    );
  }

  /// Après une modification locale de la liste : signale qu'une recherche
  /// est nécessaire pour réconcilier ordre, pages et filtrage, et ajuste le
  /// total de [delta] (ligne réellement insérée ou retirée).
  Future<void> _listChanged(
    DatasourceConfig config,
    _Runtime runtime,
    int delta,
    bool Function() live,
  ) async {
    var page = runtime.page.copyWith(needsRefresh: true);
    final total = page.total;
    if (delta != 0 && total != null) {
      final next = (total + delta).clamp(0, 1 << 52);
      final size = page.pageSize;
      page = page.copyWith(
        total: next,
        pageCount: size == null ? 1 : (next / size).ceil(),
        hasNext:
            config.search?.pagination?.mode ==
                    DatasourcePaginationMode.cursor ||
                size == null
            ? page.hasNext
            : (runtime.pageIndex + 1) * size < next,
      );
    }
    runtime.page = page;
    await _writeState(config, runtime, live);
  }

  // -------------------------------------------------------------- Entités

  Object? _keyOf(DatasourceConfig config, Object? entity) {
    final path = config.keyPath;
    if (path == null || entity is! Map) return null;
    return switch (_readAt(entity, path)) {
      final String text when text.isNotEmpty => text,
      final int number => number,
      _ => null,
    };
  }

  /// Entité retournée par une opération : objet, ou liste d'un seul objet.
  static Map<String, Object?>? _entityOf(DataProviderResult result) {
    final data = switch (result.data) {
      final Map<Object?, Object?> map => map,
      [final Map<Object?, Object?> map] => map,
      _ => null,
    };
    if (data == null) return null;
    return (_normalized(data) as Map).cast<String, Object?>();
  }

  /// Clé retournée seule par une opération (identifiant créé), ou `null`.
  static Object? _scalarKey(Object? data) => switch (data) {
    final String text when text.isNotEmpty => text,
    final int number => number,
    _ => null,
  };

  JsonTextBinding? _targetOf(DatasourceConfig config, DatasourceOperation op) {
    final id = config.providerOf(op);
    return id == null ? null : providers.provider(id)?.target;
  }

  Future<_Entity?> _currentEntity(
    DatasourceConfig config,
    JsonListScope? scope,
  ) async {
    Map<String, Object?>? entity;
    final list = _targetOf(config, DatasourceOperation.search);
    if (list != null) {
      final repositoryId = list.repositoryId!;
      final canonical = _canonical(list.path);
      int? index;
      if (scope != null &&
          !scope.placeholder &&
          scope.repositoryId == repositoryId &&
          scope.arrayTemplate == canonical &&
          scope.indices.isNotEmpty) {
        final candidate = scope.indices.last;
        final nodePath = scope.nodePath;
        if (nodePath == null || nodePath == '$canonical[$candidate]') {
          index = candidate;
        }
      }
      index ??= store
          .bindingOf(repositoryId)
          .array(canonical)
          .indexFor(const []);
      if (index != null) {
        entity = await _entityAt(repositoryId, '$canonical[$index]');
      }
    }
    final detail = _targetOf(config, DatasourceOperation.read);
    if (entity == null && detail != null) {
      entity = await _entityAt(detail.repositoryId!, detail.path);
    }
    final key = _keyOf(config, entity);
    if (entity == null || key == null) return null;
    return (key: key, entity: entity);
  }

  Future<Map<String, Object?>?> _entityAt(
    String repositoryId,
    String path,
  ) async {
    try {
      await store.flushBindings();
      final node = _readAt(await store.readDocument(repositoryId), path);
      return node is Map
          ? (_normalized(node) as Map).cast<String, Object?>()
          : null;
    } on Object {
      return null;
    }
  }

  static Map<String, Object?> _entityContext(_Entity entity) => {
    'key': entity.key,
    'entity': entity.entity,
  };

  /// Remplace la ligne de clé [key] par [entity], ou l'insère si [insert]
  /// est fourni ; retourne sa position (`null` si absente ou sans liste) et
  /// si elle a été insérée, ou `null` si l'écriture a été abandonnée.
  Future<({int? index, bool inserted})?> _upsertRow(
    DatasourceConfig config,
    Object key,
    Map<String, Object?> entity,
    bool Function() live, {
    DatasourceInsert? insert,
  }) async {
    final list = _targetOf(config, DatasourceOperation.search);
    if (list == null) return (index: null, inserted: false);
    int? index;
    var inserted = false;
    try {
      await store.updateArray(list.repositoryId!, list.path, (items) {
        if (!live()) throw const _Stale();
        index = null;
        inserted = false;
        final found = items.indexWhere((row) => _keyOf(config, row) == key);
        if (found >= 0) {
          index = found;
          return items..[found] = entity;
        }
        if (insert == null) return items;
        final at = insert == DatasourceInsert.start ? 0 : items.length;
        index = at;
        inserted = true;
        return items..insert(at, entity);
      }, componentId: 'datasource:${config.id}');
    } on _Stale {
      return null;
    }
    return (index: index, inserted: inserted);
  }

  /// Reporte [entity] (clé [key]) dans la liste et le détail.
  ///
  /// Create ([insert] fourni) l'insère si elle est absente, la sélectionne
  /// et remplace le détail ; Update remplace seulement la ligne et le détail
  /// de même clé (une entité hors de la page n'est pas ajoutée). Retourne
  /// `false` si l'écriture a été abandonnée.
  Future<bool> _applyEntity(
    DatasourceConfig config,
    _Runtime runtime,
    Object key,
    Map<String, Object?> entity,
    bool Function() live, {
    DatasourceInsert? insert,
  }) async {
    final row = await _upsertRow(config, key, entity, live, insert: insert);
    if (row == null) return false;
    final list = _targetOf(config, DatasourceOperation.search);
    final index = row.index;
    if (list != null) {
      if (insert != null && index != null && live()) {
        store
            .bindingOf(list.repositoryId!)
            .array(_canonical(list.path))
            .select(const [], index);
      }
      await _listChanged(config, runtime, row.inserted ? 1 : 0, live);
    }
    final written = await _writeDetail(
      config,
      runtime,
      (current) =>
          insert != null || _keyOf(config, current) == key ? entity : current,
      live,
    );
    if (written) runtime.detailVersion++;
    return written;
  }

  static const _incomplete =
      'Opération réussie, synchronisation locale incomplète : ';

  /// Synchronise une entité que Create / Update n'a pas retournée : la relit
  /// par Read si sa clé [key] est connue, puis la reporte
  /// ([_applyEntity]) ; sinon, ne devine rien et ne relance pas la mutation.
  ///
  /// Retourne l'avertissement (signalé au store si [reportErrors]), ou
  /// `null` si la synchronisation a réussi ou est devenue obsolète.
  Future<String?> _resync(
    DatasourceConfig config,
    _Runtime runtime, {
    required Object? key,
    required Map<String, Object?>? known,
    required String what,
    required bool Function() live,
    required bool reportErrors,
    DatasourceInsert? insert,
  }) async {
    final String reason;
    final read = config.read;
    if (key == null) {
      reason = 'l’entité $what n’a pas été retournée.';
    } else if (read == null) {
      reason =
          'l’entité $what n’a pas été retournée et aucune opération Read ne '
          'permet de la relire.';
    } else {
      Map<String, Object?>? fresh;
      final status = await providers.execute(
        read.provider,
        request: (parameters) => DataProviderRequest(
          parameters: parameters,
          context: {'key': key, 'entity': ?known},
        ),
        writeTarget: false,
        reportErrors: false,
        onResult: (provider, result, isCurrent) async {
          fresh = _entityOf(result);
          return fresh == null ? null : 1;
        },
      );
      if (!live()) return null;
      final entity = fresh;
      if (status.phase == DataProviderPhase.success &&
          entity != null &&
          _keyOf(config, entity) == key) {
        await _applyEntity(config, runtime, key, entity, live, insert: insert);
        return null;
      }
      reason = status.phase == DataProviderPhase.error
          ? 'la relecture par Read a échoué (${status.message ?? ''}).'
          : 'la relecture par Read n’a retourné aucune entité de même clé.';
    }
    final message = '$_incomplete$reason';
    if (config.search != null) {
      await _listChanged(config, runtime, 0, live);
    }
    if (reportErrors && live()) store.reportBindingError(message);
    return message;
  }

  /// Écrit [change] dans la cible Read ; retourne `false` si l'écriture a
  /// été abandonnée.
  Future<bool> _writeDetail(
    DatasourceConfig config,
    _Runtime runtime,
    Object? Function(Object? current) change,
    bool Function() live,
  ) async {
    final detail = _targetOf(config, DatasourceOperation.read);
    if (detail == null) return true;
    try {
      await store.updateValue(detail.repositoryId!, detail.path, (current) {
        if (!live()) throw const _Stale();
        return change(current);
      }, componentId: 'datasource:${config.id}');
      return true;
    } on _Stale {
      return false;
    }
  }

  Future<DatasourceStatus> _create(
    DatasourceConfig config,
    _Runtime runtime,
    bool reportErrors,
  ) async {
    const command = DatasourceCommand.create;
    final epoch = runtime.epoch;
    final run = _start(runtime, command);
    runtime.mutationsStarted++;
    bool live() => !_disposed && runtime.epoch == epoch;
    final insert = config.create!.insert;
    var synced = false;
    Object? key;
    final status = await providers.execute(
      config.create!.provider,
      reportErrors: reportErrors,
      onResult: (provider, result, isCurrent) async {
        bool current() => isCurrent() && live();
        if (!current()) {
          synced = true;
          return null;
        }
        final entity = _entityOf(result);
        final entityKey = _keyOf(config, entity);
        // Une API peut ne retourner que l'identifiant créé.
        key = entityKey ?? _scalarKey(result.data);
        if (entity == null || entityKey == null) return null;
        synced = true;
        await _applyEntity(
          config,
          runtime,
          entityKey,
          entity,
          current,
          insert: insert,
        );
        return 1;
      },
    );
    String? notice;
    if (status.phase == DataProviderPhase.success && !synced && live()) {
      notice = await _resync(
        config,
        runtime,
        key: key,
        known: null,
        what: 'créée',
        live: live,
        reportErrors: reportErrors,
        insert: insert,
      );
    }
    return _finish(runtime, run, command, status, notice: notice);
  }

  Future<DatasourceStatus> _read(
    DatasourceConfig config,
    _Runtime runtime,
    _Entity entity,
    bool reportErrors,
  ) async {
    const command = DatasourceCommand.read;
    final epoch = runtime.epoch;
    final version = runtime.detailVersion;
    final run = _start(runtime, command);
    final status = await providers.execute(
      config.read!.provider,
      request: (parameters) => DataProviderRequest(
        parameters: parameters,
        context: _entityContext(entity),
      ),
      writeTarget: false,
      reportErrors: reportErrors,
      onResult: (provider, result, isCurrent) async {
        bool live() =>
            isCurrent() &&
            !_disposed &&
            runtime.epoch == epoch &&
            runtime.detailVersion == version;
        if (!live()) return null;
        final read = _entityOf(result);
        if (read == null) {
          throw const DataProviderException(
            'La lecture n’a retourné aucune entité.',
          );
        }
        await _writeDetail(config, runtime, (_) => read, live);
        return 1;
      },
    );
    return _finish(runtime, run, command, status);
  }

  Future<DatasourceStatus> _update(
    DatasourceConfig config,
    _Runtime runtime,
    _Entity entity,
    bool reportErrors,
  ) async {
    const command = DatasourceCommand.update;
    final epoch = runtime.epoch;
    final run = _start(runtime, command);
    runtime.mutationsStarted++;
    bool live() => !_disposed && runtime.epoch == epoch;
    var synced = false;
    final status = await providers.execute(
      config.update!.provider,
      request: (parameters) => DataProviderRequest(
        parameters: parameters,
        context: _entityContext(entity),
      ),
      reportErrors: reportErrors,
      onResult: (provider, result, isCurrent) async {
        bool current() => isCurrent() && live();
        if (!current()) {
          synced = true;
          return null;
        }
        final updated = _entityOf(result);
        if (updated == null || _keyOf(config, updated) != entity.key) {
          return null;
        }
        synced = true;
        await _applyEntity(config, runtime, entity.key, updated, current);
        return 1;
      },
    );
    String? notice;
    if (status.phase == DataProviderPhase.success && !synced && live()) {
      notice = await _resync(
        config,
        runtime,
        key: entity.key,
        known: entity.entity,
        what: 'modifiée',
        live: live,
        reportErrors: reportErrors,
      );
    }
    return _finish(runtime, run, command, status, notice: notice);
  }

  Future<DatasourceStatus> _delete(
    DatasourceConfig config,
    _Runtime runtime,
    _Entity entity,
    bool reportErrors,
  ) async {
    const command = DatasourceCommand.delete;
    final epoch = runtime.epoch;
    final run = _start(runtime, command);
    runtime.mutationsStarted++;
    final status = await providers.execute(
      config.delete!.provider,
      request: (parameters) => DataProviderRequest(
        parameters: parameters,
        context: _entityContext(entity),
      ),
      reportErrors: reportErrors,
      onResult: (provider, result, isCurrent) async {
        bool live() => isCurrent() && !_disposed && runtime.epoch == epoch;
        if (!live()) return null;
        final list = _targetOf(config, DatasourceOperation.search);
        if (list != null) {
          var removed = -1;
          try {
            await store.updateArray(list.repositoryId!, list.path, (items) {
              if (!live()) throw const _Stale();
              removed = items.indexWhere(
                (row) => _keyOf(config, row) == entity.key,
              );
              if (removed >= 0) items.removeAt(removed);
              return items;
            }, componentId: 'datasource:${config.id}');
          } on _Stale {
            return null;
          }
          if (removed >= 0) {
            store
                .bindingOf(list.repositoryId!)
                .removed(_canonical(list.path), const [], removed);
          }
          await _listChanged(config, runtime, removed >= 0 ? -1 : 0, live);
        }
        if (await _writeDetail(
          config,
          runtime,
          (current) => _keyOf(config, current) == entity.key
              ? const <String, Object?>{}
              : current,
          live,
        )) {
          runtime.detailVersion++;
        }
        return 1;
      },
    );
    return _finish(runtime, run, command, status);
  }

  @override
  void dispose() {
    _disposed = true;
    if (identical(providers.coordinator, this)) providers.coordinator = null;
    for (final runtime in _runtimes.values) {
      runtime.status.dispose();
    }
    _runtimes.clear();
    super.dispose();
  }
}
