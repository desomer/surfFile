import 'package:material_ui/material_ui.dart';

import '../models/explorer_entry.dart';

class ExplorerFileIcon extends StatelessWidget {
  const ExplorerFileIcon({required this.entry, required this.size, super.key});

  final ExplorerEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color =
        entry.isDirectory ? const Color(0xFFEABF5E) : _fileColor(entry.name);
    return Icon(
      entry.isDirectory ? Icons.folder_rounded : _fileIconData(entry.name),
      size: size,
      color: color,
    );
  }

  Color _fileColor(String name) {
    final extension = name.split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].contains(extension)) {
      return const Color(0xFF52A68A);
    }
    if (extension == 'pdf') return const Color(0xFFD76B6B);
    if (['doc', 'docx', 'txt', 'rtf'].contains(extension)) {
      return const Color(0xFF5A83C8);
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(extension)) {
      return const Color(0xFF9A76C8);
    }
    return const Color(0xFF8A94A8);
  }

  IconData _fileIconData(String name) {
    final extension = name.split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].contains(extension)) {
      return Icons.image_outlined;
    }
    if (extension == 'pdf') return Icons.picture_as_pdf_outlined;
    if (['mp4', 'mov', 'mkv', 'avi'].contains(extension)) {
      return Icons.movie_outlined;
    }
    if (['mp3', 'wav', 'flac', 'aac'].contains(extension)) {
      return Icons.audio_file_outlined;
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(extension)) {
      return Icons.archive_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}
