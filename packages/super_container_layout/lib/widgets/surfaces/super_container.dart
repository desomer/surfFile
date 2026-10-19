import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import '../../models/native_component_config.dart';
import '../../super_app.dart';
import '../../services/window_transparency.dart';
import '../../theme/appearance.dart';
import '../../theme/appearance_slot.dart';
import '../../theme/container_style.dart';
import '../../theme/neon_style.dart';
import '../editing/container_style_editor.dart';
import '../editing/editor_history.dart';
import '../editing/slot_removal.dart';
import '../../models/registry.dart' show EditorConfigKind;
import '../editing/editor_dialog.dart';
import '../editing/editor_overlay.dart';
import '../editing/editor_dialog_header.dart';
import '../super_layout/layout_selection.dart';
import '../editing/style_editor_panel.dart';
import 'styled_surface.dart';
import '../super_layout/zone_axis_button.dart';
import '../native/native_component_editor.dart';
import '../super_layout/slot_implementation.dart';

/// Active ou non l'édition des styles par clic droit sur les [SuperContainer].
class StyleEditScope extends InheritedNotifier<ValueNotifier<bool>> {
  const StyleEditScope({
    required ValueNotifier<bool> controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ValueNotifier<bool>? controllerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StyleEditScope>()?.notifier;
}

/// Entree contextuelle supplementaire pour le contenu d'un conteneur.
class ContainerMenuAction extends InheritedWidget {
  const ContainerMenuAction({
    required this.label,
    required this.onEdit,
    required this.enabled,
    this.onRemove,
    this.inline = false,
    this.showEdit = true,
    required super.child,
    super.key,
  });

  final String label;
  final Future<void> Function() onEdit;
  final bool enabled;
  final Future<void> Function()? onRemove;
  final bool inline;
  final bool showEdit;

  static List<ContainerMenuAction> of(BuildContext context) {
    final actions = <ContainerMenuAction>[];
    var hasInlineAction = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is ContainerMenuAction && widget.enabled) {
        if (!widget.inline || !hasInlineAction) {
          actions.add(widget);
        }
        if (widget.inline) hasInlineAction = true;
      }
      return true;
    });
    return actions;
  }

  @override
  bool updateShouldNotify(ContainerMenuAction oldWidget) =>
      label != oldWidget.label ||
      enabled != oldWidget.enabled ||
      onEdit != oldWidget.onEdit ||
      onRemove != oldWidget.onRemove ||
      inline != oldWidget.inline;
}

/// Inserts a command at its ancestor position among container menu entries.
class ContainerContextMenuEntry extends InheritedWidget {
  const ContainerContextMenuEntry({
    required this.label,
    required this.onSelected,
    required this.enabled,
    required super.child,
    super.key,
  });

  final String label;
  final Future<void> Function() onSelected;
  final bool enabled;

  @override
  bool updateShouldNotify(ContainerContextMenuEntry oldWidget) =>
      label != oldWidget.label ||
      onSelected != oldWidget.onSelected ||
      enabled != oldWidget.enabled;
}

/// Conteneur stylé par un [ContainerStyle] qui ouvre le
/// [ContainerStyleEditor] pour se styler lui-même. Un clic droit ouvre un menu
/// listant ce conteneur et ses [SuperContainer] parents éditables.
///
/// Avec un [slot], le style est lu et écrit dans l'[Appearance] partagée (et
/// donc persisté) ; sinon il est local et remonté via [onStyleChanged].
/// Sous un [StyleEditScope], le clic droit n'est actif qu'en mode édition.
class SuperContainer extends StatefulWidget {
  const SuperContainer({
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
    this.onContextMenu,
    super.key,
  }) : assert(id == null || id != '');

  final Widget? child;

  /// Stable identity enabling a single catalog child, persisted by SuperApp.
  /// Without an ID, the supplied child remains entirely application-owned.
  final String? id;
  final AppearanceSlot? slot;
  final ContainerStyle style;
  final ValueChanged<ContainerStyle>? onStyleChanged;
  final String? label;

  /// Optional owner name displayed in bold before the container label.
  final String? menuTitle;

  /// Persists a standalone instance's name; slots use their layout config.
  final ValueChanged<String>? onLabelChanged;
  final Color? fallbackColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final bool horizontalBorder;

  /// `false` : seul le geste d'édition est ajouté, le rendu reste à l'enfant.
  final bool decorate;

  /// Applique [ContainerStyle.padding] autour de l'enfant ; par défaut
  /// seulement si [decorate], sinon l'enfant gère lui-même sa marge interne.
  final bool? applyPadding;
  final bool editable;

  /// Éditeur personnalisé ouvert à la place du [ContainerStyleEditor].
  final Future<void> Function()? onEdit;

  /// Action d'ajout affichee dans le menu contextuel en mode edition.
  final Future<void> Function()? onAdd;

  final LayoutAxisAction Function()? axisAction;

  /// Updates editor selection before building the menu at this screen position.
  final ValueChanged<Offset>? onContextMenu;

  @override
  State<SuperContainer> createState() => SuperContainerState();
}

class SuperContainerState extends State<SuperContainer> {
  final _childKey = GlobalKey<_SuperContainerChildState>();
  late final ValueNotifier<ContainerStyle> _local = ValueNotifier(widget.style);
  String? _localLabel;

  Future<void> Function()? get _onAdd =>
      widget.onAdd ??
      (widget.id == null ? null : () async => _childKey.currentState?.add());

  ValueNotifier<Appearance>? get _appearance =>
      widget.slot == null ? null : AppearanceScope.controllerOf(context);

  /// Instance name of the component this container is the outermost editable
  /// surface of; nested containers keep their own label.
  EditorComponentLabel? get _instance {
    final element = context
        .getElementForInheritedWidgetOfExactType<EditorComponentLabel>();
    if (element == null) return null;
    var direct = true;
    context.visitAncestorElements((ancestor) {
      if (identical(ancestor, element)) return false;
      if (ancestor is StatefulElement &&
          ancestor.state is SuperContainerState) {
        direct = false;
        return false;
      }
      return true;
    });
    return direct ? EditorComponentLabel.of(context) : null;
  }

  bool get _canRename => _instance != null || widget.onLabelChanged != null;

  String get _label {
    final instance = _instance;
    return (instance?.overridden ?? false)
        ? instance!.label
        : _localLabel ??
              widget.label ??
              widget.slot?.standard.label ??
              'Super container';
  }

  void _renameLabel(String label) {
    final instance = _instance;
    if (instance != null) {
      instance.onChanged(label);
    } else {
      setState(() => _localLabel = label);
      widget.onLabelChanged?.call(label);
    }
  }

  Future<void> _promptRename() async {
    final text = TextEditingController(text: _label);
    final form = GlobalKey<FormState>();
    try {
      final label = await showEditorDialog<String>(
        context: context,
        target: context,
        builder: (dialogContext) {
          void save() {
            if (form.currentState!.validate()) {
              Navigator.of(dialogContext).pop(text.text.trim());
            }
          }

          return AlertDialog(
            title: const Text('Renommer le composant'),
            content: Form(
              key: form,
              child: TextFormField(
                key: const ValueKey('style-menu-rename-input'),
                controller: text,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Le nom ne peut pas être vide.'
                    : null,
                onFieldSubmitted: (_) => save(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                key: const ValueKey('style-menu-rename-save'),
                onPressed: save,
                child: const Text('Renommer'),
              ),
            ],
          );
        },
      );
      if (label != null && label != _label && mounted) _renameLabel(label);
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
    }
  }

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
    if (oldWidget.label != widget.label) _localLabel = null;
  }

  @override
  void dispose() {
    _removeHoveredSafely();
    _local.dispose();
    super.dispose();
  }

  /// Conteneurs éditables sous le pointeur ; seul le plus profond est entouré.
  static final Set<SuperContainerState> _hovered = {};
  static final ValueNotifier<SuperContainerState?> _hoveredTarget =
      ValueNotifier(null);
  static bool _hoveredTargetUpdateScheduled = false;
  static SuperContainerState? _menuHoveredTarget;

  int _cachedDepth = 0;

  int get _depth {
    var depth = 0;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is SuperContainerState) {
        depth++;
      }
      return true;
    });
    return depth;
  }

  void _setHovered(bool hovered) {
    if (hovered) {
      _hovered.add(this);
    } else {
      _hovered.remove(this);
    }
    _refreshHoveredTarget();
  }

  void _removeHoveredSafely() {
    final wasHovered = _hovered.remove(this);
    final wasMenuTarget = identical(_menuHoveredTarget, this);
    if (wasMenuTarget) _menuHoveredTarget = null;
    if ((!wasHovered && !wasMenuTarget) || _hoveredTargetUpdateScheduled) {
      return;
    }
    _hoveredTargetUpdateScheduled = true;
    scheduleMicrotask(() {
      _hoveredTargetUpdateScheduled = false;
      _refreshHoveredTarget();
    });
  }

  static void _refreshHoveredTarget() {
    final menuTarget = _menuHoveredTarget;
    if (menuTarget != null && menuTarget.mounted && menuTarget._canEdit) {
      _hoveredTarget.value = menuTarget;
      return;
    }
    SuperContainerState? deepest;
    var maxDepth = -1;
    for (final state in _hovered) {
      if (!state.mounted) continue;
      final depth = state._cachedDepth;
      if (depth > maxDepth) {
        maxDepth = depth;
        deepest = state;
      }
    }
    _hoveredTarget.value = deepest;
  }

  Widget _menuHover(SuperContainerState target, Widget child) => MouseRegion(
    onEnter: (_) {
      if (!(StyleEditScope.controllerOf(target.context)?.value ?? false)) {
        return;
      }
      _menuHoveredTarget = target;
      _refreshHoveredTarget();
    },
    onExit: (_) {
      if (identical(_menuHoveredTarget, target)) {
        _menuHoveredTarget = null;
        _refreshHoveredTarget();
      }
    },
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      ),
    ),
  );

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

  Future<void> openEditor() async {
    if (widget.onEdit != null) return widget.onEdit!();
    final appearance = _appearance;
    final initialAppearance = appearance?.value;
    final initialStyle = _local.value;
    final initialLabel = _label;
    final initialInstance = _instance;
    final accent = AppearanceScope.of(context).accent;
    final shape = widget.slot?.editShape ?? true;
    final extended = widget.slot?.extendedLook ?? true;
    final standardSlot = widget.slot?.standard;
    final selectedSlot = standardSlot?.selectedVariant;
    final colors = Theme.of(context).colorScheme;
    // Onglet édité (standard ou sélectionné) ; le rendu reste celui du slot du
    // widget.
    var editSlot = widget.slot;
    final tabbed = selectedSlot != null;
    var dense = StyleEditorPanel.preferredDense;
    final dockWidth = ValueNotifier(dense ? 680.0 : 1080.0);
    bool? confirmed;
    try {
      confirmed = await showEditorDialog<bool>(
        context: context,
        target: context,
        preferredWidth: dockWidth,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) {
            final screen = MediaQuery.sizeOf(context);
            final width = math.min(dense ? 680.0 : 1080.0, screen.width - 96);
            final height = math.max(
              320.0,
              math.min(680.0, screen.height - 260),
            );
            return AlertDialog(
              insetPadding: const EdgeInsets.all(24),
              constraints: BoxConstraints(maxWidth: width + 48),
              content: SizedBox(
                width: width,
                height: height,
                child: StatefulBuilder(
                  builder: (context, setTab) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (tabbed) ...[
                        DefaultTabController(
                          length: 2,
                          initialIndex: editSlot == selectedSlot ? 1 : 0,
                          child: TabBar(
                            key: const ValueKey('style-editor-tabs'),
                            onTap: (index) => setTab(
                              () => editSlot = index == 1
                                  ? selectedSlot
                                  : standardSlot,
                            ),
                            tabs: const [
                              Tab(text: 'Standard'),
                              Tab(text: 'Sélectionné'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Expanded(
                        child: ListenableBuilder(
                          key: ValueKey(editSlot),
                          listenable: appearance ?? _local,
                          builder: (context, _) {
                            final slot = editSlot;
                            final style = slot != null && appearance != null
                                ? slot.read(appearance.value)
                                : this.style;
                            final fallback = slot == widget.slot
                                ? _fallback(context)
                                : slot!.isSelectedVariant
                                ? colors.primaryContainer
                                : colors.surfaceContainerLow;
                            final border = slot == widget.slot
                                ? _border(context)
                                : colors.primary;
                            void update(ContainerStyle v) =>
                                _update(v, slot: slot);
                            return ContainerStyleEditor(
                              label: _label,
                              onLabelChanged: (label) =>
                                  setDialog(() => _renameLabel(label)),
                              collapsible: false,
                              dense: dense,
                              onDenseChanged: (value) => setDialog(() {
                                dense = value;
                                dockWidth.value = value ? 680 : 1080;
                              }),
                              style: style,
                              onStyle: update,
                              extended: extended,
                              value: style.fill,
                              solidColor: style.color ?? fallback,
                              radius: style.radius,
                              borderWidth: style.borderWidth,
                              borderColor: style.borderColor ?? border,
                              elevation: style.elevation,
                              shadowOpacity: style.shadowOpacity,
                              opacity:
                                  widget.slot?.role ==
                                      AppearanceSurfaceRole
                                          .applicationBackground
                                  ? appearance!.value.backgroundOpacity
                                  : 1,
                              neon: style.neon ?? const NeonStyle(),
                              accent: accent,
                              onChanged: (v) => update(style.copyWith(fill: v)),
                              onSolidColorChanged: (v) =>
                                  update(style.copyWith(color: v)),
                              onRadiusChanged: shape
                                  ? (v) => update(style.copyWith(radius: v))
                                  : null,
                              onBorderWidthChanged: (v) =>
                                  update(style.copyWith(borderWidth: v)),
                              onBorderColorChanged: (v) =>
                                  update(style.copyWith(borderColor: v)),
                              onResetBorderColor: () => update(
                                style.copyWith(resetBorderColor: true),
                              ),
                              onElevationChanged: shape
                                  ? (v) => update(style.copyWith(elevation: v))
                                  : null,
                              onShadowOpacityChanged: shape
                                  ? (v) =>
                                        update(style.copyWith(shadowOpacity: v))
                                  : null,
                              padding: style.padding,
                              margin: style.margin,
                              onPaddingChanged: (v) =>
                                  update(style.copyWith(padding: v)),
                              onMarginChanged: (v) =>
                                  update(style.copyWith(margin: v)),
                              onNeonChanged: (v) =>
                                  update(style.copyWith(neon: v)),
                              hoverEffect: style.hoverEffect,
                              onHoverEffectChanged: (v) =>
                                  update(style.copyWith(hoverEffect: v)),
                              hoverTint: style.hoverTint,
                              hoverColor: style.hoverColor,
                              onHoverTintChanged: (v) =>
                                  update(style.copyWith(hoverTint: v)),
                              onHoverColorChanged: (v) =>
                                  update(style.copyWith(hoverColor: v)),
                              interactionEffect: style.interactionEffect,
                              onInteractionEffectChanged: (v) =>
                                  update(style.copyWith(interactionEffect: v)),
                              designSystem: style.designSystem,
                              onDesignSystemChanged: shape
                                  ? (v) => update(v.apply(style))
                                  : null,
                              onResetColor: () =>
                                  update(style.copyWith(resetColor: true)),
                              onReset: () => _reset(slot: slot),
                              extraSections: [
                                if (widget.slot?.role ==
                                    AppearanceSurfaceRole.applicationBackground)
                                  StyleEditorSection(
                                    id: 'window',
                                    title: 'Fenêtre',
                                    tag: 'windowEffect',
                                    icon: Icons.window_outlined,
                                    count: 2,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          'Opacité du fond : '
                                          '${appearance!.value.backgroundOpacity.toStringAsFixed(1)}',
                                        ),
                                        EditorHistorySlider(
                                          key: const ValueKey(
                                            'Opacité du fond',
                                          ),
                                          value: appearance
                                              .value
                                              .backgroundOpacity,
                                          onChanged: (v) => appearance.value =
                                              appearance.value.copyWith(
                                                backgroundOpacity: v,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        DropdownButtonFormField<WindowEffect>(
                                          key: const ValueKey('window-effect'),
                                          initialValue:
                                              appearance.value.windowEffect,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Effet de la fenêtre',
                                            helperText: 'Visible à travers le fond : baissez son opacité.',
                                          ),
                                          items: [
                                            for (final effect
                                                in WindowEffect.values)
                                              DropdownMenuItem(
                                                value: effect,
                                                enabled:
                                                    WindowTransparency.isSupported(
                                                      effect,
                                                    ),
                                                child: Text(
                                                  WindowTransparency.label(
                                                    effect,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      WindowTransparency.isSupported(
                                                        effect,
                                                      )
                                                      ? null
                                                      : TextStyle(
                                                          color: Theme.of(
                                                            context,
                                                          ).disabledColor,
                                                        ),
                                                ),
                                              ),
                                          ],
                                          onChanged: (v) =>
                                              appearance.value = appearance
                                                  .value
                                                  .copyWith(windowEffect: v),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Appliquer'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      dockWidth.dispose();
    }
    if (confirmed == true || !mounted) return;
    if (appearance != null) {
      if (appearance.value != initialAppearance) {
        appearance.value = initialAppearance!;
        widget.onStyleChanged?.call(style);
      }
    } else if (_local.value != initialStyle) {
      _update(initialStyle);
    }
    if (_label != initialLabel) {
      if (initialInstance != null) {
        initialInstance.onRestore();
      } else {
        _renameLabel(initialLabel);
      }
    }
  }

  bool get _canEdit {
    final editMode = StyleEditScope.controllerOf(context);
    return widget.editable &&
        (editMode?.value ?? true) &&
        (widget.slot == null || _appearance != null);
  }

  /// Ce conteneur puis ses ancêtres éditables, du plus profond au plus large.
  List<SuperContainerState> get editableChain {
    final chain = <SuperContainerState>[];
    final slots = <AppearanceSlot>{};
    SuperContainerState? state = this;
    while (state != null) {
      final slot = state.widget.slot?.standard;
      if (state._canEdit && (slot == null || slots.add(slot))) {
        chain.add(state);
      }
      state = state.context.findAncestorStateOfType<SuperContainerState>();
    }
    return chain;
  }

  /// Rattache chaque action inline (taille, suppression du slot) au conteneur
  /// éditable le plus proche qu'elle englobe ; les actions fournies par un
  /// descendant restent sur le premier conteneur de la chaîne.
  Map<SuperContainerState, List<ContainerMenuAction>> _inlineActionsByState(
    List<SuperContainerState> chain,
    List<ContainerMenuAction> provided,
  ) {
    final result = <SuperContainerState, List<ContainerMenuAction>>{};
    if (chain.isEmpty) return result;
    final ancestors = <ContainerMenuAction>{};
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is ContainerMenuAction && widget.inline) ancestors.add(widget);
      return true;
    });
    final below = [
      for (final action in provided)
        if (action.inline && !ancestors.contains(action)) action,
    ];
    if (below.isNotEmpty) result[chain.first] = below;
    SuperContainerState? current = chain.contains(this) ? this : null;
    final claimed = <SuperContainerState>{if (below.isNotEmpty) chain.first};
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (element is StatefulElement) {
        final state = element.state;
        if (state is SuperContainerState && chain.contains(state)) {
          current = state;
        }
      } else if (widget is ContainerMenuAction &&
          widget.enabled &&
          widget.inline) {
        final owner = current ?? chain.first;
        if (claimed.add(owner)) {
          (result[owner] ??= []).add(widget);
        }
      }
      return true;
    });
    return result;
  }

  Future<void> openMenu(
    Offset globalPosition, {
    List<ContainerMenuAction>? actions,
  }) async {
    final chain = editableChain;
    for (final state in chain.reversed) {
      if (StyleEditScope.controllerOf(state.context)?.value ?? false) {
        state.widget.onContextMenu?.call(globalPosition);
      }
    }
    final extraActions = actions ?? ContainerMenuAction.of(context);
    final inlineActions = _inlineActionsByState(chain, extraActions);
    final entries = <(int, Object)>[
      if (chain.contains(this)) (chain.indexOf(this), this),
    ];
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is ContainerContextMenuEntry && widget.enabled) {
        entries.add((entries.length, widget));
      } else if (element is StatefulElement) {
        final state = element.state;
        if (state is SuperContainerState && chain.contains(state)) {
          entries.add((entries.length, state));
        }
      }
      return true;
    });
    if (entries.isEmpty && extraActions.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    Object? selected;
    try {
      selected = await showMenu<Object>(
        context: context,
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 420),
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          overlay.size.width - position.dx,
          overlay.size.height - position.dy,
        ),
        items: [
          for (final action in extraActions)
            if (!action.inline)
              PopupMenuItem<Future<void> Function()>(
                value: action.onEdit,
                padding: EdgeInsets.zero,
                child: _menuHover(
                  this,
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Flexible(child: Text(action.label)),
                      if (action.onRemove case final remove?)
                        IconButton(
                          key: ValueKey('style-menu-remove-${action.label}'),
                          tooltip: 'Supprimer le slot',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => Navigator.of(context).pop(remove),
                        ),
                    ],
                  ),
                ),
              ),
          for (final (index, entry) in entries)
            if (entry is ContainerContextMenuEntry)
              PopupMenuItem<Future<void> Function()>(
                key: ValueKey('style-menu-entry-${entry.label}'),
                value: entry.onSelected,
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16 + 12.0 * index, 0, 16, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.subdirectory_arrow_left, size: 18),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          entry.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (entry case final SuperContainerState state)
              PopupMenuItem<SuperContainerState>(
                key: ValueKey('style-menu-${state._label}'),
                value: state,
                padding: EdgeInsets.zero,
                child: _menuHover(
                  state,
                  Padding(
                    padding: EdgeInsets.only(left: 12.0 * index),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Icon(
                          index == 0
                              ? Icons.brush_outlined
                              : Icons.subdirectory_arrow_left,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        if (state.widget.menuTitle case final title?) ...[
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            state._label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state.widget.axisAction != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            state.widget.axisAction!().zoneLabel,
                            key: ValueKey('style-menu-zone-${state._label}'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state._canRename)
                          IconButton(
                            key: ValueKey('style-menu-rename-${state._label}'),
                            tooltip: 'Renommer',
                            icon: const Icon(Icons.drive_file_rename_outline),
                            onPressed: () =>
                                Navigator.of(context)
                                    .pop<Future<void> Function()>(() async {
                                      if (state.mounted) {
                                        await state._promptRename();
                                      }
                                    }),
                          ),
                        for (final action
                            in inlineActions[state] ??
                                const <ContainerMenuAction>[]) ...[
                          if (action.showEdit)
                            IconButton(
                              key: ValueKey('style-menu-size-${action.label}'),
                              tooltip: action.label,
                              icon: const Icon(Icons.straighten),
                              onPressed: () =>
                                  Navigator.of(context).pop(action.onEdit),
                            ),
                          if (action.onRemove case final remove?)
                            IconButton(
                              key: ValueKey(
                                'style-menu-remove-${action.label}',
                              ),
                              tooltip: 'Supprimer le slot',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  Navigator.of(context).pop(remove),
                            ),
                        ],
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state.widget.axisAction != null)
                          ZoneAxisButton(
                            key: ValueKey('style-menu-axis-${state._label}'),
                            action: LayoutAxisAction(
                              zoneLabel: state.widget.axisAction!().zoneLabel,
                              axis: state.widget.axisAction!().axis,
                              onToggle: () =>
                                  Navigator.of(context)
                                      .pop<Future<void> Function()>(() async {
                                        if (state.mounted) {
                                          state.widget.axisAction!().onToggle();
                                        }
                                      }),
                            ),
                          ),
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state.widget.id != null &&
                            (state._childKey.currentState?.hasChild ?? false) &&
                            !state._childKey.currentState!.childHasMenu)
                          IconButton(
                            key: ValueKey(
                              'style-menu-remove-child-${state._label}',
                            ),
                            tooltip: 'Supprimer le composant enfant',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                Navigator.of(context)
                                    .pop<Future<void> Function()>(() async {
                                      state._childKey.currentState?.remove();
                                    }),
                          ),
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state._onAdd != null)
                          IconButton(
                            key: ValueKey('style-menu-add-${state._label}'),
                            tooltip: state.widget.id == null
                                ? 'Ajouter un slot'
                                : 'Ajouter / remplacer le composant enfant',
                            icon: const Icon(Icons.add),
                            onPressed: () =>
                                Navigator.of(context).pop(state._onAdd),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      );
    } finally {
      _menuHoveredTarget = null;
      _refreshHoveredTarget();
    }
    if (!mounted) return;
    if (selected is SuperContainerState && selected.mounted) {
      await selected.openEditor();
    } else if (selected is Future<void> Function()) {
      await selected();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.id case final id?) {
      return _SuperContainerChild(
        key: _childKey,
        id: id,
        label: _label,
        builder: _buildSurface,
        child: widget.child,
      );
    }
    return _buildSurface(context, widget.child ?? const SizedBox.expand());
  }

  Widget _buildSurface(BuildContext context, Widget child) {
    final editMode = StyleEditScope.controllerOf(context);
    final canEdit = _canEdit;
    Widget content = widget.padding == null
        ? child
        : Padding(padding: widget.padding!, child: child);
    if (widget.applyPadding ?? widget.decorate) {
      content = ListenableBuilder(
        listenable: _appearance ?? _local,
        builder: (context, child) =>
            Padding(padding: style.contentPadding, child: child),
        child: content,
      );
    }
    if (widget.decorate) {
      content = ListenableBuilder(
        listenable: _appearance ?? _local,
        builder: (context, child) => StyledSurface(
          style: style,
          fallbackColor: _fallback(context),
          borderColor: _border(context),
          horizontalBorder: widget.horizontalBorder,
          child: child!,
        ),
        child: content,
      );
    }
    if (canEdit && editMode != null) {
      _cachedDepth = _depth;
      final painter = _DashedOutlinePainter(
        color: AppearanceScope.of(context).accent.withValues(alpha: .8),
        radius: widget.slot?.role == AppearanceSurfaceRole.applicationBackground
            ? 0
            : style.maxRadius,
      );
      content = MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: ValueListenableBuilder<SuperContainerState?>(
          valueListenable: _hoveredTarget,
          builder: (context, target, child) => ValueListenableBuilder<int>(
            valueListenable: EditorOverlayVisibility.openDialogs,
            builder: (context, count, child) => CustomPaint(
              foregroundPainter: count == 0 && identical(target, this)
                  ? painter
                  : null,
              child: child,
            ),
            child: child,
          ),
          child: content,
        ),
      );
    } else if (_hovered.contains(this)) {
      _removeHoveredSafely();
    }
    content = GestureDetector(
      // Le clic droit d'édition n'est pas une action d'accessibilité : sans
      // cela, le nœud sémantique apparaît/disparaît avec le mode édition et
      // reparente le sous-arbre, ce que le pont AXTree Windows ne gère pas.
      excludeFromSemantics: true,
      onSecondaryTapUp: canEdit
          ? (details) => openMenu(details.globalPosition)
          : null,
      child: content,
    );
    return ListenableBuilder(
      listenable: _appearance ?? _local,
      builder: (context, child) =>
          Padding(padding: style.outerMargin, child: child),
      child: content,
    );
  }
}

class _SuperContainerChild extends StatefulWidget {
  const _SuperContainerChild({
    required this.id,
    required this.label,
    required this.child,
    required this.builder,
    super.key,
  });

  final String id, label;
  final Widget? child;
  final Widget Function(BuildContext, Widget) builder;

  @override
  State<_SuperContainerChild> createState() => _SuperContainerChildState();
}

class _SuperContainerChildState extends State<_SuperContainerChild> {
  final _editor = GlobalKey<NativeComponentEditorState>();
  late final _local = ValueNotifier(_initial);
  static const _providedId = '__provided-child';

  NativeComponentConfig get _initial => NativeComponentConfig(
    placements: {
      if (widget.child != null) 'child': [_providedId],
    },
  );

  ValueNotifier<NativeComponentConfig> get _config =>
      SuperApp.maybeOf(context)?.registry
          ?.nativeComponentController(widget.id, fallback: _initial) ??
      _local;

  bool get hasChild => _config.value.slotsOf('child').isNotEmpty;

  /// Whether the child has its own editable [SuperContainer], whose menu row
  /// then carries the child removal instead of this container's row.
  bool get childHasMenu {
    var found = false;
    void visit(Element element) {
      if (found) return;
      if (element is StatefulElement &&
          element.state is SuperContainerState &&
          (element.state as SuperContainerState)._canEdit) {
        found = true;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  void remove() {
    final current = _config.value;
    if (hasChild) {
      final id = current.slotsOf('child').single;
      removeSlotInstance(
        context,
        id: id,
        type: current.slotTypeOf(id),
        containerKind: EditorConfigKind.nativeComponent,
        unplace: () => _config.value = current.withoutSlot(id),
      );
    }
  }

  @override
  void didUpdateWidget(_SuperContainerChild oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _local.value = _initial;
  }

  Future<void> add() async {
    if (hasChild) {
      final confirmed = await showEditorDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remplacer le composant enfant ?'),
          content: const Text(
            'Le conteneur ne peut contenir qu’un seul composant. '
            'Le nouveau composant remplacera le contenu actuel.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remplacer'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _editor.currentState?.add('child');
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final controller = _config;
    return ValueListenableBuilder<NativeComponentConfig>(
      valueListenable: controller,
      builder: (context, config, _) => NativeComponentEditor(
        key: _editor,
        label: widget.label,
        keyPrefix: 'super-container-${widget.id}',
        settingsTitle: 'Configurer le contenu',
        config: config,
        onChanged: (value) => controller.value = value,
        registry: registry,
        regions: const [
          NativeRegion('child', 'Enfant', required: true, single: true),
        ],
        slots: [
          if (widget.child case final child?)
            BuilderSlot(
              id: _providedId,
              label: 'Contenu initial',
              builder: (_) => child,
            ),
        ],
        builder: (context, editor) {
          final children = editor.slotsFor('child');
          final child = children.isEmpty
              ? const SizedBox.expand()
              : children.single;
          return widget.builder(
            context,
            ContainerMenuAction(
              label: 'Composant enfant : ${widget.label}',
              inline: true,
              showEdit: false,
              enabled: children.isNotEmpty,
              onEdit: () async {},
              onRemove: children.isEmpty ? null : () async => remove(),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _local.dispose();
    super.dispose();
  }
}

class _DashedOutlinePainter extends CustomPainter {
  const _DashedOutlinePainter({required this.color, required this.radius});

  static const _strokeWidth = 1.5;
  static const _dash = 6.0;
  static const _gap = 5.0;

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = _strokeWidth / 2;
    final rect = (Offset.zero & size).deflate(inset);
    if (rect.isEmpty) return;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular((radius - inset).clamp(0, rect.shortestSide / 2)),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutlinePainter old) =>
      old.color != color || old.radius != radius;
}
