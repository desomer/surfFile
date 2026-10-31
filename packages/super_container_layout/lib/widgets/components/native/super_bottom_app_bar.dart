import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/native_component_config.dart';
import '../../../models/native_property_descriptor.dart';
import '../../../super_app.dart';
import '../../../theme/appearance.dart';
import '../../editing/components/native_component_editor.dart';
import '../super_layout/slot_implementation.dart';
import 'native_component_common.dart';

/// A native BottomAppBar with three editable, free-widget regions.
///
/// Navigation state and callbacks belong to the supplied widgets.
class SuperBottomAppBar extends StatefulWidget
    implements NativePreferredSizeWidget {
  static const List<NativePropertyDescriptor> propertyDescriptors =
      superBottomAppBarPropertyDescriptors;

  const SuperBottomAppBar({
    this.id = 'root-bottomAppBar',
    this.label = 'Barre basse',
    this.left,
    this.center,
    this.right,
    this.height = kBottomNavigationBarHeight,
    this.color,
    this.surfaceTintColor,
    this.shadowColor,
    this.elevation,
    this.shape,
    this.clipBehavior,
    this.notchMargin = 4.0,
    this.padding,
    this.slots = const [],
    this.nativeConfig,
    this.onNativeSlotAdded,
    super.key,
  }) : assert(height > 0 && height < double.infinity),
       assert(elevation == null || elevation >= 0.0),
       assert(notchMargin >= 0.0);

  final String id;
  final String label;
  final Widget? left;
  final Widget? center;
  final Widget? right;
  final double height;
  final Color? color;
  final Color? surfaceTintColor;
  final Color? shadowColor;
  final double? elevation;
  final NotchedShape? shape;
  final Clip? clipBehavior;
  final double notchMargin;
  final EdgeInsetsGeometry? padding;
  final List<SlotImplementation> slots;
  final NativeComponentConfig? nativeConfig;
  final NativeSlotAddedCallback? onNativeSlotAdded;

  NativeComponentConfig get _initialConfig =>
      nativeConfig ??
      NativeComponentConfig(
        regions: const {'left': true, 'center': true, 'right': true},
        placements: {
          if (left != null) 'left': ['left'],
          if (center != null) 'center': ['center'],
          if (right != null) 'right': ['right'],
        },
      );

  double _height(NativeComponentConfig config) {
    if (config.doubleProperty('height') case final h?) return h;
    final regionHeights = [
      for (final id in const ['left', 'center', 'right'])
        if (config.isEnabled(id)) ?config.regionSizeOf(id),
    ];
    if (regionHeights.isNotEmpty) {
      return regionHeights.reduce(math.max);
    }
    return height;
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
  State<SuperBottomAppBar> createState() => _SuperBottomAppBarState();
}

class _SuperBottomAppBarState extends State<SuperBottomAppBar> {
  late final _localConfig = ValueNotifier(widget._initialConfig);

  Clip? _clipBehavior(NativeComponentConfig config) =>
      switch (config.stringProperty('clipBehavior')) {
        'none' => Clip.none,
        'hardEdge' => Clip.hardEdge,
        'antiAlias' => Clip.antiAlias,
        'antiAliasWithSaveLayer' => Clip.antiAliasWithSaveLayer,
        _ => null,
      };

  List<NativeRegion> _regions(
    NativeComponentConfig config,
    double effectiveHeight,
  ) {
    return [
      NativeRegion(
        'left',
        'Gauche',
        axis: Axis.horizontal,
        editableFlow: true,
        emptySize: Size(double.infinity, effectiveHeight),
      ),
      NativeRegion(
        'center',
        'Centre',
        axis: Axis.horizontal,
        editableFlow: true,
        emptySize: Size(double.infinity, effectiveHeight),
      ),
      NativeRegion(
        'right',
        'Droite',
        axis: Axis.horizontal,
        editableFlow: true,
        emptySize: Size(double.infinity, effectiveHeight),
      ),
    ];
  }

  List<SlotImplementation> get _slots => [
    if (widget.left case final child?)
      BuilderSlot(id: 'left', label: 'Gauche', builder: (_) => child),
    if (widget.center case final child?)
      BuilderSlot(id: 'center', label: 'Centre', builder: (_) => child),
    if (widget.right case final child?)
      BuilderSlot(id: 'right', label: 'Droite', builder: (_) => child),
    ...widget.slots,
  ];

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
            menuType: 'BottomAppBar',
            keyPrefix: 'super-bottom-app-bar',
            settingsTitle: 'Configurer la barre basse',
            editSurface: true,
            config: config,
            onChanged: (value) => controller.value = value,
            registry: registry,
            slots: _slots,
            propertyDescriptors: SuperBottomAppBar.propertyDescriptors,
            onSlotAdded: widget.onNativeSlotAdded,
            regions: _regions(config, effectiveHeight),
            builder: (context, editor) {
              final shapeBorder = config.shapeBorderProperty('shape');
              final effectiveShape = shapeBorder != null
                  ? AutomaticNotchedShape(shapeBorder)
                  : widget.shape;
              final configPadding = config.doubleProperty('padding');
              final effectivePadding = configPadding != null
                  ? EdgeInsets.all(configPadding)
                  : (widget.padding ?? EdgeInsets.zero);
              Widget bar = BottomAppBar(
                height: effectiveHeight,
                padding: effectivePadding,
                color:
                    config.colorProperty('color') ??
                    config.colorProperty('backgroundColor') ??
                    widget.color,
                surfaceTintColor:
                    config.colorProperty('surfaceTintColor') ??
                    widget.surfaceTintColor,
                shadowColor:
                    config.colorProperty('shadowColor') ?? widget.shadowColor,
                elevation:
                    config.doubleProperty('elevation') ?? widget.elevation,
                shape: effectiveShape,
                clipBehavior:
                    _clipBehavior(config) ?? widget.clipBehavior ?? Clip.none,
                notchMargin:
                    config.doubleProperty('notchMargin') ?? widget.notchMargin,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final region in ['left', 'center', 'right'])
                      if (editor.visible(region))
                        Expanded(child: editor.region(region)),
                  ],
                ),
              );
              if (shapeBorder != null) {
                bar = ClipPath(
                  clipper: ShapeBorderClipper(shape: shapeBorder),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: ShapeDecoration(shape: shapeBorder),
                    child: bar,
                  ),
                );
              }
              return bar;
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
