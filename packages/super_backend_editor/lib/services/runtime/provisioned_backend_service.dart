/// Service d'exécution SCRUD provisionné au-dessus de [SuperBackend] intégrant
/// les politiques métier ([BackendOverlayConfig]), la validation JSON Schema
/// Draft 2020-12 ([JsonSchemaPayloadValidator]), les hooks d'invariants et un
/// générateur déterministe de données d'amorçage conformes aux contrats.
library;

import 'dart:convert';

import 'package:super_backend/super_backend.dart';
import 'package:uuid/uuid.dart';

import '../../models/backend_domain_project.dart';
import '../../models/backend_overlay_config.dart';
import '../../models/domain_design_spec.dart';
import '../../models/json_value_utils.dart';
import '../validation/json_schema_payload_validator.dart';

const Uuid _seedUuid = Uuid();

final RegExp _scrudFieldPathPattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
);

/// Hook asynchrone optionnel permettant au moteur d'invariants (ex. QuickJS)
/// de valider une entité lors d'une opération `'create'` ou `'update'`.
typedef CollectionInvariantHook =
    Future<void> Function({
      required BackendCollectionConfig collection,
      required ImportedContractEntry? contract,
      required Map<String, Object?> entity,
      required String operation,
    });

/// Exception levée lorsqu'une collection ciblée est absente de l'overlay ou
/// désactivée (`enabled == false`).
class CollectionDisabledOrUnknownException extends SuperBackendException {
  /// Crée une exception pour [collectionName].
  const CollectionDisabledOrUnknownException({
    required this.collectionName,
    this.isDisabled = false,
  }) : super(
         code: isDisabled ? 'collection_disabled' : 'collection_unknown',
         message: isDisabled
             ? 'La collection « $collectionName » est désactivée dans la configuration Backend.'
             : 'La collection « $collectionName » est inconnue dans la configuration Backend.',
         statusCode: isDisabled ? 403 : 404,
       );

  /// Nom ou identifiant de la collection demandée.
  final String collectionName;

  /// Vrai lorsque la collection existe dans l'overlay mais est désactivée.
  final bool isDisabled;
}

/// Exception levée lors d'un conflit de concurrence optimiste sur le numéro de
/// version d'une entité (équivalent HTTP 409 Conflict).
class OptimisticConcurrencyException extends SuperBackendException {
  /// Crée une exception de conflit de version optimiste.
  const OptimisticConcurrencyException({
    required this.collection,
    required this.entityId,
    required this.expectedVersion,
    required this.actualVersion,
  }) : super(
         code: 'optimistic_concurrency_conflict',
         message:
             'Conflit de concurrence optimiste sur « $collection/$entityId » : '
             'version attendue $expectedVersion, version courante $actualVersion.',
         statusCode: 409,
       );

  /// Nom de la collection concernée.
  final String collection;

  /// Identifiant de l'entité en conflit.
  final String entityId;

  /// Version attendue par l'appelant.
  final int expectedVersion;

  /// Version courante stockée.
  final int actualVersion;
}

/// Exception levée lorsqu'une suppression est refusée car la collection est en
/// mode [BackendDeletionMode.immutableArchive].
class ImmutableCollectionArchiveException extends SuperBackendException {
  /// Crée une exception d'interdiction de suppression sur [collection].
  const ImmutableCollectionArchiveException({
    required this.collection,
    this.entityId,
  }) : super(
         code: 'immutable_collection_archive',
         message:
             'Suppression interdite : la collection « $collection » est configurée '
             'en archivage immuable.',
         statusCode: 409,
       );

  /// Collection protégée contre la suppression.
  final String collection;

  /// Identifiant optionnel de l'entité visée.
  final String? entityId;
}

/// Service SCRUD provisionné enveloppant [SuperBackend] avec la connaissance
/// de [DomainDesignSpec] et les politiques d'exécution de [BackendOverlayConfig].
class ProvisionedBackendService {
  /// Crée un service provisionné au-dessus de [backend].
  ProvisionedBackendService({
    required this.backend,
    required DomainDesignSpec designSpec,
    required this._overlay,
    this._invariantHook,
    JsonSchemaPayloadValidator? validator,
  }) : _designSpec = designSpec,
       _validator =
           validator ?? JsonSchemaPayloadValidator.fromDesignSpec(designSpec);

  /// Construit un service adossé à une base SQLite en mémoire (`:memory:`) ou
  /// un [MemoryCollectionStore].
  factory ProvisionedBackendService.inMemory({
    required DomainDesignSpec designSpec,
    BackendOverlayConfig? overlay,
    CollectionInvariantHook? invariantHook,
    bool useSqlite = true,
    String Function()? idGenerator,
  }) => ProvisionedBackendService(
    backend: SuperBackend(
      store: useSqlite
          ? SqliteCollectionStore.inMemory()
          : MemoryCollectionStore(),
      idGenerator: idGenerator,
    ),
    designSpec: designSpec,
    overlay: overlay ?? BackendOverlayConfig.bootstrapFromDesign(designSpec),
    invariantHook: invariantHook,
  );

  /// Construit un service adossé à un fichier SQLite local [databasePath].
  factory ProvisionedBackendService.sqliteFile({
    required String databasePath,
    required DomainDesignSpec designSpec,
    BackendOverlayConfig? overlay,
    CollectionInvariantHook? invariantHook,
    String Function()? idGenerator,
  }) => ProvisionedBackendService(
    backend: SuperBackend(
      store: SqliteCollectionStore(databasePath),
      idGenerator: idGenerator,
    ),
    designSpec: designSpec,
    overlay: overlay ?? BackendOverlayConfig.bootstrapFromDesign(designSpec),
    invariantHook: invariantHook,
  );

  /// Construit un service à partir d'un [BackendDomainProject] complet.
  factory ProvisionedBackendService.fromProject(
    BackendDomainProject project, {
    required SuperBackend backend,
    CollectionInvariantHook? invariantHook,
  }) => ProvisionedBackendService(
    backend: backend,
    designSpec: project.designSpec,
    overlay: project.overlay,
    invariantHook: invariantHook,
  );

  /// Moteur SCRUD bas niveau sous-jacent (`SqliteCollectionStore` ou mémoire).
  final SuperBackend backend;

  DomainDesignSpec _designSpec;
  BackendOverlayConfig _overlay;
  CollectionInvariantHook? _invariantHook;
  JsonSchemaPayloadValidator _validator;

  /// Spécification Design courante du domaine.
  DomainDesignSpec get designSpec => _designSpec;

  /// Configuration d'overlay Backend active.
  BackendOverlayConfig get overlay => _overlay;

  /// Hook optionnel de vérification des invariants métier.
  CollectionInvariantHook? get invariantHook => _invariantHook;

  /// Validateur JSON Schema actif lié aux Value Objects de [designSpec].
  JsonSchemaPayloadValidator get validator => _validator;

  /// Recharge à chaud la spécification Design, l'overlay ou le hook d'invariants
  /// sans réouvrir la connexion SQLite sous-jacente.
  void updateConfiguration({
    DomainDesignSpec? designSpec,
    BackendOverlayConfig? overlay,
    CollectionInvariantHook? invariantHook,
    bool clearInvariantHook = false,
  }) {
    if (designSpec != null) {
      _designSpec = designSpec;
      _validator = JsonSchemaPayloadValidator.fromDesignSpec(designSpec);
    }
    if (overlay != null) {
      _overlay = overlay;
    }
    if (clearInvariantHook) {
      _invariantHook = null;
    } else if (invariantHook != null) {
      _invariantHook = invariantHook;
    }
  }

  /// Initialise le store sous-jacent de [backend].
  Future<void> init() => backend.init();

  /// Ferme le store sous-jacent de [backend].
  Future<void> close() => backend.close();

  /// Recherche une [BackendCollectionConfig] par son `collectionName`, son `id`
  /// ou son `contractEntryId`.
  BackendCollectionConfig? findCollection(String collectionNameOrId) {
    final needle = collectionNameOrId.trim();
    if (needle.isEmpty) return null;
    return _overlay.findCollectionByName(needle) ??
        _overlay.findCollectionById(needle) ??
        _overlay.findCollectionForContract(needle);
  }

  /// Résout l'entrée de contrat [ImportedContractEntry] associée à [col].
  ImportedContractEntry? contractForCollection(BackendCollectionConfig col) {
    final contractId = col.contractEntryId?.trim();
    if (contractId != null && contractId.isNotEmpty) {
      final byContractId = _designSpec.findContractById(contractId);
      if (byContractId != null) return byContractId;
    }
    return _designSpec.findContractById(col.id);
  }

  /// Recherche paginée, triée et filtrée dans [collectionName] en appliquant
  /// automatiquement le filtrage `softDelete` lorsque [includeSoftDeleted] vaut `false`.
  Future<ScrudSearchResult> search(
    String collectionName, {
    ScrudSearchRequest? request,
    Map<String, Object?>? parameters,
    bool includeSoftDeleted = false,
  }) async {
    final col = _requireActiveCollection(collectionName);
    if (request != null && parameters != null) {
      throw const InvalidQueryException(
        'Fournir soit « request », soit « parameters », mais pas les deux.',
      );
    }
    final baseRequest =
        request ??
        (parameters != null
            ? ScrudSearchRequest.fromParameters(parameters)
            : ScrudSearchRequest());
    baseRequest.validate();

    if (col.deletionMode == BackendDeletionMode.softDelete &&
        !includeSoftDeleted) {
      if (_isValidScrudFieldPath(col.softDeleteField)) {
        final effectiveFilters = <ScrudFilter>[
          ...baseRequest.filters,
          ScrudFilter(
            field: col.softDeleteField,
            operator: ScrudFilterOperator.isNull,
          ),
        ];
        return backend.search(
          col.collectionName,
          request: baseRequest.copyWith(filters: effectiveFilters),
        );
      }
      return _searchFilteringSoftDeletedInMemory(col, baseRequest);
    }

    return backend.search(col.collectionName, request: baseRequest);
  }

  /// Crée une nouvelle entité dans [collectionName] après application des
  /// politiques de version, `softDelete`, validation JSON Schema et invariants.
  Future<Map<String, Object?>> create(
    String collectionName,
    Map<String, Object?> data, {
    String? id,
    bool upsert = false,
    bool skipValidation = false,
  }) async {
    final col = _requireActiveCollection(collectionName);
    final working = _cloneMutableMap(data);
    final contract = contractForCollection(col);

    String? resolvedId = _nonEmptyString(id) ?? _nonEmptyString(working[col.keyField]);
    if (resolvedId == null && backend.keyField != null) {
      resolvedId = _nonEmptyString(working[backend.keyField!]);
    }
    if (resolvedId == null &&
        contract != null &&
        _schemaRequiresProperty(contract.jsonSchema, col.keyField)) {
      resolvedId = _seedUuid.v4();
    }
    if (resolvedId != null) {
      working[col.keyField] = resolvedId;
    }

    if (col.concurrencyMode == BackendConcurrencyMode.optimisticVersion) {
      final rawVersion = working[col.versionField];
      working[col.versionField] = rawVersion is int ? rawVersion : 1;
    }

    if (col.deletionMode == BackendDeletionMode.softDelete &&
        !data.containsKey(col.softDeleteField)) {
      working.remove(col.softDeleteField);
    }

    _validateEntityIfEnabled(
      col: col,
      contract: contract,
      entity: working,
      skipValidation: skipValidation,
    );

    final hook = _invariantHook;
    if (hook != null) {
      await hook(
        collection: col,
        contract: contract,
        entity: freezeJsonMap(working),
        operation: 'create',
      );
    }

    final created = await backend.create(
      col.collectionName,
      working,
      id: resolvedId,
      upsert: upsert,
    );

    if (col.keyField != backend.keyField && !created.containsKey(col.keyField)) {
      final effectiveId =
          resolvedId ?? _nonEmptyString(created[backend.keyField ?? 'id']);
      if (effectiveId != null) {
        final withCustomKey = <String, Object?>{
          ...created,
          col.keyField: effectiveId,
        };
        return backend.update(
          col.collectionName,
          effectiveId,
          withCustomKey,
          merge: false,
        );
      }
    }
    return created;
  }

  /// Lit l'entité [id] de [collectionName] (lève [EntityNotFoundException] si
  /// absente ou supprimée logiquement lorsque [includeSoftDeleted] vaut `false`).
  Future<Map<String, Object?>> read(
    String collectionName,
    String id, {
    bool includeSoftDeleted = false,
  }) async {
    final col = _requireActiveCollection(collectionName);
    final entity = await backend.read(col.collectionName, id);
    if (col.deletionMode == BackendDeletionMode.softDelete &&
        !includeSoftDeleted &&
        entity[col.softDeleteField] != null) {
      throw EntityNotFoundException(
        collection: col.collectionName,
        entityId: id,
      );
    }
    return entity;
  }

  /// Met à jour l'entité [id] de [collectionName] avec contrôle de concurrence
  /// optimiste, fusion, validation complète du schéma et hook d'invariants.
  Future<Map<String, Object?>> update(
    String collectionName,
    String id,
    Map<String, Object?> changes, {
    bool merge = true,
    int? expectedVersion,
    bool skipValidation = false,
  }) async {
    final col = _requireActiveCollection(collectionName);
    final current = await read(col.collectionName, id);
    final contract = contractForCollection(col);

    int? nextVersion;
    if (col.concurrencyMode == BackendConcurrencyMode.optimisticVersion) {
      final rawCurrentVer = current[col.versionField];
      final currentVersion = switch (rawCurrentVer) {
        int v => v,
        num n => n.toInt(),
        _ => 1,
      };
      final rawChangeVer = changes[col.versionField];
      final changeVersion = switch (rawChangeVer) {
        int v => v,
        num n => n.toInt(),
        _ => null,
      };
      final effectiveExpected = expectedVersion ?? changeVersion;
      if (effectiveExpected != null && effectiveExpected != currentVersion) {
        throw OptimisticConcurrencyException(
          collection: col.collectionName,
          entityId: id,
          expectedVersion: effectiveExpected,
          actualVersion: currentVersion,
        );
      }
      nextVersion = currentVersion + 1;
    }

    final normalizedChanges = _cloneMutableMap(changes);
    final Map<String, Object?> nextPayload = merge
        ? <String, Object?>{
            ..._cloneMutableMap(current),
            ...normalizedChanges,
          }
        : <String, Object?>{...normalizedChanges};

    nextPayload[col.keyField] = id;
    if (backend.keyField != null) {
      nextPayload[backend.keyField!] = id;
    }
    if (nextVersion != null) {
      nextPayload[col.versionField] = nextVersion;
    }

    _validateEntityIfEnabled(
      col: col,
      contract: contract,
      entity: nextPayload,
      skipValidation: skipValidation,
    );

    final hook = _invariantHook;
    if (hook != null) {
      await hook(
        collection: col,
        contract: contract,
        entity: freezeJsonMap(nextPayload),
        operation: 'update',
      );
    }

    return backend.update(col.collectionName, id, nextPayload, merge: false);
  }

  /// Supprime l'entité [id] de [collectionName] selon la politique
  /// [BackendCollectionConfig.deletionMode] (`hard: true` force la suppression physique).
  Future<bool> delete(
    String collectionName,
    String id, {
    bool hard = false,
  }) async {
    final col = _requireActiveCollection(collectionName);
    if (col.deletionMode == BackendDeletionMode.immutableArchive && !hard) {
      throw ImmutableCollectionArchiveException(
        collection: col.collectionName,
        entityId: id,
      );
    }
    if (col.deletionMode == BackendDeletionMode.softDelete && !hard) {
      await read(col.collectionName, id);
      await backend.update(
        col.collectionName,
        id,
        <String, Object?>{
          col.softDeleteField: DateTime.now().toUtc().toIso8601String(),
        },
        merge: true,
      );
      return true;
    }
    await backend.delete(col.collectionName, id);
    return true;
  }

  /// Calcule le nombre d'entités par `collectionName` pour toutes les
  /// collections déclarées dans [overlay].
  Future<Map<String, int>> collectionRowCounts({
    bool includeSoftDeleted = false,
  }) async {
    final counts = <String, int>{};
    for (final col in _overlay.collections) {
      if (col.deletionMode == BackendDeletionMode.softDelete &&
          !includeSoftDeleted) {
        if (_isValidScrudFieldPath(col.softDeleteField)) {
          final page = await backend.search(
            col.collectionName,
            request: ScrudSearchRequest(
              pagination: const ScrudPagination(pageSize: 1),
              filters: <ScrudFilter>[
                ScrudFilter(
                  field: col.softDeleteField,
                  operator: ScrudFilterOperator.isNull,
                ),
              ],
            ),
          );
          counts[col.collectionName] = page.total;
        } else {
          final page = await _searchFilteringSoftDeletedInMemory(
            col,
            ScrudSearchRequest(pagination: const ScrudPagination(pageSize: 1)),
          );
          counts[col.collectionName] = page.total;
        }
      } else {
        counts[col.collectionName] = await backend.count(col.collectionName);
      }
    }
    return Map<String, int>.unmodifiable(counts);
  }

  /// Génère de manière déterministe une entité JSON réaliste et conforme au
  /// `jsonSchema` et à l'`objectSpecJson` de [contract] pour l'indice [index].
  Map<String, Object?> generateSampleEntity(
    ImportedContractEntry contract, {
    int index = 1,
  }) {
    final safeIndex = index < 1 ? 1 : index;
    final col = _overlay.findCollectionForContract(contract.entryId);
    final keyField = col?.keyField ?? backend.keyField ?? 'id';
    final softDeleteField = col?.softDeleteField ?? 'deletedAt';
    final versionField = col?.versionField ?? 'version';

    final attrByName = <String, Map<String, Object?>>{};
    for (final attr in contract.attributes) {
      final name = (attr['name'] as String?)?.trim() ?? '';
      if (name.isNotEmpty) attrByName[name] = attr;
    }
    for (final rel in contract.relations) {
      final name = (rel['name'] as String?)?.trim() ?? '';
      if (name.isNotEmpty && !attrByName.containsKey(name)) {
        final card = (rel['cardinality'] as String?)?.trim() ?? '1:1';
        final isMany =
            card == 'oneToMany' ||
            card == 'manyToMany' ||
            card == '1:N' ||
            card == 'N:M';
        attrByName[name] = <String, Object?>{
          'name': name,
          'type': 'uuid',
          'isArray': isMany,
        };
      }
    }

    final lifecycleCodes = <String>[
      for (final st in contract.lifecycleStates)
        if ((st['code'] ?? st['name']) is String &&
            '${st['code'] ?? st['name']}'.trim().isNotEmpty)
          '${st['code'] ?? st['name']}'.trim(),
    ];

    final rootSchema = contract.jsonSchema;
    final generated = <String, Object?>{};

    if (rootSchema.isNotEmpty) {
      final built = _generateForSchemaNode(
        schemaNode: rootSchema,
        rootSchema: rootSchema,
        attrSpec: null,
        rootAttrByName: attrByName,
        lifecycleCodes: lifecycleCodes,
        propName: contract.technicalName,
        index: safeIndex,
        depth: 0,
        softDeleteField: softDeleteField,
      );
      if (built is Map) {
        for (final entry in built.entries) {
          generated['${entry.key}'] = entry.value;
        }
      }
      final disallowAdditional =
          _effectiveAdditionalPropertiesFalse(rootSchema, rootSchema);
      if (!disallowAdditional && generated.isEmpty) {
        _populateFromObjectSpecAttributes(
          target: generated,
          attrByName: attrByName,
          lifecycleCodes: lifecycleCodes,
          index: safeIndex,
          softDeleteField: softDeleteField,
        );
      }
    } else {
      _populateFromObjectSpecAttributes(
        target: generated,
        attrByName: attrByName,
        lifecycleCodes: lifecycleCodes,
        index: safeIndex,
        softDeleteField: softDeleteField,
      );
    }

    if (!generated.containsKey(keyField) || generated[keyField] == null) {
      final keyPropSchema = _findRootPropertySchema(rootSchema, keyField);
      if (keyPropSchema != null) {
        generated[keyField] = _generateForSchemaNode(
          schemaNode: keyPropSchema,
          rootSchema: rootSchema,
          attrSpec: attrByName[keyField],
          rootAttrByName: const <String, Map<String, Object?>>{},
          lifecycleCodes: lifecycleCodes,
          propName: keyField,
          index: safeIndex,
          depth: 1,
          softDeleteField: softDeleteField,
        );
      } else {
        generated[keyField] = _deterministicUuid(safeIndex);
      }
    }

    if (col?.concurrencyMode == BackendConcurrencyMode.optimisticVersion &&
        !generated.containsKey(versionField)) {
      generated[versionField] = 1;
    }

    if (!_schemaRequiresProperty(rootSchema, softDeleteField)) {
      generated.remove(softDeleteField);
    }

    return freezeJsonMap(generated);
  }

  /// Génère et insère [count] entités d'amorçage valides dans [collectionName]
  /// via [create] afin de garantir leur conformité stricte au schéma et aux politiques.
  Future<List<Map<String, Object?>>> seedCollection(
    String collectionName, {
    int count = 5,
    bool clearExisting = false,
  }) async {
    final col = _requireActiveCollection(collectionName);
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'count doit être positif ou nul.');
    }
    if (clearExisting) {
      await backend.clearCollection(col.collectionName);
    }
    if (count == 0) return const <Map<String, Object?>>[];

    final existingCount = clearExisting
        ? 0
        : await backend.count(col.collectionName);
    final contract = contractForCollection(col);
    final createdItems = <Map<String, Object?>>[];

    for (var i = 1; i <= count; i++) {
      final sampleIndex = existingCount + i;
      final Map<String, Object?> sample;
      if (contract != null) {
        sample = generateSampleEntity(contract, index: sampleIndex);
      } else {
        sample = <String, Object?>{
          col.keyField: _deterministicUuid(sampleIndex),
          'label': '${col.label} #$sampleIndex',
          'index': sampleIndex,
        };
      }
      final created = await create(col.collectionName, sample);
      createdItems.add(created);
    }

    return List<Map<String, Object?>>.unmodifiable(createdItems);
  }

  BackendCollectionConfig _requireActiveCollection(String collectionNameOrId) {
    final col = findCollection(collectionNameOrId);
    if (col == null) {
      throw CollectionDisabledOrUnknownException(
        collectionName: collectionNameOrId,
      );
    }
    if (!col.enabled) {
      throw CollectionDisabledOrUnknownException(
        collectionName: col.collectionName,
        isDisabled: true,
      );
    }
    return col;
  }

  void _validateEntityIfEnabled({
    required BackendCollectionConfig col,
    required ImportedContractEntry? contract,
    required Map<String, Object?> entity,
    required bool skipValidation,
  }) {
    if (!col.strictSchemaValidation ||
        skipValidation ||
        contract == null ||
        contract.jsonSchema.isNotEmpty == false) {
      return;
    }
    final systemFields = <String>{
      ...JsonSchemaPayloadValidator.defaultSystemFields,
      col.keyField,
      col.versionField,
      col.softDeleteField,
    };
    final result = _validator.validate(
      entity,
      contract.jsonSchema,
      allowSystemFields: true,
      systemFields: systemFields,
    );
    result.throwIfInvalid();
  }

  Future<ScrudSearchResult> _searchFilteringSoftDeletedInMemory(
    BackendCollectionConfig col,
    ScrudSearchRequest request,
  ) async {
    final allActive = <Map<String, Object?>>[];
    var currentOffset = 0;
    const batchSize = ScrudPagination.maxPageSize;

    while (true) {
      final page = await backend.search(
        col.collectionName,
        request: request.copyWith(
          pagination: ScrudPagination(
            mode: ScrudPaginationMode.offset,
            offset: currentOffset,
            pageSize: batchSize,
          ),
        ),
      );
      for (final item in page.items) {
        if (item[col.softDeleteField] == null) {
          allActive.add(item);
        }
      }
      currentOffset += page.items.length;
      if (!page.hasNext || page.items.isEmpty) break;
    }

    final total = allActive.length;
    final offset = request.pagination.effectiveOffset;
    final pageSize = request.pagination.pageSize;
    final slice = offset >= total
        ? const <Map<String, Object?>>[]
        : allActive
              .skip(offset)
              .take(pageSize)
              .toList(growable: false);
    final hasNext = offset + slice.length < total;
    final hasPrevious = offset > 0;
    return ScrudSearchResult(
      items: slice,
      total: total,
      page: request.pagination.normalizedPageNumber,
      pageSize: pageSize,
      offset: offset,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
      nextCursor: hasNext
          ? ScrudPagination.encodeCursorOffset(offset + slice.length)
          : null,
      sort: request.sort,
    );
  }

  void _populateFromObjectSpecAttributes({
    required Map<String, Object?> target,
    required Map<String, Map<String, Object?>> attrByName,
    required List<String> lifecycleCodes,
    required int index,
    required String softDeleteField,
  }) {
    for (final entry in attrByName.entries) {
      final fieldName = entry.key;
      if (fieldName == softDeleteField) continue;
      final attr = entry.value;
      final synthSchema = _synthesizeAttributeSchemaForSeed(attr);
      target[fieldName] = _generateForSchemaNode(
        schemaNode: synthSchema,
        rootSchema: synthSchema,
        attrSpec: attr,
        rootAttrByName: const <String, Map<String, Object?>>{},
        lifecycleCodes: lifecycleCodes,
        propName: fieldName,
        index: index,
        depth: 1,
        softDeleteField: softDeleteField,
      );
    }
  }

  Map<String, Object?> _synthesizeAttributeSchemaForSeed(
    Map<String, Object?> attr,
  ) {
    final rawType = (attr['type'] as String?)?.trim().toLowerCase() ?? 'string';
    final isArray = attr['isArray'] == true;
    Map<String, Object?> base;
    if ((rawType == 'vo' ||
            rawType == 'valueobject' ||
            rawType == 'value_object' ||
            rawType == 'value-object') &&
        attr['valueObjectId'] is String) {
      final vo = _designSpec.findValueObjectByName(
        attr['valueObjectId'] as String,
      );
      if (vo != null) {
        base = JsonSchemaPayloadValidator.synthesizeValueObjectSchema(vo);
      } else {
        base = const <String, Object?>{'type': 'string'};
      }
    } else if (rawType == 'object' ||
        rawType == 'subobject' ||
        rawType == 'struct') {
      final props = <String, Object?>{};
      final req = <String>[];
      if (attr['children'] case final List children) {
        for (final c in children) {
          if (c is! Map) continue;
          final cm = freezeJsonMap(c);
          final cn = (cm['name'] as String?)?.trim() ?? '';
          if (cn.isEmpty) continue;
          props[cn] = _synthesizeAttributeSchemaForSeed(cm);
          if (cm['required'] == true) req.add(cn);
        }
      }
      base = <String, Object?>{
        'type': 'object',
        if (props.isNotEmpty) 'properties': props,
        if (req.isNotEmpty) 'required': req,
      };
    } else {
      base = <String, Object?>{
        'type': switch (rawType) {
          'int' || 'integer' => 'integer',
          'number' || 'float' || 'double' || 'decimal' => 'number',
          'bool' || 'boolean' => 'boolean',
          _ => 'string',
        },
        if (rawType == 'uuid' || rawType == 'ref' || rawType == 'reference')
          'format': 'uuid',
        if (rawType == 'email') 'format': 'email',
        if (rawType == 'date') 'format': 'date',
        if (rawType == 'datetime' ||
            rawType == 'date-time' ||
            rawType == 'timestamp')
          'format': 'date-time',
        if (rawType == 'url' || rawType == 'uri') 'format': 'uri',
        if (attr['enumValues'] is List &&
            (attr['enumValues'] as List).isNotEmpty)
          'enum': attr['enumValues'],
      };
    }

    if (attr['schemaConstraints'] case final Map sc) {
      base = <String, Object?>{...base, ...freezeJsonMap(sc)};
    }
    if (isArray) {
      return <String, Object?>{'type': 'array', 'items': base};
    }
    return base;
  }

  Object? _generateForSchemaNode({
    required Object? schemaNode,
    required Map<String, Object?> rootSchema,
    required Map<String, Object?>? attrSpec,
    required Map<String, Map<String, Object?>> rootAttrByName,
    required List<String> lifecycleCodes,
    required String propName,
    required int index,
    required int depth,
    required String softDeleteField,
  }) {
    if (schemaNode is! Map) return '${propName}_$index';
    final effective = _flattenSchemaNode(schemaNode, rootSchema, depth);

    // 1. `const` et `enum` prioritaires.
    if (effective.containsKey('const')) {
      return effective['const'];
    }
    if (effective['enum'] case final List enumList when enumList.isNotEmpty) {
      return enumList[(index - 1) % enumList.length];
    }

    // 2. Gestion de `oneOf` et `anyOf`.
    if (effective['oneOf'] case final List oneOfList
        when oneOfList.isNotEmpty) {
      for (var offset = 0; offset < oneOfList.length; offset++) {
        final branch = oneOfList[(index - 1 + offset) % oneOfList.length];
        final candidate = _generateForSchemaNode(
          schemaNode: branch,
          rootSchema: rootSchema,
          attrSpec: attrSpec,
          rootAttrByName: const <String, Map<String, Object?>>{},
          lifecycleCodes: lifecycleCodes,
          propName: propName,
          index: index,
          depth: depth + 1,
          softDeleteField: softDeleteField,
        );
        if (_isValidCandidateForSubschema(candidate, effective, rootSchema)) {
          return candidate;
        }
      }
    }

    if (effective['anyOf'] case final List anyOfList
        when anyOfList.isNotEmpty) {
      final nonNullBranches = anyOfList
          .where((b) => !(b is Map && b['type'] == 'null'))
          .toList(growable: false);
      final pool = nonNullBranches.isNotEmpty ? nonNullBranches : anyOfList;
      for (var offset = 0; offset < pool.length; offset++) {
        final branch = pool[(index - 1 + offset) % pool.length];
        final candidate = _generateForSchemaNode(
          schemaNode: branch,
          rootSchema: rootSchema,
          attrSpec: attrSpec,
          rootAttrByName: const <String, Map<String, Object?>>{},
          lifecycleCodes: lifecycleCodes,
          propName: propName,
          index: index,
          depth: depth + 1,
          softDeleteField: softDeleteField,
        );
        if (_isValidCandidateForSubschema(candidate, effective, rootSchema)) {
          return candidate;
        }
      }
    }

    // 3. Exemples issus d'un Value Object lié ou du schéma lui-même.
    final voCandidate = _tryPickValueObjectExample(
      schemaNode: schemaNode,
      effectiveSchema: effective,
      rootSchema: rootSchema,
      attrSpec: attrSpec,
      propName: propName,
      index: index,
    );
    if (voCandidate.found) return voCandidate.value;

    final schemaExample = _tryPickSchemaExample(
      effectiveSchema: effective,
      rootSchema: rootSchema,
      attrSpec: attrSpec,
      index: index,
    );
    if (schemaExample.found) return schemaExample.value;

    // 4. Génération déterministe guidée par le type et les contraintes.
    final targetType = _pickPrimaryType(effective, attrSpec);

    switch (targetType) {
      case 'null':
        return null;
      case 'boolean':
        return index.isOdd;
      case 'integer':
        return _generateInteger(effective, index);
      case 'number':
        return _generateNumber(effective, index);
      case 'array':
        return _generateArray(
          effective: effective,
          rootSchema: rootSchema,
          attrSpec: attrSpec,
          lifecycleCodes: lifecycleCodes,
          propName: propName,
          index: index,
          depth: depth,
          softDeleteField: softDeleteField,
        );
      case 'object':
        return _generateObject(
          effective: effective,
          rootSchema: rootSchema,
          attrSpec: attrSpec,
          rootAttrByName: rootAttrByName,
          lifecycleCodes: lifecycleCodes,
          index: index,
          depth: depth,
          softDeleteField: softDeleteField,
        );
      case 'string':
      default:
        return _generateString(
          effective: effective,
          attrSpec: attrSpec,
          lifecycleCodes: lifecycleCodes,
          propName: propName,
          index: index,
        );
    }
  }

  Map<String, Object?> _flattenSchemaNode(
    Map<dynamic, dynamic> schemaNode,
    Map<String, Object?> rootSchema,
    int depth,
  ) {
    final out = <String, Object?>{};

    void mergeFrom(Map<dynamic, dynamic> src, int refDepth) {
      if (refDepth > 8) return;
      final rawRef = src[r'$ref'];
      if (rawRef is String && rawRef.trim().isNotEmpty) {
        final target = _resolveLocalRefMap(rawRef.trim(), rootSchema);
        if (target != null) {
          mergeFrom(target, refDepth + 1);
        }
      }
      if (src['allOf'] case final List allOfList) {
        for (final sub in allOfList) {
          if (sub is Map) mergeFrom(sub, refDepth + 1);
        }
      }

      for (final entry in src.entries) {
        final key = '${entry.key}';
        if (key == r'$ref' || key == 'allOf') continue;
        if (key == 'properties' && entry.value is Map) {
          final existingProps = out['properties'] is Map
              ? Map<String, Object?>.from(out['properties'] as Map)
              : <String, Object?>{};
          for (final pe in (entry.value as Map).entries) {
            existingProps['${pe.key}'] = pe.value;
          }
          out['properties'] = existingProps;
        } else if (key == 'required' && entry.value is List) {
          final existingReq = <String>[
            if (out['required'] case final List prev)
              for (final r in prev) '$r',
          ];
          for (final r in entry.value as List) {
            final rs = '$r';
            if (!existingReq.contains(rs)) existingReq.add(rs);
          }
          out['required'] = existingReq;
        } else {
          out[key] = entry.value;
        }
      }
    }

    if (depth <= 10) {
      mergeFrom(schemaNode, 0);
    }
    return out;
  }

  Map<String, Object?>? _resolveLocalRefMap(
    String ref,
    Map<String, Object?> rootSchema,
  ) {
    if (ref == '#') return rootSchema;
    if (ref.startsWith('#/')) {
      final segments = ref.substring(2).split('/');
      Object? cursor = rootSchema;
      for (final rawSeg in segments) {
        final seg = Uri.decodeComponent(
          rawSeg,
        ).replaceAll('~1', '/').replaceAll('~0', '~');
        if (cursor is Map && cursor.containsKey(seg)) {
          cursor = cursor[seg];
        } else if (cursor == rootSchema &&
            (seg == r'$defs' || seg == 'definitions')) {
          final alt = seg == r'$defs' ? 'definitions' : r'$defs';
          cursor = rootSchema[alt];
        } else {
          cursor = null;
          break;
        }
      }
      if (cursor is Map) return freezeJsonMap(cursor);
      final lastSeg = Uri.decodeComponent(segments.last);
      final vo = _designSpec.findValueObjectByName(lastSeg);
      if (vo != null) {
        return JsonSchemaPayloadValidator.synthesizeValueObjectSchema(vo);
      }
    } else {
      final vo = _designSpec.findValueObjectByName(ref);
      if (vo != null) {
        return JsonSchemaPayloadValidator.synthesizeValueObjectSchema(vo);
      }
    }
    return null;
  }

  ({bool found, Object? value}) _tryPickValueObjectExample({
    required Map<dynamic, dynamic> schemaNode,
    required Map<String, Object?> effectiveSchema,
    required Map<String, Object?> rootSchema,
    required Map<String, Object?>? attrSpec,
    required String propName,
    required int index,
  }) {
    ImportedValueObjectSpec? vo;
    final voId = (attrSpec?['valueObjectId'] as String?)?.trim();
    if (voId != null && voId.isNotEmpty) {
      vo = _designSpec.findValueObjectByName(voId);
    }
    if (vo == null && schemaNode[r'$ref'] is String) {
      final ref = (schemaNode[r'$ref'] as String).trim();
      final tail = ref.split('/').last;
      vo = _designSpec.findValueObjectByName(tail);
    }
    if (vo == null && effectiveSchema['title'] is String) {
      vo = _designSpec.findValueObjectByName(
        effectiveSchema['title'] as String,
      );
    }
    vo ??= _designSpec.findValueObjectByName(propName);

    if (vo == null || vo.examples.isEmpty) {
      return (found: false, value: null);
    }

    final validExamples = vo.examples
        .where((e) => e['isValid'] != false && e['value'] != null)
        .toList(growable: false);
    if (validExamples.isEmpty) return (found: false, value: null);

    final chosen = validExamples[(index - 1) % validExamples.length];
    final parsed = _coerceExampleValue(
      chosen['value'],
      _pickPrimaryType(effectiveSchema, attrSpec),
    );
    if (_isValidCandidateForSubschema(parsed, effectiveSchema, rootSchema)) {
      return (found: true, value: parsed);
    }
    return (found: false, value: null);
  }

  ({bool found, Object? value}) _tryPickSchemaExample({
    required Map<String, Object?> effectiveSchema,
    required Map<String, Object?> rootSchema,
    required Map<String, Object?>? attrSpec,
    required int index,
  }) {
    final candidates = <Object?>[];
    if (effectiveSchema['examples'] case final List exList) {
      candidates.addAll(exList);
    }
    if (attrSpec?['schemaConstraints'] case final Map sc) {
      if (sc['examples'] case final List attrEx) {
        candidates.addAll(attrEx);
      }
    }
    if (effectiveSchema.containsKey('default') &&
        effectiveSchema['default'] != null) {
      candidates.add(effectiveSchema['default']);
    }
    if (candidates.isEmpty) return (found: false, value: null);

    final chosen = candidates[(index - 1) % candidates.length];
    if (_isValidCandidateForSubschema(chosen, effectiveSchema, rootSchema)) {
      return (found: true, value: freezeJsonValue(chosen));
    }
    return (found: false, value: null);
  }

  bool _isValidCandidateForSubschema(
    Object? candidate,
    Map<String, Object?> subschema,
    Map<String, Object?> rootSchema,
  ) {
    final probeSchema = <String, Object?>{
      if (rootSchema[r'$defs'] is Map) r'$defs': rootSchema[r'$defs'],
      if (rootSchema['definitions'] is Map)
        'definitions': rootSchema['definitions'],
      ...subschema,
    };
    return _validator.validate(candidate, probeSchema).isValid;
  }

  static Object? _coerceExampleValue(Object? raw, String targetType) {
    if (raw == null) return null;
    if (targetType == 'object' && raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return freezeJsonMap(decoded);
      } on FormatException {
        return raw;
      }
    }
    if (targetType == 'array' && raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return freezeJsonValue(decoded);
      } on FormatException {
        return raw;
      }
    }
    if (targetType == 'integer' && raw is String) {
      return int.tryParse(raw.trim()) ?? raw;
    }
    if (targetType == 'number' && raw is String) {
      return num.tryParse(raw.trim()) ?? raw;
    }
    if (targetType == 'boolean' && raw is String) {
      final lower = raw.trim().toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return freezeJsonValue(raw);
  }

  static String _pickPrimaryType(
    Map<String, Object?> schema,
    Map<String, Object?>? attrSpec,
  ) {
    final rawType = schema['type'];
    if (rawType is String) return rawType;
    if (rawType is List && rawType.isNotEmpty) {
      for (final item in rawType) {
        if (item is String && item != 'null') return item;
      }
      if (rawType.first is String) return rawType.first as String;
    }
    if (schema['properties'] is Map) return 'object';
    if (schema.containsKey('items') || schema['prefixItems'] is List) {
      return 'array';
    }
    final attrType = (attrSpec?['type'] as String?)?.trim().toLowerCase();
    if (attrType != null) {
      if (attrSpec?['isArray'] == true) return 'array';
      return switch (attrType) {
        'int' || 'integer' => 'integer',
        'number' || 'float' || 'double' || 'decimal' => 'number',
        'bool' || 'boolean' => 'boolean',
        'object' || 'subobject' || 'struct' => 'object',
        _ => 'string',
      };
    }
    return 'string';
  }

  static int _generateInteger(Map<String, Object?> schema, int index) {
    final min = _numOrNull(schema['minimum']);
    final exMin = _numOrNull(schema['exclusiveMinimum']);
    final max = _numOrNull(schema['maximum']);
    final exMax = _numOrNull(schema['exclusiveMaximum']);
    final multRaw = _numOrNull(schema['multipleOf']);
    final step = (multRaw != null && multRaw >= 1) ? multRaw.ceil() : 1;

    var lower = 1;
    if (min != null) {
      lower = schema['exclusiveMinimum'] == true ? min.floor() + 1 : min.ceil();
    }
    if (exMin != null) {
      final candidate = exMin.floor() + 1;
      if (candidate > lower || min == null) lower = candidate;
    }

    int? upper;
    if (max != null) {
      upper = schema['exclusiveMaximum'] == true ? max.ceil() - 1 : max.floor();
    }
    if (exMax != null) {
      final candidate = exMax.ceil() - 1;
      upper = upper == null ? candidate : (candidate < upper ? candidate : upper);
    }

    if (step > 1 && lower % step != 0) {
      final rem = lower % step;
      lower += step - rem;
    }

    if (upper != null && upper >= lower) {
      final spanSteps = ((upper - lower) ~/ step) + 1;
      final offsetSteps = spanSteps <= 1 ? 0 : (index - 1) % spanSteps;
      return lower + offsetSteps * step;
    }
    return lower + (index - 1) * step;
  }

  static num _generateNumber(Map<String, Object?> schema, int index) {
    final min = _numOrNull(schema['minimum']);
    final exMin = _numOrNull(schema['exclusiveMinimum']);
    final max = _numOrNull(schema['maximum']);
    final exMax = _numOrNull(schema['exclusiveMaximum']);
    final mult = _numOrNull(schema['multipleOf']);
    final step = (mult != null && mult > 0) ? mult.toDouble() : 10.5;

    var lower = mult != null && mult > 0 ? mult.toDouble() : 10.0;
    if (min != null) {
      lower = schema['exclusiveMinimum'] == true
          ? min.toDouble() + (mult?.toDouble() ?? 1.0)
          : min.toDouble();
    }
    if (exMin != null) {
      final candidate = exMin.toDouble() + (mult?.toDouble() ?? 1.0);
      if (candidate > lower || min == null) lower = candidate;
    }

    double? upper;
    if (max != null) {
      upper = schema['exclusiveMaximum'] == true
          ? max.toDouble() - (mult?.toDouble() ?? 1.0)
          : max.toDouble();
    }
    if (exMax != null) {
      final candidate = exMax.toDouble() - (mult?.toDouble() ?? 1.0);
      upper = upper == null ? candidate : (candidate < upper ? candidate : upper);
    }

    if (mult != null && mult > 0) {
      final q = (lower / mult).ceil();
      lower = q * mult.toDouble();
    }

    double rawValue;
    if (upper != null && upper >= lower) {
      if (upper == lower) {
        rawValue = lower;
      } else {
        final maxSteps = ((upper - lower) / step).floor();
        final k = maxSteps <= 0 ? 0 : (index - 1) % (maxSteps + 1);
        rawValue = lower + k * step;
        if (rawValue > upper) rawValue = lower;
      }
    } else {
      rawValue = lower + (index - 1) * step;
    }

    return double.parse(rawValue.toStringAsFixed(6));
  }

  List<Object?> _generateArray({
    required Map<String, Object?> effective,
    required Map<String, Object?> rootSchema,
    required Map<String, Object?>? attrSpec,
    required List<String> lifecycleCodes,
    required String propName,
    required int index,
    required int depth,
    required String softDeleteField,
  }) {
    final minItems = _intOrNull(effective['minItems']) ?? (depth > 4 ? 0 : 1);
    final maxItems = _intOrNull(effective['maxItems']);
    var targetCount = minItems < 1 && depth <= 4 ? 1 : minItems;
    if (maxItems != null && targetCount > maxItems) {
      targetCount = maxItems;
    }
    if (depth > 6 && minItems == 0) {
      return const <Object?>[];
    }

    final items = <Object?>[];
    final prefixList = effective['prefixItems'] is List
        ? effective['prefixItems'] as List
        : const <Object?>[];
    final itemSchema = effective['items'];

    final childAttrSpec = _unwrapArrayAttrSpec(attrSpec);

    for (var i = 0; i < targetCount; i++) {
      final subSchema = i < prefixList.length ? prefixList[i] : itemSchema;
      if (subSchema == false) break;
      final itemSeedIndex = index * 17 + i + 1;
      items.add(
        _generateForSchemaNode(
          schemaNode: subSchema ?? const <String, Object?>{'type': 'string'},
          rootSchema: rootSchema,
          attrSpec: childAttrSpec,
          rootAttrByName: const <String, Map<String, Object?>>{},
          lifecycleCodes: lifecycleCodes,
          propName: '${propName}_item',
          index: itemSeedIndex,
          depth: depth + 1,
          softDeleteField: softDeleteField,
        ),
      );
    }
    return items;
  }

  Map<String, Object?> _generateObject({
    required Map<String, Object?> effective,
    required Map<String, Object?> rootSchema,
    required Map<String, Object?>? attrSpec,
    required Map<String, Map<String, Object?>> rootAttrByName,
    required List<String> lifecycleCodes,
    required int index,
    required int depth,
    required String softDeleteField,
  }) {
    final out = <String, Object?>{};
    final props = effective['properties'] is Map
        ? effective['properties'] as Map
        : const <dynamic, dynamic>{};
    final requiredSet = <String>{
      if (effective['required'] case final List reqList)
        for (final r in reqList) '$r',
    };

    final childAttrByName = <String, Map<String, Object?>>{...rootAttrByName};
    if (attrSpec?['children'] case final List children) {
      for (final c in children) {
        if (c is Map && c['name'] is String) {
          childAttrByName[(c['name'] as String).trim()] = freezeJsonMap(c);
        }
      }
    }

    for (final entry in props.entries) {
      final key = '${entry.key}';
      if (key == softDeleteField && !requiredSet.contains(key)) {
        continue;
      }
      if (depth > 5 && !requiredSet.contains(key)) {
        continue;
      }
      out[key] = _generateForSchemaNode(
        schemaNode: entry.value,
        rootSchema: rootSchema,
        attrSpec: childAttrByName[key],
        rootAttrByName: const <String, Map<String, Object?>>{},
        lifecycleCodes: lifecycleCodes,
        propName: key,
        index: index,
        depth: depth + 1,
        softDeleteField: softDeleteField,
      );
    }

    final minProps = _intOrNull(effective['minProperties']) ?? 0;
    if (out.length < minProps && effective['additionalProperties'] != false) {
      final addSchema = effective['additionalProperties'] is Map
          ? effective['additionalProperties']
          : const <String, Object?>{'type': 'string'};
      var extraIdx = 1;
      while (out.length < minProps) {
        final key = 'extra_$extraIdx';
        if (!out.containsKey(key)) {
          out[key] = _generateForSchemaNode(
            schemaNode: addSchema,
            rootSchema: rootSchema,
            attrSpec: null,
            rootAttrByName: const <String, Map<String, Object?>>{},
            lifecycleCodes: lifecycleCodes,
            propName: key,
            index: index + extraIdx,
            depth: depth + 1,
            softDeleteField: softDeleteField,
          );
        }
        extraIdx++;
      }
    }

    return out;
  }

  static String _generateString({
    required Map<String, Object?> effective,
    required Map<String, Object?>? attrSpec,
    required List<String> lifecycleCodes,
    required String propName,
    required int index,
  }) {
    final minLen = _intOrNull(effective['minLength']) ?? 0;
    final maxLen = _intOrNull(effective['maxLength']);
    final format = (effective['format'] as String?)?.trim().toLowerCase();

    if (format != null && format.isNotEmpty) {
      switch (format) {
        case 'uuid':
          return _deterministicUuid(index);
        case 'email':
        case 'idn-email':
          return _fitEmailLength('contact.$index@domaine.fr', minLen, maxLen);
        case 'date':
          final d = DateTime.utc(2026, 1, 1).add(Duration(days: index - 1));
          return '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';
        case 'date-time':
          final d = DateTime.utc(
            2026,
            1,
            1,
            9,
          ).add(Duration(days: index - 1, minutes: index * 5));
          return d.toIso8601String();
        case 'uri':
        case 'url':
          return _fitLength(
            'https://api.domaine.fr/$propName/$index',
            minLen,
            maxLen,
            padChar: 'a',
          );
      }
    }

    final pattern = effective['pattern'];
    if (pattern is String && pattern.isNotEmpty) {
      final fromRegex = _RegexSampleGenerator.generate(
        pattern,
        index: index,
        minLength: minLen,
        maxLength: maxLen,
      );
      if (fromRegex != null) return fromRegex;
    }

    final lowerProp = propName.toLowerCase();
    String base;
    if (lowerProp == 'id' || lowerProp.endsWith('id')) {
      base = _deterministicUuid(index);
    } else if (lowerProp.contains('email')) {
      return _fitEmailLength('client.$index@domaine.fr', minLen, maxLen);
    } else if (lowerProp == 'currency' || lowerProp.endsWith('currency')) {
      const currencies = <String>['EUR', 'USD', 'GBP', 'CHF'];
      base = currencies[(index - 1) % currencies.length];
    } else if ((lowerProp == 'status' || lowerProp == 'state') &&
        lifecycleCodes.isNotEmpty) {
      base = lifecycleCodes[(index - 1) % lifecycleCodes.length];
    } else if (lowerProp.contains('code') || lowerProp.contains('number')) {
      final prefix = propName
          .replaceAll(RegExp(r'[^A-Za-z]'), '')
          .toUpperCase();
      final shortPrefix = prefix.length >= 3
          ? prefix.substring(0, 3)
          : 'REF';
      base = '$shortPrefix-${index.toString().padLeft(4, '0')}';
    } else {
      final cleanName = propName.isEmpty ? 'Valeur' : propName;
      base = '${cleanName}_$index';
    }

    return _fitLength(base, minLen, maxLen);
  }

  static String _fitEmailLength(String email, int minLen, int? maxLen) {
    if (maxLen != null && email.length > maxLen && maxLen >= 6) {
      return 'u$indexOrChar@a.fr'.substring(0, maxLen < 7 ? maxLen : 7);
    }
    if (email.length < minLen) {
      final atIdx = email.indexOf('@');
      final needed = minLen - email.length;
      final pad = 'x' * needed;
      return '${email.substring(0, atIdx)}$pad${email.substring(atIdx)}';
    }
    return email;
  }

  static const String indexOrChar = '1';

  static String _fitLength(
    String input,
    int minLen,
    int? maxLen, {
    String padChar = 'x',
  }) {
    var value = input;
    if (value.runes.length < minLen) {
      value = value + (padChar * (minLen - value.runes.length));
    }
    if (maxLen != null && value.runes.length > maxLen) {
      value = String.fromCharCodes(value.runes.take(maxLen));
    }
    return value;
  }

  static String _deterministicUuid(int index) {
    final hex = index.abs().toRadixString(16).padLeft(12, '0');
    final tail = hex.length > 12 ? hex.substring(hex.length - 12) : hex;
    return '00000000-0000-4000-8000-$tail';
  }

  static Map<String, Object?>? _unwrapArrayAttrSpec(
    Map<String, Object?>? attrSpec,
  ) {
    if (attrSpec == null) return null;
    if (attrSpec['isArray'] != true) return attrSpec;
    final copy = Map<String, Object?>.of(attrSpec);
    copy['isArray'] = false;
    return copy;
  }

  static bool _effectiveAdditionalPropertiesFalse(
    Map<String, Object?> schema,
    Map<String, Object?> rootSchema,
  ) {
    if (schema['additionalProperties'] == false) return true;
    if (schema['allOf'] case final List allOfList) {
      for (final item in allOfList) {
        if (item is Map && item['additionalProperties'] == false) return true;
      }
    }
    return false;
  }

  static Object? _findRootPropertySchema(
    Map<String, Object?> rootSchema,
    String keyField,
  ) {
    if (rootSchema['properties'] case final Map props) {
      if (props.containsKey(keyField)) return props[keyField];
    }
    return null;
  }

  static bool _schemaRequiresProperty(
    Map<String, Object?> schema,
    String field,
  ) {
    if (schema['required'] case final List reqList) {
      if (reqList.contains(field)) return true;
    }
    if (schema['allOf'] case final List allOfList) {
      for (final sub in allOfList) {
        if (sub is Map &&
            sub['required'] is List &&
            (sub['required'] as List).contains(field)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _isValidScrudFieldPath(String field) =>
      field.isNotEmpty &&
      field.length <= 128 &&
      _scrudFieldPathPattern.hasMatch(field);

  static String? _nonEmptyString(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  static Map<String, Object?> _cloneMutableMap(Map<String, Object?> source) {
    final encoded = jsonEncode(source);
    final decoded = jsonDecode(encoded);
    if (decoded is Map<String, Object?>) return decoded;
    return Map<String, Object?>.from(decoded as Map);
  }

  static int? _intOrNull(Object? raw) => switch (raw) {
    int i => i,
    double d when d.isFinite && d == d.truncateToDouble() => d.toInt(),
    _ => null,
  };

  static num? _numOrNull(Object? raw) => switch (raw) {
    int i => i,
    double d when d.isFinite => d,
    _ => null,
  };
}

/// Petit synthétiseur déterministe de chaînes satisfaisant les motifs `pattern`
/// JSON Schema courants (`^INV-[0-9]{4}$`, `^[A-Z]{2,3}-\d+$`, etc.).
class _RegexSampleGenerator {
  static String? generate(
    String pattern, {
    required int index,
    int minLength = 0,
    int? maxLength,
  }) {
    RegExp compiled;
    try {
      compiled = RegExp(pattern);
    } on FormatException {
      return null;
    }

    var body = pattern;
    if (body.startsWith('^')) body = body.substring(1);
    if (body.endsWith(r'$') && !body.endsWith(r'\$')) {
      body = body.substring(0, body.length - 1);
    }

    final candidate = _emitSequence(body, index);
    var adjusted = candidate;
    if (adjusted.length < minLength) {
      adjusted = adjusted + ('a' * (minLength - adjusted.length));
    }
    if (maxLength != null && adjusted.length > maxLength) {
      adjusted = adjusted.substring(0, maxLength);
    }
    if (compiled.hasMatch(adjusted)) {
      return adjusted;
    }
    if (compiled.hasMatch(candidate)) {
      return candidate;
    }
    return null;
  }

  static String _emitSequence(String expr, int index) {
    final branches = _splitTopLevelAlternation(expr);
    if (branches.length > 1) {
      final chosen = branches[(index - 1) % branches.length];
      return _emitSequence(chosen, index);
    }

    final out = StringBuffer();
    var i = 0;
    var atomCounter = 0;
    while (i < expr.length) {
      final ch = expr[i];
      if (ch == '^' || ch == r'$') {
        i++;
        continue;
      }

      String Function(int step) atomEmitter;
      int nextIndex;

      if (ch == '(') {
        final end = _findClosingParen(expr, i);
        var inner = expr.substring(i + 1, end);
        if (inner.startsWith('?:') ||
            inner.startsWith('?=') ||
            inner.startsWith('?!')) {
          if (inner.startsWith('?!')) {
            i = end + 1;
            continue;
          }
          inner = inner.substring(2);
        }
        atomEmitter = (step) => _emitSequence(inner, index + step);
        nextIndex = end + 1;
      } else if (ch == '[') {
        final end = _findClosingBracket(expr, i);
        final charClass = expr.substring(i + 1, end);
        final pool = _expandCharClass(charClass);
        atomEmitter = (step) => pool[(index - 1 + step) % pool.length];
        nextIndex = end + 1;
      } else if (ch == r'\' && i + 1 < expr.length) {
        final esc = expr[i + 1];
        atomEmitter = (step) => _emitEscape(esc, index + step);
        nextIndex = i + 2;
      } else if (ch == '.') {
        const alpha = 'abcdefghij';
        atomEmitter = (step) {
          final pos = (index - 1 + step) % alpha.length;
          return alpha[pos];
        };
        nextIndex = i + 1;
      } else {
        final literal = ch;
        atomEmitter = (_) => literal;
        nextIndex = i + 1;
      }

      final quant = _parseQuantifier(expr, nextIndex);
      nextIndex = quant.nextPos;
      for (var rep = 0; rep < quant.repeatCount; rep++) {
        out.write(atomEmitter(atomCounter + rep));
      }
      atomCounter++;
      i = nextIndex;
    }
    return out.toString();
  }

  static List<String> _splitTopLevelAlternation(String expr) {
    final parts = <String>[];
    var depthParen = 0;
    var inBracket = false;
    var start = 0;
    for (var i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (ch == r'\') {
        i++;
        continue;
      }
      if (inBracket) {
        if (ch == ']') inBracket = false;
        continue;
      }
      if (ch == '[') {
        inBracket = true;
      } else if (ch == '(') {
        depthParen++;
      } else if (ch == ')' && depthParen > 0) {
        depthParen--;
      } else if (ch == '|' && depthParen == 0) {
        parts.add(expr.substring(start, i));
        start = i + 1;
      }
    }
    if (parts.isEmpty) return <String>[expr];
    parts.add(expr.substring(start));
    return parts;
  }

  static int _findClosingParen(String expr, int openPos) {
    var depth = 0;
    var inBracket = false;
    for (var i = openPos; i < expr.length; i++) {
      final ch = expr[i];
      if (ch == r'\') {
        i++;
        continue;
      }
      if (inBracket) {
        if (ch == ']') inBracket = false;
        continue;
      }
      if (ch == '[') {
        inBracket = true;
      } else if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return expr.length - 1;
  }

  static int _findClosingBracket(String expr, int openPos) {
    for (var i = openPos + 1; i < expr.length; i++) {
      final ch = expr[i];
      if (ch == r'\') {
        i++;
        continue;
      }
      if (ch == ']' && i > openPos + 1) return i;
    }
    return expr.length - 1;
  }

  static List<String> _expandCharClass(String spec) {
    final negated = spec.startsWith('^');
    final body = negated ? spec.substring(1) : spec;
    final chars = <String>[];
    var i = 0;
    while (i < body.length) {
      if (body[i] == r'\' && i + 1 < body.length) {
        final esc = body[i + 1];
        switch (esc) {
          case 'd':
            for (var c = 48; c <= 57; c++) {
              chars.add(String.fromCharCode(c));
            }
          case 'w':
            for (var c = 97; c <= 122; c++) {
              chars.add(String.fromCharCode(c));
            }
          case 's':
            chars.add(' ');
          default:
            chars.add(esc);
        }
        i += 2;
      } else if (i + 2 < body.length && body[i + 1] == '-') {
        final startCode = body.codeUnitAt(i);
        final endCode = body.codeUnitAt(i + 2);
        if (endCode >= startCode && endCode - startCode <= 128) {
          for (var c = startCode; c <= endCode; c++) {
            chars.add(String.fromCharCode(c));
          }
        } else {
          chars.add(body[i]);
        }
        i += 3;
      } else {
        chars.add(body[i]);
        i++;
      }
    }

    if (negated) {
      const candidates = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final allowed = <String>[
        for (final rune in candidates.runes)
          if (!chars.contains(String.fromCharCode(rune)))
            String.fromCharCode(rune),
      ];
      return allowed.isEmpty ? const <String>['a'] : allowed;
    }
    return chars.isEmpty ? const <String>['a'] : chars;
  }

  static String _emitEscape(String esc, int seed) {
    switch (esc) {
      case 'd':
        return '${seed % 10}';
      case 'D':
        return 'A';
      case 'w':
        const letters = 'abcdefghijklmnopqrstuvwxyz';
        return letters[seed % letters.length];
      case 'W':
        return '-';
      case 's':
        return ' ';
      case 'S':
        return 'x';
      case 'b':
      case 'B':
        return '';
      default:
        return esc;
    }
  }

  static ({int repeatCount, int nextPos}) _parseQuantifier(
    String expr,
    int pos,
  ) {
    if (pos >= expr.length) return (repeatCount: 1, nextPos: pos);
    final ch = expr[pos];
    if (ch == '?') {
      final next = (pos + 1 < expr.length && expr[pos + 1] == '?')
          ? pos + 2
          : pos + 1;
      return (repeatCount: 1, nextPos: next);
    }
    if (ch == '*') {
      final next = (pos + 1 < expr.length && expr[pos + 1] == '?')
          ? pos + 2
          : pos + 1;
      return (repeatCount: 1, nextPos: next);
    }
    if (ch == '+') {
      final next = (pos + 1 < expr.length && expr[pos + 1] == '?')
          ? pos + 2
          : pos + 1;
      return (repeatCount: 2, nextPos: next);
    }
    if (ch == '{') {
      final close = expr.indexOf('}', pos + 1);
      if (close > pos + 1) {
        final spec = expr.substring(pos + 1, close);
        final parts = spec.split(',');
        final minRep = int.tryParse(parts.first.trim());
        if (minRep != null) {
          var next = close + 1;
          if (next < expr.length && expr[next] == '?') next++;
          return (repeatCount: minRep, nextPos: next);
        }
      }
    }
    return (repeatCount: 1, nextPos: pos);
  }
}
