import 'dart:io';

/// Opérations disque utilisées par les actions sur fichiers.
class FileOperations {
  const FileOperations._();

  /// Copie [source] (fichier ou dossier) dans [destinationDir] et renvoie le
  /// chemin créé. Le nom est suffixé (`nom (2).ext`) s'il existe déjà.
  static Future<String> copy(String source, String destinationDir) async {
    _checkTarget(source, destinationDir);
    final target = await uniquePath(destinationDir, name(source));
    await _copy(source, target);
    return target;
  }

  /// Déplace [source] dans [destinationDir] et renvoie le nouveau chemin.
  static Future<String> move(String source, String destinationDir) async {
    _checkTarget(source, destinationDir);
    if (_same(parent(source), destinationDir)) return source;
    final target = await uniquePath(destinationDir, name(source));
    final type = await FileSystemEntity.type(source, followLinks: false);
    try {
      await _entity(source, type).rename(target);
    } on FileSystemException {
      // Volumes différents : copie puis suppression.
      await _copy(source, target);
      await _entity(source, type).delete(recursive: true);
    }
    return target;
  }

  static Future<String> uniquePath(String directory, String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final hasExtension = dot > 0;
    final base = hasExtension ? fileName.substring(0, dot) : fileName;
    final extension = hasExtension ? fileName.substring(dot) : '';
    var candidate = join(directory, fileName);
    for (var i = 2; await _exists(candidate); i++) {
      candidate = join(directory, '$base ($i)$extension');
    }
    return candidate;
  }

  static String name(String path) {
    final parts = path
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  static String parent(String path) => File(path).parent.path;

  static String join(String directory, String child) =>
      '$directory${directory.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$child';

  static void _checkTarget(String source, String destinationDir) {
    final from = _normalize(source);
    final to = _normalize(destinationDir);
    if (to == from || to.startsWith('$from/')) {
      throw FileSystemException(
        'Impossible de placer un dossier dans lui-même',
        source,
      );
    }
  }

  static bool _same(String a, String b) => _normalize(a) == _normalize(b);

  static String _normalize(String path) {
    var value = path.replaceAll('\\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  static Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  static FileSystemEntity _entity(String path, FileSystemEntityType type) =>
      switch (type) {
        FileSystemEntityType.directory => Directory(path),
        FileSystemEntityType.link => Link(path),
        FileSystemEntityType.notFound => throw FileSystemException(
          'Élément introuvable',
          path,
        ),
        _ => File(path),
      };

  static Future<void> _copy(String source, String target) async {
    final type = await FileSystemEntity.type(source, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(target).create();
        await for (final child in Directory(source).list(followLinks: false)) {
          await _copy(child.path, join(target, name(child.path)));
        }
      case FileSystemEntityType.link:
        await Link(target).create(await Link(source).target());
      case FileSystemEntityType.notFound:
        throw FileSystemException('Élément introuvable', source);
      default:
        await File(source).copy(target);
    }
  }
}
