/// Arbre hiérarchique (`SuperTreeView`) à 2 zones éditables (`Header` et `Data`)
/// lié à un repository JSON.
///
/// ## Fonctionnement
///
/// * **Deux zones par ligne** :
///   - `Header` (`SuperTreeViewConfig.headerZone`) : colonne d'en-tête à gauche,
///     indentée selon la profondeur du nœud et redimensionnable à la souris ;
///   - `Data` (`SuperTreeViewConfig.dataZone`) : colonne de données à droite,
///     occupant l'espace restant.
/// * **Liaison Repository (`JsonTextBinding`)** :
///   Lit un tableau (ou un objet) JSON de nœuds récursifs où chaque nœud peut
///   contenir une liste d'enfants sous la clé [SuperTreeViewConfig.childrenKey]
///   (par défaut `'children'`).
/// * **Résolution automatique par nœud (`JsonListScope`)** :
///   Chaque ligne enveloppe ses zones `Header` et `Data` dans un [JsonListScope]
///   portant le chemin concret du nœud (`nodes[0]`, `nodes[0].children[1]`, etc.).
///   Un `SuperValue` placé dans `Header` ou `Data` avec le repository hérité et
///   un chemin relatif (`key`, `data`) ou modèle (`nodes[?].key`) lit et modifie
///   directement l'attribut du nœud courant.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:material_ui/material_ui.dart';

import '../../models/json_text_binding.dart';
import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/super_tree_view_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../super_app.dart';
import '../../theme/appearance.dart';
import '../../theme/container_fill.dart';
import '../../theme/container_style.dart';
import '../editing/components/native_component_editor.dart';
import '../editing/components/super_tree_view_editor.dart';
import '../editing/history/editor_history.dart';
import '../surfaces/super_container.dart';
import 'super_layout/iterable_content.dart';
import 'super_layout/slot_implementation.dart';
import 'internal_widget/treeview/tree_view.dart';

/// Données associées à un nœud affiché dans un [SuperTreeView].
@immutable
class SuperTreeNodeItem {
  const SuperTreeNodeItem({
    required this.nodePath,
    required this.rootIndex,
    this.attributes = const {},
    this.isTemplate = false,
    this.isFirstRow = false,
    this.revision = 0,
  });

  /// Chemin JSON concret du nœud dans le repository (ex: `nodes[0].children[1]`).
  final String nodePath;

  /// Indice du nœud racine auquel appartient ce nœud.
  final int rootIndex;

  /// Attributs JSON bruts du nœud.
  final Map<String, Object?> attributes;

  /// Vrai lorsqu'il s'agit d'une ligne de gabarit (arbre vide ou non lié en édition).
  final bool isTemplate;

  /// Vrai pour la toute première ligne de l'arbre, qui porte les régions
  /// interactives du designer (`NativeComponentEditorState.region`).
  final bool isFirstRow;

  /// Compteur de révision permettant d'invalider le cache de ligne de [TreeView].
  final int revision;

  SuperTreeNodeItem withRevision(int nextRevision) => SuperTreeNodeItem(
    nodePath: nodePath,
    rootIndex: rootIndex,
    attributes: attributes,
    isTemplate: isTemplate,
    isFirstRow: isFirstRow,
    revision: nextRevision,
  );
}

@immutable
class _TreeSource {
  const _TreeSource({
    this.binding,
    this.error,
    this.unselected = false,
    this.parents = const [],
    this.rowBase = const [],
    this.arrays = const [],
  });

  final JsonTextBinding? binding;
  final String? error;
  final bool unselected;
  final List<int> parents;
  final List<int> rowBase;
  final List<JsonArrayBinding> arrays;

  @override
  bool operator ==(Object other) =>
      other is _TreeSource &&
      other.binding == binding &&
      other.error == error &&
      other.unselected == unselected &&
      listEquals(other.parents, parents) &&
      listEquals(other.rowBase, rowBase) &&
      listEquals(other.arrays, arrays);

  @override
  int get hashCode => Object.hash(
    binding,
    error,
    unselected,
    Object.hashAll(parents),
    Object.hashAll(rowBase),
    Object.hashAll(arrays),
  );
}

/// Composant `SuperTreeView` avec 2 zones (`Header` et `Data`) lié à un repository.
class SuperTreeView extends StatefulWidget {
  const SuperTreeView({
    this.id = 'root-tree-view',
    this.itemId,
    this.label = 'TreeView',
    this.header,
    this.headers = const [],
    this.data,
    this.datas = const [],
    this.slots = const [],
    this.config,
    this.templateStyle = const ContainerStyle(),
    this.onNodeSelected,
    this.onConfigChanged,
    super.key,
  });

  final String id;

  /// ID technique distinct pour l'[IterableContent] des lignes.
  /// Si non spécifié, utilise [SuperTreeViewConfig.itemId] ou [id].
  final String? itemId;

  final String label;

  /// Raccourci pour un widget dans la zone `Header`.
  final Widget? header;
  final List<Widget> headers;

  /// Raccourci pour un widget dans la zone `Data`.
  final Widget? data;
  final List<Widget> datas;

  /// Catalogue additionnel de slots disponibles dans les zones `Header` et `Data`.
  final List<SlotImplementation> slots;

  /// Configuration initiale avant celle enregistrée dans l'apparence.
  final SuperTreeViewConfig? config;

  /// Style initial partagé par les lignes (`IterableContent`), avant celui
  /// enregistré dans l'apparence.
  final ContainerStyle templateStyle;

  /// Appelé avec le `nodePath` lorsqu'un nœud est sélectionné.
  final ValueChanged<String>? onNodeSelected;

  /// Appelé lorsque la configuration est modifiée.
  final ValueChanged<SuperTreeViewConfig>? onConfigChanged;

  SuperTreeViewConfig get _initialConfig {
    if (config != null) {
      return itemId != null && config!.itemId == null
          ? config!.copyWith(itemId: itemId)
          : config!;
    }
    final headerIds = <String>[
      if (header != null) 'header',
      for (var i = 0; i < headers.length; i++) 'header:$i',
    ];
    final dataIds = <String>[
      if (data != null) 'data',
      for (var i = 0; i < datas.length; i++) 'data:$i',
    ];
    return SuperTreeViewConfig(
      itemId: itemId,
      placements: {
        if (headerIds.isNotEmpty) SuperTreeViewConfig.headerZone: headerIds,
        if (dataIds.isNotEmpty) SuperTreeViewConfig.dataZone: dataIds,
      },
    );
  }

  @override
  State<SuperTreeView> createState() => _SuperTreeViewState();
}

class _SuperTreeViewState extends State<SuperTreeView> {
  late final ValueNotifier<SuperTreeViewConfig> _localConfig = ValueNotifier(
    widget._initialConfig,
  );
  late final ValueNotifier<ContainerStyle> _localStyle = ValueNotifier(
    widget.templateStyle,
  );

  JsonRepositoryStore? _store;
  _TreeSource? _source;
  String? _configPath;
  JsonArrayBinding? _selection;
  List<JsonArrayBinding> _listened = const [];
  List<Object?>? _rawNodes;
  bool _singleRootObject = false;
  String? _error;
  bool _loading = false;
  int _generation = 0;
  int _renderRevision = 0;

  String? _selectedNodePath;
  final Map<String, bool> _expandedByPath = {};
  final Map<String, TreeNodeData<SuperTreeNodeItem>> _nodeByPath = {};
  List<TreeNodeData<SuperTreeNodeItem>> _cachedTreeNodes = const [];
  Object? _cachedTreeSign;

  static const List<NativeRegion> _regions = [
    NativeRegion(
      SuperTreeViewConfig.headerZone,
      'Header',
      required: true,
      axis: Axis.horizontal,
      expand: true,
      stretch: true,
      editableFlow: true,
      emptySize: Size(double.infinity, 28),
    ),
    NativeRegion(
      SuperTreeViewConfig.dataZone,
      'Data',
      required: true,
      axis: Axis.horizontal,
      expand: true,
      stretch: true,
      editableFlow: true,
      emptySize: Size(double.infinity, 28),
    ),
  ];

  @override
  void didUpdateWidget(SuperTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.config != widget.config) {
      _localConfig.value = widget._initialConfig;
      _renderRevision++;
    }
    if (oldWidget.id != widget.id ||
        oldWidget.templateStyle != widget.templateStyle) {
      _localStyle.value = widget.templateStyle;
      _renderRevision++;
    }
  }

  @override
  void dispose() {
    _generation++;
    _store?.removeListener(_reload);
    _listen(const []);
    _localConfig.dispose();
    _localStyle.dispose();
    super.dispose();
  }

  List<SlotImplementation> get _slots => [
    if (widget.header case final child?)
      BuilderSlot(id: 'header', label: 'Header', builder: (_) => child),
    for (final (index, child) in widget.headers.indexed)
      BuilderSlot(
        id: 'header:$index',
        label: 'Header ${index + 1}',
        builder: (_) => child,
      ),
    if (widget.data case final child?)
      BuilderSlot(id: 'data', label: 'Data', builder: (_) => child),
    for (final (index, child) in widget.datas.indexed)
      BuilderSlot(
        id: 'data:$index',
        label: 'Data ${index + 1}',
        builder: (_) => child,
      ),
    ...widget.slots,
  ];

  String? get _templatePath {
    final path = _configPath;
    return path == null ? null : JsonAttributePath(path).toString();
  }

  void _listen(List<JsonArrayBinding> arrays) {
    for (final array in _listened) {
      array.removeListener(_selectionChanged);
    }
    _listened = arrays;
    for (final array in arrays) {
      array.addListener(_selectionChanged);
    }
  }

  void _invalidateSelectedNodes(String? previousPath, String? nextPath) {
    void bump(String? path) {
      if (path == null) return;
      final node = _nodeByPath[path];
      if (node != null) {
        node.data = node.data.withRevision(node.data.revision + 1);
      }
    }

    if (previousPath != nextPath) {
      bump(previousPath);
      bump(nextPath);
    }
  }

  void _selectionChanged() {
    if (!mounted) return;
    final source = _source;
    if (source != null && _selection != null) {
      final path = _selection!.nodePathFor(source.parents);
      if (path != _selectedNodePath) {
        final previous = _selectedNodePath;
        setState(() {
          _selectedNodePath = path;
          _invalidateSelectedNodes(previous, path);
        });
      }
    }
  }

  _TreeSource _resolve(
    SuperTreeViewConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final binding = config.binding;
    if (binding == null) return const _TreeSource();
    try {
      final resolved = JsonListScope.resolveSelected(binding, scope, store);
      final scoped = scope?.indices ?? const <int>[];
      return _TreeSource(
        binding: resolved.binding,
        unselected: resolved.binding == null,
        parents: resolved.indices,
        rowBase: resolved.indices.length > scoped.length
            ? resolved.indices
            : scoped,
        arrays: resolved.arrays,
      );
    } on FormatException catch (error) {
      return _TreeSource(error: error.message);
    }
  }

  void _observe(
    SuperTreeViewConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    _configPath = config.binding?.path;
    if (scope?.placeholder ?? false) return;
    final source = _resolve(config, scope, store);
    if (_source == source && identical(_store, store)) return;
    if (_source != source) {
      _rawNodes = null;
      _error = null;
    }
    _source = source;
    if (!identical(_store, store)) {
      _store?.removeListener(_reload);
      _store = store?..addListener(_reload);
    }
    final binding = source.binding;
    final template = _templatePath;
    _selection = binding == null || store == null || template == null
        ? null
        : store.bindingOf(binding.repositoryId!).array(template);
    _listen([?_selection, ...source.arrays]);
    if (binding != null && store != null) {
      final cached = store.peekTreeNodes(binding.repositoryId!, binding.path);
      if (cached != null) {
        _rawNodes = cached.nodes;
        _singleRootObject = cached.singleRootObject;
        _error = null;
        _loading = false;
        _renderRevision++;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final binding = _source?.binding;
    final store = _store;
    if (binding == null || store == null) {
      setState(() {
        _rawNodes = null;
        _singleRootObject = false;
        _loading = false;
        _error =
            _source?.error ??
            (store == null && _source?.unselected == true
                ? 'Service de repositories indisponible.'
                : null);
        _renderRevision++;
      });
      return;
    }
    if (_rawNodes == null) {
      setState(() => _loading = true);
    }
    try {
      final loaded = await store.readTreeNodes(
        binding.repositoryId!,
        binding.path,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _rawNodes = loaded.nodes;
        _singleRootObject = loaded.singleRootObject;
        _error = null;
        _renderRevision++;
      });
    } on FormatException catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.message;
          _renderRevision++;
        });
      }
    } on FileSystemException {
      if (mounted && generation == _generation) {
        setState(() {
          _error = 'Impossible de lire le repository lié.';
          _renderRevision++;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  bool _isNodeSelected(SuperTreeNodeItem item) {
    if (item.isTemplate) return false;
    if (_selectedNodePath != null) {
      return _selectedNodePath == item.nodePath;
    }
    final source = _source;
    if (source == null || _selection == null) return false;
    final storePath = _selection!.nodePathFor(source.parents);
    if (storePath != null) return storePath == item.nodePath;
    return false;
  }

  void _selectNode(SuperTreeNodeItem item) {
    if (item.isTemplate) return;
    if (_selectedNodePath != item.nodePath) {
      final previous = _selectedNodePath;
      setState(() {
        _selectedNodePath = item.nodePath;
        _invalidateSelectedNodes(previous, item.nodePath);
      });
    }
    final source = _source;
    if (source != null) {
      _selection?.select(
        source.parents,
        item.rootIndex,
        nodePath: item.nodePath,
      );
    }
    widget.onNodeSelected?.call(item.nodePath);
  }

  TreeNodeData<SuperTreeNodeItem> _obtainNode({
    required String nodePath,
    required int rootIndex,
    required Map<String, Object?> attributes,
    required bool isTemplate,
    required bool isFirstRow,
    required bool isExpanded,
    required List<TreeNodeData<SuperTreeNodeItem>> children,
  }) {
    final existing = _nodeByPath[nodePath];
    if (existing != null) {
      existing.isExpanded = isExpanded;
      existing.children = children;
      existing.data = SuperTreeNodeItem(
        nodePath: nodePath,
        rootIndex: rootIndex,
        attributes: attributes,
        isTemplate: isTemplate,
        isFirstRow: isFirstRow,
        revision: existing.data.revision + 1,
      );
      return existing;
    }
    final created = TreeNodeData<SuperTreeNodeItem>(
      isExpanded: isExpanded,
      data: SuperTreeNodeItem(
        nodePath: nodePath,
        rootIndex: rootIndex,
        attributes: attributes,
        isTemplate: isTemplate,
        isFirstRow: isFirstRow,
        revision: 1,
      ),
      children: children,
    );
    _nodeByPath[nodePath] = created;
    return created;
  }

  List<TreeNodeData<SuperTreeNodeItem>> _ensureTreeNodes(
    SuperTreeViewConfig config, {
    required bool templateMode,
    required bool editing,
  }) {
    final sign = (
      _renderRevision,
      templateMode,
      editing,
      config,
      _source?.binding,
      _singleRootObject,
    );
    if (_cachedTreeSign == sign) {
      return _cachedTreeNodes;
    }
    _cachedTreeSign = sign;

    final activePaths = <String>{};

    if (templateMode) {
      final childPath = 'template[0].${config.childrenKey}[0]';
      activePaths
        ..add('template[0]')
        ..add(childPath);
      final childNode = _obtainNode(
        nodePath: childPath,
        rootIndex: 0,
        attributes: const {},
        isTemplate: true,
        isFirstRow: false,
        isExpanded: true,
        children: const [],
      );
      final rootNode = _obtainNode(
        nodePath: 'template[0]',
        rootIndex: 0,
        attributes: const {},
        isTemplate: true,
        isFirstRow: true,
        isExpanded: true,
        children: [childNode],
      );
      _nodeByPath.removeWhere((path, _) => !activePaths.contains(path));
      _cachedTreeNodes = [rootNode];
      return _cachedTreeNodes;
    }

    final rawList = _rawNodes;
    final basePath = _source?.binding?.path;
    if (rawList == null || rawList.isEmpty || basePath == null) {
      _nodeByPath.clear();
      _cachedTreeNodes = const [];
      return _cachedTreeNodes;
    }

    var firstRowAssigned = false;

    TreeNodeData<SuperTreeNodeItem> buildNode(
      Object? rawNode,
      String currentPath,
      int rootIndex,
    ) {
      activePaths.add(currentPath);
      final isFirst = !firstRowAssigned;
      firstRowAssigned = true;

      final map = rawNode is Map
          ? <String, Object?>{
              for (final entry in rawNode.entries)
                entry.key.toString(): entry.value,
            }
          : const <String, Object?>{};

      final rawChildren = map[config.childrenKey];
      final childNodes = <TreeNodeData<SuperTreeNodeItem>>[];
      if (rawChildren is List) {
        for (var i = 0; i < rawChildren.length; i++) {
          final childPath = '$currentPath.${config.childrenKey}[$i]';
          childNodes.add(buildNode(rawChildren[i], childPath, rootIndex));
        }
      }

      final expanded = _expandedByPath[currentPath] ?? config.initiallyExpanded;

      return _obtainNode(
        nodePath: currentPath,
        rootIndex: rootIndex,
        attributes: map,
        isTemplate: false,
        isFirstRow: isFirst,
        isExpanded: expanded,
        children: childNodes,
      );
    }

    final result = <TreeNodeData<SuperTreeNodeItem>>[];
    for (var i = 0; i < rawList.length; i++) {
      final path = _singleRootObject ? basePath : '$basePath[$i]';
      result.add(buildNode(rawList[i], path, i));
    }
    _nodeByPath.removeWhere((path, _) => !activePaths.contains(path));
    _cachedTreeNodes = result;
    return _cachedTreeNodes;
  }

  NativeComponentConfig _toNativeConfig(SuperTreeViewConfig config) {
    final activeRegionIds = {
      SuperTreeViewConfig.headerZone,
      SuperTreeViewConfig.dataZone,
    };
    final activePlacements = <String, List<String>>{
      for (final entry in config.placements.entries)
        if (activeRegionIds.contains(entry.key)) entry.key: entry.value,
    };
    final activeSlotIds = activePlacements.values.expand((ids) => ids).toSet();
    return NativeComponentConfig(
      regions: {for (final id in activeRegionIds) id: true},
      placements: activePlacements,
      slotTypes: {
        for (final entry in config.slotTypes.entries)
          if (activeSlotIds.contains(entry.key)) entry.key: entry.value,
      },
      regionAxes: {
        for (final entry in config.zoneAxes.entries)
          if (activeRegionIds.contains(entry.key)) entry.key: entry.value,
      },
      regionFlows: {
        for (final entry in config.zoneFlows.entries)
          if (activeRegionIds.contains(entry.key)) entry.key: entry.value,
      },
      slotPreferredSizes: {
        for (final entry in config.slotPreferredSizes.entries)
          if (activeSlotIds.contains(entry.key)) entry.key: entry.value,
      },
      slotSizeConstraints: {
        for (final entry in config.slotSizeConstraints.entries)
          if (activeSlotIds.contains(entry.key)) entry.key: entry.value,
      },
      slotLabels: {
        for (final entry in config.slotLabels.entries)
          if (activeSlotIds.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  SuperTreeViewConfig _fromNativeConfig(
    SuperTreeViewConfig current,
    NativeComponentConfig native,
  ) {
    return current.copyWith(
      placements: native.placements,
      slotTypes: native.slotTypes,
      zoneAxes: native.regionAxes,
      zoneFlows: native.regionFlows,
      slotPreferredSizes: native.slotPreferredSizes,
      slotSizeConstraints: native.slotSizeConstraints,
      slotLabels: native.slotLabels,
    );
  }

  Future<void> _handleSlotRemoved(
    ValueNotifier<SuperTreeViewConfig> controller,
    Registry? registry,
    String region,
    SlotImplementation slot,
  ) async {
    final current = controller.value;
    final removedIds = current.slotsRemovedWith(slot.id);
    final removedTypes = {
      for (final id in removedIds) id: current.slotTypeOf(id),
    };
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      controller.value = current.withoutSlot(slot.id);
      if (registry != null) {
        for (final entry in removedTypes.entries) {
          registry.purgeInstance(
            entry.key,
            entry.value,
            EditorConfigKind.treeView,
          );
        }
      }
    } finally {
      history?.commitTransaction();
    }
  }

  Future<void> _openSettings(
    ValueNotifier<SuperTreeViewConfig> controller,
  ) async {
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    SuperTreeViewConfig? result;
    try {
      result = await showSuperTreeViewEditor(
        context: context,
        config: controller.value,
      );
      if (result != null && mounted && result != controller.value) {
        controller.value = result;
        _renderRevision++;
        widget.onConfigChanged?.call(result);
      }
    } finally {
      if (result != null) {
        history?.commitTransaction();
      } else {
        history?.cancelTransaction();
      }
    }
  }

  Widget _buildZoneContent(
    BuildContext context,
    NativeComponentEditorState editor,
    SuperTreeViewConfig config,
    SuperTreeNodeItem item,
    String zoneId,
  ) {
    final Widget content;
    if (item.isFirstRow) {
      content = editor.region(zoneId, expand: true, stretch: true);
    } else {
      final slots = editor.slotsFor(zoneId);
      if (slots.isEmpty) {
        return const SizedBox.shrink();
      }
      final axis = editor.axisOf(zoneId);
      final flow = editor.flowOf(zoneId);
      content = SlotStack(
        slots: slots,
        axis: axis,
        flow: flow,
        expand: true,
        stretch: true,
        preferredSizes: {
          for (final slot in slots)
            if (slot case NativePreferredSizeWidget native)
              slot.id: native.preferredSizeIn(context),
          ...config.slotPreferredSizes,
        },
        sizeConstraints: config.slotSizeConstraints,
      );
    }
    return SlotContentFitScope(
      fitWidth: false,
      fitHeight: false,
      child: content,
    );
  }

  Widget _buildRowWrapper(
    BuildContext context,
    ValueNotifier<ContainerStyle> style,
    String rowId,
    JsonListScope? parentScope,
    TreeNodeData<SuperTreeNodeItem> node,
    Widget rowContent, {
    required bool animateSelectionAndHover,
  }) {
    final item = node.data;
    final selected = _isNodeSelected(item);
    final placeholder = item.isTemplate || (parentScope?.placeholder ?? false);
    final iterableRow = ValueListenableBuilder<ContainerStyle>(
      valueListenable: style,
      builder: (context, rowStyle, _) => IterableContent(
        id: rowId,
        label: 'Iterable Content',
        style: rowStyle,
        resolveSelectionAndHover: !animateSelectionAndHover,
        onStyleChanged: (next) => style.value = next,
        child: rowContent,
      ),
    );
    final interactive = placeholder
        ? iterableRow
        : Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (event.buttons == kPrimaryButton) {
                _selectNode(item);
              }
            },
            child: iterableRow,
          );
    return JsonListScope(
      key: ValueKey('super-tree-row-${widget.id}-${item.nodePath}'),
      selected: selected,
      repositoryId: _source?.binding?.repositoryId ?? parentScope?.repositoryId,
      indices: [...?(_source?.rowBase ?? parentScope?.indices), item.rootIndex],
      nodePath: item.isTemplate ? null : item.nodePath,
      treeTemplatePath: _templatePath,
      placeholder: placeholder,
      child: interactive,
    );
  }

  Widget _buildSelectionIndicator(
    BuildContext context,
    ContainerStyle currentRowStyle,
  ) {
    final defaultColor = Theme.of(
      context,
    ).colorScheme.primary.withValues(alpha: 0.14);
    final hasCustomSelected = currentRowStyle.states?.hasSelected == true;
    final resolved = hasCustomSelected
        ? currentRowStyle.states!.resolve(currentRowStyle, isSelected: true)
        : currentRowStyle.copyWith(clearStates: true);
    final hasFill =
        resolved.fill.type != FillType.solid || resolved.hasImage;
    final effectiveStyle = resolved.copyWith(
      clearStates: true,
      margin: 0,
      marginInsets: null,
      hoverEffect: false,
      color: hasCustomSelected
          ? (resolved.color ?? (hasFill ? null : defaultColor))
          : defaultColor,
    );
    return Padding(
      padding: resolved.outerMargin,
      child: SuperContainer(
        key: ValueKey('super-tree-selection-indicator-${widget.id}'),
        style: effectiveStyle,
        fallbackColor: Colors.transparent,
        borderColor: Colors.transparent,
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildHoverIndicator(
    BuildContext context,
    ContainerStyle currentRowStyle,
  ) {
    final accent = AppearanceScope.of(context).accent;
    final hoverBase = currentRowStyle.hoverBase(accent);
    final defaultColor = (hoverBase ?? Theme.of(context).colorScheme.onSurface)
        .withValues(alpha: 0.08);
    final hasCustomHover = currentRowStyle.states?.hover?.isEmpty == false;
    final resolved = hasCustomHover
        ? currentRowStyle.states!.resolve(currentRowStyle, isHovered: true)
        : currentRowStyle.copyWith(clearStates: true);
    final hasFill =
        resolved.fill.type != FillType.solid || resolved.hasImage;
    final effectiveStyle = resolved.copyWith(
      clearStates: true,
      margin: 0,
      marginInsets: null,
      hoverEffect: false,
      color: hasCustomHover
          ? (resolved.color ?? (hasFill ? null : defaultColor))
          : defaultColor,
    );
    return Padding(
      padding: resolved.outerMargin,
      child: SuperContainer(
        key: ValueKey('super-tree-hover-indicator-${widget.id}'),
        style: effectiveStyle,
        fallbackColor: Colors.transparent,
        borderColor: Colors.transparent,
        child: const SizedBox.expand(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = SuperApp.maybeOf(context);
    final registry = app?.registry;
    final controller =
        registry?.treeViewController(
          widget.id,
          fallback: widget._initialConfig,
        ) ??
        _localConfig;
    final listScope = JsonListScope.maybeOf(context);
    final repositoryStore = JsonRepositoryScope.maybeOf(context);

    return ValueListenableBuilder<SuperTreeViewConfig>(
      valueListenable: controller,
      builder: (context, config, _) {
        final rowId = widget.itemId ?? config.itemId ?? widget.id;
        final rowStyleFallback = app == null
            ? widget.templateStyle
            : (app.registry?.containerStyleById[rowId]?.value ??
                  app.registry?.containerStyleById[widget.id]?.value ??
                  AppearanceScope.controllerOf(context)?.value.styles[rowId] ??
                  AppearanceScope.controllerOf(
                    context,
                  )?.value.styles[widget.id] ??
                  widget.templateStyle);
        final style =
            registry?.styleController(rowId, fallback: rowStyleFallback) ??
            _localStyle;

        _observe(config, listScope, repositoryStore);
        final nativeConfig = _toNativeConfig(config);

        return ValueListenableBuilder<ContainerStyle>(
          valueListenable: style,
          builder: (context, currentRowStyle, _) => NativeComponentEditor(
            id: widget.id,
            label: widget.label,
            menuType: 'TreeView',
            menuIcon: Icons.account_tree_outlined,
            keyPrefix: 'super-tree-view',
            settingsTitle: 'Configurer le TreeView',
            editSurface: true,
            config: nativeConfig,
            onChanged: (nextNative) {
              final updated = _fromNativeConfig(controller.value, nextNative);
              controller.value = updated;
              _renderRevision++;
              widget.onConfigChanged?.call(updated);
            },
            onSlotRemoved: (region, slot) =>
                _handleSlotRemoved(controller, registry, region, slot),
            onConfigure: () => _openSettings(controller),
            menuTooltip: (_) =>
                formatSuperTreeViewTooltip(title: widget.label, config: config),
            registry: registry,
            slots: _slots,
            regions: _regions,
            builder: (context, editor) {
              final placeholder = listScope?.placeholder ?? false;
              final items = placeholder ? null : _rawNodes;
              final editing = editor.editing;
              final templateMode =
                  (items == null || items.isEmpty) && (editing || placeholder);

              final message = placeholder
                  ? null
                  : config.binding == null
                  ? 'TreeView non lié : choisissez un repository dans les réglages.'
                  : _error ??
                        (_source?.unselected == true
                            ? 'Aucune ligne parente sélectionnée.'
                            : items != null && items.isEmpty && !_loading
                            ? config.emptyText
                            : null);

              final treeNodes = _ensureTreeNodes(
                config,
                templateMode: templateMode,
                editing: editing,
              );

              final hasCustomSelectedStyle =
                  currentRowStyle.states?.hasSelected == true;
              final animateIndicators = config.animateSelectionAndHover;
              for (final root in treeNodes) {
                void applySelectionBg(TreeNodeData<SuperTreeNodeItem> node) {
                  node.bgColor =
                      !animateIndicators &&
                          !hasCustomSelectedStyle &&
                          _isNodeSelected(node.data)
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.14)
                      : null;
                  for (final child in node.children ?? const []) {
                    applySelectionBg(child);
                  }
                }

                applySelectionBg(root);
              }

              final rowExtraExtent =
                  currentRowStyle.contentPadding.vertical +
                  currentRowStyle.outerMargin.vertical;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        message,
                        key: ValueKey('super-tree-message-${widget.id}'),
                        style: _error != null || config.binding == null
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              )
                            : null,
                      ),
                    ),
                  if (treeNodes.isNotEmpty)
                    Flexible(
                      fit: FlexFit.loose,
                      child: TreeView<SuperTreeNodeItem>(
                        key: ValueKey('super-tree-${widget.id}'),
                        rowHeight: config.rowHeight,
                        rowExtraExtent: rowExtraExtent,
                        indentSize: config.indent,
                        showConnectors: config.showConnectors,
                        showCheckboxes: config.showCheckboxes,
                        animateSelectionAndHover: animateIndicators,
                        selectionIndicatorBuilder: (ctx, _) =>
                            _buildSelectionIndicator(ctx, currentRowStyle),
                        hoverIndicatorBuilder: (ctx, _) =>
                            _buildHoverIndicator(ctx, currentRowStyle),
                        canHoverNode: (node) => !node.data.isTemplate,
                        enableContextMenu: !editing,
                        onToggleNode: (node) {
                          if (!node.data.isTemplate) {
                            _expandedByPath[node.data.nodePath] =
                                !node.isToogleRequested && node.isExpanded;
                          }
                        },
                        isRowCached: (node) => node.data.revision,
                        getNodes: () => TreeViewData<SuperTreeNodeItem>(
                          nodes: treeNodes,
                          headerSize: config.headerSize,
                        ),
                        rowWrapper: (node, rowContent) => _buildRowWrapper(
                          context,
                          style,
                          rowId,
                          listScope,
                          node,
                          rowContent,
                          animateSelectionAndHover: animateIndicators,
                        ),
                        getHeader: (node) => _buildZoneContent(
                          context,
                          editor,
                          config,
                          node.data,
                          SuperTreeViewConfig.headerZone,
                        ),
                        getDataRow: (node) => _buildZoneContent(
                          context,
                          editor,
                          config,
                          node.data,
                          SuperTreeViewConfig.dataZone,
                        ),
                        isSelected: (node, _, _) => _isNodeSelected(node.data),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
