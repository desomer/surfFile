/// Pont d'export et de génération d'artefacts reliant un domaine métier de
/// `super_backend_editor` à un dossier d'application `super_designer` /
/// `super_container_layout` ([SuperDesignerBackendBridge],
/// [SuperDesignerBridgeOptions], [SuperDesignerBridgeExportResult]).
///
/// Génère et valide de manière déterministe :
/// * les `DatasourceConfig` SCRUD (`datasources/<id>.json`) et leurs 5
///   `HttpProviderConfig` (`providers/<id>_search|create|read|update|delete.json`)
///   via [ScrudDatasourceBlueprint], ciblant soit le serveur HTTP local
///   (`http://<host>:<port><apiPrefix>`) soit le transport virtuel en mémoire
///   (`https://super.backend<apiPrefix>`) ;
/// * les `HttpProviderConfig` dédiés aux endpoints applicatifs CQRS
///   (`cqrsCommand` et `cqrsQuery`) ;
/// * les repositories JSON (`repositories/<id>.json`) et leurs JSON Schemas
///   compagnons (`repositories/<id>.schema.json`) conformes au guide
///   `REPOSITORY_JSON_AI_GUIDE.md` (`<collection>_repo`, `<collection>_filter`,
///   `<collection>_form`, ainsi que les repositories d'entrée/sortie CQRS).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/backend_domain_project.dart';
import '../../models/backend_overlay_config.dart';
import '../../models/domain_design_spec.dart';
import '../../models/json_value_utils.dart';

const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

final RegExp _invalidRepoKeyChars = RegExp(r'[.\[\]?\s\x00-\x1f]');
final RegExp _expressColonParam = RegExp(r':([A-Za-z_][A-Za-z0-9_]*)');
final RegExp _singleBraceParam = RegExp(
  r'(?<!\{)\{([A-Za-z_][A-Za-z0-9_-]*)\}(?!\})',
);

/// Options de génération du bundle d'intégration vers `super_designer` /
/// `super_container_layout`.
@immutable
class SuperDesignerBridgeOptions {
  /// Crée les options d'export du pont `super_designer`.
  const SuperDesignerBridgeOptions({
    this.useLiveLocalHttpUrl = true,
    this.includeScrudDatasources = true,
    this.includeCqrsProviders = true,
    this.includeRepositorySchemasAndSeeds = true,
  });

  /// Si vrai (défaut), cible l'URL HTTP réelle du serveur local
  /// (`http://<host>:<port>`) ; sinon cible l'hôte virtuel
  /// `https://super.backend` intercepté en mémoire par
  /// [SuperBackendHttpTransport].
  final bool useLiveLocalHttpUrl;

  /// Si vrai (défaut), génère pour chaque collection active une
  /// [DatasourceConfig] et ses 5 [HttpProviderConfig] SCRUD.
  final bool includeScrudDatasources;

  /// Si vrai (défaut), génère également un [HttpProviderConfig] pour chaque
  /// endpoint actif de type `cqrsCommand` ou `cqrsQuery`.
  final bool includeCqrsProviders;

  /// Si vrai (défaut), génère les documents JSON de repositories et leurs
  /// fichiers `.schema.json` associés (`<collection>_repo`,
  /// `<collection>_filter`, `<collection>_form`, et repositories CQRS).
  final bool includeRepositorySchemasAndSeeds;

  /// Retourne une copie modifiée des options.
  SuperDesignerBridgeOptions copyWith({
    bool? useLiveLocalHttpUrl,
    bool? includeScrudDatasources,
    bool? includeCqrsProviders,
    bool? includeRepositorySchemasAndSeeds,
  }) => SuperDesignerBridgeOptions(
    useLiveLocalHttpUrl: useLiveLocalHttpUrl ?? this.useLiveLocalHttpUrl,
    includeScrudDatasources:
        includeScrudDatasources ?? this.includeScrudDatasources,
    includeCqrsProviders: includeCqrsProviders ?? this.includeCqrsProviders,
    includeRepositorySchemasAndSeeds:
        includeRepositorySchemasAndSeeds ??
        this.includeRepositorySchemasAndSeeds,
  );

  /// Sérialise les options en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'useLiveLocalHttpUrl': useLiveLocalHttpUrl,
    'includeScrudDatasources': includeScrudDatasources,
    'includeCqrsProviders': includeCqrsProviders,
    'includeRepositorySchemasAndSeeds': includeRepositorySchemasAndSeeds,
  };

  /// Désérialise les options depuis JSON.
  factory SuperDesignerBridgeOptions.fromJson(Object? raw) {
    if (raw == null) return const SuperDesignerBridgeOptions();
    if (raw is! Map) {
      throw const FormatException('SuperDesignerBridgeOptions invalide.');
    }
    return SuperDesignerBridgeOptions(
      useLiveLocalHttpUrl: raw['useLiveLocalHttpUrl'] as bool? ?? true,
      includeScrudDatasources: raw['includeScrudDatasources'] as bool? ?? true,
      includeCqrsProviders: raw['includeCqrsProviders'] as bool? ?? true,
      includeRepositorySchemasAndSeeds:
          raw['includeRepositorySchemasAndSeeds'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuperDesignerBridgeOptions &&
          other.useLiveLocalHttpUrl == useLiveLocalHttpUrl &&
          other.includeScrudDatasources == includeScrudDatasources &&
          other.includeCqrsProviders == includeCqrsProviders &&
          other.includeRepositorySchemasAndSeeds ==
              includeRepositorySchemasAndSeeds;

  @override
  int get hashCode => Object.hash(
    useLiveLocalHttpUrl,
    includeScrudDatasources,
    includeCqrsProviders,
    includeRepositorySchemasAndSeeds,
  );
}

/// Résultat immuable de la construction ou de l'écriture disque d'un bundle
/// d'intégration vers `super_designer` / `super_container_layout`.
@immutable
class SuperDesignerBridgeExportResult {
  /// Crée un résultat d'export de pont `super_designer`.
  SuperDesignerBridgeExportResult({
    required this.targetDirectoryPath,
    List<String> providerFilesWritten = const <String>[],
    List<String> datasourceFilesWritten = const <String>[],
    List<String> repositoryFilesWritten = const <String>[],
    Map<String, Map<String, Object?>> providersJson =
        const <String, Map<String, Object?>>{},
    Map<String, Map<String, Object?>> datasourcesJson =
        const <String, Map<String, Object?>>{},
    Map<String, Map<String, Object?>> repositoriesJson =
        const <String, Map<String, Object?>>{},
    Map<String, Map<String, Object?>> repositorySchemasJson =
        const <String, Map<String, Object?>>{},
  }) : providerFilesWritten = List<String>.unmodifiable(providerFilesWritten),
       datasourceFilesWritten = List<String>.unmodifiable(
         datasourceFilesWritten,
       ),
       repositoryFilesWritten = List<String>.unmodifiable(
         repositoryFilesWritten,
       ),
       providersJson = _freezeDefinitionMap(providersJson),
       datasourcesJson = _freezeDefinitionMap(datasourcesJson),
       repositoriesJson = _freezeDefinitionMap(repositoriesJson),
       repositorySchemasJson = _freezeDefinitionMap(repositorySchemasJson);

  /// Chemin du répertoire cible de l'export (vide lors d'un simple `buildBundle` sans cible).
  final String targetDirectoryPath;

  /// Chemins complets des fichiers `providers/<id>.json` écrits sur disque.
  final List<String> providerFilesWritten;

  /// Chemins complets des fichiers `datasources/<id>.json` écrits sur disque.
  final List<String> datasourceFilesWritten;

  /// Chemins complets des fichiers `repositories/<id>.json` et
  /// `repositories/<id>.schema.json` écrits sur disque.
  final List<String> repositoryFilesWritten;

  /// Définitions JSON validées de [HttpProviderConfig] indexées par identifiant.
  final Map<String, Map<String, Object?>> providersJson;

  /// Définitions JSON validées de [DatasourceConfig] indexées par identifiant.
  final Map<String, Map<String, Object?>> datasourcesJson;

  /// Documents initiaux de repositories JSON indexés par identifiant.
  final Map<String, Map<String, Object?>> repositoriesJson;

  /// JSON Schemas Draft 2020-12 compagnons indexés par identifiant de repository.
  final Map<String, Map<String, Object?>> repositorySchemasJson;

  /// Retourne une copie modifiée du résultat d'export.
  SuperDesignerBridgeExportResult copyWith({
    String? targetDirectoryPath,
    List<String>? providerFilesWritten,
    List<String>? datasourceFilesWritten,
    List<String>? repositoryFilesWritten,
    Map<String, Map<String, Object?>>? providersJson,
    Map<String, Map<String, Object?>>? datasourcesJson,
    Map<String, Map<String, Object?>>? repositoriesJson,
    Map<String, Map<String, Object?>>? repositorySchemasJson,
  }) => SuperDesignerBridgeExportResult(
    targetDirectoryPath: targetDirectoryPath ?? this.targetDirectoryPath,
    providerFilesWritten: providerFilesWritten ?? this.providerFilesWritten,
    datasourceFilesWritten:
        datasourceFilesWritten ?? this.datasourceFilesWritten,
    repositoryFilesWritten:
        repositoryFilesWritten ?? this.repositoryFilesWritten,
    providersJson: providersJson ?? this.providersJson,
    datasourcesJson: datasourcesJson ?? this.datasourcesJson,
    repositoriesJson: repositoriesJson ?? this.repositoriesJson,
    repositorySchemasJson: repositorySchemasJson ?? this.repositorySchemasJson,
  );

  /// Sérialise le résultat en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'targetDirectoryPath': targetDirectoryPath,
    'providerFilesWritten': providerFilesWritten,
    'datasourceFilesWritten': datasourceFilesWritten,
    'repositoryFilesWritten': repositoryFilesWritten,
    'providersJson': providersJson,
    'datasourcesJson': datasourcesJson,
    'repositoriesJson': repositoriesJson,
    'repositorySchemasJson': repositorySchemasJson,
  };

  static Map<String, Map<String, Object?>> _freezeDefinitionMap(
    Map<String, Map<String, Object?>> raw,
  ) {
    if (raw.isEmpty) return const <String, Map<String, Object?>>{};
    return Map<String, Map<String, Object?>>.unmodifiable(<
      String,
      Map<String, Object?>
    >{
      for (final entry in raw.entries) entry.key: freezeJsonMap(entry.value),
    });
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuperDesignerBridgeExportResult &&
          other.targetDirectoryPath == targetDirectoryPath &&
          listEquals(other.providerFilesWritten, providerFilesWritten) &&
          listEquals(other.datasourceFilesWritten, datasourceFilesWritten) &&
          listEquals(other.repositoryFilesWritten, repositoryFilesWritten) &&
          deepJsonEquals(other.providersJson, providersJson) &&
          deepJsonEquals(other.datasourcesJson, datasourcesJson) &&
          deepJsonEquals(other.repositoriesJson, repositoriesJson) &&
          deepJsonEquals(other.repositorySchemasJson, repositorySchemasJson);

  @override
  int get hashCode => Object.hash(
    targetDirectoryPath,
    Object.hashAll(providerFilesWritten),
    Object.hashAll(datasourceFilesWritten),
    Object.hashAll(repositoryFilesWritten),
    deepJsonHash(providersJson),
    deepJsonHash(datasourcesJson),
    deepJsonHash(repositoriesJson),
    deepJsonHash(repositorySchemasJson),
  );
}

/// Générateur et exporteur de définitions `providers/`, `datasources/` et
/// `repositories/` reliant un [BackendDomainProject] à `super_designer`.
abstract final class SuperDesignerBackendBridge {
  /// Construit en mémoire le bundle complet d'intégration pour [project] en
  /// validant chaque provider via [HttpProviderConfig.fromJson], chaque
  /// datasource via [DatasourceConfig.fromJson] et chaque couple
  /// repository / schéma via [JsonSchemaValidator.assertValid].
  static SuperDesignerBridgeExportResult buildBundle({
    required BackendDomainProject project,
    SuperDesignerBridgeOptions options = const SuperDesignerBridgeOptions(),
    Map<String, List<Map<String, Object?>>> existingEntitiesByCollection =
        const <String, List<Map<String, Object?>>>{},
  }) {
    project.validate();

    final server = project.overlay.server;
    final host = server.host.trim().isEmpty ? '127.0.0.1' : server.host.trim();
    final baseOrigin = options.useLiveLocalHttpUrl
        ? 'http://$host:${server.port}'
        : ScrudDatasourceBlueprint.defaultBaseUrl;

    final providersJson = <String, Map<String, Object?>>{};
    final datasourcesJson = <String, Map<String, Object?>>{};
    final repositoriesJson = <String, Map<String, Object?>>{};
    final repositorySchemasJson = <String, Map<String, Object?>>{};

    final usedDatasourceSlugs = <String>{};
    final usedProviderIds = <String>{};
    final usedRepoIds = <String>{};

    for (final collection in project.overlay.collections) {
      if (!collection.enabled) continue;

      final baseSlug = _allocateUniqueId(
        raw: collection.collectionName,
        used: usedDatasourceSlugs,
        fallback: 'collection',
        maxLength: 24,
      );
      final repoId = _allocateUniqueId(
        raw: '${baseSlug}_repo',
        used: usedRepoIds,
        fallback: 'items_repo',
        maxLength: 32,
      );
      final filterRepoId = _allocateUniqueId(
        raw: '${baseSlug}_filter',
        used: usedRepoIds,
        fallback: 'items_filter',
        maxLength: 32,
      );
      final formRepoId = _allocateUniqueId(
        raw: '${baseSlug}_form',
        used: usedRepoIds,
        fallback: 'items_form',
        maxLength: 32,
      );

      final linkedModel = collection.contractEntryId != null
          ? project.designSpec.findContractById(collection.contractEntryId!)
          : null;
      final safeKeyPath = _sanitizeKeyPath(collection.keyField);
      final sortFields = _extractSortFields(linkedModel, safeKeyPath);
      final safeLabel = _truncateLabel(
        collection.label.trim().isNotEmpty
            ? collection.label.trim()
            : collection.collectionName,
        maxLength: 70,
      );

      if (options.includeScrudDatasources) {
        final blueprint = ScrudDatasourceBlueprint(
          datasourceId: baseSlug,
          collection: collection.collectionName,
          label: safeLabel,
          keyPath: safeKeyPath,
          baseUrl: baseOrigin,
          apiPrefix: server.apiPrefix,
          listTarget: (repositoryId: repoId, path: 'items'),
          detailTarget: (repositoryId: repoId, path: 'selectedItem'),
          stateTarget: (repositoryId: repoId, path: 'pageState'),
          searchFilterRepositoryId: filterRepoId,
          formRepositoryId: formRepoId,
          sortFields: sortFields,
          mergeUpdates: true,
        );

        for (final rawProvider in blueprint.buildHttpProviderJsons()) {
          final enriched = Map<String, Object?>.of(rawProvider);
          if (enriched['id'] == blueprint.searchProviderId) {
            enriched['loading'] = <String, Object?>{
              'repositoryId': repoId,
              'path': 'loading',
            };
            enriched['error'] = <String, Object?>{
              'repositoryId': repoId,
              'path': 'error',
            };
          }
          final validatedProvider = HttpProviderConfig.fromJson(enriched);
          usedProviderIds.add(validatedProvider.id);
          providersJson[validatedProvider.id] = validatedProvider.toJson();
        }

        final rawDatasource = blueprint.buildDatasourceJson();
        final validatedDatasource = DatasourceConfig.fromJson(rawDatasource);
        datasourcesJson[validatedDatasource.id] = validatedDatasource.toJson();
      }

      if (options.includeRepositorySchemasAndSeeds) {
        final rawSeedList =
            existingEntitiesByCollection[collection.collectionName] ??
            existingEntitiesByCollection[collection.id] ??
            const <Map<String, Object?>>[];
        final sanitizedItems = <Map<String, Object?>>[
          for (final item in rawSeedList) _sanitizeRepositoryMap(item),
        ];

        final repoDoc = <String, Object?>{
          'items': sanitizedItems,
          'selectedItem': <String, Object?>{},
          'total': sanitizedItems.length,
          'loading': false,
          'error': '',
          'pageState': DatasourcePageState.initial.toJson(),
        };
        final repoSchema = _buildCollectionRepoSchema(
          repoId: repoId,
          label: safeLabel,
          model: linkedModel,
          keyField: safeKeyPath,
          document: repoDoc,
        );
        _putValidatedRepository(
          repoId: repoId,
          document: repoDoc,
          schema: repoSchema,
          repositoriesJson: repositoriesJson,
          repositorySchemasJson: repositorySchemasJson,
        );

        final (:filterDoc, :filterSchema) = _buildFilterRepoAndSchema(
          repoId: filterRepoId,
          label: safeLabel,
          model: linkedModel,
        );
        _putValidatedRepository(
          repoId: filterRepoId,
          document: filterDoc,
          schema: filterSchema,
          repositoriesJson: repositoriesJson,
          repositorySchemasJson: repositorySchemasJson,
        );

        final (:formDoc, :formSchema) = _buildFormRepoAndSchema(
          repoId: formRepoId,
          label: safeLabel,
          model: linkedModel,
          keyField: safeKeyPath,
        );
        _putValidatedRepository(
          repoId: formRepoId,
          document: formDoc,
          schema: formSchema,
          repositoriesJson: repositoriesJson,
          repositorySchemasJson: repositorySchemasJson,
        );
      }
    }

    if (options.includeCqrsProviders) {
      for (final endpoint in project.overlay.endpoints) {
        if (!endpoint.enabled) continue;
        if (endpoint.kind != BackendEndpointKind.cqrsCommand &&
            endpoint.kind != BackendEndpointKind.cqrsQuery) {
          continue;
        }

        final cqrsBase = _allocateUniqueId(
          raw: endpoint.id,
          used: usedProviderIds,
          fallback: endpoint.kind == BackendEndpointKind.cqrsQuery
              ? 'cqrs_query'
              : 'cqrs_cmd',
          maxLength: 28,
        );
        final inputRepoId = _allocateUniqueId(
          raw: '${cqrsBase}_in',
          used: usedRepoIds,
          fallback: 'cqrs_in',
          maxLength: 32,
        );
        final outputRepoId = _allocateUniqueId(
          raw: '${cqrsBase}_out',
          used: usedRepoIds,
          fallback: 'cqrs_out',
          maxLength: 32,
        );

        final (:normalizedPath, :pathParamKeys) = _normalizeEndpointTemplatePath(
          endpoint.path,
        );
        final fullUrl = '$baseOrigin$normalizedPath';
        final useCase = endpoint.useCaseId != null
            ? project.designSpec.findUseCaseById(endpoint.useCaseId!)
            : null;
        final inputContract = endpoint.inputContractEntryId != null
            ? project.designSpec.findContractById(
                endpoint.inputContractEntryId!,
              )
            : null;
        final outputContract = endpoint.outputContractEntryId != null
            ? project.designSpec.findContractById(
                endpoint.outputContractEntryId!,
              )
            : null;

        final rawLabel = endpoint.summary.trim().isNotEmpty
            ? endpoint.summary.trim()
            : (useCase?.effectiveTitle ?? endpoint.id);
        final providerLabel = _truncateLabel(
          rawLabel,
          maxLength: dataProviderLabelMaxLength,
        );

        final providerMap = <String, Object?>{
          'id': cqrsBase,
          'label': providerLabel,
          'type': 'http',
          'filter': inputRepoId,
          if (endpoint.method != 'DELETE')
            'target': <String, Object?>{
              'repositoryId': outputRepoId,
              'path': 'result',
            },
          'loading': <String, Object?>{
            'repositoryId': outputRepoId,
            'path': 'loading',
          },
          'error': <String, Object?>{
            'repositoryId': outputRepoId,
            'path': 'error',
          },
          'request': <String, Object?>{
            'method': endpoint.method,
            'url': fullUrl,
            'autoParams': true,
          },
        };
        final validatedProvider = HttpProviderConfig.fromJson(providerMap);
        providersJson[validatedProvider.id] = validatedProvider.toJson();

        if (options.includeRepositorySchemasAndSeeds) {
          final rawInputSchema =
              (useCase != null && useCase.inputJsonSchema.isNotEmpty)
              ? useCase.inputJsonSchema
              : (inputContract?.jsonSchema ?? const <String, Object?>{});
          final (:inputDoc, :inputSchema) = _buildCqrsInputRepoAndSchema(
            repoId: inputRepoId,
            label: '$providerLabel (Entrée)',
            sourceSchema: rawInputSchema,
            pathParamKeys: pathParamKeys,
          );
          _putValidatedRepository(
            repoId: inputRepoId,
            document: inputDoc,
            schema: inputSchema,
            repositoriesJson: repositoriesJson,
            repositorySchemasJson: repositorySchemasJson,
          );

          final rawOutputSchema =
              (useCase != null && useCase.outputJsonSchema.isNotEmpty)
              ? useCase.outputJsonSchema
              : (outputContract?.jsonSchema ?? const <String, Object?>{});
          final (:outputDoc, :outputSchema) = _buildCqrsOutputRepoAndSchema(
            repoId: outputRepoId,
            label: '$providerLabel (Résultat)',
            sourceSchema: rawOutputSchema,
          );
          _putValidatedRepository(
            repoId: outputRepoId,
            document: outputDoc,
            schema: outputSchema,
            repositoriesJson: repositoriesJson,
            repositorySchemasJson: repositorySchemasJson,
          );
        }
      }
    }

    return SuperDesignerBridgeExportResult(
      targetDirectoryPath: project.overlay.superDesignerExportPath ?? '',
      providersJson: providersJson,
      datasourcesJson: datasourcesJson,
      repositoriesJson: repositoriesJson,
      repositorySchemasJson: repositorySchemasJson,
    );
  }

  /// Génère le bundle d'intégration et écrit de manière atomique
  /// `providers/<id>.json`, `datasources/<id>.json`,
  /// `repositories/<id>.json` et `repositories/<id>.schema.json` dans
  /// [targetDirectory].
  static Future<SuperDesignerBridgeExportResult> exportToDirectory({
    required Directory targetDirectory,
    required BackendDomainProject project,
    SuperDesignerBridgeOptions options = const SuperDesignerBridgeOptions(),
    Map<String, List<Map<String, Object?>>> existingEntitiesByCollection =
        const <String, List<Map<String, Object?>>>{},
  }) async {
    final bundle = buildBundle(
      project: project,
      options: options,
      existingEntitiesByCollection: existingEntitiesByCollection,
    );

    await targetDirectory.create(recursive: true);
    final sep = Platform.pathSeparator;
    final rootPath = targetDirectory.path.endsWith(sep)
        ? targetDirectory.path.substring(0, targetDirectory.path.length - 1)
        : targetDirectory.path;

    final providerFilesWritten = <String>[];
    if (bundle.providersJson.isNotEmpty) {
      final providersDir = Directory('$rootPath${sep}providers');
      await providersDir.create(recursive: true);
      final sortedIds = bundle.providersJson.keys.toList()..sort();
      for (final id in sortedIds) {
        final file = File('${providersDir.path}$sep$id.json');
        await _writeJsonFileAtomically(file, bundle.providersJson[id]!);
        providerFilesWritten.add(file.path);
      }
    }

    final datasourceFilesWritten = <String>[];
    if (bundle.datasourcesJson.isNotEmpty) {
      final datasourcesDir = Directory('$rootPath${sep}datasources');
      await datasourcesDir.create(recursive: true);
      final sortedIds = bundle.datasourcesJson.keys.toList()..sort();
      for (final id in sortedIds) {
        final file = File('${datasourcesDir.path}$sep$id.json');
        await _writeJsonFileAtomically(file, bundle.datasourcesJson[id]!);
        datasourceFilesWritten.add(file.path);
      }
    }

    final repositoryFilesWritten = <String>[];
    if (bundle.repositoriesJson.isNotEmpty ||
        bundle.repositorySchemasJson.isNotEmpty) {
      final repositoriesDir = Directory('$rootPath${sep}repositories');
      await repositoriesDir.create(recursive: true);
      final sortedRepoIds = bundle.repositoriesJson.keys.toList()..sort();
      for (final id in sortedRepoIds) {
        final dataFile = File('${repositoriesDir.path}$sep$id.json');
        await _writeJsonFileAtomically(dataFile, bundle.repositoriesJson[id]!);
        repositoryFilesWritten.add(dataFile.path);

        final schema = bundle.repositorySchemasJson[id];
        if (schema != null) {
          final schemaFile = File('${repositoriesDir.path}$sep$id.schema.json');
          await _writeJsonFileAtomically(schemaFile, schema);
          repositoryFilesWritten.add(schemaFile.path);
        }
      }
    }

    return bundle.copyWith(
      targetDirectoryPath: targetDirectory.path,
      providerFilesWritten: providerFilesWritten,
      datasourceFilesWritten: datasourceFilesWritten,
      repositoryFilesWritten: repositoryFilesWritten,
    );
  }

  static Future<void> _writeJsonFileAtomically(
    File targetFile,
    Map<String, Object?> payload,
  ) async {
    await targetFile.parent.create(recursive: true);
    final encoded = '${_prettyJson.convert(payload)}\n';
    final random = Random.secure();
    final suffix = List<String>.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final tempFile = File('${targetFile.path}.tmp.$suffix');
    await tempFile.writeAsString(encoded, flush: true);
    try {
      await tempFile.rename(targetFile.path);
    } finally {
      if (await FileSystemEntity.type(tempFile.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await tempFile.delete();
      }
    }
  }

  static String _toSnakeIdentifier(
    String raw, {
    required String fallback,
    required int maxLength,
  }) {
    final splitCamel = raw
        .trim()
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'),
          (m) => '${m[1]}_${m[2]}',
        );
    var normalized = splitCamel
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) {
      normalized = fallback;
    }
    if (normalized.length > maxLength) {
      normalized = normalized
          .substring(0, maxLength)
          .replaceAll(RegExp(r'_+$'), '');
      if (normalized.isEmpty) {
        normalized = fallback.substring(0, min(fallback.length, maxLength));
      }
    }
    return normalized;
  }

  static String _allocateUniqueId({
    required String raw,
    required Set<String> used,
    required String fallback,
    required int maxLength,
  }) {
    final base = _toSnakeIdentifier(
      raw,
      fallback: fallback,
      maxLength: maxLength,
    );
    if (used.add(base)) return base;
    var index = 2;
    while (true) {
      final suffix = '_$index';
      final headMax = max(1, maxLength - suffix.length);
      final head = base.length > headMax
          ? base.substring(0, headMax).replaceAll(RegExp(r'_+$'), '')
          : base;
      final candidate = '${head.isEmpty ? 'id' : head}$suffix';
      if (used.add(candidate)) return candidate;
      index++;
    }
  }

  static String _truncateLabel(String raw, {required int maxLength}) {
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return 'Item';
    if (cleaned.length <= maxLength) return cleaned;
    return '${cleaned.substring(0, maxLength - 1).trimRight()}…';
  }

  static String _sanitizeKeyPath(String rawKey) {
    final trimmed = rawKey.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('@') ||
        _invalidRepoKeyChars.hasMatch(trimmed)) {
      return 'id';
    }
    try {
      final parsed = JsonAttributePath(trimmed)..requireResolved();
      if (parsed.calculated != null) return 'id';
      return parsed.toString();
    } on FormatException {
      return 'id';
    }
  }

  static bool _isSafeRepositoryKey(String key) =>
      key.isNotEmpty &&
      !key.startsWith('@') &&
      !_invalidRepoKeyChars.hasMatch(key);

  static String _sanitizeRepositoryKey(String rawKey) {
    if (_isSafeRepositoryKey(rawKey)) return rawKey;
    final cleaned = rawKey
        .replaceAll(RegExp(r'^@+'), '')
        .replaceAll(_invalidRepoKeyChars, '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'field' : cleaned;
  }

  static Map<String, Object?> _sanitizeRepositoryMap(Map<Object?, Object?> raw) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final rawKey = '${entry.key}'.trim();
      if (rawKey.isEmpty || rawKey.startsWith('@')) continue;
      final key = _sanitizeRepositoryKey(rawKey);
      out[key] = _sanitizeRepositoryValue(entry.value);
    }
    return out;
  }

  static Object? _sanitizeRepositoryValue(Object? value) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) {
      return value.isFinite ? value : 0.0;
    }
    if (value is List) {
      return <Object?>[
        for (final item in value) _sanitizeRepositoryValue(item),
      ];
    }
    if (value is Map) {
      return _sanitizeRepositoryMap(value);
    }
    return '$value';
  }

  static List<String> _extractSortFields(
    ImportedContractEntry? model,
    String keyPath,
  ) {
    final fields = <String>[];
    final seen = <String>{};

    void tryAdd(String candidate, {String? typeHint}) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty || !isValidDatasourceParameter(trimmed)) return;
      if (typeHint != null) {
        final lower = typeHint.toLowerCase();
        if (lower == 'object' || lower == 'array' || lower == 'map') return;
      }
      if (seen.add(trimmed) && fields.length < datasourceMaxSortFields) {
        fields.add(trimmed);
      }
    }

    tryAdd(keyPath);
    if (model != null) {
      final schemaProps = model.jsonSchema['properties'];
      if (schemaProps is Map) {
        for (final entry in schemaProps.entries) {
          final propName = '${entry.key}';
          final propSchema = entry.value;
          String? typeHint;
          if (propSchema is Map && propSchema['type'] is String) {
            typeHint = propSchema['type'] as String;
          }
          tryAdd(propName, typeHint: typeHint);
        }
      }
      for (final attr in model.attributes) {
        final name = (attr['technicalName'] ?? attr['name'])?.toString() ?? '';
        final type = (attr['type'] ?? attr['dataType'])?.toString();
        tryAdd(name, typeHint: type);
      }
    }
    return fields;
  }

  static ({String normalizedPath, List<String> pathParamKeys})
  _normalizeEndpointTemplatePath(String rawPath) {
    final paramKeys = <String>[];
    final seen = <String>{};

    String registerParam(String rawName) {
      final clean = _toSnakeIdentifier(
        rawName,
        fallback: 'id',
        maxLength: 32,
      );
      if (seen.add(clean)) {
        paramKeys.add(clean);
      }
      return '{{$clean}}';
    }

    var normalized = rawPath.trim();
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    normalized = normalized.replaceAllMapped(
      _expressColonParam,
      (m) => registerParam(m.group(1)!),
    );
    normalized = normalized.replaceAllMapped(
      _singleBraceParam,
      (m) => registerParam(m.group(1)!),
    );

    // Détecte aussi d'éventuels placeholders déjà au format `{{param}}`.
    for (final match in RegExp(r'\{\{([^{}]+)\}\}').allMatches(normalized)) {
      final expr = match.group(1)!.trim();
      if (!expr.startsWith('env.') && !expr.startsWith('ds.')) {
        final head = expr.split(RegExp(r'[.\[]')).first.trim();
        if (head.isNotEmpty && seen.add(head)) {
          paramKeys.add(head);
        }
      }
    }

    return (normalizedPath: normalized, pathParamKeys: paramKeys);
  }

  static Map<String, Object?> _extractLocalDefs(Map<String, Object?> schema) {
    final defs = <String, Object?>{};
    for (final defsKey in const <String>[r'$defs', 'definitions']) {
      final rawDefs = schema[defsKey];
      if (rawDefs is Map) {
        for (final entry in rawDefs.entries) {
          final name = '${entry.key}';
          if (entry.value is Map) {
            defs[name] = _sanitizeSubschema(
              entry.value as Map,
              availableDefs: rawDefs.keys.map((e) => '$e').toSet(),
            );
          }
        }
      }
    }
    return defs;
  }

  static Map<String, Object?> _sanitizeSubschema(
    Map<Object?, Object?> rawNode, {
    required Set<String> availableDefs,
    bool relaxRequired = false,
    bool allowNullOnFormattedStrings = false,
  }) {
    final out = <String, Object?>{};
    for (final entry in rawNode.entries) {
      final key = '${entry.key}';
      if (key == r'$schema' ||
          key == r'$id' ||
          key == r'$defs' ||
          key == 'definitions') {
        continue;
      }
      if (relaxRequired && key == 'required') continue;
      if (key == 'additionalProperties') {
        // Préserve l'extensibilité conformément à REPOSITORY_JSON_AI_GUIDE.md.
        out[key] = true;
        continue;
      }
      if (key == r'$ref') {
        final refVal = entry.value;
        if (refVal is String) {
          if (refVal.startsWith(r'#/$defs/')) {
            final target = refVal.substring(r'#/$defs/'.length);
            if (availableDefs.contains(target)) {
              out[r'$ref'] = refVal;
            }
          } else if (refVal.startsWith('#/definitions/')) {
            final target = refVal.substring('#/definitions/'.length);
            if (availableDefs.contains(target)) {
              out[r'$ref'] = '#/${r'$defs'}/$target';
            }
          }
        }
        continue;
      }
      if (key == 'properties' && entry.value is Map) {
        final rawProps = entry.value as Map;
        final sanitizedProps = <String, Object?>{};
        for (final propEntry in rawProps.entries) {
          final propName = '${propEntry.key}';
          if (!_isSafeRepositoryKey(propName)) continue;
          if (propEntry.value is Map) {
            sanitizedProps[propName] = _sanitizeSubschema(
              propEntry.value as Map,
              availableDefs: availableDefs,
              relaxRequired: relaxRequired,
              allowNullOnFormattedStrings: allowNullOnFormattedStrings,
            );
          }
        }
        out['properties'] = sanitizedProps;
        continue;
      }
      if (key == 'items' && entry.value is Map) {
        out['items'] = _sanitizeSubschema(
          entry.value as Map,
          availableDefs: availableDefs,
          relaxRequired: relaxRequired,
          allowNullOnFormattedStrings: allowNullOnFormattedStrings,
        );
        continue;
      }
      out[key] = _sanitizeRepositoryValue(entry.value);
    }

    if (allowNullOnFormattedStrings) {
      final hasFormatOrPattern =
          out.containsKey('format') ||
          out.containsKey('pattern') ||
          (out['minLength'] is int && (out['minLength'] as int) > 0);
      if (hasFormatOrPattern && out['type'] == 'string') {
        out['type'] = <String>['string', 'null'];
      }
      if (out['enum'] is List) {
        final enumList = List<Object?>.of(out['enum'] as List);
        if (!enumList.contains(null) && out['type'] == 'string') {
          out['type'] = <String>['string', 'null'];
          enumList.add(null);
          out['enum'] = enumList;
        }
      }
    }
    return out;
  }

  static Map<String, Object?> _deriveEntityPropertiesFromModel(
    ImportedContractEntry? model,
    String keyField, {
    required Set<String> availableDefs,
    bool relaxConstraints = false,
  }) {
    final props = <String, Object?>{
      keyField: <String, Object?>{'type': 'string', 'default': ''},
    };
    if (model == null) return props;

    final rawSchemaProps = model.jsonSchema['properties'];
    if (rawSchemaProps is Map && rawSchemaProps.isNotEmpty) {
      for (final entry in rawSchemaProps.entries) {
        final propName = '${entry.key}';
        if (!_isSafeRepositoryKey(propName)) continue;
        if (entry.value is Map) {
          props[propName] = _sanitizeSubschema(
            entry.value as Map,
            availableDefs: availableDefs,
            relaxRequired: relaxConstraints,
            allowNullOnFormattedStrings: relaxConstraints,
          );
        }
      }
      return props;
    }

    for (final attr in model.attributes) {
      final rawName =
          (attr['technicalName'] ?? attr['name'])?.toString().trim() ?? '';
      if (!_isSafeRepositoryKey(rawName)) continue;
      final rawType =
          (attr['type'] ?? attr['dataType'])?.toString().toLowerCase() ??
          'string';
      props[rawName] = _attributeTypeToJsonSchema(
        rawType,
        nullable: relaxConstraints || (attr['required'] != true),
      );
    }
    return props;
  }

  static Map<String, Object?> _attributeTypeToJsonSchema(
    String rawType, {
    required bool nullable,
  }) {
    String wrapType(String base) => base;
    List<String> nullableType(String base) => <String>[base, 'null'];

    switch (rawType) {
      case 'int':
      case 'integer':
      case 'long':
        return <String, Object?>{
          'type': nullable ? nullableType('integer') : wrapType('integer'),
          'default': 0,
        };
      case 'double':
      case 'float':
      case 'decimal':
      case 'number':
      case 'money':
        return <String, Object?>{
          'type': nullable ? nullableType('number') : wrapType('number'),
          'default': 0,
        };
      case 'bool':
      case 'boolean':
        return <String, Object?>{
          'type': nullable ? nullableType('boolean') : wrapType('boolean'),
          'default': false,
        };
      case 'date':
        return <String, Object?>{
          'type': nullable ? nullableType('string') : wrapType('string'),
          'format': 'date',
        };
      case 'datetime':
      case 'date-time':
      case 'timestamp':
        return <String, Object?>{
          'type': nullable ? nullableType('string') : wrapType('string'),
          'format': 'date-time',
        };
      case 'uuid':
        return <String, Object?>{
          'type': nullable ? nullableType('string') : wrapType('string'),
          'format': 'uuid',
        };
      case 'email':
        return <String, Object?>{
          'type': nullable ? nullableType('string') : wrapType('string'),
          'format': 'email',
        };
      case 'array':
      case 'list':
        return <String, Object?>{'type': 'array', 'items': <String, Object?>{}};
      case 'object':
      case 'map':
      case 'json':
        return <String, Object?>{
          'type': 'object',
          'additionalProperties': true,
        };
      default:
        return <String, Object?>{
          'type': nullable ? nullableType('string') : wrapType('string'),
          'default': '',
        };
    }
  }

  static Map<String, Object?> _buildCollectionRepoSchema({
    required String repoId,
    required String label,
    required ImportedContractEntry? model,
    required String keyField,
    required Map<String, Object?> document,
  }) {
    final defs = model != null
        ? _extractLocalDefs(model.jsonSchema)
        : const <String, Object?>{};
    final availableDefs = defs.keys.toSet();
    final itemProps = _deriveEntityPropertiesFromModel(
      model,
      keyField,
      availableDefs: availableDefs,
      relaxConstraints: false,
    );
    final selectedProps = _deriveEntityPropertiesFromModel(
      model,
      keyField,
      availableDefs: availableDefs,
      relaxConstraints: true,
    );

    final rawRequired = model?.jsonSchema['required'];
    final itemRequired = <String>[
      if (rawRequired is List)
        for (final req in rawRequired)
          if (req is String && itemProps.containsKey(req)) req,
    ];

    final candidate = <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'title': '$label (Repository)',
      'type': 'object',
      if (defs.isNotEmpty) r'$defs': defs,
      'required': <String>[
        'items',
        'selectedItem',
        'total',
        'loading',
        'error',
      ],
      'properties': <String, Object?>{
        'items': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{
            'type': 'object',
            'properties': itemProps,
            if (itemRequired.isNotEmpty) 'required': itemRequired,
            'additionalProperties': true,
          },
        },
        'selectedItem': <String, Object?>{
          'type': 'object',
          'properties': selectedProps,
          'additionalProperties': true,
        },
        'total': <String, Object?>{
          'type': 'integer',
          'minimum': 0,
          'default': 0,
        },
        'loading': <String, Object?>{'type': 'boolean', 'default': false},
        'error': <String, Object?>{'type': 'string', 'default': ''},
        'pageState': <String, Object?>{
          'type': 'object',
          'additionalProperties': true,
        },
      },
      'additionalProperties': true,
    };

    return _ensureValidSchemaForDocument(
      repoId: repoId,
      document: document,
      candidateSchema: candidate,
      fallbackTitle: '$label (Repository)',
    );
  }

  static ({Map<String, Object?> filterDoc, Map<String, Object?> filterSchema})
  _buildFilterRepoAndSchema({
    required String repoId,
    required String label,
    required ImportedContractEntry? model,
  }) {
    final filterDoc = <String, Object?>{'q': ''};
    final filterProps = <String, Object?>{
      'q': <String, Object?>{
        'type': 'string',
        'default': '',
        'description': 'Recherche plein texte',
      },
    };

    if (model != null) {
      final rawProps = model.jsonSchema['properties'];
      if (rawProps is Map) {
        for (final entry in rawProps.entries) {
          final key = '${entry.key}';
          if (key == 'q' || !_isSafeRepositoryKey(key)) continue;
          final prop = entry.value;
          if (prop is! Map) continue;
          if (prop['enum'] is List && (prop['enum'] as List).isNotEmpty) {
            final values = <Object?>[
              '',
              for (final v in prop['enum'] as List)
                if (v != '') v,
            ];
            filterDoc[key] = '';
            filterProps[key] = <String, Object?>{
              'type': 'string',
              'enum': values,
              'default': '',
            };
          }
        }
      }
    }

    final candidateSchema = <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'title': '$label (Filtre)',
      'type': 'object',
      'properties': filterProps,
      'additionalProperties': true,
    };
    final validSchema = _ensureValidSchemaForDocument(
      repoId: repoId,
      document: filterDoc,
      candidateSchema: candidateSchema,
      fallbackTitle: '$label (Filtre)',
    );
    return (filterDoc: filterDoc, filterSchema: validSchema);
  }

  static ({Map<String, Object?> formDoc, Map<String, Object?> formSchema})
  _buildFormRepoAndSchema({
    required String repoId,
    required String label,
    required ImportedContractEntry? model,
    required String keyField,
  }) {
    final defs = model != null
        ? _extractLocalDefs(model.jsonSchema)
        : const <String, Object?>{};
    final formProps = _deriveEntityPropertiesFromModel(
      model,
      keyField,
      availableDefs: defs.keys.toSet(),
      relaxConstraints: true,
    );
    final formDoc = _buildInitialObjectFromProperties(formProps);

    final candidateSchema = <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'title': '$label (Formulaire)',
      'type': 'object',
      if (defs.isNotEmpty) r'$defs': defs,
      'properties': formProps,
      'additionalProperties': true,
    };
    final validSchema = _ensureValidSchemaForDocument(
      repoId: repoId,
      document: formDoc,
      candidateSchema: candidateSchema,
      fallbackTitle: '$label (Formulaire)',
    );
    return (formDoc: formDoc, formSchema: validSchema);
  }

  static ({Map<String, Object?> inputDoc, Map<String, Object?> inputSchema})
  _buildCqrsInputRepoAndSchema({
    required String repoId,
    required String label,
    required Map<String, Object?> sourceSchema,
    required List<String> pathParamKeys,
  }) {
    final defs = _extractLocalDefs(sourceSchema);
    final props = <String, Object?>{};
    for (final param in pathParamKeys) {
      if (_isSafeRepositoryKey(param)) {
        props[param] = <String, Object?>{'type': 'string', 'default': ''};
      }
    }
    final rawProps = sourceSchema['properties'];
    if (rawProps is Map) {
      for (final entry in rawProps.entries) {
        final key = '${entry.key}';
        if (!_isSafeRepositoryKey(key) || entry.value is! Map) continue;
        props[key] = _sanitizeSubschema(
          entry.value as Map,
          availableDefs: defs.keys.toSet(),
          relaxRequired: true,
          allowNullOnFormattedStrings: true,
        );
      }
    }
    final inputDoc = _buildInitialObjectFromProperties(props);
    final candidateSchema = <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'title': label,
      'type': 'object',
      if (defs.isNotEmpty) r'$defs': defs,
      'properties': props,
      'additionalProperties': true,
    };
    final validSchema = _ensureValidSchemaForDocument(
      repoId: repoId,
      document: inputDoc,
      candidateSchema: candidateSchema,
      fallbackTitle: label,
    );
    return (inputDoc: inputDoc, inputSchema: validSchema);
  }

  static ({Map<String, Object?> outputDoc, Map<String, Object?> outputSchema})
  _buildCqrsOutputRepoAndSchema({
    required String repoId,
    required String label,
    required Map<String, Object?> sourceSchema,
  }) {
    final defs = _extractLocalDefs(sourceSchema);
    final isArrayResult = sourceSchema['type'] == 'array';
    final Object initialResult = isArrayResult
        ? <Object?>[]
        : <String, Object?>{};

    final Map<String, Object?> resultSubschema;
    if (sourceSchema.isNotEmpty) {
      final sanitized = _sanitizeSubschema(
        sourceSchema,
        availableDefs: defs.keys.toSet(),
        relaxRequired: true,
        allowNullOnFormattedStrings: true,
      );
      resultSubschema = sanitized.isNotEmpty
          ? sanitized
          : <String, Object?>{
              'type': <String>['object', 'array', 'null'],
              'additionalProperties': true,
            };
    } else {
      resultSubschema = <String, Object?>{
        'type': <String>['object', 'array', 'null'],
        'additionalProperties': true,
      };
    }

    final outputDoc = <String, Object?>{
      'result': initialResult,
      'loading': false,
      'error': '',
    };
    final candidateSchema = <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'title': label,
      'type': 'object',
      if (defs.isNotEmpty) r'$defs': defs,
      'required': <String>['result', 'loading', 'error'],
      'properties': <String, Object?>{
        'result': resultSubschema,
        'loading': <String, Object?>{'type': 'boolean', 'default': false},
        'error': <String, Object?>{'type': 'string', 'default': ''},
      },
      'additionalProperties': true,
    };
    final validSchema = _ensureValidSchemaForDocument(
      repoId: repoId,
      document: outputDoc,
      candidateSchema: candidateSchema,
      fallbackTitle: label,
    );
    return (outputDoc: outputDoc, outputSchema: validSchema);
  }

  static Map<String, Object?> _buildInitialObjectFromProperties(
    Map<String, Object?> properties,
  ) {
    final doc = <String, Object?>{};
    for (final entry in properties.entries) {
      if (!_isSafeRepositoryKey(entry.key)) continue;
      final propSchema = entry.value;
      if (propSchema is Map<String, Object?>) {
        doc[entry.key] = _initialValueForProperty(propSchema);
      } else {
        doc[entry.key] = '';
      }
    }
    return doc;
  }

  static Object? _initialValueForProperty(Map<String, Object?> propSchema) {
    if (propSchema.containsKey('default')) {
      return _sanitizeRepositoryValue(propSchema['default']);
    }
    if (propSchema['enum'] case final List enumValues
        when enumValues.isNotEmpty) {
      return _sanitizeRepositoryValue(enumValues.first);
    }
    final rawType = propSchema['type'];
    final types = switch (rawType) {
      String s => <String>[s],
      List l => <String>[for (final t in l) '$t'],
      _ => const <String>[],
    };
    if (types.contains('null') &&
        (propSchema.containsKey('format') ||
            propSchema.containsKey('pattern'))) {
      return null;
    }
    if (types.contains('boolean')) return false;
    if (types.contains('integer')) {
      final minVal = propSchema['minimum'];
      return (minVal is int && minVal > 0) ? minVal : 0;
    }
    if (types.contains('number')) {
      final minVal = propSchema['minimum'];
      return (minVal is num && minVal > 0) ? minVal : 0;
    }
    if (types.contains('array')) return <Object?>[];
    if (types.contains('object')) {
      final nested = propSchema['properties'];
      if (nested is Map<String, Object?>) {
        return _buildInitialObjectFromProperties(nested);
      }
      return <String, Object?>{};
    }
    if (types.contains('null')) return null;
    return '';
  }

  static Map<String, Object?> _ensureValidSchemaForDocument({
    required String repoId,
    required Map<String, Object?> document,
    required Map<String, Object?> candidateSchema,
    required String fallbackTitle,
  }) {
    try {
      final normalized = JsonSchemaValidator.validateSchemaDefinition(
        candidateSchema,
      );
      final check = JsonSchemaValidator.validate(document, normalized);
      if (check.isValid) {
        return normalized;
      }
    } on FormatException {
      // Replie proprement sur un schéma inféré garanti valide.
    }
    final inferred = JsonSchemaValidator.inferSchema(
      document,
      title: fallbackTitle,
    );
    JsonSchemaValidator.assertValid(
      repositoryId: repoId,
      document: document,
      schema: inferred,
    );
    return inferred;
  }

  static void _putValidatedRepository({
    required String repoId,
    required Map<String, Object?> document,
    required Map<String, Object?> schema,
    required Map<String, Map<String, Object?>> repositoriesJson,
    required Map<String, Map<String, Object?>> repositorySchemasJson,
  }) {
    JsonSchemaValidator.assertValid(
      repositoryId: repoId,
      document: document,
      schema: schema,
    );
    repositoriesJson[repoId] = freezeJsonMap(document);
    repositorySchemasJson[repoId] = freezeJsonMap(schema);
  }
}
