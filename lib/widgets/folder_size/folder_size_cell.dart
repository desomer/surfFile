import 'package:material_ui/material_ui.dart';

import '../../services/folder_size_service.dart';
import '../explorer/views/explorer_entries_view.dart' show formatExplorerSize;
import 'folder_size_indicator.dart';

/// Taille d'un dossier : icône de calcul tant qu'elle est inconnue, indicateur
/// pendant le calcul (dans un isolate), puis la taille (cliquable pour
/// recalculer).
class FolderSizeCell extends StatelessWidget {
  const FolderSizeCell({
    required this.path,
    required this.style,
    this.siblingFolders,
    this.siblingSizes,
    super.key,
  });

  final String path;
  final TextStyle style;

  /// Tailles de tous les éléments du répertoire, pour l'indicateur visuel.
  final List<int> Function()? siblingSizes;

  /// Dossiers du même répertoire : à la fin du calcul, propose de calculer
  /// aussi ceux dont la taille est encore inconnue.
  final List<String> Function()? siblingFolders;

  Future<void> _compute(BuildContext context) async {
    if (!await FolderSizeService.compute(path) || !context.mounted) return;
    final others = FolderSizeService.uncomputed(
      (siblingFolders?.call() ?? const <String>[]).where((p) => p != path),
    );
    if (others.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('folder-size-others-dialog'),
        title: const Text('Calculer les autres dossiers ?'),
        content: Text(
          others.length == 1
              ? 'Calculer aussi la taille de l\'autre dossier de ce répertoire ?'
              : 'Calculer aussi la taille des ${others.length} autres '
                    'dossiers de ce répertoire ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Non'),
          ),
          FilledButton(
            key: const ValueKey('folder-size-others-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oui'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FolderSizeService.computeAll(FolderSizeService.uncomputed(others));
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = (style.fontSize ?? 14) + 6;
    return ValueListenableBuilder<FolderSizeState>(
      valueListenable: FolderSizeService.of(path),
      builder: (context, state, _) {
        if (state.computing) {
          return Align(
            alignment: Alignment.centerLeft,
            child: _CancellableProgress(
              path: path,
              size: iconSize - 4,
              color: style.color,
            ),
          );
        }
        final bytes = state.bytes;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizeGauge(
            bytes: () => FolderSizeService.bytesOf(path),
            siblingSizes: siblingSizes,
            child: Tooltip(
              message: bytes == null
                  ? 'Calculer la taille du dossier'
                  : 'Recalculer la taille du dossier',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _compute(context),
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
          ),
        );
      },
    );
  }
}

/// Indicateur de calcul ; au survol, une croix permet d'annuler le calcul.
class _CancellableProgress extends StatefulWidget {
  const _CancellableProgress({
    required this.path,
    required this.size,
    required this.color,
  });

  final String path;
  final double size;
  final Color? color;

  @override
  State<_CancellableProgress> createState() => _CancellableProgressState();
}

class _CancellableProgressState extends State<_CancellableProgress> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox.square(
        key: const ValueKey('folder-size-progress'),
        dimension: widget.size,
        child: _hovered
            ? Tooltip(
                message: 'Annuler le calcul',
                child: InkWell(
                  key: const ValueKey('folder-size-cancel'),
                  customBorder: const CircleBorder(),
                  onTap: () => FolderSizeService.cancel(widget.path),
                  child: Icon(
                    Icons.close_rounded,
                    size: widget.size,
                    color: widget.color,
                  ),
                ),
              )
            : CircularProgressIndicator(strokeWidth: 2, color: widget.color),
      ),
    );
  }
}
