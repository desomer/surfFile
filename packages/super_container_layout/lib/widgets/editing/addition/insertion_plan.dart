import 'dart:math' as math;

import 'package:flutter/rendering.dart' show RenderSliver;
import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart' show SlotSizeConstraints;

/// Side of the target where the new component appears.
enum InsertDirection {
  right('À droite', 'à droite', Icons.arrow_forward),
  left('À gauche', 'à gauche', Icons.arrow_back),
  up('Au-dessus', 'vers le haut', Icons.arrow_upward),
  down('En dessous', 'vers le bas', Icons.arrow_downward);

  const InsertDirection(this.label, this.pushLabel, this.icon);

  final String label;
  final String pushLabel;
  final IconData icon;

  Axis get axis =>
      this == right || this == left ? Axis.horizontal : Axis.vertical;

  /// Whether the direction follows the reading order of its axis.
  bool get forward => this == right || this == down;

  IconData get pushIcon => switch (this) {
    right => Icons.keyboard_double_arrow_right,
    left => Icons.keyboard_double_arrow_left,
    up => Icons.keyboard_double_arrow_up,
    down => Icons.keyboard_double_arrow_down,
  };
}

enum InsertMode {
  /// The new component goes next to the target, which keeps its size.
  beside,

  /// The new component takes the target's place and size; the target is
  /// shifted in the direction.
  push,
}

/// How the container of a target stacks its children.
class InsertionHost {
  const InsertionHost({
    required this.axis,
    this.stacked = true,
    this.single = false,
    this.axisMutable = false,
    this.canWrap = true,
  });

  /// Axis along which siblings are stacked.
  final Axis axis;

  /// False for hosts without a stacking order, such as a grid.
  final bool stacked;

  /// The host holds a single component.
  final bool single;

  /// The stack only holds the target and its axis may be switched.
  final bool axisMutable;

  /// The host accepts a `Layout` wrapper in place of the target.
  final bool canWrap;
}

/// The resolved way to add a component next to a target.
sealed class InsertionPlan {
  const InsertionPlan(this.direction, this.mode);

  final InsertDirection direction;
  final InsertMode mode;

  /// Whether the new component precedes the target along the axis.
  bool get newFirst =>
      mode == InsertMode.beside ? !direction.forward : direction.forward;

  /// Human description of the structural change.
  String get hint;
}

/// The new component joins the target's own stack.
class DirectInsertion extends InsertionPlan {
  const DirectInsertion(super.direction, super.mode, {this.axis});

  /// New axis of the stack, when it must be switched first.
  final Axis? axis;

  @override
  String get hint => switch (axis) {
    Axis.horizontal => 'La zone passe en ligne',
    Axis.vertical => 'La zone passe en colonne',
    null => 'Dans la même zone',
  };
}

/// The target is wrapped in a new `Layout` holding it and the new component in
/// its center zone, stacked along [axis].
class WrapInsertion extends InsertionPlan {
  const WrapInsertion(super.direction, super.mode);

  Axis get axis => direction.axis;

  @override
  String get hint => axis == Axis.horizontal
      ? 'Englobe dans un Layout en ligne'
      : 'Englobe dans un Layout en colonne';
}

/// Chooses how to add a component in [direction] of a target held by [host];
/// null when impossible.
InsertionPlan? planInsertion(
  InsertionHost host,
  InsertDirection direction,
  InsertMode mode,
) {
  if (host.stacked && !host.single) {
    if (direction.axis == host.axis) return DirectInsertion(direction, mode);
    if (host.axisMutable) {
      return DirectInsertion(direction, mode, axis: direction.axis);
    }
  }
  return host.canWrap ? WrapInsertion(direction, mode) : null;
}

/// Component chosen in the contextual add wizard.
class InsertedComponent {
  const InsertedComponent({
    required this.type,
    required this.configure,
    this.label,
    this.size,
  });

  /// Placement type, such as `factory:<key>` or `component:<id>`.
  final String type;

  /// Instance label; null keeps the component label.
  final String? label;

  /// Explicit size; null keeps the host's default sizing.
  final SlotSizeConstraints? size;

  /// Writes the component settings under its new instance ID.
  final void Function(String instanceId) configure;
}

/// Resolved rectangles of a placement preview in the coordinate space of an
/// ancestor [RenderObject].
class InsertionPreviewBounds {
  const InsertionPreviewBounds({
    required this.insertRect,
    this.referenceRect,
  });

  /// Where the new component will be placed.
  final Rect insertRect;

  /// Existing element or container zone used as reference.
  final Rect? referenceRect;

  /// Union of [insertRect] and [referenceRect] for camera framing.
  Rect get framingRect => referenceRect == null
      ? insertRect
      : insertRect.expandToInclude(referenceRect!);

  @override
  bool operator ==(Object other) =>
      other is InsertionPreviewBounds &&
      other.insertRect == insertRect &&
      other.referenceRect == referenceRect;

  @override
  int get hashCode => Object.hash(insertRect, referenceRect);
}

/// Visual bounds of [target] in the coordinate space of [ancestor].
Rect? boundsOfContextIn(BuildContext? target, RenderObject ancestor) {
  if (target == null || !target.mounted || !ancestor.attached) return null;
  final ro = target.findRenderObject();
  if (ro == null || !ro.attached || ro.owner != ancestor.owner) return null;
  Size? size;
  if (ro is RenderBox && ro.hasSize) {
    size = ro.size;
  } else if (ro is RenderSliver) {
    final geom = ro.geometry;
    if (geom != null && geom.paintExtent > 0) {
      size = ro.constraints.axis == Axis.vertical
          ? Size(ro.constraints.crossAxisExtent, geom.paintExtent)
          : Size(geom.paintExtent, ro.constraints.crossAxisExtent);
    }
  }
  if (size == null || size.isEmpty || !size.isFinite) return null;
  final rect = MatrixUtils.transformRect(
    ro.getTransformTo(ancestor),
    Offset.zero & size,
  );
  return rect.isEmpty || !rect.isFinite ? null : rect;
}

/// Visual preview of a placement option hovered in the add wizard.
class ComponentAddPlacementPreview {
  const ComponentAddPlacementPreview({
    required this.resolve,
    this.focusContext,
    this.label,
    this.icon,
  });

  /// Preview of an insertion relative to a slot [targetContext].
  factory ComponentAddPlacementPreview.aroundSlot({
    required BuildContext? Function() targetContext,
    required InsertionPlan plan,
    String? label,
    IconData? icon,
  }) => ComponentAddPlacementPreview(
    focusContext: targetContext,
    label: label ??
        (plan.mode == InsertMode.beside
            ? plan.direction.label
            : 'À la place, pousse ${plan.direction.pushLabel}'),
    icon: icon ??
        (plan.mode == InsertMode.beside
            ? plan.direction.icon
            : plan.direction.pushIcon),
    resolve: (ancestor) {
      final slotRect = boundsOfContextIn(targetContext(), ancestor);
      if (slotRect == null) return null;
      final horizontal = plan.direction.axis == Axis.horizontal;
      final extent = horizontal ? slotRect.width : slotRect.height;
      final band = (extent * 0.38)
          .clamp(math.min(24.0, extent * 0.5), extent * 0.5)
          .toDouble();
      if (plan.mode == InsertMode.beside) {
        final insertRect = switch (plan.direction) {
          InsertDirection.left => Rect.fromLTWH(
            slotRect.left,
            slotRect.top,
            band,
            slotRect.height,
          ),
          InsertDirection.right => Rect.fromLTWH(
            slotRect.right - band,
            slotRect.top,
            band,
            slotRect.height,
          ),
          InsertDirection.up => Rect.fromLTWH(
            slotRect.left,
            slotRect.top,
            slotRect.width,
            band,
          ),
          InsertDirection.down => Rect.fromLTWH(
            slotRect.left,
            slotRect.bottom - band,
            slotRect.width,
            band,
          ),
        };
        return InsertionPreviewBounds(
          insertRect: insertRect,
          referenceRect: slotRect,
        );
      }
      final shiftedRect = switch (plan.direction) {
        InsertDirection.left => Rect.fromLTWH(
          slotRect.left - band,
          slotRect.top,
          band,
          slotRect.height,
        ),
        InsertDirection.right => Rect.fromLTWH(
          slotRect.right,
          slotRect.top,
          band,
          slotRect.height,
        ),
        InsertDirection.up => Rect.fromLTWH(
          slotRect.left,
          slotRect.top - band,
          slotRect.width,
          band,
        ),
        InsertDirection.down => Rect.fromLTWH(
          slotRect.left,
          slotRect.bottom,
          slotRect.width,
          band,
        ),
      };
      return InsertionPreviewBounds(
        insertRect: slotRect,
        referenceRect: shiftedRect,
      );
    },
  );

  /// Preview of an addition inside a container zone or region.
  factory ComponentAddPlacementPreview.inZone({
    BuildContext? Function()? zoneContext,
    BuildContext? Function()? containerContext,
    Axis? Function()? axis,
    bool replaces = false,
    InsertDirection? inactiveEdge,
    BuildContext? Function()? beforeContext,
    BuildContext? Function()? lastSiblingContext,
    String? label,
    IconData? icon = Icons.add_box_outlined,
  }) => ComponentAddPlacementPreview(
    focusContext: () =>
        beforeContext?.call() ??
        zoneContext?.call() ??
        containerContext?.call(),
    label: label,
    icon: icon,
    resolve: (ancestor) {
      final zoneRect = boundsOfContextIn(zoneContext?.call(), ancestor);
      final containerRect = boundsOfContextIn(
        containerContext?.call(),
        ancestor,
      );
      final effectiveAxis = axis == null ? Axis.vertical : axis();
      if (beforeContext != null) {
        final beforeRect = boundsOfContextIn(beforeContext(), ancestor);
        if (beforeRect != null) {
          final horizontal = effectiveAxis == Axis.horizontal;
          final extent = horizontal ? beforeRect.width : beforeRect.height;
          final band = (extent * 0.4)
              .clamp(math.min(24.0, extent * 0.5), extent * 0.5)
              .toDouble();
          final insertRect = horizontal
              ? Rect.fromLTWH(
                  beforeRect.left,
                  beforeRect.top,
                  band,
                  beforeRect.height,
                )
              : Rect.fromLTWH(
                  beforeRect.left,
                  beforeRect.top,
                  beforeRect.width,
                  band,
                );
          return InsertionPreviewBounds(
            insertRect: insertRect,
            referenceRect: zoneRect ?? beforeRect,
          );
        }
      }
      if (zoneRect != null) {
        if (replaces || effectiveAxis == null) {
          return InsertionPreviewBounds(
            insertRect: zoneRect,
            referenceRect: containerRect,
          );
        }
        final lastRect = boundsOfContextIn(
          lastSiblingContext?.call(),
          ancestor,
        );
        if (lastRect != null) {
          if (effectiveAxis == Axis.vertical) {
            final remaining = zoneRect.bottom - lastRect.bottom;
            if (remaining >= 24.0) {
              final height = math.min(
                remaining,
                math.max(lastRect.height, 36.0),
              );
              return InsertionPreviewBounds(
                insertRect: Rect.fromLTWH(
                  zoneRect.left,
                  lastRect.bottom,
                  zoneRect.width,
                  height,
                ),
                referenceRect: zoneRect,
              );
            }
            final maxBand = math.max(
              math.min(24.0, zoneRect.height * 0.5),
              math.max(28.0, lastRect.height * 0.6),
            );
            final band = (zoneRect.height * 0.35)
                .clamp(math.min(24.0, zoneRect.height * 0.5), maxBand)
                .clamp(0.0, zoneRect.height)
                .toDouble();
            return InsertionPreviewBounds(
              insertRect: Rect.fromLTWH(
                zoneRect.left,
                zoneRect.bottom - band,
                zoneRect.width,
                band,
              ),
              referenceRect: zoneRect,
            );
          } else {
            final remaining = zoneRect.right - lastRect.right;
            if (remaining >= 24.0) {
              final width = math.min(
                remaining,
                math.max(lastRect.width, 48.0),
              );
              return InsertionPreviewBounds(
                insertRect: Rect.fromLTWH(
                  lastRect.right,
                  zoneRect.top,
                  width,
                  zoneRect.height,
                ),
                referenceRect: zoneRect,
              );
            }
            final maxBand = math.max(
              math.min(24.0, zoneRect.width * 0.5),
              math.max(36.0, lastRect.width * 0.6),
            );
            final band = (zoneRect.width * 0.35)
                .clamp(math.min(24.0, zoneRect.width * 0.5), maxBand)
                .clamp(0.0, zoneRect.width)
                .toDouble();
            return InsertionPreviewBounds(
              insertRect: Rect.fromLTWH(
                zoneRect.right - band,
                zoneRect.top,
                band,
                zoneRect.height,
              ),
              referenceRect: zoneRect,
            );
          }
        }
        return InsertionPreviewBounds(
          insertRect: zoneRect,
          referenceRect: containerRect,
        );
      }
      if (containerRect == null) return null;
      final insertRect = switch (inactiveEdge) {
        InsertDirection.up => Rect.fromLTWH(
          containerRect.left,
          containerRect.top,
          containerRect.width,
          (containerRect.height * 0.22)
              .clamp(
                math.min(24.0, containerRect.height),
                math.max(
                  math.min(24.0, containerRect.height),
                  math.min(72.0, containerRect.height * 0.45),
                ),
              )
              .toDouble(),
        ),
        InsertDirection.down => () {
          final h = (containerRect.height * 0.22)
              .clamp(
                math.min(24.0, containerRect.height),
                math.max(
                  math.min(24.0, containerRect.height),
                  math.min(72.0, containerRect.height * 0.45),
                ),
              )
              .toDouble();
          return Rect.fromLTWH(
            containerRect.left,
            containerRect.bottom - h,
            containerRect.width,
            h,
          );
        }(),
        InsertDirection.left => Rect.fromLTWH(
          containerRect.left,
          containerRect.top,
          (containerRect.width * 0.22)
              .clamp(
                math.min(24.0, containerRect.width),
                math.max(
                  math.min(24.0, containerRect.width),
                  math.min(140.0, containerRect.width * 0.45),
                ),
              )
              .toDouble(),
          containerRect.height,
        ),
        InsertDirection.right => () {
          final w = (containerRect.width * 0.22)
              .clamp(
                math.min(24.0, containerRect.width),
                math.max(
                  math.min(24.0, containerRect.width),
                  math.min(140.0, containerRect.width * 0.45),
                ),
              )
              .toDouble();
          return Rect.fromLTWH(
            containerRect.right - w,
            containerRect.top,
            w,
            containerRect.height,
          );
        }(),
        null => containerRect,
      };
      return InsertionPreviewBounds(
        insertRect: insertRect,
        referenceRect: containerRect,
      );
    },
  );

  /// Resolves the preview bounds in the coordinate space of [ancestor].
  final InsertionPreviewBounds? Function(RenderObject ancestor) resolve;

  /// Optional context of the target element or container for zoom framing.
  final BuildContext? Function()? focusContext;

  /// Short label displayed inside the preview overlay.
  final String? label;

  /// Icon displayed inside the preview overlay.
  final IconData? icon;
}

/// Active placement preview hovered in the component add wizard.
class EditorInsertionPreview {
  EditorInsertionPreview._();

  static final ValueNotifier<ComponentAddPlacementPreview?> active =
      ValueNotifier<ComponentAddPlacementPreview?>(null);
}

/// A level of the contextual add wizard, from the clicked element outwards.
sealed class ContextualAddLevel {
  const ContextualAddLevel();
}

/// Lets a host add a component around one of its children.
class EditorSlotInsertion extends ContextualAddLevel {
  const EditorSlotInsertion({
    required this.label,
    required this.host,
    required this.acceptsTags,
    required this.insert,
    this.zoneTags = const {},
    this.targetContext,
  });

  /// Name of the target, shown as a level of the wizard.
  final String label;
  final InsertionHost host;

  /// Whether the host accepts a component with these tags as a direct child.
  final bool Function(Set<String> tags) acceptsTags;

  /// Tags the host zone is dedicated to (its filter's `include`).
  final Set<String> zoneTags;
  final Future<void> Function(InsertionPlan plan, InsertedComponent component)
  insert;

  /// Visual context of the target slot used to preview relative positions.
  final BuildContext? Function()? targetContext;
}

/// A zone or region of an existing container able to receive a component.
class EditorAddZone {
  const EditorAddZone({
    required this.id,
    required this.label,
    required this.insert,
    this.accepts,
    this.hint,
    this.zoneTags = const {},
    this.preview,
  });

  final String id;
  final String label;

  /// Whether the zone accepts a component with these tags.
  final bool Function(Set<String> tags)? accepts;

  /// Tags the zone is dedicated to (its filter's `include`).
  final Set<String> zoneTags;

  /// Consequence of the addition; defaults to an addition at the end.
  final String? hint;
  final Future<void> Function(InsertedComponent component) insert;

  /// Visual preview of the zone placement on the page.
  final ComponentAddPlacementPreview? preview;

  bool accept(Set<String> tags) => accepts?.call(tags) ?? true;
}

/// The zones of one container, offered as a level of the wizard.
class EditorAddZoneGroup extends ContextualAddLevel {
  const EditorAddZoneGroup({required this.label, required this.zones});

  /// Name of the container.
  final String label;
  final List<EditorAddZone> zones;
}

/// Publishes the zones of a container (`SuperLayout`, native component) to
/// the contextual add wizard of the elements it contains.
class EditorAddZones extends InheritedWidget {
  const EditorAddZones({
    required this.label,
    required this.zones,
    required super.child,
    this.enabled = true,
    super.key,
  });

  final String label;

  /// Evaluated when the menu opens, the zone under the pointer first.
  final List<EditorAddZone> Function() zones;
  final bool enabled;

  EditorAddZoneGroup? group() {
    if (!enabled) return null;
    final list = zones();
    return list.isEmpty ? null : EditorAddZoneGroup(label: label, zones: list);
  }

  @override
  bool updateShouldNotify(EditorAddZones oldWidget) =>
      label != oldWidget.label ||
      zones != oldWidget.zones ||
      enabled != oldWidget.enabled;
}
