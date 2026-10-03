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
