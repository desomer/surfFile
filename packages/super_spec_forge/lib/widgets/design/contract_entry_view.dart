/// Fiche d'un modèle ou contrat ouverte depuis le catalogue d'un domaine :
/// chat IA et détail de son unique objet (arbre `SuperTreeView` + inspecteur).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:highlight/languages/yaml.dart' as yaml_lang;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../../ai/domain_model_ai.dart';
import '../../models/business_object_spec.dart';
import '../../models/domain_contracts.dart';
import '../../models/domain_layer_spec.dart';
import '../../models/spec_forge_project.dart';
import '../../services/business_object_operations.dart';
import '../../services/exporters/spec_super_designer_exporter.dart';
import '../../services/spec_forge_controller.dart';
import '../../services/spec_schema_dsl_bridge.dart';
import '../spec_split_handle.dart';
import '../workspace/attribute_constraints_editor.dart';
import '../workspace/business_objects/business_object_inspector_panes.dart';
import '../workspace/business_objects/business_object_tree_models.dart';
import '../workspace/json_schema_viewer_dialog.dart';
import '../workspace/markdown_viewer_dialog.dart';
import 'contract_model_chat_pane.dart';

/// Icône de chaque étape, partagée par l'arbre, le formulaire et la fiche.
const contractStageIcons = {
  ContractStage.design: Icons.build,
  ContractStage.validation: Icons.check_circle,
  ContractStage.code: Icons.code,
  ContractStage.delivery: Icons.flag,
};

/// Libellé de chaque étape.
const contractStageLabels = {
  ContractStage.design: 'Conception',
  ContractStage.validation: 'Validation',
  ContractStage.code: 'Code',
  ContractStage.delivery: 'Livraison',
};

/// Libellé de chaque avancement.
const contractStatusLabels = {
  ContractStatus.pending: 'À faire',
  ContractStatus.inProgress: 'En cours',
  ContractStatus.done: 'Terminé',
};

/// Couleur de l'indicateur d'une étape selon son avancement.
Color contractStatusColor(ContractStatus? status, ColorScheme colors) =>
    switch (status) {
      ContractStatus.done => Colors.green,
      ContractStatus.inProgress => Colors.orange,
      _ => colors.outline,
    };

/// Couleur du badge d'un type DSL.
Color contractTypeColor(String type) => switch (type) {
  'model' || 'part' => Colors.blue.shade700,
  'component' => Colors.teal.shade700,
  'eventxpayloaddto' || 'eventxenvelopedto' => Colors.deepPurple,
  'flatfile' => Colors.blueGrey.shade700,
  _ => Colors.indigo,
};

/// Page de détail d'une entrée du catalogue : identité et avancement, puis
/// chat IA | détail de l'objet, comme l'étape Spec « Objets métier » mais
/// pour un seul objet stocké dans le domaine sous l'ID de l'entrée.
class ContractEntryView extends StatefulWidget {
  /// Crée la fiche de [entry] dans le document [document] du domaine [domainId].
  const ContractEntryView({
    required this.controller,
    required this.domainId,
    required this.document,
    required this.entry,
    this.onOpenDomainLayer,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    this.schemaViewerSurfaceBuilder,
    this.schemaBrowserLauncher,
    super.key,
  });

  /// Contrôleur qui persiste l'objet et le chat dans le domaine.
  final SpecForgeController controller;

  /// Domaine propriétaire du document.
  final String domainId;

  /// Document du domaine, dernière version enregistrée.
  final DomainContracts document;

  /// Entrée DSL affichée.
  final JsonNode entry;

  /// Ouvre la page dédiée à la couche Domain (Architecture Hexagonale) de cet objet.
  final VoidCallback? onOpenDomainLayer;

  /// Remplacent les accès fichiers et presse-papiers du chat (tests).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  /// Constructeur optionnel pour remplacer la WebView dans l'onglet « Repository » (tests).
  final SpecMarkdownViewerSurfaceBuilder? schemaViewerSurfaceBuilder;

  /// Lanceur navigateur optionnel pour l'ouverture du `.html` généré (tests).
  final SpecMarkdownBrowserLauncher? schemaBrowserLauncher;

  @override
  State<ContractEntryView> createState() => _ContractEntryViewState();
}

/// Objet affiché, projet temporaire servant aux éditeurs d'attributs, et
/// index des nœuds de l'arbre par `nodePath`.
typedef _ModelSnapshot = ({
  SpecForgeProject project,
  BusinessObjectSpec object,
  Map<String, BusinessObjectTreeSelectionTarget> targets,
  String? error,
});

class _ContractEntryViewState extends State<ContractEntryView> {
  static const _repo = 'contract_model_tree';
  static const _defaultChatFraction = 0.36;
  static const _defaultTreeFraction = 0.5;

  final _store = JsonRepositoryStore(Directory.systemTemp);
  bool _registered = false;
  double _chatFraction = _defaultChatFraction;
  double _treeFraction = _defaultTreeFraction;
  DomainContracts? _syncedDocument;
  String? _syncedEntryId;
  late _ModelSnapshot _model;

  final _filterCtrl = TextEditingController();
  bool _showFilterBar = false;
  String? _syncedFilter;
  List<String> _syncedFocus = const [];
  final ValueNotifier<String> _yamlErrorNotifier = ValueNotifier<String>('');
  late final CodeEditorConfig _codeEditorConfig;
  String _yamlText = '';
  bool _yamlDirty = false;

  /// Attribut sélectionné (vide = objet entier), repéré par ses IDs et porté
  /// par le contrôleur : il survit aux réordonnancements et l'IA le pilote
  /// (`focus_stage_or_object`) comme dans l'étape Spec « Objets métier ».
  List<String> get _focusPath => widget.controller.domainModelAttributePath(
    widget.domainId,
    widget.entry.id,
  );

  /// Filtre de l'arbre, partagé avec l'outil IA `filter_business_objects`.
  String get _filter =>
      widget.controller.domainModelFilter(widget.domainId, widget.entry.id);

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
          SpecSchemaDslBridge.applySingleObjectYamlSource(
            value,
            current: _model.object,
            referenceTargets: widget.document.referenceTargetsOf(widget.entry),
          );
        } on FormatException catch (e) {
          err = e.message;
        }
        _yamlErrorNotifier.value = err;
      },
      notifError: _yamlErrorNotifier,
      useLargeTextViewer: false,
    );
    _sync(forceYaml: true);
  }

  @override
  void didUpdateWidget(ContractEntryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    _yamlErrorNotifier.dispose();
    _store.dispose();
    super.dispose();
  }

  String? get _selectedNodePath {
    final path = _focusPath;
    if (path.isEmpty) return null;
    for (final MapEntry(key: nodePath, value: target)
        in _model.targets.entries) {
      if (_samePath(target.attributePath, path)) return nodePath;
    }
    return null;
  }

  static bool _samePath(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

  /// Reconstruit l'objet et l'arbre quand le document, l'entrée ou le filtre
  /// change ; un simple changement de focus ne fait que resurligner le nœud.
  void _sync({bool forceYaml = false}) {
    final document = widget.document;
    final entry = widget.entry;
    final filter = _filter;
    final entryChanged = entry.id != _syncedEntryId;
    if (entryChanged || filter != _syncedFilter) {
      if (_filterCtrl.text != filter) {
        _filterCtrl.value = TextEditingValue(
          text: filter,
          selection: TextSelection.collapsed(offset: filter.length),
        );
      }
      if (entryChanged) {
        _showFilterBar = false;
        _yamlDirty = false;
      }
      if (filter.trim().isNotEmpty) _showFilterBar = true;
    }
    if (!forceYaml &&
        identical(document, _syncedDocument) &&
        !entryChanged &&
        filter == _syncedFilter) {
      if (!_samePath(_focusPath, _syncedFocus)) {
        _syncedFocus = _focusPath;
        if (_registered) _highlightSelection();
      }
      return;
    }
    _syncedDocument = document;
    _syncedEntryId = entry.id;
    _syncedFilter = filter;
    _syncedFocus = _focusPath;

    // Même projet temporaire que l'agent IA : l'objet et, comme cibles des
    // références, les autres entrées du domaine.
    final project = DomainModelAiAgent.modelProject(
      document,
      entry,
      domainId: widget.domainId,
      modelPreferences: widget.controller.modelPreferences,
    );
    final object = project.businessObjects.first;

    var nodes = const <Map<String, Object?>>[];
    String? error;
    // Sans attribut, le DSL écrirait un `id` fictif : l'arbre reste vide.
    if (object.attributes.isNotEmpty) {
      try {
        final root = SpecSchemaDslBridge.buildTreeNodes(project)
            .where((node) => node['objectId'] == object.id)
            .firstOrNull;
        nodes = BusinessObjectOperations.filterTreeNodes([
          if (root?['children'] case final List children)
            for (final child in children)
              if (child is Map<String, Object?>) child,
        ], filter);
      } on FormatException catch (e) {
        error = e.message;
      }
    }

    final targets = <String, BusinessObjectTreeSelectionTarget>{};
    void index(Map<String, Object?> node, String nodePath) {
      final relationId = (node['relationId'] as String?) ?? '';
      targets[nodePath] = BusinessObjectTreeSelectionTarget(
        nodePath: nodePath,
        objectId: object.id,
        relationId: relationId,
        attributePath: [
          if (node['attributePath'] case final List path)
            for (final id in path) '$id',
        ],
        isRootObject: false,
        isRelation: relationId.isNotEmpty,
        isArray: node['isArray'] == true,
        isRequired: node['isRequired'] == true,
        attrType: (node['attrType'] as String?) ?? '',
        totalAttributes: (node['totalAttributes'] as int?) ?? 0,
        estimatedMaxRows: node['estimatedMaxRows'] as int?,
        typeIcon: (node['typeIcon'] as String?) ?? 'value',
        displayType: (node['displayType'] as String?) ?? '',
      );
      if (node['children'] case final List children) {
        for (final (i, child) in children.indexed) {
          if (child is Map<String, Object?>) {
            index(child, '$nodePath.children[$i]');
          }
        }
      }
    }

    for (final (i, node) in nodes.indexed) {
      index(node, 'nodes[$i]');
    }
    _model = (project: project, object: object, targets: targets, error: error);

    if (!_yamlDirty || forceYaml || entryChanged) {
      _yamlText = SpecSchemaDslBridge.toSingleObjectYamlLight(project, object);
      _yamlErrorNotifier.value = '';
      _yamlDirty = false;
      _codeEditorConfig.repaintCode();
    }

    if (_registered) {
      unawaited(
        _store.replaceArray(_repo, 'nodes', nodes).then((_) {
          if (mounted) _highlightSelection();
        }),
      );
    } else {
      _store.registerRepository(
        RepositoryImpl(id: _repo, json: {'nodes': nodes}),
      );
      _registered = true;
    }
  }

  /// Reporte la sélection courante dans le store après un remplacement.
  void _highlightSelection() {
    final binding = _store.bindingOf(_repo).array('nodes');
    final nodePath = _selectedNodePath;
    if (nodePath == null) return binding.clear();
    final root = RegExp(r'^nodes\[(\d+)\]').firstMatch(nodePath);
    binding.select(
      const [],
      root == null ? 0 : int.parse(root.group(1)!),
      nodePath: nodePath,
    );
  }

  void _clearSelection() {
    _syncedFocus = const [];
    widget.controller.focusDomainModelAttribute(
      widget.domainId,
      widget.entry.id,
      const [],
    );
    _store.bindingOf(_repo).array('nodes').clear();
    setState(() {});
  }

  void _setFilter(String query) {
    if (query.isEmpty && _filterCtrl.text.isNotEmpty) _filterCtrl.clear();
    widget.controller.setDomainModelFilter(
      widget.domainId,
      widget.entry.id,
      query,
    );
  }

  Future<void> _save(BusinessObjectSpec next) async {
    try {
      next.validate();
      await widget.controller.updateDomainModelObject(widget.domainId, next);
    } on Object catch (e) {
      if (e is! FormatException && e is! StateError) rethrow;
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(e is FormatException ? e.message : '$e')),
      );
    }
  }

  Future<void> _editAttribute({
    List<String> parentPath = const <String>[],
    BusinessAttribute? existing,
  }) async {
    final attribute = await showBusinessAttributeEditorDialog(
      context,
      project: _model.project,
      existing: existing,
      isSubAttribute: parentPath.isNotEmpty,
    );
    if (attribute == null || !mounted) return;
    // Relu après le dialogue : l'IA a pu modifier l'objet entre-temps.
    await _save(
      BusinessObjectOperations.upsertAttributeAtPath(
        _model.object,
        parentAttrPath: parentPath,
        attribute: attribute,
      ),
    );
  }

  Future<void> _deleteAttribute(List<String> path) => _save(
    BusinessObjectOperations.deleteAttributeAtPath(_model.object, path),
  );

  Future<void> _applyYamlSource() async {
    try {
      final updated = SpecSchemaDslBridge.applySingleObjectYamlSource(
        _yamlText,
        current: _model.object,
        referenceTargets: widget.document.referenceTargetsOf(widget.entry),
      );
      _yamlErrorNotifier.value = '';
      setState(() {
        _yamlDirty = false;
      });
      await _save(updated);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Schéma YAML appliqué au modèle.'),
          ),
        );
      }
    } on FormatException catch (e) {
      _yamlErrorNotifier.value = e.message;
    } on Object catch (e) {
      _yamlErrorNotifier.value = '$e';
    }
  }

  Future<void> _editDescription() async {
    final input = TextEditingController(text: _model.object.description);
    final description = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Description de ${widget.entry.name}'),
        content: SizedBox(
          width: 480,
          child: TextField(
            key: const ValueKey('contract-model-description-field'),
            controller: input,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Rôle métier du modèle',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    input.dispose();
    if (description == null || !mounted) return;
    await _save(_model.object.copyWith(description: description));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final details =
        widget.document.details[widget.entry.id] ?? ContractDetails.defaults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme, colors, details),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: _SplitPane(
            fraction: _chatFraction,
            defaultFraction: _defaultChatFraction,
            onChanged: (value) => setState(() => _chatFraction = value),
            handleKey: const ValueKey('contract-chat-split-handle'),
            minLeading: 240,
            minTrailing: 420,
            collapsedRail: Container(
              key: const ValueKey('contract-chat-collapsed'),
              width: 38,
              color: colors.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                spacing: 8,
                children: [
                  IconButton(
                    key: const ValueKey('contract-chat-expand'),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Afficher le chat IA',
                    onPressed: () =>
                        setState(() => _chatFraction = _defaultChatFraction),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            leading: KeyedSubtree(
              key: const ValueKey('contract-chat-pane'),
              child: ContractModelChatPane(
                key: ValueKey('${widget.domainId}/${widget.entry.id}'),
                controller: widget.controller,
                domainId: widget.domainId,
                entryId: widget.entry.id,
                modelName: widget.entry.name,
                onCollapse: () => setState(() => _chatFraction = 0),
                pickAttachments: widget.pickAttachments,
                pasteAttachments: widget.pasteAttachments,
                hasClipboardMedia: widget.hasClipboardMedia,
                pasteClipboardMedia: widget.pasteClipboardMedia,
              ),
            ),
            trailing: DefaultTabController(
              length: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TabBar(
                    tabs: [
                      Tab(
                        key: ValueKey('contract-model-object-tab'),
                        text: 'Objet',
                      ),
                      Tab(
                        key: ValueKey('contract-model-repository-tab'),
                        text: 'Repository',
                      ),
                      Tab(
                        key: ValueKey('contract-model-dsl-tab'),
                        text: 'DSL',
                      ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _SplitPane(
                          fraction: _treeFraction,
                          defaultFraction: _defaultTreeFraction,
                          onChanged: (value) =>
                              setState(() => _treeFraction = value),
                          handleKey: const ValueKey(
                            'contract-detail-split-handle',
                          ),
                          minLeading: 220,
                          minTrailing: 260,
                          leading: _buildTree(theme, colors),
                          trailing: KeyedSubtree(
                            key: const ValueKey('contract-model-inspector'),
                            child: _buildInspector(),
                          ),
                        ),
                        _buildRepositoryTab(),
                        _buildYamlSourceTab(colors, theme),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    ColorScheme colors,
    ContractDetails details,
  ) {
    final entry = widget.entry;
    final domainLayerCount = widget.document
        .domainLayerFor(entry)
        .totalItemsCount;
    final showDomainLayerBtn =
        widget.onOpenDomainLayer != null &&
        HexagonalDomainLayerSpec.isEligibleType(entry.type);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 12,
            children: [
              Icon(Icons.data_object, size: 26, color: colors.primary),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name, style: theme.textTheme.titleLarge),
                    Text(
                      details.title.isEmpty ? 'Sans titre' : details.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (showDomainLayerBtn)
                FilledButton.tonalIcon(
                  key: const ValueKey('contract-open-domain-layer-btn'),
                  onPressed: widget.onOpenDomainLayer,
                  icon: const Icon(Icons.hexagon_outlined, size: 17),
                  label: Text(
                    domainLayerCount > 0
                        ? 'Couche Domain ($domainLayerCount)'
                        : 'Couche Domain',
                  ),
                ),
              Chip(
                label: Text(
                  entry.type,
                  style: const TextStyle(color: Colors.white),
                ),
                backgroundColor: contractTypeColor(entry.type),
                side: BorderSide.none,
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Rubrique : ${entry.parent?.name ?? ''}'),
              Text('Version : ${details.version}'),
              const SizedBox(width: 8),
              for (final stage in ContractStage.values)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    contractStageIcons[stage],
                    size: 16,
                    color: contractStatusColor(details.states[stage], colors),
                  ),
                  label: Text(
                    '${contractStageLabels[stage]} : '
                    '${contractStatusLabels[details.states[stage] ?? ContractStatus.pending]}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTree(ThemeData theme, ColorScheme colors) {
    final object = _model.object;
    final error = _model.error;
    final filtering = _showFilterBar || _filter.trim().isNotEmpty;
    final Widget body;
    if (error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Arbre indisponible : $error',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
        ),
      );
    } else if (object.attributes.isNotEmpty && _model.targets.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Text(
                'Aucun attribut ne correspond à « ${_filter.trim()} ».',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              TextButton.icon(
                onPressed: () => _setFilter(''),
                icon: const Icon(Icons.clear_rounded, size: 15),
                label: const Text('Effacer le filtre'),
              ),
            ],
          ),
        ),
      );
    } else if (object.attributes.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Aucun attribut : décrivez le modèle à l’assistant IA '
            'ou ajoutez-en un depuis l’inspecteur.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, bounds) => JsonRepositoryScope(
          store: _store,
          child: SuperTreeView(
            id: 'contract-model-tree',
            config: SuperTreeViewConfig(
              binding: const JsonTextBinding(
                repositoryId: _repo,
                path: 'nodes',
              ),
              rowHeight: 34,
              headerSize: ((bounds.maxWidth - 44) * 0.55).clamp(120.0, 260.0),
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
              final path =
                  _model.targets[nodePath]?.attributePath ?? const <String>[];
              // Déjà surligné par l'arbre : _sync ne doit pas le resélectionner.
              _syncedFocus = path;
              widget.controller.focusDomainModelAttribute(
                widget.domainId,
                widget.entry.id,
                path,
              );
              setState(() {});
            },
            header: Builder(
              builder: (cell) {
                final meta = _metaOf(cell);
                final visual = visualForBusinessObjectNode(
                  meta,
                  colors,
                  theme.brightness,
                );
                final strong =
                    meta?.isRelation == true ||
                    meta?.attrType == 'object' ||
                    meta?.isArray == true;
                return Row(
                  children: [
                    Icon(visual.icon, size: 15, color: visual.fgColor),
                    const SizedBox(width: 7),
                    Expanded(
                      child: SuperValue(
                        id: 'contract-tree-node-name',
                        config: SuperValueConfig(
                          mode: SuperValueMode.display,
                          color: colors.onSurface,
                          fontWeight: strong
                              ? FontWeight.w600
                              : FontWeight.w400,
                          binding: const JsonTextBinding(
                            repositoryId: _repo,
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
                );
              },
            ),
            data: Builder(
              builder: (cell) {
                final meta = _metaOf(cell);
                final visual = visualForBusinessObjectNode(
                  meta,
                  colors,
                  theme.brightness,
                );
                return SuperValue(
                  id: 'contract-tree-node-type',
                  config: SuperValueConfig(
                    mode: SuperValueMode.display,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: visual.fgColor,
                    binding: const JsonTextBinding(
                      repositoryId: _repo,
                      path: 'nodes[?].displayType',
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    return Container(
      key: const ValueKey('contract-model-tree-pane'),
      color: colors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 18,
                  color: colors.primary,
                ),
                Expanded(
                  child: Text(
                    'Attributs (${object.totalAttributeCount})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('contract-model-filter-toggle'),
                  tooltip: 'Filtrer les attributs',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: filtering ? colors.primary : colors.onSurfaceVariant,
                  onPressed: () => setState(() {
                    if (_showFilterBar && _filter.trim().isNotEmpty) {
                      _setFilter('');
                      _showFilterBar = false;
                    } else {
                      _showFilterBar = !_showFilterBar;
                    }
                  }),
                  icon: Icon(
                    filtering ? Icons.filter_alt_rounded : Icons.search_rounded,
                  ),
                ),
              ],
            ),
          ),
          if (filtering)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: TextField(
                key: const ValueKey('contract-model-filter-field'),
                controller: _filterCtrl,
                onChanged: _setFilter,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  suffixIcon: _filter.isNotEmpty
                      ? IconButton(
                          key: const ValueKey('contract-model-filter-clear'),
                          tooltip: 'Effacer le filtre',
                          iconSize: 16,
                          onPressed: () => _setFilter(''),
                          icon: const Icon(Icons.close_rounded),
                        )
                      : null,
                  hintText: 'Filtrer nom ou type d’attribut…',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          const Divider(height: 1, thickness: 1),
          Expanded(child: body),
        ],
      ),
    );
  }

  BusinessObjectTreeSelectionTarget? _metaOf(BuildContext cell) {
    final nodePath = JsonListScope.maybeOf(cell)?.nodePath;
    return nodePath == null ? null : _model.targets[nodePath];
  }

  Widget _buildInspector() {
    final object = _model.object;
    final path = _focusPath;
    final attribute = path.isEmpty
        ? null
        : BusinessObjectOperations.findAttributeByPath(object.attributes, path);
    if (attribute != null) {
      return AttributeInspectorPane(
        project: _model.project,
        object: object,
        attribute: attribute,
        attributePath: path,
        onBackToObject: _clearSelection,
        onEditAttribute: () => _editAttribute(
          parentPath: path.sublist(0, path.length - 1),
          existing: attribute,
        ),
        onAddChildAttribute: attribute.type == BusinessAttributeType.object
            ? () => _editAttribute(parentPath: path)
            : null,
        onDeleteAttribute: () => _deleteAttribute(path),
        onExtractToSeparateObject: null,
      );
    }
    return _ModelInspector(
      project: _model.project,
      object: object,
      onEditDescription: _editDescription,
      onAddAttribute: _editAttribute,
      onEditAttribute: (attribute) => _editAttribute(existing: attribute),
      onDeleteAttribute: (attribute) => _deleteAttribute([attribute.id]),
    );
  }

  SpecForgeProject _domainResolutionProject() {
    final document = widget.document;
    final entry = widget.entry;
    final others = <BusinessObjectSpec>[
      for (final MapEntry(key: id, value: technicalName)
          in document.referenceTargetsOf(entry).entries)
        if (document.entryById(id) case final otherEntry?)
          document.objectFor(otherEntry).copyWith(technicalName: technicalName),
    ];
    return _model.project.copyWith(
      businessObjects: <BusinessObjectSpec>[_model.object, ...others],
      businessObjectModelPreferences: widget.controller.modelPreferences,
    );
  }

  Widget _buildRepositoryTab() {
    final object = _model.object;
    final resolutionProject = _domainResolutionProject();
    final preview = SpecSuperDesignerExporter.buildRepositoryPreview(
      resolutionProject,
      object,
      modelPreferencesOverride: widget.controller.modelPreferences,
    );
    final yamlLight = SpecSchemaDslBridge.toSingleObjectYamlLight(
      resolutionProject,
      object,
    );
    final bundle = SuperDesignerExportBundle(
      yamlLightSchema: yamlLight,
      repositoriesJsonSchemas: Map<String, Map<String, Object?>>.unmodifiable(
        <String, Map<String, Object?>>{preview.alias: preview.schema},
      ),
      repositoriesSeedData: Map<String, Map<String, Object?>>.unmodifiable(
        <String, Map<String, Object?>>{preview.alias: preview.seed},
      ),
    );
    final safeDomain = _safeFileSlug(widget.domainId);
    final safeTech = _safeFileSlug(object.technicalName);
    return SpecJsonSchemaViewerView(
      key: const ValueKey('contract-model-schema-viewer'),
      bundle: bundle,
      title: 'JSON Schema & Seed — ${object.name}',
      filenameStem: '${safeDomain}_${safeTech}_repository_schema',
      exportDirectory: Directory(
        '${widget.controller.store.rootDirectory.path}${Platform.pathSeparator}exports${Platform.pathSeparator}domains${Platform.pathSeparator}$safeDomain',
      ),
      openInBrowser: widget.schemaBrowserLauncher,
      htmlSurfaceBuilder: widget.schemaViewerSurfaceBuilder,
      showTitle: false,
    );
  }

  Widget _buildYamlSourceTab(ColorScheme colors, ThemeData theme) {
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
                    key: const ValueKey('contract-model-reset-yaml'),
                    onPressed: () {
                      _yamlDirty = false;
                      _yamlText = SpecSchemaDslBridge.toSingleObjectYamlLight(
                        _model.project,
                        _model.object,
                      );
                      _yamlErrorNotifier.value = '';
                      _codeEditorConfig.repaintCode();
                      setState(() {});
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Réinitialiser'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('contract-model-apply-yaml'),
                    onPressed: _applyYamlSource,
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
                  key: const ValueKey('contract-model-yaml-editor'),
                  config: _codeEditorConfig,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _safeFileSlug(String raw) {
    final s = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'model' : s;
  }
}

/// Inspecteur de l'objet d'un modèle : description, jauge, aperçu JSON Schema
/// et attributs racine.
class _ModelInspector extends StatelessWidget {
  const _ModelInspector({
    required this.project,
    required this.object,
    required this.onEditDescription,
    required this.onAddAttribute,
    required this.onEditAttribute,
    required this.onDeleteAttribute,
  });

  final SpecForgeProject project;
  final BusinessObjectSpec object;
  final VoidCallback onEditDescription;
  final VoidCallback onAddAttribute;
  final ValueChanged<BusinessAttribute> onEditAttribute;
  final ValueChanged<BusinessAttribute> onDeleteAttribute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = object.totalAttributeCount;
    const max = BusinessObjectSpec.maxAttributesPerObject;
    final gaugeColor = total > max
        ? colors.error
        : (total >= 160 ? colors.tertiary : colors.primary);
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
                  Text(
                    object.description.isEmpty
                        ? 'Aucune description'
                        : object.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Modifier la description',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditDescription,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: (total / max).clamp(0.0, 1.0),
                color: gaugeColor,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Text(
              '$total / $max attributs',
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
          badges: ['$total/$max attributs'],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Attributs racine (${object.attributes.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('contract-model-add-attr'),
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
          ),
        for (final attribute in object.attributes)
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
                    attribute.required ? '${attribute.name} *' : attribute.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Chip(
                    label: Text(
                      attribute.isArray
                          ? '${attribute.type.dslKeyword}[]'
                          : attribute.type.dslKeyword,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              subtitle: attribute.description.isEmpty
                  ? null
                  : Text(attribute.description),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Modifier ${attribute.name}',
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    onPressed: () => onEditAttribute(attribute),
                  ),
                  IconButton(
                    tooltip: 'Supprimer ${attribute.name}',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => onDeleteAttribute(attribute),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Deux panneaux séparés par une [SpecSplitHandle] déplaçable.
///
/// Avec [collapsedRail], glisser la poignée sous 140 px replie le panneau de
/// gauche (fraction 0) et la tirer au-delà de 60 px le rouvre ; un
/// double-clic rétablit [defaultFraction].
class _SplitPane extends StatefulWidget {
  const _SplitPane({
    required this.fraction,
    required this.defaultFraction,
    required this.onChanged,
    required this.handleKey,
    required this.minLeading,
    required this.minTrailing,
    required this.leading,
    required this.trailing,
    this.collapsedRail,
  });

  final double fraction;
  final double defaultFraction;
  final ValueChanged<double> onChanged;
  final Key handleKey;
  final double minLeading;
  final double minTrailing;
  final Widget leading;
  final Widget trailing;
  final Widget? collapsedRail;

  @override
  State<_SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<_SplitPane> {
  final _rowKey = GlobalKey();
  double _dragOffset = SpecSplitHandle.width / 2;

  double? _localX(Offset global) {
    final box = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global).dx;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, bounds) {
        final available = math.max(
          0.0,
          bounds.maxWidth - SpecSplitHandle.width,
        );
        final roomy = available > widget.minLeading + widget.minTrailing;
        final minFraction = roomy ? widget.minLeading / available : 0.20;
        final maxFraction = roomy
            ? (available - widget.minTrailing) / available
            : 0.72;
        final rail = widget.collapsedRail;
        final collapsed = rail != null && widget.fraction <= 0;
        final leadingWidth = collapsed
            ? 0.0
            : available * widget.fraction.clamp(minFraction, maxFraction);
        return Row(
          key: _rowKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (collapsed)
              rail
            else
              SizedBox(width: leadingWidth, child: widget.leading),
            SpecSplitHandle(
              key: widget.handleKey,
              onDoubleTap: () => widget.onChanged(widget.defaultFraction),
              onHorizontalDragDown: (details) {
                final x = _localX(details.globalPosition);
                _dragOffset = x == null || collapsed
                    ? SpecSplitHandle.width / 2
                    : (x - leadingWidth).clamp(0.0, SpecSplitHandle.width);
              },
              onHorizontalDragUpdate: (details) {
                final x = _localX(details.globalPosition);
                if (x == null || available <= 0) return;
                final next = x - _dragOffset;
                final fraction = (next / available).clamp(
                  minFraction,
                  maxFraction,
                );
                if (rail == null) return widget.onChanged(fraction);
                if (collapsed) {
                  if (next > 60) widget.onChanged(fraction);
                } else {
                  widget.onChanged(next < 140 ? 0.0 : fraction);
                }
              },
            ),
            Expanded(child: widget.trailing),
          ],
        );
      },
    );
  }
}
