import 'package:material_ui/material_ui.dart';

import '../../models/native_component_config.dart';
import '../../super_app.dart';
import 'native_component_editor.dart';
import '../super_layout/slot_implementation.dart';

/// A native BottomAppBar with three editable, free-widget regions.
///
/// Navigation state and callbacks belong to the supplied widgets.
class SuperBottomNavigationBar extends StatefulWidget
    implements NativePreferredSizeWidget {
  const SuperBottomNavigationBar({
    this.id = 'root-bottomNavigationBar',
    this.label = 'Barre basse',
    this.left,
    this.center,
    this.right,
    this.height = kBottomNavigationBarHeight,
    this.color,
    this.elevation,
    this.slots = const [],
    this.nativeConfig,
    this.onNativeSlotAdded,
    super.key,
  }) : assert(height > 0 && height < double.infinity);

  final String id;
  final String label;
  final Widget? left;
  final Widget? center;
  final Widget? right;
  final double height;
  final Color? color;
  final double? elevation;
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
        menuType: 'SuperBottomNavigationBar',
        keyPrefix: 'super-bottom-navigation-bar',
        settingsTitle: 'Configurer la barre basse',
        editSurface: true,
        config: config,
        onChanged: (value) => controller.value = value,
        registry: registry,
        slots: _slots,
        onSlotAdded: widget.onNativeSlotAdded,
        regions: const [
          NativeRegion('left', 'Gauche', axis: Axis.horizontal),
          NativeRegion('center', 'Centre', axis: Axis.horizontal),
          NativeRegion('right', 'Droite', axis: Axis.horizontal),
        ],
        builder: (context, editor) => BottomAppBar(
          height: widget.height,
          padding: EdgeInsets.zero,
          color: widget.color,
          elevation: widget.elevation,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final region in ['left', 'center', 'right'])
                if (editor.visible(region))
                  Expanded(child: editor.region(region)),
            ],
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
