import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/components/internal_widget/array/cw_table_row.dart';

bool withWidgetCache = true;

class FrozenTableView extends StatefulWidget {
  final int rowCount;
  final int colCount;
  final int colFreezeLeftCount;

  final int rowCountTop;
  final int rowCountBottom;

  final double rowWidthBorderR;
  final double rowWidthBorderL;

  final Widget Function(int row, int col) buildTopCell;
  final Widget Function(int row, int col) buildBottomCell;
  final Widget Function(int row, int col) buildLeftCell;
  final Widget Function(int row, int col) buildBodyCell;
  final Widget Function(
    int row,
    bool isStartCols,
    Widget child,
    FrozenTableViewState tableState,
  )
  buildRow;
  final double Function(int col, double usedWidth, bool isCalc, int nbFillCol)
  getColWidth;
  final double? Function(int row) getRowHeight;

  /// Appelé lorsqu'une ligne de données est sélectionnée au clic.
  final ValueChanged<int>? onRowTap;

  /// Appelé lorsque l'utilisateur clique sur le bouton d'action d'un en-tête de colonne.
  final void Function(int colIndex, Offset globalPosition)? onHeaderActionTap;

  /// Appelé lorsque les largeurs de colonnes sont modifiées ou réinitialisées.
  final ValueChanged<Map<int, double>>? onColumnWidthsChanged;

  /// Indice initial de la ligne sélectionnée.
  final int? initialSelectedRow;

  const FrozenTableView({
    super.key,
    required this.rowCount,
    required this.colCount,
    required this.buildTopCell,
    required this.buildBottomCell,
    required this.buildLeftCell,
    required this.buildBodyCell,
    required this.rowCountTop,
    required this.rowCountBottom,
    required this.colFreezeLeftCount,
    required this.getColWidth,
    required this.getRowHeight,
    required this.buildRow,
    required this.rowWidthBorderR,
    required this.rowWidthBorderL,
    this.onRowTap,
    this.onHeaderActionTap,
    this.onColumnWidthsChanged,
    this.initialSelectedRow,
  });

  @override
  State<FrozenTableView> createState() => FrozenTableViewState();
}

class CwRowCache {
  CwTableRowState? cwTableRowState;
  CwRowCache([this.cwTableRowState]);
  List<Widget?>? rowCells;
}

class FrozenTableViewState extends State<FrozenTableView> {
  final ScrollController vertical = ScrollController();
  final ScrollController vertical2 = ScrollController();
  final ScrollController horizontal1 = ScrollController();
  final ScrollController horizontal2 = ScrollController();
  final ScrollController horizontal3 = ScrollController();

  Map<int, double> colWidthMap = {};

  bool topScrollbarVisible = false;
  double topMargin = 0;

  Map<int, CwRowCache> visibleRowKeyA = {};
  Map<int, CwRowCache> visibleRowKeyB = {};

  /// Ligne actuellement survolée (partagée entre colonnes figées à gauche et corps).
  final ValueNotifier<int?> hoveredRowNotifier = ValueNotifier<int?>(null);

  /// Ligne actuellement sélectionnée (partagée entre colonnes figées à gauche et corps).
  final ValueNotifier<int?> selectedRowNotifier = ValueNotifier<int?>(null);

  void _notifyRowStates(int? row) {
    if (row == null) return;
    final rowA = visibleRowKeyA[row]?.cwTableRowState;
    if (rowA != null && rowA.mounted) {
      // ignore: invalid_use_of_protected_member
      rowA.setState(() {});
    }
    final rowB = visibleRowKeyB[row]?.cwTableRowState;
    if (rowB != null && rowB.mounted) {
      // ignore: invalid_use_of_protected_member
      rowB.setState(() {});
    }
  }

  void setHoveredRow(int? targetRow) {
    final previous = hoveredRowNotifier.value;
    if (previous == targetRow) return;
    hoveredRowNotifier.value = targetRow;
    _notifyRowStates(previous);
    _notifyRowStates(targetRow);
  }

  void selectRow(int targetRow) {
    final previous = selectedRowNotifier.value;
    if (previous != targetRow) {
      selectedRowNotifier.value = targetRow;
      _notifyRowStates(previous);
      _notifyRowStates(targetRow);
    }
    widget.onRowTap?.call(targetRow);
  }

  void resetColWidth(int colIndex) {
    if (colWidthMap.containsKey(colIndex)) {
      setState(() {
        colWidthMap.remove(colIndex);
      });
      widget.onColumnWidthsChanged?.call(Map<int, double>.unmodifiable(colWidthMap));
    }
  }

  CwTableRow? getCacheTableRowState(CwRowInfo info, Widget child) {
    CwTableRowState? cache = getCacheRow(info)?.cwTableRowState;
    if (cache != null && cache.mounted) {
      cache.setNewChild(child);
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (cache.mounted) {
            // ignore: invalid_use_of_protected_member
            cache.setState(() {});
          }
        });
      } else {
        // ignore: invalid_use_of_protected_member
        cache.setState(() {});
      }
    }
    return cache?.widget;
  }

  CwRowCache? getCacheRow(CwRowInfo info) {
    if (!withWidgetCache) {
      return null;
    }
    if (info.isStartCols) {
      return visibleRowKeyA[info.row];
    } else {
      return visibleRowKeyB[info.row];
    }
  }

  CwRowCache? getCacheRowByIdx(int row, bool isStartCols) {
    if (!withWidgetCache) {
      return null;
    }
    if (isStartCols) {
      return visibleRowKeyA[row];
    } else {
      return visibleRowKeyB[row];
    }
  }

  void disposeRowState(CwRowInfo info, CwTableRowState cwTableRowState) {
    if (info.isStartCols) {
      if (visibleRowKeyA[info.row]?.cwTableRowState == cwTableRowState) {
        visibleRowKeyA.remove(info.row);
      }
    } else {
      if (visibleRowKeyB[info.row]?.cwTableRowState == cwTableRowState) {
        visibleRowKeyB.remove(info.row);
      }
    }
  }

  void initRowState(CwRowInfo info, CwTableRowState cwTableRowState) {
    if (info.isStartCols) {
      final existing = visibleRowKeyA[info.row];
      if (existing == null) {
        visibleRowKeyA[info.row] = CwRowCache(cwTableRowState);
      } else {
        existing.cwTableRowState = cwTableRowState;
      }
    } else {
      final existing = visibleRowKeyB[info.row];
      if (existing == null) {
        visibleRowKeyB[info.row] = CwRowCache(cwTableRowState);
      } else {
        existing.cwTableRowState = cwTableRowState;
      }
    }
  }

  void setSelectedRowIndex(int row, {bool scrollIntoView = true}) {
    var rowFreezeTop = widget.rowCountTop;
    final targetRow = row + rowFreezeTop;
    selectedRowNotifier.value = targetRow;

    final rowA = visibleRowKeyA[targetRow]?.cwTableRowState;
    if (rowA != null && rowA.mounted) {
      // ignore: invalid_use_of_protected_member
      rowA.setState(() {});
    }
    final rowB = visibleRowKeyB[targetRow]?.cwTableRowState;
    if (rowB != null && rowB.mounted) {
      // ignore: invalid_use_of_protected_member
      rowB.setState(() {});
    }

    if (!scrollIntoView || !vertical2.hasClients) {
      return;
    }

    final pos = vertical2.position;
    final viewMin = pos.pixels;
    final viewMax = pos.pixels + pos.viewportDimension;

    double topPos = 0;
    for (int r = rowFreezeTop; r < row + rowFreezeTop; r++) {
      topPos += widget.getRowHeight(r) ?? 30;
    }
    if (topPos < viewMin) {
      vertical2.animateTo(
        topPos,
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeInOut,
      );
    }
    var bottomPos = topPos + (widget.getRowHeight(row + rowFreezeTop) ?? 30);
    if (bottomPos > viewMax) {
      double viewHeight = pos.viewportDimension;
      vertical2.animateTo(
        bottomPos - viewHeight,
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeInOut,
      );
    }
  }

  void _syncScroll(ScrollController source, ScrollController target) {
    if (!source.hasClients || !target.hasClients) return;
    if (target.offset != source.offset) {
      target.jumpTo(source.offset);
    }
  }

  final ValueNotifier<double> _horizontalOffset = ValueNotifier<double>(0.0);
  double _viewportWidth = 1200.0;
  List<double> _cachedColWidths = const [];
  List<double> _cachedRightColOffsets = const [];
  double _cachedLeftTotalWidth = 0.0;
  double _cachedRightTotalWidth = 0.0;

  void _updateHorizontalOffset(ScrollController source) {
    if (!source.hasClients) return;
    final offset = source.offset;
    if ((_horizontalOffset.value - offset).abs() > 16.0 || offset <= 0.0) {
      _horizontalOffset.value = offset;
    }
  }

  @override
  void initState() {
    super.initState();
    selectedRowNotifier.value = widget.initialSelectedRow;
    vertical.addListener(() {
      _syncScroll(vertical, vertical2);
    });
    vertical2.addListener(() {
      _syncScroll(vertical2, vertical);
    });
    horizontal1.addListener(() {
      _syncScroll(horizontal1, horizontal2);
      _syncScroll(horizontal1, horizontal3);
      _updateHorizontalOffset(horizontal1);
    });
    horizontal2.addListener(() {
      _syncScroll(horizontal2, horizontal1);
      _syncScroll(horizontal2, horizontal3);
      _updateHorizontalOffset(horizontal2);
    });
    horizontal3.addListener(() {
      _syncScroll(horizontal3, horizontal1);
      _syncScroll(horizontal3, horizontal2);
      _updateHorizontalOffset(horizontal3);
    });
  }

  @override
  void didUpdateWidget(covariant FrozenTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelectedRow != oldWidget.initialSelectedRow &&
        selectedRowNotifier.value != widget.initialSelectedRow) {
      final previous = selectedRowNotifier.value;
      selectedRowNotifier.value = widget.initialSelectedRow;
      _notifyRowStates(previous);
      _notifyRowStates(widget.initialSelectedRow);
    }
    for (final cache in visibleRowKeyA.values) {
      cache.rowCells = null;
    }
    for (final cache in visibleRowKeyB.values) {
      cache.rowCells = null;
    }
  }

  @override
  void dispose() {
    _horizontalOffset.dispose();
    hoveredRowNotifier.dispose();
    selectedRowNotifier.dispose();
    vertical.dispose();
    vertical2.dispose();
    horizontal1.dispose();
    horizontal2.dispose();
    horizontal3.dispose();
    super.dispose();
  }

  void _recomputeColumnMetrics() {
    final count = widget.colCount;
    final freeze = widget.colFreezeLeftCount.clamp(0, count);
    final widths = List<double>.filled(count, 0.0);

    double totalFixL = 0;
    int nbFillL = 0;
    for (int i = 0; i < freeze; i++) {
      if (colWidthMap.containsKey(i)) {
        totalFixL += colWidthMap[i]!;
        nbFillL++;
      } else {
        final w = widget.getColWidth(i, totalFixL, true, -1);
        if (w > 0) {
          totalFixL += w;
          nbFillL++;
        }
      }
    }
    double sumL = 0;
    for (int i = 0; i < freeze; i++) {
      final w =
          colWidthMap[i] ?? widget.getColWidth(i, totalFixL, false, nbFillL);
      widths[i] = w;
      sumL += w;
    }
    _cachedLeftTotalWidth = sumL + widget.rowWidthBorderL;

    double totalFixR = 0;
    int nbFillR = 0;
    for (int i = freeze; i < count; i++) {
      if (colWidthMap.containsKey(i)) {
        totalFixR += colWidthMap[i]!;
        nbFillR++;
      } else {
        final w = widget.getColWidth(i, totalFixR, true, -1);
        if (w > 0) {
          totalFixR += w;
          nbFillR++;
        }
      }
    }
    final rightCount = count - freeze;
    final offsets = List<double>.filled(rightCount + 1, 0.0);
    double sumR = 0;
    for (int i = freeze; i < count; i++) {
      final w =
          colWidthMap[i] ?? widget.getColWidth(i, totalFixR, false, nbFillR);
      widths[i] = w;
      offsets[i - freeze] = sumR;
      sumR += w;
    }
    offsets[rightCount] = sumR;
    _cachedRightColOffsets = offsets;
    _cachedRightTotalWidth = sumR + widget.rowWidthBorderR;
    _cachedColWidths = widths;
  }

  /// Plage `[startCol, endColExclusive]` des colonnes de droite visibles dans
  /// la fenêtre horizontale courante (avec marge de pré-chargement).
  (int, int) _visibleRightColumnRange() {
    final freeze = widget.colFreezeLeftCount.clamp(0, widget.colCount);
    final rightCount = widget.colCount - freeze;
    if (rightCount <= 0) return (freeze, freeze);
    if (rightCount <= 20) return (freeze, widget.colCount);

    final offsets = _cachedRightColOffsets;
    if (offsets.length != rightCount + 1) return (freeze, widget.colCount);

    final minX = math.max(0.0, _horizontalOffset.value - 200.0);
    final maxX = _horizontalOffset.value + _viewportWidth + 200.0;

    int low = 0;
    int high = rightCount - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (offsets[mid + 1] <= minX) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final startIdx = math.max(0, low - 1);

    low = startIdx;
    high = rightCount;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (offsets[mid] < maxX) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final endIdx = math.min(rightCount, low + 1);
    return (freeze + startIdx, freeze + endIdx);
  }

  @override
  Widget build(BuildContext context) {
    _recomputeColumnMetrics();
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftWidth = widget.colFreezeLeftCount > 0
            ? _cachedLeftTotalWidth
            : 0.0;
        _viewportWidth = constraints.maxWidth.isFinite
            ? math.max(200.0, constraints.maxWidth - leftWidth)
            : MediaQuery.sizeOf(context).width;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ------------------ TOP FROZEN ROW ------------------
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                _topFrozenColumn(),
                Expanded(child: _topFrozenRow()),
              ],
            ),

            // ------------------ BODY + LEFT FROZEN COLUMN ------------------
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _leftFrozenColumn(),
                  Expanded(child: _body()),
                ],
              ),
            ),

            // ------------------ BOTTOM FROZEN ROW ------------------
            Row(
              children: [
                _bottomFrozenColumn(),
                Expanded(child: _bottomFrozenRow()),
              ],
            ),
          ],
        );
      },
    );
  }

  double _computeColsWidth(int start, int end, double borderWidth) {
    double totalFix = 0;
    int nbFillCol = 0;
    for (int i = start; i < end; i++) {
      if (colWidthMap.containsKey(i)) {
        totalFix += colWidthMap[i]!;
        nbFillCol++;
        continue;
      }
      var colWidth = widget.getColWidth(i, totalFix, true, -1);
      if (colWidth > 0) {
        totalFix += colWidth;
        nbFillCol++;
      }
    }
    double total = 0;
    for (int i = start; i < end; i++) {
      if (colWidthMap.containsKey(i)) {
        total += colWidthMap[i]!;
        continue;
      }
      total += widget.getColWidth(i, totalFix, false, nbFillCol);
    }
    return total + borderWidth;
  }

  double getWitdhL(int start, int end) {
    if (start == 0 &&
        end == widget.colFreezeLeftCount &&
        _cachedColWidths.length == widget.colCount) {
      return _cachedLeftTotalWidth;
    }
    return _computeColsWidth(start, end, widget.rowWidthBorderL);
  }

  double getWitdhR(int start, int end) {
    if (start == widget.colFreezeLeftCount &&
        end == widget.colCount &&
        _cachedColWidths.length == widget.colCount) {
      return _cachedRightTotalWidth;
    }
    return _computeColsWidth(start, end, widget.rowWidthBorderR);
  }

  double getColWidth(int colIndex) {
    if (colIndex >= 0 && colIndex < _cachedColWidths.length) {
      return _cachedColWidths[colIndex];
    }
    if (colWidthMap.containsKey(colIndex)) {
      return colWidthMap[colIndex]!;
    }
    return widget.getColWidth(colIndex, -1, false, -1);
  }

  Widget getHeader(Widget child, int rowIndex, int colIndex) {
    return _TableHeaderCell(
      rowIndex: rowIndex,
      colIndex: colIndex,
      onResizeDelta: (dx) {
        setState(() {
          final current = colWidthMap[colIndex] ?? getColWidth(colIndex);
          colWidthMap[colIndex] = (current + dx).clamp(50.0, 4000.0);
        });
        widget.onColumnWidthsChanged?.call(
          Map<int, double>.unmodifiable(colWidthMap),
        );
      },
      onResetWidth: () => resetColWidth(colIndex),
      onActionTap: widget.onHeaderActionTap == null
          ? null
          : (pos) => widget.onHeaderActionTap!(colIndex, pos),
      child: child,
    );
  }

  Widget _getWeellPointerScrollBehavior(
    ScrollController controller,
    ScrollbarOrientation orientation,
    Widget child,
    bool? alwaysVisible,
    bool? enableScrollIndicator,
  ) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && controller.hasClients) {
          final delta = event.scrollDelta.dy * 0.3;
          controller.jumpTo(
            (controller.offset + delta).clamp(
              0.0,
              controller.position.maxScrollExtent,
            ),
          );
        }
      },
      child: enableScrollIndicator == true
          ? Scrollbar(
              scrollbarOrientation: orientation,
              interactive: true,
              controller: controller,
              thumbVisibility: alwaysVisible,
              trackVisibility: true,
              child: child,
            )
          : child,
    );
  }

  // Ligne gelée en haut
  Widget _topFrozenRow() {
    var witdhRow = getWitdhR(widget.colFreezeLeftCount, widget.colCount);

    return _getWeellPointerScrollBehavior(
      horizontal1,
      ScrollbarOrientation.top,
      SingleChildScrollView(
        controller: horizontal1,
        scrollDirection: Axis.horizontal,

        child: Container(
          margin: EdgeInsets.fromLTRB(0, topMargin, 0, 0),
          //  height: widget.rowHeight * widget.rowCountTop,
          width: witdhRow, // <-- FIX
          child: ListView.builder(
            primary: false,
            shrinkWrap: true,
            itemCount: widget.rowCountTop,
            itemBuilder: (_, row) {
              return getRowHeader(row, 0, witdhRow);
              // return widget.buildRow(
              //   row,
              //   false,
              //   SizedBox(
              //     // height: widget.getRowHeight(row),
              //     width: witdh, // <-- FIX
              //     child: Row(
              //       children: [
              //         for (
              //           int col = widget.colFreezeLeftCount;
              //           col < widget.colCount;
              //           col++
              //         )
              //           SizedBox(
              //             width: getColWidth(col),
              //             height: widget.getRowHeight(row),
              //             child: getHeader(
              //               widget.buildTopCell(row, col),
              //               row,
              //               col,
              //             ),
              //           ),
              //       ],
              //     ),
              //   ),
              //   this,
              // );
            },
          ),
        ),
      ),
      null,
      topScrollbarVisible,
    );
  }

  // Ligne gelée en bas
  Widget _bottomFrozenRow() {
    var witdh = getWitdhR(widget.colFreezeLeftCount, widget.colCount);
    return _getWeellPointerScrollBehavior(
      horizontal2,
      ScrollbarOrientation.bottom,
      SingleChildScrollView(
        controller: horizontal2,
        scrollDirection: Axis.horizontal,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Container(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
          width: witdh,
          child: ListView.builder(
            shrinkWrap: true,
            primary: false,
            itemCount: widget.rowCountBottom,
            itemBuilder: (_, row) => widget.buildRow(
              row + widget.rowCount - widget.rowCountBottom,
              false,
              SizedBox(
                width: witdh,
                child: Row(
                  children: [
                    for (
                      int col = widget.colFreezeLeftCount;
                      col < widget.colCount;
                      col++
                    )
                      SizedBox(
                        width: getColWidth(col),
                        height: widget.getRowHeight(
                          row + widget.rowCount - widget.rowCountBottom,
                        ),
                        child: widget.buildBottomCell(
                          row + widget.rowCount - widget.rowCountBottom,
                          col,
                        ),
                      ),
                  ],
                ),
              ),
              this,
            ),
          ),
        ),
      ),
      true,
      true,
    );
  }

  // Colonne gelée à gauche (en haut)
  Widget _topFrozenColumn() {
    if (widget.colFreezeLeftCount == 0) {
      return const SizedBox.shrink();
    }

    var witdh = getWitdhL(0, widget.colFreezeLeftCount);

    return Container(
      margin: EdgeInsets.fromLTRB(0, topMargin, 0, 0),
      width: witdh,
      child: ListView.builder(
        primary: false,
        shrinkWrap: true,
        itemCount: widget.rowCountTop,
        itemBuilder: (_, row) => widget.buildRow(
          row,
          true,
          SizedBox(
            width: witdh,
            child: Row(
              children: [
                for (int col = 0; col < widget.colFreezeLeftCount; col++)
                  SizedBox(
                    width: getColWidth(col),
                    height: widget.getRowHeight(row),
                    child: getHeader(widget.buildLeftCell(row, col), row, col),
                  ),
              ],
            ),
          ),
          this,
        ),
      ),
    );
  }

  // Colonne gelée à gauche (en bas)
  Widget _bottomFrozenColumn() {
    if (widget.colFreezeLeftCount == 0) {
      return const SizedBox.shrink();
    }
    var witdh = getWitdhL(0, widget.colFreezeLeftCount);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      width: witdh,
      child: ListView.builder(
        primary: false,
        shrinkWrap: true,
        itemCount: widget.rowCountBottom,
        itemBuilder: (_, row) => widget.buildRow(
          row + widget.rowCount - widget.rowCountBottom,
          true,
          SizedBox(
            width: witdh,
            child: Row(
              children: [
                for (int col = 0; col < widget.colFreezeLeftCount; col++)
                  SizedBox(
                    width: getColWidth(col),
                    height: widget.getRowHeight(
                      row + widget.rowCount - widget.rowCountBottom,
                    ),
                    child: widget.buildLeftCell(
                      row + widget.rowCount - widget.rowCountBottom,
                      col,
                    ),
                  ),
              ],
            ),
          ),
          this,
        ),
      ),
    );
  }

  int get _bodyRowCount =>
      math.max(0, widget.rowCount - widget.rowCountTop - widget.rowCountBottom);

  // Colonne gelée à gauche (corps)
  Widget _leftFrozenColumn() {
    if (widget.colFreezeLeftCount == 0) {
      return const SizedBox.shrink();
    }

    var witdh = getWitdhL(0, widget.colFreezeLeftCount);
    var heightRowCache = widget.getRowHeight(widget.rowCountTop);
    return SizedBox(
      width: witdh,
      child: ListView.builder(
        cacheExtent: 250,
        primary: false,
        controller: vertical,
        itemExtent: heightRowCache,
        itemCount: _bodyRowCount,
        itemBuilder: (_, row) {
          final targetRow = row + widget.rowCountTop;
          final heightRow = widget.getRowHeight(targetRow);
          CwRowCache? cacheRow;
          if (withWidgetCache) {
            cacheRow = visibleRowKeyA.putIfAbsent(targetRow, CwRowCache.new);
          }
          final colLimit = widget.colFreezeLeftCount;
          var cells = cacheRow?.rowCells;
          if (cells == null || cells.length != colLimit) {
            cells = List<Widget?>.filled(colLimit, null);
            cacheRow?.rowCells = cells;
          }
          return RepaintBoundary(
            child: SizedBox(
              height: heightRow,
              width: witdh,
              child: widget.buildRow(
                targetRow,
                true,
                Row(
                  children: [
                    for (int col = 0; col < colLimit; col++)
                      SizedBox(
                        width: getColWidth(col),
                        height: heightRow,
                        child:
                            cells[col] ??= widget.buildLeftCell(targetRow, col),
                      ),
                  ],
                ),
                this,
              ),
            ),
          );
        },
      ),
    );
  }

  // Corps du tableau
  Widget _body() {
    var witdhRow = getWitdhR(widget.colFreezeLeftCount, widget.colCount);
    var heightRowCache = widget.getRowHeight(widget.rowCountTop);
    return SingleChildScrollView(
      controller: horizontal3,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: witdhRow,
        child: ValueListenableBuilder<double>(
          valueListenable: _horizontalOffset,
          builder: (context, _, _) => ListView.builder(
            cacheExtent: 250,
            controller: vertical2,
            primary: false,
            itemExtent: heightRowCache,
            itemCount: _bodyRowCount,
            itemBuilder: (_, row) {
              return getRow(row, widget.rowCountTop, witdhRow);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCachedRightRow(
    int row,
    int rowTop,
    double witdhRow, {
    required bool isHeader,
  }) {
    final targetRow = row + rowTop;
    final heightRow = widget.getRowHeight(targetRow);
    final freeze = widget.colFreezeLeftCount.clamp(0, widget.colCount);
    final totalRightCols = widget.colCount - freeze;
    if (totalRightCols <= 0) {
      return SizedBox(width: witdhRow, height: heightRow);
    }

    CwRowCache? cacheRow;
    if (withWidgetCache) {
      cacheRow = visibleRowKeyB.putIfAbsent(targetRow, CwRowCache.new);
    }
    var cells = cacheRow?.rowCells;
    if (cells == null || cells.length != totalRightCols) {
      cells = List<Widget?>.filled(totalRightCols, null);
      cacheRow?.rowCells = cells;
    }

    final (startCol, endCol) = isHeader
        ? (freeze, widget.colCount)
        : _visibleRightColumnRange();
    final offsets = _cachedRightColOffsets;
    final hasOffsets = offsets.length == totalRightCols + 1;
    final leftSpacer = hasOffsets ? offsets[startCol - freeze] : 0.0;
    final rightSpacer = hasOffsets
        ? math.max(0.0, offsets[totalRightCols] - offsets[endCol - freeze])
        : 0.0;

    final aRow = Row(
      children: [
        if (!isHeader && leftSpacer > 0)
          SizedBox(width: leftSpacer, height: heightRow),
        for (int col = startCol; col < endCol; col++)
          SizedBox(
            width: getColWidth(col),
            height: heightRow,
            child: cells[col - freeze] ??= isHeader
                ? getHeader(
                    widget.buildTopCell(targetRow, col),
                    targetRow,
                    col,
                  )
                : widget.buildBodyCell(targetRow, col),
          ),
        if (!isHeader && rightSpacer > 0)
          SizedBox(width: rightSpacer, height: heightRow),
      ],
    );
    return RepaintBoundary(
      child: widget.buildRow(
        targetRow,
        false,
        SizedBox(width: witdhRow, height: heightRow, child: aRow),
        this,
      ),
    );
  }

  Widget getRow(int row, int rowTop, double witdhRow) =>
      _buildCachedRightRow(row, rowTop, witdhRow, isHeader: false);

  Widget getRowHeader(int row, int rowTop, double witdhRow) =>
      _buildCachedRightRow(row, rowTop, witdhRow, isHeader: true);

  void clearWidgetCache() {
    visibleRowKeyA.clear();
    visibleRowKeyB.clear();
  }
}

class _TableHeaderCell extends StatefulWidget {
  const _TableHeaderCell({
    required this.rowIndex,
    required this.colIndex,
    required this.onResizeDelta,
    required this.onResetWidth,
    this.onActionTap,
    required this.child,
  });

  final int rowIndex;
  final int colIndex;
  final ValueChanged<double> onResizeDelta;
  final VoidCallback onResetWidth;
  final ValueChanged<Offset>? onActionTap;
  final Widget child;

  @override
  State<_TableHeaderCell> createState() => _TableHeaderCellState();
}

class _TableHeaderCellState extends State<_TableHeaderCell> {
  final ValueNotifier<bool> _isHover = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isHover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.rowIndex == 0)
          Positioned(
            right: 10,
            top: 0,
            bottom: 0,
            left: 10,
            child: MouseRegion(
              opaque: false,
              onExit: (_) => _isHover.value = false,
              onHover: (_) => _isHover.value = true,
              child: ValueListenableBuilder<bool>(
                valueListenable: _isHover,
                builder: (context, hovered, _) => Visibility(
                  visible: hovered,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Builder(
                        builder: (btnContext) => Material(
                          elevation: 3,
                          color: Colors.black12,
                          shape: const CircleBorder(),
                          child: IconButton(
                            key: ValueKey(
                              'cw-table-header-action-${widget.colIndex}',
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              if (widget.onActionTap == null) return;
                              final box =
                                  btnContext.findRenderObject() as RenderBox?;
                              final pos = box != null && box.hasSize
                                  ? box.localToGlobal(
                                      Offset(0, box.size.height),
                                    )
                                  : Offset.zero;
                              widget.onActionTap!(pos);
                            },
                            icon: const Icon(
                              Icons.expand_more,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: GestureDetector(
            key: ValueKey('cw-table-header-resize-${widget.colIndex}'),
            behavior: HitTestBehavior.translucent,
            onDoubleTap: widget.onResetWidth,
            onHorizontalDragUpdate: (details) =>
                widget.onResizeDelta(details.delta.dx),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              onHover: (_) => _isHover.value = true,
              onExit: (_) => _isHover.value = false,
              child: ValueListenableBuilder<bool>(
                valueListenable: _isHover,
                builder: (context, hovered, _) => SizedBox(
                  width: 5,
                  child: hovered ? const VerticalDivider() : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
