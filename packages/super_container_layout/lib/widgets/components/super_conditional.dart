/// Composant d'affichage conditionnel ([SuperConditional]) piloté par une liaison de repository JSON.
///
/// Sélectionne dynamiquement la branche (zone `'case:<valeur>'` ou `'default'`) à
/// afficher selon la valeur résolue d'un [JsonTextBinding], et propose en mode
/// édition une barre de sélection permettant d'éditer chaque branche comme un [SuperTab].
library;

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/json_syntax.dart';
import '../../models/json_text_binding.dart';
import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/super_conditional_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../super_app.dart';
import '../editing/components/native_component_editor.dart';
import '../editing/components/super_conditional_editor.dart';
import '../editing/slots/editor_slot.dart';
import 'component_common.dart';
import 'json_collection_common.dart';
import 'super_component.dart';
import 'super_layout/slot_implementation.dart';

/// Composant conditionnel affichant la zone d'enfants correspondant à la valeur
/// courante d'une liaison de repository ([SuperConditionalConfig.binding]).
///
/// - Hors mode édition : affiche uniquement le contenu du cas actif
///   (`'case:<valeur>'` ou `'default'`), sans barre d'onglets.
/// - En mode édition : affiche une barre de sélection permettant de basculer
///   entre les différents cas et d'éditer leurs enfants respectifs.
class SuperConditional
    extends SuperStatefulComponent<SuperConditionalConfig?> {
  const SuperConditional({
    this.id = 'root-conditional',
    this.label = 'Conditionnel',
    this.caseViews = const {},
    this.defaultChild,
    this.defaultChildren = const [],
    this.slots = const [],
    this.config,
    this.onCaseChanged,
    this.onConfigChanged,
    super.behaviours,
    super.key,
  });

  @override
  final String id;
  final String label;

  /// Contenus fournis en code par valeur de cas (`'string'`, `'number'`, ...).
  final Map<String, List<Widget>> caseViews;

  /// Raccourci pour un enfant unique dans la branche `'default'`.
  final Widget? defaultChild;

  /// Contenus fournis en code pour la branche `'default'`.
  final List<Widget> defaultChildren;

  /// Catalogue additionnel de slots disponibles dans ce composant.
  final List<SlotImplementation> slots;

  /// Configuration initiale avant celle persistée dans l'apparence.
  @override
  final SuperConditionalConfig? config;

  /// Appelé lorsque la zone active résolue change.
  final ValueChanged<String?>? onCaseChanged;

  /// Appelé lorsque la configuration est modifiée via la boîte de dialogue.
  final ValueChanged<SuperConditionalConfig>? onConfigChanged;

  List<Widget> get _allDefaultChildren => [?defaultChild, ...defaultChildren];

  SuperConditionalConfig get _initialConfig {
    if (config != null) return config!;
    final placements = <String, List<String>>{};
    final cases = <String>[];
    for (final entry in caseViews.entries) {
      final caseKey = entry.key.trim();
      if (caseKey.isEmpty) continue;
      cases.add(caseKey);
      final zone = SuperConditionalConfig.caseZoneFor(caseKey);
      final ids = [
        for (var i = 0; i < entry.value.length; i++)
          'conditional-case:$caseKey:$i',
      ];
      if (ids.isNotEmpty) {
        placements[zone] = ids;
      }
    }
    final defaults = _allDefaultChildren;
    if (defaults.isNotEmpty) {
      placements[SuperConditionalConfig.defaultZone] = [
        for (var i = 0; i < defaults.length; i++) 'conditional-default:$i',
      ];
    }
    return SuperConditionalConfig(cases: cases, placements: placements);
  }

  @override
  State<SuperConditional> createState() => _SuperConditionalState();
}

class _SuperConditionalState extends State<SuperConditional> {
  late final ValueNotifier<SuperConditionalConfig> _localConfig = ValueNotifier(
    widget._initialConfig,
  );

  /// Zone actuellement sélectionnée dans la barre d'édition visuelle.
  String? _editingZone;

  // Observation de la liaison repository
  JsonRepositoryStore? _store;
  JsonTextBinding? _rawBinding;
  String? _scopeRepoId;
  String? _scopeNodePath;
  List<int> _scopeIndices = const [];
  bool _scopePlaceholder = false;
  List<JsonArrayBinding> _selections = const [];
  String? _boundValue;
  String? _bindingError;
  String? _lastNotifiedZone;
  int _generation = 0;
  bool _dirty = true;

  @override
  void didUpdateWidget(SuperConditional oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _localConfig.value = widget._initialConfig;
      _editingZone = null;
      _disposeBinding();
    }
  }

  @override
  void dispose() {
    _disposeBinding();
    _localConfig.dispose();
    super.dispose();
  }

  List<SlotImplementation> get _providedSlots => [
    for (final entry in widget.caseViews.entries)
      for (final (index, child) in entry.value.indexed)
        BuilderSlot(
          id: 'conditional-case:${entry.key.trim()}:$index',
          label: '${entry.key.trim()} ${index + 1}',
          builder: (_) => child,
        ),
    for (final (index, child) in widget._allDefaultChildren.indexed)
      BuilderSlot(
        id: 'conditional-default:$index',
        label: 'default ${index + 1}',
        builder: (_) => child,
      ),
    ...widget.slots,
  ];

  // --- Résolution et lecture réactive du binding ---

  void _disposeBinding() {
    _generation++;
    _listenSelections(const []);
    _store?.removeListener(_onStoreChanged);
    _store?.unregisterBindings(this);
    _store = null;
    _rawBinding = null;
    _boundValue = null;
    _bindingError = null;
    _dirty = true;
  }

  void _listenSelections(List<JsonArrayBinding> selections) {
    if (listEquals(_selections, selections)) return;
    for (final selection in _selections) {
      selection.removeListener(_onSelectionChanged);
    }
    _selections = selections;
    for (final selection in selections) {
      selection.addListener(_onSelectionChanged);
    }
  }

  void _onSelectionChanged() {
    _dirty = true;
    if (mounted) setState(() {});
  }

  void _onStoreChanged() {
    _dirty = true;
    if (mounted) setState(() {});
  }

  static ({String? value, String? error}) _coerceScalarValue(Object? raw) {
    if (raw == null) return (value: null, error: null);
    if (raw is String) return (value: raw, error: null);
    if (raw is bool) return (value: '$raw', error: null);
    if (raw is int) return (value: '$raw', error: null);
    if (raw is num) {
      return (value: JsonReader.formatNumber(raw.toDouble()), error: null);
    }
    return (
      value: null,
      error:
          'La valeur conditionnelle liée doit être scalaire (texte, booléen ou nombre).',
    );
  }

  void _observeBinding(
    SuperConditionalConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final placeholder = scope?.placeholder ?? false;
    final raw = config.binding;
    final sameInputs =
        !_dirty &&
        raw == _rawBinding &&
        identical(store, _store) &&
        _scopeRepoId == scope?.repositoryId &&
        _scopeNodePath == scope?.nodePath &&
        listEquals(_scopeIndices, scope?.indices ?? const []) &&
        _scopePlaceholder == placeholder;
    if (sameInputs) return;

    _dirty = false;
    _rawBinding = raw;
    _scopeRepoId = scope?.repositoryId;
    _scopeNodePath = scope?.nodePath;
    _scopeIndices = List.of(scope?.indices ?? const []);
    _scopePlaceholder = placeholder;

    if (!identical(store, _store)) {
      _store?.removeListener(_onStoreChanged);
      _store?.unregisterBindings(this);
      store?.addListener(_onStoreChanged);
      _store = store;
    }

    if (raw == null || placeholder) {
      store?.unregisterBindings(this);
      _listenSelections(const []);
      _boundValue = null;
      _bindingError = null;
      return;
    }

    if (store == null) {
      _listenSelections(const []);
      _boundValue = null;
      _bindingError = 'Service de repositories indisponible.';
      return;
    }

    store.registerBindings(this, [raw.repositoryId ?? scope?.repositoryId]);

    late final JsonSelectedBinding resolved;
    try {
      resolved = JsonListScope.resolveSelected(raw, scope, store);
    } on FormatException catch (error) {
      _listenSelections(const []);
      _boundValue = null;
      _bindingError = error.message;
      return;
    }

    _listenSelections(resolved.arrays);
    final concrete = resolved.binding;
    if (concrete == null) {
      _boundValue = null;
      _bindingError = null;
      return;
    }

    final cached = store.peekAttribute(concrete);
    if (cached != null) {
      final coerced = _coerceScalarValue(cached.value);
      _boundValue = coerced.value;
      _bindingError = coerced.error;
      return;
    }

    _readAsync(store, concrete);
  }

  void _readAsync(JsonRepositoryStore store, JsonTextBinding concrete) {
    final generation = ++_generation;
    unawaited(() async {
      try {
        final attr = await store.readAttribute(concrete);
        if (!mounted || generation != _generation) return;
        final coerced = _coerceScalarValue(attr.value);
        if (_boundValue != coerced.value || _bindingError != coerced.error) {
          setState(() {
            _boundValue = coerced.value;
            _bindingError = coerced.error;
          });
        }
      } on FormatException catch (error) {
        if (mounted && generation == _generation) {
          setState(() {
            _boundValue = null;
            _bindingError = error.message;
          });
        }
      } on FileSystemException {
        if (mounted && generation == _generation) {
          setState(() {
            _boundValue = null;
            _bindingError = 'Impossible de lire le repository lié.';
          });
        }
      }
    }());
  }

  // --- Pont avec NativeComponentEditor ---

  List<NativeRegion> _buildRegions(SuperConditionalConfig config) => [
    for (final c in config.cases)
      NativeRegion(
        SuperConditionalConfig.caseZoneFor(c),
        'Cas · $c',
        required: true,
        axis: Axis.vertical,
        expand: true,
        stretch: true,
        editableFlow: true,
        emptySize: const Size(double.infinity, 140),
      ),
    if (config.hasDefaultCase)
      const NativeRegion(
        SuperConditionalConfig.defaultZone,
        'Cas par défaut (default)',
        required: true,
        axis: Axis.vertical,
        expand: true,
        stretch: true,
        editableFlow: true,
        emptySize: Size(double.infinity, 140),
      ),
  ];

  NativeComponentConfig _toNativeConfig(
    SuperConditionalConfig config,
    Set<String> activeRegionIds,
  ) => buildNativeComponentConfigFromRegions(
    activeRegionIds: activeRegionIds,
    placements: config.placements,
    slotTypes: config.slotTypes,
    zoneAxes: config.zoneAxes,
    zoneFlows: config.zoneFlows,
    slotPreferredSizes: config.slotPreferredSizes,
    slotSizeConstraints: config.slotSizeConstraints,
    slotLabels: config.slotLabels,
  );

  SuperConditionalConfig _fromNativeConfig(
    SuperConditionalConfig current,
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
    ValueNotifier<SuperConditionalConfig> controller,
    Registry? registry,
    String region,
    SlotImplementation slot,
  ) => purgeRemovedComponentSlots<SuperConditionalConfig>(
    context: context,
    controller: controller,
    registry: registry,
    ownerKind: EditorConfigKind.conditional,
    removedIds: {slot.id},
    slotTypeOf: controller.value.slotTypeOf,
    nextConfig: controller.value.withoutSlot(slot.id),
  );

  Future<void> _openSettings(
    ValueNotifier<SuperConditionalConfig> controller,
  ) => runComponentEditorTransaction<SuperConditionalConfig>(
    context: context,
    configuration: controller,
    onConfigChanged: (result) {
      if (_editingZone != null && !result.activeZones.contains(_editingZone)) {
        _editingZone = result.activeZones.firstOrNull;
      }
      widget.onConfigChanged?.call(result);
    },
    showEditor: (initial) =>
        showSuperConditionalEditor(context: context, config: initial),
  );

  void _handleRegionSelected(String? regionId, SuperConditionalConfig config) {
    if (regionId == null) return;
    if (config.activeZones.contains(regionId) && _editingZone != regionId) {
      setState(() => _editingZone = regionId);
    }
  }

  Widget _buildContentRegion(
    NativeComponentEditorState editor,
    String zoneId, {
    required bool shrinkWidth,
    required bool shrinkHeight,
  }) {
    final zoneAxis = editor.axisOf(zoneId);
    Widget region = editor.region(
      zoneId,
      expand: !(zoneAxis == Axis.vertical ? shrinkHeight : shrinkWidth),
      stretch: !(zoneAxis == Axis.vertical ? shrinkWidth : shrinkHeight),
    );
    if (shrinkWidth || shrinkHeight) {
      region = SlotContentFitScope(
        fitWidth: shrinkWidth,
        fitHeight: shrinkHeight,
        child: region,
      );
    }
    return region;
  }

  Widget _buildEditToolbar(
    BuildContext context,
    SuperConditionalConfig config,
    ValueNotifier<SuperConditionalConfig> controller, {
    required String? activeEditZone,
    required String? runtimeZone,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final zones = config.activeZones;

    String labelForZone(String zone) {
      if (zone == SuperConditionalConfig.defaultZone) return 'default';
      return SuperConditionalConfig.caseValueOfZone(zone) ?? zone;
    }

    return Container(
      key: ValueKey('super-conditional-toolbar-${widget.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.7),
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.call_split_outlined, size: 16, color: colors.primary),
          const SizedBox(width: 6),
          if (_boundValue != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Valeur courante lue depuis le repository',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '= $_boundValue',
                    key: ValueKey('super-conditional-bound-value-${widget.id}'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  for (final zone in zones)
                    ChoiceChip(
                      key: ValueKey(
                        'super-conditional-case-selector-${widget.id}-$zone',
                      ),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          Text(labelForZone(zone)),
                          if (zone == runtimeZone)
                            Icon(
                              Icons.bolt,
                              size: 13,
                              color: activeEditZone == zone
                                  ? colors.onPrimaryContainer
                                  : colors.primary,
                            ),
                        ],
                      ),
                      selected: activeEditZone == zone,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _editingZone = zone),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: ValueKey('super-conditional-configure-${widget.id}'),
            tooltip: 'Configurer les cas conditionnels',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () => _openSettings(controller),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionalBody(
    BuildContext context,
    NativeComponentEditorState editor,
    SuperConditionalConfig config,
    ValueNotifier<SuperConditionalConfig> controller,
    BoxConstraints constraints,
  ) {
    final fitScope = SlotContentFitScope.maybeOf(context);
    final hasBoundedWidth = constraints.hasBoundedWidth;
    final shrinkWidth =
        !hasBoundedWidth ||
        (!constraints.hasTightWidth && (fitScope?.fitWidth ?? false));
    final shrinkHeight =
        !constraints.hasBoundedHeight ||
        (!constraints.hasTightHeight && (fitScope?.fitHeight ?? false));
    final crossAxisAlignment = hasBoundedWidth
        ? CrossAxisAlignment.stretch
        : CrossAxisAlignment.start;

    final zones = config.activeZones;
    final runtimeZone = config.resolveZoneForValue(_boundValue);
    if (_lastNotifiedZone != runtimeZone) {
      _lastNotifiedZone = runtimeZone;
      if (widget.onCaseChanged != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onCaseChanged?.call(runtimeZone);
        });
      }
    }

    final editing = editor.editing;
    if (editing) {
      final effectiveEditZone =
          (_editingZone != null && zones.contains(_editingZone))
          ? _editingZone
          : (runtimeZone != null && zones.contains(runtimeZone))
          ? runtimeZone
          : zones.firstOrNull;

      final toolbar = _buildEditToolbar(
        context,
        config,
        controller,
        activeEditZone: effectiveEditZone,
        runtimeZone: runtimeZone,
      );

      if (effectiveEditZone == null) {
        final emptyMsg = Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Aucun cas configuré. Ouvrez les réglages pour ajouter des cas.',
              key: ValueKey('super-conditional-empty-edit-${widget.id}'),
              textAlign: TextAlign.center,
            ),
          ),
        );
        return Column(
          mainAxisSize: shrinkHeight ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: crossAxisAlignment,
          children: [
            toolbar,
            if (shrinkHeight)
              SizedBox(height: 120, child: emptyMsg)
            else
              Expanded(child: emptyMsg),
          ],
        );
      }

      final regionWidget = KeyedSubtree(
        key: ValueKey(
          'super-conditional-content-${widget.id}-$effectiveEditZone',
        ),
        child: _buildContentRegion(
          editor,
          effectiveEditZone,
          shrinkWidth: shrinkWidth,
          shrinkHeight: shrinkHeight,
        ),
      );

      return Column(
        mainAxisSize: shrinkHeight ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          if (_bindingError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                _bindingError!,
                key: ValueKey('super-conditional-error-${widget.id}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          toolbar,
          if (shrinkHeight) regionWidget else Expanded(child: regionWidget),
        ],
      );
    }

    // Mode exécution normal (sans barre d'outils)
    if (runtimeZone == null || !zones.contains(runtimeZone)) {
      if (config.emptyText.trim().isNotEmpty) {
        return Center(
          child: Text(
            config.emptyText,
            key: ValueKey('super-conditional-empty-${widget.id}'),
          ),
        );
      }
      return SizedBox.shrink(
        key: ValueKey('super-conditional-empty-${widget.id}'),
      );
    }

    Widget activeContent;
    if (config.maintainState && zones.length > 1) {
      final index = zones.indexOf(runtimeZone).clamp(0, zones.length - 1);
      activeContent = IndexedStack(
        key: ValueKey('super-conditional-stack-${widget.id}'),
        index: index,
        sizing: shrinkHeight ? StackFit.loose : StackFit.expand,
        children: [
          for (final zone in zones)
            KeyedSubtree(
              key: ValueKey('super-conditional-content-${widget.id}-$zone'),
              child: _buildContentRegion(
                editor,
                zone,
                shrinkWidth: shrinkWidth,
                shrinkHeight: shrinkHeight,
              ),
            ),
        ],
      );
    } else {
      activeContent = KeyedSubtree(
        key: ValueKey('super-conditional-content-${widget.id}-$runtimeZone'),
        child: _buildContentRegion(
          editor,
          runtimeZone,
          shrinkWidth: shrinkWidth,
          shrinkHeight: shrinkHeight,
        ),
      );
    }

    if (_bindingError == null) {
      return activeContent;
    }

    return Column(
      mainAxisSize: shrinkHeight ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            _bindingError!,
            key: ValueKey('super-conditional-error-${widget.id}'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        if (shrinkHeight) activeContent else Expanded(child: activeContent),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final controller =
        registry?.conditionalController(
          widget.id,
          fallback: widget._initialConfig,
        ) ??
        _localConfig;
    final listScope = JsonListScope.maybeOf(context);
    final repositoryStore = JsonRepositoryScope.maybeOf(context);

    return ValueListenableBuilder<SuperConditionalConfig>(
      valueListenable: controller,
      builder: (context, config, _) {
        _observeBinding(config, listScope, repositoryStore);

        final regions = _buildRegions(config);
        final activeRegionIds = {for (final r in regions) r.id};
        final nativeConfig = _toNativeConfig(config, activeRegionIds);

        return NativeComponentEditor(
          id: widget.id,
          exportConfig: () => controller.value,
          behaviours: widget.behaviours,
          label: widget.label,
          menuType: 'Conditional',
          menuIcon: Icons.call_split_outlined,
          keyPrefix: 'super-conditional',
          settingsTitle: 'Configurer le composant conditionnel',
          editSurface: true,
          config: nativeConfig,
          menuTooltip: (_) => formatSuperConditionalTooltip(
            title: editorComponentLabelOf(context)?.label ?? widget.label,
            config: config,
          ),
          onChanged: (nextNative) {
            controller.value = _fromNativeConfig(
              controller.value,
              nextNative,
              activeRegionIds,
            );
          },
          onConfigure: () => _openSettings(controller),
          onEditRegion: (_) => _openSettings(controller),
          onRegionSelected: (regionId) =>
              _handleRegionSelected(regionId, controller.value),
          onSlotRemoved: (region, slot) =>
              _handleSlotRemoved(controller, registry, region, slot),
          registry: registry,
          slots: _providedSlots,
          regions: regions,
          builder: (context, editor) => LayoutBuilder(
            builder: (context, constraints) => _buildConditionalBody(
              context,
              editor,
              config,
              controller,
              constraints,
            ),
          ),
        );
      },
    );
  }
}
