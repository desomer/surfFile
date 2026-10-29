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
  });

  @override
  State<FrozenTableView> createState() => FrozenTableViewState();
}

class CwRowCache {
  final CwTableRowState cwTableRowState;
  CwRowCache(this.cwTableRowState);
  List<Widget>? rowCells;
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
      if (visibleRowKeyA[info.row]?.cwTableRowState != cwTableRowState) {
        visibleRowKeyA[info.row] = CwRowCache(cwTableRowState);
      }
    } else {
      if (visibleRowKeyB[info.row]?.cwTableRowState != cwTableRowState) {
        visibleRowKeyB[info.row] = CwRowCache(cwTableRowState);
      }
    }
  }

  void setSelectedRowIndex(int row, {bool scrollIntoView = true}) {
    var rowFreezeTop = widget.rowCountTop;

    final rowA = visibleRowKeyA[row + rowFreezeTop]?.cwTableRowState;
    if (rowA != null && rowA.mounted) {
      // ignore: invalid_use_of_protected_member
      rowA.setState(() {});
    }
    final rowB = visibleRowKeyB[row + rowFreezeTop]?.cwTableRowState;
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

  @override
  void initState() {
    super.initState();
    vertical.addListener(() {
      _syncScroll(vertical, vertical2);
    });
    vertical2.addListener(() {
      _syncScroll(vertical2, vertical);
    });
    horizontal1.addListener(() {
      _syncScroll(horizontal1, horizontal2);
      _syncScroll(horizontal1, horizontal3);
    });
    horizontal2.addListener(() {
      _syncScroll(horizontal2, horizontal1);
      _syncScroll(horizontal2, horizontal3);
    });
    horizontal3.addListener(() {
      _syncScroll(horizontal3, horizontal1);
      _syncScroll(horizontal3, horizontal2);
    });
  }

  @override
  void dispose() {
    vertical.dispose();
    vertical2.dispose();
    horizontal1.dispose();
    horizontal2.dispose();
    horizontal3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

  double getWitdhL(int start, int end) =>
      _computeColsWidth(start, end, widget.rowWidthBorderL);

  double getWitdhR(int start, int end) =>
      _computeColsWidth(start, end, widget.rowWidthBorderR);

  double getColWidth(int colIndex) {
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
      },
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
        primary: false,
        controller: vertical,
        itemExtent: heightRowCache,
        itemCount: _bodyRowCount,
        itemBuilder: (_, row) => SizedBox(
          height: widget.getRowHeight(row + widget.rowCountTop),
          width: witdh,
          child: widget.buildRow(
            row + widget.rowCountTop,
            true,
            Row(
              children: [
                for (int col = 0; col < widget.colFreezeLeftCount; col++)
                  SizedBox(
                    width: getColWidth(col),
                    height: widget.getRowHeight(row + widget.rowCountTop),
                    child: widget.buildLeftCell(row + widget.rowCountTop, col),
                  ),
              ],
            ),
            this,
          ),
        ),
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
        child: ListView.builder(
          scrollCacheExtent: const ScrollCacheExtent.pixels(10),
          controller: vertical2,
          primary: false,
          itemExtent: heightRowCache,
          itemCount: _bodyRowCount,
          itemBuilder: (_, row) {
            return getRow(row, widget.rowCountTop, witdhRow);
          },
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
    final cacheRow = getCacheRowByIdx(targetRow, false);
    List<Widget> aRowCells;
    if (cacheRow?.rowCells != null) {
      aRowCells = cacheRow!.rowCells!;
    } else {
      aRowCells = [];
      for (int col = widget.colFreezeLeftCount; col < widget.colCount; col++) {
        final cell = isHeader
            ? getHeader(widget.buildTopCell(targetRow, col), targetRow, col)
            : widget.buildBodyCell(targetRow, col);
        aRowCells.add(cell);
      }
      if (cacheRow != null) {
        cacheRow.rowCells = aRowCells;
      }
    }

    final aRow = Row(
      children: [
        for (int col = widget.colFreezeLeftCount; col < widget.colCount; col++)
          SizedBox(
            width: getColWidth(col),
            height: heightRow,
            child: aRowCells[col - widget.colFreezeLeftCount],
          ),
      ],
    );
    return widget.buildRow(
      targetRow,
      false,
      SizedBox(width: witdhRow, child: aRow),
      this,
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
    required this.child,
  });

  final int rowIndex;
  final int colIndex;
  final ValueChanged<double> onResizeDelta;
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
                      Material(
                        elevation: 3,
                        color: Colors.black12,
                        shape: const CircleBorder(),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {},
                          icon: const Icon(
                            Icons.expand_more,
                            size: 18,
                            color: Colors.white,
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
            behavior: HitTestBehavior.translucent,
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
