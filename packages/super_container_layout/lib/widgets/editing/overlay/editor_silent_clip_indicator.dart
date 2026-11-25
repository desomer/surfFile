/// Indicateur visuel en mode édition signalant un clipping silencieux par débordement
/// d'un [RenderBox] enfant hors d'un parent ayant `clipBehavior != Clip.none`.
///
/// S'intercale sans impact géométrique autour d'un [EditorSlot] pour inspecter,
/// lors de la phase de peinture, les conteneurs de rognage non défilables
/// (`RenderClipRect`, `RenderClipRRect`, `RenderPhysicalShape`, etc.) et tracer
/// un contour hachuré d'avertissement dès qu'une perte visuelle est détectée.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../components/super_layout/slot_core.dart'
    show SilentClipRelayoutTarget;
import 'editor_overlay.dart'
    show EditorOverlayVisibility, isRenderObjectOffstage;

/// Indique si [node] est un [RenderBox] appliquant un rognage effectif
/// (`clipBehavior != Clip.none`).
bool isSilentClippingRenderObject(RenderObject node) =>
    (node is RenderClipRect && node.clipBehavior != Clip.none) ||
    (node is RenderClipRRect && node.clipBehavior != Clip.none) ||
    (node is RenderClipOval && node.clipBehavior != Clip.none) ||
    (node is RenderClipPath && node.clipBehavior != Clip.none) ||
    (node is RenderPhysicalModel && node.clipBehavior != Clip.none) ||
    (node is RenderPhysicalShape && node.clipBehavior != Clip.none) ||
    (node is RenderStack && node.clipBehavior != Clip.none) ||
    (node is RenderFlex && node.clipBehavior != Clip.none) ||
    (node is RenderWrap && node.clipBehavior != Clip.none) ||
    (node is RenderFlow && node.clipBehavior != Clip.none);

/// Peintre du contour hachuré d'avertissement affiché en mode édition
/// lorsqu'un enfant déborde d'un parent clippé (`clipBehavior != Clip.none`).
class EditorSilentClipWarningPainter {
  const EditorSilentClipWarningPainter._();

  /// Couleur principale ambrée d'avertissement de rognage.
  static const Color primaryWarningColor = Color(0xFFF59E0B);

  /// Couleur secondaire contrastée des hachures diagonales.
  static const Color stripeContrastColor = Color(0xFFB45309);

  /// Couleur vive soulignant les bords où le contenu est effectivement coupé.
  static const Color clippedEdgeColor = Color(0xFFDC2626);

  /// Dessine le contour hachuré d'avertissement sur [canvas] dans [rect].
  static void paint(
    Canvas canvas, {
    required Rect rect,
    double radius = 0,
    double zoomScale = 1.0,
    Set<AxisDirection> clippedEdges = const <AxisDirection>{},
  }) {
    if (rect.isEmpty || rect.width <= 4 || rect.height <= 4) return;

    final effectiveZoom = zoomScale > 0 && zoomScale.isFinite ? zoomScale : 1.0;
    final bandWidth = (4.0 / effectiveZoom).clamp(2.0, 6.0);
    final maxCorner = math.max(0.0, math.min(16.0, rect.shortestSide / 2));
    final outerRadius = radius.clamp(0.0, maxCorner).toDouble();
    final innerRect = rect.deflate(bandWidth);
    final outerRRect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(outerRadius),
    );

    canvas.save();
    if (!innerRect.isEmpty && innerRect.width > 1 && innerRect.height > 1) {
      final innerRadius = math.max(0.0, outerRadius - bandWidth);
      final ringPath = Path.combine(
        PathOperation.difference,
        Path()..addRRect(outerRRect),
        Path()
          ..addRRect(
            RRect.fromRectAndRadius(innerRect, Radius.circular(innerRadius)),
          ),
      );
      canvas.clipPath(ringPath);
    } else {
      canvas.clipRRect(outerRRect);
    }

    // Fond ambré semi-transparent de la bande d'avertissement.
    canvas.drawRect(
      rect,
      Paint()..color = primaryWarningColor.withValues(alpha: 0.28),
    );

    // Hachures diagonales à 45° sur tout le périmètre.
    final stripeStep = (8.0 / effectiveZoom).clamp(4.0, 12.0);
    final stripeStroke = (3.0 / effectiveZoom).clamp(1.5, 4.5);
    final hatchPaint = Paint()
      ..color = stripeContrastColor.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stripeStroke;

    final hatchPath = Path();
    final span = rect.width + rect.height;
    for (var d = -rect.height; d <= span; d += stripeStep) {
      hatchPath.moveTo(rect.left + d, rect.top);
      hatchPath.lineTo(rect.left + d - rect.height, rect.bottom);
    }
    canvas.drawPath(hatchPath, hatchPaint);
    canvas.restore();

    // Filet extérieur net pour garantir la lisibilité sur fond clair et sombre.
    final outerStrokeWidth = (1.4 / effectiveZoom).clamp(0.8, 2.2);
    canvas.drawRRect(
      outerRRect.deflate(outerStrokeWidth / 2),
      Paint()
        ..color = primaryWarningColor.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerStrokeWidth,
    );

    // Surlignage renforcé sur les bords exacts où la perte visuelle se produit.
    if (clippedEdges.isNotEmpty) {
      final edgePaint = Paint()
        ..color = clippedEdgeColor.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.2 / effectiveZoom).clamp(1.2, 3.2)
        ..strokeCap = StrokeCap.round;
      final inset = outerStrokeWidth;
      if (clippedEdges.contains(AxisDirection.up)) {
        canvas.drawLine(
          Offset(rect.left + outerRadius, rect.top + inset),
          Offset(rect.right - outerRadius, rect.top + inset),
          edgePaint,
        );
      }
      if (clippedEdges.contains(AxisDirection.down)) {
        canvas.drawLine(
          Offset(rect.left + outerRadius, rect.bottom - inset),
          Offset(rect.right - outerRadius, rect.bottom - inset),
          edgePaint,
        );
      }
      if (clippedEdges.contains(AxisDirection.left)) {
        canvas.drawLine(
          Offset(rect.left + inset, rect.top + outerRadius),
          Offset(rect.left + inset, rect.bottom - outerRadius),
          edgePaint,
        );
      }
      if (clippedEdges.contains(AxisDirection.right)) {
        canvas.drawLine(
          Offset(rect.right - inset, rect.top + outerRadius),
          Offset(rect.right - inset, rect.bottom - outerRadius),
          edgePaint,
        );
      }
    }
  }
}

/// Widget enveloppant un slot éditable pour afficher un contour hachuré
/// d'avertissement en mode édition lorsqu'un clipping silencieux est détecté.
class EditorSilentClipIndicator extends SingleChildRenderObjectWidget {
  /// Crée un indicateur de clipping silencieux pour le mode édition.
  const EditorSilentClipIndicator({
    required this.enabled,
    this.radius = 0,
    this.zoomScale = 1.0,
    required Widget super.child,
    super.key,
  });

  /// Active la détection et le tracé du contour hachuré (mode édition).
  final bool enabled;

  /// Rayon d'arrondi de la surface cible.
  final double radius;

  /// Facteur de zoom courant du canevas d'édition (`EditorZoomScope`).
  final double zoomScale;

  @override
  RenderEditorSilentClipIndicator createRenderObject(BuildContext context) =>
      RenderEditorSilentClipIndicator(
        enabled: enabled,
        radius: radius,
        zoomScale: zoomScale,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderEditorSilentClipIndicator renderObject,
  ) {
    renderObject
      ..enabled = enabled
      ..radius = radius
      ..zoomScale = zoomScale;
  }
}

/// [RenderProxyBox] détectant sans surcoût de layout les débordements d'enfants
/// rognés silencieusement (`clipBehavior != Clip.none`) et peignant l'alerte.
class RenderEditorSilentClipIndicator extends RenderProxyBox
    implements SilentClipRelayoutTarget {
  /// Construit le [RenderProxyBox] de détection de clipping silencieux.
  RenderEditorSilentClipIndicator({
    required bool enabled,
    required double radius,
    required double zoomScale,
  }) {
    _enabled = enabled;
    _radius = radius;
    _zoomScale = zoomScale;
  }

  static const double _overflowEpsilon = 1.0;
  static const int _maxInspectedNodes = 96;

  late bool _enabled;

  /// Indique si l'indicateur de mode édition est actif.
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _lastClippedEdges = const <AxisDirection>{};
    }
    markNeedsPaint();
  }

  late double _radius;

  /// Rayon de bordure utilisé pour dessiner l'encadrement hachuré.
  double get radius => _radius;
  set radius(double value) {
    if (_radius == value) return;
    _radius = value;
    markNeedsPaint();
  }

  late double _zoomScale;

  /// Facteur d'échelle courant du canevas d'édition.
  double get zoomScale => _zoomScale;
  set zoomScale(double value) {
    if (_zoomScale == value) return;
    _zoomScale = value;
    markNeedsPaint();
  }

  Set<AxisDirection> _lastClippedEdges = const <AxisDirection>{};

  /// Indique si un clipping silencieux a été détecté lors du dernier rendu.
  bool get hasSilentClipOverflow => _lastClippedEdges.isNotEmpty;

  /// Bords sur lesquels un enfant est silencieusement rogné.
  Set<AxisDirection> get clippedEdges => _lastClippedEdges;

  void _onDialogsVisibilityChanged() {
    if (attached && _enabled) {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    EditorOverlayVisibility.openDialogs.addListener(
      _onDialogsVisibilityChanged,
    );
  }

  @override
  void detach() {
    EditorOverlayVisibility.openDialogs.removeListener(
      _onDialogsVisibilityChanged,
    );
    super.detach();
  }

  @override
  void notifyDescendantLayoutChanged() {
    if (_enabled && attached) {
      markNeedsPaint();
    }
  }

  void _notifyAncestorIndicators() {
    RenderObject? current = parent;
    while (current != null) {
      if (current is RenderAbstractViewport) break;
      if (current is SilentClipRelayoutTarget) {
        current.notifyDescendantLayoutChanged();
      }
      current = current.parent;
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_enabled) {
      _notifyAncestorIndicators();
    }
  }

  static void _collectOverflowEdgesAgainstClipBox(
    RenderBox clipBox,
    RenderObject subtreeRoot,
    Set<AxisDirection> outEdges,
  ) {
    if (!clipBox.attached || !clipBox.hasSize || clipBox.size.isEmpty) return;
    final clipSize = clipBox.size;
    var visited = 0;

    void walkDescendants(RenderObject node) {
      if (visited >= _maxInspectedNodes || outEdges.length == 4) return;
      node.visitChildren((child) {
        if (visited >= _maxInspectedNodes || outEdges.length == 4) return;
        visited++;
        if (child is RenderAbstractViewport) return;
        if ((child is RenderOffstage && child.offstage) ||
            (child is RenderSliverOffstage && child.offstage)) {
          return;
        }
        if (child is RenderBox &&
            child.attached &&
            child.hasSize &&
            !child.size.isEmpty) {
          final transform = child.getTransformTo(clipBox);
          if (!transform.isZero()) {
            final rect = MatrixUtils.transformRect(
              transform,
              Offset.zero & child.size,
            );
            if (rect.isFinite) {
              if (rect.left < -_overflowEpsilon) {
                outEdges.add(AxisDirection.left);
              }
              if (rect.top < -_overflowEpsilon) {
                outEdges.add(AxisDirection.up);
              }
              if (rect.right > clipSize.width + _overflowEpsilon) {
                outEdges.add(AxisDirection.right);
              }
              if (rect.bottom > clipSize.height + _overflowEpsilon) {
                outEdges.add(AxisDirection.down);
              }
            }
          }
        }
        walkDescendants(child);
      });
    }

    if (identical(subtreeRoot, clipBox)) {
      walkDescendants(clipBox);
    } else if (subtreeRoot is RenderBox &&
        subtreeRoot.attached &&
        subtreeRoot.hasSize &&
        !subtreeRoot.size.isEmpty) {
      final transform = subtreeRoot.getTransformTo(clipBox);
      if (!transform.isZero()) {
        final rect = MatrixUtils.transformRect(
          transform,
          Offset.zero & subtreeRoot.size,
        );
        if (rect.isFinite) {
          if (rect.left < -_overflowEpsilon) outEdges.add(AxisDirection.left);
          if (rect.top < -_overflowEpsilon) outEdges.add(AxisDirection.up);
          if (rect.right > clipSize.width + _overflowEpsilon) {
            outEdges.add(AxisDirection.right);
          }
          if (rect.bottom > clipSize.height + _overflowEpsilon) {
            outEdges.add(AxisDirection.down);
          }
        }
      }
      walkDescendants(subtreeRoot);
    }
  }

  Set<AxisDirection> _detectSilentClipEdges() {
    final rootChild = child;
    if (rootChild == null || !hasSize || size.isEmpty) {
      return const <AxisDirection>{};
    }
    if (isRenderObjectOffstage(this)) {
      return const <AxisDirection>{};
    }

    final detectedEdges = <AxisDirection>{};
    var ownedVisited = 0;

    // 1. Inspecte les RenderBox de clipping appartenant directement à ce slot
    //    (avant toute entrée dans un EditorSlot enfant ou un viewport défilant).
    void findOwnedClipBoxes(RenderObject node) {
      if (ownedVisited >= _maxInspectedNodes || detectedEdges.length == 4) {
        return;
      }
      ownedVisited++;
      if (node is RenderAbstractViewport) return;
      if ((node is RenderOffstage && node.offstage) ||
          (node is RenderSliverOffstage && node.offstage)) {
        return;
      }
      if (!identical(node, this) && node is RenderEditorSilentClipIndicator) {
        return;
      }
      if (node is RenderBox && isSilentClippingRenderObject(node)) {
        _collectOverflowEdgesAgainstClipBox(node, node, detectedEdges);
      }
      node.visitChildren(findOwnedClipBoxes);
    }

    findOwnedClipBoxes(rootChild);

    // 2. Si aucun parent EditorSlot ne possède un ancêtre clippé au-dessus de ce slot,
    //    vérifie aussi les ancêtres de rognage immédiats (ex. ClipRect englobant isolé).
    if (detectedEdges.isEmpty) {
      RenderObject? ancestor = parent;
      var hops = 0;
      final unownedAncestorClips = <RenderBox>[];
      var ownedByParentSlot = false;
      while (ancestor != null && hops < 12) {
        hops++;
        if (ancestor is RenderAbstractViewport) break;
        if ((ancestor is RenderOffstage && ancestor.offstage) ||
            (ancestor is RenderSliverOffstage && ancestor.offstage)) {
          break;
        }
        if (ancestor is RenderEditorSilentClipIndicator) {
          ownedByParentSlot = true;
          break;
        }
        if (ancestor is RenderBox && isSilentClippingRenderObject(ancestor)) {
          unownedAncestorClips.add(ancestor);
        }
        ancestor = ancestor.parent;
      }
      if (!ownedByParentSlot && unownedAncestorClips.isNotEmpty) {
        for (final clipBox in unownedAncestorClips) {
          _collectOverflowEdgesAgainstClipBox(clipBox, this, detectedEdges);
        }
      }
    }

    return detectedEdges.isEmpty
        ? const <AxisDirection>{}
        : Set<AxisDirection>.unmodifiable(detectedEdges);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_enabled || !hasSize || size.isEmpty) {
      _lastClippedEdges = const <AxisDirection>{};
      return;
    }
    final edges = _detectSilentClipEdges();
    _lastClippedEdges = edges;
    if (edges.isEmpty || EditorOverlayVisibility.openDialogs.value > 0) {
      return;
    }
    EditorSilentClipWarningPainter.paint(
      context.canvas,
      rect: offset & size,
      radius: _radius,
      zoomScale: _zoomScale,
      clippedEdges: edges,
    );
  }
}
