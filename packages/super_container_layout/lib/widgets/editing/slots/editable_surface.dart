import 'package:material_ui/material_ui.dart';

import '../../../models/automatic_state.dart';
import '../../../models/json_text_binding.dart';
import '../../../services/states/content_hover_scope.dart';

import '../../../theme/appearance.dart';
import '../../../theme/appearance_slot.dart';
import '../../../theme/container_style.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/states/surface_state_binding.dart';
import '../../surfaces/super_container.dart';
import '../../components/super_layout/layout_selection.dart';
import '../dialogs/super_value_json_extract_dialog.dart';
import '../styles/container_style_dialog.dart';
import '../history/editor_history.dart';
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
    this.applyMargin = true,
    this.editable = true,
    this.resolveSelectionAndHover = true,
    this.onEdit,
    this.onAdd,
    this.axisAction,
    this.menuSubtitle,
    this.menuTooltip,
    this.menuType,
    this.onContextMenu,
    this.menuIcon,
    this.menuDestination,
    this.singleChild = true,
    super.key,
  }) : assert(id == null || id != '');

  final Widget? child;

  /// Stable registry identity for an optional single catalog child.
  final String? id;

  /// Whether [id] manages an optional single catalog child via [EditableSingleChild].
  final bool singleChild;
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
  final bool applyMargin;
  final bool editable;

  /// When false, delegates visual `selected` and `hover` state resolution to an
  /// external animated indicator layer while keeping [JsonListScope] selection
  /// and style-dialog preview intact.
  final bool resolveSelectionAndHover;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onAdd;
  final LayoutAxisAction Function()? axisAction;
  final String? Function()? menuSubtitle;
  final String? Function()? menuTooltip;
  final String? menuType;
  final ValueChanged<Offset>? onContextMenu;
  final IconData? menuIcon;
  final EditorMenuDestination? menuDestination;

  @override
  EditableSurfaceState createState() => EditableSurfaceState();
}

class EditableSurfaceState extends State<EditableSurface>
    implements JsonExtractableState {
  final _editorKey = GlobalKey<EditorSlotState>();
  final _singleChildKey = GlobalKey<EditableSingleChildState>();
  late final ValueNotifier<ContainerStyle> _local = ValueNotifier(widget.style);
  String? _localLabel;
  final _preview = ValueNotifier<ContainerStyle?>(null);
  final _runtimeRevision = ValueNotifier(0);
  SurfaceStateBinding? _stateBinding;
  bool _rowSelected = false;
  bool _contentHovered = false;
  final _hovered = ValueNotifier(false);

  void _setHovered(bool value) {
    if (_hovered.value == value) return;
    _hovered.value = value;
    _runtimeChanged();
  }

  void _runtimeChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runtimeRevision.value++;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _syncBinding(ContainerStyle style, JsonListScope? scope) {
    final selected = scope?.selected ?? false;
    if (_rowSelected != selected) {
      _rowSelected = selected;
      _runtimeChanged();
    }
    final binding = style.states?.binding;
    if (binding == null) {
      _stateBinding?.removeListener(_runtimeChanged);
      _stateBinding?.dispose();
      _stateBinding = null;
      return;
    }
    final store = JsonRepositoryScope.maybeOf(context);
    if (_stateBinding == null) {
      _stateBinding = SurfaceStateBinding(
        store: store,
        binding: binding,
        scope: scope,
        placeholder: scope?.placeholder ?? false,
      )..addListener(_runtimeChanged);
    } else {
      _stateBinding!.reconfigure(
        store: store,
        binding: binding,
        scope: scope,
        placeholder: scope?.placeholder ?? false,
      );
    }
  }

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
      _localLabel ?? widget.label ?? widget.slot?.standard.label ?? 'Card';

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
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    var confirmed = false;
    try {
      confirmed =
          await ContainerStyleDialog.show(
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
            allowSelected: JsonListScope.maybeOf(context) != null,
            allowContentHover: ContentHoverScope.maybeOf(context) != null,
            isContentHovered: () =>
                ContentHoverScope.maybeOf(context)?.hovered == true,
            activeState: () => _stateBinding?.stateName,
            isSelected: () => _rowSelected,
            isHovered: () => _hovered.value,
            stateError: () => _stateBinding?.error,
            stateChanges: _runtimeRevision,
            onPreview: (value) {
              if (mounted) _preview.value = value;
            },
          ) ==
          true;
      if (confirmed || !mounted) return;
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
    } finally {
      if (mounted) _preview.value = null;
      if (confirmed) {
        history?.commitTransaction();
      } else {
        history?.cancelTransaction();
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
        final scope = JsonListScope.maybeOf(context);
        final content = ContentHoverScope.maybeOf(context);
        if (_contentHovered != (content?.hovered ?? false)) {
          _contentHovered = content?.hovered ?? false;
          _runtimeChanged();
        }
        _syncBinding(style, scope);
        return ListenableBuilder(
          listenable: Listenable.merge([_preview, _hovered, ?_stateBinding]),
          builder: (context, _) {
            final base = style;
            final surfaceStyle =
                _preview.value ??
                base.states?.resolve(
                  base,
                  name: _stateBinding?.stateName,
                  isSelected:
                      widget.resolveSelectionAndHover &&
                      (scope?.selected ?? false),
                  isHovered: widget.resolveSelectionAndHover && _hovered.value,
                  activeStates: {
                    if (content?.hovered == true) AutomaticState.contentHover,
                  },
                ) ??
                base;
            final renderStyle = surfaceStyle.copyWith(
              margin: 0,
              marginInsets: null,
              hoverEffect: widget.resolveSelectionAndHover
                  ? surfaceStyle.hoverEffect
                  : false,
            );
            final radius =
                widget.slot?.role == AppearanceSurfaceRole.applicationBackground
                ? 0.0
                : surfaceStyle.maxRadius;
            return Padding(
              padding: widget.applyMargin
                  ? surfaceStyle.outerMargin
                  : EdgeInsets.zero,
              child: MouseRegion(
                opaque: false,
                onEnter: (_) => _setHovered(true),
                onExit: (_) => _setHovered(false),
                child: EditorSlot(
                  key: _editorKey,
                  id: widget.id ?? widget.slot?.name,
                  label: _label,
                  menuTitle: widget.menuTitle,
                  onLabelChanged: widget.onLabelChanged == null
                      ? null
                      : _renameLabel,
                  editable:
                      widget.editable &&
                      (widget.slot == null || appearance != null),
                  onEdit: openEditor,
                  onAdd: widget.onAdd != null || widget.id != null
                      ? _addChild
                      : null,
                  axisAction: widget.axisAction,
                  menuSubtitle: widget.menuSubtitle,
                  menuTooltip:
                      widget.menuTooltip ??
                      (widget.onEdit == null
                          ? () => formatContainerStyleTooltip(
                              title:
                                  _editorKey.currentState?.titleLabel ?? _label,
                              style: style,
                            )
                          : null),
                  menuType: widget.menuType,
                  onContextMenu: widget.onContextMenu,
                  menuIcon: widget.menuIcon,
                  menuDestination:
                      widget.menuDestination ??
                      (widget.onEdit == null
                          ? EditorMenuDestination.style
                          : EditorMenuDestination.configuration),
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
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.singleChild && widget.id != null) {
      final id = widget.id!;
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
  String get extractableId =>
      _editorKey.currentState?.effectiveComponentId ??
      widget.id ??
      widget.slot?.name ??
      _label;

  @override
  ExtractableComponentKind get extractableKind =>
      ExtractableComponentKind.surface;

  @override
  EditorSlotState? get extractableSurface => _editorKey.currentState;

  @override
  BuildContext get extractableContext => context;

  @override
  bool get isExtractableMounted => mounted;

  @override
  String get preferredExtractableKey {
    final slot = _editorKey.currentState;
    if (slot != null && slot.mounted && slot.hasCustomLabel) {
      final renamed = slot.titleLabel.trim();
      if (renamed.isNotEmpty) return renamed;
    }
    final instanceLabel = slot?.componentLabel?.label.trim();
    if (instanceLabel != null &&
        instanceLabel.isNotEmpty &&
        instanceLabel != 'Card' &&
        instanceLabel != 'Iterable Content') {
      return instanceLabel;
    }
    return extractableId;
  }

  @override
  ExtractableComponentTarget buildExtractableTarget(String assignedBaseKey) {
    final currentStyle = style;
    final imageUrl = currentStyle.fill.imageUrl.trim();
    final options = <ExtractablePropertyOption>[
      if (imageUrl.isNotEmpty || currentStyle.imageBinding != null)
        ExtractablePropertyOption(
          id: ContainerStyleProperty.imageUrl.name,
          label: 'Image de fond',
          value: imageUrl,
          defaultSelected: true,
        ),
    ];
    return ExtractableComponentTarget(
      id: extractableId,
      kind: ExtractableComponentKind.surface,
      displayName: preferredExtractableKey,
      baseJsonKey: assignedBaseKey,
      properties: options,
      applyBindings: (bindings) {
        if (!mounted || bindings.isEmpty) return;
        final current = style;
        final updatedProps = <ContainerStyleProperty, JsonTextBinding>{
          ...current.propertyBindings,
          for (final prop in ContainerStyleProperty.values)
            prop: ?bindings[prop.name],
        };
        final next = current.copyWith(
          propertyBindings: updatedProps,
          fill: current.fill.imageBinding == null
              ? current.fill
              : current.fill.copyWith(clearImageBinding: true),
        );
        if (next == current) return;
        _update(next);
      },
    );
  }

  @override
  void dispose() {
    _stateBinding?.removeListener(_runtimeChanged);
    _stateBinding?.dispose();
    _preview.dispose();
    _hovered.dispose();
    _runtimeRevision.dispose();
    _local.dispose();
    super.dispose();
  }
}
