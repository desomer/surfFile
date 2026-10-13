import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;

import '../models/registry.dart';
import '../models/scaffold_page_config.dart';
import '../super_app.dart';
import 'editing/editor_dialog.dart';
import 'super_layout/slot_implementation.dart';
import 'super_layout/layout_selection.dart';
import 'surfaces/super_container.dart';

class ScaffoldPageLayout extends StatefulWidget {
  const ScaffoldPageLayout({
    required this.id,
    required this.config,
    required this.slots,
    required this.appBar,
    required this.body,
    required this.drawer,
    required this.endDrawer,
    required this.bottomNavigationBar,
    required this.floatingActionButton,
    required this.bottomSheet,
    super.key,
  });

  final String id;
  final ScaffoldPageConfig config;
  final List<SlotImplementation> slots;
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? drawer;
  final Widget? endDrawer;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? bottomSheet;

  @override
  State<ScaffoldPageLayout> createState() => _ScaffoldPageLayoutState();
}

class _ScaffoldPageLayoutState extends State<ScaffoldPageLayout> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<ScaffoldPageRegion, GlobalKey> _regionKeys = {};
  ScaffoldPageRegion? _selectedRegion;
  bool _pageSelected = false;
  ValueNotifier<bool>? _editMode;
  late final ValueNotifier<ScaffoldPageConfig> _localConfig = ValueNotifier(
    widget.config,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final editMode = StyleEditScope.controllerOf(context);
    if (editMode != _editMode) {
      _editMode?.removeListener(_editingChanged);
      _editMode = editMode;
      _editMode?.addListener(_editingChanged);
    }
    LayoutSelection.register(this, const ['Page'], (label) {
      final region = ScaffoldPageRegion.values
          .where((region) => _regionLabel(region) == label)
          .firstOrNull;
      _selectRegion(region);
    }, onDeselect: _clearSelection);
  }

  void _editingChanged() {
    if (_editMode?.value == true) {
      _selectRegion(null);
    } else {
      _clearSelection();
    }
  }

  void _clearSelection() {
    if (!mounted) return;
    setState(() {
      _pageSelected = false;
      _selectedRegion = null;
    });
    LayoutSelection.report(this, const []);
  }

  void _selectRegion(ScaffoldPageRegion? region, [BuildContext? target]) {
    if (!mounted) return;
    LayoutSelection.deselectDescendants(this);
    setState(() {
      _pageSelected = true;
      _selectedRegion = region;
    });
    LayoutSelection.report(
      this,
      ['Page', if (region != null) _regionLabel(region)],
      clear: _clearSelection,
      focusContext: target ?? _regionKeys[region]?.currentContext ?? context,
    );
  }

  @override
  void dispose() {
    _editMode?.removeListener(_editingChanged);
    LayoutSelection.unregister(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LayoutSelection.report(this, const []);
    });
    _localConfig.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final controller = registry?.scaffoldPageController(
      widget.id,
      fallback: widget.config,
    );
    return ListenableBuilder(
      listenable: LayoutSelection.path,
      builder: (context, _) => ValueListenableBuilder<ScaffoldPageConfig>(
        valueListenable: controller ?? _localConfig,
        builder: (context, config, _) {
          if (_selectedRegion != null && !config.isEnabled(_selectedRegion!)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  _selectedRegion != null &&
                  !(controller ?? _localConfig).value.isEnabled(
                    _selectedRegion!,
                  )) {
                _clearSelection();
              }
            });
          }
          return ContainerContextMenuEntry(
            label: 'Configurer la page…',
            enabled: _editMode?.value ?? false,
            onSelected: () =>
                _configurePage(controller ?? _localConfig, registry),
            child: _buildScaffold(context, config, registry),
          );
        },
      ),
    );
  }

  Future<void> _configurePage(
    ValueNotifier<ScaffoldPageConfig> controller,
    Registry? registry,
  ) async {
    ScaffoldPageRegion? drawerToOpen;
    _selectRegion(null);
    await showEditorDialog<void>(
      context: context,
      target: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('scaffold-page-settings'),
        title: const Text('Configurer la page'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: ValueListenableBuilder<ScaffoldPageConfig>(
              valueListenable: controller,
              builder: (context, config, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final region in ScaffoldPageRegion.values)
                    if (region != ScaffoldPageRegion.body)
                      SwitchListTile(
                        key: ValueKey('scaffold-page-switch-${region.name}'),
                        title: Text(_regionLabel(region)),
                        value: config.isEnabled(region),
                        onChanged: (enabled) {
                          _update(
                            config.withRegionEnabled(region, enabled),
                            registry,
                          );
                          if (enabled &&
                              (region == ScaffoldPageRegion.drawer ||
                                  region == ScaffoldPageRegion.endDrawer)) {
                            drawerToOpen = region;
                          }
                        },
                      ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final config = controller.value;
    if (drawerToOpen != null && config.isEnabled(drawerToOpen!)) {
      _openDrawer(drawerToOpen!);
    }
  }

  void _openDrawer(ScaffoldPageRegion region) {
    if (region == ScaffoldPageRegion.drawer) {
      _scaffoldKey.currentState?.openDrawer();
    } else {
      _scaffoldKey.currentState?.openEndDrawer();
    }
  }

  List<SlotImplementation> _providedSlots() => [
    if (widget.appBar case final bar?)
      BuilderSlot(
        id: 'scaffold:appBar',
        label: 'AppBar',
        sizing: SlotSizing.intrinsic,
        preferredSize: bar.preferredSize,
        builder: (_) => bar,
      ),
    BuilderSlot(
      id: 'scaffold:body',
      label: 'Body',
      builder: (_) => widget.body,
    ),
    if (widget.drawer case final drawer?)
      BuilderSlot(
        id: 'scaffold:drawer',
        label: 'Drawer',
        builder: (_) =>
            drawer is Drawer ? drawer.child ?? const SizedBox() : drawer,
      ),
    if (widget.endDrawer case final drawer?)
      BuilderSlot(
        id: 'scaffold:endDrawer',
        label: 'End drawer',
        builder: (_) =>
            drawer is Drawer ? drawer.child ?? const SizedBox() : drawer,
      ),
    if (widget.bottomNavigationBar case final bar?)
      BuilderSlot(
        id: 'scaffold:bottomNavigationBar',
        label: 'Bottom navigation bar',
        sizing: SlotSizing.intrinsic,
        builder: (_) => bar,
      ),
    if (widget.floatingActionButton case final button?)
      BuilderSlot(
        id: 'scaffold:floatingActionButton',
        label: 'Floating action button',
        sizing: SlotSizing.intrinsic,
        builder: (_) => button,
      ),
    if (widget.bottomSheet case final sheet?)
      BuilderSlot(
        id: 'scaffold:bottomSheet',
        label: 'Bottom sheet',
        sizing: SlotSizing.intrinsic,
        builder: (_) => sheet,
      ),
    ...widget.slots,
  ];

  Map<String, SlotImplementation> _slotsById() {
    final slots = _providedSlots();
    final result = <String, SlotImplementation>{};
    for (final slot in slots) {
      if (result.containsKey(slot.id)) {
        throw StateError('Identifiant de slot Scaffold en double : ${slot.id}');
      }
      result[slot.id] = slot;
    }
    return result;
  }

  List<SlotImplementation> _slotsFor(
    ScaffoldPageConfig config,
    ScaffoldPageRegion region,
    Registry? registry,
  ) {
    final slotsById = _slotsById();
    final regionSlots = <SlotImplementation>[];
    for (final id in config.slotsOf(region)) {
      final type = config.slotTypeOf(id);
      SlotImplementation? slot = slotsById[id] ?? slotsById[type];
      if (slot == null && registry != null) {
        for (final entry in registry.components.entries) {
          if (type == _componentType(entry.key, entry.value) &&
              (entry.value.isAvailable?.call(context) ?? true)) {
            slot = entry.value.createSlot(id);
            break;
          }
        }
        if (slot == null) {
          for (final entry in registry.registry.entries) {
            if (type == 'factory:${entry.key}') {
              slot = BuilderSlot(
                id: id,
                label: entry.key,
                builder: (_) => entry.value.getWidget(XuiBuildCtx(id: id)),
              );
              break;
            }
          }
        }
      }
      if (slot != null && slot.visible) {
        regionSlots.add(slot);
      }
    }
    return regionSlots;
  }

  List<({String type, SlotImplementation slot})> _availableSlots(
    BuildContext context,
    Registry? registry,
  ) {
    final candidates = <({String type, SlotImplementation slot})>[
      for (final slot in _providedSlots())
        if (slot.visible) (type: slot.id, slot: slot),
    ];
    if (registry != null) {
      candidates.addAll([
        for (final entry in registry.components.entries)
          if (entry.value.isAvailable?.call(context) ?? true)
            (
              type: _componentType(entry.key, entry.value),
              slot: entry.value.createSlot(
                _componentType(entry.key, entry.value),
              ),
            ),
        for (final entry in registry.registry.entries)
          (
            type: 'factory:${entry.key}',
            slot: BuilderSlot(
              id: 'factory:${entry.key}',
              label: entry.key,
              builder: (_) => entry.value.getWidget(
                XuiBuildCtx(id: 'factory:${entry.key}'),
              ),
            ),
          ),
      ]);
    }
    return candidates;
  }

  String _componentType(String key, RegisteredComponent component) =>
      'component:${component.slotId ?? key}';

  void _update(ScaffoldPageConfig config, Registry? registry) {
    if (_selectedRegion != null && !config.isEnabled(_selectedRegion!)) {
      _clearSelection();
    }
    final controller = registry?.scaffoldPageController(
      widget.id,
      fallback: widget.config,
    );
    (controller ?? _localConfig).value = config;
  }

  Future<void> _addSlot(ScaffoldPageRegion region, Registry? registry) async {
    final candidates = _availableSlots(context, registry);
    final selectedType = await showEditorDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Ajouter dans ${_regionLabel(region)}'),
        children: [
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Text('Aucun slot disponible.'),
            ),
          for (final candidate in candidates)
            SimpleDialogOption(
              key: ValueKey('scaffold-page-add-slot-${candidate.type}'),
              onPressed: () => Navigator.of(dialogContext).pop(candidate.type),
              child: Text(candidate.slot.label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (selectedType == null || !mounted) return;
    final config =
        registry
            ?.scaffoldPageController(widget.id, fallback: widget.config)
            .value ??
        _localConfig.value;
    final candidate = candidates.firstWhere(
      (value) => value.type == selectedType,
    );
    final provided =
        candidate.type == candidate.slot.id &&
        _providedSlots().any((slot) => slot.id == candidate.type);
    var id = selectedType;
    if (!provided) {
      final used = {
        ...widget.slots.map((slot) => slot.id),
        ...config.placements.values.expand((ids) => ids),
      };
      do {
        id = shortid.generate();
      } while (used.contains(id));
    }
    _update(
      config.withSlotAdded(id, region, type: provided ? null : selectedType),
      registry,
    );
  }

  Widget _region(
    ScaffoldPageRegion region,
    ScaffoldPageConfig config,
    Registry? registry, {
    Axis axis = Axis.vertical,
    bool expand = true,
  }) {
    final slots = _slotsFor(config, region, registry);
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    final fillSize = switch (region) {
      ScaffoldPageRegion.bottomNavigationBar => const Size.fromHeight(
        kBottomNavigationBarHeight,
      ),
      ScaffoldPageRegion.bottomSheet => const Size.fromHeight(
        kBottomNavigationBarHeight,
      ),
      ScaffoldPageRegion.floatingActionButton => const Size.square(56),
      _ => null,
    };
    final selected = _selectedRegion == region;
    final path = LayoutSelection.path.value;
    final showOverlay =
        editing &&
        _pageSelected &&
        path.isNotEmpty &&
        path.first == 'Page' &&
        path.length <= 2 &&
        (_selectedRegion == null || selected);
    final colors = Theme.of(context).colorScheme;
    final stack = SlotStack(
      slots: slots,
      axis: axis,
      expand: expand,
      stretch: region != ScaffoldPageRegion.floatingActionButton,
      preferredSizes: {
        if (fillSize != null)
          for (final slot in slots)
            if (slot.sizing == SlotSizing.fill && slot.preferredSize == null)
              slot.id: fillSize,
      },
      showLabels: showOverlay,
      zoneLabel: _regionLabel(region),
      onRemoveSlot: editing
          ? (slot) async => _update(config.withoutSlot(slot.id), registry)
          : null,
    );
    return LayoutSelectionScope(
      owner: this,
      path: ['Page', _regionLabel(region)],
      child: Builder(
        key: _regionKeys.putIfAbsent(region, GlobalKey.new),
        builder: (regionContext) => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if (editing &&
                event.buttons == kPrimaryButton &&
                LayoutSelection.claimPointer(event)) {
              _selectRegion(region, regionContext);
            }
          },
          child: SuperContainer(
            label: _regionLabel(region),
            decorate: false,
            editable: true,
            onAdd: () => _addSlot(region, registry),
            onContextMenu: (_) => _selectRegion(region, regionContext),
            child: Stack(
              children: [
                if (slots.isEmpty && editing)
                  SizedBox(
                    width: region == ScaffoldPageRegion.floatingActionButton
                        ? 56
                        : double.infinity,
                    height: expand
                        ? double.infinity
                        : kBottomNavigationBarHeight,
                  )
                else
                  stack,
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: selected && showOverlay
                          ? ValueKey('scaffold-page-selected-${region.name}')
                          : null,
                      decoration: BoxDecoration(
                        border: showOverlay
                            ? Border.all(
                                color: selected
                                    ? colors.primary
                                    : colors.outlineVariant,
                                width: selected ? 3 : 1,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                if (showOverlay)
                  Positioned.fill(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Material(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                key: ValueKey(
                                  'scaffold-page-select-${region.name}',
                                ),
                                onPressed: () => _selectRegion(
                                  selected ? null : region,
                                  regionContext,
                                ),
                                child: Text(_regionLabel(region)),
                              ),
                              IconButton(
                                key: ValueKey(
                                  'scaffold-page-add-${region.name}',
                                ),
                                tooltip: 'Ajouter dans ${_regionLabel(region)}',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.add),
                                onPressed: () {
                                  _selectRegion(region, regionContext);
                                  _addSlot(region, registry);
                                },
                              ),
                              if (region == ScaffoldPageRegion.body)
                                for (final drawer in [
                                  ScaffoldPageRegion.drawer,
                                  ScaffoldPageRegion.endDrawer,
                                ])
                                  if (config.isEnabled(drawer))
                                    IconButton(
                                      key: ValueKey(
                                        'scaffold-page-open-${drawer.name}',
                                      ),
                                      tooltip: 'Ouvrir ${_regionLabel(drawer)}',
                                      icon: Icon(
                                        drawer == ScaffoldPageRegion.drawer
                                            ? Icons.menu
                                            : Icons.menu_open,
                                      ),
                                      onPressed: () => _openDrawer(drawer),
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar(
    ScaffoldPageConfig config,
    Registry? registry,
  ) {
    final slots = _slotsFor(config, ScaffoldPageRegion.appBar, registry);
    final editing = _editMode?.value ?? false;
    if (!config.isEnabled(ScaffoldPageRegion.appBar) ||
        (slots.isEmpty && !editing))
      return null;
    final height = slots.fold<double>(
      slots.isEmpty ? kToolbarHeight : 0,
      (sum, slot) => sum + (slot.preferredSize?.height ?? kToolbarHeight),
    );
    return PreferredSize(
      preferredSize: Size.fromHeight(height),
      child: _region(
        ScaffoldPageRegion.appBar,
        config,
        registry,
        axis: Axis.vertical,
      ),
    );
  }

  Widget? _buildDrawer(
    ScaffoldPageRegion region,
    ScaffoldPageConfig config,
    Registry? registry,
    Widget? template,
  ) {
    final slots = _slotsFor(config, region, registry);
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    if (!config.isEnabled(region) || (slots.isEmpty && !editing)) return null;
    final content = _region(region, config, registry);
    if (template is Drawer) {
      return Drawer(
        backgroundColor: template.backgroundColor,
        elevation: template.elevation,
        shadowColor: template.shadowColor,
        surfaceTintColor: template.surfaceTintColor,
        shape: template.shape,
        width: template.width,
        semanticLabel: template.semanticLabel,
        clipBehavior: template.clipBehavior,
        child: content,
      );
    }
    if (template != null && slots.length == 1 && !editing) return template;
    return Drawer(child: content);
  }

  Widget _buildScaffold(
    BuildContext context,
    ScaffoldPageConfig config,
    Registry? registry,
  ) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(config, registry),
      body: SizedBox.expand(
        child: _region(ScaffoldPageRegion.body, config, registry),
      ),
      drawer: _buildDrawer(
        ScaffoldPageRegion.drawer,
        config,
        registry,
        widget.drawer,
      ),
      endDrawer: _buildDrawer(
        ScaffoldPageRegion.endDrawer,
        config,
        registry,
        widget.endDrawer,
      ),
      bottomNavigationBar: _optionalRegion(
        ScaffoldPageRegion.bottomNavigationBar,
        config,
        registry,
        expand: false,
      ),
      floatingActionButton: _optionalRegion(
        ScaffoldPageRegion.floatingActionButton,
        config,
        registry,
        expand: false,
      ),
      bottomSheet: _optionalRegion(
        ScaffoldPageRegion.bottomSheet,
        config,
        registry,
        expand: false,
      ),
    );
  }

  Widget? _optionalRegion(
    ScaffoldPageRegion region,
    ScaffoldPageConfig config,
    Registry? registry, {
    required bool expand,
  }) {
    if (!config.isEnabled(region) ||
        (_slotsFor(config, region, registry).isEmpty &&
            _editMode?.value != true)) {
      return null;
    }
    return _region(region, config, registry, expand: expand);
  }

  String _regionLabel(ScaffoldPageRegion region) => switch (region) {
    ScaffoldPageRegion.appBar => 'AppBar',
    ScaffoldPageRegion.body => 'corps',
    ScaffoldPageRegion.drawer => 'Drawer gauche',
    ScaffoldPageRegion.endDrawer => 'Drawer droit',
    ScaffoldPageRegion.bottomNavigationBar => 'barre basse',
    ScaffoldPageRegion.floatingActionButton => 'bouton flottant',
    ScaffoldPageRegion.bottomSheet => 'panneau bas',
  };
}
