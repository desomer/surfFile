import 'package:material_ui/material_ui.dart';

import '../../../models/native_component_config.dart';
import '../../../super_app.dart';
import '../../editing/components/native_component_editor.dart';
import '../super_layout/slot_implementation.dart';

/// A native NavigationRail with three editable, vertical regions:
/// [leading], [destinations], and [trailing].
///
/// Navigation state and callbacks belong to the supplied widgets.
class SuperNavigationRail extends StatefulWidget
    implements NativePreferredSizeWidget {
  const SuperNavigationRail({
    this.id = 'root-navigationRail',
    this.label = 'Rail de navigation',
    this.leading,
    this.destination,
    this.destinations = const [],
    this.trailing,
    this.width = 72.0,
    this.minExtendedWidth = 256.0,
    this.extended = false,
    this.groupAlignment = -1.0,
    this.color,
    this.elevation,
    this.slots = const [],
    this.nativeConfig,
    this.onNativeSlotAdded,
    super.key,
  }) : assert(width > 0 && width < double.infinity),
       assert(minExtendedWidth > 0 && minExtendedWidth < double.infinity);

  final String id;
  final String label;
  final Widget? leading;

  /// Shorthand for a single destination or the first destination entry.
  final Widget? destination;
  final List<Widget> destinations;
  final Widget? trailing;
  final double width;
  final double minExtendedWidth;
  final bool extended;
  final double groupAlignment;
  final Color? color;
  final double? elevation;
  final List<SlotImplementation> slots;
  final NativeComponentConfig? nativeConfig;
  final NativeSlotAddedCallback? onNativeSlotAdded;

  NativeComponentConfig get _initialConfig =>
      nativeConfig ??
      NativeComponentConfig(
        regions: const {
          'leading': true,
          'destinations': true,
          'trailing': true,
        },
        placements: {
          if (leading != null) 'leading': ['leading'],
          if (destination != null || destinations.isNotEmpty)
            'destinations': [
              if (destination != null) 'destination',
              for (var i = 0; i < destinations.length; i++) 'destination:$i',
            ],
          if (trailing != null) 'trailing': ['trailing'],
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

  List<SlotImplementation> get _slots => [
    if (widget.leading case final child?)
      BuilderSlot(id: 'leading', label: 'leading', builder: (_) => child),
    if (widget.destination case final child?)
      BuilderSlot(
        id: 'destination',
        label: 'destination',
        sizing: SlotSizing.intrinsic,
        builder: (_) => child,
      ),
    for (final (index, child) in widget.destinations.indexed)
      BuilderSlot(
        id: 'destination:$index',
        label: 'destination ${index + 1}',
        sizing: SlotSizing.intrinsic,
        builder: (_) => child,
      ),
    if (widget.trailing case final child?)
      BuilderSlot(id: 'trailing', label: 'trailing', builder: (_) => child),
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
        'leading',
        'En-tête',
        axis: Axis.vertical,
        expand: false,
        emptySize: Size(currentWidth, 56),
      ),
      NativeRegion(
        'destinations',
        'Destinations',
        axis: Axis.vertical,
        expand: true,
        emptySize: Size(currentWidth, 120),
      ),
      NativeRegion(
        'trailing',
        'Pied de page',
        axis: Axis.vertical,
        expand: false,
        emptySize: Size(currentWidth, 56),
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
        builder: (context, editor) => Material(
          color: widget.color ?? Theme.of(context).colorScheme.surface,
          elevation: widget.elevation ?? 0,
          child: SizedBox(
            width: currentWidth,
            child: SafeArea(
              right: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (editor.visible('leading')) editor.region('leading'),
                  if (editor.visible('destinations'))
                    Expanded(
                      child: Align(
                        alignment: Alignment(0.0, widget.groupAlignment),
                        child: editor.region('destinations'),
                      ),
                    )
                  else if (editor.visible('leading') &&
                      editor.visible('trailing'))
                    const Spacer(),
                  if (editor.visible('trailing')) editor.region('trailing'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _localConfig.dispose();
    super.dispose();
  }
}
