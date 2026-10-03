import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/appearance.dart';

/// Géométrie des éléments de la liste ou de la grille, dans le repère du
/// contenu défilant. Sert à la sélection par cadre, au clavier et au
/// défilement vers l'élément actif.
class EntriesLayout {
  factory EntriesLayout({
    required bool grid,
    required Appearance appearance,
    required Size viewport,
    required int count,
    bool compact = false,
  }) {
    if (!grid) {
      final padding = compact ? compactListPadding : listPadding;
      return EntriesLayout._(
        padding: padding,
        viewport: viewport,
        count: count,
        columns: 1,
        itemWidth: math.max(0, viewport.width - padding.horizontal),
        itemHeight: appearance.rowHeight,
        strideX: 0,
        strideY: appearance.rowHeight + appearance.spacing / 6,
      );
    }
    // Reprend SliverGridDelegateWithMaxCrossAxisExtent.
    final spacing = appearance.spacing;
    final width = math.max(0.0, viewport.width - gridPadding.horizontal);
    final columns = math.max(
      1,
      (width / (appearance.cardWidth + spacing)).ceil(),
    );
    final itemWidth = math.max(0.0, width - spacing * (columns - 1)) / columns;
    return EntriesLayout._(
      padding: gridPadding,
      viewport: viewport,
      count: count,
      columns: columns,
      itemWidth: itemWidth,
      itemHeight: appearance.cardHeight,
      strideX: itemWidth + spacing,
      strideY: appearance.cardHeight + spacing,
    );
  }

  const EntriesLayout._({
    required this.padding,
    required this.viewport,
    required this.count,
    required this.columns,
    required this.itemWidth,
    required this.itemHeight,
    required this.strideX,
    required this.strideY,
  });

  static const listPadding = EdgeInsets.fromLTRB(26, 2, 26, 24);

  /// Liste d'une colonne de la vue en colonnes.
  static const compactListPadding = EdgeInsets.fromLTRB(
    compactHorizontalPadding,
    2,
    compactHorizontalPadding,
    24,
  );
  static const compactHorizontalPadding = 8.0;
  static const gridPadding = EdgeInsets.fromLTRB(30, 8, 30, 28);

  final EdgeInsets padding;
  final Size viewport;
  final int count;
  final int columns;
  final double itemWidth;
  final double itemHeight;
  final double strideX;
  final double strideY;

  int get rows => (count / columns).ceil();

  /// Nombre de lignes entièrement visibles (au moins une).
  int get rowsPerPage =>
      math.max(1, ((viewport.height - padding.vertical) / strideY).floor());

  Rect itemRect(int index) => Rect.fromLTWH(
    padding.left + (index % columns) * strideX,
    padding.top + (index ~/ columns) * strideY,
    itemWidth,
    itemHeight,
  );

  /// Indices des éléments qui croisent [rect].
  Iterable<int> hits(Rect rect) {
    if (count == 0) return const [];
    final first = ((rect.top - padding.top) / strideY).floor().clamp(0, rows);
    final last = ((rect.bottom - padding.top) / strideY).floor().clamp(
      -1,
      rows - 1,
    );
    final area = rect.inflate(.5);
    return [
      for (var row = first; row <= last; row++)
        for (var column = 0; column < columns; column++)
          if (row * columns + column < count &&
              itemRect(row * columns + column).overlaps(area))
            row * columns + column,
    ];
  }
}
