import 'dart:io';

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
      ExplorerSort.size => a.size.compareTo(b.size),
    };
    return ascending ? comparison : -comparison;
  });
}
