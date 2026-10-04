import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../actions/file_actions.dart';
import '../services/file_operations.dart';

/// Barre verticale de 40 px entre les deux volets de la vue partagée.
class FileActionBar extends StatefulWidget {
  const FileActionBar({
    required this.actionContext,
    this.actions = FileAction.split,
    this.onMessage,
    super.key,
  });

  static const double width = 40;

  /// `null` tant que les deux volets ne sont pas prêts.
  final FileActionContext? actionContext;
  final List<FileAction> actions;
  final ValueChanged<String>? onMessage;

  @override
  State<FileActionBar> createState() => _FileActionBarState();
}

class _FileActionBarState extends State<FileActionBar> {
  FileAction? _running;
  FileJob? _job;

  Future<void> _run(FileAction action, FileActionContext context) async {
    setState(() => _running = action);
    try {
      final message = await action.run(
        context.withTracker((job) {
          if (mounted) setState(() => _job = job);
        }),
      );
      if (message != null) widget.onMessage?.call(message);
    } on FileSystemException catch (error) {
      widget.onMessage?.call(
        '${action.label} impossible : ${error.message}'
        '${error.path == null ? '' : ' (${error.path})'}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _running = null;
          _job = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionContext = widget.actionContext;
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: FileActionBar.width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.symmetric(
            vertical: BorderSide(color: colors.outlineVariant),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Évite le crash de l'itérateur de cette collection en AOT Windows.
            for (var i = 0; i < widget.actions.length; i++)
              _buildAction(widget.actions[i], actionContext),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(FileAction action, FileActionContext? context) {
    final VoidCallback? onPressed =
        _running == null && context != null && action.isEnabled(context)
        ? () => _run(action, context)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _running == action
          ? _progress(_job)
          : IconButton(
              key: ValueKey('file-action-${action.id}'),
              tooltip: action.label,
              icon: Icon(action.icon, size: 20),
              style: IconButton.styleFrom(
                minimumSize: const Size(32, 32),
                maximumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onPressed,
            ),
    );
  }

  Widget _progress(FileJob? job) {
    if (job == null) {
      return const SizedBox.square(
        dimension: 32,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return StreamBuilder<FileProgress>(
      stream: job.progress,
      initialData: job.latest,
      builder: (context, snapshot) {
        final progress = snapshot.data;
        final fraction = progress?.fraction;
        final detail = progress == null
            ? 'Préparation…'
            : '${progress.doneItems} / ${progress.totalItems} fichier(s)'
                  '${progress.current == null ? '' : '\n${progress.current}'}';
        return Tooltip(
          message: job.isCancelling
              ? 'Annulation…'
              : '$detail\nCliquer pour annuler',
          child: SizedBox.square(
            dimension: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CircularProgressIndicator(
                    key: const ValueKey('file-action-progress'),
                    value: fraction,
                    strokeWidth: 2.5,
                  ),
                ),
                IconButton(
                  key: const ValueKey('file-action-cancel'),
                  icon: const Icon(Icons.close_rounded, size: 14),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(24, 24),
                    maximumSize: const Size(24, 24),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: job.isCancelling
                      ? null
                      : () => setState(job.cancel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
