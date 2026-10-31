/// Disposition flex tolérante au débordement ([NoOverflowErrorFlex]).
///
/// Masque les avertissements de débordement visuel transitoires lors du redimensionnement.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

/// Widget `Flex` personnalisé supprimant l'indicateur visuel d'erreur de débordement Flutter.
class NoOverflowErrorFlex extends MultiChildRenderObjectWidget {
  final Axis direction;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;
  final Clip clipBehavior;

  const NoOverflowErrorFlex({
    super.key,
    required this.direction,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.max,
    this.clipBehavior = Clip.hardEdge,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderCustomFlex(
      textDirection: TextDirection.ltr,
      direction: direction,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderCustomFlex renderObject) {
    renderObject
      ..textDirection = TextDirection.ltr
      ..direction = direction
      ..mainAxisAlignment = mainAxisAlignment
      ..crossAxisAlignment = crossAxisAlignment
      ..mainAxisSize = mainAxisSize
      ..clipBehavior = clipBehavior;
  }
}

/// `RenderFlex` personnalisé ignorant le dessin des bandes d'erreur de débordement.
class RenderCustomFlex extends RenderFlex {
  RenderCustomFlex({
    required super.textDirection,
    required super.direction,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.mainAxisSize,
    super.clipBehavior,
  });

  @override
  paintOverflowIndicator(
    PaintingContext context,
    Offset offset,
    Rect containerRect,
    Rect childRect, {
    List<DiagnosticsNode>? overflowHints,
  }) {}

  @override
  void debugPaintSize(PaintingContext context, Offset offset) {
    // ⚠️ Ne pas dessiner les bordures de debug
    // On peut aussi ignorer cette méthode pour éviter les visuels de debug
  }
}
