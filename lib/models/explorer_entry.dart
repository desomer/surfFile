import 'dart:io';

import '../services/folder_size_service.dart';

enum ExplorerSort { name, modified, size }

class ExplorerEntry {
  const ExplorerEntry({
    required this.entity,
    required this.name,
    required this.isDirectory,
    required this.modified,
    required this.size,
  });

  final FileSystemEntity entity;
  final String name;
  final bool isDirectory;
  final DateTime modified;
  final int size;
}

/// Taille de tri : pour un dossier, la taille calculée (-1 si inconnue).
int _sizeKey(ExplorerEntry entry) => entry.isDirectory
    ? FolderSizeService.bytesOf(entry.entity.path) ?? -1
    : entry.size;

/// Dossiers d'abord, puis selon [sort] ; [ascending] n'inverse que ce second
/// critère.
void sortExplorerEntries(
  List<ExplorerEntry> entries,
  ExplorerSort sort, {
  required bool ascending,
}) {
  final lower = {for (final entry in entries) entry: entry.name.toLowerCase()};
  entries.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    final comparison = switch (sort) {
      ExplorerSort.name => lower[a]!.compareTo(lower[b]!),
      ExplorerSort.modified => a.modified.compareTo(b.modified),
      ExplorerSort.size => _sizeKey(a).compareTo(_sizeKey(b)),
    };
    return ascending ? comparison : -comparison;
  });
}
