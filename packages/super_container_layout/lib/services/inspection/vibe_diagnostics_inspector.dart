/// Inspecteurs système complémentaires ([VibeDiagnosticsInspector]) et suivi d'aperçu réversible
/// ([VibePreviewStateTracker]) pour l'assistant Vibe IA.
///
/// Fournit les implémentations des 6 outils système :
/// - `get_debug_entries` : journaux et erreurs capturés dans [debugEntries] ;
/// - `get_datasources_and_providers` : catalogue et état runtime des datasources et providers ;
/// - `inspect_bindings_and_diagnostics` : audit des liaisons JSON, orphelins et états forcés ;
/// - `get_theme_and_contrast` : palette `theme:*` résolue en `#RRGGBB` et ratios de contraste WCAG AA ;
/// - `get_registry_and_selection` : constructeurs/extensions de [Registry], polices et sélection active ;
/// - `preview_navigation_or_selection` : navigation de route et sélection Maître/Détail réversibles.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../ai/vibe_app_tools.dart';
import '../../models/component_behavior.dart';
import '../../models/component_usage.dart';
import '../../models/datasources/datasource_config.dart';
import '../../models/json_syntax.dart';
import '../../models/json_text_binding.dart';
import '../../models/material_icon_catalog.dart';
import '../../models/registry.dart';
import '../../models/super_action_config.dart';
import '../../models/super_conditional_config.dart';
import '../../models/super_indicator_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_list_view_config.dart';
import '../../models/super_tab_config.dart';
import '../../models/super_table_config.dart';
import '../../models/super_tree_view_config.dart';
import '../../models/super_value_config.dart';
import '../../theme/appearance.dart';
import '../../theme/theme_color.dart';
import '../../widgets/components/component_state_behavior.dart';
import '../../widgets/components/super_layout/layout_selection.dart';
import '../../widgets/editing/ai/vibe_scope_helpers.dart';
import '../../widgets/editing/ai/vibe_work_highlight.dart';
import '../../widgets/editing/overlay/editor_overlay.dart'
    show isRenderObjectOffstage;
import '../../widgets/editing/slots/editor_context_menu.dart'
    show VibeChatScope;
import 'vibe_ghost_component_detector.dart';
import '../../widgets/editing/slots/editor_slot.dart'
    show EditorSlotState, StyleEditScope;
import '../diagnostics/debug_entry.dart';
import '../fonts/dynamic_font_manager.dart';
import '../pages/editor_page_router.dart';
import '../providers/http_data_provider.dart';
import '../repositories/json_repository_store.dart';
import '../repositories/json_schema_field_resolver.dart';
import '../repositories/json_schema_validator.dart';
import 'vibe_debug_capture.dart';
import 'vibe_mounted_slot_index.dart';

/// Mémorise les sélections de tableaux `JsonArrayBinding` et les onglets `SuperTab` modifiés en aperçu
/// par l'outil `preview_navigation_or_selection` afin de pouvoir les restaurer au rollback.
class VibePreviewStateTracker {
  final Map<(String, String), ({List<int>? selection, String? nodePath})>
  _initialSelections = {};
  final Map<Object, ({VibeMountedTabEntry entry, int initialIndex})>
  _initialTabStates = {};

  bool _navigatedByTool = false;

  /// Indique si au moins une navigation a été déclenchée via `preview_navigation_or_selection`.
  bool get hasNavigated => _navigatedByTool;

  /// Indique si au moins un onglet `SuperTab` a été basculé en aperçu durant le tour.
  bool get hasTabChanges => _initialTabStates.isNotEmpty;

  /// Indique qu'une navigation d'aperçu a eu lieu durant le tour.
  void markNavigated() {
    _navigatedByTool = true;
  }

  /// Sauvegarde l'onglet actif initial de [entry] avant sa première bascule d'aperçu.
  void snapshotTabIfNeeded(VibeMountedTabEntry entry, int currentIndex) {
    _initialTabStates.putIfAbsent(
      entry.token,
      () => (entry: entry, initialIndex: currentIndex),
    );
  }

  /// Restaure tous les composants `SuperTab` basculés en aperçu vers leur onglet initial.
  void restoreTabs() {
    if (_initialTabStates.isEmpty) return;
    for (final saved in _initialTabStates.values) {
      try {
        saved.entry.restoreTab(saved.initialIndex);
      } catch (_) {
        // Ignore si le SuperTab a été démonté entre-temps.
      }
    }
    _initialTabStates.clear();
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Sauvegarde la sélection initiale de `(repositoryId, template)` avant sa première mutation.
  void snapshotSelectionIfNeeded(
    JsonRepositoryStore store,
    String repositoryId,
    String template,
  ) {
    final key = (repositoryId, template);
    if (_initialSelections.containsKey(key)) return;
    final array = store.bindingOf(repositoryId).array(template);
    _initialSelections[key] = (
      selection: array.selection == null
          ? null
          : List<int>.unmodifiable(array.selection!),
      nodePath: array.selectedNodePath,
    );
  }

  /// Restaure toutes les sélections `JsonArrayBinding` modifiées pendant le tour.
  void restoreSelections(JsonRepositoryStore? store) {
    if (store == null || _initialSelections.isEmpty) return;
    for (final entry in _initialSelections.entries) {
      final (repoId, template) = entry.key;
      final saved = entry.value;
      try {
        final array = store.bindingOf(repoId).array(template);
        final sel = saved.selection;
        if (sel == null || sel.isEmpty) {
          array.clear();
        } else {
          final parents = sel.length > 1
              ? sel.sublist(0, sel.length - 1)
              : const <int>[];
          array.select(parents, sel.last, nodePath: saved.nodePath);
        }
      } catch (_) {
        // Ignore si le store a été disposé entre-temps.
      }
    }
    _initialSelections.clear();
  }
}

/// Implémentation modulaire des outils de diagnostic, thème, registre et aperçu pour Vibe IA.
class VibeDiagnosticsInspector {
  /// Crée un inspecteur système connecté aux services actifs de l'application.
  VibeDiagnosticsInspector({
    required this.readAppearance,
    required this.slotIndex,
    required this.resolvePrimaryContext,
    this.registry,
    this.repositoryStore,
    this.pageRouting,
    this.ensurePageLoaded,
    this.readScope,
    this.readVisibleOnly,
    this.onSelectScope,
    this.turnStartMarker,
    this.previewTracker,
    this.fontManager,
    this.waitForVisualFrame,
  });

  /// Fournisseur de l'[Appearance] courante.
  final Appearance Function() readAppearance;

  /// Index des slots montés.
  final VibeMountedSlotIndex slotIndex;

  /// Résolveur du `BuildContext` principal monté.
  final BuildContext? Function() resolvePrimaryContext;

  /// Registre optionnel des composants et extensions.
  final Registry? registry;

  /// Store optionnel des repositories, datasources et providers.
  final JsonRepositoryStore? repositoryStore;

  /// Routeur GoRouter dynamique optionnel.
  final EditorPageRouter? pageRouting;

  /// Callback optionnel chargeant à la demande une page avant navigation d'aperçu.
  final Future<void> Function(String pageId)? ensurePageLoaded;

  /// Fournisseur optionnel du `VibeChatScope` actif.
  final VibeChatScope? Function()? readScope;

  /// Indique si le mode « Uniquement visible » verrouille l'onglet et le scroll courants.
  final bool Function()? readVisibleOnly;

  /// Callback optionnel permettant de mettre à jour le `VibeChatScope` du chat.
  final ValueChanged<VibeChatScope?>? onSelectScope;

  /// Repère optionnel dans [debugEntries] capturé au début du tour courant.
  final VibeDebugMarker? turnStartMarker;

  /// Suivi optionnel des états d'aperçu à restaurer en cas de rollback.
  final VibePreviewStateTracker? previewTracker;

  /// Gestionnaire optionnel de polices dynamiques Google Fonts.
  final DynamicFontManager? fontManager;

  /// Attente optionnelle d'une frame de rendu après navigation, sélection ou bascule d'onglet.
  final Future<void> Function()? waitForVisualFrame;

  static final RegExp _sensitiveHeaderName = RegExp(
    r'auth|token|secret|password|cookie|api[-_]?key|credential|bearer',
    caseSensitive: false,
  );

  static final RegExp _pureEnvPlaceholder = RegExp(
    r'^(?:Bearer\s+)?\{\{env\.[A-Za-z0-9_]+\}\}$',
  );

  /// Marge droite minimale recommandée sur `<listId>:item` lorsque `allowRemove` est actif.
  static const double _minListRemoveRightPadding = 38.0;

  /// 1. Lit et filtre les journaux et erreurs d'exécution depuis [debugEntries].
  Future<Map<String, Object?>> getDebugEntries(
    Map<String, Object?> args,
  ) async {
    final rawType = args['type'] is String
        ? (args['type'] as String).trim().toLowerCase()
        : 'error';
    final DebugEntryType? typeFilter = switch (rawType) {
      'error' || 'errors' => DebugEntryType.error,
      'log' || 'logs' => DebugEntryType.log,
      _ => null,
    };
    final rawMinSeverity = args['minSeverity'] ?? args['severity'];
    final DebugSeverity? minSeverity = rawMinSeverity is String
        ? DebugSeverity.tryParse(rawMinSeverity)
        : null;
    final rawCategory = args['category'] is String
        ? (args['category'] as String).trim().toLowerCase()
        : '';
    final DebugErrorCategory? categoryFilter =
        (rawCategory.isEmpty || rawCategory == 'all')
        ? null
        : DebugErrorCategory.tryParse(rawCategory);
    final componentFilter = args['componentId'] is String
        ? (args['componentId'] as String).trim()
        : '';
    final visibleInUiOnly = args['visibleInUiOnly'] == true;
    final query = args['query'] is String
        ? (args['query'] as String).trim().toLowerCase()
        : '';
    final sinceTurnStart = args['sinceTurnStart'] == true;
    final includeVibeInternal = args['includeVibeInternal'] == true;
    final includeStackTrace = args['includeStackTrace'] is bool
        ? args['includeStackTrace'] as bool
        : true;
    final rawLimit = args['limit'];
    final limit = (rawLimit is num ? rawLimit.toInt() : 20).clamp(1, 50);

    final marker = turnStartMarker;
    final List<DebugEntry> baseEntries = (sinceTurnStart && marker != null)
        ? VibeDebugCapture.entriesSince(
            marker,
            type: typeFilter,
            minSeverity: minSeverity,
            categories: categoryFilter == null
                ? null
                : <DebugErrorCategory>{categoryFilter},
            excludeVibeInternal: !includeVibeInternal,
          )
        : [
            for (final entry in debugEntries)
              if ((typeFilter == null || entry.type == typeFilter) &&
                  (minSeverity == null ||
                      entry.severity.rank >= minSeverity.rank) &&
                  (categoryFilter == null ||
                      entry.category == categoryFilter) &&
                  (includeVibeInternal ||
                      !VibeDebugCapture.isVibeInternalMessage(entry.message)))
                entry,
          ];

    final filtered = [
      for (final entry in baseEntries)
        if ((componentFilter.isEmpty || entry.componentId == componentFilter) &&
            (!visibleInUiOnly || entry.visibleInUi) &&
            (query.isEmpty ||
                entry.message.toLowerCase().contains(query) ||
                (entry.componentId?.toLowerCase().contains(query) ?? false) ||
                (entry.source?.toLowerCase().contains(query) ?? false) ||
                (entry.stackTrace?.toLowerCase().contains(query) ?? false)))
          entry,
    ];

    final recentFirst = filtered.reversed.take(limit).toList();
    final countsBySeverity = <String, int>{
      for (final sev in DebugSeverity.values) sev.name: 0,
    };
    final countsByCategory = <String, int>{
      for (final cat in DebugErrorCategory.values) cat.name: 0,
    };
    var totalErrors = 0;
    var uiVisibleErrorCount = 0;
    for (final entry in debugEntries) {
      if (entry.type != DebugEntryType.error) continue;
      if (!includeVibeInternal &&
          VibeDebugCapture.isVibeInternalMessage(entry.message)) {
        continue;
      }
      totalErrors++;
      countsBySeverity[entry.severity.name] =
          (countsBySeverity[entry.severity.name] ?? 0) + 1;
      countsByCategory[entry.category.name] =
          (countsByCategory[entry.category.name] ?? 0) + 1;
      if (entry.visibleInUi) uiVisibleErrorCount++;
    }
    final turnErrors = marker == null
        ? 0
        : VibeDebugCapture.entriesSince(
            marker,
            type: DebugEntryType.error,
          ).length;

    return <String, Object?>{
      'totalEntries': debugEntries.length,
      'totalErrors': totalErrors,
      'uiVisibleErrorCount': uiVisibleErrorCount,
      'turnErrorCount': turnErrors,
      'countsBySeverity': countsBySeverity,
      'countsByCategory': countsByCategory,
      'matchedCount': filtered.length,
      'returnedCount': recentFirst.length,
      'entries': [
        for (final entry in recentFirst)
          <String, Object?>{
            'timestamp': entry.timestamp.toIso8601String(),
            'type': entry.type.name,
            'severity': entry.severity.name,
            'severityLabel': entry.severity.label,
            'category': entry.category.name,
            'categoryLabel': entry.category.label,
            if (entry.componentId != null) 'componentId': entry.componentId,
            if (entry.source != null) 'source': entry.source,
            'visibleInUi': entry.visibleInUi,
            'message': entry.message.length > 600
                ? '${entry.message.substring(0, 600)}…'
                : entry.message,
            if (includeStackTrace && entry.stackTrace != null)
              'stackTrace': VibeDebugCapture.condenseStackTrace(
                entry.stackTrace,
              ),
          },
      ],
    };
  }

  /// 2. Inspecte le catalogue et l'état runtime de `DatasourceRegistry` et `DataProviderRegistry`.
  Future<Map<String, Object?>> getDatasourcesAndProviders(
    Map<String, Object?> args,
  ) async {
    final store = repositoryStore;
    if (store == null) {
      return const <String, Object?>{
        'available': false,
        'error': 'Aucun JsonRepositoryStore actif dans ce contexte.',
      };
    }

    await store.providers.ensureLoaded();
    await store.datasources.ensureLoaded();

    final filterDatasourceId = args['datasourceId'] is String
        ? (args['datasourceId'] as String).trim()
        : '';
    final filterProviderId = args['providerId'] is String
        ? (args['providerId'] as String).trim()
        : '';
    final includeProblems = args['includeProblems'] is bool
        ? args['includeProblems'] as bool
        : true;

    final datasourcesOut = <Map<String, Object?>>[];
    for (final ds in store.datasources.datasources) {
      if (filterDatasourceId.isNotEmpty && ds.id != filterDatasourceId) {
        continue;
      }
      final status = store.datasources.stateOf(ds.id).value;
      final problems = includeProblems
          ? store.datasources.problemsOf(ds)
          : const <String>[];
      datasourcesOut.add(<String, Object?>{
        'id': ds.id,
        'label': ds.label,
        'editable': store.datasources.isEditable(ds.id),
        'keyPath': ?ds.keyPath,
        'operations': <String, Object?>{
          for (final op in DatasourceOperation.values)
            op.name: ?ds.providerOf(op),
        },
        if (ds.search case final search?)
          'searchConfig': <String, Object?>{
            'provider': search.provider,
            'stateBinding': ?search.state?.toCompactJson(),
            'pagination': ?search.pagination?.toCompactJson(),
            'sort': ?search.sort?.toCompactJson(),
          },
        'status': <String, Object?>{
          'phase': status.phase.name,
          'lastCommand': ?status.command?.name,
          'run': status.run,
          'message': ?status.message,
          'page': status.page.toCompactJson(),
        },
        if (problems.isNotEmpty) 'problems': problems,
      });
    }

    final providersOut = <Map<String, Object?>>[];
    for (final p in store.providers.providers) {
      if (filterProviderId.isNotEmpty && p.id != filterProviderId) continue;
      final status = store.providers.statusOf(p.id).value;
      Map<String, Object?>? httpSummary;
      if (p is HttpDataProvider) {
        final req = p.config.request;
        httpSummary = <String, Object?>{
          'method': req.method,
          'url': req.url,
          if (req.headers.isNotEmpty)
            'headers': <String, String>{
              for (final h in req.headers.entries)
                h.key: _sanitizeHeaderValue(h.key, h.value),
            },
          if (req.query.isNotEmpty) 'queryKeys': req.query.keys.toList(),
          'autoParams': req.autoParams,
          'responsePath': ?p.config.responsePath,
        };
      }
      providersOut.add(<String, Object?>{
        'id': p.id,
        'label': p.label,
        'kind': p is HttpDataProvider ? 'http' : 'code',
        'editable': store.providers.isEditable(p.id),
        'filterRepositoryId': ?p.filterRepositoryId,
        'target': ?p.target?.toCompactJson(),
        'loading': ?p.loading?.toCompactJson(),
        'error': ?p.error?.toCompactJson(),
        'autoSearch': ?p.autoSearch?.toCompactJson(),
        'http': ?httpSummary,
        'status': <String, Object?>{
          'phase': status.phase.name,
          'run': status.run,
          'rowCount': ?status.rowCount,
          'message': ?status.message,
        },
      });
    }

    return <String, Object?>{
      'available': true,
      'datasourceCount': datasourcesOut.length,
      'providerCount': providersOut.length,
      'datasources': datasourcesOut,
      'providers': providersOut,
    };
  }

  static String _sanitizeHeaderValue(String headerName, String rawValue) {
    if (_pureEnvPlaceholder.hasMatch(rawValue.trim())) {
      return rawValue.trim();
    }
    if (_sensitiveHeaderName.hasMatch(headerName) ||
        rawValue.toLowerCase().contains('bearer ')) {
      return '***REDACTED***';
    }
    return rawValue;
  }

  /// 3. Audite les liaisons JSON, les composants orphelins et les états forcés sur l'écran courant.
  Future<Map<String, Object?>> inspectBindingsAndDiagnostics(
    Map<String, Object?> args,
  ) async {
    final appearance = readAppearance();
    final store = repositoryStore;
    final scope = readScope?.call();

    final requestedIds = <String>{
      if (args['componentIds'] case final List rawList)
        for (final item in rawList)
          if (item is String && item.trim().isNotEmpty) item.trim(),
    };

    final knownRepos = <String, Object?>{};
    final calculatedByRepo = <String, Set<String>>{};
    final schemasByRepo = <String, Map<String, Object?>?>{};
    if (store != null) {
      await store.providers.ensureLoaded();
      await store.datasources.ensureLoaded();
      final catalog = await store.catalog();
      for (final entry in catalog) {
        try {
          knownRepos[entry.id] = await store.readDocument(entry.id);
        } on FormatException {
          knownRepos[entry.id] = const <String, Object?>{};
        }
        calculatedByRepo[entry.id] = {
          for (final desc in store.calculatedAttributeCatalog(entry.id))
            desc.path,
        };
        try {
          schemasByRepo[entry.id] = await store.readJsonSchema(entry.id);
        } on FormatException {
          schemasByRepo[entry.id] = null;
        }
      }
    }

    final reachable = <String>{};
    final issues = <Map<String, Object?>>[];
    var checkedBindings = 0;

    for (final entry in schemasByRepo.entries) {
      final repoId = entry.key;
      final schema = entry.value;
      if (schema == null) continue;
      for (final extIssue in JsonSchemaFieldResolver.auditSchemaExtensions(
        schema,
      )) {
        issues.add(<String, Object?>{
          'repositoryId': repoId,
          'location': 'schemas[$repoId]${extIssue.schemaPath}',
          'kind': extIssue.kind,
          'message': extIssue.message,
        });
      }
      final doc = knownRepos[repoId];
      final validation = JsonSchemaValidator.validate(doc, schema);
      if (!validation.isValid) {
        for (final vIssue in validation.issues.take(5)) {
          issues.add(<String, Object?>{
            'repositoryId': repoId,
            'location': 'repositories[$repoId].${vIssue.instancePath}',
            'kind': 'json_schema_document_violation',
            'keyword': vIssue.keyword,
            'instancePath': vIssue.instancePath,
            'message': vIssue.message,
          });
        }
      }
    }

    void checkBinding({
      required String ownerId,
      required String location,
      required JsonTextBinding? binding,
      required String? inheritedRepoId,
      required int inheritedWildcards,
      required bool inTreeScope,
    }) {
      if (binding == null) return;
      if (requestedIds.isNotEmpty && !requestedIds.contains(ownerId)) return;
      checkedBindings++;

      final rawRepo = binding.repositoryId?.trim() ?? '';
      final effectiveRepo = rawRepo.isNotEmpty ? rawRepo : inheritedRepoId;

      if (effectiveRepo == null || effectiveRepo.isEmpty) {
        issues.add(<String, Object?>{
          'componentId': ownerId,
          'location': location,
          'kind': 'missing_repository_prefix_outside_list',
          'binding': binding.path,
          'message':
              'Ce binding omet le repositoryId hors de toute liste/table englobante (ex: branche sœur Maître/Détail). Ajoute le préfixe "<repoId>:${binding.path}".',
        });
        return;
      }

      if (store != null && !knownRepos.containsKey(effectiveRepo)) {
        issues.add(<String, Object?>{
          'componentId': ownerId,
          'location': location,
          'kind': 'unknown_repository',
          'repositoryId': effectiveRepo,
          'binding': binding.path,
          'message': 'Repository "$effectiveRepo" introuvable dans le store.',
        });
        return;
      }

      final JsonAttributePath parsed;
      try {
        parsed = JsonAttributePath(binding.path);
      } on FormatException catch (e) {
        issues.add(<String, Object?>{
          'componentId': ownerId,
          'location': location,
          'kind': 'invalid_path_syntax',
          'binding': binding.path,
          'message': e.message,
        });
        return;
      }

      if (parsed.calculated case final calc?) {
        final knownCalc = calculatedByRepo[effectiveRepo];
        if (knownCalc != null && !knownCalc.contains(calc.path)) {
          issues.add(<String, Object?>{
            'componentId': ownerId,
            'location': location,
            'kind': 'undeclared_calculated_attribute',
            'repositoryId': effectiveRepo,
            'binding': binding.path,
            'message':
                'Attribut calculé "${calc.path}" non déclaré sur "$effectiveRepo".',
          });
        }
        return;
      }

      final remainingWildcards = parsed.wildcardCount - inheritedWildcards;
      if (remainingWildcards > 0 && store != null) {
        final repoBinding = store.bindingOf(effectiveRepo);
        final hasAnySelection = repoBinding.arrays.any(
          (a) => a.selection != null,
        );
        if (!hasAnySelection) {
          issues.add(<String, Object?>{
            'componentId': ownerId,
            'location': location,
            'kind': 'unresolved_wildcard_no_selection',
            'severity': 'info',
            'repositoryId': effectiveRepo,
            'binding': binding.path,
            'message':
                'Le chemin contient $remainingWildcards joker(s) [?] en attente d’une ligne sélectionnée dans "$effectiveRepo" (utilisez preview_navigation_or_selection pour sélectionner une ligne).',
          });
        }
      }

      if (!inTreeScope && store != null && knownRepos[effectiveRepo] is Map) {
        final doc = knownRepos[effectiveRepo] as Map;
        final rootKey = _extractRootSegmentKey(binding.path);
        if (rootKey != null && !doc.containsKey(rootKey)) {
          issues.add(<String, Object?>{
            'componentId': ownerId,
            'location': location,
            'kind': 'missing_root_key_in_document',
            'repositoryId': effectiveRepo,
            'binding': binding.path,
            'availableRootKeys': doc.keys.take(15).map((k) => '$k').toList(),
            'message':
                'La clé racine "$rootKey" est absente du repository "$effectiveRepo".',
          });
        }
      }
    }

    void visit(
      String id, {
      String? inheritedRepo,
      int inheritedWildcards = 0,
      bool inTreeScope = false,
      Set<String>? branchSeen,
    }) {
      reachable.add(id);
      final seen = branchSeen ?? <String>{};
      if (!seen.add(id)) return;

      final config = appearance.components[id];
      final style = appearance.styles[id];
      final itemStyle = appearance.styles['$id:item'];

      if (style != null) {
        for (final pb in style.propertyBindings.entries) {
          checkBinding(
            ownerId: id,
            location: 'styles[$id].propertyBindings.${pb.key.name}',
            binding: pb.value,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
        }
        checkBinding(
          ownerId: id,
          location: 'styles[$id].states.binding',
          binding: style.states?.binding,
          inheritedRepoId: inheritedRepo,
          inheritedWildcards: inheritedWildcards,
          inTreeScope: inTreeScope,
        );
      }
      if (itemStyle != null) {
        checkBinding(
          ownerId: '$id:item',
          location: 'styles[$id:item].states.binding',
          binding: itemStyle.states?.binding,
          inheritedRepoId: config is SuperListViewConfig
              ? (config.binding?.repositoryId ?? inheritedRepo)
              : inheritedRepo,
          inheritedWildcards: config is SuperListViewConfig
              ? inheritedWildcards + 1
              : inheritedWildcards,
          inTreeScope: inTreeScope,
        );
      }

      for (final behavior in appearance.behaviorsFor(id)) {
        if (!behavior.enabled) continue;
        final validator = behavior.validator;
        if (validator != null) {
          for (final targetId in validator.referencedComponentIds) {
            final targetExists =
                appearance.components.containsKey(targetId) ||
                appearance.styles.containsKey(targetId) ||
                slotIndex.entriesFor(targetId).isNotEmpty;
            if (!targetExists &&
                (requestedIds.isEmpty || requestedIds.contains(id))) {
              issues.add(<String, Object?>{
                'componentId': id,
                'location': 'behaviors[$id].validator',
                'kind': 'unknown_validator_target',
                'targetComponentId': targetId,
                'message':
                    'Composant cible "$targetId" référencé par le validateur du comportement "${behavior.id}" introuvable.',
              });
            }
          }
          for (final binding in validator.referencedBindings) {
            checkBinding(
              ownerId: id,
              location: 'behaviors[$id].validator',
              binding: binding,
              inheritedRepoId: inheritedRepo,
              inheritedWildcards: inheritedWildcards,
              inTreeScope: inTreeScope,
            );
          }
        }
        final action = behavior.action;
        for (final targetId in action.referencedComponentIds) {
          final targetExists =
              appearance.components.containsKey(targetId) ||
              appearance.styles.containsKey(targetId) ||
              slotIndex.entriesFor(targetId).isNotEmpty;
          if (!targetExists &&
              (requestedIds.isEmpty || requestedIds.contains(id))) {
            issues.add(<String, Object?>{
              'componentId': id,
              'location': 'behaviors[$id].${action.type}',
              'kind': 'unknown_action_target',
              'targetComponentId': targetId,
              'message':
                  'Composant cible "$targetId" référencé par l’action ${action.type} du comportement "${behavior.id}" introuvable.',
            });
          }
        }
        if (action is TooltipAction) {
          checkBinding(
            ownerId: id,
            location: 'behaviors[$id].onTooltip',
            binding: action.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
        } else if (action is ZoneSizeBindingAction) {
          checkBinding(
            ownerId: id,
            location: 'behaviors[$id].bindZoneSize(${action.zone.name})',
            binding: action.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
        } else if (action is StateBindingAction) {
          checkBinding(
            ownerId: id,
            location: 'behaviors[$id].bindState(${action.state.name})',
            binding: action.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
        } else if (action is AddArrayItemAction) {
          checkBinding(
            ownerId: id,
            location: 'behaviors[$id].addArrayItem',
            binding: action.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
        } else if (action is CreationDefaultAction && action.binding != null) {
          checkBinding(
            ownerId: id,
            location: 'behaviors[$id].creationDefault',
            binding: action.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
        } else if (action is SearchProviderAction && store != null) {
          if (requestedIds.isEmpty || requestedIds.contains(id)) {
            if (store.providers.provider(action.providerId) == null) {
              issues.add(<String, Object?>{
                'componentId': id,
                'location': 'behaviors[$id].searchProvider',
                'kind': 'unknown_provider',
                'providerId': action.providerId,
                'message':
                    'Provider "${action.providerId}" introuvable dans DataProviderRegistry.',
              });
            }
          }
        } else if (action is DatasourceAction && store != null) {
          if (requestedIds.isEmpty || requestedIds.contains(id)) {
            if (store.datasources.datasource(action.datasourceId) == null) {
              issues.add(<String, Object?>{
                'componentId': id,
                'location': 'behaviors[$id].datasource',
                'kind': 'unknown_datasource',
                'datasourceId': action.datasourceId,
                'message':
                    'Datasource "${action.datasourceId}" introuvable dans DatasourceRegistry.',
              });
            }
          }
        }
      }

      String? childInheritedRepo = inheritedRepo;
      var childWildcards = inheritedWildcards;
      var childInTree = inTreeScope;

      switch (config) {
        case final SuperValueConfig v:
          checkBinding(
            ownerId: id,
            location: 'components[$id].binding',
            binding: v.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
          if (v.binding != null &&
              v.kind.isText &&
              !v.obscureText &&
              !inTreeScope &&
              (requestedIds.isEmpty || requestedIds.contains(id))) {
            final rawRepo = v.binding!.repositoryId?.trim() ?? '';
            final effectiveRepo = rawRepo.isNotEmpty ? rawRepo : inheritedRepo;
            if (effectiveRepo != null &&
                effectiveRepo.isNotEmpty &&
                knownRepos.containsKey(effectiveRepo) &&
                !JsonTextBinding.isCalculatedPath(v.binding!.path)) {
              final schema = schemasByRepo[effectiveRepo];
              var effectiveField = v.field;
              if (v.field.useRepositorySchema && schema != null) {
                final profile = JsonSchemaFieldResolver.resolve(
                  schema,
                  v.binding!.path,
                );
                if (profile != null) {
                  effectiveField = v.field.applySchemaProfile(
                    profile,
                    allowMaskAndFormat: !v.obscureText && v.maxLines == 1,
                  );
                }
              }
              if (effectiveField.hasConstraints ||
                  effectiveField.hasMaskOrFormat) {
                final samples = _sampleValuesAtPath(
                  knownRepos[effectiveRepo],
                  v.binding!.path,
                );
                for (final sample in samples) {
                  final rawText = sample.value?.toString() ?? '';
                  if (rawText.isEmpty && !effectiveField.required) continue;
                  final display = effectiveField.toDisplayText(rawText);
                  final errorMsg = effectiveField.validateValue(
                    rawText,
                    displayValue: display,
                    obscureText: v.obscureText,
                  );
                  if (errorMsg != null) {
                    issues.add(<String, Object?>{
                      'componentId': id,
                      'location': 'components[$id].binding',
                      'kind':
                          'repository_value_incompatible_with_field_or_schema',
                      'repositoryId': effectiveRepo,
                      'binding': v.binding!.path,
                      'samplePath': sample.concretePath,
                      'sampleValue': sample.value,
                      'message':
                          'La valeur "${sample.value}" à "${sample.concretePath}" ne respecte pas les contraintes/masques du champ ($errorMsg).',
                    });
                    break;
                  }
                }
              }
            }
          }
          for (final pb in v.propertyBindings.entries) {
            checkBinding(
              ownerId: id,
              location: 'components[$id].propertyBindings.${pb.key.name}',
              binding: pb.value,
              inheritedRepoId: inheritedRepo,
              inheritedWildcards: inheritedWildcards,
              inTreeScope: inTreeScope,
            );
          }
          checkBinding(
            ownerId: id,
            location: 'components[$id].states.binding',
            binding: v.states?.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
          if ((requestedIds.isEmpty || requestedIds.contains(id)) &&
              knownRepos.isNotEmpty &&
              v.mode == SuperValueMode.display &&
              v.binding == null) {
            final usage = appearance.usages[id];
            final isExplicitStatic =
                usage?.kind == ComponentUsageKind.staticData;
            final isDynamicUsage =
                usage?.kind == ComponentUsageKind.dynamicData;
            if (!isExplicitStatic &&
                (isDynamicUsage ||
                    _looksLikeMissingCalculation(
                      id: id,
                      label: v.label,
                      text: v.initialText,
                      usageKey: usage?.translationKey,
                    ))) {
              issues.add(<String, Object?>{
                'componentId': id,
                'location': 'components[$id].binding',
                'kind': 'suspected_missing_calculation',
                if (v.label.trim().isNotEmpty) 'label': v.label.trim(),
                if (v.initialText.trim().isNotEmpty)
                  'initialText': v.initialText.trim(),
                if (usage != null) 'usageKind': usage.kind.name,
                'message':
                    'Ce composant KPI/métrique semble afficher une valeur statique ou placeholder sans liaison ni attribut calculé `@calculs` alors que des repositories existent (${knownRepos.keys.join(', ')}).',
              });
            }
          }
        case final SuperIndicatorConfig ind:
          for (final pb in ind.propertyBindings.entries) {
            checkBinding(
              ownerId: id,
              location: 'components[$id].propertyBindings.${pb.key.name}',
              binding: pb.value,
              inheritedRepoId: inheritedRepo,
              inheritedWildcards: inheritedWildcards,
              inTreeScope: inTreeScope,
            );
          }
          checkBinding(
            ownerId: id,
            location: 'components[$id].states.binding',
            binding: ind.states?.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
          if ((requestedIds.isEmpty || requestedIds.contains(id)) &&
              knownRepos.isNotEmpty &&
              !ind.propertyBindings.containsKey(SuperIndicatorProperty.label)) {
            final usage = appearance.usages[id];
            final isExplicitStatic =
                usage?.kind == ComponentUsageKind.staticData;
            final isDynamicUsage =
                usage?.kind == ComponentUsageKind.dynamicData;
            if (!isExplicitStatic &&
                (isDynamicUsage ||
                    _looksLikeMissingCalculation(
                      id: id,
                      label: ind.label,
                      text: ind.label,
                      usageKey: usage?.translationKey,
                    ))) {
              issues.add(<String, Object?>{
                'componentId': id,
                'location': 'components[$id].propertyBindings.label',
                'kind': 'suspected_missing_calculation',
                if (ind.label.trim().isNotEmpty) 'label': ind.label.trim(),
                if (usage != null) 'usageKind': usage.kind.name,
                'message': 'Cet indicateur semble représenter une métrique calculée sans liaison de données ni `@calculs`.',
              });
            }
          }
        case final SuperLayoutConfig layout:
          for (final entry in layout.slotSizeConstraints.entries) {
            final childId = entry.key;
            if (requestedIds.isNotEmpty &&
                !requestedIds.contains(id) &&
                !requestedIds.contains(childId)) {
              continue;
            }
            final sc = entry.value;
            if (sc.fitContent == true) continue;
            final childStyle = appearance.styles[childId];
            final margin = childStyle?.outerMargin ?? EdgeInsets.zero;
            final padding =
                (childStyle?.contentPadding ?? EdgeInsets.zero) +
                sc.contentPadding;
            final totalH = margin.horizontal + padding.horizontal;
            final totalV = margin.vertical + padding.vertical;
            final fixedW = sc.preferredWidth?.unit == SlotSizeUnit.pixels
                ? sc.preferredWidth!.value
                : (sc.maxWidth?.unit == SlotSizeUnit.pixels
                      ? sc.maxWidth!.value
                      : null);
            final fixedH = sc.preferredHeight?.unit == SlotSizeUnit.pixels
                ? sc.preferredHeight!.value
                : (sc.maxHeight?.unit == SlotSizeUnit.pixels
                      ? sc.maxHeight!.value
                      : null);
            if ((fixedW != null && fixedW - totalH <= 8.0) ||
                (fixedH != null && fixedH - totalV <= 8.0)) {
              issues.add(<String, Object?>{
                'componentId': childId,
                'parentId': id,
                'location': 'components[$id].slotSizeConstraints.$childId',
                'kind': 'excessive_margin_or_padding_for_fixed_size',
                'fixedWidth': ?fixedW,
                'fixedHeight': ?fixedH,
                'horizontalInsets': totalH,
                'verticalInsets': totalV,
                'message':
                    'Les marges/paddings cumulés (${totalH.round()}×${totalV.round()} px) écrasent ou coupent le contenu du slot "$childId" contraint en taille fixe (${fixedW?.round() ?? 'auto'}×${fixedH?.round() ?? 'auto'} px).',
              });
            }
          }
        case final SuperActionConfig a:
          for (final pb in a.propertyBindings.entries) {
            checkBinding(
              ownerId: id,
              location: 'components[$id].propertyBindings.${pb.key.name}',
              binding: pb.value,
              inheritedRepoId: inheritedRepo,
              inheritedWildcards: inheritedWildcards,
              inTreeScope: inTreeScope,
            );
          }
          checkBinding(
            ownerId: id,
            location: 'components[$id].states.binding',
            binding: a.states?.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
        case final SuperListViewConfig l:
          checkBinding(
            ownerId: id,
            location: 'components[$id].binding',
            binding: l.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
          if (l.allowRemove &&
              !JsonTextBinding.isCalculatedPath(l.binding?.path ?? '') &&
              (requestedIds.isEmpty || requestedIds.contains(id))) {
            final rowId = (l.itemId != null && l.itemId!.trim().isNotEmpty)
                ? l.itemId!.trim()
                : '$id:item';
            final rowStyle = appearance.styles[rowId] ?? appearance.styles[id];
            final baseRightPadding =
                (rowStyle?.contentPadding.right ?? 0.0) +
                (l.itemSize?.contentPadding.right ?? 0.0);
            final hasEast =
                l.template.east &&
                l.template.placementsOf(SuperLayoutZone.east).isNotEmpty;
            final rightEdgeZones = <SuperLayoutZone>[
              if (hasEast)
                SuperLayoutZone.east
              else if (l.template
                  .placementsOf(SuperLayoutZone.center)
                  .isNotEmpty)
                SuperLayoutZone.center,
              if (l.template.north &&
                  l.template.placementsOf(SuperLayoutZone.north).isNotEmpty &&
                  (!l.template.east || l.template.ne != CornerMerge.column))
                SuperLayoutZone.north,
            ];
            final minZoneRightPadding = rightEdgeZones.isEmpty
                ? 0.0
                : rightEdgeZones
                      .map((z) => l.template.flowOf(z).contentPadding.right)
                      .reduce(math.min);
            final effectiveRightPadding =
                baseRightPadding + minZoneRightPadding;
            if (effectiveRightPadding < _minListRemoveRightPadding) {
              issues.add(<String, Object?>{
                'componentId': id,
                'location': 'styles[$rowId].paddingInsets',
                'kind': 'list_remove_button_overlap_risk',
                'effectiveRightPadding': effectiveRightPadding,
                'recommendedMinRightPadding': _minListRemoveRightPadding,
                'message':
                    'Cette ListView active allowRemove=true alors que la marge droite effective de la ligne ($effectiveRightPadding px) est inférieure à $_minListRemoveRightPadding px : le bouton supprimer superposé en haut à droite risque de recouvrir le contenu. Définis "paddingInsets": [top, 38, bottom, left] sur styles["$rowId"].',
              });
            }
          }
          final r = l.binding?.repositoryId?.trim() ?? '';
          if (r.isNotEmpty) childInheritedRepo = r;
          childWildcards = inheritedWildcards + 1;
        case final SuperTableConfig t:
          checkBinding(
            ownerId: id,
            location: 'components[$id].binding',
            binding: t.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
          final r = t.binding?.repositoryId?.trim() ?? '';
          if (r.isNotEmpty) childInheritedRepo = r;
          childWildcards = inheritedWildcards + 1;
        case final SuperTreeViewConfig tr:
          checkBinding(
            ownerId: id,
            location: 'components[$id].binding',
            binding: tr.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
          final r = tr.binding?.repositoryId?.trim() ?? '';
          if (r.isNotEmpty) childInheritedRepo = r;
          childWildcards = inheritedWildcards + 1;
          childInTree = true;
        case final SuperTabConfig tab:
          if (tab.mode == SuperTabMode.dynamic) {
            checkBinding(
              ownerId: id,
              location: 'components[$id].binding',
              binding: tab.binding,
              inheritedRepoId: inheritedRepo,
              inheritedWildcards: inheritedWildcards,
              inTreeScope: inTreeScope,
            );
            final r = tab.binding?.repositoryId?.trim() ?? '';
            if (r.isNotEmpty) childInheritedRepo = r;
            childWildcards = inheritedWildcards + 1;
          }
        case final SuperConditionalConfig cond:
          checkBinding(
            ownerId: id,
            location: 'components[$id].binding',
            binding: cond.binding,
            inheritedRepoId: inheritedRepo,
            inheritedWildcards: inheritedWildcards,
            inTreeScope: inTreeScope,
          );
        default:
          break;
      }

      for (final childId in VibeScopeHelpers.childrenOfComponent(config)) {
        visit(
          childId,
          inheritedRepo: childInheritedRepo,
          inheritedWildcards: childWildcards,
          inTreeScope: childInTree,
          branchSeen: seen,
        );
      }
      seen.remove(id);
    }

    final roots = <String>{
      if (scope != null) ...VibeScopeHelpers.scopeRootIds(appearance, scope),
      if (scope == null) ...<String>[
        ...?registry?.instantiatedComponentIds,
        ...slotIndex.mountedComponentIds,
        for (final p in appearance.pageCatalog.pages) p.id,
        if (appearance.components.containsKey('root')) 'root',
        if (appearance.components.containsKey('mainLayout')) 'mainLayout',
      ],
    };
    if (roots.isEmpty) {
      roots.addAll(appearance.components.keys);
    }
    for (final rootId in roots) {
      visit(rootId);
    }

    final orphanIds = scope != null
        ? const <String>[]
        : <String>[
            for (final id in appearance.components.keys)
              if (!reachable.contains(id)) id,
          ];
    final emptyMountedRootIds = scope == null && orphanIds.isNotEmpty
        ? VibeGhostComponentDetector.findEmptyRootLayoutIds(
            appearance,
            mountedComponentIds: slotIndex.mountedComponentIds,
          )
        : const <String>[];

    final forcedStates = <Map<String, Object?>>[];
    for (final entry in slotIndex.allEntries) {
      if (entry.zoneId != null && entry.zoneId!.isNotEmpty) continue;
      if (requestedIds.isNotEmpty &&
          !requestedIds.contains(entry.componentId)) {
        continue;
      }
      final ctx = entry.slotContext();
      if (ctx == null || !ctx.mounted) continue;
      final stateScope = ctx
          .getElementForInheritedWidgetOfExactType<
            ComponentBehaviorStateScope
          >()
          ?.widget;
      if (stateScope is ComponentBehaviorStateScope &&
          (stateScope.invisible ||
              stateScope.disabled ||
              stateScope.readOnly)) {
        forcedStates.add(<String, Object?>{
          'componentId': entry.componentId,
          if (stateScope.invisible) 'invisible': true,
          if (stateScope.invisible && stateScope.maintainSize)
            'maintainSize': true,
          if (stateScope.disabled) 'disabled': true,
          if (stateScope.readOnly) 'readOnly': true,
        });
      }
    }

    final recentErrors = debugEntries
        .where((e) => e.type == DebugEntryType.error)
        .length;
    final activeRepoError = store?.errors.value;

    return <String, Object?>{
      'checkedBindings': checkedBindings,
      'issueCount': issues.length,
      'issues': issues,
      'orphanComponentCount': orphanIds.length,
      if (orphanIds.isNotEmpty)
        'orphanComponentIds': orphanIds.take(30).toList(),
      if (emptyMountedRootIds.isNotEmpty)
        'emptyMountedRootIds': emptyMountedRootIds,
      if (forcedStates.isNotEmpty) 'forcedBehaviorStates': forcedStates,
      'activeRepositoryError': ?activeRepoError,
      if (recentErrors > 0) 'debugErrorCount': recentErrors,
    };
  }

  static List<({String concretePath, Object? value})> _sampleValuesAtPath(
    Object? root,
    String rawPath, {
    int maxSamples = 3,
  }) {
    final JsonAttributePath parsed;
    try {
      parsed = JsonAttributePath(rawPath);
    } on FormatException {
      return const [];
    }
    final results = <({String concretePath, Object? value})>[];
    final steps = parsed.steps;

    void walk(Object? current, int stepIndex, String builtPath) {
      if (results.length >= maxSamples) return;
      if (stepIndex >= steps.length) {
        if (current is! Map && current is! List) {
          results.add((concretePath: builtPath, value: current));
        }
        return;
      }
      final step = steps[stepIndex];
      if (step.key != null) {
        if (current is! Map) return;
        final next = current[step.key];
        final nextPath = builtPath.isEmpty
            ? step.key!
            : '$builtPath.${step.key!}';
        walk(next, stepIndex + 1, nextPath);
      } else if (step.index != null) {
        if (current is! List) return;
        final idx = step.index!;
        if (idx < 0 || idx >= current.length) return;
        walk(current[idx], stepIndex + 1, '$builtPath[$idx]');
      } else {
        if (current is! List) return;
        final limit = math.min(current.length, maxSamples);
        for (var i = 0; i < limit && results.length < maxSamples; i++) {
          walk(current[i], stepIndex + 1, '$builtPath[$i]');
        }
      }
    }

    walk(root, 0, '');
    return results;
  }

  static String? _extractRootSegmentKey(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed.startsWith('@')) return null;
    final stop = trimmed.indexOf(RegExp(r'[.\[]'));
    return stop < 0 ? trimmed : trimmed.substring(0, stop);
  }

  static final RegExp _placeholderCalcTextPattern = RegExp(
    r'^(?:--|—|n/?a|tbd|\?+|\.\.\.|0(?:[.,]0+)?\s*(?:€|\$|%|pts?)?)$',
    caseSensitive: false,
  );

  static final RegExp _aggregateKeywordPattern = RegExp(
    r'\b(?:total|totaux|somme|sum|moyenne|avg|average|nombre|count|nb|solde|balance|taux|rate|ratio|pourcentage|kpi|montant\s+total|chiffre\s+d.affaires?|marge\s+totale|calcul[eé]?)\b',
    caseSensitive: false,
  );

  static bool _looksLikeMissingCalculation({
    required String id,
    required String label,
    required String text,
    required String? usageKey,
  }) {
    final trimmedText = text.trim();
    if (trimmedText.isNotEmpty &&
        _placeholderCalcTextPattern.hasMatch(trimmedText)) {
      return true;
    }
    final combined = '${id.trim()} ${label.trim()} ${usageKey?.trim() ?? ''}'
        .trim();
    if (combined.isEmpty) return false;
    if (!_aggregateKeywordPattern.hasMatch(combined)) return false;
    // Évite les faux positifs sur de simples titres de section sans valeur chiffrée.
    if (trimmedText.isEmpty) return true;
    return RegExp(r'[0-9%€$]').hasMatch(trimmedText) ||
        _placeholderCalcTextPattern.hasMatch(trimmedText);
  }

  /// 4. Résout les couleurs `ThemeColorRole` (`theme:*`) en `#RRGGBB` et vérifie le contraste WCAG AA.
  Future<Map<String, Object?>> getThemeAndContrast(
    Map<String, Object?> args,
  ) async {
    final appearance = readAppearance();
    final ctx = resolvePrimaryContext();
    final onlyIssues = args['onlyIssues'] == true;
    final requestedIds = <String>{
      if (args['componentIds'] case final List rawList)
        for (final item in rawList)
          if (item is String && item.trim().isNotEmpty) item.trim(),
    };

    final platformBrightness = ctx != null && ctx.mounted
        ? MediaQuery.maybePlatformBrightnessOf(ctx) ?? Brightness.light
        : WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final effectiveBrightness = switch (appearance.mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };
    final theme = appearance.theme(effectiveBrightness);
    final scheme = theme.colorScheme;

    final resolvedRoles = <String, String>{
      for (final role in ThemeColorRole.values)
        'theme:${role.name}': _toHex(role.resolve(scheme)),
    };

    Color resolveColor(Color? color, Color fallback) {
      if (color == null) return fallback;
      if (color is ThemeColor) return color.role.resolve(scheme);
      return color;
    }

    final bgSurfaceColor = resolveColor(
      appearance.backgroundStyle.color,
      scheme.surface,
    );

    final parentSurfaceOf = <String, Color>{};
    void propagateSurface(String id, Color currentBg, Set<String> seen) {
      if (!seen.add(id)) return;
      parentSurfaceOf[id] = currentBg;
      var nextBg = currentBg;
      final style = appearance.styles[id];
      if (style?.color != null) {
        final candidate = resolveColor(style!.color, currentBg);
        nextBg = Color.alphaBlend(candidate, currentBg);
      }
      final config = appearance.components[id];
      final itemStyle = appearance.styles['$id:item'];
      if (config is SuperListViewConfig && itemStyle?.color != null) {
        nextBg = Color.alphaBlend(
          resolveColor(itemStyle!.color, nextBg),
          nextBg,
        );
      }
      for (final childId in VibeScopeHelpers.childrenOfComponent(config)) {
        propagateSurface(childId, nextBg, seen);
      }
      seen.remove(id);
    }

    for (final rootId in <String>{
      ...?registry?.instantiatedComponentIds,
      ...slotIndex.mountedComponentIds,
      for (final p in appearance.pageCatalog.pages) p.id,
      ...appearance.components.keys,
    }) {
      if (!parentSurfaceOf.containsKey(rootId)) {
        propagateSurface(rootId, bgSurfaceColor, <String>{});
      }
    }

    final checks = <Map<String, Object?>>[];
    var issueCount = 0;

    final candidateIds = requestedIds.isNotEmpty
        ? requestedIds
        : <String>{
            ...slotIndex.mountedComponentIds,
            ...appearance.components.keys,
          };

    for (final id in candidateIds) {
      final config = appearance.components[id];
      final surfaceBg = parentSurfaceOf[id] ?? bgSurfaceColor;
      Color? fg;
      Color? bg;
      var isLargeText = false;

      if (config is SuperValueConfig) {
        fg = resolveColor(config.color, scheme.onSurface);
        bg = surfaceBg;
        final size = config.fontSize ?? 14.0;
        final bold =
            config.fontWeight != null &&
            config.fontWeight!.value >= FontWeight.w700.value;
        isLargeText = size >= 18.0 || (size >= 14.0 && bold);
      } else if (config is SuperActionConfig) {
        final variant = config.variant ?? SuperActionVariant.filled;
        final defaultBg = switch (variant) {
          SuperActionVariant.filled => scheme.primary,
          SuperActionVariant.tonal => scheme.secondaryContainer,
          SuperActionVariant.elevated => scheme.surfaceContainerLow,
          SuperActionVariant.surface => resolveColor(
            config.style.color,
            surfaceBg,
          ),
          SuperActionVariant.outlined ||
          SuperActionVariant.text ||
          SuperActionVariant.icon => surfaceBg,
        };
        final defaultFg = switch (variant) {
          SuperActionVariant.filled => scheme.onPrimary,
          SuperActionVariant.tonal => scheme.onSecondaryContainer,
          _ => scheme.primary,
        };
        bg = Color.alphaBlend(
          resolveColor(config.backgroundColor, defaultBg),
          surfaceBg,
        );
        fg = resolveColor(config.color ?? config.iconColor, defaultFg);
        final size = config.fontSize ?? 14.0;
        final bold =
            config.fontWeight != null &&
            config.fontWeight!.value >= FontWeight.w700.value;
        isLargeText = size >= 18.0 || (size >= 14.0 && bold);
      }

      if (fg == null || bg == null) continue;
      final blendedFg = Color.alphaBlend(fg, bg);
      final ratio = _contrastRatio(blendedFg, bg);
      final threshold = isLargeText ? 3.0 : 4.5;
      final passesAA = ratio >= threshold;
      if (!passesAA) issueCount++;
      if (onlyIssues && passesAA) continue;

      checks.add(<String, Object?>{
        'componentId': id,
        'type': config?.componentType ?? 'unknown',
        'foreground': _toHex(blendedFg),
        'background': _toHex(bg),
        'contrastRatio': (ratio * 100).roundToDouble() / 100,
        'requiredAA': threshold,
        'passesAA': passesAA,
      });
    }

    return <String, Object?>{
      'mode': appearance.mode.name,
      'effectiveBrightness': effectiveBrightness.name,
      'accent': _toHex(appearance.accent),
      'backgroundSurface': _toHex(bgSurfaceColor),
      'themeRoles': resolvedRoles,
      'contrastIssueCount': issueCount,
      'contrastChecks': checks.take(40).toList(),
    };
  }

  static double _contrastRatio(Color a, Color b) {
    final lumA = a.computeLuminance();
    final lumB = b.computeLuminance();
    final lighter = math.max(lumA, lumB);
    final darker = math.min(lumA, lumB);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static String _toHex(Color c) => JsonColor.toHex(c);

  /// 5. Expose les constructeurs/extensions de [Registry], les polices et la sélection active.
  Future<Map<String, Object?>> getRegistryAndSelection(
    Map<String, Object?> args,
  ) async {
    final includeComponents = args['includeComponents'] is bool
        ? args['includeComponents'] as bool
        : true;
    final includeFonts = args['includeFonts'] is bool
        ? args['includeFonts'] as bool
        : true;

    final reg = registry;
    final buildersOut = <Map<String, Object?>>[];
    if (includeComponents && reg != null) {
      final sortedKeys = reg.registry.keys.toList()..sort();
      for (final key in sortedKeys) {
        final builder = reg.registry[key]!;
        buildersOut.add(<String, Object?>{
          'key': key,
          'placementType': 'registry:$key',
          'label': ?builder.label,
          'family': builder.addFamily.name,
          if (builder.tags.isNotEmpty) 'tags': builder.tags.toList(),
          if (builder.placementTags.isNotEmpty)
            'placementTags': builder.placementTags.toList(),
          'duplicable': builder.duplication != null,
        });
      }
    }

    final focusCtx = LayoutSelection.focus.value?.context;
    final focusedSlot = (focusCtx != null && focusCtx.mounted)
        ? EditorSlotState.resolveFromContext(focusCtx)
        : null;

    return <String, Object?>{
      'selection': <String, Object?>{
        'path': LayoutSelection.path.value,
        if (focusedSlot != null && focusedSlot.mounted)
          'focusedSlot': <String, Object?>{
            'componentId': focusedSlot.effectiveComponentId,
            'zoneId': ?focusedSlot.widget.zoneId,
            'label': focusedSlot.titleLabel,
          },
      },
      if (includeComponents) ...<String, Object?>{
        'hasRegistry': reg != null,
        'registeredBuilderCount': buildersOut.length,
        'registeredBuilders': buildersOut,
        if (reg != null && reg.components.isNotEmpty)
          'customComponents': reg.components.keys.toList(),
      },
      if (includeFonts) ...<String, Object?>{
        'availableFontFamilies': (fontManager ?? DynamicFontManager.shared)
            .effectiveAvailableFontFamilies(),
        'bundledFontFamilies': Registry.bundledPackageFontFamilies.toList(),
        'dynamicFontFamilies':
            (fontManager ?? DynamicFontManager.shared).loadedFontFamilies,
        'dynamicGoogleFontsSupported': true,
      },
    };
  }

  /// 6. Navigue temporairement vers une page ou sélectionne une ligne Maître/Détail en aperçu.
  Future<VibeToolResult> previewNavigationOrSelection(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) async {
    final appearance = readAppearance();
    final pageId = args['pageId'] is String
        ? (args['pageId'] as String).trim()
        : '';
    final routePath = args['routePath'] is String
        ? (args['routePath'] as String).trim()
        : '';
    final repositoryId = args['repositoryId'] is String
        ? (args['repositoryId'] as String).trim()
        : '';
    final arrayTemplate = args['arrayTemplate'] is String
        ? (args['arrayTemplate'] as String).trim()
        : '';
    final clearSelection = args['clearSelection'] == true;
    final rawIndex = args['index'];

    var didSomething = false;
    final actions = <String, Object?>{};
    final visibleOnly = readVisibleOnly?.call() == true;

    if (pageId.isNotEmpty || routePath.isNotEmpty) {
      if (visibleOnly) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message: 'Mode « Uniquement visible » actif : la navigation vers une autre page/route est désactivée.',
        );
      }
      final routing = pageRouting;
      if (routing == null) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message: 'Aucun EditorPageRouter actif : impossible de changer de route en aperçu.',
        );
      }
      routing.synchronize(appearance.pageCatalog);
      String? targetLocation;
      String? targetPageId;
      if (pageId.isNotEmpty) {
        final page = appearance.pageCatalog.pages
            .where((p) => p.id == pageId)
            .firstOrNull;
        if (page == null) {
          return VibeToolResult.error(
            callId: callId,
            name: toolName,
            message: 'Page "$pageId" introuvable dans pageCatalog.',
          );
        }
        targetPageId = page.id;
        targetLocation = routing.locationFor(page, page.defaultParameters);
      } else {
        if (!routePath.startsWith('/')) {
          return VibeToolResult.error(
            callId: callId,
            name: toolName,
            message: 'routePath doit commencer par "/" (reçu: "$routePath").',
          );
        }
        targetLocation = routePath;
        targetPageId = routing
            .pageAt(Uri.parse(routePath), catalog: appearance.pageCatalog)
            ?.id;
      }
      if (targetPageId != null && ensurePageLoaded != null) {
        await ensurePageLoaded!(targetPageId);
      }
      previewTracker?.markNavigated();
      routing.openLocation(targetLocation);
      actions['navigatedTo'] = targetLocation;
      didSomething = true;
    }

    if (repositoryId.isNotEmpty && arrayTemplate.isNotEmpty) {
      final store = repositoryStore;
      if (store == null) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'Aucun JsonRepositoryStore actif pour modifier la sélection.',
        );
      }
      final String canonicalTemplate;
      try {
        canonicalTemplate = JsonAttributePath(arrayTemplate).toString();
      } on FormatException catch (e) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message: 'arrayTemplate invalide ("$arrayTemplate") : ${e.message}',
        );
      }

      previewTracker?.snapshotSelectionIfNeeded(
        store,
        repositoryId,
        canonicalTemplate,
      );
      final arrayBinding = store
          .bindingOf(repositoryId)
          .array(canonicalTemplate);
      if (clearSelection) {
        arrayBinding.clear();
        actions['selection'] = <String, Object?>{
          'repositoryId': repositoryId,
          'arrayTemplate': canonicalTemplate,
          'cleared': true,
        };
      } else {
        final index = rawIndex is num ? rawIndex.toInt() : 0;
        if (index < 0) {
          return VibeToolResult.error(
            callId: callId,
            name: toolName,
            message: 'index doit être >= 0 (reçu: $index).',
          );
        }
        final parents = <int>[
          if (args['parentIndices'] case final List rawParents)
            for (final p in rawParents)
              if (p is num) p.toInt(),
        ];
        final nodePath =
            args['nodePath'] is String &&
                (args['nodePath'] as String).trim().isNotEmpty
            ? (args['nodePath'] as String).trim()
            : null;
        arrayBinding.select(parents, index, nodePath: nodePath);
        actions['selection'] = <String, Object?>{
          'repositoryId': repositoryId,
          'arrayTemplate': canonicalTemplate,
          'selection': arrayBinding.selection,
          'nodePath': ?arrayBinding.selectedNodePath,
        };
      }
      didSomething = true;
    }

    final tabComponentId = args['tabComponentId'] is String
        ? (args['tabComponentId'] as String).trim()
        : '';
    final tabIdArg = args['tabId'] is String
        ? (args['tabId'] as String).trim()
        : '';
    final rawTabIndex = args['tabIndex'];
    final wantsTabSwitch =
        tabComponentId.isNotEmpty || tabIdArg.isNotEmpty || rawTabIndex is num;

    if (wantsTabSwitch) {
      if (visibleOnly) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message: 'Mode « Uniquement visible » actif : interdit de changer d’onglet. Reste sur l’onglet actif et la position de scroll courante.',
        );
      }
      final activeScope = readScope?.call();
      final rootCtx = slotIndex.activeAppRootKey?.currentContext;
      final rootBox = rootCtx?.findRenderObject();
      final stopAt = rootBox is RenderBox && rootBox.attached ? rootBox : null;
      final activeTabs = <VibeMountedTabEntry>[];
      final seenTabIds = <String>{};
      for (final entry in slotIndex.allTabEntries.reversed) {
        final ctx = entry.tabContext();
        if (ctx == null || !ctx.mounted) continue;
        final ro = ctx.findRenderObject();
        if (ro != null &&
            (!ro.attached || isRenderObjectOffstage(ro, stopAt: stopAt))) {
          continue;
        }
        if (seenTabIds.add(entry.componentId)) {
          activeTabs.add(entry);
        }
      }

      VibeMountedTabEntry? targetEntry;
      if (tabComponentId.isNotEmpty) {
        targetEntry = activeTabs
            .where((e) => e.componentId == tabComponentId)
            .firstOrNull;
        if (targetEntry == null) {
          final available = activeTabs.map((e) => e.componentId).toList();
          return VibeToolResult.error(
            callId: callId,
            name: toolName,
            message: available.isEmpty
                ? 'Aucun composant SuperTab monté à l’écran (demandé: "$tabComponentId").'
                : 'SuperTab "$tabComponentId" introuvable ou non monté (disponibles: ${available.join(', ')}).',
          );
        }
      } else if (activeTabs.length == 1) {
        targetEntry = activeTabs.single;
      } else {
        final available = activeTabs.map((e) => e.componentId).toList();
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message: available.isEmpty
              ? 'Aucun composant SuperTab monté à l’écran.'
              : 'Plusieurs SuperTab sont montés (${available.join(', ')}) : précise tabComponentId.',
        );
      }

      if (activeScope != null) {
        final allowedScopeIds = <String>{};
        final pending = <String>[...activeScope.canonicalComponentIds];
        while (pending.isNotEmpty) {
          final id = pending.removeLast();
          if (!allowedScopeIds.add(id)) continue;
          for (final childId in VibeScopeHelpers.childrenOfComponent(
            appearance.components[id],
          )) {
            if (!allowedScopeIds.contains(childId)) {
              pending.add(childId);
            }
          }
        }
        if (!allowedScopeIds.contains(targetEntry.componentId)) {
          return VibeToolResult.error(
            callId: callId,
            name: toolName,
            message:
                'Le SuperTab "${targetEntry.componentId}" est en dehors du scope restreint actif "${activeScope.displayLabel}" : le balayage des onglets hors scope est désactivé.',
          );
        }
      }

      final snap = targetEntry.readSnapshot();
      if (snap == null || snap.tabCount == 0) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'Le SuperTab "${targetEntry.componentId}" ne contient aucun onglet actif.',
        );
      }

      int? resolvedTabIndex;
      if (rawTabIndex is num) {
        final idx = rawTabIndex.toInt();
        if (idx < 0 || idx >= snap.tabCount) {
          final summary = snap.tabs
              .map((t) => '[${t.index}] ${t.tabId} ("${t.label}")')
              .join(', ');
          return VibeToolResult.error(
            callId: callId,
            name: toolName,
            message:
                'tabIndex $idx hors bornes pour "${targetEntry.componentId}" (${snap.tabCount} onglet(s) : $summary).',
          );
        }
        resolvedTabIndex = idx;
      } else if (tabIdArg.isNotEmpty) {
        final exactMatch = snap.tabs
            .where((t) => t.tabId == tabIdArg || t.label == tabIdArg)
            .firstOrNull;
        final ciMatch =
            exactMatch ??
            snap.tabs
                .where(
                  (t) =>
                      t.tabId.toLowerCase() == tabIdArg.toLowerCase() ||
                      t.label.toLowerCase() == tabIdArg.toLowerCase(),
                )
                .firstOrNull;
        if (ciMatch == null) {
          final summary = snap.tabs
              .map((t) => '[${t.index}] ${t.tabId} ("${t.label}")')
              .join(', ');
          return VibeToolResult.error(
            callId: callId,
            name: toolName,
            message:
                'Onglet "$tabIdArg" introuvable dans "${targetEntry.componentId}" (disponibles : $summary).',
          );
        }
        resolvedTabIndex = ciMatch.index;
      } else {
        resolvedTabIndex = 0;
      }

      final previousIndex = snap.activeIndex;
      previewTracker?.snapshotTabIfNeeded(targetEntry, previousIndex);
      targetEntry.selectTab(resolvedTabIndex);
      final targetTab = snap.tabs[resolvedTabIndex];
      actions['tabSelection'] = <String, Object?>{
        'tabComponentId': targetEntry.componentId,
        'previousIndex': previousIndex,
        'activeIndex': resolvedTabIndex,
        'tabId': targetTab.tabId,
        'label': targetTab.label,
        'contentZone': targetTab.contentZone,
        'tabCount': snap.tabCount,
      };
      didSomething = true;
    }

    if (!didSomething) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Fournis pageId/routePath, (repositoryId + arrayTemplate) et/ou (tabComponentId + tabIndex/tabId) à prévisualiser.',
      );
    }

    if (waitForVisualFrame != null) {
      await waitForVisualFrame!();
    } else {
      SchedulerBinding.instance.ensureVisualUpdate();
      final isWidgetTest = WidgetsBinding.instance.runtimeType
          .toString()
          .contains('TestWidgetsFlutterBinding');
      if (!isWidgetTest && SchedulerBinding.instance.hasScheduledFrame) {
        try {
          await SchedulerBinding.instance.endOfFrame.timeout(
            const Duration(milliseconds: 200),
          );
        } on TimeoutException {
          // Poursuit sans blocage si aucune pompe de frame n'est active.
        }
      }
    }

    return VibeToolResult(
      callId: callId,
      name: toolName,
      data: <String, Object?>{
        ...actions,
        'mountedSlots': slotIndex.mountedSlotSummaries(limit: 30),
      },
    );
  }

  /// 7. Sélectionne (ou désélectionne) à distance un élément sur le canevas du mode édition.
  Future<VibeToolResult> selectEditorElement(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) async {
    final clear = args['clear'] == true;
    final setChatScope = args['setChatScope'] == true;
    if (clear) {
      LayoutSelection.clearAll();
      if (setChatScope) {
        onSelectScope?.call(null);
      }
      return VibeToolResult(
        callId: callId,
        name: toolName,
        data: <String, Object?>{
          'cleared': true,
          'selectionPath': LayoutSelection.path.value,
          if (setChatScope) 'scopeCleared': true,
        },
      );
    }

    var componentId =
        args['componentId'] is String &&
            (args['componentId'] as String).trim().isNotEmpty
        ? (args['componentId'] as String).trim()
        : (args['id'] is String && (args['id'] as String).trim().isNotEmpty
              ? (args['id'] as String).trim()
              : '');
    final zoneId =
        args['zoneId'] is String && (args['zoneId'] as String).trim().isNotEmpty
        ? (args['zoneId'] as String).trim()
        : null;

    if (componentId.isEmpty) {
      final available = slotIndex.mountedSlotSummaries(limit: 25);
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'Fournis "componentId" à sélectionner'
            '${available.isEmpty ? '.' : ' (slots montés : ${available.join(', ')}).'}',
      );
    }

    var entries = slotIndex.entriesFor(componentId, zoneId: zoneId);
    if (entries.isEmpty) {
      final canonical = VibeChatScope.canonicalizeId(componentId);
      if (canonical != componentId) {
        entries = slotIndex.entriesFor(canonical, zoneId: zoneId);
        if (entries.isNotEmpty) {
          componentId = canonical;
        }
      }
    }
    if (entries.isEmpty) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'Élément "$componentId"${zoneId == null ? '' : ' (zone "$zoneId")'} non monté à l’écran.',
      );
    }

    final rawOcc = args['occurrenceIndex'];
    final occurrenceIndex = rawOcc is num ? rawOcc.toInt() : 0;
    if (occurrenceIndex < 0 || occurrenceIndex >= entries.length) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'occurrenceIndex $occurrenceIndex hors limites pour "$componentId" '
            '(${entries.length} occurrence(s) montée(s)).',
      );
    }

    final entry = entries[occurrenceIndex];
    final enableEditMode = args['enableEditMode'] is bool
        ? args['enableEditMode'] as bool
        : true;
    final scrollIntoView = readVisibleOnly?.call() == true
        ? false
        : (args['scrollIntoView'] is bool
              ? args['scrollIntoView'] as bool
              : true);
    final pulseHighlight = args['pulseHighlight'] is bool
        ? args['pulseHighlight'] as bool
        : true;

    final initialCtx = entry.slotContext() ?? resolvePrimaryContext();
    var editModeActivated = false;
    if (enableEditMode && initialCtx != null && initialCtx.mounted) {
      final editController = StyleEditScope.controllerOf(initialCtx);
      if (editController != null && !editController.value) {
        editController.value = true;
        editModeActivated = true;
      }
    }

    if (scrollIntoView) {
      final scrollCtx = entry.slotContext();
      if (scrollCtx != null &&
          scrollCtx.mounted &&
          Scrollable.maybeOf(scrollCtx) != null) {
        try {
          await Scrollable.ensureVisible(
            scrollCtx,
            alignment: 0.5,
            duration: Duration.zero,
          );
        } catch (_) {}
      }
    }

    final slotCtx = entry.slotContext();
    if (slotCtx == null || !slotCtx.mounted) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Contexte du slot "$componentId" indisponible.',
      );
    }

    final EditorSlotState? slotState = entry.token is EditorSlotState
        ? entry.token as EditorSlotState
        : EditorSlotState.resolveFromContext(slotCtx, preferredId: componentId);
    if (slotState == null || !slotState.mounted) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Impossible de résoudre EditorSlotState pour "$componentId".',
      );
    }

    slotState.selectInEditor(targetContext: slotCtx);
    EditorSlotState.setHighlightedTarget(slotState);

    if (pulseHighlight) {
      final targetKey =
          (slotState.widget.zoneId != null &&
              slotState.widget.zoneId!.isNotEmpty)
          ? '${slotState.effectiveComponentId}::${slotState.widget.zoneId}'
          : slotState.effectiveComponentId;
      VibeWorkHighlightController.instance.pulseTargets(
        modifiedIds: <String>[targetKey],
      );
    }

    if (setChatScope) {
      onSelectScope?.call(slotState.aiScope);
    }

    return VibeToolResult(
      callId: callId,
      name: toolName,
      data: <String, Object?>{
        'selected': true,
        'componentId': slotState.effectiveComponentId,
        'zoneId': ?slotState.widget.zoneId,
        'label': slotState.titleLabel,
        'occurrenceIndex': occurrenceIndex,
        'editModeActivated': editModeActivated,
        'selectionPath': LayoutSelection.path.value,
        if (setChatScope) 'scopeUpdated': slotState.aiScope.displayLabel,
      },
    );
  }

  /// 8. Valide des identifiants d'icônes dans [MaterialIconCatalog] et/ou liste les icônes disponibles.
  VibeToolResult validateOrListIcons(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) {
    final requestedIcons = <String>[
      if (args['icons'] case final List rawList)
        for (final item in rawList)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      if (args['icon'] case final String single when single.trim().isNotEmpty)
        single.trim(),
    ];

    final query = args['query'] is String
        ? (args['query'] as String).trim()
        : '';
    final rawCategory = args['category'] is String
        ? (args['category'] as String).trim()
        : '';

    MaterialIconCategory? parsedCategory;
    if (rawCategory.isNotEmpty) {
      parsedCategory = MaterialIconCategory.values
          .where(
            (c) =>
                c.name.toLowerCase() == rawCategory.toLowerCase() ||
                c.label.toLowerCase() == rawCategory.toLowerCase(),
          )
          .firstOrNull;
      if (parsedCategory == null) {
        final validCategories = [
          for (final c in MaterialIconCategory.values) c.name,
        ];
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'Catégorie d’icônes inconnue "$rawCategory" '
              '(catégories valides : ${validCategories.join(', ')}).',
        );
      }
    }

    final validations = <Map<String, Object?>>[];
    final invalidIcons = <String>[];
    var validCount = 0;

    for (final raw in requestedIcons) {
      final canonical = MaterialIconCatalog.resolveCanonicalId(raw);
      if (canonical != null) {
        validCount++;
        final entry = MaterialIconCatalog.byId[canonical]!;
        validations.add(<String, Object?>{
          'requested': raw,
          'valid': true,
          'canonicalId': canonical,
          'label': entry.label,
          'category': entry.category.name,
        });
      } else {
        invalidIcons.add(raw);
        final suggestions = _suggestIconsFor(raw, category: parsedCategory);
        validations.add(<String, Object?>{
          'requested': raw,
          'valid': false,
          'canonicalId': null,
          'suggestions': suggestions,
        });
      }
    }

    final includeAllExplicit = args['includeAll'] is bool
        ? args['includeAll'] as bool
        : null;
    final shouldList =
        includeAllExplicit == true ||
        query.isNotEmpty ||
        parsedCategory != null ||
        (requestedIcons.isEmpty && includeAllExplicit != false);

    final rawOffset = args['offset'];
    final offset = rawOffset is num ? math.max(0, rawOffset.toInt()) : 0;
    final defaultLimit = (query.isEmpty && parsedCategory == null) ? 500 : 120;
    final rawLimit = args['limit'];
    final limit = rawLimit is num
        ? rawLimit.toInt().clamp(1, 500)
        : defaultLimit;

    List<MaterialIconEntry> matchedEntries = const <MaterialIconEntry>[];
    List<MaterialIconEntry> pagedEntries = const <MaterialIconEntry>[];
    if (shouldList) {
      matchedEntries = MaterialIconCatalog.search(
        query: query,
        category: parsedCategory,
      );
      if (offset < matchedEntries.length) {
        final end = math.min(matchedEntries.length, offset + limit);
        pagedEntries = matchedEntries.sublist(offset, end);
      }
    }

    final includeDetailedItems =
        query.isNotEmpty ||
        parsedCategory != null ||
        pagedEntries.length <= 120;

    return VibeToolResult(
      callId: callId,
      name: toolName,
      data: <String, Object?>{
        'ok': true,
        'totalCatalogCount': MaterialIconCatalog.entries.length,
        'availableCategories': <Map<String, Object?>>[
          for (final c in MaterialIconCategory.values)
            <String, Object?>{'id': c.name, 'label': c.label},
        ],
        if (validations.isNotEmpty) ...<String, Object?>{
          'allValid': invalidIcons.isEmpty,
          'validCount': validCount,
          'invalidCount': invalidIcons.length,
          if (invalidIcons.isNotEmpty) 'invalidIcons': invalidIcons,
          'validations': validations,
        },
        if (shouldList) ...<String, Object?>{
          if (query.isNotEmpty) 'query': query,
          if (parsedCategory != null) 'category': parsedCategory.name,
          'matchCount': matchedEntries.length,
          'returnedCount': pagedEntries.length,
          'offset': offset,
          'hasMore': offset + pagedEntries.length < matchedEntries.length,
          'iconIds': <String>[for (final entry in pagedEntries) entry.id],
          if (includeDetailedItems)
            'icons': <Map<String, Object?>>[
              for (final entry in pagedEntries)
                <String, Object?>{
                  'id': entry.id,
                  'label': entry.label,
                  'category': entry.category.name,
                },
            ],
        },
      },
    );
  }

  static List<String> _suggestIconsFor(
    String raw, {
    MaterialIconCategory? category,
    int maxSuggestions = 5,
  }) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('Icons.') || cleaned.startsWith('icons.')) {
      cleaned = cleaned.substring(6);
    }
    cleaned = cleaned
        .replaceAllMapped(
          RegExp(r'(?<=[a-z0-9])([A-Z])'),
          (m) => '_${m.group(1)!.toLowerCase()}',
        )
        .replaceAll('-', '_');
    final normalized = MaterialIconCatalog.normalizeQuery(cleaned);
    final tokens = normalized
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toList();

    final scored = <String, int>{};
    void addMatches(List<MaterialIconEntry> items, int weight) {
      for (final entry in items) {
        scored[entry.id] = (scored[entry.id] ?? 0) + weight;
      }
    }

    for (final token in tokens) {
      addMatches(
        MaterialIconCatalog.search(query: token, category: category),
        3,
      );
      for (final entry in MaterialIconCatalog.entries) {
        if (category != null && entry.category != category) continue;
        if (entry.id.contains(token) || token.contains(entry.id)) {
          scored[entry.id] = (scored[entry.id] ?? 0) + 2;
        }
      }
    }
    if (scored.isEmpty && category != null) {
      return [
        for (final entry in MaterialIconCatalog.search(
          category: category,
        ).take(maxSuggestions))
          entry.id,
      ];
    }
    final ordered = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final item in ordered.take(maxSuggestions)) item.key];
  }
}
