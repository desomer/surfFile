import 'dart:io';

import 'package:flutter/services.dart';

class PersonalFolders {
  static const channel = MethodChannel('surf_file/personal_folders');
  static const names = [
    'Desktop',
    'Documents',
    'Downloads',
    'Pictures',
    'Music',
    'Videos',
  ];

  static Future<Map<String, String>> resolve(String homePath) async {
    if (!Platform.isWindows) {
      return {
        for (final name in names)
          name:
              '$homePath${homePath.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$name',
      };
    }

    final folders = await channel.invokeMapMethod<String, String>(
      'getPersonalFolders',
    );
    if (folders == null ||
        names.any((name) => folders[name]?.isNotEmpty != true)) {
      throw PlatformException(
        code: 'invalid_personal_folders',
        message: 'Windows a renvoyé des chemins de dossiers incomplets.',
      );
    }
    return folders;
  }
}
