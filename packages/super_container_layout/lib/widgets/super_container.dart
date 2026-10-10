import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import '../services/window_transparency.dart';
import '../theme/appearance.dart';
import '../theme/appearance_slot.dart';
import '../theme/container_style.dart';
import '../theme/neon_style.dart';
import 'container_style_editor.dart';
import 'layout_selection.dart';
import 'style_editor_panel.dart';
import 'styled_surface.dart';
import 'zone_axis_button.dart';

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
    required super.child,
    super.key,
  });

  final String label;
  final Future<void> Function() onEdit;
  final bool enabled;
  final Future<void> Function()? onRemove;
  final bool inline;

  static List<ContainerMenuAction> of(BuildContext context) {
    final actions = <ContainerMenuAction>[];
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is ContainerMenuAction && widget.enabled) actions.add(widget);
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

/// Conteneur stylé par un [ContainerStyle] qui ouvre le
/// [ContainerStyleEditor] pour se styler lui-même. Un clic droit ouvre un menu
/// listant ce conteneur et ses [SuperContainer] parents éditables.
///
/// Avec un [slot], le style est lu et écrit dans l'[Appearance] partagée (et
/// donc persisté) ; sinon il est local et remonté via [onStyleChanged].
/// Sous un [StyleEditScope], le clic droit n'est actif qu'en mode édition.
class SuperContainer extends StatefulWidget {
  const SuperContainer({
    required this.child,
    this.slot,
    this.style = const ContainerStyle(),
    this.onStyleChanged,
    this.label,
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
    super.key,
  });

  final Widget child;
  final AppearanceSlot? slot;
  final ContainerStyle style;
  final ValueChanged<ContainerStyle>? onStyleChanged;
  final String? label;
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

  @override
  State<SuperContainer> createState() => SuperContainerState();
}

class SuperContainerState extends State<SuperContainer> {
  late final ValueNotifier<ContainerStyle> _local = ValueNotifier(widget.style);

  ValueNotifier<Appearance>? get _appearance =>
      widget.slot == null ? null : AppearanceScope.controllerOf(context);

  String get _label =>
      widget.label ?? widget.slot?.standard.label ?? 'Super container';

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
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (context) {
        final screen = MediaQuery.sizeOf(context);
        final width = math.min(1080.0, screen.width - 96);
        final height = math.max(320.0, math.min(680.0, screen.height - 260));
        return AlertDialog(
          title: Text(_label),
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
                        void update(ContainerStyle v) => _update(v, slot: slot);
                        return ContainerStyleEditor(
                          label: _label,
                          collapsible: false,
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
                                  AppearanceSurfaceRole.applicationBackground
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
                          onResetBorderColor: () =>
                              update(style.copyWith(resetBorderColor: true)),
                          onElevationChanged: shape
                              ? (v) => update(style.copyWith(elevation: v))
                              : null,
                          onShadowOpacityChanged: shape
                              ? (v) => update(style.copyWith(shadowOpacity: v))
                              : null,
                          padding: style.padding,
                          margin: style.margin,
                          onPaddingChanged: (v) =>
                              update(style.copyWith(padding: v)),
                          onMarginChanged: (v) =>
                              update(style.copyWith(margin: v)),
                          onNeonChanged: (v) => update(style.copyWith(neon: v)),
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
                                    Slider(
                                      key: const ValueKey('Opacité du fond'),
                                      value: appearance.value.backgroundOpacity,
                                      onChanged: (v) =>
                                          appearance.value = appearance.value
                                              .copyWith(backgroundOpacity: v),
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
                                              WindowTransparency.label(effect),
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  WindowTransparency.isSupported(
                                                    effect,
                                                  )
                                                  ? null
                                                  : TextStyle(
                                                      color: Theme.of(context)
                                                          .disabledColor,
                                                    ),
                                            ),
                                          ),
                                      ],
                                      onChanged: (v) =>
                                          appearance.value = appearance.value
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

  Future<void> openMenu(
    Offset globalPosition, {
    List<ContainerMenuAction>? actions,
  }) async {
    final chain = editableChain;
    final extraActions = actions ?? ContainerMenuAction.of(context);
    if (chain.isEmpty && extraActions.isEmpty) return;
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
          for (final (index, state) in chain.indexed)
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
                      Flexible(
                        child: Text(
                          state._label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (index == 0)
                        for (final action in extraActions.where(
                          (action) => action.inline,
                        )) ...[
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
                      if ((StyleEditScope.controllerOf(state.context)?.value ??
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
                      if ((StyleEditScope.controllerOf(state.context)?.value ??
                              false) &&
                          state.widget.onAdd != null)
                        IconButton(
                          key: ValueKey('style-menu-add-${state._label}'),
                          tooltip: 'Ajouter un slot',
                          icon: const Icon(Icons.add),
                          onPressed: () =>
                              Navigator.of(context).pop(state.widget.onAdd),
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
    final editMode = StyleEditScope.controllerOf(context);
    final canEdit = _canEdit;
    Widget content = widget.padding == null
        ? widget.child
        : Padding(padding: widget.padding!, child: widget.child);
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
          builder: (context, target, child) => CustomPaint(
            foregroundPainter: identical(target, this) ? painter : null,
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
