/// Conteneur responsive de niveau page ([ResponsiveBodyContainer]) et portée [ResponsiveBreakpointScope].
///
/// Applique le mode [PageContainerMode.constrained] (largeur maximale centrée
/// avec marges latérales flexibles et gutters horizontaux adaptatifs selon les
/// breakpoints) exclusivement au `body` d'une page, tout en préservant le mode
/// [PageContainerMode.fullPage] par défaut.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../models/responsive_layout_config.dart';
import '../editing/slots/editor_slot.dart';

/// Portée descendante exposant le palier responsive et les métriques résolues du `body`.
class ResponsiveBreakpointScope extends InheritedWidget {
  const ResponsiveBreakpointScope({
    required this.layout,
    required this.viewportWidth,
    required super.child,
    super.key,
  });

  /// Configuration résolue (breakpoint actif, mode, `maxWidth`, `gutter`).
  final ResolvedPageLayout layout;

  /// Largeur disponible (px) ayant servi à résoudre [layout].
  final double viewportWidth;

  /// Retourne la portée [ResponsiveBreakpointScope] la plus proche, ou `null`.
  static ResponsiveBreakpointScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ResponsiveBreakpointScope>();

  /// Retourne le [ResponsiveBreakpoint] actif, ou `null` hors d'une portée.
  static ResponsiveBreakpoint? breakpointOf(BuildContext context) =>
      maybeOf(context)?.layout.breakpoint;

  /// Retourne le gutter horizontal actif (px), ou `0` hors d'une portée.
  static double gutterOf(BuildContext context) =>
      maybeOf(context)?.layout.gutter ?? 0;

  @override
  bool updateShouldNotify(ResponsiveBreakpointScope oldWidget) =>
      layout != oldWidget.layout || viewportWidth != oldWidget.viewportWidth;
}

/// Enveloppe le `body` d'une page pour appliquer [ResponsiveLayoutConfig].
///
/// - En [PageContainerMode.fullPage], rend [child] sans contrainte ni marge.
/// - En [PageContainerMode.constrained], centre le contenu dans `maxWidth`
///   (marges latérales flexibles automatiques sur grands écrans) avec un
///   padding horizontal égal au gutter du breakpoint actif.
class ResponsiveBodyContainer extends StatelessWidget {
  const ResponsiveBodyContainer({
    required this.config,
    required this.child,
    this.scrollable = false,
    this.scrollDirection = Axis.vertical,
    super.key,
  });

  /// Configuration responsive effective de la page.
  final ResponsiveLayoutConfig config;

  /// Contenu du `body` à contraindre et marger.
  final Widget child;

  /// Indique si ce conteneur est placé à l'intérieur d'un viewport défilant
  /// (ex. `SingleChildScrollView`) afin de préserver la hauteur naturelle.
  final bool scrollable;

  /// Axe de défilement lorsque [scrollable] est `true`.
  final Axis scrollDirection;

  @override
  Widget build(BuildContext context) {
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaWidth = MediaQuery.maybeSizeOf(context)?.width ?? 0.0;
        final finiteWidth = constraints.maxWidth.isFinite;
        final availableWidth = finiteWidth ? constraints.maxWidth : mediaWidth;
        final resolved = config.resolveForWidth(availableWidth);

        Widget content = child;
        if (resolved.isConstrained) {
          final maxWidth = resolved.maxWidth!;
          final isHorizontalScroll =
              scrollable && scrollDirection == Axis.horizontal;
          if (isHorizontalScroll) {
            final safeGutter = resolved.gutter;
            content = Padding(
              key: const ValueKey('responsive-body-constrained'),
              padding: EdgeInsets.symmetric(horizontal: safeGutter),
              child: child,
            );
          } else {
            final containerWidth = math.min(availableWidth, maxWidth);
            final safeGutter = math.min(
              resolved.gutter,
              math.max(0.0, containerWidth / 2),
            );
            Widget inner = Padding(
              padding: EdgeInsets.symmetric(horizontal: safeGutter),
              child: child,
            );
            if (editing) {
              inner = _ResponsiveEditGuidesOverlay(
                containerWidth: containerWidth,
                gutter: safeGutter,
                showContainerBorders: availableWidth > containerWidth + 1,
                child: inner,
              );
            }
            content = Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                key: const ValueKey('responsive-body-constrained'),
                width: containerWidth,
                height: !scrollable && constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : null,
                child: inner,
              ),
            );
          }
        }

        return ResponsiveBreakpointScope(
          layout: resolved,
          viewportWidth: availableWidth,
          child: content,
        );
      },
    );
  }
}

/// Dessine des repères visuels discrets pour le conteneur centré et ses gutters en mode édition.
class _ResponsiveEditGuidesOverlay extends StatelessWidget {
  const _ResponsiveEditGuidesOverlay({
    required this.containerWidth,
    required this.gutter,
    required this.showContainerBorders,
    required this.child,
  });

  final double containerWidth;
  final double gutter;
  final bool showContainerBorders;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final guideColor = scheme.primary.withValues(alpha: 0.22);
    final gutterTint = scheme.primary.withValues(alpha: 0.04);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (gutter > 0) ...[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: gutter,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: gutterTint,
                  border: Border(
                    left: showContainerBorders
                        ? BorderSide(color: guideColor)
                        : BorderSide.none,
                    right: BorderSide(color: guideColor),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: gutter,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: gutterTint,
                  border: Border(
                    left: BorderSide(color: guideColor),
                    right: showContainerBorders
                        ? BorderSide(color: guideColor)
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ] else if (showContainerBorders) ...[
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    vertical: BorderSide(color: guideColor),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
