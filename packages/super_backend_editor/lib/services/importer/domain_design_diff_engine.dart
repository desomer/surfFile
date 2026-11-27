/// Moteur d'analyse différentielle et de réconciliation incrémentale non
/// destructive lors des imports et ré-imports d'une [DomainDesignSpec]
/// ([DomainDesignDiffEngine], [DomainReimportPreview]).
library;

import 'package:flutter/foundation.dart';

import '../../models/backend_domain_project.dart';
import '../../models/backend_overlay_config.dart';
import '../../models/domain_design_diff.dart';
import '../../models/domain_design_spec.dart';
import '../../models/json_value_utils.dart';

const Map<String, String> _slugAccentFoldMap = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ß': 'ss',
};

String _toKebabSlug(String raw, {String fallback = 'item', int maxLen = 56}) {
  final splitCamel = raw
      .trim()
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}-${m[2]}')
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (m) => '${m[1]}-${m[2]}',
      );
  final buf = StringBuffer();
  for (final rune in splitCamel.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_slugAccentFoldMap[ch] ?? ch);
  }
  var slug = buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > maxLen) {
    slug = slug.substring(0, maxLen).replaceAll(RegExp(r'-+$'), '');
  }
  return slug.isEmpty ? fallback : slug;
}

String _pluralizeKebabSlug(String kebab) {
  if (kebab.isEmpty) return 'items';
  if (kebab.endsWith('s') || kebab.endsWith('x') || kebab.endsWith('z')) {
    return kebab;
  }
  if (kebab.endsWith('ch') || kebab.endsWith('sh')) {
    return '${kebab}es';
  }
  if (kebab.length >= 2 &&
      kebab.endsWith('y') &&
      !'aeiou'.contains(kebab[kebab.length - 2])) {
    return '${kebab.substring(0, kebab.length - 1)}ies';
  }
  return '${kebab}s';
}

/// Aperçu immuable d'un ré-import Design avant application sur un [BackendDomainProject].
@immutable
class DomainReimportPreview {
  /// Crée un aperçu immuable de ré-import Design.
  const DomainReimportPreview({
    required this.previousSpec,
    required this.nextSpec,
    required this.diff,
    required this.mergedOverlay,
    required this.historyRecord,
  });

  /// Spécification Design actuellement active dans le projet.
  final DomainDesignSpec previousSpec;

  /// Nouvelle spécification Design candidate à l'import.
  final DomainDesignSpec nextSpec;

  /// Rapport différentiel détaillé entre [previousSpec] et [nextSpec].
  final DomainDesignDiff diff;

  /// Surcouche Backend réconciliée de façon non destructive.
  final BackendOverlayConfig mergedOverlay;

  /// Enregistrement d'historique prêt à être ajouté à `import_history.json`.
  final DomainImportHistoryRecord historyRecord;

  /// Vérifie la validité de tous les composants de l'aperçu.
  void validate() {
    previousSpec.validate();
    nextSpec.validate();
    diff.validate();
    mergedOverlay.validate();
    historyRecord.validate();
  }

  /// Retourne une copie modifiée.
  DomainReimportPreview copyWith({
    DomainDesignSpec? previousSpec,
    DomainDesignSpec? nextSpec,
    DomainDesignDiff? diff,
    BackendOverlayConfig? mergedOverlay,
    DomainImportHistoryRecord? historyRecord,
  }) => DomainReimportPreview(
    previousSpec: previousSpec ?? this.previousSpec,
    nextSpec: nextSpec ?? this.nextSpec,
    diff: diff ?? this.diff,
    mergedOverlay: mergedOverlay ?? this.mergedOverlay,
    historyRecord: historyRecord ?? this.historyRecord,
  );

  /// Sérialise l'aperçu de ré-import en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'previousSpec': previousSpec.toJson(),
    'nextSpec': nextSpec.toJson(),
    'diff': diff.toJson(),
    'mergedOverlay': mergedOverlay.toJson(),
    'historyRecord': historyRecord.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainReimportPreview &&
          other.previousSpec == previousSpec &&
          other.nextSpec == nextSpec &&
          other.diff == diff &&
          other.mergedOverlay == mergedOverlay &&
          other.historyRecord == historyRecord;

  @override
  int get hashCode =>
      Object.hash(previousSpec, nextSpec, diff, mergedOverlay, historyRecord);
}

/// Moteur statique de comparaison différentielle et de fusion non destructive
/// entre deux versions d'une [DomainDesignSpec] et son [BackendOverlayConfig].
abstract final class DomainDesignDiffEngine {
  /// Compare [previous] et [next] sur toutes les catégories d'artefacts Design
  /// et produit des explications lisibles en français pour chaque modification.
  static DomainDesignDiff computeDiff(
    DomainDesignSpec previous,
    DomainDesignSpec next, {
    DateTime? computedAt,
  }) {
    final entries = <DesignDiffEntry>[
      _diffDomainMeta(previous.domain, next.domain),
      ..._diffEnvironments(previous.environments, next.environments),
      ..._diffSystems(previous.systems, next.systems),
      ..._diffConfigurations(previous.configurations, next.configurations),
      ..._diffValueObjects(previous.valueObjects, next.valueObjects),
      ..._diffContracts(previous.contractEntries, next.contractEntries),
      ..._diffUseCases(previous.useCases, next.useCases),
      ..._diffSagas(previous.sagas, next.sagas),
    ];

    final diff = DomainDesignDiff(
      domainCode: next.domain.domainCode,
      computedAt: (computedAt ?? DateTime.now()).toUtc(),
      entries: entries,
    );
    diff.validate();
    return diff;
  }

  /// Fusionne de manière non destructive [currentOverlay] avec la nouvelle
  /// spécification [next], en préservant toutes les personnalisations locales,
  /// collections sur mesure, routes personnalisées, scripts QuickJS et données
  /// SQLite existantes (via le marquage `isOrphaned: true`).
  static BackendOverlayConfig reconcileOverlay({
    required DomainDesignSpec previous,
    required DomainDesignSpec next,
    required BackendOverlayConfig currentOverlay,
    DateTime? updatedAt,
  }) {
    final effectiveUpdatedAt = (updatedAt ?? DateTime.now()).toUtc();
    final server = currentOverlay.server;
    final cleanPrefix = server.apiPrefix == '/'
        ? ''
        : server.apiPrefix.replaceAll(RegExp(r'/+$'), '');

    final nextEnvIds = <String>{for (final env in next.environments) env.id};
    final resolvedActiveEnvId =
        (currentOverlay.activeEnvironmentId != null &&
            nextEnvIds.contains(currentOverlay.activeEnvironmentId))
        ? currentOverlay.activeEnvironmentId
        : (next.environments
                  .where((e) => e.status == 'active')
                  .firstOrNull
                  ?.id ??
              next.environments.firstOrNull?.id);

    final preservedEnvOverrides = <String, Map<String, String>>{
      for (final entry in currentOverlay.environmentVariableOverrides.entries)
        if (nextEnvIds.contains(entry.key)) entry.key: entry.value,
    };

    final prevModelsById = <String, ImportedContractEntry>{
      for (final model in previous.models) model.entryId: model,
    };
    final nextModelsById = <String, ImportedContractEntry>{
      for (final model in next.models) model.entryId: model,
    };

    final reconciledCollections = <BackendCollectionConfig>[];
    final usedCollectionIds = <String>{};
    final usedCollectionNames = <String>{};
    final boundContractIds = <String>{};
    final collectionIdByTechLower = <String, String>{};

    for (final col in currentOverlay.collections) {
      if (col.contractEntryId == null) {
        // Collection personnalisée créée par l'utilisateur : préservée telle quelle.
        reconciledCollections.add(col);
        usedCollectionIds.add(col.id);
        usedCollectionNames.add(col.collectionName.toLowerCase());
        continue;
      }

      final contractId = col.contractEntryId!;
      boundContractIds.add(contractId);
      final nextModel = nextModelsById[contractId];

      if (nextModel != null) {
        final prevModel = prevModelsById[contractId];
        final wasDefaultLabel =
            col.label.trim().isEmpty ||
            (prevModel != null &&
                (col.label == prevModel.effectiveLabel ||
                    col.label == prevModel.name ||
                    col.label == prevModel.technicalName));
        final updatedCol = col.copyWith(
          isOrphaned: false,
          label: wasDefaultLabel ? nextModel.effectiveLabel : col.label,
        );
        reconciledCollections.add(updatedCol);
        usedCollectionIds.add(updatedCol.id);
        usedCollectionNames.add(updatedCol.collectionName.toLowerCase());
        collectionIdByTechLower[nextModel.technicalName.toLowerCase()] =
            updatedCol.id;
        collectionIdByTechLower[nextModel.name.toLowerCase()] = updatedCol.id;
      } else {
        // Modèle Design retiré : conservation stricte en orphelin (données SQLite préservées).
        final orphanedCol = col.copyWith(isOrphaned: true);
        reconciledCollections.add(orphanedCol);
        usedCollectionIds.add(orphanedCol.id);
        usedCollectionNames.add(orphanedCol.collectionName.toLowerCase());
      }
    }

    // Amorçage des nouveaux modèles persistants absents de l'overlay courant.
    final newlyBootstrappedModels =
        <({ImportedContractEntry model, BackendCollectionConfig collection})>[];
    for (final model in next.models) {
      if (boundContractIds.contains(model.entryId)) continue;

      var colId = model.entryId;
      var idSuffix = 2;
      while (!usedCollectionIds.add(colId)) {
        colId = '${model.entryId}_$idSuffix';
        idSuffix++;
      }

      final baseSlug = _pluralizeKebabSlug(
        _toKebabSlug(model.technicalName, fallback: 'entities'),
      );
      var collectionName = baseSlug;
      var nameSuffix = 2;
      while (!usedCollectionNames.add(collectionName.toLowerCase())) {
        collectionName = '$baseSlug-$nameSuffix';
        nameSuffix++;
      }

      final hasExplicitPolicy =
          model.domainLayerJson['persistencePolicy'] is Map ||
          model.domainLayerJson['persistence_policy_behaviors'] is Map;
      final policy = model.persistencePolicy;
      final deletionMode = hasExplicitPolicy
          ? BackendDeletionMode.fromJson(policy['deletionStrategy'])
          : BackendDeletionMode.hardDelete;
      final concurrencyMode = hasExplicitPolicy
          ? BackendConcurrencyMode.fromJson(policy['concurrencyStrategy'])
          : BackendConcurrencyMode.none;

      final newCol = BackendCollectionConfig(
        id: colId,
        contractEntryId: model.entryId,
        collectionName: collectionName,
        label: model.effectiveLabel,
        deletionMode: deletionMode,
        concurrencyMode: concurrencyMode,
      );
      reconciledCollections.add(newCol);
      collectionIdByTechLower[model.technicalName.toLowerCase()] = newCol.id;
      collectionIdByTechLower[model.name.toLowerCase()] = newCol.id;
      newlyBootstrappedModels.add((model: model, collection: newCol));
    }

    final collectionsById = <String, BackendCollectionConfig>{
      for (final col in reconciledCollections) col.id: col,
    };
    final prevUseCasesById = <String, ImportedUseCaseSpec>{
      for (final uc in previous.useCases) uc.id: uc,
    };
    final nextUseCasesById = <String, ImportedUseCaseSpec>{
      for (final uc in next.useCases) uc.id: uc,
    };

    final reconciledEndpoints = <BackendEndpointConfig>[];
    final usedEndpointIds = <String>{};
    final usedMethodPaths = <String>{};
    final coveredScrudCollectionIds = <String>{};
    final coveredUseCaseIds = <String>{};

    for (final ep in currentOverlay.endpoints) {
      if (ep.kind == BackendEndpointKind.custom) {
        reconciledEndpoints.add(ep);
        usedEndpointIds.add(ep.id);
        usedMethodPaths.add('${ep.method}:${ep.path}');
        continue;
      }

      if (ep.useCaseId != null) {
        final ucId = ep.useCaseId!;
        coveredUseCaseIds.add(ucId);
        final nextUc = nextUseCasesById[ucId];
        if (nextUc != null) {
          final prevUc = prevUseCasesById[ucId];
          final wasDefaultSummary =
              ep.summary.trim().isEmpty ||
              (prevUc != null && ep.summary == prevUc.effectiveTitle);
          final inferredColId =
              ep.collectionId ??
              (nextUc.targetAggregate.trim().isEmpty
                  ? null
                  : collectionIdByTechLower[nextUc.targetAggregate
                        .trim()
                        .toLowerCase()]);
          final updatedEp = ep.copyWith(
            isOrphaned: false,
            summary: wasDefaultSummary ? nextUc.effectiveTitle : ep.summary,
            collectionId: inferredColId,
          );
          reconciledEndpoints.add(updatedEp);
          usedEndpointIds.add(updatedEp.id);
          usedMethodPaths.add('${updatedEp.method}:${updatedEp.path}');
        } else {
          final orphanedEp = ep.copyWith(isOrphaned: true);
          reconciledEndpoints.add(orphanedEp);
          usedEndpointIds.add(orphanedEp.id);
          usedMethodPaths.add('${orphanedEp.method}:${orphanedEp.path}');
        }
        continue;
      }

      if (ep.collectionId != null) {
        coveredScrudCollectionIds.add(ep.collectionId!);
        final targetCol = collectionsById[ep.collectionId!];
        final isTargetOrphaned = targetCol == null || targetCol.isOrphaned;
        final prevModel = targetCol?.contractEntryId != null
            ? prevModelsById[targetCol!.contractEntryId!]
            : null;
        final wasDefaultScrudSummary =
            !isTargetOrphaned &&
            (ep.summary.trim().isEmpty ||
                (prevModel != null &&
                    ep.summary == 'SCRUD ${prevModel.effectiveLabel}'));
        final updatedEp = ep.copyWith(
          isOrphaned: isTargetOrphaned,
          summary: wasDefaultScrudSummary
              ? 'SCRUD ${targetCol.label}'
              : ep.summary,
        );
        reconciledEndpoints.add(updatedEp);
        usedEndpointIds.add(updatedEp.id);
        usedMethodPaths.add('${updatedEp.method}:${updatedEp.path}');
        continue;
      }

      reconciledEndpoints.add(ep);
      usedEndpointIds.add(ep.id);
      usedMethodPaths.add('${ep.method}:${ep.path}');
    }

    // Endpoints SCRUD pour les modèles nouvellement provisionnés.
    for (final entry in newlyBootstrappedModels) {
      final model = entry.model;
      final col = entry.collection;
      if (coveredScrudCollectionIds.contains(col.id)) continue;

      var epId = 'ep_scrud_${model.entryId}';
      var idSuffix = 2;
      while (!usedEndpointIds.add(epId)) {
        epId = 'ep_scrud_${model.entryId}_$idSuffix';
        idSuffix++;
      }

      final baseRoute = '$cleanPrefix/${col.collectionName}';
      var routePath = baseRoute;
      var routeSuffix = 2;
      while (!usedMethodPaths.add('GET:$routePath')) {
        routePath = '$baseRoute-$routeSuffix';
        routeSuffix++;
      }

      reconciledEndpoints.add(
        BackendEndpointConfig(
          id: epId,
          kind: BackendEndpointKind.scrudCollection,
          method: 'GET',
          path: routePath,
          summary: 'SCRUD ${col.label}',
          collectionId: col.id,
          inputContractEntryId: model.entryId,
          outputContractEntryId: model.entryId,
        ),
      );
    }

    // Endpoints CQRS pour les nouveaux Use Cases.
    for (final uc in next.useCases) {
      if (coveredUseCaseIds.contains(uc.id)) continue;

      var epId = 'ep_uc_${uc.id}';
      var idSuffix = 2;
      while (!usedEndpointIds.add(epId)) {
        epId = 'ep_uc_${uc.id}_$idSuffix';
        idSuffix++;
      }

      final isQuery = uc.isQuery;
      final method = isQuery ? 'GET' : 'POST';
      final segment = isQuery ? 'queries' : 'commands';
      final baseSlug = _toKebabSlug(
        uc.name.trim().isNotEmpty ? uc.name : uc.code,
        fallback: isQuery ? 'query' : 'command',
      );
      final baseRoute = '$cleanPrefix/$segment/$baseSlug';
      var routePath = baseRoute;
      var routeSuffix = 2;
      while (!usedMethodPaths.add('$method:$routePath')) {
        routePath = '$baseRoute-$routeSuffix';
        routeSuffix++;
      }

      final targetAggLower = uc.targetAggregate.trim().toLowerCase();
      final matchedCollectionId = targetAggLower.isEmpty
          ? null
          : collectionIdByTechLower[targetAggLower];

      reconciledEndpoints.add(
        BackendEndpointConfig(
          id: epId,
          kind: isQuery
              ? BackendEndpointKind.cqrsQuery
              : BackendEndpointKind.cqrsCommand,
          method: method,
          path: routePath,
          summary: uc.effectiveTitle,
          collectionId: matchedCollectionId,
          useCaseId: uc.id,
        ),
      );
    }

    final endpointsById = <String, BackendEndpointConfig>{
      for (final ep in reconciledEndpoints) ep.id: ep,
    };

    // Liaisons de scripts QuickJS : intégralement conservées, marquées orphelines si la cible disparaît.
    final reconciledScripts = <BackendScriptBinding>[
      for (final script in currentOverlay.scripts)
        script.copyWith(
          isOrphaned: !_doesScriptTargetExistInNext(
            script: script,
            next: next,
            collectionsById: collectionsById,
            endpointsById: endpointsById,
          ),
        ),
    ];

    final merged = BackendOverlayConfig(
      domainCode: next.domain.domainCode,
      activeEnvironmentId: resolvedActiveEnvId,
      server: server,
      collections: reconciledCollections,
      endpoints: reconciledEndpoints,
      scripts: reconciledScripts,
      environmentVariableOverrides: preservedEnvOverrides,
      superDesignerExportPath: currentOverlay.superDesignerExportPath,
      updatedAt: effectiveUpdatedAt,
    );
    merged.validate();
    return merged;
  }

  /// Prépare un aperçu complet de ré-import ([DomainReimportPreview]) sans muter [currentProject].
  static DomainReimportPreview previewReimport({
    required BackendDomainProject currentProject,
    required DomainDesignSpec nextSpec,
    required String sourceLabel,
    String notes = '',
    DateTime? importedAt,
  }) {
    final effectiveTime = (importedAt ?? DateTime.now()).toUtc();
    final diff = computeDiff(
      currentProject.designSpec,
      nextSpec,
      computedAt: effectiveTime,
    );
    final mergedOverlay = reconcileOverlay(
      previous: currentProject.designSpec,
      next: nextSpec,
      currentOverlay: currentProject.overlay,
      updatedAt: effectiveTime,
    );

    final existingIds = <String>{
      for (final rec in currentProject.importHistory) rec.id,
    };
    final baseId = 'imp_${effectiveTime.millisecondsSinceEpoch}';
    var recordId = baseId;
    var suffix = currentProject.importHistory.length + 1;
    while (!existingIds.add(recordId)) {
      recordId = '${baseId}_$suffix';
      suffix++;
    }

    final effectiveLabel = sourceLabel.trim().isNotEmpty
        ? sourceLabel.trim()
        : nextSpec.domain.domainCode;
    final historyRecord = DomainImportHistoryRecord(
      id: recordId,
      importedAt: effectiveTime,
      sourceKind: nextSpec.sourceKind,
      sourceLabel: effectiveLabel,
      snapshotIteration: nextSpec.snapshotMeta?.iterationNumber,
      addedCount: diff.addedCount,
      modifiedCount: diff.modifiedCount,
      removedCount: diff.removedCount,
      notes: notes,
    );

    final preview = DomainReimportPreview(
      previousSpec: currentProject.designSpec,
      nextSpec: nextSpec,
      diff: diff,
      mergedOverlay: mergedOverlay,
      historyRecord: historyRecord,
    );
    preview.validate();
    return preview;
  }

  /// Crée un nouveau [BackendDomainProject] initialisé à partir d'un premier import [spec].
  static BackendDomainProject applyInitialImport({
    required DomainDesignSpec spec,
    required String sourceLabel,
    String notes = '',
    DateTime? importedAt,
  }) {
    final effectiveTime = (importedAt ?? DateTime.now()).toUtc();
    final overlay = BackendOverlayConfig.bootstrapFromDesign(
      spec,
      updatedAt: effectiveTime,
    );
    final totalAdded =
        spec.environments.length +
        spec.systems.length +
        spec.configurations.length +
        spec.valueObjects.length +
        spec.contractEntries.length +
        spec.useCases.length +
        spec.sagas.length;

    final effectiveLabel = sourceLabel.trim().isNotEmpty
        ? sourceLabel.trim()
        : spec.domain.domainCode;
    final historyRecord = DomainImportHistoryRecord(
      id: 'imp_${effectiveTime.millisecondsSinceEpoch}_1',
      importedAt: effectiveTime,
      sourceKind: spec.sourceKind,
      sourceLabel: effectiveLabel,
      snapshotIteration: spec.snapshotMeta?.iterationNumber,
      addedCount: totalAdded,
      modifiedCount: 0,
      removedCount: 0,
      notes: notes,
    );

    final project = BackendDomainProject(
      designSpec: spec,
      overlay: overlay,
      importHistory: <DomainImportHistoryRecord>[historyRecord],
    );
    project.validate();
    return project;
  }

  /// Applique un ré-import incrémental non destructif sur [currentProject] en
  /// conservant l'historique d'import enrichi et les secrets locaux de test.
  static BackendDomainProject applyReimport({
    required BackendDomainProject currentProject,
    required DomainDesignSpec nextSpec,
    required String sourceLabel,
    String notes = '',
    DateTime? importedAt,
  }) {
    final preview = previewReimport(
      currentProject: currentProject,
      nextSpec: nextSpec,
      sourceLabel: sourceLabel,
      notes: notes,
      importedAt: importedAt,
    );
    final updated = BackendDomainProject(
      designSpec: nextSpec,
      overlay: preview.mergedOverlay,
      importHistory: <DomainImportHistoryRecord>[
        ...currentProject.importHistory,
        preview.historyRecord,
      ],
      localSecretValues: currentProject.localSecretValues,
    );
    updated.validate();
    return updated;
  }

  static bool _doesScriptTargetExistInNext({
    required BackendScriptBinding script,
    required DomainDesignSpec next,
    required Map<String, BackendCollectionConfig> collectionsById,
    required Map<String, BackendEndpointConfig> endpointsById,
  }) {
    switch (script.targetKind) {
      case BackendScriptTargetKind.modelInvariant:
      case BackendScriptTargetKind.aggregateCommand:
        if (next.findContractById(script.targetId) != null) return true;
        final col = collectionsById[script.targetId];
        return col != null && !col.isOrphaned;
      case BackendScriptTargetKind.useCase:
        return next.findUseCaseById(script.targetId) != null;
      case BackendScriptTargetKind.saga:
        return next.findSagaById(script.targetId) != null;
      case BackendScriptTargetKind.customEndpoint:
        final ep = endpointsById[script.targetId];
        return ep != null && !ep.isOrphaned;
    }
  }

  static DesignDiffEntry _diffDomainMeta(
    ImportedDomainIdentity prev,
    ImportedDomainIdentity next,
  ) {
    final details = <String>[];
    if (prev.name != next.name) {
      details.add(
        'Nom du domaine modifié : « ${prev.name} » → « ${next.name} ».',
      );
    }
    if (prev.domainCode != next.domainCode) {
      details.add(
        'Code du domaine modifié : ${prev.domainCode} → ${next.domainCode}.',
      );
    }
    if (prev.description != next.description) {
      details.add('Description fonctionnelle du domaine mise à jour.');
    }
    if (prev.isActive != next.isActive) {
      details.add(
        'Statut d’activité modifié : ${prev.isActive ? 'actif' : 'inactif'} → '
        '${next.isActive ? 'actif' : 'inactif'}.',
      );
    }
    if (prev.techStackId != next.techStackId ||
        prev.techStack != next.techStack) {
      final prevStack = prev.techStack?.name ?? prev.techStackId ?? 'aucune';
      final nextStack = next.techStack?.name ?? next.techStackId ?? 'aucune';
      details.add('Stack technique modifiée : $prevStack → $nextStack.');
    }

    return DesignDiffEntry(
      category: DesignDiffItemCategory.domainMeta,
      changeKind: details.isEmpty
          ? DesignDiffChangeKind.unchanged
          : DesignDiffChangeKind.modified,
      itemId: next.id,
      itemName: next.name,
      details: details,
    );
  }

  static List<DesignDiffEntry> _diffEnvironments(
    List<ImportedEnvironmentSpec> previous,
    List<ImportedEnvironmentSpec> next,
  ) {
    final matchedPairs = _matchItems<ImportedEnvironmentSpec>(
      previous: previous,
      next: next,
      primaryKeyOf: (e) => e.id,
      secondaryKeyOf: (e) => e.environmentCode.toLowerCase(),
    );

    final entries = <DesignDiffEntry>[];
    for (final pair in matchedPairs) {
      final prev = pair.previous;
      final nxt = pair.next;
      if (prev == null && nxt != null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.environment,
            changeKind: DesignDiffChangeKind.added,
            itemId: nxt.id,
            itemName: nxt.name,
            details: <String>[
              'Environnement « ${nxt.environmentCode} » ajouté (${nxt.status}).',
            ],
          ),
        );
      } else if (prev != null && nxt == null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.environment,
            changeKind: DesignDiffChangeKind.removed,
            itemId: prev.id,
            itemName: prev.name,
            details: <String>[
              'Environnement « ${prev.environmentCode} » supprimé.',
            ],
          ),
        );
      } else if (prev != null && nxt != null) {
        final details = <String>[];
        if (prev.environmentCode != nxt.environmentCode) {
          details.add(
            'Code environnement modifié : ${prev.environmentCode} → ${nxt.environmentCode}.',
          );
        }
        if (prev.name != nxt.name) {
          details.add('Libellé modifié : « ${prev.name} » → « ${nxt.name} ».');
        }
        if (prev.status != nxt.status) {
          details.add('Statut modifié : ${prev.status} → ${nxt.status}.');
        }
        if (prev.description != nxt.description) {
          details.add('Description de l’environnement mise à jour.');
        }
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.environment,
            changeKind: details.isEmpty
                ? DesignDiffChangeKind.unchanged
                : DesignDiffChangeKind.modified,
            itemId: nxt.id,
            itemName: nxt.name,
            details: details,
          ),
        );
      }
    }
    return entries;
  }

  static List<DesignDiffEntry> _diffSystems(
    List<ImportedSystemSpec> previous,
    List<ImportedSystemSpec> next,
  ) {
    final matchedPairs = _matchItems<ImportedSystemSpec>(
      previous: previous,
      next: next,
      primaryKeyOf: (s) => s.id,
      secondaryKeyOf: (s) => s.serviceCode.toLowerCase(),
    );

    final entries = <DesignDiffEntry>[];
    for (final pair in matchedPairs) {
      final prev = pair.previous;
      final nxt = pair.next;
      if (prev == null && nxt != null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.system,
            changeKind: DesignDiffChangeKind.added,
            itemId: nxt.id,
            itemName: nxt.name,
            details: <String>[
              'Système « ${nxt.serviceCode} » (${nxt.kind}) ajouté.',
            ],
          ),
        );
      } else if (prev != null && nxt == null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.system,
            changeKind: DesignDiffChangeKind.removed,
            itemId: prev.id,
            itemName: prev.name,
            details: <String>['Système « ${prev.serviceCode} » supprimé.'],
          ),
        );
      } else if (prev != null && nxt != null) {
        final details = <String>[];
        if (prev.serviceCode != nxt.serviceCode) {
          details.add(
            'Code service modifié : ${prev.serviceCode} → ${nxt.serviceCode}.',
          );
        }
        if (prev.name != nxt.name) {
          details.add('Nom modifié : « ${prev.name} » → « ${nxt.name} ».');
        }
        if (prev.kind != nxt.kind) {
          details.add('Catégorie modifiée : ${prev.kind} → ${nxt.kind}.');
        }
        if (prev.isActive != nxt.isActive) {
          details.add(
            'État actif modifié : ${prev.isActive} → ${nxt.isActive}.',
          );
        }
        if (prev.techStackId != nxt.techStackId) {
          details.add(
            'Stack technique modifiée : ${prev.techStackId ?? 'aucune'} → '
            '${nxt.techStackId ?? 'aucune'}.',
          );
        }
        if (prev.vendor != nxt.vendor) {
          details.add(
            'Fournisseur modifié : « ${prev.vendor} » → « ${nxt.vendor} ».',
          );
        }
        if (prev.description != nxt.description) {
          details.add('Description du système mise à jour.');
        }
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.system,
            changeKind: details.isEmpty
                ? DesignDiffChangeKind.unchanged
                : DesignDiffChangeKind.modified,
            itemId: nxt.id,
            itemName: nxt.name,
            details: details,
          ),
        );
      }
    }
    return entries;
  }

  static List<DesignDiffEntry> _diffConfigurations(
    List<ImportedConfigurationSpec> previous,
    List<ImportedConfigurationSpec> next,
  ) {
    String compositeKey(ImportedConfigurationSpec c) =>
        '${c.environmentId}\u0000${c.microserviceId ?? ''}\u0000${c.configKey}';

    final matchedPairs = _matchItems<ImportedConfigurationSpec>(
      previous: previous,
      next: next,
      primaryKeyOf: (c) => c.id,
      secondaryKeyOf: compositeKey,
    );

    final entries = <DesignDiffEntry>[];
    for (final pair in matchedPairs) {
      final prev = pair.previous;
      final nxt = pair.next;
      if (prev == null && nxt != null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.configuration,
            changeKind: DesignDiffChangeKind.added,
            itemId: nxt.id,
            itemName: nxt.configKey,
            details: <String>[
              nxt.isSecret
                  ? 'Déclaration de secret « ${nxt.configKey} » ajoutée.'
                  : 'Variable « ${nxt.configKey} » ajoutée.',
            ],
          ),
        );
      } else if (prev != null && nxt == null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.configuration,
            changeKind: DesignDiffChangeKind.removed,
            itemId: prev.id,
            itemName: prev.configKey,
            details: <String>[
              'Clé de configuration « ${prev.configKey} » supprimée.',
            ],
          ),
        );
      } else if (prev != null && nxt != null) {
        final details = <String>[];
        if (prev.configKey != nxt.configKey) {
          details.add('Clé renommée : ${prev.configKey} → ${nxt.configKey}.');
        }
        if (prev.entryType != nxt.entryType) {
          details.add(
            'Classification modifiée : ${prev.entryType} → ${nxt.entryType}.',
          );
        }
        if (!nxt.isSecret && prev.plainValue != nxt.plainValue) {
          details.add('Valeur en clair mise à jour.');
        }
        if (prev.environmentId != nxt.environmentId ||
            prev.microserviceId != nxt.microserviceId) {
          details.add('Cible d’environnement ou de microservice modifiée.');
        }
        if (prev.isInitialized != nxt.isInitialized) {
          details.add(
            'État d’initialisation modifié : ${prev.isInitialized} → ${nxt.isInitialized}.',
          );
        }
        if (prev.description != nxt.description) {
          details.add('Description de la clé mise à jour.');
        }
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.configuration,
            changeKind: details.isEmpty
                ? DesignDiffChangeKind.unchanged
                : DesignDiffChangeKind.modified,
            itemId: nxt.id,
            itemName: nxt.configKey,
            details: details,
          ),
        );
      }
    }
    return entries;
  }

  static List<DesignDiffEntry> _diffValueObjects(
    List<ImportedValueObjectSpec> previous,
    List<ImportedValueObjectSpec> next,
  ) {
    final matchedPairs = _matchItems<ImportedValueObjectSpec>(
      previous: previous,
      next: next,
      primaryKeyOf: (vo) => vo.id,
      secondaryKeyOf: (vo) => vo.technicalName.toLowerCase(),
    );

    final entries = <DesignDiffEntry>[];
    for (final pair in matchedPairs) {
      final prev = pair.previous;
      final nxt = pair.next;
      if (prev == null && nxt != null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.valueObject,
            changeKind: DesignDiffChangeKind.added,
            itemId: nxt.id,
            itemName: nxt.technicalName,
            nextVersion: nxt.version,
            details: <String>[
              'Value Object « ${nxt.technicalName} » (${nxt.scope}, ${nxt.kind}) ajouté.',
            ],
          ),
        );
      } else if (prev != null && nxt == null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.valueObject,
            changeKind: DesignDiffChangeKind.removed,
            itemId: prev.id,
            itemName: prev.technicalName,
            previousVersion: prev.version,
            details: <String>[
              'Value Object « ${prev.technicalName} » supprimé.',
            ],
          ),
        );
      } else if (prev != null && nxt != null) {
        final details = <String>[];
        if (prev.version != nxt.version) {
          details.add('Version évoluée : ${prev.version} → ${nxt.version}.');
        }
        if (prev.technicalName != nxt.technicalName || prev.name != nxt.name) {
          details.add(
            'Identité modifiée : ${prev.technicalName} (${prev.name}) → '
            '${nxt.technicalName} (${nxt.name}).',
          );
        }
        if (prev.scope != nxt.scope) {
          details.add('Portée modifiée : ${prev.scope} → ${nxt.scope}.');
        }
        if (prev.kind != nxt.kind || prev.primitiveType != nxt.primitiveType) {
          details.add(
            'Forme ou type sous-jacent modifié : '
            '${prev.kind}${prev.primitiveType != null ? '(${prev.primitiveType})' : ''} → '
            '${nxt.kind}${nxt.primitiveType != null ? '(${nxt.primitiveType})' : ''}.',
          );
        }
        if (prev.description != nxt.description) {
          details.add('Description métier mise à jour.');
        }
        _appendNamedMapListDiff(
          details: details,
          previousList: prev.fields,
          nextList: nxt.fields,
          singularAdded: 'Champ composite ajouté',
          singularRemoved: 'Champ composite supprimé',
          singularModified: 'Champ composite modifié',
        );
        if (!deepJsonEquals(prev.jsonSchema, nxt.jsonSchema)) {
          details.add('JSON Schema Draft 2020-12 du Value Object mis à jour.');
        } else if (!deepJsonEquals(prev.specJson, nxt.specJson) ||
            !deepJsonEquals(prev.examples, nxt.examples)) {
          details.add(
            'Règles, contraintes ou exemples du Value Object mis à jour.',
          );
        }
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.valueObject,
            changeKind: details.isEmpty
                ? DesignDiffChangeKind.unchanged
                : DesignDiffChangeKind.modified,
            itemId: nxt.id,
            itemName: nxt.technicalName,
            previousVersion: prev.version,
            nextVersion: nxt.version,
            details: details,
          ),
        );
      }
    }
    return entries;
  }

  static List<DesignDiffEntry> _diffContracts(
    List<ImportedContractEntry> previous,
    List<ImportedContractEntry> next,
  ) {
    final matchedPairs = _matchItems<ImportedContractEntry>(
      previous: previous,
      next: next,
      primaryKeyOf: (c) => c.entryId,
    );

    final entries = <DesignDiffEntry>[];
    for (final pair in matchedPairs) {
      final prev = pair.previous;
      final nxt = pair.next;
      if (prev == null && nxt != null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.contract,
            changeKind: DesignDiffChangeKind.added,
            itemId: nxt.entryId,
            itemName: nxt.technicalName,
            nextVersion: nxt.version,
            details: <String>[
              'Contrat « ${nxt.technicalName} » (${nxt.dslType}) ajouté dans ${nxt.groupName}.',
            ],
          ),
        );
      } else if (prev != null && nxt == null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.contract,
            changeKind: DesignDiffChangeKind.removed,
            itemId: prev.entryId,
            itemName: prev.technicalName,
            previousVersion: prev.version,
            details: <String>[
              'Contrat « ${prev.technicalName} » (${prev.dslType}) supprimé.',
            ],
          ),
        );
      } else if (prev != null && nxt != null) {
        final details = <String>[];
        if (prev.version != nxt.version) {
          details.add('Version évoluée : ${prev.version} → ${nxt.version}.');
        }
        if (prev.dslType != nxt.dslType) {
          details.add('Type DSL modifié : ${prev.dslType} → ${nxt.dslType}.');
        }
        if (prev.groupName != nxt.groupName) {
          details.add(
            'Rubrique DSL déplacée : ${prev.groupName} → ${nxt.groupName}.',
          );
        }
        if (prev.name != nxt.name ||
            prev.technicalName != nxt.technicalName ||
            prev.title != nxt.title) {
          details.add(
            'Nom ou titre modifié : « ${prev.effectiveLabel} » (${prev.technicalName}) → '
            '« ${nxt.effectiveLabel} » (${nxt.technicalName}).',
          );
        }

        _appendNamedMapListDiff(
          details: details,
          previousList: prev.attributes,
          nextList: nxt.attributes,
          singularAdded: 'Attribut ajouté',
          singularRemoved: 'Attribut supprimé',
          singularModified: 'Attribut modifié',
        );
        _appendNamedMapListDiff(
          details: details,
          previousList: prev.relations,
          nextList: nxt.relations,
          singularAdded: 'Relation ajoutée',
          singularRemoved: 'Relation supprimée',
          singularModified: 'Relation modifiée',
        );

        if (!deepJsonEquals(prev.lifecycleStates, nxt.lifecycleStates) ||
            !deepJsonEquals(
              prev.lifecycleTransitions,
              nxt.lifecycleTransitions,
            )) {
          details.add('Cycle de vie (états ou transitions) mis à jour.');
        }
        if (prev.description != nxt.description ||
            prev.isAggregateRoot != nxt.isAggregateRoot) {
          details.add('Métadonnées de l’objet métier mises à jour.');
        }
        if (!deepJsonEquals(prev.jsonSchema, nxt.jsonSchema)) {
          details.add('JSON Schema Draft 2020-12 mis à jour.');
        }
        if (!deepJsonEquals(prev.domainLayerJson, nxt.domainLayerJson)) {
          _appendDomainLayerDiff(details, prev, nxt);
        }
        if (!mapEquals(prev.states, nxt.states)) {
          details.add('États d’avancement du contrat mis à jour.');
        }
        if (details.isEmpty &&
            !deepJsonEquals(prev.objectSpecJson, nxt.objectSpecJson)) {
          details.add('Spécification de l’objet métier modifiée.');
        }

        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.contract,
            changeKind: details.isEmpty
                ? DesignDiffChangeKind.unchanged
                : DesignDiffChangeKind.modified,
            itemId: nxt.entryId,
            itemName: nxt.technicalName,
            previousVersion: prev.version,
            nextVersion: nxt.version,
            details: details,
          ),
        );
      }
    }
    return entries;
  }

  static void _appendDomainLayerDiff(
    List<String> details,
    ImportedContractEntry prev,
    ImportedContractEntry nxt,
  ) {
    final changedSections = <String>[];
    if (!deepJsonEquals(prev.invariants, nxt.invariants)) {
      changedSections.add('invariants');
    }
    if (!deepJsonEquals(prev.stateChangingMethods, nxt.stateChangingMethods)) {
      changedSections.add('commandes stateChanging');
    }
    if (!deepJsonEquals(prev.queryMethods, nxt.queryMethods)) {
      changedSections.add('méthodes Query');
    }
    if (!deepJsonEquals(prev.policyServices, nxt.policyServices)) {
      changedSections.add('Policy Services');
    }
    if (!deepJsonEquals(prev.factories, nxt.factories)) {
      changedSections.add('Factories');
    }
    if (!deepJsonEquals(prev.domainEvents, nxt.domainEvents)) {
      changedSections.add('Domain Events');
    }
    if (!deepJsonEquals(prev.persistencePolicy, nxt.persistencePolicy)) {
      changedSections.add('politique de persistance');
    }
    if (changedSections.isEmpty) {
      details.add('Couche Domain hexagonale mise à jour.');
    } else {
      details.add('Couche Domain modifiée (${changedSections.join(', ')}).');
    }
  }

  static List<DesignDiffEntry> _diffUseCases(
    List<ImportedUseCaseSpec> previous,
    List<ImportedUseCaseSpec> next,
  ) {
    final matchedPairs = _matchItems<ImportedUseCaseSpec>(
      previous: previous,
      next: next,
      primaryKeyOf: (uc) => uc.id,
    );

    final entries = <DesignDiffEntry>[];
    for (final pair in matchedPairs) {
      final prev = pair.previous;
      final nxt = pair.next;
      if (prev == null && nxt != null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.useCase,
            changeKind: DesignDiffChangeKind.added,
            itemId: nxt.id,
            itemName: nxt.name,
            nextVersion: nxt.version,
            details: <String>[
              'Use Case ${nxt.code} « ${nxt.effectiveTitle} » (${nxt.cqrsType}) ajouté.',
            ],
          ),
        );
      } else if (prev != null && nxt == null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.useCase,
            changeKind: DesignDiffChangeKind.removed,
            itemId: prev.id,
            itemName: prev.name,
            previousVersion: prev.version,
            details: <String>[
              'Use Case ${prev.code} « ${prev.effectiveTitle} » supprimé.',
            ],
          ),
        );
      } else if (prev != null && nxt != null) {
        final details = <String>[];
        if (prev.version != nxt.version) {
          details.add('Version évoluée : ${prev.version} → ${nxt.version}.');
        }
        if (prev.cqrsType != nxt.cqrsType) {
          details.add(
            'Type CQRS modifié : ${prev.cqrsType} → ${nxt.cqrsType}.',
          );
        }
        if (prev.code != nxt.code ||
            prev.name != nxt.name ||
            prev.title != nxt.title) {
          details.add(
            'Identité modifiée : ${prev.code} ${prev.name} → ${nxt.code} ${nxt.name}.',
          );
        }
        if (prev.targetAggregate != nxt.targetAggregate) {
          details.add(
            'Agrégat cible modifié : « ${prev.targetAggregate} » → « ${nxt.targetAggregate} ».',
          );
        }
        if (prev.boundedContext != nxt.boundedContext ||
            prev.businessGoal != nxt.businessGoal ||
            prev.inboundPort != nxt.inboundPort) {
          details.add('Contexte, objectif métier ou port entrant mis à jour.');
        }

        final prevInputs = _normalizeUseCaseFieldList(
          prev.specJson['triggerInputs'],
          prev.inputJsonSchema,
        );
        final nextInputs = _normalizeUseCaseFieldList(
          nxt.specJson['triggerInputs'],
          nxt.inputJsonSchema,
        );
        _appendNamedMapListDiff(
          details: details,
          previousList: prevInputs,
          nextList: nextInputs,
          singularAdded: 'Paramètre d’entrée ajouté',
          singularRemoved: 'Paramètre d’entrée supprimé',
          singularModified: 'Paramètre d’entrée modifié',
        );
        if (prevInputs.isEmpty &&
            nextInputs.isEmpty &&
            !deepJsonEquals(prev.inputJsonSchema, nxt.inputJsonSchema)) {
          details.add('Schéma JSON d’entrée (inputJsonSchema) mis à jour.');
        }

        final prevOutputs = _normalizeUseCaseFieldList(
          prev.specJson['outputs'],
          prev.outputJsonSchema,
        );
        final nextOutputs = _normalizeUseCaseFieldList(
          nxt.specJson['outputs'],
          nxt.outputJsonSchema,
        );
        _appendNamedMapListDiff(
          details: details,
          previousList: prevOutputs,
          nextList: nextOutputs,
          singularAdded: 'Champ de sortie ajouté',
          singularRemoved: 'Champ de sortie supprimé',
          singularModified: 'Champ de sortie modifié',
        );
        if (prevOutputs.isEmpty &&
            nextOutputs.isEmpty &&
            !deepJsonEquals(prev.outputJsonSchema, nxt.outputJsonSchema)) {
          details.add('Schéma JSON de sortie (outputJsonSchema) mis à jour.');
        }

        _appendStringListDiff(
          details: details,
          previousList: prev.businessRules,
          nextList: nxt.businessRules,
          label: 'Règles métier',
        );
        _appendStringListDiff(
          details: details,
          previousList: prev.outboundPorts,
          nextList: nxt.outboundPorts,
          label: 'Ports sortants',
        );
        _appendStringListDiff(
          details: details,
          previousList: prev.emittedEvents,
          nextList: nxt.emittedEvents,
          label: 'Événements émis',
        );
        _appendStringListDiff(
          details: details,
          previousList: prev.possibleErrors,
          nextList: nxt.possibleErrors,
          label: 'Erreurs possibles',
        );
        if (!listEquals(prev.detailedProcess, nxt.detailedProcess)) {
          details.add('Processus détaillé d’orchestration mis à jour.');
        }
        if (!deepJsonEquals(prev.scenarios, nxt.scenarios)) {
          details.add('Scénarios Given / When / Then mis à jour.');
        }
        if (details.isEmpty &&
            (!deepJsonEquals(prev.specJson, nxt.specJson) ||
                !deepJsonEquals(prev.inputJsonSchema, nxt.inputJsonSchema) ||
                !deepJsonEquals(prev.outputJsonSchema, nxt.outputJsonSchema))) {
          details.add('Spécification détaillée du Use Case modifiée.');
        }

        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.useCase,
            changeKind: details.isEmpty
                ? DesignDiffChangeKind.unchanged
                : DesignDiffChangeKind.modified,
            itemId: nxt.id,
            itemName: nxt.name,
            previousVersion: prev.version,
            nextVersion: nxt.version,
            details: details,
          ),
        );
      }
    }
    return entries;
  }

  static List<DesignDiffEntry> _diffSagas(
    List<ImportedSagaSpec> previous,
    List<ImportedSagaSpec> next,
  ) {
    final matchedPairs = _matchItems<ImportedSagaSpec>(
      previous: previous,
      next: next,
      primaryKeyOf: (s) => s.id,
    );

    final entries = <DesignDiffEntry>[];
    for (final pair in matchedPairs) {
      final prev = pair.previous;
      final nxt = pair.next;
      if (prev == null && nxt != null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.saga,
            changeKind: DesignDiffChangeKind.added,
            itemId: nxt.id,
            itemName: nxt.name,
            nextVersion: nxt.version,
            details: <String>[
              'Saga ${nxt.code} « ${nxt.title} » (${nxt.coordinationMode}) ajoutée.',
            ],
          ),
        );
      } else if (prev != null && nxt == null) {
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.saga,
            changeKind: DesignDiffChangeKind.removed,
            itemId: prev.id,
            itemName: prev.name,
            previousVersion: prev.version,
            details: <String>['Saga ${prev.code} « ${prev.title} » supprimée.'],
          ),
        );
      } else if (prev != null && nxt != null) {
        final details = <String>[];
        if (prev.version != nxt.version) {
          details.add('Version évoluée : ${prev.version} → ${nxt.version}.');
        }
        if (prev.code != nxt.code ||
            prev.name != nxt.name ||
            prev.title != nxt.title) {
          details.add(
            'Identité modifiée : ${prev.code} ${prev.name} → ${nxt.code} ${nxt.name}.',
          );
        }
        if (prev.coordinationMode != nxt.coordinationMode) {
          details.add(
            'Mode de coordination modifié : ${prev.coordinationMode} → ${nxt.coordinationMode}.',
          );
        }
        if (prev.triggerEvent != nxt.triggerEvent) {
          details.add(
            'Déclencheur modifié : « ${prev.triggerEvent} » → « ${nxt.triggerEvent} ».',
          );
        }
        if (prev.boundedContext != nxt.boundedContext) {
          details.add(
            'Bounded Contexts modifiés : « ${prev.boundedContext} » → « ${nxt.boundedContext} ».',
          );
        }
        if (!deepJsonEquals(prev.steps, nxt.steps)) {
          details.add(
            'Étapes de la Saga mises à jour (${prev.steps.length} → ${nxt.steps.length}).',
          );
        }
        if (!deepJsonEquals(prev.compensations, nxt.compensations)) {
          details.add('Matrice des compensations / rollbacks mise à jour.');
        }
        if (prev.mermaidDiagram != nxt.mermaidDiagram) {
          details.add('Diagramme Mermaid de la Saga mis à jour.');
        }
        if (details.isEmpty && !deepJsonEquals(prev.specJson, nxt.specJson)) {
          details.add('Spécification de la Saga mise à jour.');
        }
        entries.add(
          DesignDiffEntry(
            category: DesignDiffItemCategory.saga,
            changeKind: details.isEmpty
                ? DesignDiffChangeKind.unchanged
                : DesignDiffChangeKind.modified,
            itemId: nxt.id,
            itemName: nxt.name,
            previousVersion: prev.version,
            nextVersion: nxt.version,
            details: details,
          ),
        );
      }
    }
    return entries;
  }

  static List<Map<String, Object?>> _normalizeUseCaseFieldList(
    Object? rawSpecFields,
    Map<String, Object?> fallbackSchema,
  ) {
    if (rawSpecFields is List && rawSpecFields.isNotEmpty) {
      final out = <Map<String, Object?>>[];
      for (final item in rawSpecFields) {
        if (item is Map) {
          out.add(freezeJsonMap(item));
        } else if (item is String && item.trim().isNotEmpty) {
          final idx = item.indexOf(':');
          final name = idx > 0 ? item.substring(0, idx).trim() : item.trim();
          out.add(<String, Object?>{'name': name, 'raw': item.trim()});
        }
      }
      return out;
    }
    if (fallbackSchema['properties'] case final Map props
        when props.isNotEmpty) {
      final reqSet = parseCleanStringList(fallbackSchema['required']).toSet();
      return <Map<String, Object?>>[
        for (final entry in props.entries)
          <String, Object?>{
            'name': '${entry.key}',
            'required': reqSet.contains('${entry.key}'),
            'schema': freezeJsonValue(entry.value),
          },
      ];
    }
    return const <Map<String, Object?>>[];
  }

  static void _appendNamedMapListDiff({
    required List<String> details,
    required List<Map<String, Object?>> previousList,
    required List<Map<String, Object?>> nextList,
    required String singularAdded,
    required String singularRemoved,
    required String singularModified,
  }) {
    if (previousList.isEmpty && nextList.isEmpty) return;

    String labelOf(Map<String, Object?> m) {
      final n = (m['name'] as String?)?.trim();
      if (n != null && n.isNotEmpty) return n;
      final id = (m['id'] as String?)?.trim();
      return (id != null && id.isNotEmpty) ? id : 'item';
    }

    final pairs = _matchItems<Map<String, Object?>>(
      previous: previousList,
      next: nextList,
      primaryKeyOf: (m) {
        final id = (m['id'] as String?)?.trim();
        return (id != null && id.isNotEmpty) ? id : labelOf(m);
      },
      secondaryKeyOf: (m) => labelOf(m).toLowerCase(),
    );

    for (final pair in pairs) {
      final prev = pair.previous;
      final nxt = pair.next;
      if (prev == null && nxt != null) {
        details.add('$singularAdded : ${labelOf(nxt)}.');
      } else if (prev != null && nxt == null) {
        details.add('$singularRemoved : ${labelOf(prev)}.');
      } else if (prev != null && nxt != null && !deepJsonEquals(prev, nxt)) {
        details.add('$singularModified : ${labelOf(nxt)}.');
      }
    }
  }

  static void _appendStringListDiff({
    required List<String> details,
    required List<String> previousList,
    required List<String> nextList,
    required String label,
  }) {
    if (listEquals(previousList, nextList)) return;
    final prevSet = previousList.toSet();
    final nextSet = nextList.toSet();
    final added = nextSet.difference(prevSet).length;
    final removed = prevSet.difference(nextSet).length;
    if (added > 0 || removed > 0) {
      details.add('$label mises à jour (+$added / -$removed).');
    } else {
      details.add('$label réordonnées.');
    }
  }

  static List<({T? previous, T? next})> _matchItems<T>({
    required List<T> previous,
    required List<T> next,
    required String Function(T) primaryKeyOf,
    String Function(T)? secondaryKeyOf,
  }) {
    final unmatchedPrev = <int>{for (var i = 0; i < previous.length; i++) i};
    final matchedPrevForNext = List<int?>.filled(next.length, null);

    final prevByPrimary = <String, int>{};
    for (var i = 0; i < previous.length; i++) {
      prevByPrimary.putIfAbsent(primaryKeyOf(previous[i]), () => i);
    }

    for (var j = 0; j < next.length; j++) {
      final pk = primaryKeyOf(next[j]);
      final prevIdx = prevByPrimary[pk];
      if (prevIdx != null && unmatchedPrev.remove(prevIdx)) {
        matchedPrevForNext[j] = prevIdx;
      }
    }

    if (secondaryKeyOf != null && unmatchedPrev.isNotEmpty) {
      final prevBySecondary = <String, int>{};
      for (final prevIdx in unmatchedPrev) {
        prevBySecondary.putIfAbsent(
          secondaryKeyOf(previous[prevIdx]),
          () => prevIdx,
        );
      }
      for (var j = 0; j < next.length; j++) {
        if (matchedPrevForNext[j] != null) continue;
        final sk = secondaryKeyOf(next[j]);
        final prevIdx = prevBySecondary[sk];
        if (prevIdx != null && unmatchedPrev.remove(prevIdx)) {
          matchedPrevForNext[j] = prevIdx;
        }
      }
    }

    final out = <({T? previous, T? next})>[];
    for (var j = 0; j < next.length; j++) {
      final prevIdx = matchedPrevForNext[j];
      out.add((
        previous: prevIdx != null ? previous[prevIdx] : null,
        next: next[j],
      ));
    }
    for (var i = 0; i < previous.length; i++) {
      if (unmatchedPrev.contains(i)) {
        out.add((previous: previous[i], next: null));
      }
    }
    return out;
  }
}
