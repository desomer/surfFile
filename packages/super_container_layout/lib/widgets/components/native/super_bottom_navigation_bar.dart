import 'package:material_ui/material_ui.dart';

import '../../../models/component_tag_filter.dart';
import '../../../models/native_component_config.dart';
import '../../../models/super_action_config.dart';
import '../../../super_app.dart';
import '../../editing/components/native_component_editor.dart';
import '../super_action.dart';
import '../super_layout/slot_implementation.dart';

/// A native [BottomNavigationBar] whose items are exclusively [SuperAction]
/// components converted into [BottomNavigationBarItem] entries.
class SuperBottomNavigationBar extends StatefulWidget
    implements NativePreferredSizeWidget {
  const SuperBottomNavigationBar({
    this.id = 'root-bottomNavigationBar',
    this.label = 'Barre de navigation',
    this.destination,
    this.destinations = const [],
    this.currentIndex = 0,
    this.onTap,
    this.height = kBottomNavigationBarHeight,
    this.color,
    this.elevation,
    this.type,
    this.slots = const [],
    this.nativeConfig,
    this.onNativeSlotAdded,
    super.key,
  }) : assert(height > 0 && height < double.infinity),
       assert(currentIndex >= 0);

  final String id;
  final String label;

  /// Shorthand for a single destination or the first destination entry.
  final SuperAction? destination;
  final List<SuperAction> destinations;
  final int currentIndex;
  final ValueChanged<int>? onTap;
  final double height;
  final Color? color;
  final double? elevation;
  final BottomNavigationBarType? type;
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

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Size preferredSizeIn(BuildContext context) =>
      Size.fromHeight(height + MediaQuery.paddingOf(context).bottom);

  @override
  Listenable? sizeListenable(BuildContext context) => null;

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
    final controller =
        registry?.nativeComponentController(
          widget.id,
          fallback: widget._initialConfig,
        ) ??
        _localConfig;
    return ValueListenableBuilder<NativeComponentConfig>(
      valueListenable: controller,
      builder: (context, config, _) => NativeComponentEditor(
        label: widget.label,
        menuType: 'BottomNavigationBar',
        keyPrefix: 'super-bottom-navigation-bar',
        settingsTitle: 'Configurer la barre de navigation',
        editSurface: true,
        config: config,
        onChanged: (value) => controller.value = value,
        registry: registry,
        slots: _slots,
        onSlotAdded: _added,
        regions: const [
          NativeRegion(
            'destinations',
            'Destinations',
            axis: Axis.horizontal,
            tagFilter: ComponentTagFilter(include: {'action'}),
          ),
        ],
        builder: (context, editor) {
          if (!editor.visible('destinations')) {
            return const SizedBox.shrink();
          }
          final slots = editor.slotsFor('destinations');
          final supplied = _suppliedActions;
          if (slots.length < 2) {
            return Material(
              color: widget.color ?? Theme.of(context).colorScheme.surface,
              elevation: widget.elevation ?? 8.0,
              child: SizedBox(
                height: widget.height,
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
                        supplied[slot.id]?.config ?? const SuperActionConfig(),
                  ),
            ]),
            builder: (context, _) {
              final effectiveIndex = _selectedIndex.clamp(0, slots.length - 1);
              final items = [
                for (final slot in slots)
                  () {
                    final fallback =
                        supplied[slot.id]?.config ?? const SuperActionConfig();
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
              return editor.region(
                'destinations',
                child: BottomNavigationBar(
                  currentIndex: effectiveIndex,
                  backgroundColor: widget.color,
                  elevation: widget.elevation,
                  type: widget.type,
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
