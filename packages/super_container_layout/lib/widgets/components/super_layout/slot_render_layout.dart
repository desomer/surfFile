/// Calcul des contraintes, mesures et bornes de redimensionnement des slots.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart';
import 'slot_core.dart';
import 'zone_scrollable_viewport.dart';

/// Mesures internes nécessaires au redimensionnement d'un slot.
abstract interface class SlotResizeGeometry implements RenderBox {
  /// Dimensions de référence configurées pour le layout contenant le slot.
  Size get layoutSize;

  /// Taille préférée historique du slot à l'index [index], si présente.
  Size? preferredSizeAt(int index);

  /// Base de pourcentage de la zone disponible pour le redimensionnement.
  Size get resizeBasis;

  /// Bornes minimales et maximales de taille du slot à l'index [index].
  ({Size min, Size max}) resizeBounds(int index);
}

/// Widget interne qui configure le layout flex des slots d'une zone.
class SlotFlex extends MultiChildRenderObjectWidget {
  /// Crée un layout flex à partir des paramètres de la zone et de ses slots.
  const SlotFlex({
    required this.axis,
    required this.expand,
    required this.stretch,
    required this.scrollable,
    required this.expandSlots,
    required this.mainAxisAlignment,
    required this.crossAxisAlignment,
    required this.spacing,
    required this.preferredSizes,
    required this.sizeConstraints,
    required this.layoutSize,
    required this.sizing,
    required super.children,
    super.key,
  });

  /// Axe principal du layout.
  final Axis axis;

  /// Indique si le layout occupe l'espace restant.
  final bool expand;

  /// Indique si les enfants s'étirent sur l'axe transversal.
  final bool stretch;

  /// Indique si les enfants peuvent déborder dans une zone défilante.
  final bool scrollable;

  /// Indique si les slots flexibles se partagent l'espace.
  final bool expandSlots;

  /// Alignement des enfants sur l'axe principal.
  final MainAxisAlignment mainAxisAlignment;

  /// Alignement des enfants sur l'axe transversal.
  final CrossAxisAlignment crossAxisAlignment;

  /// Espacement entre les enfants.
  final double spacing;

  /// Tailles préférées historiques des slots.
  final List<Size?> preferredSizes;

  /// Contraintes de taille explicites des slots.
  final List<SlotSizeConstraints?> sizeConstraints;

  /// Taille complète du layout servant de base aux pourcentages.
  final Size layoutSize;

  /// Politique de taille de chaque slot.
  final List<SlotSizing> sizing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSlotFlex()..configure(this);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderSlotFlex).configure(this);
}

class _SlotParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSlotFlex extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlotParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlotParentData>
    implements SlotResizeGeometry {
  late SlotFlex _configuration;
  List<(double, double, double?, double, double, double?)> _bounds = const [];

  Size? _viewportSize() {
    RenderObject? current = parent;
    while (current != null) {
      if (current is ScrollViewportMetrics) return current.viewportSize;
      current = current.parent;
    }
    return null;
  }

  @override
  ({Size min, Size max}) resizeBounds(int index) {
    final horizontal = _configuration.axis == Axis.horizontal;
    final bound = _bounds[index];
    final available = resizeBasis;
    var maxMain = horizontal ? available.width : available.height;
    if (_configuration.scrollable) {
      maxMain = bound.$2;
    } else {
      final children = getChildrenAsList();
      if (children.length > 1) {
        maxMain -= _configuration.spacing * (children.length - 1);
      }
      for (final (other, child) in children.indexed) {
        if (other == index) continue;
        final fitOverride = _configuration.sizeConstraints[other]?.fitContent;
        final flexible =
            _configuration.expand &&
            _bounds[other].$3 == null &&
            (fitOverride != null
                ? !fitOverride
                : (_configuration.sizing[other] == SlotSizing.fill &&
                      _configuration.expandSlots &&
                      _configuration.mainAxisAlignment ==
                          MainAxisAlignment.start));
        maxMain -= flexible
            ? _bounds[other].$1
            : _bounds[other].$3 != null
            ? _bounds[other].$3!.clamp(_bounds[other].$1, _bounds[other].$2)
            : horizontal
            ? child.size.width
            : child.size.height;
      }
      if (bound.$2 < maxMain) maxMain = bound.$2;
    }
    return (
      min: horizontal ? Size(bound.$1, bound.$4) : Size(bound.$4, bound.$1),
      max: horizontal ? Size(maxMain, bound.$5) : Size(bound.$5, maxMain),
    );
  }

  @override
  Size get resizeBasis {
    final viewport = _viewportSize();
    return Size(
      constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : (viewport != null && viewport.width.isFinite
                ? viewport.width
                : size.width),
      constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : (viewport != null && viewport.height.isFinite
                ? viewport.height
                : size.height),
    );
  }

  @override
  Size get layoutSize => _configuration.layoutSize;

  @override
  Size? preferredSizeAt(int index) => _configuration.preferredSizes[index];

  void configure(SlotFlex value) {
    _configuration = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotParentData) {
      child.parentData = _SlotParentData();
    }
  }

  @override
  void performLayout() {
    final children = getChildrenAsList();
    final preferences = _configuration.preferredSizes;
    final sizeConstraints = _configuration.sizeConstraints;
    final horizontal = _configuration.axis == Axis.horizontal;
    double mainExtent(Size size) => horizontal ? size.width : size.height;
    double crossExtent(Size size) => horizontal ? size.height : size.width;
    Size dimensions(double main, double cross) =>
        horizontal ? Size(main, cross) : Size(cross, main);
    final viewport = _viewportSize();
    final rawMaxMain = mainExtent(constraints.biggest);
    final rawMaxCross = crossExtent(constraints.biggest);
    final maxMain = rawMaxMain.isFinite
        ? rawMaxMain
        : (viewport != null ? mainExtent(viewport) : double.infinity);
    final maxCross = rawMaxCross.isFinite
        ? rawMaxCross
        : (viewport != null ? crossExtent(viewport) : double.infinity);
    final rawLayoutMain = mainExtent(_configuration.layoutSize);
    final rawLayoutCross = crossExtent(_configuration.layoutSize);
    final layoutMain = rawLayoutMain.isFinite
        ? rawLayoutMain
        : (viewport != null ? mainExtent(viewport) : double.infinity);
    final layoutCross = rawLayoutCross.isFinite
        ? rawLayoutCross
        : (viewport != null ? crossExtent(viewport) : double.infinity);
    final scrollable = _configuration.scrollable || !rawMaxMain.isFinite;
    final expand = _configuration.expand && maxMain.isFinite;
    final stretch = _configuration.stretch && rawMaxCross.isFinite;
    final stretchCross =
        stretch &&
        _configuration.crossAxisAlignment == CrossAxisAlignment.stretch;
    final bounds = <(double, double, double?, double, double, double?)>[];
    for (final (index, _) in children.indexed) {
      final legacy = preferences[index];
      final configured = sizeConstraints[index]?.hasSizeConstraints ?? false
          ? sizeConstraints[index]
          : null;
      double? value(
        SlotDimension? dimension,
        double available,
        double wholeLayout,
      ) => dimension?.resolve(
        configured?.percentBasis == SlotPercentBasis.layout
            ? wholeLayout
            : available,
      );
      double? preferredMain = configured == null
          ? legacy == null || !mainExtent(legacy).isFinite
                ? null
                : mainExtent(legacy)
          : value(
              horizontal
                  ? configured.preferredWidth
                  : configured.preferredHeight,
              maxMain,
              layoutMain,
            );
      double? preferredCross = configured == null
          ? legacy == null || !crossExtent(legacy).isFinite
                ? null
                : crossExtent(legacy)
          : value(
              horizontal
                  ? configured.preferredHeight
                  : configured.preferredWidth,
              maxCross,
              layoutCross,
            );
      double bound(
        SlotDimension? dimension,
        double available,
        double wholeLayout,
        double fallback, {
        double? limit,
      }) => (value(dimension, available, wholeLayout) ?? fallback).clamp(
        0.0,
        limit ?? (available.isFinite ? available : double.infinity),
      );
      final mainCap = scrollable ? double.infinity : null;
      final crossCap = !rawMaxCross.isFinite ? double.infinity : null;
      final minMain = bound(
        configured == null
            ? null
            : horizontal
            ? configured.minWidth
            : configured.minHeight,
        maxMain,
        layoutMain,
        0,
        limit: mainCap,
      );
      final hasConfiguredMaxMain =
          configured != null &&
          (horizontal
              ? configured.maxWidth != null
              : configured.maxHeight != null);
      final maxConfiguredMain = bound(
        configured == null
            ? null
            : horizontal
            ? configured.maxWidth
            : configured.maxHeight,
        maxMain,
        layoutMain,
        mainCap ?? maxMain,
        limit: mainCap,
      );
      final minCross = bound(
        configured == null
            ? null
            : horizontal
            ? configured.minHeight
            : configured.minWidth,
        maxCross,
        layoutCross,
        0,
        limit: crossCap,
      );
      final hasConfiguredMaxCross =
          configured != null &&
          (horizontal
              ? configured.maxHeight != null
              : configured.maxWidth != null);
      final maxConfiguredCross = bound(
        configured == null
            ? null
            : horizontal
            ? configured.maxHeight
            : configured.maxWidth,
        maxCross,
        layoutCross,
        crossCap ?? maxCross,
        limit: crossCap,
      );
      var effectiveMaxMain = maxConfiguredMain < minMain
          ? minMain
          : maxConfiguredMain;
      var effectiveMaxCross = maxConfiguredCross < minCross
          ? minCross
          : maxConfiguredCross;
      if (preferredMain != null) {
        preferredMain = preferredMain.clamp(
          minMain,
          hasConfiguredMaxMain ? effectiveMaxMain : double.infinity,
        );
        if (!hasConfiguredMaxMain && preferredMain > effectiveMaxMain) {
          effectiveMaxMain = preferredMain;
        }
      }
      if (preferredCross != null) {
        preferredCross = preferredCross.clamp(
          minCross,
          hasConfiguredMaxCross || rawMaxCross.isFinite
              ? effectiveMaxCross
              : double.infinity,
        );
        if (!hasConfiguredMaxCross &&
            !rawMaxCross.isFinite &&
            preferredCross > effectiveMaxCross) {
          effectiveMaxCross = preferredCross;
        }
      }
      bounds.add((
        minMain,
        effectiveMaxMain,
        preferredMain,
        minCross,
        effectiveMaxCross,
        preferredCross,
      ));
    }
    _bounds = bounds;
    final count = children.length;
    final spacing = _configuration.spacing;
    final totalSpacing = count > 1 ? spacing * (count - 1) : 0.0;
    var naturalExtent = 0.0;
    var preferredExtent = 0.0;
    var fills = 0;
    bool fillsSpace(int index) {
      if (!expand || scrollable || bounds[index].$3 != null) return false;
      final fitOverride = sizeConstraints[index]?.fitContent;
      if (fitOverride != null) return !fitOverride;
      if (_configuration.sizing[index] != SlotSizing.fill) return false;
      return _configuration.expandSlots &&
          _configuration.mainAxisAlignment == MainAxisAlignment.start;
    }

    BoxConstraints childConstraints(int index, {double? main, double? cross}) {
      final bound = bounds[index];
      final min = dimensions(
        main ?? bound.$1,
        cross ?? (stretchCross ? bound.$5 : bound.$4),
      );
      final max = dimensions(main ?? bound.$2, cross ?? bound.$5);
      return BoxConstraints(
        minWidth: min.width,
        maxWidth: max.width,
        minHeight: min.height,
        maxHeight: max.height,
      );
    }

    // Mesurer le contenu naturel avant de partager le reste entre les tailles
    // préférées et les slots fill évite un débordement avec des slots mixtes.
    for (final (index, child) in children.indexed) {
      final bound = bounds[index];
      if (bound.$3 != null) {
        preferredExtent += bound.$3!;
      } else if (fillsSpace(index)) {
        fills++;
      } else {
        child.layout(
          childConstraints(index, cross: bound.$6),
          parentUsesSize: true,
        );
        naturalExtent += mainExtent(child.size);
      }
    }
    final available = (maxMain - naturalExtent - totalSpacing).clamp(
      0.0,
      double.infinity,
    );
    final scale = !scrollable && preferredExtent > available
        ? available / preferredExtent
        : 1.0;
    final fillExtent = fills == 0
        ? 0.0
        : (available - preferredExtent * scale).clamp(0.0, double.infinity) /
              fills;
    var childrenMain = 0.0;
    var cross = 0.0;
    for (final (index, child) in children.indexed) {
      final bound = bounds[index];
      if (bound.$3 != null || fillsSpace(index)) {
        final desiredMain = bound.$3 ?? fillExtent.clamp(bound.$1, bound.$2);
        final scaledMain = bound.$3 == null
            ? desiredMain
            : (desiredMain * scale).clamp(bound.$1, bound.$2);
        child.layout(
          childConstraints(index, main: scaledMain, cross: bound.$6),
          parentUsesSize: true,
        );
      }
      childrenMain += mainExtent(child.size);
      if (crossExtent(child.size) > cross) cross = crossExtent(child.size);
    }
    final contentMain = childrenMain + totalSpacing;
    final targetMain = expand
        ? (scrollable ? math.max(maxMain, contentMain) : maxMain)
        : contentMain;
    final freeSpace = math.max(0.0, targetMain - contentMain);
    final (
      double leading,
      double stepSpacing,
    ) = switch (_configuration.mainAxisAlignment) {
      MainAxisAlignment.start => (0.0, spacing),
      MainAxisAlignment.end => (freeSpace, spacing),
      MainAxisAlignment.center => (freeSpace / 2.0, spacing),
      MainAxisAlignment.spaceBetween => (
        0.0,
        count > 1 ? spacing + freeSpace / (count - 1) : 0.0,
      ),
      MainAxisAlignment.spaceAround => (
        count > 0 ? freeSpace / count / 2.0 : 0.0,
        count > 0 ? spacing + freeSpace / count : spacing,
      ),
      MainAxisAlignment.spaceEvenly => (
        count > 0 ? freeSpace / (count + 1) : 0.0,
        count > 0 ? spacing + freeSpace / (count + 1) : spacing,
      ),
    };
    final resolvedSize = constraints.constrain(
      dimensions(targetMain, stretch ? maxCross : cross),
    );
    final containerCross = crossExtent(resolvedSize);
    var main = leading;
    for (final (index, child) in children.indexed) {
      final childCross = crossExtent(child.size);
      final crossOffset = switch (_configuration.crossAxisAlignment) {
        CrossAxisAlignment.start || CrossAxisAlignment.baseline => 0.0,
        CrossAxisAlignment.stretch =>
          stretch ? 0.0 : math.max(0.0, (containerCross - childCross) / 2.0),
        CrossAxisAlignment.end => math.max(0.0, containerCross - childCross),
        CrossAxisAlignment.center => math.max(
          0.0,
          (containerCross - childCross) / 2.0,
        ),
      };
      (child.parentData! as _SlotParentData).offset = horizontal
          ? Offset(main, crossOffset)
          : Offset(crossOffset, main);
      main += mainExtent(child.size);
      if (index < count - 1) main += stepSpacing;
    }
    size = resolvedSize;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
