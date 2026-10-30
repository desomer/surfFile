import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/components/internal_widget/array/cw_table_layout.dart';

class CwRowInfo {
  final int row;
  final bool isStartCols;
  final int nbColFreeze;
  final Map<String, dynamic>? propsRow;
  final FrozenTableViewState tableState;
  final dynamic data;
  final ContainerStyle? style;
  final bool isHeader;

  CwRowInfo({
    required this.row,
    required this.isStartCols,
    required this.nbColFreeze,
    required this.propsRow,
    required this.tableState,
    required this.data,
    this.style,
    this.isHeader = false,
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
    if (oldWidget.child != widget.child) {
      newChild = null;
    }
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

  static double _readDouble(
    Map<String, dynamic>? map,
    String key,
    double fallback,
  ) {
    final raw = map?[key];
    if (raw is num && raw.isFinite) return raw.toDouble();
    if (raw is String) {
      return double.tryParse(raw.trim().replaceAll(',', '.')) ?? fallback;
    }
    return fallback;
  }

  static Color? _readColor(Map<String, dynamic>? map, String key) {
    final raw = map?[key];
    if (raw is Color) return raw;
    if (raw is int) return Color(raw);
    if (raw is String) {
      final hex = raw.trim().replaceFirst(RegExp(r'^#'), '');
      if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
        return Color(0xFF000000 | int.parse(hex, radix: 16));
      }
      if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    return null;
  }

  Widget getRowStyleWidget(
    int row,
    bool isStartCols,
    int nbColFreeze,
    Map<String, dynamic>? dataRow,
    Widget child,
    BuildContext context,
  ) {
    final tableState = widget.info.tableState;
    final isHeaderRow =
        widget.info.isHeader || row < tableState.widget.rowCountTop;
    if (isHeaderRow) {
      return child;
    }

    final hasLeftEdge = isStartCols || nbColFreeze == 0;
    final hasRightEdge = !isStartCols || nbColFreeze == 0;
    final baseStyle = widget.info.style;

    final animateIndicators = tableState.widget.animateSelectionAndHover;
    final isHovered = tableState.hoveredRowNotifier.value == row;
    final isSelected = tableState.selectedRowNotifier.value == row;
    final resolvedStyle =
        baseStyle?.states?.resolve(
          baseStyle,
          isHovered: !animateIndicators && isHovered,
          isSelected: !animateIndicators && isSelected,
        ) ??
        baseStyle;

    final bRadius = resolvedStyle?.radius ?? _readDouble(dataRow, 'bRadius', 0);
    final rawBSize =
        resolvedStyle?.borderWidth ?? _readDouble(dataRow, 'bSize', 0);
    final bSize = rawBSize <= 0 ? 0.0 : rawBSize;
    final bColor = bSize == 0
        ? Colors.transparent
        : (resolvedStyle?.borderColor ??
              _readColor(dataRow, 'bColor') ??
              Colors.transparent);
    final effectiveRadius = bSize == 0 && resolvedStyle == null ? 0.0 : bRadius;

    final scheme = Theme.of(context).colorScheme;
    final selColor =
        _readColor(dataRow, 'selColor') ??
        (baseStyle?.states?.hasSelected == true
            ? resolvedStyle?.color
            : scheme.primary.withValues(alpha: 0.14));
    final hoverColor =
        _readColor(dataRow, 'hoverColor') ??
        (baseStyle?.states?.hover != null
            ? resolvedStyle?.color
            : scheme.onSurface.withValues(alpha: 0.05));
    final baseColor = resolvedStyle?.color ?? _readColor(dataRow, 'color');

    final mMargin = resolvedStyle?.outerMargin;
    final mleft = mMargin?.left ?? _readDouble(dataRow, 'pleft', 0);
    final mtop = mMargin?.top ?? _readDouble(dataRow, 'ptop', 0);
    final mright = mMargin?.right ?? _readDouble(dataRow, 'pright', 0);
    final mbottom = mMargin?.bottom ?? _readDouble(dataRow, 'pbottom', 0);

    final pPadding = resolvedStyle?.contentPadding;
    final pleft = pPadding?.left ?? _readDouble(dataRow, 'mleft', 0);
    final ptop = pPadding?.top ?? _readDouble(dataRow, 'mtop', 0);
    final pright = pPadding?.right ?? _readDouble(dataRow, 'mright', 0);
    final pbottom = pPadding?.bottom ?? _readDouble(dataRow, 'mbottom', 0);

    final rawElevation =
        resolvedStyle?.elevation ??
        (dataRow?.containsKey('elevation') == true
            ? _readDouble(dataRow, 'elevation', 0)
            : 0.0);
    final elevation = rawElevation > 0 ? rawElevation : null;

    final borderRadius = BorderRadius.only(
      topLeft: hasLeftEdge ? Radius.circular(effectiveRadius) : Radius.zero,
      topRight: hasRightEdge ? Radius.circular(effectiveRadius) : Radius.zero,
      bottomLeft: hasLeftEdge ? Radius.circular(effectiveRadius) : Radius.zero,
      bottomRight: hasRightEdge
          ? Radius.circular(effectiveRadius)
          : Radius.zero,
    );

    final border = bSize > 0
        ? Border(
            top: BorderSide(color: bColor, width: bSize),
            bottom: BorderSide(color: bColor, width: bSize),
            left: hasLeftEdge
                ? BorderSide(color: bColor, width: bSize)
                : BorderSide.none,
            right: hasRightEdge
                ? BorderSide(color: bColor, width: bSize)
                : BorderSide.none,
          )
        : null;

    final effectiveColor = animateIndicators
        ? baseColor
        : ((isSelected ? selColor : null) ??
              (isHovered ? hoverColor : null) ??
              baseColor);

    final margin = EdgeInsets.fromLTRB(
      hasLeftEdge ? mleft : 0,
      mtop,
      hasRightEdge ? mright : 0,
      mbottom,
    );
    final padding = EdgeInsets.fromLTRB(
      hasLeftEdge ? pleft : 0,
      ptop,
      hasRightEdge ? pright : 0,
      pbottom,
    );

    final boxDecoration = BoxDecoration(
      borderRadius: effectiveRadius > 0 ? borderRadius : null,
      color: elevation == null ? effectiveColor : null,
      border: border,
    );

    final Widget styledRow;
    if (elevation != null) {
      styledRow = Container(
        key: widget.info.data != null ? ObjectKey(widget.info.data) : null,
        margin: margin,
        child: Material(
          color: effectiveColor ?? Colors.transparent,
          elevation: elevation,
          borderRadius: borderRadius,
          child: Container(
            decoration: boxDecoration,
            padding: padding,
            child: child,
          ),
        ),
      );
    } else {
      styledRow = Container(
        key: widget.info.data != null ? ObjectKey(widget.info.data) : null,
        margin: margin,
        decoration: boxDecoration,
        padding: padding,
        child: child,
      );
    }

    return MouseRegion(
      onEnter: (_) => tableState.setHoveredRow(row),
      onExit: (_) {
        if (tableState.hoveredRowNotifier.value == row) {
          tableState.setHoveredRow(null);
        }
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons == kPrimaryButton) {
            tableState.selectRow(row);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => tableState.selectRow(row),
          child: styledRow,
        ),
      ),
    );
  }
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
