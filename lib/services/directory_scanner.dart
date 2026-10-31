import 'dart:io';
import 'dart:isolate';

import '../models/explorer_entry.dart';

/// Lit le contenu d'un dossier sans figer l'interface.
///
/// La liste des noms est lue de façon asynchrone (rapide). Le `stat` de chaque
/// élément, coûteux sur les gros dossiers, n'est déporté dans un isolate qu'au
/// delà de [isolateThreshold] éléments : en dessous, le coût de démarrage d'un
/// isolate serait supérieur au gain.
class DirectoryScanner {
  const DirectoryScanner._();

  static const isolateThreshold = 300;

  static Future<List<ExplorerEntry>> scan(String path) async {
    final entities = await Directory(path).list(followLinks: false).toList();
    if (entities.length <= isolateThreshold) {
      return Future.wait(entities.map(_entryAsync));
    }
    final items = [
      for (final entity in entities)
        (entity.path, entity is Directory, entity is Link),
    ];
    return Isolate.run(
      () => [for (final item in items) _entrySync(item)],
      debugName: 'directory-scan',
    );
  }

  /// Lit uniquement les noms et types (dossier/fichier) sans appel `stat()`.
  static Future<List<ExplorerEntry>> scanNames(String path) async {
    final entities = await Directory(path).list(followLinks: false).toList();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return [
      for (final entity in entities)
        ExplorerEntry(
          entity: entity,
          name: _nameOf(entity.path),
          isDirectory: entity is Directory,
          modified: epoch,
          size: 0,
        ),
    ];
  }

  static Future<ExplorerEntry> _entryAsync(FileSystemEntity entity) async =>
      _entry(entity, await entity.stat());

  static ExplorerEntry _entrySync((String, bool, bool) item) {
    final (path, isDirectory, isLink) = item;
    final FileSystemEntity entity = isDirectory
        ? Directory(path)
        : isLink
        ? Link(path)
        : File(path);
    return _entry(entity, entity.statSync());
  }

  static String _nameOf(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  static ExplorerEntry _entry(FileSystemEntity entity, FileStat stat) {
    return ExplorerEntry(
      entity: entity,
      name: _nameOf(entity.path),
      isDirectory: entity is Directory,
      modified: stat.modified,
      size: stat.size,
    );
  }
}
