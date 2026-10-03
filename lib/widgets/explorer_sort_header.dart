import 'package:material_ui/material_ui.dart';

import '../models/explorer_entry.dart';
import '../theme/explorer_colors.dart';

class ExplorerSortHeader extends StatelessWidget {
  const ExplorerSortHeader({
    required this.sort,
    required this.ascending,
    required this.onSortChanged,
    super.key,
  });

  final ExplorerSort sort;
  final bool ascending;
  final ValueChanged<ExplorerSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 3, 34, 3),
      child: Row(
        children: [
          Expanded(
              flex: 5, child: _sortButton(context, 'Nom', ExplorerSort.name)),
          Expanded(
              flex: 2,
              child: _sortButton(context, 'Modifié', ExplorerSort.modified)),
          Expanded(flex: 2, child: _sortButton(context, 'Type', null)),
          Expanded(
              flex: 1,
              child: _sortButton(context, 'Taille', ExplorerSort.size)),
        ],
      ),
    );
  }

  Widget _sortButton(
      BuildContext context, String label, ExplorerSort? selectedSort) {
    final isSelected = selectedSort == sort;
    return InkWell(
      onTap: selectedSort == null ? null : () => onSortChanged(selectedSort),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        child: Row(
          children: [
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: explorerColor(
                        context,
                        isSelected
                            ? const Color(0xFF454D60)
                            : const Color(0xFF9298A8),
                        Theme.of(context).colorScheme.onSurfaceVariant),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  )),
            ),
            if (isSelected)
              Icon(
                ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 13,
                color: explorerColor(context, const Color(0xFF737B8F),
                    Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
