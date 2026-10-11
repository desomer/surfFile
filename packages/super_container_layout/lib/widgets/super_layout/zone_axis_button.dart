import 'package:material_ui/material_ui.dart';

import 'layout_selection.dart';

class ZoneAxisButton extends StatelessWidget {
  const ZoneAxisButton({required this.action, this.color, super.key});

  final LayoutAxisAction action;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final row = action.axis == Axis.horizontal;
    return IconButton(
      tooltip:
          '${action.zoneLabel} : ${row ? 'Row' : 'Column'}'
          ' - Passer en ${row ? 'Column' : 'Row'}',
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      color: color,
      icon: Icon(row ? Icons.view_column_outlined : Icons.table_rows_outlined),
      onPressed: action.onToggle,
    );
  }
}
