import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/components/internal_widget/array/cw_table_layout.dart';

class CwRowInfo {
  final int row;
  final bool isStartCols;
  final int nbColFreeze;
  final Map<String, dynamic>? propsRow;
  final FrozenTableViewState tableState;
  final dynamic data;

  CwRowInfo({
    required this.row,
    required this.isStartCols,
    required this.nbColFreeze,
    required this.propsRow,
    required this.tableState,
    required this.data,
  });
}

class CwTableRow extends StatefulWidget {
  const CwTableRow({super.key, required this.info, required this.child});
  final CwRowInfo info;
  final Widget child;

  @override
  State<CwTableRow> createState() => CwTableRowState();
}

class CwTableRowState extends State<CwTableRow> {
  Widget? newChild;
  Widget? cache;

  void setNewChild(Widget newChild) {
    this.newChild = newChild;
  }

  @override
  void dispose() {
    widget.info.tableState.disposeRowState(widget.info, this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.info.tableState.initRowState(widget.info, this);
  }

  @override
  void didUpdateWidget(covariant CwTableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.row != widget.info.row ||
        oldWidget.info.isStartCols != widget.info.isStartCols ||
        oldWidget.info.tableState != widget.info.tableState) {
      oldWidget.info.tableState.disposeRowState(oldWidget.info, this);
      widget.info.tableState.initRowState(widget.info, this);
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.info.tableState.initRowState(widget.info, this);
    cache = getRowStyleWidget(
      widget.info.row,
      widget.info.isStartCols,
      widget.info.nbColFreeze,
      widget.info.propsRow,
      newChild ?? widget.child,
      context,
    );
    return cache!;
  }

  // bool _isHovered = false;

  Widget getRowStyleWidget(
    int row,
    bool isStartCols,
    int nbColFreeze,
    Map<String, dynamic>? dataRow,
    Widget child,
    BuildContext context,
  ) {
    return child;

    // // if (row == 0) return child; // pas de style pour la ligne header

    // var bRadius = styleBox.getStyleDouble('bRadius', 0);
    // var bColor = styleBox.getColor('bColor') ?? Colors.transparent;
    // var bSize = styleBox.getStyleDouble('bSize', 1);

    // if (bSize == 0) {
    //   bColor = Colors.transparent;
    //   bRadius = 0;
    // }

    // Color? selColor = styleBox.getColor('selColor');
    // Color? hoverColor = styleBox.getColor('hoverColor');

    // if (widget.info.ctx.aFactory.isModeDesigner()) {
    //   selColor = null;
    // }

    // var ptop = styleBox.getStyleDouble('ptop', 0);
    // var pbottom = styleBox.getStyleDouble('pbottom', 0);
    // var pleft = styleBox.getStyleDouble('pleft', 0);
    // var pright = styleBox.getStyleDouble('pright', 0);

    // var mtop = styleBox.getStyleDouble('mtop', 0);
    // var mbottom = styleBox.getStyleDouble('mbottom', 0);
    // var mleft = styleBox.getStyleDouble('mleft', 0);
    // var mright = styleBox.getStyleDouble('mright', 0);

    // var elevation = styleBox.getElevation();
    // bool isSelected = widget.info.arrayContainer?.currentIndex == row - 1;

    // var boxDecoration = BoxDecoration(
    //   borderRadius: BorderRadius.only(
    //     topLeft:
    //         isStartCols || nbColFreeze == 0
    //             ? Radius.circular(bRadius)
    //             : Radius.zero,
    //     topRight:
    //         isStartCols && nbColFreeze != 0
    //             ? Radius.zero
    //             : Radius.circular(bRadius),
    //     bottomLeft:
    //         isStartCols || nbColFreeze == 0
    //             ? Radius.circular(bRadius)
    //             : Radius.zero,
    //     bottomRight:
    //         isStartCols && nbColFreeze != 0
    //             ? Radius.zero
    //             : Radius.circular(bRadius),
    //   ),
    //   color:
    //       (elevation == null && isSelected ? selColor : null) ??
    //       (elevation == null && _isHovered ? hoverColor : null) ??
    //       styleBox.config.decoration?.color,
    //   border: Border(
    //     bottom: BorderSide(color: bColor, width: bSize),
    //     top: BorderSide(color: bColor, width: bSize),
    //     left:
    //         isStartCols || nbColFreeze == 0
    //             ? BorderSide(color: bColor, width: bSize)
    //             : BorderSide.none,
    //     right:
    //         isStartCols && nbColFreeze != 0
    //             ? BorderSide.none
    //             : BorderSide(color: bColor, width: bSize),
    //   ),
    // );

    // if (isSelected) {
    //   widget.info.arrayContainer?.initSelected(
    //     row - 1,
    //     widget.info.ctx.aWidgetPath,
    //     this,
    //   );
    // }

    // if (elevation != null) {
    //   return getGestureDetector(
    //     Container(
    //       key: ObjectKey(widget.info.data),
    //       margin: EdgeInsets.fromLTRB(
    //         isStartCols || nbColFreeze == 0 ? pleft : 0,
    //         ptop,
    //         isStartCols && nbColFreeze != 0 ? 0 : pright,
    //         pbottom,
    //       ),
    //       child: Material(
    //         color:
    //             (isSelected ? selColor : null) ??
    //             (_isHovered ? hoverColor : null),

    //         elevation: elevation,
    //         borderRadius: boxDecoration.borderRadius,
    //         child: Container(
    //           decoration: boxDecoration,
    //           padding: EdgeInsets.fromLTRB(
    //             isStartCols || nbColFreeze == 0 ? mleft : 0,
    //             mtop,
    //             isStartCols && nbColFreeze != 0 ? 0 : mright,
    //             mbottom,
    //           ),
    //           child: child,
    //         ),
    //       ),
    //     ),
    //   );
    // } else {
    //   return getGestureDetector(
    //     Container(
    //       key: ObjectKey(widget.info.data),
    //       margin: EdgeInsets.fromLTRB(
    //         isStartCols || nbColFreeze == 0 ? pleft : 0,
    //         ptop,
    //         isStartCols && nbColFreeze != 0 ? 0 : pright,
    //         pbottom,
    //       ),
    //       decoration: boxDecoration,
    //       padding: EdgeInsets.fromLTRB(
    //         isStartCols || nbColFreeze == 0 ? mleft : 0,
    //         mtop,
    //         isStartCols && nbColFreeze != 0 ? 0 : mright,
    //         mbottom,
    //       ),
    //       child: child,
    //     ),
    //   );
    // }
  }

  // Widget getGestureDetector(Widget child) {
  //   StateContainerArray? arrayContainer = widget.info.arrayContainer;
  //   int row = widget.info.row;
  //   CwWidgetCtx ctx = widget.info.ctx;
  //   if (arrayContainer != null && row > 0) {
  //     return MouseRegion(
  //       onEnter: (_) => setState(() => _isHovered = true),
  //       onExit: (_) => setState(() => _isHovered = false),
  //       child: GestureDetector(
  //         onTap: () {
  //           var w = (ctx.widgetState as CwWidgetStateBindJson);
  //           w.doChangeRowFromParent(context, stateArray: w);
  //         },
  //         child: child,
  //       ),
  //     );
  //   } else {
  //     return child;
  //   }
  // }
}

class CWInheritedRow extends InheritedWidget {
  const CWInheritedRow({
    super.key,
    required super.child,
    required this.path,
    required this.rowIdx,
    required this.tableKey,
    required this.rowkey,
  });
  final String path;
  final int rowIdx;
  final GlobalKey tableKey;
  final GlobalKey rowkey;

  void getAll(Map<String, CWInheritedRow> list) {
    var r = tableKey.currentContext
        ?.getInheritedWidgetOfExactType<CWInheritedRow>();
    if (r != null) {
      list[r.path] = r;
      r.getAll(list);
    }
  }

  @override
  bool updateShouldNotify(covariant CWInheritedRow oldWidget) {
    return path != oldWidget.path ||
        rowIdx != oldWidget.rowIdx ||
        tableKey != oldWidget.tableKey ||
        rowkey != oldWidget.rowkey;
  }
}
