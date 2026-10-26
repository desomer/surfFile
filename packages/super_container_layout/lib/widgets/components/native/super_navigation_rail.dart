import 'package:material_ui/material_ui.dart';

import '../../../models/component_tag_filter.dart';
import '../../../models/native_component_config.dart';
import '../../../models/super_action_config.dart';
import '../../../super_app.dart';
import '../../editing/components/native_component_editor.dart';
import '../super_action.dart';
import '../super_layout/slot_implementation.dart';

/// A native [NavigationRail] whose destinations are exclusively [SuperAction]
/// components converted into [NavigationRailDestination] entries.
class SuperNavigationRail extends StatefulWidget
    implements NativePreferredSizeWidget {
  const SuperNavigationRail({
    this.id = 'root-navigationRail',
    this.label = 'Rail de navigation',
    this.destination,
    this.destinations = const [],
    this.selectedIndex = 0,
    this.onDestinationSelected,
    this.width = 72.0,
    this.minExtendedWidth = 256.0,
    this.extended = false,
    this.groupAlignment = -1.0,
    this.labelType,
    this.color,
    this.elevation,
    this.slots = const [],
    this.nativeConfig,
    this.onNativeSlotAdded,
    super.key,
  }) : assert(width > 0 && width < double.infinity),
       assert(minExtendedWidth > 0 && minExtendedWidth < double.infinity),
       assert(selectedIndex >= 0);

  final String id;
  final String label;

  /// Shorthand for a single destination or the first destination entry.
  final SuperAction? destination;
  final List<SuperAction> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final double width;
  final double minExtendedWidth;
  final bool extended;
  final double groupAlignment;
  final NavigationRailLabelType? labelType;
  final Color? color;
  final double? elevation;
  final List<SlotImplementation> slots;
  final NativeComponentConfig? nativeConfig;
  final NativeSlotAddedCallback? onNativeSlotAdded;

  List<SuperAction> get _allDestinations => [?destination, ...destinations];

  NativeComponentConfig get _initialConfig =>
      nativeConfig ??
      NativeComponentConfig(
        regions: const {'destinations': true},
        placements: {
          if (_allDestinations.isNotEmpty)
            'destinations': [for (final item in _allDestinations) item.id],
        },
      );

  double get _currentWidth => extended ? minExtendedWidth : width;

  @override
  Size get preferredSize => Size.fromWidth(_currentWidth);

  @override
  Size preferredSizeIn(BuildContext context) =>
      Size.fromWidth(_currentWidth + MediaQuery.paddingOf(context).left);

  ValueNotifier<NativeComponentConfig>? _controller(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    return registry?.nativeComponentController(id, fallback: _initialConfig);
  }

  @override
  Listenable? sizeListenable(BuildContext context) => null;

  @override
  State<SuperNavigationRail> createState() => _SuperNavigationRailState();
}

class _SuperNavigationRailState extends State<SuperNavigationRail> {
  late final _localConfig = ValueNotifier(widget._initialConfig);
  late int _selectedIndex = widget.selectedIndex;

  @override
  void didUpdateWidget(SuperNavigationRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _selectedIndex = widget.selectedIndex;
    }
  }

  Map<String, SuperAction> get _suppliedActions => {
    for (final action in widget._allDestinations) action.id: action,
  };

  List<SlotImplementation> get _slots => [
    for (final action in widget._allDestinations)
      BuilderSlot(
        id: action.id,
        label: action.config.label,
        tags: const {'action', 'button', 'input'},
        sizing: SlotSizing.intrinsic,
        builder: (_) => action,
      ),
    ...widget.slots,
  ];

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

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final controller = widget._controller(context) ?? _localConfig;
    final currentWidth = widget._currentWidth;
    final regions = [
      NativeRegion(
        'destinations',
        'Destinations',
        axis: Axis.vertical,
        expand: true,
        emptySize: Size(currentWidth, 120),
        tagFilter: const ComponentTagFilter(include: {'action'}),
      ),
    ];

    return ValueListenableBuilder<NativeComponentConfig>(
      valueListenable: controller,
      builder: (context, config, _) => NativeComponentEditor(
        label: widget.label,
        menuType: 'NavigationRail',
        keyPrefix: 'super-navigation-rail',
        settingsTitle: 'Configurer le rail de navigation',
        editSurface: true,
        config: config,
        onChanged: (value) => controller.value = value,
        registry: registry,
        slots: _slots,
        onSlotAdded: _added,
        regions: regions,
        builder: (context, editor) {
          if (!editor.visible('destinations')) {
            return const SizedBox.shrink();
          }
          final slots = editor.slotsFor('destinations');
          final supplied = _suppliedActions;
          if (slots.isEmpty) {
            return Material(
              color: widget.color ?? Theme.of(context).colorScheme.surface,
              elevation: widget.elevation ?? 0,
              child: SizedBox(
                width: currentWidth,
                child: SafeArea(
                  right: false,
                  child: editor.region('destinations'),
                ),
              ),
            );
          }
          return ListenableBuilder(
            listenable: Listenable.merge([
              for (final slot in slots)
                if (registry != null)
                  registry.actionController(
                    slot.id,
                    fallback:
                        supplied[slot.id]?.config ?? const SuperActionConfig(),
                  ),
            ]),
            builder: (context, _) {
              final effectiveIndex = _selectedIndex.clamp(0, slots.length - 1);
              final effectiveLabelType =
                  widget.labelType ??
                  (widget.extended
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all);
              final railDestinations = [
                for (final slot in slots)
                  () {
                    final fallback =
                        supplied[slot.id]?.config ?? const SuperActionConfig();
                    final actionConfig =
                        registry
                            ?.actionController(slot.id, fallback: fallback)
                            .value ??
                        fallback;
                    return NavigationRailDestination(
                      icon: SuperActionNavigationScope(
                        part: SuperActionNavigationPart.icon,
                        child: editor.slotItem('destinations', slot),
                      ),
                      label: Text(
                        actionConfig.label,
                        key: ValueKey('super-action-label-${slot.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: actionConfig.fontFamily,
                          fontSize: actionConfig.fontSize,
                          fontWeight: actionConfig.fontWeight,
                          fontStyle: actionConfig.italic == null
                              ? null
                              : (actionConfig.italic!
                                    ? FontStyle.italic
                                    : FontStyle.normal),
                          color: actionConfig.color,
                          letterSpacing: actionConfig.letterSpacing,
                        ),
                      ),
                      disabled: !actionConfig.enabled,
                    );
                  }(),
              ];
              return editor.region(
                'destinations',
                child: NavigationRail(
                  selectedIndex: effectiveIndex,
                  extended: widget.extended,
                  minWidth: widget.width,
                  minExtendedWidth: widget.minExtendedWidth,
                  groupAlignment: widget.groupAlignment,
                  labelType: effectiveLabelType,
                  backgroundColor: widget.color ?? Colors.transparent,
                  elevation: widget.elevation,
                  destinations: railDestinations,
                  onDestinationSelected: (index) {
                    final slot = slots[index];
                    final action = supplied[slot.id];
                    final fallback =
                        action?.config ?? const SuperActionConfig();
                    final actionConfig =
                        registry
                            ?.actionController(slot.id, fallback: fallback)
                            .value ??
                        fallback;
                    if (!actionConfig.enabled) return;
                    setState(() => _selectedIndex = index);
                    widget.onDestinationSelected?.call(index);
                    executeSuperActionClick(
                      context,
                      slot.id,
                      onPressed: action?.onPressed,
                    );
                  },
                ),
              );
            },
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
