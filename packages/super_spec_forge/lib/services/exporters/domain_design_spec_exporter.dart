/// Exportateur JSON portable de la spécification Design complète d'un domaine
/// fonctionnel ([DomainDesignSpecExporter]), à partir de son état courant ou
/// d'un jalon figé ([DomainIterationSnapshot]).
///
/// Le document produit (`format: "super_spec_forge.domain_design_spec"`,
/// `version: 1`) consolide l'identité du domaine, sa stack technique, ses
/// environnements, ses systèmes/services, ses configurations (avec retrait
/// strict de toute valeur chiffrée de secret), ses Value Objects résolus
/// (`domain` et `shared`) accompagnés de leurs JSON Schemas Draft 2020-12, ses
/// modèles/contrats enrichis de leur couche Domain hexagonale et de leurs JSON
/// Schemas Draft 2020-12, ainsi que l'orchestration des Use Cases CQRS et Sagas.
library;

import 'dart:convert';
import 'dart:io';

import '../../models/build_design_item.dart';
import '../../models/build_tech_stack_profile.dart';
import '../../models/business_object_model_preferences.dart';
import '../../models/domain_catalog.dart';
import '../../models/domain_contracts.dart';
import '../../models/domain_iteration_snapshot.dart';
import '../../models/usecase_orchestration_spec.dart';
import '../../models/value_object_spec.dart';
import 'prompt_generator/model_prompt_context.dart';
import 'prompt_generator/prompt_json_schema_builder.dart';
import 'spec_super_designer_exporter.dart';

/// Génère le bundle JSON portable de spécification Design d'un [FunctionalDomain].
abstract final class DomainDesignSpecExporter {
  /// Identifiant canonique du format JSON d'export Design.
  static const String fileFormat = 'super_spec_forge.domain_design_spec';

  /// Numéro de version du contrat JSON d'export Design.
  static const int specVersion = 1;

  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

  /// Retourne le nom de fichier par défaut pour l'export de [domain], ou du
  /// jalon [snapshot] lorsqu'il est fourni.
  static String defaultFileName(
    FunctionalDomain domain, {
    DomainIterationSnapshot? snapshot,
  }) => snapshot == null
      ? '${domain.domainCode}.domain-design.json'
      : '${domain.domainCode}.iter-${snapshot.iterationNumber}.domain-design.json';

  /// Construit la représentation JSON portable de [domain] (état courant lorsque
  /// [snapshot] est `null`, ou artefacts figés du [snapshot] sinon).
  ///
  /// Les valeurs chiffrées (`encryptedValue`) et secrètes des entrées
  /// [ConfigurationEntry] de type [ConfigurationEntryType.secret] ne sont
  /// jamais incluses dans l'export.
  static Map<String, Object?> exportToJson({
    required FunctionalDomain domain,
    DomainCatalog? catalog,
    DomainIterationSnapshot? snapshot,
    BusinessObjectModelPreferences? modelPreferences,
    DateTime? exportedAt,
  }) {
    final effectiveExportedAt = (exportedAt ?? DateTime.now()).toUtc();
    final effectivePrefs =
        modelPreferences ?? BusinessObjectModelPreferences.defaults;
    final strictObjects =
        effectivePrefs.schemaStrictness == JsonSchemaStrictness.strict;

    final syncedCatalog = _syncCatalogWithDomain(catalog, domain);
    final resolvedTechStack = _resolveTechStack(domain, syncedCatalog);

    final environments = syncedCatalog == null
        ? const <LogicalEnvironment>[]
        : syncedCatalog.environments
              .where((env) => env.domainId == domain.id)
              .toList(growable: false);
    final systems = syncedCatalog == null
        ? const <Microservice>[]
        : syncedCatalog.microservices
              .where((svc) => svc.domainId == domain.id)
              .toList(growable: false);
    final configurations = syncedCatalog == null
        ? const <ConfigurationEntry>[]
        : syncedCatalog.configurationEntries
              .where((cfg) => cfg.domainId == domain.id)
              .toList(growable: false);

    final resolvedVos = snapshot != null
        ? <ResolvedValueObject>[
            for (final artifact in snapshot.valueObjects.values)
              ResolvedValueObject(
                spec: artifact.spec,
                scope: artifact.scope,
                domainId: artifact.scope == ValueObjectScope.domain
                    ? domain.id
                    : null,
              ),
          ]
        : (syncedCatalog != null
              ? syncedCatalog.resolvedValueObjectsForDomain(domain.id)
              : <ResolvedValueObject>[
                  for (final vo in domain.valueObjects)
                    ResolvedValueObject(
                      spec: vo,
                      scope: ValueObjectScope.domain,
                      domainId: domain.id,
                    ),
                ]);

    final allVoSpecs = <ValueObjectSpec>[
      for (final item in resolvedVos) item.spec,
    ];
    final voScopesById = <String, ValueObjectScope>{
      for (final item in resolvedVos) item.spec.id: item.scope,
    };

    final valueObjectsJson = <Map<String, Object?>>[
      for (final resolved in resolvedVos)
        <String, Object?>{
          'id': resolved.spec.id,
          'scope': resolved.scope.name,
          'spec': resolved.spec.toJson(),
          'jsonSchema': <String, Object?>{
            r'$schema': PromptJsonSchemaBuilder.draft202012Uri,
            'title': resolved.spec.technicalName,
            ...SpecSuperDesignerExporter.valueObjectToJsonSchema(
              resolved.spec,
              valueObjects: allVoSpecs,
              valueObjectScopes: voScopesById,
              scope: resolved.scope,
              strictObjects: strictObjects,
            ),
          },
        },
    ];

    final contractsJson = snapshot != null
        ? _buildSnapshotContractsJson(
            domain: domain,
            snapshot: snapshot,
            resolvedVos: resolvedVos,
            techStacks: syncedCatalog?.techStacks,
            modelPreferences: effectivePrefs,
          )
        : _buildCurrentContractsJson(
            domain: domain,
            catalog: syncedCatalog,
            modelPreferences: effectivePrefs,
          );

    final orchestrationJson = _buildOrchestrationJson(
      domain: domain,
      snapshot: snapshot,
    );

    final rawTechStackId = domain.techStackId?.trim();
    final domainJson = <String, Object?>{
      'id': domain.id,
      'domainCode': domain.domainCode,
      'name': domain.name,
      'description': domain.description,
      'isActive': domain.isActive,
      if (rawTechStackId != null && rawTechStackId.isNotEmpty)
        'techStackId': rawTechStackId,
      if (resolvedTechStack != null)
        'techStack': <String, Object?>{
          'id': resolvedTechStack.id,
          'code': resolvedTechStack.code,
          'name': resolvedTechStack.name,
          'description': resolvedTechStack.description,
        },
    };

    return <String, Object?>{
      'format': fileFormat,
      'version': specVersion,
      'exportedAt': effectiveExportedAt.toIso8601String(),
      'sourceKind': snapshot == null ? 'current' : 'snapshot',
      if (snapshot != null)
        'snapshotMeta': <String, Object?>{
          'id': snapshot.id,
          'iterationNumber': snapshot.iterationNumber,
          'label': snapshot.label,
          'notes': snapshot.notes,
          'createdAt': snapshot.createdAt.toUtc().toIso8601String(),
          if (snapshot.techStackId != null &&
              snapshot.techStackId!.trim().isNotEmpty)
            'techStackId': snapshot.techStackId,
        },
      'domain': domainJson,
      'environments': <Map<String, Object?>>[
        for (final env in environments) env.toJson(),
      ],
      'systems': <Map<String, Object?>>[
        for (final svc in systems) svc.toJson(),
      ],
      'configurations': <Map<String, Object?>>[
        for (final cfg in configurations) _serializeMaskedConfiguration(cfg),
      ],
      'valueObjects': valueObjectsJson,
      'contracts': contractsJson,
      'useCaseOrchestration': orchestrationJson,
    };
  }

  /// Sérialise la spécification Design portable de [domain] en JSON indenté sur 2 espaces.
  static String exportToPrettyJson({
    required FunctionalDomain domain,
    DomainCatalog? catalog,
    DomainIterationSnapshot? snapshot,
    BusinessObjectModelPreferences? modelPreferences,
    DateTime? exportedAt,
  }) => _prettyEncoder.convert(
    exportToJson(
      domain: domain,
      catalog: catalog,
      snapshot: snapshot,
      modelPreferences: modelPreferences,
      exportedAt: exportedAt,
    ),
  );

  /// Exporte la spécification Design portable de [domain] dans [targetFile], en
  /// créant récursivement son répertoire parent si nécessaire.
  static Future<File> exportToFile({
    required File targetFile,
    required FunctionalDomain domain,
    DomainCatalog? catalog,
    DomainIterationSnapshot? snapshot,
    BusinessObjectModelPreferences? modelPreferences,
    DateTime? exportedAt,
  }) async {
    await targetFile.parent.create(recursive: true);
    final pretty = exportToPrettyJson(
      domain: domain,
      catalog: catalog,
      snapshot: snapshot,
      modelPreferences: modelPreferences,
      exportedAt: exportedAt,
    );
    return targetFile.writeAsString('$pretty\n', flush: true);
  }

  static DomainCatalog? _syncCatalogWithDomain(
    DomainCatalog? catalog,
    FunctionalDomain domain,
  ) {
    if (catalog == null) return null;
    if (catalog.domains.any((d) => d.id == domain.id && identical(d, domain))) {
      return catalog;
    }
    final replaced = <FunctionalDomain>[
      for (final existing in catalog.domains)
        if (existing.id == domain.id) domain else existing,
      if (!catalog.domains.any((existing) => existing.id == domain.id)) domain,
    ];
    return catalog.copyWith(domains: replaced);
  }

  static BuildTechStackProfile? _resolveTechStack(
    FunctionalDomain domain,
    DomainCatalog? catalog,
  ) {
    final stackId = domain.techStackId?.trim();
    if (stackId == null || stackId.isEmpty) return null;
    if (catalog != null) {
      final fromCatalog = catalog.techStackForDomain(domain);
      if (fromCatalog != null) return fromCatalog;
    }
    return BuildTechStackProfile.defaults
        .where((stack) => stack.id == stackId)
        .firstOrNull;
  }

  static Map<String, Object?> _serializeMaskedConfiguration(
    ConfigurationEntry entry,
  ) {
    final isPlain = entry.entryType == ConfigurationEntryType.plainVariable;
    return <String, Object?>{
      'id': entry.id,
      'domainId': entry.domainId,
      'environmentId': entry.environmentId,
      if (entry.microserviceId != null) 'microserviceId': entry.microserviceId,
      'configKey': entry.configKey,
      'entryType': entry.entryType.name,
      if (isPlain) 'plainValue': entry.plainValue ?? '',
      'isInitialized': entry.isInitialized,
      'description': entry.description,
    };
  }

  static Map<String, Object?> _buildCurrentContractsJson({
    required FunctionalDomain domain,
    required DomainCatalog? catalog,
    required BusinessObjectModelPreferences modelPreferences,
  }) {
    final contracts = domain.contracts;
    if (contracts == null) {
      return <String, Object?>{
        'dslSource': '',
        'entries': const <Map<String, Object?>>[],
      };
    }

    final entries = <Map<String, Object?>>[];
    for (final group in contracts.groups) {
      for (final node in group.children) {
        final detail = contracts.details[node.id] ?? ContractDetails.defaults;
        final objectSpec = contracts.objectFor(node);
        final domainLayer = contracts.domainLayerFor(node);
        final buildItem = BuildDesignItem(
          domainId: domain.id,
          id: node.id,
          kind: BuildDesignItemKind.model,
          name: node.name,
          subtitle: detail.title.trim() == node.name ? '' : detail.title.trim(),
          version: detail.version,
          primaryBadge: node.type,
          secondaryBadge: 'v${detail.version}',
          groupName: group.name,
          states: detail.states,
        );
        final promptCtx = ModelPromptContext.resolve(
          domain: domain,
          item: buildItem,
          catalog: catalog,
          modelPreferences: modelPreferences,
        );
        final jsonSchema = PromptJsonSchemaBuilder.buildModelSchema(promptCtx);

        entries.add(<String, Object?>{
          'entryId': node.id,
          'name': node.name,
          'technicalName': objectSpec.technicalName,
          'groupName': group.name,
          'dslType': node.type,
          'title': detail.title,
          'version': detail.version,
          'states': contractStatesToJson(detail.states),
          'objectSpec': objectSpec.toJson(),
          'jsonSchema': jsonSchema,
          'domainLayer': domainLayer.toJson(),
        });
      }
    }

    return <String, Object?>{
      'dslSource': contracts.source,
      'entries': entries,
    };
  }

  static Map<String, Object?> _buildSnapshotContractsJson({
    required FunctionalDomain domain,
    required DomainIterationSnapshot snapshot,
    required List<ResolvedValueObject> resolvedVos,
    required List<BuildTechStackProfile>? techStacks,
    required BusinessObjectModelPreferences modelPreferences,
  }) {
    final snapshotContracts = _reconstructContractsFromSnapshot(snapshot);
    final snapshotDomainVos = <ValueObjectSpec>[
      for (final vo in resolvedVos)
        if (vo.scope == ValueObjectScope.domain) vo.spec,
    ];
    final snapshotSharedVos = <ValueObjectSpec>[
      for (final vo in resolvedVos)
        if (vo.scope == ValueObjectScope.shared) vo.spec,
    ];
    final snapshotDomain = domain.copyWith(
      contracts: snapshotContracts,
      valueObjects: snapshotDomainVos,
    );
    final snapshotCatalog = DomainCatalog(
      domains: <FunctionalDomain>[snapshotDomain],
      sharedValueObjects: snapshotSharedVos,
      techStacks: techStacks,
    );

    final entries = <Map<String, Object?>>[];
    for (final artifact in snapshot.models.values) {
      final buildItem = BuildDesignItem(
        domainId: domain.id,
        id: artifact.entryId,
        kind: BuildDesignItemKind.model,
        name: artifact.name,
        subtitle: artifact.title.trim() == artifact.name
            ? ''
            : artifact.title.trim(),
        version: artifact.version,
        primaryBadge: artifact.dslType,
        secondaryBadge: 'v${artifact.version}',
        groupName: artifact.groupName,
      );
      final promptCtx = ModelPromptContext.resolve(
        domain: snapshotDomain,
        item: buildItem,
        catalog: snapshotCatalog,
        modelPreferences: modelPreferences,
      );
      final builtSchema = PromptJsonSchemaBuilder.buildModelSchema(promptCtx);
      final effectiveTechName = artifact.objectSpec.technicalName;
      final jsonSchema = builtSchema['title'] == effectiveTechName
          ? builtSchema
          : <String, Object?>{...builtSchema, 'title': effectiveTechName};

      entries.add(<String, Object?>{
        'entryId': artifact.entryId,
        'name': artifact.name,
        'technicalName': effectiveTechName,
        'groupName': artifact.groupName,
        'dslType': artifact.dslType,
        'title': artifact.title,
        'version': artifact.version,
        'states': const <String, String>{},
        'objectSpec': artifact.objectSpec.toJson(),
        'jsonSchema': jsonSchema,
        'domainLayer': artifact.domainLayerSpec.toJson(),
      });
    }

    return <String, Object?>{
      'dslSource': snapshotContracts.source,
      'entries': entries,
    };
  }

  static DomainContracts _reconstructContractsFromSnapshot(
    DomainIterationSnapshot snapshot,
  ) {
    if (snapshot.models.isEmpty) {
      return DomainContracts.fromJson(<String, dynamic>{
        'source': '',
        'nodes': const <Object?>[],
        'details': <String, dynamic>{},
      });
    }

    final byGroup = <String, List<SnapshotModelArtifact>>{};
    for (final artifact in snapshot.models.values) {
      byGroup
          .putIfAbsent(artifact.groupName, () => <SnapshotModelArtifact>[])
          .add(artifact);
    }

    final sourceBuf = StringBuffer();
    final nodesJson = <Map<String, Object?>>[];
    final detailsJson = <String, dynamic>{};
    final objectsJson = <String, Object?>{};
    final domainLayersJson = <String, Object?>{};

    for (final groupEntry in byGroup.entries) {
      final groupName = groupEntry.key;
      final artifacts = groupEntry.value;
      sourceBuf.writeln('$groupName:');
      final childrenJson = <Map<String, Object?>>[];
      for (final artifact in artifacts) {
        sourceBuf.writeln('  ${artifact.name}: ${artifact.dslType}');
        childrenJson.add(<String, Object?>{
          'id': artifact.entryId,
          'name': artifact.name,
          'type': artifact.dslType,
          'value': artifact.dslType,
        });
        detailsJson[artifact.entryId] = ContractDetails(
          title: artifact.title,
          version: artifact.version,
        ).toJson();
        objectsJson[artifact.entryId] = artifact.objectSpec.toJson();
        if (artifact.domainLayerSpec.isNotEmpty) {
          domainLayersJson[artifact.entryId] = artifact.domainLayerSpec
              .toJson();
        }
      }
      nodesJson.add(<String, Object?>{
        'id': 'snap_grp_$groupName',
        'name': groupName,
        'type': childrenJson.isEmpty ? 'null' : 'object',
        'value': null,
        if (childrenJson.isNotEmpty) 'children': childrenJson,
      });
    }

    return DomainContracts.fromJson(<String, dynamic>{
      'source': sourceBuf.toString(),
      'nodes': nodesJson,
      'details': detailsJson,
      'objects': objectsJson,
      'domainLayers': domainLayersJson,
    });
  }

  static Map<String, Object?> _buildOrchestrationJson({
    required FunctionalDomain domain,
    required DomainIterationSnapshot? snapshot,
  }) {
    final orchestration =
        domain.useCaseOrchestration ?? UseCaseOrchestrationSpec.empty;
    final useCases = snapshot != null
        ? snapshot.useCases.values.toList(growable: false)
        : orchestration.useCases;
    final sagas = snapshot != null
        ? snapshot.sagas.values.toList(growable: false)
        : orchestration.sagas;

    return <String, Object?>{
      'cartography': <Map<String, Object?>>[
        for (final item in orchestration.cartography) item.toJson(),
      ],
      'useCases': <Map<String, Object?>>[
        for (final uc in useCases) _serializeUseCaseEntry(uc),
      ],
      'sagas': <Map<String, Object?>>[
        for (final saga in sagas) saga.toJson(),
      ],
    };
  }

  static Map<String, Object?> _serializeUseCaseEntry(
    ApplicationUseCaseSpec useCase,
  ) {
    final baseName = useCase.name.trim().isNotEmpty
        ? useCase.name.trim()
        : useCase.code.trim();
    return <String, Object?>{
      'spec': useCase.toJson(),
      'inputJsonSchema': PromptJsonSchemaBuilder.buildUseCaseFieldsSchema(
        title: '${baseName}Input',
        fields: useCase.triggerInputs,
        description: useCase.businessGoal,
      ),
      'outputJsonSchema': PromptJsonSchemaBuilder.buildUseCaseFieldsSchema(
        title: '${baseName}Output',
        fields: useCase.outputs,
      ),
    };
  }
}
