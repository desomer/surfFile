import 'package:material_ui/material_ui.dart';

import 'layout_selection.dart';

class ZoneAxisButton extends StatelessWidget {
  const ZoneAxisButton({
    required this.action,
    this.color,
    this.compact = false,
    super.key,
  });

  final LayoutAxisAction action;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final row = action.axis == Axis.horizontal;
    return IconButton(
      tooltip:
          '${action.zoneLabel} : ${row ? 'Row' : 'Column'}'
          ' - Passer en ${row ? 'Column' : 'Row'}',
      visualDensity: VisualDensity.compact,
      iconSize: compact ? 14 : 18,
      padding: compact ? EdgeInsets.zero : null,
      constraints: compact
          ? const BoxConstraints.tightFor(width: 24, height: 24)
          : null,
      style: compact
          ? IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
      color: color,
      icon: Icon(row ? Icons.view_column_outlined : Icons.table_rows_outlined),
      onPressed: action.onToggle,
    );
  }
}
