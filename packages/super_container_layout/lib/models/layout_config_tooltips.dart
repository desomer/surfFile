/// Formatage des info-bulles de layout, de taille de slot et de flux de zone.
library;

import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show Axis, EdgeInsets;

import 'grid_layout_config.dart' show GridSlotPosition, SuperLayoutPositioning;
import 'slot_size_constraints.dart'
    show SlotDimension, SlotPercentBasis, SlotSizeConstraints, SlotSizeUnit;
import 'super_layout_config.dart' show SuperLayoutConfig, SuperLayoutZone;
import 'zone_flow_config.dart';

String _formatPaddingSummary(double padding, EdgeInsets? paddingInsets) {
  if (paddingInsets != null) {
    return 'H ${SlotDimension.formatNumber(paddingInsets.top)}, '
        'D ${SlotDimension.formatNumber(paddingInsets.right)}, '
        'B ${SlotDimension.formatNumber(paddingInsets.bottom)}, '
        'G ${SlotDimension.formatNumber(paddingInsets.left)} px';
  }
  return '${SlotDimension.formatNumber(padding)} px';
}

/// Résumé des paramètres de taille d'un élément pour l'info-bulle de l'icône règle.
String formatSlotSizeTooltip({
  required String title,
  SlotSizeConstraints? constraints,
  Size? preferredSize,
  GridSlotPosition? gridPosition,
}) {
  final useLegacy = constraints == null || !constraints.hasSizeConstraints;
  String formatAxis(
    String axisLabel,
    SlotDimension? preferred,
    SlotDimension? min,
    SlotDimension? max,
    double? legacyExtent,
  ) {
    final main =
        preferred?.format() ??
        (useLegacy && legacyExtent != null && legacyExtent.isFinite
            ? '${SlotDimension.formatNumber(legacyExtent)} px'
            : 'Auto');
    final bounds = <String>[
      if (min != null) 'min : ${min.format()}',
      if (max != null) 'max : ${max.format()}',
    ];
    return bounds.isEmpty
        ? '$axisLabel : $main'
        : '$axisLabel : $main (${bounds.join(', ')})';
  }

  final widthLine = formatAxis(
    'Largeur',
    constraints?.preferredWidth,
    constraints?.minWidth,
    constraints?.maxWidth,
    preferredSize?.width,
  );
  final heightLine = formatAxis(
    'Hauteur',
    constraints?.preferredHeight,
    constraints?.minHeight,
    constraints?.maxHeight,
    preferredSize?.height,
  );
  final hasPercent = [
    constraints?.minWidth,
    constraints?.minHeight,
    constraints?.maxWidth,
    constraints?.maxHeight,
    constraints?.preferredWidth,
    constraints?.preferredHeight,
  ].any((d) => d?.unit == SlotSizeUnit.percent);
  final flexLabel = switch (constraints?.fitContent) {
    true => 'Contenu (flex : 0)',
    false => 'Remplir (flex : 1)',
    null => 'Auto',
  };
  final paddingLabel = _formatPaddingSummary(
    constraints?.padding ?? 0,
    constraints?.paddingInsets,
  );
  return [
    title,
    if (gridPosition != null)
      'Grille : col. ${gridPosition.x}, lig. ${gridPosition.y} '
          '(${gridPosition.width} × ${gridPosition.height} cellules)',
    '$widthLine · $heightLine',
    [
      if (gridPosition == null) 'Flex : $flexLabel',
      if (hasPercent)
        'Base % : ${constraints!.percentBasis == SlotPercentBasis.layout ? 'Layout' : 'Zone'}',
      'Marge : $paddingLabel',
    ].join(' · '),
  ].join('\n');
}

/// Résumé des paramètres de taille et de flux d'une zone pour l'info-bulle de l'icône règle.
String formatZoneFlowTooltip({
  required String zoneLabel,
  required Axis axis,
  required ZoneFlowConfig flow,
  bool isSide = false,
  Axis? sizeAxis,
  bool autoSize = true,
  double? size,
  bool canResize = false,
}) {
  final autoOnFlowAxis = isSide && autoSize && sizeAxis == axis;
  final effectiveExpand = !autoOnFlowAxis && flow.expandSlots;
  final sizeLabel = !isSide
      ? null
      : [
          autoSize
              ? 'Taille : Auto'
              : 'Taille : ${SlotDimension.formatNumber(size ?? 100)} px',
          if (canResize) 'redimensionnable',
        ].join(' · ');
  final directionLabel = axis == Axis.horizontal
      ? 'Ligne (Row)'
      : 'Colonne (Column)';
  final elementsLabel = effectiveExpand
      ? 'Étirer (flex : 1)'
      : 'Contenu (flex : 0)';
  final paddingLabel = _formatPaddingSummary(flow.padding, flow.paddingInsets);
  return [
    'Taille et flux de la zone $zoneLabel',
    ?sizeLabel,
    'Direction : $directionLabel · Éléments : $elementsLabel',
    [
      if (flow.scrollable) ...[
        'Scroll : Activé',
        if (flow.showScrollbar) 'ScrollBar : ${flow.scrollbarStyle.summary}',
      ],
      'Espacement : ${SlotDimension.formatNumber(flow.spacing)} px',
      'Marge : $paddingLabel',
    ].join(' · '),
  ].join('\n');
}

/// Résumé des propriétés d'un [SuperLayoutConfig] pour l'info-bulle du menu contextuel.
String formatSuperLayoutTooltip({
  required String title,
  required SuperLayoutConfig config,
  String Function(SuperLayoutZone)? zoneLabel,
}) {
  final labelOf = zoneLabel ?? ((SuperLayoutZone z) => z.label);
  final elementCount = config.placedSlotIds.length;
  if (config.positioning == SuperLayoutPositioning.grid) {
    final grid = config.effectiveGrid;
    return [
      title,
      'Mode : Grille (${grid.columns} colonnes)',
      'Hauteur de ligne : ${SlotDimension.formatNumber(grid.rowHeight)} px · '
          'Espacement : ${SlotDimension.formatNumber(grid.gap)} px',
      'Éléments : $elementCount',
    ].join('\n');
  }
  final visible = [for (final z in config.visibleZones) labelOf(z)];
  final sides = <String>[
    for (final side in const [
      SuperLayoutZone.north,
      SuperLayoutZone.south,
      SuperLayoutZone.west,
      SuperLayoutZone.east,
    ])
      if (config.hasSide(side))
        '${labelOf(side)} : ${config.isAuto(side) ? 'Auto' : '${SlotDimension.formatNumber(config.sizeOf(side))} px'}',
  ];
  return [
    title,
    'Mode : Zones (${visible.join(', ')})',
    sides.isEmpty ? 'Côtés : Aucun' : sides.join(' · '),
    'Redimensionnement : ${config.resizeSides ? 'Activé' : 'Désactivé'} · '
        'Éléments : $elementCount',
  ].join('\n');
}
