import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/component_tag_filter.dart';
import '../../models/json_text_binding.dart';
import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/super_action_config.dart';
import '../../models/super_tab_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/repositories/json_text_controller_binding.dart';
import '../../super_app.dart';
import '../editing/components/native_component_editor.dart';
import '../editing/components/super_tab_editor.dart';
import '../editing/history/editor_history.dart';
import 'super_action.dart';
import 'super_layout/slot_implementation.dart';

/// Tableau JSON résolu pour le mode dynamique de [SuperTab].
@immutable
class _DynamicTabSource {
  const _DynamicTabSource({
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
      other is _DynamicTabSource &&
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

/// Composant spécifique d'onglets (`TabBar` + `TabBarView`) dont les onglets
/// sont pilotés par des composants [SuperAction] et qui supporte deux modes :
/// - [SuperTabMode.static] : onglets fixes dans la zone `'tabs'`, chacun avec
///   sa propre zone de contenu `'content:<tabSlotId>'` ;
/// - [SuperTabMode.dynamic] : onglets générés dynamiquement depuis un tableau
///   JSON de repository, partageant un onglet gabarit (`'tabs'`) et une zone
///   de contenu gabarit (`'content'`) sous un [JsonListScope].
class SuperTab extends StatefulWidget {
  const SuperTab({
    this.id = 'root-tab',
    this.label = 'Onglets',
    this.tab,
    this.tabs = const [],
    this.tabViews = const {},
    this.children = const [],
    this.slots = const [],
    this.config,
    this.onTabSelected,
    this.onConfigChanged,
    super.key,
  });

  final String id;
  final String label;

  /// Raccourci pour un premier onglet [SuperAction].
  final SuperAction? tab;

  /// Liste d'onglets [SuperAction] fournis en code.
  final List<SuperAction> tabs;

  /// Contenus fournis en code par identifiant d'onglet (`tab.id`).
  final Map<String, List<Widget>> tabViews;

  /// Contenus fournis en code par position d'onglet (`children[i]` pour le
  /// `i`-ème onglet). En mode dynamique, utilisés comme contenu gabarit.
  final List<Widget> children;

  /// Catalogue additionnel de slots disponibles dans ce composant.
  final List<SlotImplementation> slots;

  /// Configuration initiale avant celle persistée dans l'apparence.
  final SuperTabConfig? config;

  /// Appelé lorsqu'un onglet est sélectionné.
  final ValueChanged<int>? onTabSelected;

  /// Appelé lorsque la configuration est modifiée via la boîte de dialogue.
  final ValueChanged<SuperTabConfig>? onConfigChanged;

  List<SuperAction> get _allTabs => [?tab, ...tabs];

  SuperTabConfig get _initialConfig {
    if (config != null) return config!;
    final allTabs = _allTabs;
    final placements = <String, List<String>>{
      if (allTabs.isNotEmpty)
        SuperTabConfig.tabsZone: [for (final item in allTabs) item.id],
    };
    for (var i = 0; i < allTabs.length; i++) {
      final tabId = allTabs[i].id;
      final contentZone = SuperTabConfig.contentZoneFor(tabId);
      final ids = <String>[
        if (i < children.length) 'tab-child:$i',
        if (tabViews[tabId] case final list?)
          for (var j = 0; j < list.length; j++) 'tab-view:$tabId:$j',
      ];
      if (ids.isNotEmpty) {
        placements[contentZone] = ids;
      }
    }
    return SuperTabConfig(placements: placements);
  }

  @override
  State<SuperTab> createState() => _SuperTabState();
}

class _SuperTabState extends State<SuperTab> with TickerProviderStateMixin {
  late final ValueNotifier<SuperTabConfig> _localConfig = ValueNotifier(
    widget._initialConfig,
  );
  late final TextEditingController _staticBindingText = TextEditingController(
    text: '${widget._initialConfig.initialIndex}',
  );

  TabController? _tabController;
  late int _selectedIndex = widget._initialConfig.initialIndex;
  int _lastValidIndex = 0;

  // Liaison repository en mode statique (index actif)
  JsonTextControllerBinding? _staticBinding;
  JsonTextBinding? _requestedStaticBinding;
  JsonRepositoryStore? _requestedStaticStore;
  String? _requestedStaticResolveError;
  bool _requestedStaticPlaceholder = false;
  int _staticBindingGeneration = 0;
  String? _staticBindingError;
  List<JsonArrayBinding> _staticSelections = const [];
  Future<void>? _pendingStaticFlush;
  bool _syncingFromStaticBinding = false;

  // Liaison repository en mode dynamique (tableau JSON)
  JsonRepositoryStore? _dynamicStore;
  _DynamicTabSource? _dynamicSource;
  String? _dynamicConfigPath;
  JsonArrayBinding? _dynamicSelection;
  List<JsonArrayBinding> _dynamicListened = const [];
  List<Object?>? _dynamicItems;
  String? _dynamicError;
  bool _dynamicLoading = false;
  bool _dynamicBusy = false;
  int _dynamicGeneration = 0;

  @override
  void initState() {
    super.initState();
    _lastValidIndex = _selectedIndex;
  }

  @override
  void didUpdateWidget(SuperTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _localConfig.value = widget._initialConfig;
      _selectedIndex = widget._initialConfig.initialIndex;
      _lastValidIndex = _selectedIndex;
      _disposeStaticBinding();
      _disposeDynamicBinding();
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabControllerTick);
    _tabController?.dispose();
    _disposeStaticBinding();
    _disposeDynamicBinding();
    _staticBindingText.dispose();
    _localConfig.dispose();
    super.dispose();
  }

  void _ensureTabController(int length, int targetIndex) {
    final safeLength = length < 0 ? 0 : length;
    final clamped = safeLength == 0 ? 0 : targetIndex.clamp(0, safeLength - 1);
    if (_tabController == null || _tabController!.length != safeLength) {
      _tabController?.removeListener(_handleTabControllerTick);
      _tabController?.dispose();
      _tabController = safeLength > 0
          ? (TabController(
              length: safeLength,
              initialIndex: clamped,
              vsync: this,
            )..addListener(_handleTabControllerTick))
          : null;
      _selectedIndex = clamped;
      _lastValidIndex = clamped;
    } else if (_tabController!.index != clamped &&
        !_tabController!.indexIsChanging) {
      _tabController!.index = clamped;
      _selectedIndex = clamped;
      _lastValidIndex = clamped;
    }
  }

  void _handleTabControllerTick() {
    final controller = _tabController;
    if (controller == null || !mounted) return;
    if (!controller.indexIsChanging && controller.index != _selectedIndex) {
      setState(() {
        _selectedIndex = controller.index;
        _lastValidIndex = controller.index;
      });
    }
  }

  Map<String, SuperAction> get _suppliedActions => {
    for (final action in widget._allTabs) action.id: action,
  };

  List<SlotImplementation> get _providedSlots => [
    for (final action in widget._allTabs)
      BuilderSlot(
        id: action.id,
        label: action.config.label,
        tags: const {'action', 'button', 'input'},
        sizing: SlotSizing.intrinsic,
        builder: (_) => action,
      ),
    for (final (index, child) in widget.children.indexed)
      BuilderSlot(
        id: 'tab-child:$index',
        label: 'child ${index + 1}',
        builder: (_) => child,
      ),
    for (final entry in widget.tabViews.entries)
      for (final (index, child) in entry.value.indexed)
        BuilderSlot(
          id: 'tab-view:${entry.key}:$index',
          label: '${entry.key} ${index + 1}',
          builder: (_) => child,
        ),
    ...widget.slots,
  ];

  // --- Liaison en mode Statique (index actif) ---

  void _disposeStaticBinding() {
    _staticBindingGeneration++;
    for (final selection in _staticSelections) {
      selection.removeListener(_staticSelectionChanged);
    }
    _staticSelections = const [];
    _staticBinding?.removeListener(_staticBindingChanged);
    _staticBinding?.dispose();
    _staticBinding = null;
    _requestedStaticBinding = null;
    _requestedStaticStore = null;
    _requestedStaticResolveError = null;
    _requestedStaticPlaceholder = false;
    _staticBindingError = null;
  }

  void _staticSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _listenStaticSelections(List<JsonArrayBinding> selections) {
    if (listEquals(_staticSelections, selections)) return;
    for (final selection in _staticSelections) {
      selection.removeListener(_staticSelectionChanged);
    }
    _staticSelections = selections;
    for (final selection in selections) {
      selection.addListener(_staticSelectionChanged);
    }
  }

  void _setStaticIndexFromBinding(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null || parsed < 0 || parsed == _selectedIndex) return;
    _syncingFromStaticBinding = true;
    try {
      setState(() {
        _selectedIndex = parsed;
        _lastValidIndex = parsed;
        if (_tabController != null && _tabController!.length > 0) {
          final clamped = parsed.clamp(0, _tabController!.length - 1);
          if (_tabController!.index != clamped) {
            _tabController!.animateTo(clamped);
          }
        }
      });
    } finally {
      _syncingFromStaticBinding = false;
    }
  }

  void _staticBindingChanged() {
    if (!mounted) return;
    final binding = _staticBinding;
    if (binding != null && !binding.loading && binding.error == null) {
      _setStaticIndexFromBinding(_staticBindingText.text);
    }
    setState(() {});
  }

  void _writeStaticBoundIndex(int index) {
    if (_syncingFromStaticBinding) return;
    final text = '$index';
    if (_staticBindingText.text != text) {
      _staticBindingText.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    unawaited(_staticBinding?.flush());
  }

  void _observeStaticBinding(
    SuperTabConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    if (config.mode != SuperTabMode.static) {
      if (_staticBinding != null || _requestedStaticBinding != null) {
        _disposeStaticBinding();
      }
      return;
    }
    ({
      JsonTextBinding? binding,
      String? error,
      bool placeholder,
      List<JsonArrayBinding> selections,
    }) resolved;
    final raw = config.binding;
    if (raw == null) {
      resolved = (
        binding: null,
        error: null,
        placeholder: false,
        selections: const [],
      );
    } else if (scope?.placeholder ?? false) {
      resolved = (
        binding: null,
        error: null,
        placeholder: true,
        selections: const [],
      );
    } else {
      try {
        final result = JsonListScope.resolveSelected(raw, scope, store);
        resolved = (
          binding: result.binding,
          error: null,
          placeholder: result.binding == null,
          selections: result.arrays,
        );
      } on FormatException catch (error) {
        resolved = (
          binding: null,
          error: error.message,
          placeholder: false,
          selections: const [],
        );
      }
    }

    _listenStaticSelections(resolved.selections);
    if (_requestedStaticBinding == resolved.binding &&
        _requestedStaticResolveError == resolved.error &&
        _requestedStaticPlaceholder == resolved.placeholder &&
        identical(_requestedStaticStore, store)) {
      return;
    }
    _requestedStaticBinding = resolved.binding;
    _requestedStaticResolveError = resolved.error;
    _requestedStaticPlaceholder = resolved.placeholder;
    _requestedStaticStore = store;
    final generation = ++_staticBindingGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _staticBindingGeneration) return;
      final oldBinding = _staticBinding;
      oldBinding?.removeListener(_staticBindingChanged);
      if (oldBinding != null) {
        _pendingStaticFlush = oldBinding.flush();
      }
      oldBinding?.dispose();
      _staticBinding = null;
      final flushed = _pendingStaticFlush;
      if (flushed != null) await flushed;
      if (!mounted || generation != _staticBindingGeneration) return;
      _staticBindingError = resolved.error;
      if (resolved.binding != null) {
        if (store == null) {
          _staticBindingError = 'Service de repositories indisponible.';
        } else {
          _staticBinding = JsonTextControllerBinding(
            store: store,
            binding: resolved.binding!,
            controller: _staticBindingText,
            onChanged: (text) {
              if (!mounted) return;
              _setStaticIndexFromBinding(text);
            },
          )..addListener(_staticBindingChanged);
        }
      }
      if (mounted) setState(() {});
    });
  }

  // --- Liaison en mode Dynamique (tableau JSON) ---

  void _disposeDynamicBinding() {
    _dynamicGeneration++;
    _dynamicStore?.removeListener(_reloadDynamic);
    _dynamicStore = null;
    _listenDynamic(const []);
    _dynamicSelection = null;
    _dynamicSource = null;
    _dynamicItems = null;
    _dynamicError = null;
    _dynamicLoading = false;
  }

  String? get _dynamicTemplatePath {
    final path = _dynamicConfigPath;
    return path == null ? null : JsonAttributePath(path).toString();
  }

  void _listenDynamic(List<JsonArrayBinding> arrays) {
    for (final array in _dynamicListened) {
      array.removeListener(_dynamicSelectionChanged);
    }
    _dynamicListened = arrays;
    for (final array in arrays) {
      array.addListener(_dynamicSelectionChanged);
    }
  }

  void _dynamicSelectionChanged() {
    if (!mounted) return;
    final source = _dynamicSource;
    final selected = source == null
        ? null
        : _dynamicSelection?.indexFor(source.parents);
    if (selected != null && selected != _selectedIndex) {
      _selectedIndex = selected;
      _lastValidIndex = selected;
      if (_tabController != null &&
          selected >= 0 &&
          selected < _tabController!.length &&
          _tabController!.index != selected) {
        _tabController!.animateTo(selected);
      }
    }
    setState(() {});
  }

  _DynamicTabSource _resolveDynamic(
    SuperTabConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final binding = config.binding;
    if (binding == null) return const _DynamicTabSource();
    try {
      final resolved = JsonListScope.resolveSelected(binding, scope, store);
      final scoped = scope?.indices ?? const <int>[];
      return _DynamicTabSource(
        binding: resolved.binding,
        unselected: resolved.binding == null,
        parents: resolved.indices,
        rowBase: resolved.indices.length > scoped.length
            ? resolved.indices
            : scoped,
        arrays: resolved.arrays,
      );
    } on FormatException catch (error) {
      return _DynamicTabSource(error: error.message);
    }
  }

  void _observeDynamic(
    SuperTabConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    if (config.mode != SuperTabMode.dynamic) {
      if (_dynamicSource != null || _dynamicStore != null) {
        _disposeDynamicBinding();
      }
      return;
    }
    _dynamicConfigPath = config.binding?.path;
    if (scope?.placeholder ?? false) return;
    final source = _resolveDynamic(config, scope, store);
    if (_dynamicSource == source && identical(_dynamicStore, store)) return;
    if (_dynamicSource != source) {
      _dynamicItems = null;
      _dynamicError = null;
    }
    _dynamicSource = source;
    if (!identical(_dynamicStore, store)) {
      _dynamicStore?.removeListener(_reloadDynamic);
      _dynamicStore = store?..addListener(_reloadDynamic);
    }
    final binding = source.binding;
    final templatePath = _dynamicTemplatePath;
    _dynamicSelection = binding == null || store == null || templatePath == null
        ? null
        : store.bindingOf(binding.repositoryId!).array(templatePath);
    _listenDynamic([?_dynamicSelection, ...source.arrays]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reloadDynamic();
    });
  }

  void _selectDynamicIndex(int index) {
    final source = _dynamicSource;
    if (source != null) {
      _dynamicSelection?.select(source.parents, index);
    }
  }

  Future<void> _reloadDynamic() async {
    final generation = ++_dynamicGeneration;
    final binding = _dynamicSource?.binding;
    final store = _dynamicStore;
    if (binding == null || store == null) {
      setState(() {
        _dynamicItems = null;
        _dynamicLoading = false;
        _dynamicError =
            _dynamicSource?.error ??
            (store == null && _dynamicSource?.unselected == true
                ? 'Service de repositories indisponible.'
                : null);
      });
      return;
    }
    setState(() => _dynamicLoading = true);
    try {
      final items = await store.readArray(binding.repositoryId!, binding.path);
      if (!mounted || generation != _dynamicGeneration) return;
      final selected = _dynamicSelection?.indexFor(_dynamicSource!.parents);
      if (selected != null && selected >= items.length) {
        _dynamicSelection!.clear();
      } else if (selected == null && items.isNotEmpty) {
        final initial = _selectedIndex.clamp(0, items.length - 1);
        _dynamicSelection?.select(_dynamicSource!.parents, initial);
      }
      setState(() {
        _dynamicItems = items;
        _dynamicError = null;
      });
    } on FormatException catch (error) {
      if (mounted && generation == _dynamicGeneration) {
        setState(() => _dynamicError = error.message);
      }
    } on FileSystemException {
      if (mounted && generation == _dynamicGeneration) {
        setState(() => _dynamicError = 'Impossible de lire le repository lié.');
      }
    } finally {
      if (mounted && generation == _dynamicGeneration) {
        setState(() => _dynamicLoading = false);
      }
    }
  }

  Future<void> _changeDynamicArray(
    Future<int> Function(JsonRepositoryStore, JsonTextBinding) action,
  ) async {
    final binding = _dynamicSource?.binding;
    final store = _dynamicStore;
    if (binding == null || store == null || _dynamicBusy) return;
    setState(() => _dynamicBusy = true);
    try {
      await store.flushBindings();
      await action(store, binding);
    } on FormatException catch (error) {
      if (mounted) setState(() => _dynamicError = error.message);
    } on FileSystemException {
      if (mounted) {
        setState(
          () => _dynamicError = 'Impossible d’enregistrer le repository lié.',
        );
      }
    } finally {
      if (mounted) setState(() => _dynamicBusy = false);
    }
  }

  Future<void> _addDynamicTab() {
    final length = _dynamicItems?.length ?? 0;
    return _changeDynamicArray((store, binding) async {
      final count = await store.appendArrayItem(
        binding.repositoryId!,
        binding.path,
        expectedLength: length,
      );
      if (mounted && _dynamicSource?.binding == binding) {
        final nextIndex = count - 1;
        _selectedIndex = nextIndex;
        _lastValidIndex = nextIndex;
        _selectDynamicIndex(nextIndex);
      }
      return count;
    });
  }

  Future<void> _removeDynamicTab(int index) async {
    final items = _dynamicItems;
    if (items == null || index < 0 || index >= items.length) return;
    final expected = items[index];
    await _changeDynamicArray((store, binding) async {
      final count = await store.removeArrayItem(
        binding.repositoryId!,
        binding.path,
        index,
        expectedItem: expected,
      );
      final templatePath = _dynamicTemplatePath;
      if (templatePath != null) {
        store
            .bindingOf(binding.repositoryId!)
            .removed(templatePath, _dynamicSource!.parents, index);
      }
      if (mounted && _selectedIndex >= count && count > 0) {
        _selectedIndex = count - 1;
        _lastValidIndex = _selectedIndex;
        _selectDynamicIndex(_selectedIndex);
      }
      return count;
    });
  }

  // --- Pont avec NativeComponentEditor ---

  String _resolveTabLabel(
    String tabSlotId,
    SuperTabConfig config,
    Registry? registry,
  ) {
    final supplied = _suppliedActions[tabSlotId];
    final fallback = supplied?.config ?? const SuperActionConfig();
    final actionConfig =
        registry?.actionController(tabSlotId, fallback: fallback).value ??
        fallback;
    if (actionConfig.label.trim().isNotEmpty &&
        actionConfig.label != 'Action') {
      return actionConfig.label.trim();
    }
    if (config.slotLabels[tabSlotId] case final custom?
        when custom.trim().isNotEmpty) {
      return custom.trim();
    }
    if (actionConfig.label.trim().isNotEmpty) {
      return actionConfig.label.trim();
    }
    return tabSlotId;
  }

  List<NativeRegion> _buildRegions(SuperTabConfig config, Registry? registry) {
    if (config.mode == SuperTabMode.dynamic) {
      return const [
        NativeRegion(
          SuperTabConfig.tabsZone,
          'Onglet gabarit',
          required: true,
          single: true,
          axis: Axis.horizontal,
          expand: false,
          stretch: false,
          emptySize: Size(double.infinity, kTextTabBarHeight),
          tagFilter: ComponentTagFilter(include: {'action'}),
        ),
        NativeRegion(
          SuperTabConfig.dynamicContentZone,
          'Contenu gabarit',
          required: true,
          axis: Axis.vertical,
          expand: true,
          stretch: true,
          editableFlow: true,
          emptySize: Size(double.infinity, 160),
        ),
      ];
    }
    final tabIds = config.tabSlotIds;
    return [
      const NativeRegion(
        SuperTabConfig.tabsZone,
        'Onglets',
        required: true,
        axis: Axis.horizontal,
        expand: false,
        stretch: false,
        emptySize: Size(double.infinity, kTextTabBarHeight),
        tagFilter: ComponentTagFilter(include: {'action'}),
      ),
      for (final tabId in tabIds)
        NativeRegion(
          SuperTabConfig.contentZoneFor(tabId),
          'Contenu · ${_resolveTabLabel(tabId, config, registry)}',
          required: true,
          axis: Axis.vertical,
          expand: true,
          stretch: true,
          editableFlow: true,
          emptySize: const Size(double.infinity, 160),
        ),
    ];
  }

  NativeComponentConfig _toNativeConfig(
    SuperTabConfig config,
    Set<String> activeRegionIds,
  ) {
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

  SuperTabConfig _fromNativeConfig(
    SuperTabConfig current,
    NativeComponentConfig native,
    Set<String> activeRegionIds,
  ) {
    final preservedPlacements = <String, List<String>>{
      for (final entry in current.placements.entries)
        if (!activeRegionIds.contains(entry.key)) entry.key: entry.value,
      ...native.placements,
    };
    final allPlacedIds = preservedPlacements.values
        .expand((ids) => ids)
        .toSet();
    final mergedTypes = <String, String>{
      for (final entry in current.slotTypes.entries)
        if (allPlacedIds.contains(entry.key)) entry.key: entry.value,
      ...native.slotTypes,
    };
    final mergedAxes = <String, Axis>{
      for (final entry in current.zoneAxes.entries)
        if (!activeRegionIds.contains(entry.key)) entry.key: entry.value,
      ...native.regionAxes,
    };
    final mergedFlows = {
      for (final entry in current.zoneFlows.entries)
        if (!activeRegionIds.contains(entry.key)) entry.key: entry.value,
      ...native.regionFlows,
    };
    final mergedSizes = <String, Size?>{
      for (final entry in current.slotPreferredSizes.entries)
        if (allPlacedIds.contains(entry.key) &&
            !activeRegionIds.any((r) => current.slotsOf(r).contains(entry.key)))
          entry.key: entry.value,
      ...native.slotPreferredSizes,
    };
    final mergedConstraints = {
      for (final entry in current.slotSizeConstraints.entries)
        if (allPlacedIds.contains(entry.key) &&
            !activeRegionIds.any((r) => current.slotsOf(r).contains(entry.key)))
          entry.key: entry.value,
      ...native.slotSizeConstraints,
    };
    final mergedLabels = <String, String>{
      for (final entry in current.slotLabels.entries)
        if (allPlacedIds.contains(entry.key) &&
            !activeRegionIds.any((r) => current.slotsOf(r).contains(entry.key)))
          entry.key: entry.value,
      ...native.slotLabels,
    };

    return current.copyWith(
      placements: preservedPlacements,
      slotTypes: mergedTypes,
      zoneAxes: mergedAxes,
      zoneFlows: mergedFlows,
      slotPreferredSizes: mergedSizes,
      slotSizeConstraints: mergedConstraints,
      slotLabels: mergedLabels,
    );
  }

  Future<void> _handleSlotRemoved(
    ValueNotifier<SuperTabConfig> controller,
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
          registry.purgeInstance(entry.key, entry.value, EditorConfigKind.tab);
        }
      }
    } finally {
      history?.commitTransaction();
    }
  }

  Future<void> _openSettings(ValueNotifier<SuperTabConfig> controller) async {
    final result = await showSuperTabEditor(
      context: context,
      config: controller.value,
    );
    if (result == null || !mounted || result == controller.value) return;
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      controller.value = result;
      _selectedIndex = result.initialIndex;
      _lastValidIndex = result.initialIndex;
    } finally {
      history?.commitTransaction();
    }
    widget.onConfigChanged?.call(result);
  }

  void _handleRegionSelected(String? regionId, SuperTabConfig config) {
    if (regionId == null || config.mode != SuperTabMode.static) return;
    final tabId = SuperTabConfig.tabSlotIdOfZone(regionId);
    if (tabId == null) return;
    final index = config.tabSlotIds.indexOf(tabId);
    if (index >= 0 && index != _selectedIndex) {
      setState(() {
        _selectedIndex = index;
        _lastValidIndex = index;
        if (_tabController != null && index < _tabController!.length) {
          _tabController!.animateTo(index);
        }
      });
    }
  }

  Widget _buildStaticTabs(
    BuildContext context,
    NativeComponentEditorState editor,
    SuperTabConfig config,
    Registry? registry,
  ) {
    final tabSlots = editor.slotsFor(SuperTabConfig.tabsZone);
    final supplied = _suppliedActions;

    if (tabSlots.isEmpty) {
      _ensureTabController(0, 0);
      final barPlaceholder = Material(
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          height: kTextTabBarHeight,
          child: editor.region(SuperTabConfig.tabsZone),
        ),
      );
      final emptyBody = Expanded(
        child: Center(
          child: Text(
            'Ajoutez une Action dans la zone « Onglets » pour créer un onglet.',
            key: ValueKey('super-tab-empty-${widget.id}'),
            textAlign: TextAlign.center,
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: config.tabBarPosition == SuperTabBarPosition.bottom
            ? [emptyBody, barPlaceholder]
            : [barPlaceholder, emptyBody],
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        for (final slot in tabSlots)
          if (registry != null)
            registry.actionController(
              slot.id,
              fallback: supplied[slot.id]?.config ?? const SuperActionConfig(),
            ),
      ]),
      builder: (context, _) {
        final effectiveIndex = _selectedIndex.clamp(0, tabSlots.length - 1);
        _ensureTabController(tabSlots.length, effectiveIndex);
        final tabController = _tabController!;

        final tabs = [
          for (final slot in tabSlots)
            Tab(
              key: ValueKey('super-tab-item-${slot.id}'),
              child: SuperActionNavigationScope(
                part: SuperActionNavigationPart.tab,
                child: editor.slotItem(SuperTabConfig.tabsZone, slot),
              ),
            ),
        ];

        final tabBar = Material(
          color: Theme.of(context).colorScheme.surface,
          child: editor.region(
            SuperTabConfig.tabsZone,
            child: TabBar(
              key: ValueKey('super-tab-bar-${widget.id}'),
              controller: tabController,
              isScrollable: config.isScrollable,
              tabs: tabs,
              onTap: (index) {
                final slot = tabSlots[index];
                final action = supplied[slot.id];
                final fallback = action?.config ?? const SuperActionConfig();
                final actionConfig =
                    registry
                        ?.actionController(slot.id, fallback: fallback)
                        .value ??
                    fallback;
                if (!actionConfig.enabled) {
                  final restore = _lastValidIndex.clamp(
                    0,
                    tabSlots.length - 1,
                  );
                  if (tabController.index != restore) {
                    tabController.index = restore;
                  }
                  return;
                }
                setState(() {
                  _selectedIndex = index;
                  _lastValidIndex = index;
                });
                if (config.binding != null) {
                  _writeStaticBoundIndex(index);
                }
                widget.onTabSelected?.call(index);
                executeSuperActionClick(
                  context,
                  slot.id,
                  onPressed: action?.onPressed,
                );
              },
            ),
          ),
        );

        final tabBarView = Expanded(
          child: TabBarView(
            key: ValueKey('super-tab-view-${widget.id}'),
            controller: tabController,
            children: [
              for (final slot in tabSlots)
                KeyedSubtree(
                  key: ValueKey('super-tab-content-${slot.id}'),
                  child: editor.region(
                    SuperTabConfig.contentZoneFor(slot.id),
                  ),
                ),
            ],
          ),
        );

        final activeError = _staticBindingError ?? _staticBinding?.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (activeError != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: Text(
                  activeError,
                  key: ValueKey('super-tab-error-${widget.id}'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (config.tabBarPosition == SuperTabBarPosition.bottom) ...[
              tabBarView,
              tabBar,
            ] else ...[
              tabBar,
              tabBarView,
            ],
          ],
        );
      },
    );
  }

  Widget _buildDynamicTabs(
    BuildContext context,
    NativeComponentEditorState editor,
    SuperTabConfig config,
    Registry? registry,
    JsonListScope? scope,
  ) {
    final placeholder = scope?.placeholder ?? false;
    final items = placeholder ? null : _dynamicItems;
    final editing = editor.editing;
    final templateMode =
        (items == null || items.isEmpty) && (editing || placeholder);
    final count = templateMode ? 1 : (items?.length ?? 0);
    final canAdd =
        !placeholder &&
        config.allowAdd &&
        _dynamicSource?.binding != null &&
        _dynamicError == null;

    final message = placeholder
        ? null
        : config.binding == null
        ? 'Onglets dynamiques non liés : choisissez un tableau dans les réglages.'
        : _dynamicError ??
              (_dynamicSource?.unselected == true
                  ? 'Aucune ligne parente sélectionnée.'
                  : items != null && items.isEmpty && !_dynamicLoading
                  ? config.emptyText
                  : null);

    final templateTabSlots = editor.slotsFor(SuperTabConfig.tabsZone);
    final templateSlot = templateTabSlots.firstOrNull;
    final supplied = _suppliedActions;

    if (templateSlot == null || count == 0) {
      _ensureTabController(0, 0);
      final barArea = Material(
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: kTextTabBarHeight,
                child: editor.region(SuperTabConfig.tabsZone),
              ),
            ),
            if (canAdd)
              IconButton(
                key: ValueKey('super-tab-add-${widget.id}'),
                tooltip: 'Ajouter un onglet',
                onPressed: _dynamicBusy ? null : _addDynamicTab,
                icon: const Icon(Icons.add),
              ),
          ],
        ),
      );
      final contentArea = Expanded(
        child: editor.region(SuperTabConfig.dynamicContentZone),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                message,
                key: ValueKey('super-tab-message-${widget.id}'),
                style: _dynamicError != null || config.binding == null
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
            ),
          if (config.tabBarPosition == SuperTabBarPosition.bottom) ...[
            contentArea,
            barArea,
          ] else ...[
            barArea,
            contentArea,
          ],
        ],
      );
    }

    final selectedFromStore = _dynamicSource == null
        ? null
        : _dynamicSelection?.indexFor(_dynamicSource!.parents);
    final effectiveIndex = (selectedFromStore ?? _selectedIndex).clamp(
      0,
      count - 1,
    );
    _ensureTabController(count, effectiveIndex);
    final tabController = _tabController!;

    JsonListScope wrapScope(int index, Widget child) => JsonListScope(
      selected: !templateMode && index == effectiveIndex,
      repositoryId:
          _dynamicSource?.binding?.repositoryId ?? scope?.repositoryId,
      indices: [
        ...?(_dynamicSource?.rowBase ?? scope?.indices),
        templateMode ? 0 : index,
      ],
      placeholder: templateMode || placeholder,
      child: child,
    );

    final tabs = [
      for (var i = 0; i < count; i++)
        Tab(
          key: ValueKey(
            'super-tab-dynamic-item-${widget.id}-${templateMode ? 'template' : i}',
          ),
          child: wrapScope(
            i,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SuperActionNavigationScope(
                    part: SuperActionNavigationPart.tab,
                    child: i == 0
                        ? editor.slotItem(SuperTabConfig.tabsZone, templateSlot)
                        : templateSlot,
                  ),
                ),
                if (!templateMode && config.allowRemove)
                  IconButton(
                    key: ValueKey('super-tab-remove-${widget.id}-$i'),
                    tooltip: 'Supprimer l’onglet',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    onPressed: _dynamicBusy ? null : () => _removeDynamicTab(i),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
        ),
    ];

    final tabBarRow = Material(
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: editor.region(
              SuperTabConfig.tabsZone,
              child: TabBar(
                key: ValueKey('super-tab-bar-${widget.id}'),
                controller: tabController,
                isScrollable: config.isScrollable,
                tabs: tabs,
                onTap: (index) {
                  setState(() {
                    _selectedIndex = index;
                    _lastValidIndex = index;
                  });
                  if (!templateMode) {
                    _selectDynamicIndex(index);
                  }
                  widget.onTabSelected?.call(index);
                  final action = supplied[templateSlot.id];
                  executeSuperActionClick(
                    context,
                    templateSlot.id,
                    onPressed: action?.onPressed,
                  );
                },
              ),
            ),
          ),
          if (canAdd)
            IconButton(
              key: ValueKey('super-tab-add-${widget.id}'),
              tooltip: 'Ajouter un onglet',
              onPressed: _dynamicBusy ? null : _addDynamicTab,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
    );

    final tabBarView = Expanded(
      key: ValueKey('super-tab-view-${widget.id}'),
      child: KeyedSubtree(
        key: ValueKey(
          'super-tab-dynamic-content-${widget.id}-${templateMode ? 'template' : effectiveIndex}',
        ),
        child: wrapScope(
          effectiveIndex,
          editor.region(SuperTabConfig.dynamicContentZone),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              message,
              key: ValueKey('super-tab-message-${widget.id}'),
              style: _dynamicError != null || config.binding == null
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          ),
        if (config.tabBarPosition == SuperTabBarPosition.bottom) ...[
          tabBarView,
          tabBarRow,
        ] else ...[
          tabBarRow,
          tabBarView,
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final controller =
        registry?.tabController(widget.id, fallback: widget._initialConfig) ??
        _localConfig;
    final listScope = JsonListScope.maybeOf(context);
    final repositoryStore = JsonRepositoryScope.maybeOf(context);

    return ValueListenableBuilder<SuperTabConfig>(
      valueListenable: controller,
      builder: (context, config, _) {
        _observeStaticBinding(config, listScope, repositoryStore);
        _observeDynamic(config, listScope, repositoryStore);

        final regions = _buildRegions(config, registry);
        final activeRegionIds = {for (final r in regions) r.id};
        final nativeConfig = _toNativeConfig(config, activeRegionIds);

        return NativeComponentEditor(
          label: widget.label,
          menuType: 'Tab',
          menuIcon: Icons.tab_outlined,
          keyPrefix: 'super-tab',
          settingsTitle: 'Configurer les onglets',
          editSurface: true,
          config: nativeConfig,
          onChanged: (nextNative) {
            controller.value = _fromNativeConfig(
              controller.value,
              nextNative,
              activeRegionIds,
            );
          },
          onConfigure: () => _openSettings(controller),
          onRegionSelected: (regionId) =>
              _handleRegionSelected(regionId, controller.value),
          onSlotRemoved: (region, slot) =>
              _handleSlotRemoved(controller, registry, region, slot),
          registry: registry,
          slots: _providedSlots,
          regions: regions,
          builder: (context, editor) {
            if (config.mode == SuperTabMode.dynamic) {
              return _buildDynamicTabs(
                context,
                editor,
                config,
                registry,
                listScope,
              );
            }
            return _buildStaticTabs(context, editor, config, registry);
          },
        );
      },
    );
  }
}
