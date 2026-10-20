import 'package:material_ui/material_ui.dart';

import '../../theme/appearance.dart';
import '../../theme/appearance_slot.dart';
import '../../theme/container_style.dart';
import 'styled_surface.dart';

/// A styled surface renderer.
///
/// Editing behavior belongs to [EditorSlot] and [EditableSurface]. This
/// widget only reads the supplied style (or its appearance slot) and renders
/// decoration, padding, and margins.
class SuperContainer extends StatefulWidget {
  const SuperContainer({
    this.child,
    this.slot,
    this.style = const ContainerStyle(),
    this.fallbackColor,
    this.borderColor,
    this.padding,
    this.horizontalBorder = false,
    this.decorate = true,
    this.applyPadding,
    super.key,
  });

  final Widget? child;
  final AppearanceSlot? slot;
  final ContainerStyle style;
  final Color? fallbackColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final bool horizontalBorder;

  /// When false, render the child without a [StyledSurface].
  ///
  /// Padding and margins remain active, allowing undecorated surfaces to
  /// retain their layout behavior.
  final bool decorate;

  /// Applies the style's content padding. By default this follows [decorate].
  final bool? applyPadding;

  @override
  State<SuperContainer> createState() => _SuperContainerState();
}

class _SuperContainerState extends State<SuperContainer> {
  late final ValueNotifier<ContainerStyle> _local =
      ValueNotifier(widget.style);

  ValueNotifier<Appearance>? get _appearance =>
      widget.slot == null ? null : AppearanceScope.controllerOf(context);

  ContainerStyle get style {
    final appearance = _appearance;
    return appearance == null
        ? _local.value
        : widget.slot!.read(appearance.value);
  }

  @override
  void didUpdateWidget(SuperContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) _local.value = widget.style;
  }

  @override
  void dispose() {
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenable = _appearance ?? _local;
    Widget content = widget.child ?? const SizedBox.expand();
    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }
    if (widget.applyPadding ?? widget.decorate) {
      content = ListenableBuilder(
        listenable: listenable,
        builder: (context, child) =>
            Padding(padding: style.contentPadding, child: child),
        child: content,
      );
    }
    if (widget.decorate) {
      content = ListenableBuilder(
        listenable: listenable,
        builder: (context, child) => StyledSurface(
          style: style,
          fallbackColor:
              widget.fallbackColor ??
              Theme.of(context).colorScheme.surfaceContainerLow,
          borderColor:
              widget.borderColor ??
              Theme.of(context).colorScheme.outlineVariant,
          horizontalBorder: widget.horizontalBorder,
          child: child!,
        ),
        child: content,
      );
    }
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, child) =>
          Padding(padding: style.outerMargin, child: child),
      child: content,
    );
  }
}
