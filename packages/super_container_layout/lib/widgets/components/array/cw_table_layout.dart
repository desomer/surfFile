// import 'package:flutter/gestures.dart';
// import 'package:material_ui/material_ui.dart';
// import 'package:flutter/rendering.dart';

// class FrozenTableView extends StatefulWidget {
//   final int rowCount;
//   final int colCount;
//   final int colFreezeLeftCount;

//   final int rowCountTop;
//   final int rowCountBottom;

//   final double rowWidthBorderR;
//   final double rowWidthBorderL;

//   final Widget Function(int row, int col) buildTopCell;
//   final Widget Function(int row, int col) buildBottomCell;
//   final Widget Function(int row, int col) buildLeftCell;
//   final Widget Function(int row, int col) buildBodyCell;
//   final Widget Function(
//     int row,
//     bool isStartCols,
//     Widget child,
//     FrozenTableViewState tableState,
//   )
//   buildRow;
//   final double Function(int col, double usedWidth, bool isCalc, int nbFillCol)
//   getColWidth;
//   final double? Function(int row) getRowHeight;

//   const FrozenTableView({
//     super.key,
//     required this.rowCount,
//     required this.colCount,
//     required this.buildTopCell,
//     required this.buildBottomCell,
//     required this.buildLeftCell,
//     required this.buildBodyCell,
//     required this.rowCountTop,
//     required this.rowCountBottom,
//     required this.colFreezeLeftCount,
//     required this.getColWidth,
//     required this.getRowHeight,
//     required this.buildRow,
//     required this.rowWidthBorderR,
//     required this.rowWidthBorderL,
//   });

//   @override
//   State<FrozenTableView> createState() => FrozenTableViewState();
// }

// class CwRowCache {
//   CwRowCache(this.cwTableRowState);
//   List<Widget>? rowCells;
// }

// class FrozenTableViewState extends State<FrozenTableView> {
//   final ScrollController vertical = ScrollController();
//   final ScrollController vertical2 = ScrollController();
//   final ScrollController horizontal1 = ScrollController();
//   final ScrollController horizontal2 = ScrollController();
//   final ScrollController horizontal3 = ScrollController();

//   Map<int, double> colWidthMap = {};

//   bool topScrollbarVisible = false;
//   double topMargin = 0;

//   Map<int, CwRowCache> visibleRowKeyA = {};
//   Map<int, CwRowCache> visibleRowKeyB = {};

//   CwTableRow? getCacheTableRowState(CwRowInfo info, Widget child) {
//     CwTableRowState? cache = getCacheRow(info)?.cwTableRowState;
//     if (cache != null) {
//       cache.setNewChild(child);
//       cache.setState(() {});
//     }
//     return cache?.widget;
//   }

//   CwRowCache? getCacheRow(CwRowInfo info) {
//     if (!withWidgetCache) {
//       return null;
//     }
//     if (info.isStartCols) {
//       return visibleRowKeyA[info.row];
//     } else {
//       return visibleRowKeyB[info.row];
//     }
//   }

//   CwRowCache? getCacheRowByIdx(int row, bool isStartCols) {
//     if (!withWidgetCache) {
//       return null;
//     }
//     if (isStartCols) {
//       return visibleRowKeyA[row];
//     } else {
//       return visibleRowKeyB[row];
//     }
//   }

//   void disposeRowState(CwRowInfo info, CwTableRowState cwTableRowState) {
//     if (info.isStartCols) {
//       if (visibleRowKeyA[info.row]?.cwTableRowState == cwTableRowState) {
//         visibleRowKeyA.remove(info.row);
//       }
//     } else {
//       if (visibleRowKeyB[info.row]?.cwTableRowState == cwTableRowState) {
//         visibleRowKeyB.remove(info.row);
//       }
//     }
//   }

//   void initRowState(CwRowInfo info, CwTableRowState cwTableRowState) {
//     if (info.isStartCols) {
//       if (visibleRowKeyA[info.row]?.cwTableRowState != cwTableRowState) {
//         visibleRowKeyA[info.row] = CwRowCache(cwTableRowState);
//       }
//     } else {
//       if (visibleRowKeyB[info.row]?.cwTableRowState != cwTableRowState) {
//         visibleRowKeyB[info.row] = CwRowCache(cwTableRowState);
//       }
//     }
//   }

//   void setSelectedRowIndex(int row, {bool scrollIntoView = true}) {
//     // int max = 0;
//     // int min = widget.rowCount + 1;
//     var rowFreezeTop = widget.rowCountTop;

//     visibleRowKeyA[row + rowFreezeTop]?.cwTableRowState.setState(() {});
//     visibleRowKeyB[row + rowFreezeTop]?.cwTableRowState.setState(() {});

//     if (!scrollIntoView) {
//       return;
//     }

//     final pos = vertical2.position;
//     final viewMin = vertical2.position.pixels;
//     final viewMax = vertical2.position.pixels + pos.viewportDimension;

//     double topPos = 0;
//     for (int r = rowFreezeTop; r < row + rowFreezeTop; r++) {
//       topPos += widget.getRowHeight(r) ?? 30;
//     }
//     if (topPos < viewMin) {
//       // scroll up
//       //print("setSelectedRowIndex row=$row min=$min max=$max offset=$topPos");
//       vertical2.animateTo(
//         topPos,
//         duration: Duration(milliseconds: 1000),
//         curve: Curves.easeInOut,
//       );
//     }
//     var bottomPos = topPos + (widget.getRowHeight(row + rowFreezeTop) ?? 30);
//     if (bottomPos > viewMax) {
//       // scroll down
//       //print("setSelectedRowIndex row=$row min=$min max=$max offset=$topPos");
//       double viewHeight = vertical2.position.viewportDimension;
//       vertical2.animateTo(
//         bottomPos - viewHeight,
//         duration: Duration(milliseconds: 1000),
//         curve: Curves.easeInOut,
//       );
//     }

//     // if (row < min) {
//     //   // scroll up
//     //   double offset = 0;
//     //   for (int r = 0; r < row; r++) {
//     //     offset += widget.getRowHeight(r) ?? 30;
//     //   }
//     //   //vertical.jumpTo(offset);
//     //   vertical2.animateTo(offset, duration: Duration(milliseconds: 300), curve: Curves.easeInOut);
//     // } else if (row > max) {
//     //   // scroll down
//     //   double offset = 0;
//     //   for (int r = 0; r <= row; r++) {
//     //     offset += widget.getRowHeight(r) ?? 30;
//     //   }
//     //   double viewHeight = vertical2.position.viewportDimension;
//     //   //vertical.jumpTo(offset - viewHeight);
//     //   vertical2.jumpTo(offset - viewHeight);
//     // }
//   }

//   @override
//   void initState() {
//     super.initState();
//     vertical.addListener(() {
//       if (vertical2.offset != vertical.offset) {
//         vertical2.jumpTo(vertical.offset);
//       }
//     });
//     vertical2.addListener(() {
//       if (vertical.hasClients && vertical.offset != vertical2.offset) {
//         vertical.jumpTo(vertical2.offset);
//       }
//     });
//     horizontal1.addListener(() {
//       if (horizontal2.offset != horizontal1.offset) {
//         horizontal2.jumpTo(horizontal1.offset);
//       }
//       if (horizontal3.offset != horizontal1.offset) {
//         horizontal3.jumpTo(horizontal1.offset);
//       }
//     });
//     horizontal2.addListener(() {
//       if (horizontal1.offset != horizontal2.offset) {
//         horizontal1.jumpTo(horizontal2.offset);
//       }
//     });
//     horizontal3.addListener(() {
//       if (horizontal1.offset != horizontal3.offset) {
//         horizontal1.jumpTo(horizontal3.offset);
//       }
//     });
//   }

//   @override
//   void dispose() {
//     vertical.dispose();
//     vertical2.dispose();
//     horizontal1.dispose();
//     horizontal2.dispose();
//     horizontal3.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.stretch,
//       children: [
//         // ------------------ TOP FROZEN ROW ------------------
//         Row(
//           mainAxisSize: MainAxisSize.max,
//           children: [
//             _topFrozenColumn(),
//             Expanded(child: _topFrozenRow()),
//           ],
//         ),

//         // ------------------ BODY + LEFT FROZEN COLUMN ------------------
//         Expanded(
//           child: Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               _leftFrozenColumn(),
//               Expanded(child: _body()),
//             ],
//           ),
//         ),

//         // ------------------ BOTTOM FROZEN ROW ------------------
//         Row(
//           children: [
//             _bottomFrozenColumn(),
//             Expanded(child: _bottomFrozenRow()),
//           ],
//         ),
//       ],
//     );
//   }

//   double getWitdhL(int start, int end) {
//     double totalFix = 0;
//     int nbFillCol = 0;
//     for (int i = start; i < end; i++) {
//       if (colWidthMap.containsKey(i)) {
//         totalFix += colWidthMap[i]!;
//         nbFillCol++;
//         continue;
//       }
//       var colWidth = widget.getColWidth(i, totalFix, true, -1);
//       if (colWidth > 0) {
//         totalFix += colWidth;
//         nbFillCol++;
//       }
//     }
//     double total = 0;
//     for (int i = start; i < end; i++) {
//       if (colWidthMap.containsKey(i)) {
//         total += colWidthMap[i]!;
//         continue;
//       }
//       total += widget.getColWidth(i, totalFix, false, nbFillCol);
//     }
//     return total + widget.rowWidthBorderL;
//   }

//   double getWitdhR(int start, int end) {
//     double totalfix = 0;
//     int nbFillCol = 0;
//     for (int i = start; i < end; i++) {
//       if (colWidthMap.containsKey(i)) {
//         totalfix += colWidthMap[i]!;
//         nbFillCol++;
//         continue;
//       }
//       var colWidth = widget.getColWidth(i, totalfix, true, -1);
//       if (colWidth > 0) {
//         totalfix += colWidth;
//         nbFillCol++;
//       }
//     }
//     double total = 0;
//     for (int i = start; i < end; i++) {
//       if (colWidthMap.containsKey(i)) {
//         total += colWidthMap[i]!;
//         continue;
//       }
//       total += widget.getColWidth(i, totalfix, false, nbFillCol);
//     }
//     return total + widget.rowWidthBorderR;
//   }

//   double getColWidth(int colIndex) {
//     double r = 0;
//     if (colWidthMap.containsKey(colIndex)) {
//       r = colWidthMap[colIndex]!;
//       //print(' getColWidth $colIndex = $r');
//       return r;
//     }
//     r = widget.getColWidth(colIndex, -1, false, -1);
//     //print(' getColWidth $colIndex = $r');
//     return r;
//   }

//   Widget getHeader(Widget child, int rowIndex, int colIndex) {
//     ValueNotifier<bool> isHover = ValueNotifier(false);
//     return Stack(
//       fit: StackFit.expand,
//       children: [
//         child,
//         if (rowIndex == 0)
//           Positioned(
//             right: 10,
//             top: 0,
//             bottom: 0,
//             left: 10,
//             child: getAction(isHover),
//           ),
//         Positioned(
//           right: 0,
//           top: 0,
//           bottom: 0,
//           child: getResizeHandle(colIndex, isHover: isHover),
//         ),
//       ],
//     );
//   }

//   Widget getAction(ValueNotifier<bool> isHover) {
//     return MouseRegion(
//       opaque: false,
//       onEnter: (_) {},
//       onExit: (_) {
//         isHover.value = false;
//       },
//       onHover: (_) {
//         isHover.value = true;
//       },
//       child: ValueListenableBuilder(
//         valueListenable: isHover,
//         builder: (context, value, child) => Visibility(
//           visible: isHover.value,
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             mainAxisAlignment: MainAxisAlignment.center,
//             crossAxisAlignment: CrossAxisAlignment.end,
//             children: [
//               Material(
//                 elevation: 3,
//                 color: Colors.black12,
//                 shape: CircleBorder(),
//                 child: IconButton(
//                   padding: EdgeInsets.zero,
//                   constraints: BoxConstraints(),
//                   onPressed: () {},
//                   icon: Icon(Icons.expand_more, size: 18, color: Colors.white),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget getResizeHandle(int colIndex, {required ValueNotifier<bool> isHover}) {
//     return GestureDetector(
//       behavior: HitTestBehavior.translucent,
//       onHorizontalDragUpdate: (details) {
//         // Handle resize logic here
//         setState(() {
//           // Update column width based on drag details
//           // This is a simplified example; you may want to add constraints
//           // and more complex logic depending on your requirements
//           // For this example, we'll just increase the width of the first column
//           if (colWidthMap.containsKey(colIndex)) {
//             colWidthMap[colIndex] = (colWidthMap[colIndex]! + details.delta.dx)
//                 .clamp(50.0, 4000.0);
//           } else {
//             colWidthMap[colIndex] = (getColWidth(colIndex) + details.delta.dx)
//                 .clamp(50.0, 4000.0);
//           }
//         });
//       },
//       child: MouseRegion(
//         cursor: SystemMouseCursors.resizeColumn,
//         onHover: (_) => isHover.value = true,
//         onExit: (_) => isHover.value = false,
//         child: ValueListenableBuilder(
//           valueListenable: isHover,
//           builder: (context, value, child) {
//             return SizedBox(width: 5, child: value ? VerticalDivider() : null);
//           },
//         ),
//       ),
//     );
//   }

//   Widget _getWeellPointerScrollBehavior(
//     ScrollController controller,
//     ScrollbarOrientation orientation,
//     Widget child,
//     bool? alwaysVisible,
//     bool? enableScrollIndicator,
//   ) {
//     return Listener(
//       onPointerSignal: (event) {
//         if (event is PointerScrollEvent) {
//           // event.scrollDelta.dy = mouvement de la molette
//           final delta = event.scrollDelta.dy * 0.3;

//           controller.jumpTo(
//             (controller.offset + delta).clamp(
//               0.0,
//               controller.position.maxScrollExtent,
//             ),
//           );
//         }
//       },
//       child: enableScrollIndicator == true
//           ? Scrollbar(
//               scrollbarOrientation: orientation,
//               interactive: true,
//               controller: controller,
//               thumbVisibility: alwaysVisible, // toujours visible
//               trackVisibility: true, // optionnel
//               child: child,
//             )
//           : child,
//     );
//   }

//   // Ligne gelée en haut
//   Widget _topFrozenRow() {
//     var witdhRow = getWitdhR(widget.colFreezeLeftCount, widget.colCount);

//     return _getWeellPointerScrollBehavior(
//       horizontal1,
//       ScrollbarOrientation.top,
//       SingleChildScrollView(
//         controller: horizontal1,
//         scrollDirection: Axis.horizontal,

//         child: Container(
//           margin: EdgeInsets.fromLTRB(0, topMargin, 0, 0),
//           //  height: widget.rowHeight * widget.rowCountTop,
//           width: witdhRow, // <-- FIX
//           child: ListView.builder(
//             primary: false,
//             shrinkWrap: true,
//             itemCount: widget.rowCountTop,
//             itemBuilder: (_, row) {
//               return getRowHeader(row, 0, witdhRow);
//               // return widget.buildRow(
//               //   row,
//               //   false,
//               //   SizedBox(
//               //     // height: widget.getRowHeight(row),
//               //     width: witdh, // <-- FIX
//               //     child: Row(
//               //       children: [
//               //         for (
//               //           int col = widget.colFreezeLeftCount;
//               //           col < widget.colCount;
//               //           col++
//               //         )
//               //           SizedBox(
//               //             width: getColWidth(col),
//               //             height: widget.getRowHeight(row),
//               //             child: getHeader(
//               //               widget.buildTopCell(row, col),
//               //               row,
//               //               col,
//               //             ),
//               //           ),
//               //       ],
//               //     ),
//               //   ),
//               //   this,
//               // );
//             },
//           ),
//         ),
//       ),
//       null,
//       topScrollbarVisible,
//     );
//   }

//   // Ligne gelée en bas
//   Widget _bottomFrozenRow() {
//     var witdh = getWitdhR(widget.colFreezeLeftCount, widget.colCount);
//     return _getWeellPointerScrollBehavior(
//       horizontal1,
//       ScrollbarOrientation.bottom,
//       SingleChildScrollView(
//         controller: horizontal2,
//         scrollDirection: Axis.horizontal,
//         physics: AlwaysScrollableScrollPhysics(),
//         child: Container(
//           margin: EdgeInsets.fromLTRB(0, 0, 0, 10),
//           // height: widget.rowHeight * widget.rowCountBottom,
//           width: witdh, // <-- FIX
//           child: ListView.builder(
//             shrinkWrap: true,
//             primary: false,
//             itemCount: widget.rowCountBottom,
//             itemBuilder: (_, row) => widget.buildRow(
//               row + widget.rowCount - widget.rowCountBottom,
//               true,
//               SizedBox(
//                 // height: widget.getRowHeight(
//                 //   row + widget.rowCount - widget.rowCountBottom,
//                 // ),
//                 width: witdh, // <-- FIX
//                 child: Row(
//                   children: [
//                     for (
//                       int col = widget.colFreezeLeftCount;
//                       col < widget.colCount;
//                       col++
//                     )
//                       SizedBox(
//                         width: getColWidth(col),
//                         height: widget.getRowHeight(
//                           row + widget.rowCount - widget.rowCountBottom,
//                         ),
//                         child: widget.buildBottomCell(
//                           row + widget.rowCount - widget.rowCountBottom,
//                           col,
//                         ),
//                       ),
//                   ],
//                 ),
//               ),
//               this,
//             ),
//           ),
//         ),
//       ),
//       true,
//       true,
//     );
//   }

//   // Colonne gelée à gauche
//   Widget _topFrozenColumn() {
//     if (widget.colFreezeLeftCount == 0) {
//       return SizedBox.shrink();
//     }

//     var witdh = getWitdhL(0, widget.colFreezeLeftCount);

//     return Container(
//       margin: EdgeInsets.fromLTRB(0, topMargin, 0, 0),
//       //height: widget.rowCountTop * widget.rowHeight,
//       width: witdh, // <-- FIX
//       child: ListView.builder(
//         primary: false,
//         shrinkWrap: true,
//         //controller: vertical,
//         itemCount: widget.rowCountTop,
//         itemBuilder: (_, row) => widget.buildRow(
//           row,
//           true,
//           SizedBox(
//             // height: widget.getRowHeight(row),
//             width: witdh,
//             child: Row(
//               children: [
//                 for (int col = 0; col < widget.colFreezeLeftCount; col++)
//                   SizedBox(
//                     width: getColWidth(col),
//                     height: widget.getRowHeight(row),
//                     child: getHeader(widget.buildLeftCell(row, col), row, col),
//                   ),
//               ],
//             ),
//           ),
//           this,
//         ),
//       ),
//     );
//   }

//   // Colonne gelée à gauche
//   Widget _bottomFrozenColumn() {
//     if (widget.colFreezeLeftCount == 0) {
//       return SizedBox.shrink();
//     }
//     var witdh = getWitdhL(0, widget.colFreezeLeftCount);
//     return Container(
//       margin: EdgeInsets.fromLTRB(0, 0, 0, 10),
//       //height: widget.rowCountBottom * widget.rowHeight,
//       width: witdh, // <-- FIX
//       child: ListView.builder(
//         primary: false,
//         shrinkWrap: true,
//         //controller: vertical,
//         itemCount: widget.rowCountBottom,
//         itemBuilder: (_, row) => widget.buildRow(
//           row + widget.rowCount - widget.rowCountBottom,
//           false,
//           SizedBox(
//             // height: widget.getRowHeight(
//             //   row + widget.rowCount - widget.rowCountBottom,
//             // ),
//             width: witdh,
//             child: Row(
//               children: [
//                 for (int col = 0; col < widget.colFreezeLeftCount; col++)
//                   SizedBox(
//                     width: getColWidth(col),
//                     height: widget.getRowHeight(
//                       row + widget.rowCount - widget.rowCountBottom,
//                     ),
//                     child: widget.buildLeftCell(
//                       row + widget.rowCount - widget.rowCountBottom,
//                       col,
//                     ),
//                   ),
//               ],
//             ),
//           ),
//           this,
//         ),
//       ),
//     );
//   }

//   // Colonne gelée à gauche
//   Widget _leftFrozenColumn() {
//     if (widget.colFreezeLeftCount == 0) {
//       return SizedBox.shrink();
//     }

//     var witdh = getWitdhL(0, widget.colFreezeLeftCount);
//     return SizedBox(
//       //height: widget.rowCount * widget.rowHeight,
//       width: witdh, // <-- FIX
//       child: ListView.builder(
//         shrinkWrap: true,
//         primary: false,
//         controller: vertical,
//         itemCount: widget.rowCount - widget.rowCountTop - widget.rowCountBottom,
//         itemBuilder: (_, row) => SizedBox(
//           //height: widget.getRowHeight(row + widget.rowCountTop),
//           width: witdh,
//           child: widget.buildRow(
//             row + widget.rowCountTop,
//             true,
//             Row(
//               children: [
//                 for (int col = 0; col < widget.colFreezeLeftCount; col++)
//                   SizedBox(
//                     width: getColWidth(col),
//                     height: widget.getRowHeight(row + widget.rowCountTop),
//                     child: widget.buildLeftCell(row + widget.rowCountTop, col),
//                   ),
//               ],
//             ),
//             this,
//           ),
//         ),
//       ),
//     );
//   }

//   // Corps du tableau
//   Widget _body() {
//     var witdhRow = getWitdhR(widget.colFreezeLeftCount, widget.colCount);
//     var heightRowCache = widget.getRowHeight(0 + widget.rowCountTop);
//     return //SingleChildScrollView(
//     //controller: vertical2,
//     //scrollDirection: Axis.vertical,
//     //child:
//     SingleChildScrollView(
//       controller: horizontal3,
//       scrollDirection: Axis.horizontal,
//       child: SizedBox(
//         width: witdhRow,
//         //height: 200,
//         child: ListView.builder(
//           scrollCacheExtent: ScrollCacheExtent.pixels(10),
//           controller: vertical2,
//           primary: false,
//           shrinkWrap: true,
//           itemExtent: heightRowCache,
//           itemCount:
//               widget.rowCount - widget.rowCountTop - widget.rowCountBottom,
//           itemBuilder: (_, row) {
//             return getRow(row, widget.rowCountTop, witdhRow);
//           },
//         ),
//       ),
//       // ),
//     );
//   }

//   Widget getRow(int row, int rowTop, double witdhRow) {
//     var heightRow = widget.getRowHeight(row + rowTop);
//     var cacheRow = getCacheRowByIdx(row + rowTop, false);
//     // if (cacheRow != null) {
//     //   print(
//     //     'Using cached row for row index ${row + rowTop} ${cacheRow.cwTableRowState}',
//     //   );
//     // }
//     List<Widget> aRowCells;
//     if (cacheRow?.rowCells != null) {
//       aRowCells = cacheRow!.rowCells!;
//     } else {
//       aRowCells = [];
//       for (int col = widget.colFreezeLeftCount; col < widget.colCount; col++) {
//         aRowCells.add(widget.buildBodyCell(row + rowTop, col));
//       }
//       if (cacheRow != null) {
//         cacheRow.rowCells = aRowCells;
//       }
//     }

//     var aRow = Row(
//       children: [
//         for (int col = widget.colFreezeLeftCount; col < widget.colCount; col++)
//           SizedBox(
//             width: getColWidth(col),
//             height: heightRow,
//             child: aRowCells[col - widget.colFreezeLeftCount],
//           ),
//       ],
//     );
//     return widget.buildRow(
//       row + rowTop,
//       false,
//       SizedBox(width: witdhRow, child: aRow),
//       this,
//     );
//   }

//   Widget getRowHeader(int row, int rowTop, double witdhRow) {
//     var heightRow = widget.getRowHeight(row + rowTop);
//     var cacheRow = getCacheRowByIdx(row + rowTop, false);
//     // if (cacheRow != null) {
//     //   print(
//     //     'Using cached row for row index ${row + rowTop} ${cacheRow.cwTableRowState}',
//     //   );
//     // }
//     List<Widget> aRowCells;
//     if (cacheRow?.rowCells != null) {
//       aRowCells = cacheRow!.rowCells!;
//     } else {
//       aRowCells = [];
//       for (int col = widget.colFreezeLeftCount; col < widget.colCount; col++) {
//         aRowCells.add(
//           getHeader(widget.buildTopCell(row + rowTop, col), row + rowTop, col),
//         );
//       }
//       if (cacheRow != null) {
//         cacheRow.rowCells = aRowCells;
//       }
//     }

//     var aRow = Row(
//       children: [
//         for (int col = widget.colFreezeLeftCount; col < widget.colCount; col++)
//           SizedBox(
//             width: getColWidth(col),
//             height: heightRow,
//             child: aRowCells[col - widget.colFreezeLeftCount],
//           ),
//       ],
//     );
//     return widget.buildRow(
//       row + rowTop,
//       false,
//       SizedBox(width: witdhRow, child: aRow),
//       this,
//     );
//   }

//   void clearWidgetCache() {
//     visibleRowKeyA.clear();
//     visibleRowKeyB.clear();
//   }
// }
