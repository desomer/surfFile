import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/component_tag_filter.dart';
import '../../../models/native_component_config.dart';
import '../../../models/native_property_descriptor.dart';
import '../../../models/super_action_config.dart';
import '../../../super_app.dart';
import '../../../theme/appearance.dart';
import '../../editing/components/native_component_editor.dart';
import '../super_action.dart';
import '../super_layout/slot_implementation.dart';
import 'native_component_common.dart';

/// A native [BottomNavigationBar] whose items are exclusively [SuperAction]
/// components converted into [BottomNavigationBarItem] entries.
class SuperBottomNavigationBar extends StatefulWidget
    implements NativePreferredSizeWidget {
  static const List<NativePropertyDescriptor> propertyDescriptors =
      superBottomNavigationBarPropertyDescriptors;

  const SuperBottomNavigationBar({
    this.id = 'root-bottomNavigationBar',
    this.label = 'Barre de navigation',
    this.destination,
    this.destinations = const [],
    this.currentIndex = 0,
    this.onTap,
    this.height = kBottomNavigationBarHeight,
    this.color,
    this.backgroundColor,
    this.selectedItemColor,
    this.fixedColor,
    this.unselectedItemColor,
    this.elevation,
    this.type,
    this.landscapeLayout,
    this.iconSize = 24.0,
    this.selectedFontSize = 14.0,
    this.unselectedFontSize = 12.0,
    this.selectedIconTheme,
    this.unselectedIconTheme,
    this.selectedLabelStyle,
    this.unselectedLabelStyle,
    this.showSelectedLabels,
    this.showUnselectedLabels,
    this.mouseCursor,
    this.enableFeedback,
    this.useLegacyColorScheme = true,
    this.slots = const [],
    this.nativeConfig,
    this.onNativeSlotAdded,
    super.key,
  }) : assert(height > 0 && height < double.infinity),
       assert(currentIndex >= 0),
       assert(elevation == null || elevation >= 0.0),
       assert(iconSize >= 0.0),
       assert(selectedFontSize >= 0.0),
       assert(unselectedFontSize >= 0.0),
       assert(
         selectedItemColor == null || fixedColor == null,
         'Either selectedItemColor or fixedColor can be specified, but not both.',
       );

  final String id;
  final String label;

  /// Shorthand for a single destination or the first destination entry.
  final SuperAction? destination;
  final List<SuperAction> destinations;
  final int currentIndex;
  final ValueChanged<int>? onTap;
  final double height;
  final Color? color;
  final Color? backgroundColor;
  final Color? selectedItemColor;
  final Color? fixedColor;
  final Color? unselectedItemColor;
  final double? elevation;
  final BottomNavigationBarType? type;
  final BottomNavigationBarLandscapeLayout? landscapeLayout;
  final double iconSize;
  final double selectedFontSize;
  final double unselectedFontSize;
  final IconThemeData? selectedIconTheme;
  final IconThemeData? unselectedIconTheme;
  final TextStyle? selectedLabelStyle;
  final TextStyle? unselectedLabelStyle;
  final bool? showSelectedLabels;
  final bool? showUnselectedLabels;
  final MouseCursor? mouseCursor;
  final bool? enableFeedback;
  final bool useLegacyColorScheme;
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

  double _height(NativeComponentConfig config) {
    if (config.doubleProperty('height') case final h?) return h;
    if (config.regionSizeOf('destinations') case final h?) return h;
    final effectiveIconSize = config.doubleProperty('iconSize') ?? iconSize;
    final effectiveSelectedFontSize =
        config.doubleProperty('selectedFontSize') ?? selectedFontSize;
    return math.max(
      height,
      effectiveIconSize + effectiveSelectedFontSize * 2.0 + 4.0,
    );
  }

  ValueNotifier<NativeComponentConfig>? _controller(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    return registry?.nativeComponentController(id, fallback: _initialConfig);
  }

  @override
  Size get preferredSize => Size.fromHeight(_height(_initialConfig));

  @override
  Size preferredSizeIn(BuildContext context) {
    final config =
        _controller(context)?.value ??
        AppearanceScope.of(context)
            .nativeComponent(id, fallback: _initialConfig);
    return Size.fromHeight(
      _height(config) + MediaQuery.paddingOf(context).bottom,
    );
  }

  @override
  Listenable? sizeListenable(BuildContext context) => _controller(context);

  @override
  State<SuperBottomNavigationBar> createState() =>
      _SuperBottomNavigationBarState();
}

class _SuperBottomNavigationBarState extends State<SuperBottomNavigationBar> {
  late final _localConfig = ValueNotifier(widget._initialConfig);
  late int _selectedIndex = widget.currentIndex;

  @override
  void didUpdateWidget(SuperBottomNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      _selectedIndex = widget.currentIndex;
    }
  }

  BottomNavigationBarType? _barType(NativeComponentConfig config) =>
      switch (config.stringProperty('navigationBarType') ??
      config.stringProperty('type')) {
        'fixed' => BottomNavigationBarType.fixed,
        'shifting' => BottomNavigationBarType.shifting,
        _ => widget.type,
      };

  BottomNavigationBarLandscapeLayout? _landscapeLayout(
    NativeComponentConfig config,
  ) => switch (config.stringProperty('landscapeLayout')) {
    'spread' => BottomNavigationBarLandscapeLayout.spread,
    'centered' => BottomNavigationBarLandscapeLayout.centered,
    'linear' => BottomNavigationBarLandscapeLayout.linear,
    _ => widget.landscapeLayout,
  };

  MouseCursor? _mouseCursor(NativeComponentConfig config) =>
      switch (config.stringProperty('mouseCursor')) {
        'click' || 'clickable' => SystemMouseCursors.click,
        'basic' => SystemMouseCursors.basic,
        'defer' => MouseCursor.defer,
        'none' => SystemMouseCursors.none,
        _ => widget.mouseCursor,
      };

  Map<String, SuperAction> get _suppliedActions =>
      suppliedActionDestinationMap(widget._allDestinations);

  List<SlotImplementation> get _slots =>
      buildActionDestinationSlots(widget._allDestinations, widget.slots);

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
    return ValueListenableBuilder<NativeComponentConfig>(
      valueListenable: controller,
      builder: (context, config, _) => LayoutBuilder(
        builder: (context, constraints) {
          final baseHeight = widget._height(config);
          final bottomPadding = MediaQuery.paddingOf(context).bottom;
          final (:targetHeight, :effectiveHeight) = resolveBottomBarHeights(
            constraints,
            baseHeight,
            bottomPadding,
          );
          return NativeComponentEditor(
            id: widget.id,
            label: widget.label,
            menuType: 'BottomNavigationBar',
            keyPrefix: 'super-bottom-navigation-bar',
            settingsTitle: 'Configurer la barre de navigation',
            editSurface: true,
            config: config,
            onChanged: (value) => controller.value = value,
            registry: registry,
            slots: _slots,
            propertyDescriptors:
                SuperBottomNavigationBar.propertyDescriptors,
            onSlotAdded: _added,
            regions: [
              NativeRegion(
                'destinations',
                'Destinations',
                axis: Axis.horizontal,
                emptySize: Size(double.infinity, effectiveHeight),
                tagFilter: const ComponentTagFilter(include: {'action'}),
              ),
            ],
            builder: (context, editor) {
              if (!editor.visible('destinations')) {
                return const SizedBox.shrink();
              }
              final slots = editor.slotsFor('destinations');
              final supplied = _suppliedActions;
              final effectiveBackgroundColor =
                  config.colorProperty('backgroundColor') ??
                  config.colorProperty('color') ??
                  widget.backgroundColor ??
                  widget.color;
              final effectiveElevation =
                  config.doubleProperty('elevation') ?? widget.elevation;
              if (slots.length < 2) {
                return Material(
                  color:
                      effectiveBackgroundColor ??
                      Theme.of(context).colorScheme.surface,
                  elevation: effectiveElevation ?? 8.0,
                  child: SizedBox(
                    height: effectiveHeight,
                    child: editor.region('destinations'),
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
                            supplied[slot.id]?.config ??
                            const SuperActionConfig(),
                      ),
                ]),
                builder: (context, _) {
                  final effectiveIndex = _selectedIndex.clamp(
                    0,
                    slots.length - 1,
                  );
                  final items = [
                    for (final slot in slots)
                      () {
                        final fallback =
                            supplied[slot.id]?.config ??
                            const SuperActionConfig();
                        final actionConfig =
                            registry
                                ?.actionController(slot.id, fallback: fallback)
                                .value ??
                            fallback;
                        return BottomNavigationBarItem(
                          icon: SuperActionNavigationScope(
                            part: SuperActionNavigationPart.icon,
                            child: editor.slotItem('destinations', slot),
                          ),
                          label: actionConfig.label,
                          tooltip: actionConfig.tooltip.trim().isNotEmpty
                              ? actionConfig.tooltip
                              : null,
                          backgroundColor:
                              actionConfig.backgroundColor ??
                              actionConfig.style.color,
                        );
                      }(),
                  ];
                  final effectiveSelectedItemColor =
                      config.colorProperty('selectedItemColor') ??
                      config.colorProperty('fixedColor') ??
                      widget.selectedItemColor ??
                      widget.fixedColor;
                  final effectiveUnselectedItemColor =
                      config.colorProperty('unselectedItemColor') ??
                      widget.unselectedItemColor;
                  final effectiveIconSize =
                      config.doubleProperty('iconSize') ?? widget.iconSize;
                  final effectiveSelectedFontSize =
                      config.doubleProperty('selectedFontSize') ??
                      widget.selectedFontSize;
                  final effectiveUnselectedFontSize =
                      config.doubleProperty('unselectedFontSize') ??
                      widget.unselectedFontSize;
                  final effectiveShowSelectedLabels =
                      config.boolProperty('showSelectedLabels') ??
                      widget.showSelectedLabels;
                  final effectiveShowUnselectedLabels =
                      config.boolProperty('showUnselectedLabels') ??
                      widget.showUnselectedLabels;
                  final effectiveEnableFeedback =
                      config.boolProperty('enableFeedback') ??
                      widget.enableFeedback;
                  final effectiveUseLegacyColorScheme =
                      config.boolProperty('useLegacyColorScheme') ??
                      widget.useLegacyColorScheme;
                  Widget navBar = BottomNavigationBar(
                    currentIndex: effectiveIndex,
                    backgroundColor: effectiveBackgroundColor,
                    selectedItemColor: effectiveSelectedItemColor,
                    unselectedItemColor: effectiveUnselectedItemColor,
                    elevation: effectiveElevation,
                    type: _barType(config),
                    landscapeLayout: _landscapeLayout(config),
                    iconSize: effectiveIconSize,
                    selectedFontSize: effectiveSelectedFontSize,
                    unselectedFontSize: effectiveUnselectedFontSize,
                    selectedIconTheme: widget.selectedIconTheme,
                    unselectedIconTheme: widget.unselectedIconTheme,
                    selectedLabelStyle: widget.selectedLabelStyle,
                    unselectedLabelStyle: widget.unselectedLabelStyle,
                    showSelectedLabels: effectiveShowSelectedLabels,
                    showUnselectedLabels: effectiveShowUnselectedLabels,
                    mouseCursor: _mouseCursor(config),
                    enableFeedback: effectiveEnableFeedback,
                    useLegacyColorScheme: effectiveUseLegacyColorScheme,
                    items: items,
                    onTap: (index) {
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
                      widget.onTap?.call(index);
                      executeSuperActionClick(
                        context,
                        slot.id,
                        onPressed: action?.onPressed,
                      );
                    },
                  );
                  if (effectiveHeight != kBottomNavigationBarHeight ||
                      config.doubleProperty('height') != null ||
                      widget.height != kBottomNavigationBarHeight) {
                    navBar = ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: effectiveHeight + bottomPadding,
                      ),
                      child: navBar,
                    );
                  }
                  return editor.region('destinations', child: navBar);
                },
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
