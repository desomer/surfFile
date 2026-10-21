import 'package:material_ui/material_ui.dart';

import '../../models/super_layout_config.dart';
import '../../super_app.dart';
import '../../theme/container_style.dart';
import '../editing/slots/editable_surface.dart';
import 'slot_implementation.dart';
import 'super_layout.dart';

/// A reusable styled surface with a structural, editable layout.
class IterableContent extends StatefulWidget {
  const IterableContent({
    this.id,
    this.label = 'IterableContent',
    this.config = const SuperLayoutConfig(),
    this.style = const ContainerStyle(),
    this.slots = const [],
    this.onChanged,
    this.onStyleChanged,
    this.editable = true,
    super.key,
  });

  final String? id;
  final String label;
  final SuperLayoutConfig config;
  final ContainerStyle style;
  final List<SlotImplementation> slots;
  final ValueChanged<SuperLayoutConfig>? onChanged;
  final ValueChanged<ContainerStyle>? onStyleChanged;
  final bool editable;

  @override
  State<IterableContent> createState() => _IterableContentState();
}

class _IterableContentState extends State<IterableContent> {
  late final _layout = ValueNotifier(widget.config);
  late final _style = ValueNotifier(widget.style);

  @override
  void didUpdateWidget(IterableContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.config != widget.config) {
      _layout.value = widget.config;
    }
    if (oldWidget.id != widget.id || oldWidget.style != widget.style) {
      _style.value = widget.style;
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final id = widget.id;
    final layout = id == null
        ? _layout
        : registry?.layoutController(id, fallback: widget.config) ?? _layout;
    final style = id == null
        ? _style
        : registry?.styleController(id, fallback: widget.style) ?? _style;
    return ValueListenableBuilder<ContainerStyle>(
      valueListenable: style,
      builder: (context, value, _) => EditableSurface(
        label: widget.label,
        menuType: 'IterableContent',
        menuIcon: Icons.article_outlined,
        editable: widget.editable,
        fallbackColor: Colors.transparent,
        style: value,
        onStyleChanged: (next) {
          style.value = next;
          widget.onStyleChanged?.call(next);
        },
        child: ValueListenableBuilder<SuperLayoutConfig>(
          valueListenable: layout,
          builder: (context, config, _) => SuperLayout(
            label: 'Layout',
            config: config,
            slots: widget.slots,
            editable: widget.editable,
            menuIcon: Icons.dashboard_outlined,
            onChanged: (next) {
              layout.value = next;
              widget.onChanged?.call(next);
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _layout.dispose();
    _style.dispose();
    super.dispose();
  }
}
