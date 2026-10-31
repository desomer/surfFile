import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/theme/surffile_appearance_slots.dart';
import 'package:super_container_layout/theme/neon_style.dart';
import 'package:super_container_layout/widgets/surfaces/neon_surface.dart';

class SlidingSelectionList extends StatefulWidget {
  const SlidingSelectionList({
    required this.paths,
    required this.selectedPath,
    required this.itemBuilder,
    this.selectedPaths = const {},
    this.controller,
    this.horizontalPadding = 26,
    super.key,
  });

  final double horizontalPadding;

  final List<String> paths;
  final String? selectedPath;

  /// Autres éléments sélectionnés, surlignés sur place (sans glissement).
  final Set<String> selectedPaths;
  final ScrollController? controller;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<SlidingSelectionList> createState() => _SlidingSelectionListState();
}

class _SlidingSelectionListState extends State<SlidingSelectionList>
    with SingleTickerProviderStateMixin {
  final _ownScroll = ScrollController();
  ScrollController get _scroll => widget.controller ?? _ownScroll;
  late final AnimationController _animation;
  double? _from;
  double? _to;
  Curve _curve = Curves.easeInOutCubic;

  /// Retard maximal (en lignes) de la sélection animée sur sa cible.
  static const _maxLag = 1.0;

  double? get _position {
    if (_to == null) return null;
    final progress = _curve.transform(_animation.value);
    return _from! + (_to! - _from!) * progress;
  }

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1,
    );
    final selectedPath = widget.selectedPath;
    final index = selectedPath == null ? -1 : widget.paths.indexOf(selectedPath);
    if (index >= 0) _from = _to = index.toDouble();
  }

  @override
  void didUpdateWidget(SlidingSelectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedPath = widget.selectedPath;
    final index = selectedPath == null ? -1 : widget.paths.indexOf(selectedPath);
    final reordered =
        !identical(oldWidget.paths, widget.paths) &&
        !listEquals(oldWidget.paths, widget.paths);
    if (index < 0) {
      _animation.stop();
      _from = _to = null;
    } else if (reordered ||
        _to == null ||
        MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _from = _to = index.toDouble();
      _animation.value = 1;
    } else if (oldWidget.selectedPath != widget.selectedPath) {
      // Relancée en plein mouvement (touche maintenue), l'animation garde sa
      // vitesse : une courbe qui démarre lentement prendrait du retard à
      // chaque répétition, puis rattraperait d'un coup au relâchement.
      final moving = _animation.isAnimating;
      final target = index.toDouble();
      final from = _position!;
      _from = moving
          ? from.clamp(target - _maxLag, target + _maxLag).toDouble()
          : from;
      _to = target;
      _curve = moving ? Curves.easeOutCubic : Curves.easeInOutCubic;
      _animation.duration = Duration(milliseconds: moving ? 140 : 250);
      _animation.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ownScroll.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    final cardStyle = appearance.style('card');
    final selectedCardStyle = SurfFileAppearanceSlots.selectedCard.read(
      appearance,
    );
    final cardNeon = cardStyle.neon ?? const NeonStyle();
    final hasSelectedCardStyle = appearance.styles.containsKey('selectedCard');
    final extent = appearance.rowHeight + appearance.spacing / 6;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scheme = Theme.of(context).colorScheme;
    final selectedGradient = selectedCardStyle.fill.gradient();
    final cardGradient = cardStyle.fill.gradient();
    final selectedImage = selectedCardStyle.fill.decorationImage();
    final cardImage = cardStyle.fill.decorationImage();
    final selectedMaterialColor = selectedGradient != null
        ? Colors.transparent
        : cardColor(context, selectedCardStyle, selected: true);
    final unselectedMaterialColor = cardGradient != null
        ? Colors.transparent
        : cardStyle.color ??
              (appearance.backgroundOpacity < 1 ||
                      (appearance.style('background').color?.a ?? 1) < 1
                  ? Colors.transparent
                  : scheme.surface);

    Widget buildSurfaceBody({
      required bool selected,
      required bool suppressNeon,
    }) {
      final style = selected ? selectedCardStyle : cardStyle;
      final gradient = selected ? selectedGradient : cardGradient;
      final image = selected ? selectedImage : cardImage;
      return RepaintBoundary(
        child: IgnorePointer(
          child: NeonSurface(
            style: suppressNeon
                ? cardNeon.copyWith(enabled: false)
                : selected
                ? selectedCardStyle.neon!
                : cardNeon,
            accent: appearance.accent,
            radius: style.radius,
            child: Material(
              color: selected ? selectedMaterialColor : unselectedMaterialColor,
              elevation: style.elevation,
              shadowColor: Colors.black.withValues(alpha: style.shadowOpacity),
              borderRadius: BorderRadius.circular(style.radius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: gradient,
                  image: image,
                  borderRadius: BorderRadius.circular(style.radius),
                  border: selected && hasSelectedCardStyle
                      ? Border.all(
                          color:
                              selectedCardStyle.borderColor ?? scheme.primary,
                          width: selectedCardStyle.borderWidth,
                          style: selectedCardStyle.borderWidth == 0
                              ? BorderStyle.none
                              : BorderStyle.solid,
                        )
                      : !selected && cardStyle.borderColor != null
                      ? Border.all(
                          color: cardStyle.borderColor!,
                          width: cardStyle.borderWidth,
                          style: cardStyle.borderWidth == 0
                              ? BorderStyle.none
                              : BorderStyle.solid,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final selectedBody = buildSurfaceBody(selected: true, suppressNeon: false);
    final unselectedBody = buildSurfaceBody(
      selected: false,
      suppressNeon: false,
    );
    final unlitUnselectedBody = cardNeon.enabled && cardNeon.intensity > 0
        ? buildSurfaceBody(selected: false, suppressNeon: true)
        : unselectedBody;

    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: AnimatedBuilder(
            animation: Listenable.merge([_scroll, _animation]),
            child: RepaintBoundary(
              child: ListView.builder(
                controller: _scroll,
                // Identique à EntriesLayout.listPadding.
                padding: EdgeInsets.fromLTRB(
                  widget.horizontalPadding,
                  2,
                  widget.horizontalPadding,
                  24,
                ),
                itemExtent: extent,
                itemCount: widget.paths.length,
                itemBuilder: widget.itemBuilder,
              ),
            ),
            builder: (context, child) {
              final offset = _scroll.hasClients ? _scroll.offset : 0.0;
              final first = math.max(0, ((offset - 2) / extent).floor() - 1);
              final last = math.min(
                widget.paths.length,
                ((offset + constraints.maxHeight) / extent).ceil() + 1,
              );
              final position = reduceMotion ? _to : _position;
              Widget surface(
                int index, {
                required bool selected,
                bool slide = false,
              }) => Positioned(
                key: slide
                    ? const ValueKey('sliding-selection')
                    : ValueKey('row-surface-${widget.paths[index]}'),
                left: widget.horizontalPadding,
                right: widget.horizontalPadding,
                top:
                    2 +
                    (slide ? position! : index.toDouble()) * extent -
                    offset,
                height: appearance.rowHeight,
                child: selected
                    ? selectedBody
                    : position == index.toDouble()
                    ? unlitUnselectedBody
                    : unselectedBody,
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  for (var index = first; index < last; index++)
                    surface(
                      index,
                      selected:
                          widget.paths[index] != widget.selectedPath &&
                          widget.selectedPaths.contains(widget.paths[index]),
                    ),
                  if (position != null) surface(0, selected: true, slide: true),
                  child!,
                ],
              );
            },
          ),
        );
      },
    );
  }
}
