import 'package:flutter/foundation.dart' show setEquals;
import 'package:material_ui/material_ui.dart';

import 'explorer_entry.dart';

/// Ancienneté de la dernière modification.
enum FilterAge {
  any('Toutes dates', null),
  today('Aujourd’hui', null),
  week('7 derniers jours', Duration(days: 7)),
  month('30 derniers jours', Duration(days: 30)),
  year('Cette année', Duration(days: 365)),
  old('Vieux (+ d’1 an)', Duration(days: 365)),
  veryOld('Très vieux (+ de 3 ans)', Duration(days: 3 * 365));

  const FilterAge(this.label, this.duration);
  final String label;
  final Duration? duration;

  bool matches(DateTime modified, DateTime now) => switch (this) {
    any => true,
    today =>
      modified.year == now.year &&
          modified.month == now.month &&
          modified.day == now.day,
    week || month || year => now.difference(modified) <= duration!,
    old || veryOld => now.difference(modified) > duration!,
  };
}

/// Catégorie d'élément déduite de l'extension.
enum FileKind {
  folder('Dossiers', Icons.folder_rounded, {}),
  image('Images', Icons.image_outlined, {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'svg',
    'ico',
    'tif',
    'tiff',
    'heic',
    'raw',
    'psd',
  }),
  video('Vidéos', Icons.movie_outlined, {
    'mp4',
    'mkv',
    'avi',
    'mov',
    'wmv',
    'webm',
    'flv',
    'm4v',
    'mpg',
    'mpeg',
  }),
  audio('Audio', Icons.music_note_outlined, {
    'mp3',
    'wav',
    'flac',
    'aac',
    'ogg',
    'm4a',
    'wma',
    'opus',
  }),
  document('Documents', Icons.description_outlined, {
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'odt',
    'ods',
    'odp',
    'txt',
    'rtf',
    'md',
    'csv',
  }),
  archive('Archives', Icons.inventory_2_outlined, {
    'zip',
    'rar',
    '7z',
    'tar',
    'gz',
    'bz2',
    'xz',
    'iso',
    'cab',
  }),
  code('Code', Icons.code_rounded, {
    'dart',
    'js',
    'ts',
    'py',
    'java',
    'kt',
    'c',
    'cpp',
    'h',
    'cs',
    'go',
    'rs',
    'html',
    'css',
    'json',
    'xml',
    'yaml',
    'yml',
    'sh',
    'ps1',
    'bat',
    'sql',
  }),
  program('Programmes', Icons.terminal_rounded, {
    'exe',
    'msi',
    'dll',
    'appx',
    'msix',
    'lnk',
    'com',
  }),
  other('Autres', Icons.insert_drive_file_outlined, {});

  const FileKind(this.label, this.icon, this.extensions);
  final String label;
  final IconData icon;
  final Set<String> extensions;

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static FileKind of(ExplorerEntry entry) {
    if (entry.isDirectory) return folder;
    final extension = extensionOf(entry.name);
    for (final kind in values) {
      if (kind.extensions.contains(extension)) return kind;
    }
    return other;
  }
}

/// Taille des fichiers (les dossiers sont masqués dès qu'elle est filtrée).
enum FilterSize {
  any('Toutes tailles', 0, null),
  empty('Vides', 0, 1),
  small('< 1 Mo', 0, 1 << 20),
  medium('1 – 100 Mo', 1 << 20, 100 << 20),
  large('100 Mo – 1 Go', 100 << 20, 1 << 30),
  huge('> 1 Go', 1 << 30, null);

  const FilterSize(this.label, this.min, this.max);
  final String label;
  final int min;
  final int? max;

  bool matches(int size) => size >= min && (max == null || size < max!);
}

@immutable
class ExplorerFilter {
  const ExplorerFilter({
    this.age = FilterAge.any,
    this.kinds = const {},
    this.size = FilterSize.any,
    this.extension = '',
  });

  final FilterAge age;

  /// Vide : tous les types.
  final Set<FileKind> kinds;
  final FilterSize size;

  /// Extensions libres séparées par des virgules ou des espaces (« pdf, docx »).
  final String extension;

  Set<String> get extensions => {
    for (final part in extension.toLowerCase().split(RegExp(r'[\s,;]+')))
      if (part.replaceFirst(RegExp(r'^\*?\.'), '') case final e
          when e.isNotEmpty)
        e,
  };

  /// Nombre de critères actifs (badge de l'icône).
  int get activeCount =>
      (age == FilterAge.any ? 0 : 1) +
      (kinds.isEmpty ? 0 : 1) +
      (size == FilterSize.any ? 0 : 1) +
      (extensions.isEmpty ? 0 : 1);

  bool get isActive => activeCount > 0;

  ExplorerFilter copyWith({
    FilterAge? age,
    Set<FileKind>? kinds,
    FilterSize? size,
    String? extension,
  }) => ExplorerFilter(
    age: age ?? this.age,
    kinds: kinds ?? this.kinds,
    size: size ?? this.size,
    extension: extension ?? this.extension,
  );

  /// Prédicat évalué une fois par liste (date de référence figée).
  bool Function(ExplorerEntry) matcher() {
    if (!isActive) return (_) => true;
    final now = DateTime.now();
    final extensions = this.extensions;
    return (entry) {
      if (!age.matches(entry.modified, now)) return false;
      if (size != FilterSize.any &&
          (entry.isDirectory || !size.matches(entry.size))) {
        return false;
      }
      if (kinds.isNotEmpty && !kinds.contains(FileKind.of(entry))) {
        return false;
      }
      if (extensions.isNotEmpty &&
          (entry.isDirectory ||
              !extensions.contains(FileKind.extensionOf(entry.name)))) {
        return false;
      }
      return true;
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ExplorerFilter &&
      other.age == age &&
      other.size == size &&
      other.extension == extension &&
      setEquals(other.kinds, kinds);

  @override
  int get hashCode =>
      Object.hash(age, size, extension, Object.hashAllUnordered(kinds));
}
