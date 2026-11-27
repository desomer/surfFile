/// Atelier de l'étape 4 : Objets métiers structurés affichés par repository
/// (`ListView` dépliable avec `SuperTreeView` embarqué), inspecteur hiérarchique
/// et éditeur [CodeEditor] YAML ([BusinessObjectsEditorView]).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:highlight/languages/yaml.dart' as yaml_lang;
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../../models/business_object_spec.dart';
import '../../models/feature_object_sync_baseline.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_initiative.dart';
import '../../services/business_object_operations.dart';
import '../../services/cross_feature_object_analyzer.dart';
import '../../services/exporters/spec_super_designer_exporter.dart';
import '../../services/spec_forge_controller.dart';
import '../../services/spec_schema_dsl_bridge.dart';
import '../spec_split_handle.dart';
import 'attribute_constraints_editor.dart';
import 'business_objects/business_object_inspector_panes.dart';
import 'business_objects/business_object_tree_models.dart';
import 'business_objects/business_object_tree_tooltip_card.dart';
import 'import_sync_business_objects_dialog.dart';
import 'json_schema_viewer_dialog.dart';
import 'markdown_viewer_dialog.dart';

/// Vue structurée à 3 onglets (« Objets », « Repositories » avec [SpecJsonSchemaViewerView],
/// et « DSL » via [CodeEditor]).
class BusinessObjectsEditorView extends StatefulWidget {
  /// Crée la vue connectée au [controller].
  const BusinessObjectsEditorView({
    required this.controller,
    this.schemaViewerSurfaceBuilder,
    this.schemaBrowserLauncher,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Constructeur optionnel pour remplacer la WebView dans l'onglet « JSON Schema & Seed » (tests).
  final SpecMarkdownViewerSurfaceBuilder? schemaViewerSurfaceBuilder;

  /// Lanceur navigateur optionnel pour l'ouverture du `.html` généré (tests).
  final SpecMarkdownBrowserLauncher? schemaBrowserLauncher;

  @override
  State<BusinessObjectsEditorView> createState() =>
      _BusinessObjectsEditorViewState();
}

class _BusinessObjectsEditorViewState extends State<BusinessObjectsEditorView> {
  final GlobalKey _splitRowKey = GlobalKey();
  late final JsonRepositoryStore _treeRepoStore;
  final Map<String, String> _repoIdByObjectId = <String, String>{};
  final Set<String> _registeredRepoIds = <String>{};
  int _nextRepoSeq = 0;
  final ValueNotifier<String> _yamlErrorNotifier = ValueNotifier<String>('');
  late final CodeEditorConfig _codeEditorConfig;
  late final TextEditingController _filterCtrl;

  String _yamlText = '';
  String? _lastSyncedProjectId;
  String? _lastSyncedFeatureId;
  String? _lastFocusedObjectId;
  List<String> _lastFocusedAttrPath = const <String>[];
  String _lastSyncedFilter = '';
  List<BusinessObjectSpec>? _lastSyncedObjects;
  List<RepoTreeEntry> _repoEntries = const <RepoTreeEntry>[];
  final Set<String> _expandedObjectIds = <String>{};
  String? _selectedObjectId;
  String? _selectedNodePath;
  bool _showFilterBar = false;
  bool _yamlDirty = false;
  String? _treeBuildError;
  double _treePaneFraction = 5 / 11;
  double _treeDragOffset = SpecSplitHandle.width / 2;

  String _repoIdForObject(String objectId) =>
      _repoIdByObjectId.putIfAbsent(objectId, () => 'repo_${_nextRepoSeq++}');

  @override
  void initState() {
    super.initState();
    _filterCtrl = TextEditingController(
      text: widget.controller.businessObjectFilter,
    );
    _showFilterBar = widget.controller.businessObjectFilter.trim().isNotEmpty;
    _codeEditorConfig = CodeEditorConfig(
      mode: yaml_lang.yaml,
      type: 'yaml',
      getText: () => _yamlText,
      onChange: (String value, CodeEditorConfig _) {
        _yamlText = value;
        _yamlDirty = true;
        var err = '';
        try {
          Yaml2JsonSchemasParser().parse(value);
        } on FormatException catch (e) {
          err = e.message;
        }
        _yamlErrorNotifier.value = err;
      },
      notifError: _yamlErrorNotifier,
      useLargeTextViewer: false,
    );
    _treeRepoStore = JsonRepositoryStore(
      Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}ssf_tree',
      ),
    );
    _syncFromProject(widget.controller.project, forceYaml: true);
  }

  @override
  void didUpdateWidget(BusinessObjectsEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromProject(widget.controller.project);
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    _yamlErrorNotifier.dispose();
    _treeRepoStore.dispose();
    super.dispose();
  }

  void _clearTreeSelections({String? exceptObjectId}) {
    for (final entry in _repoEntries) {
      if (entry.object.id == exceptObjectId) continue;
      if (_registeredRepoIds.contains(entry.repoId)) {
        _treeRepoStore.bindingOf(entry.repoId).array('nodes').clear();
      }
    }
  }

  void _selectTreeNodeInStore(String repoId, String? nodePath) {
    if (!_registeredRepoIds.contains(repoId)) return;
    final binding = _treeRepoStore.bindingOf(repoId).array('nodes');
    if (nodePath == null || nodePath.isEmpty) {
      binding.clear();
      return;
    }
    final match = RegExp(r'^nodes\[(\d+)\]').firstMatch(nodePath);
    final rootIndex = match != null ? int.parse(match.group(1)!) : 0;
    binding.select(const [], rootIndex, nodePath: nodePath);
  }

  void _syncFromProject(SpecForgeProject? project, {bool forceYaml = false}) {
    if (project == null) return;
    final projectChanged =
        _lastSyncedProjectId != project.id ||
        _lastSyncedFeatureId != project.activeFeatureId;
    final focusedId = widget.controller.focusedObjectId;
    final focusedAttrPath = widget.controller.focusedAttributePath;
    final rawFilter = widget.controller.businessObjectFilter;
    final filterChanged = rawFilter != _lastSyncedFilter;
    final focusChanged =
        (focusedId != null &&
            focusedId.isNotEmpty &&
            focusedId != _lastFocusedObjectId) ||
        !listEquals(focusedAttrPath, _lastFocusedAttrPath);

    if (!forceYaml &&
        !projectChanged &&
        !focusChanged &&
        !filterChanged &&
        identical(_lastSyncedObjects, project.businessObjects)) {
      return;
    }

    if (projectChanged) {
      _yamlDirty = false;
    }
    _lastSyncedProjectId = project.id;
    _lastSyncedFeatureId = project.activeFeatureId;
    _lastSyncedObjects = project.businessObjects;
    _lastSyncedFilter = rawFilter;
    if (_filterCtrl.text != rawFilter) {
      _filterCtrl.text = rawFilter;
      _filterCtrl.selection = TextSelection.collapsed(
        offset: rawFilter.length,
      );
    }
    if (rawFilter.trim().isNotEmpty) {
      _showFilterBar = true;
    }
    if (focusedId != null && focusedId.isNotEmpty) {
      _lastFocusedObjectId = focusedId;
    }
    _lastFocusedAttrPath = List<String>.unmodifiable(focusedAttrPath);

    List<Map<String, Object?>> rootNodes = const <Map<String, Object?>>[];
    try {
      rootNodes = SpecSchemaDslBridge.buildTreeNodes(project);
      _treeBuildError = null;
    } on FormatException catch (e) {
      _treeBuildError = e.message;
      rootNodes = const <Map<String, Object?>>[];
    }

    final rootByObjectId = <String, Map<String, Object?>>{};
    for (final root in rootNodes) {
      final objId = (root['objectId'] as String?) ?? '';
      if (objId.isNotEmpty) {
        rootByObjectId[objId] = root;
      }
    }

    final lowerFilter = rawFilter.trim().toLowerCase();
    final entries = <RepoTreeEntry>[];
    for (var i = 0; i < project.businessObjects.length; i++) {
      final obj = project.businessObjects[i];
      final preview = SpecSuperDesignerExporter.buildRepositoryPreview(
        project,
        obj,
        modelPreferencesOverride: widget.controller.modelPreferences,
      );

      final rootNode =
          rootByObjectId[obj.id] ?? (i < rootNodes.length ? rootNodes[i] : null);
      final rawChildren = rootNode?['children'];
      final allChildren = rawChildren is List
          ? [
              for (final child in rawChildren)
                if (child is Map<String, Object?>) child,
            ]
          : const <Map<String, Object?>>[];

      final objMatchesFilter =
          lowerFilter.isEmpty ||
          obj.name.toLowerCase().contains(lowerFilter) ||
          obj.technicalName.toLowerCase().contains(lowerFilter) ||
          preview.alias.toLowerCase().contains(lowerFilter) ||
          obj.description.toLowerCase().contains(lowerFilter);

      final filteredChildren = lowerFilter.isEmpty
          ? allChildren
          : BusinessObjectOperations.filterTreeNodes(allChildren, lowerFilter);

      if (lowerFilter.isNotEmpty &&
          !objMatchesFilter &&
          filteredChildren.isEmpty) {
        continue;
      }

      final children = (lowerFilter.isNotEmpty && filteredChildren.isNotEmpty)
          ? filteredChildren
          : allChildren;

      final targets = <String, BusinessObjectTreeSelectionTarget>{};
      void indexNode(Map<String, Object?> node, String nodePath) {
        final rawAttrPath = node['attributePath'];
        final attrPath = rawAttrPath is List
            ? [for (final s in rawAttrPath) '$s']
            : const <String>[];
        targets[nodePath] = BusinessObjectTreeSelectionTarget(
          nodePath: nodePath,
          objectId: obj.id,
          relationId: (node['relationId'] as String?) ?? '',
          attributePath: attrPath,
          isRootObject: false,
          isRelation: ((node['relationId'] as String?) ?? '').isNotEmpty,
          isArray: node['isArray'] == true,
          isRequired: node['isRequired'] == true,
          attrType: (node['attrType'] as String?) ?? '',
          totalAttributes: (node['totalAttributes'] as int?) ?? 0,
          estimatedMaxRows: node['estimatedMaxRows'] as int?,
          typeIcon: (node['typeIcon'] as String?) ?? 'value',
          displayType: (node['displayType'] as String?) ?? '',
        );
        final subChildren = node['children'];
        if (subChildren is List) {
          for (var j = 0; j < subChildren.length; j++) {
            final sub = subChildren[j];
            if (sub is Map<String, Object?>) {
              indexNode(sub, '$nodePath.children[$j]');
            }
          }
        }
      }

      for (var c = 0; c < children.length; c++) {
        indexNode(children[c], 'nodes[$c]');
      }

      var isSchemaValid = true;
      var schemaIssueCount = 0;
      try {
        final validation = JsonSchemaValidator.validate(
          preview.seed,
          preview.schema,
        );
        isSchemaValid = validation.isValid;
        schemaIssueCount = validation.issues.length;
      } on FormatException {
        isSchemaValid = false;
        schemaIssueCount = 1;
      }

      final repoId = _repoIdForObject(obj.id);
      if (!_registeredRepoIds.contains(repoId)) {
        _treeRepoStore.registerRepository(
          RepositoryImpl(
            id: repoId,
            json: <String, Object?>{'nodes': children},
          ),
        );
        _registeredRepoIds.add(repoId);
      } else {
        unawaited(_treeRepoStore.replaceArray(repoId, 'nodes', children));
      }

      entries.add(
        RepoTreeEntry(
          object: obj,
          repoId: repoId,
          repoAlias: preview.alias,
          isSchemaValid: isSchemaValid,
          schemaIssueCount: schemaIssueCount,
          childNodes: children,
          targetsByNodePath: targets,
        ),
      );
    }

    _repoEntries = entries;

    final validObjectIds = {for (final e in entries) e.object.id};
    if (projectChanged) {
      _expandedObjectIds.clear();
      _selectedObjectId = null;
      _selectedNodePath = null;
    } else {
      _expandedObjectIds.removeWhere((id) => !validObjectIds.contains(id));
    }

    if (_selectedObjectId == null ||
        !validObjectIds.contains(_selectedObjectId)) {
      _selectedObjectId =
          entries.isNotEmpty ? entries.first.object.id : null;
      _selectedNodePath = null;
    }

    final singleExpanded =
        widget.controller.modelPreferences.singleExpandedBusinessObject;
    if (focusedId != null &&
        focusedId.isNotEmpty &&
        validObjectIds.contains(focusedId)) {
      _selectedObjectId = focusedId;
      if (singleExpanded) {
        _expandedObjectIds.clear();
      }
      _expandedObjectIds.add(focusedId);

      final focusedEntry = entries
          .where((e) => e.object.id == focusedId)
          .firstOrNull;
      if (focusedAttrPath.isNotEmpty && focusedEntry != null) {
        final matched = focusedEntry.targetsByNodePath.entries
            .where((e) => listEquals(e.value.attributePath, focusedAttrPath))
            .firstOrNull;
        _selectedNodePath = matched?.key;
        _clearTreeSelections(exceptObjectId: focusedId);
        if (matched != null) {
          _selectTreeNodeInStore(focusedEntry.repoId, matched.key);
        }
      } else {
        _selectedNodePath = null;
        _clearTreeSelections();
      }
    } else if (_expandedObjectIds.isEmpty && entries.isNotEmpty) {
      _expandedObjectIds.add(
        _selectedObjectId ?? entries.first.object.id,
      );
    }
    if (lowerFilter.isNotEmpty && entries.isNotEmpty) {
      if (singleExpanded) {
        if (_expandedObjectIds.isEmpty) {
          _expandedObjectIds.add(entries.first.object.id);
        }
      } else {
        for (final entry in entries) {
          if (entry.childNodes.isNotEmpty) {
            _expandedObjectIds.add(entry.object.id);
          }
        }
      }
    }
    if (singleExpanded && _expandedObjectIds.length > 1) {
      final keepId = (_selectedObjectId != null &&
              _expandedObjectIds.contains(_selectedObjectId))
          ? _selectedObjectId!
          : _expandedObjectIds.first;
      _expandedObjectIds
        ..clear()
        ..add(keepId);
    }

    if (_selectedObjectId != null && _selectedNodePath != null) {
      final selectedEntry = entries
          .where((e) => e.object.id == _selectedObjectId)
          .firstOrNull;
      if (selectedEntry == null ||
          !selectedEntry.targetsByNodePath.containsKey(_selectedNodePath)) {
        _selectedNodePath = null;
      }
    }

    if (!_yamlDirty || forceYaml) {
      _yamlText = SpecSchemaDslBridge.toYamlLight(project);
      _yamlErrorNotifier.value = '';
      _yamlDirty = false;
      _codeEditorConfig.repaintCode();
    }
  }

  Future<void> _applyYamlSource(SpecForgeProject project) async {
    final source = _yamlText;
    try {
      final parsedObjects = BusinessObjectOperations.applyYamlSource(
        source,
        existing: project.businessObjects,
      );
      _yamlErrorNotifier.value = '';
      setState(() {
        _yamlDirty = false;
      });
      await widget.controller.updateProject(
        project.copyWith(businessObjects: parsedObjects),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schéma YAML appliqué aux objets métiers.'),
          ),
        );
      }
    } on FormatException catch (e) {
      _yamlErrorNotifier.value = e.message;
    } catch (e) {
      _yamlErrorNotifier.value = e.toString();
    }
  }

  Future<void> _openImportSyncDialog(
    BuildContext context, {
    ObjectSyncSourceKind? initialSourceKind,
    String? initialSourceFeatureId,
    String? initialSourceDomainId,
    String? preselectedObjectIdOrTechName,
  }) async {
    final result = await ImportSyncBusinessObjectsDialog.show(
      context,
      controller: widget.controller,
      initialSourceKind: initialSourceKind,
      initialSourceFeatureId: initialSourceFeatureId,
      initialSourceDomainId: initialSourceDomainId,
      preselectedObjectIdOrTechName: preselectedObjectIdOrTechName,
    );
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(formatFeatureObjectSyncSummary(result))),
    );
  }

  Future<void> _openCrossFeatureImpactDialog(
    BuildContext context,
    SpecForgeProject project,
    List<ObjectCrossFeatureReport> reports, {
    String? focusedObjectName,
  }) async {
    final syncTarget = await CrossFeatureImpactDetailsDialog.show(
      context,
      project: project,
      reports: reports,
      focusedObjectName: focusedObjectName,
    );
    if (syncTarget == null || !context.mounted) return;
    await _openImportSyncDialog(
      context,
      initialSourceKind: ObjectSyncSourceKind.feature,
      initialSourceFeatureId: syncTarget.featureId,
      preselectedObjectIdOrTechName: syncTarget.objectIdOrTechName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final project = widget.controller.project;
        if (project == null) return const SizedBox.shrink();
        _syncFromProject(project);

        final singleExpanded =
            widget.controller.modelPreferences.singleExpandedBusinessObject;
        if (singleExpanded && _expandedObjectIds.length > 1) {
          final keepId = (_selectedObjectId != null &&
                  _expandedObjectIds.contains(_selectedObjectId))
              ? _selectedObjectId!
              : _expandedObjectIds.first;
          _expandedObjectIds
            ..clear()
            ..add(keepId);
        }

        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final objects = project.businessObjects;
        final crossReport = CrossFeatureObjectAnalyzer.analyzeFeature(project);
        final hasSiblingObjects = project.allFeatures.any(
          (f) =>
              f.id != project.activeFeatureId &&
              f.effectiveStatus != SpecPortfolioStatus.archived &&
              f.businessObjects.isNotEmpty,
        );
        final hasDesignContracts = widget.controller.domainCatalog.domains.any(
          (d) => d.contracts?.groups.any((g) => g.children.isNotEmpty) ?? false,
        );
        final canImportOrSync = hasSiblingObjects || hasDesignContracts;

        return JsonRepositoryScope(
          store: _treeRepoStore,
          child: DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Objets métiers (${objects.length})',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Règles : max 200 attributs/objet · max 200 lignes/tableau imbriqué · objet dédié au-delà',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Tooltip(
                            message: canImportOrSync
                                ? 'Importer ou synchroniser en 3-voies depuis une autre Feature ou un domaine Design'
                                : 'Aucun objet dans une autre Feature ni contrat Design disponible',
                            child: OutlinedButton.icon(
                              key: const ValueKey(
                                'spec-objects-import-sync-btn',
                              ),
                              onPressed: canImportOrSync
                                  ? () => _openImportSyncDialog(context)
                                  : null,
                              icon: const Icon(
                                Icons.sync_alt_rounded,
                                size: 16,
                              ),
                              label: const Text('Importer / Synchroniser…'),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            key: const ValueKey('spec-objects-add-root'),
                            onPressed: () =>
                                _editObjectDialog(context, project),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Nouvel objet'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(
                      key: ValueKey('spec-objects-tree-tab'),
                      text: 'Objets',
                    ),
                    Tab(
                      key: ValueKey('spec-objects-schema-tab'),
                      text: 'Repositories',
                    ),
                    Tab(
                      key: ValueKey('spec-objects-dsl-tab'),
                      text: 'DSL',
                    ),
                  ],
                ),
                if (crossReport.warningObjectCount > 0)
                  Container(
                    key: const ValueKey(
                      'spec-objects-cross-feature-warning-banner',
                    ),
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(
                        alpha: isDark ? 0.18 : 0.13,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.amber.withValues(
                          alpha: isDark ? 0.50 : 0.40,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: isDark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${crossReport.warningObjectCount} objet(s) présentent une divergence cassante '
                            'ou un impact RG/UX/QA vis-à-vis d’une feature Validée',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.amber.shade100
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          key: const ValueKey(
                            'spec-objects-cross-feature-warning-details-btn',
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _openCrossFeatureImpactDialog(
                            context,
                            project,
                            crossReport.warnings,
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 15),
                          label: const Text('Voir les impacts'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildTreeAndInspectorTab(
                        context,
                        project,
                        colors,
                        theme,
                        crossReport: crossReport,
                        canImportOrSync: canImportOrSync,
                      ),
                      _buildJsonSchemaAndSeedTab(project),
                      _buildYamlSourceTab(context, project, colors, theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTreeAndInspectorTab(
    BuildContext context,
    SpecForgeProject project,
    ColorScheme colors,
    ThemeData theme, {
    required FeatureCrossObjectReport crossReport,
    required bool canImportOrSync,
  }) {
    if (project.businessObjects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Aucun objet métier pour l’instant.\nUtilisez le Domain Modeler à gauche ou cliquez sur « Nouvel objet ».',
                textAlign: TextAlign.center,
              ),
              if (canImportOrSync) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  key: const ValueKey('spec-objects-empty-import-sync-btn'),
                  onPressed: () => _openImportSyncDialog(context),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text(
                    'Importer depuis une autre Feature / Design…',
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_treeBuildError != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            key: const ValueKey('spec-objects-tree-error-card'),
            color: colors.errorContainer.withValues(alpha: 0.45),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: colors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Identifiant incompatible avec le DSL YAML',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _treeBuildError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const ValueKey('spec-objects-normalize-ids-btn'),
                    onPressed: () => _normalizeAllIdentifiers(project),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                    label: const Text(
                      'Corriger automatiquement les identifiants',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final selectedEntry = _selectedObjectId != null
        ? _repoEntries
              .where((e) => e.object.id == _selectedObjectId)
              .firstOrNull
        : null;
    final selectedObject =
        selectedEntry?.object ?? project.businessObjects.first;
    final target =
        selectedEntry != null && _selectedNodePath != null
            ? selectedEntry.targetsByNodePath[_selectedNodePath]
            : null;
    final selectedAttr = target == null || target.attributePath.isEmpty
        ? null
        : BusinessObjectOperations.findAttributeByPath(
            selectedObject.attributes,
            target.attributePath,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = SpecSplitHandle.width;
        const minTreeWidth = 220.0;
        const minInspectorWidth = 260.0;
        final totalWidth = constraints.maxWidth;
        final availableWidth = (totalWidth - dividerWidth).clamp(
          0.0,
          double.infinity,
        );
        final treeWidth = availableWidth <= minTreeWidth + minInspectorWidth
            ? availableWidth * _treePaneFraction
            : (availableWidth * _treePaneFraction).clamp(
                minTreeWidth,
                availableWidth - minInspectorWidth,
              );

        return Row(
          key: _splitRowKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('spec-objects-tree-pane'),
              width: treeWidth,
              child: Container(
                color: colors.surfaceContainerLowest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.controller.businessObjectFilter.trim().isEmpty
                                  ? 'Objets métiers (${_repoEntries.length})'
                                  : 'Objets métiers (${_repoEntries.length}/${project.businessObjects.length})',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('spec-objects-filter-toggle'),
                            tooltip: 'Filtrer objets et attributs',
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            color: (_showFilterBar ||
                                    widget.controller.businessObjectFilter
                                        .trim()
                                        .isNotEmpty)
                                ? colors.primary
                                : colors.onSurfaceVariant,
                            onPressed: () {
                              setState(() {
                                if (_showFilterBar &&
                                    widget.controller.businessObjectFilter
                                        .trim()
                                        .isNotEmpty) {
                                  _filterCtrl.clear();
                                  widget.controller.setBusinessObjectFilter('');
                                  _showFilterBar = false;
                                } else {
                                  _showFilterBar = !_showFilterBar;
                                }
                              });
                            },
                            icon: Icon(
                              (_showFilterBar ||
                                      widget.controller.businessObjectFilter
                                          .trim()
                                          .isNotEmpty)
                                  ? Icons.filter_alt_rounded
                                  : Icons.search_rounded,
                            ),
                          ),
                          if (!widget
                              .controller
                              .modelPreferences
                              .singleExpandedBusinessObject)
                            IconButton(
                              key: const ValueKey('spec-objects-expand-all'),
                              tooltip: 'Tout déplier',
                              visualDensity: VisualDensity.compact,
                              iconSize: 18,
                              onPressed: () {
                                setState(() {
                                  _expandedObjectIds.addAll(
                                    _repoEntries.map((e) => e.object.id),
                                  );
                                });
                              },
                              icon: const Icon(Icons.unfold_more_rounded),
                            ),
                          IconButton(
                            key: const ValueKey('spec-objects-collapse-all'),
                            tooltip: 'Tout replier',
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            onPressed: () {
                              setState(() {
                                _expandedObjectIds.clear();
                              });
                            },
                            icon: const Icon(Icons.unfold_less_rounded),
                          ),
                        ],
                      ),
                    ),
                    if (_showFilterBar ||
                        widget.controller.businessObjectFilter
                            .trim()
                            .isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                        child: TextField(
                          key: const ValueKey('spec-objects-filter-field'),
                          controller: _filterCtrl,
                          onChanged: (value) {
                            widget.controller.setBusinessObjectFilter(value);
                          },
                          style: theme.textTheme.bodySmall,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 16,
                            ),
                            suffixIcon: widget.controller.businessObjectFilter
                                    .isNotEmpty
                                ? IconButton(
                                    key: const ValueKey(
                                      'spec-objects-filter-clear',
                                    ),
                                    tooltip: 'Effacer le filtre',
                                    iconSize: 16,
                                    onPressed: () {
                                      _filterCtrl.clear();
                                      widget.controller
                                          .setBusinessObjectFilter('');
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  )
                                : null,
                            hintText: 'Filtrer objet, alias ou attribut…',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _repoEntries.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Aucun objet ou attribut ne correspond à « ${widget.controller.businessObjectFilter.trim()} ».',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: () {
                                        _filterCtrl.clear();
                                        widget.controller
                                            .setBusinessObjectFilter('');
                                      },
                                      icon: const Icon(
                                        Icons.clear_rounded,
                                        size: 15,
                                      ),
                                      label: const Text('Effacer le filtre'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : CustomScrollView(
                              key: const ValueKey('spec-objects-repo-listview'),
                              slivers: [
                                for (final entry in _repoEntries)
                                  ..._buildRepositorySlivers(
                                    context,
                                    project,
                                    entry,
                                    crossReport: crossReport,
                                    treeWidth: treeWidth,
                                    theme: theme,
                                    colors: colors,
                                  ),
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 6),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            SpecSplitHandle(
              key: const ValueKey('spec-objects-tree-split-handle'),
              onDoubleTap: () => setState(() => _treePaneFraction = 5 / 11),
              onHorizontalDragDown: (details) {
                final box =
                    _splitRowKey.currentContext?.findRenderObject()
                        as RenderBox?;
                if (box != null) {
                  final localX = box.globalToLocal(details.globalPosition).dx;
                  _treeDragOffset = (localX - treeWidth).clamp(
                    0.0,
                    SpecSplitHandle.width,
                  );
                } else {
                  _treeDragOffset = SpecSplitHandle.width / 2;
                }
              },
              onHorizontalDragUpdate: (details) {
                final box =
                    _splitRowKey.currentContext?.findRenderObject()
                        as RenderBox?;
                if (box == null || availableWidth <= 0) return;
                final localX = box.globalToLocal(details.globalPosition).dx;
                final nextWidth = localX - _treeDragOffset;
                final minFrac =
                    availableWidth > minTreeWidth + minInspectorWidth
                    ? (minTreeWidth / availableWidth)
                    : 0.20;
                final maxFrac =
                    availableWidth > minTreeWidth + minInspectorWidth
                    ? ((availableWidth - minInspectorWidth) / availableWidth)
                    : 0.78;
                setState(() {
                  _treePaneFraction = (nextWidth / availableWidth).clamp(
                    minFrac,
                    maxFrac,
                  );
                });
              },
            ),
            Expanded(
              key: const ValueKey('spec-objects-inspector-pane'),
              child: selectedAttr != null && target != null
                  ? AttributeInspectorPane(
                      project: project,
                      object: selectedObject,
                      attribute: selectedAttr,
                      attributePath: target.attributePath,
                      onBackToObject: () {
                        _clearTreeSelections();
                        _lastFocusedObjectId = selectedObject.id;
                        _lastFocusedAttrPath = const <String>[];
                        widget.controller.focusBusinessSelection(
                          objectId: selectedObject.id,
                        );
                        setState(() => _selectedNodePath = null);
                      },
                      onEditAttribute: () => _editAttributeDialog(
                        context,
                        project,
                        selectedObject,
                        parentAttrPath: target.attributePath.sublist(
                          0,
                          target.attributePath.length - 1,
                        ),
                        existing: selectedAttr,
                      ),
                      onAddChildAttribute:
                          selectedAttr.type == BusinessAttributeType.object
                          ? () => _editAttributeDialog(
                              context,
                              project,
                              selectedObject,
                              parentAttrPath: target.attributePath,
                            )
                          : null,
                      onDeleteAttribute: () => _deleteAttributeAtPath(
                        project,
                        selectedObject,
                        target.attributePath,
                      ),
                      onExtractToSeparateObject: selectedAttr.isArray
                          ? () => _extractArrayToSeparateObject(
                              project,
                              selectedObject,
                              target.attributePath,
                              selectedAttr,
                            )
                          : null,
                    )
                  : BusinessObjectInspectorPane(
                      project: project,
                      object: selectedObject,
                      controller: widget.controller,
                      onEditMeta: () => _editObjectDialog(
                        context,
                        project,
                        existing: selectedObject,
                      ),
                      onAddAttribute: () => _editAttributeDialog(
                        context,
                        project,
                        selectedObject,
                      ),
                      onEditAttribute: (attr) => _editAttributeDialog(
                        context,
                        project,
                        selectedObject,
                        existing: attr,
                      ),
                      onDeleteAttribute: (attr) => _deleteAttributeAtPath(
                        project,
                        selectedObject,
                        [attr.id],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget? _buildObjectSyncBadge({
    required BuildContext context,
    required SpecForgeProject project,
    required BusinessObjectSpec object,
    required ObjectCrossFeatureReport? objReport,
    required FeatureObjectSyncBaseline? syncBase,
    required ColorScheme colors,
    required bool isDark,
  }) {
    if (objReport != null && objReport.isSharedAcrossFeatures) {
      if (objReport.hasBreakingValidatedWarning) {
        return _ObjectSyncBadgePill(
          key: ValueKey('spec-object-shared-badge-${object.id}'),
          label: '⚠ Impact ${objReport.sharedFeaturesSummary}',
          backgroundColor: Colors.orange.withValues(
            alpha: isDark ? 0.24 : 0.15,
          ),
          foregroundColor: isDark
              ? Colors.amber.shade200
              : Colors.deepOrange.shade900,
          borderColor: Colors.orange.withValues(alpha: isDark ? 0.55 : 0.42),
          onTap: () => _openCrossFeatureImpactDialog(
            context,
            project,
            <ObjectCrossFeatureReport>[objReport],
            focusedObjectName: object.name,
          ),
        );
      }
      return _ObjectSyncBadgePill(
        key: ValueKey('spec-object-shared-badge-${object.id}'),
        icon: objReport.sharedWithValidatedFeature
            ? Icons.verified_rounded
            : Icons.share_outlined,
        label: 'Partagé · ${objReport.sharedFeaturesSummary}',
        backgroundColor: Colors.teal.withValues(alpha: isDark ? 0.22 : 0.12),
        foregroundColor: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
        borderColor: Colors.teal.withValues(alpha: isDark ? 0.48 : 0.34),
        onTap: () => _openCrossFeatureImpactDialog(
          context,
          project,
          <ObjectCrossFeatureReport>[objReport],
          focusedObjectName: object.name,
        ),
      );
    }

    if (syncBase != null &&
        syncBase.sourceKind == ObjectSyncSourceKind.designDomain) {
      return _ObjectSyncBadgePill(
        key: ValueKey('spec-object-design-sync-badge-${object.id}'),
        icon: Icons.architecture_rounded,
        label: 'Sync · ${syncBase.sourceDisplayLabel}',
        backgroundColor: Colors.indigo.withValues(alpha: isDark ? 0.22 : 0.11),
        foregroundColor: isDark
            ? Colors.indigo.shade200
            : Colors.indigo.shade800,
        borderColor: Colors.indigo.withValues(alpha: isDark ? 0.48 : 0.34),
        onTap: () => _openImportSyncDialog(
          context,
          initialSourceKind: ObjectSyncSourceKind.designDomain,
          initialSourceDomainId: syncBase.sourceDomainId,
          preselectedObjectIdOrTechName: syncBase.sourceEntryId.isNotEmpty
              ? syncBase.sourceEntryId
              : object.technicalName,
        ),
      );
    }

    return null;
  }

  List<Widget> _buildRepositorySlivers(
    BuildContext context,
    SpecForgeProject project,
    RepoTreeEntry entry, {
    required FeatureCrossObjectReport crossReport,
    required double treeWidth,
    required ThemeData theme,
    required ColorScheme colors,
  }) {
    final obj = entry.object;
    final isExpanded = _expandedObjectIds.contains(obj.id);
    final isObjectSelected = _selectedObjectId == obj.id;
    final isHeaderHighlighted = isObjectSelected && _selectedNodePath == null;
    final totalAttrs = obj.totalAttributeCount;
    final overAttrLimit =
        totalAttrs > BusinessObjectSpec.maxAttributesPerObject;
    final headerColumnWidth = ((treeWidth - 44) * 0.55).clamp(120.0, 225.0);
    final borderColor =
        isObjectSelected ? colors.primary : colors.outlineVariant;
    final borderWidth = isObjectSelected ? 1.35 : 1.0;
    final isDark = theme.brightness == Brightness.dark;

    final objReport = crossReport.reportFor(obj.id);
    final syncBase = project.activeFeature.syncBaselineFor(obj.id);
    final syncBadge = _buildObjectSyncBadge(
      context: context,
      project: project,
      object: obj,
      objReport: objReport,
      syncBase: syncBase,
      colors: colors,
      isDark: isDark,
    );
    final badgeSignature = objReport != null && objReport.isSharedAcrossFeatures
        ? 'shared:${objReport.hasBreakingValidatedWarning}:'
              '${objReport.sharedWithValidatedFeature}:'
              '${objReport.sharedFeaturesSummary}:'
              '${objReport.totalDownstreamImpactCount}'
        : (syncBase != null &&
                  syncBase.sourceKind == ObjectSyncSourceKind.designDomain
              ? 'design:${syncBase.sourceDomainId}:${syncBase.sourceDisplayLabel}'
              : '');

    void handleSelectObject() {
      _clearTreeSelections();
      _lastFocusedObjectId = obj.id;
      _lastFocusedAttrPath = const <String>[];
      widget.controller.focusBusinessSelection(objectId: obj.id);
      setState(() {
        _selectedObjectId = obj.id;
        _selectedNodePath = null;
        if (widget.controller.modelPreferences.singleExpandedBusinessObject) {
          _expandedObjectIds.clear();
        }
        _expandedObjectIds.add(obj.id);
      });
    }

    void handleToggleExpanded() {
      setState(() {
        if (isExpanded) {
          _expandedObjectIds.remove(obj.id);
        } else {
          if (widget.controller.modelPreferences.singleExpandedBusinessObject) {
            _expandedObjectIds.clear();
          }
          _expandedObjectIds.add(obj.id);
        }
      });
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: syncBadge == null
                  ? RepoStickyHeaderDelegate(
                      entry: entry,
                      isExpanded: isExpanded,
                      isObjectSelected: isObjectSelected,
                      isHeaderHighlighted: isHeaderHighlighted,
                      overAttrLimit: overAttrLimit,
                      borderColor: borderColor,
                      borderWidth: borderWidth,
                      theme: theme,
                      colors: colors,
                      onSelectObject: handleSelectObject,
                      onToggleExpanded: handleToggleExpanded,
                    )
                  : _RepoStickyHeaderWithSyncBadgeDelegate(
                      entry: entry,
                      isExpanded: isExpanded,
                      isObjectSelected: isObjectSelected,
                      isHeaderHighlighted: isHeaderHighlighted,
                      overAttrLimit: overAttrLimit,
                      borderColor: borderColor,
                      borderWidth: borderWidth,
                      theme: theme,
                      colors: colors,
                      syncBadge: syncBadge,
                      badgeSignature: badgeSignature,
                      onSelectObject: handleSelectObject,
                      onToggleExpanded: handleToggleExpanded,
                    ),
            ),
            if (isExpanded)
              SliverToBoxAdapter(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(10),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border(
                        left: BorderSide(color: borderColor, width: borderWidth),
                        right: BorderSide(
                          color: borderColor,
                          width: borderWidth,
                        ),
                        bottom: BorderSide(
                          color: borderColor,
                          width: borderWidth,
                        ),
                      ),
                    ),
                    child: entry.childNodes.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Aucun attribut ni relation.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    _editAttributeDialog(context, project, obj),
                                icon: const Icon(Icons.add_rounded, size: 15),
                                label: const Text('Ajouter'),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: SuperTreeView(
                            id: 'spec-objects-tree-${obj.id}',
                            scrollPhysics:
                                const NeverScrollableScrollPhysics(),
                            showScrollbar: false,
                            config: SuperTreeViewConfig(
                              binding: JsonTextBinding(
                                repositoryId: entry.repoId,
                                path: 'nodes',
                              ),
                              rowHeight: 34,
                              headerSize: headerColumnWidth,
                              indent: 18,
                              initiallyExpanded: true,
                              showConnectors: true,
                              emptyText: 'Aucun attribut défini',
                              placements: const {
                                SuperTreeViewConfig.headerZone: ['header'],
                                SuperTreeViewConfig.dataZone: ['data'],
                              },
                            ),
                            onNodeSelected: (nodePath) {
                              _clearTreeSelections(exceptObjectId: obj.id);
                              final meta = entry.targetsByNodePath[nodePath];
                              final attrPath =
                                  meta?.attributePath ?? const <String>[];
                              _lastFocusedObjectId = obj.id;
                              _lastFocusedAttrPath = List<String>.unmodifiable(
                                attrPath,
                              );
                              widget.controller.focusBusinessSelection(
                                objectId: obj.id,
                                attributePath: attrPath,
                              );
                              setState(() {
                                _selectedObjectId = obj.id;
                                _selectedNodePath = nodePath;
                              });
                            },
                            header: Builder(
                              builder: (cellContext) {
                                final listScope =
                                    JsonListScope.maybeOf(cellContext);
                                final meta = listScope?.nodePath != null
                                    ? entry.targetsByNodePath[listScope!
                                          .nodePath!]
                                    : null;
                                final visual = visualForBusinessObjectNode(
                                  meta,
                                  colors,
                                  theme.brightness,
                                );
                                return _wrapWithNodeTooltip(
                                  context: cellContext,
                                  project: project,
                                  meta: meta,
                                  child: Row(
                                    children: [
                                      Icon(
                                        visual.icon,
                                        size: 15,
                                        color: visual.fgColor,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: SuperValue(
                                          id: 'spec-tree-node-name-${obj.id}',
                                          config: SuperValueConfig(
                                            mode: SuperValueMode.display,
                                            color: colors.onSurface,
                                            fontWeight:
                                                (meta?.isRelation == true ||
                                                    meta?.attrType ==
                                                        'object' ||
                                                    meta?.isArray == true)
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            binding: JsonTextBinding(
                                              repositoryId: entry.repoId,
                                              path: 'nodes[?].displayName',
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (meta?.isRequired == true)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4,
                                          ),
                                          child: Text(
                                            '*',
                                            style: TextStyle(
                                              color: colors.error,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            data: Builder(
                              builder: (cellContext) {
                                final listScope =
                                    JsonListScope.maybeOf(cellContext);
                                final meta = listScope?.nodePath != null
                                    ? entry.targetsByNodePath[listScope!
                                          .nodePath!]
                                    : null;
                                final visual = visualForBusinessObjectNode(
                                  meta,
                                  colors,
                                  theme.brightness,
                                );
                                final overLimit =
                                    meta?.isArray == true &&
                                    meta?.estimatedMaxRows != null &&
                                    meta!.estimatedMaxRows! >
                                        BusinessObjectSpec
                                            .maxEmbeddedArrayRows;
                                return _wrapWithNodeTooltip(
                                  context: cellContext,
                                  project: project,
                                  meta: meta,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: SuperValue(
                                          id: 'spec-tree-node-type-${obj.id}',
                                          config: SuperValueConfig(
                                            mode: SuperValueMode.display,
                                            fontSize: 12,
                                            fontWeight:
                                                (meta?.isRelation == true ||
                                                    meta?.attrType ==
                                                        'object' ||
                                                    meta?.isArray == true)
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: visual.fgColor,
                                            binding: JsonTextBinding(
                                              repositoryId: entry.repoId,
                                              path: 'nodes[?].displayType',
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (overLimit) ...[
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          size: 16,
                                          color: colors.error,
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _buildYamlSourceTab(
    BuildContext context,
    SpecForgeProject project,
    ColorScheme colors,
    ThemeData theme,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    _codeEditorConfig.style = SuperCodeStyle(
      theme: isDark ? SuperCodeTheme.atomOneDark : SuperCodeTheme.atomOneLight,
      fontSize: 13.5,
      lineHeight: 1.45,
      showLineNumbers: true,
      showFoldingHandles: true,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'DSL YAML (Yaml2JsonSchemasParser)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      _yamlDirty = false;
                      _yamlText = SpecSchemaDslBridge.toYamlLight(project);
                      _yamlErrorNotifier.value = '';
                      _codeEditorConfig.repaintCode();
                      setState(() {});
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Réinitialiser'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('spec-objects-apply-yaml'),
                    onPressed: () => _applyYamlSource(project),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Appliquer le YAML'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CodeEditor(
                  key: const ValueKey('spec-objects-yaml-editor'),
                  config: _codeEditorConfig,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonSchemaAndSeedTab(SpecForgeProject project) {
    final bundle = SpecSuperDesignerExporter.toBundle(
      project,
      modelPreferencesOverride: widget.controller.modelPreferences,
    );
    final safeProject = _safeFileSlug(project.name);
    final safeId = _safeFileSlug(project.id);
    return SpecJsonSchemaViewerView(
      key: const ValueKey('spec-objects-schema-viewer'),
      bundle: bundle,
      title: 'JSON Schema & Seed — ${project.name}',
      filenameStem: '${safeProject}_repositories_schema',
      exportDirectory: Directory(
        '${widget.controller.store.rootDirectory.path}${Platform.pathSeparator}exports${Platform.pathSeparator}$safeId',
      ),
      openInBrowser: widget.schemaBrowserLauncher,
      htmlSurfaceBuilder: widget.schemaViewerSurfaceBuilder,
      showTitle: false,
    );
  }

  static String _safeFileSlug(String raw) {
    final s = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'spec_forge' : s;
  }

  Future<void> _deleteAttributeAtPath(
    SpecForgeProject project,
    BusinessObjectSpec object,
    List<String> pathIds,
  ) async {
    if (pathIds.isEmpty) return;
    final updated = BusinessObjectOperations.deleteAttributeAtPath(
      object,
      pathIds,
    );
    await _replaceObject(project, updated);
  }

  Future<void> _extractArrayToSeparateObject(
    SpecForgeProject project,
    BusinessObjectSpec parentObject,
    List<String> attrPath,
    BusinessAttribute arrayAttr,
  ) async {
    final nextList = BusinessObjectOperations.extractArrayToSeparateObject(
      project.businessObjects,
      parentObject: parentObject,
      attrPath: attrPath,
      arrayAttr: arrayAttr,
    );
    await widget.controller.updateProject(
      project.copyWith(businessObjects: nextList),
    );
  }

  Future<void> _replaceObject(
    SpecForgeProject project,
    BusinessObjectSpec updated,
  ) async {
    final nextList = BusinessObjectOperations.replaceObject(
      project.businessObjects,
      updated,
    );
    await widget.controller.updateProject(
      project.copyWith(businessObjects: nextList),
    );
  }

  Future<void> _editObjectDialog(
    BuildContext context,
    SpecForgeProject project, {
    BusinessObjectSpec? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final techCtrl = TextEditingController(text: existing?.technicalName ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    var aggregateRoot = existing?.aggregateRoot ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nouvel objet métier'
                : 'Modifier ${existing.name}',
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom métier *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: techCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom technique PascalCase (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Agrégat racine (entité principale)'),
                  value: aggregateRoot,
                  onChanged: (v) => setDialogState(() => aggregateRoot = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final rawTech = techCtrl.text.trim();
      final effectiveTech = rawTech.isEmpty
          ? BusinessAttribute.toPascalCaseDslIdentifier(nameCtrl.text.trim())
          : (BusinessAttribute.isValidDslIdentifier(rawTech)
                ? rawTech
                : BusinessAttribute.toPascalCaseDslIdentifier(rawTech));
      final obj = BusinessObjectSpec(
        id: existing?.id ?? 'obj_${shortid.generate()}',
        name: nameCtrl.text.trim(),
        technicalName: effectiveTech,
        description: descCtrl.text.trim(),
        aggregateRoot: aggregateRoot,
        attributes: existing?.attributes ?? const [],
        relations: existing?.relations ?? const [],
        lifecycleStates: existing?.lifecycleStates ?? const [],
        lifecycleTransitions: existing?.lifecycleTransitions ?? const [],
      );
      final list = BusinessObjectOperations.upsertObject(
        project.businessObjects,
        obj,
      );
      await widget.controller.updateProject(
        project.copyWith(businessObjects: list),
      );
    }

    nameCtrl.dispose();
    techCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _editAttributeDialog(
    BuildContext context,
    SpecForgeProject project,
    BusinessObjectSpec object, {
    List<String> parentAttrPath = const <String>[],
    BusinessAttribute? existing,
  }) async {
    final attr = await showBusinessAttributeEditorDialog(
      context,
      project: project,
      existing: existing,
      isSubAttribute: parentAttrPath.isNotEmpty,
    );
    if (attr == null) return;

    final updatedObj = BusinessObjectOperations.upsertAttributeAtPath(
      object,
      parentAttrPath: parentAttrPath,
      attribute: attr,
    );
    try {
      updatedObj.validate();
      await _replaceObject(project, updatedObj);
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Widget _wrapWithNodeTooltip({
    required BuildContext context,
    required SpecForgeProject project,
    required BusinessObjectTreeSelectionTarget? meta,
    required Widget child,
  }) {
    if (meta == null) return child;
    final object = project.findBusinessObject(meta.objectId);
    if (object == null) return child;
    final attr = meta.attributePath.isNotEmpty
        ? BusinessObjectOperations.findAttributeByPath(
            object.attributes,
            meta.attributePath,
          )
        : null;
    final rel = meta.isRelation && meta.relationId.isNotEmpty
        ? object.relations.where((r) => r.id == meta.relationId).firstOrNull
        : null;
    final theme = Theme.of(context);
    final visual = visualForBusinessObjectNode(
      meta,
      theme.colorScheme,
      theme.brightness,
    );

    return Tooltip(
      waitDuration: const Duration(seconds: 2),
      showDuration: const Duration(seconds: 12),
      preferBelow: false,
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(color: Colors.transparent),
      richMessage: WidgetSpan(
        child: TreeNodeTooltipCard(
          project: project,
          object: object,
          attribute: attr,
          attributePath: meta.attributePath,
          relation: rel,
          visual: visual,
        ),
      ),
      child: child,
    );
  }

  Future<void> _normalizeAllIdentifiers(SpecForgeProject project) async {
    final normalizedObjects = BusinessObjectOperations.normalizeAllIdentifiers(
      project.businessObjects,
    );
    await widget.controller.updateProject(
      project.copyWith(businessObjects: normalizedObjects),
    );
  }
}

class _ObjectSyncBadgePill extends StatelessWidget {
  const _ObjectSyncBadgePill({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              if (icon != null) Icon(icon, size: 12, color: foregroundColor),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepoStickyHeaderWithSyncBadgeDelegate
    extends SliverPersistentHeaderDelegate {
  const _RepoStickyHeaderWithSyncBadgeDelegate({
    required this.entry,
    required this.isExpanded,
    required this.isObjectSelected,
    required this.isHeaderHighlighted,
    required this.overAttrLimit,
    required this.borderColor,
    required this.borderWidth,
    required this.theme,
    required this.colors,
    required this.syncBadge,
    required this.badgeSignature,
    required this.onSelectObject,
    required this.onToggleExpanded,
  });

  static const double _headerHeight = 84.0;

  final RepoTreeEntry entry;
  final bool isExpanded;
  final bool isObjectSelected;
  final bool isHeaderHighlighted;
  final bool overAttrLimit;
  final Color borderColor;
  final double borderWidth;
  final ThemeData theme;
  final ColorScheme colors;
  final Widget syncBadge;
  final String badgeSignature;
  final VoidCallback onSelectObject;
  final VoidCallback onToggleExpanded;

  @override
  double get minExtent => _headerHeight;

  @override
  double get maxExtent => _headerHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final obj = entry.object;
    final totalAttrs = obj.totalAttributeCount;
    final bgColor = isHeaderHighlighted
        ? Color.alphaBlend(
            colors.primaryContainer.withValues(alpha: 0.42),
            colors.surface,
          )
        : colors.surfaceContainerLow;
    final borderSide = BorderSide(color: borderColor, width: borderWidth);

    return Container(
      key: ValueKey('spec-objects-repo-tile-${obj.id}'),
      height: _headerHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: isExpanded
            ? const BorderRadius.vertical(top: Radius.circular(10))
            : BorderRadius.circular(10),
        border: Border.fromBorderSide(borderSide),
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onSelectObject,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  key: ValueKey('spec-objects-repo-toggle-${obj.id}'),
                  tooltip: isExpanded ? 'Replier' : 'Déplier',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: onToggleExpanded,
                  icon: Icon(
                    isExpanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            obj.aggregateRoot
                                ? Icons.hub_rounded
                                : Icons.account_tree_outlined,
                            size: 15,
                            color: obj.aggregateRoot
                                ? colors.primary
                                : colors.secondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              obj.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: entry.isSchemaValid
                                  ? colors.secondaryContainer
                                  : colors.errorContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              entry.isSchemaValid
                                  ? 'Valide'
                                  : '${entry.schemaIssueCount} err.',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: entry.isSchemaValid
                                    ? colors.onSecondaryContainer
                                    : colors.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      LayoutBuilder(
                        builder: (context, rowConstraints) {
                          final maxChipsWidth =
                              (rowConstraints.maxWidth * 0.58).clamp(
                                0.0,
                                180.0,
                              );
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${entry.repoAlias} · ${obj.technicalName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: maxChipsWidth,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      RepoCardChip(
                                        label: obj.aggregateRoot
                                            ? 'Agrégat'
                                            : 'Entité liée',
                                        bg: obj.aggregateRoot
                                            ? colors.primaryContainer
                                                  .withValues(alpha: 0.7)
                                            : colors.surfaceContainerHighest,
                                        fg: obj.aggregateRoot
                                            ? colors.onPrimaryContainer
                                            : colors.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
                                      RepoCardChip(
                                        label:
                                            '$totalAttrs/${BusinessObjectSpec.maxAttributesPerObject} attr.',
                                        bg: overAttrLimit
                                            ? colors.errorContainer
                                            : colors.surfaceContainerHighest,
                                        fg: overAttrLimit
                                            ? colors.onErrorContainer
                                            : colors.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Row(children: [Flexible(child: syncBadge)]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(
    covariant _RepoStickyHeaderWithSyncBadgeDelegate oldDelegate,
  ) {
    return oldDelegate.entry.object != entry.object ||
        oldDelegate.entry.repoAlias != entry.repoAlias ||
        oldDelegate.entry.isSchemaValid != entry.isSchemaValid ||
        oldDelegate.entry.schemaIssueCount != entry.schemaIssueCount ||
        oldDelegate.isExpanded != isExpanded ||
        oldDelegate.isObjectSelected != isObjectSelected ||
        oldDelegate.isHeaderHighlighted != isHeaderHighlighted ||
        oldDelegate.overAttrLimit != overAttrLimit ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.badgeSignature != badgeSignature ||
        oldDelegate.theme.brightness != theme.brightness;
  }
}


