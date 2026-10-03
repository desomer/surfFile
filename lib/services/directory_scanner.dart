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

  static ExplorerEntry _entry(FileSystemEntity entity, FileStat stat) {
    final parts = entity.path.replaceAll('\\', '/').split('/');
    return ExplorerEntry(
      entity: entity,
      name: parts.isEmpty ? entity.path : parts.last,
      isDirectory: entity is Directory,
      modified: stat.modified,
      size: stat.size,
    );
  }
}
