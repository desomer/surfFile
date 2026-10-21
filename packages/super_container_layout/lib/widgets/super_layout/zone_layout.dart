part of 'super_layout.dart';

class _ZoneParentData extends ContainerBoxParentData<RenderBox> {
  SuperLayoutZone? zone;

  /// Un calque épouse le rectangle de sa zone sans compter dans sa mesure.
  bool overlay = false;

  /// Cible de dépôt : testée après le contenu, pour qu'une cible imbriquée soit
  /// consultée avant celle de la disposition qui la contient.
  bool dropTarget = false;
  bool resizeHandle = false;
}

/// Rattache un enfant de [_ZoneLayout] à une zone.
class _ZoneEntry extends ParentDataWidget<_ZoneParentData> {
  const _ZoneEntry({
    required this.zone,
    required super.child,
    this.overlay = false,
    this.dropTarget = false,
    this.resizeHandle = false,
    super.key,
  });

  final SuperLayoutZone zone;
  final bool overlay;
  final bool dropTarget;
  final bool resizeHandle;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _ZoneParentData;
    if (data.zone == zone &&
        data.overlay == overlay &&
        data.dropTarget == dropTarget &&
        data.resizeHandle == resizeHandle) {
      return;
    }
    data
      ..zone = zone
      ..overlay = overlay
      ..dropTarget = dropTarget;
    data.resizeHandle = resizeHandle;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _ZoneLayout;
}

/// Place les enfants dans les rectangles de [SuperLayoutConfig.resolve]. Les
/// côtés de [autoSides] sont d'abord mesurés (largeur de l'Ouest et de l'Est,
/// puis hauteur du Nord et du Sud), le centre reçoit le reste.
class _ZoneLayout extends MultiChildRenderObjectWidget {
  const _ZoneLayout({
    required this.config,
    required this.shrinkWrap,
    required this.autoSides,
    required this.emptyAutoSides,
    required super.children,
  });

  final SuperLayoutConfig config;
  final bool shrinkWrap;
  final Set<SuperLayoutZone> autoSides;
  final Set<SuperLayoutZone> emptyAutoSides;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderZoneLayout(config, autoSides, emptyAutoSides, shrinkWrap);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderZoneLayout renderObject,
  ) => renderObject
    ..config = config
    ..shrinkWrap = shrinkWrap
    ..autoSides = autoSides
    ..emptyAutoSides = emptyAutoSides;
}

class _RenderZoneLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ZoneParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ZoneParentData> {
  _RenderZoneLayout(
    this._config,
    this._autoSides,
    this._emptyAutoSides,
    this._shrinkWrap,
  );

  bool _shrinkWrap;
  set shrinkWrap(bool value) {
    if (_shrinkWrap == value) return;
    _shrinkWrap = value;
    markNeedsLayoutForSizedByParentChange();
  }

  Map<SuperLayoutZone, Rect> rects = const {};

  SuperLayoutConfig _config;
  set config(SuperLayoutConfig value) {
    if (value == _config) return;
    _config = value;
    markNeedsLayout();
  }

  Set<SuperLayoutZone> _autoSides;
  set autoSides(Set<SuperLayoutZone> value) {
    if (setEquals(value, _autoSides)) return;
    _autoSides = value;
    markNeedsLayout();
  }

  Set<SuperLayoutZone> _emptyAutoSides;
  set emptyAutoSides(Set<SuperLayoutZone> value) {
    if (setEquals(value, _emptyAutoSides)) return;
    _emptyAutoSides = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ZoneParentData) {
      child.parentData = _ZoneParentData();
    }
  }

  @override
  bool get sizedByParent => !_shrinkWrap;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (!_shrinkWrap) return constraints.biggest;
    return _measureContent(
      constraints,
      (child, limits) => child.getDryLayout(limits),
    ).size;
  }

  BoxConstraints _naturalLimits(SuperLayoutZone zone, BoxConstraints limits) {
    double fixed(SuperLayoutZone side) =>
        !_config.hasSide(side) ||
            _config.isAuto(side) ||
            _config.collapsedSides.containsKey(side)
        ? 0
        : _config.sizeOf(side);
    final west = fixed(SuperLayoutZone.west);
    final east = fixed(SuperLayoutZone.east);
    final width = switch (zone) {
      SuperLayoutZone.west ||
      SuperLayoutZone.nw ||
      SuperLayoutZone.sw when west > 0 => math.min(limits.maxWidth, west),
      SuperLayoutZone.east ||
      SuperLayoutZone.ne ||
      SuperLayoutZone.se when east > 0 => math.min(limits.maxWidth, east),
      SuperLayoutZone.center => math.max(0.0, limits.maxWidth - west - east),
      _ => limits.maxWidth,
    };
    final north = fixed(SuperLayoutZone.north);
    final south = fixed(SuperLayoutZone.south);
    final height = switch (zone) {
      SuperLayoutZone.north ||
      SuperLayoutZone.nw ||
      SuperLayoutZone.ne when north > 0 => math.min(limits.maxHeight, north),
      SuperLayoutZone.south ||
      SuperLayoutZone.sw ||
      SuperLayoutZone.se when south > 0 => math.min(limits.maxHeight, south),
      _ => limits.maxHeight,
    };
    return BoxConstraints(maxWidth: width, maxHeight: height);
  }

  ({Size size, Map<SuperLayoutZone, double> sides}) _measureContent(
    BoxConstraints limits,
    Size Function(RenderBox, BoxConstraints) measure,
  ) {
    final sizes = <SuperLayoutZone, Size>{};
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _ZoneParentData;
      if (!data.overlay && !_config.collapsedSides.containsKey(data.zone)) {
        sizes[data.zone!] = measure(child, _naturalLimits(data.zone!, limits));
      }
    }
    double width(SuperLayoutZone zone) => sizes[zone]?.width ?? 0;
    double height(SuperLayoutZone zone) => sizes[zone]?.height ?? 0;
    double side(SuperLayoutZone zone, double natural) =>
        _emptyAutoSides.contains(zone)
        ? 0
        : _config.collapsedSides.containsKey(zone)
        ? 0
        : _config.isAuto(zone)
        ? natural
        : _config.sizeOf(zone);
    final west = _config.west
        ? side(
            SuperLayoutZone.west,
            [
              width(SuperLayoutZone.west),
              width(SuperLayoutZone.nw),
              width(SuperLayoutZone.sw),
            ].reduce(math.max),
          )
        : 0.0;
    final east = _config.east
        ? side(
            SuperLayoutZone.east,
            [
              width(SuperLayoutZone.east),
              width(SuperLayoutZone.ne),
              width(SuperLayoutZone.se),
            ].reduce(math.max),
          )
        : 0.0;
    final north = _config.north
        ? side(
            SuperLayoutZone.north,
            [
              height(SuperLayoutZone.north),
              height(SuperLayoutZone.nw),
              height(SuperLayoutZone.ne),
            ].reduce(math.max),
          )
        : 0.0;
    final south = _config.south
        ? side(
            SuperLayoutZone.south,
            [
              height(SuperLayoutZone.south),
              height(SuperLayoutZone.sw),
              height(SuperLayoutZone.se),
            ].reduce(math.max),
          )
        : 0.0;
    final size = limits.constrain(
      Size(
        math.max(
          16,
          west +
              east +
              [
                width(SuperLayoutZone.center),
                width(SuperLayoutZone.north),
                width(SuperLayoutZone.south),
              ].reduce(math.max),
        ),
        math.max(
          16,
          north +
              south +
              [
                height(SuperLayoutZone.center),
                height(SuperLayoutZone.west),
                height(SuperLayoutZone.east),
              ].reduce(math.max),
        ),
      ),
    );
    return (
      size: size,
      sides: {
        SuperLayoutZone.west: west,
        SuperLayoutZone.east: east,
        SuperLayoutZone.north: north,
        SuperLayoutZone.south: south,
      },
    );
  }

  @override
  void performLayout() {
    final natural = _shrinkWrap
        ? _measureContent(constraints, (child, limits) {
            child.layout(limits, parentUsesSize: true);
            return child.size;
          })
        : null;
    if (natural != null) size = natural.size;
    final content = <SuperLayoutZone, RenderBox>{};
    final overlays = <(SuperLayoutZone, RenderBox)>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _ZoneParentData;
      final zone = data.zone!;
      if (data.overlay) {
        overlays.add((zone, child));
      } else {
        content[zone] = child;
      }
    }

    final measured = <SuperLayoutZone, double>{
      ...?natural?.sides,
      for (final side in _emptyAutoSides) side: 0,
    };
    for (final side in const [SuperLayoutZone.west, SuperLayoutZone.east]) {
      final child = content[side];
      if (_shrinkWrap || child == null || !_autoSides.contains(side)) continue;
      child.layout(
        BoxConstraints(maxWidth: size.width, maxHeight: size.height),
        parentUsesSize: true,
      );
      measured[side] = child.size.width;
    }
    // La largeur du Nord et du Sud dépend de celle de l'Ouest et de l'Est.
    final widths = _config.resolve(size, measured: measured);
    for (final side in const [SuperLayoutZone.north, SuperLayoutZone.south]) {
      final child = content[side];
      final rect = widths[side];
      if (_shrinkWrap ||
          child == null ||
          rect == null ||
          !_autoSides.contains(side)) {
        continue;
      }
      child.layout(
        BoxConstraints(
          minWidth: rect.width,
          maxWidth: rect.width,
          maxHeight: size.height,
        ),
        parentUsesSize: true,
      );
      measured[side] = child.size.height;
    }

    rects = _config.resolve(size, measured: measured);
    for (final (zone, child, overlay) in [
      for (final entry in content.entries) (entry.key, entry.value, false),
      for (final (zone, child) in overlays) (zone, child, true),
    ]) {
      var rect = rects[zone] ?? Rect.zero;
      final data = child.parentData! as _ZoneParentData;
      if (data.resizeHandle) {
        rect = switch (zone) {
          SuperLayoutZone.north => Rect.fromLTWH(
            rect.left,
            (rect.bottom - 24).clamp(0, size.height),
            rect.width,
            24,
          ),
          SuperLayoutZone.south => Rect.fromLTWH(
            rect.left,
            rect.top.clamp(0, (size.height - 24).clamp(0, size.height)),
            rect.width,
            24,
          ),
          SuperLayoutZone.west => Rect.fromLTWH(
            (rect.right - 24).clamp(0, size.width),
            rect.top,
            24,
            rect.height,
          ),
          _ => Rect.fromLTWH(
            rect.left.clamp(0, (size.width - 24).clamp(0, size.width)),
            rect.top,
            24,
            rect.height,
          ),
        };
      }
      final autoAxis =
          overlay ||
              !measured.containsKey(zone) ||
              _emptyAutoSides.contains(zone)
          ? null
          : (zone == SuperLayoutZone.north || zone == SuperLayoutZone.south)
          ? Axis.vertical
          : Axis.horizontal;
      // L'axe automatique reste libre, avec la borne de la mesure : des
      // contraintes strictes feraient du contenu une frontière de layout (son
      // changement de taille n'atteindrait pas ce parent), et une autre borne
      // changerait la taille mesurée.
      // Keep natural content on its measurement constraints so size changes
      // propagate back to the wrapping parent, including asynchronous bindings.
      child.layout(
        _shrinkWrap && !overlay
            ? _naturalLimits(zone, constraints)
            : switch (autoAxis) {
                null => BoxConstraints.tight(rect.size),
                Axis.vertical => BoxConstraints(
                  minWidth: rect.width,
                  maxWidth: rect.width,
                  maxHeight: size.height,
                ),
                Axis.horizontal => BoxConstraints(
                  minHeight: rect.height,
                  maxHeight: rect.height,
                  maxWidth: size.width,
                ),
              },
        parentUsesSize: _shrinkWrap || autoAxis != null,
      );
      (child.parentData! as _ZoneParentData).offset = rect.topLeft;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) => context.pushClipRect(
    needsCompositing,
    offset,
    Offset.zero & size,
    defaultPaint,
  );

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var hit = false;
    final dropTargets = <RenderBox>[];
    bool hitChild(RenderBox child) => result.addWithPaintOffset(
      offset: (child.parentData! as _ZoneParentData).offset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
    for (var child = lastChild; child != null; child = childBefore(child)) {
      if ((child.parentData! as _ZoneParentData).dropTarget) {
        dropTargets.add(child);
      } else if (!hit && hitChild(child)) {
        hit = true;
      }
    }
    // Un DragTarget ne consulte pas une cible apparue après un rejet : les
    // cibles imbriquées doivent donc précéder celle qui les contient.
    for (final child in dropTargets) {
      if (hitChild(child)) hit = true;
    }
    return hit;
  }
}
