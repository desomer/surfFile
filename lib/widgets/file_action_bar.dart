import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../actions/file_actions.dart';

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

  Future<void> _run(FileAction action, FileActionContext context) async {
    setState(() => _running = action);
    try {
      final message = await action.run(context);
      if (message != null) widget.onMessage?.call(message);
    } on FileSystemException catch (error) {
      widget.onMessage?.call(
        '${action.label} impossible : ${error.message}'
        '${error.path == null ? '' : ' (${error.path})'}',
      );
    } finally {
      if (mounted) setState(() => _running = null);
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
            for (final action in widget.actions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _running == action
                    ? const SizedBox.square(
                        dimension: 32,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
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
                        onPressed:
                            _running == null &&
                                actionContext != null &&
                                action.isEnabled(actionContext)
                            ? () => _run(action, actionContext)
                            : null,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
