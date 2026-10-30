/// Tableau multi-colonnes (`SuperTable`) avec colonnes figées, en-tête, pied,
/// `IterableContent` de ligne (`CwTableRow`) et liaison à un repository JSON.
///
/// ## Fonctionnement
///
/// * **Zones par colonne** :
///   Chaque colonne définie dans [SuperTableConfig.columns] expose :
///   - une zone de cellule `cell:<colId>` répétée pour chaque ligne du tableau ;
///   - une zone d'en-tête `header:<colId>` (affichant par défaut le titre de la
///     colonne si aucun composant n'y est placé) lorsque
///     [SuperTableConfig.showHeaderRow] est actif ;
///   - une zone de pied `bottom:<colId>` lorsque
///     [SuperTableConfig.showBottomRow] est actif.
/// * **IterableContent & CwTableRow** :
///   Chaque ligne de données est enveloppée dans un [IterableContent] (éditable
///   dans le designer) et un [CwTableRow] qui applique le [ContainerStyle] de
///   la ligne (couleurs, bordures, états `hover` / `selected`, marges et
///   paddings) de manière synchronisée entre les colonnes figées à gauche et
///   le corps défilant à droite.
/// * **Liaison Repository (`JsonTextBinding`) & Maître / Détail** :
///   Chaque ligne de données expose son indice et son chemin via un
///   [JsonListScope]. Un `SuperValue` placé dans une cellule avec le repository
///   hérité et un chemin relatif (`nom`) ou modèle (`clients[?].nom`) lit et
///   modifie l'élément de la ligne courante. Un clic sur une ligne met à jour
///   la sélection partagée dans le `JsonArrayBinding` du repository.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/json_text_binding.dart';
import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/super_table_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../super_app.dart';
import '../../theme/appearance.dart';
import '../../theme/container_fill.dart';
import '../../theme/container_style.dart';
import '../../theme/style_extras.dart';
import '../editing/components/native_component_editor.dart';
import '../editing/components/super_table_editor.dart';
import '../editing/history/editor_history.dart';
import '../editing/slots/editable_surface.dart';
import '../surfaces/super_container.dart';
import 'internal_widget/array/cw_table_layout.dart';
import 'internal_widget/array/cw_table_row.dart';
import 'super_layout/iterable_content.dart';
import 'super_layout/slot_implementation.dart';

@immutable
class _TableSource {
  const _TableSource({
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
      other is _TableSource &&
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

/// Composant `SuperTable` avec `IterableContent` de ligne et liaison repository.
class SuperTable extends StatefulWidget {
  const SuperTable({
    this.id = 'root-table',
    this.itemId,
    this.label = 'Table',
    this.headers = const {},
    this.cells = const {},
    this.bottoms = const {},
    this.slots = const [],
    this.config,
    this.templateStyle = const ContainerStyle(),
    this.onRowSelected,
    this.onHeaderActionTap,
    this.onConfigChanged,
    super.key,
  });

  /// ID sous lequel sont persistés les réglages et la disposition de la table.
  final String id;

  /// ID technique distinct pour l'[IterableContent] des lignes.
  /// Si non spécifié, utilise [SuperTableConfig.itemId] ou [id].
  final String? itemId;

  final String label;

  /// Widgets fournis en code pour les en-têtes, par identifiant de colonne (`col.id`).
  final Map<String, Widget> headers;

  /// Widgets fournis en code pour les cellules de données, par identifiant de colonne (`col.id`).
  final Map<String, Widget> cells;

  /// Widgets fournis en code pour les cellules de pied, par identifiant de colonne (`col.id`).
  final Map<String, Widget> bottoms;

  /// Catalogue additionnel de slots disponibles dans les zones des colonnes.
  final List<SlotImplementation> slots;

  /// Configuration initiale avant celle enregistrée dans l'apparence.
  final SuperTableConfig? config;

  /// Style initial partagé par les lignes (`IterableContent`), avant celui
  /// enregistré dans l'apparence.
  final ContainerStyle templateStyle;

  /// Appelé avec l'indice de donnée lorsqu'une ligne est sélectionnée.
  final ValueChanged<int>? onRowSelected;

  /// Appelé lorsque l'utilisateur clique sur le bouton d'action d'un en-tête de colonne.
  final void Function(int colIndex, Offset globalPosition)? onHeaderActionTap;

  /// Appelé lorsque la configuration est modifiée.
  final ValueChanged<SuperTableConfig>? onConfigChanged;

  SuperTableConfig get _initialConfig {
    if (config != null) {
      return itemId != null && config!.itemId == null
          ? config!.copyWith(itemId: itemId)
          : config!;
    }
    final placements = <String, List<String>>{};
    for (final colId in headers.keys) {
      placements[SuperTableConfig.headerZoneFor(colId)] = ['header:$colId'];
    }
    for (final colId in cells.keys) {
      placements[SuperTableConfig.cellZoneFor(colId)] = ['cell:$colId'];
    }
    for (final colId in bottoms.keys) {
      placements[SuperTableConfig.bottomZoneFor(colId)] = ['bottom:$colId'];
    }
    return SuperTableConfig(
      itemId: itemId,
      showBottomRow: bottoms.isNotEmpty,
      placements: placements,
    );
  }

  @override
  State<SuperTable> createState() => _SuperTableState();
}

class _SuperTableState extends State<SuperTable> {
  late final ValueNotifier<SuperTableConfig> _localConfig = ValueNotifier(
    widget._initialConfig,
  );
  late final ValueNotifier<ContainerStyle> _localStyle = ValueNotifier(
    widget.templateStyle,
  );

  JsonRepositoryStore? _store;
  _TableSource? _source;
  String? _configPath;
  JsonArrayBinding? _selection;
  List<JsonArrayBinding> _listened = const [];
  List<Object?>? _items;
  String? _error;
  bool _loading = false;
  bool _busy = false;
  int _generation = 0;

  @override
  void didUpdateWidget(SuperTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.config != widget.config) {
      _localConfig.value = widget._initialConfig;
    }
    if (oldWidget.id != widget.id ||
        oldWidget.templateStyle != widget.templateStyle) {
      _localStyle.value = widget.templateStyle;
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
    for (final entry in widget.headers.entries)
      BuilderSlot(
        id: 'header:${entry.key}',
        label: 'En-tête ${entry.key}',
        builder: (_) => entry.value,
      ),
    for (final entry in widget.cells.entries)
      BuilderSlot(
        id: 'cell:${entry.key}',
        label: 'Cellule ${entry.key}',
        builder: (_) => entry.value,
      ),
    for (final entry in widget.bottoms.entries)
      BuilderSlot(
        id: 'bottom:${entry.key}',
        label: 'Pied ${entry.key}',
        builder: (_) => entry.value,
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

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  int? get _selectedDataIndex {
    final source = _source;
    if (source == null || _selection == null) return null;
    return _selection!.indexFor(source.parents);
  }

  bool _isSelected(int index) => _selectedDataIndex == index;

  void _selectRow(int dataIndex) {
    final source = _source;
    if (source != null) {
      final basePath = source.binding?.path;
      _selection?.select(
        source.parents,
        dataIndex,
        nodePath: basePath == null ? null : '$basePath[$dataIndex]',
      );
    }
    widget.onRowSelected?.call(dataIndex);
  }

  _TableSource _resolve(
    SuperTableConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final binding = config.binding;
    if (binding == null) return const _TableSource();
    try {
      final resolved = JsonListScope.resolveSelected(binding, scope, store);
      final scoped = scope?.indices ?? const <int>[];
      return _TableSource(
        binding: resolved.binding,
        unselected: resolved.binding == null,
        parents: resolved.indices,
        rowBase: resolved.indices.length > scoped.length
            ? resolved.indices
            : scoped,
        arrays: resolved.arrays,
      );
    } on FormatException catch (error) {
      return _TableSource(error: error.message);
    }
  }

  void _observe(
    SuperTableConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    _configPath = config.binding?.path;
    if (scope?.placeholder ?? false) return;
    final source = _resolve(config, scope, store);
    if (_source == source && identical(_store, store)) return;
    if (_source != source) {
      _items = null;
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
        _items = null;
        _loading = false;
        _error =
            _source?.error ??
            (store == null && _source?.unselected == true
                ? 'Service de repositories indisponible.'
                : null);
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await store.readArray(binding.repositoryId!, binding.path);
      if (!mounted || generation != _generation) return;
      final selected = _selection?.indexFor(_source!.parents);
      if (selected != null && selected >= items.length) _selection!.clear();
      setState(() {
        _items = items;
        _error = null;
      });
    } on FormatException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.message);
      }
    } on FileSystemException {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Impossible de lire le repository lié.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _change(
    Future<int> Function(JsonRepositoryStore, JsonTextBinding) action,
  ) async {
    final binding = _source?.binding;
    final store = _store;
    if (binding == null || store == null || _busy) return;
    setState(() => _busy = true);
    try {
      await store.flushBindings();
      await action(store, binding);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException {
      if (mounted) {
        setState(() => _error = 'Impossible d’enregistrer le repository lié.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() {
    final length = _items?.length ?? 0;
    return _change((store, binding) async {
      final count = await store.appendArrayItem(
        binding.repositoryId!,
        binding.path,
        expectedLength: length,
      );
      if (mounted && _source?.binding == binding) _selectRow(count - 1);
      return count;
    });
  }

  Future<void> _remove(int index) async {
    final items = _items;
    if (items == null || index >= items.length) return;
    final expected = items[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l’élément ?'),
        content: Text('L’élément ${index + 1} sera retiré du repository.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _change((store, binding) async {
      final count = await store.removeArrayItem(
        binding.repositoryId!,
        binding.path,
        index,
        expectedItem: expected,
      );
      final template = _templatePath;
      if (template != null) {
        store
            .bindingOf(binding.repositoryId!)
            .removed(template, _source!.parents, index);
      }
      return count;
    });
  }

  List<NativeRegion> _buildRegions(SuperTableConfig config) => [
    for (final col in config.columns) ...[
      if (config.showHeaderRow)
        NativeRegion(
          SuperTableConfig.headerZoneFor(col.id),
          'En-tête ${col.title.isEmpty ? col.id : col.title}',
          axis: Axis.horizontal,
          expand: true,
          stretch: true,
          editableFlow: true,
          emptySize: Size(col.width, config.headerRowHeight),
        ),
      NativeRegion(
        SuperTableConfig.cellZoneFor(col.id),
        col.title.isEmpty ? col.id : col.title,
        required: true,
        axis: Axis.horizontal,
        expand: true,
        stretch: true,
        editableFlow: true,
        emptySize: Size(col.width, config.rowHeight),
      ),
      if (config.showBottomRow)
        NativeRegion(
          SuperTableConfig.bottomZoneFor(col.id),
          'Pied ${col.title.isEmpty ? col.id : col.title}',
          axis: Axis.horizontal,
          expand: true,
          stretch: true,
          editableFlow: true,
          emptySize: Size(col.width, config.bottomRowHeight),
        ),
    ],
  ];

  NativeComponentConfig _toNativeConfig(SuperTableConfig config) {
    final activeRegionIds = {
      for (final col in config.columns) ...[
        if (config.showHeaderRow) SuperTableConfig.headerZoneFor(col.id),
        SuperTableConfig.cellZoneFor(col.id),
        if (config.showBottomRow) SuperTableConfig.bottomZoneFor(col.id),
      ],
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

  SuperTableConfig _fromNativeConfig(
    SuperTableConfig current,
    NativeComponentConfig native,
  ) {
    return current.copyWith(
      placements: {...current.placements, ...native.placements},
      slotTypes: {...current.slotTypes, ...native.slotTypes},
      zoneAxes: {...current.zoneAxes, ...native.regionAxes},
      zoneFlows: {...current.zoneFlows, ...native.regionFlows},
      slotPreferredSizes: {
        ...current.slotPreferredSizes,
        ...native.slotPreferredSizes,
      },
      slotSizeConstraints: {
        ...current.slotSizeConstraints,
        ...native.slotSizeConstraints,
      },
      slotLabels: {...current.slotLabels, ...native.slotLabels},
    );
  }

  Future<void> _handleSlotRemoved(
    ValueNotifier<SuperTableConfig> controller,
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
            EditorConfigKind.table,
          );
        }
      }
    } finally {
      history?.commitTransaction();
    }
  }

  Future<void> _openSettings(ValueNotifier<SuperTableConfig> controller) async {
    final result = await showSuperTableEditor(
      context: context,
      config: controller.value,
    );
    if (result == null || !mounted || result == controller.value) return;
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      controller.value = result;
    } finally {
      history?.commitTransaction();
    }
    widget.onConfigChanged?.call(result);
  }

  Widget _buildZoneContent(
    BuildContext context,
    NativeComponentEditorState editor,
    SuperTableConfig config,
    String zoneId, {
    required bool isInteractiveRegion,
  }) {
    final Widget content;
    if (isInteractiveRegion) {
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

  void _updateZoneStyle(
    ValueNotifier<SuperTableConfig> controller,
    String zoneId,
    ContainerStyle nextStyle,
  ) {
    final updated = controller.value.withZoneStyle(zoneId, nextStyle);
    if (updated == controller.value) return;
    controller.value = updated;
    widget.onConfigChanged?.call(updated);
  }

  Widget _buildHeaderCell(
    BuildContext context,
    ValueNotifier<SuperTableConfig> controller,
    NativeComponentEditorState editor,
    SuperTableConfig config,
    int colIndex,
  ) {
    if (colIndex < 0 || colIndex >= config.columns.length) {
      return const SizedBox.shrink();
    }
    final col = config.columns[colIndex];
    final zoneId = SuperTableConfig.headerZoneFor(col.id);
    final slots = editor.slotsFor(zoneId);
    final label = 'En-tête ${col.title.isEmpty ? col.id : col.title}';
    return EditableSurface(
      key: ValueKey('super-table-header-cell-${widget.id}-${col.id}'),
      singleChild: false,
      label: label,
      menuType: 'En-tête',
      menuIcon: Icons.table_rows_outlined,
      style: config.zoneStyleOf(zoneId),
      fallbackColor: Colors.transparent,
      borderColor: Colors.transparent,
      onStyleChanged: (next) => _updateZoneStyle(controller, zoneId, next),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (slots.isEmpty && col.title.isNotEmpty)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    col.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          _buildZoneContent(
            context,
            editor,
            config,
            zoneId,
            isInteractiveRegion: true,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCell(
    BuildContext context,
    ValueNotifier<SuperTableConfig> controller,
    NativeComponentEditorState editor,
    SuperTableConfig config,
    int colIndex,
  ) {
    if (colIndex < 0 || colIndex >= config.columns.length) {
      return const SizedBox.shrink();
    }
    final col = config.columns[colIndex];
    final zoneId = SuperTableConfig.bottomZoneFor(col.id);
    final label = 'Pied ${col.title.isEmpty ? col.id : col.title}';
    return EditableSurface(
      key: ValueKey('super-table-bottom-cell-${widget.id}-${col.id}'),
      singleChild: false,
      label: label,
      menuType: 'Pied',
      menuIcon: Icons.table_rows_outlined,
      style: config.zoneStyleOf(zoneId),
      fallbackColor: Colors.transparent,
      borderColor: Colors.transparent,
      onStyleChanged: (next) => _updateZoneStyle(controller, zoneId, next),
      child: _buildZoneContent(
        context,
        editor,
        config,
        zoneId,
        isInteractiveRegion: true,
      ),
    );
  }

  Widget _buildBodyCell(
    BuildContext context,
    NativeComponentEditorState editor,
    SuperTableConfig config,
    int dataIndex,
    int colIndex, {
    required bool templateMode,
  }) {
    if (colIndex < 0 || colIndex >= config.columns.length) {
      return const SizedBox.shrink();
    }
    final col = config.columns[colIndex];
    final zoneId = SuperTableConfig.cellZoneFor(col.id);
    final isLastCol = colIndex == config.columns.length - 1;
    final showRemove = !templateMode && config.allowRemove && isLastCol;
    final content = _buildZoneContent(
      context,
      editor,
      config,
      zoneId,
      isInteractiveRegion: dataIndex == 0,
    );
    if (!showRemove) {
      return content;
    }
    return Row(
      children: [
        Expanded(child: content),
        IconButton(
          key: ValueKey('super-table-remove-${widget.id}-$dataIndex'),
          tooltip: 'Supprimer l’élément',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: _busy ? null : () => _remove(dataIndex),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Widget _buildTableRow(
    BuildContext context,
    ValueNotifier<ContainerStyle> style,
    String rowId,
    JsonListScope? parentScope,
    SuperTableConfig config, {
    required int row,
    required int rowCountTop,
    required int totalRowCount,
    required int rowCountBottom,
    required int freezeCount,
    required bool isStartCols,
    required bool templateMode,
    required List<Object?>? items,
    required Widget child,
    required FrozenTableViewState tableState,
  }) {
    final isHeader = row < rowCountTop;
    final isBottom = row >= totalRowCount - rowCountBottom;
    if (isHeader || isBottom) {
      return CwTableRow(
        key: ValueKey(
          'super-table-fixed-row-${widget.id}-${isStartCols ? 'L' : 'R'}-$row',
        ),
        info: CwRowInfo(
          row: row,
          isStartCols: isStartCols,
          nbColFreeze: freezeCount,
          propsRow: null,
          tableState: tableState,
          data: null,
          style: null,
          isHeader: true,
        ),
        child: child,
      );
    }

    final dataIndex = row - rowCountTop;
    final selected = !templateMode && _isSelected(dataIndex);
    final placeholder = templateMode || (parentScope?.placeholder ?? false);
    final itemData = !templateMode && items != null && dataIndex < items.length
        ? items[dataIndex]
        : null;
    final basePath = _source?.binding?.path;

    return JsonListScope(
      key: ValueKey(
        'super-table-row-${widget.id}-${isStartCols ? 'L' : 'R'}-${templateMode ? 'template' : dataIndex}',
      ),
      selected: selected,
      repositoryId: _source?.binding?.repositoryId ?? parentScope?.repositoryId,
      indices: [
        ...?(_source?.rowBase ?? parentScope?.indices),
        templateMode ? 0 : dataIndex,
      ],
      nodePath: templateMode || basePath == null
          ? null
          : '$basePath[$dataIndex]',
      treeTemplatePath: _templatePath,
      placeholder: placeholder,
      child: ValueListenableBuilder<ContainerStyle>(
        valueListenable: style,
        builder: (context, rowStyle, _) => IterableContent(
          id: rowId,
          label: 'Iterable Content',
          style: rowStyle,
          decorate: false,
          applyPadding: false,
          applyMargin: false,
          resolveSelectionAndHover: false,
          onStyleChanged: (next) => style.value = next,
          child: CwTableRow(
            info: CwRowInfo(
              row: row,
              isStartCols: isStartCols,
              nbColFreeze: freezeCount,
              propsRow: null,
              tableState: tableState,
              data: itemData,
              style: rowStyle,
              isHeader: false,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  ContainerStyle _adaptRowStyleForEdge(
    ContainerStyle style, {
    required bool isStartCols,
    required int freezeCount,
  }) {
    final hasLeftEdge = isStartCols || freezeCount == 0;
    final hasRightEdge = !isStartCols || freezeCount == 0;
    if (hasLeftEdge && hasRightEdge) {
      return style;
    }
    final r = style.radii ?? Quad.all(style.radius);
    final bw = style.sideWidths;
    return style.copyWith(
      radii: Quad(
        hasLeftEdge ? r.top : 0,
        hasRightEdge ? r.right : 0,
        hasRightEdge ? r.bottom : 0,
        hasLeftEdge ? r.left : 0,
      ),
      borderWidths: Quad(
        bw.top,
        hasRightEdge ? bw.right : 0,
        bw.bottom,
        hasLeftEdge ? bw.left : 0,
      ),
    );
  }

  Widget _buildSelectionIndicator(
    BuildContext context,
    ContainerStyle currentRowStyle, {
    required bool isStartCols,
    required int freezeCount,
  }) {
    final defaultColor = Theme.of(context).colorScheme.primary
        .withValues(alpha: 0.14);
    final hasCustomSelected = currentRowStyle.states?.hasSelected == true;
    final resolved = hasCustomSelected
        ? currentRowStyle.states!.resolve(currentRowStyle, isSelected: true)
        : currentRowStyle.copyWith(clearStates: true);
    final hasFill = resolved.fill.type != FillType.solid || resolved.hasImage;
    final effectiveStyle = _adaptRowStyleForEdge(
      resolved.copyWith(
        clearStates: true,
        margin: 0,
        marginInsets: null,
        hoverEffect: false,
        color: hasCustomSelected
            ? (resolved.color ?? (hasFill ? null : defaultColor))
            : defaultColor,
      ),
      isStartCols: isStartCols,
      freezeCount: freezeCount,
    );
    final hasLeftEdge = isStartCols || freezeCount == 0;
    final hasRightEdge = !isStartCols || freezeCount == 0;
    final m = resolved.outerMargin;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        hasLeftEdge ? m.left : 0,
        m.top,
        hasRightEdge ? m.right : 0,
        m.bottom,
      ),
      child: SuperContainer(
        key: ValueKey(
          isStartCols
              ? 'super-table-selection-indicator-left-${widget.id}'
              : 'super-table-selection-indicator-${widget.id}',
        ),
        style: effectiveStyle,
        fallbackColor: Colors.transparent,
        borderColor: Colors.transparent,
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildHoverIndicator(
    BuildContext context,
    ContainerStyle currentRowStyle, {
    required bool isStartCols,
    required int freezeCount,
  }) {
    final accent = AppearanceScope.of(context).accent;
    final hoverBase = currentRowStyle.hoverBase(accent);
    final defaultColor = (hoverBase ?? Theme.of(context).colorScheme.onSurface)
        .withValues(alpha: 0.08);
    final hasCustomHover = currentRowStyle.states?.hover?.isEmpty == false;
    final resolved = hasCustomHover
        ? currentRowStyle.states!.resolve(currentRowStyle, isHovered: true)
        : currentRowStyle.copyWith(clearStates: true);
    final hasFill = resolved.fill.type != FillType.solid || resolved.hasImage;
    final effectiveStyle = _adaptRowStyleForEdge(
      resolved.copyWith(
        clearStates: true,
        margin: 0,
        marginInsets: null,
        hoverEffect: false,
        color: hasCustomHover
            ? (resolved.color ?? (hasFill ? null : defaultColor))
            : defaultColor,
      ),
      isStartCols: isStartCols,
      freezeCount: freezeCount,
    );
    final hasLeftEdge = isStartCols || freezeCount == 0;
    final hasRightEdge = !isStartCols || freezeCount == 0;
    final m = resolved.outerMargin;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        hasLeftEdge ? m.left : 0,
        m.top,
        hasRightEdge ? m.right : 0,
        m.bottom,
      ),
      child: SuperContainer(
        key: ValueKey(
          isStartCols
              ? 'super-table-hover-indicator-left-${widget.id}'
              : 'super-table-hover-indicator-${widget.id}',
        ),
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
        registry?.tableController(widget.id, fallback: widget._initialConfig) ??
        _localConfig;
    final listScope = JsonListScope.maybeOf(context);
    final repositoryStore = JsonRepositoryScope.maybeOf(context);

    return ValueListenableBuilder<SuperTableConfig>(
      valueListenable: controller,
      builder: (context, config, _) {
        final rowId = widget.itemId ?? config.itemId ?? widget.id;
        final rowStyleFallback = app == null
            ? widget.templateStyle
            : (app.registry?.containerStyleById[rowId]?.value ??
                  app.registry?.containerStyleById[widget.id]?.value ??
                  AppearanceScope.controllerOf(context)?.value.styles[rowId] ??
                  AppearanceScope.controllerOf(context)
                      ?.value
                      .styles[widget.id] ??
                  widget.templateStyle);
        final style =
            registry?.styleController(rowId, fallback: rowStyleFallback) ??
            _localStyle;

        _observe(config, listScope, repositoryStore);
        final nativeConfig = _toNativeConfig(config);
        final regions = _buildRegions(config);

        return ValueListenableBuilder<ContainerStyle>(
          valueListenable: style,
          builder: (context, currentRowStyle, _) => NativeComponentEditor(
            id: widget.id,
            label: widget.label,
            menuType: 'Table',
            menuIcon: Icons.table_chart_outlined,
            keyPrefix: 'super-table',
            settingsTitle: 'Configurer la Table',
            editSurface: true,
            config: nativeConfig,
            onChanged: (nextNative) {
              final updated = _fromNativeConfig(controller.value, nextNative);
              controller.value = updated;
              widget.onConfigChanged?.call(updated);
            },
            onSlotRemoved: (region, slot) =>
                _handleSlotRemoved(controller, registry, region, slot),
            onConfigure: () => _openSettings(controller),
            menuTooltip: (_) =>
                formatSuperTableTooltip(title: widget.label, config: config),
            registry: registry,
            slots: _slots,
            regions: regions,
            builder: (context, editor) {
              final placeholder = listScope?.placeholder ?? false;
              final items = placeholder ? null : _items;
              final editing = editor.editing;
              final templateMode =
                  (items == null || items.isEmpty) && (editing || placeholder);
              final dataRowCount = templateMode ? 1 : (items?.length ?? 0);

              final message = placeholder
                  ? null
                  : config.binding == null
                  ? 'Table non liée : choisissez un tableau dans les réglages.'
                  : _error ??
                        (_source?.unselected == true
                            ? 'Aucune ligne parente sélectionnée.'
                            : items != null && items.isEmpty && !_loading
                            ? config.emptyText
                            : null);

              final rowCountTop = config.showHeaderRow ? 1 : 0;
              final rowCountBottom = config.showBottomRow ? 1 : 0;
              final totalRowCount = rowCountTop + dataRowCount + rowCountBottom;
              final freezeCount = config.colFreezeLeftCount.clamp(
                0,
                config.columns.length,
              );

              final rowExtraExtent =
                  currentRowStyle.contentPadding.vertical +
                  currentRowStyle.outerMargin.vertical;
              final effectiveDataRowHeight = config.rowHeight + rowExtraExtent;

              final selectedData = templateMode ? null : _selectedDataIndex;
              final initialSelectedTableRow =
                  selectedData != null &&
                      selectedData >= 0 &&
                      selectedData < dataRowCount
                  ? selectedData + rowCountTop
                  : null;

              final canAdd =
                  !placeholder &&
                  config.allowAdd &&
                  _source?.binding != null &&
                  _error == null;

              return LayoutBuilder(
                builder: (context, constraints) {
                  final hasBoundedHeight = constraints.hasBoundedHeight;
                  final naturalTableHeight =
                      (rowCountTop * config.headerRowHeight) +
                      (math.max(1, dataRowCount) * effectiveDataRowHeight) +
                      (rowCountBottom * config.bottomRowHeight) +
                      16.0;
                  final fallbackHeight = naturalTableHeight.clamp(120.0, 500.0);

                  final tableWidget = FrozenTableView(
                    key: ValueKey('super-table-view-${widget.id}'),
                    rowCount: totalRowCount,
                    colCount: config.columns.length,
                    rowCountTop: rowCountTop,
                    rowCountBottom: rowCountBottom,
                    colFreezeLeftCount: freezeCount,
                    rowWidthBorderL: 0,
                    rowWidthBorderR: 0,
                    initialSelectedRow: initialSelectedTableRow,
                    animateSelectionAndHover: config.animateSelectionAndHover,
                    selectionIndicatorBuilder: (ctx, _, isStartCols) =>
                        _buildSelectionIndicator(
                          ctx,
                          currentRowStyle,
                          isStartCols: isStartCols,
                          freezeCount: freezeCount,
                        ),
                    hoverIndicatorBuilder: (ctx, _, isStartCols) =>
                        _buildHoverIndicator(
                          ctx,
                          currentRowStyle,
                          isStartCols: isStartCols,
                          freezeCount: freezeCount,
                        ),
                    canHoverRow: (tableRow) =>
                        !templateMode &&
                        tableRow >= rowCountTop &&
                        tableRow < totalRowCount - rowCountBottom,
                    onRowTap: (tableRow) {
                      final dataIndex = tableRow - rowCountTop;
                      if (!templateMode &&
                          dataIndex >= 0 &&
                          dataIndex < dataRowCount) {
                        _selectRow(dataIndex);
                      }
                    },
                    onHeaderActionTap: widget.onHeaderActionTap,
                    onColumnWidthsChanged: (widths) {
                      final updated = controller.value.withColumnWidths(widths);
                      controller.value = updated;
                      widget.onConfigChanged?.call(updated);
                    },
                    getColWidth: (col, _, _, _) =>
                        col >= 0 && col < config.columns.length
                        ? config.columns[col].width
                        : SuperTableColumnConfig.defaultWidth,
                    getColFillPercent: (col) =>
                        col >= 0 && col < config.columns.length
                        ? config.columns[col].fillPercent
                        : SuperTableColumnConfig.defaultFillPercent,
                    getRowHeight: (row) {
                      if (row < rowCountTop) return config.headerRowHeight;
                      if (row >= totalRowCount - rowCountBottom) {
                        return config.bottomRowHeight;
                      }
                      return effectiveDataRowHeight;
                    },
                    buildTopCell: (row, col) => _buildHeaderCell(
                      context,
                      controller,
                      editor,
                      config,
                      col,
                    ),
                    buildBottomCell: (row, col) => _buildBottomCell(
                      context,
                      controller,
                      editor,
                      config,
                      col,
                    ),
                    buildLeftCell: (row, col) {
                      if (row < rowCountTop) {
                        return _buildHeaderCell(
                          context,
                          controller,
                          editor,
                          config,
                          col,
                        );
                      }
                      if (row >= totalRowCount - rowCountBottom) {
                        return _buildBottomCell(
                          context,
                          controller,
                          editor,
                          config,
                          col,
                        );
                      }
                      return _buildBodyCell(
                        context,
                        editor,
                        config,
                        row - rowCountTop,
                        col,
                        templateMode: templateMode,
                      );
                    },
                    buildBodyCell: (row, col) => _buildBodyCell(
                      context,
                      editor,
                      config,
                      row - rowCountTop,
                      col,
                      templateMode: templateMode,
                    ),
                    buildRow: (row, isStartCols, child, tableState) =>
                        _buildTableRow(
                          context,
                          style,
                          rowId,
                          listScope,
                          config,
                          row: row,
                          rowCountTop: rowCountTop,
                          totalRowCount: totalRowCount,
                          rowCountBottom: rowCountBottom,
                          freezeCount: freezeCount,
                          isStartCols: isStartCols,
                          templateMode: templateMode,
                          items: items,
                          child: child,
                          tableState: tableState,
                        ),
                  );

                  return Column(
                    mainAxisSize: hasBoundedHeight
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (message != null)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            message,
                            key: ValueKey('super-table-message-${widget.id}'),
                            style: _error != null || config.binding == null
                                ? TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  )
                                : null,
                          ),
                        ),
                      if (_error != null && config.binding != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Recharger la table'),
                          ),
                        ),
                      if (totalRowCount > 0)
                        if (hasBoundedHeight)
                          Expanded(child: tableWidget)
                        else
                          SizedBox(height: fallbackHeight, child: tableWidget),
                      if (canAdd)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: ValueKey('super-table-add-${widget.id}'),
                            onPressed: _busy ? null : _add,
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter'),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
