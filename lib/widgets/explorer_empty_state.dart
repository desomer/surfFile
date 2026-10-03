import 'package:material_ui/material_ui.dart';
import '../theme/explorer_colors.dart';

class ExplorerEmptyState extends StatelessWidget {
  const ExplorerEmptyState({required this.hasQuery, super.key});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 52,
            color: Color(0xFFB9C0CF),
          ),
          const SizedBox(height: 12),
          Text(
            hasQuery ? 'Aucun résultat' : 'Ce dossier est vide',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            hasQuery
                ? 'Essayez avec un autre terme de recherche.'
                : 'Créez un dossier ou choisissez un autre emplacement.',
            style: TextStyle(fontSize: 12,
                color: explorerColor(context, const Color(0xFF9298A8),
                    Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
