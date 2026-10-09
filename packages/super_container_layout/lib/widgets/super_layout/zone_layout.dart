part of '../super_layout.dart';

class _ZoneParentData extends ContainerBoxParentData<RenderBox> {
  SuperLayoutZone? zone;

  /// Un calque épouse le rectangle de sa zone sans compter dans sa mesure.
  bool overlay = false;

  /// Cible de dépôt : testée après le contenu, pour qu'une cible imbriquée soit
  /// consultée avant celle de la disposition qui la contient.
  bool dropTarget = false;
}

/// Rattache un enfant de [_ZoneLayout] à une zone.
class _ZoneEntry extends ParentDataWidget<_ZoneParentData> {
  const _ZoneEntry({
    required this.zone,
    required super.child,
    this.overlay = false,
    this.dropTarget = false,
    super.key,
  });

  final SuperLayoutZone zone;
  final bool overlay;
  final bool dropTarget;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _ZoneParentData;
    if (data.zone == zone &&
        data.overlay == overlay &&
        data.dropTarget == dropTarget) {
      return;
    }
    data
      ..zone = zone
      ..overlay = overlay
      ..dropTarget = dropTarget;
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
    required this.autoSides,
    required super.children,
  });

  final SuperLayoutConfig config;
  final Set<SuperLayoutZone> autoSides;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderZoneLayout(config, autoSides);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderZoneLayout renderObject,
  ) => renderObject
    ..config = config
    ..autoSides = autoSides;
}

class _RenderZoneLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ZoneParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ZoneParentData> {
  _RenderZoneLayout(this._config, this._autoSides);

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

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ZoneParentData) {
      child.parentData = _ZoneParentData();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
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

    final measured = <SuperLayoutZone, double>{};
    for (final side in const [SuperLayoutZone.west, SuperLayoutZone.east]) {
      final child = content[side];
      if (child == null || !_autoSides.contains(side)) continue;
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
      if (child == null || rect == null || !_autoSides.contains(side)) continue;
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
      final rect = rects[zone] ?? Rect.zero;
      final autoAxis = overlay || !measured.containsKey(zone)
          ? null
          : (zone == SuperLayoutZone.north || zone == SuperLayoutZone.south)
          ? Axis.vertical
          : Axis.horizontal;
      // L'axe automatique reste libre, avec la borne de la mesure : des
      // contraintes strictes feraient du contenu une frontière de layout (son
      // changement de taille n'atteindrait pas ce parent), et une autre borne
      // changerait la taille mesurée.
      child.layout(switch (autoAxis) {
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
      }, parentUsesSize: autoAxis != null);
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
