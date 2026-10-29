import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart';
import '../../../services/states/content_hover_scope.dart';
import '../../../super_app.dart';
import '../../../theme/container_style.dart';
import '../../editing/slots/editable_surface.dart';
import '../../editing/slots/editor_slot.dart';
import 'slot_implementation.dart';
import 'super_layout.dart';

/// A reusable styled surface with a structural, editable layout.
class IterableContent extends StatefulWidget {
  const IterableContent({
    this.id,
    this.label = 'Iterable Content',
    this.config = const SuperLayoutConfig(),
    this.style = const ContainerStyle(),
    this.slots = const [],
    this.onChanged,
    this.onStyleChanged,
    this.editable = true,
    this.shrinkWrap = false,
    this.resolveSelectionAndHover = true,
    this.onEditSize,
    this.sizeConstraints,
    this.child,
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
  final bool shrinkWrap;
  final bool resolveSelectionAndHover;
  final Future<void> Function()? onEditSize;
  final SlotSizeConstraints? sizeConstraints;
  final Widget? child;

  @override
  State<IterableContent> createState() => _IterableContentState();
}

class _IterableContentState extends State<IterableContent> {
  final _hovered = ValueNotifier(false);
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
    final customChild = widget.child;
    final layout = customChild != null || id == null
        ? _layout
        : registry?.layoutController(id, fallback: widget.config) ?? _layout;
    final style = id == null
        ? _style
        : registry?.styleController(id, fallback: widget.style) ?? _style;

    final surface = ValueListenableBuilder<ContainerStyle>(
      valueListenable: style,
      builder: (context, value, _) => EditableSurface(
        id: widget.id,
        singleChild: false,
        label: widget.label,
        menuType: 'IterableContent',
        menuIcon: Icons.loop,
        editable: widget.editable,
        resolveSelectionAndHover: widget.resolveSelectionAndHover,
        fallbackColor: Colors.transparent,
        style: value,
        onStyleChanged: (next) {
          style.value = next;
          widget.onStyleChanged?.call(next);
        },
        child:
            customChild ??
            ValueListenableBuilder<SuperLayoutConfig>(
              valueListenable: layout,
              builder: (context, config, _) => SuperLayout(
                label: 'Layout',
                id: widget.id == null
                    ? null
                    : (widget.id!.endsWith(':item')
                          ? '${widget.id!.substring(0, widget.id!.length - 5)}:layout'
                          : '${widget.id}:layout'),
                config: config,
                slots: widget.slots,
                editable: widget.editable,
                shrinkWrap: widget.shrinkWrap,
                menuIcon: Icons.dashboard_outlined,
                onChanged: (next) {
                  layout.value = next;
                  widget.onChanged?.call(next);
                },
              ),
            ),
      ),
    );
    final editSize = widget.onEditSize;
    final actionLabel = 'Taille et marge préférées : ${widget.label}';
    final content = editSize == null
        ? surface
        : EditorSlotAction(
            label: actionLabel,
            tooltip: formatSlotSizeTooltip(
              title: actionLabel,
              constraints: widget.sizeConstraints,
            ),
            onEdit: editSize,
            enabled:
                widget.editable &&
                (StyleEditScope.controllerOf(context)?.value ?? true),
            inline: true,
            child: surface,
          );
    return ContentHoverScope(
      hovered: _hovered,
      child: MouseRegion(
        opaque: false,
        onEnter: (_) => _hovered.value = true,
        onExit: (_) => _hovered.value = false,
        child: content,
      ),
    );
  }

  @override
  void dispose() {
    _layout.dispose();
    _style.dispose();
    _hovered.dispose();
    super.dispose();
  }
}
