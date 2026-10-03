import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import '../services/window_transparency.dart';
import '../theme/appearance.dart';
import '../theme/appearance_slot.dart';
import '../theme/container_style.dart';
import '../theme/neon_style.dart';
import 'container_style_editor.dart';
import 'styled_surface.dart';

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
    if (_hovered.contains(this)) _setHovered(false);
    _local.dispose();
    super.dispose();
  }

  /// Conteneurs éditables sous le pointeur ; seul le plus profond est entouré.
  static final Set<SuperContainerState> _hovered = {};
  static final ValueNotifier<SuperContainerState?> _hoveredTarget =
      ValueNotifier(null);

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
      builder: (context) => AlertDialog(
        title: Text(_label),
        content: SizedBox(
          width: 420,
          child: StatefulBuilder(
            builder: (context, setTab) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tabbed) ...[
                  DefaultTabController(
                    length: 2,
                    initialIndex: editSlot == selectedSlot ? 1 : 0,
                    child: TabBar(
                      key: const ValueKey('style-editor-tabs'),
                      onTap: (index) => setTab(
                        () =>
                            editSlot = index == 1 ? selectedSlot : standardSlot,
                      ),
                      tabs: const [
                        Tab(text: 'Standard'),
                        Tab(text: 'Sélectionné'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Flexible(
                  child: SingleChildScrollView(
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
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ContainerStyleEditor(
                              label: _label,
                              collapsible: false,
                              value: style.fill,
                              solidColor: style.color ?? fallback,
                              radius: style.radius,
                              borderWidth: style.borderWidth,
                              borderColor: style.borderColor ?? border,
                              elevation: style.elevation,
                              shadowOpacity: style.shadowOpacity,
                              opacity: widget.slot == AppearanceSlot.background
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
                            ),
                            if (widget.slot == AppearanceSlot.background) ...[
                              Text(
                                'Opacité du fond : '
                                '${appearance!.value.backgroundOpacity.toStringAsFixed(1)}',
                              ),
                              Slider(
                                key: const ValueKey('Opacité du fond'),
                                value: appearance.value.backgroundOpacity,
                                onChanged: (v) => appearance.value = appearance
                                    .value
                                    .copyWith(backgroundOpacity: v),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<WindowEffect>(
                                key: const ValueKey('window-effect'),
                                initialValue: appearance.value.windowEffect,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Effet de la fenêtre',
                                  helperText: 'Visible à travers le fond : baissez son opacité.',
                                ),
                                items: [
                                  for (final effect in WindowEffect.values)
                                    DropdownMenuItem(
                                      value: effect,
                                      enabled: WindowTransparency.isSupported(
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
                                onChanged: (v) => appearance.value = appearance
                                    .value
                                    .copyWith(windowEffect: v),
                              ),
                            ],
                            TextButton(
                              onPressed: () =>
                                  update(style.copyWith(resetColor: true)),
                              child: const Text('Couleur unie automatique'),
                            ),
                            TextButton(
                              onPressed: () => _reset(slot: slot),
                              child: const Text('Réinitialiser ce style'),
                            ),
                          ],
                        );
                      },
                    ),
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
      ),
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

  Future<void> openMenu(Offset globalPosition) async {
    final chain = editableChain;
    if (chain.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final selected = await showMenu<SuperContainerState>(
      context: context,
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 420),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        for (final (index, state) in chain.indexed)
          PopupMenuItem(
            key: ValueKey('style-menu-${state._label}'),
            value: state,
            child: Padding(
              padding: EdgeInsets.only(left: 12.0 * index),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    index == 0
                        ? Icons.brush_outlined
                        : Icons.subdirectory_arrow_left,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(state._label, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    if (selected != null && selected.mounted) await selected.openEditor();
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
            Padding(padding: EdgeInsets.all(style.padding), child: child),
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
        radius: widget.slot == AppearanceSlot.background ? 0 : style.radius,
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _setHovered(false));
    }
    content = GestureDetector(
      onSecondaryTapUp: canEdit
          ? (details) => openMenu(details.globalPosition)
          : null,
      child: content,
    );
    return ListenableBuilder(
      listenable: _appearance ?? _local,
      builder: (context, child) =>
          Padding(padding: EdgeInsets.all(style.margin), child: child),
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

/// Pastille affichée en haut au centre pendant le mode édition des styles.
///
/// Peut être placée au-dessus du [Navigator] (ex. `MaterialApp.builder`) :
/// elle fournit alors son propre [Overlay] pour l'info-bulle du bouton.
class StyleEditBanner extends StatelessWidget {
  const StyleEditBanner({super.key});

  @override
  Widget build(BuildContext context) => Overlay.maybeOf(context) == null
      ? Overlay.wrap(child: Builder(builder: _buildBanner))
      : _buildBanner(context);

  Widget _buildBanner(BuildContext context) {
    final editMode = StyleEditScope.controllerOf(context);
    if (editMode == null || !editMode.value) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          key: const ValueKey('style-edit-banner'),
          color: scheme.primary,
          elevation: 6,
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.brush_outlined, size: 16, color: scheme.onPrimary),
                const SizedBox(width: 8),
                Text(
                  'Mode édition',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('style-edit-banner-close'),
                  tooltip: 'Quitter le mode édition',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: scheme.onPrimary,
                  icon: const Icon(Icons.close),
                  onPressed: () => editMode.value = false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
