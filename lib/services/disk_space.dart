import 'dart:io';

import 'package:flutter/services.dart';

class DiskSpace {
  const DiskSpace({
    required this.path,
    this.totalBytes,
    this.freeBytes,
    this.error,
    this.ejectable = false,
  });

  final String path;
  final int? totalBytes;
  final int? freeBytes;
  final String? error;

  /// Support amovible, lecteur optique ou disque externe (USB…).
  final bool ejectable;

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
      if (value is! Map ||
          value['path'] is! String ||
          (value['path'] as String).isEmpty) {
        throw const FormatException('Chemin de disque invalide.');
      }
      final total = value['totalBytes'];
      final free = value['freeBytes'];
      final error = value['error'];
      final ejectable = value['ejectable'] ?? false;
      if (ejectable is! bool) {
        throw const FormatException('Indicateur d’éjection invalide.');
      }
      if (error != null) {
        if (error is! String || error.isEmpty) {
          throw const FormatException('Erreur de disque invalide.');
        }
        return DiskSpace(
          path: value['path'] as String,
          error: error,
          ejectable: ejectable,
        );
      }
      if (total is! int ||
          free is! int ||
          total <= 0 ||
          free < 0 ||
          free > total) {
        throw const FormatException('Capacite de disque invalide.');
      }
      return DiskSpace(
        path: value['path'] as String,
        totalBytes: total,
        freeBytes: free,
        ejectable: ejectable,
      );
    }).toList();
  }

  /// Éjecte le disque [path] (retrait sécurisé).
  ///
  /// Lève une [PlatformException] de code `in_use` quand des fichiers du
  /// disque sont encore ouverts.
  static Future<void> eject(String path) =>
      channel.invokeMethod<void>('eject', path);
}
