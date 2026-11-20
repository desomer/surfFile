/// Atelier de l'étape 4 : Objets métiers structurés affichés via `Yaml2JsonSchemasParser`
/// et `SuperTreeView`, avec inspecteur hiérarchique et éditeur [CodeEditor] YAML ([BusinessObjectsEditorView]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:highlight/languages/yaml.dart' as yaml_lang;
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../../models/business_object_model_preferences.dart';
import '../../models/business_object_spec.dart';
import '../../models/spec_forge_project.dart';
import '../../services/exporters/spec_super_designer_exporter.dart';
import '../../services/spec_forge_controller.dart';
import '../../services/spec_schema_dsl_bridge.dart';
import '../spec_split_handle.dart';
import 'attribute_constraints_editor.dart';
import 'json_schema_viewer_dialog.dart';
import 'markdown_viewer_dialog.dart';
import 'model_preferences_dialog.dart';

/// Vue structurée à 3 onglets (« Arbre & Inspecteur », « Source YAML » via [CodeEditor],
/// et « JSON Schema & Seed » avec [SpecJsonSchemaViewerView]).
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
  static const String _treeRepoId = 'spec_schema_tree';

  final GlobalKey _splitRowKey = GlobalKey();
  late final JsonRepositoryStore _treeRepoStore;
  final ValueNotifier<String> _yamlErrorNotifier = ValueNotifier<String>('');
  late final CodeEditorConfig _codeEditorConfig;

  String _yamlText = '';
  List<BusinessObjectSpec>? _lastSyncedObjects;
  Map<String, _TreeNodeSelectionTarget> _targetsByNodePath = const {};
  String? _selectedNodePath;
  bool _yamlDirty = false;
  String? _treeBuildError;
  double _treePaneFraction = 5 / 11;
  double _treeDragOffset = SpecSplitHandle.width / 2;

  @override
  void initState() {
    super.initState();
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
    _treeRepoStore.registerRepository(
      RepositoryImpl(
        id: _treeRepoId,
        json: const <String, Object?>{'nodes': <Object?>[]},
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
    _yamlErrorNotifier.dispose();
    _treeRepoStore.dispose();
    super.dispose();
  }

  void _syncFromProject(SpecForgeProject? project, {bool forceYaml = false}) {
    if (project == null) return;
    if (!forceYaml && identical(_lastSyncedObjects, project.businessObjects)) {
      return;
    }
    _lastSyncedObjects = project.businessObjects;

    List<Map<String, Object?>> nodes = const <Map<String, Object?>>[];
    try {
      nodes = SpecSchemaDslBridge.buildTreeNodes(project);
      _treeBuildError = null;
    } on FormatException catch (e) {
      _treeBuildError = e.message;
      nodes = const <Map<String, Object?>>[];
    }
    final targets = <String, _TreeNodeSelectionTarget>{};
    void indexNode(Map<String, Object?> node, String nodePath) {
      final rawAttrPath = node['attributePath'];
      final attrPath = rawAttrPath is List
          ? [for (final s in rawAttrPath) '$s']
          : const <String>[];
      targets[nodePath] = _TreeNodeSelectionTarget(
        nodePath: nodePath,
        objectId: (node['objectId'] as String?) ?? '',
        relationId: (node['relationId'] as String?) ?? '',
        attributePath: attrPath,
        isRootObject: node['isRootObject'] == true,
        isRelation: ((node['relationId'] as String?) ?? '').isNotEmpty,
        isArray: node['isArray'] == true,
        isRequired: node['isRequired'] == true,
        attrType: (node['attrType'] as String?) ?? '',
        totalAttributes: (node['totalAttributes'] as int?) ?? 0,
        estimatedMaxRows: node['estimatedMaxRows'] as int?,
        typeIcon: (node['typeIcon'] as String?) ?? 'value',
        displayType: (node['displayType'] as String?) ?? '',
      );
      final children = node['children'];
      if (children is List) {
        for (var i = 0; i < children.length; i++) {
          final child = children[i];
          if (child is Map<String, Object?>) {
            indexNode(child, '$nodePath.children[$i]');
          }
        }
      }
    }

    for (var i = 0; i < nodes.length; i++) {
      indexNode(nodes[i], 'nodes[$i]');
    }
    _targetsByNodePath = targets;

    if (_selectedNodePath == null ||
        !_targetsByNodePath.containsKey(_selectedNodePath)) {
      _selectedNodePath = nodes.isNotEmpty ? 'nodes[0]' : null;
    }

    final focusedId = widget.controller.focusedObjectId;
    if (focusedId != null && focusedId.isNotEmpty) {
      final matched = _targetsByNodePath.entries
          .where((e) => e.value.isRootObject && e.value.objectId == focusedId)
          .firstOrNull;
      if (matched != null) {
        _selectedNodePath = matched.key;
      }
    }

    if (!_yamlDirty || forceYaml) {
      _yamlText = SpecSchemaDslBridge.toYamlLight(project);
      _yamlErrorNotifier.value = '';
      _yamlDirty = false;
      _codeEditorConfig.repaintCode();
    }

    unawaited(_treeRepoStore.replaceArray(_treeRepoId, 'nodes', nodes));
  }

  Future<void> _applyYamlSource(SpecForgeProject project) async {
    final source = _yamlText;
    try {
      final parsedObjects = SpecSchemaDslBridge.fromYamlLight(
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

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();
    _syncFromProject(project);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final objects = project.businessObjects;

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
                      OutlinedButton.icon(
                        key: const ValueKey('spec-objects-prefs-btn'),
                        onPressed: () =>
                            _editModelPreferencesDialog(context, project),
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: Text(
                          'Préférences du modèle (${project.businessObjectModelPreferences.formatCompactButtonSummary()})',
                        ),
                      ),
                      FilledButton.tonalIcon(
                        key: const ValueKey('spec-objects-add-root'),
                        onPressed: () => _editObjectDialog(context, project),
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
                Tab(text: 'Arbre & Inspecteur'),
                Tab(text: 'Source YAML'),
                Tab(
                  key: ValueKey('spec-objects-schema-tab'),
                  text: 'JSON Schema & Seed',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildTreeAndInspectorTab(context, project, colors, theme),
                  _buildYamlSourceTab(context, project, colors, theme),
                  _buildJsonSchemaAndSeedTab(project),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTreeAndInspectorTab(
    BuildContext context,
    SpecForgeProject project,
    ColorScheme colors,
    ThemeData theme,
  ) {
    if (project.businessObjects.isEmpty) {
      return const Center(
        child: Text(
          'Aucun objet métier pour l’instant.\nUtilisez le Domain Modeler à gauche ou cliquez sur « Nouvel objet ».',
          textAlign: TextAlign.center,
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

    final target = _selectedNodePath != null
        ? _targetsByNodePath[_selectedNodePath]
        : null;
    final selectedObject =
        (target != null && target.objectId.isNotEmpty
            ? project.findBusinessObject(target.objectId)
            : null) ??
        project.businessObjects.first;
    final selectedAttr = target == null || target.attributePath.isEmpty
        ? null
        : _findAttributeByPath(selectedObject.attributes, target.attributePath);

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
                alignment: Alignment.topLeft,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SuperTreeView(
                    id: 'spec-objects-tree',
                    config: SuperTreeViewConfig(
                      binding: const JsonTextBinding(
                        repositoryId: _treeRepoId,
                        path: 'nodes',
                      ),
                      rowHeight: 36,
                      headerSize: 225,
                      indent: 18,
                      initiallyExpanded: true,
                      showConnectors: true,
                      emptyText: 'Aucun objet métier',
                      placements: const {
                        SuperTreeViewConfig.headerZone: ['header'],
                        SuperTreeViewConfig.dataZone: ['data'],
                      },
                    ),
                    onNodeSelected: (nodePath) {
                      setState(() => _selectedNodePath = nodePath);
                    },
                    header: Builder(
                      builder: (cellContext) {
                        final listScope = JsonListScope.maybeOf(cellContext);
                        final meta = listScope?.nodePath != null
                            ? _targetsByNodePath[listScope!.nodePath]
                            : null;
                        final visual = _visualForNode(
                          meta,
                          colors,
                          theme.brightness,
                        );
                        if (meta?.isRootObject ?? false) {
                          return _wrapWithNodeTooltip(
                            context: cellContext,
                            project: project,
                            meta: meta,
                            child: Row(
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: visual.bgColor,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: visual.borderColor,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          visual.icon,
                                          size: 14,
                                          color: visual.fgColor,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: SuperValue(
                                            id: 'spec-tree-node-name',
                                            config: SuperValueConfig(
                                              mode: SuperValueMode.display,
                                              color: visual.fgColor,
                                              fontWeight: FontWeight.w700,
                                              binding: const JsonTextBinding(
                                                repositoryId: _treeRepoId,
                                                path: 'nodes[?].displayName',
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
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
                                  id: 'spec-tree-node-name',
                                  config: SuperValueConfig(
                                    mode: SuperValueMode.display,
                                    color: colors.onSurface,
                                    fontWeight:
                                        (meta?.isRelation == true ||
                                            meta?.attrType == 'object' ||
                                            meta?.isArray == true)
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    binding: const JsonTextBinding(
                                      repositoryId: _treeRepoId,
                                      path: 'nodes[?].displayName',
                                    ),
                                  ),
                                ),
                              ),
                              if (meta?.isRequired == true)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
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
                        final listScope = JsonListScope.maybeOf(cellContext);
                        final meta = listScope?.nodePath != null
                            ? _targetsByNodePath[listScope!.nodePath]
                            : null;
                        final visual = _visualForNode(
                          meta,
                          colors,
                          theme.brightness,
                        );
                        final overLimit =
                            (meta?.isRootObject == true &&
                                (meta?.totalAttributes ?? 0) >
                                    BusinessObjectSpec
                                        .maxAttributesPerObject) ||
                            (meta?.isArray == true &&
                                meta?.estimatedMaxRows != null &&
                                meta!.estimatedMaxRows! >
                                    BusinessObjectSpec.maxEmbeddedArrayRows);
                        return _wrapWithNodeTooltip(
                          context: cellContext,
                          project: project,
                          meta: meta,
                          child: Row(
                            children: [
                              Expanded(
                                child: SuperValue(
                                  id: 'spec-tree-node-type',
                                  config: SuperValueConfig(
                                    mode: SuperValueMode.display,
                                    fontSize: 12,
                                    fontWeight:
                                        (meta?.isRootObject == true ||
                                            meta?.isRelation == true ||
                                            meta?.attrType == 'object' ||
                                            meta?.isArray == true)
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: visual.fgColor,
                                    binding: const JsonTextBinding(
                                      repositoryId: _treeRepoId,
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
                  ? _AttributeInspectorPane(
                      project: project,
                      object: selectedObject,
                      attribute: selectedAttr,
                      attributePath: target.attributePath,
                      onBackToObject: () {
                        final rootEntry = _targetsByNodePath.entries
                            .where(
                              (e) =>
                                  e.value.isRootObject &&
                                  e.value.objectId == selectedObject.id,
                            )
                            .firstOrNull;
                        if (rootEntry != null) {
                          setState(() => _selectedNodePath = rootEntry.key);
                        }
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
                  : _BusinessObjectInspectorPane(
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
    final bundle = SpecSuperDesignerExporter.toBundle(project);
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

  BusinessAttribute? _findAttributeByPath(
    List<BusinessAttribute> attrs,
    List<String> pathIds,
  ) {
    if (pathIds.isEmpty) return null;
    final head = pathIds.first;
    for (final a in attrs) {
      if (a.id == head) {
        if (pathIds.length == 1) return a;
        return _findAttributeByPath(a.children, pathIds.sublist(1));
      }
    }
    return null;
  }

  Future<void> _deleteAttributeAtPath(
    SpecForgeProject project,
    BusinessObjectSpec object,
    List<String> pathIds,
  ) async {
    if (pathIds.isEmpty) return;
    List<BusinessAttribute> removeRec(
      List<BusinessAttribute> list,
      List<String> remaining,
    ) {
      if (remaining.length == 1) {
        return list.where((a) => a.id != remaining.first).toList();
      }
      final head = remaining.first;
      return [
        for (final a in list)
          if (a.id == head)
            a.copyWith(children: removeRec(a.children, remaining.sublist(1)))
          else
            a,
      ];
    }

    final updated = object.copyWith(
      attributes: removeRec(object.attributes, pathIds),
    );
    await _replaceObject(project, updated);
  }

  Future<void> _extractArrayToSeparateObject(
    SpecForgeProject project,
    BusinessObjectSpec parentObject,
    List<String> attrPath,
    BusinessAttribute arrayAttr,
  ) async {
    final newObjTech = _singularizePascal(arrayAttr.name);
    final newObjId = 'obj_${shortid.generate()}';
    final extractedAttributes = arrayAttr.children.isNotEmpty
        ? [
            ...arrayAttr.children,
            BusinessAttribute(
              id: 'attr_${shortid.generate()}',
              name: '${_toCamel(parentObject.technicalName)}Id',
              type: BusinessAttributeType.reference,
              required: true,
              referenceObjectId: parentObject.id,
              description: 'Référence vers ${parentObject.name}',
            ),
          ]
        : [
            BusinessAttribute(
              id: 'attr_${shortid.generate()}',
              name: 'libelle',
              type: BusinessAttributeType.string,
              required: true,
            ),
            BusinessAttribute(
              id: 'attr_${shortid.generate()}',
              name: '${_toCamel(parentObject.technicalName)}Id',
              type: BusinessAttributeType.reference,
              required: true,
              referenceObjectId: parentObject.id,
            ),
          ];

    final extractedObject = BusinessObjectSpec(
      id: newObjId,
      name: newObjTech,
      technicalName: newObjTech,
      description:
          'Objet métier dédié extrait du tableau ${parentObject.technicalName}.${arrayAttr.name} (> 200 lignes).',
      aggregateRoot: true,
      attributes: extractedAttributes,
    );

    final updatedParent = _removeAttrAndAddRelation(
      parentObject,
      attrPath,
      BusinessRelation(
        id: 'rel_${shortid.generate()}',
        name: arrayAttr.name,
        targetObjectId: newObjId,
        cardinality: BusinessRelationCardinality.oneToMany,
        required: arrayAttr.required,
        description: arrayAttr.description,
      ),
    );

    final nextList = [
      for (final o in project.businessObjects)
        if (o.id == updatedParent.id) updatedParent else o,
      extractedObject,
    ];
    await widget.controller.updateProject(
      project.copyWith(businessObjects: nextList),
    );
  }

  BusinessObjectSpec _removeAttrAndAddRelation(
    BusinessObjectSpec object,
    List<String> pathIds,
    BusinessRelation relation,
  ) {
    List<BusinessAttribute> removeRec(
      List<BusinessAttribute> list,
      List<String> remaining,
    ) {
      if (remaining.length == 1) {
        return list.where((a) => a.id != remaining.first).toList();
      }
      final head = remaining.first;
      return [
        for (final a in list)
          if (a.id == head)
            a.copyWith(children: removeRec(a.children, remaining.sublist(1)))
          else
            a,
      ];
    }

    return object.copyWith(
      attributes: removeRec(object.attributes, pathIds),
      relations: [...object.relations, relation],
    );
  }

  Future<void> _replaceObject(
    SpecForgeProject project,
    BusinessObjectSpec updated,
  ) async {
    final nextList = [
      for (final o in project.businessObjects)
        if (o.id == updated.id) updated else o,
    ];
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
      final list = List<BusinessObjectSpec>.from(project.businessObjects);
      final idx = list.indexWhere((o) => o.id == obj.id);
      if (idx >= 0) {
        list[idx] = obj;
      } else {
        list.add(obj);
      }
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

    List<BusinessAttribute> upsertAtPath(
      List<BusinessAttribute> list,
      List<String> remainingParentPath,
    ) {
      if (remainingParentPath.isEmpty) {
        final next = List<BusinessAttribute>.from(list);
        final idx = next.indexWhere((a) => a.id == attr.id);
        if (idx >= 0) {
          next[idx] = attr;
        } else {
          next.add(attr);
        }
        return next;
      }
      final head = remainingParentPath.first;
      return [
        for (final item in list)
          if (item.id == head)
            item.copyWith(
              children: upsertAtPath(
                item.children,
                remainingParentPath.sublist(1),
              ),
            )
          else
            item,
      ];
    }

    final updatedObj = object.copyWith(
      attributes: upsertAtPath(object.attributes, parentAttrPath),
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
    required _TreeNodeSelectionTarget? meta,
    required Widget child,
  }) {
    if (meta == null) return child;
    final object = project.findBusinessObject(meta.objectId);
    if (object == null) return child;
    final attr = meta.attributePath.isNotEmpty
        ? _findAttributeByPath(object.attributes, meta.attributePath)
        : null;
    final rel = meta.isRelation && meta.relationId.isNotEmpty
        ? object.relations.where((r) => r.id == meta.relationId).firstOrNull
        : null;
    final theme = Theme.of(context);
    final visual = _visualForNode(meta, theme.colorScheme, theme.brightness);

    return Tooltip(
      waitDuration: const Duration(milliseconds: 260),
      showDuration: const Duration(seconds: 12),
      preferBelow: false,
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(color: Colors.transparent),
      richMessage: WidgetSpan(
        child: _TreeNodeTooltipCard(
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

  static String _singularizePascal(String raw) {
    final cleaned = raw.trim();
    final singular = cleaned.endsWith('s') && cleaned.length > 2
        ? cleaned.substring(0, cleaned.length - 1)
        : cleaned;
    final words = singular
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty);
    if (words.isEmpty) return 'SousEntite';
    return words.map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join();
  }

  static String _toCamel(String pascal) {
    if (pascal.isEmpty) return 'parent';
    return '${pascal[0].toLowerCase()}${pascal.substring(1)}';
  }

  Future<void> _editModelPreferencesDialog(
    BuildContext context,
    SpecForgeProject project,
  ) async {
    final current = project.businessObjectModelPreferences;
    final saved = await showBusinessObjectModelPreferencesDialog(
      context,
      initialPreferences: current,
      hasExistingObjects: project.businessObjects.isNotEmpty,
    );
    if (saved == null) return;

    var updatedObjects = project.businessObjects;
    if (saved.applyAttributeCaseToExisting || saved.applyEnumCaseToExisting) {
      updatedObjects = _convertBusinessObjectCases(
        project.businessObjects,
        attributeCase: saved.applyAttributeCaseToExisting
            ? saved.preferences.attributeCase
            : null,
        enumCase: saved.applyEnumCaseToExisting
            ? saved.preferences.enumCase
            : null,
      );
    }
    if (saved.preferences != current ||
        updatedObjects != project.businessObjects) {
      await widget.controller.updateProject(
        project.copyWith(
          businessObjectModelPreferences: saved.preferences,
          businessObjects: updatedObjects,
        ),
      );
    }
  }

  List<BusinessObjectSpec> _convertBusinessObjectCases(
    List<BusinessObjectSpec> objects, {
    AttributeNamingCase? attributeCase,
    EnumValueNamingCase? enumCase,
  }) {
    List<BusinessAttribute> convertAttrs(List<BusinessAttribute> list) {
      final used = <String>{};
      return [
        for (final attr in list)
          () {
            final base = attributeCase != null
                ? attributeCase.formatIdentifier(attr.name)
                : attr.name;
            var candidate = base;
            var suffix = 2;
            while (!used.add(candidate)) {
              candidate = '${base}_$suffix';
              suffix++;
            }
            final nextEnumValues =
                enumCase != null && attr.enumValues.isNotEmpty
                ? [for (final v in attr.enumValues) enumCase.formatValue(v)]
                : attr.enumValues;
            return attr.copyWith(
              name: candidate,
              enumValues: nextEnumValues,
              children: attr.children.isEmpty
                  ? const []
                  : convertAttrs(attr.children),
            );
          }(),
      ];
    }

    return [
      for (final obj in objects)
        obj.copyWith(
          attributes: convertAttrs(obj.attributes),
          relations: attributeCase == null
              ? obj.relations
              : [
                  for (final rel in obj.relations)
                    rel.copyWith(name: attributeCase.formatIdentifier(rel.name)),
                ],
          lifecycleStates: enumCase == null
              ? obj.lifecycleStates
              : [
                  for (final st in obj.lifecycleStates)
                    st.copyWith(name: enumCase.formatValue(st.name)),
                ],
          lifecycleTransitions: enumCase == null
              ? obj.lifecycleTransitions
              : [
                  for (final tr in obj.lifecycleTransitions)
                    tr.copyWith(
                      fromState: enumCase.formatValue(tr.fromState),
                      toState: enumCase.formatValue(tr.toState),
                    ),
                ],
        ),
    ];
  }

  Future<void> _normalizeAllIdentifiers(SpecForgeProject project) async {
    List<BusinessAttribute> normAttrs(List<BusinessAttribute> list) {
      final used = <String>{};
      return [
        for (final attr in list)
          () {
            final base = BusinessAttribute.isValidDslIdentifier(attr.name)
                ? attr.name
                : BusinessAttribute.normalizeDslIdentifier(attr.name);
            var candidate = base;
            var suffix = 2;
            while (!used.add(candidate)) {
              candidate = '${base}_$suffix';
              suffix++;
            }
            return attr.copyWith(
              name: candidate,
              children: attr.children.isEmpty
                  ? const []
                  : normAttrs(attr.children),
            );
          }(),
      ];
    }

    final normalizedObjects = [
      for (final obj in project.businessObjects)
        obj.copyWith(
          technicalName:
              BusinessAttribute.isValidDslIdentifier(obj.technicalName)
              ? obj.technicalName
              : BusinessAttribute.toPascalCaseDslIdentifier(obj.technicalName),
          attributes: normAttrs(obj.attributes),
          relations: [
            for (final rel in obj.relations)
              rel.copyWith(
                name: BusinessAttribute.isValidDslIdentifier(rel.name)
                    ? rel.name
                    : BusinessAttribute.normalizeDslIdentifier(
                        rel.name,
                        fallback: 'relation',
                      ),
              ),
          ],
        ),
    ];
    await widget.controller.updateProject(
      project.copyWith(businessObjects: normalizedObjects),
    );
  }
}

class _TreeNodeSelectionTarget {
  const _TreeNodeSelectionTarget({
    required this.nodePath,
    required this.objectId,
    required this.relationId,
    required this.attributePath,
    required this.isRootObject,
    required this.isRelation,
    required this.isArray,
    required this.isRequired,
    required this.attrType,
    required this.totalAttributes,
    required this.estimatedMaxRows,
    required this.typeIcon,
    required this.displayType,
  });

  final String nodePath;
  final String objectId;
  final String relationId;
  final List<String> attributePath;
  final bool isRootObject;
  final bool isRelation;
  final bool isArray;
  final bool isRequired;
  final String attrType;
  final int totalAttributes;
  final int? estimatedMaxRows;
  final String typeIcon;
  final String displayType;
}

({IconData icon, Color fgColor, Color bgColor, Color borderColor})
_visualForNode(
  _TreeNodeSelectionTarget? meta,
  ColorScheme colors,
  Brightness brightness,
) {
  final isDark = brightness == Brightness.dark;
  if (meta == null) {
    return (
      icon: Icons.label_outline_rounded,
      fgColor: colors.onSurfaceVariant,
      bgColor: colors.surfaceContainerHighest,
      borderColor: colors.outlineVariant,
    );
  }
  final overLimit =
      (meta.isRootObject &&
          meta.totalAttributes > BusinessObjectSpec.maxAttributesPerObject) ||
      (meta.isArray &&
          meta.estimatedMaxRows != null &&
          meta.estimatedMaxRows! > BusinessObjectSpec.maxEmbeddedArrayRows);
  if (overLimit) {
    return (
      icon: meta.isRootObject ? Icons.hub_rounded : Icons.view_list_rounded,
      fgColor: colors.onErrorContainer,
      bgColor: colors.errorContainer,
      borderColor: colors.error,
    );
  }
  if (meta.isRootObject) {
    return (
      icon: Icons.hub_rounded,
      fgColor: colors.onPrimaryContainer,
      bgColor: colors.primaryContainer,
      borderColor: colors.primary.withValues(alpha: 0.55),
    );
  }
  if (meta.isRelation) {
    return (
      icon: Icons.link_rounded,
      fgColor: colors.onTertiaryContainer,
      bgColor: colors.tertiaryContainer,
      borderColor: colors.tertiary.withValues(alpha: 0.55),
    );
  }
  if (meta.isArray) {
    final fg = isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
    final bg = isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
    final border = isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
    return (
      icon: Icons.view_list_rounded,
      fgColor: fg,
      bgColor: bg,
      borderColor: border.withValues(alpha: 0.65),
    );
  }
  if (meta.attrType == 'object' || meta.typeIcon == 'container') {
    return (
      icon: Icons.data_object_rounded,
      fgColor: colors.onSecondaryContainer,
      bgColor: colors.secondaryContainer,
      borderColor: colors.secondary.withValues(alpha: 0.55),
    );
  }
  if (meta.attrType == 'enumeration') {
    final fg = isDark ? const Color(0xFF5EEAD4) : const Color(0xFF115E59);
    final bg = isDark ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1);
    final border = isDark ? const Color(0xFF14B8A6) : const Color(0xFF0D9488);
    return (
      icon: Icons.list_alt_rounded,
      fgColor: fg,
      bgColor: bg,
      borderColor: border.withValues(alpha: 0.65),
    );
  }
  if (meta.attrType == 'reference') {
    final fg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF);
    final bg = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE);
    final border = isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
    return (
      icon: Icons.north_east_rounded,
      fgColor: fg,
      bgColor: bg,
      borderColor: border.withValues(alpha: 0.65),
    );
  }

  final scalarIcon = switch (meta.attrType) {
    'integer' || 'number' => Icons.tag_rounded,
    'boolean' => Icons.toggle_on_outlined,
    'date' || 'datetime' => Icons.calendar_today_outlined,
    'uuid' => Icons.fingerprint_rounded,
    'email' => Icons.alternate_email_rounded,
    'url' => Icons.language_rounded,
    _ => Icons.short_text_rounded,
  };
  return (
    icon: scalarIcon,
    fgColor: colors.onSurface,
    bgColor: colors.surfaceContainerHighest,
    borderColor: colors.outline.withValues(alpha: 0.55),
  );
}

class _BusinessObjectInspectorPane extends StatelessWidget {
  const _BusinessObjectInspectorPane({
    required this.project,
    required this.object,
    required this.controller,
    required this.onEditMeta,
    required this.onAddAttribute,
    required this.onEditAttribute,
    required this.onDeleteAttribute,
  });

  final SpecForgeProject project;
  final BusinessObjectSpec object;
  final SpecForgeController controller;
  final VoidCallback onEditMeta;
  final VoidCallback onAddAttribute;
  final ValueChanged<BusinessAttribute> onEditAttribute;
  final ValueChanged<BusinessAttribute> onDeleteAttribute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final totalAttrs = object.totalAttributeCount;
    final ratio = (totalAttrs / BusinessObjectSpec.maxAttributesPerObject)
        .clamp(0.0, 1.0);
    final gaugeColor = totalAttrs > BusinessObjectSpec.maxAttributesPerObject
        ? colors.error
        : (totalAttrs >= 160 ? colors.tertiary : colors.primary);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${object.name} (${object.technicalName})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (object.description.isNotEmpty)
                    Text(
                      object.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Modifier l’objet',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditMeta,
            ),
            IconButton(
              tooltip: 'Supprimer l’objet',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                final next = project.businessObjects
                    .where((o) => o.id != object.id)
                    .toList();
                controller.updateProject(
                  project.copyWith(businessObjects: next),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: ratio,
                color: gaugeColor,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$totalAttrs / ${BusinessObjectSpec.maxAttributesPerObject} attributs',
              style: theme.textTheme.labelMedium?.copyWith(
                color: gaugeColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AttributeSchemaPreviewCard(
          title: 'Aperçu JSON Schema (${object.technicalName})',
          schemaMap: SpecSuperDesignerExporter.objectToJsonSchema(
            project,
            object,
          ),
          badges: [
            '$totalAttrs/${BusinessObjectSpec.maxAttributesPerObject} attributs',
            '${object.relations.length} relation(s)',
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              'Attributs & sous-objets (${object.attributes.length} racine)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('spec-objects-add-attr'),
              onPressed: onAddAttribute,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (object.attributes.isEmpty)
          Text(
            'Aucun attribut défini.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          )
        else
          for (final attr in object.attributes)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 6),
              color: colors.surfaceContainerLow,
              child: ListTile(
                dense: true,
                title: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      attr.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Chip(
                      label: Text(
                        attr.isArray
                            ? '${attr.type.dslKeyword}[]'
                            : attr.type.dslKeyword,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (attr.type == BusinessAttributeType.object)
                      Chip(
                        label: Text('${attr.children.length} sous-champ(s)'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (attr.isArray && attr.estimatedMaxRows != null)
                      Chip(
                        label: Text('max ${attr.estimatedMaxRows} lignes'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (attr.schemaConstraints.isNotEmpty)
                      Chip(
                        label: Text(attr.schemaConstraints.formatSummary()),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                subtitle: (attr.description.isEmpty &&
                        attr.schemaConstraints.examples.isEmpty)
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (attr.description.isNotEmpty)
                            Text(attr.description),
                          if (attr.schemaConstraints.examples.isNotEmpty)
                            Text(
                              'Exemples : ${attr.schemaConstraints.examples.map(_formatExampleValue).join(', ')}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.primary,
                                fontFamily: 'monospace',
                              ),
                            ),
                        ],
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      onPressed: () => onEditAttribute(attr),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => onDeleteAttribute(attr),
                    ),
                  ],
                ),
              ),
            ),
        if (object.relations.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Relations (${object.relations.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final rel in object.relations)
            ListTile(
              dense: true,
              leading: const Icon(Icons.link_rounded, size: 18),
              title: Text(
                '${rel.name} → ${project.findBusinessObject(rel.targetObjectId)?.name ?? rel.targetObjectId} (${rel.cardinality.symbol})',
              ),
              subtitle: rel.description.isEmpty ? null : Text(rel.description),
            ),
        ],
        if (object.lifecycleStates.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Cycle de vie (${object.lifecycleStates.length} états)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in object.lifecycleStates)
                Chip(
                  avatar: Icon(
                    s.isInitial
                        ? Icons.play_circle_outline_rounded
                        : (s.isTerminal
                              ? Icons.stop_circle_outlined
                              : Icons.circle_outlined),
                    size: 16,
                  ),
                  label: Text(s.effectiveLabel),
                ),
            ],
          ),
          if (object.lifecycleTransitions.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final tr in object.lifecycleTransitions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${tr.fromState} → ${tr.toState}'
                  '${tr.trigger.isEmpty ? '' : ' (${tr.trigger})'}'
                  '${tr.guardSummary.isEmpty ? '' : ' — Garde : ${tr.guardSummary}'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class _AttributeInspectorPane extends StatelessWidget {
  const _AttributeInspectorPane({
    required this.project,
    required this.object,
    required this.attribute,
    required this.attributePath,
    required this.onBackToObject,
    required this.onEditAttribute,
    required this.onAddChildAttribute,
    required this.onDeleteAttribute,
    required this.onExtractToSeparateObject,
  });

  final SpecForgeProject project;
  final BusinessObjectSpec object;
  final BusinessAttribute attribute;
  final List<String> attributePath;
  final VoidCallback onBackToObject;
  final VoidCallback onEditAttribute;
  final VoidCallback? onAddChildAttribute;
  final VoidCallback onDeleteAttribute;
  final VoidCallback? onExtractToSeparateObject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onBackToObject,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text(
                    object.technicalName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditAttribute,
            ),
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: onDeleteAttribute,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          attribute.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Chip(
              label: Text(
                '${attribute.type.label} (${attribute.type.dslKeyword})',
              ),
            ),
            if (attribute.required) const Chip(label: Text('Obligatoire (!)')),
            if (attribute.nullable) const Chip(label: Text('Nullable (?)')),
            if (attribute.isArray) const Chip(label: Text('Tableau ([])')),
            if (attribute.isArray && attribute.estimatedMaxRows != null)
              Chip(label: Text('Max ${attribute.estimatedMaxRows} lignes')),
          ],
        ),
        if (attribute.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(attribute.description),
        ],
        if (attribute.constraints.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Contraintes : ${attribute.constraints}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (attribute.enumValues.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Valeurs énumérées : ${attribute.enumValues.join(', ')}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (attribute.schemaConstraints.examples.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Exemples',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            key: const ValueKey('spec-attr-inspector-examples'),
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final ex in attribute.schemaConstraints.examples)
                Chip(
                  avatar: Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 15,
                    color: colors.primary,
                  ),
                  label: Text(
                    _formatExampleValue(ex),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        if (attribute.referenceObjectId.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Référence vers : ${project.findBusinessObject(attribute.referenceObjectId)?.name ?? attribute.referenceObjectId}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        AttributeSchemaPreviewCard(
          schemaMap: SpecSuperDesignerExporter.attributeToJsonSchema(attribute),
          badges: attribute.schemaConstraints.describeBadges(),
        ),
        if (onExtractToSeparateObject != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Règle tableau imbriqué (max 200 lignes)',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Si ce tableau doit dépasser 200 lignes fonctionnelles, extrayez-le en objet métier séparé relié par relation 1:N.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  key: const ValueKey('spec-objects-extract-array'),
                  onPressed: onExtractToSeparateObject,
                  icon: const Icon(Icons.call_split_rounded, size: 16),
                  label: const Text('Extraire en objet métier dédié'),
                ),
              ],
            ),
          ),
        ],
        if (attribute.type == BusinessAttributeType.object) ...[
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'Sous-attributs (${attribute.children.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onAddChildAttribute != null)
                OutlinedButton.icon(
                  key: const ValueKey('spec-objects-add-subattr'),
                  onPressed: onAddChildAttribute,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Ajouter sous-attribut'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (attribute.children.isEmpty)
            Text(
              'Aucun sous-attribut dans ce sous-objet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            for (final child in attribute.children)
              Card(
                elevation: 0,
                color: colors.surfaceContainerLow,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text(
                    '${child.name} : ${child.type.dslKeyword}${child.isArray ? '[]' : ''}',
                  ),
                  subtitle: child.description.isEmpty
                      ? null
                      : Text(child.description),
                ),
              ),
        ],
      ],
    );
  }
}

class _TreeNodeTooltipCard extends StatelessWidget {
  const _TreeNodeTooltipCard({
    required this.project,
    required this.object,
    required this.attribute,
    required this.attributePath,
    required this.relation,
    required this.visual,
  });

  final SpecForgeProject project;
  final BusinessObjectSpec object;
  final BusinessAttribute? attribute;
  final List<String> attributePath;
  final BusinessRelation? relation;
  final ({IconData icon, Color fgColor, Color bgColor, Color borderColor})
  visual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 250, maxWidth: 380),
        child: Card(
          key: const ValueKey('spec-tree-node-tooltip-card'),
          elevation: 8,
          shadowColor: colors.shadow.withValues(alpha: 0.35),
          color: colors.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: visual.borderColor, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DefaultTextStyle(
              style:
                  theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface,
                  ) ??
                  const TextStyle(fontSize: 12),
              child: attribute != null
                  ? _buildAttributeContent(theme, colors, attribute!)
                  : (relation != null
                        ? _buildRelationContent(theme, colors, relation!)
                        : _buildObjectContent(theme, colors)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttributeContent(
    ThemeData theme,
    ColorScheme colors,
    BusinessAttribute attr,
  ) {
    final schemaBadges = attr.schemaConstraints.describeBadges();
    final refObj = attr.referenceObjectId.isNotEmpty
        ? project.findBusinessObject(attr.referenceObjectId)
        : null;
    final pathBreadcrumbs = _resolveAttributePathNames(
      object.attributes,
      attributePath,
    );
    final typeLabel =
        '${attr.type.label} (${attr.type.dslKeyword}${attr.isArray ? '[]' : ''})';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: visual.bgColor,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: visual.borderColor),
              ),
              child: Icon(visual.icon, size: 15, color: visual.fgColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attr.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  Text(
                    '${object.technicalName}.${pathBreadcrumbs.join('.')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _TooltipPill(
              label: typeLabel,
              bgColor: visual.bgColor,
              fgColor: visual.fgColor,
              borderColor: visual.borderColor,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            _TooltipPill(
              label: attr.required ? 'Obligatoire (!)' : 'Optionnel',
              bgColor: attr.required
                  ? colors.errorContainer.withValues(alpha: 0.7)
                  : colors.surfaceContainerLow,
              fgColor: attr.required
                  ? colors.onErrorContainer
                  : colors.onSurfaceVariant,
              borderColor: attr.required
                  ? colors.error.withValues(alpha: 0.4)
                  : colors.outlineVariant,
            ),
            if (attr.nullable)
              _TooltipPill(
                label: 'Nullable (?)',
                bgColor: colors.surfaceContainerLow,
                fgColor: colors.onSurfaceVariant,
                borderColor: colors.outlineVariant,
              ),
            if (attr.unique)
              _TooltipPill(
                label: 'Unique',
                bgColor: colors.secondaryContainer.withValues(alpha: 0.7),
                fgColor: colors.onSecondaryContainer,
                borderColor: colors.secondary.withValues(alpha: 0.4),
              ),
            if (attr.isArray)
              _TooltipPill(
                label: attr.estimatedMaxRows != null
                    ? 'Tableau · max ${attr.estimatedMaxRows} lignes'
                    : 'Tableau ([])',
                bgColor: colors.tertiaryContainer.withValues(alpha: 0.7),
                fgColor: colors.onTertiaryContainer,
                borderColor: colors.tertiary.withValues(alpha: 0.4),
              ),
            if (attr.type == BusinessAttributeType.object)
              _TooltipPill(
                label: '${attr.children.length} sous-champ(s)',
                bgColor: colors.secondaryContainer.withValues(alpha: 0.7),
                fgColor: colors.onSecondaryContainer,
                borderColor: colors.secondary.withValues(alpha: 0.4),
              ),
            if (attr.defaultValue != null &&
                attr.defaultValue!.trim().isNotEmpty)
              _TooltipPill(
                label: 'Défaut : ${attr.defaultValue!.trim()}',
                bgColor: colors.surfaceContainerLow,
                fgColor: colors.onSurface,
                borderColor: colors.outlineVariant,
              ),
          ],
        ),
        if (attr.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            attr.description,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurface),
          ),
        ],
        if (refObj != null || attr.referenceObjectId.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Référence → ${refObj != null ? '${refObj.name} (${refObj.technicalName})' : attr.referenceObjectId}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (attr.enumValues.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Valeurs possibles : ${attr.enumValues.join(', ')}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        if (attr.constraints.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Contraintes : ${attr.constraints}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        if (attr.schemaConstraints.examples.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Exemples',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.secondary,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            key: const ValueKey('spec-tree-tooltip-examples'),
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final ex in attr.schemaConstraints.examples.take(5))
                _TooltipPill(
                  label: _formatExampleValue(ex),
                  bgColor: colors.secondaryContainer.withValues(alpha: 0.65),
                  fgColor: colors.onSecondaryContainer,
                  borderColor: colors.secondary.withValues(alpha: 0.35),
                ),
              if (attr.schemaConstraints.examples.length > 5)
                _TooltipPill(
                  label: '+${attr.schemaConstraints.examples.length - 5}',
                  bgColor: colors.surfaceContainerLow,
                  fgColor: colors.onSurfaceVariant,
                  borderColor: colors.outlineVariant,
                ),
            ],
          ),
        ],
        if (schemaBadges.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Contraintes JSON Schema',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final badge in schemaBadges)
                _TooltipPill(
                  label: badge,
                  bgColor: colors.primaryContainer.withValues(alpha: 0.55),
                  fgColor: colors.onPrimaryContainer,
                  borderColor: colors.primary.withValues(alpha: 0.35),
                ),
            ],
          ),
        ],
        if (attr.children.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Sous-attributs',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          for (final child in attr.children.take(5))
            Text(
              '• ${child.name} : ${child.type.dslKeyword}${child.isArray ? '[]' : ''}${child.required ? '!' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: colors.onSurface,
              ),
            ),
          if (attr.children.length > 5)
            Text(
              '… +${attr.children.length - 5} autre(s)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildRelationContent(
    ThemeData theme,
    ColorScheme colors,
    BusinessRelation rel,
  ) {
    final target = project.findBusinessObject(rel.targetObjectId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(visual.icon, size: 16, color: visual.fgColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${object.technicalName}.${rel.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _TooltipPill(
              label: 'Relation ${rel.cardinality.symbol}',
              bgColor: visual.bgColor,
              fgColor: visual.fgColor,
              borderColor: visual.borderColor,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Cible : ${target != null ? '${target.name} (${target.technicalName})' : rel.targetObjectId}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
        if (rel.inverseName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Relation inverse : ${rel.inverseName}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        if (rel.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(rel.description, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _buildObjectContent(ThemeData theme, ColorScheme colors) {
    final total = object.totalAttributeCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(visual.icon, size: 16, color: visual.fgColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${object.name} (${object.technicalName})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _TooltipPill(
              label: object.aggregateRoot ? 'Agrégat racine' : 'Entité',
              bgColor: visual.bgColor,
              fgColor: visual.fgColor,
              borderColor: visual.borderColor,
            ),
          ],
        ),
        if (object.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(object.description, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            _TooltipPill(
              label:
                  '$total / ${BusinessObjectSpec.maxAttributesPerObject} attributs',
              bgColor: colors.primaryContainer.withValues(alpha: 0.6),
              fgColor: colors.onPrimaryContainer,
              borderColor: colors.primary.withValues(alpha: 0.35),
            ),
            _TooltipPill(
              label: '${object.relations.length} relation(s)',
              bgColor: colors.surfaceContainerLow,
              fgColor: colors.onSurfaceVariant,
              borderColor: colors.outlineVariant,
            ),
            if (object.lifecycleStates.isNotEmpty)
              _TooltipPill(
                label: '${object.lifecycleStates.length} état(s)',
                bgColor: colors.secondaryContainer.withValues(alpha: 0.6),
                fgColor: colors.onSecondaryContainer,
                borderColor: colors.secondary.withValues(alpha: 0.35),
              ),
          ],
        ),
        if (object.lifecycleStates.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'États : ${object.lifecycleStates.map((s) => s.effectiveLabel).join(' → ')}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  static List<String> _resolveAttributePathNames(
    List<BusinessAttribute> attrs,
    List<String> pathIds,
  ) {
    final names = <String>[];
    var current = attrs;
    for (final id in pathIds) {
      final found = current.where((a) => a.id == id).firstOrNull;
      if (found == null) break;
      names.add(found.name);
      current = found.children;
    }
    return names;
  }
}

class _TooltipPill extends StatelessWidget {
  const _TooltipPill({
    required this.label,
    required this.bgColor,
    required this.fgColor,
    required this.borderColor,
  });

  final String label;
  final Color bgColor;
  final Color fgColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fgColor,
        ),
      ),
    );
  }
}

String _formatExampleValue(Object? value) {
  if (value is String) return value;
  return jsonEncode(value);
}
