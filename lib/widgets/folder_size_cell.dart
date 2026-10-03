import 'package:material_ui/material_ui.dart';

import '../services/folder_size_service.dart';
import 'explorer_entries_view.dart' show formatExplorerSize;

/// Taille d'un dossier : icône de calcul tant qu'elle est inconnue, indicateur
/// pendant le calcul (dans un isolate), puis la taille (cliquable pour
/// recalculer).
class FolderSizeCell extends StatelessWidget {
  const FolderSizeCell({required this.path, required this.style, super.key});

  final String path;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final iconSize = (style.fontSize ?? 14) + 6;
    return ValueListenableBuilder<FolderSizeState>(
      valueListenable: FolderSizeService.of(path),
      builder: (context, state, _) {
        if (state.computing) {
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox.square(
              key: const ValueKey('folder-size-progress'),
              dimension: iconSize - 4,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: style.color,
              ),
            ),
          );
        }
        final bytes = state.bytes;
        return Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: bytes == null
                ? 'Calculer la taille du dossier'
                : 'Recalculer la taille du dossier',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => FolderSizeService.compute(path),
              child: bytes == null
                  ? Icon(
                      Icons.psychology,
                      key: const ValueKey('folder-size-compute'),
                      size: iconSize,
                      color: style.color,
                    )
                  : Text(
                      formatExplorerSize(bytes),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
            ),
          ),
        );
      },
    );
  }
}
