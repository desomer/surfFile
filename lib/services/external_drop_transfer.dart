import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'file_operations.dart';

class ExternalDropTransfer {
  const ExternalDropTransfer._();

  static final prompting = ValueNotifier(false);

  static String _normalize(String path) {
    var normalized = File(path).absolute.path.replaceAll('\\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static Future<FileJob?> confirm(
    BuildContext context,
    List<String> sources,
    String destination,
  ) async {
    if (prompting.value) return null;
    if (sources.isEmpty) {
      throw const FileSystemException(
        'Le dépôt ne contient aucun fichier local.',
      );
    }
    final paths = {
      for (final source in sources) _normalize(source): source,
    }.values.toList();
    final target = _normalize(destination);
    for (final source in paths) {
      final from = _normalize(source);
      if (target == from || target.startsWith('$from/')) {
        throw FileSystemException(
          'Impossible de déposer un dossier dans lui-même.',
          source,
        );
      }
    }
    prompting.value = true;
    final FileTransfer? kind;
    try {
      kind = await showDialog<FileTransfer>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('external-drop-dialog'),
          title: const Text('Copier ou déplacer ?'),
          content: Text(
            '${paths.length == 1 ? '« ${FileOperations.name(paths.single)} »' : '${paths.length} éléments'}'
            '\nvers « $destination »',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            OutlinedButton(
              key: const ValueKey('external-drop-move'),
              onPressed: () => Navigator.of(context).pop(FileTransfer.move),
              child: const Text('Déplacer'),
            ),
            FilledButton(
              key: const ValueKey('external-drop-copy'),
              onPressed: () => Navigator.of(context).pop(FileTransfer.copy),
              child: const Text('Copier'),
            ),
          ],
        ),
      );
    } finally {
      prompting.value = false;
    }
    if (kind == null || !context.mounted) return null;
    if (kind == FileTransfer.move &&
        paths.any((path) => _normalize(FileOperations.parent(path)) == target)) {
      throw FileSystemException(
        'Un élément se trouve déjà dans le dossier de destination.',
        destination,
      );
    }
    return FileOperations.start(kind, paths, destination);
  }
}
