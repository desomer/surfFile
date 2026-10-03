import 'dart:io';

import 'package:flutter/services.dart';

class DiskSpace {
  const DiskSpace({
    required this.path,
    this.totalBytes,
    this.freeBytes,
    this.error,
  });

  final String path;
  final int? totalBytes;
  final int? freeBytes;
  final String? error;

  double? get usedFraction => totalBytes == null || freeBytes == null
      ? null
      : (totalBytes! - freeBytes!) / totalBytes!;

  static const channel = MethodChannel('surf_file/disk_space');

  static Future<List<DiskSpace>> load() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Les disques sont disponibles sous Windows.');
    }
    final values = await channel.invokeMethod<Object?>('getDisks');
    if (values is! List) {
      throw const FormatException('Liste de disques invalide.');
    }
    return values.map((value) {
      if (value is! Map || value['path'] is! String ||
          (value['path'] as String).isEmpty) {
        throw const FormatException('Chemin de disque invalide.');
      }
      final total = value['totalBytes'];
      final free = value['freeBytes'];
      final error = value['error'];
      if (error != null) {
        if (error is! String || error.isEmpty) {
          throw const FormatException('Erreur de disque invalide.');
        }
        return DiskSpace(path: value['path'] as String, error: error);
      }
      if (total is! int || free is! int || total <= 0 ||
          free < 0 || free > total) {
        throw const FormatException('Capacite de disque invalide.');
      }
      return DiskSpace(
          path: value['path'] as String, totalBytes: total, freeBytes: free);
    }).toList();
  }
}
