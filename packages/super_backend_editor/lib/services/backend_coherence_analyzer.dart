/// Analyseur statique de cohérence entre la couche Design en lecture seule
/// ([DomainDesignSpec]) et la surcouche d'implémentation Backend
/// ([BackendOverlayConfig]) d'un [BackendDomainProject].
library;

import '../models/backend_coherence_issue.dart';
import '../models/backend_domain_project.dart';
import '../models/backend_overlay_config.dart';
import '../models/domain_design_spec.dart';
import 'backend_workspace_store.dart';

/// Produit les diagnostics de cohérence ([BackendCoherenceIssue]) d'un projet Backend.
abstract final class BackendCoherenceAnalyzer {
  /// Analyse [project] en mémoire et retourne la liste ordonnée des anomalies
  /// détectées (erreurs bloquantes, avertissements de dérive/orphelins et
  /// recommandations d'alignement).
  ///
  /// Lorsque [checkScripts] vaut `true` (par défaut), vérifie que chaque chemin
  /// relatif de script QuickJS référencé figure dans [existingScriptPaths].
  static List<BackendCoherenceIssue> analyze(
    BackendDomainProject project, {
    Set<String> existingScriptPaths = const <String>{},
    bool checkScripts = true,
  }) {
    final issues = <BackendCoherenceIssue>[];
    final normalizedExistingScripts = <String>{
      for (final path in existingScriptPaths) _normalizeScriptPath(path),
    };

    _checkCollectionMappings(project, issues);
    _checkEndpointBindings(project, issues);
    if (checkScripts) {
      _checkMissingScripts(project, normalizedExistingScripts, issues);
    }
    _checkOrphanedScripts(project, issues);
    _checkValueObjectAndContractRefs(project, issues);
    _checkContractSchemas(project, issues);
    _checkEnvironmentSecrets(project, issues);

    issues.sort((a, b) {
      final sevCmp = _severityRank(a.severity)
          .compareTo(_severityRank(b.severity));
      if (sevCmp != 0) return sevCmp;
      return a.id.compareTo(b.id);
    });

    for (final issue in issues) {
      issue.validate();
    }
    return List<BackendCoherenceIssue>.unmodifiable(issues);
  }

  /// Inspecte les scripts réellement présents sur disque dans [store] pour
  /// `project.domainCode`, puis exécute l'audit complet via [analyze].
  static Future<List<BackendCoherenceIssue>> analyzeFromStore(
    BackendDomainProject project,
    BackendWorkspaceStore store,
  ) async {
    final scriptsOnDisk = await store.listScripts(project.domainCode);
    return analyze(project, existingScriptPaths: scriptsOnDisk.toSet());
  }

  /// Alias de [analyzeFromStore] pour l'analyse de cohérence adossée à un [BackendWorkspaceStore].
  static Future<List<BackendCoherenceIssue>> analyzeWithStore(
    BackendDomainProject project,
    BackendWorkspaceStore store,
  ) => analyzeFromStore(project, store);

  static int _severityRank(BackendIssueSeverity severity) => switch (severity) {
    BackendIssueSeverity.error => 0,
    BackendIssueSeverity.warning => 1,
    BackendIssueSeverity.info => 2,
  };

  static String _normalizeScriptPath(String raw) =>
      raw.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');

  static String _normalizeHttpPath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '/') return '/';
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  static void _checkCollectionMappings(
    BackendDomainProject project,
    List<BackendCoherenceIssue> issues,
  ) {
    final spec = project.designSpec;
    final overlay = project.overlay;

    for (final model in spec.models) {
      final boundCollection = overlay.findCollectionForContract(model.entryId);
      if (boundCollection == null) {
        issues.add(
          BackendCoherenceIssue(
            id: 'col_missing_${model.entryId}',
            severity: BackendIssueSeverity.warning,
            category: BackendIssueCategory.collectionMapping,
            title: 'Modèle sans collection : ${model.technicalName}',
            message:
                'Le modèle persistant « ${model.effectiveLabel} » (${model.technicalName}) '
                'ne possède aucune collection provisionnée dans super_backend.',
            targetId: model.entryId,
            suggestion:
                'Provisionnez une collection rattachée à ${model.entryId} ou '
                'lancez une réconciliation de l’overlay.',
          ),
        );
      }
    }

    for (final col in overlay.collections) {
      final missingInDesign =
          col.contractEntryId != null &&
          spec.findContractById(col.contractEntryId!) == null;
      if (col.isOrphaned || missingInDesign) {
        issues.add(
          BackendCoherenceIssue(
            id: 'col_orphaned_${col.id}',
            severity: BackendIssueSeverity.warning,
            category: BackendIssueCategory.collectionMapping,
            title: 'Collection orpheline : ${col.collectionName}',
            message:
                'La collection « ${col.label} » (${col.collectionName}) référence un '
                'modèle Design supprimé (${col.contractEntryId ?? 'inconnu'}). '
                'Les données SQLite existantes sont conservées.',
            targetId: col.id,
            suggestion:
                'Supprimez explicitement la collection si ses données ne sont '
                'plus utiles, ou détachez contractEntryId pour en faire une collection personnalisée.',
          ),
        );
      }
    }
  }

  static void _checkEndpointBindings(
    BackendDomainProject project,
    List<BackendCoherenceIssue> issues,
  ) {
    final spec = project.designSpec;
    final overlay = project.overlay;

    // 1. Routes HTTP dupliquées parmi les endpoints actifs.
    final activeByRouteKey = <String, List<BackendEndpointConfig>>{};
    for (final ep in overlay.endpoints) {
      if (!ep.enabled) continue;
      final routeKey = '${ep.method}:${_normalizeHttpPath(ep.path)}';
      activeByRouteKey
          .putIfAbsent(routeKey, () => <BackendEndpointConfig>[])
          .add(ep);
    }
    for (final routeEntry in activeByRouteKey.entries) {
      final conflicting = routeEntry.value;
      if (conflicting.length < 2) continue;
      final idsLabel = conflicting.map((e) => e.id).join(', ');
      final first = conflicting.first;
      for (final dup in conflicting) {
        issues.add(
          BackendCoherenceIssue(
            id: 'ep_duplicate_route_${dup.id}',
            severity: BackendIssueSeverity.error,
            category: BackendIssueCategory.endpointBinding,
            title: 'Route HTTP en conflit : ${first.method} ${first.path}',
            message:
                'Plusieurs endpoints actifs partagent la route '
                '${first.method} ${_normalizeHttpPath(first.path)} ($idsLabel).',
            targetId: dup.id,
            suggestion: 'Modifiez le chemin HTTP, la méthode ou désactivez l’un des endpoints en doublon.',
          ),
        );
      }
    }

    // 2. Intégrité des cibles d'endpoints (collectionId, useCaseId, contrats).
    for (final ep in overlay.endpoints) {
      var reportedOrphaned = false;

      if (ep.collectionId != null) {
        final targetCol = overlay.findCollectionById(ep.collectionId!);
        if (targetCol == null) {
          issues.add(
            BackendCoherenceIssue(
              id: 'ep_missing_col_${ep.id}',
              severity: BackendIssueSeverity.error,
              category: BackendIssueCategory.endpointBinding,
              title: 'Collection introuvable sur ${ep.method} ${ep.path}',
              message:
                  'L’endpoint « ${ep.id} » pointe vers la collection « ${ep.collectionId} » '
                  'qui n’existe pas dans l’overlay.',
              targetId: ep.id,
              suggestion: 'Rattachez l’endpoint à une collection existante ou supprimez-le.',
            ),
          );
          reportedOrphaned = true;
        } else if (targetCol.isOrphaned) {
          issues.add(
            BackendCoherenceIssue(
              id: 'ep_orphaned_col_${ep.id}',
              severity: BackendIssueSeverity.warning,
              category: BackendIssueCategory.endpointBinding,
              title: 'Endpoint lié à une collection orpheline : ${ep.path}',
              message:
                  'L’endpoint ${ep.method} ${ep.path} cible la collection orpheline '
                  '« ${targetCol.collectionName} ».',
              targetId: ep.id,
              suggestion: 'Désactivez ou supprimez cet endpoint si la collection orpheline est retirée.',
            ),
          );
          reportedOrphaned = true;
        } else if (ep.enabled && !targetCol.enabled) {
          issues.add(
            BackendCoherenceIssue(
              id: 'ep_disabled_col_${ep.id}',
              severity: BackendIssueSeverity.warning,
              category: BackendIssueCategory.endpointBinding,
              title: 'Endpoint actif sur collection désactivée : ${ep.path}',
              message:
                  'L’endpoint actif ${ep.method} ${ep.path} cible la collection '
                  'désactivée « ${targetCol.collectionName} ».',
              targetId: ep.id,
              suggestion:
                  'Activez la collection « ${targetCol.collectionName} » ou désactivez l’endpoint.',
            ),
          );
        }
      }

      if (ep.useCaseId != null) {
        final targetUc = spec.findUseCaseById(ep.useCaseId!);
        if (targetUc == null || ep.isOrphaned) {
          issues.add(
            BackendCoherenceIssue(
              id: 'ep_orphaned_uc_${ep.id}',
              severity: BackendIssueSeverity.warning,
              category: BackendIssueCategory.endpointBinding,
              title: 'Endpoint CQRS orphelin : ${ep.method} ${ep.path}',
              message:
                  'L’endpoint « ${ep.id} » référence le Use Case « ${ep.useCaseId} » '
                  'qui ne figure plus dans la spécification Design.',
              targetId: ep.id,
              suggestion: 'Supprimez cet endpoint CQRS ou convertissez-le en route personnalisée (custom).',
            ),
          );
          reportedOrphaned = true;
        }
      } else if (ep.isOrphaned && !reportedOrphaned) {
        issues.add(
          BackendCoherenceIssue(
            id: 'ep_orphaned_${ep.id}',
            severity: BackendIssueSeverity.warning,
            category: BackendIssueCategory.endpointBinding,
            title: 'Endpoint orphelin : ${ep.method} ${ep.path}',
            message:
                'L’endpoint « ${ep.id} » est marqué orphelin suite à un ré-import Design.',
            targetId: ep.id,
            suggestion:
                'Vérifiez ou supprimez cet endpoint s’il n’est plus utilisé.',
          ),
        );
      }

      if (!ep.isOrphaned &&
          ep.inputContractEntryId != null &&
          spec.findContractById(ep.inputContractEntryId!) == null) {
        issues.add(
          BackendCoherenceIssue(
            id: 'ep_missing_in_contract_${ep.id}',
            severity: BackendIssueSeverity.warning,
            category: BackendIssueCategory.endpointBinding,
            title: 'Contrat d’entrée introuvable sur ${ep.path}',
            message:
                'L’endpoint « ${ep.id} » référence le contrat d’entrée '
                '« ${ep.inputContractEntryId} » absent du Design.',
            targetId: ep.id,
            suggestion: 'Mettez à jour ou videz inputContractEntryId.',
          ),
        );
      }

      if (!ep.isOrphaned &&
          ep.outputContractEntryId != null &&
          spec.findContractById(ep.outputContractEntryId!) == null) {
        issues.add(
          BackendCoherenceIssue(
            id: 'ep_missing_out_contract_${ep.id}',
            severity: BackendIssueSeverity.warning,
            category: BackendIssueCategory.endpointBinding,
            title: 'Contrat de sortie introuvable sur ${ep.path}',
            message:
                'L’endpoint « ${ep.id} » référence le contrat de sortie '
                '« ${ep.outputContractEntryId} » absent du Design.',
            targetId: ep.id,
            suggestion: 'Mettez à jour ou videz outputContractEntryId.',
          ),
        );
      }
    }

    // 3. Use Cases sans endpoint CQRS actif.
    for (final uc in spec.useCases) {
      final matchingEndpoints = overlay.endpoints
          .where((ep) => ep.useCaseId == uc.id && !ep.isOrphaned)
          .toList(growable: false);
      final hasActiveEndpoint = matchingEndpoints.any((ep) => ep.enabled);
      if (!hasActiveEndpoint) {
        final isDisabledOnly = matchingEndpoints.isNotEmpty;
        issues.add(
          BackendCoherenceIssue(
            id: 'uc_unexposed_${uc.id}',
            severity: isDisabledOnly
                ? BackendIssueSeverity.info
                : BackendIssueSeverity.warning,
            category: BackendIssueCategory.endpointBinding,
            title: isDisabledOnly
                ? 'Endpoint CQRS désactivé pour ${uc.code}'
                : 'Use Case non exposé : ${uc.code} (${uc.name})',
            message: isDisabledOnly
                ? 'Le Use Case « ${uc.effectiveTitle} » possède un endpoint CQRS, mais celui-ci est désactivé.'
                : 'Le Use Case « ${uc.effectiveTitle} » (${uc.cqrsType}) n’a aucun endpoint CQRS actif.',
            targetId: uc.id,
            suggestion: isDisabledOnly
                ? 'Activez l’endpoint associé si ce Use Case doit être invocable via HTTP.'
                : 'Ajoutez ou activez un endpoint ${uc.isQuery ? 'GET /api/queries/...' : 'POST /api/commands/...'} lié à ${uc.id}.',
          ),
        );
      }
    }
  }

  static void _checkMissingScripts(
    BackendDomainProject project,
    Set<String> normalizedExistingScripts,
    List<BackendCoherenceIssue> issues,
  ) {
    final overlay = project.overlay;

    for (final col in overlay.collections) {
      if (col.invariantScriptPath == null) continue;
      final normalized = _normalizeScriptPath(col.invariantScriptPath!);
      if (!normalizedExistingScripts.contains(normalized)) {
        issues.add(
          BackendCoherenceIssue(
            id: 'script_missing_col_${col.id}',
            severity: col.enabled
                ? BackendIssueSeverity.error
                : BackendIssueSeverity.warning,
            category: BackendIssueCategory.scriptMissing,
            title: 'Script d’invariant introuvable : $normalized',
            message:
                'La collection « ${col.collectionName} » référence le script QuickJS '
                '« $normalized » qui est absent du dossier scripts/.',
            targetId: col.id,
            suggestion:
                'Créez le fichier scripts/$normalized ou retirez invariantScriptPath sur la collection.',
          ),
        );
      }
    }

    for (final ep in overlay.endpoints) {
      if (ep.handlerScriptPath == null) continue;
      final normalized = _normalizeScriptPath(ep.handlerScriptPath!);
      if (!normalizedExistingScripts.contains(normalized)) {
        issues.add(
          BackendCoherenceIssue(
            id: 'script_missing_ep_${ep.id}',
            severity: ep.enabled
                ? BackendIssueSeverity.error
                : BackendIssueSeverity.warning,
            category: BackendIssueCategory.scriptMissing,
            title: 'Handler QuickJS introuvable : $normalized',
            message:
                'L’endpoint ${ep.method} ${ep.path} référence le script handler '
                '« $normalized » qui est absent du dossier scripts/.',
            targetId: ep.id,
            suggestion:
                'Générez le handler scripts/$normalized dans le Logic Studio ou corrigez handlerScriptPath.',
          ),
        );
      }
    }

    for (final binding in overlay.scripts) {
      if (!binding.enabled) continue;
      final normalized = _normalizeScriptPath(binding.scriptPath);
      if (!normalizedExistingScripts.contains(normalized)) {
        issues.add(
          BackendCoherenceIssue(
            id: 'script_missing_bind_${binding.id}',
            severity: BackendIssueSeverity.error,
            category: BackendIssueCategory.scriptMissing,
            title: 'Script QuickJS introuvable : $normalized',
            message:
                'La liaison de script active « ${binding.label} » (${binding.targetKind.label}) '
                'référence « $normalized » qui n’existe pas sur disque.',
            targetId: binding.id,
            suggestion:
                'Créez le fichier scripts/$normalized ou désactivez la liaison « ${binding.label} ».',
          ),
        );
      }
    }
  }

  static void _checkOrphanedScripts(
    BackendDomainProject project,
    List<BackendCoherenceIssue> issues,
  ) {
    for (final binding in project.overlay.scripts) {
      if (!binding.isOrphaned) continue;
      issues.add(
        BackendCoherenceIssue(
          id: 'script_orphaned_${binding.id}',
          severity: BackendIssueSeverity.warning,
          category: BackendIssueCategory.scriptMissing,
          title: 'Liaison de script orpheline : ${binding.label}',
          message:
              'Le script « ${binding.scriptPath} » cible l’élément « ${binding.targetId} » '
              '(${binding.targetKind.label}) supprimé de la spécification Design.',
          targetId: binding.id,
          suggestion: 'Rattachez ce script à un nouvel artefact ou supprimez la liaison.',
        ),
      );
    }
  }

  static void _checkValueObjectAndContractRefs(
    BackendDomainProject project,
    List<BackendCoherenceIssue> issues,
  ) {
    final spec = project.designSpec;

    void inspectAttributes({
      required ImportedContractEntry entry,
      required List<Map<String, Object?>> attributes,
      required String prefix,
    }) {
      for (final attr in attributes) {
        final attrName = (attr['name'] as String?)?.trim() ?? 'attribut';
        final attrPath = prefix.isEmpty ? attrName : '$prefix.$attrName';
        final rawType = (attr['type'] as String?)?.trim().toLowerCase() ?? '';

        if (rawType == 'valueobject' ||
            rawType == 'vo' ||
            rawType == 'value_object' ||
            rawType == 'value-object') {
          final voId = (attr['valueObjectId'] as String?)?.trim() ?? '';
          if (voId.isEmpty || spec.findValueObjectByName(voId) == null) {
            issues.add(
              BackendCoherenceIssue(
                id: 'vo_ref_${entry.entryId}_$attrPath',
                severity: BackendIssueSeverity.warning,
                category: BackendIssueCategory.valueObjectRef,
                title:
                    'Value Object inconnu sur ${entry.technicalName}.$attrPath',
                message:
                    'L’attribut « $attrPath » du contrat « ${entry.technicalName} » '
                    'référence un Value Object introuvable (${voId.isEmpty ? 'non renseigné' : voId}).',
                targetId: entry.entryId,
                suggestion: 'Vérifiez la déclaration du Value Object dans le catalogue Design ou ré-importez le domaine.',
              ),
            );
          }
        } else if (rawType == 'reference' || rawType == 'ref') {
          final refId = (attr['referenceObjectId'] as String?)?.trim() ?? '';
          final found =
              refId.isNotEmpty &&
              (spec.findContractById(refId) != null ||
                  spec.findContractByTechnicalName(refId) != null);
          if (!found) {
            issues.add(
              BackendCoherenceIssue(
                id: 'contract_ref_${entry.entryId}_$attrPath',
                severity: BackendIssueSeverity.warning,
                category: BackendIssueCategory.valueObjectRef,
                title:
                    'Contrat cible inconnu sur ${entry.technicalName}.$attrPath',
                message:
                    'L’attribut référence « $attrPath » du contrat « ${entry.technicalName} » '
                    'pointe vers une entrée introuvable (${refId.isEmpty ? 'non renseignée' : refId}).',
                targetId: entry.entryId,
                suggestion: 'Déclarez le contrat cible dans le catalogue Design ou corrigez referenceObjectId.',
              ),
            );
          }
        }

        if (attr['children'] case final List rawChildren
            when rawChildren.isNotEmpty) {
          final childMaps = <Map<String, Object?>>[
            for (final child in rawChildren)
              if (child is Map)
                <String, Object?>{
                  for (final e in child.entries) '${e.key}': e.value,
                },
          ];
          inspectAttributes(
            entry: entry,
            attributes: childMaps,
            prefix: attrPath,
          );
        }
      }
    }

    for (final entry in spec.contractEntries) {
      inspectAttributes(entry: entry, attributes: entry.attributes, prefix: '');

      for (final rel in entry.relations) {
        final relName = (rel['name'] as String?)?.trim() ?? 'relation';
        final targetId = (rel['targetObjectId'] as String?)?.trim() ?? '';
        final found =
            targetId.isNotEmpty &&
            (spec.findContractById(targetId) != null ||
                spec.findContractByTechnicalName(targetId) != null);
        if (!found) {
          issues.add(
            BackendCoherenceIssue(
              id: 'rel_ref_${entry.entryId}_$relName',
              severity: BackendIssueSeverity.warning,
              category: BackendIssueCategory.valueObjectRef,
              title:
                  'Cible de relation inconnue sur ${entry.technicalName}.$relName',
              message:
                  'La relation « $relName » de « ${entry.technicalName} » cible '
                  'un objet métier introuvable (${targetId.isEmpty ? 'non renseigné' : targetId}).',
              targetId: entry.entryId,
              suggestion:
                  'Ajoutez le modèle « $targetId » au catalogue Design ou mettez à jour la relation.',
            ),
          );
        }
      }
    }
  }

  static void _checkContractSchemas(
    BackendDomainProject project,
    List<BackendCoherenceIssue> issues,
  ) {
    for (final model in project.designSpec.models) {
      final schema = model.jsonSchema;
      final props = schema['properties'];
      final lacksProperties = schema.isEmpty || props is! Map || props.isEmpty;
      if (lacksProperties) {
        issues.add(
          BackendCoherenceIssue(
            id: 'schema_empty_${model.entryId}',
            severity: BackendIssueSeverity.warning,
            category: BackendIssueCategory.contractSchema,
            title: 'Schéma JSON incomplet : ${model.technicalName}',
            message:
                'Le modèle persistant « ${model.effectiveLabel} » (${model.technicalName}) '
                'possède un jsonSchema vide ou dépourvu de propriétés typées.',
            targetId: model.entryId,
            suggestion:
                'Définissez les attributs du modèle dans super_spec_forge puis ré-importez la spécification Design, '
                'ou désactivez strictSchemaValidation sur la collection correspondante.',
          ),
        );
      }
    }
  }

  static void _checkEnvironmentSecrets(
    BackendDomainProject project,
    List<BackendCoherenceIssue> issues,
  ) {
    final spec = project.designSpec;
    final activeEnvId =
        project.overlay.activeEnvironmentId ??
        spec.environments.firstOrNull?.id;
    final envById = <String, ImportedEnvironmentSpec>{
      for (final env in spec.environments) env.id: env,
    };

    for (final cfg in spec.configurations) {
      if (!cfg.isSecret) continue;
      final localValue =
          project.localSecretValues[cfg.environmentId]?[cfg.configKey];
      if (localValue != null && localValue.trim().isNotEmpty) continue;

      final isForActiveEnv =
          activeEnvId == null || cfg.environmentId == activeEnvId;
      final envLabel =
          envById[cfg.environmentId]?.environmentCode ?? cfg.environmentId;

      issues.add(
        BackendCoherenceIssue(
          id: 'secret_missing_${cfg.id}',
          severity: isForActiveEnv
              ? BackendIssueSeverity.warning
              : BackendIssueSeverity.info,
          category: BackendIssueCategory.environmentSecret,
          title: 'Secret local non renseigné : ${cfg.configKey} ($envLabel)',
          message:
              'La clé secrète « ${cfg.configKey} » de l’environnement « $envLabel » '
              'n’a aucune valeur de test locale définie.',
          targetId: cfg.id,
          suggestion:
              'Renseignez une valeur de test locale pour ${cfg.configKey} '
              '(stockée uniquement sous .local/secrets_${project.domainCode}.json).',
        ),
      );
    }
  }
}
