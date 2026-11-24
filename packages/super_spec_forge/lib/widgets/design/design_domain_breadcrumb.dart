/// Barre de fil d'Ariane réutilisable des pages Design, avec sélecteur du
/// domaine en cours ([DesignDomainBreadcrumbBar]).
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/domain_catalog.dart';

/// Segment cliquable, actif ou secondaire du fil d'Ariane Design.
@immutable
class DesignBreadcrumbSegment {
  /// Crée un segment de fil d'Ariane.
  const DesignBreadcrumbSegment({
    required this.label,
    this.key,
    this.onTap,
    this.isParent = false,
    this.isSecondary = false,
    this.padding,
  });

  /// Clé optionnelle appliquée au widget du segment.
  final Key? key;

  /// Libellé affiché dans le chevron.
  final String label;

  /// Action exécutée au clic sur un segment parent, ou `null` si inactif.
  final VoidCallback? onTap;

  /// Force le style de segment parent même sans [onTap].
  final bool isParent;

  /// Indique un segment secondaire non cliquable (ex. numéro de version).
  final bool isSecondary;

  /// Marges internes additionnelles autour du contenu dans la zone utile du chevron.
  final EdgeInsetsGeometry? padding;
}

/// Fil d'Ariane horizontal des vues Design permettant de changer de domaine en
/// cours via un menu déroulant et de naviguer entre les niveaux de la page.
class DesignDomainBreadcrumbBar extends StatefulWidget {
  /// Crée une barre de fil d'Ariane contextualisée par [selectedDomain].
  const DesignDomainBreadcrumbBar({
    required this.domains,
    required this.selectedDomain,
    required this.onDomainSelected,
    required this.segments,
    this.domainCrumbKey = const ValueKey('design-domain-crumb'),
    super.key,
  });

  /// Domaines disponibles dans le catalogue du workspace.
  final List<FunctionalDomain> domains;

  /// Domaine actuellement sélectionné (domaine en cours), ou `null` si vide.
  final FunctionalDomain? selectedDomain;

  /// Callback déclenché lorsqu'un autre domaine est choisi dans le menu.
  final ValueChanged<FunctionalDomain> onDomainSelected;

  /// Segments affichés après le domaine en cours.
  final List<DesignBreadcrumbSegment> segments;

  /// Clé de test du bouton de sélection du domaine.
  final Key? domainCrumbKey;

  @override
  State<DesignDomainBreadcrumbBar> createState() =>
      _DesignDomainBreadcrumbBarState();
}

class _DesignDomainBreadcrumbBarState extends State<DesignDomainBreadcrumbBar> {
  static const double _barHeight = 40;
  static const double _ribbonHeight = 32;
  static const double _chevronDepth = 11;
  static const double _outerRadius = 6;

  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = widget.selectedDomain;
    final domains = widget.domains;
    final segments = widget.segments;
    final hasSegments = segments.isNotEmpty;

    final domainBg = selected == null
        ? colors.surfaceContainerHighest
        : colors.primary;
    final domainFg = selected == null
        ? colors.onSurfaceVariant
        : colors.onPrimary;

    return Container(
      height: _barHeight,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: _ChevronRibbonRow(
          overlap: _chevronDepth,
          children: [
            _buildChevronShell(
              notchLeft: false,
              tipRight: hasSegments,
              backgroundColor: domainBg,
              borderColor: colors.outlineVariant.withValues(alpha: 0.65),
              separatorColor: colors.surfaceContainerLow,
              child: MenuAnchor(
                controller: _menu,
                menuChildren: [
                  for (final domain in domains)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ChoiceChip(
                        key: ValueKey('design-domain-option-${domain.id}'),
                        label: Text(
                          domain.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        tooltip: '${domain.name} · ${domain.domainCode}',
                        selected: domain.id == selected?.id,
                        onSelected: (_) {
                          widget.onDomainSelected(domain);
                          _menu.close();
                        },
                      ),
                    ),
                ],
                builder: (context, menu, _) => Tooltip(
                  message: 'Choisir un domaine',
                  child: InkWell(
                    key: widget.domainCrumbKey,
                    mouseCursor: selected == null
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    hoverColor: domainFg.withValues(alpha: 0.10),
                    splashColor: domainFg.withValues(alpha: 0.16),
                    onTap: selected == null
                        ? null
                        : () => menu.isOpen ? menu.close() : menu.open(),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 10,
                        right: hasSegments ? _chevronDepth + 8 : 10,
                      ),
                      child: SizedBox(
                        height: _ribbonHeight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 6,
                          children: [
                            Icon(Icons.domain_rounded, size: 16, color: domainFg),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(
                                selected?.name ?? 'Aucun domaine',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: domainFg,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (selected != null)
                              Icon(
                                Icons.arrow_drop_down_rounded,
                                size: 18,
                                color: domainFg,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < segments.length; i++)
              _buildSegment(
                context,
                segment: segments[i],
                isLast: i == segments.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context, {
    required DesignBreadcrumbSegment segment,
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tipRight = !isLast;
    final isClickable = segment.onTap != null;

    final Color bg;
    final Color fg;
    final TextStyle? textStyle;

    if (segment.isSecondary) {
      bg = colors.surfaceContainer;
      fg = colors.onSurfaceVariant;
      textStyle = theme.textTheme.labelMedium?.copyWith(
        color: fg,
        fontWeight: FontWeight.w500,
        fontSize: 12,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
    } else if (isClickable || segment.isParent) {
      bg = colors.secondaryContainer;
      fg = colors.onSecondaryContainer;
      textStyle = theme.textTheme.labelLarge?.copyWith(
        color: fg,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      );
    } else {
      bg = colors.surfaceContainerHighest;
      fg = colors.onSurface;
      textStyle = theme.textTheme.labelLarge?.copyWith(
        color: fg,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      );
    }

    final innerPadding =
        segment.padding ?? const EdgeInsets.symmetric(horizontal: 10);
    final content = Padding(
      padding: EdgeInsets.only(
        left: _chevronDepth,
        right: tipRight ? _chevronDepth : 0,
      ),
      child: Container(
        height: _ribbonHeight,
        alignment: Alignment.center,
        padding: innerPadding,
        child: Text(
          segment.label,
          style: textStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    return _buildChevronShell(
      notchLeft: true,
      tipRight: tipRight,
      backgroundColor: bg,
      borderColor: colors.outlineVariant.withValues(alpha: 0.65),
      separatorColor: colors.surfaceContainerLow,
      child: isClickable
          ? InkWell(
              key: segment.key,
              mouseCursor: SystemMouseCursors.click,
              hoverColor: fg.withValues(alpha: 0.08),
              splashColor: fg.withValues(alpha: 0.14),
              onTap: segment.onTap,
              child: content,
            )
          : KeyedSubtree(key: segment.key, child: content),
    );
  }

  Widget _buildChevronShell({
    required bool notchLeft,
    required bool tipRight,
    required Color backgroundColor,
    required Color borderColor,
    required Color separatorColor,
    required Widget child,
  }) {
    final clipper = _ChevronClipper(
      notchLeft: notchLeft,
      tipRight: tipRight,
      depth: _chevronDepth,
      radius: _outerRadius,
    );

    return ClipPath(
      clipper: clipper,
      child: CustomPaint(
        foregroundPainter: _ChevronBorderPainter(
          notchLeft: notchLeft,
          tipRight: tipRight,
          depth: _chevronDepth,
          radius: _outerRadius,
          borderColor: borderColor,
          separatorColor: separatorColor,
        ),
        child: Material(color: backgroundColor, child: child),
      ),
    );
  }
}

Path _buildChevronPath(
  Size size, {
  required bool notchLeft,
  required bool tipRight,
  required double depth,
  required double radius,
}) {
  final w = size.width;
  final h = size.height;
  final midY = h / 2;
  final r = math.min(radius, math.min(w, h) / 2);
  final d = math.min(depth, w / 2);

  final path = Path();
  if (notchLeft) {
    path.moveTo(0, 0);
  } else {
    path.moveTo(0, r);
    path.quadraticBezierTo(0, 0, r, 0);
  }

  if (tipRight) {
    path
      ..lineTo(w - d, 0)
      ..lineTo(w, midY)
      ..lineTo(w - d, h);
  } else {
    path
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h);
  }

  if (notchLeft) {
    path
      ..lineTo(0, h)
      ..lineTo(d, midY)
      ..close();
  } else {
    path
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..close();
  }
  return path;
}

class _ChevronClipper extends CustomClipper<Path> {
  const _ChevronClipper({
    required this.notchLeft,
    required this.tipRight,
    required this.depth,
    required this.radius,
  });

  final bool notchLeft;
  final bool tipRight;
  final double depth;
  final double radius;

  @override
  Path getClip(Size size) => _buildChevronPath(
    size,
    notchLeft: notchLeft,
    tipRight: tipRight,
    depth: depth,
    radius: radius,
  );

  @override
  bool shouldReclip(_ChevronClipper oldClipper) =>
      oldClipper.notchLeft != notchLeft ||
      oldClipper.tipRight != tipRight ||
      oldClipper.depth != depth ||
      oldClipper.radius != radius;
}

class _ChevronBorderPainter extends CustomPainter {
  const _ChevronBorderPainter({
    required this.notchLeft,
    required this.tipRight,
    required this.depth,
    required this.radius,
    required this.borderColor,
    required this.separatorColor,
  });

  final bool notchLeft;
  final bool tipRight;
  final double depth;
  final double radius;
  final Color borderColor;
  final Color separatorColor;

  @override
  void paint(Canvas canvas, Size size) {
    final outerPath = _buildChevronPath(
      size,
      notchLeft: notchLeft,
      tipRight: tipRight,
      depth: depth,
      radius: radius,
    );
    final outerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;
    canvas.drawPath(outerPath, outerPaint);

    if (notchLeft) {
      final d = math.min(depth, size.width / 2);
      final seamPath = Path()
        ..moveTo(0, 0)
        ..lineTo(d, size.height / 2)
        ..lineTo(0, size.height);
      final seamPaint = Paint()
        ..color = separatorColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.miter
        ..isAntiAlias = true;
      canvas.drawPath(seamPath, seamPaint);
    }
  }

  @override
  bool shouldRepaint(_ChevronBorderPainter oldDelegate) =>
      oldDelegate.notchLeft != notchLeft ||
      oldDelegate.tipRight != tipRight ||
      oldDelegate.depth != depth ||
      oldDelegate.radius != radius ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.separatorColor != separatorColor;
}

/// Aligne horizontalement les chevrons avec un chevauchement négatif exact [overlap]
/// afin que chaque encoche épouse la pointe du segment précédent sans jour.
class _ChevronRibbonRow extends MultiChildRenderObjectWidget {
  const _ChevronRibbonRow({required this.overlap, required super.children});

  final double overlap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderChevronRibbonRow(overlap);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderChevronRibbonRow renderObject,
  ) {
    renderObject.overlap = overlap;
  }
}

class _ChevronRibbonParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderChevronRibbonRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ChevronRibbonParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ChevronRibbonParentData> {
  _RenderChevronRibbonRow(this._overlap);

  double _overlap;
  double get overlap => _overlap;
  set overlap(double value) {
    if (_overlap == value) return;
    _overlap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ChevronRibbonParentData) {
      child.parentData = _ChevronRibbonParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var total = 0.0;
    var index = 0;
    var child = firstChild;
    while (child != null) {
      final childWidth = child.getMinIntrinsicWidth(height);
      total += index == 0 ? childWidth : math.max(0.0, childWidth - _overlap);
      child = childAfter(child);
      index++;
    }
    return total;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var total = 0.0;
    var index = 0;
    var child = firstChild;
    while (child != null) {
      final childWidth = child.getMaxIntrinsicWidth(height);
      total += index == 0 ? childWidth : math.max(0.0, childWidth - _overlap);
      child = childAfter(child);
      index++;
    }
    return total;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    var maxHeight = 0.0;
    var child = firstChild;
    while (child != null) {
      maxHeight = math.max(maxHeight, child.getMinIntrinsicHeight(width));
      child = childAfter(child);
    }
    return maxHeight;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    var maxHeight = 0.0;
    var child = firstChild;
    while (child != null) {
      maxHeight = math.max(maxHeight, child.getMaxIntrinsicHeight(width));
      child = childAfter(child);
    }
    return maxHeight;
  }

  @override
  void performLayout() {
    final childConstraints = BoxConstraints(
      minHeight: 0,
      maxHeight: constraints.maxHeight,
    );

    var cursorX = 0.0;
    var maxHeight = 0.0;
    var index = 0;
    var child = firstChild;

    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      final data = child.parentData! as _ChevronRibbonParentData;
      final x = index == 0 ? 0.0 : math.max(0.0, cursorX - _overlap);
      data.offset = Offset(x, 0);
      cursorX = x + child.size.width;
      maxHeight = math.max(maxHeight, child.size.height);
      child = data.nextSibling;
      index++;
    }

    size = constraints.constrain(Size(cursorX, maxHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
