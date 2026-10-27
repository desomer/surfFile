import 'package:material_ui/material_ui.dart';

import '../../../models/native_component_config.dart';
import '../../../models/registry.dart';
import '../../../super_app.dart';
import '../../../theme/appearance.dart';
import '../../editing/components/native_component_editor.dart';
import '../super_layout/slot_implementation.dart';
import '../../editing/slots/editor_slot.dart';

/// AppBar regions map to Flutter properties, never to a SuperLayout.
class SuperAppBar extends StatefulWidget implements NativePreferredSizeWidget {
  const SuperAppBar({
    this.id = 'root-appBar',
    this.label = 'ApplicationBar',
    this.title,
    this.leading,
    this.action,
    this.actions = const [],
    this.bottom,
    this.flexibleSpace,
    this.automaticallyImplyLeading = true,
    this.automaticallyImplyActions = true,
    this.toolbarHeight = kToolbarHeight,
    this.slots = const [],
    this.nativeConfig,
    this.onNativeSlotAdded,
    super.key,
  });

  final String id;
  final String label;
  final Widget? title;
  final Widget? leading;

  /// Compatibility shorthand for the first entry in [actions].
  final Widget? action;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final Widget? flexibleSpace;
  final bool automaticallyImplyLeading;
  final bool automaticallyImplyActions;
  final double toolbarHeight;
  final List<SlotImplementation> slots;
  final NativeComponentConfig? nativeConfig;
  final NativeSlotAddedCallback? onNativeSlotAdded;

  NativeComponentConfig get _initialConfig =>
      nativeConfig ??
      NativeComponentConfig(
        placements: {
          if (leading != null) 'leading': ['leading'],
          if (title != null) 'title': ['title'],
          if (action != null || actions.isNotEmpty)
            'actions': [
              if (action != null) 'action',
              for (var i = 0; i < actions.length; i++) 'action:$i',
            ],
          if (bottom != null) 'bottom': ['bottom'],
          if (flexibleSpace != null) 'flexibleSpace': ['flexibleSpace'],
        },
      );

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + _bottomHeight(_initialConfig));

  double _bottomHeight(
    NativeComponentConfig config, {
    bool editing = false,
    Registry? registry,
  }) {
    final ids = config.slotsOf('bottom');
    if (!config.isEnabled('bottom') || (ids.isEmpty && !editing)) return 0;
    if (ids.length > 1) {
      throw StateError('AppBar.bottom accepts a single slot.');
    }
    if (ids.isEmpty) return kToolbarHeight;
    final id = ids.single;
    final type = config.slotTypeOf(id);
    final supplied = slots
        .where((slot) => slot.id == id || slot.id == type)
        .firstOrNull;
    final component = registry?.components.entries
        .where(
          (entry) => type == 'component:${entry.value.slotId ?? entry.key}',
        )
        .firstOrNull
        ?.value;
    final preferred =
        config.slotPreferredSizes[id] ??
        (type == 'bottom'
            ? bottom?.preferredSize
            : supplied?.preferredSize ??
                  component?.createSlot(id).preferredSize);
    final height = preferred?.height;
    return height != null && height.isFinite ? height : kToolbarHeight;
  }

  ValueNotifier<NativeComponentConfig>? _controller(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    return registry?.nativeComponentController(id, fallback: _initialConfig);
  }

  @override
  Listenable? sizeListenable(BuildContext context) => _controller(context);

  @override
  Size preferredSizeIn(BuildContext context) {
    final config =
        _controller(context)?.value ??
        AppearanceScope.of(context)
            .nativeComponent(id, fallback: _initialConfig);
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    return Size.fromHeight(
      toolbarHeight +
          _bottomHeight(
            config,
            editing: editing,
            registry: SuperApp.maybeOf(context)?.registry,
          ),
    );
  }

  @override
  State<SuperAppBar> createState() => _SuperAppBarState();
}

class _SuperAppBarState extends State<SuperAppBar> {
  late final _localConfig = ValueNotifier(widget._initialConfig);

  bool _usesDefaultNavigation(NativeComponentConfig config) =>
      config.useDefaultNavigation ??
      (widget.automaticallyImplyLeading &&
          config.regions['leading'] != false &&
          config.slotsOf('leading').isEmpty);

  NativeComponentConfig _added(
    NativeComponentConfig config,
    String region,
    String id,
    SlotImplementation slot,
    List<SlotImplementation> siblings,
  ) {
    return widget.onNativeSlotAdded?.call(config, region, id, slot, siblings) ??
        config;
  }

  List<NativeRegion> get _regions => [
    const NativeRegion(
      'leading',
      'Navigation',
      single: true,
      emptySize: Size.square(56),
    ),
    NativeRegion(
      'title',
      'Titre',
      axis: Axis.horizontal,
      stretch: false,
      emptySize: Size(double.infinity, widget.toolbarHeight),
    ),
    const NativeRegion(
      'actions',
      'Actions',
      axis: Axis.horizontal,
      expand: false,
      stretch: false,
      emptySize: Size(96, kToolbarHeight),
    ),
    const NativeRegion('bottom', 'Bas', single: true),
    const NativeRegion('flexibleSpace', 'Espace flexible', single: true),
  ];

  List<SlotImplementation> _slots() => [
    if (widget.leading case final child?)
      BuilderSlot(id: 'leading', label: 'leading', builder: (_) => child),
    if (widget.title case final child?)
      BuilderSlot(
        id: 'title',
        label: 'title',
        builder: (_) =>
            Align(alignment: AlignmentDirectional.centerStart, child: child),
      ),
    if (widget.action case final child?)
      BuilderSlot(
        id: 'action',
        label: 'action',
        sizing: SlotSizing.intrinsic,
        builder: (_) => child,
      ),
    for (final (index, child) in widget.actions.indexed)
      BuilderSlot(
        id: 'action:$index',
        label: 'action ${index + 1}',
        sizing: SlotSizing.intrinsic,
        builder: (_) => child,
      ),
    if (widget.bottom case final child?)
      BuilderSlot(
        id: 'bottom',
        label: 'bottom',
        preferredSize: child.preferredSize,
        builder: (_) => child,
      ),
    if (widget.flexibleSpace case final child?)
      BuilderSlot(
        id: 'flexibleSpace',
        label: 'flexibleSpace',
        builder: (_) => child,
      ),
    ...widget.slots,
  ];

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final controller = widget._controller(context) ?? _localConfig;
    return ValueListenableBuilder<NativeComponentConfig>(
      valueListenable: controller,
      builder: (context, config, _) => NativeComponentEditor(
        label: widget.label,
        menuType: 'AppBar',
        keyPrefix: 'super-app-bar',
        settingsTitle: 'Configurer la barre',
        editSurface: true,
        config: config,
        onChanged: (value) => controller.value = value,
        regions: _regions,
        slots: _slots(),
        registry: registry,
        isRegionAvailable: (config, region) =>
            region != 'leading' || !_usesDefaultNavigation(config),
        settingsControls: (config, onChanged) => [
          SwitchListTile(
            key: const ValueKey('super-app-bar-default-navigation'),
            title: const Text('Bouton de navigation par défaut'),
            subtitle: const Text(
              'Menu du drawer ou bouton Retour natif. Remplace la zone Navigation.',
            ),
            value: _usesDefaultNavigation(config),
            onChanged: (value) =>
                onChanged(config.withDefaultNavigation(value)),
          ),
        ],
        onSlotAdded: _added,
        builder: (context, editor) {
          final bottomHeight = widget._bottomHeight(
            config,
            editing: editor.editing,
            registry: registry,
          );
          final actions = editor.slotsFor('actions');
          Widget toolbarRegion(
            String id, {
            SlotImplementation? item,
            bool showBadge = true,
          }) => SizedBox(
            height: widget.toolbarHeight,
            child: editor.region(id, item: item, showBadge: showBadge),
          );
          return AppBar(
            toolbarHeight: widget.toolbarHeight,
            titleSpacing: 0,
            automaticallyImplyLeading: _usesDefaultNavigation(config),
            automaticallyImplyActions:
                widget.automaticallyImplyActions &&
                config.regions['actions'] != false,
            leading:
                !_usesDefaultNavigation(config) && editor.visible('leading')
                ? toolbarRegion('leading')
                : null,
            title: editor.visible('title') ? toolbarRegion('title') : null,
            actions: !editor.visible('actions')
                ? (config.regions['actions'] == false ? const [] : null)
                : [
                    if (actions.isEmpty)
                      SizedBox(width: 96, child: toolbarRegion('actions'))
                    else
                      for (final (index, slot) in actions.indexed)
                        toolbarRegion(
                          'actions',
                          item: slot,
                          showBadge: index == 0,
                        ),
                  ],
            bottom: editor.visible('bottom')
                ? PreferredSize(
                    preferredSize: Size.fromHeight(bottomHeight),
                    child: SizedBox(
                      height: bottomHeight,
                      child: editor.region('bottom'),
                    ),
                  )
                : null,
            flexibleSpace: editor.visible('flexibleSpace')
                ? editor.region('flexibleSpace')
                : null,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _localConfig.dispose();
    super.dispose();
  }
}
