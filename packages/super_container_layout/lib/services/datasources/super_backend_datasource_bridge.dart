/// Pont d'intégration entre `super_backend` et les datasources de
/// `super_container_layout` : [SuperBackendHttpTransport] et
/// [SuperBackendDatasourceBridge].
///
/// Propose deux modes complémentaires pour relier une collection de
/// [SuperBackend] à un [JsonRepositoryStore] :
///
/// 1. **Mode Code ([SuperBackendDatasourceBridge.registerCodeDatasource])** :
///    enregistre automatiquement les 5 [CallbackDataProvider] (`<id>_search`,
///    `<id>_create`, `<id>_read`, `<id>_update`, `<id>_delete`) et la
///    [DatasourceConfig] dans `store.providers` et `store.datasources`.
/// 2. **Mode Éditeur / HTTP virtuel ([SuperBackendDatasourceBridge.installHttpTransport]
///    et [SuperBackendDatasourceBridge.saveEditorDatasource])** :
///    installe un [SuperBackendHttpTransport] qui intercepte les appels vers
///    l'hôte virtuel `https://super.backend` pour les exécuter localement via
///    [SuperBackendHttpRouter], et sauvegarde les 5 [HttpProviderConfig] ainsi
///    que la [DatasourceConfig] dans `<dossier du store>/providers/` et
///    `<dossier du store>/datasources/`.
library;

import 'package:super_backend/super_backend.dart';

import '../../models/datasources/datasource_config.dart';
import '../../models/json_text_binding.dart';
import '../../models/providers/data_provider.dart';
import '../../models/providers/http_provider_config.dart';
import '../providers/data_provider_http_transport.dart';
import '../repositories/json_repository_store.dart';

export 'package:super_backend/super_backend.dart'
    show
        CollectionApi,
        CollectionStore,
        MemoryCollectionStore,
        ScrudConnectorResult,
        ScrudDatasourceBlueprint,
        ScrudDatasourceConnector,
        ScrudFilter,
        ScrudFilterOperator,
        ScrudOperation,
        ScrudPagination,
        ScrudPaginationMode,
        ScrudSearchRequest,
        ScrudSearchResult,
        ScrudSortDirection,
        ScrudSortOrder,
        SqliteCollectionStore,
        StoredJsonRow,
        SuperBackend,
        SuperBackendException,
        SuperBackendHttpRequest,
        SuperBackendHttpResponse,
        SuperBackendHttpRouter;

/// Transport HTTP interceptant les requêtes destinées à [SuperBackendHttpRouter]
/// et déléguant toutes les autres URLs au transport [fallback] (`dart:io` par
/// défaut).
class SuperBackendHttpTransport extends DataProviderHttpTransport {
  /// Crée un transport HTTP hybride routant les URLs reconnues par [router]
  /// vers [SuperBackend] et le reste vers [fallback].
  SuperBackendHttpTransport({
    required this.router,
    DataProviderHttpTransport? fallback,
  }) : _fallback = fallback ?? DartIoDataProviderHttpTransport();

  /// Routeur REST local connecté à [SuperBackend].
  final SuperBackendHttpRouter router;

  final DataProviderHttpTransport _fallback;

  @override
  Future<DataProviderHttpResponse> send(DataProviderHttpRequest request) async {
    if (router.matchesUri(request.uri)) {
      await router.backend.init();
      final response = await router.handle(
        SuperBackendHttpRequest(
          method: request.method,
          uri: request.uri,
          headers: request.headers,
          body: request.body,
        ),
      );
      return DataProviderHttpResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    }
    return _fallback.send(request);
  }

  @override
  void close({bool force = false}) {
    _fallback.close(force: force);
  }
}

/// Pont haut niveau connectant un [SuperBackend] aux registres `providers` et
/// `datasources` d'un [JsonRepositoryStore].
class SuperBackendDatasourceBridge {
  /// Crée un pont entre [backend] et [store].
  SuperBackendDatasourceBridge({
    required this.backend,
    required this.store,
    this.apiPrefix = '/api',
    this.virtualHost = 'super.backend',
  });

  /// Instance de backend local SCRUD.
  final SuperBackend backend;

  /// Store de repositories JSON cible.
  final JsonRepositoryStore store;

  /// Préfixe REST utilisé par le routeur HTTP virtuel.
  final String apiPrefix;

  /// Nom d'hôte virtuel intercepté par [installHttpTransport].
  final String virtualHost;

  /// Installe un [SuperBackendHttpTransport] sur `store.providers.httpTransport`
  /// afin que tous les [HttpProviderConfig] pointant vers
  /// `https://<virtualHost><apiPrefix>/<collection>` soient exécutés par
  /// [backend].
  SuperBackendHttpTransport installHttpTransport({
    DataProviderHttpTransport? fallback,
  }) {
    final transport = SuperBackendHttpTransport(
      router: SuperBackendHttpRouter(
        backend: backend,
        apiPrefix: apiPrefix,
        virtualHost: virtualHost,
      ),
      fallback: fallback,
    );
    store.providers.httpTransport = transport;
    return transport;
  }

  /// Enregistre en mémoire (mode Code) les 5 [CallbackDataProvider] (`search`,
  /// `create`, `read`, `update`, `delete`) et la [DatasourceConfig] pour une
  /// collection de [backend].
  ///
  /// Retourne la [DatasourceConfig] enregistrée dans `store.datasources`.
  DatasourceConfig registerCodeDatasource({
    required String datasourceId,
    String? collection,
    String? label,
    String keyPath = 'id',
    required JsonTextBinding listTarget,
    JsonTextBinding? detailTarget,
    JsonTextBinding? stateTarget,
    String? searchFilterRepositoryId,
    String? formRepositoryId,
    JsonTextBinding? searchLoading,
    JsonTextBinding? searchError,
    ProviderAutoSearch? autoSearch,
    DatasourceSort? sort,
    DatasourcePagination? pagination = const DatasourcePagination(
      totalPath: 'total',
    ),
    DatasourceInsert insert = DatasourceInsert.end,
    bool mergeUpdates = true,
    bool upsertCreates = false,
  }) {
    final effectiveCollection = collection ?? datasourceId;
    final effectiveLabel = label ?? datasourceId;
    final connector = ScrudDatasourceConnector(
      backend: backend,
      collection: effectiveCollection,
      mergeUpdates: mergeUpdates,
      upsertCreates: upsertCreates,
    );

    final searchId = '${datasourceId}_search';
    final createId = '${datasourceId}_create';
    final readId = '${datasourceId}_read';
    final updateId = '${datasourceId}_update';
    final deleteId = '${datasourceId}_delete';

    store.providers.register(
      CallbackDataProvider(
        id: searchId,
        label: '$effectiveLabel (Search)',
        filterRepositoryId: searchFilterRepositoryId,
        target: listTarget,
        loading: searchLoading,
        error: searchError,
        autoSearch: autoSearch,
        onExecute: (request) => _runConnector(
          connector,
          ScrudOperation.search,
          request,
        ),
      ),
    );

    store.providers.register(
      CallbackDataProvider(
        id: createId,
        label: '$effectiveLabel (Create)',
        filterRepositoryId: formRepositoryId,
        onExecute: (request) => _runConnector(
          connector,
          ScrudOperation.create,
          request,
        ),
      ),
    );

    store.providers.register(
      CallbackDataProvider(
        id: readId,
        label: '$effectiveLabel (Read)',
        target: detailTarget,
        onExecute: (request) => _runConnector(
          connector,
          ScrudOperation.read,
          request,
        ),
      ),
    );

    store.providers.register(
      CallbackDataProvider(
        id: updateId,
        label: '$effectiveLabel (Update)',
        filterRepositoryId: formRepositoryId,
        onExecute: (request) => _runConnector(
          connector,
          ScrudOperation.update,
          request,
        ),
      ),
    );

    store.providers.register(
      CallbackDataProvider(
        id: deleteId,
        label: '$effectiveLabel (Delete)',
        onExecute: (request) => _runConnector(
          connector,
          ScrudOperation.delete,
          request,
        ),
      ),
    );

    final config = DatasourceConfig(
      id: datasourceId,
      label: effectiveLabel,
      keyPath: keyPath,
      search: DatasourceSearchConfig(
        provider: searchId,
        state: stateTarget,
        sort: sort,
        pagination: pagination,
      ),
      create: DatasourceCreateConfig(provider: createId, insert: insert),
      read: DatasourceEntityConfig(provider: readId),
      update: DatasourceEntityConfig(provider: updateId),
      delete: DatasourceEntityConfig(provider: deleteId),
    );
    store.datasources.register(config);
    return config;
  }

  /// Désenregistre la datasource de code [datasourceId] et ses 5 providers.
  void unregisterCodeDatasource(String datasourceId) {
    store.datasources.unregister(datasourceId);
    for (final suffix in const ['search', 'create', 'read', 'update', 'delete']) {
      store.providers.unregister('${datasourceId}_$suffix');
    }
  }

  /// Génère et persiste uniquement les 5 [HttpProviderConfig] décrits par
  /// [blueprint] dans `<store>/providers/`, puis retourne la
  /// [DatasourceConfig] correspondante (sans l'enregistrer sur disque).
  Future<DatasourceConfig> saveEditorProviders(
    ScrudDatasourceBlueprint blueprint,
  ) async {
    for (final json in blueprint.buildHttpProviderJsons()) {
      final providerConfig = HttpProviderConfig.fromJson(json);
      await store.providers.save(providerConfig);
    }
    return DatasourceConfig.fromJson(blueprint.buildDatasourceJson());
  }

  /// Génère et persiste dans `<store>/providers/` et `<store>/datasources/`
  /// les 5 [HttpProviderConfig] et la [DatasourceConfig] décrits par
  /// [blueprint].
  ///
  /// Combinez cet appel avec [installHttpTransport] pour que l'éditeur visuel
  /// puisse inspecter, modifier et exécuter ces providers sur [backend].
  Future<DatasourceConfig> saveEditorDatasource(
    ScrudDatasourceBlueprint blueprint,
  ) async {
    final datasourceConfig = await saveEditorProviders(blueprint);
    await store.datasources.save(datasourceConfig);
    return datasourceConfig;
  }

  /// Extrait le nom de la collection SQLite si [urlTemplate] cible l'hôte
  /// virtuel [virtualHost] et le préfixe [apiPrefix], ou retourne `null`.
  static String? collectionFromUrl(
    String urlTemplate, {
    String virtualHost = 'super.backend',
    String apiPrefix = '/api',
  }) {
    final sanitized = urlTemplate.replaceAll(RegExp(r'\{\{[^}]+\}\}'), '_key_');
    final uri = Uri.tryParse(sanitized);
    if (uri == null || uri.host.toLowerCase() != virtualHost.toLowerCase()) {
      return null;
    }
    final prefixSegments = apiPrefix
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < prefixSegments.length + 1) return null;
    for (var i = 0; i < prefixSegments.length; i++) {
      if (segments[i] != prefixSegments[i]) return null;
    }
    return Uri.decodeComponent(segments[prefixSegments.length]);
  }

  static Future<DataProviderResult> _runConnector(
    ScrudDatasourceConnector connector,
    ScrudOperation operation,
    DataProviderRequest request,
  ) async {
    try {
      await connector.backend.init();
      final result = await connector.execute(
        operation,
        parameters: request.parameters,
        context: request.context,
        extraParameters: request.extraParameters,
      );
      return DataProviderResult(data: result.data, raw: result.raw);
    } on SuperBackendException catch (error) {
      throw DataProviderException(error.message);
    }
  }
}
