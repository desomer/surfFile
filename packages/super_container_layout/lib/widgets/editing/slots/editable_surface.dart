import 'package:material_ui/material_ui.dart';

import '../../../theme/appearance.dart';
import '../../../theme/appearance_slot.dart';
import '../../../theme/container_style.dart';
import '../../surfaces/super_container.dart';
import '../../super_layout/layout_selection.dart';
import '../styles/container_style_dialog.dart';
import 'editor_slot.dart';
import 'editable_single_child.dart';

/// Combines an [EditorSlot] with the style-rendering [SuperContainer].
///
/// It retains the former SuperContainer editing constructor API. Use
/// [EditorSlot] directly when only generic editing interactions are needed.
class EditableSurface extends StatefulWidget {
  const EditableSurface({
    this.child,
    this.id,
    this.slot,
    this.style = const ContainerStyle(),
    this.onStyleChanged,
    this.label,
    this.menuTitle,
    this.onLabelChanged,
    this.fallbackColor,
    this.borderColor,
    this.padding,
    this.horizontalBorder = false,
    this.decorate = true,
    this.applyPadding,
    this.editable = true,
    this.onEdit,
    this.onAdd,
    this.axisAction,
    this.menuSubtitle,
    this.menuType,
    this.onContextMenu,
    this.menuIcon,
    super.key,
  }) : assert(id == null || id != '');

  final Widget? child;

  /// Stable registry identity for an optional single catalog child.
  final String? id;
  final AppearanceSlot? slot;
  final ContainerStyle style;
  final ValueChanged<ContainerStyle>? onStyleChanged;
  final String? label;
  final String? menuTitle;
  final ValueChanged<String>? onLabelChanged;
  final Color? fallbackColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final bool horizontalBorder;

  /// Disables visual decoration while retaining style padding and margins.
  final bool decorate;
  final bool? applyPadding;
  final bool editable;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onAdd;
  final LayoutAxisAction Function()? axisAction;
  final String? Function()? menuSubtitle;
  final String? menuType;
  final ValueChanged<Offset>? onContextMenu;
  final IconData? menuIcon;

  @override
  EditableSurfaceState createState() => EditableSurfaceState();
}

class EditableSurfaceState extends State<EditableSurface> {
  final _editorKey = GlobalKey<EditorSlotState>();
  final _singleChildKey = GlobalKey<EditableSingleChildState>();
  late final ValueNotifier<ContainerStyle> _local = ValueNotifier(widget.style);
  String? _localLabel;

  /// Current local or AppearanceSlot-backed style.
  ContainerStyle get style {
    final appearance = _appearance;
    return appearance == null
        ? _local.value
        : widget.slot!.read(appearance.value);
  }

  /// The generic editor target composed by this surface.
  EditorSlotState get editor => _editorKey.currentState!;

  ValueNotifier<Appearance>? get _appearance =>
      widget.slot == null ? null : AppearanceScope.controllerOf(context);

  String get _label =>
      _localLabel ??
      widget.label ??
      widget.slot?.standard.label ??
      'Card';

  @override
  void didUpdateWidget(EditableSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) _local.value = widget.style;
    if (oldWidget.label != widget.label) _localLabel = null;
  }

  void _renameLabel(String value) {
    setState(() => _localLabel = value);
    widget.onLabelChanged?.call(value);
  }

  void _update(ContainerStyle value, {AppearanceSlot? slot}) {
    final appearance = _appearance;
    if (appearance != null) {
      appearance.value = (slot ?? widget.slot)!.write(appearance.value, value);
    } else {
      _local.value = value;
    }
    widget.onStyleChanged?.call(value);
  }

  void _reset({AppearanceSlot? slot}) {
    final appearance = _appearance;
    if (appearance != null) {
      appearance.value = (slot ?? widget.slot)!.reset(appearance.value);
      widget.onStyleChanged?.call(style);
    } else {
      _update(const ContainerStyle());
    }
  }

  Color _fallback(BuildContext context) =>
      widget.fallbackColor ?? Theme.of(context).colorScheme.surfaceContainerLow;

  Color _border(BuildContext context) =>
      widget.borderColor ?? Theme.of(context).colorScheme.outlineVariant;

  /// Opens the caller's custom editor or the shared style editor dialog.
  Future<void> openEditor() async {
    if (widget.onEdit != null) {
      await widget.onEdit!();
      return;
    }
    final appearance = _appearance;
    final initialAppearance = appearance?.value;
    final initialStyle = _local.value;
    final initialLabel = editor.label;
    final initialInstance = editor.componentLabel;
    final confirmed = await ContainerStyleDialog.show(
      context: context,
      label: initialLabel,
      slot: widget.slot,
      fallbackColor: _fallback(context),
      borderColor: _border(context),
      appearance: appearance,
      localStyle: _local,
      currentStyle: () => style,
      onStyleChanged: (value, slot) => _update(value, slot: slot),
      onReset: (slot) => _reset(slot: slot),
      onLabelChanged: (value) => editor.restoreLabel(value),
    );
    if (confirmed == true || !mounted) return;
    if (appearance != null) {
      if (appearance.value != initialAppearance) {
        appearance.value = initialAppearance!;
        widget.onStyleChanged?.call(style);
      }
    } else if (_local.value != initialStyle) {
      _update(initialStyle);
    }
    if (editor.label != initialLabel) {
      if (initialInstance != null) {
        initialInstance.onRestore();
      } else {
        editor.restoreLabel(initialLabel);
      }
    }
  }

  Future<void> _addChild() async {
    if (widget.onAdd != null) {
      await widget.onAdd!();
    } else {
      await _singleChildKey.currentState?.add();
    }
  }

  Widget _buildSurface(
    BuildContext context,
    Widget child, {
    Future<void> Function()? onRemoveChild,
  }) {
    final appearance = _appearance;
    final listenable = appearance ?? _local;
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final surfaceStyle = style;
        final renderStyle = surfaceStyle.copyWith(
          margin: 0,
          marginInsets: null,
        );
        final radius =
            widget.slot?.role == AppearanceSurfaceRole.applicationBackground
            ? 0.0
            : surfaceStyle.maxRadius;
        return Padding(
          padding: surfaceStyle.outerMargin,
          child: EditorSlot(
            key: _editorKey,
            label: _label,
            menuTitle: widget.menuTitle,
            onLabelChanged: widget.onLabelChanged == null ? null : _renameLabel,
            editable:
                widget.editable && (widget.slot == null || appearance != null),
            onEdit: openEditor,
            onAdd: widget.onAdd != null || widget.id != null ? _addChild : null,
            axisAction: widget.axisAction,
            menuSubtitle: widget.menuSubtitle,
            menuType: widget.menuType,
            onContextMenu: widget.onContextMenu,
            menuIcon: widget.menuIcon,
            identity: widget.slot?.standard,
            outlineRadius: radius,
            onRemoveChild: onRemoveChild,
            child: SuperContainer(
              style: renderStyle,
              fallbackColor: widget.fallbackColor,
              borderColor: widget.borderColor,
              padding: widget.padding,
              horizontalBorder: widget.horizontalBorder,
              decorate: widget.decorate,
              applyPadding: widget.applyPadding,
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.id case final id?) {
      return EditableSingleChild(
        key: _singleChildKey,
        id: id,
        label: _label,
        child: widget.child,
        builder: (context, child, hasChild, removeChild) => _buildSurface(
          context,
          child,
          onRemoveChild: hasChild ? removeChild : null,
        ),
      );
    }
    return _buildSurface(context, widget.child ?? const SizedBox.expand());
  }

  @override
  void dispose() {
    _local.dispose();
    super.dispose();
  }
}
